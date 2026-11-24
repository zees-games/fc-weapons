@tool
extends "aw_weapon_rig_state.gd"

## Reload, fire-mode and switch callbacks of AwWeaponRig, split out for file size.

## A reload sound played (RELOAD_OUT at the start, RELOAD_IN at the end); never on a server or in a replay.
signal reload_sound(stage: StringName)

## The fire-mode selector clicked (the sound id); never on a server or in a replay.
signal mode_click(sound: StringName)

## A handling sound of a reload played, at the animation moment that makes it; never on a server or in a replay.
signal reload_cue_played(cue: StringName, weapon_id: StringName)


func _on_reload_started(slot: int) -> void:
	var carried := arsenal.slot_at(slot)

	if carried == null:
		return

	_reload_started = _last_tick
	_reload_ticks = reload_motion_ticks(carried.def, carried.magazine_space())
	_cued_reload = false
	if _view != null and not _replaying:
		var start := float(arsenal.ticks_for(carried.def, carried.def.reload_start_ticks)) if carried.def.reload_per_round else 0.0
		_view.on_reload_begin(carried.magazine, carried.def.magazine, start / float(_reload_ticks))
		# With a plan the sounds come from the animation (see _on_reload_cue); the two fixed ones would double them.
		_cued_reload = _view.has_reload_cues()
		if _cued_reload and not _view.reload_cue.is_connected(_on_reload_cue):
			_view.reload_cue.connect(_on_reload_cue)
		_cue_weapon = carried.def.id

	# A tube magazine has no magazine to drop: its shells are heard one by one.
	if not carried.def.reload_per_round and not _cued_reload:
		_reload_sound(AwWeaponSound.RELOAD_OUT, carried.def.id)


## A handling sound the reload animation reached; never on a server or in a replay.
func _on_reload_cue(cue: StringName, db: float) -> void:
	if _replaying or role == Role.SERVER or _fx == null:
		return
	# The cycle cues (bolt, pump) come between reloads, when _cue_weapon is stale: the gun in the hands is the one cycling.
	var held := arsenal.current()
	_fx.play_cue(cue, _listen_at(), db, held.def.id if held != null and held.def != null else _cue_weapon)
	reload_cue_played.emit(cue, _cue_weapon)


## Ticks the reload motion spans: exactly the arsenal's reload, so its fraction reaches 1 as the reload ends and the gun is home again. A per-round
## reload lands its first round as the start ends and each further one a round time later: the start plus one round time per missing round after the
## first. One round time more would end the motion mid-roll and snap the gun to idle in one frame.
func reload_motion_ticks(def: GSWeaponDef, space: int) -> int:
	var ticks := def.reload_ticks
	if def.reload_per_round:
		ticks = def.reload_start_ticks + def.reload_ticks * maxi(space - 1, 0)
	return maxi(1, arsenal.ticks_for(def, ticks))


func _on_fire_mode_changed(slot: int, _mode: int) -> void:
	if _replaying or role == Role.SERVER:
		return
	var carried := arsenal.slot_at(slot)
	if carried == null:
		return
	var click := AwWeaponSound.mode_click_for(carried.def.id)
	mode_click.emit(click)
	if _fx != null:
		_fx.play_mode_click(_listen_at(), carried.def.id)


func _on_dry_used(slot: int) -> void:
	if _replaying or role == Role.SERVER or _fx == null:
		return
	var carried := arsenal.slot_at(slot)
	_fx.play_dry(_listen_at(), carried.def.id if carried != null else &"")


## One shell sound for every round a per-round reload has added since the last tick.
func _per_round_sound() -> void:
	var carried := arsenal.current()
	if carried == null or not carried.def.reload_per_round:
		_rounds_seen = -1
		return
	# The last round lands on the tick the reload ends, so compare before checking is_reloading.
	if _rounds_seen >= 0 and carried.magazine > _rounds_seen and _fx != null:
		_fx.play_reload_shell(_listen_at(), carried.def.id)
	_rounds_seen = carried.magazine if arsenal.is_reloading() else -1


## The minigun's barrels, from the trigger and what is in hand: a start, a loop, a wind-down, and silence the moment
## the gun is switched away, dropped, empty or the carrier is reset (a wind-down only follows a release).
func _spin_sound() -> void:
	if _fx == null:
		return
	var carried := arsenal.current()
	var held := carried != null and carried.def.id == AwWeaponIds.MINIGUN
	if (not held or arsenal.is_switching()) and _spin.active():
		_stop_spin()
		return
	var want := held and _trigger_down and not arsenal.is_switching() and not arsenal.is_reloading() \
		and arsenal.ammo().count(arsenal.ammo_of(carried.def.id)) > 0
	var part := _spin.step(want, 1.0 / float(AwWeaponPack.TICK_RATE))
	if part != AwMinigunSpin.NONE:
		_fx.play_spin(part, _listen_at())


func _stop_spin() -> void:
	_spin.stop()
	if _fx != null:
		_fx.stop_spin()


func _listen_at() -> Vector3:
	return (_player as Node3D).global_position if _player is Node3D else Vector3.ZERO


func _on_reload_finished(slot: int, _rounds: int) -> void:
	_reload_started = -1
	var finished := arsenal.slot_at(slot)
	if _cued_reload:
		_cued_reload = false
		return
	_reload_sound(AwWeaponSound.RELOAD_IN, finished.def.id if finished != null else &"")


## Plays one half of a reload's sound, under the same rule as a shot's report: never on a
## server and never on a replayed tick — a correction that replayed across a reload would
## otherwise click the magazine out twice.
func _reload_sound(stage: StringName, weapon_id: StringName = &"") -> void:
	if _replaying or role == Role.SERVER:
		return

	reload_sound.emit(stage)

	if _fx != null:
		var at: Vector3 = (_player as Node3D).global_position if _player is Node3D else Vector3.ZERO
		_fx.play_reload(stage, at, weapon_id)


## Whether an empty hand shows bare hands: [member empty_hand_view] and weapons still carried (a thrown boomerang out).
## A carrier with nothing at all (dead, stripped) still shows nothing.
func _empty_hand_shown() -> bool:
	return empty_hand_view and arsenal != null and not arsenal.slots().is_empty()


## Bare hands with nothing in them, for a hand left empty while a thrown weapon is out.
func _empty_hand_art() -> AwWeaponVisual:
	var art := AwWeaponVisual.new()
	art.id = AwWeaponIds.FISTS
	art.pose = &"fists"
	art.aim_enabled = false
	return art


## The holster half finished and the deploy half began.
## The arsenal emits this mid-switch, not at its end; treating it as the end leaves the weapon at the screen bottom.
func _on_switched(_from: int, to: int) -> void:
	var carried := arsenal.slot_at(to)
	if _fx != null:
		_fx.stop_flashes()

	_switch_started = _last_tick
	_switch_deploying = true
	_switch_ticks = maxi(1, arsenal.ticks_for(carried.def, carried.def.deploy_ticks) if carried != null else 1)

	# A thrown weapon coming back to an empty hand is caught, not drawn: the catch keys, and no deploy dip.
	var caught := _bare_after_throw and carried != null and carried.def != null \
			and AwWeaponIds.TAG_THROWN in carried.def.tags
	_bare_after_throw = to == 0 and _empty_hand_shown()
	if caught:
		_switch_ticks = 1
		_switch_started = _last_tick - 1
		if _view != null and not _replaying and role != Role.SERVER:
			_view.on_catch()
