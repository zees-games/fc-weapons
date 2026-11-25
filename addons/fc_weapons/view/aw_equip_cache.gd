extends RefCounted

## The built first-person models of weapons the view model has put away, kept by what built them, so switching back is not a rebuild. No `class_name`: AwViewModel preloads it.
## A slot is owned by exactly one place: taken out when drawn, put back when stowed. Stowed nodes sit outside the tree
## and are freed here: by the limit, by [method clear], or by the view model leaving.

## The most weapons kept; the oldest stowed goes first. 0 keeps every one.
var limit: int = 6

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
		free_slot(_slots[oldest])
		_slots.erase(oldest)


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
