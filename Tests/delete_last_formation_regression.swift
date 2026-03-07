import Foundation
import SwiftUI

@main
struct DeleteLastFormationRegression {
    static func main() async {
        UserDefaults.standard.removeObject(forKey: "routine.v1")
        defer {
            UserDefaults.standard.removeObject(forKey: "routine.v1")
        }

        let counts = await MainActor.run { () -> (roster: Int, placementsBeforeDelete: Int, placementsAfterDelete: Int) in
            let store = RoutineStore()
            _ = store.addAthlete()

            let formationID = store.routine.formations[0].id
            let rosterCount = store.routine.roster.count
            let placementsBeforeDelete = store.routine.formations[0].placements.count

            store.deleteFormation(id: formationID)

            return (
                roster: rosterCount,
                placementsBeforeDelete: placementsBeforeDelete,
                placementsAfterDelete: store.routine.formations[0].placements.count
            )
        }

        precondition(
            counts.placementsBeforeDelete == counts.roster,
            "setup failed: placements should initially match the roster"
        )
        precondition(
            counts.placementsAfterDelete == counts.roster,
            "deleting the final formation must preserve placements for the roster"
        )

        print(
            "ok roster=\(counts.roster) placementsBeforeDelete=\(counts.placementsBeforeDelete) placementsAfterDelete=\(counts.placementsAfterDelete)"
        )
    }
}
