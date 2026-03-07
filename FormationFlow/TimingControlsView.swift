import SwiftUI

// MARK: - Timing Controls View

struct TimingControlsView: View {
    let label: String
    let delay: Double
    let duration: Double
    var onChange: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(label) starts after \(String(format: "%.1f", delay))s")
                .font(.subheadline)
            Slider(
                value: Binding(get: { delay }, set: onChange),
                in: 0...max(duration, 0.1),
                step: 0.1
            )
            HStack {
                Text("Moves first")
                Spacer()
                Text("Moves last")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
