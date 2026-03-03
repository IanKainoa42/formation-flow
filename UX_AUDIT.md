# UX Audit — FormationFlow

**Date:** 2026-03-03
**Reviewer:** Claude Code quality pass

---

## Critical

### 1. No formation delete confirmation
**Where:** `FormationListView` — swipe-to-delete on formation rows
**Issue:** Deleting a formation (potentially with many carefully placed athletes) happens instantly on swipe with no confirmation. This is a destructive, irreversible action.
**Fix:** Add `.confirmationDialog` or use `.onDelete` with an intermediate confirmation step.

### 2. Transition picker is a dead end when there's only one formation
**Where:** `TransitionPickerView`
**Issue:** If the user has only one formation, tapping the transition toolbar button shows a screen with just the current formation and no actionable options (no prev/next). The user sees empty space and has no guidance on what to do.
**Fix:** Either disable the transition button when there's only one formation, or show inline guidance ("Create another formation to animate transitions between them").

---

## Major

### 3. Athlete role colors are the only differentiator — no labels
**Where:** `AthleteDetailPanel` role picker, `FloorCanvasView` rendering
**Issue:** Roles are indicated solely by color (blue/yellow/green/purple/orange). Color-blind users cannot distinguish roles. The role picker shows colored circles with no text.
**Fix:** Add role name labels below or beside the color circles in the detail panel. Consider adding a small role initial inside athlete circles on the canvas.

### 4. Transition toolbar icon is not self-explanatory
**Where:** `FloorGridView` trailing toolbar — `arrow.right.circle`
**Issue:** The right-arrow icon doesn't clearly communicate "transitions" or "animate to next formation." Users unfamiliar with the app won't know what this button does.
**Fix:** Use a more descriptive icon (e.g., `play.circle` or `arrow.triangle.2.circlepath`) or add a text label.

### 5. No notes editing UI
**Where:** `Formation` model has a `notes` field, `FormationListView` shows a note icon
**Issue:** There's a notes field on the model and an indicator in the list, but no visible UI to create or edit notes. The note icon appears for formations with notes but users can't reach an editor.
**Fix:** Add a "Notes" option in the FloorGridView overflow menu that presents a sheet with a `TextEditor`.

### 6. No visual feedback during drag
**Where:** `FloorGridView` drag gesture
**Issue:** When dragging an athlete, there's no haptic feedback or visual indicator (like a shadow or scale change) to confirm the drag has started. The snapping to grid also provides no feedback.
**Fix:** Add haptic feedback on drag start. Consider a subtle scale animation on the dragged athlete.

---

## Minor

### 7. "P1", "P2" default labels aren't memorable
**Where:** `FloorGridView.addAthlete()`
**Issue:** New athletes get labels like "P1", "P2" which are generic. For cheer, coaches often think in terms of group letters (A, B, C) and positions.
**Recommendation:** Consider using letter-based defaults (A1, A2, B1, B2) as in the sample formation, or prompt the user to name athletes on creation.

### 8. Collision warning count has no tooltip or explanation
**Where:** `FloorGridView` toolbar — collision count badge
**Issue:** The red triangle with a number appears in the toolbar but there's no explanation of what it means or how to resolve it. New users won't understand "2" with an exclamation mark.
**Fix:** Add a tap action or tooltip explaining "2 athletes are too close together (within 2ft)."

### 9. Duration stepper is small and easy to miss
**Where:** `TransitionPlayerView` — Duration stepper
**Issue:** The duration control uses a small `Stepper` that could be easily overlooked. It's not clear this controls how long the transition takes.
**Recommendation:** Consider making this more prominent or grouping it with the speed control.

### 10. Formation names can be empty
**Where:** Rename alert in `FloorGridView`
**Issue:** The rename alert accepts an empty string, resulting in a formation with no visible name.
**Fix:** Disable the Save button when the text field is empty.

### 11. Swap mode banner could be missed on large screens
**Where:** `FloorGridView` and `TransitionPlayerView` swap mode
**Issue:** The swap mode banner appears at the top and is styled subtly. On a large iPad screen, the user's attention is on the court area, not the top edge.
**Recommendation:** Consider also highlighting the source athlete more prominently (pulsing ring) during swap mode.

### 12. No way to reorder formations from the editor
**Where:** `FormationListView` vs `FloorGridView`
**Issue:** Formation order matters for transitions but can only be changed from the list view (via edit mode drag handles). Users might want to reorder while editing.
**Recommendation:** Low priority — current flow is acceptable but could be streamlined.

---

## Summary

| Severity | Count | Actionable Now |
|----------|-------|----------------|
| Critical | 2     | Yes            |
| Major    | 4     | Partially      |
| Minor    | 6     | Some           |

**Priority fixes (implementing now):**
1. Formation delete confirmation
2. Disable transition button / show guidance when only one formation
3. Prevent empty formation names
4. Add formation notes editing UI
