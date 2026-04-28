import SwiftUI

// MARK: - Routine Playback View

struct RoutinePlaybackView: View {
    @StateObject private var player: RoutinePlayer
    @Environment(\.dismiss) private var dismiss

    init(store: RoutineStore) {
        _player = StateObject(wrappedValue: RoutinePlayer(store: store))
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black

                GeometryReader { geometry in
                    let courtWidth = CourtConstants.width
                    let courtHeight = CourtConstants.height
                    let availableWidth = geometry.size.width - 40
                    let availableHeight = geometry.size.height - 40
                    let cellSize = min(availableWidth / courtWidth, availableHeight / courtHeight)
                    let gridWidth = courtWidth * cellSize
                    let gridHeight = courtHeight * cellSize
                    let offsetX = (geometry.size.width - gridWidth) / 2
                    let offsetY = (geometry.size.height - gridHeight) / 2

                    FloorCanvasView(
                        athletes: player.currentAthletes,
                        cellSize: cellSize,
                        offset: CGPoint(x: offsetX, y: offsetY),
                        hasTransition: true,
                        startFormationColor: TransitionEndpointMarkerRenderItem.rainbowColor(forIndex: player.currentSegmentIndex),
                        endFormationColor: TransitionEndpointMarkerRenderItem.rainbowColor(forIndex: player.currentSegmentIndex + 1),
                        transitionProgress: player.segmentProgress,
                        useRoleColors: false,
                        trailPositions: player.showTrail ? player.trailPositions : [:]
                    )
                }

                VStack {
                    HStack {
                        Button {
                            player.pause()
                            dismiss()
                        } label: {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .font(.body.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .padding(16)
                        .accessibilityLabel("Close")
                        .help("Close routine playback")

                        Spacer()
                    }
                    Spacer()
                }
            }

            routineTransportBar
        }
        .background(Color.black)
        .ignoresSafeArea()
        .statusBarHidden()
        .onAppear {
            player.play()
        }
    }

    // MARK: - Transport Bar (thin single row)

    private var routineTransportBar: some View {
        HStack(spacing: 10) {
            Text(player.currentFormationName)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.white.opacity(0.12), in: Capsule())
                .onTapGesture { player.jumpToNextSegment() }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Jumps to the next formation")
                .help("Jumps to the next formation")
                .frame(maxWidth: 160, alignment: .leading)

            Button {
                player.isPlaying ? player.pause() : player.play()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            .accessibilityValue(player.isPlaying ? "Playing" : "Paused")
            .help(player.isPlaying ? "Pause the routine playback" : "Play the routine animation")

            ZStack(alignment: .leading) {
                Slider(
                    value: Binding(
                        get: { player.progress },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...1
                )
                .accessibilityLabel("Routine progress")

                GeometryReader { geo in
                    ForEach(player.segmentMarkers.indices, id: \.self) { index in
                        let marker = player.segmentMarkers[index]
                        Rectangle()
                            .fill(Color.white.opacity(0.5))
                            .frame(width: 2, height: 8)
                            .position(x: marker * geo.size.width, y: geo.size.height / 2)
                            .allowsHitTesting(false)
                    }
                }
            }
            .layoutPriority(1)

            Picker("Speed", selection: Binding(
                get: { player.speed },
                set: { player.setSpeed($0) }
            )) {
                Text("0.5x").tag(CGFloat(1.0))
                Text("1x").tag(CGFloat(2.0))
                Text("2x").tag(CGFloat(4.0))
                Text("4x").tag(CGFloat(8.0))
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .controlSize(.small)
            .accessibilityLabel("Playback Speed")

            Menu {
                Text("\(player.currentSegmentIndex + 1) / \(player.segmentCount)")

                Button(action: player.reset) {
                    Label("Reset to Start", systemImage: "backward.end.fill")
                }

                Button {
                    player.showTrail.toggle()
                } label: {
                    Label(
                        player.showTrail ? "Hide Trails" : "Show Trails",
                        systemImage: "sparkles"
                    )
                }
            } label: {
                Image(systemName: "ellipsis.circle").frame(width: 28, height: 28)
            }
            .accessibilityLabel("More playback options")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
