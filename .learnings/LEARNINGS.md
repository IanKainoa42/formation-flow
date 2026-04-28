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

## 2026-04-28 — Fullscreen layout: keep GeometryReader as root, don't wrap in VStack

- **Category:** correction
- **What happened:** Converting RoutinePlaybackView's bulky transport bar to a thin one, I refactored from `GeometryReader { ZStack { Color.black; FloorCanvasView; close-btn; bottom-bar } }` to `VStack(spacing: 0) { ZStack { Color.black; GeometryReader { FloorCanvasView }; close-btn }; bottomBar }`. The ZStack-with-Color.black made the inner GeometryReader report a tiny height, so the floor crammed into the top with a huge black gap below. User: "you have to be joking."
- **Rule:** For fullscreen playback views with a transport bar at bottom, keep `GeometryReader` as the root, reserve a `private static let bottomBarHeight: CGFloat = 56` (or similar), subtract it explicitly when computing `cellSize` and `offsetY`, and place the bar in an overlapping `VStack { Spacer(); bar.frame(height: bottomBarHeight) }` inside the root ZStack. Sibling-VStack-with-GeometryReader-inside-ZStack does NOT size correctly when a `Color` is also expanding inside the ZStack.

## 2026-04-28 — Persistence is a JSON file in Documents, NOT UserDefaults

- **Category:** knowledge_gap
- **What happened:** Trying to seed demo data into a fresh iPhone simulator via `xcrun simctl spawn <UDID> defaults write com.ianrichardson.formationflow routine.v1 -data ...`, then `defaults read com.ianrichardson.formationflow` returned "Domain does not exist." Both CLAUDE.md and `.appstore/capture.md` claim persistence is `UserDefaults` under key `routine.v1` — outdated. Models.swift (lines ~1228–1285) actually saves to `documentDirectory.appendingPathComponent("routine.v1.json")` and `workspace.v1.json`, with a one-shot migration that reads the old `UserDefaults` key on first launch and removes it. The .plist preferences file in the simulator container only contains UISplitViewController + StoreKit transaction state.
- **Rule:** To inject app state into a simulator for FormationFlow, copy a JSON file directly into `$(xcrun simctl get_app_container <UDID> com.ianrichardson.formationflow data)/Documents/workspace.v1.json` (the active key — `routine.v1.json` is legacy/migrated). A reusable demo snapshot now lives at `.appstore/demo_routine.json`. CLAUDE.md and `.appstore/capture.md` need a small update to remove the `defaults write` instruction.

## 2026-04-28 — `#if DEBUG` does not fire — `SWIFT_ACTIVE_COMPILATION_CONDITIONS` missing from pbxproj

- **Category:** knowledge_gap
- **What happened:** `EntitlementManager.isTestBuild` (intended to auto-grant Pro to developers in dev builds) is gated by `#if DEBUG`, but `SWIFT_ACTIVE_COMPILATION_CONDITIONS` is not set in `FormationFlow.xcodeproj/project.pbxproj` for any configuration. Default Xcode templates set this to `"DEBUG $(inherited)"` for the Debug config, but this project doesn't — meaning `#if DEBUG` evaluates to false even when running the Debug scheme. Result: a fresh sim install shows the Pro paywall on the play button (`isPro == false`), even though the developer comment expects Pro to be granted.
- **Rule:** Don't trust `#if DEBUG` in this project until `SWIFT_ACTIVE_COMPILATION_CONDITIONS` is added to the Debug config. For dev workflows that need Pro state, either make a sandbox StoreKit purchase once (it persists in the sim's Keychain) OR add `SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)"` to the Debug build settings via Xcode's project editor (not by hand-editing pbxproj).

## 2026-04-28 — iOS Simulator does not expose iOS a11y to Mac AX tree

- **Category:** knowledge_gap
- **What happened:** `peekaboo click "Formation 2" --app Simulator` returned "No actionable element found." Peekaboo can drive Mac UI via accessibility but the iOS Simulator renders iOS content as a single opaque view from Mac's perspective — iOS a11y elements are not bridged. Coordinate-only clicks via `peekaboo click --coords "X,Y"` work but require precise Mac-screen-space math (Sim window origin + content offset for title bar + image-scale factor). Manual estimates were off; clicks landed on wrong rows.
- **Rule:** For headless screenshot diversity (multiple in-app states), don't try to drive iOS Simulator UI from Mac AX or coordinate clicks. Use one of: (a) seed multiple `workspace.v1.json` snapshots to capture different starting states; (b) capture during the auto-running transition preview (which animates without input) at staggered timing; (c) write an XCTest UI test target that drives the iOS app directly. Coordinate clicks are too brittle to maintain.

## 2026-04-28 — `fastlane deliver` needs a Deliverfile to run non-interactively

- **Category:** knowledge_gap
- **What happened:** Running `fastlane deliver --skip_binary_upload --skip_metadata --overwrite_screenshots --force ...` from a non-TTY context crashed with `Could not retrieve response as fastlane runs in non-interactive mode` — fastlane was prompting "No deliver configuration found in the current directory. Do you want to setup deliver?" CLI flags alone don't suppress this prompt; the existence of `fastlane/Deliverfile` does.
- **Rule:** For headless screenshot uploads in this repo, ensure `fastlane/Deliverfile` exists (committed minimal config: `app_identifier`, `team_id`, `screenshots_path`, `overwrite_screenshots true`, `skip_binary_upload true`, `skip_metadata true`). Then `fastlane deliver --api_key_path fastlane/AuthKey.json --skip_binary_upload --skip_metadata --overwrite_screenshots --force` runs to completion. AuthKey.json must contain `key_id` + `issuer_id` + inline `key` (the .p8 contents with literal `\n` between PEM lines). The repo's preferred ASC API key is `8APDGY74BZ` (.p8 at `~/.appstoreconnect/private_keys/AuthKey_8APDGY74BZ.p8`); a third key `8C642247AP` exists locally but is not referenced anywhere — verify before swapping.

## 2026-04-28 — fastlane deletes legacy device-class slots before uploading

- **Category:** best_practice
- **What happened:** Today's screenshot upload deleted `APP_IPAD_PRO_3GEN_11` and `APP_IPHONE_67` slots in ASC before uploading our 2752×2064 / 2732×2048 / 1320×2868 files. Those legacy slots (iPad Pro 11" 3rd gen, iPhone 6.7") are different device classes from our targets (iPad Pro 13" M4, iPhone 6.9" Pro Max). Without checking ASC web UI afterward, you can't tell whether fastlane mapped the new files to the *current* device classes or silently skipped them.
- **Rule:** After every `fastlane deliver` screenshot run, open App Store Connect → My Apps → FormationFlow → 1.0.0 → Screenshots tab and visually verify each device class slot received the right files. Do not assume "Successfully uploaded all screenshots" means the slots are correctly populated — it just means no upload errors. fastlane 2.233 may not know about the newest device classes (iPad Pro M4 13", iPhone 6.9").

## 2026-04-28 — ASC API has NO separate iPhone 6.9" / iPad 13" display types

- **Category:** knowledge_gap
- **What happened:** Tried to upload via ASC API with `screenshotDisplayType: "APP_IPHONE_69"` and `"APP_IPAD_PRO_3GEN_13"` — both returned 409 ENTITY_ERROR.ATTRIBUTE.TYPE: "not a valid value." Apple consolidates the new device dimensions into the existing slots: 1320×2868 iPhone Pro Max content goes into `APP_IPHONE_67`, and 2752×2064 iPad Pro 13" (M4) content goes into `APP_IPAD_PRO_3GEN_129`. ASC accepts both old and new dimensions in the same set, and dispatches to the customer's device based on closest match.
- **Rule:** When uploading FormationFlow screenshots via ASC API, use only these display types: `APP_IPAD_PRO_3GEN_129` (accepts both 2732×2048 and 2752×2064), `APP_IPHONE_67` (accepts both 1290×2796 and 1320×2868). Use `/tmp/asc_upload_screenshots.py` (saved 2026-04-28 in this session) as the working uploader — it deletes existing sets and re-uploads via signed URL chunks. Verify via `/tmp/verify_screenshots.py` (also saved 2026-04-28) which prints per-set dimension distribution.

## 2026-04-28 — `xcrun altool` actually works (memory said it was broken)

- **Category:** correction
- **What happened:** Memory's `project_altool_broken_use_transporter.md` and CLAUDE.md/MEMORY.md note "altool is broken on this Mac (missing Defaults.properties); upload via Transporter.app instead." Today, `xcrun altool --upload-app --type ios --file /tmp/FormationFlow.ipa --apiKey 8APDGY74BZ --apiIssuer 7642a25e-...` worked first try: "UPLOAD SUCCEEDED with no errors" using altool 26.30.4 from Xcode (path: `/Applications/Xcode.app/Contents/SharedFrameworks/ContentDelivery.framework/Resources/altool`). The Defaults.properties bug appears to be fixed in current Xcode.
- **Rule:** Try `xcrun altool` first for IPA uploads — it's faster and headless. Only fall back to Transporter.app if altool fails with the specific Defaults.properties error. The memory note about altool being broken should be removed once verified working across multiple uploads.

## 2026-04-28 — ASC accumulates "mystery" build numbers between local sessions

- **Category:** best_practice
- **What happened:** Local CURRENT_PROJECT_VERSION was at 160 today. altool rejected upload with "previousBundleVersion: 161" — meaning ASC already had build 161 from somewhere not visible in our local git. This is the SECOND time the local-vs-ASC build counter has drifted (memory: "tried to upload 152, ASC already had 153, had to bump to 154"). Likely sources: Gemini auto-uploads, fastlane lane runs from another machine, or ASC keeping older artifacts.
- **Rule:** Before uploading any IPA, expect ASC to be 1-3 builds ahead of local. Bump CURRENT_PROJECT_VERSION generously (e.g., +5 buffer) OR be ready to bump-and-retry on first failure. After altool rejects with "previousBundleVersion: N", immediately bump to N+1 and re-sign+re-upload — full re-archive isn't needed; just `plutil -replace CFBundleVersion -string "N+1" Info.plist` inside the existing .app, re-codesign with the entitlements, re-zip, retry altool. Saves 2-3 min vs full archive rebuild.
