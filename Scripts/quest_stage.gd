class_name QuestStage
extends Resource
## One step of a quest. When every non-optional objective is done the stage
## runs its on_complete actions and the quest moves to `next` — which is how
## "investigate the ruin" turns into "now deal with what's inside" without
## any special-case code.

@export var id: StringName = "start"
## The current instruction, shown above the objectives.
@export_multiline var text: String = ""
@export var objectives: Array[QuestObjective] = []
## Stage to move to when this one completes. Empty finishes the quest.
@export var next: StringName = ""

@export_group("Effects")
## Run when the stage becomes current — spawn something, set a flag, open a door.
@export var on_enter: Array[DialogueAction] = []
## Run the moment its objectives are satisfied.
@export var on_complete: Array[DialogueAction] = []


func objective(id_to_find: StringName) -> QuestObjective:
	for o in objectives:
		if o != null and o.id == id_to_find:
			return o
	return null
