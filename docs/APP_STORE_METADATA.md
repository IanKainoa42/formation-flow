# FormationFlow — App Store Metadata

Copy-paste ready for App Store Connect.

---

## App Name (30 chars max)
```
FormationFlow
```

## Subtitle (30 chars max)
```
Cheer Formation Planner
```
> Was "Formation/Transition Simulator" on the live listing. "Simulator" is jargon nobody searches; "cheer" is the word every buyer types and it appeared nowhere in the title or subtitle. 23 chars.

## Promotional Text (170 chars, can update without new build)
```
Built by a coach at a 5x World Champion gym. Plan formations and transitions on iPhone, iPad or Mac, then export a printable playbook for your team.
```
> Seasonal swap (update in App Store Connect without a build):
> - **May–Sep (choreography season):** the line above.
> - **Oct–Apr (comp season):** `Fix the transition that keeps colliding at 3 a.m. before Worlds. Plan it, animate it, hand your athletes a printed playbook.`

## Description (4000 chars max)

```
Plan formation transitions without your full team on the mat.

FormationFlow is a visual choreography tool built for cheer coaches, dance directors, and performance teams. Place athletes on a court grid, arrange multiple formations, and preview smooth animated transitions — all from your iPad or iPhone.

EXPORT A PRINTABLE PLAYBOOK (PRO)
Turn the routine into a PDF your athletes can hold: one page per formation, transition paths drawn in, cover page with the team name. Print it, AirDrop it, pin it on the gym wall.

WORKS ON IPHONE, IPAD AND MAC
Plan at your desk on the Mac in the off-season, pull it up on your phone at practice. Same app, one purchase.

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
Create up to 2 formations with Base athletes — no purchase required. FormationFlow Pro is a one-time purchase (no subscription) that unlocks unlimited formations, all athlete roles, full routine playback and PDF playbook export.

WORKS OFFLINE
No account required. No internet needed. Your data stays on your device — always private, always available.

DESIGNED FOR COACHES
FormationFlow was built by a coach at CheerForce San Diego, a 5x World Champion program, who needed a faster way to plan transitions between practice sessions. Every feature exists because it solved a real coaching problem on a real mat.

Perfect for:
- Cheerleading teams planning competition routines
- Dance teams choreographing performances
- Marching bands arranging field shows
- Any performance group that moves in formation
```

## Keywords (100 chars max, comma-separated)
```
cheerleading,cheer,formation,choreography,dance,transition,routine,coach,allstar,stunt,playbook,mat
```
> 99 chars. Added "cheerleading" (App Store treats it as a distinct token from "cheer"), "allstar", "playbook" and "mat"; dropped "planning" and "team" (both are in the subtitle/description already, and "team" is too generic to rank for).

## Categories
- **Primary:** Sports
- **Secondary:** Productivity

## Age Rating
- No objectionable content in any category
- Rating: **4+**

## Copyright
```
© 2026 Ian Richardson
```

## Support URL
```
https://iankainoa42.github.io/formation-flow/support.html
```

## Privacy Policy URL
```
https://iankainoa42.github.io/formation-flow/privacy-policy.html
```

## Marketing URL (optional)
```
https://iankainoa42.github.io/formation-flow/
```

---

## App Store Connect — Privacy Nutrition Label

**Data Not Collected** — select this option.

FormationFlow does not collect any data from users. All data is stored locally on the device.

When prompted: "Do you or your third-party partners collect data from this app?"
→ Select **No**

---

## Pricing
- **Free** with in-app purchase
- **FormationFlow Pro** — $4.99 (one-time, non-consumable)
  - Product ID: `com.formationflow.prounlock` (matches `EntitlementManager.productID` and `FormationFlow.storekit`)
  - Reference name: `FormationFlow Pro`
  - Display name: `FormationFlow Pro`
  - Description: `Unlimited formations, roles, timing controls, and waypoints`
  - Unlocks unlimited formations, all athlete roles, and full routine playback
  - Family shareable: Yes
  - Restore Purchases button in `ProUpgradeSheet`

## Availability
- All territories


---

## Screenshot order (iPhone first)
Sales data (Jun–Aug 2026): 65% of new downloads are iPhone, 25% iPad, 10% Mac. Lead the iPhone set; the iPad set can reuse it.
1. Animated transition mid-playback with a collision marker visible (the "aha")
2. Exported PDF playbook page (the thing Pro users actually pay for)
3. Formation editor with role colours + roster
4. Waypoint / curved path editing
5. "Works offline. No account. One-time purchase." text card

## Pricing note
FormationFlow Pro converted 11% of downloads to paid Jun–Aug 2026 at $4.99 (RevenueCat 2026 freemium median ≈ 2%). Buyers are intent-driven, not price-shopping. Raise to $9.99 (Tier 10), then test $14.99 for May–Sep 2027. Update the `price` string in `CoachingApp.others` in the other apps if they cross-promote FormationFlow.
