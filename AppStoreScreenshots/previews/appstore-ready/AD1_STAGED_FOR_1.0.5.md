# Staged App Preview — AD1 (for 1.0.5)

**File:** `AD1_886x1920_30fps.mov` (this folder)
**Source:** `formation-flow/AD1.mp4` (23.976 fps → re-encoded to 30 fps)
**Specs:** 886×1920 · 30 fps · 29.87 s · H.264 high / yuv420p · AAC · 8 MB
**Status:** STAGED — not yet uploaded to App Store Connect.

## What to do when preparing 1.0.5
1.0.5 is a metadata + bug-fix update. App previews are version-scoped media — the
live 1.0.4 set is locked, so this attaches to the **new 1.0.5 version**.

- Attach to the **iPhone preview set** (App Store Connect → 1.0.5 → en-US).
  886×1920 is an Apple-accepted App Preview resolution for the 6.5" / 6.7" / 6.9"
  iPhone display family — one file covers the iPhone slot. It does **not** fit iPad
  (those are landscape ~4:3); leave iPad previews as-is.
- Upload via the ASC API (this repo manages media out-of-band; fastlane lanes
  `skip_screenshots: true`). Reserve an `appPreview` in the iPhone `appPreviewSet`
  of the 1.0.5 `appStoreVersionLocalization`, chunked-upload, then commit.

## Content / rejection-risk note
AD1 is real in-app screen recordings edited into a **split-screen collage/montage**.
All footage is from the app, so it's preview-eligible in principle, but Apple
sometimes flags montage/collage-style previews as not "representative of the app in
use." Because it's bundled with bug fixes, a preview rejection could hold up the
whole 1.0.5 release. If review flags the preview, remove it from the version and
resubmit the bug fixes alone (or resolve in Resolution Center) so fixes aren't blocked.
