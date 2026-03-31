## ⚠️ FROZEN FILES — Read Before Starting Any Task

The following files are FROZEN. Do not include them as targets for any optimization, refactor, caching, or performance task:

- **`FormationFlow/Models.swift`** — O(N²)→O(N) optimizations applied 6+ times. Violations after explicit hard-stop in CLAUDE.md: PR #34 ("Cache transition path calculations"), PR #38 ("O(1) RoutineStore Formation Lookups"), PR #44 ("Optimize waypoint path rendering allocations"), PR #47 ("Remove O(N) allocations in rendering loop"). 4 post-rule violations total.

**If your task contains:** "cache", "O(1)", "O(N)", "optimize", "allocations", "rendering loop", "waypoint", "lookup", or "reduce" AND your target includes `Models.swift` or `FloorCanvasView.swift` — **stop immediately**.

Output: `"Task rejected: target file frozen per .jules/bolt.md § Frozen Files. Choose a different target."`

This duplicates CLAUDE.md Known Fragile Areas intentionally. Bolt violated CLAUDE.md 4 times post-rule — this file is Bolt's primary instruction source.

## Commit Hygiene — Required Before Every `git add`

Before staging any commit, delete ALL intermediate patch files:
- `*.orig` files
- `patch.diff`, `patch2.diff`, `patch3.diff`, `*.diff` (any name)
- `test_auth.swift` (not in the Xcode project)

Run: `find . \( -name "*.orig" -o -name "*.diff" -o -name "test_auth.swift" \) -delete 2>/dev/null`

formation-flow PR #48 (2026-03-28) committed `test_auth.swift` after this rule existed in CLAUDE.md. This file explicitly adds it because Bolt must enforce it from its primary source.

---

## 2024-05-24 - [O(N^2) Array Lookups in Transition Logic]

**Learning:** `Array.first(where:)` inside a loop or `map` creates an O(N^2) complexity pattern. In `FormationFlow`, this was happening during routine synchronization and transition rendering logic (`TransitionSpec.synchronize` and `transitionPaths` calculations), potentially causing stuttering or high CPU usage with larger rosters.

**Action:** Always pre-calculate a `Dictionary` from arrays using `Dictionary(uniqueKeysWithValues:)` before looping if you need O(1) lookups by ID. This reduces the complexity to O(N).

## 2024-05-19 - [Redundant Loop Calculations inside Animation Block]

**Learning:** `TransitionPlayer.updateAthletesForProgress` was redundantly calculating the effective time (`travelDistance` and `holdTime`) for every single athlete TWICE on *every frame* of animation playback. The first pass collected the maximum effective time for normalization, and the second pass immediately recalculated these exact same values to determine current positions. Because `travelDistance` computes Bezier curves and waypoint segment lengths, duplicating this on every frame scaling linearly with the number of athletes leads to O(N * Frames) unnecessary overhead.

**Action:** When finding the global maximums over a dataset immediately prior to applying them in a mapping operation over the same dataset, cache the expensive derivations from the first pass to eliminate redundant processing in the second pass.

## 2024-05-25 - [Redundant Dictionary Allocations in Animation Frame Loop]

**Learning:** Allocating dictionaries inside highly iterative animation frame functions (e.g., `updateAthletesForProgress`) forces O(N) array mappings and dictionary allocations on every single screen update. This creates excessive memory pressure and high CPU usage overhead in the critical animation path.

**Action:** Whenever generating an O(1) lookup dictionary from an array that doesn't change during the animation loop itself, move the dictionary creation out of the hot path. Cache the resulting dictionary as a private class property and update it via `didSet` property observers on the source arrays (and once in `init()`). This eliminates O(N) repetitive work and memory spikes per frame.

## 2024-05-26 - [O(N^2) Array Lookups in RoutineStore]

**Learning:** `formationIndex(id:)` used `firstIndex(where:)` which is an O(N) operation. This is problematic when it is called repeatedly from functions that loop over formations or athletes, creating an O(N^2) complexity pattern.

**Action:** Maintain an O(1) `formationIndexLookup: [UUID: Int]` dictionary in `RoutineStore` and update it whenever the array of formations changes (e.g. in `reconcileTransitionSpecs()`). Use this dictionary in `formationIndex(id:)` and expose `formation(id:)` to prevent the O(N) overhead.

## 2024-11-20 - Prevent O(N^2) Math During Animation Loop

**Learning:** SwiftUI computed properties are evaluated on every render loop. In `FloorGridView.swift`, calculating the static collision summary (`collisionSummary`) during an animation loop caused O(N^2) spatial math to run on every single frame, leading to CPU spikes. Because the UI uses a separate mechanism (`pathCollidingAthletes`) to track collisions *during* transitions, evaluating the static frame collisions while scrubbing or playing is redundant and computationally expensive.

**Action:** Add an early return to expensive computed properties when the application is actively animating (e.g., `if let player, player.progress > 0 && player.progress < 1 { return (0, []) }`). This prevents O(N^2) logic from running continuously during 60fps frame ticks.

## 2026-03-27 - Prevent O(N) Array Allocations in Render Loop

**Learning:** Re-calculating array segment nodes and lengths on every frame of an animation loop (like `waypointNodes` and `segmentLengths` inside `interpolateWaypointPath`) creates significant memory pressure and GC overhead due to O(N) array allocations at 60fps.

**Action:** When interpolating positions along a segmented path, pre-calculate and cache the static geometric data (nodes, lengths, totalLength) outside the render loop. Pass the cached arrays into the interpolation function to perform pure math without heap allocations per frame.

## 2026-03-28 - Prevent O(N) Dictionary Allocations and Maps in Rendering Loop

**Learning:** Allocating dictionaries and performing maps within high-frequency rendering functions, like `drawTrails` and `drawTransitionPaths` in `FloorCanvasView.swift`, leads to unnecessary CPU and memory overhead during animation loops. This issue manifests in redundant `Dictionary(uniqueKeysWithValues:)` operations inside iterative updates and `map` functions applied on geometric path arrays over every frame.

**Action:** Eliminate the need to construct a dictionary by iterating directly over the list that contains the full details or caching geometric nodes (like path waypoints) in models. Utilize properties cached in corresponding structs (e.g. adding `nodes` to `TransitionPathRenderItem`) to sidestep calculating path allocations on each frame.

## 2026-03-30 - Prevent O(N) Array Allocations for Overlays in Render Loop

**Learning:** Computed properties in SwiftUI views (like UI overlays) are re-evaluated frequently, especially during animation loops when reactive state changes 60 times a second. Performing `filter` or `map` operations in these properties creates O(N) array allocations per frame, leading to memory pressure, GC overhead, and reduced battery life even if the values aren't strictly necessary during active animation.

**Action:** Identify computed properties responsible for static contextual UI (like collision alerts, ghost athletes, or endpoint markers) and add early returns during active animation states (e.g., `if let player, player.progress > 0 && player.progress < 1 { return [] }`) to short-circuit the O(N) allocations when the visual fidelity isn't critical or is handled by a different mechanism during playback.
