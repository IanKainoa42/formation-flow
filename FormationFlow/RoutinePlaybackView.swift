import SwiftUI

// MARK: - Routine Playback View

struct RoutinePlaybackView: View {
    @StateObject private var player: RoutinePlayer
    @Environment(\.dismiss) private var dismiss

    private static let bottomBarHeight: CGFloat = 56

    init(store: RoutineStore) {
        _player = StateObject(wrappedValue: RoutinePlayer(store: store))
    }

    var body: some View {
        GeometryReader { geometry in
            let courtWidth = CourtConstants.width
            let courtHeight = CourtConstants.height
            let availableWidth = geometry.size.width - 40
            let availableHeight = geometry.size.height - Self.bottomBarHeight - 40
            let cellSize = min(availableWidth / courtWidth, availableHeight / courtHeight)
            let gridWidth = courtWidth * cellSize
            let gridHeight = courtHeight * cellSize
            let offsetX = (geometry.size.width - gridWidth) / 2
            let offsetY = (geometry.size.height - Self.bottomBarHeight - gridHeight) / 2

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
                #if canImport(UIKit)
                // Two-finger tap = play/pause, two-finger horizontal drag = scrub.
                .background(
                    TwoFingerPlaybackGesture(
                        scrubEnabled: true,
                        onPlayToggle: { player.isPlaying ? player.pause() : player.play() },
                        currentProgress: { player.progress },
                        onScrubBegan: { player.pause() },
                        onSeek: { player.seek(to: $0) }
                    )
                )
                #endif

                VStack {
                    HStack(alignment: .top) {
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

                        // Same pip badge as the editor; editor-only bits (Into/Out
                        // tab, long-press rename) are omitted since linear playback
                        // has no selected formation. Left/right = jump segments.
                        FormationPipBadge(
                            currentIndex: player.currentSegmentIndex,
                            total: player.segmentCount,
                            formationName: player.currentFormationName,
                            onPrev: { player.jumpToPreviousSegment() },
                            onNext: { player.jumpToNextSegment() }
                        )
                        .padding(.top, 16)
                        .padding(.trailing, 16)
                    }
                    Spacer()
                }

                VStack(spacing: 0) {
                    Spacer()
                    routineTransportBar
                        .frame(height: Self.bottomBarHeight)
                }
            }
        }
        .statusBarHidden()
        .onAppear {
            player.play()
        }
    }

    // MARK: - Transport Bar (thin single row)

    private var routineTransportBar: some View {
        HStack(spacing: 10) {
            // Formation name + segment nav now live in the floating pip badge.
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
                Text("0.75x").tag(CGFloat(1.5))
                Text("1x").tag(CGFloat(2.0))
                Text("2x").tag(CGFloat(4.0))
                Text("4x").tag(CGFloat(8.0))
            }
            .pickerStyle(.segmented)
            .frame(width: 210)
            .controlSize(.small)
            .accessibilityLabel("Playback Speed")
            .accessibilityHint("Adjust the playback speed of the routine animation")

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
                Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("More playback options")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
