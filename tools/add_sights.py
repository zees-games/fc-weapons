"""Seats iron sights on a baked gun model and writes the `sight_rear` / `sight_front` marks the view runtime aims through.
Run: python3 tools/add_sights.py <addons/fc_weapons/assets/models> [name ...]   (plain Python, no Blender: the model's own meshes,
materials and textures pass through byte for byte; only the sight nodes are rebuilt).

Every run first strips the nodes an earlier pass added (`rear_*`, `front_*`, `sight_*`, plus the loose `feed_cover` / `bipod_*`
bars), then builds the parts in SPECS. A spec names a horizontal sight line height `line` (the runtime puts the eye on the rear
mark and does not tilt the gun, so both marks sit at that height) and parts that either reuse the model's own sight (no part) or
add a small piece seated ON the surface below it (the model or an earlier part): each part's bottom must be at or under the model top across its footprint, or
the run fails (a floating part is a defect). A `rear_ring*` part is hidden at the hip by the view runtime.
Stations are metres in the baked frame (origin at the grip, muzzle toward -Z, Y up). After a change, set each weapon's aim
in `AwWeaponArt.WEAPONS` to `(0, -line, z)`; the selftest measures it against the rear mark.
A `front_bead*` part is brass, the rest dark sight metal. The pistol still carries the parts an earlier Blender pass of this
tool built; give it a spec here before rerunning on it."""
import json, math, os, struct, sys

STRIP = ('rear_', 'front_', 'sight_', 'muzzle_bore', 'feed_cover', 'bipod_')
# A model whose far end is not its bore gets a `muzzle_bore` empty here: AwModelCache.muzzle_bore reads it. The quad's tube cluster centre is its bore.
BORE = {'quad_rocket_launcher': (0.0, 0.04, -0.448)}


def box(x0, x1, y0, y1, z0, z1):
    return ('frustum', (x0, x1, z0, z1, y0), (x0, x1, z0, z1, y1))


def taper(bottom, top):
    """bottom/top: (x0, x1, z0, z1, y). A front post keeps top z1 == bottom z1 so its eye-side face is vertical and reads dark."""
    return ('frustum', bottom, top)


def ring(cy, cz, ro, ri, depth):
    return ('ring', cy, cz, ro, ri, depth)


def notch(cz, y0, line, half_gap, half_w, depth):
    """Two shoulders either side of a gap, tops on the sight line (the front tip shows in the gap, level with them)."""
    return [('rear_notch-1', box(-half_w, -half_gap, y0, line, cz - depth / 2, cz + depth / 2)),
            ('rear_notch1', box(half_gap, half_w, y0, line, cz - depth / 2, cz + depth / 2))]


# name -> line y, rear mark z, front mark z, parts [(node name, shape)]; numbers come from top profiles of the model itself.
SPECS = {
    # Frame top 0.0597 at z -0.04 (the hammer stays under 0.047), barrel rib 0.0556: a low notch on the frame, a ramp blade on the rib.
    'derringer': (0.0625, -0.037, -0.111, notch(-0.037, 0.0575, 0.0625, 0.0016, 0.0056, 0.008) + [
        ('front_blade', taper((-0.0009, 0.0009, -0.116, -0.106, 0.0548), (-0.0009, 0.0009, -0.114, -0.106, 0.0625)))]),
    # Own topstrap notch (shoulders 0.1317, gap 3 mm) and own front blade (tip 0.1348): two caps lift the shoulders to the tip.
    'revolver': (0.1348, -0.015, -0.220, [
        ('rear_cap-1', box(-0.0065, -0.0017, 0.1300, 0.1348, -0.019, -0.011)),
        ('rear_cap1', box(0.0017, 0.0065, 0.1300, 0.1348, -0.019, -0.011))]),
    # Own rear ears (top 0.036) and front ears (0.0333); the cocking knob at z 0 reaches 0.033, so the line runs at the ear tops:
    # a small peep between the rear ears and a post between the front ears.
    'smg': (0.0360, 0.100, -0.100, [
        ('rear_stem', box(-0.0014, 0.0014, 0.0212, 0.0325, 0.097, 0.103)),
        ('rear_ring', ring(0.0360, 0.100, 0.0042, 0.0022, 0.005)),
        ('front_post', taper((-0.0016, 0.0016, -0.104, -0.096, 0.0212), (-0.0011, 0.0011, -0.102, -0.096, 0.0360)))]),
    # Own notch (shoulders 0.1674, floor 0.1635) and own front post between ears (0.1637): marks only.
    'machine_pistol': (0.1640, -0.020, -0.202, []),
    # Own rear peep (top 0.0786 at z 0.03) and own front post in its ears (0.073 at z -0.41): marks only, on the peep centre.
    'burst_rifle': (0.0720, 0.033, -0.410, []),
    # Own rear drum (top 0.1123 at z 0.01) and own hooded front post (hood 0.1257 at z -0.54): marks only.
    'battle_rifle': (0.1120, 0.012, -0.535, []),
    # Carry handle top 0.352 at its back (z -0.23), own front post 0.300 at z -0.648: a peep on the handle and a tower over
    # with ears on the native post.
    'lmg': (0.3630, -0.232, -0.648, [
        ('rear_base', taper((-0.012, 0.012, -0.240, -0.224, 0.3460), (-0.010, 0.010, -0.238, -0.226, 0.3540))),
        ('rear_ring', ring(0.3630, -0.232, 0.0095, 0.0045, 0.008)),
        ('front_tower', taper((-0.0120, 0.0120, -0.659, -0.637, 0.2400), (-0.0110, 0.0110, -0.654, -0.642, 0.3400))),
        ('front_post', taper((-0.0018, 0.0018, -0.651, -0.645, 0.3390), (-0.0012, 0.0012, -0.650, -0.645, 0.3630))),
        ('front_ear-1', box(-0.0105, -0.0070, 0.3390, 0.3660, -0.652, -0.644)),
        ('front_ear1', box(0.0070, 0.0105, 0.3390, 0.3660, -0.652, -0.644))]),
    # Own hooded rear aperture (centre 0.185 at z 0.364) and own front post between guard ears (tip 0.185 at z -0.400): marks only.
    'quad_rocket_launcher': (0.1850, 0.364, -0.400, []),
    # Own hooded rear aperture (centre 0.110 at z -0.030) and own front post between ears (tip 0.110 at z -0.460): marks only.
    'rocket_launcher': (0.1100, -0.030, -0.460, []),
    # Receiver top 0.094 at z 0.08 (0.088 at its edges, x 0.016), barrel 0.082-0.088 at z -0.42. The ghost ring hides at the hip, so
    # the rear reads there by two ears on a flared base, their tops on the line, and the front by a brass bead topping the post.
    'pump_shotgun': (0.1113, 0.080, -0.420, [
        ('rear_base', taper((-0.0150, 0.0150, 0.072, 0.088, 0.0878), (-0.0235, 0.0235, 0.073, 0.087, 0.0953))),
        ('rear_stem', box(-0.0060, 0.0060, 0.0893, 0.0973, 0.076, 0.084)),
        ('rear_ring', ring(0.1113, 0.080, 0.016, 0.008, 0.008)),
        ('rear_ear-1', box(-0.0225, -0.0175, 0.0953, 0.1113, 0.075, 0.085)),
        ('rear_ear1', box(0.0175, 0.0225, 0.0953, 0.1113, 0.075, 0.085)),
        ('front_post', box(-0.0021, 0.0021, 0.0822, 0.1088, -0.423, -0.417)),
        ('front_ear-1', box(-0.0071, -0.0041, 0.0812, 0.1113, -0.423, -0.417)),
        ('front_ear1', box(0.0041, 0.0071, 0.0812, 0.1113, -0.423, -0.417)),
        ('front_bead', ring(0.1088, -0.420, 0.0025, 0.0003, 0.005))]),
}


def load(path):
    b = open(path, 'rb').read()
    jl = struct.unpack_from('<I', b, 12)[0]
    j = json.loads(b[20:20 + jl])
    return j, bytearray(b[20 + jl + 8:])


def save(path, j, bin_):
    while len(bin_) % 4:
        bin_.append(0)
    j['buffers'] = [{'byteLength': len(bin_)}]
    js = json.dumps(j, separators=(',', ':')).encode()
    js += b' ' * (-len(js) % 4)
    out = struct.pack('<III', 0x46546C67, 2, 28 + len(js) + len(bin_))
    out += struct.pack('<II', len(js), 0x4E4F534A) + js + struct.pack('<II', len(bin_), 0x004E4942) + bytes(bin_)
    open(path, 'wb').write(out)


def strip(j, bin_):
    """Drop the added sight nodes and everything only they used, then compact the buffer."""
    keep = [i for i, n in enumerate(j['nodes']) if not n.get('name', '').startswith(STRIP)]
    nmap = {o: k for k, o in enumerate(keep)}
    j['nodes'] = [j['nodes'][i] for i in keep]
    for n in j['nodes']:
        if 'children' in n:
            n['children'] = [nmap[c] for c in n['children'] if c in nmap]
    for s in j['scenes']:
        s['nodes'] = [nmap[c] for c in s['nodes'] if c in nmap]
    used = sorted({n['mesh'] for n in j['nodes'] if 'mesh' in n})
    mmap = {o: k for k, o in enumerate(used)}
    j['meshes'] = [j['meshes'][i] for i in used]
    for n in j['nodes']:
        if 'mesh' in n:
            n['mesh'] = mmap[n['mesh']]
    acc = set()
    for m in j['meshes']:
        for p in m['primitives']:
            acc |= set(p['attributes'].values())
            if 'indices' in p:
                acc.add(p['indices'])
            for t in p.get('targets', []):
                acc |= set(t.values())
    for s in j.get('skins', []):
        if 'inverseBindMatrices' in s:
            acc.add(s['inverseBindMatrices'])
    for a in j.get('animations', []):
        for sm in a['samplers']:
            acc |= {sm['input'], sm['output']}
    acc = sorted(acc)
    amap = {o: k for k, o in enumerate(acc)}
    j['accessors'] = [j['accessors'][i] for i in acc]

    def remap_acc(d):
        return {k: amap[v] for k, v in d.items()}
    for m in j['meshes']:
        for p in m['primitives']:
            p['attributes'] = remap_acc(p['attributes'])
            if 'indices' in p:
                p['indices'] = amap[p['indices']]
            if 'targets' in p:
                p['targets'] = [remap_acc(t) for t in p['targets']]
    for s in j.get('skins', []):
        if 'inverseBindMatrices' in s:
            s['inverseBindMatrices'] = amap[s['inverseBindMatrices']]
    for a in j.get('animations', []):
        for sm in a['samplers']:
            sm['input'], sm['output'] = amap[sm['input']], amap[sm['output']]
    views = sorted({a['bufferView'] for a in j['accessors'] if 'bufferView' in a} | {im['bufferView'] for im in j.get('images', []) if 'bufferView' in im})
    out = bytearray()
    vmap = {}
    for k, o in enumerate(views):
        bv = j['bufferViews'][o]
        while len(out) % 4:
            out.append(0)
        start = bv.get('byteOffset', 0)
        chunk = bin_[start:start + bv['byteLength']]
        bv['byteOffset'] = len(out)
        out += chunk
        vmap[o] = k
    j['bufferViews'] = [j['bufferViews'][i] for i in views]
    for a in j['accessors']:
        if 'bufferView' in a:
            a['bufferView'] = vmap[a['bufferView']]
    for im in j.get('images', []):
        if 'bufferView' in im:
            im['bufferView'] = vmap[im['bufferView']]
    mats = sorted({p['material'] for m in j['meshes'] for p in m['primitives'] if 'material' in p})
    if len(mats) < len(j.get('materials', [])):
        # Drop every unused material: the stripped sight material (the rebuilt parts recreate exactly one) and the source
        # materials a texture bake leaves in the list after it merged their faces into one atlas.
        xmap = {o: k for k, o in enumerate(mats)}
        j['materials'] = [j['materials'][i] for i in mats]
        for m in j['meshes']:
            for p in m['primitives']:
                if 'material' in p:
                    p['material'] = xmap[p['material']]
    return out


def world_tris(j, bin_):
    def acc(i):
        a = j['accessors'][i]
        bv = j['bufferViews'][a['bufferView']]
        off = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
        n = {'VEC3': 3, 'SCALAR': 1}[a['type']]
        fmt = {5126: 'f', 5123: 'H', 5125: 'I', 5121: 'B'}[a['componentType']]
        stride = bv.get('byteStride', struct.calcsize(fmt) * n)
        return [struct.unpack_from('<' + fmt * n, bin_, off + k * stride) for k in range(a['count'])]

    def mat(n):
        if 'matrix' in n:
            m = n['matrix']
            return [[m[c * 4 + r] for c in range(4)] for r in range(4)]
        t, (x, y, z, w), s = n.get('translation', [0, 0, 0]), n.get('rotation', [0, 0, 0, 1]), n.get('scale', [1, 1, 1])
        R = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)], [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
             [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
        return [[R[i][k] * s[k] for k in range(3)] + [t[i]] for i in range(3)] + [[0, 0, 0, 1]]
    out = []

    def walk(ni, P):
        n = j['nodes'][ni]
        L = mat(n)
        M = [[sum(P[i][k] * L[k][c] for k in range(4)) for c in range(4)] for i in range(4)]
        if 'mesh' in n:
            for p in j['meshes'][n['mesh']]['primitives']:
                vs = [tuple(M[i][0] * v[0] + M[i][1] * v[1] + M[i][2] * v[2] + M[i][3] for i in range(3)) for v in acc(p['attributes']['POSITION'])]
                idx = [i[0] for i in acc(p['indices'])] if 'indices' in p else list(range(len(vs)))
                out.extend((vs[idx[k]], vs[idx[k + 1]], vs[idx[k + 2]]) for k in range(0, len(idx) - 2, 3))
        for c in n.get('children', []):
            walk(c, M)
    for r in j['scenes'][j.get('scene', 0)]['nodes']:
        walk(r, [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]])
    return out


def top_at(T, x, z):
    best = None
    for a, b, c in T:
        d = (b[2] - c[2]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[2] - c[2])
        if abs(d) < 1e-12:
            continue
        l1 = ((b[2] - c[2]) * (x - c[0]) + (c[0] - b[0]) * (z - c[2])) / d
        l2 = ((c[2] - a[2]) * (x - c[0]) + (a[0] - c[0]) * (z - c[2])) / d
        l3 = 1 - l1 - l2
        if min(l1, l2, l3) >= -1e-9:
            y = l1 * a[1] + l2 * b[1] + l3 * c[1]
            best = y if best is None else max(best, y)
    return best


def faces(shape):
    """[(polygon verts, outward hint)]"""
    if shape[0] == 'frustum':
        (bx0, bx1, bz0, bz1, by), (tx0, tx1, tz0, tz1, ty) = shape[1], shape[2]
        b = [(bx0, by, bz0), (bx1, by, bz0), (bx1, by, bz1), (bx0, by, bz1)]
        t = [(tx0, ty, tz0), (tx1, ty, tz0), (tx1, ty, tz1), (tx0, ty, tz1)]
        c = [sum(v[i] for v in b + t) / 8 for i in range(3)]
        polys = [b, t] + [[b[i], b[(i + 1) % 4], t[(i + 1) % 4], t[i]] for i in range(4)]
        return [(p, [sum(v[i] for v in p) / len(p) - c[i] for i in range(3)]) for p in polys]
    _, cy, cz, ro, ri, depth = shape
    seg = 28
    out = []
    for i in range(seg):
        a0, a1 = 2 * math.pi * i / seg, 2 * math.pi * (i + 1) / seg
        am = (a0 + a1) / 2
        rad = (math.cos(am), math.sin(am), 0)

        def p(r, a, z):
            return (r * math.cos(a), cy + r * math.sin(a), z)
        zb, zf = cz + depth / 2, cz - depth / 2
        out.append(([p(ro, a0, zb), p(ro, a1, zb), p(ro, a1, zf), p(ro, a0, zf)], rad))
        out.append(([p(ri, a0, zb), p(ri, a1, zb), p(ri, a1, zf), p(ri, a0, zf)], [-v for v in rad]))
        out.append(([p(ro, a0, zb), p(ro, a1, zb), p(ri, a1, zb), p(ri, a0, zb)], (0, 0, 1)))
        out.append(([p(ro, a0, zf), p(ro, a1, zf), p(ri, a1, zf), p(ri, a0, zf)], (0, 0, -1)))
    return out


def sub(a, b):
    return [a[i] - b[i] for i in range(3)]


def cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


def flat(shape):
    """Flat-shaded triangle soup: positions, normals."""
    P, N = [], []
    for poly, hint in faces(shape):
        n = [0.0, 0.0, 0.0]
        for k in range(1, len(poly) - 1):
            n = [n[i] + cross(sub(poly[k], poly[0]), sub(poly[k + 1], poly[0]))[i] for i in range(3)]
        if sum(n[i] * hint[i] for i in range(3)) < 0:
            poly = poly[::-1]
            n = [-v for v in n]
        L = math.sqrt(sum(v * v for v in n)) or 1.0
        n = [v / L for v in n]
        for k in range(1, len(poly) - 1):
            for v in (poly[0], poly[k], poly[k + 1]):
                P.append(v)
                N.append(n)
    return P, N


def footprint(shape):
    if shape[0] == 'frustum':
        x0, x1, z0, z1, y = shape[1]
        return y, [(x, z) for x in (x0, (x0 + x1) / 2, x1) for z in (z0, (z0 + z1) / 2, z1)]
    return None, []


def add_parts(j, bin_, parts, T, name):
    mi = len(j['materials'])
    j['materials'].append({'name': 'sight_metal', 'pbrMetallicRoughness': {'baseColorFactor': [0.035, 0.035, 0.04, 1.0], 'metallicFactor': 0.3, 'roughnessFactor': 0.75}})
    if any(p.startswith('front_bead') for p, _ in parts):
        j['materials'].append({'name': 'sight_bead', 'emissiveFactor': [0.09, 0.065, 0.02],
                               'pbrMetallicRoughness': {'baseColorFactor': [0.86, 0.64, 0.28, 1.0], 'metallicFactor': 1.0, 'roughnessFactor': 0.3}})
    for pname, shape in parts:
        y0, feet = footprint(shape)
        for x, z in feet:
            top = top_at(T, x, z)
            if top is None or y0 > top + 0.0005:
                sys.exit('%s: %s floats at (%.4f, %.4f): bottom %.4f, model top %s' % (name, pname, x, z, y0, top))
        P, N = flat(shape)
        T.extend((P[k], P[k + 1], P[k + 2]) for k in range(0, len(P), 3))  # later parts may seat on this one
        while len(bin_) % 4:
            bin_.append(0)
        pv = len(j['bufferViews'])
        for arr in (P, N):
            off = len(bin_)
            for v in arr:
                bin_ += struct.pack('<3f', *v)
            j['bufferViews'].append({'buffer': 0, 'byteOffset': off, 'byteLength': len(arr) * 12, 'target': 34962})
        pa = len(j['accessors'])
        j['accessors'].append({'bufferView': pv, 'componentType': 5126, 'count': len(P), 'type': 'VEC3',
                               'min': [min(v[i] for v in P) for i in range(3)], 'max': [max(v[i] for v in P) for i in range(3)]})
        j['accessors'].append({'bufferView': pv + 1, 'componentType': 5126, 'count': len(N), 'type': 'VEC3'})
        mat = mi + 1 if pname.startswith('front_bead') else mi
        j['meshes'].append({'name': pname, 'primitives': [{'attributes': {'POSITION': pa, 'NORMAL': pa + 1}, 'material': mat}]})
        j['nodes'].append({'name': pname, 'mesh': len(j['meshes']) - 1})
        j['scenes'][0]['nodes'].append(len(j['nodes']) - 1)


def run(path, name):
    line, rz, fz, parts = SPECS[name]
    j, bin_ = load(path)
    bin_ = strip(j, bin_)
    T = world_tris(j, bin_)
    # The sight line must clear the model between the stations, or the gun's own body sits in the picture.
    for i in range(1, 20):
        z = rz + (fz - rz) * i / 20.0
        top = top_at(T, 0.0, z)
        if top is not None and top > line + 0.0005:
            sys.exit('%s: model top %.4f at z %.3f is above the sight line %.4f' % (name, top, z, line))
    if parts:
        add_parts(j, bin_, parts, T, name)
    for mark, z in (('sight_rear', rz), ('sight_front', fz)):
        j['nodes'].append({'name': mark, 'translation': [0.0, line, z]})
        j['scenes'][0]['nodes'].append(len(j['nodes']) - 1)
    if name in BORE:
        j['nodes'].append({'name': 'muzzle_bore', 'translation': list(BORE[name])})
        j['scenes'][0]['nodes'].append(len(j['nodes']) - 1)
    save(path, j, bin_)
    print('SIGHTED %s line y %.4f rear z %.3f front z %.3f parts %s' % (name, line, rz, fz, ','.join(p for p, _ in parts) or 'own'))


if __name__ == '__main__':
    dst, names = sys.argv[1], sys.argv[2:] or list(SPECS)
    for n in names:
        run(os.path.join(dst, n + '.glb'), n)
