@tool
extends "aw_world_model_fit.gd"

## Ticking part of [AwWorldModel], split out for file size: whether a held gun runs its own `_process`
## or is one of the guns [code]aw_world_ticks.gd[/code] runs in one loop. The frame itself is
## [method _tick], which [AwWorldModel] defines.

## One ticker node runs every held gun's frame instead of each gun's own `_process` (off by
## default; a game maps its own cvar onto it). Same steps, same order within a gun, one
## frame later in the tree than the gun's own place; nothing a shot or hit reads comes from here.
## A game that turned a gun's processing off to thin it calls [method set_ticking] instead, which
## works either way. Turned off at run time, every gun gets its own `_process` back on its next frame.
static var central_tick := false

const WorldTicks := preload("aw_world_ticks.gd")
const TICKS_META := &"fc_weapons_world_ticks"

## Whether this gun should be ticked (see [method set_ticking]), whether the ticker holds it, the
## process frame it last ticked in, and a suite's way of keeping one gun on its own `_process`.
var _tick_wanted := true
var _central := false
var _ticked_frame := -1
var _own_tick := false


## Starts or stops this gun's frame: `set_process` when it ticks itself, the ticker's skip when it is
## central. A game thinning far bodies calls this rather than `set_process`, which the central
## ticker cannot see.
func set_ticking(on: bool) -> void:
	_tick_wanted = on
	if not _central:
		set_process(on)


## Whether this gun's frame runs, by [method set_ticking] or by `set_process` while it ticks itself.
func is_ticking() -> bool:
	return _tick_wanted if _central else is_processing()


func _process(delta: float) -> void:
	_ticked_frame = Engine.get_process_frames()
	_tick(delta)
	if central_tick and not _own_tick and not Engine.is_editor_hint():
		_join_central()


## Hands this gun to the tree's ticker and stops its own `_process`. Someone calling
## `set_process(true)` later just brings it back here for a frame; the stamp stops a double tick.
func _join_central() -> void:
	var ticks := _world_ticks()
	if ticks == null:
		return
	_tick_wanted = true
	set_process(false)
	if not _central:
		_central = true
		ticks.join(self)


## The ticker's call, once a frame: false drops this gun from its list.
func _central_step(frame: int, delta: float) -> bool:
	if not central_tick or not _central:
		_central = false
		set_process(_tick_wanted)
		return false
	if not _tick_wanted or _ticked_frame == frame or not is_inside_tree() or not can_process():
		return true
	_ticked_frame = frame
	_tick(delta)
	return true


## The tree's ticker, made and parented at the end of the root on first use.
static func _world_ticks() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return null
	if loop.has_meta(TICKS_META):
		var held: Variant = loop.get_meta(TICKS_META)
		if is_instance_valid(held):
			return held
	var made := WorldTicks.new()
	made.name = "AwWorldTicks"
	made.process_mode = Node.PROCESS_MODE_ALWAYS
	loop.root.add_child.call_deferred(made)
	loop.set_meta(TICKS_META, made)
	return made


## The ticker, or null before any gun joined it. For a suite.
static func world_ticks() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or not loop.has_meta(TICKS_META):
		return null
	var held: Variant = loop.get_meta(TICKS_META)
	return held if is_instance_valid(held) else null


## One frame of the gun, defined by [AwWorldModel].
func _tick(_delta: float) -> void:
	pass
