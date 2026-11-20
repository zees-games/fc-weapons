extends SceneTree
## Close-up sheet of the attachment models alone under studio light: one row per id, columns a front three-quarter view from above and a rear view (what the eye sees through an optic).
## tools/render_attach_models.sh <out.png under the project> <id>...   (ids as in make_attachments.gd)

const W := 640
const H := 400
const DIR := "res://addons/fc_weapons/assets/attachments/"
const BACK := Color(0.52, 0.56, 0.62)


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	var ids: Array = a.slice(1)
	root.size = Vector2i(W, H)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = BACK
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	root.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 200, 0)
	fill.light_energy = 0.5
	root.add_child(fill)
	var cam := Camera3D.new()
	cam.fov = 35.0
	root.add_child(cam)
	cam.current = true
	var sheet := Image.create(W * 2, H * ids.size(), false, Image.FORMAT_RGB8)
	for row in ids.size():
		var model: Node3D = (load(DIR + String(ids[row]) + ".tscn") as PackedScene).instantiate()
		root.add_child(model)
		var box := _bounds(model)
		var centre := box.get_center()
		var radius := box.size.length() * 0.5
		var dist := radius / sin(deg_to_rad(cam.fov * 0.5)) * 0.9
		for col in 2:
			var dir := Vector3(-0.7, 0.55, -0.6).normalized() if col == 0 else Vector3(0.12, 0.1, 1.0).normalized()
			cam.look_at_from_position(centre + dir * dist, centre)
			await process_frame
			await process_frame
			var img := root.get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			sheet.blit_rect(img, Rect2i(0, 0, W, H), Vector2i(col * W, row * H))
		model.queue_free()
	out = ProjectSettings.globalize_path("res://" + out)
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	sheet.save_png(out)
	print("RESULT %s %d models" % [out, ids.size()])
	quit()


func _bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var local := mi.get_aabb()
		for i in 8:
			var p := mi.transform * local.get_endpoint(i)
			box = AABB(p, Vector3.ZERO) if first else box.expand(p)
			first = false
	return box
