extends CharacterBody3D
 
signal interacted(npc)
signal health_changed(current: int, maximum: int)
signal mana_changed(current: int, maximum: int)
signal died
signal gold_changed(amount: int)
signal xp_changed(amount: int)
signal armor_changed(value: int)
signal leveled_up(new_level: int)
signal effects_changed
signal talents_changed
 
@export var speed: float = 5.0
@export var interaction_range: float = 2.0
 
@export_group("Character")
@export var display_name: String = "Hero"
@export var stats: Stats
@export var character_class: CharacterClass
@export var inventory: Inventory
@export var spells: Array[Spell] = []
@export var level: int = 1
@export var xp: int = 0
@export var gold: int = 0
@export var base_armor: int = 0
@export var base_resistances: Resistances
 
var current_health: int = 0
var current_mana: int = 0
var effects: EffectHolder = EffectHolder.new()
 
## Talent display_name -> ranks taken.
var talent_ranks: Dictionary = {}
 
var target_position: Vector3
var interaction_target = null
var dialogue_open: bool = false
 
var _waypoints: Array = []
var _deploy_selection = null
var _computing_armor: bool = false
 
 
func _ready() -> void:
	base_resistances = base_resistances.duplicate() if base_resistances != null else Resistances.new()
	stats = stats.duplicate() if stats != null else Stats.new()
	stats.changed_stat.connect(_on_stat_raised)
	inventory = inventory.duplicate(true) if inventory != null else Inventory.new()
	current_health = max_health()
	current_mana = max_mana()
	target_position = global_position
 
 
func class_name_of() -> String:
	return character_class.display_name if character_class != null else "—"
 
# ------------------------------------------------------------------ movement
 
func teleport_to(where: Vector3) -> void:
	global_position = where
	target_position = where
	interaction_target = null
	_waypoints.clear()
	velocity = Vector3.ZERO
 
 
func walk_path(points: Array) -> void:
	_begin_path(points)
 
 
func _begin_path(path) -> bool:
	if path == null or path.is_empty():
		return false
	_waypoints = path.duplicate()
	target_position = _waypoints.pop_front()
	return true
 
 
func _physics_process(delta: float) -> void:
	if not is_alive():
		return
	var to_target: Vector3 = target_position - global_position
	to_target.y = 0.0
 
	if to_target.length() > 0.15:
		var dir: Vector3 = to_target.normalized()
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		look_at(global_position + dir, Vector3.UP)
	elif not _waypoints.is_empty():
		target_position = _waypoints.pop_front()
	else:
		velocity.x = 0.0
		velocity.z = 0.0
 
	velocity.y = 0.0 if is_on_floor() else velocity.y - 20.0 * delta
	move_and_slide()
	_check_arrival()
 
# --------------------------------------------------------------------- input
 
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_handle_inspect(event.pressed)
		return
	if dialogue_open:
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
 
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
 
	var world := Game.current_world
	var deploying: bool = world != null and world.has_method("is_deploying") and world.is_deploying()
	var targeting: bool = world != null and world.has_method("is_targeting") and world.is_targeting()
 
	var from: Vector3 = cam.project_ray_origin(event.position)
	var to: Vector3 = from + cam.project_ray_normal(event.position) * 1000.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	if not deploying:
		query.exclude = [self]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.has("position"):
		return
 
	if targeting:
		world.confirm_cast(hit["position"])
		return
 
	var actor = _active_actor()
	if actor == null:
		return
 
	var collider = hit.get("collider")
 
	if deploying:
		if collider == self:
			_set_deploy_selection(null)
			return
		if collider != null and collider.has_method("is_ally") and collider.is_ally():
			_set_deploy_selection(collider)
			return
		if collider != null and collider.has_method("get_faction"):
			return
		_request_path(actor, hit["position"])
		return
 
	if collider != null and collider.has_method("get_faction"):
		if world != null and world.has_method("request_attack"):
			world.request_attack(actor, collider)
		elif actor == self:
			_approach(collider)
		return
 
	var path = _request_path(actor, hit["position"])
	if path != null and not path.is_empty():
		actor.walk_path(path)
 
 
## In battle, clicks command whoever's turn it is. Outside battle, us.
func _active_actor():
	var world := Game.current_world
	if world != null and world.has_method("is_deploying") and world.is_deploying():
		return _selected_deploy_unit()
	if world != null and world.has_method("get_controlled_unit"):
		return world.get_controlled_unit()
	return self
 
 
func _selected_deploy_unit():
	return _deploy_selection if _deploy_selection != null and is_instance_valid(_deploy_selection) else self
 
 
func _set_deploy_selection(unit) -> void:
	_deploy_selection = unit
	var world := Game.current_world
	if world != null and world.has_method("set_deploy_selection"):
		world.set_deploy_selection(unit if unit != null else self)
 
 
func _request_path(actor, point: Vector3):
	var world := Game.current_world
	if world != null and world.has_method("request_move"):
		return world.request_move(actor, point)
	return [point]
 
 
func _handle_inspect(pressed: bool) -> void:
	if not Game.in_battle():
		return
	var inspector = get_tree().get_first_node_in_group("unit_inspector")
	if inspector == null:
		return
	if not pressed:
		inspector.hide_card()
		return
 
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var from: Vector3 = cam.project_ray_origin(mouse)
	var to: Vector3 = from + cam.project_ray_normal(mouse) * 1000.0
	var query := PhysicsRayQueryParameters3D.create(from, to, 2)   # units only
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
 
	var collider = hit.get("collider")
	if collider != null and (collider.has_method("get_faction") or collider == self):
		inspector.show_for(collider)
 
# ----------------------------------------------------------------- dialogue
 
func _approach(npc) -> void:
	var away: Vector3 = global_position - npc.global_position
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3.FORWARD
	var stand_at: Vector3 = npc.global_position + away.normalized() * (interaction_range * 0.85)
 
	if _begin_path(_request_path(self, stand_at)):
		interaction_target = npc
 
 
func _check_arrival() -> void:
	if interaction_target == null:
		return
	if not is_instance_valid(interaction_target):
		interaction_target = null
		return
 
	var a: Vector3 = global_position
	var b: Vector3 = interaction_target.global_position
	var flat_distance: float = Vector2(a.x - b.x, a.z - b.z).length()
	if flat_distance > interaction_range:
		return
 
	var npc = interaction_target
	interaction_target = null
	target_position = global_position
	_face(b)
 
	dialogue_open = true
	interacted.emit(npc)
 
 
func _face(point: Vector3) -> void:
	var flat := Vector3(point.x, global_position.y, point.z)
	if flat.distance_to(global_position) > 0.01:
		look_at(flat, Vector3.UP)
 
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
 
 
func add_armor(amount: int) -> void:
	base_armor = maxi(0, base_armor + amount)
	armor_changed.emit(armor())
 
 
## Innate resistance plus whatever gear adds.
func resistances() -> Resistances:
	var base: Resistances = base_resistances if base_resistances != null else Resistances.new()
	var gear: Resistances = inventory.total_resistances() if inventory != null else null
	return base.combined(gear)
 
 
func resistance_to(kind: int) -> int:
	return resistances().get_for(kind) + talent_resistance_bonus(kind)
 
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
 
 
func _on_stat_raised(stat_name: String) -> void:
	if stat_name == "health":
		current_health += 1
		health_changed.emit(current_health, max_health())
 
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
 
# ------------------------------------------------------- gold and levelling
 
func add_gold(amount: int) -> void:
	gold = maxi(0, gold + amount)
	gold_changed.emit(gold)
 
 
func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	xp = maxi(0, xp + amount)
	xp_changed.emit(xp)
	_check_level_up()
 
 
## Award a point per level gained, however many levels that is at once.
func _check_level_up() -> void:
	var earned: int = Progression.level_for_xp(xp)
	while level < earned:
		level += 1
		if stats != null:
			stats.available_points += Progression.POINTS_PER_LEVEL
			stats.talent_points += 1
		print("%s reaches level %d." % [display_name, level])
		leveled_up.emit(level)
 
# -------------------------------------------------------------------- saving
 
func save_state() -> Dictionary:
	return {
		"stats": stats,
		"inventory": inventory,
		"character_class": character_class,
		"talent_ranks": talent_ranks.duplicate(),
		"base_resistances": base_resistances,
		"health": current_health,
		"mana": current_mana,
		"gold": gold,
		"xp": xp,
		"level": level,
		"base_armor": base_armor,
	}
 
 
func load_state(data: Dictionary) -> void:
	if data.get("stats") != null:
		stats = data["stats"]
		if not stats.changed_stat.is_connected(_on_stat_raised):
			stats.changed_stat.connect(_on_stat_raised)
	if data.get("inventory") != null:
		inventory = data["inventory"]
	if data.get("character_class") != null:
		character_class = data["character_class"]
	if data.get("base_resistances") != null:
		base_resistances = data["base_resistances"]
 
	talent_ranks = data.get("talent_ranks", {}).duplicate()
	gold = data.get("gold", 0)
	xp = data.get("xp", 0)
	level = maxi(data.get("level", 1), Progression.level_for_xp(xp))
	base_armor = data.get("base_armor", 0)
	current_health = data.get("health", max_health())
	current_mana = data.get("mana", max_mana())
 
	health_changed.emit(current_health, max_health())
	mana_changed.emit(current_mana, max_mana())
	gold_changed.emit(gold)
	xp_changed.emit(xp)
	armor_changed.emit(armor())
 
