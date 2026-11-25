extends RefCounted

## One run of the sight cut (aw_sight_cut.gd's cone applied to every mesh under some roots), able to stop part way and go on in a later frame:
## [method step] works for a time budget and returns, [method run] goes through at once; the hole is the same either way, and a stepped prewarm spreads it over frames.
## No `class_name`: preloaded by path, like aw_sight_cut.gd.

const Cut := preload("aw_sight_cut.gd")

## Work between looks at the clock, in loop turns: a turn is some microseconds, so the budget is overrun by about a millisecond at most.
const CHECK_EVERY := 128
const NO_LIMIT := 1 << 62

signal _resume

## The result of the run, `{removed, near, far}` as [method AwSightCut.apply] returns it; filled when [method step] reports done.
var result := {"removed": 0, "near": INF, "far": 0.0}

var _roots: Array
var _space: Node3D
var _cut: Dictionary
var _deadline := NO_LIMIT
var _begun := false
var _finished := false


func _init(roots: Array, space: Node3D, cut: Dictionary) -> void:
	_roots = roots
	_space = space
	_cut = cut


## The whole cut now.
func run() -> Dictionary:
	_deadline = NO_LIMIT
	_begun = true
	_apply()
	return result


## Works for [param budget_usec] more microseconds (a little over at most); true once the cut is done.
func step(budget_usec: int) -> bool:
	_deadline = Time.get_ticks_usec() + budget_usec
	if _finished:
		return true
	if not _begun:
		_begun = true
		_apply()
	else:
		_resume.emit()
	return _finished


## Waits for the next [method step] when the budget is spent. Asked every [constant CHECK_EVERY] turns of a loop.
func _yield_if_spent() -> void:
	if _deadline != NO_LIMIT and Time.get_ticks_usec() >= _deadline:
		await _resume


func _apply() -> void:
	if _cut.is_empty():
		_finished = true
		return
	var planes := Cut.planes_of(_cut)
	var meshes: Array[MeshInstance3D] = []
	for root: Variant in _roots:
		if not (root is Node):
			continue
		var stack: Array[Node] = [root]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			stack.append_array(n.get_children())
			var mi := n as MeshInstance3D
			if mi != null and (mi.mesh is ArrayMesh or mi.mesh is PrimitiveMesh):
				meshes.append(mi)
	for mi in meshes:
		if not is_instance_valid(mi) or mi.mesh == null:
			continue
		var to_space := Cut.to_space_of(mi, _space)
		var cache_key := "%d|%s|%s|%s|%s|%s" % [mi.mesh.get_instance_id(), to_space, _cut.eye, _cut.axis, _cut.tan, _cut.stop]
		var done: Dictionary
		if Cut.cache.has(cache_key):
			done = Cut.cache[cache_key]
		else:
			done = await _cut_mesh(mi.mesh, to_space, planes)
			if not is_instance_valid(mi):
				continue
		Cut.cache[cache_key] = done
		if int(done.removed) == 0:
			continue
		result.removed += int(done.removed)
		result.near = minf(result.near, float(done.near))
		result.far = maxf(result.far, float(done.far))
		var overrides: Array[Material] = []
		for s in mi.get_surface_override_material_count():
			overrides.append(mi.get_surface_override_material(s))
		mi.mesh = done.mesh
		for s in mini(overrides.size(), mi.mesh.get_surface_count()):
			mi.set_surface_override_material(s, overrides[s])
	if result.removed == 0:
		result.near = 0.0
	_finished = true


## `{mesh, removed, near, far}`: [param mesh] with the region taken out of each triangle surface; the mesh itself when nothing is.
func _cut_mesh(mesh: Mesh, to_space: Transform3D, planes: Array) -> Dictionary:
	if mesh is PrimitiveMesh:
		var baked := ArrayMesh.new()
		baked.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, (mesh as PrimitiveMesh).get_mesh_arrays())
		baked.surface_set_material(0, (mesh as PrimitiveMesh).material)
		mesh = baked
	var out := ArrayMesh.new()
	var removed := 0
	var near := INF
	var far := 0.0
	var eye: Vector3 = _cut.eye
	var axis: Vector3 = _cut.axis
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		# Extra glTF UV sets come back as custom channels, which add_surface_from_arrays refuses without their format
		# flags; no weapon material reads them.
		for custom in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
			arrays[custom] = null
		var plain: bool = mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES \
			or arrays[Mesh.ARRAY_BONES] != null or mesh.get_blend_shape_count() > 0
		var cut_surface: Array = [] if plain else await _cut_surface(arrays, to_space, planes, mesh.get_aabb())
		if cut_surface.is_empty():
			# The source's own format flags: its custom channels need them to be read back as the byte arrays they are.
			out.add_surface_from_arrays(mesh.surface_get_primitive_type(s), arrays, [], {}, mesh.surface_get_format(s))
		else:
			removed += int(cut_surface[1])
			for p: Vector3 in cut_surface[2]:
				var d := (p - eye).dot(axis)
				near = minf(near, d)
				far = maxf(far, d)
			var built: Array = cut_surface[0]
			if (built[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
				# Wholly inside the region: nothing is left, and the engine refuses an empty surface. A zero-area
				# triangle keeps the surface count, so material overrides by index stay aligned.
				built = []
				built.resize(Mesh.ARRAY_MAX)
				built[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
				Cut.warn_whole_surface(mesh, s)
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, built)
		if out.get_surface_count() > s:
			out.surface_set_material(s, mesh.surface_get_material(s))
	if removed == 0:
		return {"mesh": mesh, "removed": 0, "near": 0.0, "far": 0.0}
	return {"mesh": out, "removed": removed, "near": near, "far": far}


## `[arrays, removed, points]` for one surface (non-indexed, every attribute interpolated), or `[]` when nothing is inside.
func _cut_surface(arrays: Array, to_space: Transform3D, planes: Array, box: AABB = AABB()) -> Array:
	if (box.has_volume() or box.size != Vector3.ZERO) and Cut.box_beyond(to_space, planes, box):
		return []
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var count := index.size() if not index.is_empty() else verts.size()
	var world := PackedVector3Array()
	world.resize(verts.size())
	# Per vertex, the set of planes it lies beyond (bit k): a triangle misses the region when its three vertices share one.
	var beyond := PackedInt32Array()
	beyond.resize(verts.size())
	var normals: Array[Vector3] = []
	var offsets := PackedFloat64Array()
	for plane: Array in planes:
		normals.append(plane[0])
		offsets.append(plane[1])
	var plane_count := normals.size()
	for i in verts.size():
		if i % CHECK_EVERY == 0:
			await _yield_if_spent()
		var w := to_space * verts[i]
		world[i] = w
		var bits := 0
		for k in plane_count:
			if normals[k].dot(w) > offsets[k]:
				bits |= 1 << k
		beyond[i] = bits
	var corners := PackedInt32Array()
	var bary: Array[Vector3] = []
	var removed := 0
	var points: Array[Vector3] = []
	var corner := [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]
	var indexed := not index.is_empty()
	for i in range(0, count - 2, 3):
		if i % (CHECK_EVERY * 3) == 0:
			await _yield_if_spent()
		var i0 := index[i] if indexed else i
		var i1 := index[i + 1] if indexed else i + 1
		var i2 := index[i + 2] if indexed else i + 2
		if beyond[i0] & beyond[i1] & beyond[i2] != 0:
			corners.append(i0)
			corners.append(i1)
			corners.append(i2)
			corners.append(i0)
			corners.append(i1)
			corners.append(i2)
			corners.append(i0)
			corners.append(i1)
			corners.append(i2)
			bary.append(corner[0])
			bary.append(corner[1])
			bary.append(corner[2])
			continue
		var ids := PackedInt32Array([i0, i1, i2])
		var p: Array[Vector3] = [world[i0], world[i1], world[i2]]
		var pieces: Array = []
		var poly: Array[Vector3] = [corner[0], corner[1], corner[2]]
		for plane: Array in planes:
			var split := Cut.split(poly, p, plane[0], plane[1])
			if not (split[0] as Array).is_empty():
				pieces.append(split[0])
			poly = split[1]
			if poly.is_empty():
				break
		if poly.is_empty():
			pieces = [[corner[0], corner[1], corner[2]]]
		else:
			removed += 1
			for b: Vector3 in poly:
				points.append(p[0] * b.x + p[1] * b.y + p[2] * b.z)
		for piece: Array in pieces:
			for k in range(1, piece.size() - 1):
				for b: Vector3 in [piece[0], piece[k], piece[k + 1]]:
					corners.append_array(ids)
					bary.append(b)
	if removed == 0:
		return []
	return [await _build(arrays, corners, bary), removed, points]


## Non-indexed arrays: entry i is corners[3i..3i+2] (the source triangle) weighted by bary[i].
func _build(arrays: Array, corners: PackedInt32Array, bary: Array[Vector3]) -> Array:
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for slot in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR, Mesh.ARRAY_TANGENT]:
		var src: Variant = arrays[slot]
		if src == null:
			continue
		match slot:
			Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL:
				var a: PackedVector3Array = src
				var o := PackedVector3Array()
				for i in bary.size():
					if i % CHECK_EVERY == 0:
						await _yield_if_spent()
					var b := bary[i]
					var v := a[corners[3 * i]] * b.x + a[corners[3 * i + 1]] * b.y + a[corners[3 * i + 2]] * b.z
					o.append(v.normalized() if slot == Mesh.ARRAY_NORMAL and v != Vector3.ZERO else v)
				out[slot] = o
			Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2:
				var a2: PackedVector2Array = src
				var o2 := PackedVector2Array()
				for i in bary.size():
					if i % CHECK_EVERY == 0:
						await _yield_if_spent()
					var b := bary[i]
					o2.append(a2[corners[3 * i]] * b.x + a2[corners[3 * i + 1]] * b.y + a2[corners[3 * i + 2]] * b.z)
				out[slot] = o2
			Mesh.ARRAY_COLOR:
				var c: PackedColorArray = src
				var oc := PackedColorArray()
				for i in bary.size():
					if i % CHECK_EVERY == 0:
						await _yield_if_spent()
					var b := bary[i]
					oc.append(c[corners[3 * i]] * b.x + c[corners[3 * i + 1]] * b.y + c[corners[3 * i + 2]] * b.z)
				out[slot] = oc
			Mesh.ARRAY_TANGENT:
				var t: PackedFloat32Array = src
				var ot := PackedFloat32Array()
				for i in bary.size():
					if i % CHECK_EVERY == 0:
						await _yield_if_spent()
					var b := bary[i]
					for k in 4:
						ot.append(t[4 * corners[3 * i] + k] * b.x + t[4 * corners[3 * i + 1] + k] * b.y + t[4 * corners[3 * i + 2] + k] * b.z)
				out[slot] = ot
	return out
