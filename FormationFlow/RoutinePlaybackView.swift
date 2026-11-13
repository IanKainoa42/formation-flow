import SwiftUI

// MARK: - Routine Playback View

struct RoutinePlaybackView: View {
    @StateObject private var player: RoutinePlayer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.editorLayoutContext) private var editorLayout

    private static let bottomBarHeight: CGFloat = 64

    private var isPhoneLayout: Bool { editorLayout.isPhone }
    private var isPhoneLandscape: Bool { editorLayout.isPhoneLandscape }

    init(store: RoutineStore) {
        _player = StateObject(wrappedValue: RoutinePlayer(store: store))
    }

    var body: some View {
        playbackContent
            .playbackHaptics(player)
    }

    private var playbackContent: some View {
        GeometryReader { geometry in
            let courtWidth = CourtConstants.width
            let courtHeight = CourtConstants.height
            let sideRailWidth: CGFloat = isPhoneLandscape ? 148 : 0
            let horizontalPad: CGFloat = isPhoneLayout ? 16 : 40
            let verticalPad: CGFloat = isPhoneLayout ? 12 : 40
            let availableWidth = geometry.size.width - sideRailWidth - horizontalPad
            let availableHeight = geometry.size.height - Self.bottomBarHeight - verticalPad
            let cellSize = min(availableWidth / courtWidth, availableHeight / courtHeight)
            let gridWidth = courtWidth * cellSize
            let gridHeight = courtHeight * cellSize
            let offsetX = sideRailWidth + (geometry.size.width - sideRailWidth - gridWidth) / 2
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
                                .frame(minWidth: 44, minHeight: 44)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .padding(isPhoneLayout ? 12 : 16)
                        .accessibilityLabel("Close")
                        .help("Close routine playback")

                        Spacer()

                        if !isPhoneLandscape {
                            playbackFormationBadge
                                .padding(.top, 12)
                                .padding(.trailing, 12)
                        }
                    }
                    Spacer()
                }

                if isPhoneLandscape {
                    HStack(alignment: .top, spacing: 0) {
                        playbackFormationBadge
                            .padding(.leading, 8)
                            .padding(.top, 64)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    private var playbackFormationBadge: some View {
        FormationPipBadge(
            currentIndex: player.currentSegmentIndex,
            total: player.segmentCount,
            formationName: player.currentFormationName,
            onPrev: { player.jumpToPreviousSegment() },
            onNext: { player.jumpToNextSegment() }
        )
        .scaleEffect(isPhoneLandscape ? 0.82 : 1, anchor: .topLeading)
        .opacity(player.isPlaying ? 0.55 : 1)
        .animation(.easeInOut(duration: 0.25), value: player.isPlaying)
    }

    // MARK: - Transport Bar (thin single row)

    private var routineTransportBar: some View {
        HStack(spacing: 12) {
            Button {
                player.isPlaying ? player.pause() : player.play()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.borderedProminent)
            .frame(minWidth: 44, minHeight: 44)
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
                            .frame(width: 2, height: 10)
                            .position(x: marker * geo.size.width, y: geo.size.height / 2)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(minHeight: 44)
            .layoutPriority(1)

            if !isPhoneLayout {
                playbackSpeedPicker
                    .pickerStyle(.segmented)
                    .frame(width: 210)
            }

            Menu {
                Text("\(player.currentSegmentIndex + 1) / \(player.segmentCount)")

                if isPhoneLayout {
                    playbackSpeedPicker
                }

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
        .padding(.horizontal, isPhoneLayout ? 12 : 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var playbackSpeedPicker: some View {
        Picker("Speed", selection: Binding(
            get: { player.speed },
            set: { player.setSpeed($0) }
        )) {
            Text("0.5x").tag(CGFloat(0.5))
            Text("0.75x").tag(CGFloat(0.75))
            Text("1x").tag(CGFloat(1.0))
            Text("2x").tag(CGFloat(2.0))
            Text("4x").tag(CGFloat(4.0))
        }
        .accessibilityLabel("Playback Speed")
        .accessibilityHint("Adjust the playback speed of the routine animation")
    }
}
