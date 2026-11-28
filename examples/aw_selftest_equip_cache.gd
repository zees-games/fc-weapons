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
	var EquipCache := preload("../addons/fc_weapons/view/aw_equip_cache.gd")
	EquipCache.spill_evicted = false
	var limited := _rig(true, 1)
	limited.equip(a)
	var gone := limited.weapon_node()
	limited.equip(b)
	limited.equip(_art(&"pistol"))
	suite._check("past the limit the oldest kept weapon is freed (1 kept)", not is_instance_valid(gone) and limited.equip_cache_size() == 1)
	limited.queue_free()
	# Spilling (the default): the oldest goes to the shared store instead, and another view draws that very build.
	EquipCache.spill_evicted = true
	AwViewModel.prewarmed.clear()
	var spilling := _rig(true, 1)
	spilling.equip(a)
	var spilled := spilling.weapon_node()
	spilling.equip(b)
	spilling.equip(_art(&"pistol"))
	var other := _rig(true, 1)
	other.equip(a)
	suite._check("past the limit the oldest goes to the shared store and another view draws it (%d shared)" % AwViewModel.prewarmed.size(),
		is_instance_valid(spilled) and other.weapon_node() == spilled and spilled.is_inside_tree())
	spilling.queue_free()
	other.queue_free()
	AwViewModel.prewarmed.clear()


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
	AwViewModel.prewarmed.clear()
	view.free()
	suite._check("freeing the view model hands every weapon it kept to the shared store (%d)" % count,
		count > 0 and AwViewModel.prewarmed.size() == count and kept.all(func(n) -> bool: return is_instance_valid(n) and not n.is_inside_tree()))
	AwViewModel.prewarmed.clear()
	suite._check("and clearing the shared store frees them", kept.all(func(n) -> bool: return not is_instance_valid(n)))
	await _late_checks()
	_fitting_and_prewarm_checks()
	suite._end()


## A weapon equipped while its addon group is still being fetched is drawn once the group is mounted, in hand and on a body.
func _late_checks() -> void:
	var path := "res://assets/models/zz_late_group_probe.glb"
	var real: Variant = AwModelCache.scene(_art(&"rifle").model_path).value
	var art := _art(&"rifle")
	art.model_path = path
	ProjectSettings.set_setting(AwModelCache.LATE_PENDING, true)
	var hand := _rig(false)
	var world := AwWorldModel.new()
	suite.add_child(world)
	hand.equip(art)
	world.equip(art)
	suite._check("with the group on its way a missing model leaves the hand and the body empty", hand.weapon_node() == null and world._weapon == null)
	await suite.get_tree().process_frame
	suite._check("and they stay empty while it is still on its way", hand.weapon_node() == null and world._weapon == null)
	AwModelCache._scenes[path] = real
	ProjectSettings.set_setting(AwModelCache.LATE_PENDING, false)
	await suite.get_tree().process_frame
	await suite.get_tree().process_frame
	suite._check("once it is mounted the hand draws the weapon without a re-equip", hand.weapon_node() != null and hand.weapon_node().is_inside_tree())
	suite._check("and so does the body", world._weapon != null and world._weapon.is_inside_tree())
	AwModelCache._scenes.erase(path)
	hand.queue_free()
	world.queue_free()


## The rig tells the view its fitting on every switch: an empty one on a build that wears none refits nothing, and a prewarmed build is the one a real equip takes.
func _fitting_and_prewarm_checks() -> void:
	AwViewModel.prewarmed.clear()
	var view := _rig(true)
	var art := _art(&"rifle")
	view.equip(art)
	var weapon := view.weapon_node()
	view.set_fitting(GSWeaponFitting.new())
	suite._check("an empty fitting on a build that wears none keeps its weapon (no refit)", weapon != null and view.weapon_node() == weapon)
	var spare := _rig(true)
	spare.prewarm(art)
	suite._check("a prewarm leaves its finished build in the shared store (%d kept)" % AwViewModel.prewarmed.size(), AwViewModel.prewarmed.size() == 1 and spare.weapon_node() == null)
	var real := _rig(true)
	real.equip(art)
	suite._check("the first equip of that weapon takes the prewarmed build", AwViewModel.prewarmed.size() == 0 and real.weapon_node() != null)
	AwViewModel.prewarmed.clear()
	view.queue_free()
	spare.queue_free()
	real.queue_free()
