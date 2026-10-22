class_name DialogueCondition
extends Resource
## A gate on a dialogue choice. All of a choice's conditions must pass for it
## to be offered.
##
## Enum-driven rather than one subclass per kind: these are lookups, not
## computations, and twelve files for twelve one-liners isn't worth it.

enum Kind {
	ALWAYS,
	AFFINITY_AT_LEAST,
	FLAG_SET,
	COUNTER_AT_LEAST,
	STAT_AT_LEAST,
	LEVEL_AT_LEAST,
	GOLD_AT_LEAST,
	HAS_ITEM,
	IS_FOLLOWING,
	IS_MERCHANT,
	FACTION_IS,
}

@export var kind: Kind = Kind.ALWAYS
## Flag name, counter name, or stat name, depending on the kind.
## For AFFINITY_AT_LEAST, leave empty to mean the NPC you're talking to.
@export var key: StringName = ""
@export var amount: int = 0
@export var item: Item
@export var faction: NPC.Faction = NPC.Faction.NEUTRAL
## Flip the result, so one entry covers "below" as well as "at least".
@export var negate: bool = false


func is_met(npc, player) -> bool:
	var result: bool = _evaluate(npc, player)
	return not result if negate else result


func _evaluate(npc, player) -> bool:
	match kind:
		Kind.AFFINITY_AT_LEAST:
			return Story.get_affinity(_target_id(npc)) >= amount

		Kind.FLAG_SET:
			return Story.get_flag(key)

		Kind.COUNTER_AT_LEAST:
			return Story.get_counter(key) >= amount

		Kind.STAT_AT_LEAST:
			if player == null or not player.has_method("modified_stat"):
				return false
			return player.modified_stat(String(key)) >= amount

		Kind.LEVEL_AT_LEAST:
			return player != null and "level" in player and player.level >= amount

		Kind.GOLD_AT_LEAST:
			return player != null and "gold" in player and player.gold >= amount

		Kind.HAS_ITEM:
			return _carries(player, item)

		Kind.IS_FOLLOWING:
			return npc != null and npc.has_method("is_following") and npc.is_following()

		Kind.IS_MERCHANT:
			return npc != null and "is_merchant" in npc and npc.is_merchant

		Kind.FACTION_IS:
			return npc != null and "faction" in npc and npc.faction == faction

		_:
			return true


## Affinity usually means "this NPC", but `key` can name someone else.
func _target_id(npc) -> StringName:
	if not key.is_empty():
		return key
	if npc != null and npc.has_method("unique_id"):
		return npc.unique_id()
	return &""


## Carried or worn — either counts as having it.
func _carries(player, wanted: Item) -> bool:
	if wanted == null or player == null or not "inventory" in player:
		return false
	var inv: Inventory = player.inventory
	if inv == null:
		return false
	for carried in inv.items:
		if carried != null and carried.display_name == wanted.display_name:
			return true
	for worn in inv.equipped.values():
		if worn != null and worn.display_name == wanted.display_name:
			return true
	return false


## One line for a tooltip when a choice is shown but locked.
func describe() -> String:
	match kind:
		Kind.AFFINITY_AT_LEAST:
			return "Needs affinity %d" % amount
		Kind.FLAG_SET:
			return "Needs: %s" % key
		Kind.COUNTER_AT_LEAST:
			return "Needs %s of %d" % [key, amount]
		Kind.STAT_AT_LEAST:
			return "Needs %s %d" % [Stats.LABELS.get(String(key), String(key)), amount]
		Kind.LEVEL_AT_LEAST:
			return "Needs level %d" % amount
		Kind.GOLD_AT_LEAST:
			return "Needs %d gold" % amount
		Kind.HAS_ITEM:
			return "Needs %s" % (item.display_name if item != null else "an item")
		_:
			return ""
