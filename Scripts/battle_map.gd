extends Node3D
const HUD_SCENE_PATH := "res://scenes/combat_hud.tscn"
const COMBAT_CAMERA_PATH := "res://scenes/combat_camera.tscn"
const SPELL_BOOK_PATH := "res://scenes/spell_book.tscn"
const REACHABLE_TINT := Color(0.62, 0.72, 0.55)
const COLOR_OBSTACLE := Color(0.04, 0.04, 0.05)
const COLOR_ROUGH := Color(0.18, 0.32, 0.58)
const PREVIEW_TINT := Color(0.95, 0.82, 0.45)
const DEPLOY_TINT := Color(0.55, 0.9, 0.65)
const CAST_RANGE_TINT := Color(0.70, 0.62, 0.95)
const BLAST_TINT := Color(1.15, 0.45, 0.30)


@export var columns: int = 30
@export var rows: int = 40
@export var hex_size: float = 1.0
@export var hex_gap: float = 0.06
@export var tile_height: float = 0.15
@export var deploy_rows: int = 2
@export var movement_per_turn: int = 5
 
@export_range(0.0, 0.3) var obstacle_density: float = 0.05
@export_range(0.0, 1.0) var obstacle_spread: float = 0.2
@export var max_cluster_size: int = 8
 
@export_range(0.0, 0.3) var rough_density: float = 0.08
@export_range(0.0, 1.0) var rough_spread: float = 0.3
@export var max_rough_cluster: int = 12
 
## Toggle this if tiles don't interlock. One of the two will be correct.
@export var flat_top: bool = false:
	set(value):
		flat_top = value
		if is_node_ready():
			_rebuild()
 
signal deployment_ready

var _book: CanvasLayer = null
var _deploying: bool = false
var _grid: MultiMeshInstance3D
var _ground: StaticBody3D
var combat: Combat = null
var _hud: Control = null
var _reachable: Dictionary = {}
var _camera: Camera3D = null
var _units: Array = []
var _hexes: Dictionary = {}
var _obstacles: Dictionary = {}
var _rough: Dictionary = {}
var _enemies: Array = []
var _allies: Array = []
var _battle_over: bool = false
var _preview: Dictionary = {}
var _painted: Dictionary = {}          # hex -> Color currently on the mesh
var _hover_unit = null
var _portrait_hover = null
var _world_hover = null
var _deploy_tiles: Dictionary = {}
var _targeting: Spell = null
var _caster = null
var _cast_tiles: Dictionary = {}
var _blast_tiles: Dictionary = {}
var _xp_pool: int = 0
var _gold_pool: int = 0


func _ready() -> void:
	_rebuild()
 
func _rebuild() -> void:
	if _grid:
		_grid.queue_free()
		_grid = null
	if _ground:
		_ground.queue_free()
		_ground = null
	_generate_terrain()
	_build_ground()
	_build_grid()
 
# ------------------------------------------------------------- hex geometry
# Pointy-top: neighbours are left/right, rows stagger by half a tile.
# Flat-top:   neighbours are up/down, columns stagger by half a tile.
 
func _grid_local(col: int, row: int) -> Vector3:
	if flat_top:
		var fx: float = hex_size * 1.5 * col
		var fz: float = hex_size * sqrt(3.0) * (row + 0.5 * (col & 1))
		return Vector3(fx, 0.0, fz)
	var x: float = hex_size * sqrt(3.0) * (col + 0.5 * (row & 1))
	var z: float = hex_size * 1.5 * row
	return Vector3(x, 0.0, z)
 
func _span() -> Vector2:
	if flat_top:
		return Vector2(columns * hex_size * 1.5, rows * hex_size * sqrt(3.0))
	return Vector2(columns * hex_size * sqrt(3.0), rows * hex_size * 1.5)
 
func _origin_offset() -> Vector3:
	var s: Vector2 = _span()
	return Vector3(-s.x * 0.5, 0.0, -s.y * 0.5)
 
func hex_to_local(col: int, row: int) -> Vector3:
	return _grid_local(col, row) + _origin_offset()
 
func hex_to_world(col: int, row: int) -> Vector3:
	return to_global(hex_to_local(col, row) + Vector3(0.0, tile_height * 0.5, 0.0))
 
func world_to_hex(world_pos: Vector3) -> Vector2i:
	var local: Vector3 = to_local(world_pos) - _origin_offset()
	var q: float
	var r: float
	if flat_top:
		q = (2.0 / 3.0 * local.x) / hex_size
		r = (-1.0 / 3.0 * local.x + sqrt(3.0) / 3.0 * local.z) / hex_size
	else:
		q = (sqrt(3.0) / 3.0 * local.x - 1.0 / 3.0 * local.z) / hex_size
		r = (2.0 / 3.0 * local.z) / hex_size
 
	var axial: Vector2 = _axial_round(Vector2(q, r))
	var col: int
	var row: int
	if flat_top:
		col = int(axial.x)
		row = int(axial.y) + int((col - (col & 1)) / 2.0)
	else:
		row = int(axial.y)
		col = int(axial.x) + int((row - (row & 1)) / 2.0)
 
	return Vector2i(clampi(col, 0, columns - 1), clampi(row, 0, rows - 1))
 
 
func snap_to_hex(world_pos: Vector3) -> Vector3:
	var h: Vector2i = world_to_hex(world_pos)
	return hex_to_world(h.x, h.y)
 
 
## Offset coords are convenient for storage; cube coords are what distance
## math actually needs. This converts between them.
func _offset_to_axial(h: Vector2i) -> Vector2i:
	if flat_top:
		return Vector2i(h.x, h.y - int((h.x - (h.x & 1)) / 2.0))
	return Vector2i(h.x - int((h.y - (h.y & 1)) / 2.0), h.y)
 
 
func _axial_to_offset(a: Vector2i) -> Vector2i:
	if flat_top:
		return Vector2i(a.x, a.y + int((a.x - (a.x & 1)) / 2.0))
	return Vector2i(a.x + int((a.y - (a.y & 1)) / 2.0), a.y)
 
 
func hex_distance(a: Vector2i, b: Vector2i) -> int:
	var aa: Vector2i = _offset_to_axial(a)
	var bb: Vector2i = _offset_to_axial(b)
	var dq: int = aa.x - bb.x
	var dr: int = aa.y - bb.y
	return int((absi(dq) + absi(dq + dr) + absi(dr)) / 2.0)
 
func _axial_round(a: Vector2) -> Vector2:
	var x: float = a.x
	var z: float = a.y
	var y: float = -x - z
	var rx: float = roundf(x)
	var ry: float = roundf(y)
	var rz: float = roundf(z)
	var dx: float = absf(rx - x)
	var dy: float = absf(ry - y)
	var dz: float = absf(rz - z)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector2(rx, rz)
 
 
## The six adjacent hexes, clipped to the grid.
func hex_neighbors(h: Vector2i) -> Array:
	const DIRS := [
		Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
		Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
	]
	var axial: Vector2i = _offset_to_axial(h)
	var out: Array = []
	for d in DIRS:
		var n: Vector2i = _axial_to_offset(axial + d)
		if n.x >= 0 and n.x < columns and n.y >= 0 and n.y < rows:
			out.append(n)
	return out
 
 
func is_occupied(h: Vector2i) -> bool:
	if _obstacles.has(h):
		return true
	for u in _hexes.keys():
		if not is_instance_valid(u):
			continue
		if u.has_method("is_alive") and not u.is_alive():
			continue
		if _hexes[u] == h:
			return true
	return false
 
 
## Every living unit standing on a hex. Used by spells and terrain hazards.
func units_on_hex(h: Vector2i) -> Array:
	var out: Array = []
	for u in _hexes.keys():
		if not is_instance_valid(u):
			continue
		if u.has_method("is_alive") and not u.is_alive():
			continue
		if _hexes[u] == h:
			out.append(u)
	return out
 
# ---------------------------------------------------------------- building
 
func _build_ground() -> void:
	var s: Vector2 = _span()
	_ground = StaticBody3D.new()
	_ground.collision_layer = 1
	_ground.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(s.x + 6.0, 1.0, s.y + 6.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	_ground.add_child(shape)
	add_child(_ground)
 
func _build_grid() -> void:
	var mesh := CylinderMesh.new()
	mesh.radial_segments = 6
	mesh.rings = 1
	mesh.height = tile_height
	mesh.top_radius = hex_size - hex_gap
	mesh.bottom_radius = hex_size - hex_gap
 
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mesh.material = mat
 
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = columns * rows
 
	# CylinderMesh starts its first vertex at +Z, giving a pointy-top hex.
	# Flat-top needs that turned by half a segment (60/2 = 30 degrees).
	var basis := Basis(Vector3.UP, deg_to_rad(30.0)) if flat_top else Basis()
 
	var i: int = 0
	for row in rows:
		for col in columns:
			mm.set_instance_transform(i, Transform3D(basis, hex_to_local(col, row)))
			mm.set_instance_color(i, _tile_color(col, row))
			i += 1
 
	_grid = MultiMeshInstance3D.new()
	_grid.multimesh = mm
	add_child(_grid)
 
func _tile_color(col: int, row: int) -> Color:
	var h := Vector2i(col, row)
	if _obstacles.has(h):
		return COLOR_OBSTACLE
	if _rough.has(h):
		return COLOR_ROUGH
	if col < deploy_rows:
		return Color(0.24, 0.42, 0.30)
	if col >= columns - deploy_rows:
		return Color(0.44, 0.24, 0.24)
	return Color(0.34, 0.34, 0.38) if (col + row) % 2 == 0 else Color(0.29, 0.29, 0.33)
 
# ------------------------------------------------------------ world interface
 
func get_spawn_position(spawn_name: String) -> Vector3:
	var mid: int = int(rows / 2)
	if spawn_name == "EnemySpawn":
		return hex_to_world(columns - 2, mid)
	return hex_to_world(1, mid)
 
func setup_battle(player: Node, enemy_group: Dictionary, ally_data: Array = []) -> void:
	_units = [player]
	_hexes[player] = world_to_hex(player.global_position)
	HealthTag.attach(player)
	if player.has_signal("died"):
		player.died.connect(_on_unit_died.bind(player))
 
	var ally_slots: Array = _deploy_slots(ally_data.size(), false)
	for i in ally_data.size():
		if i >= ally_slots.size():
			break
		var ally = _spawn_unit(ally_data[i], ally_slots[i], NPC.Faction.ALLY)
		if ally:
			_allies.append(ally)
			_units.append(ally)
 
	var members: Array = enemy_group.get("members", [])
	var enemy_slots: Array = _random_deploy_slots(members.size(), true)
	for i in members.size():
		if i >= enemy_slots.size():
			break
		var foe = _spawn_unit(members[i], enemy_slots[i], NPC.Faction.ENEMY)
		if foe:
			_enemies.append(foe)
			_units.append(foe)
 
	var cam_packed: PackedScene = load(COMBAT_CAMERA_PATH)
	if cam_packed:
		_camera = cam_packed.instantiate()
		add_child(_camera)
		var s: Vector2 = _span()
		_camera.set_bounds(
			Vector2(global_position.x - s.x * 0.5, global_position.z - s.y * 0.5),
			Vector2(global_position.x + s.x * 0.5, global_position.z + s.y * 0.5)
		)
		_camera.focus_on(player.global_position)
 
	_begin_deployment()
 
 
## Free repositioning inside the friendly band, before initiative is rolled.
func _begin_deployment() -> void:
	_deploying = true
	_highlight_deploy_zone()
	SelectionRing.attach(Game.player)
 
	var hud_packed: PackedScene = load(HUD_SCENE_PATH)
	if hud_packed:
		_hud = hud_packed.instantiate()
		add_child(_hud)
		_hud.show_deployment()
		_hud.deployment_confirmed.connect(_finish_deployment)
 
 
func _finish_deployment() -> void:
	if not _deploying:
		return
	_deploying = false
	set_deploy_selection(null)
	_deploy_tiles.clear()
	_repaint()

	combat = Combat.new()
	combat.name = "Combat"
	add_child(combat)
	combat.budget_for = _movement_for
	combat.is_player_side = _is_player_side
	combat.ai_phase = _run_ai_turn
	combat.setup(_units)

	_hud.bind(combat)
	_hud.unit_hovered.connect(set_portrait_hover)
	_hud.unit_unhovered.connect(func(): set_portrait_hover(null))

	var book_packed: PackedScene = load(SPELL_BOOK_PATH)
	if book_packed:
		_book = book_packed.instantiate()
		add_child(_book)
		_book.spell_chosen.connect(_on_spell_chosen)

	combat.movement_changed.connect(_on_movement_changed)
	combat.turn_changed.connect(func(_u, _r, _p):
		cancel_targeting()
		if _book != null:
			_book.close()
		_refresh_preview()
	)
	combat.begin()
	
 
## Free hexes in a deploy band, filling outward from the centre row.
func _deploy_slots(count: int, enemy_side: bool) -> Array:
	var mid: int = int(rows / 2)
	var band: Array = []
	for i in deploy_rows:
		band.append(columns - 1 - i if enemy_side else i)
 
	var offsets: Array = [0]
	for d in range(1, rows):
		offsets.append(d)
		offsets.append(-d)
 
	var slots: Array = []
	for off in offsets:
		for c in band:
			var row: int = mid + off
			if row < 0 or row >= rows:
				continue
			var h := Vector2i(c, row)
			if is_occupied(h) or slots.has(h):
				continue
			slots.append(h)
			if slots.size() >= count:
				return slots
	return slots
 
 
## Every free hex in a deploy band, shuffled.
func _random_deploy_slots(count: int, enemy_side: bool) -> Array:
	var band: Array = []
	for i in deploy_rows:
		band.append(columns - 1 - i if enemy_side else i)
 
	var free: Array = []
	for c in band:
		for row in rows:
			var h := Vector2i(c, row)
			if not is_occupied(h):
				free.append(h)
 
	free.shuffle()
	return free.slice(0, mini(count, free.size()))
 
 
func _spawn_unit(data: Dictionary, at: Vector2i, faction: int):
	var path: String = data.get("scene_override", "")
	if path.is_empty():
		path = "res://scenes/npc.tscn"
	var packed: PackedScene = load(path)
	if packed == null:
		push_error("BattleMap: could not load unit scene at %s" % path)
		return null

	var unit = packed.instantiate()
	add_child(unit)
	unit.global_position = hex_to_world(at.x, at.y)
	unit.display_name = data.get("display_name", "Unit")
	unit.faction = faction
	unit.level = data.get("level", 1)
	unit.base_armor = data.get("base_armor", 0)
	if data.get("base_resistances") != null:
		unit.base_resistances = data["base_resistances"].duplicate()
	if data.get("character_class") != null:
		unit.character_class = data["character_class"]
	if data.get("stats") != null:
		unit.stats = data["stats"].duplicate()
		unit.current_health = unit.max_health()
	unit.current_mana = unit.max_mana()

	if data.get("spells") != null:
		unit.spells = data["spells"].duplicate()

	# an existing inventory (an ally's) wins; otherwise build one from the loadout
	if data.get("inventory") != null:
		unit.inventory = data["inventory"]
	else:
		unit.inventory = _build_loadout(data.get("equipment", []))

	if data.get("ai") != null:
		unit.ai = data["ai"]

	unit.set_meta("xp_reward", data.get("xp_reward", 0))
	unit.set_meta("gold_reward", data.get("gold", 0))

	unit.stop_following()
	_hexes[unit] = at
	HealthTag.attach(unit)
	if unit.has_signal("died"):
		unit.died.connect(_on_unit_died.bind(unit))
	return unit


## Fresh inventory with the template's gear worn. Items are duplicated so
## three pirates don't share one cutlass.
func _build_loadout(equipment: Array) -> Inventory:
	var inv := Inventory.new()
	for item in equipment:
		if item == null:
			continue
		var copy: Item = item.duplicate()
		if copy.slot == Item.Slot.NONE:
			inv.items.append(copy)
		else:
			inv.items.append(copy)
			inv.equip(copy)
	return inv
 
func _is_player_side(unit) -> bool:
	return not _enemies.has(unit)
 
 
## Whoever the player can command right now, or null.
func get_controlled_unit():
	if _deploying:
		return null          # clicks route through _active_actor's fallback
	if combat == null:
		return null
	return combat.active if combat.player_controlled() else null
 
 
func is_deploying() -> bool:
	return _deploying
 
 
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	if event.keycode == KEY_ESCAPE:
		if _book != null and _book.is_open():
			_book.close()
		elif _targeting != null:
			cancel_targeting()
		else:
			Game.end_battle()
	elif event.keycode == KEY_B:
		_toggle_spell_book()
 
 
func _highlight_deploy_zone() -> void:
	_deploy_tiles.clear()
	for row in rows:
		for col in deploy_rows:
			var h := Vector2i(col, row)
			if not _obstacles.has(h):
				_deploy_tiles[h] = true
	_repaint()
 
 
func set_deploy_selection(unit) -> void:
	for u in _units:
		if is_instance_valid(u):
			SelectionRing.clear(u)
	if unit != null and is_instance_valid(unit):
		SelectionRing.attach(unit)
 
 
## Returns an Array of world positions to walk through, or null if refused.
func request_move(unit, to: Vector3):
	if _deploying:
		return _deploy_move(unit, to)
	if combat == null:
		return [snap_to_hex(to)]
	if unit != combat.active or not combat.player_controlled():
		return null
 
	var from_hex: Vector2i = _hexes.get(unit, world_to_hex(unit.global_position))
	var to_hex: Vector2i = world_to_hex(to)
	if to_hex == from_hex or is_occupied(to_hex):
		return null
 
	_hexes.erase(unit)                       # don't path around ourselves
	var path: Array = find_path(from_hex, to_hex)
	_hexes[unit] = from_hex
 
	if path.is_empty():
		print("No path there.")
		return null
 
	var cost: int = path_cost(path)
	if not combat.can_afford(cost):
		print("Too far — %d points needed, %d left." % [cost, combat.movement_left])
		return null
 
	_hexes[unit] = to_hex
	combat.spend(cost)
 
	var waypoints: Array = []
	for h in path:
		waypoints.append(hex_to_world(h.x, h.y))
	return waypoints
 
 
## No cost, no pathing — just teleport within the band.
func _deploy_move(unit, to: Vector3):
	if not _is_player_side(unit):
		return null
	var to_hex: Vector2i = world_to_hex(to)
	if not _deploy_tiles.has(to_hex) or is_occupied(to_hex):
		return null
 
	_hexes[unit] = to_hex
	if unit.has_method("teleport_to"):
		unit.teleport_to(hex_to_world(to_hex.x, to_hex.y))
	else:
		unit.global_position = hex_to_world(to_hex.x, to_hex.y)
	return null          # teleported already, no path to walk
 
# ------------------------------------------------------------------ attacking
 
## Melee attack: must be in reach, costs the turn's action.
func request_attack(attacker, target) -> bool:
	if combat == null or attacker != combat.active or not combat.can_act():
		return false
	if target == null or not is_instance_valid(target):
		return false
	if target.has_method("is_alive") and not target.is_alive():
		return false
	if _is_player_side(attacker) == _is_player_side(target):
		print("Won't attack an ally.")
		return false
 
	var a: Vector2i = _hexes.get(attacker, world_to_hex(attacker.global_position))
	var b: Vector2i = _hexes.get(target, world_to_hex(target.global_position))
	var distance: int = hex_distance(a, b)
	if distance > _max_range_of(attacker):
		print("Out of range.")
		return false
 
	combat.spend_action()
	_strike(attacker, target, distance)
	return true
 
 
## Same hit, without the player-turn checks — used by the AI.
func _ai_attack(attacker, target) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target.has_method("is_alive") and not target.is_alive():
		return false
	var a: Vector2i = _hexes.get(attacker, world_to_hex(attacker.global_position))
	var b: Vector2i = _hexes.get(target, world_to_hex(target.global_position))
	var distance: int = hex_distance(a, b)
	if distance > _max_range_of(attacker):
		return false
	_strike(attacker, target, distance)
	return true
 
 
func _strike(attacker, target, distance: int) -> void:
	var strength: int = 1
	if unit_has_stat(attacker):
		strength = attacker.modified_stat("strength")
 
	var weapon: Item = _weapon_of(attacker)
	var roll: int = weapon.roll_damage() if weapon != null else 0
	var raw: int = strength + roll
 
	# crits multiply before range falloff and armor
	var crit: bool = Damage.rolls_crit(attacker, weapon)
	if crit:
		raw = Damage.apply_crit(raw)
 
	var long_shot: bool = weapon != null and weapon.is_long_shot(distance)
	if long_shot:
		raw = maxi(1, int(raw / 2.0))

	var kind: int = weapon.damage_type if weapon != null else DamageType.Kind.BLUNT
	var armor: int = Damage.armor_of(target)
	var dealt: int = Damage.mitigate(raw, target, kind)
	var defence: int = Damage.defence_against(target, kind)

	_face_unit(attacker, target)
	print("%s hits %s for %d %s (raw %d, defence %d)%s%s" % [
		_name_of(attacker), _name_of(target), dealt,
		DamageType.label(kind).to_lower(), raw, defence,
		" CRIT" if crit else "",
		" [long shot]" if long_shot else ""
	])
	DamageNumber.spawn(target, dealt, "crit" if crit else ("blocked" if long_shot else "damage"), kind)
	target.take_damage(dealt)
 
 
func _weapon_of(unit) -> Item:
	if not "inventory" in unit or unit.inventory == null:
		return null
	var item: Item = unit.inventory.get_equipped(Item.Slot.MAIN_HAND)
	return item if item != null and item.is_weapon() else null
 
 
## Furthest hex this unit can strike at all.
func _max_range_of(unit) -> int:
	var weapon: Item = _weapon_of(unit)
	return weapon.max_range() if weapon != null else 1
 
 
func _face_unit(unit, target) -> void:
	var flat := Vector3(target.global_position.x, unit.global_position.y, target.global_position.z)
	if flat.distance_to(unit.global_position) > 0.01:
		unit.look_at(flat, Vector3.UP)
 
 
func _name_of(unit) -> String:
	return unit.display_name if "display_name" in unit else "Unit"
 
 
func unit_has_stat(unit) -> bool:
	return unit != null and unit.has_method("modified_stat") and "stats" in unit and unit.stats != null
 
 
func _on_unit_died(unit) -> void:
	print("%s is down." % _name_of(unit))
	_hexes.erase(unit)
	if _hover_unit == unit:
		_hover_unit = null
		_portrait_hover = null
		_world_hover = null
		_refresh_preview()
	_refresh_reachable()
	if combat != null:
		combat.order_changed.emit(combat.order)
	if _enemies.has(unit):
		_xp_pool += unit.get_meta("xp_reward", 0)
		_gold_pool += unit.get_meta("gold_reward", 0)
	_check_battle_over()
 
 
func _check_battle_over() -> void:
	if _battle_over:
		return
	var enemies_up: bool = false
	var players_up: bool = false
	for u in _units:
		if not is_instance_valid(u):
			continue
		if u.has_method("is_alive") and not u.is_alive():
			continue
		if _enemies.has(u):
			enemies_up = true
		else:
			players_up = true
 
	if not enemies_up or not players_up:
		_battle_over = true
		if not enemies_up:
			print("Victory.")
			_award_rewards()
		else:
			print("Defeat.")
		for u in _units:
			if is_instance_valid(u) and u.has_method("clear_effects"):
				u.clear_effects()
		Game.end_battle.call_deferred()
 
# ------------------------------------------------------------------- spells
 
func is_targeting() -> bool:
	return _targeting != null
 
 
## Every spell this unit can cast: its own list plus its class's.
func _spells_of(unit) -> Array:
	var out: Array = []
	if "spells" in unit and unit.spells != null:
		for s in unit.spells:
			if s != null:
				out.append(s)
	if "character_class" in unit and unit.character_class != null:
		for s in unit.character_class.spells:
			if s != null and not out.has(s):
				out.append(s)
	return out
 
 
func _try_begin_targeting(index: int) -> void:
	if combat == null or _deploying or _battle_over:
		return
	var caster = get_controlled_unit()
	if caster == null:
		return
	if not combat.can_act():
		print("No action left this turn.")
		return
 
	var known: Array = _spells_of(caster)
	if index >= known.size():
		print("No spell in slot %d." % (index + 1))
		return
 
	var spell: Spell = known[index]
	var mana: int = caster.current_mana if "current_mana" in caster else 0
	if mana < spell.mana_cost:
		print("Not enough mana for %s (%d needed, %d left)." % [
			spell.display_name, spell.mana_cost, mana
		])
		return
 
	_targeting = spell
	_caster = caster
	_cast_tiles = _hexes_within(_hexes[caster], spell.cast_range)
	_blast_tiles.clear()
	_repaint()
	print("Targeting %s — left click to cast, Escape to cancel." % spell.display_name)
 
 
func cancel_targeting() -> void:
	_targeting = null
	_caster = null
	_cast_tiles.clear()
	_blast_tiles.clear()
	_repaint()
 
 
## Straight-line hex distance, ignoring obstacles — spells don't walk.
func _hexes_within(centre: Vector2i, radius: int) -> Dictionary:
	var out: Dictionary = {}
	for row in range(maxi(0, centre.y - radius - 1), mini(rows, centre.y + radius + 2)):
		for col in range(maxi(0, centre.x - radius - 1), mini(columns, centre.x + radius + 2)):
			var h := Vector2i(col, row)
			if hex_distance(centre, h) <= radius:
				out[h] = true
	return out
 
 
func _update_blast() -> void:
	var centre: Vector2i = _hex_under_mouse()
	var next: Dictionary = {}
	if centre.x >= 0 and _cast_tiles.has(centre):
		next = _hexes_within(centre, _targeting.radius)
 
	if next.size() == _blast_tiles.size() and (next.is_empty() or next.keys()[0] == _blast_tiles.keys()[0]):
		return                                  # nothing moved, skip the repaint
	_blast_tiles = next
	_repaint()
 
 
func _hex_under_mouse() -> Vector2i:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector2i(-1, -1)
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var from: Vector3 = cam.project_ray_origin(mouse)
	var to: Vector3 = from + cam.project_ray_normal(mouse) * 1000.0
 
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 2)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.has("position"):
		return Vector2i(-1, -1)
	return world_to_hex(hit["position"])
 
 
func confirm_cast(world_pos: Vector3) -> bool:
	if _targeting == null or _caster == null:
		return false
	var centre: Vector2i = world_to_hex(world_pos)
	if not _cast_tiles.has(centre):
		print("Out of range.")
		return false
	if not combat.can_act():
		cancel_targeting()
		return false
 
	var spell: Spell = _targeting
	var caster = _caster
	var area: Dictionary = _hexes_within(centre, spell.radius)
 
	if caster.has_method("spend_mana") and not caster.spend_mana(spell.mana_cost):
		cancel_targeting()
		return false
	combat.spend_action()
 
	var power: int = 0
	if unit_has_stat(caster):
		power = caster.modified_stat("magic_power")
 
	var caster_side: bool = _is_player_side(caster)
	print("%s casts %s at %s" % [_name_of(caster), spell.display_name, centre])
 
	for unit in _units:
		if not is_instance_valid(unit):
			continue
		if unit.has_method("is_alive") and not unit.is_alive():
			continue
		if not _hexes.has(unit) or not area.has(_hexes[unit]):
			continue
		if not spell.affects(caster_side, _is_player_side(unit)):
			continue
 
		if spell.deals_damage():
			var raw: int = power + spell.roll_damage()
			var dealt: int = Damage.mitigate(raw, unit, spell.damage_type)
			print("  %s takes %d %s (raw %d)" % [
				_name_of(unit), dealt, DamageType.label(spell.damage_type).to_lower(), raw
			])
			DamageNumber.spawn(unit, dealt, "damage", spell.damage_type)
			unit.take_damage(dealt)
 
		if spell.effect != null:
			apply_effect_to(unit, spell.effect)
 
	cancel_targeting()
	_refresh_reachable()
	return true
 
 
## Public entry point for anything that applies an effect: spells now, and
## later terrain hazards, traps, or auras. Nothing else needs to know how
## effects are stored on a unit.
func apply_effect_to(unit, effect: Effect) -> void:
	if unit == null or not is_instance_valid(unit) or effect == null:
		return
	if not unit.has_method("add_effect"):
		return
	unit.add_effect(effect)
	print("  %s gains %s for %d turns." % [
		_name_of(unit), effect.display_name, effect.duration
	])
	_refresh_reachable()      # haste may have changed
 
 
## Apply an effect to everyone in an area. For fire fields, gas clouds, auras.
func apply_effect_to_area(centre: Vector2i, radius: int, effect: Effect) -> void:
	var area: Dictionary = _hexes_within(centre, radius)
	for h in area.keys():
		for unit in units_on_hex(h):
			apply_effect_to(unit, effect)
 
# ------------------------------------------------------------ tile highlight
 
func _on_movement_changed(_remaining: int, _maximum: int) -> void:
	_refresh_reachable()
 
 
## The active unit's remaining range, in green.
func _refresh_reachable() -> void:
	if combat == null:
		_reachable = {}
		_repaint()
		return
 
	var next: Dictionary = {}
	var actor = get_controlled_unit()
	if actor != null and combat.movement_left > 0:
		next = _range_for(actor, combat.movement_left)
	_reachable = next
	_repaint()
 
 
## What the hovered unit could reach on a full turn, in amber.
func _refresh_preview() -> void:
	var next: Dictionary = {}
	var unit = _hover_unit
 
	var valid: bool = unit != null and is_instance_valid(unit) and _hexes.has(unit)
	if valid and unit.has_method("is_alive") and not unit.is_alive():
		valid = false
	if valid and combat != null and unit == combat.active:
		valid = false          # already shown in green
 
	if valid:
		next = _range_for(unit, _movement_for(unit))
 
	_preview = next
	_repaint()
 
 
## Reachable set from a unit's hex, ignoring its own body as an obstacle.
func _range_for(unit, budget: int) -> Dictionary:
	if not _hexes.has(unit) or budget <= 0:
		return {}
	var origin: Vector2i = _hexes[unit]
	_hexes.erase(unit)
	var result: Dictionary = reachable_hexes(origin, budget)
	_hexes[unit] = origin
	return result
 
 
## Build the target colour for every tinted tile, then push only the changes.
func _repaint() -> void:
	if _grid == null:
		return
 
	var desired: Dictionary = {}
	for h in _deploy_tiles.keys():
		desired[h] = _tile_color(h.x, h.y) * DEPLOY_TINT
	for h in _reachable.keys():
		desired[h] = _tile_color(h.x, h.y) * REACHABLE_TINT
	for h in _preview.keys():
		desired[h] = _tile_color(h.x, h.y) * PREVIEW_TINT
	for h in _cast_tiles.keys():
		desired[h] = _tile_color(h.x, h.y) * CAST_RANGE_TINT
	for h in _blast_tiles.keys():
		desired[h] = _tile_color(h.x, h.y) * BLAST_TINT
 
	var mm: MultiMesh = _grid.multimesh
 
	for h in _painted.keys():
		if not desired.has(h):
			mm.set_instance_color(h.y * columns + h.x, _tile_color(h.x, h.y))
 
	for h in desired.keys():
		if _painted.get(h) != desired[h]:
			mm.set_instance_color(h.y * columns + h.x, desired[h])
 
	_painted = desired
 
# ---------------------------------------------------------------- hovering
 
func set_portrait_hover(unit) -> void:
	_portrait_hover = unit
	_resolve_hover()
 
 
func _resolve_hover() -> void:
	# a portrait beats whatever the cursor is over in the 3D view
	var next = _portrait_hover if _portrait_hover != null else _world_hover
	if next == _hover_unit:
		return
	_hover_unit = next
	_refresh_preview()
 
 
func _process(_delta: float) -> void:
	if _targeting != null:
		_update_blast()
		return
	if combat == null:
		return
	var found = _unit_under_mouse()
	if found != _world_hover:
		_world_hover = found
		_resolve_hover()
 
 
func _unit_under_mouse():
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var from: Vector3 = cam.project_ray_origin(mouse)
	var to: Vector3 = from + cam.project_ray_normal(mouse) * 1000.0
 
	var query := PhysicsRayQueryParameters3D.create(from, to, 2)   # layer 2 = units
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
 
	var collider = hit.get("collider")
	return collider if collider != null and _hexes.has(collider) else null
 
 
func _movement_for(unit: Node) -> int:
	if unit_has_stat(unit):
		return unit.modified_stat("haste")
	return movement_per_turn
 
# ------------------------------------------------------------------- enemy AI
 
func _run_ai_turn(unit) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if unit.has_method("is_alive") and not unit.is_alive():
		return
	await get_tree().create_timer(0.35).timeout
	if _battle_over:
		return
 
	var target = _nearest_player_unit(unit)
	if target == null:
		return
 
	var from_hex: Vector2i = _hexes[unit]
	var brain: CombatAI = unit.ai if unit.ai != null else CombatAI.new()
 
	_hexes.erase(unit)
	var destination: Vector2i = brain.plan_move(self, from_hex, _hexes[target], _movement_for(unit))
	_hexes[unit] = from_hex
 
	if destination != from_hex:
		var path: Array = find_path(from_hex, destination)
		if not path.is_empty():
			_hexes[unit] = destination
			var points: Array = []
			for h in path:
				points.append(hex_to_world(h.x, h.y))
			unit.walk_path(points)
			await unit.walk_finished
 
	if _battle_over:
		return
	if _ai_attack(unit, target):
		await get_tree().create_timer(0.4).timeout
 
	await get_tree().create_timer(0.3).timeout
 
 
func _nearest_player_unit(from_unit):
	var best = null
	var best_d: int = 1 << 30
	for u in _units:
		if not is_instance_valid(u) or _enemies.has(u):
			continue
		if u.has_method("is_alive") and not u.is_alive():
			continue
		if not _hexes.has(u):
			continue
		var d: int = hex_distance(_hexes[from_unit], _hexes[u])
		if d < best_d:
			best_d = d
			best = u
	return best
 
# ---------------------------------------------------------------- pathfinding
 
func find_path(from: Vector2i, to: Vector2i) -> Array:
	if from == to or is_occupied(to):
		return []
 
	var frontier: Array = [from]
	var came_from: Dictionary = {from: from}
	var cost_so_far: Dictionary = {from: 0}
 
	while not frontier.is_empty():
		# cheapest open node by (cost so far + estimate remaining)
		var best_i: int = 0
		var best_score: int = cost_so_far[frontier[0]] + hex_distance(frontier[0], to)
		for i in range(1, frontier.size()):
			var score: int = cost_so_far[frontier[i]] + hex_distance(frontier[i], to)
			if score < best_score:
				best_score = score
				best_i = i
 
		var current: Vector2i = frontier[best_i]
		frontier.remove_at(best_i)
		if current == to:
			break
 
		for n in hex_neighbors(current):
			if is_occupied(n):
				continue
			var next_cost: int = cost_so_far[current] + move_cost(n)
			if not cost_so_far.has(n) or next_cost < cost_so_far[n]:
				cost_so_far[n] = next_cost
				came_from[n] = current
				frontier.append(n)
 
	if not came_from.has(to):
		return []
 
	var path: Array = []
	var node: Vector2i = to
	while node != from:
		path.push_front(node)
		node = came_from[node]
	return path
 
 
## Dijkstra rather than BFS, because hexes no longer all cost the same.
func reachable_hexes(from: Vector2i, budget: int) -> Dictionary:
	var dist: Dictionary = {from: 0}
	var open: Array = [from]
 
	while not open.is_empty():
		var best_i: int = 0
		for i in range(1, open.size()):
			if dist[open[i]] < dist[open[best_i]]:
				best_i = i
		var current: Vector2i = open[best_i]
		open.remove_at(best_i)
 
		var d: int = dist[current]
		for n in hex_neighbors(current):
			if is_occupied(n):
				continue
			var next_cost: int = d + move_cost(n)
			if next_cost > budget:
				continue
			if not dist.has(n) or next_cost < dist[n]:
				dist[n] = next_cost
				open.append(n)
 
	dist.erase(from)
	return dist
 
# -------------------------------------------------------------------- terrain
 
func _generate_terrain() -> void:
	_obstacles.clear()
	_rough.clear()
	_scatter(_obstacles, obstacle_density, obstacle_spread, max_cluster_size)
	_scatter(_rough, rough_density, rough_spread, max_rough_cluster)
 
 
## Scatter seeds, then grow each into its neighbours. Growing rather than
## placing individually is what produces clumps instead of confetti.
func _scatter(into: Dictionary, density: float, spread: float, max_cluster: int) -> void:
	var target: int = int(columns * rows * density)
	if target <= 0:
		return
 
	var guard: int = 0
	while into.size() < target and guard < target * 40:
		guard += 1
		var seed_hex := Vector2i(randi() % columns, randi() % rows)
		if not _is_free_ground(seed_hex, into):
			continue
		_grow_cluster(into, seed_hex, target, spread, max_cluster)
 
 
func _grow_cluster(into: Dictionary, start: Vector2i, target: int, spread: float, max_cluster: int) -> void:
	var queue: Array = [start]
	into[start] = true
	var placed: int = 1
 
	while not queue.is_empty() and placed < max_cluster and into.size() < target:
		var current: Vector2i = queue.pop_front()
		for n in hex_neighbors(current):
			if not _is_free_ground(n, into):
				continue
			if randf() > spread:
				continue
			into[n] = true
			queue.append(n)
			placed += 1
			if placed >= max_cluster or into.size() >= target:
				break
 
 
## Nothing generates into a deploy zone or on top of existing terrain.
func _is_free_ground(h: Vector2i, into: Dictionary) -> bool:
	if into.has(h) or _obstacles.has(h) or _rough.has(h):
		return false
	return not _in_deploy_zone(h)
 
 
func _in_deploy_zone(h: Vector2i) -> bool:
	return h.x < deploy_rows or h.x >= columns - deploy_rows
 
 
func is_obstacle(h: Vector2i) -> bool:
	return _obstacles.has(h)
 
 
## Movement points to enter this hex.
func move_cost(h: Vector2i) -> int:
	return 2 if _rough.has(h) else 1
 
 
## Total cost of a path (which excludes the starting hex).
func path_cost(path: Array) -> int:
	var total: int = 0
	for h in path:
		total += move_cost(h)
	return total
 
func _toggle_spell_book() -> void:
	if _book == null or combat == null or _deploying or _battle_over:
		return
	var caster = get_controlled_unit()
	if caster == null:
		_book.close()
		return
	_book.toggle(caster, _spells_of(caster))


func _on_spell_chosen(index: int) -> void:
	_book.close()
	_try_begin_targeting(index)


## XP is split evenly among survivors; gold all goes to the player.
func _award_rewards() -> void:
	var survivors: Array = []
	for u in _units:
		if not is_instance_valid(u) or _enemies.has(u):
			continue
		if u.has_method("is_alive") and not u.is_alive():
			continue
		survivors.append(u)

	if survivors.is_empty():
		return

	var share: int = maxi(1, int(_xp_pool / float(survivors.size())))
	for u in survivors:
		if u.has_method("add_xp"):
			u.add_xp(share)
			print("  %s gains %d xp." % [_name_of(u), share])

	if _gold_pool > 0 and Game.player != null and Game.player.has_method("add_gold"):
		Game.player.add_gold(_gold_pool)
		print("  Looted %d gold." % _gold_pool)

	Game.record_battle_results(_xp_pool, survivors)
