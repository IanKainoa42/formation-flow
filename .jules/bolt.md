## 2024-05-24 - [O(N^2) Array Lookups in Transition Logic]

**Learning:** `Array.first(where:)` inside a loop or `map` creates an O(N^2) complexity pattern. In `FormationFlow`, this was happening during routine synchronization and transition rendering logic (`TransitionSpec.synchronize` and `transitionPaths` calculations), potentially causing stuttering or high CPU usage with larger rosters.

**Action:** Always pre-calculate a `Dictionary` from arrays using `Dictionary(uniqueKeysWithValues:)` before looping if you need O(1) lookups by ID. This reduces the complexity to O(N).

## 2024-05-19 - [Redundant Loop Calculations inside Animation Block]

**Learning:** `TransitionPlayer.updateAthletesForProgress` was redundantly calculating the effective time (`travelDistance` and `holdTime`) for every single athlete TWICE on *every frame* of animation playback. The first pass collected the maximum effective time for normalization, and the second pass immediately recalculated these exact same values to determine current positions. Because `travelDistance` computes Bezier curves and waypoint segment lengths, duplicating this on every frame scaling linearly with the number of athletes leads to O(N * Frames) unnecessary overhead.

**Action:** When finding the global maximums over a dataset immediately prior to applying them in a mapping operation over the same dataset, cache the expensive derivations from the first pass to eliminate redundant processing in the second pass.
