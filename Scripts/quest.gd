class_name Quest
extends Resource
## A whole quest. Save these as .tres files in res://quests/ and the log picks
## them up — no central list to maintain.
##
## Quests are given out and handed in through dialogue: a choice with a
## START_QUEST action begins one, a choice with COMPLETE_QUEST ends it, and
## the QUEST_* conditions decide when those choices are offered. Nothing here
## knows about NPCs.

@export var id: StringName = ""
@export var title: String = "Untitled quest"
## Groups the log, the way WoW groups by zone.
@export var category: String = "Quests"
@export var level: int = 1
## The giver's pitch, shown under the objectives.
@export_multiline var description: String = ""

@export var stages: Array[QuestStage] = []

@export_group("Turn in")
## Off — the default — means the quest sits in the log marked complete until a
## dialogue choice hands it in. Turn it on for a quest with nobody to report
## back to, which then pays out the moment its last objective is done.
@export var auto_complete: bool = false
## Shown in the log once every objective is done: "Return to Kael in Riverside."
@export var turn_in_hint: String = ""
@export var repeatable: bool = false

@export_group("Rewards")
@export var xp_reward: int = 0
@export var gold_reward: int = 0
@export var item_rewards: Array[Item] = []
## Anything the three fields above don't cover — affinity, flags, a stat point.
@export var extra_rewards: Array[DialogueAction] = []


func stage(stage_id: StringName) -> QuestStage:
	for s in stages:
		if s != null and s.id == stage_id:
			return s
	return null


func first_stage() -> QuestStage:
	return stages[0] if not stages.is_empty() else null


## True when finishing the objectives isn't enough and someone has to be told.
func needs_turn_in() -> bool:
	return not auto_complete


## Readable reward lines for the log panel.
func reward_lines() -> Array:
	var lines: Array = []
	if xp_reward > 0:
		lines.append("%d experience" % xp_reward)
	if gold_reward > 0:
		lines.append("%d gold" % gold_reward)
	for item in item_rewards:
		if item != null:
			lines.append(item.display_name)
	return lines
