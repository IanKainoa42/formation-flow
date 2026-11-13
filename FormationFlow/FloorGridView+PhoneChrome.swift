extension FloorGridView {
    @ViewBuilder
    private var phoneToolbarMenuContent: some View {
        if hasTransition {
            Picker("Path Preview", selection: Binding(
                get: { transitionPreviewMode },
                set: { transitionPreviewModeRaw = $0.rawValue }
            )) {
                ForEach(TransitionPreviewMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.systemImage).tag(mode)
                }
            }
            Divider()
        }

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
            Label(entitlementManager.isPro ? "Export PDF" : "Export PDF (Pro)",
                  systemImage: entitlementManager.isPro ? "doc.text" : "lock.fill")
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

    private var phoneLandscapeToolsButton: some View {
        Menu {
            phoneToolbarMenuContent
        } label: {
            Image(systemName: "ellipsis")
                .font(.caption.weight(.bold))
                .frame(width: 36, height: 36)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
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
        .accessibilityValue(formation?.notes.isEmpty == false ? "Has notes" : "")
    }

    private var phonePortraitTopChrome: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !phonePortraitHasSelection {
                phoneTopOverlay
                formationContextBadge
            }
            phoneStatusBanners
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private var phonePortraitBottomChrome: some View {
        VStack(spacing: 8) {
            if selectedRosterAthlete != nil || selectedAthleteIDs.count > 1 {
                phoneSelectionOverlay
            }
            if let player, let startFormationName, let endFormationName {
                if phonePortraitHasSelection {
                    ThinTransitionTransportBar(
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
                        showsTransitionTitle: false,
                        hidesDisabledActions: true,
                        phoneCompactLayout: true
                    )
                } else {
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
                        isLastFormation: isLastFormation,
                        onAdjustCounts: { setTransitionCounts($0) },
                        countsLocked: !entitlementManager.isPro,
                        onLockedCounts: { showingUpgradeSheet = true },
                        showsTransitionTitle: true,
                        hidesDisabledActions: true,
                        usesStackedHeader: true,
                        phoneCompactTransport: true
                    )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var phoneLandscapeStatusInset: some View {
        if isSwapMode, let athlete = swapSourceRosterAthlete {
            swapBanner(athleteLabel: athlete.label)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        } else if let pathSketchStatusText {
            banner(text: pathSketchStatusText, color: .coral)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var phoneStatusBanners: some View {
        if isSwapMode, let athlete = swapSourceRosterAthlete {
            swapBanner(athleteLabel: athlete.label)
        } else if let compactBannerConfiguration {
            banner(text: compactBannerConfiguration.text, color: compactBannerConfiguration.color)
        }
        if let pathSketchStatusText {
            banner(text: pathSketchStatusText, color: .coral)
        }
    }

    /// Side rail for phone landscape. Safe-area insets keep it off the notch
    /// and the home indicator in either rotation, so it does not need to swap sides.
    private var phoneLandscapeHasSelection: Bool {
        selectedRosterAthlete != nil || selectedAthleteIDs.count > 1
    }

    private var phoneLandscapeRail: some View {
        Group {
            if let player, let startFormationName, let endFormationName {
                VStack(alignment: .leading, spacing: 0) {
                    phoneLandscapePlaybackRail(
                        player: player,
                        startFormationName: startFormationName,
                        endFormationName: endFormationName,
                        usesCompactLandscapeHeader: phoneLandscapeHasSelection,
                        section: .header
                    )
                    .fixedSize(horizontal: false, vertical: true)

                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 6) {
                            if phoneLandscapeHasSelection {
                                phoneLandscapeSelectionRailSection
                                phoneLandscapePlaybackRail(
                                    player: player,
                                    startFormationName: startFormationName,
                                    endFormationName: endFormationName,
                                    pinsPlaybackMetadataInTransport: false,
                                    pinsSwapPathInTransport: false,
                                    section: .scrollSupplement
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.bottom, 6)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(
                        minHeight: phoneLandscapeHasSelection ? 90 : 0,
                        maxHeight: .infinity
                    )
                    .layoutPriority(phoneLandscapeHasSelection ? 1 : 0)

                    phoneLandscapePlaybackRail(
                        player: player,
                        startFormationName: startFormationName,
                        endFormationName: endFormationName,
                        pinsPlaybackMetadataInTransport: !phoneLandscapeHasSelection,
                        pinsSwapPathInTransport: !phoneLandscapeHasSelection,
                        section: .transport
                    )
                    .fixedSize(horizontal: false, vertical: true)
                }
                .formationGlassPanel(cornerRadius: 22, shadowRadius: 12)
            } else {
                phoneLandscapeIdleRail
            }
        }
        .padding(.leading, 8)
        .padding(.vertical, 8)
        .frame(width: 184, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func phoneLandscapePlaybackRail(
        player: TransitionPlayer,
        startFormationName: String,
        endFormationName: String,
        pinsPlaybackMetadataInTransport: Bool = true,
        pinsSwapPathInTransport: Bool = true,
        usesCompactLandscapeHeader: Bool = false,
        section: CompactPlaybackRailSection
    ) -> some View {
        CompactTransitionPlaybackRailView(
            player: player,
            startFormationName: startFormationName,
            endFormationName: endFormationName,
            availableWidth: 176,
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
            isLastFormation: isLastFormation,
            onBack: onBack,
            onAdjustCounts: { setTransitionCounts($0) },
            countsLocked: !entitlementManager.isPro,
            onLockedCounts: { showingUpgradeSheet = true },
            directionLabel: hasTransition ? (endFormationID == formationID ? "Into" : "Out of") : nil,
            canToggleDirection: !isFirstFormation && !isLastFormation,
            onToggleDirection: onToggleTransitionDirection,
            phoneCompact: true,
            hidesDisabledActions: true,
            scrollsInternally: false,
            pinsPlaybackMetadataInTransport: pinsPlaybackMetadataInTransport,
            pinsSwapPathInTransport: pinsSwapPathInTransport,
            usesCompactLandscapeHeader: usesCompactLandscapeHeader,
            section: section,
            tools: phoneLandscapeToolsButton
        )
    }

    @ViewBuilder
    private var phoneLandscapeSelectionRailSection: some View {
        let chipColumns = [
            GridItem(.flexible(minimum: 72), spacing: 6),
            GridItem(.flexible(minimum: 72), spacing: 6),
        ]

        VStack(alignment: .leading, spacing: 6) {
            if selectedAthleteIDs.count > 1 {
                Text("\(selectedAthleteIDs.count) selected")
                    .font(.caption.weight(.bold))
                LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 6) {
                    if hasTransition {
                        landscapeRailChipButton(title: "Waypoint", action: { addWaypoint() })
                        landscapeRailChipButton(
                            title: isExplicitPathDrawMode ? "Cancel" : "Draw",
                            prominent: !isExplicitPathDrawMode,
                            action: toggleExplicitPathDrawMode
                        )
                        landscapeRailChipButton(
                            title: selectionIsTransitionGroup ? "Ungroup" : "Group",
                            disabled: !selectionIsTransitionGroup && !canCreateSelectedTransitionGroup,
                            action: {
                                if selectionIsTransitionGroup {
                                    ungroupSelectedTransitionGroup()
                                } else {
                                    createSelectedTransitionGroup()
                                }
                            }
                        )
                    }
                    landscapeRailChipButton(title: "Clear", action: { selectedAthleteIDs = [] })
                }
            } else if let selectedRosterAthlete {
                Text(selectedRosterAthlete.label)
                    .font(.caption.weight(.bold))
                LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 6) {
                    if hasTransition {
                        landscapeRailChipButton(title: "Path") { showingInspectorSheet = true }
                        landscapeRailChipButton(
                            title: isExplicitPathDrawMode ? "Cancel" : "Draw",
                            prominent: !isExplicitPathDrawMode,
                            disabled: !isExplicitPathDrawMode && !canBeginExplicitPathDraw,
                            action: toggleExplicitPathDrawMode
                        )
                    }
                    landscapeRailChipButton(title: "Clear", action: { selectedAthleteIDs = [] })
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .formationGlassPanel(cornerRadius: 14, shadowRadius: 6)
    }

    @ViewBuilder
    private func landscapeRailChipButton(
        title: String,
        prominent: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let label = Text(title)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)

        if prominent {
            Button(action: action, label: { label })
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(disabled)
        } else {
            Button(action: action, label: { label })
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(disabled)
        }
    }

    private var phoneLandscapeIdleRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.caption.weight(.bold))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back to formations")
                }
                Spacer(minLength: 0)
                phoneLandscapeToolsButton
            }
            if !renderedAthletes.isEmpty {
                HStack(spacing: 6) {
                    Circle()
                        .fill(currentFormationColor)
                        .frame(width: 7, height: 7)
                    Text(formationContextLabel)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                }
                Button(action: addAthlete) {
                    Label("Add", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 176, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .formationGlassPanel(cornerRadius: 22, shadowRadius: 12)
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
            } else {
                Button(action: mirrorFormation) {
                    Label("Mirror Formation", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right.fill")
                }
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

            Button(action: { showingRosterSheet = true }) {
                Label("Roster", systemImage: "list.bullet.rectangle")
            }

            Button(action: { showingNotesSheet = true }) {
                Label("Notes", systemImage: "note.text")
            }

            Button(action: { showingMoreAppsSheet = true }) {
                Label("More Coaching Tools", systemImage: "square.grid.2x2")
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
            VStack(alignment: .leading, spacing: 8) {
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

                ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                if hasTransition {
                    Button("Path") {
                        showingInspectorSheet = true
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)

                    Button(isExplicitPathDrawMode ? "Cancel" : (entitlementManager.isPro ? "Draw" : "Draw (Pro)")) {
                        toggleExplicitPathDrawMode()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isExplicitPathDrawMode && !canBeginExplicitPathDraw)
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
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .formationGlassPanel(cornerRadius: 18, shadowRadius: 10)
        } else if selectedAthleteIDs.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(selectedAthleteIDs.count) athletes selected")
                        .font(.headline)
                    Text("Drag to move together. Pinch to adjust spacing, or twist to rotate.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 8) {
                if hasTransition {
                    Button {
                        addWaypoint()
                    } label: {
                        Label(
                            entitlementManager.isPro
                                ? (isPhoneLayout ? "Waypoint" : "Add Waypoint")
                                : "Waypoint (Pro)",
                            systemImage: entitlementManager.isPro ? "plus.circle" : "lock.fill"
                        )
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .accessibilityHint(entitlementManager.isPro ? "Add a waypoint to every selected path" : "Upgrade to Pro to add waypoints")

                    Button(isExplicitPathDrawMode ? "Cancel Draw" : explicitPathDrawButtonTitle) {
                        toggleExplicitPathDrawMode()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isExplicitPathDrawMode && !canBeginExplicitPathDraw)
                    .frame(minHeight: 44)

                    Button(selectionIsTransitionGroup ? "Ungroup" : (isPhoneLayout ? "Group" : "Create Stunt Group")) {
                        if selectionIsTransitionGroup {
                            ungroupSelectedTransitionGroup()
                        } else {
                            createSelectedTransitionGroup()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!selectionIsTransitionGroup && !canCreateSelectedTransitionGroup)
                    .frame(minHeight: 44)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                }

                Button("Clear") {
                    selectedAthleteIDs = []
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .formationGlassPanel(cornerRadius: 18, shadowRadius: 10)
        }
    }
}
