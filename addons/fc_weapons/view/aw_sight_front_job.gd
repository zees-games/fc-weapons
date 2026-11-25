extends "res://addons/gs_weapon/view/gs_weapon_slice_job.gd"

## [method AwSightCut.short_of_front] as a job able to stop part way and go on in a later frame: the same cut, the code is one.
## Its loops over a mesh's faces (the extent along the axis, the nearest vertex inside the cone) were one 40-50 ms call for a rifle's
## 40k triangles at game-fatal-contact startup. No `class_name`: preloaded by path, like aw_sight_cut.gd, which loads this one late.

const Cut := preload("aw_sight_cut.gd")

## The cut, stopped short of the first thing its axis meets in the front part; filled when [method step] reports done (or [method run] returns).
var result: Dictionary

var _cut: Dictionary
var _node: Node
var _space: Node3D
var _from: float


func _init(cut: Dictionary, node: Node, space: Node3D, from: float) -> void:
	_cut = cut
	_node = node
	_space = space
	_from = from
	result = cut


func _work() -> void:
	if _cut.is_empty() or is_finite(float(_cut.stop)):
		return
	var eye: Vector3 = _cut.eye
	var axis: Vector3 = _cut.axis
	var parts: Array = []
	var lo := INF
	var hi := -INF
	var stack: Array[Node] = [_node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var to_space := Cut.to_space_of(mi, _space)
		if not Cut._invertible(to_space.basis):
			Cut._warn_once(mi.mesh, "sight cut skipped a mesh with a flat transform", {"node": mi.name})
			continue
		var span: Array = await _span(mi.mesh, to_space.basis.transposed() * axis)
		if span.is_empty():
			continue
		var shift := (to_space.origin - eye).dot(axis)
		lo = minf(lo, float(span[0]) + shift)
		hi = maxf(hi, float(span[1]) + shift)
		parts.append([mi.mesh, to_space])
	var front := lo + (hi - lo) * _from
	var planes := Cut.planes_of(_cut)
	var nearest := INF
	var start := eye + axis * maxf(front, 0.0)
	var end := eye + axis * (hi + 1.0)
	for part: Array in parts:
		var to_space: Transform3D = part[1]
		var back := to_space.affine_inverse()
		var tm := Cut._triangle_mesh(part[0] as Mesh)
		var hit: Dictionary = tm.intersect_segment(back * start, back * end) if tm != null else {}
		if not hit.is_empty():
			nearest = minf(nearest, ((to_space * (hit.position as Vector3)) - eye).dot(axis))
		# A sight line that grazes the post's top edge hits no triangle, yet the post stands inside the cone and would be cut away whole.
		nearest = minf(nearest, await _nearest_inside(part[0] as Mesh, to_space, planes, eye, axis, maxf(front, 0.0)))
	if is_finite(nearest):
		var out := _cut.duplicate()
		out.stop = nearest * (1.0 - Cut.POST_CLEAR)
		result = out


## [min, max] of the dot of [param dir] with the mesh's triangle vertices, or [] with none; cached because every equip asks the same.
func _span(mesh: Mesh, dir: Vector3) -> Array:
	var key := "%d|%s" % [mesh.get_instance_id(), dir]
	if not Cut._spans.has(key):
		var lo := INF
		var hi := -INF
		var n := 0
		for v: Vector3 in mesh.get_faces():
			n += 1
			if n % CHECK_EVERY == 0:
				await _yield_if_spent()
			var d := v.dot(dir)
			lo = minf(lo, d)
			hi = maxf(hi, d)
		Cut._spans[key] = [] if lo > hi else [lo, hi]
	return Cut._spans[key]


## Axial depth of the nearest triangle vertex of [param mesh] inside the region (planes from [method AwSightCut.planes_of]) at or past [param from], else INF; cached per mesh and cut.
func _nearest_inside(mesh: Mesh, to_space: Transform3D, planes: Array, eye: Vector3, axis: Vector3, from: float) -> float:
	var key := "in|%d|%s|%s|%s|%s|%s" % [mesh.get_instance_id(), to_space, eye, axis, planes.size(), from]
	if Cut._spans.has(key):
		return Cut._spans[key]
	var best := INF
	var n := 0
	for v: Vector3 in mesh.get_faces():
		n += 1
		if n % CHECK_EVERY == 0:
			await _yield_if_spent()
		var p := to_space * v
		var d := (p - eye).dot(axis)
		if d < from or d >= best:
			continue
		var inside := true
		for plane: Array in planes:
			if (plane[0] as Vector3).dot(p) - float(plane[1]) > 0.0:
				inside = false
				break
		if inside:
			best = d
	Cut._spans[key] = best
	return best
