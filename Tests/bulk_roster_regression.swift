import Foundation

@main
struct BulkRosterRegression {
    @MainActor static func main() throws {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        precondition(documents.path.hasPrefix("/tmp/formationflow-roster-test-"), "Run with CFFIXED_USER_HOME pointing to an isolated test home")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let entries = try RosterImport.prepare("Name\tRole\r\nAlex Smith\tFlyer\r\nAlex Stone\tback spot\r\n\r\nSam\tT\r\nSam\tUnknown", existingLabels: ["AS"])
        precondition(entries.count == 4)
        precondition(entries.map(\.role) == [.flyer, .backspot, .tumbler, .base])
        precondition(Set(entries.map(\.label)).count == 4)
        precondition(!entries.map(\.label).contains("AS"))
        precondition(entries.allSatisfy { $0.label.count <= 3 })
        let csv = try RosterImport.prepare("\"Smith, Alex\",Flyer\nZoë Chen,Spotter", existingLabels: [])
        precondition(csv.count == 2 && csv[0].sourceName == "Smith, Alex" && csv[0].role == .flyer)
        let boundary = try RosterImport.prepare(Array(repeating: "Alex", count: 200).joined(separator: "\n"), existingLabels: [])
        precondition(boundary.count == 200 && RosterImport.valid(boundary, existingLabels: []))
        do {
            _ = try RosterImport.prepare(Array(repeating: "Alex", count: 201).joined(separator: "\n"), existingLabels: [])
            preconditionFailure("Oversized input must not silently drop athletes")
        } catch RosterImportError.tooMany {}
        do { _ = try RosterImport.prepare(" \n\t", existingLabels: []); preconditionFailure("Empty import") }
        catch RosterImportError.empty {}
        var invalid = entries
        invalid[0].label = "LONG"
        precondition(!RosterImport.valid(invalid, existingLabels: []))
        invalid[0].label = invalid[1].label.lowercased()
        precondition(!RosterImport.valid(invalid, existingLabels: []))

        let store = RoutineStore()
        store.resetRoutine()
        let first = store.routine.formations[0].id
        let originalAthlete = store.addAthlete()
        store.mutateRosterAthlete(id: originalAthlete) { $0.label = "OLD" }
        let second = store.addFormation(after: first)
        let oldPositions = store.routine.formations.map { $0.placements.first { $0.athleteID == originalAthlete }!.position }
        let prepared = try RosterImport.prepare("Alex Smith,Flyer\nSam,Base", existingLabels: ["OLD"])
        let before = store.routine
        do { try store.importRoster(prepared, isPro: false); preconditionFailure("Pro gate") }
        catch RosterImportError.requiresPro {}
        precondition(store.routine == before)
        let importedIDs = try store.importRoster(prepared, isPro: true)
        precondition(importedIDs.count == 2)
        precondition(store.routine.roster.count == 3)
        for (index, formation) in store.routine.formations.enumerated() {
            precondition(formation.placements.count == 3)
            precondition(Set(formation.placements.map(\.athleteID)) == Set(store.routine.roster.map(\.id)))
            precondition(formation.placements.first { $0.athleteID == originalAthlete }!.position == oldPositions[index])
        }
        precondition(store.transitionPaths(from: first, to: second).count == 3)
        precondition(store.renderedAthletes(for: first).contains { $0.id == importedIDs[0] && $0.role == .flyer && $0.label == prepared[0].label })
        let source = store.routine
        let targetID = store.addRoutine()
        store.switchRoutine(id: targetID)
        let copies = try RosterImport.copy(source.roster, existingLabels: [])
        let copiedIDs = try store.importRoster(copies, isPro: true)
        precondition(Set(copiedIDs).isDisjoint(with: Set(source.roster.map(\.id))))
        precondition(store.routine.roster.map(\.label) == source.roster.map(\.label))
        precondition(store.routine.roster.map(\.role) == source.roster.map(\.role))
        precondition(store.workspace.routines.first { $0.id == source.id } == source)
        let largerTeam = try RosterImport.prepare((1...20).map { "Player \($0)" }.joined(separator: "\n"), existingLabels: store.routine.roster.map(\.label))
        try store.importRoster(largerTeam, isPro: true)
        let placements = store.routine.formations[0].placements
        for first in placements.indices {
            for second in placements.indices where second > first {
                let a = placements[first].position
                let b = placements[second].position
                let dx = a.x - b.x
                let dy = a.y - b.y
                precondition(dx * dx + dy * dy >= CourtConstants.collisionDistance * CourtConstants.collisionDistance, "New team members must not stack at the default court-edge spawn")
            }
        }
        let loaded = RoutineStore()
        precondition(loaded.routine.roster == store.routine.roster)
        precondition(loaded.routine.formations == store.routine.formations)
        print("PASS: paste/TSV/CSV/Unicode, collisions, batch limits, validation, Pro gate, placements, transition caches, roster copy, source preservation and persistence")
    }
}
