# FormationFlow — App Store Screenshot Capture Spec

Autonomous capture flow consumed by `~/.config/appstore-auto/run.sh` (launchd `com.ianrichardson.appstore-auto`, Mon-Fri 5:32am PT).

## Goal
Produce iPad 13" and iPad 12.9" screenshots + app preview videos at native resolution — no more squashed iPhone-source hacks. Also refresh iPhone 6.9" assets.

## Required App Store Connect dimensions
| Device | Portrait | Landscape |
|---|---|---|
| iPad Pro 13" (M4) | 2064 × 2752 | 2752 × 2064 |
| iPad Pro 12.9" | 2048 × 2732 | 2732 × 2048 |
| iPhone 6.9" (15/16 Pro Max) | 1320 × 2868 | 2868 × 1320 |

FormationFlow is landscape-oriented by design — capture in **landscape** for iPad, **portrait** for iPhone.

## Output layout
Everything under `AppStoreScreenshots/auto/<YYYY-MM-DD>/`:
```
auto/
  <date>/
    ipad13/
      screenshot_01_formation_editor.png
      screenshot_02_transition_player.png
      ...
      preview_01_clean.mov            (≤30s, 2752x2064)
      preview_02_collision.mov
      preview_03_swap.mov
    ipad129/
      (same structure, 2732x2048)
    iphone69/
      (same structure, 1320x2868 portrait)
    NOTES.md                          (what was captured, problems, next action)
```

Do not commit. Do not upload to App Store Connect. Ian reviews and uploads manually.

## Prep (idempotent, safe to re-run)
1. `git fetch origin && git status --porcelain` — bail with a NOTES.md note if there are uncommitted changes in tracked files (dirty tree = risk of capturing mid-edit state). Untracked files are fine.
2. Ensure no simulator is stuck: `xcrun simctl shutdown all`.
3. Build for simulator destination (iPad Pro 13"):
   ```
   xcodebuild -project FormationFlow.xcodeproj -scheme FormationFlow \
     -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
     -derivedDataPath /tmp/ff-auto-build build
   ```
4. If the exact device name is missing, list with `xcrun simctl list devicetypes | grep -i ipad` and pick the closest iPad Pro 13"; fall back to iPad Pro 12.9" if needed. Log the substitution in NOTES.md.

## Capture flow per device

For each device type (iPad 13, iPad 12.9, iPhone 6.9):

1. **Boot** the simulator: `xcrun simctl boot <UDID>` then `open -a Simulator`.
2. **Install** the freshly built app: `xcrun simctl install booted /tmp/ff-auto-build/Build/Products/Debug-iphonesimulator/FormationFlow.app`.
3. **Launch**: `xcrun simctl launch booted com.ianrichardson.formationflow`.
4. **Seed demo data** (critical — empty app = useless screenshots):
   - FormationFlow persists to UserDefaults under key `routine.v1`. Before launch, preload a demo routine:
     ```
     xcrun simctl spawn booted defaults write com.ianrichardson.formationflow routine.v1 -data "$(cat .appstore/demo_routine.json | plutil -convert binary1 -o - -)"
     ```
   - If `demo_routine.json` does not yet exist, create one by: launching the app, manually building a 3-formation routine with 8 athletes covering all roles (base/flyer/spotter/backspot/tumbler), then reading `xcrun simctl spawn booted defaults read com.ianrichardson.formationflow routine.v1` and saving it as JSON. **First autonomous run will likely lack this file — log the gap in NOTES.md and capture empty-state screenshots as fallback.**
5. **Wait** for UI to settle (2s).
6. **Take screenshots** via `xcrun simctl io booted screenshot <path>`. Target shots:
   1. Formation editor — full routine, athletes placed, sidebar visible
   2. Transition player — mid-animation with path trails
   3. Multi-formation sidebar — 4+ formations with one selected
   4. Roster management sheet — athletes with role colors
   5. Inspector panel — athlete selected, showing waypoint controls
   6. Collision detection — two athletes overlapping, warning shown
   7. 8-count timing view — transition duration controls
   8. Waypoint editing — curved path with 3+ waypoints
   9. Empty state — fresh routine with empty state copy (use before seeding for this one)
   10. Color roles legend — all 5 role colors visible
7. **Record 3 app preview videos** via `xcrun simctl io booted recordVideo --codec=h264 --mask=ignored <path.mov>`:
   - `preview_01_clean.mov` — 27s walkthrough of clean formation + simple transition
   - `preview_02_collision.mov` — 30s, demonstrates collision detection
   - `preview_03_swap.mov` — 30s, demonstrates athlete swap animation
   - Drive interactions via `xcrun simctl io booted` taps + `peekaboo` if needed. If interactive driving isn't possible headlessly, record the transition player on auto-loop for 27s and let the existing playback animations carry the video.
8. **Verify dimensions** on every output with `sips -g pixelWidth -g pixelHeight` and `ffprobe`. Any file whose dimensions don't match the target exactly gets deleted and logged as FAILED in NOTES.md.
9. **Shutdown** simulator: `xcrun simctl shutdown booted`.

## Known gotchas (learned, do not re-discover)
- **Source-aspect mismatch** — do NOT reuse `AppStoreScreenshots/previews/fixed_preview_*.mov`. Those were iPhone portrait (886x1920) force-scaled to iPad landscape — squashed and warped. Capture natively per device.
- **Models.swift is locked** per CLAUDE.md Known Fragile Areas. Do not touch it during capture prep.
- **Xcode project file** — never edit `FormationFlow.xcodeproj/project.pbxproj` from this flow. Read-only.
- **Simulator timing** — launching the app and immediately screenshotting captures the splash. Wait ≥2s after launch, and ≥500ms after any tap before capture.
- **Permissions** — LaunchAgent runs under Ian's user, so Simulator.app and xcrun have full access. Do not prompt for credentials.

## First-run expectations
On the first autonomous run the agent will likely:
- Succeed at building + booting iPad Pro 13"
- Lack `demo_routine.json` → capture empty states only
- Succeed at screen recordings at correct native dimensions (big win vs squashed files)
- Fail at interactive driving for preview videos → fall back to auto-play of existing routine if any, or record static frames

The NOTES.md file is the handoff. Write it as a punch list of what Ian needs to do to unblock the next run (e.g., "Create demo_routine.json by running the app and exporting UserDefaults").
