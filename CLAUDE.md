# CLAUDE.md — FormationFlow

## Project Overview

FormationFlow is a native iOS/iPad app for digital choreography planning. It lets coaches place athletes on a virtual court grid, save formations, and animate transitions between them — without needing the full team physically present. Built for Cheer Force San Diego (CFSD).

## Tech Stack

- **Language:** Swift 5.9+
- **UI Framework:** SwiftUI with `Canvas` for high-performance 2D rendering
- **Target:** iOS 17+, iPad only (`TARGETED_DEVICE_FAMILY = 2`)
- **IDE:** Xcode 15+ (project uses `FormationFlow.xcodeproj`, no SPM/CocoaPods)
- **Dependencies:** None — zero external dependencies
- **Persistence:** `UserDefaults` with JSON encoding (no Core Data, no CloudKit)
- **Bundle ID:** `com.cheerforcesandiego.formationflow`

## Build & Run

```bash
# Open in Xcode
open FormationFlow.xcodeproj

# Build from command line (requires macOS with Xcode)
xcodebuild -project FormationFlow.xcodeproj -scheme FormationFlow -destination 'platform=iOS Simulator,name=iPad Pro' build
```

There are no tests, linters, or CI pipelines configured yet.

## Project Structure

```
FormationFlow/
├── FormationFlowApp.swift        # @main app entry point, sets up NavigationStack + PersistenceManager
├── Models.swift                  # All data models, persistence, path math, collision detection, animation
├── FloorGridView.swift           # Main formation editor — drag athletes, zoom/pan, collision display
├── FloorCanvasView.swift         # Shared Canvas renderer — draws grid, athletes, paths (used by editor + player)
├── FormationListView.swift       # Home screen — list of saved formations with thumbnails
├── FormationThumbnailView.swift  # Mini Canvas preview of a formation for list rows
├── TransitionViews.swift         # Transition picker + animated transition player with scrubbing
├── TimingControlsView.swift      # Per-athlete move-timing slider (delay before movement starts)
├── AthleteDetailPanel.swift      # Floating panel for editing selected athlete (label, role, position)
├── Assets.xcassets/              # Asset catalog (currently minimal)
├── Info.plist                    # App configuration
└── Base.lproj/LaunchScreen.storyboard
```

Supporting files at repo root:
- `FormationFlow.xcodeproj/` — Xcode project (single target, Release config only)
- `build.log`, `build_log.txt` — historical build output

## Architecture & Key Patterns

### Data Flow

- **PersistenceManager** is a singleton `ObservableObject` (`PersistenceManager.shared`) injected via `.environmentObject()` from the app root. It owns the `[Formation]` array and debounces saves to UserDefaults (0.5s delay via `DispatchWorkItem`).
- Views also access `PersistenceManager.shared` directly via `@StateObject` — this is the established pattern in this codebase.
- Formations are value types (`struct`) passed into views as `@State`. Views mutate their local copy, then sync back to `PersistenceManager` via `.onChange`.

### Coordinate System

All positions use **floor feet** (not pixels). The standard court is **52ft wide × 30ft tall** (defined in `CourtConstants`). Conversion to screen pixels happens at render time by multiplying by `cellSize` (pixels per foot, computed from available screen space).

### Rendering

- **Canvas API** is used for all court rendering (grid lines, athlete circles, transition paths). This is a SwiftUI `Canvas` — an immediate-mode drawing surface, not a view hierarchy.
- `FloorCanvasView` is the shared renderer used by both the formation editor (`FloorGridView`) and the transition player (`TransitionPlayerView`).
- Athletes render as colored circles with monospaced labels. Colors are role-based (blue=base, yellow=flyer, green=spotter, purple=backspot, orange=tumbler).

### Collision Detection

- **Static collisions:** Pairs of athletes closer than 2ft (`CourtConstants.collisionDistance`). Detected via `PathCalculations.collisionSummary()` using squared-distance comparisons for performance.
- **Path collisions:** Athletes whose transition paths cross within 2ft at any time step. Detected via `PathCalculations.findPathCollisionIndices()`.
- Both use **caching** — results recompute only when athlete positions/paths actually change (tracked via `Equatable` key structs).

### Transition Animation

- `TransitionPlayer` is an `ObservableObject` that drives playback with a 60fps `Timer`.
- Supports linear interpolation and **quadratic Bezier curves** (via optional `pathControlPoint` on each athlete).
- Per-athlete **move timing** offsets allow staggered movement (who moves first/last).

## Code Conventions

### Style

- Use `// MARK: -` section headers to organize files (Navigation, Canvas, Toolbar, Actions, etc.)
- `#if os(iOS)` / `#else` guards for platform-specific toolbar placement
- `#Preview` macros at the bottom of view files
- Positions are rounded to whole feet during drag (`round(newX)`)
- Athlete labels are max 3 characters

### Naming

- Views are named descriptively: `FloorGridView`, `TransitionPlayerView`, `AthleteDetailPanel`
- Models use domain language: `Athlete`, `Formation`, `AthleteRole`
- Utilities are static methods on `PathCalculations`
- Constants live in the `CourtConstants` enum

### State Management

- `@State` for view-local mutable state
- `@StateObject` for owned `ObservableObject` references
- `@Binding` for child-to-parent two-way data flow
- `@Environment(\.dismiss)` for navigation dismissal
- No Combine pipelines — state updates are synchronous or timer-driven

### Patterns to Follow

- Keep all data models and computation in `Models.swift`
- Keep views focused — one primary view per file
- Use `Canvas` for performance-critical rendering, SwiftUI views for controls/UI
- Use squared-distance comparisons (`squaredDistance`) over `distance` for collision checks
- Cache expensive computations (collisions) and only recompute when inputs change
- Debounce persistence writes to avoid excessive UserDefaults I/O
- Support both iOS and macOS via `#if os(iOS)` where needed (toolbar placement)

### Things to Avoid

- Do not add external dependencies — this project is intentionally dependency-free
- Do not use Core Data or SwiftData — persistence is UserDefaults-based by design
- Do not break the `Canvas`-based rendering into individual SwiftUI views for athletes — `Canvas` is used for performance
- Do not modify the `.xcodeproj` file manually — use Xcode to add/remove files
- Do not put business logic in views — path calculations, collision detection, and animation math belong in `Models.swift`

## Key Domain Concepts

| Term | Meaning |
|------|---------|
| **Formation** | A named arrangement of athletes on the court |
| **Athlete** | A person with a label (e.g. "A1"), position (in feet), and role |
| **Role** | base, flyer, spotter, backspot, or tumbler — determines color |
| **Transition** | Animated movement of athletes from one formation to another |
| **Path Control Point** | Optional Bezier control point for curved transition paths |
| **Move Timing** | Per-athlete delay (seconds) before they begin moving in a transition |
| **Collision** | Two athletes within 2ft of each other (static or during path traversal) |
| **8-count** | Choreography timing unit — transitions can display in counts (4, 8, 16) |

## Navigation Flow

```
FormationListView (home)
  └── FloorGridView (formation editor)
        ├── AthleteDetailPanel (floating, on athlete selection)
        ├── Manage Athletes (sheet)
        ├── Formation Notes (sheet)
        └── TransitionPickerView
              └── TransitionPlayerView (animated playback)
                    └── TimingControlsView (per-athlete timing)
```
