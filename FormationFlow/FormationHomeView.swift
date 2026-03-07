import SwiftUI

// MARK: - Routine Workspace View

struct RoutineWorkspaceView: View {
    enum DetailMode {
        case edit
        case preview
    }

    @StateObject private var store = RoutineStore()
    @State private var selectedFormationID: UUID?
    @State private var detailMode: DetailMode = .edit
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

    private var nextFormationID: UUID? {
        guard let selectedFormationIndex, store.routine.formations.indices.contains(selectedFormationIndex + 1)
        else { return nil }
        return store.routine.formations[selectedFormationIndex + 1].id
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
        }
        .onChange(of: store.routine.formations) { _, formations in
            if formations.isEmpty {
                selectedFormationID = nil
                return
            }
            if let selectedFormationID, formations.contains(where: { $0.id == selectedFormationID }) {
                return
            }
            self.selectedFormationID = formations.first?.id
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
                if nextFormationID == nil {
                    detailMode = .edit
                }
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

    private var sidebar: some View {
        List(selection: $selectedFormationID) {
            Section {
                ForEach(store.routine.formations) { formation in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 34, height: 34)
                            .overlay {
                                Image(systemName: "square.grid.2x2")
                                    .foregroundColor(.accentColor)
                            }

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
                    if let nextFormationID {
                        TransitionPlayerView(
                            store: store,
                            startFormationID: selectedFormationID,
                            endFormationID: nextFormationID
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
            modeButton(title: "Edit", mode: .edit, disabled: false)
            modeButton(title: "Preview", mode: .preview, disabled: nextFormationID == nil)
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

    private func modeButton(title: String, mode: DetailMode, disabled: Bool) -> some View {
        Button {
            guard !disabled else { return }
            detailMode = mode
        } label: {
            Text(title)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(detailMode == mode ? Color.accentColor : Color.clear)
                )
                .foregroundColor(
                    disabled
                        ? .secondary
                        : (detailMode == mode ? .white : .primary)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private var previewEmptyState: some View {
        VStack {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "play.slash")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
                Text("Preview needs a next formation")
                    .font(.title2.weight(.semibold))
                Text("Duplicate this formation to create the next picture.")
                    .foregroundColor(.secondary)
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
}

// MARK: - Preview

#Preview {
    RoutineWorkspaceView()
}
