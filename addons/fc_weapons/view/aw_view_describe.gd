extends RefCounted

## The text and dictionary descriptions of an [AwViewModel] for the debug panel and the self-tests, and the searches into a view model's art the sight and the scope body use.


static func describe(view: Node3D) -> Dictionary:
	return {
		"equipped": String(view._id),
		"has_model": view._weapon != null,
		"magazine": view._magazine != null,
		"attachments": view._attachments.size(),
		"arms": view._arms.describe() if view._arms != null else {},
		"reload": view._seq.describe() if view._seq != null else {},
		"pose": view._pose.describe(),
		"muzzle": view._muzzle,
		"aim": "%.2f%s%s" % [view._aim_fraction, " held" if view._aim_held else "", " scoped" if view.is_scoped() else ""],
	}


static func describe_lines(view: Node3D) -> PackedStringArray:
	var out := PackedStringArray()
	out.append("view model: %s%s" % [
		String(view._id) if view._id != &"" else "(nothing)",
		"" if view._weapon != null else " (no mesh)",
	])
	out.append("  muzzle %.3f m out, %d attachment(s)" % [
		view._muzzle.length(), view._attachments.size()
	])
	out.append("  %s" % str(view._pose.describe()))
	return out


## The visible `rear_ring` nodes under [param root].
static func find_rear_rings(root: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if root == null:
		return out
	for node in root.find_children("rear_ring*", "Node3D", true, false):
		if (node as Node3D).visible:
			out.append(node)
	return out


## The scope style's `ocular` ([x, y, z, radius] in the model's metres, the eye end of the scope's glass) as [centre, radius]; empty without one.
static func scope_ocular(style: Dictionary) -> Array:
	var ocular: Variant = style.get("ocular", null)
	if not (ocular is Array) or (ocular as Array).size() < 4 or float(ocular[3]) <= 0.0:
		return []
	return [Vector3(float(ocular[0]), float(ocular[1]), float(ocular[2])), float(ocular[3])]
