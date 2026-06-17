#!/usr/bin/env python3
"""Split-screen hero for FormationFlow App Store (iPad 2752x2064).

Left half = BAD transition (tangled, crossing, colliding straight paths).
Right half = GOOD transition (clean curved bezier paths).
Same formation pair (Balanced Block -> Symmetrical Wedge V) from Ian's real
'Showcase' routine. Full-bleed floor, app-accurate court + pink circle athletes,
headline overlaid on a top scrim.
"""
import json, os, math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, ".appstore/showcase_old.json")
OUT = os.path.join(ROOT, "AppStoreScreenshots/marketing-v2/ipad/ipad_01.png")
W, H = 2752, 2064
CW, CH = 72.0, 56.0

# app-accurate colors
COURT_BG = (33, 33, 33)
GRID     = (58, 58, 62)
PINK     = (240, 53, 90)
PINK_HI  = (255, 150, 170)
CORAL    = (255, 71, 87)
CYAN     = (0, 212, 255)
NAVY     = (10, 15, 30)
WHITE    = (255, 255, 255)
DIM      = (255, 255, 255, 190)

HEAD = "/Library/Fonts/InterTight-Black.ttf"
SEMI = "/Library/Fonts/Inter-SemiBold.ttf"
REG  = "/Library/Fonts/Inter-Regular.ttf"
MONO = "/System/Library/Fonts/SFNSMono.ttf"
def font(p, s):
    try: return ImageFont.truetype(p, s)
    except: return ImageFont.truetype(REG, s)

# ---- court mapping (cover the frame) ---------------------------------------
S = W / CW                      # px per foot, fill width
OY = (H - CH * S) / 2           # vertical offset (slightly negative)
def cx(fx): return fx * S
def cy(fy): return fy * S + OY

# ---- load formations -------------------------------------------------------
w = json.load(open(SRC))
r = w["routines"][0]
forms = {f["name"]: f for f in r["formations"]}
A = forms["Balanced Block"]["placements"]
B = forms["Symmetrical Wedge (V)"]["placements"]
def pts(pl): return [(p["positionX"], p["positionY"]) for p in pl]
Apos, Bpos = pts(A), pts(B)
N = min(len(Apos), len(Bpos))
Apos, Bpos = Apos[:N], Bpos[:N]

# ---- court layer -----------------------------------------------------------
def court_base():
    im = Image.new("RGB", (W, H), COURT_BG)
    d = ImageDraw.Draw(im)
    # subtle vignette
    for fx in range(0, int(CW) + 1, 8):
        x = cx(fx); d.line([(x, 0), (x, H)], fill=GRID, width=2)
    for fy in range(0, int(CH) + 1, 8):
        y = cy(fy); d.line([(0, y), (W, y)], fill=GRID, width=2)
    return im.convert("RGBA")

def quad(a, c, b, steps=40):
    out = []
    for i in range(steps + 1):
        t = i / steps
        mt = 1 - t
        x = mt*mt*a[0] + 2*mt*t*c[0] + t*t*b[0]
        y = mt*mt*a[1] + 2*mt*t*c[1] + t*t*b[1]
        out.append((x, y))
    return out

def control(a, b):
    mx, my = (a[0]+b[0])/2, (a[1]+b[1])/2
    dx, dy = b[0]-a[0], b[1]-a[1]
    L = math.hypot(dx, dy) or 1
    nx, ny = -dy/L, dx/L
    side = 1 if mx >= CW/2 else -1
    if nx*side < 0: nx, ny = -nx, -ny
    off = min(12, 5 + L*0.22)
    return (mx+nx*off, my+ny*off)

def stroke_glow(d, poly, color, w_core, w_glow, a_core=255, a_glow=70):
    d.line(poly, fill=color+(a_glow,), width=w_glow, joint="curve")
    d.line(poly, fill=color+(a_core,), width=w_core, joint="curve")

def seg_intersect(p1, p2, p3, p4):
    def ccw(A,B,C): return (C[1]-A[1])*(B[0]-A[0]) > (B[1]-A[1])*(C[0]-A[0])
    if (ccw(p1,p3,p4) != ccw(p2,p3,p4)) and (ccw(p1,p2,p3) != ccw(p1,p2,p4)):
        d1=(p2[0]-p1[0],p2[1]-p1[1]); d2=(p4[0]-p3[0],p4[1]-p3[1])
        den=d1[0]*d2[1]-d1[1]*d2[0]
        if abs(den)<1e-6: return None
        t=((p3[0]-p1[0])*d2[1]-(p3[1]-p1[1])*d2[0])/den
        return (p1[0]+t*d1[0], p1[1]+t*d1[1])
    return None

def draw_paths(layer, style):
    d = ImageDraw.Draw(layer)
    if style == "good":
        for a, b in zip(Apos, Bpos):
            poly = [(cx(x), cy(y)) for x, y in quad(a, control(a, b), b)]
            stroke_glow(d, poly, CYAN, 8, 26)
    else:
        # bad: cross-map destinations (reverse) -> heavy crossings
        dest = list(reversed(Bpos))
        segs = []
        for a, b in zip(Apos, dest):
            p0 = (cx(a[0]), cy(a[1])); p1 = (cx(b[0]), cy(b[1]))
            stroke_glow(d, [p0, p1], CORAL, 7, 22)
            segs.append((p0, p1))
        # collision bursts at intersections
        hits = []
        for i in range(len(segs)):
            for j in range(i+1, len(segs)):
                p = seg_intersect(segs[i][0], segs[i][1], segs[j][0], segs[j][1])
                if p: hits.append(p)
        # thin to avoid over-clutter
        for p in hits[::3]:
            burst(d, p, 26, CORAL)

def burst(d, c, rad, color):
    x, y = c
    for k in range(8):
        ang = k * math.pi / 4
        d.line([(x, y), (x + math.cos(ang)*rad, y + math.sin(ang)*rad)],
               fill=color+(230,), width=5)
    d.ellipse([x-7, y-7, x+7, y+7], fill=(255, 255, 255, 235))

def draw_athletes(layer, ghost_first=True):
    d = ImageDraw.Draw(layer)
    rad = int(1.15 * S)
    # end ghosts (V)
    for x, y in Bpos:
        px, py = cx(x), cy(y)
        d.ellipse([px-rad, py-rad, px+rad, py+rad], outline=(255,255,255,60), width=3)
    # start solid (Block)
    lf = font(REG, int(rad*0.7))
    for i, (x, y) in enumerate(Apos):
        px, py = cx(x), cy(y)
        d.ellipse([px-rad, py-rad, px+rad, py+rad], fill=PINK+(255,),
                  outline=(255,255,255,140), width=3)
        d.ellipse([px-rad*0.55-rad*0.15, py-rad*0.55-rad*0.15,
                   px-rad*0.15+rad*0.2, py-rad*0.15+rad*0.2], fill=PINK_HI+(120,))

def render_floor(style):
    base = court_base()
    paths = Image.new("RGBA", (W, H), (0,0,0,0))
    draw_paths(paths, style)
    base.alpha_composite(paths)
    ath = Image.new("RGBA", (W, H), (0,0,0,0))
    draw_athletes(ath)
    base.alpha_composite(ath)
    return base

bad = render_floor("bad")
good = render_floor("good")

# splice: left=bad, right=good
hero = Image.new("RGBA", (W, H))
half = W // 2
hero.paste(bad.crop((0, 0, half, H)), (0, 0))
hero.paste(good.crop((half, 0, W, H)), (half, 0))

# divider glow
dv = Image.new("RGBA", (W, H), (0,0,0,0))
dd = ImageDraw.Draw(dv)
dd.line([(half, 0), (half, H)], fill=(255,255,255,60), width=10)
dv = dv.filter(ImageFilter.GaussianBlur(8))
dd2 = ImageDraw.Draw(dv)
dd2.line([(half, 0), (half, H)], fill=(255,255,255,210), width=4)
hero.alpha_composite(dv)

# top scrim for headline legibility
scrim = Image.new("RGBA", (W, H), (0,0,0,0))
sd = ImageDraw.Draw(scrim)
band = int(H*0.34)
for yy in range(band):
    a = int(235 * (1 - yy/band)**1.3)
    sd.line([(0, yy), (W, yy)], fill=NAVY+(a,))
# bottom subtle scrim for labels
for yy in range(int(H*0.86), H):
    a = int(150 * ((yy-H*0.86)/(H*0.14)))
    sd.line([(0, yy), (W, yy)], fill=NAVY+(a,))
hero.alpha_composite(scrim)

d = ImageDraw.Draw(hero)
# tag pill
tag = "CHEER CHOREOGRAPHY PLANNING"
tf = font(SEMI, 34)
tw = d.textlength(tag, font=tf)
pw, ph = int(tw+60), 76
x0 = int(W/2 - pw/2); ty = 70
ov = Image.new("RGBA",(W,H),(0,0,0,0)); od=ImageDraw.Draw(ov)
od.rounded_rectangle([x0,ty,x0+pw,ty+ph],radius=ph//2,fill=CORAL+(40,),outline=CORAL+(130,),width=3)
od.text((W/2,ty+ph/2+1),tag,font=tf,fill=CORAL+(255,),anchor="mm")
hero.alpha_composite(ov)

# headline
hf = font(HEAD, 132)
y = ty + ph + 48
def seg_line(segs, yy):
    total = sum(d.textlength(s, font=hf) for s,_ in segs)
    x = W/2 - total/2
    for s,c in segs:
        d.text((x, yy), s, font=hf, fill=c, anchor="la"); x += d.textlength(s, font=hf)
seg_line([("Stop Running ", WHITE), ("Ugly ", CORAL), ("Transitions.", WHITE)], y)
y += int(132*1.05)
sf = font(REG, 46)
d.text((W/2, y), "The same formation. One tangled, one fixed.", font=sf, fill=DIM, anchor="ma")

# BEFORE / AFTER labels
def chip(cxp, label, color):
    f = font(HEAD, 60)
    tw = d.textlength(label, font=f)
    bw, bh = int(tw+70), 100; x = int(cxp-bw/2); yy = H-190
    o = Image.new("RGBA",(W,H),(0,0,0,0)); od=ImageDraw.Draw(o)
    od.rounded_rectangle([x,yy,x+bw,yy+bh],radius=bh//2,fill=color+(45,),outline=color+(150,),width=4)
    od.text((cxp,yy+bh/2+2),label,font=f,fill=color+(255,),anchor="mm")
    hero.alpha_composite(o)
chip(W*0.25, "BEFORE", CORAL)
chip(W*0.75, "AFTER", CYAN)

hero.convert("RGB").save(OUT)
print("wrote", OUT, hero.size, "| athletes", N)
