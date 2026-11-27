@tool
class_name AwWorldModel
extends "aw_world_model_ticking.gd"

## The weapon everybody [i]else[/i] sees, hanging off a character's hand. Not a second copy of [AwViewModel]: a view model is drawn on top of the world at an exaggerated scale for one viewer,
## a world model is depth-tested, casts a shadow, is the right size, and thirty can be on screen. It attaches by duck typing (`attach_to` takes any node answering `attachment(point)`; no character class
## is named, as a missing `class_name` breaks every script that mentions it). Recoil is a fraction of the first-person kick, enough to tell a watcher the gun went off.

# No CHANNEL: a drawer. Its one failure, a model that will not load, is reported once by
# AwModelCache and handed back as a GSResult; "nowhere to attach" is headless, not wrong.

## How much of a weapon's recoil a watcher sees.
const RECOIL_SHARE := 0.35

@export_group("Attachment")

## The attachment point on the character to hang from: any node answering `attachment(point)`.
## The name is the character rig's to define; `right_hand` is what gs-player-char ships.
@export var mount: StringName = &"right_hand"

@export_group("Behaviour")

## Hides the model while the character is switching weapons: the third-person counterpart of the view model's deploy,
## a visibility toggle, as nobody watching can tell a holster from a deploy at range.
@export var hide_while_switching: bool = true

## Whether a shot is drawn and heard from this hand. See [method on_fired].
@export var effects: bool = true

## Whether the report is heard, when [member effects] draws the shot. Off for a game that already plays a sound for somebody else's shot
## (two reports for one shot otherwise; turning [member effects] off would lose the flash and tracer). Set with `set(&"sounds", ...)` from a delivered game,
## because a shell built before this property existed fails to parse a pack that names it.
@export var sounds: bool = true

## Pulls the weapon back and holds it low when a wall is within the gun's length, so a watcher does not see it through the wall. Off switch for a game with its own.
@export var wall_response: bool = true
## Physics layers the wall probe stops on; the carrier's own body is skipped, and so are other characters.
@export_flags_3d_physics var wall_mask: int = 0xFFFFFFFF
## Furthest the gun is pulled back, in metres.
@export_range(0.0, 1.0, 0.01) var wall_max_pull: float = 0.3
## Degrees the muzzle drops per metre of pull-back.
@export_range(0.0, 400.0, 1.0) var wall_tilt_per_m: float = 150.0
## Smoothing rate of the response, per second.
@export_range(0.5, 40.0, 0.5) var wall_rate: float = 12.0

## Microseconds one frame may spend building watchers' weapon models; 0 (the default) builds every one at once. A respawn on a map change equips every player in one tick
## (about 4 ms each): past the budget [method equip] records the weapon ([method equipped] answers at once) and builds its model on a later frame. The first build of a frame
## always goes ahead, so a single switch never waits. Presentation only: nothing a shot, a hit or the simulation reads comes from this node.
static var equip_budget_usec := 0
static var _budget_frame := -1
static var _budget_spent := 0

const WALL_ARM := 0.45
const WALL_MARGIN := 0.04
const WALL_PROBE_EVERY := 0.05

var _wall_amount: float = 0.0
var _wall_target: float = 0.0
var _wall_clock: float = 0.0
var _wall_was: bool = false
var _attachments: Array[Node3D] = []

## True while [member _art]'s model waits for a frame with [member equip_budget_usec] to spare.
var _deferred: bool = false
const ChargeFx := preload("aw_charge_fx.gd")
const CarryClass := preload("aw_carry_class.gd")
var _charge_fx: Node3D = null
var _last_charge := 0.0

var _fx: AwShotFx = null

## Recoil offset in metres and its decay, so a watcher sees the gun move when it fires.
var _kick: float = 0.0

## The swing or throw playing: its keys, its length, and how far through it is (1 is none).
var _action_keys: Array = []
var _action_seconds: float = SWING_SECONDS
var _action: float = 1.0
var _action_hides: bool = false

var _built: bool = false

## The person this hangs from (duck-typed, see [method _person]), the sprint carry blended in (read from
## it), and the support hand's place in the holder's space, [constant Vector3.INF] for one hand.
var _owner_cache: Object = null
## What the person answers, looked up once per person rather than every frame: [member _owner_ok] goes false on
## entering or leaving the tree (the only way the ancestors change), and the carry's checks are kept for the
## object last read. [member person_cache] off resolves all of it every frame (the old path, for parity checks).
static var person_cache := true
var _owner_ok := false
var _person_grips := false
var _carry_seen: Object = null
var _carry_seen_ok := false
## The reload and switch flags last written to [member _carry]; -1 unknown.
var _told_reloading := -1
var _told_switching := -1
## [method _sprint_carry]'s offset and turn for this frame.
var _sprint_offset := Vector3.ZERO
var _sprint_turn := Basis.IDENTITY
var _sprint: float = 0.0
## Whether [method advance] hands the holder's pose arithmetic (the action keys, the Euler turns, the reload dip, the sprint carry,
## the wall tilt and the compose) to GameSpice Sim's `GSSimWorldHold` when the library is loaded. Bit for bit the script's answer;
## off (or without the library) the script does it. Reached through [ClassDB] by name only.
static var native_hold := true
## This model's `GSSimWorldHold`, made on first use; [member _hold_tried] stops a second lookup without the library.
var _hold_native: Object = null
var _hold_tried := false
## The action keys changed since the kernel was last given them.
var _hold_keys_dirty := true
var _support_sent: bool = false
var _sprint_was_on: bool = false
## Whether `GSSimWorldHoldBatch` exists, looked up once: with it and [member native_hold], every gun joins the
## ticker ([code]aw_world_ticks.gd[/code]), which poses all holders in one native call a frame.
static var _batch_known := -1
## This frame's row for the ticker's batch (see [code]GSSimWorldHoldBatch.step[/code] for the layout) and its flags.
const ROW_SIZE := 16
const ROW_ACTING := 1
const ROW_LOOKING := 2
const ROW_POSE := 4
const ROW_SUPPORT := 8
var _hold_row := PackedFloat64Array()
var _row_flags := 0
## The batch holding this gun's slot (-1 none), and what the slot was last given: the person, the
## art (rest, sprint carry) and support point, the action keys.
var _batch: Object = null
var _batch_slot := -1
var _batch_person: Object = null
var _batch_art: Object = null
var _batch_support := Vector3.INF
var _batch_art_set := false
var _batch_keys_dirty := true

## The person's gun-arm carry (gs-player-char API 22's `GSHumanoidFigure.carry`, duck-typed), the weapon id its class was last set for, and whether the character is mid-switch.
## While there is one it draws the kick, the reload roll and the sprint. Whether a held gun hands them to it (off: the model's own kick and reload dip, the clip's arms):
## on by default; a bench turns it off to price the carry.
static var person_carry := true
var _carry: Object = null
var _carry_for: StringName = &"-"
var _switching: bool = false

## Bumped whenever a rig enters or leaves the tree or builds its shot effects, so each model's
## [method _carrier_draws_its_own] answer goes stale at once. -1 in [member _draws_own_epoch]: not asked yet.
static var rig_epoch := 0
var _draws_own_epoch := -1
var _draws_own := false

## The reload a watcher sees: whether one is on, its blend in and out, time into it and one cycle's length.
var _reloading: bool = false
var _reload_blend: float = 0.0
var _reload_time: float = 0.0
var _reload_period: float = 1.5


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE or what == NOTIFICATION_EXIT_TREE:
		_draws_own_epoch = -1
		_owner_ok = false
		_wall_carrier_known = false
		_wall_from = Vector3.INF
	elif what == NOTIFICATION_PREDELETE and _batch_slot >= 0 and _batch != null:
		_batch.call(&"close", _batch_slot)
		_batch_slot = -1


func _wants_central() -> bool:
	if central_tick:
		return true
	if not native_hold:
		return false
	if _batch_known < 0:
		_batch_known = int(ClassDB.class_exists(&"GSSimWorldHoldBatch"))
	return _batch_known == 1


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	_build()


func _build() -> void:
	if _built:
		return

	_holder = Node3D.new()
	_holder.name = "Holder"
	add_child(_holder)
	_built = true


# --- Attaching --------------------------------------------------------------

## Hangs this model off [param character]'s [member mount] point. Returning false is not an error: a dedicated server has no character model and a 2D game
## has no hand, and a rig that treats "nowhere to attach" as a failure cannot run headless, which this family insists on being able to do.
func attach_to(character: Object) -> bool:
	if character == null or not character.has_method("attachment"):
		return false

	var point: Variant = character.call("attachment", mount)

	if not (point is Node):
		return false

	if get_parent() != null:
		get_parent().remove_child(self)

	(point as Node).add_child(self)
	transform = Transform3D.IDENTITY
	return true


# --- Weapons ----------------------------------------------------------------

## Draws [param art]'s weapon at the hand, replacing whatever was there.
func equip(art: AwWeaponVisual) -> GSResult:
	_build()
	_clear_models()
	_deferred = false
	_late_wait = false

	if _art != null and _art.changed.is_connected(_on_art_changed):
		_art.changed.disconnect(_on_art_changed)
	_art = art
	if art != null:
		art.changed.connect(_on_art_changed)

	if art == null:
		_id = &""
		return GSResult.fail(GSError.CODE_INVALID, "No art to equip.")

	_id = art.id
	_holder.transform = _rest()
	_support_local = Vector3.INF
	_eject_local = Vector3.INF
	_wall_from = Vector3.INF
	_two_known = false

	if not art.has_model():
		return GSResult.success(null)

	if not _budget_left():
		_deferred = true
		return GSResult.success(null)

	var built := _build_model(art)
	_late_wait = not built.ok and AwModelCache.late_pending()
	return built


## Whether this frame still has [member equip_budget_usec] to spend on a model; always true for the first, or with no budget.
static func _budget_left() -> bool:
	if equip_budget_usec <= 0:
		return true
	var frame := Engine.get_process_frames()
	if frame != _budget_frame:
		_budget_frame = frame
		_budget_spent = 0
		return true
	return _budget_spent < equip_budget_usec


## Puts [param art]'s model in the hand, charging the time to this frame's budget.
func _build_model(art: AwWeaponVisual) -> GSResult:
	var started := Time.get_ticks_usec()
	_weapon = AwModelCache.instantiate(art.model_path)

	if _weapon == null:
		_budget_spent += Time.get_ticks_usec() - started
		return GSResult.fail(GSError.CODE_IO, "No model loads for this weapon.", art.model_path)

	_weapon.name = "Weapon"
	_holder.add_child(_weapon)

	# Attachments come across, magazines do not: a watcher cannot see a magazine fall
	# out at range, and thirty players each carrying one extra mesh they cannot see is
	# thirty meshes being culled every frame for nothing.
	_attachments.append_array(Dress.art_parts(art, _holder))

	_apply_shadows()
	_support_local = _support_point_for(art)
	_two_known = false
	_budget_spent += Time.get_ticks_usec() - started
	return GSResult.success(null)


## Builds a model [method equip] left for a later frame, and dresses it with the fitting set meanwhile.
func _build_deferred() -> void:
	if not _budget_left():
		return
	_deferred = false
	if _art == null or not _built:
		return
	var fitting := _fitting
	var _res := _build_model(_art)
	if fitting != null:
		set_fitting(fitting)


func clear() -> void:
	_send_support(false)
	_clear_models()
	_deferred = false
	if _art != null and _art.changed.is_connected(_on_art_changed):
		_art.changed.disconnect(_on_art_changed)
	_art = null
	_two_known = false
	_id = &""


func equipped() -> StringName:
	return _id


## Where this weapon's muzzle is in the world, for an effect a watcher can see.
func muzzle_transform() -> Transform3D:
	if _weapon == null or _art == null:
		return global_transform

	var distance := _art.muzzle_distance

	if distance <= 0.0:
		distance = AwModelCache.muzzle_distance(_art.model_path, _art.model_forward)

	distance = maxf(distance, float(_dressed.get("reach", 0.0)))

	return _weapon.global_transform * Transform3D(
		Basis.IDENTITY,
		_art.model_forward.normalized() * distance + _art.muzzle_offset
	)


# --- Being told what happened -----------------------------------------------

## A charged weapon's draw, 0 to 1, from the snapshot. Builds the ball on the first charge.
func on_charge(fraction: float) -> void:
	if fraction > 0.0 and _charge_fx == null and is_inside_tree() and effects:
		_charge_fx = AwFxPool.take_charge_fx()
		if _charge_fx == null:
			_charge_fx = ChargeFx.new()
		_charge_fx.name = "ChargeFx"
		_charge_fx.follow = muzzle_transform
		_charge_fx.with_light = false
		add_child(_charge_fx)
	if _charge_fx != null:
		_charge_fx.set_charge(fraction)
	_last_charge = fraction


## The charge ball, or null. For a suite.
func charge_fx() -> Node3D:
	return _charge_fx


## The weapon fired. [param recoil] is the pitch and yaw a behaviour asked for, and [param kind] a [AwWeaponNet] kind number. [param with_effects] draws the shot
## from this hand (flash, tracer, report): what a watcher sees of somebody else firing. It stands down when the carrier's own first-person rig is on this machine,
## because that rig already drew the shot from the view model's muzzle and a second report centimetres away is the same gun going off twice.
func on_fired(
	recoil: Vector2 = Vector2(0.5, 0.1),
	kind: int = AwWeaponNet.KIND_SHOT,
	with_effects: bool = true
) -> void:
	if not is_finite(recoil.x):
		return
	match kind:
		AwWeaponNet.KIND_SWING:
			swing()
		AwWeaponNet.KIND_THROW:
			throw()
		_:
			var carry := _person_carry()
			if carry != null:
				carry.call(&"fired")
			else:
				_kick = minf(_kick + recoil.x * 0.008 * RECOIL_SHARE, 0.08)

	if with_effects and effects and is_inside_tree() and not _carrier_draws_its_own():
		if _charge_fx != null:
			_charge_fx.note_fired()
		_shot_fx().play_remote(kind, muzzle_transform(), muzzle_direction(), _id, _last_charge)
		if kind == AwWeaponNet.KIND_SHOT and _art != null and _art.ejects and _weapon != null:
			var drawn := _weapon.global_transform.basis.get_scale()
			_shot_fx().play_eject(eject_transform(), _id, _art.eject_speed,
					(absf(drawn.x) + absf(drawn.y) + absf(drawn.z)) / 3.0)


## Plays [constant SWING_KEYS] from the top: what [method on_fired] does with a swing. A swing
## during a swing starts again, which is what a second strike looks like.
func swing() -> void:
	_start_action(SWING_KEYS, SWING_SECONDS, false)


## Plays [constant THROW_KEYS]: what [method on_fired] does with a throw. Also starts the slash
## overlay on the person this hangs from, if it hangs from one.
func throw() -> void:
	_start_action(THROW_KEYS, THROW_SECONDS, true)
	var person := _person()
	if person != null:
		person.call(&"swing", &"slash")


## The person this hand belongs to: the nearest node above it that answers both `swing(which)` and `set_hold(kind)`, which gs-player-char's figure does.
## Asked for a throw only, and duck-typed for [method attach_to]'s reason: every game already plays the slash on a swing itself, and the figure has no throw clip,
## so empty-handed arms are what a thrown weapon is held with.
func _person() -> Object:
	if _owner_ok and person_cache and is_instance_valid(_owner_cache):
		return _owner_cache
	if _owner_cache != null and is_instance_valid(_owner_cache) and _owner_cache is Node and (_owner_cache as Node).is_ancestor_of(self):
		_owner_ok = true
		return _owner_cache
	_owner_cache = null
	_owner_ok = false
	var node := get_parent()
	var depth := 0
	while node != null and depth < 10:
		if node.has_method(&"swing") and node.has_method(&"set_hold"):
			_owner_cache = node
			_owner_ok = true
			_person_grips = node.has_method(&"set_support_grip")  # perf-lint: allow dynamic_call once per owner, cached
			return node
		node = node.get_parent()
		depth += 1
	return null


## How far through the swing or throw playing, 0 to 1; 1 when none is.
func action_fraction() -> float:
	return _action


func _start_action(keys: Array, seconds: float, hides: bool) -> void:
	_action_keys = keys
	_hold_keys_dirty = true
	_batch_keys_dirty = true
	_action_seconds = seconds
	_action_hides = hides
	_action = 0.0
	# The kick a swing used to be is not added to the cut: a knife pushed back along its own
	# blade as it strikes reads as the hand flinching.
	_kick = 0.0


## Whether the character is mid-switch. Hides the model while they are, if asked to.
func on_switching(switching: bool) -> void:
	_switching = switching
	_tell_carry()
	if hide_while_switching:
		visible = not switching


## Whether the character is aiming down the sights: the person's carry shoulders the gun while it is on.
func on_aiming(aiming: bool) -> void:
	var carry := _person_carry()
	if carry != null:
		carry.set(&"raised", aiming)


## Whether the character is reloading (the replicated flag): plays the watcher's reload while it is on.
func on_reloading(reloading: bool) -> void:
	if reloading and not _reloading:
		_reload_time = 0.0
		_reload_period = _cycle_seconds()
		_detach_magazine()
	_reloading = reloading
	_tell_carry()


## How far into the watcher's reload, 0 to 1 per cycle; -1 when none is showing.
func reload_fraction() -> float:
	return fposmod(_reload_time / _reload_period, 1.0) if _reload_blend > 0.0 else -1.0


## One cycle of the support hand: the weapon's whole reload, or one round of a reload by the round.
func _cycle_seconds() -> float:
	var def: GSWeaponDef = AwWeaponCatalogue.shared().get_def(_id) if _id != &"" else null
	if def == null or def.reload_ticks <= 0:
		return 1.5
	var rate := float(def.authored_tick_rate) if def.authored_tick_rate > 0 else float(AwWeaponCatalogue.TICK_RATE)
	return clampf(float(def.reload_ticks) / rate, 0.4, 6.0)


## The model was missing at equip while a late addon group was on its way: built again once the group is mounted.
var _late_wait := false


## One frame of the gun however it is ticked.
func _tick(delta: float) -> void:
	if _late_wait and not AwModelCache.late_pending():
		# The group is mounted now.
		_late_wait = false
		_deferred = _art != null
	if _deferred:
		_build_deferred()
	# Hidden (the local player's own, a switch), one frame lets go of the support hand, then the
	# time is banked and spent in one step when it shows: every step clamps or converges, and a
	# hidden gun was still probing walls and asking the body for its sprint every frame.
	if not visible:
		if _hidden_for >= 0.0:
			_hidden_for += delta
			return
		_hidden_for = 0.0
		advance(delta)
		return
	if _hidden_for > 0.0:
		delta += _hidden_for
	_hidden_for = -1.0
	advance(delta)


## Seconds banked while hidden; below zero while shown.
var _hidden_for := -1.0


## One frame of the hand, [param delta] seconds long. [method _tick] calls it; a tool that
## freezes processing (`tools/world_sheet.gd`) calls it with a fixed step, so a frame is the
## same picture on every machine.
func advance(delta: float) -> void:
	if Engine.is_editor_hint() or not _built or _holder == null:
		return
	if not is_finite(delta) or delta < 0.0:
		return

	# Run by the ticker with its native batch: the support hand and the pose go into a row (see _post_row).
	var via: Node = _batch_via if native_hold else null
	_row_flags = 0
	_reload_blend = move_toward(_reload_blend, 1.0 if _reloading else 0.0, delta / 0.2)
	_reload_time += delta
	_follow_person(via != null)
	_advance_wall(delta)
	if _wall_amount <= 0.0 and _wall_was and _kick <= 0.00001:
		_wall_was = false
	elif _wall_amount > 0.0:
		_wall_was = true
	var told := _inspect_told
	_inspect_told = false
	var looked := _inspect_turn(delta, told)
	var looking := _inspect_shown > 0.0
	if not _wall_was and _kick <= 0.00001 and _action >= 1.0 and _sprint <= 0.0 and not _sprint_was_on and _reload_blend <= 0.0 \
			and not _reloading and not looking and not _inspect_was_on:
		if _row_flags != 0:
			_post_row(via, looked, false)
		return
	_inspect_was_on = looking
	_sprint_was_on = _sprint > 0.0

	# Decayed rather than sprung. A watcher cannot see an overshoot at twenty metres, so
	# the spring the view model runs would be arithmetic nobody ever sees the result of.
	_kick = move_toward(_kick, 0.0, _kick * 12.0 * delta + 0.0002)

	var acting := _action < 1.0
	if acting:
		_action = minf(1.0, _action + delta / maxf(_action_seconds, 0.01))
	if via != null:
		_show_in_hand(not (_action_hides and _action >= THROW_RELEASE and _action < THROW_BACK))
		_row_flags |= ROW_POSE | (ROW_ACTING if acting else 0) | (ROW_LOOKING if looking else 0)
		_post_row(via, looked, true)
		return
	if native_hold and _hold_kernel() != null:
		_show_in_hand(not (_action_hides and _action >= THROW_RELEASE and _action < THROW_BACK))
		_holder.transform = _hold_natively(acting, looking, looked)
		_finish_frame()
		return

	var turn := Basis.IDENTITY
	var moved := Vector3.ZERO
	if acting:
		var at := AwWeaponPose.sample_keys(_action_keys, _action)
		moved = at[0]
		var degrees: Vector3 = at[1]
		turn = Basis.from_euler(Vector3(
			deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z)
		))
	elif looking:
		moved = looked[0]
		var looked_degrees: Vector3 = looked[1]
		turn = Basis.from_euler(Vector3(
			deg_to_rad(looked_degrees.x), deg_to_rad(looked_degrees.y), deg_to_rad(looked_degrees.z)
		))
	_show_in_hand(not (_action_hides and _action >= THROW_RELEASE and _action < THROW_BACK))
	if _reload_blend > 0.0 and _carry == null:
		var share := smoothstep(0.0, 1.0, _reload_blend)
		moved += RELOAD_DIP * share
		turn = turn * Basis.from_euler(RELOAD_TURN * share * (PI / 180.0))

	# About the grip, which is where the hand is: the rest transform's origin.
	var rest := _rest()
	_sprint_carry()
	var low := Basis.from_euler(Vector3(-deg_to_rad(_wall_amount * wall_tilt_per_m), 0.0, 0.0))
	_holder.transform = Transform3D(
		low * _sprint_turn * turn * rest.basis, rest.origin + moved + _sprint_offset + Vector3(0.0, 0.0, _kick + _wall_amount)
	)
	_finish_frame()


## The kernel when [member native_hold] may use it: made once through [ClassDB], null without the library.
func _hold_kernel() -> Object:
	if _hold_native == null and not _hold_tried:
		_hold_tried = true
		if ClassDB.class_exists(&"GSSimWorldHold"):
			_hold_native = ClassDB.instantiate(&"GSSimWorldHold")
	return _hold_native


## The holder's transform from the kernel, given what the script settled this frame; the same inputs the script path reads.
func _hold_natively(acting: bool, looking: bool, looked: Array) -> Transform3D:
	if _hold_keys_dirty:
		_hold_keys_dirty = false
		_hold_native.call(&"set_keys", _key_rows(_action_keys))
	var sprint := _sprint if _art != null else 0.0
	var sprint_offset := Vector3.ZERO
	var sprint_degrees := Vector3.ZERO
	if sprint > 0.0:
		var carry := _sprint_world()
		sprint_offset = carry[0]
		sprint_degrees = carry[1]
	return _hold_native.call(&"hold", acting, _action, looking, looked[0], looked[1],
		_reload_blend if _carry == null else 0.0, _rest(), sprint, sprint_offset, sprint_degrees,
		_wall_amount * wall_tilt_per_m, _kick + _wall_amount)


## The art's sprint carry at full blend: its own offset and degrees, or its pose's. Needs [member _art].
func _sprint_world() -> Array:
	var own_offset := _art.sprint_world_offset.is_finite()
	var own_turn := _art.sprint_world_rotation.is_finite()
	var base: Array = AwWeaponArtTable.sprint_world(_art.pose) if not (own_offset and own_turn) else _NO_SPRINT
	return [_art.sprint_world_offset if own_offset else base[0], _art.sprint_world_rotation if own_turn else base[1]]


## The art said it changed ([signal Resource.changed]; an edit that should show live calls its
## [method Resource.emit_changed], since plain property sets do not): the batch slot gets the rest pose and sprint
## carry again on the next row. The script and single-kernel holds read the art every frame already.
func _on_art_changed() -> void:
	_batch_art_set = false
	_two_known = false


## Posts this frame's row to the ticker [param via]: the support hand when [member _row_flags] asks for it, and the
## holder's pose when [param posed] (the same inputs [method _hold_natively] passes). The slot is told about a new
## person, art, support point or action keys first. The ticker's step runs it and calls [method _finish_frame].
func _post_row(via: Variant, looked: Array, posed: bool) -> void:
	var batch: Object = via.batch
	if _batch_slot < 0 or batch != _batch:
		_batch = batch
		_batch_slot = batch.call(&"open", _holder)
		_batch_person = null
		_batch_art_set = false
		_batch_keys_dirty = true
		_hold_row.resize(ROW_SIZE)
		if not via.support_keys_set:
			via.support_keys_set = true
			batch.call(&"set_support_keys", _key_rows(RELOAD_SUPPORT_KEYS))
	if _row_flags & ROW_SUPPORT and _owner_cache != _batch_person:
		_batch_person = _owner_cache
		batch.call(&"set_person", _batch_slot, _owner_cache)
	if not _batch_art_set or _art != _batch_art or _support_local != _batch_support:
		_batch_art_set = true
		_batch_art = _art
		_batch_support = _support_local
		var carry: Array = _sprint_world() if _art != null else [Vector3.ZERO, Vector3.ZERO]
		batch.call(&"set_art", _batch_slot, _rest(), carry[0], carry[1], _support_local)
	if posed and _batch_keys_dirty:
		_batch_keys_dirty = false
		batch.call(&"set_keys", _batch_slot, _key_rows(_action_keys))
	_hold_row[0] = _batch_slot
	_hold_row[1] = _row_flags
	if posed:
		var moved: Vector3 = looked[0]
		var degrees: Vector3 = looked[1]
		_hold_row[2] = _action
		_hold_row[3] = moved.x
		_hold_row[4] = moved.y
		_hold_row[5] = moved.z
		_hold_row[6] = degrees.x
		_hold_row[7] = degrees.y
		_hold_row[8] = degrees.z
		_hold_row[9] = _reload_blend if _carry == null else 0.0
		_hold_row[10] = _sprint if _art != null else 0.0
		_hold_row[11] = _wall_amount * wall_tilt_per_m
		_hold_row[12] = _kick + _wall_amount
	_hold_row[13] = _reload_blend
	_hold_row[14] = _reload_time
	_hold_row[15] = _reload_period
	via.post(self, _hold_row, posed)


## Action keys as the kernels take them: seven floats a key (time, position, degrees).
static func _key_rows(keys: Array) -> PackedFloat64Array:
	var rows := PackedFloat64Array()
	for key: Array in keys:
		var pos: Vector3 = key[1]
		var rot: Vector3 = key[2]
		rows.append_array([float(key[0]), pos.x, pos.y, pos.z, rot.x, rot.y, rot.z])
	return rows


## The frame's end on either path: the magazine follows the hand, and goes back into the gun once the reload is over.
func _finish_frame() -> void:
	_move_magazine()
	if _mag != null and _reload_blend <= 0.0 and not _reloading:
		# Seated again and the reload over: the gun is one mesh once more.
		MagCarve.merge_back(_mag)
		_mag = null


## Follows the support hand while it has the magazine: out of the well at a quarter of the cycle, down to the belt and back up with the fresh one, seated at three quarters.
## In the hand, not under the gun: dropped straight down from the well, the magazine hung in the air beside the hand meant to hold it.
## Its middle goes to the support hand's point as the hand leaves the well.
func _move_magazine() -> void:
	if _mag == null or not is_instance_valid(_mag):
		return
	_mag.transform = _mag_local
	var f := reload_fraction()
	if f < 0.25 or f >= 0.75 or not _reloading:
		return
	var at: Vector3 = AwWeaponPose.sample_keys(RELOAD_SUPPORT_KEYS, f)[0]
	var mesh := _mag as MeshInstance3D
	var middle := _mag.global_transform * (mesh.mesh.get_aabb().get_center() if mesh != null and mesh.mesh != null else Vector3.ZERO)
	_mag.global_position += (_support_world() - middle) * smoothstep(0.0, 0.3, clampf(at.y, 0.0, 1.0))


## Metres the gun must be pulled back for a wall [param hit] away from a ray that starts [param arm] behind the hand (INF for none).
static func wall_pull(hit: float, gun_length: float, arm: float = WALL_ARM, margin: float = WALL_MARGIN, max_pull: float = 0.3) -> float:
	if not is_finite(hit) or not is_finite(gun_length):
		return 0.0
	return clampf(arm + gun_length + margin - hit, 0.0, maxf(max_pull, 0.0))


## Probes forward from behind the hand every [constant WALL_PROBE_EVERY] and eases toward the answer.
func _advance_wall(delta: float) -> void:
	_wall_clock += delta
	if wall_response and _wall_clock >= WALL_PROBE_EVERY and _weapon != null and _weapon.visible and is_inside_tree():
		_wall_still += _wall_clock
		_wall_clock = 0.0
		_wall_target = _probe_wall()
	elif not wall_response or _weapon == null:
		_wall_target = 0.0
	_wall_amount = lerpf(_wall_amount, _wall_target, 1.0 - exp(-wall_rate * clampf(delta, 0.0, 0.25)))
	if _wall_target == 0.0 and _wall_amount < 0.002:
		_wall_amount = 0.0

## Seconds a hand that has not moved since the last probe keeps that answer, so a door closing in front of a still
## player still shows within this long.
const WALL_STILL_SECONDS := 0.5

var _wall_query: PhysicsRayQueryParameters3D
## The probe's exclusions, assigned whole: [code]query.exclude[/code] hands back a copy, so appending to it excluded nothing.
## The carrier's body first (looked up once per tree entry), then any character a hop passed this probe.
var _wall_exclude: Array[RID] = []
var _wall_carrier := RID()
var _wall_carrier_known := false
var _wall_exclude_grown := true
## The last probe's ray start and direction, its answer and the seconds since it was asked of the physics server.
var _wall_from := Vector3.INF
var _wall_forward := Vector3.ZERO
var _wall_last := 0.0
var _wall_still := 0.0


func _probe_wall() -> float:
	var world := get_world_3d()
	if world == null:
		return 0.0
	var person := _person()
	var facing: Node3D = person if person is Node3D else self
	var forward := -facing.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return 0.0
	forward = forward.normalized()
	var hand := _holder.global_position
	var from := hand - forward * WALL_ARM
	if from == _wall_from and forward == _wall_forward and _wall_still < WALL_STILL_SECONDS:
		return _wall_last
	_wall_from = from
	_wall_forward = forward
	_wall_still = 0.0
	_wall_last = _cast_wall(world.direct_space_state, from, forward, hand.distance_to(muzzle_transform().origin))
	return _wall_last


## The pull for a ray from [param from] along [param forward], past the carrier's own body and any character.
func _cast_wall(space: PhysicsDirectSpaceState3D, from: Vector3, forward: Vector3, length: float) -> float:
	if _wall_query == null:
		_wall_query = PhysicsRayQueryParameters3D.new()
		_wall_query.collide_with_areas = false
	var query := _wall_query
	query.from = from
	query.to = from + forward * (WALL_ARM + length + WALL_MARGIN)
	query.collision_mask = wall_mask
	if not _wall_carrier_known:
		_wall_carrier_known = true
		var body := _carrier_body()
		_wall_carrier = (body as CollisionObject3D).get_rid() if body is CollisionObject3D else RID()
		_wall_exclude_grown = true
	if _wall_exclude_grown:
		_wall_exclude_grown = false
		_wall_exclude.clear()
		if _wall_carrier.is_valid():
			_wall_exclude.append(_wall_carrier)
		query.exclude = _wall_exclude
	for _hop in range(6):
		var found := space.intersect_ray(query)
		if found.is_empty():
			return 0.0
		if found["collider"] is CharacterBody3D:
			_wall_exclude.append(found["rid"])
			query.exclude = _wall_exclude
			_wall_exclude_grown = true
			continue
		return wall_pull(from.distance_to(found["position"]), length, WALL_ARM, WALL_MARGIN, wall_max_pull)
	return 0.0


## The pull-back now, for a suite and a tool.
func wall_amount() -> float:
	return _wall_amount


## The art's third-person transform, scaled by its pose's share of the figure's hand scale.
func _rest() -> Transform3D:
	if _art == null:
		return Transform3D.IDENTITY
	var rest := _art.world_transform()
	return Transform3D(rest.basis.scaled(Vector3.ONE * AwWeaponArtTable.pose_world_factor(_art.pose)), rest.origin)


## The sprint carry at the current blend into [member _sprint_offset] and [member _sprint_turn], in the hand's frame, about the grip.
func _sprint_carry() -> void:
	if _art == null or _sprint <= 0.0:
		_sprint_offset = Vector3.ZERO
		_sprint_turn = Basis.IDENTITY
		return
	var own_offset := _art.sprint_world_offset.is_finite()
	var own_turn := _art.sprint_world_rotation.is_finite()
	var base: Array = AwWeaponArtTable.sprint_world(_art.pose) if not (own_offset and own_turn) else _NO_SPRINT
	var offset: Vector3 = _art.sprint_world_offset if own_offset else base[0]
	var degrees: Vector3 = _art.sprint_world_rotation if own_turn else base[1]
	degrees *= _sprint
	_sprint_offset = offset * _sprint
	_sprint_turn = Basis.from_euler(Vector3(deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z)))


const _NO_SPRINT: Array = []


## Whether the art held now takes a support hand ([member _two_art]); asked again after an equip, a model or an art edit.
var _two_known := false
var _two_art := false


## Reads the person's sprint blend and tells it where the support hand goes: every frame, because the holder moves.
func _follow_person(batching: bool = false) -> void:
	var person := _person()
	if person == null:
		_sprint = 0.0
		_carry = null
		return
	_tell_carry()
	var blend: Variant = person.get(&"sprint_blend")
	_sprint = clampf(float(blend), 0.0, 1.0) if blend != null else 0.0
	if not (_person_grips if person_cache else person.has_method(&"set_support_grip")):
		return
	if not _two_known:
		_two_known = true
		_two_art = _art != null and _support_local.is_finite() \
			and (_art.hands == 2 or (_art.hands == 0 and AwWeaponArtTable.pose_two_handed(_art.pose)))
	var two := _two_art and _weapon != null and visible and _weapon.visible
	if two and batching:
		# The ticker's step computes _support_world natively and calls set_support_grip.
		_row_flags |= ROW_SUPPORT
		_support_sent = true
	elif two:
		person.call(&"set_support_grip", _support_world())
		_support_sent = true
	else:
		_send_support(false)


## The support hand's point in the world: on the fore-end, or on the reload's path (well, belt) while one shows.
func _support_world() -> Vector3:
	var fore := _holder.global_transform * _support_local
	if _reload_blend <= 0.0:
		return fore
	var well := _holder.global_transform * (_support_local * 0.45)
	var belt := well + Vector3.DOWN * 0.28
	var at: Vector3 = AwWeaponPose.sample_field(RELOAD_SUPPORT_KEYS, reload_fraction(), 1)
	var path := fore.lerp(well, clampf(at.x, 0.0, 1.0)).lerp(belt, clampf(at.y, 0.0, 1.0))
	return fore.lerp(path, smoothstep(0.0, 1.0, _reload_blend))


## The person's carry, if it has one and [member person_carry] is on (or [param any]): an object answering `fired`
## and `set_class` on its `carry` property.
func _person_carry(any: bool = false) -> Object:
	var person := _person()
	if person == null or not (person_carry or any):
		return null
	var carry: Variant = person.get(&"carry")
	if not (carry is Object):
		return null
	if not person_cache or not is_same(carry, _carry_seen):
		_carry_seen = carry
		_carry_seen_ok = (carry as Object).has_method(&"fired") and (carry as Object).has_method(&"set_class")
	return carry if _carry_seen_ok else null


## Gives the person's carry the class of the gun in hand when either changes, and the reload and switch flags.
func _tell_carry() -> void:
	var carry := _person_carry(true)
	if carry != null and not person_carry:
		if _carry_for != &"off":
			carry.call(&"set_class", null)
			_carry_for = &"off"
		carry = null
	if carry == null:
		_carry = null
		return
	if carry != _carry or _carry_for != _id:
		_carry = carry
		_carry_for = _id
		_told_reloading = -1
		_told_switching = -1
		carry.call(&"set_class", carry_class(_art))
	# Written when they change: nothing else writes them, and two property sets by name a frame per gun added up.
	var reloading := int(_reloading)
	if reloading != _told_reloading or not person_cache:
		_told_reloading = reloading
		carry.set(&"reloading", _reloading)
	var switching := int(_switching)
	if switching != _told_switching or not person_cache:
		_told_switching = switching
		carry.set(&"switching", _switching)


## The carry class (gs-player-char's `GSHumanoidCarry.CLASSES`) [param art] is held as; see [code]aw_carry_class.gd[/code].
static func carry_class(art: AwWeaponVisual) -> Variant:
	return CarryClass.of(art)


func _send_support(_on: bool) -> void:
	if not _support_sent:
		return
	_support_sent = false
	var person := _person()
	if person != null and person.has_method(&"set_support_grip"):
		person.call(&"set_support_grip", Vector3.INF)


func _show_in_hand(shown: bool) -> void:
	if _weapon != null and _weapon.visible != shown:
		_weapon.visible = shown
	for part in _attachments:
		if part.visible != shown:
			part.visible = shown


# --- Internals --------------------------------------------------------------

## The effects node, taken from [AwFxPool] the first time this hand fires, or built then
## when no pool has one parked.
func _shot_fx() -> AwShotFx:
	if _fx != null and is_instance_valid(_fx):
		# Read every shot, not only at creation: a game that turns sounds off after the
		# first shot (a settings change) would otherwise keep hearing them.
		_fx.sounds = sounds
		return _fx

	_fx = AwFxPool.take_shot_fx()
	if _fx == null:
		_fx = AwShotFx.new()
	_fx.name = "ShotFx"
	_fx.sounds = sounds
	add_child(_fx)
	_fx.exclude_carrier(_carrier_body())
	return _fx


## The nearest physics body above this hand: the character carrying it, whose own capsule
## the barrel starts inside.
func _carrier_body() -> Node:
	var node := get_parent()
	var depth := 0

	while node != null and depth < 8:
		if node is CollisionObject3D:
			return node
		node = node.get_parent()
		depth += 1

	return null


## Whether a first-person rig with its own effects carries this hand on this machine. Asked of the tree, not configured:
## a game that forgot to switch the local player's world model off would play every shot twice. Kept until [member rig_epoch]
## moves or this model does, because the walk visits every sibling of every ancestor and a watcher asks on every shot.
func _carrier_draws_its_own() -> bool:
	if _draws_own_epoch == rig_epoch:
		return _draws_own
	_draws_own = _walk_for_carrier_fx()
	_draws_own_epoch = rig_epoch
	return _draws_own


func _walk_for_carrier_fx() -> bool:
	var node := get_parent()
	var depth := 0

	while node != null and depth < 8:
		for child in node.get_children():
			# By method, not by class: the rig names this script, so naming the rig here closed a parser cycle.
			if child.has_method(&"shot_fx") and child.call(&"shot_fx") != null:
				return true
		node = node.get_parent()
		depth += 1

	return false


func _clear_models() -> void:
	_mag = null
	if _weapon != null:
		_weapon.queue_free()

	for node in _attachments:
		node.queue_free()

	_weapon = null
	_attachments.clear()
	_dressed = {}
	_fitting = null
	_fit_code = -1
	_kick = 0.0
	_action = 1.0


func describe() -> Dictionary:
	return {
		"equipped": String(_id),
		"has_model": _weapon != null,
		"attachments": _attachments.size(),
		"attached": get_parent() != null,
		"mount": String(mount),
		"action": snappedf(_action, 0.01),
		"reload": snappedf(reload_fraction(), 0.01),
	}
