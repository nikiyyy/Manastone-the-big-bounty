class_name Stats
extends Resource

const NAMES := [
	"strength", "health",
	"agility", "haste", "dodge",
	"magic_power", "mana_pool", "luck",
	"charisma", "trade", "crafting",
]

const LABELS := {
	"strength": "Strength", "health": "Health",
	"agility": "Agility", "haste": "Haste", "dodge": "Dodge",
	"magic_power": "Magic power", "mana_pool": "Mana pool", "luck": "Luck",
	"charisma": "Charisma", "trade": "Trade", "crafting": "Crafting",
}

signal changed_stat(stat_name: String)

@export_group("Progression")
@export var available_points: int = 5
@export var talent_points: int = 0

@export_group("Physical")
@export var strength: int = 1
@export var health: int = 1

@export_group("Speed")
@export var agility: int = 1
@export var haste: int = 1      ## hexes of movement per combat turn
@export var dodge: int = 1

@export_group("Arcane")
@export var magic_power: int = 1
@export var mana_pool: int = 1
@export var luck: int = 1

@export_group("Social")
@export var charisma: int = 1
@export var trade: int = 1
@export var crafting: int = 1


## Hexes this unit can move in one turn.
func movement_per_turn() -> int:
	return haste


func can_raise() -> bool:
	return available_points > 0


func raise(stat_name: String) -> bool:
	if not can_raise() or not NAMES.has(stat_name):
		return false
	set(stat_name, get(stat_name) + 1)
	available_points -= 1
	changed_stat.emit(stat_name)
	return true
