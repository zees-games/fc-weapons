extends RefCounted

## The playback audit of aw_selftest.gd: every weapon, fired as the local player (play_use), as another player or a bot
## (play_remote) and through the plain voice path (layered shots off), makes a sound with a stream, and a gun's own recording
## is the one asked for. Headless audio has no real driver, so this asserts what AwShotFx asks to play (its [signal heard]
## stream and its voices), not what reaches a speaker. Reports through the suite.

const KIND_OF := {
	&"knife": AwWeaponNet.KIND_SWING, &"frag": AwWeaponNet.KIND_THROW, &"sticky": AwWeaponNet.KIND_THROW,
	&"flash": AwWeaponNet.KIND_THROW, &"smoke": AwWeaponNet.KIND_THROW, &"incendiary": AwWeaponNet.KIND_THROW,
	&"launcher": AwWeaponNet.KIND_SPAWN, &"quad_launcher": AwWeaponNet.KIND_SPAWN, &"grenade_launcher": AwWeaponNet.KIND_SPAWN,
	&"beamer": AwWeaponNet.KIND_BEAM,
}

var suite: Node
var _streams: Array = []


func _init(host: Node) -> void:
	suite = host


func _noted(stream: AudioStream) -> void:
	_streams.append(stream)


func _fx(first_person: bool, layered: bool) -> AwShotFx:
	var fx := AwShotFx.new()
	fx.first_person = first_person
	fx.layered_shots = layered
	fx.visuals = false
	fx.heard.connect(_noted)
	suite.add_child(fx)
	return fx


func _outcome(kind: int) -> GSWeaponOutcome:
	var outcome := GSWeaponOutcome.new()
	outcome.used = true
	outcome.kind = AwWeaponNet.kind_name(kind)
	return outcome


func run() -> void:
	suite._begin("every weapon is heard: local, remote, bot")
	var classed: Array[String] = []
	for id: StringName in AwWeaponPack.IDS:
		if AwWeaponSound.class_for(id, &"shot") == AwWeaponSound.RIFLE and not AwWeaponSound.WEAPONS.has(id) \
				and not AwWeaponPack.SOUND_CLASSES.has(id) and not KIND_OF.has(id):
			classed.append(String(id))
	suite._check("no weapon falls to the generic rifle report by accident: %s" % ", ".join(classed), classed.is_empty())
	var table: Array[String] = []
	for id: StringName in AwWeaponPack.SOUND_CLASSES:
		if not AwWeaponSound.WEAPONS.has(id):
			table.append(String(id))
	suite._check("AwWeaponSound.WEAPONS lists every gun with a sound class: %s" % ", ".join(table), table.is_empty())

	var silent: Array[String] = []
	for layered in [true, false]:
		var local := _fx(true, layered)
		var remote := _fx(false, layered)
		for id: StringName in AwWeaponPack.IDS:
			var kind: int = KIND_OF.get(id, AwWeaponNet.KIND_SHOT)
			_streams.clear()
			local.play_use(_outcome(kind), Transform3D.IDENTITY, id)
			if _streams.is_empty() or _streams[0] == null:
				silent.append("local %s%s" % [id, "" if layered else " (plain)"])
			_streams.clear()
			remote.play_remote(kind, Transform3D.IDENTITY, Vector3.FORWARD, id)
			if _streams.is_empty() or _streams[0] == null:
				silent.append("remote %s%s" % [id, "" if layered else " (plain)"])
			local.advance(1.0)
			remote.advance(1.0)
		if not layered:
			suite._check("the plain path holds voices for local and remote",
				int(local.describe()["voices"]) > 0 and int(remote.describe()["voices"]) > 0)
		local.free()
		remote.free()
	suite._check("every weapon is heard as local and remote, layered and plain: %s" % ", ".join(silent), silent.is_empty())

	var far := _fx(false, false)
	var was := AwShotFx.rules.voice_distance
	AwShotFx.rules.voice_distance = 50.0
	var cam := Camera3D.new()
	suite.add_child(cam)
	cam.current = true
	_streams.clear()
	far.play_remote(AwWeaponNet.KIND_SHOT, Transform3D(Basis.IDENTITY, Vector3(0, 0, -40)), Vector3.FORWARD, &"rifle")
	var near_heard := not _streams.is_empty()
	_streams.clear()
	far.play_remote(AwWeaponNet.KIND_SHOT, Transform3D(Basis.IDENTITY, Vector3(0, 0, -400)), Vector3.FORWARD, &"rifle")
	suite._check("a report inside the voice distance is heard and one beyond it is not", near_heard and _streams.is_empty())
	AwShotFx.rules.voice_distance = was
	cam.free()
	far.free()

	var plain := _fx(false, false)
	var cap := plain._voice_cap()
	for _i in 12:
		plain.play_remote(AwWeaponNet.KIND_SHOT, Transform3D.IDENTITY, Vector3.FORWARD, &"smg")
	suite._check("a burst past the voice cap still plays its last shot (%d voices of cap %d)" % [int(plain.describe()["voices"]), cap],
		int(plain.describe()["voices"]) <= cap and int(plain.describe()["voices"]) > 0 and not _streams.is_empty())
	plain.free()
	suite._end()
