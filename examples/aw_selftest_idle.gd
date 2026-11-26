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
func _batch_parity(cat: GSWeaponCatalogue, slot: int) -> void:
	if not ClassDB.class_exists(&"GSSimWeaponIdleBatch") or preload("res://addons/gs_weapon/gs_weapon_api.gd").LEVEL < 57:
		_check("skip: GSSimWeaponIdleBatch or gs-weapon API 57 missing", true)
		return
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
	cmd.slot = slot
	var joined := 0
	for tick in range(10, 90):
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
			and rigs[0].arsenal.snapshot() == rigs[1].arsenal.snapshot()
	_check("idle_batch plus one native batch run matches simulate_idle_row on a server rig (%d of 80 ticks joined)" % joined, same and joined > 40)
	for r in rigs:
		r.queue_free()
