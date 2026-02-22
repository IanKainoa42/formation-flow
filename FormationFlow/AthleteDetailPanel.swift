import SwiftUI

// MARK: - Athlete Detail Panel

struct AthleteDetailPanel: View {
    @Binding var athlete: Athlete
    @Binding var selectedAthleteId: UUID?

    private let roles: [(AthleteRole, Color)] = [
        (.base, .blue),
        (.flyer, .yellow),
        (.spotter, .green),
        (.backspot, .purple),
        (.tumbler, .orange),
    ]

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
                Button(action: { selectedAthleteId = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 12) {
                ForEach(roles, id: \.0) { role, color in
                    Button {
                        athlete.role = role
                    } label: {
                        ZStack {
                            Circle()
                                .fill(color)
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
