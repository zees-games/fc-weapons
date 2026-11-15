extends "aw_selftest_grenades.gd"

## Shot effect, pooling, idle-sleep and asset-pack sections of the self-test; split out of aw_selftest.gd for file size.


## Every class but the beam (a flashless stream) has a flash, dressed guns throw cases (a held one too), and each gun but the launchers and energy guns has its own report.
func _fire_fx() -> void:
	_begin("muzzle flash, cases and per-gun reports")
	var no_flash: Array[String] = []
	for gun: StringName in AwWeaponPack.SOUND_CLASSES:
		if gun != &"beamer" and not AwShotFx.FLASH.has(AwWeaponPack.SOUND_CLASSES[gun]):
			no_flash.append(String(gun))
	_check("every gun's class has a flash row: %s" % ", ".join(no_flash), no_flash.is_empty())
	var rows := AwWeaponArt.weapon_rows("")
	var eject_bad: Array[String] = []
	for gun: StringName in AwWeaponPack.SOUND_CLASSES:
		var art := AwWeaponVisual.make(gun)
		AwArtDress.apply(art, rows[gun])
		if art.ejects != bool((rows[gun] as Dictionary).get("ejects", true)):
			eject_bad.append(String(gun))
	_check("dressing keeps each row's ejects (default on): %s" % ", ".join(eject_bad),
		eject_bad.is_empty() and rows[&"revolver"].get("ejects", true) == false)
	var silent: Array[String] = []
	var own := 0
	for gun: StringName in AwWeaponPack.SOUND_CLASSES:
		if AwShotLayers.has_gun_sound(gun):
			own += 1
		elif not gun in [&"launcher", &"quad_launcher", &"grenade_launcher", &"beamer", &"charge_rifle"]:
			silent.append(String(gun))
	_check("every gun but the launchers and energy guns has its own report: %s" % ", ".join(silent), silent.is_empty() and own > 0)
	_check("a host's prefix still finds the gun", AwShotLayers.gun_of(&"fc_burst_rifle") == &"burst_rifle"
		and AwShotLayers.gun_of(&"fc_rifle") == &"rifle" and AwShotLayers.gun_of(&"axe") == &"")
	var registered := own
	if AwShotLayers.available():
		var layers := AwShotLayers.new()
		add_child(layers)
		registered = 0
		if layers.setup(&"Master"):
			for gun: StringName in AwWeaponPack.SOUND_CLASSES:
				registered += 1 if layers.plays_gun(gun) else 0
		layers.free()
	_check("the layered player registers each gun's own shot (%d of %d)" % [registered, own], registered == own)
	var host_def := AwShotLayers.gun_shot(&"sniper")
	_check("a host's own shot player gets a gun's report under its id (aw_gun_sniper, attack layers)",
		AwShotLayers.gun_shot_id(&"fc_sniper") == &"aw_gun_sniper" and AwShotLayers.gun_shot_id(&"axe") == &""
		and AwShotLayers.gun_shot(&"axe") == null and (not AwShotLayers.available()
		or (host_def != null and host_def.get(&"id") == &"aw_gun_sniper" and not (host_def.get(&"attack") as PackedStringArray).is_empty())))
	var shells := []
	for gun: StringName in [&"sniper", &"revolver"]:
		var held := AwWorldModel.new()
		held.sounds = false
		held.effects = true
		add_child(held)
		var art := AwWeaponVisual.make(gun)
		AwArtDress.apply(art, rows[gun])
		held.equip(art)
		await get_tree().process_frame
		held.on_fired(Vector2(0.5, 0.1), AwWeaponNet.KIND_SHOT, true)
		shells.append(held._shot_fx().shell_count())
		held.free()
	_check("a held gun seen firing throws a case, a revolver none (%s)" % str(shells), shells == [1, 0])
	_end()


## 32 shooters (bots) each fire; counts the nodes the effects cost and the time per shot.
## The "BENCH" lines are the before/after record in the commit message.
func _shot_fx_pool() -> void:
	_begin("shot fx pool: 32 shooters, 100 shots")
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 0.4, 400.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -1.8, 0.0)
	add_child(floor_body)
	await get_tree().process_frame
	var base := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var holder := Node3D.new()
	add_child(holder)
	var fxs: Array[AwShotFx] = []
	for i in 32:
		var fx := AwShotFx.new()
		fx.name = "ShotFx%d" % i
		holder.add_child(fx)
		fxs.append(fx)
	for _i in 3:
		await get_tree().process_frame
	var built := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) - base
	var peak := built
	var spent := 0
	var voices_max := 0
	var lights_max := 0
	for s in 100:
		var i := s % 32
		var angle := float(i) / 32.0 * TAU
		var spot := Vector3(cos(angle), 0.0, sin(angle)) * (4.0 + float(i) * 2.0)
		var muzzle := Transform3D(Basis.looking_at(Vector3(0.0, -0.5, -1.0)), spot)
		var t0 := Time.get_ticks_usec()
		fxs[i].play_remote(AwWeaponNet.KIND_SHOT, muzzle, Vector3(0.0, -0.5, -1.0), &"rifle")
		spent += Time.get_ticks_usec() - t0
		if s % 4 == 3:
			await get_tree().process_frame
			peak = maxi(peak, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) - base)
	var in_flight := 0
	for fx in fxs:
		voices_max = maxi(voices_max, int(fx.describe()["voices"]))
		lights_max = maxi(lights_max, fx.lights_built())
		in_flight += fx.live_count()
	for _i in 90:
		await get_tree().process_frame
	var after := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) - base
	print("BENCH shotfx: 32 shooters build %d nodes; 100 shots peak %d, settled %d; %.4f ms/shot; max voices/shooter %d, max lights/shooter %d; effects alive after the burst %d" % [
		built, peak, after, float(spent) / 100.0 / 1000.0, voices_max, lights_max, in_flight])
	_check("a burst of 100 shots from 32 shooters leaves the effects settling back", after <= peak)
	_check("every shooter keeps its effects bounded", in_flight <= 32 * AwShotFx.MAX_LIVE)
	for fx in fxs:
		fx.advance(5.0)
	var warm := 0
	for s in 100:
		var spot := Vector3(float(s % 32) + 4.0, 0.0, -6.0)
		var t1 := Time.get_ticks_usec()
		fxs[s % 32].play_remote(AwWeaponNet.KIND_SHOT, Transform3D(Basis.looking_at(Vector3(0.0, -0.5, -1.0)), spot), Vector3(0.0, -0.5, -1.0), &"rifle")
		warm += Time.get_ticks_usec() - t1
	print("BENCH shotfx: warm second burst %.4f ms/shot" % (float(warm) / 100.0 / 1000.0))
	for fx in fxs:
		fx.advance(5.0)

	_shot_fx_limits(holder)
	holder.queue_free()
	camera.queue_free()
	floor_body.queue_free()
	_end()


## The cvar limits half of [method _shot_fx_pool]: what a far, a mid-range and the local gun draw, under [param holder].
func _shot_fx_limits(holder: Node3D) -> void:
	# A far shooter draws nothing, a mid-range one draws no light, the local gun is never limited.
	var rules := AwShotFx.rules
	var lone := AwShotFx.new()
	lone.binbun_flash = false
	holder.add_child(lone)
	var near_at := Transform3D(Basis.looking_at(Vector3(0.0, -0.5, -1.0)), Vector3(0.0, 0.0, -10.0))
	var mid_at := Transform3D(near_at.basis, Vector3(0.0, 0.0, -60.0))
	var far_at := Transform3D(near_at.basis, Vector3(0.0, 0.0, -300.0))
	var aim := Vector3(0.0, -0.5, -1.0)
	DotFxLightBudget.reset()
	lone.play_remote(AwWeaponNet.KIND_SHOT, far_at, aim, &"rifle")
	_check("a shot farther than cl_shotfx_fx_distance draws nothing", lone.live_count() == 0 and rules.fx_distance < 300.0)
	lone.play_remote(AwWeaponNet.KIND_SHOT, mid_at, aim, &"rifle")
	_check("a shot beyond cl_shotfx_light_distance still draws but carries no light", lone.live_count() > 0 and lone._lights_live() == 0)
	lone.advance(5.0)
	DotFxLightBudget.reset()
	lone.play_remote(AwWeaponNet.KIND_SHOT, near_at, aim, &"rifle")
	_check("a near shot carries one light, and never more than cl_shotfx_remote_lights", lone._lights_live() == 1)
	lone.advance(5.0)
	var mine := AwShotFx.new()
	mine.first_person = true
	mine.binbun_flash = false
	holder.add_child(mine)
	DotFxLightBudget.reset()
	mine.play_remote(AwWeaponNet.KIND_SHOT, mid_at, aim, &"rifle")
	_check("the local gun keeps its light at the same distance", mine.live_count() > 0 and mine._lights_live() == 1)
	for _i in 12:
		lone.play_remote(AwWeaponNet.KIND_SHOT, near_at, aim, &"rifle")
		mine.play_remote(AwWeaponNet.KIND_SHOT, near_at, aim, &"rifle")
	_check("another shooter holds at most cl_shotfx_remote_voices voices", int(lone.describe()["voices"]) <= rules.remote_voices)
	_check("another shooter keeps at most cl_shotfx_remote_live effects", lone.live_count() <= rules.remote_live)
	_check("the local gun holds more than that (%d voices, %d effects)" % [int(mine.describe()["voices"]), mine.live_count()], mine.live_count() > rules.remote_live)
	var deaf := AwShotFx.new()
	holder.add_child(deaf)
	deaf.play_remote(AwWeaponNet.KIND_SHOT, far_at, aim, &"rifle")
	_check("a report beyond cl_shotfx_voice_distance makes no voice", int(deaf.describe()["voices"]) == 0)
	_shot_fx_sky(holder)
	_shot_fx_rounds(holder)
	_shot_fx_unfade(holder)
	_shot_fx_drawn_case(holder)


## A case thrown from a gun drawn twice life size (first person) is twice as long and thrown twice as fast, under twice
## the gravity, so it keeps its size beside the gun and the same arc.
func _shot_fx_drawn_case(holder: Node3D) -> void:
	var fx := AwShotFx.new()
	fx.first_person = true
	fx.sounds = false
	holder.add_child(fx)
	fx.play_eject(Transform3D.IDENTITY, &"rifle", 1.0, 1.0)
	fx.play_eject(Transform3D.IDENTITY, &"rifle", 1.0, 2.0)
	var ok := fx.shell_count() == 2
	if ok:
		var life: Dictionary = fx._shells[0]
		var drawn: Dictionary = fx._shells[1]
		var ratio: float = (drawn["node"] as Node3D).scale.y / (life["node"] as Node3D).scale.y
		ok = is_equal_approx(ratio, 2.0) and is_equal_approx(float(drawn["gravity"]), 2.0 * float(life["gravity"]))
	_check("a case from a gun drawn twice life size is drawn and thrown at twice the scale", ok)
	fx.free()


## A first-person pack flash draws without the art's proximity fade (it hid the flash against the gun's own barrel),
## keeps that when another copy of the art sets it again, sizes a revolver's above a rifle's, and allocates nothing more per shot.
func _shot_fx_unfade(holder: Node3D) -> void:
	var was := DotMuzzleFlash.force_available
	DotMuzzleFlash.force_available = true
	var fx := AwShotFx.new()
	fx.first_person = true
	fx.sounds = false
	holder.add_child(fx)
	var warmed := AwShotFx.warm().size()
	var shaders := AwShotFx._over_shaders.size()
	var muzzle := Transform3D(Basis(), Vector3(0.0, 1.0, -0.5))
	fx._flash(muzzle, 1.0, AwWeaponSound.MAGNUM, &"revolver", true)
	var flash: Node3D = null
	for one: Variant in fx._pack_flashes.values():
		flash = one
	var originals: Array = fx._unfaded.keys().filter(func(m: ShaderMaterial) -> bool: return fx._unfaded[m] != m)
	var faded_elsewhere := originals.any(func(m: ShaderMaterial) -> bool: return bool(m.get_shader_parameter("proximity_fade")))
	_check("a first-person pack flash draws over its gun, without the proximity fade dot-fx sets on the shared art (%d materials)" % originals.size(),
		flash != null and not originals.is_empty() and faded_elsewhere and AwShotFx.is_unfaded(flash))
	var copies := fx._unfaded.size()
	var nodes := flash.find_children("*", "", true, false).size() if flash != null else -1
	for _i in 4:
		fx._flash(muzzle, 1.0, AwWeaponSound.MAGNUM, &"revolver", true)
	_check("a later first-person shot copies no material and builds no node",
		fx._unfaded.size() == copies and flash != null and flash.find_children("*", "", true, false).size() == nodes)
	_check("the load gate's warm list builds the over-the-gun flash shaders, so no shot compiles one (%d shaders, %d warmed)" % [shaders, warmed],
		shaders >= 4 and AwShotFx._over_shaders.size() == shaders)
	_check("a revolver's first-person pack flash is drawn larger than its category's (%.2f)" % (flash.scale.x if flash != null else 0.0),
		flash != null and flash.scale.x > 1.2)
	fx.queue_free()
	DotMuzzleFlash.force_available = was


## A shot on the sky draws nothing where it lands, a shot on a wall a mark: sky by group or by hull_kind meta.
func _shot_fx_sky(holder: Node3D) -> void:
	var wall := StaticBody3D.new()
	var tagged := StaticBody3D.new()
	tagged.set_meta(&"hull_kind", "sky")
	var grouped := StaticBody3D.new()
	grouped.add_to_group(AwShotFx.NO_IMPACT_GROUP)
	for body in [wall, tagged, grouped]:
		holder.add_child(body)
	_check("the sky (meta or group) draws no impact, a wall and a ray with no collider do",
		not AwShotFx.draws_impact(tagged) and not AwShotFx.draws_impact(grouped)
		and AwShotFx.draws_impact(wall) and AwShotFx.draws_impact(null))
	var fx := AwShotFx.new()
	holder.add_child(fx)
	var at := Vector3(0.0, 0.0, -10.0)
	fx.play_impact(at, Vector3.BACK, tagged)
	fx.play_impact(at, Vector3.BACK, grouped)
	_check("a shot landing on the sky leaves no mark and no effect (%d, %d)" % [fx.mark_count(), fx.live_count()],
		fx.mark_count() == 0 and fx.live_count() == 0)
	fx.play_impact(at, Vector3.BACK, wall)
	_check("the same shot on a wall leaves a mark and an effect (%d, %d)" % [fx.mark_count(), fx.live_count()],
		fx.mark_count() == 1 and fx.live_count() > 0)
	fx.advance(5.0)


## Each gun's round has its own tracer and impact, its impact sounds like what it hit, and handling carries less far than a report.
func _shot_fx_rounds(holder: Node3D) -> void:
	var pistol := float(AwShotFx.round_profile(AwWeaponSound.LIGHT)["width"])
	var sniper := float(AwShotFx.round_profile(AwWeaponSound.SNIPER)["width"])
	var pellet := float(AwShotFx.round_profile(AwWeaponSound.SHOTGUN)["width"])
	_check("a sniper's tracer is wider than a pistol's, a pellet's the thinnest, an unknown class the rifle's",
		sniper > pistol and pellet < pistol
		and AwShotFx.round_profile(&"nonsense") == AwShotFx.round_profile(AwWeaponSound.RIFLE))
	var fx := AwShotFx.new()
	fx.first_person = true
	holder.add_child(fx)
	fx.play_remote(AwWeaponNet.KIND_SHOT, Transform3D(Basis(), Vector3(0.0, 0.0, 40.0)), Vector3.FORWARD, &"sniper")
	var widths: Array[float] = []
	for live: Dictionary in fx._live:
		if live.get("kind", &"") == &"tracer":
			widths.append(float(live["width"]))
	_check("a sniper shot's tracer is drawn at the sniper's width (%s)" % [widths], widths.size() == 1 and is_equal_approx(widths[0], sniper))
	var metal := StaticBody3D.new()
	metal.set_meta(&"surface", "steel")
	holder.add_child(metal)
	var linked := DotWeaponSound.count(&"impact_metal") > 0 and DotWeaponSound.count(&"impact_flesh") > 0
	var on_metal := AwShotFx.impact_stream(AwShotFx.IMPACT_WORLD, metal)
	var on_body := AwShotFx.impact_stream(AwShotFx.IMPACT_BODY)
	_check("a shot on steel sounds of metal and one on a body of flesh, with dot-audio linked",
		not linked or (on_metal.resource_path.contains("impact_metal") and on_body.resource_path.contains("impact_flesh")))
	var reloader := AwShotFx.new()
	var shooter := AwShotFx.new()
	for one: AwShotFx in [reloader, shooter]:
		one.first_person = true
		one.layered_shots = false
		holder.add_child(one)
	reloader.play_reload(AwWeaponSound.RELOAD_OUT, Vector3.ZERO, &"rifle")
	shooter.play_remote(AwWeaponNet.KIND_SHOT, Transform3D(), Vector3.FORWARD, &"rifle")
	var handling_size := -1.0
	var report_size := -1.0
	for voice in reloader._voices:
		if voice.stream != null:
			handling_size = voice.unit_size
	for voice in shooter._voices:
		if voice.stream != null:
			report_size = voice.unit_size
	_check("a reload carries less far than a report (unit size %.1f vs %.1f)" % [handling_size, report_size],
		handling_size > 0.0 and handling_size < report_size)
	fx.advance(5.0)


## The glove fit reads each gun texture back once: a second fit of the same art gives the same
## colours from the cache, and turning the cache off still reads them.
func _glove_cache() -> void:
	_begin("glove contrast texture cache")
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.4, 0.6, 1.0))
	var tex := ImageTexture.create_from_image(img)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	mi.material_override = mat
	var was := AwViewArms.albedo_cache
	AwViewArms.albedo_cache = true
	var first := AwViewArms.surface_albedos(mi)
	img.fill(Color(1, 1, 1, 1))
	tex.set_image(img)
	var again := AwViewArms.surface_albedos(mi)
	_check("a second fit of the same texture comes from the cache",
		first.size() == 1 and again.size() == 1 and first[0].is_equal_approx(again[0]) and absf(first[0].g - 0.4) < 0.02)
	AwViewArms.albedo_cache = false
	var img2 := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img2.fill(Color(0.8, 0.4, 0.2, 1.0))
	var tex2 := ImageTexture.create_from_image(img2)
	mat.albedo_texture = tex2
	var fresh := AwViewArms.surface_albedos(mi)
	_check("with the cache off the texture is read and not remembered",
		fresh.size() == 1 and absf(fresh[0].r - 0.8) < 0.02 and not AwViewArms._means.has(tex2.get_instance_id()))
	AwViewArms.albedo_cache = was
	mi.free()
	_end()


## Marks walk only their fading head: the same transparencies and lifetimes as aging every mark
## each frame, over seeded uneven frames with marks made between them.
func _mark_fade() -> void:
	_begin("mark fade walks the head")
	var holder := Node3D.new()
	add_child(holder)
	var wall := StaticBody3D.new()
	holder.add_child(wall)
	var shots := AwShotFx.new()
	shots.sounds = false
	holder.add_child(shots)
	shots.set_process(false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var ages: Array[float] = []  # the reference: each mark aged by every frame's delta
	var worst := 0.0
	var count_ok := true
	var most := 0
	for frame in 1200:
		if frame % 40 == 0 and frame < 700:
			shots.play_impact(Vector3(rng.randf_range(-2.0, 2.0), 1.0, -10.0), Vector3.BACK, wall)
			ages.append(0.0)
		var delta := rng.randf_range(0.004, 0.05)
		shots.advance(delta)
		var kept: Array[float] = []
		for age in ages:
			if (age + delta) / AwShotFx.MARK_LIFE < 1.0:
				kept.append(age + delta)
		ages = kept
		if shots.mark_count() != ages.size():
			count_ok = false
			break
		most = maxi(most, ages.size())
		for i in ages.size():
			var want := clampf((ages[i] / AwShotFx.MARK_LIFE - 0.75) / 0.25, 0.0, 1.0)
			var node: Node3D = shots._marks[i]["node"]
			worst = maxf(worst, absf(node.transparency - want))
	_check("as many marks as aging each one (%d at most, %d left)" % [most, ages.size()],
		count_ok and most >= 5 and ages.is_empty())
	_check("the same fade, worst %.7f" % worst, worst < 1e-5)
	holder.free()
	_end()


## The rig tells a host whether a tick would take the idle path.
func _would_idle() -> void:
	_begin("rig would_idle")
	var rig := AwWeaponRig.new()
	var cmd := DotWeaponCommand.new()
	_check("a rig not set up never idles", not rig.would_idle(cmd))
	rig.free()
	var r2 := AwWeaponRig.new()
	var cat := DotWeaponCatalogue.new()
	for def in AwWeaponPack.weapons(AwWeaponDamage.table(), ""):
		cat.add(def)
	r2.catalogue = cat
	add_child(r2)
	var ok := r2.setup().ok
	_check("the rig sets up", ok)
	var idles := false
	if ok:
		r2.give_everything()
		# A gun whose spread follows the carrier needs a context; the rig's own idle posture stands in for it.
		for slot in r2.arsenal._slots.keys():
			r2.arsenal.equip(slot)
			if r2.would_idle(cmd):
				idles = true
				break
	_check("a set-up rig with nothing pressed idles on a weapon that needs no context", idles)
	cmd.buttons = DotWeaponCommand.BUTTON_ATTACK
	_check("a pressed attack does not", ok and idles and not r2.would_idle(cmd))
	r2.queue_free()
	_end()


## Effects with nothing to show stop their per-frame work and pick it up again on the next shot, draw or showing.
func _idle_sleep() -> void:
	_begin("idle effects sleep")
	var holder := Node3D.new()
	add_child(holder)
	var wall := StaticBody3D.new()
	holder.add_child(wall)
	var shots := AwShotFx.new()
	shots.sounds = false
	holder.add_child(shots)
	shots._process(0.1)
	_check("a shooter with nothing showing stops processing", not shots.is_processing() and shots.is_idle())
	shots.play_impact(Vector3(0.0, 0.0, -10.0), Vector3.BACK, wall)
	_check("an impact wakes it (%d marks, %d live)" % [shots.mark_count(), shots.live_count()],
		shots.is_processing() and not shots.is_idle())
	shots._process(AwShotFx.MARK_LIFE + 1.0)
	_check("once the mark has faded it sleeps again", not shots.is_processing() and shots.is_idle())

	var charge := preload("res://addons/arena_weapons/view/aw_charge_fx.gd").new()
	holder.add_child(charge)
	charge._process(0.1)
	_check("a hidden charge ball stops processing", not charge.is_processing())
	charge.note_fired()
	charge._process(0.1)
	_check("a shot keeps it counting through the fizzle window", charge.is_processing())
	charge._process(0.2)
	_check("past the window it sleeps again", not charge.is_processing())
	charge.set_charge(0.5)
	_check("a draw wakes it", charge.is_processing() and charge.visible)

	var held := AwWorldModel.new()
	holder.add_child(held)
	held.visible = false
	held._process(0.1)
	held._process(0.25)
	_check("a hidden held gun banks its time (%.2f)" % held._hidden_for, is_equal_approx(held._hidden_for, 0.25))
	held.visible = true
	held._process(0.1)
	_check("and spends it when it shows", held._hidden_for < 0.0)
	holder.free()
	_end()


## [param id]'s art as a pack's stand-in builds it: the base gun of its slot, dressed from the pack's own rows.
func _dressed(id: StringName) -> AwWeaponVisual:
	var art: AwWeaponVisual
	match id:
		&"knife":
			art = AwWeaponArtTable.knife()
		&"pistol":
			art = AwWeaponArtTable.pistol()
		&"minigun", &"launcher":
			art = AwWeaponArtTable.launcher()
		_:
			art = AwWeaponArtTable.rifle()
	art.id = id
	AwArtDress.apply(art, AwWeaponArt.weapon_rows("").get(id, {}))
	return art


func _charge_fizzle() -> void:
	_begin("charge ball fizzle")
	var fx := preload("res://addons/arena_weapons/view/aw_charge_fx.gd").new()
	fx.set_charge(0.6)
	fx.advance(0.5)
	fx.set_charge(0.0)
	_check("an early release is a fizzle that ends in under 8 frames at 60 Hz",
		fx.is_fizzling() and fx.collapse_time() < 8.0 / 60.0)
	for i in 8:
		fx.advance(1.0 / 60.0)
	_check("the fizzle is gone after 8 frames", not fx.visible and fx.shown() == 0.0)
	fx.free()
	_end()


## A hand's first shot and charge take what [AwFxPool] parked under the cover: nothing is built when they happen.
func _fx_pool() -> void:
	_begin("fx pool: parked effects are taken, not built")
	var pool := AwFxPool.new()
	add_child(pool)
	var full := false
	for _i in 400:
		if pool.fill(3, 2, 0.5):
			full = true
			break
	_check("fill parks what was asked for, a slice at a time", full and pool.spare_shots() == 3 and pool.spare_charges() == 2)
	for _i in 3:
		await get_tree().process_frame
	var hand := Node3D.new()
	add_child(hand)
	var before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var fx := AwFxPool.take_shot_fx()
	_check("a parked effects node comes out of the tree", fx != null and fx.get_parent() == null)
	# A game hands every remote hand one shared layered player; alone, the first shot would build its own.
	fx.layered_shots = false
	hand.add_child(fx)
	var kids := fx.get_child_count()
	fx.play_remote(AwWeaponNet.KIND_SHOT, Transform3D.IDENTITY, Vector3.FORWARD, &"rifle")
	var made := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) - before
	_check("taking it and firing once creates no node (%d made, %d under it)" % [made, fx.get_child_count() - kids], made == 0)
	_check("it came with its voices and quads", (fx.get("_voices") as Array).size() >= 1
		and (fx.get_node("Meshes") as DotFxMeshPool).built() >= pool.shot_meshes)
	_check("it ticks again once in a hand", fx.can_process())
	var ball := AwFxPool.take_charge_fx()
	hand.add_child(ball)
	ball.call("set_charge", 0.5)
	_check("a parked charge ball shows on the first charge and creates no node", ball.visible
		and int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) == before)
	_check("the pool counts what it handed out", pool.handed == 2 and pool.spare_shots() == 2 and pool.spare_charges() == 1)
	var _a := AwFxPool.take_shot_fx()
	var _b := AwFxPool.take_shot_fx()
	_check("an empty pool answers null and counts the miss", AwFxPool.take_shot_fx() == null and pool.missed == 1)
	hand.add_child(_a)
	hand.add_child(_b)
	_a.first_person = false
	_a.layered_shots = true
	_check("a remote shooter takes the layered shot the pool built instead of its own",
		not AwShotLayers.available() or (_a.prewarm_layers() and _a.get("_layers") == AwFxPool.shared_layers(self, pool.layers_bus)))
	pool.free()
	_check("with no pool in the tree there is nothing to take",
		AwFxPool.current() == null and AwFxPool.take_shot_fx() == null and AwFxPool.take_charge_fx() == null)
	hand.free()
	_end()


func _shared_catalogue() -> void:
	_begin("shared weapon catalogue")
	var a := AwWeaponCatalogue.shared()
	var ids := AwWeaponCatalogue.weapons().map(func(d: DotWeaponDef) -> StringName: return d.id)
	_check("the shared catalogue is built once and holds every weapon",
		a != null and a == AwWeaponCatalogue.shared() and ids.all(func(id: StringName) -> bool: return a.get_def(id) != null))
	AwWeaponCatalogue.remove_source(&"lag16_probe")
	_check("adding or removing a source builds it again", AwWeaponCatalogue.shared() != a)
	_end()


func _mag_carve() -> void:
	_begin("a magazine carved out of a welded mesh")
	var carve: Script = load("res://addons/arena_weapons/view/aw_mag_carve.gd")
	# One mesh: a body (triangles near y=0) and a magazine (triangles near y=-1) in a single surface.
	var verts := PackedVector3Array()
	for y in [0.0, -1.0]:
		for k in 20:
			var x := float(k) * 0.1
			verts.append_array(PackedVector3Array([Vector3(x, y, 0), Vector3(x + 0.05, y, 0), Vector3(x, y, 0.05)]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var whole := ArrayMesh.new()
	whole.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var holder := Node3D.new()
	var weapon := Node3D.new()
	holder.add_child(weapon)
	var mi := MeshInstance3D.new()
	mi.mesh = whole
	weapon.add_child(mi)
	add_child(holder)
	var mag: Node3D = carve.call(&"carve", weapon, holder, Transform3D.IDENTITY, AABB(Vector3(-1, -1.5, -1), Vector3(4, 1, 2)), "selftest")
	_check("the magazine becomes a node of the weapon", mag != null and mag.get_parent() == mi.get_parent() and mag.name == "Magazine")
	_check("the magazine holds its 20 triangles", mag != null and (mag as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 60)
	_check("the gun keeps the other 20", mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 60)
	_check("nothing is left in the carve box on the gun", mi.mesh.get_aabb().position.y > -0.5)
	var again: Node3D = carve.call(&"carve", weapon, holder, Transform3D.IDENTITY, AABB(Vector3(-1, 5, -1), Vector3(1, 1, 1)), "selftest-empty")
	_check("a box with nothing in it carves nothing", again == null)
	carve.call(&"merge_back", mag)
	_check("merging back leaves one mesh with every triangle", mi.mesh == whole and weapon.get_child_count() == 1)
	holder.queue_free()
	_check("the carve box is remembered per model", (carve.call(&"recall", "x") as AABB).size == Vector3.ZERO)
	_end()


## A build without the models (the web shell) draws them from a mounted pack listed with add_fallback_root.
## The pack is built here with PCKPacker: one box scene, under a synthetic dot-cloud mount; no CDN.
func _assets_pack() -> void:
	_begin("models come from a mounted pack when the build lacks them")
	const ROOT := "res://dot_cloud/aw_synth/1/arena_weapons/assets"
	var path := AwModelCache.ASSETS_BASE + "models/selftest_pack_gun.tscn"
	var outside := "res://aw_selftest_elsewhere/models/selftest_pack_gun.tscn"
	AwModelCache.clear()
	_check("the build does not carry the pack's model", not AwModelCache.scene(path).ok and not AwModelCache.exists(path))
	_check("a missing model measures as an empty box", AwModelCache.bounds(path).size == Vector3.ZERO)
	var made := _synth_assets_pack(ROOT + "/models/selftest_pack_gun.tscn")
	_check("synthetic assets pack mounts", made != "" and ProjectSettings.load_resource_pack(made, false))
	_check("mounted but not listed, the model is still missing", not AwModelCache.scene(path).ok)
	AwModelCache.add_fallback_root(ROOT + "/")
	_check("listed, the model loads from the pack", AwModelCache.scene(path).ok and AwModelCache.exists(path))
	var model := AwModelCache.instantiate(path)
	_check("and instantiates", model != null)
	if model != null:
		model.free()
	_check("the empty box measured before is dropped and the model measured", is_equal_approx(AwModelCache.bounds(path).size.x, 0.2))
	_check("a path outside the addon's assets is not redirected", not AwModelCache.exists(outside))
	AwModelCache.remove_fallback_root(ROOT)
	_check("unlisted again, the model is gone and the list empty", not AwModelCache.exists(path) and AwModelCache.fallback_roots().is_empty())
	AwModelCache.clear()
	_end()


## A headless build keeps each model's textures as 4x4 downsamples (the dummy renderer holds a full
## decoded copy otherwise): the glove reads the same colours, and the bounds come from the same pass.
func _headless_textures() -> void:
	_begin("headless models keep 4x4 textures")
	var path := _dressed(&"rifle").model_path
	var was := AwModelCache.shrink_textures_headless
	var cached := AwViewArms.albedo_cache
	AwViewArms.albedo_cache = false
	# A fresh read of the file: the model may already be cached (and shrunk) by an earlier section.
	var fresh := ResourceLoader.load(AwModelCache.resolve(path), "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	var whole: Node = fresh.instantiate() if fresh != null else null
	var before: Array[Color] = []
	var box := AABB()
	if whole != null:
		before = AwViewArms.surface_albedos(whole)
		var boxes: Array[AABB] = []
		AwModelCache._collect_bounds(whole, Transform3D.IDENTITY, boxes)
		for b in boxes:
			box = b if box.size == Vector3.ZERO else box.merge(b)
	_check("the file itself has whole textures", whole != null and _largest_texture(whole) > 4)
	if whole != null:
		whole.free()
	AwModelCache.shrink_textures_headless = true
	AwModelCache.clear()
	var headless := DisplayServer.get_name() == "headless"
	var loaded := AwModelCache.scene(path).ok
	_check("headless, the bounds are measured as the model loads", loaded and (not headless or AwModelCache.describe().measured == 1) and AwModelCache.bounds(path).is_equal_approx(box))
	var small := AwModelCache.instantiate(path)
	var after: Array[Color] = []
	if small != null:
		after = AwViewArms.surface_albedos(small)
	var same := after.size() == before.size() and not after.is_empty()
	for i in mini(after.size(), before.size()):
		same = same and after[i].is_equal_approx(before[i])
	_check("headless, textures are 4x4 and the glove reads the same colours", small != null and same and (not headless or _largest_texture(small) == 4))
	if small != null:
		small.free()
	AwModelCache.shrink_textures_headless = was
	AwViewArms.albedo_cache = cached
	AwModelCache.clear()
	_end()


## The widest texture side on any material under [param root].
func _largest_texture(root: Node) -> int:
	var widest := 0
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			if mat == null:
				continue
			for prop in mat.get_property_list():
				if prop["type"] != TYPE_OBJECT:
					continue
				var tex := mat.get(prop["name"]) as Texture2D
				if tex != null:
					widest = maxi(widest, maxi(tex.get_width(), tex.get_height()))
	return widest

## Writes a pck holding a 0.2 m box scene at [param inside]; the pck's path, or "" if it could not.
func _synth_assets_pack(inside: String) -> String:
	var root := Node3D.new()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.2, 0.1, 0.4)
	mesh.mesh = box
	root.add_child(mesh)
	mesh.owner = root
	var packed := PackedScene.new()
	var packed_ok := packed.pack(root) == OK
	root.free()
	var scene_file := ProjectSettings.globalize_path("user://aw_selftest_pack_gun.tscn")
	if not packed_ok or ResourceSaver.save(packed, scene_file) != OK:
		return ""
	var out := ProjectSettings.globalize_path("user://aw_selftest_assets.pck")
	var packer := PCKPacker.new()
	if packer.pck_start(out) != OK or packer.add_file(inside, scene_file) != OK or packer.flush() != OK:
		return ""
	return out
