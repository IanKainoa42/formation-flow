import XCTest
@testable import FormationFlow

final class ModelTests: XCTestCase {
    func testFormationInitialization() {
        let formation = Formation(name: "Test Formation", notes: "Test Notes")

        XCTAssertEqual(formation.name, "Test Formation")
        XCTAssertEqual(formation.notes, "Test Notes")
        XCTAssertTrue(formation.placements.isEmpty)
    }

    func testFormationPlacementIndex() {
        let athleteID1 = UUID()
        let athleteID2 = UUID()
        let placements = [
            FormationPlacement(athleteID: athleteID1, position: CGPoint(x: 10, y: 10)),
            FormationPlacement(athleteID: athleteID2, position: CGPoint(x: 20, y: 20))
        ]
        let formation = Formation(placements: placements)

        XCTAssertEqual(formation.placementIndex(for: athleteID1), 0)
        XCTAssertEqual(formation.placementIndex(for: athleteID2), 1)
        XCTAssertNil(formation.placementIndex(for: UUID()))
    }

    func testAthleteTransitionInitialization() {
        let athleteID = UUID()
        let transition = AthleteTransition(athleteID: athleteID, moveDelay: 2.0)

        XCTAssertEqual(transition.athleteID, athleteID)
        XCTAssertEqual(transition.moveDelay, 2.0)
        XCTAssertNil(transition.pathControlPoint)
        XCTAssertTrue(transition.pathWaypoints.isEmpty)
    }

    func testTransitionSpecAthleteTransitionLookup() {
        let athleteID1 = UUID()
        let athleteID2 = UUID()
        let transition1 = AthleteTransition(athleteID: athleteID1)
        let spec = TransitionSpec(
            fromFormationID: UUID(),
            toFormationID: UUID(),
            athleteTransitions: [transition1]
        )

        XCTAssertEqual(spec.athleteTransition(for: athleteID1), transition1)
        // Should return a new transition for an unknown athlete
        let newTransition = spec.athleteTransition(for: athleteID2)
        XCTAssertEqual(newTransition.athleteID, athleteID2)
        XCTAssertEqual(newTransition.moveDelay, 0)
    }

    func testTransitionSpecSynchronize() {
        let athleteID1 = UUID()
        let athleteID2 = UUID()
        let athleteID3 = UUID()

        let transition1 = AthleteTransition(athleteID: athleteID1, moveDelay: 1.0)
        let transition2 = AthleteTransition(athleteID: athleteID2, moveDelay: 2.0)

        var spec = TransitionSpec(
            fromFormationID: UUID(),
            toFormationID: UUID(),
            athleteTransitions: [transition1, transition2]
        )

        // Synchronize with athleteID1 (kept), athleteID3 (added), athleteID2 (removed)
        spec.synchronize(athleteIDs: [athleteID1, athleteID3])

        XCTAssertEqual(spec.athleteTransitions.count, 2)
        XCTAssertEqual(spec.athleteTransitions[0].athleteID, athleteID1)
        XCTAssertEqual(spec.athleteTransitions[0].moveDelay, 1.0) // Properties kept
        XCTAssertEqual(spec.athleteTransitions[1].athleteID, athleteID3)
        XCTAssertEqual(spec.athleteTransitions[1].moveDelay, 0.0) // Default properties
    }

    func testTransitionStuntGroupCreationOverridesSelectedPaths() {
        let athleteID1 = UUID()
        let athleteID2 = UUID()
        let athleteID3 = UUID()
        var spec = TransitionSpec(
            fromFormationID: UUID(),
            toFormationID: UUID(),
            athleteTransitions: [
                AthleteTransition(
                    athleteID: athleteID1,
                    moveDelay: 1.5,
                    pathControlPoint: CGPoint(x: 4, y: 5),
                    pathWaypoints: [PathWaypoint(position: CGPoint(x: 6, y: 7))]
                ),
                AthleteTransition(
                    athleteID: athleteID2,
                    moveDelay: 0.5,
                    pathControlPoint: CGPoint(x: 8, y: 9),
                    pathWaypoints: [PathWaypoint(position: CGPoint(x: 10, y: 11))]
                ),
                AthleteTransition(athleteID: athleteID3, moveDelay: 2)
            ]
        )

        let group = spec.createStuntGroup(athleteIDs: [athleteID1, athleteID2])

        XCTAssertEqual(group?.athleteIDs, [athleteID1, athleteID2])
        XCTAssertEqual(spec.stuntGroups.first?.athleteIDSet, [athleteID1, athleteID2])
        XCTAssertEqual(spec.athleteTransition(for: athleteID1).moveDelayCounts, 0.5)
        XCTAssertEqual(spec.athleteTransition(for: athleteID2).moveDelayCounts, 0.5)
        XCTAssertNil(spec.athleteTransition(for: athleteID1).pathControlPoint)
        XCTAssertNil(spec.athleteTransition(for: athleteID2).pathControlPoint)
        XCTAssertTrue(spec.athleteTransition(for: athleteID1).pathWaypoints.isEmpty)
        XCTAssertTrue(spec.athleteTransition(for: athleteID2).pathWaypoints.isEmpty)
        XCTAssertEqual(spec.athleteTransition(for: athleteID3).moveDelayCounts, 2)
    }

    func testTransitionStuntGroupsKeepOneGroupPerAthlete() {
        let athleteID1 = UUID()
        let athleteID2 = UUID()
        let athleteID3 = UUID()
        var spec = TransitionSpec(
            fromFormationID: UUID(),
            toFormationID: UUID(),
            athleteTransitions: [
                AthleteTransition(athleteID: athleteID1),
                AthleteTransition(athleteID: athleteID2),
                AthleteTransition(athleteID: athleteID3)
            ]
        )

        _ = spec.createStuntGroup(athleteIDs: [athleteID1, athleteID2])
        _ = spec.createStuntGroup(athleteIDs: [athleteID2, athleteID3])

        XCTAssertEqual(spec.stuntGroups.count, 1)
        XCTAssertEqual(spec.stuntGroups[0].athleteIDSet, [athleteID2, athleteID3])
    }

    func testRoutineInitialization() {
        let routine = Routine.initial()

        XCTAssertEqual(routine.name, "Routine 1")
        XCTAssertTrue(routine.roster.isEmpty)
        XCTAssertEqual(routine.formations.count, 1)
        XCTAssertEqual(routine.formations[0].name, "Formation 1")
        XCTAssertTrue(routine.transitionSpecs.isEmpty)
    }
}
