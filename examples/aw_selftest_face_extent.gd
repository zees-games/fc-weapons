extends RefCounted

## The native corner extents and the marked sight line built on them against the script walks they replace; split out of aw_selftest_sight.gd for file size.
## Reports through the suite's `_check`.

const IronSight := preload("res://addons/gs_weapon/view/gs_weapon_iron_sight.gd")

var suite: Node


func _init(host: Node) -> void:
	suite = host


func run() -> void:
	var space := Node3D.new()
	suite.add_child(space)
	var weapon := Node3D.new()
	weapon.transform = Transform3D(Basis(Vector3.UP, 0.7), Vector3(0.1, -0.2, 0.3))
	space.add_child(weapon)
	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radial_segments = 24
	sphere.rings = 12
	body.mesh = sphere
	body.transform = Transform3D(Basis.from_scale(Vector3(0.05, 0.08, 0.6)), Vector3(0.0, 0.01, 0.1))
	weapon.add_child(body)
	var box := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = Vector3(0.03, 0.05, 0.2)
	box.mesh = shape
	box.position = Vector3(0.0, 0.06, -0.3)
	weapon.add_child(box)
	var faces := IronSight.faces_of(weapon, space)
	var same := faces.size() > 0
	for dir: Vector3 in [Vector3.FORWARD, Vector3(0.3, 0.1, -0.9).normalized(), Vector3.UP, Vector3(1, 0, 0)]:
		var want := Vector2(INF, -INF)
		for p: Vector3 in faces:
			want = Vector2(minf(want.x, p.dot(dir)), maxf(want.y, p.dot(dir)))
		same = same and AwViewModel.SightFit.Extent.range_along(faces, dir) == want
	suite._check("native corner extents equal the script walk (%d corners, 4 directions)" % faces.size(), same)
	suite._check("no corners have no extent", AwViewModel.SightFit.Extent.range_along(PackedVector3Array(), Vector3.UP) == Vector2(INF, -INF))
	for mark_name in [IronSight.MARK_REAR, IronSight.MARK_FRONT]:
		var mark := Node3D.new()
		mark.name = StringName(mark_name)
		mark.position = Vector3(0.0, 0.07, 0.25 if mark_name == IronSight.MARK_FRONT else -0.35)
		weapon.add_child(mark)
	for forward: Vector3 in [Vector3.FORWARD, Vector3(0.2, 0.0, -1.0)]:
		suite._check("marked sight line equals IronSight.from_marks (forward %s)" % forward, AwViewModel.SightFit.marked_line(weapon, space, forward) == IronSight.from_marks(weapon, space, forward) and not IronSight.from_marks(weapon, space, forward).is_empty())
	weapon.free()
	space.free()
