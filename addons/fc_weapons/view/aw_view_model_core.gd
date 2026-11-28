@tool
extends "aw_view_model_materials.gd"

## Build, hands, belt and teardown half of AwViewModel, split out for file size.

const ReloadProps := preload("aw_reload_props.gd")
const MagCarve := preload("aw_mag_carve.gd")

const CHANNEL := "aw.view"

@export_group("Wiring")

## The arms. Left null, the view model builds its own on first use.
## A [GSNodeRef], not a path: the host decides per instance.
@export var arms_ref: GSNodeRef = null

const BeltFeed := preload("aw_belt_feed.gd")
const ArmsColour := preload("aw_view_arms_colour.gd")

var _belt: Node3D = null

@export_group("Behaviour")

## Whether to build and show hands at all.
## A real configuration (non-humanoid characters, a gun with no holder), not a debug switch.
## Turned off after the model is built (a game mounting its own arms once this is in the tree), the built hands go too.
@export var show_arms: bool = true:
	set(value):
		show_arms = value
		if not _built:
			return
		if not value and _arms != null:
			if _arms.get_parent() == _animated:
				_animated.remove_child(_arms)
				_arms.queue_free()
			else:
				_arms.visible = false
			_arms = null
		elif value and _arms == null:
			_build_arms()
			if _art != null and _arms != null:
				_arms.set_pose(_art.pose)
				_reach_for(_art)

## Which skin the hands wear. Passed to [AwViewArms] when this builds its own.
@export_file("*.png", "*.jpg", "*.webp") var arm_skin: String = ""

## Keeps the built models of weapons put away and draws them again on switching back, instead of building them anew (a model load,
## a material pass, a sight fit and a magazine carve a switch, a stall on the web build). What is drawn is the same either way.
@export var cache_equips: bool = true:
	set(value):
		cache_equips = value
		if not value:
			_equip_cache.clear()

## How many put-away weapons are kept; the longest unused goes first. 0 keeps every one.
@export_range(0, 64) var equip_cache_limit: int = 6:
	set(value):
		equip_cache_limit = value
		_equip_cache.limit = value

@export_group("Wall")

## Draws the view model again in a pass with no world in it while it is pressed against one, so a wall cannot hide the gun. Costs a second render of the view layer only while active.
## Never built on the web (see [method AwViewOverlay.supported]): there a stencil pass draws the hidden part instead.
@export var wall_overlay: bool = true

@export_group("Light")

## The energy of the view model's own key light, which turns with the camera and lights only the view model. 0 builds none.
## The world's sun is fixed, so turning round leaves the gun lit by ambient alone; a key light keeps its side lit the same way.
@export_range(0.0, 4.0, 0.05) var view_light_energy: float = 0.3

## Where that light comes from, as Euler degrees of the light's own rotation in the camera's
## space: above, behind and to the left, so it rakes across the right side the hold shows.
@export var view_light_rotation: Vector3 = Vector3(-38.0, -32.0, 0.0)

## Sets [member hands_fov] from a horizontal field of view measured on a 4:3 frame, the
## convention a game's `field_of_view` setting already uses, so the two are comparable.
func set_hands_fov_at_4_3(horizontal: float) -> void:
	hands_fov = vertical_from_horizontal_4_3(horizontal)


## The vertical field of view that is [param horizontal] degrees across a 4:3 frame.
static func vertical_from_horizontal_4_3(horizontal: float) -> float:
	return GSViewLens.vertical_from_horizontal_4_3(horizontal)


func _init() -> void:
	add_to_group(&"gs_view_model")


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	_build_structure()
	if wall_overlay and view_layer > 0 and AwViewOverlay.supported():
		_overlay = AwViewOverlay.new()
		add_child(_overlay)
		_overlay.setup(self, view_layer)
	_reveal = wall_overlay and view_layer > 0 and _overlay == null


# Building:


func _build_structure() -> void:
	if _built:
		return

	_animated = Node3D.new()
	_animated.name = "Animated"
	add_child(_animated)

	# Aim is a node of its own because the aim hold is turned as well as moved: the hip hold is canted,
	# the aim hold is straight down the sight, and moving only the position brought a canted gun end-on to the middle.
	_aim_node = Node3D.new()
	_aim_node.name = "Aim"
	_animated.add_child(_aim_node)

	_holder = Node3D.new()
	_holder.name = "Holder"
	_aim_node.add_child(_holder)
	_hands_frame = Node3D.new()
	_hands_frame.name = "HandsFrame"
	add_child(_hands_frame)

	if show_arms:
		_build_arms()

	_build_light()
	_built = true


func _build_arms() -> void:
	if arms_ref != null:
		var found := arms_ref.resolve(self)
		if found.ok and found.value is AwViewArms:
			_arms = found.value
			_arms.build()
			return

	_arms = AwViewArms.new()
	_arms.view_layer = view_layer
	_arms.name = "Arms"
	_arms.skin = arm_skin
	# Under Animated so the hands move with the gun (a reload would otherwise slide it out of them).
	# Not under Aim: carried rigidly to the sight, the shoulders went with the gun; they reach for the aimed hands each frame (_place_hands).
	_animated.add_child(_arms)

	var res := _arms.build()

	if not res.ok:
		# Not fatal, and not even an error: a rig with no hands still draws the weapon,
		# which is what a great many games in this genre ship anyway.
		GSLog.info(
			CHANNEL, "no first-person hands; drawing the weapon alone",
			{"why": res.error.message}
		)


## The view model's own key light. See [member view_light_energy].
func _build_light() -> void:
	if view_light_energy <= 0.0 or view_layer <= 0:
		return

	_light = DirectionalLight3D.new()
	_light.name = "ViewLight"
	_light.light_energy = view_light_energy
	_light.light_cull_mask = 1 << (view_layer - 1)
	# A light for one object a metre from the eye casts nothing worth a shadow map, and it
	# must not draw a second sun in the sky.
	_light.shadow_enabled = false
	_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	_light.rotation_degrees = view_light_rotation
	add_child(_light)


# Weapons:


## Puts the hands on this weapon, measured from the weapon itself in the holder's space: a blaster's right hand round its grip,
## the left on the fore-end at 62%, a melee hand round its handle, a grenade's round its middle, each with the held axis.
func _reach_for(art: AwWeaponVisual) -> void:
	var to_aim := _holder.transform
	var r := HandReach.measure(art, _weapon, _holder)
	var grip: Vector3 = r.grip
	var fore: Vector3 = r.fore
	var grip_axis: Vector3 = r.grip_axis
	var fore_axis: Vector3 = r.fore_axis
	var radius: float = r.radius

	if _arms != null:
		_arms.fit_glove_to(_weapon)
	elif _weapon != null:
		# An armless view (the loading cover's spare) still reads the gun's texture means, so the
		# first armed equip in play finds them cached instead of downloading textures (26-64 ms).
		ArmsColour.surface_albedos(_weapon)
	_has_well = art.has_magazine() and _weapon != null
	_well = to_aim * art.magazine_transform().origin
	# A round fed by hand from somewhere (the top, the muzzle): where its push in starts, and
	# the bolt the hand works first, all in the same space as the well.
	_feeds = _has_well and art.magazine_loose and art.load_from.length_squared() > 0.000001
	_entry = to_aim * (art.magazine_offset + art.load_from)
	_bolted = _feeds and art.bolt_pull.length_squared() > 0.000001
	_bolt = to_aim * art.bolt_at
	_bolt_back = to_aim * (art.bolt_at + art.bolt_pull)

	_grip_at = to_aim * grip
	_fore_at = to_aim * fore
	_fore_aimed_at = to_aim * (r.get("fore_aimed", fore) as Vector3)  # perf-lint: allow dynamic_call Dictionary.get (the reach row)
	# After the fore-end: the keys start and end on it.
	_feed_keys = _build_feed_keys(art) if _feeds else []
	_grip_axis = (to_aim.basis * grip_axis).normalized()
	_fore_axis = (to_aim.basis * fore_axis).normalized()
	if _weapon == null:
		# Bare fists, raised: closed round nothing, knuckles forward, leaning in a little.
		_grip_axis = Vector3(-0.35, 1.0, -0.25).normalized()
		_fore_axis = Vector3(0.35, 1.0, -0.25).normalized()
	# In the view's metres: the holder's scale is the art's view_scale.
	_grip_radius = radius * art.view_scale
	_place_hands()


## Removes whatever is in hand.
func clear() -> void:
	_clear_models()
	_art = null
	_id = &""
	_muzzle = Vector3.ZERO


## The multiple of the default speed this weapon's cases leave at ([member AwWeaponVisual.eject_speed]).
func eject_speed() -> float:
	return _art.eject_speed if _art != null else 1.0


## How many times life size the weapon in hand is drawn (the holder's view_scale and the view lens), so a case thrown
## from it is drawn to the same scale; 1 with no weapon.
func eject_scale() -> float:
	if _weapon == null or not _weapon.is_inside_tree():
		return 1.0
	var s := _weapon.global_transform.basis.get_scale()
	return (absf(s.x) + absf(s.y) + absf(s.z)) / 3.0


## The moving belt of a belt-fed gun, or null.
func belt_feed() -> Node3D:
	return _belt


func _build_belt(art: AwWeaponVisual) -> void:
	_belt = null
	if not art.belt_feed or _weapon == null:
		return
	var box := HandReach.bounds_in(_weapon, _weapon)
	if box.size == Vector3.ZERO:
		return
	var tray := Vector3(box.position.x * 0.8, box.position.y + box.size.y * 0.62, box.position.z + box.size.z * 0.5) + art.belt_offset
	# The run comes up from under the receiver (where the box hangs) to the tray on its left side: started out past the
	# side instead, it is a row of rounds hanging in the air beside the gun.
	var from := Vector3(box.position.x * 0.35, box.position.y + box.size.y * 0.2, tray.z) + art.belt_offset
	_belt = BeltFeed.new()
	_belt.name = "BeltFeed"
	_weapon.add_child(_belt)
	_belt.build(from, tray)


## True when the weapon in hand throws a spent case ([member AwWeaponVisual.ejects]).
func ejects() -> bool:
	return _art != null and _art.ejects and _weapon != null


## Where the ejection port is right now, in world space: the receiver's right side, 45% from stock to muzzle, measured from the mesh bounds.
## The basis is the weapon's, unscaled (+X out of the right side, +Y up, -Z to the muzzle). Effects only.
func eject_transform() -> Transform3D:
	if _weapon == null:
		return global_transform

	var world := _weapon.global_transform
	return Transform3D(world.basis.orthonormalized(), world * HandReach.eject_local(_weapon, _art))


# Being told what happened:


var _props: ReloadProps = null

## The magazine split out of a one-mesh model (MagCarve), a node of the weapon; null when the model has its own or none.
var _carved: Node3D = null


## Makes the magazine of a gun whose model draws it welded into the body a node of its own, from the triangles in the
## magazine well's box (the row's `reload.mag_box`, six numbers in Aim space, or one measured from the well).
## Where the magazine sits in each welded model, in the holder's space: x0, y0, z0, x1, y1, z1. Read off rendered side views
## (tools/render_reload.gd --probe). An empty array means the mesh holds no magazine to take out.
const MAG_BOXES := {
	"machine_pistol.glb": [-0.12, -0.175, -0.067, 0.12, -0.012, 0.031],
	"drum_shotgun.glb": [-0.12, -0.11, 0.20, 0.12, 0.05, 0.37],
	"marksman.glb": [-0.12, -0.03, -0.245, 0.12, 0.03, -0.14],
	"sniper_ph.glb": [-0.12, -0.01, -0.17, 0.12, 0.04, -0.095],
	"lmg.glb": [-0.2, -0.125, -0.31, 0.2, 0.10, -0.155],
	"bullpup.glb": [],
}

func _carve_magazine(art: AwWeaponVisual) -> void:
	_carved = null
	if art.hide_during_reload != &"" or art.has_magazine() or _weapon == null or feel_rules.reload_detail <= 0.0:
		return
	var style := ReloadSequence.style_of(art)
	if style not in [&"magazine", &"pistol", &"cell", &"belt"]:
		return
	var to_aim := _holder.transform
	var well: Variant = _well if _has_well and art.reload.is_empty() else null
	var anchors := ReloadSequence.anchors_for(_grip_at, _fore_at, to_aim * (_weapon.transform * _muzzle), well, art.reload.get("anchors", {}), to_aim)
	var seq := ReloadSequence.new()
	seq.compose(art, anchors, 30, 15)
	var ps: float = seq.prop_scale
	var box := AABB()
	var held: Variant = MAG_BOXES.get(art.model_path.get_file(), null)
	if held is Array and (held as Array).is_empty():
		return
	if style == &"belt" and held == null and art.reload.get("mag_box", null) == null:
		return
	var given: Variant = art.reload.get("mag_box", null)
	if held is Array and given == null:
		var h: Array = held
		box = AABB(Vector3(h[0], h[1], h[2]), Vector3(h[3] - h[0], h[4] - h[1], h[5] - h[2]))
		MagCarve.remember(art.model_path, box)
		_carved = MagCarve.carve(_weapon, _holder, Transform3D.IDENTITY, box, "%s|%s" % [art.model_path, box])
		if _carved != null:
			_set_on_top(_carved)
		return
	if given is Array and (given as Array).size() == 6:
		var g: Array = given
		box = AABB(Vector3(g[0], g[1], g[2]), Vector3(g[3] - g[0], g[4] - g[1], g[5] - g[2]))
	else:
		var w: Vector3 = anchors[&"well"]
		var half := Vector3(0.03, 0.0, 0.045) * ps
		box = AABB(w - Vector3(half.x, 0.17 * ps, half.z), Vector3(half.x * 2.0, 0.18 * ps, half.z * 2.0))
	# In the holder's space, where the watcher's model of the gun finds it too.
	box = to_aim.affine_inverse() * box
	MagCarve.remember(art.model_path, box)
	_carved = MagCarve.carve(_weapon, _holder, Transform3D.IDENTITY, box, "%s|%s" % [art.model_path, box])
	if _carved != null:
		_set_on_top(_carved)

func _animate_sequence(f: float) -> void:
	var out: bool = _seq.own_magazine_out(f)
	if _magazine != null:
		_magazine.visible = not _art.magazine_loose and not out
		_magazine.transform = _art.magazine_transform()
	if _props == null and _art.hide_during_reload != &"" and _weapon != null:
		var own := _weapon.find_child(String(_art.hide_during_reload), true, false) as Node3D
		if own != null:
			own.visible = not out
	if _props != null:
		var scale := maxf(_holder.transform.basis.get_scale().x, 0.0001)
		_props.show_at(_seq, f if f > 0.0 and f < 1.0 else -1.0, _holder.transform.affine_inverse(), float(_seq.prop_scale) / scale)
	var stroke: Vector2 = _seq.bolt_stroke(f) if f > 0.0 and f < 1.0 else Vector2.ZERO
	_set_bolt(stroke.y, stroke.x)


## The cycle a bolt or pump gun works after a shot ([member AwWeaponVisual.cycle_style]): seconds since the shot, -1 when none
## runs. It waits a beat for the recoil, works the part back, holds, and closes it, all inside the fire interval so the gun is
## ready again as the next shot is. A reload cuts it short.
func _start_cycle(interval: float) -> void:
	if _art == null or _art.cycle_style == &"" or _art.cycle_time <= 0.0 or _art.bolt_node == &"" or _seq != null:
		return
	var gap := interval if interval > 0.0 else _art.cycle_time + CYCLE_WAIT
	_cycle_wait = minf(CYCLE_WAIT, gap * 0.25)
	_cycle_len = maxf(minf(_art.cycle_time, gap - _cycle_wait - 0.02), 0.05)
	_cycle_t = 0.0
	_cycle_heard = 0


func _advance_cycle(delta: float) -> void:
	if _cycle_t < 0.0:
		return
	if _seq != null or _art == null:
		_end_cycle()
		return
	_cycle_t += delta
	var f := (_cycle_t - _cycle_wait) / _cycle_len
	if _art.bolt_lift != 0.0:
		var stroke := lifted_stroke(f)
		_set_bolt(stroke.y, stroke.x)
	else:
		_set_bolt(cycle_back(f))
	var cues: Array = CYCLE_CUES.get(_art.cycle_style, NO_CUES)
	if cues.size() == 2:
		if _cycle_heard == 0 and f >= 0.0:
			_cycle_heard = 1
			cycle_cue.emit(cues[0], -3.0)
		elif _cycle_heard == 1 and f >= CYCLE_SPLIT[1]:
			_cycle_heard = 2
			cycle_cue.emit(cues[1], -3.0)
	if f >= 1.0:
		_end_cycle()


func _end_cycle() -> void:
	_cycle_t = -1.0
	_cycle_back = 0.0
	_cycle_shift = Vector3.ZERO


## Draws the art's [member AwWeaponVisual.bolt_node] [param back] (0 rest, 1 fully charged) of [member AwWeaponVisual.bolt_travel]
## along [member AwWeaponVisual.bolt_axis] toward the stock, turned [param lift] (0 to 1, below 0: up whenever it is back) of
## [member AwWeaponVisual.bolt_lift] about [member AwWeaponVisual.bolt_pivot]. The rest transform is kept on the node the first time
## it moves, so a sequence cut short puts it back. How the handle moved, in the holder's space, is left in [member _cycle_shift].
func _set_bolt(back: float, lift: float = -1.0) -> void:
	if _art == null or _art.bolt_node == &"" or _art.bolt_travel <= 0.0 or not is_instance_valid(_weapon):
		return
	var bolt := _weapon.find_child(String(_art.bolt_node), true, false) as Node3D
	if bolt == null:
		return
	if not bolt.has_meta(&"aw_bolt_rest"):
		bolt.set_meta(&"aw_bolt_rest", bolt.transform)
	var rest: Transform3D = bolt.get_meta(&"aw_bolt_rest")
	back = clampf(back, 0.0, 1.0)
	lift = clampf(back * 4.0 if lift < 0.0 else lift, 0.0, 1.0)
	var moved := rest.translated(_art.bolt_axis * (_art.bolt_travel * back))
	if _art.bolt_lift != 0.0 and lift > 0.0:
		var turn := Transform3D(Basis(_art.bolt_axis.normalized(), deg_to_rad(_art.bolt_lift * lift)), Vector3.ZERO)
		var pivot := Transform3D(Basis.IDENTITY, _art.bolt_pivot)
		moved = pivot * turn * pivot.affine_inverse() * moved
	bolt.transform = moved
	_cycle_back = back
	_cycle_shift = _shift_of(bolt, moved * rest.affine_inverse() * _art.cycle_at - _art.cycle_at)


## [method _set_bolt]'s [param moved] (the handle's move in the bolt's parent's space) taken through the parents up to the holder.
func _shift_of(bolt: Node3D, moved: Vector3) -> Vector3:
	var parent := bolt.get_parent() as Node3D
	var world := parent.global_transform.basis * moved
	return _holder.transform.basis * (_holder.global_transform.basis.inverse() * world)


## The scale that draws the hands at [member hands_fov]. See there.
func _apply_hands_lens() -> void:
	# Only under a camera: the scale is in the camera's own space, and a view model hung
	# anywhere else is in some other space where this would be a distortion, not a lens.
	GSViewLens.apply(self, get_parent() as Camera3D, hands_fov, hands_depth_comp)


## How much X and Y are scaled to draw at [param hands] degrees under a [param camera]-degree
## lens. 1 when either is not a usable field of view.
static func lens_scale(camera: float, hands: float) -> float:
	return GSViewLens.lens_scale(camera, hands)


# Aiming:


## Smoothstep, so the weapon leaves the hip and arrives at the eye gently.
static func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


## Whether the carrier is sprinting: the weapon lowers and swings to the side, blended over [constant SPRINT_SECONDS].
func set_sprinting(on: bool) -> void:
	_sprinting = on


## Where the sprint carry is, 0 (hip) to 1.
func sprint_fraction() -> float:
	return _sprint


## Tells the rig how the holder is moving and looking this frame.
## [param look] is absolute yaw and pitch in degrees (the rig takes the difference itself, so sway is computed once);
## [param strafe] is sideways ground speed in m/s, positive right; left out, measured from this node's own movement.
func drive(look: Vector2, speed: float, on_floor: bool, crouched: bool = false, strafe: float = NAN) -> void:
	_strafe_given = strafe
	_look = look
	_speed = speed
	_on_floor = on_floor
	_crouched = crouched


## Drops the magazine out and slides a fresh one in, if there is one to animate.
func _animate_magazine(fraction: float) -> void:
	if _seq != null:
		_animate_sequence(clampf(fraction, 0.0, 1.0))
		return
	if _magazine == null or _art == null:
		return

	var f := clampf(fraction, 0.0, 1.0)
	var rest := _art.magazine_transform()

	# The gun's own magazine node is out of the gun from when the hand pulls it (0.20) to the seat.
	if _art.hide_during_reload != &"" and _weapon != null:
		var own := _weapon.find_child(String(_art.hide_during_reload), true, false) as Node3D
		if own != null:
			own.visible = not (f >= 0.20 and f < 0.58)

	# Timed to the reload keys (AwWeaponPose.RELOAD_KEYS_*) and `_support_hand`: out while the gun rolls onto its side (0.10-0.28),
	# in the hand from 0.36, seated with the jolt at 0.58. Visible throughout it reads as the gun shaking; rising from nothing, as a hand reaching for air.
	var shown := true
	var at := rest.origin
	var basis := rest.basis

	if _feeds:
		# Fetched, carried to where its push starts and pushed home (_build_feed_keys).
		var fed := _fed_round(f)
		shown = fed.is_finite()
		if shown:
			at = fed
	elif _art.magazine_loose:
		# A round fed by hand: in sight only while it is carried in.
		shown = f >= 0.36 and f < 0.58
		if shown and _holder != null:
			# Held up between the fingertips, higher than a magazine: a round inside the fist
			# is a hand that fetched nothing.
			var carried := _holder.transform.affine_inverse() * (_support_hand() + Vector3(0.0, 0.065, 0.0))
			at = carried if carried.is_finite() else rest.origin
	elif f >= 0.10 and f < 0.28:
		var drop := (f - 0.10) / 0.18
		# Falls, faster as it goes, and tips forward off the hand's line.
		at = rest.origin + Vector3(0.0, -0.40 * drop * drop - 0.04 * drop, 0.02 * drop)
		basis = rest.basis * Basis(Vector3.RIGHT, deg_to_rad(-35.0 * drop))
	elif f >= 0.28 and f < 0.36:
		shown = false
	elif f >= 0.36 and f < 0.58 and _holder != null:
		# Where the support hand is, a little above the palm, in the holder's (model) space.
		var settle := clampf((f - 0.36) / 0.22, 0.0, 1.0)
		var carry := _art.magazine_carry.lerp(Vector3(0.0, 0.035, 0.0), settle * settle * settle)
		var hand := _support_hand() + carry
		var held := _holder.transform.affine_inverse() * hand
		at = held if held.is_finite() else rest.origin
		basis = rest.basis * Basis(Vector3.RIGHT, deg_to_rad(-20.0 * (1.0 - settle)))

	_magazine.visible = shown
	_magazine.transform = Transform3D(basis, at)


func _add_part(path: String, at: Transform3D) -> Node3D:
	if path == "":
		return null

	var part := AwModelCache.instantiate(path)

	if part == null:
		return null

	_holder.add_child(part)
	part.transform = at
	_set_on_top(part)
	return part


## The held weapon art's first-person hand size, 0 when it keeps the arms' own.
func art_hand_scale() -> float:
	return _art.hand_scale if _art != null else 0.0


## How the hands close on the held weapon: its `hand_grip` row plus `pose` and the world `forward` and `up` of the drawn gun.
func art_hand_grip() -> Dictionary:
	if _art == null or _weapon == null:
		return {}
	var out := _art.hand_grip.duplicate()
	var b := _weapon.global_transform.basis.orthonormalized()
	out["pose"] = _art.pose
	out["forward"] = (b * _art.model_forward).normalized()
	out["up"] = b.y if _art.pose != &"melee" else -b.z
	return out


func art_forearm_scale() -> float:
	return _art.forearm_scale if _art != null else 0.0


## The art's trimmed elbow-clearance box in the weapon node's space (zero size: measure the meshes instead).
func art_clear_box() -> AABB:
	return _art.clear_box if _art != null else AABB()


## The weapon's arm-lean cap, or below 0 for the arms' own.
func art_max_lean() -> float:
	return _art.max_lean if _art != null else -1.0


## Measures the muzzle, honouring an override on the art.
func _measure_muzzle(art: AwWeaponVisual) -> Vector3:
	if art.muzzle_socket.is_finite():
		return art.muzzle_socket

	var distance := art.muzzle_distance

	if distance <= 0.0:
		distance = AwModelCache.muzzle_distance(art.model_path, art.model_forward)

	distance = maxf(distance, float(_dressed.get("reach", 0.0)))
	return art.model_forward.normalized() * distance + art.muzzle_offset


func _clear_models() -> void:
	if _build_key != "" and _weapon != null and is_instance_valid(_weapon):
		_stow()
	_build_key = ""
	for node in [_weapon, _magazine, _sight]:
		if node != null and is_instance_valid(node):
			node.queue_free()
	_sight = null
	_sight_line = {}
	_dressed = {}
	_worn_key = ""
	_fitting = null

	for node in _attachments:
		node.queue_free()

	_weapon = null
	_belt = null
	_magazine = null
	_attachments.clear()
	_scope_glass = null


# Keeping built weapons:


const DressUndo := preload("aw_attachment_dress.gd")
const _StowGlass := preload("aw_scope_glass.gd")

## How many put-away weapons are held for a quick switch back.
func equip_cache_size() -> int:
	return _equip_cache.size()


## Frees every put-away weapon. The rig does it for you on leaving; a game that swaps its whole kit may do it sooner.
func clear_equip_cache() -> void:
	_equip_cache.clear()
	prewarmed.clear()


## What the built weapon depends on besides its art: the art itself, the rules read at build and the finish. A build is reused only under the same key.
func _equip_key(art: AwWeaponVisual) -> String:
	return "|".join([EquipCache.describe_object(art), AwModelCache.resolve(art.model_path),
		EquipCache.describe_object(ads_rules), EquipCache.describe_object(feel_rules), str(view_layer), str(_reveal),
		str(finish_materials), str(finish_metal), str(finish_metal_roughness), str(finish_polymer_roughness),
		str(finish_wood_roughness), str(finish_lift), "" if _fitting == null else _fitting.key()])


## Notes that the weapon in hand is built through (every stage run): from here on it can be put away and kept.
## Not for a prewarm, which builds on a spare rig only to warm what the real one reads.
func _note_built(art: AwWeaponVisual) -> void:
	if not cache_equips or _prewarming:
		_build_key = ""
		return
	_build_key = _equip_key(art)
	_build_shape = EquipCache.snapshot(_stow_roots())


## Ends a prewarm: the finished build goes to [member prewarmed] under the key a real view would look it up by, or is dropped
## when [member keep_prewarmed] is off or the build is not whole. The view is left empty either way.
func _keep_prewarm() -> void:
	if keep_prewarmed and cache_equips and _weapon != null and is_instance_valid(_weapon) and _fitting == null:
		_build_key = _equip_key(_art)
		_build_shape = EquipCache.snapshot(_stow_roots())
		var key := _build_key
		_stow()
		_build_key = ""
		prewarmed.put(key, _equip_cache.take(key))
	clear()


## The nodes of the weapon in hand that sit under the holder, in draw order.
func _stow_roots() -> Array:
	var wanted: Array = [_weapon, _magazine, _sight]
	wanted.append_array(_attachments)
	var out: Array = []
	for child in _holder.get_children():
		if child in wanted:
			out.append(child)
	return out


## Ends a reload or action in flight; AwViewModel's reload layer does the work.
func _end_sequence() -> void:
	pass


## Takes the weapon in hand out of the holder and keeps it, as it was just built: no fitting, no reload in flight.
func _stow() -> void:
	_end_sequence()
	DressUndo.clear(_dressed)
	var roots := _stow_roots()
	for node: Node in roots:
		_holder.remove_child(node)
	for node: Variant in _attachments:
		if node is Node3D and (node as Node3D).name == &"ScopeGlass":
			_StowGlass.release(node)
	# A build pushed out of this view's own cache goes to the shared store (aw_equip_cache.gd spill), not the bin.
	_equip_cache.spill = prewarmed
	if is_inside_tree():
		EquipCache.free_at_exit(get_tree(), prewarmed)
	_equip_cache.put(_build_key, {
		"roots": roots, "shape": _build_shape,
		"weapon": _weapon, "magazine": _magazine, "sight": _sight, "belt": _belt, "carved": _carved,
		"attachments": _attachments.duplicate(), "rear_rings": _rear_rings.duplicate(),
		"sight_line": _sight_line, "sight_aim": _sight_aim, "muzzle": _muzzle, "reach": _reach_state(),
	})
	_weapon = null
	_magazine = null
	_sight = null
	_belt = null
	_carved = null
	_attachments.clear()
	_scope_glass = null
	_rear_rings.clear()


## Puts back the weapon kept under [param key], as [method equip]'s stages left it; false when none is kept.
func _unstow(key: String) -> bool:
	var slot := _equip_cache.take(key)
	if slot.is_empty():
		slot = prewarmed.take(key)
	if slot.is_empty():
		return false
	for node: Node in slot.roots:
		_holder.add_child(node)
	EquipCache.restore(slot.shape)
	_weapon = slot.weapon
	_magazine = slot.magazine
	_sight = slot.sight
	_belt = slot.belt
	_carved = slot.carved
	_attachments.clear()
	_scope_glass = null
	_attachments.append_array(slot.attachments)
	# The kept glass is driven again: left without updates it would hold whatever render mode it was stowed in.
	for node: Variant in slot.attachments:
		if node is Node3D and (node as Node3D).name == &"ScopeGlass":
			_scope_glass = node
	_rear_rings.clear()
	_rear_rings.append_array(slot.rear_rings)
	_ring_fade = -1.0
	_sight_line = slot.sight_line
	_sight_aim = slot.sight_aim
	_muzzle = slot.muzzle
	_set_reach_state(slot.reach)
	_worn_key = ""
	_build_key = key
	_build_shape = slot.shape
	return true


## What [method _reach_for] works out from the model (kept, so a reuse does not measure it again).
func _reach_state() -> Array:
	return [_has_well, _well, _feeds, _entry, _bolted, _bolt, _bolt_back, _grip_at, _fore_at, _fore_aimed_at,
		_feed_keys, _grip_axis, _fore_axis, _grip_radius]


## The half of [method _reach_for] that touches the arms, with the measurements it would have made given back.
func _set_reach_state(r: Array) -> void:
	_has_well = r[0]
	_well = r[1]
	_feeds = r[2]
	_entry = r[3]
	_bolted = r[4]
	_bolt = r[5]
	_bolt_back = r[6]
	_grip_at = r[7]
	_fore_at = r[8]
	_fore_aimed_at = r[9]
	_feed_keys = r[10]
	_grip_axis = r[11]
	_fore_axis = r[12]
	_grip_radius = r[13]
	if _arms != null:
		_arms.fit_glove_to(_weapon)
	_place_hands()


## The range at which the hip barrel crosses the screen's centre (metres), 0 when it is stood up by `hip_lean` instead.
func hip_zero() -> float:
	var id := _art.id if _art != null else &""
	return ads_rules.hip_zero_for(id) if ads_rules != null else float(AwAdsRules.SPECS["hip_zero"]["default"])


func _toggles() -> bool:
	return ads_rules != null and _art != null and ads_rules.toggle_for(_art.id)


## Whether the weapon in hand can be aimed at all (melee and throwables cannot).
func can_aim() -> bool:
	return _art != null and _art.aim_enabled and (ads_rules == null or ads_rules.enabled_for(_art.id))
