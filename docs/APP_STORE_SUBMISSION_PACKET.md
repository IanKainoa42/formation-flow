# FormationFlow — App Store Connect Submission Packet

Everything Ian needs to paste into App Store Connect, in the order the ASC UI presents it. Extracted verbatim from `docs/APP_STORE_METADATA.md` — do not re-word here; edit the metadata doc if copy needs to change.

Build target: **v1.0.9 (297)** — matches current `CFBundleShortVersionString` / `CFBundleVersion` in `FormationFlow/Info.plist`.

---

## 1. App Information (one-time; edit before submitting first version)

| Field | Value |
|---|---|
| Bundle ID | `com.ianrichardson.formationflow` |
| SKU | `formationflow-ios-001` (any unique string) |
| Primary language | English (U.S.) |
| Name | `FormationFlow` |
| Subtitle | `Formation transition planner` |
| Primary category | Sports |
| Secondary category | Productivity |
| Content Rights | "Contains, or accesses, third-party content" → **No** |
| Age Rating | 4+ (no objectionable content in any category) |

---

## 2. Version 1.0 Page — Copy-paste blocks

### Promotional Text (170 chars)
```
Plan your team's formation transitions visually — place athletes on a court grid, set paths, preview animations. No full team needed.
```

### Description (4000 chars)
```
Plan formation transitions without your full team on the mat.

FormationFlow is a visual choreography tool built for cheer coaches, dance directors, and performance teams. Place athletes on a court grid, arrange multiple formations, and preview smooth animated transitions — all from your iPad or iPhone.

PLAN FORMATIONS VISUALLY
Drop athletes onto a scaled court grid. Drag to reposition. See your formations take shape in seconds, not hours.

ANIMATE TRANSITIONS
Preview how athletes move between formations with real-time playback. Adjust timing, add waypoints for curved paths, and set move delays for staggered entries.

ROLE-BASED ATHLETES
Assign roles — Base, Flyer, Spotter, Backspot, Tumbler, or Stunt Group — each with distinct color-coded markers so you can read your formation at a glance.

CUSTOM TRANSITION PATHS
Go beyond straight-line movement. Add waypoints to create curved paths, set hold durations at waypoints, and control smooth vs. sharp turns for each athlete.

BUILD FULL ROUTINES
Create multiple formations within a single routine. Reorder formations, duplicate them, and preview the entire sequence.

FREE TO START
Create up to 2 formations with Base athletes — no purchase required. Upgrade to FormationFlow Pro to unlock unlimited formations, all athlete roles, and full routine playback.

WORKS OFFLINE
No account required. No internet needed. Your data stays on your device — always private, always available.

DESIGNED FOR COACHES
FormationFlow was built by a cheer coach who needed a faster way to plan transitions between practice sessions. Every feature exists because it solved a real coaching problem.

Perfect for:
- Cheerleading teams planning competition routines
- Dance teams choreographing performances
- Marching bands arranging field shows
- Any performance group that moves in formation
```

### Keywords (100 chars)
```
cheer,formation,choreography,dance,transition,routine,coach,planning,stunt,team
```

### What's New in This Version (first release)
```
Initial release — plan formation transitions visually. Place athletes, add waypoints, animate transitions between formations. Free to start; unlock unlimited formations with FormationFlow Pro.
```

### Support URL
```
https://iankainoa42.github.io/formation-flow/support.html
```

### Privacy Policy URL
```
https://iankainoa42.github.io/formation-flow/privacy-policy.html
```

### Marketing URL (optional)
```
https://iankainoa42.github.io/formation-flow/
```

### Copyright
```
© 2026 Ian Richardson
```

---

## 3. In-App Purchase — Create then attach to v1.0 submission

ASC → Features → In-App Purchases → "+"

| Field | Value |
|---|---|
| Type | Non-Consumable |
| Reference Name | `FormationFlow Pro` |
| Product ID | `com.formationflow.prounlock` |
| Price | Tier 5 — $4.99 USD |
| Family Sharing | Enabled |

**Localization (English U.S.)**
- Display Name: `FormationFlow Pro`
- Description: `Unlimited formations, roles, timing controls, and waypoints`

**Review Screenshot**
- Upload one screenshot of `ProUpgradeSheet` showing the upgrade CTA. Recommend using an iPad 12.9" or 13" screenshot from `AppStoreScreenshots/ipad13/` if one shows the upgrade sheet; otherwise capture a fresh one.

**Attach to app version**
- On the v1.0 version page → "In-App Purchases" section → add `FormationFlow Pro` so it submits with the app (first submission MUST include the IAP for review).

---

## 4. Privacy Nutrition Label

Answer to "Do you or your third-party partners collect data from this app?" → **No**

This maps to "Data Not Collected" on the public listing. Matches the app's actual behavior: all state lives in `UserDefaults` on-device, no network calls except App Transport Security allowlist (empty).

---

## 5. App Review Information

| Field | Value |
|---|---|
| Sign-in required? | No |
| Demo account | None |
| Contact info | Ian Richardson · iankainoa42@gmail.com |
| Notes to reviewer | See block below |

### Notes to Reviewer
```
FormationFlow is a coaching tool for planning cheerleading formations. No login or account. All data lives on-device.

To exercise the paid features during review, use StoreKit test purchase flow — the IAP "com.formationflow.prounlock" ($4.99, non-consumable) unlocks unlimited formations, all athlete roles, and full-routine playback.

Free-tier limits: 2 formations, Base role only. Pro unlocks all other roles (Flyer, Spotter, Backspot, Tumbler, Stunt Group) and unlimited formations.

The app is designed for iPad (landscape-primary) but runs universally.
```

---

## 6. Export Compliance

| Field | Value |
|---|---|
| Does your app use encryption? | Yes (HTTPS only via Apple system frameworks) |
| Exempt from export documentation? | Yes — falls under Category 5 Part 2 Note 4 (uses only standard OS crypto) |

Already declared in `Info.plist` via `ITSAppUsesNonExemptEncryption = false`.

---

## 7. Build

Select the uploaded build (v1.0.9, build 297) after `xcrun altool` processing completes.

Upload command (from `CLAUDE.md`, run on Ian's Mac):
```
xcrun altool --upload-app --type ios --file /tmp/FormationFlow.ipa \
  --apiKey 8APDGY74BZ --apiIssuer 7642a25e-aca7-402d-8b7d-de18dfef1756
```

---

## 8. Media

Upload from the repo:

| Device | Count | Source |
|---|---|---|
| iPad Pro 13" (2752×2064) | 10 | `AppStoreScreenshots/ipad13/*.png` |
| iPad Pro 12.9" (2732×2048) | 10 | `AppStoreScreenshots/ipad129/*.png` |
| iPhone 6.9" (1320×2868) | 5 | `appstore-assets/iphone_screenshot_*.png` |
| App Previews | skip | Existing `preview_*_886x1920_*.mov` are iPhone-portrait squashed to iPad — do NOT upload. Re-capture natively per `.appstore/capture.md` if desired. |

---

## 9. Pricing & Availability

- Price tier: Free
- Availability: All territories
- Pre-order: No

---

## 10. Version Release

Recommend **"Automatically release this version"** — no marketing coordination required for v1.0.

---

## 11. Final Submit

- Click "Add for Review" then "Submit for Review".
- Monitor status in ASC and email over 24–72h.
