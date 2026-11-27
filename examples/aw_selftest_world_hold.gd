extends RefCounted

## The suite's native hold section: a held gun stepped the same fixed frames (a swing, a throw, an inspect,
## a reload, a sprint, a wall and two shots) with [member AwWorldModel.native_hold] on and off holds the same
## transform to the bit, with the person's carry on and off. Without GameSpice Sim both passes run the script,
## so the comparison still runs; with it, the kernel must have been made. Reports through the suite's
## `_begin`, `_check` and `_end`.

const FRAMES := 130
const STEP := 1.0 / 60.0


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

	func set_support_grip(_at: Vector3) -> void:
		pass


var suite: Node
var _made := false
## Frames of each kind the passes went through, so a pass that skipped one shows.
var _seen := {}


func _init(host: Node) -> void:
	suite = host


## The holder's transform as bytes for each of [constant FRAMES] fixed frames, with the native hold [param native].
func _pass(native: bool, carry: bool) -> Array[PackedByteArray]:
	var was := AwWorldModel.native_hold
	var was_carry := AwWorldModel.person_carry
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
		held.advance(STEP)
		if native and held._hold_native != null:
			_made = true
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
		out.append(var_to_bytes(held._holder.transform))
	person.queue_free()
	AwWorldModel.native_hold = was
	AwWorldModel.person_carry = was_carry
	return out


func _first_difference(a: Array[PackedByteArray], b: Array[PackedByteArray]) -> int:
	for frame in range(mini(a.size(), b.size())):
		if a[frame] != b[frame]:
			return frame
	return -1 if a.size() == b.size() else mini(a.size(), b.size())


func run() -> void:
	suite._begin("native hold matches the script to the bit")
	var library := ClassDB.class_exists(&"GSSimWorldHold")
	for carry: bool in [true, false]:
		_seen.clear()
		var differ := _first_difference(_pass(true, carry), _pass(false, carry))
		suite._check("person carry %s: native hold (library %s) and script hold the same transform on all %d frames (first differs at %d; saw %s)"
			% ["on" if carry else "off", "loaded" if library else "absent", FRAMES, differ, ",".join(_seen.keys())],
			differ < 0 and _seen.size() == 5)
	suite._check("the kernel is made exactly when the library is loaded (library %s, made %s)" % [library, _made], _made == library)
	suite._end()
