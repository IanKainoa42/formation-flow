import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Routine Workspace View

struct RoutineWorkspaceView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = RoutineStore()
    @StateObject private var previewSession = TransitionPreviewSession()

    @State private var selectedFormationID: UUID?
    // Mirrors selectedFormationID but retains its last non-nil value so the detail
    // pane keeps rendering the active formation when SwiftUI's List clears its
    // selection binding upon entering edit mode (sidebar EditButton).
    @State private var displayedFormationID: UUID?
    @State private var compactNavigationPath: [UUID] = []
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .all
    @State private var previewReferenceMode: PreviewReferenceMode = .intoSelected
    @State private var showingCompactFormationPicker = false
    @State private var renamingFormationID: UUID?
    @State private var formationNameDraft = ""
    @State private var showingRoutineRenamePrompt = false
    @State private var routineNameDraft = ""
    @EnvironmentObject private var entitlementManager: EntitlementManager
    @State private var showingUpgradeSheet = false
    @State private var isFullScreen = false
    @State private var showingRoutinePlayback = false
    @State private var selectedAthleteIDs: Set<UUID> = []
    @State private var isSwapMode = false
    @State private var triggerDeleteAthlete = false
    @State private var isIPadPortrait = false
    @State private var sidebarEditMode: EditMode = .inactive
    // iPad portrait has no sidebar — the selected-athlete inspector opens as a
    // sheet from the bottom transport's edit-path button instead.
    @State private var showingPortraitInspector = false

    private var isCompactLayout: Bool {
        let isPhone: Bool
        #if os(iOS)
        isPhone = UIDevice.current.userInterfaceIdiom == .phone
        #else
        isPhone = false
        #endif
        return horizontalSizeClass == .compact || isPhone
    }

    private var isPhoneLayout: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    private var isPhoneLandscape: Bool {
        isPhoneLayout && verticalSizeClass == .compact
    }

    private var effectiveFormationID: UUID? {
        selectedFormationID ?? displayedFormationID
    }

    private var selectedFormationIndex: Int? {
        store.formationIndex(id: effectiveFormationID)
    }

    private var selectedFormation: Formation? {
        guard let selectedFormationIndex else { return nil }
        return store.routine.formations[selectedFormationIndex]
    }

    /// Returns the currently desired mode, auto-flipping only when the current
    /// selection makes the user's preferred direction unavailable (first or last
    /// formation). Otherwise preserves the user's last choice.
    private func smartPickReferenceMode() -> PreviewReferenceMode {
        if isFirstFormation && !isLastFormation { return .outOfSelected }
        if isLastFormation && !isFirstFormation { return .intoSelected }
        return previewReferenceMode
    }

    private var canPreviewInto: Bool { !isFirstFormation }
    private var canPreviewOutOf: Bool { !isLastFormation }

    /// Flip between editing the transition into vs out of the selected formation,
    /// respecting first/last-formation guards. No-op if only one direction is available.
    private func toggleTransitionDirection() {
        let canInto = canPreviewInto
        let canOut = canPreviewOutOf
        guard canInto && canOut else { return }
        previewReferenceMode = (previewReferenceMode == .intoSelected) ? .outOfSelected : .intoSelected
    }

    private var previewTransitionPair: (start: Formation, end: Formation)? {
        previewReferenceMode.transitionPair(
            in: store.routine.formations,
            selectedIndex: selectedFormationIndex
        )
    }

    private var showingRenamePrompt: Binding<Bool> {
        Binding(
            get: { renamingFormationID != nil },
            set: { isPresented in
                if !isPresented {
                    renamingFormationID = nil
                    formationNameDraft = ""
                }
            }
        )
    }

    private var canAddFormation: Bool {
        // Pro users can add unlimited formations
        if entitlementManager.isPro {
            return true
        }
        // Free users can have up to 2 formations
        return store.routine.formations.count < FreeTierLimits.maxFormations
    }

    /// Free tier may only open/edit the first `maxFormations`; any beyond that
    /// (e.g. created while Pro, then downgraded) are Pro-locked but kept on disk —
    /// never deleted. Returns true if this formation should be gated for free users.
    private func isFormationLocked(_ formationID: UUID) -> Bool {
        guard !entitlementManager.isPro else { return false }
        guard let index = store.formationIndex(id: formationID) else { return false }
        return index >= FreeTierLimits.maxFormations
    }

    @ViewBuilder
    private var transitionDirectionPicker: some View {
        let canInto = canPreviewInto
        let canOut = canPreviewOutOf
        if canInto || canOut {
            Picker("Transition focus", selection: Binding(
                get: { previewReferenceMode },
                set: { newMode in
                    switch newMode {
                    case .intoSelected:
                        if canInto { previewReferenceMode = .intoSelected }
                    case .outOfSelected:
                        if canOut { previewReferenceMode = .outOfSelected }
                    }
                }
            )) {
                Text("Into").tag(PreviewReferenceMode.intoSelected)
                    .accessibilityLabel("Transition into selected formation")
                Text("Out of").tag(PreviewReferenceMode.outOfSelected)
                    .accessibilityLabel("Transition out of selected formation")
            }
            .pickerStyle(.segmented)
            .disabled(!(canInto && canOut))
            .accessibilityLabel("Transition focus")
            .accessibilityHint("Choose whether to edit the transition into or out of the selected formation")
            .help("Switch between editing the transition into vs out of the selected formation")
        }
    }

    @ViewBuilder
    private var workspaceContent: some View {
        if isFullScreen && !isCompactLayout {
            if let selectedFormationID {
                fullScreenFloor(formationID: selectedFormationID)
            } else {
                regularWorkspace
            }
        } else if isCompactLayout {
            compactWorkspace
        } else if isIPadPortrait {
            iPadPortraitWorkspace
        } else {
            regularWorkspace
        }
    }

    // iPad portrait drops the formation sidebar entirely (and with it the
    // split-view reveal toggle): the floating pip badge handles formation
    // nav + rename, and the bottom transport's edit-path button opens the
    // athlete inspector as a sheet.
    private var iPadPortraitWorkspace: some View {
        NavigationStack {
            regularDetailView
        }
        .sheet(isPresented: $showingPortraitInspector) {
            portraitInspectorSheet
        }
        .onChange(of: selectedAthleteIDs) { _, ids in
            if ids.isEmpty { showingPortraitInspector = false }
        }
    }

    @ViewBuilder
    private var portraitInspectorSheet: some View {
        if let selectedFormationID, let player = previewSession.player {
            NavigationStack {
                SelectedAthleteSidebarView(
                    store: store,
                    formationID: selectedFormationID,
                    selectedAthleteIDs: $selectedAthleteIDs,
                    onDeleteAthlete: { triggerDeleteAthlete = true },
                    player: player,
                    startFormationID: previewTransitionPair?.start.id,
                    endFormationID: previewTransitionPair?.end.id,
                    isPro: entitlementManager.isPro,
                    onUpgrade: { showingUpgradeSheet = true },
                    onRefreshTransition: { refreshPreviewSession() },
                    onSwap: { isSwapMode.toggle() },
                    isSwapMode: isSwapMode,
                    isIPadPortrait: true
                )
                .navigationTitle("Athlete")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showingPortraitInspector = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    var body: some View {
        workspaceContent
        .background {
            GeometryReader { geo in
                Color.clear.onChange(of: geo.size) { _, size in
                    isIPadPortrait = !isPhoneLayout && size.height > size.width
                }
                .onAppear {
                    isIPadPortrait = !isPhoneLayout && geo.size.height > geo.size.width
                }
            }
        }
        .onChange(of: isIPadPortrait) { _, portrait in
            // Portrait gives the floor full width by collapsing the sidebar;
            // landscape restores the split so the sidebar transport is reachable.
            withAnimation(.easeInOut(duration: 0.22)) {
                splitViewVisibility = portrait ? .detailOnly : .all
            }
        }
        .onAppear {
            if selectedFormationID == nil {
                selectedFormationID = store.routine.formations.first?.id
            }
            previewReferenceMode = smartPickReferenceMode()
            refreshPreviewSession()
        }
        .onChange(of: store.routine.formations) { _, formations in
            reconcileSelection(with: formations)
            refreshPreviewSession()
        }
        .onChange(of: store.workspace.activeRoutineID) { _, _ in
            selectedAthleteIDs = []
            isSwapMode = false
            triggerDeleteAthlete = false
            previewReferenceMode = smartPickReferenceMode()
            refreshPreviewSession()
        }
        .onChange(of: selectedFormationID) { old, new in
            // Free tier: formations beyond the cap are Pro-locked. Don't open them —
            // revert to the prior selection and surface the upgrade sheet.
            if let new, isFormationLocked(new) {
                selectedFormationID = old
                showingUpgradeSheet = true
                return
            }
            if let new {
                displayedFormationID = new
            }
            selectedAthleteIDs = []
            isSwapMode = false
            previewReferenceMode = smartPickReferenceMode()
            refreshPreviewSession()
        }
        .onChange(of: previewReferenceMode) { _, _ in
            selectedAthleteIDs = []
            isSwapMode = false
            refreshPreviewSession()
        }
        .alert("Rename Formation", isPresented: showingRenamePrompt) {
            TextField("Formation name", text: $formationNameDraft)

            Button("Save") {
                commitFormationRename()
            }
            .disabled(formationNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Use the routine list or toolbar menu to rename formations without covering the floor.")
        }
        .alert("Rename Routine", isPresented: $showingRoutineRenamePrompt) {
            TextField("Routine name", text: $routineNameDraft)

            Button("Save") {
                commitRoutineRename()
            }
            .disabled(routineNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a new name for this routine.")
        }
        .sheet(isPresented: $showingUpgradeSheet) {
            ProUpgradeSheet()
                .environmentObject(entitlementManager)
        }
        .fullScreenCover(isPresented: $showingRoutinePlayback) {
            RoutinePlaybackView(store: store)
                .environmentObject(entitlementManager)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                store.saveNow()
            }
        }
    }

    // MARK: - Full Screen Floor

    private func fullScreenFloor(formationID: UUID) -> some View {
        VStack(spacing: 0) {
            FloorGridView(
                store: store,
                selectedAthleteIDs: $selectedAthleteIDs,
                isSwapMode: $isSwapMode,
                triggerDeleteAthlete: $triggerDeleteAthlete,
                formationID: formationID,
                onCycleFormation: cycleToNextFormation,
                onCyclePreviousFormation: stepToPreviousFormation,
                isFirstFormation: isFirstFormation,
                isLastFormation: isLastFormation,
                hideFormationContextBadge: true,
                onDuplicateAsNext: duplicateSelectedFormation,
                player: previewSession.player,
                startFormationID: previewTransitionPair?.start.id,
                endFormationID: previewTransitionPair?.end.id,
                onToggleTransitionDirection: toggleTransitionDirection,
                onBootstrapFromAthlete: { athleteID, liftPoint, waypoints in
                    bootstrapTransition(fromFormationID: formationID, athleteID: athleteID, liftPoint: liftPoint, waypoints: waypoints)
                }
            )
            .overlay(alignment: .topTrailing) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isFullScreen = false
                    }
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Exit full screen")
                .accessibilityHint("Restores the standard interface layout")
                .help("Exit full screen")
                .padding(.top, 64)
                .padding(.trailing, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let previewTransitionPair, let player = previewSession.player {
                ThinTransitionTransportBar(
                    player: player,
                    startFormationName: previewTransitionPair.start.name,
                    endFormationName: previewTransitionPair.end.name,
                    onSwap: { isSwapMode.toggle() },
                    isSwapMode: isSwapMode,
                    canSwap: selectedAthleteIDs.count == 1,
                    canEditPath: selectedAthleteIDs.count == 1,
                    onPreviousFormation: stepToPreviousFormation,
                    onNextFormation: stepToNextFormation,
                    isFirstFormation: isFirstFormation,
                    isLastFormation: isLastFormation
                )
            }
        }
        .environmentObject(entitlementManager)
        .ignoresSafeArea()
        .statusBarHidden()
    }

    // MARK: - Workspace Shell

    private var regularWorkspace: some View {
        NavigationSplitView(columnVisibility: $splitViewVisibility) {
            regularSidebar
        } detail: {
            regularDetailView
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var compactWorkspace: some View {
        NavigationStack(path: $compactNavigationPath) {
            compactFormationList
                .navigationDestination(for: UUID.self) { formationID in
                    compactDetailView(for: formationID)
                }
        }
        // Lists/navigation stay portrait on iPhone; the floor editor flips to
        // landscape on its own (see detailContent). iPad is never constrained.
        .onAppear {
            if isPhoneLayout { OrientationLock.set(.portrait) }
        }
    }

    /// Shown over the floor editor on iPhone while the device is still portrait
    /// (e.g. rotation hasn't completed, or the user has rotation lock on). The
    /// editor itself forces landscape, so this is a brief/fallback state.
    private var rotateToEditPrompt: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "rotate.right.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text("Rotate to edit")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("The floor opens in landscape so the full court fits.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
            .padding(32)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rotate your phone to landscape to edit the floor")
    }

    // MARK: - Sidebar

    private var regularSidebar: some View {
        VStack(spacing: 0) {
            if !selectedAthleteIDs.isEmpty, let selectedFormationID,
               let player = previewSession.player {
                SelectedAthleteSidebarView(
                    store: store,
                    formationID: selectedFormationID,
                    selectedAthleteIDs: $selectedAthleteIDs,
                    onDeleteAthlete: { triggerDeleteAthlete = true },
                    player: player,
                    startFormationID: previewTransitionPair?.start.id,
                    endFormationID: previewTransitionPair?.end.id,
                    onUpgrade: { showingUpgradeSheet = true },
                    onRefreshTransition: { refreshPreviewSession() },
                    onSwap: { isSwapMode.toggle() },
                    isSwapMode: isSwapMode,
                    isIPadPortrait: isIPadPortrait
                )
            } else if !selectedAthleteIDs.isEmpty, let selectedFormationID {
                // Single formation — no player, show basic inspector
                SidebarInspectorView(
                    store: store,
                    formationID: selectedFormationID,
                    selectedAthleteIDs: $selectedAthleteIDs,
                    onDeleteAthlete: { triggerDeleteAthlete = true },
                    onUpgrade: { showingUpgradeSheet = true }
                )
                Spacer()
            } else {
                if store.routine.formations.isEmpty {
                    emptyFormationListView
                } else {
                    List(selection: $selectedFormationID) {
                        Section {
                            ForEach(store.routine.formations) { formation in
                                formationRow(for: formation)
                                .tag(formation.id)
                                .contextMenu {
                                    formationContextMenu(for: formation)
                                }
                            }
                            .onDelete { offsets in
                                requestFormationDeletion(offsets.map { store.routine.formations[$0].id })
                            }
                            .onMove { from, to in
                                store.moveFormations(fromOffsets: from, toOffset: to)
                            }
                        } header: {
                            routinePickerMenu
                        }
                    }
                }

                if !isIPadPortrait, let previewTransitionPair, let player = previewSession.player {
                    Divider()
                    VStack(spacing: 12) {
                        // Into/Out toggle now lives on the formation pip badge.
                        SidebarTransportView(
                            player: player,
                            startFormationName: previewTransitionPair.start.name,
                            endFormationName: previewTransitionPair.end.name,
                            onSwap: { isSwapMode.toggle() },
                            isSwapMode: isSwapMode,
                            canSwap: selectedAthleteIDs.count == 1,
                            canEditPath: selectedAthleteIDs.count == 1,
                            onPreviousFormation: stepToPreviousFormation,
                            onNextFormation: stepToNextFormation,
                            isFirstFormation: isFirstFormation,
                            isLastFormation: isLastFormation,
                            onAdjustCounts: { setPreviewCounts($0) },
                            countsLocked: !entitlementManager.isPro,
                            onLockedCounts: { showingUpgradeSheet = true }
                        )
                    }
                    .padding(16)
                    .background(.thinMaterial)
                    .layoutPriority(1)
                } else if !isIPadPortrait, store.routine.formations.count == 1 {
                    Divider()
                    singleFormationTransitionHint
                        .padding(16)
                        .background(.thinMaterial)
                        .layoutPriority(1)
                }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: selectedAthleteIDs.isEmpty)
        .navigationTitle(selectedAthleteIDs.isEmpty ? "Routine" : "Athlete")
        .toolbar {
            if selectedAthleteIDs.isEmpty {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    EditButton()
                    Button(action: addFormation) {
                        LockBadgedToolbarIcon(icon: "plus")
                    }
                    .accessibilityLabel(canAddFormation ? "Add formation" : "Upgrade to Pro to add formation")
                }
            }
        }
        .environment(\.editMode, $sidebarEditMode)
        .onChange(of: sidebarEditMode) { _, newValue in
            if newValue == .inactive, selectedFormationID == nil, let displayedFormationID {
                selectedFormationID = displayedFormationID
            }
        }
    }

    private var compactFormationList: some View {
        VStack(spacing: 0) {
            if store.routine.formations.isEmpty {
                emptyFormationListView
            } else {
                List {
                    Section {
                        ForEach(store.routine.formations) { formation in
                            Button {
                                showFormation(formation.id)
                            } label: {
                                formationRow(for: formation, showsDisclosure: true)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                formationContextMenu(for: formation)
                            }
                        }
                        .onDelete { offsets in
                            requestFormationDeletion(offsets.map { store.routine.formations[$0].id })
                        }
                        .onMove { from, to in
                            store.moveFormations(fromOffsets: from, toOffset: to)
                        }
                    } header: {
                        routinePickerMenu
                    }
                }
            }

            if !isPhoneLayout, let previewTransitionPair, let player = previewSession.player {
                Divider()
                // Into/Out toggle now lives on the formation pip badge.
                SidebarTransportView(
                    player: player,
                    startFormationName: previewTransitionPair.start.name,
                    endFormationName: previewTransitionPair.end.name,
                    onSwap: { isSwapMode.toggle() },
                    isSwapMode: isSwapMode,
                    canSwap: selectedAthleteIDs.count == 1,
                    canEditPath: selectedAthleteIDs.count == 1,
                    onPreviousFormation: stepToPreviousFormation,
                    onNextFormation: stepToNextFormation,
                    isFirstFormation: isFirstFormation,
                    isLastFormation: isLastFormation,
                    onAdjustCounts: { setPreviewCounts($0) },
                    countsLocked: !entitlementManager.isPro,
                    onLockedCounts: { showingUpgradeSheet = true }
                )
                .padding(16)
                .background(.thinMaterial)
            } else if !isPhoneLayout, store.routine.formations.count == 1 {
                Divider()
                singleFormationTransitionHint
                    .padding(16)
                    .background(.thinMaterial)
            }
        }
        .navigationTitle("Routine")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    attemptRoutinePlayback()
                } label: {
                    LockBadgedToolbarIcon(icon: "play.circle")
                }
                .disabled(store.routine.formations.count < 2)
                .accessibilityLabel(entitlementManager.isPro ? "Play routine" : "Upgrade to Pro to play routine")
                .help(playbackHelpText)

                EditButton()
                Button(action: addFormation) {
                    LockBadgedToolbarIcon(icon: "plus")
                }
                .accessibilityLabel(canAddFormation ? "Add formation" : "Upgrade to Pro to add formation")
            }
        }
    }

    // MARK: - Detail View

    @ViewBuilder
    private var regularDetailView: some View {
        if let selectedFormation, let formationID = effectiveFormationID {
            detailContent(for: selectedFormation, formationID: formationID, compact: false)
        } else {
            ContentUnavailableView("Select a formation", systemImage: "rectangle.grid.1x2")
        }
    }

    @ViewBuilder
    private func compactDetailView(for formationID: UUID) -> some View {
        if let formation = store.formation(id: formationID) {
            detailContent(for: formation, formationID: formationID, compact: true)
                .onAppear {
                    selectedFormationID = formationID
                }
        } else {
            ContentUnavailableView("Formation unavailable", systemImage: "rectangle.grid.1x2")
        }
    }

    @ViewBuilder
    private func detailContent(for formation: Formation, formationID: UUID, compact: Bool) -> some View {
        let editor = FloorGridView(
            store: store,
            selectedAthleteIDs: $selectedAthleteIDs,
            isSwapMode: $isSwapMode,
            triggerDeleteAthlete: $triggerDeleteAthlete,
            formationID: formationID,
            onCycleFormation: cycleToNextFormation,
            onCyclePreviousFormation: stepToPreviousFormation,
            isFirstFormation: isFirstFormation,
            isLastFormation: isLastFormation,
            onDuplicateAsNext: duplicateSelectedFormation,
            onRenameFormation: { beginRenaming(formation) },
            onDeleteFormation: { requestFormationDeletion([formationID]) },
            onResetRoutine: { resetRoutine() },
            onBack: compact ? { compactNavigationPath.removeAll() } : nil,
            player: previewSession.player,
            startFormationID: previewTransitionPair?.start.id,
            endFormationID: previewTransitionPair?.end.id,
            onToggleTransitionDirection: toggleTransitionDirection,
            onBootstrapFromAthlete: { athleteID, liftPoint, waypoints in
                bootstrapTransition(fromFormationID: formationID, athleteID: athleteID, liftPoint: liftPoint, waypoints: waypoints)
            }
        )

        if compact {
            editor
                .navigationTitle(formation.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(isPhoneLandscape ? .hidden : .automatic, for: .navigationBar)
                .ignoresSafeArea(edges: isPhoneLandscape ? .all : [])
                .statusBarHidden(isPhoneLandscape)
                // The court is wide (72×56) — on a phone it only fills the screen
                // in landscape, so the floor editor forces landscape on iPhone and
                // hands the orientation back to portrait when you leave.
                .overlay {
                    if isPhoneLayout && !isPhoneLandscape {
                        rotateToEditPrompt
                    }
                }
                .onAppear {
                    if isPhoneLayout { OrientationLock.set(.landscape) }
                }
                .onDisappear {
                    if isPhoneLayout { OrientationLock.set(.portrait) }
                }
                .sheet(isPresented: $showingCompactFormationPicker) {
                    compactFormationPickerSheet
                }
                .toolbar {
                    if !isPhoneLandscape {
                        compactDetailToolbar(for: formation)
                    }
                }
        } else {
            editor
                .navigationTitle(formation.name)
                .navigationBarTitleDisplayMode(.inline)
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 8) {
                        if store.routine.formations.count >= 2 {
                            Button {
                                attemptRoutinePlayback()
                            } label: {
                                Image(systemName: entitlementManager.isPro ? "play.fill" : "lock.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            .accessibilityLabel(entitlementManager.isPro ? "Play routine" : "Upgrade to Pro to play routine")
                            .accessibilityHint(entitlementManager.isPro ? "Play the full routine" : "Upgrade to Pro to play the full routine")
                            .help(entitlementManager.isPro ? "Play the full routine" : "Upgrade to Pro to play the full routine")
                        }

                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isFullScreen = true
                            }
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .accessibilityLabel("Enter full screen")
                        .accessibilityHint("Expands the canvas to fill the screen")
                        .help("Enter full screen")
                    }
                    .padding(12)
                }
                .safeAreaInset(edge: .bottom) {
                    if isIPadPortrait, let previewTransitionPair, let player = previewSession.player {
                        VStack(spacing: 10) {
                            // Into/Out toggle now lives on the formation pip badge.
                            SidebarTransportView(
                                player: player,
                                startFormationName: previewTransitionPair.start.name,
                                endFormationName: previewTransitionPair.end.name,
                                onSwap: { isSwapMode.toggle() },
                                onPath: { showingPortraitInspector = true },
                                isSwapMode: isSwapMode,
                                canSwap: selectedAthleteIDs.count == 1,
                                canEditPath: selectedAthleteIDs.count == 1,
                                onPreviousFormation: stepToPreviousFormation,
                                onNextFormation: stepToNextFormation,
                                isFirstFormation: isFirstFormation,
                                isLastFormation: isLastFormation,
                                onAdjustCounts: { setPreviewCounts($0) },
                                countsLocked: !entitlementManager.isPro,
                                onLockedCounts: { showingUpgradeSheet = true }
                            )
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .formationGlassPanel(cornerRadius: 16, shadowRadius: 12)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        Button(action: duplicateSelectedFormation) {
                            Label(
                                canAddFormation ? "Duplicate" : "Duplicate (Pro)",
                                systemImage: canAddFormation ? "plus.square.on.square" : "lock.fill"
                            )
                        }

                        Menu {
                            formationOverflowMenu(for: formation)
                        } label: {
                            Label("More", systemImage: "ellipsis.circle")
                        }
                    }
                }
        }
    }

    @ToolbarContentBuilder
    private func compactDetailToolbar(for formation: Formation) -> some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                showingCompactFormationPicker = true
            } label: {
                Image(systemName: "sidebar.leading")
            }
            .accessibilityLabel("Show formations")
        }

        // On phone, FloorGridView contributes the merged trailing menu — skip here.
        if !isPhoneLayout {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: duplicateSelectedFormation) {
                        Label(
                            canAddFormation ? "Duplicate as Next" : "Duplicate as Next (Pro)",
                            systemImage: canAddFormation ? "plus.square.on.square" : "lock.fill"
                        )
                    }

                    Divider()

                    formationOverflowMenu(for: formation)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More actions")
            }
        }
    }

    private var compactFormationPickerSheet: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.routine.formations) { formation in
                        Button {
                            showingCompactFormationPicker = false
                            showFormation(formation.id)
                        } label: {
                            HStack(spacing: 12) {
                                formationRow(for: formation)

                                if selectedFormationID == formation.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            formationContextMenu(for: formation)
                        }
                    }
                    .onDelete { offsets in
                        requestFormationDeletion(offsets.map { store.routine.formations[$0].id })
                    }
                    .onMove { from, to in
                        store.moveFormations(fromOffsets: from, toOffset: to)
                    }
                } header: {
                    routinePickerMenu
                }
            }
            .navigationTitle("Formations")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: {
                        addFormation()
                        showingCompactFormationPicker = false
                    }) {
                        LockBadgedToolbarIcon(icon: "plus")
                    }
                    .accessibilityLabel(canAddFormation ? "Add formation" : "Upgrade to Pro to add formation")

                    Button("Done") {
                        showingCompactFormationPicker = false
                    }
                }
            }
        }
        .presentationDetents(isPhoneLayout ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func formationRow(for formation: Formation, showsDisclosure: Bool = false) -> some View {
        let index = store.formationIndex(id: formation.id) ?? 0
        let color = TransitionEndpointMarkerRenderItem.rainbowColor(forIndex: index)
        HStack(spacing: 12) {
            FormationListThumbnailView(athletes: store.renderedAthletes(for: formation), color: color)

            VStack(alignment: .leading, spacing: 4) {
                Text(formation.name)
                    .font(.body.weight(.medium))
                Text("\(formation.placements.count) athletes")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !formation.notes.isEmpty {
                Image(systemName: "note.text")
                    .foregroundColor(.secondary)
                    .accessibilityLabel("Has notes")
            }

            if isFormationLocked(formation.id) {
                Image(systemName: "lock.fill")
                    .font(.footnote)
                    .foregroundColor(.orange)
                    .accessibilityLabel("Locked — upgrade to Pro")
            }

            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func formationContextMenu(for formation: Formation) -> some View {
        Button {
            beginRenaming(formation)
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button {
            duplicateFormation(after: formation.id)
        } label: {
            Label(
                canAddFormation ? "Duplicate as Next" : "Duplicate as Next (Pro)",
                systemImage: canAddFormation ? "plus.square.on.square" : "lock.fill"
            )
        }
        
        Divider()
        
        let index = store.formationIndex(id: formation.id) ?? 0
        
        Button {
            store.moveFormationEarlier(id: formation.id)
        } label: {
            Label("Move Earlier", systemImage: "arrow.up")
        }
        .disabled(index == 0)
        .help(index == 0 ? "Already at the first formation" : "Move formation earlier")
        
        Button {
            store.moveFormationLater(id: formation.id)
        } label: {
            Label("Move Later", systemImage: "arrow.down")
        }
        .disabled(index >= store.routine.formations.count - 1)
        .help(index >= store.routine.formations.count - 1 ? "Already at the last formation" : "Move formation later")

        Divider()

        Button(role: .destructive) {
            selectedFormationID = formation.id
            requestFormationDeletion([formation.id])
        } label: {
            Label("Delete Formation", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func formationOverflowMenu(for formation: Formation) -> some View {
        Button {
            beginRenaming(formation)
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        
        Divider()
        
        let index = store.formationIndex(id: formation.id) ?? 0

        Button {
            store.moveFormationEarlier(id: formation.id)
        } label: {
            Label("Move Earlier", systemImage: "arrow.up")
        }
        .disabled(index == 0)
        .help(index == 0 ? "Already at the first formation" : "Move formation earlier")
        
        Button {
            store.moveFormationLater(id: formation.id)
        } label: {
            Label("Move Later", systemImage: "arrow.down")
        }
        .disabled(index >= store.routine.formations.count - 1)
        .help(index >= store.routine.formations.count - 1 ? "Already at the last formation" : "Move formation later")

        Divider()

        Button(role: .destructive) {
            selectedFormationID = formation.id
            requestFormationDeletion([formation.id])
        } label: {
            Label("Delete Formation", systemImage: "trash")
        }

        Divider()

        Button(role: .destructive) {
            resetRoutine()
        } label: {
            Label("Reset Routine", systemImage: "arrow.counterclockwise")
        }
    }


    // MARK: - Empty State Views

    private var emptyFormationListView: some View {
        ContentUnavailableView {
            Label("No Formations", systemImage: "square.stack")
        } description: {
            Text("Tap + to create your first formation.")
        } actions: {
            Button(action: addFormation) {
                Text("Add Formation")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var singleFormationTransitionHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Transitions", systemImage: "arrow.right.arrow.left")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            Text("Add a second formation to preview transitions between them.")
                .font(.caption)
                .foregroundColor(.secondary)

            Button(action: addFormation) {
                Label("Add Formation", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
        }
    }

    // MARK: - Routine Actions

    private var routinePickerMenu: some View {
        Menu {
            Section("Switch Routine") {
                ForEach(store.workspace.routines) { routine in
                    Button {
                        switchRoutine(to: routine.id)
                    } label: {
                        HStack {
                            Text(routine.name)
                            if store.workspace.activeRoutineID == routine.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Section("Actions") {
                Button {
                    routineNameDraft = store.routine.name
                    showingRoutineRenamePrompt = true
                } label: {
                    Label("Rename Routine", systemImage: "pencil")
                }

                Button {
                    duplicateCurrentRoutine()
                } label: {
                    Label(entitlementManager.isPro ? "Duplicate Routine" : "Duplicate Routine (Pro)", systemImage: entitlementManager.isPro ? "plus.square.on.square" : "lock.fill")
                }

                Button(role: .destructive) {
                    deleteCurrentRoutine()
                } label: {
                    Label("Delete Routine", systemImage: "trash")
                }
                .disabled(store.workspace.routines.count <= 1)
                .help(store.workspace.routines.count <= 1 ? "Cannot delete the only routine" : "Delete Routine")
            }

            Section {
                Button {
                    createNewRoutine()
                } label: {
                    Label(entitlementManager.isPro ? "New Routine" : "New Routine (Pro)", systemImage: entitlementManager.isPro ? "plus" : "lock.fill")
                }
            }
        } label: {
            HStack {
                Text(store.routine.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityLabel("Routine Menu")
        .accessibilityValue(store.routine.name)
    }

    private func switchRoutine(to id: UUID) {
        store.switchRoutine(id: id)
        selectedFormationID = store.routine.formations.first?.id
    }

    private func commitRoutineRename() {
        let trimmedName = routineNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        store.renameRoutine(id: store.workspace.activeRoutineID, newName: trimmedName)
        routineNameDraft = ""
    }

    private func duplicateCurrentRoutine() {
        guard entitlementManager.isPro else {
            showingUpgradeSheet = true
            return
        }
        if store.duplicateRoutine(id: store.workspace.activeRoutineID) != nil {
            selectedFormationID = store.routine.formations.first?.id
        }
    }

    private func createNewRoutine() {
        guard entitlementManager.isPro else {
            showingUpgradeSheet = true
            return
        }
        _ = store.addRoutine()
        selectedFormationID = store.routine.formations.first?.id
    }

    private func deleteCurrentRoutine() {
        store.deleteRoutine(id: store.workspace.activeRoutineID)
        selectedFormationID = store.routine.formations.first?.id
    }

    // MARK: - Actions

    private func attemptRoutinePlayback() {
        if entitlementManager.isPro {
            showingRoutinePlayback = true
        } else {
            showingUpgradeSheet = true
        }
    }

    private var playbackHelpText: String {
        if store.routine.formations.count < 2 {
            return "Add at least 2 formations to play the routine"
        }
        if !entitlementManager.isPro {
            return "Upgrade to Pro to play the full routine"
        }
        return "Play the full routine"
    }

    private func addFormation() {
        guard canAddFormation else {
            showingUpgradeSheet = true
            return
        }
        let newFormationID = store.addFormation(after: selectedFormationID)
        showFormation(newFormationID)
    }

    private func duplicateFormation(after formationID: UUID) {
        guard canAddFormation else {
            showingUpgradeSheet = true
            return
        }
        let duplicatedFormationID = store.duplicateFormation(after: formationID)
        showFormation(duplicatedFormationID)
    }

    private func duplicateSelectedFormation() {
        guard let selectedFormationID else { return }
        duplicateFormation(after: selectedFormationID)
    }

    private func cycleToNextFormation() {
        let formations = store.routine.formations
        guard formations.count > 1 else { return }
        let currentIndex = store.formationIndex(id: selectedFormationID) ?? 0
        let nextIndex = (currentIndex + 1) % formations.count
        selectFormation(formations[nextIndex].id)
    }

    private func stepToPreviousFormation() {
        let formations = store.routine.formations
        guard let currentIndex = store.formationIndex(id: selectedFormationID), currentIndex > 0 else { return }
        selectFormation(formations[currentIndex - 1].id)
    }

    private func stepToNextFormation() {
        let formations = store.routine.formations
        guard let currentIndex = store.formationIndex(id: selectedFormationID), currentIndex < formations.count - 1 else { return }
        selectFormation(formations[currentIndex + 1].id)
    }

    /// Advance the displayed formation. On compact (iPhone) the editor is a
    /// pushed `NavigationStack` destination keyed by `compactNavigationPath`, so
    /// mutating `selectedFormationID` alone leaves the pushed editor (and the
    /// formation badge, which reads its fixed `formationID` prop) stuck on the
    /// original formation. Route through `showFormation` so the pushed route
    /// advances in lockstep when the editor is on-screen.
    private func selectFormation(_ formationID: UUID) {
        showFormation(formationID, pushOnCompact: isCompactLayout && !compactNavigationPath.isEmpty)
    }

    private var isFirstFormation: Bool {
        (store.formationIndex(id: selectedFormationID) ?? 0) <= 0
    }

    private var isLastFormation: Bool {
        let formations = store.routine.formations
        guard let idx = store.formationIndex(id: selectedFormationID), !formations.isEmpty else { return true }
        return idx >= formations.count - 1
    }

    private func requestFormationDeletion(_ formationIDs: [UUID]) {
        deleteFormations(ids: formationIDs)
    }

    private func deleteSelectedFormation() {
        guard let selectedFormationID else { return }
        requestFormationDeletion([selectedFormationID])
    }

    private func deleteFormations(ids: [UUID]) {
        let validFormationIDs = ids.reduce(into: [UUID]()) { result, formationID in
            guard store.formationIndex(id: formationID) != nil else { return }
            guard !result.contains(formationID) else { return }
            result.append(formationID)
        }
        guard !validFormationIDs.isEmpty else { return }

        let shouldStayInEditor = isCompactLayout && !compactNavigationPath.isEmpty
        let currentSelection = selectedFormationID

        // Defer to next run loop so any in-flight UICollectionView batch update
        // (e.g. from .onDelete swipe) completes before the data source changes.
        DispatchQueue.main.async {
            for formationID in validFormationIDs {
                store.deleteFormation(id: formationID)
            }

            if let currentSelection, store.formationIndex(id: currentSelection) != nil {
                return
            }

            if let nextFormationID = store.routine.formations.first?.id {
                showFormation(nextFormationID, pushOnCompact: shouldStayInEditor)
            } else {
                selectedFormationID = nil
                compactNavigationPath.removeAll()
            }
        }
    }

    private func resetRoutine() {
        let shouldStayInEditor = isCompactLayout && !compactNavigationPath.isEmpty
        store.resetRoutine()

        if let firstFormationID = store.routine.formations.first?.id {
            showFormation(firstFormationID, pushOnCompact: shouldStayInEditor)
        } else {
            selectedFormationID = nil
            compactNavigationPath.removeAll()
        }
    }

    private func beginRenaming(_ formation: Formation) {
        selectedFormationID = formation.id
        renamingFormationID = formation.id
        formationNameDraft = formation.name
    }

    private func commitFormationRename() {
        guard let renamingFormationID else { return }
        let trimmedName = formationNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        store.mutateFormation(id: renamingFormationID) { formation in
            formation.name = trimmedName
        }

        self.renamingFormationID = nil
        formationNameDraft = ""
    }

    private func showFormation(_ formationID: UUID, pushOnCompact: Bool = true) {
        selectedFormationID = formationID

        guard isCompactLayout, pushOnCompact else { return }

        if compactNavigationPath.last != formationID {
            compactNavigationPath = [formationID]
        }
    }

    private func reconcileSelection(with formations: [Formation]) {
        let validIDs = Set(formations.map(\.id))
        compactNavigationPath.removeAll { !validIDs.contains($0) }

        if let displayedFormationID, !validIDs.contains(displayedFormationID) {
            self.displayedFormationID = nil
        }

        guard !formations.isEmpty else {
            selectedFormationID = nil
            displayedFormationID = nil
            compactNavigationPath.removeAll()
            return
        }

        if let selectedFormationID, validIDs.contains(selectedFormationID) {
            return
        }

        if let firstFormationID = formations.first?.id {
            showFormation(
                firstFormationID,
                pushOnCompact: isCompactLayout && !compactNavigationPath.isEmpty
            )
        }
    }

    private func bootstrapTransition(
        fromFormationID: UUID,
        athleteID: UUID,
        liftPoint: CGPoint,
        waypoints: [PathWaypoint]
    ) {
        guard canAddFormation else {
            showingUpgradeSheet = true
            return
        }
        let newFormationID = store.addFormation(after: fromFormationID)
        store.mutateFormation(id: newFormationID) { formation in
            if let idx = formation.placements.firstIndex(where: { $0.athleteID == athleteID }) {
                formation.placements[idx].position = liftPoint
            }
        }
        store.mutateAthleteTransition(from: fromFormationID, to: newFormationID, athleteID: athleteID) { t in
            t.pathControlPoint = nil
            t.pathWaypoints = waypoints
        }
        previewReferenceMode = .outOfSelected
        refreshPreviewSession()
        store.saveNow()

        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.impactOccurred()
    }

    private func setPreviewCounts(_ newCounts: Int) {
        guard let pair = previewTransitionPair else { return }
        store.mutateTransitionSpec(from: pair.start.id, to: pair.end.id) { spec in
            spec.duration = Double(min(32, max(1, newCounts)))
        }
        refreshPreviewSession()
    }

    private func refreshPreviewSession() {
        guard let previewTransitionPair else {
            previewSession.clear()
            return
        }

        previewSession.configure(
            store: store,
            startFormationID: previewTransitionPair.start.id,
            endFormationID: previewTransitionPair.end.id
        )
    }

    private func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.2)) {
            splitViewVisibility = splitViewVisibility == .detailOnly ? .all : .detailOnly
        }
    }
}

// MARK: - Lock Badge

private struct LockBadgedToolbarIcon: View {
    @EnvironmentObject private var entitlementManager: EntitlementManager
    let icon: String

    var body: some View {
        Image(systemName: icon)
            .overlay(alignment: .bottomTrailing) {
                if !entitlementManager.isPro {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(2)
                        .background(.tint, in: Circle())
                        .offset(x: 5, y: 4)
                }
            }
    }
}

// MARK: - Formation List Thumbnail

private struct FormationListThumbnailView: View {
    let athletes: [RenderedAthlete]
    var color: Color = .white

    var body: some View {
        Canvas { context, size in
            let scaleX = size.width / CourtConstants.width
            let scaleY = size.height / CourtConstants.height
            let radius: CGFloat = 2

            for athlete in athletes {
                let center = CGPoint(
                    x: athlete.position.x * scaleX,
                    y: athlete.position.y * scaleY
                )
                let rect = CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }
        }
        .frame(width: 34, height: 34)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.12))
        )
    }
}

// MARK: - Preview

#Preview {
    RoutineWorkspaceView()
        .environmentObject(EntitlementManager())
}
