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
    var onSelect: (AthleteRole) -> Void

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: compactLayout ? 68 : 74), spacing: 8)],
            spacing: 8
        ) {
            ForEach(AthleteRole.allCases, id: \.self) { role in
                Button {
                    onSelect(role)
                } label: {
                    VStack(spacing: compactLayout ? 4 : 6) {
                        AthleteRoleSwatch(role: role, isSelected: role == selectedRole)
                            .frame(width: compactLayout ? 24 : 28, height: compactLayout ? 24 : 28)
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
