import SwiftUI

// MARK: - Athlete Detail Panel

struct AthleteDetailPanel: View {
    @Binding var athlete: Athlete
    @Binding var selectedAthleteId: UUID?
    var onDelete: () -> Void
    var onSwap: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Name", text: $athlete.label)
                    .font(.headline)
                    .textFieldStyle(.plain)
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
                }
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                Button(action: { selectedAthleteId = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 12) {
                ForEach(AthleteRole.allCases, id: \.self) { role in
                    Button {
                        athlete.role = role
                    } label: {
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
                    }
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
