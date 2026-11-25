extends RefCounted

## The sliced sight cut (what prewarm runs a frame at a time) against the one-call cut; split out of aw_selftest_sight.gd for file size.
## Reports through the suite's `_check`.

var suite: Node


func _init(host: Node) -> void:
	suite = host


## The sliced cut (a zero budget, so a slice per step) makes exactly the mesh the one-call cut makes.
func run() -> void:
	var cut := AwViewModel.SightFit.Cut.cone(Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.5)), 12.0)
	var results: Array = []
	for sliced in [false, true]:
		AwViewModel.SightFit.Cut.cache.clear()
		var space := Node3D.new()
		var mi := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radial_segments = 64
		sphere.rings = 32
		mi.mesh = sphere
		space.add_child(mi)
		var job := AwViewModel.SightFit.begin([space], space, cut)
		var steps := 0
		if sliced:
			while not job.step(0):
				steps += 1
		else:
			job.run()
		var arrays := mi.mesh.surface_get_arrays(0)
		results.append([job.result, arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_NORMAL], steps])
		space.free()
	suite._check("sliced sight cut matches the one-call cut (%d triangles cut, %d slices)" % [results[0][0].removed, results[1][3]], int(results[0][0].removed) > 0 and results[1][3] > 1 and results[0][0] == results[1][0] and results[0][1] == results[1][1] and results[0][2] == results[1][2])


## The sliced stop-short-of-the-front walk (a zero budget, so a slice per step) gives the one-call cut, which does stop short.
func front() -> void:
	var Cut = AwViewModel.SightFit.Cut
	var cut: Dictionary = Cut.cone(Transform3D(Basis.IDENTITY, Vector3(0, 0, -2.0)), 12.0)
	var results: Array = []
	for sliced in [false, true]:
		Cut._spans.clear()
		Cut._tree.clear()
		var space := Node3D.new()
		var mi := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radial_segments = 64
		sphere.rings = 32
		mi.mesh = sphere
		space.add_child(mi)
		var job: RefCounted = Cut.front_job(cut, space, space)
		var steps := 0
		if sliced:
			while not job.step(0):
				steps += 1
		else:
			job.run()
		results.append([job.result, steps])
		space.free()
	suite._check("sliced front walk matches the one-call walk (stop %.3f, %d slices)" % [float(results[0][0].stop), results[1][1]], is_finite(float(results[0][0].stop)) and results[1][1] > 1 and results[0][0] == results[1][0])
