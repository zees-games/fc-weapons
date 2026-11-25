extends RefCounted

## The suite's third-person inspect section: the held gun turns through the first-person inspect's fraction and lets
## go when it stops being told. Reports through the suite's `_begin`, `_check` and `_end`.

const STEP := 1.0 / 60.0

var suite: Node


## The least a person is to a held gun: it answers swing and set_hold, and has no carry of its own.
class Holder extends Node3D:
	func swing(_which: StringName) -> void:
		pass

	func set_hold(_kind: int) -> void:
		pass


func _init(host: Node) -> void:
	suite = host


func run() -> void:
	suite._begin("a held gun turns through the inspect it is told")
	var person := Holder.new()
	suite.add_child(person)
	var held := AwWorldModel.new()
	person.add_child(held)
	held.equip(suite._dressed(&"rifle"))
	held.advance(STEP)
	var rest: Transform3D = held._holder.transform
	held.on_inspect(0.42)
	held.advance(STEP)
	var looked: Transform3D = held._holder.transform
	var rolled := rad_to_deg(rest.basis.get_rotation_quaternion().angle_to(looked.basis.get_rotation_quaternion()))
	suite._check("at the left-side key the gun is rolled well past a wrist's twitch (%.1f degrees)" % rolled, rolled > 45.0)
	suite._check("and lifted toward the face (%.3f m)" % (looked.origin.y - rest.origin.y), looked.origin.y > rest.origin.y + 0.03)
	suite._check("the fraction reads back", is_equal_approx(held.inspect_fraction(), 0.42))
	held.on_inspect(0.72)
	held.advance(STEP)
	var across: Transform3D = held._holder.transform
	suite._check("at the right-side key it rolls the other way",
		signf(looked.basis.get_euler().z - rest.basis.get_euler().z) != signf(across.basis.get_euler().z - rest.basis.get_euler().z))
	# Not told again: the inspect was cut short, and the gun eases back into the hand.
	held.advance(STEP)
	var easing: Transform3D = held._holder.transform
	suite._check("cut short it eases rather than snapping (%.3f m off rest)" % easing.origin.distance_to(rest.origin),
		easing.origin.distance_to(rest.origin) > 0.005)
	for _i in range(30):
		held.advance(STEP)
	suite._check("and is back in the hand (%.4f m)" % held._holder.transform.origin.distance_to(rest.origin),
		held._holder.transform.is_equal_approx(rest) and held.inspect_fraction() == 1.0)
	held.on_inspect(NAN)
	held.advance(STEP)
	suite._check("a fraction that is not a number turns nothing", held._holder.transform.is_equal_approx(rest))
	held.on_inspect(1.0)
	held.advance(STEP)
	suite._check("and one told as finished turns nothing", held._holder.transform.is_equal_approx(rest))
	person.queue_free()
	suite._end()
