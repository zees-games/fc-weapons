@tool
extends "aw_world_model_keys.gd"

## Fitting half of [AwWorldModel], split out for file size: dressing the gun with its attachments, its
## shadows, the support hand point and the dropped magazine. Behaviour lives in [AwWorldModel], which extends this.

const Dress := preload("aw_attachment_dress.gd")
const MagCarve := preload("aw_mag_carve.gd")
const HandReach := preload("aw_hand_reach.gd")
var _art: AwWeaponVisual = null
var _dressed: Dictionary = {}
var _fit_code: int = -1
var _fitting: DotWeaponFitting = null
var _id: StringName = &""
var _weapon: Node3D = null
## The catalogue [method on_fitted] decodes a replicated fitting against; the arsenal's own.
var attachments: DotWeaponAttachments = null
var _holder: Node3D = null
var _mag: Node3D = null
var _mag_local := Transform3D.IDENTITY
var _support_local := Vector3.INF
## The ejection port in the model's space, measured on the first shot after an equip (INF until then).
var _eject_local: Vector3 = Vector3.INF

@export_group("Behaviour")

## Whether the weapon casts a shadow. On by default because a weapon with no shadow floats, and a floating weapon
## is one of the few third-person artefacts a player will actually mention.
@export var cast_shadow: bool = true


## Draws [param fitting]'s attachments on the weapon in hand, and moves the muzzle to the suppressor's end.
func set_fitting(fitting: DotWeaponFitting) -> void:
	_fitting = fitting.duplicate_fitting() if fitting != null else null
	if _weapon == null or _art == null:
		return
	_dressed = Dress.apply(_weapon, _fitting, _art.model_forward, _dressed)
	_apply_shadows()


## Follows a carrier's replicated [code]net_fitted[/code] [param code]; needs [member attachments] to decode it.
func on_fitted(code: int) -> void:
	if code == _fit_code or attachments == null or _id == &"":
		return
	_fit_code = code
	var base := AwWeaponCatalogue.shared().get_def(_id)
	if base != null and attachments.code_bits(base) <= DotWeaponNetSync.FITTED_BITS:
		set_fitting(attachments.decode(base, code))


## Where the spent case leaves this gun in the world: the same port the first-person rig throws from. Effects only.
func eject_transform() -> Transform3D:
	if _weapon == null:
		return global_transform
	if not _eject_local.is_finite():
		_eject_local = HandReach.eject_local(_weapon, _art)
	var world := _weapon.global_transform
	return Transform3D(world.basis.orthonormalized(), world * _eject_local)


## Which way the barrel points in the world: the art's forward through the model's basis.
func muzzle_direction() -> Vector3:
	if _weapon == null or _art == null:
		return -global_basis.z.normalized()

	return (_weapon.global_basis * _art.model_forward).normalized()


## The reload's magazine: split out of the gun on the reload's first frame (the first person view measured where it sits),
## pulled out with the support hand, carried to the belt and back, and seated.
func _detach_magazine() -> void:
	if _mag != null or _weapon == null or _art == null or not _support_local.is_finite():
		return
	var box := MagCarve.recall(_art.model_path)
	if box.size == Vector3.ZERO:
		return
	_mag = MagCarve.carve(_weapon, _holder, Transform3D.IDENTITY, box, "%s|%s" % [_art.model_path, box])
	if _mag != null:
		_mag_local = _mag.transform
		_apply_shadows()


## Where the support hand holds [param art]'s model, in the holder's space: its own `support_grip`, else
## the fractions [member AwWeaponVisual.fore_along] and [member AwWeaponVisual.fore_up] over the mesh's bounds.
func _support_point_for(art: AwWeaponVisual) -> Vector3:
	if art.support_grip.is_finite():
		return art.support_grip
	if _weapon == null:
		return Vector3.INF
	var box := AABB()
	var seeded := false
	for mi in _meshes(_weapon):
		if mi.mesh == null:
			continue
		var to_holder := Transform3D.IDENTITY
		var walk: Node = mi
		while walk != null and walk != _holder:
			if walk is Node3D:
				to_holder = (walk as Node3D).transform * to_holder
			walk = walk.get_parent()
		var part := to_holder * mi.mesh.get_aabb()
		box = part if not seeded else box.merge(part)
		seeded = true
	if not seeded:
		return Vector3.INF
	var forward := art.model_forward.normalized()
	var t_min := INF
	var t_max := -INF
	for i in 8:
		var t := box.get_endpoint(i).dot(forward)
		t_min = minf(t_min, t)
		t_max = maxf(t_max, t)
	var centre := box.get_center()
	var point := centre - forward * centre.dot(forward) + forward * lerpf(t_min, t_max, art.fore_along)
	point.y = box.position.y + box.size.y * art.fore_up
	return point


func _apply_shadows() -> void:
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	for mesh in _meshes(self):
		mesh.cast_shadow = mode


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []

	if node is MeshInstance3D:
		out.append(node)

	for child in node.get_children():
		out.append_array(_meshes(child))

	return out
