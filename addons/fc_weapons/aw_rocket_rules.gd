class_name AwRocketRules
extends GSWeaponCvarRules

## Server cvars for the rocket launchers (`sv_rocket_*`): the single-missile launcher's tube and blast, and the
## Rocketjump warhead's damage and launch. [method apply] puts the launcher numbers on a def; [AwRocketJump] reads the rest.

var launcher_magazine: float = 1.0
var launcher_reserve: float = 12.0
var launcher_splash_radius: float = 5.5
var launcher_splash_damage: float = 88.0
var jump_damage_scale: float = 0.4
var jump_self_damage_scale: float = 0.0
var jump_speed: float = 14.0
var jump_ground_scale: float = 0.6
var jump_steer: float = 0.6
var jump_up: float = 1.0
var jump_max_speed: float = 24.0
var plain_jump_scale: float = 0.0


func fields() -> Dictionary:
	return {
		&"launcher_magazine": [1.0, 1.0, 1000000.0, "Missiles the single-missile launcher holds; it reloads after each"],
		&"launcher_reserve": [12.0, 0.0, 1000000.0, "Spare missiles the single-missile launcher spawns with"],
		&"launcher_splash_radius": [5.5, 0.0, 1000.0, "Blast radius of the single-missile launcher, metres"],
		&"launcher_splash_damage": [88.0, 0.0, 100000.0, "Blast damage at the centre for the single-missile launcher"],
		&"jump_damage_scale": [0.4, 0.0, 100.0, "Damage a Rocketjump missile deals to others, times the plain missile's"],
		&"jump_self_damage_scale": [0.0, 0.0, 100.0, "Damage a Rocketjump blast deals its own shooter, times what it deals others"],
		&"jump_speed": [14.0, 0.0, 1000.0, "Speed in m/s a point-blank Rocketjump blast adds to its shooter in the air"],
		&"jump_ground_scale": [0.6, 0.0, 100.0, "Launch speed times this when the shooter stands on the floor"],
		&"jump_steer": [0.6, 0.0, 100.0, "How far the launch bends from straight off the blast toward the jump direction"],
		&"jump_up": [1.0, 0.0, 100.0, "Upward share of the jump direction against the move input"],
		&"jump_max_speed": [24.0, 0.0, 100000.0, "Shooter speed after a launch is held under this; 0 = unlimited"],
		&"plain_jump_scale": [0.0, 0.0, 100.0, "Launch speed for a plain missile's self blast, times the Rocketjump's; 0 = none"],
	}


func prefix() -> String:
	return "sv_rocket"


## Puts the single-missile launcher's tube and blast on [param def] (params `rocket_tube` = single); others are left alone.
func apply(def: GSWeaponDef) -> void:
	if def == null or str(def.params.get(&"rocket_tube", "")) != "single":
		return
	def.magazine = int(launcher_magazine)
	def.reserve = int(launcher_reserve)
	def.reserve_max = maxi(def.reserve_max, def.reserve)
	var b := def.tuning as GSWeaponBallistics
	if b != null:
		b.splash_radius = launcher_splash_radius
		b.splash_damage = launcher_splash_damage
