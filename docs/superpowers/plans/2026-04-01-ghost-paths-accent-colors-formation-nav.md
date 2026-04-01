# Ghost Paths, Formation Accent Colors & Formation Navigation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add ghost transition paths showing prior formation movement, replace hardcoded orange selection indicators with per-formation rainbow colors, and add prev/next formation navigation to transport controls.

**Architecture:** Three additive features touching the rendering layer (`FloorCanvasView`), the editor state layer (`FloorGridView`), the transport UI (`TransitionViews.swift`), and the navigation wiring (`FormationHomeView`). No data model changes — `Models.swift` is untouched. Each feature is independent and can be committed separately.

**Tech Stack:** Swift 5.9+, SwiftUI Canvas API, iOS 17+

**Spec:** `docs/superpowers/specs/2026-04-01-ghost-paths-accent-colors-formation-nav-design.md`

---

## File Map

| File | Responsibility | Changes |
|------|---------------|---------|
| `FloorCanvasView.swift` | Canvas rendering | Add `ghostTransitionPaths` prop + `drawGhostTransitionPaths` method; replace `.orange` with `formationColor` in 5 locations |
| `FloorGridView.swift` | Editor state + canvas wiring | Compute `previousTransitionPaths`; pass to canvas; add `onPreviousFormation`/`onNextFormation` callbacks; wire `isFirstFormation`/`isLastFormation` |
| `TransitionViews.swift` | Transport control UI | Add `previousFormationButton`/`nextFormationButton` to `TransportControls`; add to `SidebarTransportView`, `CompactTransitionPlaybackRailView`, `CompactTransitionPlaybackOverlayView` |
| `FormationHomeView.swift` | Navigation wiring | Add `goToPreviousFormation`/`goToNextFormation`; wire new callbacks in all `FloorGridView` call sites |

---

### Task 1: Ghost Transition Paths — Canvas Rendering

**Files:**
- Modify: `FormationFlow/FloorCanvasView.swift:90-147` (struct properties + mainCanvas draw order)
- Modify: `FormationFlow/FloorCanvasView.swift:449-495` (after drawGhostAthletes)

- [ ] **Step 1: Add `ghostTransitionPaths` property to `FloorCanvasView`**

In `FloorCanvasView.swift`, after line 110 (`var trailPositions`), add:

```swift
var ghostTransitionPaths: [TransitionPathRenderItem] = []
```

- [ ] **Step 2: Add `drawGhostTransitionPaths` to the draw order**

In `mainCanvas` (line 125-147), insert the call between `drawGhostAthletes` and `drawTrails`:

```swift
// Change lines 129-131 from:
drawGrid(in: &context)
drawGhostAthletes(in: &context)
drawTrails(in: &context)

// To:
drawGrid(in: &context)
drawGhostAthletes(in: &context)
drawGhostTransitionPaths(in: &context)
drawTrails(in: &context)
```

- [ ] **Step 3: Implement `drawGhostTransitionPaths`**

Add this method after `drawGhostAthletes` (after line 457):

```swift
private func drawGhostTransitionPaths(in context: inout GraphicsContext) {
    guard !ghostTransitionPaths.isEmpty else { return }

    let dashStyle = StrokeStyle(lineWidth: 1, dash: [4, 4])

    for item in ghostTransitionPaths {
        let start = CGPoint(x: item.startPosition.x * cellSize, y: item.startPosition.y * cellSize)
        let end = CGPoint(x: item.endPosition.x * cellSize, y: item.endPosition.y * cellSize)

        // Draw ghost start position — hollow circle showing where athlete was
        var startMarker = Path()
        startMarker.addEllipse(in: CGRect(x: start.x - 6, y: start.y - 6, width: 12, height: 12))
        context.stroke(startMarker, with: .color(.white.opacity(0.08)), style: dashStyle)

        // Build the full path (same logic as drawTransitionPaths but simplified — no handles)
        if !item.waypoints.isEmpty {
            let nodes = item.nodes
            let segmentCount = nodes.count - 1
            guard segmentCount > 0 else { continue }

            for segmentIndex in 0..<segmentCount {
                let p0 = CGPoint(x: nodes[segmentIndex].x * cellSize, y: nodes[segmentIndex].y * cellSize)
                let p1 = CGPoint(x: nodes[segmentIndex + 1].x * cellSize, y: nodes[segmentIndex + 1].y * cellSize)
                let waypointAtEnd = segmentIndex < item.waypoints.count ? item.waypoints[segmentIndex] : nil

                var segment = Path()
                segment.move(to: p0)
                if waypointAtEnd?.isSmooth == true {
                    let prevNode = segmentIndex > 0 ? nodes[segmentIndex - 1] : nodes[segmentIndex]
                    let nextNode = segmentIndex + 2 < nodes.count ? nodes[segmentIndex + 2] : nodes[segmentIndex + 1]
                    let prev = CGPoint(x: prevNode.x * cellSize, y: prevNode.y * cellSize)
                    let next = CGPoint(x: nextNode.x * cellSize, y: nextNode.y * cellSize)
                    let (c1, c2) = PathCalculations.catmullRomControlPoints(prev: prev, p0: p0, p1: p1, next: next)
                    segment.addCurve(to: p1, control1: c1, control2: c2)
                } else {
                    segment.addLine(to: p1)
                }

                // Gradient opacity: stronger near end (where athlete arrived)
                let segmentProgress = CGFloat(segmentIndex + 1) / CGFloat(segmentCount)
                let opacity = 0.03 + 0.07 * segmentProgress  // 3% at start → 10% at end

                context.stroke(segment, with: .color(.white.opacity(opacity)), style: dashStyle)
            }
        } else {
            // Simple path (straight or quadratic Bezier)
            var path = Path()
            path.move(to: start)
            if let control = item.controlPoint {
                let controlPoint = CGPoint(x: control.x * cellSize, y: control.y * cellSize)
                path.addQuadCurve(to: end, control: controlPoint)
            } else {
                path.addLine(to: end)
            }
            // For simple paths, use a middle opacity since we can't easily gradient a single stroke
            context.stroke(path, with: .color(.white.opacity(0.07)), style: dashStyle)
        }
    }
}
```

- [ ] **Step 4: Build to verify compilation**

Run:
```bash
xcodebuild -project FormationFlow.xcodeproj -scheme FormationFlow \
  -destination 'platform=iOS Simulator,id=4676C328-77F6-47FA-85E1-B6E327B0E17C' build
```
Expected: BUILD SUCCEEDED (ghost paths won't render yet — no data passed from FloorGridView)

- [ ] **Step 5: Commit**

```bash
git add FormationFlow/FloorCanvasView.swift
git commit -m "feat: add ghost transition path rendering to FloorCanvasView

Draws prior-formation transition paths as dashed white lines with gradient
opacity (3% at origin, 10% at destination). Hollow circles mark prior positions.
Read-only — no handles or interactivity."
```

---

### Task 2: Ghost Transition Paths — Data Wiring

**Files:**
- Modify: `FormationFlow/FloorGridView.swift:159-165` (after previousFormationAthletes)
- Modify: `FormationFlow/FloorGridView.swift:923-944` (FloorCanvasView construction)

- [ ] **Step 1: Add `previousTransitionPaths` computed property**

In `FloorGridView.swift`, after `previousFormationAthletes` (line 165), add:

```swift
private var previousTransitionPaths: [TransitionPathRenderItem] {
    // Same optimization as previousFormationAthletes — skip during playback
    if let player, player.progress > 0 && player.progress < 1 { return [] }
    guard let formationIndex, formationIndex > 0 else { return [] }
    let prevFormation = store.routine.formations[formationIndex - 1]
    return store.transitionPaths(from: prevFormation.id, to: formationID)
}
```

- [ ] **Step 2: Pass `ghostTransitionPaths` to `FloorCanvasView`**

In the `FloorCanvasView` construction (around line 923-944), add after `ghostAthletes: previousFormationAthletes,` (line 941):

```swift
ghostTransitionPaths: showTransitionPaths ? previousTransitionPaths : [],
```

- [ ] **Step 3: Build and launch on simulator to verify ghost paths render**

Run:
```bash
xcodebuild -project FormationFlow.xcodeproj -scheme FormationFlow \
  -destination 'platform=iOS Simulator,id=4676C328-77F6-47FA-85E1-B6E327B0E17C' build
```
Expected: BUILD SUCCEEDED. When viewing formation 2+ with transition paths enabled, faint dashed paths from the prior transition should appear.

- [ ] **Step 4: Commit**

```bash
git add FormationFlow/FloorGridView.swift
git commit -m "feat: wire ghost transition paths from FloorGridView to canvas

Computes prior-formation transition paths and passes them to FloorCanvasView.
Skips computation during playback for performance."
```

---

### Task 3: Formation-Derived Accent Color — Canvas

**Files:**
- Modify: `FormationFlow/FloorCanvasView.swift:137-144` (selection lasso)
- Modify: `FormationFlow/FloorCanvasView.swift:210-217` (path color)
- Modify: `FormationFlow/FloorCanvasView.swift:537` (transition mode selected stroke)
- Modify: `FormationFlow/FloorCanvasView.swift:555` (formation mode selected stroke)
- Modify: `FormationFlow/FloorCanvasView.swift:564-570` (swap source ring)

- [ ] **Step 1: Replace `.orange` in selection lasso**

Change lines 139-143 from:

```swift
context.fill(path, with: .color(.orange.opacity(0.1)))
context.stroke(
    path,
    with: .color(.orange.opacity(0.45)),
    style: StrokeStyle(lineWidth: 1.5, lineJoin: .round, dash: [6, 3])
)
```

To:

```swift
context.fill(path, with: .color(formationColor.opacity(0.1)))
context.stroke(
    path,
    with: .color(formationColor.opacity(0.45)),
    style: StrokeStyle(lineWidth: 1.5, lineJoin: .round, dash: [6, 3])
)
```

- [ ] **Step 2: Replace `.orange` in path color selection**

Change line 217 from:

```swift
let pathColor: Color = isColliding ? .red : (isSelected ? .orange : .green)
```

To:

```swift
let pathColor: Color = isColliding ? .red : (isSelected ? formationColor : .green)
```

- [ ] **Step 3: Replace `.orange` in transition mode athlete stroke**

Change line 537 from:

```swift
let strokeColor: Color = isSelected ? .orange : .white
```

To:

```swift
let strokeColor: Color = isSelected ? formationColor : .white
```

- [ ] **Step 4: Replace `.orange` in formation mode athlete stroke**

Change line 555 from:

```swift
let strokeColor: Color = isSelected ? .orange : .white
```

To:

```swift
let strokeColor: Color = isSelected ? formationColor : .white
```

- [ ] **Step 5: Replace `.orange` in swap source ring**

Change line 568 from:

```swift
with: .color(.orange),
```

To:

```swift
with: .color(formationColor),
```

- [ ] **Step 6: Build to verify**

Run:
```bash
xcodebuild -project FormationFlow.xcodeproj -scheme FormationFlow \
  -destination 'platform=iOS Simulator,id=4676C328-77F6-47FA-85E1-B6E327B0E17C' build
```
Expected: BUILD SUCCEEDED. Selection indicators now use rainbow color matching the current formation.

- [ ] **Step 7: Commit**

```bash
git add FormationFlow/FloorCanvasView.swift
git commit -m "feat: replace hardcoded orange with formation rainbow color

Selection strokes, path highlights, swap rings, and lasso all now use
the current formation's rainbow color instead of orange."
```

---

### Task 4: Formation Navigation — Transport Control Buttons

**Files:**
- Modify: `FormationFlow/TransitionViews.swift:31-117` (TransportControls enum)

- [ ] **Step 1: Add `previousFormationButton` and `nextFormationButton` to `TransportControls`**

After the `pathButton` method (after line 116), add:

```swift
@ViewBuilder
static func previousFormationButton(size: CGFloat = 34, disabled: Bool = false, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: "chevron.up")
            .frame(width: size, height: size)
    }
    .buttonStyle(.bordered)
    .disabled(disabled)
    .accessibilityLabel("Previous formation")
    .help("Go to the previous formation")
}

@ViewBuilder
static func nextFormationButton(size: CGFloat = 34, disabled: Bool = false, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: "chevron.down")
            .frame(width: size, height: size)
    }
    .buttonStyle(.bordered)
    .disabled(disabled)
    .accessibilityLabel("Next formation")
    .help("Go to the next formation")
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
git add FormationFlow/TransitionViews.swift
git commit -m "feat: add prev/next formation buttons to TransportControls"
```

---

### Task 5: Formation Navigation — Wire into Transport Views

**Files:**
- Modify: `FormationFlow/TransitionViews.swift:326-370` (SidebarTransportView)
- Modify: `FormationFlow/TransitionViews.swift:227-322` (CompactTransitionPlaybackRailView)
- Modify: `FormationFlow/TransitionViews.swift:188-225` (CompactTransitionPlaybackOverlayView)

- [ ] **Step 1: Add navigation callbacks and state to `SidebarTransportView`**

Add properties after `canEditPath` (line 334):

```swift
var onPreviousFormation: () -> Void = {}
var onNextFormation: () -> Void = {}
var isFirstFormation: Bool = false
var isLastFormation: Bool = false
```

- [ ] **Step 2: Add nav buttons to `SidebarTransportView` body**

Change the transport HStack in body (lines 342-346) from:

```swift
HStack(spacing: 16) {
    TransportControls.resetButton(player: player)
    TransportControls.playPauseButton(player: player)
    TransportControls.loopButton(player: player)
}
```

To:

```swift
HStack(spacing: 16) {
    TransportControls.previousFormationButton(disabled: isFirstFormation, action: onPreviousFormation)
    TransportControls.nextFormationButton(disabled: isLastFormation, action: onNextFormation)
    TransportControls.resetButton(player: player)
    TransportControls.playPauseButton(player: player)
    TransportControls.loopButton(player: player)
}
```

- [ ] **Step 3: Add navigation callbacks and state to `CompactTransitionPlaybackRailView`**

Add properties after `formationColor` (line 239):

```swift
var onPreviousFormation: () -> Void = {}
var onNextFormation: () -> Void = {}
var isFirstFormation: Bool = false
var isLastFormation: Bool = false
```

- [ ] **Step 4: Add nav buttons to `CompactTransitionPlaybackRailView` body**

Change the transport HStack (lines 272-276) from:

```swift
HStack(spacing: 8) {
    TransportControls.resetButton(player: player, size: 30)
    TransportControls.playPauseButton(player: player, size: 36)
    TransportControls.loopButton(player: player, size: 30)
}
```

To:

```swift
HStack(spacing: 8) {
    TransportControls.previousFormationButton(size: 28, disabled: isFirstFormation, action: onPreviousFormation)
    TransportControls.nextFormationButton(size: 28, disabled: isLastFormation, action: onNextFormation)
    TransportControls.resetButton(player: player, size: 30)
    TransportControls.playPauseButton(player: player, size: 36)
    TransportControls.loopButton(player: player, size: 30)
}
```

- [ ] **Step 5: Add navigation callbacks and state to `CompactTransitionPlaybackOverlayView`**

Add properties after `canEditPath` (line 196):

```swift
var onPreviousFormation: () -> Void = {}
var onNextFormation: () -> Void = {}
var isFirstFormation: Bool = false
var isLastFormation: Bool = false
```

- [ ] **Step 6: Build to verify**

Run:
```bash
xcodebuild -project FormationFlow.xcodeproj -scheme FormationFlow \
  -destination 'platform=iOS Simulator,id=4676C328-77F6-47FA-85E1-B6E327B0E17C' build
```
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add FormationFlow/TransitionViews.swift
git commit -m "feat: add prev/next formation nav to all transport views"
```

---

### Task 6: Formation Navigation — FloorGridView + FormationHomeView Wiring

**Files:**
- Modify: `FormationFlow/FloorGridView.swift:14-26` (FloorGridView properties)
- Modify: `FormationFlow/FloorGridView.swift:1099-1121` (CompactTransitionPlaybackRailView call site)
- Modify: `FormationFlow/FloorGridView.swift:1238` (compactTransportSheet)
- Modify: `FormationFlow/FormationHomeView.swift:181-193` (fullScreenFloor FloorGridView call site)
- Modify: `FormationFlow/FormationHomeView.swift:440-455` (detailContent FloorGridView call site)
- Modify: `FormationFlow/FormationHomeView.swift:292-303` (SidebarTransportView in regularSidebar)
- Modify: `FormationFlow/FormationHomeView.swift:377-385` (SidebarTransportView in compact)
- Modify: `FormationFlow/FormationHomeView.swift:929-935` (add goToPreviousFormation)

- [ ] **Step 1: Add callbacks and state to `FloorGridView`**

After `onResetRoutine` (line 26), add:

```swift
var onPreviousFormation: (() -> Void)?
var onNextFormation: (() -> Void)?
var isFirstFormation: Bool = true
var isLastFormation: Bool = true
```

- [ ] **Step 2: Wire nav to `CompactTransitionPlaybackRailView` in FloorGridView**

In the `CompactTransitionPlaybackRailView` call (lines 1105-1118), add after `formationColor: currentFormationColor`:

```swift
onPreviousFormation: { onPreviousFormation?() },
onNextFormation: { onNextFormation?() },
isFirstFormation: isFirstFormation,
isLastFormation: isLastFormation
```

- [ ] **Step 3: Wire nav to `compactTransportSheet` in FloorGridView**

Find the `TransitionTransportSidebarView` inside `compactTransportSheet` (around line 1241). After the existing parameters, ensure the transport sidebar also gets the nav callbacks. Since `compactTransportSheet` uses `TransitionTransportSidebarView`, check if that view also needs the nav props — if it uses `SidebarTransportView` internally or has its own transport row, wire accordingly.

Look at the actual `TransitionTransportSidebarView` body — it has its own `transportControls` HStack at line 155. It needs the same treatment as `SidebarTransportView`. Add:

```swift
var onPreviousFormation: () -> Void = {}
var onNextFormation: () -> Void = {}
var isFirstFormation: Bool = false
var isLastFormation: Bool = false
```

And update its `transportControls` HStack (line 155-159) to include the nav buttons, same pattern as `SidebarTransportView`.

- [ ] **Step 4: Add `goToPreviousFormation` and `goToNextFormation` to `FormationHomeView`**

After `cycleToNextFormation` (line 935), add:

```swift
private func goToPreviousFormation() {
    let formations = store.routine.formations
    guard formations.count > 1 else { return }
    let currentIndex = formations.firstIndex(where: { $0.id == selectedFormationID }) ?? 0
    guard currentIndex > 0 else { return }
    selectedFormationID = formations[currentIndex - 1].id
}

private func goToNextFormation() {
    let formations = store.routine.formations
    guard formations.count > 1 else { return }
    let currentIndex = formations.firstIndex(where: { $0.id == selectedFormationID }) ?? 0
    guard currentIndex < formations.count - 1 else { return }
    selectedFormationID = formations[currentIndex + 1].id
}
```

- [ ] **Step 5: Add `isFirstFormation` / `isLastFormation` computed properties to `FormationHomeView`**

Near the other computed formation properties, add:

```swift
private var isFirstFormation: Bool {
    guard let selectedFormationID else { return true }
    return store.routine.formations.first?.id == selectedFormationID
}

private var isLastFormation: Bool {
    guard let selectedFormationID else { return true }
    return store.routine.formations.last?.id == selectedFormationID
}
```

- [ ] **Step 6: Wire callbacks in `fullScreenFloor` FloorGridView call site**

In `fullScreenFloor` (line 182-193), add after `onCycleFormation: cycleToNextFormation,`:

```swift
onPreviousFormation: goToPreviousFormation,
onNextFormation: goToNextFormation,
isFirstFormation: isFirstFormation,
isLastFormation: isLastFormation,
```

- [ ] **Step 7: Wire callbacks in `detailContent` FloorGridView call site**

In `detailContent` (line 442-455), add after `onCycleFormation: cycleToNextFormation,`:

```swift
onPreviousFormation: goToPreviousFormation,
onNextFormation: goToNextFormation,
isFirstFormation: isFirstFormation,
isLastFormation: isLastFormation,
```

- [ ] **Step 8: Wire callbacks in `SidebarTransportView` call sites in FormationHomeView**

In `regularSidebar` (line 294) and compact sidebar (line 379), the `SidebarTransportView` calls need the new params. Add after `canEditPath`:

```swift
onPreviousFormation: goToPreviousFormation,
onNextFormation: goToNextFormation,
isFirstFormation: isFirstFormation,
isLastFormation: isLastFormation
```

- [ ] **Step 9: Build and launch on simulator**

Run:
```bash
xcodebuild -project FormationFlow.xcodeproj -scheme FormationFlow \
  -destination 'platform=iOS Simulator,id=4676C328-77F6-47FA-85E1-B6E327B0E17C' build
```
Expected: BUILD SUCCEEDED. Prev/next chevrons appear in transport controls, disabled at boundaries.

- [ ] **Step 10: Commit**

```bash
git add FormationFlow/FloorGridView.swift FormationFlow/FormationHomeView.swift FormationFlow/TransitionViews.swift
git commit -m "feat: wire formation prev/next navigation through all views

Adds goToPreviousFormation/goToNextFormation in FormationHomeView,
threads callbacks through FloorGridView to all transport view variants.
Buttons disable at first/last formation boundaries."
```

---

### Task 7: Visual Polish & Simulator Verification

**Files:**
- All previously modified files (read-only verification pass)

- [ ] **Step 1: Build, install, and launch on simulator**

```bash
xcodebuild -project FormationFlow.xcodeproj -scheme FormationFlow \
  -destination 'platform=iOS Simulator,id=4676C328-77F6-47FA-85E1-B6E327B0E17C' \
  build

xcrun simctl boot 4676C328-77F6-47FA-85E1-B6E327B0E17C 2>/dev/null; \
xcrun simctl install 4676C328-77F6-47FA-85E1-B6E327B0E17C \
  ~/Library/Developer/Xcode/DerivedData/FormationFlow-*/Build/Products/Debug-iphonesimulator/FormationFlow.app && \
xcrun simctl launch 4676C328-77F6-47FA-85E1-B6E327B0E17C com.ianrichardson.formationflow
```

- [ ] **Step 2: Manual verification checklist**

Verify in simulator:
1. Create 3+ formations with athletes placed differently
2. Select formation 2 — ghost dashed paths from formation 1→2 visible, gradient opacity stronger near current positions
3. Hollow circles visible at prior formation positions
4. Colored paths to formation 3 render with full color
5. Select an athlete — selection stroke uses formation's rainbow color (not orange)
6. Lasso select — lasso uses formation's rainbow color
7. Prev/next buttons in transport controls work, disable at boundaries
8. Switch between formations — accent color changes with each formation

- [ ] **Step 3: Adjust opacity values if needed**

If ghost paths are too visible or too faint, tune:
- `0.03 + 0.07 * segmentProgress` in `drawGhostTransitionPaths` (target: barely visible at start, subtly visible at end)
- `0.08` on hollow start circles
- `0.07` on simple path fallback

- [ ] **Step 4: Final commit if adjustments were made**

```bash
git add -A
git commit -m "polish: tune ghost path opacity values after visual testing"
```
