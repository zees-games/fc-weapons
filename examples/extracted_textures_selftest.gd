extends Node
## Headless suite: every texture the game renders beside a GLB is that GLB's own image, byte for byte. Godot never
## rewrites an extracted image, so a rebake that skips them ships the old textures; fix with the --fix run below.
##   godot --headless --path . --script res://addons/gs_weapon/tools/gs_weapon_glb_extracted.gd -- --fix res://addons/fc_weapons

const Extracted := preload("res://addons/gs_weapon/tools/gs_weapon_glb_extracted.gd")
const ROOT := "res://addons/fc_weapons"


func _ready() -> void:
	print("fc-weapons extracted textures")
	var bad := Extracted.stale(ROOT)
	for line in bad:
		print("  FAIL %s" % line)
	var glbs := Extracted.extracting(ROOT).size()
	if glbs == 0:
		bad.append("no extracting GLB found under %s" % ROOT)
		print("  FAIL no extracting GLB found under %s" % ROOT)
	else:
		print("  ok   %d GLBs checked" % glbs)
	print("%d checks, %d failed" % [glbs, bad.size()])
	get_tree().quit(1 if bad.size() > 0 else 0)
