@tool
class_name AwScopeOverlay
extends "res://addons/dot_weapon/view/dot_weapon_scope_overlay.gd"

## What a player sees through a scope; the drawing and the exports live in dot-weapon's shared
## overlay (`view/dot_weapon_scope_overlay.gd`), which zee-dot-weapons' [ZeeScopeOverlay] also
## extends. A game puts one of these in its HUD and calls [method follow] with its [AwViewModel]
## each frame.

var _own_style: Dictionary = {}

## Where the lens and reticle sit off centre, in lens radii (x right, y down); [method follow] takes it from the view.
var motion := Vector2.ZERO

## The view whose scope is drawn as its body (AwViewModel.scope_ocular_points), or null for the flat lens.
var _body_view: Object = null

## Takes the view's state, then sets the lens camera so the glass magnifies: the shared overlay
## spreads the zoomed camera's whole frame over the lens, which on screen is barely bigger than the hip view.
func follow(view: Object) -> void:
	# A weapon's style keys go back to the overlay's own values first, so the next gun does not keep the last one's look.
	var style: Dictionary = view.scope_style()
	for key: Variant in style:
		if key is String and key in self and not _own_style.has(key):
			_own_style[key] = get(key)
	for key: String in _own_style:
		set(key, _own_style[key])
	super.follow(view)
	_body_view = view if view.has_method(&"scope_ocular_points") and not (view.scope_ocular_points() as Dictionary).is_empty() else null
	var body := _body_lens()
	if is_instance_valid(_source) and size.y > 0.0:
		var share := minf(size.x, size.y) * lens_circle * lens_scale / size.y
		share = share if body.is_empty() else 2.0 * float(body["radius"]) / size.y
		lens_zoom = lens_fov_share(_source.fov, view.aim_fov_scale(), share)
	if _body_view != null:
		queue_redraw()
	# The scope body moves in the 3D hands, so the lens follows its ocular and not the drawn motion.
	var moved: Vector2 = view.scope_offset() if view.has_method(&"scope_offset") and _body_view == null else Vector2.ZERO
	if not moved.is_equal_approx(motion):
		motion = moved
		queue_redraw()


## The shared drawing, shifted by [member motion]: lens, rim and reticle move as one, as a scope
## tube does in the hands. A full-screen scope's surround is widened so no edge shows through.
func _draw() -> void:
	var body := _body_lens() if mode == 1 else {}
	if not body.is_empty():
		_draw_lens_at(body["centre"], body["radius"])
		return
	var shift := motion * minf(size.x, size.y) * 0.5 * lens_scale * (lens_circle if mode == 1 else circle)
	if shift.is_zero_approx() or fraction <= 0.0 or clear >= 1.0:
		super._draw()
		return
	if mode == 2:
		var surround := Color(surround_colour, surround_colour.a * fraction * (1.0 - clear))
		draw_rect(Rect2(0.0 if shift.x > 0.0 else size.x + shift.x, 0.0, absf(shift.x), size.y), surround)
		draw_rect(Rect2(0.0, 0.0 if shift.y > 0.0 else size.y + shift.y, size.x, absf(shift.y)), surround)
	draw_set_transform(shift)
	super._draw()
	draw_set_transform(Vector2.ZERO)


## The share of the main camera's [param fov] (vertical degrees) the lens camera takes so a lens
## [param share] of the screen's height tall shows the world [param zoom] times the hip view's size.
static func lens_fov_share(fov: float, zoom: float, share: float) -> float:
	if fov <= 0.0 or fov >= 179.0:
		return zoom
	var half := tan(deg_to_rad(fov) * 0.5) * zoom * share
	return rad_to_deg(2.0 * atan(half)) / fov


## The scope body's ocular on screen this frame, {centre, radius} in pixels, from the view's 3D points through the
## bound camera; empty for the flat lens. Read at draw time too, so the circle sits on the housing drawn in the same frame.
func _body_lens() -> Dictionary:
	if _body_view == null or not is_instance_valid(_body_view) or not is_instance_valid(_source) or not _source.is_inside_tree():
		return {}
	var points: Dictionary = _body_view.scope_ocular_points()
	if points.is_empty() or _source.is_position_behind(points["centre"]):
		return {}
	var centre := _source.unproject_position(points["centre"])
	var radius := centre.distance_to(_source.unproject_position(points["edge"]))
	return {"centre": centre, "radius": radius} if radius > 0.5 else {}


## The lens view's drawing (dot-weapon's _draw_lens) at [param centre] with [param radius] pixels: the scope body's ocular.
func _draw_lens_at(centre: Vector2, radius: float) -> void:
	var unit := size.y / 1080.0
	var alpha := _shown()
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	var steps := 72
	for i in range(steps):
		var dir := Vector2.from_angle(TAU * float(i) / float(steps))
		points.append(centre + dir * radius)
		uvs.append(Vector2(0.5, 0.5) + dir * 0.5)
	if _port != null and lens_active():
		draw_colored_polygon(points, Color(1.0, 1.0, 1.0, alpha), uvs, _port.get_texture())
	else:
		draw_colored_polygon(points, Color(0.02, 0.03, 0.03, 0.55 * alpha))
	if glass_tint.a > 0.0:
		draw_circle(centre, radius, Color(glass_tint, glass_tint.a * alpha), true, -1.0, true)
	if vignette > 0.0:
		_draw_edge_shadow(centre, radius, alpha)
	_draw_rim(centre, radius, unit)
	_draw_reticle(centre, radius, unit)
