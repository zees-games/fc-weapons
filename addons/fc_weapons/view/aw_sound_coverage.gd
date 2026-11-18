class_name AwSoundCoverage
extends RefCounted

## Which sounds each weapon of the pack has as a recording, and which it only borrows or synthesises. [method gaps] is what a suite asserts empty:
## a weapon missing a sound a player should hear (fire, reload out and in, equip, dry, impact; a melee weapon's swing and bash; a grenade's throw and detonation).
## [method weak] lists what exists but is shared or generic, so the next sound pass knows where to spend effort; it is a report, not a failure.

## Sounds [param id] lacks altogether: no recording where one is required.
static func gaps(id: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	if id == &"knife":
		_need(out, id, "swing", DotWeaponSound.pick(&"swing") != null)
		_need(out, id, "bash", DotWeaponSound.pick(&"bash") != null)
		_need(out, id, "impact", DotWeaponSound.pick(&"melee_flesh") != null and DotWeaponSound.pick(&"melee_metal") != null)
		_need(out, id, "equip", DotWeaponSound.pick_feel(&"light", &"equip") != null)
		return out
	if AwWeaponPack.SOUND_CLASSES.has(id):
		var sound_class: StringName = AwWeaponPack.SOUND_CLASSES[id]
		var own := ResourceLoader.exists("%s%s/attack_0.ogg" % [AwShotLayers.GUN_SOUNDS, id])
		_need(out, id, "fire", own or DotWeaponSound.pick_class(sound_class) != null)
		_need(out, id, "reload out", DotWeaponSound.pick_reload(sound_class, &"out") != null)
		_need(out, id, "reload in", DotWeaponSound.pick_reload(sound_class, &"in") != null)
		_need(out, id, "equip", DotWeaponSound.pick_feel(sound_class, &"equip") != null)
		_need(out, id, "dry", DotWeaponSound.pick_feel(sound_class, &"dry") != null)
		_need(out, id, "impact", DotWeaponSound.pick(&"impact") != null)
		return out
	_need(out, id, "throw", DotWeaponSound.pick(&"throw") != null)
	_need(out, id, "pin pull", DotWeaponSound.pick(&"pin_pull") != null)
	_need(out, id, "detonation", AwGrenadeSound.count(id) > 0)
	return out


## Sounds [param id] has only in a generic or shared form.
static func weak(id: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	if not AwWeaponPack.SOUND_CLASSES.has(id):
		return out
	var sound_class: StringName = AwWeaponPack.SOUND_CLASSES[id]
	for stage in [&"out", &"in"]:
		if sound_class != &"shotgun" and DotWeaponSound.reload_name(sound_class, stage) == StringName("reload_" + String(stage)):
			out.append("reload %s is the generic set" % stage)
	if not ResourceLoader.exists("%s%s/attack_0.ogg" % [AwShotLayers.GUN_SOUNDS, id]):
		out.append("fire is the class stock (%s), shared with other guns" % sound_class)
	if not ResourceLoader.exists("%s%s/far_0.ogg" % [AwShotLayers.GUN_SOUNDS, id]) and DotWeaponSound.pick_far(sound_class) == null:
		out.append("no distant report")
	return out


static func _need(out: PackedStringArray, id: StringName, what: String, present: bool) -> void:
	if not present:
		out.append("%s: no %s sound" % [id, what])
