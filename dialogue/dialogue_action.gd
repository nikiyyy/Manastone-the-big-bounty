class_name DialogueAction
extends Resource
## Something that happens when a choice is picked, or when a node is entered.
## Actions run in order; the ones that end the conversation (trade, combat,
## leave) ask the runner to do it once the whole list has finished.

enum Kind {
	NONE,
	CHANGE_AFFINITY,
	SET_FLAG,
	CLEAR_FLAG,
	ADD_COUNTER,
	GIVE_GOLD,
	TAKE_GOLD,
	GIVE_ITEM,
	TAKE_ITEM,
	HEAL_PLAYER,
	APPLY_EFFECT,
	GRANT_XP,
	GRANT_STAT_POINTS,
	GRANT_TALENT_POINTS,
	RAISE_STAT,
	START_FOLLOWING,
	STOP_FOLLOWING,
	OPEN_TRADE,
	START_COMBAT,
	FLEE_BATTLE,
	END_DIALOGUE,
	CUSTOM,
}

@export var kind: Kind = Kind.NONE
## Flag name, counter name, stat name, or an NPC id for CHANGE_AFFINITY.
## Leave empty on CHANGE_AFFINITY to mean the NPC you're talking to.
@export var key: StringName = ""
@export var amount: int = 0
@export var item: Item
@export var effect: Effect
## Free text handed to Story.custom_action, for the CUSTOM kind.
@export_multiline var payload: String = ""


## `runner` is the dialogue window — actions that end the conversation call
## back into it rather than doing it themselves, so the rest of the list
## still runs and nothing is freed mid-loop.
func run(npc, player, runner) -> void:
	match kind:
		Kind.CHANGE_AFFINITY:
			Story.change_affinity(_target_id(npc), amount)

		Kind.SET_FLAG:
			Story.set_flag(key, true)

		Kind.CLEAR_FLAG:
			Story.set_flag(key, false)

		Kind.ADD_COUNTER:
			Story.add_counter(key, maxi(1, amount))

		Kind.GIVE_GOLD:
			if player != null and player.has_method("add_gold"):
				player.add_gold(amount)

		Kind.TAKE_GOLD:
			if player != null and player.has_method("add_gold"):
				player.add_gold(-amount)

		Kind.GIVE_ITEM:
			_give_item(player)

		Kind.TAKE_ITEM:
			_take_item(player)

		Kind.HEAL_PLAYER:
			if player != null and player.has_method("heal"):
				player.heal(amount)

		Kind.APPLY_EFFECT:
			if player != null and player.has_method("apply_effect_now"):
				player.apply_effect_now(effect)

		Kind.GRANT_XP:
			if player != null and player.has_method("add_xp"):
				player.add_xp(amount)

		Kind.GRANT_STAT_POINTS:
			if player != null and player.stats != null:
				player.stats.available_points += amount

		Kind.GRANT_TALENT_POINTS:
			if player != null and player.stats != null:
				player.stats.talent_points += amount

		Kind.RAISE_STAT:
			_raise_stat(player)

		Kind.START_FOLLOWING:
			if npc != null and npc.has_method("start_following") and player != null:
				npc.start_following(player)

		Kind.STOP_FOLLOWING:
			if npc != null and npc.has_method("stop_following"):
				npc.stop_following()

		Kind.OPEN_TRADE:
			if runner != null:
				runner.request_trade()

		Kind.START_COMBAT:
			if runner != null:
				runner.request_combat()

		Kind.FLEE_BATTLE:
			if runner != null:
				runner.request_flee()

		Kind.END_DIALOGUE:
			if runner != null:
				runner.request_end()

		Kind.CUSTOM:
			Story.custom_action.emit(key, payload)

		_:
			pass


func _target_id(npc) -> StringName:
	if not key.is_empty():
		return key
	if npc != null and npc.has_method("unique_id"):
		return npc.unique_id()
	return &""


func _give_item(player) -> void:
	if item == null or player == null or not "inventory" in player:
		return
	var inv: Inventory = player.inventory
	if inv == null or inv.is_full():
		return
	# a copy, so one reward resource can be handed out many times
	inv.items.append(item.duplicate())
	inv.inventory_changed.emit()


func _take_item(player) -> void:
	if item == null or player == null or not "inventory" in player:
		return
	var inv: Inventory = player.inventory
	if inv == null:
		return
	for i in inv.items.size():
		if inv.items[i] != null and inv.items[i].display_name == item.display_name:
			inv.items.remove_at(i)
			inv.inventory_changed.emit()
			return


## Permanent stat change, unlike an Effect — training, a blessing, a curse.
func _raise_stat(player) -> void:
	if player == null or player.stats == null:
		return
	if not Stats.NAMES.has(String(key)):
		return
	player.stats.set(String(key), player.stats.get(String(key)) + amount)
