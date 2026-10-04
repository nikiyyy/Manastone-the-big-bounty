class_name FlatResistanceTalent
extends TalentEffect
## Adds flat elemental resistance, multiplied by rank.

@export var element: DamageType.Kind = DamageType.Kind.FIRE
@export var amount_per_rank: int = 5


func resistance_bonus(_unit, kind: int, rank: int) -> int:
	return amount_per_rank * rank if kind == element else 0


func describe(rank: int) -> String:
	return "+%d %s resistance" % [amount_per_rank * rank, DamageType.label(element).to_lower()]
