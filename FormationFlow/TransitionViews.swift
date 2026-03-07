import SwiftUI

// MARK: - Transition Player View

struct TransitionPlayerView: View {
    enum TimelineMode: Int, CaseIterable {
        case seconds = 0
        case four = 4
        case eight = 8
        case sixteen = 16

        var title: String {
            switch self {
            case .seconds: return "Seconds"
            case .four: return "4-count"
            case .eight: return "8-count"
            case .sixteen: return "16-count"
            }
        }
    }

    @ObservedObject var store: RoutineStore
    let startFormationID: UUID
    let endFormationID: UUID

    @StateObject private var player: TransitionPlayer
    @State private var selectedAthleteID: UUID?
    @State private var timelineMode: TimelineMode = .seconds
    @State private var isDraggingHandle = false
    @State private var draggingWaypointID: UUID?

    init(store: RoutineStore, startFormationID: UUID, endFormationID: UUID) {
        self.store = store
        self.startFormationID = startFormationID
        self.endFormationID = endFormationID
        _player = StateObject(
            wrappedValue: TransitionPlayer(
                startAthletes: store.renderedAthletes(for: startFormationID),
                endAthletes: store.renderedAthletes(for: endFormationID),
                transitionSpec: store.transitionSpec(for: startFormationID, to: endFormationID)
            )
        )
    }

    private var startFormation: Formation? {
        guard let index = store.formationIndex(id: startFormationID) else { return nil }
        return store.routine.formations[index]
    }

    private var endFormation: Formation? {
        guard let index = store.formationIndex(id: endFormationID) else { return nil }
        return store.routine.formations[index]
    }

    private var transitionPaths: [TransitionPathRenderItem] {
        let endLookup = Dictionary(uniqueKeysWithValues: player.endAthletes.map { ($0.id, $0) })
        return player.startAthletes.compactMap { athlete in
            guard let endAthlete = endLookup[athlete.id] else { return nil }
            let transition = player.transitionSpec.athleteTransition(for: athlete.id)
            return TransitionPathRenderItem(
                athleteID: athlete.id,
                startPosition: athlete.position,
                endPosition: endAthlete.position,
                controlPoint: transition.pathControlPoint,
                waypoints: transition.pathWaypoints
            )
        }
    }

    private var pathCollisionIDs: Set<UUID> {
        PathCalculations.findPathCollisionIDs(paths: transitionPaths)
    }

    private var selectedStartAthlete: RenderedAthlete? {
        guard let selectedAthleteID else { return nil }
        return player.startAthletes.first(where: { $0.id == selectedAthleteID })
    }

    private var selectedEndAthlete: RenderedAthlete? {
        guard let selectedAthleteID else { return nil }
        return player.endAthletes.first(where: { $0.id == selectedAthleteID })
    }

    private var selectedTransition: AthleteTransition? {
        guard let selectedAthleteID else { return nil }
        return player.transitionSpec.athleteTransition(for: selectedAthleteID)
    }

    var body: some View {
        Group {
            if startFormation != nil && endFormation != nil {
                HStack(spacing: 0) {
                    canvasArea
                    Divider()
                    inspectorPanel
                        .frame(width: 360)
                }
            } else {
                ContentUnavailableView("Transition unavailable", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
            }
        }
        .onAppear(perform: refreshFromStore)
        .onChange(of: store.routine) { _, _ in
            refreshFromStore()
        }
    }

    private var canvasArea: some View {
        GeometryReader { geometry in
            let cellSize = min(
                geometry.size.width / CourtConstants.width,
                geometry.size.height / CourtConstants.height
            )
            let canvasWidth = CourtConstants.width * cellSize
            let canvasHeight = CourtConstants.height * cellSize
            let offset = CGPoint(
                x: (geometry.size.width - canvasWidth) / 2,
                y: (geometry.size.height - canvasHeight) / 2
            )

            ZStack(alignment: .top) {
                FloorCanvasView(
                    athletes: player.currentAthletes,
                    selectedAthleteIDs: selectedAthleteID.map { [$0] } ?? [],
                    transitionPaths: transitionPaths,
                    pathCollisionIDs: pathCollisionIDs,
                    cellSize: cellSize,
                    offset: offset
                )
                .gesture(canvasGesture(cellSize: cellSize, offset: offset))
                .simultaneousGesture(waypointDoubleTapGesture(cellSize: cellSize, offset: offset))

                VStack(spacing: 10) {
                    banner(
                        text: "Select an athlete to adjust delay and path. Drag path handles on the court for fine tuning.",
                        color: .accentColor
                    )

                    if !pathCollisionIDs.isEmpty {
                        banner(
                            text: "\(pathCollisionIDs.count) athletes have crossing paths inside this preview.",
                            color: .red
                        )
                    }
                }
                .padding(.top, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inspectorPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerSection
                playbackSection
                timelineSection
                selectedAthleteSection
            }
            .padding(20)
        }
        .background(.thinMaterial)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transition Preview")
                .font(.headline)
            if let startFormation, let endFormation {
                Text("\(startFormation.name) → \(endFormation.name)")
                    .font(.title3.weight(.semibold))
                Text("This preview always uses the selected formation and the one immediately after it.")
                    .foregroundColor(.secondary)
            }
        }
    }

    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Playback")
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Duration")
                    Spacer()
                    Text(String(format: "%.1fs", player.duration))
                        .font(.system(.body, design: .monospaced))
                }
                Slider(
                    value: Binding(
                        get: { player.duration },
                        set: { newValue in
                            store.mutateTransitionSpec(from: startFormationID, to: endFormationID) { spec in
                                spec.duration = max(0.5, newValue)
                            }
                            refreshFromStore()
                        }
                    ),
                    in: 0.5...20,
                    step: 0.5
                )
            }

            HStack(spacing: 10) {
                Button(action: { player.reset() }) {
                    Label("Reset", systemImage: "backward.end.fill")
                }
                .buttonStyle(.bordered)

                Button(action: {
                    if player.isPlaying {
                        player.pause()
                    } else {
                        player.play()
                    }
                }) {
                    Label(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                }
                .buttonStyle(.borderedProminent)

                Button(action: { player.isLooping.toggle() }) {
                    Label("Loop", systemImage: "repeat")
                }
                .buttonStyle(.bordered)
                .tint(player.isLooping ? .accentColor : .secondary)
            }
        }
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Timing")
                .font(.subheadline.weight(.semibold))

            Slider(
                value: Binding(
                    get: { player.progress },
                    set: { player.seek(to: $0) }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    if editing { player.pause() }
                }
            )

            HStack {
                if timelineMode == .seconds {
                    Text(formatTime(player.progress * CGFloat(player.duration)))
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Text(formatTime(CGFloat(player.duration)))
                        .font(.system(.body, design: .monospaced))
                } else {
                    let totalCounts = CGFloat(timelineMode.rawValue)
                    Text(String(format: "%.1f / %.0f", player.progress * totalCounts, totalCounts))
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Text("Counts")
                        .foregroundColor(.secondary)
                }
            }
            .foregroundColor(.secondary)

            Picker("Timeline", selection: $timelineMode) {
                ForEach(TimelineMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Picker("Speed", selection: Binding(
                get: { speedSelection(for: player.speed) },
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

    @ViewBuilder
    private var selectedAthleteSection: some View {
        if let selectedStartAthlete, let selectedEndAthlete, let selectedTransition {
            VStack(alignment: .leading, spacing: 16) {
                Text("Selected Athlete")
                    .font(.subheadline.weight(.semibold))

                HStack {
                    Circle()
                        .fill(selectedStartAthlete.role.color)
                        .frame(width: 14, height: 14)
                    Text(selectedStartAthlete.label)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Button {
                        selectedAthleteID = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Text("Starts at (\(Int(selectedStartAthlete.position.x)), \(Int(selectedStartAthlete.position.y))) and finishes at (\(Int(selectedEndAthlete.position.x)), \(Int(selectedEndAthlete.position.y))).")
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Starts moving after")
                    Slider(
                        value: Binding(
                            get: { selectedTransition.moveDelay },
                            set: { newValue in
                                store.mutateAthleteTransition(
                                    from: startFormationID,
                                    to: endFormationID,
                                    athleteID: selectedStartAthlete.id
                                ) { transition in
                                    transition.moveDelay = min(CGFloat(player.duration), max(0, newValue))
                                }
                                refreshFromStore()
                            }
                        ),
                        in: 0...CGFloat(player.duration),
                        step: 0.1
                    )
                    Text(String(format: "%.1fs", selectedTransition.moveDelay))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Path")
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

                    Text("Use the buttons to create the path, then double-tap the selected athlete on the court to add a waypoint and drag the handles to place it precisely.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !selectedTransition.pathWaypoints.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Waypoints")
                            .font(.subheadline.weight(.semibold))
                        ForEach(Array(selectedTransition.pathWaypoints.enumerated()), id: \.element.id) { waypointIndex, waypoint in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Waypoint \(waypointIndex + 1)")
                                        .font(.body.weight(.medium))
                                    Spacer()
                                    Button {
                                        store.mutateAthleteTransition(
                                            from: startFormationID,
                                            to: endFormationID,
                                            athleteID: selectedStartAthlete.id
                                        ) { transition in
                                            transition.pathWaypoints.remove(at: waypointIndex)
                                        }
                                        refreshFromStore()
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
                                        store.mutateAthleteTransition(
                                            from: startFormationID,
                                            to: endFormationID,
                                            athleteID: selectedStartAthlete.id
                                        ) { transition in
                                            transition.pathWaypoints[waypointIndex].isSmooth.toggle()
                                        }
                                        refreshFromStore()
                                    }
                                    .buttonStyle(.bordered)
                                }

                                HStack {
                                    Text("Hold")
                                    Spacer()
                                    Button("- 0.5s") {
                                        store.mutateAthleteTransition(
                                            from: startFormationID,
                                            to: endFormationID,
                                            athleteID: selectedStartAthlete.id
                                        ) { transition in
                                            transition.pathWaypoints[waypointIndex].holdDuration = max(
                                                0,
                                                transition.pathWaypoints[waypointIndex].holdDuration - 0.5
                                            )
                                        }
                                        refreshFromStore()
                                    }
                                    .buttonStyle(.bordered)

                                    Text(String(format: "%.1fs", waypoint.holdDuration))
                                        .font(.system(.body, design: .monospaced))
                                        .frame(width: 56)

                                    Button("+ 0.5s") {
                                        store.mutateAthleteTransition(
                                            from: startFormationID,
                                            to: endFormationID,
                                            athleteID: selectedStartAthlete.id
                                        ) { transition in
                                            transition.pathWaypoints[waypointIndex].holdDuration = min(
                                                10,
                                                transition.pathWaypoints[waypointIndex].holdDuration + 0.5
                                            )
                                        }
                                        refreshFromStore()
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(14)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
            }
        } else {
            EmptyInspectorView(
                title: "Path Inspector",
                message: "Select one athlete on the canvas to edit its start delay, curve, and waypoint timing."
            )
        }
    }

    private func canvasGesture(cellSize: CGFloat, offset: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let scaledPoint = CGPoint(
                    x: (value.location.x - offset.x) / cellSize,
                    y: (value.location.y - offset.y) / cellSize
                )
                let startScaledPoint = CGPoint(
                    x: (value.startLocation.x - offset.x) / cellSize,
                    y: (value.startLocation.y - offset.y) / cellSize
                )

                if let selectedAthleteID,
                    let startAthlete = player.startAthletes.first(where: { $0.id == selectedAthleteID }),
                    let endAthlete = player.endAthletes.first(where: { $0.id == selectedAthleteID })
                {
                    let transition = player.transitionSpec.athleteTransition(for: selectedAthleteID)

                    if !transition.pathWaypoints.isEmpty {
                        if let draggingWaypointID,
                            let waypointIndex = transition.pathWaypoints.firstIndex(where: { $0.id == draggingWaypointID })
                        {
                            isDraggingHandle = true
                            store.mutateAthleteTransition(
                                from: startFormationID,
                                to: endFormationID,
                                athleteID: selectedAthleteID
                            ) { transition in
                                transition.pathWaypoints[waypointIndex].position = scaledPoint
                            }
                            refreshFromStore()
                            return
                        }

                        for waypoint in transition.pathWaypoints {
                            if PathCalculations.squaredDistance(from: startScaledPoint, to: waypoint.position)
                                < CourtConstants.hitRadiusSquared
                            {
                                draggingWaypointID = waypoint.id
                                isDraggingHandle = true
                                return
                            }
                        }

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
                                let waypoint = PathWaypoint(position: midpoint, isSmooth: true)
                                store.mutateAthleteTransition(
                                    from: startFormationID,
                                    to: endFormationID,
                                    athleteID: selectedAthleteID
                                ) { transition in
                                    let insertIndex = min(segmentIndex, transition.pathWaypoints.count)
                                    transition.pathWaypoints.insert(waypoint, at: insertIndex)
                                    transition.pathControlPoint = nil
                                }
                                draggingWaypointID = waypoint.id
                                isDraggingHandle = true
                                refreshFromStore()
                                return
                            }
                        }
                    } else {
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

                        if isDraggingHandle
                            || PathCalculations.squaredDistance(from: startScaledPoint, to: midpoint)
                                < CourtConstants.hitRadiusSquared
                        {
                            isDraggingHandle = true
                            let newControlPoint = CGPoint(
                                x: 2 * scaledPoint.x - 0.5 * startAthlete.position.x - 0.5 * endAthlete.position.x,
                                y: 2 * scaledPoint.y - 0.5 * startAthlete.position.y - 0.5 * endAthlete.position.y
                            )
                            store.mutateAthleteTransition(
                                from: startFormationID,
                                to: endFormationID,
                                athleteID: selectedAthleteID
                            ) { transition in
                                transition.pathControlPoint = newControlPoint
                                transition.pathWaypoints = []
                            }
                            refreshFromStore()
                            return
                        }
                    }
                }

                if let athlete = player.currentAthletes.first(where: {
                    PathCalculations.squaredDistance(from: startScaledPoint, to: $0.position) < CourtConstants.hitRadiusSquared
                }) {
                    selectedAthleteID = athlete.id
                } else if !isDraggingHandle {
                    selectedAthleteID = nil
                }
            }
            .onEnded { _ in
                isDraggingHandle = false
                draggingWaypointID = nil
            }
    }

    private func waypointDoubleTapGesture(cellSize: CGFloat, offset: CGPoint) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                guard
                    let selectedAthleteID,
                    let selectedAthlete = player.currentAthletes.first(where: { $0.id == selectedAthleteID })
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

    private func clearPath() {
        guard let selectedAthleteID else { return }
        store.mutateAthleteTransition(from: startFormationID, to: endFormationID, athleteID: selectedAthleteID) { transition in
            transition.pathControlPoint = nil
            transition.pathWaypoints = []
        }
        refreshFromStore()
    }

    private func ensureCurve() {
        guard let selectedAthleteID, let startAthlete = selectedStartAthlete, let endAthlete = selectedEndAthlete else { return }

        store.mutateAthleteTransition(from: startFormationID, to: endFormationID, athleteID: selectedAthleteID) { transition in
            guard transition.pathControlPoint == nil && transition.pathWaypoints.isEmpty else { return }
            let midpoint = CGPoint(
                x: (startAthlete.position.x + endAthlete.position.x) / 2,
                y: (startAthlete.position.y + endAthlete.position.y) / 2
            )
            transition.pathControlPoint = CGPoint(x: midpoint.x, y: midpoint.y - 6)
        }
        refreshFromStore()
    }

    private func addWaypoint() {
        guard let selectedAthleteID, let startAthlete = selectedStartAthlete, let endAthlete = selectedEndAthlete else { return }

        store.mutateAthleteTransition(from: startFormationID, to: endFormationID, athleteID: selectedAthleteID) { transition in
            if transition.pathWaypoints.isEmpty {
                let point = transition.pathControlPoint
                    ?? CGPoint(
                        x: (startAthlete.position.x + endAthlete.position.x) / 2,
                        y: (startAthlete.position.y + endAthlete.position.y) / 2
                    )
                transition.pathWaypoints = [PathWaypoint(position: point, isSmooth: true)]
                transition.pathControlPoint = nil
            } else {
                let lastNode = transition.pathWaypoints.last?.position ?? startAthlete.position
                let point = CGPoint(
                    x: (lastNode.x + endAthlete.position.x) / 2,
                    y: (lastNode.y + endAthlete.position.y) / 2
                )
                transition.pathWaypoints.append(PathWaypoint(position: point, isSmooth: true))
            }
        }
        refreshFromStore()
    }

    private func speedSelection(for value: CGFloat) -> CGFloat {
        [CGFloat(0.5), 1.0, 1.5, 2.0]
            .min(by: { abs($0 - value) < abs($1 - value) }) ?? 1.0
    }

    private func refreshFromStore() {
        player.refresh(
            startAthletes: store.renderedAthletes(for: startFormationID),
            endAthletes: store.renderedAthletes(for: endFormationID),
            transitionSpec: store.transitionSpec(for: startFormationID, to: endFormationID)
        )
    }

    private func formatTime(_ seconds: CGFloat) -> String {
        String(format: "%.1fs", max(0, seconds))
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
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @StateObject private var store = RoutineStore()

        var body: some View {
            Group {
                if store.routine.formations.count > 1 {
                    TransitionPlayerView(
                        store: store,
                        startFormationID: store.routine.formations[0].id,
                        endFormationID: store.routine.formations[1].id
                    )
                } else {
                    Text("Preparing preview...")
                        .onAppear {
                            let startID = store.routine.formations[0].id
                            if store.routine.roster.isEmpty {
                                store.applyBowlingPinTemplate(to: startID)
                            }
                            _ = store.duplicateFormation(after: startID)
                        }
                }
            }
        }
    }

    return PreviewWrapper()
}
