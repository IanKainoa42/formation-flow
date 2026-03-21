# Full Routine Playback

## Problem

The app currently plays transitions one pair at a time. Coaches need to watch the entire routine — formation 1 through formation N — in a single continuous playback to evaluate flow and spacing across the whole piece.

## Solution

A full-screen routine player that chains all transitions end-to-end with a global scrub bar, speed controls, and an optional ghost trail effect for visualizing movement fluidity.

## Architecture

### RoutinePlayer (Models.swift)

`@MainActor` class, `ObservableObject`. Orchestrates the existing `TransitionPlayer` across multiple segments.

**Initialization:**
- Takes a `RoutineStore` reference
- On init, snapshots all formations and transition specs into an ordered segment list: `[(startAthletes: [RenderedAthlete], endAthletes: [RenderedAthlete], spec: TransitionSpec, formationName: String)]`
- Default speed is `1.0` (real-time, so coaches see actual performance tempo)

**Segment sequencing:**
- Owns a single `TransitionPlayer` instance internally
- Detects segment completion by adding an `onComplete: (() -> Void)?` closure to `TransitionPlayer`. When `progress >= 1.0` and not looping, `TransitionPlayer` calls `onComplete` before pausing.
- On segment completion: schedules a 0.5s `DispatchQueue.main.asyncAfter` delay, then calls `player.refresh()` with the next segment's data followed by `player.seek(to: 0)` (to avoid a one-frame flash of end positions), then `player.play()`.
- During the 0.5s inter-segment pause, athletes remain at the completed segment's end positions. Global progress holds steady (the pause is off-timeline).
- When the last segment completes, stops playback (no auto-loop).

**Global progress:**
- `progress: CGFloat` (0–1) across the entire routine
- Segments are **proportional to their `TransitionSpec.duration`** (a 16-count transition gets 4x the scrub bar width of a 4-count transition). Total timeline = sum of all segment durations.
- Segment boundary positions are published as `segmentMarkers: [CGFloat]` for the UI to render tick marks. Computed from cumulative duration fractions.
- Seeking to an exact segment boundary belongs to the **next** segment (for `currentSegmentIndex` and `currentFormationName`).

**Published state:**
- `currentAthletes: [RenderedAthlete]` — forwarded from internal `TransitionPlayer.currentAthletes` via a Combine `$currentAthletes.sink` subscription
- `progress: CGFloat` — global 0–1, computed from `currentSegmentIndex` + `TransitionPlayer.progress` mapped to the global scale
- `isPlaying: Bool`
- `speed: CGFloat` — 1.0, 2.0, or 4.0
- `currentSegmentIndex: Int`
- `segmentCount: Int`
- `currentFormationName: String` — name of the formation the playback is currently leaving (the "from" formation of the active segment)
- `showTrail: Bool` — ghost effect toggle (default `false`)
- `trailPositions: [UUID: [CGPoint]]` — ring buffer of last ~6 positions per athlete, in **floor-feet coordinates** (matching all other position data in the app)

**Speed:** Passed through to internal `TransitionPlayer.speed`.

**Scrubbing:** `seek(to:)` maps global progress to the correct segment index using cumulative duration fractions, loads that segment into `TransitionPlayer` via `refresh()` + `seek(to: 0)`, then seeks within it at the computed local offset.

**Ghost trail:** Updated every frame from `currentAthletes`. Stores last 6 positions per athlete ID in a dictionary of ring buffers. Buffer updates regardless of `showTrail` — the flag only controls rendering.

### RoutinePlaybackView (new file)

Full-screen SwiftUI view for playback. No editing, no sidebar, no inspector.

**Layout:**
- Dark background, court centered and filling available space
- `FloorCanvasView` with `RoutinePlayer.currentAthletes`
- Close button (top-left corner, `arrow.down.right.and.arrow.up.left` icon on material circle — matches existing full-screen pattern)
- `FloorCanvasView` parameters mirror the existing full-screen floor pattern: `GeometryReader` computes `cellSize` and `offset`, `hasTransition = false`, `formationColor = .accentColor`, `ghostAthletes` is empty (the trail system is separate), `collisionIDs` and `pathCollisionIDs` are empty, no transition paths or endpoint markers

**Transport bar (bottom overlay):**
- Material background pill (matches existing `CompactTransitionPlaybackOverlayView` style)
- Play/Pause button (borderedProminent)
- Scrub slider (0–1) with tick marks at each `segmentMarkers` position
- Current formation name label (updates as playback crosses boundaries)
- Speed picker: segmented control — 1x / 2x / 4x
- Trail toggle: icon button (e.g., `sparkles`) that toggles `showTrail`

### Ghost Trail Rendering (FloorCanvasView)

- New optional parameter: `trailPositions: [UUID: [CGPoint]]` (defaults to empty)
- Coordinates are in floor-feet; the Canvas applies `* cellSize` conversion at draw time (same as athlete positions)
- When non-empty, draws ghost circles before main athlete circles
- Each ghost: same role color, decreasing opacity (oldest = most faded), slightly smaller radius
- Example: 6 trail positions at opacities 0.08, 0.12, 0.16, 0.20, 0.24, 0.28
- Subtle, not distracting — just enough to see movement direction and speed
- This is distinct from the existing `ghostAthletes` parameter (which shows static prior-formation positions). During routine playback, `ghostAthletes` is empty.

### Integration (RoutineWorkspaceView in FormationHomeView.swift)

- New "Play Routine" button in the sidebar toolbar (e.g., `play.circle` icon)
- Disabled when fewer than 2 formations
- `@State private var showingRoutinePlayback = false`
- `.fullScreenCover(isPresented:)` presenting `RoutinePlaybackView(store: store)`
- `RoutinePlaybackView` creates `RoutinePlayer` as `@StateObject` on init
- Data is snapshotted at init time; `RoutinePlayer` does not react to `RoutineStore` changes during playback (`.fullScreenCover` blocks underlying interaction anyway)

## Files Changed

| File | Change |
|------|--------|
| `Models.swift` | Add `RoutinePlayer` class, add `onComplete` closure to `TransitionPlayer` |
| `FloorCanvasView.swift` | Add optional `trailPositions` parameter and ghost rendering |
| `FormationHomeView.swift` | Add Play Routine button and `.fullScreenCover` to `RoutineWorkspaceView` |
| `RoutinePlaybackView.swift` (new) | Full-screen playback view with transport controls |

## Out of Scope

- Looping the entire routine (can add later)
- Per-formation count/duration editing from playback view
- Video/GIF export of playback
- Audio sync
