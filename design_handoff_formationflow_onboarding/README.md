# Handoff: FormationFlow Onboarding (first-launch intro)

## Overview
A six-screen first-launch onboarding flow for **FormationFlow** (the cheer/dance choreography planner). It introduces the core value prop and the key features — place athletes, animate transitions, bend paths with waypoints, stagger with move-delay, build multi-formation routines, work offline, go Pro — in a **dark "courtside" aesthetic** with a **dry, deadpan cheer-coach voice**.

The flow is presented as a **floating marketing card layered over a live, dimmed app surface** (the iPadOS first-launch convention). Each screen shows a real-looking FormationFlow editor state behind the copy, with callouts pointing at the UI element being described.

Two device layouts are included:
- **iPad landscape** (1066×800 reference) — the hero treatment.
- **iPhone portrait** (393×852 reference) — court up top, copy as a bottom sheet.

## About the Design Files
The files in this bundle are **design references created in HTML/React-in-Babel** — prototypes showing intended look and behavior, **not production code to ship directly**. FormationFlow is a native **SwiftUI iOS/iPadOS** app (Swift 5.9+, iOS 17+, SwiftUI `Canvas` rendering, zero dependencies, `UserDefaults` persistence). The task is to **recreate these designs in SwiftUI** using the app's existing patterns:
- Reuse `FloorCanvasView` / the `Canvas`-based floor renderer for the court grid + athlete dots + paths behind each card.
- Role colors already exist in `Models.swift` (`AthleteRole.color`).
- Build the onboarding as a `.fullScreenCover` or paged `TabView(.page)` over a static/looping demo `Routine`, shown on first launch (gate with a `UserDefaults` bool, e.g. `hasSeenOnboarding`).
- The "live app surface" behind each card can be a real (non-interactive) `FloorCanvasView` driven by a bundled demo routine, dimmed with an overlay.

Do **not** add new dependencies, and respect the repo's `Models.swift` / `FloorGridView.swift` freeze rules (see `CLAUDE.md`) — the onboarding should be **new view files**, not edits to those locked files.

## Fidelity
**High-fidelity.** Final colors, typography, spacing, copy, and layout are specified below. Recreate pixel-faithfully using SwiftUI, substituting SF Pro / SF Mono (already the system fonts) and the existing role-color tokens. The athlete positions shown are demo placeholders — use any sensible demo formation.

---

## Design Tokens

### Surface / chrome (dark)
| Token | Value | Use |
|---|---|---|
| `bg` | `#0A0C0F` | App background behind the floor |
| `floor` | `#0E1217` | Court fill |
| `floorEdge` | `rgba(255,255,255,0.08)` | Court border |
| `gridMinor` | `rgba(255,255,255,0.040)` | 1-ft grid lines |
| `gridMajor` | `rgba(255,255,255,0.105)` | 8-ft panel lines |
| `bar` | `rgba(14,17,22,0.72)` + blur(12) | Top bar / strip / transport background |
| `barBd` | `rgba(255,255,255,0.09)` | Hairline borders |
| `tile` | `rgba(255,255,255,0.05)` | Icon button fill |
| `card` | `rgba(16,19,24,0.82)` + blur(30) | Floating intro card |
| `txt` | `#F5F5F7` | Primary text |
| `txtDim` | `rgba(235,235,245,0.60)` | Body / secondary |
| `txtFaint` | `rgba(235,235,245,0.30)` | Tertiary |

### Accent (tweakable; app default is system blue)
`#0A84FF` (blue, default) · alternates: `#30D158` green · `#BF5AF2` purple · `#FF9F0A` orange · `#FF375F` pink. The accent drives the UI tint **and** the intro card eyebrow/italic/CTA. (The current saved preview uses pink `#FF375F`.)

### Athlete role colors (from `Models.swift` → `AthleteRole.color`, dark/vivid iOS values)
| Role | Label | Hex |
|---|---|---|
| base | A# | `#0A84FF` (blue) |
| flyer | A# | `#FFD60A` (yellow — use dark text `#1c1500` on the dot) |
| spotter | A# | `#30D158` (green) |
| backspot | A# | `#BF5AF2` (purple) |
| tumbler | A# | `#FF9F0A` (orange) |
| stuntGroup | A# | `#FF375F` (pink) |

Formation accent (thumbnail rings / per-formation tint) uses a rainbow cycle: `#FF375F, #FF9F0A, #FFD60A, #30D158, #0A84FF, #BF5AF2` indexed by formation order — matches `TransitionEndpointMarkerRenderItem.rainbowColor(forIndex:)`.

### Typography
- **Sans:** SF Pro Display / system. Card title **34px / weight 800 / line-height 1.05 / letter-spacing −0.9** (iPad); **25px / 800** (iPhone sheet). Body **14.5px / line-height 22px** (iPad), **13.5/20** (iPhone). One clause per title is set in **italic + accent color** for emphasis.
- **Mono:** SF Mono / `ui-monospace`. Used for eyebrows, labels, counts, CTA text, athlete labels. Eyebrow **10px / 600 / letter-spacing 1.8 / uppercase / accent**. Athlete dot label **~13px / 700** on iPad (`max(cell*1.15, 8.5)`).

### Geometry
- Court is **72 ft × 56 ft**, drawn as **9 × 7 panels of 8 ft** (`CourtConstants`). Grid: thin line every 1 ft (`gridMinor`), heavier every 8 ft (`gridMajor`).
- Athlete dot radius = **2.0 ft × cellSize** (min 11px). `cellSize` = courtWidthPx / 72.
- Intro card: width **432px** (iPad, 470 when wide), radius **26**, padding **32**, shadow `0 30px 80px rgba(0,0,0,0.6)`.
- CTA button: height **42–46**, radius **12–13**, accent fill, white text, glow `0 8px 22px accent55`, trailing arrow.
- Page dots: 6 dots, active dot is a **22×6 pill** in accent, others **6×6** at `rgba(255,255,255,0.18)`.

### Radii / shadows
Cards 26 · tiles/chips 9–12 · floor 10 · CTA 12 · pills 20. Floating elements use a backdrop blur + 1px hairline border.

---

## Screens / Views

> Copy comes in **two deadpan voices (A / B)**. The delivered default is a **curated per-screen mix**: **01-A · 02-B · 03-A · 04-A · 05-B · 06-A**. Both full voices are listed so the team can pick. (#03 voice is a tentative A — confirm with owner.)

Every screen shares the same chrome unless noted:
- **Top bar** (52px iPad / 46px iPhone): `‹ Saved Formations` (accent) · undo glyph · **formation name** (bold) · centered FORMATIONFLOW wordmark (iPad) · trailing "next arrow" circle + "•••" circle (both accent-outlined).
- **Floating intro card** centered/left/right with eyebrow → title → body → page dots → optional CTA.
- **Dim scrim** over the floor so the card stays readable (linear top→bottom; radial for the final screen).
- **Callout** = dashed accent connector from card to a UI element, with a small mono label chip.

### 01 · Welcome
- **Purpose:** Set the premise — plan the whole routine here, not on the mat.
- **Surface:** "Opening V" formation (10 athletes) on the floor; bottom **thumbnail strip** (Opening V · Lines · Pyramid + dashed "Add" tile).
- **Card:** right-aligned. Eyebrow `WELCOME · 01 / 06`. CTA **"Get started"**.
- **Voice A title:** "Your full team shows up *the day before* competition."
  body: "Cool. Plan the entire routine here instead — place every athlete, map every transition, press play. The mat is for cleaning it up, not figuring it out."
- **Voice B title:** "Practice is Thursday. *Half the team* will be there."
  body: "Plan the routine now, while it's quiet. Place every athlete, map every transition, and walk into practice already knowing the answer."

### 02 · Roster
- **Purpose:** Place athletes; role-based colors.
- **Surface:** Opening V with the **flyer (A1) selected** (dashed accent ring). Left **action row**: `+` (active), roster-list, notes icon buttons. Callout → flyer labeled `FLYER · A1`.
- **Card:** left-aligned. Eyebrow `ROSTER · 02 / 06`. *(Per owner: the role legend block was removed — copy only.)*
- **Voice A title:** "Move athletes around without anyone *bumping into each other.*"
  body: "Drop your roster onto a true-to-scale floor and drag them where they go. Color-coded by role so you can read the formation at a glance. This generation collides enough in real life."
- **Voice B title (delivered default):** "Assign roles. Avoid *reunions mid-mat.*"
  body: "Build your roster once and drop athletes onto a scaled floor. Each role gets its own color, so you're never squinting at sixteen identical dots wondering which one is the flyer."
- *(Optional legend if reinstated: 6 swatches — Base/Flyer/Spotter/Backspot/Tumbler/Stunt Grp — with a "PRO unlocks all" tag; free tier = base only.)*

### 03 · Transitions (animate · Flow vs Steps)
- **Purpose:** Animate the move between two formations.
- **Surface:** Two formations — **V (dimmed, start)** and **Lines (bright, end)** — with a **curved dashed path per athlete** (role-colored, "flow" dash). Title bar reads `V → Lines`. Bottom **transport bar**: `[Flow|Steps]` segmented toggle (Flow active), prev/play(active)/next, current count `3.4`, scrubber (~42%), `8 ct`, speed `1.0×`, loop (active). "8-COUNT" mono label.
- **Card:** left-aligned. Eyebrow `TRANSITIONS · 03 / 06`.
- **Voice A title (delivered default):** "Press play. Watch the chaos *resolve itself.*"
  body: "Animate the move between any two formations in real time. Flow mode pulses the paths; Steps mode counts out the footwork. Either way you see it before they walk it."
- **Voice B title:** "See the transition *before they trip through it.*"
  body: "Hit play and the whole move animates in real time. Flow mode for the paths, Steps mode for the counts — pick whichever way you actually coach it."

### 04 · Paths (waypoints + move delay)
- **Purpose:** Bend paths with waypoints; stagger with move delay; collision flagging.
- **Surface:** V (dim) → Lines, with **two highlighted paths** that bend through a **waypoint handle** (small ring dot); one labeled `·2 ct`. Left action row: red **collision badge** `⚠ 1 · path` + paths-eye toggle (active). Transport in **Steps** mode.
- **Card:** right-aligned. Eyebrow `PATHS · 04 / 06`. Contains a **MOVE DELAY** control: label + value `·2 ct`, a slider (~28%), and pills `[Smooth]` (on) `[Sharp]` `[+ Waypoint]` (accent).
- **Voice A title (delivered default):** "Two athletes, one spot, *zero collisions.*"
  body: "Bend any path with waypoints — smooth or sharp — and stagger entrances with a move delay measured in 8-counts. The app flags crossings before they become a pile-up."
- **Voice B title:** "Curved paths for athletes who *can't walk straight.*"
  body: "Add waypoints to route around traffic — smooth or sharp — and offset each entrance by a few counts. Crossings get flagged before someone's eating floor."

### 05 · Routine (multi-formation + multi-select)
- **Purpose:** Chain formations into a routine; multi-select a stunt group.
- **Surface:** Lines formation with **4 athletes selected** (dashed accent rings). Left pill: `4 selected · stunt group` (accent). Bottom **thumbnail strip** with a 4th formation "Closer", second item selected.
- **Card:** right-aligned. Eyebrow `ROUTINE · 05 / 06`.
- **Voice A title:** "String it all together. Then move *twelve of them at once.*"
  body: "Chain formations into a full routine and scrub the whole thing end to end. Multi-select a stunt group to slide everyone together — re-placing sixteen athletes one at a time is a punishment, not a workflow."
- **Voice B title (delivered default):** "One routine. Every formation. *Scrubbable.*"
  body: "Link formations into a sequence and preview the whole thing front to back. Grab a stunt group and move all four at once — your thumbs will thank you."

### 06 · Ready / Pro (offline + paywall + outro)
- **Purpose:** Offline/private reassurance + Pro upsell + final CTA.
- **Surface:** Opening V, **strong radial scrim**. Thumbnail strip.
- **Card:** centered, **wide (470px)**. Eyebrow `READY · 06 / 06`. Contains a **Pro list** card (`FORMATIONFLOW PRO` / **$4.99 once**) with checkmark rows: *Unlimited formations* (Free caps at 2) · *Every athlete role* (Free is base only) · *Full-routine playback* (Scrub end to end) · *Waypoints & timing* (Bend + stagger paths). CTA full-width: **"now let your imagination be."**
- **Voice A title (delivered default):** "No team, no signal, *no excuses.*"
  body: "Everything lives on your device — works on the mat with zero bars, stays private, no account. Go Pro for unlimited formations, every role, and full-routine playback. Four hours a week. Don't spend them on a transition you could've solved at home."
- **Voice B title:** "Courtside-proof. *Wi-Fi optional.*"
  body: "It's all on-device: no account, no signal, fully private. Pro unlocks unlimited formations, all roles, and full-routine playback. Mat time is precious — stop spending it on math you could do on the couch."

### iPhone portrait variants
Same six screens, same copy. Layout: status bar + dynamic island, compact top bar (`‹ Saved` · title · •••), the **court near the top** (full width, naturally short → authentic empty floor below, like the real portrait app), and the **intro card as a bottom sheet** (rounded top, grab handle, eyebrow/title/body/optional inset control/dots, **full-width CTA**). Transitions/Paths show a floating transport / collision pill below the court. The Pro list appears inside the screen-06 sheet.

---

## Interactions & Behavior
- **Paging:** swipe or tap CTA advances screen; page dots reflect index (0-based internally, labeled 01–06). "Skip" affordance optional. Back chevron on bar is decorative in onboarding.
- **CTA:** `Get started` (01) and `now let your imagination be.` (06) dismiss onboarding into the editor; intermediate screens have no CTA (advance via dot/swipe).
- **Demo surface:** the floor behind each card is a non-interactive `FloorCanvasView` driven by a bundled demo `Routine`. Screen 03 may animate the V→Lines transition on a loop (reuse `TransitionPlayer` at speed 1.0×, 8-count) to sell "press play". Respect `prefers-reduced-motion` — show end state, no infinite loops.
- **Entrance animation:** card content can fade/slide in on becoming active; base style = visible end-state so PDF/reduced-motion/first-paint show content.
- **Accent tweak:** in the prototype, accent is user-switchable and re-tints UI + card. In-app this maps to the app's `accentColor`.
- **Voice:** prototype exposes Mix / A / B; in-app, ship the curated mix as static copy (no toggle) unless the team wants A/B testing.

## State Management
- `hasSeenOnboarding: Bool` in `UserDefaults` — gates first-launch presentation.
- `currentPage: Int` (0…5) for the pager.
- A bundled demo `Routine` (roster of 10, two formations "Opening V" + "Lines", one transition with a couple of waypoints + a move delay) used purely for the background surface. Do not persist it into the user's real `routine.v1`.
- No data fetching; fully offline (consistent with the app).

## Assets
No external images. All glyphs are simple inline SVGs (chevrons, undo/redo, play/pause, loop, plus, list, note, eye, flame/wordmark, collision triangle, arrowheads) — recreate with **SF Symbols** in SwiftUI (`chevron.left`, `arrow.uturn.backward`, `play.fill`, `pause.fill`, `repeat`, `plus`, `list.bullet.rectangle`, `note.text`, `eye`/`eye.slash`, `exclamationmark.triangle.fill`, `arrow.right`, `ellipsis`). The wordmark "FORMATIONFLOW" is mono text with a small accent rounded-square logo containing a stylized "flow" stroke.

## Files
In this bundle:
- `FormationFlow Intro.html` — entry point; wires the design canvas + tweaks panel and lays out both device sections.
- `formationflow-intro.jsx` — **all the design**: theme tokens, copy (both voices + per-screen mix `SCREEN_VOICE`), formations, floor/athlete/path primitives, chrome (top bar, thumbnail strip, transport, action row, collision badge), intro card + CTA + callout, and all 12 screen components (`Screen01–06`, `PScreen01–06`).
- `design-canvas.jsx` — pan/zoom canvas harness used only to present the screens side-by-side (not part of the product).
- `tweaks-panel.jsx` — the in-prototype tweak controls (not part of the product).

To read the exact pixel values, colors, and copy, open `formationflow-intro.jsx` — it is the source of truth. Search `const COPY`, `useFF()`, `SCREEN_VOICE`, and each `ScreenNN` / `PScreenNN` function.

## Screenshots
Rendered reference captures of the **delivered curated mix** (pink accent) are in `screenshots/`:

| iPad (landscape) | iPhone (portrait) | Screen |
|---|---|---|
| `01-ipad.png` | `01-iphone.png` | 01 Welcome (voice A) |
| `02-ipad.png` | `02-iphone.png` | 02 Roster (voice B, no legend) |
| `03-ipad.png` | `03-iphone.png` | 03 Transitions (voice A) |
| `04-ipad.png` | `04-iphone.png` | 04 Paths (voice A) |
| `05-ipad.png` | `05-iphone.png` | 05 Routine (voice B) |
| `06-ipad.png` | `06-iphone.png` | 06 Ready / Pro (voice A) |

These show the intended final look — match colors, type, spacing, and layout to these. To preview the alternate voices or accent colors, open `FormationFlow Intro.html` and use the Tweaks panel (Voice: Mix / A / B; Accent swatches).
