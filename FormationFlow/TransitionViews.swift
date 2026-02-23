import SwiftUI

// MARK: - Transition Picker View (launched from editor toolbar)

struct TransitionPickerView: View {
    let startFormation: Formation
    @StateObject private var persistenceManager = PersistenceManager.shared

    var otherFormations: [Formation] {
        persistenceManager.formations.filter { $0.id != startFormation.id }
    }

    var body: some View {
        Group {
            if otherFormations.isEmpty {
                ContentUnavailableView(
                    "No Other Formations",
                    systemImage: "arrow.left.arrow.right",
                    description: Text(
                        "Save another formation first, then come back to preview the transition.")
                )
            } else {
                List {
                    Section("Transition from") {
                        HStack(spacing: 12) {
                            FormationThumbnailView(formation: startFormation)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.gray.opacity(0.3)))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(startFormation.name).font(.headline)
                                Text("\(startFormation.athletes.count) athletes")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    Section("Transition to...") {
                        ForEach(otherFormations) { formation in
                            NavigationLink(
                                destination: TransitionPlayerView(
                                    startFormation: startFormation,
                                    endFormation: formation
                                )
                            ) {
                                HStack(spacing: 12) {
                                    FormationThumbnailView(formation: formation)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color.gray.opacity(0.3)))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(formation.name).font(.headline)
                                        Text("\(formation.athletes.count) athletes")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Preview Transition")
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

    let gridCols: CGFloat = 52
    let gridRows: CGFloat = 30

    init(startFormation: Formation, endFormation: Formation) {
        _player = StateObject(
            wrappedValue: TransitionPlayer(from: startFormation, to: endFormation))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Bug 1 fix: centered canvas using GeometryReader
            GeometryReader { geometry in
                let cellSize = min(geometry.size.width / gridCols, geometry.size.height / gridRows)
                let canvasWidth = gridCols * cellSize
                let canvasHeight = gridRows * cellSize
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
                Text("Tap an athlete to adjust move timing")
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

                Button(action: { player.isLooping.toggle() }) {
                    Image(systemName: "repeat")
                        .font(.title2)
                        .foregroundColor(player.isLooping ? .blue : .primary)
                }
            }
            .padding()
        }
        .navigationTitle("\(player.startFormation.name) → \(player.endFormation.name)")
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
                        let u = 1.0 - t
                        let tt = t * t
                        let uu = u * u
                        let ut2 = 2.0 * u * t
                        midPoint = CGPoint(
                            x: uu * startPos.x + ut2 * c.x + tt * endPos.x,
                            y: uu * startPos.y + ut2 * c.y + tt * endPos.y
                        )
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

                    let dx = startScaledPoint.x - midPoint.x
                    let dy = startScaledPoint.y - midPoint.y
                    if isDraggingHandle || (dx * dx + dy * dy) < 9.0 {
                        isDraggingHandle = true

                        // User's finger is dragging the midpoint. We need to back-calculate the Bezier control point 'c'.
                        // Formula for midpoint: M = 0.25*P0 + 0.5*c + 0.25*P2
                        // Solving for c: c = 2*M - 0.5*P0 - 0.5*P2

                        let newCx = 2 * scaledPoint.x - 0.5 * startPos.x - 0.5 * endPos.x
                        let newCy = 2 * scaledPoint.y - 0.5 * startPos.y - 0.5 * endPos.y

                        let newControlPoint = CGPoint(x: newCx, y: newCy)
                        if player.startFormation.athletes[index].pathControlPoint != newControlPoint {
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
                    let adx = initialScaledPoint.x - athlete.position.x
                    let ady = initialScaledPoint.y - athlete.position.y
                    if (adx * adx + ady * ady) < 9.0 {
                        selectedAthleteId = athlete.id
                        return
                    }
                }
                selectedAthleteId = nil
            }
            .onEnded { _ in
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
        let count = min(start.athletes.count, player.endFormation.athletes.count)
        var newKey: [PathCollisionKey] = []
        newKey.reserveCapacity(count)

        for i in 0..<count {
            newKey.append(
                PathCollisionKey(
                    id: start.athletes[i].id,
                    startPosition: start.athletes[i].position,
                    endPosition: player.endFormation.athletes[i].position,
                    controlPoint: start.athletes[i].pathControlPoint
                ))
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
