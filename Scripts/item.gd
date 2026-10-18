class_name Item
extends Resource
## Anything that can sit in an inventory: weapons, armour, trinkets, potions.
 
enum Slot {
	MAIN_HAND,
	OFF_HAND,
	HELMET,
	NECKLACE,
	TORSO,
	RING_1,
	RING_2,
	HANDS,
	FEET,
	CHARM_1,
	CHARM_2,
	NONE,
}
 
enum Kind { WEAPON, ARMOR, CONSUMABLE, MISC }
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }
enum Hands { ONE_HANDED, TWO_HANDED }
enum Attack { MELEE, RANGED }
enum ArmorClass { NONE, LIGHT, MEDIUM, HEAVY }
enum UseMode { DRINK, THROW }
 
const RARITY_COLORS := {
	Rarity.COMMON: Color(0.75, 0.75, 0.72),
	Rarity.UNCOMMON: Color(0.35, 0.8, 0.4),
	Rarity.RARE: Color(0.3, 0.6, 0.95),
	Rarity.EPIC: Color(0.7, 0.4, 0.9),
	Rarity.LEGENDARY: Color(0.95, 0.7, 0.2),
}
 
const ARMOR_CLASS_LABELS := {
	ArmorClass.NONE: "",
	ArmorClass.LIGHT: "Light",
	ArmorClass.MEDIUM: "Medium",
	ArmorClass.HEAVY: "Heavy",
}
 
@export var display_name: String = "Item"
@export_multiline var description: String = ""
@export var kind: Kind = Kind.MISC
@export var slot: Slot = Slot.NONE
@export var rarity: Rarity = Rarity.COMMON
@export var value: int = 0
 
@export_group("Weapon")
@export var hands: Hands = Hands.ONE_HANDED
@export var attack: Attack = Attack.MELEE
@export var damage_type: DamageType.Kind = DamageType.Kind.SLASHING
@export var damage_min: int = 0
@export var damage_max: int = 0
@export var reach: int = 1          ## hexes; 1 = must be adjacent
@export var is_light: bool = false
@export var crit_bonus: int = 10    ## percentage points, only if light
 
@export_group("Armor")
@export var armor_class: ArmorClass = ArmorClass.NONE
@export var armor_bonus: int = 0
@export var resistances: Resistances
 
@export_group("Bonuses")
@export var stat_bonus: StatBonus
 
@export_group("Consumable")
@export var use_mode: UseMode = UseMode.DRINK
@export var effect: Effect
@export var consumed_on_use: bool = true
@export var throw_range: int = 5
@export var throw_radius: int = 0
 
@export_group("Projectile")
## Flies from user to target. Used by ranged weapons and thrown consumables.
@export var projectile_scene: PackedScene
 
 
func is_weapon() -> bool:
	return kind == Kind.WEAPON
 
 
func is_ranged() -> bool:
	return is_weapon() and attack == Attack.RANGED
 
 
func is_consumable() -> bool:
	return kind == Kind.CONSUMABLE
 
 
func is_thrown() -> bool:
	return is_consumable() and use_mode == UseMode.THROW
 
 
## One damage roll from this weapon, before the wielder's strength.
func roll_damage() -> int:
	if damage_max <= damage_min:
		return damage_min
	return randi_range(damage_min, damage_max)
 
 
## Ranged weapons can shoot any distance; melee is capped at reach.
func max_range() -> int:
	if not is_ranged():
		return reach
	return 1 << 30
 
 
## True when the target is past effective range — the shot still lands, weakly.
func is_long_shot(distance: int) -> bool:
	return is_ranged() and distance > reach
 
 
## Extra crit chance in percentage points from this weapon.
func crit_chance_bonus() -> int:
	return crit_bonus if is_light and is_weapon() else 0
 
 
func rarity_color() -> Color:
	return RARITY_COLORS.get(rarity, RARITY_COLORS[Rarity.COMMON])
 
 
func armor_class_name() -> String:
	return ARMOR_CLASS_LABELS.get(armor_class, "")
 
 
## A thrown consumable becomes a one-shot spell, so it can reuse the whole
## targeting pipeline rather than needing one of its own.
func to_spell() -> Spell:
	var s := Spell.new()
	s.display_name = display_name
	s.description = description
	s.mana_cost = 0
	s.cast_range = throw_range
	s.radius = throw_radius
	s.target_side = Spell.TargetSide.ANY
	s.damage_min = damage_min
	s.damage_max = damage_max
	s.damage_type = damage_type
	s.effect = effect
	s.scales_with_magic = false
	s.projectile_scene = projectile_scene
	return s
 
 
func tooltip() -> String:
	var lines: Array = [display_name]
 
	if is_weapon():
		var style: String = "ranged" if is_ranged() else "melee"
		lines.append("%d–%d %s damage, %s, reach %d" % [
			damage_min, damage_max, DamageType.label(damage_type).to_lower(), style, reach
		])
		if is_light:
			lines.append("Light  (+%d%% crit)" % crit_bonus)
		if hands == Hands.TWO_HANDED:
			lines.append("Two-handed")
 
	if is_consumable():
		lines.append("Thrown, range %d" % throw_range if is_thrown() else "Drink")
		if effect != null:
			if effect.heals():
				lines.append("Restores %d–%d health" % [effect.heal_min, effect.heal_max])
			if not effect.is_instant():
				lines.append("%s for %d turns" % [effect.display_name, effect.duration])
		if damage_max > 0:
			lines.append("%d–%d %s damage" % [
				damage_min, damage_max, DamageType.label(damage_type).to_lower()
			])
 
	if armor_bonus > 0 or armor_class != ArmorClass.NONE:
		var weight: String = armor_class_name()
		if weight.is_empty():
			lines.append("+%d armor" % armor_bonus)
		else:
			lines.append("+%d armor (%s)" % [armor_bonus, weight.to_lower()])
 
	if resistances != null:
		for element in DamageType.ELEMENTS:
			var amount: int = resistances.get_for(element)
			if amount != 0:
				lines.append("+%d %s resist" % [amount, DamageType.label(element).to_lower()])
 
	if stat_bonus != null:
		for line in stat_bonus.describe():
			lines.append(line)
 
	lines.append("%d gold" % value)
	return "\n".join(lines)
 
