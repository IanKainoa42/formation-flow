import SwiftUI

// MARK: - Floor Canvas View (Shared Rendering)

struct FloorCanvasView: View {
    let formation: Formation
    var selectedAthleteId: UUID? = nil
    var startFormation: Formation? = nil
    var endFormation: Formation? = nil
    var collisionIds: Set<UUID> = []
    var pathCollisionIndices: Set<Int> = []
    var cellSize: CGFloat = 12
    var offset: CGPoint = .zero

    let gridCols: CGFloat = 52
    let gridRows: CGFloat = 30

    var body: some View {
        Canvas { context, _ in
            var ctx = context
            ctx.translateBy(x: offset.x, y: offset.y)
            drawGrid(in: &ctx)
            if let start = startFormation, let end = endFormation {
                drawPaths(in: &ctx, start: start, end: end)
            }
            drawAthletes(in: &ctx)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    // MARK: - Path Drawing

    private func drawPaths(in context: inout GraphicsContext, start: Formation, end: Formation) {
        let count = min(start.athletes.count, end.athletes.count)

        for i in 0..<count {
            let startPos = CGPoint(
                x: start.athletes[i].position.x * cellSize,
                y: start.athletes[i].position.y * cellSize
            )
            let endPos = CGPoint(
                x: end.athletes[i].position.x * cellSize,
                y: end.athletes[i].position.y * cellSize
            )

            let isPathColliding = pathCollisionIndices.contains(i)
            let isSelected = start.athletes[i].id == selectedAthleteId
            let pathColor: Color = isPathColliding ? .red : (isSelected ? .blue : .green)
            let lineWidth: CGFloat = isSelected ? 3 : 1.5

            var pathLine = Path()
            pathLine.move(to: startPos)
            if let c = start.athletes[i].pathControlPoint {
                let controlPos = CGPoint(x: c.x * cellSize, y: c.y * cellSize)
                pathLine.addQuadCurve(to: endPos, control: controlPos)
            } else {
                pathLine.addLine(to: endPos)
            }
            context.stroke(
                pathLine,
                with: .color(pathColor.opacity(0.4)),
                lineWidth: lineWidth
            )

            // Draw midpoint handle if selected
            if isSelected {
                let t: CGFloat = 0.5
                let midPoint: CGPoint
                if let c = start.athletes[i].pathControlPoint {
                    let cp = CGPoint(x: c.x * cellSize, y: c.y * cellSize)
                    let u = 1.0 - t
                    let tt = t * t
                    let uu = u * u
                    let ut2 = 2.0 * u * t
                    midPoint = CGPoint(
                        x: uu * startPos.x + ut2 * cp.x + tt * endPos.x,
                        y: uu * startPos.y + ut2 * cp.y + tt * endPos.y
                    )
                } else {
                    midPoint = CGPoint(
                        x: startPos.x + (endPos.x - startPos.x) * t,
                        y: startPos.y + (endPos.y - startPos.y) * t
                    )
                }

                var handlePath = Path()
                handlePath.addEllipse(
                    in: CGRect(x: midPoint.x - 6, y: midPoint.y - 6, width: 12, height: 12))
                context.fill(handlePath, with: .color(.white))
                context.stroke(handlePath, with: .color(pathColor), lineWidth: 2)
            }

            let dx = endPos.x - startPos.x
            let dy = endPos.y - startPos.y
            let dist = hypot(dx, dy)
            guard dist > 5 else { continue }

            let angle = atan2(dy, dx)
            let arrowLen: CGFloat = 10
            let arrowAngle: CGFloat = .pi / 6

            var arrowPath = Path()
            arrowPath.move(to: endPos)
            arrowPath.addLine(
                to: CGPoint(
                    x: endPos.x - arrowLen * cos(angle - arrowAngle),
                    y: endPos.y - arrowLen * sin(angle - arrowAngle)
                ))
            arrowPath.move(to: endPos)
            arrowPath.addLine(
                to: CGPoint(
                    x: endPos.x - arrowLen * cos(angle + arrowAngle),
                    y: endPos.y - arrowLen * sin(angle + arrowAngle)
                ))
            context.stroke(
                arrowPath,
                with: .color(pathColor.opacity(0.6)),
                lineWidth: 2
            )

            var startGhost = Path()
            startGhost.addEllipse(
                in: CGRect(x: startPos.x - 10, y: startPos.y - 10, width: 20, height: 20))
            context.stroke(
                startGhost,
                with: .color(.gray.opacity(0.25)),
                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
            )

            var endGhost = Path()
            endGhost.addEllipse(
                in: CGRect(x: endPos.x - 10, y: endPos.y - 10, width: 20, height: 20))
            context.stroke(
                endGhost,
                with: .color(.gray.opacity(0.25)),
                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
            )
        }
    }

    private func drawGrid(in context: inout GraphicsContext) {
        let width = gridCols * cellSize
        let height = gridRows * cellSize

        var gridPath = Path()

        for x in stride(from: 0, through: width, by: cellSize) {
            gridPath.move(to: CGPoint(x: x, y: 0))
            gridPath.addLine(to: CGPoint(x: x, y: height))
        }

        for y in stride(from: 0, through: height, by: cellSize) {
            gridPath.move(to: CGPoint(x: 0, y: y))
            gridPath.addLine(to: CGPoint(x: width, y: y))
        }

        context.stroke(
            gridPath,
            with: .color(.gray.opacity(0.3)),
            lineWidth: 0.5
        )
    }

    private func drawAthletes(in context: inout GraphicsContext) {

        for athlete in formation.athletes {
            let screenPos = CGPoint(
                x: athlete.position.x * cellSize,
                y: athlete.position.y * cellSize
            )

            let isSelected = athlete.id == selectedAthleteId
            let isColliding = collisionIds.contains(athlete.id)

            // Bug 5 fix: role-based color coding
            let roleColor = athlete.role.color
            let color: Color = isColliding ? .red : (isSelected ? .white : roleColor)
            let radius: CGFloat = isSelected ? 18 : 14

            var circlePath = Path()
            circlePath.addEllipse(
                in: CGRect(
                    x: screenPos.x - radius,
                    y: screenPos.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))

            context.fill(circlePath, with: .color(color.opacity(0.85)))

            if isSelected {
                // Draw selection ring
                var ringPath = Path()
                ringPath.addEllipse(
                    in: CGRect(
                        x: screenPos.x - radius,
                        y: screenPos.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    ))
                context.stroke(ringPath, with: .color(roleColor), lineWidth: 3)
            }

            if isColliding {
                var warningRing = Path()
                warningRing.addEllipse(
                    in: CGRect(
                        x: screenPos.x - (radius + 4),
                        y: screenPos.y - (radius + 4),
                        width: (radius + 4) * 2,
                        height: (radius + 4) * 2
                    ))
                context.stroke(
                    warningRing,
                    with: .color(.red),
                    lineWidth: 2
                )
            }

            let labelColor: Color = isSelected ? roleColor : .white
            let displayLabel = athlete.label
            let text = Text(displayLabel)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(labelColor)

            context.draw(text, at: screenPos, anchor: .center)
        }
    }
}
