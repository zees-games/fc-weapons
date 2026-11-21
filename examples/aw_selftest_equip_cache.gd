extends RefCounted

## The view model's kept builds (switching A -> B -> A puts the same model back, as it was built, and leaks nothing);
## split out of aw_selftest.gd for file size. Reports through the suite's `_begin`, `_check` and `_end`.

var suite: Node


func _init(host: Node) -> void:
	suite = host


func _art(id: StringName) -> AwWeaponVisual:
	var art := AwWeaponVisual.make(id)
	AwArtDress.apply(art, AwWeaponArt.weapon_rows("")[id])
	return art


func _rig(cache: bool, limit: int = 6) -> AwViewModel:
	var view := AwViewModel.new()
	view.show_arms = false
	view.cache_equips = cache
	view.equip_cache_limit = limit
	suite.add_child(view)
	return view


## What a player sees of the weapon in hand: its description, muzzle, sight points and every drawn mesh's visibility.
func _look(view: AwViewModel) -> Array:
	var shown: Array = []
	for mesh in view.weapon_node().find_children("*", "MeshInstance3D", true, false):
		shown.append([str(view.weapon_node().get_path_to(mesh)), (mesh as MeshInstance3D).visible])
	return [view.describe_lines(), view._muzzle, view.sight_points(), shown, view._grip_at, view._fore_at, view._grip_radius,
		view._attachments.size(), view._magazine != null, view._carved != null, view._rear_rings.size()]


## Nothing builds up over many switches; a limit frees the oldest.
func _limit_checks(view: AwViewModel, a: AwWeaponVisual, b: AwWeaponVisual) -> void:
	var ids: Array[StringName] = [&"rifle", &"sniper", &"pistol"]
	await suite.get_tree().process_frame
	var base := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	for i in 30:
		view.equip(_art(ids[i % ids.size()]))
	await suite.get_tree().process_frame
	var settled := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	for i in 30:
		view.equip(_art(ids[i % ids.size()]))
	await suite.get_tree().process_frame
	var after := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	suite._check("30 more switches among three weapons add no nodes (%d -> %d -> %d)" % [base, settled, after], after == settled and view.equip_cache_size() == 2)
	var limited := _rig(true, 1)
	limited.equip(a)
	var gone := limited.weapon_node()
	limited.equip(b)
	limited.equip(_art(&"pistol"))
	suite._check("past the limit the oldest kept weapon is freed (1 kept)", not is_instance_valid(gone) and limited.equip_cache_size() == 1)
	limited.queue_free()


func run() -> void:
	suite._begin("a view model keeps the weapons it put away: A, B, A is the same model, as built, with nothing leaked")
	var view := _rig(true)
	var a := _art(&"rifle")
	var b := _art(&"sniper")
	view.equip(a)
	var first := view.weapon_node()
	var fresh_look := _look(view)
	view.equip(b)
	var second := view.weapon_node()
	suite._check("the weapon put away is out of the tree and kept (%d kept)" % view.equip_cache_size(), not first.is_inside_tree() and view.equip_cache_size() == 1 and second.is_inside_tree())
	view.equip(a)
	suite._check("switching back draws the same instance, not a new one", view.weapon_node() == first and first.is_inside_tree() and view.equip_cache_size() == 1)
	suite._check("and it looks as a fresh build does (description, muzzle, sight, hands, meshes)", _look(view) == fresh_look)

	# A moved magazine and a hidden model are put right on the way out.
	var rig_plain := _rig(false)
	rig_plain.equip(_art(&"rifle"))
	var plain_look := _look(rig_plain)
	if view._magazine != null:
		view._magazine.visible = false
		view._magazine.position += Vector3(0.0, -0.3, 0.0)
	view.weapon_node().visible = false
	view.equip(b)
	view.equip(a)
	suite._check("a magazine moved and a model hidden are as a fresh build's after a switch away and back", view.weapon_node() == first and _look(view) == plain_look)

	# A fitting changes what is built, so a build kept without it is not put back under it.
	var fit := GSWeaponFitting.new()
	fit.weapon_id = &"aw_rifle"
	fit.fit(GSWeaponAttachment.MOUNT_OPTIC, &"red_dot")
	view.set_fitting(fit)
	view.equip(b)
	view.equip(a)
	var fitted_ref := _rig(false)
	fitted_ref.set_fitting(fit)
	fitted_ref.equip(_art(&"rifle"))
	suite._check("a weapon drawn under a new fitting is built for it, as a fresh rig builds it", _look(view) == _look(fitted_ref))
	view.set_fitting(null)
	rig_plain.queue_free()
	fitted_ref.queue_free()

	await _limit_checks(view, a, b)

	# Off, it builds each time, as before.
	var off := _rig(false)
	off.equip(a)
	var built := off.weapon_node()
	off.equip(b)
	off.equip(a)
	suite._check("with cache_equips off each equip builds a new model and keeps none", off.weapon_node() != built and off.equip_cache_size() == 0)
	off.queue_free()

	# Leaving frees the kept ones too.
	var kept: Array = []
	var count := 0
	for key: String in view._equip_cache._slots:
		kept.append(view._equip_cache._slots[key].weapon)
		count += 1
	view.free()
	suite._check("freeing the view model frees every weapon it kept (%d)" % count, count > 0 and kept.all(func(n) -> bool: return not is_instance_valid(n)))
	suite._end()
