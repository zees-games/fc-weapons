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


## A view out in the world, turned and kicked by a shot, reads the sight line a view at the origin measured: no line is measured twice.
func posed() -> void:
	var lines: Dictionary = AwViewModel.SightFit._lines
	var arts: Array[AwWeaponVisual] = []
	for id: StringName in [&"revolver", &"battle_rifle", &"smg"]:
		var art := AwWeaponVisual.make(id)
		AwArtDress.apply(art, AwWeaponArt.weapon_rows("")[id])
		arts.append(art)
	var counts: Array[int] = []
	for at: Transform3D in [Transform3D.IDENTITY, Transform3D(Basis.from_euler(Vector3(0.31, 1.27, 0.0)), Vector3(1234.5, 67.8, -912.3))]:
		var place := Node3D.new()
		place.transform = at
		suite.add_child(place)
		var view := AwViewModel.new()
		view.show_arms = false
		place.add_child(view)
		for art in arts:
			view.equip(art)
			view.on_fired()
			view.advance(0.016)
		counts.append(lines.size())
		place.free()
	suite._check("a posed view out in the world measures no sight line again (%d lines, then %d)" % [counts[0], counts[1]], counts[0] > 0 and counts[1] == counts[0])



## A refit (a second cut on the same build) cuts the whole part, not the last copy; no hole puts the whole part back; the cache keeps its limit.
func refit() -> void:
	var Cut = AwViewModel.SightFit.Cut
	Cut.cache.clear()
	var space := Node3D.new()
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radial_segments = 64
	sphere.rings = 32
	mi.mesh = sphere
	space.add_child(mi)
	var wide: Dictionary = Cut.cone(Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.5)), 12.0)
	var narrow: Dictionary = Cut.cone(Transform3D(Basis.IDENTITY, Vector3(0.05, 0, -0.5)), 6.0)
	AwViewModel.SightFit.begin([space], space, narrow).run()
	var alone: int = (mi.mesh as Mesh).surface_get_array_len(0)
	mi.mesh = sphere
	AwViewModel.SightFit.begin([space], space, wide).run()
	AwViewModel.SightFit.begin([space], space, narrow).run()
	var refitted := mi.mesh as Mesh
	AwViewModel.SightFit.begin([space], space, {}).run()
	var back: bool = mi.mesh == sphere
	var limit: int = Cut.cache_limit
	Cut.cache_limit = 1
	AwViewModel.SightFit.begin([space], space, wide).run()
	var kept: int = Cut.cache.size()
	Cut.cache_limit = limit
	space.free()
	Cut.cache.clear()
	suite._check("sight refit cuts the whole part (%d vertices, alone %d), no hole restores it, cache keeps its limit" % [refitted.surface_get_array_len(0), alone],
		refitted != sphere and Cut.source_of(refitted) == sphere and refitted.surface_get_array_len(0) == alone and back and kept == 1)
