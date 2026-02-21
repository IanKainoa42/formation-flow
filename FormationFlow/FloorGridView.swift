import SwiftUI

// MARK: - Floor Grid View

struct FloorGridView: View {
    @StateObject private var persistenceManager = PersistenceManager.shared
    @Environment(\\.dismiss) private var dismiss
    @State var formation: Formation
    @State var selectedAthleteId: UUID?
    @State private var showingRenameAlert = false
    @State private var renameText = ""
    @State private var navigateToTransition = false
    @State private var showingNotesSheet = false

    // Bug 2 fix: track drag state in parent so gesture and canvas share it
    @State private var isDraggingAthlete = false
    @State private var dragStartAthletePosition: CGPoint = .zero
    @State private var isPanning = false
    @State private var showingDeleteConfirmation = false

    // Zoom + pan state
    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero
    @State private var lastZoomScale: CGFloat = 1.0

    let gridCols: CGFloat = 52
    let gridRows: CGFloat = 30

    var body: some View {
        // Bug 1 fix: GeometryReader to compute centered canvas layout
        GeometryReader { geometry in
            let baseCellSize = min(geometry.size.width / gridCols, geometry.size.height / gridRows)
            let cellSize = baseCellSize * zoomScale
            let canvasWidth = gridCols * cellSize
            let canvasHeight = gridRows * cellSize
            let offsetX = (geometry.size.width - canvasWidth) / 2 + panOffset.width
            let offsetY = (geometry.size.height - canvasHeight) / 2 + panOffset.height
            let canvasOffset = CGPoint(x: offsetX, y: offsetY)

            ZStack {
                FloorCanvasView(
                    formation: formation,
                    selectedAthleteId: selectedAthleteId,
                    cellSize: cellSize,
                    offset: canvasOffset
                )
                // Single DragGesture decides mode on first touch: athlete drag or pan
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDraggingAthlete && !isPanning {
                                let startScaled = CGPoint(
                                    x: (value.startLocation.x - canvasOffset.x) / cellSize,
                                    y: (value.startLocation.y - canvasOffset.y) / cellSize
                                )
                                var hitAthlete = false
                                for athlete in formation.athletes {
                                    if hypot(startScaled.x - athlete.position.x,
                                             startScaled.y - athlete.position.y) < 2.0 {
                                        selectedAthleteId = athlete.id
                                        isDraggingAthlete = true
                                        dragStartAthletePosition = athlete.position
                                        hitAthlete = true
                                        break
                                    }
                                }
                                if !hitAthlete {
                                    selectedAthleteId = nil
                                    isPanning = true
                                }
                            }

                            if isDraggingAthlete,
                               let selectedId = selectedAthleteId,
                               let index = formation.athletes.firstIndex(where: { $0.id == selectedId }) {
                                let newX = dragStartAthletePosition.x + value.translation.width / cellSize
                                let newY = dragStartAthletePosition.y + value.translation.height / cellSize
                                formation.athletes[index].position = CGPoint(
                                    x: max(0, min(CourtConstants.width, newX)),
                                    y: max(0, min(CourtConstants.height, newY))
                                )
                            } else if isPanning {
                                panOffset = CGSize(
                                    width: lastPanOffset.width + value.translation.width,
                                    height: lastPanOffset.height + value.translation.height
                                )
                            }
                        }
                        .onEnded { _ in
                            if isPanning { lastPanOffset = panOffset }
                            isDraggingAthlete = false
                            isPanning = false
                        }
                )
                // Pinch-to-zoom (iOS distinguishes 1-finger vs 2-finger natively)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in zoomScale = max(0.5, min(4.0, lastZoomScale * value)) }
                        .onEnded { _ in lastZoomScale = zoomScale }
                )
                // Double-tap to reset zoom and pan
                .onTapGesture(count: 2) {
                    withAnimation(.spring()) {
                        zoomScale = 1.0; lastZoomScale = 1.0
                        panOffset = .zero; lastPanOffset = .zero
                    }
                }

                // Bug 5 fix: empty state prompt
                if formation.athletes.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "figure.stand")
                            .font(.system(size: 60))
                            .foregroundColor(.gray.opacity(0.4))
                        Text("Tap + to add athletes")
                            .font(.title3)
                            .foregroundColor(.gray)
                    }
                    .allowsHitTesting(false)
                }

                // Collision badge overlay
                if !collisions.isEmpty {
                    VStack {
                        HStack {
                            Spacer()
                            Label("\\(collisions.count)", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.red)
                                .cornerRadius(6)
                                .padding(.top, 12)
                                .padding(.trailing, 12)
                        }
                        Spacer()
                    }
                    .allowsHitTesting(false)
                }

                // Athlete detail panel
                if let selectedId = selectedAthleteId,
                   let index = formation.athletes.firstIndex(where: { $0.id == selectedId }) {
                    AthleteDetailPanel(athlete: $formation.athletes[index], selectedAthleteId: $selectedAthleteId)
                        .frame(width: 280)
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }

                // Bug 5 fix: floating + button (more prominent than toolbar icon)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: addAthlete) {
                            Image(systemName: "plus")
                                .font(.title2.bold())
                                .frame(width: 56, height: 56)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .clipShape(Circle())
                                .shadow(radius: 4)
                        }
                        .padding(.trailing, 24)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .navigationTitle(formation.name)
        .toolbar {
            // Bug 4 fix: Done button so users can leave the editor
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    // Bug 3 fix: direct transition button from editor
                    Button(action: { navigateToTransition = true }) {
                        Label("Transition", systemImage: "arrow.right.circle")
                    }

                    if selectedAthleteId != nil {
                        Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                            Image(systemName: "person.badge.minus")
                        }
                    }

                    Menu {
                        Button(action: {
                            renameText = formation.name
                            showingRenameAlert = true
                        }) {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button(action: duplicateFormation) {
                            Label("Duplicate", systemImage: "doc.on.doc")
                        }
                        Button(action: { showingNotesSheet = true }) {
                            Label("Notes", systemImage: "note.text")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .onChange(of: formation) { _, newFormation in
            persistenceManager.updateFormation(newFormation)
        }
        .alert("Rename Formation", isPresented: $showingRenameAlert) {
            TextField("Name", text: $renameText)
            Button("Save") {
                formation.name = renameText
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Enter a new name for this formation")
        }
        .navigationDestination(isPresented: $navigateToTransition) {
            TransitionPickerView(startFormation: formation)
        }
        .alert("Remove Athlete", isPresented: $showingDeleteConfirmation) {
            Button("Remove", role: .destructive) { deleteSelectedAthlete() }
            Button("Cancel", role: .cancel) { }
        } message: {
            if let id = selectedAthleteId,
               let athlete = formation.athletes.first(where: { $0.id == id }) {
                Text("Remove \\(athlete.label) from this formation?")
            }
        }
        .sheet(isPresented: $showingNotesSheet) {
            NavigationStack {
                ZStack(alignment: .topLeading) {
                    if formation.notes.isEmpty {
                        Text("Add notes for dancers, counts, cues...")
                            .foregroundColor(.gray.opacity(0.6))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $formation.notes)
                }
                .padding()
                .navigationTitle("Formation Notes")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { showingNotesSheet = false }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    var collisions: [(Athlete, Athlete)] {
        PathCalculations.findCollisions(in: formation, minDistance: 2.0)
    }

    private func addAthlete() {
        let count = formation.athletes.count + 1
        let label = "P\\(count)"
        let newAthlete = Athlete(
            label: label,
            position: CGPoint(x: gridCols / 2, y: gridRows / 2)
        )
        formation.addAthlete(newAthlete)
        selectedAthleteId = newAthlete.id
    }

    private func deleteSelectedAthlete() {
        guard let id = selectedAthleteId else { return }
        formation.removeAthlete(id: id)
        selectedAthleteId = nil
    }

    private func duplicateFormation() {
        var duplicate = formation
        duplicate.id = UUID()
        duplicate.name = "\\(formation.name) (Copy)"
        persistenceManager.addFormation(duplicate)
    }

}

// MARK: - Previews

#Preview {
    NavigationStack {
        FloorGridView(formation: Formation.sample())
    }
}
