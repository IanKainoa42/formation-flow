# FormationFlow

Digital choreography tool for planning formation transitions without requiring the full team physically present.

## Features

- Floor grid visualization (52ft x 30ft standard court)
- Drag-drop athlete placement with labels
- Save/load formations (UserDefaults persistence)
- Formation list with create, rename, duplicate, delete
- Transition animation player with play/pause/scrub/speed control
- Per-athlete move timing (who moves first/last)
- Path visualization with direction arrows
- Path collision detection (red highlight when paths cross)
- Static collision detection (athletes too close)
- Add/remove athletes from formations

## Tech Stack

- Swift 5.9+
- SwiftUI with Canvas rendering
- iOS 17+, iPad optimized
- No external dependencies

## How to Use

1. Clone this repo
2. Open `FormationFlow.xcodeproj` in Xcode 15+
3. Select iPad as target device
4. Run
5. Create a formation, place athletes, save
6. Create a second formation with different positions
7. Go to Transitions, pick start/end, play

## Project Structure

```
FormationFlow/
  FormationFlowApp.swift  - App entry point
  Models.swift            - Data models, persistence, path calculations, animation
  Views.swift             - All views (menu, editor, transitions, canvas)
```

## Next Steps

- [ ] Unit tests for collision detection and path calculations
- [ ] iPad landscape-optimized layout
- [ ] Export formation as image
- [ ] Keyboard shortcuts

---

Built for CFSD

## Quick team setup (Pro)

Open **Roster** from the editor’s tools menu, then choose **Add Team from Names**.
Paste one athlete per line, or copy a spreadsheet’s **Name** and optional **Role**
columns. `Alex Smith, Flyer` also works. Review the suggested 1–3 character floor
labels and roles before adding the team. Full names are shown during review;
only the short labels and roles are saved. Unknown roles start as Base.

Use **Apply Role to Everyone** to assign a shared role, then adjust individual
athletes. Distinct labels are suggested for matching initials or repeated names.
Each batch supports up to 200 athletes and adds to the current roster without
replacing existing athletes or moving their placements.

Choose **Copy Roster from Routine** to reuse another routine’s labels and roles.
Copied athletes get new identities; choreography and positions are not copied.
You can edit existing labels and roles directly in **Manage Roster**.

Run the isolated import and persistence regression checks with:

```sh
Tests/run_bulk_roster_regression.sh
```
