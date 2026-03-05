import SwiftUI

// MARK: - Transition Player View

struct TransitionPlayerView: View {
    private struct PathCollisionKey: Equatable {
        let id: UUID
        let startPosition: CGPoint
        let endPosition: CGPoint
        let controlPoint: CGPoint?
        let waypoints: [PathWaypoint]
    }

    @StateObject private var player: TransitionPlayer
    @State private var selectedAthleteId: UUID?
    @State private var countMode: Bool = false
    @State private var countsPerTransition: Int = 8
    @State private var isDraggingHandle = false
    @State private var draggingWaypointId: UUID?
    @State private var pathCollisionIndices: Set<Int> = []
    @State private var pathCollisionKey: [PathCollisionKey] = []
    @State private var isSwapMode = false
    @State private var swapSourceAthleteId: UUID?
    @State private var swapTargetIsEnd = false

    init(startFormation: Formation, endFormation: Formation) {
        _player = StateObject(
            wrappedValue: TransitionPlayer(from: startFormation, to: endFormation))
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let cellSize = min(
                    geometry.size.width / CourtConstants.width,
                    geometry.size.height / CourtConstants.height)
                let canvasWidth = CourtConstants.width * cellSize
                let canvasHeight = CourtConstants.height * cellSize
                let offsetX = (geometry.size.width - canvasWidth) / 2
                let offsetY = (geometry.size.height - canvasHeight) / 2
                let canvasOffset = CGPoint(x: offsetX, y: offsetY)

                FloorCanvasView(
                    formation: player.currentFormation,
                    selectedAthleteIds: selectedAthleteId.map { Set([$0]) } ?? [],
                    startFormation: player.startFormation,
                    endFormation: player.endFormation,
                    pathCollisionIndices: pathCollisionIndices,
                    cellSize: cellSize,
                    offset: canvasOffset,
                    swapSourceId: swapSourceAthleteId
                )
                .gesture(athleteTapGesture(cellSize: cellSize, offset: canvasOffset))

                // Swap mode banner
                if isSwapMode, let sourceId = swapSourceAthleteId,
                    let sourceAthlete = player.startFormation.athletes.first(where: {
                        $0.id == sourceId
                    })
                        ?? player.endFormation.athletes.first(where: { $0.id == sourceId })
                {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "arrow.triangle.swap")
                            Text("Tap an athlete to swap with \(sourceAthlete.label)")
                                .font(.subheadline.bold())
                            Spacer()
                            Picker("", selection: $swapTargetIsEnd) {
                                Text("Start").tag(false)
                                Text("End").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 140)
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
            }

            Divider()

            VStack(spacing: 4) {
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
                    if countMode {
                        let currentCount = player.progress * CGFloat(countsPerTransition)
                        Text(String(format: "Count %.1f", currentCount))
                            .font(.caption.monospacedDigit())
                        Spacer()
                        Text("of \(countsPerTransition)")
                            .font(.caption.monospacedDigit())
                    } else {
                        Text(formatTime(player.progress * CGFloat(player.duration)))
                            .font(.caption.monospacedDigit())
                        Spacer()
                        Text(formatTime(CGFloat(player.duration)))
                            .font(.caption.monospacedDigit())
                    }
                }
                .foregroundColor(.gray)

                if countMode {
                    Divider().padding(.horizontal)
                    HStack(spacing: 0) {
                        ForEach(1...countsPerTransition, id: \.self) { count in
                            Text("\(count)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            selectedAthleteTimingBar

            HStack {
                Text("Duration")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Stepper(
                    "\(String(format: "%.1f", player.duration))s",
                    value: Binding(
                        get: { player.duration },
                        set: { player.duration = max(0.5, $0) }
                    ),
                    in: 0.5...30,
                    step: 0.5
                )
                .font(.caption)
            }
            .padding(.horizontal)

            HStack(spacing: 30) {
                Menu {
                    Button("0.25x") { player.speed = 0.25 }
                    Button("0.5x") { player.speed = 0.5 }
                    Button("1x") { player.speed = 1.0 }
                    Button("1.5x") { player.speed = 1.5 }
                    Button("2x") { player.speed = 2.0 }
                } label: {
                    Text("\(String(format: "%.2g", player.speed))x")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)
                }

                Menu {
                    Button("Seconds") { countMode = false }
                    Divider()
                    Button("4 counts") {
                        countMode = true
                        countsPerTransition = 4
                    }
                    Button("8 counts") {
                        countMode = true
                        countsPerTransition = 8
                    }
                    Button("16 counts") {
                        countMode = true
                        countsPerTransition = 16
                    }
                } label: {
                    Text(countMode ? "\(countsPerTransition)ct" : "sec")
                        .font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(countMode ? Color.blue : Color.gray.opacity(0.2))
                        .foregroundColor(countMode ? .white : .primary)
                        .cornerRadius(4)
                }

                Button(action: { player.reset() }) {
                    Image(systemName: "backward.end.fill")
                        .font(.title2)
                }
                .accessibilityLabel("Reset to beginning")

                Button(action: {
                    if player.isPlaying {
                        player.pause()
                    } else {
                        player.play()
                    }
                }) {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.largeTitle)
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                Button(action: { player.isLooping.toggle() }) {
                    Image(systemName: "repeat")
                        .font(.title2)
                        .foregroundColor(player.isLooping ? .blue : .primary)
                }
                .accessibilityLabel("Loop playback")
                .accessibilityAddTraits(player.isLooping ? .isSelected : [])
            }
            .padding()
        }
        .toolbar {
            #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        if let selectedId = selectedAthleteId {
                            swapSourceAthleteId = selectedId
                            isSwapMode = true
                        }
                    }) {
                        Image(systemName: "arrow.triangle.swap")
                    }
                    .disabled(selectedAthleteId == nil || isSwapMode)
                }
            #else
                ToolbarItem {
                    Button(action: {
                        if let selectedId = selectedAthleteId {
                            swapSourceAthleteId = selectedId
                            isSwapMode = true
                        }
                    }) {
                        Image(systemName: "arrow.triangle.swap")
                    }
                    .disabled(selectedAthleteId == nil || isSwapMode)
                }
            #endif
        }
        .onAppear {
            updatePathCollisionCache(start: player.startFormation, force: true)
        }
        .onChange(of: player.startFormation) { _, newFormation in
            updatePathCollisionCache(start: newFormation)
        }
    }

    private func athleteTimingBinding(id: UUID) -> Binding<Double> {
        Binding<Double>(
            get: {
                guard let i = player.startFormation.athletes.firstIndex(where: { $0.id == id })
                else { return 0 }
                return player.startFormation.athletes[i].moveTiming
            },
            set: { newVal in
                guard let i = player.startFormation.athletes.firstIndex(where: { $0.id == id })
                else { return }
                player.startFormation.athletes[i].moveTiming = newVal
                player.seek(to: player.progress)
            }
        )
    }

    @ViewBuilder
    private var selectedAthleteTimingBar: some View {
        if let selectedId = selectedAthleteId,
            let i = player.startFormation.athletes.firstIndex(where: { $0.id == selectedId })
        {
            let athlete = player.startFormation.athletes[i]
            HStack(spacing: 8) {
                Text("\(athlete.label) delay:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Slider(
                    value: athleteTimingBinding(id: selectedId),
                    in: 0...max(player.duration, 0.1),
                    step: 0.1
                )
                Text(String(format: "%.1fs", athlete.moveTiming))
                    .font(.caption.monospacedDigit())
                    .frame(width: 36, alignment: .trailing)

                if !athlete.pathWaypoints.isEmpty || athlete.pathControlPoint != nil {
                    Button(action: {
                        player.startFormation.athletes[i].pathWaypoints = []
                        player.startFormation.athletes[i].pathControlPoint = nil
                        player.seek(to: player.progress)
                    }) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.caption)
                    }
                }

                Button(action: { selectedAthleteId = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.top, 4)

            if !athlete.pathWaypoints.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(
                            Array(athlete.pathWaypoints.enumerated()),
                            id: \.element.id
                        ) { wpIdx, waypoint in
                            VStack(spacing: 4) {
                                // Top row: label, smooth/sharp toggle, delete
                                HStack(spacing: 4) {
                                    Text("WP\(wpIdx + 1)")
                                        .font(.system(size: 11, weight: .bold))
                                    Button(action: {
                                        player.startFormation.athletes[i]
                                            .pathWaypoints[wpIdx].isSmooth.toggle()
                                        player.seek(to: player.progress)
                                    }) {
                                        Image(systemName: waypoint.isSmooth ? "line.diagonal" : "chevron.right")
                                            .font(.system(size: 11))
                                    }
                                    Spacer()
                                    Button(action: {
                                        player.startFormation.athletes[i]
                                            .pathWaypoints.remove(at: wpIdx)
                                        player.seek(to: player.progress)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(.red)
                                    }
                                }

                                Divider()

                                // Bottom row: hold duration with +/- buttons
                                HStack(spacing: 6) {
                                    Image(systemName: "pause.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(waypoint.holdDuration > 0 ? .orange : .secondary)
                                    Button(action: {
                                        let current = player.startFormation.athletes[i].pathWaypoints[wpIdx].holdDuration
                                        player.startFormation.athletes[i].pathWaypoints[wpIdx].holdDuration = max(0, current - 0.5)
                                        player.seek(to: player.progress)
                                    }) {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(waypoint.holdDuration > 0 ? .primary : .gray.opacity(0.3))
                                    }
                                    .disabled(waypoint.holdDuration <= 0)
                                    Text(String(format: "%.1fs", waypoint.holdDuration))
                                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                                        .foregroundColor(waypoint.holdDuration > 0 ? .orange : .secondary)
                                        .frame(minWidth: 32)
                                    Button(action: {
                                        let current = player.startFormation.athletes[i].pathWaypoints[wpIdx].holdDuration
                                        player.startFormation.athletes[i].pathWaypoints[wpIdx].holdDuration = min(10, current + 0.5)
                                        player.seek(to: player.progress)
                                    }) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(.primary)
                                    }
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(minWidth: 100)
                            .background(waypoint.holdDuration > 0 ? Color.orange.opacity(0.1) : Color.gray.opacity(0.08))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(waypoint.holdDuration > 0 ? Color.orange.opacity(0.4) : Color.gray.opacity(0.2), lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 2)
            }
        }
    }

    private func athleteTapGesture(cellSize: CGFloat, offset: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // In swap mode, skip normal drag/selection
                if isSwapMode { return }

                let scaledPoint = CGPoint(
                    x: (value.location.x - offset.x) / cellSize,
                    y: (value.location.y - offset.y) / cellSize
                )
                let startScaledPoint = CGPoint(
                    x: (value.startLocation.x - offset.x) / cellSize,
                    y: (value.startLocation.y - offset.y) / cellSize
                )

                // If an athlete is already selected, check if we're dragging a waypoint or handle
                if let selectedId = selectedAthleteId,
                    let index = player.startFormation.athletes.firstIndex(where: {
                        $0.id == selectedId
                    }),
                    index < player.endFormation.athletes.count
                {
                    let athlete = player.startFormation.athletes[index]
                    let startPos = athlete.position
                    let endPos = player.endFormation.athletes[index].position

                    // --- Multi-waypoint mode ---
                    if !athlete.pathWaypoints.isEmpty {
                        // Check if we're already dragging a waypoint
                        if let dragId = draggingWaypointId {
                            isDraggingHandle = true
                            if let wpIdx = player.startFormation.athletes[index].pathWaypoints
                                .firstIndex(where: { $0.id == dragId })
                            {
                                player.startFormation.athletes[index].pathWaypoints[wpIdx]
                                    .position = scaledPoint
                                player.seek(to: player.progress)
                            }
                            return
                        }

                        // Check if initial touch is near any waypoint handle
                        for wp in athlete.pathWaypoints {
                            if PathCalculations.squaredDistance(
                                from: startScaledPoint, to: wp.position)
                                < CourtConstants.hitRadiusSquared
                            {
                                draggingWaypointId = wp.id
                                isDraggingHandle = true
                                return
                            }
                        }

                        // Check if initial touch is near a "+" segment midpoint (to insert waypoint)
                        let nodes = PathCalculations.waypointNodes(
                            from: startPos, to: endPos, waypoints: athlete.pathWaypoints)
                        for segIdx in 0..<(nodes.count - 1) {
                            let mid = CGPoint(
                                x: (nodes[segIdx].x + nodes[segIdx + 1].x) / 2,
                                y: (nodes[segIdx].y + nodes[segIdx + 1].y) / 2
                            )
                            if PathCalculations.squaredDistance(from: startScaledPoint, to: mid)
                                < CourtConstants.hitRadiusSquared
                            {
                                // Insert a new waypoint at this segment midpoint
                                let newWp = PathWaypoint(position: mid, isSmooth: true)
                                let insertIdx = min(
                                    segIdx,
                                    player.startFormation.athletes[index].pathWaypoints.count)
                                player.startFormation.athletes[index].pathWaypoints.insert(
                                    newWp, at: insertIdx)
                                draggingWaypointId = newWp.id
                                isDraggingHandle = true
                                player.seek(to: player.progress)
                                return
                            }
                        }
                    } else {
                        // --- Legacy single-control-point mode ---
                        let currentControl = athlete.pathControlPoint
                        let t: CGFloat = 0.5
                        let midPoint: CGPoint
                        if let c = currentControl {
                            midPoint = PathCalculations.quadraticBezierPoint(
                                from: startPos, control: c, to: endPos, t: t)
                        } else {
                            midPoint = CGPoint(
                                x: startPos.x + (endPos.x - startPos.x) * t,
                                y: startPos.y + (endPos.y - startPos.y) * t
                            )
                        }

                        if isDraggingHandle
                            || PathCalculations.squaredDistance(
                                from: startScaledPoint, to: midPoint)
                                < CourtConstants.hitRadiusSquared
                        {
                            isDraggingHandle = true

                            let newCx = 2 * scaledPoint.x - 0.5 * startPos.x - 0.5 * endPos.x
                            let newCy = 2 * scaledPoint.y - 0.5 * startPos.y - 0.5 * endPos.y

                            let newControlPoint = CGPoint(x: newCx, y: newCy)
                            if player.startFormation.athletes[index].pathControlPoint
                                != newControlPoint
                            {
                                player.startFormation.athletes[index].pathControlPoint =
                                    newControlPoint
                                player.seek(to: player.progress)
                            }
                            return
                        }
                    }
                }

                // Normal athlete selection
                for athlete in player.currentFormation.athletes {
                    if PathCalculations.squaredDistance(
                        from: startScaledPoint, to: athlete.position)
                        < CourtConstants.hitRadiusSquared
                    {
                        selectedAthleteId = athlete.id
                        return
                    }
                }
                selectedAthleteId = nil
            }
            .onEnded { value in
                // Handle swap mode tap
                if isSwapMode, let sourceId = swapSourceAthleteId {
                    let tapScaled = CGPoint(
                        x: (value.location.x - offset.x) / cellSize,
                        y: (value.location.y - offset.y) / cellSize
                    )

                    let athletes =
                        swapTargetIsEnd
                        ? player.endFormation.athletes
                        : player.startFormation.athletes

                    for athlete in athletes {
                        if athlete.id != sourceId,
                            PathCalculations.squaredDistance(from: tapScaled, to: athlete.position)
                                < CourtConstants.hitRadiusSquared
                        {
                            if swapTargetIsEnd {
                                player.endFormation.swapAthletePositions(
                                    id1: sourceId, id2: athlete.id)
                            } else {
                                player.startFormation.swapAthletePositions(
                                    id1: sourceId, id2: athlete.id)
                            }
                            player.seek(to: player.progress)
                            isSwapMode = false
                            swapSourceAthleteId = nil
                            return
                        }
                    }

                    // Tapped background — cancel
                    isSwapMode = false
                    swapSourceAthleteId = nil
                    selectedAthleteId = nil
                    return
                }

                isDraggingHandle = false
                draggingWaypointId = nil
            }
    }

    private func formatTime(_ seconds: CGFloat) -> String {
        String(format: "%.1fs", max(0, seconds))
    }

    private func updatePathCollisionCache(start: Formation, force: Bool = false) {
        var newKey: [PathCollisionKey] = []
        newKey.reserveCapacity(start.athletes.count)

        for startAthlete in start.athletes {
            if let endAthlete = player.endFormation.athletes.first(where: {
                $0.id == startAthlete.id
            }) {
                newKey.append(
                    PathCollisionKey(
                        id: startAthlete.id,
                        startPosition: startAthlete.position,
                        endPosition: endAthlete.position,
                        controlPoint: startAthlete.pathControlPoint,
                        waypoints: startAthlete.pathWaypoints
                    ))
            }
        }

        guard force || newKey != pathCollisionKey else { return }
        pathCollisionKey = newKey
        pathCollisionIndices = PathCalculations.findPathCollisionIndices(
            start: start, end: player.endFormation)
    }
}

// MARK: - Previews

#Preview("Transition Player") {
    NavigationStack {
        TransitionPlayerView(
            startFormation: Formation.bowlingPin(name: "Start"),
            endFormation: {
                var end = Formation.bowlingPin(name: "End")
                end.id = UUID()
                for i in 0..<end.athletes.count {
                    end.athletes[i].position.x += 10
                }
                return end
            }()
        )
    }
}
