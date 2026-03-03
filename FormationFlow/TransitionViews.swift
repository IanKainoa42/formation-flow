import SwiftUI

// MARK: - Transition Picker View (launched from editor toolbar)

struct TransitionPickerView: View {
    let startFormation: Formation
    @StateObject private var persistenceManager = PersistenceManager.shared
    @State private var newFormationDestination: Formation?

    private var otherFormations: [Formation] {
        persistenceManager.formations.filter { $0.id != startFormation.id }
    }

    var body: some View {
        List {
            // Start formation (current)
            Section {
                HStack(spacing: 12) {
                    FormationThumbnailView(formation: startFormation)
                        .frame(width: 80, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.blue, lineWidth: 2))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(startFormation.name)
                            .font(.headline)
                        Text("\(startFormation.athletes.count) athletes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("START")
                        .font(.caption2.bold())
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                }
                .listRowBackground(Color.blue.opacity(0.05))
            } header: {
                Text("Transitioning From")
            }

            // Other formations to transition to
            Section {
                if otherFormations.isEmpty {
                    Text("Create another formation to animate transitions between them. Athletes will move from their positions here to their positions in the other formation.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(otherFormations) { formation in
                        NavigationLink(
                            destination: TransitionPlayerView(
                                startFormation: startFormation,
                                endFormation: formation
                            )
                        ) {
                            HStack(spacing: 12) {
                                FormationThumbnailView(formation: formation)
                                    .frame(width: 80, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.gray.opacity(0.3)))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(formation.name)
                                        .font(.headline)
                                    Text("\(formation.athletes.count) athletes")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            } header: {
                Text("Transition To")
            } footer: {
                Text("Athletes are matched by their position in the roster. Use Manage Athletes to reorder.")
            }

            // Add new formation
            Section {
                Button(action: addFormation) {
                    Label("New Formation", systemImage: "plus.circle.fill")
                        .font(.body.bold())
                }
            }
        }
        .navigationTitle("Transitions")
        .navigationDestination(item: $newFormationDestination) { formation in
            TransitionPlayerView(
                startFormation: startFormation,
                endFormation: formation
            )
        }
    }

    private func addFormation() {
        let n = persistenceManager.formations.count + 1
        var formation = Formation()
        formation.name = "Formation \(n)"
        // Copy the same athletes so there's a 1-to-1 mapping for transition paths
        formation.athletes = startFormation.athletes.map { athlete in
            Athlete(id: athlete.id, label: athlete.label, position: athlete.position, role: athlete.role)
        }
        persistenceManager.addFormation(formation)
        newFormationDestination = formation
    }
}

// MARK: - Transition Player View

struct TransitionPlayerView: View {
    private struct PathCollisionKey: Equatable {
        let id: UUID
        let startPosition: CGPoint
        let endPosition: CGPoint
        let controlPoint: CGPoint?
    }

    @StateObject private var player: TransitionPlayer
    @StateObject private var persistenceManager = PersistenceManager.shared
    @State private var selectedAthleteId: UUID?
    @State private var countMode: Bool = false
    @State private var countsPerTransition: Int = 8
    @State private var isDraggingHandle = false
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
                    selectedAthleteId: selectedAthleteId,
                    startFormation: player.startFormation,
                    endFormation: player.endFormation,
                    pathCollisionIndices: pathCollisionIndices,
                    cellSize: cellSize,
                    offset: canvasOffset
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

            if let selectedId = selectedAthleteId,
                let index = player.startFormation.athletes.firstIndex(where: { $0.id == selectedId }
                )
            {
                HStack(alignment: .top) {
                    TimingControlsView(
                        athlete: Binding(
                            get: { player.startFormation.athletes[index] },
                            set: { newAthlete in
                                player.startFormation.athletes[index] = newAthlete
                                player.seek(to: player.progress)
                            }
                        ),
                        duration: player.duration
                    )

                    if player.startFormation.athletes[index].pathControlPoint != nil {
                        Button(action: {
                            player.startFormation.athletes[index].pathControlPoint = nil
                            player.seek(to: player.progress)
                        }) {
                            Label("Straight", systemImage: "arrow.right")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.15))
                                .cornerRadius(6)
                        }
                        .padding(.top, 12)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            } else {
                Text("Tap an athlete to adjust timing \u{00B7} Drag path midpoint to curve it")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }

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
        .navigationTitle("\(player.startFormation.name) → \(player.endFormation.name)")
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
            if !isDraggingHandle {
                persistenceManager.updateFormation(newFormation)
            }
            updatePathCollisionCache(start: newFormation)
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

                // If an athlete is already selected, check if we're dragging their curve handle
                if let selectedId = selectedAthleteId,
                    let index = player.startFormation.athletes.firstIndex(where: {
                        $0.id == selectedId
                    }),
                    index < player.endFormation.athletes.count
                {

                    let startPos = player.startFormation.athletes[index].position
                    let endPos = player.endFormation.athletes[index].position
                    let currentControl = player.startFormation.athletes[index].pathControlPoint

                    // Determine where the current midpoint is
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

                    // Check if initial touch was near the handle (allow generous tap target: roughly 3 feet distance)
                    let startScaledPoint = CGPoint(
                        x: (value.startLocation.x - offset.x) / cellSize,
                        y: (value.startLocation.y - offset.y) / cellSize
                    )

                    if isDraggingHandle
                        || PathCalculations.squaredDistance(from: startScaledPoint, to: midPoint)
                            < CourtConstants.hitRadiusSquared
                    {
                        isDraggingHandle = true

                        // User's finger is dragging the midpoint. We need to back-calculate the Bezier control point 'c'.
                        // Formula for midpoint: M = 0.25*P0 + 0.5*c + 0.25*P2
                        // Solving for c: c = 2*M - 0.5*P0 - 0.5*P2

                        let newCx = 2 * scaledPoint.x - 0.5 * startPos.x - 0.5 * endPos.x
                        let newCy = 2 * scaledPoint.y - 0.5 * startPos.y - 0.5 * endPos.y

                        let newControlPoint = CGPoint(x: newCx, y: newCy)
                        if player.startFormation.athletes[index].pathControlPoint != newControlPoint
                        {
                            player.startFormation.athletes[index].pathControlPoint = newControlPoint
                            player.seek(to: player.progress)  // force refresh
                        }
                        return
                    }
                }

                // Normal athlete selection
                let initialScaledPoint = CGPoint(
                    x: (value.startLocation.x - offset.x) / cellSize,
                    y: (value.startLocation.y - offset.y) / cellSize
                )

                for athlete in player.currentFormation.athletes {
                    if PathCalculations.squaredDistance(
                        from: initialScaledPoint, to: athlete.position)
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
                                persistenceManager.updateFormation(player.endFormation)
                            } else {
                                player.startFormation.swapAthletePositions(
                                    id1: sourceId, id2: athlete.id)
                                persistenceManager.updateFormation(player.startFormation)
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

                if isDraggingHandle {
                    persistenceManager.updateFormation(player.startFormation)
                }
                isDraggingHandle = false
            }
    }

    private func formatTime(_ seconds: CGFloat) -> String {
        String(format: "%.1fs", max(0, seconds))
    }

    private func updatePathCollisionCache(start: Formation, force: Bool = false) {
        var newKey: [PathCollisionKey] = []
        newKey.reserveCapacity(start.athletes.count)

        for startAthlete in start.athletes {
            if let endAthlete = player.endFormation.athletes.first(where: { $0.id == startAthlete.id }) {
                newKey.append(
                    PathCollisionKey(
                        id: startAthlete.id,
                        startPosition: startAthlete.position,
                        endPosition: endAthlete.position,
                        controlPoint: startAthlete.pathControlPoint
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
            startFormation: Formation.sample(),
            endFormation: {
                var end = Formation.sample()
                end.id = UUID()
                end.name = "End"
                for i in 0..<end.athletes.count {
                    end.athletes[i].position.x += 10
                }
                return end
            }()
        )
    }
}
