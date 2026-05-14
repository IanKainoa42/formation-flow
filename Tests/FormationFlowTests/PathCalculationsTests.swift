import XCTest
@testable import FormationFlow

final class PathCalculationsTests: XCTestCase {
    func testDistanceCalculations() {
        let p1 = CGPoint(x: 0, y: 0)
        let p2 = CGPoint(x: 3, y: 4)

        XCTAssertEqual(PathCalculations.distance(from: p1, to: p2), 5.0)
        XCTAssertEqual(PathCalculations.squaredDistance(from: p1, to: p2), 25.0)
    }

    func testQuadraticBezierPoint() {
        let p0 = CGPoint(x: 0, y: 0)
        let c = CGPoint(x: 5, y: 10)
        let p2 = CGPoint(x: 10, y: 0)

        // At t = 0, should be p0
        XCTAssertEqual(PathCalculations.quadraticBezierPoint(from: p0, control: c, to: p2, t: 0), p0)

        // At t = 0.5
        let mid = PathCalculations.quadraticBezierPoint(from: p0, control: c, to: p2, t: 0.5)
        XCTAssertEqual(mid.x, 5.0)
        XCTAssertEqual(mid.y, 5.0)

        // At t = 1, should be p2
        XCTAssertEqual(PathCalculations.quadraticBezierPoint(from: p0, control: c, to: p2, t: 1), p2)
    }

    func testCubicBezierPoint() {
        let p0 = CGPoint(x: 0, y: 0)
        let c1 = CGPoint(x: 0, y: 10)
        let c2 = CGPoint(x: 10, y: 10)
        let p3 = CGPoint(x: 10, y: 0)

        // At t = 0, should be p0
        XCTAssertEqual(PathCalculations.cubicBezierPoint(p0: p0, c1: c1, c2: c2, p3: p3, t: 0), p0)

        // At t = 0.5
        let mid = PathCalculations.cubicBezierPoint(p0: p0, c1: c1, c2: c2, p3: p3, t: 0.5)
        XCTAssertEqual(mid.x, 5.0)
        XCTAssertEqual(mid.y, 7.5)

        // At t = 1, should be p3
        XCTAssertEqual(PathCalculations.cubicBezierPoint(p0: p0, c1: c1, c2: c2, p3: p3, t: 1), p3)
    }

    func testAthletePathStraightLine() {
        let start = CGPoint(x: 0, y: 0)
        let end = CGPoint(x: 10, y: 0)

        let path = PathCalculations.athletePath(from: start, to: end, steps: 3)
        XCTAssertEqual(path.count, 3)
        XCTAssertEqual(path[0], start)
        XCTAssertEqual(path[1], CGPoint(x: 5, y: 0))
        XCTAssertEqual(path[2], end)
    }

    func testAthletePathWithControlPoint() {
        let start = CGPoint(x: 0, y: 0)
        let end = CGPoint(x: 10, y: 0)
        let control = CGPoint(x: 5, y: 10)

        let path = PathCalculations.athletePath(from: start, to: end, control: control, steps: 3)
        XCTAssertEqual(path.count, 3)
        XCTAssertEqual(path[0], start)
        XCTAssertEqual(path[1], CGPoint(x: 5, y: 5))
        XCTAssertEqual(path[2], end)
    }

    func testCollisionSummary() {
        let athlete1 = RenderedAthlete(id: UUID(), label: "A1", role: .base, position: CGPoint(x: 10, y: 10))
        let athlete2 = RenderedAthlete(id: UUID(), label: "A2", role: .base, position: CGPoint(x: 11, y: 11)) // Distance ~1.41
        let athlete3 = RenderedAthlete(id: UUID(), label: "A3", role: .base, position: CGPoint(x: 20, y: 20)) // Distance > 2.0

        let minDistance: CGFloat = 2.0

        // Only A1 and A2 should collide
        let (count, ids) = PathCalculations.collisionSummary(in: [athlete1, athlete2, athlete3], minDistance: minDistance)

        XCTAssertEqual(count, 1)
        XCTAssertEqual(ids.count, 2)
        XCTAssertTrue(ids.contains(athlete1.id))
        XCTAssertTrue(ids.contains(athlete2.id))
        XCTAssertFalse(ids.contains(athlete3.id))
    }

    func testFindPathCollisionIDs() {
        let athlete1 = UUID()
        let athlete2 = UUID()
        let athlete3 = UUID()

        // Paths that cross exactly at (5, 5) at the same time
        let path1 = TransitionPathRenderItem(
            athleteID: athlete1,
            startPosition: CGPoint(x: 0, y: 0),
            endPosition: CGPoint(x: 10, y: 10),
            controlPoint: nil,
            waypoints: []
        )
        let path2 = TransitionPathRenderItem(
            athleteID: athlete2,
            startPosition: CGPoint(x: 0, y: 10),
            endPosition: CGPoint(x: 10, y: 0),
            controlPoint: nil,
            waypoints: []
        )
        // Path far away
        let path3 = TransitionPathRenderItem(
            athleteID: athlete3,
            startPosition: CGPoint(x: 20, y: 20),
            endPosition: CGPoint(x: 30, y: 30),
            controlPoint: nil,
            waypoints: []
        )

        let collisionIDs = PathCalculations.findPathCollisionIDs(paths: [path1, path2, path3])

        XCTAssertEqual(collisionIDs.count, 2)
        XCTAssertTrue(collisionIDs.contains(athlete1))
        XCTAssertTrue(collisionIDs.contains(athlete2))
        XCTAssertFalse(collisionIDs.contains(athlete3))
    }

    func testDelayedMovementProgressDoesNotCompressMovementToCatchUp() {
        let shortMoveProgress = PathCalculations.delayedMovementProgress(
            timelineProgress: 0.5,
            moveDelayCounts: 2,
            moveDurationCounts: 4,
            playbackDurationCounts: 8
        )
        let shortMoveFinished = PathCalculations.delayedMovementProgress(
            timelineProgress: 0.75,
            moveDelayCounts: 2,
            moveDurationCounts: 4,
            playbackDurationCounts: 8
        )
        let longMoveProgress = PathCalculations.delayedMovementProgress(
            timelineProgress: 0.8,
            moveDelayCounts: 2,
            moveDurationCounts: 8,
            playbackDurationCounts: 10
        )

        XCTAssertEqual(shortMoveProgress, 0.5, accuracy: 0.001)
        XCTAssertEqual(shortMoveFinished, 1.0, accuracy: 0.001)
        XCTAssertEqual(longMoveProgress, 0.75, accuracy: 0.001)
    }

    func testFindPathCollisionDetailsAddsPenaltyResponses() {
        let athlete1 = UUID()
        let athlete2 = UUID()

        let path1 = TransitionPathRenderItem(
            athleteID: athlete1,
            startPosition: CGPoint(x: 0, y: 0),
            endPosition: CGPoint(x: 10, y: 10),
            controlPoint: nil,
            waypoints: []
        )
        let path2 = TransitionPathRenderItem(
            athleteID: athlete2,
            startPosition: CGPoint(x: 0, y: 10),
            endPosition: CGPoint(x: 10, y: 0),
            controlPoint: nil,
            waypoints: []
        )

        let details = PathCalculations.findPathCollisionDetails(paths: [path1, path2], counts: 8, steps: 60)

        XCTAssertTrue(details.ids.contains(athlete1))
        XCTAssertTrue(details.ids.contains(athlete2))
        XCTAssertEqual(details.markerProgresses.count, 1)
        XCTAssertEqual(details.responses[athlete1]?.count, 1)
        XCTAssertEqual(details.responses[athlete2]?.count, 1)

        let response1 = try XCTUnwrap(details.responses[athlete1]?.first)
        let response2 = try XCTUnwrap(details.responses[athlete2]?.first)
        let markerProgress = try XCTUnwrap(details.markerProgresses.first)
        XCTAssertEqual(markerProgress, 0.422, accuracy: 0.02)
        XCTAssertLessThan(markerProgress, response1.progress)
        XCTAssertEqual(response1.holdCounts, 0.5)
        XCTAssertEqual(response2.holdCounts, 0.5)
        XCTAssertEqual(response1.progress, 0.45, accuracy: 0.02)
        XCTAssertEqual(response2.progress, 0.45, accuracy: 0.02)
        XCTAssertGreaterThan(PathCalculations.squaredDistance(from: response1.redirectOffset, to: .zero), 0)
        XCTAssertGreaterThan(PathCalculations.squaredDistance(from: response2.redirectOffset, to: .zero), 0)
        XCTAssertNotEqual(response1.redirectOffset, response2.redirectOffset)
    }

    func testPathCollisionDetailsDoesNotBumpStationaryAthlete() {
        let movingAthlete = UUID()
        let stationaryAthlete = UUID()

        let movingPath = TransitionPathRenderItem(
            athleteID: movingAthlete,
            startPosition: CGPoint(x: 0, y: 5),
            endPosition: CGPoint(x: 10, y: 5),
            controlPoint: nil,
            waypoints: []
        )
        let stationaryPath = TransitionPathRenderItem(
            athleteID: stationaryAthlete,
            startPosition: CGPoint(x: 5, y: 5),
            endPosition: CGPoint(x: 5, y: 5),
            controlPoint: nil,
            waypoints: []
        )

        let details = PathCalculations.findPathCollisionDetails(paths: [movingPath, stationaryPath], counts: 8, steps: 60)

        XCTAssertTrue(details.ids.contains(movingAthlete))
        XCTAssertTrue(details.ids.contains(stationaryAthlete))
        XCTAssertEqual(details.markerProgresses.first ?? -1, 0.325, accuracy: 0.02)
        XCTAssertEqual(details.responses[movingAthlete]?.count, 1)
        XCTAssertNil(details.responses[stationaryAthlete])
    }

    func testHoldAdjustedPathProgressSupportsTransientCollisionHolds() {
        let collisionHold = [(progress: CGFloat(0.5), duration: CGFloat(0.5))]

        let heldProgress = PathCalculations.holdAdjustedPathProgress(
            wallProgress: 0.52,
            holdEvents: collisionHold,
            moveDuration: 8
        )
        let recoveredProgress = PathCalculations.holdAdjustedPathProgress(
            wallProgress: 0.7,
            holdEvents: collisionHold,
            moveDuration: 8
        )

        XCTAssertEqual(heldProgress, 0.5, accuracy: 0.001)
        XCTAssertGreaterThan(recoveredProgress, 0.5)
        XCTAssertLessThan(recoveredProgress, 0.7)
    }

    func testCollisionRedirectedPositionTapersAroundCollision() {
        let response = PathCalculations.CollisionResponse(
            progress: 0.5,
            holdCounts: 0.5,
            redirectOffset: CGPoint(x: 1, y: 0)
        )
        let position = CGPoint(x: 10, y: 10)

        let redirected = PathCalculations.collisionRedirectedPosition(
            position,
            pathProgress: 0.5,
            responses: [response]
        )
        let recovered = PathCalculations.collisionRedirectedPosition(
            position,
            pathProgress: 0.7,
            responses: [response]
        )
        let final = PathCalculations.collisionRedirectedPosition(
            position,
            pathProgress: 1,
            responses: [response]
        )

        XCTAssertEqual(redirected.x, 11, accuracy: 0.001)
        XCTAssertEqual(redirected.y, 10, accuracy: 0.001)
        XCTAssertEqual(recovered, position)
        XCTAssertEqual(final, position)
    }
}
