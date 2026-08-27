# FormationFlow — App Store Submission Checklist

Two lanes: **Checklist A** is work only Ian can do (ASC web UI, Mac + distribution cert, human judgement). **Checklist B** is work that can be handed to agents or scripted.

Details for pasting into ASC live in `docs/APP_STORE_SUBMISSION_PACKET.md`. Copy source for all metadata lives in `docs/APP_STORE_METADATA.md`.

---

## Status at last update

- Info.plist has `LSApplicationCategoryType = public.app-category.sports` ✅
- Subtitle shortened to 28 chars ✅
- IAP product ID confirmed as `com.formationflow.prounlock` (code + StoreKit agree) ✅
- Metadata character counts pass ASC limits ✅
- iPhone screenshots verified at native 1320×2868 ✅
- Repo root is artifact-free ✅
- Current build metadata: v1.0.9 (297)

Outstanding:
- Live URL check (blocked in sandbox — Ian to eyeball in browser)
- `.appstore/demo_routine.json` not yet generated
- Native iPad preview videos not yet captured
- Fastlane `AuthKey.json` not yet placed
- Nothing has been uploaded to ASC yet

---

## Checklist A — Ian (manual, cannot be delegated)

### A1. Verify live URLs (browser)
- [ ] `https://iankainoa42.github.io/formation-flow/`
- [ ] `https://iankainoa42.github.io/formation-flow/support.html`
- [ ] `https://iankainoa42.github.io/formation-flow/privacy-policy.html`
- [ ] Privacy policy states "no data collected", no third-party analytics, mentions device-only storage, has a contact email + effective date.

### A2. App Store Connect — App Record Setup
- [ ] Create app record (or open existing) — bundle `com.ianrichardson.formationflow`, primary language English (U.S.), SKU any unique string.
- [ ] App Information tab: name, subtitle, categories, content rights, age rating (see Packet §1).

### A3. Version 1.0 page (paste from Packet §2)
- [ ] Promotional text
- [ ] Description
- [ ] Keywords
- [ ] Support / Privacy / Marketing URLs
- [ ] What's New
- [ ] Copyright
- [ ] Review notes (Packet §5)

### A4. In-App Purchase — CREATE then attach (Packet §3)
- [ ] Create non-consumable `com.formationflow.prounlock` @ $4.99
- [ ] Upload IAP review screenshot (`ProUpgradeSheet`)
- [ ] Attach IAP to the v1.0 version (required for first submission)

### A5. Build Upload (Ian's Mac only)
- [ ] Archive with `xcodebuild ... archive`
- [ ] Manual IPA re-sign flow from `CLAUDE.md` (openrsync breaks `-exportArchive`)
- [ ] `xcrun altool --upload-app ... --apiKey 8APDGY74BZ --apiIssuer 7642a25e-...`
- [ ] Wait for processing; select build 297 on the version page

### A6. Compliance form (ASC)
- [ ] Privacy Nutrition Label → Data Not Collected
- [ ] Export Compliance → exempt (already declared in Info.plist)
- [ ] IDFA → No
- [ ] Third-party content rights → No

### A7. Media (Packet §8)
- [ ] Upload iPad 13" screenshots (10 files from `AppStoreScreenshots/ipad13/`)
- [ ] Upload iPad 12.9" screenshots (10 files from `AppStoreScreenshots/ipad129/`)
- [ ] Upload iPhone 6.9" screenshots (5 files from `appstore-assets/`)
- [ ] Skip app previews unless Checklist B3 produced native-dim MOVs

### A8. Final submit
- [ ] Pricing & availability → Free, all territories
- [ ] Version release → Automatic
- [ ] "Add for Review" → "Submit for Review"
- [ ] Monitor ASC status / email 24–72h

---

## Checklist B — Agent-delegatable

### B1. Metadata & config hygiene
- [x] Add `LSApplicationCategoryType` to `FormationFlow/Info.plist` (done)
- [x] Confirm subtitle ≤ 30 chars (was 31; now 28)
- [x] Character-count audit of all metadata fields (all pass)
- [ ] WebFetch the 3 GitHub Pages URLs when running from an environment that isn't egress-blocked — flag any 404s or copy that contradicts the "no data collected" claim

### B2. Submission packet generator
- [x] Produce `docs/APP_STORE_SUBMISSION_PACKET.md` — done, extracted verbatim from metadata

### B3. Screenshot / preview capture (needs Ian's Mac + Xcode + simulator)
- [ ] Generate `.appstore/demo_routine.json` from a hand-built 3-formation × 8-athlete routine via `xcrun simctl spawn booted defaults read com.ianrichardson.formationflow routine.v1` → JSON dump → commit
- [ ] Run `.appstore/capture.md` flow to produce native iPad 13" (2752×2064) and iPad 12.9" (2732×2048) preview MOVs
- [ ] Verify dimensions with `sips` / `ffprobe`; log failures in `NOTES.md`
- [ ] Output to `AppStoreScreenshots/auto/<YYYY-MM-DD>/` (not committed)

### B4. Fastlane readiness (docs-only until AuthKey is placed)
- [ ] Update `fastlane/README.md` with required env vars (`APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`) and where `AuthKey.json` lives (gitignored)
- [ ] Confirm `fastlane/Fastfile` remains `ENV[...]`-only (per CLAUDE.md Known Fixed Security Issues)

### B5. Pre-submit smoke checks (read-only)
- [x] Confirm product ID matches between `EntitlementManager.swift` and `FormationFlow.storekit` (both `com.formationflow.prounlock`)
- [x] Confirm no `*.orig`/`*.patch`/`*.diff`/root `*.sh`/`*.py`/`plan.md` artifacts
- [ ] Run `xcodebuild ... build` against a simulator destination and confirm exit 0 before archive

---

## Hard constraints (every agent must respect)

- `Models.swift` is locked. Do not touch.
- `FloorGridView.swift`, `FormationHomeView.swift`, `RoutinePlaybackView.swift`, `AthleteDetailPanel.swift` are high-churn — no polish/refactor passes without a concrete user-visible regression.
- Never modify `FormationFlow.xcodeproj/project.pbxproj` manually. Adding new files (e.g., a real `LaunchScreen.storyboard`) is Ian's job in Xcode.
- Never commit `AuthKey.json`, `*.p8`, or any API secret.
- Delete artifacts (`*.orig`, `*.patch`, `*.diff`, root `*.sh`/`*.py`, `plan.md`, `.Jules/*`, `.jules/*`) before staging.
