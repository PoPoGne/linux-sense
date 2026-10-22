#!/usr/bin/env python3
"""Generates the Linux Sense logo with vectorcraft-cli (headless).

Usage: build_logo.py <vectorcraft-cli> <output-folder>
Produces linux-sense.vectorcraft (editable source), linux-sense.svg and PNGs.
"""
import json
import subprocess
import sys
from pathlib import Path

VC, OUT = sys.argv[1], Path(sys.argv[2])
OUT.mkdir(parents=True, exist_ok=True)

RED = "#ff2e4d"
ORANGE = "#ff8a3d"


def hexagon(r, cx=512, cy=512):
    # hexagon with a vertex at the top
    import math
    pts = []
    for i in range(6):
        a = math.radians(-90 + 60 * i)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return "M" + " L".join(f"{x:.2f} {y:.2f}" for x, y in pts) + " Z"


steps = []


def add(cid, params=None):
    steps.append((cid, params or {}))


add("file.new", {"name": "Linux Sense", "width": 1024, "height": 1024, "units": "Pixels"})

# 1. dark hexagonal base
add("path.create", {"d": hexagon(440)})
add("paint.setFill", {"gradient": {"kind": "linear", "angle": -90, "stops": [
    {"offset": 0, "color": "#232834"}, {"offset": 1, "color": "#0a0c11"}]}})
add("paint.setStroke", {"none": True})

# 2. border with red -> orange gradient
add("path.create", {"d": hexagon(440)})
add("paint.setFill", {"none": True})
add("paint.setStroke", {"gradient": {"kind": "linear", "angle": -60, "stops": [
    {"offset": 0, "color": RED}, {"offset": 1, "color": ORANGE}]}})
add("stroke.set", {"weight": 24, "join": "miter", "align": "inside"})

# 3. thin inner line
add("path.create", {"d": hexagon(384)})
add("paint.setFill", {"none": True})
add("paint.setStroke", {"color": "#ffffff"})
add("stroke.set", {"weight": 3, "join": "miter"})
add("transparency.set", {"opacity": 10})

# 4. horizontal "HUD" lines on the sides of the S
for d in ("M176 512 L318 512", "M706 512 L848 512"):
    add("path.create", {"d": d})
    add("paint.setFill", {"none": True})
    add("paint.setStroke", {"color": RED})
    add("stroke.set", {"weight": 8, "cap": "butt"})
    add("transparency.set", {"opacity": 55})

# 5. angular S monogram, as an explicit outline with 45° cut ends
def s_outline(h=42, slant=22):
    import math
    c = [(686, 330), (416, 330), (370, 376), (370, 466), (416, 512), (608, 512),
         (654, 558), (654, 648), (608, 694), (338, 694)]

    def off(p, q, d):
        dx, dy = q[0] - p[0], q[1] - p[1]
        n = math.hypot(dx, dy)
        nx, ny = -dy / n * d, dx / n * d
        return (p[0] + nx, p[1] + ny), (q[0] + nx, q[1] + ny)

    def inter(a1, a2, b1, b2):
        x1, y1 = a1; x2, y2 = a2; x3, y3 = b1; x4, y4 = b2
        den = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
        t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / den
        return (x1 + t * (x2 - x1), y1 + t * (y2 - y1))

    def side(d):
        segs = [off(c[i], c[i + 1], d) for i in range(len(c) - 1)]
        pts = [segs[0][0]]
        for a, b in zip(segs, segs[1:]):
            pts.append(inter(a[0], a[1], b[0], b[1]))
        pts.append(segs[-1][1])
        return pts

    a, b = side(h), side(-h)
    # parallel slanted ends ("/"): the top side sticks out to the right
    for pts in (a, b):
        top = pts[0][1] < 330
        pts[0] = (pts[0][0] + (slant if top else -slant), pts[0][1])
        top = pts[-1][1] < 694
        pts[-1] = (pts[-1][0] + (slant if top else -slant), pts[-1][1])
    poly = a + b[::-1]
    return "M" + " L".join(f"{x:.2f} {y:.2f}" for x, y in poly) + " Z"


add("path.create", {"d": s_outline()})
add("paint.setStroke", {"none": True})
add("paint.setFill", {"gradient": {"kind": "linear", "angle": -60, "stops": [
    {"offset": 0, "color": "#ff4658"}, {"offset": 1, "color": ORANGE}]}})

args = [VC, "run"]
for cid, params in steps:
    args += ["--cmd", cid, "--params", json.dumps(params)]
args += ["--export", str(OUT / "linux-sense.vectorcraft"),
         "--export", str(OUT / "linux-sense.svg")]
res = subprocess.run(args, capture_output=True, text=True, timeout=120)
failed = False
for line in res.stdout.splitlines():
    try:
        j = json.loads(line)
    except json.JSONDecodeError:
        continue
    if "error" in j or (j.get("result") or {}).get("warnings"):
        print(line)
        failed = failed or "error" in j
if res.returncode or failed:
    print(res.stdout[-3000:], res.stderr[-3000:])
    sys.exit(1)
for size in (16, 24, 32, 48, 64, 128, 256, 512, 1024):
    subprocess.run([VC, "convert", str(OUT / "linux-sense.vectorcraft"),
                    str(OUT / f"linux-sense-{size}.png"), "--scale", str(size / 1024)],
                   check=True, capture_output=True, timeout=60)
print("ok:", sorted(p.name for p in OUT.iterdir()))
