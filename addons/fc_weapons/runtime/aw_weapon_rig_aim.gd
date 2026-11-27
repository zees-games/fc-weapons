@tool
extends "aw_weapon_rig_setup.gd"

## AwWeaponRig's aim: the barrel turned by a sprint carry or a wall, the aim-in ramp and what the sights do to a shot.

## Layers a wall-pushed barrel stops on when the rig draws no shots itself (a server): the shot effects' default, every layer.
@export_flags_3d_physics var wall_shot_mask: int = 0xFFFFFFFF


func current_def() -> GSWeaponDef:
	return arsenal.current_def() if arsenal != null else null


func current_art() -> AwWeaponVisual:
	var def := current_def()
	return AwWeaponArtTable.table().get(def.id, null) if def != null else null


## A basis looking along [param direction] with an up that is never colinear with it; identity for a zero or non-finite direction. Basis.looking_at errors on either.
static func _look_basis(direction: Vector3) -> Basis:
	if not direction.is_finite() or direction.length_squared() < 0.000001:
		return Basis.IDENTITY
	var dir := direction.normalized()
	return Basis.looking_at(dir, Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.999 else Vector3.FORWARD)


## Turns [member GSWeaponContext.direction] to where the sprint carry points the barrel (full blend, from the art, so a server and a replay agree without reading the rendered pose). The origin stays the eye.
func _aim_along_sprint_barrel(context: GSWeaponContext) -> void:
	if not (context.sprinting and context.sprint_shot_follows_barrel):
		return
	var art := current_art()
	if art == null or absf(context.direction.dot(Vector3.UP)) > 0.999:
		return
	var rot: Vector3 = art.sprint_rotation if art.sprint_rotation.is_finite() \
		else AwWeaponArtTable.sprint_view(art.pose)[1]
	var hand := Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z)))
	var aim := _look_basis(context.direction)
	context.direction = (aim * (hand * Vector3.FORWARD)).normalized()


## Whether this tick hands [member GSWeaponContext.direction] to nobody: no sights (a held-back shot is a release), no bash, and an arsenal only counting its cadence down.
func _aim_unread(command: GSWeaponCommand, context: GSWeaponContext) -> bool:
	if (command.buttons & (GSWeaponCommand.BUTTON_AIM | GSWeaponCommand.BUTTON_ALT)) != 0:
		return false
	# Asked by name: an older gs-weapon has no such answer, and then every tick casts as before. Whether it has one is
	# looked up once per arsenal; the lookup each tick cost as much as the answer.
	if arsenal != _cooling_of:
		_cooling_of = arsenal
		_cooling_known = arsenal != null and arsenal.has_method(&"is_cooling_for")
	return _cooling_known and arsenal.call(&"is_cooling_for", command, context)


var _cooling_of: Object = null
var _cooling_known := false


## Sideways speed last given to [method drive_view]; the wall shot tilts with it, as the drawn gun does. A server sets it from `context.extra[&"strafe"]` instead.
var _drive_strafe: float = 0.0


## Turns [member GSWeaponContext.direction] to where a wall has pushed the barrel, recomputed each tick from the carrier's eye, aim and speed so a server, a prediction and a replay agree without the rendered pose. The origin stays the eye: a muzzle inside the wall would shoot through it.
func _aim_along_wall_barrel(context: GSWeaponContext) -> void:
	var def := current_def()
	var art := current_art()
	if def == null or art == null or ads_rules == null or not ads_rules.wall_shot_for(def.id) or not (_player is Node3D):
		return
	var turn := wall_barrel(context.origin, context.direction, art, context.speed, ads_progress(), float(context.extra.get(&"strafe", _drive_strafe)))  # perf-lint: allow dynamic_call Dictionary.get (context.extra)
	if turn != Basis.IDENTITY:
		var aim := _look_basis(context.direction)
		context.direction = (aim * (turn * Vector3.FORWARD)).normalized()


## The rotation (view space) a wall puts on the held gun's barrel for an eye at [param origin] looking along [param direction].
func wall_barrel(origin: Vector3, direction: Vector3, art: AwWeaponVisual, speed: float, aim: float, strafe: float = 0.0) -> Basis:
	var node := _player as Node3D
	if node == null or not node.is_inside_tree():
		return Basis.IDENTITY
	var world := node.get_world_3d()
	if world == null:
		return Basis.IDENTITY
	var eye := Transform3D(_look_basis(direction), origin)
	# Reused: barrel_turn copies it into its query and keeps no reference.
	var exclude := _wall_barrel_exclude
	exclude.clear()
	if node is CollisionObject3D:
		exclude.append((node as CollisionObject3D).get_rid())
	var mask := (_fx.collision_mask if _fx != null else wall_shot_mask) | wall_extra_mask
	return AwWallSlam.barrel_turn(world.direct_space_state, eye, art.hip_muzzle(arsenal.fitting_at(arsenal.current_slot()) if arsenal != null else null), ads_rules.view_scale_for(art.id),
		ads_rules.wall_for(art.id), 1.0, 1.0, speed, aim, mask, true, exclude, strafe)


var _wall_barrel_exclude: Array[RID] = []


## The class's aim factors and hip spread (gs-weapon switches both the instant the aim bit is set) follow the sights' ramp.
static func _ease_class_aim(b: GSWeaponBallistics, def: GSWeaponDef, ramp: float) -> void:
	var klass := GSWeaponAccuracyClass.resolve(b.accuracy_class, def.tags, def.id)
	var factor := lerpf(1.0, b.accuracy("spread_aim", klass), ramp)
	b.spread_aim = factor
	# The factor scales the whole cone, so divide it out of the hip term to leave hip * (1 - ramp).
	b.spread += b.accuracy("spread_hip", klass) * (1.0 - ramp) / maxf(factor, 0.001)
	b.recoil_aim = lerpf(1.0, b.accuracy("recoil_aim", klass), ramp)


## The aim facts [method _tag_aimed_shots] put on a shot, for a stat rule: `ads_progress` (-1 when untagged) and `quickscope`.
static func aim_facts(shot: GSShot) -> Dictionary:
	if shot == null:
		return {"ads_progress": -1.0, "quickscope": false}
	return {"ads_progress": float(shot.get_meta(&"ads_progress", -1.0)), "quickscope": bool(shot.get_meta(&"quickscope", false))}


## Marks each shot fired while the sights were still coming up: `ads_progress` (0 to 1) always, `quickscope` true for a scope fired before it landed. Metadata, because a shot is gs-combat's.
func _tag_aimed_shots(outcome: GSWeaponOutcome, scoped: bool) -> void:
	for shot in outcome.shots:
		shot.set_meta(&"ads_progress", _ads_progress)
		shot.set_meta(&"quickscope", scoped and _ads_progress < 1.0)


## Whether the aim bit counts: the server does not take it on trust. Needs rules, a weapon that
## aims (rules and art), and a rifle that is neither being switched to nor reloaded, and a carrier not sprinting under `sv_sprint_noaim`.
func _can_aim(command: GSWeaponCommand, def: GSWeaponDef, context: GSWeaponContext = null) -> bool:
	if ads_rules == null or ads_button == 0 or def == null or (command.buttons & ads_button) == 0:
		return false
	if context != null and context.sprinting and context.sprint_blocks_aim:
		return false
	if not ads_rules.enabled_for(def.id) or arsenal.is_switching() or arsenal.is_reloading():
		return false
	var art: AwWeaponVisual = AwWeaponArtTable.table().get(def.id, null)
	return art == null or art.aim_enabled


## The walk-speed multiplier of the last simulated command: [member AwAdsRules] move speed while it
## held the aim button, else 1. A game multiplies its motor's speed by it on the server and in prediction.
func ads_move_scale() -> float:
	return _ads_move


## How far into the aim-in the last simulated command was (0 at the hip, 1 fully aimed), by ticks.
func ads_progress() -> float:
	return _ads_progress


## The arsenal's tick with the spread scaled while the command holds the aim button. The scale
## is put back after, so the def is never left changed; it follows the command, so a replay agrees.
func _simulate_aimed(command: GSWeaponCommand, context: GSWeaponContext) -> GSWeaponOutcome:
	_ads_move = 1.0
	_ads_progress = 0.0
	var def := arsenal.current_def()
	if def != null and ads_rules != null:
		ads_rules.set_def_row(def.id, def.params.get("ads"))
	if not _can_aim(command, def, context):
		_aim_ticks = 0
		return arsenal.simulate_tick(command, context, _previous_command)
	var art: AwWeaponVisual = AwWeaponArtTable.table().get(def.id, null)
	var b := def.tuning as GSWeaponBallistics
	if b == null:
		return arsenal.simulate_tick(command, context, _previous_command)
	_aim_ticks += 1
	_ads_move = ads_rules.move_speed_for(def.id)
	# The spread closes as the sights come up, over the weapon's aim time, counted in ticks so a replay agrees.
	var seconds := ads_rules.aim_time_for(def.id, art.aim_time if art != null else 0.16)
	var ramp := clampf(float(_aim_ticks) / maxf(seconds * float(tick_rate), 1.0), 0.0, 1.0)
	_ads_progress = ramp
	var k := lerpf(1.0, ads_rules.spread_for(def.id), ramp)
	# A shot before the fire threshold is held back; at 1 nothing fires until the sights are up, at 0 a quick scope is allowed.
	var fire_min := ads_rules.quickscope_fire_min_for(def.id)
	if ramp < fire_min and (command.buttons & GSWeaponCommand.BUTTON_ATTACK) != 0:
		command = command.duplicate_command()
		command.buttons &= ~GSWeaponCommand.BUTTON_ATTACK
	# Kept in float locals, not an array: nothing allocated on an aimed tick, and the f64 copies put back to the bit.
	var kept_spread := b.spread
	var kept_moving := b.spread_moving
	var kept_airborne := b.spread_airborne
	var kept_bloom := b.bloom
	var kept_pitch := b.recoil_pitch
	var kept_yaw := b.recoil_yaw
	var kept_aim := b.spread_aim
	var kept_recoil_aim := b.recoil_aim
	var rk := lerpf(1.0, ads_rules.recoil_for(def.id), ramp)
	b.recoil_pitch *= rk
	b.recoil_yaw *= rk
	b.spread *= k
	b.spread_moving *= k
	b.spread_airborne *= k
	b.bloom *= k
	_ease_class_aim(b, def, ramp)
	var outcome := arsenal.simulate_tick(command, context, _previous_command)
	b.spread = kept_spread
	b.spread_moving = kept_moving
	b.spread_airborne = kept_airborne
	b.bloom = kept_bloom
	b.recoil_pitch = kept_pitch
	b.recoil_yaw = kept_yaw
	b.spread_aim = kept_aim
	b.recoil_aim = kept_recoil_aim
	if outcome.used and outcome.kind == GSWeaponOutcome.KIND_SHOT:
		_tag_aimed_shots(outcome, art != null and art.aim_scoped)
	return outcome
