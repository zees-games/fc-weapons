extends RefCounted

## The suite's native hold section: a held gun stepped the same fixed frames (a swing, a throw, an inspect,
## a reload, a sprint, a wall and two shots) with [member AwWorldModel.native_hold] on and off holds the same
## transform to the bit, with the person's carry on and off. Without GameSpice Sim both passes run the script,
## so the comparison still runs; with it, the kernel must have been made. A third pass steps the gun the way the
## ticker does with its native batch (`aw_world_ticks.gd`'s `advance_all`), and the bench's 32 guns go through all
## three; each frame compares the holder, the support grip the person was given and the magazine. Reports through
## the suite's `_begin`, `_check` and `_end`.

const FRAMES := 130
const STEP := 1.0 / 60.0
const SCRIPT := 0
const NATIVE := 1
const BATCH := 2
const GUNS := 32
const GUN_FRAMES := 300
const IDS: Array[StringName] = [&"rifle", &"pistol", &"launcher", &"knife"]
const WorldTicks := preload("res://addons/fc_weapons/view/aw_world_ticks.gd")


class Carry extends RefCounted:
	var reloading := false
	var switching := false
	var klass: Variant = null

	func fired(_kick: Variant = null) -> void:
		pass

	func set_class(value: Variant) -> void:
		klass = value


class Person extends Node3D:
	var sprint_blend := 0.0
	var carry := Carry.new()

	func swing(_which: StringName) -> void:
		pass

	func set_hold(_kind: int) -> void:
		pass

	var grip := Vector3.INF

	func set_support_grip(at: Vector3) -> void:
		grip = at


var suite: Node
var _made := false
## Whether a batch pass gave its gun a slot.
var _slotted := false
## Frames of each kind the passes went through, so a pass that skipped one shows.
var _seen := {}


func _init(host: Node) -> void:
	suite = host


## What a frame left: the holder, the grip the person was given, the magazine, as bytes.
static func _frame_bytes(held: AwWorldModel, person: Person) -> PackedByteArray:
	var mag: Variant = held._mag.transform if held._mag != null and is_instance_valid(held._mag) else null
	return var_to_bytes([held._holder.transform, person.grip, mag])


## Each of [constant FRAMES] fixed frames as bytes ([method _frame_bytes]), the hold run by [param mode].
func _pass(mode: int, carry: bool) -> Array[PackedByteArray]:
	var native := mode != SCRIPT
	var was := AwWorldModel.native_hold
	var was_carry := AwWorldModel.person_carry
	var ticks: Node = WorldTicks.new() if mode == BATCH else null
	AwWorldModel.native_hold = native
	AwWorldModel.person_carry = carry
	var person := Person.new()
	suite.add_child(person)
	var held := AwWorldModel.new()
	held._own_tick = true
	person.add_child(held)
	held.equip(suite._dressed(&"rifle"))
	held.set_ticking(false)
	held.set_process(false)
	var out: Array[PackedByteArray] = []
	for frame in range(FRAMES):
		person.sprint_blend = clampf(float(frame - 60) / 20.0, 0.0, 1.0) if frame < 112 else 0.0
		match frame:
			5:
				held.swing()
			15, 120:
				held.on_fired(Vector2(0.9, 0.2))
			25:
				held.throw()
			80:
				held.on_reloading(true)
			104:
				held.on_reloading(false)
		if frame >= 45 and frame < 75:
			held.on_inspect(float(frame - 45) / 30.0)
		if frame >= 30 and frame < 50:
			held._wall_amount = 0.02 + 0.001 * frame
		if ticks != null:
			ticks.advance_all([held], STEP)
		else:
			held.advance(STEP)
		if mode == NATIVE and held._hold_native != null:
			_made = true
		if mode == BATCH and held._batch_slot >= 0:
			_slotted = true
		if held._action < 1.0:
			_seen["action"] = true
		if held._inspect_shown > 0.0:
			_seen["inspect"] = true
		if held._reload_blend > 0.0:
			_seen["reload"] = true
		if held._sprint > 0.0:
			_seen["sprint"] = true
		if held._wall_amount > 0.0:
			_seen["wall"] = true
		out.append(_frame_bytes(held, person))
	person.queue_free()
	if ticks != null:
		ticks.free()
	AwWorldModel.native_hold = was
	AwWorldModel.person_carry = was_carry
	return out


func _first_difference(a: Array[PackedByteArray], b: Array[PackedByteArray]) -> int:
	for frame in range(mini(a.size(), b.size())):
		if a[frame] != b[frame]:
			return frame
	return -1 if a.size() == b.size() else mini(a.size(), b.size())


## The bench's scene ([code]aw_world_bench.gd[/code]): [constant GUNS] guns of four kinds on people in a grid, its
## shots, swings, reloads and sprints, [constant GUN_FRAMES] frames; every gun's every frame as bytes.
func _bench_pass(mode: int) -> Array[PackedByteArray]:
	var was := AwWorldModel.native_hold
	AwWorldModel.native_hold = mode != SCRIPT
	var ticks: Node = WorldTicks.new() if mode == BATCH else null
	var root := Node3D.new()
	suite.add_child(root)
	var guns: Array[AwWorldModel] = []
	var people: Array[Person] = []
	for i in GUNS:
		var person := Person.new()
		person.position = Vector3(float(i % 8) * 2.0, 0.0, float(i / 8) * 2.0)
		root.add_child(person)
		var held := AwWorldModel.new()
		held._own_tick = true
		person.add_child(held)
		held.equip(suite._dressed(IDS[i % IDS.size()]))
		held.set_ticking(false)
		held.set_process(false)
		guns.append(held)
		people.append(person)
	var out: Array[PackedByteArray] = []
	for frame in GUN_FRAMES:
		for i in GUNS:
			var held := guns[i]
			var phase := (frame + i * 17) % 240
			people[i].sprint_blend = clampf(float(phase - 120) / 20.0, 0.0, 1.0) if phase < 200 else 0.0
			if phase % 9 == 0 and phase < 100:
				held.on_fired(Vector2(0.9, 0.2), AwWeaponNet.KIND_SWING if i % 4 == 3 else AwWeaponNet.KIND_SHOT, false)
			if phase == 30:
				held.on_reloading(true)
			elif phase == 110:
				held.on_reloading(false)
		if ticks != null:
			ticks.advance_all(guns, STEP)
		else:
			for held in guns:
				held.advance(STEP)
		for i in GUNS:
			out.append(_frame_bytes(guns[i], people[i]))
	root.free()
	if ticks != null:
		ticks.free()
	AwWorldModel.native_hold = was
	return out


func run() -> void:
	suite._begin("native hold matches the script to the bit")
	var library := ClassDB.class_exists(&"GSSimWorldHold")
	var batched := ClassDB.class_exists(&"GSSimWorldHoldBatch")
	for carry: bool in [true, false]:
		_seen.clear()
		var script := _pass(SCRIPT, carry)
		var differ := _first_difference(_pass(NATIVE, carry), script)
		suite._check("person carry %s: native hold (library %s) and script hold the same transform on all %d frames (first differs at %d; saw %s)"
			% ["on" if carry else "off", "loaded" if library else "absent", FRAMES, differ, ",".join(_seen.keys())],
			differ < 0 and _seen.size() == 5)
		differ = _first_difference(_pass(BATCH, carry), script)
		suite._check("person carry %s: the ticker's batch (library %s) gives the same holder, grip and magazine on all %d frames (first differs at %d)"
			% ["on" if carry else "off", "loaded" if batched else "absent", FRAMES, differ], differ < 0)
	suite._check("the kernel is made exactly when the library is loaded (library %s, made %s)" % [library, _made], _made == library)
	suite._check("the batch gives a gun a slot exactly when the library is loaded (library %s, slotted %s)" % [batched, _slotted], _slotted == batched)
	var script_guns := _bench_pass(SCRIPT)
	for mode: int in [NATIVE, BATCH]:
		var differ := _first_difference(_bench_pass(mode), script_guns)
		suite._check("the bench's %d guns over %d frames: %s matches the script to the bit (first differs at gun-frame %d)"
			% [GUNS, GUN_FRAMES, "the native hold" if mode == NATIVE else "the ticker's batch", differ], differ < 0)
	suite._end()
