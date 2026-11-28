extends Node

## Attachment section of the self-test, with the counters and `_begin` / `_end` / `_check` every section uses.

const Dress := preload("res://addons/fc_weapons/view/aw_attachment_dress.gd")

var _entered := 0
var _finished := 0
var _checks := 0
var _failures := 0


## A row's third-person hold off the grip: a launcher forward and nose up, a gun without one on the bare grip.
func _world_holds() -> void:
	var tube := AwWeaponVisual.new()
	AwArtDress.apply(tube, AwWeaponArt.row_of(&"launcher"))
	var held := tube.world_transform()
	var nose := -held.basis.z.normalized()
	_check("a launcher's row holds it forward of the grip and nose up, clear of the pack (%s, nose %s)" % [held.origin, nose],
		held.origin.z < -0.05 and nose.y > 0.1 and is_equal_approx(tube.world_scale, 1.8))
	var rifle := AwWeaponVisual.new()
	AwArtDress.apply(rifle, AwWeaponArt.row_of(&"rifle"))
	_check("a gun row without a world hold keeps the bare grip", rifle.world_offset == Vector3.ZERO and rifle.world_rotation == Vector3.ZERO)


func _attachments() -> void:
	_begin("attachments")
	var cat := AwSpawnProvider.attachment_defs()
	var defs := AwSpawnProvider.weapon_defs()
	var atts := AwAttachmentPack.attachments()
	_check("eleven attachments, each valid and its own item", cat.ids().size() == 11 and atts.all(func(a: GSWeaponAttachment) -> bool: return a.validate().ok and String(a.item()).begins_with("att_")))
	_check("every attachment model loads; each optic has its glass", atts.all(_model_ok))
	_check("a part merged by material draws once per material, same triangles, glass and reticle kept by name", _merge_ok(&"holo"))

	var rifle := _def(defs, &"aw_rifle")
	var marksman := _def(defs, &"aw_marksman")
	var pistol := _def(defs, &"aw_pistol")
	_check("a rifle has all five mounts", rifle.mounts.size() == 5)
	_check("the single-missile launcher has only its warhead", _def(defs, &"aw_launcher").mounts == [AwAttachmentSockets.MOUNT_WARHEAD])
	_check("the quad launcher, the minigun and the knife have none", [&"aw_quad_launcher", &"aw_minigun", &"aw_knife", &"aw_frag"].all(func(i: StringName) -> bool: return _def(defs, i).mounts.is_empty()))
	_check("a scope baked into the gun's one mesh leaves no optic mount", not marksman.mounts.has(GSWeaponAttachment.MOUNT_OPTIC) and marksman.mounts.has(GSWeaponAttachment.MOUNT_MUZZLE))
	var pistol_optics: Array = cat.choices_for(pistol).get(GSWeaponAttachment.MOUNT_OPTIC, [])
	_check("a sidearm takes a red dot but no magnified optic", pistol_optics.has(&"red_dot") and not pistol_optics.has(&"prism_3x") and not pistol_optics.has(&"scope_6x"))

	var applied := 0
	var offered := 0
	for def in defs:
		var choices := cat.choices_for(def)
		for mount: StringName in choices:
			for id: StringName in choices[mount]:
				offered += 1
				var fit := GSWeaponFitting.make(def.id)
				fit.fit(mount, id)
				if cat.apply(def, fit).ok:
					applied += 1
	_check("every offered attachment applies to its gun (%d of %d)" % [applied, offered], offered > 50 and applied == offered)

	var full := GSWeaponFitting.make(rifle.id)
	for pair: Array in [[&"optic", &"scope_6x"], [&"muzzle", &"suppressor"], [&"underbarrel", &"vertical_grip"], [&"side", &"laser"], [&"magazine", &"extended_mag"]]:
		full.fit(pair[0], pair[1])
	var res := cat.apply(rifle, full)
	var fitted: GSWeaponDef = res.value if res.ok else null
	_check("a fitted rifle holds more, kicks less and is suppressed", fitted != null and fitted.magazine > rifle.magazine
		and fitted.tuning.recoil_pitch < rifle.tuning.recoil_pitch and fitted.params.get(GSWeaponAttachment.PARAM_SUPPRESSED, false) == true)
	_check("the suppressor picks the suppressed report", fitted != null and AwSpawnProvider.sound_class_for(fitted, &"rifle") == AwWeaponSound.SUPPRESSED and AwSpawnProvider.sound_class_for(rifle, &"rifle") == &"rifle")
	_check("the base def is untouched", not rifle.params.has(GSWeaponAttachment.PARAM_SUPPRESSED))
	var bad := GSWeaponFitting.make(marksman.id)
	bad.fit(GSWeaponAttachment.MOUNT_OPTIC, &"red_dot")
	_check("the server refuses an optic on a gun with no optic mount", not cat.validate_fitting(marksman, bad).ok and cat.conform(marksman, bad).is_empty())
	_check("a fitting survives the wire", cat.decode(rifle, cat.encode(rifle, full)).key() == full.key())
	_check("art for an id the pack does not draw is empty", AwAttachmentArt.of(&"no_such").is_empty() and AwAttachmentArt.of(&"holo").get("zoom", 0.0) == 0.75)

	_world_holds()
	var art := AwWeaponVisual.new()
	AwArtDress.apply(art, AwWeaponArt.row_of(&"rifle"))
	var gun := AwModelCache.instantiate(art.model_path)
	var dressed := Dress.apply(gun, full, art.model_forward, {})
	_check("all five draw on the rifle's sockets", dressed.parts.size() == 5)
	var mag_socket := gun.find_child("socket_magazine", true, false)
	_check("the magazine extension rides on the magazine", mag_socket != null and mag_socket.get_parent().name == &"magazine")
	_check("the scope gives the sight picture: scoped, its zoom, a line through the glass", dressed.scoped and is_equal_approx(dressed.zoom, 0.17) and dressed.line.has("front"))
	_check("a fitted scope brings its own ocular (the gun stays up through it)", (dressed.ocular as Array).size() == 4 and is_equal_approx(float(dressed.ocular[3]), Dress.OCULAR_RADIUS))
	var socket_z := absf((gun.find_child("socket_muzzle", true, false) as Node3D).position.z)
	_check("the suppressor moves the muzzle out (%.3f past %.3f)" % [dressed.reach, socket_z], dressed.reach > socket_z + 0.1)
	_check("the server measures the same reach", is_equal_approx(Dress.muzzle_reach(art, full), dressed.reach))
	var dot := GSWeaponFitting.make(rifle.id)
	dot.fit(GSWeaponAttachment.MOUNT_OPTIC, &"red_dot")
	dressed = Dress.apply(gun, dot, art.model_forward, dressed)
	_check("a red dot swaps in unscoped at its own zoom", dressed.parts.size() == 1 and not dressed.scoped and is_equal_approx(dressed.zoom, 0.83))
	_check("a red dot has no ocular: it is no lens view", (dressed.ocular as Array).is_empty())
	var skew := PackedStringArray()
	for optic: StringName in [&"red_dot", &"holo", &"prism_3x", &"scope_6x"]:
		var one := GSWeaponFitting.make(rifle.id)
		one.fit(GSWeaponAttachment.MOUNT_OPTIC, optic)
		var d := Dress.apply(gun, one, art.model_forward, {})
		var ray: Vector3 = (d.line["front"] as Vector3) - (d.line["rear"] as Vector3)
		var off := absf(ray.x) + absf(ray.y)
		if d.line.is_empty() or ray.length() < 0.001 or off > 0.02 * absf(ray.z):
			skew.append("%s %.3f" % [optic, off / maxf(absf(ray.z), 0.0001)])
	_check("every optic's sight line runs along the bore, not skewed by its lens (%s)" % [", ".join(skew)], skew.is_empty())
	gun.free()
	_sniper_optic(_def(defs, &"aw_sniper"))
	_mounts_valid(defs, cat)
	_end()


## A fitted optic on the sniper hides its built-in scope and takes over the sight picture; clearing the fitting brings the scope back.
func _sniper_optic(sniper: GSWeaponDef) -> void:
	var sniper_art := AwWeaponVisual.new()
	AwArtDress.apply(sniper_art, AwWeaponArt.row_of(&"sniper"))
	var sniper_gun := AwModelCache.instantiate(sniper_art.model_path)
	var sniper_dot := GSWeaponFitting.make(sniper.id)
	sniper_dot.fit(GSWeaponAttachment.MOUNT_OPTIC, &"red_dot")
	var sd := Dress.apply(sniper_gun, sniper_dot, sniper_art.model_forward, {})
	var own_scope := sniper_gun.find_child("scope", true, false) as Node3D
	_check("the sniper has an optic mount; a fitted optic hides the built-in scope and takes over the sight picture", sniper.mounts.has(GSWeaponAttachment.MOUNT_OPTIC)
		and sd.parts.size() == 1 and sd.replaced and own_scope != null and not own_scope.visible and not sd.scoped and sd.line.has("front"))
	Dress.clear(sd)
	_check("clearing the fitting brings the built-in scope back", own_scope.visible)
	sniper_gun.free()


## Every weapon x offered attachment: the gun has the mount's socket, the socket sits on the gun, and the part drawn there touches the gun, is bore-centred (muzzle) and of sane size.
func _mounts_valid(defs: Array[GSWeaponDef], cat: GSWeaponAttachments) -> void:
	var rows := AwSpawnProvider.art_rows()
	var bad := PackedStringArray()
	var no_socket := PackedStringArray()
	var combos := 0
	for def in defs:
		if def.mounts.is_empty() or not rows.has(def.id):
			continue
		var art := AwWeaponVisual.new()
		AwArtDress.apply(art, rows[def.id])
		var choices := cat.choices_for(def)
		for mount: StringName in choices:
			for id: StringName in choices[mount]:
				combos += 1
				var gun := AwModelCache.instantiate(art.model_path)
				var gun_box: AABB = Dress._bounds(gun, gun).grow(0.02)
				var fit := GSWeaponFitting.make(def.id)
				fit.fit(mount, id)
				var d := Dress.apply(gun, fit, art.model_forward, {})
				var socket := gun.find_child(String(AwAttachmentArt.socket_name(mount)), true, false) as Node3D
				var tag := "%s/%s" % [def.id, id]
				if socket == null or d.parts.size() != 1:
					no_socket.append(tag)
				else:
					var box: AABB = Dress._bounds(d.parts[0], gun)
					var sp := Transform3D.IDENTITY
					var up: Node = socket
					while up != null and up != gun:
						sp = (up as Node3D).transform * sp
						up = up.get_parent()
					var pos := sp.origin
					var why := ""
					if not gun_box.has_point(pos):
						why = "socket %s off the gun %s" % [pos, gun_box]
					elif not gun_box.intersects(box):
						why = "floats clear of the gun"
					elif box.size.length() > 0.8 or box.size.length() < 0.01:
						why = "size %.2f" % box.size.length()
					elif mount == GSWeaponAttachment.MOUNT_MUZZLE and (absf(box.get_center().x - pos.x) > 0.03 or absf(box.get_center().y - pos.y) > 0.04):
						why = "off the bore"
					elif mount == GSWeaponAttachment.MOUNT_OPTIC and (box.position.y > pos.y + 0.03 or box.end.y < pos.y):
						why = "optic not seated on its socket"
					if why != "":
						bad.append("%s %s" % [tag, why])
				gun.free()
	_check("every weapon x attachment has a socket and a part (%d combos; %s)" % [combos, ", ".join(no_socket)], combos > 100 and no_socket.is_empty())
	_check("every mount sits on its gun, touching it, bore-centred, sane size (%s)" % [", ".join(bad)], bad.is_empty())


## [param id]'s model merged ([method AwModelCache.instantiate_merged]) against the plain one: fewer draws (surfaces), the same
## triangles, the glass and reticle still found by name.
func _merge_ok(id: StringName) -> bool:
	var path := str(AwAttachmentArt.of(id).get("path", ""))
	var plain := AwModelCache.instantiate(path)
	var merged := AwModelCache.instantiate_merged(path)
	if plain == null or merged == null:
		return false
	var a := _draws_tris(plain)
	var b := _draws_tris(merged)
	var named := merged.find_child("holo_glass", true, false) != null and merged.find_child("reticle", true, false) != null
	print("  merged %s: %d draws %d tris -> %d draws %d tris" % [id, a.x, a.y, b.x, b.y])
	plain.free()
	merged.free()
	return named and b.x * 4 < a.x and a.y == b.y


func _draws_tris(root: Node) -> Vector2i:
	var out := Vector2i.ZERO
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			out.x += 1
			var arrays := mesh.surface_get_arrays(s)
			var idx: Variant = arrays[Mesh.ARRAY_INDEX]
			out.y += ((idx as PackedInt32Array).size() if idx != null else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return out


func _model_ok(a: GSWeaponAttachment) -> bool:
	var part := AwModelCache.instantiate(a.model)
	if part == null:
		return false
	var ok := a.mount != GSWeaponAttachment.MOUNT_OPTIC or part.find_child("*_glass", true, false) != null
	part.free()
	return ok


func _def(defs: Array[GSWeaponDef], id: StringName) -> GSWeaponDef:
	for d in defs:
		if d.id == id:
			return d
	return GSWeaponDef.new()


func _begin(name: String) -> void:
	_entered += 1
	print("")
	print("-- %s" % name)


func _end() -> void:
	_finished += 1


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if passed:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)
