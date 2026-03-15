import SwiftUI

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

                Button {
                    player.isPlaying ? player.pause() : player.play()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    player.isLooping.toggle()
                } label: {
                    Image(systemName: "repeat")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .tint(player.isLooping ? .accentColor : .secondary)
            }

            Slider(
                value: Binding(
                    get: { player.progress },
                    set: { player.seek(to: $0) }
                ),
                in: 0...1
            )

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

                Button {
                    player.isPlaying ? player.pause() : player.play()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderedProminent)

                Slider(
                    value: Binding(
                        get: { player.progress },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...1
                )

                Button {
                    player.isLooping.toggle()
                } label: {
                    Image(systemName: "repeat")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .tint(player.isLooping ? .accentColor : .secondary)

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

    private let countOptions = [4, 8, 16, 32]
    private let speedOptions: [CGFloat] = [0.5, 1.0, 1.5, 2.0]

    var body: some View {
        VStack(spacing: 10) {
            Text("\(startFormationName) \u{2192} \(endFormationName)")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)

            settingsMenu

            Button(action: player.reset) {
                Image(systemName: "backward.end.fill")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.bordered)

            Button {
                player.isPlaying ? player.pause() : player.play()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.borderedProminent)

            Button {
                player.isLooping.toggle()
            } label: {
                Image(systemName: "repeat")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.bordered)
            .tint(player.isLooping ? .accentColor : .secondary)

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                Text(String(format: "%.0f%%", player.progress * 100))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)

                Slider(
                    value: Binding(
                        get: { player.progress },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...1
                )
                .frame(width: 170)
                .rotationEffect(.degrees(-90))
                .frame(width: 36, height: 170)

                HStack(spacing: 6) {
                    Text("0")
                    Spacer(minLength: 0)
                    Text("100")
                }
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(width: 94)
        .frame(maxHeight: .infinity)
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
            VStack(spacing: 4) {
                Image(systemName: "slider.horizontal.3")
                Text("\(TransitionCountFormatting.value(player.counts)) ct")
                Text(speedLabel(for: player.speed))
            }
            .font(.caption2.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
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
