class_name CodexSection
extends Resource
## One block of a codex entry. Gated sections stay invisible until their
## conditions pass, so an entry can grow as the player learns things.
##
## Conditions are the same DialogueCondition resources dialogue uses, so a
## secret revealed by a conversation is a flag on one side and a section on
## the other, with no new gating code.

@export var heading: String = ""
## BBCode. Link other entries with [url=entry_id]display text[/url] — the
## reader colours them and makes them clickable.
@export_multiline var text: String = ""

@export_group("Gating")
@export var conditions: Array[DialogueCondition] = []
## Mark a late-revealed section so the reader can flag it as new information.
@export var is_secret: bool = false


## Codex conditions have no NPC to talk about, so anything that asks about one
## (IS_FOLLOWING, IS_MERCHANT, FACTION_IS) is simply false here.
func is_visible(player) -> bool:
	for condition in conditions:
		if condition != null and not condition.is_met(null, player):
			return false
	return true
