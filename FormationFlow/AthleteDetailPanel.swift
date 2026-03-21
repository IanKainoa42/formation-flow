import SwiftUI

// MARK: - Inspector Components

struct AthleteInspectorView: View {
    private let swapButtonSymbolName = "arrow.triangle.2.circlepath"

    let athlete: RosterAthlete
    let position: CGPoint
    let isSwapMode: Bool
    let formationCount: Int
    var formationName: String = "Formation"
    var compactLayout: Bool = false
    var isPro: Bool = true
    var onUpgrade: () -> Void = {}
    var onUpdateLabel: (String) -> Void
    var onUpdateRole: (AthleteRole) -> Void
    var onSwap: () -> Void
    var onDelete: () -> Void
    var onClearSelection: () -> Void

    @State private var showDeleteConfirmation = false

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
                TextField(
                    "Label",
                    text: Binding(
                        get: { athlete.label },
                        set: { onUpdateLabel(String($0.prefix(4))) }
                    )
                )
                .textFieldStyle(.roundedBorder)
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
                Button(action: onSwap) {
                    Label(isSwapMode ? "Cancel Swap" : "Swap Position", systemImage: swapButtonSymbolName)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

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
                Button {
                    if isPro || role == .base {
                        onSelect(role)
                    } else {
                        onUpgrade()
                    }
                } label: {
                    VStack(spacing: compactLayout ? 4 : 6) {
                        ZStack {
                            AthleteRoleSwatch(role: role, isSelected: role == selectedRole)
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
                            .foregroundColor(role == selectedRole ? .primary : .secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, compactLayout ? 6 : 8)
                    .background(role == selectedRole ? Color.primary.opacity(0.08) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(role.displayName)
                .accessibilityValue(role == selectedRole ? "Selected" : "")
                .accessibilityHint("Double tap to set role to \(role.displayName)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Athlete role picker")
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

// MARK: - Sidebar Inspector (Reusable)

struct SidebarInspectorView: View {
    @ObservedObject var store: RoutineStore
    let formationID: UUID
    @Binding var selectedAthleteIDs: Set<UUID>
    var isCompactLayout: Bool = false
    var onSwap: () -> Void = {}
    var onDeleteAthlete: () -> Void = {}
    var isSwapMode: Bool = false

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let selectedRosterAthlete, let selectedPlacement {
                    AthleteInspectorView(
                        athlete: selectedRosterAthlete,
                        position: selectedPlacement.position,
                        isSwapMode: isSwapMode,
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
                        onSwap: onSwap,
                        onDelete: onDeleteAthlete,
                        onClearSelection: {
                            selectedAthleteIDs = []
                        }
                    )
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
}
