import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class RoutinePDFExporter {
    
    static func generatePDF(for formationID: UUID, in store: RoutineStore) -> URL? {
        guard let formation = store.formation(id: formationID) else { return nil }
        
        let routine = store.routine
        let renderedAthletes = store.renderedAthletes(for: formation.id)
        
        let pdfView = FormationPDFTemplateView(
            routineName: routine.name,
            formationName: formation.name,
            notes: formation.notes,
            renderedAthletes: renderedAthletes
        )
        
        // 8.5 x 11 inches at 72 DPI (Landscape)
        let pageWidth: CGFloat = 11.0 * 72.0
        let pageHeight: CGFloat = 8.5 * 72.0
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        
        let renderer = ImageRenderer(content: pdfView.frame(width: pageWidth, height: pageHeight))
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(formation.name).pdf")
        
        // Render PDF
        var pdfBox = pageRect
        guard let pdfContext = CGContext(tempURL as CFURL, mediaBox: &pdfBox, nil) else {
            return nil
        }
        
        pdfContext.beginPDFPage(nil)
        renderer.render { size, context in
            context(pdfContext)
        }
        pdfContext.endPDFPage()
        pdfContext.closePDF()
        
        return tempURL
    }
}

struct FormationPDFTemplateView: View {
    let routineName: String
    let formationName: String
    let notes: String
    let renderedAthletes: [RenderedAthlete]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(routineName)
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text(formationName)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                }
                Spacer()
                Text("FormationFlow")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 40)
            .padding(.top, 40)
            
            // Court Diagram
            // Court is 72x56. We'll use a cell size that fits well.
            // 792 width - 80 padding = 712. 712 / 72 = 9.88. Let's use cellSize = 9.
            CenterAlignedCourt(renderedAthletes: renderedAthletes, cellSize: 9)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            
            // Notes & Legend
            HStack(alignment: .top) {
                if !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.headline)
                        Text(notes)
                            .font(.body)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer()
                }
                
                VStack(alignment: .trailing, spacing: 8) {
                    Text("Legend")
                        .font(.headline)
                    HStack(spacing: 12) {
                        LegendItem(role: .flyer)
                        LegendItem(role: .base)
                        LegendItem(role: .backspot)
                        LegendItem(role: .spotter)
                        LegendItem(role: .tumbler)
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
            
            Spacer(minLength: 0)
        }
        .frame(width: 792, height: 612)
        .background(Color.white)
    }
}

private struct CenterAlignedCourt: View {
    let renderedAthletes: [RenderedAthlete]
    let cellSize: CGFloat
    
    var body: some View {
        let courtWidth = CourtConstants.width * cellSize
        let courtHeight = CourtConstants.height * cellSize
        
        FloorCanvasView(
            athletes: renderedAthletes,
            cellSize: cellSize,
            useRoleColors: true,
            showCenterMark: true
        )
        .frame(width: courtWidth, height: courtHeight)
        .background(Color(white: 0.95)) // Light background for contrast
        .overlay(
            Rectangle().stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        // Keep it light theme for printing
        .environment(\.colorScheme, .light)
    }
}

private struct LegendItem: View {
    let role: AthleteRole
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(role.color)
                .frame(width: 12, height: 12)
            Text(role.displayName)
                .font(.caption)
                .foregroundColor(.black)
        }
    }
}
