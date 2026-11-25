extends "aw_selftest_sight.gd"

## Headless suite: models load with the muzzle where the table says and the stock clear of the eye at the sights,
## the provider's contract, the pack's own weapon definitions, and a base art dressed by role.
## What it cannot see is how they look: tools/screenshot.sh in game-fatal-contact renders the hands.

const IronSight := preload("res://addons/gs_weapon/view/gs_weapon_iron_sight.gd")
const CHECKS := 622

func _ready() -> void:
	print("fc-weapons self-test")
	# The idle breath moves every pose a little; the motion checks below measure exact positions.
	AwWeaponPose.breathing = false
	_models()
	_download_groups()
	_no_uid_loads()
	_import_markers()
	_spans()
	_provider()
	_sound_classes()
	_sound_coverage()
	await _sound_hooks()
	_defs()
	_fire_feel()
	_dress()
	await _fire_fx()
	_own_sights()
	_scope_hides_gun()
	_scope_modes()
	_scope_body()
	_scope_align()
	_scope_glass()
	preload("aw_selftest_reload.gd").new(self).cues()
	preload("aw_selftest_reload.gd").new(self).drop_charge()
	await _floor_clip()
	await _near_plane_clip()
	await _shot_fx_pool()
	await _fx_pool()
	await _previews()
	_grenades()
	_rockets()
	_attachments()
	_utility()
	_glove_cache()
	_shared_catalogue()
	_mag_carve()
	_assets_pack()
	_headless_textures()
	_charge_fizzle()
	await _one_arm_set()
	_charge_fizzle()
	_idle_sleep()
	_mark_fade()
	_person_carry()
	await _equip_budget()
	_would_idle()
	_carrier_cache()
	_holster_and_inspect()
	_native_spread()
	preload("aw_selftest_throw.gd").new(self).run()
	preload("aw_selftest_lens.gd").new(self).run()
	await preload("aw_selftest_equip_cache.gd").new(self).run()
	preload("aw_selftest_sight_slices.gd").new(self).run()
	preload("aw_selftest_face_extent.gd").new(self).run()
	preload("aw_selftest_cycle.gd").new(self).run()
	preload("aw_selftest_bake.gd").new(self).run()
	await _finish()


## The rig's native spread switch is gs-weapon's static, both ways, and is live only with gs-sim's class loaded.
func _native_spread() -> void:
	_begin("native spread switch")
	var was := AwWeaponRig.native_spread
	AwWeaponRig.native_spread = not was
	var flipped := GSWeaponHitscan.native_tick == (not was)
	GSWeaponHitscan.native_tick = was
	_check("AwWeaponRig.native_spread sets and reads GSWeaponHitscan.native_tick", flipped and AwWeaponRig.native_spread == was)
	AwWeaponRig.native_spread = true
	var on := AwWeaponRig.native_spread_active()
	AwWeaponRig.native_spread = false
	var off := AwWeaponRig.native_spread_active()
	AwWeaponRig.native_spread = was
	_check("native_spread_active() is the switch and gs-sim's class together",
		on == ClassDB.class_exists(&"GSSimWeaponSpread") and not off)
	_end()


## The hand spans of every model (IronSight.spans: bare faces and one TriangleMesh) equal the per-triangle
## ray tests (IronSight.span) they replaced, which cost 60-400 ms a weapon of GDScript at load.
func _spans() -> void:
	_begin("hand spans, fast against reference")
	var holder := Node3D.new()
	add_child(holder)
	var worst := 0.0
	var compared := 0
	var mismatched := PackedStringArray()
	var ref_usec := 0
	var fast_usec := 0
	var all := AwWeaponArt.weapon_rows("")
	for role: StringName in all:
		var scene := load(str((all[role] as Dictionary)["model"])) as PackedScene
		if scene == null:
			continue
		var model := scene.instantiate() as Node3D
		holder.add_child(model)
		var forward := Vector3(0, 0, -1)
		var fractions := [0.62, 0.30]
		var t0 := Time.get_ticks_usec()
		var tris := IronSight.triangles_of(model, holder)
		var want: Array = []
		for fraction: float in fractions:
			want.append(IronSight.span(model, holder, forward, fraction, tris))
		var t1 := Time.get_ticks_usec()
		var got := IronSight.spans(IronSight.faces_of(model, holder), forward, fractions)
		var t2 := Time.get_ticks_usec()
		ref_usec += t1 - t0
		fast_usec += t2 - t1
		for k in fractions.size():
			var a: Dictionary = want[k]
			var b: Dictionary = got[k]
			compared += 1
			if a.is_empty() != b.is_empty():
				mismatched.append("%s[%d] empty %s vs %s" % [role, k, a.is_empty(), b.is_empty()])
				continue
			for key in a:
				var d := absf(float(a[key]) - float(b[key]))
				worst = maxf(worst, d)
				if d > 0.0001:
					mismatched.append("%s[%d].%s %f vs %f" % [role, k, key, a[key], b[key]])
		holder.remove_child(model)
		model.free()
	holder.queue_free()
	print("  spans: %d compared, worst difference %.7f m, reference %d ms, fast %d ms" % [compared, worst, ref_usec / 1000, fast_usec / 1000])
	_check("hand spans: %d compared, none differs (%s)" % [compared, ", ".join(mismatched)], compared > 20 and mismatched.is_empty())
	_end()


func _sound_classes() -> void:
	_begin("sound classes")
	var plain := AwWeaponPack.sound_classes("")
	var gun_ids := 0
	for id: StringName in AwWeaponPack.IDS:
		if id in [&"knife", &"frag", &"sticky", &"flash", &"smoke", &"incendiary"]:
			continue
		gun_ids += 1
		if not plain.has(id):
			_check("%s has a sound class" % id, false)
	_check("every gun has a sound class (%d)" % gun_ids, plain.size() == gun_ids)
	_check("lmg has its own sound class, not the rifle's", plain[&"lmg"] == &"lmg")
	_check("a prefix is applied to the ids", AwWeaponPack.sound_classes("aw_").has(&"aw_quad_launcher"))
	_check("the prefixed class is the same", AwWeaponPack.sound_classes("aw_")[&"aw_quad_launcher"] == &"launcher")
	_end()


func _sound_coverage() -> void:
	_begin("sound coverage")
	for id: StringName in AwWeaponPack.IDS:
		var gaps := AwSoundCoverage.gaps(id)
		_check("%s has every sound it needs %s" % [id, ", ".join(gaps)], gaps.is_empty())
	for id: StringName in AwGrenadeSound.STEMS:
		_check("%s has its own detonation takes (%d)" % [id, AwGrenadeSound.count(id)], AwGrenadeSound.count(id) >= 1 and AwGrenadeSound.stream(id, 1) != null)
	_check("an id that is not a grenade has none", AwGrenadeSound.stream(&"no_such_grenade") == null)
	_check("an unknown id has no gaps hidden: it reports missing sounds", not AwSoundCoverage.gaps(&"no_such_weapon").is_empty())
	# A gun's own handling cues: every file the manifest names exists and loads, and none sits in the folder unlisted.
	for gun: StringName in AwGunCues.CUES:
		var cues: Dictionary = AwGunCues.CUES[gun]
		for cue: StringName in cues:
			var found := 0
			for n in int(cues[cue]):
				if AwGunCues.stream(gun, cue, n) != null:
					found += 1
			_check("%s's cue %s has its %d files" % [gun, cue, int(cues[cue])], found == int(cues[cue]))
		var listed := 0
		for cue: StringName in cues:
			listed += int(cues[cue])
		var on_disk := 0
		for file in DirAccess.get_files_at(AwShotLayers.GUN_SOUNDS + String(gun)):
			if file.begins_with("cue_") and file.ends_with(".ogg"):
				on_disk += 1
		_check("%s has no cue file the manifest does not list (%d of %d)" % [gun, on_disk, listed], on_disk == listed)
	_check("the minigun's spin up, loop and down exist", AwGunCues.SPIN.all(func(part: StringName) -> bool: return AwGunCues.spin_stream(part) != null))
	_check("a gun with no cues of its own falls back to stock", AwGunCues.stream(&"aw_rifle", &"bolt_back", 0) == null and AwGunCues.stream(&"aw_sniper", &"mag_out", 0) == null)
	_end()


## The minigun's spin voice, the shotgun's own shell loads, and that the owner's raw recordings never ship.
func _sound_hooks() -> void:
	_begin("sound hooks")
	var spin := AwMinigunSpin.new()
	var dt := 1.0 / float(AwWeaponPack.TICK_RATE)
	_check("an idle minigun with the trigger up plays nothing", spin.step(false, dt) == &"" and not spin.active())
	_check("the trigger going down starts the spin up", spin.step(true, dt) == &"spin_up" and spin.active())
	var started := &""
	var ticks := 0
	while started == &"" and ticks < 200:
		started = spin.step(true, dt)
		ticks += 1
	_check("the loop follows the start after its length (%d ticks)" % ticks, started == &"spin_loop" and absf(float(ticks) * dt - AwMinigunSpin.UP_SEC) < 0.05)
	_check("held on, the loop plays on without restarting", spin.step(true, dt) == &"")
	_check("letting go winds down", spin.step(false, dt) == &"spin_down")
	var idle_ticks := 0
	while spin.active() and idle_ticks < 200:
		spin.step(false, dt)
		idle_ticks += 1
	_check("the wind-down ends in silence (%d ticks)" % idle_ticks, not spin.active() and absf(float(idle_ticks) * dt - AwMinigunSpin.DOWN_SEC) < 0.05)
	spin.step(true, dt)
	_check("letting go before it is up to speed winds down at once", spin.step(false, dt) == &"spin_down")
	_check("squeezing again in the wind-down spins up again", spin.step(true, dt) == &"spin_up")
	_check("a drop, switch or death stops it dead, once", spin.stop() and not spin.active() and not spin.stop())
	_check("the loop recording loops and the start and end do not", AwGunCues.spin_stream(&"spin_loop").get(&"loop") == true and AwGunCues.spin_stream(&"spin_up").get(&"loop") == false and AwGunCues.spin_stream(&"spin_down").get(&"loop") == false)
	var holder := Node3D.new()
	add_child(holder)
	var fx := AwShotFx.new()
	holder.add_child(fx)
	fx.play_spin(&"spin_loop", Vector3.ZERO)
	await get_tree().process_frame
	_check("the spin voice plays the loop", fx.spin_playing())
	fx.stop_spin()
	_check("stop_spin cuts it", not fx.spin_playing())
	var rig := AwWeaponRig.new()
	rig._fx = fx
	holder.add_child(rig)
	rig._spin.step(true, dt)
	fx.play_spin(&"spin_loop", Vector3.ZERO)
	rig.on_reset()
	_check("a reset stops the rig's spin and its voice", not rig._spin.active() and not fx.spin_playing())
	fx.play_spin(&"spin_loop", Vector3.ZERO)
	holder.remove_child(fx)
	_check("a shot fx leaving the tree takes its loop with it", not fx.spin_playing())
	holder.remove_child(rig)
	rig.free()
	fx.free()
	holder.queue_free()
	_check("the shotgun has its own shell loads", AwGunCues.stream(&"aw_shotgun", &"shell_load", 3) != null and AwGunCues.stream(&"aw_rifle", &"shell_load", 0) == null)
	_check("the AK has its own magazine and charging handle cues", AwGunCues.stream(&"aw_rifle", &"mag_out", 0) != null and AwGunCues.stream(&"aw_rifle", &"charge_back", 0) != null)
	var publish := FileAccess.get_file_as_string("res://tools/publish.sh")
	_check("publish.sh keeps assets-src (the raw recordings) out of the pack", publish.contains("--exclude-dir assets-src"))
	var shipped_from_src := 0
	for gun: StringName in AwGunCues.CUES:
		for file in DirAccess.get_files_at(AwShotLayers.GUN_SOUNDS + String(gun)):
			if "assets-src" in AwShotLayers.GUN_SOUNDS + file:
				shipped_from_src += 1
	_check("no shipped sound lives under assets-src", shipped_from_src == 0 and not AwShotLayers.GUN_SOUNDS.contains("assets-src"))
	_end()


func _models() -> void:
	_begin("models")
	var all := AwWeaponArt.weapon_rows("")

	for role: StringName in all:
		var row: Dictionary = all[role]
		var path := str(row["model"])
		_check("%s: %s exists" % [role, path.get_file()], ResourceLoader.exists(path))
		var scene := load(path) as PackedScene
		_check("%s loads as a scene" % role, scene != null)

		if scene == null or row["motion"] != "gun":
			continue

		var node := scene.instantiate() as Node3D
		var box := _aabb(node, Transform3D.IDENTITY)
		var rear_top := _rear_top(node, Transform3D.IDENTITY, float(row["muzzle"]), -INF, Vector3.ZERO)
		var mark := node.find_child("sight_rear", true, false) as Node3D
		if mark != null:
			rear_top = mark.transform.origin
		node.free()
		if rear_top != Vector3.ZERO:
			var aim_in: Vector3 = (row["view"] as Dictionary).get("aim", Vector3.ZERO)
			var low := rad_to_deg(atan2(rear_top.y + aim_in.y, -(aim_in.z + rear_top.z)))
			_check("%s: the rear sight sits %.2f degrees off the crosshair, under 0.15" % [role, low], absf(low) < 0.15)
		_check("%s: the barrel end is %.3f m ahead of the grip, as the table says" % [role, row["muzzle"]], absf(-box.position.z - float(row["muzzle"])) < 0.02)
		_check("%s: a gun, not a tiny prop (%.2f m long)" % [role, box.size.z], box.size.z > 0.08 and box.size.z < 1.6)
		var aim: Vector3 = (row["view"] as Dictionary).get("aim", Vector3.ZERO)
		_check("%s: at the sights the stock ends %.2f m ahead of the eye" % [role, -(aim.z + box.end.z)], aim.z + box.end.z < -0.1)

	for prop in AwWeaponArt.PROPS:
		_check("prop %s ships" % prop, ResourceLoader.exists(AwWeaponArt.model_path(prop)))
	_end()


## groups.json: every non-core weapon's model sits in its own group and a core weapon's in none.
func _download_groups() -> void:
	_begin("download groups")
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://groups.json"))
	_check("groups.json is an object", doc is Dictionary)
	var groups: Dictionary = doc if doc is Dictionary else {}
	_check("one group per weapon but the two core ones", groups.size() == AwWeaponPack.IDS.size() - AwWeaponGroups.CORE.size())
	var uncovered: Array[String] = []
	for id: StringName in AwWeaponArt.WEAPONS:
		var g := AwWeaponGroups.group_of(id)
		var model := String(AwWeaponArt.WEAPONS[id]["model"])
		if g == "":
			continue
		var found := false
		for pattern: String in groups.get(g, []):
			if pattern.contains("assets/models/" + model + "."):
				found = true
		if not found:
			uncovered.append(String(id))
	_check("every grouped weapon's model is in its group (missing: %s)" % ", ".join(uncovered), uncovered.is_empty())
	_check("the core weapons have no group", AwWeaponGroups.group_of(&"knife") == "" and AwWeaponGroups.group_of(&"pistol") == "")
	_check("groups_for skips core and unknown ids and repeats", AwWeaponGroups.groups_for([&"knife", &"rifle", &"rifle", &"nope"]) == PackedStringArray(["weapon-rifle"]))
	_check("all_groups is every group groups.json defines", AwWeaponGroups.all_groups().size() == groups.size())
	var stray: Array[String] = []
	for name: String in AwWeaponGroups.all_groups():
		if not groups.has(name):
			stray.append(name)
	_check("every group the code names is in groups.json", stray.is_empty())
	_check("the sniper's textures are extracted, so its model is a few hundred KB, not 4.8 MB", FileAccess.file_exists("res://addons/fc_weapons/assets/models/sniper_ph_bolt_action_rifle_7_62_diff.jpg"))
	_end()


## A pack mounted as an overlay does not register its uids ("Unrecognized UID" on the web), so a
## shipped script names other files by path. Any "uid:// string in a .gd under the addon fails this.
func _no_uid_loads() -> void:
	_begin("no uid loads")
	var hits: Array[String] = []
	_scan_uid_strings("res://addons/fc_weapons", hits)
	_check("no shipped script names a file by uid (%s)" % ", ".join(hits), hits.is_empty())
	_end()


## A marker whose imported scene is missing (an import cut short on a server) is no model, said once,
## instead of a load that fails with engine errors; a shipped model's marker still counts.
func _import_markers() -> void:
	_begin("import markers")
	var shipped := "res://addons/fc_weapons/assets/models/%s.glb" % String(AwWeaponArt.WEAPONS[&"pistol"]["model"])
	_check("a shipped model's marker has its output", AwModelCache._imported(shipped))
	var fake := "user://aw_selftest_marker.glb"
	var f := FileAccess.open(fake + ".import", FileAccess.WRITE)
	f.store_string('[remap]\nimporter="scene"\ntype="PackedScene"\npath="res://.godot/imported/aw_selftest_missing.scn"\n')
	f.close()
	_check("a marker naming a missing output is not imported", not AwModelCache._imported(fake))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fake + ".import"))
	_end()


func _scan_uid_strings(dir: String, hits: Array[String]) -> void:
	for sub: String in DirAccess.get_directories_at(dir):
		_scan_uid_strings(dir.path_join(sub), hits)
	for file: String in DirAccess.get_files_at(dir):
		if file.get_extension() != "gd":
			continue
		var path := dir.path_join(file)
		if FileAccess.get_file_as_string(path).contains("\"uid://"):
			hits.append(path)


func _provider() -> void:
	_begin("provider contract")
	var rows := AwSpawnProvider.art_rows()
	var entries := AwSpawnProvider.spawn_entries()
	_check("one art row per weapon this pack defines", rows.size() == AwWeaponPack.IDS.size() and AwWeaponArt.WEAPONS.size() == AwWeaponPack.IDS.size())
	var pistol := AwWeaponArt.row_of(&"pistol")
	_check("the pistol row keeps its own hand scale, not the tier's 0.36", is_equal_approx(float(pistol["hand_scale"]), 0.5))
	_check("the pistol row slims its forearm so it does not fill the lower right", float(pistol.get("forearm_scale", 1.0)) < 1.0)
	_check("the pistol row names a support grip", (pistol["support_grip"] as Vector3).is_finite())
	_check("the grenade launcher is drawn smaller than a long gun", float(AwWeaponArt.row_of(&"grenade_launcher")["view"]["scale"]) < 0.5)
	_check("a pistol keeps the runtime's wall defaults", AwWeaponArt.wall_row(&"pistol").is_empty())
	_check("a rifle retreats deeper from a wall than the 0.34 m default", float(AwWeaponArt.wall_row(&"rifle")["wall_max"]) > 0.34)
	_check("a launcher retreats deeper than a rifle", float(AwWeaponArt.wall_row(&"launcher")["wall_max"]) > float(AwWeaponArt.wall_row(&"rifle")["wall_max"]))
	_check("the launcher keeps the world pull from shrinking it below 0.9 so a wall no longer swallows the hands", is_equal_approx(float(AwWeaponArt.row_of(&"launcher")["view"]["pull_min"]), 0.9))
	_check("a knife shortens its wall reach", float(AwWeaponArt.wall_row(&"knife")["wall_reach"]) < 1.0)
	var rifle_def := AwWeaponPack.weapons({}, "", false).filter(func(d: GSWeaponDef) -> bool: return d.id == &"rifle")[0] as GSWeaponDef
	_check("the rifle def carries its wall row in params.ads", (rifle_def.params["ads"] as Dictionary).has("wall_max"))
	var rules := AwAdsRules.new()
	rules.set_def_row(&"rifle", rifle_def.params["ads"])
	_check("the ADS rules accept the rifle's wall row whole", float(rules.wall_for(&"rifle")["max"]) == float((rifle_def.params["ads"] as Dictionary)["wall_max"]))
	_check("every weapon id carries the pack prefix", rows.keys().all(func(k: StringName) -> bool: return String(k).begins_with("aw_")))
	_check("one spawn entry per weapon", entries.size() == rows.size())
	_check("role_art is keyed by role, not by this pack's ids", AwSpawnProvider.role_art().has(&"rifle") and not AwSpawnProvider.role_art().has(&"aw_rifle"))
	var credit := AwSpawnProvider.credits()[0]
	_check("the credit names Styloo, CC0 and the page", credit["author"] == "Styloo" and str(credit["licence"]).begins_with("CC0") and str(credit["url"]).begins_with("https://styloo.itch.io/"))
	# Free licences only: CC0, or CC BY / MIT with the author named (the credit is the attribution they ask for).
	_check("every credit is CC0, CC BY or MIT with a page and, past CC0, an author", AwSpawnProvider.credits().all(_free_credit))
	AwSpawnProvider.set_id_prefix("")
	var plain := AwSpawnProvider.art_rows()
	_check("a host that owns the plain ids gets `rifle`, not `aw_rifle`", plain.has(&"rifle") and not plain.has(&"aw_rifle") and AwSpawnProvider.role_art().is_empty())
	AwSpawnProvider.set_id_prefix(AwSpawnProvider.DEFAULT_PREFIX)
	_end()


func _defs() -> void:
	_begin("the pack's own weapon definitions")
	var defs := AwSpawnProvider.weapon_defs()
	_check("every pack weapon has a definition", defs.size() == AwWeaponPack.IDS.size() and AwWeaponPack.errors.is_empty())
	var ids := {}
	var tiered := true
	for def in defs:
		ids[def.id] = true
		var n := 0
		for t: StringName in [&"sidearm", &"primary", &"heavy", &"melee", &"thrown"]:
			n += 1 if def.tags.has(t) else 0
		tiered = tiered and n == 1
	_check("ids are unique", ids.size() == defs.size())
	_check("each has exactly one tier tag", tiered)
	_check("the rifle is a primary with a magazine", _def(defs, &"aw_rifle").slot == AwWeaponPack.SLOT_PRIMARY and _def(defs, &"aw_rifle").magazine > 0)
	_check("the quad launcher fires the launcher's ammunition", _def(defs, &"aw_quad_launcher").ammo_type == _def(defs, &"aw_launcher").ammo_type)
	_check("default layout: the frag is on the thrown slot, the sniper on the heavy slot", _def(defs, &"aw_frag").slot == AwWeaponIds.thrown_slot() and _def(defs, &"aw_sniper").slot == AwWeaponIds.heavy_slot() and AwWeaponIds.thrown_slot() == AwWeaponIds.SLOT_THROWN)
	_check("one weapon per slot at least", [1, 2, 3, 4, 5].all(func(s: int) -> bool: return defs.any(func(d: GSWeaponDef) -> bool: return d.slot == s)))
	var rifle_modes := _def(defs, &"aw_rifle").allowed_fire_modes()
	_check("the rifle's selector offers semi, burst and auto", rifle_modes.size() == 3 and rifle_modes.has(GSWeaponDef.Fire.AUTO) and rifle_modes.has(GSWeaponDef.Fire.SEMI))
	_check("the pistol's selector has no auto it cannot fire", not _def(defs, &"aw_pistol").allowed_fire_modes().has(GSWeaponDef.Fire.AUTO))
	_check("the smg's selector offers more than one mode", _def(defs, &"aw_smg").allowed_fire_modes().size() > 1)
	_check("every selector starts on a mode its gun allows", defs.all(func(d: GSWeaponDef) -> bool: return d.allowed_fire_modes().has(d.fire_mode)))
	# As a host's registered source: it must not recurse through the host's own weapons().
	AwWeaponCatalogue.add_source(&"aw_selftest", Callable(AwSpawnProvider, &"weapon_defs"))
	var hosted := AwWeaponCatalogue.weapons()
	AwWeaponCatalogue.remove_source(&"aw_selftest")
	var found := 0
	for d in hosted:
		found += 1 if String(d.id).begins_with("aw_") else 0
	_check("registered as a catalogue source, every weapon joins the catalogue once", found == defs.size())
	_check("and the catalogue is the host's plus the pack's", hosted.size() == AwWeaponCatalogue.weapons().size() + defs.size())
	_end()


## Each gun's drawn kick (presentation only) as measured off the pose spring: one shot from rest, 120 frames a second.
## Returns [peak camera pitch, peak gun pitch, peak push-back, camera pitch left after a second].
func _kick_trace(params: Dictionary, recoil: Vector2, interval: float) -> Array[float]:
	var pose := AwWeaponPose.make()
	pose.tunables.apply_kick(params)
	pose.fire_interval = interval
	pose.punch(recoil, true)
	var out: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for i in range(120):
		pose.advance(1.0 / 120.0, Vector2.ZERO, 0.0, true)
		out[0] = maxf(out[0], pose.view_punch().x)
		out[1] = maxf(out[1], pose._kick_rotation.x + pose._extra_pitch)
		out[2] = maxf(out[2], pose._kick + pose._extra_back)
	out[3] = absf(pose.view_punch().x)
	return out


## The sniper's shot climbs and shoves the gun and turns the camera well past the old default; an automatic's gun climbs
## more while its camera share stays near the bullets' own climb; every kick settles; the bullets' recoil is untouched.
func _fire_feel() -> void:
	_begin("per-weapon fire feel")
	var defs := AwSpawnProvider.weapon_defs()
	var shot := func(id: StringName, own: bool) -> Array[float]:
		var d := _def(defs, id)
		var b := d.tuning as GSWeaponBallistics
		var interval := float(d.use_interval_ticks) / float(AwWeaponPack.TICK_RATE)
		return _kick_trace(d.params if own else {}, Vector2(b.recoil_pitch, b.recoil_yaw), interval)
	var sniper: Array[float] = shot.call(&"aw_sniper", true)
	var sniper_old: Array[float] = shot.call(&"aw_sniper", false)
	var rifle: Array[float] = shot.call(&"aw_rifle", true)
	var rifle_old: Array[float] = shot.call(&"aw_rifle", false)
	print("  sniper camera %.2f deg (was %.2f), gun %.2f deg (was %.2f), back %.3f m (was %.3f); rifle camera %.2f (was %.2f), gun %.2f (was %.2f)" % [
		sniper[0], sniper_old[0], sniper[1], sniper_old[1], sniper[2], sniper_old[2], rifle[0], rifle_old[0], rifle[1], rifle_old[1]])
	_check("a sniper shot turns the camera at least 4 degrees, 2.5 times the default", sniper[0] >= 4.0 and sniper[0] >= sniper_old[0] * 2.5)
	_check("a sniper shot climbs the gun at least 12 degrees and shoves it back at least 8 cm", sniper[1] >= 12.0 and sniper[2] >= 0.08)
	_check("a rifle shot climbs the gun 1.4 times the default, its camera within 0.8 to 1.3 times", rifle[1] >= rifle_old[1] * 1.4 and rifle[0] >= rifle_old[0] * 0.8 and rifle[0] <= rifle_old[0] * 1.3)
	_check("every kick has settled a second later", sniper[3] < 0.05 and rifle[3] < 0.05)
	var sim_kept := (_def(defs, &"aw_sniper").tuning as GSWeaponBallistics).recoil_pitch == (AwWeaponPack.sniper().tuning as GSWeaponBallistics).recoil_pitch \
		and not _def(defs, &"aw_sniper").params.has(&"recoil_pitch")
	_check("the feel lives in params only: the bullets' recoil is the ballistics' own", sim_kept and (AwWeaponPack.sniper().tuning as GSWeaponBallistics).recoil_pitch == 4.0)
	_end()


func _dress() -> void:
	_begin("dressing a base art by role")
	AwWeaponArtTable.drop_cache()
	var before := AwWeaponArtTable.rifle()
	var rows := AwSpawnProvider.role_art()
	var art := AwWeaponVisual.make(&"rifle")
	AwArtDress.apply(art, rows[&"rifle"])
	_check("the model is this pack's", art.model_path == AwWeaponArt.model_path("rifle"))
	_check("the muzzle is the table's", is_equal_approx(art.muzzle_distance, 0.573))
	# The rifle's origin is its grip, under the bore: the flash starts on the barrel's axis, measured from its end.
	_check("the muzzle sits up on the bore, not on the grip's axis (%.3f m up)" % art.muzzle_offset.y, art.muzzle_offset.y > 0.015 and absf(art.muzzle_offset.z) < 0.001)
	_check("the base art itself is untouched until a game applies it", before.model_path != art.model_path)
	var drift := _bore_drift()
	_check("every gun row's written bore is its model's, within a millimetre: %s" % ", ".join(drift), drift.is_empty())
	_check("a grenade dressed keeps the throw carry", _thrown())
	_check("every gun row names its own reload style: %s" % ", ".join(_unstyled()), _unstyled().is_empty())
	var belt_bad := _style_mismatch("belt", "belt_feed", true)
	_check("every belt-reload gun draws a moving belt (belt_feed): %s" % ", ".join(belt_bad), belt_bad.is_empty())
	var feed_bad := _style_mismatch("belt", "belt_feed", false)
	_check("and nothing else is marked belt_feed: %s" % ", ".join(feed_bad), feed_bad.is_empty())
	var rev_bad: Array[String] = []
	var all_rows := AwWeaponArt.weapon_rows("")
	for role: StringName in all_rows:
		var reload: Dictionary = (all_rows[role] as Dictionary).get("reload", {})
		if str(reload.get("style", "")) == "revolver" and all_rows[role].get("tier", "") != "sidearm":
			rev_bad.append(String(role))
	_check("revolver-style reloads are sidearms: %s" % ", ".join(rev_bad), rev_bad.is_empty())
	_end()


## Roles breaking "reload style [param style] iff [param key] is set"; [param want] picks the direction checked.
## Gun rows whose `muzzle_offset` is missing or is not what AwModelCache.muzzle_bore measures on the model.
func _bore_drift() -> Array[String]:
	var out: Array[String] = []
	for id: StringName in AwWeaponArt.WEAPONS:
		var row: Dictionary = AwWeaponArt.row_of(id)
		if row["motion"] != "gun":
			continue
		var written: Variant = row.get("muzzle_offset")
		var measured := AwModelCache.muzzle_bore(str(row["model"]), Vector3.FORWARD)
		if not written is Vector3 or (written as Vector3).distance_to(measured) > 0.001:
			out.append("%s %s, model %s" % [id, written, measured])
	return out


func _style_mismatch(style: String, key: String, want: bool) -> Array[String]:
	var out: Array[String] = []
	var rows := AwWeaponArt.weapon_rows("")
	for role: StringName in rows:
		var row: Dictionary = rows[role]
		var is_style := str((row.get("reload", {}) as Dictionary).get("style", "")) == style
		var has_key := bool(row.get(key, false))
		if (want and is_style and not has_key) or (not want and has_key and not is_style):
			out.append(String(role))
	return out


## Gun rows whose `reload` names no known style (the view model would play the generic reload).
func _unstyled() -> Array[String]:
	var out: Array[String] = []
	var rows := AwWeaponArt.weapon_rows("")
	for role: StringName in rows:
		var row: Dictionary = rows[role]
		var style := str((row.get("reload", {}) as Dictionary).get("style", ""))
		if row["motion"] == "gun" and not style in ["magazine", "pistol", "revolver", "tube", "bolt", "belt", "launcher", "cell"]:
			out.append(String(role))
	return out


## A person's gun-arm carry, as gs-player-char API 22 draws it: what a held gun told it.
class FakeCarry extends RefCounted:
	var kinds: Array = []
	var fires := 0
	var raised := false
	var reloading := false
	var switching := false

	func set_class(kind: Variant) -> void:
		kinds.append(kind)

	func fired() -> void:
		fires += 1


## A person the held gun finds by its swing and set_hold, carrying [member carry].
class FakePerson extends Node3D:
	var carry: Variant = FakeCarry.new()

	func swing(_which: StringName) -> void:
		pass

	func set_hold(_kind: int) -> void:
		pass


## A held gun on a person with a carry hands it the class, the shot, the reload and the switch, and draws no kick
## or reload dip of its own; on a person without one it still does.
func _person_carry() -> void:
	_begin("a held gun hands its kick and reload to the person's carry")
	var person := FakePerson.new()
	add_child(person)
	var held := AwWorldModel.new()
	person.add_child(held)
	var carry: FakeCarry = person.carry
	held.equip(_dressed(&"shotgun"))
	held.advance(0.02)
	_check("the shotgun sets the shotgun carry (%s)" % [carry.kinds], carry.kinds == [&"shotgun"])
	held.advance(0.02)
	_check("once, not every frame", carry.kinds.size() == 1)
	held.on_fired(Vector2(1.0, 0.1))
	_check("a shot is the carry's, with no kick of the model's own (%.3f)" % held._kick, carry.fires == 1 and held._kick == 0.0)
	held.on_reloading(true)
	held.advance(0.4)
	_check("a reload is the carry's, with no dip of the model's own", carry.reloading
		and held._holder.position.is_equal_approx(held._rest().origin))
	held.on_reloading(false)
	held.on_switching(true)
	held.on_aiming(true)
	_check("the switch and the aim reach it", carry.switching and carry.raised and not carry.reloading)
	held.on_switching(false)
	held.equip(_dressed(&"knife"))
	held.advance(0.02)
	_check("a knife clears the class (%s)" % [carry.kinds], carry.kinds.size() == 2 and carry.kinds[1] == null)
	var classes := {}
	AwWeaponSound.set_class(&"aw_drum_shotgun", &"autoshot")
	for id: StringName in [&"pistol", &"sniper", &"marksman", &"smg", &"lmg", &"minigun", &"launcher", &"rifle", &"aw_drum_shotgun"]:
		classes[id] = AwWorldModel.carry_class(_dressed(id))
	AwWeaponSound.set_class(&"aw_drum_shotgun", &"")
	_check("guns read as the carry's classes, a prefixed id by its host's sound class (%s)" % [classes], classes == {
		&"pistol": &"pistol", &"sniper": &"sniper", &"marksman": &"sniper", &"smg": &"smg", &"lmg": &"rifle",
		&"minigun": &"heavy", &"launcher": &"heavy", &"rifle": &"rifle", &"aw_drum_shotgun": &"shotgun"})
	held.equip(_dressed(&"rifle"))
	held.advance(0.02)
	AwWorldModel.person_carry = false
	held.advance(0.02)
	held.on_fired(Vector2(1.0, 0.1))
	var off_kinds := carry.kinds.duplicate()
	held.advance(0.02)
	AwWorldModel.person_carry = true
	_check("switched off, the carry is cleared once and the model kicks again (%s)" % [off_kinds],
		off_kinds == [&"shotgun", null, &"rifle", null] and carry.kinds.size() == 4 and carry.fires == 1 and held._kick > 0.0)
	held.advance(0.02)
	_check("switched back on, the class returns (%s)" % [carry.kinds], carry.kinds.size() == 5 and carry.kinds[4] == &"rifle")
	person.free()

	var bare := Node3D.new()
	add_child(bare)
	var alone := AwWorldModel.new()
	bare.add_child(alone)
	alone.equip(_dressed(&"rifle"))
	alone.on_fired(Vector2(1.0, 0.1))
	_check("without a carry a shot still kicks the model (%.3f)" % alone._kick, alone._kick > 0.0)
	alone.on_reloading(true)
	alone.advance(0.4)
	_check("and a reload still dips it", alone._holder.position.y < alone._rest().origin.y - 0.01)
	bare.free()
	_end()


## A map change equips every respawned person's held gun in one frame; past
## [member AwWorldModel.equip_budget_usec] the model waits for a later frame, but what is held does not.
func _equip_budget() -> void:
	_begin("held guns past a frame's equip budget build on a later frame")
	var bare := Node3D.new()
	add_child(bare)
	var first := AwWorldModel.new()
	var second := AwWorldModel.new()
	bare.add_child(first)
	bare.add_child(second)
	await get_tree().process_frame
	AwWorldModel.equip_budget_usec = 1
	first.equip(_dressed(&"rifle"))
	second.equip(_dressed(&"shotgun"))
	_check("the frame's first gun builds at once", first.describe().has_model)
	_check("the next waits, already holding the shotgun (%s)" % second.equipped(),
		not second.describe().has_model and second.equipped() == &"shotgun")
	await get_tree().process_frame
	await get_tree().process_frame
	AwWorldModel.equip_budget_usec = 0
	_check("a frame later it has its model", second.describe().has_model)
	bare.free()
	_end()


## A held gun asks once whether a rig beside it draws its shots, and asks again when a rig comes or goes or the gun moves.
func _carrier_cache() -> void:
	_begin("world model: whether its carrier draws its own shots")
	var carrier := Node3D.new()
	var bare := Node3D.new()
	add_child(carrier)
	add_child(bare)
	var held := AwWorldModel.new()
	held.effects = false
	carrier.add_child(held)
	var before := held._carrier_draws_its_own()
	var rig := AwWeaponRig.new()
	rig._fx = AwShotFx.new()
	carrier.add_child(rig)
	_check("a rig with its own effects arriving beside the gun is seen", held._carrier_draws_its_own())
	held.reparent(bare)
	_check("the gun moved away from that rig asks again", held._carrier_draws_its_own() == before)
	held.reparent(carrier)
	_check("and back beside it, sees it again", held._carrier_draws_its_own())
	var fx := rig._fx
	carrier.remove_child(rig)
	_check("the rig gone, the gun draws its own again", held._carrier_draws_its_own() == before)
	rig.free()
	fx.free()
	carrier.queue_free()
	bare.queue_free()
	_end()



func _finish() -> void:
	print("")
	print("%d sections entered, %d finished, %d checks, %d failed" % [_entered, _finished, _checks, _failures])
	var passed := _failures == 0 and _entered == _finished and _checks == CHECKS
	if _checks != CHECKS:
		print("!! %d checks ran, %d expected. A section aborted part-way." % [_checks, CHECKS])
	print("RESULT: %s" % ("PASS" if passed else "FAIL"))
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0 if passed else 1)


func _free_credit(c: Dictionary) -> bool:
	var lic := str(c["licence"])
	var named := not str(c.get("author", "")).is_empty()
	var free := lic.begins_with("CC0") or ((lic.begins_with("CC BY") or lic.begins_with("CC-BY") or lic.begins_with("MIT")) and named)
	return free and str(c["url"]).begins_with("https://")
