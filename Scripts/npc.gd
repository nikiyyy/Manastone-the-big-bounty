@tool
class_name NPC
extends CharacterBody3D
 
enum Faction { ALLY, ENEMY, NEUTRAL }
 
const FACTION_COLORS := {
	Faction.ALLY: Color(0.25, 0.8, 0.35),
	Faction.ENEMY: Color(0.85, 0.2, 0.2),
	Faction.NEUTRAL: Color(0.9, 0.8, 0.2),
}
 
signal walk_finished
signal died
signal health_changed(current: int, maximum: int)
signal mana_changed(current: int, maximum: int)
signal effects_changed
signal xp_changed(amount: int)
signal leveled_up(new_level: int)
signal talents_changed
 
@export var faction: Faction = Faction.NEUTRAL:
	set(value):
		faction = value
		_apply_color()
 
@export var display_name: String = "NPC"
@export_multiline var greeting: String = "Hello there, traveller."
@export_multiline var response: String = "Nice weather we're having."
 
@export_group("Character")
@export var stats: Stats
@export var character_class: CharacterClass
@export var inventory: Inventory
@export var spells: Array[Spell] = []
@export var ai: CombatAI
@export var level: int = 1
@export var xp: int = 0
@export var base_armor: int = 0
@export var base_resistances: Resistances
 
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
 
var current_health: int = 0
var current_mana: int = 0
var effects: EffectHolder = EffectHolder.new()
var follow_target: Node3D = null
 
## Talent display_name -> ranks taken.
var talent_ranks: Dictionary = {}
 
var _walking: bool = false
var _walk_target = null
var _walk_queue: Array = []
var _stock_loaded: bool = false
var _computing_armor: bool = false
 
 
func _ready() -> void:
	base_resistances = base_resistances.duplicate() if base_resistances != null else Resistances.new()
	inventory = inventory.duplicate(true) if inventory != null else Inventory.new()
	if not Engine.is_editor_hint():
		stats = stats.duplicate() if stats != null else Stats.new()
		current_health = max_health()
		current_mana = max_mana()
	_apply_color()
 
 
func _apply_color() -> void:
	if not is_node_ready():
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = FACTION_COLORS[faction]
	$MeshInstance3D.material_override = mat
 
 
func get_faction() -> Faction:
	return faction
 
 
func is_ally() -> bool:
	return faction == Faction.ALLY
 
 
func is_enemy() -> bool:
	return faction == Faction.ENEMY
 
 
func class_name_of() -> String:
	return character_class.display_name if character_class != null else "—"
 
# ------------------------------------------------------------------- follow
 
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
 
# ------------------------------------------------------------------ walking
 
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
	global_position = where
	_walk_queue.clear()
	_walk_target = null
	velocity = Vector3.ZERO
 
# ------------------------------------------------------------------- health
 
func max_health() -> int:
	return maxi(1, modified_stat("health"))
 
 
func take_damage(amount: int) -> void:
	if current_health <= 0:
		return
	current_health = maxi(0, current_health - amount)
	health_changed.emit(current_health, max_health())
	if current_health == 0:
		_die()
 
 
func heal(amount: int) -> void:
	current_health = mini(max_health(), current_health + amount)
	health_changed.emit(current_health, max_health())
 
 
func is_alive() -> bool:
	return current_health > 0
 
 
func _die() -> void:
	velocity = Vector3.ZERO
	rotation.x = deg_to_rad(-90.0)
	set_collision_layer_value(2, false)
	set_collision_mask_value(2, false)
	$CollisionShape3D.set_deferred("disabled", true)
	died.emit()
 
# --------------------------------------------------------- armor, resisting
 
func equipment_armor() -> int:
	return inventory.total_armor() if inventory != null else 0
 
 
## Innate armor, gear, and whatever talents convert into armor.
## The guard stops a talent that reads armor from recursing forever.
func armor() -> int:
	var total: int = base_armor + equipment_armor()
	if not _computing_armor:
		_computing_armor = true
		total += talent_armor_bonus()
		_computing_armor = false
	return total
 
 
## Innate resistance plus whatever gear adds.
func resistances() -> Resistances:
	var base: Resistances = base_resistances if base_resistances != null else Resistances.new()
	var gear: Resistances = inventory.total_resistances() if inventory != null else null
	return base.combined(gear)
 
 
func resistance_to(kind: int) -> int:
	return resistances().get_for(kind) + talent_resistance_bonus(kind)
 
# --------------------------------------------------------------------- mana
 
func max_mana() -> int:
	return maxi(0, modified_stat("mana_pool"))
 
 
func spend_mana(amount: int) -> bool:
	if amount > current_mana:
		return false
	current_mana -= amount
	mana_changed.emit(current_mana, max_mana())
	return true
 
 
func restore_mana(amount: int) -> void:
	current_mana = mini(max_mana(), current_mana + amount)
	mana_changed.emit(current_mana, max_mana())
 
# ----------------------------------------------------------- stats, effects
 
## A stat with gear, talents and active effects layered on, in that order.
func modified_stat(stat_name: String) -> int:
	var base: int = stats.get(stat_name) if stats != null else 0
	base += equipment_bonus(stat_name)
	base += talent_stat_bonus(stat_name)
	return effects.modify(stat_name, base)
 
 
func equipment_bonus(stat_name: String) -> int:
	return inventory.total_stat_bonus(stat_name) if inventory != null else 0
 
 
func add_effect(effect: Effect) -> void:
	effects.add(effect)
	effects_changed.emit()
 
 
## Called at the start of this unit's turn.
func tick_effects() -> void:
	var expired: Array = effects.advance()
	if not expired.is_empty():
		effects_changed.emit()
 
 
func clear_effects() -> void:
	effects.clear()
	effects_changed.emit()
 
# ------------------------------------------------------------------ talents
 
func talent_rank(talent: Talent) -> int:
	return talent_ranks.get(talent.display_name, 0) if talent != null else 0
 
 
func talent_points_spent() -> int:
	var total: int = 0
	for ranks in talent_ranks.values():
		total += ranks
	return total
 
 
## Can this talent take another rank right now?
func can_learn(talent: Talent) -> bool:
	if talent == null or stats == null:
		return false
	if stats.talent_points <= 0:
		return false
	if talent_rank(talent) >= talent.max_ranks:
		return false
	if talent_points_spent() < talent.required_points:
		return false
	if talent.requires != null and talent_rank(talent.requires) < talent.requires.max_ranks:
		return false
	return true
 
 
func learn_talent(talent: Talent) -> bool:
	if not can_learn(talent):
		return false
	talent_ranks[talent.display_name] = talent_rank(talent) + 1
	stats.talent_points -= 1
	talents_changed.emit()
	return true
 
 
## Talents this unit has at least one rank in, paired with that rank.
func learned_talents() -> Array:
	var out: Array = []
	if character_class == null or character_class.talent_tree == null:
		return out
	for talent in character_class.talent_tree.talents:
		if talent == null:
			continue
		var rank: int = talent_rank(talent)
		if rank > 0:
			out.append({"talent": talent, "rank": rank})
	return out
 
 
func talent_stat_bonus(stat_name: String) -> int:
	var total: int = 0
	for entry in learned_talents():
		for effect in entry["talent"].effects:
			if effect != null:
				total += effect.stat_bonus(self, stat_name, entry["rank"])
	return total
 
 
func talent_armor_bonus() -> int:
	var total: int = 0
	for entry in learned_talents():
		for effect in entry["talent"].effects:
			if effect != null:
				total += effect.armor_bonus(self, entry["rank"])
	return total
 
 
func talent_resistance_bonus(kind: int) -> int:
	var total: int = 0
	for entry in learned_talents():
		for effect in entry["talent"].effects:
			if effect != null:
				total += effect.resistance_bonus(self, kind, entry["rank"])
	return total
 
# ---------------------------------------------------------------- levelling
 
func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	xp = maxi(0, xp + amount)
	xp_changed.emit(xp)
	var earned: int = Progression.level_for_xp(xp)
	while level < earned:
		level += 1
		if stats != null:
			stats.available_points += Progression.POINTS_PER_LEVEL
			stats.talent_points += 1
		print("%s reaches level %d." % [display_name, level])
		leveled_up.emit(level)
 
# ----------------------------------------------------------------- merchant
 
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
 
# ------------------------------------------------------- battle and saving
 
## The whole army this figure represents. An empty party means it fights alone.
func to_battle_group() -> Dictionary:
	var members: Array = []
 
	if party.is_empty():
		members.append({
			"display_name": display_name,
			"stats": stats,
			"ai": ai,
			"character_class": character_class,
			"level": level,
			"base_armor": base_armor,
			"base_resistances": base_resistances,
			"inventory": inventory,
			"spells": spells,
			"xp_reward": 10,
			"gold": 0,
			"scene_override": "",
		})
	else:
		for template in party:
			if template == null:
				continue
			for i in template.count:
				members.append(template.to_member(i))
 
	return {"name": display_name, "members": members}
 
 
## This NPC as a single combatant, for when it joins your side.
func to_ally_data() -> Dictionary:
	return {
		"display_name": display_name,
		"stats": stats,
		"ai": ai,
		"character_class": character_class,
		"inventory": inventory,
		"spells": spells,
		"level": level,
		"xp": xp,
		"base_armor": base_armor,
		"base_resistances": base_resistances,
		"talent_ranks": talent_ranks.duplicate(),
	}
 
 
func save_state() -> Dictionary:
	return {
		"position": global_position,
		"rotation_y": rotation.y,
		"following": is_following(),
		"stats": stats,
		"inventory": inventory,
		"character_class": character_class,
		"talent_ranks": talent_ranks.duplicate(),
		"level": level,
		"xp": xp,
		"base_armor": base_armor,
		"base_resistances": base_resistances,
		"mana": current_mana,
		"merchant_gold": merchant_gold,
		"stock_loaded": _stock_loaded,
	}
 
 
func load_state(data: Dictionary) -> void:
	global_position = data.get("position", global_position)
	rotation.y = data.get("rotation_y", rotation.y)
	if data.get("stats") != null:
		stats = data["stats"]
	if data.get("inventory") != null:
		inventory = data["inventory"]
	if data.get("character_class") != null:
		character_class = data["character_class"]
	if data.get("base_resistances") != null:
		base_resistances = data["base_resistances"]
	xp = data.get("xp", xp)
	talent_ranks = data.get("talent_ranks", {}).duplicate()
	level = maxi(data.get("level", level), Progression.level_for_xp(xp))
	base_armor = data.get("base_armor", base_armor)
	current_mana = data.get("mana", max_mana())
	merchant_gold = data.get("merchant_gold", merchant_gold)
	_stock_loaded = data.get("stock_loaded", false)
	mana_changed.emit(current_mana, max_mana())
	xp_changed.emit(xp)
	if data.get("following", false) and Game.player != null:
		start_following(Game.player)
 
