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
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel("Reset transition")
        .accessibilityHint("Jump back to the start of the transition")
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
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
        .accessibilityValue(player.isPlaying ? "Playing" : "Paused")
        .accessibilityHint(player.isPlaying ? "Pause the transition preview" : "Play the transition animation")
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
        .frame(minWidth: 44, minHeight: 44)
        .tint(player.isLooping ? .accentColor : .secondary)
        .accessibilityLabel("Toggle loop")
        .accessibilityValue(player.isLooping ? "On" : "Off")
        .accessibilityHint(player.isLooping ? "Stop looping — play once and stop" : "Loop — repeat the transition continuously")
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
    static func swapButton(isActive: Bool, size: CGFloat = 34, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Swap")
                .font(.caption.weight(.semibold))
                .frame(minWidth: max(size + 18, 58), minHeight: size)
        }
        .buttonStyle(.bordered)
        .frame(minWidth: 44, minHeight: 44)
        .disabled(disabled)
        .tint(isActive ? .blue : .secondary)
        .accessibilityLabel(isActive ? "Cancel Swap" : "Swap Position")
        .accessibilityValue(isActive ? "Active" : "Inactive")
        .accessibilityHint(isActive ? "Cancel the swap operation" : "Swap start or end positions between two athletes")
        .help(disabled ? "Add athletes to swap their positions" : isActive ? "Cancel the swap operation" : "Swap start or end positions between two athletes")
    }

    @ViewBuilder
    static func pathButton(size: CGFloat = 34, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .frame(width: size, height: size)
        }
        .buttonStyle(.bordered)
        .frame(minWidth: 44, minHeight: 44)
        .disabled(disabled)
        .accessibilityLabel("Edit Path")
        .accessibilityHint("Open the inspector to adjust the path curve and hold duration")
        .help(disabled ? "Select a transition to edit its path" : "Edit movement path and timing")
    }

    @ViewBuilder
    static func previousFormationButton(size: CGFloat = 34, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "chevron.up")
                .frame(width: size, height: size)
        }
        .buttonStyle(.bordered)
        .frame(minWidth: 44, minHeight: 44)
        .disabled(disabled)
        .accessibilityLabel("Previous formation")
        .accessibilityHint(disabled ? "Already at the first formation" : "Go to the previous formation")
        .help(disabled ? "Already at the first formation" : "Go to the previous formation")
    }

    @ViewBuilder
    static func nextFormationButton(size: CGFloat = 34, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .frame(width: size, height: size)
        }
        .buttonStyle(.bordered)
        .frame(minWidth: 44, minHeight: 44)
        .disabled(disabled)
        .accessibilityLabel("Next formation")
        .accessibilityHint(disabled ? "Already at the last formation" : "Go to the next formation")
        .help(disabled ? "Already at the last formation" : "Go to the next formation")
    }
}

// MARK: - Formation Pip Badge

/// Which transition (relative to the selected formation) the editor is focused
/// on. Drives the Into/Out tab and the single directional arrow in the pips.
enum TransitionBadgeDirection { case into, outOf }

/// The floating formation indicator. Carries five interactions:
/// • tap left half  → previous formation
/// • tap right half → next formation
/// • long-press     → rename (editor only; omit `onRename` to disable)
/// • top tab        → toggle Into / Out of (editor only; omit `onToggleDirection`)
/// A single arrow sits between the pips to show where the focused transition
/// comes from (left of current = into) or goes to (right of current = out of).
struct FormationPipBadge: View {
    let currentIndex: Int
    let total: Int
    let formationName: String

    var direction: TransitionBadgeDirection? = nil
    var canInto: Bool = false
    var canOutOf: Bool = false
    var onToggleDirection: (() -> Void)? = nil

    var onPrev: () -> Void
    var onNext: () -> Void
    var onRename: (() -> Void)? = nil

    /// Transition length in counts. `nil` hides the length row (e.g. the
    /// full-screen player, or a formation with no adjacent transition).
    var transitionCounts: Int? = nil
    /// Free tier: length editing is Pro — show the value with a lock instead of
    /// the stepper, and route taps to the upgrade gate.
    var countsLocked: Bool = false
    var onAdjustCounts: ((Int) -> Void)? = nil
    var onLockedCountsTap: (() -> Void)? = nil

    private static let badgeWidth: CGFloat = 220
    private static let rowWidth: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let direction, let onToggleDirection {
                directionTab(active: direction, onToggle: onToggleDirection)
            }
            navBody
            if let transitionCounts {
                lengthRow(counts: transitionCounts)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(width: Self.badgeWidth, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        }
    }

    // Length of the whole transition, in counts. A −/+ stepper so a coach can
    // dial the move from 1 to 32 counts right on the badge; locked behind Pro.
    private func lengthRow(counts: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "metronome")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("Length")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
            Spacer(minLength: 4)
            if countsLocked {
                Button { onLockedCountsTap?() } label: {
                    HStack(spacing: 4) {
                        Text("\(counts) ct").font(.caption.weight(.bold).monospacedDigit())
                        Image(systemName: "lock.fill").font(.system(size: 9))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Transition length \(counts) counts, locked")
                .accessibilityHint("Upgrade to Pro to change the transition length")
            } else {
                stepButton("minus.circle.fill", enabled: counts > 1) { onAdjustCounts?(counts - 1) }
                Text("\(counts) ct")
                    .font(.callout.weight(.bold).monospacedDigit())
                    .foregroundColor(.primary)
                    .frame(minWidth: 38)
                    .accessibilityLabel("Transition length \(counts) counts")
                stepButton("plus.circle.fill", enabled: counts < 32) { onAdjustCounts?(counts + 1) }
            }
        }
        .frame(width: Self.rowWidth, alignment: .leading)
    }

    private func stepButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.primary)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(icon.hasPrefix("minus") ? "Decrease length" : "Increase length")
    }

    // Pips + name. This is the prev/next/rename surface — the tab sits above it
    // and keeps its own taps, so the two gesture regions never overlap.
    private var navBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            pipRow
            Text(formationName.isEmpty ? "Formation" : formationName)
                .font(.headline.weight(.semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: Self.rowWidth, alignment: .leading)
        }
        .frame(width: Self.rowWidth, alignment: .leading)
        .contentShape(Rectangle())   // taps on padding/whitespace still register
        .gesture(bodyGesture)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Formation \(currentIndex + 1) of \(total), \(formationName)")
        .accessibilityHint("Tap left for previous, right for next. Long press to rename.")
    }

    // Long-press wins if held; otherwise a spatial tap resolves to a half. Using
    // ExclusiveGesture (not two simultaneous recognizers) avoids the tap/long-press
    // race that has bitten dual-gesture surfaces in this project before.
    private var bodyGesture: some Gesture {
        ExclusiveGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in onRename?() },
            SpatialTapGesture(coordinateSpace: .local)
                .onEnded { value in
                    if value.location.x < Self.rowWidth / 2 { onPrev() } else { onNext() }
                }
        )
    }

    private var pipRow: some View {
        let sizes = pipSizes(for: total)
        // Arrow gap index: the pip *after which* the arrow is drawn.
        let arrowGap: Int? = direction.map { $0 == .into ? currentIndex - 1 : currentIndex }
        return HStack(spacing: sizes.spacing) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                let isCurrent = index == currentIndex
                Circle()
                    .fill(isCurrent
                          ? TransitionEndpointMarkerRenderItem.rainbowColor(forIndex: index)
                          : Color.secondary.opacity(0.35))
                    .frame(width: isCurrent ? sizes.current : sizes.other,
                           height: isCurrent ? sizes.current : sizes.other)
                    .frame(width: sizes.slot, height: sizes.slot)
                if let arrowGap, index == arrowGap, total > 1 {
                    Image(systemName: "arrow.right")
                        .font(.system(size: max(8, sizes.current * 0.85), weight: .bold))
                        .foregroundColor(.primary.opacity(0.85))
                }
            }
        }
        .frame(width: Self.rowWidth, height: 16, alignment: .leading)
        .animation(nil, value: currentIndex)
    }

    private func directionTab(active: TransitionBadgeDirection, onToggle: @escaping () -> Void) -> some View {
        HStack(spacing: 2) {
            tabSegment(title: "Into", isActive: active == .into, isEnabled: canInto) {
                if active != .into, canInto { onToggle() }
            }
            tabSegment(title: "Out of", isActive: active == .outOf, isEnabled: canOutOf) {
                if active != .outOf, canOutOf { onToggle() }
            }
        }
        .padding(2)
        .frame(width: Self.rowWidth)
        .background(.black.opacity(0.22), in: Capsule())
    }

    private func tabSegment(title: String, isActive: Bool, isEnabled: Bool, onTap: @escaping () -> Void) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundColor(isActive ? .primary : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .background {
                if isActive {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
                }
            }
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Capsule())
            .onTapGesture { if isEnabled { onTap() } }
            .accessibilityLabel("\(title) transition")
            .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }

    private struct PipSizing {
        let current: CGFloat
        let other: CGFloat
        let slot: CGFloat
        let spacing: CGFloat
    }

    private func pipSizes(for total: Int) -> PipSizing {
        let preferredCurrent: CGFloat = 14
        let preferredOther: CGFloat = 7
        let preferredSpacing: CGFloat = 6
        guard total > 1 else {
            return PipSizing(current: preferredCurrent, other: preferredOther, slot: preferredCurrent, spacing: 0)
        }
        let preferredWidth = preferredCurrent + preferredOther * CGFloat(total - 1) + preferredSpacing * CGFloat(total - 1)
        if preferredWidth <= Self.rowWidth {
            return PipSizing(current: preferredCurrent, other: preferredOther, slot: preferredCurrent, spacing: preferredSpacing)
        }
        let scale = Self.rowWidth / preferredWidth
        let current = max(8, preferredCurrent * scale)
        let other = max(4, preferredOther * scale)
        let spacing = max(2, preferredSpacing * scale)
        return PipSizing(current: current, other: other, slot: current, spacing: spacing)
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
    var onPreviousFormation: () -> Void = {}
    var onNextFormation: () -> Void = {}
    var isFirstFormation: Bool = false
    var isLastFormation: Bool = false

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
                TransportControls.previousFormationButton(disabled: isFirstFormation, action: onPreviousFormation)
                TransportControls.nextFormationButton(disabled: isLastFormation, action: onNextFormation)
                TransportControls.resetButton(player: player)
                TransportControls.playPauseButton(player: player)
                TransportControls.loopButton(player: player)
            }

            TransportControls.progressSlider(player: player)
            TransportControls.progressText(player: player)

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
            .accessibilityLabel("Playback Speed")
            .accessibilityHint("Adjust the playback speed of the transition animation")
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            TransportControls.swapButton(isActive: isSwapMode, disabled: !canSwap, action: onSwap)
            TransportControls.pathButton(disabled: !canEditPath, action: onPath)
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
    var onPreviousFormation: () -> Void = {}
    var onNextFormation: () -> Void = {}
    var isFirstFormation: Bool = false
    var isLastFormation: Bool = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text("\(startFormationName) \u{2192} \(endFormationName)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
                TransportControls.loopButton(player: player, size: 30)
                TransportControls.swapButton(isActive: isSwapMode, size: 30, disabled: !canSwap, action: onSwap)
                TransportControls.pathButton(size: 30, disabled: !canEditPath, action: onPath)
            }

            HStack(spacing: 10) {
                TransportControls.previousFormationButton(size: 34, disabled: isFirstFormation, action: onPreviousFormation)
                TransportControls.resetButton(player: player, size: 34)
                TransportControls.playPauseButton(player: player, size: 40)
                TransportControls.progressSlider(player: player)
                TransportControls.nextFormationButton(size: 34, disabled: isLastFormation, action: onNextFormation)
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
    var onAdd: (() -> Void)? = nil
    var formationLabel: String? = nil
    var formationColor: Color = .accentColor
    var onPreviousFormation: () -> Void = {}
    var onNextFormation: () -> Void = {}
    var isFirstFormation: Bool = false
    var isLastFormation: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Formation context (replaces the canvas overlay that was covering the floor)
            if let formationLabel {
                HStack(spacing: 6) {
                    Circle()
                        .fill(formationColor)
                        .frame(width: 7, height: 7)
                    Text(formationLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
            }

            Text("\(startFormationName) \u{2192} \(endFormationName)")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)

            // Add athlete button
            if let onAdd {
                Button(action: onAdd) {
                    Label("Add", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            Divider()

            // Two rows so the transport fits the narrow landscape rail (as little
            // as ~116pt of content width). A single 5-button row was ~184pt wide
            // and spilled outside the rail's rounded background.
            HStack(spacing: 8) {
                TransportControls.previousFormationButton(size: 28, disabled: isFirstFormation, action: onPreviousFormation)
                TransportControls.playPauseButton(player: player, size: 36)
                TransportControls.nextFormationButton(size: 28, disabled: isLastFormation, action: onNextFormation)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                TransportControls.resetButton(player: player, size: 30)
                TransportControls.loopButton(player: player, size: 30)
            }
            .frame(maxWidth: .infinity)

            // Swap and path buttons fill the full row width
            HStack(spacing: 8) {
                TransportControls.swapButton(isActive: isSwapMode, size: 30, disabled: !canSwap, action: onSwap)
                    .frame(maxWidth: .infinity)
                TransportControls.pathButton(size: 30, disabled: !canEditPath, action: onPath)
                    .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 6) {
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
    var onPreviousFormation: () -> Void = {}
    var onNextFormation: () -> Void = {}
    var isFirstFormation: Bool = false
    var isLastFormation: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(startFormationName) \u{2192} \(endFormationName)")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            // Row 1: nav + play
            HStack(spacing: 8) {
                TransportControls.previousFormationButton(size: 28, disabled: isFirstFormation, action: onPreviousFormation)
                TransportControls.nextFormationButton(size: 28, disabled: isLastFormation, action: onNextFormation)
                TransportControls.resetButton(player: player, size: 28)
                TransportControls.playPauseButton(player: player, size: 28)
                TransportControls.loopButton(player: player, size: 28)
            }

            TransportControls.progressSlider(player: player)

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
            .accessibilityLabel("Playback Speed")
            .accessibilityHint("Adjust the playback speed of the transition animation")

            HStack(spacing: 8) {
                TransportControls.swapButton(isActive: isSwapMode, size: 28, disabled: !canSwap, action: onSwap)
                TransportControls.pathButton(size: 28, disabled: !canEditPath, action: onPath)
            }
        }
    }
}

// MARK: - Thin Transition Transport Bar (single row, sits below the floor)

struct ThinTransitionTransportBar: View {
    @ObservedObject var player: TransitionPlayer
    let startFormationName: String
    let endFormationName: String
    var onSwap: () -> Void = {}
    var onPath: () -> Void = {}
    var isSwapMode: Bool = false
    var canSwap: Bool = false
    var canEditPath: Bool = false
    var onPreviousFormation: () -> Void = {}
    var onNextFormation: () -> Void = {}
    var isFirstFormation: Bool = false
    var isLastFormation: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Text("\(startFormationName) \u{2192} \(endFormationName)")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 180, alignment: .leading)

            Button(action: onPreviousFormation) {
                Image(systemName: "chevron.up").frame(width: 36, height: 36)
            }
            .buttonStyle(.bordered)
            .frame(minWidth: 44, minHeight: 44)
            .disabled(isFirstFormation)
            .accessibilityLabel("Previous formation")
            .accessibilityHint(isFirstFormation ? "Already at the first formation" : "Go to the previous formation")
            .help(isFirstFormation ? "Already at the first formation" : "Go to the previous formation")

            TransportControls.playPauseButton(player: player, size: 30)

            Button(action: onNextFormation) {
                Image(systemName: "chevron.down").frame(width: 36, height: 36)
            }
            .buttonStyle(.bordered)
            .frame(minWidth: 44, minHeight: 44)
            .disabled(isLastFormation)
            .accessibilityLabel("Next formation")
            .accessibilityHint(isLastFormation ? "Already at the last formation" : "Go to the next formation")
            .help(isLastFormation ? "Already at the last formation" : "Go to the next formation")

            TransportControls.progressSlider(player: player)
                .layoutPriority(1)

            Menu {
                Button {
                    player.isLooping.toggle()
                } label: {
                    Label(
                        player.isLooping ? "Stop Looping" : "Loop Playback",
                        systemImage: player.isLooping ? "repeat.circle.fill" : "repeat"
                    )
                }

                Button(action: player.reset) {
                    Label("Reset to Start", systemImage: "backward.end.fill")
                }

                Divider()

                Button(action: onSwap) {
                    Text(isSwapMode ? "Cancel Swap" : "Swap")
                }
                .disabled(!canSwap)

                Button(action: onPath) {
                    Label("Edit Path", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
                .disabled(!canEditPath)
            } label: {
                Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("More transition options")
            .accessibilityHint("Show more transition options")
            .help("More transition options")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.bar)
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
    let pathCollisionMarkerPositions: [CGPoint]
    let pathCollisionMarkerProgresses: [CGFloat]
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
                    pathCollisionMarkerPositions: pathCollisionMarkerPositions,
                    pathCollisionMarkerProgresses: pathCollisionMarkerProgresses,
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
