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
                detailHeader(for: selectedFormation)
                Divider()

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
        } else {
            ContentUnavailableView("Select a formation", systemImage: "rectangle.grid.1x2")
        }
    }

    private func detailHeader(for formation: Formation) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField(
                        "Formation Name",
                        text: Binding(
                            get: { formation.name },
                            set: { newValue in
                                store.mutateFormation(id: formation.id) { formation in
                                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                    formation.name = trimmed.isEmpty ? formation.name : trimmed
                                }
                            }
                        )
                    )
                    .font(.title2.weight(.semibold))
                    .textFieldStyle(.roundedBorder)

                    Text("\(formation.placements.count) athletes in this picture")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: duplicateSelectedFormation) {
                    Label("Duplicate as Next", systemImage: "plus.square.on.square")
                }
                .buttonStyle(.borderedProminent)

                Menu {
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
                    Label("Routine Actions", systemImage: "ellipsis.circle")
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 0) {
                modeButton(title: "Edit Formation", mode: .edit, disabled: false)
                modeButton(title: "Preview to Next", mode: .preview, disabled: nextFormationID == nil)
            }
            .padding(4)
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.bar)
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
}

// MARK: - Preview

#Preview {
    RoutineWorkspaceView()
}
