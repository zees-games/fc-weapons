class_name AwMissileArt
extends RefCounted

## What a launcher's shot looks like in flight: the launcher's own round, not a generic ball.
## A launcher fires the round its reload loads (an [AwReloadParts] part): the rocket for the tube launchers, the 40 mm
## grenade for the revolver. The models keep no loaded round in sight, so nothing is left in the tube after the shot.
## Every round is centred on its middle with its nose toward -Z, so a host points it along the velocity.

const ReloadParts := preload("../view/aw_reload_parts.gd")

## Weapon id -> [reload part that flies for it (its +Y turned to -Z), scale]. The quad launcher's tubes take a smaller rocket.
const ROUNDS := {
	&"launcher": [&"rocket", 1.0],
	&"quad_launcher": [&"rocket", 0.7],
	&"grenade_launcher": [&"grenade", 1.0],
}


## Whether [param weapon_id] has a missile of its own.
static func has_missile(weapon_id: StringName) -> bool:
	return ROUNDS.has(weapon_id)


## A new missile for [param weapon_id], or null when it has none, so the host draws its own. Its child `Body` holds the round.
static func build(weapon_id: StringName) -> Node3D:
	if not ROUNDS.has(weapon_id):
		return null
	var row: Array = ROUNDS[weapon_id]
	var part := ReloadParts.build(row[0])
	if part == null:
		return null
	var turn := Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3.ONE * float(row[1]))
	var box := _bounds(part, Transform3D.IDENTITY)
	part.name = "Body"
	part.transform = Transform3D(turn, -(turn * box.get_center()))
	var root := Node3D.new()
	root.name = "Missile"
	root.add_child(part)
	return root


## The box around every mesh under [param node], in the space [param xf] puts it in.
static func _bounds(node: Node3D, xf: Transform3D) -> AABB:
	var box := AABB()
	var seen := false
	var here := xf * node.transform if node != null else xf
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		box = here * (node as MeshInstance3D).mesh.get_aabb()
		seen = true
	for child: Node in node.get_children():
		if child is Node3D:
			var got := _bounds(child as Node3D, here)
			if got.size != Vector3.ZERO:
				box = got if not seen else box.merge(got)
				seen = true
	return box
