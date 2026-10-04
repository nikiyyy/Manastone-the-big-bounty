class_name FlatStatTalent
extends TalentEffect
## Adds a flat amount to one stat, multiplied by rank.

@export_enum("strength", "health", "agility", "haste", "dodge",
	"magic_power", "mana_pool", "luck", "charisma", "trade", "crafting")
var stat_name: String = "strength"

@export var amount_per_rank: int = 1


func stat_bonus(_unit, which: String, rank: int) -> int:
	return amount_per_rank * rank if which == stat_name else 0


func describe(rank: int) -> String:
	return "%+d %s" % [amount_per_rank * rank, Stats.LABELS.get(stat_name, stat_name).to_lower()]
