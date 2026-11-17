class_name AwMissileArt
extends RefCounted

## What a launcher's shot looks like in flight: the launcher's own missile, not a generic ball.
## The single-missile launcher's model carries the missile loaded in its tube (`rocketbullet_low`); that mesh flies.
## Every piece is centred on its middle with its nose toward -Z, so a host points it along the velocity.

const ReloadParts := preload("../view/aw_reload_parts.gd")

## Weapon id -> [model file, mesh node in it, scale]. The quad launcher's tubes take a smaller missile.
const MISSILES := {
	&"launcher": ["rocket_launcher", "rocketbullet_low", 1.0],
	&"quad_launcher": ["rocket_launcher", "rocketbullet_low", 0.7],
}
## Weapon id -> reload part that flies for it (its +Y turned to -Z).
const ROUNDS := {
	&"grenade_launcher": &"grenade",
}


## Whether [param weapon_id] has a missile of its own.
static func has_missile(weapon_id: StringName) -> bool:
	return MISSILES.has(weapon_id) or ROUNDS.has(weapon_id)


## A new missile for [param weapon_id], or null when it has none (or its model is not loaded), so the host draws its own.
static func build(weapon_id: StringName) -> Node3D:
	if MISSILES.has(weapon_id):
		var row: Array = MISSILES[weapon_id]
		return _from_model(str(row[0]), str(row[1]), float(row[2]), weapon_id)
	if ROUNDS.has(weapon_id):
		var part := ReloadParts.build(ROUNDS[weapon_id])
		if part == null:
			return null
		var root := Node3D.new()
		root.name = "Missile"
		part.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, 0.0, 0.05))
		root.add_child(part)
		return root
	return null


static func _from_model(file: String, node_name: String, scale: float, weapon_id: StringName) -> Node3D:
	var got := AwModelCache.scene(AwWeaponArt.model_path(file))
	if not got.ok:
		return null
	var model := (got.value as PackedScene).instantiate()
	var src := model.find_child(node_name, true, false) as MeshInstance3D
	var mesh: Mesh = src.mesh if src != null else null
	model.free()
	if mesh == null:
		DotLog.warn("aw.missile_art", "model has no such mesh", {"file": file, "node": node_name, "weapon": weapon_id})
		return null
	# The model lies along +X with its nose there; a quarter turn about Y points it to -Z, as the launcher's own root does.
	var basis := Basis(Vector3.UP, PI * 0.5).scaled(Vector3.ONE * scale)
	var piece := MeshInstance3D.new()
	piece.name = "Body"
	piece.mesh = mesh
	piece.transform = Transform3D(basis, -(basis * mesh.get_aabb().get_center()))
	var root := Node3D.new()
	root.name = "Missile"
	root.add_child(piece)
	return root
