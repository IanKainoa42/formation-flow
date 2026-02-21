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
                // Bug 3 fix: blank slate, not sample()
                var formation = Formation()
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

// MARK: - Formation Thumbnail View

struct FormationThumbnailView: View {
    let formation: Formation

    private let thumbWidth: CGFloat = 80
    private let thumbHeight: CGFloat = 46
    private let gridCols: CGFloat = 52
    private let gridRows: CGFloat = 30

    var body: some View {
        Canvas { context, _ in
            let cellSize = min(thumbWidth / gridCols, thumbHeight / gridRows)

            // Border
            let borderRect = CGRect(x: 0, y: 0, width: gridCols * cellSize, height: gridRows * cellSize)
            context.stroke(Path(borderRect), with: .color(.gray.opacity(0.4)), lineWidth: 0.5)

            // Athletes
            for athlete in formation.athletes {
                let x = athlete.position.x * cellSize
                let y = athlete.position.y * cellSize
                let radius: CGFloat = 4

                let roleColor: Color
                switch athlete.role {
                case .flyer:    roleColor = .yellow
                case .base:     roleColor = .blue
                case .spotter:  roleColor = .green
                case .backspot: roleColor = .purple
                case .tumbler:  roleColor = .orange
                }

                var circle = Path()
                circle.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                context.fill(circle, with: .color(roleColor.opacity(0.85)))
            }
        }
        .frame(width: thumbWidth, height: thumbHeight)
        .background(Color(UIColor.systemBackground))
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
                            HStack(spacing: 12) {
                                FormationThumbnailView(formation: formation)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3)))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(formation.name).font(.headline)
                                    Text("\(formation.athletes.count) athletes")
                                        .font(.caption).foregroundColor(.gray)
                                }
                                Spacer()
                                if !formation.notes.isEmpty {
                                    Image(systemName: "note.text")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
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
    var startFormation: Formation? = nil
    var endFormation: Formation? = nil
    // Bug 1 fix: dynamic cellSize and offset passed in from parent GeometryReader
    var cellSize: CGFloat = 12
    var offset: CGPoint = .zero

    let gridCols: CGFloat = 52
    let gridRows: CGFloat = 30

    var body: some View {
        Canvas { context, _ in
            var ctx = context
            // Translate so the grid is centered in the available space
            ctx.translateBy(x: offset.x, y: offset.y)
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

            var pathLine = Path()
            pathLine.move(to: startPos)
            pathLine.addLine(to: endPos)
            context.stroke(
                pathLine,
                with: .color(pathColor.opacity(0.4)),
                lineWidth: lineWidth
            )

            let dx = endPos.x - startPos.x
            let dy = endPos.y - startPos.y
            let dist = hypot(dx, dy)
            guard dist > 5 else { continue }

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

            var startGhost = Path()
            startGhost.addEllipse(in: CGRect(x: startPos.x - 10, y: startPos.y - 10, width: 20, height: 20))
            context.stroke(
                startGhost,
                with: .color(.gray.opacity(0.25)),
                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
            )

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
        let width = gridCols * cellSize
        let height = gridRows * cellSize

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

            // Bug 5 fix: role-based color coding
            let roleColor: Color
            switch athlete.role {
            case .flyer:    roleColor = .yellow
            case .base:     roleColor = .blue
            case .spotter:  roleColor = .green
            case .backspot: roleColor = .purple
            case .tumbler:  roleColor = .orange
            }
            let color: Color = isColliding ? .red : (isSelected ? .white : roleColor)
            let radius: CGFloat = isSelected ? 18 : 14

            var circlePath = Path()
            circlePath.addEllipse(in: CGRect(
                x: screenPos.x - radius,
                y: screenPos.y - radius,
                width: radius * 2,
                height: radius * 2
            ))

            context.fill(circlePath, with: .color(color.opacity(0.85)))

            if isSelected {
                // Draw selection ring
                var ringPath = Path()
                ringPath.addEllipse(in: CGRect(
                    x: screenPos.x - radius,
                    y: screenPos.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
                context.stroke(ringPath, with: .color(roleColor), lineWidth: 3)
            }

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

            let labelColor: Color = isSelected ? roleColor : .white
            let displayLabel = String(athlete.label.prefix(3))
            let text = Text(displayLabel)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(labelColor)

            context.draw(text, at: screenPos, anchor: .center)
        }
    }
}

// MARK: - Floor Grid View

struct FloorGridView: View {
    @StateObject private var persistenceManager = PersistenceManager.shared
    @Environment(\.dismiss) private var dismiss
    @State var formation: Formation
    @State var selectedAthleteId: UUID?
    @State private var showingRenameAlert = false
    @State private var renameText = ""
    @State private var showingTransitionSheet = false
    @State private var showingNotesSheet = false

    // Bug 2 fix: track drag state in parent so gesture and canvas share it
    @State private var isDraggingAthlete = false
    @State private var dragStartAthletePosition: CGPoint = .zero

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
                // Bug 2 fix: single combined gesture handles both tap-to-select and drag
                .gesture(floorGesture(cellSize: cellSize, offset: canvasOffset))
                // Pinch-to-zoom + two-finger pan
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            zoomScale = max(0.5, min(4.0, lastZoomScale * value))
                        }
                        .onEnded { value in
                            lastZoomScale = zoomScale
                        }
                        .simultaneously(with:
                            DragGesture(minimumDistance: 1)
                                .onChanged { value in
                                    panOffset = CGSize(
                                        width: lastPanOffset.width + value.translation.width,
                                        height: lastPanOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    lastPanOffset = panOffset
                                }
                        )
                )
                // Double-tap to reset zoom and pan
                .onTapGesture(count: 2) {
                    withAnimation(.spring()) {
                        zoomScale = 1.0
                        lastZoomScale = 1.0
                        panOffset = .zero
                        lastPanOffset = .zero
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
                            Label("\(collisions.count)", systemImage: "exclamationmark.triangle.fill")
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
                    Button(action: { showingTransitionSheet = true }) {
                        Label("Transition", systemImage: "arrow.right.circle")
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
        // Bug 3 fix: transition picker sheet — pick end formation, go straight to player
        .sheet(isPresented: $showingTransitionSheet) {
            TransitionPickerView(startFormation: formation)
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
        let label = "P\(count)"
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
        duplicate.name = "\(formation.name) (Copy)"
        persistenceManager.addFormation(duplicate)
    }

    // Bug 2 fix: combined tap+drag gesture — single source of truth for position.
    // Stores the athlete's position at drag start so translation never compounds.
    private func floorGesture(cellSize: CGFloat, offset: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let startScaled = CGPoint(
                    x: (value.startLocation.x - offset.x) / cellSize,
                    y: (value.startLocation.y - offset.y) / cellSize
                )

                if !isDraggingAthlete {
                    // First event: determine if a finger landed on an athlete
                    var found = false
                    for athlete in formation.athletes {
                        let dist = hypot(startScaled.x - athlete.position.x,
                                         startScaled.y - athlete.position.y)
                        // Bug 2 fix: threshold 2.0 ft (was 1.0) — matches visible circle radius
                        if dist < 2.0 {
                            selectedAthleteId = athlete.id
                            isDraggingAthlete = true
                            dragStartAthletePosition = athlete.position
                            found = true
                            break
                        }
                    }
                    if !found {
                        selectedAthleteId = nil
                    }
                }

                // Move selected athlete using translation from drag start (no drift)
                if isDraggingAthlete,
                   let selectedId = selectedAthleteId,
                   let index = formation.athletes.firstIndex(where: { $0.id == selectedId }) {
                    let newX = dragStartAthletePosition.x + value.translation.width / cellSize
                    let newY = dragStartAthletePosition.y + value.translation.height / cellSize
                    formation.athletes[index].position = CGPoint(
                        x: max(0, min(CourtConstants.width, newX)),
                        y: max(0, min(CourtConstants.height, newY))
                    )
                }
            }
            .onEnded { _ in
                isDraggingAthlete = false
            }
    }
}

// MARK: - Transition Picker View (launched from editor toolbar)

struct TransitionPickerView: View {
    let startFormation: Formation
    @StateObject private var persistenceManager = PersistenceManager.shared
    @Environment(\.dismiss) private var dismiss

    var otherFormations: [Formation] {
        persistenceManager.formations.filter { $0.id != startFormation.id }
    }

    var body: some View {
        NavigationStack {
            Group {
                if otherFormations.isEmpty {
                    ContentUnavailableView(
                        "No Other Formations",
                        systemImage: "arrow.left.arrow.right",
                        description: Text("Save another formation first, then come back to preview the transition.")
                    )
                } else {
                    List {
                        Section {
                            Text("Starting from: \(startFormation.name)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Section("Transition to...") {
                            ForEach(otherFormations) { formation in
                                NavigationLink(destination: TransitionPlayerView(
                                    startFormation: startFormation,
                                    endFormation: formation
                                )) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(formation.name).font(.headline)
                                        Text("\(formation.athletes.count) athletes")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Preview Transition")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Transition Setup View (accessible from main menu)

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
    @State private var countMode: Bool = false

    let gridCols: CGFloat = 52
    let gridRows: CGFloat = 30

    init(startFormation: Formation, endFormation: Formation) {
        _player = StateObject(wrappedValue: TransitionPlayer(from: startFormation, to: endFormation))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Bug 1 fix: centered canvas using GeometryReader
            GeometryReader { geometry in
                let cellSize = min(geometry.size.width / gridCols, geometry.size.height / gridRows)
                let canvasWidth = gridCols * cellSize
                let canvasHeight = gridRows * cellSize
                let offsetX = (geometry.size.width - canvasWidth) / 2
                let offsetY = (geometry.size.height - canvasHeight) / 2
                let canvasOffset = CGPoint(x: offsetX, y: offsetY)

                FloorCanvasView(
                    formation: player.currentFormation,
                    selectedAthleteId: selectedAthleteId,
                    startFormation: player.startFormation,
                    endFormation: player.endFormation,
                    cellSize: cellSize,
                    offset: canvasOffset
                )
                .gesture(athleteTapGesture(cellSize: cellSize, offset: canvasOffset))
            }

            Divider()

            if let selectedId = selectedAthleteId,
               let index = player.startFormation.athletes.firstIndex(where: { $0.id == selectedId }) {
                TimingControlsView(athlete: Binding(
                    get: { player.startFormation.athletes[index] },
                    set: { newAthlete in
                        player.startFormation.athletes[index] = newAthlete
                        player.seek(to: player.progress)
                    }
                ))
                .padding(.horizontal)
                .padding(.top, 8)
            }

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
                    if countMode {
                        let currentCount = player.progress * 8
                        Text(String(format: "Count %.1f", currentCount))
                            .font(.caption.monospacedDigit())
                        Spacer()
                        Text("of 8")
                            .font(.caption.monospacedDigit())
                    } else {
                        Text(formatTime(player.progress * CGFloat(player.duration)))
                            .font(.caption.monospacedDigit())
                        Spacer()
                        Text(formatTime(CGFloat(player.duration)))
                            .font(.caption.monospacedDigit())
                    }
                }
                .foregroundColor(.gray)

                if countMode {
                    Divider().padding(.horizontal)
                    HStack(spacing: 0) {
                        ForEach(1...8, id: \.self) { count in
                            Text("\(count)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

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

                Button(action: { countMode.toggle() }) {
                    Text(countMode ? "8ct" : "sec")
                        .font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(countMode ? Color.blue : Color.gray.opacity(0.2))
                        .foregroundColor(countMode ? .white : .primary)
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

    private func athleteTapGesture(cellSize: CGFloat, offset: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let scaledPoint = CGPoint(
                    x: (value.startLocation.x - offset.x) / cellSize,
                    y: (value.startLocation.y - offset.y) / cellSize
                )

                for athlete in player.currentFormation.athletes {
                    if hypot(scaledPoint.x - athlete.position.x,
                             scaledPoint.y - athlete.position.y) < 2.0 {
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

// MARK: - Athlete Detail Panel

struct AthleteDetailPanel: View {
    @Binding var athlete: Athlete
    @Binding var selectedAthleteId: UUID?

    private let roles: [(AthleteRole, Color)] = [
        (.base, .blue),
        (.flyer, .yellow),
        (.spotter, .green),
        (.backspot, .purple),
        (.tumbler, .orange),
    ]

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Name", text: $athlete.label)
                    .font(.headline)
                    .textFieldStyle(.plain)
                Spacer()
                Button(action: { selectedAthleteId = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 12) {
                ForEach(roles, id: \.0) { role, color in
                    Button {
                        athlete.role = role
                    } label: {
                        ZStack {
                            Circle()
                                .fill(color)
                                .frame(width: 28, height: 28)
                            if athlete.role == role {
                                Image(systemName: "checkmark")
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
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
                for i in 0..<end.athletes.count {
                    end.athletes[i].position.x += 10
                }
                return end
            }()
        )
    }
}
