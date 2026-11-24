class_name AwGunCues
extends RefCounted
## The handling sounds a gun ships of its own (cue_NAME_N.ogg beside its shot layers, cut by tools/cut_user_sounds.py):
## the reload and cycle cues of AwReloadCues and the aim-down cycle (bolt, pump) that GSWeaponSound would otherwise play
## from the stock set. A gun or cue not listed here plays the stock one.

## gun -> cue -> how many variants cue_NAME_0 .. cue_NAME_(n-1) exist. The selftest checks this against the folder.
const CUES := {
	&"sniper": {&"bolt_lift": 5, &"bolt_back": 6, &"bolt_fwd": 3, &"bolt_down": 6},
	&"shotgun": {&"pump_back": 5, &"pump_fwd": 5, &"shell_load": 7},
	&"revolver": {&"cyl_open": 2, &"cyl_dump": 2, &"round_tick": 11, &"cyl_close": 2, &"cyl_twist": 1},
	&"rifle": {&"mag_out": 1, &"mag_seat": 1, &"charge_back": 1, &"charge_fwd": 1},
}

## The minigun's barrel spin, cut from its recording: a start, a seamless loop and a wind-down. AwWeaponRig drives them from
## AwMinigunSpin through AwShotFx.play_spin; spin_loop comes back with its loop on.
const SPIN: Array[StringName] = [&"spin_up", &"spin_loop", &"spin_down"]
const SPIN_GUN := &"minigun"

static var _cache: Dictionary = {}


static func path_of(gun: StringName, file: String) -> String:
	return "%s%s/%s.ogg" % [AwShotLayers.GUN_SOUNDS, gun, file]


## One of [param weapon_id]'s own variants of [param cue] picked by [param roll], or null (play the stock cue).
static func stream(weapon_id: StringName, cue: StringName, roll: int) -> AudioStream:
	var gun := AwShotLayers.gun_of(weapon_id)
	var count := int((CUES.get(gun, {}) as Dictionary).get(cue, 0))
	if count == 0:
		return null
	return _load(path_of(gun, "cue_%s_%d" % [cue, absi(roll) % count]))


## The minigun's [param part] (one of [constant SPIN]), or null.
static func spin_stream(part: StringName) -> AudioStream:
	if not SPIN.has(part):
		return null
	var s := _load(path_of(SPIN_GUN, String(part)))
	if s != null and &"loop" in s:
		s.set(&"loop", part == &"spin_loop")
	return s


static func _load(path: String) -> AudioStream:
	if not _cache.has(path):
		_cache[path] = load(path) as AudioStream if ResourceLoader.exists(path) else null
	return _cache[path] as AudioStream
