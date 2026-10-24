class_name CodexEntry
extends Resource
## One wiki page. Hidden from the index entirely until its conditions pass —
## use that for topics the player shouldn't know exist yet, and gate a section
## instead when they should see the page but not all of it.

@export var id: StringName = ""
@export var title: String = ""
## Groups the index. "People", "Places", "History", whatever you like.
@export var category: String = "General"
## Shown under the title and searched against.
@export_multiline var summary: String = ""
@export var tint: Color = Color(0.70, 0.62, 0.95)

@export_group("Content")
@export var sections: Array[CodexSection] = []
## Listed at the foot of the page. Entries not yet discovered are skipped.
@export var related: Array[StringName] = []

@export_group("Gating")
## All must pass for this entry to appear at all. Empty means always known.
@export var conditions: Array[DialogueCondition] = []


func is_discovered(player) -> bool:
	for condition in conditions:
		if condition != null and not condition.is_met(null, player):
			return false
	return true


func has_been_read() -> bool:
	return Story.has_read(id)


func visible_sections(player) -> Array:
	var out: Array = []
	for section in sections:
		if section != null and section.is_visible(player):
			out.append(section)
	return out


## True when a gated section has opened up since the player last read this.
## Drives the "new information" marker in the index.
func has_unread_secret(player) -> bool:
	if not has_been_read():
		return false
	for section in sections:
		if section != null and section.is_secret and section.is_visible(player):
			if not Story.get_flag(_secret_flag(section)):
				return true
	return false


## Called by the reader once a secret section has actually been displayed.
func acknowledge_secrets(player) -> void:
	for section in sections:
		if section != null and section.is_secret and section.is_visible(player):
			Story.set_flag(_secret_flag(section), true)


func _secret_flag(section: CodexSection) -> StringName:
	return StringName("codex_secret:%s:%s" % [id, section.heading])


func matches(query: String) -> bool:
	if query.is_empty():
		return true
	var needle: String = query.to_lower()
	return title.to_lower().contains(needle) \
		or summary.to_lower().contains(needle) \
		or category.to_lower().contains(needle)
