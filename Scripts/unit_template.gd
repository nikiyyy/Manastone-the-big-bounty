class_name UnitTemplate
extends Resource
## A reusable enemy archetype. Save one as a .tres and drop it into any NPC's
## party; each instance gets its own copy of the stats at spawn time.

@export var display_name: String = "Soldier"
@export_range(1, 12) var count: int = 1
@export var stats: Stats
@export var ai: CombatAI
@export var character_class: CharacterClass
@export var level: int = 1
@export var base_armor: int = 0
@export var base_resistances: Resistances

@export_group("Loadout")
## Equipped automatically on spawn, into each item's own slot.
@export var loadout: Array[Item] = []
@export var spells: Array[Spell] = []

@export_group("Rewards")
@export var xp_reward: int = 10
@export var gold_min: int = 0
@export var gold_max: int = 0
## Dropped on death, once loot exists.
@export var loot: Array[Item] = []
@export_range(0.0, 1.0) var loot_chance: float = 0.5

@export_group("Appearance")
## Overrides npc.tscn when this archetype gets its own model.
@export_file("*.tscn") var scene_override: String = ""


func roll_gold() -> int:
	if gold_max <= gold_min:
		return gold_min
	return randi_range(gold_min, gold_max)


## Everything the battle map needs to build one combatant from this template.
func to_member(index: int) -> Dictionary:
	return {
		"display_name": display_name if count == 1 else "%s %d" % [display_name, index + 1],
		"stats": stats,
		"ai": ai,
		"character_class": character_class,
		"level": level,
		"base_armor": base_armor,
		"base_resistances": base_resistances,
		"loadout": loadout,
		"spells": spells,
		"xp_reward": xp_reward,
		"gold": roll_gold(),
		"scene_override": scene_override,
	}
