#!/usr/bin/env python3
"""Composite a full-UI iPad screenshot into a device frame on a navy background.
Usage: python3 scripts/device_frame.py <input.png> <output.png> ["Optional Header"]
Output is 2752x2064 (iPad 13").
"""
import sys, os, math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

W,H = 2752,2064
NAVY=(10,15,30); DEEP=(6,9,15); NLITE=(22,32,58)
WHITE=(255,255,255); CYAN=(0,212,255)
HEAD="/Library/Fonts/InterTight-Black.ttf"; SEMI="/Library/Fonts/Inter-SemiBold.ttf"
def lerp(a,b,t): return tuple(int(a[i]+(b[i]-a[i])*t) for i in range(3))

def radial_bg():
    sw,sh=W//8,H//8; img=Image.new("RGB",(sw,sh)); px=img.load()
    cx,cy=sw*0.5,sh*0.34; maxd=((max(cx,sw-cx))**2+(max(cy,sh-cy))**2)**.5
    stops=[(0,NLITE),(0.55,NAVY),(1,DEEP)]
    for y in range(sh):
        for x in range(sw):
            d=min(1,(((x-cx)**2+(y-cy)**2)**.5)/maxd)
            for i in range(len(stops)-1):
                p0,c0=stops[i];p1,c1=stops[i+1]
                if d<=p1: px[x,y]=lerp(c0,c1,(d-p0)/(p1-p0) if p1>p0 else 0); break
            else: px[x,y]=stops[-1][1]
    return img.resize((W,H),Image.BICUBIC).convert("RGBA")

def grid(im):
    ov=Image.new("RGBA",(W,H),(0,0,0,0)); d=ImageDraw.Draw(ov)
    for i in range(1,9): d.line([(round(i*W/9),0),(round(i*W/9),H)],fill=(255,255,255,10),width=1)
    for j in range(1,14): d.line([(0,round(j*H/14)),(W,round(j*H/14))],fill=(255,255,255,10),width=1)
    return Image.alpha_composite(im,ov)

def rounded(size,r):
    m=Image.new("L",size,0); ImageDraw.Draw(m).rounded_rectangle([0,0,size[0]-1,size[1]-1],radius=r,fill=255); return m

def main():
    inp,outp = sys.argv[1], sys.argv[2]
    header = sys.argv[3] if len(sys.argv)>3 else None
    shot=Image.open(inp).convert("RGB")

    im=grid(radial_bg())
    top_pad = 250 if header else 0

    # device sizing (screen aspect 1.333), fit within canvas leaving navy margins
    bezel=30
    avail_h = H - 150 - top_pad
    screen_h = min(int(avail_h), 1760)
    screen_w = int(screen_h*1.3333)
    if screen_w > W-220:
        screen_w=W-220; screen_h=int(screen_w/1.3333)
    dev_w, dev_h = screen_w+2*bezel, screen_h+2*bezel
    dev_x=(W-dev_w)//2
    dev_y=int(top_pad + ( (H-top_pad) - dev_h)//2)

    # glow
    glow=Image.new("RGBA",(W,H),(0,0,0,0))
    ImageDraw.Draw(glow).rounded_rectangle([dev_x-20,dev_y-20,dev_x+dev_w+20,dev_y+dev_h+20],radius=90,fill=CYAN+(26,))
    im.alpha_composite(glow.filter(ImageFilter.GaussianBlur(120)))
    # shadow
    sh=Image.new("RGBA",(W,H),(0,0,0,0))
    ImageDraw.Draw(sh).rounded_rectangle([dev_x,dev_y+30,dev_x+dev_w,dev_y+dev_h+30],radius=86,fill=(0,0,0,180))
    im.alpha_composite(sh.filter(ImageFilter.GaussianBlur(55)))
    # device body
    body=Image.new("RGBA",(dev_w,dev_h),(0,0,0,0))
    ImageDraw.Draw(body).rounded_rectangle([0,0,dev_w-1,dev_h-1],radius=86,fill=(14,14,18,255),outline=(60,64,74,255),width=3)
    im.alpha_composite(body,(dev_x,dev_y))
    # screen
    scr=shot.resize((screen_w,screen_h),Image.LANCZOS)
    sm=rounded((screen_w,screen_h),58)
    im.paste(scr,(dev_x+bezel,dev_y+bezel),sm)
    ImageDraw.Draw(im).rounded_rectangle([dev_x+bezel,dev_y+bezel,dev_x+bezel+screen_w-1,dev_y+bezel+screen_h-1],radius=58,outline=(0,0,0,160),width=2)

    if header:
        d=ImageDraw.Draw(im)
        hf=ImageFont.truetype(HEAD,116)
        # accent last word cyan
        parts=header.rsplit(" ",1)
        if len(parts)==2:
            a,b=parts[0]+" ",parts[1]
            tw=d.textlength(a,font=hf)+d.textlength(b,font=hf); x=W/2-tw/2; yy=96
            d.text((x,yy),a,font=hf,fill=WHITE,anchor="la"); d.text((x+d.textlength(a,font=hf),yy),b,font=hf,fill=CYAN,anchor="la")
        else:
            d.text((W/2,96),header,font=hf,fill=WHITE,anchor="ma")

    im.convert("RGB").save(outp); print("wrote",outp,im.size)

if __name__=="__main__": main()
