extends SceneTree
## Scope clips for the visual judge: the sniper (or any scoped gun) held at the hip, aimed, and zoomed through both levels, with landmarks
## (coloured pillars at 8, 25 and 80 m, a fence, ground) in front so the lens shows what is behind it. One PNG per frame under
## <out>/<gun>/<clip>/, which tools/render_scope_clip.sh turns into <out>/<gun>/<clip>.mp4. Args: out dir under the project; gun id (default sniper).
## Clips: hip_idle (lens see-through with sway, no aim), aim_in (raise to the scope), zoom_cycle (both levels, back to the widest), lower.
const W := 960
const H := 540
const FPS := 30
var _view: AwViewModel
var _cam: Camera3D
var _frame := 0
var _dir := ""


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var out := ProjectSettings.globalize_path("res://" + a[0])
	var id := StringName(a[1] if a.size() > 1 else "sniper")
	root.size = Vector2i(W, H)
	_world()
	_cam = Camera3D.new()
	_cam.fov = 90.0
	_cam.position = Vector3(0, 1.6, 0)
	root.add_child(_cam)
	_cam.current = true
	_view = AwViewModel.new()
	_view.ads_rules = AwAdsRules.load_config()  # the game sets it: it sizes the hip pose and holds the zoom levels
	_view.hands_fov = 55.0
	_cam.add_child(_view)
	var art := AwWeaponVisual.make(id)
	AwArtDress.apply(art, AwWeaponArt.weapon_rows("")[id])
	_view.equip(art)
	for _i in 60:
		await _step(false)
	var only := a[2] if a.size() > 2 else ""  # one clip name, default all
	if only.is_empty() or only == "hip_idle":
		await _clip(out, id, "hip_idle", 90, func(_f: int) -> void: _view.aim(false))
	if only.is_empty() or only == "aim_in":
		await _clip(out, id, "aim_in", 75, func(_f: int) -> void: _view.aim(true))
	if only.is_empty() or only == "zoom_cycle":
		await _clip(out, id, "zoom_cycle", 150, func(f: int) -> void:
			_view.aim(true)
			if f == 40 or f == 100:
				_view.cycle_zoom())
	if only.is_empty() or only == "lower":
		await _clip(out, id, "lower", 60, func(_f: int) -> void: _view.aim(false))
	print("RESULT scope clips %s zoom_levels=%s" % [id, str(_view.zoom_scales())])
	quit()


## Renders [param frames] frames of one clip, calling [param drive] before each.
func _clip(out: String, id: StringName, name: String, frames: int, drive: Callable) -> void:
	_dir = "%s/%s/%s" % [out, id, name]
	DirAccess.make_dir_recursive_absolute(_dir)
	for f in frames:
		drive.call(f)
		await _step(true)
		_cam.fov = 90.0 * _view.aim_fov_scale()
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		img.save_png("%s/%04d.png" % [_dir, f])


func _step(_save: bool) -> void:
	_view.advance(1.0 / float(FPS))
	await process_frame


func _world() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.68, 0.82)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	ground.mesh = PlaneMesh.new()
	(ground.mesh as PlaneMesh).size = Vector2(600, 600)
	ground.material_override = _paint(Color(0.35, 0.42, 0.28))
	root.add_child(ground)
	# Pillars in the line of sight and to its sides; the far ones read only through magnification.
	for spec in [[8.0, 0.0, Color(0.9, 0.15, 0.1)], [25.0, -2.0, Color(0.1, 0.7, 0.2)], [80.0, 1.0, Color(0.15, 0.3, 0.95)],
			[80.0, -6.0, Color(0.95, 0.85, 0.1)], [25.0, 5.0, Color(0.9, 0.5, 0.1)]]:
		var pillar := MeshInstance3D.new()
		pillar.mesh = BoxMesh.new()
		(pillar.mesh as BoxMesh).size = Vector3(0.6, 3.0, 0.6) * maxf(1.0, float(spec[0]) / 25.0)
		pillar.position = Vector3(float(spec[1]), 1.5, -float(spec[0]))
		pillar.material_override = _paint(spec[2])
		root.add_child(pillar)
	for i in 40:
		var post := MeshInstance3D.new()
		post.mesh = BoxMesh.new()
		(post.mesh as BoxMesh).size = Vector3(0.2, 1.2, 0.2)
		post.position = Vector3(-14.0 + float(i) * 0.7, 0.6, -50.0)
		post.material_override = _paint(Color(0.8, 0.8, 0.8) if i % 2 == 0 else Color(0.2, 0.2, 0.2))
		root.add_child(post)


func _paint(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	return m
