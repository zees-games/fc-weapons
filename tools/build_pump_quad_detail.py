"""Adds real modelled detail (fore-end, shroud, bands, rib, swivels, buttpad; four launch tubes, rails, straps, bolts, loops) to the
pump_shotgun / quad_rocket_launcher sources, which otherwise read as stick / box. Run on the pristine (bevelled) GLBs, then texbake:
  blender -b -P np.py -P tools/build_pump_quad_detail.py -- <pump_shotgun|quad_rocket_launcher> <in.glb> <out.glb>
Coordinates in the helpers are glTF (x right, y up, muzzle -Z, origin at the grip); every new face points at one clean source-atlas
texel (the bake picks the colour from it and adds AO / edge wear), so no new atlas is needed."""
import bpy, bmesh, sys, math
from mathutils import Matrix, Vector

a = sys.argv[sys.argv.index('--') + 1:]
weapon, src, dst = a
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)

# palette texels (blender uv, v up) in each source atlas
PAL = {
    'pump_shotgun': {'M': (0.3125, 0.18), 'W': (0.586, 0.785), 'D': (0.586, 0.258)},
    'quad_rocket_launcher': {'G': (0.098, 0.805), 'M': (0.723, 0.14), 'D': (0.9375, 0.414), 'B': (0.376, 0.805)},
}[weapon]

bm = bmesh.new()
uvl = bm.loops.layers.uv.new('UVMap')


def g2b(x, y, z):
    return Vector((x, -z, y))


def finish(before, grp, bevel):
    new = [f for f in bm.faces if f not in before]
    if bevel:
        edges = list({e for f in new for e in f.edges})
        bmesh.ops.bevel(bm, geom=edges, offset=bevel, segments=2, affect='EDGES')
        new = [f for f in bm.faces if f not in before]
    u = PAL[grp]
    for f in new:
        for l in f.loops:
            l[uvl].uv = u


ROT = {'z': Matrix.Rotation(math.radians(90), 4, 'X'), 'x': Matrix.Rotation(math.radians(90), 4, 'Y'), 'y': Matrix.Identity(4)}


def box(c, s, grp, bevel=0.0015, rotx=0.0):
    before = set(bm.faces)
    r = bmesh.ops.create_cube(bm, size=1.0)
    m = Matrix.Translation(g2b(*c)) @ Matrix.Rotation(math.radians(rotx), 4, 'X') @ Matrix.Diagonal((s[0], s[2], s[1], 1))
    bmesh.ops.transform(bm, matrix=m, verts=r['verts'])
    finish(before, grp, min(bevel, min(s) * 0.45))


def cyl(c, r, length, axis, grp, seg=16, bevel=0.0):
    before = set(bm.faces)
    res = bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r, depth=length)
    bmesh.ops.transform(bm, matrix=Matrix.Translation(g2b(*c)) @ ROT[axis], verts=res['verts'])
    finish(before, grp, bevel)


def torus(c, big, small, axis, grp, n=20, m=6):
    """Ring with its hole along `axis` (x, y or z of glTF)."""
    before = set(bm.faces)
    vs = []
    for i in range(n):
        A = 2 * math.pi * i / n
        row = []
        for j in range(m):
            B = 2 * math.pi * j / m
            rr = big + small * math.cos(B)
            row.append(bm.verts.new((rr * math.cos(A), rr * math.sin(A), small * math.sin(B))))
        vs.append(row)
    for i in range(n):
        for j in range(m):
            bm.faces.new((vs[i][j], vs[(i + 1) % n][j], vs[(i + 1) % n][(j + 1) % m], vs[i][(j + 1) % m]))
    bmesh.ops.transform(bm, matrix=Matrix.Translation(g2b(*c)) @ ROT[axis], verts=[v for r_ in vs for v in r_])
    finish(before, grp, 0)


if weapon == 'pump_shotgun':
    # fore-end (wood) with grooves, end caps
    box((0, .049, -.2075), (.043, .040, .150), 'W', .004)
    for i in range(9):
        z = -.27 + i * .0145
        for sx in (1, -1):
            box((.0217 * sx, .049, z), (.0016, .030, .0035), 'D', .0004)
    box((0, .049, -.1285), (.046, .044, .004), 'M', .0012)
    box((0, .049, -.2875), (.046, .044, .004), 'M', .0012)
    # vented barrel shroud
    cyl((0, .078, -.352), .0125, .085, 'z', 'M', 20)
    for i in range(5):
        z = -.385 + i * .015
        for sx in (1, -1):
            box((.0127 * sx, .078, z), (.002, .006, .008), 'D', .0003)
        box((0, .0905, z), (.006, .002, .008), 'D', .0003)
    # clamp bands, magazine cap + swivel, muzzle ring and bore, top rib
    for z in (-.428, -.292):
        box((0, .064, z), (.026, .054, .008), 'D', .002)
    cyl((0, .049, -.42), .0095, .02, 'z', 'M', 16)
    cyl((0, .049, -.412), .0118, .007, 'z', 'M', 16)
    torus((0, .0335, -.42), .0048, .0013, 'x', 'M')
    cyl((0, .078, -.4405), .0108, .007, 'z', 'M', 18)
    cyl((0, .078, -.4445), .0058, .0012, 'z', 'D', 12)
    box((0, .0868, -.24), (.004, .0025, .38), 'M', .0008)
    # receiver: top ridge, rivets, cross-bolt safety
    box((0, .0925, .04), (.016, .003, .12), 'M', .001)
    for z in (-.02, .14):
        for y in (.05, .08):
            for sx in (1, -1):
                cyl((.0186 * sx, y, z), .0026, .0022, 'x', 'M', 10)
    cyl((0, .05, .12), .0038, .040, 'x', 'D', 12)
    # stock: slanted butt pad, bottom sling swivel
    box((0, -.038, .4295), (.0385, .108, .007), 'D', .002, rotx=-6)
    torus((0, -.047, .277), .0055, .0014, 'x', 'M')
    box((0, -.045, .277), (.006, .004, .008), 'M', .0006)
elif weapon == 'quad_rocket_launcher':
    # four launch tubes on the front face: collar, tube, lip, dark bore
    for tx in (.056, -.056):
        for ty in (.088, -.008):
            cyl((tx, ty, -.418), .0445, .008, 'z', 'M', 24)
            cyl((tx, ty, -.4305), .038, .033, 'z', 'D', 24)
            cyl((tx, ty, -.445), .040, .004, 'z', 'M', 24)
            cyl((tx, ty, -.4476), .031, .0016, 'z', 'B', 20)
    # picatinny-style top rails (either side of the sight posts) with slots
    for sx in (.05, -.05):
        box((sx, .1405, -.115), (.014, .011, .53), 'M', .0012)
        for i in range(17):
            box((sx, .1405, -.35 + i * .03), (.0146, .0114, .004), 'D', .0003)
    # reinforcing straps that wrap the body, with bolt heads on both sides
    for z in (-.33, -.06, .12):
        box((0, .015, z), (.226, .248, .014), 'G', .003)
        for y in (.10, .015, -.07):
            for sx in (1, -1):
                cyl((.1135 * sx, y, z), .0045, .003, 'x', 'M', 10)
    # lower skid rails
    for sx in (.05, -.05):
        box((sx, -.108, -.17), (.012, .006, .42), 'D', .0015)
    # rear shoulder plate bolts
    for bx in (.085, -.085):
        for by in (.105, -.075):
            cyl((bx, by, .2935), .006, .004, 'z', 'M', 10)
    # side sling loops with mounting pads
    for sx in (1, -1):
        for z in (.12, -.36):
            box((.112 * sx, .07, z), (.003, .02, .02), 'M', .001)
            torus((.1175 * sx, .07, z), .011, .0022, 'x', 'D')

bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
me = bpy.data.meshes.new('detail')
bm.to_mesh(me)
obj = bpy.data.objects.new('detail', me)
bpy.context.scene.collection.objects.link(obj)
ref = [o for o in bpy.data.objects if o.type == 'MESH' and o.data.materials and o.data.materials[0].name != 'sight_metal'][0]
me.materials.append(ref.data.materials[0])
# top level like the sight nodes: the weapon root carries a scale / rotation, the detail is built in world space
bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', export_apply=False)
print('DETAIL faces', len(me.polygons))
