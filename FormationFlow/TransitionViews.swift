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
                    description: Text("Save another formation first, then come back to preview the transition.")
                )
            } else {
                List {
                    Section {
                        Text("Starting from: \\(startFormation.name)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Section("Transition to...") {
                        ForEach(otherFormations) { formation in
                            NavigationLink(destination: TransitionPlayerView(
                                startFormation: startFormation,
                                endFormation: formation
                            )) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(formation.name).font(.headline)
                                    Text("\\(formation.athletes.count) athletes")
                                        .font(.caption)
                                        .foregroundColor(.gray)
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

// MARK: - Transition Setup View (accessible from main menu)

struct TransitionSetupView: View {
    @StateObject private var persistenceManager = PersistenceManager.shared
    @State private var startFormationId: UUID?
    @State private var endFormationId: UUID?

    private var startFormation: Formation? {
        persistenceManager.formations.first(where: { $0.id == startFormationId })
    }

    private var endFormation: Formation? {
        persistenceManager.formations.first(where: { $0.id == endFormationId })
    }

    var body: some View {
        Group {
            if persistenceManager.formations.count < 2 {
                ContentUnavailableView(
                    "Need 2+ Formations",
                    systemImage: "arrow.left.arrow.right",
                    description: Text("Create at least two formations to preview a transition.")
                )
            } else {
                Form {
                    Section("Start Formation") {
                        Picker("Start", selection: $startFormationId) {
                            Text("Select...").tag(nil as UUID?)
                            ForEach(persistenceManager.formations) { f in
                                Text("\\(f.name) (\\(f.athletes.count) athletes)").tag(f.id as UUID?)
                            }
                        }
                    }

                    Section("End Formation") {
                        Picker("End", selection: $endFormationId) {
                            Text("Select...").tag(nil as UUID?)
                            ForEach(persistenceManager.formations) { f in
                                Text("\\(f.name) (\\(f.athletes.count) athletes)").tag(f.id as UUID?)
                            }
                        }
                    }

                    if let start = startFormation, let end = endFormation {
                        Section {
                            if start.athletes.count != end.athletes.count {
                                Label("Athlete count differs (\\(start.athletes.count) vs \\(end.athletes.count)). Extra athletes stay in place.",
                                      systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }

                            NavigationLink("Play Transition") {
                                TransitionPlayerView(startFormation: start, endFormation: end)
                            }
                            .font(.headline)
                        }
                    }
                }
            }
        }
        .navigationTitle("Transitions")
    }
}

// MARK: - Transition Player View

struct TransitionPlayerView: View {
    @StateObject private var player: TransitionPlayer
    @State private var selectedAthleteId: UUID?
    @State private var countMode: Bool = false

    let gridCols: CGFloat = 52
    let gridRows: CGFloat = 30

    init(startFormation: Formation, endFormation: Formation) {
        _player = StateObject(wrappedValue: TransitionPlayer(from: startFormation, to: endFormation))
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
                    cellSize: cellSize,
                    offset: canvasOffset
                )
                .gesture(athleteTapGesture(cellSize: cellSize, offset: canvasOffset))
            }

            Divider()

            if let selectedId = selectedAthleteId,
               let index = player.startFormation.athletes.firstIndex(where: { $0.id == selectedId }) {
                TimingControlsView(athlete: Binding(
                    get: { player.startFormation.athletes[index] },
                    set: { newAthlete in
                        player.startFormation.athletes[index] = newAthlete
                        player.seek(to: player.progress)
                    }
                ))
                .padding(.horizontal)
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
                        let currentCount = player.progress * 8
                        Text(String(format: "Count %.1f", currentCount))
                            .font(.caption.monospacedDigit())
                        Spacer()
                        Text("of 8")
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
                        ForEach(1...8, id: \\.self) { count in
                            Text("\\(count)")
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

            HStack(spacing: 30) {
                Menu {
                    Button("0.25x") { player.speed = 0.25 }
                    Button("0.5x") { player.speed = 0.5 }
                    Button("1x") { player.speed = 1.0 }
                    Button("2x") { player.speed = 2.0 }
                } label: {
                    Text("\\(String(format: "%.2g", player.speed))x")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)
                }

                Button(action: { countMode.toggle() }) {
                    Text(countMode ? "8ct" : "sec")
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
            }
            .padding()
        }
        .navigationTitle("Transition")
    }

    private func athleteTapGesture(cellSize: CGFloat, offset: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let scaledPoint = CGPoint(
                    x: (value.startLocation.x - offset.x) / cellSize,
                    y: (value.startLocation.y - offset.y) / cellSize
                )

                for athlete in player.currentFormation.athletes {
                    if hypot(scaledPoint.x - athlete.position.x,
                             scaledPoint.y - athlete.position.y) < 2.0 {
                        selectedAthleteId = athlete.id
                        return
                    }
                }
                selectedAthleteId = nil
            }
    }

    private func formatTime(_ seconds: CGFloat) -> String {
        String(format: "%.1fs", max(0, seconds))
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
