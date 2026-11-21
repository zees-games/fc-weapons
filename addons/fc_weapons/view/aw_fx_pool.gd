class_name AwFxPool
extends Node
## What a world model needs for its first shot or charge, built ahead under a loading cover.
##
## A game adds one to its tree, calls [method fill] and [method fill_flashes] until both
## answer true, and from then on [AwWorldModel] takes its effects from here instead of building
## them in the tick. An empty pool is not an error: the world model builds its own as before.

const ChargeFx := preload("aw_charge_fx.gd")
const FLASH_VARIANTS := 6

## Quads a parked [AwShotFx] holds: a flash, its petals, a tracer and an impact or two.
@export_range(6, 32) var shot_meshes: int = 12

## The bus of the layered shot every remote shooter shares, which [method fill] builds once the parked effects are.
## Empty builds none, and each remote shooter then builds its own on its first shot.
@export var layers_bus: StringName = &"Master"

## Quads built ahead for the pool every remote shooter's flashes, tracers and impacts share, so the first shot of a crowd
## compiles and allocates nothing. The pool grows past it by demand; 0 builds none ahead and the first shots build them.
@export_range(0, 4096) var shared_meshes: int = 24

## Flash lights built ahead for the shared pool; it grows past it by demand.
@export_range(0, 256) var shared_lights: int = 4

## Most idle quads the shared pool keeps after a burst; a release past it frees the quad. 0 keeps every one built
## (the pool is only as big as the most effects that were ever in the air at once, across all shooters).
@export_range(0, 65536) var shared_idle: int = 0

## The pool in the tree. Typed loosely: a static of a script's own type can outlive the script.
static var _current: Node = null

## Handed out, and asked for with nothing parked. For a suite and a game's log line.
var handed: int = 0
var missed: int = 0

var _parked: Node = null
var _shots: Array[AwShotFx] = []
var _charges: Array[Node3D] = []
## Flash size to the flashes every remote shooter shares, and whose turn is next.
var _rings: Dictionary = {}
var _turn: Dictionary = {}
var _flash_script: GDScript = null
## Bus to the shared layered shot (an [AwShotLayers]) on it.
var _layers: Dictionary = {}
## The quads and flash lights every remote [AwShotFx] draws from, built on the first ask. Effects are top-level and
## world-space, so a shooter owns nothing but its report voices: 63 remote players held 14 nodes each before this.
var _shared_mesh_pool: AwSharedMeshPool = null
var _shared_light_pool: GSFxLightPool = null


func _enter_tree() -> void:
	if _parked == null:
		_parked = Node.new()
		_parked.name = "Parked"
		# Parked effects wait without a tick; taking one out gives it its own back.
		_parked.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(_parked)
	_current = self


func _exit_tree() -> void:
	if _current == self:
		_current = null


## The pool in the tree, or null.
static func current() -> AwFxPool:
	return (_current as AwFxPool) if is_instance_valid(_current) else null


## A parked effects node, out of the tree and ready to be added to a hand. Null with none left.
static func take_shot_fx() -> AwShotFx:
	var pool := current()
	return pool._take_shot() if pool != null else null


## A parked charge ball, out of the tree, built without a light. Null with none left.
static func take_charge_fx() -> Node3D:
	var pool := current()
	return pool._take_charge() if pool != null else null


## The shared flash for the next remote shot of this size, or null when the pool keeps none.
static func shared_flash(category: String, def: GSWeaponDef, suppressed: bool) -> Node3D:
	var pool := current()
	return pool._next_flash(category, def, suppressed) if pool != null else null


## The layered shot the pool shares with remote shooters on [param bus] in [param fx]'s viewport, or null (no pool,
## another viewport, no gs-audio). Built on the first ask, about 60 ms: one per shooter was that on each one's first shot.
static func shared_layers(fx: Node, bus: StringName) -> AwShotLayers:
	var pool := current()
	if pool == null or fx == null or not fx.is_inside_tree() or fx.get_viewport() != pool.get_viewport():
		return null
	return pool._shared_layers(bus)


## The quad pool and the light pool remote shooters in [param fx]'s viewport share, as [lights, meshes], or an empty
## array (no pool, another viewport: the effect then builds its own, as before). Built on the first ask, and prewarmed
## from [member shared_meshes] and [member shared_lights] so the first shot of the crowd compiles nothing.
static func shared_pools(fx: AwShotFx) -> Array:
	var pool := current()
	if pool == null or fx == null or not fx.is_inside_tree() or fx.get_viewport() != pool.get_viewport():
		return []
	return pool._shared_fx_pools(fx)


func _shared_fx_pools(fx: AwShotFx) -> Array:
	if _shared_mesh_pool == null or not is_instance_valid(_shared_mesh_pool):
		_shared_mesh_pool = AwSharedMeshPool.new()
		_shared_mesh_pool.name = "SharedMeshes"
		_shared_mesh_pool.idle_limit = shared_idle
		add_child(_shared_mesh_pool)
		_shared_light_pool = GSFxLightPool.new()
		_shared_light_pool.name = "SharedLights"
		add_child(_shared_light_pool)
		_shared_light_pool.prewarm(shared_lights)
		_shared_mesh_pool.prewarm(fx._quad_mesh(), fx._flash_mat(), shared_meshes)
	return [_shared_light_pool, _shared_mesh_pool]


## Quads the shared pool has built, in use or idle. For a suite and a game's log line.
func shared_mesh_count() -> int:
	return _shared_mesh_pool.built() if _shared_mesh_pool != null else 0


## Builds parked effects up to [param shots] and [param charges], at least one a call, stopping
## after [param budget_msec], then the shared layered shot on [member layers_bus]. True when all are built:
## call it each frame under the cover until then.
func fill(shots: int, charges: int, budget_msec: float = 2.0) -> bool:
	if not is_inside_tree():
		return false
	var start := Time.get_ticks_usec()
	_drop_freed()
	while _shots.size() < shots or _charges.size() < charges:
		if _shots.size() < shots:
			_park_shot()
		else:
			_park_charge()
		if float(Time.get_ticks_usec() - start) > budget_msec * 1000.0:
			return _shots.size() >= shots and _charges.size() >= charges and _layers_built()
	if not _layers_built():
		var _built := _shared_layers(layers_bus)
	return true


func _layers_built() -> bool:
	return layers_bus == &"" or _layers.has(layers_bus)


func _shared_layers(bus: StringName) -> AwShotLayers:
	var held: Variant = _layers.get(bus)
	if held != null and is_instance_valid(held):
		var kept: AwShotLayers = held
		return kept if kept.is_ready() else null
	if not is_inside_tree() or not AwShotLayers.available():
		_layers[bus] = null
		return null
	var layers := AwShotLayers.new()
	layers.follow_camera = true
	add_child(layers)
	_layers[bus] = layers
	return layers if layers.setup(bus) else null


## Builds [param each] shared flashes per size the [param categories] draw (default: every class's).
## True when all are built or none can draw here; each flash builds itself a node a frame.
func fill_flashes(each: int = 8, categories: PackedStringArray = PackedStringArray()) -> bool:
	if not is_inside_tree() or not ResourceLoader.exists(GSWeaponMuzzle.SCRIPT_PATH):
		return true
	if _flash_script == null:
		_flash_script = load(GSWeaponMuzzle.SCRIPT_PATH)
	if not _flash_script.call("available"):
		return true
	var wanted := categories.duplicate()
	if wanted.is_empty():
		for category: String in AwShotFx.CLASS_CATEGORY.values():
			if not wanted.has(category):
				wanted.append(category)
	for category in wanted:
		var size: int = _flash_script.call("size_for", category, {}, false)
		if size == 0:
			continue
		var ring: Array = _rings.get(size, [])
		_rings[size] = ring
		while ring.size() < each:
			var flash: Node3D = _flash_script.new()
			flash.set("size", size)
			flash.set("first_person", false)
			flash.set("variant", 1 + ring.size() % FLASH_VARIANTS)
			flash.top_level = true
			# Built under a cover that may have the tree paused.
			flash.process_mode = Node.PROCESS_MODE_ALWAYS
			add_child(flash)
			ring.append(flash)
	return flashes_ready()


## Whether every shared flash has finished building.
func flashes_ready() -> bool:
	for ring: Array in _rings.values():
		for flash: Node3D in ring:
			if is_instance_valid(flash) and not bool(flash.call("is_ready")):
				return false
	return true


## Parked effects nodes waiting to be taken.
func spare_shots() -> int:
	return _shots.size()


## Parked charge balls waiting to be taken.
func spare_charges() -> int:
	return _charges.size()


## Shared flashes kept, over every size.
func flash_count() -> int:
	var count := 0
	for ring: Array in _rings.values():
		count += ring.size()
	return count


func _park_shot() -> void:
	var fx := AwShotFx.new()
	_parked.add_child(fx)
	fx.prewarm_parked(shot_meshes)  # its voices; the quads are the shared pool's
	_shots.append(fx)


func _park_charge() -> void:
	var fx: Node3D = ChargeFx.new()
	fx.set("with_light", false)
	_parked.add_child(fx)
	fx.call("prewarm")
	_charges.append(fx)


func _take_shot() -> AwShotFx:
	while not _shots.is_empty():
		var fx: AwShotFx = _shots.pop_back()
		if is_instance_valid(fx):
			_parked.remove_child(fx)
			handed += 1
			return fx
	missed += 1
	return null


func _take_charge() -> Node3D:
	while not _charges.is_empty():
		var fx: Node3D = _charges.pop_back()
		if is_instance_valid(fx):
			_parked.remove_child(fx)
			handed += 1
			return fx
	missed += 1
	return null


func _next_flash(category: String, def: GSWeaponDef, suppressed: bool) -> Node3D:
	if _rings.is_empty():
		return null
	var extra := {GSWeaponMuzzle.KEY: GSWeaponMuzzle.flash_name(def)}
	var size: int = _flash_script.call("size_for", category, extra, suppressed)
	var ring: Array = _rings.get(size, [])
	if ring.is_empty():
		return null
	var turn: int = (int(_turn.get(size, -1)) + 1) % ring.size()
	_turn[size] = turn
	var flash: Node3D = ring[turn]
	return flash if is_instance_valid(flash) else null


func _drop_freed() -> void:
	var shots: Array[AwShotFx] = []
	for fx in _shots:
		if is_instance_valid(fx):
			shots.append(fx)
	_shots = shots
	var charges: Array[Node3D] = []
	for fx in _charges:
		if is_instance_valid(fx):
			charges.append(fx)
	_charges = charges
