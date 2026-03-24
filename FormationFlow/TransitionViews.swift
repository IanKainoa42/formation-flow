import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum TransitionCountFormatting {
    static func value(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.001 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }

    static func value(_ value: CGFloat) -> String {
        Self.value(Double(value))
    }

    static func label(_ value: Double) -> String {
        let unit = abs(value - 1) < 0.001 ? "count" : "counts"
        return "\(self.value(value)) \(unit)"
    }

    static func label(_ value: CGFloat) -> String {
        Self.label(Double(value))
    }
}

// MARK: - Transport Building Blocks

@MainActor
enum TransportControls {

    @ViewBuilder
    static func resetButton(player: TransitionPlayer, size: CGFloat = 34) -> some View {
        Button(action: player.reset) {
            Image(systemName: "backward.end.fill")
                .frame(width: size, height: size)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Reset transition")
        .help("Jump back to the start of the transition")
    }

    @ViewBuilder
    static func playPauseButton(player: TransitionPlayer, size: CGFloat = 34) -> some View {
        Button {
            player.isPlaying ? player.pause() : player.play()
        } label: {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                .frame(width: size, height: size)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
        .help(player.isPlaying ? "Pause the transition preview" : "Play the transition animation")
    }

    @ViewBuilder
    static func loopButton(player: TransitionPlayer, size: CGFloat = 34) -> some View {
        Button {
            player.isLooping.toggle()
        } label: {
            Image(systemName: "repeat")
                .frame(width: size, height: size)
        }
        .buttonStyle(.bordered)
        .tint(player.isLooping ? .accentColor : .secondary)
        .accessibilityLabel("Toggle loop")
        .accessibilityValue(player.isLooping ? "On" : "Off")
        .help(player.isLooping ? "Stop looping — play once and stop" : "Loop — repeat the transition continuously")
    }

    @ViewBuilder
    static func progressSlider(player: TransitionPlayer) -> some View {
        Slider(
            value: Binding(
                get: { player.progress },
                set: { player.seek(to: $0) }
            ),
            in: 0...1
        )
        .accessibilityLabel("Transition progress")
        .help("Scrub through the transition — drag to jump to any point")
    }

    @ViewBuilder
    static func progressText(player: TransitionPlayer) -> some View {
        Text(String(format: "%.0f%%", player.progress * 100))
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(.secondary)
            .help("Current position in the transition (0% = start, 100% = end)")
    }

    @ViewBuilder
    static func swapButton(isActive: Bool, size: CGFloat = 34, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .frame(width: size, height: size)
        }
        .buttonStyle(.bordered)
        .tint(isActive ? .blue : .secondary)
        .accessibilityLabel(isActive ? "Cancel Swap" : "Swap Position")
        .accessibilityValue(isActive ? "Active" : "Inactive")
        .help(isActive ? "Cancel the swap operation" : "Swap start or end positions between two athletes")
    }

    @ViewBuilder
    static func pathButton(size: CGFloat = 34, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .frame(width: size, height: size)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Edit Path")
    }
}

// MARK: - Transport Sidebar

struct TransitionTransportSidebarView: View {
    @ObservedObject var player: TransitionPlayer
    let startFormationName: String
    let endFormationName: String
    var onSwap: () -> Void = {}
    var onPath: () -> Void = {}
    var isSwapMode: Bool = false
    var canSwap: Bool = false
    var canEditPath: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerSection
                transportControls
                actionButtons
            }
            .padding(20)
        }
        .navigationTitle("Transport")
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Transition")
                .font(.headline)
            Text("\(startFormationName) \u{2192} \(endFormationName)")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var transportControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                TransportControls.resetButton(player: player)
                TransportControls.playPauseButton(player: player)
                TransportControls.loopButton(player: player)
            }

            TransportControls.progressSlider(player: player)
            TransportControls.progressText(player: player)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            TransportControls.swapButton(isActive: isSwapMode, action: onSwap)
                .disabled(!canSwap)
            TransportControls.pathButton(action: onPath)
                .disabled(!canEditPath)
        }
    }
}

struct CompactTransitionPlaybackOverlayView: View {
    @ObservedObject var player: TransitionPlayer
    let startFormationName: String
    let endFormationName: String
    var onSwap: () -> Void = {}
    var onPath: () -> Void = {}
    var isSwapMode: Bool = false
    var canSwap: Bool = false
    var canEditPath: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(startFormationName) \u{2192} \(endFormationName)")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .lineLimit(1)

            HStack(spacing: 10) {
                TransportControls.resetButton(player: player, size: 28)
                TransportControls.playPauseButton(player: player, size: 32)
                TransportControls.progressSlider(player: player)
                TransportControls.loopButton(player: player, size: 28)
                TransportControls.swapButton(isActive: isSwapMode, size: 28, action: onSwap)
                    .disabled(!canSwap)
                TransportControls.pathButton(size: 28, action: onPath)
                    .disabled(!canEditPath)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        }
        .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
        .controlSize(.small)
    }
}

struct CompactTransitionPlaybackRailView: View {
    @ObservedObject var player: TransitionPlayer
    let startFormationName: String
    let endFormationName: String
    let availableWidth: CGFloat
    var onSwap: () -> Void = {}
    var onPath: () -> Void = {}
    var isSwapMode: Bool = false
    var canSwap: Bool = false
    var canEditPath: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(startFormationName) \u{2192} \(endFormationName)")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                TransportControls.resetButton(player: player, size: 30)
                TransportControls.playPauseButton(player: player, size: 36)
                TransportControls.loopButton(player: player, size: 30)
            }

            HStack(spacing: 8) {
                TransportControls.swapButton(isActive: isSwapMode, size: 30, action: onSwap)
                    .disabled(!canSwap)
                TransportControls.pathButton(size: 30, action: onPath)
                    .disabled(!canEditPath)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Progress")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Spacer(minLength: 0)
                    Text(String(format: "%.0f%%", player.progress * 100))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                TransportControls.progressSlider(player: player)

                HStack(spacing: 6) {
                    Text("0%")
                    Spacer(minLength: 0)
                    Text("100%")
                }
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(width: availableWidth, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        }
        .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
        .controlSize(.small)
    }
}

// MARK: - Sidebar Transport View

struct SidebarTransportView: View {
    @ObservedObject var player: TransitionPlayer
    let startFormationName: String
    let endFormationName: String
    var onSwap: () -> Void = {}
    var onPath: () -> Void = {}
    var isSwapMode: Bool = false
    var canSwap: Bool = false
    var canEditPath: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(startFormationName) \u{2192} \(endFormationName)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                TransportControls.resetButton(player: player)
                TransportControls.playPauseButton(player: player)
                TransportControls.loopButton(player: player)
            }

            TransportControls.progressSlider(player: player)

            HStack(spacing: 12) {
                TransportControls.swapButton(isActive: isSwapMode, action: onSwap)
                    .disabled(!canSwap)
                TransportControls.pathButton(action: onPath)
                    .disabled(!canEditPath)
            }
        }
    }
}

#if canImport(UIKit)
struct TransitionSharePayload: Identifiable {
    let id = UUID()
    let image: UIImage
    let message: String
    let completionMessage: String
}

struct ShareSheetView: UIViewControllerRepresentable {
    let items: [Any]
    var onComplete: (Bool, UIActivity.ActivityType?) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { activityType, completed, _, _ in
            onComplete(completed, activityType)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

struct TransitionShareCardView: View {
    let routineName: String
    let startFormationName: String
    let endFormationName: String
    let athleteCount: Int
    let counts: CGFloat
    let spacingAlerts: Int
    let pathAlerts: Int
    let athletes: [RenderedAthlete]
    let transitionPaths: [TransitionPathRenderItem]
    let endpointMarkers: [TransitionEndpointMarkerRenderItem]
    let collisionIDs: Set<UUID>
    let pathCollisionIDs: Set<UUID>
    let startFormationColor: Color
    let endFormationColor: Color
    let transitionProgress: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                Text(routineName)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text("\(startFormationName) \u{2192} \(endFormationName)")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.orange)

                Text("Share the move path, counts, and spacing checks with your team.")
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
            }

            HStack(spacing: 14) {
                ShareStatPill(title: "Athletes", value: "\(athleteCount)")
                ShareStatPill(title: "Counts", value: TransitionCountFormatting.value(counts))
                ShareStatPill(title: "Spacing", value: "\(spacingAlerts)")
                ShareStatPill(title: "Path Crossings", value: "\(pathAlerts)")
            }

            GeometryReader { geometry in
                let cardPadding: CGFloat = 24
                let width = max(0, geometry.size.width - (cardPadding * 2))
                let height = max(0, geometry.size.height - (cardPadding * 2))
                let cellSize = min(width / CourtConstants.width, height / CourtConstants.height)
                let offset = CGPoint(
                    x: (width - (CourtConstants.width * cellSize)) / 2,
                    y: (height - (CourtConstants.height * cellSize)) / 2
                )

                FloorCanvasView(
                    athletes: athletes,
                    transitionPaths: transitionPaths,
                    endpointMarkers: endpointMarkers,
                    collisionIDs: collisionIDs,
                    pathCollisionIDs: pathCollisionIDs,
                    cellSize: cellSize,
                    offset: offset,
                    hasTransition: true,
                    startFormationColor: startFormationColor,
                    endFormationColor: endFormationColor,
                    transitionProgress: transitionProgress,
                    formationColor: startFormationColor
                )
                .padding(cardPadding)
                .background(
                    LinearGradient(
                        colors: [Color.white.opacity(0.06), Color.white.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("FormationFlow")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Transition preview generated in-app")
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.64))
                }

                Spacer()

                Image(systemName: "square.and.arrow.up.circle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.orange)
            }
        }
        .padding(36)
        .frame(width: 1200, height: 1400, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.08, blue: 0.11),
                    Color(red: 0.12, green: 0.10, blue: 0.08),
                    Color(red: 0.16, green: 0.09, blue: 0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

private struct ShareStatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.54))
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
