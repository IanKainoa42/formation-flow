import SwiftUI
import LocalAuthentication
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Routine Workspace View

struct RoutineWorkspaceView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var store = RoutineStore()
    @StateObject private var previewSession = TransitionPreviewSession()

    @State private var selectedFormationID: UUID?
    @State private var compactNavigationPath: [UUID] = []
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .all
    @State private var previewReferenceMode: PreviewReferenceMode = .outOfSelected
    @State private var showingResetConfirmation = false
    @State private var pendingFormationDeleteIDs: [UUID] = []
    @State private var showingCompactFormationPicker = false
    @State private var renamingFormationID: UUID?
    @State private var formationNameDraft = ""
    @EnvironmentObject private var entitlementManager: EntitlementManager
    @State private var showingUpgradeSheet = false
    @State private var isFullScreen = false
    @State private var showingRoutinePlayback = false
    @State private var selectedAthleteIDs: Set<UUID> = []
    @State private var isSwapMode = false
    @State private var triggerDeleteAthlete = false

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

    private var selectedFormationIndex: Int? {
        store.formationIndex(id: selectedFormationID)
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

    private var showingFormationDeleteConfirmation: Binding<Bool> {
        Binding(
            get: { !pendingFormationDeleteIDs.isEmpty },
            set: { isPresented in
                if !isPresented {
                    pendingFormationDeleteIDs = []
                }
            }
        )
    }

    private var canAddFormation: Bool {
        entitlementManager.isPro || store.routine.formations.count < FreeTierLimits.maxFormations
    }

    private var deleteConfirmationTitle: String {
        "Delete \(pendingFormationDeleteIDs.count == 1 ? "this formation" : "these formations")?"
    }
    
    private var deleteButtonTitle: String {
        pendingFormationDeleteIDs.count == 1 ? "Delete Formation" : "Delete Formations"
    }
    
    private var deleteConfirmationMessage: String {
        pendingFormationDeleteIDs.count == 1
            ? "This removes the formation and any transition data connected to it. This cannot be undone."
            : "This removes the selected formations and any transition data connected to them. This cannot be undone."
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
        .onChange(of: selectedFormationID) { _, _ in
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
                authenticateAndResetRoutine()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears the roster, formations, notes, and transition data, then starts over with one empty formation.")
        }
        .confirmationDialog(
            deleteConfirmationTitle,
            isPresented: showingFormationDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(deleteButtonTitle, role: .destructive) {
                deletePendingFormations()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteConfirmationMessage)
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
        .sheet(isPresented: $showingUpgradeSheet) {
            ProUpgradeSheet()
                .environmentObject(entitlementManager)
        }
        .fullScreenCover(isPresented: $showingRoutinePlayback) {
            RoutinePlaybackView(store: store)
                .environmentObject(entitlementManager)
        }
    }

    // MARK: - Full Screen Floor

    private func fullScreenFloor(formationID: UUID) -> some View {
        FloorGridView(
            store: store,
            selectedAthleteIDs: $selectedAthleteIDs,
            isSwapMode: $isSwapMode,
            triggerDeleteAthlete: $triggerDeleteAthlete,
            formationID: formationID,
            onCycleFormation: cycleToNextFormation,
            onDuplicateAsNext: duplicateSelectedFormation,
            player: previewSession.player,
            startFormationID: previewTransitionPair?.start.id,
            endFormationID: previewTransitionPair?.end.id
        )
        .overlay(alignment: .topLeading) {
            HStack(spacing: 10) {
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

                if store.routine.formations.count >= 2 {
                    Button {
                        showingRoutinePlayback = true
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.body.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
            }
            .padding(16)
        }
        .overlay(alignment: .bottom) {
            if let previewTransitionPair, let player = previewSession.player {
                CompactTransitionPlaybackOverlayView(
                    player: player,
                    startFormationName: previewTransitionPair.start.name,
                    endFormationName: previewTransitionPair.end.name,
                    onSwap: { isSwapMode.toggle() },
                    isSwapMode: isSwapMode,
                    canSwap: selectedAthleteIDs.count == 1,
                    canEditPath: selectedAthleteIDs.count == 1
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
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
                        Text(store.routine.name)
                    }
                }
            }

            if let previewTransitionPair, let player = previewSession.player {
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
            } else if store.routine.formations.count == 1 {
                Divider()
                singleFormationTransitionHint
                    .padding(16)
                    .background(.thinMaterial)
            }

            if !selectedAthleteIDs.isEmpty, let selectedFormationID {
                Divider()
                SidebarInspectorView(
                    store: store,
                    formationID: selectedFormationID,
                    selectedAthleteIDs: $selectedAthleteIDs,
                    onDeleteAthlete: {
                        triggerDeleteAthlete = true
                    }
                )
                .frame(minHeight: 200, maxHeight: 400)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: selectedAthleteIDs.isEmpty)
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

                EditButton()
                Button(action: addFormation) {
                    Image(systemName: canAddFormation ? "plus" : "lock.fill")
                }
                .accessibilityLabel(canAddFormation ? "Add formation" : "Upgrade to Pro to add formation")
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
                        Text(store.routine.name)
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
                    canEditPath: selectedAthleteIDs.count == 1
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
        if let selectedFormation, let selectedFormationID {
            detailContent(for: selectedFormation, formationID: selectedFormationID, compact: false)
        } else {
            ContentUnavailableView("Select a formation", systemImage: "rectangle.grid.1x2")
        }
    }

    @ViewBuilder
    private func compactDetailView(for formationID: UUID) -> some View {
        if let formation = store.routine.formations.first(where: { $0.id == formationID }) {
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
            onDuplicateAsNext: duplicateSelectedFormation,
            player: previewSession.player,
            startFormationID: previewTransitionPair?.start.id,
            endFormationID: previewTransitionPair?.end.id
        )

        if compact {
            editor
                .navigationTitle(formation.name)
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showingCompactFormationPicker) {
                    compactFormationPickerSheet
                }
                .toolbar {
                    compactDetailToolbar(for: formation)
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
                    }
                    .padding(12)
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
                Image(systemName: isPhoneLayout ? "ellipsis.circle.fill" : "ellipsis.circle")
            }
            .accessibilityLabel("More actions")
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
                    Text(store.routine.name)
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
        let index = store.routine.formations.firstIndex(where: { $0.id == formation.id }) ?? 0
        let color = TransitionEndpointMarkerRenderItem.rainbowColor(forIndex: index)
        return HStack(spacing: 12) {
            FormationThumbnailView(athletes: store.renderedAthletes(for: formation), color: color)

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
        
        Button {
            store.moveFormationLater(id: formation.id)
        } label: {
            Label("Move Later", systemImage: "arrow.down")
        }
        .disabled(index >= store.routine.formations.count - 1)

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
        
        Button {
            store.moveFormationLater(id: formation.id)
        } label: {
            Label("Move Later", systemImage: "arrow.down")
        }
        .disabled(index >= store.routine.formations.count - 1)

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
        let currentIndex = formations.firstIndex(where: { $0.id == selectedFormationID }) ?? 0
        let nextIndex = (currentIndex + 1) % formations.count
        selectedFormationID = formations[nextIndex].id
    }

    private func requestFormationDeletion(_ formationIDs: [UUID]) {
        pendingFormationDeleteIDs = formationIDs.reduce(into: [UUID]()) { result, formationID in
            guard store.formationIndex(id: formationID) != nil else { return }
            guard !result.contains(formationID) else { return }
            result.append(formationID)
        }
    }

    private func deletePendingFormations() {
        let formationIDs = pendingFormationDeleteIDs
        pendingFormationDeleteIDs = []
        deleteFormations(ids: formationIDs)
    }

    private func deleteSelectedFormation() {
        guard let selectedFormationID else { return }
        deleteFormations(ids: [selectedFormationID])
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

    private func authenticateAndResetRoutine() {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Authenticate to reset the routine") { success, _ in
                DispatchQueue.main.async {
                    if success {
                        resetRoutine()
                    }
                }
            }
        } else if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Authenticate to reset the routine") { success, _ in
                DispatchQueue.main.async {
                    if success {
                        resetRoutine()
                    }
                }
            }
        } else {
            resetRoutine()
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

        guard !formations.isEmpty else {
            selectedFormationID = nil
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

// MARK: - Formation Thumbnail

private struct FormationThumbnailView: View {
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
