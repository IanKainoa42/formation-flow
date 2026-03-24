import SwiftUI

// MARK: - Timing Controls View

struct TimingControlsView: View {
    let label: String
    let delay: Double
    let duration: Double
    var onChange: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(label) starts after \(countLabel(delay))")
                .font(.subheadline)
            Slider(
                value: Binding(get: { delay }, set: onChange),
                in: 0...max(duration, 0.5),
                step: 0.5
            )
            .accessibilityLabel("\(label) starts after")
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

    private func countLabel(_ value: Double) -> String {
        let rounded = abs(value.rounded() - value) < 0.001
        let amount = rounded ? String(Int(value.rounded())) : String(format: "%.1f", value)
        let unit = abs(value - 1) < 0.001 ? "count" : "counts"
        return "\(amount) \(unit)"
    }
}
