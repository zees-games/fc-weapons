extends RefCounted

## The fire-sound ratchet of aw_selftest.gd: every gun in AwWeaponPack.SOUND_CLASSES has its own layered shot, each
## file loads and is not trivially short, and no two guns share a file. Clipping, DC offset and spectra are measured by
## tools/audit_fire_sounds.py (it decodes; this suite only checks presence and uniqueness). Reports through the suite.

const MIN_BYTES := 2000
const MIN_SECONDS := 0.03

var suite: Node


func _init(host: Node) -> void:
	suite = host


func run() -> void:
	suite._begin("every gun has its own fire sound")
	var owner_of := {}
	var missing: Array[String] = []
	var short: Array[String] = []
	var shared: Array[String] = []
	var guns := 0
	for gun: StringName in AwWeaponPack.SOUND_CLASSES:
		guns += 1
		for layer: StringName in AwShotLayers.GUN_LAYERS:
			var n := 0
			while FileAccess.file_exists("%s%s/%s_%d.ogg" % [AwShotLayers.GUN_SOUNDS, gun, layer, n]):
				var path := "%s%s/%s_%d.ogg" % [AwShotLayers.GUN_SOUNDS, gun, layer, n]
				var stream := load(path) as AudioStream
				if stream == null or stream.get_length() < MIN_SECONDS or FileAccess.get_file_as_bytes(path).size() < MIN_BYTES:
					short.append(path)
				var sha := FileAccess.get_sha256(path)
				if owner_of.has(sha) and owner_of[sha] != gun:
					shared.append("%s = %s" % [path, owner_of[sha]])
				owner_of[sha] = gun
				n += 1
			if n == 0:
				missing.append("%s/%s" % [gun, layer])
	suite._check("every gun has all four layers %s" % [missing], guns >= 21 and missing.is_empty())
	suite._check("every layer loads and is not near-empty %s" % [short], short.is_empty())
	suite._check("no two guns share a fire sample %s" % [shared], shared.is_empty())
	suite._end()
