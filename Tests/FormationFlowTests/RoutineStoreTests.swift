import XCTest
@testable import FormationFlow

@MainActor
final class RoutineStoreTests: XCTestCase {
    var store: RoutineStore!

    override func setUp() {
        super.setUp()
        // Clear standard UserDefaults to avoid side effects
        UserDefaults.standard.removeObject(forKey: "routine.v1")
        store = RoutineStore()
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "routine.v1")
        store = nil
        super.tearDown()
    }

    func testAddAthlete() {
        XCTAssertTrue(store.routine.roster.isEmpty)

        let initialFormation = store.routine.formations[0]
        XCTAssertTrue(initialFormation.placements.isEmpty)

        let athleteID = store.addAthlete()

        XCTAssertEqual(store.routine.roster.count, 1)
        XCTAssertEqual(store.routine.roster[0].id, athleteID)

        // Ensure athlete was placed in all formations
        XCTAssertEqual(store.routine.formations[0].placements.count, 1)
        XCTAssertEqual(store.routine.formations[0].placements[0].athleteID, athleteID)
    }

    func testAddFormation() {
        XCTAssertEqual(store.routine.formations.count, 1)

        // Setup initial state with an athlete
        let athleteID = store.addAthlete()
        let initialFormationID = store.routine.formations[0].id

        let newFormationID = store.addFormation(after: initialFormationID)

        XCTAssertEqual(store.routine.formations.count, 2)
        XCTAssertEqual(store.routine.formations[1].id, newFormationID)

        // Check transition specs were generated
        XCTAssertEqual(store.routine.transitionSpecs.count, 1)
        XCTAssertEqual(store.routine.transitionSpecs[0].fromFormationID, initialFormationID)
        XCTAssertEqual(store.routine.transitionSpecs[0].toFormationID, newFormationID)
        XCTAssertEqual(store.routine.transitionSpecs[0].athleteTransitions.count, 1)
        XCTAssertEqual(store.routine.transitionSpecs[0].athleteTransitions[0].athleteID, athleteID)
    }

    func testDeleteFormation() {
        let initialFormationID = store.routine.formations[0].id
        let newFormationID = store.addFormation(after: initialFormationID)
        let newFormationID2 = store.addFormation(after: newFormationID)

        XCTAssertEqual(store.routine.formations.count, 3)
        XCTAssertEqual(store.routine.transitionSpecs.count, 2)

        // Delete middle formation
        store.deleteFormation(id: newFormationID)

        XCTAssertEqual(store.routine.formations.count, 2)
        XCTAssertEqual(store.routine.formations[0].id, initialFormationID)
        XCTAssertEqual(store.routine.formations[1].id, newFormationID2)

        // Transition spec should be updated from initial -> newFormationID2
        XCTAssertEqual(store.routine.transitionSpecs.count, 1)
        XCTAssertEqual(store.routine.transitionSpecs[0].fromFormationID, initialFormationID)
        XCTAssertEqual(store.routine.transitionSpecs[0].toFormationID, newFormationID2)
    }

    func testDeleteLastFormationIsPrevented() {
        let initialFormationID = store.routine.formations[0].id

        // Attempt to delete the only formation
        store.deleteFormation(id: initialFormationID)

        // Should recreate a default formation
        XCTAssertEqual(store.routine.formations.count, 1)
        XCTAssertNotEqual(store.routine.formations[0].id, initialFormationID)
        XCTAssertEqual(store.routine.formations[0].name, "Formation 1")
    }

    func testDuplicateFormation() {
        let athleteID = store.addAthlete()
        let initialFormationID = store.routine.formations[0].id

        store.mutateFormation(id: initialFormationID) { formation in
            formation.name = "Original"
            formation.notes = "Test Note"
            formation.placements[0].position = CGPoint(x: 10, y: 10)
        }

        let duplicatedID = store.duplicateFormation(after: initialFormationID)

        XCTAssertEqual(store.routine.formations.count, 2)
        XCTAssertEqual(store.routine.formations[1].id, duplicatedID)

        let duplicatedFormation = store.routine.formations[1]
        XCTAssertNotEqual(duplicatedFormation.name, "Original") // Name should be auto-generated to next available
        XCTAssertEqual(duplicatedFormation.notes, "Test Note")
        XCTAssertEqual(duplicatedFormation.placements[0].position, CGPoint(x: 10, y: 10))
    }

    func testDeleteAthlete() {
        let athleteID1 = store.addAthlete()
        let athleteID2 = store.addAthlete()
        let initialFormationID = store.routine.formations[0].id
        _ = store.addFormation(after: initialFormationID)

        XCTAssertEqual(store.routine.roster.count, 2)
        XCTAssertEqual(store.routine.formations[0].placements.count, 2)
        XCTAssertEqual(store.routine.transitionSpecs[0].athleteTransitions.count, 2)

        // Delete first athlete
        store.deleteAthlete(id: athleteID1)

        XCTAssertEqual(store.routine.roster.count, 1)
        XCTAssertEqual(store.routine.roster[0].id, athleteID2)

        XCTAssertEqual(store.routine.formations[0].placements.count, 1)
        XCTAssertEqual(store.routine.formations[0].placements[0].athleteID, athleteID2)

        XCTAssertEqual(store.routine.transitionSpecs[0].athleteTransitions.count, 1)
        XCTAssertEqual(store.routine.transitionSpecs[0].athleteTransitions[0].athleteID, athleteID2)
    }
}
