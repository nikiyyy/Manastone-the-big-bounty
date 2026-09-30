class_name StatBonus
extends Resource
## Flat stat additions from a single item. Every field is a bonus, never a
## replacement — they sum across equipped gear.

@export var strength: int = 0
@export var health: int = 0
@export var agility: int = 0
@export var haste: int = 0
@export var dodge: int = 0
@export var magic_power: int = 0
@export var mana_pool: int = 0
@export var luck: int = 0
@export var charisma: int = 0
@export var trade: int = 0
@export var crafting: int = 0


func get_for(stat_name: String) -> int:
	return get(stat_name) if stat_name in self else 0


func is_empty() -> bool:
	for stat_name in Stats.NAMES:
		if get_for(stat_name) != 0:
			return false
	return true


## Human-readable lines for tooltips, one per non-zero bonus.
func describe() -> Array:
	var lines: Array = []
	for stat_name in Stats.NAMES:
		var value: int = get_for(stat_name)
		if value != 0:
			lines.append("%+d %s" % [value, Stats.LABELS[stat_name].to_lower()])
	return lines
