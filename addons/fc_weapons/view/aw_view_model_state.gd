@tool
extends Node3D

## State and constants of AwViewModel, split out for file size; no behaviour lives here.

var _source_art: AwWeaponVisual = null

var _aim_button_was: bool = false
var _arms: AwViewArms = null
var _light: DirectionalLight3D = null
var _animated: Node3D = null
var _aim_node: Node3D = null
var _holder: Node3D = null
var _weapon: Node3D = null
var _magazine: Node3D = null
## The scope glass of the equipped weapon (see aw_scope_glass.gd), or null: headless, or no scope.
var _scope_glass: Node3D = null
var _attachments: Array[Node3D] = []
var _sight: Node3D = null
## Rear aperture ring nodes of the weapon in hand (see aw_view_model.gd).
var _rear_rings: Array[Node3D] = []

## Weapons put away, built and ready ([code]aw_equip_cache.gd[/code]); [member cache_equips] says whether switching keeps them.
const EquipCache := preload("aw_equip_cache.gd")
var _equip_cache := EquipCache.new()
## The key the weapon in hand was built under, and what a fresh build of it looked like: set once [method equip] has built it all, "" otherwise (a prewarm, a half-built weapon).
var _build_key := ""
var _build_shape := {}
## True while [method equip] has put a kept build back instead of making one.
var _reused := false
## True inside [method prewarm]: what it builds is not kept in this view's own cache.
var _prewarming := false
## Builds a prewarm finished, kept for every view model of the process: a spare view under the loading cover builds them, and the
## player's own view takes one the first time it equips that weapon, so that equip is a put-back, not a 30-100 ms sight fit and cut.
## Keyed like [member _equip_cache], so a view whose rules or finish differ from the spare's never takes one. 0 limit: keeps every one.
static var prewarmed: RefCounted:
	get:
		if _prewarm_store == null:
			_prewarm_store = EquipCache.new()
			_prewarm_store.limit = prewarm_keep_limit
		return _prewarm_store
## How many prewarmed builds are kept (0 keeps every one); the oldest goes first.
static var prewarm_keep_limit: int = 0:
	set(value):
		prewarm_keep_limit = maxi(value, 0)
		prewarmed.limit = prewarm_keep_limit
## False: a prewarm drops its build, as before.
static var keep_prewarmed := true


## Made on first use, not at load: a script that holds an instance from load cannot be reloaded, which the parse pass does.
static var _prewarm_store: RefCounted = null

## The fitted attachments (what the rig was told) and what [code]aw_attachment_dress.gd[/code] drew for them.
var _fitting: GSWeaponFitting = null
## The key of the fitting the weapon in hand was last dressed with; [method set_fitting] with the same key redraws and refits nothing.
var _worn_key := ""
var _dressed: Dictionary = {}

## The iron sight's line, measured at equip in the holder's (model) space: `rear` and `front`
## on the line, or empty when the weapon aims at its written aim_offset. See gs_weapon_iron_sight.gd.
var _sight_line: Dictionary = {}

## The holder's transform at full aim when there is a sight line: the line through the eye.
var _sight_aim := Transform3D.IDENTITY

## The camera's near plane the eye relief keeps the gun's back end in front of, plus a margin
## for the kick pushing it back. A view model under no camera assumes Godot's default.
const NEAR_MARGIN := 0.05
## Metres beyond the camera near plane that no part of the drawn model may come nearer than.
const NEAR_CLEAR := 0.02

var _pose := AwWeaponPose.make()
var _wall := AwWallSlam.new()
var _wall_excluded: Array[RID] = []
var _art: AwWeaponVisual = null
var _id: StringName = &""

## Where the right and left hands go, in the Aim node's space, measured at equip.
var _grip_at := Vector3.ZERO
var _fore_at := Vector3.ZERO
## The support hand at full aim (the fore point before its raise onto the handguard); [member _fore_at] at the hip.
var _fore_aimed_at := Vector3.ZERO

## The axis of what each hand holds (a pistol grip, a fore-end, a handle), in the same space.
var _grip_axis := Vector3.UP
var _fore_axis := Vector3.FORWARD
var _grip_radius := 0.0

## Where the magazine sits at rest, in the Aim node's space (the well), or NAN-free zero
## with [member _has_well] false when the weapon has none.
var _well := Vector3.ZERO
var _has_well := false

## A round fed by hand from [member AwWeaponVisual.load_from], and its keys (`_build_feed_keys`):
## where its push starts, and the bolt's handle forward and drawn back, in the well's space.
var _feeds := false
var _entry := Vector3.ZERO
var _bolted := false
var _bolt := Vector3.ZERO
var _bolt_back := Vector3.ZERO
var _feed_keys: Array = []

## The share of a reload the rounds are fed in, and where in each round's share the hand has it
## at the start of its push and home. Matched by the fed weapons' keys (AwWeaponPose
## `RELOAD_KEYS_BOLT`, `_BREAK`, `_MUZZLE`), which hold the gun still across it.
const FEED_START := 0.26
const FEED_END := 0.70
const FEED_AT_ENTRY := 0.45
const FEED_AT_SEAT := 0.82

## Where a fed round is held from the palm: above it and to its right, between the fingertips,
## so the fist is below and beside the round rather than over it. Straight above the palm by
## 3.5 cm, the glove hid every round on the contact sheet.
const FEED_CARRY := Vector3(0.03, 0.06, 0.0)

## The last reload fraction handed in, for the hand that fetches the magazine.
var _reload_fraction: float = 0.0

## Where the muzzle sits in the weapon's own space, measured when the model was built.
var _muzzle := Vector3.ZERO

## The look angles last frame, so sway can be driven by how far the view moved.
var _last_look := Vector2.ZERO
var _look_seen := false

var _built: bool = false

## Posture for this frame, written by whoever drives the rig.
## Plain fields, because a remote player, bot or replay has no controller to ask; the default is standing still.
var _speed: float = 0.0
var _on_floor: bool = true
var _crouched: bool = false
var _look := Vector2.ZERO

## Sideways ground speed, m/s, positive to the right: handed in by [method drive], else
## measured from how this node moved between frames (a game that never heard of strafing
## still gets the tilt). NAN is "not handed in".
var _strafe_given: float = NAN
var _last_origin := Vector3.ZERO
var _origin_seen := false

## Whether the aim button is held, and how far the weapon has come up to the eye.
## Presentation only: never part of a command or a snapshot.
var _aim_held: bool = false
var _aim_fraction: float = 0.0

## The vertical field of view, in degrees, the hands are drawn at whatever the camera's is. 0 uses the camera's lens.
## Poses were set under 90 degrees; a different lens would make the same pose a different gun.
## Done by scaling X and Y by tan(camera/2)/tan(this/2) with Z alone, which is exact for a perspective projection and keeps depth sorting.
@export var hands_fov: float = 90.0

## How much of the size a narrower [member hands_fov] adds is given back by drawing the hands farther away, 0 to 1.
## 1 keeps the size at [constant REFERENCE_FOV]; wider than the reference pulls the hands in, never past [constant MAX_PULL_IN].
@export_range(0.0, 1.0, 0.05) var hands_depth_comp: float = 1.0

## The field of view the pack's poses were authored under, vertical degrees.
const REFERENCE_FOV := GSViewLens.REFERENCE_FOV
## The depth the gun's middle sits at under the reference lens, in metres.
const REFERENCE_DEPTH := GSViewLens.REFERENCE_DEPTH

## The share of a pose's sideways and upward move kept so it lands where it was authored under [constant REFERENCE_FOV]:
## a narrow [member hands_fov] drawn near ([member hands_depth_comp] 0) magnifies the gun and each move with it, and a
## sprint or wall move sent the gun off the screen and pulled the arms out straight. 1 with full depth compensation.
func lens_move_share() -> float:
	if not get_parent() is Camera3D:
		return 1.0
	var size := GSViewLens.lens_scale(REFERENCE_FOV, hands_fov)
	if size == 1.0:
		return 1.0
	var depth := REFERENCE_DEPTH + maxf((size - 1.0) * REFERENCE_DEPTH * hands_depth_comp, -GSViewLens.MAX_PULL_IN)
	return depth / (REFERENCE_DEPTH * size)

## The most the hands are drawn closer than authored, in metres.
const MAX_PULL_IN := GSViewLens.MAX_PULL_IN

## Seconds to blend the sprint carry in or out (smoothstepped); 0.2 hopped 0.2 m in three frames at 15 fps; 0.4 left sprint_fp view_pop at 0.189 (limit 0.15), 0.6 reads 0.124.
const SPRINT_SECONDS := 0.6

## Whether sprinting changes the pose (a game's cvar to turn it off).
var sprint_pose: bool = true

var _sprinting: bool = false
var _sprint: float = 0.0


## What a bolt or pump gun's cycle after a shot keeps: its clock and the part's move (the cycle itself runs in AwViewModel's core).
var _cycle_t := -1.0
var _cycle_wait := 0.0
var _cycle_len := 0.0
var _cycle_heard := 0
## How far the part is back and where the support hand stands on it this frame (in the hands' space), for [method _support_hand].
var _cycle_back := 0.0
var _cycle_shift := Vector3.ZERO
const CYCLE_WAIT := 0.12
const CYCLE_SPLIT: Array[float] = [0.4, 0.5, 1.0]
## The cycle of each style as {cue back, cue forward}: the sounds gs-audio ships.
## An empty list to default a lookup to (read only, so no default array is made per frame): a cycle style's cues, an optic's ocular.
const NO_CUES: Array = []
const CYCLE_CUES := {&"bolt": [&"bolt_back", &"bolt_fwd"], &"pump": [&"pump_back", &"pump_fwd"]}

## A cycled gun's part moved: the handling sound of the bolt or the pump, to play at the gun.
signal cycle_cue(cue: StringName, db: float)


## How far back the part is [param f] (0 to 1) through the cycle: drawn back by 40%, held to 50%, closed by the end.
static func cycle_back(f: float) -> float:
	if f <= 0.0 or f >= 1.0:
		return 0.0
	if f < CYCLE_SPLIT[0]:
		return smoothstep(0.0, CYCLE_SPLIT[0], f)
	if f < CYCLE_SPLIT[1]:
		return 1.0
	return 1.0 - smoothstep(CYCLE_SPLIT[1], CYCLE_SPLIT[2], f)


## How much of the support hand is on the cycled part [param f] (the cycle's own 0 to 1, below 0 before it starts): it reaches
## over the wait and the first twentieth, stays through the stroke, lets go over the last fifth.
static func cycle_reach(f: float, lead: float) -> float:
	if f >= 1.0:
		return 0.0
	var rise := smoothstep(-lead, 0.05, f)
	return rise * (1.0 - smoothstep(0.8, 1.0, f))
