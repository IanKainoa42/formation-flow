import Combine
import SwiftUI

// MARK: - Floor Grid View

struct FloorGridView: View {
    @ObservedObject var store: RoutineStore
    let formationID: UUID
    var onDuplicateAsNext: () -> Void

    // Transition parameters (nil when no adjacent formation)
    var player: TransitionPlayer?
    var startFormationID: UUID?
    var endFormationID: UUID?

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
    @State private var activeAlignmentGuides: [AlignmentGuideRenderItem] = []
    @State private var rosterDeleteIDs: [UUID] = []
    @State private var collisionCycleIndex: Int = 0

    // Transition editing state
    @State private var focusedEndpoint: PreviewEditableEndpoint?
    @State private var isDraggingEndpoint = false
    @State private var isDraggingPathHandle = false
    @State private var draggingWaypointID: UUID?
    @State private var endpointDragStartPosition: CGPoint?
    @State private var showingResetAllPathsConfirmation = false
    @State private var playerTick: UInt = 0

    private var formationIndex: Int? {
        store.formationIndex(id: formationID)
    }

    private var formation: Formation? {
        guard let formationIndex else { return nil }
        return store.routine.formations[formationIndex]
    }

    private var renderedAthletes: [RenderedAthlete] {
        _ = playerTick // force redraw on player updates
        if let player, player.progress > 0 {
            return player.currentAthletes
        }
        return store.renderedAthletes(for: formationID)
    }

    private var collisionSummary: (count: Int, ids: Set<UUID>) {
        PathCalculations.collisionSummary(in: renderedAthletes)
    }

    private var collidingAthletes: [RenderedAthlete] {
        renderedAthletes.filter { collisionSummary.ids.contains($0.id) }
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

    // MARK: - Transition Computed Properties

    private var hasTransition: Bool {
        player != nil && startFormationID != nil && endFormationID != nil
    }

    private var transitionPaths: [TransitionPathRenderItem] {
        guard let player else { return [] }
        let endLookup = Dictionary(uniqueKeysWithValues: player.endAthletes.map { ($0.id, $0) })
        return player.startAthletes.compactMap { athlete in
            guard let endAthlete = endLookup[athlete.id] else { return nil }
            let transition = player.transitionSpec.athleteTransition(for: athlete.id)
            return TransitionPathRenderItem(
                athleteID: athlete.id,
                startPosition: athlete.position,
                endPosition: endAthlete.position,
                controlPoint: transition.pathControlPoint,
                waypoints: transition.pathWaypoints,
                moveDelay: transition.moveDelay
            )
        }
    }

    private var endpointMarkers: [TransitionEndpointMarkerRenderItem] {
        guard let player else { return [] }
        let startStyle: TransitionEndpointMarkerRenderItem.Style =
            focusedEndpoint == nil || focusedEndpoint == .start ? .editable : .readOnly
        let endStyle: TransitionEndpointMarkerRenderItem.Style =
            focusedEndpoint == nil || focusedEndpoint == .end ? .editable : .readOnly
        let startMarkers = player.startAthletes.map { athlete in
            TransitionEndpointMarkerRenderItem(
                athleteID: athlete.id,
                label: athlete.label,
                role: athlete.role,
                position: athlete.position,
                endpoint: .start,
                style: startStyle
            )
        }
        let endMarkers = player.endAthletes.map { athlete in
            TransitionEndpointMarkerRenderItem(
                athleteID: athlete.id,
                label: athlete.label,
                role: athlete.role,
                position: athlete.position,
                endpoint: .end,
                style: endStyle
            )
        }
        return startMarkers + endMarkers
    }

    private var pathCollisionIDs: Set<UUID> {
        guard let player else { return [] }
        return PathCalculations.findPathCollisionIDs(paths: transitionPaths, counts: CGFloat(player.counts))
    }

    private var editableFormationID: UUID? {
        guard hasTransition, let focusedEndpoint else { return nil }
        return focusedEndpoint == .start ? startFormationID : endFormationID
    }

    private var editableAthletes: [RenderedAthlete] {
        guard let player, let focusedEndpoint else { return [] }
        return focusedEndpoint == .start ? player.startAthletes : player.endAthletes
    }

    private var selectedTransition: AthleteTransition? {
        guard let selectedAthleteID, let player else { return nil }
        return player.transitionSpec.athleteTransition(for: selectedAthleteID)
    }

    private var hasCustomPaths: Bool {
        guard let player else { return false }
        return player.transitionSpec.athleteTransitions.contains {
            $0.pathControlPoint != nil || !$0.pathWaypoints.isEmpty
        }
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
            activeAlignmentGuides = []
            collisionCycleIndex = 0
            focusedEndpoint = nil
            clearTransitionDragState()
        }
        .onChange(of: selectedAthleteIDs) { _, newSelection in
            if !newSelection.isEmpty {
                hasMadeFirstSelection = true
            }
            if newSelection.isEmpty {
                isSwapMode = false
                swapSourceAthleteID = nil
                focusedEndpoint = nil
            }
        }
        .confirmationDialog(
            "Reset all paths?",
            isPresented: $showingResetAllPathsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset All Paths", role: .destructive) {
                resetAllPaths()
            }
        } message: {
            Text("This removes every custom curve and waypoint and returns all athletes to straight-line travel.")
        }
        .onReceive(player?.objectWillChange.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()) { _ in
            playerTick &+= 1
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
                if !collidingAthletes.isEmpty {
                    HStack(spacing: 4) {
                        Button {
                            collisionCycleIndex = (collisionCycleIndex - 1 + collidingAthletes.count) % collidingAthletes.count
                            selectCollision(at: collisionCycleIndex)
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .buttonStyle(.bordered)

                        Label(
                            "\(collisionCycleIndex + 1)/\(collidingAthletes.count) collisions",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundColor(.red)
                        .font(.subheadline.weight(.medium))

                        Button {
                            collisionCycleIndex = (collisionCycleIndex + 1) % collidingAthletes.count
                            selectCollision(at: collisionCycleIndex)
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .buttonStyle(.bordered)
                    }
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
                .overlay(alignment: .topTrailing) {
                    if formation?.notes.isEmpty == false {
                        Circle()
                            .fill(.orange)
                            .frame(width: 8, height: 8)
                            .offset(x: 2, y: -2)
                    }
                }

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
                    transitionPaths: transitionPaths,
                    endpointMarkers: endpointMarkers,
                    alignmentGuides: activeAlignmentGuides,
                    collisionIDs: collisionSummary.ids,
                    pathCollisionIDs: pathCollisionIDs,
                    cellSize: cellSize,
                    offset: offset,
                    swapSourceID: swapSourceAthleteID,
                    selectionRect: selectionRect,
                    focusedEndpoint: focusedEndpoint,
                    hasTransition: hasTransition
                )
                .gesture(dragGesture(cellSize: cellSize, offset: offset))
                .simultaneousGesture(waypointDoubleTapGesture(cellSize: cellSize, offset: offset))
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

                    if !pathCollisionIDs.isEmpty {
                        banner(
                            text: "\(pathCollisionIDs.count) athletes have crossing paths.",
                            color: .red
                        )
                    }
                }
                .padding(.top, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Inspector Panel

    private var inspectorPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let selectedRosterAthlete, let selectedPlacement {
                    AthleteInspectorView(
                        athlete: selectedRosterAthlete,
                        position: selectedPlacement.position,
                        isSwapMode: isSwapMode,
                        formationCount: store.routine.formations.count,
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

                    if hasTransition, let selectedTransition, let player,
                       let startFormationID, let endFormationID
                    {
                        Divider()
                        transitionInspectorSection(
                            transition: selectedTransition,
                            player: player,
                            startFormationID: startFormationID,
                            endFormationID: endFormationID
                        )
                    }
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
        }
        .background(.thinMaterial)
        .frame(maxHeight: .infinity)
    }

    // MARK: - Transition Inspector

    private func transitionInspectorSection(
        transition: AthleteTransition,
        player: TransitionPlayer,
        startFormationID: UUID,
        endFormationID: UUID
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Transition")
                    .font(.headline)
                Spacer()
                Button(role: .destructive) {
                    showingResetAllPathsConfirmation = true
                } label: {
                    Label("Reset All", systemImage: "arrow.uturn.backward.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(!hasCustomPaths)
            }

            // Move delay
            VStack(alignment: .leading, spacing: 8) {
                Text("Start Delay")
                    .font(.subheadline.weight(.semibold))
                Slider(
                    value: Binding(
                        get: { transition.moveDelayCounts },
                        set: { newValue in
                            guard let selectedAthleteID else { return }
                            store.mutateAthleteTransition(
                                from: startFormationID,
                                to: endFormationID,
                                athleteID: selectedAthleteID
                            ) { t in
                                t.moveDelayCounts = min(CGFloat(player.counts), max(0, newValue))
                            }
                            refreshTransitionFromStore()
                        }
                    ),
                    in: 0...CGFloat(player.counts),
                    step: 0.5
                )
                Text(TransitionCountFormatting.label(transition.moveDelayCounts))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            // Path controls
            VStack(alignment: .leading, spacing: 10) {
                Text("Path")
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 10) {
                    Button(action: clearPath) {
                        Label("Straight", systemImage: "line.diagonal")
                    }
                    .buttonStyle(.bordered)

                    Button(action: ensureCurve) {
                        Label("Curve", systemImage: "scribble")
                    }
                    .buttonStyle(.bordered)
                }

                Text("Double-tap the selected athlete to add a waypoint, then drag the handles.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Waypoint list
            if !transition.pathWaypoints.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Waypoints")
                        .font(.subheadline.weight(.semibold))
                    ForEach(Array(transition.pathWaypoints.enumerated()), id: \.element.id) { waypointIndex, waypoint in
                        waypointCard(
                            waypointIndex: waypointIndex,
                            waypoint: waypoint,
                            player: player,
                            startFormationID: startFormationID,
                            endFormationID: endFormationID
                        )
                    }
                }
            }
        }
        .padding(20)
    }

    private func waypointCard(
        waypointIndex: Int,
        waypoint: PathWaypoint,
        player: TransitionPlayer,
        startFormationID: UUID,
        endFormationID: UUID
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Waypoint \(waypointIndex + 1)")
                    .font(.body.weight(.medium))
                Spacer()
                Button {
                    guard let selectedAthleteID else { return }
                    store.mutateAthleteTransition(
                        from: startFormationID,
                        to: endFormationID,
                        athleteID: selectedAthleteID
                    ) { t in
                        t.pathWaypoints.remove(at: waypointIndex)
                    }
                    refreshTransitionFromStore()
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }

            HStack {
                Text(waypoint.isSmooth ? "Smooth" : "Sharp")
                Spacer()
                Button(waypoint.isSmooth ? "Make Sharp" : "Make Smooth") {
                    guard let selectedAthleteID else { return }
                    store.mutateAthleteTransition(
                        from: startFormationID,
                        to: endFormationID,
                        athleteID: selectedAthleteID
                    ) { t in
                        t.pathWaypoints[waypointIndex].isSmooth.toggle()
                    }
                    refreshTransitionFromStore()
                }
                .buttonStyle(.bordered)
            }

            HStack {
                Text("Hold")
                Spacer()
                Button("- 0.5") {
                    guard let selectedAthleteID else { return }
                    store.mutateAthleteTransition(
                        from: startFormationID,
                        to: endFormationID,
                        athleteID: selectedAthleteID
                    ) { t in
                        t.pathWaypoints[waypointIndex].holdCounts = max(
                            0,
                            t.pathWaypoints[waypointIndex].holdCounts - 0.5
                        )
                    }
                    refreshTransitionFromStore()
                }
                .buttonStyle(.bordered)

                Text(TransitionCountFormatting.label(waypoint.holdCounts))
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 84)

                Button("+ 0.5") {
                    guard let selectedAthleteID else { return }
                    store.mutateAthleteTransition(
                        from: startFormationID,
                        to: endFormationID,
                        athleteID: selectedAthleteID
                    ) { t in
                        t.pathWaypoints[waypointIndex].holdCounts = min(
                            CGFloat(player.counts),
                            t.pathWaypoints[waypointIndex].holdCounts + 0.5
                        )
                    }
                    refreshTransitionFromStore()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
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
                        Text(athlete.role.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onMove { from, to in
                    store.moveRoster(fromOffsets: from, toOffset: to)
                }
                .onDelete { offsets in
                    rosterDeleteIDs = offsets.map { store.routine.roster[$0].id }
                }
            }
            .confirmationDialog(
                "Delete \(rosterDeleteIDs.count == 1 ? "this athlete" : "these athletes")?",
                isPresented: Binding(
                    get: { !rosterDeleteIDs.isEmpty },
                    set: { if !$0 { rosterDeleteIDs = [] } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    for id in rosterDeleteIDs {
                        store.deleteAthlete(id: id)
                    }
                    selectedAthleteIDs.subtract(rosterDeleteIDs)
                    rosterDeleteIDs = []
                }
            } message: {
                Text("This will remove them from all \(store.routine.formations.count) formations and their transitions.")
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

    // MARK: - Unified Gesture Handler

    private func dragGesture(cellSize: CGFloat, offset: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if isSwapMode { return }

                let startScaledPoint = CGPoint(
                    x: (value.startLocation.x - offset.x) / cellSize,
                    y: (value.startLocation.y - offset.y) / cellSize
                )
                let scaledPoint = CGPoint(
                    x: (value.location.x - offset.x) / cellSize,
                    y: (value.location.y - offset.y) / cellSize
                )

                // Priority 1: Continue in-progress drags
                if isDraggingPathHandle {
                    handlePathDragContinued(scaledPoint: scaledPoint)
                    return
                }
                if isDraggingEndpoint {
                    handleEndpointDragContinued(value, cellSize: cellSize, offset: offset)
                    return
                }
                if isDraggingAthletes {
                    handleFormationDragContinued(value, cellSize: cellSize)
                    return
                }
                if isDrawingSelectionBox {
                    handleSelectionBoxContinued(value)
                    return
                }

                // Priority 2: Hit-test for new drag initiation
                // 2a: Waypoint handles
                if hasTransition, let selectedAthleteID,
                   let startFormationID, let endFormationID,
                   let player
                {
                    let transition = player.transitionSpec.athleteTransition(for: selectedAthleteID)

                    if !transition.pathWaypoints.isEmpty {
                        // Check waypoint handles
                        for waypoint in transition.pathWaypoints {
                            if PathCalculations.squaredDistance(from: startScaledPoint, to: waypoint.position)
                                < CourtConstants.hitRadiusSquared
                            {
                                draggingWaypointID = waypoint.id
                                isDraggingPathHandle = true
                                focusedEndpoint = nil
                                return
                            }
                        }

                        // Check "+" midpoint handles for inserting new waypoints
                        let startAthlete = player.startAthletes.first(where: { $0.id == selectedAthleteID })
                        let endAthlete = player.endAthletes.first(where: { $0.id == selectedAthleteID })
                        if let startAthlete, let endAthlete {
                            let nodes = PathCalculations.waypointNodes(
                                from: startAthlete.position,
                                to: endAthlete.position,
                                waypoints: transition.pathWaypoints
                            )
                            for segmentIndex in 0..<(nodes.count - 1) {
                                let midpoint = CGPoint(
                                    x: (nodes[segmentIndex].x + nodes[segmentIndex + 1].x) / 2,
                                    y: (nodes[segmentIndex].y + nodes[segmentIndex + 1].y) / 2
                                )
                                if PathCalculations.squaredDistance(from: startScaledPoint, to: midpoint)
                                    < CourtConstants.hitRadiusSquared
                                {
                                    let newWaypoint = PathWaypoint(position: midpoint, isSmooth: true)
                                    store.mutateAthleteTransition(
                                        from: startFormationID,
                                        to: endFormationID,
                                        athleteID: selectedAthleteID
                                    ) { t in
                                        let insertIndex = min(segmentIndex, t.pathWaypoints.count)
                                        t.pathWaypoints.insert(newWaypoint, at: insertIndex)
                                        t.pathControlPoint = nil
                                    }
                                    draggingWaypointID = newWaypoint.id
                                    isDraggingPathHandle = true
                                    focusedEndpoint = nil
                                    refreshTransitionFromStore()
                                    return
                                }
                            }
                        }
                    } else {
                        // Legacy control point handle
                        let startAthlete = player.startAthletes.first(where: { $0.id == selectedAthleteID })
                        let endAthlete = player.endAthletes.first(where: { $0.id == selectedAthleteID })
                        if let startAthlete, let endAthlete {
                            let midpoint: CGPoint
                            if let controlPoint = transition.pathControlPoint {
                                midpoint = PathCalculations.quadraticBezierPoint(
                                    from: startAthlete.position,
                                    control: controlPoint,
                                    to: endAthlete.position,
                                    t: 0.5
                                )
                            } else {
                                midpoint = CGPoint(
                                    x: (startAthlete.position.x + endAthlete.position.x) / 2,
                                    y: (startAthlete.position.y + endAthlete.position.y) / 2
                                )
                            }
                            if PathCalculations.squaredDistance(from: startScaledPoint, to: midpoint)
                                < CourtConstants.hitRadiusSquared
                            {
                                isDraggingPathHandle = true
                                focusedEndpoint = nil
                                handlePathDragContinued(scaledPoint: scaledPoint)
                                return
                            }
                        }
                    }
                }

                // 2b: Endpoint markers (either side — tapping focuses that formation)
                if hasTransition {
                    if let hitMarker = endpointMarkers.first(where: {
                        PathCalculations.squaredDistance(from: startScaledPoint, to: $0.position) < CourtConstants.hitRadiusSquared
                    }) {
                        selectedAthleteIDs = [hitMarker.athleteID]
                        focusedEndpoint = hitMarker.endpoint
                        endpointDragStartPosition = hitMarker.position
                        isDraggingEndpoint = true
                        return
                    }
                }

                // 2c: Main formation athletes
                if let hitAthlete = renderedAthletes.first(where: {
                    PathCalculations.squaredDistance(from: startScaledPoint, to: $0.position) < CourtConstants.hitRadiusSquared
                }) {
                    if !selectedAthleteIDs.contains(hitAthlete.id) {
                        selectedAthleteIDs = [hitAthlete.id]
                    }
                    focusedEndpoint = nil
                    dragStartPositions = Dictionary(
                        uniqueKeysWithValues: renderedAthletes
                            .filter { selectedAthleteIDs.contains($0.id) }
                            .map { ($0.id, $0.position) }
                    )
                    isDraggingAthletes = true
                    return
                }

                // 2d: Empty space → selection box
                focusedEndpoint = nil
                selectionStartPoint = value.startLocation
                selectionRect = CGRect(origin: value.startLocation, size: .zero)
                isDrawingSelectionBox = true
            }
            .onEnded { value in
                defer {
                    isDraggingAthletes = false
                    isDraggingEndpoint = false
                    isDraggingPathHandle = false
                    draggingWaypointID = nil
                    isDrawingSelectionBox = false
                    selectionRect = nil
                    dragStartPositions = [:]
                    endpointDragStartPosition = nil
                    activeAlignmentGuides = []
                }

                if isSwapMode, let swapSourceAthleteID {
                    let tapPoint = CGPoint(
                        x: (value.location.x - offset.x) / cellSize,
                        y: (value.location.y - offset.y) / cellSize
                    )

                    // Try swapping in endpoint markers (check both sides)
                    if hasTransition, let player {
                        let allEndpointAthletes: [(athlete: RenderedAthlete, formationID: UUID)] =
                            player.startAthletes.map { ($0, startFormationID!) }
                            + player.endAthletes.map { ($0, endFormationID!) }
                        if let target = allEndpointAthletes.first(where: {
                            $0.athlete.id != swapSourceAthleteID
                                && PathCalculations.squaredDistance(from: tapPoint, to: $0.athlete.position) < CourtConstants.hitRadiusSquared
                        }) {
                            store.swapPositions(in: target.formationID, id1: swapSourceAthleteID, id2: target.athlete.id)
                            selectedAthleteIDs = [target.athlete.id]
                            refreshTransitionFromStore()
                            isSwapMode = false
                            self.swapSourceAthleteID = nil
                            return
                        }
                    }

                    // Try swapping in main formation
                    if let targetAthlete = renderedAthletes.first(where: {
                        $0.id != swapSourceAthleteID
                            && PathCalculations.squaredDistance(from: tapPoint, to: $0.position) < CourtConstants.hitRadiusSquared
                    }) {
                        store.swapPositions(in: formationID, id1: swapSourceAthleteID, id2: targetAthlete.id)
                        selectedAthleteIDs = [targetAthlete.id]
                        refreshTransitionFromStore()
                    }
                    isSwapMode = false
                    self.swapSourceAthleteID = nil
                    return
                }

                if isDraggingAthletes, !dragStartPositions.isEmpty {
                    undoStack.append(dragStartPositions.map { ($0.key, $0.value) })
                    refreshTransitionFromStore()
                }

                if isDraggingEndpoint {
                    refreshTransitionFromStore()
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
                        // Tap on empty space — also try selecting from transition athletes
                        let tapPoint = CGPoint(
                            x: (value.location.x - offset.x) / cellSize,
                            y: (value.location.y - offset.y) / cellSize
                        )
                        if hasTransition, let player {
                            if let athlete = player.currentAthletes.first(where: {
                                PathCalculations.squaredDistance(from: tapPoint, to: $0.position) < CourtConstants.hitRadiusSquared
                            }) {
                                selectedAthleteIDs = [athlete.id]
                                return
                            }
                        }
                        selectedAthleteIDs = []
                    } else {
                        selectedAthleteIDs = newSelection
                    }
                }
            }
    }

    // MARK: - Drag Helpers

    private func handlePathDragContinued(scaledPoint: CGPoint) {
        guard let selectedAthleteID, let player, let startFormationID, let endFormationID else { return }
        activeAlignmentGuides = []
        let transition = player.transitionSpec.athleteTransition(for: selectedAthleteID)

        if !transition.pathWaypoints.isEmpty {
            if let draggingWaypointID,
               let waypointIndex = transition.pathWaypoints.firstIndex(where: { $0.id == draggingWaypointID })
            {
                store.mutateAthleteTransition(
                    from: startFormationID,
                    to: endFormationID,
                    athleteID: selectedAthleteID
                ) { t in
                    t.pathWaypoints[waypointIndex].position = scaledPoint
                }
                refreshTransitionFromStore()
            }
        } else {
            // Legacy control point drag
            let startAthlete = player.startAthletes.first(where: { $0.id == selectedAthleteID })
            let endAthlete = player.endAthletes.first(where: { $0.id == selectedAthleteID })
            if let startAthlete, let endAthlete {
                let newControlPoint = CGPoint(
                    x: 2 * scaledPoint.x - 0.5 * startAthlete.position.x - 0.5 * endAthlete.position.x,
                    y: 2 * scaledPoint.y - 0.5 * startAthlete.position.y - 0.5 * endAthlete.position.y
                )
                store.mutateAthleteTransition(
                    from: startFormationID,
                    to: endFormationID,
                    athleteID: selectedAthleteID
                ) { t in
                    t.pathControlPoint = newControlPoint
                    t.pathWaypoints = []
                }
                refreshTransitionFromStore()
            }
        }
    }

    private func handleEndpointDragContinued(
        _ value: DragGesture.Value,
        cellSize: CGFloat,
        offset: CGPoint
    ) {
        guard let selectedAthleteID, let editableFormationID, let endpointDragStartPosition else { return }

        let rawTranslation = CGPoint(
            x: value.translation.width / cellSize,
            y: value.translation.height / cellSize
        )
        let snapResult = AlignmentSnapEngine.snap(
            translation: rawTranslation,
            startingPositions: [endpointDragStartPosition],
            otherAthletePositions: editableAthletes
                .filter { $0.id != selectedAthleteID }
                .map(\.position)
        )
        activeAlignmentGuides = snapResult.guides

        let nextPosition = CGPoint(
            x: clampedCoordinate(endpointDragStartPosition.x + snapResult.translation.x, upperBound: CourtConstants.width),
            y: clampedCoordinate(endpointDragStartPosition.y + snapResult.translation.y, upperBound: CourtConstants.height)
        )

        store.mutateFormation(id: editableFormationID) { formation in
            guard let placementIndex = formation.placementIndex(for: selectedAthleteID) else { return }
            formation.placements[placementIndex].position = nextPosition
        }
        refreshTransitionFromStore()
    }

    private func handleFormationDragContinued(_ value: DragGesture.Value, cellSize: CGFloat) {
        let rawTranslation = CGPoint(
            x: value.translation.width / cellSize,
            y: value.translation.height / cellSize
        )
        let snapResult = snappingResult(for: rawTranslation)
        activeAlignmentGuides = snapResult.guides

        store.mutateFormation(id: formationID) { formation in
            for athleteID in selectedAthleteIDs {
                guard
                    let startPosition = dragStartPositions[athleteID],
                    let placementIndex = formation.placementIndex(for: athleteID)
                else { continue }

                let nextPosition = CGPoint(
                    x: clampedCoordinate(startPosition.x + snapResult.translation.x, upperBound: CourtConstants.width),
                    y: clampedCoordinate(startPosition.y + snapResult.translation.y, upperBound: CourtConstants.height)
                )
                formation.placements[placementIndex].position = nextPosition
            }
        }
    }

    private func handleSelectionBoxContinued(_ value: DragGesture.Value) {
        activeAlignmentGuides = []
        selectionRect = CGRect(
            x: min(selectionStartPoint.x, value.location.x),
            y: min(selectionStartPoint.y, value.location.y),
            width: abs(value.location.x - selectionStartPoint.x),
            height: abs(value.location.y - selectionStartPoint.y)
        )
    }

    // MARK: - Double-Tap Gesture for Waypoints

    private func waypointDoubleTapGesture(cellSize: CGFloat, offset: CGPoint) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                guard hasTransition else { return }
                guard let selectedAthleteID, let player else { return }
                guard let selectedAthlete = player.currentAthletes.first(where: { $0.id == selectedAthleteID })
                else { return }

                let scaledPoint = CGPoint(
                    x: (value.location.x - offset.x) / cellSize,
                    y: (value.location.y - offset.y) / cellSize
                )

                guard
                    PathCalculations.squaredDistance(from: scaledPoint, to: selectedAthlete.position)
                        < CourtConstants.hitRadiusSquared
                else { return }

                addWaypoint()
            }
    }

    // MARK: - Transition Actions

    private func clearPath() {
        guard let selectedAthleteID, let startFormationID, let endFormationID else { return }
        store.mutateAthleteTransition(from: startFormationID, to: endFormationID, athleteID: selectedAthleteID) { t in
            t.pathControlPoint = nil
            t.pathWaypoints = []
        }
        refreshTransitionFromStore()
    }

    private func ensureCurve() {
        guard let selectedAthleteID, let startFormationID, let endFormationID, let player else { return }
        let startAthlete = player.startAthletes.first(where: { $0.id == selectedAthleteID })
        let endAthlete = player.endAthletes.first(where: { $0.id == selectedAthleteID })
        guard let startAthlete, let endAthlete else { return }

        store.mutateAthleteTransition(from: startFormationID, to: endFormationID, athleteID: selectedAthleteID) { t in
            guard t.pathControlPoint == nil && t.pathWaypoints.isEmpty else { return }
            let midpoint = CGPoint(
                x: (startAthlete.position.x + endAthlete.position.x) / 2,
                y: (startAthlete.position.y + endAthlete.position.y) / 2
            )
            t.pathControlPoint = CGPoint(x: midpoint.x, y: midpoint.y - 6)
        }
        refreshTransitionFromStore()
    }

    private func addWaypoint() {
        guard let selectedAthleteID, let startFormationID, let endFormationID, let player else { return }
        let startAthlete = player.startAthletes.first(where: { $0.id == selectedAthleteID })
        let endAthlete = player.endAthletes.first(where: { $0.id == selectedAthleteID })
        guard let startAthlete, let endAthlete else { return }

        store.mutateAthleteTransition(from: startFormationID, to: endFormationID, athleteID: selectedAthleteID) { t in
            if t.pathWaypoints.isEmpty {
                let point = t.pathControlPoint
                    ?? CGPoint(
                        x: (startAthlete.position.x + endAthlete.position.x) / 2,
                        y: (startAthlete.position.y + endAthlete.position.y) / 2
                    )
                t.pathWaypoints = [PathWaypoint(position: point, isSmooth: true)]
                t.pathControlPoint = nil
            } else {
                let lastNode = t.pathWaypoints.last?.position ?? startAthlete.position
                let point = CGPoint(
                    x: (lastNode.x + endAthlete.position.x) / 2,
                    y: (lastNode.y + endAthlete.position.y) / 2
                )
                t.pathWaypoints.append(PathWaypoint(position: point, isSmooth: true))
            }
        }
        refreshTransitionFromStore()
    }

    private func resetAllPaths() {
        guard let startFormationID, let endFormationID else { return }
        clearTransitionDragState()

        store.mutateTransitionSpec(from: startFormationID, to: endFormationID) { spec in
            for index in spec.athleteTransitions.indices {
                spec.athleteTransitions[index].pathControlPoint = nil
                spec.athleteTransitions[index].pathWaypoints = []
            }
        }
        refreshTransitionFromStore()
    }

    private func clearTransitionDragState() {
        isDraggingPathHandle = false
        isDraggingEndpoint = false
        draggingWaypointID = nil
        endpointDragStartPosition = nil
    }

    private func refreshTransitionFromStore() {
        guard let player, let startFormationID, let endFormationID else { return }
        player.refresh(
            startAthletes: store.renderedAthletes(for: startFormationID),
            endAthletes: store.renderedAthletes(for: endFormationID),
            transitionSpec: store.transitionSpec(for: startFormationID, to: endFormationID)
        )
    }

    // MARK: - Formation Actions

    private func snappingResult(for translation: CGPoint) -> SnapResult {
        guard !dragStartPositions.isEmpty else {
            return SnapResult(translation: translation, guides: [])
        }

        let result = AlignmentSnapEngine.snap(
            translation: translation,
            startingPositions: Array(dragStartPositions.values),
            otherAthletePositions: renderedAthletes
                .filter { !selectedAthleteIDs.contains($0.id) }
                .map(\.position)
        )
        return SnapResult(translation: result.translation, guides: result.guides)
    }

    private func clampedCoordinate(_ value: CGFloat, upperBound: CGFloat) -> CGFloat {
        max(0, min(upperBound, round(value)))
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

    private func selectCollision(at index: Int) {
        guard !collidingAthletes.isEmpty else { return }
        let safeIndex = index % collidingAthletes.count
        selectedAthleteIDs = [collidingAthletes[safeIndex].id]
        collisionMessage = "\(collidingAthletes.count) athletes are within 2ft. Use arrows to cycle."
    }

    private func resetView() {
        withAnimation(.spring()) {
            zoomScale = 1.0
            lastZoomScale = 1.0
        }
    }
}

private struct SnapResult {
    let translation: CGPoint
    let guides: [AlignmentGuideRenderItem]
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
