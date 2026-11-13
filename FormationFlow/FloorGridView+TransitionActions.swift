import SwiftUI

extension FloorGridView {
    // MARK: - Transition Actions

    private func clearPath() {
        guard let selectedAthleteID, let startFormationID, let endFormationID else { return }
        recentPathEditSnapshot = nil
        store.mutateAthleteTransition(from: startFormationID, to: endFormationID, athleteID: selectedAthleteID) { t in
            t.pathControlPoint = nil
            t.pathWaypoints = []
        }
        refreshTransitionFromStore()
    }

    private func ensureCurve() {
        guard let selectedAthleteID, let startFormationID, let endFormationID, let player else { return }
        recentPathEditSnapshot = nil
        let startAthlete = player.startAthletes.first(where: { $0.id == selectedAthleteID })
        let endAthlete = player.endAthletes.first(where: { $0.id == selectedAthleteID })
        guard let startAthlete, let endAthlete else { return }

        store.mutateAthleteTransition(from: startFormationID, to: endFormationID, athleteID: selectedAthleteID) { t in
            guard t.pathControlPoint == nil && t.pathWaypoints.isEmpty else { return }
            let midpoint = CGPoint(
                x: (startAthlete.position.x + endAthlete.position.x) / 2,
                y: (startAthlete.position.y + endAthlete.position.y) / 2
            )
            t.pathControlPoint = CGPoint(x: midpoint.x, y: midpoint.y - 6)
        }
        refreshTransitionFromStore()
    }

    private func addWaypoint(anchorAthleteID: UUID? = nil) {
        guard entitlementManager.isPro else {
            showingUpgradeSheet = true
            return
        }
        recentPathEditSnapshot = nil
        guard let player else { return }
        guard let anchorAthleteID = anchorAthleteID ?? TransitionPathSelectionEditing.anchorAthleteID(
            for: selectedAthleteIDs,
            in: player
        ) else { return }
        let startAthlete = player.startAthletes.first(where: { $0.id == anchorAthleteID })
        let endAthlete = player.endAthletes.first(where: { $0.id == anchorAthleteID })
        guard let startAthlete, let endAthlete else { return }
        let transition = player.transitionSpec.athleteTransition(for: anchorAthleteID)
        let placement = PathWaypointPlacement.defaultPlacement(
            transition: transition,
            start: startAthlete.position,
            end: endAthlete.position
        )

        _ = insertWaypoint(
            anchorAthleteID: anchorAthleteID,
            at: placement.point,
            segmentIndex: placement.index
        )
    }

    private func insertWaypoint(anchorAthleteID: UUID? = nil, at point: CGPoint, segmentIndex: Int) -> UUID? {
        guard entitlementManager.isPro else {
            showingUpgradeSheet = true
            return nil
        }
        recentPathEditSnapshot = nil
        guard let startFormationID, let endFormationID, let player else { return nil }
        let waypointID = TransitionPathSelectionEditing.addWaypoint(
            store: store,
            player: player,
            startFormationID: startFormationID,
            endFormationID: endFormationID,
            selectedAthleteIDs: selectedAthleteIDs,
            anchorAthleteID: anchorAthleteID,
            point: clampedPathPoint(point),
            segmentIndex: segmentIndex
        )
        refreshTransitionFromStore()
        return waypointID
    }

    private func cycleWaypointByDoubleTap(at point: CGPoint, cellSize: CGFloat) -> Bool {
        guard hasTransition, let selectedAthleteID, let player else { return false }
        let transition = player.transitionSpec.athleteTransition(for: selectedAthleteID)
        let hitRadiusSquared = interactionHitRadiusSquared(for: cellSize) * 1.5

        let candidates = transition.pathWaypoints
            .enumerated()
            .compactMap { index, waypoint -> (index: Int, waypoint: PathWaypoint, distance: CGFloat)? in
                let distance = PathCalculations.squaredDistance(from: point, to: waypoint.position)
                guard distance < hitRadiusSquared else { return nil }
                return (index, waypoint, distance)
            }
            .sorted {
                if abs($0.distance - $1.distance) > 0.0001 {
                    return $0.distance < $1.distance
                }
                return $0.index < $1.index
            }

        guard !candidates.isEmpty else { return false }

        if let focusedIndex = focusedWaypointIndex(in: transition) {
            if let currentCandidateIndex = candidates.firstIndex(where: { $0.index == focusedIndex }),
               candidates.count > 1 {
                focusWaypoint(candidates[(currentCandidateIndex + 1) % candidates.count].waypoint)
                return true
            }

            if candidates.count == 1, candidates[0].index == focusedIndex {
                let waypoint = transition.pathWaypoints[focusedIndex]
                if waypoint.isSmooth {
                    setWaypointSmooth(id: waypoint.id, isSmooth: false)
                    focusWaypoint(waypoint)
                } else {
                    deleteWaypoint(id: waypoint.id)
                }
                return true
            }

            if transition.pathWaypoints.count > 1 {
                let nextIndex = (focusedIndex + 1) % transition.pathWaypoints.count
                focusWaypoint(transition.pathWaypoints[nextIndex])
                return true
            }
        }

        focusWaypoint(candidates[0].waypoint)
        return true
    }

    private func focusWaypoint(_ waypoint: PathWaypoint) {
        guard let selectedAthleteID else { return }
        focusedEndpoint = currentFormationEndpoint
        focusedPathHandle = waypoint.position
        hoveredPathAthleteID = selectedAthleteID
    }

    private func setWaypointSmooth(id waypointID: UUID, isSmooth: Bool) {
        guard let selectedAthleteID, let startFormationID, let endFormationID else { return }

        store.mutateAthleteTransition(from: startFormationID, to: endFormationID, athleteID: selectedAthleteID) { t in
            guard let waypointIndex = t.pathWaypoints.firstIndex(where: { $0.id == waypointID }) else { return }
            t.pathWaypoints[waypointIndex].isSmooth = isSmooth
        }
        refreshTransitionFromStore()
    }

    private func focusedWaypointIndex(in transition: AthleteTransition) -> Int? {
        guard let focusedPathHandle else { return nil }
        return transition.pathWaypoints.firstIndex {
            PathCalculations.squaredDistance(from: focusedPathHandle, to: $0.position) < 1.0
        }
    }

    private func deleteWaypoint(id waypointID: UUID) {
        guard let selectedAthleteID, let startFormationID, let endFormationID else { return }
        pendingWaypointDeletionID = nil
        focusedPathHandle = nil

        store.mutateAthleteTransition(from: startFormationID, to: endFormationID, athleteID: selectedAthleteID) { t in
            t.pathWaypoints.removeAll { $0.id == waypointID }
        }
        refreshTransitionFromStore()
    }

    private func deletePendingWaypoint() {
        guard
            let waypointID = pendingWaypointDeletionID
        else {
            pendingWaypointDeletionID = nil
            return
        }

        deleteWaypoint(id: waypointID)
    }

    private func resetSelectedPaths() {
        recentPathEditSnapshot = nil
        if selectedAthleteIDs.count == 1, let athleteID = selectedAthleteIDs.first {
            resetPath(for: athleteID)
        } else if !selectedAthleteIDs.isEmpty {
            resetPaths(for: selectedAthleteIDs)
        } else {
            resetAllPaths()
        }
    }

    private func resetPathForSelectedAthlete() {
        guard let selectedAthleteID else { return }
        resetPath(for: selectedAthleteID)
    }

    private func resetPath(for athleteID: UUID) {
        guard let startFormationID, let endFormationID else { return }
        clearTransitionDragState()
        store.mutateAthleteTransition(from: startFormationID, to: endFormationID, athleteID: athleteID) { t in
            t.pathControlPoint = nil
            t.pathWaypoints = []
        }
        refreshTransitionFromStore()
    }

    private func resetPaths(for athleteIDs: Set<UUID>) {
        guard let startFormationID, let endFormationID, !athleteIDs.isEmpty else { return }
        clearTransitionDragState()
        store.mutateTransitionSpec(from: startFormationID, to: endFormationID) { spec in
            for index in spec.athleteTransitions.indices where athleteIDs.contains(spec.athleteTransitions[index].athleteID) {
                spec.athleteTransitions[index].pathControlPoint = nil
                spec.athleteTransitions[index].pathWaypoints = []
            }
        }
        refreshTransitionFromStore()
    }

    private func resetAllPaths() {
        guard let startFormationID, let endFormationID else { return }
        clearTransitionDragState()

        store.mutateTransitionSpec(from: startFormationID, to: endFormationID) { spec in
            for index in spec.athleteTransitions.indices {
                spec.athleteTransitions[index].pathControlPoint = nil
                spec.athleteTransitions[index].pathWaypoints = []
            }
        }
        refreshTransitionFromStore()
    }

    private func clearTransitionDragState() {
        isDraggingPathHandle = false
        isDraggingEndpoint = false
        draggingWaypointID = nil
        pathDragAthleteID = nil
        pathHandleDragDraft = nil
        endpointDragStartPosition = nil
        lastAppliedEndpointDragPosition = nil
    }

    private func commitPathHandleDrag() {
        guard
            let draft = pathHandleDragDraft,
            draft.startFormationID == startFormationID,
            draft.endFormationID == endFormationID,
            draft.hasChanges
        else {
            refreshTransitionFromStore()
            return
        }

        let committedSpec = draft.transitionSpec
        store.mutateTransitionSpec(
            from: draft.startFormationID,
            to: draft.endFormationID
        ) { spec in
            spec = committedSpec
        }
        recentPathEditSnapshot = draft.undoSnapshot
        refreshTransitionFromStore()
    }

    private func refreshTransitionPreview(
        transitionSpec: TransitionSpec,
        collisionRefreshMode: PathCollisionRefreshMode
    ) {
        guard let player else { return }
        player.refresh(
            startAthletes: player.startAthletes,
            endAthletes: player.endAthletes,
            transitionSpec: transitionSpec,
            collisionRefreshMode: collisionRefreshMode
        )
    }

    private func refreshTransitionFromStore(collisionRefreshMode: PathCollisionRefreshMode = .full) {
        guard let player, let startFormationID, let endFormationID else { return }
        player.refresh(
            startAthletes: store.renderedAthletes(for: startFormationID),
            endAthletes: store.renderedAthletes(for: endFormationID),
            transitionSpec: store.transitionSpec(for: startFormationID, to: endFormationID),
            collisionRefreshMode: collisionRefreshMode
        )
    }

    private func createSelectedTransitionGroup() {
        guard hasTransition,
              canCreateSelectedTransitionGroup,
              let startFormationID,
              let endFormationID,
              selectedAthleteIDs.count >= 2 else { return }
        if let group = store.createTransitionStuntGroup(
            from: startFormationID,
            to: endFormationID,
            athleteIDs: selectedAthleteIDs
        ) {
            selectedAthleteIDs = group.athleteIDSet
            if currentFormationEndpoint == .start {
                focusedEndpoint = .end
                player?.pause()
                player?.seek(to: 1)
            } else if focusedEndpoint == nil {
                focusedEndpoint = currentFormationEndpoint
            }
            refreshTransitionFromStore()
        }
    }

    private func ungroupSelectedTransitionGroup() {
        guard hasTransition,
              let startFormationID,
              let endFormationID,
              !selectedAthleteIDs.isEmpty else { return }
        if let selectedTransitionGroup {
            store.removeTransitionStuntGroup(id: selectedTransitionGroup.id, from: startFormationID, to: endFormationID)
        } else {
            store.removeTransitionStuntGroups(containing: selectedAthleteIDs, from: startFormationID, to: endFormationID)
        }
        refreshTransitionFromStore()
    }
}
