"""Models the small parts of this pack (the 11 attachments, the four rounds, the ammo box) as source GLBs for the shared texture bake.
Run: blender -b -P tools/build_small_parts.py -- <out dir> [<name>...]   (no names: all)
The attachments keep the layout of tools/make_attachments.gd PARTS (read from that file, so the sockets, optic lines and `*_glass` meshes stay
where the game expects them); each part is rebuilt as a bevelled box or a chamfered lathe at 32 segments, then dressed: picatinny cross bars on
rails, hex screws on mounts, knurled bands and dials, turret caps, seam rings on long tubes. The rounds and the ammo box are modelled here from
scratch (case, primer, bullet ogive, cannelure; a stamped can with ribs, lid gasket, latches, hinge, handle, rivets).
Output: <out>/<name>.glb for every part (attachments by id, round_*, ammo_box). Textures come from addons/gs_weapon/tools/texbake/tex_pipeline.sh.
import bpy, bmesh, sys, os, re, math

HERE = os.path.dirname(os.path.abspath(__file__))
SEG = 32
ROUND_SEG = 80
MATS = {  # name -> (base colour, metallic, roughness, extra)
    'metal': ((0.30, 0.30, 0.32), 0.4, 0.45), 'dark': ((0.045, 0.045, 0.05), 0.0, 0.7), 'bore': ((0.0, 0.0, 0.0), 0.0, 1.0),
    'polymer': ((0.16, 0.15, 0.13), 0.0, 0.75), 'practice': ((0.95, 0.42, 0.05), 0.0, 0.55),
    'brass': ((0.56, 0.38, 0.12), 0.9, 0.35), 'copper': ((0.50, 0.22, 0.10), 0.8, 0.4), 'nickel': ((0.62, 0.62, 0.64), 0.9, 0.3),
    'hull': ((0.55, 0.05, 0.03), 0.0, 0.5), 'tip': ((0.03, 0.03, 0.035), 0.0, 0.5), 'olive': ((0.14, 0.17, 0.08), 0.2, 0.6),
    'lens_glass': ((0.30, 0.50, 0.55), 0.0, 0.03), 'reticle_glass': ((1.0, 0.08, 0.04), 0.0, 0.5), 'laser_glass': ((1.0, 0.1, 0.05), 0.0, 0.5),
}
ALIAS = {'glass': 'lens_glass', 'reticle': 'reticle_glass', 'laser': 'laser_glass'}


def G(p):
    """Godot space (x right, y up, -z forward) to Blender space."""
    return (p[0], -p[2], p[1])


def rot(p, axis, deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    x, y, z = p
    if axis == 'x':
        return (x, y * c - z * s, y * s + z * c)
    if axis == 'y':
        return (x * c + z * s, y, -x * s + z * c)
    return (x * c - y * s, x * s + y * c, z)


class Mesh:
    """Vertices and faces in Godot space, one material."""
    def __init__(s, mat):
        s.mat, s.v, s.f = mat, [], []

    def add(s, verts, faces):
        o = len(s.v)
        s.v += verts
        s.f += [tuple(i + o for i in f) for f in faces]
        return s

    def xf(s, rotation=None, at=(0, 0, 0)):
        v = s.v
        if rotation:
            for ax, d in rotation:
                v = [rot(p, ax, d) for p in v]
        s.v = [(p[0] + at[0], p[1] + at[1], p[2] + at[2]) for p in v]
        return s


def lathe(profile, mat, segs=SEG, axis='z', closed=False, teeth=0, depth=0.0, phase=0.0):
    """Profile [(r, t)...] about an axis (t along it). Open profiles with r == 0 at an end are capped to a point; closed ones wrap (a hollow ring).
    teeth/depth knurl the surface: every other tooth sits `depth` (fraction of r) lower."""
    m = Mesh(mat)
    n = len(profile)
    verts, faces = [], []
    for k, (r, t) in enumerate(profile):
        for i in range(segs):
            a = 2 * math.pi * i / segs + phase
            rr = r
            if teeth and r > 0:
                rr = r * (1.0 - depth * (0.5 + 0.5 * math.cos(a * teeth)) ** 0.6)
            if axis == 'z':
                verts.append((rr * math.cos(a), rr * math.sin(a), t))
            else:
                verts.append((rr * math.cos(a), t, rr * math.sin(a)))
    rings = n if not closed else n
    for k in range(rings if closed else n - 1):
        k2 = (k + 1) % n
        for i in range(segs):
            i2 = (i + 1) % segs
            a, b, c, d = k * segs + i, k * segs + i2, k2 * segs + i2, k2 * segs + i
            ra, rb = profile[k][0], profile[k2][0]
            if ra == 0 and rb == 0:
                continue
            if ra == 0:
                faces.append((a, c, d) if axis == 'z' else (a, d, c))
            elif rb == 0:
                faces.append((a, b, c) if axis == 'z' else (a, c, b))
            else:
                faces.append((a, b, c, d) if axis == 'z' else (a, d, c, b))
    # the faces above wind one way for +t growing; flip all when the profile's outside faces inward
    m.add(verts, faces)
    return m


def chamfered_tube(r_rear, r_front, length, mat, c=None, segs=SEG, teeth=0, depth=0.0):
    """A solid tube along Z (rear at +Z): chamfered at both ends so it catches light on its rim. Front at -Z."""
    h = length / 2
    rf = r_front if r_front > 0 else r_rear
    c = min(c if c is not None else 0.0011, 0.2 * min(r_rear, rf), 0.3 * h)
    prof = [(0, h), (r_rear - c, h), (r_rear, h - c), (rf, -h + c), (rf - c, -h), (0, -h)]
    # profile runs rear to front: winding for the outside to face out
    return lathe(prof, mat, segs, 'z', teeth=teeth, depth=depth)


def chamfered_ring(r_out, length, r_in, mat, c=None, segs=SEG, teeth=0, depth=0.0):
    h = length / 2
    c = min(c if c is not None else 0.0009, 0.25 * (r_out - r_in), 0.3 * h)
    prof = [(r_in + c, h), (r_out - c, h), (r_out, h - c), (r_out, -h + c), (r_out - c, -h), (r_in + c, -h), (r_in, -h + c), (r_in, h - c)]
    return lathe(prof, mat, segs, 'z', closed=True, teeth=teeth, depth=depth)


def box(sx, sy, sz, mat, bevel=None, seg=2):
    b = bmesh.new()
    bmesh.ops.create_cube(b, size=1.0)
    for v in b.verts:
        v.co.x *= sx
        v.co.y *= sy
        v.co.z *= sz
    bv = bevel if bevel is not None else min(0.0012, 0.2 * min(sx, sy, sz))
    if bv > 0.0002:
        bmesh.ops.bevel(b, geom=list(b.edges), offset=bv, offset_type='OFFSET', segments=seg, profile=0.5, affect='EDGES')
    b.verts.ensure_lookup_table()
    verts = [tuple(v.co) for v in b.verts]
    faces = [tuple(v.index for v in f.verts) for f in b.faces]
    b.free()
    return Mesh(mat).add(verts, faces)


def screw(at, axis_dir, r, mat='nickel', head=0.0012):
    """A hex head with a domed top, seated on a face; axis_dir is a unit axis of Godot space the head points along."""
    prof = [(0, head * 1.0), (r * 0.62, head * 0.95), (r * 0.95, head * 0.55), (r, 0.0), (r, -0.0006), (0, -0.0006)]
    m = lathe(prof, mat, 6, 'z', phase=0.2)
    d = tuple(int(round(x)) for x in axis_dir)
    if d == (1, 0, 0):
        m.xf([('y', 90)], at)
    elif d == (-1, 0, 0):
        m.xf([('y', -90)], at)
    elif d == (0, 1, 0):
        m.xf([('x', -90)], at)
    elif d == (0, -1, 0):
        m.xf([('x', 90)], at)
    elif d == (0, 0, -1):
        m.xf([('y', 180)], at)
    else:
        m.xf(None, at)
    return m


# ------------------------------------------------------------------------------ attachments from make_attachments.gd
def read_parts():
    src = open(os.path.join(HERE, 'make_attachments.gd')).read()
    body = src[src.index('const PARTS := {'):]
    body = body[:body.index('\n}\n')]
    out, cur = {}, None
    for line in body.splitlines():
        m = re.match(r'\t"(\w+)": \[', line)
        if m:
            cur = out.setdefault(m.group(1), [])
            continue
        if cur is not None and line.strip().startswith('["'):
            txt = line.strip().rstrip(',').replace('Vector3', '')
            cur.append(eval(txt))
    return out


def attachment(parts):
    ms = []
    for p in parts:
        name, kind, size, pos, mat = p[:5]
        turn = p[5] if len(p) > 5 else None
        mat = ALIAS.get(mat, mat)
        rotation = None
        if turn is not None and any(turn):
            nz = [(a, d) for a, d in zip('xyz', turn) if d]
            assert len(nz) == 1, name
            rotation = nz
        dark_band = mat == 'dark' and kind in ('ring', 'tube') and size[1] <= 0.014 and size[0] >= 0.0105
        knurl = dict(teeth=36, depth=0.045) if dark_band and not name.startswith('eye') else {}
        glass = mat.endswith('_glass')
        segs = 32 if glass else SEG
        if kind == 'box':
            m = box(size[0], size[1], size[2], mat)
        elif kind == 'tube':
            if glass or name in ('bore', 'emitter', 'reticle', 'face'):
                m = chamfered_tube(size[0], size[2], size[1], mat, c=0.0, segs=segs)
            else:
                m = chamfered_tube(size[0], size[2], size[1], mat, segs=segs, **knurl)
        else:
            m = chamfered_ring(size[0], size[1], size[2], mat, segs=SEG, **knurl)
        m.name = name
        m.xf(rotation, pos)
        ms.append((name, m))
        # ---- dressing
        if kind == 'box' and name == 'rail' and not rotation:
            sx, sy, sz = size
            n = int((sz - 0.008) / 0.0072)
            for i in range(n):
                z = pos[2] - (n - 1) * 0.0072 / 2 + i * 0.0072
                for sgn in (-1, 1):
                    b = box(0.0042, 0.0013, 0.0034, 'dark', bevel=0.0004, seg=1).xf(None, (pos[0] + sgn * (sx / 2 - 0.0019), pos[1] + sy / 2 + 0.0004, z))
                    ms.append(('%s_bar_%d_%d' % (name, i, sgn), b))
        elif kind == 'box' and not rotation and mat in ('metal', 'polymer') and size[0] >= 0.006 and max(size[1], size[2]) >= 0.020 and not name.startswith(('rib', 'port', 'extension')):
            sx, sy, sz = size
            along = 2 if sz >= sy else 1
            L = size[along]
            other = size[3 - along]
            rs = max(0.0011, min(0.0022, 0.3 * other))
            for sgn in (-1, 1):
                for sgn2 in (-1, 1):
                    off = [0.0, 0.0, 0.0]
                    off[along] = sgn2 * 0.3 * L
                    at = (pos[0] + sx / 2, pos[1] + off[1], pos[2] + off[2])
                    ms.append(('%s_screw' % name, screw(at, (1, 0, 0), rs)))
                    break
                break
            if sx >= 0.014:  # a clamped mount: the far side too
                for sgn2 in (-1, 1):
                    off = [0.0, 0.0, 0.0]
                    off[along] = sgn2 * 0.3 * L
                    ms.append(('%s_screw' % name, screw((pos[0] - sx / 2, pos[1] + off[1], pos[2] + off[2]), (-1, 0, 0), rs)))
        if kind == 'tube' and name.startswith('turret') and not glass:
            r0 = size[0]
            cap = chamfered_ring(r0 * 1.32, 0.0026, r0 * 0.5, 'dark', segs=SEG, teeth=24, depth=0.06)
            if rotation:
                # tube lies along the turned axis; the turret's outer end is its +Z end turned
                top = rot((0, 0, size[1] / 2 + 0.0004), rotation[0][0], rotation[0][1])
            else:
                top = (0, 0, size[1] / 2 + 0.0004)
            cap.xf(rotation, (pos[0] + top[0], pos[1] + top[1], pos[2] + top[2]))
            ms.append((name + '_cap', cap))
        if kind in ('tube', 'ring') and mat == 'metal' and size[1] >= 0.05 and size[0] >= 0.012 and not rotation and not glass:
            for f in (0.28, 0.72):
                z = pos[2] + size[1] / 2 - size[1] * f
                seam = chamfered_ring(size[0] * 1.025, 0.0016, size[0] * 0.9, 'dark', c=0.0005)
                seam.xf(None, (pos[0], pos[1], z))
                ms.append((name + '_seam', seam))
    return ms


# ------------------------------------------------------------------------------ rounds
def case_bottle(y0, rim_r, body_r, body_top, shoulder_top, neck_r, neck_top, mat='brass', extractor=True):
    """A cartridge case about Y, base at y0: base rebate, extractor groove, tapered body, shoulder, neck with a thin lip."""
    p = []
    p.append((0.0, y0 + 0.00025))
    p.append((rim_r * 0.52, y0 + 0.00025))      # primer pocket floor (recessed ring)
    p.append((rim_r * 0.60, y0 + 0.0))
    p.append((rim_r - 0.0003, y0))
    p.append((rim_r, y0 + 0.0003))
    p.append((rim_r, y0 + 0.0011))
    if extractor:
        p.append((body_r * 0.88, y0 + 0.0013))  # extractor groove
        p.append((body_r * 0.88, y0 + 0.0019))
        p.append((body_r, y0 + 0.0022))
    else:
        p.append((body_r, y0 + 0.0012))
    p.append((body_r * 0.965, body_top))
    if shoulder_top > body_top:
        p.append((neck_r + 0.0003, shoulder_top))
    p.append((neck_r + 0.0001, neck_top - 0.0003))
    p.append((neck_r + 0.00005, neck_top))
    return lathe(p, mat, ROUND_SEG, 'y', teeth=0)


def bullet(y0, y1, r, nose_r, boat=0.0, mat='copper', tip_from=None, cannelure=None):
    """Ogive bullet about Y from y0 (base) to y1 (nose), radius r; a flat meplat of nose_r, optional boat-tail and cannelure groove."""
    L = y1 - y0
    p = [(0.0, y0), (r * (1 - boat), y0)] if boat else [(0.0, y0), (r * 0.98, y0)]
    if boat:
        p.append((r, y0 + 0.0012))
    else:
        p.append((r, y0 + 0.0003))
    cyl_top = y0 + L * 0.46
    if cannelure is not None:
        p += [(r, cannelure - 0.0006), (r * 0.9, cannelure - 0.0002), (r * 0.9, cannelure + 0.0002), (r, cannelure + 0.0006)]
    p.append((r, cyl_top))
    steps = 9
    for k in range(1, steps + 1):
        t = k / steps
        rr = nose_r + (r - nose_r) * (1 - t ** 1.6) ** 0.62 if nose_r < r else r
        p.append((rr, cyl_top + (y1 - cyl_top) * t))
    p.append((0.0, y1))
    return lathe(p, mat, ROUND_SEG, 'y')


def primer(y0, r, mat='nickel'):
    return lathe([(0, y0 - 0.00015), (r, y0 - 0.00015), (r, y0 + 0.0002), (0, y0 + 0.0003)], mat, 32, 'y')


def round_model(name):
    ms = []
    if name == 'round_pistol':
        y0 = -0.0082
        ms.append(('casing', case_bottle(y0, 0.0037, 0.0034, 0.0030, 0.0030, 0.0033, 0.0030, extractor=True)))
        ms.append(('primer', primer(y0 + 0.0002, 0.0017)))
        ms.append(('bullet', bullet(0.0014, 0.0130, 0.0033, 0.0014, cannelure=0.0021)))
    elif name == 'round_rifle':
        y0 = -0.0084
        ms.append(('casing', case_bottle(y0, 0.0037, 0.0036, 0.0010, 0.0036, 0.0023, 0.0072, extractor=True)))
        ms.append(('primer', primer(y0 + 0.0002, 0.0016)))
        ms.append(('bullet', bullet(0.0030, 0.0184, 0.0022, 0.0003, mat='copper', tip_from=0.0150, cannelure=0.0046)))
    elif name == 'round_sniper':
        y0 = -0.0158
        ms.append(('casing', case_bottle(y0, 0.0036, 0.0035, -0.0010, 0.0090, 0.0027, 0.0140, extractor=True)))
        ms.append(('primer', primer(y0 + 0.0002, 0.0016)))
        ms.append(('bullet', bullet(0.0100, 0.0282, 0.0027, 0.0003, boat=0.12, mat='copper', cannelure=0.0150)))
        ms.append(('tip', lathe([(0.0003, 0.0282), (0.00135, 0.0252), (0.0017, 0.0230), (0.0, 0.0230)], 'tip', ROUND_SEG, 'y')))
    elif name == 'round_shell':
        y0 = -0.0174
        head = 0.0085
        ms.append(('head', lathe([(0, y0), (0.0050, y0), (0.0059, y0 + 0.0003), (0.0063, y0 + 0.0006), (0.0063, y0 + 0.0020), (0.0058, y0 + 0.0024), (0.0058, y0 + 0.0029), (0.0062, y0 + 0.0033),
                                  (0.0062, y0 + head - 0.0003), (0.0059, y0 + head), (0.0, y0 + head)], 'brass', ROUND_SEG, 'y')))
        ms.append(('primer', primer(y0 + 0.0002, 0.0024)))
        top = 0.0174
        ms.append(('hull', lathe([(0.0, y0 + head - 0.0005), (0.0059, y0 + head - 0.0005), (0.0060, y0 + head + 0.0002), (0.0060, top - 0.0030), (0.0055, top - 0.0016), (0.0045, top - 0.0004),
                                  (0.0036, top), (0.0, top - 0.0004)], 'hull', ROUND_SEG, "y", teeth=24, depth=0.03)))
        ms.append(('crimp', lathe([(0.0, top + 0.0001), (0.0034, top + 0.0001), (0.0034, top - 0.0003), (0.0, top - 0.0003)], 'tip', 12, 'y')))
        ms.append(('band', lathe([(0.0061, y0 + head), (0.0061, y0 + head + 0.0009), (0.0059, y0 + head + 0.0009), (0.0059, y0 + head)], 'copper', ROUND_SEG, 'y', closed=True)))
    return ms


# ------------------------------------------------------------------------------ ammo box (0.2294 x 0.1456 x 0.1224, long axis X, handle on the lid)
def ammo_box():
    ms = []
    W, D = 0.2294, 0.1224
    yb0, yb1, yl1 = -0.0551, 0.0450, 0.0735
    hb = yb1 - yb0
    ms.append(('body', box(W - 0.010, hb, D - 0.010, 'olive', bevel=0.004, seg=3).xf(None, (0, (yb0 + yb1) / 2, 0))))
    ms.append(('lid', box(W, yl1 - yb1 + 0.0015, D, 'olive', bevel=0.004, seg=3).xf(None, (0, (yb1 - 0.0015 + yl1) / 2, 0))))
    ms.append(('gasket', box(W - 0.006, 0.0045, D - 0.006, 'dark', bevel=0.0015, seg=2).xf(None, (0, yb1 - 0.0010, 0))))
    for sx in (-1, 1):
        ms.append(('foot', box(0.022, 0.006, D - 0.008, 'olive', bevel=0.0015).xf(None, (sx * 0.075, yb0 - 0.002, 0))))
    for side in (-1, 1):
        zf = side * (D / 2 - 0.005)
        for i in range(4):  # stamped stiffening ribs on both long faces
            x = -0.075 + i * 0.050
            ms.append(('rib', box(0.011, 0.060, 0.003, 'olive', bevel=0.0012).xf(None, (x, -0.0070, zf + side * 0.0010))))
        ms.append(('stencil', box(0.060, 0.022, 0.0008, 'tip', bevel=0.0).xf(None, (0.0, 0.0070, zf + side * 0.0030))))
        for sx in (-1, 1):  # latches on the lid seam
            x = sx * 0.078
            ms.append(('latch_plate', box(0.026, 0.020, 0.003, 'metal', bevel=0.001).xf(None, (x, yb1 - 0.0050, D / 2 * side + side * 0.0010))))
            ms.append(('latch_hook', box(0.014, 0.010, 0.004, 'metal', bevel=0.0012).xf(None, (x, yb1 + 0.0100, D / 2 * side + side * 0.0020))))
            ms.append(('rivet', screw((x - 0.009, yb1 - 0.0050, D / 2 * side + side * 0.0025), (0, 0, side), 0.0019)))
            ms.append(('rivet', screw((x + 0.009, yb1 - 0.0050, D / 2 * side + side * 0.0025), (0, 0, side), 0.0019)))
    for sx in (-1, 1):  # carry handle: bent bar on two brackets
        ms.append(('handle_bracket', box(0.014, 0.012, 0.030, 'metal', bevel=0.0012).xf(None, (sx * 0.044, yl1 + 0.0050, 0))))
        ms.append(('handle_post', chamfered_tube(0.0030, 0.0030, 0.0120, 'metal', segs=24).xf([('x', 90)], (sx * 0.044, yl1 + 0.0110, 0))))
    ms.append(('handle', chamfered_tube(0.0036, 0.0036, 0.088, 'dark', segs=32, teeth=16, depth=0.05).xf([('y', 90)], (0, yl1 + 0.0170, 0))))
    ms.append(('hinge', chamfered_tube(0.0040, 0.0040, W - 0.050, 'metal', segs=32).xf([('y', 90)], (0, yb1 + 0.0020, -(D / 2 + 0.0010)))))
    for sx in (-1, 1):
        ms.append(('hinge_knuckle', chamfered_tube(0.0048, 0.0048, 0.016, 'metal', segs=32).xf([('y', 90)], (sx * 0.060, yb1 + 0.0020, -(D / 2 + 0.0010)))))
    for sx in (-0.080, 0.0, 0.080):
        for sz in (-1, 1):
            ms.append(('lid_rivet', screw((sx, yl1, sz * 0.045), (0, 1, 0), 0.0019)))
    ms.append(('lid_ridge', box(0.150, 0.0020, 0.075, 'olive', bevel=0.0008).xf(None, (0, yl1 + 0.0003, 0))))
    return ms


# ------------------------------------------------------------------------------ blender side
def material(name):
    key = ALIAS.get(name, name)
    m = bpy.data.materials.get(key)
    if m:
        return m
    col, metal, rough = MATS[key]
    m = bpy.data.materials.new(key)
    m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = (*col, 1.0)
    b.inputs['Metallic'].default_value = metal
    b.inputs['Roughness'].default_value = rough
    if key == 'lens_glass':
        b.inputs['Alpha'].default_value = 0.22
        m.blend_method = 'BLEND'
        m.use_backface_culling = False
    if key in ('reticle_glass', 'laser_glass'):
        b.inputs['Emission Color'].default_value = (*col, 1.0)
        b.inputs['Emission Strength'].default_value = 6.0 if key == 'reticle_glass' else 4.0
        m.use_backface_culling = False
    return m


def build(name, parts, out_dir):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    tris = 0
    for pname, m in parts:
        verts = [G(p) for p in m.v]
        me = bpy.data.meshes.new(pname)
        me.from_pydata(verts, [], m.f)
        me.update()
        me.materials.append(material(m.mat))
        ob = bpy.data.objects.new(pname, me)
        bpy.context.scene.collection.objects.link(ob)
        bpy.context.view_layer.objects.active = ob
        ob.select_set(True)
        bpy.ops.object.shade_smooth()
        me.polygons.foreach_set('use_smooth', [True] * len(me.polygons))
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.00002)
        bm.to_mesh(me)
        bm.free()
        tris += sum(max(1, len(p.vertices) - 2) for p in me.polygons)
        # sharp edges where the surface turns more than 40 degrees: keeps boxes crisp, tubes smooth
        me.set_sharp_from_angle(angle=math.radians(40))
    bpy.ops.object.select_all(action='DESELECT')
    path = os.path.join(out_dir, name + '.glb')
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', export_yup=True, export_apply=False, export_materials='EXPORT', export_image_format='AUTO')
    print('build_small_parts: %s %d parts %d tris' % (name, len(parts), tris))


def main():
    args = sys.argv[sys.argv.index('--') + 1:]
    out_dir, only = args[0], args[1:]
    os.makedirs(out_dir, exist_ok=True)
    atts = read_parts()
    models = {}
    for k, v in atts.items():
        models[k] = lambda v=v: attachment(v)
    for r in ('round_pistol', 'round_rifle', 'round_sniper', 'round_shell'):
        models[r] = lambda r=r: round_model(r)
    models['ammo_box'] = ammo_box
    for name, fn in models.items():
        if only and name not in only:
            continue
        build(name, fn(), out_dir)


main()
