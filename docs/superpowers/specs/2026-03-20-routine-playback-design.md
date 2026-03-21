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
- On play, snapshots all formations and transition specs into an ordered segment list: `[(startAthletes: [RenderedAthlete], endAthletes: [RenderedAthlete], spec: TransitionSpec)]`

**Segment sequencing:**
- Owns a single `TransitionPlayer` instance internally
- When a segment completes, pauses for 0.5 seconds, then loads the next segment via `TransitionPlayer.refresh()` and resumes
- When the last segment completes, stops playback (no auto-loop)

**Global progress:**
- `progress: CGFloat` (0–1) across the entire routine
- Each segment gets an equal fraction of the timeline (e.g., 3 transitions = each segment is 1/3)
- Segment boundary positions are published as `segmentMarkers: [CGFloat]` for the UI to render tick marks

**Published state:**
- `currentAthletes: [RenderedAthlete]` — current interpolated positions
- `progress: CGFloat` — global 0–1
- `isPlaying: Bool`
- `speed: CGFloat` — 1.0, 2.0, or 4.0
- `currentSegmentIndex: Int`
- `segmentCount: Int`
- `currentFormationName: String` — name of the formation the playback is currently in/leaving
- `showTrail: Bool` — ghost effect toggle
- `trailPositions: [UUID: [CGPoint]]` — ring buffer of last ~6 positions per athlete

**Speed:** Passed through to internal `TransitionPlayer.speed`.

**Scrubbing:** `seek(to:)` maps global progress to the correct segment index, loads that segment into the `TransitionPlayer`, and seeks within it at the local offset.

**Ghost trail:** Updated every frame from `currentAthletes`. Stores last 6 positions per athlete ID in a dictionary of ring buffers. Buffer updates regardless of `showTrail` — the flag only controls rendering.

### RoutinePlaybackView (new file)

Full-screen SwiftUI view for playback. No editing, no sidebar, no inspector.

**Layout:**
- Dark background, court centered and filling available space
- `FloorCanvasView` with `RoutinePlayer.currentAthletes`
- Close button (top-left corner, `arrow.down.right.and.arrow.up.left` icon on material circle — matches existing full-screen pattern)

**Transport bar (bottom overlay):**
- Material background pill (matches existing `CompactTransitionPlaybackOverlayView` style)
- Play/Pause button (borderedProminent)
- Scrub slider (0–1) with tick marks at each `segmentMarkers` position
- Current formation name label (updates as playback crosses boundaries)
- Speed picker: segmented control — 1x / 2x / 4x
- Trail toggle: icon button (e.g., `sparkles`) that toggles `showTrail`

### Ghost Trail Rendering (FloorCanvasView)

- New optional parameter: `trailPositions: [UUID: [CGPoint]]` (defaults to empty)
- When non-empty, draws ghost circles before main athlete circles
- Each ghost: same role color, decreasing opacity (oldest = most faded), slightly smaller radius
- Example: 6 trail positions at opacities 0.08, 0.12, 0.16, 0.20, 0.24, 0.28
- Subtle, not distracting — just enough to see movement direction and speed

### Integration (FormationHomeView)

- New "Play Routine" button in the sidebar toolbar (e.g., `play.circle` icon)
- Disabled when fewer than 2 formations
- `@State private var showingRoutinePlayback = false`
- `.fullScreenCover(isPresented:)` presenting `RoutinePlaybackView(store: store)`
- `RoutinePlaybackView` creates `RoutinePlayer` as `@StateObject` on init

## Files Changed

| File | Change |
|------|--------|
| `Models.swift` | Add `RoutinePlayer` class |
| `FloorCanvasView.swift` | Add optional `trailPositions` parameter and ghost rendering |
| `FormationHomeView.swift` | Add Play Routine button and `.fullScreenCover` |
| `RoutinePlaybackView.swift` (new) | Full-screen playback view with transport controls |

## Out of Scope

- Looping the entire routine (can add later)
- Per-formation count/duration editing from playback view
- Video/GIF export of playback
- Audio sync
