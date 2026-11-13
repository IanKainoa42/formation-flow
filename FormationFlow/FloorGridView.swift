import Combine
import SwiftUI
import UIKit


// MARK: - Floor Grid View

struct FloorGridView: View {
    @Environment(\.editorLayoutContext) private var editorLayout
    @ObservedObject var store: RoutineStore
    @Binding var selectedAthleteIDs: Set<UUID>
    @Binding var isSwapMode: Bool
    @Binding var triggerDeleteAthlete: Bool
    let formationID: UUID
    var onCycleFormation: (() -> Void)?
    var onCyclePreviousFormation: (() -> Void)?
    var isFirstFormation: Bool = false
    var isLastFormation: Bool = false
    var hideFormationContextBadge: Bool = false
    var onDuplicateAsNext: () -> Void
    var onRenameFormation: (() -> Void)?
    var onDeleteFormation: (() -> Void)?
    var onResetRoutine: (() -> Void)?
    var onPlayRoutine: (() -> Void)?
    var onEnterFullScreen: (() -> Void)?
    var onBack: (() -> Void)?

    // Transition parameters (nil when no adjacent formation)
    var player: TransitionPlayer?
    var startFormationID: UUID?
    var endFormationID: UUID?
    var onToggleTransitionDirection: (() -> Void)?
    var onBootstrapFromAthlete: ((UUID, CGPoint, [PathWaypoint]) -> Void)?

    @EnvironmentObject private var entitlementManager: EntitlementManager
    @State private var showingUpgradeSheet = false
    @State private var showingRosterSheet = false
    @State private var showingNotesSheet = false
    @State private var showingInspectorSheet = false
    @State private var showingTransportSheet = false
    @State private var showingPathSettingsSheet = false
    @State private var showingAthleteRenamePrompt = false
    @State private var athleteLabelDraft = ""
    @State private var showingAthleteDeleteConfirmation = false
    @AppStorage("pathDisplayScope") private var pathDisplayScopeRaw = PathDisplayScope.selectedOnly.rawValue
    private var pathDisplayScope: PathDisplayScope {
        PathDisplayScope(rawValue: pathDisplayScopeRaw) ?? .selectedOnly
    }
    @AppStorage("transitionPreviewMode") private var transitionPreviewModeRaw = TransitionPreviewMode.flow.rawValue
    private var transitionPreviewMode: TransitionPreviewMode {
        TransitionPreviewMode(rawValue: transitionPreviewModeRaw) ?? .flow
    }
    // Kept as a computed convenience so the many gesture sites that gate on
    // "are paths visible at all" don't need to learn about scope.
    private var showTransitionPaths: Bool { pathDisplayScope != .off }
    @State private var isDraggingAthletes = false
    @State private var isPanningCanvas = false
    @State private var isDrawingSelectionLasso = false
    @State private var selectionLasso: FloorSelectionLasso? = nil
    @State private var dragStartPositions: [UUID: CGPoint] = [:]
    @State private var lastAppliedFormationDragPositions: [UUID: CGPoint] = [:]
    @State private var lastAppliedEndpointDragPosition: CGPoint?
    @State private var draggingAthleteIDs: Set<UUID> = []
    @State private var undoStack: [FormationMoveUndoSnapshot] = []
    @State private var rotationStartPositions: [UUID: CGPoint] = [:]
    @State private var lastRotationDetent: Int = 0
    @State private var rotationDidApplyChange = false
    @State private var spacingStartPositions: [UUID: CGPoint] = [:]
    @State private var lastAppliedSpacingPositions: [UUID: CGPoint] = [:]
    @State private var spacingDidChange = false
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    @State private var canvasPanOffset: CGSize = .zero
    @State private var lastCanvasPanOffset: CGSize = .zero
    @State private var swapSourceAthleteID: UUID?
    @State private var swapFormationTarget: SwapFormationTarget = .start
    @State private var hasMadeFirstSelection = false
    @State private var activeAlignmentGuides: [AlignmentGuideRenderItem] = []
    @State private var activeMirrorGuides: [FormationMirrorGuideRenderItem] = []
    @State private var rosterDeleteIDs: [UUID] = []
    @State private var collisionCycleIndex: Int = 0
    @State private var pathCollisionCycleIndex: Int = 0

    private var isCanvasInteractionActive: Bool {
        isDraggingAthletes
            || isDraggingEndpoint
            || isDraggingPathHandle
            || isPanningCanvas
            || isDrawingSelectionLasso
            || isSketchingPath
            || !rotationStartPositions.isEmpty
            || !spacingStartPositions.isEmpty
    }

    // Transition editing state
    @State private var focusedEndpoint: PreviewEditableEndpoint?
    @State private var isDraggingEndpoint = false
    @State private var isDraggingPathHandle = false
    @State private var isExplicitPathDrawMode = false
    @State private var pathDragAthleteID: UUID?
    @State private var isSketchingPath = false
    @State private var isLongPressSketching = false
    /// True from the moment a long-press sketch arms until the main drag gesture's
    /// onEnded observes it. The long-press gesture and the main drag gesture receive
    /// the SAME touch and both fire onEnded in an undefined order; this flag lets the
    /// main gesture recognize "this touch was a long-press sketch — endLongPressSketch
    /// owns the commit" regardless of which onEnded runs first, so we never
    /// double-commit, wipe the pending sketch points, or fall through to a tap.
    @State private var didConsumeLongPressTouch = false
    @State private var draggingWaypointID: UUID?
    @State private var pathHandleDragDraft: PathHandleDragDraft?
    @State private var pendingWaypointDeletionID: UUID?
    @State private var pathSketchPoints: [CGPoint] = []
    @State private var pathSketchAnchorSide: PathSketchAnchorSide?
    /// The athlete whose endpoint the active long-press sketch is anchored to.
    /// Distinct from `selectedAthleteID` because group sketches preserve the
    /// full multi-selection while still tracking which athlete owns the anchor.
    @State private var longPressSketchAnchorAthleteID: UUID?
    @State private var bootstrapAthleteID: UUID?
    @State private var longPressArmingPosition: CGPoint?
    @State private var longPressProgress: Double = 0
    @State private var longPressArmingToken: UUID?
    @State private var isLongPressCountdownVisible = false
    @State private var endpointDragStartPosition: CGPoint?
    @State private var showingResetAllPathsConfirmation = false
    @State private var showingResetSinglePathConfirmation = false
    @State private var hoveredHandlePosition: CGPoint?
    @State private var hoveredAthleteID: UUID?
    @State private var hoveredPathAthleteID: UUID?
    @State private var focusedPathHandle: CGPoint?
    @State private var playerTick: UInt = 0
    @State private var sharePayload: TransitionSharePayload?
    @State private var documentSharePayload: DocumentSharePayload?
    @State private var showingPDFExportSheet = false
    @State private var showingMoreAppsSheet = false
    @State private var shareResultMessage = ""
    @State private var showingShareResult = false
    @State private var recentPathEditSnapshot: PathEditUndoSnapshot?

    private var pathCollisionIDs: Set<UUID> {
        _ = playerTick
        return player?.cachedPathCollisionIDs ?? []
    }

    private var activeTransitionGroups: [TransitionStuntGroup] {
        player?.transitionSpec.stuntGroups ?? []
    }

    private var activeTransitionGroupIDSets: [Set<UUID>] {
        activeTransitionGroups.map(\.athleteIDSet)
    }

    private var selectedTransitionGroup: TransitionStuntGroup? {
        guard selectedAthleteIDs.count >= 2 else { return nil }
        return activeTransitionGroups.first { $0.athleteIDSet == selectedAthleteIDs }
    }

    private var selectionIsTransitionGroup: Bool {
        selectedTransitionGroup != nil
    }

    private var selectedAthletesAreInDisplayedFormation: Bool {
        guard
            selectedAthleteIDs.count >= 2,
            let endpoint = displayedFormationEndpoint,
            let formationID = endpoint == .start ? startFormationID : endFormationID,
            let formation = store.formation(id: formationID)
        else { return false }

        let placementIDs = Set(formation.placements.map(\.athleteID))
        return selectedAthleteIDs.isSubset(of: placementIDs)
    }

    private var canCreateSelectedTransitionGroup: Bool {
        hasTransition
            && !isTransportEngaged
            && displayedFormationEndpoint != nil
            && selectedAthletesAreInDisplayedFormation
    }

    private var formationIndex: Int? {
        store.formationIndex(id: formationID)
    }

    private var formation: Formation? {
        guard let formationIndex else { return nil }
        return store.routine.formations[formationIndex]
    }

    private var isCompactLayout: Bool { editorLayout.usesCompactWorkspace }
    private var isPhoneLayout: Bool { editorLayout.isPhone }
    private var isPhoneLandscape: Bool { editorLayout.isPhoneLandscape }
    private var isHeightConstrained: Bool { editorLayout.isHeightConstrained }

    private var phonePortraitHasSelection: Bool {
        isPhoneLayout && !isPhoneLandscape
            && (selectedRosterAthlete != nil || selectedAthleteIDs.count > 1)
    }

    private var canAddFormation: Bool {
        entitlementManager.isPro || store.routine.formations.count < FreeTierLimits.maxFormations
    }

    /// The transport is "engaged" while playing OR while scrubbed/paused away
    /// from the resting start. The player retains a tiny resting epsilon after
    /// auto-rewind to preserve endpoint ownership, so it is still idle here.
    /// When engaged we follow
    /// `player.currentAthletes` so the scrubber animates the floor and pause
    /// freezes athletes in place. When at rest we lock to the formation's
    /// endpoint so the editor shows a crisp static formation (and progress
    /// stays 0, so the idle-reset never fires under the editor).
    private var isTransportEngaged: Bool {
        guard let player else { return false }
        return player.isPlaying || player.progress > 0.001
    }

    private var renderedAthletes: [RenderedAthlete] {
        _ = playerTick // force redraw on player updates
        if let player {
            // Idle display follows the formation being edited, falling back to
            // currentFormationEndpoint so the very first frame (before any
            // gesture sets focusedEndpoint) already shows the right formation.
            // Without this, focusedEndpoint is nil on appear → currentAthletes
            // (= start positions), and the first tap snapped the canvas to the
            // edited formation's real positions ("selecting changes formations").
            if !isTransportEngaged,
               let endpointAthletes = athletes(for: displayedFormationEndpoint) {
                return endpointAthletes
            }
            return player.currentAthletes
        }
        return store.renderedAthletes(for: formationID)
    }

    private var collisionSummary: (count: Int, ids: Set<UUID>) {
        // ⚡ Bolt: Avoid O(N^2) spatial math per frame during playback.
        // Lower bound is a small epsilon (not 0) so the idle-rewind rest state
        // (progress floored at 0.0001) still computes collisions for the
        // displayed start formation.
        if let player, player.progress > 0.001 && player.progress < 1 {
            return (0, [])
        }
        return PathCalculations.collisionSummary(in: renderedAthletes)
    }

    private var collidingAthletes: [RenderedAthlete] {
        renderedAthletes.filter { collisionSummary.ids.contains($0.id) }
    }

    private var selectedAthleteID: UUID? {
        selectedAthleteIDs.count == 1 ? selectedAthleteIDs.first : nil
    }

    private var selectedRosterAthlete: RosterAthlete? {
        guard let selectedAthleteID else { return nil }
        return store.routine.roster.first(where: { $0.id == selectedAthleteID })
    }

    private var selectedPlacement: FormationPlacement? {
        guard let selectedAthleteID, let formation else { return nil }
        return formation.placements.first(where: { $0.athleteID == selectedAthleteID })
    }

    // MARK: - Formation Display

    private var formationContextLabel: String {
        let index = (formationIndex ?? 0) + 1
        let total = store.routine.formations.count
        let name = formation?.name ?? "Formation"
        return "\(index)/\(total): \(name)"
    }

    private var previousFormationName: String? {
        guard let formationIndex, formationIndex > 0 else { return nil }
        return store.routine.formations[formationIndex - 1].name
    }

    private var currentFormationColor: Color {
        let index = formationIndex ?? 0
        return TransitionEndpointMarkerRenderItem.rainbowColor(forIndex: index)
    }

    // Ghost athletes and paths are anchored to startFormationID/endFormationID so they
    // correctly show the transition BEFORE the current start and AFTER the current end,
    // regardless of whether the selected formation is the start or end of the transition.

    private var previousFormationAthletes: [RenderedAthlete] {
        guard let startFormationID,
              let startIndex = store.formationIndex(id: startFormationID),
              startIndex > 0 else { return [] }
        return store.renderedAthletes(for: store.routine.formations[startIndex - 1])
    }

    private var nextFormationAthletes: [RenderedAthlete] {
        guard let endFormationID,
              let endIndex = store.formationIndex(id: endFormationID),
              endIndex + 1 < store.routine.formations.count else { return [] }
        return store.renderedAthletes(for: store.routine.formations[endIndex + 1])
    }

    private var previousFormationColor: Color {
        guard let startFormationID,
              let startIndex = store.formationIndex(id: startFormationID),
              startIndex > 0 else { return .white }
        return TransitionEndpointMarkerRenderItem.rainbowColor(forIndex: startIndex - 1)
    }

    private var nextFormationColor: Color {
        guard let endFormationID,
              let endIndex = store.formationIndex(id: endFormationID),
              endIndex + 1 < store.routine.formations.count else { return .white }
        return TransitionEndpointMarkerRenderItem.rainbowColor(forIndex: endIndex + 1)
    }

    private var previousGhostPaths: [TransitionPathRenderItem] {
        guard let startFormationID,
              let startIndex = store.formationIndex(id: startFormationID),
              startIndex > 0 else { return [] }
        let prevFormation = store.routine.formations[startIndex - 1]
        let startFormation = store.routine.formations[startIndex]
        let spec = store.transitionSpec(for: prevFormation.id, to: startFormation.id)
        let prevAthletes = store.renderedAthletes(for: prevFormation)
        let startAthletes = store.renderedAthletes(for: startFormation)
        let startLookup = startAthletes.reduce(into: [UUID: RenderedAthlete]()) { result, athlete in
            if result[athlete.id] == nil { result[athlete.id] = athlete }
        }
        return prevAthletes.compactMap { athlete in
            guard let end = startLookup[athlete.id] else { return nil }
            let transition = spec.athleteTransitions.first { $0.athleteID == athlete.id }
            return TransitionPathRenderItem(
                athleteID: athlete.id,
                startPosition: athlete.position,
                endPosition: end.position,
                controlPoint: transition?.pathControlPoint,
                waypoints: transition?.pathWaypoints ?? [],
                moveDelay: transition?.moveDelay ?? 0
            )
        }
    }

    private var nextGhostPaths: [TransitionPathRenderItem] {
        guard let endFormationID,
              let endIndex = store.formationIndex(id: endFormationID),
              endIndex + 1 < store.routine.formations.count else { return [] }
        let endFormation = store.routine.formations[endIndex]
        let nextFormation = store.routine.formations[endIndex + 1]
        let spec = store.transitionSpec(for: endFormation.id, to: nextFormation.id)
        let endAthletes = store.renderedAthletes(for: endFormation)
        let nextAthletes = store.renderedAthletes(for: nextFormation)
        let nextLookup = nextAthletes.reduce(into: [UUID: RenderedAthlete]()) { result, athlete in
            if result[athlete.id] == nil { result[athlete.id] = athlete }
        }
        return endAthletes.compactMap { athlete in
            guard let end = nextLookup[athlete.id] else { return nil }
            let transition = spec.athleteTransitions.first { $0.athleteID == athlete.id }
            return TransitionPathRenderItem(
                athleteID: athlete.id,
                startPosition: athlete.position,
                endPosition: end.position,
                controlPoint: transition?.pathControlPoint,
                waypoints: transition?.pathWaypoints ?? [],
                moveDelay: transition?.moveDelay ?? 0
            )
        }
    }

    // MARK: - Transition Computed Properties

    private var hasTransition: Bool {
        player != nil && startFormationID != nil && endFormationID != nil
    }

    private var displayProgress: CGFloat {
        guard let player else { return 0 }
        // Same nil-window guard as renderedAthletes — keep the formation color
        // blend in sync with the edited formation on the first frame.
        if !isTransportEngaged, let endpoint = displayedFormationEndpoint {
            return endpoint == .end ? 1.0 : 0.0
        }
        return player.progress
    }

    private var transitionStartColor: Color {
        let index = startFormationID.flatMap { store.formationIndex(id: $0) } ?? 0
        return TransitionEndpointMarkerRenderItem.rainbowColor(forIndex: index)
    }

    private var transitionEndColor: Color {
        let index = endFormationID.flatMap { store.formationIndex(id: $0) } ?? 0
        return TransitionEndpointMarkerRenderItem.rainbowColor(forIndex: index)
    }

    private var transitionPaths: [TransitionPathRenderItem] {
        guard let player else { return [] }
        return player.cachedTransitionPaths
    }

    // MARK: - Path display scope

    /// Current-transition paths filtered by the user's display-scope preference.
    private var displayedTransitionPaths: [TransitionPathRenderItem] {
        switch pathDisplayScope {
        case .off:
            return []
        case .selectedOnly:
            guard !selectedAthleteIDs.isEmpty else { return [] }
            return transitionPaths.filter { selectedAthleteIDs.contains($0.athleteID) }
        case .currentFormation, .allFormations:
            return transitionPaths
        }
    }

    /// Prev/next ghosts only render in All Formations mode.
    private var displayedPrevGhostPaths: [TransitionPathRenderItem] {
        pathDisplayScope == .allFormations ? previousGhostPaths : []
    }

    private var displayedNextGhostPaths: [TransitionPathRenderItem] {
        pathDisplayScope == .allFormations ? nextGhostPaths : []
    }

    /// Fade the non-selected athletes when focusing a single athlete's path so
    /// the only thing that reads as editable is the selected athlete's route.
    private var dimUnselectedAthletes: Bool {
        pathDisplayScope == .selectedOnly && hasTransition && !selectedAthleteIDs.isEmpty
    }

    private var canBeginExplicitPathDraw: Bool {
        hasTransition
            && !isTransportEngaged
            && !selectedAthleteIDs.isEmpty
            && currentFormationEndpoint != nil
            && player != nil
    }

    private var drawPathButtonTitle: String {
        selectedAthleteIDs.count > 1 ? "Draw Paths" : "Draw Path"
    }

    private var explicitPathDrawButtonTitle: String {
        if isExplicitPathDrawMode { return "Cancel Draw" }
        return entitlementManager.isPro ? drawPathButtonTitle : "\(drawPathButtonTitle) (Pro)"
    }

    private var explicitPathDrawButtonSystemImage: String {
        if isExplicitPathDrawMode { return "xmark.circle" }
        return entitlementManager.isPro ? "scribble" : "lock.fill"
    }

    private var pathSketchStatusText: String? {
        if isSketchingPath {
            let count = pathSketchPreviewPaths.count
            if count > 1 { return "Drawing for \(count) athletes" }
            return "Drawing path"
        }
        if isExplicitPathDrawMode {
            return selectedAthleteIDs.count > 1
                ? "Draw paths: drag the route, lift to save"
                : "Draw path: drag the route, lift to save"
        }
        return nil
    }

    private var pathSketchPreviewPaths: [PathSketchPreviewRenderItem] {
        guard
            isSketchingPath,
            // A bootstrap sketch (drawing forward off the last formation) has no
            // existing transition pair to anchor a smoothed preview to — the raw
            // freehand line is the live indicator instead.
            bootstrapAthleteID == nil,
            pathSketchPoints.count >= 2,
            let player,
            let anchorAthleteID = longPressSketchAnchorAthleteID
                ?? TransitionPathSelectionEditing.anchorAthleteID(for: selectedAthleteIDs, in: player),
            let anchorStartAthlete = player.startAthletes.first(where: { $0.id == anchorAthleteID }),
            let anchorEndAthlete = player.endAthletes.first(where: { $0.id == anchorAthleteID })
        else { return [] }

        let isGroupSketch = selectedAthleteIDs.count > 1 && selectedAthleteIDs.contains(anchorAthleteID)
        let resolved = isGroupSketch
            ? (start: anchorStartAthlete.position, end: anchorEndAthlete.position)
            : resolvedSketchEndpoints(
                anchorStart: anchorStartAthlete.position,
                anchorEnd: anchorEndAthlete.position
            )
        let anchorWaypoints = smoothedWaypoints(
            fromSketch: pathSketchPoints,
            start: resolved.start,
            end: resolved.end
        )

        if isGroupSketch {
            let anchorStart = anchorStartAthlete.position
            let startsByID = Dictionary(uniqueKeysWithValues: player.startAthletes.map { ($0.id, $0.position) })
            let endsByID = Dictionary(uniqueKeysWithValues: player.endAthletes.map { ($0.id, $0.position) })

            return player.startAthletes.compactMap { athlete in
                let athleteID = athlete.id
                guard selectedAthleteIDs.contains(athleteID),
                      let start = startsByID[athleteID],
                      let end = endsByID[athleteID]
                else { return nil }
                let dx = start.x - anchorStart.x
                let dy = start.y - anchorStart.y
                let translatedWaypoints = anchorWaypoints.map { waypoint in
                    PathWaypoint(
                        id: waypoint.id,
                        position: clampedPathPoint(CGPoint(x: waypoint.position.x + dx, y: waypoint.position.y + dy)),
                        isSmooth: waypoint.isSmooth,
                        holdDuration: waypoint.holdDuration
                    )
                }
                return PathSketchPreviewRenderItem(
                    athleteID: athleteID,
                    startPosition: start,
                    endPosition: end,
                    waypoints: translatedWaypoints,
                    isPrimary: athleteID == anchorAthleteID
                )
            }
        }

        return [
            PathSketchPreviewRenderItem(
                athleteID: anchorAthleteID,
                startPosition: resolved.start,
                endPosition: resolved.end,
                waypoints: anchorWaypoints,
                isPrimary: true
            )
        ]
    }

    private var endpointMarkers: [TransitionEndpointMarkerRenderItem] {
        guard let player else { return [] }

        let startStyle: TransitionEndpointMarkerRenderItem.Style =
            focusedEndpoint == nil || focusedEndpoint == .start ? .editable : .readOnly
        let endStyle: TransitionEndpointMarkerRenderItem.Style =
            focusedEndpoint == nil || focusedEndpoint == .end ? .editable : .readOnly

        // Rainbow color per formation index
        let startIndex = startFormationID.flatMap { store.formationIndex(id: $0) } ?? 0
        let endIndex = endFormationID.flatMap { store.formationIndex(id: $0) } ?? 0
        let startColor = TransitionEndpointMarkerRenderItem.rainbowColor(forIndex: startIndex)
        let endColor = TransitionEndpointMarkerRenderItem.rainbowColor(forIndex: endIndex)

        let startMarkers = player.startAthletes.map { athlete in
            TransitionEndpointMarkerRenderItem(
                athleteID: athlete.id,
                label: athlete.label,
                role: athlete.role,
                position: athlete.position,
                endpoint: .start,
                style: startStyle,
                formationColor: startColor
            )
        }
        let endMarkers = player.endAthletes.map { athlete in
            TransitionEndpointMarkerRenderItem(
                athleteID: athlete.id,
                label: athlete.label,
                role: athlete.role,
                position: athlete.position,
                endpoint: .end,
                style: endStyle,
                formationColor: endColor
            )
        }
        return startMarkers + endMarkers
    }

    private var currentFormationEndpoint: PreviewEditableEndpoint? {
        guard startFormationID != nil && endFormationID != nil else { return nil }
        if formationID == startFormationID { return .start }
        if formationID == endFormationID { return .end }
        return nil
    }

    private var displayedFormationEndpoint: PreviewEditableEndpoint? {
        focusedEndpoint ?? currentFormationEndpoint
    }

    private func formationID(for endpoint: PreviewEditableEndpoint?) -> UUID? {
        guard let endpoint else { return nil }
        switch endpoint {
        case .start:
            return startFormationID
        case .end:
            return endFormationID
        }
    }

    private func endpoint(for formationID: UUID) -> PreviewEditableEndpoint? {
        if formationID == startFormationID { return .start }
        if formationID == endFormationID { return .end }
        return nil
    }

    private var displayedEditableFormationID: UUID {
        formationID(for: displayedFormationEndpoint) ?? formationID
    }

    private var editableFormationID: UUID? {
        guard hasTransition, let focusedEndpoint else { return nil }
        return focusedEndpoint == .start ? startFormationID : endFormationID
    }

    private var editableAthletes: [RenderedAthlete] {
        guard let player, let focusedEndpoint else { return [] }
        return focusedEndpoint == .start ? player.startAthletes : player.endAthletes
    }

    private func athletes(for endpoint: PreviewEditableEndpoint?) -> [RenderedAthlete]? {
        guard let player, let endpoint else { return nil }
        return endpoint == .start ? player.startAthletes : player.endAthletes
    }

    private var selectedTransition: AthleteTransition? {
        guard let selectedAthleteID, let player else { return nil }
        return player.transitionSpec.athleteTransition(for: selectedAthleteID)
    }


    private var startFormationName: String? {
        guard let startFormationID else { return nil }
        return store.formation(id: startFormationID)?.name
    }

    private var endFormationName: String? {
        guard let endFormationID else { return nil }
        return store.formation(id: endFormationID)?.name
    }

    private var compactInspectorTitle: String {
        if selectedAthleteIDs.count > 1 {
            return "\(selectedAthleteIDs.count) Selected"
        }
        if let selectedRosterAthlete, selectedAthleteIDs.count == 1 {
            return selectedRosterAthlete.label
        }
        return "Inspector"
    }

    private var compactInspectButtonTitle: String {
        if selectedAthleteIDs.count > 1 {
            return "Selection"
        }
        if selectedAthleteID != nil {
            return "Athlete"
        }
        return "Inspect"
    }

    private var pathCollidingAthletes: [RenderedAthlete] {
        renderedAthletes.filter { pathCollisionIDs.contains($0.id) }
    }

    private var canShareTransition: Bool {
        hasTransition && startFormationName != nil && endFormationName != nil
    }

    private var swapSourceRosterAthlete: RosterAthlete? {
        guard let swapSourceAthleteID else { return nil }
        return store.routine.roster.first(where: { $0.id == swapSourceAthleteID })
    }

    private var compactBannerConfiguration: (text: String, color: Color)? {
        if isSwapMode, swapSourceRosterAthlete != nil {
            // Handled by swapBanner view instead
            return nil
        }

        if !hasMadeFirstSelection {
            return ("Tap an athlete to edit it. Drag on empty space to lasso-select.", .coral)
        }

        return nil
    }

    @ViewBuilder
    private var resetViewFloatingButton: some View {
        if isViewTransformed {
            Button(action: resetView) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset View")
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var dragActivationDistance: CGFloat {
        isCompactLayout ? 10 : 6
    }

    private var pathSketchLongPressDuration: Double { 1.25 }
    private var pathSketchCountdownDelay: Double { 0.45 }
    /// Movement allowed during the sketch long-press hold. Must be generous: a real
    /// finger tremors several points over the deliberate hold, so tying this to
    /// the tiny `dragActivationDistance` (6–10pt) made the long-press impossible
    /// to satisfy on-device (it only "worked" against a perfectly-still touch).
    private var pathSketchHoldTolerance: CGFloat { 30 }
    private var pathSketchEndpointSnapDistance: CGFloat { 1.35 }
    private var pathSketchCountdownDuration: Double {
        max(0.1, pathSketchLongPressDuration - pathSketchCountdownDelay)
    }

    var body: some View {
        Group {
            if formation != nil {
                editorBody
            } else {
                ContentUnavailableView("Select a formation", systemImage: "square.grid.2x2")
            }
        }
        .sheet(isPresented: $showingRosterSheet) {
            rosterSheet
        }
        .sheet(isPresented: $showingMoreAppsSheet) {
            MoreCoachingAppsView()
        }
        .sheet(isPresented: $showingNotesSheet) {
            notesSheet
        }
        .sheet(isPresented: $showingInspectorSheet) {
            compactInspectorSheet
        }
        .sheet(isPresented: $showingTransportSheet) {
            compactTransportSheet
        }
        .sheet(isPresented: $showingPathSettingsSheet) {
            pathSettingsSheet
        }
        .sheet(isPresented: $showingUpgradeSheet) {
            // Sheets present in a detached environment — ProUpgradeSheet reads
            // @EnvironmentObject entitlementManager, so it must be re-injected or
            // it traps on present (crashed when the Pro length lock was tapped).
            ProUpgradeSheet()
                .environmentObject(entitlementManager)
        }
        .sheet(isPresented: $showingPDFExportSheet) {
            PDFExportSheetView(store: store, currentFormationID: formationID)
                .environmentObject(entitlementManager)
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheetView(items: [payload.message, payload.image]) { completed, activityType in
                if completed {
                    RoutineMetrics.record(
                        .transitionShareCompleted,
                        metadata: shareMetricMetadata(activityType: activityType?.rawValue)
                    )
                    shareResultMessage = payload.completionMessage
                    showingShareResult = true
                }
                sharePayload = nil
            }
        }
        .sheet(item: $documentSharePayload) { payload in
            ShareSheetView(items: [payload.url]) { completed, activityType in
                if completed {
                    shareResultMessage = "Export completed successfully"
                    showingShareResult = true
                }
                documentSharePayload = nil
            }
        }
        .alert("Rename Athlete", isPresented: $showingAthleteRenamePrompt) {
            TextField("Label", text: $athleteLabelDraft)
                .autocorrectionDisabled()
                .onChange(of: athleteLabelDraft) { _, newValue in
                    let clamped = String(newValue.prefix(3))
                    if clamped != newValue { athleteLabelDraft = clamped }
                }

            Button("Save") {
                commitAthleteRename()
            }
            .disabled(athleteLabelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Athlete labels are shared across every formation.")
        }
        .alert("Transition Shared", isPresented: $showingShareResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shareResultMessage)
        }
        .onChange(of: formationID) { _, _ in
            // Batch all resets before clearing selection to avoid
            // cascading onChange triggers in the same frame.
            endSwapMode()
            clearActiveGuides()
            collisionCycleIndex = 0
            pathCollisionCycleIndex = 0
            focusedEndpoint = currentFormationEndpoint
            focusedPathHandle = nil
            showingInspectorSheet = false
            showingTransportSheet = false
            showingAthleteRenamePrompt = false
            showingAthleteDeleteConfirmation = false
            pendingWaypointDeletionID = nil
            athleteLabelDraft = ""
            canvasPanOffset = .zero
            lastCanvasPanOffset = .zero
            rotationStartPositions = [:]
            lastRotationDetent = 0
            rotationDidApplyChange = false
            spacingStartPositions = [:]
            lastAppliedSpacingPositions = [:]
            spacingDidChange = false
            lastAppliedFormationDragPositions = [:]
            lastAppliedEndpointDragPosition = nil
            clearTransitionDragState()
            selectedAthleteIDs = []
        }
        .onChange(of: endFormationID) { _, _ in
            focusedEndpoint = currentFormationEndpoint
        }
        .onChange(of: startFormationID) { _, _ in
            focusedEndpoint = currentFormationEndpoint
        }
        .onChange(of: isSwapMode) { _, newValue in
            if newValue, swapSourceAthleteID == nil {
                // Swap was toggled externally (e.g. from FormationHomeView transport)
                // Run the same logic as toggleSwapMode
                guard let selectedAthleteID else {
                    isSwapMode = false
                    return
                }
                swapSourceAthleteID = selectedAthleteID
                swapFormationTarget = .start
                if let player {
                    player.pause()
                    player.seek(to: 0)
                }
            }
        }
        .onChange(of: store.routine.roster) { _, newRoster in
            pruneRosterDependentState(validAthleteIDs: Set(newRoster.map(\.id)))
            refreshTransitionFromStore()
        }
        .onChange(of: selectedAthleteIDs) { _, newSelection in
            pendingWaypointDeletionID = nil
            if !spacingStartPositions.isEmpty, Set(spacingStartPositions.keys) != newSelection {
                spacingStartPositions = [:]
                lastAppliedSpacingPositions = [:]
                spacingDidChange = false
            }
            if newSelection.count == 1,
               let athleteID = newSelection.first,
               let group = transitionGroup(containing: athleteID),
               selectedAthleteIDs != group.athleteIDSet {
                selectedAthleteIDs = group.athleteIDSet
                return
            }
            if !newSelection.isEmpty {
                hasMadeFirstSelection = true
            }
            if newSelection.isEmpty {
                // Only call endSwapMode if still active — avoids redundant
                // updates when formationID onChange already ended it.
                if isSwapMode {
                    endSwapMode()
                }
                focusedEndpoint = hasTransition ? currentFormationEndpoint : nil
            }
        }
        .onChange(of: triggerDeleteAthlete) { _, shouldDelete in
            if shouldDelete {
                triggerDeleteAthlete = false
                deleteSelectedAthlete()
            }
        }
        .onReceive(player?.objectWillChange.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()) { _ in
            playerTick &+= 1
        }
        .toolbar {
            if isPhoneLayout && !isPhoneLandscape {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: undoLastMove) {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(undoStack.isEmpty)
                    .accessibilityLabel("Undo Move")
                    .help(undoStack.isEmpty ? "Nothing to undo" : "Undo the last move")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    phoneToolbarMenu
                }
            } else if !isPhoneLayout {
                ToolbarItem(placement: .navigationBarTrailing) {
                    editorToolbar
                }
            }
        }
    }

    private var editorBody: some View {
        Group {
            if renderedAthletes.isEmpty {
                emptyState
            } else {
                canvasArea
            }
        }
        .background {
            if isPhoneLayout {
                FormationEditorTheme.stageBackground.ignoresSafeArea()
            }
        }
        // Phone chrome is an inset, so the court scales into the space that
        // remains instead of rendering underneath the controls. Landscape uses
        // one side rail (the only transport). Portrait uses the bottom bar.
        .safeAreaInset(edge: .leading, spacing: 0) {
            if isPhoneLandscape {
                phoneLandscapeRail
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if !renderedAthletes.isEmpty, isPhoneLayout, !isPhoneLandscape {
                phonePortraitTopChrome
            } else if isPhoneLandscape {
                phoneLandscapeStatusInset
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !renderedAthletes.isEmpty, isPhoneLayout, !isPhoneLandscape {
                phonePortraitBottomChrome
            }
        }
    }

    private var editorToolbar: some View {
        HStack(spacing: 8) {
            Button(action: addAthlete) {
                EditorToolbarButtonLabel(
                    title: "Add",
                    systemImage: "plus.circle.fill",
                    isProminent: true
                )
            }
            .buttonStyle(.plain)
            .contentShape(Capsule(style: .continuous))
            .accessibilityLabel("Add Athlete")
            .help("Add a new athlete to this formation")

            if hasTransition {
                Button {
                    showingPathSettingsSheet = true
                } label: {
                    EditorToolbarButtonLabel(
                        title: "Paths",
                        systemImage: pathDisplayScope.systemImage,
                        isProminent: true
                    )
                }
                .buttonStyle(.plain)
                .contentShape(Capsule(style: .continuous))
                .accessibilityLabel("Path display: \(pathDisplayScope.label), preview \(transitionPreviewMode.label)")
                .help("Open path display and preview settings")
            }

            Button(action: undoLastMove) {
                EditorToolbarButtonLabel(
                    title: "Undo",
                    systemImage: "arrow.uturn.backward"
                )
            }
            .buttonStyle(.plain)
            .contentShape(Capsule(style: .continuous))
            .disabled(undoStack.isEmpty)
            .accessibilityLabel("Undo Move")
            .help(undoStack.isEmpty ? "Nothing to undo" : "Undo the last move")

            Menu {
                editorMoreMenuContent
            } label: {
                EditorToolbarButtonLabel(
                    title: "More",
                    systemImage: "ellipsis.circle",
                    indicatorColor: editorMoreIndicatorColor
                )
            }
            .buttonStyle(.plain)
            .contentShape(Capsule(style: .continuous))
            .accessibilityLabel("More actions")
            .accessibilityValue(formation?.notes.isEmpty == false ? "Has notes" : "")
            .help("More actions")
        }
    }

    private var editorMoreIndicatorColor: Color? {
        if !collidingAthletes.isEmpty {
            return .red
        }
        if showTransitionPaths, !pathCollidingAthletes.isEmpty {
            return .orange
        }
        if formation?.notes.isEmpty == false {
            return .orange
        }
        return nil
    }

    @ViewBuilder
    private var editorMoreMenuContent: some View {
        if !collidingAthletes.isEmpty {
            Button {
                collisionCycleIndex = (collisionCycleIndex + 1) % collidingAthletes.count
                selectCollision(at: collisionCycleIndex)
            } label: {
                Label("\(collidingAthletes.count) Spacing Alerts", systemImage: "exclamationmark.triangle.fill")
            }
        }

        if showTransitionPaths, !pathCollidingAthletes.isEmpty {
            Button {
                pathCollisionCycleIndex = (pathCollisionCycleIndex + 1) % pathCollidingAthletes.count
                selectPathCollision(at: pathCollisionCycleIndex)
            } label: {
                Label("\(pathCollidingAthletes.count) Path Conflicts", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
            }
        }

        if !collidingAthletes.isEmpty || (showTransitionPaths && !pathCollidingAthletes.isEmpty) {
            Divider()
        }

        if isCompactLayout, !isPhoneLayout {
            Button {
                showingInspectorSheet = true
            } label: {
                Label(compactInspectButtonTitle, systemImage: "slider.horizontal.3")
            }

            if hasTransition, startFormationName != nil, endFormationName != nil {
                Button {
                    showingTransportSheet = true
                } label: {
                    Label("Preview", systemImage: "play.circle")
                }
            }

            Divider()
        }

        if hasTransition, !selectedAthleteIDs.isEmpty {
            Button(action: toggleExplicitPathDrawMode) {
                Label(explicitPathDrawButtonTitle, systemImage: explicitPathDrawButtonSystemImage)
            }
            .disabled(!isExplicitPathDrawMode && !canBeginExplicitPathDraw)
        }

        if store.routine.formations.count >= 2, let onPlayRoutine {
            Button(action: onPlayRoutine) {
                Label(
                    entitlementManager.isPro ? "Play Routine" : "Play Routine (Pro)",
                    systemImage: entitlementManager.isPro ? "play.fill" : "lock.fill"
                )
            }
        }

        if let onEnterFullScreen {
            Button(action: onEnterFullScreen) {
                Label("Enter Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
            }
        }

        if hasTransition || onPlayRoutine != nil || onEnterFullScreen != nil {
            Divider()
        }

        secondaryEditorMenuContent
    }

    @ViewBuilder
    private var secondaryEditorMenuContent: some View {
        if canShareTransition {
            Button(action: shareTransitionPreview) {
                Label("Share Preview", systemImage: "square.and.arrow.up")
            }
        }

        Button(action: {
            if entitlementManager.isPro {
                showingPDFExportSheet = true
            } else {
                showingUpgradeSheet = true
            }
        }) {
            Label(
                entitlementManager.isPro ? "Export PDF" : "Export PDF (Pro)",
                systemImage: entitlementManager.isPro ? "doc.text" : "lock.fill"
            )
        }

        Button(action: { showingRosterSheet = true }) {
            Label("Roster", systemImage: "list.bullet.rectangle")
        }

        Button(action: { showingNotesSheet = true }) {
            Label("Notes", systemImage: "note.text")
        }

        Button(action: { showingMoreAppsSheet = true }) {
            Label("More Coaching Tools", systemImage: "square.grid.2x2")
        }

        Divider()

        Button(action: onDuplicateAsNext) {
            Label(
                canAddFormation ? "Duplicate as Next" : "Duplicate as Next (Pro)",
                systemImage: canAddFormation ? "plus.square.on.square" : "lock.fill"
            )
        }

        Button(action: { onRenameFormation?() }) {
            Label("Rename Formation", systemImage: "pencil")
        }

        let index = formationIndex ?? 0
        Button(action: { store.moveFormationEarlier(id: formationID) }) {
            Label("Move Earlier", systemImage: "arrow.up")
        }
        .disabled(index == 0)
        .help(index == 0 ? "Already at the first formation" : "Move formation earlier")

        Button(action: { store.moveFormationLater(id: formationID) }) {
            Label("Move Later", systemImage: "arrow.down")
        }
        .disabled(index >= store.routine.formations.count - 1)
        .help(index >= store.routine.formations.count - 1 ? "Already at the last formation" : "Move formation later")

        Divider()

        if hasTransition {
            Button(action: resetSelectedPaths) {
                Label(selectedAthleteIDs.count == 1 ? "Reset Path" : "Reset Paths", systemImage: "arrow.counterclockwise")
            }
        } else {
            Button(action: resetView) {
                Label("Reset View", systemImage: "arrow.counterclockwise")
            }
            .accessibilityLabel("Reset View")
        }

        Divider()

        Button(role: .destructive, action: { onDeleteFormation?() }) {
            Label("Delete Formation", systemImage: "trash")
        }

        Button(role: .destructive, action: { onResetRoutine?() }) {
            Label("Reset Routine", systemImage: "arrow.counterclockwise")
        }
    }

    private var controlStrip: some View {
        Group {
            HStack(spacing: isCompactLayout ? 8 : 12) {
                if !collidingAthletes.isEmpty {
                    Button {
                        collisionCycleIndex = (collisionCycleIndex + 1) % collidingAthletes.count
                        selectCollision(at: collisionCycleIndex)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("\(collidingAthletes.count)")
                        }
                        .font(.caption.weight(.bold))
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.red.opacity(0.15), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Athlete spacing alerts")
                    .help("Athletes too close together — tap to cycle through collisions")
                }

                if showTransitionPaths, !pathCollidingAthletes.isEmpty {
                    Button {
                        pathCollisionCycleIndex = (pathCollisionCycleIndex + 1) % pathCollidingAthletes.count
                        selectPathCollision(at: pathCollisionCycleIndex)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                            Text("\(pathCollidingAthletes.count)")
                        }
                        .font(.caption.weight(.bold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.orange.opacity(0.15), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Path crossing alerts")
                    .help("Transition paths cross — tap to cycle through conflicts")
                }

                Button(action: addAthlete) {
                    Label("Add", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Add Athlete")
                .help("Add a new athlete to this formation")

                if hasTransition {
                    Button {
                        showingPathSettingsSheet = true
                    } label: {
                        Label("Paths", systemImage: pathDisplayScope.systemImage)
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Path display: \(pathDisplayScope.label), preview \(transitionPreviewMode.label)")
                    .help("Open path display and preview settings")
                }

                if isCompactLayout {
                    Group {
                        if selectedAthleteIDs.isEmpty {
                            Button {
                                showingInspectorSheet = true
                            } label: {
                                Label(compactInspectButtonTitle, systemImage: "slider.horizontal.3")
                            }
                            .buttonStyle(.bordered)
                            .help("Open inspector to edit athlete details")
                        } else {
                            Button {
                                showingInspectorSheet = true
                            } label: {
                                Label(compactInspectButtonTitle, systemImage: "slider.horizontal.3")
                            }
                            .buttonStyle(.borderedProminent)
                            .help("Open inspector to edit selected athlete")
                        }
                    }
                }

                if isCompactLayout, !isPhoneLayout, hasTransition, startFormationName != nil, endFormationName != nil {
                    Button {
                        showingTransportSheet = true
                    } label: {
                        Label("Preview", systemImage: "play.circle")
                    }
                    .buttonStyle(.bordered)
                    .help("Preview the transition animation between formations")
                }

                if hasTransition {
                    if !selectedAthleteIDs.isEmpty {
                        Button(action: toggleExplicitPathDrawMode) {
                            Label(
                                explicitPathDrawButtonTitle,
                                systemImage: explicitPathDrawButtonSystemImage
                            )
                        }
                        .buttonStyle(.bordered)
                        .disabled(!isExplicitPathDrawMode && !canBeginExplicitPathDraw)
                        .accessibilityLabel(drawPathButtonTitle)
                        .help("Draw a path directly on the floor")
                    }

                    Button(action: shareTransitionPreview) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Share Preview")
                    .help("Export an animated preview of this transition")
                }

                if isCompactLayout {
                    compactOverflowMenu
                } else {
                    Button(action: { showingRosterSheet = true }) {
                        Label("Roster", systemImage: "list.bullet.rectangle")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Manage Roster")
                    .help("Add, remove, or rename athletes on the team roster")

                    Button(action: {
                        if entitlementManager.isPro {
                            showingPDFExportSheet = true
                        } else {
                            showingUpgradeSheet = true
                        }
                    }) {
                        Label(entitlementManager.isPro ? "Export PDF" : "Export PDF (Pro)",
                              systemImage: entitlementManager.isPro ? "doc.text" : "lock.fill")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(entitlementManager.isPro ? "Export PDF Playbook" : "Upgrade to Pro to export PDF Playbook")
                    .help("Export formation playbook as a configurable PDF")

                    if hasTransition {
                        Button(action: resetSelectedPaths) {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(selectedAthleteIDs.count == 1 ? "Reset Path" : "Reset Paths")
                        .help(selectedAthleteIDs.count == 1 ? "Reset this athlete's path to straight" : "Reset all athlete paths to straight")
                    } else {
                        Button(action: resetView) {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Reset View")
                        .help("Reset zoom and pan back to the default view")
                    }

                    Button(action: { showingNotesSheet = true }) {
                        Label("Notes", systemImage: "note.text")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityValue(formation?.notes.isEmpty == false ? "Has notes" : "")
                    .help("Add notes or reminders for this formation")
                    .overlay(alignment: .topTrailing) {
                        if formation?.notes.isEmpty == false {
                            Circle()
                                .fill(.orange)
                                .frame(width: 8, height: 8)
                                .offset(x: 2, y: -2)
                        }
                    }

                    Button(action: undoLastMove) {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)
                    .disabled(undoStack.isEmpty)
                    .accessibilityLabel("Undo Move")
                    .help("Undo the last athlete position change")
                }
            }
            .controlSize(isCompactLayout || isHeightConstrained ? .small : .regular)
            .padding(.horizontal, 16)
            .padding(.vertical, isHeightConstrained ? 6 : (isCompactLayout ? 8 : 8))
        }
        .background(.bar)
    }

    private var compactOverflowMenu: some View {
        Menu {
            Button(action: { showingRosterSheet = true }) {
                Label("Roster", systemImage: "list.bullet.rectangle")
            }

            Button(action: { showingNotesSheet = true }) {
                Label("Notes", systemImage: "note.text")
            }

            Button(action: { showingMoreAppsSheet = true }) {
                Label("More Coaching Tools", systemImage: "square.grid.2x2")
            }

            Button(action: {
                if entitlementManager.isPro {
                    showingPDFExportSheet = true
                } else {
                    showingUpgradeSheet = true
                }
            }) {
                Label(entitlementManager.isPro ? "Export PDF" : "Export PDF (Pro)",
                      systemImage: entitlementManager.isPro ? "doc.text" : "lock.fill")
            }

            if !hasTransition {
                Button(action: mirrorFormation) {
                    Label("Mirror Formation", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right.fill")
                }
            }

            if hasTransition {
                Button(action: resetSelectedPaths) {
                    Label(selectedAthleteIDs.count == 1 ? "Reset Path" : "Reset Paths", systemImage: "arrow.counterclockwise")
                }
            } else {
                Button(action: resetView) {
                    Label("Reset View", systemImage: "arrow.counterclockwise")
                }
                .accessibilityLabel("Reset View")
            }

            Button(action: undoLastMove) {
                Label("Undo Move", systemImage: "arrow.uturn.backward")
            }
            .disabled(undoStack.isEmpty)
            .help(undoStack.isEmpty ? "Nothing to undo" : "Undo the last move")
        } label: {
            compactOverflowMenuLabel
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("More actions")
        .accessibilityHint("Open menu for additional formation actions")
        .help("More actions")
        .accessibilityValue(formation?.notes.isEmpty == false ? "Has notes" : "")
    }

    private var compactOverflowMenuLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "ellipsis.circle")
            Text("More")
        }
        .overlay(alignment: .topTrailing) {
            if formation?.notes.isEmpty == false {
                Circle()
                    .fill(.orange)
                    .frame(width: 8, height: 8)
                    .offset(x: 4, y: -4)
            }
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            VStack(spacing: isHeightConstrained ? 10 : 18) {
                Image(systemName: "figure.stand.line.dotted.figure.stand")
                    .font(.system(size: isHeightConstrained ? 32 : 52))
                    .foregroundColor(.coral)
                Text("Start your first picture")
                    .font(isHeightConstrained ? .headline : .title2.weight(.semibold))
                if !isHeightConstrained {
                    Text("Add one athlete, drop in a 10-athlete template, or duplicate after you have a picture to build from.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                }

                Group {
                    if isHeightConstrained {
                        VStack(spacing: 8) {
                            Button(action: addAthlete) {
                                Label("Add Athlete", systemImage: "plus.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)

                            Button(action: applyTemplate) {
                                Label("10-Athlete Template", systemImage: "square.grid.3x3.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        .controlSize(.small)
                    } else if isCompactLayout {
                        VStack(spacing: 12) {
                            Button(action: addAthlete) {
                                Label("Add Athlete", systemImage: "plus.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .help("Place a single athlete on the floor")

                            Button(action: applyTemplate) {
                                Label("Apply 10-Athlete Template", systemImage: "square.grid.3x3.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .help("Place 10 athletes in a bowling-pin formation")

                            Button(action: onDuplicateAsNext) {
                                Label("Duplicate as Next Formation", systemImage: "plus.square.on.square")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(renderedAthletes.isEmpty)
                            .help(renderedAthletes.isEmpty ? "Add athletes to copy to a new formation" : "Copy this formation's positions into a new formation")
                        }
                    } else {
                        HStack(spacing: 12) {
                            Button(action: addAthlete) {
                                Label("Add Athlete", systemImage: "plus.circle.fill")
                                    .frame(minWidth: 180)
                            }
                            .buttonStyle(.borderedProminent)
                            .help("Place a single athlete on the floor")

                            Button(action: applyTemplate) {
                                Label("Apply 10-Athlete Template", systemImage: "square.grid.3x3.fill")
                                    .frame(minWidth: 220)
                            }
                            .buttonStyle(.bordered)
                            .help("Place 10 athletes in a bowling-pin formation")

                            Button(action: onDuplicateAsNext) {
                                Label("Duplicate as Next Formation", systemImage: "plus.square.on.square")
                                    .frame(minWidth: 220)
                            }
                            .buttonStyle(.bordered)
                            .disabled(renderedAthletes.isEmpty)
                            .help(renderedAthletes.isEmpty ? "Add athletes to copy to a new formation" : "Copy this formation's positions into a new formation")
                        }
                    }
                }
            }
            .padding(isHeightConstrained ? 16 : 32)
            .formationGlassPanel(cornerRadius: 24, material: .thinMaterial, shadowRadius: 16)
            .padding(.horizontal, isHeightConstrained ? 12 : (isCompactLayout ? 20 : 0))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private var canvasArea: some View {
        GeometryReader { geometry in
            let baseCellSize = min(
                geometry.size.width / CourtConstants.width,
                geometry.size.height / CourtConstants.height
            )
            let cellSize = baseCellSize * zoomScale
            let canvasWidth = CourtConstants.width * cellSize
            let canvasHeight = CourtConstants.height * cellSize
            let canvasSize = CGSize(width: canvasWidth, height: canvasHeight)
            let displayPanOffset = clampedCanvasPanOffset(
                canvasPanOffset,
                viewportSize: geometry.size,
                canvasSize: canvasSize
            )
            let offset = CGPoint(
                x: (geometry.size.width - canvasWidth) / 2 + displayPanOffset.width,
                y: (geometry.size.height - canvasHeight) / 2 + displayPanOffset.height
            )

            let baseCanvasContent = FloorCanvasView(
                athletes: renderedAthletes,
                selectedAthleteIDs: selectedAthleteIDs,
                groupedAthleteIDSets: activeTransitionGroupIDSets,
                transitionPaths: displayedTransitionPaths,
                endpointMarkers: endpointMarkers,
                alignmentGuides: activeAlignmentGuides,
                mirrorGuides: activeMirrorGuides,
                collisionIDs: collisionSummary.ids,
                pathCollisionIDs: pathCollisionIDs,
                pathCollisionMarkerPositions: player?.cachedPathCollisionMarkers ?? [],
                pathCollisionMarkerProgresses: player?.cachedPathCollisionMarkerProgresses ?? [],
                pathCollisionStartProgresses: player?.cachedPathCollisionStartProgresses ?? [:],
                animatePathCollisionWarnings: !isCanvasInteractionActive,
                cellSize: cellSize,
                offset: offset,
                swapSourceID: swapSourceAthleteID,
                selectionLasso: selectionLassoForDisplay,
                focusedEndpoint: focusedEndpoint,
                hasTransition: hasTransition,
                startFormationColor: transitionStartColor,
                endFormationColor: transitionEndColor,
                transitionProgress: displayProgress,
                formationColor: currentFormationColor,
                showPathPulse: hasTransition && showTransitionPaths && (player?.isPlaying != true) && !isCanvasInteractionActive && transitionPreviewMode == .flow,
                transitionCounts: player?.counts ?? 8,
                showCountSteps: hasTransition && showTransitionPaths && (player?.isPlaying != true) && !isCanvasInteractionActive && transitionPreviewMode == .step,
                ghostAthletes: pathDisplayScope == .allFormations ? previousFormationAthletes : [],
                ghostColor: previousFormationColor,
                ghostNextAthletes: pathDisplayScope == .allFormations ? nextFormationAthletes : [],
                ghostNextColor: nextFormationColor,
                ghostPrevPaths: displayedPrevGhostPaths,
                ghostNextPaths: displayedNextGhostPaths,
                pathSketchPoints: pathSketchPoints,
                pathSketchPreviewPaths: pathSketchPreviewPaths,
                hoveredHandlePosition: hoveredHandlePosition,
                hoveredAthleteID: hoveredAthleteID,
                hoveredPathAthleteID: hoveredPathAthleteID,
                focusedPathHandle: focusedPathHandle,
                draggingAthleteIDs: draggingAthleteIDs,
                dimUnselectedAthletes: dimUnselectedAthletes
            )
            .gesture(
                dragGesture(
                    cellSize: cellSize,
                    offset: offset,
                    viewportSize: geometry.size,
                    canvasSize: canvasSize
                )
            )
            .simultaneousGesture(waypointDoubleTapGesture(cellSize: cellSize, offset: offset))
            .simultaneousGesture(longPressSketchGesture(cellSize: cellSize, offset: offset))
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        handleSpacingMagnification(value.magnification)
                    }
                    .onEnded { value in
                        finishSpacingMagnification(value.magnification)
                    }
            )
            .simultaneousGesture(
                RotationGesture()
                    .onChanged { value in
                        guard selectedAthleteIDs.count >= 2, spacingStartPositions.isEmpty else { return }
                        if rotationStartPositions.isEmpty {
                            // Capture starting positions for undo + rotation reference
                            rotationStartPositions = renderedAthletes.reduce(into: [UUID: CGPoint]()) { result, athlete in
                                if selectedAthleteIDs.contains(athlete.id) {
                                    if result[athlete.id] == nil { result[athlete.id] = athlete.position }
                                }
                            }
                            lastRotationDetent = 0
                            rotationDidApplyChange = false
                        }
                        // Hard-cut to 45° detents — the formation only ever lands on a
                        // clean grid-aligned orientation, never an awkward in-between.
                        let detent = rotationDetent(for: value.radians)
                        guard detent != lastRotationDetent else { return }
                        lastRotationDetent = detent
                        UISelectionFeedbackGenerator().selectionChanged()
                        applyRotation(angle: CGFloat(detent) * rotationSnapIncrement)
                    }
                    .onEnded { value in
                        guard selectedAthleteIDs.count >= 2, !rotationStartPositions.isEmpty else {
                            rotationStartPositions = [:]
                            lastRotationDetent = 0
                            rotationDidApplyChange = false
                            return
                        }
                        let detent = rotationDetent(for: value.radians)
                        if detent != lastRotationDetent {
                            applyRotation(angle: CGFloat(detent) * rotationSnapIncrement)
                        }
                        // A net rotation of zero is a no-op for undo, even if the
                        // live gesture crossed a detent and returned to its start.
                        if detent != 0 {
                            appendUndoSnapshot(positions: rotationStartPositions)
                        }
                        if rotationDidApplyChange {
                            refreshTransitionFromStore()
                        }
                        rotationStartPositions = [:]
                        lastRotationDetent = 0
                        rotationDidApplyChange = false
                    }
            )
            #if canImport(UIKit)
            // Two-finger tap = play/pause. Two-finger pan = scrub whenever a
            // transition exists, except while a multi-selection owns two-finger
            // gestures for spacing and rotation.
            .background(
                TwoFingerPlaybackGesture(
                    playbackEnabled: selectedAthleteIDs.count < 2,
                    scrubEnabled: hasTransition,
                    onPlayToggle: {
                        guard let player, hasTransition else { return }
                        player.isPlaying ? player.pause() : player.play()
                    },
                    currentProgress: { player?.progress ?? 0 },
                    onScrubBegan: { player?.pause() },
                    onSeek: { player?.seek(to: $0) }
                )
            )
            #endif

            let canvasContent = baseCanvasContent
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let scaledPoint = CGPoint(
                        x: (location.x - offset.x) / cellSize,
                        y: (location.y - offset.y) / cellSize
                    )
                    if let nearestHandle = nearestPathHandle(at: scaledPoint, cellSize: cellSize) {
                        hoveredHandlePosition = nearestHandle
                        hoveredAthleteID = nil
                        hoveredPathAthleteID = nil
                    } else {
                        hoveredHandlePosition = nil
                        hoveredAthleteID = athleteHit(at: scaledPoint, within: renderedAthletes, cellSize: cellSize)?.id
                        if hoveredAthleteID == nil,
                           let hit = selectedTransitionPathHit(
                            at: scaledPoint,
                            maxSquaredDistance: pathHitRadiusSquared(for: cellSize)
                           )
                        {
                            hoveredPathAthleteID = hit.transition.athleteID
                        } else {
                            hoveredPathAthleteID = nil
                        }
                    }
                case .ended:
                    hoveredHandlePosition = nil
                    hoveredAthleteID = nil
                    hoveredPathAthleteID = nil
                }
            }
            .overlay(alignment: .top) {
                if !isPhoneLayout {
                    VStack(spacing: isCompactLayout ? 8 : 10) {
                        if isSwapMode, let athlete = swapSourceRosterAthlete {
                            swapBanner(athleteLabel: athlete.label)
                        } else if let pathSketchStatusText {
                            banner(text: pathSketchStatusText, color: .coral)
                        } else if isCompactLayout {
                            if let compactBannerConfiguration {
                                banner(text: compactBannerConfiguration.text, color: compactBannerConfiguration.color)
                            }
                        } else if !hasMadeFirstSelection {
                            banner(
                                text: "Tap an athlete to edit it. Drag on empty space to lasso-select.",
                                color: .coral
                            )
                        }
                    }
                    .padding(.horizontal, isCompactLayout ? 12 : 0)
                    .padding(.top, isHeightConstrained ? 4 : 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            canvasContent
                .overlay(alignment: .topLeading) {
                    // Render the ring overlay unconditionally so SwiftUI keeps a
                    // stable view identity for `.trim` — otherwise the first
                    // appearance has no prior value to interpolate from and the
                    // 0→1 fill is skipped. Opacity-gate visibility instead.
                    let armingPos = longPressArmingPosition ?? .zero
                    let screenPos = CGPoint(
                        x: armingPos.x * cellSize + offset.x,
                        y: armingPos.y * cellSize + offset.y
                    )
                    // Diameter must clear the selected athlete's circle in both
                    // modes: in formation-only mode the athlete is cellSize*3.0
                    // wide (markerScale=cellSize/12, selectedMarkerRadius=18), so
                    // anything ≤ that disappears behind the athlete. Bump to 4.0
                    // for a consistent ring outside the athlete edge.
                    let diameter = max(56, cellSize * 4.0)
                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.18), lineWidth: max(2.5, cellSize * 0.22))
                        Circle()
                            .trim(from: 0, to: longPressProgress)
                            .stroke(
                                .white.opacity(0.95),
                                style: StrokeStyle(lineWidth: max(2.5, cellSize * 0.22), lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: diameter, height: diameter)
                    .position(screenPos)
                    .opacity(isLongPressCountdownVisible ? 1 : 0)
                    .allowsHitTesting(false)
                }
                .overlay(alignment: .bottom) {
                    pathSaveRecoveryBar
                        .padding(.horizontal, 12)
                        .padding(.bottom, pathSaveRecoveryBottomPadding)
                }
                .overlay(alignment: .bottomLeading) {
                    if !isPhoneLayout && !hideFormationContextBadge {
                        formationContextBadge
                            .padding(.init(top: 0, leading: 12, bottom: 12, trailing: 0))
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    resetViewFloatingButton
                        .padding(.trailing, 12)
                        .padding(.bottom, 12)
                        .animation(.spring(), value: isViewTransformed)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Formation Context Badge

    private var formationContextBadge: some View {
        let currentIndex = formationIndex ?? 0
        let total = max(1, store.routine.formations.count)
        // Into = selected formation is the transition's destination (end);
        // Out of = it's the source (start). nil when there's no transition.
        let direction: TransitionBadgeDirection? = hasTransition
            ? (endFormationID == formationID ? .into : .outOf)
            : nil
        return FormationPipBadge(
            currentIndex: currentIndex,
            total: total,
            formationName: formation?.name ?? "Formation",
            showsFormationTitle: !(isPhoneLayout && !isPhoneLandscape),
            direction: direction,
            canInto: !isFirstFormation,
            canOutOf: !isLastFormation,
            onToggleDirection: onToggleTransitionDirection,
            onPrev: { onCyclePreviousFormation?() },
            onNext: { onCycleFormation?() },
            onRename: onRenameFormation
        )
        .accessibilityLabel(formationContextLabel)
    }

    private func setTransitionCounts(_ newCounts: Int) {
        guard let startFormationID, let endFormationID else { return }
        store.mutateTransitionSpec(from: startFormationID, to: endFormationID) { spec in
            spec.duration = Double(min(32, max(1, newCounts)))
        }
        refreshTransitionFromStore()
    }

    private var compactInspectorSheet: some View {
        NavigationStack {
            ScrollView {
                SidebarInspectorView(
                    store: store,
                    formationID: formationID,
                    selectedAthleteIDs: $selectedAthleteIDs,
                    isCompactLayout: true,
                    onDeleteAthlete: { deleteSelectedAthlete() },
                    player: player,
                    startFormationID: startFormationID,
                    endFormationID: endFormationID,
                    isPro: entitlementManager.isPro,
                    onUpgrade: { showingUpgradeSheet = true },
                    onRefreshTransition: { refreshTransitionFromStore() },
                    onDrawPath: { toggleExplicitPathDrawMode() }
                )
            }
            .navigationTitle(compactInspectorTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !selectedAthleteIDs.isEmpty {
                        Button("Clear") {
                            selectedAthleteIDs = []
                            showingInspectorSheet = false
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingInspectorSheet = false
                    }
                }
            }
        }
        .presentationDetents(isPhoneLayout ? [.medium, .large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    private var pathSettingsSheet: some View {
        NavigationStack {
            Form {
                Section("Visible Paths") {
                    Picker("Show", selection: Binding(
                        get: { pathDisplayScope },
                        set: { pathDisplayScopeRaw = $0.rawValue }
                    )) {
                        ForEach(PathDisplayScope.allCases) { scope in
                            Label(scope.label, systemImage: scope.systemImage).tag(scope)
                        }
                    }
                }

                Section("Visualizer") {
                    Picker("Mode", selection: Binding(
                        get: { transitionPreviewMode },
                        set: { transitionPreviewModeRaw = $0.rawValue }
                    )) {
                        ForEach(TransitionPreviewMode.allCases) { mode in
                            Label(mode.label, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Paths")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingPathSettingsSheet = false
                    }
                }
            }
        }
        .presentationDetents(isPhoneLayout ? [.medium] : [.fraction(0.35)])
        .presentationDragIndicator(.visible)
    }

    private var compactTransportSheet: some View {
        NavigationStack {
            if let player, let startFormationName, let endFormationName {
                TransitionTransportSidebarView(
                    player: player,
                    startFormationName: startFormationName,
                    endFormationName: endFormationName,
                    onSwap: toggleSwapMode,
                    onPath: { showingInspectorSheet = true },
                    isSwapMode: isSwapMode,
                    canSwap: selectedAthleteID != nil,
                    canEditPath: selectedAthleteID != nil,
                    onPreviousFormation: { onCyclePreviousFormation?() },
                    onNextFormation: { onCycleFormation?() },
                    isFirstFormation: isFirstFormation,
                    isLastFormation: isLastFormation,
                    onAdjustCounts: { setTransitionCounts($0) },
                    countsLocked: !entitlementManager.isPro,
                    onLockedCounts: { showingUpgradeSheet = true }
                )
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showingTransportSheet = false
                        }
                    }
                }
            } else {
                ContentUnavailableView("Transition unavailable", systemImage: "play.slash")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showingTransportSheet = false
                            }
                        }
                    }
            }
        }
        .presentationDetents(isPhoneLayout ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }


    private var pathSaveRecoveryBottomPadding: CGFloat { 18 }

    @ViewBuilder
    private var pathSaveRecoveryBar: some View {
        if let snapshot = recentPathEditSnapshot {
            HStack(spacing: 10) {
                Label(snapshot.message, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Button("Undo", action: undoRecentPathEdit)
                    .buttonStyle(.bordered)

                Button("Straighten", action: straightenRecentPathEdit)
                    .buttonStyle(.bordered)

                Button("Edit") {
                    selectedAthleteIDs = snapshot.selectedAthleteIDs
                    showingInspectorSheet = true
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(.primary)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var rosterSheet: some View {
        RosterManagementView(
            store: store,
            onAddAthlete: {
                showingRosterSheet = false
                addAthlete()
            },
            onDeleteAthletes: requestRosterAthleteDeletion
        )
        .environmentObject(entitlementManager)
    }

    private var notesSheet: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                TextEditor(
                    text: Binding(
                        get: { formation?.notes ?? "" },
                        set: { newValue in
                            store.mutateFormation(id: formationID) { formation in
                                formation.notes = newValue
                            }
                        }
                    )
                )
                .padding(8)

                if formation?.notes.isEmpty != false {
                    Text("Add notes for this formation — counts, cues, or reminders.")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .navigationTitle("\(formation?.name ?? "Formation") Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showingNotesSheet = false }
                }
            }
        }
        .presentationDetents(isPhoneLayout ? [.medium, .large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func banner(text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle.fill")
                .font(.caption2)
            Text(text)
                .font(.caption2.weight(.medium))
                .lineLimit(isPhoneLayout ? 2 : 1)
                .minimumScaleFactor(isPhoneLayout ? 0.85 : 1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundColor(color)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.2), lineWidth: 0.5))
    }

    @ViewBuilder
    private func swapBanner(athleteLabel: String) -> some View {
        VStack(spacing: 6) {
            banner(text: "Tap another athlete to swap with \(athleteLabel).", color: .coral)

            if hasTransition, let startFormationName, let endFormationName {
                Picker("Swap in", selection: $swapFormationTarget) {
                    Text(startFormationName).tag(SwapFormationTarget.start)
                    Text(endFormationName).tag(SwapFormationTarget.end)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Swap target formation")
                .accessibilityHint("Choose whether to swap athletes in the start or end formation")
                .frame(maxWidth: 260)
                .onChange(of: swapFormationTarget) { _, target in
                    player?.pause()
                    player?.seek(to: target == .start ? 0 : 1)
                }
            }
        }
    }

    private func athleteHitRadiusSquared(for athlete: RenderedAthlete, cellSize: CGFloat) -> CGFloat {
        let baseRadius = sqrt(interactionHitRadiusSquared(for: cellSize))
        // Use the visible marker radius, not the expanded selected radius. This
        // keeps selection precise when athletes overlap while leaving the drawn
        // selected state and accessibility overlay unchanged.
        let markerRadius = athlete.role.markerRadius / max(cellSize, 1)
        let radius = max(baseRadius, markerRadius)
        return radius * radius
    }

    private func athleteHit(
        at point: CGPoint,
        within athletes: [RenderedAthlete],
        cellSize: CGFloat,
        excluding excludedID: UUID? = nil
    ) -> RenderedAthlete? {
        athleteHits(
            at: point,
            within: athletes,
            cellSize: cellSize,
            excluding: excludedID
        ).first
    }

    private func athleteHits(
        at point: CGPoint,
        within athletes: [RenderedAthlete],
        cellSize: CGFloat,
        excluding excludedID: UUID? = nil
    ) -> [RenderedAthlete] {
        athletes
            .compactMap { athlete -> (athlete: RenderedAthlete, distance: CGFloat)? in
                guard athlete.id != excludedID else { return nil }

                let distance = PathCalculations.squaredDistance(from: point, to: athlete.position)
                guard distance < athleteHitRadiusSquared(for: athlete, cellSize: cellSize) else { return nil }
                return (athlete, distance)
            }
            .sorted {
                if abs($0.distance - $1.distance) > 0.0001 {
                    return $0.distance < $1.distance
                }
                if $0.athlete.label != $1.athlete.label {
                    return $0.athlete.label.localizedStandardCompare($1.athlete.label) == .orderedAscending
                }
                return $0.athlete.id.uuidString < $1.athlete.id.uuidString
            }
            .map(\.athlete)
    }

    private func preferredAthleteHit(
        at point: CGPoint,
        within athletes: [RenderedAthlete],
        cellSize: CGFloat,
        preferredID: UUID? = nil,
        excluding excludedID: UUID? = nil
    ) -> RenderedAthlete? {
        let candidates = athleteHits(
            at: point,
            within: athletes,
            cellSize: cellSize,
            excluding: excludedID
        )

        guard !candidates.isEmpty else { return nil }

        if let preferredID,
           let preferredAthlete = candidates.first(where: { $0.id == preferredID })
        {
            return preferredAthlete
        }

        return candidates.first
    }

    private func nearestOrTiedCycledAthleteHit(
        at point: CGPoint,
        within athletes: [RenderedAthlete],
        cellSize: CGFloat,
        excluding excludedID: UUID? = nil
    ) -> RenderedAthlete? {
        let candidates = athletes
            .compactMap { athlete -> (athlete: RenderedAthlete, distance: CGFloat)? in
                guard athlete.id != excludedID else { return nil }

                let distance = PathCalculations.squaredDistance(from: point, to: athlete.position)
                guard distance < athleteHitRadiusSquared(for: athlete, cellSize: cellSize) else { return nil }
                return (athlete, distance)
            }
            .sorted {
                if abs($0.distance - $1.distance) > 0.0001 {
                    return $0.distance < $1.distance
                }
                if $0.athlete.label != $1.athlete.label {
                    return $0.athlete.label.localizedStandardCompare($1.athlete.label) == .orderedAscending
                }
                return $0.athlete.id.uuidString < $1.athlete.id.uuidString
            }

        guard let nearest = candidates.first else { return nil }

        // The normal rule is "closest to the finger wins." Only cycle when
        // athletes are truly stacked/equidistant, where there is no closer
        // athlete to choose. Cycling the full hit-radius set is what made a
        // previously selected neighbor appear to be favored after a correct
        // momentary highlight.
        let tiedNearest = candidates.filter { abs($0.distance - nearest.distance) <= 0.0001 }
        guard tiedNearest.count > 1, let selectedAthleteID else { return nearest.athlete }

        guard let selectedIndex = tiedNearest.firstIndex(where: { $0.athlete.id == selectedAthleteID }) else {
            return nearest.athlete
        }

        return tiedNearest[(selectedIndex + 1) % tiedNearest.count].athlete
    }

    private func nearestPointOnTransitionPath(
        at point: CGPoint,
        transition: AthleteTransition,
        startAthlete: RenderedAthlete,
        endAthlete: RenderedAthlete
    ) -> (point: CGPoint, segmentIndex: Int, squaredDistance: CGFloat)? {
        if transition.pathWaypoints.isEmpty, let controlPoint = transition.pathControlPoint {
            var best: (point: CGPoint, segmentIndex: Int, squaredDistance: CGFloat)?
            var previous = startAthlete.position
            let steps = 24

            for step in 1...steps {
                let t = CGFloat(step) / CGFloat(steps)
                let current = PathCalculations.quadraticBezierPoint(
                    from: startAthlete.position,
                    control: controlPoint,
                    to: endAthlete.position,
                    t: t
                )
                let dx = current.x - previous.x
                let dy = current.y - previous.y
                let lenSq = dx * dx + dy * dy
                let projectionT: CGFloat
                if lenSq < 0.0001 {
                    projectionT = 0
                } else {
                    projectionT = max(0, min(1, ((point.x - previous.x) * dx + (point.y - previous.y) * dy) / lenSq))
                }
                let projection = CGPoint(
                    x: previous.x + dx * projectionT,
                    y: previous.y + dy * projectionT
                )
                let d2 = PathCalculations.squaredDistance(from: point, to: projection)
                if best == nil || d2 < best!.squaredDistance {
                    best = (projection, step - 1, d2)
                }
                previous = current
            }

            return best
        }

        let nodes = PathCalculations.waypointNodes(
            from: startAthlete.position,
            to: endAthlete.position,
            waypoints: transition.pathWaypoints
        )
        guard nodes.count >= 2 else { return nil }

        var best: (point: CGPoint, segmentIndex: Int, squaredDistance: CGFloat)?
        for segIdx in 0..<(nodes.count - 1) {
            let p0 = nodes[segIdx]
            let p1 = nodes[segIdx + 1]

            if segmentUsesSmoothWaypoint(segmentIndex: segIdx, waypoints: transition.pathWaypoints) {
                let prevNode = segIdx > 0 ? nodes[segIdx - 1] : p0
                let nextNode = segIdx + 2 < nodes.count ? nodes[segIdx + 2] : p1
                let (c1, c2) = PathCalculations.catmullRomControlPoints(prev: prevNode, p0: p0, p1: p1, next: nextNode)
                var previous = p0
                let steps = 20

                for step in 1...steps {
                    let t = CGFloat(step) / CGFloat(steps)
                    let current = PathCalculations.cubicBezierPoint(p0: p0, c1: c1, c2: c2, p3: p1, t: t)
                    let projection = projectedPoint(onSegmentFrom: previous, to: current, nearestTo: point)
                    let d2 = PathCalculations.squaredDistance(from: point, to: projection)
                    if best == nil || d2 < best!.squaredDistance {
                        best = (projection, segIdx, d2)
                    }
                    previous = current
                }
            } else {
                let projection = projectedPoint(onSegmentFrom: p0, to: p1, nearestTo: point)
                let d2 = PathCalculations.squaredDistance(from: point, to: projection)
                if best == nil || d2 < best!.squaredDistance {
                    best = (projection, segIdx, d2)
                }
            }
        }
        return best
    }

    private func segmentUsesSmoothWaypoint(segmentIndex: Int, waypoints: [PathWaypoint]) -> Bool {
        let startsAtWaypoint = segmentIndex > 0
        let endsAtWaypoint = segmentIndex < waypoints.count

        if startsAtWaypoint && !waypoints[segmentIndex - 1].isSmooth { return false }
        if endsAtWaypoint && !waypoints[segmentIndex].isSmooth { return false }

        return startsAtWaypoint || endsAtWaypoint
    }

    private func projectedPoint(onSegmentFrom start: CGPoint, to end: CGPoint, nearestTo point: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lenSq = dx * dx + dy * dy
        let t: CGFloat
        if lenSq < 0.0001 {
            t = 0
        } else {
            t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lenSq))
        }
        return CGPoint(x: start.x + dx * t, y: start.y + dy * t)
    }

    private func selectedTransitionPathHit(
        at point: CGPoint,
        maxSquaredDistance: CGFloat
    ) -> (
        point: CGPoint,
        segmentIndex: Int,
        squaredDistance: CGFloat,
        transition: AthleteTransition,
        startAthlete: RenderedAthlete,
        endAthlete: RenderedAthlete
    )? {
        guard hasTransition, showTransitionPaths, !selectedAthleteIDs.isEmpty, let player else { return nil }

        var bestHit: (
            point: CGPoint,
            segmentIndex: Int,
            squaredDistance: CGFloat,
            transition: AthleteTransition,
            startAthlete: RenderedAthlete,
            endAthlete: RenderedAthlete
        )?

        for athleteID in selectedAthleteIDs {
            guard
                let startAthlete = player.startAthletes.first(where: { $0.id == athleteID }),
                let endAthlete = player.endAthletes.first(where: { $0.id == athleteID })
            else { continue }

            let transition = player.transitionSpec.athleteTransition(for: athleteID)
            guard let nearest = nearestPointOnTransitionPath(
                at: point,
                transition: transition,
                startAthlete: startAthlete,
                endAthlete: endAthlete
            ), nearest.squaredDistance < maxSquaredDistance else {
                continue
            }

            if bestHit == nil || nearest.squaredDistance < bestHit!.squaredDistance {
                bestHit = (
                    nearest.point,
                    nearest.segmentIndex,
                    nearest.squaredDistance,
                    transition,
                    startAthlete,
                    endAthlete
                )
            }
        }

        return bestHit
    }

    private func pathHitRadiusSquared(for cellSize: CGFloat) -> CGFloat {
        interactionHitRadiusSquared(for: cellSize) * 6
    }

    private func pathNearMissRadiusSquared(for cellSize: CGFloat) -> CGFloat {
        interactionHitRadiusSquared(for: cellSize) * 16
    }

    private func shouldSuppressMarqueeForSelectedPathNearMiss(at point: CGPoint, cellSize: CGFloat) -> Bool {
        guard !selectedAthleteIDs.isEmpty else { return false }
        return selectedTransitionPathHit(
            at: point,
            maxSquaredDistance: pathNearMissRadiusSquared(for: cellSize)
        ) != nil
    }

    private func endpointMarkerHit(
        at point: CGPoint,
        within markers: [TransitionEndpointMarkerRenderItem],
        hitRadiusSquared: CGFloat
    ) -> TransitionEndpointMarkerRenderItem? {
        markers.first {
            PathCalculations.squaredDistance(from: point, to: $0.position) < hitRadiusSquared
        }
    }

    private func toggleExplicitPathDrawMode() {
        if isExplicitPathDrawMode || isSketchingPath {
            cancelExplicitPathDrawMode()
        } else {
            beginExplicitPathDrawMode()
        }
    }

    private func beginExplicitPathDrawMode() {
        guard canBeginExplicitPathDraw else { return }
        guard entitlementManager.isPro else {
            showingUpgradeSheet = true
            return
        }

        if pathDisplayScope == .off {
            pathDisplayScopeRaw = PathDisplayScope.selectedOnly.rawValue
        }
        focusedEndpoint = currentFormationEndpoint
        focusedPathHandle = nil
        recentPathEditSnapshot = nil
        showingInspectorSheet = false
        showingTransportSheet = false
        isExplicitPathDrawMode = true
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func cancelExplicitPathDrawMode() {
        isExplicitPathDrawMode = false
        isSketchingPath = false
        isLongPressSketching = false
        pathSketchPoints = []
        pathSketchAnchorSide = nil
        longPressSketchAnchorAthleteID = nil
        bootstrapAthleteID = nil
        cancelLongPressCountdown()
    }

    private func beginExplicitPathSketch() {
        guard
            entitlementManager.isPro,
            let player,
            let endpoint = currentFormationEndpoint,
            let anchorAthleteID = TransitionPathSelectionEditing.anchorAthleteID(
                for: selectedAthleteIDs,
                in: player
            )
        else {
            cancelExplicitPathDrawMode()
            return
        }

        let anchorAthlete: RenderedAthlete?
        switch endpoint {
        case .start:
            anchorAthlete = player.startAthletes.first { $0.id == anchorAthleteID }
        case .end:
            anchorAthlete = player.endAthletes.first { $0.id == anchorAthleteID }
        }
        guard let anchorAthlete else {
            cancelExplicitPathDrawMode()
            return
        }

        focusedEndpoint = endpoint
        focusedPathHandle = nil
        longPressSketchAnchorAthleteID = anchorAthleteID
        pathSketchAnchorSide = endpoint == .start ? .start : .end
        // On the last formation there is no forward transition to edit — drawing
        // bootstraps a new formation instead (the onEnded commit routes through
        // commitBootstrapSketch when bootstrapAthleteID is set). The sketch already
        // anchors at the athlete's current position, which is the correct forward start.
        if isLastFormation, onBootstrapFromAthlete != nil {
            bootstrapAthleteID = anchorAthleteID
        }
        isSketchingPath = true
        pathSketchPoints = [clampedPathPoint(anchorAthlete.position)]
        longPressArmingToken = nil
        longPressArmingPosition = anchorAthlete.position
        longPressProgress = 1
        isLongPressCountdownVisible = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.65)
    }

    private func beginPathSketch(startingAt point: CGPoint) {
        guard entitlementManager.isPro else {
            showingUpgradeSheet = true
            return
        }

        isSketchingPath = true
        focusedEndpoint = currentFormationEndpoint
        focusedPathHandle = nil
        pathSketchPoints = [clampedPathPoint(point)]
    }

    private func handlePathSketchContinued(_ point: CGPoint) {
        let clampedPoint = clampedPathPoint(point)
        guard let lastPoint = pathSketchPoints.last else {
            pathSketchPoints = [clampedPoint]
            return
        }

        let minimumDistance: CGFloat = 0.5
        let dx = clampedPoint.x - lastPoint.x
        let dy = clampedPoint.y - lastPoint.y
        guard dx * dx + dy * dy >= minimumDistance * minimumDistance else { return }
        pathSketchPoints.append(clampedPoint)
    }

    /// Returns true if the bootstrap committed (creating a new formation).
    /// Returns false if the sketch was too short — caller should fall through
    /// to normal tap-to-select so a slow-start tap doesn't get eaten.
    private func commitBootstrapSketch(athleteID: UUID) -> Bool {
        guard pathSketchPoints.count >= 2 else { return false }
        let startPoint = clampedPathPoint(pathSketchPoints[0])
        let liftPoint = clampedPathPoint(pathSketchPoints[pathSketchPoints.count - 1])
        // Require meaningful travel — otherwise treat as a held-tap, not a path.
        let travelSquared = PathCalculations.squaredDistance(from: startPoint, to: liftPoint)
        guard travelSquared >= 4 else { return false }
        let waypoints = smoothedWaypoints(
            fromSketch: pathSketchPoints,
            start: startPoint,
            end: liftPoint
        )
        onBootstrapFromAthlete?(athleteID, liftPoint, waypoints)
        return true
    }

    private func resolvedSketchEndpoints(
        anchorStart: CGPoint,
        anchorEnd: CGPoint,
        emitSnapFeedback: Bool = false
    ) -> (start: CGPoint, end: CGPoint) {
        var resolvedStart = anchorStart
        var resolvedEnd = anchorEnd
        guard
            let liftPoint = pathSketchPoints.last.map(clampedPathPoint),
            let anchorSide = pathSketchAnchorSide
        else {
            return (resolvedStart, resolvedEnd)
        }

        let snappedLift = snappedSketchLiftPoint(
            liftPoint,
            anchorSide: anchorSide,
            start: anchorStart,
            end: anchorEnd,
            emitFeedback: emitSnapFeedback
        )
        switch anchorSide {
        case .start:
            resolvedEnd = snappedLift
        case .end:
            resolvedStart = snappedLift
        }
        return (resolvedStart, resolvedEnd)
    }

    private func snappedSketchLiftPoint(
        _ point: CGPoint,
        anchorSide: PathSketchAnchorSide,
        start: CGPoint,
        end: CGPoint,
        emitFeedback: Bool
    ) -> CGPoint {
        let target = anchorSide == .start ? end : start
        let snapDistanceSquared = pathSketchEndpointSnapDistance * pathSketchEndpointSnapDistance
        if PathCalculations.squaredDistance(from: point, to: target) <= snapDistanceSquared {
            if emitFeedback {
                UISelectionFeedbackGenerator().selectionChanged()
            }
            return target
        }
        return point
    }

    @discardableResult
    private func finishPathSketch() -> Bool {
        guard
            pathSketchPoints.count >= 2,
            let startFormationID,
            let endFormationID,
            let player
        else { return false }

        // Resolve the anchor athlete: in single-select this is the only selected
        // athlete; in group sketches it's whichever endpoint the long-press
        // landed on (tracked separately so the whole group stays selected).
        let anchorAthleteID = longPressSketchAnchorAthleteID
            ?? (selectedAthleteIDs.count == 1 ? selectedAthleteIDs.first : nil)
        guard
            let anchorAthleteID,
            let anchorStartAthlete = player.startAthletes.first(where: { $0.id == anchorAthleteID }),
            let anchorEndAthlete = player.endAthletes.first(where: { $0.id == anchorAthleteID })
        else { return false }

        let isGroupSketch = selectedAthleteIDs.count > 1 && selectedAthleteIDs.contains(anchorAthleteID)
        let affectedIDs: Set<UUID> = isGroupSketch ? selectedAthleteIDs : [anchorAthleteID]
        let message = affectedIDs.count > 1 ? "Paths saved for \(affectedIDs.count) athletes" : "Path saved"
        let undoSnapshot = makePathEditUndoSnapshot(
            affectedAthleteIDs: affectedIDs,
            message: message
        )

        // The lift point redefines the opposite endpoint's position in the
        // single-athlete sketch flow. In a group sketch we keep every athlete's
        // existing endpoints and only apply the drawn shape — the user asked
        // for a relative path, not a wholesale position rewrite.
        var resolvedStart = anchorStartAthlete.position
        var resolvedEnd = anchorEndAthlete.position
        if !isGroupSketch, let anchorSide = pathSketchAnchorSide {
            let resolved = resolvedSketchEndpoints(
                anchorStart: anchorStartAthlete.position,
                anchorEnd: anchorEndAthlete.position,
                emitSnapFeedback: true
            )
            resolvedStart = resolved.start
            resolvedEnd = resolved.end
            switch anchorSide {
            case .start:
                store.mutateFormation(id: endFormationID) { formation in
                    if let idx = formation.placements.firstIndex(where: { $0.athleteID == anchorAthleteID }) {
                        formation.placements[idx].position = resolvedEnd
                    }
                }
            case .end:
                store.mutateFormation(id: startFormationID) { formation in
                    if let idx = formation.placements.firstIndex(where: { $0.athleteID == anchorAthleteID }) {
                        formation.placements[idx].position = resolvedStart
                    }
                }
            }
        }

        let anchorWaypoints = smoothedWaypoints(
            fromSketch: pathSketchPoints,
            start: resolvedStart,
            end: resolvedEnd
        )

        if isGroupSketch {
            // Translate the anchor's waypoint shape by each athlete's offset from
            // the anchor's start. Everyone walks the same shape; nobody's
            // start/end position changes. Single mutateTransitionSpec call to
            // avoid the multi-mutation iOS 26 List storm noted in memory.
            let anchorStart = anchorStartAthlete.position
            let startsByID: [UUID: CGPoint] = Dictionary(
                uniqueKeysWithValues: player.startAthletes.map { ($0.id, $0.position) }
            )
            let ids = selectedAthleteIDs
            store.mutateTransitionSpec(from: startFormationID, to: endFormationID) { spec in
                for index in spec.athleteTransitions.indices {
                    let athleteID = spec.athleteTransitions[index].athleteID
                    guard ids.contains(athleteID), let athleteStart = startsByID[athleteID] else { continue }
                    let dx = athleteStart.x - anchorStart.x
                    let dy = athleteStart.y - anchorStart.y
                    let translated = anchorWaypoints.map { wp -> PathWaypoint in
                        // Each athlete gets fresh waypoint IDs — sharing IDs
                        // across athletes would collide downstream identity work.
                        // The anchor reuses its original ids for visual continuity.
                        let shifted = CGPoint(x: wp.position.x + dx, y: wp.position.y + dy)
                        let newID = athleteID == anchorAthleteID ? wp.id : UUID()
                        return PathWaypoint(
                            id: newID,
                            position: clampedPathPoint(shifted),
                            isSmooth: wp.isSmooth,
                            holdDuration: wp.holdDuration
                        )
                    }
                    spec.athleteTransitions[index].pathControlPoint = nil
                    spec.athleteTransitions[index].pathWaypoints = translated
                }
            }
        } else {
            store.mutateAthleteTransition(from: startFormationID, to: endFormationID, athleteID: anchorAthleteID) { t in
                t.pathControlPoint = nil
                t.pathWaypoints = anchorWaypoints
            }
        }
        refreshTransitionFromStore()
        recentPathEditSnapshot = undoSnapshot
        return true
    }

    private func makePathEditUndoSnapshot(
        affectedAthleteIDs: Set<UUID>,
        message: String
    ) -> PathEditUndoSnapshot? {
        guard let startFormationID, let endFormationID, let player else { return nil }
        let transitions = Dictionary(
            uniqueKeysWithValues: affectedAthleteIDs.map {
                ($0, player.transitionSpec.athleteTransition(for: $0))
            }
        )
        let startPositions = Dictionary(
            uniqueKeysWithValues: player.startAthletes
                .filter { affectedAthleteIDs.contains($0.id) }
                .map { ($0.id, $0.position) }
        )
        let endPositions = Dictionary(
            uniqueKeysWithValues: player.endAthletes
                .filter { affectedAthleteIDs.contains($0.id) }
                .map { ($0.id, $0.position) }
        )
        return PathEditUndoSnapshot(
            startFormationID: startFormationID,
            endFormationID: endFormationID,
            affectedAthleteIDs: affectedAthleteIDs,
            selectedAthleteIDs: selectedAthleteIDs,
            transitions: transitions,
            startPositions: startPositions,
            endPositions: endPositions,
            message: message
        )
    }

    private func smoothedWaypoints(
        fromSketch sketchPoints: [CGPoint],
        start: CGPoint,
        end: CGPoint
    ) -> [PathWaypoint] {
        var points = sketchPoints.map(clampedPathPoint)
        guard points.count >= 2 else { return [] }

        let forwardDistance = PathCalculations.squaredDistance(from: points[0], to: start)
            + PathCalculations.squaredDistance(from: points[points.count - 1], to: end)
        let reverseDistance = PathCalculations.squaredDistance(from: points[0], to: end)
            + PathCalculations.squaredDistance(from: points[points.count - 1], to: start)
        if reverseDistance < forwardDistance {
            points.reverse()
        }

        let interior = points.filter { point in
            PathCalculations.squaredDistance(from: point, to: start) > 1
                && PathCalculations.squaredDistance(from: point, to: end) > 1
        }
        let fullPath = [start] + interior + [end]
        let simplified = simplifiedSketchPath(fullPath, tolerance: 1.35)
        var waypointPositions = Array(simplified.dropFirst().dropLast())

        if waypointPositions.isEmpty,
           let farthest = farthestSketchPoint(from: fullPath, start: start, end: end)
        {
            waypointPositions = [farthest]
        }

        return downsampledWaypointPositions(waypointPositions, maxCount: 6)
            .map { PathWaypoint(position: clampedPathPoint($0), isSmooth: true) }
    }

    private func simplifiedSketchPath(_ points: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }

        let start = points[0]
        let end = points[points.count - 1]
        var farthestIndex = 0
        var farthestDistance = CGFloat.zero

        for index in 1..<(points.count - 1) {
            let projection = projectedPoint(onSegmentFrom: start, to: end, nearestTo: points[index])
            let distance = PathCalculations.squaredDistance(from: points[index], to: projection)
            if distance > farthestDistance {
                farthestDistance = distance
                farthestIndex = index
            }
        }

        guard farthestDistance > tolerance * tolerance else {
            return [start, end]
        }

        let left = simplifiedSketchPath(Array(points[0...farthestIndex]), tolerance: tolerance)
        let right = simplifiedSketchPath(Array(points[farthestIndex..<(points.count)]), tolerance: tolerance)
        return Array(left.dropLast()) + right
    }

    private func farthestSketchPoint(from points: [CGPoint], start: CGPoint, end: CGPoint) -> CGPoint? {
        points.dropFirst().dropLast().max { lhs, rhs in
            let lhsProjection = projectedPoint(onSegmentFrom: start, to: end, nearestTo: lhs)
            let rhsProjection = projectedPoint(onSegmentFrom: start, to: end, nearestTo: rhs)
            return PathCalculations.squaredDistance(from: lhs, to: lhsProjection)
                < PathCalculations.squaredDistance(from: rhs, to: rhsProjection)
        }
    }

    private func downsampledWaypointPositions(_ positions: [CGPoint], maxCount: Int) -> [CGPoint] {
        guard positions.count > maxCount, maxCount > 1 else { return positions }

        let stride = CGFloat(positions.count - 1) / CGFloat(maxCount - 1)
        var sampled: [CGPoint] = []
        var usedIndices = Set<Int>()

        for index in 0..<maxCount {
            let sourceIndex = min(positions.count - 1, Int((CGFloat(index) * stride).rounded()))
            if usedIndices.insert(sourceIndex).inserted {
                sampled.append(positions[sourceIndex])
            }
        }

        return sampled
    }



}

