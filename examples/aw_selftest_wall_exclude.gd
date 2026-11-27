extends RefCounted

## The suite's wall-exclude section: the wall probes step over the bodies they mean to skip and find the wall behind.
## A query's `exclude` getter returns a copy, so `query.exclude.append(rid)` once changed nothing and every probe
## below stopped on (or gave up at) the first body in its way. Reports through the suite's `_begin`, `_check` and `_end`.

const MASK := 1

var suite: Node
var _bodies: Array[CollisionObject3D] = []


func _init(host: Node) -> void:
	suite = host


## A thin wide slab, its face toward the eye, at [param z] in [param parent].
func _slab(parent: Node3D, body: CollisionObject3D, z: float) -> CollisionObject3D:
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.0, 0.1)
	var shape := CollisionShape3D.new()
	shape.shape = box
	body.add_child(shape)
	body.collision_layer = MASK
	body.position = Vector3(0.0, 0.0, z)
	parent.add_child(body)
	_bodies.append(body)
	return body


func _settle() -> void:
	for _i in 2:
		await suite.get_tree().physics_frame


func _clear() -> void:
	for body in _bodies:
		body.get_parent().remove_child(body)
		body.free()
	_bodies.clear()


func run() -> void:
	suite._begin("wall probes skip the bodies they exclude")
	var room := Node3D.new()
	suite.add_child(room)
	await _slab_probes(room)
	_clear()
	await _world_model_probe(room)
	room.queue_free()
	suite._end()


## [AwWallSlam]'s ray, side and sweep probes with a character 0.4 m ahead and a wall 0.9 m ahead.
func _slab_probes(room: Node3D) -> void:
	_slab(room, CharacterBody3D.new(), -0.4)
	_slab(room, StaticBody3D.new(), -0.95)
	await _settle()
	var space := room.get_world_3d().direct_space_state
	var ahead := Vector3(0.0, 0.0, -1.0)
	var none: Array[RID] = []
	var hit := AwWallSlam.probe_from(space, Transform3D.IDENTITY, 1.2, MASK, true, none, ahead, 0.05, 0.5, 30.0)
	suite._check("the muzzle ray steps over a character to the wall behind it (depth %.3f)" % hit["depth"], hit["depth"] > 0.2)
	var sides := AwWallSlam.probe_sides(space, Transform3D.IDENTITY, 1.2, MASK, true, none, ahead, 0.05, 0.5, 30.0, 0.1)
	suite._check("the side rays step over a character to the wall behind it (up %.3f)" % sides["up"], sides["up"] > 0.2)
	var swept := AwWallSlam._sweep(space, Vector3.ZERO, ahead, 1.25, 0.05, MASK, none, true)
	suite._check("the swept sphere steps over a character to the wall behind it (%.3f m)" % swept["distance"],
			absf(swept["distance"] - 0.9) < 0.05)
	var keep := AwWallSlam.probe_from(space, Transform3D.IDENTITY, 1.2, MASK, false, none, ahead, 0.05, 0.5, 30.0)
	suite._check("with characters counted the ray stops on the character (depth %.3f)" % keep["depth"], keep["depth"] > hit["depth"])
	var after := AwWallSlam.probe_from(space, Transform3D.IDENTITY, 1.2, MASK, true, none, ahead, 0.05, 0.5, 30.0)
	suite._check("a skipped character does not leak into the next probe's list", none.is_empty() and is_equal_approx(after["depth"], hit["depth"]))


## [AwWorldModel]'s wall probe starts behind the hand: through the carrier's own body (excluded), and past a teammate.
func _world_model_probe(room: Node3D) -> void:
	var carrier := StaticBody3D.new()
	room.add_child(carrier)
	var held := AwWorldModel.new()
	carrier.add_child(held)
	held.equip(suite._dressed(&"rifle"))
	await suite.get_tree().process_frame
	var hand: float = held._holder.global_position.z
	var length: float = held._holder.global_position.distance_to(held.muzzle_transform().origin)
	# The carrier's own slab sits between the probe's start (WALL_ARM behind the hand) and the hand.
	carrier.collision_layer = MASK
	var own := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.0, 0.1)
	own.shape = box
	own.position = Vector3(0.0, 0.0, hand + AwWorldModel.WALL_ARM * 0.5)
	carrier.add_child(own)
	await _settle()
	suite._check("the held gun's wall probe passes through its carrier's own body", is_zero_approx(held._probe_wall()))
	var mate := _slab(room, CharacterBody3D.new(), hand - length * 0.3)
	var wall := _slab(room, StaticBody3D.new(), hand - length * 0.6)
	await _settle()
	var pull := held._probe_wall()
	suite._check("the held gun's wall probe steps over a teammate to the wall behind (pull %.3f)" % pull, pull > 0.05)
	_bodies.erase(mate)
	_bodies.erase(wall)
	mate.free()
	wall.free()
	await _settle()
	suite._check("the next probe starts again from the carrier alone", is_zero_approx(held._probe_wall()))
	carrier.queue_free()
