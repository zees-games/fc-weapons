extends RefCounted

## The scope's lens as real glass: a disc at the ocular showing the world through a second camera that rides the scope, so the scene is seen through it
## at all times (hip, idle, in sway), not only while aiming. The camera sits at the ocular looking down the tube (-Z, the muzzle's way) in the model's
## space, so it follows every sway and recoil the hands do. Drawn on the view layer, so the gun is not in its own lens. A reticle is drawn in the disc's shader.
## Not built headless (nothing renders). Preloaded by path (no `class_name`), as aw_scope_housing.gd is.

const RESOLUTION := 384
## How far in front of the ocular the disc sits (metres in model space), so it covers the baked glass.
const DISC_LIFT := 0.0012
const SIDES := 48
## Baked placeholders in the model (tools/add_scope_lens.py) the live glass replaces.
const BAKED := [&"scope_lens", &"scope_reticle", &"scope_eyecup", &"scope_eyecup_lip"]

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
	vec3 col = texture(picture, vec2(uv_at.x, uv_at.y)).rgb * tint.rgb;
	col *= 1.0 - vignette * smoothstep(0.55, 1.0, r);
	float px = fwidth(r) * 1.5;
	float line = max(1.0 - smoothstep(0.004, 0.004 + px, abs(p.x)), 1.0 - smoothstep(0.004, 0.004 + px, abs(p.y)));
	line *= step(0.06, r);
	float ticks = 0.0;
	for (int i = 1; i < 5; i++) {
		float d = float(i) * 0.18;
		ticks = max(ticks, (1.0 - smoothstep(0.012, 0.012 + px, length(p - vec2(d, 0.0)))) + (1.0 - smoothstep(0.012, 0.012 + px, length(p + vec2(d, 0.0)))));
		ticks = max(ticks, (1.0 - smoothstep(0.012, 0.012 + px, length(p - vec2(0.0, d)))) + (1.0 - smoothstep(0.012, 0.012 + px, length(p + vec2(0.0, d)))));
	}
	float mark = clamp(max(line, ticks), 0.0, 1.0) * reticle_colour.a;
	col = mix(col, reticle_colour.rgb, mark);
	ALBEDO = col;
}
"""

static var _shader: Shader = null


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
	root.add_child(port)

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


## Points the lens camera, once per frame: [param main] is the camera the view model hangs from, [param fov_scale] the zoom the glass shows
## (the scope's current level, 0 or less leaves the main camera's own), [param shown] whether the glass is seen this frame.
static func update(root: Node3D, main: Camera3D, fov_scale: float, shown: bool) -> void:
	if not is_instance_valid(root):
		return
	root.visible = shown
	var port := root.get_node_or_null("Port") as SubViewport
	if port == null:
		return
	port.render_target_update_mode = SubViewport.UPDATE_ALWAYS if shown else SubViewport.UPDATE_DISABLED
	var camera := port.get_node_or_null("Lens") as Camera3D
	if camera == null or main == null or not shown:
		return
	# The camera looks down the tube from the ocular: the disc's own transform without its scale.
	camera.global_transform = Transform3D(root.global_transform.basis.orthonormalized(), root.global_transform.origin)
	var scale_by := fov_scale if fov_scale > 0.0 else 1.0
	camera.fov = clampf(rad_to_deg(2.0 * atan(tan(deg_to_rad(main.fov) * 0.5) * scale_by)), 1.0, 120.0)


## The baked placeholders (see [constant BAKED]) of [param model], hidden: the live glass and housing take their place.
static func hide_baked(model: Node) -> void:
	for named in BAKED:
		var node := model.find_child(String(named), true, false) as Node3D
		if node != null:
			node.visible = false


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
