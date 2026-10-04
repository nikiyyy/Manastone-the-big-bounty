class_name StatToArmorTalent
extends TalentEffect
## Converts a percentage of one stat into armor. Rounded up.

@export_enum("strength", "health", "agility", "haste", "dodge",
	"magic_power", "mana_pool", "luck", "charisma", "trade", "crafting")
var source_stat: String = "health"

@export var percent_per_rank: int = 10


func armor_bonus(unit, rank: int) -> int:
	if unit == null or not unit.has_method("modified_stat"):
		return 0
	var source: int = unit.modified_stat(source_stat)
	return int(ceil(source * float(percent_per_rank * rank) / 100.0))


func describe(rank: int) -> String:
	return "Gain %d%% of your %s as armor" % [
		percent_per_rank * rank, Stats.LABELS.get(source_stat, source_stat).to_lower()
	]
