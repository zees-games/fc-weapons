@tool
extends "aw_world_model_keys.gd"

## AwWorldModel's third-person inspect: the state and the turn it samples, split out for file size.

## The inspect a watcher sees ([method on_inspect]): the fraction last told (1 is none) and how much of it shows.
var _inspect: float = 1.0
var _inspect_shown: float = 0.0
var _inspect_told: bool = false
var _inspect_was_on: bool = false


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
func _inspect_turn(delta: float, told: bool) -> Array:
	if _inspect_shown <= 0.0:
		return [Vector3.ZERO, Vector3.ZERO]
	if not told:
		_inspect_shown = maxf(0.0, _inspect_shown - delta / INSPECT_RELEASE_SECONDS)
		if _inspect_shown <= 0.0:
			_inspect = 1.0
			return [Vector3.ZERO, Vector3.ZERO]
	var at := AwWeaponPose.sample_keys(INSPECT_KEYS, _inspect)
	var share := smoothstep(0.0, 1.0, _inspect_shown)
	return [(at[0] as Vector3) * share, (at[1] as Vector3) * share]
