class_name AwMinigunSpin
extends RefCounted
## The minigun's barrel spin as sound: a start while the trigger is held, a loop once it is up to speed, a wind-down when it lets go.
## Pure state, no audio: [method step] says which part to start (or to cut), the rig plays it. The simulation has no spin, so this
## follows what the player holds: trigger down, minigun in hand, not switching or reloading, ammo left.

enum State { IDLE, UP, LOOP, DOWN }

## Seconds of the spin_up and spin_down recordings (tools/cut_user_sounds.py MINIGUN_UP / MINIGUN_DOWN).
const UP_SEC := 0.61
const DOWN_SEC := 1.0

const NONE := &""
const STOP := &"stop"

var state: int = State.IDLE
var _t: float = 0.0


func active() -> bool:
	return state != State.IDLE


## One tick of [param dt] seconds with the barrels [param want]ed spinning. Returns the part to start now
## ([code]&"spin_up"[/code], [code]&"spin_loop"[/code], [code]&"spin_down"[/code]) or [code]&""[/code] to carry on.
func step(want: bool, dt: float) -> StringName:
	match state:
		State.IDLE:
			if want:
				return _enter(State.UP, &"spin_up")
		State.UP:
			_t += dt
			if not want:
				return _enter(State.DOWN, &"spin_down")
			if _t >= UP_SEC:
				return _enter(State.LOOP, &"spin_loop")
		State.LOOP:
			if not want:
				return _enter(State.DOWN, &"spin_down")
		State.DOWN:
			_t += dt
			if want:
				return _enter(State.UP, &"spin_up")
			if _t >= DOWN_SEC:
				state = State.IDLE
	return NONE


## Drops, switches, deaths and resets: silence now, no wind-down. True when something was playing.
func stop() -> bool:
	var was := state != State.IDLE
	state = State.IDLE
	_t = 0.0
	return was


func _enter(to: int, part: StringName) -> StringName:
	state = to
	_t = 0.0
	return part
