import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum PDFPageLayout {
    static let width: CGFloat = 612
    static let height: CGFloat = 792
}

@MainActor
final class RoutinePDFExporter {

    /// Main entry point for configurable multi-page PDF generation.
    static func generatePDF(
        with config: PDFExportConfiguration,
        in store: RoutineStore,
        currentFormationID: UUID? = nil
    ) -> URL? {
        let routine = store.routine
        let targetFormations = config.resolvedFormations(for: routine, currentFormationID: currentFormationID)
        guard !targetFormations.isEmpty else { return nil }

        // US Letter portrait, shared by the live preview and exported document.
        let pageWidth = PDFPageLayout.width
        let pageHeight = PDFPageLayout.height
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        let safeRoutineName = routine.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .punctuationCharacters)
            .joined(separator: "_")
            .replacingOccurrences(of: " ", with: "_")
        let filename = "\(safeRoutineName.isEmpty ? "FormationFlow" : safeRoutineName)_Playbook.pdf"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        // Remove old file if it exists
        try? FileManager.default.removeItem(at: tempURL)

        var pdfBox = pageRect
        guard let pdfContext = CGContext(tempURL as CFURL, mediaBox: &pdfBox, nil) else {
            return nil
        }

        let totalPages = targetFormations.count + ((config.includeCoverPage && targetFormations.count > 1) ? 1 : 0)
        var currentPageNumber = 1

        // 1. Optional Cover Page (rendered only when exporting multi-formation playbook)
        if config.includeCoverPage && targetFormations.count > 1 {
            let coverView = PDFCoverPageView(
                routine: routine,
                targetFormations: targetFormations,
                config: config,
                pageNumber: currentPageNumber,
                totalPages: totalPages
            )

            let renderer = ImageRenderer(content: coverView.frame(width: pageWidth, height: pageHeight))
            renderer.proposedSize = ProposedViewSize(width: pageWidth, height: pageHeight)

            pdfContext.beginPDFPage(nil)
            renderer.render { size, context in
                context(pdfContext)
            }
            pdfContext.endPDFPage()

            currentPageNumber += 1
        }

        // 2. Formation Pages
        for formation in targetFormations {
            let formationIndex = store.formationIndex(id: formation.id) ?? 0

            let pageView = PDFFormationPageView(
                formation: formation,
                formationIndex: formationIndex,
                store: store,
                config: config,
                pageNumber: currentPageNumber,
                totalPages: totalPages
            )

            let renderer = ImageRenderer(content: pageView.frame(width: pageWidth, height: pageHeight))
            renderer.proposedSize = ProposedViewSize(width: pageWidth, height: pageHeight)

            pdfContext.beginPDFPage(nil)
            renderer.render { size, context in
                context(pdfContext)
            }
            pdfContext.endPDFPage()

            currentPageNumber += 1
        }

        pdfContext.closePDF()
        return tempURL
    }

    /// Single-formation fallback for backward compatibility.
    static func generatePDF(for formationID: UUID, in store: RoutineStore) -> URL? {
        let config = PDFExportConfiguration(scope: .currentOnly)
        return generatePDF(with: config, in: store, currentFormationID: formationID)
    }
}

// MARK: - PDF Formation Page View

struct PDFFormationPageView: View {
    let formation: Formation
    let formationIndex: Int
    let store: RoutineStore
    let config: PDFExportConfiguration
    let pageNumber: Int
    let totalPages: Int

    init(
        formation: Formation,
        formationIndex: Int,
        store: RoutineStore,
        config: PDFExportConfiguration,
        pageNumber: Int = 1,
        totalPages: Int = 1
    ) {
        self.formation = formation
        self.formationIndex = formationIndex
        self.store = store
        self.config = config
        self.pageNumber = pageNumber
        self.totalPages = totalPages
    }

    private var previousFormation: Formation? {
        guard formationIndex > 0, formationIndex - 1 < store.routine.formations.count else { return nil }
        return store.routine.formations[formationIndex - 1]
    }

    private var transitionPaths: [TransitionPathRenderItem] {
        guard config.showTransitionPaths, let previousFormation else { return [] }
        let spec = store.transitionSpec(for: previousFormation.id, to: formation.id)
        let prevAthletes = store.renderedAthletes(for: previousFormation)
        let currentAthletes = store.renderedAthletes(for: formation)
        let currentLookup = Dictionary(uniqueKeysWithValues: currentAthletes.map { ($0.id, $0) })

        return prevAthletes.compactMap { start in
            guard let end = currentLookup[start.id] else { return nil }
            let transition = spec.athleteTransitions.first { $0.athleteID == start.id }
            return TransitionPathRenderItem(
                athleteID: start.id,
                startPosition: start.position,
                endPosition: end.position,
                controlPoint: transition?.pathControlPoint,
                waypoints: transition?.pathWaypoints ?? [],
                moveDelay: transition?.moveDelay ?? 0
            )
        }
    }

    private var ghostAthletes: [RenderedAthlete] {
        guard config.showGhostFormations, let previousFormation else { return [] }
        return store.renderedAthletes(for: previousFormation)
    }

    private var ghostColor: Color {
        guard formationIndex > 0 else { return .secondary }
        return TransitionEndpointMarkerRenderItem.rainbowColor(forIndex: formationIndex - 1)
    }

    private var stuntGroupIDSets: [Set<UUID>] {
        guard config.showStuntGroupHarnesses, let previousFormation else { return [] }
        let spec = store.transitionSpec(for: previousFormation.id, to: formation.id)
        return spec.stuntGroups.map(\.athleteIDSet)
    }

    private var processedAthletes: [RenderedAthlete] {
        let baseAthletes = store.renderedAthletes(for: formation.id)
        return baseAthletes.map { athlete in
            let label: String
            switch config.athleteLabelMode {
            case .nameOrInitials:
                label = athlete.label
            case .role:
                label = String(athlete.role.displayName.prefix(2)).uppercased()
            case .coordinates:
                label = "\(Int(round(athlete.position.x))),\(Int(round(athlete.position.y)))"
            }
            return RenderedAthlete(
                id: athlete.id,
                label: label,
                role: athlete.role,
                position: athlete.position
            )
        }
    }

    private var transitionDurationCounts: Int {
        guard let previousFormation else { return 0 }
        let spec = store.transitionSpec(for: previousFormation.id, to: formation.id)
        return Int(spec.duration.rounded())
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header Bar
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.routine.name.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        Text("\(formationIndex + 1). \(formation.name)")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                            .foregroundColor(.black)

                        if config.showCountsBadge && formationIndex > 0 {
                            Text("\(transitionDurationCounts) Counts")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.accentColor, in: Capsule())
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text("FormationFlow")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                    if config.includePageNumbers {
                        Text("Page \(pageNumber) of \(totalPages)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 24)

            PDFCourtView(athletes: processedAthletes, paths: transitionPaths,
                         ghosts: ghostAthletes, groups: stuntGroupIDSets,
                         config: config, formationIndex: formationIndex,
                         counts: transitionDurationCounts)
                .frame(width: 552, height: 470)
                .padding(.vertical, 12)

            // Footer: Notes & Legend
            VStack(alignment: .leading, spacing: 16) {
                if config.showNotes && !formation.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Notes & Coaching Cues")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        Text(formation.notes)
                            .font(.system(size: 9.5, weight: .regular))
                            .foregroundColor(.secondary)
                            .lineLimit(5)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if config.showRoleLegend {
                    PDFLegendView(colorMode: config.colorMode)
                }
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 20)

            Spacer(minLength: 0)
        }
        .frame(width: PDFPageLayout.width, height: PDFPageLayout.height)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}

// MARK: - PDF Cover Page View

struct PDFCoverPageView: View {
    let routine: Routine
    let targetFormations: [Formation]
    let config: PDFExportConfiguration
    let pageNumber: Int
    let totalPages: Int

    init(
        routine: Routine,
        targetFormations: [Formation],
        config: PDFExportConfiguration,
        pageNumber: Int = 1,
        totalPages: Int = 1
    ) {
        self.routine = routine
        self.targetFormations = targetFormations
        self.config = config
        self.pageNumber = pageNumber
        self.totalPages = totalPages
    }

    private var totalAthletes: Int {
        routine.roster.count
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: Date())
    }

    var body: some View {
        VStack(spacing: 24) {
            // Header Section
            VStack(spacing: 8) {
                Text("FORMATION PLAYBOOK")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentColor)
                    .tracking(2)

                Text(routine.name)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 32)
                    .foregroundColor(.black)

                Text("Generated on \(formattedDate) • FormationFlow")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 44)

            Divider()
                .padding(.horizontal, 48)

            // Summary Stats Grid
            HStack(spacing: 12) {
                SummaryCard(title: "Formations", value: "\(targetFormations.count)", icon: "square.grid.2x2")
                SummaryCard(title: "Roster Size", value: "\(totalAthletes) Athletes", icon: "person.3")
                SummaryCard(title: "Court Size", value: "\(Int(CourtConstants.width))′ × \(Int(CourtConstants.height))′", icon: "grid")
            }
            .padding(.vertical, 8)

            // Formation Order List & Roster Summary
            HStack(alignment: .top, spacing: 32) {
                // Left: Formations Sequence
                VStack(alignment: .leading, spacing: 8) {
                    Text("FORMATION SEQUENCE")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(targetFormations.prefix(8).enumerated()), id: \.element.id) { index, formation in
                            HStack(spacing: 8) {
                                Text("\(index + 1)")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .frame(width: 18, height: 18)
                                    .background(TransitionEndpointMarkerRenderItem.rainbowColor(forIndex: index), in: Circle())

                                Text(formation.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.black)
                                Spacer()
                            }
                        }
                        if targetFormations.count > 8 {
                            Text("+ \(targetFormations.count - 8) more formations...")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundColor(.secondary)
                                .padding(.leading, 26)
                        }
                    }
                    .padding(12)
                    .background(Color(white: 0.96), in: RoundedRectangle(cornerRadius: 10))
                }
                .frame(maxWidth: .infinity)

                // Right: Team Roster Summary
                VStack(alignment: .leading, spacing: 8) {
                    Text(routine.roster.count > 16 ? "ROSTER PREVIEW" : "TEAM ROSTER")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)

                    if routine.roster.isEmpty {
                        Text("No roster athletes configured.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(12)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                            ForEach(routine.roster.prefix(16)) { athlete in
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(athlete.role.color)
                                        .frame(width: 8, height: 8)
                                    Text(athlete.label)
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.black)
                                    Text(athlete.role.displayName)
                                        .font(.system(size: 9, weight: .regular))
                                        .foregroundColor(.secondary)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                        .padding(12)
                        .background(Color(white: 0.96), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 48)

            Spacer()

            if config.includePageNumbers {
                Text("Page \(pageNumber) of \(totalPages)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 24)
            }
        }
        .frame(width: PDFPageLayout.width, height: PDFPageLayout.height)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}

private struct SummaryCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.accentColor)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.black)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 110)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(white: 0.96), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - PDF Legend View

struct PDFLegendView: View {
    var colorMode: PDFExportConfiguration.ColorMode = .roleColors

    init(colorMode: PDFExportConfiguration.ColorMode = .roleColors) {
        self.colorMode = colorMode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Role Legend")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.black)
            HStack(spacing: 12) {
                PDFLegendItem(role: .flyer, colorMode: colorMode)
                PDFLegendItem(role: .base, colorMode: colorMode)
                PDFLegendItem(role: .backspot, colorMode: colorMode)
                PDFLegendItem(role: .spotter, colorMode: colorMode)
                PDFLegendItem(role: .tumbler, colorMode: colorMode)
            }
        }
    }
}

private struct PDFLegendItem: View {
    let role: AthleteRole
    let colorMode: PDFExportConfiguration.ColorMode

    var body: some View {
        HStack(spacing: 4) {
            AthleteRoleMarkerShape(role: role)
                .fill(colorMode == .roleColors ? role.color : .black)
                .frame(width: 10, height: 10)
            Text(role.displayName)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundColor(.black)
        }
    }
}

// MARK: - Print Floor

/// Static document rendering: no editor chrome, animation, or dark stage.
private struct PDFCourtView: View {
    let athletes: [RenderedAthlete]
    let paths: [TransitionPathRenderItem]
    let ghosts: [RenderedAthlete]
    let groups: [Set<UUID>]
    let config: PDFExportConfiguration
    let formationIndex: Int
    let counts: Int

    private func ink(for athlete: RenderedAthlete) -> Color {
        switch config.colorMode {
        case .roleColors: return athlete.role.color
        case .formationAccent: return TransitionEndpointMarkerRenderItem.rainbowColor(forIndex: formationIndex)
        case .monochrome: return .black
        }
    }

    private func routePoint(_ item: TransitionPathRenderItem, progress: CGFloat) -> CGPoint {
        if !item.waypoints.isEmpty {
            let lengths = PathCalculations.segmentLengths(item.nodes)
            return PathCalculations.interpolateWaypointPath(nodes: item.nodes, lengths: lengths,
                totalLength: lengths.reduce(0, +), waypoints: item.waypoints, progress: progress)
        }
        if let control = item.controlPoint {
            return PathCalculations.quadraticBezierPoint(from: item.startPosition, control: control,
                                                         to: item.endPosition, t: progress)
        }
        return CGPoint(x: item.startPosition.x + (item.endPosition.x - item.startPosition.x) * progress,
                       y: item.startPosition.y + (item.endPosition.y - item.startPosition.y) * progress)
    }

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 18
            let scale = min((size.width - inset * 2) / CourtConstants.width,
                            (size.height - 36) / CourtConstants.height)
            let floor = CGRect(x: (size.width - CourtConstants.width * scale) / 2, y: 12,
                               width: CourtConstants.width * scale, height: CourtConstants.height * scale)
            func point(_ p: CGPoint) -> CGPoint {
                CGPoint(x: floor.minX + p.x * scale, y: floor.minY + p.y * scale)
            }
            context.fill(Path(floor), with: .color(Color(white: 0.98)))
            if config.showFloorGrid {
                var grid = Path()
                for x in stride(from: CGFloat(0), through: CourtConstants.width, by: 6) {
                    grid.move(to: point(CGPoint(x: x, y: 0)))
                    grid.addLine(to: point(CGPoint(x: x, y: CourtConstants.height)))
                }
                for y in stride(from: CGFloat(0), through: CourtConstants.height, by: 6) {
                    grid.move(to: point(CGPoint(x: 0, y: y)))
                    grid.addLine(to: point(CGPoint(x: CourtConstants.width, y: y)))
                }
                context.stroke(grid, with: .color(.black.opacity(0.12)), lineWidth: 0.6)
            }
            context.stroke(Path(floor), with: .color(.black.opacity(0.3)), lineWidth: 1)
            if config.showCenterMark {
                let c = point(CGPoint(x: CourtConstants.width / 2, y: CourtConstants.height / 2))
                var mark = Path()
                mark.move(to: CGPoint(x: c.x - 5, y: c.y)); mark.addLine(to: CGPoint(x: c.x + 5, y: c.y))
                mark.move(to: CGPoint(x: c.x, y: c.y - 5)); mark.addLine(to: CGPoint(x: c.x, y: c.y + 5))
                context.stroke(mark, with: .color(.black.opacity(0.35)), lineWidth: 1)
            }
            for group in groups {
                let members = athletes.filter { group.contains($0.id) }.map { point($0.position) }
                if let first = members.first {
                    let bounds = members.reduce(CGRect(origin: first, size: .zero)) { rect, p in
                        rect.union(CGRect(x: p.x, y: p.y, width: 0.01, height: 0.01))
                    }.insetBy(dx: -17, dy: -17)
                    context.stroke(Path(roundedRect: bounds, cornerRadius: 12),
                                   with: .color(.black.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            for ghost in ghosts {
                let c = point(ghost.position)
                context.stroke(Path(ellipseIn: CGRect(x: c.x - 10, y: c.y - 10, width: 20, height: 20)),
                               with: .color(.black.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            }
            for item in paths {
                let samples = (0...80).map { point(routePoint(item, progress: CGFloat($0) / 80)) }
                var line = Path(); line.addLines(samples)
                context.stroke(line, with: .color(.black.opacity(0.35)), lineWidth: 1)
                if config.showCountTicks && counts > 1 {
                    for count in 1..<counts {
                        let c = point(routePoint(item, progress: CGFloat(count) / CGFloat(counts)))
                        context.fill(Path(ellipseIn: CGRect(x: c.x - 1.5, y: c.y - 1.5, width: 3, height: 3)),
                                     with: .color(.black.opacity(0.6)))
                    }
                }
            }
            let conflicts = config.showSpacingAlerts ? PathCalculations.collisionSummary(in: athletes).ids : []
            for athlete in athletes {
                let c = point(athlete.position)
                let rect = CGRect(x: c.x - 12, y: c.y - 12, width: 24, height: 24)
                let shape = AthleteRoleMarkerShape(role: athlete.role).path(in: rect)
                context.fill(shape, with: .color(.white))
                context.fill(shape, with: .color(ink(for: athlete).opacity(0.18)))
                context.stroke(shape, with: .color(ink(for: athlete)), lineWidth: 1.5)
                if conflicts.contains(athlete.id) {
                    context.stroke(Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)), with: .color(.red), lineWidth: 1.5)
                }
                context.draw(Text(athlete.label).font(.system(size: athlete.label.count > 3 ? 7 : 9,
                                                             weight: .bold, design: .rounded)).foregroundColor(.black), at: c)
            }
            context.draw(Text("FRONT").font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.gray), at: CGPoint(x: size.width / 2, y: floor.maxY + 18))
        }
        .accessibilityLabel("Formation diagram with \(athletes.count) athletes")
    }
}
