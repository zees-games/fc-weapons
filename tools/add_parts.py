"""Adds modelled detail parts to the shipped weapon GLBs in place (pure python + numpy, no Blender): minigun barrel clamps and bores, the launcher
venturi, the lmg belt and a smaller ammo box, rear sights on lmg, machine_pistol and carbine;
second pass (aw_parts_v2): the marksman's smooth scope, the drum_shotgun's green smudges off its steel; third pass (aw_parts_v3): the bullpup's red
dot in place of the tan block and a de-blotched 2k receiver albedo, the drum_shotgun's rebuilt sights, the machine_pistol's sights and slide
detail, the battle_rifle's Loop-subdivided stock, the quad launcher's modelled end cap. Parts are plain-material meshes named aw_part_*
(see glb_parts.py); the glb's asset.extras.aw_parts marks a model as done, so a second run does nothing.
Usage: python3 tools/add_parts.py [model ...]   (default: every model of every pass). Needs numpy; own geometry, no new licence."""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glb_parts as g

MODELS = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'addons', 'fc_weapons', 'assets', 'models')
TAG = 'aw_parts_v1'
TAG2 = 'aw_parts_v2'
TAG3 = 'aw_parts_v3'


def edit_mesh(j, b, node, fn):
    """fn(P (N,3) float64, in the mesh node's own frame, I (T,3) int) -> (P, I); appends new buffer views and repoints the accessors."""
    nd = next(n for n in j['nodes'] if n.get('name') == node)
    pr = j['meshes'][nd['mesh']]['primitives'][0]
    P = g.accessor(j, b, pr['attributes']['POSITION']).astype(np.float64)
    I = g.accessor(j, b, pr['indices']).reshape(-1, 3).astype(np.int64)
    P, I = fn(P, I)
    for key, arr, ct, tgt in (('POSITION', P.astype(np.float32), 5126, 34962), ('indices', I.astype(np.uint32).reshape(-1), 5125, 34963)):
        while len(b) % 4:
            b.append(0)
        data = arr.tobytes()
        j['bufferViews'].append({'buffer': 0, 'byteOffset': len(b), 'byteLength': len(data), 'target': tgt})
        b += data
        ai = pr['attributes'][key] if key == 'POSITION' else pr['indices']
        a = j['accessors'][ai]
        a['bufferView'] = len(j['bufferViews']) - 1
        a['byteOffset'] = 0
        a['componentType'] = ct
        a['count'] = len(arr) if key == 'POSITION' else int(arr.size)
        if key == 'POSITION':
            a['min'], a['max'] = P.min(0).tolist(), P.max(0).tolist()


def cut_world(j, b, node, pred):
    """Drops the triangles of a mesh node whose centroid, in the scene roots' frame, satisfies pred(C (T,3)) -> bool array."""
    m = g.node_world(j, next(i for i, n in enumerate(j['nodes']) if n.get('name') == node))

    def fn(P, I):
        C = P[I].mean(1) @ m[:3, :3].T + m[:3, 3]
        return P, I[~pred(C)]
    edit_mesh(j, b, node, fn)


def degreen_tris(j, b, node, pred, dilate=3):
    """Olive-green albedo texels under the triangles whose world centroid satisfies pred go grey at the same brightness (the source's
    green wear smudges on steel); the albedo is re-encoded in place. Returns the number of texels changed."""
    import io
    from PIL import Image, ImageDraw, ImageFilter
    i = next(k for k, n in enumerate(j['nodes']) if n.get('name') == node)
    m = g.node_world(j, i)
    pr = j['meshes'][j['nodes'][i]['mesh']]['primitives'][0]
    I = g.accessor(j, b, pr['indices']).reshape(-1, 3).astype(np.int64)
    P = g.accessor(j, b, pr['attributes']['POSITION']).astype(np.float64)
    uv = g.accessor(j, b, pr['attributes']['TEXCOORD_0']).astype(np.float64)
    C = P[I].mean(1) @ m[:3, :3].T + m[:3, 3]
    img = j['images'][j['textures'][j['materials'][pr['material']]['pbrMetallicRoughness']['baseColorTexture']['index']]['source']]
    bv = j['bufferViews'][img['bufferView']]
    im = Image.open(io.BytesIO(bytes(b[bv['byteOffset']:bv['byteOffset'] + bv['byteLength']]))).convert('RGB')
    w, h = im.size
    mask = Image.new('L', (w, h), 0)
    d = ImageDraw.Draw(mask)
    for t in I[pred(C)]:
        d.polygon([(float(u * w), float(v * h)) for u, v in uv[t] % 1.0], fill=255)
    mask = np.array(mask.filter(ImageFilter.MaxFilter(2 * dilate + 1))) > 0
    a = np.array(im).astype(np.float64)
    r, gg, bb = a[..., 0], a[..., 1], a[..., 2]
    green = mask & (gg > bb + 10) & (gg >= r - 4)
    lum = (0.299 * r + 0.587 * gg + 0.114 * bb)[green]
    a[green] = np.stack([lum * 0.97, lum, lum * 1.06], 1)   # the receiver's cool grey
    buf = io.BytesIO()
    Image.fromarray(a.clip(0, 255).astype(np.uint8)).save(buf, 'JPEG', quality=92)
    data = buf.getvalue()
    while len(b) % 4:
        b.append(0)
    j['bufferViews'].append({'buffer': 0, 'byteOffset': len(b), 'byteLength': len(data)})
    b += data
    img['bufferView'] = len(j['bufferViews']) - 1
    img['mimeType'] = 'image/jpeg'
    return int(green.sum())


def brown_tris(j, b, node):
    """Boolean per triangle: the albedo under its UV centroid is orange-brown (rust, belt, wood)."""
    import io
    from PIL import Image
    nd = next(n for n in j['nodes'] if n.get('name') == node)
    pr = j['meshes'][nd['mesh']]['primitives'][0]
    I = g.accessor(j, b, pr['indices']).reshape(-1, 3).astype(np.int64)
    uv = g.accessor(j, b, pr['attributes']['TEXCOORD_0']).astype(np.float64)[I].mean(1)
    ti = j['materials'][pr['material']]['pbrMetallicRoughness']['baseColorTexture']['index']
    bv = j['bufferViews'][j['images'][j['textures'][ti]['source']]['bufferView']]
    im = np.array(Image.open(io.BytesIO(bytes(b[bv['byteOffset']:bv['byteOffset'] + bv['byteLength']]))).convert('RGB')).astype(np.float64)
    h, w, _ = im.shape
    px = im[(uv[:, 1] % 1 * h).astype(int).clip(0, h - 1), (uv[:, 0] % 1 * w).astype(int).clip(0, w - 1)]
    return (px[:, 0] > px[:, 2] * 1.25) & (px[:, 0] > 60)


def mark(j, name, y=None):
    n = next((x for x in j['nodes'] if x.get('name') == name), None)
    if n and y is not None:
        t = n['translation']
        n['translation'] = [t[0], y, t[2]]


def sight_marks(j, y, rear_z, front_z):
    """Writes the `sight_rear` / `sight_front` marks (GSWeaponIronSight.from_marks) on the line y, for sights whose
    aperture sits below their own ears, where the model's highest point is not the line."""
    for name, z in (('sight_rear', rear_z), ('sight_front', front_z)):
        n = next((x for x in j['nodes'] if x.get('name') == name), None)
        if n is None:
            n = {'name': name}
            j['nodes'].append(n)
            j['scenes'][0]['nodes'].append(len(j['nodes']) - 1)
        n['translation'] = [0.0, y, z]


def rear_notch(p, mat, x, z, y0, h, width=0.026, gap=0.009, ear=0.004, depth=0.012):
    """Open rear sight: a base plate on y0 and two ears (the notch between them), top at y0 + h."""
    p.box(mat, (x, y0 + 0.0025, z), (width, 0.005, depth))
    for s in (-1, 1):
        p.box(mat, (x + s * (gap / 2 + ear / 2), y0 + h / 2, z), (ear, h, depth * 0.8))


def minigun(j, b, p):
    cy = 0.0245
    for z, ln in ((-0.40, 0.022), (-0.60, 0.018), (-0.738, 0.026)):
        p.cyl('part_steel', (0, cy, z), 0.122, 0.122, ln, 'z', 40, True, inner=0.094)
    for k in range(6):
        a = math.radians(30 + 60 * k)
        c = (0.078 * math.cos(a), cy + 0.078 * math.sin(a), -0.7675)
        p.cyl('part_black', c, 0.0155, 0.0155, 0.003, 'z', 16)
        p.cyl('part_steel', (c[0], c[1], -0.7655), 0.027, 0.027, 0.002, 'z', 16, True, inner=0.0165)
    for s in (-1, 1):  # clamp bolts
        p.cyl('part_blued', (s * 0.126, cy, -0.60), 0.008, 0.008, 0.016, 'x', 12)


def launcher(j, b, p):
    cy = -0.016
    p.cyl('part_blued', (0, cy, 0.475), 0.056, 0.092, 0.11, 'z', 40, False, inner=0.046)
    p.cyl('part_steel', (0, cy, 0.531), 0.094, 0.094, 0.008, 'z', 40, True, inner=0.082)
    p.cyl('part_black', (0, cy, 0.46), 0.046, 0.046, 0.004, 'z', 32)


def lmg(j, b, p):
    # the lmg mesh is in its own frame (x long axis, scene parent scales 1.05 and turns it); regions below are in that local frame
    brown = brown_tris(j, b, 'geometry_0')

    def fn(P, I):
        # the belt blobs are the brown-albedo triangles inside the feed volume; remove them and the facets sharing their vertices
        c = P[I].mean(1)
        box = np.all((c > (-0.1, -0.01, -0.125)) & (c < (0.01, 0.116, 0.125)), 1)
        hit = np.zeros(len(P), bool)
        hit[I[box & brown].reshape(-1)] = True
        kill = np.all((c > (-0.1, 0.0, -0.125)) & (c < (0.01, 0.1, 0.125)), 1) | (box & hit[I].any(1))
        return P, I[~kill]
    edit_mesh(j, b, 'geometry_0', fn)
    # belt in the scene frame: brass rounds (axis across the gun) with steel links, laid in the box and rising to the feed tray
    for y in (0.092, 0.108):
        for i in range(7):
            z = -0.275 + i * 0.0165
            p.cyl('part_brass', (0, y, z), 0.0085, 0.0085, 0.07, 'x', 12)
            p.cyl('part_steel', (0, y, z + 0.0082), 0.0035, 0.0035, 0.076, 'x', 6)
    # feed cover closes the opening left where the belt blobs were
    p.box('part_blued', (0, 0.205, -0.215), (0.086, 0.07, 0.125))
    p.box('part_steel', (0, 0.243, -0.215), (0.09, 0.008, 0.13))
    # rear sight: base plate and the two protective wings around the existing aperture
    p.box('part_blued', (0, 0.343, -0.232), (0.04, 0.006, 0.05))
    for s in (-1, 1):
        p.box('part_blued', (s * 0.019, 0.358, -0.232), (0.004, 0.032, 0.03))
    p.box('part_blued', (0, 0.372, -0.246), (0.042, 0.005, 0.006))


def machine_pistol(j, b, p):
    top = 0.168
    rear_notch(p, 'part_blued', 0, -0.02, top, 0.014, width=0.034, gap=0.011)
    p.box('part_blued', (0, top + 0.004, -0.202), (0.004, 0.008, 0.012))
    p.box('part_blued', (0, top + 0.0005, -0.202), (0.022, 0.003, 0.014))
    mark(j, 'sight_rear', top + 0.006)
    mark(j, 'sight_front', top + 0.006)


def carbine(j, b, p):
    rear_notch(p, 'part_blued', 0, -0.215, 0.079, 0.012, width=0.03, gap=0.009)


def marksman(j, b, p):
    """The source scope was an octagonal tube baked near-black; replace it with a smooth one (same axis: y 0.195, eyepiece at z 0)."""
    cy = 0.195
    cut_world(j, b, 'geometry_0', lambda C: (C[:, 1] > 0.145) & (C[:, 2] > -0.43) & (C[:, 2] < 0.01) & (np.abs(C[:, 0]) < 0.06))
    S = 48
    p.cyl('part_rubber', (0, cy, -0.0075), 0.0355, 0.036, 0.011, 'z', S, True, inner=0.029)   # eye cup (the game draws live glass at the ocular: aw_scope_glass.gd)
    p.cyl('part_scope', (0, cy, -0.0395), 0.0355, 0.0355, 0.053, 'z', S)                      # ocular housing
    p.cyl('part_scope', (0, cy, -0.0835), 0.0245, 0.0355, 0.035, 'z', S, False)               # ocular taper
    p.cyl('part_scope', (0, cy, -0.2), 0.0245, 0.0245, 0.2, 'z', S, False)                    # main tube
    p.cyl('part_scope', (0, cy, -0.19), 0.031, 0.031, 0.048, 'z', S)                         # turret saddle
    p.cyl('part_scope', (0, cy + 0.041, -0.19), 0.017, 0.017, 0.026, 'y', S)                 # elevation turret: its cap top is the
    p.cyl('part_steel', (0, cy + 0.0555, -0.19), 0.0155, 0.0155, 0.007, 'y', S)               # source's y 0.254, the rear top aim_in was set on
    p.cyl('part_scope', (0.041, cy, -0.19), 0.017, 0.017, 0.026, 'x', S)                     # windage turret
    p.cyl('part_steel', (0.0555, cy, -0.19), 0.0155, 0.0155, 0.007, 'x', S)
    p.cyl('part_scope', (-0.036, cy, -0.19), 0.013, 0.013, 0.014, 'x', S)                    # parallax knob
    p.cyl('part_scope', (0, cy, -0.33), 0.046, 0.0245, 0.06, 'z', S, False)                  # objective taper
    p.cyl('part_scope', (0, cy, -0.39), 0.046, 0.046, 0.06, 'z', S, False)                   # objective bell
    p.cyl('part_scope', (0, cy, -0.4205), 0.0475, 0.0475, 0.007, 'z', S, True, inner=0.04)   # objective lip
    p.cyl('part_glass', (0, cy, -0.418), 0.04, 0.04, 0.004, 'z', S)
    for z in (-0.12, -0.255):                                                                 # rings on their bases
        p.cyl('part_black', (0, cy, z), 0.0295, 0.0295, 0.018, 'z', S, True, inner=0.0245)
        p.box('part_black', (0, 0.145, z), (0.03, 0.05, 0.018))
        p.box('part_black', (0, 0.124, z), (0.036, 0.012, 0.024))
        p.cyl('part_steel', (0.019, 0.152, z), 0.0045, 0.0045, 0.006, 'x', 12)


def drum_shotgun(j, b, p):
    """Only the pistol grip and the foregrip are olive polymer; the green smudges on the steel receiver and stock block go grey."""
    def steel(C):
        grips = (C[:, 1] < 0.105) & (((C[:, 2] > -0.25) & (C[:, 2] < -0.13)) | ((C[:, 2] > -0.12) & (C[:, 2] < 0.19)))
        return ~grips
    print('drum_shotgun degreened texels', degreen_tris(j, b, 'geometry_0', steel))


# ---- third pass helpers ----

def _put(j, b, data, tgt=None):
    """Appends raw bytes (or an array) as a new buffer view; returns its index."""
    if not isinstance(data, bytes):
        data = np.ascontiguousarray(data).tobytes()
    while len(b) % 4:
        b.append(0)
    bv = {'buffer': 0, 'byteOffset': len(b), 'byteLength': len(data)}
    if tgt:
        bv['target'] = tgt
    j['bufferViews'].append(bv)
    b += data
    return len(j['bufferViews']) - 1


def prim(j, node):
    nd = next(n for n in j['nodes'] if n.get('name') == node)
    prs = j['meshes'][nd['mesh']]['primitives']
    assert len(prs) == 1, node
    return prs[0]


def set_attrs(j, b, pr, attrs, I):
    """Rewrites the named float attributes ((N,k) arrays) and the indices of a primitive; attributes not named must already match N."""
    for key, arr in attrs.items():
        arr = np.asarray(arr, np.float32)
        a = j['accessors'][pr['attributes'][key]]
        a.update(bufferView=_put(j, b, arr, 34962), byteOffset=0, componentType=5126, count=len(arr))
        a.pop('normalized', None)
        a.pop('sparse', None)
        if key == 'POSITION':
            a['min'], a['max'] = arr.min(0).tolist(), arr.max(0).tolist()
        else:
            a.pop('min', None)
            a.pop('max', None)
    idx = np.asarray(I, np.uint32).reshape(-1)
    a = j['accessors'][pr['indices']]
    a.update(bufferView=_put(j, b, idx, 34963), byteOffset=0, componentType=5125, count=int(idx.size))
    a.pop('min', None)
    a.pop('max', None)


def albedo(j, b, node):
    """(image entry, PIL RGB image) of a node's base colour texture."""
    import io
    from PIL import Image
    pr = prim(j, node)
    img = j['images'][j['textures'][j['materials'][pr['material']]['pbrMetallicRoughness']['baseColorTexture']['index']]['source']]
    bv = j['bufferViews'][img['bufferView']]
    return img, Image.open(io.BytesIO(bytes(b[bv['byteOffset']:bv['byteOffset'] + bv['byteLength']]))).convert('RGB')


def store_image(j, b, img, im, quality=92):
    import io
    buf = io.BytesIO()
    im.save(buf, 'JPEG', quality=quality)
    img['bufferView'] = _put(j, b, buf.getvalue())
    img['mimeType'] = 'image/jpeg'


def _box_blur(a, r):
    """Box blur of radius r over the first two axes (edge padded), via cumulative sums."""
    for ax in (0, 1):
        pad = [(0, 0)] * a.ndim
        pad[ax] = (r + 1, r)
        c = np.cumsum(np.pad(a, pad, mode='edge'), ax)
        n = c.shape[ax]
        a = (np.take(c, range(2 * r + 1, n), ax) - np.take(c, range(0, n - 2 * r - 1), ax)) / (2 * r + 1)
    return a


def _blur(a, r):
    for _ in range(3):   # three box passes ~ a gaussian
        a = _box_blur(a, r)
    return a


def flatten_blotches(im, keep, small=12, large=40, amount=0.6):
    """Damps the mid-frequency light/dark blotches (between ~small and ~large texels) of the texels where keep is False, with
    normalised masked blurs so the kept texels (tan paint, light markings, dark seams) neither bleed in nor change."""
    a = np.asarray(im).astype(np.float64)
    m = (~keep).astype(np.float64)[..., None]
    eps = 1e-6
    bs = _blur(a * m, small) / (_blur(m, small) + eps)
    bl = _blur(a * m, large) / (_blur(m, large) + eps)
    out = np.where(m > 0, a - amount * (bs - bl), a)
    return out.clip(0, 255).astype(np.uint8)


def loop_subdivide(P, N, UV, I, crease_deg=50.0):
    """One Loop subdivision step of the triangles I (indices into P/N/UV) with sharp creases: edges with a dihedral above crease_deg,
    boundary and non-manifold edges stay sharp (crease rule), vertices on more than two creases stay put. Vertices are welded by
    position; the output has its own vertices per triangle corner (UVs interpolate linearly) and crease-aware smooth normals.
    Returns (P', N', UV', I') for the new triangles only."""
    key = np.round(P[I.reshape(-1)] / 1e-5).astype(np.int64)
    _, wid = np.unique(key, axis=0, return_inverse=True)
    wid = wid.reshape(-1)
    T = wid.reshape(-1, 3)
    W = np.zeros((T.max() + 1, 3))
    W[T.reshape(-1)] = P[I.reshape(-1)]
    nt = len(T)
    fn = np.cross(W[T[:, 1]] - W[T[:, 0]], W[T[:, 2]] - W[T[:, 0]])
    fn /= np.linalg.norm(fn, axis=1, keepdims=True) + 1e-20
    # edges: (tri, local edge k) -> vertices T[k], T[(k+1)%3]; opposite T[(k+2)%3]
    ea = T.reshape(-1)
    eb = T[:, [1, 2, 0]].reshape(-1)
    eo = T[:, [2, 0, 1]].reshape(-1)
    ef = np.repeat(np.arange(nt), 3)
    ek = np.stack([np.minimum(ea, eb), np.maximum(ea, eb)], 1)
    E, eid = np.unique(ek, axis=0, return_inverse=True)
    eid = eid.reshape(-1)
    ne = len(E)
    cnt = np.bincount(eid, minlength=ne)
    crease = cnt != 2
    two = np.where(cnt == 2)[0]
    order = np.argsort(eid, kind='stable')
    first = np.searchsorted(eid[order], np.arange(ne))
    f0 = np.full(ne, -1)
    f1 = np.full(ne, -1)
    f0[two] = order[first[two]]
    f1[two] = order[first[two] + 1]
    cosang = np.einsum('ij,ij->i', fn[ef[f0[two]]], fn[ef[f1[two]]])
    crease[two[cosang < math.cos(math.radians(crease_deg))]] = True
    # edge points
    EP = (W[E[:, 0]] + W[E[:, 1]]) / 2
    sm = np.where(~crease)[0]
    EP[sm] = 0.375 * (W[E[sm, 0]] + W[E[sm, 1]]) + 0.125 * (W[eo[f0[sm]]] + W[eo[f1[sm]]])
    # vertex points
    nv = len(W)
    val = np.bincount(E.reshape(-1), minlength=nv).astype(np.float64)
    nsum = np.zeros((nv, 3))
    np.add.at(nsum, E[:, 0], W[E[:, 1]])
    np.add.at(nsum, E[:, 1], W[E[:, 0]])
    nc = np.bincount(E[crease].reshape(-1), minlength=nv)
    csum = np.zeros((nv, 3))
    np.add.at(csum, E[crease, 0], W[E[crease, 1]])
    np.add.at(csum, E[crease, 1], W[E[crease, 0]])
    beta = np.where(val > 3, 3.0 / (8.0 * np.maximum(val, 1)), 3.0 / 16.0)
    VP = (1 - val * beta)[:, None] * W + beta[:, None] * nsum
    VP[nc == 2] = 0.75 * W[nc == 2] + 0.125 * csum[nc == 2]
    VP[nc > 2] = W[nc > 2]
    # output: per source triangle 6 vertices (3 corners, 3 edge points on edges 01, 12, 20) -> 4 triangles
    E3 = eid.reshape(-1, 3)
    uv3 = UV[I]
    OP = np.concatenate([VP[T], EP[E3]], 1).reshape(-1, 3)
    OU = np.concatenate([uv3, (uv3 + uv3[:, [1, 2, 0]]) / 2], 1).reshape(-1, 2)
    OK = np.concatenate([T, nv + E3], 1).reshape(-1)          # weld id of each output vertex
    loc = np.array([[0, 3, 5], [1, 4, 3], [2, 5, 4], [3, 4, 5]])
    OI = (np.arange(nt)[:, None, None] * 6 + loc[None]).reshape(-1, 3)
    # crease-aware normals: per output corner, the area-weighted normals of the faces around its weld id within crease_deg of its own face
    fa = np.cross(OP[OI[:, 1]] - OP[OI[:, 0]], OP[OI[:, 2]] - OP[OI[:, 0]])
    fu = fa / (np.linalg.norm(fa, axis=1, keepdims=True) + 1e-20)
    ck = OK[OI.reshape(-1)]
    cf = np.repeat(np.arange(len(OI)), 3)
    srt = np.argsort(ck, kind='stable')
    bounds = np.searchsorted(ck[srt], np.unique(ck))
    bounds = np.append(bounds, len(srt))
    ON = np.zeros_like(OP)
    lim = math.cos(math.radians(crease_deg))
    for s, e in zip(bounds[:-1], bounds[1:]):
        cs = srt[s:e]
        faces = cf[cs]
        u = fu[faces]
        a = fa[faces]
        near = (u @ u.T) > lim
        nn = near.astype(np.float64) @ a
        ON[OI.reshape(-1)[cs]] = nn
    ON /= np.linalg.norm(ON, axis=1, keepdims=True) + 1e-20
    return OP, ON, OU, OI


def smooth_region(j, b, node, pred, min_tris=200, crease_deg=50.0):
    """Loop-subdivides (once, with creases) each welded connected component of a node's mesh whose world triangle centroids all satisfy
    pred and that has at least min_tris triangles; other triangles are kept as they are. Returns the subdivided triangle count."""
    i = next(k for k, n in enumerate(j['nodes']) if n.get('name') == node)
    m = g.node_world(j, i)
    pr = prim(j, node)
    P = g.accessor(j, b, pr['attributes']['POSITION']).astype(np.float64)
    N = g.accessor(j, b, pr['attributes']['NORMAL']).astype(np.float64)
    UV = g.accessor(j, b, pr['attributes']['TEXCOORD_0']).astype(np.float64)
    I = g.accessor(j, b, pr['indices']).reshape(-1, 3).astype(np.int64)
    assert set(pr['attributes']) == {'POSITION', 'NORMAL', 'TEXCOORD_0'}, pr['attributes']
    _, wid = np.unique(np.round(P / 1e-5).astype(np.int64), axis=0, return_inverse=True)
    wid = wid.reshape(-1)
    par = list(range(wid.max() + 1))

    def root(x):
        while par[x] != x:
            par[x] = par[par[x]]
            x = par[x]
        return x
    for t in wid[I]:
        ra, rb, rc = root(t[0]), root(t[1]), root(t[2])
        par[rb] = ra
        par[root(rc)] = ra
    comp = np.array([root(x) for x in wid[I[:, 0]]])
    ok = pred(P[I].mean(1) @ m[:3, :3].T + m[:3, 3])
    sel = np.zeros(len(I), bool)
    for c in np.unique(comp):
        s = comp == c
        if s.sum() >= min_tris and ok[s].all():
            sel |= s
    OP, ON, OU, OI = loop_subdivide(P, N, UV, I[sel], crease_deg)
    n0 = len(P)
    set_attrs(j, b, pr, {'POSITION': np.vstack([P, OP]), 'NORMAL': np.vstack([N, ON]), 'TEXCOORD_0': np.vstack([UV, OU])},
              np.vstack([I[~sel], OI + n0]))
    return int(sel.sum())


# ---- third pass models ----

def bullpup_v3(j, b, p):
    """The tan block on the receiver becomes a modelled red dot (aw_sight_fit.gd draws the lens and cuts the view cone in ADS); the 1k
    receiver albedo goes to 2k with its mid-frequency grey blotches flattened (tan paint, markings and seams kept)."""
    from PIL import Image, ImageFilter
    cut_world(j, b, 'geometry_0', lambda C: (C[:, 1] > 0.237) & (C[:, 2] > -0.125) & (C[:, 2] < -0.02) & (np.abs(C[:, 0]) < 0.04))
    S = 40
    p.box('part_blued', (0, 0.239, -0.072), (0.066, 0.010, 0.09))           # rail mount
    for s in (-1, 1):
        p.cyl('part_steel', (s * 0.034, 0.239, -0.05), 0.005, 0.005, 0.004, 'x', 12)
    p.box('part_blued', (0, 0.25, -0.07), (0.034, 0.012, 0.056))            # riser
    p.cyl('part_scope', (0, 0.27, -0.07), 0.0175, 0.0175, 0.056, 'z', S, True, inner=0.0135)   # tube (the aim line, y 0.278, runs in the bore)
    p.cyl('part_scope', (0, 0.27, -0.1), 0.019, 0.019, 0.006, 'z', S, True, inner=0.0135)     # front hood
    p.cyl('part_scope', (0, 0.27, -0.041), 0.019, 0.019, 0.004, 'z', S, True, inner=0.0135)   # rear ring
    p.cyl('part_glass', (0, 0.27, -0.094), 0.0135, 0.0135, 0.002, 'z', S)
    p.cyl('part_scope', (0.0195, 0.27, -0.07), 0.008, 0.008, 0.008, 'x', 20)  # brightness turret
    p.cyl('part_scope', (0, 0.2895, -0.07), 0.007, 0.007, 0.006, 'y', 20)     # adjustment turret
    sight_marks(j, 0.2776, -0.041, -0.1)   # the turret now tops the gun, so mark the line through the bore
    img, im = albedo(j, b, 'geometry_0')
    im = im.resize((im.width * 2, im.height * 2), Image.LANCZOS)
    a = np.asarray(im).astype(np.float64)
    lum = a @ [0.299, 0.587, 0.114]
    tan = (a[..., 0] > a[..., 2] * 1.2) & (a[..., 0] > 70)
    keep = tan | (lum > 105) | (lum < 32)
    im = Image.fromarray(flatten_blotches(im, keep)).filter(ImageFilter.MedianFilter(3))
    store_image(j, b, img, im)


def machine_pistol_v3(j, b, p):
    """The v1 sights stood on the slide as a flat box with specks on it; new sights sit in the slide top, with serrations, an ejection
    port and a top rib so the slide is not a plain box. The marks stay at y 0.174."""
    nd = next(n for n in j['nodes'] if n.get('name') == 'aw_part_machine_pistol_part_blued')
    nd.pop('mesh', None)
    p.box('part_blued', (0, 0.165, -0.02), (0.03, 0.018, 0.018))            # rear sight body
    for s in (-1, 1):
        p.box('part_blued', (s * 0.01025, 0.178, -0.02), (0.0095, 0.008, 0.016))
    p.box('part_blued', (0, 0.163, -0.202), (0.018, 0.010, 0.028))          # front ramp
    p.box('part_blued', (0, 0.1715, -0.204), (0.0045, 0.007, 0.012))
    p.box('part_steel', (0, 0.1748, -0.2), (0.0046, 0.0016, 0.002))          # post face dot
    p.box('part_steel', (0, 0.1568, -0.1), (0.012, 0.0015, 0.14))           # top rib
    for s in (-1, 1):
        for z0, z1 in ((-0.025, 0.005), (-0.17, -0.15)):
            for z in np.arange(z0, z1 + 1e-6, 0.005):
                p.box('part_black', (s * 0.0254, 0.13, float(z)), (0.0012, 0.034, 0.0022))
    p.box('part_black', (0.0253, 0.14, -0.09), (0.0012, 0.018, 0.04))      # ejection port
    p.box('part_steel', (0.02605, 0.14, -0.09), (0.0003, 0.01, 0.026))     # bolt face in the port


def drum_shotgun_v3(j, b, p):
    """The source's faceted sight blocks (and the block between them) go; a protected front post and a ghost-ring rear
    sight, both with round-topped ears."""
    cut_world(j, b, 'geometry_0', lambda C: (C[:, 1] > 0.256) & (np.abs(C[:, 0]) < 0.04) & (C[:, 2] > -0.255) & (C[:, 2] < -0.083))
    p.box('part_blued', (0, 0.264, -0.216), (0.068, 0.02, 0.07))             # front base
    p.box('part_blued', (0, 0.26, -0.161), (0.05, 0.012, 0.042))            # bridge to the rear base
    for s in (-1, 1):
        p.box('part_blued', (s * 0.015, 0.284, -0.2155), (0.008, 0.02, 0.03))
        p.cyl('part_blued', (s * 0.015, 0.293, -0.2155), 0.004, 0.004, 0.03, 'z', 16)
    p.box('part_blued', (0, 0.274, -0.2155), (0.005, 0.022, 0.008))          # post, top 0.285
    p.box('part_blued', (0, 0.265, -0.111), (0.068, 0.022, 0.06))            # rear base
    p.cyl('part_blued', (0, 0.284, -0.116), 0.011, 0.011, 0.008, 'z', 32, True, inner=0.0075)   # ghost ring
    for s in (-1, 1):
        p.box('part_blued', (s * 0.0185, 0.284, -0.116), (0.007, 0.024, 0.03))
        p.cyl('part_blued', (s * 0.0185, 0.296, -0.116), 0.0035, 0.0035, 0.03, 'z', 16)
    sight_marks(j, 0.2842, -0.116, -0.2155)   # ring centre to post top; the ears stand above the line


def battle_rifle_v3(j, b, p):
    """The stock was coarse polygons: one Loop subdivision step with 50 degree creases (flats and edges keep, curves round)."""
    print('battle_rifle stock tris subdivided', smooth_region(j, b, 'body', lambda C: C[:, 2] > 0.085, min_tris=500))


def quad_rocket_launcher_v3(j, b, p):
    """The rear end cap was one stretched texel field (863 texels/m like the rest, but large and flat): a modelled cover plate with
    corner bolts, a vent and a data plate over it."""
    zc, y0, y1, hx, r = 0.2955, -0.047, 0.128, 0.104, 0.012
    yc, hy = (y0 + y1) / 2, y1 - y0
    p.box('part_drab', (0, yc, zc), (2 * hx - 2 * r, hy, 0.003))
    p.box('part_drab', (0, yc, zc), (2 * hx, hy - 2 * r, 0.003))
    for sx in (-1, 1):
        for y in (y0 + r, y1 - r):
            p.cyl('part_drab', (sx * (hx - r), y, zc), r, r, 0.003, 'z', 20)
            p.cyl('part_steel', (sx * (hx - r), y, 0.2985), 0.0055, 0.0055, 0.003, 'z', 6)
    p.box('part_black', (0, 0.075, 0.2975), (0.11, 0.05, 0.002))
    for k in range(5):
        p.box('part_drab', (0, 0.058 + k * 0.0085, 0.2985), (0.104, 0.004, 0.003))
    p.box('part_steel', (0, 0.008, 0.29775), (0.06, 0.022, 0.0015))


DONE = {'minigun': minigun, 'rocket_launcher_alt': launcher, 'lmg': lmg, 'machine_pistol': machine_pistol, 'carbine': carbine}
# second pass (the judge's remodel list): its own tag, so a model done in the first pass still takes it once
DONE2 = {'marksman': marksman, 'drum_shotgun': drum_shotgun}
DONE3 = {'bullpup': bullpup_v3, 'machine_pistol': machine_pistol_v3, 'drum_shotgun': drum_shotgun_v3, 'battle_rifle': battle_rifle_v3,
         'quad_rocket_launcher': quad_rocket_launcher_v3}


def main(names):
    for tag, done in ((TAG, DONE), (TAG2, DONE2), (TAG3, DONE3)):
        for n in names or list(done):
            f = done.get(n)
            if not f:
                continue
            path = os.path.join(MODELS, n + '.glb')
            j, b = g.read_glb(path)
            ex = j['asset'].setdefault('extras', {})
            if tag in ex:
                print(n, tag, 'already done')
                continue
            p = g.Parts(j, b)
            f(j, b, p)
            p.finish(n + {TAG: '', TAG2: '_v2', TAG3: '_v3'}[tag])
            ex[tag] = True
            b = g.compact(j, b)   # drop the buffer views this pass replaced
            g.write_glb(path, j, b)
            print(n, tag, 'ok', len(b))


if __name__ == '__main__':
    main(sys.argv[1:])
