extends Node
## Autoload "Quests". Owns both the catalogue of quest definitions and the
## player's progress through them.
##
## Quest .tres files dropped into res://quests/ are found automatically, so
## there's no central list to keep in step with the folder.

signal quest_started(quest_id: StringName)
signal quest_advanced(quest_id: StringName, stage_id: StringName)
signal objective_progressed(quest_id: StringName, objective_id: StringName, now: int, required: int)
## Every objective is done but the player still has to report back.
signal quest_ready(quest_id: StringName)
signal quest_completed(quest_id: StringName)
signal quest_abandoned(quest_id: StringName)

const QUEST_FOLDER := "res://quests"
## Prints every start, tick, stage change and completion to the Output panel.
## Leave it on while you're authoring quests — a quest that misbehaves almost
## always does so in one visible line. Turn it off before you ship.
const VERBOSE := true

## quest_id -> { "stage": StringName, "progress": { objective_id: int } }
var active: Dictionary = {}
## quest_id -> how many times it's been finished
var completed: Dictionary = {}

var _catalog: Dictionary = {}      # StringName -> Quest
var _ordered: Array = []
var _loaded: bool = false

# ----------------------------------------------------------------- catalogue

func quest(quest_id: StringName) -> Quest:
	_load()
	return _catalog.get(quest_id)


func all_quests() -> Array:
	_load()
	return _ordered


func reload() -> void:
	_loaded = false
	_load()


func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_catalog.clear()
	_ordered.clear()

	var dir := DirAccess.open(QUEST_FOLDER)
	if dir == null:
		push_warning("Quests: no folder at %s" % QUEST_FOLDER)
		return

	for file_name in dir.get_files():
		# exported projects rename .tres to .remap
		var clean: String = file_name.trim_suffix(".remap")
		if not clean.ends_with(".tres") and not clean.ends_with(".res"):
			continue
		var res = load(QUEST_FOLDER.path_join(clean))
		if res is Quest and not res.id.is_empty() and not _catalog.has(res.id):
			_catalog[res.id] = res
			_ordered.append(res)

	_ordered.sort_custom(func(a, b):
		if a.category != b.category:
			return a.category.naturalnocasecmp_to(b.category) < 0
		return a.level < b.level
	)

# --------------------------------------------------------------------- state

func is_active(quest_id: StringName) -> bool:
	return active.has(quest_id)


func is_completed(quest_id: StringName) -> bool:
	return completed.get(quest_id, 0) > 0


func is_started(quest_id: StringName) -> bool:
	return is_active(quest_id) or is_completed(quest_id)


func current_stage_id(quest_id: StringName) -> StringName:
	return active.get(quest_id, {}).get("stage", &"")


func current_stage(quest_id: StringName) -> QuestStage:
	var q: Quest = quest(quest_id)
	if q == null or not is_active(quest_id):
		return null
	return q.stage(current_stage_id(quest_id))


func active_quests() -> Array:
	var out: Array = []
	for quest_id in active.keys():
		var q: Quest = quest(quest_id)
		if q != null:
			out.append(q)
	out.sort_custom(func(a, b):
		if a.category != b.category:
			return a.category.naturalnocasecmp_to(b.category) < 0
		return a.level < b.level
	)
	return out

# ------------------------------------------------------------------ progress

func progress_of(quest_id: StringName, objective_id: StringName) -> int:
	return active.get(quest_id, {}).get("progress", {}).get(objective_id, 0)


## Counted objectives read their stored tally; derived ones are recomputed.
func objective_progress(quest_id: StringName, objective: QuestObjective) -> int:
	if objective == null:
		return 0
	if objective.is_derived():
		return objective.derived_progress(_player())
	return progress_of(quest_id, objective.id)


func is_objective_done(quest_id: StringName, objective: QuestObjective) -> bool:
	return objective != null and objective.is_done(objective_progress(quest_id, objective))


## True when every non-optional objective of the current stage is satisfied.
func is_stage_done(quest_id: StringName) -> bool:
	var stage: QuestStage = current_stage(quest_id)
	if stage == null:
		return false
	for objective in stage.objectives:
		if objective == null or objective.optional:
			continue
		if not is_objective_done(quest_id, objective):
			return false
	return true


## The last stage is finished and the player owes someone a conversation.
## This is what a QUEST_READY dialogue condition reads.
func is_ready_to_turn_in(quest_id: StringName) -> bool:
	if not is_active(quest_id):
		return false
	var q: Quest = quest(quest_id)
	if q == null or not q.needs_turn_in():
		return false
	var stage: QuestStage = current_stage(quest_id)
	return stage != null and stage.next.is_empty() and is_stage_done(quest_id)


## Can this quest be picked up at all right now? What a QUEST_NOT_STARTED
## condition is really asking, allowing for repeatables.
func can_start(quest_id: StringName) -> bool:
	var q: Quest = quest(quest_id)
	if q == null or is_active(quest_id):
		return false
	return q.repeatable or not is_completed(quest_id)

# ------------------------------------------------------------------ lifecycle

func start(quest_id: StringName) -> bool:
	var q: Quest = quest(quest_id)
	if q == null:
		push_warning("Quests: no quest '%s'" % quest_id)
		return false
	if is_active(quest_id):
		return false
	if is_completed(quest_id) and not q.repeatable:
		return false

	var first: QuestStage = q.first_stage()
	if first == null:
		push_warning("Quests: '%s' has no stages" % quest_id)
		return false

	# An objective-less first stage is satisfied the moment it begins, so the
	# quest would start and finish in the same breath. Almost always a stage
	# whose Objectives array never got filled in.
	if first.objectives.is_empty():
		push_warning("Quests: '%s' stage '%s' has no objectives — it will complete immediately." % [quest_id, first.id])

	active[quest_id] = {"stage": first.id, "progress": {}}
	_log("started '%s' at stage '%s'" % [quest_id, first.id])
	quest_started.emit(quest_id)
	_run(first.on_enter)
	refresh()
	return true


## Only reachable from an ABANDON_QUEST dialogue action — there's no button
## for it, so dropping a quest is something a conversation does on purpose.
func abandon(quest_id: StringName) -> bool:
	if not is_active(quest_id):
		return false
	active.erase(quest_id)
	_log("abandoned '%s'" % quest_id)
	quest_abandoned.emit(quest_id)
	return true


## Hand it in. Grants rewards and files it under completed.
func complete(quest_id: StringName) -> bool:
	var q: Quest = quest(quest_id)
	if q == null or not is_active(quest_id):
		return false

	active.erase(quest_id)
	completed[quest_id] = completed.get(quest_id, 0) + 1
	_log("completed '%s' — %d xp, %d gold" % [quest_id, q.xp_reward, q.gold_reward])
	_grant_rewards(q)
	quest_completed.emit(quest_id)
	return true


## Jump straight to a named stage, for dialogue that skips ahead.
func set_stage(quest_id: StringName, stage_id: StringName) -> bool:
	var q: Quest = quest(quest_id)
	if q == null or not is_active(quest_id):
		return false
	var stage: QuestStage = q.stage(stage_id)
	if stage == null:
		return false

	active[quest_id]["stage"] = stage_id
	active[quest_id]["progress"] = {}
	quest_advanced.emit(quest_id, stage_id)
	_run(stage.on_enter)
	refresh()
	return true

# -------------------------------------------------------------- notifications

func notify_kill(tag: StringName, amount: int = 1) -> void:
	_tick(QuestObjective.Kind.KILL, tag, amount)


func notify_talk(npc_id: StringName) -> void:
	_tick(QuestObjective.Kind.TALK, npc_id, 1)


func notify_location(location_id: StringName) -> void:
	_tick(QuestObjective.Kind.REACH, location_id, 1)


func notify_custom(tag: StringName, amount: int = 1) -> void:
	_tick(QuestObjective.Kind.CUSTOM, tag, amount)


## Add to every matching counted objective across every active quest.
func _tick(kind: int, target: StringName, amount: int) -> void:
	if target.is_empty() or amount <= 0:
		return

	for quest_id in active.keys():
		var stage: QuestStage = current_stage(quest_id)
		if stage == null:
			continue
		for objective in stage.objectives:
			if objective == null or objective.is_derived():
				continue
			if objective.kind != kind or objective.target != target:
				continue
			var now: int = mini(progress_of(quest_id, objective.id) + amount, objective.required)
			active[quest_id]["progress"][objective.id] = now
			_log("'%s' objective '%s' now %d/%d" % [quest_id, objective.id, now, objective.required])
			objective_progressed.emit(quest_id, objective.id, now, objective.required)

	refresh()


## Re-check every active quest and advance anything that's finished. Safe to
## call as often as you like — the log calls it whenever it opens.
func refresh() -> void:
	# a copy, since advancing can complete a quest and mutate `active`
	for quest_id in active.keys().duplicate():
		if not is_active(quest_id):
			continue
		if is_stage_done(quest_id):
			_advance(quest_id)


func _advance(quest_id: StringName) -> void:
	var q: Quest = quest(quest_id)
	var stage: QuestStage = current_stage(quest_id)
	if q == null or stage == null:
		return

	_log("'%s' stage '%s' complete" % [quest_id, stage.id])
	_run(stage.on_complete)

	if not stage.next.is_empty():
		var next_stage: QuestStage = q.stage(stage.next)
		if next_stage == null:
			push_warning("Quests: '%s' points at missing stage '%s'" % [quest_id, stage.next])
			return
		active[quest_id]["stage"] = next_stage.id
		active[quest_id]["progress"] = {}
		quest_advanced.emit(quest_id, next_stage.id)
		_run(next_stage.on_enter)
		# the new stage may already be satisfied
		if is_stage_done(quest_id):
			_advance(quest_id)
		return

	if q.needs_turn_in():
		_log("'%s' is ready to hand in" % quest_id)
		quest_ready.emit(quest_id)
	else:
		# no turn-in NPC means the quest pays out on its own
		complete(quest_id)


func _grant_rewards(q: Quest) -> void:
	var player = _player()
	if player == null:
		return

	if q.xp_reward > 0 and player.has_method("add_xp"):
		player.add_xp(q.xp_reward)
	if q.gold_reward > 0 and player.has_method("add_gold"):
		player.add_gold(q.gold_reward)

	if "inventory" in player and player.inventory != null:
		for item in q.item_rewards:
			if item == null or player.inventory.is_full():
				continue
			player.inventory.items.append(item.duplicate())
		player.inventory.inventory_changed.emit()

	_run(q.extra_rewards)


## Quest actions reuse DialogueAction, so there's one vocabulary of effects.
## No NPC and no dialogue runner, so anything needing those is a no-op.
func _run(actions: Array) -> void:
	for action in actions:
		if action != null:
			action.run(null, _player(), null)


func _player():
	return Game.player


func _log(line: String) -> void:
	if VERBOSE:
		print("Quests: ", line)

# --------------------------------------------------------------------- saving

func reset() -> void:
	active.clear()
	completed.clear()


func save_state() -> Dictionary:
	return {
		"active": active.duplicate(true),
		"completed": completed.duplicate(),
	}


func load_state(data: Dictionary) -> void:
	active = data.get("active", {}).duplicate(true)
	completed = data.get("completed", {}).duplicate()
