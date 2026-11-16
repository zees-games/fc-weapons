The weapon set for [Fatal Contact](https://github.com/zees-games/game-fatal-contact) (FC): weapon definitions (stats, ammunition, reloads, view and aim holds), 3D models, sounds and the runtime that draws and fires them in first and third person.

Models come from CC0 packs, baked to one contract: origin at the grip, muzzle toward -Z, metres. The code is MIT. See [CREDITS.md](CREDITS.md) for every asset.

Pack id: `gamemann/fc-weapons` (it was `gamemann/arena-weapons` up to v1.3.x). The addon directory is still `addons/arena_weapons` and its classes still start with `Aw`, because every game loads it by that path.

## Using it

FC requires this pack. It registers the weapons under plain ids (`rifle`) and runs them on this pack's runtime. A game that mixes several weapon packs (zombie-zone, Playlot) calls `weapon_defs()`, `art_rows()` and `spawn_entries()` on `AwSpawnProvider` and gets ids with an `aw_` prefix. `role_art()` dresses a game's own weapons by role.

Link `addons/arena_weapons` into your project, or let `dot-bootstrap` do it. The current API level is 31 (see `addons/arena_weapons/arena_weapons_api.gd`, which also lists what each level added). It needs dot-weapon API 42 or newer (`AwWeaponRig.setup()` fails with a message on an older one); dot-sim from 1a28540 is optional and moves the hitscan spread tick to native code (`AwWeaponRig.native_spread`, on by default, bit-exact with the GDScript tick).

## Weapons

| Slot | Weapons |
| --- | --- |
| 1 melee | `knife` |
| 2 sidearm | `pistol`, `revolver`, `machine_pistol`, `derringer` |
| 3 primary | `smg`, `carbine`, `rifle`, `bullpup`, `battle_rifle`, `burst_rifle`, `shotgun`, `drum_shotgun`, `marksman`, `lmg` |
| 4 heavy | `sniper`, `minigun`, `launcher`, `quad_launcher`, `grenade_launcher`, `beamer`, `charge_rifle` |
| 5 thrown | `frag`, `sticky`, plus `flash`, `smoke` and `incendiary` utility grenades |

Models for ammo boxes, extra grenades and rounds also ship, for a game's pickups and effects.

## Settings

Every stat of every weapon is tunable in `cfg/addons/arena_weapons/weapon/<id>.yml` (through dot-weapon's `DotWeaponProfiles`). Nothing is fixed in code: set a value in the file to change it.

| Setting | What it does |
| --- | --- |
| `fire_modes` | Fire modes of a weapon. The first entry is the starting mode. Automatic guns also fire semi. SMGs, carbines and rifles also burst. |
| `sv_grenade_*` cvars | Grenade flight, bounce, stick and fuse rules (`AwGrenadeRules`) |

The host binds `DotWeaponCommand.BUTTON_FIRE_MODE` to switch modes.

## What is in the pack

| Path | Contents |
| --- | --- |
| `addons/arena_weapons/aw_weapon_pack.gd` | `AwWeaponPack`, the weapon definitions |
| `addons/arena_weapons/aw_weapon_art.gd` | `AwWeaponArt`, the only file that names a model |
| `addons/arena_weapons/spawn_provider.gd` | `AwSpawnProvider`, the contract a game uses |
| `addons/arena_weapons/assets/` | Models (`models/`), attachment models, per-gun sounds |
| `weapons/*.tres` | Weapon resources |
| `groups.json` | Download groups, one per weapon (`weapon-<id>`) |
| `tools/` | Baking and measuring scripts (Blender models, sight points, attachments) |
| `examples/aw_selftest.tscn` | The headless test suite |
| `examples/aw_selftest_ads.tscn` | Checks motion down the sights and through a scope |

## Features for a host game

- **Grenades and utility zones.** `AwUtilityZones` runs flash, smoke and incendiary grenades. The game calls `detonate(grenade, def)` when one goes off and `tick(delta)` once per game tick, and supplies its combat rules (`victims`, `los`, `damage`) so friendly fire and armour stay its own. On the client `AwGrenadeFx` plays the effects. Needs dot-fx.
- **Attachments.** Ten attachments (`att_<id>`): red dot, holographic, 3x prism, 6x scope, suppressor, compensator, vertical and angled grips, laser, extended magazine. Each gun lists the mounts its model has. The server checks a fitting with `validate_fitting`.
- **Sounds.** Each gun has its own layered shot sound in `assets/sounds/`. Other sounds (reload, dry click, equip) come from dot-audio's stock by sound class (`AwSpawnProvider.sound_classes()`).
- **Inspect and holster.** `AwViewModel.inspect()` plays a look-over of the gun. It moves only the view, never the shot or the net.
- **Knife throw and sprint.** Each frame the game passes the throw meter to `AwViewModel.on_windup(charge)` (dot-weapon's `charge_of`: 0 to 1 while winding up, below 0 when not); the hand draws back past the ear and the throw releases from there. A blade pumps with the stride on a sprint; arms that show the free hand read `AwViewModel.run_amount()` and `run_phase()` to pump it.
- **Effects pool.** `AwFxPool` builds shot effects ahead of time under a loading cover, so the first remote shot does not stall a tick. An empty pool is not an error.
- **Download groups.** A web shell sets `DotCloudAddonSet.groups` to `AwWeaponGroups.groups_for(ids)` for the weapons its loadout can hand out. List every weapon a player can receive, because a deferred group cannot be added at runtime.
- **Builds without models.** A build that leaves `assets/` out (the web shell) can draw models from a mounted pack: call `AwModelCache.add_fallback_root(...)` after mounting and `remove_fallback_root` when leaving. Until then each weapon still fires and is drawn invisible, with one warning per model.

## Tests

Open `examples/aw_selftest.tscn` headless in Godot for the main suite, and `examples/aw_selftest_ads.tscn` for the aiming checks. Fatal Contact's own test run covers them too.

## Credits

| What | Author | Licence |
| --- | --- | --- |
| Most primary guns, rocket launchers, grenades, ammo | Styloo (Guns Asset Pack), Polyy (two low-poly gun packs) | CC0 1.0 |
| Knife, pistol, sniper, rifle, stick grenade | Vinrax, Mateusz Sadek, Lamoot, singaii | CC0 1.0 |
| Attachments, finishing and wear maps | TMC (own work) | CC0 1.0 |
| Per-gun shot sounds | Free Firearm Sound Library authors, KuraiWolf, Tabasco, Michel Baradari, jc-sounds, others | CC0 1.0, CC-BY 3.0 and 4.0 |
| Code in this repository | TMC | MIT |

Full per-asset author, link and licence tables are in [CREDITS.md](CREDITS.md). CC0 asks for no credit, but it is given anyway.
