@tool
class_name NPC
extends Unit
## Anyone who isn't the player: allies, enemies, merchants. Everything shared
## with the player lives in Unit — this is faction, following, walking a path
## on command, trading, and handing itself to the battle map.

enum Faction { ALLY, ENEMY, NEUTRAL }

const FACTION_COLORS := {
	Faction.ALLY: Color(0.25, 0.8, 0.35),
	Faction.ENEMY: Color(0.85, 0.2, 0.2),
	Faction.NEUTRAL: Color(0.9, 0.8, 0.2),
}

signal walk_finished

@export var faction: Faction = Faction.NEUTRAL:
	set(value):
		faction = value
		_apply_color()

## Stable identity for affinity, flags and quest state. Set it to something
## you won't rename — "innkeeper_mara", not "NPC3". Falls back to the node
## name, which works but breaks the moment you rename the node.
@export var npc_id: StringName = ""

@export_group("Dialogue")
@export var dialogue: DialogueTree
@export_multiline var greeting: String = "Hello there, traveller."
@export_multiline var response: String = "Nice weather we're having."

@export_group("Combat")
@export var ai: CombatAI

@export_group("Follow")
@export var move_speed: float = 5.5
@export var follow_distance: float = 3.0
@export var stop_buffer: float = 0.8

@export_group("Battle group")
@export var party: Array[UnitTemplate] = []

@export_group("Merchant")
@export var is_merchant: bool = false
@export var merchant_gold: int = 200
@export var stock: Array[Item] = []
@export_range(0.1, 1.0) var buy_rate: float = 0.5   ## fraction of value paid to you

var follow_target: Node3D = null

var _walking: bool = false
var _walk_target = null
var _walk_queue: Array = []
var _stock_loaded: bool = false


func _ready() -> void:
	super()
	_apply_color()


func _apply_color() -> void:
	if not is_node_ready():
		return
	var mesh := get_node_or_null("MeshInstance3D")
	if mesh == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = FACTION_COLORS[faction]
	mesh.material_override = mat


## What Story keys this character's affinity and flags by.
func unique_id() -> StringName:
	return npc_id if not npc_id.is_empty() else StringName(name)


func affinity() -> int:
	return Story.get_affinity(unique_id())


func affinity_tier() -> String:
	return Story.affinity_tier(unique_id())


func get_faction() -> Faction:
	return faction


func is_ally() -> bool:
	return faction == Faction.ALLY


func is_enemy() -> bool:
	return faction == Faction.ENEMY

# -------------------------------------------------------------------- follow

func start_following(who: Node3D) -> void:
	follow_target = who


func stop_following() -> void:
	follow_target = null
	_walking = false
	velocity = Vector3.ZERO


func is_following() -> bool:
	return follow_target != null and is_instance_valid(follow_target)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not is_alive():
		return

	if _walk_target != null:
		var to_dest: Vector3 = _walk_target - global_position
		to_dest.y = 0.0
		if to_dest.length() < 0.12:
			velocity.x = 0.0
			velocity.z = 0.0
			_next_waypoint()
		else:
			var d: Vector3 = to_dest.normalized()
			velocity.x = d.x * move_speed
			velocity.z = d.z * move_speed
			look_at(global_position + d, Vector3.UP)
	elif not is_following():
		follow_target = null
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		var to_target: Vector3 = follow_target.global_position - global_position
		to_target.y = 0.0
		var dist: float = to_target.length()

		# hysteresis: start walking past follow_distance, stop once well inside
		if dist > follow_distance:
			_walking = true
		elif dist < follow_distance - stop_buffer:
			_walking = false

		if _walking and dist > 0.01:
			var dir: Vector3 = to_target.normalized()
			velocity.x = dir.x * move_speed
			velocity.z = dir.z * move_speed
			look_at(global_position + dir, Vector3.UP)
		else:
			velocity.x = 0.0
			velocity.z = 0.0

	velocity.y = 0.0 if is_on_floor() else velocity.y - 20.0 * delta
	move_and_slide()

# ------------------------------------------------------------------- walking

func walk_to(where: Vector3) -> void:
	walk_path([where])


func walk_path(points: Array) -> void:
	_walk_queue = points.duplicate()
	_next_waypoint()


func _next_waypoint() -> void:
	if _walk_queue.is_empty():
		_walk_target = null
		walk_finished.emit()
	else:
		_walk_target = _walk_queue.pop_front()


func teleport_to(where: Vector3) -> void:
	super(where)
	_walk_queue.clear()
	_walk_target = null


func _die() -> void:
	_walk_queue.clear()
	_walk_target = null
	_walking = false
	super()

# ------------------------------------------------------------------ merchant

## Merchant inventory is built from `stock` on first use, then persists.
func merchant_inventory() -> Inventory:
	if inventory == null:
		inventory = Inventory.new()
	if not _stock_loaded:
		_stock_loaded = true
		for item in stock:
			if item != null:
				inventory.items.append(item.duplicate())
	return inventory


## What this merchant pays for an item you're selling.
func buy_price(item: Item) -> int:
	return maxi(1, int(item.value * buy_rate))


## What this merchant charges you for an item.
func sell_price(item: Item) -> int:
	return maxi(1, item.value)

# -------------------------------------------------------- battle and saving

## The whole army this figure represents. An empty party means it fights alone.
func to_battle_group() -> Dictionary:
	var members: Array = []

	if party.is_empty():
		var solo: Dictionary = to_unit_data()
		solo["ai"] = ai
		solo["xp_reward"] = 10
		solo["gold"] = 0
		solo["scene_override"] = ""
		members.append(solo)
	else:
		for template in party:
			if template == null:
				continue
			for i in template.count:
				members.append(template.to_member(i))

	return {"name": display_name, "members": members}


## This NPC as a single combatant, for when it joins your side.
func to_ally_data() -> Dictionary:
	var data: Dictionary = to_unit_data()
	data["ai"] = ai
	data["npc_id"] = unique_id()
	return data


func save_state() -> Dictionary:
	var data: Dictionary = super()
	data["position"] = global_position
	data["rotation_y"] = rotation.y
	data["following"] = is_following()
	data["merchant_gold"] = merchant_gold
	data["stock_loaded"] = _stock_loaded
	return data


func load_state(data: Dictionary) -> void:
	super(data)
	global_position = data.get("position", global_position)
	rotation.y = data.get("rotation_y", rotation.y)
	merchant_gold = data.get("merchant_gold", merchant_gold)
	_stock_loaded = data.get("stock_loaded", false)
	if data.get("following", false) and Game.player != null:
		start_following(Game.player)
