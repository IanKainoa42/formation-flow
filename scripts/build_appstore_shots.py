#!/usr/bin/env python3
"""Render captioned App Store screenshots for FormationFlow.

Executes the AppStoreStoryboard.md design handoff into real PNGs:
navy gradient + faint court grid + tag pill + headline (accent word) +
sub-headline + feature pills + a device mockup of a clean app capture.

Sources: clean vector frames exported from FormationFlowui.pen
(AppStoreScreenshots/design-exports/) and real device captures (IMG_*.png).
"""
import sys, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_IPHONE = os.path.join(ROOT, "AppStoreScreenshots/marketing-v2/iphone")
OUT_IPAD   = os.path.join(ROOT, "AppStoreScreenshots/marketing-v2/ipad")
os.makedirs(OUT_IPHONE, exist_ok=True)
os.makedirs(OUT_IPAD, exist_ok=True)

# ---- palette ---------------------------------------------------------------
NAVY      = (10, 15, 30)
DEEP      = (6, 9, 15)
NAVY_LITE = (22, 32, 58)
CORAL     = (255, 71, 87)
ELECTRIC  = (0, 212, 255)
GOLD      = (255, 212, 59)
GREEN     = (81, 207, 102)
WHITE     = (255, 255, 255)
DIM       = (255, 255, 255, 184)

F = "/Library/Fonts/"
HEAD = F + "InterTight-Black.ttf"
SEMI = F + "Inter-SemiBold.ttf"
MED  = F + "Inter-Medium.ttf"
REG  = F + "Inter-Regular.ttf"

def font(path, size):
    return ImageFont.truetype(path, size)

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def radial_bg(w, h, cx=0.5, cy=0.30):
    stops = [(0.0, NAVY_LITE), (0.55, NAVY), (1.0, DEEP)]
    sw, sh = max(8, w // 8), max(8, h // 8)
    img = Image.new("RGB", (sw, sh))
    px = img.load()
    ccx, ccy = cx * sw, cy * sh
    maxd = max((((0 if cx < .5 else sw) - ccx) ** 2 + ((0 if cy < .5 else sh) - ccy) ** 2) ** .5,
               (((sw - ccx) ** 2 + (sh - ccy) ** 2) ** .5),
               ((ccx ** 2 + ccy ** 2) ** .5))
    for y in range(sh):
        for x in range(sw):
            d = (((x - ccx) ** 2 + (y - ccy) ** 2) ** .5) / maxd
            d = min(1.0, d)
            for i in range(len(stops) - 1):
                p0, c0 = stops[i]; p1, c1 = stops[i + 1]
                if d <= p1:
                    t = (d - p0) / (p1 - p0) if p1 > p0 else 0
                    px[x, y] = lerp(c0, c1, t); break
            else:
                px[x, y] = stops[-1][1]
    return img.resize((w, h), Image.BICUBIC).convert("RGBA")

def add_grid(img, cols=9, rows=17, alpha=13):
    w, h = img.size
    ov = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    for i in range(1, cols):
        x = round(i * w / cols); d.line([(x, 0), (x, h)], fill=(255, 255, 255, alpha), width=1)
    for j in range(1, rows):
        y = round(j * h / rows); d.line([(0, y), (w, y)], fill=(255, 255, 255, alpha), width=1)
    return Image.alpha_composite(img, ov)

def cover(im, bw, bh):
    iw, ih = im.size
    s = max(bw / iw, bh / ih)
    nim = im.resize((max(1, round(iw * s)), max(1, round(ih * s))), Image.LANCZOS)
    nx, ny = nim.size
    l = (nx - bw) // 2; t = (ny - bh) // 2
    return nim.crop((l, t, l + bw, t + bh))

def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return m

def place_device(base, src_path, box, accent, radius):
    """box=(x,y,w,h). Adds glow, shadow, rounded screenshot, border."""
    x, y, w, h = box
    src = Image.open(src_path).convert("RGB")
    shot = cover(src, w, h)
    mask = rounded_mask((w, h), radius)

    # glow behind device
    glow = Image.new("RGBA", base.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gx, gy = x + w // 2, y + h // 2
    gr = int(w * 0.72)
    gd.ellipse([gx - gr, gy - gr, gx + gr, gy + gr], fill=accent + (60,))
    glow = glow.filter(ImageFilter.GaussianBlur(int(w * 0.18)))
    base.alpha_composite(glow)

    # drop shadow
    sh = Image.new("RGBA", base.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(sh)
    off = int(h * 0.018)
    sd.rounded_rectangle([x, y + off, x + w, y + h + off], radius=radius, fill=(0, 0, 0, 165))
    sh = sh.filter(ImageFilter.GaussianBlur(int(w * 0.06)))
    base.alpha_composite(sh)

    # screenshot
    base.paste(shot, (x, y), mask)
    # border
    bd = ImageDraw.Draw(base)
    bd.rounded_rectangle([x, y, x + w - 1, y + h - 1], radius=radius,
                         outline=(60, 78, 110, 255), width=3)

def text_w(d, s, fnt):
    return d.textlength(s, font=fnt)

def draw_centered_segments(d, cx, y, segments, fnt):
    total = sum(text_w(d, s, fnt) for s, _ in segments)
    x = cx - total / 2
    for s, col in segments:
        d.text((x, y), s, font=fnt, fill=col, anchor="la")
        x += text_w(d, s, fnt)

def line_height(fnt):
    a, dsc = fnt.getmetrics()
    return a + dsc

def overlay(base):
    ov = Image.new("RGBA", base.size, (0, 0, 0, 0))
    return ov, ImageDraw.Draw(ov)

def tag_pill(base, cx, y, label, accent, fs):
    fnt = font(SEMI, fs)
    md = ImageDraw.Draw(base)
    tw = text_w(md, label, fnt); th = line_height(fnt)
    px, py = int(fs * 0.95), int(fs * 0.5)
    pw, ph = int(tw + 2 * px), int(th + 2 * py)
    x0 = int(cx - pw / 2); r = ph // 2
    ov, d = overlay(base)
    d.rounded_rectangle([x0, y, x0 + pw, y + ph], radius=r, fill=accent + (38,),
                        outline=accent + (120,), width=3)
    d.text((cx, y + ph / 2 + 1), label, font=fnt, fill=accent + (255,), anchor="mm")
    base.alpha_composite(ov)
    return ph

def pills_row(base, cx, y, items, fs):
    fnt = font(MED, fs)
    md = ImageDraw.Draw(base)
    px, py, gap = int(fs * 0.85), int(fs * 0.48), int(fs * 0.6)
    dims = [(int(text_w(md, it, fnt) + 2 * px), int(line_height(fnt) + 2 * py)) for it in items]
    total = sum(w for w, _ in dims) + gap * (len(items) - 1)
    x = cx - total / 2; ph = dims[0][1]
    ov, d = overlay(base)
    for it, (pw, _) in zip(items, dims):
        r = ph // 2
        d.rounded_rectangle([x, y, x + pw, y + ph], radius=r,
                            fill=(255, 255, 255, 20), outline=(255, 255, 255, 46), width=2)
        d.text((x + pw / 2, y + ph / 2 + 1), it, font=fnt, fill=WHITE + (255,), anchor="mm")
        x += pw + gap
    base.alpha_composite(ov)
    return ph

def wrap(d, text, fnt, maxw):
    words = text.split(); lines = []; cur = ""
    for w in words:
        t = (cur + " " + w).strip()
        if text_w(d, t, fnt) <= maxw:
            cur = t
        else:
            if cur: lines.append(cur)
            cur = w
    if cur: lines.append(cur)
    return lines

def render(cfg, portrait):
    if portrait:
        W, H = 1320, 2868
        pad_top, side = 150, 110
        head_fs, sub_fs, tag_fs, pill_fs = 116, 44, 30, 32
        aspect = 1320 / 2868; dev_r = 92; dev_w_cap = 760
        cyf = 0.30
    else:
        W, H = 2752, 2064
        pad_top, side = 100, 150
        head_fs, sub_fs, tag_fs, pill_fs = 104, 48, 32, 38
        aspect = 2752 / 2064; dev_r = 40; dev_w_cap = 2300
        cyf = 0.32

    base = radial_bg(W, H, 0.5, cyf)
    base = add_grid(base)
    d = ImageDraw.Draw(base)
    cx = W / 2
    y = pad_top

    accent = cfg["accent"]
    ph = tag_pill(base, cx, y, cfg["tag"], accent, tag_fs)
    y += ph + int(head_fs * 0.55)

    hfnt = font(HEAD, head_fs)
    lh = int(head_fs * 1.04)
    for line in cfg["headline"]:
        draw_centered_segments(d, cx, y, line, hfnt)
        y += lh
    y += int(head_fs * 0.18)

    sfnt = font(REG, sub_fs)
    sub_maxw = 1040 if portrait else 1680
    for ln in wrap(d, cfg["sub"], sfnt, sub_maxw):
        d.text((cx, y), ln, font=sfnt, fill=DIM, anchor="ma")
        y += int(sub_fs * 1.34)
    y += int(sub_fs * 0.5)

    if cfg.get("pills"):
        ph2 = pills_row(base, cx, y, cfg["pills"], pill_fs)
        y += ph2 + int(pill_fs * 1.2)

    text_bottom = y
    maxbottom = H - (96 if portrait else 70)
    gap_min = int(head_fs * 0.40)
    avail_top = text_bottom + gap_min
    avail_h = maxbottom - avail_top
    avail_w = W - 2 * side
    # fit device into available box preserving aspect (w/h)
    dev_h = min(avail_h, avail_w / aspect)
    dev_w = dev_h * aspect
    if dev_w > dev_w_cap:
        dev_w = dev_w_cap; dev_h = dev_w / aspect
    dev_w, dev_h = int(dev_w), int(dev_h)
    dev_x = int(cx - dev_w / 2)
    dev_y = int(avail_top + max(0, (avail_h - dev_h) / 2))
    place_device(base, cfg["img"], (dev_x, dev_y, dev_w, dev_h), accent, dev_r)

    return base.convert("RGB")

# ---- screenshot definitions ------------------------------------------------
DE = os.path.join(ROOT, "AppStoreScreenshots/design-exports")
def img(name): return os.path.join(ROOT, name)
def de(name):  return os.path.join(DE, name)

IPHONE = [
    dict(tag="CHEER CHOREOGRAPHY PLANNING", accent=CORAL,
         headline=[[("Stop Running", WHITE)], [("Ugly ", CORAL), ("Transitions.", WHITE)]],
         sub="Plan every path. Preview every move. Coach with confidence.",
         img=de("gocPg.png")),
    dict(tag="FORMATION EDITOR", accent=ELECTRIC,
         headline=[[("Set Every Spot,", WHITE)], [("Perfectly.", ELECTRIC)]],
         sub="Drag and drop your whole team on a to-scale 72×56 ft court.",
         pills=["Role Colors", "72×56 ft Court", "Drag & Drop"],
         img=img("IMG_0207-1.png")),
    dict(tag="TRANSITION PATHS", accent=CORAL,
         headline=[[("Draw the Path,", WHITE)], [("Not the ", WHITE), ("Chaos.", CORAL)]],
         sub="Bezier curves, waypoints, and hold timing — every move intentional.",
         pills=["Bezier Curves", "Waypoints", "Hold Timing"],
         img=img("IMG_0209.png")),
    dict(tag="COLLISION DETECTION", accent=GOLD,
         headline=[[("Catch Every", WHITE)], [("Collision.", GOLD)]],
         sub="The court flags athletes who cross paths — before practice, not during.",
         pills=["Live Detection", "Auto Warnings"],
         img=img("IMG_0208.png")),
    dict(tag="FREE · NO ACCOUNT", accent=ELECTRIC,
         headline=[[("Coach Like", WHITE)], [("a ", WHITE), ("Pro.", ELECTRIC)]],
         sub="Free. No account. No subscription. Just better choreography.",
         img=de("gocPg.png")),
]

IPAD = [
    dict(tag="CHEER CHOREOGRAPHY PLANNING", accent=CORAL,
         headline=[[("Stop Running ", WHITE), ("Ugly ", CORAL), ("Transitions.", WHITE)]],
         sub="Plan your whole routine on iPad — every formation, every path, every count.",
         img=img("AppStoreScreenshots/captures/ipad/01_hero_pyramid.png")),
    dict(tag="FORMATION EDITOR", accent=ELECTRIC,
         headline=[[("Set Every Spot, ", WHITE), ("Perfectly.", ELECTRIC)]],
         sub="Role-shaped athletes on a to-scale court, with a full inspector at your side.",
         pills=["Role Shapes", "Live Inspector", "Shared Roster"],
         img=img("IMG_0210.png")),
    dict(tag="TRANSITION PATHS", accent=CORAL,
         headline=[[("Draw the Path, ", WHITE), ("Not the ", WHITE), ("Chaos.", CORAL)]],
         sub="Curved paths and waypoints for every athlete, timed to the 8-count.",
         pills=["Bezier Curves", "Waypoints", "8-Count Timing"],
         img=img("IMG_0214.png")),
    dict(tag="ANIMATED PLAYBACK", accent=GOLD,
         headline=[[("See It Move ", WHITE), ("Before They Do.", GOLD)]],
         sub="Smooth 60fps playback with speed control — rehearse the routine at home.",
         pills=["60fps Playback", "Speed Control", "Scrub Timeline"],
         img=img("IMG_0207.png")),
    dict(tag="ONE ROSTER, EVERY FORMATION", accent=ELECTRIC,
         headline=[[("Manage Your ", WHITE), ("Whole Team.", ELECTRIC)]],
         sub="Define each athlete once — their spot updates across every formation.",
         pills=["Shared Roster", "Per-Athlete Roles", "Swap & Edit"],
         img=img("IMG_0211.png")),
]

def main():
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    jobs = []
    if which in ("all", "iphone", "proof"):
        idxs = [0, 1] if which == "proof" else range(len(IPHONE))
        for i in idxs:
            jobs.append((IPHONE[i], True, os.path.join(OUT_IPHONE, f"iphone_{i+1:02d}.png")))
    if which.startswith("ipad"):
        parts = which.split()
        if len(parts) > 1 and parts[1].isdigit():
            i = int(parts[1]) - 1
            jobs.append((IPAD[i], False, os.path.join(OUT_IPAD, f"ipad_{i+1:02d}.png")))
        else:
            for i in range(len(IPAD)):
                jobs.append((IPAD[i], False, os.path.join(OUT_IPAD, f"ipad_{i+1:02d}.png")))
    elif which.startswith("iphone") and len(which.split()) > 1 and which.split()[1].isdigit():
        i = int(which.split()[1]) - 1
        jobs.append((IPHONE[i], True, os.path.join(OUT_IPHONE, f"iphone_{i+1:02d}.png")))
    elif which == "all":
        for i in range(len(IPAD)):
            jobs.append((IPAD[i], False, os.path.join(OUT_IPAD, f"ipad_{i+1:02d}.png")))
    for cfg, portrait, out in jobs:
        im = render(cfg, portrait)
        im.save(out)
        print(f"wrote {out}  {im.size[0]}x{im.size[1]}")

if __name__ == "__main__":
    main()
