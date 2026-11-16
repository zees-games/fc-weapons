class_name AwRocketJump
extends RefCounted

## The Rocketjump warhead: a weaker missile whose blast throws its own shooter. When a blast reaches the one who fired it,
## the server asks [method launch_velocity] for their new velocity and scales the hurt by [method self_damage_scale].
## Like the classic rocket jump: shoot at your feet as you jump, the blast adds speed away from it, bent toward where you jump,
## stronger in the air than on the floor, weaker the farther the body is from the blast.

## The def param the warhead sets.
const PARAM := &"rocketjump"
const ID := &"rocketjump"


static func is_rocketjump(def: DotWeaponDef) -> bool:
	return def != null and bool(def.params.get(PARAM, false))


## Multiplier on the damage a blast from [param def] deals the one who fired it; 1 for a plain missile.
static func self_damage_scale(def: DotWeaponDef, rules: AwRocketRules) -> float:
	return rules.jump_self_damage_scale if is_rocketjump(def) else 1.0


## The shooter's velocity after their own blast at [param blast_at]. [param center] is the middle of their body,
## [param move_dir] their move input (only its flat part counts), [param on_floor] whether they stood on the floor.
## Unchanged for a body outside the blast or a plain missile while `sv_rocket_plain_jump_scale` is 0.
static func launch_velocity(def: DotWeaponDef, rules: AwRocketRules, velocity: Vector3, center: Vector3, blast_at: Vector3, on_floor: bool, move_dir: Vector3) -> Vector3:
	var strength := 1.0 if is_rocketjump(def) else rules.plain_jump_scale
	var b: DotWeaponBallistics = def.tuning as DotWeaponBallistics if def != null else null
	if strength <= 0.0 or b == null or b.splash_radius <= 0.0:
		return velocity
	var dist := center.distance_to(blast_at)
	if dist >= b.splash_radius:
		return velocity
	var speed := rules.jump_speed * strength * (1.0 - dist / b.splash_radius)
	if on_floor:
		speed *= rules.jump_ground_scale
	var away := _unit(center - blast_at, Vector3.UP)
	var jump := _unit(_unit(Vector3(move_dir.x, 0.0, move_dir.z), Vector3.ZERO) + Vector3.UP * rules.jump_up, Vector3.ZERO)
	var dir := _unit(away + jump * rules.jump_steer, away)
	var out := velocity + dir * speed
	# A cap never slows someone already going faster than it.
	var cap := maxf(rules.jump_max_speed, velocity.length())
	if rules.jump_max_speed > 0.0 and out.length() > cap:
		out = out.normalized() * cap
	return out


static func _unit(v: Vector3, fallback: Vector3) -> Vector3:
	return v.normalized() if v.length() > 0.001 else fallback
