extends RefCounted

## The ADS axis section of the self-test; split out of aw_selftest_sight.gd for file size. Reports through the suite's `_check`.

var suite: Node


func _init(host: Node) -> void:
	suite = host


## The eye sits on the scope axis: at full aim the ocular's centre is on the camera's forward axis and the bore runs along it, so the rifle
## is not seen diagonally under the ring. Prints the ocular's offset from the axis and the bore's angle off it (degrees).
func run() -> void:
	suite._begin("ADS aim: ocular on the camera axis, bore along it")
	for roleid in [&"sniper", &"marksman", &"charge_rifle"]:
		var port := SubViewport.new()
		port.size = Vector2i(1280, 720)
		suite.add_child(port)
		var camera := Camera3D.new()
		camera.fov = 75.0
		port.add_child(camera)
		var view := AwViewModel.new()
		view.show_arms = false
		view.scope_body = true
		camera.add_child(view)
		var art := AwWeaponVisual.make(roleid)
		AwArtDress.apply(art, AwWeaponArt.weapon_rows("")[roleid])
		view.equip(art)
		view.aim(true)
		for _i in 80:
			view._process(0.02)
		var points := view.scope_ocular_points()
		var to_camera := camera.global_transform.affine_inverse()
		var centre: Vector3 = to_camera * (points.get("centre", Vector3(0, 0, -1)) as Vector3)
		var off := rad_to_deg(atan2(Vector2(centre.x, centre.y).length(), -centre.z))
		var bore: Vector3 = to_camera.basis * (view._holder.global_transform.basis * Vector3(0, 0, -1)).normalized()
		var tilt := rad_to_deg(acos(clampf(-bore.z, -1.0, 1.0)))
		print("ads axis %s: ocular off %.2f deg (x %.4f y %.4f z %.3f), bore %.2f deg off the view axis" % [roleid, off, centre.x, centre.y, centre.z, tilt])
		suite._check("%s: ocular within 0.5 deg of the view axis (%.2f)" % [roleid, off], not points.is_empty() and off < 0.5)
		suite._check("%s: bore within 2 deg of the view axis (%.2f)" % [roleid, tilt], tilt < 2.0)
		suite._check("%s: the ocular is in front of the eye" % roleid, centre.z < -0.02)
		port.queue_free()
	suite._end()
