extends RefCounted

## A grenade's pin pulled out of its fuze in the view model: the pin, its legs, its eye and the pull ring (the
## models' own parts, by name) slide out along the pin's axis, ring first, twist off and are gone. Pulled when the
## cook starts (the button held, the way the pin comes out before a throw), put back when the next grenade comes up.
## By path, like aw_carry_class.gd: no global name for a helper.

const PARTS := [&"pin", &"pin_leg_a", &"pin_leg_b", &"pin_eye", &"pull_ring"]
## Seconds from the pull until the pin is gone from the hand.
const SECONDS := 0.2
## How far the pin travels out of the fuze (model metres, along +Z where the ring hangs) and how far it twists.
const TRAVEL := 0.06
const TWIST_DEGREES := 70.0

var _parts: Array[Node3D] = []
var _rest: Array[Transform3D] = []
var _t := -1.0


## Finds the pin's parts on [param model] (none on a grenade without a pin) and puts them back in.
func bind(model: Node3D) -> void:
	_parts.clear()
	_rest.clear()
	_t = -1.0
	if model == null:
		return
	for part: StringName in PARTS:
		var node := model.find_child(String(part), true, false) as Node3D
		if node == null:
			continue
		# A kept model may come back mid-pull: its rest is the one first seen on it.
		if not node.has_meta(&"pin_rest"):
			node.set_meta(&"pin_rest", node.transform)
		_parts.append(node)
		_rest.append(node.get_meta(&"pin_rest"))
	reset()


## Starts the pull, once per grenade.
func pull() -> void:
	if _t < 0.0 and not _parts.is_empty():
		_t = 0.0


func pulled() -> bool:
	return _t >= 0.0


## The pin back in the fuze: a fresh grenade.
func reset() -> void:
	_t = -1.0
	for i in _parts.size():
		if is_instance_valid(_parts[i]):
			_parts[i].transform = _rest[i]
			_parts[i].visible = true


## Shows [param model] (the grenade in hand) while [param in_hand], with a fresh pin each time it comes back, and
## moves the pin on by [param delta] seconds.
func follow(model: Node3D, in_hand: bool, delta: float) -> void:
	if model.visible != in_hand:
		model.visible = in_hand
		if in_hand:
			reset()
	advance(delta)


## Moves the pulled pin on by [param delta] seconds. Does nothing at rest or once it is gone.
func advance(delta: float) -> void:
	if _t < 0.0 or _t > SECONDS:
		return
	_t += delta
	var f := clampf(_t / SECONDS, 0.0, 1.0)
	var out := Vector3(0.0, 0.0, TRAVEL * f * f)
	var twist := Basis(Vector3.BACK, deg_to_rad(TWIST_DEGREES) * smoothstep(0.4, 1.0, f))
	for i in _parts.size():
		if not is_instance_valid(_parts[i]):
			continue
		var rest := _rest[i]
		_parts[i].transform = Transform3D(twist * rest.basis, rest.origin + out)
		_parts[i].visible = _t < SECONDS
