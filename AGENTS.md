# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

FormationFlow is a native iOS/iPadOS app for digital choreography planning. Coaches place athletes on a virtual court grid, save formations, and animate transitions between them. Built for Cheer Force San Diego (CFSD).

## Tech Stack

- **Language:** Swift 5.9+
- **UI Framework:** SwiftUI with `Canvas` for high-performance 2D rendering
- **Target:** iOS 17+, Universal — iPhone + iPad (`TARGETED_DEVICE_FAMILY = "1,2"`)
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

## UI Layout Policy — Transport Controls (ALL agents)

**Exactly one transport control stack may be visible at a time.** Choose by orientation:

- **Portrait → bottom controls only.** The transport lives in the floating bottom overlay on the detail/canvas pane. The sidebar/inspector must NOT render its own transport.
- **Landscape → sidebar controls only.** The transport lives in the sidebar (`SidebarTransportView`) or the selected-athlete inspector. The bottom overlay must NOT render.

iPad portrait vs landscape cannot be distinguished by size class alone (both are regular width) — use the `isIPadPortrait` flag (computed via `GeometryReader` width-vs-height in `FormationHomeView`) and thread it down to any view that embeds a transport. The selected-athlete inspector (`SelectedAthleteSidebarView` in `AthleteDetailPanel.swift`) takes `isIPadPortrait` and hides its embedded transport block in portrait so the bottom overlay is the sole control surface.

**Before adding or relocating any transport/playback control: confirm it cannot co-render with another transport in the same orientation.** A duplicate transport in iPad portrait (inspector + bottom overlay) was fixed 2026-05-23; do not reintroduce it. The bottom overlay's `SidebarTransportView` is a superset (nav + reset + play + loop + slider + speed + swap + path), so hiding the inspector transport in portrait drops no functionality.

---

## Visual Verification (canvas/rendering changes)

Two verification-claim corrections happened within the same session window (2026-06-20):

- **Catalyst ≠ the simulator Ian is testing on.** They are different binaries. A build/install/screenshot on Mac Catalyst does NOT prove the iPad simulator (or device) has the change — if Ian reports "I don't see X" after a Catalyst-only verification, the simulator likely has a stale binary. After any canvas/rendering change, build+install+launch on the **actual target** (the simulator Ian is using, or device) before claiming it's visible there. Fresh sim installs also reset `@AppStorage` and wipe the routine — re-seed `workspace.v1.json` (copy `.appstore/demo_routine.json` into the app's `Documents/`) or the floor renders empty-state instead of the canvas.
- **Do not eyeball-confirm a faint/subtle visual element against a busy background.** A watermark at 0.16–0.28 opacity was claimed "visible" by pattern-matching existing athlete/ghost circles — it wasn't actually distinguishable. Verify a subtle element by first rendering it in an unmistakable debug color (solid green, opacity 1.0) to prove it draws at the right place, THEN dial back to the target style. On FormationFlow's dark floor (panel grey ~rgb 38), coral/cream/mid-saturation colors need ~0.5+ opacity to read — sub-0.3 disappears visually.

## Known Fragile Areas

`FormationFlow/Models.swift` is the entire data layer. It has been modified 6 times in a single week (4 optimization passes + 1 security migration + 1 privacy fix). Stability now matters more than micro-optimizations.

- **`FormationFlow/Models.swift`** — Contains `Routine`, `Formation`, `TransitionSpec`, `AthleteTransition`, `TransitionPlayer`, `PathCalculations`. O(N²)→O(N) lookup chains have already been applied 3 times. UserDefaults migration is done. OSLog privacy is fixed. Consider this file **stable**.

**HARD STOP:** Do NOT modify `Models.swift` unless your issue description contains **all three**:
1. A specific failing test or user-visible regression with repro steps
2. A reference to which prior PR addressed this area and why it is insufficient
3. An acceptance criterion verifiable in under 60 seconds

If your task says "optimize", "cache", "reduce allocations", "O(1)", "O(N)", or "refactor" without a failing assertion, **stop immediately**. Comment: "Task rejected: Models.swift is locked per Known Fragile Areas."

**Bolt and Palette agent sessions are specifically included.** Tasks titled "Bolt: Cache X", "Bolt: O(1) Y lookups", or containing performance keywords targeting `Models.swift` must stop. Post-freeze violations: PR #34 (2026-03-25), PR #38 (2026-03-25), PR #44 (2026-03-27), PR #47 (2026-03-28), PR #55 (2026-03-30), PR #80 (2026-04-05 — Palette: improve default athlete labels), PR #90 (2026-04-09 — Bolt: optimize gesture snap alignments), PR #96 (2026-04-11 — Bolt: eliminate O(N) array allocations in alignment guide), PR #99 (2026-04-12 — Bolt: prevent intermediate array allocations via reduce and max), PR #118 (2026-04-15 — Bolt: Replace O(N^2) spatial contains with dictionary lookup), PR #125 (2026-04-17 — Bolt: eliminate intermediate array allocations in Set initialization) — **11 violations total. The freeze is absolute. Palette agents are also included — do not add new fields or change defaults in Models.swift.**

- **`FormationFlow/FloorGridView.swift`** — The main canvas editor. Touched 30+ times total (12 Bolt optimization passes, 3 feature additions, 5 Palette passes, 6 Sentinel security passes, 5+ additional). Latest Palette violations: PR #135 (Apr 2026, accessibility labels for Swap formation picker), PR #140 (May 2026, added floating "Reset View" button — a feature scope change without explicit owner approval), PR #142 (May 2026, Sentinel: autocorrection disabled — also touches FloorGridView), and PR #143 (May 2026, Palette: tooltips and accessibility hints — HARD STOP violation, merged 2026-05-12 despite rule added 2026-05-07). Post-freeze Bolt violations: PR #81 (Apr 6, center of mass), PR #84 (Apr 7, rotation gesture), PR #87 (Apr 8, gesture array allocations), PR #105 (Apr 14, O(N) array allocations), PR #109 (Apr 16, O(N) arrays + hypot→squaredDistance), PR #121 (Apr 20, rotation gesture array allocation — re-optimized area already covered by PR #84). Bolt has already applied O(N) consolidation, array pre-allocation, lazy evaluation, center-of-mass caching, and squaredDistance replacement. **Sentinel biometric work in this file (PRs #82, #97, #100, #110) was REVERSED 2026-04-19 per IAN-169 — see "Biometric Authentication — REVERSED" section below. Do not re-add.**
- **`FormationFlow/FormationHomeView.swift`** — The top-level home/navigation view. Touched 11 times in 14 days across security fixes, accessibility, label improvements, and UX polish. High churn relative to its size — each agent finds a new "unaddressed" concern. Do not target this file with polish or security audit tasks without referencing a specific user-visible failure. Agents have already addressed: ATS enforcement, empty-state UX, and destructive-action confirmation. **Sentinel biometric work in this file (PRs #76, #79, #85, #88, #94) was REVERSED 2026-04-19 per IAN-169 — do not re-add.** Comment "Task rejected: FormationHomeView.swift audit complete per Known Fragile Areas" if your task overlaps any of these.
- **`FormationFlow/RoutinePlaybackView.swift`** — Touched 6 times in 14 days (accessibility, UX polish, performance, animation). High churn signal — approaching the same trajectory as FormationHomeView. Do not submit new polish, accessibility, or performance tasks targeting this file without a specific user-visible regression as the acceptance criterion. Comment "Task rejected: RoutinePlaybackView.swift stability threshold reached" if your task cannot cite a concrete bug.
- **`FormationFlow/AthleteDetailPanel.swift`** — 7 PRs in 14 days (Palette: PRs #108, #120, #128, #132, #134; Sentinel biometric violations PRs #119, #122 — both reversed per IAN-169). Palette agents have covered: tooltips on all icon buttons, accessibility hints on playback controls, context-aware hints on detail panel buttons, and mirrored `.help()` tooltips. **HARD STOP for Palette/accessibility/polish tasks.** Every plausible accessibility improvement has been addressed. Comment: "Task rejected: AthleteDetailPanel.swift has hit its HARD STOP (7 a11y/Palette PRs). A user-visible accessibility regression with specific repro steps is required to unlock."

**Stability rule for FloorGridView.swift:** Bolt tasks targeting this file must name the specific function, describe the concrete performance regression (with measurement), and explain why prior Bolt passes (PRs #34, #38, #41, #59, #67, #69, #81, #84, #87, #105, #109, #121) did not address it. Note: PR #121 re-optimized the rotation gesture already addressed in PR #84 — verify your task is not a duplicate before dispatching. If you cannot answer all three, output: "Task rejected: FloorGridView.swift Bolt quota reached — 12 passes already applied. Provide profiler evidence (Instruments trace) to unlock."

**Palette tasks targeting FloorGridView.swift are HARD STOP. This rule has been violated 3 times post-rule-addition.** PRs #129, #135 (Apr 2026), #140, #142, and #143 (May 2026) have covered all reachable accessibility improvements. PR #142 (Sentinel: autocorrection, merged 2026-05-09) and PR #143 (Palette: tooltips/hints, merged 2026-05-12) were both merged AFTER the HARD STOP was added on 2026-05-07 — confirming that this file's HARD STOP must be treated as absolute regardless of session type (Palette, Sentinel, Bolt). Comment: "Task rejected: FloorGridView.swift Palette HARD STOP (3 post-rule violations — #140, #142, #143). A user-visible a11y regression with specific repro steps is required to unlock. Feature additions require explicit owner approval."

**Sentinel tasks targeting FloorGridView.swift** must NOT propose biometric authentication of any form — that entire scope was reversed 2026-04-19 (see "Biometric Authentication — REVERSED" below). Destructive actions take effect immediately with NO confirmation (see "Destructive-Action Confirmations — REMOVED"). Post: "Task rejected: biometric authentication was deliberately removed per IAN-169. Re-adding requires explicit owner approval."

## Known Fixed Security Issues

Do NOT re-file these as security problems — they have already been resolved:

- **`fastlane/Fastfile` hardcoded API secrets** — Removed in PR #48 (2026-03-28). Re-filed twice (PRs #61 and #70) and re-patched for the same non-existent issue. The file currently uses `ENV[...]` for all App Store Connect credentials. **Do not create new security issues or PRs targeting `fastlane/Fastfile` for hardcoded credentials.** Verified clean as of PR #70 (2026-04-02).

### Biometric Authentication — REVERSED 2026-04-19 per IAN-169

**Product decision:** All Face ID / biometric authentication has been removed from the app. This is a coach-facing iPad tool used courtside under time pressure — biometric prompts on every destructive action created intolerable friction. Destructive actions have **no confirmation gate at all** (see "Destructive-Action Confirmations — REMOVED" below).

**What was removed (all of it):**
- Every `LAContext` / `evaluatePolicy` block across `FormationHomeView.swift`, `FloorGridView.swift`, `AthleteDetailPanel.swift`
- Every `authenticateAndX()` wrapper function — call sites now invoke the underlying mutation directly
- Every "Authentication Failed" alert and `showingAuthFailedAlert` / `authErrorMessage` `@State` var
- `import LocalAuthentication` from all three files
- `NSFaceIDUsageDescription` from `FormationFlow/Info.plist`
- `.blur(radius: ...)` app-switcher privacy overlay from `FormationFlowApp.swift` (PR #91)
- `@Environment(\.scenePhase)` in `FormationFlowApp.swift` (no longer needed)

**What is preserved:**
- Hardcoded API key removal in `fastlane/Fastfile` (PR #75) — this was an unrelated secrets fix, KEEP
- ATS / `NSAppTransportSecurity` in Info.plist — KEEP
- `.confirmationDialog` modifiers — REMOVED 2026-05-26 (see "Destructive-Action Confirmations — REMOVED"); the biometric reversal kept them at the time, but the owner has since decided destructive actions take effect immediately with no confirmation

**HARD STOP for Sentinel agents:** Do NOT re-add biometric authentication, Face ID prompts, `LAContext`, `LocalAuthentication`, `NSFaceIDUsageDescription`, the `.blur(...)` app-switcher overlay, or any `authenticateAndX()` wrapper to this project. Reversed PRs: #76, #79, #82, #85, #88, #91, #94, #97, #100, #110, #119, #122 (PRs #119 and #122 re-added biometric after the reversal decision and were immediately reverted — this pattern has now occurred twice post-IAN-169). If your Sentinel task asks for "biometric protection of [destructive action]" or "app-switcher privacy overlay" — comment: **"Task rejected: biometric authentication was deliberately removed in IAN-169 (2026-04-19). Re-adding it requires explicit owner approval — not Sentinel scope."**

### Destructive-Action Confirmations — REMOVED 2026-05-26

**Product decision (owner):** FormationFlow destructive actions take effect **immediately, with no confirmation dialog**. The data is low-stakes and trivially re-created (re-place athletes, re-add a formation), and a courtside coach wants zero friction. All `.confirmationDialog` modifiers were removed (delete athlete, delete formation, delete routine, reset routine, reset/clear paths, delete waypoint) and their triggers now call the action directly.

**HARD STOP:** Do NOT add `.confirmationDialog`, alerts, Face ID, or any other confirmation/auth layer to a destructive action. Do NOT flag the *absence* of a confirmation as a bug or QA finding — it is intentional. This supersedes the earlier "`.confirmationDialog` is the agreed UX" note from the biometric reversal.

## Commit Hygiene

Before staging any commit, delete all intermediate patch artifacts:
- `*.orig` files (e.g., `SomeView.swift.orig`)
- `*.patch` files
- `patch.diff` or any `*.diff` files
- Root-level `.sh` scripts (e.g., `patch2.sh`, `patch_confirmation.sh` — committed in PR #92)
- Root-level `.py` scripts (e.g., `patch_file.py`, `patch_file2.py` — committed in PR #92)
- Temp Swift files not in the Xcode project (e.g., `test_auth.swift` — PR #35)
- `plan.md` — Jules planning artifact committed in PRs #118, #120 (Apr 2026). In `.gitignore` but will re-appear if `git add -f` is used. Stage by specific path only.
- `.Jules/palette.md`, `.jules/bolt.md`, `.jules/palette.md` — Jules agent state files. **HARD STOP — NEVER commit these files.** Violation count: 10 PRs (#117, #121, #123, #124, #128, #129, #132, #134 and counting). Root cause: `.Jules/` (capital J) was missing from `.gitignore` — added 2026-04-27; both dirs untracked via `git rm --cached`. If any appear in staging: `git reset HEAD .Jules/palette.md .jules/bolt.md .jules/palette.md && git rm --cached .Jules/palette.md .jules/bolt.md .jules/palette.md`. Stage by specific file path only — never `git add .` or `git add .Jules` or `git add .jules`.

All of the above are now in `.gitignore`. Do not use `git add -f` — stage by specific path only. Violations: PR #35 (`test_auth.swift`), PR #92 (4 shell/Python scripts), PRs #118/#120 (`plan.md`), PRs #117/#121/#123/#124/#128/#129/#132/#134 (`.Jules/palette.md`, `.jules/bolt.md`).

## SwiftUI Accessibility: Slider Anti-Pattern

**Do NOT add `.accessibilityValue` to standard SwiftUI `Slider` components.** Sliders already have native VoiceOver support (adjustable actions, announces bounds/percentage). Adding a custom `.accessibilityValue` overrides the native `.adjustable` trait and degrades the VoiceOver experience.

- OK: `.accessibilityLabel("Transition duration")`
- NOT OK: `.accessibilityValue("3 seconds")` on a `Slider` — this breaks native adjustable behavior

This pattern was introduced in PR #12 and corrected in PR #22. The rule is documented in `.jules/palette.md`.

## Imported Claude Cowork project instructions

You are the project manager/supervisor in charge of keeping tabs on what needs to get done, what extra features are being worked on, and updateing linear on progress and what we need from agents
