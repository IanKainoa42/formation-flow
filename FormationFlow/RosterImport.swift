import Foundation

// MARK: - Bulk Roster Preparation

struct RosterImportEntry: Identifiable, Equatable {
    var id = UUID()
    var sourceName: String
    var label: String
    var role: AthleteRole
}

enum RosterImportError: LocalizedError {
    case empty, tooMany, invalidLabels, requiresPro

    var errorDescription: String? {
        switch self {
        case .empty: return "Paste at least one athlete name."
        case .tooMany: return "Add up to 200 athletes at a time."
        case .invalidLabels: return "Use a different label for each athlete, with 1–3 characters and no spaces."
        case .requiresPro: return "Adding a team with custom labels and roles requires FormationFlow Pro."
        }
    }
}

enum RosterImport {
    static let batchLimit = 200

    /// Notes: one name per line. Spreadsheets: Name and optional Role columns.
    /// Names are only retained in the review draft; the saved identity is the floor label.
    static func prepare(_ text: String, existingLabels: [String]) throws -> [RosterImportEntry] {
        var used = Set(existingLabels.map { $0.lowercased() })
        var entries: [RosterImportEntry] = []
        for line in text.components(separatedBy: .newlines) {
            let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { continue }
            let separator: Character = clean.contains("\t") ? "\t" : ","
            let columns = fields(clean, separator: separator)
            let name = (columns.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            if entries.isEmpty, ["name", "athlete", "athlete name"].contains(name.lowercased()),
               columns.count == 1 || columns.dropFirst().first?.lowercased() == "role" { continue }
            guard entries.count < batchLimit else { throw RosterImportError.tooMany }
            let role = columns.count > 1 ? role(named: columns[1]) ?? .base : .base
            entries.append(RosterImportEntry(sourceName: name, label: uniqueLabel(for: name, used: &used), role: role))
        }
        guard !entries.isEmpty else { throw RosterImportError.empty }
        return entries
    }

    static func copy(_ roster: [RosterAthlete], existingLabels: [String]) throws -> [RosterImportEntry] {
        guard !roster.isEmpty else { throw RosterImportError.empty }
        guard roster.count <= batchLimit else { throw RosterImportError.tooMany }
        var used = Set(existingLabels.map { $0.lowercased() })
        return roster.map {
            RosterImportEntry(sourceName: $0.label, label: uniqueLabel(for: $0.label, used: &used), role: $0.role)
        }
    }

    static func valid(_ entries: [RosterImportEntry], existingLabels: [String]) -> Bool {
        guard !entries.isEmpty, entries.count <= batchLimit else { return false }
        var used = Set(existingLabels.map { $0.lowercased() })
        for entry in entries {
            let label = entry.label
            guard !label.isEmpty, label.count <= 3,
                  !label.contains(where: { $0.isWhitespace }),
                  used.insert(label.lowercased()).inserted else { return false }
        }
        return true
    }

    static func role(named text: String) -> AthleteRole? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        return AthleteRole.allCases.first {
            $0.rawValue.lowercased() == value || $0.shortLabel.lowercased() == value
        }
    }

    private static func uniqueLabel(for name: String, used: inout Set<String>) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace })
        let suggested = words.count > 1
            ? String(words.prefix(3).compactMap { $0.first })
            : String(name.filter { !$0.isWhitespace }.prefix(3))
        let stem = suggested.isEmpty ? "A" : suggested.uppercased()
        let initial = String(stem.prefix(3))
        if used.insert(initial.lowercased()).inserted { return initial }
        for number in 1...999 {
            let suffix = String(number)
            let candidate = String(stem.prefix(max(0, 3 - suffix.count))) + suffix
            if used.insert(candidate.lowercased()).inserted { return candidate }
        }
        // More than 1,000 distinct floor labels is outside this batch's supported size.
        return ""
    }

    static func spawnPosition(near preferred: CGPoint, occupied: [CGPoint]) -> CGPoint {
        func distanceSquared(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
            let dx = first.x - second.x
            let dy = first.y - second.y
            return dx * dx + dy * dy
        }
        let clearance = CourtConstants.collisionDistance * CourtConstants.collisionDistance
        if !occupied.contains(where: { distanceSquared(preferred, $0) < clearance }) { return preferred }
        var best: CGPoint?
        var bestDistance = CGFloat.infinity
        for y in stride(from: CGFloat(2), through: CourtConstants.height - 2, by: CGFloat(2)) {
            for x in stride(from: CGFloat(2), through: CourtConstants.width - 2, by: CGFloat(2)) {
                let candidate = CGPoint(x: x, y: y)
                let distance = distanceSquared(candidate, preferred)
                if distance < bestDistance,
                   !occupied.contains(where: { distanceSquared(candidate, $0) < clearance }) {
                    best = candidate
                    bestDistance = distance
                }
            }
        }
        return best ?? preferred
    }

    private static func fields(_ line: String, separator: Character) -> [String] {
        var result: [String] = []
        var field = ""
        var quoted = false
        var iterator = line.makeIterator()
        while let character = iterator.next() {
            if character == "\"" { quoted.toggle() }
            else if character == separator && !quoted {
                result.append(field.trimmingCharacters(in: .whitespaces))
                field = ""
            } else { field.append(character) }
        }
        result.append(field.trimmingCharacters(in: .whitespaces))
        return result
    }
}

// MARK: - Store Mutations

extension RoutineStore {
    /// Uses the existing mutation methods to preserve placements, paths and lookup caches.
    @discardableResult
    func importRoster(_ entries: [RosterImportEntry], isPro: Bool) throws -> [UUID] {
        guard isPro else { throw RosterImportError.requiresPro }
        guard RosterImport.valid(entries, existingLabels: routine.roster.map(\.label)) else {
            throw RosterImportError.invalidLabels
        }
        let ids = entries.map { entry in
            let id = addAthlete()
            mutateRosterAthlete(id: id) {
                $0.label = entry.label
                $0.role = entry.role
            }
            // The single-athlete spawn clamps at the court edge. A pasted team
            // would otherwise stack several newcomers at identical positions.
            for formation in routine.formations {
                guard let placement = formation.placements.first(where: { $0.athleteID == id }) else { continue }
                let occupied = formation.placements.filter { $0.athleteID != id }.map(\.position)
                let position = RosterImport.spawnPosition(near: placement.position, occupied: occupied)
                mutateFormation(id: formation.id) { formation in
                    if let index = formation.placements.firstIndex(where: { $0.athleteID == id }) {
                        formation.placements[index].position = position
                    }
                }
            }
            return id
        }
        saveNow()
        return ids
    }
}
