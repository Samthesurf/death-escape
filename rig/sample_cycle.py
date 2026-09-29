"""Sample N interpolated frames across the run cycle (same math as preview.html
and export_keys.py) so the in-betweens can be inspected, not just the keys."""
import math, sys
from PIL import Image, ImageDraw

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
CLEAR = [-2, -2, 0, 6, -2, -2, 0, 6]
L = dict(thigh=44, shin=42, torso=52, head=12, ua=32, fa=28)
INK = (46, 44, 40)
FAR = (150, 148, 142)
GROUND = 185


def joints(p, hx, hy):
    lean = math.radians(p["lean"])
    sh = (hx + math.sin(lean) * L["torso"], hy - math.cos(lean) * L["torso"])
    head = (sh[0] + math.sin(lean) * 12.5, sh[1] - math.cos(lean) * 12.5)

    def leg(th, kn):
        a, k = math.radians(th), math.radians(kn)
        kx, ky = hx + math.sin(a) * L["thigh"], hy + math.cos(a) * L["thigh"]
        sa = a - k
        return (kx, ky), (kx + math.sin(sa) * L["shin"], ky + math.cos(sa) * L["shin"])

    def arm(th, eb):
        a, e = math.radians(th), math.radians(eb)
        ex, ey = sh[0] + math.sin(a) * L["ua"], sh[1] + math.cos(a) * L["ua"]
        sa = a + e
        return (ex, ey), (ex + math.sin(sa) * L["fa"], ey + math.cos(sa) * L["fa"])

    rk, rf = leg(p["rT"], p["rK"])
    lk, lf = leg(p["lT"], p["lK"])
    re, rh = arm(p["rS"], p["rE"])
    le, lh = arm(p["lS"], p["lE"])
    return dict(hip=(hx, hy), sh=sh, head=head, rK=rk, rF=rf, lK=lk, lF=lf,
                rE=re, rH=rh, lE=le, lH=lh)


DUR = [0.5, 0.7, 1.0, 1.3, 0.5, 0.7, 1.0, 1.3]
TOTAL = sum(DUR)


def seg_at(t):
    t = t % TOTAL
    i = 0
    while t > DUR[i]:
        t -= DUR[i]
        i = (i + 1) % len(DUR)
    return i, t / DUR[i]


def pose_at(t):
    n = len(KEYS)
    i, f = seg_at(t)
    A, B = KEYS[i], KEYS[(i + 1) % n]
    return {k: A[k] + (B[k] - A[k]) * f for k in A}


def clear_at(t):
    n = len(KEYS)
    i, f = seg_at(t)
    return CLEAR[i] + (CLEAR[(i + 1) % n] - CLEAR[i]) * f


def draw_frame(t, S=2):
    W = H = 200
    img = Image.new("RGB", (W * S, H * S), "white")
    d = ImageDraw.Draw(img)
    p = pose_at(t)
    J0 = joints(p, 100 + p["hipX"], 120)
    low = max(J0["rF"][1], J0["lF"][1])
    J = joints(p, 100 + p["hipX"], 120 + ((GROUND + clear_at(t)) - low))

    def ln(a, b, c=INK, w=3):
        d.line([a[0] * S, a[1] * S, b[0] * S, b[1] * S], fill=c, width=w * S)

    gy = GROUND * S
    d.line([20 * S, gy, 180 * S, gy], fill=INK, width=2 * S)
    for A, B in [(J["hip"], J["lK"]), (J["lK"], J["lF"]), (J["sh"], J["lE"]), (J["lE"], J["lH"])]:
        ln(A, B, FAR)
    for A, B in [(J["hip"], J["sh"]), (J["hip"], J["rK"]), (J["rK"], J["rF"]),
                 (J["sh"], J["rE"]), (J["rE"], J["rH"])]:
        ln(A, B)
    for f in (J["rF"], J["lF"]):
        ln((f[0] - 5, f[1]), (f[0] + 5, f[1]))
    for j in (J["hip"], J["sh"]):
        d.ellipse([j[0] * S - 3 * S, j[1] * S - 3 * S, j[0] * S + 3 * S, j[1] * S + 3 * S], fill=INK)
    hx, hy = J["head"]
    d.ellipse([hx * S - 12 * S, hy * S - 12 * S, hx * S + 12 * S, hy * S + 12 * S],
              outline=INK, width=3 * S)
    return img


if __name__ == "__main__":
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 12
    out = sys.argv[2] if len(sys.argv) > 2 else "/home/samuelsurf/.hermes/cache/scratch/cycle_sample.png"
    frames = [draw_frame(i * 6 / n) for i in range(n)]
    sheet = Image.new("RGB", (400 * n, 400), "white")
    for i, f in enumerate(frames):
        sheet.paste(f, (i * 400, 0))
    sheet.save(out)
    print("saved", out)
