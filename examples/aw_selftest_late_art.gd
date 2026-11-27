extends RefCounted

## The suite's late addon group section: a table or menu picture made while a web shell's late addon group was still
## streaming holds stand-in art (every primary the base rifle) and must be rebuilt once the group is mounted, and every
## weapon's model must be its own file. Reports through the suite's `_begin`, `_check` and `_end`.

var suite: Node


func _init(host: Node) -> void:
	suite = host


func run() -> void:
	suite._begin("late addon group: art and previews refresh, every weapon's model is its own")
	var models := {}
	var shared := ""
	for role: StringName in AwWeaponArt.weapon_rows(""):
		var model := str((AwWeaponArt.weapon_rows("")[role] as Dictionary)["model"])
		if models.has(model):
			shared = "%s and %s" % [role, models[model]]
		models[model] = role
	suite._check("no two weapon rows share a model file (%s)" % shared, shared == "")
	var missing: Array = []
	for model: Variant in models:
		if not AwModelCache.exists(str(model)):
			missing.append(models[model])
	suite._check("every weapon row's model exists (missing %s)" % str(missing), missing.is_empty())
	var table_ids := AwWeaponArtTable.table().keys()
	var paths := {}
	var dup := ""
	for id: Variant in table_ids:
		var art: AwWeaponVisual = AwWeaponArtTable.table()[id]
		if art.model_path != "" and paths.has(art.model_path) and not str(id).begins_with("preview_"):
			dup = "%s=%s" % [id, paths[art.model_path]]
		paths[art.model_path] = id
	suite._check("the art table gives no two weapons one model (%s)" % dup, dup == "")
	# A source whose art appears only once the "group" is mounted, as a pack's models do.
	var mounted := [false]
	var art := AwWeaponVisual.new()
	art.id = &"aw_late_probe"
	art.model_path = str((AwWeaponArt.weapon_rows("")[AwWeaponArt.weapon_rows("").keys()[0]] as Dictionary)["model"])
	AwWeaponArtTable.add_source(&"aw_selftest_late", func() -> Array[AwWeaponVisual]: return [art] if mounted[0] else [])
	var base := AwWeaponVisual.new()
	base.id = &"aw_late_base"
	AwWeaponArtTable.add_source(&"aw_selftest_late_base", func() -> Array[AwWeaponVisual]: return [base])
	ProjectSettings.set_setting(AwModelCache.LATE_PENDING, true)
	AwWeaponArtTable.drop_cache()
	var held := AwWeaponArtTable.table()
	suite._check("while pending the table is cached", AwWeaponArtTable.table() == held and not held.has(&"aw_late_probe"))
	var previews := AwWeaponPreview.new()
	suite.add_child(previews)
	suite._check("a weapon with no art yet has no picture", previews.texture(&"aw_late_probe") == null and previews.cached_count() == 1)
	mounted[0] = true
	suite._check("still pending, the old table and the empty answer are kept", not AwWeaponArtTable.table().has(&"aw_late_probe") and previews.texture(&"aw_late_probe") == null)
	ProjectSettings.set_setting(AwModelCache.LATE_PENDING, false)
	suite._check("once the group is mounted the table is rebuilt", AwWeaponArtTable.table().has(&"aw_late_probe"))
	suite._check("the preview forgets what it saw pending and draws the real model", previews.texture(&"aw_late_probe") != null)
	previews.queue_free()
	AwWeaponArtTable.remove_source(&"aw_selftest_late")
	AwWeaponArtTable.remove_source(&"aw_selftest_late_base")
	suite._end()
