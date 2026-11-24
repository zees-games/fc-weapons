extends RefCounted

## A bolt or pump gun's cycle after a shot, run through a real view model: the part moves and comes home inside the fire
## interval, the support hand rides it, the sound cues fire once each, and a gun with no cycle does none of it. Split out of
## aw_selftest.gd for file size. Reports through the suite's `_begin`, `_check` and `_end`.

var suite: Node
var _cues: Array[StringName] = []


func _init(host: Node) -> void:
	suite = host


func _on_cue(cue: StringName, _db: float) -> void:
	_cues.append(cue)


## Fires once and steps the view 90 frames of 1/60 s: how far the part got from home, how far the hand got from the fore-end,
## and where the part and hand are at the end.
func _fire(id: StringName, interval: float) -> Dictionary:
	var view := AwViewModel.new()
	view.show_arms = false
	view.fire_interval = interval
	suite.add_child(view)
	var art := AwWeaponVisual.make(id)
	AwArtDress.apply(art, AwWeaponArt.weapon_rows("")[id])
	view.equip(art)
	_cues.clear()
	view.cycle_cue.connect(_on_cue)
	var part := view.weapon_node().find_child(String(art.bolt_node), true, false) as Node3D if art.bolt_node != &"" else null
	var home := part.position if part != null else Vector3.ZERO
	view.advance(1.0 / 60.0)
	var rest_hand: Vector3 = view._support_hand()
	var shot := GSWeaponOutcome.of(GSWeaponOutcome.KIND_SHOT)
	shot.used = true
	view.on_used(shot)
	var part_far := 0.0
	var hand_far := 0.0
	var done_at := -1.0
	for i in 90:
		view.advance(1.0 / 60.0)
		if part != null:
			part_far = maxf(part_far, part.position.distance_to(home))
		hand_far = maxf(hand_far, (view._support_hand() as Vector3).distance_to(rest_hand))
		if done_at < 0.0 and view._cycle_t < 0.0:
			done_at = float(i + 1) / 60.0
	var out := {"part": part_far, "hand": hand_far, "done": done_at, "cues": _cues.duplicate(),
		"home": part == null or part.position.distance_to(home) < 0.000001, "hand_home": (view._support_hand() as Vector3).distance_to(rest_hand) < 0.0001}
	view.queue_free()
	return out


func run() -> void:
	suite._begin("a bolt or pump gun works its part after a shot, with the support hand on it, inside the fire interval")
	var sniper := _fire(&"sniper", 1.0)
	suite._check("the sniper's bolt goes back and home, the hand rides it and returns, one sound each way, inside the fire interval (bolt %.3f m, hand %.3f m, done %.2f s, %s)" % [sniper.part, sniper.hand, sniper.done, sniper.cues],
		sniper.part > 0.06 and sniper.hand > 0.04 and sniper.home and sniper.hand_home and sniper.done > 0.0 and sniper.done <= 1.0 and sniper.cues == [&"bolt_back", &"bolt_fwd"])
	var shotgun := _fire(&"shotgun", 0.8)
	suite._check("the shotgun's pump goes back and home with the fore-end hand, one sound each way, inside 0.8 s (pump %.3f m, hand %.3f m, done %.2f s, %s)" % [shotgun.part, shotgun.hand, shotgun.done, shotgun.cues],
		shotgun.part > 0.04 and shotgun.hand > 0.03 and shotgun.home and shotgun.hand_home and shotgun.done > 0.0 and shotgun.done <= 0.8 and shotgun.cues == [&"pump_back", &"pump_fwd"])
	var rifle := _fire(&"rifle", 0.1)
	suite._check("a rifle works no part after a shot (part %.3f m, hand %.3f m, %s)" % [rifle.part, rifle.hand, rifle.cues],
		rifle.part == 0.0 and rifle.hand < 0.0001 and rifle.cues.is_empty())
	var scope := _aim_through_cycle()
	suite._check("a scoped gun leaves the scope while it cycles and looks through it again after (aim %.2f in, %.2f cycling, %.2f after)" % [scope[0], scope[1], scope[2]],
		scope[0] > 0.99 and scope[1] < 0.5 and scope[2] > 0.99)
	suite._end()


## The aim fraction of a held scoped gun just before a shot, during its bolt cycle and after it.
func _aim_through_cycle() -> Array:
	var view := AwViewModel.new()
	view.show_arms = false
	view.fire_interval = 1.0
	suite.add_child(view)
	var art := AwWeaponVisual.make(&"sniper")
	AwArtDress.apply(art, AwWeaponArt.weapon_rows("")[&"sniper"])
	view.equip(art)
	view.aim(true)
	for i in 90:
		view.advance(1.0 / 60.0)
	var before: float = view._aim_fraction
	var shot := GSWeaponOutcome.of(GSWeaponOutcome.KIND_SHOT)
	shot.used = true
	view.on_used(shot)
	var low := before
	for i in 40:
		view.advance(1.0 / 60.0)
		low = minf(low, view._aim_fraction)
	for i in 120:
		view.advance(1.0 / 60.0)
	var out := [before, low, view._aim_fraction]
	view.queue_free()
	return out
