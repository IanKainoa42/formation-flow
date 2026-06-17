#!/usr/bin/env python3
"""Overlay the marketing headline/caption onto the split-screen hero."""
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = os.path.join(ROOT, "AppStoreScreenshots/captures/ipad/split_pyramid_fill.png")
OUT  = os.path.join(ROOT, "AppStoreScreenshots/marketing-v2/ipad/ipad_01_hero.png")
os.makedirs(os.path.dirname(OUT), exist_ok=True)

WHITE=(255,255,255); CORAL=(255,71,87); GREEN=(81,207,102); CYAN=(0,212,255)
NAVY=(8,12,24); DIM=(255,255,255,205)
HEAD="/Library/Fonts/InterTight-Black.ttf"; SEMI="/Library/Fonts/Inter-SemiBold.ttf"; REG="/Library/Fonts/Inter-Regular.ttf"
def f(p,s): return ImageFont.truetype(p,s)

im = Image.open(BASE).convert("RGBA")
W,H = im.size
d = ImageDraw.Draw(im)

# top scrim
scrim = Image.new("RGBA",(W,H),(0,0,0,0)); sd=ImageDraw.Draw(scrim)
band=int(H*0.33)
for y in range(band):
    a=int(238*(1-y/band)**1.25); sd.line([(0,y),(W,y)],fill=NAVY+(a,))
botS=int(H*0.84)
for y in range(botS,H):
    a=int(150*((y-botS)/(H-botS))); sd.line([(0,y),(W,y)],fill=NAVY+(a,))
im.alpha_composite(scrim)

cx=W/2
# tag pill
tag="CHEER CHOREOGRAPHY PLANNING"; tf=f(SEMI,34)
tw=d.textlength(tag,font=tf); pw,ph=int(tw+64),80; x0=int(cx-pw/2); ty=66
ov=Image.new("RGBA",(W,H),(0,0,0,0)); od=ImageDraw.Draw(ov)
od.rounded_rectangle([x0,ty,x0+pw,ty+ph],radius=ph//2,fill=CORAL+(38,),outline=CORAL+(120,),width=3)
od.text((cx,ty+ph/2+1),tag,font=tf,fill=CORAL+(255,),anchor="mm")
im.alpha_composite(ov)

# headline, auto-fit width
segs=[("Your transitions are ",WHITE),("ugly.",CORAL)]
size=150; maxw=W-280
while size>90:
    hf=f(HEAD,size)
    if sum(d.textlength(s,font=hf) for s,_ in segs)<=maxw: break
    size-=4
hf=f(HEAD,size)
y=ty+ph+44
total=sum(d.textlength(s,font=hf) for s,_ in segs); x=cx-total/2
for s,c in segs:
    d.text((x,y),s,font=hf,fill=c,anchor="la"); x+=d.textlength(s,font=hf)
y+=int(size*1.02)
# punchline second line
pf=f(SEMI,int(size*0.5))
d.text((cx,y),"And everybody is talking about it.",font=pf,fill=WHITE,anchor="ma")

# BEFORE / AFTER chips
def chip(xc,label,color):
    cf=f(HEAD,58); tw=d.textlength(label,font=cf); bw,bh=int(tw+72),100
    x=int(xc-bw/2); yy=H-188
    o=Image.new("RGBA",(W,H),(0,0,0,0)); oo=ImageDraw.Draw(o)
    oo.rounded_rectangle([x,yy,x+bw,yy+bh],radius=bh//2,fill=color+(48,),outline=color+(160,),width=4)
    oo.text((xc,yy+bh/2+2),label,font=cf,fill=color+(255,),anchor="mm")
    im.alpha_composite(o)
chip(W*0.25,"BEFORE",CORAL)
chip(W*0.75,"AFTER",GREEN)

im.convert("RGB").save(OUT)
print("wrote",OUT,im.size,"headline pt",size)
