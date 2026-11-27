import SwiftUI
import Foundation

/// Manages the interaction and drafting state for the FloorGrid editor.
/// This is separated from the View to reduce the complexity of the FloorGridView.
@MainActor
final class EditorViewModel: ObservableObject {
    // MARK: - Sketching State
    @Published var pathSketchPoints: [CGPoint] = []
    @Published var isSketchingPath = false
    @Published var longPressArmingPosition: CGPoint?
    @Published var draggingWaypointID: UUID?
    @Published var pathHandleDragDraft: PathHandleDragDraft?
    @Published var pendingWaypointDeletionID: UUID?
    
    // MARK: - Undo State
    @Published var undoStack: [FormationMoveUndoSnapshot] = []
    
    // MARK: - Selection & Interaction
    @Published var draggingAthleteIDs: Set<UUID> = []
    @Published var isPanningCanvas = false
    @Published var isDrawingSelectionLasso = false
    @Published var selectionLasso: FloorSelectionLasso?
    @Published var dragStartPositions: [UUID: CGPoint] = [:]
    @Published var lastAppliedFormationDragPositions: [UUID: CGPoint] = [ies]
    @Published var lastAppliedEndpointDragPosition: CGPoint?
    @Published var swapSourceAthleteID: UUID?
    @Published var hasMadeFirstSelection = false
    @Published var activeAlignmentGuides: [AlignmentGuideRenderItem] = []
    @Published var activeMirrorGuides: [FormationMirrorGuideRenderItem] = []
    
    // MARK: - Selection Context
    @Published var focusedEndpoint: PreviewEditableEndpoint?
    @Published var isDraggingEndpoint = false
    @Published var isDraggingPathHandle = false
    @Published var isExplicitPathDrawMode = false
    @Published var pathDragAthleteID: UUID?
    @Published var selectionLasso: FloorSelectionLasso?
    
    init() {}
}