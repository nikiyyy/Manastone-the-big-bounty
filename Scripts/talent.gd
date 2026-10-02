class_name Talent
extends Resource
## One node in a class's talent tree.

@export var display_name: String = "Talent"
@export_multiline var description: String = ""
@export var max_ranks: int = 1
@export var icon_color: Color = Color(0.55, 0.45, 0.85)

@export_group("Layout")
## Grid position in the tree. Column 0-3, row 0 upward.
@export var column: int = 0
@export var row: int = 0

@export_group("Requirements")
## Must be fully ranked before this one unlocks. Leave empty for a root node.
@export var requires: Talent
@export var required_points: int = 0      ## points spent in this tree first
