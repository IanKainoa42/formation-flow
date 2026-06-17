#!/usr/bin/env python3
"""General full-bleed caption overlay for FormationFlow App Store beats.
Usage: python3 scripts/add_caption.py <beat>
"""
import os, sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CAP = os.path.join(ROOT, "AppStoreScreenshots/captures/ipad")
OUTD = os.path.join(ROOT, "AppStoreScreenshots/marketing-v2/ipad")
os.makedirs(OUTD, exist_ok=True)

WHITE=(255,255,255); CORAL=(255,71,87); GREEN=(81,207,102); CYAN=(0,212,255); GOLD=(255,212,59)
NAVY=(8,12,24); DIM=(255,255,255,205)
HEAD="/Library/Fonts/InterTight-Black.ttf"; SEMI="/Library/Fonts/Inter-SemiBold.ttf"; REG="/Library/Fonts/Inter-Regular.ttf"
def f(p,s): return ImageFont.truetype(p,s)

CONFIGS = {
  "practice": dict(
    base="paths_fill.png", out="ipad_02_practice.png", accent=CORAL,
    tag="WHO ARE WE KIDDING?",
    headline=[("You'll never have a ",WHITE),("full team",CORAL),(" at practice.",WHITE)],
    sub="So solve every transition before practice even starts.",
  ),
  "collisions": dict(
    base="collisions_fill.png", out="ipad_03_collisions.png", accent=CORAL,
    tag="COLLISION DETECTION",
    headline=[("We ",WHITE),("crash-test",CORAL),(" your transitions.",WHITE)],
    sub="Run the move on-screen and every pile-up lights up — long before your team does.",
  ),
  "cta": dict(
    base="cta_fill.png", out="ipad_04_cta.png", accent=CYAN,
    tag="FREE · NO ACCOUNT",
    headline=[("Coach like ",WHITE),("a pro.",CYAN)],
    sub="Free. No account. No subscription. Just better choreography.",
  ),
}

def render(beat):
    c = CONFIGS[beat]
    im = Image.open(os.path.join(CAP, c["base"])).convert("RGBA")
    W,H = im.size; d = ImageDraw.Draw(im); cx=W/2

    scrim = Image.new("RGBA",(W,H),(0,0,0,0)); sd=ImageDraw.Draw(scrim)
    band=int(H*0.34)
    for y in range(band):
        a=int(240*(1-y/band)**1.25); sd.line([(0,y),(W,y)],fill=NAVY+(a,))
    im.alpha_composite(scrim)

    tf=f(SEMI,34); tw=d.textlength(c["tag"],font=tf); pw,ph=int(tw+64),80
    x0=int(cx-pw/2); ty=66; ov=Image.new("RGBA",(W,H),(0,0,0,0)); od=ImageDraw.Draw(ov)
    od.rounded_rectangle([x0,ty,x0+pw,ty+ph],radius=ph//2,fill=c["accent"]+(38,),outline=c["accent"]+(120,),width=3)
    od.text((cx,ty+ph/2+1),c["tag"],font=tf,fill=c["accent"]+(255,),anchor="mm")
    im.alpha_composite(ov)

    segs=c["headline"]; size=140; maxw=W-260
    while size>78:
        hf=f(HEAD,size)
        if sum(d.textlength(s,font=hf) for s,_ in segs)<=maxw: break
        size-=4
    hf=f(HEAD,size); y=ty+ph+44
    total=sum(d.textlength(s,font=hf) for s,_ in segs); x=cx-total/2
    for s,col in segs:
        d.text((x,y),s,font=hf,fill=col,anchor="la"); x+=d.textlength(s,font=hf)
    y+=int(size*1.04)
    if c.get("sub"):
        sf=f(SEMI,int(size*0.42))
        d.text((cx,y),c["sub"],font=sf,fill=WHITE,anchor="ma")

    out=os.path.join(OUTD,c["out"]); im.convert("RGB").save(out)
    print("wrote",out,im.size,"headline pt",size)

if __name__=="__main__":
    render(sys.argv[1] if len(sys.argv)>1 else "practice")
