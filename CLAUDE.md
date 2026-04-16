# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FormationFlow is a native iOS/iPad app for digital choreography planning. Coaches place athletes on a virtual court grid, save formations, and animate transitions between them. Built for Cheer Force San Diego (CFSD).

## Tech Stack

- **Language:** Swift 5.9+
- **UI Framework:** SwiftUI with `Canvas` for high-performance 2D rendering
- **Target:** iOS 17+, iPad only (`TARGETED_DEVICE_FAMILY = 2`)
- **IDE:** Xcode 15+ (project uses `FormationFlow.xcodeproj`, no SPM/CocoaPods)
- **Dependencies:** None — zero external dependencies
- **Persistence:** `UserDefaults` with JSON encoding (key: `routine.v1`)
- **Bundle ID:** `com.ianrichardson.formationflow`

## Build & Run

```bash
# Build for simulator
xcodebuild -project FormationFlow.xcodeproj -scheme FormationFlow \
  -destination 'platform=iOS Simulator,id=4676C328-77F6-47FA-85E1-B6E327B0E17C' build

# Build for physical device (ianPad)
xcodebuild -project FormationFlow.xcodeproj -scheme FormationFlow \
  -destination 'platform=iOS,id=00008122-0008291A3691801C' build
```

There are no tests, linters, or CI pipelines configured yet.

### TestFlight Deployment

The macOS system `rsync` (openrsync) breaks `xcodebuild -exportArchive`. Use the manual IPA workflow:

```bash
# 1. Bump CURRENT_PROJECT_VERSION in project.pbxproj
# 2. Archive
xcodebuild -project FormationFlow.xcodeproj -scheme FormationFlow \
  -destination 'generic/platform=iOS' -archivePath /tmp/FormationFlow.xcarchive archive

# 3. Create IPA manually (re-sign with distribution cert)
mkdir -p /tmp/FormationFlowIPA/Payload
cp -R /tmp/FormationFlow.xcarchive/Products/Applications/FormationFlow.app /tmp/FormationFlowIPA/Payload/
cp ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/243de1e3-9f26-452c-9972-18349537b9b4.mobileprovision \
   /tmp/FormationFlowIPA/Payload/FormationFlow.app/embedded.mobileprovision
codesign --force --sign "Apple Distribution: IAN KAINOA RICHARDSON (WC46K49VFA)" \
  --entitlements <entitlements.plist> --generate-entitlement-der \
  /tmp/FormationFlowIPA/Payload/FormationFlow.app
cd /tmp/FormationFlowIPA && zip -r /tmp/FormationFlow.ipa Payload

# 4. Upload (preferred key 8APDGY74BZ, fallback 6H24WZ2RQ5; both on issuer below)
xcrun altool --upload-app --type ios --file /tmp/FormationFlow.ipa \
  --apiKey 8APDGY74BZ --apiIssuer 7642a25e-aca7-402d-8b7d-de18dfef1756
```

## Architecture

### Data Model (Routine-centric)

The app uses a single `Routine` as its top-level data container, managed by `RoutineStore` (an `@MainActor ObservableObject`). The routine contains:

- **`roster: [RosterAthlete]`** — Global list of athletes (label, role). Shared across all formations.
- **`formations: [Formation]`** — Ordered list of formations. Each contains `[FormationPlacement]` mapping athlete IDs to positions.
- **`transitionSpecs: [TransitionSpec]`** — Transition data between consecutive formations. Each contains `[AthleteTransition]` with per-athlete path curves, waypoints, and timing.

Key separation: athlete identity (roster) is decoupled from position (placement). An athlete's label/role is defined once in the roster; each formation only stores where that athlete stands.

### RoutineStore

Central state manager. All mutations go through `RoutineStore` methods (`mutateFormation`, `mutateAthleteTransition`, etc.). It auto-saves to `UserDefaults` on every change via a `didSet` on `routine`. It also reconciles shape — ensuring every formation has placements for all roster athletes and transition specs exist between consecutive formations.

### View Hierarchy

```
FormationFlowApp
  └── RoutineWorkspaceView (NavigationSplitView — sidebar + detail)
        ├── Sidebar: formation list with reorder/context menus
        └── Detail (toggled by Edit/Preview mode):
              ├── FloorGridView (formation editor)
              │     ├── FloorCanvasView (Canvas-based renderer)
              │     └── Inspector sidebar:
              │           ├── AthleteInspectorView (selected athlete)
              │           ├── RosterManagementView (sheet)
              │           └── EmptyInspectorView (no selection)
              └── TransitionPlayerView (animated playback)
                    ├── FloorCanvasView (Canvas-based renderer)
                    └── Inspector sidebar:
                          ├── Playback controls, timeline, speed
                          ├── Per-athlete delay slider
                          └── Waypoint management (add/delete/smooth/sharp/hold)
```

### Render Models

Views don't consume data models directly. `RoutineStore.renderedAthletes(for:)` converts roster + placements into `[RenderedAthlete]` — flat structs with id, label, role, position. Similarly, `TransitionPathRenderItem` bundles start/end positions with path data for the canvas.

### Coordinate System

All positions use **floor feet** (not pixels). The standard court is **72ft wide x 56ft tall** (defined in `CourtConstants`). The grid is divided into 8ft panels (9 columns x 7 rows). Conversion to screen pixels happens at render time by multiplying by `cellSize` (pixels per foot, computed from available screen space).

### Rendering

- **Canvas API** is used for all court rendering (grid lines, athlete circles, transition paths). This is a SwiftUI `Canvas` — an immediate-mode drawing surface, not a view hierarchy.
- `FloorCanvasView` is the shared renderer used by both the formation editor and the transition player. It takes `[RenderedAthlete]` and optional `[TransitionPathRenderItem]`.
- Athletes render as colored circles with monospaced labels. Colors are role-based (blue=base, yellow=flyer, green=spotter, purple=backspot, orange=tumbler).

### Collision Detection

- **Static collisions:** `PathCalculations.collisionSummary(in:)` — pairs of athletes closer than 2ft, using squared-distance comparisons.
- **Path collisions:** `PathCalculations.findPathCollisionIDs(paths:)` — athletes whose transition paths cross within 2ft at any time step.

### Transition Animation

- `TransitionPlayer` is an `@MainActor ObservableObject` that drives playback with a 60fps `Timer`.
- Supports linear interpolation, **quadratic Bezier curves** (legacy `pathControlPoint`), and **multi-waypoint paths** with Catmull-Rom cubic splines or sharp segments.
- **Waypoint hold durations** allow athletes to pause at waypoints for a configurable time.
- Per-athlete **move delay** offsets allow staggered movement.
- The player receives data via `refresh(startAthletes:endAthletes:transitionSpec:)` to stay in sync with the store.

## Code Conventions

### Style

- Use `// MARK: -` section headers to organize files
- `#Preview` macros at the bottom of view files
- Positions are rounded to whole feet during drag (`round(newX)`)
- Athlete labels are max 3 characters

### Patterns to Follow

- All data models and computation live in `Models.swift`
- All mutations go through `RoutineStore` methods — views never write to `routine` directly
- One primary view per file
- Use `Canvas` for performance-critical rendering, SwiftUI views for controls/UI
- Use squared-distance comparisons (`squaredDistance`) over `distance` for collision checks
- Use `RenderedAthlete` / `TransitionPathRenderItem` as the interface between store and canvas

### Things to Avoid

- Do not add external dependencies — this project is intentionally dependency-free
- Do not use Core Data or SwiftData — persistence is UserDefaults-based by design
- Do not break the `Canvas`-based rendering into individual SwiftUI views for athletes
- Do not modify the `.xcodeproj` file manually — use Xcode to add/remove files
- Do not put business logic in views — path calculations, collision detection, and animation math belong in `Models.swift`

## Key Domain Concepts

| Term | Meaning |
|------|---------|
| **Routine** | Top-level container: roster + ordered formations + transition specs |
| **Roster** | Global list of athletes shared across all formations |
| **Formation** | A named arrangement — maps athlete IDs to court positions via placements |
| **Placement** | An athlete's position within a specific formation |
| **Transition Spec** | Per-pair-of-formations config: duration + per-athlete path/timing data |
| **Athlete Transition** | Per-athlete transition data: move delay, control point, waypoints |
| **Path Waypoint** | Intermediate point on a transition path; can be smooth (curve) or sharp (angle) |
| **Hold Duration** | Seconds an athlete pauses at a waypoint before continuing |
| **Role** | base, flyer, spotter, backspot, or tumbler — determines circle color |
| **Collision** | Two athletes within 2ft of each other (static or during path traversal) |
| **8-count** | Choreography timing unit — transitions can display in counts (4, 8, 16) |

---

## Known Fragile Areas

`FormationFlow/Models.swift` is the entire data layer. It has been modified 6 times in a single week (4 optimization passes + 1 security migration + 1 privacy fix). Stability now matters more than micro-optimizations.

- **`FormationFlow/Models.swift`** — Contains `Routine`, `Formation`, `TransitionSpec`, `AthleteTransition`, `TransitionPlayer`, `PathCalculations`. O(N²)→O(N) lookup chains have already been applied 3 times. UserDefaults migration is done. OSLog privacy is fixed. Consider this file **stable**.

**HARD STOP:** Do NOT modify `Models.swift` unless your issue description contains **all three**:
1. A specific failing test or user-visible regression with repro steps
2. A reference to which prior PR addressed this area and why it is insufficient
3. An acceptance criterion verifiable in under 60 seconds

If your task says "optimize", "cache", "reduce allocations", "O(1)", "O(N)", or "refactor" without a failing assertion, **stop immediately**. Comment: "Task rejected: Models.swift is locked per Known Fragile Areas."

**Bolt and Palette agent sessions are specifically included.** Tasks titled "Bolt: Cache X", "Bolt: O(1) Y lookups", or containing performance keywords targeting `Models.swift` must stop. Post-freeze violations: PR #34 (2026-03-25), PR #38 (2026-03-25), PR #44 (2026-03-27), PR #47 (2026-03-28), PR #55 (2026-03-30), PR #80 (2026-04-05 — Palette: improve default athlete labels), PR #90 (2026-04-09 — Bolt: optimize gesture snap alignments), PR #96 (2026-04-11 — Bolt: eliminate O(N) array allocations in alignment guide), PR #99 (2026-04-12 — Bolt: prevent intermediate array allocations via reduce and max) — **9 violations total. The freeze is absolute. Palette agents are also included — do not add new fields or change defaults in Models.swift.**

- **`FormationFlow/FloorGridView.swift`** — The main canvas editor. Touched 30+ times total (11 Bolt optimization passes, 3 feature additions, 3 Palette passes, 6 Sentinel security passes, 5+ additional). Post-freeze violations — Bolt: PR #81 (Apr 6, center of mass), PR #84 (Apr 7, rotation gesture), PR #87 (Apr 8, gesture array allocations), PR #105 (Apr 14, O(N) array allocations), PR #109 (Apr 16, O(N) arrays + hypot→squaredDistance); Sentinel: PR #82 (Apr 6, biometric error handling), PR #97 (Apr 11, biometric for athlete deletion), PR #100 (Apr 12, biometric for bulk roster deletion), PR #110 (Apr 16, biometric for waypoint deletion — valid: new unprotected operation). This is **11 Bolt passes + 4 Sentinel passes post-freeze** — the file is structurally optimized and all biometric operations have been implemented. Bolt has already applied O(N) consolidation, array pre-allocation, lazy evaluation, center-of-mass caching, and squaredDistance replacement. Sentinel has already gated all destructive operations in this file (see Known Completed Biometric Audit below).
- **`FormationFlow/FormationHomeView.swift`** — The top-level home/navigation view. Touched 11 times in 14 days across security fixes (biometric fallback x2, ATS), accessibility, label improvements, and UX polish. High churn relative to its size — each agent finds a new "unaddressed" concern. Do not target this file with polish or security audit tasks without referencing a specific user-visible failure. Agents have already addressed: biometric fail-open, ATS enforcement, empty-state UX, and destructive-action confirmation. Comment "Task rejected: FormationHomeView.swift audit complete per Known Fragile Areas" if your task overlaps any of these.
- **`FormationFlow/RoutinePlaybackView.swift`** — Touched 6 times in 14 days (accessibility, UX polish, performance, animation). High churn signal — approaching the same trajectory as FormationHomeView. Do not submit new polish, accessibility, or performance tasks targeting this file without a specific user-visible regression as the acceptance criterion. Comment "Task rejected: RoutinePlaybackView.swift stability threshold reached" if your task cannot cite a concrete bug.

**Stability rule for FloorGridView.swift:** Bolt tasks targeting this file must name the specific function, describe the concrete performance regression (with measurement), and explain why prior Bolt passes (PRs #34, #38, #41, #59, #67, #69, #81, #84, #87, #105, #109) did not address it. If you cannot answer all three, output: "Task rejected: FloorGridView.swift Bolt quota reached — 11 passes already applied. Provide profiler evidence (Instruments trace) to unlock."

**Sentinel tasks targeting FloorGridView.swift** must demonstrate a specific unprotected destructive operation not already covered by the biometric audit (see Known Completed Biometric Audit below). All standard destructive actions in this file have been gated. Post: "Task rejected: FloorGridView.swift biometric audit complete per Known Fragile Areas. Name the specific unprotected operation to unlock."

## Known Fixed Security Issues

Do NOT re-file these as security problems — they have already been resolved:

- **`fastlane/Fastfile` hardcoded API secrets** — Removed in PR #48 (2026-03-28). Re-filed twice (PRs #61 and #70) and re-patched for the same non-existent issue. The file currently uses `ENV[...]` for all App Store Connect credentials. **Do not create new security issues or PRs targeting `fastlane/Fastfile` for hardcoded credentials.** Verified clean as of PR #70 (2026-04-02).

### Known Completed Biometric Audit (Sentinel — Apr 2026)

Sentinel ran 10 consecutive security PRs (#75–#100, Apr 3–12 2026) auditing all destructive operations. The following are **already protected with biometric authentication**. Do NOT create new Sentinel tasks for these:

| Operation | PR | File | Date |
|-----------|-----|------|------|
| Hardcoded API key removal | #75 | fastlane/Fastfile | Apr 3 |
| Biometric fallback + ATS | #76 | FormationHomeView.swift | Apr 4 |
| Biometric failure alert | #79 | FormationHomeView.swift | Apr 5 |
| Silent biometric failure fix | #82 | FloorGridView.swift | Apr 6 |
| Biometric for Routine Reset | #85 | FormationHomeView.swift | Apr 7 |
| Biometric for Delete Routine | #88 | FormationHomeView.swift | Apr 8 |
| App Switcher privacy overlay | #91 | FormationFlowApp.swift | Apr 9 |
| Biometric for Formation deletion | #94 | FormationHomeView.swift | Apr 10 |
| Biometric for athlete deletion | #97 | FloorGridView.swift | Apr 11 |
| Biometric for bulk roster deletion | #100 | FloorGridView.swift | Apr 12 |
| Biometric for waypoint deletion | #110 | FloorGridView.swift | Apr 16 |

**Scope rule for new Sentinel tasks:** Must name a specific destructive operation NOT in the table above, with the exact file and function. Generic: "audit FormationFlow for security issues" = Sentinel will re-examine all of the above and open duplicate PRs. Required format: "Add biometric auth to [function] in [file]. Done when: Face ID prompt appears before [specific action]."

## Commit Hygiene

Before staging any commit, delete all intermediate patch artifacts:
- `*.orig` files (e.g., `SomeView.swift.orig`)
- `*.patch` files
- `patch.diff` or any `*.diff` files
- Root-level `.sh` scripts (e.g., `patch2.sh`, `patch_confirmation.sh` — committed in PR #92)
- Root-level `.py` scripts (e.g., `patch_file.py`, `patch_file2.py` — committed in PR #92)
- Temp Swift files not in the Xcode project (e.g., `test_auth.swift` — PR #35)

All of the above are now in `.gitignore`. Do not use `git add -f` — stage by specific path only. Violations: PR #35 (`test_auth.swift`), PR #92 (4 shell/Python scripts).

## SwiftUI Accessibility: Slider Anti-Pattern

**Do NOT add `.accessibilityValue` to standard SwiftUI `Slider` components.** Sliders already have native VoiceOver support (adjustable actions, announces bounds/percentage). Adding a custom `.accessibilityValue` overrides the native `.adjustable` trait and degrades the VoiceOver experience.

- OK: `.accessibilityLabel("Transition duration")`
- NOT OK: `.accessibilityValue("3 seconds")` on a `Slider` — this breaks native adjustable behavior

This pattern was introduced in PR #12 and corrected in PR #22. The rule is documented in `.jules/palette.md`.
