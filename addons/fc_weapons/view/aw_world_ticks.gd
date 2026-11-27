extends Node

## The one node that ticks every held gun when [member AwWorldModel.central_tick] is on: thirty-three
## models cost one engine dispatch and one loop instead of two script calls each (`_notification`
## and `_process`). [AwWorldModel] makes it, hangs it at the end of the root and keeps it on the main
## loop's metadata, never on Engine's (see docs/gdscript-hazards.md). Each model answers whether it
## stays on the list, so turning the switch off hands it back its own `_process`.
##
## With GameSpice Sim's `GSSimWorldHoldBatch` loaded (reached through [ClassDB] by name only) the ticker
## also batches the holder poses: each gun's frame posts one row of what the script settled
## ([code]AwWorldModel._post_row[/code]), then one native `step` follows every support hand and poses every
## holder, and the posed guns finish their frame (the magazine) after it. Without the library a gun
## poses itself as before.

## Typed, yet each entry is read into a Variant: a model freed since it joined is still on the list until this frame drops it.
var _models: Array[Node] = []
## The native batch, null without the library; this frame's rows and the guns whose holders they pose.
var batch: Object = null
## Whether the batch has the reload's support-hand keys (the first gun to open a slot gives them).
var support_keys_set := false
var _rows := PackedFloat64Array()
var _posed: Array[Node] = []


func _init() -> void:
	if ClassDB.class_exists(&"GSSimWorldHoldBatch"):
		batch = ClassDB.instantiate(&"GSSimWorldHoldBatch")


func join(model: Node) -> void:
	_models.append(model)


## How many models are on the list (a model told to stop ticking stays on it). For a suite.
func count() -> int:
	return _models.size()


## One gun's row for this frame's step; [param posed] guns get [code]_finish_frame[/code] after it.
func post(model: Node, row: PackedFloat64Array, posed: bool) -> void:
	_rows.append_array(row)
	if posed:
		_posed.append(model)


## Runs [param models]' frames the way the ticker does, with the native step, outside the tree's
## frame: for a bench and a suite that step guns with a fixed delta.
func advance_all(models: Array, delta: float) -> void:
	var via: Node = self if batch != null else null
	for model: Variant in models:
		model._batch_via = via
		model.advance(delta)
		model._batch_via = null
	_flush()


func _flush() -> void:
	if not _rows.is_empty():
		batch.call(&"step", _rows)
		_rows.clear()
	for model: Variant in _posed:
		if is_instance_valid(model):
			model._finish_frame()
	_posed.clear()


func _process(delta: float) -> void:
	var frame := Engine.get_process_frames()
	var via: Node = self if batch != null else null
	var kept := 0
	for i in _models.size():
		var model: Variant = _models[i]
		if is_instance_valid(model) and model._central_step(frame, delta, via):
			_models[kept] = model
			kept += 1
	_models.resize(kept)
	if via != null:
		_flush()
