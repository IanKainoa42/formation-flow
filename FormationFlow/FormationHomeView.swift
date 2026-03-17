import SwiftUI

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
    @State private var showingDeleteConfirmation = false
    @State private var showingCompactFormationPicker = false
    @State private var renamingFormationID: UUID?
    @State private var formationNameDraft = ""

    private var isCompactLayout: Bool {
        horizontalSizeClass == .compact || UIDevice.current.userInterfaceIdiom == .phone
    }

    private var isPhoneLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
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

    var body: some View {
        Group {
            if isCompactLayout {
                compactWorkspace
            } else {
                regularWorkspace
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
                resetRoutine()
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
                deleteSelectedFormation()
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
            Text("Use the routine list or toolbar menu to rename formations without covering the floor.")
        }
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
            List(selection: $selectedFormationID) {
                Section {
                    ForEach(store.routine.formations) { formation in
                        formationRow(for: formation)
                        .tag(formation.id)
                        .contextMenu {
                            formationContextMenu(for: formation)
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
                Button(action: addFormation) {
                    Image(systemName: "plus")
                }
            }
        }
    }

    private var compactFormationList: some View {
        VStack(spacing: 0) {
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
                    .onMove { from, to in
                        store.moveFormations(fromOffsets: from, toOffset: to)
                    }
                } header: {
                    Text(store.routine.name)
                }
            }

            if !isPhoneLayout, let previewTransitionPair, let player = previewSession.player {
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
                Button(action: addFormation) {
                    Image(systemName: "plus")
                }
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
            formationID: formationID,
            onDuplicateAsNext: duplicateSelectedFormation,
            player: previewSession.player,
            startFormationID: previewTransitionPair?.start.id,
            endFormationID: previewTransitionPair?.end.id
        )

        if compact {
            editor
                .navigationTitle(isPhoneLayout ? "" : formation.name)
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
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        Button(action: duplicateSelectedFormation) {
                            Label("Duplicate", systemImage: "plus.square.on.square")
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
                    Label("Duplicate as Next", systemImage: "plus.square.on.square")
                }

                Divider()

                formationOverflowMenu(for: formation)
            } label: {
                Image(systemName: isPhoneLayout ? "ellipsis.circle.fill" : "ellipsis.circle")
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
                        Image(systemName: "plus")
                    }

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
            Label("Duplicate as Next", systemImage: "plus.square.on.square")
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
            showingDeleteConfirmation = true
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
    }

    // MARK: - Actions

    private func addFormation() {
        let newFormationID = store.addFormation(after: selectedFormationID)
        showFormation(newFormationID)
    }

    private func duplicateFormation(after formationID: UUID) {
        let duplicatedFormationID = store.duplicateFormation(after: formationID)
        showFormation(duplicatedFormationID)
    }

    private func duplicateSelectedFormation() {
        guard let selectedFormationID else { return }
        duplicateFormation(after: selectedFormationID)
    }

    private func deleteSelectedFormation() {
        guard let selectedFormationID else { return }

        let shouldStayInEditor = isCompactLayout && !compactNavigationPath.isEmpty
        store.deleteFormation(id: selectedFormationID)

        if let nextFormationID = store.routine.formations.first?.id {
            showFormation(nextFormationID, pushOnCompact: shouldStayInEditor)
        } else {
            self.selectedFormationID = nil
            compactNavigationPath.removeAll()
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
                .accessibilityLabel("Reset transition")

                Button {
                    player.isPlaying ? player.pause() : player.play()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                Button {
                    player.isLooping.toggle()
                } label: {
                    Image(systemName: "repeat")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .tint(player.isLooping ? .accentColor : .secondary)
                .accessibilityLabel("Toggle loop")
                .accessibilityValue(player.isLooping ? "On" : "Off")
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
