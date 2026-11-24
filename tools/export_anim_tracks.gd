extends SceneTree

## Bakes each weapon's procedural first-person animations into <model>.anim.json (see aw_anim_bake.gd): the sidecar Nightly's asset
## viewer plays next to the model. Args: out_dir [id,id ...] [pack]; the file is named like Nightly's GLB for the model (pack__path__with__underscores) so the viewer finds it beside the asset. No ids bakes every weapon in AwWeaponArt.
## godot --headless --path . --script tools/export_anim_tracks.gd -- out_dir sniper
const Bake := preload("aw_anim_bake.gd")
const PACK := "fc-weapons"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: export_anim_tracks.gd -- out_dir [ids]")
		quit(2)
		return
	var out := args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var wanted: PackedStringArray = args[1].split(",") if args.size() > 1 and args[1] != "" else PackedStringArray()
	var defs := {}
	for d in AwWeaponPack.weapons({}, "", false):
		defs[d.id] = d
	var host := Node3D.new()
	root.add_child(host)
	await process_frame
	var failed := 0
	for id: StringName in AwWeaponArt.weapon_rows(""):
		if not wanted.is_empty() and not String(id) in wanted:
			continue
		var sidecar := Bake.new().bake(host, id, defs.get(id))
		if sidecar.is_empty():
			print("SKIP %s (no model)" % id)
			continue
		var path := "%s/%s.anim.json" % [out, sidecar.asset]
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			failed += 1
			push_error("cannot write %s" % path)
			continue
		f.store_string(JSON.stringify(sidecar))
		f.close()
		var n := 0
		for c: Dictionary in sidecar.clips:
			n += (c.tracks as Array).size()
		print("BAKED %s -> %s (%d clips, %d tracks)" % [id, path, (sidecar.clips as Array).size(), n])
	quit(1 if failed > 0 else 0)
