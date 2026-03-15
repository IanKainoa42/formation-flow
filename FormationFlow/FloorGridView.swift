import Combine
import SwiftUI

// MARK: - Floor Grid View

struct FloorGridView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @ObservedObject var store: RoutineStore
    let formationID: UUID
    var onDuplicateAsNext: () -> Void

    // Transition parameters (nil when no adjacent formation)
    var player: TransitionPlayer?
    var startFormationID: UUID?
    var endFormationID: UUID?

    @State private var selectedAthleteIDs: Set<UUID> = []
    @State private var showingRosterSheet = false
    @State private var showingNotesSheet = false
    @State private var showingInspectorSheet = false
    @State private var showingTransportSheet = false
    @State private var showingAthleteRenamePrompt = false
    @State private var athleteLabelDraft = ""
    @State private var showingAthleteDeleteConfirmation = false
    @State private var isDraggingAthletes = false
    @State private var isPanningCanvas = false
    @State private var isDrawingSelectionBox = false
    @State private var selectionRect: CGRect? = nil
    @State private var selectionStartPoint: CGPoint = .zero
    @State private var dragStartPositions: [UUID: CGPoint] = [:]
    @State private var undoStack: [[(id: UUID, position: CGPoint)]] = []
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    @State private var canvasPanOffset: CGSize = .zero
    @State private var lastCanvasPanOffset: CGSize = .zero
    @State private var isSwapMode = false
    @State private var swapSourceAthleteID: UUID?
    @State private var collisionMessage: String?
    @State private var hasMadeFirstSelection = false
    @State private var activeAlignmentGuides: [AlignmentGuideRenderItem] = []
    @State private var rosterDeleteIDs: [UUID] = []
    @State private var collisionCycleIndex: Int = 0

    // Transition editing state
    @State private var focusedEndpoint: PreviewEditableEndpoint?
    @State private var isDraggingEndpoint = false
    @State private var isDraggingPathHandle = false
    @State private var draggingWaypointID: UUID?
    @State private var endpointDragStartPosition: CGPoint?
    @State private var showingResetAllPathsConfirmation = false
    @State private var playerTick: UInt = 0

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

    private var renderedAthletes: [RenderedAthlete] {
        _ = playerTick // force redraw on player updates
        if let player, player.progress > 0 {
            return player.currentAthletes
        }
        return store.renderedAthletes(for: formationID)
    }

    private var collisionSummary: (count: Int, ids: Set<UUID>) {
        PathCalculations.collisionSummary(in: renderedAthletes)
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
        let endLookup = Dictionary(uniqueKeysWithValues: player.endAthletes.map { ($0.id, $0) })
        return player.startAthletes.compactMap { athlete in
            guard let endAthlete = endLookup[athlete.id] else { return nil }
            let transition = player.transitionSpec.athleteTransition(for: athlete.id)
            return TransitionPathRenderItem(
                athleteID: athlete.id,
                startPosition: athlete.position,
                endPosition: endAthlete.position,
                controlPoint: transition.pathControlPoint,
                waypoints: transition.pathWaypoints,
                moveDelay: transition.moveDelay
            )
        }
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

    private var pathCollisionIDs: Set<UUID> {
        guard let player else { return [] }
        return PathCalculations.findPathCollisionIDs(paths: transitionPaths, counts: CGFloat(player.counts))
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
        return store.routine.formations.first(where: { $0.id == startFormationID })?.name
    }

    private var endFormationName: String? {
        guard let endFormationID else { return nil }
        return store.routine.formations.first(where: { $0.id == endFormationID })?.name
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

    private var compactBannerConfiguration: (text: String, color: Color)? {
        if let collisionMessage {
            return (collisionMessage, .red)
        }

        if isSwapMode,
           let swapSourceAthleteID,
           let rosterAthlete = store.routine.roster.first(where: { $0.id == swapSourceAthleteID })
        {
            return ("Tap another athlete to swap with \(rosterAthlete.label).", .blue)
        }

        if !pathCollisionIDs.isEmpty {
            return ("\(pathCollisionIDs.count) athletes have crossing paths.", .red)
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
        .confirmationDialog(
            "Delete athlete?",
            isPresented: $showingAthleteDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Athlete", role: .destructive) {
                deleteSelectedAthlete()
            }
        } message: {
            Text("This removes the athlete from the roster, every formation, and all transitions.")
        }
        .onChange(of: formationID) { _, _ in
            selectedAthleteIDs = []
            isSwapMode = false
            swapSourceAthleteID = nil
            collisionMessage = nil
            activeAlignmentGuides = []
            collisionCycleIndex = 0
            focusedEndpoint = nil
            showingInspectorSheet = false
            showingTransportSheet = false
            showingAthleteRenamePrompt = false
            showingAthleteDeleteConfirmation = false
            athleteLabelDraft = ""
            canvasPanOffset = .zero
            lastCanvasPanOffset = .zero
            clearTransitionDragState()
        }
        .onChange(of: selectedAthleteIDs) { _, newSelection in
            if !newSelection.isEmpty {
                hasMadeFirstSelection = true
            }
            if newSelection.isEmpty {
                isSwapMode = false
                swapSourceAthleteID = nil
                focusedEndpoint = nil
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
        } message: {
            Text("This removes every custom curve and waypoint and returns all athletes to straight-line travel.")
        }
        .onReceive(player?.objectWillChange.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()) { _ in
            playerTick &+= 1
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
                    } else if isCompactLayout {
                        canvasArea
                    } else {
                        HStack(spacing: 0) {
                            canvasArea
                            if !selectedAthleteIDs.isEmpty {
                                Divider()
                            }
                            inspectorPanel
                                .frame(width: selectedAthleteIDs.isEmpty ? 0 : 320)
                                .clipped()
                        }
                        .animation(.easeInOut(duration: 0.2), value: selectedAthleteIDs.isEmpty)
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
                }

                Button(action: addAthlete) {
                    Label(isCompactLayout ? "Add" : "Add Athlete", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)

                if isCompactLayout {
                    Group {
                        if selectedAthleteIDs.isEmpty {
                            Button {
                                showingInspectorSheet = true
                            } label: {
                                Label(compactInspectButtonTitle, systemImage: "slider.horizontal.3")
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button {
                                showingInspectorSheet = true
                            } label: {
                                Label(compactInspectButtonTitle, systemImage: "slider.horizontal.3")
                            }
                            .buttonStyle(.borderedProminent)
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
                }

                Button(action: beginSwapMode) {
                    Label("Swap", systemImage: "arrow.triangle.swap")
                }
                .buttonStyle(.bordered)
                .disabled(selectedAthleteID == nil)

                if isCompactLayout {
                    compactOverflowMenu
                } else {
                    Button(action: { showingRosterSheet = true }) {
                        Label("Manage Roster", systemImage: "list.bullet.rectangle")
                    }
                    .buttonStyle(.bordered)

                    Button(action: resetView) {
                        Label("Reset View", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)

                    Button(action: { showingNotesSheet = true }) {
                        Label("Notes", systemImage: "note.text")
                    }
                    .buttonStyle(.bordered)
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

            Button(action: resetView) {
                Label("Reset View", systemImage: "arrow.counterclockwise")
            }

            Button(action: undoLastMove) {
                Label("Undo Move", systemImage: "arrow.uturn.backward")
            }
            .disabled(undoStack.isEmpty)
        } label: {
            compactOverflowMenuLabel
        }
        .buttonStyle(.bordered)
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

                            Button(action: applyTemplate) {
                                Label("Apply 10-Athlete Template", systemImage: "square.grid.3x3.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button(action: onDuplicateAsNext) {
                                Label("Duplicate as Next Formation", systemImage: "plus.square.on.square")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(renderedAthletes.isEmpty)
                        }
                    } else {
                        HStack(spacing: 12) {
                            Button(action: addAthlete) {
                                Label("Add Athlete", systemImage: "plus.circle.fill")
                                    .frame(minWidth: 180)
                            }
                            .buttonStyle(.borderedProminent)

                            Button(action: applyTemplate) {
                                Label("Apply 10-Athlete Template", systemImage: "square.grid.3x3.fill")
                                    .frame(minWidth: 220)
                            }
                            .buttonStyle(.bordered)

                            Button(action: onDuplicateAsNext) {
                                Label("Duplicate as Next Formation", systemImage: "plus.square.on.square")
                                    .frame(minWidth: 220)
                            }
                            .buttonStyle(.bordered)
                            .disabled(renderedAthletes.isEmpty)
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
            let offset = CGPoint(
                x: (geometry.size.width - canvasWidth) / 2 + displayPanOffset.width,
                y: (geometry.size.height - canvasHeight) / 2 + displayPanOffset.height
            )
            let phoneUsesPlaybackRail =
                isPhoneLandscape && player != nil && startFormationName != nil && endFormationName != nil

            let canvasContent = ZStack(alignment: .top) {
                FloorCanvasView(
                    athletes: renderedAthletes,
                    selectedAthleteIDs: selectedAthleteIDs,
                    transitionPaths: transitionPaths,
                    endpointMarkers: endpointMarkers,
                    alignmentGuides: activeAlignmentGuides,
                    collisionIDs: collisionSummary.ids,
                    pathCollisionIDs: pathCollisionIDs,
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
                    ghostAthletes: previousFormationAthletes
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

                if isPhoneLayout {
                    VStack(spacing: 10) {
                        phoneTopOverlay

                        if let compactBannerConfiguration {
                            banner(text: compactBannerConfiguration.text, color: compactBannerConfiguration.color)
                        }

                        Spacer(minLength: 0)

                        VStack(spacing: 10) {
                            if selectedRosterAthlete != nil || selectedAthleteIDs.count > 1 {
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
                                    endFormationName: endFormationName
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                } else {
                    VStack(spacing: isCompactLayout ? 8 : 10) {
                        if isCompactLayout {
                            if let compactBannerConfiguration {
                                banner(text: compactBannerConfiguration.text, color: compactBannerConfiguration.color)
                            }
                        } else {
                            if let collisionMessage {
                                banner(text: collisionMessage, color: .red)
                            }

                            if isSwapMode, let swapSourceAthleteID,
                                let rosterAthlete = store.routine.roster.first(where: { $0.id == swapSourceAthleteID })
                            {
                                banner(
                                    text: "Tap another athlete to swap with \(rosterAthlete.label).",
                                    color: .blue
                                )
                            } else if !hasMadeFirstSelection {
                                banner(
                                    text: "Tap an athlete to edit it. Drag on empty space to box-select.",
                                    color: .accentColor
                                )
                            }

                            if !pathCollisionIDs.isEmpty {
                                banner(
                                    text: "\(pathCollisionIDs.count) athletes have crossing paths.",
                                    color: .red
                                )
                            }
                        }
                    }
                    .padding(.horizontal, isCompactLayout ? 12 : 0)
                    .padding(.top, isHeightConstrained ? 4 : 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if phoneUsesPlaybackRail,
                let player,
                let startFormationName,
                let endFormationName
            {
                HStack(spacing: 10) {
                    canvasContent

                    CompactTransitionPlaybackRailView(
                        player: player,
                        startFormationName: startFormationName,
                        endFormationName: endFormationName
                    )
                }
            } else {
                canvasContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var compactInspectorSheet: some View {
        NavigationStack {
            inspectorPanel
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
                    endFormationName: endFormationName
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
        HStack(spacing: 8) {
            Button(action: addAthlete) {
                Label("Add", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)

            if selectedAthleteID != nil {
                Button(action: beginSwapMode) {
                    Image(systemName: "arrow.triangle.swap")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.bordered)
            }

            Spacer(minLength: 0)

            phoneOverflowMenu
        }
        .controlSize(.small)
    }

    private var phoneOverflowMenu: some View {
        Menu {
            Button(action: { showingRosterSheet = true }) {
                Label("Roster", systemImage: "list.bullet.rectangle")
            }

            Button(action: { showingNotesSheet = true }) {
                Label("Notes", systemImage: "note.text")
            }

            Button(action: resetView) {
                Label("Reset View", systemImage: "arrow.counterclockwise")
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

                    Button(action: beginSwapMode) {
                        Label("Swap Position", systemImage: "arrow.triangle.swap")
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

    // MARK: - Inspector Panel

    private var inspectorPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let selectedRosterAthlete, let selectedPlacement {
                    AthleteInspectorView(
                        athlete: selectedRosterAthlete,
                        position: selectedPlacement.position,
                        isSwapMode: isSwapMode,
                        formationCount: store.routine.formations.count,
                        compactLayout: isCompactLayout,
                        onUpdateLabel: { newLabel in
                            store.mutateRosterAthlete(id: selectedRosterAthlete.id) { athlete in
                                athlete.label = newLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? athlete.label
                                    : newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        },
                        onUpdateRole: { newRole in
                            store.mutateRosterAthlete(id: selectedRosterAthlete.id) { athlete in
                                athlete.role = newRole
                            }
                        },
                        onSwap: beginSwapMode,
                        onDelete: {
                            deleteSelectedAthlete()
                        },
                        onClearSelection: {
                            selectedAthleteIDs = []
                        }
                    )

                    if hasTransition, let selectedTransition, let player,
                       let startFormationID, let endFormationID
                    {
                        Divider()
                        transitionInspectorSection(
                            transition: selectedTransition,
                            player: player,
                            startFormationID: startFormationID,
                            endFormationID: endFormationID
                        )
                    }
                } else if selectedAthleteIDs.count > 1 {
                    MultiSelectionInspectorView(
                        count: selectedAthleteIDs.count,
                        compactLayout: isCompactLayout,
                        onClearSelection: { selectedAthleteIDs = [] }
                    )
                } else {
                    EmptyInspectorView(
                        title: "Inspector",
                        message: "Select one athlete to edit its label, role, and actions. Multi-select to move groups together.",
                        compactLayout: isCompactLayout
                    )
                }
            }
        }
        .background(.thinMaterial)
        .frame(maxHeight: .infinity)
    }

    // MARK: - Transition Inspector

    private func transitionInspectorSection(
        transition: AthleteTransition,
        player: TransitionPlayer,
        startFormationID: UUID,
        endFormationID: UUID
    ) -> some View {
        VStack(alignment: .leading, spacing: isCompactLayout ? 14 : 16) {
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

            // Move delay
            VStack(alignment: .leading, spacing: isCompactLayout ? 6 : 8) {
                Text("Start Delay")
                    .font(.subheadline.weight(.semibold))
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
                Button {
                    guard let selectedAthleteID else { return }
                    store.mutateAthleteTransition(
                        from: startFormationID,
                        to: endFormationID,
                        athleteID: selectedAthleteID
                    ) { t in
                        t.pathWaypoints.remove(at: waypointIndex)
                    }
                    refreshTransitionFromStore()
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }

            HStack {
                Text(waypoint.isSmooth ? "Smooth" : "Sharp")
                Spacer()
                Button(waypoint.isSmooth ? "Make Sharp" : "Make Smooth") {
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
            .confirmationDialog(
                "Delete \(rosterDeleteIDs.count == 1 ? "this athlete" : "these athletes")?",
                isPresented: Binding(
                    get: { !rosterDeleteIDs.isEmpty },
                    set: { if !$0 { rosterDeleteIDs = [] } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    for id in rosterDeleteIDs {
                        store.deleteAthlete(id: id)
                    }
                    selectedAthleteIDs.subtract(rosterDeleteIDs)
                    rosterDeleteIDs = []
                }
            } message: {
                Text("This will remove them from all \(store.routine.formations.count) formations and their transitions.")
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

                // Priority 2: Hit-test for new drag initiation
                if hasTransition {
                    // In transition mode: path handles take priority over non-selected athletes
                    // 2a: Currently selected athlete (allow dragging)
                    if let hitAthlete = renderedAthletes.first(where: {
                        selectedAthleteIDs.contains($0.id)
                            && PathCalculations.squaredDistance(from: startScaledPoint, to: $0.position) < hitRadiusSquared
                    }) {
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

                    // 2b: Waypoint/path handles (prioritized over non-selected athletes)
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
                                    focusedEndpoint = nil
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
                                        focusedEndpoint = nil
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
                                    focusedEndpoint = nil
                                    handlePathDragContinued(scaledPoint: scaledPoint)
                                    return
                                }
                            }
                        }
                    }

                    // 2c: Non-selected athletes
                    if let hitAthlete = renderedAthletes.first(where: {
                        PathCalculations.squaredDistance(from: startScaledPoint, to: $0.position) < hitRadiusSquared
                    }) {
                        selectedAthleteIDs = [hitAthlete.id]
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
                } else {
                    // Not in transition mode: athletes have highest priority
                    if let hitAthlete = renderedAthletes.first(where: {
                        PathCalculations.squaredDistance(from: startScaledPoint, to: $0.position) < hitRadiusSquared
                    }) {
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

                // 2c: Endpoint markers (other formation — tapping focuses that formation)
                if hasTransition {
                    if let hitMarker = endpointMarkers.first(where: {
                        PathCalculations.squaredDistance(from: startScaledPoint, to: $0.position) < hitRadiusSquared
                    }) {
                        selectedAthleteIDs = [hitMarker.athleteID]
                        focusedEndpoint = hitMarker.endpoint
                        endpointDragStartPosition = hitMarker.position
                        guard dragDistance >= dragActivationDistance else { return }
                        isDraggingEndpoint = true
                        handleEndpointDragContinued(value, cellSize: cellSize, offset: offset)
                        return
                    }
                }

                // 2d: Empty space → pan if zoomed on compact, otherwise selection box
                focusedEndpoint = nil
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
                }

                if isSwapMode, let swapSourceAthleteID {
                    let tapPoint = CGPoint(
                        x: (value.location.x - offset.x) / cellSize,
                        y: (value.location.y - offset.y) / cellSize
                    )

                    // Try swapping in endpoint markers (check both sides)
                    if hasTransition, let player {
                        let allEndpointAthletes: [(athlete: RenderedAthlete, formationID: UUID)] =
                            player.startAthletes.map { ($0, startFormationID!) }
                            + player.endAthletes.map { ($0, endFormationID!) }
                        if let target = allEndpointAthletes.first(where: {
                            $0.athlete.id != swapSourceAthleteID
                                && PathCalculations.squaredDistance(from: tapPoint, to: $0.athlete.position) < hitRadiusSquared
                        }) {
                            store.swapPositions(in: target.formationID, id1: swapSourceAthleteID, id2: target.athlete.id)
                            selectedAthleteIDs = [target.athlete.id]
                            refreshTransitionFromStore()
                            isSwapMode = false
                            self.swapSourceAthleteID = nil
                            return
                        }
                    }

                    // Try swapping in main formation
                    if let targetAthlete = renderedAthletes.first(where: {
                        $0.id != swapSourceAthleteID
                            && PathCalculations.squaredDistance(from: tapPoint, to: $0.position) < hitRadiusSquared
                    }) {
                        store.swapPositions(in: formationID, id1: swapSourceAthleteID, id2: targetAthlete.id)
                        selectedAthleteIDs = [targetAthlete.id]
                        refreshTransitionFromStore()
                    }
                    isSwapMode = false
                    self.swapSourceAthleteID = nil
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
                        if hasTransition, let player {
                            if let athlete = player.currentAthletes.first(where: {
                                PathCalculations.squaredDistance(from: tapPoint, to: $0.position) < hitRadiusSquared
                            }) {
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

                if renderedAthletes.contains(where: {
                    PathCalculations.squaredDistance(from: tapPoint, to: $0.position) < hitRadiusSquared
                }) {
                    return
                }

                if endpointMarkers.contains(where: {
                    PathCalculations.squaredDistance(from: tapPoint, to: $0.position) < hitRadiusSquared
                }) {
                    return
                }

                if transitionHandleIsHit(at: tapPoint, hitRadiusSquared: hitRadiusSquared) {
                    return
                }

                selectedAthleteIDs = []
                focusedEndpoint = nil
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
                guard hasTransition else { return }
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
                .map(\.position)
        )
        return SnapResult(translation: result.translation, guides: result.guides)
    }

    private func clampedCoordinate(_ value: CGFloat, upperBound: CGFloat) -> CGFloat {
        max(0, min(upperBound, round(value)))
    }

    private func addAthlete() {
        let newID = store.addAthlete()
        selectedAthleteIDs = [newID]
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

    private func beginSwapMode() {
        guard let selectedAthleteID else { return }
        swapSourceAthleteID = selectedAthleteID
        isSwapMode = true
    }

    private func deleteSelectedAthlete() {
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
        collisionMessage = "\(collidingAthletes.count) athletes are within 2ft. Use arrows to cycle."
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

        var body: some View {
            NavigationStack {
                FloorGridView(
                    store: store,
                    formationID: store.routine.formations.first?.id ?? UUID()
                ) {}
            }
        }
    }

    return PreviewWrapper()
}
