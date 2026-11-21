extends RefCounted

## The carry class a weapon is held as, split out of [AwWorldModel]. By path, like the hip hold: no global name for a helper.


## The carry class (gs-player-char's `GSHumanoidCarry.CLASSES`) [param art] is held as: from its pose, and for a
## long gun from its sound class (the pack's own, else the one a host gave [AwWeaponSound] for a prefixed or another
## pack's id); null for a knife or a grenade, which the clip's arms hold.
static func of(art: AwWeaponVisual) -> Variant:
	if art == null:
		return null
	match art.pose:
		&"pistol":
			return &"pistol"
		&"heavy":
			return &"heavy"
		&"melee", &"thrown":
			return null
	var sound: StringName = AwWeaponPack.SOUND_CLASSES.get(art.id, &"")
	if sound == &"":
		sound = AwWeaponSound.class_for(art.id, &"")
	match sound:
		&"shotgun", &"autoshot":
			return &"shotgun"
		&"sniper", &"marksman", &"rail":
			return &"sniper"
		&"smg", &"mpistol":
			return &"smg"
		&"minigun", &"launcher", &"grenade":
			return &"heavy"
	return &"rifle"
