@tool
class_name AwViewModel
extends "aw_view_model_scope.gd"

const ReloadParts := preload("aw_reload_parts.gd")
const Dress := preload("aw_attachment_dress.gd")
const HipHold := preload("aw_hip_hold.gd")
const ScopeHousing := preload("aw_scope_housing.gd")
const ScopeGlass := preload("aw_scope_glass.gd")

## The weapon you see in your own hands. Parent it to the camera; it is told what happened (on_used, on_reload_started)
## and never reads a device, a clock or the arsenal, so it draws a remote player's gun the same way.
## Presentation only: it runs on render frames and never writes to the simulation.


## Emitted once the weapon model for [param id] is in the tree and placed.
## For a muzzle flash, laser or scope overlay that cannot be hung before the model exists.
signal model_ready(id: StringName, weapon: Node3D)


@export_group("Wiring")


@export_group("Behaviour")

const ChargeFx := preload("aw_charge_fx.gd")
const GrenadePin := preload("aw_grenade_pin.gd")
## The shortest time (seconds) a scope takes to lower from full aim.
const SCOPE_LOWER_TIME := 0.3
var _charge_fx: Node3D = null
## The model's own rear aperture rings (mesh nodes named `rear_ring`) and a built sight's rear notch: drawn only once
## the aim is this far in, since at the hip a ring a few centimetres from the eye is a hoop around the crosshair.
const REAR_RING_SHOW_AIM := 0.35


## Hides the whole rig. What a "view model" video setting toggles.
@export var visible_model: bool = true:
	set(value):
		visible_model = value
		visible = value

@export_group("Wall")


@export_group("Light")


@export_group("Finish")

@export_group("Feel")

## Scales sway, bob and kick for everything this rig draws.
@export_range(0.0, 3.0, 0.05) var feel: float = 1.0


## Draws [param art]'s weapon, replacing whatever was in hand; a model built before is put back from the kept ones ([member cache_equips]); every model in the tree is culled per player, so the old one leaves the tree rather than hiding.
func equip(art: AwWeaponVisual) -> GSResult:
	_forget_mesh_walks()
	_late_art = null
	var head := _equip_head(art, true)
	# Drawn while a late group streams: the model may be missing, or a stand-in under this id; look again after the mount.
	if art != null and AwModelCache.late_pending():
		_late_art = art
		_late_failed = not head.ok
	if not head.ok or head.value_or(null) == null:
		return head
	if not _reused:
		for stage in EQUIP_STAGES:
			_equip_stage(_art, stage)
		_note_built(_art)
	model_ready.emit(_id, _weapon)
	return GSResult.success(null)


## The part of [method equip] before its stages: the pose, the holder and the model load. Its value is the weapon node, or null for fists.
## With [param reuse], a weapon kept from an earlier equip of the same art is put back whole ([member _reused]), its stages already run.
func _equip_head(art: AwWeaponVisual, reuse: bool = false) -> GSResult:
	_build_structure()

	if art == null:
		clear()
		return GSResult.fail(GSError.CODE_INVALID, "No art to equip.")

	_clear_models()

	_end_sequence()
	_source_art = art
	_art = HipHold.sized(art, ads_rules, position.z)
	art = _art
	_id = art.id
	_pose.weight = art.weight
	_pose.rules = feel_rules
	_pose.feel = maxf(0.0, feel)
	_pose.tunables.draw_keys = art.draw_keys if not art.draw_keys.is_empty() \
		else AwWeaponPose.DRAW_KEYS
	# A weapon with its own draw holsters along it; the shared draw has its own holster.
	_pose.tunables.holster_keys = art.draw_keys if not art.draw_keys.is_empty() \
		else AwWeaponPose.HOLSTER_KEYS
	_pose.tunables.reload_keys = _default_reload_keys()
	var carry := AwWeaponArtTable.sprint_view(art.pose)
	_pose.tunables.sprint_offset = art.sprint_offset if art.sprint_offset.is_finite() else carry[0]
	_pose.tunables.sprint_rotation = art.sprint_rotation if art.sprint_rotation.is_finite() else carry[1]
	var bob := AwWeaponArtTable.sprint_bob(art.pose)
	_pose.tunables.sprint_bob = bob.x
	_pose.tunables.sprint_bob_roll = bob.y
	_pose.tunables.sprint_pump = AwWeaponArtTable.sprint_pump(art.pose)
	_reload_fraction = 0.0

	_holder.transform = art.view_transform()
	_pose.pivot = _holder.transform.origin  # the kick turns about the grip
	_pose.aim_shift = Vector3.ZERO  # aim is the Aim node's (_apply_aim); a new weapon starts at the hip
	_aim_fraction = 0.0
	_aim_node.transform = Transform3D.IDENTITY
	_zoom_level = 0

	if _arms != null:
		_arms.set_pose(art.pose)

	if not art.has_model():
		# The fists: hands and no object. Not a failure, not worth a log line.
		_muzzle = Vector3.ZERO
		_reach_for(art)
		model_ready.emit(_id, null)
		return GSResult.success(null)

	_reused = reuse and cache_equips and _unstow(_equip_key(art))
	if _reused:
		_pin.bind(_weapon if art.pose == AwWeaponArtTable.POSE_THROWN else null)
		return GSResult.success(_weapon)

	_weapon = AwModelCache.instantiate(art.model_path)

	if _weapon == null:
		return GSResult.fail(
			GSError.CODE_IO, Describe.no_model_message(art.id), art.model_path
		)

	_weapon.name = "Weapon"
	_drop_parts(art)
	_pin.bind(_weapon if art.pose == AwWeaponArtTable.POSE_THROWN else null)
	_holder.add_child(_weapon)
	_set_on_top(_weapon)
	return GSResult.success(_weapon)


## Frees the parts [member AwWeaponVisual.view_drop] names from the first-person model, before anything measures or cuts it.
## A name the model lacks is an error in the art row, so it says so.
func _drop_parts(art: AwWeaponVisual) -> void:
	for part: String in art.view_drop:
		var node := _weapon.find_child(part, true, false)
		if node == null:
			push_error(Describe.missing_drop_message(art.id, part))
			continue
		node.get_parent().remove_child(node)
		node.free()


## Draws [param fitting]'s attachments on the weapon in hand, and moves the muzzle and the sight line to suit.
func set_fitting(fitting: GSWeaponFitting) -> void:
	_fitting = fitting.duplicate_fitting() if fitting != null else null
	if _weapon == null:
		return
	# The build in hand already wears this fitting (none on a fresh or kept build, and the rig tells every switch): nothing to redraw or refit.
	if _fitting_key() == _worn_key:
		return
	# The kept build is of the fitting it was made with: refitted in hand, it is no longer one to keep.
	_build_key = "" if _equip_key(_art) != _build_key else _build_key
	_dress()
	_muzzle = _measure_muzzle(_art)
	if _sight != null:
		_sight.queue_free()
		_sight = null
	_fit_sight(_art)
	_apply_aim(_ease(_aim_fraction))


func _fitting_key() -> String:
	return "" if _fitting == null else _fitting.key()


func _dress() -> void:
	_dressed = Dress.apply(_weapon, _fitting, _art.model_forward, _dressed)
	_worn_key = _fitting_key()
	_forget_mesh_walks()
	for part: Node3D in _dressed.parts:
		_set_on_top(part)


## The weapon currently drawn, or an empty name.
func equipped() -> StringName:
	return _id


## The drawn weapon's model node, or null. A search by name can find the last one, which is freed only at the frame's end.
func weapon_node() -> Node3D:
	return _weapon


## Seconds between this weapon's shots, set by the rig; drives the kick spring's rate.
var fire_interval: float = 0.0


## Sets this weapon's kick feel from its profile params (see [method AwWeaponPose.Tunables.apply_kick]).
func set_kick_params(params: Dictionary) -> void:
	_pose.tunables.apply_kick(params)


## A use produced [param outcome].
func on_used(outcome: GSWeaponOutcome) -> void:
	if outcome == null or not outcome.used:
		return

	_pose.fire_interval = fire_interval
	_pose.punch(outcome.recoil, outcome.recoil_signed)
	if _belt != null and outcome.kind == GSWeaponOutcome.KIND_SHOT:
		_belt.step()
	if outcome.kind == GSWeaponOutcome.KIND_SHOT:
		_start_cycle(fire_interval)
	match outcome.kind:
		GSWeaponOutcome.KIND_SWING:
			_pose.swing()
		GSWeaponOutcome.KIND_THROW:
			_pose.throw()


## Recoil with no outcome to hand, for a remote player whose shots arrive as a counter.
func on_fired(recoil: Vector2 = Vector2(0.5, 0.1)) -> void:
	_pose.punch(recoil)


## A melee swing with no outcome to hand (a bash, or a remote player's swing): the swing's keys.
func on_swing() -> void:
	_pose.swing()


## A throw with no outcome to hand (the owner's knife leaves on the server): the release keys, from the windup
## if one is showing. Skipped while an action already plays, so a throw seen both ways plays once.
func on_throw() -> void:
	if _pose.action_fraction() >= 1.0:
		_pose.throw()


## A thrown weapon caught back into an empty hand: the catch keys instead of a draw.
func on_catch() -> void:
	_pose.catch()


## Looks the weapon over (the inspect keys). False when it is not resting in the hand; a shot, an aim, a reload,
## a sprint, a swing or a switch cancels it.
func inspect() -> bool:
	return _pose.inspect()


## Eases a playing inspect back into the hand.
func cancel_inspect() -> void:
	_pose.cancel_inspect()


## How far through an inspect, 0 to 1; 1 when none is playing.
func inspect_fraction() -> float:
	return _pose.inspect_fraction()


## How far recoil should turn the camera this frame, in degrees: x pitch up, y yaw.
## This node cannot apply it: controllers write the camera's angles from scratch each frame, so the game adds it
## where it writes the camera (`GSFpsView.external_angles`).
func view_punch() -> Vector2:
	return _pose.view_punch()


## How far a scope's lens and reticle sit off centre this frame, in lens radii (see [method AwWeaponPose.scope_offset]).
func scope_offset() -> Vector2:
	return _pose.scope_offset()


## How far the held breath turns the scoped view this frame, in degrees (x yaw, y pitch); zero unless a scope is up.
## Like [method view_punch] the node cannot apply it: the game adds it where it writes the camera. Presentation only: the aim the server reads is untouched.
func scope_breath_angles() -> Vector2:
	return _pose.view_breath(scope_fraction())


## A charged weapon's draw, 0 to 1.
func on_charge(fraction: float) -> void:
	# A grenade's charge is its cook: the hand draws back by it like a knife's windup, and no charge ball glows on it.
	if _art != null and _art.pose == AwWeaponArtTable.POSE_THROWN:
		_cook_windup = fraction if is_finite(fraction) and fraction > 0.0 else -1.0
		if _cook_windup > 0.0:
			_pin.pull()  # the pin comes out as the cook starts, once per grenade
		_pose.set_windup(maxf(_cook_windup, _game_windup))
		return
	_pose.set_charge(fraction)
	if fraction > 0.0 and _charge_fx == null and _built:
		_charge_fx = ChargeFx.new()
		_charge_fx.name = "ChargeFx"
		_charge_fx.follow = muzzle_transform
		add_child(_charge_fx)
	if _charge_fx != null:
		_charge_fx.set_charge(fraction)


## A throw's meter (gs-weapon's `charge_of`): 0 to 1 while it winds up, below 0 when not. The hand draws back past
## the ear, further the fuller it is; the throw outcome then releases from there.
func on_windup(fraction: float) -> void:
	_game_windup = fraction if is_finite(fraction) and fraction >= 0.0 else -1.0
	_pose.set_windup(maxf(_cook_windup, _game_windup))


## The two meters a throw's hand draws back by: the game's (a knife's windup, [method on_windup]) and a grenade's
## cook ([method on_charge]). Below 0 is none; both are sent every frame, so neither may clear the other.
var _game_windup := -1.0
var _cook_windup := -1.0
## The grenade in hand's pin ([code]aw_grenade_pin.gd[/code]): pulled on the cook, back in on the next grenade.
var _pin := GrenadePin.new()


## The pin of the grenade in hand, for a suite.
func grenade_pin() -> RefCounted:
	return _pin


## The sprint stride for arms that pump the free hand: how much shows (0 to 1) and where in it, 0 to 1 a stride.
func run_amount() -> float:
	return _pose.run_amount()


func run_phase() -> float:
	return _pose.run_phase()


## The weapon fired this frame, for the charge ball to tell a shot from a fizzle.
func note_fired() -> void:
	if _charge_fx != null:
		_charge_fx.note_fired()


## The charge ball, or null before the weapon has been charged. For a suite.
func charge_fx() -> Node3D:
	return _charge_fx


## A landing, with the downward speed in metres a second.
func on_landed(impact: float) -> void:
	_pose.land(impact)


## Everything back to rest. A respawn, a teleport, a correction.
func on_reset() -> void:
	_pose.reset()
	_wall.reset()
	_wall_excluded.clear()
	_look_seen = false
	_aim_fraction = 0.0
	_clip_left = 0.0
	# The next frame turns it back on if the gun is still in the world; a parked view model has no next frame.
	if _overlay != null:
		_overlay.update(false, null)
	if _charge_fx != null:
		_charge_fx.reset()


# --- The frame --------------------------------------------------------------

## The art whose model was missing when equipped while a late addon group was on its way: drawn again once the group is mounted.
var _late_art: AwWeaponVisual = null
var _late_failed := false


func _process(delta: float) -> void:
	if _late_art != null and not AwModelCache.late_pending():
		var again := _late_art
		_late_art = null
		var fresh := AwWeaponArtTable.upgraded(again)
		if fresh != null or _late_failed:
			equip(fresh if fresh != null else again)
	smooth_reload()
	smooth_deploy()
	advance(delta)


## One frame of the view model, [param delta] seconds long. [method _process] calls it; a
## tool that freezes processing (the range's contact sheet) calls it with a fixed step so
## that "fire frame 4" is the same picture on every machine.
func advance(delta: float) -> void:
	if Engine.is_editor_hint() or not _built:
		return

	if _belt != null:
		_belt.advance(delta)

	_strafe_now = _strafe_speed(delta)
	_advance_cycle(delta)
	_pose.advance(delta, _look_delta(), _speed, _on_floor, _crouched, _strafe_now)
	_sprint = move_toward(_sprint, 1.0 if _sprinting and sprint_pose else 0.0, delta / SPRINT_SECONDS)
	_pose.set_sprint(_ease(_sprint))
	_advance_aim(delta)
	_pose.lens_share = lens_move_share()
	_animated.transform = _pose.offset()
	_advance_wall(delta)
	# The drawn gun is pulled out of the world first; the wall-free pass is on only while it is still in it.
	var in_world := _drawn_gun_in_world(delta)
	if _overlay != null:
		_overlay.update(in_world, get_parent() as Camera3D)
	elif _reveal:
		_set_reveal(in_world)
	_place_hands()
	_apply_hands_lens()
	if _sight != null:
		SightFit.track(_sight, (transform * _animated.transform * _aim_node.transform * _holder.transform).affine_inverse() * Vector3.ZERO)
	# Through a scope the weapon is not drawn: the scope is the view. The built arms go with Animated;
	# a game's own arms (arms_ref) may live anywhere, so they are hidden by name too.
	var scoped := is_scoped()
	# The gun goes when the scope's picture is half up, in both scope views: the view model draws over the HUD,
	# so a gun kept for the lens view covers its glass. The scope body view keeps it: the lens is drawn into its ocular.
	_animated.visible = scope_body_active() or not (scoped or scope_picture_up())
	# A thrown weapon is gone from the hand from its release until the next is taken up from below.
	# The next grenade up has its pin back in.
	if _weapon != null and _art != null and _art.pose == AwWeaponArtTable.POSE_THROWN:
		if _weapon.visible == _pose.thrown_out():
			_weapon.visible = not _weapon.visible
			if _weapon.visible:
				_pin.reset()
		_pin.advance(delta)
	if _scope_glass != null:
		ScopeGlass.update(_scope_glass, get_parent() as Camera3D, scope_zoom_scale(), _animated.visible and is_visible_in_tree() and not scope_body_active(), _aim_fraction)
	if _arms != null:
		_arms.visible = not (scoped or scope_picture_up() or arms_hidden_by_scope())


## Holds or releases the aim. Call every frame with the button's state, or on its edges.
func aim(held: bool) -> void:
	_aim_held = held


## The aim button's raw state every frame; held follows it, or a press flips it under toggle rules.
func aim_input(pressed: bool) -> void:
	if _toggles():
		if pressed and not _aim_button_was:
			_aim_held = not _aim_held
	else:
		_aim_held = pressed
	_aim_button_was = pressed


## Whether the sights are being held up (the key, or the toggle's state): what a game sends as its aim button.
func is_aim_held() -> bool:
	return _aim_held


## How big a muzzle flash is drawn: 1 at the hip, the scope's own zoom through a scope, which cancels the magnification.
func flash_scale() -> float:
	return clampf(aim_fov_scale(), 0.1, 1.0) if is_scoped() else 1.0


func _advance_aim(delta: float) -> void:
	# A reload lowers the aim: the keys turn the gun about the rear sight, centimetres from the eye, and swing it out of view.
	var reloading := _reload_fraction > 0.0 and _reload_fraction < 1.0
	# A scoped weapon leaves the scope while its action cycles and looks through it again after.
	var cycling := _cycle_t >= 0.0 and has_scope()
	var target := 1.0 if (_aim_held and can_aim() and not reloading and not cycling) else 0.0
	var time := _art.aim_time if _art != null else 0.16
	if ads_rules != null and _art != null:
		time = ads_rules.aim_time_for(_art.id, time)
		_pose.aim_sway_scale = ads_rules.sway_for(_art.id)
		_pose.gun_strafe = ads_rules.strafe_for(_art.id)
	if not can_aim():
		_aim_held = false
	# Lowering out of a scope takes at least SCOPE_LOWER_TIME, so the overlay and the zoom ease out over several frames, not two.
	if target <= 0.0 and has_scope() and _aim_fraction > 0.0:
		time = maxf(time, SCOPE_LOWER_TIME)
	_aim_fraction = move_toward(_aim_fraction, target, delta / maxf(time, 0.01))
	var surround := scope_fraction()
	if surround >= SCOPE_GUN_HIDE_FRACTION:
		_gun_covered = true
	elif surround <= SCOPE_GUN_SHOW_FRACTION:
		_gun_covered = false
	if _aim_fraction <= 0.0:
		_zoom_level = 0  # every new look through the scope starts at its widest
	_pose.set_aim(_ease(_aim_fraction))
	_apply_aim(_ease(_aim_fraction))


## Moves and turns the Aim node so the holder sits [param f] of the way from the art's hip hold to its aim hold,
## and tells the pose where the grip now is so a kick turns about it.
func _apply_aim(f: float) -> void:
	if _art == null or _aim_node == null:
		return

	var hip := _art.view_transform()
	if _sight != null:
		SightFit.fade(_sight, f)
	for ring in _rear_rings:
		if is_instance_valid(ring):
			ring.visible = f >= REAR_RING_SHOW_AIM
	if f <= 0.0:
		_aim_node.transform = Transform3D.IDENTITY
		_pose.pivot = hip.origin
		return

	var ocular := Describe.scope_ocular(scope_style()) if scope_body_active() else []
	var grow := 1.0 if ocular.is_empty() else _scope_body_growth(float(ocular[1]))
	# The scope body view: the eye is where the camera is, in this rig's space (GSViewLens pulls the rig along z).
	var eye := Vector3(0.0, 0.0, -position.z)
	var sight := _aim_target() if ocular.is_empty() else _scope_body_target(ocular[0], eye, grow)
	var turn := hip.basis.get_rotation_quaternion().slerp(
		sight.basis.get_rotation_quaternion(), f
	)
	var now := Transform3D(
		Basis(turn).scaled(Vector3.ONE * _art.view_scale), hip.origin.lerp(sight.origin, f)
	)
	if not ocular.is_empty():
		# Grown about the eye the gun looks the same, only nearer: the ocular ends past the near plane, filling the lens circle.
		var m := lerpf(1.0, grow, f)
		now = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * m), eye - eye * m) * now
	_aim_node.transform = now * hip.affine_inverse()
	# Aimed, the kick turns about the rear sight (the ocular through a scope body), not the grip, or the sight picture jumps up the screen.
	if not ocular.is_empty():
		_pose.pivot = now.origin.lerp(now * (ocular[0] as Vector3), f)
	elif not _sight_line.is_empty():
		_pose.pivot = now.origin.lerp(now * _sight_line.rear, f)
	else:
		_pose.pivot = now.origin


## The holder's transform at full aim in the scope body view, before it is grown [param grow] times about [param eye]:
## the scope straight down the view with its [param ocular] (model metres) that much nearer than [member scope_body_relief].
func _scope_body_target(ocular: Vector3, eye: Vector3, grow: float) -> Transform3D:
	var basis := _art.orientation().scaled(Vector3.ONE * _art.view_scale)
	return Transform3D(basis, eye + Vector3(0.0, 0.0, -scope_body_relief / grow) - basis * ocular)


## The holder's transform at full aim: down the measured sight line, or the art's written
## aim hold when there is none.
func _aim_target() -> Transform3D:
	return _sight_aim if not _sight_line.is_empty() else _art.aim_transform()


## Fits [param art]'s sight on the mesh just built (see aw_sight_fit.gd) and keeps the aim hold that puts it through the eye.
func _fit_sight(art: AwWeaponVisual) -> void:
	_fit_sight_line(art)
	_cut_sight(art)


## The first half of [method _fit_sight]: the sight line, the aim hold and the fitted sight. [method prewarm_step] runs the halves in separate frames.
func _fit_sight_line(art: AwWeaponVisual) -> void:
	_sight_line = {}
	# Measured with the rings drawn, then hidden again by the aim.
	for ring in _rear_rings:
		if is_instance_valid(ring):
			ring.visible = true
	_rear_rings = Describe.find_rear_rings(_weapon)
	var camera := get_parent() as Camera3D
	var near := (camera.near if camera != null else 0.05) + NEAR_MARGIN
	var dot := ads_rules.sight_dot_for(art.id) if ads_rules != null else float(AwAdsRules.SPECS["sight_dot"]["default"])
	var fitted := SightFit.fit(art, _weapon, _holder, _dressed.get("line", {}), near, dot)
	if not fitted.is_empty():
		_sight_line = fitted.line
		_sight_aim = fitted.aim
		_sight = fitted.sight
		# A built iron sight's rear notch and front ring float over the line, above a gun whose top is lower than its
		# sight line (the quad's ring at the hip), so both show only from REAR_RING_SHOW_AIM.
		_rear_rings.append_array(Describe.iron_sight_pieces(_sight))


## The second half of [method _fit_sight]: the red dot cut for the line, and the sight put in the holder.
func _cut_sight(art: AwWeaponVisual) -> void:
	var red := SightFit.cut(art, ads_rules, _cut_roots(), _holder, _aim_target(), _sight_line)
	_place_sight(red)


## [method _cut_sight] a slice at a time for [method prewarm_step]: starts the cut on the first call, works [constant CUT_SLICE_USEC] on each;
## true once it is done and the sight placed. The cut is the same, only spread over frames.
func _cut_sight_slice(art: AwWeaponVisual) -> bool:
	if _cut_job == null:
		var roots := _cut_roots()
		if _cone_begun.is_empty():
			_cone_begun = SightFit.cone_begin(art, ads_rules, roots, _holder, _aim_target(), _sight_line)
		# The walk over the gun's faces that stops the hole short of a front post, a slice a call too.
		if _cone_begun.front != null and not _cone_begun.front.step(CUT_SLICE_USEC):
			return false
		_cut_cone = SightFit.cone_end(_cone_begun)
		_cone_begun = {}
		if _cut_cone.is_empty():
			_place_sight(null)
			return true
		_cut_job = SightFit.begin(roots, _holder, _cut_cone)
	if not _cut_job.step(CUT_SLICE_USEC):
		return false
	var red := SightFit.finish(art, ads_rules, _cut_cone, _cut_job)
	_cut_job = null
	_place_sight(red)
	return true


## [method HandReach.measure]'s mesh walk a slice at a time for [method prewarm_step]; true once the spans are cached.
func _reach_slice(art: AwWeaponVisual) -> bool:
	if not _reach_begun:
		_reach_begun = true
		_reach_job = HandReach.spans_job(art, _weapon, _holder)
	if _reach_job != null:
		if not _reach_job.step(CUT_SLICE_USEC):
			return false
		HandReach.spans_store(art, _holder, _reach_job)
		_reach_job = null
	return true


func _cut_roots() -> Array:
	var parts: Array = _dressed.get("parts", [])
	return [_weapon] + parts


func _place_sight(red: Node3D) -> void:
	if red != null and _sight != null:
		_sight.add_child(red)
	elif red != null:
		_sight = red
	if _sight != null:
		_holder.add_child(_sight)
		_set_on_top(_sight)


## The sight's rear and front points this frame in the camera's space (before the hands' lens), as `{rear, front}`; empty without a sight.
func sight_points() -> Dictionary:
	if _sight_line.is_empty() or _animated == null:
		return {}
	var to_view := _animated.transform * _aim_node.transform * _holder.transform
	return {"rear": to_view * (_sight_line.rear as Vector3), "front": to_view * (_sight_line.front as Vector3)}
# --- Internals --------------------------------------------------------------


## Puts a part built in code ([method _add_part]'s other half) on the weapon.
func _add_built(part: Node3D, at: Transform3D) -> Node3D:
	if part == null:
		return null
	_holder.add_child(part)
	part.transform = at
	_set_on_top(part)
	return part


## The stages the tail of [method equip] runs in, after the model is in the holder; [method prewarm_step] runs them one a call.
## The belt, the two halves of the sight fit and the hand reach's two measurements are separate stages: together they were a 50-234 ms frame per weapon at game-fatal-contact startup.
const EQUIP_STAGES := 10
## The stage that cuts the sight hole, which [method prewarm_step] works in slices.
const CUT_STAGE := 3
## What one [method prewarm_step] spends on the cut: the rest waits for the next frame.
const CUT_SLICE_USEC := 6000
## The stage that measures the hand reach, whose mesh walk [method prewarm_step] works in slices too.
const REACH_STAGE := 6
var _cut_job: RefCounted
var _cut_cone: Dictionary = {}
var _cone_begun: Dictionary = {}
var _reach_job: RefCounted
var _reach_begun := false


func _equip_stage(art: AwWeaponVisual, stage: int) -> void:
	match stage:
		0:
			_dress()
			_muzzle = _measure_muzzle(art)
		1:
			_build_belt(art)
		2:
			_fit_sight_line(art)
		3:
			_cut_sight(art)
		4:
			if art.has_magazine():
				if art.magazine_path != "":
					_magazine = _add_part(art.magazine_path, art.magazine_transform())
				else:
					_magazine = _add_built(ReloadParts.build(art.magazine_part), art.magazine_transform())
		5:
			for part in Dress.art_parts(art, _holder):
				_set_on_top(part)
				_attachments.append(part)
			# A clean tube round the baked scope, which the scope body view brings up to fill the screen.
			var housing := _add_built(ScopeHousing.build(art.scope_style), Transform3D(Basis.IDENTITY, ScopeHousing.origin(art.scope_style)))
			if housing != null:
				_attachments.append(housing)
			# Real glass in the lens, live while the scope is raised; the model's baked placeholders show the rest of the time.
			var glass := ScopeGlass.build(art.scope_style, view_layer) if art.aim_scoped else null
			if glass != null:
				_holder.add_child(glass)
				_attachments.append(glass)
				_scope_glass = glass
				ScopeGlass.hide_baked(_holder, glass)
		6:
			# The hand reach's mesh spans and the glove's texture means are cached by what they measure, so each is its own stage
			# and [method _reach_for] after them reads both back: together they were a 50-90 ms frame for a rifle.
			HandReach.measure(art, _weapon, _holder)
		7:
			if _weapon != null:
				ArmsColour.surface_albedos(_weapon)
		8:
			_reach_for(art)
		9:
			_carve_magazine(art)


static var _parts_warmed := false
var _prewarm_stage := -1
## Reload parts [method prewarm_step] still has to build and drop, one a call.
var _parts_left: Array = []
## The parts' material kinds go first, one shader compile a call: the cell built and dressed in one call was a
## 356 ms frame on staging02 (191 ms build, 165 ms dressing), every part after it about 1 ms.
const WARM_KINDS := [&"kind_plain", &"kind_plain_view", &"kind_glow", &"kind_glow_view"]
## Held until the parts are warm: the engine drops a shader with its last material, and the cell would compile it again.
var _kinds_held: Array[Material] = []


## Starts [method prewarm] over several calls: [method equip]'s head (pose, holder, model load) now, its stages one per [method prewarm_step].
## Returns false when there is nothing to step (no art, no model, or the load failed); the weapon is then already as warm as it gets.
func prewarm_begin(art: AwWeaponVisual) -> bool:
	_prewarm_stage = -1
	_cut_job = null
	_cone_begun = {}
	_reach_job = null
	_reach_begun = false
	if not _parts_left.is_empty():
		_warm_parts()
	var head := _equip_head(art)
	if head.ok and head.value_or(null) != null:
		_prewarm_stage = 0
		return true
	clear()
	_warm_parts()
	return false


## One more stage of the weapon begun by [method prewarm_begin]. True while more remain; after the last the weapon is dropped again, as [method prewarm] leaves it.
## The first weapon stepped in a process then warms the reload parts, one part a call: all of them at once were a 593 ms frame.
func prewarm_step() -> bool:
	if not _parts_left.is_empty():
		_warm_part(_parts_left.pop_front())
		return not _parts_left.is_empty()
	if _prewarm_stage < 0 or _art == null:
		_prewarm_stage = -1
		return false
	if _prewarm_stage == CUT_STAGE:
		if not _cut_sight_slice(_art):
			return true
	elif _prewarm_stage == REACH_STAGE and not _reach_slice(_art):
		return true
	else:
		_equip_stage(_art, _prewarm_stage)
	_prewarm_stage += 1
	if _prewarm_stage < EQUIP_STAGES:
		return true
	_prewarm_stage = -1
	model_ready.emit(_id, _weapon)
	_keep_prewarm()
	if not _parts_warmed:
		_parts_warmed = true
		_parts_left = WARM_KINDS + ReloadParts.part_names()
		return true
	return false


## Builds [param art]'s view of the weapon once and drops it again, so the model is loaded,
## its materials made and its hand spans measured before the weapon is first drawn in play.
## Call it on a spare view model under a loading cover, one weapon a frame.
func prewarm(art: AwWeaponVisual) -> void:
	_prewarming = true
	var _r := equip(art)
	_prewarming = false
	_keep_prewarm()
	_warm_parts()


## Every reload part not yet warmed (all of them the first time in a process), now.
func _warm_parts() -> void:
	if not _parts_warmed:
		_parts_warmed = true
		_parts_left = WARM_KINDS + ReloadParts.part_names()
	while not _parts_left.is_empty():
		_warm_part(_parts_left.pop_front())


func _warm_part(part: StringName) -> void:
	match part:
		&"kind_plain", &"kind_glow":
			_kinds_held.append(ReloadParts.material_kind(part == &"kind_glow"))
			return
		&"kind_plain_view", &"kind_glow_view":
			var sample := ReloadParts.sample(_kinds_held.back())
			_set_on_top(sample)
			sample.free()
			return
	var node := ReloadParts.build(part)
	if node != null:
		_set_on_top(node)
		node.free()
	if _parts_left.is_empty():
		_kinds_held.clear()


func describe() -> Dictionary:
	return Describe.describe(self)


func describe_lines() -> PackedStringArray:
	return Describe.describe_lines(self)

