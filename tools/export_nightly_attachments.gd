extends SceneTree
## Writes what Nightly needs to list the attachments as assets of their own and link them to the guns they fit:
## <out>/att_<id>.glb for each attachment model and <out>/attachments.json (an rsi-assets audit document with `attach_links`).
## Every number comes from the game's own tables, nothing is repeated here: the mounts and their positions from AwAttachmentSockets.SOCKETS,
## the attachments from AwAttachmentPack.ROWS, the gun tiers from AwWeaponArt.WEAPONS (an attachment's `excludes` names tiers).
## Run through tools/publish_nightly.sh, or: godot --headless --path . --script res://tools/export_nightly_attachments.gd -- <out dir> [<glb dir relative to the pack root>]
## Positions are in the gun model's space, which is the gun glb's space (grip at the origin, muzzle toward -Z); rotation is identity and scale 1
## because the game seats the attachment model at the socket with no offset (AwAttachmentSockets.ensure).

const PACK := "fc-weapons"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: -- <out dir> [<glb dir relative to the pack root, as Nightly reads it>]")
		quit(2)
		return
	var out_dir := args[0]
	var rel := args[1] if args.size() > 1 else "build/nightly"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var assets: Array = []
	for id: StringName in AwAttachmentPack.ROWS:
		var row: Dictionary = AwAttachmentPack.ROWS[id]
		var item := AwAttachmentPack.ITEM_PREFIX + String(id)
		var scene := load(AwAttachmentPack.MODEL_DIR + String(id) + ".tscn") as PackedScene
		if scene == null:
			push_error("no model for attachment %s" % id)
			quit(1)
			return
		var node := scene.instantiate()
		var state := GLTFState.new()
		var doc := GLTFDocument.new()
		var file := "%s/%s.glb" % [out_dir, item]
		if doc.append_from_scene(node, state) != OK or doc.write_to_filesystem(state, file) != OK:
			push_error("glb export failed for %s" % id)
			quit(1)
			return
		node.free()
		assets.append({
			"pack": PACK, "weapon_id": item, "kind": "attachment", "flags": [],
			"model": {"glb": "%s/%s.glb" % [rel, item]},
		})
	var tier := {}
	for wid: StringName in AwWeaponArt.WEAPONS:
		var w: Dictionary = AwWeaponArt.WEAPONS[wid]
		tier[String(w["model"])] = str(w.get("tier", ""))
	var links: Array = []
	for key: StringName in AwAttachmentSockets.SOCKETS:
		var sockets: Dictionary = AwAttachmentSockets.SOCKETS[key]
		for id: StringName in AwAttachmentPack.ROWS:
			var row: Dictionary = AwAttachmentPack.ROWS[id]
			var mount := String(row["mount"])
			var excludes: Array = []
			for t: Variant in row.get("excludes", []):
				excludes.append(String(t))
			if not sockets.has(mount) or excludes.has(tier.get(String(key), "")):
				continue
			var at: Vector3 = sockets[mount]
			links.append({
				"pack": PACK, "parent": String(key), "attachment": AwAttachmentPack.ITEM_PREFIX + String(id), "slot": mount,
				"pos": [at.x, at.y, at.z], "rot": [0, 0, 0], "scale": [1, 1, 1],
				"node": str(sockets.get("mag", "")) if mount == "magazine" else "",
				"meta": {"name": str(row["name"]), "tier": tier.get(String(key), ""), "excludes": excludes,
					"aim": str(row.get("aim", "")), "zoom": float(row.get("zoom", 0.0))},
			})
	var f := FileAccess.open(out_dir.path_join("attachments.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"schema": "rsi-assets/2", "generated_at": Time.get_datetime_string_from_system(true), "assets": assets, "attach_links": links}, "  "))
	f.close()
	print("export_nightly_attachments: %d attachments, %d links -> %s" % [assets.size(), links.size(), out_dir])
	quit()
