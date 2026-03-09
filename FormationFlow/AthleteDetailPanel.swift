import SwiftUI

// MARK: - Inspector Components

struct AthleteInspectorView: View {
    let athlete: RosterAthlete
    let position: CGPoint
    let isSwapMode: Bool
    let formationCount: Int
    var onUpdateLabel: (String) -> Void
    var onUpdateRole: (AthleteRole) -> Void
    var onSwap: () -> Void
    var onDelete: () -> Void
    var onClearSelection: () -> Void

    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
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
                AthleteRolePicker(selectedRole: athlete.role, onSelect: onUpdateRole)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Position")
                    .font(.subheadline.weight(.semibold))
                Text(String(format: "x %.1fft   y %.1fft", position.x, position.y))
                    .font(.system(.body, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Actions")
                    .font(.subheadline.weight(.semibold))
                Button(action: onSwap) {
                    Label(isSwapMode ? "Tap another athlete on the court" : "Swap Position", systemImage: "arrow.triangle.swap")
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
        .padding(20)
        .background(.thinMaterial)
        .confirmationDialog(
            "Delete \(athlete.label)?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Athlete", role: .destructive, action: onDelete)
        } message: {
            Text("This will remove them from all \(formationCount) formations and their transitions.")
        }
    }
}

struct MultiSelectionInspectorView: View {
    let count: Int
    var onClearSelection: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Selection")
                .font(.headline)
            Text("\(count) athletes selected")
                .font(.title3.weight(.semibold))
            Text("Drag on the floor to move the selected athletes together. Use Swap for one athlete at a time.")
                .font(.body)
                .foregroundColor(.secondary)
            Button("Clear Selection", action: onClearSelection)
                .buttonStyle(.bordered)
            Spacer()
        }
        .padding(20)
        .background(.thinMaterial)
    }
}

struct EmptyInspectorView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
            Text(message)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(20)
        .background(.thinMaterial)
    }
}

struct AthleteRolePicker: View {
    let selectedRole: AthleteRole
    var onSelect: (AthleteRole) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 8)], spacing: 8) {
            ForEach(AthleteRole.allCases, id: \.self) { role in
                Button {
                    onSelect(role)
                } label: {
                    VStack(spacing: 6) {
                        AthleteRoleSwatch(role: role, isSelected: role == selectedRole)
                            .frame(width: 28, height: 28)
                        Text(role.displayName)
                            .font(.caption2)
                            .foregroundColor(role == selectedRole ? .primary : .secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(role == selectedRole ? Color.primary.opacity(0.08) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct AthleteRoleSwatch: View {
    let role: AthleteRole
    let isSelected: Bool

    var body: some View {
        ZStack {
            if role == .stuntGroup {
                TriangleShape()
                    .fill(role.color)
            } else {
                Circle()
                    .fill(role.color)
            }

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.bold())
                    .foregroundColor(.white)
            }
        }
    }
}

private struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
