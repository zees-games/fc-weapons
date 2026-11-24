"""Small pure-python glTF/GLB helpers for the weapon tools: read and write a GLB, world positions of a model's meshes, and primitive builders
(box, cylinder, cone, ring) that append flat-shaded parts with their own plain PBR material as new scene roots. Frame is glTF: x right, y up,
muzzle toward -Z, metres, origin at the grip (the scene roots' frame, the same one the sight marks are written in).
Used by tools/add_parts.py and tools/material_pass.py. Run with python3 -I."""
import json
import math
import struct

import numpy as np


def read_glb(p):
    b = open(p, 'rb').read()
    n = struct.unpack('<I', b[12:16])[0]
    j = json.loads(b[20:20 + n])
    off = 20 + n
    m = struct.unpack('<I', b[off:off + 4])[0]
    return j, bytearray(b[off + 8:off + 8 + m])


def write_glb(p, j, binb):
    while len(binb) % 4:
        binb.append(0)
    j['buffers'] = [{'byteLength': len(binb)}]
    js = json.dumps(j, separators=(',', ':')).encode()
    js += b' ' * (-len(js) % 4)
    total = 12 + 8 + len(js) + 8 + len(binb)
    open(p, 'wb').write(b'glTF' + struct.pack('<II', 2, total) + struct.pack('<I', len(js)) + b'JSON' + js + struct.pack('<I', len(binb)) + b'BIN\0' + bytes(binb))


def node_matrix(n):
    if 'matrix' in n:
        return np.array(n['matrix'], dtype=np.float64).reshape(4, 4).T
    t = np.array(n.get('translation', [0, 0, 0]), dtype=np.float64)
    q = n.get('rotation', [0, 0, 0, 1])
    s = np.array(n.get('scale', [1, 1, 1]), dtype=np.float64)
    x, y, z, w = q
    r = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                  [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                  [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    m = np.eye(4)
    m[:3, :3] = r * s
    m[:3, 3] = t
    return m


def accessor(j, binb, idx):
    a = j['accessors'][idx]
    v = j['bufferViews'][a['bufferView']]
    comp = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a['type']]
    dt = {5126: np.float32, 5123: np.uint16, 5125: np.uint32, 5121: np.uint8}[a['componentType']]
    o = v.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = v.get('byteStride')
    cnt = a['count']
    isz = np.dtype(dt).itemsize
    if stride and stride != comp * isz:
        raw = np.frombuffer(bytes(binb[o:o + stride * cnt]), dtype=np.uint8).reshape(cnt, stride)[:, :comp * isz]
        return np.frombuffer(raw.tobytes(), dtype=dt).reshape(cnt, comp)
    return np.frombuffer(bytes(binb[o:o + cnt * comp * isz]), dtype=dt).reshape(cnt, comp)


def world_points(j, binb, skip_prefix='aw_part'):
    """All mesh vertices of the scene in the scene roots' frame, as {node name: (N,3) array}."""
    out = {}
    parent = {}
    for i, n in enumerate(j['nodes']):
        for c in n.get('children', []):
            parent[c] = i

    def world(i):
        m = node_matrix(j['nodes'][i])
        while i in parent:
            i = parent[i]
            m = node_matrix(j['nodes'][i]) @ m
        return m
    for i, n in enumerate(j['nodes']):
        if 'mesh' not in n or n.get('name', '').startswith(skip_prefix):
            continue
        m = world(i)
        pts = []
        for p in j['meshes'][n['mesh']]['primitives']:
            pts.append(accessor(j, binb, p['attributes']['POSITION']).astype(np.float64))
        pts = np.vstack(pts)
        out[n.get('name', str(i))] = (m[:3, :3] @ pts.T).T + m[:3, 3]
    return out


class Parts:
    """Collects flat-shaded parts per material and appends them to a GLB as one scene-root node per part group."""

    def __init__(self, j, binb):
        self.j, self.b = j, binb
        self.groups = {}

    def _add(self, mat, v, n, f):
        g = self.groups.setdefault(mat, [[], [], []])
        base = sum(len(x) for x in g[0])
        g[0].append(v)
        g[1].append(n)
        g[2].append(f + base)

    # ---- primitives (centres and sizes in the model frame)
    def box(self, mat, c, s, rot=None):
        """Box of full size s=(x,y,z) at centre c; rot = 3x3 matrix or None."""
        hx, hy, hz = (s[0] / 2, s[1] / 2, s[2] / 2)
        v, nn, ff = [], [], []
        faces = [((1, 0, 0), (1, 1, -1), (1, -1, -1), (1, -1, 1), (1, 1, 1)),
                 ((-1, 0, 0), (-1, 1, 1), (-1, -1, 1), (-1, -1, -1), (-1, 1, -1)),
                 ((0, 1, 0), (-1, 1, 1), (-1, 1, -1), (1, 1, -1), (1, 1, 1)),
                 ((0, -1, 0), (-1, -1, -1), (-1, -1, 1), (1, -1, 1), (1, -1, -1)),
                 ((0, 0, 1), (-1, 1, 1), (1, 1, 1), (1, -1, 1), (-1, -1, 1)),
                 ((0, 0, -1), (1, 1, -1), (-1, 1, -1), (-1, -1, -1), (1, -1, -1))]
        for k, (nrm, *cs) in enumerate(faces):
            for q in cs:
                v.append((q[0] * hx, q[1] * hy, q[2] * hz))
                nn.append(nrm)
            ff += [(4 * k, 4 * k + 1, 4 * k + 2), (4 * k, 4 * k + 2, 4 * k + 3)]
        v, nn = np.array(v, np.float64), np.array(nn, np.float64)
        self._emit(mat, v, nn, np.array(ff, np.uint32), c, rot)

    def cyl(self, mat, c, r0, r1, length, axis='z', seg=24, caps=True, inner=0.0, rot=None):
        """Frustum along an axis (radius r0 at -axis end, r1 at +axis end), optional hollow (inner radius) with the bore visible."""
        v, nn, ff = [], [], []
        ang = [2 * math.pi * i / seg for i in range(seg)]
        slope = (r0 - r1) / length if length else 0.0
        for i, a in enumerate(ang):
            ca, sa = math.cos(a), math.sin(a)
            nrm = np.array([ca, sa, slope])
            nrm /= np.linalg.norm(nrm)
            v += [(r0 * ca, r0 * sa, -length / 2), (r1 * ca, r1 * sa, length / 2)]
            nn += [tuple(nrm)] * 2
        for i in range(seg):
            a0, a1 = 2 * i, 2 * ((i + 1) % seg)
            ff += [(a0, a0 + 1, a1 + 1), (a0, a1 + 1, a1)]
        base = len(v)
        if caps:
            for end, r, sgn in ((-length / 2, r0, -1), (length / 2, r1, 1)):
                o = len(v)
                v.append((0, 0, end))
                nn.append((0, 0, sgn))
                for a in ang:
                    v.append((r * math.cos(a), r * math.sin(a), end))
                    nn.append((0, 0, sgn))
                for i in range(seg):
                    p, q = o + 1 + i, o + 1 + (i + 1) % seg
                    ff.append((o, q, p) if sgn < 0 else (o, p, q))
        v, nn = np.array(v, np.float64), np.array(nn, np.float64)
        ff = np.array(ff, np.uint32)
        if inner > 0:
            # hollow ring: replace the front cap by an annulus and add a bore tube (inner wall, normals inward)
            self._emit(mat, v[:base], nn[:base], ff[:2 * seg], c, rot, axis)
            ov, on, of = [], [], []
            for i, a in enumerate(ang):
                ca, sa = math.cos(a), math.sin(a)
                ov += [(r0 * ca, r0 * sa, -length / 2), (inner * ca, inner * sa, -length / 2),
                       (r1 * ca, r1 * sa, length / 2), (inner * ca, inner * sa, length / 2),
                       (inner * ca, inner * sa, -length / 2), (inner * ca, inner * sa, length / 2)]
                on += [(0, 0, -1), (0, 0, -1), (0, 0, 1), (0, 0, 1), (-ca, -sa, 0), (-ca, -sa, 0)]
            for i in range(seg):
                a, b = 6 * i, 6 * ((i + 1) % seg)
                of += [(a, b + 1, a + 1), (a, b, b + 1), (a + 2, a + 3, b + 3), (a + 2, b + 3, b + 2), (a + 4, b + 5, a + 5), (a + 4, b + 4, b + 5)]
            self._emit(mat, np.array(ov), np.array(on), np.array(of, np.uint32), c, rot, axis)
            return
        self._emit(mat, v, nn, ff, c, rot, axis)

    def _emit(self, mat, v, nn, ff, c, rot=None, axis='z'):
        if axis == 'x':   # z -> x
            m = np.array([[0, 0, 1], [0, 1, 0], [-1, 0, 0]], np.float64)
        elif axis == 'y':  # z -> y
            m = np.array([[1, 0, 0], [0, 0, 1], [0, -1, 0]], np.float64)
        else:
            m = np.eye(3)
        if rot is not None:
            m = np.asarray(rot, np.float64) @ m
        v = v @ m.T + np.asarray(c, np.float64)
        nn = nn @ m.T
        self._add(mat, v.astype(np.float32), nn.astype(np.float32), ff.astype(np.uint32))

    def finish(self, tag):
        """Appends every group as one mesh node (a scene root) named aw_part_<tag>_<material>."""
        j, binb = self.j, self.b
        mats = {m.get('name'): i for i, m in enumerate(j['materials'])}
        for name, (vs, ns, fs) in self.groups.items():
            spec = MATERIALS[name]
            if name not in mats:
                j['materials'].append({'name': name, 'pbrMetallicRoughness': {'baseColorFactor': spec[0] + [1.0], 'metallicFactor': spec[1], 'roughnessFactor': spec[2]},
                                       'extras': {'aw_part_material': True}})
                mats[name] = len(j['materials']) - 1
            v, nrm, f = np.vstack(vs), np.vstack(ns), np.vstack(fs).astype(np.uint32)
            views = []
            for arr, tgt in ((v, 34962), (nrm, 34962), (f.reshape(-1), 34963)):
                while len(binb) % 4:
                    binb.append(0)
                data = np.ascontiguousarray(arr).tobytes()
                j['bufferViews'].append({'buffer': 0, 'byteOffset': len(binb), 'byteLength': len(data), 'target': tgt})
                binb += data
                views.append(len(j['bufferViews']) - 1)
            ai = len(j['accessors'])
            j['accessors'] += [
                {'bufferView': views[0], 'componentType': 5126, 'count': len(v), 'type': 'VEC3', 'min': v.min(0).tolist(), 'max': v.max(0).tolist()},
                {'bufferView': views[1], 'componentType': 5126, 'count': len(nrm), 'type': 'VEC3'},
                {'bufferView': views[2], 'componentType': 5125, 'count': int(f.size), 'type': 'SCALAR'}]
            j['meshes'].append({'name': 'aw_part_%s_%s' % (tag, name), 'primitives': [{'attributes': {'POSITION': ai, 'NORMAL': ai + 1}, 'indices': ai + 2, 'material': mats[name], 'mode': 4}]})
            j['nodes'].append({'name': 'aw_part_%s_%s' % (tag, name), 'mesh': len(j['meshes']) - 1})
            j['scenes'][j.get('scene', 0)]['nodes'].append(len(j['nodes']) - 1)


# name: (linear base colour, metallic, roughness)
MATERIALS = {
    'part_steel': ([0.30, 0.30, 0.31], 1.0, 0.38),
    'part_blued': ([0.075, 0.08, 0.09], 1.0, 0.42),
    'part_black': ([0.03, 0.03, 0.032], 0.0, 0.55),
    'part_brass': ([0.62, 0.40, 0.14], 1.0, 0.30),
    'part_olive': ([0.07, 0.085, 0.045], 0.0, 0.6),
    'part_glass': ([0.02, 0.05, 0.06], 0.0, 0.05),
}
