import Foundation
import SwiftUI

// MARK: - Constants

enum CourtConstants {
    static let width: CGFloat = 72
    static let height: CGFloat = 56
    static let collisionDistance: CGFloat = 2.0
    static let hitRadiusSquared: CGFloat = 9.0
}

// MARK: - Templates

enum FormationTemplates {
    static func defaultSpawnPosition(for index: Int) -> CGPoint {
        let athletesPerRow = 8
        let col = index % athletesPerRow
        let row = index / athletesPerRow

        let x = min(CourtConstants.width - 2, 8.0 + CGFloat(col) * 8.0)
        let panelIndex = row / 2
        let isCenter = row % 2 == 1
        let y = min(
            CourtConstants.height - 2,
            8.0 + CGFloat(panelIndex) * 8.0 + (isCenter ? 4.0 : 0.0)
        )
        return CGPoint(x: x, y: y)
    }

    static func bowlingPinPositions() -> [CGPoint] {
        let centerX: CGFloat = CourtConstants.width / 2
        let startY: CGFloat = CourtConstants.height / 2 - 6
        let rowSpacing: CGFloat = 4
        let colSpacing: CGFloat = 4

        var positions: [CGPoint] = []
        for row in 0...3 {
            let count = row + 1
            let y = startY + CGFloat(row) * rowSpacing
            let rowWidth = CGFloat(count - 1) * colSpacing
            let startX = centerX - rowWidth / 2
            for col in 0..<count {
                positions.append(CGPoint(x: startX + CGFloat(col) * colSpacing, y: y))
            }
        }
        return positions
    }
}

// MARK: - Athlete Role

enum AthleteRole: String, Codable, CaseIterable, Hashable {
    case base
    case flyer
    case spotter
    case backspot
    case tumbler
    case stuntGroup

    var color: Color {
        switch self {
        case .base: return .blue
        case .flyer: return .yellow
        case .spotter: return .green
        case .backspot: return .purple
        case .tumbler: return .orange
        case .stuntGroup: return .pink
        }
    }

    var shortLabel: String {
        switch self {
        case .base: return "B"
        case .flyer: return "F"
        case .spotter: return "S"
        case .backspot: return "BS"
        case .tumbler: return "T"
        case .stuntGroup: return "SG"
        }
    }

    var displayName: String {
        switch self {
        case .base: return "Base"
        case .flyer: return "Flyer"
        case .spotter: return "Spotter"
        case .backspot: return "Backspot"
        case .tumbler: return "Tumbler"
        case .stuntGroup: return "Stunt Group"
        }
    }

    var markerRadius: CGFloat {
        switch self {
        case .stuntGroup:
            return 18
        default:
            return 14
        }
    }

    var selectedMarkerRadius: CGFloat {
        switch self {
        case .stuntGroup:
            return 22
        default:
            return 18
        }
    }

    func markerPath(center: CGPoint, radius: CGFloat) -> Path {
        markerPath(
            in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        )
    }

    func markerPath(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX
        let cy = rect.midY
        let r = min(rect.width, rect.height) / 2

        switch self {
        case .base:
            // Circle
            path.addEllipse(in: rect)

        case .flyer:
            // Diamond
            path.move(to: CGPoint(x: cx, y: cy - r))
            path.addLine(to: CGPoint(x: cx + r, y: cy))
            path.addLine(to: CGPoint(x: cx, y: cy + r))
            path.addLine(to: CGPoint(x: cx - r, y: cy))
            path.closeSubpath()

        case .spotter:
            // Pentagon
            for i in 0..<5 {
                let angle = (CGFloat(i) * 2 * .pi / 5) - .pi / 2
                let point = CGPoint(x: cx + r * cos(angle), y: cy + r * sin(angle))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()

        case .backspot:
            // Hexagon
            for i in 0..<6 {
                let angle = (CGFloat(i) * 2 * .pi / 6) - .pi / 6
                let point = CGPoint(x: cx + r * cos(angle), y: cy + r * sin(angle))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()

        case .tumbler:
            // Star (5-pointed)
            let innerR = r * 0.42
            for i in 0..<10 {
                let angle = (CGFloat(i) * .pi / 5) - .pi / 2
                let pointR = i % 2 == 0 ? r : innerR
                let point = CGPoint(x: cx + pointR * cos(angle), y: cy + pointR * sin(angle))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()

        case .stuntGroup:
            // Triangle
            path.move(to: CGPoint(x: cx, y: cy - r))
            path.addLine(to: CGPoint(x: cx + r, y: cy + r))
            path.addLine(to: CGPoint(x: cx - r, y: cy + r))
            path.closeSubpath()
        }

        return path
    }
}

enum PreviewReferenceMode: String, Codable, CaseIterable, Hashable, Identifiable {
    case intoSelected
    case outOfSelected

    var id: String { rawValue }

    var title: String {
        switch self {
        case .intoSelected:
            return "Into Current"
        case .outOfSelected:
            return "Out of Current"
        }
    }

    var description: String {
        switch self {
        case .intoSelected:
            return "Transition from the prior formation into the selected one."
        case .outOfSelected:
            return "Transition from the selected formation into the next one."
        }
    }

    var editableEndpoint: PreviewEditableEndpoint {
        switch self {
        case .intoSelected:
            return .start
        case .outOfSelected:
            return .end
        }
    }

    func transitionPair(
        in formations: [Formation],
        selectedIndex: Int?
    ) -> (start: Formation, end: Formation)? {
        guard let selectedIndex, formations.indices.contains(selectedIndex) else { return nil }

        switch self {
        case .intoSelected:
            guard formations.indices.contains(selectedIndex - 1) else { return nil }
            return (formations[selectedIndex - 1], formations[selectedIndex])
        case .outOfSelected:
            guard formations.indices.contains(selectedIndex + 1) else { return nil }
            return (formations[selectedIndex], formations[selectedIndex + 1])
        }
    }
}

// MARK: - Path Waypoint

struct PathWaypoint: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var position: CGPoint
    var isSmooth: Bool
    var holdDuration: CGFloat

    var holdCounts: CGFloat {
        get { holdDuration }
        set { holdDuration = newValue }
    }

    init(
        id: UUID = UUID(),
        position: CGPoint,
        isSmooth: Bool = true,
        holdDuration: CGFloat = 0
    ) {
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
        holdDuration = (try? container.decode(CGFloat.self, forKey: .holdDuration)) ?? 0
        let x = try container.decode(CGFloat.self, forKey: .positionX)
        let y = try container.decode(CGFloat.self, forKey: .positionY)
        position = CGPoint(x: x, y: y)
    }
}

// MARK: - Routine Models

struct RosterAthlete: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var label: String
    var role: AthleteRole

    init(id: UUID = UUID(), label: String, role: AthleteRole = .base) {
        self.id = id
        self.label = label
        self.role = role
    }
}

struct FormationPlacement: Codable, Identifiable, Equatable, Hashable {
    var athleteID: UUID
    var position: CGPoint

    var id: UUID { athleteID }

    enum CodingKeys: String, CodingKey {
        case athleteID
        case positionX, positionY
    }

    init(athleteID: UUID, position: CGPoint) {
        self.athleteID = athleteID
        self.position = position
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(athleteID, forKey: .athleteID)
        try container.encode(position.x, forKey: .positionX)
        try container.encode(position.y, forKey: .positionY)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        athleteID = try container.decode(UUID.self, forKey: .athleteID)
        let x = try container.decode(CGFloat.self, forKey: .positionX)
        let y = try container.decode(CGFloat.self, forKey: .positionY)
        position = CGPoint(x: x, y: y)
    }
}

struct Formation: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var name: String
    var notes: String
    var placements: [FormationPlacement]

    init(
        id: UUID = UUID(),
        name: String = "Untitled Formation",
        notes: String = "",
        placements: [FormationPlacement] = []
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.placements = placements
    }

    func placementIndex(for athleteID: UUID) -> Int? {
        placements.firstIndex(where: { $0.athleteID == athleteID })
    }
}

struct AthleteTransition: Codable, Identifiable, Equatable, Hashable {
    var athleteID: UUID
    var moveDelay: CGFloat
    var pathControlPoint: CGPoint?
    var pathWaypoints: [PathWaypoint]

    var id: UUID { athleteID }
    var moveDelayCounts: CGFloat {
        get { moveDelay }
        set { moveDelay = newValue }
    }

    enum CodingKeys: String, CodingKey {
        case athleteID, moveDelay, pathWaypoints
        case controlX, controlY
    }

    init(
        athleteID: UUID,
        moveDelay: CGFloat = 0,
        pathControlPoint: CGPoint? = nil,
        pathWaypoints: [PathWaypoint] = []
    ) {
        self.athleteID = athleteID
        self.moveDelay = moveDelay
        self.pathControlPoint = pathControlPoint
        self.pathWaypoints = pathWaypoints
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(athleteID, forKey: .athleteID)
        try container.encode(moveDelay, forKey: .moveDelay)
        try container.encode(pathWaypoints, forKey: .pathWaypoints)
        if let controlPoint = pathControlPoint {
            try container.encode(controlPoint.x, forKey: .controlX)
            try container.encode(controlPoint.y, forKey: .controlY)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        athleteID = try container.decode(UUID.self, forKey: .athleteID)
        moveDelay = (try? container.decode(CGFloat.self, forKey: .moveDelay)) ?? 0
        pathWaypoints = (try? container.decode([PathWaypoint].self, forKey: .pathWaypoints)) ?? []
        if let x = try? container.decode(CGFloat.self, forKey: .controlX),
            let y = try? container.decode(CGFloat.self, forKey: .controlY)
        {
            pathControlPoint = CGPoint(x: x, y: y)
        } else {
            pathControlPoint = nil
        }
    }
}

struct TransitionSpec: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var fromFormationID: UUID
    var toFormationID: UUID
    var duration: Double
    var athleteTransitions: [AthleteTransition]

    var counts: Double {
        get { duration }
        set { duration = newValue }
    }

    init(
        id: UUID = UUID(),
        fromFormationID: UUID,
        toFormationID: UUID,
        duration: Double = 8.0,
        athleteTransitions: [AthleteTransition] = []
    ) {
        self.id = id
        self.fromFormationID = fromFormationID
        self.toFormationID = toFormationID
        self.duration = duration
        self.athleteTransitions = athleteTransitions
    }

    func athleteTransition(for athleteID: UUID) -> AthleteTransition {
        athleteTransitions.first(where: { $0.athleteID == athleteID })
            ?? AthleteTransition(athleteID: athleteID)
    }

    mutating func synchronize(athleteIDs: [UUID]) {
        athleteTransitions = athleteIDs.map { athleteID in
            athleteTransitions.first(where: { $0.athleteID == athleteID })
                ?? AthleteTransition(athleteID: athleteID)
        }
    }
}

struct Routine: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var name: String
    var roster: [RosterAthlete]
    var formations: [Formation]
    var transitionSpecs: [TransitionSpec]

    static func initial() -> Routine {
        Routine(
            id: UUID(),
            name: "Routine 1",
            roster: [],
            formations: [Formation(name: "Formation 1")],
            transitionSpecs: []
        )
    }
}

// MARK: - Render Models

struct RenderedAthlete: Identifiable, Equatable, Hashable {
    let id: UUID
    let label: String
    let role: AthleteRole
    let position: CGPoint
}

struct TransitionPathRenderItem: Identifiable, Equatable, Hashable {
    let athleteID: UUID
    let startPosition: CGPoint
    let endPosition: CGPoint
    let controlPoint: CGPoint?
    let waypoints: [PathWaypoint]
    let moveDelay: CGFloat

    var id: UUID { athleteID }

    init(
        athleteID: UUID,
        startPosition: CGPoint,
        endPosition: CGPoint,
        controlPoint: CGPoint?,
        waypoints: [PathWaypoint],
        moveDelay: CGFloat = 0
    ) {
        self.athleteID = athleteID
        self.startPosition = startPosition
        self.endPosition = endPosition
        self.controlPoint = controlPoint
        self.waypoints = waypoints
        self.moveDelay = moveDelay
    }
}

enum PreviewEditableEndpoint: Hashable {
    case start
    case end

    var title: String {
        switch self {
        case .start:
            return "Previous Picture"
        case .end:
            return "Next Picture"
        }
    }

    var shortTitle: String {
        switch self {
        case .start:
            return "Previous"
        case .end:
            return "Next"
        }
    }
}

struct TransitionEndpointMarkerRenderItem: Identifiable, Equatable, Hashable {
    enum Style: Hashable {
        case editable
        case readOnly
    }

    let athleteID: UUID
    let label: String
    let role: AthleteRole
    let position: CGPoint
    let endpoint: PreviewEditableEndpoint
    let style: Style
    let formationColor: Color

    var id: String {
        "\(athleteID)-\(endpoint)-\(style)"
    }

    static let rainbowColors: [Color] = [
        .red, .orange, .yellow, .green, .cyan, .blue, .indigo, .purple
    ]

    static func rainbowColor(forIndex index: Int) -> Color {
        rainbowColors[index % rainbowColors.count]
    }
}

enum AlignmentGuideOrientation: Hashable {
    case vertical
    case horizontal
}

enum AlignmentGuideGeometry: Hashable {
    case axis(orientation: AlignmentGuideOrientation, value: CGFloat)
    case line(start: CGPoint, end: CGPoint)

    var idComponent: String {
        switch self {
        case let .axis(orientation, value):
            return "axis-\(orientation)-\(Self.quantized(value))"
        case let .line(start, end):
            return "line-\(Self.quantized(start.x))-\(Self.quantized(start.y))-\(Self.quantized(end.x))-\(Self.quantized(end.y))"
        }
    }

    private static func quantized(_ value: CGFloat) -> Int {
        Int((value * 100).rounded())
    }
}

struct AlignmentGuideRenderItem: Identifiable, Equatable, Hashable {
    enum Emphasis: Hashable {
        case strong
        case subtle
    }

    let geometry: AlignmentGuideGeometry
    let emphasis: Emphasis

    init(
        orientation: AlignmentGuideOrientation,
        value: CGFloat,
        emphasis: Emphasis
    ) {
        geometry = .axis(orientation: orientation, value: value)
        self.emphasis = emphasis
    }

    init(
        start: CGPoint,
        end: CGPoint,
        emphasis: Emphasis
    ) {
        geometry = .line(start: start, end: end)
        self.emphasis = emphasis
    }

    var id: String {
        "\(geometry.idComponent)-\(emphasis)"
    }
}

struct AlignmentSnapResult: Equatable, Hashable {
    let translation: CGPoint
    let guides: [AlignmentGuideRenderItem]
}

enum AlignmentSnapEngine {
    static func snap(
        translation: CGPoint,
        startingPositions: [CGPoint],
        otherAthletePositions: [CGPoint],
        threshold: CGFloat = 0.8
    ) -> AlignmentSnapResult {
        guard !startingPositions.isEmpty else {
            return AlignmentSnapResult(translation: translation, guides: [])
        }

        let movingPositions = startingPositions.map {
            CGPoint(x: $0.x + translation.x, y: $0.y + translation.y)
        }
        let candidates = alignmentGuideCandidates(otherAthletePositions: otherAthletePositions)
        let verticalMatch = bestSnapMatch(
            currentValues: movingPositions.map(\.x),
            candidates: candidates.filter { $0.orientation == .vertical },
            threshold: threshold
        )
        let horizontalMatch = bestSnapMatch(
            currentValues: movingPositions.map(\.y),
            candidates: candidates.filter { $0.orientation == .horizontal },
            threshold: threshold
        )
        let adjustedTranslation = CGPoint(
            x: translation.x + (verticalMatch?.delta ?? 0),
            y: translation.y + (horizontalMatch?.delta ?? 0)
        )
        let adjustedMovingPositions = startingPositions.map {
            CGPoint(x: $0.x + adjustedTranslation.x, y: $0.y + adjustedTranslation.y)
        }
        var guides = [verticalMatch?.guide, horizontalMatch?.guide].compactMap { $0 }
        guides.append(
            contentsOf: linearAlignmentGuides(
                movingPositions: adjustedMovingPositions,
                otherAthletePositions: otherAthletePositions
            )
        )

        return AlignmentSnapResult(
            translation: adjustedTranslation,
            guides: guides
        )
    }

    private static func alignmentGuideCandidates(otherAthletePositions: [CGPoint]) -> [SnapGuideCandidate] {
        var candidates = courtGuideCandidates(length: CourtConstants.width, orientation: .vertical)
        candidates.append(
            contentsOf: courtGuideCandidates(length: CourtConstants.height, orientation: .horizontal)
        )

        let xValues = Array(Set(otherAthletePositions.map { round($0.x) }))
        let yValues = Array(Set(otherAthletePositions.map { round($0.y) }))

        candidates.append(
            contentsOf: xValues.map {
                SnapGuideCandidate(
                    orientation: .vertical,
                    value: $0,
                    emphasis: .strong,
                    priority: 130
                )
            }
        )
        candidates.append(
            contentsOf: yValues.map {
                SnapGuideCandidate(
                    orientation: .horizontal,
                    value: $0,
                    emphasis: .strong,
                    priority: 130
                )
            }
        )

        return candidates
    }

    private static func courtGuideCandidates(
        length: CGFloat,
        orientation: AlignmentGuideOrientation
    ) -> [SnapGuideCandidate] {
        var candidates: [SnapGuideCandidate] = stride(from: CGFloat.zero, through: length, by: 8).map {
            SnapGuideCandidate(
                orientation: orientation,
                value: $0,
                emphasis: .strong,
                priority: 110
            )
        }

        let center = length / 2

        candidates.append(
            SnapGuideCandidate(
                orientation: orientation,
                value: center,
                emphasis: .strong,
                priority: 125
            )
        )

        // Panel center guides at the midpoint of each 8ft panel (4, 12, 20, ...)
        let panelCenters = stride(from: CGFloat(4), to: length, by: 8)
            .filter { abs($0 - center) > 0.5 }
        candidates.append(
            contentsOf: panelCenters.map {
                SnapGuideCandidate(
                    orientation: orientation,
                    value: $0,
                    emphasis: .subtle,
                    priority: 100
                )
            }
        )

        return candidates
    }

    private static func bestSnapMatch(
        currentValues: [CGFloat],
        candidates: [SnapGuideCandidate],
        threshold: CGFloat
    ) -> SnapMatch? {
        currentValues
            .flatMap { currentValue in
                candidates.compactMap { candidate -> SnapMatch? in
                    let delta = candidate.value - currentValue
                    guard abs(delta) <= threshold else { return nil }
                    return SnapMatch(
                        delta: delta,
                        guide: AlignmentGuideRenderItem(
                            orientation: candidate.orientation,
                            value: candidate.value,
                            emphasis: candidate.emphasis
                        ),
                        priority: candidate.priority,
                        distance: abs(delta)
                    )
                }
            }
            .sorted {
                if $0.priority != $1.priority {
                    return $0.priority > $1.priority
                }
                return $0.distance < $1.distance
            }
            .first
    }

    private static func linearAlignmentGuides(
        movingPositions: [CGPoint],
        otherAthletePositions: [CGPoint],
        distanceThreshold: CGFloat = 0.001
    ) -> [AlignmentGuideRenderItem] {
        let allPositions = movingPositions + otherAthletePositions
        guard movingPositions.count + otherAthletePositions.count >= 3 else { return [] }

        var seenKeys: Set<LinearGuideKey> = []
        var matches: [LinearGuideMatch] = []

        for firstIndex in 0..<allPositions.count {
            for secondIndex in (firstIndex + 1)..<allPositions.count {
                guard
                    let line = NormalizedGuideLine(
                        from: allPositions[firstIndex],
                        to: allPositions[secondIndex]
                    ),
                    !line.isAxisAligned,
                    seenKeys.insert(line.key).inserted
                else { continue }

                let alignedMovingIndices = movingPositions.indices.filter {
                    line.distance(to: movingPositions[$0]) <= distanceThreshold
                }
                let alignedOtherIndices = otherAthletePositions.indices.filter {
                    line.distance(to: otherAthletePositions[$0]) <= distanceThreshold
                }
                let alignedCount = alignedMovingIndices.count + alignedOtherIndices.count

                guard !alignedMovingIndices.isEmpty, !alignedOtherIndices.isEmpty, alignedCount >= 3 else { continue }
                guard let segment = guideSegment(for: line) else { continue }

                let averageDistance = (
                    alignedMovingIndices.reduce(CGFloat.zero) { total, index in
                        total + line.distance(to: movingPositions[index])
                    }
                    + alignedOtherIndices.reduce(CGFloat.zero) { total, index in
                        total + line.distance(to: otherAthletePositions[index])
                    }
                ) / CGFloat(alignedCount)

                matches.append(
                    LinearGuideMatch(
                        membershipKey: LinearGuideMembershipKey(
                            movingIndices: alignedMovingIndices,
                            otherIndices: alignedOtherIndices
                        ),
                        guide: AlignmentGuideRenderItem(
                            start: segment.start,
                            end: segment.end,
                            emphasis: .strong
                        ),
                        alignedCount: alignedCount,
                        stationaryCount: alignedOtherIndices.count,
                        averageDistance: averageDistance,
                        segmentLength: segment.length
                    )
                )
            }
        }

        return matches
            .sorted {
                if $0.alignedCount != $1.alignedCount {
                    return $0.alignedCount > $1.alignedCount
                }
                if $0.stationaryCount != $1.stationaryCount {
                    return $0.stationaryCount > $1.stationaryCount
                }
                if abs($0.averageDistance - $1.averageDistance) > 0.001 {
                    return $0.averageDistance < $1.averageDistance
                }
                return $0.segmentLength > $1.segmentLength
            }
            .reduce(into: [LinearGuideMatch]()) { result, match in
                guard !result.contains(where: { $0.membershipKey == match.membershipKey }) else { return }
                result.append(match)
            }
            .prefix(3)
            .map(\.guide)
    }

    private static func guideSegment(
        for line: NormalizedGuideLine
    ) -> (start: CGPoint, end: CGPoint, length: CGFloat)? {
        let courtWidth = CourtConstants.width
        let courtHeight = CourtConstants.height
        let epsilon: CGFloat = 0.0001
        var intersections: [CGPoint] = []

        if abs(line.b) > epsilon {
            let yAtLeft = (line.c - line.a * 0) / line.b
            if (0...courtHeight).contains(yAtLeft) {
                intersections.append(CGPoint(x: 0, y: yAtLeft))
            }

            let yAtRight = (line.c - line.a * courtWidth) / line.b
            if (0...courtHeight).contains(yAtRight) {
                intersections.append(CGPoint(x: courtWidth, y: yAtRight))
            }
        }

        if abs(line.a) > epsilon {
            let xAtTop = (line.c - line.b * 0) / line.a
            if (0...courtWidth).contains(xAtTop) {
                intersections.append(CGPoint(x: xAtTop, y: 0))
            }

            let xAtBottom = (line.c - line.b * courtHeight) / line.a
            if (0...courtWidth).contains(xAtBottom) {
                intersections.append(CGPoint(x: xAtBottom, y: courtHeight))
            }
        }

        intersections = deduplicatedIntersections(intersections)
        guard intersections.count >= 2 else { return nil }

        let sorted = intersections.sorted { line.projection(of: $0) < line.projection(of: $1) }
        guard let start = sorted.first, let end = sorted.last else { return nil }

        return (
            start: start,
            end: end,
            length: hypot(end.x - start.x, end.y - start.y)
        )
    }

    private static func deduplicatedIntersections(_ points: [CGPoint]) -> [CGPoint] {
        points.reduce(into: [CGPoint]()) { result, point in
            let alreadyIncluded = result.contains {
                hypot($0.x - point.x, $0.y - point.y) < 0.05
            }
            if !alreadyIncluded {
                result.append(point)
            }
        }
    }

    private struct SnapGuideCandidate {
        let orientation: AlignmentGuideOrientation
        let value: CGFloat
        let emphasis: AlignmentGuideRenderItem.Emphasis
        let priority: Int
    }

    private struct SnapMatch {
        let delta: CGFloat
        let guide: AlignmentGuideRenderItem
        let priority: Int
        let distance: CGFloat
    }

    private struct LinearGuideMatch {
        let membershipKey: LinearGuideMembershipKey
        let guide: AlignmentGuideRenderItem
        let alignedCount: Int
        let stationaryCount: Int
        let averageDistance: CGFloat
        let segmentLength: CGFloat
    }

    private struct LinearGuideMembershipKey: Hashable {
        let movingIndices: [Int]
        let otherIndices: [Int]
    }

    private struct LinearGuideKey: Hashable {
        let a: Int
        let b: Int
        let c: Int
    }

    private struct NormalizedGuideLine {
        let a: CGFloat
        let b: CGFloat
        let c: CGFloat
        let direction: CGPoint
        let key: LinearGuideKey

        init?(from start: CGPoint, to end: CGPoint) {
            let dx = end.x - start.x
            let dy = end.y - start.y
            let length = hypot(dx, dy)
            guard length > 0.001 else { return nil }

            var normalizedA = dy / length
            var normalizedB = -dx / length
            var normalizedC = normalizedA * start.x + normalizedB * start.y

            if normalizedA < -0.0001 || (abs(normalizedA) <= 0.0001 && normalizedB < 0) {
                normalizedA *= -1
                normalizedB *= -1
                normalizedC *= -1
            }

            a = normalizedA
            b = normalizedB
            c = normalizedC
            direction = CGPoint(x: -normalizedB, y: normalizedA)
            key = LinearGuideKey(
                a: Int((normalizedA * 1000).rounded()),
                b: Int((normalizedB * 1000).rounded()),
                c: Int((normalizedC * 1000).rounded())
            )
        }

        var isAxisAligned: Bool {
            abs(direction.x) < 0.01 || abs(direction.y) < 0.01
        }

        func distance(to point: CGPoint) -> CGFloat {
            abs(a * point.x + b * point.y - c)
        }

        func projection(of point: CGPoint) -> CGFloat {
            direction.x * point.x + direction.y * point.y
        }
    }
}

// MARK: - Persistence

@MainActor
final class RoutineStore: ObservableObject {
    private struct TransitionEdge: Hashable {
        let fromID: UUID
        let toID: UUID
    }

    @Published var routine: Routine {
        didSet {
            guard !isLoading else { return }
            save()
        }
    }

    private let storageKey = "routine.v1"
    private var isLoading = false

    init() {
        self.routine = Routine.initial()
        load()
    }

    func load() {
        isLoading = true
        defer { isLoading = false }

        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode(Routine.self, from: data)
        else {
            routine = Routine.initial()
            reconcileRoutineShape()
            save()
            return
        }

        routine = decoded
        reconcileRoutineShape()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(routine) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    func resetRoutine() {
        routine = Routine.initial()
        reconcileRoutineShape()
    }

    func formationIndex(id: UUID?) -> Int? {
        guard let id else { return nil }
        return routine.formations.firstIndex(where: { $0.id == id })
    }

    func rosterIndex(id: UUID) -> Int? {
        routine.roster.firstIndex(where: { $0.id == id })
    }

    func transitionSpecIndex(from fromID: UUID, to toID: UUID) -> Int? {
        routine.transitionSpecs.firstIndex {
            $0.fromFormationID == fromID && $0.toFormationID == toID
        }
    }

    func transitionSpec(for fromID: UUID, to toID: UUID) -> TransitionSpec {
        if let index = transitionSpecIndex(from: fromID, to: toID) {
            return routine.transitionSpecs[index]
        }

        let athleteIDs = routine.formations[formationIndex(id: fromID) ?? 0].placements.map(\.athleteID)
        return TransitionSpec(
            fromFormationID: fromID,
            toFormationID: toID,
            athleteTransitions: athleteIDs.map { AthleteTransition(athleteID: $0) }
        )
    }

    func renderedAthletes(for formationID: UUID) -> [RenderedAthlete] {
        guard let index = formationIndex(id: formationID) else { return [] }
        return renderedAthletes(for: routine.formations[index])
    }

    func renderedAthletes(for formation: Formation) -> [RenderedAthlete] {
        let rosterLookup = Dictionary(uniqueKeysWithValues: routine.roster.map { ($0.id, $0) })
        return formation.placements.compactMap { placement in
            guard let rosterAthlete = rosterLookup[placement.athleteID] else { return nil }
            return RenderedAthlete(
                id: rosterAthlete.id,
                label: rosterAthlete.label,
                role: rosterAthlete.role,
                position: placement.position
            )
        }
    }

    func transitionPaths(from fromID: UUID, to toID: UUID) -> [TransitionPathRenderItem] {
        guard
            let fromIndex = formationIndex(id: fromID),
            let toIndex = formationIndex(id: toID)
        else { return [] }

        let spec = transitionSpec(for: fromID, to: toID)
        let endLookup = Dictionary(
            uniqueKeysWithValues: routine.formations[toIndex].placements.map { ($0.athleteID, $0.position) }
        )

        return routine.formations[fromIndex].placements.compactMap { placement in
            guard let endPosition = endLookup[placement.athleteID] else { return nil }
            let athleteTransition = spec.athleteTransition(for: placement.athleteID)
            return TransitionPathRenderItem(
                athleteID: placement.athleteID,
                startPosition: placement.position,
                endPosition: endPosition,
                controlPoint: athleteTransition.pathControlPoint,
                waypoints: athleteTransition.pathWaypoints,
                moveDelay: athleteTransition.moveDelay
            )
        }
    }

    func addFormation(after formationID: UUID?) -> UUID {
        let newFormation = Formation(
            name: nextFormationName(),
            placements: routine.roster.enumerated().map { index, athlete in
                FormationPlacement(athleteID: athlete.id, position: FormationTemplates.defaultSpawnPosition(for: index))
            }
        )

        if let currentIndex = formationIndex(id: formationID) {
            routine.formations.insert(newFormation, at: currentIndex + 1)
        } else {
            routine.formations.append(newFormation)
        }
        reconcileTransitionSpecs()
        return newFormation.id
    }

    func duplicateFormation(after formationID: UUID) -> UUID {
        guard let index = formationIndex(id: formationID) else {
            return addFormation(after: nil)
        }

        let source = routine.formations[index]
        let duplicated = Formation(
            name: nextFormationName(),
            notes: source.notes,
            placements: source.placements
        )
        routine.formations.insert(duplicated, at: index + 1)
        reconcileTransitionSpecs()
        return duplicated.id
    }

    func deleteFormation(id: UUID) {
        guard routine.formations.count > 1 else {
            routine.formations = [Formation(name: "Formation 1")]
            routine.transitionSpecs = []
            reconcileRoutineShape()
            return
        }

        routine.formations.removeAll { $0.id == id }
        reconcileTransitionSpecs()
    }

    func moveFormations(fromOffsets: IndexSet, toOffset: Int) {
        routine.formations.move(fromOffsets: fromOffsets, toOffset: toOffset)
        reconcileTransitionSpecs()
    }

    @discardableResult
    func addAthlete() -> UUID {
        let newAthlete = RosterAthlete(label: nextRosterLabel())
        let athleteIndex = routine.roster.count
        routine.roster.append(newAthlete)

        for formationIndex in routine.formations.indices {
            routine.formations[formationIndex].placements.append(
                FormationPlacement(
                    athleteID: newAthlete.id,
                    position: FormationTemplates.defaultSpawnPosition(for: athleteIndex)
                )
            )
        }

        reconcileTransitionSpecs()
        return newAthlete.id
    }

    func applyBowlingPinTemplate(to formationID: UUID) {
        while routine.roster.count < 10 {
            _ = addAthlete()
        }

        guard let formationIndex = formationIndex(id: formationID) else { return }
        let positions = FormationTemplates.bowlingPinPositions()

        for (index, athlete) in routine.roster.enumerated() {
            if index >= routine.formations[formationIndex].placements.count {
                routine.formations[formationIndex].placements.append(
                    FormationPlacement(
                        athleteID: athlete.id,
                        position: FormationTemplates.defaultSpawnPosition(for: index)
                    )
                )
            }
        }

        for index in 0..<routine.formations[formationIndex].placements.count {
            let position = index < positions.count
                ? positions[index]
                : FormationTemplates.defaultSpawnPosition(for: index)
            routine.formations[formationIndex].placements[index].position = position
        }

        if routine.roster.count >= 10 {
            for index in 0..<10 {
                routine.roster[index].label = "A\(index + 1)"
            }
        }

        reconcileTransitionSpecs()
    }

    func moveRoster(fromOffsets: IndexSet, toOffset: Int) {
        routine.roster.move(fromOffsets: fromOffsets, toOffset: toOffset)
        let orderedIDs = routine.roster.map(\.id)

        for formationIndex in routine.formations.indices {
            var placementLookup = Dictionary(
                uniqueKeysWithValues: routine.formations[formationIndex].placements.map { ($0.athleteID, $0) }
            )
            routine.formations[formationIndex].placements = orderedIDs.compactMap { placementLookup.removeValue(forKey: $0) }
        }

        reconcileTransitionSpecs()
    }

    func deleteAthlete(id: UUID) {
        routine.roster.removeAll { $0.id == id }
        for formationIndex in routine.formations.indices {
            routine.formations[formationIndex].placements.removeAll { $0.athleteID == id }
        }
        for transitionIndex in routine.transitionSpecs.indices {
            routine.transitionSpecs[transitionIndex].athleteTransitions.removeAll { $0.athleteID == id }
        }
        reconcileTransitionSpecs()
    }

    func swapPositions(in formationID: UUID, id1: UUID, id2: UUID) {
        guard let formationIndex = formationIndex(id: formationID) else { return }
        guard
            let firstIndex = routine.formations[formationIndex].placementIndex(for: id1),
            let secondIndex = routine.formations[formationIndex].placementIndex(for: id2),
            firstIndex != secondIndex
        else { return }

        let firstPosition = routine.formations[formationIndex].placements[firstIndex].position
        routine.formations[formationIndex].placements[firstIndex].position =
            routine.formations[formationIndex].placements[secondIndex].position
        routine.formations[formationIndex].placements[secondIndex].position = firstPosition
    }

    func mutateFormation(id: UUID, _ update: (inout Formation) -> Void) {
        guard let index = formationIndex(id: id) else { return }
        update(&routine.formations[index])
    }

    func mutateRosterAthlete(id: UUID, _ update: (inout RosterAthlete) -> Void) {
        guard let index = rosterIndex(id: id) else { return }
        update(&routine.roster[index])
    }

    func mutateTransitionSpec(from fromID: UUID, to toID: UUID, _ update: (inout TransitionSpec) -> Void) {
        guard let index = transitionSpecIndex(from: fromID, to: toID) else { return }
        update(&routine.transitionSpecs[index])
        let athleteIDs = routine.formations[formationIndex(id: fromID) ?? 0].placements.map(\.athleteID)
        routine.transitionSpecs[index].synchronize(athleteIDs: athleteIDs)
    }

    func mutateAthleteTransition(
        from fromID: UUID,
        to toID: UUID,
        athleteID: UUID,
        _ update: (inout AthleteTransition) -> Void
    ) {
        guard let specIndex = transitionSpecIndex(from: fromID, to: toID) else { return }
        let athleteIndex =
            routine.transitionSpecs[specIndex].athleteTransitions.firstIndex(where: { $0.athleteID == athleteID })
            ?? {
                routine.transitionSpecs[specIndex].athleteTransitions.append(AthleteTransition(athleteID: athleteID))
                return routine.transitionSpecs[specIndex].athleteTransitions.count - 1
            }()

        update(&routine.transitionSpecs[specIndex].athleteTransitions[athleteIndex])
        let athleteIDs = routine.formations[formationIndex(id: fromID) ?? 0].placements.map(\.athleteID)
        routine.transitionSpecs[specIndex].synchronize(athleteIDs: athleteIDs)
    }

    private func nextRosterLabel() -> String {
        let existing = Set(routine.roster.map(\.label))
        var index = routine.roster.count + 1
        var candidate = "A\(index)"
        while existing.contains(candidate) {
            index += 1
            candidate = "A\(index)"
        }
        return candidate
    }

    private func nextFormationName() -> String {
        let existing = Set(routine.formations.map(\.name))
        var index = routine.formations.count + 1
        var candidate = "Formation \(index)"
        while existing.contains(candidate) {
            index += 1
            candidate = "Formation \(index)"
        }
        return candidate
    }

    private func reconcileRoutineShape() {
        if routine.formations.isEmpty {
            routine.formations = [Formation(name: "Formation 1")]
        }

        let rosterIDs = routine.roster.map(\.id)
        for index in routine.formations.indices {
            var placementLookup = Dictionary(
                uniqueKeysWithValues: routine.formations[index].placements.map { ($0.athleteID, $0) }
            )
            routine.formations[index].placements = rosterIDs.enumerated().map { offset, athleteID in
                placementLookup.removeValue(forKey: athleteID)
                    ?? FormationPlacement(
                        athleteID: athleteID,
                        position: FormationTemplates.defaultSpawnPosition(for: offset)
                    )
            }
        }

        reconcileTransitionSpecs()
    }

    private func reconcileTransitionSpecs() {
        let existing = Dictionary(
            uniqueKeysWithValues: routine.transitionSpecs.map {
                (TransitionEdge(fromID: $0.fromFormationID, toID: $0.toFormationID), $0)
            }
        )

        routine.transitionSpecs = routine.formations.indices.dropLast().map { index in
            let fromFormation = routine.formations[index]
            let toFormation = routine.formations[index + 1]
            var spec = existing[TransitionEdge(fromID: fromFormation.id, toID: toFormation.id)]
                ?? TransitionSpec(
                    fromFormationID: fromFormation.id,
                    toFormationID: toFormation.id,
                    athleteTransitions: fromFormation.placements.map {
                        AthleteTransition(athleteID: $0.athleteID)
                    }
                )
            spec.fromFormationID = fromFormation.id
            spec.toFormationID = toFormation.id
            spec.synchronize(athleteIDs: fromFormation.placements.map(\.athleteID))
            return spec
        }
    }
}

// MARK: - Path Calculation Utilities

struct PathCalculations {
    static func distance(from: CGPoint, to: CGPoint) -> CGFloat {
        hypot(to.x - from.x, to.y - from.y)
    }

    static func squaredDistance(from: CGPoint, to: CGPoint) -> CGFloat {
        let dx = to.x - from.x
        let dy = to.y - from.y
        return dx * dx + dy * dy
    }

    static func quadraticBezierPoint(
        from p0: CGPoint,
        control c: CGPoint,
        to p2: CGPoint,
        t: CGFloat
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

    static func cubicBezierPoint(
        p0: CGPoint,
        c1: CGPoint,
        c2: CGPoint,
        p3: CGPoint,
        t: CGFloat
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

    static func waypointNodes(from start: CGPoint, to end: CGPoint, waypoints: [PathWaypoint]) -> [CGPoint] {
        [start] + waypoints.map(\.position) + [end]
    }

    static func segmentLengths(_ nodes: [CGPoint]) -> [CGFloat] {
        guard nodes.count > 1 else { return [] }
        return (0..<(nodes.count - 1)).map { distance(from: nodes[$0], to: nodes[$0 + 1]) }
    }

    static func athletePath(
        from: CGPoint,
        to: CGPoint,
        control: CGPoint? = nil,
        steps: Int = 10
    ) -> [CGPoint] {
        guard steps > 1 else { return [from, to] }

        var path: [CGPoint] = [from]
        for index in 1..<steps {
            let t = CGFloat(index) / CGFloat(steps - 1)
            if let control {
                path.append(quadraticBezierPoint(from: from, control: control, to: to, t: t))
            } else {
                path.append(
                    CGPoint(
                        x: from.x + (to.x - from.x) * t,
                        y: from.y + (to.y - from.y) * t
                    )
                )
            }
        }
        path.append(to)
        return path
    }

    static func waypointPath(
        from start: CGPoint,
        to end: CGPoint,
        waypoints: [PathWaypoint],
        steps: Int = 20
    ) -> [CGPoint] {
        guard !waypoints.isEmpty else {
            return athletePath(from: start, to: end, steps: steps)
        }

        let nodes = waypointNodes(from: start, to: end, waypoints: waypoints)
        let lengths = segmentLengths(nodes)
        let totalLength = lengths.reduce(0, +)
        guard totalLength > 0 else { return [start, end] }

        var path: [CGPoint] = [start]
        for segmentIndex in 0..<(nodes.count - 1) {
            let segmentSteps = max(2, Int(round(CGFloat(steps) * lengths[segmentIndex] / totalLength)))
            let p0 = nodes[segmentIndex]
            let p1 = nodes[segmentIndex + 1]
            let waypointAtEnd = segmentIndex < waypoints.count ? waypoints[segmentIndex] : nil

            if waypointAtEnd?.isSmooth == true {
                let prev = segmentIndex > 0 ? nodes[segmentIndex - 1] : p0
                let next = segmentIndex + 2 < nodes.count ? nodes[segmentIndex + 2] : p1
                let c1 = CGPoint(
                    x: p0.x + (p1.x - prev.x) / 6.0,
                    y: p0.y + (p1.y - prev.y) / 6.0
                )
                let c2 = CGPoint(
                    x: p1.x - (next.x - p0.x) / 6.0,
                    y: p1.y - (next.y - p0.y) / 6.0
                )
                for step in 1...segmentSteps {
                    let t = CGFloat(step) / CGFloat(segmentSteps)
                    path.append(cubicBezierPoint(p0: p0, c1: c1, c2: c2, p3: p1, t: t))
                }
            } else {
                for step in 1...segmentSteps {
                    let t = CGFloat(step) / CGFloat(segmentSteps)
                    path.append(
                        CGPoint(
                            x: p0.x + (p1.x - p0.x) * t,
                            y: p0.y + (p1.y - p0.y) * t
                        )
                    )
                }
            }
        }
        return path
    }

    static func interpolateWaypointPath(
        from start: CGPoint,
        to end: CGPoint,
        waypoints: [PathWaypoint],
        progress: CGFloat
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

        let targetDistance = progress * totalLength
        var accumulated: CGFloat = 0
        for segmentIndex in 0..<lengths.count {
            let segmentLength = lengths[segmentIndex]
            if accumulated + segmentLength >= targetDistance || segmentIndex == lengths.count - 1 {
                let localProgress = segmentLength > 0 ? (targetDistance - accumulated) / segmentLength : 0
                let t = max(0, min(1, localProgress))
                let p0 = nodes[segmentIndex]
                let p1 = nodes[segmentIndex + 1]
                let waypointAtEnd = segmentIndex < waypoints.count ? waypoints[segmentIndex] : nil

                if waypointAtEnd?.isSmooth == true {
                    let prev = segmentIndex > 0 ? nodes[segmentIndex - 1] : p0
                    let next = segmentIndex + 2 < nodes.count ? nodes[segmentIndex + 2] : p1
                    let c1 = CGPoint(
                        x: p0.x + (p1.x - prev.x) / 6.0,
                        y: p0.y + (p1.y - prev.y) / 6.0
                    )
                    let c2 = CGPoint(
                        x: p1.x - (next.x - p0.x) / 6.0,
                        y: p1.y - (next.y - p0.y) / 6.0
                    )
                    return cubicBezierPoint(p0: p0, c1: c1, c2: c2, p3: p1, t: t)
                }

                return CGPoint(
                    x: p0.x + (p1.x - p0.x) * t,
                    y: p0.y + (p1.y - p0.y) * t
                )
            }
            accumulated += segmentLength
        }

        return end
    }

    static func waypointProgressThresholds(
        from start: CGPoint,
        to end: CGPoint,
        waypoints: [PathWaypoint]
    ) -> [CGFloat] {
        let nodes = waypointNodes(from: start, to: end, waypoints: waypoints)
        let lengths = segmentLengths(nodes)
        let totalLength = lengths.reduce(0, +)
        guard totalLength > 0 else { return waypoints.map { _ in 0 } }

        var thresholds: [CGFloat] = []
        var accumulated: CGFloat = 0
        for index in 0..<waypoints.count {
            accumulated += lengths[index]
            thresholds.append(accumulated / totalLength)
        }
        return thresholds
    }

    static func holdAdjustedPathProgress(
        wallProgress: CGFloat,
        waypoints: [PathWaypoint],
        thresholds: [CGFloat],
        moveDuration: CGFloat,
        totalHoldTime: CGFloat
    ) -> CGFloat {
        guard !waypoints.isEmpty, totalHoldTime > 0, moveDuration > 0 else {
            return wallProgress
        }

        let effectiveDuration = moveDuration + totalHoldTime
        let elapsed = wallProgress * effectiveDuration
        var timeUsed: CGFloat = 0
        var previousThreshold: CGFloat = 0

        for index in 0..<waypoints.count {
            let threshold = thresholds[index]
            let segmentFraction = threshold - previousThreshold
            let segmentMoveTime = segmentFraction * moveDuration

            if elapsed <= timeUsed + segmentMoveTime {
                let segmentElapsed = elapsed - timeUsed
                let segmentProgress = segmentMoveTime > 0 ? segmentElapsed / segmentMoveTime : 1
                return previousThreshold + segmentFraction * segmentProgress
            }
            timeUsed += segmentMoveTime

            let hold = waypoints[index].holdDuration
            if hold > 0 && elapsed <= timeUsed + hold {
                return threshold
            }
            timeUsed += hold
            previousThreshold = threshold
        }

        let lastFraction = 1.0 - previousThreshold
        let lastMoveTime = lastFraction * moveDuration
        if elapsed <= timeUsed + lastMoveTime {
            let segmentElapsed = elapsed - timeUsed
            let segmentProgress = lastMoveTime > 0 ? segmentElapsed / lastMoveTime : 1
            return previousThreshold + lastFraction * segmentProgress
        }

        return 1.0
    }

    static func travelDistance(
        from start: CGPoint,
        to end: CGPoint,
        transition: AthleteTransition
    ) -> CGFloat {
        if !transition.pathWaypoints.isEmpty {
            let nodes = waypointNodes(from: start, to: end, waypoints: transition.pathWaypoints)
            return segmentLengths(nodes).reduce(0, +)
        }

        if let controlPoint = transition.pathControlPoint {
            let samples = 20
            var length: CGFloat = 0
            var previous = start
            for index in 1...samples {
                let t = CGFloat(index) / CGFloat(samples)
                let point = quadraticBezierPoint(from: start, control: controlPoint, to: end, t: t)
                length += distance(from: previous, to: point)
                previous = point
            }
            return length
        }

        return distance(from: start, to: end)
    }

    static func collisionSummary(
        in athletes: [RenderedAthlete],
        minDistance: CGFloat = CourtConstants.collisionDistance
    ) -> (count: Int, ids: Set<UUID>) {
        guard athletes.count > 1 else { return (0, []) }

        let minDistanceSquared = minDistance * minDistance
        var count = 0
        var ids = Set<UUID>()

        for firstIndex in 0..<athletes.count {
            for secondIndex in (firstIndex + 1)..<athletes.count {
                if squaredDistance(from: athletes[firstIndex].position, to: athletes[secondIndex].position)
                    < minDistanceSquared
                {
                    count += 1
                    ids.insert(athletes[firstIndex].id)
                    ids.insert(athletes[secondIndex].id)
                }
            }
        }

        return (count, ids)
    }

    static func findPathCollisionIDs(
        paths: [TransitionPathRenderItem],
        counts: CGFloat = 8,
        steps: Int = 60,
        minDistance: CGFloat = CourtConstants.collisionDistance
    ) -> Set<UUID> {
        guard paths.count > 1 else { return [] }

        // Compute per-athlete timing data (mirrors TransitionPlayer.updateAthletesForProgress)
        struct AthleteTiming {
            let item: TransitionPathRenderItem
            let transition: AthleteTransition
            let travel: CGFloat
            let hold: CGFloat
            let effectiveTime: CGFloat
        }

        let timings: [AthleteTiming] = paths.map { item in
            let transition = AthleteTransition(
                athleteID: item.athleteID,
                moveDelay: item.moveDelay,
                pathControlPoint: item.controlPoint,
                pathWaypoints: item.waypoints
            )
            let travel = travelDistance(from: item.startPosition, to: item.endPosition, transition: transition)
            let hold = item.waypoints.reduce(CGFloat(0)) { $0 + $1.holdCounts }
            return AthleteTiming(
                item: item,
                transition: transition,
                travel: travel,
                hold: hold,
                effectiveTime: travel + hold
            )
        }

        let maxEffectiveTime = timings.map(\.effectiveTime).max() ?? 1
        let effectiveCounts = max(counts, 0.5)

        // Sample each athlete's position at each time step
        let sampledPositions: [[CGPoint]] = timings.map { timing in
            var positions: [CGPoint] = []
            for step in 0...steps {
                let progress = CGFloat(step) / CGFloat(steps)
                let durationFraction = maxEffectiveTime > 0 ? timing.effectiveTime / maxEffectiveTime : 1
                let timingOffset = min(0.99, timing.item.moveDelay / effectiveCounts)
                let adjustedProgress = max(0, progress - timingOffset) / (1.0 - timingOffset)
                let athleteProgress = durationFraction > 0 ? min(1.0, adjustedProgress / durationFraction) : 1.0

                let effectiveProgress: CGFloat
                if !timing.item.waypoints.isEmpty && timing.hold > 0 {
                    let thresholds = waypointProgressThresholds(
                        from: timing.item.startPosition,
                        to: timing.item.endPosition,
                        waypoints: timing.item.waypoints
                    )
                    let moveDuration = durationFraction * effectiveCounts * (timing.travel / max(timing.effectiveTime, 0.001))
                    effectiveProgress = holdAdjustedPathProgress(
                        wallProgress: athleteProgress,
                        waypoints: timing.item.waypoints,
                        thresholds: thresholds,
                        moveDuration: moveDuration,
                        totalHoldTime: timing.hold
                    )
                } else {
                    effectiveProgress = athleteProgress
                }

                let position: CGPoint
                if !timing.item.waypoints.isEmpty {
                    position = interpolateWaypointPath(
                        from: timing.item.startPosition,
                        to: timing.item.endPosition,
                        waypoints: timing.item.waypoints,
                        progress: effectiveProgress
                    )
                } else if let controlPoint = timing.item.controlPoint {
                    position = quadraticBezierPoint(
                        from: timing.item.startPosition,
                        control: controlPoint,
                        to: timing.item.endPosition,
                        t: athleteProgress
                    )
                } else {
                    position = CGPoint(
                        x: timing.item.startPosition.x + (timing.item.endPosition.x - timing.item.startPosition.x) * athleteProgress,
                        y: timing.item.startPosition.y + (timing.item.endPosition.y - timing.item.startPosition.y) * athleteProgress
                    )
                }
                positions.append(position)
            }
            return positions
        }

        let minDistanceSquared = minDistance * minDistance
        var collisionIDs = Set<UUID>()

        for firstIndex in 0..<paths.count {
            for secondIndex in (firstIndex + 1)..<paths.count {
                for step in 0...steps {
                    if squaredDistance(from: sampledPositions[firstIndex][step], to: sampledPositions[secondIndex][step])
                        < minDistanceSquared
                    {
                        collisionIDs.insert(paths[firstIndex].athleteID)
                        collisionIDs.insert(paths[secondIndex].athleteID)
                        break
                    }
                }
            }
        }

        return collisionIDs
    }
}

// MARK: - Transition Player

@MainActor
final class TransitionPlayer: ObservableObject {
    @Published var isPlaying = false
    @Published var isLooping = false
    @Published var progress: CGFloat = 0
    @Published var currentAthletes: [RenderedAthlete]
    @Published var speed: CGFloat = 1.0
    @Published var startAthletes: [RenderedAthlete]
    @Published var endAthletes: [RenderedAthlete]
    @Published var transitionSpec: TransitionSpec

    var duration: TimeInterval {
        didSet { transitionSpec.duration = duration }
    }

    var counts: TimeInterval {
        get { duration }
        set { duration = newValue }
    }

    private var animationTimer: AnimationTimer?

    init(
        startAthletes: [RenderedAthlete],
        endAthletes: [RenderedAthlete],
        transitionSpec: TransitionSpec
    ) {
        self.startAthletes = startAthletes
        self.endAthletes = endAthletes
        self.transitionSpec = transitionSpec
        self.duration = transitionSpec.duration
        self.currentAthletes = startAthletes
    }

    deinit {
        animationTimer?.invalidate()
    }

    func refresh(
        startAthletes: [RenderedAthlete],
        endAthletes: [RenderedAthlete],
        transitionSpec: TransitionSpec
    ) {
        self.startAthletes = startAthletes
        self.endAthletes = endAthletes
        self.transitionSpec = transitionSpec
        duration = transitionSpec.duration
        updateAthletesForProgress()
    }

    func play() {
        guard !isPlaying else { return }
        if progress >= 1.0 { progress = 0 }
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
        progress = 0
        updateAthletesForProgress()
    }

    func seek(to newProgress: CGFloat) {
        progress = max(0, min(1, newProgress))
        updateAthletesForProgress()
    }

    private func update() {
        guard isPlaying else { return }
        let delta = CGFloat(1.0 / 60.0) * speed / max(CGFloat(duration), 0.5)
        progress = min(1.0, progress + delta)
        updateAthletesForProgress()
        if progress >= 1.0 {
            if isLooping {
                progress = 0
            } else {
                pause()
            }
        }
    }

    private func updateAthletesForProgress() {
        let endLookup = Dictionary(uniqueKeysWithValues: endAthletes.map { ($0.id, $0) })
        let transitionLookup = Dictionary(
            uniqueKeysWithValues: transitionSpec.athleteTransitions.map { ($0.athleteID, $0) }
        )

        let maxEffectiveTime = startAthletes.compactMap { athlete -> CGFloat? in
            guard let endAthlete = endLookup[athlete.id] else { return nil }
            let transition = transitionLookup[athlete.id] ?? AthleteTransition(athleteID: athlete.id)
            let travel = PathCalculations.travelDistance(
                from: athlete.position,
                to: endAthlete.position,
                transition: transition
            )
            let hold = transition.pathWaypoints.reduce(CGFloat(0)) { $0 + $1.holdCounts }
            return travel + hold
        }.max() ?? 1

        currentAthletes = startAthletes.map { athlete in
            guard let endAthlete = endLookup[athlete.id] else { return athlete }
            let transition = transitionLookup[athlete.id] ?? AthleteTransition(athleteID: athlete.id)
            let travel = PathCalculations.travelDistance(
                from: athlete.position,
                to: endAthlete.position,
                transition: transition
            )
            let hold = transition.pathWaypoints.reduce(CGFloat(0)) { $0 + $1.holdCounts }
            let effectiveTime = travel + hold
            let durationFraction = maxEffectiveTime > 0 ? effectiveTime / maxEffectiveTime : 1
            let timingOffset = min(0.99, transition.moveDelayCounts / max(CGFloat(counts), 0.5))
            let adjustedProgress = max(0, progress - timingOffset) / (1.0 - timingOffset)
            let athleteProgress = durationFraction > 0 ? min(1.0, adjustedProgress / durationFraction) : 1.0

            let effectiveProgress: CGFloat
            if !transition.pathWaypoints.isEmpty && hold > 0 {
                let thresholds = PathCalculations.waypointProgressThresholds(
                    from: athlete.position,
                    to: endAthlete.position,
                    waypoints: transition.pathWaypoints
                )
                let moveDuration = durationFraction * max(CGFloat(counts), 0.5) * (travel / max(effectiveTime, 0.001))
                effectiveProgress = PathCalculations.holdAdjustedPathProgress(
                    wallProgress: athleteProgress,
                    waypoints: transition.pathWaypoints,
                    thresholds: thresholds,
                    moveDuration: moveDuration,
                    totalHoldTime: hold
                )
            } else {
                effectiveProgress = athleteProgress
            }

            let nextPosition: CGPoint
            if !transition.pathWaypoints.isEmpty {
                nextPosition = PathCalculations.interpolateWaypointPath(
                    from: athlete.position,
                    to: endAthlete.position,
                    waypoints: transition.pathWaypoints,
                    progress: effectiveProgress
                )
            } else if let controlPoint = transition.pathControlPoint {
                nextPosition = PathCalculations.quadraticBezierPoint(
                    from: athlete.position,
                    control: controlPoint,
                    to: endAthlete.position,
                    t: athleteProgress
                )
            } else {
                nextPosition = CGPoint(
                    x: athlete.position.x + (endAthlete.position.x - athlete.position.x) * athleteProgress,
                    y: athlete.position.y + (endAthlete.position.y - athlete.position.y) * athleteProgress
                )
            }

            return RenderedAthlete(
                id: athlete.id,
                label: athlete.label,
                role: athlete.role,
                position: nextPosition
            )
        }
    }
}

@MainActor
final class TransitionPreviewSession: ObservableObject {
    @Published var player: TransitionPlayer?
    @Published var startFormationID: UUID?
    @Published var endFormationID: UUID?

    func configure(store: RoutineStore, startFormationID: UUID, endFormationID: UUID) {
        let startAthletes = store.renderedAthletes(for: startFormationID)
        let endAthletes = store.renderedAthletes(for: endFormationID)
        let transitionSpec = store.transitionSpec(for: startFormationID, to: endFormationID)

        if let player, self.startFormationID == startFormationID, self.endFormationID == endFormationID {
            player.refresh(
                startAthletes: startAthletes,
                endAthletes: endAthletes,
                transitionSpec: transitionSpec
            )
        } else {
            self.player = TransitionPlayer(
                startAthletes: startAthletes,
                endAthletes: endAthletes,
                transitionSpec: transitionSpec
            )
        }

        self.startFormationID = startFormationID
        self.endFormationID = endFormationID
    }

    func clear() {
        player?.pause()
        player = nil
        startFormationID = nil
        endFormationID = nil
    }
}

// MARK: - Animation Timer Helper

final class AnimationTimer {
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
