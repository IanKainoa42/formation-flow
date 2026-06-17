#!/usr/bin/env python3
"""Derive iPhone 6.9" (1320x2868) portrait marketing shots from the landscape iPad floors.
Navy card layout: stacked headline on top, the landscape floor as a framed card below.
Usage: python3 scripts/add_caption_iphone.py <beat>
"""
import os, sys, math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CAP = os.path.join(ROOT, "AppStoreScreenshots/captures/ipad")
OUTD = os.path.join(ROOT, "AppStoreScreenshots/marketing-v2/iphone")
os.makedirs(OUTD, exist_ok=True)

W, H = 1320, 2868
NAVY=(10,15,30); DEEP=(6,9,15); NLITE=(22,32,58)
WHITE=(255,255,255); CORAL=(255,71,87); GREEN=(81,207,102); CYAN=(0,212,255)
DIM=(255,255,255,200)
HEAD="/Library/Fonts/InterTight-Black.ttf"; SEMI="/Library/Fonts/Inter-SemiBold.ttf"; REG="/Library/Fonts/Inter-Regular.ttf"
def f(p,s): return ImageFont.truetype(p,s)
def lerp(a,b,t): return tuple(int(a[i]+(b[i]-a[i])*t) for i in range(3))

CONFIGS={
 "hero": dict(floor="split_pyramid_fill.png", out="iphone_01_hero.png", accent=CORAL,
   tag="CHEER CHOREOGRAPHY PLANNING",
   lines=[[("Your transitions",WHITE)],[("are ",WHITE),("ugly.",CORAL)]],
   sub="And everybody is talking about it.",
   chips=[("BEFORE",CORAL),("AFTER",GREEN)]),
 "practice": dict(floor="paths_fill.png", out="iphone_02_practice.png", accent=CORAL,
   tag="WHO ARE WE KIDDING?",
   lines=[[("You'll never have a",WHITE)],[("full team",CORAL),(" at practice.",WHITE)]],
   sub="So solve every transition before practice even starts."),
 "collisions": dict(floor="collisions_fill.png", out="iphone_03_collisions.png", accent=CORAL,
   tag="COLLISION DETECTION",
   lines=[[("We ",WHITE),("crash-test",CORAL)],[("your transitions.",WHITE)]],
   sub="Run the move on-screen and every pile-up lights up before your team does."),
 "cta": dict(floor="cta_fill.png", out="iphone_04_cta.png", accent=CYAN,
   tag="FREE · NO ACCOUNT",
   lines=[[("Coach like",WHITE)],[("a ",WHITE),("pro.",CYAN)]],
   sub="Free. No account. No subscription. Just better choreography."),
}

def radial_bg():
    sw,sh=W//8,H//8; img=Image.new("RGB",(sw,sh)); px=img.load()
    cx,cy=sw*0.5,sh*0.30; maxd=((max(cx,sw-cx))**2+(max(cy,sh-cy))**2)**.5
    stops=[(0,NLITE),(0.55,NAVY),(1,DEEP)]
    for y in range(sh):
        for x in range(sw):
            d=min(1,(((x-cx)**2+(y-cy)**2)**.5)/maxd)
            for i in range(len(stops)-1):
                p0,c0=stops[i]; p1,c1=stops[i+1]
                if d<=p1: px[x,y]=lerp(c0,c1,(d-p0)/(p1-p0) if p1>p0 else 0); break
            else: px[x,y]=stops[-1][1]
    return img.resize((W,H),Image.BICUBIC).convert("RGBA")

def grid(im):
    ov=Image.new("RGBA",(W,H),(0,0,0,0)); d=ImageDraw.Draw(ov)
    for i in range(1,9): d.line([(round(i*W/9),0),(round(i*W/9),H)],fill=(255,255,255,12),width=1)
    for j in range(1,18): d.line([(0,round(j*H/18)),(W,round(j*H/18))],fill=(255,255,255,12),width=1)
    return Image.alpha_composite(im,ov)

def overlay(im,fn):
    ov=Image.new("RGBA",(W,H),(0,0,0,0)); fn(ImageDraw.Draw(ov)); im.alpha_composite(ov)

def render(beat):
    c=CONFIGS[beat]; accent=c["accent"]
    im=grid(radial_bg()); d=ImageDraw.Draw(im); cx=W/2; y=130

    tf=f(SEMI,28); tw=d.textlength(c["tag"],font=tf); pw,ph=int(tw+52),66; x0=int(cx-pw/2)
    overlay(im, lambda dr:(dr.rounded_rectangle([x0,y,x0+pw,y+ph],radius=ph//2,fill=accent+(36,),outline=accent+(120,),width=3),
                           dr.text((cx,y+ph/2+1),c["tag"],font=tf,fill=accent+(255,),anchor="mm")))
    y+=ph+44

    # headline lines (auto-fit each line to width)
    maxw=W-150
    for line in c["lines"]:
        size=104
        while size>54:
            hf=f(HEAD,size)
            if sum(d.textlength(s,font=hf) for s,_ in line)<=maxw: break
            size-=3
        hf=f(HEAD,size); total=sum(d.textlength(s,font=hf) for s,_ in line); x=cx-total/2
        for s,col in line: d.text((x,y),s,font=hf,fill=col,anchor="la"); x+=d.textlength(s,font=hf)
        y+=int(size*1.05)
    y+=14
    if c.get("sub"):
        sf=f(SEMI,38)
        # wrap sub
        words=c["sub"].split(); cur=""; lines=[]
        for w in words:
            t=(cur+" "+w).strip()
            if d.textlength(t,font=sf)<=W-160: cur=t
            else: lines.append(cur); cur=w
        if cur: lines.append(cur)
        for ln in lines: d.text((cx,y),ln,font=sf,fill=DIM,anchor="ma"); y+=int(38*1.32)
    y+=30

    # floor card — big, fills the lower frame
    floor=Image.open(os.path.join(CAP,c["floor"])).convert("RGB")
    card_x=42; card_w=W-2*card_x
    card_y=int(y+22); card_h=(H-64)-card_y
    # cover-crop floor to card aspect, centered
    fa=card_w/card_h; iw,ih=floor.size
    if iw/ih>fa:
        nw=int(ih*fa); l=(iw-nw)//2; fc=floor.crop((l,0,l+nw,ih))
    else:
        nh=int(iw/fa); t=(ih-nh)//2; fc=floor.crop((0,t,iw,t+nh))
    card=fc.resize((card_w,card_h),Image.LANCZOS)
    mask=Image.new("L",(card_w,card_h),0); ImageDraw.Draw(mask).rounded_rectangle([0,0,card_w-1,card_h-1],radius=40,fill=255)
    glow=Image.new("RGBA",(W,H),(0,0,0,0)); ImageDraw.Draw(glow).ellipse([card_x-30,card_y+60,card_x+card_w+30,card_y+card_h+60],fill=accent+(40,))
    im.alpha_composite(glow.filter(ImageFilter.GaussianBlur(130)))
    sh=Image.new("RGBA",(W,H),(0,0,0,0)); ImageDraw.Draw(sh).rounded_rectangle([card_x,card_y+24,card_x+card_w,card_y+card_h+24],radius=40,fill=(0,0,0,150))
    im.alpha_composite(sh.filter(ImageFilter.GaussianBlur(44)))
    im.paste(card,(card_x,card_y),mask)
    ImageDraw.Draw(im).rounded_rectangle([card_x,card_y,card_x+card_w-1,card_y+card_h-1],radius=40,outline=(60,78,110,255),width=3)

    if c.get("chips"):
        cyy=card_y+card_h-118; cf=f(HEAD,52)
        positions=[cx-285,cx+285]
        for (label,col),xc in zip(c["chips"],positions):
            tw=d.textlength(label,font=cf); bw,bh=int(tw+56),90; x=int(xc-bw/2)
            overlay(im, lambda dr,x=x,bw=bw,bh=bh,col=col,xc=xc,label=label,cyy=cyy:(
                dr.rounded_rectangle([x,cyy,x+bw,cyy+bh],radius=bh//2,fill=col+(150,),outline=col+(230,),width=4),
                dr.text((xc,cyy+bh/2+2),label,font=cf,fill=WHITE+(255,),anchor="mm")))

    out=os.path.join(OUTD,c["out"]); im.convert("RGB").save(out)
    print("wrote",out,im.size)

if __name__=="__main__":
    render(sys.argv[1] if len(sys.argv)>1 else "hero")
