import SwiftUI

// MARK: - Routine Workspace View

struct RoutineWorkspaceView: View {
    enum DetailMode {
        case edit
        case preview
    }

    @StateObject private var store = RoutineStore()
    @StateObject private var previewSession = TransitionPreviewSession()

    @State private var selectedFormationID: UUID?
    @State private var detailMode: DetailMode = .edit
    @State private var previewReferenceMode: PreviewReferenceMode = .intoSelected
    @State private var showingResetConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var renamingFormationID: UUID?
    @State private var formationNameDraft = ""

    private var selectedFormationIndex: Int? {
        store.formationIndex(id: selectedFormationID)
    }

    private var selectedFormation: Formation? {
        guard let selectedFormationIndex else { return nil }
        return store.routine.formations[selectedFormationIndex]
    }

    private func smartPickReferenceMode() -> PreviewReferenceMode {
        guard let selectedFormationIndex else { return .intoSelected }
        if selectedFormationIndex > 0 {
            return .intoSelected
        }
        if selectedFormationIndex < store.routine.formations.count - 1 {
            return .outOfSelected
        }
        return .intoSelected
    }

    private var previewTransitionPair: (start: Formation, end: Formation)? {
        previewReferenceMode.transitionPair(
            in: store.routine.formations,
            selectedIndex: selectedFormationIndex
        )
    }

    private var canSelectPreviousFormation: Bool {
        guard let selectedFormationIndex else { return false }
        return store.routine.formations.indices.contains(selectedFormationIndex - 1)
    }

    private var canSelectNextFormation: Bool {
        guard let selectedFormationIndex else { return false }
        return store.routine.formations.indices.contains(selectedFormationIndex + 1)
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

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            if selectedFormationID == nil {
                selectedFormationID = store.routine.formations.first?.id
            }
            refreshPreviewSession()
        }
        .onChange(of: store.routine.formations) { _, formations in
            if formations.isEmpty {
                selectedFormationID = nil
            } else if let selectedFormationID, formations.contains(where: { $0.id == selectedFormationID }) {
                refreshPreviewSession()
                return
            } else {
                selectedFormationID = formations.first?.id
            }

            refreshPreviewSession()
        }
        .onChange(of: store.routine) { _, _ in
            refreshPreviewSession()
        }
        .onChange(of: selectedFormationID) { _, _ in
            if detailMode == .preview {
                previewReferenceMode = smartPickReferenceMode()
            }
            refreshPreviewSession()
        }
        .onChange(of: detailMode) { _, newMode in
            if newMode == .preview {
                previewReferenceMode = smartPickReferenceMode()
            }
            refreshPreviewSession()
        }
        .onChange(of: previewReferenceMode) { _, _ in
            refreshPreviewSession()
        }
        .confirmationDialog(
            "Reset routine?",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Routine", role: .destructive) {
                store.resetRoutine()
                selectedFormationID = store.routine.formations.first?.id
                detailMode = .edit
                refreshPreviewSession()
            }
        } message: {
            Text("This clears the current routine and starts over with one empty formation.")
        }
        .confirmationDialog(
            "Delete this formation?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Formation", role: .destructive) {
                guard let selectedFormationID else { return }
                store.deleteFormation(id: selectedFormationID)
                self.selectedFormationID = store.routine.formations.first?.id
                refreshPreviewSession()
            }
        } message: {
            Text("This removes the formation and updates adjacent transition previews.")
        }
        .alert("Rename Formation", isPresented: showingRenamePrompt) {
            TextField("Formation name", text: $formationNameDraft)

            Button("Save") {
                commitFormationRename()
            }
            .disabled(formationNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Use the sidebar or toolbar menu to rename formations without covering the floor.")
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        switch detailMode {
        case .edit:
            formationSidebar
        case .preview:
            previewSidebar
        }
    }

    private var formationSidebar: some View {
        List(selection: $selectedFormationID) {
            Section {
                ForEach(store.routine.formations) { formation in
                    HStack(spacing: 12) {
                        FormationThumbnailView(athletes: store.renderedAthletes(for: formation))

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
                    }
                    .tag(formation.id)
                    .contextMenu {
                        Button {
                            beginRenaming(formation)
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }

                        Button {
                            selectedFormationID = store.duplicateFormation(after: formation.id)
                        } label: {
                            Label("Duplicate as Next", systemImage: "plus.square.on.square")
                        }

                        Button(role: .destructive) {
                            selectedFormationID = formation.id
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete Formation", systemImage: "trash")
                        }
                    }
                }
                .onMove { from, to in
                    store.moveFormations(fromOffsets: from, toOffset: to)
                }
            } header: {
                Text(store.routine.name)
            }
        }
        .navigationTitle("Routine")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                EditButton()
                Button {
                    selectedFormationID = store.addFormation(after: selectedFormationID)
                    detailMode = .edit
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

    @ViewBuilder
    private var previewSidebar: some View {
        if let previewTransitionPair, let player = previewSession.player {
            TransitionTransportSidebarView(
                player: player,
                startFormationName: previewTransitionPair.start.name,
                endFormationName: previewTransitionPair.end.name
            )
        } else {
            previewSidebarUnavailable
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if let selectedFormation, let selectedFormationID {
            VStack(spacing: 0) {
                switch detailMode {
                case .edit:
                    FloorGridView(
                        store: store,
                        formationID: selectedFormationID,
                        onDuplicateAsNext: duplicateSelectedFormation
                    )
                case .preview:
                    if let previewTransitionPair, let player = previewSession.player {
                        TransitionPlayerView(
                            store: store,
                            player: player,
                            startFormationID: previewTransitionPair.start.id,
                            endFormationID: previewTransitionPair.end.id,
                            selectedFormationName: selectedFormation.name,
                            previewReferenceMode: $previewReferenceMode,
                            editableEndpoint: previewReferenceMode.editableEndpoint,
                            onSelectPreviousFormation: selectPreviousFormation,
                            onSelectNextFormation: selectNextFormation,
                            canSelectPreviousFormation: canSelectPreviousFormation,
                            canSelectNextFormation: canSelectNextFormation
                        )
                    } else {
                        previewEmptyState
                    }
                }
            }
            .navigationTitle(selectedFormation.name)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) {
                detailToolbar(for: selectedFormation)
            }
        } else {
            ContentUnavailableView("Select a formation", systemImage: "rectangle.grid.1x2")
        }
    }

    private func detailToolbar(for formation: Formation) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                detailModeControl
                Spacer(minLength: 0)
                detailToolbarActions(for: formation)
            }

            VStack(spacing: 10) {
                detailModeControl
                HStack {
                    Spacer(minLength: 0)
                    detailToolbarActions(for: formation)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var detailModeControl: some View {
        HStack(spacing: 0) {
            modeButton(title: "Edit", mode: .edit)
            modeButton(title: "Transition", mode: .preview)
        }
        .padding(4)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func detailToolbarActions(for formation: Formation) -> some View {
        HStack(spacing: 12) {
            Button(action: duplicateSelectedFormation) {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .buttonStyle(.borderedProminent)

            Menu {
                Button {
                    beginRenaming(formation)
                } label: {
                    Label("Rename", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete Formation", systemImage: "trash")
                }

                Divider()

                Button(role: .destructive) {
                    showingResetConfirmation = true
                } label: {
                    Label("Reset Routine", systemImage: "arrow.counterclockwise")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .buttonStyle(.bordered)
        }
    }

    private func modeButton(title: String, mode: DetailMode) -> some View {
        Button {
            detailMode = mode
        } label: {
            Text(title)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(detailMode == mode ? Color.accentColor : Color.clear)
                )
                .foregroundColor(detailMode == mode ? .white : .primary)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .buttonStyle(.plain)
    }

    private var previewSidebarUnavailable: some View {
        ContentUnavailableView(
            "Transport unavailable",
            systemImage: "play.slash",
            description: Text("Choose a formation with a playable preview pair to use transport controls.")
        )
        .navigationTitle("Transport")
    }

    private var previewEmptyState: some View {
        VStack {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "play.slash")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
                Text("No adjacent formation")
                    .font(.title2.weight(.semibold))
                Text("This formation needs a neighbor to show a transition. Add another formation to get started.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button(action: duplicateSelectedFormation) {
                    Label("Duplicate as Next Formation", systemImage: "plus.square.on.square")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(28)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func duplicateSelectedFormation() {
        guard let selectedFormationID else { return }
        self.selectedFormationID = store.duplicateFormation(after: selectedFormationID)
        detailMode = .edit
        refreshPreviewSession()
    }

    private func selectPreviousFormation() {
        guard let selectedFormationIndex, store.routine.formations.indices.contains(selectedFormationIndex - 1) else {
            return
        }
        selectedFormationID = store.routine.formations[selectedFormationIndex - 1].id
    }

    private func selectNextFormation() {
        guard let selectedFormationIndex, store.routine.formations.indices.contains(selectedFormationIndex + 1) else {
            return
        }
        selectedFormationID = store.routine.formations[selectedFormationIndex + 1].id
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

    private func refreshPreviewSession() {
        guard
            detailMode == .preview,
            let previewTransitionPair
        else {
            previewSession.clear()
            return
        }

        previewSession.configure(
            store: store,
            startFormationID: previewTransitionPair.start.id,
            endFormationID: previewTransitionPair.end.id
        )
    }
}

// MARK: - Formation Thumbnail

private struct FormationThumbnailView: View {
    let athletes: [RenderedAthlete]

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
                context.fill(Path(ellipseIn: rect), with: .color(athlete.role.color))
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
}
