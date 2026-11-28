extends "res://addons/gs_weapon/tools/gs_weapon_anim_export.gd"

## Bakes each weapon's procedural first-person animations into <model>.anim.json (see aw_anim_bake.gd): the sidecar Nightly's asset viewer plays next to the model.
## The arguments and the output (a directory, or - for SIDECAR lines) are the shared shell's (addons/gs_weapon/tools/gs_weapon_anim_export.gd). No ids bakes every weapon in AwWeaponArt.
## godot --headless --path . --script tools/export_anim_tracks.gd -- out_dir sniper
const Bake := preload("aw_anim_bake.gd")
## Models no weapon row uses, shown in Nightly as alternates of one the game does play: they get that weapon's clips baked on the alias's own model (its own grips and reach), marked alias_of.
const ALIASES := {"sniper_ph": ["sniper_rifle"], "pistol_ph": ["pistol"], "combat_knife": ["knife"], "frag_grenade_alt": ["frag_grenade"]}


func _bake_all(host: Node3D, wanted: PackedStringArray) -> void:
	var defs := {}
	for d in AwWeaponPack.weapons({}, "", false):
		defs[d.id] = d
	for id: StringName in AwWeaponArt.weapon_rows(""):
		if not wanted.is_empty() and not String(id) in wanted:
			continue
		var sidecar := Bake.new().bake(host, id, defs.get(id))
		if sidecar.is_empty():
			print("SKIP %s (no model)" % id)
			continue
		emit(sidecar)
		for alt: String in ALIASES.get(sidecar.model, []):
			var copy := Bake.new().bake(host, id, defs.get(id), alt)
			if not copy.is_empty():
				emit(_aliased(copy, sidecar.model))


func _aliased(copy: Dictionary, of: String) -> Dictionary:
	copy.alias_of = of
	return copy
