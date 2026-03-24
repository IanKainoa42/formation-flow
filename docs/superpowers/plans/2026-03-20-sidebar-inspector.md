# Sidebar Inspector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the athlete inspector panel from a right-edge canvas overlay into the left sidebar (below the formation list), matching the existing transport controls pattern.

**Architecture:** Lift `selectedAthleteIDs` out of `FloorGridView` into `RoutineWorkspaceView` via a `@Binding`. The sidebar in `RoutineWorkspaceView` renders the inspector panel below the formation list when selection is non-empty. The right-edge overlay and "Inspect" button in `FloorGridView` are removed for regular (non-compact) layout. Compact/phone layout keeps the existing sheet behavior unchanged.

**Tech Stack:** SwiftUI, no new dependencies

---

### Task 1: Lift selectedAthleteIDs to RoutineWorkspaceView

**Files:**
- Modify: `FormationFlow/FormationHomeView.swift` (RoutineWorkspaceView)
- Modify: `FormationFlow/FloorGridView.swift`

This task makes the selection state shared so the sidebar can react to it.

- [ ] **Step 1: Add selectedAthleteIDs state to RoutineWorkspaceView**

In `FormationHomeView.swift`, add a new `@State` property to `RoutineWorkspaceView`:

```swift
@State private var selectedAthleteIDs: Set<UUID> = []
```

Add it after the existing `@State` declarations (around line 16).

- [ ] **Step 2: Convert FloorGridView's selectedAthleteIDs from @State to @Binding**

In `FloorGridView.swift`, change line 19 from:

```swift
@State private var selectedAthleteIDs: Set<UUID> = []
```

to:

```swift
@Binding var selectedAthleteIDs: Set<UUID>
```

- [ ] **Step 3: Pass the binding from RoutineWorkspaceView to FloorGridView**

In `FormationHomeView.swift`, update the `FloorGridView` initializer in `detailContent(for:formationID:compact:)` (around line 319) to pass the binding:

```swift
let editor = FloorGridView(
    store: store,
    selectedAthleteIDs: $selectedAthleteIDs,
    formationID: formationID,
    onDuplicateAsNext: duplicateSelectedFormation,
    player: previewSession.player,
    startFormationID: previewTransitionPair?.start.id,
    endFormationID: previewTransitionPair?.end.id
)
```

- [ ] **Step 4: Clear selection when formation changes in RoutineWorkspaceView**

In `FormationHomeView.swift`, add to the existing `onChange(of: selectedFormationID)` handler (around line 91):

```swift
.onChange(of: selectedFormationID) { _, _ in
    selectedAthleteIDs = []
    previewReferenceMode = smartPickReferenceMode()
    refreshPreviewSession()
}
```

- [ ] **Step 5: Build to verify compilation**

Run:
```bash
xcodebuild -project FormationFlow.xcodeproj -scheme FormationFlow \
  -destination 'platform=iOS Simulator,id=4676C328-77F6-47FA-85E1-B6E327B0E17C' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add FormationFlow/FormationHomeView.swift FormationFlow/FloorGridView.swift
git commit -m "refactor: lift selectedAthleteIDs to RoutineWorkspaceView via binding"
```

---

### Task 2: Extract inspectorPanel into a standalone view

**Files:**
- Modify: `FormationFlow/FloorGridView.swift`
- Modify: `FormationFlow/AthleteDetailPanel.swift`

The inspector panel logic currently lives inside `FloorGridView` and depends on its local state. Extract it into a self-contained view that can be hosted by both `FloorGridView` (compact sheet) and `RoutineWorkspaceView` (sidebar).

- [ ] **Step 1: Create SidebarInspectorView in AthleteDetailPanel.swift**

Add a new view at the bottom of `AthleteDetailPanel.swift` that wraps the inspector content. It takes all its data as parameters:

```swift
struct SidebarInspectorView: View {
    let store: RoutineStore
    let formationID: UUID
    @Binding var selectedAthleteIDs: Set<UUID>
    var isCompactLayout: Bool = false

    // Transition context (nil when no adjacent formation)
    var player: TransitionPlayer?
    var startFormationID: UUID?
    var endFormationID: UUID?

    // Callbacks for actions that FloorGridView still manages
    var onSwap: () -> Void = {}
    var onDeleteAthlete: () -> Void = {}

    @State private var isSwapMode = false

    private var selectedAthleteID: UUID? {
        selectedAthleteIDs.count == 1 ? selectedAthleteIDs.first : nil
    }

    private var selectedRosterAthlete: RosterAthlete? {
        guard let selectedAthleteID else { return nil }
        return store.routine.roster.first(where: { $0.id == selectedAthleteID })
    }

    private var formation: Formation? {
        guard let idx = store.formationIndex(id: formationID) else { return nil }
        return store.routine.formations[idx]
    }

    private var selectedPlacement: FormationPlacement? {
        guard let selectedAthleteID, let formation else { return nil }
        return formation.placements.first(where: { $0.athleteID == selectedAthleteID })
    }

    var body: some View {
        // Will be fleshed out in Step 2
        inspectorContent
    }

    @ViewBuilder
    private var inspectorContent: some View {
        if let selectedRosterAthlete, let selectedPlacement {
            AthleteInspectorView(
                athlete: selectedRosterAthlete,
                position: selectedPlacement.position,
                isSwapMode: isSwapMode,
                formationCount: store.routine.formations.count,
                formationName: formation?.name ?? "Formation",
                compactLayout: isCompactLayout,
                onUpdateLabel: { newLabel in
                    store.mutateRosterAthlete(id: selectedRosterAthlete.id) { athlete in
                        athlete.label = newLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? athlete.label
                            : newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                },
                onUpdateRole: { newRole in
                    store.mutateRosterAthlete(id: selectedRosterAthlete.id) { athlete in
                        athlete.role = newRole
                    }
                },
                onSwap: onSwap,
                onDelete: onDeleteAthlete,
                onClearSelection: {
                    selectedAthleteIDs = []
                }
            )
        } else if selectedAthleteIDs.count > 1 {
            MultiSelectionInspectorView(
                count: selectedAthleteIDs.count,
                compactLayout: isCompactLayout,
                onClearSelection: { selectedAthleteIDs = [] }
            )
        } else {
            EmptyInspectorView(
                title: "Inspector",
                message: "Select one athlete to edit its label, role, and actions. Multi-select to move groups together.",
                compactLayout: isCompactLayout
            )
        }
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run:
```bash
xcodebuild -project FormationFlow.xcodeproj -scheme FormationFlow \
  -destination 'platform=iOS Simulator,id=4676C328-77F6-47FA-85E1-B6E327B0E17C' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add FormationFlow/AthleteDetailPanel.swift FormationFlow/FloorGridView.swift
git commit -m "refactor: extract SidebarInspectorView for reuse in sidebar"
```

---

### Task 3: Add inspector to the left sidebar

**Files:**
- Modify: `FormationFlow/FormationHomeView.swift`

- [ ] **Step 1: Add the inspector section to regularSidebar**

In `FormationHomeView.swift`, in the `regularSidebar` computed property (around line 182), add the inspector below the existing transport/hint section. The full `VStack` should end like this — add the inspector block between the transport section and the closing `}` of the VStack:

```swift
// After the transport/hint if-else block and before the closing }
if !selectedAthleteIDs.isEmpty, let selectedFormationID {
    Divider()
    SidebarInspectorView(
        store: store,
        formationID: selectedFormationID,
        selectedAthleteIDs: $selectedAthleteIDs,
        player: previewSession.player,
        startFormationID: previewTransitionPair?.start.id,
        endFormationID: previewTransitionPair?.end.id
    )
    .frame(maxHeight: 400)
}
```

- [ ] **Step 2: Build to verify compilation**

Run:
```bash
xcodebuild -project FormationFlow.xcodeproj -scheme FormationFlow \
  -destination 'platform=iOS Simulator,id=4676C328-77F6-47FA-85E1-B6E327B0E17C' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add FormationFlow/FormationHomeView.swift
git commit -m "feat: show inspector panel in left sidebar when athlete selected"
```

---

### Task 4: Remove the right-edge overlay inspector on regular layout

**Files:**
- Modify: `FormationFlow/FloorGridView.swift`

- [ ] **Step 1: Remove the trailing overlay inspector from editorBody**

In `FloorGridView.swift`, in the `editorBody` computed property (around line 462-481), replace the regular layout's canvas + overlay block with just the canvas. Change:

```swift
} else {
    canvasArea
        .overlay(alignment: .trailing) {
            if showingPinnedInspector {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color(uiColor: .separator).opacity(0.35))
                        .frame(width: 1)

                    inspectorPanel
                        .frame(width: 320)
                        .frame(maxHeight: .infinity)
                }
                .background(.thinMaterial)
                .shadow(color: .black.opacity(0.12), radius: 14, x: -4, y: 0)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: selectedAthleteIDs.isEmpty)
}
```

to:

```swift
} else {
    canvasArea
}
```

- [ ] **Step 2: Remove the "Inspect" toggle button from the regular controlStrip**

In the `controlStrip` computed property (around line 584-598), remove the `if showingPinnedInspector` / `else` block that renders the "Inspect" / "Hide Inspector" button on regular layout. Remove the entire block:

```swift
if isCompactLayout {
    compactOverflowMenu
} else {
    if showingPinnedInspector {
        Button(action: togglePinnedInspector) {
            Label(regularInspectButtonTitle, systemImage: "slider.horizontal.3")
        }
        .buttonStyle(.borderedProminent)
    } else {
        Button(action: togglePinnedInspector) {
            Label(regularInspectButtonTitle, systemImage: "slider.horizontal.3")
        }
        .buttonStyle(.bordered)
        .disabled(selectedAthleteIDs.isEmpty)
    }
    ...
```

Replace it with just the compact check — keep the Roster/Reset buttons for regular layout:

```swift
if isCompactLayout {
    compactOverflowMenu
} else {
    Button(action: { showingRosterSheet = true }) {
        Label("Manage Roster", systemImage: "list.bullet.rectangle")
    }
    .buttonStyle(.bordered)

    Button(action: resetView) {
        Label("Reset View", systemImage: "arrow.counterclockwise")
    }
    .buttonStyle(.bordered)
```

(Keep any remaining buttons that were after the inspect button.)

- [ ] **Step 3: Clean up dead code**

Remove `showingPinnedInspector`, `togglePinnedInspector()`, `regularInspectButtonTitle`, and the `inspectorPanel` computed property from `FloorGridView.swift` — these are no longer used on regular layout. Keep `compactInspectorSheet` and `showingInspectorSheet` since compact layout still uses them.

Also remove `inspectorScrollOffset`, `inspectorContentHeight`, `inspectorViewportHeight`, and `inspectorScrollIndicator` if they were only used by `inspectorPanel`.

- [ ] **Step 4: Build to verify compilation**

Run:
```bash
xcodebuild -project FormationFlow.xcodeproj -scheme FormationFlow \
  -destination 'platform=iOS Simulator,id=4676C328-77F6-47FA-85E1-B6E327B0E17C' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add FormationFlow/FloorGridView.swift
git commit -m "feat: remove right-edge inspector overlay on iPad, now in sidebar"
```

---

### Task 5: Wire up swap and delete actions through the sidebar

**Files:**
- Modify: `FormationFlow/FormationHomeView.swift`
- Modify: `FormationFlow/FloorGridView.swift`

The swap and delete actions in the inspector need to trigger behavior in `FloorGridView` (swap mode, athlete deletion). Add callbacks.

- [ ] **Step 1: Add callback properties to FloorGridView**

Add two new closure properties to `FloorGridView`:

```swift
var onSwapRequested: (() -> Void)?
var onDeleteAthleteRequested: (() -> Void)?
```

Wire `FloorGridView`'s existing `toggleSwapMode()` and `deleteSelectedAthlete()` to be callable from these, or expose them. The simplest approach: when the sidebar inspector's swap/delete callbacks fire, they set state that `FloorGridView` reacts to.

Alternatively, since `FloorGridView` already has `isSwapMode` state, lift `isSwapMode` to a `@Binding` as well, and the sidebar inspector's "Swap" button toggles it directly.

For delete: add a `@Binding var pendingAthleteDelete: Bool` that triggers the existing `deleteSelectedAthlete()` in `FloorGridView`.

- [ ] **Step 2: Update RoutineWorkspaceView to manage the swap/delete bindings**

Add state in `RoutineWorkspaceView`:

```swift
@State private var isSwapMode = false
@State private var pendingAthleteDelete = false
```

Pass to both `FloorGridView` and `SidebarInspectorView`.

- [ ] **Step 3: Update SidebarInspectorView to use the bindings**

Pass `onSwap` and `onDeleteAthlete` closures that toggle the shared state.

- [ ] **Step 4: Build and verify**

Run:
```bash
xcodebuild -project FormationFlow.xcodeproj -scheme FormationFlow \
  -destination 'platform=iOS Simulator,id=4676C328-77F6-47FA-85E1-B6E327B0E17C' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add FormationFlow/FormationHomeView.swift FormationFlow/FloorGridView.swift FormationFlow/AthleteDetailPanel.swift
git commit -m "feat: wire swap and delete actions from sidebar inspector to floor grid"
```

---

### Task 6: Visual polish and sidebar scroll behavior

**Files:**
- Modify: `FormationFlow/FormationHomeView.swift`

- [ ] **Step 1: Make the sidebar scrollable**

Wrap the entire sidebar VStack content in a `ScrollView` so the formation list + transport + inspector can scroll together when content is tall. Or better: keep the formation list as a `List` (already scrollable) and put the inspector in a fixed-height section at the bottom with its own scroll.

The cleanest approach: use the existing `VStack(spacing: 0)` structure. The formation list `List` handles its own scrolling. The transport and inspector sections at the bottom are fixed-position (like a toolbar), and the inspector section itself scrolls internally via its existing `ScrollView`.

Add `.frame(minHeight: 200, maxHeight: 400)` to the inspector to prevent it from pushing the formation list off screen.

- [ ] **Step 2: Add slide animation**

Wrap the inspector appearance in `withAnimation`:

```swift
if !selectedAthleteIDs.isEmpty, let selectedFormationID {
    Divider()
    SidebarInspectorView(...)
        .frame(minHeight: 200, maxHeight: 400)
        .transition(.move(edge: .bottom).combined(with: .opacity))
}
```

And add `.animation(.easeInOut(duration: 0.22), value: selectedAthleteIDs.isEmpty)` to the sidebar VStack.

- [ ] **Step 3: Build and verify**

Run:
```bash
xcodebuild -project FormationFlow.xcodeproj -scheme FormationFlow \
  -destination 'platform=iOS Simulator,id=4676C328-77F6-47FA-85E1-B6E327B0E17C' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add FormationFlow/FormationHomeView.swift
git commit -m "feat: add scroll constraints and slide animation to sidebar inspector"
```
