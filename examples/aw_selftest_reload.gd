extends RefCounted

## The reload checks of aw_selftest.gd, split out for file size: the cue plans and the magazine, bolt and pump motion.
## Reports through the suite's `_begin`, `_check` and `_end`.

const ReloadSequence := preload("../addons/fc_weapons/view/aw_reload_sequence.gd")
const ReloadCues := preload("../addons/fc_weapons/view/aw_reload_cues.gd")

var suite: Node


func _init(host: Node) -> void:
	suite = host


## Every gun's reload plays its handling sounds off the animation's own phases: each cue sits inside the phase that
## makes it, they run in order, and a reload that ticks through fires each exactly once, at most one tick late.
func cues() -> void:
	suite._begin("reload sounds follow the reload animation")
	var rows := AwWeaponArt.weapon_rows("")
	var planned := 0
	var unplanned: Array[StringName] = []
	var off_phase: Array[String] = []
	var unsorted: Array[StringName] = []
	var late: Array[String] = []
	var named: Array[StringName] = []
	var empty_drop := 0
	var empty_mags := 0
	for role: StringName in rows:
		var row: Dictionary = rows[role]
		if row["motion"] != "gun":
			continue
		var art := AwWeaponVisual.make(role)
		AwArtDress.apply(art, row)
		var style := ReloadSequence.style_of(art)
		if style == &"generic":
			continue
		for left in [30, 0]:
			var seq := ReloadSequence.new()
			var anchors := ReloadSequence.anchors_for(Vector3.ZERO, Vector3(0, 0, -0.3), Vector3(0, 0, -0.6), null, art.reload.get("anchors", {}), Transform3D.IDENTITY)
			seq.compose(art, anchors, 30, left, 0.0)
			var plan := ReloadCues.plan(seq)
			if plan.is_empty():
				# A tube with nothing to pump (a reload that only pushes shells in) has no handling sound of its own.
				if not (style == &"tube" and left > 0):
					unplanned.append(role)
				continue
			planned += 1
			if left == 30 and "--plans" in OS.get_cmdline_user_args():
				print("PLAN ", JSON.stringify({"role": role, "style": style, "plan": plan.map(func(c: Dictionary) -> Dictionary: return {"t": snappedf(float(c.t), 0.001), "cue": c.cue, "db": c.db})}))
			var last := -1.0
			for c: Dictionary in plan:
				var ph := {}
				for p: Dictionary in seq.phases:
					if p.name == c.phase:
						ph = p
				if ph.is_empty() or float(c.t) < float(ph.t0) - 0.0001 or float(c.t) > float(ph.t1) + 0.0001:
					off_phase.append("%s/%s" % [role, c.cue])
				if float(c.t) < last or float(c.t) < 0.0 or float(c.t) > 1.0:
					unsorted.append(role)
				last = float(c.t)
				if not named.has(c.cue):
					named.append(c.cue)
			if left == 0 and (style == &"magazine" or style == &"pistol"):
				empty_mags += 1
				if plan.any(func(c: Dictionary) -> bool: return c.cue == &"mag_drop"):
					empty_drop += 1
			# Tick through a 90-tick reload: each cue fires once, on the first tick at or after its moment.
			var ticks := 90
			var next := 0
			var fired := 0
			for k in range(1, ticks):
				var step := ReloadCues.due(plan, next, float(k) / float(ticks))
				next = int(step.next)
				for c: Dictionary in step.due:
					fired += 1
					if float(k) / float(ticks) - float(c.t) >= 1.0 / float(ticks):
						late.append("%s/%s" % [role, c.cue])
			if fired != plan.filter(func(c: Dictionary) -> bool: return float(c.t) < float(ticks - 1) / float(ticks)).size():
				late.append("%s count %d" % [role, fired])
	suite._check("%d reloads (full and empty) of every non-generic gun have a cue plan (%s)" % [planned, str(unplanned)], planned > 0 and unplanned.is_empty())
	suite._check("every cue lies inside the phase that makes it (%s)" % str(off_phase.slice(0, 5)), off_phase.is_empty())
	suite._check("cues run in order inside 0..1 (%s)" % str(unsorted), unsorted.is_empty())
	suite._check("ticking a reload fires each cue once, at most one tick late (%s)" % str(late.slice(0, 5)), late.is_empty())
	var have := 0
	for cue in ReloadCues.all_cues():
		if GSWeaponSound.count(StringName("cue_%s" % cue)) > 0:
			have += 1
	suite._check("an empty magazine's reload drops it (%d of %d); stock has %d of %d cues (0 when gs-audio is not linked)" % [empty_drop, empty_mags, have, ReloadCues.all_cues().size()],
		empty_drop == empty_mags and (have == 0 or have == ReloadCues.all_cues().size()))
	suite._end()


## A magazine reload drops the old magazine and works the action on every reload by default (`cl_vm_reload_drop`,
## `cl_vm_reload_charge`, both 1), and only on an empty one with both 0; the new magazine ends exactly in its well, unturned,
## and the old and the new are never in sight together.
func drop_charge() -> void:
	suite._begin("magazine reloads drop the old magazine, seat the new one and work the action")
	var rows := AwWeaponArt.weapon_rows("")
	var wrong_default: Array[String] = []
	var wrong_off: Array[String] = []
	var off_well: Array[String] = []
	var both: Array[String] = []
	var rocked: Array[String] = []
	var mags := 0
	for role: StringName in rows:
		if rows[role]["motion"] != "gun":
			continue
		var art := AwWeaponVisual.make(role)
		AwArtDress.apply(art, rows[role])
		var style := ReloadSequence.style_of(art)
		if style != &"magazine" and style != &"pistol":
			continue
		mags += 1
		var anchors := ReloadSequence.anchors_for(Vector3.ZERO, Vector3(0, 0, -0.3), Vector3(0, 0, -0.6), null, art.reload.get("anchors", {}), Transform3D.IDENTITY)
		var action := &"slide_back" if style == &"pistol" else &"charge_back"
		for always: bool in [true, false]:
			for left: int in [30, 0]:
				var seq := ReloadSequence.new()
				seq.drop_always = always
				seq.charge_always = always
				seq.compose(art, anchors, 30, left, 0.0)
				var names: Array = seq.describe().phases
				var want := always or left == 0
				var dropped := names.has("drop") and ReloadCues.plan(seq).any(func(c: Dictionary) -> bool: return c.cue == &"mag_drop")
				var charged := names.has(String(action))
				var thrown := seq.props.any(func(p: Dictionary) -> bool: return p.part == &"round")
				if dropped != want or charged != want or thrown != (want and left > 0):
					(wrong_default if always else wrong_off).append("%s/%d" % [role, left])
				var seat_end := 0.0
				for p: Dictionary in seq.phases:
					if p.name == &"seat":
						seat_end = float(p.t1)
				# The ejected round (a full reload) comes first among the props: the magazines are the own ones, old then new.
				var end: Dictionary = seq.props_at(seat_end - 0.0005).filter(func(e: Dictionary) -> bool: return e.own)[1]
				if not end.shown or (end.at as Vector3).distance_to(anchors[&"well"]) > 0.004 or (end.turn as Vector3).length() > 0.5:
					off_well.append("%s/%d %s" % [role, left, str(end.at)])
				for k in 400:
					var shown := 0
					for e: Dictionary in seq.props_at(float(k) / 400.0):
						shown += 1 if e.own and e.shown else 0
					if shown > 1:
						both.append("%s/%d at %.3f" % [role, left, float(k) / 400.0])
						break
				if always and left == 30 and float(art.reload.get("rock", 0.0)) > 0.0:
					var out_end := 0.0
					for p: Dictionary in seq.phases:
						if p.name == &"mag_out":
							out_end = float(p.t1)
					var turn: Vector3 = seq.props_at(out_end - 0.0005).filter(func(e: Dictionary) -> bool: return e.own)[0].turn
					if absf(turn.x - float(art.reload.rock)) > 1.0:
						rocked.append("%s %.1f" % [role, turn.x])
	suite._check("%d magazine weapons: by default every reload drops the magazine (mag_drop cue) and works the action, a full one throwing its round (%s)" % [mags, str(wrong_default.slice(0, 4))], mags > 0 and wrong_default.is_empty())
	suite._check("with both off only an empty reload drops and works the action (%s)" % str(wrong_off.slice(0, 4)), wrong_off.is_empty())
	suite._check("the new magazine ends seated in its well, unturned (%s)" % str(off_well.slice(0, 3)), off_well.is_empty())
	suite._check("the old and the new magazine are never in sight together, and a rocking magazine leaves the well rocked (%s %s)" % [str(both.slice(0, 3)), str(rocked)], both.is_empty() and rocked.is_empty())
	var feel := AwViewFeel.new()
	var defaults := feel.reload_drop == 1.0 and feel.reload_charge == 1.0
	var set_ok := feel.set_cvar(AwViewFeel.CVAR_RELOAD_DROP, "0") and feel.set_cvar(AwViewFeel.CVAR_RELOAD_CHARGE, "0")
	suite._check("cl_vm_reload_drop and cl_vm_reload_charge default to 1 and set to 0 (%s %s)" % [defaults, set_ok],
		defaults and set_ok and feel.reload_drop == 0.0 and feel.reload_charge == 0.0)
	_reload_bolt(rows)
	_shot_bolt(rows)
	suite._end()


## The rifle's own bolt node rides back with the charging hand and is home again before the reload ends.
func _reload_bolt(rows: Dictionary) -> void:
	var rifle := AwWeaponVisual.make(&"rifle")
	AwArtDress.apply(rifle, rows[&"rifle"])
	var bolt_seq := ReloadSequence.new()
	bolt_seq.compose(rifle, ReloadSequence.anchors_for(Vector3.ZERO, Vector3(0, 0, -0.3), Vector3(0, 0, -0.6), null, rifle.reload.get("anchors", {}), Transform3D.IDENTITY), 30, 30, 0.0)
	var peak := 0.0
	var start_back := bolt_seq.bolt_back(0.0)
	var end_back := bolt_seq.bolt_back(0.999)
	for k in 400:
		peak = maxf(peak, bolt_seq.bolt_back(float(k) / 400.0))
	var still := ReloadSequence.new()
	still.charge_always = false
	still.compose(rifle, ReloadSequence.anchors_for(Vector3.ZERO, Vector3(0, 0, -0.3), Vector3(0, 0, -0.6), null, rifle.reload.get("anchors", {}), Transform3D.IDENTITY), 30, 30, 0.0)
	var still_peak := 0.0
	for k in 400:
		still_peak = maxf(still_peak, still.bolt_back(float(k) / 400.0))
	var model := AwModelCache.instantiate(rifle.model_path) if ResourceLoader.exists(rifle.model_path) else null
	var has_bolt := model != null and model.find_child(String(rifle.bolt_node), true, false) != null and model.find_child(String(rifle.hide_during_reload), true, false) != null
	if model != null:
		model.free()
	suite._check("the rifle's bolt node (%s, %s) is drawn back with the charge and home at both ends (peak %.2f, start %.2f, end %.2f, uncharged %.2f)" % [rifle.bolt_node, has_bolt, peak, start_back, end_back, still_peak],
		has_bolt and rifle.bolt_travel > 0.0 and peak > 0.95 and start_back == 0.0 and end_back == 0.0 and still_peak == 0.0)


## The sniper cycles its bolt and the shotgun its pump after each shot: home at both ends, fully back between, the hand on the part
## through the stroke and off it at both ends, and only they do.
func _shot_bolt(rows: Dictionary) -> void:
	var sniper := AwWeaponVisual.make(&"sniper")
	AwArtDress.apply(sniper, rows[&"sniper"])
	var shotgun := AwWeaponVisual.make(&"shotgun")
	AwArtDress.apply(shotgun, rows[&"shotgun"])
	var rifle := AwWeaponVisual.make(&"rifle")
	AwArtDress.apply(rifle, rows[&"rifle"])
	var peak := 0.0
	for k in 201:
		peak = maxf(peak, AwViewModel.cycle_back(float(k) / 200.0))
	var ends := AwViewModel.cycle_back(0.0) == 0.0 and AwViewModel.cycle_back(1.0) == 0.0
	suite._check("the sniper's bolt cycles with a handle to reach and the rifle's does not (%s %.2f s, peak %.2f, ends home %s, handle %s, rifle %s)" % [sniper.cycle_style, sniper.cycle_time, peak, ends, sniper.cycle_at, rifle.cycle_style],
		sniper.cycle_style == &"bolt" and sniper.cycle_time > 0.0 and sniper.bolt_node != &"" and sniper.bolt_travel > 0.0 and sniper.cycle_at != Vector3.ZERO and peak > 0.99 and ends and rifle.cycle_style == &"")
	var reach := AwViewModel.cycle_reach(0.5, 0.3)
	suite._check("the shotgun's pump cycles after a shot and the hand is on it mid-stroke, off it at both ends (%s %.2f s, reach %.2f, before %.2f, after %.2f)" % [shotgun.cycle_style, shotgun.cycle_time, reach, AwViewModel.cycle_reach(-0.3, 0.3), AwViewModel.cycle_reach(1.0, 0.3)],
		shotgun.cycle_style == &"pump" and shotgun.cycle_time > 0.0 and shotgun.bolt_node != &"" and shotgun.bolt_travel > 0.0 and reach > 0.99 and AwViewModel.cycle_reach(-0.3, 0.3) == 0.0 and AwViewModel.cycle_reach(1.0, 0.3) == 0.0)
