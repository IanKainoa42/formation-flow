import Combine
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

    func testAddFormationDuplicatesPreviousFormation() {
        let athleteID = store.addAthlete()
        let initialFormationID = store.routine.formations[0].id

        store.mutateFormation(id: initialFormationID) { formation in
            formation.notes = "8-count intro"
            formation.placements[0].position = CGPoint(x: 24, y: 18)
        }

        let newFormationID = store.addFormation(after: initialFormationID)

        XCTAssertEqual(store.routine.formations.count, 2)

        guard let duplicated = store.formation(id: newFormationID) else {
            XCTFail("Expected new formation")
            return
        }

        XCTAssertEqual(duplicated.notes, "8-count intro")
        XCTAssertEqual(duplicated.placements.count, 1)
        XCTAssertEqual(duplicated.placements[0].athleteID, athleteID)
        XCTAssertEqual(duplicated.placements[0].position, CGPoint(x: 24, y: 18))
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

    func testDeleteMultipleAthletesReconcilesRosterFormationsAndTransitionsAtomically() {
        let athleteID1 = store.addAthlete()
        let athleteID2 = store.addAthlete()
        let athleteID3 = store.addAthlete()
        let initialFormationID = store.routine.formations[0].id
        let secondFormationID = store.addFormation(after: initialFormationID)

        store.mutateFormation(id: secondFormationID) { formation in
            formation.placements[0].position = CGPoint(x: 11, y: 12)
            formation.placements[1].position = CGPoint(x: 21, y: 22)
            formation.placements[2].position = CGPoint(x: 31, y: 32)
        }
        store.mutateAthleteTransition(from: initialFormationID, to: secondFormationID, athleteID: athleteID2) { transition in
            transition.moveDelayCounts = 2
        }

        store.deleteAthletes(ids: [athleteID1, athleteID3])

        XCTAssertEqual(store.routine.roster.map(\.id), [athleteID2])
        XCTAssertEqual(store.routine.formations.map { $0.placements.map(\.athleteID) }, [[athleteID2], [athleteID2]])
        XCTAssertEqual(store.routine.formations[1].placements[0].position, CGPoint(x: 21, y: 22))
        XCTAssertEqual(store.routine.transitionSpecs.count, 1)
        XCTAssertEqual(store.routine.transitionSpecs[0].athleteTransitions.map(\.athleteID), [athleteID2])
        XCTAssertEqual(store.routine.transitionSpecs[0].athleteTransitions[0].moveDelayCounts, 2)
    }

    func testCreateTransitionStuntGroupPersistsOnTransitionSpec() {
        let athleteID1 = store.addAthlete()
        let athleteID2 = store.addAthlete()
        let athleteID3 = store.addAthlete()
        let startFormationID = store.routine.formations[0].id
        let endFormationID = store.addFormation(after: startFormationID)

        let group = store.createTransitionStuntGroup(
            from: startFormationID,
            to: endFormationID,
            athleteIDs: [athleteID1, athleteID2]
        )

        XCTAssertEqual(group?.athleteIDSet, [athleteID1, athleteID2])
        XCTAssertEqual(
            store.transitionStuntGroup(containing: athleteID1, from: startFormationID, to: endFormationID)?.athleteIDSet,
            [athleteID1, athleteID2]
        )
        XCTAssertNil(store.transitionStuntGroup(containing: athleteID3, from: startFormationID, to: endFormationID))

        store.removeTransitionStuntGroups(containing: [athleteID1], from: startFormationID, to: endFormationID)

        XCTAssertTrue(store.transitionStuntGroups(from: startFormationID, to: endFormationID).isEmpty)
    }

    func testApplyRelativePathWaypointsToStuntGroupPreservesMemberOffsets() {
        let athleteID1 = store.addAthlete()
        let athleteID2 = store.addAthlete()
        let athleteID3 = store.addAthlete()
        let startFormationID = store.routine.formations[0].id
        let endFormationID = store.addFormation(after: startFormationID)

        store.mutateFormation(id: startFormationID) { formation in
            formation.placements[0].position = CGPoint(x: 10, y: 10)
            formation.placements[1].position = CGPoint(x: 14, y: 12)
            formation.placements[2].position = CGPoint(x: 30, y: 30)
        }
        _ = store.createTransitionStuntGroup(
            from: startFormationID,
            to: endFormationID,
            athleteIDs: [athleteID1, athleteID2]
        )

        let anchorWaypoint = PathWaypoint(
            id: UUID(),
            position: CGPoint(x: 20, y: 18),
            isSmooth: true,
            holdDuration: 2
        )
        let startPositions = Dictionary(
            uniqueKeysWithValues: store.renderedAthletes(for: startFormationID).map { ($0.id, $0.position) }
        )

        store.mutateTransitionSpec(from: startFormationID, to: endFormationID) { spec in
            XCTAssertTrue(
                spec.applyRelativePathWaypoints(
                    anchorAthleteID: athleteID1,
                    memberIDs: [athleteID1, athleteID2],
                    anchorWaypoints: [anchorWaypoint],
                    startPositionsByAthleteID: startPositions
                )
            )
        }

        let spec = store.transitionSpec(for: startFormationID, to: endFormationID)
        let anchorPath = spec.athleteTransition(for: athleteID1).pathWaypoints
        let secondPath = spec.athleteTransition(for: athleteID2).pathWaypoints
        let nonMemberPath = spec.athleteTransition(for: athleteID3).pathWaypoints

        XCTAssertEqual(anchorPath.map(\.id), [anchorWaypoint.id])
        XCTAssertEqual(anchorPath.map(\.position), [CGPoint(x: 20, y: 18)])
        XCTAssertEqual(anchorPath.map(\.holdDuration), [2])
        XCTAssertEqual(secondPath.map(\.position), [CGPoint(x: 24, y: 20)])
        XCTAssertEqual(secondPath.map(\.holdDuration), [2])
        XCTAssertNotEqual(secondPath.first?.id, anchorWaypoint.id)
        XCTAssertTrue(nonMemberPath.isEmpty)
    }

    func testDeleteMissingAthleteDoesNotPublishOrMutateRoutine() {
        _ = store.addAthlete()
        let original = store.routine
        var publishCount = 0
        let cancellable = store.objectWillChange.sink {
            publishCount += 1
        }

        store.deleteAthlete(id: UUID())

        XCTAssertEqual(store.routine, original)
        XCTAssertEqual(publishCount, 0)
        _ = cancellable
    }

    func testRoleMutationPublishesAfterRenderedAthletesReflectEveryRole() {
        let athleteID = store.addAthlete()
        let formationID = store.routine.formations[0].id
        XCTAssertEqual(store.renderedAthletes(for: formationID).first?.role, .base)

        for role in AthleteRole.allCases {
            let publishExpectation = expectation(description: "role mutation publishes rendered \(role.rawValue) refresh")
            var observedRoles: [AthleteRole?] = []
            var cancellable: AnyCancellable?
            cancellable = store.objectWillChange.sink { [weak self] _ in
                let renderedRole = self?.store.renderedAthletes(for: formationID).first?.role
                observedRoles.append(renderedRole)
                if renderedRole == role {
                    publishExpectation.fulfill()
                }
            }

            store.mutateRosterAthlete(id: athleteID) { athlete in
                athlete.role = role
            }

            wait(for: [publishExpectation], timeout: 1.0)
            XCTAssertTrue(observedRoles.contains(role), "Expected a post-mutation publish with updated rendered role, observed: \(observedRoles)")
            _ = cancellable
        }
    }
}
