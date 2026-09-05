#!/usr/bin/env python3
"""App Store Connect media uploader for FormationFlow.
Modes:
  query                       - print app/version/localization + current screenshot+preview sets
  upload <ver> [build]        - create/reuse the ASC version, set what's-new, attach the build,
                                and delete-then-replace both en-US screenshot sets from
                                AppStoreScreenshots/ship-ready/
Auth: ASC API key 8APDGY74BZ (issuer in ISSUER). Key at ~/.appstoreconnect/private_keys/.
"""
import sys, os, time, json, hashlib
import jwt, requests

KEY_ID="8APDGY74BZ"
ISSUER="7642a25e-aca7-402d-8b7d-de18dfef1756"
KEY_PATH=os.path.expanduser("~/.appstoreconnect/private_keys/AuthKey_8APDGY74BZ.p8")
BUNDLE="com.ianrichardson.formationflow"
BASE="https://api.appstoreconnect.apple.com/v1"
TARGET_VERSION="1.1"

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



# ---------------------------------------------------------------- upload mode

SHIP_READY = "AppStoreScreenshots/ship-ready"
SETS = {
    "APP_IPAD_PRO_3GEN_129": sorted(f"{SHIP_READY}/ipad/{n}" for n in os.listdir(f"{SHIP_READY}/ipad")
                                    if n.endswith(".png")) if os.path.isdir(f"{SHIP_READY}/ipad") else [],
    "APP_IPHONE_67": sorted(f"{SHIP_READY}/iphone/{n}" for n in os.listdir(f"{SHIP_READY}/iphone")
                            if n.endswith(".png")) if os.path.isdir(f"{SHIP_READY}/iphone") else [],
}


def ensure_version(aid, version_string):
    """Return the appStoreVersion id for `version_string`, creating it if absent."""
    for v in versions(aid):
        if v["attributes"]["versionString"] == version_string:
            print(f"  version {version_string} exists ({v['attributes']['appStoreState']})")
            return v["id"]
    d = post("/appStoreVersions", {"data": {
        "type": "appStoreVersions",
        "attributes": {"platform": "IOS", "versionString": version_string,
                       "releaseType": "AFTER_APPROVAL"},
        "relationships": {"app": {"data": {"type": "apps", "id": aid}}},
    }})
    print(f"  created version {version_string}")
    return d["data"]["id"]


def en_us_localization(vid):
    for l in get(f"/appStoreVersions/{vid}/appStoreVersionLocalizations")["data"]:
        if l["attributes"]["locale"] == "en-US":
            return l["id"]
    raise SystemExit("no en-US localization")


def set_release_notes(lid, path):
    notes = open(path).read().strip()
    patch(f"/appStoreVersionLocalizations/{lid}",
          {"data": {"type": "appStoreVersionLocalizations", "id": lid,
                    "attributes": {"whatsNew": notes}}})
    print(f"  what's-new set ({len(notes)} chars)")


def attach_build(aid, vid, build_number):
    bs = get("/builds", **{"filter[app]": aid, "filter[version]": str(build_number), "limit": 1})["data"]
    if not bs:
        raise SystemExit(f"build {build_number} not found on ASC")
    b = bs[0]
    state = b["attributes"]["processingState"]
    if state != "VALID":
        raise SystemExit(f"build {build_number} is {state}, not VALID — wait for processing")
    patch(f"/appStoreVersions/{vid}",
          {"data": {"type": "appStoreVersions", "id": vid,
                    "relationships": {"build": {"data": {"type": "builds", "id": b["id"]}}}}})
    print(f"  build {build_number} attached ({b['id']})")
    return b["id"]


def screenshot_set(lid, display_type):
    """Return the set id for display_type, creating it if absent."""
    for s in get(f"/appStoreVersionLocalizations/{lid}/appScreenshotSets")["data"]:
        if s["attributes"]["screenshotDisplayType"] == display_type:
            return s["id"]
    d = post("/appScreenshotSets", {"data": {
        "type": "appScreenshotSets",
        "attributes": {"screenshotDisplayType": display_type},
        "relationships": {"appStoreVersionLocalization":
                          {"data": {"type": "appStoreVersionLocalizations", "id": lid}}},
    }})
    return d["data"]["id"]


def clear_set(set_id):
    existing = get(f"/appScreenshotSets/{set_id}/appScreenshots")["data"]
    for s in existing:
        delete(f"/appScreenshots/{s['id']}")
    print(f"    cleared {len(existing)} existing shot(s)")


def upload_screenshot(set_id, path):
    blob = open(path, "rb").read()
    d = post("/appScreenshots", {"data": {
        "type": "appScreenshots",
        "attributes": {"fileSize": len(blob), "fileName": os.path.basename(path)},
        "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}},
    }})
    sid = d["data"]["id"]
    for op in d["data"]["attributes"]["uploadOperations"]:
        chunk = blob[op["offset"]:op["offset"] + op["length"]]
        headers = {h["name"]: h["value"] for h in op["requestHeaders"]}
        r = S.request(op["method"], op["url"], headers=headers, data=chunk)
        r.raise_for_status()
    patch(f"/appScreenshots/{sid}", {"data": {
        "type": "appScreenshots", "id": sid,
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(blob).hexdigest()},
    }})
    print(f"    + {os.path.basename(path)} ({len(blob)//1024} KB)")


def upload(version_string, build_number=None, notes_path="fastlane/metadata/en-US/release_notes.txt"):
    aid, name = app_id()
    print("APP:", name, aid)
    vid = ensure_version(aid, version_string)
    lid = en_us_localization(vid)
    if os.path.exists(notes_path):
        set_release_notes(lid, notes_path)
    if build_number:
        attach_build(aid, vid, build_number)
    for display_type, files in SETS.items():
        if not files:
            print(f"  {display_type}: no staged files, skipped")
            continue
        print(f"  {display_type}: replacing with {len(files)} shot(s)")
        sid = screenshot_set(lid, display_type)
        clear_set(sid)
        for f in files:
            upload_screenshot(sid, f)
    print("done")


if __name__=="__main__":
    mode=sys.argv[1] if len(sys.argv)>1 else "query"
    if mode=="query":
        query()
    elif mode=="upload":
        # usage: asc_upload.py upload <versionString> [buildNumber]
        upload(sys.argv[2], sys.argv[3] if len(sys.argv)>3 else None)
    else:
        raise SystemExit(f"unknown mode {mode!r} (query|upload)")
