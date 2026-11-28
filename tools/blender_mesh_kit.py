"""Shared Blender mesh kit for the own-work model builders (build_small_parts.py, build_thrown_melee.py): parts are built in Godot space
(x right, y up, -z forward) as one-material meshes, then exported as one GLB per model with smooth shading, welded seams and sharp
edges past 40 degrees. Import it from a script run by blender -b -P (the builder puts tools/ on sys.path)."""
import bpy, bmesh, os, math

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
    print('build: %s %d parts %d tris' % (name, len(parts), tris))
