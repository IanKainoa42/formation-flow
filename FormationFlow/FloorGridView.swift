import SwiftUI

// MARK: - Navigation Destination

private enum FloorGridDestination: Identifiable, Hashable {
    case transition(Formation)

    var id: String {
        switch self {
        case .transition(let f): return "transition-\(f.id)"
        }
    }
}

// MARK: - Floor Grid View

struct FloorGridView: View {
    private struct CollisionPositionKey: Equatable {
        let id: UUID
        let position: CGPoint
    }

    @StateObject private var persistenceManager = PersistenceManager.shared
    @Environment(\.dismiss) private var dismiss
    @State var formation: Formation
    @State var selectedAthleteId: UUID?
    @State private var showingRenameAlert = false
    @State private var renameText = ""
    @State private var showingManageAthletes = false
    @State private var showingNotes = false
    @State private var showingDeleteFormation = false
    @State private var activeDestination: FloorGridDestination?

    @State private var cachedCollisionIds: Set<UUID> = []
    @State private var cachedCollisionCount: Int = 0

    @State private var isDraggingAthlete = false
    @State private var draggingAthleteIndex: Int?
    @State private var isSwapMode = false
    @State private var swapSourceAthleteId: UUID?
    @State private var dragStartAthletePosition: CGPoint = .zero
    @State private var isPanning = false
    @State private var undoStack: [(id: UUID, position: CGPoint)] = []
    @State private var collisionPositionKey: [CollisionPositionKey] = []

    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero
    @State private var lastZoomScale: CGFloat = 1.0

    var body: some View {
        GeometryReader { geometry in
            canvasStack(geometry: geometry)
        }
        .navigationTitle(formation.name)
        .toolbar {
            #if os(iOS)
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    if cachedCollisionCount > 0 {
                        Label(
                            "\(cachedCollisionCount)", systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundColor(.red)
                        .font(.caption.bold())
                    }
                    Button(action: undoLastMove) {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(undoStack.isEmpty)
                    .accessibilityLabel("Undo last move")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    trailingToolbar
                }
            #else
                ToolbarItemGroup {
                    if cachedCollisionCount > 0 {
                        Label(
                            "\(cachedCollisionCount)", systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundColor(.red)
                        .font(.caption.bold())
                    }
                    Button(action: undoLastMove) {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(undoStack.isEmpty)
                }
                ToolbarItem {
                    trailingToolbar
                }
            #endif
        }
        .onAppear {
            updateCollisionCache(for: formation, force: true)
        }
        .onChange(of: formation) { _, newFormation in
            if !isDraggingAthlete && !isPanning {
                persistenceManager.updateFormation(newFormation)
            }
            updateCollisionCache(for: newFormation)
        }
        .navigationDestination(item: $activeDestination) { dest in
            destinationView(dest)
        }
        .alert("Rename Formation", isPresented: $showingRenameAlert) {
            TextField("Name", text: $renameText)
            Button("Save") {
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    formation.name = trimmed
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a new name for this formation")
        }
        .sheet(isPresented: $showingManageAthletes) {
            manageAthletesSheet
        }
        .sheet(isPresented: $showingNotes) {
            notesSheet
        }
        .confirmationDialog(
            "Delete \"\(formation.name)\"?",
            isPresented: $showingDeleteFormation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                persistenceManager.deleteFormation(id: formation.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete this formation and its \(formation.athletes.count) athletes.")
        }
    }

    // MARK: - Manage Athletes Sheet

    private var manageAthletesSheet: some View {
        NavigationStack {
            List {
                ForEach(formation.athletes) { athlete in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(athlete.role.color)
                            .frame(width: 10, height: 10)
                        Text(athlete.label).font(.body)
                        Text(athlete.role.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onMove { from, to in
                    formation.athletes.move(fromOffsets: from, toOffset: to)
                }
            }
            .navigationTitle("Manage Athletes")
            .toolbar {
                #if os(iOS)
                    ToolbarItem(placement: .navigationBarLeading) { EditButton() }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { showingManageAthletes = false }
                    }
                #else
                    ToolbarItem {
                        Button("Done") { showingManageAthletes = false }
                    }
                #endif
            }
        }
    }

    // MARK: - Notes Sheet

    private var notesSheet: some View {
        NavigationStack {
            TextEditor(text: $formation.notes)
                .padding()
                .navigationTitle("Formation Notes")
                .toolbar {
                    #if os(iOS)
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showingNotes = false }
                        }
                    #else
                        ToolbarItem {
                            Button("Done") { showingNotes = false }
                        }
                    #endif
                }
        }
    }

    // MARK: - Canvas

    private func canvasStack(geometry: GeometryProxy) -> some View {
        let baseCellSize = min(
            geometry.size.width / CourtConstants.width, geometry.size.height / CourtConstants.height
        )
        let cellSize = baseCellSize * zoomScale
        let canvasWidth = CourtConstants.width * cellSize
        let canvasHeight = CourtConstants.height * cellSize
        let offsetX = (geometry.size.width - canvasWidth) / 2 + panOffset.width
        let offsetY = (geometry.size.height - canvasHeight) / 2 + panOffset.height
        let canvasOffset = CGPoint(x: offsetX, y: offsetY)

        return ZStack {
            canvasWithGestures(cellSize: cellSize, canvasOffset: canvasOffset)
            overlays(cellSize: cellSize, canvasOffset: canvasOffset)
        }
    }

    private func canvasWithGestures(cellSize: CGFloat, canvasOffset: CGPoint) -> some View {
        FloorCanvasView(
            formation: formation,
            selectedAthleteId: selectedAthleteId,
            collisionIds: cachedCollisionIds,
            cellSize: cellSize,
            offset: canvasOffset
        )
        .gesture(dragGesture(cellSize: cellSize, canvasOffset: canvasOffset))
        .gesture(
            MagnifyGesture()
                .onChanged { value in zoomScale = max(0.5, min(4.0, lastZoomScale * value.magnification)) }
                .onEnded { _ in lastZoomScale = zoomScale }
        )
        .onTapGesture(count: 2) {
            withAnimation(.spring()) {
                zoomScale = 1.0
                lastZoomScale = 1.0
                panOffset = .zero
                lastPanOffset = .zero
            }
        }
    }

    private func dragGesture(cellSize: CGFloat, canvasOffset: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // Swap mode: tap to swap, no dragging
                if isSwapMode { return }

                if !isDraggingAthlete && !isPanning {
                    let startScaled = CGPoint(
                        x: (value.startLocation.x - canvasOffset.x) / cellSize,
                        y: (value.startLocation.y - canvasOffset.y) / cellSize
                    )
                    var hitAthlete = false
                    for (index, athlete) in formation.athletes.enumerated() {
                        if PathCalculations.squaredDistance(from: startScaled, to: athlete.position)
                            < CourtConstants.hitRadiusSquared
                        {
                            selectedAthleteId = athlete.id
                            isDraggingAthlete = true
                            draggingAthleteIndex = index
                            dragStartAthletePosition = athlete.position
                            hitAthlete = true
                            break
                        }
                    }
                    if !hitAthlete {
                        selectedAthleteId = nil
                        draggingAthleteIndex = nil
                        isPanning = true
                    }
                }

                if isDraggingAthlete,
                    let index = draggingAthleteIndex,
                    formation.athletes.indices.contains(index)
                {
                    let newX = dragStartAthletePosition.x + value.translation.width / cellSize
                    let newY = dragStartAthletePosition.y + value.translation.height / cellSize
                    let newPosition = CGPoint(
                        x: max(0, min(CourtConstants.width, round(newX))),
                        y: max(0, min(CourtConstants.height, round(newY)))
                    )
                    if formation.athletes[index].position != newPosition {
                        formation.athletes[index].position = newPosition
                    }
                } else if isPanning {
                    panOffset = CGSize(
                        width: lastPanOffset.width + value.translation.width,
                        height: lastPanOffset.height + value.translation.height
                    )
                }
            }
            .onEnded { value in
                // Swap mode: handle tap on end
                if isSwapMode, let sourceId = swapSourceAthleteId {
                    let tapScaled = CGPoint(
                        x: (value.location.x - canvasOffset.x) / cellSize,
                        y: (value.location.y - canvasOffset.y) / cellSize
                    )
                    var tappedTarget = false
                    for athlete in formation.athletes {
                        if athlete.id != sourceId,
                            PathCalculations.squaredDistance(from: tapScaled, to: athlete.position)
                                < CourtConstants.hitRadiusSquared
                        {
                            // Record undo for both athletes
                            if let srcIdx = formation.athletes.firstIndex(where: {
                                $0.id == sourceId
                            }) {
                                undoStack.append(
                                    (id: sourceId, position: formation.athletes[srcIdx].position))
                            }
                            undoStack.append((id: athlete.id, position: athlete.position))
                            formation.swapAthletePositions(id1: sourceId, id2: athlete.id)
                            persistenceManager.updateFormation(formation)
                            tappedTarget = true
                            break
                        }
                    }
                    isSwapMode = false
                    swapSourceAthleteId = nil
                    if !tappedTarget { selectedAthleteId = nil }
                    return
                }

                if isPanning { lastPanOffset = panOffset }
                if isDraggingAthlete, let id = selectedAthleteId {
                    undoStack.append((id: id, position: dragStartAthletePosition))
                    persistenceManager.updateFormation(formation)
                }
                isDraggingAthlete = false
                draggingAthleteIndex = nil
                isPanning = false
            }
    }

    @ViewBuilder
    private func overlays(cellSize: CGFloat, canvasOffset: CGPoint) -> some View {
        if formation.athletes.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "figure.stand")
                    .font(.system(size: 60))
                    .foregroundColor(.gray.opacity(0.4))
                Text("Tap + to add athletes")
                    .font(.title3)
                    .foregroundColor(.gray)
            }
            .allowsHitTesting(false)
        }

        // Swap mode banner
        if isSwapMode, let sourceId = swapSourceAthleteId,
            let sourceAthlete = formation.athletes.first(where: { $0.id == sourceId })
        {
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "arrow.triangle.swap")
                    Text("Tap an athlete to swap with \(sourceAthlete.label)")
                        .font(.subheadline.bold())
                    Spacer()
                    Button("Cancel") {
                        isSwapMode = false
                        swapSourceAthleteId = nil
                    }
                    .font(.subheadline)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.blue.opacity(0.15))
                .cornerRadius(10)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }

        if let selectedId = selectedAthleteId, !isSwapMode,
            let index = formation.athletes.firstIndex(where: { $0.id == selectedId })
        {
            AthleteDetailPanel(
                athlete: $formation.athletes[index],
                selectedAthleteId: $selectedAthleteId,
                onDelete: deleteSelectedAthlete,
                onSwap: {
                    swapSourceAthleteId = selectedId
                    isSwapMode = true
                }
            )
            .frame(width: 280)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }

        if zoomScale != 1.0 || panOffset != .zero {
            VStack {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.spring()) {
                            zoomScale = 1.0
                            lastZoomScale = 1.0
                            panOffset = .zero
                            lastPanOffset = .zero
                        }
                    } label: {
                        Label("Reset View", systemImage: "arrow.counterclockwise")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 8)
                }
                Spacer()
            }
        }

        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: addAthlete) {
                    Image(systemName: "plus")
                        .font(.title2.bold())
                        .frame(width: 48, height: 48)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
                .accessibilityLabel("Add athlete")
                .padding(.trailing, 24)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Toolbar

    private var trailingToolbar: some View {
        HStack(spacing: 12) {
            Button(action: { activeDestination = .transition(formation) }) {
                Image(systemName: "arrow.right.circle")
            }
            .accessibilityLabel("Transitions")
            .disabled(persistenceManager.formations.count < 2)

            Menu {
                Button(action: {
                    renameText = formation.name
                    showingRenameAlert = true
                }) {
                    Label("Rename", systemImage: "pencil")
                }
                Button(action: duplicateFormation) {
                    Label("Duplicate", systemImage: "doc.on.doc")
                }
                Button(action: { showingNotes = true }) {
                    Label("Notes", systemImage: "note.text")
                }
                Button(action: { showingManageAthletes = true }) {
                    Label("Manage Athletes", systemImage: "list.bullet")
                }
                Divider()
                Button(role: .destructive, action: { showingDeleteFormation = true }) {
                    Label("Delete Formation", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More options")
        }
    }

    // MARK: - Navigation

    @ViewBuilder
    private func destinationView(_ dest: FloorGridDestination) -> some View {
        switch dest {
        case .transition(let f):
            TransitionPickerView(startFormation: f)
        }
    }

    // MARK: - Actions

    private func updateCollisionCache(for formation: Formation, force: Bool = false) {
        let newKey = formation.athletes.map { athlete in
            CollisionPositionKey(id: athlete.id, position: athlete.position)
        }
        guard force || newKey != collisionPositionKey else { return }
        collisionPositionKey = newKey

        let summary = PathCalculations.collisionSummary(in: formation, minDistance: 2.0)
        cachedCollisionCount = summary.count
        cachedCollisionIds = summary.ids
    }

    private func addAthlete() {
        let existingLabels = Set(formation.athletes.map { $0.label })
        var count = formation.athletes.count + 1
        var label = "P\(count)"
        while existingLabels.contains(label) {
            count += 1
            label = "P\(count)"
        }

        // Grid layout: 8 per row, 6 ft spacing, starting at (4, 4)
        // so athletes don't spawn stacked on each other.
        let col = formation.athletes.count % 8
        let row = formation.athletes.count / 8
        let spawnX = min(CourtConstants.width - 2, 4.0 + CGFloat(col) * 6.0)
        let spawnY = min(CourtConstants.height - 2, 4.0 + CGFloat(row) * 6.0)

        let newAthlete = Athlete(label: label, position: CGPoint(x: spawnX, y: spawnY))
        formation.addAthlete(newAthlete)
        selectedAthleteId = newAthlete.id
    }

    private func undoLastMove() {
        guard let last = undoStack.popLast(),
            let index = formation.athletes.firstIndex(where: { $0.id == last.id })
        else { return }
        formation.athletes[index].position = last.position
    }

    private func deleteSelectedAthlete() {
        guard let id = selectedAthleteId else { return }
        formation.removeAthlete(id: id)
        undoStack.removeAll { $0.id == id }
        selectedAthleteId = nil
    }

    private func duplicateFormation() {
        var duplicate = formation
        duplicate.id = UUID()
        duplicate.name = "\(formation.name) (Copy)"
        persistenceManager.addFormation(duplicate)
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        FloorGridView(formation: Formation.sample())
    }
}
