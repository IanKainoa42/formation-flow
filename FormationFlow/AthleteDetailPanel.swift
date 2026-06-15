import SwiftUI

// MARK: - Inspector Components

struct AthleteInspectorView: View {
    let athlete: RosterAthlete
    let position: CGPoint
    let formationCount: Int
    var formationName: String = "Formation"
    var compactLayout: Bool = false
    var isPro: Bool = true
    var onUpgrade: () -> Void = {}
    var onUpdateLabel: (String) -> Void
    var onUpdateRole: (AthleteRole) -> Void
    var onDelete: () -> Void
    var onClearSelection: () -> Void

    @State private var showDeleteConfirmation = false
    @State private var labelDraft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: compactLayout ? 14 : 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Athlete")
                        .font(.headline)
                    Text("Shared across every formation")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: onClearSelection) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear selection")
                .accessibilityHint("Deselect this athlete")
                .help("Deselect this athlete")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Identity")
                    .font(.subheadline.weight(.semibold))
                if isPro {
                    TextField("Label", text: $labelDraft)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .onChange(of: labelDraft) { _, newValue in
                            let clamped = String(newValue.prefix(3))
                            if clamped != newValue { labelDraft = clamped }
                            let trimmed = clamped.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                onUpdateLabel(trimmed)
                            }
                        }
                        .onAppear { labelDraft = athlete.label }
                        .onChange(of: athlete.id) { _, _ in labelDraft = athlete.label }
                } else {
                    Button(action: onUpgrade) {
                        HStack {
                            Text(athlete.label)
                                .font(.body.monospaced())
                            Spacer()
                            Label("Rename (Pro)", systemImage: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3))
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Rename athlete (Pro feature)")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Role")
                    .font(.subheadline.weight(.semibold))
                AthleteRolePicker(
                    selectedRole: athlete.role,
                    compactLayout: compactLayout,
                    isPro: isPro,
                    onUpgrade: onUpgrade,
                    onSelect: onUpdateRole
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Position in \(formationName)")
                    .font(.subheadline.weight(.semibold))
                Text(String(format: "x %.1fft   y %.1fft", position.x, position.y))
                    .font(.system(.body, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Actions")
                    .font(.subheadline.weight(.semibold))

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete Athlete", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .padding(compactLayout ? 16 : 20)
        .background(.thinMaterial)
    }
}

struct MultiSelectionInspectorView: View {
    let count: Int
    var compactLayout: Bool = false
    var onClearSelection: () -> Void

    // Optional bulk-delay context. When all of these are provided, render a
    // Start Delay slider that sets the delay on every selected athlete at once.
    var store: RoutineStore? = nil
    var selectedAthleteIDs: Set<UUID> = []
    var player: TransitionPlayer? = nil
    var startFormationID: UUID? = nil
    var endFormationID: UUID? = nil
    var isPro: Bool = true
    var onUpgrade: () -> Void = {}
    var onRefreshTransition: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: compactLayout ? 12 : 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Selection")
                        .font(.headline)
                    Text("\(count) athletes selected")
                        .font((compactLayout ? Font.title3 : .title3).weight(.semibold))
                }
                Spacer()
                Button(action: onClearSelection) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear selection")
                .accessibilityHint("Deselect these athletes")
                .help("Clear selection")
            }
            Text("Drag or rotate the group on the floor. Use the controls below to update everyone selected.")
                .font(.body)
                .foregroundColor(.secondary)

            if let store, !selectedAthleteIDs.isEmpty {
                Divider()
                BulkRoleControl(
                    store: store,
                    selectedAthleteIDs: selectedAthleteIDs,
                    compactLayout: compactLayout,
                    isPro: isPro,
                    onUpgrade: onUpgrade
                )
            }

            if let store, let player, let startFormationID, let endFormationID, !selectedAthleteIDs.isEmpty {
                Divider()
                TransitionGroupControl(
                    store: store,
                    selectedAthleteIDs: selectedAthleteIDs,
                    startFormationID: startFormationID,
                    endFormationID: endFormationID,
                    compactLayout: compactLayout,
                    onRefreshTransition: onRefreshTransition
                )

                Divider()
                BulkDelayControl(
                    store: store,
                    player: player,
                    selectedAthleteIDs: selectedAthleteIDs,
                    startFormationID: startFormationID,
                    endFormationID: endFormationID,
                    isPro: isPro,
                    onUpgrade: onUpgrade,
                    onRefreshTransition: onRefreshTransition
                )

                Divider()
                BulkPathActions(
                    store: store,
                    selectedAthleteIDs: selectedAthleteIDs,
                    startFormationID: startFormationID,
                    endFormationID: endFormationID,
                    onRefreshTransition: onRefreshTransition
                )
            }

            if let store, !selectedAthleteIDs.isEmpty {
                Divider()
                Button(role: .destructive) {
                    store.deleteAthletes(ids: Array(selectedAthleteIDs))
                    onClearSelection()
                } label: {
                    Label("Delete Selected Athletes", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .padding(compactLayout ? 16 : 20)
        .background(.thinMaterial)
    }
}

private struct TransitionGroupControl: View {
    @ObservedObject var store: RoutineStore
    let selectedAthleteIDs: Set<UUID>
    let startFormationID: UUID
    let endFormationID: UUID
    let compactLayout: Bool
    let onRefreshTransition: () -> Void

    private var selectedGroup: TransitionStuntGroup? {
        store.transitionStuntGroup(exactly: selectedAthleteIDs, from: startFormationID, to: endFormationID)
    }

    private var overlapsExistingGroup: Bool {
        selectedAthleteIDs.contains { athleteID in
            store.transitionStuntGroup(containing: athleteID, from: startFormationID, to: endFormationID) != nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compactLayout ? 8 : 10) {
            HStack {
                Text("Transition Group")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(selectedGroup == nil ? "Unlocked" : "Locked")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button {
                if let selectedGroup {
                    store.removeTransitionStuntGroup(id: selectedGroup.id, from: startFormationID, to: endFormationID)
                } else {
                    _ = store.createTransitionStuntGroup(
                        from: startFormationID,
                        to: endFormationID,
                        athleteIDs: selectedAthleteIDs
                    )
                }
                onRefreshTransition()
            } label: {
                Label(
                    selectedGroup == nil ? (overlapsExistingGroup ? "Regroup as Unit" : "Group as Unit") : "Ungroup Unit",
                    systemImage: selectedGroup == nil ? "link" : "link.badge.minus"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Text(selectedGroup == nil ? "Locks these athletes together for this transition." : "Ungroup before editing one athlete by itself.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

private struct BulkRoleControl: View {
    @ObservedObject var store: RoutineStore
    let selectedAthleteIDs: Set<UUID>
    let compactLayout: Bool
    let isPro: Bool
    let onUpgrade: () -> Void

    private var selectedAthletes: [RosterAthlete] {
        store.routine.roster.filter { selectedAthleteIDs.contains($0.id) }
    }

    private var commonRole: AthleteRole? {
        guard let first = selectedAthletes.first?.role else { return nil }
        return selectedAthletes.allSatisfy { $0.role == first } ? first : nil
    }

    private var roleLabel: String {
        commonRole?.displayName ?? "Mixed"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compactLayout ? 8 : 10) {
            HStack {
                Text("Role")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(roleLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: compactLayout ? 64 : 72), spacing: 8)],
                spacing: 8
            ) {
                ForEach(AthleteRole.allCases, id: \.self) { role in
                    Button {
                        guard isPro || role == .base else {
                            onUpgrade()
                            return
                        }
                        let ids = selectedAthleteIDs
                        for athleteID in ids {
                            store.mutateRosterAthlete(id: athleteID) { athlete in
                                athlete.role = role
                            }
                        }
                    } label: {
                        VStack(spacing: compactLayout ? 4 : 6) {
                            ZStack {
                                AthleteRoleSwatch(role: role, isSelected: commonRole == role)
                                    .frame(width: compactLayout ? 24 : 28, height: compactLayout ? 24 : 28)
                                if !isPro && role != .base {
                                    Image(systemName: "lock.fill")
                                        .font(.caption2)
                                        .foregroundColor(.white)
                                        .shadow(radius: 2)
                                }
                            }
                            Text(role.displayName)
                                .font(.caption2)
                                .foregroundColor(commonRole == role ? .primary : .secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, compactLayout ? 6 : 8)
                        .background(commonRole == role ? Color.primary.opacity(0.08) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Set selected athletes to \(role.displayName)")
                    .accessibilityValue(commonRole == role ? "Selected" : "")
                }
            }
        }
    }
}

private struct BulkDelayControl: View {
    @ObservedObject var store: RoutineStore
    @ObservedObject var player: TransitionPlayer
    let selectedAthleteIDs: Set<UUID>
    let startFormationID: UUID
    let endFormationID: UUID
    let isPro: Bool
    let onUpgrade: () -> Void
    let onRefreshTransition: () -> Void

    @State private var sliderValue: CGFloat = 0
    @State private var isEditing = false

    private var selectedDelays: [CGFloat] {
        selectedAthleteIDs.map {
            player.transitionSpec.athleteTransition(for: $0).moveDelayCounts
        }
    }

    private var commonDelay: CGFloat? {
        let delays = selectedDelays
        guard let first = delays.first else { return nil }
        return delays.allSatisfy({ $0 == first }) ? first : nil
    }

    private var displayedValue: CGFloat {
        isEditing ? sliderValue : (commonDelay ?? selectedDelays.first ?? 0)
    }

    private var valueLabel: String {
        if !isEditing, commonDelay == nil {
            return "Mixed"
        }
        return TransitionCountFormatting.label(displayedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Start Delay (\(selectedAthleteIDs.count))")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(valueLabel)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            if isPro {
                Slider(
                    value: Binding(
                        get: { displayedValue },
                        set: { newValue in
                            sliderValue = newValue
                            applyBulkDelay(newValue)
                        }
                    ),
                    in: 0...CGFloat(player.counts),
                    step: 0.5,
                    onEditingChanged: { editing in
                        isEditing = editing
                        if editing {
                            sliderValue = commonDelay ?? selectedDelays.first ?? 0
                        }
                    }
                )
                .accessibilityLabel("Start Delay for \(selectedAthleteIDs.count) selected athletes")
            } else {
                HStack {
                    Slider(value: .constant(0), in: 0...CGFloat(player.counts))
                        .disabled(true)
                    Button(action: onUpgrade) {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("Upgrade to Pro to adjust start delay")
                    .help("Upgrade to Pro to adjust start delay")
                }
            }
            Text("Applies to all selected athletes.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func applyBulkDelay(_ newValue: CGFloat) {
        let clamped = min(CGFloat(player.counts), max(0, newValue))
        let ids = selectedAthleteIDs
        store.mutateTransitionSpec(from: startFormationID, to: endFormationID) { spec in
            for index in spec.athleteTransitions.indices where ids.contains(spec.athleteTransitions[index].athleteID) {
                spec.athleteTransitions[index].moveDelayCounts = clamped
            }
        }
        onRefreshTransition()
    }
}

private struct BulkPathActions: View {
    @ObservedObject var store: RoutineStore
    let selectedAthleteIDs: Set<UUID>
    let startFormationID: UUID
    let endFormationID: UUID
    let onRefreshTransition: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paths")
                .font(.subheadline.weight(.semibold))

            Button(role: .destructive) {
                let ids = selectedAthleteIDs
                store.mutateTransitionSpec(from: startFormationID, to: endFormationID) { spec in
                    for index in spec.athleteTransitions.indices where ids.contains(spec.athleteTransitions[index].athleteID) {
                        spec.athleteTransitions[index].pathControlPoint = nil
                        spec.athleteTransitions[index].pathWaypoints = []
                    }
                }
                onRefreshTransition()
            } label: {
                Label("Reset Selected Paths", systemImage: "line.diagonal")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Text("Clears custom path bends only for the selected athletes.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct EmptyInspectorView: View {
    let title: String
    let message: String
    var compactLayout: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compactLayout ? 12 : 14) {
            Text(title)
                .font(.headline)
            Text(message)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(compactLayout ? 16 : 20)
        .background(.thinMaterial)
    }
}

struct AthleteRolePicker: View {
    let selectedRole: AthleteRole
    var compactLayout: Bool = false
    var isPro: Bool = true
    var onUpgrade: () -> Void = {}
    var onSelect: (AthleteRole) -> Void

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: compactLayout ? 68 : 74), spacing: 8)],
            spacing: 8
        ) {
            ForEach(AthleteRole.allCases, id: \.self) { role in
                AthleteRolePickerButton(
                    role: role,
                    isSelected: role == selectedRole,
                    compactLayout: compactLayout,
                    isPro: isPro,
                    onSelect: { onSelect(role) },
                    onUpgrade: onUpgrade
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Athlete role picker")
    }
}

private struct AthleteRolePickerButton: View {
    let role: AthleteRole
    let isSelected: Bool
    let compactLayout: Bool
    let isPro: Bool
    let onSelect: () -> Void
    let onUpgrade: () -> Void

    var body: some View {
        Button {
            if isPro || role == .base {
                onSelect()
            } else {
                onUpgrade()
            }
        } label: {
            VStack(spacing: compactLayout ? 4 : 6) {
                ZStack {
                    AthleteRoleSwatch(role: role, isSelected: isSelected)
                        .frame(width: compactLayout ? 24 : 28, height: compactLayout ? 24 : 28)
                    if !isPro && role != .base {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                    }
                }
                Text(role.displayName)
                    .font(.caption2)
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, compactLayout ? 6 : 8)
            .background(isSelected ? Color.primary.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(role.displayName)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityHint("Double tap to set role to \(role.displayName)")
    }
}

private struct AthleteRoleSwatch: View {
    let role: AthleteRole
    let isSelected: Bool

    private var fillColor: Color {
        isSelected ? .primary : .gray.opacity(0.75)
    }

    var body: some View {
        ZStack {
            AthleteRoleMarkerShape(role: role)
                .fill(fillColor)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.bold())
                    .foregroundColor(Color(uiColor: .systemBackground))
            }
        }
    }
}

struct AthleteRoleMarkerShape: Shape {
    let role: AthleteRole

    func path(in rect: CGRect) -> Path {
        role.markerPath(in: rect)
    }
}

// MARK: - Transition Inspector Section

struct TransitionInspectorSectionView: View {
    let transition: AthleteTransition
    @ObservedObject var player: TransitionPlayer
    let startFormationName: String
    let endFormationName: String
    var compactLayout: Bool = false
    var isPro: Bool = true
    var onUpdateMoveDelay: (CGFloat) -> Void = { _ in }
    var onClearPath: () -> Void = {}
    var onEnsureCurve: () -> Void = {}
    var onAddWaypoint: () -> Void = {}
    var onToggleWaypointSmooth: (Int) -> Void = { _ in }
    var onDeleteWaypoint: (UUID) -> Void = { _ in }
    var onSetWaypointHold: (Int, CGFloat) -> Void = { _, _ in }
    var onResetAllPaths: () -> Void = {}
    var onUpgrade: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: compactLayout ? 14 : 16) {
            header
            moveDelaySection
            pathControlsSection

            if !transition.pathWaypoints.isEmpty {
                waypointListSection
            }
        }
        .padding(compactLayout ? 16 : 20)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Transition")
                    .font(.headline)
                Spacer()
                Button(role: .destructive, action: onResetAllPaths) {
                    Label("Reset All", systemImage: "arrow.uturn.backward.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(!hasCustomPaths)
                .help(!hasCustomPaths ? "No custom paths to reset" : "Reset all paths to default")
            }
            Text("\(startFormationName) \u{2192} \(endFormationName)")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var hasCustomPaths: Bool {
        player.transitionSpec.athleteTransitions.contains {
            $0.pathControlPoint != nil || !$0.pathWaypoints.isEmpty
        }
    }

    // MARK: - Move Delay

    private var moveDelaySection: some View {
        VStack(alignment: .leading, spacing: compactLayout ? 6 : 8) {
            Text("Start Delay")
                .font(.subheadline.weight(.semibold))
            if isPro {
                Slider(
                    value: Binding(
                        get: { transition.moveDelayCounts },
                        set: { onUpdateMoveDelay($0) }
                    ),
                    in: 0...CGFloat(player.counts),
                    step: 0.5
                )
                .accessibilityLabel("Start Delay")
            } else {
                HStack {
                    Slider(value: .constant(0), in: 0...CGFloat(player.counts))
                        .disabled(true)
                    Button(action: onUpgrade) {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("Upgrade to Pro to adjust start delay")
                    .accessibilityHint("Requires a Pro subscription to change the start delay timing")
                    .help("Upgrade to Pro to adjust start delay")
                }
            }
            Text(TransitionCountFormatting.label(transition.moveDelayCounts))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Path Controls

    private var pathControlsSection: some View {
        VStack(alignment: .leading, spacing: compactLayout ? 8 : 10) {
            Text("Path")
                .font(.subheadline.weight(.semibold))
            Group {
                if compactLayout {
                    VStack(spacing: 8) { pathButtons }
                } else {
                    HStack(spacing: 10) { pathButtons }
                }
            }

            Text("Tap Waypoint to bend the path, then drag the handles. You can also double-tap the athlete on the floor.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var pathButtons: some View {
        Button(action: onClearPath) {
            Label("Straight", systemImage: "line.diagonal")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)

        Button(action: onEnsureCurve) {
            Label("Curve", systemImage: "scribble")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)

        Button(action: onAddWaypoint) {
            Label(
                isPro ? "Waypoint" : "Waypoint (Pro)",
                systemImage: isPro ? "plus.circle" : "lock.fill"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .accessibilityHint(isPro ? "Add a waypoint to the path" : "Upgrade to Pro to add waypoints")
    }

    // MARK: - Waypoint List

    private var waypointListSection: some View {
        VStack(alignment: .leading, spacing: compactLayout ? 8 : 10) {
            Text("Waypoints")
                .font(.subheadline.weight(.semibold))
            ForEach(Array(transition.pathWaypoints.enumerated()), id: \.element.id) { waypointIndex, waypoint in
                waypointCard(waypointIndex: waypointIndex, waypoint: waypoint)
            }
        }
    }

    private func waypointCard(waypointIndex: Int, waypoint: PathWaypoint) -> some View {
        VStack(alignment: .leading, spacing: compactLayout ? 6 : 8) {
            HStack {
                Text("Waypoint \(waypointIndex + 1)")
                    .font(.body.weight(.medium))
                Spacer()
                Button(role: .destructive) {
                    onDeleteWaypoint(waypoint.id)
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete waypoint")
                .accessibilityHint("Removes this waypoint from the athlete's path")
                .help("Removes this waypoint from the athlete's path")
            }

            HStack {
                Text(waypoint.isSmooth ? "Smooth" : "Sharp")
                Spacer()
                Button(waypoint.isSmooth ? "Make Sharp" : "Make Smooth") {
                    if isPro {
                        onToggleWaypointSmooth(waypointIndex)
                    } else {
                        onUpgrade()
                    }
                }
                .buttonStyle(.bordered)
            }

            holdSection(waypointIndex: waypointIndex, waypoint: waypoint)
        }
        .padding(compactLayout ? 12 : 14)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var transitionTotalCounts: CGFloat {
        CGFloat(player.counts)
    }

    private var holdSliderMax: CGFloat {
        // Cap at 8 counts (a full 8-count) or the transition's total, whichever is smaller.
        // Holding longer than the transition itself doesn't make musical sense.
        min(8, max(0.5, transitionTotalCounts))
    }

    @ViewBuilder
    private func holdSection(waypointIndex: Int, waypoint: PathWaypoint) -> some View {
        VStack(alignment: .leading, spacing: compactLayout ? 6 : 8) {
            HStack {
                Text("Hold")
                    .font(.body.weight(.medium))
                Spacer()
                Text(TransitionCountFormatting.label(waypoint.holdCounts))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            if isPro {
                Slider(
                    value: Binding(
                        get: { min(waypoint.holdCounts, holdSliderMax) },
                        set: { onSetWaypointHold(waypointIndex, $0) }
                    ),
                    in: 0...holdSliderMax,
                    step: 0.5
                )
                .accessibilityLabel("Hold duration for waypoint \(waypointIndex + 1)")
            } else {
                HStack {
                    Slider(value: .constant(0), in: 0...holdSliderMax)
                        .disabled(true)
                    Button(action: onUpgrade) {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("Upgrade to Pro to adjust hold duration")
                    .help("Upgrade to Pro to adjust hold duration")
                }
            }

            Text("Pause at this waypoint · transition total \(TransitionCountFormatting.label(transitionTotalCounts))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Sidebar Inspector (Reusable)

struct SidebarInspectorView: View {
    @ObservedObject var store: RoutineStore
    let formationID: UUID
    @Binding var selectedAthleteIDs: Set<UUID>
    var isCompactLayout: Bool = false
    var onDeleteAthlete: () -> Void = {}

    // Optional transition data — when present, shows timing controls
    var player: TransitionPlayer?
    var startFormationID: UUID?
    var endFormationID: UUID?
    var isPro: Bool = true
    var onUpgrade: () -> Void = {}
    var onRefreshTransition: () -> Void = {}

    @State private var showingClearPathConfirmation = false

    private var selectedAthleteID: UUID? {
        selectedAthleteIDs.count == 1 ? selectedAthleteIDs.first : nil
    }

    private var selectedRosterAthlete: RosterAthlete? {
        guard let selectedAthleteID else { return nil }
        return store.routine.roster.first(where: { $0.id == selectedAthleteID })
    }

    private var formation: Formation? {
        guard let idx = store.formationIndex(id: formationID) else { return nil }
        return store.routine.formations[idx]
    }

    private var selectedPlacement: FormationPlacement? {
        guard let selectedAthleteID, let formation else { return nil }
        return formation.placements.first(where: { $0.athleteID == selectedAthleteID })
    }

    private var selectedTransition: AthleteTransition? {
        guard let selectedAthleteID, let player else { return nil }
        return player.transitionSpec.athleteTransition(for: selectedAthleteID)
    }

    private var startFormationName: String? {
        guard let startFormationID, let idx = store.formationIndex(id: startFormationID) else { return nil }
        return store.routine.formations[idx].name
    }

    private var endFormationName: String? {
        guard let endFormationID, let idx = store.formationIndex(id: endFormationID) else { return nil }
        return store.routine.formations[idx].name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let selectedRosterAthlete, let selectedPlacement {
                AthleteInspectorView(
                        athlete: selectedRosterAthlete,
                        position: selectedPlacement.position,
                        formationCount: store.routine.formations.count,
                        formationName: formation?.name ?? "Formation",
                        compactLayout: isCompactLayout,
                        isPro: isPro,
                        onUpgrade: onUpgrade,
                        onUpdateLabel: { newLabel in
                            store.mutateRosterAthlete(id: selectedRosterAthlete.id) { athlete in
                                athlete.label = newLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? athlete.label
                                    : newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        },
                        onUpdateRole: { newRole in
                            guard isPro else {
                                onUpgrade()
                                return
                            }
                            store.mutateRosterAthlete(id: selectedRosterAthlete.id) { athlete in
                                athlete.role = newRole
                            }
                        },
                        onDelete: onDeleteAthlete,
                        onClearSelection: {
                            selectedAthleteIDs = []
                        }
                    )

                    if let selectedTransition, let player,
                       let startFormationID, let endFormationID,
                       let startFormationName, let endFormationName
                    {
                        Divider()
                        transitionSection(
                            transition: selectedTransition,
                            player: player,
                            startFormationID: startFormationID,
                            endFormationID: endFormationID,
                            startFormationName: startFormationName,
                            endFormationName: endFormationName
                        )
                    }
                } else if selectedAthleteIDs.count > 1 {
                    MultiSelectionInspectorView(
                        count: selectedAthleteIDs.count,
                        compactLayout: isCompactLayout,
                        onClearSelection: { selectedAthleteIDs = [] },
                        store: store,
                        selectedAthleteIDs: selectedAthleteIDs,
                        player: player,
                        startFormationID: startFormationID,
                        endFormationID: endFormationID,
                        isPro: isPro,
                        onUpgrade: onUpgrade,
                        onRefreshTransition: onRefreshTransition
                    )
                } else {
                    EmptyInspectorView(
                        title: "Inspector",
                        message: "Select one athlete to edit its label, role, and actions. Multi-select to move groups together.",
                        compactLayout: isCompactLayout
                    )
                }
            }
        .background(.thinMaterial)
    }

    private func performClearPath(startFormationID: UUID, endFormationID: UUID) {
        guard let selectedAthleteID else { return }
        store.mutateAthleteTransition(
            from: startFormationID,
            to: endFormationID,
            athleteID: selectedAthleteID
        ) { t in
            t.pathControlPoint = nil
            t.pathWaypoints = []
        }
        onRefreshTransition()
    }

    @ViewBuilder
    private func transitionSection(
        transition: AthleteTransition,
        player: TransitionPlayer,
        startFormationID: UUID,
        endFormationID: UUID,
        startFormationName: String,
        endFormationName: String
    ) -> some View {
        TransitionInspectorSectionView(
            transition: transition,
            player: player,
            startFormationName: startFormationName,
            endFormationName: endFormationName,
            compactLayout: isCompactLayout,
            isPro: isPro,
            onUpdateMoveDelay: { newValue in
                guard let selectedAthleteID else { return }
                store.mutateAthleteTransition(
                    from: startFormationID,
                    to: endFormationID,
                    athleteID: selectedAthleteID
                ) { t in
                    t.moveDelayCounts = min(CGFloat(player.counts), max(0, newValue))
                }
                onRefreshTransition()
            },
            onClearPath: {
                performClearPath(
                    startFormationID: startFormationID,
                    endFormationID: endFormationID
                )
            },
            onEnsureCurve: {
                guard let selectedAthleteID else { return }
                let startAthlete = player.startAthletes.first(where: { $0.id == selectedAthleteID })
                let endAthlete = player.endAthletes.first(where: { $0.id == selectedAthleteID })
                guard let startAthlete, let endAthlete else { return }
                store.mutateAthleteTransition(
                    from: startFormationID,
                    to: endFormationID,
                    athleteID: selectedAthleteID
                ) { t in
                    guard t.pathControlPoint == nil && t.pathWaypoints.isEmpty else { return }
                    let midpoint = CGPoint(
                        x: (startAthlete.position.x + endAthlete.position.x) / 2,
                        y: (startAthlete.position.y + endAthlete.position.y) / 2
                    )
                    t.pathControlPoint = CGPoint(x: midpoint.x, y: midpoint.y - 6)
                }
                onRefreshTransition()
            },
            onAddWaypoint: {
                guard isPro else {
                    onUpgrade()
                    return
                }
                guard let selectedAthleteID else { return }
                let startAthlete = player.startAthletes.first(where: { $0.id == selectedAthleteID })
                let endAthlete = player.endAthletes.first(where: { $0.id == selectedAthleteID })
                guard let startAthlete, let endAthlete else { return }
                store.mutateAthleteTransition(
                    from: startFormationID,
                    to: endFormationID,
                    athleteID: selectedAthleteID
                ) { t in
                    let placement = PathWaypointPlacement.defaultPlacement(
                        transition: t,
                        start: startAthlete.position,
                        end: endAthlete.position
                    )
                    t.pathControlPoint = nil
                    t.pathWaypoints.insert(
                        PathWaypoint(position: placement.point, isSmooth: true),
                        at: placement.index
                    )
                }
                onRefreshTransition()
            },
            onToggleWaypointSmooth: { waypointIndex in
                guard let selectedAthleteID else { return }
                store.mutateAthleteTransition(
                    from: startFormationID,
                    to: endFormationID,
                    athleteID: selectedAthleteID
                ) { t in
                    t.pathWaypoints[waypointIndex].isSmooth.toggle()
                }
                onRefreshTransition()
            },
            onDeleteWaypoint: { waypointID in
                guard let selectedAthleteID else { return }
                store.mutateAthleteTransition(
                    from: startFormationID,
                    to: endFormationID,
                    athleteID: selectedAthleteID
                ) { t in
                    t.pathWaypoints.removeAll(where: { $0.id == waypointID })
                }
                onRefreshTransition()
            },
            onSetWaypointHold: { waypointIndex, newValue in
                guard isPro else {
                    onUpgrade()
                    return
                }
                guard let selectedAthleteID else { return }
                store.mutateAthleteTransition(
                    from: startFormationID,
                    to: endFormationID,
                    athleteID: selectedAthleteID
                ) { t in
                    t.pathWaypoints[waypointIndex].holdCounts = min(
                        CGFloat(player.counts),
                        max(0, newValue)
                    )
                }
                onRefreshTransition()
            },
            onResetAllPaths: {
                store.mutateTransitionSpec(from: startFormationID, to: endFormationID) { spec in
                    for index in spec.athleteTransitions.indices {
                        spec.athleteTransitions[index].pathControlPoint = nil
                        spec.athleteTransitions[index].pathWaypoints = []
                    }
                }
                onRefreshTransition()
            },
            onUpgrade: onUpgrade
        )
    }
}

// MARK: - Selected Athlete Sidebar (Composed)

struct SelectedAthleteSidebarView: View {
    @ObservedObject var store: RoutineStore
    let formationID: UUID
    @Binding var selectedAthleteIDs: Set<UUID>
    var onDeleteAthlete: () -> Void = {}

    @ObservedObject var player: TransitionPlayer
    var startFormationID: UUID?
    var endFormationID: UUID?
    var isPro: Bool = true
    var onUpgrade: () -> Void = {}
    var onRefreshTransition: () -> Void = {}

    var onSwap: () -> Void = {}
    var isSwapMode: Bool = false
    /// In iPad portrait the transport lives in the bottom overlay, so the
    /// inspector hides its own copy to avoid two transport stacks on screen.
    var isIPadPortrait: Bool = false

    @State private var labelDraft: String = ""
    @State private var showDeleteConfirmation = false
    @State private var showingClearPathConfirmation = false

    private var selectedAthleteID: UUID? {
        selectedAthleteIDs.count == 1 ? selectedAthleteIDs.first : nil
    }

    private var athlete: RosterAthlete? {
        guard let selectedAthleteID else { return nil }
        return store.routine.roster.first { $0.id == selectedAthleteID }
    }

    private var formation: Formation? {
        guard let idx = store.formationIndex(id: formationID) else { return nil }
        return store.routine.formations[idx]
    }

    private var transition: AthleteTransition? {
        guard let selectedAthleteID else { return nil }
        return player.transitionSpec.athleteTransition(for: selectedAthleteID)
    }

    private var startFormationName: String {
        guard let startFormationID, let idx = store.formationIndex(id: startFormationID) else { return "" }
        return store.routine.formations[idx].name
    }

    private var endFormationName: String {
        guard let endFormationID, let idx = store.formationIndex(id: endFormationID) else { return "" }
        return store.routine.formations[idx].name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let athlete {
                // MARK: Name + Role
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        if isPro {
                            TextField("Label", text: $labelDraft)
                                .textFieldStyle(.roundedBorder)
                                .font(.headline)
                                .autocorrectionDisabled()
                                .onChange(of: labelDraft) { _, newValue in
                                    let clamped = String(newValue.prefix(3))
                                    if clamped != newValue { labelDraft = clamped }
                                    let trimmed = clamped.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !trimmed.isEmpty {
                                        store.mutateRosterAthlete(id: athlete.id) { a in
                                            a.label = trimmed
                                        }
                                    }
                                }
                                .onAppear { labelDraft = athlete.label }
                                .onChange(of: athlete.id) { _, _ in labelDraft = athlete.label }
                        } else {
                            Button(action: onUpgrade) {
                                HStack(spacing: 6) {
                                    Text(athlete.label)
                                        .font(.headline.monospaced())
                                    Image(systemName: "lock.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Rename athlete (Pro feature)")
                        }

                        Spacer()

                        Button(action: { selectedAthleteIDs = [] }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear selection")
                        .accessibilityHint("Deselect this athlete")
                        .help("Deselect this athlete")
                    }

                    AthleteRolePicker(
                        selectedRole: athlete.role,
                        compactLayout: true,
                        isPro: isPro,
                        onUpgrade: onUpgrade,
                        onSelect: { newRole in
                            store.mutateRosterAthlete(id: athlete.id) { a in
                                a.role = newRole
                            }
                        }
                    )
                }
                .padding(16)

                // MARK: Transport (hidden in iPad portrait — bottom overlay owns it)
                if !isIPadPortrait {
                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(startFormationName) \u{2192} \(endFormationName)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        HStack(spacing: 8) {
                            TransportControls.resetButton(player: player, size: 28)
                            TransportControls.playPauseButton(player: player, size: 28)
                            TransportControls.loopButton(player: player, size: 28)
                            Spacer()
                            TransportControls.swapButton(isActive: isSwapMode, size: 28, disabled: false, action: onSwap)
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
                    }
                    .padding(16)
                }

                // MARK: Timing + Path
                if let transition {
                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        // Start Delay
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Start Delay")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(TransitionCountFormatting.label(transition.moveDelayCounts))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            if isPro {
                                Slider(
                                    value: Binding(
                                        get: { transition.moveDelayCounts },
                                        set: { newValue in
                                            guard let selectedAthleteID, let startFormationID, let endFormationID else { return }
                                            store.mutateAthleteTransition(
                                                from: startFormationID, to: endFormationID,
                                                athleteID: selectedAthleteID
                                            ) { t in
                                                t.moveDelayCounts = min(CGFloat(player.counts), max(0, newValue))
                                            }
                                            onRefreshTransition()
                                        }
                                    ),
                                    in: 0...CGFloat(player.counts),
                                    step: 0.5
                                )
                                .accessibilityLabel("Start Delay")
                            } else {
                                HStack {
                                    Slider(value: .constant(0), in: 0...CGFloat(player.counts))
                                        .disabled(true)
                                    Button(action: onUpgrade) {
                                        Image(systemName: "lock.fill")
                                            .foregroundColor(.secondary)
                                    }
                                    .accessibilityLabel("Upgrade to Pro to adjust start delay")
                                    .accessibilityHint("Requires a Pro subscription to change the start delay timing")
                                    .help("Upgrade to Pro to adjust start delay")
                                }
                            }
                        }

                        // Path
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                Button {
                                    clearPath()
                                } label: {
                                    Label("Straight", systemImage: "line.diagonal")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    guard let selectedAthleteID, let startFormationID, let endFormationID else { return }
                                    let startAthlete = player.startAthletes.first { $0.id == selectedAthleteID }
                                    let endAthlete = player.endAthletes.first { $0.id == selectedAthleteID }
                                    guard let startAthlete, let endAthlete else { return }
                                    store.mutateAthleteTransition(
                                        from: startFormationID, to: endFormationID,
                                        athleteID: selectedAthleteID
                                    ) { t in
                                        guard t.pathControlPoint == nil && t.pathWaypoints.isEmpty else { return }
                                        let midpoint = CGPoint(
                                            x: (startAthlete.position.x + endAthlete.position.x) / 2,
                                            y: (startAthlete.position.y + endAthlete.position.y) / 2
                                        )
                                        t.pathControlPoint = CGPoint(x: midpoint.x, y: midpoint.y - 6)
                                    }
                                    onRefreshTransition()
                                } label: {
                                    Label("Curve", systemImage: "scribble")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }

                            Button {
                                guard isPro else {
                                    onUpgrade()
                                    return
                                }
                                guard let selectedAthleteID, let startFormationID, let endFormationID else { return }
                                let startAthlete = player.startAthletes.first { $0.id == selectedAthleteID }
                                let endAthlete = player.endAthletes.first { $0.id == selectedAthleteID }
                                guard let startAthlete, let endAthlete else { return }
                                store.mutateAthleteTransition(
                                    from: startFormationID, to: endFormationID,
                                    athleteID: selectedAthleteID
                                ) { t in
                                    let placement = PathWaypointPlacement.defaultPlacement(
                                        transition: t,
                                        start: startAthlete.position,
                                        end: endAthlete.position
                                    )
                                    t.pathControlPoint = nil
                                    t.pathWaypoints.insert(
                                        PathWaypoint(position: placement.point, isSmooth: true),
                                        at: placement.index
                                    )
                                }
                                onRefreshTransition()
                            } label: {
                                Label(
                                    isPro ? "Add Waypoint" : "Add Waypoint (Pro)",
                                    systemImage: isPro ? "plus.circle" : "lock.fill"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityHint(isPro ? "Add a waypoint to bend the path" : "Upgrade to Pro to add waypoints")

                            Text("Drag the waypoint handles on the floor to shape the curve.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(16)
                }

                Spacer()

                // MARK: Delete (bottom)
                Divider()
                Button(role: .destructive) {
                    onDeleteAthlete()
                } label: {
                    Label("Delete Athlete", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(16)
            } else if selectedAthleteIDs.count > 1 {
                MultiSelectionInspectorView(
                    count: selectedAthleteIDs.count,
                    compactLayout: true,
                    onClearSelection: { selectedAthleteIDs = [] },
                    store: store,
                    selectedAthleteIDs: selectedAthleteIDs,
                    player: player,
                    startFormationID: startFormationID,
                    endFormationID: endFormationID,
                    isPro: isPro,
                    onUpgrade: onUpgrade,
                    onRefreshTransition: onRefreshTransition
                )
            }
        }
        .background(.thinMaterial)
    }

    private func clearPath() {
        guard let selectedAthleteID, let startFormationID, let endFormationID else { return }
        store.mutateAthleteTransition(
            from: startFormationID, to: endFormationID,
            athleteID: selectedAthleteID
        ) { t in
            t.pathControlPoint = nil
            t.pathWaypoints = []
        }
        onRefreshTransition()
    }
}
