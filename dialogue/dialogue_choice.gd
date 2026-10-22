class_name DialogueChoice
extends Resource
## One option the player can pick. Offered only if every condition passes.

@export_multiline var text: String = "..."
## Node to jump to. Empty ends the conversation.
@export var next: StringName = ""

@export_group("Gating")
@export var conditions: Array[DialogueCondition] = []
## Show it greyed out with a hint instead of hiding it, so the player can see
## what they're missing. Good for skill checks, bad for secrets.
@export var show_when_locked: bool = false
@export var locked_hint: String = ""
## Set a flag when picked, and hide the choice once that flag is set.
## Leave empty for a choice that can be picked repeatedly.
@export var once_flag: StringName = ""

@export_group("Effects")
@export var actions: Array[DialogueAction] = []


func is_available(npc, player) -> bool:
	if not once_flag.is_empty() and Story.get_flag(once_flag):
		return false
	for condition in conditions:
		if condition != null and not condition.is_met(npc, player):
			return false
	return true


## True when the only thing stopping it is a condition, not the once-flag —
## those are the ones worth showing greyed out.
func is_locked_but_visible(npc, player) -> bool:
	if not show_when_locked:
		return false
	if not once_flag.is_empty() and Story.get_flag(once_flag):
		return false
	return not is_available(npc, player)


## Why it's locked, for the tooltip.
func lock_reason(npc, player) -> String:
	if not locked_hint.is_empty():
		return locked_hint
	for condition in conditions:
		if condition != null and not condition.is_met(npc, player):
			var line: String = condition.describe()
			if not line.is_empty():
				return line
	return "Unavailable"
