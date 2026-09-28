class_name Damage
extends RefCounted
## Central damage maths. Everything that deals damage routes through here.

## Tuned so 100 armor = 75% reduction. Raise it to make armor weaker.
const ARMOR_CONSTANT := 33.333333
const CRIT_CAP := 75            ## percentage points
const CRIT_MULTIPLIER := 2.0

## Fraction of incoming damage that gets through, 0.25 at 100 armor.
static func multiplier(armor: int) -> float:
	if armor <= 0:
		return 1.0
	return ARMOR_CONSTANT / (ARMOR_CONSTANT + float(armor))


## Damage after armor, rounded up, never below 1 for a hit that connected.
static func apply_armor(raw: int, armor: int) -> int:
	if raw <= 0:
		return 0
	return maxi(1, int(ceil(raw * multiplier(armor))))

## Damage after whichever defence applies: armor for physical types,
## the matching elemental resistance for the rest.
static func mitigate(raw: int, target, kind: int) -> int:
	return apply_armor(raw, defence_against(target, kind))

## The defence value that a given damage type is reduced by.
static func defence_against(target, kind: int) -> int:
	if target == null:
		return 0
	if DamageType.is_elemental(kind):
		return target.resistance_to(kind) if target.has_method("resistance_to") else 0
	return armor_of(target)
	
static func armor_of(unit) -> int:
	return unit.armor() if unit != null and unit.has_method("armor") else 0
## Crit chance in percent: one point per agility, plus a light weapon's bonus.

static func crit_chance(attacker, weapon: Item) -> int:
	var agility: int = 0
	if attacker != null and attacker.has_method("modified_stat"):
		agility = attacker.modified_stat("agility")
	elif attacker != null and "stats" in attacker and attacker.stats != null:
		agility = attacker.stats.agility
	var bonus: int = weapon.crit_chance_bonus() if weapon != null else 0
	return clampi(agility + bonus, 0, CRIT_CAP)


static func rolls_crit(attacker, weapon: Item) -> bool:
	return randi_range(1, 100) <= crit_chance(attacker, weapon)


static func apply_crit(raw: int) -> int:
	return int(ceil(raw * CRIT_MULTIPLIER))
