import SwiftUI

// MARK: - Main Menu View

struct MainMenuView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Formation Flow")
                .font(.title)
                .bold()
            
            Text("Digital Choreography Tool")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            Spacer()
            
            NavigationLink(destination: FloorGridView(formation: Formation.sample())) {
                Label("New Formation", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            
            NavigationLink(destination: Text("Load Formation (Coming Soon)")) {
                Label("Load Formation", systemImage: "folder.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.3))
                    .foregroundColor(.primary)
                    .cornerRadius(8)
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("Formation Flow")
    }
}

// MARK: - Floor Grid View

struct FloorGridView: View {
    @State var formation: Formation
    @State var selectedAthleteId: UUID?
    @State var dragOffset: CGSize = .zero
    
    let gridSize = CGSize(width: 52, height: 30)  // Standard cheerleading court
    let cellSize: CGFloat = 12  // pixels per foot
    
    var body: some View {
        ZStack {
            // Floor Grid Canvas
            Canvas { context in
                drawGrid(in: context)
                drawAthletes(in: context)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
            .gesture(floorTapGesture())
            
            // Drag Overlay for selected athlete
            if let selectedId = selectedAthleteId,
               let index = formation.athletes.firstIndex(where: { $0.id == selectedId }) {
                DragOverlayView(
                    athleteIndex: index,
                    formation: $formation,
                    dragOffset: $dragOffset
                )
            }
        }
        .navigationTitle("Floor Grid")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { selectedAthleteId = nil }) {
                    Text("Done")
                }
            }
        }
    }
    
    // MARK: - Drawing Functions
    
    private func drawGrid(in context: inout GraphicsContext) {
        let width = gridSize.width * cellSize
        let height = gridSize.height * cellSize
        
        var gridPath = Path()
        
        // Vertical lines
        for x in stride(from: 0, through: width, by: cellSize) {
            gridPath.move(to: CGPoint(x: x, y: 0))
            gridPath.addLine(to: CGPoint(x: x, y: height))
        }
        
        // Horizontal lines
        for y in stride(from: 0, through: height, by: cellSize) {
            gridPath.move(to: CGPoint(x: 0, y: y))
            gridPath.addLine(to: CGPoint(x: width, y: y))
        }
        
        context.stroke(
            gridPath,
            with: .color(.gray.opacity(0.3)),
            lineWidth: 0.5
        )
    }
    
    private func drawAthletes(in context: inout GraphicsContext) {
        for athlete in formation.athletes {
            let screenPos = CGPoint(
                x: athlete.position.x * cellSize,
                y: athlete.position.y * cellSize
            )
            
            let isSelected = athlete.id == selectedAthleteId
            let color: Color = isSelected ? .blue : .cyan
            let radius: CGFloat = isSelected ? 18 : 14
            
            // Draw circle
            var circlePath = Path()
            circlePath.addEllipse(in: CGRect(
                x: screenPos.x - radius,
                y: screenPos.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            
            context.fill(
                circlePath,
                with: .color(color.opacity(0.7))
            )
            
            // Draw label
            var text = Text(athlete.label)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.white)
            
            context.draw(
                text,
                at: screenPos,
                anchor: .center
            )
        }
    }
    
    private func floorTapGesture() -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let tapPoint = value.location
                let scaledPoint = CGPoint(
                    x: tapPoint.x / cellSize,
                    y: tapPoint.y / cellSize
                )
                
                // Check if tap is on an athlete
                for athlete in formation.athletes {
                    let distance = hypot(
                        scaledPoint.x - athlete.position.x,
                        scaledPoint.y - athlete.position.y
                    )
                    if distance < 1.0 {  // Within 1 foot
                        withAnimation {
                            selectedAthleteId = athlete.id
                        }
                        return
                    }
                }
            }
    }
}

// MARK: - Drag Overlay View

struct DragOverlayView: View {
    let athleteIndex: Int
    @Binding var formation: Formation
    @Binding var dragOffset: CGSize
    
    let cellSize: CGFloat = 12
    
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        withAnimation(.easeInOut(duration: 0.05)) {
                            let newX = (formation.athletes[athleteIndex].position.x * cellSize + value.translation.width) / cellSize
                            let newY = (formation.athletes[athleteIndex].position.y * cellSize + value.translation.height) / cellSize
                            
                            formation.athletes[athleteIndex].position = CGPoint(
                                x: max(0, min(52, newX)),
                                y: max(0, min(30, newY))
                            )
                        }
                    }
            )
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        FloorGridView(formation: Formation.sample())
    }
}

#Preview("Menu") {
    NavigationStack {
        MainMenuView()
    }
}
