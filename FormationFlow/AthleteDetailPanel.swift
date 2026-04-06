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
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Identity")
                    .font(.subheadline.weight(.semibold))
                TextField("Label", text: $labelDraft)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: labelDraft) { _, newValue in
                        let clamped = String(newValue.prefix(4))
                        if clamped != newValue { labelDraft = clamped }
                        let trimmed = clamped.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            onUpdateLabel(trimmed)
                        }
                    }
                    .onAppear { labelDraft = athlete.label }
                    .onChange(of: athlete.id) { _, _ in labelDraft = athlete.label }
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
                    showDeleteConfirmation = true
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
        .confirmationDialog(
            "Delete \(athlete.label)?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Athlete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove them from all \(formationCount) formations and their transitions. This cannot be undone.")
        }
    }
}

struct MultiSelectionInspectorView: View {
    let count: Int
    var compactLayout: Bool = false
    var onClearSelection: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: compactLayout ? 12 : 16) {
            Text("Selection")
                .font(.headline)
            Text("\(count) athletes selected")
                .font((compactLayout ? Font.title3 : .title3).weight(.semibold))
            Text("Drag on the floor to move the selected athletes together. Use Swap for one athlete at a time.")
                .font(.body)
                .foregroundColor(.secondary)
            Button("Clear Selection", action: onClearSelection)
                .buttonStyle(.bordered)
            Spacer()
        }
        .padding(compactLayout ? 16 : 20)
        .background(.thinMaterial)
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
    var onToggleWaypointSmooth: (Int) -> Void = { _ in }
    var onDeleteWaypoint: (UUID) -> Void = { _ in }
    var onAdjustWaypointHold: (Int, CGFloat) -> Void = { _, _ in }
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

            Text("Double-tap the selected athlete to add a waypoint, then drag the handles.")
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

            if compactLayout {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Hold")
                        Spacer()
                        Text(TransitionCountFormatting.label(waypoint.holdCounts))
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 8) {
                        Button("- 0.5") {
                            onAdjustWaypointHold(waypointIndex, -0.5)
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)

                        Button("+ 0.5") {
                            onAdjustWaypointHold(waypointIndex, 0.5)
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }
                }
            } else {
                HStack {
                    Text("Hold")
                    Spacer()
                    Button("- 0.5") {
                        onAdjustWaypointHold(waypointIndex, -0.5)
                    }
                    .buttonStyle(.bordered)

                    Text(TransitionCountFormatting.label(waypoint.holdCounts))
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 84)

                    Button("+ 0.5") {
                        onAdjustWaypointHold(waypointIndex, 0.5)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(compactLayout ? 12 : 14)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let selectedRosterAthlete, let selectedPlacement {
                    AthleteInspectorView(
                        athlete: selectedRosterAthlete,
                        position: selectedPlacement.position,
                        formationCount: store.routine.formations.count,
                        formationName: formation?.name ?? "Formation",
                        compactLayout: isCompactLayout,
                        onUpdateLabel: { newLabel in
                            store.mutateRosterAthlete(id: selectedRosterAthlete.id) { athlete in
                                athlete.label = newLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? athlete.label
                                    : newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        },
                        onUpdateRole: { newRole in
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
                        onClearSelection: { selectedAthleteIDs = [] }
                    )
                } else {
                    EmptyInspectorView(
                        title: "Inspector",
                        message: "Select one athlete to edit its label, role, and actions. Multi-select to move groups together.",
                        compactLayout: isCompactLayout
                    )
                }
            }
        }
        .background(.thinMaterial)
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
            onAdjustWaypointHold: { waypointIndex, delta in
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
                    let updatedValue = t.pathWaypoints[waypointIndex].holdCounts + delta
                    t.pathWaypoints[waypointIndex].holdCounts = min(
                        CGFloat(player.counts),
                        max(0, updatedValue)
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
