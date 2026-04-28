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
    @State private var previewReferenceMode: PreviewReferenceMode = .outOfSelected
    @State private var showingResetConfirmation = false
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
    @State private var showingRoutineDeleteConfirmation = false
    @State private var sidebarEditMode: EditMode = .inactive

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

    private func smartPickReferenceMode() -> PreviewReferenceMode {
        .outOfSelected
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
        entitlementManager.isPro || store.routine.formations.count < FreeTierLimits.maxFormations
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
        } else {
            regularWorkspace
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
        .onChange(of: selectedFormationID) { _, new in
            if let new {
                displayedFormationID = new
            }
            selectedAthleteIDs = []
            isSwapMode = false
            previewReferenceMode = smartPickReferenceMode()
            refreshPreviewSession()
        }
        .confirmationDialog(
            "Reset routine?",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Routine", role: .destructive) {
                resetRoutine()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears the roster, formations, notes, and transition data, then starts over with one empty formation.")
        }
        .confirmationDialog(
            "Delete Routine?",
            isPresented: $showingRoutineDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Routine", role: .destructive) {
                deleteCurrentRoutine()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the routine and all its formations. This cannot be undone.")
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
                endFormationID: previewTransitionPair?.end.id
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
                    isPro: entitlementManager.isPro,
                    onUpgrade: { showingUpgradeSheet = true },
                    onRefreshTransition: { refreshPreviewSession() },
                    onSwap: { isSwapMode.toggle() },
                    isSwapMode: isSwapMode
                )
            } else if !selectedAthleteIDs.isEmpty, let selectedFormationID {
                // Single formation — no player, show basic inspector
                SidebarInspectorView(
                    store: store,
                    formationID: selectedFormationID,
                    selectedAthleteIDs: $selectedAthleteIDs,
                    onDeleteAthlete: { triggerDeleteAthlete = true },
                    isPro: entitlementManager.isPro,
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
                    SidebarTransportView(
                        player: player,
                        startFormationName: previewTransitionPair.start.name,
                        endFormationName: previewTransitionPair.end.name,
                        onSwap: { isSwapMode.toggle() },
                        isSwapMode: isSwapMode,
                        canSwap: selectedAthleteIDs.count == 1,
                        canEditPath: selectedAthleteIDs.count == 1
                    )
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
                        Image(systemName: canAddFormation ? "plus" : "lock.fill")
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
                    isLastFormation: isLastFormation
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
                    showingRoutinePlayback = true
                } label: {
                    Image(systemName: "play.circle")
                }
                .disabled(store.routine.formations.count < 2)
                .accessibilityLabel("Play routine")
                .help(store.routine.formations.count < 2 ? "Add at least 2 formations to play the routine" : "Play the full routine")

                EditButton()
                Button(action: addFormation) {
                    Image(systemName: canAddFormation ? "plus" : "lock.fill")
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
            onResetRoutine: { showingResetConfirmation = true },
            onBack: compact ? { compactNavigationPath.removeAll() } : nil,
            player: previewSession.player,
            startFormationID: previewTransitionPair?.start.id,
            endFormationID: previewTransitionPair?.end.id
        )

        if compact {
            editor
                .navigationTitle(formation.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(isPhoneLandscape ? .hidden : .automatic, for: .navigationBar)
                .ignoresSafeArea(edges: isPhoneLandscape ? .all : [])
                .statusBarHidden(isPhoneLandscape)
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
                                showingRoutinePlayback = true
                            } label: {
                                Image(systemName: "play.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            .accessibilityLabel("Play routine")
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
                    }
                    .padding(12)
                }
                .overlay(alignment: .bottom) {
                    if isIPadPortrait, let previewTransitionPair, let player = previewSession.player {
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
                            isLastFormation: isLastFormation
                        )
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                        Image(systemName: canAddFormation ? "plus" : "lock.fill")
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
            showingResetConfirmation = true
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
            .controlSize(.small)
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
                    showingRoutineDeleteConfirmation = true
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
        selectedFormationID = formations[nextIndex].id
    }

    private func stepToPreviousFormation() {
        let formations = store.routine.formations
        guard let currentIndex = store.formationIndex(id: selectedFormationID), currentIndex > 0 else { return }
        selectedFormationID = formations[currentIndex - 1].id
    }

    private func stepToNextFormation() {
        let formations = store.routine.formations
        guard let currentIndex = store.formationIndex(id: selectedFormationID), currentIndex < formations.count - 1 else { return }
        selectedFormationID = formations[currentIndex + 1].id
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
