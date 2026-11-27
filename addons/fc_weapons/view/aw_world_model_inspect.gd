@tool
extends "aw_world_model_keys.gd"

## AwWorldModel's third-person inspect: the state and the turn it samples, split out for file size.

## The inspect a watcher sees ([method on_inspect]): the fraction last told (1 is none) and how much of it shows.
var _inspect: float = 1.0
var _inspect_shown: float = 0.0
var _inspect_told: bool = false
var _inspect_was_on: bool = false
## The turn [method _inspect_turn] hands back, reused each frame: [offset, degrees]. Read it before the next call.
var _turn_out: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]


## How far through looking the gun over, 0 to 1 (1 is none): `AwViewModel.inspect_fraction`, so the hand in the world
## turns the gun the way the eye sees it turned. Not replicated, like aiming. An inspect cut short (1 told mid-way)
## eases out over [constant INSPECT_RELEASE_SECONDS].
func on_inspect(fraction: float) -> void:
	var f := clampf(fraction, 0.0, 1.0) if is_finite(fraction) else 1.0
	if f < 1.0:
		_inspect = f
		_inspect_shown = 1.0
		_inspect_told = true


## How far through the watcher's inspect, 0 to 1; 1 when none is showing.
func inspect_fraction() -> float:
	return _inspect if _inspect_shown > 0.0 else 1.0


## The inspect's turn about the grip at [param delta] into the frame: [offset, degrees], zero when none shows.
## A fraction not told again this frame (the inspect ended or was cut) lets go over [constant INSPECT_RELEASE_SECONDS].
func _inspect_turn(delta: float, told: bool) -> Array[Vector3]:
	if _inspect_shown <= 0.0:
		return _zero_turn()
	if not told:
		_inspect_shown = maxf(0.0, _inspect_shown - delta / INSPECT_RELEASE_SECONDS)
		if _inspect_shown <= 0.0:
			_inspect = 1.0
			return _zero_turn()
	var at := AwWeaponPose.sample_keys(INSPECT_KEYS, _inspect)
	var share := smoothstep(0.0, 1.0, _inspect_shown)
	_turn_out[0] = (at[0] as Vector3) * share
	_turn_out[1] = (at[1] as Vector3) * share
	return _turn_out


## [member _turn_out] at zero.
func _zero_turn() -> Array[Vector3]:
	_turn_out[0] = Vector3.ZERO
	_turn_out[1] = Vector3.ZERO
	return _turn_out
