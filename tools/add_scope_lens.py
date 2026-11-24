"""Adds a lens, a reticle and an eyecup to a scoped GLB, so the scope looks right where only the model is drawn (the nightly model viewer).
No Blender needed: the glTF JSON and binary chunk are edited in place. Four nodes are added at the scope's ocular, each its own mesh:
scope_lens (a tinted glass disc), scope_reticle (crosshair, mil dots and a ring), scope_eyecup (a rubber eyecup) and scope_eyecup_lip (a bright ring round the glass).
In the game, AwScopeGlass (addons/fc_weapons/view/aw_scope_glass.gd) hides all three and draws live glass and housing instead.
Run: python3 -I tools/add_scope_lens.py <in.glb> <out.glb> [--ocular X Y Z RADIUS]
The default ocular is the sniper's (sniper_ph.glb: the eyepiece end of the scope tube, tube axis along -Z, eye toward +Z). Run on a copy of the
baked file; running on a file that already has the nodes replaces them."""
import json, math, struct, sys

NAMES = ("scope_lens", "scope_reticle", "scope_eyecup", "scope_eyecup_lip")
SIDES = 48


def disc(c, r, z):
    v = [(c[0], c[1], z)] + [(c[0] + r * math.cos(math.tau * i / SIDES), c[1] + r * math.sin(math.tau * i / SIDES), z) for i in range(SIDES)]
    idx = [t for i in range(SIDES) for t in (0, 1 + i, 1 + (i + 1) % SIDES)]
    return v, [(0, 0, 1)] * len(v), idx


def quad(c, hx, hy, z):
    v = [(c[0] - hx, c[1] - hy, z), (c[0] + hx, c[1] - hy, z), (c[0] + hx, c[1] + hy, z), (c[0] - hx, c[1] + hy, z)]
    return v, [(0, 0, 1)] * 4, [0, 1, 2, 0, 2, 3]


def ring(c, r_in, r_out, z):
    v, n, idx = [], [], []
    for i in range(SIDES):
        a = math.tau * i / SIDES
        for r in (r_in, r_out):
            v.append((c[0] + r * math.cos(a), c[1] + r * math.sin(a), z))
            n.append((0, 0, 1))
    for i in range(SIDES):
        a, b, c2, d = 2 * i, 2 * i + 1, 2 * ((i + 1) % SIDES), 2 * ((i + 1) % SIDES) + 1
        idx += [a, b, d, a, d, c2]
    return v, n, idx


def band(c, profile):
    """A surface of revolution about the tube axis: profile is [(z, radius)] from the glass toward the eye; normals face outward."""
    v, n, idx = [], [], []
    for k in range(len(profile) - 1):
        (z0, r0), (z1, r1) = profile[k], profile[k + 1]
        base = len(v)
        for i in range(SIDES):
            a = math.tau * i / SIDES
            ca, sa = math.cos(a), math.sin(a)
            dr, dz = r1 - r0, z1 - z0
            ln = math.hypot(dr, dz) or 1.0
            nrm = (ca * dz / ln, sa * dz / ln, -dr / ln)
            v += [(c[0] + r0 * ca, c[1] + r0 * sa, z0), (c[0] + r1 * ca, c[1] + r1 * sa, z1)]
            n += [nrm, nrm]
        for i in range(SIDES):
            a, b, c2, d = base + 2 * i, base + 2 * i + 1, base + 2 * ((i + 1) % SIDES), base + 2 * ((i + 1) % SIDES) + 1
            idx += [a, b, d, a, d, c2]
    return v, n, idx


def merge(parts):
    v, n, idx = [], [], []
    for pv, pn, pi in parts:
        idx += [i + len(v) for i in pi]
        v += pv
        n += pn
    return v, n, idx


def main():
    src, dst = sys.argv[1], sys.argv[2]
    ocular = (0.0, 0.107, -0.0757, 0.006)
    if "--ocular" in sys.argv:
        at = sys.argv.index("--ocular")
        ocular = tuple(float(x) for x in sys.argv[at + 1:at + 5])
    cx, cy, ez, r = ocular
    c = (cx, cy)
    data = open(src, "rb").read()
    jlen = struct.unpack("<I", data[12:16])[0]
    g = json.loads(data[20:20 + jlen])
    blob = bytearray(data[28 + jlen:28 + jlen + struct.unpack("<I", data[20 + jlen:24 + jlen])[0]])
    # Drop any earlier run's nodes (their mesh data stays in the buffer, unreferenced).
    g["nodes"] = [nd for nd in g["nodes"] if nd.get("name") not in NAMES]
    g["scenes"][0]["nodes"] = list(range(len(g["nodes"])))  # every node of these weapon GLBs is a scene root

    def material(name, base, metallic, rough, emissive=None, blend=False):
        m = {"name": name, "pbrMetallicRoughness": {"baseColorFactor": list(base), "metallicFactor": metallic, "roughnessFactor": rough}}
        if emissive:
            m["emissiveFactor"] = list(emissive)
        if blend:
            m["alphaMode"] = "BLEND"
        g["materials"].append(m)
        return len(g["materials"]) - 1

    glass = material("scope_glass", (0.10, 0.22, 0.24, 0.55), 0.0, 0.05, (0.0, 0.02, 0.025), blend=True)
    black = material("scope_reticle", (0.01, 0.01, 0.01, 1.0), 0.0, 0.9)
    rubber = material("scope_rubber", (0.025, 0.025, 0.028, 1.0), 0.0, 0.85)
    lip = material("scope_lip", (0.45, 0.46, 0.48, 1.0), 1.0, 0.3)

    def add_mesh(name, parts, mat):
        v, n, idx = merge(parts)
        views = []
        for payload, fmt, target in ((b"".join(struct.pack("<fff", *p) for p in v), None, 34962), (b"".join(struct.pack("<fff", *p) for p in n), None, 34962),
                                     (b"".join(struct.pack("<I", i) for i in idx), None, 34963)):
            while len(blob) % 4:
                blob.append(0)
            g["bufferViews"].append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(payload), "target": target})
            blob.extend(payload)
            views.append(len(g["bufferViews"]) - 1)
        lo = [min(p[k] for p in v) for k in range(3)]
        hi = [max(p[k] for p in v) for k in range(3)]
        g["accessors"] += [{"bufferView": views[0], "componentType": 5126, "count": len(v), "type": "VEC3", "min": lo, "max": hi},
                           {"bufferView": views[1], "componentType": 5126, "count": len(n), "type": "VEC3"},
                           {"bufferView": views[2], "componentType": 5125, "count": len(idx), "type": "SCALAR"}]
        a = len(g["accessors"]) - 3
        g["meshes"].append({"name": name, "primitives": [{"attributes": {"POSITION": a, "NORMAL": a + 1}, "indices": a + 2, "material": mat}]})
        g["nodes"].append({"name": name, "mesh": len(g["meshes"]) - 1})
        g["scenes"][0]["nodes"].append(len(g["nodes"]) - 1)

    z = ez + 0.0004  # a hair toward the eye of the eyepiece's end, so the disc covers it
    add_mesh("scope_lens", [disc(c, r * 1.02, z)], glass)
    ticks = [quad(c, r * 0.9, r * 0.012, z + 0.00005), quad(c, r * 0.012, r * 0.9, z + 0.00005), ring(c, r * 0.96, r * 1.0, z + 0.00005)]
    for k in (-3, -2, -1, 1, 2, 3):
        ticks += [quad((cx + k * r * 0.18, cy), r * 0.03, r * 0.03, z + 0.00005), quad((cx, cy + k * r * 0.18), r * 0.03, r * 0.03, z + 0.00005)]
    add_mesh("scope_reticle", ticks, black)
    # The eyecup: a rubber flare from the tube's end toward the eye, and a bright lip round the glass.
    cup = band(c, [(ez + 0.0004, r * 1.25), (ez + 0.003, r * 1.45), (ez + 0.0075, r * 1.6), (ez + 0.0095, r * 1.5)])
    cup2 = ring(c, r * 1.02, r * 1.5, ez + 0.0095)
    add_mesh("scope_eyecup", [cup, cup2], rubber)
    lip_v = merge([ring(c, r * 0.98, r * 1.12, ez + 0.0006), band(c, [(ez + 0.0006, r * 1.12), (ez + 0.0016, r * 1.12)])])
    add_mesh("scope_eyecup_lip", [lip_v], lip)

    g["buffers"][0]["byteLength"] = len(blob)
    js = json.dumps(g, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    while len(blob) % 4:
        blob.append(0)
    out = b"glTF" + struct.pack("<II", 2, 12 + 8 + len(js) + 8 + len(blob))
    out += struct.pack("<I", len(js)) + b"JSON" + js + struct.pack("<I", len(blob)) + b"BIN\0" + bytes(blob)
    open(dst, "wb").write(out)
    print("wrote", dst, "nodes", [nd["name"] for nd in g["nodes"]])


main()
