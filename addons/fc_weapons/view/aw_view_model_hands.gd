@tool
extends "aw_view_model_state.gd"

## Hands, feed and muzzle layer of AwViewModel, split out for file size.

## By path, not by class_name: see the file's own header.
const SightFit := preload("aw_sight_fit.gd")

const HandReach := preload("aw_hand_reach.gd")

## The server's amounts for sway, strafe tilt, bob and the landing (the `mp_vm_*` cvars). One
## object per view model, shared with its pose; assign a game's own to share it between rigs.
var feel_rules := AwViewFeel.new():
	set(value):
		feel_rules = value if value != null else AwViewFeel.new()
		if _pose != null:
			_pose.rules = feel_rules

## The server's aiming rules (enabled, time, zoom, sway, hold or toggle); null aims by the art alone.
var ads_rules: AwAdsRules = null:
	set(value):
		ads_rules = value
		_equip_cache.clear()
		if _source_art != null and _art != null:
			call(&"equip", _source_art)

## Every frame, where the hands belong: [param grip] and [param fore] in [param anchor]'s space, for a game that draws its own arms (with [member show_arms] off).
## With [member hands_scale] or [member hands_min_distance] set, the anchor is the drawn weapon scaled about the eye to
## that share of life size ([AwHandsFrame]), so a game's own arms reach it; otherwise the drawn weapon itself.
signal hands_reached(anchor: Node3D, grip: Vector3, fore: Vector3, pose: StringName)

const ReloadSequence := preload("aw_reload_sequence.gd")

## The reload being played as phases (aw_reload_sequence.gd), or null for the generic one.
var _seq: ReloadSequence = null

var _hands_frame: Node3D = null

## How far the support hand is on a bolt's handle (0 to 1), so the arms can pinch it instead of fanning open; set by [method _cycle_hand].
var _cycle_grip: float = 0.0

## The size of a game's own arms against life size: [signal hands_reached]'s anchor shrinks the weapon to match, about the eye.
@export var hands_scale: float = 1.0

## The nearest the hands frame brings the grip to the eye, metres (0 = no limit): a weapon drawn close, a pistol, would
## otherwise put a life-size hand over the whole view.
@export var hands_min_distance: float = 0.0

## Every frame, the arms onto the hands: the hands follow the gun while the built arms' shoulders stay
## put in the view, so neither a wall's pull-back nor a reload swings them up into view or past the near plane.
func _place_hands() -> void:
	if _art == null or _aim_node == null:
		return
	var aim := _aim_node.transform
	var pose := _art.pose if _art.has_model() else &"fists"
	var fore := aim * _support_hand()
	var in_seq := _seq != null and _reload_fraction > 0.0 and _reload_fraction < 1.0
	var grip := aim * (_grip_at + (_seq.right_offset(_reload_fraction) if in_seq else Vector3.ZERO))
	var anchor := _animated
	if hands_scale != 1.0 or hands_min_distance > 0.0:
		var to_holder := transform * _animated.transform * aim * _holder.transform
		var scale := AwHandsFrame.life_scale(to_holder, _art) / maxf(hands_scale, 0.01)
		scale = AwHandsFrame.keep_distance(scale, (transform * _animated.transform * grip).length(), hands_min_distance)
		AwHandsFrame.place(_hands_frame, self, _animated, scale)
		anchor = _hands_frame
	hands_reached.emit(anchor, grip, fore, pose)
	if _arms == null:
		return
	var into := Transform3D.IDENTITY
	if _arms.get_parent() == _animated:
		_arms.transform = _animated.transform.affine_inverse()
		into = _arms.transform.affine_inverse()
	aim = into * aim
	grip = into * grip
	fore = into * fore
	# _arms is an AwViewArms (its reach takes the axes; an override keeps the signature): typed calls, no name lookups.
	_arms.run = _pose.run_amount()
	_arms.run_phase = _pose.run_phase()
	if _arms_cycle_for != _arms:
		_arms_cycle_for = _arms
		_arms_has_cycle = &"cycle_grip" in _arms
	if _arms_has_cycle:
		_arms.set(&"cycle_grip", _cycle_grip if _cycle_t >= 0.0 else 0.0)  # perf-lint: allow dynamic_call a game's own arms may add it
	_arms.throw_grip = _pose.windup_fraction()
	_arms.support_free = in_seq or (_has_well and not _feeds and _reload_fraction > 0.0 and _reload_fraction < 1.0)
	_arms.reach(grip, fore, pose, aim.basis * _grip_axis, aim.basis * _fore_axis, _grip_radius)


## The arms [member _arms_has_cycle] was read from, and whether they have a `cycle_grip` (AwViewArms itself has none).
var _arms_cycle_for: AwViewArms = null
var _arms_has_cycle := false

## Where the support hand is this frame: on the fore-end, or, through a reload of a weapon with
## a magazine, to the well, down with the old magazine and out of sight, back up with the next
## one, and back to the fore-end. Keys in the same shape as the gun's, so the two agree.
func _support_hand() -> Vector3:
	var f := _reload_fraction
	if _seq != null and f > 0.0 and f < 1.0:
		return _seq.left_hand(f)
	if _cycle_t >= 0.0 and _art != null:
		return _cycle_hand()
	if not _has_well or f <= 0.0 or f >= 1.0:
		return _fore_at.lerp(_fore_aimed_at, clampf(_aim_fraction, 0.0, 1.0)) if is_finite(_aim_fraction) else _fore_at
	if _feeds:
		return AwWeaponPose.sample_keys(_feed_keys, f)[0]
	var below := _well + Vector3(0.0, -0.24, 0.08)
	var keys := [
		[0.0, _fore_at, Vector3.ZERO],
		[0.08, _fore_at, Vector3.ZERO],
		[0.16, _well + Vector3(0.0, -0.03, 0.0), Vector3.ZERO],
		[0.30, below, Vector3.ZERO],
		[0.40, below + Vector3(0.0, -0.04, 0.0), Vector3.ZERO],
		[0.50, _well + Vector3(0.0, -0.08, 0.0), Vector3.ZERO],
		[0.58, _well + Vector3(0.0, -0.035, 0.0), Vector3.ZERO],
		[0.64, _well + Vector3(0.0, -0.03, 0.0), Vector3.ZERO],
		[0.78, _fore_at, Vector3.ZERO],
		[1.0, _fore_at, Vector3.ZERO],
	]
	return AwWeaponPose.sample_keys(keys, f)[0]

## The support hand through a bolt's or pump's cycle: from the fore-end to the handle, riding it back and home, and away again. A pump's
## handle is the fore-end itself ([member AwWeaponVisual.cycle_at] empty), so the hand stays and travels with it.
func _cycle_hand() -> Vector3:
	var rest := _fore_at.lerp(_fore_aimed_at, clampf(_aim_fraction, 0.0, 1.0)) if is_finite(_aim_fraction) else _fore_at
	var handle := rest
	if _art.cycle_at.length_squared() > 0.000001:
		handle = _holder.transform * _art.cycle_at
	var f := (_cycle_t - _cycle_wait) / _cycle_len
	var w := cycle_reach(f, _cycle_wait / _cycle_len)
	_cycle_grip = w if _art.cycle_at.length_squared() > 0.000001 else 0.0
	return rest.lerp(handle + _cycle_shift, w)

## The support hand's keys for a gun fed by hand ([member AwWeaponVisual.load_from]): bolt back, each round fetched, carried and pushed home, bolt closed. Built once per weapon.
## The round is drawn at the hand ([constant FEED_CARRY] above it) for the whole trip, because [method _animate_magazine] reads the hand and the two must not part.
func _build_feed_keys(art: AwWeaponVisual) -> Array:
	var carry := FEED_CARRY
	var keys: Array = [[0.0, _fore_at, Vector3.ZERO], [0.06, _fore_at, Vector3.ZERO]]
	var start := FEED_START
	if _bolted:
		keys.append([0.12, _bolt, Vector3.ZERO])
		keys.append([0.20, _bolt_back, Vector3.ZERO])
	# Fetched from below the gun, out of frame the first time and from a pouch nearer for the
	# next, so a round at a time does not send the hand off screen between each.
	var far := _well + Vector3(0.0, -0.26, 0.06)
	var near := _entry - carry + Vector3(0.0, -0.13, 0.05)
	var count := maxi(1, art.load_count)
	var span := (FEED_END - start) / float(count)
	for i in count:
		var a := start + span * float(i)
		keys.append([a, far if i == 0 else near, Vector3.ZERO])
		keys.append([a + span * FEED_AT_ENTRY, _entry - carry, Vector3.ZERO])
		keys.append([a + span * FEED_AT_SEAT, _well - carry, Vector3.ZERO])
	if _bolted:
		keys.append([0.75, _bolt_back, Vector3.ZERO])
		keys.append([0.82, _bolt, Vector3.ZERO])
		keys.append([0.92, _fore_at, Vector3.ZERO])
	else:
		keys.append([0.84, _fore_at, Vector3.ZERO])
	keys.append([1.0, _fore_at, Vector3.ZERO])
	return keys

## A fed round in the hand: where it is this frame in the holder's (model) space, and whether
## it is drawn; empty when it is in the gun or not yet fetched.
func _fed_round(fraction: float) -> Dictionary:
	var count := maxi(1, _art.load_count)
	var span := (FEED_END - FEED_START) / float(count)
	var into := fraction - FEED_START
	if into < 0.0 or fraction >= FEED_END:
		return {}
	var local := fmod(into, span) / span
	if local >= FEED_AT_SEAT:
		return {}
	var hand := _support_hand() + FEED_CARRY
	var at := _holder.transform.affine_inverse() * hand
	return {"at": at} if at.is_finite() else {}

## Where the muzzle is right now in world space, for a flash, a tracer and a shell; the simulation never reads it.
func muzzle_transform() -> Transform3D:
	if _weapon == null:
		return global_transform

	return _weapon.global_transform * Transform3D(Basis.IDENTITY, _muzzle)

## 0 at the hip to 1 at full aim.
func aim_fraction() -> float:
	return _aim_fraction




## Sideways speed this frame, m/s, to the right of the view. Measured as the camera's world
## movement across its own right axis when the game did not say; a teleport (a jump of more
## than 30 m/s) is no strafe, and the first frame has nothing to compare with.
func _strafe_speed(delta: float) -> float:
	if not is_nan(_strafe_given):
		return _strafe_given
	if not is_inside_tree():
		return 0.0
	var origin := global_position
	var moved := origin - _last_origin
	var seen := _origin_seen
	_last_origin = origin
	_origin_seen = true
	if not seen or delta <= 0.0:
		return 0.0
	var side := moved.dot(global_transform.basis.x.normalized()) / delta
	return side if absf(side) < 30.0 else 0.0


func _look_delta() -> Vector2:
	if not _look_seen:
		_look_seen = true
		_last_look = _look
		return Vector2.ZERO

	# Yaw wraps, and the wrap is the bug: turning from 179 to -179 degrees is two
	# degrees of movement and reads as 358 without this, which throws the weapon clear
	# off the screen once per full turn.
	var delta := Vector2(
		wrapf(_look.x - _last_look.x, -180.0, 180.0), _look.y - _last_look.y
	)
	_last_look = _look
	return delta
