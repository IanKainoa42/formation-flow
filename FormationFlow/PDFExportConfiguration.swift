import Foundation
import SwiftUI

// MARK: - PDF Export Configuration

struct PDFExportConfiguration: Equatable {
    // MARK: - Export Scope
    enum ExportScope: String, CaseIterable, Identifiable {
        case all = "All Formations"
        case currentOnly = "Current Formation"
        case custom = "Custom Selection"

        var id: String { rawValue }
    }

    // MARK: - Color Mode
    enum ColorMode: String, CaseIterable, Identifiable {
        case roleColors = "Role Colors"
        case formationAccent = "Formation Color"
        case monochrome = "Black & White (Print)"

        var id: String { rawValue }
    }

    // MARK: - Athlete Label Mode
    enum AthleteLabelMode: String, CaseIterable, Identifiable {
        case nameOrInitials = "Name / Initials"
        case role = "Role Name"
        case coordinates = "Coordinates (X, Y)"

        var id: String { rawValue }
    }

    // Scope & Pages
    var scope: ExportScope = .all
    var selectedFormationIDs: Set<UUID> = []
    var includeCoverPage: Bool = true
    var includePageNumbers: Bool = true

    // Visual Overlays
    var showTransitionPaths: Bool = true
    var showCountTicks: Bool = true
    var showGhostFormations: Bool = false
    var showStuntGroupHarnesses: Bool = true
    var showFloorGrid: Bool = true
    var showCenterMark: Bool = true
    var showSpacingAlerts: Bool = false

    // Athlete Styling
    var colorMode: ColorMode = .roleColors
    var athleteLabelMode: AthleteLabelMode = .nameOrInitials

    // Notes & Legend
    var showNotes: Bool = true
    var showRoleLegend: Bool = true
    var showCountsBadge: Bool = true

    init(
        scope: ExportScope = .all,
        selectedFormationIDs: Set<UUID> = [],
        includeCoverPage: Bool = true,
        includePageNumbers: Bool = true,
        showTransitionPaths: Bool = true,
        showCountTicks: Bool = true,
        showGhostFormations: Bool = false,
        showStuntGroupHarnesses: Bool = true,
        showFloorGrid: Bool = true,
        showCenterMark: Bool = true,
        showSpacingAlerts: Bool = false,
        colorMode: ColorMode = .roleColors,
        athleteLabelMode: AthleteLabelMode = .nameOrInitials,
        showNotes: Bool = true,
        showRoleLegend: Bool = true,
        showCountsBadge: Bool = true
    ) {
        self.scope = scope
        self.selectedFormationIDs = selectedFormationIDs
        self.includeCoverPage = includeCoverPage
        self.includePageNumbers = includePageNumbers
        self.showTransitionPaths = showTransitionPaths
        self.showCountTicks = showCountTicks
        self.showGhostFormations = showGhostFormations
        self.showStuntGroupHarnesses = showStuntGroupHarnesses
        self.showFloorGrid = showFloorGrid
        self.showCenterMark = showCenterMark
        self.showSpacingAlerts = showSpacingAlerts
        self.colorMode = colorMode
        self.athleteLabelMode = athleteLabelMode
        self.showNotes = showNotes
        self.showRoleLegend = showRoleLegend
        self.showCountsBadge = showCountsBadge
    }

    /// Resolves which formations should be exported based on scope and selection.
    func resolvedFormations(for routine: Routine, currentFormationID: UUID? = nil) -> [Formation] {
        switch scope {
        case .all:
            return routine.formations
        case .currentOnly:
            if let currentFormationID, let match = routine.formations.first(where: { $0.id == currentFormationID }) {
                return [match]
            }
            return routine.formations.first.map { [$0] } ?? []
        case .custom:
            return routine.formations.filter { selectedFormationIDs.contains($0.id) }
        }
    }
}
