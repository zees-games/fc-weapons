class_name AwWeaponArt
extends RefCounted

## The one file with a filename in it: which model each of [AwWeaponPack]'s weapons wears and how it is held.
## A model's origin is at the grip, its muzzle toward -Z, in metres (tools/bake_models.py makes them so).

const MODEL_DIR := "res://addons/fc_weapons/assets/models"
const ID_PREFIX := "aw_"

const _SIDEARM := {"hold": Vector3(0.14, -0.13, -0.32), "rot": Vector3(0, 8, 22), "scale": 1.0, "zoom": 0.9}
const _LONG := {"hold": Vector3(0.14, -0.05, -0.38), "rot": Vector3(0, 10, 30), "scale": 0.7, "zoom": 0.8}
const _HEAVY := {"hold": Vector3(0.16, -0.07, -0.42), "rot": Vector3(0, 10, 26), "scale": 0.55, "zoom": 0.8}

## weapon id -> {model, muzzle, motion, tier, reload, view}; `reload` is the view model's reload phases, `aim` is tools/measure_sights.py's. `view` without hold/rot/scale/zoom takes its tier's;
## a `scope` style's `ocular` is [x, y, z, radius] of the eye-end glass; `ads` is the row's own AwAdsRules keys; `muzzle_offset` is the bore's end off the grip's axis (AwModelCache.muzzle_bore), written here so no model loads;
## `thrown_span` sizes a grenade in the hand; `mag_node`, `hand_grip`, `bolt_node` and `bolt_travel` name model parts a reload or bolt cycle moves (AwWeaponVisual).
const WEAPONS := {
	&"knife": {"model": "combat_knife", "world_scale": 1.0, "world_rotation": Vector3(130.0, 0.0, 0.0), "hands_life": 1.0, "grip_socket": Vector3(0.0, -0.035, 0.03), "muzzle": 0.0, "motion": "melee", "tier": "melee", "view": {"rot": Vector3(55, 80, 75), "scale": 1.5, "hold": Vector3(0.19, -0.17, -0.40)}},
	&"pistol": {"model": "pistol_ph", "measured_grip": true, "mag_node": "magazine", "muzzle": 0.151, "muzzle_offset": Vector3(-0.0005, 0.0526, 0.0000), "tier": "sidearm", "reload": {"style": "pistol"}, "support_grip": Vector3(-0.028, 0.004, -0.004), "grip_socket": Vector3(-0.012, 0.02, 0.004), "hand_scale": 0.5, "forearm_scale": 0.85, "view": {"hold": Vector3(0.12, -0.06, -0.36), "scale": 1.25, "aim": Vector3(0.002, -0.063, -0.332)}},
	&"revolver": {"model": "revolver", "measured_grip": true, "ejects": false, "muzzle": 0.231, "muzzle_offset": Vector3(0.0000, 0.1104, 0.0000), "tier": "sidearm", "reload": {"style": "revolver", "hands": {"open": {"left": ["cylinder", [0.0, -0.05, -0.03]]}, "dump": {"left": ["cylinder", [0.0, -0.03, -0.02]]}}}, "grip_socket": Vector3(0.0, -0.015, 0.058), "view": {"scale": 0.8, "aim": Vector3(0.000, -0.135, -0.350)}},
	&"machine_pistol": {"world_scale": 2.0, "hands_life": 1.0, "model": "machine_pistol", "measured_grip": true, "muzzle": 0.274, "muzzle_offset": Vector3(0.0000, 0.1271, 0.0000), "tier": "sidearm", "reload": {"style": "pistol", "anchors": {"below": [0.0, -0.13, 0.0], "pouch": [-0.06, -0.1, -0.03]}}, "support_grip": Vector3(-0.03, -0.06, 0.05), "hand_scale": 0.4, "view": {"hold": Vector3(0.10, 0.0, -0.36), "rot": Vector3(0, 5, 4), "scale": 0.3, "aim": Vector3(0.000, -0.174, -0.309)}},
	&"derringer": {"model": "derringer", "measured_grip": true, "ejects": false, "muzzle": 0.120, "muzzle_offset": Vector3(0.0000, 0.0292, 0.0000), "tier": "sidearm", "reload": {"style": "launcher", "round": "round", "case": "casing", "prop_scale": 4.0, "anchors": {"breech": [0.0, 0.03, 0.03], "pouch": [-0.07, -0.15, 0.05], "near": [-0.03, -0.08, 0.04]}}, "support_grip": Vector3(-0.03, -0.05, 0.02), "view": {"hold": Vector3(0.10, 0.0, -0.36), "scale": 0.55, "aim": Vector3(0.000, -0.063, -0.330)}},
	&"smg": {"model": "smg", "clear_box": [-0.0165, -0.075, -0.143, 0.033, 0.111, 0.27], "forearm_scale": 1.35, "mag_node": "mac10magazine_low", "world_scale": 2.2, "hands_life": 1.0, "muzzle": 0.143, "muzzle_offset": Vector3(0.0000, -0.0029, 0.0000), "tier": "primary", "wall": {"wall_max": 0.35}, "reload": {"style": "magazine", "prop_scale": 2.3, "gun_scale": 1.6, "anchors": {"below": [0.0, -0.11, -0.06], "pouch": [-0.07, -0.17, -0.16]}}, "view": {"aim": Vector3(0.000, -0.036, -0.400), "scale": 1.7, "zoom": 0.85}},
	&"carbine": {"world_scale": 1.8, "hands_life": 1.0, "model": "carbine", "mag_node": "akmagazine_low_001", "fore_along": 0.68, "muzzle": 0.548, "muzzle_offset": Vector3(0.0000, 0.0315, 0.0000), "tier": "primary", "reload": {"style": "magazine", "rock": 22.0, "anchors": {"below": [0.0, -0.12, -0.12], "pouch": [-0.07, -0.2, -0.2]}}, "view": {"rot": Vector3(0, 4, 8), "aim": Vector3(-0.007, -0.090, -0.227), "scale": 0.5}},
	&"rifle": {"world_scale": 1.35, "hands_life": 1.0, "model": "rifle", "mag_node": "magazine", "bolt_node": "bolt", "bolt_travel": 0.07, "fore_along": 0.68, "muzzle": 0.573, "muzzle_offset": Vector3(-0.0001, 0.0272, 0.0000), "tier": "primary", "reload": {"style": "magazine", "rock": 22.0, "anchors": {"below": [0.0, -0.12, -0.12], "pouch": [-0.07, -0.2, -0.2]}}, "view": {"aim": Vector3(-0.006, -0.077, -0.432)}},
	&"bullpup": {"model": "bullpup", "measured_grip": true, "muzzle": 0.451, "muzzle_offset": Vector3(-0.0001, 0.0932, 0.0000), "tier": "primary", "reload": {"style": "magazine", "prop_scale": 2.3, "gun_scale": 1.6, "anchors": {"below": [0.0, -0.11, -0.06], "pouch": [-0.07, -0.17, -0.16]}}, "ads": {"red_dot_window": 2.5}, "view": {"sight": "red_dot", "scale": 0.38, "aim": Vector3(0.000, -0.278, -0.451)}},
	&"battle_rifle": {"model": "battle_rifle", "measured_grip": true, "mag_node": "magazine", "muzzle": 0.672, "muzzle_offset": Vector3(0.0000, 0.0623, 0.0000), "fore_along": 0.62, "tier": "primary", "reload": {"style": "magazine", "rock": 18.0, "anchors": {"below": [0.0, -0.13, -0.14], "pouch": [-0.08, -0.2, -0.2]}}, "view": {"aim": Vector3(0.000, -0.112, -0.503)}},
	&"burst_rifle": {"model": "burst_rifle", "measured_grip": true, "mag_node": "magazine", "bolt_node": "bolt", "bolt_travel": 0.07, "fore_along": 0.68, "muzzle": 0.579, "muzzle_offset": Vector3(0.0000, 0.0146, 0.0000), "tier": "primary", "reload": {"style": "magazine", "rock": 22.0, "anchors": {"below": [0.0, -0.12, -0.12], "pouch": [-0.07, -0.2, -0.2]}}, "view": {"aim": Vector3(0.000, -0.072, -0.487)}},
	&"shotgun": {"model": "pump_shotgun", "world_scale": 1.8, "hands_life": 1.0, "bolt_node": "shotgunpomp", "bolt_travel": 0.05, "bolt_axis": Vector3(-1.0, 0.0, 0.0), "cycle_style": "pump", "cycle_time": 0.45, "muzzle": 0.444, "muzzle_offset": Vector3(0.0000, 0.0621, 0.0000), "tier": "primary", "reload": {"style": "tube", "prop_scale": 2.0, "anchors": {"pouch": [-0.05, -0.15, -0.20], "near": [-0.02, -0.08, -0.16]}}, "view": {"aim": Vector3(0.000, -0.111, -0.594), "scale": 0.75}},
	&"drum_shotgun": {"model": "drum_shotgun", "measured_grip": true, "muzzle": 0.384, "muzzle_offset": Vector3(0.0001, 0.1724, 0.0000), "fore_along": 0.32, "tier": "primary", "reload": {"style": "magazine", "part": "drum_magazine", "prop_scale": 2.3, "gun_scale": 1.6, "anchors": {"below": [0.0, -0.11, -0.06], "pouch": [-0.07, -0.17, -0.16]}}, "view": {"aim": Vector3(0.020, -0.284, -0.619), "scale": 0.2, "hold": Vector3(0.09, -0.03, -0.40), "rot": Vector3(0, 10, 30)}},
	&"marksman": {"world_scale": 1.6, "hands_life": 1.0, "model": "marksman", "measured_grip": true, "wall": {"wall_max": 0.5}, "muzzle": 0.882, "muzzle_offset": Vector3(0.0000, 0.0939, 0.0000), "fore_along": 0.65, "forearm_scale": 1.5, "tier": "primary", "reload": {"style": "magazine", "anchors": {"below": [0.0, -0.2, -0.1], "pouch": [-0.1, -0.28, -0.2]}}, "ads": {"view_shift_x": 0.20, "view_shift_y": -0.17, "view_shift_z": -0.17}, "view": {"rot": Vector3(0, 4, 8), "aim": Vector3(0.013, -0.254, -0.372), "scale": 0.4, "zoom": 0.45, "zoom_levels": [40.0, 15.0], "scoped": true, "scope": {"lens_circle": 0.52, "ocular": [0.0, 0.195, -0.005, 0.027], "housing": true}}},
	&"lmg": {"world_scale": 1.6, "hands_life": 1.0, "model": "lmg", "measured_grip": true, "wall": {"wall_max": 0.35, "wall_lean": 0.5}, "max_lean": 0.14, "forearm_scale": 1.5, "muzzle": 0.790, "muzzle_offset": Vector3(0.0000, 0.1889, 0.0000), "fore_along": 0.45, "belt_feed": true, "tier": "primary", "reload": {"style": "belt", "hands": {"lift": {"left": ["cover", [0.0, 0.0, -0.08]]}, "cover_open": {"left": ["cover", [0.0, 0.09, -0.10]]}, "belt_lay": {"left": ["cover", [0.0, 0.02, -0.08]]}, "cover_close": {"left": ["cover", [0.0, 0.10, -0.10]]}, "slap": {"left": ["cover", [0.0, 0.0, -0.08]]}}}, "view": {"rot": Vector3(0, 4, 6), "aim": Vector3(0.000, -0.363, -0.414), "scale": 0.22}},
	&"sniper": {"model": "sniper_ph", "world_scale": 1.6, "hands_life": 1.0, "bolt_node": "bolt", "bolt_travel": 0.1, "bolt_lift": 60.0, "bolt_pivot": Vector3(0.0006, 0.077, 0.0), "cycle_style": "bolt", "cycle_time": 0.9, "cycle_at": Vector3(0.03, 0.062, -0.085), "muzzle": 0.804, "muzzle_offset": Vector3(-0.0001, 0.0772, 0.0000), "fore_along": 0.58, "fore_up": 0.62, "tier": "heavy", "reload": {"style": "bolt", "clip": 5, "part": "round", "gun_scale": 1.4, "anchors": {"pouch": [-0.1, -0.28, -0.2], "clip": [-0.031, 0.058, -0.12]}}, "view": {"hold": Vector3(0.17, -0.15, -0.42), "aim": Vector3(0.000, -0.116, -0.392), "rot": Vector3(0, 8, 14), "scale": 0.8, "zoom": 0.3, "zoom_levels": [40.0, 10.0], "scoped": true, "scope": {"lens_circle": 0.62, "ocular": [0.0, 0.107, -0.074, 0.006], "housing": [[-0.15, 0.98, 1], [0.12, 1.02, 1], [0.24, 1.1, 1], [0.28, 1.14], [0.3, 1.55], [0.1, 1.62], [-1.0, 1.62], [-1.3, 1.5], [-15.6, 1.5], [-15.9, 1.62], [-16.2, 1.62], [-16.2, 1.3]]}}},
	&"minigun": {"world_scale": 1.4, "hands_life": 1.0, "model": "minigun", "measured_grip": true, "muzzle": 0.766, "muzzle_offset": Vector3(0.0001, 0.0245, 0.0000), "fore_along": 0.32, "grip_socket": Vector3(0.06, -0.04, 0.21), "support_grip": Vector3(-0.2, 0.0, -0.3), "belt_feed": true, "tier": "heavy", "reload": {"style": "belt"}, "view": {"rot": Vector3(0, 4, 6), "scale": 0.26, "aim": Vector3(0.000, -0.273, -0.342)}},
	&"launcher": {"world_scale": 1.1, "world_offset": Vector3(0.0, 0.0, -0.12), "world_rotation": Vector3(20.0, 6.0, 0.0), "hands_life": 1.0, "model": "rocket_launcher", "forearm_scale": 0.85, "muzzle": 0.756, "muzzle_offset": Vector3(0.0000, -0.0154, 0.0000), "fore_along": 0.32, "tier": "heavy", "reload": {"style": "launcher", "round": "rocket", "eject": "none", "anchors": {"breech": [0.0, 0.08, 0.3], "pouch": [-0.08, -0.28, 0.15], "near": [-0.04, -0.15, 0.2]}}, "view": {"scale": 0.42, "pull_min": 0.9, "aim": Vector3(0.000, -0.110, -0.577)}},
	&"quad_launcher": {"model": "quad_rocket_launcher", "world_scale": 1.0, "world_offset": Vector3(0.06, -0.08, -0.32), "world_rotation": Vector3(4.0, 4.0, 0.0), "hands_life": 1.0, "forearm_scale": 1.4, "muzzle": 0.448, "muzzle_offset": Vector3(0.0000, 0.0400, 0.0000), "fore_along": 0.42, "max_lean": 0.6, "tier": "heavy", "reload": {"style": "launcher", "round": "rocket", "prop_scale": 2.5, "eject": "none", "anchors": {"breech": [0.05, 0.09, 0.38], "pouch": [-0.1, -0.35, 0.15], "near": [-0.05, -0.2, 0.2]}}, "view": {"hold": Vector3(0.18, -0.09, -0.50), "aim": Vector3(0.000, -0.185, -0.679), "scale": 0.30}},
	&"grenade_launcher": {"model": "grenade_launcher", "world_scale": 2.0, "hands_life": 1.0, "world_rotation": Vector3(6.0, 0.0, 0.0), "measured_grip": true, "forearm_scale": 1.3, "muzzle": 0.522, "muzzle_offset": Vector3(-0.0001, 0.1009, 0.0000), "fore_along": 0.31, "fore_up": 0.3, "tier": "heavy", "reload": {"style": "launcher", "prop_scale": 3.0, "anchors": {"breech": [0.059, 0.066, -0.115], "pouch": [-0.06, -0.15, 0.0], "near": [0.075, 0.04, -0.05]}}, "view": {"sight": "red_dot", "rot": Vector3(0, 4, 2), "hold": Vector3(0.12, -0.02, -0.45), "scale": 0.22, "aim": Vector3(0.000, -0.218, -0.420)}},
	&"beamer": {"model": "plasma_rifle", "measured_grip": true, "muzzle": 0.597, "muzzle_offset": Vector3(0.0002, 0.0757, 0.0000), "fore_along": 0.32, "tier": "heavy", "reload": {"style": "cell"}, "ads": {"red_dot_hip": false}, "view": {"sight": "red_dot", "hold": Vector3(0.12, -0.02, -0.4), "scale": 0.22, "aim": Vector3(0.000, -0.274, -0.407)}},
	&"charge_rifle": {"model": "energy_rifle", "world_scale": 1.6, "hands_life": 1.0, "measured_grip": true, "muzzle": 0.598, "muzzle_offset": Vector3(0.0017, 0.0569, 0.0000), "fore_along": 0.45, "wall": {"wall_max": 0.45}, "tier": "heavy", "reload": {"style": "cell", "anchors": {"well": [0.0, 0.0, -0.09], "below": [0.0, -0.15, -0.09], "pouch": [-0.08, -0.22, -0.15]}}, "view": {"aim": Vector3(-0.002, -0.141, -0.452), "zoom": 0.4, "scale": 0.5, "hold": Vector3(0.14, -0.12, -0.42), "rot": Vector3(0, 8, 18), "scoped": true, "scope": {"lens_circle": 0.5, "reticle_colour": Color(0.1, 0.85, 1.0, 0.9), "mil_ticks": false, "ocular": [0.002, 0.115, -0.011, 0.02]}}},
	&"frag": {"model": "frag_grenade", "world_scale": 2.0, "hands_life": 1.0, "muzzle": 0.0, "motion": "throw", "tier": "thrown", "ads": {"thrown_span": 0.09}, "view": {}},
	&"sticky": {"model": "frag_grenade_alt", "world_scale": 2.0, "hands_life": 1.0, "muzzle": 0.0, "motion": "throw", "tier": "thrown", "ads": {"thrown_span": 0.16}, "view": {}},
	&"flash": {"model": "flash_grenade", "world_scale": 1.8, "hands_life": 1.0, "muzzle": 0.0, "motion": "throw", "tier": "thrown", "ads": {"thrown_span": 0.16}, "view": {}},
	&"smoke": {"model": "smoke_grenade", "world_scale": 1.6, "hands_life": 1.0, "muzzle": 0.0, "motion": "throw", "tier": "thrown", "ads": {"thrown_span": 0.23}, "view": {}},
	&"incendiary": {"model": "incendiary_grenade", "world_scale": 1.6, "hands_life": 1.0, "muzzle": 0.0, "motion": "throw", "tier": "thrown", "ads": {"thrown_span": 0.23}, "view": {}},
}

## Equipment and props with no weapon behind them yet: the pack's own, for a host's pickups and effects.
const PROPS: Array[String] = ["ammo_box", "round_pistol", "round_rifle", "round_shell", "round_sniper", "rocket_launcher_alt"]

## Who made each model ([method AwSpawnProvider.credits]); CREDITS.md says the same for people.
const CREDITS: Array[Dictionary] = [
	{"id": "styloo", "model": "pistol, smg, carbine, sniper_rifle, pump_shotgun, rocket_launcher_alt", "author": "Styloo", "licence": "CC0-1.0", "url": "https://styloo.itch.io/guns-asset-pack"},
	{"id": "polyy-1", "model": "revolver, machine_pistol, derringer, bullpup, drum_shotgun, marksman", "author": "Polyy", "licence": "CC0-1.0", "url": "https://polyyai.itch.io/3d-low-poly-guns-pack"},
	{"id": "polyy-2", "model": "minigun, lmg, plasma_rifle", "author": "Polyy", "licence": "CC0-1.0", "url": "https://polyyai.itch.io/3d-low-poly-guns-pack-2"},
	{"id": "ambientcg-metal", "model": "surface detail on every gun (Metal038, Metal027)", "author": "ambientCG", "licence": "CC0-1.0", "url": "https://ambientcg.com/view?id=Metal038"},
	{"id": "polyhaven-guns", "model": "pistol, sniper (service_pistol, bolt_action_rifle_7_62; 2K PBR)", "author": "Mateusz Sadek (Poly Haven)", "licence": "CC0-1.0", "url": "https://polyhaven.com/a/service_pistol"},
	{"id": "lamoot-rifle", "model": "rifle (high-poly AK, rebuilt by tools/build_own_ak.py)", "author": "Lamoot", "licence": "CC0-1.0", "url": "https://opengameart.org/content/high-poly-ak-47"},
	{"id": "firearm-sound-library", "model": "every gun's own report (sounds, cut by tools/make_fire_sounds.py)", "author": "Ben Jaszczak, Brian Nelson, Kevin Heras, Matthew Nanney (The Free Firearm Sound Library)", "licence": "CC0-1.0", "url": "https://opengameart.org/content/the-free-firearm-sound-library"},
	{"id": "oga-rocket-sounds", "model": "launcher and quad_launcher reports (sounds: rocket launch, missile)", "author": "qubodup, mikeask", "licence": "CC0-1.0", "url": "https://opengameart.org/content/rocket-launch"},
	{"id": "fainclaw-energy", "model": "energy_rifle (high-poly, 2K PBR, rebuilt by tools/build_sf_rifles.py)", "author": "Fainclaw", "licence": "CC-BY-4.0", "url": "https://sketchfab.com/3d-models/gameready-sci-fi-energy-rifle-b50bbacccf794e7fa0bc9c61c80d0315"},
	{"id": "8siandude-burst", "model": "burst_rifle (high-poly, 2K PBR, rebuilt by tools/build_sf_rifles.py)", "author": "8sianDude", "licence": "CC-BY-4.0", "url": "https://sketchfab.com/3d-models/howa-type-89-assault-rifle-40ed169fba7d478190f1ad57a42857a3"},
	{"id": "ulrik-battle", "model": "battle_rifle (high-poly, 2K PBR, rebuilt by tools/build_sf_rifles.py)", "author": "Ulrik Langvandsbråten", "licence": "CC-BY-4.0", "url": "https://sketchfab.com/3d-models/hk-g3-rifle-game-ready-2cd63366353b4e8fbc9eff81b1fe922f"},
	{"id": "tmc-launchers", "model": "launcher, grenade_launcher and quad_launcher (own work, tools/build_launchers.py)", "author": "TMC", "licence": "CC0-1.0", "url": "https://github.com/zees-games/fc-weapons"},
	{"id": "tmc-thrown-melee", "model": "frag, sticky, flash, smoke and incendiary grenades, knife (own work, tools/build_thrown_melee.py)", "author": "TMC", "licence": "CC0-1.0", "url": "https://github.com/zees-games/fc-weapons"},
	{"id": "vinrax-knife", "model": "knife", "author": "Vinrax", "licence": "CC0-1.0", "url": "https://opengameart.org/content/knife-low-poly"},
]

## The view rig's wall response per tier (`wall_*` keys, into each def's `params.ads`): a long gun needs a deeper retreat than a pistol to clear a wall.
const WALL_BY_TIER := {
	"melee": {"wall_reach": 0.6},
	"primary": {"wall_max": 0.7, "wall_push": 1.2},
	"heavy": {"wall_max": 0.8, "wall_push": 1.3},
}


## The ADS keys for [param id]: its tier's wall keys, over-ridden by the row's own `wall` and `ads`; empty for the sidearm, whose defaults suit it.
## A row's own `wall` beats its tier's: the smg, short and drawn 1.7 times life size, stops at 0.35 (a long gun's 0.7
## pulled it into the eye running into a wall, both forearms 0.14 m into its receiver's box; 0.35 leaves 0.1 for a frame).
static func wall_row(id: StringName) -> Dictionary:
	if not WEAPONS.has(id):
		return {}
	var out: Dictionary = (WALL_BY_TIER.get(str(WEAPONS[id]["tier"]), {}) as Dictionary).duplicate()
	out.merge(WEAPONS[id].get("wall", {}) as Dictionary, true)
	out.merge(WEAPONS[id].get("ads", {}) as Dictionary, true)
	return out


## The role each tier dresses when a host skins its own weapons by role.
const ROLE_OF := [&"pistol", &"smg", &"carbine", &"rifle", &"shotgun", &"sniper", &"launcher", &"frag"]


static func model_path(file: String) -> String:
	return MODEL_DIR.path_join(file + ".glb")


## One row with its model path resolved and its tier's hold filled in.
static func row_of(id: StringName) -> Dictionary:
	var src: Dictionary = WEAPONS[id]
	var out := src.duplicate(true)
	out["model"] = model_path(str(src["model"]))
	out["motion"] = str(src.get("motion", "gun"))

	if out["motion"] == "gun":
		var tier: Dictionary = _SIDEARM if src["tier"] == "sidearm" else (_HEAVY if src["tier"] == "heavy" else _LONG)
		var view: Dictionary = tier.duplicate()
		view.merge(src["view"] as Dictionary, true)
		out["view"] = view
		# The Styloo models are baked with the origin at the grip, so the palm goes there. The Polyy ones are centred
		# on their bounds, so a row marked measured_grip leaves the palm to HandReach's measurement of the mesh.
		if not bool(src.get("measured_grip", false)):
			out["grip_socket"] = Vector3.ZERO
		if src["tier"] == "sidearm" and not out.has("hand_scale"):
			out["hand_scale"] = 0.36
		if src["tier"] == "sidearm" and not out.has("forearm_scale"):
			out["forearm_scale"] = 0.85

	return out


## role -> row, for a host that dresses its own weapons by role.
static func role_rows() -> Dictionary:
	var out := {}
	for role: StringName in ROLE_OF:
		out[role] = row_of(role)
	return out


## <prefix><id> -> row, for the weapons this pack defines ([method AwWeaponPack.weapons] with the same prefix).
static func weapon_rows(prefix: String = ID_PREFIX) -> Dictionary:
	var out := {}
	for id: StringName in WEAPONS:
		out[StringName(prefix + String(id))] = row_of(id)
	return out
