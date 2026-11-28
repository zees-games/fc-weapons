"""Models this pack's own-work grenades and the combat knife (CC0, modelled here from scratch) as source GLBs for the shared texture bake.
Run: blender -b -P tools/build_thrown_melee.py -- <out dir> [<name>...]   (no names: all)
Every grenade stands on +Y with the origin in the palm and shares one fuze: threaded neck, fuze body, striker hump, a spoon (lever) that
hooks over the top and runs down the body's side, a split safety pin through the fuze with its pull ring hanging clear. The bodies:
  flash_grenade       perforated steel tube (three rows of port holes over a dark core), blue identification band, end caps
  smoke_grenade       rolled-rim canister, olive drab, yellow band, emission holes in the top plate, body seam
  incendiary_grenade  taller red canister with ribbed black bands and rolled rims
  frag_grenade_alt    the sticky: a round steel body with an equator seam, the lower half under a knobbed adhesive pad
The knife (combat_knife): clip-point blade with a ground edge, fuller and swedge, a steel guard, a ribbed polymer grip with finger
grooves, a pommel with lanyard hole; laid along the axis the shipped knife used so the view hold keeps its framing.
Colours are picked for the bake's classes (tex_gen.py classify reads the sRGB albedo): steel grey reads as metal, near-black as
polymer, saturated paint as coat. Output: <out>/<name>.glb. Textures: addons/gs_weapon/tools/texbake/tex_pipeline.sh."""
import bpy, sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import blender_mesh_kit as kit  # noqa: E402
from blender_mesh_kit import Mesh, lathe, chamfered_ring, box, build  # noqa: E402

kit.MATS.update({  # linear colours; sRGB of the polymer stays under the bake's poly_max (0.19)
    'steel': ((0.33, 0.33, 0.34), 0.7, 0.4), 'fuze': ((0.26, 0.27, 0.25), 0.6, 0.45), 'spoon': ((0.42, 0.42, 0.40), 0.8, 0.35),
    'pin': ((0.62, 0.62, 0.64), 0.9, 0.3), 'core': ((0.012, 0.012, 0.013), 0.0, 0.9), 'grip': ((0.018, 0.018, 0.02), 0.0, 0.75),
    'od': ((0.13, 0.16, 0.07), 0.1, 0.6), 'yellow': ((0.72, 0.52, 0.04), 0.0, 0.55), 'red': ((0.42, 0.04, 0.025), 0.0, 0.55),
    'band_blue': ((0.04, 0.17, 0.48), 0.0, 0.5), 'tack': ((0.55, 0.17, 0.02), 0.0, 0.85), 'blade': ((0.62, 0.63, 0.65), 0.95, 0.22),
})
SEG = 32


def ycyl(profile, mat, segs=SEG, at=(0, 0, 0), teeth=0, depth=0.0, phase=0.0):
    """Lathe a [(r, y)] profile about +Y (bottom to top) and move it."""
    return lathe(profile, mat, segs, 'y', teeth=teeth, depth=depth, phase=phase).xf(None, at)


def yring(r_out, r_in, y0, y1, mat, segs=SEG, c=0.0006, teeth=0, depth=0.0):
    """A hollow ring about +Y from y0 to y1."""
    return chamfered_ring(r_out, y1 - y0, r_in, mat, c=c, segs=segs, teeth=teeth, depth=depth).xf([('x', 90)], (0, (y0 + y1) / 2, 0))


def torus(R, r, mat, at, normal='x', segs=28, tube=10):
    m = Mesh(mat)
    verts, faces = [], []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        for j in range(tube):
            b = 2 * math.pi * j / tube
            u, w = (R + r * math.cos(b)) * math.cos(a), (R + r * math.cos(b)) * math.sin(a)
            h = r * math.sin(b)
            verts.append((h, u, w) if normal == 'x' else (u, w, h) if normal == 'z' else (u, h, w))
    for i in range(segs):
        for j in range(tube):
            i2, j2 = (i + 1) % segs, (j + 1) % tube
            faces.append((i * tube + j, i2 * tube + j, i2 * tube + j2, i * tube + j2))
    return m.add(verts, faces).xf(None, at)


def sweep(path, half_w, half_t, mat, side=(0, 0, 1)):
    """A flat strip (width along `side`, thickness across) swept along a polyline: the spoon."""
    m = Mesh(mat)
    verts = []
    n = len(path)
    for k, p in enumerate(path):
        a, b = path[max(k - 1, 0)], path[min(k + 1, n - 1)]
        t = [b[i] - a[i] for i in range(3)]
        tl = math.sqrt(sum(x * x for x in t)) or 1.0
        t = [x / tl for x in t]
        s = side
        nrm = (t[1] * s[2] - t[2] * s[1], t[2] * s[0] - t[0] * s[2], t[0] * s[1] - t[1] * s[0])
        for sw, tw in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            verts.append(tuple(p[i] + sw * half_w * s[i] + tw * half_t * nrm[i] for i in range(3)))
    faces = []
    for k in range(n - 1):
        for e in range(4):
            e2 = (e + 1) % 4
            faces.append((k * 4 + e, k * 4 + e2, (k + 1) * 4 + e2, (k + 1) * 4 + e))
    faces += [(0, 1, 2, 3), ((n - 1) * 4 + 3, (n - 1) * 4 + 2, (n - 1) * 4 + 1, (n - 1) * 4)]
    return m.add(verts, faces)


def rod(path, r, mat, segs=10):
    """A round wire along a polyline: the safety pin."""
    m = Mesh(mat)
    verts, n = [], len(path)
    for k, p in enumerate(path):
        a, b = path[max(k - 1, 0)], path[min(k + 1, n - 1)]
        t = [b[i] - a[i] for i in range(3)]
        tl = math.sqrt(sum(x * x for x in t)) or 1.0
        t = [x / tl for x in t]
        ref = (0, 1, 0) if abs(t[1]) < 0.9 else (1, 0, 0)
        u = (t[1] * ref[2] - t[2] * ref[1], t[2] * ref[0] - t[0] * ref[2], t[0] * ref[1] - t[1] * ref[0])
        ul = math.sqrt(sum(x * x for x in u))
        u = [x / ul for x in u]
        v = (t[1] * u[2] - t[2] * u[1], t[2] * u[0] - t[0] * u[2], t[0] * u[1] - t[1] * u[0])
        for i in range(segs):
            a2 = 2 * math.pi * i / segs
            verts.append(tuple(p[j] + r * (math.cos(a2) * u[j] + math.sin(a2) * v[j]) for j in range(3)))
    faces = [(k * segs + i, k * segs + (i + 1) % segs, (k + 1) * segs + (i + 1) % segs, (k + 1) * segs + i) for k in range(n - 1) for i in range(segs)]
    return m.add(verts, faces)


# ------------------------------------------------------------------------------ the shared fuze
def fuze(top, body_r, lever_to, body_profile=None):
    """The fuze on a body whose top sits at y=top; the spoon runs down the +X side to y=lever_to, hugging body_profile(y) -> radius."""
    prof = body_profile or (lambda y: body_r)
    ms = [
        ('fuze_neck', yring(0.0098, 0.004, top - 0.002, top + 0.005, 'fuze', teeth=24, depth=0.06)),
        ('fuze_body', ycyl([(0, top + 0.004), (0.0088, top + 0.004), (0.0090, top + 0.006), (0.0090, top + 0.019), (0.0082, top + 0.0215), (0.0062, top + 0.023), (0, top + 0.023)], 'fuze')),
        ('fuze_striker', box(0.010, 0.013, 0.012, 'fuze', bevel=0.0016).xf(None, (0.0065, top + 0.0165, 0))),
        ('fuze_rivet', ycyl([(0, top + 0.0225), (0.0032, top + 0.0225), (0.0034, top + 0.0245), (0.002, top + 0.0255), (0, top + 0.0255)], 'pin', segs=16)),
    ]
    # spoon: from behind the rivet over the top, down the striker's face, flaring out over the shoulder and down the body
    y_top = top + 0.0262
    path = [(-0.0035, y_top, 0), (0.004, y_top + 0.0004, 0), (0.0105, y_top - 0.0008, 0), (0.0128, y_top - 0.004, 0), (0.0130, top + 0.012, 0), (0.0132, top + 0.004, 0)]
    steps = 12
    for i in range(1, steps + 1):
        y = top + 0.004 - (top + 0.004 - lever_to) * i / steps
        r = max(prof(y) + 0.0016, 0.0133)
        path.append((r, y, 0))
    path.append((path[-1][0] + 0.0025, lever_to - 0.004, 0))
    ms.append(('spoon', sweep(path, 0.0068, 0.0006, 'spoon')))
    ms.append(('spoon_rib', sweep(path[3:-1], 0.0016, 0.0009, 'spoon').xf(None, (0.0005, 0, 0))))
    # safety pin through the fuze along Z, split legs bent back on the far side, pull ring on the near side hanging clear of the body
    py = top + 0.0135
    ms.append(('pin', rod([(0.0075, py, -0.0145), (0.0075, py, 0.0125)], 0.00095, 'pin')))
    ms.append(('pin_leg_a', rod([(0.0075, py, -0.0145), (0.0082, py + 0.003, -0.0175), (0.0086, py + 0.0075, -0.0182)], 0.0008, 'pin')))
    ms.append(('pin_leg_b', rod([(0.0075, py, -0.0145), (0.0066, py - 0.003, -0.0172), (0.0062, py - 0.0072, -0.0178)], 0.0008, 'pin')))
    ms.append(('pin_eye', torus(0.0026, 0.0008, 'pin', (0.0075, py, 0.0148), 'x', segs=16, tube=8)))
    ms.append(('pull_ring', torus(0.0118, 0.00115, 'pin', (0.0075, py - 0.0026 - 0.0118 * 0.62, 0.0148 + 0.0118 * 0.78), 'x', segs=28, tube=8)))
    return ms


# ------------------------------------------------------------------------------ bodies
def canister(r, y0, y1, mat, rim='steel'):
    """A rolled-rim can about +Y: rolled bead top and bottom, a shallow top plate."""
    return [
        ('body', ycyl([(0, y0 + 0.0009), (r - 0.0015, y0 + 0.0009), (r, y0 + 0.004), (r, y1 - 0.004), (r - 0.0015, y1 - 0.002), (0, y1 - 0.002)], mat)),
        ('rim_bottom', yring(r + 0.0011, r - 0.004, y0, y0 + 0.0045, rim, c=0.0012)),
        ('rim_top', yring(r + 0.0011, r - 0.004, y1 - 0.0045, y1, rim, c=0.0012)),
        ('top_plate', ycyl([(0, y1 - 0.0028), (r - 0.0036, y1 - 0.0028), (r - 0.0032, y1 - 0.0012), (0, y1 - 0.0012)], rim)),
        ('seam', box(0.0016, y1 - y0 - 0.01, 0.003, mat, bevel=0.0005, seg=1).xf(None, (-r - 0.0002, (y0 + y1) / 2, 0))),
    ]


def holes_on_top(r_ring, y, n, hole_r, mat='core', phase=0.0):
    ms = []
    for i in range(n):
        a = 2 * math.pi * i / n + phase
        ms.append(('vent_%d' % i, ycyl([(0, y), (hole_r, y), (hole_r, y + 0.0006), (0, y + 0.0006)], mat, segs=12, at=(r_ring * math.cos(a), 0, r_ring * math.sin(a)))))
    return ms


def smoke_grenade():
    r, y0, y1 = 0.0305, -0.058, 0.052
    ms = canister(r, y0, y1, 'od')
    ms.append(('band', yring(r + 0.0004, r - 0.002, y1 - 0.024, y1 - 0.011, 'yellow', c=0.0003)))
    ms.append(('band_low', yring(r + 0.0004, r - 0.002, y0 + 0.010, y0 + 0.016, 'yellow', c=0.0003)))
    ms += holes_on_top(0.019, y1 - 0.0013, 4, 0.0035, phase=math.pi / 4)
    ms += fuze(y1 - 0.0012, r, y0 + 0.026)
    return ms


def incendiary_grenade():
    r, y0, y1 = 0.0265, -0.064, 0.058
    ms = canister(r, y0, y1, 'red')
    for k, yc in enumerate((y1 - 0.016, y0 + 0.016)):
        ms.append(('band_%d' % k, yring(r + 0.0006, r - 0.002, yc - 0.0055, yc + 0.0055, 'grip', c=0.0004)))
        for s in (-1, 1):
            ms.append(('rib_%d_%d' % (k, s), yring(r + 0.0013, r - 0.001, yc + s * 0.0075 - 0.0009, yc + s * 0.0075 + 0.0009, 'steel', c=0.0004)))
    ms += holes_on_top(0.0145, y1 - 0.0013, 6, 0.0022)
    ms += fuze(y1 - 0.0012, r, y0 + 0.03)
    return ms


def flash_grenade():
    r, y0, y1 = 0.0195, -0.050, 0.046
    ms = [('core', ycyl([(0, y0 + 0.004), (r - 0.0035, y0 + 0.004), (r - 0.0035, y1 - 0.004), (0, y1 - 0.004)], 'core'))]
    rows = [(-0.040, -0.016), (-0.012, 0.012), (0.016, 0.034)]
    bands = [(y0, rows[0][0]), (rows[0][1], rows[1][0]), (rows[1][1], rows[2][0]), (rows[2][1], y1)]
    for k, (a, b) in enumerate(bands):
        ms.append(('ring_%d' % k, yring(r, r - 0.0028, a, b, 'steel', c=0.0007)))
    nb = 8
    for k, (a, b) in enumerate(rows):
        for i in range(nb):
            ang = 2 * math.pi * (i + 0.5 * (k % 2)) / nb
            bar = box(0.0068, b - a + 0.001, 0.0028, 'steel', bevel=0.0006, seg=1)
            bar.xf([('y', -math.degrees(ang) + 90)], (0, 0, 0))
            bar.xf(None, ((r - 0.0014) * math.cos(ang), (a + b) / 2, (r - 0.0014) * math.sin(ang)))
            ms.append(('bar_%d_%d' % (k, i), bar))
    ms.append(('band', yring(r + 0.0006, r - 0.001, y1 - 0.011, y1 - 0.003, 'band_blue', c=0.0004)))
    ms.append(('cap_bottom', ycyl([(0, y0 - 0.0025), (r - 0.002, y0 - 0.0025), (r + 0.0004, y0 - 0.0008), (r + 0.0004, y0 + 0.003), (0, y0 + 0.003)], 'steel')))
    ms.append(('cap_top', ycyl([(0, y1 - 0.003), (r + 0.0004, y1 - 0.003), (r + 0.0004, y1 + 0.0008), (r - 0.003, y1 + 0.0026), (0, y1 + 0.0026)], 'steel')))
    ms += fuze(y1 + 0.0024, r, y0 + 0.022)
    return ms


def round_body(R, c=0.0, stretch=1.04):
    """A round steel body on Y (slightly tall, the lower half a touch slimmer): its lathe profile, its fuze-well top and its radius at a height."""
    prof = [(0, c - R)]
    for i in range(1, 24):
        th = math.pi * i / 24
        prof.append((R * math.sin(th) * (1.0 if th > math.pi / 2 else 0.97), c - R * math.cos(th) * stretch))
    top = c + R * stretch - 0.0035
    prof.append((0.0105, top - 0.0005))
    prof.append((0.0098, top))
    prof.append((0, top))
    return prof, top, lambda y: R * math.sqrt(max(0.0, 1 - ((y - c) / (R * stretch)) ** 2))


def frag_grenade():
    """The frag: a round olive steel body with its seam, a yellow filler band under the fuze, the spoon and pin."""
    R, c = 0.032, 0.0
    prof, top, body_r = round_body(R, c)
    ms = [('body', ycyl(prof, 'od'))]
    ms.append(('seam', yring(R + 0.0009, R - 0.003, c - 0.0013, c + 0.0013, 'steel', c=0.0005)))
    yb = c + R * 0.62  # the band sits on the shoulder, a ring hugging the curve
    ms.append(('band', yring(body_r(yb) + 0.0006, body_r(yb + 0.004) - 0.002, yb, yb + 0.004, 'yellow', c=0.0003)))
    ms.append(('base_ring', yring(0.0095, 0.004, c - R * 1.0 - 0.0006, c - R * 0.96, 'steel', c=0.0003)))
    ms += fuze(top, 0.012, c + 0.004, body_profile=body_r)
    return ms


def frag_grenade_alt():
    """The sticky: a round steel body, the lower half under a knobbed adhesive pad."""
    R, c = 0.031, 0.0
    prof, top, body_r = round_body(R, c)
    ms = [('body', ycyl(prof, 'od'))]
    ms.append(('seam', yring(R + 0.0009, R - 0.003, c - 0.0013, c + 0.0013, 'steel', c=0.0005)))
    pad = [(0, c - R * 1.04 - 0.0042)]
    for i in range(1, 12):
        th = (math.pi * 0.46) * i / 11
        pad.append(((R + 0.0032) * math.sin(th), c - (R * 1.04 + 0.0042) * math.cos(th)))
    pad.append((R + 0.0006, c - 0.0045))
    pad.append((R - 0.003, c - 0.0045))
    ms.append(('pad', ycyl(pad, 'tack', segs=SEG, teeth=10, depth=0.03)))
    k = 0
    for row, (th, n) in enumerate(((0.22, 6), (0.62, 11), (1.0, 14), (1.3, 16))):
        for i in range(n):
            a = 2 * math.pi * (i + 0.5 * (row % 2)) / n
            rr = (R + 0.0032) * math.sin(th)
            y = c - (R * 1.04 + 0.0042) * math.cos(th)
            knob = ycyl([(0, -0.001), (0.0026, -0.001), (0.0024, 0.0012), (0.0012, 0.0021), (0, 0.0024)], 'tack', segs=8)
            knob.xf([('z', 90 + math.degrees(th)), ('y', -math.degrees(a))], (rr * math.cos(a), y, rr * math.sin(a)))
            ms.append(('knob_%d' % k, knob))
            k += 1
    ms += fuze(top, 0.012, c + 0.006, body_profile=body_r)
    return ms


# ------------------------------------------------------------------------------ knife
KNIFE_FROM = (0.0, -0.083, 0.052)  # the pommel end of the shipped knife's axis (grip_socket and the view hold were tuned on it)
KNIFE_TILT = -29.8                 # degrees about X: the axis leans from +Y toward -Z
KNIFE_FLIP = 180.0                 # degrees about the blade's own axis: the edge on the side the slash leads with
BLADE_W, BLADE_T = 0.037, 0.0062   # a real fighting knife's blade: 37 mm deep, a 6 mm spine (thin enough to vanish edge-on otherwise)


def blade(y0, length, spine_t, width):
    """Clip-point blade along +Y in the YZ plane, edge at -Z, spine at +Z: stations of (spine z, grind z, edge z, thickness)."""
    st = []
    n = 26
    for i in range(n + 1):
        u = i / n
        y = y0 + length * u
        edge = -width * (0.52 if u < 0.06 else 0.55 * (1 - max(0.0, (u - 0.62) / 0.38) ** 1.7))
        if u > 0.62:  # clip: the spine drops in a straight-ish concave line to the tip
            v = (u - 0.62) / 0.38
            spine = width * 0.45 * (1 - v) - width * 0.08 * math.sin(math.pi * v) + edge * v * 0.0
        else:
            spine = width * 0.45
        tip = max(0.0, (u - 0.62) / 0.38)
        spine = max(spine, edge + 0.0006)
        grind = edge + (spine - edge) * 0.58
        t = spine_t * (1 - 0.25 * u) * (1 - tip ** 2 * 0.85)
        if i == n:
            spine = edge = grind = edge * 0.2
            t = 0.0
        st.append((y, spine, grind, edge, t))
    m = Mesh('blade')
    verts, faces = [], []
    for (y, sp, gr, ed, t) in st:
        h = t / 2
        swedge = 0.6 * h if (y - y0) / length > 0.66 else h  # the false-edge bevel on the clip
        verts += [(h, y, gr), (swedge, y, sp), (-swedge, y, sp), (-h, y, gr), (0.0, y, ed)]
    for k in range(len(st) - 1):
        for e in range(5):
            e2 = (e + 1) % 5
            faces.append((k * 5 + e, k * 5 + e2, (k + 1) * 5 + e2, (k + 1) * 5 + e))
    faces.append((4, 3, 2, 1, 0))
    m.add(verts, faces)
    return m


def combat_knife():
    pommel_h, grip_l, guard_h, blade_l = 0.014, 0.112, 0.008, 0.188
    ms = []
    y = 0.0
    ms.append(('pommel', ycyl([(0, 0.0), (0.0105, 0.0), (0.0135, 0.003), (0.0135, 0.010), (0.0115, pommel_h), (0, pommel_h)], 'steel', segs=24)))
    ms.append(('lanyard_hole', torus(0.0034, 0.0011, 'core', (0, 0.0065, 0), 'x', segs=14, tube=6).xf(None, (0.0, 0.0, 0.0))))
    y = pommel_h
    prof = [(0.0105, y)]
    n = 30
    for i in range(1, n):
        u = i / n
        groove = 0.0012 * max(0.0, math.sin(math.pi * 4 * (u - 0.08))) if u > 0.08 else 0.0
        bulge = 0.0012 * math.sin(math.pi * u)
        prof.append((0.0118 + bulge - groove, y + grip_l * u))
    prof.append((0.0112, y + grip_l))
    grip = ycyl([(0, y)] + prof + [(0, y + grip_l)], 'grip', segs=32, teeth=0)
    grip.v = [(p[0] * 0.78, p[1], p[2] * 1.12) for p in grip.v]  # oval: narrow across the blade's flat
    ms.append(('grip', grip))
    for i in range(9):
        yy = y + 0.010 + i * (grip_l - 0.02) / 8
        rib = yring(0.0124 + 0.0012 * math.sin(math.pi * (yy - y) / grip_l), 0.009, yy - 0.0009, yy + 0.0009, 'grip', segs=24, c=0.0004)
        rib.v = [(p[0] * 0.78, p[1], p[2] * 1.12) for p in rib.v]
        ms.append(('grip_rib_%d' % i, rib))
    y += grip_l
    ms.append(('ferrule', ycyl([(0, y - 0.002), (0.0118, y - 0.002), (0.0122, y + 0.001), (0, y + 0.001)], 'steel', segs=24)))
    ms[-1][1].v = [(p[0] * 0.8, p[1], p[2] * 1.1) for p in ms[-1][1].v]
    ms.append(('guard', box(0.010, guard_h, 0.060, 'steel', bevel=0.0018).xf(None, (0, y + guard_h / 2, 0.002))))
    for s in (-1, 1):
        ms.append(('guard_tip_%d' % (s > 0), ycyl([(0, -0.004), (0.0052, -0.004), (0.0058, 0.0), (0.0052, 0.004), (0, 0.004)], 'steel', segs=16).xf([('x', 90)], (0, y + guard_h / 2, 0.002 + s * 0.030))))
    y += guard_h
    ms.append(('ricasso', box(BLADE_T, 0.012, BLADE_W, 'blade', bevel=0.0008).xf(None, (0, y + 0.006, 0.0005))))
    ms.append(('blade', blade(y + 0.0115, blade_l - 0.0115, BLADE_T, BLADE_W)))
    for k, s in (('a', 1), ('b', -1)):  # a fuller ground into each flat, just under the spine
        ms.append(('fuller_' + k, box(0.0008, blade_l * 0.48, 0.0055, 'core', bevel=0.0003, seg=1).xf(None, (s * (BLADE_T / 2 - 0.0006), y + 0.018 + blade_l * 0.24, 0.0078))))
    for _, m in ms:
        m.xf([('y', KNIFE_FLIP), ('x', KNIFE_TILT)], KNIFE_FROM)
    return ms


MODELS = {'flash_grenade': flash_grenade, 'smoke_grenade': smoke_grenade, 'incendiary_grenade': incendiary_grenade,
          'frag_grenade': frag_grenade, 'frag_grenade_alt': frag_grenade_alt, 'combat_knife': combat_knife}


def main():
    args = sys.argv[sys.argv.index('--') + 1:]
    out_dir, only = args[0], args[1:]
    os.makedirs(out_dir, exist_ok=True)
    for name, fn in MODELS.items():
        if only and name not in only:
            continue
        build(name, fn(), out_dir)


main()
