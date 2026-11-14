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

## Art only — the unit stays a normal NPC and its coloured capsule is simply
## hidden in favour of this. Leave it empty and the capsule is used, so an
## archetype with no art yet still shows up. Use scene_override instead only
## when the whole NPC scene needs to differ, not just how it looks.
@export var model: PackedScene
## Imported models arrive at whatever size the program that made them chose,
## so this range runs wide.
@export_range(0.05, 50.0, 0.05) var model_scale: float = 1.0
## Turns the model on the spot. Y straightens a model whose front doesn't face
## the way the unit walks; X and Z stand up one that was exported lying down.
@export var model_rotation_degrees: Vector3 = Vector3.ZERO
## Nudge up or down after the automatic drop to ground level.
@export var model_y_offset: float = 0.0


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
		"model": model,
		"model_scale": model_scale,
		"model_rotation_degrees": model_rotation_degrees,
		"model_y_offset": model_y_offset,
	}
