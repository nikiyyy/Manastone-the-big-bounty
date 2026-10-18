class_name Spell
extends Resource
## A targeted spell. It can deal damage, apply an effect, or both.
## Radius 0 hits one hex; radius 1 hits a hex and its six neighbours.
 
enum TargetSide { ENEMIES, ALLIES, ANY }
 
@export var display_name: String = "Spell"
@export_multiline var description: String = ""
@export var mana_cost: int = 3
@export var cast_range: int = 6
@export var radius: int = 0
@export var target_side: TargetSide = TargetSide.ENEMIES
 
@export_group("Damage")
@export var damage_min: int = 0
@export var damage_max: int = 0
@export var damage_type: DamageType.Kind = DamageType.Kind.FIRE
## Off for thrown items, which don't care how clever the thrower is.
@export var scales_with_magic: bool = true
 
@export_group("Effect")
@export var effect: Effect
 
@export_group("Projectile")
@export var projectile_scene: PackedScene
 
 
func deals_damage() -> bool:
	return damage_max > 0 or damage_min > 0
 
 
func roll_damage() -> int:
	if damage_max <= damage_min:
		return damage_min
	return randi_range(damage_min, damage_max)
 
 
## Should this spell touch a unit, given which side each is on?
func affects(caster_is_player: bool, unit_is_player: bool) -> bool:
	match target_side:
		TargetSide.ALLIES:
			return caster_is_player == unit_is_player
		TargetSide.ENEMIES:
			return caster_is_player != unit_is_player
		_:
			return true
 
