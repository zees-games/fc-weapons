extends SceneTree

## Bakes what Nightly's asset viewer needs to show a weapon held the way gs-player-char draws it: per stock body, the skeleton's local bone poses holding a gun,
## where the skeleton sits in the figure, and the hand mount's frame on the right-hand bone. Writes avatars.json and copies each body's glb beside it.
## godot --headless --path . --script tools/export_third_person.gd -- out_dir
const VERSION := 1
const HEIGHT := 1.8


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: export_third_person.gd -- out_dir")
		quit(2)
		return
	var out := args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var host := Node3D.new()
	root.add_child(host)
	await process_frame
	var avatars: Array = []
	for body: StringName in GSHumanoidLook.BODIES:
		var a := _bake(host, body, out)
		if not a.is_empty():
			avatars.append(a)
	DirAccess.copy_absolute(ProjectSettings.globalize_path(GSHumanoidAssets.directory().path_join("atlas_people.png")), "%s/atlas_people.png" % out)
	var f := FileAccess.open("%s/avatars.json" % out, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": VERSION, "height": HEIGHT, "hand_bone": GSHumanoidFigure.HAND_BONE, "held_scale": 1.7, "atlas": "atlas_people.png", "avatars": avatars}))
	f.close()
	print("BAKED %d avatars" % avatars.size())
	quit(0 if avatars.size() == GSHumanoidLook.BODIES.size() else 1)


func _bake(host: Node3D, body: StringName, out: String) -> Dictionary:
	var look := GSHumanoidLook.stock(1)
	look.body = body
	var fig := GSHumanoidFigure.new()
	host.add_child(fig)
	fig.build(look, HEIGHT)
	fig.set_hold(GSHumanoidFigure.Hold.GUN)
	for _i in 30:
		fig.animate(0.0, 1.0 / 60.0)
	var sk := fig.skeleton()
	if sk == null:
		print("SKIP %s (no skeleton)" % body)
		fig.free()
		return {}
	var hand := fig.attachment(&"right_hand")
	var bones := {}
	for i in sk.get_bone_count():
		var p := sk.get_bone_pose(i)
		var q := p.basis.get_rotation_quaternion()
		var s := p.basis.get_scale()
		bones[sk.get_bone_name(i)] = [p.origin.x, p.origin.y, p.origin.z, q.x, q.y, q.z, q.w, s.x, s.y, s.z]
	var file := GSHumanoidAssets.body_path(body)
	var name := "people_%s.glb" % body
	DirAccess.copy_absolute(ProjectSettings.globalize_path(file), "%s/%s" % [out, name])
	var swaps: Array = []
	var colours := {"skin": look.skin, "hair": look.hair, "top": look.top, "bottom": look.bottom}
	var wears: Dictionary = GSHumanoidAssets.WEARS.get(body, {})
	for role: String in ["skin", "hair", "top", "bottom"]:
		for hex: String in wears.get(role, []):
			swaps.append([hex, (colours[role] as Color).to_html(false)])
	var result := {
		"body": String(body), "glb": name, "height": HEIGHT, "swaps": swaps,
		"skeleton_in_figure": _tf(fig.global_transform.affine_inverse() * sk.global_transform),
		"mount": _tf(hand.transform),
		"bones": bones,
	}
	fig.free()
	return result


func _tf(t: Transform3D) -> Array:
	return [t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z, t.basis.z.x, t.basis.z.y, t.basis.z.z, t.origin.x, t.origin.y, t.origin.z]
