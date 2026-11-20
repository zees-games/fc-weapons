extends RefCounted

## The README studio shot's model hook (tools/readme.cfg [shot] model_script): weapon id -> the bare model the
## pack draws for it, by AwWeaponArt's row (the one file that names a model). Not shipped: tools/ is not in the pack.

const Art := preload("res://addons/fc_weapons/aw_weapon_art.gd")


static func instantiate(id: StringName) -> Node3D:
	if not Art.WEAPONS.has(id):
		return null
	var packed := load(Art.model_path(str(Art.WEAPONS[id]["model"]))) as PackedScene
	return packed.instantiate() as Node3D if packed != null else null
