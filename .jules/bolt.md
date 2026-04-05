## 2025-04-05 - Safe Gestural Geometry Optimization

**Learning:** When calculating geometry (like center of mass) over a collection during high-frequency gesture loops (e.g., rotation gestures), chaining `.map` then `.reduce` allocates redundant intermediate arrays per dimension, triggering O(N) memory allocations per frame.

**Action:** Consolidate these calculations into a single `reduce` pass (e.g., `values.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }`) to eliminate multiple linear iterations and array allocations entirely, resulting in O(1) memory overhead and maintaining smooth 60fps rendering without sacrificing code readability.