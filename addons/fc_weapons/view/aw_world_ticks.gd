extends Node

## The one node that ticks every held gun when [member AwWorldModel.central_tick] is on: thirty-three
## models cost one engine dispatch and one loop instead of two script calls each (`_notification`
## and `_process`). [AwWorldModel] makes it, hangs it at the end of the root and keeps it on the main
## loop's metadata, never on Engine's (see docs/gdscript-hazards.md). Each model answers whether it
## stays on the list, so turning the switch off hands it back its own `_process`.

## Typed, yet each entry is read into a Variant: a model freed since it joined is still on the list until this frame drops it.
var _models: Array[Node] = []


func join(model: Node) -> void:
	_models.append(model)


## How many models are on the list (a model told to stop ticking stays on it). For a suite.
func count() -> int:
	return _models.size()


func _process(delta: float) -> void:
	var frame := Engine.get_process_frames()
	var kept := 0
	for i in _models.size():
		var model: Variant = _models[i]
		if is_instance_valid(model) and model._central_step(frame, delta):
			_models[kept] = model
			kept += 1
	_models.resize(kept)
