# FormationFlow Freemium Design

## Overview

Gate FormationFlow behind a freemium model with a one-time $4.99 IAP ("FormationFlow Pro"). Free users get a meaningful taste of the app. Pro unlocks the full feature set.

## Free vs Pro Boundaries

### Free Tier
- 1 routine (already the only mode — no multi-routine support yet)
- Up to 3 formations per routine
- Place and drag athletes on the court grid
- Default Base role (circle marker) — cannot change to other roles
- Transition playback (A→B, B→C)
- Basic path adjustment via the single `pathControlPoint` (straight-line drag)
- Formation notes
- Bowling Pin template
- Transition share/export

### Pro Tier ($4.99 one-time)
- Unlimited formations per routine
- Multiple routines (future feature — no code exists yet, gated when built)
- Role assignments (change from default Base to Flyer, Spotter, Backspot, Tumbler, Stunt Group)
- Move delays and hold durations (staggered entries = per-athlete move delays)
- Waypoint creation (tap-to-add on paths)
- Smooth/linear waypoint toggle (Bezier curves)

## Architecture

### Approach: Local-only entitlement with StoreKit 2

No server, no third-party SDK. Apple handles purchase verification via on-device transaction history. This preserves the app's "Data Not Collected" privacy label and offline-first philosophy.

### New Files

#### `EntitlementManager.swift`

`@MainActor` ObservableObject with a single published property: `isPro: Bool`.

Responsibilities:
- On init: read cached `isPro` from UserDefaults (instant, no flash), then async-refresh via `Transaction.currentEntitlements`
- `purchase() async throws -> Bool`: fetch product, execute purchase, update `isPro`, cache to UserDefaults
- `restore() async`: re-check `currentEntitlements`, update cache (handles reinstalls, new devices)
- Listen for `Transaction.updates` to catch external purchases (e.g., Ask to Buy, promo codes, refunds)
- Cache `isPro` in UserDefaults for instant UI state on cold launch — `Transaction.currentEntitlements` is authoritative async refresh

Product ID: `com.ianrichardson.formationflow.pro`

Injected at app root as `.environmentObject(entitlementManager)`.

#### `ProUpgradeSheet.swift`

Modal sheet presented whenever a gated feature is tapped by a free user.

Content:
- App icon
- "Unlock FormationFlow Pro" heading
- Bullet list: Unlimited formations, Athlete roles & colors, Timing controls, Advanced path waypoints, Multiple routines (soon)
- Primary button: "Upgrade — $4.99" → calls `entitlementManager.purchase()`
- Link: "Restore Purchase" → calls `entitlementManager.restore()`
- Footer: "One-time purchase. No subscription."
- Purchase button states: idle → loading (spinner) → success (auto-dismiss) / cancelled (dismiss spinner) / pending "Waiting for approval" message (Ask to Buy) / error (alert with retry)
- Auto-dismiss on success

### Free Tier Limits

```swift
enum FreeTierLimits {
    static let maxFormations = 3
    static let maxRoutines = 1
}
```

## Gating UX Pattern

Consistent across all gated features: **show everything, lock what's Pro.**

Free users see the full UI — buttons, controls, pickers — but Pro-only features display a lock icon overlay. Tapping a locked element presents the upgrade sheet. This maximizes discovery of Pro value without creating a degraded experience.

### Gating Points (existing file changes)

#### `FormationFlowApp.swift`
- Create `EntitlementManager()` instance
- Inject via `.environmentObject`

#### `FormationHomeView.swift` (contains `RoutineWorkspaceView`)
- "+ Formation" button: if `!isPro && formations.count >= FreeTierLimits.maxFormations`, show lock icon, tap triggers paywall sheet
- "Duplicate as Next" (context menu, toolbar button, compact overflow menu): same formation count check — this is a second path to creating formations that must be gated
- When under the limit, both buttons work normally regardless of Pro status

#### `AthleteDetailPanel.swift`
- Role picker: all role options visible with lock icon overlay when `!isPro`
- Tapping any locked role → paywall sheet
- Free users see the default Base role (blue circle) but cannot change it — model defaults `role` to `.base`

#### `TimingControlsView.swift`
- Move delay slider: disabled + lock overlay when `!isPro`
- Hold duration controls: disabled + lock overlay when `!isPro`
- Tapping locked controls → paywall sheet

#### `FloorGridView.swift`
- Waypoint creation (tap-to-add on path): gated when `!isPro`
- Smooth/linear waypoint toggle: gated when `!isPro`
- Basic `pathControlPoint` drag: **stays free** — this is the core value demo

#### `Models.swift`
- No changes. Limits enforced at view/store level, not data model.

## App Store Connect Setup

- Product type: Non-Consumable
- Product ID: `com.ianrichardson.formationflow.pro`
- Reference Name: FormationFlow Pro
- Price: $4.99 (Tier 5)
- Requires Paid Apps agreement to be active

## Privacy Impact

None. StoreKit 2 transactions are handled entirely on-device by Apple. No data is sent to any server. "Data Not Collected" privacy label remains accurate.

## Edge Cases

- **User downgrades (refund):** `Transaction.updates` listener catches revocation → set `isPro = false`. Existing formations beyond 3 are preserved but user cannot add more. Existing role assignments remain visible but cannot be changed.
- **Existing data exceeds free limits after refund:** Don't delete user data. Just prevent creating new items beyond limits. User can still view and play transitions for all existing formations.
- **No network on purchase attempt:** StoreKit 2 handles this — shows Apple's system error UI.
- **Ask to Buy (family sharing):** `Transaction.updates` picks up the deferred → approved flow automatically.
- **Family Sharing:** Non-Consumable IAPs are shared by default across Family Sharing groups. If the original purchaser gets a refund, all family members lose access. This is acceptable default behavior for $4.99.

## Files Summary

| File | Action |
|------|--------|
| `EntitlementManager.swift` | New — StoreKit 2 entitlement logic |
| `ProUpgradeSheet.swift` | New — paywall UI |
| `FormationFlowApp.swift` | Modified — inject EntitlementManager |
| `FormationHomeView.swift` | Modified — gate "+ Formation" button |
| `AthleteDetailPanel.swift` | Modified — gate role picker |
| `TimingControlsView.swift` | Modified — gate timing controls |
| `FloorGridView.swift` | Modified — gate waypoint creation |
| `FormationFlow.storekit` | New — StoreKit testing configuration for Xcode |
| `Models.swift` | Unchanged |
