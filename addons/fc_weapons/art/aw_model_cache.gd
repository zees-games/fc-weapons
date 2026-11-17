class_name AwModelCache
extends RefCounted

## Loads a weapon mesh once, measures it once, and hands out copies.
##
## [b]Why a cache at all.[/b] Thirty players holding the same rifle is thirty
## instances of one [PackedScene], not thirty loads of one file. `load()` is cached by
## the engine, so the loading half of this is a convenience; the measuring half is not,
## and that is the part that earns the file. Walking a scene tree to merge mesh bounding
## boxes costs an instantiate, and doing it every time somebody switches weapons is a
## hitch on every switch.
##
## [b]Measuring is how the muzzle is found.[/b] The alternative is a hand-authored
## offset per weapon, and eighteen hand-authored offsets are eighteen chances to be
## quietly wrong — including on `blaster-e`, whose mesh origin is at the stock rather
## than at the centre, so the offset that is correct for the other seventeen puts its
## muzzle somewhere behind the player's ear. A measurement cannot drift from the model
## it measured.
##
## [b]A dedicated server keeps the models warm too[/b], so a first equip does not read a file;
## headless, their textures are shrunk as they load ([member shrink_textures_headless]).

const CHANNEL := "aw.models"

## Path -> PackedScene.
static var _scenes: Dictionary = {}

## Path -> AABB in the model's own space.
static var _bounds: Dictionary = {}

## "path|forward" -> the bore's offset from the forward axis ([method muzzle_bore]).
static var _bores: Dictionary = {}

## How far back from the barrel's far end (metres) the mesh counts as the muzzle's face in [method muzzle_bore]. Thin,
## so a front sight or a bayonet lug a centimetre or two behind the crown stays out of it; 0 turns the measurement off
## and every muzzle sits on the model's forward axis again.
static var muzzle_face_depth := 0.01

## Paths already reported as missing, so a model that is not there is logged once
## rather than once per frame for as long as somebody is holding it.
static var _complained: Dictionary = {}

## Where `res://assets/` is on this machine. `res://` everywhere but inside a mounted pack.
static var _asset_root: String = "res://"

## Where this addon's own models are in a full build.
const ASSETS_BASE := "res://addons/fc_weapons/assets/"

## Folders laid out like [constant ASSETS_BASE], tried in order for a model the build lacks.
## The web shell leaves the models out to stay small and mounts them as a pack on join.
static var _fallback_roots: PackedStringArray = PackedStringArray()


## Puts the art somewhere other than `res://assets/`, for a game delivered as a pack.
##
## [b]Every path in [AwWeaponArtTable] and [AwViewArms] says `res://assets/…`, and in a
## delivered game that is the one place the art is not.[/b] The pack vendors it beside its
## own files and dot-cloud mounts those under `res://dot_cloud/<id>/<version>/`, so a
## client shell — which carries this addon and no art — resolves every weapon to nothing
## and the WARN below says "the weapon will be invisible" for all twenty-seven. The table
## is not rewritten because it is the one file that names art and must keep reading the same
## in a game that builds the art in. Called by the game when it loads, with its mount root;
## `res://` puts it back, and a game that sets it clears it when it goes, because a static
## outlives the game in a shell that switches to another one.
static func set_asset_root(root: String) -> void:
	_asset_root = root if root.ends_with("/") else root + "/"
	_scenes.clear()
	_bounds.clear()
	_complained.clear()


## Lets models under [constant ASSETS_BASE] come from [param root] when the build lacks them.
## Cached misses are dropped, so a weapon drawn invisible before the pack mounted is drawn now.
static func add_fallback_root(root: String) -> void:
	var r := root.trim_suffix("/")
	if r == "" or r in _fallback_roots:
		return
	_fallback_roots.append(r)
	_drop_misses()
	# The table dressed its rows only where a model was readable; redress them now that more are.
	# Loaded, not named: the table names this cache (a parser cycle Godot 4.7 never frees).
	load("uid://c70ct6i6udqgm").drop_cache()


## Undoes [method add_fallback_root], for a shell leaving the game that mounted the pack.
static func remove_fallback_root(root: String) -> void:
	var i := _fallback_roots.find(root.trim_suffix("/"))
	if i < 0:
		return
	_fallback_roots.remove_at(i)
	clear()
	load("uid://c70ct6i6udqgm").drop_cache()


## The folders [method add_fallback_root] listed, in the order they are tried.
static func fallback_roots() -> PackedStringArray:
	return _fallback_roots.duplicate()


## [param path], under [method set_asset_root] when it names the shipped art. A path that
## is already under the root, or names anything else, comes back unchanged.
static func resolve(path: String) -> String:
	if _asset_root == "res://" or not path.begins_with("res://assets/"):
		return path

	return _asset_root + path.trim_prefix("res://")


## The scene at [param path], loaded at most once.
static func scene(path: String) -> DotResult:
	if path == "":
		return DotResult.fail(DotError.CODE_INVALID, "No model path.")

	if _scenes.has(path):
		return DotResult.success(_scenes[path])

	var real := _locate(resolve(path))

	if not ResourceLoader.exists(real):
		return DotResult.fail(
			DotError.CODE_IO,
			"No model at %s. A weapon delivered in a content pack needs that pack " % real
			+ "mounted before it can be drawn."
		)

	var loaded: Variant = load(real)

	if not (loaded is PackedScene):
		return DotResult.fail(
			DotError.CODE_INVALID, "%s is not a scene." % path
		)

	_scenes[path] = loaded
	if shrink_textures_headless and DisplayServer.get_name() == "headless":
		_shrink(loaded as PackedScene, path)
	return DotResult.success(loaded)


## Whether a headless build swaps a loaded model's textures for 4x4 downsamples. The dummy renderer
## keeps a decoded copy of each texture it never draws (12 MB a rifle, 270 MB for the kit); the
## 4x4 is what AwViewArmsColour.texture_mean reads, so the glove fit is unchanged. False keeps them.
static var shrink_textures_headless := true


## Shrinks the textures of [param packed]'s materials in place (they are shared by every instance)
## and measures its bounds while the instance is at hand.
static func _shrink(packed: PackedScene, path: String) -> void:
	var node := packed.instantiate()
	var small := {}
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var mi := n as MeshInstance3D
		if mi == null:
			continue
		var mats: Array[Material] = [mi.material_override, mi.material_overlay]
		for i in mi.get_surface_override_material_count():
			mats.append(mi.get_surface_override_material(i))
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				mats.append(mi.mesh.surface_get_material(s))
		for mat in mats:
			while mat != null:
				_shrink_material(mat, small)
				mat = mat.next_pass
	if node is Node3D and not _bounds.has(path):
		var boxes: Array[AABB] = []
		_collect_bounds(node, Transform3D.IDENTITY, boxes)
		var box := AABB()
		for i in range(boxes.size()):
			box = boxes[i] if i == 0 else box.merge(boxes[i])
		_bounds[path] = box
	node.free()


static func _shrink_material(mat: Material, small: Dictionary) -> void:
	for prop in mat.get_property_list():
		if prop["type"] != TYPE_OBJECT:
			continue
		var tex := mat.get(prop["name"]) as Texture2D
		if tex == null or (tex.get_width() <= 4 and tex.get_height() <= 4):
			continue
		var key := tex.get_instance_id()
		if not small.has(key):
			var img := tex.get_image()
			if img == null or img.is_empty() or (img.is_compressed() and img.decompress() != OK):
				small[key] = tex
			else:
				img.resize(4, 4, Image.INTERPOLATE_BILINEAR)
				small[key] = ImageTexture.create_from_image(img)
		mat.set(prop["name"], small[key])


## True when [method scene] would find a file for [param path], here or under a fallback root.
static func exists(path: String) -> bool:
	return path != "" and ResourceLoader.exists(_locate(resolve(path)))


## [param real], or the same file under a fallback root when the build lacks it.
static func _locate(real: String) -> String:
	if _fallback_roots.is_empty() or not real.begins_with(ASSETS_BASE) or ResourceLoader.exists(real):
		return real
	var rel := real.substr(ASSETS_BASE.length())
	for root in _fallback_roots:
		if ResourceLoader.exists(root + "/" + rel):
			return root + "/" + rel
	return real


## Forgets the models that could not be found, and the empty boxes measured for them.
static func _drop_misses() -> void:
	for path: Variant in _complained.keys():
		_bounds.erase(path)
	_complained.clear()


## Loads every scene in [param paths] into the cache, so the first equip of each does not read
## its file (90-110 ms in the middle of a fight). Returns how many are cached.
static func warm(paths: Array) -> int:
	var cached := 0
	for path: Variant in paths:
		if scene(str(path)).ok:
			cached += 1
	return cached


## A fresh instance of the model at [param path], or null.
##
## [b]Returns null rather than failing loudly for a missing model[/b], because a missing
## mesh must not stop a weapon from working. The gun still fires, still costs
## ammunition and still kills; it is invisible, which is a visual bug and not a
## simulation one. It is logged once per path, at WARN, because somebody should
## eventually look.
static func instantiate(path: String) -> Node3D:
	var res := scene(path)

	if not res.ok:
		if not _complained.has(path):
			_complained[path] = true
			DotLog.warn(
				CHANNEL,
				"could not load a weapon model; the weapon will be invisible",
				{"path": path, "why": res.error.message}
			)
		return null

	var made: Node = (res.value as PackedScene).instantiate()

	if made is Node3D:
		return made

	# A .glb always instantiates as a Node3D. A .tscn a game substituted might not, and
	# adding a Control to a 3D rig is a crash several frames later rather than here.
	made.queue_free()
	DotLog.warn(
		CHANNEL, "a weapon model is not a Node3D and was discarded", {"path": path}
	)
	return null


## The merged bounding box of every mesh in the model, in the model's own space.
## Measured once per path.
## An empty box for a model that could not be loaded, which is the right answer: no mesh, no bounds, and a muzzle at the origin.
static func bounds(path: String) -> AABB:
	if _bounds.has(path):
		return _bounds[path]

	var box := AABB()
	var node := instantiate(path)

	if node != null:
		var boxes: Array[AABB] = []
		_collect_bounds(node, Transform3D.IDENTITY, boxes)
		for i in range(boxes.size()):
			box = boxes[i] if i == 0 else box.merge(boxes[i])
		node.queue_free()

	_bounds[path] = box
	return box


## Metres from the model origin to the far end of the mesh along [param forward].
##
## The end of the barrel on every model in this kit. Uses the bounding box corner that
## is furthest along the axis, so it is correct for a mesh centred on its origin and for
## one whose origin sits at the stock — which this kit contains one of.
static func muzzle_distance(path: String, forward: Vector3) -> float:
	var box := bounds(path)

	if box.size.length_squared() <= 0.0:
		return 0.0

	var axis := forward.normalized()
	var best := -INF

	for i in range(8):
		var corner := box.get_endpoint(i)
		best = maxf(best, corner.dot(axis))

	return maxf(0.0, best)


## Where the bore leaves the mesh, off the forward axis: the centre of the mesh within [member muzzle_face_depth] of
## its far end along [param forward], with the forward part taken out (model space, metres).
##
## [b]The kit's models are baked with the origin at the grip, below the bore[/b] (2 cm on the rifle, 11 on the
## revolver, 17 on the drum shotgun), and a muzzle placed along the axis through the origin put the flash and the
## tracer under the barrel. Measured once per model; zero for a model that cannot be loaded or has no mesh there.
static func muzzle_bore(path: String, forward: Vector3) -> Vector3:
	var axis := forward.normalized()
	if muzzle_face_depth <= 0.0 or not axis.is_normalized():
		return Vector3.ZERO
	var key := "%s|%s|%s" % [path, axis, muzzle_face_depth]
	if _bores.has(key):
		return _bores[key]
	var out := Vector3.ZERO
	var node := instantiate(path)
	if node != null:
		var points: Array[PackedVector3Array] = []
		_collect_vertices(node, Transform3D.IDENTITY, points)
		node.queue_free()
		var far := -INF
		for vs in points:
			for p in vs:
				far = maxf(far, p.dot(axis))
		var face := AABB()
		var seeded := false
		for vs in points:
			for p in vs:
				if p.dot(axis) >= far - muzzle_face_depth:
					face = AABB(p, Vector3.ZERO) if not seeded else face.expand(p)
					seeded = true
		if seeded:
			var c := face.get_center()
			out = c - axis * c.dot(axis)
	_bores[key] = out
	return out


## Every mesh surface's vertices under [param node], in the root's space.
static func _collect_vertices(node: Node, at: Transform3D, into: Array[PackedVector3Array]) -> void:
	var here := at
	if node is Node3D:
		here = at * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).visible:
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			for s in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(s)
				if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
					into.append(here * (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array))
	for child in node.get_children():
		_collect_vertices(child, here, into)


## Drops everything. For a test, and for a game unmounting content it will not remount.
static func clear() -> void:
	_scenes.clear()
	_bounds.clear()
	_bores.clear()
	_complained.clear()


## How many models are held. For a console command and the self-test.
static func describe() -> Dictionary:
	return {
		"scenes": _scenes.keys().size(),
		"measured": _bounds.keys().size(),
		"missing": _complained.keys().size(),
		"fallback_roots": _fallback_roots.size(),
	}


## Every mesh's bounding box, each already in the root's space.
##
## [b]Collected into a list and merged by the caller rather than merged as it goes.[/b]
## [method AABB.merge] with a default-constructed box does not give the other box back —
## it gives a box stretched to include the origin — so a model sitting entirely to one
## side of its origin measures as reaching the origin, and its muzzle comes out at the
## wrong end. Starting from the first real box instead is the whole fix, and it needs
## the boxes in hand to know which one is first.
static func _collect_bounds(node: Node, at: Transform3D, into: Array[AABB]) -> void:
	var here := at

	if node is Node3D:
		here = at * (node as Node3D).transform

	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			into.append(here * mesh.get_aabb())

	for child in node.get_children():
		_collect_bounds(child, here, into)
