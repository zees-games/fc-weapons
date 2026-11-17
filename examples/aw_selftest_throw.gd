extends RefCounted

## The suite's knife-throw windup and sprinting-blade section; split out of aw_selftest.gd for file size.
## Reports through the suite's `_begin`, `_check` and `_end`.

const STEP := 1.0 / 60.0

var suite: Node


func _init(host: Node) -> void:
	suite = host


func run() -> void:
	suite._begin("a knife winds up, releases and pumps on a sprint")
	var pose := AwWeaponPose.make()
	_frames(pose, 0.3, 0.0)
	var rest := pose.offset().origin
	var finite := rest.is_finite()

	var drawn: Array[Vector3] = []
	var shown: Array[float] = []
	for meter in [0.0, 0.5, 1.0] as Array[float]:
		pose.set_windup(meter)
		_frames(pose, 0.3, 0.0)
		drawn.append(pose.offset().origin)
		shown.append(pose.windup_fraction())
		finite = finite and pose.offset().origin.is_finite()
	var full := drawn[2]
	suite._check("a full meter draws the hand up and back past rest (%s from %s)" % [full, rest], full.y > rest.y + 0.08 and full.z > rest.z + 0.05)
	suite._check("an empty meter has already started back (%.2f shown)" % shown[0], shown[0] > 0.15 and drawn[0].y > rest.y + 0.01)
	suite._check("the fuller the meter, the further back (%.2f, %.2f, %.2f)" % shown,
		shown[0] < shown[1] and shown[1] < shown[2] and drawn[0].y < drawn[1].y and drawn[1].y < drawn[2].y)

	pose.throw()
	var start := pose.offset().origin
	suite._check("the release starts from the cocked hand, no jump to rest (%.3f m)" % start.distance_to(full), start.distance_to(full) < 0.02)
	var nearest := INF
	for i in int(0.15 / STEP):
		pose.advance(STEP, Vector2.ZERO, 0.0, true)
		nearest = minf(nearest, pose.offset().origin.z)
		finite = finite and pose.offset().origin.is_finite()
	suite._check("it whips the blade forward of rest (%.3f m ahead)" % (rest.z - nearest), nearest < rest.z - 0.1)
	_frames(pose, 0.6, 0.0)
	suite._check("and comes back to rest (%.3f m)" % pose.offset().origin.distance_to(rest), pose.offset().origin.distance_to(rest) < 0.01 and pose.windup_fraction() == 0.0)

	var melee := AwWeaponArtTable.sprint_pump(AwWeaponArtTable.POSE_MELEE)
	suite._check("a blade pumps on a sprint and a gun does not", melee.length() > 0.0 and AwWeaponArtTable.sprint_pump(AwWeaponArtTable.POSE_THROWN).length() > 0.0
		and AwWeaponArtTable.sprint_pump(&"rifle") == Vector3.ZERO)
	var pumped := _sprint_spread(melee)
	var still := _sprint_spread(Vector3.ZERO)
	suite._check("sprinting, the blade swings with the stride (%.3f m against %.3f m)" % [pumped, still], pumped > still + 0.04)
	var runner := AwWeaponPose.make()
	runner.set_sprint(1.0)
	_frames(runner, 1.0, 7.5)
	suite._check("and hands its stride to the arms (amount %.2f, phase %.2f)" % [runner.run_amount(), runner.run_phase()],
		runner.run_amount() > 0.5 and runner.run_phase() >= 0.0 and runner.run_phase() < 1.0)

	pose.set_windup(NAN)
	_frames(pose, 0.1, 0.0)
	suite._check("a meter that is not a number draws nothing", finite and pose.windup_fraction() == 0.0 and pose.offset().origin.is_finite())

	var catcher := AwWeaponPose.make()
	_frames(catcher, 0.3, 0.0)
	var at_rest := catcher.offset().origin
	catcher.catch()
	var reach := catcher.offset().origin
	var give := -INF
	for i in int(0.2 / STEP):
		catcher.advance(STEP, Vector2.ZERO, 0.0, true)
		give = maxf(give, catcher.offset().origin.z)
	suite._check("a catch meets the blade forward of rest and gives back with it (%.3f m out, %.3f m back)" % [at_rest.z - reach.z, give - at_rest.z],
		reach.z < at_rest.z - 0.08 and give > at_rest.z + 0.01)
	_frames(catcher, 0.6, 0.0)
	suite._check("and settles at rest (%.3f m)" % catcher.offset().origin.distance_to(at_rest), catcher.offset().origin.distance_to(at_rest) < 0.01)

	var rig := AwWeaponRig.new()
	var bare: AwWeaponVisual = rig._empty_hand_art()
	suite._check("an empty hand while a boomerang is out is bare fists, no model", bare.id == AwWeaponIds.FISTS and not bare.has_model()
		and bare.pose == &"fists" and rig.empty_hand_view and not rig._empty_hand_shown())
	rig.free()
	suite._end()


func _frames(pose: AwWeaponPose, seconds: float, speed: float) -> void:
	for i in int(seconds / STEP):
		pose.advance(STEP, Vector2.ZERO, speed, true)


## The depth the weapon covers over a second of sprint, with [param pump] as the art's sprint pump.
func _sprint_spread(pump: Vector3) -> float:
	var pose := AwWeaponPose.make()
	pose.tunables.sprint_pump = pump
	pose.set_sprint(1.0)
	_frames(pose, 0.5, 7.5)
	var lo := INF
	var hi := -INF
	for i in int(1.0 / STEP):
		pose.advance(STEP, Vector2.ZERO, 7.5, true)
		lo = minf(lo, pose.offset().origin.z)
		hi = maxf(hi, pose.offset().origin.z)
	return hi - lo
