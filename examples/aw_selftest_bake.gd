extends RefCounted

## The animation bake (tools/aw_anim_bake.gd): a bolt gun's sidecar has every clip with whole-frame tracks, a shot moves the bolt and kicks the
## view, a reload moves the magazine, the idle sway stays small, and the lens block carries the numbers the viewer needs. Reports through
## the suite's `_begin`, `_check` and `_end`.

const Bake := preload("res://tools/aw_anim_bake.gd")
const PER_FRAME := {"transform": 7, "position": 3, "visible": 1, "vec2": 2}

var suite: Node


func _init(host: Node) -> void:
	suite = host


func _range(clip: Dictionary, target: String) -> float:
	for t: Dictionary in clip.tracks:
		if t.target == target:
			var n: int = PER_FRAME[t.path]
			var v: Array = t.values
			var best := 0.0
			for i in n:
				var lo := 1e9
				var hi := -1e9
				for j in range(i, v.size(), n):
					lo = minf(lo, v[j])
					hi = maxf(hi, v[j])
				best = maxf(best, hi - lo)
			return best
	return -1.0


func _ok(passed: bool, label: String) -> void:
	suite._check(label, passed)


func run() -> void:
	suite._begin("a baked sidecar samples the real view model: every clip, whole frames, the parts that move")
	var defs := {}
	for d in AwWeaponPack.weapons({}, "", false):
		defs[d.id] = d
	var sc := Bake.new().bake(suite, &"sniper", defs[&"sniper"])
	var by := {}
	for c: Dictionary in sc.clips:
		by[c.name] = c
	_ok(sc.fps == 60 and by.has("fire") and by.has("bolt_cycle") and by.has("reload") and by.has("draw") and by.has("inspect") and by.has("ads") and by.has("idle"),
			"the sniper bakes fire, bolt_cycle, reload, draw, inspect, ads and idle at 60 fps")
	var whole := true
	for c: Dictionary in sc.clips:
		whole = whole and c.frames > 0 and absf(c.length - float(c.frames) / 60.0) < 0.002
		for t: Dictionary in c.tracks:
			whole = whole and t.values.size() == PER_FRAME[t.path] * c.frames
	_ok(whole, "every track holds exactly one value set per frame and each clip's length is its frames over 60")
	_ok(_range(by.fire, "bolt") > 0.05 and _range(by.fire, "view_punch") > 0.5 and _range(by.fire, "weapon") > 0.01,
			"a shot slides the bolt, kicks the view and moves the weapon")
	_ok(_range(by.reload, "magazine") > 0.1 and _range(by.reload, "hand.left") > 0.1, "a reload carries the magazine and the support hand")
	_ok(_range(by.idle, "weapon") < 0.02 and _range(by.idle, "weapon") > 0.0, "the idle sway is small but not still")
	_ok(sc.lens.reference_fov == GSViewLens.REFERENCE_FOV and sc.lens.max_pull_in == GSViewLens.MAX_PULL_IN, "the sidecar carries the game's lens constants")
	suite._end()
