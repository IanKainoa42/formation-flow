import SwiftUI

struct FormationThumbnailView: View {
    let athletes: [RenderedAthlete]
    let isSelected: Bool
    let accentColor: Color

    private let thumbnailWidth: CGFloat = 52
    private let thumbnailHeight: CGFloat = 40

    var body: some View {
        Canvas { context, size in
            for athlete in athletes {
                let x = athlete.position.x * size.width / CourtConstants.width
                let y = athlete.position.y * size.height / CourtConstants.height
                let dotRadius: CGFloat = 3
                let rect = CGRect(
                    x: x - dotRadius,
                    y: y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                )
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(athlete.role.color)
                )
            }
        }
        .frame(width: thumbnailWidth, height: thumbnailHeight)
        .background(Color(uiColor: .systemBackground).opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? accentColor : Color.gray.opacity(0.4), lineWidth: isSelected ? 2 : 1)
        )
    }
}

#Preview {
    FormationThumbnailView(
        athletes: [
            RenderedAthlete(id: UUID(), label: "K1", role: .base, position: CGPoint(x: 36, y: 20)),
            RenderedAthlete(id: UUID(), label: "F1", role: .flyer, position: CGPoint(x: 36, y: 28)),
            RenderedAthlete(id: UUID(), label: "S1", role: .spotter, position: CGPoint(x: 28, y: 36))
        ],
        isSelected: true,
        accentColor: .blue
    )
    .padding()
    .background(.black)
}
