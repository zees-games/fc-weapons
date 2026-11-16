class_name AwWeaponPoseTunables
extends RefCounted

## The key tables, by path: naming [AwWeaponPose] here would make the two scripts a cycle the parser cannot resolve.
const _Keys := preload("aw_weapon_pose_keys.gd")

## How the springs behave. One resource for the whole rig; a weapon scales it by its own
## [member AwWeaponVisual.weight] rather than carrying its own copy.
## Split out of [AwWeaponPose] for file size; the pose reaches it as [code]AwWeaponPose.Tunables[/code].

## Metres the weapon lags behind a turn, at [member sway_reference] degrees a second.
var sway_amount: float = 0.035

## Degrees per second of look movement producing the full sway.
var sway_reference: float = 220.0

## How quickly sway catches up, per second. Higher is stiffer.
var sway_response: float = 9.0

## Degrees the weapon rolls into a turn.
var sway_roll: float = 4.0

## Sideways ground speed producing the full strafe tilt, metres a second.
var strafe_reference: float = 6.0

## How quickly the tilt follows a change of strafe, per second.
var strafe_response: float = 8.0

## Degrees the weapon leans against a full strafe.
var strafe_roll: float = 6.0

## Degrees the muzzle swings against a full strafe (a yaw about the grip).
var strafe_yaw: float = 3.0

## Metres the weapon trails behind a full strafe.
var strafe_slide: float = 0.035

## Metres of vertical travel at [member bob_reference] metres a second.
var bob_amount: float = 0.022

## Horizontal travel, as a fraction of [member bob_amount]. Slightly more than the
## vertical, because a figure-of-eight reads as walking and a straight bounce reads
## as a lift.
var bob_lateral: float = 1.4

## Ground speed producing the full bob.
var bob_reference: float = 6.0

## Bob cycles per metre travelled. [b]Per metre, not per second:[/b] a bob driven by time keeps bobbing when the
## player walks into a wall, and slides rather than steps when they slow down.
var bob_per_metre: float = 0.55

## The most bob cycles a second, however fast the carrier moves: a cadence, not a speed. Per metre alone, a 9 m/s runner bobbed 10 footfalls a second, a weapon
## vibrating rather than carried (game-fatal-contact's `headless_feel`). A runner's legs reach about three steps a second and then stride longer, so past this rate
## the distance a cycle covers grows instead. 1.5 cycles is three footfalls a second.
var bob_max_rate: float = 1.5

## How quickly the bob amplitude follows speed, per second.
var bob_response: float = 7.0

## Degrees of muzzle climb a small recoil produces per degree a behaviour asked for.
##
## [b]Not the whole story, because the curve bends.[/b] See [member kick_knee].
var kick_pitch: float = 4.0

## How hard large recoil is compressed: climb is [code]kick_pitch * r / (1 + r * kick_knee)[/code]. The behaviours' recoil runs from 0.12 (minigun) to 4.0 (sniper),
## right for a camera; fed linearly into a view model and times the weapon's weight, one minigun shot moved the gun 0.6 degrees and one sniper shot 17 degrees.
## Compressed, the same pack runs from about one degree to about six, the range a hand can hold.
var kick_knee: float = 0.45

## Degrees of sideways kick per degree of recoil yaw, compressed by the same curve.
var kick_yaw: float = 3.0

## Degrees the weapon rolls per degree of sideways kick, the same way it went.
var kick_roll: float = 1.5

## Metres the weapon is pushed back per degree of climb.
var kick_back: float = 0.008

## The most a single shot may push the weapon back, in metres.
var kick_back_max: float = 0.045

## The least a shot may lift the drawn weapon, in degrees, however small its recoil: the
## automatics' recoil is tuned for the camera and was under a degree on screen. Drawn
## only (a separate spring), so the camera punch and the shot are untouched. 0 off.
var kick_min: float = 2.0

## Metres the weapon slides back per degree of that minimum lift.
var kick_min_back: float = 0.012

## Stiffness of the recoil spring, per second, for a weapon of weight 1. A heavier
## weapon returns more slowly, by the square root of its weight.
var kick_response: float = 22.0

## A weapon firing faster than this many seconds a shot gets a stiffer kick spring, so the kick settles between shots.
var kick_rate_ref: float = 0.12

## The most that stiffening multiplies [member kick_response] by.
var kick_rate_max: float = 1.8

## The fraction of the weapon's climb the camera takes, for [method view_punch] (the kick spring is critically damped, not tunable: underdamped, a sniper's barrel
## dipped under its rest after each shot). Small, because the simulation fires along the command's angles and nothing here changes them: a punch that recovers
## inside a fifth of a second reads as the weapon going off; a large one reads as the crosshair lying about where the next shot lands.
var camera_share: float = 0.3

## The draw, as keys from fully holstered (0) to in hand (1). See [method sample_keys].
## Replaced per weapon by the view model from [member AwWeaponVisual.draw_keys].
var draw_keys: Array = _Keys.DRAW_KEYS

## The holster, on the draw's scale and played from 1 down to 0 (see [method AwWeaponPose.set_deploy]).
## Its own keys: the draw backwards begins with the draw's settle and barely moves for a third of the holster.
var holster_keys: Array = _Keys.HOLSTER_KEYS

## Looking the weapon over, as keys over [member inspect_seconds]. Empty is none.
var inspect_keys: Array = _Keys.INSPECT_KEYS

## How long an inspect takes, in seconds.
var inspect_seconds: float = 2.6

## Seconds a cancelled inspect takes to ease back into the hand, so a shot or an aim never snaps it.
var inspect_cancel_seconds: float = 0.2

## The reload, as keys over its fraction, 0 to 1. Empty is no reload motion.
var reload_keys: Array = _Keys.RELOAD_KEYS_RIFLE

## The sprint carry at full blend: metres and degrees (pitch up, yaw muzzle-left, roll), about the grip.
var sprint_offset := Vector3.ZERO
var sprint_rotation := Vector3.ZERO

## While sprinting: the bob's amplitude multiplier and a roll in degrees that rocks with each stride, both at full blend.
var sprint_bob: float = 1.0
var sprint_bob_roll: float = 0.0

## A melee swing, as keys over its own time (see [member swing_seconds]). Empty is none.
var swing_keys: Array = _Keys.SWING_KEYS

## How long a swing's keys take, in seconds. Presentation time, not the weapon's cooldown:
## a swing that lasted the whole cooldown of a slow hammer would still be crossing the
## screen when the next one was pressed.
var swing_seconds: float = 0.36

## A throw, as keys over [member throw_seconds].
var throw_keys: Array = _Keys.THROW_KEYS

var throw_seconds: float = 0.45

## A throw's windup ([method AwWeaponPose.set_windup]): keys over the meter, the share of them shown at an empty
## meter, and seconds easing in, holding once the meter stops (the release usually lands then) and easing out.
var windup_keys: Array = _Keys.WINDUP_KEYS
var windup_start: float = 0.25
var windup_in_seconds: float = 0.1
var windup_hold_seconds: float = 0.15
var windup_out_seconds: float = 0.2
## A throw from a windup: keys after the cocked pose, over [member throw_release_seconds].
var throw_release_keys: Array = _Keys.THROW_RELEASE_KEYS
var throw_release_seconds: float = 0.4

## While sprinting, metres the hand pumps forward and back (z) and up and down (y) with each stride, at full blend.
## Zero for a gun, which is carried; a one-handed blade swings with the running arm.
var sprint_pump := Vector3.ZERO

## Metres it is pulled back at full charge.
var charge_pull: float = 0.06

## Metres of dip on a landing, at the controller's own reference speed.
var landing_dip: float = 0.07

## How quickly a landing dip recovers, per second.
var landing_response: float = 8.0

## The profile keys (`extra: params:`) that set each kick number, by name here: a server tunes a weapon's feel in cfg.
const KICK_PARAMS := {
	&"view_kick_pitch": &"kick_pitch", &"view_kick_knee": &"kick_knee", &"view_kick_yaw": &"kick_yaw",
	&"view_kick_roll": &"kick_roll", &"view_kick_back": &"kick_back", &"view_kick_back_max": &"kick_back_max",
	&"view_kick_response": &"kick_response", &"view_kick_rate_ref": &"kick_rate_ref",
	&"view_kick_rate_max": &"kick_rate_max", &"view_camera_share": &"camera_share",
	&"view_kick_min": &"kick_min", &"view_kick_min_back": &"kick_min_back",
}


## The builders' kick numbers as profile params: the defaults above, so a profile that sets none changes nothing.
static func kick_defaults() -> Dictionary:
	var base := AwWeaponPoseTunables.new()
	var out := {}
	for key: StringName in KICK_PARAMS:
		out[key] = float(base.get(KICK_PARAMS[key]))
	return out


## Sets the kick numbers from a weapon's params; a key that is absent or not a number keeps the default.
func apply_kick(params: Dictionary) -> void:
	var base := AwWeaponPoseTunables.new()
	for key: StringName in KICK_PARAMS:
		var field: StringName = KICK_PARAMS[key]
		var v: Variant = params.get(key, params.get(String(key)))
		set(field, float(v) if (v is float or v is int) and is_finite(float(v)) else base.get(field))
