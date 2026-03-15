import SwiftUI

// MARK: - Routine Workspace View

struct RoutineWorkspaceView: View {
    @StateObject private var store = RoutineStore()
    @StateObject private var previewSession = TransitionPreviewSession()

    @State private var selectedFormationID: UUID?
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
            previewReferenceMode = smartPickReferenceMode()
            refreshPreviewSession()
        }
        .onChange(of: store.routine.formations) { _, formations in
            if formations.isEmpty {
                selectedFormationID = nil
            } else if let selectedFormationID, formations.contains(where: { $0.id == selectedFormationID }) {
                // Selection still valid — just refresh preview
            } else {
                selectedFormationID = formations.first?.id
            }

            refreshPreviewSession()
        }
        .onChange(of: selectedFormationID) { _, _ in
            previewReferenceMode = smartPickReferenceMode()
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

    // MARK: - Sidebar

    private var sidebar: some View {
        formationSidebar
    }

    private var formationSidebar: some View {
        VStack(spacing: 0) {
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

            if let previewTransitionPair, let player = previewSession.player {
                Divider()
                SidebarTransportView(
                    player: player,
                    startFormationName: previewTransitionPair.start.name,
                    endFormationName: previewTransitionPair.end.name
                )
                .padding(16)
                .background(.thinMaterial)
            }
        }
        .navigationTitle("Routine")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                EditButton()
                Button {
                    selectedFormationID = store.addFormation(after: selectedFormationID)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

    // MARK: - Detail View

    @ViewBuilder
    private var detailView: some View {
        if let selectedFormation, let selectedFormationID {
            VStack(spacing: 0) {
                FloorGridView(
                    store: store,
                    formationID: selectedFormationID,
                    onDuplicateAsNext: duplicateSelectedFormation,
                    player: previewSession.player,
                    startFormationID: previewTransitionPair?.start.id,
                    endFormationID: previewTransitionPair?.end.id
                )
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
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            detailToolbarActions(for: formation)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
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

    // MARK: - Actions

    private func duplicateSelectedFormation() {
        guard let selectedFormationID else { return }
        self.selectedFormationID = store.duplicateFormation(after: selectedFormationID)
        refreshPreviewSession()
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
}

// MARK: - Sidebar Transport View

private struct SidebarTransportView: View {
    @ObservedObject var player: TransitionPlayer
    let startFormationName: String
    let endFormationName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(startFormationName) \u{2192} \(endFormationName)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                Button(action: player.reset) {
                    Image(systemName: "backward.end.fill")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)

                Button {
                    player.isPlaying ? player.pause() : player.play()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    player.isLooping.toggle()
                } label: {
                    Image(systemName: "repeat")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .tint(player.isLooping ? .accentColor : .secondary)
            }

            Slider(
                value: Binding(
                    get: { player.progress },
                    set: { player.seek(to: $0) }
                ),
                in: 0...1
            )

            HStack {
                Text("Counts")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(TransitionCountFormatting.label(player.counts))
                    .font(.system(.caption, design: .monospaced))
            }
            HStack(spacing: 8) {
                ForEach([4, 8, 16, 32], id: \.self) { count in
                    Button("\(count)") {
                        player.counts = CGFloat(count)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(player.counts == CGFloat(count) ? .accentColor : .secondary)
                }
            }

            Picker("Speed", selection: Binding(
                get: {
                    [CGFloat(0.5), 1.0, 1.5, 2.0]
                        .min(by: { abs($0 - player.speed) < abs($1 - player.speed) }) ?? 1.0
                },
                set: { player.speed = $0 }
            )) {
                Text("0.5x").tag(CGFloat(0.5))
                Text("1x").tag(CGFloat(1.0))
                Text("1.5x").tag(CGFloat(1.5))
                Text("2x").tag(CGFloat(2.0))
            }
            .pickerStyle(.segmented)
        }
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
