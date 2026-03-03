import SwiftUI

// MARK: - Formation Thumbnail View

struct FormationThumbnailView: View {
    let formation: Formation

    private let thumbWidth: CGFloat = 80
    private let thumbHeight: CGFloat = 46

    var body: some View {
        Canvas { context, _ in
            let cellSize = min(thumbWidth / CourtConstants.width, thumbHeight / CourtConstants.height)

            // Border
            let borderRect = CGRect(
                x: 0, y: 0, width: CourtConstants.width * cellSize, height: CourtConstants.height * cellSize)
            context.stroke(Path(borderRect), with: .color(.gray.opacity(0.4)), lineWidth: 0.5)

            // Athletes
            for athlete in formation.athletes {
                let x = athlete.position.x * cellSize
                let y = athlete.position.y * cellSize
                let radius: CGFloat = 4

                let roleColor = athlete.role.color

                var circle = Path()
                circle.addEllipse(
                    in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                context.fill(circle, with: .color(roleColor.opacity(0.85)))
            }
        }
        .frame(width: thumbWidth, height: thumbHeight)
        .background(.background)
    }
}
