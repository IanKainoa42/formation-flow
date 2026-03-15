import SwiftUI

// MARK: - Floor Canvas View

struct FloorCanvasView: View {
    let athletes: [RenderedAthlete]
    var selectedAthleteIDs: Set<UUID> = []
    var transitionPaths: [TransitionPathRenderItem] = []
    var endpointMarkers: [TransitionEndpointMarkerRenderItem] = []
    var alignmentGuides: [AlignmentGuideRenderItem] = []
    var collisionIDs: Set<UUID> = []
    var pathCollisionIDs: Set<UUID> = []
    var cellSize: CGFloat = 12
    var offset: CGPoint = .zero
    var swapSourceID: UUID? = nil
    var selectionRect: CGRect? = nil
    var focusedEndpoint: PreviewEditableEndpoint? = nil
    var hasTransition: Bool = false

    var body: some View {
        Canvas { context, _ in
            var context = context
            context.translateBy(x: offset.x, y: offset.y)
            drawGrid(in: &context)
            drawAlignmentGuides(in: &context)
            drawTransitionPaths(in: &context)
            drawEndpointMarkers(in: &context)
            drawAthletes(in: &context)

            if let selectionRect {
                let adjustedRect = CGRect(
                    x: selectionRect.origin.x - offset.x,
                    y: selectionRect.origin.y - offset.y,
                    width: selectionRect.width,
                    height: selectionRect.height
                )
                var path = Path()
                path.addRect(adjustedRect)
                context.fill(path, with: .color(.blue.opacity(0.1)))
                context.stroke(
                    path,
                    with: .color(.blue.opacity(0.45)),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 3])
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private func drawAlignmentGuides(in context: inout GraphicsContext) {
        guard !alignmentGuides.isEmpty else { return }

        for guide in alignmentGuides {
            var path = Path()
            let color = Color.accentColor.opacity(guide.emphasis == .strong ? 0.72 : 0.38)
            let lineWidth: CGFloat = guide.emphasis == .strong ? 2.5 : 1.5

            switch guide.geometry {
            case let .axis(orientation, value):
                let position = value * cellSize
                switch orientation {
                case .vertical:
                    path.move(to: CGPoint(x: position, y: 0))
                    path.addLine(to: CGPoint(x: position, y: CourtConstants.height * cellSize))
                case .horizontal:
                    path.move(to: CGPoint(x: 0, y: position))
                    path.addLine(to: CGPoint(x: CourtConstants.width * cellSize, y: position))
                }
            case let .line(start, end):
                path.move(to: CGPoint(x: start.x * cellSize, y: start.y * cellSize))
                path.addLine(to: CGPoint(x: end.x * cellSize, y: end.y * cellSize))
            }

            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: lineWidth, dash: guide.emphasis == .strong ? [8, 4] : [4, 4])
            )
        }
    }

    private func drawTransitionPaths(in context: inout GraphicsContext) {
        let pathOpacityMultiplier: CGFloat = focusedEndpoint != nil ? 0.5 : 1.0
        for item in transitionPaths {
            let start = CGPoint(x: item.startPosition.x * cellSize, y: item.startPosition.y * cellSize)
            let end = CGPoint(x: item.endPosition.x * cellSize, y: item.endPosition.y * cellSize)
            let isSelected = selectedAthleteIDs.contains(item.athleteID)
            let isColliding = pathCollisionIDs.contains(item.athleteID)
            let pathColor: Color = isColliding ? .red : (isSelected ? .blue : .green)
            let lineWidth: CGFloat = isSelected ? 3 : 1.5

            if !item.waypoints.isEmpty {
                let nodes = PathCalculations.waypointNodes(
                    from: item.startPosition,
                    to: item.endPosition,
                    waypoints: item.waypoints
                )
                let screenNodes = nodes.map { CGPoint(x: $0.x * cellSize, y: $0.y * cellSize) }

                for segmentIndex in 0..<(screenNodes.count - 1) {
                    let p0 = screenNodes[segmentIndex]
                    let p1 = screenNodes[segmentIndex + 1]
                    let waypointAtEnd = segmentIndex < item.waypoints.count ? item.waypoints[segmentIndex] : nil

                    var segment = Path()
                    segment.move(to: p0)
                    if waypointAtEnd?.isSmooth == true {
                        let prev = segmentIndex > 0 ? screenNodes[segmentIndex - 1] : p0
                        let next = segmentIndex + 2 < screenNodes.count ? screenNodes[segmentIndex + 2] : p1
                        let c1 = CGPoint(
                            x: p0.x + (p1.x - prev.x) / 6.0,
                            y: p0.y + (p1.y - prev.y) / 6.0
                        )
                        let c2 = CGPoint(
                            x: p1.x - (next.x - p0.x) / 6.0,
                            y: p1.y - (next.y - p0.y) / 6.0
                        )
                        segment.addCurve(to: p1, control1: c1, control2: c2)
                    } else {
                        segment.addLine(to: p1)
                    }

                    context.stroke(
                        segment,
                        with: .color(pathColor.opacity(0.42 * pathOpacityMultiplier)),
                        lineWidth: lineWidth
                    )

                    if isSelected {
                        let midpoint = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
                        var handleBackground = Path()
                        handleBackground.addEllipse(
                            in: CGRect(x: midpoint.x - 8, y: midpoint.y - 8, width: 16, height: 16)
                        )
                        context.fill(handleBackground, with: .color(.white.opacity(0.75)))
                        context.stroke(handleBackground, with: .color(pathColor.opacity(0.55)), lineWidth: 1)
                        context.draw(
                            Text("+")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(pathColor),
                            at: midpoint,
                            anchor: .center
                        )
                    }
                }

                if isSelected {
                    for waypoint in item.waypoints {
                        let point = CGPoint(
                            x: waypoint.position.x * cellSize,
                            y: waypoint.position.y * cellSize
                        )
                        let size: CGFloat = waypoint.isSmooth ? 10 : 8
                        var handle = Path()
                        if waypoint.isSmooth {
                            handle.addEllipse(
                                in: CGRect(
                                    x: point.x - size / 2,
                                    y: point.y - size / 2,
                                    width: size,
                                    height: size
                                )
                            )
                        } else {
                            handle.move(to: CGPoint(x: point.x, y: point.y - size / 2))
                            handle.addLine(to: CGPoint(x: point.x + size / 2, y: point.y))
                            handle.addLine(to: CGPoint(x: point.x, y: point.y + size / 2))
                            handle.addLine(to: CGPoint(x: point.x - size / 2, y: point.y))
                            handle.closeSubpath()
                        }
                        context.fill(handle, with: .color(.white))
                        context.stroke(handle, with: .color(pathColor), lineWidth: 2)

                        if waypoint.holdDuration > 0 {
                            let ringSize = size + 6
                            var ring = Path()
                            ring.addEllipse(
                                in: CGRect(
                                    x: point.x - ringSize / 2,
                                    y: point.y - ringSize / 2,
                                    width: ringSize,
                                    height: ringSize
                                )
                            )
                            context.stroke(ring, with: .color(.orange), lineWidth: 2)
                        }
                    }
                }
            } else {
                var path = Path()
                path.move(to: start)
                if let control = item.controlPoint {
                    let controlPoint = CGPoint(x: control.x * cellSize, y: control.y * cellSize)
                    path.addQuadCurve(to: end, control: controlPoint)
                } else {
                    path.addLine(to: end)
                }
                context.stroke(path, with: .color(pathColor.opacity(0.42 * pathOpacityMultiplier)), lineWidth: lineWidth)

                if isSelected {
                    let midpoint: CGPoint
                    if let control = item.controlPoint {
                        midpoint = PathCalculations.quadraticBezierPoint(
                            from: start,
                            control: CGPoint(x: control.x * cellSize, y: control.y * cellSize),
                            to: end,
                            t: 0.5
                        )
                    } else {
                        midpoint = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
                    }

                    var handle = Path()
                    handle.addEllipse(
                        in: CGRect(x: midpoint.x - 6, y: midpoint.y - 6, width: 12, height: 12)
                    )
                    context.fill(handle, with: .color(.white))
                    context.stroke(handle, with: .color(pathColor), lineWidth: 2)
                }
            }

            let dx = end.x - start.x
            let dy = end.y - start.y
            let distance = hypot(dx, dy)
            guard distance > 5 else {
                drawGhostCircle(in: &context, center: start)
                drawGhostCircle(in: &context, center: end)
                continue
            }

            let angle = atan2(dy, dx)
            let arrowLength: CGFloat = 10
            let arrowAngle: CGFloat = .pi / 6
            var arrow = Path()
            arrow.move(to: end)
            arrow.addLine(
                to: CGPoint(
                    x: end.x - arrowLength * cos(angle - arrowAngle),
                    y: end.y - arrowLength * sin(angle - arrowAngle)
                )
            )
            arrow.move(to: end)
            arrow.addLine(
                to: CGPoint(
                    x: end.x - arrowLength * cos(angle + arrowAngle),
                    y: end.y - arrowLength * sin(angle + arrowAngle)
                )
            )
            context.stroke(arrow, with: .color(pathColor.opacity(0.65 * pathOpacityMultiplier)), lineWidth: 2)

            drawGhostCircle(in: &context, center: start)
            drawGhostCircle(in: &context, center: end)
        }
    }

    private func drawGrid(in context: inout GraphicsContext) {
        let width = CourtConstants.width * cellSize
        let height = CourtConstants.height * cellSize

        var fine = Path()
        for x in stride(from: 0, through: width, by: cellSize) {
            fine.move(to: CGPoint(x: x, y: 0))
            fine.addLine(to: CGPoint(x: x, y: height))
        }
        for y in stride(from: 0, through: height, by: cellSize) {
            fine.move(to: CGPoint(x: 0, y: y))
            fine.addLine(to: CGPoint(x: width, y: y))
        }
        context.stroke(fine, with: .color(.gray.opacity(0.14)), lineWidth: 0.5)

        var panels = Path()
        for col in stride(from: 8, through: Int(CourtConstants.width) - 1, by: 8) {
            let x = CGFloat(col) * cellSize
            panels.move(to: CGPoint(x: x, y: 0))
            panels.addLine(to: CGPoint(x: x, y: height))
        }
        for row in stride(from: 8, through: Int(CourtConstants.height) - 1, by: 8) {
            let y = CGFloat(row) * cellSize
            panels.move(to: CGPoint(x: 0, y: y))
            panels.addLine(to: CGPoint(x: width, y: y))
        }
        context.stroke(panels, with: .color(.gray.opacity(0.58)), lineWidth: 2)

        var border = Path()
        border.addRect(CGRect(x: 0, y: 0, width: width, height: height))
        context.stroke(border, with: .color(.gray.opacity(0.58)), lineWidth: 2)
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

    private func drawEndpointMarkers(in context: inout GraphicsContext) {
        for marker in endpointMarkers {
            let point = CGPoint(x: marker.position.x * cellSize, y: marker.position.y * cellSize)
            let isSelected = selectedAthleteIDs.contains(marker.athleteID)
            let baseRadius = max(9, marker.role.markerRadius - (marker.style == .editable ? 2 : 4))
            let radius = baseRadius + (isSelected ? 2 : 0)
            let path = marker.role.markerPath(center: point, radius: radius)
            let color = marker.formationColor
            let isDimmed = focusedEndpoint != nil && marker.endpoint != focusedEndpoint
            let opacityMultiplier: CGFloat = isDimmed ? 0.2 : 1.0

            switch marker.style {
            case .editable:
                context.fill(path, with: .color(.white.opacity((isSelected ? 0.92 : 0.78) * opacityMultiplier)))
                context.stroke(
                    path,
                    with: .color(color.opacity((isSelected ? 1.0 : 0.82) * opacityMultiplier)),
                    style: StrokeStyle(lineWidth: isSelected ? 3 : 2.25)
                )

                let halo = marker.role.markerPath(center: point, radius: radius + 5)
                context.stroke(
                    halo,
                    with: .color(color.opacity((isSelected ? 0.45 : 0.28) * opacityMultiplier)),
                    style: StrokeStyle(lineWidth: isSelected ? 2 : 1.5, dash: [6, 3])
                )
            case .readOnly:
                context.fill(path, with: .color(color.opacity(0.08 * opacityMultiplier)))
                context.stroke(
                    path,
                    with: .color(color.opacity((isSelected ? 0.55 : 0.3) * opacityMultiplier)),
                    style: StrokeStyle(lineWidth: isSelected ? 2 : 1.25, dash: [4, 4])
                )
            }
        }
    }

    private func drawAthletes(in context: inout GraphicsContext) {
        for athlete in athletes {
            let point = CGPoint(x: athlete.position.x * cellSize, y: athlete.position.y * cellSize)
            let isSelected = selectedAthleteIDs.contains(athlete.id)
            let isColliding = collisionIDs.contains(athlete.id)

            if hasTransition {
                // Transition mode: white + smaller for selected, grey for others
                // Blue/red reserved for endpoint markers only
                let radius = isSelected ? athlete.role.markerRadius - 1 : athlete.role.markerRadius - 2
                let fillColor: Color = isColliding ? .red : (isSelected ? .white : .gray)
                let fillOpacity: CGFloat = isSelected ? 0.92 : 0.45
                let marker = athlete.role.markerPath(center: point, radius: radius)
                context.fill(marker, with: .color(fillColor.opacity(fillOpacity)))

                if isSelected {
                    context.stroke(marker, with: .color(.white.opacity(0.6)), lineWidth: 1.5)
                }

                let labelColor: Color = isSelected ? .black : .white
                let label = Text(athlete.label)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(labelColor.opacity(isSelected ? 0.8 : 0.7))
                context.draw(label, at: point, anchor: .center)
            } else {
                // Formation-only mode: normal role-colored rendering
                let fillColor: Color = isColliding ? .red : (isSelected ? .white : athlete.role.color)
                let radius = isSelected ? athlete.role.selectedMarkerRadius : athlete.role.markerRadius
                let marker = athlete.role.markerPath(center: point, radius: radius)
                context.fill(marker, with: .color(fillColor.opacity(0.86)))

                if isSelected {
                    context.stroke(marker, with: .color(athlete.role.color), lineWidth: 3)
                }

                if isColliding {
                    let ring = athlete.role.markerPath(center: point, radius: radius + 4)
                    context.stroke(ring, with: .color(.red), lineWidth: 2)
                }

                if athlete.id == swapSourceID {
                    let ring = athlete.role.markerPath(center: point, radius: radius + 6)
                    context.stroke(
                        ring,
                        with: .color(.blue),
                        style: StrokeStyle(lineWidth: 3, dash: [6, 3])
                    )
                }

                let labelColor: Color = isSelected ? athlete.role.color : .white
                let label = Text(athlete.label)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(labelColor)
                context.draw(label, at: point, anchor: .center)
            }
        }
    }
}
