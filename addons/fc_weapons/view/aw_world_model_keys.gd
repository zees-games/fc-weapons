@tool
extends Node3D

## Authored motion keys of AwWorldModel, split out for file size.

# --- Authored motion ----------------------------------------------------------
#
# [b]A swing and a throw are keys here too, for the view model's reason[/b] ([AwWeaponPose]'s
# SWING_KEYS): a melee weapon has no recoil, so a watcher saw somebody's knife ride the arm's
# slash rigid in the hand, pointing where the held-gun pose points, and a grenade thrown from a
# hand that never moved. Each key is [t, position in metres, rotation in degrees (pitch up,
# yaw left, roll counter-clockwise)] in the hand's frame (-Z the way the person faces, +Y up),
# turned about the grip, on top of [method AwWeaponVisual.world_transform], read through
# [method AwWeaponPose.sample_keys]. [b]Not the view model's keys[/b]: those are in the camera's
# frame at the view model's scale, and the arm under this one already moves (the person's
# slash overlay), so these are the wrist's share only: cocked back as the arm comes up, cut
# through as it comes down, followed through and back.

## A melee swing, timed to the person's slash overlay (the arm is up at about 0.12 s and through
## by 0.3 s at the rate the family plays it).
const SWING_KEYS := [
	[0.0, Vector3.ZERO, Vector3.ZERO],
	[0.22, Vector3(0.0, 0.03, 0.04), Vector3(65.0, -15.0, -10.0)],
	[0.42, Vector3(0.0, 0.0, -0.05), Vector3(-35.0, 30.0, 20.0)],
	[0.58, Vector3(0.0, -0.02, -0.03), Vector3(-55.0, 38.0, 25.0)],
	[0.82, Vector3(0.0, 0.0, 0.0), Vector3(-15.0, 10.0, 6.0)],
	[1.0, Vector3.ZERO, Vector3.ZERO],
]

const SWING_SECONDS := 0.5

## A throw: the wrist cocked back as the arm swings forward, flicked through, and the weapon gone
## from [constant THROW_RELEASE] (the projectile is the game's, and a grenade still in the hand
## beside it is two grenades) until it is back in the hand at [constant THROW_BACK]. The arm is
## the person's: a thrown weapon is held with empty-handed arms, which have no throw of their
## own, so [method throw] asks the person it hangs from for the slash overlay (see
## [method _person]): up past the head and over, an overhand throw's path. Without an arm under
## it a grenade moved by keys alone floated away from a hand that stayed where it was, and the
## punch overlay punches with the other hand.
const THROW_KEYS := [
	[0.0, Vector3.ZERO, Vector3.ZERO],
	[0.20, Vector3(0.0, 0.03, 0.05), Vector3(55.0, 0.0, -8.0)],
	[0.36, Vector3(0.0, 0.02, -0.04), Vector3(-30.0, 0.0, 4.0)],
	[0.60, Vector3(0.0, 0.0, -0.03), Vector3(-40.0, 0.0, 0.0)],
	[0.85, Vector3(0.0, 0.0, 0.0), Vector3(-8.0, 0.0, 0.0)],
	[1.0, Vector3.ZERO, Vector3.ZERO],
]

const THROW_SECONDS := 0.55

## The fractions of a throw between which the thrown weapon is not in the hand.
const THROW_RELEASE := 0.36
const THROW_BACK := 0.9

## A grenade's throw (a thrown-pose weapon, [constant AwWeaponArtTable.POSE_THROWN]): the grenade
## leaves on the button's release, the projectile with it, so the arm is the person's knife-throw
## release ([method throw] asks for `throw_release()`, a whip forward from the shoulder) and the
## grenade is gone from [constant LOB_RELEASE], a few frames in, while the hand is still ahead of the
## head. It comes back at [constant LOB_BACK] once the arm has dropped, grown in from
## [constant LOB_BACK_SCALE] and risen from below the hand over the last keys: the next grenade out of
## the pouch, not the same one snapping back into a hand at the hip (a judged pop).
const LOB_KEYS := [
	[0.0, Vector3.ZERO, Vector3.ZERO],
	[0.12, Vector3(0.0, 0.01, -0.03), Vector3(-25.0, 0.0, 0.0)],
	[0.40, Vector3(0.0, 0.0, -0.02), Vector3(-12.0, 0.0, 0.0)],
	[0.72, Vector3(0.0, -0.07, 0.03), Vector3(10.0, 0.0, 0.0)],
	[1.0, Vector3.ZERO, Vector3.ZERO],
]

const LOB_SECONDS := 0.95
const LOB_RELEASE := 0.1
const LOB_BACK := 0.72
const LOB_BACK_SCALE := 0.35

## The fractions of the playing throw between which the weapon is out of the hand, and the size it grows back from.
var _action_release: float = THROW_RELEASE
var _action_back: float = THROW_BACK
var _action_back_scale: float = 1.0


## Asks [param person] (none is fine) for its throw's arm: the knife-throw release where it has one, else the slash.
static func _ask_release(person: Node) -> void:
	if person == null:
		return
	if person.has_method(&"throw_release"):
		person.call(&"throw_release")
	else:
		person.call(&"swing", &"slash")


## The size the next thrown weapon up is drawn at, [param at] through a throw that [param hides] it: grown in
## from [member _action_back_scale] after [member _action_back], else full size.
func _regrown(hides: bool, at: float) -> float:
	if not hides or _action_back_scale >= 1.0 or at < _action_back or at >= 1.0:
		return 1.0
	return lerpf(_action_back_scale, 1.0, smoothstep(_action_back, 1.0, at))

## Looking the gun over, as a watcher sees it, timed to the first-person inspect's fraction (AwWeaponPose's INSPECT_KEYS):
## lifted toward the face and rolled further than those, since at twenty metres a 30 degree wrist reads as the gun at rest.
## Turned about the grip, so the hand stays on it and the support hand follows the fore-end round.
const INSPECT_KEYS := [
	[0.0, Vector3.ZERO, Vector3.ZERO],
	[0.16, Vector3(0.0, 0.07, 0.05), Vector3(14.0, 22.0, -55.0)],
	[0.42, Vector3(0.0, 0.09, 0.06), Vector3(20.0, 28.0, -70.0)],
	[0.56, Vector3(0.0, 0.06, 0.04), Vector3(8.0, 6.0, -10.0)],
	[0.72, Vector3(0.0, 0.07, 0.05), Vector3(10.0, -20.0, 55.0)],
	[0.86, Vector3(0.0, 0.06, 0.04), Vector3(8.0, -18.0, 48.0)],
	[1.0, Vector3.ZERO, Vector3.ZERO],
]

## Seconds the watcher's inspect takes to let go when it is cut short (a shot, a switch): the first-person
## inspect's cancel ease.
const INSPECT_RELEASE_SECONDS := 0.2

## A watcher's reload, in the hand's frame like the swing: the gun dipped and rolled so its well faces the support
## hand, which goes from the fore-end to the well, down to the belt and back once per cycle (one reload, or one round).
const RELOAD_DIP := Vector3(0.0, -0.05, 0.03)
const RELOAD_TURN := Vector3(-18.0, 12.0, 38.0)
const RELOAD_SUPPORT_KEYS := [
	[0.0, Vector3(0.0, 0.0, 0.0), Vector3.ZERO],
	[0.25, Vector3(1.0, 0.0, 0.0), Vector3.ZERO],
	[0.5, Vector3(1.0, 1.0, 0.0), Vector3.ZERO],
	[0.75, Vector3(1.0, 0.0, 0.0), Vector3.ZERO],
	[0.9, Vector3(1.0, 0.0, 0.0), Vector3.ZERO],
	[1.0, Vector3(0.0, 0.0, 0.0), Vector3.ZERO],
]
