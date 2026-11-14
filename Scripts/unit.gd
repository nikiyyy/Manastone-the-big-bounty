@tool
class_name Unit
extends CharacterBody3D
## Everything a combatant is, minus how it decides where to walk.
##
## Player and NPC both extend this. If a system touches health, mana, armor,
## resistances, stats, effects, talents or levelling, it belongs here and is
## written once — movement, input and faction behaviour stay in the subclass.
##
## @tool so NPC's editor preview still works; the runtime half of _ready is
## guarded, so nothing is duplicated or initialised while you're editing.

signal died
signal health_changed(current: int, maximum: int)
signal mana_changed(current: int, maximum: int)
signal armor_changed(value: int)
signal effects_changed
signal xp_changed(amount: int)
signal leveled_up(new_level: int)
signal talents_changed

@export var display_name: String = "Unit"

@export_group("Character")
@export var stats: Stats
@export var character_class: CharacterClass
@export var inventory: Inventory
## Worn on spawn. Simpler to fill in than the inventory's equipped dictionary.
@export var loadout: Array[Item] = []
@export var spells: Array[Spell] = []
@export var level: int = 1
@export var xp: int = 0
@export var base_armor: int = 0
@export var base_resistances: Resistances

@export_group("Model")
## Stands in for the coloured capsule. Leave it empty and the capsule is used,
## so a unit with no art yet still turns up on the field.
@export var model: PackedScene
## Imported models arrive at whatever size the program that made them chose,
## so this range runs wide.
@export_range(0.05, 50.0, 0.05) var model_scale: float = 1.0
## Turns the model on the spot. Y straightens a model whose front doesn't
## face the way the unit walks; X and Z stand up one that was exported lying
## down. It's applied under the unit's own facing, so turning to face an
## enemy still works on top of it.
@export var model_rotation_degrees: Vector3 = Vector3.ZERO
## Nudge up or down after the automatic drop to ground level.
@export var model_y_offset: float = 0.0

var current_health: int = 0
var current_mana: int = 0
var effects: EffectHolder = EffectHolder.new()
var _model_instance: Node3D = null

## Talent display_name -> ranks taken.
var talent_ranks: Dictionary = {}

var _computing_armor: bool = false


## Subclasses call super() first, then do their own setup.
func _ready() -> void:
	if Engine.is_editor_hint():
		return

	base_resistances = base_resistances.duplicate() if base_resistances != null else Resistances.new()
	stats = stats.duplicate() if stats != null else Stats.new()
	if not stats.changed_stat.is_connected(_on_stat_raised):
		stats.changed_stat.connect(_on_stat_raised)

	inventory = inventory.duplicate(true) if inventory != null else Inventory.new()
	inventory.equip_all(loadout)

	current_health = max_health()
	current_mana = max_mana()
	apply_model()


# --------------------------------------------------------------------- model

## Put the unit's model on, or fall back to the capsule when there isn't one.
## Safe to call again — the battle map does exactly that once it's copied an
## enemy template's art onto a freshly spawned unit.
func apply_model() -> void:
	if _model_instance != null and is_instance_valid(_model_instance):
		_model_instance.queue_free()
	_model_instance = null

	# The capsule is hidden, never freed: it carries the faction colour, and a
	# unit whose model is taken away has to have something left to draw.
	_show_capsule(model == null)
	if model == null:
		return

	var node = model.instantiate()
	if not node is Node3D:
		push_warning("Unit %s: model isn't a 3D scene." % display_name)
		node.queue_free()
		_show_capsule(true)
		return

	add_child(node)
	_model_instance = node

	# size and angle first: the drop below measures the model as it will
	# actually stand, so neither can throw the height off
	var s: float = maxf(0.01, model_scale)
	node.scale = Vector3(s, s, s)
	node.rotation_degrees = model_rotation_degrees
	node.position = Vector3(0.0, -_model_bottom(node) + model_y_offset, 0.0)
	_mute_model_collision(node)


func _show_capsule(visible_now: bool) -> void:
	for child in get_children():
		if child is MeshInstance3D:
			child.visible = visible_now


## How far the model's lowest point sits below the unit's own origin, with its
## scale already applied. Subtracting it puts the model's feet on the ground
## wherever the artist left the origin, at any size.
func _model_bottom(node: Node3D) -> float:
	var meshes: Array = []
	_collect_meshes(node, meshes)
	if meshes.is_empty():
		return 0.0

	var into_unit: Transform3D = global_transform.affine_inverse()
	var lowest: float = INF
	for mi in meshes:
		var box: AABB = into_unit * mi.global_transform * mi.get_aabb()
		lowest = minf(lowest, box.position.y)
	return 0.0 if lowest == INF else lowest


func _collect_meshes(node: Node, into: Array) -> void:
	if node is MeshInstance3D:
		into.append(node)
	for child in node.get_children():
		_collect_meshes(child, into)


## A model that shipped with a collision shape would sit on the unit layer and
## confuse the hover and click raycasts, so anything solid in it is switched
## off. The unit's own body is untouched.
func _mute_model_collision(node: Node) -> void:
	if node is CollisionObject3D:
		node.collision_layer = 0
		node.collision_mask = 0
	for child in node.get_children():
		_mute_model_collision(child)


func class_name_of() -> String:
	return character_class.display_name if character_class != null else "—"


## Move without walking. Subclasses override to clear their own movement
## state as well, then call super().
func teleport_to(where: Vector3) -> void:
	global_position = where
	velocity = Vector3.ZERO

# -------------------------------------------------------------------- health

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
	var shape := get_node_or_null("CollisionShape3D")
	if shape != null:
		shape.set_deferred("disabled", true)
	died.emit()

# ---------------------------------------------------------------------- mana

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

# ---------------------------------------------------------- armor, resisting

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


func resistances() -> Resistances:
	var base: Resistances = base_resistances if base_resistances != null else Resistances.new()
	var gear: Resistances = inventory.total_resistances() if inventory != null else null
	return base.combined(gear)


func resistance_to(kind: int) -> int:
	return resistances().get_for(kind) + talent_resistance_bonus(kind)

# ------------------------------------------------------------ stats, effects

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


## Apply an effect right now: instant healing lands immediately, a timed
## effect is held. Works in and out of combat.
func apply_effect_now(effect: Effect) -> void:
	if effect == null:
		return
	if effect.heals():
		heal(effect.roll_heal())
	if not effect.is_instant():
		add_effect(effect)


## Drink a consumable. Returns false if the item isn't drinkable.
func consume(item: Item) -> bool:
	if item == null or not item.is_consumable() or item.is_thrown():
		return false
	apply_effect_now(item.effect)
	return true


## Called at the start of this unit's turn.
func tick_effects() -> void:
	var expired: Array = effects.advance()
	if not expired.is_empty():
		effects_changed.emit()


func clear_effects() -> void:
	effects.clear()
	effects_changed.emit()


## Spending a point in health should hand over the point you just bought.
func _on_stat_raised(stat_name: String) -> void:
	if stat_name == "health":
		current_health += 1
		health_changed.emit(current_health, max_health())

# ------------------------------------------------------------------- talents

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

# ----------------------------------------------------------------- levelling

func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	xp = maxi(0, xp + amount)
	xp_changed.emit(xp)
	_check_level_up()


## Award a stat point and a talent point per level, however many at once.
func _check_level_up() -> void:
	var earned: int = Progression.level_for_xp(xp)
	while level < earned:
		level += 1
		if stats != null:
			stats.available_points += Progression.POINTS_PER_LEVEL
			stats.talent_points += 1
		print("%s reaches level %d." % [display_name, level])
		leveled_up.emit(level)

# -------------------------------------------------------- battle and saving

## The shared half of what the battle map needs to rebuild this unit.
## Subclasses add their own keys on top.
func to_unit_data() -> Dictionary:
	return {
		"display_name": display_name,
		"stats": stats,
		"character_class": character_class,
		"inventory": inventory,
		"spells": spells,
		"level": level,
		"xp": xp,
		"base_armor": base_armor,
		"base_resistances": base_resistances,
		"talent_ranks": talent_ranks.duplicate(),
		"model": model,
		"model_scale": model_scale,
		"model_rotation_degrees": model_rotation_degrees,
		"model_y_offset": model_y_offset,
	}


## Subclasses override and merge their own keys into the result.
func save_state() -> Dictionary:
	return {
		"stats": stats,
		"inventory": inventory,
		"character_class": character_class,
		"base_resistances": base_resistances,
		"talent_ranks": talent_ranks.duplicate(),
		"health": current_health,
		"mana": current_mana,
		"xp": xp,
		"level": level,
		"base_armor": base_armor,
	}


## Subclasses call super(data) first, then restore their own fields.
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
	xp = data.get("xp", xp)
	level = maxi(data.get("level", level), Progression.level_for_xp(xp))
	base_armor = data.get("base_armor", base_armor)
	current_health = data.get("health", max_health())
	current_mana = data.get("mana", max_mana())

	health_changed.emit(current_health, max_health())
	mana_changed.emit(current_mana, max_mana())
	xp_changed.emit(xp)
	armor_changed.emit(armor())
