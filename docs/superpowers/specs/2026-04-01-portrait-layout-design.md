# Portrait Layout: Static Toolbar + Formation Thumbnails

**Date:** 2026-04-01
**Status:** Approved
**Scope:** Portrait orientation only (iPad + iPhone). Landscape is unchanged.

## Problem

In portrait mode, the sidebar wastes horizontal space and duplicates controls that are already available on-screen (transport, playback). The court ends up smaller than it needs to be, and there's unused vertical space at the top and bottom. On iPhone portrait, the sidebar is already hidden but the top space is still underutilized.

## Design

Replace the sidebar with a two-tier top area in portrait orientation:

### Tier 1: Static Action Bar

A single-row, non-scrolling toolbar below the navigation bar. All items are icon-only except where noted. Items are laid out with left group + right-pinned share:

| Position | Icon | Label | Action |
|----------|------|-------|--------|
| Left 1 | `plus.circle.fill` | "+ Athlete" | Add athlete (short text label to distinguish from formation add) |
| Left 2 | `list.bullet.rectangle` | (none) | Open roster sheet |
| Left 3 | `note.text` | (none) | Open notes sheet |
| Left 4 | `arrow.uturn.backward` | (none) | Undo last move |
| Left 5 | `I` monospace glyph | (none) | Toggle transition paths. Highlighted background when active. |
| Right | `square.and.arrow.up` | (none) | Share preview (standard iOS share position) |

**Conditional items** that appear when relevant:
- Collision warning badge (red capsule with count) — appears left of "+ Athlete" when collisions exist
- Path collision badge (orange capsule with count) — appears after collision badge when path crossings exist
- Inspector button (`slider.horizontal.3`) — appears when in compact layout, contextual to selection state

The action bar does NOT scroll. If device width is too narrow for all items, the overflow goes into a `...` menu (ellipsis) on the right before the share button — but this should not happen with the icon-only approach at standard iPad/iPhone widths.

### Tier 2: Formation Thumbnail Strip

A horizontally scrollable strip of formation thumbnails below the action bar:

- **Thumbnail:** Mini court rectangle (~52x40pt on iPad, scaled for iPhone) showing colored dots at actual athlete positions, rendered from `RenderedAthlete` data
- **Selected formation:** Accent-colored border (formation rainbow tint). Others have dim border.
- **Label:** Formation name below each thumbnail (truncated if long)
- **Arrows:** `→` between consecutive formations to show transition flow
- **Add button:** Dashed-border `+` rectangle at the end to add a new formation
- **Interaction:** Tap thumbnail to switch to that formation. Long-press for context menu (rename, duplicate, delete, move).

This strip scrolls horizontally because it's data (formations vary from 1 to 20+), not toolbar actions. The scroll is for content, not controls.

### Court Area

- Court gets full viewport width (minus small horizontal padding)
- Court is vertically centered in the remaining space between the thumbnail strip and bottom transport
- No sidebar steals width — court renders larger in portrait than current layout
- Existing zoom/pan gestures continue to work

### Bottom Transport

Existing `CompactTransitionPlaybackOverlayView` stays at the bottom. No changes to transport controls.

## Orientation Logic

This layout activates when **all** of these are true:
- Portrait orientation (verticalSizeClass != .compact, or more precisely: not landscape)
- Could apply to both iPad and iPhone

When the device rotates to landscape:
- iPad: reverts to current `NavigationSplitView` sidebar layout
- iPhone: uses existing `CompactTransitionPlaybackRailView` (left rail)

The detection mechanism should use `@Environment(\.verticalSizeClass)` and `@Environment(\.horizontalSizeClass)` rather than device idiom checks alone, so it works correctly with Split View / Slide Over on iPad.

## Formation Thumbnail Rendering

Each thumbnail is a miniature version of the court. Implementation approach:

- Use a small SwiftUI `Canvas` (or pre-rendered image) per formation
- Map athlete positions from floor-feet coordinates to thumbnail pixel coordinates: `x * thumbnailWidth / CourtConstants.width`, `y * thumbnailHeight / CourtConstants.height`
- Color dots by role (same colors as main canvas: blue=base, yellow=flyer, green=spotter, purple=backspot, orange=tumbler)
- No grid lines in thumbnails — just dots on dark background
- Dot size: ~3-4pt radius, scaled to thumbnail

## What Moves Out of the Sidebar

For portrait mode, every sidebar function must have a portrait-mode home:

| Sidebar Item | Portrait Location |
|--------------|-------------------|
| Formation list | Thumbnail strip (Tier 2) |
| Formation reorder | Long-press context menu on thumbnails |
| Transport controls | Bottom overlay (existing) |
| Add athlete | Action bar `+ Athlete` button |
| Roster management | Action bar roster icon → sheet |
| Notes | Action bar notes icon → sheet |
| Undo | Action bar undo icon |
| Path toggle | Action bar `I` toggle |
| Share preview | Action bar share icon (right-pinned) |
| Inspector | Action bar inspector button → sheet (compact layout) |
| Speed picker | Bottom transport (existing) |

## Files to Modify

- **`FormationHomeView.swift`** — Add portrait detection; when portrait, skip `NavigationSplitView` sidebar and use the new vertical layout (action bar + thumbnails + floor + transport)
- **New: `PortraitActionBar.swift`** — Static action bar view
- **New: `FormationThumbnailStrip.swift`** — Horizontal scrolling thumbnail strip with mini-canvas renderers
- **New: `FormationThumbnailView.swift`** — Individual thumbnail (mini Canvas rendering athlete dots)
- **`FloorGridView.swift`** — May need adjustments to control strip visibility when portrait layout is active (hide the existing `controlStrip` in portrait since the action bar replaces it)

## What This Does NOT Change

- Landscape layout on any device
- `FloorCanvasView` rendering logic
- `Models.swift` (no data model changes)
- Transport/playback controls
- Drag/drop behavior on the court
- Any persistence or data flow
