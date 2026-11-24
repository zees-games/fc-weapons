extends RefCounted

## Samples a weapon's procedural first-person motion into keyframed tracks, from the code the game runs: a real AwViewModel is
## driven through each clip (fire, the bolt or pump cycle, reload, draw, inspect, aim, idle sway) at 60 fps and every drawn part's
## transform is read back each frame. Nothing here copies a number from the animation code; the clip only says which call to make.
## Used by tools/export_anim_tracks.gd (the file Nightly's viewer plays) and by the suite.
##
## Space: every transform is in the view model's own space (the rig's node under the camera, drawn with no hands lens, so
## hands_fov 0): metres, Godot axes (-Z forward). The viewer applies the lens itself (GSViewLens.apply) from the player's FoV.

const FPS := 60
const STEP := 1.0 / float(FPS)
const VERSION := 1
## The menu's viewmodel_fov default (gs-menu GSMenuStock.VIEWMODEL_FOV) and field_of_view default, horizontal degrees on 4:3.
const VIEWMODEL_FOV_H := 54.0
const WORLD_FOV_H := 90.0
## Frames the rig is settled for before a clip is recorded.
const SETTLE := 90
## The sway clip's look sweep: a slow turn of this many degrees either way over [constant SWAY_SECONDS].
const SWAY_DEGREES := 3.0
const SWAY_SECONDS := 4.0

var _view: AwViewModel = null
var _tracks: Dictionary = {}
var _frames := 0
## The reload parts built in code (ammo box, casing, cell ...) the clip drew: index -> {part, shapes}; their tracks are prop.<index>, .scale and .visible.
var _props: Dictionary = {}


## The clips a weapon has, in play order, each {name, loop}.
static func clip_names(art: AwWeaponVisual, def: GSWeaponDef) -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"name": "fire", "loop": false}]
	if art.cycle_style != &"" and art.bolt_node != &"":
		out.append({"name": "%s_cycle" % art.cycle_style, "loop": false})
	if def != null and def.magazine > 0:
		out.append({"name": "reload", "loop": false})
		out.append({"name": "reload_empty", "loop": false})
	out.append({"name": "draw", "loop": false})
	out.append({"name": "inspect", "loop": false})
	out.append({"name": "ads", "loop": false})
	out.append({"name": "idle", "loop": true})
	return out


## Bakes every clip of weapon [param id] under [param host] (a node in the tree). Returns the sidecar dictionary, or {} for an unknown id.
## [param model] swaps in another model file of the same folder (an alias the game does not play): the row's tuning stays, and the grips, the
## muzzle and the hand reach are measured from that model itself.
func bake(host: Node, id: StringName, def: GSWeaponDef, model: String = "") -> Dictionary:
	var art := AwWeaponVisual.make(id)
	var rows := AwWeaponArt.weapon_rows("")
	if rows.has(id):
		AwArtDress.apply(art, rows[id])
	if model != "":
		art.model_path = "%s/%s.glb" % [art.model_path.get_base_dir(), model]
	if not art.has_model():
		return {}
	var clips: Array = []
	for c in clip_names(art, def):
		var view := AwViewModel.new()
		view.show_arms = true
		view.wall_overlay = false
		view.hands_fov = 0.0
		view.fire_interval = float(def.use_interval_ticks) / float(AwWeaponPack.TICK_RATE) if def != null else 0.0
		host.add_child(view)
		view.set_kick_params(def.params if def != null else {})
		view.equip(art)
		_view = view
		var baked := _clip(String(c.name), bool(c.loop), art, def)
		baked["props"] = _props
		clips.append(baked)
		host.remove_child(view)
		view.free()
	return {
		"version": VERSION,
		"weapon": String(id),
		"model": art.model_path.get_file().get_basename(),
		"asset": "fc-weapons__" + art.model_path.trim_prefix("res://").get_basename().replace("/", "__"),
		"fps": FPS,
		"lens": {
			"viewmodel_fov_h": VIEWMODEL_FOV_H, "world_fov_h": WORLD_FOV_H,
			"reference_fov": GSViewLens.REFERENCE_FOV, "reference_depth": GSViewLens.REFERENCE_DEPTH,
			"max_pull_in": GSViewLens.MAX_PULL_IN, "depth_comp": 1.0,
		},
		"third_person": _third_person(art),
		"nodes": {"bolt": String(art.bolt_node), "magazine": String(art.hide_during_reload)},
		"clips": clips,
	}


func _clip(name: String, loop: bool, art: AwWeaponVisual, def: GSWeaponDef) -> Dictionary:
	_tracks = {}
	_props = {}
	_frames = 0
	_view.on_reload(0.0)
	_view.on_deploy(1.0)
	for _i in SETTLE:
		_view.advance(STEP)
	match name:
		"fire":
			_fire(0.8, def)
		"bolt_cycle", "pump_cycle":
			_fire(maxf(0.8, _view.fire_interval + 0.2), def)
		"reload", "reload_empty":
			_reload(def, name == "reload_empty")
		"draw":
			_draw(def)
		"inspect":
			_inspect()
		"ads":
			_ads()
		"idle":
			_idle()
	var tracks: Array = []
	for key: String in _tracks:
		var t: Dictionary = _tracks[key]
		# a part the game frees mid-clip (a casing, an ammo box) stops reporting: hold its last set, hidden
		var width: int = {"transform": 7, "position": 3, "visible": 1, "vec2": 2}[t.path]
		var vals: Array = t.values
		while vals.size() < width * _frames:
			if t.path == "visible":
				vals.append(0.0)
			else:
				vals.append_array(vals.slice(vals.size() - width))
		tracks.append({"target": key, "path": t.path, "values": _round(t.values)})
	return {"name": name, "length": snappedf(float(_frames) / float(FPS), 0.001), "frames": _frames, "loop": loop, "tracks": tracks}


func _fire(seconds: float, def: GSWeaponDef) -> void:
	var shot := GSWeaponOutcome.new()
	shot.used = true
	shot.kind = GSWeaponOutcome.KIND_SHOT
	var b := def.tuning as GSWeaponBallistics if def != null else null
	if b != null:
		shot.recoil = Vector2(b.recoil_pitch, b.recoil_yaw)
		shot.recoil_signed = true
	_snap()
	_view.on_used(shot)
	_run(seconds)


func _reload(def: GSWeaponDef, empty: bool) -> void:
	var seconds := maxf(float(def.reload_ticks) / float(AwWeaponPack.TICK_RATE), 0.5)
	_view.on_reload_begin(0 if empty else int(def.magazine / 2), def.magazine, 0.0)
	var frames := int(ceil(seconds * FPS))
	for i in frames:
		_view.on_reload(clampf(float(i + 1) / float(frames), 0.0001, 0.9999), 1.0 / float(frames))
		_view.advance(STEP)
		_snap()
	_view.on_reload(0.0, 0.0)
	_run(0.25)


func _draw(def: GSWeaponDef) -> void:
	var seconds := maxf(float(def.deploy_ticks) / float(AwWeaponPack.TICK_RATE) if def != null else 0.0, 0.4)
	var frames := int(ceil(seconds * FPS))
	for i in frames:
		_view.on_deploy(clampf(float(i) / float(frames), 0.0, 0.9999), 1.0 / float(frames))
		_view.advance(STEP)
		_snap()
	_view.on_deploy(1.0, 0.0)
	_run(0.2)


func _inspect() -> void:
	_snap()
	_view.inspect()
	for _i in 8 * FPS:
		_view.advance(STEP)
		_snap()
		if _view.inspect_fraction() >= 1.0:
			break
	_run(0.2)


func _ads() -> void:
	_snap()
	_view.aim(true)
	_run(0.9)
	_view.aim(false)
	_run(0.9)


func _idle() -> void:
	var frames := int(SWAY_SECONDS * FPS)
	_snap()
	for i in frames:
		var turn := TAU * float(i + 1) / float(frames)
		_view.drive(Vector2(SWAY_DEGREES * sin(turn), SWAY_DEGREES * 0.5 * sin(turn * 2.0)), 0.0, true, false, 0.0)
		_view.advance(STEP)
		_snap()
	_view.drive(Vector2.ZERO, 0.0, true, false, 0.0)


func _run(seconds: float) -> void:
	for _i in int(ceil(seconds * FPS)):
		_view.advance(STEP)
		_snap()


## Reads every drawn part's transform now, one value per track. A track that starts late is backfilled with its first value.
func _snap() -> void:
	var weapon := _view.weapon_node()
	if weapon == null:
		return
	# The camera's frame, not the rig's own: a shot kicks the rig itself, and that motion is the clip.
	var parent := _view.get_parent() as Node3D
	var to_view := parent.global_transform.affine_inverse() if parent != null else Transform3D.IDENTITY
	var to_weapon := weapon.global_transform.affine_inverse()
	_put("weapon", "transform", _t7(to_view * weapon.global_transform))
	var art: AwWeaponVisual = _view._art
	if art.bolt_node != &"":
		var bolt := weapon.find_child(String(art.bolt_node), true, false) as Node3D
		if bolt != null:
			_put("bolt", "position", [bolt.position.x, bolt.position.y, bolt.position.z])
	var mag: Node3D = _view._own_magazine()
	if mag != null:
		_put("magazine", "transform", _t7(to_weapon * mag.global_transform))
		_put("magazine.visible", "visible", [1.0 if mag.is_visible_in_tree() else 0.0])
	var props: Node3D = _view._props
	if props != null:
		for k: Variant in props._nodes:
			var n: Node3D = props._nodes[k]
			if not _props.has(k):
				_props[k] = {"part": String(n.get_meta(&"part", &"")), "shapes": _shapes(n)}
			var at := to_view * n.global_transform
			_put("prop.%d" % k, "transform", _t7(at.orthonormalized()))
			_put("prop.%d.scale" % k, "position", [at.basis.get_scale().x, at.basis.get_scale().y, at.basis.get_scale().z])
			_put("prop.%d.visible" % k, "visible", [1.0 if n.is_visible_in_tree() else 0.0], [0.0])
	var arms: AwViewArms = _view._arms
	if arms != null and not arms.last_hands.is_empty():
		var to_arms: Transform3D = to_view * arms.global_transform
		for k: String in ["right", "left", "right_shoulder", "left_shoulder"]:
			if arms.last_hands.has(k):
				var p: Vector3 = to_arms * (arms.last_hands[k] as Vector3)
				_put("hand.%s" % k, "position", [p.x, p.y, p.z])
	var punch := _view.view_punch()
	_put("view_punch", "vec2", [punch.x, punch.y])
	_frames += 1


func _put(key: String, path: String, values: Array, before: Array = []) -> void:
	if not _tracks.has(key):
		var back: Array = []
		for _i in _frames:
			back.append_array(before if not before.is_empty() else values)
		_tracks[key] = {"path": path, "values": back}
	(_tracks[key].values as Array).append_array(values)


static func _t7(t: Transform3D) -> Array:
	var q := t.basis.orthonormalized().get_rotation_quaternion()
	return [t.origin.x, t.origin.y, t.origin.z, q.x, q.y, q.z, q.w]


static func _round(values: Array) -> Array:
	var out: Array = []
	for v: float in values:
		out.append(snappedf(v, 0.00001))
	return out


## Where the weapon sits in the hand mount, as AwWorldModel's holder places it (the art's world transform, its basis scaled by the pose's share of the hand scale): 12 floats, basis columns then origin.
static func _third_person(art: AwWeaponVisual) -> Dictionary:
	var rest := art.world_transform()
	rest = Transform3D(rest.basis.scaled(Vector3.ONE * AwWeaponArtTable.pose_world_factor(art.pose)), rest.origin)
	var b := rest.basis
	return {"pose": String(art.pose), "rest": [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, rest.origin.x, rest.origin.y, rest.origin.z]}


## The primitive meshes under a built reload part, in the part's space: {kind, size (box x y z; cylinder top, bottom, height; sphere radius, height), at (12 floats), colour, metal, rough, glow}.
static func _shapes(part: Node3D) -> Array:
	var out: Array = []
	var inv := part.global_transform.affine_inverse()
	for m: Node in part.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var shape := {}
		if mi.mesh is BoxMesh:
			var sz := (mi.mesh as BoxMesh).size
			shape = {"kind": "box", "size": [sz.x, sz.y, sz.z]}
		elif mi.mesh is CylinderMesh:
			var c := mi.mesh as CylinderMesh
			shape = {"kind": "cylinder", "size": [c.top_radius, c.bottom_radius, c.height]}
		elif mi.mesh is SphereMesh:
			var sp := mi.mesh as SphereMesh
			shape = {"kind": "sphere", "size": [sp.radius, sp.height]}
		else:
			continue
		var t := inv * mi.global_transform
		var b := t.basis
		shape["at"] = [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, t.origin.x, t.origin.y, t.origin.z]
		var mat := mi.get_active_material(0) as StandardMaterial3D
		if mat != null:
			shape["colour"] = mat.albedo_color.to_html(false)
			shape["metal"] = mat.metallic
			shape["rough"] = mat.roughness
			shape["glow"] = mat.emission.to_html(false) if mat.emission_enabled else ""
		out.append(shape)
	return out
