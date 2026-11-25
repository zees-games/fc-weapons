extends RefCounted

## The idle breath of a held weapon, as pure arithmetic: [AwWeaponPose] keeps the clock and the switch
## ([member AwWeaponPose.breathing]); this turns them into motion. No Node, no state.

## The slow cycle, in hertz.
const HZ := 0.23
## How far a full breath turns the weapon at the hip (degrees) and moves it (metres).
const HIP_DEGREES := 0.7
const HIP_REACH := 0.004
## How far a full breath turns the scoped view, in degrees.
const VIEW_DEGREES := 0.35


## The breath at [param seconds], each axis in [-1, 1] (x right, y up): two incommensurate sines per axis so it never
## repeats visibly. Zero when not finite.
static func wave(seconds: float) -> Vector2:
	var t := seconds * TAU * HZ
	var v := Vector2(sin(t * 0.83 + 1.3) * 0.7 + sin(t * 1.9) * 0.3, sin(t) * 0.75 + sin(t * 2.3 + 0.6) * 0.25)
	return v if v.is_finite() else Vector2.ZERO


## The hip drift [param drift] (a scaled [method wave]) as [position (metres), rotation (degrees, pitch/yaw/roll)],
## in the same form as a pose's sampled keys so the caller adds it beside them.
static func hip(drift: Vector2) -> Array:
	return [Vector3(drift.x, drift.y, 0.0) * HIP_REACH, Vector3(drift.y, drift.x, 0.0) * HIP_DEGREES]
