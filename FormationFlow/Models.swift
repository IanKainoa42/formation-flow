import Foundation
import SwiftUI

#if os(iOS)
    import UIKit
#else
    import AppKit
#endif

// MARK: - Constants

enum CourtConstants {
    static let width: CGFloat = 72  // 72ft wide — 9 panels × 8 units
    static let height: CGFloat = 56  // 56ft tall — 7 panels × 8 units
    static let cellSize: CGFloat = 12  // pixels per foot
    static let collisionDistance: CGFloat = 2.0  // feet
    static let hitRadiusSquared: CGFloat = 9.0  // 3-foot tap radius, squared
}

// MARK: - Athlete Role

enum AthleteRole: String, Codable, CaseIterable {
    case base
    case flyer
    case spotter
    case backspot
    case tumbler

    var color: Color {
        switch self {
        case .base: return .blue
        case .flyer: return .yellow
        case .spotter: return .green
        case .backspot: return .purple
        case .tumbler: return .orange
        }
    }
}

// MARK: - Path Waypoint

struct PathWaypoint: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var position: CGPoint  // waypoint position in floor feet
    var isSmooth: Bool  // true = bezier curve through point, false = sharp cut
    var holdDuration: CGFloat = 0.0  // seconds to pause at this waypoint

    init(id: UUID = UUID(), position: CGPoint, isSmooth: Bool = true, holdDuration: CGFloat = 0.0) {
        self.id = id
        self.position = position
        self.isSmooth = isSmooth
        self.holdDuration = holdDuration
    }

    enum CodingKeys: String, CodingKey {
        case id, isSmooth, holdDuration
        case positionX, positionY
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(isSmooth, forKey: .isSmooth)
        try container.encode(holdDuration, forKey: .holdDuration)
        try container.encode(position.x, forKey: .positionX)
        try container.encode(position.y, forKey: .positionY)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        isSmooth = (try? container.decode(Bool.self, forKey: .isSmooth)) ?? true
        holdDuration = (try? container.decode(CGFloat.self, forKey: .holdDuration)) ?? 0.0
        let x = try container.decode(CGFloat.self, forKey: .positionX)
        let y = try container.decode(CGFloat.self, forKey: .positionY)
        position = CGPoint(x: x, y: y)
    }
}

// MARK: - Data Models

struct Athlete: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var label: String  // "A1", "B2", etc.
    var position: CGPoint  // x, y on floor (in feet)
    var role: AthleteRole = .base
    var moveTiming: CGFloat = 0.0  // seconds delay before this athlete starts moving
    var pathControlPoint: CGPoint?  // Legacy single bezier control point (kept for backward compat)
    var pathWaypoints: [PathWaypoint] = []  // Ordered intermediate waypoints for multi-segment paths

    static func == (lhs: Athlete, rhs: Athlete) -> Bool {
        lhs.id == rhs.id && lhs.label == rhs.label && lhs.position.x == rhs.position.x
            && lhs.position.y == rhs.position.y && lhs.role == rhs.role
            && lhs.moveTiming == rhs.moveTiming && lhs.pathControlPoint == rhs.pathControlPoint
            && lhs.pathWaypoints == rhs.pathWaypoints
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(label)
        hasher.combine(position.x)
        hasher.combine(position.y)
        hasher.combine(role)
        hasher.combine(moveTiming)
        hasher.combine(pathControlPoint?.x)
        hasher.combine(pathControlPoint?.y)
        hasher.combine(pathWaypoints)
    }

    enum CodingKeys: String, CodingKey {
        case id, label, role, moveTiming, pathWaypoints
        case positionX = "positionX"
        case positionY = "positionY"
        case pathControlX = "pathControlX"
        case pathControlY = "pathControlY"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(role, forKey: .role)
        try container.encode(moveTiming, forKey: .moveTiming)
        try container.encode(position.x, forKey: .positionX)
        try container.encode(position.y, forKey: .positionY)
        if let control = pathControlPoint {
            try container.encode(control.x, forKey: .pathControlX)
            try container.encode(control.y, forKey: .pathControlY)
        }
        if !pathWaypoints.isEmpty {
            try container.encode(pathWaypoints, forKey: .pathWaypoints)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        // Backwards-compatible: decode role as AthleteRole, fallback to .base for old String values
        if let decodedRole = try? container.decode(AthleteRole.self, forKey: .role) {
            role = decodedRole
        } else {
            let roleString = try container.decode(String.self, forKey: .role)
            role = AthleteRole(rawValue: roleString) ?? .base
        }
        moveTiming = (try? container.decode(CGFloat.self, forKey: .moveTiming)) ?? 0.0
        let x = try container.decode(CGFloat.self, forKey: .positionX)
        let y = try container.decode(CGFloat.self, forKey: .positionY)
        position = CGPoint(x: x, y: y)

        if let cx = try? container.decode(CGFloat.self, forKey: .pathControlX),
            let cy = try? container.decode(CGFloat.self, forKey: .pathControlY)
        {
            pathControlPoint = CGPoint(x: cx, y: cy)
        }

        // Decode waypoints, or migrate legacy pathControlPoint to a single waypoint
        if let waypoints = try? container.decode([PathWaypoint].self, forKey: .pathWaypoints) {
            pathWaypoints = waypoints
        } else if let cp = pathControlPoint {
            // Migration: convert legacy single control point to a waypoint
            pathWaypoints = [PathWaypoint(position: cp, isSmooth: true)]
        }
    }

    init(id: UUID = UUID(), label: String, position: CGPoint, role: AthleteRole = .base) {
        self.id = id
        self.label = label
        self.position = position
        self.role = role
    }
}

struct Formation: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String = "Untitled Formation"
    var athletes: [Athlete] = []
    var notes: String = ""
    var gridSizeWidth: CGFloat = CourtConstants.width
    var gridSizeHeight: CGFloat = CourtConstants.height

    var gridSize: CGSize {
        get {
            CGSize(width: gridSizeWidth, height: gridSizeHeight)
        }
        set {
            gridSizeWidth = newValue.width
            gridSizeHeight = newValue.height
        }
    }

    static func == (lhs: Formation, rhs: Formation) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.athletes == rhs.athletes
            && lhs.notes == rhs.notes && lhs.gridSizeWidth == rhs.gridSizeWidth
            && lhs.gridSizeHeight == rhs.gridSizeHeight
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(athletes)
        hasher.combine(notes)
        hasher.combine(gridSizeWidth)
        hasher.combine(gridSizeHeight)
    }

    mutating func addAthlete(_ athlete: Athlete) {
        athletes.append(athlete)
    }

    mutating func removeAthlete(id: UUID) {
        athletes.removeAll { $0.id == id }
    }

    mutating func updateAthlete(_ athlete: Athlete) {
        if let index = athletes.firstIndex(where: { $0.id == athlete.id }) {
            athletes[index] = athlete
        }
    }

    mutating func swapAthletePositions(id1: UUID, id2: UUID) {
        guard let index1 = athletes.firstIndex(where: { $0.id == id1 }),
            let index2 = athletes.firstIndex(where: { $0.id == id2 }),
            index1 != index2
        else { return }
        let tempPosition = athletes[index1].position
        athletes[index1].position = athletes[index2].position
        athletes[index2].position = tempPosition
    }

    /// 10-athlete bowling pin layout centered on the court
    static func bowlingPin(name: String = "Formation") -> Formation {
        var formation = Formation()
        formation.name = name
        // Centered on 72x56 court. 4ft row spacing, 4ft column spacing.
        // Row 0: 1 pin, Row 1: 2 pins, Row 2: 3 pins, Row 3: 4 pins
        let centerX: CGFloat = CourtConstants.width / 2   // 36
        let startY: CGFloat = CourtConstants.height / 2 - 6  // 22
        let rowSpacing: CGFloat = 4
        let colSpacing: CGFloat = 4

        var label = 1
        for row in 0...3 {
            let count = row + 1
            let y = startY + CGFloat(row) * rowSpacing
            let rowWidth = CGFloat(count - 1) * colSpacing
            let startX = centerX - rowWidth / 2
            for col in 0..<count {
                let x = startX + CGFloat(col) * colSpacing
                formation.athletes.append(
                    Athlete(label: "P\(label)", position: CGPoint(x: x, y: y))
                )
                label += 1
            }
        }
        return formation
    }
}

// MARK: - Path Calculation Utilities

struct PathCalculations {
    /// Calculate standard distance between two points in floor feet
    static func distance(from: CGPoint, to: CGPoint) -> CGFloat {
        hypot(to.x - from.x, to.y - from.y)
    }

    /// Calculate mathematically cheaper squared distance between two points in floor feet
    static func squaredDistance(from: CGPoint, to: CGPoint) -> CGFloat {
        let dx = to.x - from.x
        let dy = to.y - from.y
        return dx * dx + dy * dy
    }

    /// Evaluate a quadratic Bezier curve at parameter t (0...1).
    static func quadraticBezierPoint(
        from p0: CGPoint, control c: CGPoint, to p2: CGPoint, t: CGFloat
    ) -> CGPoint {
        let u = 1.0 - t
        let uu = u * u
        let ut2 = 2.0 * u * t
        let tt = t * t
        return CGPoint(
            x: uu * p0.x + ut2 * c.x + tt * p2.x,
            y: uu * p0.y + ut2 * c.y + tt * p2.y
        )
    }

    /// Evaluate a cubic Bezier curve at parameter t (0...1).
    static func cubicBezierPoint(
        p0: CGPoint, c1: CGPoint, c2: CGPoint, p3: CGPoint, t: CGFloat
    ) -> CGPoint {
        let u = 1.0 - t
        let uu = u * u
        let uuu = uu * u
        let tt = t * t
        let ttt = tt * t
        return CGPoint(
            x: uuu * p0.x + 3 * uu * t * c1.x + 3 * u * tt * c2.x + ttt * p3.x,
            y: uuu * p0.y + 3 * uu * t * c1.y + 3 * u * tt * c2.y + ttt * p3.y
        )
    }

    /// Build a complete point-sequence (nodes) for a multi-waypoint path: [start, wp1, wp2, ..., end]
    static func waypointNodes(from start: CGPoint, to end: CGPoint, waypoints: [PathWaypoint])
        -> [CGPoint]
    {
        var nodes = [start]
        nodes.append(contentsOf: waypoints.map { $0.position })
        nodes.append(end)
        return nodes
    }

    /// Calculate segment lengths for a multi-node path. Returns array of distances.
    static func segmentLengths(_ nodes: [CGPoint]) -> [CGFloat] {
        guard nodes.count > 1 else { return [] }
        var lengths: [CGFloat] = []
        for i in 0..<(nodes.count - 1) {
            lengths.append(distance(from: nodes[i], to: nodes[i + 1]))
        }
        return lengths
    }

    /// Sample a multi-waypoint path into discrete points for collision detection.
    /// Smooth waypoints use Catmull-Rom-style cubic bezier; sharp waypoints use straight line segments.
    static func waypointPath(
        from start: CGPoint, to end: CGPoint, waypoints: [PathWaypoint], steps: Int = 20
    ) -> [CGPoint] {
        guard !waypoints.isEmpty else {
            return athletePath(from: start, to: end, steps: steps)
        }

        let nodes = waypointNodes(from: start, to: end, waypoints: waypoints)
        let lengths = segmentLengths(nodes)
        let totalLength = lengths.reduce(0, +)
        guard totalLength > 0 else { return [start, end] }

        // Distribute steps proportionally across segments
        var path: [CGPoint] = [start]
        for segIdx in 0..<(nodes.count - 1) {
            let segSteps = max(2, Int(round(CGFloat(steps) * lengths[segIdx] / totalLength)))
            let p0 = nodes[segIdx]
            let p1 = nodes[segIdx + 1]

            // Check if the endpoint waypoint is smooth (Catmull-Rom) or sharp (straight line).
            // The first node is start (no waypoint), last is end (no waypoint).
            let waypointAtEnd: PathWaypoint? =
                (segIdx + 1 > 0 && segIdx + 1 <= waypoints.count) ? waypoints[segIdx] : nil
            let isSmooth = waypointAtEnd?.isSmooth ?? false

            if isSmooth {
                // Catmull-Rom control points for the segment
                let prev = segIdx > 0 ? nodes[segIdx - 1] : p0
                let next = segIdx + 2 < nodes.count ? nodes[segIdx + 2] : p1
                let c1 = CGPoint(
                    x: p0.x + (p1.x - prev.x) / 6.0,
                    y: p0.y + (p1.y - prev.y) / 6.0
                )
                let c2 = CGPoint(
                    x: p1.x - (next.x - p0.x) / 6.0,
                    y: p1.y - (next.y - p0.y) / 6.0
                )
                for i in 1...segSteps {
                    let t = CGFloat(i) / CGFloat(segSteps)
                    path.append(cubicBezierPoint(p0: p0, c1: c1, c2: c2, p3: p1, t: t))
                }
            } else {
                // Sharp / straight line segment
                for i in 1...segSteps {
                    let t = CGFloat(i) / CGFloat(segSteps)
                    path.append(CGPoint(x: p0.x + (p1.x - p0.x) * t, y: p0.y + (p1.y - p0.y) * t))
                }
            }
        }
        return path
    }

    /// Interpolate position along a multi-waypoint path at a given progress (0...1).
    /// This distributes progress proportionally across segment lengths for natural speed.
    static func interpolateWaypointPath(
        from start: CGPoint, to end: CGPoint, waypoints: [PathWaypoint], progress: CGFloat
    ) -> CGPoint {
        guard !waypoints.isEmpty else {
            return CGPoint(
                x: start.x + (end.x - start.x) * progress,
                y: start.y + (end.y - start.y) * progress
            )
        }

        let nodes = waypointNodes(from: start, to: end, waypoints: waypoints)
        let lengths = segmentLengths(nodes)
        let totalLength = lengths.reduce(0, +)
        guard totalLength > 0 else { return start }

        // Find which segment the progress falls into
        let targetDist = progress * totalLength
        var accumulated: CGFloat = 0
        for segIdx in 0..<lengths.count {
            let segLen = lengths[segIdx]
            if accumulated + segLen >= targetDist || segIdx == lengths.count - 1 {
                let segProgress = segLen > 0 ? (targetDist - accumulated) / segLen : 0
                let clampedT = max(0, min(1, segProgress))

                let p0 = nodes[segIdx]
                let p1 = nodes[segIdx + 1]

                // Check if we should use smooth or sharp interpolation
                let waypointAtEnd: PathWaypoint? =
                    (segIdx < waypoints.count) ? waypoints[segIdx] : nil
                let isSmooth = waypointAtEnd?.isSmooth ?? false

                if isSmooth {
                    let prev = segIdx > 0 ? nodes[segIdx - 1] : p0
                    let next = segIdx + 2 < nodes.count ? nodes[segIdx + 2] : p1
                    let c1 = CGPoint(
                        x: p0.x + (p1.x - prev.x) / 6.0,
                        y: p0.y + (p1.y - prev.y) / 6.0
                    )
                    let c2 = CGPoint(
                        x: p1.x - (next.x - p0.x) / 6.0,
                        y: p1.y - (next.y - p0.y) / 6.0
                    )
                    return cubicBezierPoint(p0: p0, c1: c1, c2: c2, p3: p1, t: clampedT)
                } else {
                    return CGPoint(
                        x: p0.x + (p1.x - p0.x) * clampedT,
                        y: p0.y + (p1.y - p0.y) * clampedT
                    )
                }
            }
            accumulated += segLen
        }
        return end
    }

    /// Returns the path-progress (0→1) at which each waypoint is reached, based on segment lengths.
    /// The returned array has one entry per waypoint, in order.
    static func waypointProgressThresholds(
        from start: CGPoint, to end: CGPoint, waypoints: [PathWaypoint]
    ) -> [CGFloat] {
        let nodes = waypointNodes(from: start, to: end, waypoints: waypoints)
        let lengths = segmentLengths(nodes)
        let totalLength = lengths.reduce(0, +)
        guard totalLength > 0 else { return waypoints.map { _ in 0 } }

        var thresholds: [CGFloat] = []
        var accumulated: CGFloat = 0
        // Each waypoint sits at the end of segment [i], i.e. between nodes[i] and nodes[i+1].
        for i in 0..<waypoints.count {
            accumulated += lengths[i]
            thresholds.append(accumulated / totalLength)
        }
        return thresholds
    }

    /// Map wall-clock progress (0→1) to path-progress (0→1) accounting for waypoint hold durations.
    /// `totalHoldTime` is in seconds; `moveDuration` is the moving-only portion in seconds.
    /// Returns the effective path progress (position along the spatial path).
    static func holdAdjustedPathProgress(
        wallProgress: CGFloat, waypoints: [PathWaypoint],
        thresholds: [CGFloat], moveDuration: CGFloat, totalHoldTime: CGFloat
    ) -> CGFloat {
        guard !waypoints.isEmpty, totalHoldTime > 0, moveDuration > 0 else {
            return wallProgress
        }
        let effectiveDuration = moveDuration + totalHoldTime
        let elapsed = wallProgress * effectiveDuration  // seconds into this athlete's motion

        // Walk through the timeline: alternating move-segments and holds
        var timeUsed: CGFloat = 0
        var prevThreshold: CGFloat = 0

        for i in 0..<waypoints.count {
            let threshold = thresholds[i]
            let segmentPathFraction = threshold - prevThreshold
            let segmentMoveTime = segmentPathFraction * moveDuration

            // Moving phase for this segment
            if elapsed <= timeUsed + segmentMoveTime {
                let segElapsed = elapsed - timeUsed
                let segProgress = segmentMoveTime > 0 ? segElapsed / segmentMoveTime : 1
                return prevThreshold + segmentPathFraction * segProgress
            }
            timeUsed += segmentMoveTime

            // Hold phase at this waypoint
            let hold = waypoints[i].holdDuration
            if hold > 0 && elapsed <= timeUsed + hold {
                return threshold  // clamped at waypoint position
            }
            timeUsed += hold
            prevThreshold = threshold
        }

        // Final segment: from last waypoint to end
        let lastSegFraction = 1.0 - prevThreshold
        let lastSegMoveTime = lastSegFraction * moveDuration
        if elapsed <= timeUsed + lastSegMoveTime {
            let segElapsed = elapsed - timeUsed
            let segProgress = lastSegMoveTime > 0 ? segElapsed / lastSegMoveTime : 1
            return prevThreshold + lastSegFraction * segProgress
        }

        return 1.0
    }

    /// Calculate the total travel distance (in feet) for an athlete's transition path.
    static func travelDistance(
        from start: CGPoint, to end: CGPoint, athlete: Athlete
    ) -> CGFloat {
        if !athlete.pathWaypoints.isEmpty {
            let nodes = waypointNodes(from: start, to: end, waypoints: athlete.pathWaypoints)
            return segmentLengths(nodes).reduce(0, +)
        } else if let c = athlete.pathControlPoint {
            // Approximate quadratic Bezier length by sampling
            let steps = 20
            var length: CGFloat = 0
            var prev = start
            for i in 1...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let pt = quadraticBezierPoint(from: start, control: c, to: end, t: t)
                length += distance(from: prev, to: pt)
                prev = pt
            }
            return length
        } else {
            return distance(from: start, to: end)
        }
    }

    /// Find the nearest athlete to a given position
    static func nearestAthlete(to position: CGPoint, in formation: Formation) -> Athlete? {
        guard !formation.athletes.isEmpty else { return nil }
        return formation.athletes.min { a, b in
            squaredDistance(from: position, to: a.position)
                < squaredDistance(from: position, to: b.position)
        }
    }

    /// Calculate the bounding box of all athletes in formation (returns in floor feet)
    static func formationBounds(of formation: Formation) -> CGRect {
        guard !formation.athletes.isEmpty else {
            return CGRect(
                origin: .zero,
                size: CGSize(width: CourtConstants.width, height: CourtConstants.height))
        }

        let xs = formation.athletes.map { $0.position.x }
        let ys = formation.athletes.map { $0.position.y }

        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 52
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 30

        return CGRect(
            origin: CGPoint(x: minX, y: minY),
            size: CGSize(width: maxX - minX, height: maxY - minY)
        )
    }

    /// Calculate the path (as array of points) an athlete takes from start to end position
    static func athletePath(from: CGPoint, to: CGPoint, control: CGPoint? = nil, steps: Int = 10)
        -> [CGPoint]
    {
        guard steps > 1 else { return [from, to] }

        var path: [CGPoint] = [from]
        for i in 1..<steps {
            let t = CGFloat(i) / CGFloat(steps - 1)
            let point: CGPoint
            if let c = control {
                point = quadraticBezierPoint(from: from, control: c, to: to, t: t)
            } else {
                point = CGPoint(
                    x: from.x + (to.x - from.x) * t,
                    y: from.y + (to.y - from.y) * t
                )
            }
            path.append(point)
        }
        path.append(to)
        return path
    }

    /// Check if two athletes collide based on minimum separation distance
    /// Returns true if distance between athletes is less than minDistance (in floor feet)
    static func checkCollision(athleteA: Athlete, athleteB: Athlete, minDistance: CGFloat = 2.0)
        -> Bool
    {
        let distSq = squaredDistance(from: athleteA.position, to: athleteB.position)
        return distSq < (minDistance * minDistance)
    }

    /// Find all collision pairs in a formation
    static func findCollisions(in formation: Formation, minDistance: CGFloat = 2.0) -> [(
        Athlete, Athlete
    )] {
        var collisions: [(Athlete, Athlete)] = []
        for i in 0..<formation.athletes.count {
            for j in (i + 1)..<formation.athletes.count {
                if checkCollision(
                    athleteA: formation.athletes[i], athleteB: formation.athletes[j],
                    minDistance: minDistance)
                {
                    collisions.append((formation.athletes[i], formation.athletes[j]))
                }
            }
        }
        return collisions
    }

    /// Return collision count and participant ids without allocating all collision pairs.
    static func collisionSummary(in formation: Formation, minDistance: CGFloat = 2.0) -> (
        count: Int, ids: Set<UUID>
    ) {
        let athletes = formation.athletes
        guard athletes.count > 1 else { return (0, Set<UUID>()) }

        let minDistanceSq = minDistance * minDistance
        var collisionCount = 0
        var collisionIds = Set<UUID>()
        collisionIds.reserveCapacity(athletes.count)

        for i in 0..<athletes.count {
            for j in (i + 1)..<athletes.count {
                if squaredDistance(from: athletes[i].position, to: athletes[j].position)
                    < minDistanceSq
                {
                    collisionCount += 1
                    collisionIds.insert(athletes[i].id)
                    collisionIds.insert(athletes[j].id)
                }
            }
        }

        return (collisionCount, collisionIds)
    }

    /// Find the indices of athletes whose transition paths cross within minDistance.
    /// Athletes are matched by ID between start and end formations.
    static func findPathCollisionIndices(
        start: Formation, end: Formation, steps: Int = 20, minDistance: CGFloat = 2.0
    ) -> Set<Int> {
        // Build matched pairs: (startIndex, startAthlete, endAthlete)
        var matchedPairs: [(index: Int, start: Athlete, end: Athlete)] = []
        for (i, startAthlete) in start.athletes.enumerated() {
            if let endAthlete = end.athletes.first(where: { $0.id == startAthlete.id }) {
                matchedPairs.append((index: i, start: startAthlete, end: endAthlete))
            }
        }

        var collidingIndices = Set<Int>()
        var paths: [[CGPoint]] = []
        for pair in matchedPairs {
            if !pair.start.pathWaypoints.isEmpty {
                paths.append(
                    waypointPath(
                        from: pair.start.position,
                        to: pair.end.position,
                        waypoints: pair.start.pathWaypoints,
                        steps: steps
                    ))
            } else {
                paths.append(
                    athletePath(
                        from: pair.start.position,
                        to: pair.end.position,
                        control: pair.start.pathControlPoint,
                        steps: steps
                    ))
            }
        }
        let minDistanceSq = minDistance * minDistance
        for i in 0..<matchedPairs.count {
            for j in (i + 1)..<matchedPairs.count {
                for step in 0..<min(paths[i].count, paths[j].count) {
                    if squaredDistance(from: paths[i][step], to: paths[j][step]) < minDistanceSq {
                        collidingIndices.insert(matchedPairs[i].index)
                        collidingIndices.insert(matchedPairs[j].index)
                        break
                    }
                }
            }
        }
        return collidingIndices
    }
}

// MARK: - Transition Player

class TransitionPlayer: ObservableObject {
    @Published var isPlaying = false
    @Published var isLooping = false
    @Published var progress: CGFloat = 0.0  // 0.0 to 1.0
    @Published var currentFormation: Formation
    @Published var speed: CGFloat = 1.0  // playback speed multiplier
    @Published var startFormation: Formation  // mutable for timing edits

    @Published var endFormation: Formation
    var duration: TimeInterval
    private var animationTimer: AnimationTimer?

    init(from start: Formation, to end: Formation, duration: TimeInterval = 2.0) {
        self.startFormation = start
        self.endFormation = end
        self.duration = duration
        self.currentFormation = start
    }

    deinit {
        animationTimer?.invalidate()
    }

    func play() {
        guard !isPlaying else { return }
        if progress >= 1.0 { progress = 0.0 }
        isPlaying = true
        animationTimer = AnimationTimer { [weak self] in
            self?.update()
        }
    }

    func pause() {
        isPlaying = false
        animationTimer?.invalidate()
        animationTimer = nil
    }

    func reset() {
        pause()
        progress = 0.0
        updateFormationForProgress()
    }

    func seek(to newProgress: CGFloat) {
        progress = max(0, min(1, newProgress))
        updateFormationForProgress()
    }

    private func update() {
        guard isPlaying else { return }
        let deltaProgress = CGFloat(1.0 / 60.0) * speed / CGFloat(duration)
        progress = min(1.0, progress + deltaProgress)
        updateFormationForProgress()
        if progress >= 1.0 {
            if isLooping { progress = 0.0 } else { pause() }
        }
    }

    private func updateFormationForProgress() {
        var newFormation = startFormation
        newFormation.athletes = []

        // Compute the longest effective duration (travel + holds) so timing stays proportional
        let maxEffectiveTime: CGFloat = startFormation.athletes.compactMap { startAthlete -> CGFloat? in
            guard let endAthlete = endFormation.athletes.first(where: { $0.id == startAthlete.id })
            else { return nil }
            let dist = PathCalculations.travelDistance(
                from: startAthlete.position, to: endAthlete.position, athlete: startAthlete)
            let holdTime = startAthlete.pathWaypoints.reduce(CGFloat(0)) { $0 + $1.holdDuration }
            return dist + holdTime  // treat hold seconds as equivalent "distance" for proportioning
        }.max() ?? 1.0

        for startAthlete in startFormation.athletes {
            if let endAthlete = endFormation.athletes.first(where: { $0.id == startAthlete.id }) {
                let dist = PathCalculations.travelDistance(
                    from: startAthlete.position, to: endAthlete.position, athlete: startAthlete)
                let totalHold = startAthlete.pathWaypoints.reduce(CGFloat(0)) { $0 + $1.holdDuration }
                let effectiveTime = dist + totalHold
                // Each athlete's fraction of the total duration is proportional to their effective time
                let durationFraction = maxEffectiveTime > 0 ? effectiveTime / maxEffectiveTime : 1.0
                let timingOffset = min(0.99, startAthlete.moveTiming / CGFloat(duration))
                // Scale progress so this athlete finishes when their duration portion is done
                let adjustedProgress = max(0, progress - timingOffset) / (1.0 - timingOffset)
                let athleteProgress: CGFloat
                if durationFraction > 0 {
                    athleteProgress = min(1.0, adjustedProgress / durationFraction)
                } else {
                    athleteProgress = 1.0  // stationary athlete, jump to end
                }

                // Apply hold-duration adjustment for waypoint paths
                let effectiveProgress: CGFloat
                if !startAthlete.pathWaypoints.isEmpty && totalHold > 0 {
                    let thresholds = PathCalculations.waypointProgressThresholds(
                        from: startAthlete.position, to: endAthlete.position,
                        waypoints: startAthlete.pathWaypoints)
                    let moveDuration = durationFraction * CGFloat(duration) * (dist / effectiveTime)
                    effectiveProgress = PathCalculations.holdAdjustedPathProgress(
                        wallProgress: athleteProgress, waypoints: startAthlete.pathWaypoints,
                        thresholds: thresholds, moveDuration: moveDuration,
                        totalHoldTime: totalHold)
                } else {
                    effectiveProgress = athleteProgress
                }

                let newPosition: CGPoint
                if !startAthlete.pathWaypoints.isEmpty {
                    newPosition = PathCalculations.interpolateWaypointPath(
                        from: startAthlete.position, to: endAthlete.position,
                        waypoints: startAthlete.pathWaypoints, progress: effectiveProgress)
                } else if let c = startAthlete.pathControlPoint {
                    newPosition = PathCalculations.quadraticBezierPoint(
                        from: startAthlete.position, control: c, to: endAthlete.position,
                        t: athleteProgress)
                } else {
                    newPosition = CGPoint(
                        x: startAthlete.position.x
                            + (endAthlete.position.x - startAthlete.position.x) * athleteProgress,
                        y: startAthlete.position.y
                            + (endAthlete.position.y - startAthlete.position.y) * athleteProgress
                    )
                }

                var athlete = startAthlete
                athlete.position = newPosition
                newFormation.athletes.append(athlete)
            } else {
                // No matching end athlete — keep start position
                newFormation.athletes.append(startAthlete)
            }
        }

        currentFormation = newFormation
    }
}

// MARK: - Animation Timer Helper

class AnimationTimer {
    private var timer: Timer?

    init(closure: @escaping () -> Void) {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            closure()
        }
    }

    func invalidate() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        invalidate()
    }
}
