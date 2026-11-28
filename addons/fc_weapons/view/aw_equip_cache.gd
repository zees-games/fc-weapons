extends RefCounted

## The built first-person models of weapons the view model has put away, kept by what built them, so switching back is not a rebuild. No `class_name`: AwViewModel preloads it.
## A slot is owned by exactly one place: taken out when drawn, put back when stowed. Stowed nodes sit outside the tree
## and are freed here: by the limit, by [method clear], or by the view model leaving.

## The most weapons kept; the oldest stowed goes first. 0 keeps every one.
var limit: int = 6

## Where a slot pushed out by [member limit], or left when the view goes, is handed instead of being freed: the process's shared
## [code]prewarmed[/code] store, so another view (a kill-view rig, the player's next life) takes the build rather than making it again.
## Null frees them. Only used while [member spill_evicted] is on.
var spill: RefCounted = null
## False frees every slot pushed out, as before.
static var spill_evicted := true

## Key -> slot Dictionary, oldest first (insertion order).
var _slots: Dictionary = {}


## How many weapons are stowed.
func size() -> int:
	return _slots.size()


func has(key: String) -> bool:
	return _slots.has(key)


## The slot for [param key], now owned by the caller; an empty Dictionary when none is kept.
func take(key: String) -> Dictionary:
	if not _slots.has(key):
		return {}
	var slot: Dictionary = _slots[key]
	_slots.erase(key)
	return slot


## Keeps [param slot] under [param key] (a key already kept is freed first), then frees the oldest beyond [member limit].
func put(key: String, slot: Dictionary) -> void:
	if _slots.has(key):
		free_slot(_slots[key])
		_slots.erase(key)
	_slots[key] = slot
	while limit > 0 and _slots.size() > limit:
		var oldest: String = _slots.keys()[0]
		var gone: Dictionary = _slots[oldest]  # perf-lint: allow untyped_array a slot is a mixed record (roots, nodes, state); callers build it untyped
		_slots.erase(oldest)
		_drop(oldest, gone)


## Hands everything kept to [member spill] (frees it without one): for a view that is going away.
func spill_all() -> void:
	for key: String in _slots.keys():
		_drop(key, _slots[key])
	_slots.clear()


func _drop(key: String, slot: Dictionary) -> void:  # perf-lint: allow untyped_array a slot is a mixed record; callers build it untyped
	if spill_evicted and spill != null and spill != self and not key.is_empty() and not closing:
		spill.call(&"put", key, slot)
	else:
		free_slot(slot)


## True once the root window has left at quit: the shared store has been emptied and nothing spills into it after.
static var closing := false
static var _exit_hooked := false


## Empties [param store] when [param tree]'s root leaves at quit, so builds kept outside the tree are not leaked at exit;
## views freed after that free their own. Hooked once per process; the lambda is static, so no view's lifetime ends it.
static func free_at_exit(tree: SceneTree, store: RefCounted) -> void:
	if _exit_hooked or tree == null or tree.root == null:
		return
	_exit_hooked = true
	tree.root.tree_exiting.connect(func() -> void:
		closing = true
		store.call(&"clear"), CONNECT_ONE_SHOT)


## Frees everything kept.
func clear() -> void:
	for key: String in _slots.keys():
		free_slot(_slots[key])
	_slots.clear()


## Frees the nodes of [param slot] (all of them are outside the tree).
static func free_slot(slot: Dictionary) -> void:
	for node: Variant in slot.get("roots", []):
		if is_instance_valid(node) and not (node as Node).is_inside_tree():
			(node as Node).free()


## What a fresh build looks like, to put right after a reuse: every Node3D's visibility and transform under [param roots].
static func snapshot(roots: Array) -> Dictionary:
	var out := {}
	var stack: Array = roots.duplicate()
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node == null or not is_instance_valid(node):
			continue
		stack.append_array(node.get_children())
		if node is Node3D:
			out[node] = [(node as Node3D).visible, (node as Node3D).transform]
	return out


static func restore(shape: Dictionary) -> void:
	for node: Variant in shape:
		if is_instance_valid(node):
			(node as Node3D).visible = shape[node][0]
			(node as Node3D).transform = shape[node][1]


## A string of an object's script variables, for a key: two objects that would build the same weapon give the same string.
static func describe_object(obj: Object) -> String:
	if obj == null:
		return "null"
	var parts := PackedStringArray()
	for prop in obj.get_property_list():
		if int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			parts.append("%s=%s" % [prop["name"], str(obj.get(prop["name"]))])
	return ";".join(parts)
