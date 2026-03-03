# Friction Audit — FormationFlow

**Date:** 2026-03-03
**Goal:** Identify every point where a user might drop off, get confused, or feel resistance.

---

## Time-to-First-Value

**Current flow:** Open app → See empty list → Tap + → Land on empty court → Tap + to add athlete → Drag athlete → See something useful.

**Steps to first value: 4 taps + a drag** (open → create → add athlete → position → see result)

| Step | Action | Friction |
|------|--------|---------|
| 1 | Open app | Empty state says "Tap + to create your first formation" — clear |
| 2 | Tap + | Creates "Formation 1" and navigates to editor — good |
| 3 | See empty court | Empty state says "Tap + to add athletes" — clear |
| 4 | Tap + to add athlete | Athlete appears, selected with detail panel — good |
| 5 | Drag to position | Snap-to-grid, immediate visual feedback — good |

**Verdict:** Acceptable. Could be faster with a pre-populated sample formation on first launch, but the current 4-step flow is reasonable. The empty states guide the user well.

---

## Friction Points (Priority Order)

### P0 — Blocking or highly confusing

#### 1. Transition setup requires non-obvious prerequisite
**Where:** Transition toolbar button → TransitionPickerView
**Issue:** To see a transition animation, the user must:
1. Create formation A
2. Go back to list
3. Create formation B
4. Open formation A (or B)
5. Tap the transition arrow
6. Tap Prev/Next to start playback

This is a 6-step process with no in-app guidance explaining that transitions work between adjacent formations in the list. The relationship between formation order and transition availability is not communicated.
**Fix (implemented):** Transition button is now disabled when only 1 formation exists. **Remaining:** Add a tooltip or inline text when the user first reaches the transition picker explaining the concept.
**Quick win:** N/A — needs design thought.

#### 2. Athlete order coupling between formations is invisible
**Where:** Transition animation logic
**Issue:** Transitions match athletes by array index (athlete[0] in formation A moves to athlete[0] in formation B). If the user adds athletes in different orders across formations, the wrong athletes will animate to the wrong positions. There's no visual indication of this pairing, and no way to see or fix it from the transition screen.
**Fix:** This is an architectural issue. Consider matching by athlete ID instead of index, or showing athlete pairing in the transition picker.
**Quick win:** N/A — requires design decision.

---

### P1 — Causes confusion or wasted time

#### 3. Bezier curve handle is undiscoverable
**Where:** TransitionPlayerView — path midpoint handle
**Issue:** Users can drag the midpoint of a selected athlete's path to create curved transitions. This is a powerful feature but completely undiscoverable — there's no visual hint, tooltip, or onboarding. The white circle handle only appears when an athlete is selected and paths are shown.
**Fix:** Add a brief "Drag the path to curve it" hint the first time a user selects an athlete in the transition player.
**Quick win:** N/A — needs first-run hint system.

#### 4. Collision warning has no actionable guidance
**Where:** FloorGridView toolbar — red triangle badge
**Issue:** The collision count appears but tapping it does nothing. The user knows "something is wrong" but not which athletes are colliding or what to do about it. The red rings on athletes help visually, but on a crowded court they could be hard to spot.
**Fix (suggested):** Make the collision badge tappable to zoom/highlight the first collision pair, or show a popover listing colliding athletes.
**Quick win:** N/A — needs UI work.

#### 5. No way to cancel a formation creation
**Where:** FormationListView → FloorGridView
**Issue:** When tapping +, a formation is immediately created and saved. If the user decides they don't want it, they must go back to the list and swipe to delete. There's no "cancel" or "discard" option.
**Fix (suggested):** Delay persistence until the user explicitly saves, or add a "Delete Formation" option in the overflow menu.
**Quick win:** Add "Delete Formation" to the overflow menu (implementing below).

---

### P2 — Mild friction or polish

#### 6. Undo only works for position moves, not other edits
**Where:** FloorGridView — undo stack
**Issue:** Undo tracks position changes but not label edits, role changes, or athlete additions/deletions. Users might expect a full undo system.
**Verdict:** Acceptable for current scope. The most common mistake (mis-positioning) is covered.

#### 7. Swap mode requires precise tapping
**Where:** FloorGridView swap mode
**Issue:** After entering swap mode, the user must tap precisely on another athlete (within 3ft hit radius). On a crowded court, this could be fiddly. Missing the target cancels swap mode with no feedback.
**Verdict:** Acceptable. The 3ft radius is generous enough for most use cases.

#### 8. Speed control uses a menu instead of direct controls
**Where:** TransitionPlayerView — speed menu
**Issue:** Changing playback speed requires opening a menu and selecting a preset. For quick adjustments, a slider or +/- buttons would be faster.
**Verdict:** Acceptable. The preset speeds cover common needs.

#### 9. Move timing slider maximum equals duration
**Where:** TimingControlsView
**Issue:** The timing slider goes up to the full duration, meaning an athlete could be set to start moving at the very end (effectively not moving). This isn't harmful but could confuse users who accidentally max out the slider.
**Verdict:** Acceptable. The labels "Moves first" / "Moves last" provide context.

#### 10. Double-tap to reset zoom is undiscoverable
**Where:** FloorGridView — double-tap gesture
**Issue:** Double-tapping resets zoom and pan, but there's no indication this gesture exists.
**Fix (suggested):** Add a "Reset View" button that appears when zoom ≠ 1.0 or pan ≠ 0.
**Quick win:** Implementing below.

---

## Destructive Action Review

| Action | Guard | Verdict |
|--------|-------|---------|
| Delete formation | Confirmation dialog (added in UX audit) | Good |
| Delete athlete | Confirmation dialog (added in kitchen sink pass) | Good |
| Remove path control point | "Straight" button, no confirm | Acceptable — easily re-created |
| Swap positions | Immediate, no undo for swap | Minor risk — swap is reversible by swapping again |

---

## Dead Ends

| State | What user sees | Guidance | Status |
|-------|---------------|----------|--------|
| No formations | Empty state with instruction | Good |
| Empty formation (no athletes) | "Tap + to add athletes" overlay | Good |
| Only 1 formation, tap transitions | Button now disabled | Fixed |
| Transition picker with only prev OR next | One side shows, other is empty space | Acceptable |

---

## Quick Wins Implementing

1. **Add "Delete Formation" to editor overflow menu** — lets users discard from within the editor
2. **Add "Reset View" button** — appears when zoomed/panned, makes the gesture discoverable
