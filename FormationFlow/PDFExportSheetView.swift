import SwiftUI

// MARK: - PDF Export Sheet View

struct PDFExportSheetView: View {
    @ObservedObject var store: RoutineStore
    let currentFormationID: UUID?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var entitlementManager: EntitlementManager

    @State private var config = PDFExportConfiguration()
    @State private var previewIndex: Int = 0
    @State private var showingCustomization = false
    @State private var isGeneratingPDF: Bool = false
    @State private var sharePayload: DocumentSharePayload?
    @State private var showingUpgradeSheet: Bool = false
    @State private var showingErrorAlert: Bool = false
    @State private var errorMessage: String = ""

    init(store: RoutineStore, currentFormationID: UUID? = nil, initialPreviewIndex: Int = 1) {
        self.store = store
        self.currentFormationID = currentFormationID
        let initialIDs = Set(store.routine.formations.map(\.id))
        _config = State(initialValue: PDFExportConfiguration(
            scope: .all,
            selectedFormationIDs: initialIDs
        ))
        _previewIndex = State(initialValue: initialPreviewIndex)
    }

    private var targetFormations: [Formation] {
        config.resolvedFormations(for: store.routine, currentFormationID: currentFormationID)
    }

    private var totalPreviewPages: Int {
        targetFormations.count + ((config.includeCoverPage && targetFormations.count > 1) ? 1 : 0)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                livePreviewPane
                HStack(spacing: 12) {
                    Button { showingCustomization = true } label: {
                        Label("Customize", systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.bordered)
                    Button { exportPDF() } label: {
                        HStack {
                            if isGeneratingPDF { ProgressView() }
                            else { Image(systemName: "square.and.arrow.up") }
                            Text(isGeneratingPDF ? "Exporting…" : "Export PDF")
                        }
                        .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(targetFormations.isEmpty || isGeneratingPDF)
                }
                .font(.subheadline.weight(.semibold))
                .padding(20)
                .background(.bar)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Playbook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingCustomization) {
                NavigationStack {
                    configurationForm
                        .navigationTitle("Customize Playbook")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showingCustomization = false }
                            }
                        }
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
            .onChange(of: config.focusedAthleteID) { _, focusedAthleteID in
                // A focused athlete export is specifically a path handoff.
                if focusedAthleteID != nil {
                    config.showTransitionPaths = true
                }
            }
        }
        .modifier(WidePresentationSizing())
    }

    // MARK: - Live Preview Pane

    private var livePreviewPane: some View {
        VStack(spacing: 12) {
            if targetFormations.isEmpty {
                ContentUnavailableView("No formations selected", systemImage: "doc",
                    description: Text("Choose formations in Customize to build your playbook."))
                    .frame(maxHeight: .infinity)
            } else {
                VStack(spacing: 4) {
                    Text(store.routine.name)
                        .font(.title2.bold())
                        .lineLimit(2)
                    Text("\(targetFormations.count) formations · \(totalPreviewPages) pages")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)

                TabView(selection: $previewIndex) {
                    ForEach(0..<totalPreviewPages, id: \.self) { index in
                        GeometryReader { geometry in
                            let scale = max(0.01, min((geometry.size.width - 32) / PDFPageLayout.width,
                                                     (geometry.size.height - 24) / PDFPageLayout.height))
                            previewPage(at: index)
                                .frame(width: PDFPageLayout.width, height: PDFPageLayout.height)
                                .environment(\.colorScheme, .light)
                                .scaleEffect(scale)
                                .frame(width: PDFPageLayout.width * scale, height: PDFPageLayout.height * scale)
                                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 24) {
                    Button { previewIndex -= 1 } label: {
                        Image(systemName: "chevron.left").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Previous page")
                    .disabled(previewIndex == 0)
                    Text("Page \(previewIndex + 1) of \(totalPreviewPages)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button { previewIndex += 1 } label: {
                        Image(systemName: "chevron.right").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Next page")
                    .disabled(previewIndex >= totalPreviewPages - 1)
                }
                .padding(.bottom, 8)
            }
        }
        .onAppear { clampPreviewIndex() }
    }

    @ViewBuilder
    private func previewPage(at index: Int) -> some View {
        let hasCover = config.includeCoverPage && targetFormations.count > 1
        if hasCover && index == 0 {
            PDFCoverPageView(routine: store.routine, targetFormations: targetFormations,
                             config: config, pageNumber: 1, totalPages: totalPreviewPages)
        } else {
            let offset = index - (hasCover ? 1 : 0)
            if targetFormations.indices.contains(offset) {
                let formation = targetFormations[offset]
                PDFFormationPageView(formation: formation,
                    formationIndex: store.formationIndex(id: formation.id) ?? 0,
                    store: store, config: config, pageNumber: index + 1, totalPages: totalPreviewPages)
            }
        }
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
                .pickerStyle(.menu)

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
                                        .foregroundColor(isSelected ? .coral : .secondary)

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
                Picker("Athlete Path", selection: $config.focusedAthleteID) {
                    Text("Entire Team").tag(UUID?.none)
                    ForEach(store.routine.roster) { athlete in
                        Text("\(athlete.label) · \(athlete.role.displayName)")
                            .tag(Optional(athlete.id))
                    }
                }

                if config.focusedAthleteID != nil {
                    Text("Keeps the full formation for context and highlights only the selected athlete's route.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle(isOn: $config.showTransitionPaths) {
                    Label("Transition Paths", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                }
                .disabled(config.focusedAthleteID != nil)

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

// MARK: - Presentation Sizing

/// A default `.sheet` on iPad is form-width (~578pt), which is below the 700pt
/// threshold the split preview/config layout needs — so the wide layout never
/// appeared on iPad. Page sizing gives the sheet the width it was designed for.
private struct WidePresentationSizing: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.presentationSizing(.page)
        } else {
            content
        }
    }
}
