import SwiftUI
import UIKit

extension FloorGridView {
    // MARK: - Formation Actions

    private func snappingResult(for translation: CGPoint) -> SnapResult {
        guard !dragStartPositions.isEmpty else {
            return SnapResult(translation: translation, alignmentGuides: [], mirrorGuides: [])
        }

        return snappingResult(
            translation: translation,
            startingPositions: Array(dragStartPositions.values),
            otherAthletePositions: renderedAthletes.compactMap {
                !selectedAthleteIDs.contains($0.id) ? $0.position : nil
            },
            skipLinearGuides: renderedAthletes.count > 20
        )
    }

    private func snappingResult(
        translation: CGPoint,
        startingPositions: [CGPoint],
        otherAthletePositions: [CGPoint],
        skipLinearGuides: Bool
    ) -> SnapResult {
        guard !startingPositions.isEmpty else {
            return SnapResult(translation: translation, alignmentGuides: [], mirrorGuides: [])
        }

        let alignmentResult = AlignmentSnapEngine.snap(
            translation: translation,
            startingPositions: startingPositions,
            otherAthletePositions: otherAthletePositions,
            skipLinearGuides: skipLinearGuides
        )
        let mirrorResult = FormationMirrorSnapEngine.snap(
            translation: alignmentResult.translation,
            startingPositions: startingPositions,
            otherAthletePositions: otherAthletePositions
        )

        return SnapResult(
            translation: mirrorResult.translation,
            alignmentGuides: alignmentResult.guides,
            mirrorGuides: mirrorResult.guides
        )
    }

    private func clampedCoordinate(_ value: CGFloat, upperBound: CGFloat) -> CGFloat {
        let snapped = round(value / 0.75) * 0.75
        return max(0, min(upperBound, snapped))
    }

    private func addAthlete() {
        let newID = store.addAthlete()
        selectedAthleteIDs = [newID]

        guard entitlementManager.isPro else { return }

        if let newAthlete = store.routine.roster.first(where: { $0.id == newID }) {
            athleteLabelDraft = newAthlete.label
            showingAthleteRenamePrompt = true
        }
    }

    private func beginAthleteRename() {
        guard entitlementManager.isPro else {
            showingUpgradeSheet = true
            return
        }
        guard let selectedRosterAthlete else { return }
        athleteLabelDraft = selectedRosterAthlete.label
        showingAthleteRenamePrompt = true
    }

    private func commitAthleteRename() {
        guard let selectedAthleteID else { return }
        let trimmedLabel = athleteLabelDraft
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedLabel.isEmpty else { return }

        store.mutateRosterAthlete(id: selectedAthleteID) { athlete in
            athlete.label = String(trimmedLabel.prefix(3))
        }
    }

    private func applyTemplate() {
        store.applyBowlingPinTemplate(to: formationID)
        selectedAthleteIDs = []
    }

    private func requestRosterAthleteDeletion(_ ids: [UUID]) {
        let validRosterIDs = Set(store.routine.roster.map(\.id))
        rosterDeleteIDs = ids.reduce(into: [UUID]()) { result, id in
            guard validRosterIDs.contains(id), !result.contains(id) else { return }
            result.append(id)
        }
        if !rosterDeleteIDs.isEmpty { deleteRosterAthletes() }
    }

    private func toggleSwapMode() {
        guard let selectedAthleteID else {
            endSwapMode()
            return
        }

        if isSwapMode, swapSourceAthleteID == selectedAthleteID {
            endSwapMode()
            return
        }

        swapSourceAthleteID = selectedAthleteID
        isSwapMode = true
        swapFormationTarget = .start

        // Reset playback to show the start formation clearly
        if let player {
            player.pause()
            player.seek(to: 0)
        }
    }

    private func endSwapMode() {
        isSwapMode = false
        swapSourceAthleteID = nil
    }

    private func deleteRosterAthletes() {
        let toDelete = rosterDeleteIDs
        rosterDeleteIDs = []
        selectedAthleteIDs.subtract(toDelete)
        if let swapSourceAthleteID, toDelete.contains(swapSourceAthleteID) {
            endSwapMode()
        }
        store.deleteAthletes(ids: toDelete)
    }

    private func deleteSelectedAthlete() {
        guard !selectedAthleteIDs.isEmpty else { return }
        let idsToDelete = selectedAthleteIDs
        selectedAthleteIDs = []
        if let swapSourceAthleteID, idsToDelete.contains(swapSourceAthleteID) {
            endSwapMode()
        }
        store.deleteAthletes(ids: Array(idsToDelete))
    }

    private func pruneRosterDependentState(validAthleteIDs: Set<UUID>) {
        selectedAthleteIDs.formIntersection(validAthleteIDs)
        rosterDeleteIDs.removeAll { !validAthleteIDs.contains($0) }
        if let swapSourceAthleteID, !validAthleteIDs.contains(swapSourceAthleteID) {
            endSwapMode()
        }
    }

    private func mirrorFormation() {
        guard let formation = formation else { return }
        undoStack.append(
            FormationMoveUndoSnapshot(
                formationID: formationID,
                positions: Dictionary(uniqueKeysWithValues: formation.placements.map { ($0.athleteID, $0.position) })
            )
        )
        store.mutateFormation(id: formationID) { form in
            for i in form.placements.indices {
                let x = form.placements[i].position.x
                form.placements[i].position.x = CourtConstants.width - x
            }
        }
        if let endpoint = endpoint(for: formationID) {
            focusedEndpoint = endpoint
        }
        refreshTransitionFromStore()
    }

    private func undoLastMove() {
        guard let snapshot = undoStack.popLast() else { return }
        store.mutateFormation(id: snapshot.formationID) { formation in
            for (athleteID, position) in snapshot.positions {
                if let placementIndex = formation.placementIndex(for: athleteID) {
                    formation.placements[placementIndex].position = position
                }
            }
        }
        if let endpoint = endpoint(for: snapshot.formationID) {
            focusedEndpoint = endpoint
        }
        selectedAthleteIDs = Set(snapshot.positions.keys)
        refreshTransitionFromStore()
    }

    private func undoRecentPathEdit() {
        guard let snapshot = recentPathEditSnapshot else { return }
        clearTransitionDragState()

        store.mutateFormation(id: snapshot.startFormationID) { formation in
            for (athleteID, position) in snapshot.startPositions {
                if let placementIndex = formation.placementIndex(for: athleteID) {
                    formation.placements[placementIndex].position = position
                }
            }
        }
        store.mutateFormation(id: snapshot.endFormationID) { formation in
            for (athleteID, position) in snapshot.endPositions {
                if let placementIndex = formation.placementIndex(for: athleteID) {
                    formation.placements[placementIndex].position = position
                }
            }
        }
        store.mutateTransitionSpec(from: snapshot.startFormationID, to: snapshot.endFormationID) { spec in
            for athleteID in snapshot.affectedAthleteIDs {
                guard let transition = snapshot.transitions[athleteID] else { continue }
                if let index = spec.athleteTransitions.firstIndex(where: { $0.athleteID == athleteID }) {
                    spec.athleteTransitions[index] = transition
                } else {
                    spec.athleteTransitions.append(transition)
                }
            }
        }

        selectedAthleteIDs = snapshot.selectedAthleteIDs
        recentPathEditSnapshot = nil
        isExplicitPathDrawMode = false
        if let endpoint = endpoint(for: formationID) {
            focusedEndpoint = endpoint
        }
        refreshTransitionFromStore()
        store.saveNow()
    }

    private func straightenRecentPathEdit() {
        guard let snapshot = recentPathEditSnapshot else { return }
        clearTransitionDragState()
        store.mutateTransitionSpec(from: snapshot.startFormationID, to: snapshot.endFormationID) { spec in
            for index in spec.athleteTransitions.indices where snapshot.affectedAthleteIDs.contains(spec.athleteTransitions[index].athleteID) {
                spec.athleteTransitions[index].pathControlPoint = nil
                spec.athleteTransitions[index].pathWaypoints = []
            }
        }
        selectedAthleteIDs = snapshot.selectedAthleteIDs
        recentPathEditSnapshot = nil
        refreshTransitionFromStore()
        store.saveNow()
    }

    private func selectCollision(at index: Int) {
        guard !collidingAthletes.isEmpty else { return }
        let safeIndex = index % collidingAthletes.count
        selectedAthleteIDs = selectionForAthlete(collidingAthletes[safeIndex].id)
    }

    private func selectPathCollision(at index: Int) {
        guard !pathCollidingAthletes.isEmpty else { return }
        let safeIndex = index % pathCollidingAthletes.count
        selectedAthleteIDs = selectionForAthlete(pathCollidingAthletes[safeIndex].id)
    }

    private func shareTransitionPreview() {
        guard let payload = makeSharePayload() else {
            shareResultMessage = "Couldn’t prepare the transition preview."
            showingShareResult = true
            return
        }

        RoutineMetrics.record(.transitionShareTapped, metadata: shareMetricMetadata())
        sharePayload = payload
    }

    private func makeSharePayload() -> TransitionSharePayload? {
        guard
            let startFormationName,
            let endFormationName
        else {
            return nil
        }

        let shareCard = TransitionShareCardView(
            routineName: store.routine.name,
            startFormationName: startFormationName,
            endFormationName: endFormationName,
            athleteCount: renderedAthletes.count,
            counts: CGFloat(player?.counts ?? 0),
            spacingAlerts: collidingAthletes.count,
            pathAlerts: pathCollidingAthletes.count,
            athletes: renderedAthletes,
            transitionPaths: transitionPaths,
            endpointMarkers: endpointMarkers,
            collisionIDs: collisionSummary.ids,
            pathCollisionIDs: pathCollisionIDs,
            pathCollisionMarkerPositions: player?.cachedPathCollisionMarkers ?? [],
            pathCollisionMarkerProgresses: player?.cachedPathCollisionMarkerProgresses ?? [],
            pathCollisionStartProgresses: player?.cachedPathCollisionStartProgresses ?? [:],
            startFormationColor: transitionStartColor,
            endFormationColor: transitionEndColor,
            transitionProgress: displayProgress
        )

        let renderer = ImageRenderer(content: shareCard)
        renderer.proposedSize = ProposedViewSize(width: 1200, height: 1400)
        renderer.scale = UIScreen.main.scale

        guard let image = renderer.uiImage else { return nil }

        let message = [
            "\(store.routine.name): \(startFormationName) \u{2192} \(endFormationName)",
            "\(TransitionCountFormatting.label(CGFloat(player?.counts ?? 0)))",
            "Shared from FormationFlow"
        ].joined(separator: "\n")

        return TransitionSharePayload(
            image: image,
            message: message,
            completionMessage: "Shared \(startFormationName) \u{2192} \(endFormationName)."
        )
    }

    private func shareMetricMetadata(activityType: String? = nil) -> [String: String] {
        var metadata: [String: String] = [
            "routine": store.routine.name,
            "formation": formation?.name ?? "unknown",
            "start": startFormationName ?? "unknown",
            "end": endFormationName ?? "unknown",
            "athletes": "\(renderedAthletes.count)"
        ]

        if let activityType {
            metadata["channel"] = activityType
        }

        return metadata
    }

    private var isViewTransformed: Bool {
        zoomScale != 1.0 || canvasPanOffset != .zero
    }

    private func resetView() {
        withAnimation(.spring()) {
            zoomScale = 1.0
            lastZoomScale = 1.0
            canvasPanOffset = .zero
            lastCanvasPanOffset = .zero
        }
    }

}

enum SelectionSpacing {
    static func scaledPositions(
        _ positions: [UUID: CGPoint],
        magnification: CGFloat,
        courtSize: CGSize
    ) -> [UUID: CGPoint] {
        guard positions.count >= 2 else { return positions }

        let sum = positions.values.reduce(CGPoint.zero) {
            CGPoint(x: $0.x + $1.x, y: $0.y + $1.y)
        }
        let center = CGPoint(
            x: sum.x / CGFloat(positions.count),
            y: sum.y / CGFloat(positions.count)
        )

        // Keep the whole selection on the floor without independently clamping
        // members, which would distort the line or shape at an edge.
        var maximumScale: CGFloat = 8
        for position in positions.values {
            let dx = position.x - center.x
            let dy = position.y - center.y
            if dx > 0 {
                maximumScale = min(maximumScale, (courtSize.width - center.x) / dx)
            } else if dx < 0 {
                maximumScale = min(maximumScale, -center.x / dx)
            }
            if dy > 0 {
                maximumScale = min(maximumScale, (courtSize.height - center.y) / dy)
            } else if dy < 0 {
                maximumScale = min(maximumScale, -center.y / dy)
            }
        }

        let scale = max(0.1, min(magnification, maximumScale))
        return positions.mapValues { position in
            CGPoint(
                x: roundedCourtCoordinate(center.x + (position.x - center.x) * scale, upperBound: courtSize.width),
                y: roundedCourtCoordinate(center.y + (position.y - center.y) * scale, upperBound: courtSize.height)
            )
        }
    }

    private static func roundedCourtCoordinate(_ value: CGFloat, upperBound: CGFloat) -> CGFloat {
        max(0, min(upperBound, value.rounded()))
    }
}

enum PathWaypointPlacement {
    static func defaultPlacement(
        transition: AthleteTransition,
        start: CGPoint,
        end: CGPoint
    ) -> (index: Int, point: CGPoint) {
        if transition.pathWaypoints.isEmpty {
            return (
                0,
                transition.pathControlPoint ?? midpoint(from: start, to: end)
            )
        }

        let nodes = PathCalculations.waypointNodes(
            from: start,
            to: end,
            waypoints: transition.pathWaypoints
        )
        guard nodes.count >= 2 else {
            return (transition.pathWaypoints.count, midpoint(from: start, to: end))
        }

        var bestSegmentIndex = 0
        var bestLengthSquared = CGFloat.zero
        for index in 0..<(nodes.count - 1) {
            let dx = nodes[index + 1].x - nodes[index].x
            let dy = nodes[index + 1].y - nodes[index].y
            let lengthSquared = dx * dx + dy * dy
            if lengthSquared > bestLengthSquared {
                bestLengthSquared = lengthSquared
                bestSegmentIndex = index
            }
        }

        return (
            min(bestSegmentIndex, transition.pathWaypoints.count),
            midpoint(from: nodes[bestSegmentIndex], to: nodes[bestSegmentIndex + 1])
        )
    }

    private static func midpoint(from start: CGPoint, to end: CGPoint) -> CGPoint {
        CGPoint(
            x: (start.x + end.x) / 2,
            y: (start.y + end.y) / 2
        )
    }
}

@MainActor
enum TransitionPathSelectionEditing {
    static func anchorAthleteID(for selectedAthleteIDs: Set<UUID>, in player: TransitionPlayer) -> UUID? {
        if selectedAthleteIDs.count == 1 {
            return selectedAthleteIDs.first
        }

        return player.transitionSpec.athleteTransitions
            .map(\.athleteID)
            .first { selectedAthleteIDs.contains($0) }
            ?? player.startAthletes.first { selectedAthleteIDs.contains($0.id) }?.id
    }

    @discardableResult
    static func addWaypoint(
        store: RoutineStore,
        player: TransitionPlayer,
        startFormationID: UUID,
        endFormationID: UUID,
        selectedAthleteIDs: Set<UUID>,
        anchorAthleteID explicitAnchorAthleteID: UUID? = nil,
        point explicitPoint: CGPoint? = nil,
        segmentIndex explicitSegmentIndex: Int? = nil
    ) -> UUID? {
        guard
            let anchorAthleteID = explicitAnchorAthleteID ?? anchorAthleteID(
                for: selectedAthleteIDs,
                in: player
            )
        else { return nil }

        var transitionSpec = store.transitionSpec(for: startFormationID, to: endFormationID)
        guard let waypointID = addWaypoint(
            to: &transitionSpec,
            player: player,
            selectedAthleteIDs: selectedAthleteIDs,
            anchorAthleteID: anchorAthleteID,
            point: explicitPoint,
            segmentIndex: explicitSegmentIndex
        ) else { return nil }

        store.mutateTransitionSpec(from: startFormationID, to: endFormationID) { spec in
            spec = transitionSpec
        }
        return waypointID
    }

    @discardableResult
    static func addWaypoint(
        to transitionSpec: inout TransitionSpec,
        player: TransitionPlayer,
        selectedAthleteIDs: Set<UUID>,
        anchorAthleteID: UUID,
        point explicitPoint: CGPoint? = nil,
        segmentIndex explicitSegmentIndex: Int? = nil
    ) -> UUID? {
        guard
            let startAthlete = player.startAthletes.first(where: { $0.id == anchorAthleteID }),
            let endAthlete = player.endAthletes.first(where: { $0.id == anchorAthleteID })
        else { return nil }

        let transition = transitionSpec.athleteTransition(for: anchorAthleteID)
        let placement: (index: Int, point: CGPoint)
        if let explicitPoint {
            placement = (
                index: explicitSegmentIndex ?? transition.pathWaypoints.count,
                point: clampedPathPoint(explicitPoint)
            )
        } else {
            placement = PathWaypointPlacement.defaultPlacement(
                transition: transition,
                start: startAthlete.position,
                end: endAthlete.position
            )
        }
        let waypoint = PathWaypoint(position: clampedPathPoint(placement.point), isSmooth: true)

        if selectedAthleteIDs.count > 1, selectedAthleteIDs.contains(anchorAthleteID) {
            let startsByID = Dictionary(uniqueKeysWithValues: player.startAthletes.map { ($0.id, $0.position) })
            let memberIDs = selectedAthleteIDs
            guard let anchorIndex = transitionSpec.athleteTransitions.firstIndex(where: {
                $0.athleteID == anchorAthleteID
            }) else { return nil }
            var anchorWaypoints = transitionSpec.athleteTransitions[anchorIndex].pathWaypoints
            let insertionIndex = max(0, min(placement.index, anchorWaypoints.count))
            anchorWaypoints.insert(waypoint, at: insertionIndex)
            let didInsert = transitionSpec.applyRelativePathWaypoints(
                anchorAthleteID: anchorAthleteID,
                memberIDs: memberIDs,
                anchorWaypoints: anchorWaypoints,
                startPositionsByAthleteID: startsByID
            )
            return didInsert ? waypoint.id : nil
        }

        let anchorIndex: Int
        if let existingIndex = transitionSpec.athleteTransitions.firstIndex(where: {
            $0.athleteID == anchorAthleteID
        }) {
            anchorIndex = existingIndex
        } else {
            transitionSpec.athleteTransitions.append(AthleteTransition(athleteID: anchorAthleteID))
            anchorIndex = transitionSpec.athleteTransitions.count - 1
        }
        let insertionIndex = max(
            0,
            min(placement.index, transitionSpec.athleteTransitions[anchorIndex].pathWaypoints.count)
        )
        transitionSpec.athleteTransitions[anchorIndex].pathControlPoint = nil
        transitionSpec.athleteTransitions[anchorIndex].pathWaypoints.insert(
            waypoint,
            at: insertionIndex
        )
        return waypoint.id
    }

    @discardableResult
    static func moveWaypoint(
        in transitionSpec: inout TransitionSpec,
        player: TransitionPlayer,
        selectedAthleteIDs: Set<UUID>,
        anchorAthleteID: UUID,
        waypointID: UUID,
        point: CGPoint
    ) -> Bool {
        let pathPoint = clampedPathPoint(point)
        if selectedAthleteIDs.count > 1, selectedAthleteIDs.contains(anchorAthleteID) {
            let startsByID = Dictionary(uniqueKeysWithValues: player.startAthletes.map { ($0.id, $0.position) })
            let memberIDs = selectedAthleteIDs
            guard
                let anchorIndex = transitionSpec.athleteTransitions.firstIndex(where: {
                    $0.athleteID == anchorAthleteID
                }),
                let waypointIndex = transitionSpec.athleteTransitions[anchorIndex]
                    .pathWaypoints.firstIndex(where: { $0.id == waypointID }),
                transitionSpec.athleteTransitions[anchorIndex]
                    .pathWaypoints[waypointIndex].position != pathPoint
            else { return false }

            var anchorWaypoints = transitionSpec.athleteTransitions[anchorIndex].pathWaypoints
            anchorWaypoints[waypointIndex].position = pathPoint
            return transitionSpec.applyRelativePathWaypoints(
                anchorAthleteID: anchorAthleteID,
                memberIDs: memberIDs,
                anchorWaypoints: anchorWaypoints,
                startPositionsByAthleteID: startsByID
            )
        }

        guard
            let anchorIndex = transitionSpec.athleteTransitions.firstIndex(where: {
                $0.athleteID == anchorAthleteID
            }),
            let waypointIndex = transitionSpec.athleteTransitions[anchorIndex]
                .pathWaypoints.firstIndex(where: { $0.id == waypointID }),
            transitionSpec.athleteTransitions[anchorIndex]
                .pathWaypoints[waypointIndex].position != pathPoint
        else { return false }

        transitionSpec.athleteTransitions[anchorIndex]
            .pathWaypoints[waypointIndex].position = pathPoint
        return true
    }

    private static func clampedPathPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: max(0, min(CourtConstants.width, point.x)),
            y: max(0, min(CourtConstants.height, point.y))
        )
    }
}
