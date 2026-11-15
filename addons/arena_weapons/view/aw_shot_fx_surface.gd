extends "aw_shot_fx_flash.gd"

## What a shot landing on something is drawn and heard as (body or world, mark or none, which surface
## sound), split out of [AwShotFx] for file size. Behaviour lives in [AwShotFx], which extends this.

## Put a node in this group to have a shot that lands on it drawn as a hit on a body (a red
## burst, no mark), whatever its class. A character, a ragdoll's bone and this group are bodies.
const BODY_GROUP := &"aw_body"

## Put a node in this group to have it never drawn as a body, even if it is a character: a game
## where what was hit must not be given away by the impact (a disguised player).
const NOT_BODY_GROUP := &"aw_not_body"

## Put a node in this group to have a shot that lands on it draw no impact at all (no mark, spark
## or puff): a map's sky. A collider whose meta hull_kind is "sky" counts too, as map imports tag it.
const NO_IMPACT_GROUP := &"aw_no_impact"

## What a presentation ray's collider is, for [method impact_kind].
const IMPACT_WORLD := &"world"
const IMPACT_BODY := &"body"

## Each sound class's round: tracer [code]width[/code] per metre of distance (see _screen_width), streak
## [code]length[/code] and impact size [code]hit[/code] as multipliers. One width for every gun made a pistol's
## shot as thick as a sniper's; a class not listed draws the rifle's ([constant ROUND_DEFAULT]).
const ROUNDS := {
	&"light": {"width": 0.0028, "length": 0.8, "hit": 0.8},
	&"suppressed": {"width": 0.0022, "length": 0.7, "hit": 0.75},
	&"derringer": {"width": 0.003, "length": 0.75, "hit": 0.85},
	&"mpistol": {"width": 0.0026, "length": 0.8, "hit": 0.8},
	&"smg": {"width": 0.003, "length": 0.85, "hit": 0.85},
	&"magnum": {"width": 0.0046, "length": 1.0, "hit": 1.2},
	&"rifle": {"width": 0.004, "length": 1.0, "hit": 1.0},
	&"carbine": {"width": 0.0038, "length": 0.95, "hit": 0.95},
	&"battle": {"width": 0.0047, "length": 1.1, "hit": 1.1},
	&"marksman": {"width": 0.005, "length": 1.25, "hit": 1.15},
	&"heavy": {"width": 0.0052, "length": 1.15, "hit": 1.2},
	&"lmg": {"width": 0.0046, "length": 1.1, "hit": 1.05},
	&"minigun": {"width": 0.0036, "length": 1.0, "hit": 0.9},
	&"sniper": {"width": 0.0068, "length": 1.6, "hit": 1.4},
	&"shotgun": {"width": 0.0022, "length": 0.55, "hit": 0.6},
	&"autoshot": {"width": 0.0022, "length": 0.55, "hit": 0.6},
}
const ROUND_DEFAULT := {"width": 0.004, "length": 1.0, "hit": 1.0}

## Stock impact per surface (dot-audio's [code]surface_of_collider[/code] names it); others play [code]impact[/code].
const SURFACE_IMPACTS := {&"metal": &"impact_metal", &"wood": &"impact_wood"}

## Read by path, so the pack needs no dot-audio; without it every surface sounds the same.
const SURFACE_PROBE := "res://addons/dot_audio/runtime/dot_audio_footsteps.gd"


## What a shot landing on [param collider] is drawn as: [constant IMPACT_BODY] for a character,
## a ragdoll's bone or a node in [constant BODY_GROUP]; otherwise [constant IMPACT_WORLD].
static func impact_kind(collider: Object) -> StringName:
	var node := collider as Node
	if node == null:
		return IMPACT_WORLD
	if node.is_in_group(NOT_BODY_GROUP):
		return IMPACT_WORLD
	if node is CharacterBody3D or node is PhysicalBone3D or node.is_in_group(BODY_GROUP):
		return IMPACT_BODY
	return IMPACT_WORLD


## Whether a shot landing on [param collider] may leave a mark: only on what never moves. A mark
## is placed in world space and would hang in the air where a crate or a door used to be.
static func takes_marks(collider: Object) -> bool:
	if collider == null:
		return false
	if collider is RigidBody3D or collider is CharacterBody3D or collider is AnimatableBody3D \
			or collider is PhysicalBone3D:
		return false
	# By class name, not by type: a build without the CSG or GridMap module must still parse this.
	return collider is StaticBody3D or collider.is_class("CSGShape3D") or collider.is_class("GridMap")


## Whether a shot landing on [param collider] draws an impact at all: not on the sky (a node in
## [constant NO_IMPACT_GROUP] or one whose meta hull_kind is "sky"). Only the picture: the shot hit.
static func draws_impact(collider: Object) -> bool:
	var node := collider as Node
	if node == null:
		return true
	if node.is_in_group(NO_IMPACT_GROUP):
		return false
	return str(node.get_meta(&"hull_kind", "")) != "sky"


## The tracer and impact sizes of [param weapon_class] (an AwWeaponSound class): [constant ROUNDS], else the rifle's.
static func round_profile(weapon_class: StringName) -> Dictionary:
	return ROUNDS.get(weapon_class, ROUND_DEFAULT)


## The stock impact for what [param kind] and [param collider] are made of, or null without dot-audio.
static func impact_stream(kind: StringName, collider: Object = null, shape: int = -1) -> AudioStream:
	var sound: StringName = &"impact_flesh" if kind == IMPACT_BODY \
		else SURFACE_IMPACTS.get(surface_of(collider, shape), &"impact")
	var picked := DotWeaponSound.pick(sound, randi())
	return picked if picked != null else DotWeaponSound.pick(&"impact", randi())


## What [param collider] is made of as dot-audio names it (metal, wood, ...), empty without dot-audio or a tag.
static func surface_of(collider: Object, shape: int = -1) -> StringName:
	if collider == null or not is_instance_valid(collider) or not ResourceLoader.exists(SURFACE_PROBE):
		return &""
	var probe: Script = load(SURFACE_PROBE)
	return StringName(probe.call(&"surface_of_collider", collider, shape))
