# Learnings Log

Corrections, knowledge gaps, and best practices. See `/self-improvement` for format.

## 2026-03-22 — StoreKit config files must be created via Xcode GUI

- **Category:** best_practice
- **What happened:** Manually editing `FormationFlow.storekit` JSON (even with valid-looking content) resulted in Xcode's StoreKit editor showing "No Selection" and `Product.products(for:)` returning empty ("Product not found"). The JSON format is undocumented and varies by Xcode version.
- **Rule:** Always create/modify `.storekit` configuration files through Xcode's visual editor (click "+", fill in fields). Never hand-edit the JSON — Xcode generates internal fields and formatting that aren't publicly documented.

## 2026-04-19 — Two algorithms computing the "same" check will drift

- **Category:** best_practice
- **What happened:** Path-crossing detection was duplicated: `PathCalculations.findPathCollisionIDs` decided which paths turn red (timing-aware — moveDelay normalized against effectiveCounts, holdAdjustedPathProgress for waypoint holds, Catmull-Rom interpolation). `FloorCanvasView.pathCollisionMarkers` decided where to draw the red star markers, using its own `sampledPathPoints` sampler (naive delay via `Array(repeating: start) + samples`, no holds, equal steps per segment). The two samplers placed athletes at different positions at the same "step index," so athlete paths turned red without any marker appearing. A second duplication existed in `FloorGridView.cachedPathCollisionIDs` (a `@State` recomputed only in a few onChange hooks) that shadowed `player.cachedPathCollisionIDs`.
- **Rule:** When a UI renders a computed result AND a secondary artifact derived from the same computation (e.g., IDs + visual marker positions), return both from a single function and cache them together. Never let the view layer re-derive "where did the detected event happen" with its own sampler — it will drift from the detection logic. For the FormationFlow collision-marker bug: `findPathCollisionMarkers` now returns `(ids, markers)` in one call; `TransitionPlayer` caches both; views consume the cache. Canvas sampler deleted.
