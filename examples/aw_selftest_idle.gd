extends "aw_selftest_grenades.gd"

## Idle-path parity helpers of the self-test (simulate_idle and the native idle batch); split out of aw_selftest_fx.gd for file size.


## simulate_idle after would_idle leaves the rig and the weapon's state where simulate_tick(cmd, tick, null) does.
func _idle_parity(r2: AwWeaponRig, cat: GSWeaponCatalogue, cmd: GSWeaponCommand) -> void:
	var r3 := AwWeaponRig.new()
	r3.catalogue = cat
	add_child(r3)
	var same := r3.setup().ok and r2.arsenal.current() != null
	if same:
		r3.give_everything()
		r3.arsenal.equip(r2.arsenal.current_slot())
		for tick in range(10, 20):
			var a := r2.simulate_tick(cmd, tick, null)
			var b := r3.simulate_idle(cmd, tick) if r3.would_idle(cmd) else null
			same = same and b != null and a.used == b.used and a.kind == b.kind and a.refusal == b.refusal \
				and r2.arsenal.current().behaviour.state == r3.arsenal.current().behaviour.state
	_check("simulate_idle after would_idle matches simulate_tick with no context", same)
	r3.queue_free()


## On a server rig with an idle posture, idle_batch plus one native GSSimWeaponIdleBatch run leaves the rig, the outcome and
## the weapon's state where simulate_idle_row does, over moving and settled postures (skipped without that gs-sim class).
## Run with [member AwWeaponRig.idle_batch_lean] on and off: the straight bookkeeping writes and the helpers it stands for agree.
func _batch_parity(cat: GSWeaponCatalogue, slot: int) -> void:
	if not ClassDB.class_exists(&"GSSimWeaponIdleBatch") or preload("res://addons/gs_weapon/gs_weapon_api.gd").LEVEL < 58:
		_check("skip: GSSimWeaponIdleBatch or gs-weapon API 58 missing", true)
		_check("skip: GSSimWeaponIdleBatch or gs-weapon API 58 missing", true)
		return
	var was := AwWeaponRig.idle_batch_lean
	for lean in [true, false]:
		AwWeaponRig.idle_batch_lean = lean
		_batch_parity_run(cat, slot, lean)
	AwWeaponRig.idle_batch_lean = was


## The rig's idle bookkeeping fields, for [method _batch_parity_run].
func _rig_fields(r: AwWeaponRig) -> Array:
	var prev: GSWeaponCommand = r.get(&"_previous_command")
	var out := [r.get(&"_last_tick"), prev.slot if prev != null else -9, prev.buttons if prev != null else -9]
	for f in [&"_was_switching", &"_switch_started", &"_ads_move", &"_ads_progress", &"_aim_ticks", &"_charge_started", &"_trigger_down"]:
		out.append(r.get(f))
	return out


func _batch_parity_run(cat: GSWeaponCatalogue, slot: int, lean: bool) -> void:
	var batch: Object = ClassDB.instantiate(&"GSSimWeaponIdleBatch")
	var ctx := GSWeaponContext.new()
	var still := [false]
	var rigs: Array[AwWeaponRig] = []
	var same := true
	for i in 2:
		var r := AwWeaponRig.new()
		r.catalogue = cat
		r.role = AwWeaponRig.Role.SERVER
		add_child(r)
		same = same and r.setup().ok
		r.give_everything()
		r.arsenal.equip(slot)
		r.arsenal.idle_posture = func() -> GSWeaponContext: return ctx
		r.arsenal.idle_still = func() -> bool: return still[0]
		rigs.append(r)
	var cmd := GSWeaponCommand.new()
	var joined := 0
	for tick in range(10, 90):
		# Slot 0 (keep what is in hand) on some ticks, so the previous command is copied on the change.
		cmd.slot = 0 if tick % 13 < 4 else slot
		ctx.tick = tick
		ctx.speed = 0.0 if tick % 20 < 10 else 4.0 + tick % 3
		ctx.crouched = tick % 7 == 0
		still[0] = ctx.speed == 0.0
		var row := PackedFloat64Array([ctx.speed, 0.0, 1.0 if ctx.crouched else 0.0, 0.0, 0.0, 0.0, 0.0, tick, ctx.hurt_tick])
		var a := rigs[0].simulate_idle_row(cmd, tick, row, still[0])
		var entries: Array = []
		var b := rigs[1].idle_batch(cmd, tick, entries, 0)
		if b == null:
			b = rigs[1].simulate_idle_row(cmd, tick, row, still[0])
		else:
			joined += 1
			var rows := row.duplicate()
			rows.append(1.0 if still[0] else 0.0)
			var declined: PackedInt32Array = batch.call(&"run", entries, rows, 10)
			if not declined.is_empty():
				rigs[1].idle_batch_declined()
		same = same and a.used == b.used and a.kind == b.kind and a.refusal == b.refusal \
			and rigs[0].arsenal.current().behaviour.state == rigs[1].arsenal.current().behaviour.state \
			and rigs[0].arsenal.snapshot() == rigs[1].arsenal.snapshot() and _rig_fields(rigs[0]) == _rig_fields(rigs[1])
	_check("idle_batch (lean %s) plus one native batch run matches simulate_idle_row on a server rig, rig fields too (%d of 80 ticks joined)" % [lean, joined], same and joined > 40)
	for r in rigs:
		r.queue_free()


## On a server rig, would_cool then simulate_cooling_row (or cooling_batch plus one native GSSimWeaponIdleBatch run) leaves
## the outcome, the weapon's state, the arsenal's snapshot and the rig's fields where simulate_tick with the same posture
## does, over every carried weapon, a trigger held and let go, aimed now and then (skipped before gs-weapon API 59).
func _cool_parity(cat: GSWeaponCatalogue) -> void:
	if preload("res://addons/gs_weapon/gs_weapon_api.gd").LEVEL < 59:
		_check("skip: gs-weapon API 59 missing", true)
		_check("skip: gs-weapon API 59 missing", true)
		return
	_cool_parity_run(cat, false)
	if ClassDB.class_exists(&"GSSimWeaponIdleBatch"):
		_cool_parity_run(cat, true)
	else:
		_check("skip: GSSimWeaponIdleBatch missing", true)


func _cool_posture(tick: int) -> GSWeaponContext:
	var ctx := GSWeaponContext.new()
	ctx.tick = tick
	ctx.speed = 0.0 if tick % 23 < 9 else 3.0 + tick % 4
	ctx.crouched = tick % 11 == 0
	ctx.airborne = tick % 37 == 5
	return ctx


func _cool_parity_run(cat: GSWeaponCatalogue, batched: bool) -> void:
	var batch: Object = ClassDB.instantiate(&"GSSimWeaponIdleBatch") if batched else null
	var rigs: Array[AwWeaponRig] = []
	var same := true
	for i in 2:
		var r := AwWeaponRig.new()
		r.catalogue = cat
		r.role = AwWeaponRig.Role.SERVER
		add_child(r)
		same = same and r.setup().ok
		r.give_everything()
		r.arsenal.idle_posture = func() -> GSWeaponContext: return _cool_posture(_cool_now[0])
		r.arsenal.idle_still = func() -> bool: return _cool_posture(_cool_now[0]).speed == 0.0
		rigs.append(r)
	var cooled := 0
	var detail := ""
	var tick := 10
	for slot in rigs[0].arsenal._slots.keys():
		for r in rigs:
			r.arsenal.equip(slot)
		for n in 160:
			tick += 1
			_cool_now[0] = tick
			var cmd := GSWeaponCommand.new()
			var phase := tick % 40
			cmd.buttons = GSWeaponCommand.BUTTON_ATTACK if phase < 30 else 0
			if phase >= 24 and phase < 27:
				cmd.buttons |= GSWeaponCommand.BUTTON_AIM
			var a := rigs[0].simulate_tick(cmd, tick, _cool_posture(tick))
			var post := _cool_posture(tick)
			var b: GSWeaponOutcome = null
			if rigs[1].would_cool(cmd, tick, post.sprinting, post.sprint_blocks_fire):
				cooled += 1
				var row := PackedFloat64Array([post.speed, 1.0 if post.airborne else 0.0, 1.0 if post.crouched else 0.0, 0.0, 0.0, 0.0, 0.0, tick, post.hurt_tick])
				if batched:
					var entries: Array = []
					b = rigs[1].cooling_batch(cmd, tick, entries, 0)
					if b != null:
						row.append(1.0 if post.speed == 0.0 else 0.0)
						var declined: PackedInt32Array = batch.call(&"run", entries, row, 10)
						if not declined.is_empty():
							rigs[1].idle_batch_declined()
				if b == null:
					b = rigs[1].simulate_cooling_row(cmd, tick, row.slice(0, 9))
			else:
				b = rigs[1].simulate_tick(cmd, tick, _cool_posture(tick))
			var ok := a.used == b.used and a.kind == b.kind and a.refusal == b.refusal \
				and rigs[0].arsenal.current().behaviour.state == rigs[1].arsenal.current().behaviour.state \
				and rigs[0].arsenal.snapshot() == rigs[1].arsenal.snapshot() and _rig_fields(rigs[0]) == _rig_fields(rigs[1])
			if not ok and same:
				detail = "slot %d tick %d buttons %d" % [slot, tick, cmd.buttons]
			same = same and ok
	_check("would_cool then %s matches simulate_tick on a server rig, rig fields too (%d cooled ticks)" \
		% ["cooling_batch and one native batch run" if batched else "simulate_cooling_row", cooled] + ("; first differs at " + detail if detail != "" else ""), same and cooled > 100)
	for r in rigs:
		r.queue_free()


## The tick [method _cool_parity_run]'s idle posture answers for.
var _cool_now := [0]

