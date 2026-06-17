#!/usr/bin/env python3
"""App Store Connect media uploader for FormationFlow.
Modes:
  query                       - print app/version/localization + current screenshot+preview sets
  upload                      - replace 1.0.5 screenshots (iPad13 + iPhone6.9) and the iPad App Preview
Auth: ASC API key 8APDGY74BZ (issuer in ISSUER). Key at ~/.appstoreconnect/private_keys/.
"""
import sys, os, time, json, hashlib
import jwt, requests

KEY_ID="8APDGY74BZ"
ISSUER="7642a25e-aca7-402d-8b7d-de18dfef1756"
KEY_PATH=os.path.expanduser("~/.appstoreconnect/private_keys/AuthKey_8APDGY74BZ.p8")
BUNDLE="com.ianrichardson.formationflow"
BASE="https://api.appstoreconnect.apple.com/v1"
TARGET_VERSION="1.0.5"

def token():
    with open(KEY_PATH) as fh: key=fh.read()
    now=int(time.time())
    return jwt.encode({"iss":ISSUER,"iat":now,"exp":now+1100,"aud":"appstoreconnect-v1"},
                      key, algorithm="ES256", headers={"kid":KEY_ID,"typ":"JWT"})

S=requests.Session()
def H(): return {"Authorization":f"Bearer {token()}"}
def get(path, **params):
    r=S.get(path if path.startswith("http") else BASE+path, headers=H(), params=params)
    r.raise_for_status(); return r.json()
def post(path, payload):
    r=S.post(BASE+path, headers={**H(),"Content-Type":"application/json"}, data=json.dumps(payload))
    if r.status_code>=300: print("POST ERR",r.status_code,r.text); r.raise_for_status()
    return r.json()
def patch(path, payload):
    r=S.patch(BASE+path, headers={**H(),"Content-Type":"application/json"}, data=json.dumps(payload))
    if r.status_code>=300: print("PATCH ERR",r.status_code,r.text); r.raise_for_status()
    return r.json()
def delete(path):
    r=S.delete(BASE+path, headers=H())
    if r.status_code not in (200,204): print("DEL ERR",r.status_code,r.text)
    return r.status_code

def app_id():
    d=get("/apps", **{"filter[bundleId]":BUNDLE})
    return d["data"][0]["id"], d["data"][0]["attributes"]["name"]

def versions(aid):
    return get(f"/apps/{aid}/appStoreVersions", **{"limit":50})["data"]

def query():
    aid,name=app_id(); print("APP:",name,aid)
    vs=versions(aid)
    for v in vs:
        a=v["attributes"]; print("  version",a["versionString"],"state",a["appStoreState"],"id",v["id"])
    tv=[v for v in vs if v["attributes"]["versionString"]==TARGET_VERSION]
    if not tv: print("  (no",TARGET_VERSION,"version)"); return
    vid=tv[0]["id"]
    locs=get(f"/appStoreVersions/{vid}/appStoreVersionLocalizations")["data"]
    for l in locs:
        if l["attributes"]["locale"]=="en-US":
            lid=l["id"]; print("  en-US loc",lid)
            ss=get(f"/appStoreVersionLocalizations/{lid}/appScreenshotSets")["data"]
            for s in ss:
                cnt=get(s["relationships"]["appScreenshots"]["links"]["related"])["data"]
                print("    screenshotSet",s["attributes"]["screenshotDisplayType"],"id",s["id"],"count",len(cnt))
            pv=get(f"/appStoreVersionLocalizations/{lid}/appPreviewSets")["data"]
            for p in pv:
                cnt=get(p["relationships"]["appPreviews"]["links"]["related"])["data"]
                print("    previewSet",p["attributes"]["previewType"],"id",p["id"],"count",len(cnt))

if __name__=="__main__":
    mode=sys.argv[1] if len(sys.argv)>1 else "query"
    if mode=="query": query()
