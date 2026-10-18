class_name Effect
extends Resource
## A buff, curse, or instant change. Duration counts down at the start of the
## owner's turn; duration 0 means it resolves once and is never held.
 
enum Mode { ADD, SET, MULTIPLY }
 
@export var display_name: String = "Effect"
@export_multiline var description: String = ""
@export var duration: int = 3          ## the owner's turns; 0 = instant only
@export var is_curse: bool = false
@export var color: Color = Color(0.5, 0.85, 1.0)
 
@export_group("Modifier")
@export_enum("strength", "health", "agility", "haste", "dodge",
	"magic_power", "mana_pool", "luck", "charisma", "trade", "crafting")
var stat_name: String = "strength"
@export var amount: int = 0
@export var mode: Mode = Mode.ADD
 
@export_group("Instant")
## Applied once when the effect lands, regardless of duration.
@export var heal_min: int = 0
@export var heal_max: int = 0
 
 
## Layer this effect's contribution onto a stat's running value.
func apply_to(name_to_check: String, value: int) -> int:
	if name_to_check != stat_name or amount == 0:
		return value
	match mode:
		Mode.SET:
			return amount
		Mode.MULTIPLY:
			return int(value * float(amount))
		_:
			return value + amount
 
 
## Duration 0 means it fires once and is never held in the effect list.
func is_instant() -> bool:
	return duration <= 0
 
 
func heals() -> bool:
	return heal_max > 0 or heal_min > 0
 
 
func roll_heal() -> int:
	if heal_max <= heal_min:
		return heal_min
	return randi_range(heal_min, heal_max)
 
