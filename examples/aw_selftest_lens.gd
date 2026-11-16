extends RefCounted

## The suite's hands-lens and sprint-exit section (fc-fp-gun-scale-1, fc-sprint-exit-pop-1); split out of aw_selftest.gd for file size.
## Reports through the suite's `_begin`, `_check` and `_end`.

const STEP := 1.0 / 60.0
## The most a wall response may move the gun in one 60 fps frame when the body is stopped dead: the pop it replaced was 0.08 m.
const MAX_STEP_M := 0.02

var suite: Node


func _init(host: Node) -> void:
	suite = host


func run() -> void:
	suite._begin("a hands lens keeps moves on screen and a stop does not pop the gun")
	_move_share()
	_turn()
	_sprint_share()
	_stop_dead()
	suite._end()


## Full depth compensation keeps every move; drawn near under a 54-degree (4:3) viewmodel lens a move is cut by the lens's size.
func _move_share() -> void:
	var cam := Camera3D.new()
	cam.fov = 75.0
	var view := AwViewModel.new()
	cam.add_child(view)
	view.hands_fov = DotViewLens.vertical_from_horizontal_4_3(54.0)
	view.hands_depth_comp = 1.0
	var full := view.lens_move_share()
	view.hands_depth_comp = 0.0
	var near := view.lens_move_share()
	var size := DotViewLens.lens_scale(AwViewModel.REFERENCE_FOV, view.hands_fov)
	view.hands_fov = 90.0
	var plain := view.lens_move_share()
	cam.free()
	suite._check("move share: 1 with full depth comp (%.3f), 1/size drawn near (%.3f, size %.2f), 1 at the reference lens (%.3f)" % [full, near, size, plain],
		is_equal_approx(full, 1.0) and absf(near - 1.0 / size) < 0.001 and is_equal_approx(plain, 1.0))


func _turn() -> void:
	var a := deg_to_rad(30.0)
	var kept := AwWeaponPose.lens_turn(a, 1.0)
	var cut := AwWeaponPose.lens_turn(a, 0.4)
	suite._check("a turn under a 2.5x lens keeps its on-screen swing (sin %.3f = 0.4 * %.3f), none under no lens" % [sin(cut), sin(a)],
		is_equal_approx(kept, a) and absf(sin(cut) - 0.4 * sin(a)) < 0.0001)


## A full sprint under share 0.4 moves the gun 0.4 as far on every axis, as full depth compensation drew it.
func _sprint_share() -> void:
	var pose := AwWeaponPose.make()
	pose.tunables.sprint_offset = Vector3(0.2, -0.1, 0.05)
	pose.set_sprint(1.0)
	var whole := pose.offset().origin
	pose.lens_share = 0.4
	var cut := pose.offset().origin
	suite._check("a sprint under share 0.4 moves %s against %s whole" % [str(cut), str(whole)],
		cut.is_equal_approx(0.4 * whole) and not whole.is_zero_approx())


## Sprinting into a body that stops the carrier dead (7 m/s to 0 in one tick) eases the response from push-back to nudge.
func _stop_dead() -> void:
	var wall := AwWallSlam.new()
	var prev := Vector3.ZERO
	var worst := 0.0
	var worst_at := -1
	for i in 90:
		wall.aim_at(Vector3(0.0, 0.0, 1.0), 7.0 if i < 45 else 0.0)
		wall.step(0.12, STEP)
		var now := wall.offset(1.0, 1.0).origin
		if i > 0 and i >= 30:
			var moved := (now - prev).length()
			if moved > worst:
				worst = moved
				worst_at = i
		prev = now
	suite._check("stopped dead against a wall the gun moves at most %.3f m a frame (%.4f at frame %d)" % [MAX_STEP_M, worst, worst_at], worst <= MAX_STEP_M)
