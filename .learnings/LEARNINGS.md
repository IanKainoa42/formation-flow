# Learnings Log

Corrections, knowledge gaps, and best practices. See `/self-improvement` for format.

## 2026-05-18 — SwiftUI animation needs stable view identity — opacity-gate, don't conditional-render

- **Category:** correction
- **What happened:** Built a long-press progress ring around an athlete using `Circle().trim(from: 0, to: progress)` inside an `if let armingPos = state { ... }` overlay. The user reported "it works but there's no animation." Root cause: when `armingPos` flipped from `nil` to non-nil, the overlay's body produced a brand-new view, so SwiftUI had no prior `trim(to:)` value to interpolate from. The `withAnimation(.linear(duration: 0.35)) { progress = 1.0 }` ran, but the ring rendered at the final state (1.0) immediately, not the animated 0→1 transition.
- **Rule:** For animations on properties of a transiently-visible view (`.trim`, `.scaleEffect`, `.rotationEffect`, etc.), always render the view in the hierarchy and gate visibility with `.opacity(...)`. Conditional rendering (`if let`) destroys view identity and forfeits animation interpolation on the first appearance. Also explicitly reset the animated value to its start state BEFORE the `withAnimation` call so the from-state is unambiguous: `progress = 0; withAnimation(...) { progress = 1.0 }`. **Caveat:** A bare assignment like `progress = 0` does NOT bypass an in-flight `withAnimation` transaction — it gets folded into the existing animation and continues smoothly from the current value. If the user re-triggers (e.g., re-press during exit animation), they'll see the new ring inherit a stale partial value. Force-reset with `withTransaction(Transaction { $0.disablesAnimations = true }) { progress = 0; armingPosition = newAnchor }`, then start the new `withAnimation(...) { progress = 1.0 }`.

## 2026-05-18 — "Fixed size" UI means constraining EVERY contributing variable, not just one

- **Category:** correction
- **What happened:** User said "make the badge stay the same size." First pass only fixed pip-slot widths (so the row didn't reflow on cycle). But the badge as a whole still resized because: (a) different formation names had different widths → name pushed badge wider, (b) optional sub-lines (transition preview, ghost label) appeared/disappeared → badge grew taller, (c) pip count grew with routine length → row widened. Fixing one of three variables doesn't deliver "fixed size."
- **Rule:** When the user asks for fixed-size UI, enumerate every variable that contributes to layout and constrain each one: (1) variable-count children → scale them to fit a budget OR cap and ellipsize; (2) variable-length text → `.lineLimit(1) .truncationMode(.tail) .frame(width:)`; (3) optional sub-views → either remove them, reserve fixed slots whether or not they're populated, or accept the variance only along one axis. Hard-pin the container with `.frame(width:, height:)` after constraining its contents. Confirm by mentally cycling through all the empty/full/long/short permutations.

## 2026-05-18 — When one sibling in a row differs in size, give every sibling a fixed slot

- **Category:** correction
- **What happened:** Built the formation-context pip row in `FloorGridView.formationContextBadge` with the current pip at 14pt and others at 7pt. Each pip's `.frame` was sized directly to the dot, so when the user tapped the button to cycle, the HStack reflowed (different pip became the 14pt one) and the rounded-rect background subtly resized — read by the user as the button "popping bigger" on every press. Also `.buttonStyle(.plain)` left zero press-state visual.
- **Rule:** For rows of items where one is visually emphasized (larger/colored) and the rest are minor, give every slot a fixed outer frame matching the largest possible size, then render the smaller dot centered inside that slot. The container's measured size stays constant across state changes and you avoid implicit layout animation on the parent. Apply `.animation(nil, value: <toggleState>)` to the row as belt-and-suspenders. Separately: when you strip a button's default visual with `.buttonStyle(.plain)`, you owe the user an explicit pressed-state effect (scale + brightness) via a custom `ButtonStyle`.

## 2026-04-30 — ASC submission flow: legacy endpoint is read-only, use v2 reviewSubmissions

- **Category:** knowledge_gap
- **What happened:** `POST /v1/appStoreVersionSubmissions` returns 403 `FORBIDDEN_ERROR` with `"The resource 'appStoreVersionSubmissions' does not allow 'CREATE'. Allowed operation is: DELETE"`. Apple migrated submission to the v2 reviewSubmissions flow. Also: a rejected version stays bound to its prior submission (`UNRESOLVED_ISSUES` state) and POSTing a new `reviewSubmissionItems` returns 409 `STATE_ERROR.ITEM_PART_OF_ANOTHER_SUBMISSION`. Cancel the old one first.
- **Rule:** To submit (or resubmit after rejection) via API:
  1. If a prior reviewSubmission is in `UNRESOLVED_ISSUES`: `PATCH /v1/reviewSubmissions/{old} {"data":{"type":"reviewSubmissions","id":"{old}","attributes":{"canceled":true}}}` → state goes `CANCELING`, poll until `COMPLETE`.
  2. `POST /v1/reviewSubmissions` with `{platform:"IOS"}` + app relationship → returns new submission in `READY_FOR_REVIEW`.
  3. `POST /v1/reviewSubmissionItems` with reviewSubmission + appStoreVersion relationships → adds the version.
  4. `PATCH /v1/reviewSubmissions/{new} {"attributes":{"submitted":true}}` → state goes `WAITING_FOR_REVIEW` with `submittedDate`. That's submission complete.
- **Build swap pattern:** `PATCH /v1/appStoreVersions/{vid}/relationships/build` with `{"data":{"type":"builds","id":"{bid}"}}` returns 204 No Content. Works on `PREPARE_FOR_SUBMISSION` versions even with prior rejected build attached.
- **Age rating:** lives on AppInfo (`/v1/appInfos/{id}/ageRatingDeclaration`), not directly on App or appStoreVersion. ASC auto-creates a default declaration; for a clean coaching/utility app it's already all NONE/false → 4+. No action needed.

## 2026-04-29 — Multiple `routine.X` mutations in one method storm SwiftUI List's UICollectionView coordinator

- **Category:** correction
- **What happened:** Roster delete crashed with `_Bug_Detected_In_Client_Of_UICollectionView_Invalid_Number_Of_Items_In_Section`. Two prior fixes did NOT resolve it: (1) replacing `.onDelete` with `.swipeActions`, (2) deferring the deletion via `DispatchQueue.main.async`. Both still crashed. Real root cause: `RoutineStore.deleteAthlete` did `routine.roster.removeAll`, then `routine.formations[i].placements.removeAll` for every formation, then `routine.transitionSpecs[i].athleteTransitions.removeAll` for every spec, then `reconcileTransitionSpecs()` (which re-assigns `routine.transitionSpecs`). Each line mutates `routine` (a computed property over `@Published var workspace`), firing `objectWillChange` per line — N+M+2 notifications in a single call. SwiftUI List's `UICollectionViewListCoordinator` saw an inconsistent diff between count-before and count-after and aborted.
- **Rule:** When a destructive action mutates multiple sub-collections of a `@Published` value-type model in one method, snapshot first, mutate the local copy, then assign back ONCE. Pattern: `var updated = routine; updated.roster.removeAll{...}; for i { updated.formations[i].placements.removeAll{...} }; routine = updated`. This produces a single `objectWillChange` event so the List coordinator gets one consistent diff. Also avoid calling `reconcileX()` helpers that re-assign `routine` — call non-`@Published` lookup-rebuild helpers (`rebuildFormationLookup`, `rebuildTransitionSpecLookup`, `rebuildRosterLookup`) directly after the single assignment.

## 2026-04-28 — Don't re-ask the user for info they already provided

- **Category:** correction
- **What happened:** User reported a crash; I asked them to reproduce while I captured a console log. After they corrected my console-capture setup, I asked them again to reproduce. They had already done it. Re-asking forced unnecessary repetition of work.
- **Rule:** When a user reports a bug, assume they already encountered it. Capture context first (logs, file state, recent changes) and only ask the user to reproduce as a last resort, *after* exhausting code-only diagnosis. If a tool setup misses the original repro window, apply the most-likely fix with explicit "if this doesn't fix it, please repro once with logging on" — don't pre-emptively block on another repro.

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

## 2026-04-28 — `simctl io screenshot` ignores simulator UI rotation

- **Category:** knowledge_gap
- **What happened:** Rotated iPad Pro 13" sim to landscape via `Device → Rotate Right`. Screenshot still came out 2064×2752 (portrait) — the same dimensions as before rotation. Same on iPhone 17 Pro Max: rotated via menu, simctl returned raw 1320×2868 portrait framebuffer with rotated content embedded. `simctl io <udid> screenshot` always returns the underlying display framebuffer in its native orientation, NOT what the user sees on screen. There is no `--orientation` or `--rotated` flag. Tried `osascript ... keystroke (ASCII 29) using command down` and direct menu clicks — both rotate the iOS UI but neither changes the screenshot output dimensions.
- **Rule:** For ASC landscape iPad screenshots (need 2752×2064): rotate the sim to landscape (any method), then `xcrun simctl io <udid> screenshot /tmp/raw.png; sips -r -90 /tmp/raw.png` to get the correct 2752×2064 result. iPhone Pro Max ASC shots are portrait-native (1320×2868) so no rotation post-process needed. If a screenshot looks "wrong-rotation" but content is correct, it's a framebuffer-orientation issue — fix with `sips -r -90` (negative degrees), not `sips -r 90` which produces upside-down landscape.

## 2026-04-29 — fastlane deliver "Too many screenshots" warnings during ASC 500 retries are non-fatal

- **Category:** knowledge_gap
- **What happened:** Replacing the iPad screenshot set via `fastlane deliver --force` (with `overwrite_screenshots: true`). First-pass uploads succeeded for some files, then ASC threw a wave of `Server error got 500` ("Waiting for screenshots to appear before uploading...") for ~20 minutes. On retry, fastlane logged `Too many screenshots found for device 'APP_IPAD_PRO_3GEN_129' in 'en-US', skipping this one (...)` for 3 files, plus `iPadPro13_02_shot.png is missing on App Store Connect`. Looked like a partial failure. Verifying via ASC API afterward showed all 10 iPad shots COMPLETE — the warnings were transient state during ASC's slow indexing.
- **Rule:** Don't trust fastlane's mid-run "Too many" / "missing on ASC" diagnostics during a retry storm — they reflect ASC's stale read view, not the final committed state. After deliver exits cleanly (`Successfully uploaded screenshots to App Store Connect`), verify the actual set with the ASC API (`/v1/appScreenshotSets/<id>/appScreenshots`) before re-running deliver. A re-run with `overwrite_screenshots: true` would wipe a correct set and risk hitting the 500 storm again.

## 2026-04-29 — Bash tool runs in zsh; arrays default to 1-indexed and break bash-style indexing

- **Category:** correction
- **What happened:** Wrote `SHOTS=(...)`; `for i in 0 1 2 3 4; do ... ${SHOTS[$i]} ...` expecting 0-indexed access. zsh (the default shell for the Bash tool on this machine) treats `${SHOTS[0]}` as empty (zsh arrays are 1-indexed by default; `KSH_ARRAYS` is not set). Result: empty filename in `cp`, copying wrong files, silently skipping the last shot.
- **Rule:** Wrap any array-indexed Bash logic in `/bin/bash -c '...'` to force a true bash subshell. Inside heredocs/inline commands that aren't explicitly bash, never use `${arr[$i]}` with a 0-based loop — either use 1-based indexing (`for i in 1 2 3 4 5`), or invoke bash explicitly. The `#!/bin/bash` shebang in a Bash-tool command body is a comment, not a shell switch.

## 2026-04-29 — Working ASC API JWT generation: use Ruby's OpenSSL::PKey::EC, not openssl(1) asn1parse

- **Category:** best_practice
- **What happened:** Tried generating an ES256 JWT for the App Store Connect API in pure bash using `openssl dgst -sha256 -sign | openssl asn1parse | awk | xxd`. The DER → r||s reconstruction was wrong (lost padding on integers with high bit set). Got `Cannot iterate over null` from jq on the API response — auth had silently failed.
- **Rule:** For one-shot ASC API queries, use Ruby (already installed via fastlane) with `OpenSSL::PKey::EC` + `Base64.urlsafe_encode64`. The signature reconstruction needs both r and s padded/truncated to exactly 32 bytes from the DER ASN1 INTEGER. Reference snippet saved in this conversation. Don't try to do this in pure bash.

## 2026-05-12 — xcrun simctl has a 15-20 min cold-start delay after CoreSimulator service restart

- **Category:** best_practice
- **What happened:** After `xcrun simctl shutdown all`, the CoreSimulatorService daemon effectively restarts. All subsequent `xcrun simctl list devices` calls appear to hang (60s+ timeout) but actually complete after 15-20 minutes. This caused misdiagnosis — appeared as a fatal error but was just slow startup.
- **Rule:** Don't use `xcrun simctl shutdown all` at the start of screenshot capture sessions; just boot the target device directly. If you do run shutdown all, don't immediately check `simctl list` — open `Simulator.app` first to kick the daemon and wait ~20 min before checking status. For diagnosing simctl hangs, check `ps aux | grep CoreSimulatorService` and look for a process started recently.

## 2026-05-12 — xcodebuild cannot target iOS Simulators when iOS SDK is not installed

- **Category:** knowledge_gap
- **What happened:** `xcodebuild -showdestinations` showed ZERO iOS Simulator destinations (not even as ineligible) even though `xcrun simctl list devices` confirmed iOS 26.4 simulators exist. Root cause: the iOS 26.5 platform SDK was not installed in Xcode. Both physical and simulator iOS targets require the SDK to be present in Xcode → Settings → Platforms.
- **Rule:** Before any screenshot capture session, run `xcodebuild -project <proj> -scheme <scheme> -showdestinations` and verify iOS Simulator entries appear. If absent: open Xcode → Settings → Platforms and download the current iOS platform. The fix also updates the CoreSimulator framework version.

## 2026-05-14 — App persistence is file-based, not UserDefaults

- **Category:** knowledge_gap
- **What happened:** CLAUDE.md says persistence is `UserDefaults` key `routine.v1`, but the app now saves to `Documents/workspace.v1.json` (RoutineStore uses `workspaceStorageKey = "workspace.v1"` with FileManager). Seeding via `defaults write` always failed; seeding via `cp demo_routine.json "$CONTAINER/Documents/workspace.v1.json"` works.
- **Rule:** For simulator seeding, use `cp .appstore/demo_routine.json "$(xcrun simctl get_app_container <UDID> com.ianrichardson.formationflow data)/Documents/workspace.v1.json"`. Do not attempt `xcrun simctl spawn defaults write` for this app.

## 2026-05-14 — Headless simulator rotation is not possible without assistive access

- **Category:** knowledge_gap
- **What happened:** `xcrun simctl` has no rotate command. Peekaboo hotkey `cmd+right` was accepted but had no effect (Simulator window didn't rotate). AppleScript `click menu item "Rotate Left"` failed due to missing assistive access.
- **Rule:** Landscape iPad screenshots require Simulator.app to have assistive access granted in System Settings > Privacy > Accessibility, OR manual rotation before the headless capture run. Without it, simctl captures are always portrait (2064×2752 for iPad Pro 13").

## 2026-05-18 — UIKit gesture recognizers can run alongside SwiftUI gestures via overlay UIViewRepresentable

- **Category:** best_practice
- **What happened:** Needed two-finger double-tap + UILongPressGestureRecognizer on the FloorGridView canvas, but the canvas already has a unified SwiftUI `DragGesture(minimumDistance: 0)` doing athlete drag / waypoint drag / pan / marquee. SwiftUI has no native multi-finger tap, and `LongPressGesture(...).sequenced(before: DragGesture(...))` doesn't compose cleanly with the existing unified gesture.
- **Rule:** Add a transparent `UIViewRepresentable` as an `.overlay(...)` whose UIView has `isUserInteractionEnabled = true` + `isMultipleTouchEnabled = true`. Attach `UITapGestureRecognizer` / `UILongPressGestureRecognizer` with `cancelsTouchesInView = false`, `delaysTouchesBegan = false`, `delaysTouchesEnded = false`. SwiftUI's gestures sit on an ancestor hosting view, so they continue to fire on the same touches. The overlay's recognizers fire independently for their patterns. Use a separate `@State` flag (e.g. `isLongPressSketching`) to gate the SwiftUI gesture's onChanged so it doesn't double-process while the UIKit recognizer is driving an interaction. Verify on device — if SwiftUI's recognizer is not on an ancestor of the overlay, this falls back to window-level recognizer install.

## 2026-05-18 — Correction: UIViewRepresentable overlay DOES block SwiftUI gestures behind it

- **Category:** correction
- **What happened:** Earlier learning today claimed a `UIViewRepresentable` overlay with `cancelsTouchesInView = false` recognizers could coexist with the SwiftUI DragGesture beneath. Tested on ianPad — total failure: athletes could not be selected/dragged, panning didn't work, all touches were absorbed by the overlay. SwiftUI gesture recognizers are NOT attached to the overlay's parent UIView — they live in a separate subview tree. When the overlay's UIView claims hits, recognizers in sibling SwiftUI trees never see the touches.
- **Rule:** Do NOT use an overlay UIViewRepresentable to add UIKit gesture recognizers to a SwiftUI Canvas/view that already has SwiftUI gestures. The overlay will swallow touches. Alternatives that actually work: (1) SwiftUI-native `LongPressGesture(...).sequenced(before: DragGesture(...))` attached as `.simultaneousGesture`, which composes natively. (2) UIWindow-level recognizers added on view-appear and filtered by location bounds — global, but they see all touches without claiming any. (3) Wrap the entire SwiftUI canvas inside a UIViewController-hosted parent that owns the recognizers. The advisor's suggestion to use overlay+cancelsTouchesInView was wrong for this case; supersedes the previous entry about it.
