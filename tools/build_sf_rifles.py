"""Builds the shipped GLB of a rifle from a textured high-poly CC-BY source (credited in CREDITS.md, licence.json and
AwWeaponArt.CREDITS). The source's own PBR textures are kept, scaled to TEX px and written JPEG (the web download):
  blender -b -P tools/build_sf_rifles.py -- <recipe> <source scene.gltf> <out .glb> [tex px]
Recipes below give the source frame: which axis the muzzle points along, the grip point that becomes the origin, the overall
length in metres, and which source meshes make each node (unlisted meshes go to `body`, `drop` is left out). A source that
welds parts into one mesh lists it in `loose`: it is cut into its loose pieces, and a piece wholly inside a `boxes` box (source
units, min and max corners) goes to that box's node, or is left out when the node is `drop`.
Nodes, origins all at the model origin: body, magazine (the row's `mag_node`), bolt (the row's `bolt_node`).
Frame written: muzzle -Z, up +Y, origin at the top of the pistol grip, the same as every other model in the pack."""
import bpy, sys, math
from mathutils import Matrix, Vector

RECIPES = {
	# Howa Type 89 by 8sianDude (CC-BY-4.0). Source: Z up, muzzle -Y, 7.58 units long; 0.916 m real.
	'burst_rifle': {'length': 0.916, 'muzzle': '-Y', 'grip': (0.0, 0.80, 0.85),
		'parts': {'magazine': ('20rnd_mag', 'mag_follower'), 'bolt': ('bolt_type89',)},
		'drop': ('bipod', 'bullets', 'bullet_chamber'),
		# The source stock carries a decal sticker baked into its base colour: painted out (saturation > 0.15, plus the light
		# pixels > 0.35 around it, grown 24 px).
		'paint_out': {'type89_lower_bipod_baseColor': (0.15, 0.35, 24)}},
	# G3 by Ulrik Langvandsbraten (CC-BY-4.0). Source: Z up, muzzle +Y, about 121 units long; 1.025 m real. The scope, the
	# suppressor (with its bipod), the smoke plane and the spare mesh copies laid out beside the gun are left out.
	'battle_rifle': {'length': 1.025, 'muzzle': '+Y', 'grip': (-2.8, -20.0, 0.0),
		'drop': ('Scope001', 'Silencer001', 'Plane006', 'MainBody003', 'Grip002'),
		'loose': ('MainBody001',),
		'boxes': {'magazine': ((-4.5, -5.6, -15.3), (-1.0, 4.0, 3.9)), 'drop': ((5.0, -100.0, -100.0), (100.0, 100.0, 100.0))}},
	# Sci-fi energy rifle by Fainclaw (CC-BY-4.0), the charge_rifle. Source: Z up, muzzle -Y, 0.84 units long; 0.9 m here. No
	# magazine (the cell reload brings its own), so every mesh, the optic glass too, is the body.
	'energy_rifle': {'length': 0.9, 'muzzle': '-Y', 'grip': (0.0, 0.1066, -0.045), 'drop': ()},
}

args = sys.argv[sys.argv.index('--') + 1:]
R = RECIPES[args[0]]
SRC, OUT = args[1], args[2]
TEX = int(args[3]) if len(args) > 3 else 2048

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
for o in [o for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith(R.get('loose', ()))]:
	bpy.ops.object.select_all(action='DESELECT')
	o.select_set(True)
	bpy.context.view_layer.objects.active = o
	bpy.ops.object.mode_set(mode='EDIT')
	bpy.ops.mesh.select_all(action='SELECT')
	bpy.ops.mesh.separate(type='LOOSE')
	bpy.ops.object.mode_set(mode='OBJECT')
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
lo = [min((o.matrix_world @ v.co)[i] for o in meshes for v in o.data.vertices) for i in range(3)]
hi = [max((o.matrix_world @ v.co)[i] for o in meshes for v in o.data.vertices) for i in range(3)]


def inside(o, box):
	return all(box[0][i] <= (o.matrix_world @ v.co)[i] <= box[1][i] for v in o.data.vertices for i in range(3))


def part_of(o):
	name = o.name
	if any(name.startswith(d) for d in R['drop']):
		return None
	if name.startswith(R.get('loose', ())):
		for part, box in R.get('boxes', {}).items():
			if inside(o, box):
				return None if part == 'drop' else part
	for part, prefixes in R.get('parts', {}).items():
		if any(name.startswith(p) for p in prefixes):
			return part
	return 'body'


# Muzzle to Blender +Y (glTF -Z after the Y-up export), grip to the origin, scaled to the real length.
axis = R['muzzle']
turn = {'-Y': Matrix.Rotation(math.pi, 4, 'Z'), '+Y': Matrix.Identity(4), '-X': Matrix.Rotation(-math.pi / 2, 4, 'Z'),
	'+X': Matrix.Rotation(math.pi / 2, 4, 'Z')}[axis]
keep = [o for o in meshes if part_of(o) is not None]
ax = 1 if axis.endswith('Y') else 0
span = max((o.matrix_world @ v.co)[ax] for o in keep for v in o.data.vertices) - min((o.matrix_world @ v.co)[ax] for o in keep for v in o.data.vertices)
S = R['length'] / span
TO_GUN = Matrix.Scale(S, 4) @ turn @ Matrix.Translation(-Vector(R['grip']))

groups = {}
for o in meshes:
	part = part_of(o)
	if part is None:
		bpy.data.objects.remove(o, do_unlink=True)
		continue
	o.data = o.data.copy()
	o.data.transform(TO_GUN @ o.matrix_world)
	o.parent = None
	o.matrix_world = Matrix.Identity(4)
	groups.setdefault(part, []).append(o)
for o in [o for o in bpy.data.objects if o.type != 'MESH']:
	bpy.data.objects.remove(o, do_unlink=True)

root = bpy.data.objects.new(args[0], None)
bpy.context.scene.collection.objects.link(root)
for part, objs in sorted(groups.items()):
	bpy.ops.object.select_all(action='DESELECT')
	for o in objs:
		o.select_set(True)
	bpy.context.view_layer.objects.active = objs[0]
	if len(objs) > 1:
		bpy.ops.object.join()
	ob = bpy.context.view_layer.objects.active
	ob.name = ob.data.name = part
	ob.parent = root
	vs = [v.co for v in ob.data.vertices]
	print('NODE', part, 'tris', sum(len(p.vertices) - 2 for p in ob.data.polygons),
		'bounds', [round(min(v[i] for v in vs), 3) for i in range(3)], [round(max(v[i] for v in vs), 3) for i in range(3)])

def paint_out(img, sat_min, light_min, grow):
	"""Fills the saturated (decal) pixels and the light ones inside their box, grown by `grow` px, with the median colour of the
	plain pixels around them."""
	import numpy as np
	w, h = img.size
	a = np.empty(w * h * 4, np.float32)
	img.pixels.foreach_get(a)
	a = a.reshape(h, w, 4)
	m = (a[:, :, :3].max(2) - a[:, :, :3].min(2)) > sat_min
	ys, xs = np.nonzero(m)
	if len(ys):
		box = (slice(max(0, ys.min() - grow), ys.max() + grow + 1), slice(max(0, xs.min() - grow), xs.max() + grow + 1))
		m[box] |= a[box][:, :, :3].max(2) > light_min
	for _ in range(grow):
		g = m.copy()
		g[1:] |= m[:-1]; g[:-1] |= m[1:]; g[:, 1:] |= m[:, :-1]; g[:, :-1] |= m[:, 1:]
		m = g
	ys, xs = np.nonzero(m)
	if not len(ys):
		return
	box = (slice(ys.min(), ys.max() + 1), slice(xs.min(), xs.max() + 1))
	plain = a[box][~m[box]]
	a[m] = np.median(plain, axis=0) if len(plain) else a[~m].mean(0)
	img.pixels.foreach_set(a.ravel())
	img.update()
	print('PAINTED', img.name, int(m.sum()), 'px')


for img in bpy.data.images:
	for name, spec in R.get('paint_out', {}).items():
		if img.name.startswith(name):
			paint_out(img, *spec)
	if img.size[0] > TEX or img.size[1] > TEX:
		f = TEX / max(img.size[0], img.size[1])
		img.scale(max(1, int(img.size[0] * f)), max(1, int(img.size[1] * f)))
	print('IMAGE', img.name, tuple(img.size))
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_apply=True, export_yup=True, export_texcoords=True,
	export_normals=True, export_materials='EXPORT', export_image_format='JPEG', export_jpeg_quality=92)
print('SCALE', round(S, 5), 'WROTE', OUT)
