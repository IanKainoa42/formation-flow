import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif


// MARK: - Floor Canvas View

struct FloorSelectionLasso {
    private(set) var points: [CGPoint]

    init(startPoint: CGPoint) {
        points = [startPoint]
    }

    var bounds: CGRect {
        guard let firstPoint = points.first else { return .null }

        var minX = firstPoint.x
        var maxX = firstPoint.x
        var minY = firstPoint.y
        var maxY = firstPoint.y

        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    var isTapCandidate: Bool {
        let selectionBounds = bounds
        return selectionBounds.width < 5 && selectionBounds.height < 5
    }

    mutating func append(_ point: CGPoint, minimumDistance: CGFloat = 6) {
        guard let lastPoint = points.last else {
            points = [point]
            return
        }

        // ⚡ Bolt Performance Optimization:
        // Use squared distance (dx*dx + dy*dy) to avoid expensive square root (hypot) in proximity checks.
        let dx = point.x - lastPoint.x
        let dy = point.y - lastPoint.y
        guard dx * dx + dy * dy >= minimumDistance * minimumDistance else { return }
        points.append(point)
    }

    func contains(_ point: CGPoint) -> Bool {
        guard points.count >= 3 else { return false }

        var containsPoint = false
        var previousPoint = points[points.count - 1]

        for currentPoint in points {
            let denominator = previousPoint.y - currentPoint.y
            let intersects = ((currentPoint.y > point.y) != (previousPoint.y > point.y))
                && (point.x < (previousPoint.x - currentPoint.x) * (point.y - currentPoint.y)
                    / (denominator == 0 ? CGFloat.leastNonzeroMagnitude : denominator)
                    + currentPoint.x)
            if intersects {
                containsPoint.toggle()
            }
            previousPoint = currentPoint
        }

        return containsPoint
    }

    func canvasPath(offset: CGPoint) -> Path {
        guard let firstPoint = points.first else { return Path() }

        var path = Path()
        path.move(to: CGPoint(x: firstPoint.x - offset.x, y: firstPoint.y - offset.y))

        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x - offset.x, y: point.y - offset.y))
        }

        if points.count >= 3 {
            path.closeSubpath()
        }

        return path
    }
}

struct FormationMirrorGuideRenderItem: Identifiable, Equatable, Hashable {
    let sourcePosition: CGPoint
    let mirroredPosition: CGPoint

    var id: String {
        [
            sourcePosition.x,
            sourcePosition.y,
            mirroredPosition.x,
            mirroredPosition.y
        ]
        .map { String(Int(($0 * 100).rounded())) }
        .joined(separator: "-")
    }
}

struct FloorCanvasView: View {
    let athletes: [RenderedAthlete]
    var selectedAthleteIDs: Set<UUID> = []
    var transitionPaths: [TransitionPathRenderItem] = []
    var endpointMarkers: [TransitionEndpointMarkerRenderItem] = []
    var alignmentGuides: [AlignmentGuideRenderItem] = []
    var mirrorGuides: [FormationMirrorGuideRenderItem] = []
    var collisionIDs: Set<UUID> = []
    var pathCollisionIDs: Set<UUID> = []
    var pathCollisionMarkerPositions: [CGPoint] = []
    var pathCollisionMarkerProgresses: [CGFloat] = []
    var blinkingResolvedIDs: Set<UUID> = []
    var blinkPhase: Int = 0
    var cellSize: CGFloat = 12
    var offset: CGPoint = .zero
    var swapSourceID: UUID? = nil
    var selectionLasso: FloorSelectionLasso? = nil
    var focusedEndpoint: PreviewEditableEndpoint? = nil
    var hasTransition: Bool = false
    var startFormationColor: Color = .clear
    var endFormationColor: Color = .clear
    var transitionProgress: CGFloat = 0
    var formationColor: Color = .white
    var useRoleColors: Bool = false
    var ghostAthletes: [RenderedAthlete] = []
    var ghostColor: Color = .white
    var ghostNextAthletes: [RenderedAthlete] = []
    var ghostNextColor: Color = .white
    var trailPositions: [UUID: [CGPoint]] = [:]
    var ghostTransitionPaths: [TransitionPathRenderItem] = []
    var ghostPrevPaths: [TransitionPathRenderItem] = []
    var ghostNextPaths: [TransitionPathRenderItem] = []
    var pathSketchPoints: [CGPoint] = []
    var hoveredHandlePosition: CGPoint? = nil
    var hoveredAthleteID: UUID? = nil
    var hoveredPathAthleteID: UUID? = nil
    var focusedPathHandle: CGPoint? = nil

    /// Scale factor so athlete markers stay proportional to the floor.
    /// Reference cellSize of 12 matches the original fixed-pixel radii.
    private var markerScale: CGFloat { cellSize / 12.0 }

    var body: some View {
        mainCanvas
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Formation court grid")
            .accessibilityValue("\(athletes.count) athletes on the court")
            .overlay { accessibilityOverlay }
    }

    private var mainCanvas: some View {
        Canvas { context, _ in
            var context = context
            context.translateBy(x: offset.x, y: offset.y)
            drawGrid(in: &context)
            drawGhostPrevPaths(in: &context)
            drawGhostAthletes(in: &context)
            drawGhostNextPaths(in: &context)
            drawGhostNextAthletes(in: &context)
            drawGhostTransitionPaths(in: &context)
            drawTrails(in: &context)
            drawAlignmentGuides(in: &context)
            drawMirrorGuides(in: &context)
            drawTransitionPaths(in: &context)
            drawPathSketch(in: &context)
            drawPathCollisionMarkers(in: &context)
            drawEndpointMarkers(in: &context)
            drawAthletes(in: &context)

            if let selectionLasso {
                let path = selectionLasso.canvasPath(offset: offset)
                context.fill(path, with: .color(formationColor.opacity(0.1)))
                context.stroke(
                    path,
                    with: .color(formationColor.opacity(0.45)),
                    style: StrokeStyle(lineWidth: 1.5, lineJoin: .round, dash: [6, 3])
                )
            }
        }
    }

    @Environment(\.accessibilityEnabled) private var accessibilityEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    private var accessibilityOverlay: some View {
        if accessibilityEnabled {
            ForEach(athletes) { athlete in
                AthleteAccessibilityElement(
                    athlete: athlete,
                    cellSize: cellSize,
                    offset: offset,
                    isSelected: selectedAthleteIDs.contains(athlete.id),
                    isColliding: collisionIDs.contains(athlete.id)
                )
            }
        }
    }


    private func drawPathCollisionMarkers(in context: inout GraphicsContext) {
        guard !pathCollisionMarkerPositions.isEmpty else { return }

        for (index, position) in pathCollisionMarkerPositions.enumerated() {
            let center = CGPoint(x: position.x * cellSize, y: position.y * cellSize)

            if let pulsePhase = collisionPulsePhase(forMarkerAt: index) {
                let expansion = pulsePhase * pulsePhase
                let pulseOpacity = pow(1.0 - pulsePhase, 0.65)
                let floorGlowR = (20 + (52 * expansion)) * markerScale
                var floorGlow = Path()
                floorGlow.addEllipse(
                    in: CGRect(
                        x: center.x - floorGlowR,
                        y: center.y - floorGlowR,
                        width: floorGlowR * 2,
                        height: floorGlowR * 2
                    )
                )
                context.fill(
                    floorGlow,
                    with: .radialGradient(
                        Gradient(colors: [
                            Color.red.opacity(0.34 * pulseOpacity),
                            Color.orange.opacity(0.18 * pulseOpacity),
                            Color.clear
                        ]),
                        center: center,
                        startRadius: 0,
                        endRadius: floorGlowR
                    )
                )
                context.stroke(
                    floorGlow,
                    with: .color(.red.opacity(0.42 * pulseOpacity)),
                    lineWidth: max(1.0, 1.5 * markerScale)
                )
            }

            let glowR = 10 * markerScale
            var glow = Path()
            glow.addEllipse(in: CGRect(x: center.x - glowR, y: center.y - glowR, width: glowR * 2, height: glowR * 2))
            context.fill(glow, with: .color(.red.opacity(0.22)))

            let star = eightPointStarPath(center: center, outerRadius: 8 * markerScale, innerRadius: 4.2 * markerScale)
            context.fill(star, with: .color(.white.opacity(0.95)))
            context.stroke(star, with: .color(.red), lineWidth: 2)
        }
    }

    private func collisionPulsePhase(forMarkerAt index: Int) -> CGFloat? {
        guard
            !reduceMotion,
            pathCollisionMarkerProgresses.indices.contains(index)
        else {
            return nil
        }

        let collisionProgress = pathCollisionMarkerProgresses[index]
        let pulseDuration: CGFloat = 0.22
        let elapsed = transitionProgress - collisionProgress
        guard elapsed >= 0, elapsed <= pulseDuration else { return nil }
        return elapsed / pulseDuration
    }

    private func eightPointStarPath(center: CGPoint, outerRadius: CGFloat, innerRadius: CGFloat) -> Path {
        var path = Path()
        let points = 16

        for index in 0..<points {
            let angle = (CGFloat(index) * .pi / 8) - (.pi / 2)
            let radius = index.isMultiple(of: 2) ? outerRadius : innerRadius
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )

            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        path.closeSubpath()
        return path
    }

    private func drawAlignmentGuides(in context: inout GraphicsContext) {
        guard !alignmentGuides.isEmpty else { return }

        for guide in alignmentGuides {
            var path = Path()
            let color = Color.orange.opacity(guide.emphasis == .strong ? 0.72 : 0.38)
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

    private func drawMirrorGuides(in context: inout GraphicsContext) {
        guard !mirrorGuides.isEmpty else { return }

        let axisX = (CourtConstants.width * cellSize) / 2
        let primaryColor = Color.white
        let shadowColor = Color.black
        var centerAxis = Path()
        centerAxis.move(to: CGPoint(x: axisX, y: 0))
        centerAxis.addLine(to: CGPoint(x: axisX, y: CourtConstants.height * cellSize))

        context.stroke(
            centerAxis,
            with: .color(shadowColor.opacity(0.45)),
            style: StrokeStyle(lineWidth: max(2.4, 2.8 * markerScale), lineCap: .round, dash: [2, 7])
        )
        context.stroke(
            centerAxis,
            with: .color(primaryColor.opacity(0.34)),
            style: StrokeStyle(lineWidth: max(1.1, 1.3 * markerScale), lineCap: .round, dash: [2, 7])
        )

        for guide in mirrorGuides {
            let source = scaledCanvasPoint(guide.sourcePosition)
            let target = scaledCanvasPoint(guide.mirroredPosition)
            let leftPoint = source.x <= target.x ? source : target
            let rightPoint = source.x <= target.x ? target : source
            let centerGap = max(4, 4.5 * markerScale)
            let centerY = source.y
            let leftEnd = CGPoint(x: max(leftPoint.x, axisX - centerGap), y: centerY)
            let rightStart = CGPoint(x: min(rightPoint.x, axisX + centerGap), y: centerY)
            let lineWidth = max(1.5, 1.8 * markerScale)

            var connector = Path()
            connector.move(to: leftPoint)
            connector.addLine(to: leftEnd)
            connector.move(to: rightStart)
            connector.addLine(to: rightPoint)

            context.stroke(
                connector,
                with: .color(shadowColor.opacity(0.7)),
                style: StrokeStyle(lineWidth: lineWidth + max(2.6, 3 * markerScale), lineCap: .butt, dash: [9, 5])
            )
            context.stroke(
                connector,
                with: .color(primaryColor.opacity(0.86)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt, dash: [9, 5])
            )

            let barHeight = max(13, 15 * markerScale)
            let barHalfHeight = barHeight / 2
            let barInset = max(2.2, 2.8 * markerScale)
            var bars = Path()
            for x in [leftPoint.x, axisX - barInset, axisX + barInset, rightPoint.x] {
                bars.move(to: CGPoint(x: x, y: centerY - barHalfHeight))
                bars.addLine(to: CGPoint(x: x, y: centerY + barHalfHeight))
            }
            context.stroke(
                bars,
                with: .color(shadowColor.opacity(0.75)),
                style: StrokeStyle(lineWidth: lineWidth + max(2.4, 2.8 * markerScale), lineCap: .round)
            )
            context.stroke(
                bars,
                with: .color(primaryColor.opacity(0.94)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )

            let targetDiamond = diamondPath(center: target, radius: max(5.5, 6.5 * markerScale))
            context.fill(targetDiamond, with: .color(shadowColor.opacity(0.35)))
            context.stroke(targetDiamond, with: .color(shadowColor.opacity(0.8)), lineWidth: max(3.4, 3.8 * markerScale))
            context.stroke(targetDiamond, with: .color(primaryColor.opacity(0.96)), lineWidth: max(1.3, 1.5 * markerScale))

            var sourceRing = Path()
            let sourceRadius = max(4.5, 5.5 * markerScale)
            sourceRing.addEllipse(
                in: CGRect(
                    x: source.x - sourceRadius,
                    y: source.y - sourceRadius,
                    width: sourceRadius * 2,
                    height: sourceRadius * 2
                )
            )
            context.stroke(
                sourceRing,
                with: .color(shadowColor.opacity(0.65)),
                style: StrokeStyle(lineWidth: max(3.2, 3.6 * markerScale), dash: [3, 3])
            )
            context.stroke(
                sourceRing,
                with: .color(primaryColor.opacity(0.74)),
                style: StrokeStyle(lineWidth: max(1.2, 1.4 * markerScale), dash: [3, 3])
            )
        }
    }

    private func scaledCanvasPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * cellSize, y: point.y * cellSize)
    }

    private func diamondPath(center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - radius))
        path.addLine(to: CGPoint(x: center.x + radius, y: center.y))
        path.addLine(to: CGPoint(x: center.x, y: center.y + radius))
        path.addLine(to: CGPoint(x: center.x - radius, y: center.y))
        path.closeSubpath()
        return path
    }

    private func isHandleHovered(at gridPosition: CGPoint) -> Bool {
        if let focused = focusedPathHandle {
            let dx = gridPosition.x - focused.x
            let dy = gridPosition.y - focused.y
            if dx * dx + dy * dy < 1.0 { return true }
        }
        guard let hovered = hoveredHandlePosition else { return false }
        let dx = gridPosition.x - hovered.x
        let dy = gridPosition.y - hovered.y
        return dx * dx + dy * dy < 1.0
    }

    private func drawPathSketch(in context: inout GraphicsContext) {
        guard pathSketchPoints.count >= 2 else { return }

        var path = Path()
        let first = scaledCanvasPoint(pathSketchPoints[0])
        path.move(to: first)

        for point in pathSketchPoints.dropFirst() {
            path.addLine(to: scaledCanvasPoint(point))
        }

        context.stroke(
            path,
            with: .color(.black.opacity(0.7)),
            style: StrokeStyle(lineWidth: max(5, 5.5 * markerScale), lineCap: .round, lineJoin: .round)
        )
        context.stroke(
            path,
            with: .color(.white.opacity(0.9)),
            style: StrokeStyle(lineWidth: max(2.2, 2.6 * markerScale), lineCap: .round, lineJoin: .round, dash: [10, 5])
        )
    }

    private func drawTransitionPaths(in context: inout GraphicsContext) {
        let pathOpacityMultiplier: CGFloat = focusedEndpoint != nil ? 0.5 : 1.0
        for item in transitionPaths {
            let start = CGPoint(x: item.startPosition.x * cellSize, y: item.startPosition.y * cellSize)
            let end = CGPoint(x: item.endPosition.x * cellSize, y: item.endPosition.y * cellSize)
            let isSelected = selectedAthleteIDs.contains(item.athleteID)
            let isColliding = pathCollisionIDs.contains(item.athleteID)
            let isBlinking = blinkingResolvedIDs.contains(item.athleteID)
            let resolvedColor: Color = isBlinking && blinkPhase % 2 == 0 ? .white : .green
            let pathColor: Color = isColliding ? .red : (isBlinking ? resolvedColor : (isSelected ? formationColor : .green))
            let isPathHovered = hoveredPathAthleteID == item.athleteID
            let isSelectedPathHovered = isSelected && isPathHovered
            let selectedLineWidth: CGFloat = 3
            let lineWidth: CGFloat = isSelected
                ? (isSelectedPathHovered ? selectedLineWidth * 1.6 : selectedLineWidth)
                : 1.5
            let pathOpacity = isSelectedPathHovered
                ? min(1.0, 0.68 * pathOpacityMultiplier)
                : 0.42 * pathOpacityMultiplier

            if !item.waypoints.isEmpty {
                let nodes = item.nodes

                for segmentIndex in 0..<(nodes.count - 1) {
                    let p0 = CGPoint(x: nodes[segmentIndex].x * cellSize, y: nodes[segmentIndex].y * cellSize)
                    let p1 = CGPoint(x: nodes[segmentIndex + 1].x * cellSize, y: nodes[segmentIndex + 1].y * cellSize)
                    let waypointAtEnd = segmentIndex < item.waypoints.count ? item.waypoints[segmentIndex] : nil

                    var segment = Path()
                    segment.move(to: p0)
                    if waypointAtEnd?.isSmooth == true {
                        let prevNode = segmentIndex > 0 ? nodes[segmentIndex - 1] : nodes[segmentIndex]
                        let nextNode = segmentIndex + 2 < nodes.count ? nodes[segmentIndex + 2] : nodes[segmentIndex + 1]
                        let prev = CGPoint(x: prevNode.x * cellSize, y: prevNode.y * cellSize)
                        let next = CGPoint(x: nextNode.x * cellSize, y: nextNode.y * cellSize)
                        let (c1, c2) = PathCalculations.catmullRomControlPoints(prev: prev, p0: p0, p1: p1, next: next)
                        segment.addCurve(to: p1, control1: c1, control2: c2)
                    } else {
                        segment.addLine(to: p1)
                    }

                    context.stroke(
                        segment,
                        with: .color(pathColor.opacity(pathOpacity)),
                        lineWidth: lineWidth
                    )

                }

                if isSelected {
                    for waypoint in item.waypoints {
                        let point = CGPoint(
                            x: waypoint.position.x * cellSize,
                            y: waypoint.position.y * cellSize
                        )
                        let isHovered = isHandleHovered(at: waypoint.position)
                        let baseSize: CGFloat = waypoint.isSmooth ? 14 : 12
                        let size: CGFloat = isHovered ? baseSize * 1.6 : baseSize

                        // Outer glow for visibility
                        var glow = Path()
                        let glowSize = size + (isHovered ? 10 : 6)
                        glow.addEllipse(
                            in: CGRect(
                                x: point.x - glowSize / 2,
                                y: point.y - glowSize / 2,
                                width: glowSize,
                                height: glowSize
                            )
                        )
                        context.fill(glow, with: .color(pathColor.opacity(isHovered ? 0.25 : 0.15)))

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
                        context.fill(handle, with: .color(pathColor.opacity(isHovered ? 0.3 : 0.18)))
                        context.stroke(handle, with: .color(pathColor), lineWidth: isHovered ? 3.5 : 2.5)

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
                            context.stroke(ring, with: .color(formationColor), lineWidth: 2)
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
                context.stroke(path, with: .color(pathColor.opacity(pathOpacity)), lineWidth: lineWidth)

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

                    let midpointGrid = CGPoint(x: midpoint.x / cellSize, y: midpoint.y / cellSize)
                    let isHovered = isHandleHovered(at: midpointGrid)
                    let handleRadius: CGFloat = isHovered ? 10 : 6
                    var handle = Path()
                    handle.addEllipse(
                        in: CGRect(x: midpoint.x - handleRadius, y: midpoint.y - handleRadius, width: handleRadius * 2, height: handleRadius * 2)
                    )
                    context.fill(handle, with: .color(.white))
                    context.stroke(handle, with: .color(pathColor), lineWidth: isHovered ? 3 : 2)
                }
            }

            let dx = end.x - start.x
            let dy = end.y - start.y

            // ⚡ Bolt Performance Optimization:
            // Use squared distance (dx*dx + dy*dy) to avoid expensive square root (hypot) in proximity checks.
            let squaredDistance = dx * dx + dy * dy
            guard squaredDistance > 25 else { // 5 squared is 25
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
        let panelWidth = 8 * cellSize
        let numCols = Int(CourtConstants.width / 8)

        // Alternating vertical panel fills
        let panelLight = Color(white: 0.17)
        let panelDark = Color(white: 0.13)
        for col in 0..<numCols {
            let x = CGFloat(col) * panelWidth
            let color = col % 2 == 0 ? panelLight : panelDark
            var rect = Path()
            rect.addRect(CGRect(x: x, y: 0, width: panelWidth, height: height))
            context.fill(rect, with: .color(color))
        }

        // Fine 1ft grid (very subtle)
        var fine = Path()
        for x in stride(from: 0, through: width, by: cellSize) {
            fine.move(to: CGPoint(x: x, y: 0))
            fine.addLine(to: CGPoint(x: x, y: height))
        }
        for y in stride(from: 0, through: height, by: cellSize) {
            fine.move(to: CGPoint(x: 0, y: y))
            fine.addLine(to: CGPoint(x: width, y: y))
        }
        context.stroke(fine, with: .color(.white.opacity(0.04)), lineWidth: 0.5)

        // Vertical panel dividers
        var verticalPanels = Path()
        for col in stride(from: 8, through: Int(CourtConstants.width) - 1, by: 8) {
            let x = CGFloat(col) * cellSize
            verticalPanels.move(to: CGPoint(x: x, y: 0))
            verticalPanels.addLine(to: CGPoint(x: x, y: height))
        }
        context.stroke(verticalPanels, with: .color(.white.opacity(0.12)), lineWidth: 1)

        // Horizontal panel lines (low opacity — like floor seams)
        var horizontalPanels = Path()
        for row in stride(from: 8, through: Int(CourtConstants.height) - 1, by: 8) {
            let y = CGFloat(row) * cellSize
            horizontalPanels.move(to: CGPoint(x: 0, y: y))
            horizontalPanels.addLine(to: CGPoint(x: width, y: y))
        }
        context.stroke(horizontalPanels, with: .color(.white.opacity(0.08)), lineWidth: 1)

        // Border
        var border = Path()
        border.addRect(CGRect(x: 0, y: 0, width: width, height: height))
        context.stroke(border, with: .color(.white.opacity(0.25)), lineWidth: 2)
    }

    private func drawGhostAthletes(in context: inout GraphicsContext) {
        guard !ghostAthletes.isEmpty else { return }
        let ghostStyle = StrokeStyle(lineWidth: 1 * markerScale, dash: [3, 3])
        for athlete in ghostAthletes {
            let point = CGPoint(x: athlete.position.x * cellSize, y: athlete.position.y * cellSize)
            // Previous = larger than current (formations grow as they recede into the past)
            let innerRadius = (athlete.role.markerRadius + 4) * markerScale
            let outerRadius = (athlete.role.markerRadius + 9) * markerScale

            // Inner circle — tinted with previous formation color
            var inner = Path()
            inner.addEllipse(in: CGRect(x: point.x - innerRadius, y: point.y - innerRadius, width: innerRadius * 2, height: innerRadius * 2))
            context.stroke(inner, with: .color(ghostColor.opacity(0.33)), style: ghostStyle)

            // Outer circle
            var outer = Path()
            outer.addEllipse(in: CGRect(x: point.x - outerRadius, y: point.y - outerRadius, width: outerRadius * 2, height: outerRadius * 2))
            context.stroke(outer, with: .color(ghostColor.opacity(0.22)), style: ghostStyle)
        }
    }

    private func drawGhostNextAthletes(in context: inout GraphicsContext) {
        guard !ghostNextAthletes.isEmpty else { return }
        for athlete in ghostNextAthletes {
            let point = CGPoint(x: athlete.position.x * cellSize, y: athlete.position.y * cellSize)
            // Next = smaller than current (hasn't happened yet, grows when it becomes current)
            let radius = (athlete.role.markerRadius - 4) * markerScale

            // Hollow outline — tinted with next formation color
            var ring = Path()
            ring.addEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            context.stroke(ring, with: .color(ghostNextColor.opacity(0.35)), lineWidth: 1.5 * markerScale)
        }
    }

    private func drawGhostPrevPaths(in context: inout GraphicsContext) {
        guard !ghostPrevPaths.isEmpty else { return }
        let style = StrokeStyle(lineWidth: 1 * markerScale, dash: [4, 5])
        for item in ghostPrevPaths {
            let start = CGPoint(x: item.startPosition.x * cellSize, y: item.startPosition.y * cellSize)
            let end = CGPoint(x: item.endPosition.x * cellSize, y: item.endPosition.y * cellSize)

            // ⚡ Bolt Performance Optimization:
            // Use squared distance (dx*dx + dy*dy) to avoid expensive square root (hypot) in proximity checks.
            let dx = end.x - start.x
            let dy = end.y - start.y
            guard dx * dx + dy * dy > 9 else { continue } // 3 squared is 9

            var path = Path()
            path.move(to: start)
            if !item.waypoints.isEmpty {
                let nodes = item.nodes
                for i in 0..<(nodes.count - 1) {
                    let p1 = CGPoint(x: nodes[i + 1].x * cellSize, y: nodes[i + 1].y * cellSize)
                    path.addLine(to: p1)
                }
            } else if let control = item.controlPoint {
                path.addQuadCurve(to: end, control: CGPoint(x: control.x * cellSize, y: control.y * cellSize))
            } else {
                path.addLine(to: end)
            }
            context.stroke(path, with: .color(ghostColor.opacity(0.22)), style: style)
        }
    }

    private func drawGhostNextPaths(in context: inout GraphicsContext) {
        guard !ghostNextPaths.isEmpty else { return }
        let style = StrokeStyle(lineWidth: 1 * markerScale, dash: [3, 4])
        for item in ghostNextPaths {
            let start = CGPoint(x: item.startPosition.x * cellSize, y: item.startPosition.y * cellSize)
            let end = CGPoint(x: item.endPosition.x * cellSize, y: item.endPosition.y * cellSize)

            // ⚡ Bolt Performance Optimization:
            // Use squared distance (dx*dx + dy*dy) to avoid expensive square root (hypot) in proximity checks.
            let dx = end.x - start.x
            let dy = end.y - start.y
            guard dx * dx + dy * dy > 9 else { continue } // 3 squared is 9

            var path = Path()
            path.move(to: start)
            if !item.waypoints.isEmpty {
                let nodes = item.nodes
                for i in 0..<(nodes.count - 1) {
                    let p1 = CGPoint(x: nodes[i + 1].x * cellSize, y: nodes[i + 1].y * cellSize)
                    path.addLine(to: p1)
                }
            } else if let control = item.controlPoint {
                path.addQuadCurve(to: end, control: CGPoint(x: control.x * cellSize, y: control.y * cellSize))
            } else {
                path.addLine(to: end)
            }
            context.stroke(path, with: .color(ghostNextColor.opacity(0.22)), style: style)
        }
    }

    private func drawGhostTransitionPaths(in context: inout GraphicsContext) {
        guard !ghostTransitionPaths.isEmpty else { return }

        let dashStyle = StrokeStyle(lineWidth: 1, dash: [4, 4])

        for item in ghostTransitionPaths {
            let start = CGPoint(x: item.startPosition.x * cellSize, y: item.startPosition.y * cellSize)
            let end = CGPoint(x: item.endPosition.x * cellSize, y: item.endPosition.y * cellSize)

            // Draw ghost start position — hollow circle showing where athlete was
            var startMarker = Path()
            let ghostR = 6 * markerScale
            startMarker.addEllipse(in: CGRect(x: start.x - ghostR, y: start.y - ghostR, width: ghostR * 2, height: ghostR * 2))
            context.stroke(startMarker, with: .color(.white.opacity(0.20)), style: dashStyle)

            // Build the full path (same logic as drawTransitionPaths but simplified — no handles)
            if !item.waypoints.isEmpty {
                let nodes = item.nodes
                let segmentCount = nodes.count - 1
                guard segmentCount > 0 else { continue }

                for segmentIndex in 0..<segmentCount {
                    let p0 = CGPoint(x: nodes[segmentIndex].x * cellSize, y: nodes[segmentIndex].y * cellSize)
                    let p1 = CGPoint(x: nodes[segmentIndex + 1].x * cellSize, y: nodes[segmentIndex + 1].y * cellSize)
                    let waypointAtEnd = segmentIndex < item.waypoints.count ? item.waypoints[segmentIndex] : nil

                    var segment = Path()
                    segment.move(to: p0)
                    if waypointAtEnd?.isSmooth == true {
                        let prevNode = segmentIndex > 0 ? nodes[segmentIndex - 1] : nodes[segmentIndex]
                        let nextNode = segmentIndex + 2 < nodes.count ? nodes[segmentIndex + 2] : nodes[segmentIndex + 1]
                        let prev = CGPoint(x: prevNode.x * cellSize, y: prevNode.y * cellSize)
                        let next = CGPoint(x: nextNode.x * cellSize, y: nextNode.y * cellSize)
                        let (c1, c2) = PathCalculations.catmullRomControlPoints(prev: prev, p0: p0, p1: p1, next: next)
                        segment.addCurve(to: p1, control1: c1, control2: c2)
                    } else {
                        segment.addLine(to: p1)
                    }

                    // Gradient opacity: stronger near end (where athlete arrived)
                    let segmentProgress = CGFloat(segmentIndex + 1) / CGFloat(segmentCount)
                    let opacity = 0.15 + 0.07 * segmentProgress  // 15% at start → 22% at end

                    context.stroke(segment, with: .color(.white.opacity(opacity)), style: dashStyle)
                }
            } else {
                // Simple path (straight or quadratic Bezier)
                var path = Path()
                path.move(to: start)
                if let control = item.controlPoint {
                    let controlPoint = CGPoint(x: control.x * cellSize, y: control.y * cellSize)
                    path.addQuadCurve(to: end, control: controlPoint)
                } else {
                    path.addLine(to: end)
                }
                // For simple paths, use a middle opacity since we can't easily gradient a single stroke
                context.stroke(path, with: .color(.white.opacity(0.20)), style: dashStyle)
            }
        }
    }

    private func drawTrails(in context: inout GraphicsContext) {
        guard !trailPositions.isEmpty else { return }

        for athlete in athletes {
            guard let positions = trailPositions[athlete.id], positions.count > 1 else { continue }
            let color: Color = useRoleColors ? athlete.role.color : formationColor

            for (i, position) in positions.enumerated() {
                let age = positions.count - 1 - i  // 0 = newest, count-1 = oldest
                guard age > 0 else { continue }  // skip newest (that's the main circle)

                let opacity = 0.06 + 0.04 * CGFloat(positions.count - 1 - age)
                let scale = 0.5 + 0.08 * CGFloat(positions.count - 1 - age)
                let radius = athlete.role.markerRadius * scale * markerScale

                let point = CGPoint(x: position.x * cellSize, y: position.y * cellSize)
                var trail = Path()
                trail.addEllipse(in: CGRect(
                    x: point.x - radius,
                    y: point.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
                context.fill(trail, with: .color(color.opacity(opacity)))
            }
        }
    }

    private func drawGhostCircle(in context: inout GraphicsContext, center: CGPoint) {
        let r = 10 * markerScale
        var ghost = Path()
        ghost.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        context.stroke(
            ghost,
            with: .color(.gray.opacity(0.38)),
            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
        )
    }

    private func drawEndpointMarkers(in context: inout GraphicsContext) {
        for marker in endpointMarkers {
            let point = CGPoint(x: marker.position.x * cellSize, y: marker.position.y * cellSize)
            let isSelected = selectedAthleteIDs.contains(marker.athleteID)
            let radius: CGFloat = (isSelected ? 8 : 6) * markerScale
            let color = marker.formationColor
            let isDimmed = focusedEndpoint != nil && marker.endpoint != focusedEndpoint
            let opacityMultiplier: CGFloat = isDimmed ? 0.2 : 1.0

            var dot = Path()
            dot.addEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))

            context.fill(dot, with: .color(color.opacity((isSelected ? 0.38 : 0.2) * opacityMultiplier)))
            context.stroke(
                dot,
                with: .color(color.opacity((isSelected ? 0.7 : 0.45) * opacityMultiplier)),
                style: StrokeStyle(lineWidth: isSelected ? 2 : 1.5, dash: [4, 3])
            )
        }
    }

    private func drawAthletes(in context: inout GraphicsContext) {
        for athlete in athletes {
            let point = CGPoint(x: athlete.position.x * cellSize, y: athlete.position.y * cellSize)
            let isSelected = selectedAthleteIDs.contains(athlete.id)
            let isColliding = collisionIDs.contains(athlete.id)
            let isHovered = athlete.id == hoveredAthleteID
            let hoverScale: CGFloat = isHovered ? 1.3 : 1.0

            if hasTransition {
                // Transition mode: athletes colored by formation, blending start→end
                let baseRadius = (isSelected ? athlete.role.markerRadius - 1 : athlete.role.markerRadius - 2) * markerScale
                let radius = baseRadius * hoverScale
                let formationColor = blendedFormationColor(progress: transitionProgress)
                let fillColor: Color = isColliding ? .red : formationColor
                let fillOpacity: CGFloat = isSelected ? 0.92 : (isHovered ? 0.88 : 0.78)
                let marker = athlete.role.markerPath(center: point, radius: radius)
                context.fill(marker, with: .color(fillColor.opacity(fillOpacity)))

                if isSelected || isHovered {
                    let strokeOpacity: CGFloat = isSelected ? 1.0 : 0.7
                    context.stroke(marker, with: .color(.white.opacity(strokeOpacity)), lineWidth: isSelected ? 3 : (isHovered ? 2.5 : 2))
                }

                let label = Text(athlete.label)
                    .font(.system(isHovered ? .caption : .caption2, design: .monospaced))
                    .foregroundColor(.white.opacity(isSelected || isHovered ? 0.95 : 0.85))
                context.draw(label, at: point, anchor: .center)
            } else {
                // Formation-only mode: colored by formation, role conveyed by shape
                let baseColor: Color = useRoleColors ? athlete.role.color : formationColor
                let fillColor: Color = isColliding ? .red : baseColor
                let baseRadius = (isSelected ? athlete.role.selectedMarkerRadius : athlete.role.markerRadius) * markerScale
                let radius = baseRadius * hoverScale
                let marker = athlete.role.markerPath(center: point, radius: radius)
                context.fill(marker, with: .color(fillColor.opacity(isSelected ? 0.92 : (isHovered ? 0.92 : 0.86))))

                if isSelected || isHovered {
                    let strokeOpacity: CGFloat = isSelected ? 1.0 : 0.7
                    context.stroke(marker, with: .color(.white.opacity(strokeOpacity)), lineWidth: isSelected ? 3.5 : (isHovered ? 3.5 : 3))
                }

                if isColliding {
                    let ring = athlete.role.markerPath(center: point, radius: radius + 4 * markerScale)
                    context.stroke(ring, with: .color(.red), lineWidth: 2 * markerScale)
                }

                if athlete.id == swapSourceID {
                    let ring = athlete.role.markerPath(center: point, radius: radius + 6 * markerScale)
                    context.stroke(
                        ring,
                        with: .color(formationColor),
                        style: StrokeStyle(lineWidth: 3, dash: [6, 3])
                    )
                }

                let labelColor = contrastingLabelColor(for: fillColor)
                let label = Text(athlete.label)
                    .font(.system(isHovered ? .caption : .caption, design: .monospaced))
                    .foregroundColor(labelColor.opacity(isSelected || isHovered ? 0.95 : 0.85))
                context.draw(label, at: point, anchor: .center)
            }
        }
    }

    private func blendedFormationColor(progress: CGFloat) -> Color {
        #if canImport(UIKit)
        let resolved1 = UIColor(startFormationColor)
        let resolved2 = UIColor(endFormationColor)
        #elseif canImport(AppKit)
        let resolved1 = NSColor(startFormationColor).usingColorSpace(.extendedSRGB) ?? NSColor()
        let resolved2 = NSColor(endFormationColor).usingColorSpace(.extendedSRGB) ?? NSColor()
        #else
        return startFormationColor
        #endif
        
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        
        #if canImport(UIKit) || canImport(AppKit)
        resolved1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        resolved2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        #endif
        
        let t = min(max(progress, 0), 1)
        return Color(
            red: r1 + (r2 - r1) * t,
            green: g1 + (g2 - g1) * t,
            blue: b1 + (b2 - b1) * t
        )
    }

    /// Returns white or black depending on the perceived brightness of the fill color.
    /// Uses relative luminance formula: 0.299*R + 0.587*G + 0.114*B
    private func contrastingLabelColor(for fillColor: Color) -> Color {
        #if canImport(UIKit)
        let uiColor = UIColor(fillColor)
        #elseif canImport(AppKit)
        let uiColor = NSColor(fillColor).usingColorSpace(.extendedSRGB) ?? NSColor()
        #else
        return .white
        #endif
        
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if canImport(UIKit) || canImport(AppKit)
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.5 ? .black : .white
    }
}

// MARK: - Athlete Accessibility Element

private struct AthleteAccessibilityElement: View {
    let athlete: RenderedAthlete
    let cellSize: CGFloat
    let offset: CGPoint
    let isSelected: Bool
    let isColliding: Bool

    private var accessibilityValue: String {
        var value = "Position: \(Int(athlete.position.x)) feet, \(Int(athlete.position.y)) feet"
        if isSelected { value += ", selected" }
        if isColliding { value += ", spacing alert" }
        return value
    }

    var body: some View {
        Color.clear
            .frame(width: 44, height: 44)
            .position(
                x: athlete.position.x * cellSize + offset.x,
                y: athlete.position.y * cellSize + offset.y
            )
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel("\(athlete.label), \(athlete.role.displayName)")
            .accessibilityValue(accessibilityValue)
    }
}
