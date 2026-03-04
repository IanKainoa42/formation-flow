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
    @State var selectedAthleteIds: Set<UUID> = []
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
    @State private var dragStartPositions: [UUID: CGPoint] = [:]  // For group move
    @State private var isPanning = false
    @State private var isDrawingSelectionBox = false
    @State private var selectionRect: CGRect? = nil
    @State private var selectionStartPoint: CGPoint = .zero
    @State private var undoStack: [[(id: UUID, position: CGPoint)]] = []  // Group undo
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
                        Button(action: selectNextCollidingAthlete) {
                            Label(
                                "\(cachedCollisionCount)",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .foregroundColor(.red)
                            .font(.caption.bold())
                        }
                        .accessibilityLabel(
                            "Cycle through \(cachedCollisionCount) colliding athletes")
                        .help("\(cachedCollisionCount) athletes are within 2ft of each other. Tap to cycle through them.")
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
                        Button(action: selectNextCollidingAthlete) {
                            Label(
                                "\(cachedCollisionCount)",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .foregroundColor(.red)
                            .font(.caption.bold())
                        }
                        .accessibilityLabel(
                            "Cycle through \(cachedCollisionCount) colliding athletes")
                        .help("\(cachedCollisionCount) athletes are within 2ft of each other. Tap to cycle through them.")
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
            Text(
                "This will permanently delete this formation and its \(formation.athletes.count) athletes."
            )
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
            selectedAthleteIds: selectedAthleteIds,
            collisionIds: cachedCollisionIds,
            cellSize: cellSize,
            offset: canvasOffset,
            swapSourceId: swapSourceAthleteId,
            selectionRect: selectionRect
        )
        .gesture(dragGesture(cellSize: cellSize, canvasOffset: canvasOffset))
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    zoomScale = max(0.5, min(4.0, lastZoomScale * value.magnification))
                }
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

                if !isDraggingAthlete && !isPanning && !isDrawingSelectionBox {
                    let startScaled = CGPoint(
                        x: (value.startLocation.x - canvasOffset.x) / cellSize,
                        y: (value.startLocation.y - canvasOffset.y) / cellSize
                    )

                    // Check if touch started on an athlete
                    var hitAthlete = false
                    for (index, athlete) in formation.athletes.enumerated() {
                        if PathCalculations.squaredDistance(from: startScaled, to: athlete.position)
                            < CourtConstants.hitRadiusSquared
                        {
                            // If tapping a non-selected athlete, make it the sole selection
                            if !selectedAthleteIds.contains(athlete.id) {
                                selectedAthleteIds = [athlete.id]
                            }
                            isDraggingAthlete = true
                            draggingAthleteIndex = index
                            dragStartAthletePosition = athlete.position
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            #endif
                            // Record start positions for all selected athletes (group move)
                            dragStartPositions = [:]
                            for id in selectedAthleteIds {
                                if let a = formation.athletes.first(where: { $0.id == id }) {
                                    dragStartPositions[id] = a.position
                                }
                            }
                            hitAthlete = true
                            break
                        }
                    }
                    if !hitAthlete {
                        // Start drawing selection box
                        isDrawingSelectionBox = true
                        selectionStartPoint = value.startLocation
                        selectionRect = CGRect(
                            origin: value.startLocation,
                            size: .zero
                        )
                    }
                }

                if isDraggingAthlete {
                    // Move all selected athletes together
                    let translationX = value.translation.width / cellSize
                    let translationY = value.translation.height / cellSize

                    for id in selectedAthleteIds {
                        guard let startPos = dragStartPositions[id],
                            let idx = formation.athletes.firstIndex(where: { $0.id == id })
                        else { continue }

                        let newX = startPos.x + translationX
                        let newY = startPos.y + translationY
                        let newPosition = CGPoint(
                            x: max(0, min(CourtConstants.width, round(newX))),
                            y: max(0, min(CourtConstants.height, round(newY)))
                        )
                        if formation.athletes[idx].position != newPosition {
                            formation.athletes[idx].position = newPosition
                        }
                    }
                } else if isDrawingSelectionBox {
                    // Update selection rectangle
                    let origin = CGPoint(
                        x: min(selectionStartPoint.x, value.location.x),
                        y: min(selectionStartPoint.y, value.location.y)
                    )
                    let size = CGSize(
                        width: abs(value.location.x - selectionStartPoint.x),
                        height: abs(value.location.y - selectionStartPoint.y)
                    )
                    selectionRect = CGRect(origin: origin, size: size)
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
                            var undoEntries: [(id: UUID, position: CGPoint)] = []
                            if let srcIdx = formation.athletes.firstIndex(where: {
                                $0.id == sourceId
                            }) {
                                undoEntries.append(
                                    (id: sourceId, position: formation.athletes[srcIdx].position))
                            }
                            undoEntries.append((id: athlete.id, position: athlete.position))
                            undoStack.append(undoEntries)
                            formation.swapAthletePositions(id1: sourceId, id2: athlete.id)
                            persistenceManager.updateFormation(formation)
                            tappedTarget = true
                            break
                        }
                    }
                    isSwapMode = false
                    swapSourceAthleteId = nil
                    if !tappedTarget { selectedAthleteIds = [] }
                    return
                }

                if isPanning { lastPanOffset = panOffset }

                if isDraggingAthlete {
                    // Record group undo
                    var undoEntries: [(id: UUID, position: CGPoint)] = []
                    for (id, startPos) in dragStartPositions {
                        undoEntries.append((id: id, position: startPos))
                    }
                    if !undoEntries.isEmpty {
                        undoStack.append(undoEntries)
                    }
                    persistenceManager.updateFormation(formation)
                }

                if isDrawingSelectionBox, let rect = selectionRect {
                    // Select all athletes within the selection rectangle
                    var newSelection: Set<UUID> = []
                    for athlete in formation.athletes {
                        let screenPos = CGPoint(
                            x: athlete.position.x * cellSize + canvasOffset.x,
                            y: athlete.position.y * cellSize + canvasOffset.y
                        )
                        if rect.contains(screenPos) {
                            newSelection.insert(athlete.id)
                        }
                    }
                    // If box was tiny (just a tap on empty space), deselect all
                    if rect.width < 5 && rect.height < 5 {
                        selectedAthleteIds = []
                    } else {
                        selectedAthleteIds = newSelection
                    }
                    selectionRect = nil
                }

                isDraggingAthlete = false
                draggingAthleteIndex = nil
                isPanning = false
                isDrawingSelectionBox = false
                dragStartPositions = [:]
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

        if let selectedId = selectedAthleteIds.first, selectedAthleteIds.count == 1, !isSwapMode,
            let index = formation.athletes.firstIndex(where: { $0.id == selectedId })
        {
            AthleteDetailPanel(
                athlete: $formation.athletes[index],
                selectedAthleteId: Binding(
                    get: { selectedAthleteIds.first },
                    set: { newId in
                        if let id = newId {
                            selectedAthleteIds = [id]
                        } else {
                            selectedAthleteIds = []
                        }
                    }
                ),
                onDelete: deleteSelectedAthlete,
                onSwap: {
                    swapSourceAthleteId = selectedId
                    isSwapMode = true
                }
            )
            .frame(width: 280)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        } else if selectedAthleteIds.count > 1, !isSwapMode {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
                Text("\(selectedAthleteIds.count) athletes selected")
                    .font(.subheadline.bold())
                Spacer()
                Button("Deselect") {
                    selectedAthleteIds = []
                }
                .font(.subheadline)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .cornerRadius(10)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
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
                Label("Transitions", systemImage: "play.circle")
                    .labelStyle(.titleAndIcon)
            }

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

    private func selectNextCollidingAthlete() {
        let collidingAthletes = formation.athletes.filter { cachedCollisionIds.contains($0.id) }
        guard !collidingAthletes.isEmpty else { return }

        if let currentId = selectedAthleteIds.first, selectedAthleteIds.count == 1,
            let currentIndex = collidingAthletes.firstIndex(where: { $0.id == currentId })
        {
            let nextIndex = (currentIndex + 1) % collidingAthletes.count
            selectedAthleteIds = [collidingAthletes[nextIndex].id]
        } else {
            selectedAthleteIds = [collidingAthletes.first!.id]
        }
    }

    private func addAthlete() {
        let existingLabels = Set(formation.athletes.map { $0.label })
        var count = formation.athletes.count + 1
        var label = "P\(count)"
        while existingLabels.contains(label) {
            count += 1
            label = "P\(count)"
        }

        // "Windows" layout: 8 athletes per row, 1 panel (8 ft) apart on x.
        // Rows alternate: row 0 on a panel line (y=8), row 1 on center (y=12),
        // row 2 on next line (y=16), row 3 on center (y=20), etc.
        let athletesPerRow = 8
        let col = formation.athletes.count % athletesPerRow
        let row = formation.athletes.count / athletesPerRow

        // X: start at first panel line (x=8), each column 1 panel (8 ft) apart
        let spawnX = min(CourtConstants.width - 2, 8.0 + CGFloat(col) * 8.0)

        // Y: odd rows on panel centers, even rows on panel lines
        // Row 0 → y=8 (first line), Row 1 → y=12 (center), Row 2 → y=16 (line), ...
        let panelIndex = row / 2  // which pair of line/center we're in
        let isCenter = row % 2 == 1
        let spawnY: CGFloat
        if isCenter {
            spawnY = min(CourtConstants.height - 2, 8.0 + CGFloat(panelIndex) * 8.0 + 4.0)
        } else {
            spawnY = min(CourtConstants.height - 2, 8.0 + CGFloat(panelIndex) * 8.0)
        }

        let newAthlete = Athlete(label: label, position: CGPoint(x: spawnX, y: spawnY))
        formation.addAthlete(newAthlete)
        selectedAthleteIds = [newAthlete.id]
    }

    private func undoLastMove() {
        guard let lastGroup = undoStack.popLast() else { return }
        for entry in lastGroup {
            if let index = formation.athletes.firstIndex(where: { $0.id == entry.id }) {
                formation.athletes[index].position = entry.position
            }
        }
    }

    private func deleteSelectedAthlete() {
        guard let id = selectedAthleteIds.first, selectedAthleteIds.count == 1 else { return }
        formation.removeAthlete(id: id)
        undoStack.removeAll { group in group.contains(where: { $0.id == id }) }
        selectedAthleteIds = []
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
