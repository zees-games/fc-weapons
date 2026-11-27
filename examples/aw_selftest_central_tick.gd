extends RefCounted

## The suite's central tick section: two held guns told the same things on the same frames, one on its own
## `_process` and one on the ticker, hold the same transform every frame, stop and start through
## `set_ticking` either way, and the ticker hands its gun back when the switch goes off. Reports through
## the suite's `_begin`, `_check` and `_end`.

const FRAMES := 90

var suite: Node


class Holder extends Node3D:
	func swing(_which: StringName) -> void:
		pass

	func set_hold(_kind: int) -> void:
		pass


func _init(host: Node) -> void:
	suite = host


func _held(own: bool) -> Array:
	var person := Holder.new()
	suite.add_child(person)
	var held := AwWorldModel.new()
	held._own_tick = own
	person.add_child(held)
	held.equip(suite._dressed(&"rifle"))
	return [person, held]


func _tell(guns: Array, frame: int) -> void:
	for held: AwWorldModel in guns:
		match frame:
			5, 75:
				held.on_fired(Vector2(0.9, 0.2))
			20:
				held.on_reloading(true)
			50:
				held.on_reloading(false)
			60:
				held.swing()


func run() -> void:
	suite._begin("held guns on one ticker match their own _process")
	var was := AwWorldModel.central_tick
	var was_native := AwWorldModel.native_hold
	var batched := ClassDB.class_exists(&"GSSimWorldHoldBatch")
	AwWorldModel.central_tick = true
	AwWorldModel.native_hold = true
	var own_pair := _held(true)
	var central_pair := _held(false)
	var own: AwWorldModel = own_pair[1]
	var central: AwWorldModel = central_pair[1]
	var guns := [own, central]
	var differ := -1
	var moved := 0
	var rest: Transform3D = own._holder.transform
	for frame in range(FRAMES):
		_tell(guns, frame)
		await suite.get_tree().process_frame
		if differ < 0 and own._holder.transform != central._holder.transform:
			differ = frame
		if own._holder.transform != rest:
			moved += 1
	suite._check("both guns hold the same transform on all %d frames (first differs at %d; %d frames off rest)" % [FRAMES, differ, moved],
		differ < 0 and moved > 20)
	var ticks := AwWorldModel.world_ticks()
	suite._check("the ticker holds the central gun and its own _process is off",
		ticks != null and ticks.count() == 1 and central._central and not central.is_processing())
	suite._check("the other gun still ticks itself", own.is_processing() and not own._central and own.is_ticking())
	suite._check("the ticker poses the central gun in its native batch exactly when the library is loaded (library %s, slot %d)"
		% [batched, central._batch_slot], (central._batch_slot >= 0) == batched and own._batch_slot < 0)

	for held: AwWorldModel in guns:
		held.set_ticking(false)
	var frozen: Transform3D = central._holder.transform
	for held: AwWorldModel in guns:
		held.on_fired(Vector2(0.9, 0.2))
	for _i in range(5):
		await suite.get_tree().process_frame
	suite._check("set_ticking(false) stops both, ticker or not",
		not own.is_ticking() and not central.is_ticking() and central._holder.transform == frozen and own._holder.transform == frozen)
	for held: AwWorldModel in guns:
		held.set_ticking(true)
	for _i in range(5):
		await suite.get_tree().process_frame
	suite._check("set_ticking(true) starts both again, still the same",
		central._holder.transform != frozen and central._holder.transform == own._holder.transform)

	# The native hold keeps a gun on the ticker by itself when the batch is there; off, the switch hands it back.
	AwWorldModel.native_hold = false
	AwWorldModel.central_tick = false
	await suite.get_tree().process_frame
	await suite.get_tree().process_frame
	suite._check("the switch off hands the gun back its own _process",
		central.is_processing() and not central._central and ticks.count() == 0)
	AwWorldModel.native_hold = true
	await suite.get_tree().process_frame
	await suite.get_tree().process_frame
	suite._check("with central_tick off, the native hold takes the gun to the ticker exactly when the batch is loaded (library %s)" % batched,
		central._central == batched and ticks.count() == int(batched) and central.is_processing() != batched)
	AwWorldModel.central_tick = was
	AwWorldModel.native_hold = was_native
	own_pair[0].queue_free()
	central_pair[0].queue_free()
	suite._end()
