import Combine
import Foundation
import OSLog
import SwiftUI

// MARK: - Constants

enum CourtConstants {
    static let width: CGFloat = 72
    static let height: CGFloat = 56
    static let collisionDistance: CGFloat = 1.5
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
    var formattedNotesRTF: Data?
    var notesDrawingData: Data?
    var placements: [FormationPlacement]

    init(
        id: UUID = UUID(),
        name: String = "Untitled Formation",
        notes: String = "",
        formattedNotesRTF: Data? = nil,
        notesDrawingData: Data? = nil,
        placements: [FormationPlacement] = []
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.formattedNotesRTF = formattedNotesRTF
        self.notesDrawingData = notesDrawingData
        self.placements = placements
    }

    var hasCoachCardContent: Bool {
        !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            formattedNotesRTF != nil ||
            notesDrawingData != nil
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case notes
        case formattedNotesRTF
        case notesDrawingData
        case placements
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Untitled Formation"
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        formattedNotesRTF = try container.decodeIfPresent(Data.self, forKey: .formattedNotesRTF)
        notesDrawingData = try container.decodeIfPresent(Data.self, forKey: .notesDrawingData)
        placements = try container.decodeIfPresent([FormationPlacement].self, forKey: .placements) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(notes, forKey: .notes)
        try container.encodeIfPresent(formattedNotesRTF, forKey: .formattedNotesRTF)
        try container.encodeIfPresent(notesDrawingData, forKey: .notesDrawingData)
        try container.encode(placements, forKey: .placements)
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
        duration: Double = 4.0,
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
        let lookup = athleteTransitions.reduce(into: [UUID: AthleteTransition]()) { result, transition in
            if result[transition.athleteID] == nil {
                result[transition.athleteID] = transition
            }
        }
        athleteTransitions = athleteIDs.map { athleteID in
            lookup[athleteID] ?? AthleteTransition(athleteID: athleteID)
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
    let nodes: [CGPoint]

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
        self.nodes = PathCalculations.waypointNodes(from: startPosition, to: endPosition, waypoints: waypoints)
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
        .pink, .orange, .yellow, Color(red: 0.6, green: 0.9, blue: 0.2), .cyan, .blue, .purple
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
        threshold: CGFloat = 0.8,
        skipLinearGuides: Bool = false
    ) -> AlignmentSnapResult {
        guard !startingPositions.isEmpty else {
            return AlignmentSnapResult(translation: translation, guides: [])
        }

        let movingPositions = startingPositions.map {
            CGPoint(x: $0.x + translation.x, y: $0.y + translation.y)
        }
        let candidates = alignmentGuideCandidates(otherAthletePositions: otherAthletePositions)
        let verticalMatch = bestSnapMatch(
            movingPositions: movingPositions,
            valueExtractor: \.x,
            candidates: candidates,
            targetOrientation: .vertical,
            threshold: threshold
        )
        let horizontalMatch = bestSnapMatch(
            movingPositions: movingPositions,
            valueExtractor: \.y,
            candidates: candidates,
            targetOrientation: .horizontal,
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
        if !skipLinearGuides {
            guides.append(
                contentsOf: linearAlignmentGuides(
                    movingPositions: adjustedMovingPositions,
                    otherAthletePositions: otherAthletePositions
                )
            )
        }

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

        var seenX = Set<CGFloat>()
        var seenY = Set<CGFloat>()

        // ⚡ Bolt Performance Optimization:
        // By replacing `Array(Set(otherAthletePositions.map { ... }))` with a single loop
        // and using `Set.insert(_:).inserted`, we eliminate multiple O(N) intermediate
        // heap allocations (map -> Set -> Array) during high-frequency drag alignment evaluations.
        // Expected impact: Removes memory overhead per evaluation tick on large arrays.
        for position in otherAthletePositions {
            let x = round(position.x)
            if seenX.insert(x).inserted {
                candidates.append(
                    SnapGuideCandidate(
                        orientation: .vertical,
                        value: x,
                        emphasis: .strong,
                        priority: 130
                    )
                )
            }
            let y = round(position.y)
            if seenY.insert(y).inserted {
                candidates.append(
                    SnapGuideCandidate(
                        orientation: .horizontal,
                        value: y,
                        emphasis: .strong,
                        priority: 130
                    )
                )
            }
        }

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
        // ⚡ Bolt Performance Optimization:
        // Combined `.filter` and `.map` into a single `.compactMap` call.
        // Expected impact: Eliminates one O(N) array allocation.
        let panelCenterCandidates = stride(from: CGFloat(4), to: length, by: 8).compactMap { panelCenter -> SnapGuideCandidate? in
            guard abs(panelCenter - center) > 0.5 else { return nil }
            return SnapGuideCandidate(
                orientation: orientation,
                value: panelCenter,
                emphasis: .subtle,
                priority: 100
            )
        }
        candidates.append(contentsOf: panelCenterCandidates)

        return candidates
    }

    private static func bestSnapMatch(
        movingPositions: [CGPoint],
        valueExtractor: KeyPath<CGPoint, CGFloat>,
        candidates: [SnapGuideCandidate],
        targetOrientation: AlignmentGuideOrientation,
        threshold: CGFloat
    ) -> SnapMatch? {
        movingPositions
            .flatMap { position in
                let currentValue = position[keyPath: valueExtractor]
                return candidates.compactMap { candidate -> SnapMatch? in
                    guard candidate.orientation == targetOrientation else { return nil }
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
        distanceThreshold: CGFloat = 0.35
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

        let sortedMatches = matches.sorted {
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

        var uniqueGuides: [AlignmentGuideRenderItem] = []
        var seenMemberships = Set<LinearGuideMembershipKey>()

        for match in sortedMatches {
            if seenMemberships.insert(match.membershipKey).inserted {
                uniqueGuides.append(match.guide)
                if uniqueGuides.count >= 3 { break }
            }
        }

        return uniqueGuides
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
        // ⚡ Bolt Performance Optimization:
        // Replaced O(N^2) `.reduce` with `.contains` scan using a spatial hash grid.
        // This reduces complexity to O(N) by only checking points in adjacent grid cells.
        // Expected impact: Significant reduction in time complexity for proximity checks.
        struct GridCell: Hashable {
            let x: Int
            let y: Int
        }
        let tolerance: CGFloat = 0.05
        let toleranceSq = tolerance * tolerance
        var grid: [GridCell: [CGPoint]] = [:]
        var result: [CGPoint] = []

        for point in points {
            let cellX = Int(floor(point.x / tolerance))
            let cellY = Int(floor(point.y / tolerance))

            var alreadyIncluded = false
            for cx in (cellX - 1)...(cellX + 1) {
                for cy in (cellY - 1)...(cellY + 1) {
                    let cell = GridCell(x: cx, y: cy)
                    if let cellPoints = grid[cell] {
                        for p in cellPoints {
                            let dx = p.x - point.x
                            let dy = p.y - point.y
                            if dx * dx + dy * dy < toleranceSq {
                                alreadyIncluded = true
                                break
                            }
                        }
                    }
                    if alreadyIncluded { break }
                }
                if alreadyIncluded { break }
            }

            if !alreadyIncluded {
                result.append(point)
                let cell = GridCell(x: cellX, y: cellY)
                grid[cell, default: []].append(point)
            }
        }
        return result
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

// MARK: - Lightweight Measurement

enum RoutineMetricEvent: String {
    case transitionShareTapped = "transition_share_tapped"
    case transitionShareCompleted = "transition_share_completed"
}

@MainActor
enum RoutineMetrics {
    private static let storageKey = "routine.metrics.v1"
    private static let logger = Logger(subsystem: "FormationFlow", category: "Metrics")

    private struct Snapshot: Codable {
        var counters: [String: Int] = [:]
    }

    static func record(_ event: RoutineMetricEvent, metadata: [String: String] = [:]) {
        var snapshot = load()
        snapshot.counters[event.rawValue, default: 0] += 1
        save(snapshot)

        let metadataSummary = metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")

        if metadataSummary.isEmpty {
            logger.log("metric=\(event.rawValue, privacy: .private)")
        } else {
            logger.log("metric=\(event.rawValue, privacy: .private) \(metadataSummary, privacy: .private)")
        }
    }

    static func count(for event: RoutineMetricEvent) -> Int {
        load().counters[event.rawValue, default: 0]
    }

    private static var fileURL: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("\(storageKey).json")
    }

    private static func load() -> Snapshot {
        if let data = try? Data(contentsOf: fileURL),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            return snapshot
        }

        // Migration from UserDefaults
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            if save(snapshot) { // Save to new fileURL
                UserDefaults.standard.removeObject(forKey: storageKey) // Clean up
            }
            return snapshot
        }

        return Snapshot()
    }

    @discardableResult
    private static func save(_ snapshot: Snapshot) -> Bool {
        guard let data = try? JSONEncoder().encode(snapshot) else { return false }
        do {
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            return true
        } catch {
            Self.logger.error("Failed to save metrics: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }
}

// MARK: - Persistence

struct RoutineWorkspace: Codable, Equatable, Hashable {
    var routines: [Routine]
    var activeRoutineID: UUID

    init(routines: [Routine], activeRoutineID: UUID) {
        self.routines = routines
        self.activeRoutineID = activeRoutineID
    }

    static func initial() -> RoutineWorkspace {
        let initialRoutine = Routine.initial()
        return RoutineWorkspace(
            routines: [initialRoutine],
            activeRoutineID: initialRoutine.id
        )
    }
}

@MainActor
final class RoutineStore: ObservableObject {
    private static let logger = Logger(subsystem: "FormationFlow", category: "Persistence")

    private struct TransitionEdge: Hashable {
        let fromID: UUID
        let toID: UUID
    }

    @Published var workspace: RoutineWorkspace {
        didSet {
            guard !isLoading else { return }
            debouncedSave()
        }
    }

    var routine: Routine {
        get {
            workspace.routines.first(where: { $0.id == workspace.activeRoutineID }) ?? workspace.routines[0]
        }
        set {
            if let index = workspace.routines.firstIndex(where: { $0.id == newValue.id }) {
                workspace.routines[index] = newValue
            } else {
                workspace.routines.append(newValue)
            }
        }
    }

    private let storageKey = "routine.v1"
    private let workspaceStorageKey = "workspace.v1"
    private var isLoading = false
    private var pendingSave: DispatchWorkItem?
    private var rosterLookup: [UUID: RosterAthlete] = [:]
    private var formationIndexLookup: [UUID: Int] = [:]
    private var transitionSpecIndexLookup: [TransitionEdge: Int] = [:]

    init() {
        self.workspace = RoutineWorkspace.initial()
        load()
        rebuildTransitionSpecLookup()
    }

    private var fileURL: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("\(storageKey).json")
    }

    private var workspaceFileURL: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("\(workspaceStorageKey).json")
    }

    func load() {
        isLoading = true
        defer { isLoading = false }

        // Try loading new workspace format
        if let data = try? Data(contentsOf: workspaceFileURL),
           let decoded = try? JSONDecoder().decode(RoutineWorkspace.self, from: data) {
            workspace = decoded
            reconcileRoutineShape()
            rebuildTransitionSpecLookup()
            return
        }

        // Migration from old routine file
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Routine.self, from: data) {
            workspace = RoutineWorkspace(routines: [decoded], activeRoutineID: decoded.id)
            reconcileRoutineShape()
            rebuildTransitionSpecLookup()
            if save() {
                try? FileManager.default.removeItem(at: fileURL) // Clean up
            }
            return
        }

        // Migration from UserDefaults
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(Routine.self, from: data) {
            workspace = RoutineWorkspace(routines: [decoded], activeRoutineID: decoded.id)
            reconcileRoutineShape()
            rebuildTransitionSpecLookup()
            if save() { // Save to new workspaceFileURL
                UserDefaults.standard.removeObject(forKey: storageKey) // Clean up
            }
            return
        }

        workspace = RoutineWorkspace.initial()
        reconcileRoutineShape()
        rebuildTransitionSpecLookup()
        save()
    }

    @discardableResult
    func save() -> Bool {
        guard let data = try? JSONEncoder().encode(workspace) else { return false }
        do {
            try data.write(to: workspaceFileURL, options: [.atomic, .completeFileProtection])
            return true
        } catch {
            Self.logger.error("Failed to save workspace: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    private func debouncedSave() {
        pendingSave?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.save()
        }
        pendingSave = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        save()
    }

    func resetRoutine() {
        routine = Routine.initial()
        reconcileRoutineShape()
        saveNow()
    }

    // MARK: - Routine Management

    func switchRoutine(id: UUID) {
        guard workspace.routines.contains(where: { $0.id == id }) else { return }
        workspace.activeRoutineID = id
        reconcileRoutineShape()
    }

    func addRoutine() -> UUID {
        var newRoutine = Routine.initial()
        newRoutine.name = nextRoutineName()
        workspace.routines.append(newRoutine)
        workspace.activeRoutineID = newRoutine.id
        reconcileRoutineShape()
        return newRoutine.id
    }

    func duplicateRoutine(id: UUID) -> UUID? {
        guard let sourceIndex = workspace.routines.firstIndex(where: { $0.id == id }) else { return nil }
        var duplicated = workspace.routines[sourceIndex]
        duplicated.id = UUID()
        duplicated.name = nextRoutineName()

        // Give new UUIDs to formations to avoid sharing IDs across routines
        let idMap = duplicated.formations.reduce(into: [UUID: UUID]()) { result, formation in
            result[formation.id] = UUID()
        }
        for i in duplicated.formations.indices {
            if let newID = idMap[duplicated.formations[i].id] {
                duplicated.formations[i].id = newID
            }
        }
        for i in duplicated.transitionSpecs.indices {
            if let newFromID = idMap[duplicated.transitionSpecs[i].fromFormationID] {
                duplicated.transitionSpecs[i].fromFormationID = newFromID
            }
            if let newToID = idMap[duplicated.transitionSpecs[i].toFormationID] {
                duplicated.transitionSpecs[i].toFormationID = newToID
            }
        }

        workspace.routines.insert(duplicated, at: sourceIndex + 1)
        workspace.activeRoutineID = duplicated.id
        reconcileRoutineShape()
        return duplicated.id
    }

    func deleteRoutine(id: UUID) {
        guard workspace.routines.count > 1 else { return }
        if let index = workspace.routines.firstIndex(where: { $0.id == id }) {
            workspace.routines.remove(at: index)
            if workspace.activeRoutineID == id {
                workspace.activeRoutineID = workspace.routines.first?.id ?? UUID()
            }
            reconcileRoutineShape()
        }
    }

    func renameRoutine(id: UUID, newName: String) {
        if let index = workspace.routines.firstIndex(where: { $0.id == id }) {
            workspace.routines[index].name = newName
        }
    }

    private func nextRoutineName() -> String {
        // ⚡ Bolt: Eliminate intermediate array allocation in Set init
        let existing = workspace.routines.reduce(into: Set<String>()) { $0.insert($1.name) }
        var index = workspace.routines.count + 1
        var candidate = "Routine \(index)"
        while existing.contains(candidate) {
            index += 1
            candidate = "Routine \(index)"
        }
        return candidate
    }

    // MARK: - Formation Management

    func formationIndex(id: UUID?) -> Int? {
        guard let id else { return nil }
        if let index = formationIndexLookup[id],
           index < routine.formations.count,
           routine.formations[index].id == id {
            return index
        }
        return routine.formations.firstIndex(where: { $0.id == id })
    }

    func formation(id: UUID) -> Formation? {
        guard let index = formationIndexLookup[id],
              index < routine.formations.count,
              routine.formations[index].id == id else {
            return routine.formations.first(where: { $0.id == id })
        }
        return routine.formations[index]
    }

    func rosterIndex(id: UUID) -> Int? {
        routine.roster.firstIndex(where: { $0.id == id })
    }

    func transitionSpecIndex(from fromID: UUID, to toID: UUID) -> Int? {
        let edge = TransitionEdge(fromID: fromID, toID: toID)
        if let index = transitionSpecIndexLookup[edge],
           index < routine.transitionSpecs.count,
           routine.transitionSpecs[index].fromFormationID == fromID,
           routine.transitionSpecs[index].toFormationID == toID {
            return index
        }

        return routine.transitionSpecs.firstIndex {
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
        let endLookup = routine.formations[toIndex].placements.reduce(into: [UUID: CGPoint]()) { result, placement in
            if result[placement.athleteID] == nil {
                result[placement.athleteID] = placement.position
            }
        }
        let transitionLookup = spec.athleteTransitions.reduce(into: [UUID: AthleteTransition]()) { result, transition in
            if result[transition.athleteID] == nil {
                result[transition.athleteID] = transition
            }
        }

        return routine.formations[fromIndex].placements.compactMap { placement in
            guard let endPosition = endLookup[placement.athleteID] else { return nil }
            let athleteTransition = transitionLookup[placement.athleteID] ?? AthleteTransition(athleteID: placement.athleteID)
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
        let insertionIndex: Int
        let sourceFormation: Formation?

        if let formationID, let currentIndex = formationIndex(id: formationID) {
            insertionIndex = currentIndex + 1
            sourceFormation = routine.formations[currentIndex]
        } else {
            insertionIndex = routine.formations.count
            sourceFormation = routine.formations.last
        }

        let newFormation = Formation(
            name: nextFormationName(),
            notes: sourceFormation?.notes ?? "",
            placements: sourceFormation?.placements
                ?? routine.roster.enumerated().map { index, athlete in
                    FormationPlacement(athleteID: athlete.id, position: FormationTemplates.defaultSpawnPosition(for: index))
                }
        )

        routine.formations.insert(newFormation, at: insertionIndex)
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
        guard formationIndex(id: id) != nil else { return }

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

    func moveFormationEarlier(id: UUID) {
        guard let index = formationIndex(id: id), index > 0 else { return }
        routine.formations.swapAt(index, index - 1)
        reconcileTransitionSpecs()
    }

    func moveFormationLater(id: UUID) {
        guard let index = formationIndex(id: id), index < routine.formations.count - 1 else { return }
        routine.formations.swapAt(index, index + 1)
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
        rebuildRosterLookup()
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

        reconcileTransitionSpecs()
    }

    func moveRoster(fromOffsets: IndexSet, toOffset: Int) {
        routine.roster.move(fromOffsets: fromOffsets, toOffset: toOffset)
        let orderedIDs = routine.roster.map(\.id)

        for formationIndex in routine.formations.indices {
            var placementLookup = routine.formations[formationIndex].placements.reduce(into: [UUID: FormationPlacement]()) { result, placement in
                if result[placement.athleteID] == nil {
                    result[placement.athleteID] = placement
                }
            }
            routine.formations[formationIndex].placements = orderedIDs.compactMap { placementLookup.removeValue(forKey: $0) }
        }

        reconcileTransitionSpecs()
    }

    func deleteAthlete(id: UUID) {
        var updated = routine
        updated.roster.removeAll { $0.id == id }
        for formationIndex in updated.formations.indices {
            updated.formations[formationIndex].placements.removeAll { $0.athleteID == id }
        }
        for transitionIndex in updated.transitionSpecs.indices {
            updated.transitionSpecs[transitionIndex].athleteTransitions.removeAll { $0.athleteID == id }
        }
        routine = updated
        rebuildRosterLookup()
        rebuildFormationLookup()
        rebuildTransitionSpecLookup()
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
        rebuildRosterLookup()
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
        // ⚡ Bolt: Eliminate intermediate array allocation in Set init
        let existing = routine.roster.reduce(into: Set<String>()) { $0.insert($1.label) }
        var index = routine.roster.count + 1
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

        func generateLabel(for idx: Int) -> String {
            let zeroBasedIdx = idx - 1
            let groupIndex = zeroBasedIdx / 5
            let positionIndex = (zeroBasedIdx % 5) + 1

            if groupIndex < alphabet.count {
                let letterIndex = alphabet.index(alphabet.startIndex, offsetBy: groupIndex)
                return "\(alphabet[letterIndex])\(positionIndex)"
            } else {
                return String(format: "%02d", idx)
            }
        }

        var candidate = generateLabel(for: index)
        while existing.contains(candidate) {
            index += 1
            candidate = generateLabel(for: index)
        }
        return candidate
    }

    private func nextFormationName() -> String {
        // ⚡ Bolt: Eliminate intermediate array allocation in Set init
        let existing = routine.formations.reduce(into: Set<String>()) { $0.insert($1.name) }
        var index = routine.formations.count + 1
        var candidate = "Formation \(index)"
        while existing.contains(candidate) {
            index += 1
            candidate = "Formation \(index)"
        }
        return candidate
    }

    private func rebuildRosterLookup() {
        rosterLookup = routine.roster.reduce(into: [UUID: RosterAthlete]()) { result, athlete in
            if result[athlete.id] == nil {
                result[athlete.id] = athlete
            }
        }
    }

    private func reconcileRoutineShape() {
        if routine.formations.isEmpty {
            routine.formations = [Formation(name: "Formation 1")]
        }

        let rosterIDs = routine.roster.map(\.id)
        for index in routine.formations.indices {
            var placementLookup = routine.formations[index].placements.reduce(into: [UUID: FormationPlacement]()) { result, placement in
                if result[placement.athleteID] == nil {
                    result[placement.athleteID] = placement
                }
            }
            routine.formations[index].placements = rosterIDs.enumerated().map { offset, athleteID in
                placementLookup.removeValue(forKey: athleteID)
                    ?? FormationPlacement(
                        athleteID: athleteID,
                        position: FormationTemplates.defaultSpawnPosition(for: offset)
                    )
            }
        }

        reconcileTransitionSpecs()
        rebuildRosterLookup()
    }

    private func rebuildFormationLookup() {
        formationIndexLookup = routine.formations.enumerated().reduce(into: [UUID: Int]()) { result, element in
            if result[element.element.id] == nil {
                result[element.element.id] = element.offset
            }
        }
    }

    private func reconcileTransitionSpecs() {
        rebuildFormationLookup()

        let existing = routine.transitionSpecs.reduce(into: [TransitionEdge: TransitionSpec]()) { result, spec in
            let edge = TransitionEdge(fromID: spec.fromFormationID, toID: spec.toFormationID)
            if result[edge] == nil {
                result[edge] = spec
            }
        }

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
        rebuildTransitionSpecLookup()
    }

    private func rebuildTransitionSpecLookup() {
        transitionSpecIndexLookup = routine.transitionSpecs.enumerated().reduce(into: [TransitionEdge: Int]()) { result, element in
            let edge = TransitionEdge(fromID: element.element.fromFormationID, toID: element.element.toFormationID)
            if result[edge] == nil {
                result[edge] = element.offset
            }
        }
    }
}

// MARK: - Path Calculation Utilities

struct PathCalculations {
    static let collisionPenaltyCounts: CGFloat = 0.1
    static let defaultPlaybackSpeed: CGFloat = 1.5
    private static let collisionResponseMinimumTravel: CGFloat = 0.001
    private static let collisionRedirectDistance: CGFloat = 1.0
    private static let collisionRedirectLeadProgress: CGFloat = 0.05
    private static let collisionRedirectRecoveryProgress: CGFloat = 0.18
    private static let collisionPulseLeadProgress: CGFloat = 0.025

    struct CollisionResponse: Equatable, Hashable {
        let progress: CGFloat
        let holdCounts: CGFloat
        let redirectOffset: CGPoint
    }

    private struct PathCollisionSample {
        let position: CGPoint
        let pathProgress: CGFloat
    }

    static func delayedMovementProgress(
        timelineProgress: CGFloat,
        moveDelayCounts: CGFloat,
        moveDurationCounts: CGFloat,
        playbackDurationCounts: CGFloat
    ) -> CGFloat {
        let elapsedCounts = max(0, timelineProgress) * max(playbackDurationCounts, 0.001)
        let activeCounts = elapsedCounts - max(0, moveDelayCounts)
        guard moveDurationCounts > 0 else {
            return activeCounts >= 0 ? 1 : 0
        }
        return max(0, min(1, activeCounts / moveDurationCounts))
    }

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

    static func catmullRomControlPoints(
        prev: CGPoint, p0: CGPoint, p1: CGPoint, next: CGPoint
    ) -> (c1: CGPoint, c2: CGPoint) {
        let c1 = CGPoint(
            x: p0.x + (p1.x - prev.x) / 6.0,
            y: p0.y + (p1.y - prev.y) / 6.0
        )
        let c2 = CGPoint(
            x: p1.x - (next.x - p0.x) / 6.0,
            y: p1.y - (next.y - p0.y) / 6.0
        )
        return (c1, c2)
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
                let (c1, c2) = catmullRomControlPoints(prev: prev, p0: p0, p1: p1, next: next)
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
        return interpolateWaypointPath(
            nodes: nodes,
            lengths: lengths,
            totalLength: totalLength,
            waypoints: waypoints,
            progress: progress
        )
    }

    static func interpolateWaypointPath(
        nodes: [CGPoint],
        lengths: [CGFloat],
        totalLength: CGFloat,
        waypoints: [PathWaypoint],
        progress: CGFloat
    ) -> CGPoint {
        guard totalLength > 0, let _ = nodes.first, let end = nodes.last else {
            return nodes.first ?? CGPoint(x: 0, y: 0)
        }

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
                    let (c1, c2) = catmullRomControlPoints(prev: prev, p0: p0, p1: p1, next: next)
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

        let holdEvents = waypoints.indices.map { index in
            (
                progress: thresholds[index],
                duration: waypoints[index].holdDuration
            )
        }

        return holdAdjustedPathProgress(
            wallProgress: wallProgress,
            holdEvents: holdEvents,
            moveDuration: moveDuration
        )
    }

    static func holdAdjustedPathProgress(
        wallProgress: CGFloat,
        holdEvents: [(progress: CGFloat, duration: CGFloat)],
        moveDuration: CGFloat
    ) -> CGFloat {
        let orderedHolds = holdEvents
            .filter { $0.duration > 0 }
            .sorted { $0.progress < $1.progress }
        let totalHoldTime = orderedHolds.reduce(CGFloat(0)) { $0 + $1.duration }
        guard totalHoldTime > 0, moveDuration > 0 else {
            return wallProgress
        }

        let effectiveDuration = moveDuration + totalHoldTime
        let elapsed = max(0, min(1, wallProgress)) * effectiveDuration
        var timeUsed: CGFloat = 0
        var previousThreshold: CGFloat = 0

        for hold in orderedHolds {
            let threshold = max(previousThreshold, min(1, hold.progress))
            let segmentFraction = threshold - previousThreshold
            let segmentMoveTime = segmentFraction * moveDuration

            if elapsed <= timeUsed + segmentMoveTime {
                let segmentElapsed = elapsed - timeUsed
                let segmentProgress = segmentMoveTime > 0 ? segmentElapsed / segmentMoveTime : 1
                return previousThreshold + segmentFraction * segmentProgress
            }
            timeUsed += segmentMoveTime

            if elapsed <= timeUsed + hold.duration {
                return threshold
            }
            timeUsed += hold.duration
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

    static func collisionRedirectedPosition(
        _ position: CGPoint,
        pathProgress: CGFloat,
        responses: [CollisionResponse]
    ) -> CGPoint {
        guard !responses.isEmpty, pathProgress > 0, pathProgress < 1 else { return position }

        var offset = CGPoint(x: 0, y: 0)
        for response in responses {
            let influence = collisionRedirectInfluence(
                pathProgress: pathProgress,
                collisionProgress: response.progress
            )
            guard influence > 0 else { continue }
            offset.x += response.redirectOffset.x * influence
            offset.y += response.redirectOffset.y * influence
        }

        guard offset.x != 0 || offset.y != 0 else { return position }

        return CGPoint(
            x: max(0, min(CourtConstants.width, position.x + offset.x)),
            y: max(0, min(CourtConstants.height, position.y + offset.y))
        )
    }

    private static func collisionRedirectInfluence(
        pathProgress: CGFloat,
        collisionProgress: CGFloat
    ) -> CGFloat {
        let leadStart = collisionProgress - collisionRedirectLeadProgress
        if pathProgress < leadStart {
            return 0
        }

        if pathProgress <= collisionProgress {
            guard collisionRedirectLeadProgress > 0 else { return 1 }
            return max(0, min(1, (pathProgress - leadStart) / collisionRedirectLeadProgress))
        }

        let recoveryEnd = collisionProgress + collisionRedirectRecoveryProgress
        guard pathProgress < recoveryEnd else { return 0 }
        return max(0, min(1, (recoveryEnd - pathProgress) / collisionRedirectRecoveryProgress))
    }

    private static func collisionContactStartProgress(
        firstSamples: [PathCollisionSample],
        secondSamples: [PathCollisionSample],
        step: Int,
        steps: Int,
        minDistanceSquared: CGFloat
    ) -> CGFloat {
        guard step > 0, step < firstSamples.count, step < secondSamples.count else {
            return CGFloat(step) / CGFloat(max(steps, 1))
        }

        let previousDistanceSquared = squaredDistance(
            from: firstSamples[step - 1].position,
            to: secondSamples[step - 1].position
        )
        let currentDistanceSquared = squaredDistance(
            from: firstSamples[step].position,
            to: secondSamples[step].position
        )

        if previousDistanceSquared < minDistanceSquared {
            return CGFloat(step - 1) / CGFloat(max(steps, 1))
        }

        let crossingRange = previousDistanceSquared - currentDistanceSquared
        guard crossingRange > 0.001 else {
            return CGFloat(step) / CGFloat(max(steps, 1))
        }

        let crossingFraction = max(0, min(1, (previousDistanceSquared - minDistanceSquared) / crossingRange))
        return (CGFloat(step - 1) + crossingFraction) / CGFloat(max(steps, 1))
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
        let cellSize = max(minDistance, 0.1)

        struct GridCell: Hashable {
            let x: Int
            let y: Int
        }

        var grid: [GridCell: [Int]] = [:]
        for (index, athlete) in athletes.enumerated() {
            let cellX = Int(floor(athlete.position.x / cellSize))
            let cellY = Int(floor(athlete.position.y / cellSize))
            let cell = GridCell(x: cellX, y: cellY)
            grid[cell, default: []].append(index)
        }

        var count = 0
        var ids = Set<UUID>()

        for (index, athlete) in athletes.enumerated() {
            let cellX = Int(floor(athlete.position.x / cellSize))
            let cellY = Int(floor(athlete.position.y / cellSize))

            for cx in (cellX - 1)...(cellX + 1) {
                for cy in (cellY - 1)...(cellY + 1) {
                    let cell = GridCell(x: cx, y: cy)
                    if let cellIndices = grid[cell] {
                        for otherIndex in cellIndices {
                            if otherIndex > index {
                                if squaredDistance(from: athlete.position, to: athletes[otherIndex].position) < minDistanceSquared {
                                    count += 1
                                    ids.insert(athlete.id)
                                    ids.insert(athletes[otherIndex].id)
                                }
                            }
                        }
                    }
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
            let thresholds: [CGFloat]
            let nodes: [CGPoint]
            let lengths: [CGFloat]
            let totalLength: CGFloat
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
            let thresholds = !item.waypoints.isEmpty
                ? waypointProgressThresholds(
                    from: item.startPosition,
                    to: item.endPosition,
                    waypoints: item.waypoints
                )
                : []

            let nodes = waypointNodes(from: item.startPosition, to: item.endPosition, waypoints: item.waypoints)
            let lengths = segmentLengths(nodes)
            let totalLength = lengths.reduce(0, +)

            return AthleteTiming(
                item: item,
                transition: transition,
                travel: travel,
                hold: hold,
                effectiveTime: travel + hold,
                thresholds: thresholds,
                nodes: nodes,
                lengths: lengths,
                totalLength: totalLength
            )
        }

        let maxEffectiveTime = timings.max(by: { $0.effectiveTime < $1.effectiveTime })?.effectiveTime ?? 1
        let effectiveCounts = max(counts, 0.5)
        let playbackDurationCounts = timings.reduce(effectiveCounts) { currentMax, timing in
            let durationFraction = maxEffectiveTime > 0 ? timing.effectiveTime / maxEffectiveTime : 1
            let activeDurationCounts = durationFraction * effectiveCounts
            return max(currentMax, max(0, timing.item.moveDelay) + activeDurationCounts)
        }

        // Sample each athlete's position at each time step
        let sampledPositions: [[CGPoint]] = timings.map { timing in
            var positions: [CGPoint] = []
            for step in 0...steps {
                let progress = CGFloat(step) / CGFloat(steps)
                let durationFraction = maxEffectiveTime > 0 ? timing.effectiveTime / maxEffectiveTime : 1
                let activeDurationCounts = durationFraction * effectiveCounts
                let athleteProgress = delayedMovementProgress(
                    timelineProgress: progress,
                    moveDelayCounts: timing.item.moveDelay,
                    moveDurationCounts: activeDurationCounts,
                    playbackDurationCounts: playbackDurationCounts
                )

                let effectiveProgress: CGFloat
                if !timing.item.waypoints.isEmpty && timing.hold > 0 {
                    let moveDuration = activeDurationCounts * (timing.travel / max(timing.effectiveTime, 0.001))
                    effectiveProgress = holdAdjustedPathProgress(
                        wallProgress: athleteProgress,
                        waypoints: timing.item.waypoints,
                        thresholds: timing.thresholds,
                        moveDuration: moveDuration,
                        totalHoldTime: timing.hold
                    )
                } else {
                    effectiveProgress = athleteProgress
                }

                let position: CGPoint
                if !timing.item.waypoints.isEmpty {
                    position = interpolateWaypointPath(
                        nodes: timing.nodes,
                        lengths: timing.lengths,
                        totalLength: timing.totalLength,
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
        let cellSize = max(minDistance, 0.1)

        struct GridCell: Hashable {
            let x: Int
            let y: Int
        }

        var collisionIDs = Set<UUID>()
        var seenPairs = Set<Int64>()

        // Skip first and last steps — static proximity is already
        // handled by collisionSummary; only flag mid-transition crossings.
        for step in 1..<steps {
            var grid: [GridCell: [Int]] = [:]
            for index in 0..<paths.count {
                let pos = sampledPositions[index][step]
                let cellX = Int(floor(pos.x / cellSize))
                let cellY = Int(floor(pos.y / cellSize))
                let cell = GridCell(x: cellX, y: cellY)
                grid[cell, default: []].append(index)
            }

            for index in 0..<paths.count {
                let pos = sampledPositions[index][step]
                let cellX = Int(floor(pos.x / cellSize))
                let cellY = Int(floor(pos.y / cellSize))

                for cx in (cellX - 1)...(cellX + 1) {
                    for cy in (cellY - 1)...(cellY + 1) {
                        let cell = GridCell(x: cx, y: cy)
                        if let cellIndices = grid[cell] {
                            for otherIndex in cellIndices {
                                if otherIndex > index {
                                    let packedKey = Int64(index) << 32 | Int64(otherIndex)
                                    if !seenPairs.contains(packedKey) {
                                        if squaredDistance(from: pos, to: sampledPositions[otherIndex][step]) < minDistanceSquared {
                                            seenPairs.insert(packedKey)
                                            collisionIDs.insert(paths[index].athleteID)
                                            collisionIDs.insert(paths[otherIndex].athleteID)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        return collisionIDs
    }

    static func findPathCollisionDetails(
        paths: [TransitionPathRenderItem],
        counts: CGFloat = 8,
        steps: Int = 60,
        minDistance: CGFloat = CourtConstants.collisionDistance
    ) -> (ids: Set<UUID>, markers: [CGPoint], markerProgresses: [CGFloat], responses: [UUID: [CollisionResponse]]) {
        guard paths.count > 1 else { return ([], [], [], [:]) }

        let timings: [(travel: CGFloat, hold: CGFloat, effectiveTime: CGFloat, thresholds: [CGFloat], nodes: [CGPoint], lengths: [CGFloat], totalLength: CGFloat, item: TransitionPathRenderItem)] = paths.map { item in
            let transition = AthleteTransition(
                athleteID: item.athleteID,
                moveDelay: item.moveDelay,
                pathControlPoint: item.controlPoint,
                pathWaypoints: item.waypoints
            )
            let travel = travelDistance(from: item.startPosition, to: item.endPosition, transition: transition)
            let hold = item.waypoints.reduce(CGFloat(0)) { $0 + $1.holdCounts }
            let thresholds = !item.waypoints.isEmpty
                ? waypointProgressThresholds(
                    from: item.startPosition,
                    to: item.endPosition,
                    waypoints: item.waypoints
                )
                : []
            let nodes = waypointNodes(from: item.startPosition, to: item.endPosition, waypoints: item.waypoints)
            let lengths = segmentLengths(nodes)
            let totalLength = lengths.reduce(0, +)
            return (travel, hold, travel + hold, thresholds, nodes, lengths, totalLength, item)
        }

        let maxEffectiveTime = timings.max(by: { $0.effectiveTime < $1.effectiveTime })?.effectiveTime ?? 1
        let effectiveCounts = max(counts, 0.5)
        let playbackDurationCounts = timings.reduce(effectiveCounts) { currentMax, timing in
            let durationFraction = maxEffectiveTime > 0 ? timing.effectiveTime / maxEffectiveTime : 1
            let activeDurationCounts = durationFraction * effectiveCounts
            return max(currentMax, max(0, timing.item.moveDelay) + activeDurationCounts)
        }

        let sampledPaths: [[PathCollisionSample]] = timings.map { timing in
            var samples: [PathCollisionSample] = []
            samples.reserveCapacity(steps + 1)
            for step in 0...steps {
                let progress = CGFloat(step) / CGFloat(steps)
                let durationFraction = maxEffectiveTime > 0 ? timing.effectiveTime / maxEffectiveTime : 1
                let activeDurationCounts = durationFraction * effectiveCounts
                let athleteProgress = delayedMovementProgress(
                    timelineProgress: progress,
                    moveDelayCounts: timing.item.moveDelay,
                    moveDurationCounts: activeDurationCounts,
                    playbackDurationCounts: playbackDurationCounts
                )

                let effectiveProgress: CGFloat
                if !timing.item.waypoints.isEmpty && timing.hold > 0 {
                    let moveDuration = activeDurationCounts * (timing.travel / max(timing.effectiveTime, 0.001))
                    effectiveProgress = holdAdjustedPathProgress(
                        wallProgress: athleteProgress,
                        waypoints: timing.item.waypoints,
                        thresholds: timing.thresholds,
                        moveDuration: moveDuration,
                        totalHoldTime: timing.hold
                    )
                } else {
                    effectiveProgress = athleteProgress
                }

                let position: CGPoint
                if !timing.item.waypoints.isEmpty {
                    position = interpolateWaypointPath(
                        nodes: timing.nodes,
                        lengths: timing.lengths,
                        totalLength: timing.totalLength,
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
                samples.append(PathCollisionSample(position: position, pathProgress: effectiveProgress))
            }
            return samples
        }

        let minDistanceSquared = minDistance * minDistance
        let cellSize = max(minDistance, 0.1)

        struct GridCell: Hashable {
            let x: Int
            let y: Int
        }

        var collisionIDs = Set<UUID>()
        var markers: [CGPoint] = []
        var markerProgresses: [CGFloat] = []
        var responses: [UUID: [CollisionResponse]] = [:]
        var seenPairs = Set<Int64>()

        for step in 1..<steps {
            var grid: [GridCell: [Int]] = [:]
            for index in 0..<paths.count {
                let pos = sampledPaths[index][step].position
                let cellX = Int(floor(pos.x / cellSize))
                let cellY = Int(floor(pos.y / cellSize))
                let cell = GridCell(x: cellX, y: cellY)
                grid[cell, default: []].append(index)
            }

            for index in 0..<paths.count {
                let a = sampledPaths[index][step].position
                let cellX = Int(floor(a.x / cellSize))
                let cellY = Int(floor(a.y / cellSize))

                for cx in (cellX - 1)...(cellX + 1) {
                    for cy in (cellY - 1)...(cellY + 1) {
                        let cell = GridCell(x: cx, y: cy)
                        if let cellIndices = grid[cell] {
                            for otherIndex in cellIndices {
                                if otherIndex > index {
                                    let packedKey = Int64(index) << 32 | Int64(otherIndex)
                                    if !seenPairs.contains(packedKey) {
                                        let b = sampledPaths[otherIndex][step].position
                                        let currentDistanceSquared = squaredDistance(from: a, to: b)
                                        if currentDistanceSquared < minDistanceSquared {
                                            seenPairs.insert(packedKey)
                                            collisionIDs.insert(paths[index].athleteID)
                                            collisionIDs.insert(paths[otherIndex].athleteID)
                                            let midpoint = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                                            if !markers.contains(where: { squaredDistance(from: $0, to: midpoint) < 1 }) {
                                                markers.append(midpoint)
                                                let contactStartProgress = collisionContactStartProgress(
                                                    firstSamples: sampledPaths[index],
                                                    secondSamples: sampledPaths[otherIndex],
                                                    step: step,
                                                    steps: steps,
                                                    minDistanceSquared: minDistanceSquared
                                                )
                                                markerProgresses.append(
                                                    max(0, contactStartProgress - collisionPulseLeadProgress)
                                                )
                                            }

                                            if timings[index].travel > collisionResponseMinimumTravel {
                                                responses[paths[index].athleteID, default: []].append(
                                                    CollisionResponse(
                                                        progress: sampledPaths[index][step].pathProgress,
                                                        holdCounts: collisionPenaltyCounts,
                                                        redirectOffset: collisionRedirectOffset(
                                                            samples: sampledPaths[index],
                                                            step: step,
                                                            fallbackStart: paths[index].startPosition,
                                                            fallbackEnd: paths[index].endPosition
                                                        )
                                                    )
                                                )
                                            }

                                            if timings[otherIndex].travel > collisionResponseMinimumTravel {
                                                responses[paths[otherIndex].athleteID, default: []].append(
                                                    CollisionResponse(
                                                        progress: sampledPaths[otherIndex][step].pathProgress,
                                                        holdCounts: collisionPenaltyCounts,
                                                        redirectOffset: collisionRedirectOffset(
                                                            samples: sampledPaths[otherIndex],
                                                            step: step,
                                                            fallbackStart: paths[otherIndex].startPosition,
                                                            fallbackEnd: paths[otherIndex].endPosition
                                                        )
                                                    )
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        for athleteID in responses.keys {
            responses[athleteID] = responses[athleteID]?.sorted { $0.progress < $1.progress }
        }

        return (collisionIDs, markers, markerProgresses, responses)
    }

    static func findPathCollisionMarkers(
        paths: [TransitionPathRenderItem],
        counts: CGFloat = 8,
        steps: Int = 60,
        minDistance: CGFloat = CourtConstants.collisionDistance
    ) -> (ids: Set<UUID>, markers: [CGPoint]) {
        let details = findPathCollisionDetails(
            paths: paths,
            counts: counts,
            steps: steps,
            minDistance: minDistance
        )
        return (details.ids, details.markers)
    }

    private static func collisionRedirectOffset(
        samples: [PathCollisionSample],
        step: Int,
        fallbackStart: CGPoint,
        fallbackEnd: CGPoint
    ) -> CGPoint {
        guard !samples.isEmpty else {
            return CGPoint(x: 0, y: collisionRedirectDistance)
        }

        let previous = samples[max(0, step - 1)].position
        let next = samples[min(samples.count - 1, step + 1)].position

        var dx = next.x - previous.x
        var dy = next.y - previous.y
        var length = hypot(dx, dy)

        if length < 0.001 {
            dx = fallbackEnd.x - fallbackStart.x
            dy = fallbackEnd.y - fallbackStart.y
            length = hypot(dx, dy)
        }

        guard length >= 0.001 else {
            return CGPoint(x: 0, y: collisionRedirectDistance)
        }

        let scale = collisionRedirectDistance / length
        return CGPoint(x: -dy * scale, y: dx * scale)
    }
}

// MARK: - Transition Player

@MainActor
final class TransitionPlayer: ObservableObject {
    @Published var isPlaying = false
    @Published var isLooping = false
    @Published var progress: CGFloat = 0
    @Published var currentAthletes: [RenderedAthlete]
    @Published var speed: CGFloat = PathCalculations.defaultPlaybackSpeed
    @Published var startAthletes: [RenderedAthlete] {
        didSet { guard !isBatchRefreshing else { return }; updateTimingCache() }
    }
    @Published var endAthletes: [RenderedAthlete] {
        didSet {
            guard !isBatchRefreshing else { return }
            updateEndLookup()
            updateTimingCache()
        }
    }
    @Published var transitionSpec: TransitionSpec {
        didSet {
            guard !isBatchRefreshing else { return }
            updateTransitionLookup()
            updateTimingCache()
        }
    }

    var onComplete: (() -> Void)?

    var duration: TimeInterval {
        didSet { guard !isBatchRefreshing else { return }; transitionSpec.duration = duration }
    }

    var counts: TimeInterval {
        get { duration }
        set { duration = newValue }
    }

    private var endLookup: [UUID: RenderedAthlete] = [:]
    private var transitionLookup: [UUID: AthleteTransition] = [:]

    // ⚡ Bolt: Cache timing calculations outside the animation loop to avoid O(N) operations per frame.
    private var timingCache: [UUID: (endAthlete: RenderedAthlete, transition: AthleteTransition, travel: CGFloat, hold: CGFloat, effectiveTime: CGFloat, thresholds: [CGFloat], nodes: [CGPoint], lengths: [CGFloat], totalLength: CGFloat)] = [:]
    private var maxEffectiveTime: CGFloat = 1
    private var playbackDurationCounts: CGFloat = 1

    // ⚡ Bolt: Cache path generation and spatial collisions outside the animation loop
    private(set) var cachedTransitionPaths: [TransitionPathRenderItem] = []
    private(set) var cachedPathCollisionIDs: Set<UUID> = []
    private(set) var cachedPathCollisionMarkers: [CGPoint] = []
    private(set) var cachedPathCollisionMarkerProgresses: [CGFloat] = []
    private var collisionResponseCache: [UUID: [PathCalculations.CollisionResponse]] = [:]

    private var animationTimer: AnimationTimer?
    private var idleResetTask: Task<Void, Never>?

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
        updateEndLookup()
        updateTransitionLookup()
        updateTimingCache()
    }

    private func updateEndLookup() {
        endLookup = endAthletes.reduce(into: [UUID: RenderedAthlete]()) { result, athlete in
            if result[athlete.id] == nil {
                result[athlete.id] = athlete
            }
        }
    }

    private func updateTransitionLookup() {
        transitionLookup = transitionSpec.athleteTransitions.reduce(into: [UUID: AthleteTransition]()) { result, transition in
            if result[transition.athleteID] == nil {
                result[transition.athleteID] = transition
            }
        }
    }

    private func updateTimingCache() {
        var newTimingCache: [UUID: (endAthlete: RenderedAthlete, transition: AthleteTransition, travel: CGFloat, hold: CGFloat, effectiveTime: CGFloat, thresholds: [CGFloat], nodes: [CGPoint], lengths: [CGFloat], totalLength: CGFloat)] = [:]
        newTimingCache.reserveCapacity(startAthletes.count)

        let newMaxEffectiveTime = startAthletes.compactMap { athlete -> CGFloat? in
            guard let endAthlete = endLookup[athlete.id] else { return nil }
            let transition = transitionLookup[athlete.id] ?? AthleteTransition(athleteID: athlete.id)
            let travel = PathCalculations.travelDistance(
                from: athlete.position,
                to: endAthlete.position,
                transition: transition
            )
            let hold = transition.pathWaypoints.reduce(CGFloat(0)) { $0 + $1.holdCounts }
            let effectiveTime = travel + hold
            let thresholds = !transition.pathWaypoints.isEmpty
                ? PathCalculations.waypointProgressThresholds(
                    from: athlete.position,
                    to: endAthlete.position,
                    waypoints: transition.pathWaypoints
                )
                : []

            let nodes = PathCalculations.waypointNodes(from: athlete.position, to: endAthlete.position, waypoints: transition.pathWaypoints)
            let lengths = PathCalculations.segmentLengths(nodes)
            let totalLength = lengths.reduce(0, +)

            newTimingCache[athlete.id] = (endAthlete, transition, travel, hold, effectiveTime, thresholds, nodes, lengths, totalLength)
            return effectiveTime
        }.max() ?? 1

        self.timingCache = newTimingCache
        self.maxEffectiveTime = newMaxEffectiveTime
        updatePathCaches()

        let finalMaxEffectiveTime = newTimingCache.map { athleteID, cached in
            let collisionHold = collisionResponseCache[athleteID]?.reduce(CGFloat(0)) { $0 + $1.holdCounts } ?? 0
            return cached.effectiveTime + collisionHold
        }.max() ?? newMaxEffectiveTime
        self.maxEffectiveTime = finalMaxEffectiveTime

        let effectiveCounts = max(CGFloat(counts), 0.5)
        self.playbackDurationCounts = newTimingCache.reduce(effectiveCounts) { currentMax, entry in
            let athleteID = entry.key
            let cached = entry.value
            let collisionHold = collisionResponseCache[athleteID]?.reduce(CGFloat(0)) { $0 + $1.holdCounts } ?? 0
            let effectiveTime = cached.effectiveTime + collisionHold
            let durationFraction = finalMaxEffectiveTime > 0 ? effectiveTime / finalMaxEffectiveTime : 1
            let activeDurationCounts = durationFraction * effectiveCounts
            return max(currentMax, max(0, cached.transition.moveDelayCounts) + activeDurationCounts)
        }
    }

    private func updatePathCaches() {
        cachedTransitionPaths = startAthletes.compactMap { athlete in
            guard let cached = timingCache[athlete.id] else { return nil }
            return TransitionPathRenderItem(
                athleteID: athlete.id,
                startPosition: athlete.position,
                endPosition: cached.endAthlete.position,
                controlPoint: cached.transition.pathControlPoint,
                waypoints: cached.transition.pathWaypoints,
                moveDelay: cached.transition.moveDelay
            )
        }

        let collisions = PathCalculations.findPathCollisionDetails(
            paths: cachedTransitionPaths,
            counts: CGFloat(counts)
        )
        cachedPathCollisionIDs = collisions.ids
        cachedPathCollisionMarkers = collisions.markers
        cachedPathCollisionMarkerProgresses = collisions.markerProgresses
        collisionResponseCache = collisions.responses
    }

    deinit {
        animationTimer?.invalidate()
    }

    private var isBatchRefreshing = false

    func refresh(
        startAthletes: [RenderedAthlete],
        endAthletes: [RenderedAthlete],
        transitionSpec: TransitionSpec
    ) {
        // Batch property updates to avoid cascading didSet → updateTimingCache()
        // which previously ran findPathCollisionIDs 3-4 times per refresh.
        isBatchRefreshing = true
        self.startAthletes = startAthletes
        self.endAthletes = endAthletes
        self.transitionSpec = transitionSpec
        duration = transitionSpec.duration
        isBatchRefreshing = false
        updateEndLookup()
        updateTransitionLookup()
        updateTimingCache()
        updateAthletesForProgress()
    }

    func play() {
        guard !isPlaying else { return }
        cancelIdleReset()
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
        scheduleIdleReset()
    }

    func reset() {
        cancelIdleReset()
        pause()
        progress = 0
        updateAthletesForProgress()
    }

    func seek(to newProgress: CGFloat) {
        cancelIdleReset()
        progress = max(0, min(1, newProgress))
        updateAthletesForProgress()
        if !isPlaying { scheduleIdleReset() }
    }

    private func scheduleIdleReset() {
        cancelIdleReset()
        guard progress > 0 else { return }
        idleResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.seek(to: 0)
        }
    }

    private func cancelIdleReset() {
        idleResetTask?.cancel()
        idleResetTask = nil
    }

    func setSpeed(_ newSpeed: CGFloat) {
        speed = newSpeed
    }

    private func update() {
        guard isPlaying else { return }
        let delta = CGFloat(1.0 / 60.0) * speed / max(playbackDurationCounts, 0.5)
        progress = min(1.0, progress + delta)
        updateAthletesForProgress()
        if progress >= 1.0 {
            if isLooping {
                progress = 0
            } else {
                pause()
                onComplete?()
            }
        }
    }

    private func updateAthletesForProgress() {
        // ⚡ Bolt: Removed redundant O(N) lookup dictionary allocations per frame. Used cached lookups.

        currentAthletes = startAthletes.map { athlete in
            guard let cached = timingCache[athlete.id] else { return athlete }
            let endAthlete = cached.endAthlete
            let transition = cached.transition
            let travel = cached.travel
            let hold = cached.hold
            let collisionResponses = collisionResponseCache[athlete.id] ?? []
            let collisionHold = collisionResponses.reduce(CGFloat(0)) { $0 + $1.holdCounts }
            let effectiveTime = cached.effectiveTime + collisionHold

            let durationFraction = maxEffectiveTime > 0 ? effectiveTime / maxEffectiveTime : 1
            let activeDurationCounts = durationFraction * max(CGFloat(counts), 0.5)
            let athleteProgress = PathCalculations.delayedMovementProgress(
                timelineProgress: progress,
                moveDelayCounts: transition.moveDelayCounts,
                moveDurationCounts: activeDurationCounts,
                playbackDurationCounts: playbackDurationCounts
            )

            let effectiveProgress: CGFloat
            if hold > 0 || collisionHold > 0 {
                var holdEvents: [(progress: CGFloat, duration: CGFloat)] = []
                if !transition.pathWaypoints.isEmpty {
                    for index in transition.pathWaypoints.indices {
                        holdEvents.append(
                            (
                                progress: cached.thresholds[index],
                                duration: transition.pathWaypoints[index].holdCounts
                            )
                        )
                    }
                }
                holdEvents.append(
                    contentsOf: collisionResponses.map {
                        (progress: $0.progress, duration: $0.holdCounts)
                    }
                )

                let moveDuration = activeDurationCounts * (travel / max(effectiveTime, 0.001))
                effectiveProgress = PathCalculations.holdAdjustedPathProgress(
                    wallProgress: athleteProgress,
                    holdEvents: holdEvents,
                    moveDuration: moveDuration
                )
            } else {
                effectiveProgress = athleteProgress
            }

            let nextPosition: CGPoint
            if !transition.pathWaypoints.isEmpty {
                nextPosition = PathCalculations.interpolateWaypointPath(
                    nodes: cached.nodes,
                    lengths: cached.lengths,
                    totalLength: cached.totalLength,
                    waypoints: transition.pathWaypoints,
                    progress: effectiveProgress
                )
            } else if let controlPoint = transition.pathControlPoint {
                nextPosition = PathCalculations.quadraticBezierPoint(
                    from: athlete.position,
                    control: controlPoint,
                    to: endAthlete.position,
                    t: effectiveProgress
                )
            } else {
                nextPosition = CGPoint(
                    x: athlete.position.x + (endAthlete.position.x - athlete.position.x) * effectiveProgress,
                    y: athlete.position.y + (endAthlete.position.y - athlete.position.y) * effectiveProgress
                )
            }

            let redirectedPosition = PathCalculations.collisionRedirectedPosition(
                nextPosition,
                pathProgress: effectiveProgress,
                responses: collisionResponses
            )

            return RenderedAthlete(
                id: athlete.id,
                label: athlete.label,
                role: athlete.role,
                position: redirectedPosition
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
            let newPlayer = TransitionPlayer(
                startAthletes: startAthletes,
                endAthletes: endAthletes,
                transitionSpec: transitionSpec
            )
            newPlayer.onComplete = { [weak newPlayer] in
                newPlayer?.seek(to: 0)
            }
            self.player = newPlayer
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

// MARK: - Routine Player

struct RoutineSegment {
    let startAthletes: [RenderedAthlete]
    let endAthletes: [RenderedAthlete]
    let spec: TransitionSpec
    let formationName: String
}

@MainActor
final class RoutinePlayer: ObservableObject {
    @Published var currentAthletes: [RenderedAthlete] = []
    @Published var progress: CGFloat = 0
    @Published var isPlaying = false
    @Published var speed: CGFloat = PathCalculations.defaultPlaybackSpeed
    @Published var currentSegmentIndex: Int = 0
    @Published var currentFormationName: String = ""
    @Published var showTrail = false
    @Published var trailPositions: [UUID: [CGPoint]] = [:]
    @Published var segmentProgress: CGFloat = 0

    let segments: [RoutineSegment]
    let segmentMarkers: [CGFloat]
    var segmentCount: Int { segments.count }

    private var player: TransitionPlayer?
    private var athletesSink: AnyCancellable?
    private var isInGap = false
    private var gapWorkItem: DispatchWorkItem?
    private let trailLength = 14

    // Cumulative duration fractions for proportional timeline
    private let cumulativeFractions: [CGFloat]
    private let totalDuration: CGFloat

    init(store: RoutineStore) {
        let formations = store.routine.formations
        var segs: [RoutineSegment] = []

        for i in 0..<(formations.count - 1) {
            let from = formations[i]
            let to = formations[i + 1]
            segs.append(RoutineSegment(
                startAthletes: store.renderedAthletes(for: from),
                endAthletes: store.renderedAthletes(for: to),
                spec: store.transitionSpec(for: from.id, to: to.id),
                formationName: from.name
            ))
        }

        self.segments = segs

        // Compute cumulative duration fractions
        let total = segs.reduce(CGFloat(0)) { $0 + max(CGFloat($1.spec.duration), 0.5) }
        self.totalDuration = total
        var cumulative: [CGFloat] = []
        var running: CGFloat = 0
        for seg in segs {
            running += max(CGFloat(seg.spec.duration), 0.5)
            cumulative.append(running / total)
        }
        self.cumulativeFractions = cumulative

        // Segment markers are at boundaries between segments (not including 0 or 1)
        self.segmentMarkers = Array(cumulative.dropLast())

        if let first = segs.first {
            self.currentAthletes = first.startAthletes
            self.currentFormationName = first.formationName
        }
    }

    func play() {
        guard !segments.isEmpty else { return }
        if progress >= 1.0 {
            progress = 0
            currentSegmentIndex = 0
            loadSegment(at: 0)
        }
        isPlaying = true
        if player == nil {
            loadSegment(at: currentSegmentIndex)
        }
        player?.play()
    }

    func pause() {
        isPlaying = false
        player?.pause()
    }

    func reset() {
        pause()
        cancelGap()
        progress = 0
        currentSegmentIndex = 0
        trailPositions = [:]
        if let first = segments.first {
            currentAthletes = first.startAthletes
            currentFormationName = first.formationName
        }
    }

    func seek(to globalProgress: CGFloat) {
        cancelGap()
        let clamped = max(0, min(1, globalProgress))
        progress = clamped

        // Find which segment this falls in
        let segIndex = segmentIndex(for: clamped)
        let localProgress = localProgress(for: clamped, inSegment: segIndex)

        if currentSegmentIndex != segIndex || player == nil {
            currentSegmentIndex = segIndex
            if segIndex < segments.count {
                currentFormationName = segments[segIndex].formationName
            }
            trailPositions = [:]
            loadSegment(at: segIndex)
        }

        player?.seek(to: localProgress)
    }

    func setSpeed(_ newSpeed: CGFloat) {
        speed = newSpeed
        player?.speed = newSpeed
    }

    func jumpToNextSegment() {
        let wasPlaying = isPlaying
        cancelGap()
        let nextIndex = (currentSegmentIndex + 1) % segments.count
        currentSegmentIndex = nextIndex
        trailPositions = [:]
        loadSegment(at: nextIndex)

        // Set progress to segment start
        let segStart: CGFloat = nextIndex > 0 ? cumulativeFractions[nextIndex - 1] : 0
        progress = segStart

        player?.seek(to: 0)
        if wasPlaying {
            player?.play()
        }
    }

    // MARK: - Private

    private func loadSegment(at index: Int) {
        guard index < segments.count else { return }
        let seg = segments[index]
        currentFormationName = seg.formationName

        if let player {
            if player.transitionSpec.id != seg.spec.id {
                player.refresh(
                    startAthletes: seg.startAthletes,
                    endAthletes: seg.endAthletes,
                    transitionSpec: seg.spec
                )
                player.seek(to: 0)
            }
            player.speed = speed
        } else {
            let newPlayer = TransitionPlayer(
                startAthletes: seg.startAthletes,
                endAthletes: seg.endAthletes,
                transitionSpec: seg.spec
            )
            newPlayer.speed = speed
            self.player = newPlayer
            subscribeToPlayer(newPlayer)
        }

        player?.onComplete = { [weak self] in
            self?.handleSegmentComplete()
        }
    }

    private func subscribeToPlayer(_ player: TransitionPlayer) {
        athletesSink = player.$currentAthletes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] athletes in
                guard let self else { return }
                self.currentAthletes = athletes
                self.updateTrail(athletes: athletes)
                self.updateGlobalProgress()
            }
    }

    private func handleSegmentComplete() {
        let nextIndex = currentSegmentIndex + 1
        guard nextIndex < segments.count else {
            isPlaying = false
            progress = 1.0
            return
        }

        isInGap = true
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isPlaying else {
                self?.isInGap = false
                return
            }
            self.isInGap = false
            self.currentSegmentIndex = nextIndex
            self.loadSegment(at: nextIndex)
            self.player?.play()
        }
        gapWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private func cancelGap() {
        gapWorkItem?.cancel()
        gapWorkItem = nil
        isInGap = false
    }

    private func updateGlobalProgress() {
        guard !isInGap, let player else { return }
        let localP = player.progress
        segmentProgress = localP

        let segStart: CGFloat = currentSegmentIndex > 0 ? cumulativeFractions[currentSegmentIndex - 1] : 0
        let segEnd = cumulativeFractions[currentSegmentIndex]
        progress = segStart + localP * (segEnd - segStart)
    }

    private func updateTrail(athletes: [RenderedAthlete]) {
        for athlete in athletes {
            var positions = trailPositions[athlete.id] ?? []
            positions.append(athlete.position)
            if positions.count > trailLength {
                positions.removeFirst(positions.count - trailLength)
            }
            trailPositions[athlete.id] = positions
        }
    }

    private func segmentIndex(for globalProgress: CGFloat) -> Int {
        if globalProgress >= 1.0 { return max(0, segments.count - 1) }
        for (i, fraction) in cumulativeFractions.enumerated() {
            if globalProgress < fraction { return i }
        }
        return max(0, segments.count - 1)
    }

    private func localProgress(for globalProgress: CGFloat, inSegment index: Int) -> CGFloat {
        let segStart: CGFloat = index > 0 ? cumulativeFractions[index - 1] : 0
        let segEnd = cumulativeFractions[index]
        let segWidth = segEnd - segStart
        guard segWidth > 0 else { return 0 }
        return max(0, min(1, (globalProgress - segStart) / segWidth))
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
