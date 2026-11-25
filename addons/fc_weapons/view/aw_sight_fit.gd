extends RefCounted

## Which sight a weapon aims down and the aim hold that puts it through the eye: the model's own (read off its mesh),
## its marked one, or the built ring and post. No `class_name`: [AwViewModel] preloads it by path.

const IronSight := preload("res://addons/gs_weapon/view/gs_weapon_iron_sight.gd")
const OwnSight := preload("aw_own_sight.gd")
const Extent := preload("aw_face_extent.gd")
const Cut := preload("aw_sight_cut.gd")
const CutJob := preload("aw_sight_cut_job.gd")

## The front sight's glow: a small dot on the post's tip, its size in degrees from the ADS rule `sight_dot`, shown as the aim arrives.
const DOT_COLOR := Color(0.75, 1.0, 0.35)
const GLOW_NODE_NAME := "SightDot"
const DOT_FADE_FROM := 0.6
const RED_DOT_NAME := "RedDot"
## The red dot's reticle and lens tint show from this aim fraction on, as the sight comes to the eye; its housing (tube,
## mount and turrets round the window) and rim show at every fraction, filling the hole the window cuts in the gun.
const RED_SHOW_FROM := 0.35
const RETICLE_NAME := "Reticle"
const LENS_NAME := "Lens"
const HOUSING_NAME := "Housing"
## The housing's anodised finish and its sizes as shares of the window's radius: the tube's wall, how far it runs back
## toward the eye and forward past the window; and the tube's sides.
const HOUSING_COLOR := Color(0.045, 0.047, 0.052)
const HOUSING_WALL := 0.2
const HOUSING_BACK := 1.7
const HOUSING_FRONT := 0.12
const HOUSING_SIDES := 40
## The red dot's lens: a faint tint, and the thin rim round it as a share of the window's radius.
const LENS_COLOR := Color(0.55, 0.85, 1.0, 0.035)
const RIM_COLOR := Color(0.06, 0.06, 0.07)
const RIM_SHARE := 0.07

static var _parts: Dictionary = {}
## Whether [method fit] remembers each model's measured sight line. Measuring walks every triangle in script
## (16 to 140 ms for a gun), and the line depends only on the model and where it sits under the holder.
static var line_cache := true
## model path|forward|weapon-in-holder transform -> [line, built]
static var _lines: Dictionary = {}


## `{line, aim, sight}` for [param art] on [param weapon] under [param holder] (`sight` a node to add under the holder, or
## null), or `{}` when the weapon aims at its written hold. [param near] is the camera's near plane plus its margin.
static func fit(art: AwWeaponVisual, weapon: Node3D, holder: Node3D, dressed_line: Dictionary, near: float, dot_degrees: float) -> Dictionary:
	if not (art.iron_sight or art.sight_own) or not art.aim_enabled or art.aim_scoped or weapon == null:
		return {}
	var basis := art.orientation().scaled(Vector3.ONE * art.view_scale)
	var key := _line_key(art, weapon, holder, basis)
	var found: Array = _lines[key] if key != "" and _lines.has(key) else _measure_line(art, weapon, holder, basis)
	if key != "":
		_lines[key] = found
	var line: Dictionary = (found[0] as Dictionary).duplicate()
	var built: bool = found[1]
	if line.get("marked", false):
		line.merge(dressed_line, true)
	if line.is_empty():
		return {}
	# The eye stands back far enough to keep the gun's back end past the near plane (a clip plane slices).
	var behind := maxf(0.0, (basis * (line.back as Vector3)).z - (basis * (line.rear as Vector3)).z)
	var relief := maxf(art.aim_eye_relief, behind + near)
	# The ring is sized to how far out it ends up, so a toy blaster and a real-sized rifle read alike.
	var span := absf((basis * (line.front as Vector3)).z - (basis * (line.rear as Vector3)).z)
	var sight: Node3D = null
	if built:
		var ring := (relief + span) * tan(deg_to_rad(IronSight.RING_DEGREES)) / art.view_scale
		line = IronSight.with_ring(line, clampf(ring, IronSight.RING_FIT_MIN, IronSight.RING_FIT_MAX))
		sight = IronSight.build(line, art.model_forward)
	elif line.get("post", false) and dot_degrees > 0.0:
		sight = _dot(line, art.model_forward, (relief + span) * tan(deg_to_rad(dot_degrees)) / art.view_scale)
	return {"line": line, "aim": Transform3D(basis, Vector3(0.0, 0.0, -relief) - basis * (line.rear as Vector3)), "sight": sight}


## [method IronSight.from_marks] with the back end read natively ([Extent]) instead of by a script walk over every triangle (50-100 ms for a rifle):
## the same line, the corners walked from the same faces.
static func marked_line(weapon: Node, space: Node3D, forward: Vector3) -> Dictionary:
	var rear := weapon.find_child(IronSight.MARK_REAR, true, false) as Node3D
	var front := weapon.find_child(IronSight.MARK_FRONT, true, false) as Node3D
	if rear == null or front == null:
		return {}
	var to_space := space.global_transform.affine_inverse()
	var r := to_space * rear.global_transform.origin
	var fr := to_space * front.global_transform.origin
	var f := forward.normalized()
	var back_t := minf(r.dot(f), Extent.range_along(IronSight.faces_of(weapon, space), f).x)
	return {"rear": r, "front": fr, "back": r + f * (back_t - r.dot(f)), "marked": true}


## `[line, built]` read off [param weapon]: the marked line, else its own sight, else the measured line for a built ring and post ([] line when none).
static func _measure_line(art: AwWeaponVisual, weapon: Node3D, holder: Node3D, basis: Basis) -> Array:
	# Marks a modeller placed win over anything read off the mesh.
	var line := marked_line(weapon, holder, art.model_forward)
	if line.is_empty() and art.sight_own:
		# The rear point stays where the written hold had it, so the eye keeps its distance from the gun.
		var written := basis.inverse() * (Vector3(0.0, 0.0, -art.aim_eye_relief) - art.aim_offset)
		line = OwnSight.measure(weapon, holder, art.model_forward, written.dot(art.model_forward.normalized()), art.model_path)
	if line.is_empty() and art.iron_sight:
		return [IronSight.measure(weapon, holder, art.model_forward), true]
	return [line, false]


## The cache key of [method _measure_line] for this model where it sits under [param holder], or "" when it cannot be cached.
static func _line_key(art: AwWeaponVisual, weapon: Node3D, holder: Node3D, basis: Basis) -> String:
	if not line_cache or art.model_path == "" or not weapon.is_inside_tree() or not holder.is_inside_tree():
		return ""
	var placed := holder.global_transform.affine_inverse() * weapon.global_transform
	return "%s|%s|%s|%s|%s|%s|%s|%s" % [art.model_path, art.model_forward, placed, basis, art.aim_eye_relief,
		art.aim_offset, art.sight_own, art.iron_sight]


## A glowing dot of [param radius] (model metres) just behind the post's tip on [param line], its top on the line.
static func _dot(line: Dictionary, forward: Vector3, radius: float) -> Node3D:
	var root := Node3D.new()
	root.name = "OwnSight"
	var dot := MeshInstance3D.new()
	dot.name = GLOW_NODE_NAME
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	dot.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(DOT_COLOR, 0.0)
	dot.material_override = material
	dot.position = (line.front as Vector3) - forward.normalized() * radius * 1.2 - Vector3.UP * radius
	dot.visible = false
	root.add_child(dot)
	return root


## Cuts the see-through hole of [method cone_for] out of [param roots]; a red-dot sight returns its dot, lens and rim to add under the holder, else null.
static func cut(art: AwWeaponVisual, rules: AwAdsRules, roots: Array, holder: Node3D, aim: Transform3D, line: Dictionary) -> Node3D:
	var cone := cone_for(art, rules, roots, holder, aim, line)
	if cone.is_empty():
		return null
	var job: RefCounted = begin(roots, holder, cone)
	job.run()
	return finish(art, rules, cone, job)


## A cut in progress for [param cone] (from [method cone_for], not empty): [code]step(usec)[/code] it a frame at a time until it reports
## done, then [method finish]. The same hole [method cut] makes at once.
static func begin(roots: Array, holder: Node3D, cone: Dictionary) -> RefCounted:
	return CutJob.new(roots, holder, cone)


## The red dot (or null) once [param job] from [method begin] is done.
static func finish(art: AwWeaponVisual, rules: AwAdsRules, cone: Dictionary, job: RefCounted) -> Node3D:
	if not cone.red:
		return null
	var done: Dictionary = job.result
	var relief := art.aim_eye_relief / maxf(art.view_scale, 0.01)
	return _red_dot(cone, float(done.far) if int(done.removed) > 0 else relief, _red(art, rules))


## The hole along the aim hold [param aim] in the holder's space (aw_sight_cut.gd's cone plus `red`): `sight_cut` degrees stopping
## short of the front post ([param line]'s, else the first thing on the axis in the gun's front part); a red dot's wider window runs through.
static func cone_for(art: AwWeaponVisual, rules: AwAdsRules, roots: Array, holder: Node3D, aim: Transform3D, line: Dictionary) -> Dictionary:
	var begun := cone_begin(art, rules, roots, holder, aim, line)
	if begun.front != null:
		begun.front.run()
	return cone_end(begun)


## [method cone_for] in two halves, so the walk over the gun's faces that stops the hole short of a front post can be stepped a frame
## at a time: `{cone, red, front}` where `front` is null (the cone is final) or a job to `step(usec)` until done; then [method cone_end].
static func cone_begin(art: AwWeaponVisual, rules: AwAdsRules, roots: Array, holder: Node3D, aim: Transform3D, line: Dictionary) -> Dictionary:
	if art == null or not art.aim_enabled or art.aim_scoped or roots.is_empty() or roots[0] == null:
		return {"cone": {}, "red": false, "front": null}
	var red := _red(art, rules)
	var is_red := art.sight_red_dot or bool(red.on)
	var degrees: float = float(red.window) if is_red else (rules.sight_cut_for(art.id) if rules != null else float(AwAdsRules.SPECS["sight_cut"]["default"]))
	var cone := Cut.cone(aim, degrees, line.front if line.get("post", false) and not is_red else null)
	var front: RefCounted = Cut.front_job(cone, roots[0], holder) if not is_red else null
	return {"cone": cone, "red": is_red, "front": front}


## The cone of [method cone_begin] once its `front` job (if any) is done.
static func cone_end(begun: Dictionary) -> Dictionary:
	var cone: Dictionary = begun.cone if begun.front == null else begun.front.result
	if not cone.is_empty():
		cone.red = begun.red
	return cone


static func _red(art: AwWeaponVisual, rules: AwAdsRules) -> Dictionary:
	return (rules if rules != null else AwAdsRules.new()).red_dot_for(art.id)


## The dot, its lens, rim and housing at [param depth] along [param cone]'s axis; [method track] keeps the dot on the axis from wherever the eye is.
static func _red_dot(cone: Dictionary, depth: float, red: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = RED_DOT_NAME
	var axis: Vector3 = cone.axis
	var centre: Vector3 = (cone.eye as Vector3) + axis * depth
	var window := depth * float(cone.tan)
	root.transform = Transform3D(Basis(Quaternion(Vector3.UP, axis)), centre)
	root.set_meta(&"axis", axis)
	root.set_meta(&"window", window)
	root.set_meta(&"hip", bool(red.get("hip", true)))
	var lens := MeshInstance3D.new()
	lens.name = LENS_NAME
	lens.mesh = _part("lens")
	lens.scale = Vector3.ONE * window
	lens.material_override = _part("lens_material")
	root.add_child(lens)
	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	rim.mesh = _part("rim")
	rim.scale = Vector3.ONE * window
	rim.material_override = _part("rim_material")
	root.add_child(rim)
	root.add_child(_housing(window))
	var dot := MeshInstance3D.new()
	dot.name = RETICLE_NAME
	dot.mesh = _part("dot")
	dot.scale = Vector3.ONE * (depth * tan(deg_to_rad(float(red.size))))
	var glow_color: Color = (red.color as Color) * maxf(1.0, float(red.brightness) * 0.25)
	glow_color.a = 1.0
	dot.material_override = _glow(glow_color)
	dot.set_meta(&"glow", float(red.brightness))
	root.add_child(dot)
	return root


## The housing round a red dot's window of radius [param window]: in the root's frame +Y runs down the aim, +Z is up and
## +X right, so the tube runs along Y behind the window, the mount sits under it and the turrets on its top and right.
static func _housing(window: float) -> Node3D:
	var housing := Node3D.new()
	housing.name = HOUSING_NAME
	housing.scale = Vector3.ONE * window
	var outer := 1.0 + HOUSING_WALL
	var mid := (HOUSING_FRONT - HOUSING_BACK) * 0.5
	var pieces := [
		["Tube", "housing_tube", Vector3.ZERO, Vector3.ZERO, Vector3.ONE],
		# Mount: a riser under the tube and a wider rail clamp under that.
		["Mount", "housing_box", Vector3(0.0, mid, -outer - 0.2), Vector3.ZERO, Vector3(0.9, HOUSING_BACK * 0.8, 0.45)],
		["Clamp", "housing_box", Vector3(0.0, mid, -outer - 0.5), Vector3.ZERO, Vector3(1.5, HOUSING_BACK * 0.9, 0.2)],
		# Elevation cap on top and brightness turret on the right, just behind the window.
		["TurretTop", "housing_cap", Vector3(0.0, -0.7, outer + 0.12), Vector3(PI * 0.5, 0.0, 0.0), Vector3(0.38, 0.32, 0.38)],
		["TurretSide", "housing_cap", Vector3(outer + 0.12, -0.7, 0.0), Vector3(0.0, 0.0, PI * 0.5), Vector3(0.42, 0.32, 0.42)],
	]
	for piece: Array in pieces:
		var mesh := MeshInstance3D.new()
		mesh.name = piece[0]
		mesh.mesh = _part(piece[1])
		mesh.material_override = _part("housing_material")
		mesh.position = piece[2]
		mesh.rotation = piece[3]
		mesh.scale = piece[4]
		housing.add_child(mesh)
	return housing


## The housing's tube: a hollow cylinder of inner radius 1 along +Y, from [constant HOUSING_BACK] behind the window to
## [constant HOUSING_FRONT] past it, its ends closed by flat rings.
static func _tube_mesh() -> ArrayMesh:
	var outer := 1.0 + HOUSING_WALL
	var back := -HOUSING_BACK
	var front := HOUSING_FRONT
	# Each wall: radius and y at its start, radius and y at its end, and its normal as (radial, y).
	var walls := [
		[outer, back, outer, front, Vector2(1.0, 0.0)],
		[outer, front, 1.0, front, Vector2(0.0, 1.0)],
		[1.0, front, 1.0, back, Vector2(-1.0, 0.0)],
		[1.0, back, outer, back, Vector2(0.0, -1.0)],
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for wall: Array in walls:
		var n: Vector2 = wall[4]
		for i in HOUSING_SIDES:
			var quad: Array[Vector3] = []
			var normals: Array[Vector3] = []
			for corner: Array in [[i, 0], [i + 1, 0], [i + 1, 2], [i, 2]]:
				var angle := TAU * float(corner[0]) / HOUSING_SIDES
				var at: int = corner[1]
				var r: float = wall[at]
				quad.append(Vector3(r * cos(angle), float(wall[at + 1]), r * sin(angle)))
				normals.append(Vector3(n.x * cos(angle), n.y, n.x * sin(angle)))
			for k: int in [0, 2, 1, 0, 3, 2]:
				st.set_normal(normals[k])
				st.add_vertex(quad[k])
	return st.commit()


## A unit-size part of the red dot (scaled per gun), built once: building the cylinder, torus and sphere and their materials per equip cost 110 ms on a cold gun.
static func _part(part: String) -> Resource:
	if not _parts.has(part):
		match part:
			"lens":
				var disc := CylinderMesh.new()
				disc.top_radius = 1.0
				disc.bottom_radius = 1.0
				disc.height = 0.01
				disc.radial_segments = 32
				disc.rings = 1
				disc.cap_bottom = false
				_parts[part] = disc
			"rim":
				var ring := TorusMesh.new()
				ring.inner_radius = 1.0
				ring.outer_radius = 1.0 + RIM_SHARE
				ring.rings = 48
				ring.ring_segments = 6
				_parts[part] = ring
			"dot":
				var sphere := SphereMesh.new()
				sphere.radius = 1.0
				sphere.height = 2.0
				sphere.radial_segments = 12
				sphere.rings = 6
				_parts[part] = sphere
			"lens_material":
				_parts[part] = _flat(LENS_COLOR, true)
			"rim_material":
				_parts[part] = _flat(RIM_COLOR, false)
			"housing_tube":
				_parts[part] = _tube_mesh()
			"housing_box":
				var box := BoxMesh.new()
				box.size = Vector3.ONE
				_parts[part] = box
			"housing_cap":
				var cap := CylinderMesh.new()
				cap.top_radius = 1.0
				cap.bottom_radius = 1.0
				cap.height = 1.0
				cap.radial_segments = 20
				cap.rings = 1
				_parts[part] = cap
			"housing_material":
				var anodised := StandardMaterial3D.new()
				anodised.albedo_color = HOUSING_COLOR
				anodised.metallic = 0.6
				anodised.roughness = 0.45
				anodised.disable_receive_shadows = true
				_parts[part] = anodised
	return _parts[part]


static func _glow(color: Color) -> StandardMaterial3D:
	var key := "glow|%s" % color
	if not _parts.has(key):
		var glow := StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.albedo_color = color
		glow.no_depth_test = true
		glow.render_priority = Material.RENDER_PRIORITY_MAX
		_parts[key] = glow
	return _parts[key]


static func _flat(color: Color, see_through: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.3
	material.disable_receive_shadows = true
	if see_through:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


## Keeps a red dot under [param sight] on its axis as seen from [param eye] (holder space), as a collimated sight does,
## and hides it once that leaves the window; 0 brightness hides it for good.
static func track(sight: Node3D, eye: Vector3) -> void:
	var red := red_of(sight)
	if red == null:
		return
	var dot := red.get_node(RETICLE_NAME) as Node3D
	var local := red.transform.affine_inverse() * eye
	# In the root's frame the axis is +Y and the window is the plane y = 0: the dot is the eye's foot on it.
	dot.position = Vector3(local.x, 0.0, local.z)
	dot.visible = bool(red.get_meta(&"shown", true)) and float(dot.get_meta(&"glow", 0.0)) > 0.0 \
		and Vector2(local.x, local.z).length() < float(red.get_meta(&"window", 0.0))


## The red-dot root [param sight] is or holds, else null. By its meta, not its name: added beside the last gun's
## (queue_free'd, still in the tree) it is renamed.
static func red_of(sight: Node3D) -> Node3D:
	if sight == null or sight.has_meta(&"window"):
		return sight
	for child in sight.get_children():
		if child is Node3D and child.has_meta(&"window"):
			return child
	return null


## Shows the dot under [param sight] by the aim fraction [param f]: none at the hip, full at the eye. A red dot's
## reticle and lens show from [constant RED_SHOW_FROM]; its housing and rim stay, as a real sight's do, unless its
## `red_dot_hip` rule is false (aw_ads_rules.gd), when they too show from [constant RED_SHOW_FROM].
static func fade(sight: Node3D, f: float) -> void:
	var red := red_of(sight)
	if red != null:
		var shown := f >= RED_SHOW_FROM
		red.set_meta(&"shown", shown)
		var lens := red.get_node_or_null(LENS_NAME) as Node3D
		if lens != null:
			lens.visible = shown
		# [method track] shows the reticle again each frame while it is on the axis.
		var reticle := red.get_node_or_null(RETICLE_NAME) as Node3D
		if reticle != null and not shown:
			reticle.visible = false
		# A red dot over a gun whose top is well under its line (`red_dot_hip` false) floats there at the hip: all of it waits.
		if not bool(red.get_meta(&"hip", true)):
			for part: String in [HOUSING_NAME, "Rim"]:
				var piece := red.get_node_or_null(part) as Node3D
				if piece != null:
					piece.visible = shown
	var dot := sight.get_node_or_null(GLOW_NODE_NAME) as MeshInstance3D
	if dot == null:
		return
	var alpha := clampf((f - DOT_FADE_FROM) / (1.0 - DOT_FADE_FROM), 0.0, 1.0)
	dot.visible = alpha > 0.0
	(dot.material_override as StandardMaterial3D).albedo_color.a = alpha


## Sharpens a view material's textures at a grazing angle (a sight's top seen edge-on), keeping its filter's kind.
static func sharpen(material: BaseMaterial3D) -> void:
	match material.texture_filter:
		BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS:
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS:
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
