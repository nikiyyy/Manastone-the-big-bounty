class_name TalentEffect
extends Resource
## Base class for what a talent actually does. Subclass it and override the
## hooks you need; everything returns zero by default, so a subclass only
## implements what it cares about.
##
## Every hook receives the rank, so scaling lives in the effect, not the unit.

## Added to a stat before active effects are layered on.
func stat_bonus(_unit, _stat_name: String, _rank: int) -> int:
	return 0


## Added to the unit's armor.
func armor_bonus(_unit, _rank: int) -> int:
	return 0


## Added to one elemental resistance.
func resistance_bonus(_unit, _kind: int, _rank: int) -> int:
	return 0


## One line for the tooltip, at the given rank. Empty means nothing to say.
func describe(_rank: int) -> String:
	return ""
