class_name CharacterClass
extends Resource
## What a unit is. Skill trees and starting abilities will hang off this.

@export var display_name: String = "Adventurer"
@export_multiline var description: String = ""
@export var icon_color: Color = Color(0.7, 0.7, 0.7)

@export_group("Starting bonuses")
@export var bonus_strength: int = 0
@export var bonus_magic_power: int = 0
@export var bonus_mana_pool: int = 0

## Filled in when abilities exist.
@export var abilities: Array[Resource] = []
@export var spells: Array[Spell] = []
@export var talent_tree: TalentTree
