extends RefCounted

## The scope's lens as real glass: a disc at the ocular showing the world through a second camera that rides the scope while the scope is raised.
## The camera looks down the tube (-Z) in the model's space, on the view layer so the gun is not in its own lens; a reticle is drawn in the disc's shader.
## The second camera draws the whole scene again, so it renders only while it is live (see [method update]); the rest of the time the model's baked lens shows.
## Not built headless (nothing renders). Preloaded by path (no `class_name`), as aw_scope_housing.gd is.

## The largest lens picture (pixels a side); a smaller lens on screen gets a smaller one, in steps of [constant RESOLUTION_STEP].
const RESOLUTION := 384
const MIN_RESOLUTION := 128
const RESOLUTION_STEP := 64
## How far into the aim (0 at the hip, 1 aimed) the lens starts rendering the scene. Below it the baked lens shows and nothing is drawn twice.
## 0 renders it at the hip as well: a whole second scene pass every frame for a lens a few dozen pixels wide.
static var live_from := 0.3
## How far in front of the ocular the disc sits (metres in model space), so it covers the baked glass.
const DISC_LIFT := 0.0012
const SIDES := 48
## Baked placeholders in the model (tools/add_scope_lens.py) the live glass replaces.
const BAKED := [&"scope_lens", &"scope_reticle", &"scope_eyecup", &"scope_eyecup_lip"]

const _NO_BAKED: Array = []
const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, shadows_disabled;
uniform sampler2D picture : source_color, filter_linear;
uniform vec4 tint : source_color = vec4(0.82, 0.95, 0.9, 1.0);
uniform vec4 reticle_colour : source_color = vec4(0.02, 0.02, 0.02, 0.95);
uniform float vignette = 0.5;
varying vec2 uv_at;
void vertex() { uv_at = UV; }
void fragment() {
	vec2 p = (uv_at - 0.5) * 2.0;
	float r = length(p);
	float px = fwidth(r) * 1.5;
	// How small the lens is on screen: near 1 for the hip lens (a few dozen pixels), 0 once the scope fills the view. A small lens is a window, not a decal:
	// the tint, vignette, glint and heavy lip fade out so the world shows through undimmed, and only a faint thin cross stays.
	float small = 1.0 - smoothstep(0.012, 0.04, fwidth(r));
	vec3 col = texture(picture, uv_at).rgb * mix(tint.rgb, vec3(1.0), small);
	col *= 1.0 - vignette * (1.0 - small) * smoothstep(0.55, 1.0, r);
	float hw = max(0.004, px * 0.5);
	float line = max(1.0 - smoothstep(hw, hw + px, abs(p.x)), 1.0 - smoothstep(hw, hw + px, abs(p.y)));
	line *= step(0.06, r);
	float ticks = 0.0;
	for (int i = 1; i < 5; i++) {
		float d = float(i) * 0.18;
		ticks = max(ticks, (1.0 - smoothstep(0.012, 0.012 + px, length(p - vec2(d, 0.0)))) + (1.0 - smoothstep(0.012, 0.012 + px, length(p + vec2(d, 0.0)))));
		ticks = max(ticks, (1.0 - smoothstep(0.012, 0.012 + px, length(p - vec2(0.0, d)))) + (1.0 - smoothstep(0.012, 0.012 + px, length(p + vec2(0.0, d)))));
	}
	float mark = clamp(max(line, ticks * (1.0 - small)), 0.0, 1.0) * reticle_colour.a * mix(1.0, 0.45, small);
	col = mix(col, reticle_colour.rgb, mark);
	// Glass: a soft diagonal glint across the upper left (large lens only) and a dark metal lip at the edge, thin on the small lens.
	float glint = smoothstep(0.35, 0.0, abs(p.x * 0.7 + p.y * 0.7 + 0.45)) * (1.0 - smoothstep(0.7, 0.95, r)) * 0.22 * (1.0 - small);
	col += vec3(0.85, 0.95, 1.0) * glint;
	col = mix(col, vec3(0.03, 0.04, 0.05), smoothstep(mix(0.86, 0.94, small), 0.98, r));
	ALBEDO = col;
}
"""

static var _shader: Shader = null
## A put-away glass gives back its picture: the port shrinks to one pixel until [method update] next makes it live (each kept lens held a
## 384-pixel MSAA target, about 3.5 MB of video memory, for every scoped gun stowed in any view or kill-view rig). False keeps it, as before.
static var release_stowed := true
## Every lens shares one environment made from the scene's; false duplicates the scene's environment for each glass, as before.
static var share_environment := true
static var _env_source: Environment = null
static var _env_lens: Environment = null


## The glass for [param style] (a weapon's scope style: its `ocular` [x, y, z, radius]) in the model's space, or null headless / without an ocular.
## [param view_layer] is the render layer the gun is on (1 to 20, 0 for none): the lens camera leaves it out.
static func build(style: Dictionary, view_layer: int) -> Node3D:
	var ocular: Variant = style.get("ocular", null)
	if DisplayServer.get_name() == "headless" or not (ocular is Array) or (ocular as Array).size() < 4 or float(ocular[3]) <= 0.0:
		return null
	var radius := float(ocular[3])
	var root := Node3D.new()
	root.name = "ScopeGlass"
	root.position = Vector3(float(ocular[0]), float(ocular[1]), float(ocular[2]))

	var port := SubViewport.new()
	port.name = "Port"
	port.size = Vector2i(RESOLUTION, RESOLUTION)
	port.render_target_update_mode = SubViewport.UPDATE_DISABLED
	port.transparent_bg = false
	port.msaa_3d = Viewport.MSAA_2X
	# No omni or spot shadows in the lens: its own shadow atlas would redraw every lit caster for a picture this size.
	port.positional_shadow_atlas_size = 0
	root.add_child(port)
	root.set_meta(&"radius", radius)

	var camera := Camera3D.new()
	camera.name = "Lens"
	camera.near = 0.05
	camera.far = 2000.0
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	if view_layer > 0:
		camera.cull_mask = 0xFFFFF & ~(1 << (view_layer - 1))
	port.add_child(camera)

	var disc := MeshInstance3D.new()
	disc.name = "Disc"
	disc.mesh = _disc(radius)
	disc.position = Vector3(0.0, 0.0, DISC_LIFT)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var material := ShaderMaterial.new()
	material.shader = _shader
	material.set_shader_parameter("picture", port.get_texture())
	disc.material_override = material
	if view_layer > 0:
		disc.layers = 1 << (view_layer - 1)
	disc.sorting_offset = 100.0
	root.add_child(disc)
	return root


## Whether the lens renders the scene at [param aim] (0 at the hip, 1 aimed): from [member live_from] on.
static func live_at(aim: float) -> bool:
	return aim >= live_from


## The lens picture's side (pixels) for a lens [param pixels] wide on screen: rounded up to [constant RESOLUTION_STEP], within
## [constant MIN_RESOLUTION] and [constant RESOLUTION].
static func side_for(pixels: float) -> int:
	return clampi(ceili(maxf(pixels, 1.0) / RESOLUTION_STEP) * RESOLUTION_STEP, MIN_RESOLUTION, RESOLUTION)


## Points the lens camera, once per frame: [param main] is the camera the view model hangs from, [param fov_scale] the zoom the glass shows
## (the scope's current level, 0 or less leaves the main camera's own), [param shown] whether the glass is seen this frame, [param aim] how far
## the scope is raised (0 at the hip, 1 aimed).
## The lens renders only while shown, raised past [member live_from], in the tree and seen through a current camera; then it is armed for one
## frame at a time (UPDATE_ONCE), so a view model that stops calling this (parked, hidden, stowed) stops the second render on its own.
static func update(root: Node3D, main: Camera3D, fov_scale: float, shown: bool, aim: float = 1.0) -> void:
	if not is_instance_valid(root):
		return
	root.visible = shown
	var port := root.get_node_or_null(^"Port") as SubViewport
	if port == null:
		return
	var live := shown and live_at(aim) and main != null and main.current and root.is_visible_in_tree()
	var disc := root.get_node_or_null(^"Disc") as Node3D
	if disc != null:
		disc.visible = live
	for baked: Variant in (root.get_meta(&"baked") if root.has_meta(&"baked") else _NO_BAKED):
		if is_instance_valid(baked):
			(baked as Node3D).visible = not live
	port.render_target_update_mode = SubViewport.UPDATE_ONCE if live else SubViewport.UPDATE_DISABLED
	var camera := port.get_node_or_null(^"Lens") as Camera3D
	if camera == null or not live:
		return
	# The camera looks down the tube from the ocular: the disc's own transform without its scale.
	camera.global_transform = Transform3D(root.global_transform.basis.orthonormalized(), root.global_transform.origin)
	var scale_by := fov_scale if fov_scale > 0.0 else 1.0
	camera.fov = clampf(rad_to_deg(2.0 * atan(tan(deg_to_rad(main.fov) * 0.5) * scale_by)), 1.0, 120.0)
	if camera.environment == null:
		camera.environment = _lens_environment(main)
	var side := side_for(_lens_pixels(root, main))
	if port.size.x != side:
		port.size = Vector2i(side, side)


## Lets [param root]'s port give back its picture while the glass is put away (see [member release_stowed]): one pixel and no render.
## [method update] sizes it again the first frame it is live.
static func release(root: Node3D) -> void:
	if not release_stowed or not is_instance_valid(root):
		return
	var port := root.get_node_or_null(^"Port") as SubViewport
	if port == null:
		return
	port.render_target_update_mode = SubViewport.UPDATE_DISABLED
	port.size = Vector2i(1, 1)


## Draws [param root]'s lens once at full size through [param main]'s view, for a load cover: the lens's own pass (its MSAA and
## environment) compiles its pipelines then, not on the first raised scope. The next [method update] puts it back as it should be.
static func prime(root: Node3D, main: Camera3D) -> void:
	if not is_instance_valid(root) or main == null:
		return
	var port := root.get_node_or_null(^"Port") as SubViewport
	if port == null:
		return
	var camera := port.get_node_or_null(^"Lens") as Camera3D
	if camera != null:
		camera.global_transform = main.global_transform
		camera.fov = main.fov
		if camera.environment == null:
			camera.environment = _lens_environment(main)
	var disc := root.get_node_or_null(^"Disc") as Node3D
	if disc != null:
		disc.visible = true
	port.size = Vector2i(RESOLUTION, RESOLUTION)
	port.render_target_update_mode = SubViewport.UPDATE_ONCE


## How many pixels wide the lens is on [param main]'s screen.
static func _lens_pixels(root: Node3D, main: Camera3D) -> float:
	var depth := -(main.global_transform.affine_inverse() * root.global_position).z
	if depth <= 0.001:
		return float(RESOLUTION)
	var radius := float(root.get_meta(&"radius", 0.0)) * root.global_transform.basis.get_scale().x
	var height := main.get_viewport().get_visible_rect().size.y
	return radius / (depth * tan(deg_to_rad(main.fov) * 0.5)) * height


## The scene's environment for the lens without its screen-space and volume passes (SSAO, SSIL, SSR, SDFGI, volumetric fog): their buffers
## would be built again for a small picture. Null when the scene has none (the lens then uses the world's, as before).
static func _lens_environment(main: Camera3D) -> Environment:
	var source := main.environment
	if source == null and main.get_world_3d() != null:
		source = main.get_world_3d().environment
	if source == null:
		return null
	if share_environment and source == _env_source and _env_lens != null:
		return _env_lens
	var env := source.duplicate() as Environment
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.ssr_enabled = false
	env.sdfgi_enabled = false
	env.volumetric_fog_enabled = false
	if share_environment:
		_env_source = source
		_env_lens = env
	return env


## The baked placeholders (see [constant BAKED]) of [param model], hidden: the live glass and housing take their place. With [param glass]
## (built by [method build]) they are kept on it, and [method update] shows them again whenever the lens is not live.
static func hide_baked(model: Node, glass: Node3D = null) -> void:
	var found: Array[Node3D] = []
	for named in BAKED:
		var node := model.find_child(String(named), true, false) as Node3D
		if node != null:
			node.visible = false
			found.append(node)
	if glass != null:
		glass.set_meta(&"baked", found)


## A disc of [param radius] facing +Z (toward the eye), UVs mapped across it.
static func _disc(radius: float) -> ArrayMesh:
	var verts := PackedVector3Array([Vector3.ZERO])
	var uvs := PackedVector2Array([Vector2(0.5, 0.5)])
	var normals := PackedVector3Array([Vector3.BACK])
	var indices := PackedInt32Array()
	for i in SIDES:
		var dir := Vector2.from_angle(TAU * float(i) / float(SIDES))
		verts.append(Vector3(dir.x * radius, dir.y * radius, 0.0))
		uvs.append(Vector2(0.5 + dir.x * 0.5, 0.5 - dir.y * 0.5))
		normals.append(Vector3.BACK)
	for i in SIDES:
		indices.append_array([0, 1 + i, 1 + (i + 1) % SIDES])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
