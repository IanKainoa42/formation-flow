# Ghost Paths, Formation Accent Colors & Formation Navigation

**Date:** 2026-04-01
**Status:** Approved

## Summary

Three features that enhance the formation editor's visual feedback and navigation:

1. **Ghost transition paths** — low-opacity dashed paths showing how athletes arrived at their current positions (prior formation's transition)
2. **Formation-derived accent color** — replace hardcoded orange selection indicators with the current formation's rainbow color
3. **Formation navigation buttons** — prev/next chevrons in transport controls for stepping through formations

## Feature 1: Ghost Transition Paths

### Purpose

When editing formation N with a transition preview to N+1, coaches currently see colored paths showing where athletes are going. This feature adds a second layer showing where athletes came from (the N-1 → N transition), giving full context of movement flow.

### Data Source

`FloorGridView` computes `previousTransitionPaths: [TransitionPathRenderItem]` using `store.transitionPaths(from: prevFormationID, to: currentFormationID)`. Returns `[]` during playback (progress 0–1) — same optimization pattern as `previousFormationAthletes`.

### Canvas Input

New property on `FloorCanvasView`:

```swift
var ghostTransitionPaths: [TransitionPathRenderItem] = []
```

### Rendering

New method `drawGhostTransitionPaths(in:)` — drawn between `drawGhostAthletes` and `drawTrails` in the draw order.

**Path styling:**
- Color: white/gray
- Stroke: dashed `[4, 4]`, lineWidth 1
- Opacity gradient along path: ~3% at path start (where athlete came from) → ~10% at path end (where athlete arrived). Achieved by splitting each path into sub-segments with stepped opacity.
- Uses the same waypoint/Bezier/Catmull-Rom logic as regular paths, just with ghost styling.

**Start position markers:**
- Hollow circles (stroke only), radius ~6
- White at ~8% opacity, dashed stroke
- Shows where the athlete was in the prior formation

**No interactivity:**
- No handles, no arrows, no hit testing
- Purely informational overlay

**Existing ghost athletes** (filled circles at 7% opacity from `drawGhostAthletes`) remain unchanged — they complement the ghost paths.

## Feature 2: Formation-Derived Accent Color

### Purpose

Replace hardcoded `.orange` selection indicators with the current formation's rainbow color. This ties the visual identity of each formation to its position in the sequence, reinforcing the rainbow color language already used in thumbnails and endpoint markers.

### Rainbow Colors (existing)

```swift
// TransitionEndpointMarkerRenderItem.rainbowColors
[.red, .orange, .yellow, .green, .cyan, .blue, .indigo, .purple]
```

### Changes in FloorCanvasView

**`drawAthletes`:**
- Selected athlete stroke: `.orange` → `formationColor`
- Swap source ring: `.orange` → `formationColor`

**`drawTransitionPaths`:**
- Selected path color: `.orange` → `formationColor` (in the `isSelected ? .orange : .green` ternary)
- All selected handles, waypoint handles, "+" text: derive from `formationColor`

**Selection lasso:**
- Fill: `.orange.opacity(0.1)` → `formationColor.opacity(0.1)`
- Stroke: `.orange.opacity(0.45)` → `formationColor.opacity(0.45)`

### What Stays the Same

- Collision indicators: `.red`
- Unselected path color: `.green`
- System controls (sliders, toggles, pickers): default system tint
- Endpoint markers: already use per-formation rainbow colors
- `contrastingLabelColor`: already handles varying fill colors

## Feature 3: Formation Navigation in Transport Controls

### Purpose

Let coaches step through formations without returning to the sidebar. Especially useful on compact layouts where the sidebar may be hidden.

### New Transport Control Buttons

```swift
// In TransportControls enum
static func previousFormationButton(action:, disabled:) -> some View
    // chevron.up icon
static func nextFormationButton(action:, disabled:) -> some View
    // chevron.down icon
```

Disabled when at first/last formation respectively. No wrapping — stops at boundaries.

### Placement

**`SidebarTransportView`:**
- Added as an HStack alongside reset/play/loop:
  `[prev] [next] | [reset] [play] [loop]`

**`CompactTransitionPlaybackRailView`:**
- Same two buttons, adapted to available width

### Callbacks

New callbacks on `FloorGridView`:
- `onPreviousFormation: (() -> Void)?`
- `onNextFormation: (() -> Void)?`

`FormationHomeView` provides implementations using the same pattern as `cycleToNextFormation` but directional, clamping at boundaries instead of wrapping.

The existing `onCycleFormation` and `formationContextBadge` cycle button remain unchanged.

## Files Modified

| File | Changes |
|------|---------|
| `FloorCanvasView.swift` | Add `ghostTransitionPaths` property, `drawGhostTransitionPaths` method, replace `.orange` with `formationColor` in selection indicators and lasso |
| `FloorGridView.swift` | Compute `previousTransitionPaths`, pass to canvas, add `onPreviousFormation`/`onNextFormation` callbacks |
| `TransitionViews.swift` | Add `previousFormationButton`/`nextFormationButton` to `TransportControls`, add to `SidebarTransportView` and compact rail |
| `FormationHomeView.swift` | Implement `goToPreviousFormation`/`goToNextFormation`, wire callbacks |

**Not modified:** `Models.swift` (data layer unchanged — `transitionPaths(from:to:)` already exists).
