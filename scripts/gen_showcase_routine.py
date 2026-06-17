#!/usr/bin/env python3
"""Generate a clean showcase RoutineWorkspace JSON for FormationFlow App Store shots.

18 athletes, 3 intentional formations (Pyramid -> V-Formation -> Spread),
with curved transition paths (quadratic control points) so the 'Draw the Path'
beat shows deliberate, non-colliding curves. Court is 72ft x 56ft.
Writes .appstore/showcase_routine.json (the workspace.v1.json payload).
"""
import json, uuid, os, math

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, ".appstore/showcase_routine.json")
CW, CH = 72.0, 56.0
CX = CW / 2  # 36

NAMES = ["Kat","Mia","Ava","Zoe","Lea","Liv","Eva","Ivy","Joy",
         "Sky","Tay","Rae","Cor","Jas","Ash","Sam","Bri","Kai"]
ROLES = ["flyer","base","spotter","base","flyer","tumbler","base","spotter","flyer",
         "base","backspot","base","spotter","flyer","tumbler","base","backspot","flyer"]
N = len(NAMES)

def uid():
    return str(uuid.uuid4()).upper()

athletes = [{"id": uid(), "label": NAMES[i], "role": ROLES[i]} for i in range(N)]
AID = [a["id"] for a in athletes]

def row(cx, y, count, spacing):
    return [(cx + (i - (count - 1) / 2) * spacing, y) for i in range(count)]

# --- Formation 1: Pyramid (rows 2,4,6,6 widening downward) -------------------
pyramid = []
pyramid += row(CX, 12, 2, 12)
pyramid += row(CX, 22, 4, 10)
pyramid += row(CX, 32, 6, 9)
pyramid += row(CX, 42, 6, 11)

# --- Formation 2: V-Formation (two arms opening upward) ----------------------
vform = []
left, right = [], []
for k in range(9):
    left.append((CX - 4 - k * 3.2, 44 - k * 4))
    right.append((CX + 4 + k * 3.2, 44 - k * 4))
vform = left + right

# --- Formation 3: Spread (two staggered horizontal lines of 9) ---------------
spread = row(CX, 23, 9, 7) + [(x + 3.5, 35) for (x, _) in row(CX, 35, 9, 7)]

assert len(pyramid) == len(vform) == len(spread) == N, (len(pyramid), len(vform), len(spread))

def clamp(p):
    return (round(max(4.0, min(CW - 4, p[0])), 1), round(max(4.0, min(CH - 4, p[1])), 1))

pyramid = [clamp(p) for p in pyramid]
vform   = [clamp(p) for p in vform]
spread  = [clamp(p) for p in spread]

FORMS = [("Pyramid", pyramid), ("V-Formation", vform), ("Spread", spread)]
FID = [uid() for _ in FORMS]

def placements(poslist):
    return [{"athleteID": AID[i], "positionX": poslist[i][0], "positionY": poslist[i][1]}
            for i in range(N)]

formations = [{"id": FID[f], "name": name, "notes": "", "placements": placements(pos)}
              for f, (name, pos) in enumerate(FORMS)]

# --- Transition specs with outward-bowing curved control points --------------
def control_point(start, end):
    mx, my = (start[0] + end[0]) / 2, (start[1] + end[1]) / 2
    dx, dy = end[0] - start[0], end[1] - start[1]
    L = math.hypot(dx, dy) or 1.0
    # perpendicular, bow away from court center horizontally
    nx, ny = -dy / L, dx / L
    side = 1.0 if mx >= CX else -1.0
    if nx * side < 0:
        nx, ny = -nx, -ny
    off = min(10.0, 4.0 + L * 0.18)
    return (round(mx + nx * off, 1), round(my + ny * off, 1))

def transition(fi, ti, posA, posB):
    ats = []
    for i in range(N):
        cp = control_point(posA[i], posB[i])
        ats.append({"athleteID": AID[i],
                    "moveDelay": float(i % 3),
                    "pathWaypoints": [],
                    "controlX": cp[0], "controlY": cp[1]})
    return {"id": uid(), "fromFormationID": FID[fi], "toFormationID": FID[ti],
            "duration": 8.0, "athleteTransitions": ats}

specs = [transition(0, 1, pyramid, vform), transition(1, 2, vform, spread)]

routine_id = uid()
workspace = {
    "routines": [{
        "id": routine_id, "name": "Routine 1",
        "roster": athletes, "formations": formations, "transitionSpecs": specs,
    }],
    "activeRoutineID": routine_id,
}

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w") as f:
    json.dump(workspace, f)
print(f"wrote {OUT}: {N} athletes, {len(formations)} formations, {len(specs)} transitions")
