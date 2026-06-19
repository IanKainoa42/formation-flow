import Combine
import SwiftUI
import UIKit

enum SwapFormationTarget: String, CaseIterable {
    case start = "Start"
    case end = "End"
}

/// How many transition paths the editor draws at once. Persisted as a user
/// preference so coaches can dial down clutter. Default is `.selectedOnly` —
/// only the selected athlete's path shows, everything else recedes.
enum PathDisplayScope: String, CaseIterable, Identifiable {
    case off
    case selectedOnly
    case currentFormation
    case allFormations

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "Hidden"
        case .selectedOnly: return "Selected Athlete"
        case .currentFormation: return "This Formation"
        case .allFormations: return "All Formations"
        }
    }

    var systemImage: String {
        switch self {
        case .off: return "eye.slash"
        case .selectedOnly: return "scope"
        case .currentFormation: return "point.topleft.down.curvedto.point.bottomright.up"
        case .allFormations: return "square.stack.3d.up.fill"
        }
    }
}

private struct FormationMoveUndoSnapshot: Equatable {
    let formationID: UUID
    let positions: [UUID: CGPoint]
}

private struct PathHandleHit {
    let athleteID: UUID
    let waypointID: UUID?
    let position: CGPoint
}

// MARK: - Floor Grid View

struct FloorGridView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
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
    @State private var showingAthleteRenamePrompt = false
    @State private var athleteLabelDraft = ""
    @State private var showingAthleteDeleteConfirmation = false
    @AppStorage("pathDisplayScope") private var pathDisplayScopeRaw = PathDisplayScope.selectedOnly.rawValue
    private var pathDisplayScope: PathDisplayScope {
        PathDisplayScope(rawValue: pathDisplayScopeRaw) ?? .selectedOnly
    }
    // Kept as a computed convenience so the many gesture sites that gate on
    // "are paths visible at all" don't need to learn about scope.
    private var showTransitionPaths: Bool { pathDisplayScope != .off }
    @State private var isDraggingAthletes = false
    @State private var isPanningCanvas = false
    @State private var isDrawingSelectionLasso = false
    @State private var selectionLasso: FloorSelectionLasso? = nil
    @State private var dragStartPositions: [UUID: CGPoint] = [:]
    @State private var draggingAthleteIDs: Set<UUID> = []
    @State private var undoStack: [FormationMoveUndoSnapshot] = []
    @State private var rotationStartPositions: [UUID: CGPoint] = [:]
    @State private var lastRotationDetent: Int = 0
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

    // Transition editing state
    @State private var focusedEndpoint: PreviewEditableEndpoint?
    @State private var isDraggingEndpoint = false
    @State private var isDraggingPathHandle = false
    @State private var pathDragAthleteID: UUID?
    @State private var isSketchingPath = false
    @State private var isLongPressSketching = false
    @State private var draggingWaypointID: UUID?
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
    @State private var shareResultMessage = ""
    @State private var showingShareResult = false

    private var pathCollisionIDs: Set<UUID> {
        player?.cachedPathCollisionIDs ?? []
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

    private var isCompactLayout: Bool {
        horizontalSizeClass == .compact || UIDevice.current.userInterfaceIdiom == .phone
    }

    private var isPhoneLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private var isPhoneLandscape: Bool {
        isPhoneLayout && isHeightConstrained
    }

    private var isHeightConstrained: Bool {
        verticalSizeClass == .compact
    }

    /// Controls go on the side opposite the notch/Dynamic Island.
    private var landscapeControlsTrailing: Bool {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return true }
        switch scene.interfaceOrientation {
        case .landscapeRight:
            // Device rotated clockwise → notch on LEFT → controls on RIGHT
            return true
        case .landscapeLeft:
            // Device rotated counter-clockwise → notch on RIGHT → controls on LEFT
            return false
        default:
            return true
        }
    }

    private var canAddFormation: Bool {
        entitlementManager.isPro || store.routine.formations.count < FreeTierLimits.maxFormations
    }

    /// The transport is "engaged" while playing OR while scrubbed/paused away
    /// from the resting start (progress > 0). When engaged we follow
    /// `player.currentAthletes` so the scrubber animates the floor and pause
    /// freezes athletes in place. When at rest we lock to the formation's
    /// endpoint so the editor shows a crisp static formation (and progress
    /// stays 0, so the idle-reset never fires under the editor).
    private var isTransportEngaged: Bool {
        guard let player else { return false }
        return player.isPlaying || player.progress > 0
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
            return "Selection"
        }
        if selectedAthleteID != nil {
            return "Athlete"
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
            return ("Tap an athlete to edit it. Drag on empty space to lasso-select.", .accentColor)
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
        .sheet(isPresented: $showingNotesSheet) {
            notesSheet
        }
        .sheet(isPresented: $showingInspectorSheet) {
            compactInspectorSheet
        }
        .sheet(isPresented: $showingTransportSheet) {
            compactTransportSheet
        }
        .sheet(isPresented: $showingUpgradeSheet) {
            ProUpgradeSheet()
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    phoneToolbarMenu
                }
            }
        }
        .overlay {
            if isPhoneLandscape {
                VStack {
                    Spacer()
                    HStack {
                        if landscapeControlsTrailing { Spacer() }
                        landscapeControlStrip
                        if !landscapeControlsTrailing { Spacer() }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
    }

    private var editorBody: some View {
        Group {
            if isPhoneLayout {
                if renderedAthletes.isEmpty {
                    emptyState
                } else {
                    canvasArea
                }
            } else {
                VStack(spacing: 0) {
                    controlStrip
                    Divider()

                    if renderedAthletes.isEmpty {
                        emptyState
                    } else {
                        canvasArea
                    }
                }
            }
        }
    }

    private var controlStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
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
                    Menu {
                        Picker("Paths", selection: Binding(
                            get: { pathDisplayScope },
                            set: { pathDisplayScopeRaw = $0.rawValue }
                        )) {
                            ForEach(PathDisplayScope.allCases) { scope in
                                Label(scope.label, systemImage: scope.systemImage).tag(scope)
                            }
                        }
                    } label: {
                        Label("Paths", systemImage: pathDisplayScope.systemImage)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Path display: \(pathDisplayScope.label)")
                    .help("Choose how many transition paths to show")

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
            VStack(spacing: 18) {
                Image(systemName: "figure.stand.line.dotted.figure.stand")
                    .font(.system(size: 52))
                    .foregroundColor(.accentColor)
                Text("Start your first picture")
                    .font(.title2.weight(.semibold))
                Text("Add one athlete, drop in a 10-athlete template, or duplicate after you have a picture to build from.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)

                Group {
                    if isCompactLayout {
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
            .padding(32)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, isCompactLayout ? 20 : 0)
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
            let baseOffsetX = (geometry.size.width - canvasWidth) / 2 + displayPanOffset.width
            let availableLeadingSideSpace = max(0, baseOffsetX)
            let phonePlaybackRailWidth = max(0, availableLeadingSideSpace - 16)
            let phoneUsesPlaybackRail =
                isPhoneLandscape
                && phonePlaybackRailWidth >= 140
                && player != nil
                && startFormationName != nil
                && endFormationName != nil

            // When rail is present, center canvas in the space to the right of the rail
            // instead of the full viewport, eliminating the empty gap on the right side.
            let railRegionWidth: CGFloat = phoneUsesPlaybackRail ? (8 + phonePlaybackRailWidth) : 0
            let adjustedOffsetX = phoneUsesPlaybackRail
                ? railRegionWidth + (geometry.size.width - railRegionWidth - canvasWidth) / 2 + displayPanOffset.width
                : baseOffsetX
            let offset = CGPoint(
                x: adjustedOffsetX,
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
                showPathPulse: hasTransition && showTransitionPaths && !isTransportEngaged,
                transitionCounts: player?.counts ?? 4,
                ghostAthletes: pathDisplayScope == .allFormations ? previousFormationAthletes : [],
                ghostColor: previousFormationColor,
                ghostNextAthletes: pathDisplayScope == .allFormations ? nextFormationAthletes : [],
                ghostNextColor: nextFormationColor,
                ghostPrevPaths: displayedPrevGhostPaths,
                ghostNextPaths: displayedNextGhostPaths,
                pathSketchPoints: pathSketchPoints,
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
                RotationGesture()
                    .onChanged { value in
                        guard selectedAthleteIDs.count >= 2 else { return }
                        if rotationStartPositions.isEmpty {
                            // Capture starting positions for undo + rotation reference
                            rotationStartPositions = renderedAthletes.reduce(into: [UUID: CGPoint]()) { result, athlete in
                                if selectedAthleteIDs.contains(athlete.id) {
                                    if result[athlete.id] == nil { result[athlete.id] = athlete.position }
                                }
                            }
                            lastRotationDetent = 0
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
                            return
                        }
                        let detent = rotationDetent(for: value.radians)
                        // A net rotation of zero is a no-op — don't reset positions or
                        // push a useless undo entry for an incidental two-finger twitch.
                        if detent != 0 {
                            applyRotation(angle: CGFloat(detent) * rotationSnapIncrement)
                            appendUndoSnapshot(positions: rotationStartPositions)
                            refreshTransitionFromStore()
                        }
                        rotationStartPositions = [:]
                        lastRotationDetent = 0
                    }
            )
            #if canImport(UIKit)
            // Two-finger tap = play/pause. Two-finger pan = scrub whenever a
            // transition exists. (Pinch-to-zoom was removed; the two-finger pan
            // is now exclusively a scrub gesture.)
            .background(
                TwoFingerPlaybackGesture(
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
                if isPhoneLayout {
                    // In landscape, keep the floor fully visible — no top overlay.
                    // When the playback rail is showing on the left side, it contains
                    // the Add button and formation context — skip the canvas overlay to
                    // avoid covering the floor.
                    if !phoneUsesPlaybackRail && !isPhoneLandscape {
                        VStack(alignment: .leading, spacing: 8) {
                            phoneTopOverlay

                            formationContextBadge

                            if let compactBannerConfiguration {
                                banner(text: compactBannerConfiguration.text, color: compactBannerConfiguration.color)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                    }
                } else {
                    VStack(spacing: isCompactLayout ? 8 : 10) {
                        if isSwapMode, let athlete = swapSourceRosterAthlete {
                            swapBanner(athleteLabel: athlete.label)
                        } else if isCompactLayout {
                            if let compactBannerConfiguration {
                                banner(text: compactBannerConfiguration.text, color: compactBannerConfiguration.color)
                            }
                        } else if !hasMadeFirstSelection {
                            banner(
                                text: "Tap an athlete to edit it. Drag on empty space to lasso-select.",
                                color: .accentColor
                            )
                        }
                    }
                    .padding(.horizontal, isCompactLayout ? 12 : 0)
                    .padding(.top, isHeightConstrained ? 4 : 8)
                }
            }
            .overlay(alignment: .bottom) {
                if isPhoneLayout {
                    VStack(spacing: 10) {
                        // In landscape the selection overlay moves to the right side.
                        if !isPhoneLandscape, (selectedRosterAthlete != nil || selectedAthleteIDs.count > 1) {
                            phoneSelectionOverlay
                        }

                        if !phoneUsesPlaybackRail,
                            let player,
                            let startFormationName,
                            let endFormationName
                        {
                            CompactTransitionPlaybackOverlayView(
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
                                isLastFormation: isLastFormation
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
            // In phone landscape, skip the selection overlay — screen is too
            // narrow and it overlaps the floor canvas. The user can still tap
            // the athlete or use the inspector sheet for edits.
            .overlay(alignment: .topLeading) {
                if phoneUsesPlaybackRail,
                    let player,
                    let startFormationName,
                    let endFormationName
                {
                    CompactTransitionPlaybackRailView(
                        player: player,
                        startFormationName: startFormationName,
                        endFormationName: endFormationName,
                        availableWidth: phonePlaybackRailWidth,
                        onSwap: toggleSwapMode,
                        onPath: { showingInspectorSheet = true },
                        isSwapMode: isSwapMode,
                        canSwap: selectedAthleteID != nil,
                        canEditPath: selectedAthleteID != nil,
                        onAdd: addAthlete,
                        formationLabel: formationContextLabel,
                        formationColor: currentFormationColor,
                        onPreviousFormation: { onCyclePreviousFormation?() },
                        onNextFormation: { onCycleFormation?() },
                        isFirstFormation: isFirstFormation,
                        isLastFormation: isLastFormation
                    )
                    .padding(.leading, 8)
                    .padding(.top, 12)
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
                .overlay(alignment: .bottomLeading) {
                    if !isPhoneLayout && !hideFormationContextBadge {
                        formationContextBadge
                            .padding(.init(top: 0, leading: 12, bottom: 12, trailing: 0))
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if zoomScale != 1.0 || canvasPanOffset != .zero {
                        Button(action: resetView) {
                            Label("Reset View", systemImage: "arrow.counterclockwise")
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        }
                        .foregroundColor(.primary)
                        .background(.ultraThinMaterial, in: Capsule())
                        .accessibilityLabel("Reset View")
                        .padding(.trailing, 12)
                        .padding(.bottom, isPhoneLayout && !isPhoneLandscape ? 92 : 12)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    resetViewFloatingButton
                        .padding(.trailing, 12)
                        .padding(.bottom, isPhoneLayout ? (isPhoneLandscape ? 12 : 80) : 12)
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

    private var compactInspectorSheet: some View {
        NavigationStack {
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
                onRefreshTransition: { refreshTransitionFromStore() }
            )
            .navigationTitle(compactInspectorTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingInspectorSheet = false
                    }
                }
            }
        }
        .presentationDetents(isPhoneLayout ? [.large] : [.medium, .large])
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
                    isLastFormation: isLastFormation
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

    @ViewBuilder
    private var phoneToolbarMenuContent: some View {
        if canShareTransition {
            Button(action: shareTransitionPreview) {
                Label("Share Preview", systemImage: "square.and.arrow.up")
            }
        }

        Button(action: { showingRosterSheet = true }) {
            Label("Roster", systemImage: "list.bullet.rectangle")
        }

        Button(action: { showingNotesSheet = true }) {
            Label("Notes", systemImage: "note.text")
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

        let idx = formationIndex ?? 0
        Button(action: { store.moveFormationEarlier(id: formationID) }) {
            Label("Move Earlier", systemImage: "arrow.up")
        }
        .disabled(idx == 0)
        .help(idx == 0 ? "Already at the first formation" : "Move formation earlier")

        Button(action: { store.moveFormationLater(id: formationID) }) {
            Label("Move Later", systemImage: "arrow.down")
        }
        .disabled(idx >= store.routine.formations.count - 1)
        .help(idx >= store.routine.formations.count - 1 ? "Already at the last formation" : "Move formation later")

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

        Button(action: undoLastMove) {
            Label("Undo Move", systemImage: "arrow.uturn.backward")
        }
        .disabled(undoStack.isEmpty)
        .help(undoStack.isEmpty ? "Nothing to undo" : "Undo the last move")

        Divider()

        Button(role: .destructive, action: { onDeleteFormation?() }) {
            Label("Delete Formation", systemImage: "trash")
        }

        Button(role: .destructive, action: { onResetRoutine?() }) {
            Label("Reset Routine", systemImage: "arrow.counterclockwise")
        }
    }

    private var phoneToolbarMenu: some View {
        Menu {
            phoneToolbarMenuContent
        } label: {
            Image(systemName: "ellipsis.circle")
                .overlay(alignment: .topTrailing) {
                    if formation?.notes.isEmpty == false {
                        Circle()
                            .fill(.orange)
                            .frame(width: 7, height: 7)
                            .offset(x: 3, y: -3)
                    }
                }
        }
        .accessibilityLabel("Editing tools")
        .accessibilityValue(formation?.notes.isEmpty == false ? "Has notes" : "")
    }

    private var landscapeControlStrip: some View {
        HStack(spacing: 2) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.bold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Back to formations")
            }

            Menu {
                phoneToolbarMenuContent
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption.weight(.bold))
                    .frame(width: 44, height: 44)
                    .overlay(alignment: .topTrailing) {
                        if formation?.notes.isEmpty == false {
                            Circle()
                                .fill(.orange)
                                .frame(width: 6, height: 6)
                                .offset(x: 2, y: 2)
                        }
                    }
            }
            .accessibilityLabel("Editing tools")
        }
        .foregroundColor(.white)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var phoneTopOverlay: some View {
        HStack {
            Button(action: addAthlete) {
                Label("Add", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .controlSize(.small)
    }

    private var phoneOverflowMenu: some View {
        Menu {
            if canShareTransition {
                Button(action: shareTransitionPreview) {
                    Label("Share Preview", systemImage: "square.and.arrow.up")
                }
            }

            Button(action: { showingRosterSheet = true }) {
                Label("Roster", systemImage: "list.bullet.rectangle")
            }

            Button(action: { showingNotesSheet = true }) {
                Label("Notes", systemImage: "note.text")
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
            Image(systemName: "ellipsis.circle.fill")
                .frame(minWidth: 44, minHeight: 44)
                .overlay(alignment: .topTrailing) {
                    if formation?.notes.isEmpty == false {
                        Circle()
                            .fill(.orange)
                            .frame(width: 7, height: 7)
                            .offset(x: 3, y: -3)
                    }
                }
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("More actions")
        .accessibilityHint("Open menu for additional formation actions")
        .help("More actions")
        .accessibilityValue(formation?.notes.isEmpty == false ? "Has notes" : "")
    }

    @ViewBuilder
    private var phoneSelectionOverlay: some View {
        if let selectedRosterAthlete, let selectedPlacement {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedRosterAthlete.label)
                        .font(.headline)
                    Text(
                        "\(selectedRosterAthlete.role.displayName) - x \(String(format: "%.1f", selectedPlacement.position.x))  y \(String(format: "%.1f", selectedPlacement.position.y))"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 0)

                if hasTransition {
                    Button("Path") {
                        showingInspectorSheet = true
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                }

                Menu {
                    Button {
                        beginAthleteRename()
                    } label: {
                        Label(
                            entitlementManager.isPro ? "Rename" : "Rename (Pro)",
                            systemImage: entitlementManager.isPro ? "pencil" : "lock.fill"
                        )
                    }

                    Menu(entitlementManager.isPro ? "Role" : "Role (Pro)") {
                        ForEach(AthleteRole.allCases, id: \.self) { role in
                            Button {
                                guard entitlementManager.isPro else {
                                    showingUpgradeSheet = true
                                    return
                                }
                                store.mutateRosterAthlete(id: selectedRosterAthlete.id) { athlete in
                                    athlete.role = role
                                }
                            } label: {
                                if selectedRosterAthlete.role == role {
                                    Label(role.displayName, systemImage: "checkmark")
                                } else {
                                    Text(role.displayName)
                                }
                            }
                        }
                    }

                    if hasTransition {
                        Button {
                            showingInspectorSheet = true
                        } label: {
                            Label("Path & Timing", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                        }
                    }

                    Button {
                        selectedAthleteIDs = []
                    } label: {
                        Label("Clear Selection", systemImage: "xmark.circle")
                    }

                    Button(role: .destructive) {
                        deleteSelectedAthlete()
                    } label: {
                        Label("Delete Athlete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("More actions")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.08))
            }
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        } else if selectedAthleteIDs.count > 1 {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(selectedAthleteIDs.count) athletes selected")
                        .font(.headline)
                    Text("Drag them together on the floor. Use swap for one athlete at a time.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                if hasTransition {
                    Button(selectionIsTransitionGroup ? "Ungroup" : "Create Stunt Group") {
                        if selectionIsTransitionGroup {
                            ungroupSelectedTransitionGroup()
                        } else {
                            createSelectedTransitionGroup()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!selectionIsTransitionGroup && !canCreateSelectedTransitionGroup)
                    .frame(minHeight: 44)
                }

                Button("Clear") {
                    selectedAthleteIDs = []
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.08))
            }
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        }
    }

    private var rosterSheet: some View {
        NavigationStack {
            Group {
                if store.routine.roster.isEmpty {
                    ContentUnavailableView {
                        Label("No Athletes", systemImage: "person.3")
                    } description: {
                        Text("Add athletes to your roster to start building formations.")
                    } actions: {
                        Button {
                            showingRosterSheet = false
                            addAthlete()
                        } label: {
                            Text("Add Athlete")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(store.routine.roster) { athlete in
                            HStack(spacing: 12) {
                                AthleteRoleMarkerShape(role: athlete.role)
                                    .fill(.primary)
                                    .frame(width: 14, height: 14)
                                    .frame(width: 26, height: 26)
                                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(athlete.label)
                                    Text(athlete.role.displayName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    requestRosterAthleteDeletion([athlete.id])
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .onDelete { offsets in
                            let athletes = store.routine.roster
                            requestRosterAthleteDeletion(
                                offsets.compactMap { athletes.indices.contains($0) ? athletes[$0].id : nil }
                            )
                        }
                        .onMove { from, to in
                            store.moveRoster(fromOffsets: from, toOffset: to)
                        }
                    }
                }
            }
            .navigationTitle("Manage Roster")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showingRosterSheet = false }
                }
            }
        }
    }

    private var notesSheet: some View {
        NavigationStack {
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
            .padding()
            .navigationTitle("Formation Notes")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showingNotesSheet = false }
                }
            }
        }
    }

    private func banner(text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle.fill")
                .font(.caption2)
            Text(text)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
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
            banner(text: "Tap another athlete to swap with \(athleteLabel).", color: .blue)

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

    private func finishPathSketch() {
        guard
            pathSketchPoints.count >= 2,
            let startFormationID,
            let endFormationID,
            let player
        else { return }

        // Resolve the anchor athlete: in single-select this is the only selected
        // athlete; in group sketches it's whichever endpoint the long-press
        // landed on (tracked separately so the whole group stays selected).
        let anchorAthleteID = longPressSketchAnchorAthleteID
            ?? (selectedAthleteIDs.count == 1 ? selectedAthleteIDs.first : nil)
        guard
            let anchorAthleteID,
            let anchorStartAthlete = player.startAthletes.first(where: { $0.id == anchorAthleteID }),
            let anchorEndAthlete = player.endAthletes.first(where: { $0.id == anchorAthleteID })
        else { return }

        let isGroupSketch = selectedAthleteIDs.count > 1 && selectedAthleteIDs.contains(anchorAthleteID)

        // The lift point redefines the opposite endpoint's position in the
        // single-athlete sketch flow. In a group sketch we keep every athlete's
        // existing endpoints and only apply the drawn shape — the user asked
        // for a relative path, not a wholesale position rewrite.
        var resolvedStart = anchorStartAthlete.position
        var resolvedEnd = anchorEndAthlete.position
        if !isGroupSketch,
           let liftPoint = pathSketchPoints.last.map(clampedPathPoint),
           let anchorSide = pathSketchAnchorSide {
            switch anchorSide {
            case .start:
                resolvedEnd = liftPoint
                store.mutateFormation(id: endFormationID) { formation in
                    if let idx = formation.placements.firstIndex(where: { $0.athleteID == anchorAthleteID }) {
                        formation.placements[idx].position = liftPoint
                    }
                }
            case .end:
                resolvedStart = liftPoint
                store.mutateFormation(id: startFormationID) { formation in
                    if let idx = formation.placements.firstIndex(where: { $0.athleteID == anchorAthleteID }) {
                        formation.placements[idx].position = liftPoint
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
                defer {
                    isDraggingAthletes = false
                    isDraggingEndpoint = false
                    isDraggingPathHandle = false
                    isSketchingPath = false
                    isPanningCanvas = false
                    draggingWaypointID = nil
                    pathDragAthleteID = nil
                    pathSketchPoints = []
                    isDrawingSelectionLasso = false
                    selectionLasso = nil
                    dragStartPositions = [:]
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
                    refreshTransitionFromStore()
                    return
                }

                if isSketchingPath {
                    if let athleteID = bootstrapAthleteID {
                        if commitBootstrapSketch(athleteID: athleteID) {
                            return
                        }
                        // Held-tap with no meaningful path — keep this athlete
                        // selected and let the rest of onEnded run normally.
                        selectedAthleteIDs = selectionForAthlete(athleteID)
                        return
                    }
                    finishPathSketch()
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
        pathDragAthleteID = hit.athleteID
        draggingWaypointID = hit.waypointID
        isDraggingPathHandle = true
        focusedEndpoint = displayedFormationEndpoint

        if hit.waypointID == nil {
            draggingWaypointID = materializePathWaypointForDrag(
                anchorAthleteID: hit.athleteID,
                at: scaledPoint
            )
        }

        focusedPathHandle = scaledPoint
        handlePathDragContinued(scaledPoint: scaledPoint)
    }

    private func materializePathWaypointForDrag(anchorAthleteID: UUID, at point: CGPoint) -> UUID? {
        guard let startFormationID, let endFormationID, let player else { return nil }

        let waypointID = TransitionPathSelectionEditing.addWaypoint(
            store: store,
            player: player,
            startFormationID: startFormationID,
            endFormationID: endFormationID,
            selectedAthleteIDs: selectedAthleteIDs,
            anchorAthleteID: anchorAthleteID,
            point: clampedPathPoint(point),
            segmentIndex: 0
        )
        refreshTransitionFromStore()
        return waypointID
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
        guard let anchorAthleteID, let player, let startFormationID, let endFormationID else { return }
        clearActiveGuides()
        let transition = player.transitionSpec.athleteTransition(for: anchorAthleteID)
        let pathPoint = clampedPathPoint(scaledPoint)

        if !transition.pathWaypoints.isEmpty {
            if let draggingWaypointID,
               transition.pathWaypoints.contains(where: { $0.id == draggingWaypointID })
            {
                _ = TransitionPathSelectionEditing.moveWaypoint(
                    store: store,
                    player: player,
                    startFormationID: startFormationID,
                    endFormationID: endFormationID,
                    selectedAthleteIDs: selectedAthleteIDs,
                    anchorAthleteID: anchorAthleteID,
                    waypointID: draggingWaypointID,
                    point: pathPoint
                )
                refreshTransitionFromStore()
            }
        } else {
            // Legacy control point drag
            let startAthlete = player.startAthletes.first(where: { $0.id == anchorAthleteID })
            let endAthlete = player.endAthletes.first(where: { $0.id == anchorAthleteID })
            if let startAthlete, let endAthlete {
                let newControlPoint = CGPoint(
                    x: 2 * pathPoint.x - 0.5 * startAthlete.position.x - 0.5 * endAthlete.position.x,
                    y: 2 * pathPoint.y - 0.5 * startAthlete.position.y - 0.5 * endAthlete.position.y
                )
                store.mutateAthleteTransition(
                    from: startFormationID,
                    to: endFormationID,
                    athleteID: anchorAthleteID
                ) { t in
                    t.pathControlPoint = newControlPoint
                    t.pathWaypoints = []
                }
                refreshTransitionFromStore()
            }
        }
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
        activeAlignmentGuides = snapResult.alignmentGuides
        activeMirrorGuides = snapResult.mirrorGuides

        let nextPosition = CGPoint(
            x: clampedCoordinate(endpointDragStartPosition.x + snapResult.translation.x, upperBound: CourtConstants.width),
            y: clampedCoordinate(endpointDragStartPosition.y + snapResult.translation.y, upperBound: CourtConstants.height)
        )

        store.mutateFormation(id: editableFormationID) { formation in
            guard let placementIndex = formation.placementIndex(for: selectedAthleteID) else { return }
            formation.placements[placementIndex].position = nextPosition
        }
        refreshTransitionFromStore()
    }

    private func handleFormationDragContinued(_ value: DragGesture.Value, cellSize: CGFloat) {
        let rawTranslation = CGPoint(
            x: value.translation.width / cellSize,
            y: value.translation.height / cellSize
        )
        let snapResult = snappingResult(for: rawTranslation)
        activeAlignmentGuides = snapResult.alignmentGuides
        activeMirrorGuides = snapResult.mirrorGuides

        // Resolve which formation we're actually editing. In transition preview
        // the visible athletes come from player.startAthletes / player.endAthletes
        // (chosen by focusedEndpoint), which may differ from formationID — the
        // viewed formation can be either endpoint of the previewed pair.
        let editableID = displayedEditableFormationID

        store.mutateFormation(id: editableID) { formation in
            for athleteID in selectedAthleteIDs {
                guard
                    let startPosition = dragStartPositions[athleteID],
                    let placementIndex = formation.placementIndex(for: athleteID)
                else { continue }

                let nextPosition = CGPoint(
                    x: clampedCoordinate(startPosition.x + snapResult.translation.x, upperBound: CourtConstants.width),
                    y: clampedCoordinate(startPosition.y + snapResult.translation.y, upperBound: CourtConstants.height)
                )
                formation.placements[placementIndex].position = nextPosition
            }
        }
        refreshTransitionFromStore()
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
        guard !isSwapMode,
              showTransitionPaths, hasTransition,
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

    /// When no successor formation exists, hit-tests the current formation's
    /// athletes so a long-press can bootstrap a new formation + path to it.
    private func bootstrapAthleteHit(
        at scaledPoint: CGPoint,
        cellSize: CGFloat
    ) -> (athleteID: UUID, anchor: CGPoint)? {
        guard !isSwapMode,
              onBootstrapFromAthlete != nil,
              !hasTransition,
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
        guard !isDraggingAthletes,
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

    // MARK: - Transition Actions

    private func clearPath() {
        guard let selectedAthleteID, let startFormationID, let endFormationID else { return }
        store.mutateAthleteTransition(from: startFormationID, to: endFormationID, athleteID: selectedAthleteID) { t in
            t.pathControlPoint = nil
            t.pathWaypoints = []
        }
        refreshTransitionFromStore()
    }

    private func ensureCurve() {
        guard let selectedAthleteID, let startFormationID, let endFormationID, let player else { return }
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
        endpointDragStartPosition = nil
    }

    private func refreshTransitionFromStore() {
        guard let player, let startFormationID, let endFormationID else { return }
        player.refresh(
            startAthletes: store.renderedAthletes(for: startFormationID),
            endAthletes: store.renderedAthletes(for: endFormationID),
            transitionSpec: store.transitionSpec(for: startFormationID, to: endFormationID)
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
        max(0, min(upperBound, round(value)))
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

    private func performResetSelectedPath() {
        resetPathForSelectedAthlete()
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
            let anchorAthleteID = explicitAnchorAthleteID ?? anchorAthleteID(for: selectedAthleteIDs, in: player),
            let startAthlete = player.startAthletes.first(where: { $0.id == anchorAthleteID }),
            let endAthlete = player.endAthletes.first(where: { $0.id == anchorAthleteID })
        else { return nil }

        let transition = player.transitionSpec.athleteTransition(for: anchorAthleteID)
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
            var didInsert = false
            store.mutateTransitionSpec(from: startFormationID, to: endFormationID) { spec in
                guard let anchorIndex = spec.athleteTransitions.firstIndex(where: { $0.athleteID == anchorAthleteID }) else {
                    return
                }
                var anchorWaypoints = spec.athleteTransitions[anchorIndex].pathWaypoints
                let insertionIndex = max(0, min(placement.index, anchorWaypoints.count))
                anchorWaypoints.insert(waypoint, at: insertionIndex)
                didInsert = spec.applyRelativePathWaypoints(
                    anchorAthleteID: anchorAthleteID,
                    memberIDs: memberIDs,
                    anchorWaypoints: anchorWaypoints,
                    startPositionsByAthleteID: startsByID
                )
            }
            return didInsert ? waypoint.id : nil
        }

        store.mutateAthleteTransition(
            from: startFormationID,
            to: endFormationID,
            athleteID: anchorAthleteID
        ) { transition in
            let insertionIndex = max(0, min(placement.index, transition.pathWaypoints.count))
            transition.pathControlPoint = nil
            transition.pathWaypoints.insert(waypoint, at: insertionIndex)
        }
        return waypoint.id
    }

    @discardableResult
    static func moveWaypoint(
        store: RoutineStore,
        player: TransitionPlayer,
        startFormationID: UUID,
        endFormationID: UUID,
        selectedAthleteIDs: Set<UUID>,
        anchorAthleteID: UUID,
        waypointID: UUID,
        point: CGPoint
    ) -> Bool {
        let pathPoint = clampedPathPoint(point)
        if selectedAthleteIDs.count > 1, selectedAthleteIDs.contains(anchorAthleteID) {
            let startsByID = Dictionary(uniqueKeysWithValues: player.startAthletes.map { ($0.id, $0.position) })
            let memberIDs = selectedAthleteIDs
            var didMove = false
            store.mutateTransitionSpec(from: startFormationID, to: endFormationID) { spec in
                guard
                    let anchorIndex = spec.athleteTransitions.firstIndex(where: { $0.athleteID == anchorAthleteID }),
                    let waypointIndex = spec.athleteTransitions[anchorIndex].pathWaypoints.firstIndex(where: { $0.id == waypointID })
                else { return }

                var anchorWaypoints = spec.athleteTransitions[anchorIndex].pathWaypoints
                anchorWaypoints[waypointIndex].position = pathPoint
                didMove = spec.applyRelativePathWaypoints(
                    anchorAthleteID: anchorAthleteID,
                    memberIDs: memberIDs,
                    anchorWaypoints: anchorWaypoints,
                    startPositionsByAthleteID: startsByID
                )
            }
            return didMove
        }

        var didMove = false
        store.mutateAthleteTransition(
            from: startFormationID,
            to: endFormationID,
            athleteID: anchorAthleteID
        ) { transition in
            guard let waypointIndex = transition.pathWaypoints.firstIndex(where: { $0.id == waypointID }) else { return }
            transition.pathWaypoints[waypointIndex].position = pathPoint
            didMove = true
        }
        return didMove
    }

    private static func clampedPathPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: max(0, min(CourtConstants.width, point.x)),
            y: max(0, min(CourtConstants.height, point.y))
        )
    }
}

private enum PathSketchAnchorSide {
    case start
    case end
}

private struct FormationBadgeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .brightness(configuration.isPressed ? 0.12 : 0)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.10 : 0))
                    .allowsHitTesting(false)
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct SnapResult {
    let translation: CGPoint
    let alignmentGuides: [AlignmentGuideRenderItem]
    let mirrorGuides: [FormationMirrorGuideRenderItem]
}

private struct FormationMirrorSnapResult {
    let translation: CGPoint
    let guides: [FormationMirrorGuideRenderItem]
}

private enum FormationMirrorSnapEngine {
    static func snap(
        translation: CGPoint,
        startingPositions: [CGPoint],
        otherAthletePositions: [CGPoint],
        threshold: CGFloat = 0.8
    ) -> FormationMirrorSnapResult {
        guard !startingPositions.isEmpty, !otherAthletePositions.isEmpty else {
            return FormationMirrorSnapResult(translation: translation, guides: [])
        }

        let movingPositions = startingPositions.map {
            CGPoint(x: $0.x + translation.x, y: $0.y + translation.y)
        }

        guard let match = bestMirrorMatch(
            movingPositions: movingPositions,
            otherAthletePositions: otherAthletePositions,
            threshold: threshold
        ) else {
            return FormationMirrorSnapResult(translation: translation, guides: [])
        }

        let adjustedTranslation = CGPoint(
            x: translation.x + match.delta.x,
            y: translation.y + match.delta.y
        )
        let adjustedMovingPositions = startingPositions.map {
            CGPoint(x: $0.x + adjustedTranslation.x, y: $0.y + adjustedTranslation.y)
        }

        return FormationMirrorSnapResult(
            translation: adjustedTranslation,
            guides: mirrorGuides(
                movingPositions: adjustedMovingPositions,
                otherAthletePositions: otherAthletePositions
            )
        )
    }

    private static func bestMirrorMatch(
        movingPositions: [CGPoint],
        otherAthletePositions: [CGPoint],
        threshold: CGFloat
    ) -> MirrorMatch? {
        let mirrorAxisX = CourtConstants.width / 2
        let thresholdSquared = threshold * threshold
        var bestMatch: MirrorMatch?

        for movingPosition in movingPositions {
            for sourcePosition in otherAthletePositions {
                guard abs(sourcePosition.x - mirrorAxisX) > 0.25 else { continue }

                let targetPosition = mirroredPosition(for: sourcePosition)
                let delta = CGPoint(
                    x: targetPosition.x - movingPosition.x,
                    y: targetPosition.y - movingPosition.y
                )
                guard abs(delta.x) <= threshold, abs(delta.y) <= threshold else { continue }

                let distanceSquared = delta.x * delta.x + delta.y * delta.y
                guard distanceSquared <= thresholdSquared else { continue }

                let candidate = MirrorMatch(delta: delta, distanceSquared: distanceSquared)
                if bestMatch == nil || candidate.distanceSquared < bestMatch!.distanceSquared {
                    bestMatch = candidate
                }
            }
        }

        return bestMatch
    }

    private static func mirrorGuides(
        movingPositions: [CGPoint],
        otherAthletePositions: [CGPoint],
        threshold: CGFloat = 0.35
    ) -> [FormationMirrorGuideRenderItem] {
        let mirrorAxisX = CourtConstants.width / 2
        let thresholdSquared = threshold * threshold
        var guides: [FormationMirrorGuideRenderItem] = []
        var seenGuides = Set<FormationMirrorGuideRenderItem>()

        for movingPosition in movingPositions {
            for sourcePosition in otherAthletePositions {
                guard abs(sourcePosition.x - mirrorAxisX) > 0.25 else { continue }

                let targetPosition = mirroredPosition(for: sourcePosition)
                let dx = targetPosition.x - movingPosition.x
                let dy = targetPosition.y - movingPosition.y
                guard dx * dx + dy * dy <= thresholdSquared else { continue }

                let guide = FormationMirrorGuideRenderItem(
                    sourcePosition: sourcePosition,
                    mirroredPosition: targetPosition
                )
                if seenGuides.insert(guide).inserted {
                    guides.append(guide)
                    if guides.count >= 4 { return guides }
                }
            }
        }

        return guides
    }

    private static func mirroredPosition(for sourcePosition: CGPoint) -> CGPoint {
        CGPoint(
            x: CourtConstants.width - sourcePosition.x,
            y: sourcePosition.y
        )
    }

    private struct MirrorMatch {
        let delta: CGPoint
        let distanceSquared: CGFloat
    }
}

// MARK: - Previews

#Preview {
    struct PreviewWrapper: View {
        @StateObject private var store = RoutineStore()
        @StateObject private var entitlementManager = EntitlementManager()
        @State private var selectedAthleteIDs: Set<UUID> = []
        @State private var isSwapMode = false
        @State private var triggerDeleteAthlete = false

        var body: some View {
            NavigationStack {
                FloorGridView(
                    store: store,
                    selectedAthleteIDs: $selectedAthleteIDs,
                    isSwapMode: $isSwapMode,
                    triggerDeleteAthlete: $triggerDeleteAthlete,
                    formationID: store.routine.formations.first?.id ?? UUID()
                ) {}
            }
            .environmentObject(entitlementManager)
        }
    }

    return PreviewWrapper()
}
