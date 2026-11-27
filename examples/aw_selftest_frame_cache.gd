extends RefCounted

## The suite's frame cache section: a held gun stepped the same fixed frames with
## [member AwWorldModel.person_cache] on and off tells its person the same sprint, support grip and
## carry flags and holds the same transform; [member AwAdsRules.cache_values] on and off resolve the
## same values, and a changed rule shows through the cache. Reports through the suite's `_begin`,
## `_check` and `_end`.

const FRAMES := 80
const STEP := 1.0 / 60.0

var suite: Node


class Carry extends RefCounted:
	var reloading := false
	var switching := false
	var klass: Variant = null
	var shots := 0

	func fired(_kick: Variant = null) -> void:
		shots += 1

	func set_class(value: Variant) -> void:
		klass = value


class Holder extends Node3D:
	var sprint_blend := 0.0
	var carry := Carry.new()
	var grip := Vector3.INF

	func swing(_which: StringName) -> void:
		pass

	func set_hold(_kind: int) -> void:
		pass

	func set_support_grip(at: Vector3) -> void:
		grip = at


func _init(host: Node) -> void:
	suite = host


## One gun stepped [constant FRAMES] fixed frames with the person cache [param cached]; each frame's
## transform, support grip and carry state.
func _pass(cached: bool) -> Array:
	var was := AwWorldModel.person_cache
	AwWorldModel.person_cache = cached
	var person := Holder.new()
	suite.add_child(person)
	var held := AwWorldModel.new()
	held._own_tick = true
	person.add_child(held)
	held.equip(suite._dressed(&"rifle"))
	held.set_ticking(false)
	held.set_process(false)
	var out := []
	for frame in range(FRAMES):
		person.sprint_blend = clampf(float(frame - 10) / 20.0, 0.0, 1.0) if frame < 40 else 0.0
		match frame:
			5, 65:
				held.on_fired(Vector2(0.9, 0.2))
			20:
				held.on_reloading(true)
			45:
				held.on_reloading(false)
			55:
				person.carry = Carry.new()
		held.advance(STEP)
		var carry: Carry = person.carry
		out.append([held._holder.transform, person.grip, carry.reloading, carry.switching, carry.klass])
	person.queue_free()
	AwWorldModel.person_cache = was
	return out


func run() -> void:
	suite._begin("per-frame caches match the uncached path")
	var cached := _pass(true)
	var plain := _pass(false)
	var differ := -1
	var reloads := 0
	for frame in range(FRAMES):
		if differ < 0 and str(cached[frame]) != str(plain[frame]):
			differ = frame
		if cached[frame][2]:
			reloads += 1
	suite._check("person cache on and off tell and hold the same on all %d frames (first differs at %d; %d reloading)" % [FRAMES, differ, reloads],
		differ < 0 and reloads > 10 and cached[FRAMES - 1][4] != null)

	var rules := AwAdsRules.new()
	var was := AwAdsRules.cache_values
	var mismatched := 0
	for id: StringName in AwWeaponPack.IDS:
		for key: String in AwAdsRules.SPECS:
			AwAdsRules.cache_values = true
			var a: Variant = rules.value_for(id, key)
			var a2: Variant = rules.value_for(id, key)
			AwAdsRules.cache_values = false
			if str(a) != str(rules.value_for(id, key)) or str(a2) != str(a):
				mismatched += 1
		AwAdsRules.cache_values = true
		var wall_a := str(rules.wall_for(id))
		AwAdsRules.cache_values = false
		if wall_a != str(rules.wall_for(id)):
			mismatched += 1
	suite._check("ADS values and wall rows cached match uncached for every weapon (%d differ)" % mismatched, mismatched == 0)

	AwAdsRules.cache_values = true
	var id: StringName = AwWeaponPack.IDS[0]
	var before: float = float(rules.value_for(id, "aim_time"))
	rules.set_value(id, "aim_time", before + 0.5)
	var after_set: float = float(rules.value_for(id, "aim_time"))
	rules.weapons[String(id)]["aim_time"] = before + 0.25
	rules.touch()
	var after_touch: float = float(rules.value_for(id, "aim_time"))
	suite._check("a set value and a touched in-place edit show through the cache (%.2f -> %.2f -> %.2f)" % [before, after_set, after_touch],
		is_equal_approx(after_set, before + 0.5) and is_equal_approx(after_touch, before + 0.25))
	AwAdsRules.cache_values = was
	suite._end()
