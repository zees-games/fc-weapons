extends RefCounted

## Cuts a see-through hole out of a view model's own meshes along the aim line: a cone from the aimed eye round the aim axis,
## ending short of the front post, so a solid rear sight, ring housing or optic box is looked through, not at.
## No `class_name`: preloaded by path, as aw_own_sight.gd is. Cut meshes are copies; the world model keeps the original.

## Sides of the pyramid that stands in for the cone; it is drawn round the circle, so the hole is never smaller than asked.
const SIDES := 16
## How far short of the front post's back face the cut stops, as a share of its distance from the eye.
const POST_CLEAR := 0.03

const IronSight := preload("res://addons/gs_weapon/view/gs_weapon_iron_sight.gd")

const CHANNEL := "aw.sightcut"

static var cache: Dictionary = {}
static var _tree: Dictionary = {}
static var _spans: Dictionary = {}
static var _warned: Dictionary = {}


## The cut for an aim hold [param aim] (the holder's transform at full aim): `{eye, axis, tan, stop}` in the holder's space.
## [param degrees] is the hole's angular radius; [param front] the front post (holder space) the hole stops short of, or null.
static func cone(aim: Transform3D, degrees: float, front: Variant = null) -> Dictionary:
	if degrees <= 0.0:
		return {}
	var inv := aim.affine_inverse()
	var eye := inv * Vector3.ZERO
	var axis := (inv.basis * Vector3.FORWARD).normalized()
	var stop := INF
	if front is Vector3:
		stop = ((front as Vector3) - eye).dot(axis) * (1.0 - POST_CLEAR)
	return {"eye": eye, "axis": axis, "tan": tan(deg_to_rad(degrees)), "stop": stop}


## Gives every mesh under [param roots] the cut copy for [param cut] (from [method cone]) in [param space].
## Returns `{removed, near, far}`: triangles touched and the axial range of what was taken away (0 when nothing).
static func apply(roots: Array, space: Node3D, cut: Dictionary) -> Dictionary:
	# Loaded here, not preloaded: the job preloads this script, and a preload cycle is refused.
	return load("res://addons/fc_weapons/view/aw_sight_cut_job.gd").new(roots, space, cut).run()



## [param cut] stopped short of the first thing its axis meets in the front part of [param node] (past [param from] of its length
## along the axis): a front post the mesh reading missed. Unchanged when the axis meets nothing there.
static func short_of_front(cut: Dictionary, node: Node, space: Node3D, from: float = 0.55) -> Dictionary:
	if cut.is_empty() or is_finite(float(cut.stop)):
		return cut
	var eye: Vector3 = cut.eye
	var axis: Vector3 = cut.axis
	var parts: Array = []
	var lo := INF
	var hi := -INF
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var to_space := to_space_of(mi, space)
		if not _invertible(to_space.basis):
			_warn_once(mi.mesh, "sight cut skipped a mesh with a flat transform", {"node": mi.name})
			continue
		var span := _span(mi.mesh, to_space.basis.transposed() * axis)
		if span.is_empty():
			continue
		var shift := (to_space.origin - eye).dot(axis)
		lo = minf(lo, float(span[0]) + shift)
		hi = maxf(hi, float(span[1]) + shift)
		parts.append([mi.mesh, to_space])
	var front := lo + (hi - lo) * from
	var planes := planes_of(cut)
	var nearest := INF
	var start := eye + axis * maxf(front, 0.0)
	var end := eye + axis * (hi + 1.0)
	for part: Array in parts:
		var to_space: Transform3D = part[1]
		var back := to_space.affine_inverse()
		var tm := _triangle_mesh(part[0] as Mesh)
		var hit: Dictionary = tm.intersect_segment(back * start, back * end) if tm != null else {}
		if not hit.is_empty():
			nearest = minf(nearest, ((to_space * (hit.position as Vector3)) - eye).dot(axis))
		# A sight line that grazes the post's top edge hits no triangle, yet the post stands inside the cone and would be cut away whole.
		nearest = minf(nearest, _nearest_inside(part[0] as Mesh, to_space, planes, eye, axis, maxf(front, 0.0)))
	if is_finite(nearest):
		var out := cut.duplicate()
		out.stop = nearest * (1.0 - POST_CLEAR)
		return out
	return cut


## Axial depth of the nearest triangle vertex of [param mesh] inside the region (planes from [method planes_of]) at or past [param from], else INF; cached per mesh and cut.
static func _nearest_inside(mesh: Mesh, to_space: Transform3D, planes: Array, eye: Vector3, axis: Vector3, from: float) -> float:
	var key := "in|%d|%s|%s|%s|%s|%s" % [mesh.get_instance_id(), to_space, eye, axis, planes.size(), from]
	if _spans.has(key):
		return _spans[key]
	var best := INF
	for v: Vector3 in mesh.get_faces():
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
	_spans[key] = best
	return best


## A mesh's collision-style triangle tree, built natively once: [method short_of_front] asks it one segment instead of walking every triangle in script.
static func _triangle_mesh(mesh: Mesh) -> TriangleMesh:
	var id := mesh.get_instance_id()
	if not _tree.has(id):
		_tree[id] = mesh.generate_triangle_mesh()
	return _tree[id]


## [min, max] of the dot of [param dir] with the mesh's triangle vertices, or [] with none; cached because every equip asks the same.
static func _span(mesh: Mesh, dir: Vector3) -> Array:
	var key := "%d|%s" % [mesh.get_instance_id(), dir]
	if not _spans.has(key):
		var lo := INF
		var hi := -INF
		for v: Vector3 in mesh.get_faces():
			var d := v.dot(dir)
			lo = minf(lo, d)
			hi = maxf(hi, d)
		_spans[key] = [] if lo > hi else [lo, hi]
	return _spans[key]


## Rays from [param cut]'s eye inside its cone ([param share] of its radius, [param rings] rings of [param per_ring]) that hit a triangle
## of [param node]'s meshes before the stop: 0 when the sight is seen through. A suite's check on the drawn meshes, not the cut.
static func occluders(node: Node, space: Node3D, cut: Dictionary, share: float = 0.9, rings: int = 4, per_ring: int = 12) -> int:
	if cut.is_empty():
		return 0
	var eye: Vector3 = cut.eye
	var axis: Vector3 = cut.axis
	var u := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := axis.cross(u)
	var reach: float = float(cut.stop) if is_finite(float(cut.stop)) else 10.0
	var triangles := IronSight.triangles_of(node, space)
	var hits := 0
	for r in rings + 1:
		var t: float = float(cut.tan) * share * r / rings
		for k in (1 if r == 0 else per_ring):
			var phi := TAU * k / per_ring
			var dir := (axis + (u * cos(phi) + v * sin(phi)) * t).normalized()
			var to := eye + dir * reach / dir.dot(axis)
			for tri: Dictionary in triangles:
				if Geometry3D.segment_intersects_triangle(eye, to, tri.a, tri.b, tri.c) != null:
					hits += 1
					break
	return hits


## The region as planes `[normal, d]` in space coordinates: a point p is inside when every `normal.dot(p) - d <= 0`.
static func planes_of(cut: Dictionary) -> Array:
	var eye: Vector3 = cut.eye
	var axis: Vector3 = cut.axis
	var u := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := axis.cross(u)
	# The pyramid's sides sit outside the circle: its inner radius is the cone's at every depth.
	var t: float = float(cut.tan) / cos(PI / SIDES)
	var planes: Array = []
	for k in SIDES:
		var phi := TAU * k / SIDES
		var n := u * cos(phi) + v * sin(phi) - axis * t
		planes.append([n, n.dot(eye)])
	planes.append([-axis, -axis.dot(eye)])
	if is_finite(float(cut.stop)):
		planes.append([axis, axis.dot(eye) + float(cut.stop)])
	return planes


## False for a zero-scale or collinear basis: its inverse is undefined and the engine logs an error for it.
static func _invertible(basis: Basis) -> bool:
	return absf(basis.determinant()) > 1e-12


static func _warn_once(mesh: Mesh, message: String, fields: Dictionary) -> void:
	var key := "%d|%s" % [mesh.get_instance_id(), message]
	if not _warned.has(key):
		_warned[key] = true
		GSLog.warn(CHANNEL, message, fields)


static func to_space_of(mi: Node, space: Node3D) -> Transform3D:
	var to_space := Transform3D.IDENTITY
	var walk: Node = mi
	while walk != null and walk != space:
		if walk is Node3D:
			to_space = (walk as Node3D).transform * to_space
		walk = walk.get_parent()
	return to_space



## Whether [param box] (moved by [param to_space]) lies wholly beyond one of [param planes], with a margin for float
## noise: nothing of the surface is inside, so every vertex can be skipped.
static func box_beyond(to_space: Transform3D, planes: Array, box: AABB) -> bool:
	var corners_box: Array[Vector3] = []
	for c in 8:
		corners_box.append(to_space * box.get_endpoint(c))
	for plane: Array in planes:
		var pn: Vector3 = plane[0]
		var pd: float = plane[1] + 0.001
		var all_beyond := true
		for w in corners_box:
			if pn.dot(w) <= pd:
				all_beyond = false
				break
		if all_beyond:
			return true
	return false


## Whether every corner of [param p] is outside one of [param planes]: the triangle misses the region.
static func _outside_any(p: Array[Vector3], planes: Array) -> bool:
	for plane: Array in planes:
		var n: Vector3 = plane[0]
		var d: float = plane[1]
		if n.dot(p[0]) > d and n.dot(p[1]) > d and n.dot(p[2]) > d:
			return true
	return false


## Splits a convex polygon of barycentrics on [param p] by a plane: `[outside, inside]`.
static func split(poly: Array[Vector3], p: Array[Vector3], n: Vector3, d: float) -> Array:
	var outside: Array[Vector3] = []
	var inside: Array[Vector3] = []
	var size := poly.size()
	for k in size:
		var a := poly[k]
		var b := poly[(k + 1) % size]
		var fa := n.dot(p[0] * a.x + p[1] * a.y + p[2] * a.z) - d
		var fb := n.dot(p[0] * b.x + p[1] * b.y + p[2] * b.z) - d
		if fa > 0.0:
			outside.append(a)
		else:
			inside.append(a)
		if (fa > 0.0) != (fb > 0.0):
			var c := a.lerp(b, fa / (fa - fb))
			outside.append(c)
			inside.append(c)
	var none: Array[Vector3] = []
	return [outside if outside.size() >= 3 else none, inside if inside.size() >= 3 else none]


## Warns once per mesh that a surface lay wholly inside the region (shared with the cut job).
static func warn_whole_surface(mesh: Mesh, surface: int) -> void:
	if not _warned.has(mesh.get_instance_id()):
		_warned[mesh.get_instance_id()] = true
		GSLog.warn(CHANNEL, "sight cut removed a whole surface", {"mesh": mesh.resource_name, "surface": surface})
