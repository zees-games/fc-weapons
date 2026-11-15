@tool
extends "aw_weapon_rig_reload.gd"

## Setup half of [AwWeaponRig], split out for file size: finding the carrier, the arsenal and the
## presentation nodes a rig drives. Behaviour lives in [AwWeaponRig], which extends this.

const CHANNEL := "aw.rig"

const BASH_BEHAVIOUR := "res://addons/arena_weapons/behaviour/aw_weapon_bash.gd"

## Layers the wall probe stops on beyond the shot mask: set it to what stops the carrier (clip brushes and fences a shot passes), so the gun lowers at them.
@export_flags_3d_physics var wall_extra_mask: int = 0:
	set(v):
		wall_extra_mask = v
		if _view != null and _fx != null:
			_view.wall_mask = _fx.collision_mask | v


## Builds everything and validates the catalogue. Safe to call twice.
func setup() -> DotResult:
	if _ready_for_use:
		return DotResult.success(null)

	var res := _resolve_arsenal()
	if not res.ok:
		return res.wrap("The rig could not find or build an arsenal.")

	arsenal.catalogue = catalogue if catalogue != null else AwWeaponCatalogue.catalogue()
	arsenal.tick_rate = tick_rate
	arsenal.authority = authority

	var ready_res := arsenal.setup()
	if not ready_res.ok:
		return ready_res

	if allow_bash:
		var script: Variant = load(BASH_BEHAVIOUR)
		if script is Script:
			_bash = (script as Script).new()

	_resolve_carrier()
	if not arsenal.idle_posture.is_valid():
		arsenal.idle_posture = _posture_now
	_resolve_presentation()
	_connect_arsenal()

	_ready_for_use = true
	return DotResult.success(null)


func _resolve_arsenal() -> DotResult:
	if arsenal_ref != null:
		var found := arsenal_ref.resolve(self)
		if found.ok and found.value is DotWeaponArsenal:
			arsenal = found.value
			return DotResult.success(null)

	arsenal = DotWeaponArsenal.new()
	arsenal.name = "Arsenal"
	add_child(arsenal)
	return DotResult.success(null)


## Who is carrying this: not presentation, so it must not be skipped on a server.
## A null player makes [method DotWeaponPlayerBridge.context_for] return defaults, so every shot traces from the world origin.
## Nothing else reports it: the weapon fires and the counters move, but hit registration finds nothing.
func _resolve_carrier() -> void:
	if player_ref == null:
		return

	var player := player_ref.resolve(self)

	if player.ok:
		_player = player.value
		return

	# Loud, because a carrier that cannot be found is a carrier that shoots the map.
	DotLog.warn(CHANNEL, "the rig could not find the player carrying it", {
		"why": player.error.message,
		"consequence": "shots resolve from the world origin",
	})


func _resolve_presentation() -> void:
	if role == Role.SERVER:
		return

	if role == Role.LOCAL and view_model_ref != null:
		var view := view_model_ref.resolve(self)
		if view.ok and view.value is AwViewModel:
			_view = view.value
			_view.ads_rules = ads_rules
			# Cvars bound before the view model existed keep their object.
			if _standalone_feel != null:
				_view.feel_rules = _standalone_feel

	if world_model_ref != null:
		var world := world_model_ref.resolve(self)
		if world.ok and world.value is AwWorldModel:
			_world = world.value

	# Only a first-person rig draws its own shots. Without a view model there is no muzzle
	# this rig owns, and the world model draws them from the hand instead.
	if effects and _view != null:
		_fx = AwShotFx.new()
		_fx.name = "ShotFx"
		_fx.first_person = true
		_fx.catalogue = catalogue
		add_child(_fx)
		_fx.exclude_carrier(_player)
		_view.wall_mask = _fx.collision_mask | wall_extra_mask


func _connect_arsenal() -> void:
	arsenal.reload_started.connect(_on_reload_started)
	arsenal.reload_finished.connect(_on_reload_finished)
	arsenal.switched.connect(_on_switched)
	arsenal.dry_used.connect(_on_dry_used)
	arsenal.fire_mode_changed.connect(_on_fire_mode_changed)


## The motion-only context an idle tick hands the arsenal (see [member DotWeaponArsenal.idle_posture]).
func _posture_now() -> DotWeaponContext:
	var ctx := DotWeaponPlayerBridge.posture_for(_player, _last_tick)
	ctx.authority = authority
	return ctx
