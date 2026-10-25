class_name QuestObjective
extends Resource
## One line in the quest log. Two flavours:
##
## Counted  (KILL, REACH, TALK) tick up when the game tells the log something
##          happened, and the count is stored.
## Derived  (COLLECT, FLAG, COUNTER) are recomputed from the world whenever
##          the log refreshes, so they can't drift — drop a quest item and the
##          objective un-ticks itself.

enum Kind { KILL, COLLECT, REACH, TALK, FLAG, COUNTER, CUSTOM }

@export var id: StringName = ""
## Shown in the log. Leave empty to build one from kind and target.
@export var description: String = ""
@export var kind: Kind = Kind.KILL
## Enemy quest tag, item name, location id, flag name or counter name,
## depending on the kind.
@export var target: StringName = ""
@export var required: int = 1
## Doesn't block the stage from completing.
@export var optional: bool = false
## Stays out of the log until it's done — for beats you don't want telegraphed.
@export var hidden_until_done: bool = false


## Derived objectives are read from the world instead of counted up.
func is_derived() -> bool:
	return kind == Kind.COLLECT or kind == Kind.FLAG or kind == Kind.COUNTER


func derived_progress(player) -> int:
	match kind:
		Kind.COLLECT:
			return _count_carried(player)
		Kind.FLAG:
			return required if Story.get_flag(target) else 0
		Kind.COUNTER:
			return Story.get_counter(target)
		_:
			return 0


func _count_carried(player) -> int:
	if player == null or not "inventory" in player or player.inventory == null:
		return 0
	var total: int = 0
	for item in player.inventory.items:
		if item != null and item.display_name == String(target):
			total += 1
	for item in player.inventory.equipped.values():
		if item != null and item.display_name == String(target):
			total += 1
	return total


func is_done(progress: int) -> bool:
	return progress >= required


## "Witherbark Tusk: 3/10", or just the text when there's only one of a thing.
func label(progress: int) -> String:
	var text: String = description if not description.is_empty() else _default_text()
	if required <= 1:
		return text
	return "%s: %d/%d" % [text, mini(progress, required), required]


func _default_text() -> String:
	match kind:
		Kind.KILL:
			return "Defeat %s" % target
		Kind.COLLECT:
			return String(target)
		Kind.REACH:
			return "Travel to %s" % target
		Kind.TALK:
			return "Speak to %s" % target
		_:
			return String(target)
