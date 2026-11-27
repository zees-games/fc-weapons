extends Node

## Where a held gun's frame goes: [constant GUNS] world models on stand-in people (a carry, a sprint
## blend, a support grip), stepped [constant FRAMES] fixed frames with shots, swings, reloads and
## sprints mixed in, the whole [method AwWorldModel.advance] timed and each of its parts on its own.
## Prints one line per part (microseconds per gun per frame) and quits. A profiling tool, not a check.

const GUNS := 32
const FRAMES := 600
const STEP := 1.0 / 60.0
const IDS: Array[StringName] = [&"rifle", &"pistol", &"launcher", &"knife"]


class Carry extends RefCounted:
	var reloading := false
	var switching := false
	var raised := false

	func fired(_kick: Variant = null) -> void:
		pass

	func set_class(_value: Variant) -> void:
		pass


class Person extends Node3D:
	var sprint_blend := 0.0
	var carry: Variant = Carry.new()
	var grip := Vector3.INF

	func swing(_which: StringName) -> void:
		pass

	func set_hold(_kind: int) -> void:
		pass

	func set_support_grip(at: Vector3) -> void:
		grip = at


var _guns: Array[AwWorldModel] = []
var _people: Array[Person] = []


func _ready() -> void:
	var carry := "--no-carry" not in OS.get_cmdline_user_args()
	for i in GUNS:
		var person := Person.new()
		if not carry:
			person.carry = null
		person.position = Vector3(float(i % 8) * 2.0, 0.0, float(i / 8) * 2.0)
		add_child(person)
		var held := AwWorldModel.new()
		held._own_tick = true
		person.add_child(held)
		held.equip(_dressed(IDS[i % IDS.size()]))
		held.set_process(false)
		_guns.append(held)
		_people.append(person)
	await get_tree().process_frame
	await get_tree().physics_frame
	var parts := {
		"advance": func(g: AwWorldModel) -> void: g.advance(STEP),
		"advance_script": func(g: AwWorldModel) -> void: g.advance(STEP),
		"follow_person": func(g: AwWorldModel) -> void: g._follow_person(),
		"advance_wall": func(g: AwWorldModel) -> void: g._advance_wall(STEP),
		"inspect_turn": func(g: AwWorldModel) -> void: g._inspect_turn(STEP, false),
		"rest": func(g: AwWorldModel) -> void: g._rest(),
		"sprint_carry": func(g: AwWorldModel) -> void: g._sprint_carry(),
		"move_magazine": func(g: AwWorldModel) -> void: g._move_magazine(),
		"empty_call": func(_g: AwWorldModel) -> void: pass,
	}
	print("aw_world_bench: guns=%d frames=%d carry=%s native_hold=%s" % [GUNS, FRAMES, carry, ClassDB.class_exists(&"GSSimWorldHold")])
	var was := AwWorldModel.native_hold
	for part: String in parts:
		# "advance" runs with the native hold where the library has it, "advance_script" with the switch off.
		AwWorldModel.native_hold = part != "advance_script"
		var usec := _run(parts[part])
		print("aw_world_bench: %-14s %7.2f us/gun/frame" % [part, float(usec) / float(GUNS * FRAMES)])
	AwWorldModel.native_hold = was
	get_tree().quit(0)


## Steps every gun [constant FRAMES] frames through the same script of events and returns the
## microseconds spent in [param part] alone.
func _run(part: Callable) -> int:
	var spent := 0
	for frame in FRAMES:
		for i in GUNS:
			var held := _guns[i]
			var person := _people[i]
			var phase := (frame + i * 17) % 240
			person.sprint_blend = clampf(float(phase - 120) / 20.0, 0.0, 1.0) if phase < 200 else 0.0
			if phase % 9 == 0 and phase < 100:
				held.on_fired(Vector2(0.9, 0.2), AwWeaponNet.KIND_SWING if i % 4 == 3 else AwWeaponNet.KIND_SHOT, false)
			if phase == 30:
				held.on_reloading(true)
			elif phase == 110:
				held.on_reloading(false)
		var t := Time.get_ticks_usec()
		for held in _guns:
			part.call(held)
		spent += Time.get_ticks_usec() - t
	return spent


func _dressed(id: StringName) -> AwWeaponVisual:
	var art: AwWeaponVisual
	match id:
		&"knife":
			art = AwWeaponArtTable.knife()
		&"pistol":
			art = AwWeaponArtTable.pistol()
		&"launcher":
			art = AwWeaponArtTable.launcher()
		_:
			art = AwWeaponArtTable.rifle()
	art.id = id
	AwArtDress.apply(art, AwWeaponArt.weapon_rows("").get(id, {}))
	return art
