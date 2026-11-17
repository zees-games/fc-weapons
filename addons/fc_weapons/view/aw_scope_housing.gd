extends RefCounted

## A clean scope tube built in code around a model's baked one: a smooth dark anodised body turned from a profile, with a bright lip round the glass and fine machining rings on the eyecup.
## The baked scopes are low-poly (twelve sides) with mottled texture, and the scope body view (aw_view_model.gd) brings the eyepiece up to fill the screen, so their facets and blotches were the whole picture round the lens. A scope style opts in with `housing`:
## `true` for [constant PROFILE], or an array of `[along, radius]` (or `[along, radius, 1]` for the bright lip) in the ocular's radii. `along` runs from the ocular toward the eye (+Z in the model's space, the muzzle is -Z), from the glass's lip round the eyecup and forward to the objective's face. `housing_sides` sets the sides (default [constant SIDES]). The ocular comes from the style's `ocular` ([x, y, z, radius]). Preloaded by path (no `class_name`), as aw_reload_parts.gd is.

## The marksman's scope measured off its model (tools in the commit message), in ocular radii: lip, eyecup,
## eyepiece, taper, tube, objective bell and its face. It sits a few millimetres outside the baked surfaces so they never poke through.
const PROFILE := [
	[-0.15, 0.98, 1], [0.12, 1.02, 1], [0.24, 1.1, 1],
	[0.28, 1.14], [0.3, 1.38], [0.24, 1.47], [0.1, 1.52],
	[-2.2, 1.52], [-2.45, 1.47], [-3.4, 1.2],
	[-11.1, 1.2], [-11.5, 1.26], [-12.8, 1.8], [-15.4, 1.82],
	[-15.6, 1.76], [-15.6, 1.48],
]
const SIDES := 64
## The body: near-black anodised aluminium, a little metallic so the key light draws a soft line along it.
const BODY_COLOR := Color(0.05, 0.052, 0.058)
## The lip round the glass: bright turned metal, which outlines the lens circle.
const LIP_COLOR := Color(0.32, 0.33, 0.35)

static var _materials: Dictionary = {}


## The housing for [param style] (a weapon's scope style), placed in the model's space; null without `housing` and `ocular`.
static func build(style: Dictionary) -> Node3D:
	var wanted: Variant = style.get("housing", null)
	var ocular: Variant = style.get("ocular", null)
	if not (wanted is Array or (wanted is bool and wanted)) or not (ocular is Array) or (ocular as Array).size() < 4 or float(ocular[3]) <= 0.0:
		return null
	var profile: Array = wanted if wanted is Array else PROFILE
	if profile.size() < 2:
		push_error("AwScopeHousing: a housing profile needs two points or more, got %d." % profile.size())
		return null
	var sides := int(style.get("housing_sides", SIDES))
	if sides < 3:
		push_error("AwScopeHousing: housing_sides must be 3 or more, got %d." % sides)
		return null
	var root := Node3D.new()
	root.name = "ScopeHousing"
	root.position = origin(style)
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "Body"
	mesh_node.mesh = turn(profile, float(ocular[3]), sides)
	root.add_child(mesh_node)
	return root


## Where the housing's origin sits in the model's space: the style's ocular centre.
static func origin(style: Dictionary) -> Vector3:
	var ocular: Variant = style.get("ocular", null)
	if not (ocular is Array) or (ocular as Array).size() < 3:
		return Vector3.ZERO
	return Vector3(float(ocular[0]), float(ocular[1]), float(ocular[2]))


## The mesh turned from [param profile] (see the script's notes) scaled by [param radius], [param sides] round:
## surface 0 the body, surface 1 the lip. Each profile step is its own band, so a corner stays sharp and a band smooth round.
static func turn(profile: Array, radius: float, sides: int) -> ArrayMesh:
	var bands: Array = [[], []]
	var total := 0.0
	for i in range(1, profile.size()):
		total += Vector2(float(profile[i][0]) - float(profile[i - 1][0]), float(profile[i][1]) - float(profile[i - 1][1])).length()
	var run := 0.0
	for i in range(1, profile.size()):
		var a := Vector2(float(profile[i - 1][0]), float(profile[i - 1][1])) * radius
		var b := Vector2(float(profile[i][0]), float(profile[i][1])) * radius
		var step := (b - a).length() / radius
		var lip := (profile[i] as Array).size() > 2 and int(profile[i][2]) != 0
		bands[1 if lip else 0].append([a, b, run / maxf(total, 0.0001), (run + step) / maxf(total, 0.0001)])
		run += step
	var mesh := ArrayMesh.new()
	for kind in 2:
		if (bands[kind] as Array).is_empty():
			continue
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _band_arrays(bands[kind], sides))
		mesh.surface_set_material(mesh.get_surface_count() - 1, _material(kind == 1))
	return mesh


## Vertex arrays for [param bands] (each `[from, to, u_from, u_to]`, a profile point as (along, radius)) turned [param sides] round.
static func _band_arrays(bands: Array, sides: int) -> Array:
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for band: Array in bands:
		var a: Vector2 = band[0]
		var b: Vector2 = band[1]
		if a.is_equal_approx(b):
			continue
		# The outward normal of the step from a to b in the (along, radius) plane, turned so it faces away from the axis
		# on a tube and toward the eye on the eyecup's back face (the step there runs outward with along falling or fixed).
		var d := (b - a).normalized()
		var n2 := Vector2(d.y, -d.x)
		var base := points.size()
		for s in sides + 1:
			var angle := TAU * float(s) / float(sides)
			var spoke := Vector2(cos(angle), sin(angle))
			for end in 2:
				var p: Vector2 = a if end == 0 else b
				points.append(Vector3(spoke.x * p.y, spoke.y * p.y, p.x))
				normals.append(Vector3(spoke.x * n2.y, spoke.y * n2.y, n2.x).normalized())
				uvs.append(Vector2(float(band[2 + end]), float(s) / float(sides) * 8.0))
		for s in sides:
			var i0 := base + s * 2
			var i1 := i0 + 2
			indices.append_array([i0, i0 + 1, i1, i1, i0 + 1, i1 + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


## The body's or the lip's material, made once; the body carries the machining rings as a small texture.
static func _material(lip: bool) -> StandardMaterial3D:
	var key := "lip" if lip else "body"
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = LIP_COLOR if lip else Color.WHITE
	material.metallic = 0.85 if lip else 0.55
	material.roughness = 0.3 if lip else 0.48
	material.disable_receive_shadows = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if not lip:
		material.albedo_texture = _rings()
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_materials[key] = material
	return material


## Fine turned rings along the profile (u) over a faint grain round it (v), all within a few percent of [constant BODY_COLOR].
static func _rings() -> ImageTexture:
	var width := 512
	var height := 64
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGB8)
	for x in width:
		var ring := 0.5 + 0.5 * sin(float(x) * TAU * 120.0 / float(width))
		for y in height:
			# A hash, not a noise generator, so the texture is the same on every machine and costs no thread.
			var h := fposmod(sin(float(x) * 12.9898 + float(y) * 78.233) * 43758.5453, 1.0)
			var shade := 1.0 + 0.1 * (ring - 0.5) + 0.06 * (h - 0.5)
			image.set_pixel(x, y, Color(BODY_COLOR.r * shade, BODY_COLOR.g * shade, BODY_COLOR.b * shade))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
