import SwiftUI

// MARK: - Floor Grid View

struct FloorGridView: View {
    @ObservedObject var store: RoutineStore
    let formationID: UUID
    var onDuplicateAsNext: () -> Void

    @State private var selectedAthleteIDs: Set<UUID> = []
    @State private var showingRosterSheet = false
    @State private var showingNotesSheet = false
    @State private var isDraggingAthletes = false
    @State private var isDrawingSelectionBox = false
    @State private var selectionRect: CGRect? = nil
    @State private var selectionStartPoint: CGPoint = .zero
    @State private var dragStartPositions: [UUID: CGPoint] = [:]
    @State private var undoStack: [[(id: UUID, position: CGPoint)]] = []
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    @State private var isSwapMode = false
    @State private var swapSourceAthleteID: UUID?
    @State private var collisionMessage: String?
    @State private var hasMadeFirstSelection = false

    private var formationIndex: Int? {
        store.formationIndex(id: formationID)
    }

    private var formation: Formation? {
        guard let formationIndex else { return nil }
        return store.routine.formations[formationIndex]
    }

    private var renderedAthletes: [RenderedAthlete] {
        store.renderedAthletes(for: formationID)
    }

    private var collisionSummary: (count: Int, ids: Set<UUID>) {
        PathCalculations.collisionSummary(in: renderedAthletes)
    }

    private var selectedAthleteID: UUID? {
        selectedAthleteIDs.count == 1 ? selectedAthleteIDs.first : nil
    }

    private var selectedRosterAthlete: RosterAthlete? {
        guard let selectedAthleteID else { return nil }
        return store.routine.roster.first(where: { $0.id == selectedAthleteID })
    }

    private var selectedPlacement: FormationPlacement? {
        guard let selectedAthleteID, let formation else { return nil }
        return formation.placements.first(where: { $0.athleteID == selectedAthleteID })
    }

    var body: some View {
        Group {
            if formation != nil {
                editorBody
            } else {
                ContentUnavailableView("Select a formation", systemImage: "square.grid.2x2")
            }
        }
        .sheet(isPresented: $showingRosterSheet) {
            rosterSheet
        }
        .sheet(isPresented: $showingNotesSheet) {
            notesSheet
        }
        .onChange(of: formationID) { _, _ in
            selectedAthleteIDs = []
            isSwapMode = false
            swapSourceAthleteID = nil
            collisionMessage = nil
        }
        .onChange(of: selectedAthleteIDs) { _, newSelection in
            if !newSelection.isEmpty {
                hasMadeFirstSelection = true
            }
            if newSelection.isEmpty {
                isSwapMode = false
                swapSourceAthleteID = nil
            }
        }
    }

    private var editorBody: some View {
        VStack(spacing: 0) {
            controlStrip
            Divider()

            if renderedAthletes.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    canvasArea
                    Divider()
                    inspectorPanel
                        .frame(width: 320)
                }
            }
        }
    }

    private var controlStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if collisionSummary.count > 0 {
                    Button(action: cycleCollidingSelection) {
                        Label(
                            "\(collisionSummary.count) collisions",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundColor(.red)
                    }
                    .buttonStyle(.bordered)
                }

                Button(action: addAthlete) {
                    Label("Add Athlete", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)

                Button(action: { showingRosterSheet = true }) {
                    Label("Manage Roster", systemImage: "list.bullet.rectangle")
                }
                .buttonStyle(.bordered)

                Button(action: beginSwapMode) {
                    Label("Swap", systemImage: "arrow.triangle.swap")
                }
                .buttonStyle(.bordered)
                .disabled(selectedAthleteID == nil)

                Button(action: resetView) {
                    Label("Reset View", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)

                Button(action: { showingNotesSheet = true }) {
                    Label("Notes", systemImage: "note.text")
                }
                .buttonStyle(.bordered)

                Button(action: undoLastMove) {
                    Label("Undo Move", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .disabled(undoStack.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(.bar)
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            VStack(spacing: 18) {
                Image(systemName: "figure.stand.line.dotted.figure.stand")
                    .font(.system(size: 52))
                    .foregroundColor(.accentColor)
                Text("Start your first picture")
                    .font(.title2.weight(.semibold))
                Text("Add one athlete, drop in a 10-athlete template, or duplicate after you have a picture to build from.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)

                HStack(spacing: 12) {
                    Button(action: addAthlete) {
                        Label("Add Athlete", systemImage: "plus.circle.fill")
                            .frame(minWidth: 180)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: applyTemplate) {
                        Label("Apply 10-Athlete Template", systemImage: "square.grid.3x3.fill")
                            .frame(minWidth: 220)
                    }
                    .buttonStyle(.bordered)

                    Button(action: onDuplicateAsNext) {
                        Label("Duplicate as Next Formation", systemImage: "plus.square.on.square")
                            .frame(minWidth: 220)
                    }
                    .buttonStyle(.bordered)
                    .disabled(renderedAthletes.isEmpty)
                }
            }
            .padding(32)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private var canvasArea: some View {
        GeometryReader { geometry in
            let baseCellSize = min(
                geometry.size.width / CourtConstants.width,
                geometry.size.height / CourtConstants.height
            )
            let cellSize = baseCellSize * zoomScale
            let canvasWidth = CourtConstants.width * cellSize
            let canvasHeight = CourtConstants.height * cellSize
            let offset = CGPoint(
                x: (geometry.size.width - canvasWidth) / 2,
                y: (geometry.size.height - canvasHeight) / 2
            )

            ZStack(alignment: .top) {
                FloorCanvasView(
                    athletes: renderedAthletes,
                    selectedAthleteIDs: selectedAthleteIDs,
                    collisionIDs: collisionSummary.ids,
                    cellSize: cellSize,
                    offset: offset,
                    swapSourceID: swapSourceAthleteID,
                    selectionRect: selectionRect
                )
                .gesture(dragGesture(cellSize: cellSize, offset: offset))
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            zoomScale = max(0.65, min(3.0, lastZoomScale * value.magnification))
                        }
                        .onEnded { _ in
                            lastZoomScale = zoomScale
                        }
                )

                VStack(spacing: 10) {
                    if let collisionMessage {
                        banner(text: collisionMessage, color: .red)
                    }

                    if isSwapMode, let swapSourceAthleteID,
                        let rosterAthlete = store.routine.roster.first(where: { $0.id == swapSourceAthleteID })
                    {
                        banner(
                            text: "Tap another athlete to swap with \(rosterAthlete.label).",
                            color: .blue
                        )
                    } else if !hasMadeFirstSelection {
                        banner(
                            text: "Tap an athlete to edit it. Drag on empty space to box-select.",
                            color: .accentColor
                        )
                    }
                }
                .padding(.top, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inspectorPanel: some View {
        Group {
            if let selectedRosterAthlete, let selectedPlacement {
                AthleteInspectorView(
                    athlete: selectedRosterAthlete,
                    position: selectedPlacement.position,
                    isSwapMode: isSwapMode,
                    onUpdateLabel: { newLabel in
                        store.mutateRosterAthlete(id: selectedRosterAthlete.id) { athlete in
                            athlete.label = newLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? athlete.label
                                : newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    },
                    onUpdateRole: { newRole in
                        store.mutateRosterAthlete(id: selectedRosterAthlete.id) { athlete in
                            athlete.role = newRole
                        }
                    },
                    onSwap: beginSwapMode,
                    onDelete: {
                        deleteSelectedAthlete()
                    },
                    onClearSelection: {
                        selectedAthleteIDs = []
                    }
                )
            } else if selectedAthleteIDs.count > 1 {
                MultiSelectionInspectorView(
                    count: selectedAthleteIDs.count,
                    onClearSelection: { selectedAthleteIDs = [] }
                )
            } else {
                EmptyInspectorView(
                    title: "Inspector",
                    message: "Select one athlete to edit its label, role, and actions. Multi-select to move groups together."
                )
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var rosterSheet: some View {
        NavigationStack {
            List {
                ForEach(store.routine.roster) { athlete in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(athlete.role.color)
                            .frame(width: 12, height: 12)
                        Text(athlete.label)
                        Spacer()
                        Text(athlete.role.rawValue.capitalized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onMove { from, to in
                    store.moveRoster(fromOffsets: from, toOffset: to)
                }
                .onDelete { offsets in
                    let ids = offsets.map { store.routine.roster[$0].id }
                    for id in ids {
                        store.deleteAthlete(id: id)
                    }
                    selectedAthleteIDs.subtract(ids)
                }
            }
            .navigationTitle("Manage Roster")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showingRosterSheet = false }
                }
            }
        }
    }

    private var notesSheet: some View {
        NavigationStack {
            TextEditor(
                text: Binding(
                    get: { formation?.notes ?? "" },
                    set: { newValue in
                        store.mutateFormation(id: formationID) { formation in
                            formation.notes = newValue
                        }
                    }
                )
            )
            .padding()
            .navigationTitle("Formation Notes")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showingNotesSheet = false }
                }
            }
        }
    }

    private func banner(text: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
            Text(text)
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(color.opacity(0.15))
        .foregroundColor(color)
        .clipShape(Capsule())
    }

    private func dragGesture(cellSize: CGFloat, offset: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if isSwapMode { return }

                if !isDraggingAthletes && !isDrawingSelectionBox {
                    let startPoint = CGPoint(
                        x: (value.startLocation.x - offset.x) / cellSize,
                        y: (value.startLocation.y - offset.y) / cellSize
                    )

                    if let hitAthlete = renderedAthletes.first(where: {
                        PathCalculations.squaredDistance(from: startPoint, to: $0.position) < CourtConstants.hitRadiusSquared
                    }) {
                        if !selectedAthleteIDs.contains(hitAthlete.id) {
                            selectedAthleteIDs = [hitAthlete.id]
                        }
                        dragStartPositions = Dictionary(
                            uniqueKeysWithValues: renderedAthletes
                                .filter { selectedAthleteIDs.contains($0.id) }
                                .map { ($0.id, $0.position) }
                        )
                        isDraggingAthletes = true
                    } else {
                        selectionStartPoint = value.startLocation
                        selectionRect = CGRect(origin: value.startLocation, size: .zero)
                        isDrawingSelectionBox = true
                    }
                }

                if isDraggingAthletes {
                    let translation = CGPoint(
                        x: value.translation.width / cellSize,
                        y: value.translation.height / cellSize
                    )
                    store.mutateFormation(id: formationID) { formation in
                        for athleteID in selectedAthleteIDs {
                            guard
                                let startPosition = dragStartPositions[athleteID],
                                let placementIndex = formation.placementIndex(for: athleteID)
                            else { continue }

                            let nextPosition = CGPoint(
                                x: max(0, min(CourtConstants.width, round(startPosition.x + translation.x))),
                                y: max(0, min(CourtConstants.height, round(startPosition.y + translation.y)))
                            )
                            formation.placements[placementIndex].position = nextPosition
                        }
                    }
                } else if isDrawingSelectionBox {
                    selectionRect = CGRect(
                        x: min(selectionStartPoint.x, value.location.x),
                        y: min(selectionStartPoint.y, value.location.y),
                        width: abs(value.location.x - selectionStartPoint.x),
                        height: abs(value.location.y - selectionStartPoint.y)
                    )
                }
            }
            .onEnded { value in
                defer {
                    isDraggingAthletes = false
                    isDrawingSelectionBox = false
                    selectionRect = nil
                    dragStartPositions = [:]
                }

                if isSwapMode, let swapSourceAthleteID {
                    let tapPoint = CGPoint(
                        x: (value.location.x - offset.x) / cellSize,
                        y: (value.location.y - offset.y) / cellSize
                    )
                    if let targetAthlete = renderedAthletes.first(where: {
                        $0.id != swapSourceAthleteID
                            && PathCalculations.squaredDistance(from: tapPoint, to: $0.position) < CourtConstants.hitRadiusSquared
                    }) {
                        store.swapPositions(in: formationID, id1: swapSourceAthleteID, id2: targetAthlete.id)
                        selectedAthleteIDs = [targetAthlete.id]
                    }
                    isSwapMode = false
                    self.swapSourceAthleteID = nil
                    return
                }

                if isDraggingAthletes, !dragStartPositions.isEmpty {
                    undoStack.append(dragStartPositions.map { ($0.key, $0.value) })
                }

                if isDrawingSelectionBox, let selectionRect {
                    let newSelection = Set(
                        renderedAthletes.compactMap { athlete in
                            let screenPoint = CGPoint(
                                x: athlete.position.x * cellSize + offset.x,
                                y: athlete.position.y * cellSize + offset.y
                            )
                            return selectionRect.contains(screenPoint) ? athlete.id : nil
                        }
                    )

                    if selectionRect.width < 5 && selectionRect.height < 5 {
                        selectedAthleteIDs = []
                    } else {
                        selectedAthleteIDs = newSelection
                    }
                }
            }
    }

    private func addAthlete() {
        let newID = store.addAthlete()
        selectedAthleteIDs = [newID]
    }

    private func applyTemplate() {
        store.applyBowlingPinTemplate(to: formationID)
        selectedAthleteIDs = []
    }

    private func beginSwapMode() {
        guard let selectedAthleteID else { return }
        swapSourceAthleteID = selectedAthleteID
        isSwapMode = true
    }

    private func deleteSelectedAthlete() {
        guard let selectedAthleteID else { return }
        store.deleteAthlete(id: selectedAthleteID)
        selectedAthleteIDs = []
    }

    private func undoLastMove() {
        guard let previousPositions = undoStack.popLast() else { return }
        store.mutateFormation(id: formationID) { formation in
            for entry in previousPositions {
                if let placementIndex = formation.placementIndex(for: entry.id) {
                    formation.placements[placementIndex].position = entry.position
                }
            }
        }
    }

    private func cycleCollidingSelection() {
        let collidingAthletes = renderedAthletes.filter { collisionSummary.ids.contains($0.id) }
        guard !collidingAthletes.isEmpty else { return }

        if let current = selectedAthleteID,
            let currentIndex = collidingAthletes.firstIndex(where: { $0.id == current })
        {
            let nextIndex = (currentIndex + 1) % collidingAthletes.count
            selectedAthleteIDs = [collidingAthletes[nextIndex].id]
        } else {
            selectedAthleteIDs = [collidingAthletes[0].id]
        }

        collisionMessage = "\(collisionSummary.count) athletes are within 2ft. Tap again to cycle the selection."
    }

    private func resetView() {
        withAnimation(.spring()) {
            zoomScale = 1.0
            lastZoomScale = 1.0
        }
    }
}

// MARK: - Previews

#Preview {
    struct PreviewWrapper: View {
        @StateObject private var store = RoutineStore()

        var body: some View {
            NavigationStack {
                FloorGridView(
                    store: store,
                    formationID: store.routine.formations.first?.id ?? UUID()
                ) {}
            }
        }
    }

    return PreviewWrapper()
}
