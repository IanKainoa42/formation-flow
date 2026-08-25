import SwiftUI

// MARK: - PDF Export Sheet View

struct PDFExportSheetView: View {
    @ObservedObject var store: RoutineStore
    let currentFormationID: UUID?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var entitlementManager: EntitlementManager

    @State private var config = PDFExportConfiguration()
    @State private var previewIndex: Int = 0
    @State private var isGeneratingPDF: Bool = false
    @State private var sharePayload: DocumentSharePayload?
    @State private var showingUpgradeSheet: Bool = false
    @State private var showingErrorAlert: Bool = false
    @State private var errorMessage: String = ""

    init(store: RoutineStore, currentFormationID: UUID? = nil) {
        self.store = store
        self.currentFormationID = currentFormationID
        let initialIDs = Set(store.routine.formations.map(\.id))
        _config = State(initialValue: PDFExportConfiguration(
            scope: .all,
            selectedFormationIDs: initialIDs
        ))
    }

    private var targetFormations: [Formation] {
        config.resolvedFormations(for: store.routine, currentFormationID: currentFormationID)
    }

    private var isCoverPagePreview: Bool {
        config.includeCoverPage && targetFormations.count > 1 && previewIndex == 0
    }

    private var currentPreviewFormation: Formation? {
        let formationOffset = (config.includeCoverPage && targetFormations.count > 1) ? (previewIndex - 1) : previewIndex
        guard formationOffset >= 0, formationOffset < targetFormations.count else { return nil }
        return targetFormations[formationOffset]
    }

    private var totalPreviewPages: Int {
        targetFormations.count + ((config.includeCoverPage && targetFormations.count > 1) ? 1 : 0)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let isWideLayout = geometry.size.width >= 700

                if isWideLayout {
                    HStack(spacing: 0) {
                        // Left: Live Document Preview
                        livePreviewPane
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(uiColor: .systemGroupedBackground))

                        Divider()

                        // Right: Configuration Inspector Form
                        configurationForm
                            .frame(width: 360)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                    }
                } else {
                    VStack(spacing: 0) {
                        // Top: Live Document Preview
                        livePreviewPane
                            .frame(height: 280)
                            .background(Color(uiColor: .systemGroupedBackground))

                        Divider()

                        // Bottom: Configuration Form
                        configurationForm
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .navigationTitle("Export Playbook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        exportPDF()
                    } label: {
                        if isGeneratingPDF {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Export PDF", systemImage: "square.and.arrow.up")
                                .font(.body.weight(.semibold))
                        }
                    }
                    .disabled(targetFormations.isEmpty || isGeneratingPDF)
                }
            }
            .sheet(item: $sharePayload) { payload in
                ShareSheetView(items: [payload.url]) { completed, _ in
                    if completed {
                        dismiss()
                    }
                    sharePayload = nil
                }
            }
            .sheet(isPresented: $showingUpgradeSheet) {
                ProUpgradeSheet()
                    .environmentObject(entitlementManager)
            }
            .alert("Export Error", isPresented: $showingErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .onChange(of: config.scope) { _, _ in
                clampPreviewIndex()
            }
            .onChange(of: config.selectedFormationIDs) { _, _ in
                clampPreviewIndex()
            }
            .onChange(of: config.includeCoverPage) { _, _ in
                clampPreviewIndex()
            }
        }
    }

    // MARK: - Live Preview Pane

    private var livePreviewPane: some View {
        VStack(spacing: 12) {
            if targetFormations.isEmpty {
                ContentUnavailableView(
                    "No Formations Selected",
                    systemImage: "square.dashed",
                    description: Text("Select at least one formation in the configuration options.")
                )
            } else {
                // Page Carousel View
                GeometryReader { previewGeom in
                    let availableWidth = previewGeom.size.width - 24
                    let availableHeight = previewGeom.size.height - 16
                    let pageAspect: CGFloat = 792.0 / 612.0

                    let fitWidth = min(availableWidth, availableHeight * pageAspect)
                    let fitHeight = fitWidth / pageAspect
                    let scale = fitWidth / 792.0

                    ZStack {
                        Group {
                            if isCoverPagePreview {
                                PDFCoverPageView(
                                    routine: store.routine,
                                    targetFormations: targetFormations,
                                    config: config,
                                    pageNumber: 1,
                                    totalPages: totalPreviewPages
                                )
                            } else if let formation = currentPreviewFormation {
                                let formationIndex = store.formationIndex(id: formation.id) ?? 0
                                PDFFormationPageView(
                                    formation: formation,
                                    formationIndex: formationIndex,
                                    store: store,
                                    config: config,
                                    pageNumber: previewIndex + 1,
                                    totalPages: totalPreviewPages
                                )
                            }
                        }
                        .frame(width: 792, height: 612)
                        .scaleEffect(scale)
                        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                    }
                    .frame(width: previewGeom.size.width, height: previewGeom.size.height, alignment: .center)
                }

                // Page Navigation Bar
                HStack(spacing: 16) {
                    Button {
                        if previewIndex > 0 {
                            previewIndex -= 1
                        }
                    } label: {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.title3)
                    }
                    .disabled(previewIndex <= 0)

                    Text("Page \(previewIndex + 1) of \(totalPreviewPages)")
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundColor(.primary)

                    Button {
                        if previewIndex < totalPreviewPages - 1 {
                            previewIndex += 1
                        }
                    } label: {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.title3)
                    }
                    .disabled(previewIndex >= totalPreviewPages - 1)
                }
                .padding(.bottom, 8)
            }
        }
        .padding(.top, 12)
    }

    // MARK: - Configuration Form

    private var configurationForm: some View {
        Form {
            // Section 1: Pages & Selection
            Section(header: Text("Pages & Scope")) {
                Picker("Export Scope", selection: $config.scope) {
                    ForEach(PDFExportConfiguration.ExportScope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)

                if config.scope == .custom {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Select Formations (\(config.selectedFormationIDs.count)/\(store.routine.formations.count))")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("All") {
                                config.selectedFormationIDs = Set(store.routine.formations.map(\.id))
                            }
                            .font(.caption)
                            Button("None") {
                                config.selectedFormationIDs = []
                            }
                            .font(.caption)
                        }

                        ForEach(Array(store.routine.formations.enumerated()), id: \.element.id) { index, formation in
                            let isSelected = config.selectedFormationIDs.contains(formation.id)
                            Button {
                                if isSelected {
                                    config.selectedFormationIDs.remove(formation.id)
                                } else {
                                    config.selectedFormationIDs.insert(formation.id)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(isSelected ? .accentColor : .secondary)

                                    Circle()
                                        .fill(TransitionEndpointMarkerRenderItem.rainbowColor(forIndex: index))
                                        .frame(width: 8, height: 8)

                                    Text("\(index + 1). \(formation.name)")
                                        .font(.subheadline)
                                        .foregroundColor(.primary)

                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Toggle("Include Cover Page", isOn: $config.includeCoverPage)
                    .disabled(targetFormations.count <= 1)

                Toggle("Include Page Numbers", isOn: $config.includePageNumbers)
            }

            // Section 2: Floor Canvas Overlays
            Section(header: Text("Floor Overlays & Layers")) {
                Toggle(isOn: $config.showTransitionPaths) {
                    Label("Transition Paths", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                }

                if config.showTransitionPaths {
                    Toggle(isOn: $config.showCountTicks) {
                        Label("Count Ticks on Paths", systemImage: "figure.walk")
                    }
                }

                Toggle(isOn: $config.showGhostFormations) {
                    Label("Ghost Formations", systemImage: "square.stack.3d.up")
                }

                Toggle(isOn: $config.showStuntGroupHarnesses) {
                    Label("Stunt Group Outlines", systemImage: "person.2.fill")
                }

                Toggle(isOn: $config.showFloorGrid) {
                    Label("Floor Grid & Mat Seams", systemImage: "grid")
                }

                Toggle(isOn: $config.showCenterMark) {
                    Label("Center Floor Mark", systemImage: "plus.circle")
                }

                Toggle(isOn: $config.showSpacingAlerts) {
                    Label("Spacing & Conflict Alerts", systemImage: "exclamationmark.triangle")
                }
            }

            // Section 3: Athlete Styling
            Section(header: Text("Athlete Styling")) {
                Picker("Color Mode", selection: $config.colorMode) {
                    ForEach(PDFExportConfiguration.ColorMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                Picker("Athlete Labels", selection: $config.athleteLabelMode) {
                    ForEach(PDFExportConfiguration.AthleteLabelMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
            }

            // Section 4: Annotations & Metadata
            Section(header: Text("Notes & Metadata")) {
                Toggle("Formation Notes", isOn: $config.showNotes)
                Toggle("Role Legend", isOn: $config.showRoleLegend)
                Toggle("Count Duration Badge", isOn: $config.showCountsBadge)
            }
        }
    }

    // MARK: - Actions

    private func clampPreviewIndex() {
        let maxIndex = max(0, totalPreviewPages - 1)
        if previewIndex > maxIndex {
            previewIndex = maxIndex
        }
    }

    private func exportPDF() {
        guard !targetFormations.isEmpty else { return }

        // Pro feature gating check: PDF export is a Pro-only feature
        guard entitlementManager.isPro else {
            showingUpgradeSheet = true
            return
        }

        isGeneratingPDF = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let url = RoutinePDFExporter.generatePDF(
                with: config,
                in: store,
                currentFormationID: currentFormationID
            ) {
                isGeneratingPDF = false
                sharePayload = DocumentSharePayload(url: url)
            } else {
                isGeneratingPDF = false
                errorMessage = "Unable to generate the PDF document. Please try again."
                showingErrorAlert = true
            }
        }
    }
}
