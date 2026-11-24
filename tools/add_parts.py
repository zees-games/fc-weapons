"""Adds modelled detail parts to the shipped weapon GLBs in place (pure python + numpy, no Blender): minigun barrel clamps and bores, the launcher
venturi, the lmg belt and a smaller ammo box, rear sights on lmg, machine_pistol and carbine. Parts are plain-material meshes named aw_part_*
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


DONE = {'minigun': minigun, 'rocket_launcher_alt': launcher, 'lmg': lmg, 'machine_pistol': machine_pistol, 'carbine': carbine}


def main(names):
    for n in names or list(DONE):
        f = DONE.get(n)
        if not f:
            print('skip', n)
            continue
        path = os.path.join(MODELS, n + '.glb')
        j, b = g.read_glb(path)
        ex = j['asset'].setdefault('extras', {})
        if TAG in ex:
            print(n, 'already done')
            continue
        p = g.Parts(j, b)
        f(j, b, p)
        p.finish(n)
        ex[TAG] = True
        g.write_glb(path, j, b)
        print(n, 'ok', len(b))


if __name__ == '__main__':
    main(sys.argv[1:])
