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

// MARK: - Transport Sidebar

struct TransitionTransportSidebarView: View {
    @ObservedObject var player: TransitionPlayer
    let startFormationName: String
    let endFormationName: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerSection
                transportControls
                countsSection
                speedSection
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
                Button(action: player.reset) {
                    Image(systemName: "backward.end.fill")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Reset transition")

                Button {
                    player.isPlaying ? player.pause() : player.play()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                Button {
                    player.isLooping.toggle()
                } label: {
                    Image(systemName: "repeat")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .tint(player.isLooping ? .accentColor : .secondary)
                .accessibilityLabel("Toggle loop")
                .accessibilityValue(player.isLooping ? "On" : "Off")
            }

            Slider(
                value: Binding(
                    get: { player.progress },
                    set: { player.seek(to: $0) }
                ),
                in: 0...1
            )
            .accessibilityLabel("Transition progress")

            Text(String(format: "%.0f%%", player.progress * 100))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    private var countsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Counts")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(TransitionCountFormatting.label(player.counts))
                    .font(.system(.body, design: .monospaced))
            }
            HStack(spacing: 8) {
                ForEach([4, 8, 16, 32], id: \.self) { count in
                    Button("\(count)") {
                        player.counts = CGFloat(count)
                    }
                    .buttonStyle(.bordered)
                    .tint(player.counts == CGFloat(count) ? .accentColor : .secondary)
                    .accessibilityLabel("\(count) counts")
                    .accessibilityValue(player.counts == CGFloat(count) ? "Selected" : "")
                }
            }
            Slider(
                value: Binding(
                    get: { player.counts },
                    set: { player.counts = $0 }
                ),
                in: 1...32,
                step: 1
            )
            .accessibilityLabel("Transition counts")
        }
    }

    private var speedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Speed")
                .font(.subheadline.weight(.semibold))

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
            .accessibilityLabel("Playback speed")
        }
    }

    private func speedSelection(for value: CGFloat) -> CGFloat {
        [CGFloat(0.5), 1.0, 1.5, 2.0]
            .min(by: { abs($0 - value) < abs($1 - value) }) ?? 1.0
    }
}

struct CompactTransitionPlaybackOverlayView: View {
    @ObservedObject var player: TransitionPlayer
    let startFormationName: String
    let endFormationName: String

    private let countOptions = [4, 8, 16, 32]
    private let speedOptions: [CGFloat] = [0.5, 1.0, 1.5, 2.0]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("\(startFormationName) \u{2192} \(endFormationName)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                settingsMenu
            }

            HStack(spacing: 10) {
                Button(action: player.reset) {
                    Image(systemName: "backward.end.fill")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Reset transition")

                Button {
                    player.isPlaying ? player.pause() : player.play()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                Slider(
                    value: Binding(
                        get: { player.progress },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...1
                )
                .accessibilityLabel("Transition progress")

                Button {
                    player.isLooping.toggle()
                } label: {
                    Image(systemName: "repeat")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .tint(player.isLooping ? .accentColor : .secondary)
                .accessibilityLabel("Toggle loop")
                .accessibilityValue(player.isLooping ? "On" : "Off")

                Text(String(format: "%.0f%%", player.progress * 100))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(minWidth: 42, alignment: .trailing)
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

    private var settingsMenu: some View {
        Menu {
            Section("Counts") {
                ForEach(countOptions, id: \.self) { count in
                    Button {
                        player.counts = Double(count)
                    } label: {
                        if Int(player.counts.rounded()) == count {
                            Label("\(count) counts", systemImage: "checkmark")
                        } else {
                            Text("\(count) counts")
                        }
                    }
                }
            }

            Section("Speed") {
                ForEach(speedOptions, id: \.self) { speed in
                    Button {
                        player.speed = speed
                    } label: {
                        if abs(player.speed - speed) < 0.01 {
                            Label(speedLabel(for: speed), systemImage: "checkmark")
                        } else {
                            Text(speedLabel(for: speed))
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                Text("\(TransitionCountFormatting.value(player.counts)) ct")
                Text(speedLabel(for: player.speed))
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.08), in: Capsule())
        }
    }

    private func speedLabel(for value: CGFloat) -> String {
        if abs(value.rounded() - value) < 0.001 {
            return "\(Int(value.rounded()))x"
        }
        return String(format: "%.1fx", value)
    }
}

struct CompactTransitionPlaybackRailView: View {
    @ObservedObject var player: TransitionPlayer
    let startFormationName: String
    let endFormationName: String
    let availableWidth: CGFloat

    private let countOptions = [4, 8, 16, 32]
    private let speedOptions: [CGFloat] = [0.5, 1.0, 1.5, 2.0]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(startFormationName) \u{2192} \(endFormationName)")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .lineLimit(2)

            settingsMenu

            HStack(spacing: 8) {
                Button(action: player.reset) {
                    Image(systemName: "backward.end.fill")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Reset transition")

                Button {
                    player.isPlaying ? player.pause() : player.play()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                Button {
                    player.isLooping.toggle()
                } label: {
                    Image(systemName: "repeat")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.bordered)
                .tint(player.isLooping ? .accentColor : .secondary)
                .accessibilityLabel("Toggle loop")
                .accessibilityValue(player.isLooping ? "On" : "Off")
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

                Slider(
                    value: Binding(
                        get: { player.progress },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...1
                )
                .accessibilityLabel("Transition progress")

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

    private var settingsMenu: some View {
        Menu {
            Section("Counts") {
                ForEach(countOptions, id: \.self) { count in
                    Button {
                        player.counts = Double(count)
                    } label: {
                        if Int(player.counts.rounded()) == count {
                            Label("\(count) counts", systemImage: "checkmark")
                        } else {
                            Text("\(count) counts")
                        }
                    }
                }
            }

            Section("Speed") {
                ForEach(speedOptions, id: \.self) { speed in
                    Button {
                        player.speed = speed
                    } label: {
                        if abs(player.speed - speed) < 0.01 {
                            Label(speedLabel(for: speed), systemImage: "checkmark")
                        } else {
                            Text(speedLabel(for: speed))
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(TransitionCountFormatting.value(player.counts)) ct")
                    Text(speedLabel(for: player.speed))
                }
                Spacer(minLength: 0)
            }
            .font(.caption.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func speedLabel(for value: CGFloat) -> String {
        if abs(value.rounded() - value) < 0.001 {
            return "\(Int(value.rounded()))x"
        }
        return String(format: "%.1fx", value)
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
