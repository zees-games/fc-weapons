extends RefCounted

## fc-weapons' API level. The rule for bumping it is on [DotAddonApi].
##
## LEVEL rises by one for anything a game could call that did not exist before. OLDEST is
## raised to LEVEL when something a game could have called is removed or changes meaning.

# 1: role skins (role_art, art_rows, spawn_entries, credits) and the aw_* weapon clones.
# 2: AwWeaponPack owns 24 weapon definitions with plain ids (set_id_prefix, weapon_defs), 14 new
#    models, cfg/addons/fc_weapons/weapon/<id>.yml tuning, aims that keep the stock clear of the eye.
# 3: flash, smoke and incendiary weapons; AwGrenade (flight, bounce, stick, fuse), AwGrenadeBlast (falloff, blind, smoke,
#    fire events) and AwGrenadeRules (sv_grenade_* cvars).
# 4: AwUtilityZones (victims/line-of-sight adapter, fire-zone ticker, blast events to effects), AwBlindLedger (per-victim
#    capped blind clock) and AwGrenadeFx (dot-fx smoke, fire and blind defs and visuals). Nothing removed, OLDEST stays.
# 5: the smoke and fire cloud scenes ship in fx/ and AwGrenadeFx finds them itself (fx_dir optional); AwBlindLedger.strength
#    and the effect/blind-event "strength" (0..1, distance and facing scaled) so a screen can be as white as the flash was.
# 6: sound_classes(prefix) (id -> weapon-sound class) so a host's sound table classes lmg, the launchers and prefixed ids.
# 7: sound_classes() names nine new classes (lmg, battle, marksman, carbine, derringer, mpistol, autoshot, grenade, rail),
#    each a recording of its own in dot-audio's stock; a host that fed the old classes to set_class need change nothing.
# 8: the view runtime is the pack's own: AwWeaponCatalogue, AwWeaponArtTable, AwWeaponVisual, AwViewModel, AwWorldModel,
#    AwWeaponRig, AwWeaponNet, AwShotFx, AwWeaponSound, AwAdsRules (hip_zero 20 m) and the rest, a host needs no other weapon pack.
# 9: AwFxPool (fill, fill_flashes, take_shot_fx, take_charge_fx, shared_flash): a world model's shot effects, charge ball
#    and muzzle flashes built under a loading cover and taken on first use instead of being built in the tick.
# 10: AwWeaponRig.phase_timers, phase_us, phase_calls, PHASES: opt-in sub-phase timings of simulate_tick for a profiler.
# 11: AwShotFx.NO_IMPACT_GROUP and draws_impact: a shot on the sky (that group, or meta hull_kind "sky") draws no impact.
# 12: AwShotFx.round_profile, ROUNDS (tracer width, length and impact size per sound class), impact_stream and surface_of
#     (impact sound per surface and flesh), play_impact(at, normal, collider, weapon_class, shape).
# 13: AwModelCache.add_fallback_root / remove_fallback_root / fallback_roots / exists: a build without the addon's models (the web shell) draws them
#     from a mounted pack laid out like addons/fc_weapons/assets/.
# 14: AwWeaponGroups (group_of, groups_for, all_groups): the download group "weapon-<id>" of each weapon, as groups.json at the pack root defines them.
# 15: AwShotFx.prewarm_layers(): build a weapon's layered shot sound (dot-audio layers, enclosure, player) under a
#     loading cover; the first knife shot built them in the tick, 61 ms on a GPU box.
# 16: AwFxPool.layers_bus and shared_layers(fx, bus): fill() builds one layered shot every remote shooter shares, so
#     no shooter's first shot builds its own.
# 17: AwWeaponRig.would_idle(command): whether simulate_tick(command, tick, null) takes the idle path, so a host can skip its context.
# 18: AwShotLayers.fire(class, at, listener, weapon_id) plays the gun's own layered report (has_gun_sound, gun_of,
#     plays_gun); AwWorldModel.eject_transform() is where a held gun throws its case; gun_shot(gun) and gun_shot_id(id)
#     let a host's own shot player register and fire those reports.
# 19: attachments. AwAttachmentPack (catalogue, art_of, register_art, sound_class_for), AwAttachmentSockets (mounts_of, ensure);
#     each gun's def.mounts lists its mounts; AwSpawnProvider.attachment_defs and sound_class_for.
# 20: aimed motion. AwViewFeel mp_vm_ads_kick/_strafe/_bob (shares kept down the sights), mp_vm_scope_sway/_shake;
#     AwViewModel.scope_offset() and AwScopeOverlay.motion shift a scope's lens with a strafe, a walk and a shot.
# 21: inspect. AwViewModel.inspect() / cancel_inspect() / inspect_fraction() (AwWeaponPose.inspect and the inspect keys);
#     the holster has its own keys (AwWeaponPose.HOLSTER_KEYS, Tunables.holster_keys).
# 22: AwWorldModel.equip_budget_usec: past it, a frame's world-model equips build their models on later frames.
# 23: AwModelCache.shrink_textures_headless (default on): headless, a loaded model's textures become 4x4 downsamples.
# 24: AwWeaponRig.simulate_idle(command, tick): the idle tick for a host whose would_idle just answered true, without asking again.
# 25: scope body view. AwViewModel.scope_body / scope_body_relief / scope_body_active() / scope_ocular_points(), a scope style's
#     `ocular`: the gun stays up through a lens scope and AwScopeOverlay draws the zoomed picture into its ocular.
# 26: AwGrenadeSound (count, stream): the detonation recordings of the five thrown grenades, for a host to play where one goes off.
# 27: rockets and bounce. AwRocketRules (sv_rocket_*: single launcher's tube and blast, Rocketjump launch), AwRocketJump
#     (launch_velocity, self_damage_scale), the `warhead` mount and its Rocketjump, AwMissileArt.build(weapon_id);
#     AwGrenade.bounce_velocity / settles / damp_factor and sv_grenade_damping / _rest_speed / _max_bounces.
# 28: AwViewModel.on_windup(charge): a throw's hand draws back by the meter and releases from there; a blade pumps on a
#     sprint, and AwViewModel.run_amount() / run_phase() hand the stride to arms that pump the free hand.
# 29: a narrow hands lens at hands_depth_comp 0 keeps the authored place: AwViewModel.lens_move_share(), AwWeaponPose.lens_share /
#     lens_turn(angle, share), and AwWallSlam.offset's lens_share; the wall's closing is eased (CLOSING_RATE).
# 30: AwShotFxRules.crowd_frame (cl_shotfx_crowd_frame): most other shooters' shots drawn in one frame across the crowd.
# 31: AwWeaponRig.native_spread (and native_spread_active()): the hitscan spread tick in dot-sim's native class or in
#     GDScript, bit-exact either way; DOT_WEAPON_MIN, which AwWeaponRig.setup() checks and fails on.
# 32: the addon directory is addons/fc_weapons (was addons/arena_weapons) and its cfg cfg/addons/fc_weapons;
#     this file is fc_weapons_api.gd. Nothing a game calls changed meaning, so OLDEST stays.
const LEVEL := 32
const OLDEST := 1

## The oldest addons this pack runs on. dot-weapon is checked by AwWeaponRig.setup(); dot-sim is optional (without it,
## or older than DOT_SIM_MIN, the spread tick stays in GDScript).
const DOT_WEAPON_MIN := 42
const DOT_SIM_MIN := "1a28540"
