extends SceneTree
## Close-up of the lmg belt feed: godot --script tools/render_belt.gd -- <out.png>
## Windowed (xvfb); a geometry check of the round meshes, not a visual-judge capture.

const BeltFeed := preload("res://addons/fc_weapons/view/aw_belt_feed.gd")


func _init() -> void:
	var out := "belt.png"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var belt := BeltFeed.new()
	root.add_child(belt)
	belt.build(Vector3(-0.1, 0.0, 0.0), Vector3(0.1, 0.0, 0.0))
	await process_frame
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.fov = 30.0
	cam.position = Vector3(0.0, 0.05, 0.22)
	cam.make_current()
	cam.look_at(Vector3(0.0, -0.01, 0.0))
	var key := DirectionalLight3D.new()
	root.add_child(key)
	key.rotation_degrees = Vector3(-35.0, 25.0, 0.0)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.3, 0.32, 0.36)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.65)
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	for i in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	print("RESULT ", out)
	quit()
