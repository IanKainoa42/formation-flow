import SwiftUI

// MARK: - Athlete Detail Panel

struct AthleteDetailPanel: View {
    @Binding var athlete: Athlete
    @Binding var selectedAthleteId: UUID?
    var onDelete: () -> Void
    var onSwap: (() -> Void)? = nil
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Name", text: $athlete.label)
                    .font(.headline)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Athlete label")
                    .onChange(of: athlete.label) { _, newValue in
                        if newValue.count > 3 {
                            athlete.label = String(newValue.prefix(3))
                        }
                    }
                Spacer()
                if let onSwap {
                    Button(action: onSwap) {
                        Image(systemName: "arrow.triangle.swap")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .accessibilityLabel("Swap position with another athlete")
                }
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .accessibilityLabel("Delete athlete")
                .confirmationDialog(
                    "Delete \(athlete.label)?",
                    isPresented: $showDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive, action: onDelete)
                    Button("Cancel", role: .cancel) {}
                }
                Button(action: { selectedAthleteId = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .accessibilityLabel("Deselect athlete")
            }

            HStack(spacing: 8) {
                ForEach(AthleteRole.allCases, id: \.self) { role in
                    Button {
                        athlete.role = role
                    } label: {
                        VStack(spacing: 2) {
                            ZStack {
                                Circle()
                                    .fill(role.color)
                                    .frame(width: 28, height: 28)
                                if athlete.role == role {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundColor(.white)
                                }
                            }
                            Text(role.rawValue.capitalized)
                                .font(.system(size: 9))
                                .foregroundColor(athlete.role == role ? .primary : .secondary)
                        }
                    }
                    .accessibilityLabel("Set role to \(role.rawValue)")
                    .accessibilityAddTraits(athlete.role == role ? .isSelected : [])
                }
            }

            HStack {
                Image(systemName: "location")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(String(format: "%.1f ft, %.1f ft", athlete.position.x, athlete.position.y))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }
}
