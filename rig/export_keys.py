"""Export the 6 run keys as transparent, registration-stable SVG sprites.

Same rig math as preview.html. Fixed 200x200 viewBox, hip anchor locked at
(100,120); only joints move. Wobble uses a seeded RNG with the same seed
every frame so the pencil character stays consistent across keys.
"""
import math, os, random

KEYS = [
    dict(lean=14, hipX=-8, rT=36,  rK=14, lT=-32, lK=28,  rS=-28, rE=55, lS=30,  lE=50),
    dict(lean=16, hipX=6,  rT=-8,  rK=12, lT=-52, lK=10,  rS=-2,  rE=55, lS=6,   lE=55),
    dict(lean=18, hipX=12, rT=6,   rK=12, lT=28,  lK=115, rS=22,  rE=50, lS=-20, lE=60),
    dict(lean=16, hipX=2,  rT=-35, rK=30, lT=34,  lK=14,  rS=30,  rE=50, lS=-28, lE=55),
    dict(lean=14, hipX=-8, rT=-32, rK=28, lT=36,  lK=14,  rS=30,  rE=50, lS=-28, lE=55),
    dict(lean=16, hipX=6,  rT=-52, rK=10, lT=-8,  lK=12,  rS=6,   rE=55, lS=-2,  lE=55),
    dict(lean=18, hipX=12, rT=28,  rK=115, lT=6,  lK=12,  rS=-20, rE=60, lS=22,  lE=50),
    dict(lean=16, hipX=2,  rT=34,  rK=14, lT=-35, lK=30,  rS=-28, rE=55, lS=30,  lE=50),
]

L = dict(thigh=44, shin=42, torso=52, head=12, ua=32, fa=28)
NAMES = ["1_R_contact", "2_R_stance", "3_L_swingthru", "4_L_plant",
         "5_L_contact", "6_L_stance", "7_R_swingthru", "8_R_plant"]
OUT = "/home/samuelsurf/Death escape/assets/stick-runner/rig"
os.makedirs(OUT, exist_ok=True)
INK = "#2e2c28"


def joints(p, hx, hy):
    lean = math.radians(p["lean"])
    sh = (hx + math.sin(lean) * L["torso"], hy - math.cos(lean) * L["torso"])
    head = (sh[0] + math.sin(lean) * 12.5, sh[1] - math.cos(lean) * 12.5)

    def leg(th, kn):
        a, k = math.radians(th), math.radians(kn)
        kx, ky = hx + math.sin(a) * L["thigh"], hy + math.cos(a) * L["thigh"]
        sa = a - k
        fx, fy = kx + math.sin(sa) * L["shin"], ky + math.cos(sa) * L["shin"]
        return (kx, ky), (fx, fy)

    def arm(th, eb):
        a, e = math.radians(th), math.radians(eb)
        ex, ey = sh[0] + math.sin(a) * L["ua"], sh[1] + math.cos(a) * L["ua"]
        sa = a + e
        hx2, hy2 = ex + math.sin(sa) * L["fa"], ey + math.cos(sa) * L["fa"]
        return (ex, ey), (hx2, hy2)

    return dict(hip=(hx, hy), sh=sh, head=head,
                rK=leg(p["rT"], p["rK"])[0], rF=leg(p["rT"], p["rK"])[1],
                lK=leg(p["lT"], p["lK"])[0], lF=leg(p["lT"], p["lK"])[1],
                rE=arm(p["rS"], p["rE"])[0], rH=arm(p["rS"], p["rE"])[1],
                lE=arm(p["lS"], p["lE"])[0], lH=arm(p["lS"], p["lE"])[1])


def wobble_line(rng, a, b, w, extra=""):
    # 3-segment jittered polyline reads as pencil at game size
    mx, my = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
    dx, dy = b[0] - a[0], b[1] - a[1]
    leng = math.hypot(dx, dy) or 1
    nx, ny = -dy / leng, dx / leng
    j1, j2 = rng.uniform(-1.4, 1.4), rng.uniform(-1.4, 1.4)
    m1 = (a[0] * 0.75 + b[0] * 0.25 + nx * j1, a[1] * 0.75 + b[1] * 0.25 + ny * j1)
    m2 = (a[0] * 0.25 + b[0] * 0.75 + nx * j2, a[1] * 0.25 + b[1] * 0.75 + ny * j2)
    pts = " ".join(f"{x:.1f},{y:.1f}" for x, y in (a, m1, m2, b))
    return (f'<polyline points="{pts}" fill="none" stroke="{INK}" '
            f'stroke-width="{w}" stroke-linecap="round" stroke-linejoin="round" {extra}/>')


for i, (p, name) in enumerate(zip(KEYS, NAMES)):
    rng = random.Random(7)  # same seed every key: consistent wobble
    # auto-ground: solve hip height so lowest foot plants (contact/stance)
    # or clears (swing/plant) the implied ground at y=185
    clear = [-2, -2, 0, 6, -2, -2, 0, 6][i]
    J0 = joints(p, 100 + p["hipX"], 120)
    low = max(J0["rF"][1], J0["lF"][1])
    J = joints(p, 100 + p["hipX"], 120 + ((185 - clear) - low))
    s = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200" '
         f'width="200" height="200">']
    # far limbs first, lighter
    s.append(wobble_line(rng, J["hip"], J["lK"], 3.4, 'opacity="0.62"'))
    s.append(wobble_line(rng, J["lK"], J["lF"], 3.4, 'opacity="0.62"'))
    s.append(wobble_line(rng, J["sh"], J["lE"], 3.4, 'opacity="0.62"'))
    s.append(wobble_line(rng, J["lE"], J["lH"], 3.4, 'opacity="0.62"'))
    # torso + near limbs
    s.append(wobble_line(rng, J["hip"], J["sh"], 3.8))
    s.append(wobble_line(rng, J["hip"], J["rK"], 3.4))
    s.append(wobble_line(rng, J["rK"], J["rF"], 3.4))
    s.append(wobble_line(rng, J["sh"], J["rE"], 3.4))
    s.append(wobble_line(rng, J["rE"], J["rH"], 3.4))
    # feet + hands + head
    for f in (J["rF"], J["lF"]):
        s.append(wobble_line(rng, (f[0] - 5, f[1]), (f[0] + 5, f[1]), 3))
    for h in (J["rH"], J["lH"]):
        s.append(f'<circle cx="{h[0]:.1f}" cy="{h[1]:.1f}" r="2.6" fill="{INK}"/>')
    hx, hy = J["head"]
    s.append(f'<circle cx="{hx:.1f}" cy="{hy:.1f}" r="{L["head"]}" fill="none" '
             f'stroke="{INK}" stroke-width="3.4"/>')
    for j in (J["hip"],):
        s.append(f'<circle cx="{j[0]:.1f}" cy="{j[1]:.1f}" r="3" fill="{INK}"/>')
    s.append('</svg>')
    open(os.path.join(OUT, f"run_{name}.svg"), "w").write("\n".join(s))
print("wrote", len(KEYS), "svgs to", OUT)
