## 2024-05-24 - [O(N^2) Array Lookups in Transition Logic]

**Learning:** `Array.first(where:)` inside a loop or `map` creates an O(N^2) complexity pattern. In `FormationFlow`, this was happening during routine synchronization and transition rendering logic (`TransitionSpec.synchronize` and `transitionPaths` calculations), potentially causing stuttering or high CPU usage with larger rosters.

**Action:** Always pre-calculate a `Dictionary` from arrays using `Dictionary(uniqueKeysWithValues:)` before looping if you need O(1) lookups by ID. This reduces the complexity to O(N).
