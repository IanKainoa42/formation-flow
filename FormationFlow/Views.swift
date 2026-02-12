import SwiftUI

// MARK: - Main Menu View

struct MainMenuView: View {
    @StateObject private var persistenceManager = PersistenceManager.shared
    @State private var showingNewFormationAlert = false
    @State private var newFormationName = ""
    @State private var navigateToEditor = false
    @State private var activeFormation: Formation?

    var body: some View {
        VStack(spacing: 20) {
            Text("Formation Flow")
                .font(.title)
                .bold()

            Text("Digital Choreography Tool")
                .font(.subheadline)
                .foregroundColor(.gray)

            Spacer()

            Button(action: { showingNewFormationAlert = true }) {
                Label("New Formation", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }

            NavigationLink(destination: FormationListView()) {
                Label {
                    HStack {
                        Text("Saved Formations")
                        if !persistenceManager.formations.isEmpty {
                            Text("(\(persistenceManager.formations.count))")
                                .foregroundColor(.gray)
                        }
                    }
                } icon: {
                    Image(systemName: "folder.fill")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gray.opacity(0.3))
                .foregroundColor(.primary)
                .cornerRadius(8)
            }

            NavigationLink(destination: TransitionSetupView()) {
                Label("Transitions", systemImage: "arrow.left.arrow.right")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange.opacity(0.3))
                    .foregroundColor(.primary)
                    .cornerRadius(8)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Formation Flow")
        .alert("New Formation", isPresented: $showingNewFormationAlert) {
            TextField("Formation name", text: $newFormationName)
            Button("Create") {
                var formation = Formation.sample()
                formation.id = UUID()
                formation.name = newFormationName.isEmpty ? "Untitled Formation" : newFormationName
                persistenceManager.addFormation(formation)
                activeFormation = formation
                newFormationName = ""
                navigateToEditor = true
            }
            Button("Cancel", role: .cancel) { newFormationName = "" }
        }
        .navigationDestination(isPresented: $navigateToEditor) {
            if let formation = activeFormation {
                FloorGridView(formation: formation)
            }
        }
    }
}

// MARK: - Formation List View

struct FormationListView: View {
    @StateObject private var persistenceManager = PersistenceManager.shared

    var body: some View {
        Group {
            if persistenceManager.formations.isEmpty {
                ContentUnavailableView(
                    "No Saved Formations",
                    systemImage: "square.grid.2x2",
                    description: Text("Create a new formation from the main menu.")
                )
            } else {
                List {
                    ForEach(persistenceManager.formations) { formation in
                        NavigationLink(destination: FloorGridView(formation: formation)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(formation.name)
                                    .font(.headline)
                                Text("\(formation.athletes.count) athletes")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            persistenceManager.deleteFormation(id: persistenceManager.formations[index].id)
                        }
                    }
                }
            }
        }
        .navigationTitle("Saved Formations")
    }
}

// MARK: - Floor Canvas View (Shared Rendering)

struct FloorCanvasView: View {
    let formation: Formation
    var selectedAthleteId: UUID? = nil
    var startFormation: Formation? = nil  // for transition path drawing
    var endFormation: Formation? = nil    // for transition path drawing

    let gridSize = CGSize(width: 52, height: 30)
    let cellSize: CGFloat = 12

    var body: some View {
        Canvas { context, size in
            var ctx = context
            drawGrid(in: &ctx)
            if let start = startFormation, let end = endFormation {
                drawPaths(in: &ctx, start: start, end: end)
            }
            drawAthletes(in: &ctx)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }

    private var collisions: [(Athlete, Athlete)] {
        PathCalculations.findCollisions(in: formation, minDistance: 2.0)
    }

    // MARK: - Path Drawing

    private func drawPaths(in context: inout GraphicsContext, start: Formation, end: Formation) {
        let pathCollisionIndices = findPathCollisionIndices(start: start, end: end)
        let count = min(start.athletes.count, end.athletes.count)

        for i in 0..<count {
            let startPos = CGPoint(
                x: start.athletes[i].position.x * cellSize,
                y: start.athletes[i].position.y * cellSize
            )
            let endPos = CGPoint(
                x: end.athletes[i].position.x * cellSize,
                y: end.athletes[i].position.y * cellSize
            )

            let isPathColliding = pathCollisionIndices.contains(i)
            let isSelected = start.athletes[i].id == selectedAthleteId
            let pathColor: Color = isPathColliding ? .red : (isSelected ? .blue : .green)
            let lineWidth: CGFloat = isSelected ? 3 : 1.5

            // Draw path line
            var pathLine = Path()
            pathLine.move(to: startPos)
            pathLine.addLine(to: endPos)
            context.stroke(
                pathLine,
                with: .color(pathColor.opacity(0.4)),
                lineWidth: lineWidth
            )

            // Draw arrow at end position
            let dx = endPos.x - startPos.x
            let dy = endPos.y - startPos.y
            let dist = hypot(dx, dy)
            guard dist > 5 else { continue }  // skip arrow for tiny movements

            let angle = atan2(dy, dx)
            let arrowLen: CGFloat = 10
            let arrowAngle: CGFloat = .pi / 6

            var arrowPath = Path()
            arrowPath.move(to: endPos)
            arrowPath.addLine(to: CGPoint(
                x: endPos.x - arrowLen * cos(angle - arrowAngle),
                y: endPos.y - arrowLen * sin(angle - arrowAngle)
            ))
            arrowPath.move(to: endPos)
            arrowPath.addLine(to: CGPoint(
                x: endPos.x - arrowLen * cos(angle + arrowAngle),
                y: endPos.y - arrowLen * sin(angle + arrowAngle)
            ))
            context.stroke(
                arrowPath,
                with: .color(pathColor.opacity(0.6)),
                lineWidth: 2
            )

            // Ghost circle at start position (dashed outline)
            var startGhost = Path()
            startGhost.addEllipse(in: CGRect(x: startPos.x - 10, y: startPos.y - 10, width: 20, height: 20))
            context.stroke(
                startGhost,
                with: .color(.gray.opacity(0.25)),
                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
            )

            // Ghost circle at end position (dashed outline)
            var endGhost = Path()
            endGhost.addEllipse(in: CGRect(x: endPos.x - 10, y: endPos.y - 10, width: 20, height: 20))
            context.stroke(
                endGhost,
                with: .color(.gray.opacity(0.25)),
                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
            )
        }
    }

    private func findPathCollisionIndices(start: Formation, end: Formation, steps: Int = 20) -> Set<Int> {
        let count = min(start.athletes.count, end.athletes.count)
        var collidingIndices = Set<Int>()

        var paths: [[CGPoint]] = []
        for i in 0..<count {
            paths.append(PathCalculations.athletePath(
                from: start.athletes[i].position,
                to: end.athletes[i].position,
                steps: steps
            ))
        }

        for i in 0..<count {
            for j in (i + 1)..<count {
                for step in 0..<min(paths[i].count, paths[j].count) {
                    if PathCalculations.distance(from: paths[i][step], to: paths[j][step]) < 2.0 {
                        collidingIndices.insert(i)
                        collidingIndices.insert(j)
                        break
                    }
                }
            }
        }

        return collidingIndices
    }

    private func drawGrid(in context: inout GraphicsContext) {
        let width = gridSize.width * cellSize
        let height = gridSize.height * cellSize

        var gridPath = Path()

        for x in stride(from: 0, through: width, by: cellSize) {
            gridPath.move(to: CGPoint(x: x, y: 0))
            gridPath.addLine(to: CGPoint(x: x, y: height))
        }

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
        let collisionIds = Set(collisions.flatMap { [$0.0.id, $0.1.id] })

        for athlete in formation.athletes {
            let screenPos = CGPoint(
                x: athlete.position.x * cellSize,
                y: athlete.position.y * cellSize
            )

            let isSelected = athlete.id == selectedAthleteId
            let isColliding = collisionIds.contains(athlete.id)
            let color: Color = isColliding ? .red : (isSelected ? .blue : .cyan)
            let radius: CGFloat = isSelected ? 18 : 14

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

            if isColliding {
                var warningRing = Path()
                warningRing.addEllipse(in: CGRect(
                    x: screenPos.x - (radius + 4),
                    y: screenPos.y - (radius + 4),
                    width: (radius + 4) * 2,
                    height: (radius + 4) * 2
                ))
                context.stroke(
                    warningRing,
                    with: .color(.red),
                    lineWidth: 2
                )
            }

            let text = Text(athlete.label)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.white)

            context.draw(
                text,
                at: screenPos,
                anchor: .center
            )
        }
    }
}

// MARK: - Floor Grid View

struct FloorGridView: View {
    @StateObject private var persistenceManager = PersistenceManager.shared
    @State var formation: Formation
    @State var selectedAthleteId: UUID?
    @State var dragOffset: CGSize = .zero
    @State private var showingRenameAlert = false
    @State private var renameText = ""

    let gridSize = CGSize(width: 52, height: 30)
    let cellSize: CGFloat = 12

    var body: some View {
        ZStack {
            FloorCanvasView(
                formation: formation,
                selectedAthleteId: selectedAthleteId
            )
            .gesture(floorTapGesture())

            if let selectedId = selectedAthleteId,
               let index = formation.athletes.firstIndex(where: { $0.id == selectedId }) {
                DragOverlayView(
                    athleteIndex: index,
                    formation: $formation,
                    dragOffset: $dragOffset
                )
            }
        }
        .navigationTitle(formation.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    if !collisions.isEmpty {
                        Text("\(collisions.count) collision(s)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    Button(action: addAthlete) {
                        Image(systemName: "person.badge.plus")
                    }

                    if selectedAthleteId != nil {
                        Button(role: .destructive, action: deleteSelectedAthlete) {
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
    }

    // MARK: - Actions

    var collisions: [(Athlete, Athlete)] {
        PathCalculations.findCollisions(in: formation, minDistance: 2.0)
    }

    private func addAthlete() {
        let count = formation.athletes.count + 1
        let label = "P\(count)"
        let newAthlete = Athlete(
            label: label,
            position: CGPoint(x: gridSize.width / 2, y: gridSize.height / 2)
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
        duplicate.name = "\(formation.name) (Copy)"
        persistenceManager.addFormation(duplicate)
    }

    private func floorTapGesture() -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let tapPoint = value.location
                let scaledPoint = CGPoint(
                    x: tapPoint.x / cellSize,
                    y: tapPoint.y / cellSize
                )

                for athlete in formation.athletes {
                    let distance = hypot(
                        scaledPoint.x - athlete.position.x,
                        scaledPoint.y - athlete.position.y
                    )
                    if distance < 1.0 {
                        withAnimation {
                            selectedAthleteId = athlete.id
                        }
                        return
                    }
                }
            }
    }
}

// MARK: - Transition Setup View

struct TransitionSetupView: View {
    @StateObject private var persistenceManager = PersistenceManager.shared
    @State private var startFormationId: UUID?
    @State private var endFormationId: UUID?

    private var startFormation: Formation? {
        persistenceManager.formations.first(where: { $0.id == startFormationId })
    }

    private var endFormation: Formation? {
        persistenceManager.formations.first(where: { $0.id == endFormationId })
    }

    var body: some View {
        Group {
            if persistenceManager.formations.count < 2 {
                ContentUnavailableView(
                    "Need 2+ Formations",
                    systemImage: "arrow.left.arrow.right",
                    description: Text("Create at least two formations to preview a transition.")
                )
            } else {
                Form {
                    Section("Start Formation") {
                        Picker("Start", selection: $startFormationId) {
                            Text("Select...").tag(nil as UUID?)
                            ForEach(persistenceManager.formations) { f in
                                Text("\(f.name) (\(f.athletes.count) athletes)").tag(f.id as UUID?)
                            }
                        }
                    }

                    Section("End Formation") {
                        Picker("End", selection: $endFormationId) {
                            Text("Select...").tag(nil as UUID?)
                            ForEach(persistenceManager.formations) { f in
                                Text("\(f.name) (\(f.athletes.count) athletes)").tag(f.id as UUID?)
                            }
                        }
                    }

                    if let start = startFormation, let end = endFormation {
                        Section {
                            if start.athletes.count != end.athletes.count {
                                Label("Athlete count differs (\(start.athletes.count) vs \(end.athletes.count)). Extra athletes stay in place.",
                                      systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }

                            NavigationLink("Play Transition") {
                                TransitionPlayerView(startFormation: start, endFormation: end)
                            }
                            .font(.headline)
                        }
                    }
                }
            }
        }
        .navigationTitle("Transitions")
    }
}

// MARK: - Transition Player View

struct TransitionPlayerView: View {
    @StateObject private var player: TransitionPlayer
    @State private var selectedAthleteId: UUID?

    init(startFormation: Formation, endFormation: Formation) {
        _player = StateObject(wrappedValue: TransitionPlayer(from: startFormation, to: endFormation))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Animation canvas with path visualization
            FloorCanvasView(
                formation: player.currentFormation,
                selectedAthleteId: selectedAthleteId,
                startFormation: player.startFormation,
                endFormation: player.endFormation
            )
            .gesture(athleteTapGesture())

            Divider()

            // Timing control for selected athlete
            if let selectedId = selectedAthleteId,
               let index = player.startFormation.athletes.firstIndex(where: { $0.id == selectedId }) {
                TimingControlsView(athlete: Binding(
                    get: { player.startFormation.athletes[index] },
                    set: { newAthlete in
                        player.startFormation.athletes[index] = newAthlete
                        player.seek(to: player.progress)  // refresh with new timing
                    }
                ))
                .padding(.horizontal)
                .padding(.top, 8)
            }

            // Progress slider
            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { player.progress },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...1,
                    onEditingChanged: { editing in
                        if editing { player.pause() }
                    }
                )

                HStack {
                    Text(formatTime(player.progress * CGFloat(player.duration)))
                        .font(.caption.monospacedDigit())
                    Spacer()
                    Text(formatTime(CGFloat(player.duration)))
                        .font(.caption.monospacedDigit())
                }
                .foregroundColor(.gray)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // Playback controls
            HStack(spacing: 30) {
                Menu {
                    Button("0.25x") { player.speed = 0.25 }
                    Button("0.5x") { player.speed = 0.5 }
                    Button("1x") { player.speed = 1.0 }
                    Button("2x") { player.speed = 2.0 }
                } label: {
                    Text("\(String(format: "%.2g", player.speed))x")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)
                }

                Button(action: { player.reset() }) {
                    Image(systemName: "backward.end.fill")
                        .font(.title2)
                }

                Button(action: {
                    if player.isPlaying {
                        player.pause()
                    } else {
                        player.play()
                    }
                }) {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.largeTitle)
                }
            }
            .padding()
        }
        .navigationTitle("Transition")
    }

    private func athleteTapGesture() -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let cellSize: CGFloat = 12
                let scaledPoint = CGPoint(
                    x: value.location.x / cellSize,
                    y: value.location.y / cellSize
                )

                for athlete in player.currentFormation.athletes {
                    if hypot(scaledPoint.x - athlete.position.x, scaledPoint.y - athlete.position.y) < 1.0 {
                        selectedAthleteId = athlete.id
                        return
                    }
                }
                selectedAthleteId = nil
            }
    }

    private func formatTime(_ seconds: CGFloat) -> String {
        String(format: "%.1fs", max(0, seconds))
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

// MARK: - Timing Controls View

struct TimingControlsView: View {
    @Binding var athlete: Athlete

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("\(athlete.label) - Move Timing: \(String(format: "%.1f", athlete.moveTiming))s")
                    .font(.caption)
                Spacer()
            }

            Slider(
                value: $athlete.moveTiming,
                in: 0...3,
                step: 0.1
            )
            .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                Text("Moves first")
                    .font(.caption2)
                    .foregroundColor(.gray)
                Spacer()
                Text("Moves last")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
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

#Preview("Formation List") {
    NavigationStack {
        FormationListView()
    }
}

#Preview("Transition Player") {
    NavigationStack {
        TransitionPlayerView(
            startFormation: Formation.sample(),
            endFormation: {
                var end = Formation.sample()
                end.id = UUID()
                end.name = "End"
                // Shift all athletes right by 10 feet
                for i in 0..<end.athletes.count {
                    end.athletes[i].position.x += 10
                }
                return end
            }()
        )
    }
}
