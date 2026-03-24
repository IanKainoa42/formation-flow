# Full Routine Playback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add full-screen routine playback that chains all transitions end-to-end with scrubbing, speed controls, and an optional ghost trail effect.

**Architecture:** A new `RoutinePlayer` class orchestrates the existing `TransitionPlayer` across multiple segments. A new `RoutinePlaybackView` provides full-screen playback UI. Ghost trails are rendered in `FloorCanvasView` via a new optional `trailPositions` parameter.

**Tech Stack:** Swift/SwiftUI, Canvas API, Combine

**Spec:** `docs/superpowers/specs/2026-03-20-routine-playback-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `FormationFlow/Models.swift` | Modify | Add `onComplete` closure to `TransitionPlayer`, add `RoutinePlayer` class |
| `FormationFlow/FloorCanvasView.swift` | Modify | Add `trailPositions` parameter and ghost trail rendering |
| `FormationFlow/RoutinePlaybackView.swift` | Create | Full-screen playback view with transport controls |
| `FormationFlow/FormationHomeView.swift` | Modify | Add "Play Routine" button and `.fullScreenCover` to `RoutineWorkspaceView` |

---

### Task 1: Add `onComplete` closure to `TransitionPlayer`

**Files:**
- Modify: `FormationFlow/Models.swift:1850-1937` (TransitionPlayer class)

- [ ] **Step 1: Add the `onComplete` property to `TransitionPlayer`**

In `Models.swift`, add an `onComplete` closure property to the `TransitionPlayer` class after the existing published properties (after line 1858):

```swift
var onComplete: (() -> Void)?
```

- [ ] **Step 2: Call `onComplete` when a non-looping transition finishes**

In the `update()` method (line 1925-1937), modify the completion branch to call `onComplete` before pausing. Change:

```swift
if progress >= 1.0 {
    if isLooping {
        progress = 0
    } else {
        pause()
    }
}
```

To:

```swift
if progress >= 1.0 {
    if isLooping {
        progress = 0
    } else {
        pause()
        onComplete?()
    }
}
```

- [ ] **Step 3: Build to verify no regressions**

Run:
```bash
xcodebuild -project FormationFlow.xcodeproj -scheme FormationFlow \
  -destination 'platform=iOS Simulator,id=4676C328-77F6-47FA-85E1-B6E327B0E17C' build
```
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add FormationFlow/Models.swift
git commit -m "feat: add onComplete closure to TransitionPlayer"
```

---

### Task 2: Add `RoutinePlayer` class

**Files:**
- Modify: `FormationFlow/Models.swift` (add after `TransitionPreviewSession` class, before `AnimationTimer`)

- [ ] **Step 0: Add `import Combine` to Models.swift**

`Models.swift` currently imports `Foundation`, `OSLog`, and `SwiftUI`. `RoutinePlayer` uses `AnyCancellable`, which requires Combine. Add `import Combine` at the top of `Models.swift` (after the existing imports).

- [ ] **Step 1: Add the `RoutinePlayer` class**

Add the following class to `Models.swift` after the `TransitionPreviewSession.clear()` closing brace (after line ~2059) and before the `AnimationTimer` class (line ~2063):

```swift
// MARK: - Routine Player

struct RoutineSegment {
    let startAthletes: [RenderedAthlete]
    let endAthletes: [RenderedAthlete]
    let spec: TransitionSpec
    let formationName: String
}

@MainActor
final class RoutinePlayer: ObservableObject {
    @Published var currentAthletes: [RenderedAthlete] = []
    @Published var progress: CGFloat = 0
    @Published var isPlaying = false
    @Published var speed: CGFloat = 1.0
    @Published var currentSegmentIndex: Int = 0
    @Published var currentFormationName: String = ""
    @Published var showTrail = false
    @Published var trailPositions: [UUID: [CGPoint]] = [:]

    let segments: [RoutineSegment]
    let segmentMarkers: [CGFloat]
    var segmentCount: Int { segments.count }

    private var player: TransitionPlayer?
    private var athletesSink: AnyCancellable?
    private var isInGap = false
    private let trailLength = 6

    // Cumulative duration fractions for proportional timeline
    private let cumulativeFractions: [CGFloat]
    private let totalDuration: CGFloat

    init(store: RoutineStore) {
        let formations = store.routine.formations
        var segs: [RoutineSegment] = []

        for i in 0..<(formations.count - 1) {
            let from = formations[i]
            let to = formations[i + 1]
            segs.append(RoutineSegment(
                startAthletes: store.renderedAthletes(for: from),
                endAthletes: store.renderedAthletes(for: to),
                spec: store.transitionSpec(for: from.id, to: to.id),
                formationName: from.name
            ))
        }

        self.segments = segs

        // Compute cumulative duration fractions
        let total = segs.reduce(CGFloat(0)) { $0 + max(CGFloat($1.spec.duration), 0.5) }
        self.totalDuration = total
        var cumulative: [CGFloat] = []
        var running: CGFloat = 0
        for seg in segs {
            running += max(CGFloat(seg.spec.duration), 0.5)
            cumulative.append(running / total)
        }
        self.cumulativeFractions = cumulative

        // Segment markers are at boundaries between segments (not including 0 or 1)
        self.segmentMarkers = Array(cumulative.dropLast())

        if let first = segs.first {
            self.currentAthletes = first.startAthletes
            self.currentFormationName = first.formationName
        }
    }

    func play() {
        guard !segments.isEmpty else { return }
        if progress >= 1.0 {
            progress = 0
            currentSegmentIndex = 0
        }
        isPlaying = true
        loadSegment(at: currentSegmentIndex)
        player?.play()
    }

    func pause() {
        isPlaying = false
        player?.pause()
    }

    func reset() {
        pause()
        progress = 0
        currentSegmentIndex = 0
        trailPositions = [:]
        if let first = segments.first {
            currentAthletes = first.startAthletes
            currentFormationName = first.formationName
        }
    }

    func seek(to globalProgress: CGFloat) {
        let clamped = max(0, min(1, globalProgress))
        progress = clamped

        // Find which segment this falls in
        let segIndex = segmentIndex(for: clamped)
        let localProgress = localProgress(for: clamped, inSegment: segIndex)

        currentSegmentIndex = segIndex
        if segIndex < segments.count {
            currentFormationName = segments[segIndex].formationName
        }

        trailPositions = [:]
        loadSegment(at: segIndex)
        player?.seek(to: localProgress)
    }

    func setSpeed(_ newSpeed: CGFloat) {
        speed = newSpeed
        player?.speed = newSpeed
    }

    // MARK: - Private

    private func loadSegment(at index: Int) {
        guard index < segments.count else { return }
        let seg = segments[index]
        currentFormationName = seg.formationName

        if let player {
            player.refresh(
                startAthletes: seg.startAthletes,
                endAthletes: seg.endAthletes,
                transitionSpec: seg.spec
            )
            player.seek(to: 0)
            player.speed = speed
        } else {
            let newPlayer = TransitionPlayer(
                startAthletes: seg.startAthletes,
                endAthletes: seg.endAthletes,
                transitionSpec: seg.spec
            )
            newPlayer.speed = speed
            self.player = newPlayer
            subscribeToPlayer(newPlayer)
        }

        player?.onComplete = { [weak self] in
            self?.handleSegmentComplete()
        }
    }

    private func subscribeToPlayer(_ player: TransitionPlayer) {
        athletesSink = player.$currentAthletes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] athletes in
                guard let self else { return }
                self.currentAthletes = athletes
                self.updateTrail(athletes: athletes)
                self.updateGlobalProgress()
            }
    }

    private func handleSegmentComplete() {
        let nextIndex = currentSegmentIndex + 1
        guard nextIndex < segments.count else {
            isPlaying = false
            progress = 1.0
            return
        }

        isInGap = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.isPlaying else {
                self?.isInGap = false
                return
            }
            self.isInGap = false
            self.currentSegmentIndex = nextIndex
            self.loadSegment(at: nextIndex)
            self.player?.play()
        }
    }

    private func updateGlobalProgress() {
        guard !isInGap, let player else { return }
        let localP = player.progress

        let segStart: CGFloat = currentSegmentIndex > 0 ? cumulativeFractions[currentSegmentIndex - 1] : 0
        let segEnd = cumulativeFractions[currentSegmentIndex]
        progress = segStart + localP * (segEnd - segStart)
    }

    private func updateTrail(athletes: [RenderedAthlete]) {
        for athlete in athletes {
            var positions = trailPositions[athlete.id] ?? []
            positions.append(athlete.position)
            if positions.count > trailLength {
                positions.removeFirst(positions.count - trailLength)
            }
            trailPositions[athlete.id] = positions
        }
    }

    private func segmentIndex(for globalProgress: CGFloat) -> Int {
        if globalProgress >= 1.0 { return max(0, segments.count - 1) }
        for (i, fraction) in cumulativeFractions.enumerated() {
            if globalProgress < fraction { return i }
        }
        return max(0, segments.count - 1)
    }

    private func localProgress(for globalProgress: CGFloat, inSegment index: Int) -> CGFloat {
        let segStart: CGFloat = index > 0 ? cumulativeFractions[index - 1] : 0
        let segEnd = cumulativeFractions[index]
        let segWidth = segEnd - segStart
        guard segWidth > 0 else { return 0 }
        return max(0, min(1, (globalProgress - segStart) / segWidth))
    }
}
```

- [ ] **Step 2: Build to verify**

Run:
```bash
xcodebuild -project FormationFlow.xcodeproj -scheme FormationFlow \
  -destination 'platform=iOS Simulator,id=4676C328-77F6-47FA-85E1-B6E327B0E17C' build
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add FormationFlow/Models.swift
git commit -m "feat: add RoutinePlayer class for full routine playback"
```

---

### Task 3: Add ghost trail rendering to `FloorCanvasView`

**Files:**
- Modify: `FormationFlow/FloorCanvasView.swift:5-466`

- [ ] **Step 1: Add `trailPositions` parameter**

In `FloorCanvasView`, add after the `ghostAthletes` property (line 23):

```swift
var trailPositions: [UUID: [CGPoint]] = [:]
```

- [ ] **Step 2: Add `drawTrails` method**

Add after the `drawGhostAthletes` method (after line 352):

```swift
private func drawTrails(in context: inout GraphicsContext) {
    guard !trailPositions.isEmpty else { return }

    let athleteLookup = Dictionary(athletes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    for (athleteID, positions) in trailPositions {
        guard positions.count > 1, let athlete = athleteLookup[athleteID] else { continue }
        let color = athlete.role.color

        for (i, position) in positions.enumerated() {
            let age = positions.count - 1 - i  // 0 = newest, count-1 = oldest
            guard age > 0 else { continue }  // skip newest (that's the main circle)

            let opacity = 0.06 + 0.04 * CGFloat(positions.count - 1 - age)
            let scale = 0.5 + 0.08 * CGFloat(positions.count - 1 - age)
            let radius = athlete.role.markerRadius * scale

            let point = CGPoint(x: position.x * cellSize, y: position.y * cellSize)
            var trail = Path()
            trail.addEllipse(in: CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            context.fill(trail, with: .color(color.opacity(opacity)))
        }
    }
}
```

- [ ] **Step 3: Call `drawTrails` in the Canvas body**

In the `body` Canvas closure (line 26-52), add `drawTrails(in: &context)` after `drawGhostAthletes`:

```swift
drawGhostAthletes(in: &context)
drawTrails(in: &context)
```

- [ ] **Step 4: Build to verify**

Run:
```bash
xcodebuild -project FormationFlow.xcodeproj -scheme FormationFlow \
  -destination 'platform=iOS Simulator,id=4676C328-77F6-47FA-85E1-B6E327B0E17C' build
```
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add FormationFlow/FloorCanvasView.swift
git commit -m "feat: add ghost trail rendering to FloorCanvasView"
```

---

### Task 4: Create `RoutinePlaybackView`

**Files:**
- Create: `FormationFlow/RoutinePlaybackView.swift`

- [ ] **Step 1: Create the playback view file**

Create `FormationFlow/RoutinePlaybackView.swift`:

```swift
import SwiftUI

// MARK: - Routine Playback View

struct RoutinePlaybackView: View {
    @StateObject private var player: RoutinePlayer
    @Environment(\.dismiss) private var dismiss

    init(store: RoutineStore) {
        _player = StateObject(wrappedValue: RoutinePlayer(store: store))
    }

    var body: some View {
        GeometryReader { geometry in
            let courtWidth = CourtConstants.width
            let courtHeight = CourtConstants.height
            let availableWidth = geometry.size.width - 40  // 20pt padding each side
            let availableHeight = geometry.size.height - 140  // room for transport bar
            let cellSize = min(availableWidth / courtWidth, availableHeight / courtHeight)
            let gridWidth = courtWidth * cellSize
            let gridHeight = courtHeight * cellSize
            let offsetX = (geometry.size.width - gridWidth) / 2
            let offsetY = (geometry.size.height - 140 - gridHeight) / 2 + 20

            ZStack {
                Color.black.ignoresSafeArea()

                FloorCanvasView(
                    athletes: player.currentAthletes,
                    cellSize: cellSize,
                    offset: CGPoint(x: offsetX, y: offsetY),
                    formationColor: .accentColor,
                    trailPositions: player.showTrail ? player.trailPositions : [:]
                )
                .ignoresSafeArea()

                // Close button
                VStack {
                    HStack {
                        Button {
                            player.pause()
                            dismiss()
                        } label: {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .font(.body.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .padding(16)

                        Spacer()
                    }
                    Spacer()
                }

                // Transport bar
                VStack {
                    Spacer()
                    routineTransportBar
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
            }
        }
        .statusBarHidden()
        .onAppear {
            player.play()
        }
    }

    // MARK: - Transport Bar

    private var routineTransportBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Formation name
            HStack {
                Text(player.currentFormationName)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()

                Text("\(player.currentSegmentIndex + 1) / \(player.segmentCount)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            // Scrub bar with segment markers
            ZStack(alignment: .leading) {
                Slider(
                    value: Binding(
                        get: { player.progress },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...1
                )

                // Segment marker ticks
                GeometryReader { geo in
                    ForEach(Array(player.segmentMarkers.enumerated()), id: \.offset) { _, marker in
                        Rectangle()
                            .fill(Color.white.opacity(0.5))
                            .frame(width: 2, height: 12)
                            .position(x: marker * geo.size.width, y: geo.size.height / 2)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(height: 28)

            // Controls row
            HStack(spacing: 12) {
                // Play/Pause
                Button {
                    player.isPlaying ? player.pause() : player.play()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderedProminent)

                // Reset
                Button(action: player.reset) {
                    Image(systemName: "backward.end.fill")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)

                Spacer()

                // Speed picker
                Picker("Speed", selection: Binding(
                    get: { player.speed },
                    set: { player.setSpeed($0) }
                )) {
                    Text("1x").tag(CGFloat(1.0))
                    Text("2x").tag(CGFloat(2.0))
                    Text("4x").tag(CGFloat(4.0))
                }
                .pickerStyle(.segmented)
                .frame(width: 160)

                // Trail toggle
                Button {
                    player.showTrail.toggle()
                } label: {
                    Image(systemName: "sparkles")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .tint(player.showTrail ? .orange : .secondary)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        }
        .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
        .controlSize(.small)
    }
}
```

- [ ] **Step 2: Add the file to the Xcode project**

The file needs to be added to the Xcode project. Since the project uses `FormationFlow.xcodeproj`, open it in Xcode or use the following approach — create the file in the `FormationFlow/` directory (already done above), then add its reference to the project:

```bash
# The file is already in the FormationFlow/ directory alongside other Swift files.
# Xcode auto-discovers Swift files in the project directory for projects configured
# with folder references. If this project uses explicit file references in the
# .xcodeproj, the file must be added via Xcode. Build to check.
xcodebuild -project FormationFlow.xcodeproj -scheme FormationFlow \
  -destination 'platform=iOS Simulator,id=4676C328-77F6-47FA-85E1-B6E327B0E17C' build
```

If the build fails because the file isn't recognized, open `FormationFlow.xcodeproj` in Xcode and add the file to the project target. Then re-run the build.

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add FormationFlow/RoutinePlaybackView.swift
git commit -m "feat: add RoutinePlaybackView for full-screen routine playback"
```

---

### Task 5: Integrate into `RoutineWorkspaceView`

**Files:**
- Modify: `FormationFlow/FormationHomeView.swift`

- [ ] **Step 1: Add state variable**

In `RoutineWorkspaceView`, add after the `isFullScreen` state variable (line 22):

```swift
@State private var showingRoutinePlayback = false
```

- [ ] **Step 2: Add "Play Routine" button to the regular sidebar toolbar**

In the `regularSidebar` toolbar (lines 307-314), add a Play Routine button before the EditButton:

```swift
ToolbarItemGroup(placement: .navigationBarTrailing) {
    Button {
        showingRoutinePlayback = true
    } label: {
        Image(systemName: "play.circle")
    }
    .disabled(store.routine.formations.count < 2)
    .accessibilityLabel("Play routine")

    EditButton()
    Button(action: addFormation) {
        Image(systemName: canAddFormation ? "plus" : "lock.fill")
    }
    .accessibilityLabel(canAddFormation ? "Add formation" : "Upgrade to Pro to add formation")
}
```

- [ ] **Step 3: Add "Play Routine" button to the compact formation list toolbar**

In the `compactFormationList` toolbar (lines 365-372), add the same button before EditButton:

```swift
ToolbarItemGroup(placement: .navigationBarTrailing) {
    Button {
        showingRoutinePlayback = true
    } label: {
        Image(systemName: "play.circle")
    }
    .disabled(store.routine.formations.count < 2)
    .accessibilityLabel("Play routine")

    EditButton()
    Button(action: addFormation) {
        Image(systemName: canAddFormation ? "plus" : "lock.fill")
    }
    .accessibilityLabel(canAddFormation ? "Add formation" : "Upgrade to Pro to add formation")
}
```

- [ ] **Step 4: Add `.fullScreenCover` modifier**

In the `body` computed property, add a `.fullScreenCover` modifier after the existing `.sheet(isPresented: $showingUpgradeSheet)` (after line 173):

```swift
.fullScreenCover(isPresented: $showingRoutinePlayback) {
    RoutinePlaybackView(store: store)
}
```

- [ ] **Step 5: Build to verify**

Run:
```bash
xcodebuild -project FormationFlow.xcodeproj -scheme FormationFlow \
  -destination 'platform=iOS Simulator,id=4676C328-77F6-47FA-85E1-B6E327B0E17C' build
```
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add FormationFlow/FormationHomeView.swift
git commit -m "feat: add Play Routine button and full-screen cover to workspace"
```

---

### Task 6: Add new file to Xcode project (if needed)

**Files:**
- Modify: `FormationFlow.xcodeproj/project.pbxproj` (via Xcode)

This task only applies if Task 4's build failed because the `.xcodeproj` uses explicit file references.

- [ ] **Step 1: Check if the project uses explicit file references**

If Task 4's build succeeded, skip this entire task. If it failed with an "undefined" error for `RoutinePlaybackView`, the file needs to be added to the Xcode project manually. Since CLAUDE.md says "Do not modify the `.xcodeproj` file manually — use Xcode to add/remove files," this step requires opening Xcode.

Run Xcode to add the file:
```bash
open FormationFlow.xcodeproj
```

Then drag `RoutinePlaybackView.swift` into the FormationFlow group in the project navigator, ensuring "Add to targets: FormationFlow" is checked.

- [ ] **Step 2: Rebuild**

```bash
xcodebuild -project FormationFlow.xcodeproj -scheme FormationFlow \
  -destination 'platform=iOS Simulator,id=4676C328-77F6-47FA-85E1-B6E327B0E17C' build
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit the project file change**

```bash
git add FormationFlow.xcodeproj/project.pbxproj
git commit -m "chore: add RoutinePlaybackView.swift to Xcode project"
```
