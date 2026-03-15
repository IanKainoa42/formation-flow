import Foundation
import SwiftUI

@main
struct DeleteInvalidFormationRegression {
    @MainActor
    static func main() {
        UserDefaults.standard.removeObject(forKey: "routine.v1")
        defer {
            UserDefaults.standard.removeObject(forKey: "routine.v1")
        }

        let store = RoutineStore()
        _ = store.addAthlete()

        store.mutateFormation(id: store.routine.formations[0].id) { formation in
            formation.name = "Keep Me"
            formation.notes = "still here"
        }

        let original = store.routine.formations[0]
        store.deleteFormation(id: UUID())
        let remaining = store.routine.formations[0]

        precondition(store.routine.formations.count == 1, "expected a single formation")
        precondition(remaining.id == original.id, "invalid delete replaced the only formation")
        precondition(remaining.name == original.name, "invalid delete lost formation name")
        precondition(remaining.notes == original.notes, "invalid delete lost formation notes")
        precondition(
            remaining.placements.map(\.athleteID) == original.placements.map(\.athleteID),
            "invalid delete lost placements"
        )

        print("ok")
    }
}
