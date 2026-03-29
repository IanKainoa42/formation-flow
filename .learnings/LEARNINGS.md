# Learnings Log

Corrections, knowledge gaps, and best practices. See `/self-improvement` for format.

## 2026-03-22 — StoreKit config files must be created via Xcode GUI

- **Category:** best_practice
- **What happened:** Manually editing `FormationFlow.storekit` JSON (even with valid-looking content) resulted in Xcode's StoreKit editor showing "No Selection" and `Product.products(for:)` returning empty ("Product not found"). The JSON format is undocumented and varies by Xcode version.
- **Rule:** Always create/modify `.storekit` configuration files through Xcode's visual editor (click "+", fill in fields). Never hand-edit the JSON — Xcode generates internal fields and formatting that aren't publicly documented.
