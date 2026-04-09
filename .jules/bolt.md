## 2025-04-05 - Safe Gestural Geometry Optimization

**Learning:** When calculating geometry (like center of mass) over a collection during high-frequency gesture loops (e.g., rotation gestures), chaining `.map` then `.reduce` allocates redundant intermediate arrays per dimension, triggering O(N) memory allocations per frame.

**Action:** Consolidate these calculations into a single `reduce` pass (e.g., `values.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }`) to eliminate multiple linear iterations and array allocations entirely, resulting in O(1) memory overhead and maintaining smooth 60fps rendering without sacrificing code readability.## 2026-04-09 - KeyPath-Driven  Optimization

**Learning:** When needing to extract specific fields (like `.x` or `.y`) from a collection and filter against another collection, chaining `.map` and `.filter` causes O(N) memory allocations per operation. Using a  parameter allows generalized inline extraction during a single `.compactMap` pass without sacrificing code reusability.

**Action:** Replace  and  inputs with  and , evaluating both inline within  to maintain O(1) extra memory overhead.
## 2026-04-09 - KeyPath-Driven compactMap Optimization

**Learning:** When needing to extract specific fields (like \.x or \.y) from a collection and filter against another collection, chaining .map and .filter causes O(N) memory allocations per operation. Using a KeyPath parameter allows generalized inline extraction during a single .compactMap pass without sacrificing code reusability.

**Action:** Replace `items.map(\.field)` and `candidates.filter { ... }` inputs with `valueExtractor: KeyPath<T, V>` and `targetCondition: Enum`, evaluating both inline within `items.flatMap { candidates.compactMap { ... } }` to maintain O(1) extra memory overhead.
