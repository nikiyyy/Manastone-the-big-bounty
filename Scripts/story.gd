extends Node
## Autoload "Story". Narrative state that outlives any world: how each NPC
## feels about you, flags you've set, counters you've raised.
##
## Kept here rather than on the NPC so a conversation can read someone else's
## opinion of you, and so it survives the node being destroyed and rebuilt on
## every world change.

signal affinity_changed(npc_id: StringName, value: int)
signal flag_changed(flag: StringName, value: bool)
## Escape hatch: a DialogueAction of kind CUSTOM fires this. Listen for it
## anywhere that needs behaviour the action enum doesn't cover.
signal custom_action(key: StringName, payload: String)

const MIN_AFFINITY := -100
const MAX_AFFINITY := 100

## Upper bound of each band, walked in order.
const TIERS := [
	{"below": -60, "name": "Hostile"},
	{"below": -20, "name": "Cold"},
	{"below": 20, "name": "Neutral"},
	{"below": 60, "name": "Friendly"},
	{"below": 101, "name": "Devoted"},
]

var affinity: Dictionary = {}      # StringName -> int
var flags: Dictionary = {}         # StringName -> bool
var counters: Dictionary = {}      # StringName -> int

# ------------------------------------------------------------------ affinity

func get_affinity(npc_id: StringName) -> int:
	return affinity.get(npc_id, 0)


func set_affinity(npc_id: StringName, value: int) -> int:
	if npc_id.is_empty():
		return 0
	var clamped: int = clampi(value, MIN_AFFINITY, MAX_AFFINITY)
	affinity[npc_id] = clamped
	affinity_changed.emit(npc_id, clamped)
	return clamped


func change_affinity(npc_id: StringName, delta: int) -> int:
	return set_affinity(npc_id, get_affinity(npc_id) + delta)


func affinity_tier(npc_id: StringName) -> String:
	var value: int = get_affinity(npc_id)
	for tier in TIERS:
		if value < tier["below"]:
			return tier["name"]
	return TIERS[TIERS.size() - 1]["name"]

# --------------------------------------------------------- flags and counters

func get_flag(flag: StringName) -> bool:
	return flags.get(flag, false)


func set_flag(flag: StringName, value: bool = true) -> void:
	if flag.is_empty():
		return
	flags[flag] = value
	flag_changed.emit(flag, value)


func get_counter(key: StringName) -> int:
	return counters.get(key, 0)


## Codex pages the player has opened. Stored as ordinary flags, so a dialogue
## condition can check FLAG_SET on "codex_read:the_siege" and react to what
## the player has actually looked up.
const READ_PREFIX := "codex_read:"


func mark_read(entry_id: StringName) -> void:
	if entry_id.is_empty():
		return
	set_flag(StringName(READ_PREFIX + entry_id), true)


func has_read(entry_id: StringName) -> bool:
	return get_flag(StringName(READ_PREFIX + entry_id))


func add_counter(key: StringName, delta: int = 1) -> int:
	if key.is_empty():
		return 0
	counters[key] = get_counter(key) + delta
	return counters[key]

# --------------------------------------------------------------------- saving

func reset() -> void:
	affinity.clear()
	flags.clear()
	counters.clear()


func save_state() -> Dictionary:
	return {
		"affinity": affinity.duplicate(),
		"flags": flags.duplicate(),
		"counters": counters.duplicate(),
	}


func load_state(data: Dictionary) -> void:
	affinity = data.get("affinity", {}).duplicate()
	flags = data.get("flags", {}).duplicate()
	counters = data.get("counters", {}).duplicate()
