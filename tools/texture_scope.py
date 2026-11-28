"""Gives a model's plain-material scope parts (tools/add_parts.py's aw_part_* meshes, which carry no UVs) a texture set of
their own: cylindrical UVs round the scope axis, a procedural anodised finish (lathe rings, mottling, fine grain in the
albedo, roughness and normal maps, knurled bands where the row asks) and a coated objective lens with a rim highlight.
Own work, no source image, so no further licence applies. The glb's asset.extras.aw_scope_tex marks a model as done.
Usage: python3 tools/texture_scope.py [model ...]   (default: every model in SCOPES). Needs numpy and Pillow."""
import io
import math
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glb_parts as g

MODELS = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'addons', 'fc_weapons', 'assets', 'models')
TAG = 'aw_scope_tex'
# model: scope axis (y of the bore line, x), the body materials to texture, the lens material, knurled z bands (metres).
SCOPES = {
    'marksman': {'axis': (0.0, 0.195), 'body': ['part_scope', 'part_black'], 'lens': 'part_glass',
                 'knurl': [], 'colour': [0.085, 0.088, 0.094], 'rough': 0.55},
}
SIZE = 256
# Texture repeats per metre along the axis: 256 texels over 0.12 m, about half a millimetre each.
ALONG = 1.0 / 0.12


def _blur(a, k):
    for axis in (0, 1):
        acc = np.zeros_like(a)
        for d in range(-k, k + 1):
            acc += np.roll(a, d, axis=axis)
        a = acc / (2 * k + 1)
    return a


def _png(arr):
    out = io.BytesIO()
    Image.fromarray(np.clip(arr * 255.0 + 0.5, 0, 255).astype(np.uint8)).save(out, 'PNG', optimize=True)
    return out.getvalue()


def body_maps(rng, knurl_rows):
    """Albedo, metal-rough and normal maps (rows run along the axis, columns round it)."""
    n = SIZE
    mottle = _blur(rng.standard_normal((n, n)), 12)
    mottle /= np.abs(mottle).max() + 1e-6
    # Lathe rings: a height that varies along the axis only, plus a fine grain.
    rings = _blur(rng.standard_normal((n, 1)).repeat(n, 1), 1)
    rings /= np.abs(rings).max() + 1e-6
    grain = _blur(rng.standard_normal((n, n)), 1)
    grain /= np.abs(grain).max() + 1e-6
    height = 0.35 * rings + 0.15 * grain
    v, u = np.mgrid[0:n, 0:n] / n
    knurled = np.zeros((n, n), bool)
    for r0, r1 in knurl_rows:
        knurled |= (v >= r0) & (v < r1)
    diamond = np.abs(np.sin(u * math.pi * 96 + v * math.pi * 48)) * np.abs(np.sin(u * math.pi * 96 - v * math.pi * 48))
    height = np.where(knurled, 1.6 * diamond, height)
    albedo = 0.86 + 0.10 * mottle + 0.04 * grain
    albedo = np.where(knurled, 0.75 + 0.35 * diamond, albedo)
    rough = np.clip(0.85 + 0.12 * mottle - 0.08 * rings, 0, 1)
    rough = np.where(knurled, 0.7 + 0.2 * (1 - diamond), rough)
    gy, gx = np.gradient(height)
    nx, ny = -gx * 2.0, gy * 2.0
    nz = np.ones_like(nx)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    normal = np.stack([nx / ln * 0.5 + 0.5, ny / ln * 0.5 + 0.5, nz / ln * 0.5 + 0.5], -1)
    alb = np.stack([albedo, albedo, albedo * 1.02], -1)
    mr = np.stack([np.ones_like(rough), rough, np.full_like(rough, 0.35)], -1)
    return _png(alb), _png(mr), _png(normal)


def lens_map():
    """A coated lens seen from the front: deep in the middle, a green-violet coating toward the rim, a bright crescent."""
    n = 128
    y, x = (np.mgrid[0:n, 0:n] + 0.5) / n * 2.0 - 1.0
    r = np.sqrt(x * x + y * y)
    coat = np.clip((r - 0.35) / 0.6, 0, 1) ** 1.5
    rgb = np.stack([0.10 + 0.35 * coat, 0.16 + 0.55 * coat, 0.14 + 0.45 * coat], -1)
    crescent = np.clip(1.0 - np.abs(r - 0.72) / 0.08, 0, 1) * np.clip(-(x + y) * 0.9, 0, 1)
    rgb = rgb + crescent[..., None] * 0.8
    return _png(np.clip(rgb, 0, 1))


def _uv(pos, nrm, axis):
    """Round the axis (u, one turn per texture width) and along it (v); a face across the axis maps flat."""
    ax, ay = axis
    dx, dy = pos[:, 0] - ax, pos[:, 1] - ay
    u = (np.arctan2(dx, dy) / (2 * math.pi) + 0.5)
    v = -pos[:, 2] * ALONG
    cap = np.abs(nrm[:, 2]) > 0.7
    u = np.where(cap, dx * ALONG + 0.5, u)
    v = np.where(cap, dy * ALONG + 0.5, v)
    return np.stack([u, v], -1).astype(np.float32)


def _image(j, b, data):
    view = _put(b, j, data)
    j['images'].append({'bufferView': view, 'mimeType': 'image/png'})
    j['samplers'] = j.get('samplers') or []
    if not j['samplers'] or j['samplers'][-1].get('name') != 'aw_repeat':
        j['samplers'].append({'name': 'aw_repeat', 'magFilter': 9729, 'minFilter': 9987, 'wrapS': 10497, 'wrapT': 10497})
    j['textures'].append({'source': len(j['images']) - 1, 'sampler': len(j['samplers']) - 1})
    return len(j['textures']) - 1


def _put(b, j, data):
    while len(b) % 4:
        b.append(0)
    j['bufferViews'].append({'buffer': 0, 'byteOffset': len(b), 'byteLength': len(data)})
    b += data
    return len(j['bufferViews']) - 1


def _set_uv(j, b, node, axis):
    pr = j['meshes'][node['mesh']]['primitives'][0]
    pos = g.accessor(j, b, pr['attributes']['POSITION']).astype(np.float64)
    nrm = g.accessor(j, b, pr['attributes']['NORMAL']).astype(np.float64)
    uv = _uv(pos, nrm, axis)
    view = _put(b, j, uv.tobytes())
    j['bufferViews'][view]['target'] = 34962
    j['accessors'].append({'bufferView': view, 'byteOffset': 0, 'componentType': 5126, 'count': len(uv), 'type': 'VEC2'})
    pr['attributes']['TEXCOORD_0'] = len(j['accessors']) - 1
    return pr['material']


def texture(name):
    spec = SCOPES[name]
    path = os.path.join(MODELS, name + '.glb')
    j, b = g.read_glb(path)
    ex = j['asset'].setdefault('extras', {})
    if TAG in ex:
        print(name, 'already done')
        return
    rng = np.random.default_rng(7)
    knurl = [((-z1) * ALONG % 1.0, (-z0) * ALONG % 1.0) for z0, z1 in spec['knurl']]
    alb, mr, nrm = body_maps(rng, knurl)
    t_alb, t_mr, t_nrm = _image(j, b, alb), _image(j, b, mr), _image(j, b, nrm)
    t_lens = _image(j, b, lens_map())
    done = set()
    for node in j['nodes']:
        nm = node.get('name', '')
        if not nm.startswith('aw_part_') or 'mesh' not in node:
            continue
        hit = [m for m in spec['body'] + [spec['lens']] if nm.endswith('_' + m)]
        if not hit:
            continue
        mi = _set_uv(j, b, node, spec['axis'])
        if mi in done:
            continue
        done.add(mi)
        mat = j['materials'][mi]
        pbr = mat.setdefault('pbrMetallicRoughness', {})
        if hit[0] == spec['lens']:
            pbr.update(baseColorTexture={'index': t_lens}, baseColorFactor=[0.5, 0.5, 0.5, 1.0], metallicFactor=0.0, roughnessFactor=0.06)
            mat['emissiveTexture'] = {'index': t_lens}
            mat['emissiveFactor'] = [0.12, 0.12, 0.12]
            continue
        pbr.update(baseColorTexture={'index': t_alb}, metallicRoughnessTexture={'index': t_mr},
                   baseColorFactor=spec['colour'] + [1.0], metallicFactor=1.0, roughnessFactor=spec['rough'])
        mat['normalTexture'] = {'index': t_nrm, 'scale': 0.6}
    ex[TAG] = True
    b = g.compact(j, b)
    g.write_glb(path, j, b)
    print(name, 'ok', len(done), 'materials', len(b))


if __name__ == '__main__':
    for n in sys.argv[1:] or list(SCOPES):
        texture(n)
