import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif


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
    var startFormationColor: Color = .clear
    var endFormationColor: Color = .clear
    var transitionProgress: CGFloat = 0
    var formationColor: Color = .white
    var useRoleColors: Bool = false
    var ghostAthletes: [RenderedAthlete] = []
    var trailPositions: [UUID: [CGPoint]] = [:]
    var hoveredHandlePosition: CGPoint? = nil
    var hoveredAthleteID: UUID? = nil
    var focusedPathHandle: CGPoint? = nil

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
            drawGhostAthletes(in: &context)
            drawTrails(in: &context)
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
                context.fill(path, with: .color(.orange.opacity(0.1)))
                context.stroke(
                    path,
                    with: .color(.orange.opacity(0.45)),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 3])
                )
            }
        }
    }

    private var accessibilityOverlay: some View {
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

    private func drawTransitionPaths(in context: inout GraphicsContext) {
        let pathOpacityMultiplier: CGFloat = focusedEndpoint != nil ? 0.5 : 1.0
        for item in transitionPaths {
            let start = CGPoint(x: item.startPosition.x * cellSize, y: item.startPosition.y * cellSize)
            let end = CGPoint(x: item.endPosition.x * cellSize, y: item.endPosition.y * cellSize)
            let isSelected = selectedAthleteIDs.contains(item.athleteID)
            let isColliding = pathCollisionIDs.contains(item.athleteID)
            let pathColor: Color = isColliding ? .red : (isSelected ? .orange : .green)
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
                        let midpointGrid = CGPoint(x: midpoint.x / cellSize, y: midpoint.y / cellSize)
                        let isHovered = isHandleHovered(at: midpointGrid)
                        let handleRadius: CGFloat = isHovered ? 12 : 8
                        var handleBackground = Path()
                        handleBackground.addEllipse(
                            in: CGRect(x: midpoint.x - handleRadius, y: midpoint.y - handleRadius, width: handleRadius * 2, height: handleRadius * 2)
                        )
                        context.fill(handleBackground, with: .color(.white.opacity(isHovered ? 0.9 : 0.75)))
                        context.stroke(handleBackground, with: .color(pathColor.opacity(isHovered ? 0.8 : 0.55)), lineWidth: isHovered ? 2 : 1)
                        context.draw(
                            Text("+")
                                .font(.system(size: isHovered ? 16 : 12, weight: .bold))
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
        for athlete in ghostAthletes {
            let point = CGPoint(x: athlete.position.x * cellSize, y: athlete.position.y * cellSize)
            let radius = athlete.role.markerRadius - 3
            let marker = athlete.role.markerPath(center: point, radius: radius)
            context.fill(marker, with: .color(.white.opacity(0.07)))
        }
    }

    private func drawTrails(in context: inout GraphicsContext) {
        guard !trailPositions.isEmpty else { return }

        let athleteLookup = Dictionary(athletes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for (athleteID, positions) in trailPositions {
            guard positions.count > 1, let athlete = athleteLookup[athleteID] else { continue }
            let color = athlete.role.color

            for (i, position) in positions.enumerated() {
                let age = positions.count - 1 - i  // 0 = newest, count-1 = oldest
                guard age > 0 else { continue }  // skip newest (that's the main circle)

                let opacity = 0.06 + 0.04 * CGFloat(positions.count - 1 - age)
                let scale = 0.5 + 0.08 * CGFloat(positions.count - 1 - age)
                let radius = athlete.role.markerRadius * scale

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
            let radius: CGFloat = isSelected ? 8 : 6
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
                let baseRadius = isSelected ? athlete.role.markerRadius - 1 : athlete.role.markerRadius - 2
                let radius = baseRadius * hoverScale
                let formationColor = blendedFormationColor(progress: transitionProgress)
                let fillColor: Color = isColliding ? .red : formationColor
                let fillOpacity: CGFloat = isSelected ? 0.92 : (isHovered ? 0.88 : 0.78)
                let marker = athlete.role.markerPath(center: point, radius: radius)
                context.fill(marker, with: .color(fillColor.opacity(fillOpacity)))

                if isSelected || isHovered {
                    let strokeColor: Color = isSelected ? .orange : .white
                    context.stroke(marker, with: .color(strokeColor.opacity(0.7)), lineWidth: isHovered ? 2.5 : 2)
                }

                let label = Text(athlete.label)
                    .font(.system(isHovered ? .caption : .caption2, design: .monospaced))
                    .foregroundColor(.white.opacity(isSelected || isHovered ? 0.95 : 0.85))
                context.draw(label, at: point, anchor: .center)
            } else {
                // Formation-only mode: colored by formation, role conveyed by shape
                let baseColor: Color = useRoleColors ? athlete.role.color : formationColor
                let fillColor: Color = isColliding ? .red : baseColor
                let baseRadius = isSelected ? athlete.role.selectedMarkerRadius : athlete.role.markerRadius
                let radius = baseRadius * hoverScale
                let marker = athlete.role.markerPath(center: point, radius: radius)
                context.fill(marker, with: .color(fillColor.opacity(isSelected ? 0.92 : (isHovered ? 0.92 : 0.86))))

                if isSelected || isHovered {
                    let strokeColor: Color = isSelected ? .orange : .white
                    context.stroke(marker, with: .color(strokeColor.opacity(0.7)), lineWidth: isHovered ? 3.5 : 3)
                }

                if isColliding {
                    let ring = athlete.role.markerPath(center: point, radius: radius + 4)
                    context.stroke(ring, with: .color(.red), lineWidth: 2)
                }

                if athlete.id == swapSourceID {
                    let ring = athlete.role.markerPath(center: point, radius: radius + 6)
                    context.stroke(
                        ring,
                        with: .color(.orange),
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
