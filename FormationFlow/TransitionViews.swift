import SwiftUI

private enum TransitionCountFormatting {
    static func value(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.001 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }

    static func value(_ value: CGFloat) -> String {
        Self.value(Double(value))
    }

    static func label(_ value: Double) -> String {
        let unit = abs(value - 1) < 0.001 ? "count" : "counts"
        return "\(self.value(value)) \(unit)"
    }

    static func label(_ value: CGFloat) -> String {
        Self.label(Double(value))
    }
}

enum PreviewInteractionMode: String, CaseIterable, Identifiable {
    case editSpots
    case editPath

    var id: String { rawValue }

    var title: String {
        switch self {
        case .editSpots: return "Edit Spots"
        case .editPath: return "Edit Path"
        }
    }

    var description: String {
        switch self {
        case .editSpots:
            return "Drag the counterpart picture directly on the floor so you can fix transition issues without leaving preview."
        case .editPath:
            return "Adjust delay, curves, and waypoints for the selected athlete without changing formation spots."
        }
    }
}

// MARK: - Transport Sidebar

struct TransitionTransportSidebarView: View {
    @ObservedObject var player: TransitionPlayer
    let startFormationName: String
    let endFormationName: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerSection
                playbackButtons
                scrubSection
            }
            .padding(20)
        }
        .background(.thinMaterial)
        .navigationTitle("Transport")
        .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 280)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview Transport")
                .font(.headline)
            Text("\(startFormationName) → \(endFormationName)")
                .font(.title3.weight(.semibold))
            Text("Scrub and playback stay here so the right inspector can focus on settings and path work.")
                .foregroundColor(.secondary)
        }
    }

    private var playbackButtons: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Playback")
                .font(.subheadline.weight(.semibold))

            Button(action: { player.reset() }) {
                Label("Reset", systemImage: "backward.end.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(action: togglePlayback) {
                Label(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button(action: { player.isLooping.toggle() }) {
                Label("Loop", systemImage: "repeat")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(player.isLooping ? .accentColor : .secondary)
        }
    }

    private var scrubSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Scrub")
                .font(.subheadline.weight(.semibold))

            Slider(
                value: Binding(
                    get: { player.progress },
                    set: { player.seek(to: $0) }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    if editing {
                        player.pause()
                    }
                }
            )

            HStack {
                Text("\(TransitionCountFormatting.value(player.progress * CGFloat(player.counts))) / \(TransitionCountFormatting.value(player.counts))")
                    .font(.system(.body, design: .monospaced))
                Spacer()
                Text(player.counts == 1 ? "Count" : "Counts")
                    .foregroundColor(.secondary)
            }
            .foregroundColor(.secondary)
        }
    }

    private func togglePlayback() {
        if player.isPlaying {
            player.pause()
        } else {
            player.play()
        }
    }
}

// MARK: - Transition Player View

struct TransitionPlayerView: View {
    @ObservedObject var store: RoutineStore
    @ObservedObject var player: TransitionPlayer
    let startFormationID: UUID
    let endFormationID: UUID
    let selectedFormationName: String
    @Binding var previewReferenceMode: PreviewReferenceMode
    let editableEndpoint: PreviewEditableEndpoint
    var onSelectPreviousFormation: () -> Void
    var onSelectNextFormation: () -> Void
    var canSelectPreviousFormation: Bool
    var canSelectNextFormation: Bool

    @State private var selectedAthleteID: UUID?
    @State private var interactionMode: PreviewInteractionMode = .editSpots
    @State private var isDraggingHandle = false
    @State private var draggingWaypointID: UUID?
    @State private var editableDragStartPosition: CGPoint?
    @State private var activeAlignmentGuides: [AlignmentGuideRenderItem] = []
    @State private var showingResetAllPathsConfirmation = false

    private var transitionIdentity: String {
        "\(startFormationID.uuidString)-\(endFormationID.uuidString)"
    }

    private var startFormation: Formation? {
        guard let index = store.formationIndex(id: startFormationID) else { return nil }
        return store.routine.formations[index]
    }

    private var endFormation: Formation? {
        guard let index = store.formationIndex(id: endFormationID) else { return nil }
        return store.routine.formations[index]
    }

    private var editableFormationID: UUID {
        editableEndpoint == .start ? startFormationID : endFormationID
    }

    private var editableFormationName: String {
        switch editableEndpoint {
        case .start:
            return startFormation?.name ?? "Previous Formation"
        case .end:
            return endFormation?.name ?? "Next Formation"
        }
    }

    private var readOnlyFormationName: String {
        switch editableEndpoint {
        case .start:
            return endFormation?.name ?? "Current Formation"
        case .end:
            return startFormation?.name ?? "Current Formation"
        }
    }

    private var editableAthletes: [RenderedAthlete] {
        editableEndpoint == .start ? player.startAthletes : player.endAthletes
    }

    private var transitionPaths: [TransitionPathRenderItem] {
        let endLookup = Dictionary(uniqueKeysWithValues: player.endAthletes.map { ($0.id, $0) })
        return player.startAthletes.compactMap { athlete in
            guard let endAthlete = endLookup[athlete.id] else { return nil }
            let transition = player.transitionSpec.athleteTransition(for: athlete.id)
            return TransitionPathRenderItem(
                athleteID: athlete.id,
                startPosition: athlete.position,
                endPosition: endAthlete.position,
                controlPoint: transition.pathControlPoint,
                waypoints: transition.pathWaypoints
            )
        }
    }

    private var endpointMarkers: [TransitionEndpointMarkerRenderItem] {
        let startMarkers = player.startAthletes.map { athlete in
            TransitionEndpointMarkerRenderItem(
                athleteID: athlete.id,
                label: athlete.label,
                role: athlete.role,
                position: athlete.position,
                endpoint: .start,
                style: editableEndpoint == .start ? .editable : .readOnly
            )
        }
        let endMarkers = player.endAthletes.map { athlete in
            TransitionEndpointMarkerRenderItem(
                athleteID: athlete.id,
                label: athlete.label,
                role: athlete.role,
                position: athlete.position,
                endpoint: .end,
                style: editableEndpoint == .end ? .editable : .readOnly
            )
        }
        return startMarkers + endMarkers
    }

    private var pathCollisionIDs: Set<UUID> {
        PathCalculations.findPathCollisionIDs(paths: transitionPaths)
    }

    private var selectedStartAthlete: RenderedAthlete? {
        guard let selectedAthleteID else { return nil }
        return player.startAthletes.first(where: { $0.id == selectedAthleteID })
    }

    private var selectedEndAthlete: RenderedAthlete? {
        guard let selectedAthleteID else { return nil }
        return player.endAthletes.first(where: { $0.id == selectedAthleteID })
    }

    private var selectedTransition: AthleteTransition? {
        guard let selectedAthleteID else { return nil }
        return player.transitionSpec.athleteTransition(for: selectedAthleteID)
    }

    private var hasCustomPaths: Bool {
        player.transitionSpec.athleteTransitions.contains {
            $0.pathControlPoint != nil || !$0.pathWaypoints.isEmpty
        }
    }

    private var canvasInstruction: String {
        switch interactionMode {
        case .editSpots:
            return "Drag the \(editableFormationName) spots to fix the move into \(readOnlyFormationName) without leaving preview."
        case .editPath:
            return "Select an athlete, double-tap it to add a waypoint, then drag path handles to refine the move."
        }
    }

    var body: some View {
        Group {
            if startFormation != nil && endFormation != nil {
                HStack(spacing: 0) {
                    canvasArea
                    Divider()
                    inspectorPanel
                        .frame(width: 380)
                }
            } else {
                ContentUnavailableView(
                    "Transition unavailable",
                    systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right"
                )
            }
        }
        .onAppear {
            resetPreviewInteractionMode()
            refreshFromStore()
        }
        .onChange(of: transitionIdentity) { _, _ in
            resetPreviewInteractionMode()
            refreshFromStore()
        }
        .onChange(of: store.routine) { _, _ in
            refreshFromStore()
        }
        .onChange(of: interactionMode) { _, _ in
            clearCanvasInteractionState()
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
            Text("This removes every custom curve and waypoint in this preview and returns all athletes to straight-line travel.")
        }
    }

    private var canvasArea: some View {
        GeometryReader { geometry in
            let cellSize = min(
                geometry.size.width / CourtConstants.width,
                geometry.size.height / CourtConstants.height
            )
            let canvasWidth = CourtConstants.width * cellSize
            let canvasHeight = CourtConstants.height * cellSize
            let offset = CGPoint(
                x: (geometry.size.width - canvasWidth) / 2,
                y: (geometry.size.height - canvasHeight) / 2
            )

            ZStack(alignment: .top) {
                FloorCanvasView(
                    athletes: player.currentAthletes,
                    selectedAthleteIDs: selectedAthleteID.map { [$0] } ?? [],
                    transitionPaths: transitionPaths,
                    endpointMarkers: endpointMarkers,
                    alignmentGuides: activeAlignmentGuides,
                    pathCollisionIDs: pathCollisionIDs,
                    cellSize: cellSize,
                    offset: offset
                )
                .gesture(canvasGesture(cellSize: cellSize, offset: offset))
                .simultaneousGesture(waypointDoubleTapGesture(cellSize: cellSize, offset: offset))

                VStack(spacing: 10) {
                    banner(text: canvasInstruction, color: .accentColor)

                    if !pathCollisionIDs.isEmpty {
                        banner(
                            text: "\(pathCollisionIDs.count) athletes have crossing paths inside this preview.",
                            color: .red
                        )
                    }
                }
                .padding(.top, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inspectorPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerSection
                previewSettingsSection
                playbackSettingsSection
                selectedAthleteSection
            }
            .padding(20)
        }
        .background(.thinMaterial)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview Inspector")
                        .font(.headline)
                    if let startFormation, let endFormation {
                        Text("\(startFormation.name) → \(endFormation.name)")
                            .font(.title3.weight(.semibold))
                        Text("The selected formation stays anchored while preview lets you tune the counterpart picture and the path in one place.")
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 0)

                Button(role: .destructive) {
                    showingResetAllPathsConfirmation = true
                } label: {
                    Label("Reset All Paths", systemImage: "arrow.uturn.backward.circle")
                }
                .buttonStyle(.bordered)
                .disabled(!hasCustomPaths)
            }
        }
    }

    private var previewSettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Preview")
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 12) {
                Text("Selected Formation")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Button(action: onSelectPreviousFormation) {
                        Image(systemName: "chevron.left")
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canSelectPreviousFormation)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedFormationName)
                            .font(.body.weight(.semibold))
                        Text("Previewing \(previewReferenceMode == .intoSelected ? "into" : "out of") this picture")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer(minLength: 0)

                    Button(action: onSelectNextFormation) {
                        Image(systemName: "chevron.right")
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canSelectNextFormation)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Preview Pairing")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                Picker("Preview pairing", selection: $previewReferenceMode) {
                    ForEach(PreviewReferenceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(previewReferenceMode.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Canvas Interaction")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                Picker("Canvas interaction", selection: $interactionMode) {
                    ForEach(PreviewInteractionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(interactionMode.description)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Label("Dragging now updates \(editableFormationName). \(readOnlyFormationName) stays read-only in preview.", systemImage: "scope")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var playbackSettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Playback Settings")
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Transition Counts")
                    Spacer()
                    Text(TransitionCountFormatting.label(player.counts))
                        .font(.system(.body, design: .monospaced))
                }
                Slider(
                    value: Binding(
                        get: { player.counts },
                        set: { newValue in
                            store.mutateTransitionSpec(from: startFormationID, to: endFormationID) { spec in
                                spec.counts = max(1, newValue.rounded())
                                let maxTimingValue = CGFloat(spec.counts)
                                for athleteIndex in spec.athleteTransitions.indices {
                                    spec.athleteTransitions[athleteIndex].moveDelayCounts = min(
                                        spec.athleteTransitions[athleteIndex].moveDelayCounts,
                                        maxTimingValue
                                    )
                                    for waypointIndex in spec.athleteTransitions[athleteIndex].pathWaypoints.indices {
                                        spec.athleteTransitions[athleteIndex].pathWaypoints[waypointIndex].holdCounts = min(
                                            spec.athleteTransitions[athleteIndex].pathWaypoints[waypointIndex].holdCounts,
                                            maxTimingValue
                                        )
                                    }
                                }
                            }
                            refreshFromStore()
                        }
                    ),
                    in: 1...32,
                    step: 1
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Speed")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                Picker("Speed", selection: Binding(
                    get: { speedSelection(for: player.speed) },
                    set: { player.speed = $0 }
                )) {
                    Text("0.5x").tag(CGFloat(0.5))
                    Text("1x").tag(CGFloat(1.0))
                    Text("1.5x").tag(CGFloat(1.5))
                    Text("2x").tag(CGFloat(2.0))
                }
                .pickerStyle(.segmented)
            }
        }
    }

    @ViewBuilder
    private var selectedAthleteSection: some View {
        if let selectedStartAthlete, let selectedEndAthlete, let selectedTransition {
            VStack(alignment: .leading, spacing: 16) {
                Text("Selected Athlete")
                    .font(.subheadline.weight(.semibold))

                HStack {
                    if selectedStartAthlete.role == .stuntGroup {
                        Image(systemName: "triangle.fill")
                            .foregroundColor(selectedStartAthlete.role.color)
                    } else {
                        Circle()
                            .fill(selectedStartAthlete.role.color)
                            .frame(width: 14, height: 14)
                    }

                    Text(selectedStartAthlete.label)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Button {
                        selectedAthleteID = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Text("Starts at (\(Int(selectedStartAthlete.position.x)), \(Int(selectedStartAthlete.position.y))) and finishes at (\(Int(selectedEndAthlete.position.x)), \(Int(selectedEndAthlete.position.y))).")
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Start Delay")
                    Slider(
                        value: Binding(
                            get: { selectedTransition.moveDelayCounts },
                            set: { newValue in
                                store.mutateAthleteTransition(
                                    from: startFormationID,
                                    to: endFormationID,
                                    athleteID: selectedStartAthlete.id
                                ) { transition in
                                    transition.moveDelayCounts = min(CGFloat(player.counts), max(0, newValue))
                                }
                                refreshFromStore()
                            }
                        ),
                        in: 0...CGFloat(player.counts),
                        step: 0.5
                    )
                    Text(TransitionCountFormatting.label(selectedTransition.moveDelayCounts))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Path")
                    HStack(spacing: 10) {
                        Button(action: clearPath) {
                            Label("Straight", systemImage: "line.diagonal")
                        }
                        .buttonStyle(.bordered)

                        Button(action: ensureCurve) {
                            Label("Curve", systemImage: "scribble")
                        }
                        .buttonStyle(.bordered)
                    }

                    Text(
                        interactionMode == .editPath
                            ? "Double-tap the selected athlete on the floor to add a waypoint, then drag the handles to place it."
                            : "Switch the canvas to Edit Path when you want to drag curve handles directly on the floor."
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                if !selectedTransition.pathWaypoints.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Waypoints")
                            .font(.subheadline.weight(.semibold))
                        ForEach(Array(selectedTransition.pathWaypoints.enumerated()), id: \.element.id) { waypointIndex, waypoint in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Waypoint \(waypointIndex + 1)")
                                        .font(.body.weight(.medium))
                                    Spacer()
                                    Button {
                                        store.mutateAthleteTransition(
                                            from: startFormationID,
                                            to: endFormationID,
                                            athleteID: selectedStartAthlete.id
                                        ) { transition in
                                            transition.pathWaypoints.remove(at: waypointIndex)
                                        }
                                        refreshFromStore()
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
                                        store.mutateAthleteTransition(
                                            from: startFormationID,
                                            to: endFormationID,
                                            athleteID: selectedStartAthlete.id
                                        ) { transition in
                                            transition.pathWaypoints[waypointIndex].isSmooth.toggle()
                                        }
                                        refreshFromStore()
                                    }
                                    .buttonStyle(.bordered)
                                }

                                HStack {
                                    Text("Hold")
                                    Spacer()
                                    Button("- 0.5 count") {
                                        store.mutateAthleteTransition(
                                            from: startFormationID,
                                            to: endFormationID,
                                            athleteID: selectedStartAthlete.id
                                        ) { transition in
                                            transition.pathWaypoints[waypointIndex].holdCounts = max(
                                                0,
                                                transition.pathWaypoints[waypointIndex].holdCounts - 0.5
                                            )
                                        }
                                        refreshFromStore()
                                    }
                                    .buttonStyle(.bordered)

                                    Text(TransitionCountFormatting.label(waypoint.holdCounts))
                                        .font(.system(.body, design: .monospaced))
                                        .frame(width: 84)

                                    Button("+ 0.5 count") {
                                        store.mutateAthleteTransition(
                                            from: startFormationID,
                                            to: endFormationID,
                                            athleteID: selectedStartAthlete.id
                                        ) { transition in
                                            transition.pathWaypoints[waypointIndex].holdCounts = min(
                                                CGFloat(player.counts),
                                                transition.pathWaypoints[waypointIndex].holdCounts + 0.5
                                            )
                                        }
                                        refreshFromStore()
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(14)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
            }
        } else {
            EmptyInspectorView(
                title: "Athlete Inspector",
                message: interactionMode == .editSpots
                    ? "Tap or drag an editable endpoint marker to fix a formation spot, or switch to Edit Path to work on curves and waypoints."
                    : "Select one athlete on the canvas to edit its start delay and path."
            )
        }
    }

    private func canvasGesture(cellSize: CGFloat, offset: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                switch interactionMode {
                case .editSpots:
                    handleSpotGestureChanged(value, cellSize: cellSize, offset: offset)
                case .editPath:
                    handlePathGestureChanged(value, cellSize: cellSize, offset: offset)
                }
            }
            .onEnded { value in
                switch interactionMode {
                case .editSpots:
                    handleSpotGestureEnded(value, cellSize: cellSize, offset: offset)
                case .editPath:
                    handlePathGestureEnded()
                }
            }
    }

    private func handleSpotGestureChanged(
        _ value: DragGesture.Value,
        cellSize: CGFloat,
        offset: CGPoint
    ) {
        let startScaledPoint = CGPoint(
            x: (value.startLocation.x - offset.x) / cellSize,
            y: (value.startLocation.y - offset.y) / cellSize
        )

        if editableDragStartPosition == nil {
            guard let hitAthlete = editableAthlete(at: startScaledPoint) else {
                selectedAthleteID = nil
                activeAlignmentGuides = []
                return
            }

            selectedAthleteID = hitAthlete.id
            editableDragStartPosition = hitAthlete.position
        }

        guard let selectedAthleteID, let editableDragStartPosition else { return }

        let rawTranslation = CGPoint(
            x: value.translation.width / cellSize,
            y: value.translation.height / cellSize
        )
        let snapResult = AlignmentSnapEngine.snap(
            translation: rawTranslation,
            startingPositions: [editableDragStartPosition],
            otherAthletePositions: editableAthletes
                .filter { $0.id != selectedAthleteID }
                .map(\.position)
        )
        activeAlignmentGuides = snapResult.guides

        let nextPosition = CGPoint(
            x: clampedCoordinate(editableDragStartPosition.x + snapResult.translation.x, upperBound: CourtConstants.width),
            y: clampedCoordinate(editableDragStartPosition.y + snapResult.translation.y, upperBound: CourtConstants.height)
        )

        store.mutateFormation(id: editableFormationID) { formation in
            guard let placementIndex = formation.placementIndex(for: selectedAthleteID) else { return }
            formation.placements[placementIndex].position = nextPosition
        }
        refreshFromStore()
    }

    private func handleSpotGestureEnded(
        _ value: DragGesture.Value,
        cellSize: CGFloat,
        offset: CGPoint
    ) {
        if selectedAthleteID == nil {
            let tapPoint = CGPoint(
                x: (value.location.x - offset.x) / cellSize,
                y: (value.location.y - offset.y) / cellSize
            )
            selectedAthleteID = editableAthlete(at: tapPoint)?.id
        }

        editableDragStartPosition = nil
        activeAlignmentGuides = []
    }

    private func handlePathGestureChanged(
        _ value: DragGesture.Value,
        cellSize: CGFloat,
        offset: CGPoint
    ) {
        activeAlignmentGuides = []

        let scaledPoint = CGPoint(
            x: (value.location.x - offset.x) / cellSize,
            y: (value.location.y - offset.y) / cellSize
        )
        let startScaledPoint = CGPoint(
            x: (value.startLocation.x - offset.x) / cellSize,
            y: (value.startLocation.y - offset.y) / cellSize
        )

        if let selectedAthleteID,
            let startAthlete = player.startAthletes.first(where: { $0.id == selectedAthleteID }),
            let endAthlete = player.endAthletes.first(where: { $0.id == selectedAthleteID })
        {
            let transition = player.transitionSpec.athleteTransition(for: selectedAthleteID)

            if !transition.pathWaypoints.isEmpty {
                if let draggingWaypointID,
                    let waypointIndex = transition.pathWaypoints.firstIndex(where: { $0.id == draggingWaypointID })
                {
                    isDraggingHandle = true
                    store.mutateAthleteTransition(
                        from: startFormationID,
                        to: endFormationID,
                        athleteID: selectedAthleteID
                    ) { transition in
                        transition.pathWaypoints[waypointIndex].position = scaledPoint
                    }
                    refreshFromStore()
                    return
                }

                for waypoint in transition.pathWaypoints {
                    if PathCalculations.squaredDistance(from: startScaledPoint, to: waypoint.position)
                        < CourtConstants.hitRadiusSquared
                    {
                        draggingWaypointID = waypoint.id
                        isDraggingHandle = true
                        return
                    }
                }

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
                        < CourtConstants.hitRadiusSquared
                    {
                        let waypoint = PathWaypoint(position: midpoint, isSmooth: true)
                        store.mutateAthleteTransition(
                            from: startFormationID,
                            to: endFormationID,
                            athleteID: selectedAthleteID
                        ) { transition in
                            let insertIndex = min(segmentIndex, transition.pathWaypoints.count)
                            transition.pathWaypoints.insert(waypoint, at: insertIndex)
                            transition.pathControlPoint = nil
                        }
                        draggingWaypointID = waypoint.id
                        isDraggingHandle = true
                        refreshFromStore()
                        return
                    }
                }
            } else {
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

                if isDraggingHandle
                    || PathCalculations.squaredDistance(from: startScaledPoint, to: midpoint)
                        < CourtConstants.hitRadiusSquared
                {
                    isDraggingHandle = true
                    let newControlPoint = CGPoint(
                        x: 2 * scaledPoint.x - 0.5 * startAthlete.position.x - 0.5 * endAthlete.position.x,
                        y: 2 * scaledPoint.y - 0.5 * startAthlete.position.y - 0.5 * endAthlete.position.y
                    )
                    store.mutateAthleteTransition(
                        from: startFormationID,
                        to: endFormationID,
                        athleteID: selectedAthleteID
                    ) { transition in
                        transition.pathControlPoint = newControlPoint
                        transition.pathWaypoints = []
                    }
                    refreshFromStore()
                    return
                }
            }
        }

        if let athlete = player.currentAthletes.first(where: {
            PathCalculations.squaredDistance(from: startScaledPoint, to: $0.position) < CourtConstants.hitRadiusSquared
        }) {
            selectedAthleteID = athlete.id
        } else if !isDraggingHandle {
            selectedAthleteID = nil
        }
    }

    private func handlePathGestureEnded() {
        isDraggingHandle = false
        draggingWaypointID = nil
    }

    private func waypointDoubleTapGesture(cellSize: CGFloat, offset: CGPoint) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                guard interactionMode == .editPath else { return }
                guard
                    let selectedAthleteID,
                    let selectedAthlete = player.currentAthletes.first(where: { $0.id == selectedAthleteID })
                else { return }

                let scaledPoint = CGPoint(
                    x: (value.location.x - offset.x) / cellSize,
                    y: (value.location.y - offset.y) / cellSize
                )

                guard
                    PathCalculations.squaredDistance(from: scaledPoint, to: selectedAthlete.position)
                        < CourtConstants.hitRadiusSquared
                else { return }

                addWaypoint()
            }
    }

    private func editableAthlete(at point: CGPoint) -> RenderedAthlete? {
        editableAthletes.first(where: {
            PathCalculations.squaredDistance(from: point, to: $0.position) < CourtConstants.hitRadiusSquared
        })
    }

    private func clearPath() {
        guard let selectedAthleteID else { return }
        store.mutateAthleteTransition(from: startFormationID, to: endFormationID, athleteID: selectedAthleteID) { transition in
            transition.pathControlPoint = nil
            transition.pathWaypoints = []
        }
        refreshFromStore()
    }

    private func ensureCurve() {
        guard let selectedAthleteID, let startAthlete = selectedStartAthlete, let endAthlete = selectedEndAthlete else {
            return
        }

        store.mutateAthleteTransition(from: startFormationID, to: endFormationID, athleteID: selectedAthleteID) { transition in
            guard transition.pathControlPoint == nil && transition.pathWaypoints.isEmpty else { return }
            let midpoint = CGPoint(
                x: (startAthlete.position.x + endAthlete.position.x) / 2,
                y: (startAthlete.position.y + endAthlete.position.y) / 2
            )
            transition.pathControlPoint = CGPoint(x: midpoint.x, y: midpoint.y - 6)
        }
        refreshFromStore()
    }

    private func addWaypoint() {
        guard let selectedAthleteID, let startAthlete = selectedStartAthlete, let endAthlete = selectedEndAthlete else {
            return
        }

        store.mutateAthleteTransition(from: startFormationID, to: endFormationID, athleteID: selectedAthleteID) { transition in
            if transition.pathWaypoints.isEmpty {
                let point = transition.pathControlPoint
                    ?? CGPoint(
                        x: (startAthlete.position.x + endAthlete.position.x) / 2,
                        y: (startAthlete.position.y + endAthlete.position.y) / 2
                    )
                transition.pathWaypoints = [PathWaypoint(position: point, isSmooth: true)]
                transition.pathControlPoint = nil
            } else {
                let lastNode = transition.pathWaypoints.last?.position ?? startAthlete.position
                let point = CGPoint(
                    x: (lastNode.x + endAthlete.position.x) / 2,
                    y: (lastNode.y + endAthlete.position.y) / 2
                )
                transition.pathWaypoints.append(PathWaypoint(position: point, isSmooth: true))
            }
        }
        refreshFromStore()
    }

    private func resetAllPaths() {
        clearCanvasInteractionState()

        store.mutateTransitionSpec(from: startFormationID, to: endFormationID) { spec in
            for index in spec.athleteTransitions.indices {
                spec.athleteTransitions[index].pathControlPoint = nil
                spec.athleteTransitions[index].pathWaypoints = []
            }
        }
        refreshFromStore()
    }

    private func resetPreviewInteractionMode() {
        interactionMode = .editSpots
        selectedAthleteID = nil
        clearCanvasInteractionState()
    }

    private func clearCanvasInteractionState() {
        isDraggingHandle = false
        draggingWaypointID = nil
        editableDragStartPosition = nil
        activeAlignmentGuides = []
    }

    private func speedSelection(for value: CGFloat) -> CGFloat {
        [CGFloat(0.5), 1.0, 1.5, 2.0]
            .min(by: { abs($0 - value) < abs($1 - value) }) ?? 1.0
    }

    private func refreshFromStore() {
        player.refresh(
            startAthletes: store.renderedAthletes(for: startFormationID),
            endAthletes: store.renderedAthletes(for: endFormationID),
            transitionSpec: store.transitionSpec(for: startFormationID, to: endFormationID)
        )
    }

    private func clampedCoordinate(_ value: CGFloat, upperBound: CGFloat) -> CGFloat {
        max(0, min(upperBound, round(value)))
    }

    private func banner(text: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
            Text(text)
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(color.opacity(0.15))
        .foregroundColor(color)
        .clipShape(Capsule())
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @StateObject private var store = RoutineStore()
        @State private var previewReferenceMode: PreviewReferenceMode = .intoSelected

        var body: some View {
            Group {
                if store.routine.formations.count > 1 {
                    let selectedIndex = 1
                    let selectedFormation = store.routine.formations[selectedIndex]
                    let pair = previewReferenceMode.transitionPair(
                        in: store.routine.formations,
                        selectedIndex: selectedIndex
                    )!
                    let player = TransitionPlayer(
                        startAthletes: store.renderedAthletes(for: pair.start.id),
                        endAthletes: store.renderedAthletes(for: pair.end.id),
                        transitionSpec: store.transitionSpec(for: pair.start.id, to: pair.end.id)
                    )

                    HStack(spacing: 0) {
                        TransitionTransportSidebarView(
                            player: player,
                            startFormationName: pair.start.name,
                            endFormationName: pair.end.name
                        )

                        Divider()

                        TransitionPlayerView(
                            store: store,
                            player: player,
                            startFormationID: pair.start.id,
                            endFormationID: pair.end.id,
                            selectedFormationName: selectedFormation.name,
                            previewReferenceMode: $previewReferenceMode,
                            editableEndpoint: previewReferenceMode.editableEndpoint,
                            onSelectPreviousFormation: {},
                            onSelectNextFormation: {},
                            canSelectPreviousFormation: true,
                            canSelectNextFormation: true
                        )
                    }
                } else {
                    Text("Preparing preview...")
                        .onAppear {
                            let startID = store.routine.formations[0].id
                            if store.routine.roster.isEmpty {
                                store.applyBowlingPinTemplate(to: startID)
                            }
                            _ = store.duplicateFormation(after: startID)
                        }
                }
            }
        }
    }

    return PreviewWrapper()
}
