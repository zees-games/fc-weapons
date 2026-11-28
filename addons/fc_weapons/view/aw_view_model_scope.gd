@tool
extends "aw_view_model_reload.gd"

## AwViewModel's scope: the lens and full-screen views, the zoom levels, the scope body and the fade of its surround.

@export_group("Scope")

## How far into the aim-in a scoped weapon's arms are hidden: by default only once the aim is complete, so the support hand stays on the gun while it rises and the scope picture (which hides the gun and arms together) takes over.
@export_range(0.0, 1.0, 0.01) var scope_arms_hide: float = 1.0

## The [method scope_fraction] from which the gun model is no longer drawn: the lens is up and the gun would show through it.
const SCOPE_GUN_HIDE_FRACTION := 0.5
## On the way out the gun stays hidden until the surround is this nearly gone, so it never shows through a half-faded scope.
const SCOPE_GUN_SHOW_FRACTION := 0.02
var _gun_covered := false
## A game's setting (a cvar) that beats the weapon's art and [member scope_arms_hide]; below 0 is off.
var scope_arms_hide_override: float = -1.0

var _style_art: AwWeaponVisual = null
var _style_ocular: Array = []
var _style: Dictionary = {}

const Describe := preload("aw_view_describe.gd")
const ScopeView := preload("res://addons/gs_weapon/view/gs_weapon_scope_view.gd")

## The scope views: the scope as a lens on a normal screen, and the scope filling it.
const SCOPE_LENS := ScopeView.LENS
const SCOPE_FULL := ScopeView.FULL

## The scope view the player chose (a game sets it from its cvar, through [method AwAdsRules.resolve_scope_mode]).
var scope_mode: int = SCOPE_LENS

var _zoom_level := 0

## The scope drawn as its own body (lens view only): the gun stays up at full aim, grown about the eye until its ocular
## is the lens circle, and [AwScopeOverlay] draws the zoomed picture into that ocular. Off (the default) keeps the flat lens.
var scope_body := false
## How far in front of the eye the ocular sits in the scope body view, in metres; it must be past the camera's near plane.
var scope_body_relief: float = 0.1
## The lens circle a scope style without `lens_circle` gets: the shared overlay's own default.
const SCOPE_BODY_CIRCLE := 0.46

## How much of the scope's picture goes clear at a walk (0 keeps it solid at any speed), and the speed in m/s that clears all of it.
var scope_walk_clear: float = 0.55
var scope_walk_speed: float = 5.0


## The scope view the player [param wanted], or the one the server's ADS rules pin for this weapon.
func resolve_scope_mode(wanted: int) -> int:
	if ads_rules == null or _art == null:
		return ScopeView.resolve(wanted)
	return ads_rules.resolve_scope_mode(_art.id, wanted)


## The scope as a lens: the camera stays at the hip's field of view and the overlay's own camera shows the zoom.
func scope_is_lens() -> bool:
	return ScopeView.is_lens(scope_mode, has_scope())


## The field-of-view multiplier the main camera takes: [method aim_fov_scale], or 1 with the scope as a lens, which zooms itself.
func view_fov_scale() -> float:
	return ScopeView.fov_scale(scope_is_lens(), aim_fov_scale())


## How much of the scope's picture is clear because the player is moving: 0 standing, up to [member scope_walk_clear].
func scope_clear() -> float:
	return ScopeView.clear(has_scope(), scope_walk_clear, scope_walk_speed, _speed)


## The field-of-view multiplier this frame: 1 at the hip, the zoom at full aim; the game applies it (`GSFpsView.external_fov_scale`).
func aim_fov_scale() -> float:
	if _art == null:
		return 1.0
	return lerpf(1.0, scope_zoom_scale(), _ease(_aim_fraction))


## The camera multiplier of the zoom level now looked through at full aim; the scope's glass shows it at all times.
func scope_zoom_scale() -> float:
	if _art == null:
		return 1.0
	var base := float(_dressed.get("zoom", 0.0))  # perf-lint: allow dynamic_call Dictionary.get (_dressed is the fitted optic's row)
	base = base if base > 0.0 else _art.aim_zoom
	var zoom := base if ads_rules == null else ads_rules.zoom_for(_art.id, base)
	return ScopeView.scale_at(zoom_scales(), _zoom_level, zoom)


## The camera multipliers of the equipped scope's zoom levels, widest first; empty when it has one zoom.
func zoom_scales() -> PackedFloat32Array:
	if _art == null:
		return PackedFloat32Array()
	var levels: Array = _art.aim_zoom_levels
	if ads_rules != null:
		levels = ads_rules.zoom_levels_for(_art.id, levels)
	return ScopeView.level_scales(levels)


## The zoom level now looked through (0 the widest).
func zoom_level() -> int:
	return _zoom_level


## Steps a scope with two zoom levels to the next, wrapping; returns the new level. Does nothing off a scope.
func cycle_zoom() -> int:
	if _art == null or not has_scope():
		return _zoom_level
	_zoom_level = ScopeView.next_level(_zoom_level, zoom_scales().size())
	return _zoom_level


## Whether the weapon's view is a scope: its own, unless a fitted optic replaced the built-in one, then that optic's.
func _aim_scoped() -> bool:
	return bool(_dressed.get("scoped", false)) or (_art.aim_scoped and not bool(_dressed.get("replaced", false)))  # perf-lint: allow dynamic_call Dictionary.get (_dressed is the fitted optic's row)


## Whether the view is through a scope right now: a scoped weapon at (nearly) full aim.
func is_scoped() -> bool:
	return _art != null and _aim_scoped() and _aim_fraction >= 0.95


## The aim fraction the arms hide at: the override, else the weapon's art key, else [member scope_arms_hide].
func scope_arms_hide_at() -> float:
	if scope_arms_hide_override >= 0.0:
		return scope_arms_hide_override
	return _art.scope_arms_hide if _art != null and _art.scope_arms_hide >= 0.0 else scope_arms_hide


## Whether a scoped weapon's arms are hidden: from [method scope_arms_hide_at] of the aim-in on.
func arms_hidden_by_scope() -> bool:
	return _art != null and _aim_scoped() and _aim_fraction >= scope_arms_hide_at()


## Whether the weapon in hand is looked through (a scope), at any point of the aim-in.
func has_scope() -> bool:
	return _art != null and _aim_scoped()


## The weapon's overrides of the default scope look, applied by [method AwScopeOverlay.follow].
## A fitted scoped optic brings its own `ocular`, so the gun stays up behind it as behind a built-in scope.
func scope_style() -> Dictionary:
	if _art == null:
		return {}
	var ocular: Array = _dressed.get("ocular", NO_CUES)
	if ocular.is_empty():
		return _art.scope_style
	if _style_art != _art or not is_same(ocular, _style_ocular):
		_style_art = _art
		_style_ocular = ocular
		_style = _art.scope_style.merged({"ocular": ocular})
	return _style


## Whether the scope is drawn as its body this frame: [member scope_body] on, the lens view, and an `ocular` in the weapon's scope style.
## A fitted optic that replaced the built-in scope has its own ocular, or else the flat lens is used.
func scope_body_active() -> bool:
	var own: bool = not (_dressed.get("ocular", NO_CUES) as Array).is_empty()  # perf-lint: allow dynamic_call Dictionary.get (_dressed is the fitted optic's row)
	return scope_body and scope_is_lens() and (own or not bool(_dressed.get("replaced", false))) and not Describe.scope_ocular(scope_style()).is_empty()  # perf-lint: allow dynamic_call Dictionary.get (_dressed is the fitted optic's row)


## The ocular's centre and a point on its edge, in global space, for [AwScopeOverlay]; empty unless [method scope_body_active] and drawn.
func scope_ocular_points() -> Dictionary:
	if not scope_body_active() or _holder == null or not _holder.is_inside_tree() or not _animated.visible:
		return {}
	var ocular := Describe.scope_ocular(scope_style())
	var held := _holder.global_transform
	return {"centre": held * (ocular[0] as Vector3), "edge": held * ((ocular[0] as Vector3) + Vector3(float(ocular[1]), 0.0, 0.0))}


## How many times larger than its view scale the gun is drawn at full aim in the scope body view, so an ocular of
## [param radius] at [member scope_body_relief] fills the lens circle. Drawn about the eye, it looks the same, only nearer.
func _scope_body_growth(radius: float) -> float:
	var camera := get_parent() as Camera3D
	var fov := camera.fov if camera != null else 75.0
	var share := 1.0
	if is_inside_tree():
		var rect := get_viewport().get_visible_rect().size
		share = minf(rect.x, rect.y) / rect.y if rect.y > 0.0 else 1.0
	var circle := float(scope_style().get("lens_circle", SCOPE_BODY_CIRCLE))  # perf-lint: allow dynamic_call Dictionary.get (the scope style)
	var want := scope_body_relief * tan(deg_to_rad(fov) * 0.5) * circle * share
	var lens := absf(scale.x) if not is_zero_approx(scale.x) else 1.0
	return maxf(want / (radius * lens * maxf(_art.view_scale, 0.001)), 0.001)


## The gun's origin at aim fraction [param f] in the scope body view, turned as [param now]: the [param ocular]'s depth before
## the [param eye] shrinks from its [param hip] place to its [param sight] one by the same ratio each step and its place on
## screen moves evenly, so the eyepiece grows by an even factor per frame. A straight move leaves it small until the last
## frames, then triples it each frame as it closes on the eye.
static func scope_body_origin(now: Transform3D, hip: Transform3D, sight: Transform3D, ocular: Vector3, eye: Vector3, f: float) -> Vector3:
	var from := hip * ocular - eye
	var to := sight * ocular - eye
	if from.z >= 0.0 or to.z >= 0.0:
		return now.origin
	var depth := -from.z * pow(to.z / from.z, f)
	var screen := (Vector2(from.x, from.y) / -from.z).lerp(Vector2(to.x, to.y) / -to.z, f)
	return eye + Vector3(screen.x * depth, screen.y * depth, -depth) - now.basis * ocular


## How visible the scope's surround is, 0 to 1: it fades in over the last of the aim-in, not at the end.
func scope_fraction() -> float:
	if not has_scope():
		return 0.0
	var start := 0.6 if ads_rules == null else ads_rules.scope_fade_start_for(_art.id)
	return smoothstep(start, 1.0, _aim_fraction)


## Whether the scope's picture is up enough that the 3D gun must not show through it: the surround is at least half in.
func scope_picture_up() -> bool:
	return has_scope() and (_gun_covered or scope_fraction() >= SCOPE_GUN_HIDE_FRACTION)


## The scope lens's size, a share of its full size: small at the start of the aim-in, growing toward the eye.
func scope_lens_scale() -> float:
	if not has_scope():
		return 1.0
	var least := 0.3 if ads_rules == null else ads_rules.scope_lens_min_for(_art.id)
	return lerpf(least, 1.0, _ease(_aim_fraction))


## The model's own rear aperture rings (mesh nodes named `rear_ring`) and a built sight's rear notch: drawn only once
## the aim is this far in, since at the hip a ring a few centimetres from the eye is a hoop around the crosshair.
const REAR_RING_SHOW_AIM := 0.35
## The aim at which the rings start to fade in: from here to [constant REAR_RING_SHOW_AIM] they go from clear to solid,
## so the ring grows into the picture as the gun rises instead of popping in on one frame (and out on the way down).
const REAR_RING_FADE_FROM := 0.1
## On the raise the fade runs to this aim instead: a raise takes ~0.16 s, and the narrow window fits inside one frame
## and reads as a pop. The lower keeps the narrow window (it is slower, and a long fade there leaves a translucent ring
## floating over the dropping gun).
const REAR_RING_RAISE_SHOW_AIM := 0.7


## Shows the rear rings [param f] of the way into the aim: hidden below [constant REAR_RING_FADE_FROM], see-through
## up to [constant REAR_RING_SHOW_AIM], solid past it.
func _fade_rear_rings(f: float) -> void:
	var raising := f > _ring_aim_last
	_ring_aim_last = f
	var solid_at := REAR_RING_RAISE_SHOW_AIM if raising else REAR_RING_SHOW_AIM
	var clear := 1.0 - smoothstep(REAR_RING_FADE_FROM, solid_at, f)
	if is_equal_approx(clear, _ring_fade):
		return
	_ring_fade = clear
	for ring in _rear_rings:
		if is_instance_valid(ring):
			ring.visible = clear < 1.0
			_set_clear(ring, clear)


static func _set_clear(node: Node, clear: float) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).transparency = clear
	for child in node.get_children():
		_set_clear(child, clear)
