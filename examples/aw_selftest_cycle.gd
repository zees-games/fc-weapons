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
	var strung := _string_of_shots(&"sniper", AwSpawnProvider.weapon_defs())
	suite._check("the sniper works its bolt after each of three shots at its own fire interval, and is ready again before the next (interval %.2f s, bolt travel per shot %s, idle at each next shot %s)" % [strung.interval, strung.travel, strung.idle],
		strung.interval >= 0.6 and strung.travel.size() == 3 and strung.travel.all(func(t: float) -> bool: return t > 0.06) and strung.idle.all(func(i: bool) -> bool: return i))
	var lift := _lift_through_cycle()
	suite._check("the sniper's handle turns up before the bolt slides, stays up through the stroke and turns down after it closes, square at rest (turn before slide %.1f deg, turn at rearmost %.1f deg, slide while turning %.3f m, rest %s)" % [lift.early, lift.mid, lift.slide_early, lift.square],
		lift.early > 50.0 and lift.mid > 55.0 and lift.slide_early < 0.005 and lift.square)
	var belt: Node3D = load("res://addons/fc_weapons/view/aw_belt_feed.gd").new()
	suite.add_child(belt)
	belt.build(Vector3.ZERO, Vector3(0.0, 0.0, -0.3))
	var flattest := INF
	for i in 120:
		belt.step()
		belt.advance(1.0 / 60.0)
		for r in belt.get_children():
			flattest = minf(flattest, absf((r as Node3D).transform.basis.determinant()))
	belt.queue_free()
	suite._check("a belt round shrinks out of sight without ever getting a flat transform (smallest determinant %s)" % flattest,
		flattest > 1e-12)
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


## Three shots in a row at the weapon's own fire interval (the rig's gate): per shot how far the bolt travelled, and whether the
## cycle had ended by the time the next shot is due.
func _string_of_shots(id: StringName, defs: Array) -> Dictionary:
	var def: GSWeaponDef = null
	for d: GSWeaponDef in defs:
		if String(d.id) == "aw_" + String(id):
			def = d
	var interval := float(def.use_interval_ticks) / float(AwWeaponPack.TICK_RATE) if def != null else 0.0
	var view := AwViewModel.new()
	view.show_arms = false
	view.fire_interval = interval
	suite.add_child(view)
	var art := AwWeaponVisual.make(id)
	AwArtDress.apply(art, AwWeaponArt.weapon_rows("")[id])
	view.equip(art)
	var part := view.weapon_node().find_child(String(art.bolt_node), true, false) as Node3D
	var home := part.position
	var travel: Array[float] = []
	var idle: Array[bool] = []
	var shot := GSWeaponOutcome.of(GSWeaponOutcome.KIND_SHOT)
	shot.used = true
	for n in 3:
		view.on_used(shot)
		var far := 0.0
		for i in int(ceil(interval * 60.0)):
			view.advance(1.0 / 60.0)
			far = maxf(far, part.position.distance_to(home))
		travel.append(far)
		idle.append(view._cycle_t < 0.0 and part.position.distance_to(home) < 0.000001)
	view.queue_free()
	return {"interval": interval, "travel": travel, "idle": idle}


## The sniper's bolt through one cycle: the turn it has when its handle is up but it has not slid yet, the turn at the rearmost
## point, how far it slid while the handle was still turning, and whether its basis is square again at the end.
func _lift_through_cycle() -> Dictionary:
	var view := AwViewModel.new()
	view.show_arms = false
	view.fire_interval = 1.4
	suite.add_child(view)
	var art := AwWeaponVisual.make(&"sniper")
	AwArtDress.apply(art, AwWeaponArt.weapon_rows("")[&"sniper"])
	view.equip(art)
	var bolt := view.weapon_node().find_child(String(art.bolt_node), true, false) as Node3D
	var rest := bolt.transform
	var shot := GSWeaponOutcome.of(GSWeaponOutcome.KIND_SHOT)
	shot.used = true
	view.on_used(shot)
	var out := {"early": 0.0, "mid": 0.0, "slide_early": 0.0, "square": false}
	var axis := art.bolt_axis.normalized()
	for i in 120:
		view.advance(1.0 / 60.0)
		var turn := rad_to_deg((rest.basis.inverse() * bolt.transform.basis).get_rotation_quaternion().get_angle())
		var f: float = (view._cycle_t - view._cycle_wait) / view._cycle_len if view._cycle_t >= 0.0 else -1.0
		var slide := (bolt.transform * rest.affine_inverse() * art.bolt_pivot - art.bolt_pivot).dot(axis)
		if f > 0.0 and f < AwViewModel.LIFT_SPLIT[0]:
			out.slide_early = maxf(out.slide_early, absf(slide))
		if f >= AwViewModel.LIFT_SPLIT[0] and f < AwViewModel.LIFT_SPLIT[0] + 0.03:
			out.early = maxf(out.early, turn)
		if absf(slide) > art.bolt_travel * 0.99:
			out.mid = maxf(out.mid, turn)
	out.square = bolt.transform.is_equal_approx(rest)
	view.queue_free()
	return out
