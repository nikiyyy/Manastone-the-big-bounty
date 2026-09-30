class_name Item
extends Resource

enum Slot { MAIN_HAND, OFF_HAND, RANGED, NONE }
enum Kind { WEAPON, ARMOR, CONSUMABLE, MISC }
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }
enum Hands { ONE_HANDED, TWO_HANDED }
enum Attack { MELEE, RANGED }

const RARITY_COLORS := {
	Rarity.COMMON: Color(0.75, 0.75, 0.72),
	Rarity.UNCOMMON: Color(0.35, 0.8, 0.4),
	Rarity.RARE: Color(0.3, 0.6, 0.95),
	Rarity.EPIC: Color(0.7, 0.4, 0.9),
	Rarity.LEGENDARY: Color(0.95, 0.7, 0.2),
}

@export var display_name: String = "Item"
@export_multiline var description: String = ""
@export var kind: Kind = Kind.MISC
@export var slot: Slot = Slot.NONE
@export var rarity: Rarity = Rarity.COMMON
@export var value: int = 0

@export_group("Weapon")
@export var hands: Hands = Hands.ONE_HANDED
@export var damage_min: int = 0
@export var damage_max: int = 0
@export var reach: int = 1          ## hexes; 1 = must be adjacent
@export var attack: Attack = Attack.MELEE
@export var is_light: bool = false
@export var crit_bonus: int = 10        ## percentage points, only if light
@export var damage_type: DamageType.Kind = DamageType.Kind.SLASHING

@export_group("Bonuses")
@export var stat_bonus: StatBonus

@export_group("Armor")
@export var armor_bonus: int = 0
@export var resistances: Resistances

func is_weapon() -> bool:
	return kind == Kind.WEAPON


## One damage roll from this weapon, before the wielder's strength.
func roll_damage() -> int:
	if damage_max <= damage_min:
		return damage_min
	return randi_range(damage_min, damage_max)


func rarity_color() -> Color:
	return RARITY_COLORS.get(rarity, RARITY_COLORS[Rarity.COMMON])


func tooltip() -> String:
	var lines: Array = [display_name]
	if is_weapon():
		var style: String = "ranged" if is_ranged() else "melee"
		lines.append("%d–%d %s damage, %s, reach %d" % [
			damage_min, damage_max, DamageType.label(damage_type).to_lower(), style, reach
		])
		if is_light:
			lines.append("Light  (+%d%% crit)" % crit_bonus)
	if armor_bonus > 0:
		lines.append("+%d armor" % armor_bonus)
	if resistances != null:
		for element in DamageType.ELEMENTS:
			var value: int = resistances.get_for(element)
			if value != 0:
				lines.append("+%d %s resist" % [value, DamageType.label(element).to_lower()])
	if stat_bonus != null:
		for line in stat_bonus.describe():
			lines.append(line)
	lines.append("%d gold" % value)
	return "\n".join(lines)


## The furthest this weapon can reach at all. Melee weapons can't exceed reach.
func max_range() -> int:
	if not is_ranged():
		return reach
	return 1 << 30

## Extra crit chance in percentage points from this weapon.
func crit_chance_bonus() -> int:
	return crit_bonus if is_light and is_weapon() else 0
	
## True when the target is past effective range but still inside max range.
func is_long_shot(distance: int) -> bool:
	return is_ranged() and distance > reach
	
func is_ranged() -> bool:
	return kind == Kind.WEAPON and attack == Attack.RANGED
