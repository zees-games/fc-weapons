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
## Meta on a cut copy: the mesh it was cut from, so a refit cuts the whole part again, not the last hole.
const SOURCE_META := &"aw_cut_source"

## Cuts made, by source mesh and cut: `{mesh, removed, near, far}`. Least recently used first; [method cached] and [method remember] keep the order.
static var cache: Dictionary = {}
## How many cuts [member cache] keeps (0 keeps every one); the least recently used is dropped first. A cut mesh is a de-indexed copy of
## a whole gun part (several MB for a 40k-triangle rifle), and every fitting of every gun is a cut of its own.
static var cache_limit: int = 128
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
	var job := front_job(cut, node, space, from)
	job.run()
	return job.result


## [method short_of_front] as a job: [code]step(usec)[/code] it a frame at a time, then read its `result`.
static func front_job(cut: Dictionary, node: Node, space: Node3D, from: float = 0.55) -> RefCounted:
	# Loaded here, not preloaded: the job preloads this script, and a preload cycle is refused.
	return load("res://addons/fc_weapons/view/aw_sight_front_job.gd").new(cut, node, space, from)


## The mesh [param mesh] was cut from, or [param mesh] itself when it is no cut copy.
static func source_of(mesh: Mesh) -> Mesh:
	if mesh == null or not mesh.has_meta(SOURCE_META):
		return mesh
	var source: Variant = mesh.get_meta(SOURCE_META)
	return source as Mesh if source is Mesh else mesh


## The cut kept under [param key] (moved to most recently used), or `{}`.
static func cached(key: String) -> Dictionary:
	if not cache.has(key):
		return {}
	var done: Dictionary = cache[key]
	cache.erase(key)
	cache[key] = done
	return done


## Keeps [param done] under [param key], dropping the least recently used past [member cache_limit].
static func remember(key: String, done: Dictionary) -> void:
	cache.erase(key)
	cache[key] = done
	while cache_limit > 0 and cache.size() > cache_limit:
		cache.erase(cache.keys()[0])


## A mesh's collision-style triangle tree, built natively once: [method short_of_front] asks it one segment instead of walking every triangle in script.
static func _triangle_mesh(mesh: Mesh) -> TriangleMesh:
	var id := mesh.get_instance_id()
	if not _tree.has(id):
		_tree[id] = mesh.generate_triangle_mesh()
	return _tree[id]


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
