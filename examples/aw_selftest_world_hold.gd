extends RefCounted

## The suite's native hold section: a held gun stepped the same fixed frames (a swing, a throw, an inspect,
## a reload, a sprint, a wall and two shots) with [member AwWorldModel.native_hold] on and off holds the same
## transform to the bit, with the person's carry on and off. Without GameSpice Sim both passes run the script,
## so the comparison still runs; with it, the kernel must have been made. A third pass steps the gun the way the
## ticker does with its native batch (`aw_world_ticks.gd`'s `advance_all`), and the bench's 32 guns go through all
## three; each frame compares the holder, the support grip the person was given and the magazine. Reports through
## the suite's `_begin`, `_check` and `_end`. Partway through, the art is edited and says so ([signal Resource.changed]),
## so a batch slot that kept the old rest pose shows as a difference.

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
		if frame == 62:
			held._art.world_offset += Vector3(0.0, 0.01, -0.02)
			held._art.emit_changed()
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


## A box body of [param size] at [param at] under [param parent]; a character when [param character].
static func _box(parent: Node, at: Vector3, size: Vector3, character := false) -> CollisionObject3D:
	var body: CollisionObject3D = CharacterBody3D.new() if character else StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	body.global_position = at
	return body


## The wall probe looks past its carrier's own body and past characters: a ray's exclusions are assigned whole
## ([code]query.exclude[/code] hands back a copy, so appending to it used to exclude nothing).
func _wall_exclusions() -> void:
	suite._begin("the wall probe excludes its carrier and passes characters")
	var carrier := StaticBody3D.new()
	suite.add_child(carrier)
	var person := Person.new()
	carrier.add_child(person)
	var held := AwWorldModel.new()
	held._own_tick = true
	person.add_child(held)
	held.equip(suite._dressed(&"rifle"))
	held.set_ticking(false)
	held.set_process(false)
	var hand := held._holder.global_position
	var forward := Vector3.FORWARD
	var length := hand.distance_to(held.muzzle_transform().origin)
	var flat := Vector3(4.0, 4.0, 0.1)
	var own := CollisionShape3D.new()
	var own_box := BoxShape3D.new()
	own_box.size = flat
	own.shape = own_box
	carrier.add_child(own)
	own.global_position = hand + forward * 0.05
	await suite.get_tree().physics_frame
	await suite.get_tree().physics_frame
	var plain := PhysicsRayQueryParameters3D.create(hand - forward * AwWorldModel.WALL_ARM, hand + forward * length)
	var crossed := held.get_world_3d().direct_space_state.intersect_ray(plain)
	var pull := held._probe_wall()
	suite._check("the carrier's own body crosses the probe's ray (hit %s) yet the probe sees no wall (pull %.3f)"
		% [not crossed.is_empty(), pull], not crossed.is_empty() and crossed["collider"] == carrier and pull == 0.0)
	var stranger := _box(suite, hand + forward * 0.05 + Vector3(0.0, 0.0, -0.02), flat, true)
	var wall := _box(suite, hand + forward * (length * 0.5), flat)
	await suite.get_tree().physics_frame
	await suite.get_tree().physics_frame
	held._wall_from = Vector3.INF
	pull = held._probe_wall()
	var face := (hand - forward * AwWorldModel.WALL_ARM).distance_to(wall.global_position) - flat.z * 0.5
	var want := AwWorldModel.wall_pull(face, length, AwWorldModel.WALL_ARM, AwWorldModel.WALL_MARGIN, held.wall_max_pull)
	suite._check("a character in front of a wall is passed and the wall pulls the gun (pull %.4f, want %.4f)" % [pull, want],
		want > 0.0 and absf(pull - want) < 0.001)
	wall.free()
	await suite.get_tree().physics_frame
	var kept := held._probe_wall()
	held._wall_still = AwWorldModel.WALL_STILL_SECONDS
	var fresh := held._probe_wall()
	suite._check("a still hand keeps the last answer until %.1f s pass, then asks again (kept %.4f, then %.4f)"
		% [AwWorldModel.WALL_STILL_SECONDS, kept, fresh], kept == pull and fresh == 0.0)
	stranger.free()
	carrier.free()
	suite._end()


func run() -> void:
	await _wall_exclusions()
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
