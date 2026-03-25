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
