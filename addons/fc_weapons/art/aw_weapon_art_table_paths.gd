extends RefCounted

## Model paths and pose names of AwWeaponArtTable, split out for file size.

## The arms model [AwViewArms] loads for `style = &"model"`; here so the vendoring list can name it.
const ARMS_MODEL := "res://assets/arms/character-a.glb"
## The rigged arm [AwViewArms] draws by default (`style = &"rigged"`): one right arm with finger bones, built by art-src/arms/ from a CC0 base. Without the file the arms fall back to the code-built gloves, so a game that has not synced it loses nothing.
const RIGGED_ARMS_MODEL := "res://assets/arms/arms-rigged.glb"
## The frag grenade (Kenney Blaster Kit grenade-a, CC0), carried by this pack.
const FRAG_GRENADE := "res://addons/fc_weapons/assets/models/frag_grenade/frag_grenade.glb"
const MELEE := "res://assets/melee/"
## The real-world guns (kitbashed from CC0 Quaternius and Kenney parts by art-src/guns/): one file per role, the muzzle on -Z and the origin at the bounds' centre like the blasters, a magazine split off as `<role>_magazine.glb` where the source had one.
const GUNS := "res://assets/low-poly-guns/"

## Shared parts ship as separate models, so a magazine visibly falls out on reload.


## Loose foam darts, for the guns with no clip: what the support hand carries in on a reload
## (`AwWeaponVisual.magazine_loose`), so no gun reloads with an empty hand.
## Realistic rounds (Kenney Weapon Pack, CC0) for the real-world guns; the darts stay for the toy ones.
const AMMO := "res://assets/ammo/"
const ROUND_CARTRIDGE := AMMO + "ammo_uzi.glb"
const ROUND_SHELL := AMMO + "ammo_shotgun.glb"
const ROUND_RIFLE := AMMO + "ammo_sniper.glb"
const ROUND_ROCKET := AMMO + "ammo_rocketModern.glb"


## Five hand positions rather than twenty-seven; a weapon states its family and only nudges what is its own.

const POSE_PISTOL := &"pistol"
const POSE_RIFLE := &"rifle"
const POSE_HEAVY := &"heavy"
const POSE_MELEE := &"melee"
const POSE_THROWN := &"thrown"
