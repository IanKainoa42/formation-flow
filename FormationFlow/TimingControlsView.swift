import SwiftUI

// MARK: - Timing Controls View

struct TimingControlsView: View {
    @Binding var athlete: Athlete
    var duration: Double = 2.0

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("\(athlete.label) - Delay: \(String(format: "%.1f", athlete.moveTiming))s")
                    .font(.caption)
                Spacer()
            }

            Slider(
                value: $athlete.moveTiming,
                in: 0...max(duration, 0.1),
                step: 0.1
            )
            .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                Text("Moves first")
                    .font(.caption2)
                    .foregroundColor(.gray)
                Spacer()
                Text("Moves last")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}
