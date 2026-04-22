import SwiftUI

// MARK: - Routine Playback View

struct RoutinePlaybackView: View {
    @StateObject private var player: RoutinePlayer
    @Environment(\.dismiss) private var dismiss

    init(store: RoutineStore) {
        _player = StateObject(wrappedValue: RoutinePlayer(store: store))
    }

    var body: some View {
        GeometryReader { geometry in
            let courtWidth = CourtConstants.width
            let courtHeight = CourtConstants.height
            let availableWidth = geometry.size.width - 40  // 20pt padding each side
            let availableHeight = geometry.size.height - 140  // room for transport bar
            let cellSize = min(availableWidth / courtWidth, availableHeight / courtHeight)
            let gridWidth = courtWidth * cellSize
            let gridHeight = courtHeight * cellSize
            let offsetX = (geometry.size.width - gridWidth) / 2
            let offsetY = (geometry.size.height - 140 - gridHeight) / 2 + 20

            ZStack {
                Color.black.ignoresSafeArea()

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
                .ignoresSafeArea()

                // Close button
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

                // Transport bar
                VStack {
                    Spacer()
                    routineTransportBar
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
            }
        }
        .statusBarHidden()
        .onAppear {
            player.play()
        }
    }

    // MARK: - Transport Bar

    private var routineTransportBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Formation name
            HStack {
                Text(player.currentFormationName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.12), in: Capsule())
                    .onTapGesture {
                        player.jumpToNextSegment()
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Jumps to the next formation")
                    .help("Jumps to the next formation")

                Spacer()

                Text("\(player.currentSegmentIndex + 1) / \(player.segmentCount)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            // Scrub bar with segment markers
            ZStack(alignment: .leading) {
                Slider(
                    value: Binding(
                        get: { player.progress },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...1
                )
                .accessibilityLabel("Routine progress")

                // Segment marker ticks
                GeometryReader { geo in
                    ForEach(player.segmentMarkers.indices, id: \.self) { index in
                        let marker = player.segmentMarkers[index]
                        Rectangle()
                            .fill(Color.white.opacity(0.5))
                            .frame(width: 2, height: 12)
                            .position(x: marker * geo.size.width, y: geo.size.height / 2)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(height: 36)

            // Controls row
            HStack(spacing: 12) {
                // Play/Pause
                Button {
                    player.isPlaying ? player.pause() : player.play()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                .accessibilityValue(player.isPlaying ? "Playing" : "Paused")
                .accessibilityHint(player.isPlaying ? "Pause the routine playback" : "Play the routine animation")
                .help(player.isPlaying ? "Pause the routine playback" : "Play the routine animation")

                // Reset
                Button(action: player.reset) {
                    Image(systemName: "backward.end.fill")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Reset playback")
                .accessibilityHint("Jump back to the start of the routine")
                .help("Jump back to the start of the routine")

                Spacer()

                // Speed picker
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
                .frame(width: 180)
                .accessibilityLabel("Playback Speed")
                .accessibilityHint("Adjust the playback speed of the routine animation")

                // Trail toggle
                Button {
                    player.showTrail.toggle()
                } label: {
                    Image(systemName: "sparkles")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .tint(player.showTrail ? .orange : .secondary)
                .accessibilityLabel("Toggle trails")
                .accessibilityValue(player.showTrail ? "On" : "Off")
                .accessibilityHint(player.showTrail ? "Hide movement trails" : "Show movement trails for the athletes")
                .help(player.showTrail ? "Hide movement trails" : "Show movement trails for the athletes")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        }
        .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
    }
}
