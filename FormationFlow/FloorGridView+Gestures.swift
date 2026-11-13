import SwiftUI
import UIKit

extension FloorGridView {
    // MARK: - Unified Gesture Handler

    private func dragGesture(
        cellSize: CGFloat,
        offset: CGPoint,
        viewportSize: CGSize,
        canvasSize: CGSize
    ) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if isSwapMode { return }

                let explicitDrawPoint = CGPoint(
                    x: (value.location.x - offset.x) / cellSize,
                    y: (value.location.y - offset.y) / cellSize
                )
                if isExplicitPathDrawMode {
                    if !isSketchingPath {
                        beginExplicitPathSketch()
                    }
                    if isSketchingPath {
                        handlePathSketchContinued(explicitDrawPoint)
                    }
                    return
                }

                // Long-press arming ring: track press-down on any athlete's start/end
                // endpoint so the user sees how long the long-press needs to be held.
                // Additive — does not affect any other gesture branch.
                if longPressArmingPosition == nil, !isLongPressSketching {
                    let startScaled = CGPoint(
                        x: (value.startLocation.x - offset.x) / cellSize,
                        y: (value.startLocation.y - offset.y) / cellSize
                    )
                    let anchor: CGPoint?
                    if let hit = athleteEndpointHit(at: startScaled, cellSize: cellSize) {
                        anchor = hit.anchor
                    } else if let bootstrap = bootstrapAthleteHit(at: startScaled, cellSize: cellSize) {
                        anchor = bootstrap.anchor
                    } else {
                        anchor = nil
                    }
                    if let anchor {
                        armLongPressCountdown(at: anchor)
                    }
                } else if longPressArmingPosition != nil, !isLongPressSketching {
                    // Cancel arming if the touch moves far enough to become an
                    // intentional drag — keeps ring visibility in sync with
                    // whether the sketch will actually arm.
                    let dx = value.translation.width
                    let dy = value.translation.height
                    if dx * dx + dy * dy > pathSketchHoldTolerance * pathSketchHoldTolerance {
                        cancelLongPressCountdown()
                    }
                }

                if isLongPressSketching { return }

                let hitRadiusSquared = interactionHitRadiusSquared(for: cellSize)
                let dragDistanceSquared = value.translation.width * value.translation.width + value.translation.height * value.translation.height
                let dragActivationDistanceSquared = dragActivationDistance * dragActivationDistance
                let startScaledPoint = CGPoint(
                    x: (value.startLocation.x - offset.x) / cellSize,
                    y: (value.startLocation.y - offset.y) / cellSize
                )
                let scaledPoint = CGPoint(
                    x: (value.location.x - offset.x) / cellSize,
                    y: (value.location.y - offset.y) / cellSize
                )

                // Priority 1: Continue in-progress drags
                if isDraggingPathHandle {
                    handlePathDragContinued(scaledPoint: scaledPoint)
                    return
                }
                if isSketchingPath {
                    handlePathSketchContinued(scaledPoint)
                    return
                }
                if isDraggingEndpoint {
                    handleEndpointDragContinued(value, cellSize: cellSize, offset: offset)
                    return
                }
                if isPanningCanvas {
                    handleCanvasPanContinued(
                        value,
                        viewportSize: viewportSize,
                        canvasSize: canvasSize
                    )
                    return
                }
                if isDraggingAthletes {
                    handleFormationDragContinued(value, cellSize: cellSize)
                    return
                }
                if isDrawingSelectionLasso {
                    handleSelectionLassoContinued(value)
                    return
                }

                // Athletes always win over path handles at the drag start point.
                let athleteAtStart: RenderedAthlete? = {
                    if let hoveredID = hoveredAthleteID,
                       let hovered = renderedAthletes.first(where: { $0.id == hoveredID }) {
                        return hovered
                    }
                    return athleteHit(at: startScaledPoint, within: renderedAthletes, cellSize: cellSize)
                }()

                // Priority 2: Focused path handle gets a large grab area.
                if athleteAtStart == nil,
                   let focusedPathHandle,
                   showTransitionPaths, hasTransition
                {
                    let focusedHitRadius = hitRadiusSquared * 2
                    if PathCalculations.squaredDistance(from: startScaledPoint, to: focusedPathHandle) < focusedHitRadius,
                       let hit = selectedPathHandleHit(
                        at: startScaledPoint,
                        maxSquaredDistance: focusedHitRadius
                       ) {
                        guard dragDistanceSquared >= dragActivationDistanceSquared else { return }
                        beginPathHandleDrag(hit: hit, scaledPoint: scaledPoint)
                        return
                    }
                }

                // Priority 3: Hit-test for new drag initiation
                if showTransitionPaths, hasTransition {
                    // 3a: Path handles — selected athlete markers still win
                    // direct touches, but a selected path handle can be dragged
                    // without collapsing a stunt group selection.
                    if athleteAtStart.map({ !selectedAthleteIDs.contains($0.id) }) ?? true {
                        let waypointGrabRadius = hitRadiusSquared * 2.5
                        if let hit = selectedPathHandleHit(
                            at: startScaledPoint,
                            maxSquaredDistance: waypointGrabRadius
                        ) {
                            guard dragDistanceSquared >= dragActivationDistanceSquared else { return }
                            beginPathHandleDrag(hit: hit, scaledPoint: scaledPoint)
                            return
                        }
                    }

                    // 2b/2c: Hovered athlete wins, then closest hit
                    let targetAthlete: RenderedAthlete? = {
                        if let hoveredID = hoveredAthleteID,
                           let hovered = renderedAthletes.first(where: { $0.id == hoveredID }) {
                            return hovered
                        }
                        return athleteHit(at: startScaledPoint, within: renderedAthletes, cellSize: cellSize)
                    }()
                    if let hitAthlete = targetAthlete {
                        let dragEndpoint = displayedFormationEndpoint
                        focusedEndpoint = dragEndpoint
                        guard dragDistanceSquared >= dragActivationDistanceSquared else { return }
                        if !selectedAthleteIDs.contains(hitAthlete.id) {
                            selectedAthleteIDs = selectionForAthlete(hitAthlete.id)
                        }
                        let dragAthletes = athletes(for: dragEndpoint) ?? renderedAthletes
                        dragStartPositions = dragAthletes.reduce(into: [UUID: CGPoint]()) { result, athlete in
                            if selectedAthleteIDs.contains(athlete.id) {
                                if result[athlete.id] == nil { result[athlete.id] = athlete.position }
                            }
                        }
                        beginAthleteDragFeedback()
                        handleFormationDragContinued(value, cellSize: cellSize)
                        return
                    }

                    if let hitGroup = transitionGroupHit(
                        at: startScaledPoint,
                        within: editableAthletesForDrag(endpoint: displayedFormationEndpoint),
                        cellSize: cellSize
                    ) {
                        let dragEndpoint = displayedFormationEndpoint
                        focusedEndpoint = dragEndpoint
                        guard dragDistanceSquared >= dragActivationDistanceSquared else { return }
                        selectedAthleteIDs = hitGroup.athleteIDSet
                        let dragAthletes = editableAthletesForDrag(endpoint: dragEndpoint)
                        dragStartPositions = dragAthletes.reduce(into: [UUID: CGPoint]()) { result, athlete in
                            if selectedAthleteIDs.contains(athlete.id) {
                                if result[athlete.id] == nil { result[athlete.id] = athlete.position }
                            }
                        }
                        beginAthleteDragFeedback()
                        handleFormationDragContinued(value, cellSize: cellSize)
                        return
                    }
                } else {
                    // Not in transition mode: hovered athlete wins, then closest hit
                    let targetAthlete: RenderedAthlete? = {
                        if let hoveredID = hoveredAthleteID,
                           let hovered = renderedAthletes.first(where: { $0.id == hoveredID }) {
                            return hovered
                        }
                        return athleteHit(at: startScaledPoint, within: renderedAthletes, cellSize: cellSize)
                    }()
                    if let hitAthlete = targetAthlete {
                        focusedEndpoint = nil
                        guard dragDistanceSquared >= dragActivationDistanceSquared else { return }
                        if !selectedAthleteIDs.contains(hitAthlete.id) {
                            selectedAthleteIDs = selectionForAthlete(hitAthlete.id)
                        }
                        dragStartPositions = renderedAthletes.reduce(into: [UUID: CGPoint]()) { result, athlete in
                            if selectedAthleteIDs.contains(athlete.id) {
                                if result[athlete.id] == nil { result[athlete.id] = athlete.position }
                            }
                        }
                        beginAthleteDragFeedback()
                        handleFormationDragContinued(value, cellSize: cellSize)
                        return
                    }
                }

                // 2c: Endpoint markers — only allow dragging markers from the current formation
                if hasTransition {
                    if let hitMarker = endpointMarkerHit(
                        at: startScaledPoint,
                        within: endpointMarkers,
                        hitRadiusSquared: hitRadiusSquared
                    ) {
                        selectedAthleteIDs = selectionForAthlete(hitMarker.athleteID)
                        focusedEndpoint = hitMarker.endpoint
                        endpointDragStartPosition = hitMarker.position
                        guard dragDistanceSquared >= dragActivationDistanceSquared else { return }
                        isDraggingEndpoint = true
                        handleEndpointDragContinued(value, cellSize: cellSize, offset: offset)
                        return
                    }
                }

                // 2d: Empty space → pan if zoomed on compact, otherwise selection box
                focusedEndpoint = hasTransition ? currentFormationEndpoint : nil
                guard dragDistanceSquared >= dragActivationDistanceSquared else { return }

                if canPanCanvas(viewportSize: viewportSize, canvasSize: canvasSize) {
                    isPanningCanvas = true
                    handleCanvasPanContinued(
                        value,
                        viewportSize: viewportSize,
                        canvasSize: canvasSize
                    )
                    return
                }

                if shouldSuppressMarqueeForSelectedPathNearMiss(at: startScaledPoint, cellSize: cellSize) {
                    return
                }

                selectionLasso = FloorSelectionLasso(startPoint: value.startLocation)
                isDrawingSelectionLasso = true
                handleSelectionLassoContinued(value)
            }
            .onEnded { value in
                let hitRadiusSquared = interactionHitRadiusSquared(for: cellSize)
                // The long-press sketch gesture and this drag gesture share the same
                // touch and both fire onEnded in an undefined order. When the touch was
                // a long-press sketch, endLongPressSketch() owns the commit and cleanup —
                // this gesture must NOT commit (double-commit), wipe pathSketchPoints
                // (clobbering a not-yet-run endLongPressSketch), or fall through to tap
                // handling (which clears the selection). Capture the fact up front so the
                // decision is the same whichever onEnded ran first.
                let wasLongPressSketch = isLongPressSketching || didConsumeLongPressTouch
                defer {
                    isDraggingAthletes = false
                    isDraggingEndpoint = false
                    isDraggingPathHandle = false
                    isPanningCanvas = false
                    draggingWaypointID = nil
                    pathDragAthleteID = nil
                    pathHandleDragDraft = nil
                    if !wasLongPressSketch {
                        isSketchingPath = false
                        pathSketchPoints = []
                    }
                    isDrawingSelectionLasso = false
                    selectionLasso = nil
                    dragStartPositions = [:]
                    lastAppliedFormationDragPositions = [:]
                    lastAppliedEndpointDragPosition = nil
                    draggingAthleteIDs = []
                    endpointDragStartPosition = nil
                    clearActiveGuides()
                    // If the press lifted before the long-press armed, fade out the ring.
                    // endLongPressSketch() handles its own cleanup when sketching arms.
                    if !isLongPressSketching, longPressArmingPosition != nil {
                        cancelLongPressCountdown()
                    }
                    store.saveNow()
                }

                if wasLongPressSketch {
                    didConsumeLongPressTouch = false
                    return
                }

                if isSwapMode, let swapSourceAthleteID {
                    let tapPoint = CGPoint(
                        x: (value.location.x - offset.x) / cellSize,
                        y: (value.location.y - offset.y) / cellSize
                    )

                    // Determine which formation to swap in and which athletes to hit-test
                    let swapFormationID: UUID
                    let swapAthletes: [RenderedAthlete]

                    if hasTransition, let player,
                       let resolvedSwapID = swapFormationTarget == .start ? startFormationID : endFormationID {
                        swapFormationID = resolvedSwapID
                        swapAthletes = swapFormationTarget == .start ? player.startAthletes : player.endAthletes
                    } else {
                        swapFormationID = formationID
                        swapAthletes = renderedAthletes
                    }

                    if let targetAthlete = athleteHit(
                        at: tapPoint,
                        within: swapAthletes,
                        cellSize: cellSize,
                        excluding: swapSourceAthleteID
                    ) {
                        store.swapPositions(in: swapFormationID, id1: swapSourceAthleteID, id2: targetAthlete.id)
                        selectedAthleteIDs = selectionForAthlete(targetAthlete.id)
                        refreshTransitionFromStore()
                    }
                    endSwapMode()
                    return
                }

                if isDraggingAthletes, !dragStartPositions.isEmpty {
                    appendUndoSnapshot(positions: dragStartPositions)
                    refreshTransitionFromStore()
                    // A real move happened (drag cleared the activation threshold) —
                    // keep the moved selection intact. Falling through to tap-handling
                    // below would collapse a multi-athlete group down to the single
                    // athlete under the finger.
                    return
                }

                if isDraggingEndpoint {
                    refreshTransitionFromStore()
                }

                if isDraggingPathHandle {
                    commitPathHandleDrag()
                    return
                }

                if isSketchingPath {
                    if let athleteID = bootstrapAthleteID {
                        if commitBootstrapSketch(athleteID: athleteID) {
                            isExplicitPathDrawMode = false
                            return
                        }
                        // Held-tap with no meaningful path — keep this athlete
                        // selected and let the rest of onEnded run normally.
                        selectedAthleteIDs = selectionForAthlete(athleteID)
                        isExplicitPathDrawMode = false
                        return
                    }
                    _ = finishPathSketch()
                    isExplicitPathDrawMode = false
                    return
                }

                if isPanningCanvas {
                    lastCanvasPanOffset = canvasPanOffset
                    return
                }

                if isDrawingSelectionLasso, var selectionLasso {
                    selectionLasso.append(value.location, minimumDistance: 0)
                    var newSelection = Set(
                        renderedAthletes.compactMap { athlete in
                            let screenPoint = CGPoint(
                                x: athlete.position.x * cellSize + offset.x,
                                y: athlete.position.y * cellSize + offset.y
                            )
                            return selectionLasso.contains(screenPoint) ? athlete.id : nil
                        }
                    )
                    for group in activeTransitionGroups where !group.athleteIDSet.isDisjoint(with: newSelection) {
                        newSelection.formUnion(group.athleteIDSet)
                    }

                    if selectionLasso.isTapCandidate {
                        // Tap on empty space — also try selecting from transition athletes
                        let tapPoint = CGPoint(
                            x: (value.location.x - offset.x) / cellSize,
                            y: (value.location.y - offset.y) / cellSize
                        )
                        if showTransitionPaths, hasTransition, let player {
                            if let athlete = nearestOrTiedCycledAthleteHit(
                                at: tapPoint,
                                within: player.currentAthletes,
                                cellSize: cellSize
                            ) {
                                selectedAthleteIDs = selectionForAthlete(athlete.id)
                                return
                            }
                        }
                        selectedAthleteIDs = []
                    } else {
                        selectedAthleteIDs = newSelection
                    }
                    return
                }

                let tapPoint = CGPoint(
                    x: (value.location.x - offset.x) / cellSize,
                    y: (value.location.y - offset.y) / cellSize
                )
                let startScaledPoint = CGPoint(
                    x: (value.startLocation.x - offset.x) / cellSize,
                    y: (value.startLocation.y - offset.y) / cellSize
                )

                // Athletes always win taps. Selecting an athlete is how you
                // choose whose path to edit, so it must never be blocked by the
                // currently-selected athlete's path handle or path line sitting
                // nearby (the old "force field"). Tap an athlete → it's selected;
                // its waypoint handles are then dragged directly.

                // If an athlete is hovered, tapping selects exactly that athlete
                if let hoveredID = hoveredAthleteID,
                   renderedAthletes.contains(where: { $0.id == hoveredID }) {
                    selectedAthleteIDs = selectionForAthlete(hoveredID)
                    focusedEndpoint = hasTransition ? displayedFormationEndpoint : nil
                    focusedPathHandle = nil
                    return
                }

                if let athlete = nearestOrTiedCycledAthleteHit(
                    at: tapPoint,
                    within: renderedAthletes,
                    cellSize: cellSize
                ) ?? nearestOrTiedCycledAthleteHit(
                    at: startScaledPoint,
                    within: renderedAthletes,
                    cellSize: cellSize
                ) {
                    selectedAthleteIDs = selectionForAthlete(athlete.id)
                    focusedEndpoint = hasTransition ? displayedFormationEndpoint : nil
                    focusedPathHandle = nil
                    return
                }

                if hasTransition,
                   let hitGroup = transitionGroupHit(
                    at: tapPoint,
                    within: editableAthletesForDrag(endpoint: displayedFormationEndpoint),
                    cellSize: cellSize
                   ) ?? transitionGroupHit(
                    at: startScaledPoint,
                    within: editableAthletesForDrag(endpoint: displayedFormationEndpoint),
                    cellSize: cellSize
                   ) {
                    selectedAthleteIDs = hitGroup.athleteIDSet
                    focusedEndpoint = displayedFormationEndpoint
                    focusedPathHandle = nil
                    return
                }

                // No athlete under the tap — now allow focusing the selected
                // athlete's path / waypoint handle (empty-space taps on the line).
                if showTransitionPaths {
                    if let handle = nearestPathHandle(at: tapPoint, cellSize: cellSize)
                        ?? nearestPathHandle(at: startScaledPoint, cellSize: cellSize)
                    {
                        focusedEndpoint = currentFormationEndpoint
                        focusedPathHandle = handle
                        return
                    }

                    if let hit = selectedTransitionPathHit(
                        at: tapPoint,
                        maxSquaredDistance: pathHitRadiusSquared(for: cellSize)
                    ) ?? selectedTransitionPathHit(
                        at: startScaledPoint,
                        maxSquaredDistance: pathHitRadiusSquared(for: cellSize)
                    ) {
                        focusedEndpoint = currentFormationEndpoint
                        focusedPathHandle = nil
                        hoveredPathAthleteID = hit.transition.athleteID
                        return
                    }
                }

                if endpointMarkerHit(at: tapPoint, within: endpointMarkers, hitRadiusSquared: hitRadiusSquared) != nil
                    || endpointMarkerHit(
                        at: startScaledPoint,
                        within: endpointMarkers,
                        hitRadiusSquared: hitRadiusSquared
                    ) != nil
                {
                    return
                }

                selectedAthleteIDs = []
                focusedEndpoint = hasTransition ? currentFormationEndpoint : nil
                focusedPathHandle = nil
            }
    }

    // MARK: - Drag Helpers

    private func transitionGroup(containing athleteID: UUID) -> TransitionStuntGroup? {
        activeTransitionGroups.first { $0.athleteIDs.contains(athleteID) }
    }

    private func selectionForAthlete(_ athleteID: UUID) -> Set<UUID> {
        transitionGroup(containing: athleteID)?.athleteIDSet ?? [athleteID]
    }

    private func transitionGroupHit(
        at point: CGPoint,
        within athletes: [RenderedAthlete],
        cellSize: CGFloat
    ) -> TransitionStuntGroup? {
        guard !activeTransitionGroups.isEmpty else { return nil }
        let athletesByID = Dictionary(uniqueKeysWithValues: athletes.map { ($0.id, $0) })

        for group in activeTransitionGroups {
            let members = group.athleteIDs.compactMap { athletesByID[$0] }
            guard members.count >= 2 else { continue }
            let xs = members.map { $0.position.x }
            let ys = members.map { $0.position.y }
            guard
                let minX = xs.min(),
                let maxX = xs.max(),
                let minY = ys.min(),
                let maxY = ys.max()
            else { continue }

            let padding = max(1.4, 18 / max(cellSize, 1))
            let rect = CGRect(
                x: minX - padding,
                y: minY - padding,
                width: max(maxX - minX + padding * 2, padding * 2),
                height: max(maxY - minY + padding * 2, padding * 2)
            )
            if rect.contains(point) {
                return group
            }
        }
        return nil
    }

    private func editableAthletesForDrag(endpoint: PreviewEditableEndpoint?) -> [RenderedAthlete] {
        if let endpoint, let athletes = athletes(for: endpoint) {
            return athletes
        }
        return renderedAthletes
    }

    private func interactionHitRadiusSquared(for cellSize: CGFloat) -> CGFloat {
        // Selection hit-testing deliberately stays tighter than the 44pt
        // accessibility overlay so nearby athletes/handles/waypoints don't
        // steal taps from the item closest to the finger. Collision detection
        // lives in PathCalculations and does not use this radius.
        let minimumTouchRadius: CGFloat = isCompactLayout ? 14 : 11
        let cellAdjustedRadius = minimumTouchRadius / max(cellSize, 1)
        let defaultRadius: CGFloat = 1.15
        let radius = max(defaultRadius, cellAdjustedRadius)
        return radius * radius
    }


    private func canPanCanvas(viewportSize: CGSize, canvasSize: CGSize) -> Bool {
        let overflowWidth = canvasSize.width - viewportSize.width
        let overflowHeight = canvasSize.height - viewportSize.height
        return overflowWidth > 1 || overflowHeight > 1
    }

    private func clearActiveGuides() {
        activeAlignmentGuides = []
        activeMirrorGuides = []
    }

    private func beginAthleteDragFeedback() {
        guard !isDraggingAthletes else { return }
        isDraggingAthletes = true
        lastAppliedFormationDragPositions = dragStartPositions
        draggingAthleteIDs = selectedAthleteIDs
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred(intensity: 0.7)
    }

    private func appendUndoSnapshot(positions: [UUID: CGPoint]) {
        guard !positions.isEmpty else { return }
        undoStack.append(
            FormationMoveUndoSnapshot(
                formationID: displayedEditableFormationID,
                positions: positions
            )
        )
    }

    private func clampedCanvasPanOffset(
        _ proposedOffset: CGSize,
        viewportSize: CGSize,
        canvasSize: CGSize
    ) -> CGSize {
        let maxX = max(0, (canvasSize.width - viewportSize.width) / 2)
        let maxY = max(0, (canvasSize.height - viewportSize.height) / 2)

        return CGSize(
            width: min(max(proposedOffset.width, -maxX), maxX),
            height: min(max(proposedOffset.height, -maxY), maxY)
        )
    }

    private func handleCanvasPanContinued(
        _ value: DragGesture.Value,
        viewportSize: CGSize,
        canvasSize: CGSize
    ) {
        clearActiveGuides()
        canvasPanOffset = clampedCanvasPanOffset(
            CGSize(
                width: lastCanvasPanOffset.width + value.translation.width,
                height: lastCanvasPanOffset.height + value.translation.height
            ),
            viewportSize: viewportSize,
            canvasSize: canvasSize
        )
    }

    private func selectedPathHandleHit(
        at point: CGPoint,
        maxSquaredDistance: CGFloat
    ) -> PathHandleHit? {
        guard hasTransition, !selectedAthleteIDs.isEmpty, let player else { return nil }

        var bestHit: PathHandleHit?
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for item in transitionPaths where selectedAthleteIDs.contains(item.athleteID) {
            let transition = player.transitionSpec.athleteTransition(for: item.athleteID)
            let candidates: [(waypointID: UUID?, position: CGPoint)]

            if transition.pathWaypoints.isEmpty {
                let midpoint: CGPoint
                if let controlPoint = transition.pathControlPoint {
                    midpoint = PathCalculations.quadraticBezierPoint(
                        from: item.startPosition,
                        control: controlPoint,
                        to: item.endPosition,
                        t: 0.5
                    )
                } else {
                    midpoint = CGPoint(
                        x: (item.startPosition.x + item.endPosition.x) / 2,
                        y: (item.startPosition.y + item.endPosition.y) / 2
                    )
                }
                candidates = [(waypointID: nil, position: midpoint)]
            } else {
                candidates = transition.pathWaypoints.map { waypoint in
                    (waypointID: waypoint.id, position: waypoint.position)
                }
            }

            for candidate in candidates {
                let distance = PathCalculations.squaredDistance(from: point, to: candidate.position)
                guard distance < maxSquaredDistance, distance < bestDistance else { continue }
                bestDistance = distance
                bestHit = PathHandleHit(
                    athleteID: item.athleteID,
                    waypointID: candidate.waypointID,
                    position: candidate.position
                )
            }
        }

        return bestHit
    }

    private func beginPathHandleDrag(hit: PathHandleHit, scaledPoint: CGPoint) {
        guard let startFormationID, let endFormationID, let player else { return }

        let affectedAthleteIDs: Set<UUID>
        if selectedAthleteIDs.count > 1, selectedAthleteIDs.contains(hit.athleteID) {
            affectedAthleteIDs = selectedAthleteIDs
        } else {
            affectedAthleteIDs = [hit.athleteID]
        }
        let message = affectedAthleteIDs.count > 1
            ? "Paths adjusted for \(affectedAthleteIDs.count) athletes"
            : "Path adjusted"
        let draft = PathHandleDragDraft(
            startFormationID: startFormationID,
            endFormationID: endFormationID,
            transitionSpec: store.transitionSpec(for: startFormationID, to: endFormationID),
            undoSnapshot: makePathEditUndoSnapshot(
                affectedAthleteIDs: affectedAthleteIDs,
                message: message
            )
        )

        let didMaterializeWaypoint = hit.waypointID == nil
        var waypointID = hit.waypointID
        if waypointID == nil {
            waypointID = TransitionPathSelectionEditing.addWaypoint(
                to: &draft.transitionSpec,
                player: player,
                selectedAthleteIDs: selectedAthleteIDs,
                anchorAthleteID: hit.athleteID,
                point: clampedPathPoint(scaledPoint),
                segmentIndex: 0
            )
        }
        guard let waypointID else { return }

        pathDragAthleteID = hit.athleteID
        draggingWaypointID = waypointID
        pathHandleDragDraft = draft
        isDraggingPathHandle = true
        focusedEndpoint = displayedFormationEndpoint
        focusedPathHandle = scaledPoint
        if didMaterializeWaypoint {
            refreshTransitionPreview(
                transitionSpec: draft.transitionSpec,
                collisionRefreshMode: .interactivePreview
            )
        }
        handlePathDragContinued(scaledPoint: scaledPoint)
    }

    private func transitionHandleIsHit(at point: CGPoint, hitRadiusSquared: CGFloat) -> Bool {
        guard hasTransition, let selectedAthleteID, let player else { return false }

        let transition = player.transitionSpec.athleteTransition(for: selectedAthleteID)
        let startAthlete = player.startAthletes.first(where: { $0.id == selectedAthleteID })
        let endAthlete = player.endAthletes.first(where: { $0.id == selectedAthleteID })

        if transition.pathWaypoints.contains(where: {
            PathCalculations.squaredDistance(from: point, to: $0.position) < hitRadiusSquared
        }) {
            return true
        }

        guard transition.pathWaypoints.isEmpty, let startAthlete, let endAthlete else { return false }

        let midpoint: CGPoint
        if let controlPoint = transition.pathControlPoint {
            midpoint = PathCalculations.quadraticBezierPoint(
                from: startAthlete.position,
                control: controlPoint,
                to: endAthlete.position,
                t: 0.5
            )
        } else {
            midpoint = CGPoint(
                x: (startAthlete.position.x + endAthlete.position.x) / 2,
                y: (startAthlete.position.y + endAthlete.position.y) / 2
            )
        }

        return PathCalculations.squaredDistance(from: point, to: midpoint) < hitRadiusSquared
    }

    private func nearestPathHandle(at point: CGPoint, cellSize: CGFloat) -> CGPoint? {
        let hitRadiusSquared = interactionHitRadiusSquared(for: cellSize) * 1.5
        return selectedPathHandleHit(at: point, maxSquaredDistance: hitRadiusSquared)?.position
    }

    private func handlePathDragContinued(scaledPoint: CGPoint) {
        let anchorAthleteID = pathDragAthleteID ?? selectedAthleteID
        guard
            let anchorAthleteID,
            let draggingWaypointID,
            let draft = pathHandleDragDraft,
            let player
        else { return }

        clearActiveGuides()
        let pathPoint = clampedPathPoint(scaledPoint)
        guard TransitionPathSelectionEditing.moveWaypoint(
            in: &draft.transitionSpec,
            player: player,
            selectedAthleteIDs: selectedAthleteIDs,
            anchorAthleteID: anchorAthleteID,
            waypointID: draggingWaypointID,
            point: pathPoint
        ) else { return }

        focusedPathHandle = pathPoint
        refreshTransitionPreview(
            transitionSpec: draft.transitionSpec,
            collisionRefreshMode: .interactivePreview
        )
    }

    private func clampedPathPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: max(0, min(CourtConstants.width, point.x)),
            y: max(0, min(CourtConstants.height, point.y))
        )
    }

    private func handleEndpointDragContinued(
        _ value: DragGesture.Value,
        cellSize: CGFloat,
        offset: CGPoint
    ) {
        guard let selectedAthleteID, let editableFormationID, let endpointDragStartPosition else { return }

        let rawTranslation = CGPoint(
            x: value.translation.width / cellSize,
            y: value.translation.height / cellSize
        )
        let snapResult = snappingResult(
            translation: rawTranslation,
            startingPositions: [endpointDragStartPosition],
            otherAthletePositions: editableAthletes.compactMap {
                $0.id != selectedAthleteID ? $0.position : nil
            },
            skipLinearGuides: false
        )
        let newAlignmentGuides = snapResult.alignmentGuides
        let newMirrorGuides = snapResult.mirrorGuides
        if newAlignmentGuides != activeAlignmentGuides || newMirrorGuides != activeMirrorGuides {
            if !newAlignmentGuides.isEmpty || !newMirrorGuides.isEmpty {
                UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
            }
        }
        activeAlignmentGuides = newAlignmentGuides
        activeMirrorGuides = newMirrorGuides

        let nextPosition = CGPoint(
            x: clampedCoordinate(endpointDragStartPosition.x + snapResult.translation.x, upperBound: CourtConstants.width),
            y: clampedCoordinate(endpointDragStartPosition.y + snapResult.translation.y, upperBound: CourtConstants.height)
        )

        if lastAppliedEndpointDragPosition == nil {
            lastAppliedEndpointDragPosition = endpointDragStartPosition
        }
        guard nextPosition != lastAppliedEndpointDragPosition else { return }
        lastAppliedEndpointDragPosition = nextPosition

        store.mutateFormation(id: editableFormationID) { formation in
            guard let placementIndex = formation.placementIndex(for: selectedAthleteID) else { return }
            formation.placements[placementIndex].position = nextPosition
        }
        refreshTransitionFromStore(collisionRefreshMode: .interactivePreview)
    }

    private func handleFormationDragContinued(_ value: DragGesture.Value, cellSize: CGFloat) {
        let rawTranslation = CGPoint(
            x: value.translation.width / cellSize,
            y: value.translation.height / cellSize
        )
        let snapResult = snappingResult(for: rawTranslation)
        let newAlignmentGuides = snapResult.alignmentGuides
        let newMirrorGuides = snapResult.mirrorGuides
        if newAlignmentGuides != activeAlignmentGuides || newMirrorGuides != activeMirrorGuides {
            if !newAlignmentGuides.isEmpty || !newMirrorGuides.isEmpty {
                UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
            }
        }
        activeAlignmentGuides = newAlignmentGuides
        activeMirrorGuides = newMirrorGuides

        // Resolve which formation we're actually editing. In transition preview
        // the visible athletes come from player.startAthletes / player.endAthletes
        // (chosen by focusedEndpoint), which may differ from formationID — the
        // viewed formation can be either endpoint of the previewed pair.
        let editableID = displayedEditableFormationID

        let nextPositions = selectedAthleteIDs.reduce(into: [UUID: CGPoint]()) { result, athleteID in
            guard let startPosition = dragStartPositions[athleteID] else { return }
            result[athleteID] = CGPoint(
                x: clampedCoordinate(startPosition.x + snapResult.translation.x, upperBound: CourtConstants.width),
                y: clampedCoordinate(startPosition.y + snapResult.translation.y, upperBound: CourtConstants.height)
            )
        }
        guard !nextPositions.isEmpty, nextPositions != lastAppliedFormationDragPositions else { return }
        lastAppliedFormationDragPositions = nextPositions

        store.mutateFormation(id: editableID) { formation in
            for (athleteID, nextPosition) in nextPositions {
                guard let placementIndex = formation.placementIndex(for: athleteID) else { continue }
                formation.placements[placementIndex].position = nextPosition
            }
        }
        refreshTransitionFromStore(collisionRefreshMode: .interactivePreview)
    }

    // MARK: - Rotation

    /// Rotation snaps in 45° steps so groups never land at an off-grid angle.
    private var rotationSnapIncrement: CGFloat { .pi / 4 }

    /// Nearest 45° detent index for a raw gesture angle (…, -1, 0, 1, 2, …).
    private func rotationDetent(for radians: CGFloat) -> Int {
        Int((radians / rotationSnapIncrement).rounded())
    }

    private func applyRotation(angle: CGFloat) {
        guard !rotationStartPositions.isEmpty else { return }
        let editableID = displayedEditableFormationID

        // ⚡ Bolt: Eliminate redundant `.map` and intermediate arrays in O(N) path
        // Compute center of mass of the selected group using a single pass
        let sum = rotationStartPositions.values.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        let center = CGPoint(
            x: sum.x / CGFloat(rotationStartPositions.count),
            y: sum.y / CGFloat(rotationStartPositions.count)
        )

        let cosA = cos(angle)
        let sinA = sin(angle)

        store.mutateFormation(id: editableID) { formation in
            for (athleteID, startPosition) in rotationStartPositions {
                guard let placementIndex = formation.placementIndex(for: athleteID) else { continue }

                // Rotate around center
                let dx = startPosition.x - center.x
                let dy = startPosition.y - center.y
                let rotatedX = center.x + dx * cosA - dy * sinA
                let rotatedY = center.y + dx * sinA + dy * cosA

                // Snap to whole feet and clamp to court
                formation.placements[placementIndex].position = CGPoint(
                    x: clampedCoordinate(rotatedX, upperBound: CourtConstants.width),
                    y: clampedCoordinate(rotatedY, upperBound: CourtConstants.height)
                )
            }
        }
        rotationDidApplyChange = true
        refreshTransitionFromStore(collisionRefreshMode: .interactivePreview)
    }

    // MARK: - Multi-Selection Spacing

    /// A small dead zone lets an intentional two-finger twist reach the existing
    /// rotation gesture without a tiny amount of finger spread stealing it.
    private var spacingMagnificationActivationDelta: CGFloat { 0.04 }

    private func handleSpacingMagnification(_ magnification: CGFloat) {
        guard selectedAthleteIDs.count >= 2, !isSwapMode else { return }

        if spacingStartPositions.isEmpty {
            guard abs(magnification - 1) >= spacingMagnificationActivationDelta else { return }
            guard lastRotationDetent == 0 else { return }

            let selectedAthletes = editableAthletesForDrag(endpoint: displayedFormationEndpoint)
            spacingStartPositions = selectedAthletes.reduce(into: [UUID: CGPoint]()) { result, athlete in
                if selectedAthleteIDs.contains(athlete.id) {
                    result[athlete.id] = athlete.position
                }
            }
            guard spacingStartPositions.count >= 2 else {
                spacingStartPositions = [:]
                lastAppliedSpacingPositions = [:]
                return
            }
            lastAppliedSpacingPositions = spacingStartPositions

            // Once the pinch clearly wins, abandon any not-yet-snapped twist.
            rotationStartPositions = [:]
            lastRotationDetent = 0
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
        }

        spacingDidChange = applySpacingMagnification(magnification)
    }

    private func finishSpacingMagnification(_ magnification: CGFloat) {
        guard !spacingStartPositions.isEmpty else { return }

        let hadLiveMutation = lastAppliedSpacingPositions != spacingStartPositions
        spacingDidChange = applySpacingMagnification(magnification)
        if spacingDidChange {
            appendUndoSnapshot(positions: spacingStartPositions)
            UISelectionFeedbackGenerator().selectionChanged()
        }
        if hadLiveMutation || lastAppliedSpacingPositions != spacingStartPositions {
            refreshTransitionFromStore()
            store.saveNow()
        }
        spacingStartPositions = [:]
        lastAppliedSpacingPositions = [:]
        spacingDidChange = false
    }

    @discardableResult
    private func applySpacingMagnification(_ magnification: CGFloat) -> Bool {
        guard spacingStartPositions.count >= 2 else { return false }

        let positions = SelectionSpacing.scaledPositions(
            spacingStartPositions,
            magnification: magnification,
            courtSize: CGSize(width: CourtConstants.width, height: CourtConstants.height)
        )
        let didChange = positions != spacingStartPositions
        guard positions != lastAppliedSpacingPositions else { return didChange }
        lastAppliedSpacingPositions = positions
        let editableID = displayedEditableFormationID

        store.mutateFormation(id: editableID) { formation in
            for (athleteID, position) in positions {
                guard let placementIndex = formation.placementIndex(for: athleteID) else { continue }
                formation.placements[placementIndex].position = position
            }
        }
        refreshTransitionFromStore(collisionRefreshMode: .interactivePreview)
        return didChange
    }

    private var selectionLassoForDisplay: FloorSelectionLasso? {
        guard isDrawingSelectionLasso, let selectionLasso, !selectionLasso.isTapCandidate else { return nil }
        return selectionLasso
    }

    private func handleSelectionLassoContinued(_ value: DragGesture.Value) {
        clearActiveGuides()
        selectionLasso?.append(value.location)
    }

    // MARK: - Double-Tap Gesture for Waypoints

    private func waypointDoubleTapGesture(cellSize: CGFloat, offset: CGPoint) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                guard showTransitionPaths, hasTransition else { return }
                guard !selectedAthleteIDs.isEmpty, let player else { return }

                let scaledPoint = CGPoint(
                    x: (value.location.x - offset.x) / cellSize,
                    y: (value.location.y - offset.y) / cellSize
                )

                if cycleWaypointByDoubleTap(at: scaledPoint, cellSize: cellSize) {
                    return
                }

                if nearestPathHandle(at: scaledPoint, cellSize: cellSize) != nil {
                    return
                }

                if let hit = selectedTransitionPathHit(
                    at: scaledPoint,
                    maxSquaredDistance: pathHitRadiusSquared(for: cellSize)
                ) {
                    _ = insertWaypoint(
                        anchorAthleteID: hit.transition.athleteID,
                        at: hit.point,
                        segmentIndex: hit.segmentIndex
                    )
                    return
                }

                guard let selectedAthlete = player.currentAthletes.first(where: {
                    selectedAthleteIDs.contains($0.id)
                        && PathCalculations.squaredDistance(from: scaledPoint, to: $0.position) < interactionHitRadiusSquared(for: cellSize)
                })
                else { return }

                addWaypoint(anchorAthleteID: selectedAthlete.id)
            }
    }

    // MARK: - Long-Press Sketch Gesture

    /// SwiftUI long-press -> drag, attached as a simultaneous gesture so it
    /// composes with the existing unified DragGesture. When the long-press
    /// completes on the selected athlete's endpoint, the sketch arms; the
    /// follow-up drag traces the path. The main DragGesture early-outs when
    /// `isLongPressSketching` is true so it doesn't try to drag the athlete.
    private func longPressSketchGesture(cellSize: CGFloat, offset: CGPoint) -> some Gesture {
        LongPressGesture(minimumDuration: pathSketchLongPressDuration, maximumDistance: pathSketchHoldTolerance)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .first:
                    break
                case .second(true, let drag):
                    guard let drag else { return }
                    if !isLongPressSketching {
                        beginLongPressSketch(at: drag.startLocation, cellSize: cellSize, offset: offset)
                    }
                    if isLongPressSketching {
                        continueLongPressSketch(at: drag.location, cellSize: cellSize, offset: offset)
                    }
                default:
                    break
                }
            }
            .onEnded { _ in
                endLongPressSketch()
            }
    }

    /// Hit-tests the touch point against every athlete's start/end endpoint and
    /// returns the closest one. The athlete does not need to be pre-selected;
    /// the long-press arming + sketch arm will auto-select on success.
    private func athleteEndpointHit(
        at scaledPoint: CGPoint,
        cellSize: CGFloat
    ) -> (athleteID: UUID, anchor: CGPoint, side: PathSketchAnchorSide)? {
        // On the last formation a draw should always go FORWARD — i.e. bootstrap a
        // new formation — rather than reverse-editing the incoming transition (which
        // is awkward/counterintuitive). Yield here so beginLongPressSketch falls
        // through to bootstrapAthleteHit.
        guard !isSwapMode,
              showTransitionPaths, hasTransition,
              !isLastFormation,
              let player
        else { return nil }

        let hitRadiusSquared = interactionHitRadiusSquared(for: cellSize) * 1.5
        var bestDistSq: CGFloat = .greatestFiniteMagnitude
        var best: (athleteID: UUID, anchor: CGPoint, side: PathSketchAnchorSide)?

        for athlete in player.startAthletes {
            let distSq = PathCalculations.squaredDistance(from: scaledPoint, to: athlete.position)
            if distSq < hitRadiusSquared, distSq < bestDistSq {
                bestDistSq = distSq
                best = (athlete.id, athlete.position, .start)
            }
        }
        for athlete in player.endAthletes {
            let distSq = PathCalculations.squaredDistance(from: scaledPoint, to: athlete.position)
            if distSq < hitRadiusSquared, distSq < bestDistSq {
                bestDistSq = distSq
                best = (athlete.id, athlete.position, .end)
            }
        }
        return best
    }

    /// On the last formation (no successor), hit-tests the current formation's
    /// athletes so a draw bootstraps a new formation + forward path to it. Fires
    /// regardless of whether the incoming transition is being previewed — being the
    /// last formation already guarantees there is no forward transition to edit.
    private func bootstrapAthleteHit(
        at scaledPoint: CGPoint,
        cellSize: CGFloat
    ) -> (athleteID: UUID, anchor: CGPoint)? {
        guard !isSwapMode,
              onBootstrapFromAthlete != nil,
              let formationIndex,
              formationIndex == store.routine.formations.count - 1
        else { return nil }

        let hitRadiusSquared = interactionHitRadiusSquared(for: cellSize) * 1.5
        var bestDistSq: CGFloat = .greatestFiniteMagnitude
        var best: (athleteID: UUID, anchor: CGPoint)?
        for athlete in renderedAthletes {
            let distSq = PathCalculations.squaredDistance(from: scaledPoint, to: athlete.position)
            if distSq < hitRadiusSquared, distSq < bestDistSq {
                bestDistSq = distSq
                best = (athlete.id, athlete.position)
            }
        }
        return best
    }

    private func armLongPressCountdown(at anchor: CGPoint) {
        let token = UUID()
        longPressArmingToken = token

        // Force progress to 0 instantly so a prior exit animation cannot make
        // the next hold look partially complete.
        var noAnim = Transaction()
        noAnim.disablesAnimations = true
        withTransaction(noAnim) {
            longPressProgress = 0
            longPressArmingPosition = anchor
            isLongPressCountdownVisible = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + pathSketchCountdownDelay) {
            guard longPressArmingToken == token,
                  longPressArmingPosition != nil,
                  !isLongPressSketching,
                  !isDraggingAthletes,
                  !isDraggingEndpoint,
                  !isDraggingPathHandle,
                  !isPanningCanvas,
                  !isDrawingSelectionLasso
            else { return }

            let generator = UISelectionFeedbackGenerator()
            generator.selectionChanged()

            withAnimation(.easeIn(duration: 0.08)) {
                isLongPressCountdownVisible = true
            }
            withAnimation(.linear(duration: pathSketchCountdownDuration)) {
                longPressProgress = 1.0
            }
        }
    }

    private func cancelLongPressCountdown() {
        longPressArmingToken = nil
        isLongPressCountdownVisible = false
        longPressArmingPosition = nil
        withAnimation(.easeOut(duration: 0.15)) { longPressProgress = 0 }
    }

    /// Arms a path sketch when the long-press lands on the selected athlete's
    /// start or end position. The sketch is anchored at that endpoint so the
    /// finger naturally traces the route to the opposite endpoint.
    private func beginLongPressSketch(at location: CGPoint, cellSize: CGFloat, offset: CGPoint) {
        guard entitlementManager.isPro else {
            showingUpgradeSheet = true
            cancelLongPressCountdown()
            return
        }
        guard !isExplicitPathDrawMode,
              !isSketchingPath,
              !isDraggingAthletes,
              !isDraggingEndpoint,
              !isDraggingPathHandle,
              !isPanningCanvas,
              !isDrawingSelectionLasso
        else { return }

        let scaledPoint = CGPoint(
            x: (location.x - offset.x) / cellSize,
            y: (location.y - offset.y) / cellSize
        )
        if let hit = athleteEndpointHit(at: scaledPoint, cellSize: cellSize) {
            // Preserve an existing multi-selection when the long-press lands on
            // one of the selected athletes — that athlete becomes the anchor
            // and the drawn shape will be applied to the whole group on commit.
            let preserveGroup = selectedAthleteIDs.count > 1 && selectedAthleteIDs.contains(hit.athleteID)
            if !preserveGroup, selectedAthleteIDs != [hit.athleteID] {
                selectedAthleteIDs = selectionForAthlete(hit.athleteID)
            }
            longPressSketchAnchorAthleteID = hit.athleteID
            isLongPressSketching = true
            isSketchingPath = true
            didConsumeLongPressTouch = true
            pathSketchPoints = [clampedPathPoint(hit.anchor)]
            pathSketchAnchorSide = hit.side
            longPressArmingPosition = hit.anchor
            longPressProgress = 1.0
            longPressArmingToken = nil
            isLongPressCountdownVisible = true
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            return
        }

        if let bootstrap = bootstrapAthleteHit(at: scaledPoint, cellSize: cellSize) {
            if selectedAthleteIDs != [bootstrap.athleteID] {
                selectedAthleteIDs = selectionForAthlete(bootstrap.athleteID)
            }
            isLongPressSketching = true
            isSketchingPath = true
            didConsumeLongPressTouch = true
            pathSketchPoints = [clampedPathPoint(bootstrap.anchor)]
            pathSketchAnchorSide = .start
            bootstrapAthleteID = bootstrap.athleteID
            longPressArmingPosition = bootstrap.anchor
            longPressProgress = 1.0
            longPressArmingToken = nil
            isLongPressCountdownVisible = true
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }
    }

    private func continueLongPressSketch(at location: CGPoint, cellSize: CGFloat, offset: CGPoint) {
        guard isLongPressSketching else { return }
        let scaledPoint = CGPoint(
            x: (location.x - offset.x) / cellSize,
            y: (location.y - offset.y) / cellSize
        )
        pathSketchPoints.append(clampedPathPoint(scaledPoint))
    }

    private func endLongPressSketch() {
        guard isLongPressSketching else { return }
        if let athleteID = bootstrapAthleteID {
            _ = commitBootstrapSketch(athleteID: athleteID)
        } else {
            finishPathSketch()
        }
        isLongPressSketching = false
        isSketchingPath = false
        pathSketchPoints = []
        pathSketchAnchorSide = nil
        longPressSketchAnchorAthleteID = nil
        bootstrapAthleteID = nil
        longPressArmingToken = nil
        isLongPressCountdownVisible = false
        longPressArmingPosition = nil
        withAnimation(.easeOut(duration: 0.18)) { longPressProgress = 0 }
        store.saveNow()
    }
}
