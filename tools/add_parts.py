"""Adds modelled detail parts to the shipped weapon GLBs in place (pure python + numpy, no Blender): minigun barrel clamps and bores, the launcher
venturi, the lmg belt and a smaller ammo box, rear sights on lmg, machine_pistol and carbine;
second pass (aw_parts_v2): the marksman's smooth scope, the drum_shotgun's green smudges off its steel. Parts are plain-material meshes named aw_part_*
(see glb_parts.py); the glb's asset.extras.aw_parts marks a model as done, so a second run does nothing.
Usage: python3 tools/add_parts.py [model ...]   (default: all six). Needs numpy; own geometry, no new licence."""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glb_parts as g

MODELS = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'addons', 'fc_weapons', 'assets', 'models')
TAG = 'aw_parts_v1'
TAG2 = 'aw_parts_v2'


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


DONE = {'minigun': minigun, 'rocket_launcher_alt': launcher, 'lmg': lmg, 'machine_pistol': machine_pistol, 'carbine': carbine}
# second pass (the judge's remodel list): its own tag, so a model done in the first pass still takes it once
DONE2 = {'marksman': marksman, 'drum_shotgun': drum_shotgun}


def main(names):
    for tag, done in ((TAG, DONE), (TAG2, DONE2)):
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
            p.finish(n if tag == TAG else n + '_v2')
            ex[tag] = True
            g.write_glb(path, j, b)
            print(n, tag, 'ok', len(b))


if __name__ == '__main__':
    main(sys.argv[1:])
