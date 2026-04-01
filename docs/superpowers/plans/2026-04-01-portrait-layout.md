# Portrait Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the sidebar in portrait orientation with a static action bar + formation thumbnail strip, giving the court full width.

**Architecture:** New `PortraitActionBar` and `FormationThumbnailStrip` views compose into a portrait-specific layout branch in `RoutineWorkspaceView`. Portrait detection uses `verticalSizeClass` + `horizontalSizeClass`. The existing `FloorGridView` control strip is hidden when the portrait action bar is active via a new `hideControlStrip` parameter.

**Tech Stack:** SwiftUI, Canvas API for thumbnail rendering

**Spec:** `docs/superpowers/specs/2026-04-01-portrait-layout-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `FormationFlow/FormationThumbnailView.swift` | Create | Single formation thumbnail — mini Canvas with athlete dots |
| `FormationFlow/FormationThumbnailStrip.swift` | Create | Horizontal scroll strip of thumbnails with arrows and add button |
| `FormationFlow/PortraitActionBar.swift` | Create | Static non-scrolling toolbar with icon buttons |
| `FormationFlow/FormationHomeView.swift` | Modify | Add portrait layout branch, wire up new views |
| `FormationFlow/FloorGridView.swift` | Modify | Add `hideControlStrip` param to suppress control strip in portrait |

---

### Task 1: FormationThumbnailView — Mini Canvas Renderer

**Files:**
- Create: `FormationFlow/FormationThumbnailView.swift`

This view renders a single formation as a tiny court with colored dots.

- [ ] **Step 1: Create FormationThumbnailView.swift**

```swift
import SwiftUI

struct FormationThumbnailView: View {
    let athletes: [RenderedAthlete]
    let isSelected: Bool
    let accentColor: Color

    private let thumbnailWidth: CGFloat = 52
    private let thumbnailHeight: CGFloat = 40

    var body: some View {
        Canvas { context, size in
            for athlete in athletes {
                let x = athlete.position.x * size.width / CourtConstants.width
                let y = athlete.position.y * size.height / CourtConstants.height
                let dotRadius: CGFloat = 3
                let rect = CGRect(
                    x: x - dotRadius,
                    y: y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                )
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(athlete.role.color)
                )
            }
        }
        .frame(width: thumbnailWidth, height: thumbnailHeight)
        .background(Color(uiColor: .systemBackground).opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? accentColor : Color.gray.opacity(0.4), lineWidth: isSelected ? 2 : 1)
        )
    }
}

#Preview {
    FormationThumbnailView(
        athletes: [
            RenderedAthlete(id: UUID(), label: "K1", role: .base, position: CGPoint(x: 36, y: 20)),
            RenderedAthlete(id: UUID(), label: "F1", role: .flyer, position: CGPoint(x: 36, y: 28)),
            RenderedAthlete(id: UUID(), label: "S1", role: .spotter, position: CGPoint(x: 28, y: 36))
        ],
        isSelected: true,
        accentColor: .blue
    )
    .padding()
    .background(.black)
}
```

- [ ] **Step 2: Build to verify compilation**

Run:
```bash
xcodebuild -project FormationFlow.xcodeproj -scheme FormationFlow \
  -destination 'platform=iOS Simulator,id=4676C328-77F6-47FA-85E1-B6E327B0E17C' build
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add FormationFlow/FormationThumbnailView.swift
git commit -m "feat: add FormationThumbnailView mini-canvas renderer"
```

---

### Task 2: FormationThumbnailStrip — Horizontal Scrolling Strip

**Files:**
- Create: `FormationFlow/FormationThumbnailStrip.swift`

Horizontal scroll of formation thumbnails with transition arrows, labels, add button, and context menus.

- [ ] **Step 1: Create FormationThumbnailStrip.swift**

```swift
import SwiftUI

struct FormationThumbnailStrip: View {
    @ObservedObject var store: RoutineStore
    @Binding var selectedFormationID: UUID?
    let canAddFormation: Bool
    let onAddFormation: () -> Void
    let onRenameFormation: (Formation) -> Void
    let onDeleteFormation: (UUID) -> Void
    let onDuplicateFormation: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(store.routine.formations.enumerated()), id: \.element.id) { index, formation in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.5))
                        }

                        let isSelected = formation.id == selectedFormationID
                        let accentColor = TransitionEndpointMarkerRenderItem.rainbowColor(forIndex: index)

                        Button {
                            selectedFormationID = formation.id
                        } label: {
                            VStack(spacing: 3) {
                                FormationThumbnailView(
                                    athletes: store.renderedAthletes(for: formation.id),
                                    isSelected: isSelected,
                                    accentColor: accentColor
                                )

                                Text(formation.name)
                                    .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                                    .foregroundColor(isSelected ? .primary : .secondary)
                                    .lineLimit(1)
                                    .frame(maxWidth: 56)
                            }
                        }
                        .buttonStyle(.plain)
                        .id(formation.id)
                        .contextMenu {
                            Button {
                                onRenameFormation(formation)
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button(action: onDuplicateFormation) {
                                Label("Duplicate as Next", systemImage: "plus.square.on.square")
                            }
                            Button(role: .destructive) {
                                onDeleteFormation(formation.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }

                    // Add formation button
                    Button(action: onAddFormation) {
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                                .foregroundColor(.secondary.opacity(0.4))
                                .frame(width: 52, height: 40)
                                .overlay {
                                    Image(systemName: canAddFormation ? "plus" : "lock.fill")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                            Text("Add")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .onChange(of: selectedFormationID) { _, newID in
                if let newID {
                    withAnimation {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                }
            }
        }
        .background(.bar)
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run:
```bash
xcodebuild -project FormationFlow.xcodeproj -scheme FormationFlow \
  -destination 'platform=iOS Simulator,id=4676C328-77F6-47FA-85E1-B6E327B0E17C' build
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add FormationFlow/FormationThumbnailStrip.swift
git commit -m "feat: add FormationThumbnailStrip horizontal formation picker"
```

---

### Task 3: PortraitActionBar — Static Toolbar

**Files:**
- Create: `FormationFlow/PortraitActionBar.swift`

Non-scrolling action bar with icon buttons. All actions are closures passed in from the parent.

- [ ] **Step 1: Create PortraitActionBar.swift**

```swift
import SwiftUI

struct PortraitActionBar: View {
    let onAddAthlete: () -> Void
    let onShowRoster: () -> Void
    let onShowNotes: () -> Void
    let onUndo: () -> Void
    let onTogglePaths: () -> Void
    let onSharePreview: () -> Void
    let showTransitionPaths: Bool
    let hasTransition: Bool
    let undoDisabled: Bool
    let hasNotes: Bool

    // Collision badges
    let collidingCount: Int
    let onCycleCollision: () -> Void
    let pathCollidingCount: Int
    let onCyclePathCollision: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Left group
            HStack(spacing: 2) {
                if collidingCount > 0 {
                    Button(action: onCycleCollision) {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("\(collidingCount)")
                        }
                        .font(.caption.weight(.bold))
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.red.opacity(0.15), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Athlete spacing alerts")
                }

                if showTransitionPaths, pathCollidingCount > 0 {
                    Button(action: onCyclePathCollision) {
                        HStack(spacing: 4) {
                            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                            Text("\(pathCollidingCount)")
                        }
                        .font(.caption.weight(.bold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.orange.opacity(0.15), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Path crossing alerts")
                }

                Button(action: onAddAthlete) {
                    Label("Athlete", systemImage: "plus.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button(action: onShowRoster) {
                    Image(systemName: "list.bullet.rectangle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Roster")

                Button(action: onShowNotes) {
                    Image(systemName: "note.text")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Notes")
                .overlay(alignment: .topTrailing) {
                    if hasNotes {
                        Circle()
                            .fill(.orange)
                            .frame(width: 6, height: 6)
                            .offset(x: 2, y: -2)
                    }
                }

                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(undoDisabled)
                .accessibilityLabel("Undo move")

                if hasTransition {
                    Button(action: onTogglePaths) {
                        Text("I")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .background(showTransitionPaths ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityLabel(showTransitionPaths ? "Hide paths" : "Show paths")
                }
            }

            Spacer()

            // Right: share
            if hasTransition {
                Button(action: onSharePreview) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Share preview")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run:
```bash
xcodebuild -project FormationFlow.xcodeproj -scheme FormationFlow \
  -destination 'platform=iOS Simulator,id=4676C328-77F6-47FA-85E1-B6E327B0E17C' build
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add FormationFlow/PortraitActionBar.swift
git commit -m "feat: add PortraitActionBar static toolbar for portrait mode"
```

---

### Task 4: FloorGridView — Add hideControlStrip Parameter

**Files:**
- Modify: `FormationFlow/FloorGridView.swift:14-30` (struct properties)
- Modify: `FormationFlow/FloorGridView.swift:600-620` (editorBody)

Add a `hideControlStrip` parameter so the portrait layout can suppress the built-in scrolling control strip (since `PortraitActionBar` replaces it).

- [ ] **Step 1: Add the parameter to FloorGridView**

In `FormationFlow/FloorGridView.swift`, add a new property after the existing parameters (around line 30, after `isLastFormation`):

```swift
    var hideControlStrip: Bool = false
```

The default `false` means all existing call sites continue working without changes.

- [ ] **Step 2: Use the parameter in editorBody**

In `FormationFlow/FloorGridView.swift`, modify the `editorBody` computed property (around line 600). Change the non-phone branch from:

```swift
            } else {
                VStack(spacing: 0) {
                    controlStrip
                    Divider()

                    if renderedAthletes.isEmpty {
                        emptyState
                    } else {
                        canvasArea
                    }
                }
            }
```

to:

```swift
            } else {
                VStack(spacing: 0) {
                    if !hideControlStrip {
                        controlStrip
                        Divider()
                    }

                    if renderedAthletes.isEmpty {
                        emptyState
                    } else {
                        canvasArea
                    }
                }
            }
```

- [ ] **Step 3: Build to verify compilation**

Run:
```bash
xcodebuild -project FormationFlow.xcodeproj -scheme FormationFlow \
  -destination 'platform=iOS Simulator,id=4676C328-77F6-47FA-85E1-B6E327B0E17C' build
```
Expected: BUILD SUCCEEDED (existing behavior unchanged since default is `false`)

- [ ] **Step 4: Commit**

```bash
git add FormationFlow/FloorGridView.swift
git commit -m "feat: add hideControlStrip parameter to FloorGridView"
```

---

### Task 5: FormationHomeView — Portrait Layout Branch

**Files:**
- Modify: `FormationFlow/FormationHomeView.swift:33-41` (isCompactLayout / isPortrait)
- Modify: `FormationFlow/FormationHomeView.swift:92-104` (workspaceContent)
- Modify: `FormationFlow/FormationHomeView.swift` (add portraitWorkspace computed property)

This is the main integration task. Add portrait detection and a new `portraitWorkspace` layout that composes the action bar, thumbnail strip, and floor grid without a sidebar.

- [ ] **Step 1: Add verticalSizeClass and isPortrait to RoutineWorkspaceView**

In `FormationFlow/FormationHomeView.swift`, add a `verticalSizeClass` environment variable near the existing `horizontalSizeClass` (line 10):

```swift
    @Environment(\.verticalSizeClass) private var verticalSizeClass
```

Add an `isPortrait` computed property after `isPhoneLayout` (around line 49):

```swift
    private var isPortrait: Bool {
        verticalSizeClass == .regular
    }
```

- [ ] **Step 2: Modify workspaceContent to add portrait branch**

Change `workspaceContent` (around line 92) from:

```swift
    @ViewBuilder
    private var workspaceContent: some View {
        if isFullScreen && !isCompactLayout {
            if let selectedFormationID {
                fullScreenFloor(formationID: selectedFormationID)
            } else {
                regularWorkspace
            }
        } else if isCompactLayout {
            compactWorkspace
        } else {
            regularWorkspace
        }
    }
```

to:

```swift
    @ViewBuilder
    private var workspaceContent: some View {
        if isFullScreen && !isCompactLayout {
            if let selectedFormationID {
                fullScreenFloor(formationID: selectedFormationID)
            } else {
                regularWorkspace
            }
        } else if isPortrait {
            portraitWorkspace
        } else if isCompactLayout {
            compactWorkspace
        } else {
            regularWorkspace
        }
    }
```

The `isPortrait` check comes before `isCompactLayout` so that portrait iPad (which has `horizontalSizeClass == .regular`) and portrait iPhone (which has `horizontalSizeClass == .compact`) both use the new layout. When rotated to landscape, `verticalSizeClass` becomes `.compact`, so `isPortrait` is `false` and the existing landscape paths take over.

- [ ] **Step 3: Add portraitWorkspace computed property**

Add the following after the `compactWorkspace` property (around line 275):

```swift
    // MARK: - Portrait Workspace

    private var portraitWorkspace: some View {
        NavigationStack {
            portraitContent
                .navigationTitle(store.routine.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        Button {
                            showingRoutinePlayback = true
                        } label: {
                            Image(systemName: "play.circle")
                        }
                        .disabled(store.routine.formations.count < 2)
                        .accessibilityLabel("Play routine")

                        Button(action: addFormation) {
                            Image(systemName: canAddFormation ? "plus" : "lock.fill")
                        }
                        .accessibilityLabel(canAddFormation ? "Add formation" : "Upgrade to Pro to add formation")
                    }
                }
                .confirmationDialog(
                    "Reset routine?",
                    isPresented: $showingResetConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Reset Routine", role: .destructive) {
                        authenticateAndResetRoutine()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This clears the roster, formations, notes, and transition data, then starts over with one empty formation.")
                }
        }
    }

    @ViewBuilder
    private var portraitContent: some View {
        if let selectedFormationID {
            portraitFloor(formationID: selectedFormationID)
        } else {
            ContentUnavailableView("No formation selected", systemImage: "rectangle.grid.1x2")
                .onAppear {
                    selectedFormationID = store.routine.formations.first?.id
                }
        }
    }

    private func portraitFloor(formationID: UUID) -> some View {
        VStack(spacing: 0) {
            FormationThumbnailStrip(
                store: store,
                selectedFormationID: $selectedFormationID,
                canAddFormation: canAddFormation,
                onAddFormation: addFormation,
                onRenameFormation: { formation in beginRenaming(formation) },
                onDeleteFormation: { id in requestFormationDeletion([id]) },
                onDuplicateFormation: duplicateSelectedFormation
            )
            Divider()

            FloorGridView(
                store: store,
                selectedAthleteIDs: $selectedAthleteIDs,
                isSwapMode: $isSwapMode,
                triggerDeleteAthlete: $triggerDeleteAthlete,
                formationID: formationID,
                onCycleFormation: cycleToNextFormation,
                onDuplicateAsNext: duplicateSelectedFormation,
                onRenameFormation: {
                    if let f = selectedFormation { beginRenaming(f) }
                },
                onDeleteFormation: { requestFormationDeletion([formationID]) },
                onResetRoutine: { showingResetConfirmation = true },
                onPreviousFormation: goToPreviousFormation,
                onNextFormation: goToNextFormation,
                isFirstFormation: isFirstFormation,
                isLastFormation: isLastFormation,
                player: previewSession.player,
                startFormationID: previewTransitionPair?.start.id,
                endFormationID: previewTransitionPair?.end.id,
                hideControlStrip: true
            )
        }
        .overlay(alignment: .bottom) {
            if let previewTransitionPair, let player = previewSession.player {
                CompactTransitionPlaybackOverlayView(
                    player: player,
                    startFormationName: previewTransitionPair.start.name,
                    endFormationName: previewTransitionPair.end.name,
                    onSwap: { isSwapMode.toggle() },
                    isSwapMode: isSwapMode,
                    canSwap: selectedAthleteIDs.count == 1,
                    canEditPath: selectedAthleteIDs.count == 1,
                    onPreviousFormation: goToPreviousFormation,
                    onNextFormation: goToNextFormation,
                    isFirstFormation: isFirstFormation,
                    isLastFormation: isLastFormation
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }
```

Note: The `PortraitActionBar` is not wired in this step. That happens in Task 6 after we verify the basic portrait layout works.

- [ ] **Step 4: Build to verify compilation**

Run:
```bash
xcodebuild -project FormationFlow.xcodeproj -scheme FormationFlow \
  -destination 'platform=iOS Simulator,id=4676C328-77F6-47FA-85E1-B6E327B0E17C' build
```
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Install and launch on simulator to verify portrait layout**

Run:
```bash
xcodebuild -project FormationFlow.xcodeproj -scheme FormationFlow \
  -destination 'platform=iOS Simulator,id=4676C328-77F6-47FA-85E1-B6E327B0E17C' \
  build -resultBundlePath /tmp/ff-build
xcrun simctl boot 4676C328-77F6-47FA-85E1-B6E327B0E17C 2>/dev/null; \
xcrun simctl install 4676C328-77F6-47FA-85E1-B6E327B0E17C \
  $(find /Users/ianrichardson/Library/Developer/Xcode/DerivedData -name "FormationFlow.app" -path "*/Debug-iphonesimulator/*" | head -1) && \
xcrun simctl launch 4676C328-77F6-47FA-85E1-B6E327B0E17C com.ianrichardson.formationflow
```

Verify: In portrait orientation, the sidebar is gone and the thumbnail strip appears at top. Court fills full width. Rotating to landscape restores sidebar.

- [ ] **Step 6: Commit**

```bash
git add FormationFlow/FormationHomeView.swift
git commit -m "feat: add portrait workspace layout with thumbnail strip"
```

---

### Task 6: Wire PortraitActionBar into Portrait Layout

**Files:**
- Modify: `FormationFlow/FormationHomeView.swift` (portraitFloor function)
- Modify: `FormationFlow/FloorGridView.swift` (expose state needed by action bar)

Wire the `PortraitActionBar` between the thumbnail strip and the floor grid. The action bar needs access to some state that currently lives inside `FloorGridView` (collision counts, undo stack, path toggle, notes indicator). We'll expose these via bindings or callbacks.

- [ ] **Step 1: Add PortraitActionBar inside FloorGridView editorBody**

The action bar needs access to `FloorGridView` internal state (collision counts, undo stack, path toggle). Rather than exposing all that via bindings, we place the `PortraitActionBar` inside `FloorGridView` as a replacement for `controlStrip` when `hideControlStrip` is true. This keeps all state access internal.

In `FormationFlow/FloorGridView.swift`, modify the `editorBody` non-phone branch. Change:

```swift
            } else {
                VStack(spacing: 0) {
                    if !hideControlStrip {
                        controlStrip
                        Divider()
                    }

                    if renderedAthletes.isEmpty {
                        emptyState
                    } else {
                        canvasArea
                    }
                }
            }
```

to:

```swift
            } else {
                VStack(spacing: 0) {
                    if hideControlStrip {
                        portraitActionBar
                        Divider()
                    } else {
                        controlStrip
                        Divider()
                    }

                    if renderedAthletes.isEmpty {
                        emptyState
                    } else {
                        canvasArea
                    }
                }
            }
```

- [ ] **Step 2: Add portraitActionBar computed property to FloorGridView**

Add the following inside `FloorGridView`, after the `controlStrip` property:

```swift
    private var portraitActionBar: some View {
        PortraitActionBar(
            onAddAthlete: addAthlete,
            onShowRoster: { showingRosterSheet = true },
            onShowNotes: { showingNotesSheet = true },
            onUndo: undoLastMove,
            onTogglePaths: { showTransitionPaths.toggle() },
            onSharePreview: shareTransitionPreview,
            showTransitionPaths: showTransitionPaths,
            hasTransition: hasTransition,
            undoDisabled: undoStack.isEmpty,
            hasNotes: formation?.hasCoachCardContent == true,
            collidingCount: collidingAthletes.count,
            onCycleCollision: {
                collisionCycleIndex = (collisionCycleIndex + 1) % max(collidingAthletes.count, 1)
                selectCollision(at: collisionCycleIndex)
            },
            pathCollidingCount: pathCollidingAthletes.count,
            onCyclePathCollision: {
                pathCollisionCycleIndex = (pathCollisionCycleIndex + 1) % max(pathCollidingAthletes.count, 1)
                selectPathCollision(at: pathCollisionCycleIndex)
            }
        )
    }
```

- [ ] **Step 3: Build to verify compilation**

Run:
```bash
xcodebuild -project FormationFlow.xcodeproj -scheme FormationFlow \
  -destination 'platform=iOS Simulator,id=4676C328-77F6-47FA-85E1-B6E327B0E17C' build
```
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Install and launch on simulator**

Run:
```bash
xcrun simctl install 4676C328-77F6-47FA-85E1-B6E327B0E17C \
  $(find /Users/ianrichardson/Library/Developer/Xcode/DerivedData -name "FormationFlow.app" -path "*/Debug-iphonesimulator/*" | head -1) && \
xcrun simctl launch 4676C328-77F6-47FA-85E1-B6E327B0E17C com.ianrichardson.formationflow
```

Verify in portrait:
- Action bar visible below thumbnail strip
- "+ Athlete" button works
- Roster/Notes/Undo icons work
- "I" toggle shows/hides paths
- Share button appears when transition exists
- Collision badges appear when athletes overlap
- Rotating to landscape shows normal control strip

- [ ] **Step 5: Commit**

```bash
git add FormationFlow/FloorGridView.swift
git commit -m "feat: wire PortraitActionBar into portrait layout"
```

---

### Task 7: Phone Portrait — Use Same Layout

**Files:**
- Modify: `FormationFlow/FloorGridView.swift:600-620` (editorBody phone branch)

Currently the phone branch in `editorBody` skips the control strip entirely and uses overlays. When `hideControlStrip` is true on phone, we want the portrait action bar to show at the top instead of the phone overlays handling everything.

- [ ] **Step 1: Add portrait action bar to phone branch**

In `FloorGridView.swift`, modify the phone branch of `editorBody` (around line 601). Change:

```swift
            if isPhoneLayout {
                if renderedAthletes.isEmpty {
                    emptyState
                } else {
                    canvasArea
                }
            }
```

to:

```swift
            if isPhoneLayout {
                VStack(spacing: 0) {
                    if hideControlStrip {
                        portraitActionBar
                        Divider()
                    }

                    if renderedAthletes.isEmpty {
                        emptyState
                    } else {
                        canvasArea
                    }
                }
            }
```

- [ ] **Step 2: Wire hideControlStrip for phone portrait in FormationHomeView**

In `FormationHomeView.swift`, the `compactDetailView` (used for phone navigation) should also pass `hideControlStrip: true` when portrait. Modify the `detailContent` function (around line 462) to pass the flag:

Change the `FloorGridView` constructor inside `detailContent` to include:

```swift
                hideControlStrip: isPortrait
```

after the `endFormationID` parameter.

Also modify `compactWorkspace` to use the portrait layout when `isPortrait` is true. In `workspaceContent`, the `isPortrait` check already comes first, so phone portrait will use `portraitWorkspace`. No additional changes needed — the routing is already correct.

- [ ] **Step 3: Build and verify**

Run:
```bash
xcodebuild -project FormationFlow.xcodeproj -scheme FormationFlow \
  -destination 'platform=iOS Simulator,id=4676C328-77F6-47FA-85E1-B6E327B0E17C' build
```
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add FormationFlow/FloorGridView.swift FormationFlow/FormationHomeView.swift
git commit -m "feat: apply portrait action bar to phone layout"
```

---

### Task 8: Visual Polish and Final Verification

**Files:**
- Modify: `FormationFlow/FormationThumbnailStrip.swift` (if needed)
- Modify: `FormationFlow/PortraitActionBar.swift` (if needed)

Install, test all orientations, and fix any visual issues.

- [ ] **Step 1: Build, install, and launch**

Run:
```bash
xcodebuild -project FormationFlow.xcodeproj -scheme FormationFlow \
  -destination 'platform=iOS Simulator,id=4676C328-77F6-47FA-85E1-B6E327B0E17C' build && \
xcrun simctl install 4676C328-77F6-47FA-85E1-B6E327B0E17C \
  $(find /Users/ianrichardson/Library/Developer/Xcode/DerivedData -name "FormationFlow.app" -path "*/Debug-iphonesimulator/*" | head -1) && \
xcrun simctl launch 4676C328-77F6-47FA-85E1-B6E327B0E17C com.ianrichardson.formationflow
```

- [ ] **Step 2: Screenshot portrait and landscape**

```bash
peekaboo image --app "Simulator" --path /tmp/ff-portrait.png
```

Rotate simulator to landscape and screenshot again:

```bash
peekaboo image --app "Simulator" --path /tmp/ff-landscape.png
```

- [ ] **Step 3: Verify checklist**

Portrait mode:
- [ ] No sidebar visible
- [ ] Thumbnail strip shows all formations with colored dots
- [ ] Selected formation has accent border
- [ ] Tapping thumbnail switches formation
- [ ] Action bar: "+ Athlete" button adds athlete
- [ ] Action bar: Roster icon opens roster sheet
- [ ] Action bar: Notes icon opens notes sheet
- [ ] Action bar: Undo icon works
- [ ] Action bar: "I" toggles paths (highlighted when active)
- [ ] Action bar: Share appears when transition exists
- [ ] Court fills full width
- [ ] Bottom transport overlay works for playback
- [ ] Long-press thumbnail shows context menu (rename, duplicate, delete)

Landscape mode:
- [ ] iPad: sidebar + detail layout (unchanged)
- [ ] iPhone: left rail layout (unchanged)

- [ ] **Step 4: Fix any visual issues found**

Address spacing, sizing, or interaction issues discovered during testing. Common things to check:
- Thumbnail strip scrolls to selected formation on switch
- Action bar buttons don't overflow on narrower devices
- Formation add button (`+` dashed) works correctly
- Transitions between portrait/landscape are smooth

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "polish: portrait layout visual refinements"
```
