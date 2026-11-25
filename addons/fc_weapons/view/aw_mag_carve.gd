extends RefCounted

## Splits a gun's magazine out of a model drawn as one welded mesh, so it is a node a reload can pull out, carry in the support hand and seat again.
## The triangles whose middle lies in a box move to a new "Magazine" mesh; the rest stay on the gun.
## Preloaded by path (no class_name), as its siblings are.

const HandReach := preload("aw_hand_reach.gd")
const MIN_TRIANGLES := 12

## key -> {mesh path: [rest ArrayMesh, magazine ArrayMesh, magazine triangle count]}, so a weapon equipped twice is split once.
static var _cache: Dictionary = {}
## model path -> the magazine's box in the weapon's parent (holder) space, kept by the first person view that measured it so the
## watcher's model of the same gun splits the same triangles.
static var _boxes: Dictionary = {}


static func remember(model_path: String, box: AABB) -> void:
	_boxes[model_path] = box


## The box [method remember] was given for [param model_path], or an empty AABB.
static func recall(model_path: String) -> AABB:
	return _boxes.get(model_path, AABB())


## Puts a carved magazine back into the mesh it came from and frees its node, so a gun nobody is reloading is one mesh again.
static func merge_back(mag: Node3D) -> void:
	if mag == null or not is_instance_valid(mag):
		return
	var source: Variant = mag.get_meta(&"source", null)
	var whole: Variant = mag.get_meta(&"whole", null)
	if source is MeshInstance3D and is_instance_valid(source) and whole is Mesh:
		(source as MeshInstance3D).mesh = whole
	mag.get_parent().remove_child(mag)
	mag.queue_free()


## Splits [param weapon]'s magazine out and returns the new node, or null when too little of the gun lies in [param box].
## The box is in the space [param to_space] takes [param space]'s own space to ([param space] is an ancestor of [param weapon]).
## [param key] names the split for the cache.
static func carve(weapon: Node3D, space: Node3D, to_space: Transform3D, box: AABB, key: String) -> Node3D:
	var best: MeshInstance3D = null
	var best_count := 0
	var fresh := not _cache.has(key)
	var entry: Dictionary = _cache.get(key, {})
	for mi: MeshInstance3D in HandReach.meshes(weapon):
		if mi.mesh == null or mi.get_meta(&"carved", false):
			continue
		var rel := str(weapon.get_path_to(mi))
		var pair: Array = entry.get(rel, [])
		if fresh:
			pair = _split(mi.mesh, to_space * _relative(mi, space), box)
			if not pair.is_empty():
				entry[rel] = pair
		if pair.is_empty():
			continue
		if int(pair[2]) > best_count:
			best_count = int(pair[2])
			best = mi
	if fresh:
		_cache[key] = entry
	if best == null or best_count < MIN_TRIANGLES:
		return null
	var chosen: Array = entry[str(weapon.get_path_to(best))]
	var mag := MeshInstance3D.new()
	mag.name = "Magazine"
	mag.mesh = chosen[1]
	mag.transform = best.transform
	mag.set_meta(&"carved", true)
	mag.set_meta(&"source", best)
	mag.set_meta(&"whole", best.mesh)
	mag.material_override = best.material_override
	mag.layers = best.layers
	mag.cast_shadow = best.cast_shadow
	best.mesh = chosen[0]
	best.get_parent().add_child(mag)
	# The closing cap is a surface past the source's own (_add_cap), with no override slot there.
	for s in mini(mag.mesh.get_surface_count(), best.get_surface_override_material_count()):
		var override := best.get_surface_override_material(s)
		if override != null:
			mag.set_surface_override_material(s, override)
	return mag


static func _relative(node: Node3D, space: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var walk: Node = node
	while walk != null and walk != space:
		if walk is Node3D:
			t = (walk as Node3D).transform * t
		walk = walk.get_parent()
	return t


## [rest mesh, magazine mesh, magazine triangle count], or empty when nothing of [param mesh] is in the box.
static func _split(mesh: Mesh, xf: Transform3D, box: AABB) -> Array:
	var rest := ArrayMesh.new()
	var mag := ArrayMesh.new()
	var total := 0
	# The carved triangles' corners and UVs, to close the opening where they were welded to the gun, and the surface
	# holding most of them, whose material closes it.
	var rim := PackedVector3Array()
	var rim_uv := PackedVector2Array()
	var most_at := -1
	var most := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index: Variant = arrays[Mesh.ARRAY_INDEX]
		var idx := PackedInt32Array()
		if index is PackedInt32Array and not (index as PackedInt32Array).is_empty():
			idx = index
		else:
			idx.resize(verts.size())
			for i in verts.size():
				idx[i] = i
		var keep := PackedInt32Array()
		var take := PackedInt32Array()
		for i in range(0, idx.size() - 2, 3):
			var c := (verts[idx[i]] + verts[idx[i + 1]] + verts[idx[i + 2]]) / 3.0
			if box.has_point(xf * c):
				take.append(idx[i])
				take.append(idx[i + 1])
				take.append(idx[i + 2])
			else:
				keep.append(idx[i])
				keep.append(idx[i + 1])
				keep.append(idx[i + 2])
		total += take.size() / 3
		_add_surface(rest, mesh, s, arrays, keep)
		_add_surface(mag, mesh, s, arrays, take)
		var uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
		for v in take:
			rim.append(verts[v])
			rim_uv.append((uvs as PackedVector2Array)[v] if uvs is PackedVector2Array else Vector2.ZERO)
		if take.size() > most:
			most = take.size()
			most_at = s
	if total == 0:
		return []
	if most_at >= 0:
		_add_cap(mag, mesh.surface_get_material(most_at), rim, rim_uv)
	return [rest, mag, total]


## Closes the opening of a carved magazine, which was welded to the gun there and so has no faces across it. [param tris] are the carved
## triangles' corners, three a triangle, with [param uvs]; the edges only one triangle uses (welded by position) are the opening,
## chained into loops and each filled as a fan from its middle. Seated, it lies inside the gun.
static func _add_cap(into: ArrayMesh, material: Material, tris: PackedVector3Array, uvs: PackedVector2Array) -> void:
	var weld := func(p: Vector3) -> Vector3: return p.snapped(Vector3.ONE * 0.0001)
	var uses := {}
	var uv_at := {}
	for t in range(0, tris.size() - 2, 3):
		for k in 3:
			var a: Vector3 = weld.call(tris[t + k])
			var b: Vector3 = weld.call(tris[t + (k + 1) % 3])
			uv_at[a] = uvs[t + k]
			var edge := [a, b] if a < b else [b, a]
			uses[edge] = int(uses.get(edge, 0)) + 1
	var next := {}
	for edge: Array in uses:
		if uses[edge] != 1:
			continue
		for e in 2:
			if not next.has(edge[e]):
				next[edge[e]] = []
			(next[edge[e]] as Array).append(edge[1 - e])
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tex := PackedVector2Array()
	var seen := {}
	for start: Vector3 in next:
		if seen.has(start):
			continue
		var loop: Array[Vector3] = [start]
		seen[start] = true
		var at := start
		while true:
			var step: Variant = null
			for n: Vector3 in next[at]:
				if not seen.has(n):
					step = n
					break
			if step == null:
				break
			at = step
			seen[at] = true
			loop.append(at)
		if loop.size() < 3:
			continue
		var mid := Vector3.ZERO
		var mid_uv := Vector2.ZERO
		for p in loop:
			mid += p
			mid_uv += uv_at[p]
		mid /= loop.size()
		mid_uv /= loop.size()
		# Both windings, each lit from its own face: which side looks out depends on how the loop happened to run.
		for side: float in [1.0, -1.0]:
			for i in loop.size():
				var a := loop[i]
				var b := loop[(i + 1) % loop.size()]
				if side < 0.0:
					var swap := a
					a = b
					b = swap
				verts.append_array(PackedVector3Array([mid, a, b]))
				var face := Plane(mid, a, b).normal
				normals.append_array(PackedVector3Array([face, face, face]))
				tex.append_array(PackedVector2Array([mid_uv, uv_at[a], uv_at[b]]))
	if verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = tex
	into.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	into.surface_set_material(into.get_surface_count() - 1, material)


static func _add_surface(into: ArrayMesh, from: Mesh, s: int, arrays: Array, idx: PackedInt32Array) -> void:
	if idx.is_empty():
		# Nothing of this material here; the slot is not needed, a mesh with no surface for it draws the same.
		return
	# Only the vertices these triangles use, so each half has its own bounds and no dead vertices.
	var remap := {}
	var order := PackedInt32Array()
	var fresh := PackedInt32Array()
	fresh.resize(idx.size())
	for i in idx.size():
		var v: int = idx[i]
		if not remap.has(v):
			remap[v] = order.size()
			order.append(v)
		fresh[i] = remap[v]
	var out := arrays.duplicate()
	for k in out.size():
		if k == Mesh.ARRAY_INDEX or out[k] == null:
			continue
		out[k] = _pick(out[k], order, k)
	out[Mesh.ARRAY_INDEX] = fresh
	into.add_surface_from_arrays(from.surface_get_primitive_type(s), out)
	into.surface_set_material(into.get_surface_count() - 1, from.surface_get_material(s))


## The entries of one vertex array at [param order]; per-vertex arrays only (tangents and bone weights have several floats a vertex).
static func _pick(arr: Variant, order: PackedInt32Array, kind: int) -> Variant:
	var size: int = int(arr.size())
	if size == 0:
		return arr
	var per := 1
	if kind == Mesh.ARRAY_TANGENT:
		per = 4
	elif kind == Mesh.ARRAY_BONES or kind == Mesh.ARRAY_WEIGHTS:
		per = 4 if size % 4 == 0 else 8
	var out: Variant = arr.duplicate()
	out.resize(order.size() * per)
	for i in order.size():
		for j in per:
			out[i * per + j] = arr[order[i] * per + j]
	return out
