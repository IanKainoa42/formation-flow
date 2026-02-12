import Foundation

// MARK: - Data Models

struct Athlete: Codable, Identifiable {
    let id: UUID
    var label: String          // "A1", "B2", etc.
    var position: CGPoint      // x, y on floor
    var role: String = "base"  // "flyer", "base", "spotter", etc.
    
    enum CodingKeys: String, CodingKey {
        case id, label, role
        case positionX = "positionX"
        case positionY = "positionY"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(role, forKey: .role)
        try container.encode(position.x, forKey: .positionX)
        try container.encode(position.y, forKey: .positionY)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        role = try container.decode(String.self, forKey: .role)
        let x = try container.decode(CGFloat.self, forKey: .positionX)
        let y = try container.decode(CGFloat.self, forKey: .positionY)
        position = CGPoint(x: x, y: y)
    }
    
    init(id: UUID = UUID(), label: String, position: CGPoint, role: String = "base") {
        self.id = id
        self.label = label
        self.position = position
        self.role = role
    }
}

struct Formation: Codable {
    var id: UUID = UUID()
    var name: String = "Untitled Formation"
    var athletes: [Athlete] = []
    var gridSize: CGSize = CGSize(width: 52, height: 30)  // feet (standard cheerleading court)
    
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
            Athlete(label: "A1", position: CGPoint(x: 10, y: 10), role: "flyer"),
            Athlete(label: "A2", position: CGPoint(x: 10, y: 15), role: "base"),
            Athlete(label: "A3", position: CGPoint(x: 10, y: 20), role: "base"),
            Athlete(label: "B1", position: CGPoint(x: 26, y: 10), role: "flyer"),
            Athlete(label: "B2", position: CGPoint(x: 26, y: 15), role: "base"),
            Athlete(label: "B3", position: CGPoint(x: 26, y: 20), role: "base"),
            Athlete(label: "C1", position: CGPoint(x: 42, y: 10), role: "flyer"),
            Athlete(label: "C2", position: CGPoint(x: 42, y: 15), role: "base"),
        ]
        return formation
    }
}
