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

struct PathSketchPreviewRenderItem: Identifiable {
    let athleteID: UUID
    let startPosition: CGPoint
    let endPosition: CGPoint
    let waypoints: [PathWaypoint]
    let isPrimary: Bool

    var id: UUID { athleteID }

    var nodes: [CGPoint] {
        PathCalculations.waypointNodes(
            from: startPosition,
            to: endPosition,
            waypoints: waypoints
        )
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
    var groupedAthleteIDSets: [Set<UUID>] = []
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
    /// Faint FormationFlow "FF" brand dots at floor center. On by default in the
    /// real editor; the onboarding demo floor switches it off (reads as a floating
    /// doodle over the dimmed hero court).
    var showCenterMark: Bool = true
    /// When true (preview, idle only), a light pulse continuously sweeps each
    /// transition path showing where every athlete is at that moment — an
    /// ambient, no-press preview of the move. Driven by its own clock, not the
    /// player's progress.
    var showPathPulse: Bool = false
    /// Seconds for the pulse to traverse a full transition (slowest athlete).
    /// Deliberately quicker than real playback — it's an ambient teaser, not a rehearsal.
    var pulsePeriodSeconds: Double = 1.3
    /// The transition's total length in counts (== seconds at 1× playback). Used
    /// to scale each athlete's pulse launch delay so a comet waits the same
    /// FRACTION of the transition that the athlete waits in real playback.
    var transitionCounts: Double = 8
    /// When true (preview, idle only — Step mode), each visible transition path
    /// is divided into `transitionCounts` equal arc-length segments with a small
    /// perpendicular tick at every count boundary: the "one step per count"
    /// footwork guide. Mutually exclusive with `showPathPulse` (Flow mode).
    var showCountSteps: Bool = false
    var ghostAthletes: [RenderedAthlete] = []
    var ghostColor: Color = .white
    var ghostNextAthletes: [RenderedAthlete] = []
    var ghostNextColor: Color = .white
    var trailPositions: [UUID: [CGPoint]] = [:]
    var ghostTransitionPaths: [TransitionPathRenderItem] = []
    var ghostPrevPaths: [TransitionPathRenderItem] = []
    var ghostNextPaths: [TransitionPathRenderItem] = []
    var pathSketchPoints: [CGPoint] = []
    var pathSketchPreviewPaths: [PathSketchPreviewRenderItem] = []
    var hoveredHandlePosition: CGPoint? = nil
    var hoveredAthleteID: UUID? = nil
    var hoveredPathAthleteID: UUID? = nil
    var focusedPathHandle: CGPoint? = nil
    var draggingAthleteIDs: Set<UUID> = []
    /// When true, non-selected athletes render faintly (path-focus mode) so the
    /// selected athlete and its route are the only things that read as active.
    var dimUnselectedAthletes: Bool = false

    /// Scale factor so athlete markers stay proportional to the floor.
    /// Reference cellSize of 12 matches the original fixed-pixel radii.
    private var markerScale: CGFloat { cellSize / 12.0 }

    var body: some View {
        mainCanvas
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // A fixed dark "stage" behind the court (not the system background) so
            // the floor reads as the hero in both light and dark mode — no white
            // letterbox margins when the wide court is fit to a tall phone screen.
            .background(Color(white: 0.08))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Formation court grid")
            .accessibilityValue("\(athletes.count) athletes on the court")
            .overlay { accessibilityOverlay }
    }

    private var mainCanvas: some View {
        // Only tick the timeline when a path is colliding (and motion is allowed),
        // so the collision blink animates without burning redraws when idle.
        let blinkActive = !pathCollisionIDs.isEmpty && !reduceMotion
        let blinkInterval: Double = 0.45
        let pulseActive = showPathPulse && !transitionPaths.isEmpty && !reduceMotion
        // Step mode animates a blip that snaps from count to count, so it needs the
        // same smooth clock as the comet. Under Reduce Motion it falls back to a
        // static dot at every step (no animation), so no fast clock then.
        let stepActive = showCountSteps && !transitionPaths.isEmpty && !reduceMotion
        // The comet needs a smooth ~30fps clock. The step LED only changes when it
        // snaps to the next beat (it holds steady between), so a coarser ~12fps is
        // plenty and roughly halves the redraw load. Everything else (selection
        // rings, warnings) is static and never forces a redraw on its own.
        let tickInterval: Double = pulseActive ? (1.0 / 30.0)
            : stepActive ? (1.0 / 12.0)
            : blinkActive ? blinkInterval
            : 86_400
        return TimelineView(.periodic(from: .now, by: tickInterval)) { timeline in
            Canvas { context, _ in
                var context = context
                context.translateBy(x: offset.x, y: offset.y)

                // Collision paths pulse red↔orange as a warning; static red when
                // blinking is off (no collisions or Reduce Motion).
                let collisionColor: Color = blinkActive
                    ? (Int(timeline.date.timeIntervalSinceReferenceDate / blinkInterval) % 2 == 0 ? .red : .orange)
                    : .red

                drawGrid(in: &context)
                let pulseState = pulseActive
                    ? pathPulseRenderState(time: timeline.date.timeIntervalSinceReferenceDate)
                    : nil
                let pulseLights = pulseState.map { activePulseLights(in: $0) } ?? []
                if !pulseLights.isEmpty {
                    drawPathPulseEnvironment(in: &context, lights: pulseLights)
                }
                drawGhostPrevPaths(in: &context)
                drawGhostAthletes(in: &context)
                drawGhostNextPaths(in: &context)
                drawGhostNextAthletes(in: &context)
                drawGhostTransitionPaths(in: &context)
                drawTrails(in: &context)
                drawAlignmentGuides(in: &context)
                drawMirrorGuides(in: &context)
                drawGroupHarnesses(in: &context)
                // Step mode: work out who can't reach their spot in the counts, and
                // whether the counts are spent (the rest phase). Once they're out of
                // time, their whole path blinks blue↔purple — the same treatment the
                // collision paths get in red↔orange.
                let stepCycle: StepCycle? = stepActive
                    ? computeStepCycle(time: timeline.date.timeIntervalSinceReferenceDate)
                    : nil
                let pathStepWarn: (ids: Set<UUID>, color: Color)? = {
                    guard let c = stepCycle, c.countsDone, !c.shortIDs.isEmpty else { return nil }
                    return (c.shortIDs, c.warnColor)
                }()
                drawTransitionPaths(in: &context, collisionColor: collisionColor, stepWarn: pathStepWarn)
                if showCountSteps {
                    if let cycle = stepCycle {
                        drawStepBlinks(in: &context, cycle: cycle)
                    } else if !stepActive {
                        // Reduce Motion: static dot at each step.
                        drawStepDotsStatic(in: &context)
                    }
                }
                drawPathSketchPreview(in: &context)
                drawPathSketch(in: &context)
                drawPathCollisionMarkers(in: &context)
                drawEndpointMarkers(in: &context)
                drawSelectedDestination(in: &context)
                drawAthletes(in: &context, pulseLights: pulseLights)

                if let pulseState {
                    drawPathPulses(in: &context, state: pulseState)
                }

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

    private func drawGroupHarnesses(in context: inout GraphicsContext) {
        guard !groupedAthleteIDSets.isEmpty else { return }
        let athletesByID = Dictionary(uniqueKeysWithValues: athletes.map { ($0.id, $0) })

        for groupIDs in groupedAthleteIDSets {
            let members = groupIDs.compactMap { athletesByID[$0] }
            guard members.count >= 2 else { continue }
            guard let harness = groupHarnessOutline(for: members) else { continue }

            let isActive = groupIDs.isSubset(of: selectedAthleteIDs)
            let harnessColor = isActive ? formationColor : Color.white
            let opacity: CGFloat = isActive ? 0.88 : 0.36

            context.fill(harness.path, with: .color(harnessColor.opacity(isActive ? 0.08 : 0.035)))
            context.stroke(
                harness.path,
                with: .color(harnessColor.opacity(opacity)),
                style: StrokeStyle(
                    lineWidth: isActive ? max(2, 2.4 * markerScale) : max(1.2, 1.5 * markerScale),
                    lineCap: .round,
                    lineJoin: .round,
                    dash: [8, 5]
                )
            )

        }
    }

    private func groupHarnessOutline(for members: [RenderedAthlete]) -> (path: Path, bounds: CGRect, center: CGPoint)? {
        let points = members.map { scaledCanvasPoint($0.position) }
        guard !points.isEmpty else { return nil }

        let summedCenter = points.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x, y: partial.y + point.y)
        }
        let center = CGPoint(
            x: summedCenter.x / CGFloat(points.count),
            y: summedCenter.y / CGFloat(points.count)
        )
        let padding = max(
            10,
            (members.map { $0.role.selectedMarkerRadius }.max() ?? 18) * markerScale + max(2, 3 * markerScale)
        )

        if points.count == 2 {
            let path = capsuleHarnessPath(from: points[0], to: points[1], radius: padding)
            return (path, path.boundingRect, center)
        }

        let hull = convexHull(points)
        guard hull.count >= 3 else {
            let path = circularHarnessPath(center: center, radius: padding)
            return (path, path.boundingRect, center)
        }

        let expanded = hull.map { point -> CGPoint in
            let dx = point.x - center.x
            let dy = point.y - center.y
            let length = max(0.001, (dx * dx + dy * dy).squareRoot())
            return CGPoint(
                x: point.x + (dx / length) * padding,
                y: point.y + (dy / length) * padding
            )
        }

        let path = smoothClosedPath(through: expanded)
        return (path, path.boundingRect, center)
    }

    private func capsuleHarnessPath(from start: CGPoint, to end: CGPoint, radius: CGFloat) -> Path {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0.001 else {
            return circularHarnessPath(center: start, radius: radius)
        }

        let ux = dx / length
        let uy = dy / length
        let nx = -uy * radius
        let ny = ux * radius

        let startA = CGPoint(x: start.x + nx, y: start.y + ny)
        let endA = CGPoint(x: end.x + nx, y: end.y + ny)
        let endB = CGPoint(x: end.x - nx, y: end.y - ny)
        let startB = CGPoint(x: start.x - nx, y: start.y - ny)

        var path = Path()
        path.move(to: startA)
        path.addLine(to: endA)
        path.addQuadCurve(to: endB, control: CGPoint(x: end.x + ux * radius, y: end.y + uy * radius))
        path.addLine(to: startB)
        path.addQuadCurve(to: startA, control: CGPoint(x: start.x - ux * radius, y: start.y - uy * radius))
        path.closeSubpath()
        return path
    }

    private func circularHarnessPath(center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        path.addEllipse(
            in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        )
        return path
    }

    private func smoothClosedPath(through points: [CGPoint]) -> Path {
        guard points.count >= 3 else { return Path() }

        func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }

        var path = Path()
        let last = points[points.count - 1]
        path.move(to: midpoint(last, points[0]))

        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            path.addQuadCurve(to: midpoint(current, next), control: current)
        }
        path.closeSubpath()
        return path
    }

    private func convexHull(_ points: [CGPoint]) -> [CGPoint] {
        let sorted = points.sorted {
            if abs($0.x - $1.x) > 0.001 { return $0.x < $1.x }
            return $0.y < $1.y
        }
        guard sorted.count > 2 else { return sorted }

        func cross(_ origin: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            (a.x - origin.x) * (b.y - origin.y) - (a.y - origin.y) * (b.x - origin.x)
        }

        var lower: [CGPoint] = []
        for point in sorted {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], point) <= 0 {
                lower.removeLast()
            }
            lower.append(point)
        }

        var upper: [CGPoint] = []
        for point in sorted.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], point) <= 0 {
                upper.removeLast()
            }
            upper.append(point)
        }

        lower.removeLast()
        upper.removeLast()
        return lower + upper
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

    private func drawPathSketchPreview(in context: inout GraphicsContext) {
        guard !pathSketchPreviewPaths.isEmpty else { return }

        for item in pathSketchPreviewPaths {
            let color: Color = item.isPrimary ? .white : formationColor
            let opacity: CGFloat = item.isPrimary ? 0.9 : 0.42
            let lineWidth: CGFloat = item.isPrimary ? max(3, 3.2 * markerScale) : max(1.6, 2.0 * markerScale)
            let style = StrokeStyle(
                lineWidth: lineWidth,
                lineCap: .round,
                lineJoin: .round,
                dash: item.isPrimary ? [] : [7, 5]
            )

            if item.waypoints.isEmpty {
                var path = Path()
                path.move(to: scaledCanvasPoint(item.startPosition))
                path.addLine(to: scaledCanvasPoint(item.endPosition))
                context.stroke(path, with: .color(color.opacity(opacity)), style: style)
            } else {
                let nodes = item.nodes
                for segmentIndex in 0..<(nodes.count - 1) {
                    let p0 = scaledCanvasPoint(nodes[segmentIndex])
                    let p1 = scaledCanvasPoint(nodes[segmentIndex + 1])
                    var segment = Path()
                    segment.move(to: p0)
                    if segmentUsesSmoothWaypoint(segmentIndex: segmentIndex, waypoints: item.waypoints) {
                        let prevNode = segmentIndex > 0 ? nodes[segmentIndex - 1] : nodes[segmentIndex]
                        let nextNode = segmentIndex + 2 < nodes.count ? nodes[segmentIndex + 2] : nodes[segmentIndex + 1]
                        let (c1, c2) = PathCalculations.catmullRomControlPoints(
                            prev: scaledCanvasPoint(prevNode),
                            p0: p0,
                            p1: p1,
                            next: scaledCanvasPoint(nextNode)
                        )
                        segment.addCurve(to: p1, control1: c1, control2: c2)
                    } else {
                        segment.addLine(to: p1)
                    }
                    context.stroke(segment, with: .color(color.opacity(opacity)), style: style)
                }
            }

            for waypoint in item.waypoints {
                let center = scaledCanvasPoint(waypoint.position)
                let radius: CGFloat = item.isPrimary ? max(3, 3.2 * markerScale) : max(2.2, 2.6 * markerScale)
                var dot = Path()
                dot.addEllipse(
                    in: CGRect(
                        x: center.x - radius,
                        y: center.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                )
                context.fill(dot, with: .color(color.opacity(item.isPrimary ? 0.85 : 0.45)))
                context.stroke(dot, with: .color(.black.opacity(0.55)), lineWidth: 1)
            }
        }
    }

    private func segmentUsesSmoothWaypoint(segmentIndex: Int, waypoints: [PathWaypoint]) -> Bool {
        let startsAtWaypoint = segmentIndex > 0
        let endsAtWaypoint = segmentIndex < waypoints.count

        if startsAtWaypoint && !waypoints[segmentIndex - 1].isSmooth { return false }
        if endsAtWaypoint && !waypoints[segmentIndex].isSmooth { return false }

        return startsAtWaypoint || endsAtWaypoint
    }

    private func drawTransitionPaths(in context: inout GraphicsContext, collisionColor: Color, stepWarn: (ids: Set<UUID>, color: Color)? = nil) {
        let pathOpacityMultiplier: CGFloat = focusedEndpoint != nil ? 0.5 : 1.0
        for item in transitionPaths {
            let start = CGPoint(x: item.startPosition.x * cellSize, y: item.startPosition.y * cellSize)
            let end = CGPoint(x: item.endPosition.x * cellSize, y: item.endPosition.y * cellSize)
            let isSelected = selectedAthleteIDs.contains(item.athleteID)
            let isColliding = pathCollisionIDs.contains(item.athleteID)
            // "Out of time" path — blinks blue↔purple, the same loud treatment a
            // collision path gets in red↔orange. Collision still wins if both apply.
            let isOutOfTime = !isColliding && (stepWarn?.ids.contains(item.athleteID) ?? false)
            let isAlert = isColliding || isOutOfTime
            // Color hierarchy: collision = pulsing red, out-of-time = pulsing
            // blue/purple, selected = white, everything else = neutral dim.
            let pathColor: Color = isColliding ? collisionColor
                : (isOutOfTime ? (stepWarn?.color ?? .blue) : (isSelected ? .white : Color(white: 0.72)))
            let isPathHovered = hoveredPathAthleteID == item.athleteID
            let isSelectedPathHovered = isSelected && isPathHovered
            let lineWidth: CGFloat = isAlert ? 2.4 : 2
            let basePathOpacity: CGFloat = isAlert ? 0.95 : (isSelected ? 0.85 : 0.4)
            let pathOpacity = isSelectedPathHovered ? 0.95 * pathOpacityMultiplier : basePathOpacity * pathOpacityMultiplier

            if !item.waypoints.isEmpty {
                let nodes = item.nodes

                for segmentIndex in 0..<(nodes.count - 1) {
                    let p0 = CGPoint(x: nodes[segmentIndex].x * cellSize, y: nodes[segmentIndex].y * cellSize)
                    let p1 = CGPoint(x: nodes[segmentIndex + 1].x * cellSize, y: nodes[segmentIndex + 1].y * cellSize)
                    var segment = Path()
                    segment.move(to: p0)
                    if segmentUsesSmoothWaypoint(segmentIndex: segmentIndex, waypoints: item.waypoints) {
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
                        let size: CGFloat = 13

                        // Outer glow for visibility
                        var glow = Path()
                        let glowSize = size + 8
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
                        context.stroke(handle, with: .color(pathColor), lineWidth: 2.5)

                        if waypoint.holdDuration > 0 {
                            // Ring radius scales with hold counts (capped) so longer holds
                            // visibly stand out without overlapping nearby handles.
                            let clamped = min(waypoint.holdDuration, 8)
                            let ringSize = size + 6 + clamped * 1.6
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

                            let holdLabel = "·\(TransitionCountFormatting.value(waypoint.holdDuration)) ct"
                            let labelText = Text(holdLabel)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(formationColor)
                            let resolved = context.resolve(labelText)
                            let labelSize = resolved.measure(in: CGSize(width: 80, height: 20))
                            let labelOrigin = CGPoint(
                                x: point.x + ringSize / 2 + 4,
                                y: point.y - labelSize.height / 2
                            )
                            context.draw(resolved, at: labelOrigin, anchor: .topLeading)
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
                    let handleRadius: CGFloat = 6
                    var handle = Path()
                    handle.addEllipse(
                        in: CGRect(x: midpoint.x - handleRadius, y: midpoint.y - handleRadius, width: handleRadius * 2, height: handleRadius * 2)
                    )
                    context.fill(handle, with: .color(.white))
                    context.stroke(handle, with: .color(pathColor.opacity(isHovered ? 1 : 0.85)), lineWidth: 2)
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

            // Direction is shown by chevrons marching along the whole path
            // (not just one arrowhead) so it stays readable amid ghost paths.
            // Chevron brightness follows the same hierarchy as the base stroke:
            // collision loudest, selected bright white, others dim/neutral.
            let chevronOpacity = (isAlert ? 0.95 : (isSelected ? 0.9 : 0.55)) * pathOpacityMultiplier
            drawDirectionChevrons(
                in: &context,
                along: pathPolyline(for: item),
                color: pathColor,
                opacity: chevronOpacity,
                spacing: max(8, 10 * markerScale),
                size: max(5, 6 * markerScale),
                lineWidth: max(1.8, 2.2 * markerScale)
            )

            drawGhostCircle(in: &context, center: start)
            drawGhostCircle(in: &context, center: end)
        }
    }

    /// A dense screen-space polyline approximating a transition path, covering
    /// straight, quadratic-curve, and multi-waypoint (Catmull-Rom / sharp)
    /// shapes. Used to march directional chevrons along the entire path.
    private func pathPolyline(for item: TransitionPathRenderItem) -> [CGPoint] {
        let start = CGPoint(x: item.startPosition.x * cellSize, y: item.startPosition.y * cellSize)
        let end = CGPoint(x: item.endPosition.x * cellSize, y: item.endPosition.y * cellSize)

        if !item.waypoints.isEmpty {
            let nodes = item.nodes.map { CGPoint(x: $0.x * cellSize, y: $0.y * cellSize) }
            guard nodes.count > 1 else { return [start, end] }
            var points: [CGPoint] = [nodes[0]]
            let samplesPerSegment = 8
            for segmentIndex in 0..<(nodes.count - 1) {
                let p0 = nodes[segmentIndex]
                let p1 = nodes[segmentIndex + 1]
                if segmentUsesSmoothWaypoint(segmentIndex: segmentIndex, waypoints: item.waypoints) {
                    let prevNode = segmentIndex > 0 ? nodes[segmentIndex - 1] : p0
                    let nextNode = segmentIndex + 2 < nodes.count ? nodes[segmentIndex + 2] : p1
                    let (c1, c2) = PathCalculations.catmullRomControlPoints(prev: prevNode, p0: p0, p1: p1, next: nextNode)
                    for s in 1...samplesPerSegment {
                        let t = CGFloat(s) / CGFloat(samplesPerSegment)
                        points.append(PathCalculations.cubicBezierPoint(p0: p0, c1: c1, c2: c2, p3: p1, t: t))
                    }
                } else {
                    points.append(p1)
                }
            }
            return points
        } else if let control = item.controlPoint {
            let c = CGPoint(x: control.x * cellSize, y: control.y * cellSize)
            let samples = 20
            return (0...samples).map { s in
                PathCalculations.quadraticBezierPoint(from: start, control: c, to: end, t: CGFloat(s) / CGFloat(samples))
            }
        } else {
            return [start, end]
        }
    }

    /// Stroke ">" chevrons evenly along a polyline, each pointing toward the
    /// path's destination, conveying travel direction over the whole length.
    private func drawDirectionChevrons(
        in context: inout GraphicsContext,
        along polyline: [CGPoint],
        color: Color,
        opacity: CGFloat,
        spacing: CGFloat,
        size: CGFloat,
        lineWidth: CGFloat
    ) {
        guard polyline.count >= 2, spacing > 0 else { return }
        let armAngle: CGFloat = .pi / 5
        var traveled: CGFloat = 0
        var nextMark = spacing * 0.5
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)

        for i in 1..<polyline.count {
            let a = polyline[i - 1]
            let b = polyline[i]
            let segDX = b.x - a.x
            let segDY = b.y - a.y
            let segLen = (segDX * segDX + segDY * segDY).squareRoot()
            guard segLen > 0.01 else { continue }
            let angle = atan2(segDY, segDX)
            let back = angle + .pi
            while nextMark <= traveled + segLen {
                let f = (nextMark - traveled) / segLen
                let tip = CGPoint(x: a.x + segDX * f, y: a.y + segDY * f)
                var chevron = Path()
                chevron.move(to: CGPoint(x: tip.x + size * cos(back - armAngle), y: tip.y + size * sin(back - armAngle)))
                chevron.addLine(to: tip)
                chevron.addLine(to: CGPoint(x: tip.x + size * cos(back + armAngle), y: tip.y + size * sin(back + armAngle)))
                context.stroke(chevron, with: .color(color.opacity(opacity)), style: style)
                nextMark += spacing
            }
            traveled += segLen
        }
    }

    // MARK: - Step Mode (one blip per count, preview idle)

    /// Step mode reuses the comet's group clock but quantizes motion: instead of
    /// gliding, a blip SNAPS to each successive count position along the path and
    /// blinks sharply on arrival — "step, step, step" at one step per count. Path
    /// length is divided into `transitionCounts` equal segments; during the k-th
    /// count window the blip sits at step k and decays until it jumps to k+1.
    /// One stride ≈ a yard (~half a grid square). The LED advances exactly one
    /// stride per beat, so the step length is a real footstep — not the path
    /// stretched across `counts` (which made steps arbitrarily long). Stride
    /// count therefore comes from the path's true length, not the count setting.
    private static let stepFeet: CGFloat = 3

    private struct StepLane {
        let item: TransitionPathRenderItem
        let poly: [CGPoint]
        let cum: [CGFloat]
        let total: CGFloat
        let strides: Int
        let delayBeats: Double
    }

    // "Out of time" alert blinks between the app's base-blue and backspot-purple
    // (brightened for the dark stage) — a distinct two-tone pulse that reads
    // nothing like the red↔orange collision blink.
    private static let warningBlue = Color(red: 0.24, green: 0.55, blue: 1.0)
    private static let warningPurple = Color(red: 0.72, green: 0.36, blue: 1.0)

    /// The state of the shared step cycle for one frame — lanes, timing, and who
    /// ran out of counts. Computed before paths are drawn so the path stroke can
    /// blink for out-of-time athletes, then reused to render the LED blips.
    private struct StepCycle {
        let lanes: [StepLane]
        let cap: Int
        let elapsedBeats: Double
        let shortIDs: Set<UUID>
        let countsDone: Bool   // the counts are spent — everyone has stopped
        let warnColor: Color   // blinks blue↔purple on the beat
    }

    private func computeStepCycle(time: TimeInterval) -> StepCycle? {
        // One beat per stride at the real tempo (0.4s at 150 BPM).
        let spc = Double(PathCalculations.secondsPerCount)
        // The athlete only has `counts` beats — at one stride per beat that caps
        // how far they get. Paths needing more strides than this can't be reached.
        let cap = max(1, Int(transitionCounts.rounded()))

        // Each lane takes as many strides as its real length holds yards.
        var lanes: [StepLane] = []
        lanes.reserveCapacity(transitionPaths.count)
        for item in transitionPaths {
            let poly = pathPolyline(for: item)
            guard poly.count >= 2 else { continue }
            let cum = cumulativeLengths(poly)
            guard let total = cum.last, total > 0 else { continue }
            let lengthFeet = total / max(cellSize, 0.0001)
            let strides = max(1, Int((lengthFeet / Self.stepFeet).rounded()))
            lanes.append(StepLane(
                item: item, poly: poly, cum: cum, total: total,
                strides: strides, delayBeats: Double(max(0, item.moveDelay))
            ))
        }
        guard !lanes.isEmpty else { return nil }

        let shortIDs = Set(lanes.filter { $0.strides > cap }.map { $0.item.athleteID })
        // Hold the parked formation longer when someone's out of time, so the
        // blue↔purple alert blinks a few times before the cycle relaunches.
        let restBeats: Double = shortIDs.isEmpty ? 1.0 : 4.0
        // Shared cycle: longest (delay + strides it actually takes, capped) + rest.
        let maxBeats = lanes.map { $0.delayBeats + Double(min($0.strides, cap)) }.max() ?? 1
        let cycleSeconds = (maxBeats + restBeats) * spc
        guard cycleSeconds > 0 else { return nil }
        let elapsedBeats = time.truncatingRemainder(dividingBy: cycleSeconds) / spc
        // The counts are "done" once the last athlete has taken their final stride.
        let countsDone = elapsedBeats >= maxBeats
        let warnColor = (Int(time / spc) % 2 == 0) ? Self.warningBlue : Self.warningPurple

        return StepCycle(
            lanes: lanes, cap: cap, elapsedBeats: elapsedBeats,
            shortIDs: shortIDs, countsDone: countsDone, warnColor: warnColor
        )
    }

    private func drawStepBlinks(in context: inout GraphicsContext, cycle: StepCycle) {
        let pathOpacityMultiplier: CGFloat = focusedEndpoint != nil ? 0.5 : 1.0
        let cap = cycle.cap
        let warnColor = cycle.warnColor

        let (sr, sg, sb) = rgbComponents(startFormationColor)
        let (er, eg, eb) = rgbComponents(endFormationColor)

        for lane in cycle.lanes {
            let movingStrides = min(lane.strides, cap)   // where the athlete actually stops
            let cameUpShort = lane.strides > cap
            let stopFrac = CGFloat(movingStrides) / CGFloat(lane.strides)
            let isSelected = selectedAthleteIDs.contains(lane.item.athleteID)
            // The "out of time" flag only fires once the counts are spent.
            let flagOutOfTime = cameUpShort && cycle.countsDone

            // A blinking TIMER badge marks the spot they couldn't reach in time.
            if flagOutOfTime {
                let dest = CGPoint(x: lane.item.endPosition.x * cellSize, y: lane.item.endPosition.y * cellSize)
                drawUnreachedBadge(in: &context, at: dest, color: warnColor, opacity: pathOpacityMultiplier)
            }

            let localBeats = cycle.elapsedBeats - lane.delayBeats
            guard localBeats >= 0 else { continue }

            if localBeats < Double(movingStrides) {
                // Stride we're on. The LED snaps to it and holds full brightness
                // for the whole beat (no fade) — a persisting light that hops a
                // yard per beat, like a Mattel Electronic Football blip.
                let stepIndex = min(movingStrides, Int(floor(localBeats)) + 1)
                let posFrac = CGFloat(stepIndex) / CGFloat(lane.strides)
                let center = pointAtArcLength(posFrac * lane.total, pts: lane.poly, cum: lane.cum)
                let color = isSelected
                    ? Color.white
                    : Color(red: sr + (er - sr) * posFrac, green: sg + (eg - sg) * posFrac, blue: sb + (eb - sb) * posFrac)
                drawStepBlip(in: &context, center: center, intensity: pathOpacityMultiplier, color: color)
            } else {
                // Out of beats: hold at the stop point — the destination if reached,
                // short of it (blinking blue/purple once counts are done) if not.
                let center = pointAtArcLength(stopFrac * lane.total, pts: lane.poly, cum: lane.cum)
                let color = flagOutOfTime ? warnColor : (isSelected ? Color.white : endFormationColor)
                drawStepBlip(in: &context, center: center, intensity: pathOpacityMultiplier, color: color)
            }
        }
    }

    /// "Ran out of counts" badge — a bold TIMER glyph on the spot the athlete
    /// couldn't reach in time. The `color` blinks blue↔purple on the beat, and a
    /// stopwatch glyph (not the collision star/triangle) keeps the two problems
    /// reading as different. The path stroke itself carries the rest of the blink.
    private func drawUnreachedBadge(in context: inout GraphicsContext, at dest: CGPoint, color: Color, opacity: CGFloat) {
        // Blinking badge + white stopwatch glyph = a clear, distinct "out of time" flag.
        let badgeR = max(8.5, 9.5 * markerScale)
        var badge = Path()
        badge.addEllipse(in: CGRect(x: dest.x - badgeR, y: dest.y - badgeR, width: badgeR * 2, height: badgeR * 2))
        context.fill(badge, with: .color(color.opacity(0.95 * opacity)))
        context.stroke(badge, with: .color(.white.opacity(0.55 * opacity)), lineWidth: max(1, markerScale))

        let glyph = context.resolve(
            Text(Image(systemName: "timer"))
                .font(.system(size: badgeR * 1.15, weight: .bold))
                .foregroundColor(.white.opacity(0.95))
        )
        context.draw(glyph, at: dest, anchor: .center)
    }

    /// A static spotlight on the selected athlete's destination — concentric white
    /// rings (like the ghost rings) so it's obvious where they end up. White for
    /// contrast, no pulse/bounce: it never forces a redraw.
    private func drawSelectedDestination(in context: inout GraphicsContext) {
        guard hasTransition, selectedAthleteIDs.count == 1, let selected = selectedAthleteIDs.first else { return }
        guard let item = transitionPaths.first(where: { $0.athleteID == selected }) else { return }
        let dest = CGPoint(x: item.endPosition.x * cellSize, y: item.endPosition.y * cellSize)

        let radii: [CGFloat] = [8, 13, 18].map { $0 * markerScale }
        for (index, r) in radii.enumerated() {
            var ring = Path()
            ring.addEllipse(in: CGRect(x: dest.x - r, y: dest.y - r, width: r * 2, height: r * 2))
            context.stroke(
                ring,
                with: .color(.white.opacity(0.85 - CGFloat(index) * 0.22)),
                style: StrokeStyle(lineWidth: max(1.5, 2 * markerScale))
            )
        }
        let cr = max(3, 3.5 * markerScale)
        var core = Path()
        core.addEllipse(in: CGRect(x: dest.x - cr, y: dest.y - cr, width: cr * 2, height: cr * 2))
        context.fill(core, with: .color(.white.opacity(0.95)))
    }

    /// A steady LED: solid colored core + white-hot center + fixed soft glow.
    /// Sizes don't track intensity, so it reads as a persisting light that holds
    /// on its step and snaps to the next — not a twinkle that fades each beat.
    private func drawStepBlip(in context: inout GraphicsContext, center: CGPoint, intensity: CGFloat, color: Color) {
        let clamped = min(max(intensity, 0), 1)
        let glowR = max(10, 11 * markerScale)
        var glow = Path()
        glow.addEllipse(in: CGRect(x: center.x - glowR, y: center.y - glowR, width: glowR * 2, height: glowR * 2))
        context.fill(
            glow,
            with: .radialGradient(
                Gradient(colors: [color.opacity(0.5 * clamped), color.opacity(0.14 * clamped), .clear]),
                center: center,
                startRadius: 0,
                endRadius: glowR
            )
        )
        let coreR = max(3.2, 3.6 * markerScale)
        var core = Path()
        core.addEllipse(in: CGRect(x: center.x - coreR, y: center.y - coreR, width: coreR * 2, height: coreR * 2))
        context.fill(core, with: .color(color.opacity(0.98 * clamped)))
        let hotR = coreR * 0.5
        var hot = Path()
        hot.addEllipse(in: CGRect(x: center.x - hotR, y: center.y - hotR, width: hotR * 2, height: hotR * 2))
        context.fill(hot, with: .color(.white.opacity(0.95 * clamped)))
    }

    /// Reduce Motion fallback: a static dot at every step position (no blink),
    /// so the "one step per count" spacing is still legible without animation.
    private func drawStepDotsStatic(in context: inout GraphicsContext) {
        let pathOpacityMultiplier: CGFloat = focusedEndpoint != nil ? 0.5 : 1.0

        for item in transitionPaths {
            let isSelected = selectedAthleteIDs.contains(item.athleteID)
            let color: Color = isSelected ? .white : Color(white: 0.72)
            let opacity = (isSelected ? 0.9 : 0.5) * pathOpacityMultiplier

            let polyline = pathPolyline(for: item)
            guard polyline.count >= 2 else { continue }
            let cum = cumulativeLengths(polyline)
            guard let total = cum.last, total > 0 else { continue }
            // One dot per ~3ft stride, matching the animated step length.
            let lengthFeet = total / max(cellSize, 0.0001)
            let strides = max(1, Int((lengthFeet / Self.stepFeet).rounded()))
            let dotR = max(2.2, 2.6 * markerScale)

            for i in 1...strides {
                let p = pointAtArcLength(total * CGFloat(i) / CGFloat(strides), pts: polyline, cum: cum)
                var dot = Path()
                dot.addEllipse(in: CGRect(x: p.x - dotR, y: p.y - dotR, width: dotR * 2, height: dotR * 2))
                context.fill(dot, with: .color(color.opacity(opacity)))
            }
        }
    }

    // MARK: - Ambient Path Pulse (preview, idle)

    /// Cumulative arc length at each polyline vertex (cum[0] == 0).
    private func cumulativeLengths(_ pts: [CGPoint]) -> [CGFloat] {
        var cum: [CGFloat] = [0]
        cum.reserveCapacity(pts.count)
        for i in 1..<pts.count {
            let dx = pts[i].x - pts[i - 1].x
            let dy = pts[i].y - pts[i - 1].y
            cum.append(cum[i - 1] + (dx * dx + dy * dy).squareRoot())
        }
        return cum
    }

    /// Point on the polyline at a given arc length (clamped to the path).
    private func pointAtArcLength(_ s: CGFloat, pts: [CGPoint], cum: [CGFloat]) -> CGPoint {
        guard let total = cum.last, total > 0 else { return pts.first ?? .zero }
        let target = min(max(s, 0), total)
        var lo = cum.count - 2
        for i in 1..<cum.count where cum[i] >= target {
            lo = i - 1
            break
        }
        let segLen = cum[lo + 1] - cum[lo]
        let f = segLen > 0 ? (target - cum[lo]) / segLen : 0
        return CGPoint(
            x: pts[lo].x + (pts[lo + 1].x - pts[lo].x) * f,
            y: pts[lo].y + (pts[lo + 1].y - pts[lo].y) * f
        )
    }

    /// Extracts RGB (0...1) from a SwiftUI Color for cheap inline lerping.
    private func rgbComponents(_ color: Color) -> (CGFloat, CGFloat, CGFloat) {
        #if canImport(UIKit)
        let resolved = UIColor(color)
        #elseif canImport(AppKit)
        let resolved = NSColor(color).usingColorSpace(.extendedSRGB) ?? NSColor()
        #else
        return (1, 1, 1)
        #endif
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if canImport(UIKit) || canImport(AppKit)
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        return (r, g, b)
    }

    /// Geometry + timing for one athlete's pulse within the shared group cycle.
    private struct PulseLane {
        let item: TransitionPathRenderItem
        let poly: [CGPoint]
        let cum: [CGFloat]
        let total: CGFloat
        let start: Double    // launch offset (move delay) in seconds
        let travel: Double   // time to traverse the path at constant floor-speed
    }

    private struct PulseRenderState {
        let lanes: [PulseLane]
        let cycleT: Double
        let startRed: CGFloat
        let startGreen: CGFloat
        let startBlue: CGFloat
        let endRed: CGFloat
        let endGreen: CGFloat
        let endBlue: CGFloat
        let endGlow: Color
    }

    private struct PulseLight {
        let athleteID: UUID
        let center: CGPoint
        let color: Color
        let intensity: CGFloat
    }

    private struct PulseMarkerInfluence {
        /// Unit vector pointing away from the light source.
        let shadowDirection: CGPoint
        let color: Color
        let strength: CGFloat
    }

    private func pulseGlowColor(progress: CGFloat, state: PulseRenderState) -> Color {
        let t = min(max(progress, 0), 1)
        return Color(
            red: state.startRed + (state.endRed - state.startRed) * t,
            green: state.startGreen + (state.endGreen - state.startGreen) * t,
            blue: state.startBlue + (state.endBlue - state.startBlue) * t
        )
    }

    private func pathPulseRenderState(time: TimeInterval) -> PulseRenderState? {
        let items = transitionPaths
        guard !items.isEmpty else { return nil }

        let restPause: Double = 0.7      // group holds, parked, before relaunching

        // Glow tint blends start→end formation color along the path so the light
        // reads directionally — trailing hue = where they came from, leading hue =
        // where they're going. Extract endpoints once; lerp per segment is cheap.
        let (sr, sg, sb) = rgbComponents(startFormationColor)
        let (er, eg, eb) = rgbComponents(endFormationColor)
        let endGlow = Color(red: er, green: eg, blue: eb)

        // Constant on-screen floor speed: a comet covers `referenceFeet` in one
        // pulse period, so travel time scales with path length — longer moves take
        // longer to arrive (and flash later).
        let referenceFeet: CGFloat = 28
        let secondsPerFoot = pulsePeriodSeconds / Double(max(referenceFeet, 1))

        // First pass: geometry + per-athlete travel/launch times.
        var lanes: [PulseLane] = []
        lanes.reserveCapacity(items.count)
        for item in items {
            let dx = item.endPosition.x - item.startPosition.x
            let dy = item.endPosition.y - item.startPosition.y
            guard dx * dx + dy * dy > 1 else { continue }
            let poly = pathPolyline(for: item)
            guard poly.count >= 2 else { continue }
            let cum = cumulativeLengths(poly)
            guard let total = cum.last, total > 0 else { continue }
            let lengthFeet = total / max(cellSize, 0.0001)
            let travel = max(0.25, Double(lengthFeet) * secondsPerFoot)
            // Launch delay = the same fraction of the transition the athlete waits
            // in real playback (moveDelay counts out of `transitionCounts`), mapped
            // onto the pulse's own "one full move" time unit. A full-transition
            // delay therefore parks the comet for one whole reference traverse and,
            // because it pushes out lastArrival below, lengthens the group cycle —
            // mirroring how a delayed athlete extends the real transition.
            let delayFraction = Double(max(0, item.moveDelay)) / max(transitionCounts, 0.5)
            let start = delayFraction * pulsePeriodSeconds
            lanes.append(PulseLane(item: item, poly: poly, cum: cum, total: total, start: start, travel: travel))
        }
        guard !lanes.isEmpty else { return nil }

        // One shared cycle for the whole group: everyone launches together, each
        // parks on arrival and waits until the slowest lands, then all relaunch.
        let lastArrival = lanes.map { $0.start + $0.travel }.max() ?? pulsePeriodSeconds
        let cycle = lastArrival + restPause
        let cycleT = time.truncatingRemainder(dividingBy: cycle)

        return PulseRenderState(
            lanes: lanes,
            cycleT: cycleT,
            startRed: sr,
            startGreen: sg,
            startBlue: sb,
            endRed: er,
            endGreen: eg,
            endBlue: eb,
            endGlow: endGlow
        )
    }

    private func activePulseLights(in state: PulseRenderState) -> [PulseLight] {
        let flashDecay: Double = 0.32
        let restingGlow: CGFloat = 0.08
        let laneDensityDamping = min(CGFloat(1), CGFloat(3 / sqrt(Double(max(state.lanes.count, 1)))))
        var lights: [PulseLight] = []
        lights.reserveCapacity(state.lanes.count)

        for lane in state.lanes {
            let localT = state.cycleT - lane.start
            let progress = lane.travel > 0 ? min(max(localT / lane.travel, 0), 1) : (localT >= 0 ? 1 : 0)

            if localT >= 0, progress < 1 {
                let head = CGFloat(progress)
                let center = pointAtArcLength(head * lane.total, pts: lane.poly, cum: lane.cum)
                let color = pulseGlowColor(progress: head, state: state)
                lights.append(
                    PulseLight(
                        athleteID: lane.item.athleteID,
                        center: center,
                        color: color,
                        intensity: laneDensityDamping
                    )
                )
            }

            let sinceArrival = state.cycleT - (lane.start + lane.travel)
            if sinceArrival >= 0 {
                let flash = max(restingGlow, CGFloat(exp(-sinceArrival / flashDecay)))
                let center = CGPoint(x: lane.item.endPosition.x * cellSize, y: lane.item.endPosition.y * cellSize)
                lights.append(
                    PulseLight(
                        athleteID: lane.item.athleteID,
                        center: center,
                        color: state.endGlow,
                        intensity: flash * laneDensityDamping
                    )
                )
            }
        }

        return lights
    }

    private func drawPathPulseEnvironment(in context: inout GraphicsContext, lights: [PulseLight]) {
        for light in lights {
            drawPulseFloorSpill(in: &context, center: light.center, intensity: light.intensity, color: light.color)
        }
    }

    private func pulseInfluence(
        for athleteID: UUID,
        at center: CGPoint,
        markerRadius: CGFloat,
        lights: [PulseLight]
    ) -> PulseMarkerInfluence? {
        guard !lights.isEmpty else { return nil }

        let reach = max(46, markerRadius + 46 * markerScale)
        let reachSquared = reach * reach
        var bestStrength: CGFloat = 0
        var bestDirection = CGPoint.zero
        var bestColor = Color.white

        for light in lights where light.athleteID != athleteID {
            let dx = center.x - light.center.x
            let dy = center.y - light.center.y
            let distanceSquared = dx * dx + dy * dy
            guard distanceSquared > 0.25, distanceSquared < reachSquared else { continue }

            let distance = distanceSquared.squareRoot()
            let falloff = 1 - (distance / reach)
            let strength = light.intensity * falloff * falloff
            if strength > bestStrength {
                bestStrength = strength
                bestDirection = CGPoint(x: dx / distance, y: dy / distance)
                bestColor = light.color
            }
        }

        guard bestStrength > 0.025 else { return nil }
        return PulseMarkerInfluence(
            shadowDirection: bestDirection,
            color: bestColor,
            strength: min(bestStrength, 1)
        )
    }

    private func drawPulseFloorSpill(in context: inout GraphicsContext, center: CGPoint, intensity: CGFloat, color: Color) {
        let clampedIntensity = min(max(intensity, 0), 1)
        guard clampedIntensity > 0.02 else { return }

        let spillRadius = max(72, 90 * markerScale)
        var spill = Path()
        spill.addEllipse(
            in: CGRect(
                x: center.x - spillRadius,
                y: center.y - spillRadius,
                width: spillRadius * 2,
                height: spillRadius * 2
            )
        )
        context.fill(
            spill,
            with: .radialGradient(
                Gradient(colors: [
                    color.opacity(0.028 * clampedIntensity),
                    color.opacity(0.014 * clampedIntensity),
                    Color.white.opacity(0.006 * clampedIntensity),
                    .clear
                ]),
                center: center,
                startRadius: 0,
                endRadius: spillRadius
            )
        )

        drawPulseSeamGlint(in: &context, center: center, intensity: clampedIntensity, color: color)
    }

    private func drawPulseSeamGlint(in context: inout GraphicsContext, center: CGPoint, intensity: CGFloat, color: Color) {
        let width = CourtConstants.width * cellSize
        let height = CourtConstants.height * cellSize
        let seamSpacing = 8 * cellSize
        guard seamSpacing > 1 else { return }

        let reach = max(22, 26 * markerScale)
        let halfLength = max(34, 44 * markerScale)
        let lineWidth = max(0.55, 0.7 * markerScale)

        let nearestVertical = (center.x / seamSpacing).rounded() * seamSpacing
        if nearestVertical > 0, nearestVertical < width {
            let distance = abs(center.x - nearestVertical)
            if distance < reach {
                let falloff = 1 - (distance / reach)
                var seam = Path()
                seam.move(to: CGPoint(x: nearestVertical, y: max(0, center.y - halfLength)))
                seam.addLine(to: CGPoint(x: nearestVertical, y: min(height, center.y + halfLength)))
                context.stroke(
                    seam,
                    with: .color(color.opacity(0.045 * falloff * intensity)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            }
        }

        let nearestHorizontal = (center.y / seamSpacing).rounded() * seamSpacing
        if nearestHorizontal > 0, nearestHorizontal < height {
            let distance = abs(center.y - nearestHorizontal)
            if distance < reach {
                let falloff = 1 - (distance / reach)
                var seam = Path()
                seam.move(to: CGPoint(x: max(0, center.x - halfLength), y: nearestHorizontal))
                seam.addLine(to: CGPoint(x: min(width, center.x + halfLength), y: nearestHorizontal))
                context.stroke(
                    seam,
                    with: .color(color.opacity(0.04 * falloff * intensity)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            }
        }
    }

    private func drawPathPulses(in context: inout GraphicsContext, state: PulseRenderState) {
        let samples = 36
        let tailLen: CGFloat = 0.12   // comet trail length, as fraction of path
        let leadLen: CGFloat = 0.05   // sharp leading edge
        let haloWidth = max(5, 6.2 * markerScale)
        let coreWidth = max(1.7, 2.0 * markerScale)
        let flashDecay: Double = 0.22    // arrival-burst fade
        let restingGlow: CGFloat = 0.1   // faint "parked here, waiting" glow

        for lane in state.lanes {
            let localT = state.cycleT - lane.start
            let progress = lane.travel > 0 ? min(max(localT / lane.travel, 0), 1) : (localT >= 0 ? 1 : 0)
            let head = CGFloat(progress)

            // Moving comet only while en route — not before launch, and not after
            // arrival, so it never sits frozen at the end during the group wait.
            if localT >= 0, progress < 1 {
                var prev = pointAtArcLength(0, pts: lane.poly, cum: lane.cum)
                for i in 1...samples {
                    let f1 = CGFloat(i) / CGFloat(samples)
                    let p1 = pointAtArcLength(f1 * lane.total, pts: lane.poly, cum: lane.cum)
                    let fMid = (CGFloat(i) - 0.5) / CGFloat(samples)
                    let d = fMid - head
                    let intensity = d <= 0 ? exp(d / tailLen) : exp(-d / leadLen)
                    if intensity > 0.05 {
                        var seg = Path()
                        seg.move(to: prev)
                        seg.addLine(to: p1)
                        let t = min(max(fMid, 0), 1)
                        let glow = pulseGlowColor(progress: t, state: state)
                        context.stroke(
                            seg,
                            with: .color(glow.opacity(0.38 * intensity)),
                            style: StrokeStyle(lineWidth: haloWidth, lineCap: .round)
                        )
                        context.stroke(
                            seg,
                            with: .color(.white.opacity(0.72 * intensity)),
                            style: StrokeStyle(lineWidth: coreWidth, lineCap: .round)
                        )
                    }
                    prev = p1
                }
            }

            // Arrival flash, then a faint resting glow held until the group
            // relaunches — so you can see who's already parked and waiting.
            let sinceArrival = state.cycleT - (lane.start + lane.travel)
            if sinceArrival >= 0 {
                let flash = max(restingGlow, CGFloat(exp(-sinceArrival / flashDecay)))
                drawArrivalFlash(in: &context, at: lane.item.endPosition, intensity: flash, color: state.endGlow)
            }
        }
    }

    /// A short radial burst at the destination so the light reads as passing
    /// "through the wall" rather than stopping dead at the path end.
    private func drawArrivalFlash(in context: inout GraphicsContext, at gridPosition: CGPoint, intensity: CGFloat, color: Color) {
        let center = CGPoint(x: gridPosition.x * cellSize, y: gridPosition.y * cellSize)
        let glowR = (10 + 10 * intensity) * markerScale
        var glow = Path()
        glow.addEllipse(in: CGRect(x: center.x - glowR, y: center.y - glowR, width: glowR * 2, height: glowR * 2))
        context.fill(
            glow,
            with: .radialGradient(
                Gradient(colors: [color.opacity(0.42 * intensity), color.opacity(0.12 * intensity), .clear]),
                center: center,
                startRadius: 0,
                endRadius: glowR
            )
        )
        let coreR = (2.5 + 2 * intensity) * markerScale
        var core = Path()
        core.addEllipse(in: CGRect(x: center.x - coreR, y: center.y - coreR, width: coreR * 2, height: coreR * 2))
        context.fill(core, with: .color(.white.opacity(0.64 * intensity)))
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
        context.stroke(fine, with: .color(.black.opacity(0.07)), lineWidth: 0.8)
        context.stroke(fine, with: .color(floorLiftColor.opacity(0.07)), lineWidth: 0.45)

        // Vertical panel dividers
        var verticalPanels = Path()
        for col in stride(from: 8, through: Int(CourtConstants.width) - 1, by: 8) {
            let x = CGFloat(col) * cellSize
            verticalPanels.move(to: CGPoint(x: x, y: 0))
            verticalPanels.addLine(to: CGPoint(x: x, y: height))
        }
        var verticalPanelShadows = verticalPanels
        verticalPanelShadows = verticalPanelShadows.offsetBy(dx: 0.55 * markerScale, dy: 0.85 * markerScale)
        context.stroke(verticalPanelShadows, with: .color(.black.opacity(0.22)), lineWidth: max(1.0, 1.25 * markerScale))
        context.stroke(verticalPanels, with: .color(floorLiftColor.opacity(0.18)), lineWidth: max(0.8, 0.95 * markerScale))
        var verticalPanelHighlights = verticalPanels
        verticalPanelHighlights = verticalPanelHighlights.offsetBy(dx: -0.25 * markerScale, dy: -0.35 * markerScale)
        context.stroke(verticalPanelHighlights, with: .color(.white.opacity(0.08)), lineWidth: max(0.45, 0.55 * markerScale))

        // Horizontal panel lines (low opacity — like floor seams)
        var horizontalPanels = Path()
        for row in stride(from: 8, through: Int(CourtConstants.height) - 1, by: 8) {
            let y = CGFloat(row) * cellSize
            horizontalPanels.move(to: CGPoint(x: 0, y: y))
            horizontalPanels.addLine(to: CGPoint(x: width, y: y))
        }
        var horizontalPanelShadows = horizontalPanels
        horizontalPanelShadows = horizontalPanelShadows.offsetBy(dx: 0.45 * markerScale, dy: 0.75 * markerScale)
        context.stroke(horizontalPanelShadows, with: .color(.black.opacity(0.18)), lineWidth: max(1.0, 1.2 * markerScale))
        context.stroke(horizontalPanels, with: .color(floorLiftColor.opacity(0.14)), lineWidth: max(0.75, 0.9 * markerScale))
        var horizontalPanelHighlights = horizontalPanels
        horizontalPanelHighlights = horizontalPanelHighlights.offsetBy(dx: -0.2 * markerScale, dy: -0.3 * markerScale)
        context.stroke(horizontalPanelHighlights, with: .color(.white.opacity(0.065)), lineWidth: max(0.45, 0.5 * markerScale))

        // Center-floor mark — faint FormationFlow "FF" logo, centered on the floor.
        if showCenterMark { drawCenterMark(in: &context) }

        // Border
        var border = Path()
        border.addRect(CGRect(x: 0, y: 0, width: width, height: height))
        context.stroke(border, with: .color(.white.opacity(0.25)), lineWidth: 2)

        drawCourtVignette(in: &context, width: width, height: height)
    }

    /// Faint FormationFlow "FF" logo marking the center of the floor. The mark is
    /// the brand logo: two F's spelled out in athlete dots (coral filled + cream
    /// outlined) on the same grid the court uses (see ff_logo_anim.py).
    private func drawCenterMark(in context: inout GraphicsContext) {
        let coral = Color(red: 255 / 255, green: 75 / 255, blue: 92 / 255)
        let cream = Color(red: 232 / 255, green: 222 / 255, blue: 198 / 255)

        // Logo dot layout in (col, row) units; the mark spans cols 0...8, rows 0...4.
        let coralDots: [(CGFloat, CGFloat)] = [
            (0, 0), (1, 0), (2, 0), (3, 0),   // top bar
            (0, 1),                            // left stem
            (0, 2), (1, 2), (2, 2),            // mid bar
            (0, 3),
            (0, 4),
        ]
        let creamDots: [(CGFloat, CGFloat)] = [
            (5, 0), (6, 0), (7, 0), (8, 0),
            (5, 1),
            (5, 2), (6, 2), (7, 2),
            (5, 3),
            (5, 4),
        ]

        let pitch: CGFloat = 3.0 * cellSize          // feet between dots → ~24ft-wide mark
        let coralR = 0.233 * pitch                   // radii from the logo's px ratios
        let creamR = 0.275 * pitch
        // Centre the logo bounding box (cols 0...8, rows 0...4) on the floor centre.
        let originX = (CourtConstants.width / 2) * cellSize - 4 * pitch
        let originY = (CourtConstants.height / 2) * cellSize - 2 * pitch

        func dotRect(_ col: CGFloat, _ row: CGFloat, _ r: CGFloat) -> CGRect {
            let c = CGPoint(x: originX + col * pitch, y: originY + row * pitch)
            return CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        }

        for (col, row) in coralDots {
            context.fill(Path(ellipseIn: dotRect(col, row, coralR)), with: .color(coral.opacity(0.16)))
        }
        for (col, row) in creamDots {
            context.stroke(
                Path(ellipseIn: dotRect(col, row, creamR)),
                with: .color(cream.opacity(0.20)),
                lineWidth: max(1.0, 1.6 * markerScale)
            )
        }
    }

    private var floorLiftColor: Color {
        let baseColor = hasTransition
            ? blendedFormationColor(progress: transitionProgress)
            : formationColor
        let (r, g, b) = rgbComponents(baseColor)
        return Color(
            red: min(1, r * 0.7 + 0.18),
            green: min(1, g * 0.7 + 0.22),
            blue: min(1, b * 0.7 + 0.28)
        )
    }

    private func drawCourtVignette(in context: inout GraphicsContext, width: CGFloat, height: CGFloat) {
        let edge = min(width, height) * 0.12
        guard edge > 1 else { return }

        var top = Path()
        top.addRect(CGRect(x: 0, y: 0, width: width, height: edge))
        context.fill(
            top,
            with: .linearGradient(
                Gradient(colors: [.black.opacity(0.22), .clear]),
                startPoint: CGPoint(x: width / 2, y: 0),
                endPoint: CGPoint(x: width / 2, y: edge)
            )
        )

        var bottom = Path()
        bottom.addRect(CGRect(x: 0, y: height - edge, width: width, height: edge))
        context.fill(
            bottom,
            with: .linearGradient(
                Gradient(colors: [.clear, .black.opacity(0.2)]),
                startPoint: CGPoint(x: width / 2, y: height - edge),
                endPoint: CGPoint(x: width / 2, y: height)
            )
        )

        var left = Path()
        left.addRect(CGRect(x: 0, y: 0, width: edge, height: height))
        context.fill(
            left,
            with: .linearGradient(
                Gradient(colors: [.black.opacity(0.16), .clear]),
                startPoint: CGPoint(x: 0, y: height / 2),
                endPoint: CGPoint(x: edge, y: height / 2)
            )
        )

        var right = Path()
        right.addRect(CGRect(x: width - edge, y: 0, width: edge, height: height))
        context.fill(
            right,
            with: .linearGradient(
                Gradient(colors: [.clear, .black.opacity(0.16)]),
                startPoint: CGPoint(x: width - edge, y: height / 2),
                endPoint: CGPoint(x: width, y: height / 2)
            )
        )
    }

    private func drawGhostAthletes(in context: inout GraphicsContext) {
        guard !ghostAthletes.isEmpty else { return }
        let ghostStyle = StrokeStyle(lineWidth: 1 * markerScale, dash: [3, 3])
        for athlete in ghostAthletes {
            let point = CGPoint(x: athlete.position.x * cellSize, y: athlete.position.y * cellSize)
            // Previous = clearly larger than current (formations grow as they recede into the past)
            let innerRadius = (athlete.role.markerRadius + 8) * markerScale
            let outerRadius = (athlete.role.markerRadius + 15) * markerScale

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
            // Next = clearly smaller than current (hasn't happened yet, grows when it becomes current)
            let radius = max(5, athlete.role.markerRadius - 7) * markerScale

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
            context.stroke(path, with: .color(ghostColor.opacity(0.12)), style: style)
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
            context.stroke(path, with: .color(ghostNextColor.opacity(0.12)), style: style)
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
                    var segment = Path()
                    segment.move(to: p0)
                    if segmentUsesSmoothWaypoint(segmentIndex: segmentIndex, waypoints: item.waypoints) {
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

            drawDirectionChevrons(
                in: &context,
                along: pathPolyline(for: item),
                color: .white,
                opacity: 0.3,
                spacing: max(7, 8 * markerScale),
                size: max(4, 5 * markerScale),
                lineWidth: max(1.1, 1.3 * markerScale)
            )
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

    private func drawAthletes(in context: inout GraphicsContext, pulseLights: [PulseLight]) {
        for athlete in athletes {
            let point = CGPoint(x: athlete.position.x * cellSize, y: athlete.position.y * cellSize)
            let isSelected = selectedAthleteIDs.contains(athlete.id)
            let isColliding = collisionIDs.contains(athlete.id)
            let isHovered = athlete.id == hoveredAthleteID
            let isDragging = draggingAthleteIDs.contains(athlete.id)
            let interactionScale: CGFloat = isDragging ? 1.08 : (isHovered ? 1.04 : 1.0)

            // Path-focus mode: everything that isn't the selected athlete recedes
            // to a faint, frozen-looking ghost (still tappable to switch focus).
            var context = context
            if dimUnselectedAthletes && !isSelected {
                context.opacity = 0.11
            }

            if hasTransition {
                // Transition mode: athletes colored by formation, blending start→end
                let baseRadius = (isSelected ? athlete.role.markerRadius - 1 : athlete.role.markerRadius - 2) * markerScale
                let radius = baseRadius * interactionScale
                let formationColor = blendedFormationColor(progress: transitionProgress)
                let fillColor: Color = isColliding ? .red : formationColor
                let markerPulseInfluence = pulseInfluence(
                    for: athlete.id,
                    at: point,
                    markerRadius: radius,
                    lights: pulseLights
                )
                drawPremiumAthleteMarker(
                    in: &context,
                    athlete: athlete,
                    center: point,
                    radius: radius,
                    fillColor: fillColor,
                    isSelected: isSelected,
                    isHovered: isHovered,
                    isDragging: isDragging,
                    isColliding: isColliding,
                    isSwapSource: false,
                    pulseInfluence: markerPulseInfluence
                )

                let label = Text(athlete.label)
                    .font(.system(.caption2, design: .monospaced).weight(isSelected || isHovered || isDragging ? .bold : .semibold))
                    .foregroundColor(.white.opacity(isSelected || isHovered || isDragging ? 0.98 : 0.9))
                context.draw(label, at: point, anchor: .center)
            } else {
                // Formation-only mode: colored by formation, role conveyed by shape
                let baseColor: Color = useRoleColors ? athlete.role.color : formationColor
                let fillColor: Color = isColliding ? .red : baseColor
                let baseRadius = (isSelected ? athlete.role.selectedMarkerRadius : athlete.role.markerRadius) * markerScale
                let radius = baseRadius * interactionScale
                let isSwapSource = athlete.id == swapSourceID
                let markerPulseInfluence = pulseInfluence(
                    for: athlete.id,
                    at: point,
                    markerRadius: radius,
                    lights: pulseLights
                )

                drawPremiumAthleteMarker(
                    in: &context,
                    athlete: athlete,
                    center: point,
                    radius: radius,
                    fillColor: fillColor,
                    isSelected: isSelected,
                    isHovered: isHovered,
                    isDragging: isDragging,
                    isColliding: isColliding,
                    isSwapSource: isSwapSource,
                    pulseInfluence: markerPulseInfluence
                )

                if isColliding {
                    let ring = athlete.role.markerPath(center: point, radius: radius + 4 * markerScale)
                    context.stroke(ring, with: .color(.red.opacity(0.95)), lineWidth: 2 * markerScale)
                }

                if isSwapSource {
                    let ring = athlete.role.markerPath(center: point, radius: radius + 6 * markerScale)
                    context.stroke(
                        ring,
                        with: .color(formationColor),
                        style: StrokeStyle(lineWidth: max(2.5, 3 * markerScale), dash: [6, 3])
                    )
                }

                let labelColor = contrastingLabelColor(for: fillColor)
                let label = Text(athlete.label)
                    .font(.system(.caption, design: .monospaced).weight(isSelected || isHovered || isDragging ? .bold : .semibold))
                    .foregroundColor(labelColor.opacity(isSelected || isHovered || isDragging ? 0.98 : 0.9))
                context.draw(label, at: point, anchor: .center)
            }
        }
    }

    private func drawPremiumAthleteMarker(
        in context: inout GraphicsContext,
        athlete: RenderedAthlete,
        center: CGPoint,
        radius: CGFloat,
        fillColor: Color,
        isSelected: Bool,
        isHovered: Bool,
        isDragging: Bool,
        isColliding: Bool,
        isSwapSource: Bool,
        pulseInfluence: PulseMarkerInfluence?
    ) {
        let marker = athlete.role.markerPath(center: center, radius: radius)
        let lift = isDragging || isHovered

        if let pulseInfluence {
            let strength = pulseInfluence.strength
            let castDistance = (3.2 + 7.0 * strength) * markerScale
            let castCenter = CGPoint(
                x: center.x + pulseInfluence.shadowDirection.x * castDistance,
                y: center.y + pulseInfluence.shadowDirection.y * castDistance
            )
            let castRadius = radius + (2.0 + 4.5 * strength) * markerScale
            let castShadow = athlete.role.markerPath(center: castCenter, radius: castRadius)
            context.fill(castShadow, with: .color(.black.opacity(0.13 * strength)))
        }

        let shadowOffset = CGPoint(
            x: center.x + (lift ? 2.2 : 1.4) * markerScale,
            y: center.y + (lift ? 4.0 : 2.8) * markerScale
        )
        let shadowRadius = radius + (lift ? 3.5 : 2.4) * markerScale
        let shadow = athlete.role.markerPath(center: shadowOffset, radius: shadowRadius)
        context.fill(shadow, with: .color(.black.opacity(isDragging ? 0.38 : 0.26)))

        if isSelected || isDragging || isColliding || isSwapSource {
            let glowRadius = radius + (isDragging ? 7 : 5) * markerScale
            let glow = athlete.role.markerPath(center: center, radius: glowRadius)
            let glowColor: Color = isColliding ? .red : .white
            context.fill(glow, with: .color(glowColor.opacity(isColliding ? 0.14 : 0.08)))
        }

        let rimRadius = radius + max(1.6, 2.0 * markerScale)
        let rim = athlete.role.markerPath(center: center, radius: rimRadius)
        context.fill(rim, with: .color(.black.opacity(isColliding ? 0.45 : 0.38)))
        context.stroke(rim, with: .color(.white.opacity(isSelected || isDragging ? 0.82 : 0.34)), lineWidth: max(1.1, 1.3 * markerScale))

        let bodyOpacity: CGFloat = isColliding ? 0.98 : (isSelected || isHovered || isDragging ? 0.97 : 0.93)
        context.fill(marker, with: .color(fillColor.opacity(bodyOpacity)))

        let topLight = athlete.role.markerPath(
            center: CGPoint(x: center.x - radius * 0.16, y: center.y - radius * 0.2),
            radius: radius * 0.72
        )
        context.fill(topLight, with: .color(.white.opacity(isColliding ? 0.12 : 0.16)))

        if let pulseInfluence {
            let strength = pulseInfluence.strength
            let litCenter = CGPoint(
                x: center.x - pulseInfluence.shadowDirection.x * radius * 0.22,
                y: center.y - pulseInfluence.shadowDirection.y * radius * 0.22
            )
            let catchlight = athlete.role.markerPath(center: litCenter, radius: radius * 0.62)
            context.fill(catchlight, with: .color(pulseInfluence.color.opacity(0.11 * strength)))

            let rimLift = athlete.role.markerPath(
                center: litCenter,
                radius: radius + max(1.2, 1.5 * markerScale)
            )
            context.stroke(
                rimLift,
                with: .color(.white.opacity(0.14 * strength)),
                lineWidth: max(0.7, 0.9 * markerScale)
            )
        }

        let lowerShade = athlete.role.markerPath(
            center: CGPoint(x: center.x + radius * 0.12, y: center.y + radius * 0.16),
            radius: radius * 0.96
        )
        context.stroke(lowerShade, with: .color(.black.opacity(0.16)), lineWidth: max(1.2, 1.6 * markerScale))

        let outlineColor: Color = isColliding ? .red : (isDragging || isSelected ? .white : .black)
        let outlineOpacity: CGFloat = isColliding ? 1.0 : (isDragging || isSelected ? 0.95 : 0.28)
        context.stroke(
            marker,
            with: .color(outlineColor.opacity(outlineOpacity)),
            lineWidth: isSelected || isDragging ? max(2.5, 3.0 * markerScale) : max(1.4, 1.8 * markerScale)
        )
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

#if canImport(UIKit)
// MARK: - Two-Finger Playback Gesture (UIKit bridge)

/// Installs a two-finger tap (play/pause) and an optional two-finger pan
/// (scrub) recognizer. The recognizers are attached to the **window** — the only
/// guaranteed ancestor of every touch — and scoped to the canvas by checking the
/// touch lands inside this representable's own frame (`.background` lays it out to
/// match the canvas). Attaching to the representable's immediate host doesn't work:
/// `.background` is a *sibling* of the canvas, so its subtree never sees canvas
/// touches and the recognizers stay dead.
///
/// `cancelsTouchesInView = false` + simultaneous recognition means single-finger
/// SwiftUI gestures (athlete drag, selection, path sketch) and two-finger
/// pinch/rotate keep working untouched. SwiftUI has no count-based tap/drag
/// gesture, so this UIKit bridge is the only way to read a two-finger gesture.
struct TwoFingerPlaybackGesture: UIViewRepresentable {
    /// When false, the scrub (pan) recognizer is disabled — tap-to-toggle only.
    var scrubEnabled: Bool
    /// Two-finger tap: toggle play/pause.
    var onPlayToggle: () -> Void
    /// Read the player's current progress (0...1) at the moment a scrub begins.
    var currentProgress: () -> CGFloat = { 0 }
    /// Called once when a two-finger scrub begins (e.g. pause playback).
    var onScrubBegan: () -> Void = {}
    /// Seek to an absolute progress (0...1) during a scrub.
    var onSeek: (CGFloat) -> Void = { _ in }

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false // frame anchor only; recognizers live on the window
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: AnchorView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.pan?.isEnabled = scrubEnabled
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// Reports window membership changes so the coordinator can (un)install
    /// window-level recognizers — avoids leaking recognizers across view reuse.
    final class AnchorView: UIView {
        weak var coordinator: Coordinator?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.windowChanged(to: window, anchor: self)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: TwoFingerPlaybackGesture
        weak var anchor: UIView?
        weak var installedWindow: UIWindow?
        weak var tap: UITapGestureRecognizer?
        weak var pan: UIPanGestureRecognizer?
        private var scrubAnchor: CGFloat = 0

        init(_ parent: TwoFingerPlaybackGesture) { self.parent = parent }

        func windowChanged(to window: UIWindow?, anchor: UIView) {
            self.anchor = anchor
            if let old = installedWindow {
                if let t = tap { old.removeGestureRecognizer(t) }
                if let p = pan { old.removeGestureRecognizer(p) }
                tap = nil; pan = nil; installedWindow = nil
            }
            guard let window else { return }

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            tap.numberOfTouchesRequired = 2
            tap.delegate = self
            tap.cancelsTouchesInView = false
            window.addGestureRecognizer(tap)
            self.tap = tap

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
            pan.minimumNumberOfTouches = 2
            pan.maximumNumberOfTouches = 2
            pan.delegate = self
            pan.cancelsTouchesInView = false
            pan.isEnabled = parent.scrubEnabled
            window.addGestureRecognizer(pan)
            self.pan = pan

            installedWindow = window
        }

        /// True when a touch falls within the canvas region (this anchor's frame).
        private func anchorContains(_ locationInWindow: CGPoint, _ window: UIWindow) -> Bool {
            guard let anchor, anchor.window === window else { return false }
            return anchor.convert(anchor.bounds, to: window).contains(locationInWindow)
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            parent.onPlayToggle()
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let window = installedWindow, let anchor, anchor.bounds.width > 0 else { return }
            let fraction = recognizer.translation(in: window).x / anchor.bounds.width
            switch recognizer.state {
            case .began:
                parent.onScrubBegan()
                scrubAnchor = parent.currentProgress()
            case .changed:
                parent.onSeek(min(1, max(0, scrubAnchor + fraction)))
            default:
                break
            }
        }

        // Scope the window-level recognizers to the canvas frame.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldReceive touch: UITouch) -> Bool {
            guard let window = installedWindow else { return false }
            return anchorContains(touch.location(in: window), window)
        }

        // Run alongside SwiftUI's own gestures rather than blocking them.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
#endif
