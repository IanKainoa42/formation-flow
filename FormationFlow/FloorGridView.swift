import LocalAuthentication
import Combine
import SwiftUI
import UIKit

enum SwapFormationTarget: String, CaseIterable {
    case start = "Start"
    case end = "End"
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
    var onDuplicateAsNext: () -> Void
    var onRenameFormation: (() -> Void)?
    var onDeleteFormation: (() -> Void)?
    var onResetRoutine: (() -> Void)?

    // Transition parameters (nil when no adjacent formation)
    var player: TransitionPlayer?
    var startFormationID: UUID?
    var endFormationID: UUID?

    @EnvironmentObject private var entitlementManager: EntitlementManager
    @State private var showingUpgradeSheet = false
    @State private var showingRosterSheet = false
    @State private var showingNotesSheet = false
    @State private var showingInspectorSheet = false
    @State private var showingTransportSheet = false
    @State private var showingAthleteRenamePrompt = false
    @State private var athleteLabelDraft = ""
    @State private var showingAthleteDeleteConfirmation = false
    @State private var showTransitionPaths = true
    @State private var isDraggingAthletes = false
    @State private var isPanningCanvas = false
    @State private var isDrawingSelectionBox = false
    @State private var selectionRect: CGRect? = nil
    @State private var selectionStartPoint: CGPoint = .zero
    @State private var dragStartPositions: [UUID: CGPoint] = [:]
    @State private var undoStack: [[(id: UUID, position: CGPoint)]] = []
    @State private var rotationStartPositions: [UUID: CGPoint] = [:]
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    @State private var canvasPanOffset: CGSize = .zero
    @State private var lastCanvasPanOffset: CGSize = .zero
    @State private var swapSourceAthleteID: UUID?
    @State private var swapFormationTarget: SwapFormationTarget = .start
    @State private var hasMadeFirstSelection = false
    @State private var activeAlignmentGuides: [AlignmentGuideRenderItem] = []
    @State private var rosterDeleteIDs: [UUID] = []
    @State private var collisionCycleIndex: Int = 0
    @State private var pathCollisionCycleIndex: Int = 0

    // Transition editing state
    @State private var focusedEndpoint: PreviewEditableEndpoint?
    @State private var isDraggingEndpoint = false
    @State private var isDraggingPathHandle = false
    @State private var draggingWaypointID: UUID?
    @State private var pendingWaypointDeletionID: UUID?
    @State private var endpointDragStartPosition: CGPoint?
    @State private var showingResetAllPathsConfirmation = false
    @State private var hoveredHandlePosition: CGPoint?
    @State private var hoveredAthleteID: UUID?
    @State private var focusedPathHandle: CGPoint?
    @State private var playerTick: UInt = 0
    @State private var sharePayload: TransitionSharePayload?
    @State private var shareResultMessage = ""
    @State private var showingShareResult = false
    @State private var cachedPathCollisionIDs: Set<UUID> = []

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

    private var canAddFormation: Bool {
        entitlementManager.isPro || store.routine.formations.count < FreeTierLimits.maxFormations
    }

    private var renderedAthletes: [RenderedAthlete] {
        _ = playerTick // force redraw on player updates
        if let player {
            return player.currentAthletes
        }
        return store.renderedAthletes(for: formationID)
    }

    private var collisionSummary: (count: Int, ids: Set<UUID>) {
        // ⚡ Bolt: Avoid O(N^2) spatial math per frame during playback.
        if let player, player.progress > 0 && player.progress < 1 {
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

    private var previousFormationAthletes: [RenderedAthlete] {
        guard let formationIndex, formationIndex > 0 else { return [] }
        let prevFormation = store.routine.formations[formationIndex - 1]
        return store.renderedAthletes(for: prevFormation)
    }

    // MARK: - Transition Computed Properties

    private var hasTransition: Bool {
        player != nil && startFormationID != nil && endFormationID != nil
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

    private func recomputePathCollisionIDs() {
        guard let player else {
            cachedPathCollisionIDs = []
            return
        }
        cachedPathCollisionIDs = PathCalculations.findPathCollisionIDs(paths: transitionPaths, counts: CGFloat(player.counts))
    }

    private var currentFormationEndpoint: PreviewEditableEndpoint? {
        guard hasTransition else { return nil }
        if formationID == startFormationID { return .start }
        if formationID == endFormationID { return .end }
        return nil
    }

    private var editableFormationID: UUID? {
        guard hasTransition, let focusedEndpoint else { return nil }
        return focusedEndpoint == .start ? startFormationID : endFormationID
    }

    private var editableAthletes: [RenderedAthlete] {
        guard let player, let focusedEndpoint else { return [] }
        return focusedEndpoint == .start ? player.startAthletes : player.endAthletes
    }

    private var selectedTransition: AthleteTransition? {
        guard let selectedAthleteID, let player else { return nil }
        return player.transitionSpec.athleteTransition(for: selectedAthleteID)
    }

    private var hasCustomPaths: Bool {
        guard let player else { return false }
        return player.transitionSpec.athleteTransitions.contains {
            $0.pathControlPoint != nil || !$0.pathWaypoints.isEmpty
        }
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
        renderedAthletes.filter { cachedPathCollisionIDs.contains($0.id) }
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
            return ("Tap an athlete to edit it. Drag on empty space to box-select.", .accentColor)
        }

        return nil
    }

    private var dragActivationDistance: CGFloat {
        isCompactLayout ? 10 : 6
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
        .confirmationDialog(
            "Delete athlete?",
            isPresented: $showingAthleteDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Athlete", role: .destructive) {
                deleteSelectedAthlete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the athlete from the roster, every formation, and all transitions. This cannot be undone.")
        }
        .confirmationDialog(
            "Delete waypoint?",
            isPresented: Binding(
                get: { pendingWaypointDeletionID != nil },
                set: { if !$0 { pendingWaypointDeletionID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Waypoint", role: .destructive) {
                deletePendingWaypoint()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the waypoint and its timing hold from the selected athlete's path. This cannot be undone.")
        }
        .onChange(of: formationID) { _, _ in
            // Batch all resets before clearing selection to avoid
            // cascading onChange triggers in the same frame.
            endSwapMode()
            activeAlignmentGuides = []
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
            clearTransitionDragState()
            selectedAthleteIDs = []
            recomputePathCollisionIDs()
        }
        .onAppear {
            recomputePathCollisionIDs()
        }
        .onChange(of: startFormationID) { _, _ in
            recomputePathCollisionIDs()
        }
        .onChange(of: endFormationID) { _, _ in
            recomputePathCollisionIDs()
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
        .onChange(of: selectedAthleteIDs) { _, newSelection in
            pendingWaypointDeletionID = nil
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
        .confirmationDialog(
            "Reset all paths?",
            isPresented: $showingResetAllPathsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset All Paths", role: .destructive) {
                resetAllPaths()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every custom curve and waypoint and returns all athletes to straight-line travel. This cannot be undone.")
        }
        .onReceive(player?.objectWillChange.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()) { _ in
            playerTick &+= 1
        }
        .toolbar {
            if isPhoneLayout {
                ToolbarItem(placement: .navigationBarTrailing) {
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

                        Button(action: { store.moveFormationLater(id: formationID) }) {
                            Label("Move Later", systemImage: "arrow.down")
                        }
                        .disabled(idx >= store.routine.formations.count - 1)

                        Divider()

                        if hasTransition {
                            Button(action: resetSelectedPaths) {
                                Label(selectedAthleteIDs.count == 1 ? "Reset Path" : "Reset Paths", systemImage: "arrow.counterclockwise")
                            }
                        } else {
                            Button(action: resetView) {
                                Label("Reset View", systemImage: "arrow.counterclockwise")
                            }
                        }

                        Button(action: undoLastMove) {
                            Label("Undo Move", systemImage: "arrow.uturn.backward")
                        }
                        .disabled(undoStack.isEmpty)

                        Divider()

                        Button(role: .destructive, action: { onDeleteFormation?() }) {
                            Label("Delete Formation", systemImage: "trash")
                        }

                        Button(role: .destructive, action: { onResetRoutine?() }) {
                            Label("Reset Routine", systemImage: "arrow.counterclockwise")
                        }
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
                    Label(isCompactLayout ? "Add" : "Add Athlete", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
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
                    Button {
                        showTransitionPaths.toggle()
                    } label: {
                        Label(
                            showTransitionPaths ? "Hide Paths" : "Show Paths",
                            systemImage: showTransitionPaths ? "eye.slash" : "eye"
                        )
                    }
                    .buttonStyle(.bordered)
                    .help(showTransitionPaths ? "Hide movement paths between formations" : "Show movement paths between formations")

                    Button(action: shareTransitionPreview) {
                        Label("Share Preview", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Export an animated preview of this transition")
                }

                if isCompactLayout {
                    compactOverflowMenu
                } else {
                    Button(action: { showingRosterSheet = true }) {
                        Label("Manage Roster", systemImage: "list.bullet.rectangle")
                    }
                    .buttonStyle(.bordered)
                    .help("Add, remove, or rename athletes on the team roster")

                    if hasTransition {
                        Button(action: resetSelectedPaths) {
                            Label(selectedAthleteIDs.count == 1 ? "Reset Path" : "Reset Paths", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                        .help(selectedAthleteIDs.count == 1 ? "Reset this athlete's path to straight" : "Reset all athlete paths to straight")
                    } else {
                        Button(action: resetView) {
                            Label("Reset View", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
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
                        Label("Undo Move", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)
                    .disabled(undoStack.isEmpty)
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
            }

            Button(action: undoLastMove) {
                Label("Undo Move", systemImage: "arrow.uturn.backward")
            }
            .disabled(undoStack.isEmpty)
        } label: {
            compactOverflowMenuLabel
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("More actions")
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
                            .help("Copy this formation's positions into a new formation")
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
                            .help("Copy this formation's positions into a new formation")
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
                transitionPaths: showTransitionPaths ? transitionPaths : [],
                endpointMarkers: endpointMarkers,
                alignmentGuides: activeAlignmentGuides,
                collisionIDs: collisionSummary.ids,
                pathCollisionIDs: cachedPathCollisionIDs,
                cellSize: cellSize,
                offset: offset,
                swapSourceID: swapSourceAthleteID,
                selectionRect: selectionRect,
                focusedEndpoint: focusedEndpoint,
                hasTransition: hasTransition,
                startFormationColor: transitionStartColor,
                endFormationColor: transitionEndColor,
                transitionProgress: player?.progress ?? 0,
                formationColor: currentFormationColor,
                ghostAthletes: previousFormationAthletes,
                hoveredHandlePosition: hoveredHandlePosition,
                hoveredAthleteID: hoveredAthleteID,
                focusedPathHandle: focusedPathHandle
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
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        let nextZoomScale = max(0.65, min(3.0, lastZoomScale * value.magnification))
                        let nextCellSize = baseCellSize * nextZoomScale
                        let nextCanvasSize = CGSize(
                            width: CourtConstants.width * nextCellSize,
                            height: CourtConstants.height * nextCellSize
                        )

                        zoomScale = nextZoomScale
                        canvasPanOffset = clampedCanvasPanOffset(
                            canvasPanOffset,
                            viewportSize: geometry.size,
                            canvasSize: nextCanvasSize
                        )
                    }
                    .onEnded { _ in
                        lastZoomScale = zoomScale
                        canvasPanOffset = clampedCanvasPanOffset(
                            canvasPanOffset,
                            viewportSize: geometry.size,
                            canvasSize: CGSize(
                                width: CourtConstants.width * baseCellSize * zoomScale,
                                height: CourtConstants.height * baseCellSize * zoomScale
                            )
                        )
                        lastCanvasPanOffset = canvasPanOffset
                    }
            )
            .simultaneousGesture(
                RotationGesture()
                    .onChanged { value in
                        guard selectedAthleteIDs.count >= 2 else { return }
                        if rotationStartPositions.isEmpty {
                            // Capture starting positions for undo + rotation reference
                            let selected = renderedAthletes.filter { selectedAthleteIDs.contains($0.id) }
                            rotationStartPositions = Dictionary(uniqueKeysWithValues: selected.map { ($0.id, $0.position) })
                        }
                        applyRotation(angle: value.radians)
                    }
                    .onEnded { value in
                        guard selectedAthleteIDs.count >= 2, !rotationStartPositions.isEmpty else {
                            rotationStartPositions = [:]
                            return
                        }
                        // Final snap + push undo
                        applyRotation(angle: value.radians)
                        undoStack.append(rotationStartPositions.map { ($0.key, $0.value) })
                        rotationStartPositions = [:]
                        refreshTransitionFromStore()
                    }
            )

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
                    } else {
                        hoveredHandlePosition = nil
                        hoveredAthleteID = athleteHit(at: scaledPoint, within: renderedAthletes, cellSize: cellSize)?.id
                    }
                case .ended:
                    hoveredHandlePosition = nil
                    hoveredAthleteID = nil
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
                                text: "Tap an athlete to edit it. Drag on empty space to box-select.",
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
                                canEditPath: selectedAthleteID != nil
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
                        formationColor: currentFormationColor
                    )
                    .padding(.leading, 8)
                    .padding(.top, 12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            canvasContent
                .overlay(alignment: .bottomLeading) {
                    if !isPhoneLayout {
                        formationContextBadge
                            .padding(.init(top: 0, leading: 12, bottom: 12, trailing: 0))
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Formation Context Badge

    private var formationContextBadge: some View {
        Button {
            onCycleFormation?()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(currentFormationColor)
                        .frame(width: 8, height: 8)
                    Text(formationContextLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.primary)
                }

                if hasTransition, showTransitionPaths, let startFormationName, let endFormationName {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(transitionStartColor)
                            .frame(width: 6, height: 6)
                        Text(startFormationName)
                            .font(.caption2)
                        Text("\u{2192}")
                            .font(.caption2)
                        Circle()
                            .fill(transitionEndColor)
                            .frame(width: 6, height: 6)
                        Text(endFormationName)
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                }

                if !previousFormationAthletes.isEmpty, let previousFormationName {
                    HStack(spacing: 4) {
                        Circle()
                            .stroke(.white.opacity(0.3), lineWidth: 1)
                            .frame(width: 6, height: 6)
                        Text("Ghost: \(previousFormationName)")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(0.08))
            }
        }
        .buttonStyle(.plain)
    }

    private var compactInspectorSheet: some View {
        NavigationStack {
            SidebarInspectorView(
                store: store,
                formationID: formationID,
                selectedAthleteIDs: $selectedAthleteIDs,
                isCompactLayout: true,
                onDeleteAthlete: { deleteSelectedAthlete() }
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
                    canEditPath: selectedAthleteID != nil
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
            }

            Button(action: undoLastMove) {
                Label("Undo Move", systemImage: "arrow.uturn.backward")
            }
            .disabled(undoStack.isEmpty)
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .frame(width: 30, height: 30)
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
        .accessibilityValue(formation?.notes.isEmpty == false ? "Has notes" : "")
        .controlSize(.small)
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
                    .controlSize(.small)
                }

                Menu {
                    Button {
                        beginAthleteRename()
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }

                    Menu("Role") {
                        ForEach(AthleteRole.allCases, id: \.self) { role in
                            Button {
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
                        showingAthleteDeleteConfirmation = true
                    } label: {
                        Label("Delete Athlete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("More actions")
                .controlSize(.small)
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

                Button("Clear") {
                    selectedAthleteIDs = []
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
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

    // MARK: - Transition Inspector

    private func transitionInspectorSection(
        transition: AthleteTransition,
        player: TransitionPlayer,
        startFormationID: UUID,
        endFormationID: UUID
    ) -> some View {
        VStack(alignment: .leading, spacing: isCompactLayout ? 14 : 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Transition")
                        .font(.headline)
                    Spacer()
                    Button(role: .destructive) {
                        showingResetAllPathsConfirmation = true
                    } label: {
                        Label("Reset All", systemImage: "arrow.uturn.backward.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasCustomPaths)
                }
                if let startFormationName, let endFormationName {
                    Text("\(startFormationName) \u{2192} \(endFormationName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            // Move delay
            VStack(alignment: .leading, spacing: isCompactLayout ? 6 : 8) {
                Text("Start Delay")
                    .font(.subheadline.weight(.semibold))
                if entitlementManager.isPro {
                    Slider(
                        value: Binding(
                            get: { transition.moveDelayCounts },
                            set: { newValue in
                                guard let selectedAthleteID else { return }
                                store.mutateAthleteTransition(
                                    from: startFormationID,
                                    to: endFormationID,
                                    athleteID: selectedAthleteID
                                ) { t in
                                    t.moveDelayCounts = min(CGFloat(player.counts), max(0, newValue))
                                }
                                refreshTransitionFromStore()
                            }
                        ),
                        in: 0...CGFloat(player.counts),
                        step: 0.5
                    )
                    .accessibilityLabel("Start Delay")
                } else {
                    HStack {
                        Slider(value: .constant(0), in: 0...CGFloat(player.counts))
                            .disabled(true)
                        Button {
                            showingUpgradeSheet = true
                        } label: {
                            Image(systemName: "lock.fill")
                                .foregroundColor(.secondary)
                        }
                        .accessibilityLabel("Upgrade to Pro to adjust start delay")
                    }
                }
                Text(TransitionCountFormatting.label(transition.moveDelayCounts))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            // Path controls
            VStack(alignment: .leading, spacing: isCompactLayout ? 8 : 10) {
                Text("Path")
                    .font(.subheadline.weight(.semibold))
                Group {
                    if isCompactLayout {
                        VStack(spacing: 8) {
                            transitionPathButtons
                        }
                    } else {
                        HStack(spacing: 10) {
                            transitionPathButtons
                        }
                    }
                }

                Text("Double-tap the selected athlete to add a waypoint, then drag the handles.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Waypoint list
            if !transition.pathWaypoints.isEmpty {
                VStack(alignment: .leading, spacing: isCompactLayout ? 8 : 10) {
                    Text("Waypoints")
                        .font(.subheadline.weight(.semibold))
                    ForEach(Array(transition.pathWaypoints.enumerated()), id: \.element.id) { waypointIndex, waypoint in
                        waypointCard(
                            waypointIndex: waypointIndex,
                            waypoint: waypoint,
                            player: player,
                            startFormationID: startFormationID,
                            endFormationID: endFormationID
                        )
                    }
                }
            }
        }
        .padding(isCompactLayout ? 16 : 20)
    }

    @ViewBuilder
    private var transitionPathButtons: some View {
        Button(action: clearPath) {
            Label("Straight", systemImage: "line.diagonal")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)

        Button(action: ensureCurve) {
            Label("Curve", systemImage: "scribble")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private func waypointCard(
        waypointIndex: Int,
        waypoint: PathWaypoint,
        player: TransitionPlayer,
        startFormationID: UUID,
        endFormationID: UUID
    ) -> some View {
        VStack(alignment: .leading, spacing: isCompactLayout ? 6 : 8) {
            HStack {
                Text("Waypoint \(waypointIndex + 1)")
                    .font(.body.weight(.medium))
                Spacer()
                Button(role: .destructive) {
                    pendingWaypointDeletionID = waypoint.id
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete waypoint")
            }

            HStack {
                Text(waypoint.isSmooth ? "Smooth" : "Sharp")
                Spacer()
                Button(waypoint.isSmooth ? "Make Sharp" : "Make Smooth") {
                    guard entitlementManager.isPro else {
                        showingUpgradeSheet = true
                        return
                    }
                    guard let selectedAthleteID else { return }
                    store.mutateAthleteTransition(
                        from: startFormationID,
                        to: endFormationID,
                        athleteID: selectedAthleteID
                    ) { t in
                        t.pathWaypoints[waypointIndex].isSmooth.toggle()
                    }
                    refreshTransitionFromStore()
                }
                .buttonStyle(.bordered)
            }

            if isCompactLayout {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Hold")
                        Spacer()
                        Text(TransitionCountFormatting.label(waypoint.holdCounts))
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 8) {
                        Button("- 0.5") {
                            adjustWaypointHold(
                                by: -0.5,
                                waypointIndex: waypointIndex,
                                player: player,
                                startFormationID: startFormationID,
                                endFormationID: endFormationID
                            )
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)

                        Button("+ 0.5") {
                            adjustWaypointHold(
                                by: 0.5,
                                waypointIndex: waypointIndex,
                                player: player,
                                startFormationID: startFormationID,
                                endFormationID: endFormationID
                            )
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }
                }
            } else {
                HStack {
                    Text("Hold")
                    Spacer()
                    Button("- 0.5") {
                        adjustWaypointHold(
                            by: -0.5,
                            waypointIndex: waypointIndex,
                            player: player,
                            startFormationID: startFormationID,
                            endFormationID: endFormationID
                        )
                    }
                    .buttonStyle(.bordered)

                    Text(TransitionCountFormatting.label(waypoint.holdCounts))
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 84)

                    Button("+ 0.5") {
                        adjustWaypointHold(
                            by: 0.5,
                            waypointIndex: waypointIndex,
                            player: player,
                            startFormationID: startFormationID,
                            endFormationID: endFormationID
                        )
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(isCompactLayout ? 12 : 14)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func adjustWaypointHold(
        by delta: CGFloat,
        waypointIndex: Int,
        player: TransitionPlayer,
        startFormationID: UUID,
        endFormationID: UUID
    ) {
        guard entitlementManager.isPro else {
            showingUpgradeSheet = true
            return
        }
        guard let selectedAthleteID else { return }
        store.mutateAthleteTransition(
            from: startFormationID,
            to: endFormationID,
            athleteID: selectedAthleteID
        ) { t in
            let updatedValue = t.pathWaypoints[waypointIndex].holdCounts + delta
            t.pathWaypoints[waypointIndex].holdCounts = min(
                CGFloat(player.counts),
                max(0, updatedValue)
            )
        }
        refreshTransitionFromStore()
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
                        }
                        .onMove { from, to in
                            store.moveRoster(fromOffsets: from, toOffset: to)
                        }
                        .onDelete { offsets in
                            rosterDeleteIDs = offsets.map { store.routine.roster[$0].id }
                        }
                    }
                }
            }
            .confirmationDialog(
                "Delete \(rosterDeleteIDs.count == 1 ? "this athlete" : "these athletes")?",
                isPresented: Binding(
                    get: { !rosterDeleteIDs.isEmpty },
                    set: { if !$0 { rosterDeleteIDs = [] } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    let context = LAContext()
                    var error: NSError?
                    if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
                        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Authentication is required to perform this destructive action.") { success, _ in
                            DispatchQueue.main.async {
                                if success {
                                    for id in self.rosterDeleteIDs {
                                        self.store.deleteAthlete(id: id)
                                    }
                                    self.selectedAthleteIDs.subtract(self.rosterDeleteIDs)
                                    self.rosterDeleteIDs = []
                                }
                            }
                        }
                    } else {
                        for id in rosterDeleteIDs {
                            store.deleteAthlete(id: id)
                        }
                        selectedAthleteIDs.subtract(rosterDeleteIDs)
                        rosterDeleteIDs = []
                    }
                }
                Button("Cancel", role: .cancel) {
                    rosterDeleteIDs = []
                }
            } message: {
                Text("This will remove them from all \(store.routine.formations.count) formations and their transitions. This cannot be undone.")
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
        let rolePadding: CGFloat = athlete.role == .tumbler ? 10 : 6
        let markerRadius = (athlete.role.selectedMarkerRadius + rolePadding) / max(cellSize, 1)
        let radiusBonus: CGFloat = athlete.role == .tumbler ? 1.25 : 0.5
        let radius = max(baseRadius + radiusBonus, markerRadius)
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

    private func cycledAthleteHit(
        at point: CGPoint,
        within athletes: [RenderedAthlete],
        cellSize: CGFloat,
        excluding excludedID: UUID? = nil
    ) -> RenderedAthlete? {
        let candidates = athleteHits(
            at: point,
            within: athletes,
            cellSize: cellSize,
            excluding: excludedID
        )

        guard !candidates.isEmpty else { return nil }
        guard candidates.count > 1, let selectedAthleteID else { return candidates.first }

        guard let selectedIndex = candidates.firstIndex(where: { $0.id == selectedAthleteID }) else {
            return candidates.first
        }

        return candidates[(selectedIndex + 1) % candidates.count]
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

                let hitRadiusSquared = interactionHitRadiusSquared(for: cellSize)
                let dragDistance = hypot(value.translation.width, value.translation.height)
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
                if isDrawingSelectionBox {
                    handleSelectionBoxContinued(value)
                    return
                }

                // Priority 2: Focused path handle gets a large grab area
                if let focusedPathHandle,
                   let selectedAthleteID, let player,
                   showTransitionPaths, hasTransition
                {
                    let focusedHitRadius = hitRadiusSquared * 4
                    if PathCalculations.squaredDistance(from: startScaledPoint, to: focusedPathHandle) < focusedHitRadius {
                        guard dragDistance >= dragActivationDistance else { return }
                        let transition = player.transitionSpec.athleteTransition(for: selectedAthleteID)
                        // Match to a waypoint if possible
                        if let waypoint = transition.pathWaypoints.first(where: {
                            PathCalculations.squaredDistance(from: focusedPathHandle, to: $0.position) < 1.0
                        }) {
                            draggingWaypointID = waypoint.id
                        }
                        isDraggingPathHandle = true
                        focusedEndpoint = currentFormationEndpoint
                        handlePathDragContinued(scaledPoint: scaledPoint)
                        return
                    }
                }

                // Priority 3: Hit-test for new drag initiation
                    if showTransitionPaths, hasTransition {
                        // 3a: Path handles (checked first so they win over athlete dot)
                    if let selectedAthleteID,
                       let startFormationID, let endFormationID,
                       let player
                    {
                        let transition = player.transitionSpec.athleteTransition(for: selectedAthleteID)

                        if !transition.pathWaypoints.isEmpty {
                            // Check waypoint handles
                            for waypoint in transition.pathWaypoints {
                                if PathCalculations.squaredDistance(from: startScaledPoint, to: waypoint.position)
                                    < hitRadiusSquared
                                {
                                    guard dragDistance >= dragActivationDistance else { return }
                                    draggingWaypointID = waypoint.id
                                    isDraggingPathHandle = true
                                    focusedEndpoint = currentFormationEndpoint
                                    handlePathDragContinued(scaledPoint: scaledPoint)
                                    return
                                }
                            }

                            // Check "+" midpoint handles for inserting new waypoints
                            let startAthlete = player.startAthletes.first(where: { $0.id == selectedAthleteID })
                            let endAthlete = player.endAthletes.first(where: { $0.id == selectedAthleteID })
                            if let startAthlete, let endAthlete {
                                let nodes = PathCalculations.waypointNodes(
                                    from: startAthlete.position,
                                    to: endAthlete.position,
                                    waypoints: transition.pathWaypoints
                                )
                                for segmentIndex in 0..<(nodes.count - 1) {
                                    let midpoint = CGPoint(
                                        x: (nodes[segmentIndex].x + nodes[segmentIndex + 1].x) / 2,
                                        y: (nodes[segmentIndex].y + nodes[segmentIndex + 1].y) / 2
                                    )
                                    if PathCalculations.squaredDistance(from: startScaledPoint, to: midpoint)
                                        < hitRadiusSquared
                                    {
                                        guard dragDistance >= dragActivationDistance else { return }
                                        guard entitlementManager.isPro else {
                                            showingUpgradeSheet = true
                                            return
                                        }
                                        let newWaypoint = PathWaypoint(position: midpoint, isSmooth: true)
                                        store.mutateAthleteTransition(
                                            from: startFormationID,
                                            to: endFormationID,
                                            athleteID: selectedAthleteID
                                        ) { t in
                                            let insertIndex = min(segmentIndex, t.pathWaypoints.count)
                                            t.pathWaypoints.insert(newWaypoint, at: insertIndex)
                                            t.pathControlPoint = nil
                                        }
                                        draggingWaypointID = newWaypoint.id
                                        isDraggingPathHandle = true
                                        focusedEndpoint = currentFormationEndpoint
                                        refreshTransitionFromStore()
                                        return
                                    }
                                }
                            }
                        } else {
                            // Legacy control point handle
                            let startAthlete = player.startAthletes.first(where: { $0.id == selectedAthleteID })
                            let endAthlete = player.endAthletes.first(where: { $0.id == selectedAthleteID })
                            if let startAthlete, let endAthlete {
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
                                if PathCalculations.squaredDistance(from: startScaledPoint, to: midpoint)
                                    < hitRadiusSquared
                                {
                                    guard dragDistance >= dragActivationDistance else { return }
                                    isDraggingPathHandle = true
                                    focusedEndpoint = currentFormationEndpoint
                                    handlePathDragContinued(scaledPoint: scaledPoint)
                                    return
                                }
                            }
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
                        if !selectedAthleteIDs.contains(hitAthlete.id) {
                            selectedAthleteIDs = [hitAthlete.id]
                        }
                        focusedEndpoint = currentFormationEndpoint
                        guard dragDistance >= dragActivationDistance else { return }
                        dragStartPositions = Dictionary(
                            uniqueKeysWithValues: renderedAthletes
                                .filter { selectedAthleteIDs.contains($0.id) }
                                .map { ($0.id, $0.position) }
                        )
                        isDraggingAthletes = true
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
                        if !selectedAthleteIDs.contains(hitAthlete.id) {
                            selectedAthleteIDs = [hitAthlete.id]
                        }
                        focusedEndpoint = nil
                        guard dragDistance >= dragActivationDistance else { return }
                        dragStartPositions = Dictionary(
                            uniqueKeysWithValues: renderedAthletes
                                .filter { selectedAthleteIDs.contains($0.id) }
                                .map { ($0.id, $0.position) }
                        )
                        isDraggingAthletes = true
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
                        selectedAthleteIDs = [hitMarker.athleteID]
                        focusedEndpoint = hitMarker.endpoint
                        endpointDragStartPosition = hitMarker.position
                        // Only allow dragging if the marker belongs to the current formation
                        guard hitMarker.endpoint == currentFormationEndpoint else { return }
                        guard dragDistance >= dragActivationDistance else { return }
                        isDraggingEndpoint = true
                        handleEndpointDragContinued(value, cellSize: cellSize, offset: offset)
                        return
                    }
                }

                // 2d: Empty space → pan if zoomed on compact, otherwise selection box
                focusedEndpoint = hasTransition ? currentFormationEndpoint : nil
                guard dragDistance >= dragActivationDistance else { return }

                if canPanCanvas(viewportSize: viewportSize, canvasSize: canvasSize) {
                    isPanningCanvas = true
                    handleCanvasPanContinued(
                        value,
                        viewportSize: viewportSize,
                        canvasSize: canvasSize
                    )
                    return
                }

                selectionStartPoint = value.startLocation
                selectionRect = CGRect(origin: value.startLocation, size: .zero)
                isDrawingSelectionBox = true
                handleSelectionBoxContinued(value)
            }
            .onEnded { value in
                let hitRadiusSquared = interactionHitRadiusSquared(for: cellSize)
                defer {
                    isDraggingAthletes = false
                    isDraggingEndpoint = false
                    isDraggingPathHandle = false
                    isPanningCanvas = false
                    draggingWaypointID = nil
                    isDrawingSelectionBox = false
                    selectionRect = nil
                    dragStartPositions = [:]
                    endpointDragStartPosition = nil
                    activeAlignmentGuides = []
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

                    if hasTransition, let player {
                        swapFormationID = swapFormationTarget == .start ? startFormationID! : endFormationID!
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
                        selectedAthleteIDs = [targetAthlete.id]
                        refreshTransitionFromStore()
                    }
                    endSwapMode()
                    return
                }

                if isDraggingAthletes, !dragStartPositions.isEmpty {
                    undoStack.append(dragStartPositions.map { ($0.key, $0.value) })
                    refreshTransitionFromStore()
                }

                if isDraggingEndpoint {
                    refreshTransitionFromStore()
                }

                if isPanningCanvas {
                    lastCanvasPanOffset = canvasPanOffset
                    return
                }

                if isDrawingSelectionBox, let selectionRect {
                    let newSelection = Set(
                        renderedAthletes.compactMap { athlete in
                            let screenPoint = CGPoint(
                                x: athlete.position.x * cellSize + offset.x,
                                y: athlete.position.y * cellSize + offset.y
                            )
                            return selectionRect.contains(screenPoint) ? athlete.id : nil
                        }
                    )

                    if selectionRect.width < 5 && selectionRect.height < 5 {
                        // Tap on empty space — also try selecting from transition athletes
                        let tapPoint = CGPoint(
                            x: (value.location.x - offset.x) / cellSize,
                            y: (value.location.y - offset.y) / cellSize
                        )
                        if showTransitionPaths, hasTransition, let player {
                            if let athlete = cycledAthleteHit(
                                at: tapPoint,
                                within: player.currentAthletes,
                                cellSize: cellSize
                            ) {
                                selectedAthleteIDs = [athlete.id]
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

                // If an athlete is hovered, tapping selects exactly that athlete
                if let hoveredID = hoveredAthleteID,
                   renderedAthletes.contains(where: { $0.id == hoveredID }) {
                    selectedAthleteIDs = [hoveredID]
                    focusedEndpoint = hasTransition ? currentFormationEndpoint : nil
                    focusedPathHandle = nil
                    return
                }

                if let athlete = cycledAthleteHit(
                    at: tapPoint,
                    within: renderedAthletes,
                    cellSize: cellSize
                ) ?? cycledAthleteHit(
                    at: startScaledPoint,
                    within: renderedAthletes,
                    cellSize: cellSize
                ) {
                    selectedAthleteIDs = [athlete.id]
                    focusedEndpoint = hasTransition ? currentFormationEndpoint : nil
                    focusedPathHandle = nil
                    return
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

                if showTransitionPaths {
                    if let handle = nearestPathHandle(at: tapPoint, cellSize: cellSize)
                        ?? nearestPathHandle(at: startScaledPoint, cellSize: cellSize)
                    {
                        focusedPathHandle = handle
                        return
                    }
                }

                selectedAthleteIDs = []
                focusedEndpoint = hasTransition ? currentFormationEndpoint : nil
                focusedPathHandle = nil
            }
    }

    // MARK: - Drag Helpers

    private func interactionHitRadiusSquared(for cellSize: CGFloat) -> CGFloat {
        let minimumTouchRadius: CGFloat = isCompactLayout ? 22 : 18
        let cellAdjustedRadius = minimumTouchRadius / max(cellSize, 1)
        let defaultRadius = sqrt(CourtConstants.hitRadiusSquared)
        let radius = max(defaultRadius, cellAdjustedRadius)
        return radius * radius
    }


    private func canPanCanvas(viewportSize: CGSize, canvasSize: CGSize) -> Bool {
        guard isCompactLayout else { return false }

        let overflowWidth = canvasSize.width - viewportSize.width
        let overflowHeight = canvasSize.height - viewportSize.height
        return overflowWidth > 1 || overflowHeight > 1
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
        activeAlignmentGuides = []
        canvasPanOffset = clampedCanvasPanOffset(
            CGSize(
                width: lastCanvasPanOffset.width + value.translation.width,
                height: lastCanvasPanOffset.height + value.translation.height
            ),
            viewportSize: viewportSize,
            canvasSize: canvasSize
        )
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

        if !transition.pathWaypoints.isEmpty, let startAthlete, let endAthlete {
            let nodes = PathCalculations.waypointNodes(
                from: startAthlete.position,
                to: endAthlete.position,
                waypoints: transition.pathWaypoints
            )

            for segmentIndex in 0..<(nodes.count - 1) {
                let midpoint = CGPoint(
                    x: (nodes[segmentIndex].x + nodes[segmentIndex + 1].x) / 2,
                    y: (nodes[segmentIndex].y + nodes[segmentIndex + 1].y) / 2
                )

                if PathCalculations.squaredDistance(from: point, to: midpoint) < hitRadiusSquared {
                    return true
                }
            }
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
        guard hasTransition, let selectedAthleteID, let player else { return nil }
        let hitRadiusSquared = interactionHitRadiusSquared(for: cellSize) * 3

        let transition = player.transitionSpec.athleteTransition(for: selectedAthleteID)
        let startAthlete = player.startAthletes.first(where: { $0.id == selectedAthleteID })
        let endAthlete = player.endAthletes.first(where: { $0.id == selectedAthleteID })

        // Check waypoint handles
        for waypoint in transition.pathWaypoints {
            if PathCalculations.squaredDistance(from: point, to: waypoint.position) < hitRadiusSquared {
                return waypoint.position
            }
        }

        // Check midpoint "+" handles
        if !transition.pathWaypoints.isEmpty, let startAthlete, let endAthlete {
            let nodes = PathCalculations.waypointNodes(
                from: startAthlete.position,
                to: endAthlete.position,
                waypoints: transition.pathWaypoints
            )
            for segmentIndex in 0..<(nodes.count - 1) {
                let midpoint = CGPoint(
                    x: (nodes[segmentIndex].x + nodes[segmentIndex + 1].x) / 2,
                    y: (nodes[segmentIndex].y + nodes[segmentIndex + 1].y) / 2
                )
                if PathCalculations.squaredDistance(from: point, to: midpoint) < hitRadiusSquared {
                    return midpoint
                }
            }
        }

        // Legacy control point handle
        guard transition.pathWaypoints.isEmpty, let startAthlete, let endAthlete else { return nil }
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
        if PathCalculations.squaredDistance(from: point, to: midpoint) < hitRadiusSquared {
            return midpoint
        }
        return nil
    }

    private func handlePathDragContinued(scaledPoint: CGPoint) {
        guard let selectedAthleteID, let player, let startFormationID, let endFormationID else { return }
        activeAlignmentGuides = []
        let transition = player.transitionSpec.athleteTransition(for: selectedAthleteID)

        if !transition.pathWaypoints.isEmpty {
            if let draggingWaypointID,
               let waypointIndex = transition.pathWaypoints.firstIndex(where: { $0.id == draggingWaypointID })
            {
                store.mutateAthleteTransition(
                    from: startFormationID,
                    to: endFormationID,
                    athleteID: selectedAthleteID
                ) { t in
                    t.pathWaypoints[waypointIndex].position = scaledPoint
                }
                refreshTransitionFromStore()
            }
        } else {
            // Legacy control point drag
            let startAthlete = player.startAthletes.first(where: { $0.id == selectedAthleteID })
            let endAthlete = player.endAthletes.first(where: { $0.id == selectedAthleteID })
            if let startAthlete, let endAthlete {
                let newControlPoint = CGPoint(
                    x: 2 * scaledPoint.x - 0.5 * startAthlete.position.x - 0.5 * endAthlete.position.x,
                    y: 2 * scaledPoint.y - 0.5 * startAthlete.position.y - 0.5 * endAthlete.position.y
                )
                store.mutateAthleteTransition(
                    from: startFormationID,
                    to: endFormationID,
                    athleteID: selectedAthleteID
                ) { t in
                    t.pathControlPoint = newControlPoint
                    t.pathWaypoints = []
                }
                refreshTransitionFromStore()
            }
        }
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
        let snapResult = AlignmentSnapEngine.snap(
            translation: rawTranslation,
            startingPositions: [endpointDragStartPosition],
            otherAthletePositions: editableAthletes
                .filter { $0.id != selectedAthleteID }
                .map(\.position)
        )
        activeAlignmentGuides = snapResult.guides

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
        activeAlignmentGuides = snapResult.guides

        store.mutateFormation(id: formationID) { formation in
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
    }

    // MARK: - Rotation

    private func applyRotation(angle: CGFloat) {
        guard !rotationStartPositions.isEmpty else { return }

        // Compute center of mass of the selected group
        let positions = Array(rotationStartPositions.values)
        let centerX = positions.map(\.x).reduce(0, +) / CGFloat(positions.count)
        let centerY = positions.map(\.y).reduce(0, +) / CGFloat(positions.count)
        let center = CGPoint(x: centerX, y: centerY)

        let cosA = cos(angle)
        let sinA = sin(angle)

        store.mutateFormation(id: formationID) { formation in
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

    private func handleSelectionBoxContinued(_ value: DragGesture.Value) {
        activeAlignmentGuides = []
        selectionRect = CGRect(
            x: min(selectionStartPoint.x, value.location.x),
            y: min(selectionStartPoint.y, value.location.y),
            width: abs(value.location.x - selectionStartPoint.x),
            height: abs(value.location.y - selectionStartPoint.y)
        )
    }

    // MARK: - Double-Tap Gesture for Waypoints

    private func waypointDoubleTapGesture(cellSize: CGFloat, offset: CGPoint) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                guard showTransitionPaths, hasTransition else { return }
                guard let selectedAthleteID, let player else { return }
                guard let selectedAthlete = player.currentAthletes.first(where: { $0.id == selectedAthleteID })
                else { return }

                let scaledPoint = CGPoint(
                    x: (value.location.x - offset.x) / cellSize,
                    y: (value.location.y - offset.y) / cellSize
                )
                let hitRadiusSquared = interactionHitRadiusSquared(for: cellSize)

                guard
                    PathCalculations.squaredDistance(from: scaledPoint, to: selectedAthlete.position)
                        < hitRadiusSquared
                else { return }

                addWaypoint()
            }
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

    private func addWaypoint() {
        guard entitlementManager.isPro else {
            showingUpgradeSheet = true
            return
        }
        guard let selectedAthleteID, let startFormationID, let endFormationID, let player else { return }
        let startAthlete = player.startAthletes.first(where: { $0.id == selectedAthleteID })
        let endAthlete = player.endAthletes.first(where: { $0.id == selectedAthleteID })
        guard let startAthlete, let endAthlete else { return }

        store.mutateAthleteTransition(from: startFormationID, to: endFormationID, athleteID: selectedAthleteID) { t in
            if t.pathWaypoints.isEmpty {
                let point = t.pathControlPoint
                    ?? CGPoint(
                        x: (startAthlete.position.x + endAthlete.position.x) / 2,
                        y: (startAthlete.position.y + endAthlete.position.y) / 2
                    )
                t.pathWaypoints = [PathWaypoint(position: point, isSmooth: true)]
                t.pathControlPoint = nil
            } else {
                let lastNode = t.pathWaypoints.last?.position ?? startAthlete.position
                let point = CGPoint(
                    x: (lastNode.x + endAthlete.position.x) / 2,
                    y: (lastNode.y + endAthlete.position.y) / 2
                )
                t.pathWaypoints.append(PathWaypoint(position: point, isSmooth: true))
            }
        }
        refreshTransitionFromStore()
    }

    private func deletePendingWaypoint() {
        guard
            let waypointID = pendingWaypointDeletionID,
            let selectedAthleteID,
            let startFormationID,
            let endFormationID
        else {
            pendingWaypointDeletionID = nil
            return
        }

        pendingWaypointDeletionID = nil
        store.mutateAthleteTransition(from: startFormationID, to: endFormationID, athleteID: selectedAthleteID) { t in
            guard let waypointIndex = t.pathWaypoints.firstIndex(where: { $0.id == waypointID }) else { return }
            t.pathWaypoints.remove(at: waypointIndex)
        }
        refreshTransitionFromStore()
    }

    private func resetSelectedPaths() {
        if selectedAthleteIDs.count == 1, let athleteID = selectedAthleteIDs.first {
            guard let startFormationID, let endFormationID else { return }
            clearTransitionDragState()
            store.mutateAthleteTransition(from: startFormationID, to: endFormationID, athleteID: athleteID) { t in
                t.pathControlPoint = nil
                t.pathWaypoints = []
            }
            refreshTransitionFromStore()
        } else {
            showingResetAllPathsConfirmation = true
        }
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
        recomputePathCollisionIDs()
    }

    // MARK: - Formation Actions

    private func snappingResult(for translation: CGPoint) -> SnapResult {
        guard !dragStartPositions.isEmpty else {
            return SnapResult(translation: translation, guides: [])
        }

        let result = AlignmentSnapEngine.snap(
            translation: translation,
            startingPositions: Array(dragStartPositions.values),
            otherAthletePositions: renderedAthletes
                .filter { !selectedAthleteIDs.contains($0.id) }
                .map(\.position),
            skipLinearGuides: renderedAthletes.count > 20
        )
        return SnapResult(translation: result.translation, guides: result.guides)
    }

    private func clampedCoordinate(_ value: CGFloat, upperBound: CGFloat) -> CGFloat {
        max(0, min(upperBound, round(value)))
    }

    private func addAthlete() {
        let newID = store.addAthlete()
        selectedAthleteIDs = [newID]
        
        if let newAthlete = store.routine.roster.first(where: { $0.id == newID }) {
            athleteLabelDraft = newAthlete.label
            showingAthleteRenamePrompt = true
        }
    }

    private func beginAthleteRename() {
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
            athlete.label = String(trimmedLabel.prefix(4))
        }
    }

    private func applyTemplate() {
        store.applyBowlingPinTemplate(to: formationID)
        selectedAthleteIDs = []
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

    private func deleteSelectedAthlete() {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Authentication is required to perform this destructive action.") { success, _ in
                DispatchQueue.main.async {
                    if success {
                        self.performDeleteSelectedAthlete()
                    }
                }
            }
        } else {
            performDeleteSelectedAthlete()
        }
    }

    private func performDeleteSelectedAthlete() {
        guard let selectedAthleteID else { return }
        store.deleteAthlete(id: selectedAthleteID)
        selectedAthleteIDs = []
    }

    private func undoLastMove() {
        guard let previousPositions = undoStack.popLast() else { return }
        store.mutateFormation(id: formationID) { formation in
            for entry in previousPositions {
                if let placementIndex = formation.placementIndex(for: entry.id) {
                    formation.placements[placementIndex].position = entry.position
                }
            }
        }
    }

    private func selectCollision(at index: Int) {
        guard !collidingAthletes.isEmpty else { return }
        let safeIndex = index % collidingAthletes.count
        selectedAthleteIDs = [collidingAthletes[safeIndex].id]
    }

    private func selectPathCollision(at index: Int) {
        guard !pathCollidingAthletes.isEmpty else { return }
        let safeIndex = index % pathCollidingAthletes.count
        selectedAthleteIDs = [pathCollidingAthletes[safeIndex].id]
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
            pathCollisionIDs: cachedPathCollisionIDs,
            startFormationColor: transitionStartColor,
            endFormationColor: transitionEndColor,
            transitionProgress: player?.progress ?? 0
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

    private func resetView() {
        withAnimation(.spring()) {
            zoomScale = 1.0
            lastZoomScale = 1.0
            canvasPanOffset = .zero
            lastCanvasPanOffset = .zero
        }
    }
}

private struct SnapResult {
    let translation: CGPoint
    let guides: [AlignmentGuideRenderItem]
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
