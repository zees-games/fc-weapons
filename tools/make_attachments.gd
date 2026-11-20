extends SceneTree
## Builds the attachment models (own work, primitives only) into addons/fc_weapons/assets/attachments/<id>.tscn, each drawn on its gun's `socket_<mount>` with no offset:
## muzzle parts run toward -Z, optics sit on +Y (their `<id>_glass` mesh is what the sight line runs through), underbarrel parts hang toward -Y, side parts sit toward +X, magazine extensions hang below the magazine, a warhead sits on the missile's nose (its tip at the socket).
## Optics are hollow tubes (open at both ends, so the view runs through them) with a glass lens and an unshaded red `reticle` disc on the lens plane.
## godot --headless --path . --script res://tools/make_attachments.gd [-- <id>...] (ids: only those, so the rest keep their files)

const OUT := "res://addons/fc_weapons/assets/attachments/"

## id -> parts: [name, kind, size, position, material, rotation degrees (optional)].
## Kinds: "box" (x y z); "tube" (radius, length along Z, front radius, 0 = same as the rear: a cone); "ring" (outer radius, length along Z, inner radius: a hollow tube, open at both ends).
const PARTS := {
	"red_dot": [
		["rail", "box", Vector3(0.028, 0.006, 0.050), Vector3(0, 0.003, 0), "dark"],
		["riser", "box", Vector3(0.020, 0.014, 0.034), Vector3(0, 0.013, 0), "metal"],
		["tube_body", "ring", Vector3(0.0165, 0.046, 0.0140), Vector3(0, 0.0345, -0.004), "metal"],
		["hood_front", "ring", Vector3(0.0178, 0.010, 0.0148), Vector3(0, 0.0345, -0.030), "metal"],
		["hood_rear", "ring", Vector3(0.0178, 0.008, 0.0136), Vector3(0, 0.0345, 0.022), "metal"],
		["turret_top", "tube", Vector3(0.0045, 0.008, 0), Vector3(0, 0.0535, -0.006), "metal", Vector3(90, 0, 0)],
		["turret_side", "tube", Vector3(0.0045, 0.008, 0), Vector3(0.0185, 0.0345, -0.006), "metal", Vector3(0, 0, 90)],
		["red_dot_glass", "tube", Vector3(0.0139, 0.0016, 0), Vector3(0, 0.0345, -0.0275), "glass"],
		["reticle", "tube", Vector3(0.0011, 0.0006, 0), Vector3(0, 0.0345, -0.0287), "reticle"],
	],
	"holo": [
		["rail", "box", Vector3(0.032, 0.006, 0.070), Vector3(0, 0.003, 0), "dark"],
		["base", "box", Vector3(0.030, 0.010, 0.062), Vector3(0, 0.011, -0.002), "metal"],
		["frame_l", "box", Vector3(0.004, 0.034, 0.052), Vector3(-0.017, 0.033, -0.004), "metal"],
		["frame_r", "box", Vector3(0.004, 0.034, 0.052), Vector3(0.017, 0.033, -0.004), "metal"],
		["frame_top", "box", Vector3(0.038, 0.005, 0.052), Vector3(0, 0.0525, -0.004), "metal"],
		["emitter_box", "box", Vector3(0.026, 0.008, 0.014), Vector3(0, 0.020, 0.022), "dark"],
		["holo_glass", "box", Vector3(0.030, 0.026, 0.0016), Vector3(0, 0.0365, -0.028), "glass"],
		["reticle", "tube", Vector3(0.0013, 0.0006, 0), Vector3(0, 0.0365, -0.0292), "reticle"],
		["reticle_ring_t", "box", Vector3(0.0036, 0.0006, 0.0006), Vector3(0, 0.0425, -0.0292), "reticle"],
		["reticle_ring_b", "box", Vector3(0.0036, 0.0006, 0.0006), Vector3(0, 0.0305, -0.0292), "reticle"],
	],
	"prism_3x": [
		["rail", "box", Vector3(0.030, 0.006, 0.062), Vector3(0, 0.003, 0), "dark"],
		["riser", "box", Vector3(0.022, 0.010, 0.040), Vector3(0, 0.011, 0), "metal"],
		["body", "ring", Vector3(0.0205, 0.074, 0.0180), Vector3(0, 0.0395, -0.004), "metal"],
		["objective", "ring", Vector3(0.0240, 0.012, 0.0200), Vector3(0, 0.0395, -0.040), "metal"],
		["eye_ring", "ring", Vector3(0.0225, 0.008, 0.0165), Vector3(0, 0.0395, 0.036), "dark"],
		["turret_top", "tube", Vector3(0.0050, 0.008, 0), Vector3(0, 0.0630, -0.004), "metal", Vector3(90, 0, 0)],
		["turret_side", "tube", Vector3(0.0050, 0.008, 0), Vector3(0.0235, 0.0395, -0.004), "metal", Vector3(0, 0, 90)],
		["prism_3x_glass", "tube", Vector3(0.0185, 0.0016, 0), Vector3(0, 0.0395, -0.0385), "glass"],
		["reticle", "tube", Vector3(0.0009, 0.0006, 0), Vector3(0, 0.0395, -0.0396), "reticle"],
	],
	"scope_6x": [
		["ring_rear", "box", Vector3(0.026, 0.040, 0.014), Vector3(0, 0.020, 0.030), "metal"],
		["ring_front", "box", Vector3(0.026, 0.040, 0.014), Vector3(0, 0.020, -0.050), "metal"],
		["rail", "box", Vector3(0.030, 0.006, 0.100), Vector3(0, 0.003, -0.010), "dark"],
		["tube", "tube", Vector3(0.016, 0.200, 0), Vector3(0, 0.046, -0.010), "metal"],
		["bell", "tube", Vector3(0.019, 0.050, 0.026), Vector3(0, 0.046, -0.120), "metal"],
		["bell_lip", "ring", Vector3(0.026, 0.006, 0.0235), Vector3(0, 0.046, -0.148), "dark"],
		["eyepiece", "tube", Vector3(0.019, 0.040, 0.0165), Vector3(0, 0.046, 0.100), "metal"],
		["eye_rubber", "ring", Vector3(0.0195, 0.010, 0.0150), Vector3(0, 0.046, 0.122), "dark"],
		["turret_top", "tube", Vector3(0.0070, 0.012, 0), Vector3(0, 0.0700, -0.010), "metal", Vector3(90, 0, 0)],
		["turret_side", "tube", Vector3(0.0070, 0.012, 0), Vector3(0.0240, 0.046, -0.010), "metal", Vector3(0, 0, 90)],
		["scope_6x_glass", "tube", Vector3(0.014, 0.260, 0), Vector3(0, 0.046, -0.010), "glass"],
	],
	"suppressor": [
		["can", "tube", Vector3(0.0175, 0.150, 0), Vector3(0, 0, -0.085), "metal"],
		["collar", "tube", Vector3(0.0125, 0.014, 0), Vector3(0, 0, -0.004), "dark"],
		["band_a", "ring", Vector3(0.0182, 0.006, 0.0170), Vector3(0, 0, -0.050), "dark"],
		["band_b", "ring", Vector3(0.0182, 0.006, 0.0170), Vector3(0, 0, -0.110), "dark"],
		["end_cap", "tube", Vector3(0.0170, 0.008, 0.0140), Vector3(0, 0, -0.1565), "dark"],
		["bore", "tube", Vector3(0.0045, 0.0004, 0), Vector3(0, 0, -0.1607), "bore"],
	],
	"compensator": [
		["body", "tube", Vector3(0.0125, 0.050, 0), Vector3(0, 0, -0.025), "metal"],
		["collar", "tube", Vector3(0.0138, 0.008, 0), Vector3(0, 0, -0.004), "dark"],
		["port_a", "box", Vector3(0.028, 0.006, 0.006), Vector3(0, 0.010, -0.018), "dark"],
		["port_b", "box", Vector3(0.028, 0.006, 0.006), Vector3(0, 0.010, -0.030), "dark"],
		["port_c", "box", Vector3(0.028, 0.006, 0.006), Vector3(0, 0.010, -0.042), "dark"],
		["bore", "tube", Vector3(0.0045, 0.0004, 0), Vector3(0, 0, -0.0502), "bore"],
	],
	"vertical_grip": [
		["clamp", "box", Vector3(0.026, 0.010, 0.040), Vector3(0, -0.005, 0), "metal"],
		["stem", "tube", Vector3(0.012, 0.012, 0), Vector3(0, -0.016, 0), "metal", Vector3(90, 0, 0)],
		["grip", "tube", Vector3(0.0135, 0.090, 0.0160), Vector3(0, -0.067, 0), "polymer", Vector3(90, 0, 0)],
		["cap", "tube", Vector3(0.0165, 0.008, 0.0140), Vector3(0, -0.116, 0), "dark", Vector3(90, 0, 0)],
		["rib_a", "ring", Vector3(0.0158, 0.004, 0.0140), Vector3(0, -0.050, 0), "dark", Vector3(90, 0, 0)],
		["rib_b", "ring", Vector3(0.0162, 0.004, 0.0140), Vector3(0, -0.070, 0), "dark", Vector3(90, 0, 0)],
		["rib_c", "ring", Vector3(0.0166, 0.004, 0.0140), Vector3(0, -0.090, 0), "dark", Vector3(90, 0, 0)],
	],
	"angled_grip": [
		["clamp", "box", Vector3(0.026, 0.010, 0.070), Vector3(0, -0.005, 0), "metal"],
		["ramp", "box", Vector3(0.022, 0.030, 0.066), Vector3(0, -0.024, 0.004), "polymer", Vector3(-28, 0, 0)],
		["nose", "box", Vector3(0.022, 0.016, 0.014), Vector3(0, -0.040, -0.030), "dark", Vector3(-28, 0, 0)],
		["rib_a", "box", Vector3(0.0235, 0.004, 0.006), Vector3(0, -0.019, -0.008), "dark", Vector3(-28, 0, 0)],
		["rib_b", "box", Vector3(0.0235, 0.004, 0.006), Vector3(0, -0.026, 0.008), "dark", Vector3(-28, 0, 0)],
	],
	"laser": [
		["clamp", "box", Vector3(0.008, 0.020, 0.030), Vector3(0.004, 0, 0), "metal"],
		["box", "box", Vector3(0.020, 0.024, 0.056), Vector3(0.018, 0, -0.008), "polymer"],
		["barrel", "tube", Vector3(0.0075, 0.012, 0), Vector3(0.018, 0.004, -0.040), "metal"],
		["dial", "tube", Vector3(0.0045, 0.006, 0), Vector3(0.0285, -0.004, 0.004), "dark", Vector3(0, 0, 90)],
		["emitter", "tube", Vector3(0.0045, 0.0014, 0), Vector3(0.018, 0.004, -0.0468), "laser"],
	],
	"extended_mag": [
		["extension", "box", Vector3(0.030, 0.050, 0.034), Vector3(0, -0.025, 0), "polymer"],
		["rib_a", "box", Vector3(0.0315, 0.003, 0.0355), Vector3(0, -0.014, 0), "dark"],
		["rib_b", "box", Vector3(0.0315, 0.003, 0.0355), Vector3(0, -0.026, 0), "dark"],
		["rib_c", "box", Vector3(0.0315, 0.003, 0.0355), Vector3(0, -0.038, 0), "dark"],
		["plate", "box", Vector3(0.034, 0.006, 0.040), Vector3(0, -0.053, 0), "metal"],
	],
	"rocketjump": [
		["cap", "tube", Vector3(0.030, 0.050, 0), Vector3(0, 0, 0.012), "practice"],
		["face", "tube", Vector3(0.022, 0.006, 0), Vector3(0, 0, -0.015), "dark"],
		["band", "tube", Vector3(0.069, 0.040, 0), Vector3(0, 0, 0.170), "practice"],
	],
}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var made := 0
	var only := OS.get_cmdline_user_args()
	for id: String in PARTS:
		if not only.is_empty() and not only.has(id):
			continue
		var root := Node3D.new()
		root.name = id
		for part: Array in PARTS[id]:
			var mi := MeshInstance3D.new()
			mi.name = part[0]
			mi.mesh = _mesh(part[1], part[2])
			mi.material_override = _material(part[4])
			mi.position = part[3]
			if part.size() > 5:
				var turn: Vector3 = part[5]
				mi.rotation_degrees = turn
			root.add_child(mi)
			mi.owner = root
		var scene := PackedScene.new()
		scene.pack(root)
		var err := ResourceSaver.save(scene, OUT + id + ".tscn")
		root.free()
		if err != OK:
			printerr("make_attachments: %s failed (%d)" % [id, err])
			quit(1)
			return
		made += 1
	print("make_attachments: %d models" % made)
	quit()


static func _mesh(kind: String, size: Vector3) -> Mesh:
	if kind == "ring":
		return _ring(size.x, size.y, size.z)
	if kind == "tube":
		var c := CylinderMesh.new()
		c.top_radius = size.x
		c.bottom_radius = size.z if size.z > 0.0 else size.x
		c.height = size.y
		c.radial_segments = 20
		c.rings = 1
		return _along_z(c.get_mesh_arrays())
	var b := BoxMesh.new()
	b.size = size
	return b


## A cylinder stands on Y; bake a turn so it runs along Z (its top toward +Z).
static func _along_z(arrays: Array) -> ArrayMesh:
	var turn := Basis(Vector3.RIGHT, PI / 2.0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in verts.size():
		verts[i] = turn * verts[i]
		normals[i] = turn * normals[i]
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = null
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


## A hollow tube along Z, open at both ends: outer wall, inner wall (facing in) and the two annular faces.
static func _ring(r_out: float, length: float, r_in: float) -> ArrayMesh:
	var segs := 24
	var h := length * 0.5
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var d0 := Vector3(cos(a0), sin(a0), 0.0)
		var d1 := Vector3(cos(a1), sin(a1), 0.0)
		for wall in [[r_out, 1.0], [r_in, -1.0]]:
			var r: float = wall[0]
			var facing: float = wall[1]
			var base := verts.size()
			verts.append_array([d0 * r + Vector3(0, 0, -h), d1 * r + Vector3(0, 0, -h), d1 * r + Vector3(0, 0, h), d0 * r + Vector3(0, 0, h)])
			normals.append_array([d0 * facing, d1 * facing, d1 * facing, d0 * facing])
			idx.append_array(_quad(base, facing < 0.0))
		for end in [-1.0, 1.0]:
			var base := verts.size()
			var n := Vector3(0, 0, end)
			verts.append_array([d0 * r_out + n * h, d1 * r_out + n * h, d1 * r_in + n * h, d0 * r_in + n * h])
			normals.append_array([n, n, n, n])
			idx.append_array(_quad(base, end > 0.0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


static func _quad(base: int, flip: bool) -> PackedInt32Array:
	if flip:
		return PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2])
	return PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3])


static var _materials: Dictionary = {}


static func _material(kind: String) -> StandardMaterial3D:
	if _materials.has(kind):
		return _materials[kind]
	var m := StandardMaterial3D.new()
	match kind:
		"metal":
			m.albedo_color = Color(0.30, 0.30, 0.32)
			m.metallic = 0.4
			m.roughness = 0.45
		"dark":
			m.albedo_color = Color(0.045, 0.045, 0.05)
			m.roughness = 0.7
		"bore":
			m.albedo_color = Color(0.0, 0.0, 0.0)
			m.roughness = 1.0
		"polymer":
			m.albedo_color = Color(0.16, 0.15, 0.13)
			m.roughness = 0.75
		"glass":
			m.albedo_color = Color(0.30, 0.50, 0.55, 0.22)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.metallic_specular = 1.0
			m.roughness = 0.03
		"reticle":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(1.0, 0.08, 0.04)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.08, 0.04)
			m.emission_energy_multiplier = 6.0
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"practice":
			m.albedo_color = Color(0.95, 0.42, 0.05)
			m.roughness = 0.55
		"laser":
			m.albedo_color = Color(1.0, 0.1, 0.05)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.1, 0.05)
			m.emission_energy_multiplier = 4.0
	_materials[kind] = m
	return m
