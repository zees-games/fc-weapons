extends Node3D
## The belt of a belt-fed gun: rounds from the ammo box to the feed tray, one step per shot.
## Six instances of one mesh and material, a child of the weapon; nothing draws unless firing.

## Smallest scale a belt round shrinks to: nothing flat, so the sight cut can invert its transform.
const MIN_GROW := 0.001
const COUNT := 6
## Rounds per second the belt can be pulled at: a gun firing faster than this shows a belt at its limit, not a blur.
const MAX_RATE := 14.0
## Sides of every lathed part: round enough that a close-up shows no flats, cheap enough for six instances.
const SIDES := 16

var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _rounds: Array[MeshInstance3D] = []
var _phase := 0.0
var _target := 0.0


## Builds the run from [param from] (at the box) to [param to] (at the feed tray), in the weapon's space.
func build(from: Vector3, to: Vector3) -> void:
	_from = from
	_to = to
	var mesh := _round_mesh()
	for i in COUNT:
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_rounds.append(node)
	_place()


## One round is drawn into the gun.
func step() -> void:
	_target += 1.0


## Where the belt is, in rounds of travel; the tests read it.
func travelled() -> float:
	return _phase


func advance(delta: float) -> void:
	if _phase < _target:
		_phase = minf(_phase + MAX_RATE * delta, _target)
		_place()
	elif _target > 64.0:
		_phase -= 64.0
		_target -= 64.0


func _place() -> void:
	for i in _rounds.size():
		var t := fposmod((float(i) + _phase) / float(COUNT), 1.0)
		var at := _from.lerp(_to, t)
		# A belt hangs between its ends: sagging mid-run, taut where it meets the tray.
		at.y -= sin(t * PI) * 0.025 * (1.0 - t)
		var node := _rounds[i]
		node.position = at
		# The round that has just wrapped is hidden: it is in the receiver, and a new one is at the box.
		# Hidden by shrinking, never to exactly nothing: a flat basis has no inverse, and the sight cut walks these meshes.
		var grow := clampf(minf(t, 1.0 - t) * 12.0, 0.0, 1.0)
		node.scale = Vector3.ONE * maxf(grow, MIN_GROW)
		node.visible = grow > 0.0


## One cartridge on its link, along +Y with the base at the origin side: a brass case (rim, body, shoulder, neck), a
## copper-jacketed ogive bullet and a steel link band. An ArrayMesh with three surfaces: the sight cut walks every mesh
## under the gun and cannot read a primitive one.
static func _round_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	# (height, radius) profiles, base to tip; each is a lathe turned SIDES times, flat-shaded along the profile only.
	var case_profile: Array[Vector2] = [
		Vector2(-0.025, 0.0), Vector2(-0.025, 0.0070), Vector2(-0.0225, 0.0070), Vector2(-0.0225, 0.0058),
		Vector2(-0.0205, 0.0058), Vector2(-0.0205, 0.0064), Vector2(0.004, 0.0060), Vector2(0.0085, 0.0040),
		Vector2(0.0125, 0.0037), Vector2(0.0125, 0.0)]
	var bullet_profile: Array[Vector2] = [Vector2(0.0125, 0.0)]
	# An ogive: radius falls off as a circular arc to a rounded point.
	for k in 7:
		var u := float(k) / 6.0
		bullet_profile.append(Vector2(0.0125 + 0.016 * u, 0.0037 * sqrt(maxf(1.0 - u * u * 0.94, 0.0))))
	bullet_profile.append(Vector2(0.0285, 0.0))
	var link_profile: Array[Vector2] = [
		Vector2(-0.0085, 0.0064), Vector2(-0.0085, 0.0077), Vector2(-0.0020, 0.0077), Vector2(-0.0020, 0.0064)]
	_lathe(mesh, case_profile, Color(0.86, 0.62, 0.2), 0.9, 0.28)
	_lathe(mesh, bullet_profile, Color(0.62, 0.34, 0.2), 0.85, 0.32)
	_lathe(mesh, link_profile, Color(0.42, 0.44, 0.47), 0.95, 0.45)
	return mesh


## Turns [param profile] about Y into one surface of [param mesh] with its own material.
static func _lathe(mesh: ArrayMesh, profile: Array[Vector2], colour: Color, metallic: float, rough: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in profile.size() - 1:
		var a := profile[i]
		var b := profile[i + 1]
		var tangent := b - a
		if tangent.length() < 0.00001:
			continue
		# Outward normal of the segment in (height, radius) space.
		var n2 := Vector2(-tangent.y, tangent.x).normalized()
		for s in SIDES:
			var a0 := TAU * float(s) / float(SIDES)
			var a1 := TAU * float(s + 1) / float(SIDES)
			var p00 := Vector3(cos(a0) * a.y, a.x, sin(a0) * a.y)
			var p01 := Vector3(cos(a1) * a.y, a.x, sin(a1) * a.y)
			var p10 := Vector3(cos(a0) * b.y, b.x, sin(a0) * b.y)
			var p11 := Vector3(cos(a1) * b.y, b.x, sin(a1) * b.y)
			var n0 := Vector3(cos(a0) * n2.y, n2.x, sin(a0) * n2.y)
			var n1 := Vector3(cos(a1) * n2.y, n2.x, sin(a1) * n2.y)
			var corners: Array[Vector3] = [p00, p11, p10, p00, p01, p11]
			var normals: Array[Vector3] = [n0, n1, n0, n0, n1, n1]
			for c in corners.size():
				st.set_normal(normals[c])
				st.add_vertex(corners[c])
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.metallic = metallic
	mat.roughness = rough
	st.set_material(mat)
	st.commit(mesh)
