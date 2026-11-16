extends "aw_selftest_fx.gd"

## Sight, scope, near-plane and preview sections of the self-test; split out of aw_selftest.gd for file size.

## Guns whose model shows its own notch, aperture or post (the rest aim at their row's written aim).
const OWN_SIGHTED := 9


func _scope_hides_gun() -> void:
	_begin("scoped gun model hidden once the scope picture is up")
	var view := AwViewModel.new()
	view.scope_mode = AwViewModel.SCOPE_FULL
	view.show_arms = false
	add_child(view)
	var row: Dictionary = AwWeaponArt.weapon_rows("")[&"sniper"]
	var art := AwWeaponVisual.make(&"sniper")
	AwArtDress.apply(art, row)
	view.equip(art)
	view._process(0.02)
	_check("hip: gun drawn, no scope picture", view._animated.visible and not view.scope_picture_up())
	view.aim(true)
	var hid_early := false
	var shown_late := false
	for _i in 80:
		view._process(0.02)
		var up := view.scope_picture_up()
		if up and view._animated.visible:
			hid_early = true
		if not up and not view._animated.visible and not view.is_scoped():
			shown_late = true
	_check("gun never drawn while the scope picture is half up", not hid_early)
	_check("gun not hidden before the picture is half up", not shown_late)
	view.queue_free()
	_end()


## The scope body view (FC's cl_scope_body): the gun stays up and the lens is drawn into its ocular, which sits at the
## eye relief and is the lens circle's size on screen; off, or in the full-screen view, the gun hides as before.
func _scope_body() -> void:
	_begin("scope body: the gun stays up, the lens sits in its ocular")
	var camera := Camera3D.new()
	camera.fov = 75.0
	add_child(camera)
	var view := AwViewModel.new()
	view.show_arms = false
	view.scope_body = true
	camera.add_child(view)
	var art := AwWeaponVisual.make(&"sniper")
	AwArtDress.apply(art, AwWeaponArt.weapon_rows("")[&"sniper"])
	view.equip(art)
	view.aim(true)
	for _i in 80:
		view._process(0.02)
	_check("body: active on the sniper through the lens", view.scope_body_active() and view.is_scoped())
	_check("body: the gun is drawn at full aim", view._animated.visible)
	var points := view.scope_ocular_points()
	var eye_space: Vector3 = camera.global_transform.affine_inverse() * (points.get("centre", Vector3.ZERO) as Vector3)
	_check("body: the ocular is centred at the eye relief", Vector2(eye_space.x, eye_space.y).length() < 0.01 and absf(eye_space.z + view.scope_body_relief) < 0.01)
	var overlay := AwScopeOverlay.new()
	add_child(overlay)
	overlay.bind_camera(camera)
	overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
	overlay.size = get_viewport().get_visible_rect().size
	overlay.follow(view)
	var lens := overlay._body_lens()
	var want := minf(overlay.size.x, overlay.size.y) * 0.62 * 0.5
	_check("body: the ocular is the lens circle's size on screen", not lens.is_empty() and absf(float(lens.get("radius", 0.0)) / want - 1.0) < 0.05)
	_check("body: the lens sits on the ocular, not shifted by the drawn motion", overlay.motion == Vector2.ZERO and (lens.get("centre", Vector2.ZERO) as Vector2).distance_to(overlay.size * 0.5) < want * 0.1)
	view.scope_mode = AwViewModel.SCOPE_FULL
	view._process(0.02)
	_check("body: the full-screen view still hides the gun", not view.scope_body_active() and not view._animated.visible)
	view.scope_mode = AwViewModel.SCOPE_LENS
	view.scope_body = false
	view._process(0.02)
	overlay.follow(view)
	_check("body off: the flat lens as before", not view._animated.visible and overlay._body_lens().is_empty())
	overlay.queue_free()
	camera.queue_free()
	_end()


func _scope_modes() -> void:
	_begin("scope views: lens on screen, full screen, server pin, see-through on the move")
	var view := AwViewModel.new()
	view.show_arms = false
	add_child(view)
	var art := AwWeaponVisual.make(&"sniper")
	AwArtDress.apply(art, AwWeaponArt.weapon_rows("")[&"sniper"])
	view.equip(art)
	_check("the scope lens is the default view", view.scope_mode == AwViewModel.SCOPE_LENS)
	view.aim(true)
	for _i in 80:
		view.drive(Vector2.ZERO, 0.0, true)
		view._process(0.02)
	_check("lens: the camera keeps the hip field of view", is_equal_approx(view.view_fov_scale(), 1.0))
	_check("lens: the scope still zooms", view.aim_fov_scale() < 0.9)
	_check("lens: the gun is hidden so it does not cover the glass", not view._animated.visible)
	_check("standing, the picture is solid", view.scope_clear() < 0.01)
	view.drive(Vector2.ZERO, 6.0, true)
	view._process(0.02)
	_check("running, the picture goes part clear", view.scope_clear() > 0.4 and view.scope_clear() < 1.0)
	view.scope_walk_clear = 0.0
	_check("a clear of 0 keeps it solid at a run", view.scope_clear() == 0.0)
	view.scope_mode = AwViewModel.SCOPE_FULL
	view._process(0.02)
	_check("full: the camera takes the whole zoom", is_equal_approx(view.view_fov_scale(), view.aim_fov_scale()))
	_check("full: the gun is hidden behind the scope", not view._animated.visible)

	var rules := AwAdsRules.new()
	_check("no server rule: the client chooses 2", rules.resolve_scope_mode(&"sniper", 2) == 2)
	_check("no server rule: the client chooses 1", rules.resolve_scope_mode(&"sniper", 1) == 1)
	_check("a wild client value is clamped", rules.resolve_scope_mode(&"sniper", 9) == 2)
	var _ok := rules.set_value(&"", "scope_mode", 2)
	_check("server pins the full-screen scope", rules.resolve_scope_mode(&"sniper", 1) == 2)
	var client := AwAdsRules.new()
	_check("the pin travels on the wire", client.adopt_wire(rules.to_wire()) and client.resolve_scope_mode(&"sniper", 1) == 2)
	view.ads_rules = rules
	_check("the view model applies the server's pin", view.resolve_scope_mode(1) == 2)

	var overlay := AwScopeOverlay.new()
	add_child(overlay)
	overlay.fraction = 1.0
	_check("the overlay is headless-safe in lens mode", not overlay.lens_active() and overlay.mode == 1)
	overlay.follow(view)
	_check("the overlay takes mode and clear from the view", overlay.mode == AwViewModel.SCOPE_FULL and overlay.clear == 0.0)
	_check("the sniper row brings its own lens size", is_equal_approx(overlay.lens_circle, float(art.scope_style.get("lens_circle", -1.0))))
	var share := 0.62
	var lens_fov := 75.0 * AwScopeOverlay.lens_fov_share(75.0, 0.3, share)
	_check("the lens magnifies by the zoom over the hip view", absf(tan(deg_to_rad(lens_fov) * 0.5) / (tan(deg_to_rad(37.5)) * share) - 0.3) < 0.001)
	var camera := Camera3D.new()
	camera.fov = 75.0
	add_child(camera)
	overlay.bind_camera(camera)
	overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
	overlay.size = Vector2(1920.0, 1080.0)
	overlay.follow(view)
	_check("a bound lens narrows past the camera's zoom", overlay.lens_zoom < view.aim_fov_scale() * 0.75)
	var plain := AwWeaponVisual.make(&"rifle")
	AwArtDress.apply(plain, AwWeaponArt.weapon_rows("")[&"rifle"])
	view.equip(plain)
	overlay.follow(view)
	_check("the next gun does not keep the last gun's lens", is_equal_approx(overlay.lens_circle, 0.46))
	_red_dot_parts()
	camera.queue_free()
	overlay.queue_free()
	view.queue_free()
	_end()


func _red_dot_parts() -> void:
	# A red dot's housing fills the hole its window cuts in the gun at every aim; its reticle and lens come with the aim.
	var sight := Node3D.new()
	var red: Node3D = AwViewModel.SightFit._red_dot({"axis": Vector3.FORWARD, "eye": Vector3.ZERO, "tan": tan(deg_to_rad(4.0))},
		0.2, AwAdsRules.new().red_dot_for(&"bullpup"))
	sight.add_child(red)
	var reticle := red.get_node(AwViewModel.SightFit.RETICLE_NAME) as Node3D
	var housing := red.get_node_or_null(AwViewModel.SightFit.HOUSING_NAME) as Node3D
	_check("a red dot is built with a housing", housing != null and housing.get_child_count() >= 3)
	AwViewModel.SightFit.fade(sight, 0.0)
	AwViewModel.SightFit.track(sight, Vector3.ZERO)
	_check("its housing shows at the hip", red.visible and housing.visible)
	_check("its reticle is hidden at the hip", not reticle.visible)
	AwViewModel.SightFit.fade(sight, 1.0)
	AwViewModel.SightFit.track(sight, Vector3.ZERO)
	_check("and shown at the eye", reticle.visible)
	sight.free()


func _own_sights() -> void:
	_begin("aimed down each model's own sight")
	var view := AwViewModel.new()
	view.show_arms = false
	add_child(view)
	var own := 0
	var built: Array[StringName] = []
	var blocked: Array[StringName] = []
	var worst := 0.0
	var sighted: AwWeaponVisual = null
	var means_before := AwViewArms._means.size()
	var rows := AwWeaponArt.weapon_rows("")
	for role: StringName in rows:
		var row: Dictionary = rows[role]
		if row["motion"] != "gun" or (row["view"] as Dictionary).get("scoped", false):
			continue
		var art := AwWeaponVisual.make(role)
		AwArtDress.apply(art, row)
		view.equip(art)
		view.aim(true)
		for _i in 40:
			view._process(0.02)
		if view.find_child("Sight", true, false) != null and not (row["view"] as Dictionary).get("iron", false):
			built.append(role)
		_aim_clear(view, role, blocked)
		var points := view.sight_points()
		if points.is_empty():
			continue
		own += 1
		sighted = art
		for p: Vector3 in [points.rear, points.front]:
			worst = maxf(worst, Vector2(p.x, p.y).length())
	_check("an armless view still leaves the guns' texture means cached for the first armed equip",
		AwViewArms._means.size() > means_before)
	_check_sight_cache(view, sighted)
	view.queue_free()
	_check("no gun has a sight built over its own (%s)" % str(built), built.is_empty())
	_check("%d guns aim down a notch, aperture or post of their own" % own, own >= OWN_SIGHTED)
	_check("each own sight line runs through the screen's centre (worst %.4f m)" % worst, worst < 0.002)
	_check("no gun has any of its model inside the see-through cone round the aim line (%s)" % str(blocked), blocked.is_empty())
	_check_stepped_prewarm()
	_end()


## A gun's sight line measured once is reused: the cached fit puts the sight where a fresh measurement does.
func _check_sight_cache(view: AwViewModel, art: AwWeaponVisual) -> void:
	if art == null:
		_check("a gun with its own sight to fit from the cache", false)
		return
	view.equip(art)
	var cached := str(view.sight_points())
	AwViewModel.SightFit.line_cache = false
	view.equip(art)
	var measured := str(view.sight_points())
	AwViewModel.SightFit.line_cache = true
	_check("a gun's sight line from the cache matches a fresh measurement",
		not AwViewModel.SightFit._lines.is_empty() and cached == measured)


## A weapon prewarmed a stage at a time ends dropped again, in as many calls as it has stages.
func _check_stepped_prewarm() -> void:
	var view := AwViewModel.new()
	view.show_arms = false
	add_child(view)
	var rows := AwWeaponArt.weapon_rows("")
	var role: StringName = &""
	for r: StringName in rows:
		if rows[r]["motion"] == "gun":
			role = r
			break
	var art := AwWeaponVisual.make(role)
	AwArtDress.apply(art, rows[role])
	var spans: Dictionary = AwViewModel.HandReach._span_cache
	for key: String in spans.keys():
		if key.begins_with("%s|" % art.id):
			spans.erase(key)
	var before := spans.size()
	var ready := [0]
	view.model_ready.connect(func(_id: StringName, _node: Node3D) -> void: ready[0] += 1)
	var steps := 0
	var parts_cold := not AwViewModel._parts_warmed
	var part_steps := AwViewModel.WARM_KINDS.size() + AwViewModel.ReloadParts.part_names().size() if parts_cold else 0
	var began := view.prewarm_begin(art)
	var weapon_loaded := view.weapon_node() != null
	while began and view.prewarm_step():
		steps += 1
	view.queue_free()
	_check("stepped prewarm loads the model, then runs %d stages and drops the weapon" % AwViewModel.EQUIP_STAGES, began and weapon_loaded and steps == AwViewModel.EQUIP_STAGES - 1 + part_steps and view.weapon_node() == null)
	_check("stepped prewarm leaves every reload part warmed (one a step when cold: %d)" % part_steps, AwViewModel._parts_warmed and view._parts_left.is_empty() and view._kinds_held.is_empty())
	var warmed := spans.size()
	var hot := AwViewModel.new()
	hot.show_arms = false
	add_child(hot)
	var _r := hot.equip(art)
	hot.queue_free()
	_check("stepped prewarm warms what equip reads, as prewarm does (model_ready %d, hand spans %d -> %d, equip adds %d)" % [ready[0], before, warmed, spans.size() - warmed], ready[0] == 1 and warmed > before and spans.size() == warmed)


## Rays from the aimed eye inside the sight cone, as far as the front post, hit nothing of the gun.
func _aim_clear(view: AwViewModel, role: StringName, blocked: Array[StringName]) -> void:
	var roots: Array = [view._weapon]
	var cone: Dictionary = AwViewModel.SightFit.cone_for(view._art, view.ads_rules, roots, view._holder, view._aim_target(), view._sight_line)
	if cone.is_empty() or AwViewModel.SightFit.Cut.occluders(view._weapon, view._holder, cone) > 0:
		blocked.append(role)


## Looking steeply down at a flat floor, no part of the drawn gun may be seen going through it: its lowest vertex stays above the floor plane, or the wall-free pass that draws it over the world is on.
## The lens draws the gun larger and farther from the eye than the wall probe assumes, so a barrel can be through a floor the probe never reaches.
func _floor_clip() -> void:
	_begin("the gun at the floor when looking down")
	var eye_height := 1.6
	var camera := Camera3D.new()
	camera.fov = 100.0
	add_child(camera)
	camera.current = true
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 0.4, 60.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -eye_height - 0.2, 0.0)
	add_child(floor_body)
	var view := AwViewModel.new()
	view.show_arms = false
	# The player's lens: a narrower field of view for the hands than for the world makes the gun larger and flatter.
	view.hands_fov = 55.0
	camera.add_child(view)
	var art := AwWeaponVisual.make(&"rifle")
	AwArtDress.apply(art, AwWeaponArt.weapon_rows("")[&"rifle"])
	view.equip(art)
	for _i in 3:
		await get_tree().physics_frame
	var floor_y := -eye_height
	for pitch: float in [0.0, -45.0, -70.0, -89.0]:
		camera.rotation_degrees = Vector3(pitch, 0.0, 0.0)
		for _i in 60:
			await get_tree().physics_frame
			view.advance(0.02)
		var lowest := INF
		for mesh in AwViewModel.HandReach.meshes(view._animated):
			if mesh.mesh == null or not mesh.is_visible_in_tree():
				continue
			for surface in mesh.mesh.get_surface_count():
				var vertices: Variant = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				if vertices == null:
					continue
				for v: Vector3 in vertices:
					lowest = minf(lowest, (mesh.global_transform * v).y)
		var covered: bool = view._overlay != null and view._overlay.is_active()
		if pitch < -40.0:
			_check("pitch %d: the gun's lowest vertex is %.2f m from the floor plane, or the wall-free pass draws it (pass %s)" % [pitch, lowest - floor_y, covered], lowest >= floor_y or covered)
		else:
			_check("pitch %d: looking level the gun is not pulled back or tipped (wall %.3f)" % [pitch, view.wall_amount()], view.wall_amount() < 0.05)
			# Standing in the open the drawn gun is clear of the floor, so the extra pass must stay off: it costs a frame's view layer.
			_check("pitch %d: standing in the open the wall-free pass stays off (lowest vertex %.2f m above the floor)" % [pitch, lowest - floor_y],
				view._overlay != null and not view._overlay.is_active() and not view._drawn_gun_touches_world() and lowest >= floor_y)
	var space := view.get_world_3d().direct_space_state
	_check("the sphere before the drawn-gun rays misses a floor out of reach", not view._world_near(space, camera.global_position, eye_height * 0.5))
	_check("and finds it within reach", view._world_near(space, camera.global_position, eye_height + 0.1))
	await _overlay_follows_view(view, camera)
	view.queue_free()
	await _floor_clip_web(camera)
	camera.queue_free()
	floor_body.queue_free()
	_end()


## The web half of [method _floor_clip]: no wall-free pass there, so a stencil copy of each material draws the part the floor hides instead.
func _floor_clip_web(camera: Camera3D) -> void:
	var web := AwViewModel.new()
	web.show_arms = false
	web.hands_fov = 55.0
	camera.add_child(web)
	if web._overlay != null:
		web._overlay.free()
		web._overlay = null
	web._reveal = true
	var web_art := AwWeaponVisual.make(&"rifle")
	AwArtDress.apply(web_art, AwWeaponArt.weapon_rows("")[&"rifle"])
	web.equip(web_art)
	var revealed := {}
	for pitch: float in [-70.0, 0.0]:
		camera.rotation_degrees = Vector3(pitch, 0.0, 0.0)
		for _i in 60:
			await get_tree().physics_frame
			web.advance(0.02)
		var passes := 0
		var surfaces := 0
		for mesh in AwViewModel.HandReach.meshes(web._animated):
			for surface in (mesh.mesh.get_surface_count() if mesh.mesh != null else 0):
				var material := mesh.get_surface_override_material(surface) as BaseMaterial3D
				surfaces += 1
				if material != null and material.next_pass is BaseMaterial3D and (material.next_pass as BaseMaterial3D).no_depth_test \
						and material.stencil_flags == BaseMaterial3D.STENCIL_FLAG_WRITE:
					passes += 1
		revealed[pitch] = [passes, surfaces]
	_check("web, looking down: every gun surface carries the hidden-part pass (%d of %d)" % revealed[-70.0], revealed[-70.0][1] > 0 and revealed[-70.0][0] == revealed[-70.0][1])
	_check("web, looking level: the pass is off, so it cannot draw the gun over the hands (%d on)" % revealed[0.0][0], revealed[0.0][0] == 0)
	_check("the pass's copies are prepared under the loading cover", AwViewModel._reveal_passes.values().all(func(m: Material) -> bool: return m in AwViewModel.prepared_materials()))
	web.queue_free()


## The wall-free pass's layer and camera are not hidden or stopped with the view model, and its camera shares the world: left on
## by a view model that is hidden, stopped, parked away from its camera or reset, it drew the shown gun small from where it
## last stood (Fatal Contact: a dark copy of the player's gun in the world per parked killcam hand, four in the owner's video).
func _overlay_follows_view(view: AwViewModel, camera: Camera3D) -> void:
	var overlay := view._overlay
	if overlay == null:
		_check("the view model built its wall-free pass", false)
		return
	camera.rotation_degrees = Vector3(-89.0, 0.0, 0.0)
	overlay.update(true, camera)
	_check("the pass is on while the gun is in the floor", overlay.is_active())
	view.visible = false
	_check("hiding the view model turns the pass off", not overlay.is_active())
	view.visible = true
	overlay.update(true, camera)
	view.process_mode = Node.PROCESS_MODE_DISABLED
	_check("stopping the view model turns the pass off", not overlay.is_active())
	view.process_mode = Node.PROCESS_MODE_INHERIT
	overlay.update(true, camera)
	view.on_reset()
	_check("a reset turns the pass off", not overlay.is_active())
	# Parked as a killcam keeps its spare hands: under a layer, not a camera, then back under a camera, many times.
	var park := CanvasLayer.new()
	add_child(park)
	var shown := 0
	for _i in 8:
		overlay.update(true, camera)
		view.reparent(park, false)
		view.advance(0.02)
		shown += 1 if overlay.is_active() else 0
		view.reparent(camera, false)
	_check("parked away from a camera, eight times over, the pass is never left on (%d)" % shown, shown == 0)
	park.queue_free()
	var other := Camera3D.new()
	add_child(other)
	other.current = true
	overlay.update(true, camera)
	_check("the pass never draws from a camera that is not on screen", not overlay.is_active())
	other.queue_free()
	camera.current = true
	await get_tree().process_frame


## A wall shoved against the muzzle retracts the gun toward the eye; no drawn mesh may then be cut by the camera near plane inside the view
## (that slices it open into flat faces), at the narrow and the wide field of view alike, and the clamp must not push the gun past its free pose.
func _near_plane_clip() -> void:
	_begin("the gun at the near plane against a wall")
	for fov: float in [75.0, 120.0]:
		var camera := Camera3D.new()
		camera.fov = fov
		add_child(camera)
		var view := AwViewModel.new()
		view.show_arms = false
		view.hands_fov = 55.0
		camera.add_child(view)
		var art := AwWeaponVisual.make(&"rifle")
		AwArtDress.apply(art, AwWeaponArt.weapon_rows("")[&"rifle"])
		view.equip(art)
		var wall := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(20.0, 20.0, 0.4)
		shape.shape = box
		wall.add_child(shape)
		add_child(wall)
		var worst := 0.0
		var clear := camera.near + AwViewModel.NEAR_CLEAR
		for gap: float in [1.2, 0.8, 0.5, 0.35, 0.25, 0.15]:
			wall.position = Vector3(0.0, 0.0, -gap - 0.2)
			for _i in 40:
				await get_tree().physics_frame
				view.advance(0.02)
			worst = maxf(worst, view.weapon_cut_depth(camera, clear))
		_check("fov %d: the near plane cuts no part of the gun inside the view (worst %.3f m)" % [fov, worst], worst < 0.001)
		wall.position = Vector3(0.0, 0.0, -50.0)
		for _i in 80:
			await get_tree().physics_frame
			view.advance(0.02)
		_check("fov %d: free of the wall the gun is not pulled back (wall %.3f)" % [fov, view.wall_amount()], view.wall_amount() < 0.05)
		wall.queue_free()
		view.queue_free()
		camera.queue_free()
	var probe := AwViewModel.new()
	var rect := PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)])
	var inside: Array[Vector3] = []
	var outside: Array[Vector3] = []
	for i in 8:
		inside.append(Vector3(0.5 if i & 4 else -0.5, 0.5 if i & 2 else -0.5, -0.1 if i & 1 else -1.0))
		outside.append(Vector3(5.5 if i & 4 else 4.5, 0.5 if i & 2 else -0.5, -0.1 if i & 1 else -1.0))
	_check("a box cutting the near plane inside the view counts", probe._section_meets(inside, 0.5, rect))
	_check("a box cutting the near plane outside the view does not", not probe._section_meets(outside, 0.5, rect))
	probe.free()
	_end()


## However the gun is equipped, swapped or reloaded, a view model owns exactly one set of arms (a second set drawn
## beside the first was reported on charge_rifle's reload; render_reload counts the drawn sets on the real client).
func _one_arm_set() -> void:
	_begin("a view model holds exactly one arm set")
	var camera := Camera3D.new()
	add_child(camera)
	var view := AwViewModel.new()
	camera.add_child(view)
	var bad: Array[String] = []
	for id: StringName in [&"charge_rifle", &"lmg", &"rifle", &"charge_rifle"]:
		var art := AwWeaponVisual.make(id)
		AwArtDress.apply(art, AwWeaponArt.weapon_rows("")[id])
		view.equip(art)
		var sets := view.find_children("*", "AwViewArms", true, false).size()
		if sets != 1:
			bad.append("%s after equip: %d" % [id, sets])
		for f in 12:
			view.on_reload((f + 0.5) / 12.0)
			await get_tree().physics_frame
			view.advance(0.02)
			sets = view.find_children("*", "AwViewArms", true, false).size()
			if sets != 1:
				bad.append("%s reload %d/12: %d" % [id, f, sets])
		view.on_reload(0.0)
	_check("one AwViewArms through equip, swaps and a reload sweep: %s" % ", ".join(bad), bad.is_empty())
	view.queue_free()
	camera.queue_free()
	_end()


## The highest vertex in the rear half of the gun's length, as tools/measure_sights.py finds the rear sight.
func _rear_top(n: Node, parent: Transform3D, muzzle: float, best_y: float, best: Vector3) -> Vector3:
	var t := parent * (n as Node3D).transform if n is Node3D else parent
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mesh := (n as MeshInstance3D).mesh
		for surf in mesh.get_surface_count():
			for v: Vector3 in mesh.surface_get_arrays(surf)[Mesh.ARRAY_VERTEX]:
				var w := t * v
				if w.z > -muzzle * 0.5 and w.y > best_y:
					best_y = w.y
					best = w
	for c in n.get_children():
		best = _rear_top(c, t, muzzle, best.y if best != Vector3.ZERO else -INF, best)
	return best


func _aabb(n: Node, parent: Transform3D) -> AABB:
	var t := parent
	var out := AABB()
	var first := true
	if n is Node3D:
		t = parent * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out = t * (n as MeshInstance3D).mesh.get_aabb()
		first = false
	for c in n.get_children():
		var b := _aabb(c, t)
		if b.size == Vector3.ZERO and b.position == Vector3.ZERO:
			continue
		out = b if first else out.merge(b)
		first = false
	return out


## The menu pictures: warm() draws them a frame each through one viewport (a viewport apiece headless, which has no pixels to read back), and a
## cached id costs nothing after, so pressing B does not make 27 MSAA viewports at once.
func _previews() -> void:
	_begin("weapon previews, warmed through one viewport")
	# Six of the pack's own models, registered as art the way a game does.
	var ids: Array = []
	var arts: Array[AwWeaponVisual] = []
	var rows := AwWeaponArt.weapon_rows("")
	for role: StringName in rows:
		if ids.size() < 6 and load(str((rows[role] as Dictionary)["model"])) is PackedScene:
			var art := AwWeaponVisual.new()
			art.id = StringName("preview_" + str(role))
			art.model_path = str((rows[role] as Dictionary)["model"])
			arts.append(art)
			ids.append(art.id)
	AwWeaponArtTable.add_source(&"aw_selftest_previews", func() -> Array[AwWeaponVisual]: return arts)
	var previews := AwWeaponPreview.new()
	add_child(previews)
	var done := [0]
	var _c := previews.warmed.connect(func() -> void: done[0] += 1)
	previews.warm(ids)
	_check("the warm-up is spread over frames, not done in the call (%d ids)" % ids.size(), previews.is_warming() and previews.cached_count() == 0)
	var frames := 0
	while done[0] == 0 and frames < 600:
		await get_tree().process_frame
		frames += 1
	var headless := DisplayServer.get_name() == "headless"
	_check("every id has a picture after %d frames" % frames, previews.cached_count() == ids.size() and not previews.is_warming())
	var drawn := true
	for id: Variant in ids:
		drawn = drawn and previews.texture(StringName(id)) != null
	_check("and each is a texture", drawn)
	_check("one viewport for all of them on a display, one each headless (%d made)" % previews.ports_made(), previews.ports_made() == (ids.size() if headless else 1))
	var made := previews.ports_made()
	previews.warm(ids)
	_check("warming the same ids again does nothing", done[0] == 2 and previews.ports_made() == made and not previews.is_warming())
	await get_tree().process_frame
	var again := 0
	for child in previews.get_children():
		again += 1 if child is SubViewport else 0
	_check("the shared viewport is gone once done (%d left)" % again, again == (ids.size() if headless else 0))
	previews.queue_free()
	AwWeaponArtTable.remove_source(&"aw_selftest_previews")
	_end()


## How far a frame of the pose moved a 1.2 m gun held at the grip: the largest of grip, muzzle and stock travel.
func _pose_step(a: Transform3D, b: Transform3D) -> float:
	var most := 0.0
	for at: Vector3 in [Vector3.ZERO, Vector3(0.0, 0.0, -0.8), Vector3(0.0, 0.0, 0.4)]:
		most = maxf(most, (a * at).distance_to(b * at))
	return most


## The holster has its own keys and spreads evenly over any frame count; inspect plays, returns to rest, and a shot cancels it smoothly.
func _holster_and_inspect() -> void:
	_begin("holster and inspect")
	var worst_share := 0.0
	var least_first := INF
	for frames: int in [3, 4, 6, 12, 24]:
		var down := AwWeaponPose.make()
		var steps: Array[float] = []
		var was := down.offset()
		for i in range(1, frames + 1):
			down.set_deploy(1.0 - float(i) / frames)
			var now := down.offset()
			steps.append(_pose_step(was, now))
			was = now
		var even := 0.0
		for v in steps:
			even += v
		even /= frames
		least_first = minf(least_first, steps[0] / even)
		worst_share = maxf(worst_share, steps.max() / even)
	_check("a holster's first frame leaves the hand (at least 0.4 of an even share, 3 to 24 frames): %.2f" % least_first,
		least_first >= 0.4)
	_check("no holster frame carries more than 1.9 even shares (3 to 24 frames): %.2f" % worst_share, worst_share <= 1.9)

	var turn := AwWeaponPose.make()
	turn.set_deploy(0.6)
	var before := turn.offset()
	turn.set_deploy(0.62)
	_check("a holster turned back keeps its curve (no jump)", _pose_step(before, turn.offset()) < 0.02)
	turn.set_deploy(0.0)
	turn.set_deploy(0.3)
	var drawing := turn.offset()
	var draw_only := AwWeaponPose.make()
	draw_only._holstering = false
	draw_only._deploy = 0.3
	_check("a draw from the bottom plays the draw's keys", _pose_step(drawing, draw_only.offset()) < 0.0001)

	var pose := AwWeaponPose.make()
	var rest := pose.offset()
	pose.set_aim(0.5)
	_check("inspect is refused while aiming", not pose.inspect())
	pose.set_aim(0.0)
	_check("inspect starts at rest", pose.inspect())
	var step := 1.0 / 60.0
	var biggest := 0.0
	var forward := -INF
	var last := pose.offset()
	var ticks := 0
	while pose.inspect_fraction() < 1.0 and ticks < 600:
		pose.advance(step, Vector2.ZERO, 0.0, true)
		var now := pose.offset()
		biggest = maxf(biggest, _pose_step(last, now))
		forward = maxf(forward, (now * Vector3(0.0, 0.0, 0.4)).z - 0.4)
		last = now
		ticks += 1
	_check("inspect ends in %.1f s and comes back to rest" % (ticks * step),
		ticks < 600 and _pose_step(rest, pose.offset()) < 0.0001)
	_check("inspect never moves 1.5 cm in a 60 Hz frame (%.4f m) nor brings the stock toward the eye (%.4f m)" % [
		biggest, forward], biggest < 0.015 and forward <= 0.002)

	pose.inspect()
	for i in 60:
		pose.advance(step, Vector2.ZERO, 0.0, true)
	var held := pose.offset()
	pose.punch(Vector2(0.0, 0.0))
	biggest = 0.0
	last = held
	for i in 13:
		pose.advance(step, Vector2.ZERO, 0.0, true)
		var now := pose.offset()
		biggest = maxf(biggest, _pose_step(last, now))
		last = now
	_check("a shot cancels inspect, easing back within 0.2 s (largest frame %.4f m)" % biggest,
		pose.inspect_fraction() >= 1.0 and _pose_step(rest, pose.offset()) < 0.0001 and biggest < 0.045)
	_end()


## The scope body's ring, lens and reticle sit on the screen's middle at any window size, aspect and canvas stretch: the
## camera's viewport is each size in turn and the overlay is drawn in a canvas scaled to it (a window under the base size
## draws a 1280-wide canvas scaled down), as the client does. The ring must be the lens circle's size and on the middle.
func _scope_align() -> void:
	_begin("scope body: ring centred and sized at every window size and canvas scale")
	var sizes := [Vector2i(1036, 648), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2366, 1022), Vector2i(1024, 768),
		Vector2i(1440, 900), Vector2i(854, 480), Vector2i(3440, 1440), Vector2i(640, 960)]
	var worst := 0.0
	var worst_size := 0.0
	for roleid in [&"sniper", &"marksman", &"charge_rifle"]:
		for win: Vector2i in sizes:
			# The canvas the overlay draws in: the window itself, or the base width (1280) scaled down to it.
			for canvas_scale in [1.0, maxf(1.0, 1280.0 / float(win.x)), 1.5]:
				var port := SubViewport.new()
				port.size = win
				add_child(port)
				var camera := Camera3D.new()
				camera.fov = 75.0
				port.add_child(camera)
				var view := AwViewModel.new()
				view.show_arms = false
				view.scope_body = true
				camera.add_child(view)
				var art := AwWeaponVisual.make(roleid)
				AwArtDress.apply(art, AwWeaponArt.weapon_rows("")[roleid])
				view.equip(art)
				view.aim(true)
				for _i in 80:
					view._process(0.02)
				var overlay := AwScopeOverlay.new()
				port.add_child(overlay)
				overlay.bind_camera(camera)
				overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
				overlay.size = Vector2(win) * canvas_scale
				overlay.follow(view)
				var lens := overlay._body_lens()
				var want := minf(overlay.size.x, overlay.size.y) * float(view.scope_style().get("lens_circle", 0.46)) * 0.5
				var centre_error := ((lens.get("centre", Vector2(-9999, -9999)) as Vector2) - overlay.size * 0.5).length() / overlay.size.y
				var radius_error := absf(float(lens.get("radius", 0.0)) / want - 1.0)
				if centre_error + radius_error > worst:
					worst = centre_error + radius_error
					worst_size = canvas_scale
				if lens.is_empty() or centre_error > 0.002 or radius_error > 0.03:
					_check("ring at %s %dx%d canvas x%.2f: off %.4f of the height, radius off %.3f" % [roleid, win.x, win.y, canvas_scale, centre_error, radius_error], false)
				port.queue_free()
	_check("ring centred and sized in every window and canvas (worst %.4f)" % worst, worst < 0.03)
	_end()
