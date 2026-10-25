@tool
class_name QuestTrigger
extends Area3D
## An invisible patch of world that tells the quest log the player arrived.
## Drop one wherever a REACH objective points, give it a matching Location id,
## and add a CollisionShape3D child to say how big it is.

## Matches a QuestObjective of kind REACH whose target is this id.
@export var location_id: StringName = ""
## Fire once and then stop listening. Turn off for a doorway you cross often.
@export var once: bool = true
## A flag set the first time the player walks in — handy for dialogue and the
## codex, which can then react to places the player has been.
@export var flag_on_enter: StringName = ""

## Extra things to run on entry, using the same vocabulary as dialogue.
@export var on_enter: Array[DialogueAction] = []

var _fired: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	# the player is on the unit layer, so only watch that one
	collision_layer = 0
	set_collision_mask_value(1, false)
	set_collision_mask_value(2, true)
	monitoring = true
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if _fired and once:
		return
	if body != Game.player:
		return

	_fired = true

	if not location_id.is_empty():
		Quests.notify_location(location_id)
	if not flag_on_enter.is_empty():
		Story.set_flag(flag_on_enter, true)
	for action in on_enter:
		if action != null:
			action.run(null, body, null)


## Saved alongside the rest of the world so a one-shot trigger stays spent.
func save_state() -> Dictionary:
	return {"fired": _fired}


func load_state(data: Dictionary) -> void:
	_fired = data.get("fired", false)
