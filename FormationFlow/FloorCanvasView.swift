import SwiftUI

// MARK: - Floor Canvas View (Shared Rendering)

struct FloorCanvasView: View {
    let formation: Formation
    var selectedAthleteIds: Set<UUID> = []
    var startFormation: Formation? = nil
    var endFormation: Formation? = nil
    var collisionIds: Set<UUID> = []
    var pathCollisionIndices: Set<Int> = []
    var cellSize: CGFloat = 12
    var offset: CGPoint = .zero
    var swapSourceId: UUID? = nil
    var selectionRect: CGRect? = nil  // Selection box in screen coordinates (already offset)

    var body: some View {
        Canvas { context, _ in
            var ctx = context
            ctx.translateBy(x: offset.x, y: offset.y)
            drawGrid(in: &ctx)
            if let start = startFormation, let end = endFormation {
                drawPaths(in: &ctx, start: start, end: end)
            }
            drawAthletes(in: &ctx)

            // Draw selection rectangle (coordinates are relative to offset)
            if let rect = selectionRect {
                let adjustedRect = CGRect(
                    x: rect.origin.x - offset.x,
                    y: rect.origin.y - offset.y,
                    width: rect.width,
                    height: rect.height
                )
                var selPath = Path()
                selPath.addRect(adjustedRect)
                ctx.fill(selPath, with: .color(.blue.opacity(0.1)))
                ctx.stroke(
                    selPath,
                    with: .color(.blue.opacity(0.5)),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 3])
                )
            }
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
            let isSelected = selectedAthleteIds.contains(start.athletes[i].id)
            let pathColor: Color = isPathColliding ? .red : (isSelected ? .blue : .green)
            let lineWidth: CGFloat = isSelected ? 3 : 1.5

            let waypoints = start.athletes[i].pathWaypoints

            if !waypoints.isEmpty {
                // --- Multi-waypoint path ---
                let nodes = PathCalculations.waypointNodes(
                    from: start.athletes[i].position, to: end.athletes[i].position,
                    waypoints: waypoints
                )
                let screenNodes = nodes.map { CGPoint(x: $0.x * cellSize, y: $0.y * cellSize) }

                // Draw each segment
                for segIdx in 0..<(screenNodes.count - 1) {
                    let p0 = screenNodes[segIdx]
                    let p1 = screenNodes[segIdx + 1]

                    let waypointAtEnd: PathWaypoint? =
                        (segIdx < waypoints.count) ? waypoints[segIdx] : nil
                    let isSmooth = waypointAtEnd?.isSmooth ?? false

                    var segPath = Path()
                    segPath.move(to: p0)

                    if isSmooth {
                        let prev = segIdx > 0 ? screenNodes[segIdx - 1] : p0
                        let next = segIdx + 2 < screenNodes.count ? screenNodes[segIdx + 2] : p1
                        let c1 = CGPoint(
                            x: p0.x + (p1.x - prev.x) / 6.0,
                            y: p0.y + (p1.y - prev.y) / 6.0
                        )
                        let c2 = CGPoint(
                            x: p1.x - (next.x - p0.x) / 6.0,
                            y: p1.y - (next.y - p0.y) / 6.0
                        )
                        segPath.addCurve(to: p1, control1: c1, control2: c2)
                    } else {
                        segPath.addLine(to: p1)
                    }

                    context.stroke(
                        segPath,
                        with: .color(pathColor.opacity(0.4)),
                        lineWidth: lineWidth
                    )

                    // Draw "+" add-waypoint handle at segment midpoint when selected
                    if isSelected {
                        let mid = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
                        var plusBg = Path()
                        plusBg.addEllipse(
                            in: CGRect(x: mid.x - 8, y: mid.y - 8, width: 16, height: 16))
                        context.fill(plusBg, with: .color(.white.opacity(0.7)))
                        context.stroke(plusBg, with: .color(pathColor.opacity(0.5)), lineWidth: 1)
                        let plusText = Text("+").font(.system(size: 12, weight: .bold))
                            .foregroundColor(pathColor)
                        context.draw(plusText, at: mid, anchor: .center)
                    }
                }

                // Draw waypoint handles when selected
                if isSelected {
                    for wp in waypoints {
                        let wpScreen = CGPoint(
                            x: wp.position.x * cellSize, y: wp.position.y * cellSize)
                        let handleSize: CGFloat = wp.isSmooth ? 10 : 8
                        var handlePath = Path()
                        if wp.isSmooth {
                            handlePath.addEllipse(
                                in: CGRect(
                                    x: wpScreen.x - handleSize / 2, y: wpScreen.y - handleSize / 2,
                                    width: handleSize, height: handleSize))
                        } else {
                            // Sharp cut: draw a diamond
                            handlePath.move(
                                to: CGPoint(x: wpScreen.x, y: wpScreen.y - handleSize / 2))
                            handlePath.addLine(
                                to: CGPoint(x: wpScreen.x + handleSize / 2, y: wpScreen.y))
                            handlePath.addLine(
                                to: CGPoint(x: wpScreen.x, y: wpScreen.y + handleSize / 2))
                            handlePath.addLine(
                                to: CGPoint(x: wpScreen.x - handleSize / 2, y: wpScreen.y))
                            handlePath.closeSubpath()
                        }
                        context.fill(handlePath, with: .color(.white))
                        context.stroke(handlePath, with: .color(pathColor), lineWidth: 2)

                        // Double ring + pause icon for waypoints with hold duration
                        if wp.holdDuration > 0 {
                            let outerSize = handleSize + 6
                            var outerRing = Path()
                            outerRing.addEllipse(
                                in: CGRect(
                                    x: wpScreen.x - outerSize / 2, y: wpScreen.y - outerSize / 2,
                                    width: outerSize, height: outerSize))
                            context.stroke(outerRing, with: .color(.orange), lineWidth: 2)

                            // Small pause bars
                            let barW: CGFloat = 2
                            let barH: CGFloat = 6
                            let gap: CGFloat = 1.5
                            var pauseIcon = Path()
                            pauseIcon.addRect(CGRect(
                                x: wpScreen.x - gap - barW, y: wpScreen.y + outerSize / 2 + 2,
                                width: barW, height: barH))
                            pauseIcon.addRect(CGRect(
                                x: wpScreen.x + gap, y: wpScreen.y + outerSize / 2 + 2,
                                width: barW, height: barH))
                            context.fill(pauseIcon, with: .color(.orange))
                        }
                    }
                }
            } else {
                // --- Legacy single-control-point path ---
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
                        midPoint = PathCalculations.quadraticBezierPoint(
                            from: startPos, control: cp, to: endPos, t: t)
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
            }

            // Arrow at end position
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

            drawGhostCircle(in: &context, center: startPos)
            drawGhostCircle(in: &context, center: endPos)
        }
    }

    private func drawGrid(in context: inout GraphicsContext) {
        let width = CourtConstants.width * cellSize
        let height = CourtConstants.height * cellSize

        // Fine grid — 1 unit squares inside each panel
        var finePath = Path()
        for x in stride(from: 0, through: width, by: cellSize) {
            finePath.move(to: CGPoint(x: x, y: 0))
            finePath.addLine(to: CGPoint(x: x, y: height))
        }
        for y in stride(from: 0, through: height, by: cellSize) {
            finePath.move(to: CGPoint(x: 0, y: y))
            finePath.addLine(to: CGPoint(x: width, y: y))
        }
        context.stroke(finePath, with: .color(.gray.opacity(0.15)), lineWidth: 0.5)

        // Panel dividers — every 8 units (9 cols × 7 rows)
        var panelPath = Path()
        for col in stride(from: 8, through: Int(CourtConstants.width) - 1, by: 8) {
            let screenX = CGFloat(col) * cellSize
            panelPath.move(to: CGPoint(x: screenX, y: 0))
            panelPath.addLine(to: CGPoint(x: screenX, y: height))
        }
        for row in stride(from: 8, through: Int(CourtConstants.height) - 1, by: 8) {
            let screenY = CGFloat(row) * cellSize
            panelPath.move(to: CGPoint(x: 0, y: screenY))
            panelPath.addLine(to: CGPoint(x: width, y: screenY))
        }
        context.stroke(panelPath, with: .color(.gray.opacity(0.6)), lineWidth: 2.0)

        // Floor border
        var borderPath = Path()
        borderPath.addRect(CGRect(x: 0, y: 0, width: width, height: height))
        context.stroke(borderPath, with: .color(.gray.opacity(0.6)), lineWidth: 2.0)
    }

    private func drawGhostCircle(in context: inout GraphicsContext, center: CGPoint) {
        var ghost = Path()
        ghost.addEllipse(in: CGRect(x: center.x - 10, y: center.y - 10, width: 20, height: 20))
        context.stroke(
            ghost,
            with: .color(.gray.opacity(0.25)),
            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
        )
    }

    private func drawAthletes(in context: inout GraphicsContext) {
        for athlete in formation.athletes {
            let screenPos = CGPoint(
                x: athlete.position.x * cellSize,
                y: athlete.position.y * cellSize
            )

            let isSelected = selectedAthleteIds.contains(athlete.id)
            let isColliding = collisionIds.contains(athlete.id)

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

            if athlete.id == swapSourceId {
                var swapRing = Path()
                swapRing.addEllipse(
                    in: CGRect(
                        x: screenPos.x - (radius + 6),
                        y: screenPos.y - (radius + 6),
                        width: (radius + 6) * 2,
                        height: (radius + 6) * 2
                    ))
                context.stroke(
                    swapRing,
                    with: .color(.blue),
                    style: StrokeStyle(lineWidth: 3, dash: [6, 3])
                )
            }

            let labelColor: Color = isSelected ? roleColor : .white
            let text = Text(athlete.label)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(labelColor)

            context.draw(text, at: screenPos, anchor: .center)
        }
    }
}
