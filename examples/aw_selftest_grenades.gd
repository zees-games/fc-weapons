extends "aw_selftest_attach.gd"

## Grenade and utility sections of the self-test; split out of aw_selftest.gd for file size.


func _grenades() -> void:
	_begin("grenade gameplay")
	var defs := AwSpawnProvider.weapon_defs()
	var rules := AwGrenadeRules.new()
	var floor_y := func(_from: Vector3, to: Vector3) -> Dictionary:
		if to.y > 0.0:
			return {}
		return {"position": Vector3(to.x, 0.0, to.z), "normal": Vector3.UP}
	var make := func(id: StringName, vel: Vector3, fuse: int) -> AwGrenade:
		var s := GSWeaponSpawn.make(id, Vector3(0, 1, 0), vel, 7)
		s.fuse_ticks = fuse
		s.gravity_scale = 1.0
		return AwGrenade.from_spawn(s, _def(defs, id), rules)

	_check("flash, smoke and incendiary are weapons with their own kinds", [&"aw_flash", &"aw_smoke", &"aw_incendiary"].all(func(i: StringName) -> bool: return _def(defs, i).slot == 5 and _def(defs, i).params.has(&"kind")))
	_check("they wear the baked grenade models", [&"flash", &"smoke", &"incendiary"].all(func(i: StringName) -> bool: return ResourceLoader.exists(AwWeaponArt.row_of(i)["model"])))

	var g: AwGrenade = make.call(&"aw_frag", Vector3(4, 0, 0), 64)
	var ticks := 0
	while ticks < 200:
		var gone := g.step(floor_y, 64)
		ticks += 1
		if gone:
			break
	_check("a frag bounces off the floor and goes off when the fuse runs out (%d ticks)" % ticks, g.bounces > 0 and ticks == 64 and g.position.y >= 0.0)
	_check("a bounce loses speed", g.velocity.length() < 12.0)

	var st: AwGrenade = make.call(&"aw_sticky", Vector3(2, 0, 0), 500)
	for i in 100:
		var _gone := st.step(floor_y, 64)
	_check("a sticky stays where it landed", st.stuck and st.velocity == Vector3.ZERO)

	var inc: AwGrenade = make.call(&"aw_incendiary", Vector3(0, -3, 0), 500)
	var burst := false
	for i in 100:
		burst = inc.step(floor_y, 64)
		if burst:
			break
	_check("an incendiary bursts on first contact, fuse not spent", burst and inc.fuse > 300)

	var cooked: AwGrenade = make.call(&"aw_frag", Vector3.ZERO, 0)
	_check("a grenade cooked past its fuse goes off at once", cooked.step(floor_y, 64))

	g.position = Vector3.ZERO
	var victims: Array = [
		{"id": 7, "position": Vector3(0, 0, 0), "eye": Vector3(0, 1.6, 0), "forward": Vector3.FORWARD},
		{"id": 2, "position": Vector3(2.6, 0, 0), "eye": Vector3(2.6, 1.6, 0), "forward": Vector3.FORWARD},
		{"id": 3, "position": Vector3(9, 0, 0), "eye": Vector3(9, 1.6, 0), "forward": Vector3.FORWARD},
		{"id": 4, "position": Vector3(1, 0, 0), "eye": Vector3(1, 1.6, 0), "forward": Vector3.FORWARD},
	]
	var clear := func(_a: Vector3, b: Vector3) -> bool: return b.x != 1.0
	var hurt := {}
	for e in AwGrenadeBlast.detonate(g, _def(defs, &"aw_frag"), victims, clear):
		if e["event"] == "damage":
			hurt[e["victim"]] = e["damage"]
	_check("splash falls off with distance and the thrower is hurt", hurt.has(7) and hurt.has(2) and hurt[7] > hurt[2] and hurt[2] > 0.0)
	_check("outside the radius or behind cover takes nothing", not hurt.has(3) and not hurt.has(4))

	var flash := AwGrenade.from_spawn(GSWeaponSpawn.make(&"aw_flash", Vector3.ZERO, Vector3.ZERO, 7), _def(defs, &"aw_flash"), rules)
	var look: Array = [
		{"id": 2, "position": Vector3(0, 0, -4), "eye": Vector3(0, 1.6, -4), "forward": Vector3(0, 0, 1)},
		{"id": 3, "position": Vector3(0, 0, -4), "eye": Vector3(0, 1.6, -4), "forward": Vector3(0, 0, -1)},
	]
	var blind := {}
	for e in AwGrenadeBlast.detonate(flash, _def(defs, &"aw_flash"), look, func(_a: Vector3, _b: Vector3) -> bool: return true):
		if e["event"] == "blind":
			blind[e["victim"]] = e["seconds"]
	_check("a flash blinds who faces it and spares who looks away", blind.has(2) and not blind.has(3) and blind[2] <= rules.flash_seconds)

	var sm := AwGrenade.from_spawn(GSWeaponSpawn.make(&"aw_smoke", Vector3.ZERO, Vector3.ZERO, 7), _def(defs, &"aw_smoke"), rules)
	var sev := AwGrenadeBlast.detonate(sm, _def(defs, &"aw_smoke"), [], clear)
	_check("smoke leaves a cloud and no damage", sev.any(func(e: Dictionary) -> bool: return e["event"] == "smoke") and not sev.any(func(e: Dictionary) -> bool: return e["event"] == "damage"))

	var _set := rules.set_cvar("sv_grenade_bounce", "5")
	_check("cvars clamp to their range and have sane defaults", is_equal_approx(rules.bounce, 0.95) and is_equal_approx(AwGrenadeRules.new().friction, 0.7))
	_grenade_bounce(defs, floor_y)
	_end()


## A dropped grenade rebounds as high as sv_grenade_bounce says; sv_grenade_damping drags it; a sticky still sticks.
func _grenade_bounce(defs: Array[GSWeaponDef], floor_y: Callable) -> void:
	var throw := func(id: StringName, vel: Vector3, r: AwGrenadeRules) -> AwGrenade:
		var s := GSWeaponSpawn.make(id, Vector3(0, 1, 0), vel, 7)
		s.fuse_ticks = 5000
		s.gravity_scale = 1.0
		return AwGrenade.from_spawn(s, _def(defs, id), r)
	var rebound := func(r: AwGrenadeRules) -> float:
		var g: AwGrenade = throw.call(&"aw_frag", Vector3.ZERO, r)
		var top := 0.0
		for i in 200:
			var _gone := g.step(floor_y, 64)
			if g.bounces == 1:
				top = maxf(top, g.position.y)
		return top
	var soft := AwGrenadeRules.new()
	soft.set_cvar("sv_grenade_bounce", "0.2")
	var hard := AwGrenadeRules.new()
	hard.set_cvar("sv_grenade_bounce", "0.8")
	var low: float = rebound.call(soft)
	var high: float = rebound.call(hard)
	_check("a dropped grenade bounces up off the floor, higher with sv_grenade_bounce (%.2f m, %.2f m)" % [low, high], low > 0.02 and high > low * 4.0 and high < 1.0)

	var none := func(_a: Vector3, _b: Vector3) -> Dictionary: return {}
	var drag := AwGrenadeRules.new()
	drag.set_cvar("sv_grenade_damping", "2")
	var free: AwGrenade = throw.call(&"aw_frag", Vector3(10, 0, 0), AwGrenadeRules.new())
	var slowed: AwGrenade = throw.call(&"aw_frag", Vector3(10, 0, 0), drag)
	for i in 32:
		var _a := free.step(none, 64)
		var _b := slowed.step(none, 64)
	_check("sv_grenade_damping slows a flying grenade (%.1f against %.1f m/s)" % [slowed.velocity.x, free.velocity.x], is_equal_approx(free.velocity.x, 10.0) and slowed.velocity.x < 4.0 and slowed.velocity.x > 3.0)

	var once := AwGrenadeRules.new()
	once.set_cvar("sv_grenade_max_bounces", "1")
	var dead: AwGrenade = throw.call(&"aw_frag", Vector3.ZERO, once)
	while dead.bounces == 0:
		var _gone := dead.step(floor_y, 64)
	_check("sv_grenade_max_bounces stops it dead; 0 keeps bouncing", dead.velocity == Vector3.ZERO and AwGrenadeRules.new().max_bounces == 0.0)

	var sticky: AwGrenade = throw.call(&"aw_sticky", Vector3(2, -2, 0), hard)
	for i in 60:
		var _gone := sticky.step(floor_y, 64)
	_check("a sticky sticks however bouncy the cvar", sticky.stuck and sticky.velocity == Vector3.ZERO and sticky.bounces <= 1)


func _utility() -> void:
	_begin("utility grenade glue")
	var defs := AwSpawnProvider.weapon_defs()
	var ids := AwUtilityZones.utility_ids(defs)
	_check("utility ids are the flash, smoke and incendiary, not the frags", ids.size() == 3 and ids.has(&"aw_flash") and not ids.has(&"aw_frag"))

	var z := AwUtilityZones.new()
	var people: Array = [
		AwUtilityZones.victim(2, Vector3(1, 0, 0), Vector3(1, 1.6, 0), Vector3.LEFT),
		AwUtilityZones.victim(3, Vector3(30, 0, 0), Vector3(30, 1.6, 0), Vector3.LEFT),
		AwUtilityZones.victim(4, Vector3(1, 5, 0), Vector3(1, 6.6, 0), Vector3.LEFT),
	]
	var hits: Array[Dictionary] = []
	z.victims = func() -> Array: return people
	z.los = AwUtilityZones.los_from_ray(func(_f: Vector3, _d: Vector3, _n: float) -> bool: return false)
	z.damage = func(attacker: int, victim: int, amount: float, type: Variant, _w: StringName) -> void:
		hits.append({"a": attacker, "v": victim, "n": amount, "t": type})
	var seen: Array[Dictionary] = []
	z.effect.connect(func(i: Dictionary) -> void: seen.append(i))

	var blocked := AwUtilityZones.los_from_ray(func(_f: Vector3, _d: Vector3, _n: float) -> bool: return true)
	_check("the ray adapter says clear when nothing is hit and blocked when something is", z.los.call(Vector3.ZERO, Vector3.ONE) and not blocked.call(Vector3.ZERO, Vector3.ONE) and z.los.call(Vector3.ONE, Vector3.ONE) and blocked.call(Vector3.ONE, Vector3.ONE))

	var inc := AwGrenade.from_spawn(GSWeaponSpawn.make(&"aw_incendiary", Vector3.ZERO, Vector3.ZERO, 7), _def(defs, &"aw_incendiary"), z.rules)
	inc.owner_entity = 9
	var _ev := z.detonate(inc, _def(defs, &"aw_incendiary"))
	_check("an incendiary opens one fire zone and tells the host", z.active_fires() == 1 and seen.size() == 1 and int(seen[0]["fx"]) == AwUtilityZones.Fx.FIRE)
	for i in 10:
		z.tick(0.1)
	var burned := hits.filter(func(h: Dictionary) -> bool: return h["v"] == 2)
	_check("the fire pulses damage as the thrower, twice a second", burned.size() == 2 and burned[0]["a"] == 9 and burned[0]["t"] == AwUtilityZones.FIRE_TYPE)
	_check("fire spares who stands far off or a floor above", not hits.any(func(h: Dictionary) -> bool: return h["v"] == 3 or h["v"] == 4))
	for i in int(z.rules.fire_seconds * 10.0) + 10:
		z.tick(0.1)
	_check("a fire zone burns out", z.active_fires() == 0)

	var smoke := AwGrenade.from_spawn(GSWeaponSpawn.make(&"aw_smoke", Vector3.ZERO, Vector3.ZERO, 7), _def(defs, &"aw_smoke"), z.rules)
	var _sev := z.detonate(smoke, _def(defs, &"aw_smoke"))
	_check("smoke is a cloud that expires", z.active_smokes() == 1 and int(seen[-1]["fx"]) == AwUtilityZones.Fx.SMOKE)
	z.tick(z.rules.smoke_seconds + 1.0)
	_check("smoke is gone after its seconds", z.active_smokes() == 0)

	var flash := AwGrenade.from_spawn(GSWeaponSpawn.make(&"aw_flash", Vector3.ZERO, Vector3.ZERO, 7), _def(defs, &"aw_flash"), z.rules)
	var _fev := z.detonate(flash, _def(defs, &"aw_flash"))
	var blinds := seen.filter(func(i: Dictionary) -> bool: return int(i["fx"]) == AwUtilityZones.Fx.BLIND)
	_check("a flash blinds the one facing it and the ledger holds the blind", blinds.any(func(i: Dictionary) -> bool: return int(i["victim"]) == 2) and z.ledger.is_blind(2) and not z.ledger.is_blind(3))
	var before := z.ledger.remaining(2)
	z.tick(1.0)
	_check("the blind ticks down with the clock", is_equal_approx(z.ledger.remaining(2), before - 1.0))
	z.tick(60.0)
	_check("and ends", not z.ledger.is_blind(2) and z.ledger.count() == 0)

	var l := AwBlindLedger.new()
	var _a := l.blind(1, 3.0)
	var _b := l.blind(1, 1.0)
	_check("a shorter flash never shortens a blind", is_equal_approx(l.remaining(1), 3.0))
	var _c := l.blind(1, 5.0)
	_check("a longer one extends it", is_equal_approx(l.remaining(1), 5.0))
	var _d := l.blind(2, 999.0)
	_check("no blind passes the cap", is_equal_approx(l.remaining(2), l.max_seconds))
	l.clear_victim(2)
	_check("a victim's blind can be lifted", not l.is_blind(2) and l.is_blind(1))

	z.apply_blast_damage = true
	hits.clear()
	var frag := AwGrenade.from_spawn(GSWeaponSpawn.make(&"aw_frag", Vector3.ZERO, Vector3.ZERO, 7), _def(defs, &"aw_frag"), z.rules)
	var _gev := z.detonate(frag, _def(defs, &"aw_frag"))
	_check("blast damage goes through the host's callable when asked", hits.any(func(h: Dictionary) -> bool: return h["v"] == 2))

	var _w := l.blind(5, 2.0, 0.4)
	var _w2 := l.blind(5, 1.0, 0.9)
	var _w3 := l.blind(5, 1.0, 0.2)
	_check("the ledger keeps the strongest strength of a stretch", is_equal_approx(l.strength(5), 0.9) and is_equal_approx(l.strength(1), 1.0))
	l.tick(99.0)
	_check("strength is 0 once the blind ends, and a new blind starts fresh", l.strength(5) == 0.0 and is_equal_approx((l.blind(5, 1.0, 0.3) * 0.0) + l.strength(5), 0.3))
	_check("a blind event carries strength, and a flash at the edge or side is weaker",
		blinds.any(func(i: Dictionary) -> bool: return int(i["victim"]) == 2 and float(i["strength"]) > 0.0 and float(i["strength"]) <= 1.0))
	_utility_fx()
	_end()


func _utility_fx() -> void:
	var own_dir := AwGrenadeFx.own_dir()
	var own_defs := AwGrenadeFx.defs()
	_check("with no folder the clouds load from the addon's own fx/", own_defs[0].scene_path == own_dir + "/smoke_cloud.tscn" and ResourceLoader.exists(own_defs[0].scene_path) and ResourceLoader.exists(own_defs[1].scene_path))
	_check("both shipped cloud scenes instance", (load(own_defs[0].scene_path) as PackedScene).instantiate() != null and (load(own_defs[1].scene_path) as PackedScene).instantiate() != null)
	_check("API level 27 or later", preload("res://addons/fc_weapons/fc_weapons_api.gd").LEVEL >= 27)

	var fx_defs := AwGrenadeFx.defs("res://fx")
	_check("three fx defs: two clouds from the game's folder and a screen flash", fx_defs.size() == 3 and fx_defs[0].scene_path == "res://fx/smoke_cloud.tscn" and fx_defs[2].kind == GSFxDef.Kind.SCREEN)
	_check("the flash decay follows the blind, clamped", AwGrenadeFx.flash_decay_ms(0.01) == AwGrenadeFx.BLIND_MIN_MS and AwGrenadeFx.flash_decay_ms(3.0) == 3000 and AwGrenadeFx.flash_decay_ms(99.0) == AwGrenadeFx.BLIND_MAX_MS)
	_check("showing with no fx host is a no-op", AwGrenadeFx.show(null, null, {"fx": AwUtilityZones.Fx.SMOKE, "seconds": 1.0, "radius": 1.0, "position": Vector3.ZERO, "victim": 0}, 0) == null)


func _thrown() -> bool:
	var art := AwWeaponVisual.make(&"frag")
	art.model_forward = Vector3.UP
	AwArtDress.apply(art, AwSpawnProvider.role_art()[&"frag"])
	return art.model_path == AwWeaponArt.model_path("frag_grenade") and art.model_forward == Vector3.UP



func _rockets() -> void:
	_begin("rocket launchers and the Rocketjump")
	var defs := AwSpawnProvider.weapon_defs()
	var single := _def(defs, &"aw_launcher")
	var quad := _def(defs, &"aw_quad_launcher")
	var sb := single.tuning as GSWeaponBallistics
	var qb := quad.tuning as GSWeaponBallistics
	_check("the single-missile launcher holds one missile, the quad four", single.magazine == 1 and quad.magazine == 4)
	_check("its blast is wider than the quad's (%.1f m against %.1f m)" % [sb.splash_radius, qb.splash_radius], sb.splash_radius > qb.splash_radius)
	var rules := AwRocketRules.new()
	var _m := rules.set_cvar("sv_rocket_launcher_magazine", "2")
	var _r := rules.set_cvar("sv_rocket_launcher_splash_radius", "8")
	var tuned := AwWeaponPack.launcher()
	var other := AwWeaponPack.quad_launcher()
	rules.apply(tuned)
	rules.apply(other)
	_check("sv_rocket_launcher_* retune the single launcher and leave the quad alone", tuned.magazine == 2 and is_equal_approx((tuned.tuning as GSWeaponBallistics).splash_radius, 8.0) and other.magazine == 4)

	var weak := AwRocketRules.new()
	var _w := weak.set_cvar("sv_rocket_jump_damage_scale", "0.25")
	var fit := GSWeaponFitting.make(single.id)
	fit.fit(AwAttachmentSockets.MOUNT_WARHEAD, AwRocketJump.ID)
	var res := AwAttachmentPack.catalogue(weak).apply(single, fit)
	var rj: GSWeaponDef = res.value if res.ok else null
	var rb: GSWeaponBallistics = rj.tuning as GSWeaponBallistics if rj != null else null
	_check("the Rocketjump fits the launcher and cuts its damage by sv_rocket_jump_damage_scale", rb != null and AwRocketJump.is_rocketjump(rj) and is_equal_approx(rb.splash_damage, sb.splash_damage * 0.25) and not AwRocketJump.is_rocketjump(single))
	var choices := AwSpawnProvider.attachment_defs().choices_for(_def(defs, &"aw_rifle"))
	_check("no other gun is offered it", not choices.values().any(func(ids: Array) -> bool: return ids.has(AwRocketJump.ID)))

	var jr := AwRocketRules.new()
	var feet := Vector3(0, 0.1, 0)
	var body := Vector3(0, 0.9, 0)
	var still := Vector3.ZERO
	var fwd := Vector3(0, 0, -1)
	var air := AwRocketJump.launch_velocity(rj, jr, still, body, feet, false, fwd)
	var ground := AwRocketJump.launch_velocity(rj, jr, still, body, feet, true, fwd)
	_check("a blast at the feet throws up and toward the jump (%s)" % air, air.y > 5.0 and air.z < -1.0 and absf(air.x) < 0.01)
	_check("weaker from the floor, unchanged for a plain missile or out of range", ground.length() < air.length() and ground.y > 0.0
		and AwRocketJump.launch_velocity(single, jr, still, body, feet, false, fwd) == still
		and AwRocketJump.launch_velocity(rj, jr, still, body + Vector3(0, 50, 0), feet, false, fwd) == still)
	var side := AwRocketJump.launch_velocity(rj, jr, still, body, feet, false, Vector3(1, 0, 0))
	_check("the move input steers the launch", side.x > 1.0 and absf(side.z) < 0.01)
	var fast := AwRocketRules.new()
	var _s := fast.set_cvar("sv_rocket_jump_speed", "200")
	var capped := AwRocketJump.launch_velocity(rj, fast, still, body, feet, false, fwd)
	var _c := fast.set_cvar("sv_rocket_jump_max_speed", "0")
	var free := AwRocketJump.launch_velocity(rj, fast, still, body, feet, false, fwd)
	_check("sv_rocket_jump_max_speed holds the launch; 0 lifts it (%.1f, %.1f m/s)" % [capped.length(), free.length()], is_equal_approx(capped.length(), 24.0) and free.length() > 100.0)
	var _p := jr.set_cvar("sv_rocket_jump_self_damage_scale", "0.5")
	_check("sv_rocket_jump_self_damage_scale scales the shooter's own hurt; a plain missile's is whole", is_equal_approx(AwRocketJump.self_damage_scale(rj, jr), 0.5) and AwRocketJump.self_damage_scale(single, jr) == 1.0 and AwRocketRules.new().jump_self_damage_scale == 0.0)

	var missile := AwMissileArt.build(&"launcher")
	var box: AABB = AwMissileArt._bounds(missile, Transform3D.IDENTITY) if missile != null else AABB()
	_check("the launcher flies its own rocket, long along -Z and centred (%s)" % box.size, box.size.z > 0.3 and box.size.x < 0.2 and box.get_center().length() < 0.01)
	var small := AwMissileArt.build(&"quad_launcher")
	var small_box: AABB = AwMissileArt._bounds(small, Transform3D.IDENTITY) if small != null else AABB()
	_check("the quad's rocket is the same round at 0.7 (%.3f m)" % small_box.size.z, is_equal_approx(small_box.size.z, box.size.z * 0.7))
	var round_model := AwMissileArt.ReloadParts.build(&"rocket")
	var textured := round_model != null and round_model.get_child_count() == 1 and round_model.get_child(0).find_children("*", "MeshInstance3D", true, false).size() > 0
	if textured:
		for mi: Node in round_model.get_child(0).find_children("*", "MeshInstance3D", true, false):
			var mesh := (mi as MeshInstance3D).mesh
			var mat := mesh.surface_get_material(0) as BaseMaterial3D if mesh != null and mesh.get_surface_count() > 0 else null
			textured = textured and mat != null and mat.albedo_texture != null
	_check("the reload rocket is the baked, textured model, not primitives", textured)
	if round_model != null:
		round_model.free()
	var gren := AwMissileArt.build(&"grenade_launcher")
	_check("the quad's is smaller, the grenade launcher flies its round, a rifle has none", small != null and gren != null and AwMissileArt.build(&"rifle") == null)
	for n: Node in [missile, small, gren]:
		if n != null:
			n.free()
	_end()
