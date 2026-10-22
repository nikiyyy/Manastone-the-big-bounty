class_name DialogueNode
extends Resource
## One thing the NPC says, plus what you can say back.

@export var id: StringName = "start"
@export_multiline var text: String = ""
## Overrides the NPC's name in the header — for a narrator line, or someone
## else cutting in.
@export var speaker: String = ""
@export var choices: Array[DialogueChoice] = []

@export_group("Effects")
## Run as soon as this node is shown. Use for affinity shifts that happen
## just from reaching a branch, or for setting a "has met" flag.
@export var on_enter: Array[DialogueAction] = []
