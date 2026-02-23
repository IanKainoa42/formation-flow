import Foundation
import SwiftUI

#if os(iOS)
    import UIKit
#else
    import AppKit
#endif

// MARK: - Constants

enum CourtConstants {
    static let width: CGFloat = 52  // feet (standard cheerleading court)
    static let height: CGFloat = 30  // feet
    static let cellSize: CGFloat = 12  // pixels per foot
    static let collisionDistance: CGFloat = 2.0  // feet
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

// MARK: - Persistence Manager

class PersistenceManager: ObservableObject {
    static let shared = PersistenceManager()

    private let formationsKey = "formations"
    private var saveWorkItem: DispatchWorkItem?

    @Published var formations: [Formation] = [] {
        didSet { scheduleSave() }
    }

    init() {
        loadFormations()
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let snapshot = formations
        let key = formationsKey
        let item = DispatchWorkItem {
            guard let encoded = try? JSONEncoder().encode(snapshot) else { return }
            UserDefaults.standard.set(encoded, forKey: key)
        }
        saveWorkItem = item
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    private func loadFormations() {
        if let data = UserDefaults.standard.data(forKey: formationsKey) {
            do {
                formations = try JSONDecoder().decode([Formation].self, from: data)
            } catch {
                print("Error loading formations: \(error)")
                formations = []
            }
        } else {
            formations = []
        }
    }

    func addFormation(_ formation: Formation) {
        formations.append(formation)
    }

    func deleteFormation(id: UUID) {
        formations.removeAll { $0.id == id }
    }

    func updateFormation(_ formation: Formation) {
        if let index = formations.firstIndex(where: { $0.id == formation.id }) {
            formations[index] = formation
        }
    }

    func moveFormation(from source: IndexSet, to destination: Int) {
        formations.move(fromOffsets: source, toOffset: destination)
    }
}

// MARK: - Data Models

struct Athlete: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var label: String  // "A1", "B2", etc.
    var position: CGPoint  // x, y on floor (in feet)
    var role: AthleteRole = .base
    var moveTiming: CGFloat = 0.0  // seconds delay before this athlete starts moving
    var pathControlPoint: CGPoint?  // Optional relative or absolute bezier control point

    static func == (lhs: Athlete, rhs: Athlete) -> Bool {
        lhs.id == rhs.id && lhs.label == rhs.label && lhs.position.x == rhs.position.x
            && lhs.position.y == rhs.position.y && lhs.role == rhs.role
            && lhs.moveTiming == rhs.moveTiming && lhs.pathControlPoint == rhs.pathControlPoint
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
    }

    enum CodingKeys: String, CodingKey {
        case id, label, role, moveTiming
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

    // Sample formations for POC
    static func sample() -> Formation {
        var formation = Formation()
        formation.name = "Opening Formation"
        formation.athletes = [
            Athlete(label: "A1", position: CGPoint(x: 10, y: 10), role: .flyer),
            Athlete(label: "A2", position: CGPoint(x: 10, y: 15), role: .base),
            Athlete(label: "A3", position: CGPoint(x: 10, y: 20), role: .base),
            Athlete(label: "B1", position: CGPoint(x: 26, y: 10), role: .flyer),
            Athlete(label: "B2", position: CGPoint(x: 26, y: 15), role: .base),
            Athlete(label: "B3", position: CGPoint(x: 26, y: 20), role: .base),
            Athlete(label: "C1", position: CGPoint(x: 42, y: 10), role: .flyer),
            Athlete(label: "C2", position: CGPoint(x: 42, y: 15), role: .base),
        ]
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
            let x: CGFloat
            let y: CGFloat

            if let c = control {
                // Quadratic bezier interpolation
                let u = 1.0 - t
                let tt = t * t
                let uu = u * u
                let ut2 = 2.0 * u * t

                x = uu * from.x + ut2 * c.x + tt * to.x
                y = uu * from.y + ut2 * c.y + tt * to.y
            } else {
                // Linear interpolation
                x = from.x + (to.x - from.x) * t
                y = from.y + (to.y - from.y) * t
            }

            path.append(CGPoint(x: x, y: y))
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

    /// Find the indices of athletes whose transition paths cross within minDistance
    static func findPathCollisionIndices(
        start: Formation, end: Formation, steps: Int = 20, minDistance: CGFloat = 2.0
    ) -> Set<Int> {
        let count = min(start.athletes.count, end.athletes.count)
        var collidingIndices = Set<Int>()
        var paths: [[CGPoint]] = []
        for i in 0..<count {
            paths.append(
                athletePath(
                    from: start.athletes[i].position,
                    to: end.athletes[i].position,
                    control: start.athletes[i].pathControlPoint,
                    steps: steps
                ))
        }
        let minDistanceSq = minDistance * minDistance
        for i in 0..<count {
            for j in (i + 1)..<count {
                for step in 0..<min(paths[i].count, paths[j].count) {
                    if squaredDistance(from: paths[i][step], to: paths[j][step]) < minDistanceSq {
                        collidingIndices.insert(i)
                        collidingIndices.insert(j)
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

    let endFormation: Formation
    var duration: TimeInterval
    private var animationTimer: AnimationTimer?

    init(from start: Formation, to end: Formation, duration: TimeInterval = 2.0) {
        self.startFormation = start
        self.endFormation = end
        self.duration = duration
        self.currentFormation = start
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

        for i in 0..<startFormation.athletes.count {
            if i < endFormation.athletes.count {
                let startAthlete = startFormation.athletes[i]
                let endAthlete = endFormation.athletes[i]

                let timingOffset = min(0.99, startAthlete.moveTiming / CGFloat(duration))
                let athleteProgress = min(
                    1.0, max(0, progress - timingOffset) / (1.0 - timingOffset))

                let newX: CGFloat
                let newY: CGFloat
                if let c = startAthlete.pathControlPoint {
                    let u = 1.0 - athleteProgress
                    let tt = athleteProgress * athleteProgress
                    let uu = u * u
                    let ut2 = 2.0 * u * athleteProgress

                    newX = uu * startAthlete.position.x + ut2 * c.x + tt * endAthlete.position.x
                    newY = uu * startAthlete.position.y + ut2 * c.y + tt * endAthlete.position.y
                } else {
                    newX =
                        startAthlete.position.x + (endAthlete.position.x - startAthlete.position.x)
                        * athleteProgress
                    newY =
                        startAthlete.position.y + (endAthlete.position.y - startAthlete.position.y)
                        * athleteProgress
                }

                var athlete = startAthlete
                athlete.position = CGPoint(x: newX, y: newY)
                newFormation.athletes.append(athlete)
            } else {
                newFormation.athletes.append(startFormation.athletes[i])
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
}
