extends Node3D
const HUD_SCENE_PATH := "res://scenes/combat_hud.tscn"
const COMBAT_CAMERA_PATH := "res://scenes/combat_camera.tscn"
const SPELL_BOOK_PATH := "res://scenes/spell_book.tscn"
const RESULTS_SCENE_PATH := "res://scenes/battle_results.tscn"
const GRID_SHADER_PATH := "res://shaders/hex_grid.gdshader"
const REACHABLE_TINT := Color(0.62, 0.72, 0.55)
const PREVIEW_TINT := Color(0.95, 0.82, 0.45)
const DEPLOY_TINT := Color(0.55, 0.9, 0.65)
const CAST_RANGE_TINT := Color(0.70, 0.62, 0.95)
const BLAST_TINT := Color(1.15, 0.45, 0.30)

@export var columns: int = 30
@export var rows: int = 40
@export var hex_size: float = 1.0
@export var hex_gap: float = 0.00
@export var tile_height: float = 0.001
@export var deploy_rows: int = 2
@export var movement_per_turn: int = 5

## Leave empty to roll a random map from res://terrain/ each battle. Set it to
## pin this scene to one kind, which is what you want while you're tuning.
@export var terrain: BattleTerrain

@export_group("Grid look")
@export var edge_color: Color = Color(0.45, 0.85, 0.25, 0.85)
@export_range(0.0, 0.5) var edge_width: float = 0.07
## How solid a plain walkable tile is. 0 is outline only.
@export_range(0.0, 1.0) var fill_alpha: float = 0.0
## How solid a tile goes when the game highlights it.
@export_range(0.0, 1.0) var highlight_alpha: float = 0.45
## Only touch this if outlines come out as six-pointed stars.
@export_range(0.0, 60.0) var edge_rotation_degrees: float = 0.0

@export_group("Projectiles")
@export var projectile_scene: PackedScene
@export var projectile_height: float = 1.1    ## launch and impact height

## Toggle this if tiles don't interlock. One of the two will be correct.
@export var flat_top: bool = false:
	set(value):
		flat_top = value
		if is_node_ready():
			_rebuild()

signal deployment_ready

var combat: Combat = null
var battle_log: BattleLog = BattleLog.new()

var _book: CanvasLayer = null
var _deploying: bool = false
var _grid: MultiMeshInstance3D
var _ground: StaticBody3D               # the invisible slab clicks land on
var _ground_art: MeshInstance3D         # the sheet of grass/brick you see
var _props: Node3D                      # trees and rocks on the obstacle tiles
var _hud: Control = null
var _reachable: Dictionary = {}
var _camera: Camera3D = null
var _units: Array = []
var _hexes: Dictionary = {}
var _obstacles: Dictionary = {}
var _rough: Dictionary = {}
var _terrain: BattleTerrain = null      # the kind rolled for this battle
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
var _spoils: Inventory = Inventory.new()
var _thrown_item: Item = null          # consumed when a thrown item lands


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if _grid:
		_grid.queue_free()
		_grid = null
	if _ground:
		_ground.queue_free()
		_ground = null
	if _ground_art:
		_ground_art.queue_free()
		_ground_art = null
	if _props:
		_props.queue_free()
		_props = null
	_generate_terrain()
	_build_ground()
	_build_ground_art()
	_build_grid()
	_build_props()

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


## The visible ground, one flat sheet sitting just under the hexes. It's art
## only — `_build_ground` above is what raycasts hit, and the two are kept
## apart so changing how the map looks can't break how it's clicked.
func _build_ground_art() -> void:
	var t: BattleTerrain = active_terrain()
	var s: Vector2 = _span()

	var mesh := PlaneMesh.new()
	# overhang, so the sheet doesn't stop exactly at the outermost hex edge
	mesh.size = Vector2(s.x + hex_size * 4.0, s.y + hex_size * 4.0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = t.ground_color
	mat.roughness = 1.0
	mat.metallic = 0.0

	if t.ground_texture != null:
		mat.albedo_texture = t.ground_texture
		mat.texture_repeat = true
		# one copy of the texture per `ground_texture_scale` hexes, measured
		# the same way on both axes so the image never comes out stretched
		var world_per_copy: float = maxf(0.001, hex_size * 2.0 * t.ground_texture_scale)
		mat.uv1_scale = Vector3(mesh.size.x / world_per_copy, mesh.size.y / world_per_copy, 1.0)

	mesh.material = mat

	_ground_art = MeshInstance3D.new()
	_ground_art.mesh = mesh
	# just under the bottom face of the tiles
	_ground_art.position = Vector3(0.0, -tile_height * 0.5 - 0.005, 0.0)
	add_child(_ground_art)


## The outline shader when it's there, solid tiles when it isn't — so the map
## still draws if the shader hasn't been added to the project yet.
func _grid_material() -> Material:
	if not ResourceLoader.exists(GRID_SHADER_PATH):
		var solid := StandardMaterial3D.new()
		solid.vertex_color_use_as_albedo = true
		solid.roughness = 0.95
		return solid

	var mat := ShaderMaterial.new()
	mat.shader = load(GRID_SHADER_PATH)
	mat.set_shader_parameter("edge_color", edge_color)
	mat.set_shader_parameter("hex_radius", hex_size - hex_gap)
	mat.set_shader_parameter("edge_width", edge_width)
	mat.set_shader_parameter("edge_rotation_degrees", edge_rotation_degrees)
	return mat


func _build_grid() -> void:
	var mesh := CylinderMesh.new()
	mesh.radial_segments = 6
	mesh.rings = 1
	mesh.height = tile_height
	mesh.top_radius = hex_size - hex_gap
	mesh.bottom_radius = hex_size - hex_gap

	mesh.material = _grid_material()

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = columns * rows

	# CylinderMesh starts its first vertex at +Z, giving a pointy-top hex.
	# Flat-top needs that turned by half a segment (60/2 = 30 degrees).
	var basis := Basis(Vector3.UP, deg_to_rad(30.0)) if flat_top else Basis()

	# A MultiMesh has no way to skip an instance, so a tile that's been handed
	# over to a model is scaled to nothing instead. It keeps its index, which
	# is what every highlight layer addresses it by.
	var gone := basis.scaled(Vector3.ZERO)

	var i: int = 0
	for row in rows:
		for col in columns:
			var b: Basis = gone if _tile_replaced(Vector2i(col, row)) else basis
			mm.set_instance_transform(i, Transform3D(b, hex_to_local(col, row)))
			mm.set_instance_color(i, _tile_color(col, row))
			i += 1

	_grid = MultiMeshInstance3D.new()
	_grid.multimesh = mm
	add_child(_grid)


## Stand a model on every obstacle tile. Which model is the terrain's choice,
## so a forest grows trees and a river bank grows rocks.
func _build_props() -> void:
	var t: BattleTerrain = active_terrain()
	if not t.has_props():
		return

	_props = Node3D.new()
	_props.name = "Props"
	add_child(_props)

	for h in _obstacles.keys():
		var prop: TerrainProp = t.pick_obstacle_prop(_obstacle_neighbors(h))
		if prop == null:
			continue

		# standing where the tile was, so it sits on the ground sheet — or on
		# top of the hex, if the tile is still being drawn
		var base_y: float = -tile_height * 0.5 if _tile_replaced(h) else tile_height * 0.5

		var node = prop.scene.instantiate()
		if not node is Node3D:
			push_warning("TerrainProp: %s isn't a 3D scene." % prop.scene.resource_path)
			node.queue_free()
			continue

		_props.add_child(node)

		# size and spin first: the drop below measures the model as it will
		# actually stand, so neither one can throw the height off
		var s: float = prop.random_scale()
		node.scale = Vector3(s, s, s)
		if prop.random_yaw:
			node.rotation.y = randf() * TAU

		var drop: float = _model_bottom(node) if prop.snap_to_ground else 0.0
		node.position = hex_to_local(h.x, h.y) + Vector3(
			0.0, base_y - drop + prop.y_offset * s, 0.0
		)
		_mute_collision(node)


## How far the model's lowest point sits below its own origin, measured with
## its scale and rotation already applied. Subtracting this puts the bottom of
## the model exactly on the ground, wherever the artist left the origin — so
## nothing floats and nothing sinks, at any size.
##
## Returns 0.0 for a scene with no meshes in it, which leaves it where it was.
func _model_bottom(node: Node3D) -> float:
	var meshes: Array = []
	_collect_meshes(node, meshes)
	if meshes.is_empty():
		return 0.0

	# measured in the props container's space, with the model sitting at y = 0
	var old_position: Vector3 = node.position
	node.position = Vector3.ZERO
	var to_local: Transform3D = _props.global_transform.affine_inverse()

	var lowest: float = INF
	for mi in meshes:
		var box: AABB = to_local * mi.global_transform * mi.get_aabb()
		lowest = minf(lowest, box.position.y)

	node.position = old_position
	return 0.0 if lowest == INF else lowest


func _collect_meshes(node: Node, into: Array) -> void:
	if node is MeshInstance3D:
		into.append(node)
	for child in node.get_children():
		_collect_meshes(child, into)


## True when a model stands here in place of the hex, rather than on top of it.
func _tile_replaced(h: Vector2i) -> bool:
	if not _obstacles.has(h):
		return false
	var t: BattleTerrain = active_terrain()
	return t.hide_obstacle_tiles and t.has_props()


func _obstacle_neighbors(h: Vector2i) -> int:
	var total: int = 0
	for n in hex_neighbors(h):
		if _obstacles.has(n):
			total += 1
	return total


## Props are scenery. A model that shipped with a collision shape would sit on
## the world layer and swallow the clicks meant for the ground, so anything
## solid inside one gets switched off on the way in.
func _mute_collision(node: Node) -> void:
	if node is CollisionObject3D:
		node.collision_layer = 0
		node.collision_mask = 0
	for child in node.get_children():
		_mute_collision(child)


func _tile_color(col: int, row: int) -> Color:
	var h := Vector2i(col, row)
	if _obstacles.has(h):
		return active_terrain().obstacle_color
	if _rough.has(h):
		return active_terrain().rough_color
	# plain ground is the ground texture plus an outline, nothing more
	var c: Color = _plain_tile_color(col, row)
	c.a = fill_alpha
	return c


## The tile with no terrain on it — deploy zones and the chequerboard.
func _plain_tile_color(col: int, row: int) -> Color:
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
	battle_log = BattleLog.new()
	_spoils = Inventory.new()
	_spoils.capacity = 999        # the pool is never the constraint

	_units = [player]
	_hexes[player] = world_to_hex(player.global_position)
	battle_log.note_name(player)
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
	combat.turn_changed.connect(func(_u, round_number, _p):
		battle_log.rounds = round_number
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
	if data.get("talent_ranks") != null:
		unit.talent_ranks = data["talent_ranks"].duplicate()
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
		unit.inventory = Inventory.new()
		unit.inventory.equip_all(data.get("loadout", []))

	if data.get("ai") != null:
		unit.ai = data["ai"]

	unit.set_meta("xp_reward", data.get("xp_reward", 0))
	unit.set_meta("gold_reward", data.get("gold", 0))
	unit.set_meta("quest_tag", data.get("quest_tag", ""))

	unit.stop_following()
	_hexes[unit] = at
	battle_log.note_name(unit)
	HealthTag.attach(unit)
	if unit.has_signal("died"):
		unit.died.connect(_on_unit_died.bind(unit))
	return unit


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
	var defence: int = Damage.defence_against(target, kind)
	var dealt: int = Damage.mitigate(raw, target, kind)

	_face_unit(attacker, target)
	print("%s hits %s for %d %s (raw %d, defence %d)%s%s" % [
		_name_of(attacker), _name_of(target), dealt,
		DamageType.label(kind).to_lower(), raw, defence,
		" CRIT" if crit else "",
		" [long shot]" if long_shot else ""
	])

	var flavour: String = "crit" if crit else ("blocked" if long_shot else "damage")
	var show_number := func():
		if is_instance_valid(target):
			DamageNumber.spawn(target, dealt, flavour, kind)

	# a ranged hit shows its number when the shot lands, not when it's loosed
	var ranged: bool = weapon != null and weapon.is_ranged()
	if not (ranged and _launch_projectile(attacker, target, show_number)):
		show_number.call()

	battle_log.record_damage(attacker, target, dealt)
	# record before take_damage: a fatal blow ends the battle synchronously,
	# so anything after that call never runs
	if target.is_alive() and dealt >= target.current_health:
		battle_log.record_kill(attacker)
	target.take_damage(dealt)


## Fire a visual projectile between two units. Returns false when none is
## configured, so the caller can show the hit immediately instead.
func _launch_projectile(attacker, target, on_arrive: Callable) -> bool:
	if projectile_scene == null:
		return false
	var shot = projectile_scene.instantiate()
	if not shot.has_method("launch"):
		shot.queue_free()
		return false

	add_child(shot)
	shot.launch(
		attacker.global_position + Vector3.UP * projectile_height,
		target.global_position + Vector3.UP * projectile_height,
		on_arrive
	)
	return true


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

# ----------------------------------------------- death, rewards and results

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
		_collect_spoils(unit)
		_report_kill(unit)
	_check_battle_over()


## A kill counts under two names: the individual's npc_id, for "deal with the
## bandit captain", and the display name, for "kill ten bandits". An objective
## can target whichever it needs.
func _report_kill(unit) -> void:
	var tag: StringName = StringName(unit.get_meta("quest_tag", ""))
	if not tag.is_empty():
		Quests.notify_kill(tag)
	if "display_name" in unit and not unit.display_name.is_empty():
		var by_name := StringName(unit.display_name)
		if by_name != tag:
			Quests.notify_kill(by_name)


## Everything a fallen enemy carried or wore goes into the shared pool.
func _collect_spoils(unit) -> void:
	if not "inventory" in unit or unit.inventory == null:
		return
	var inv: Inventory = unit.inventory
	for item in inv.items:
		if item != null:
			_spoils.items.append(item)
	for item in inv.equipped.values():
		if item != null:
			_spoils.items.append(item)
	inv.items.clear()
	inv.equipped.clear()


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

	if enemies_up and players_up:
		return

	_battle_over = true
	var won: bool = not enemies_up
	if won:
		print("Victory.")
		_award_rewards()
	else:
		print("Defeat.")

	for u in _units:
		if is_instance_valid(u) and u.has_method("clear_effects"):
			u.clear_effects()

	_show_results(won)


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

	battle_log.xp_awarded = _xp_pool
	battle_log.gold_looted = _gold_pool
	Game.record_battle_results(_xp_pool, survivors)


## Results first, then spoils if anything dropped, then back to the overworld.
func _show_results(won: bool) -> void:
	var packed: PackedScene = load(RESULTS_SCENE_PATH)
	if packed == null:
		_show_spoils()
		return

	var screen = packed.instantiate()
	add_child(screen)

	var friendly: Array = []
	for u in _units:
		if not _enemies.has(u):
			friendly.append(u)

	screen.show_results(won, battle_log, friendly)
	screen.dismissed.connect(_show_spoils)


## Spoils reuse the persistent transfer window — the same one containers use.
func _show_spoils() -> void:
	var window = get_tree().get_first_node_in_group("transfer_window")
	if _spoils.items.is_empty() or window == null or Game.player == null:
		Game.end_battle.call_deferred()
		return

	window.open(_spoils, Game.player.inventory, {
		"title": "Spoils of war",
		"left_title": "Spoils",
		"right_title": Game.player.display_name,
		"close_label": "Leave",
		"hint": "Double-click an item to move it. Anything left behind is lost.",
	})
	# one-shot, since the window outlives this battle
	window.closed.connect(func(): Game.end_battle.call_deferred(), CONNECT_ONE_SHOT)

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


func _try_begin_targeting(index: int) -> void:
	if combat == null or _deploying or _battle_over:
		return
	var caster = get_controlled_unit()
	if caster == null:
		return

	var known: Array = _spells_of(caster)
	if index >= known.size():
		print("No spell in slot %d." % (index + 1))
		return

	_begin_targeting_with(known[index], caster)


## Shared by spells and thrown items. `source_item` is consumed on a hit.
func _begin_targeting_with(spell: Spell, caster, source_item: Item = null) -> bool:
	if combat == null or _deploying or _battle_over or caster == null:
		return false
	if not combat.can_act():
		print("No action left this turn.")
		return false

	var mana: int = caster.current_mana if "current_mana" in caster else 0
	if mana < spell.mana_cost:
		print("Not enough mana for %s (%d needed, %d left)." % [
			spell.display_name, spell.mana_cost, mana
		])
		return false

	_targeting = spell
	_caster = caster
	_thrown_item = source_item
	_cast_tiles = _hexes_within(_hexes[caster], spell.cast_range)
	_blast_tiles.clear()
	_repaint()
	print("Targeting %s — left click to use, Escape to cancel." % spell.display_name)
	return true


## Drink or throw a consumable. Returns true if the action was taken.
func use_consumable(unit, item: Item) -> bool:
	if combat == null or _deploying or _battle_over:
		return false
	if item == null or not item.is_consumable():
		return false
	if unit != combat.active or not combat.player_controlled():
		print("Not that unit's turn.")
		return false
	if not combat.can_act():
		print("No action left this turn.")
		return false

	if item.is_thrown():
		return _begin_targeting_with(item.to_spell(), unit, item)

	combat.spend_action()
	print("%s drinks %s." % [_name_of(unit), item.display_name])
	apply_effect_to(unit, item.effect)
	if item.consumed_on_use and "inventory" in unit and unit.inventory != null:
		unit.inventory.items.erase(item)
	return true


func cancel_targeting() -> void:
	_targeting = null
	_caster = null
	_thrown_item = null
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

	# a thrown item is spent whether or not it hits anyone
	if _thrown_item != null and _thrown_item.consumed_on_use:
		if "inventory" in caster and caster.inventory != null:
			caster.inventory.items.erase(_thrown_item)

	var power: int = 0
	if spell.scales_with_magic and unit_has_stat(caster):
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

			battle_log.record_damage(caster, unit, dealt)
			# same reason as _strike: the battle can end inside take_damage
			if unit.is_alive() and dealt >= unit.current_health:
				battle_log.record_kill(caster)
			unit.take_damage(dealt)

		if spell.effect != null:
			apply_effect_to(unit, spell.effect)

	cancel_targeting()
	_refresh_reachable()
	return true


## Public entry point for anything that applies an effect: spells, consumables,
## and later terrain hazards, traps or auras. Instant effects resolve here;
## timed ones are handed to the unit to hold.
func apply_effect_to(unit, effect: Effect) -> void:
	if unit == null or not is_instance_valid(unit) or effect == null:
		return

	if effect.heals() and unit.has_method("heal"):
		var amount: int = effect.roll_heal()
		unit.heal(amount)
		DamageNumber.spawn(unit, amount, "heal")
		print("  %s recovers %d health." % [_name_of(unit), amount])

	if not effect.is_instant() and unit.has_method("add_effect"):
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
## A highlighted tile keeps its own hue but is forced up to a solid-enough
## alpha, so the wash reads over the ground texture whatever's underneath.
func _highlight(h: Vector2i, tint: Color) -> Color:
	var c: Color = _tile_color(h.x, h.y) * tint
	c.a = maxf(highlight_alpha, _tile_color(h.x, h.y).a)
	return c


func _repaint() -> void:
	if _grid == null:
		return

	var desired: Dictionary = {}
	for h in _deploy_tiles.keys():
		desired[h] = _highlight(h, DEPLOY_TINT)
	for h in _reachable.keys():
		desired[h] = _highlight(h, REACHABLE_TINT)
	for h in _preview.keys():
		desired[h] = _highlight(h, PREVIEW_TINT)
	for h in _cast_tiles.keys():
		desired[h] = _highlight(h, CAST_RANGE_TINT)
	for h in _blast_tiles.keys():
		desired[h] = _highlight(h, BLAST_TINT)

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

# ------------------------------------------------------------------ enemy AI

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

## The kind of map this battle is being fought on. Rolled once and kept, so
## redrawing the grid doesn't quietly reshuffle the terrain under the units.
func active_terrain() -> BattleTerrain:
	if _terrain != null:
		return _terrain

	if terrain != null:
		_terrain = terrain
	else:
		_terrain = BattleTerrain.random_from_folder()
	if _terrain == null:
		_terrain = BattleTerrain.new()      # defaults match the old wetland
	print("Battle terrain: %s" % _terrain.display_name)
	return _terrain


## Throw the map away and roll a fresh one. Handy on a debug key.
func reroll_terrain() -> void:
	_terrain = null
	_rebuild()


func _generate_terrain() -> void:
	_obstacles.clear()
	_rough.clear()
	var t: BattleTerrain = active_terrain()

	# water first, so rocks can't be placed where the river is about to go
	if t.kind == BattleTerrain.Kind.RIVER:
		_carve_river(t)
	else:
		_scatter(_rough, t.rough_density, t.rough_spread, t.max_rough_cluster)

	_scatter(_obstacles, t.obstacle_density, t.obstacle_spread, t.max_obstacle_cluster)
	_ensure_crossable()


## A band of water running from one end of the map to the other, across the
## axis the armies face along, so both sides have to deal with it. It wanders
## as it goes rather than ruling a straight line.
func _carve_river(t: BattleTerrain) -> void:
	var width: int = randi_range(t.river_min_width, maxi(t.river_min_width, t.river_max_width))
	var centre: int = columns / 2

	for row in rows:
		if randf() < t.river_meander:
			centre += 1 if randf() < 0.5 else -1
		if randf() < t.river_meander * 0.5:
			width = clampi(width + (1 if randf() < 0.5 else -1), t.river_min_width, t.river_max_width)

		# never let the channel wander into a deploy zone — a river you start
		# standing in isn't an obstacle, it's a penalty for turn one
		var lowest: int = deploy_rows + 1
		var highest: int = maxi(lowest, columns - deploy_rows - width - 1)
		centre = clampi(centre, lowest, highest)

		var half: int = width / 2
		for offset in range(-half, width - half):
			var h := Vector2i(centre + offset, row)
			if h.x < 0 or h.x >= columns or _in_deploy_zone(h):
				continue
			_rough[h] = true


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


## A dense forest can close the map off entirely, which ends a battle before
## it starts. Check the two sides connect, and if they don't, bulldoze the
## shortest line between them.
func _ensure_crossable() -> void:
	var start := Vector2i(0, rows / 2)
	var goal := Vector2i(columns - 1, rows / 2)
	if _reaches(start, goal):
		return
	push_warning("BattleMap: terrain sealed the map off — carving a way through.")
	_carve_path(start, goal)


func _reaches(start: Vector2i, goal: Vector2i) -> bool:
	var seen: Dictionary = {start: true}
	var queue: Array = [start]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		if current == goal:
			return true
		for n in hex_neighbors(current):
			if seen.has(n) or _obstacles.has(n):
				continue
			seen[n] = true
			queue.append(n)
	return false


## Walk greedily downhill on hex distance, clearing whatever's in the way.
## Distance strictly decreases each step, so this always arrives.
func _carve_path(from: Vector2i, to: Vector2i) -> void:
	var current: Vector2i = from
	var guard: int = 0

	while current != to and guard < columns * rows:
		guard += 1
		var best: Vector2i = current
		var best_distance: int = hex_distance(current, to)
		for n in hex_neighbors(current):
			var d: int = hex_distance(n, to)
			if d < best_distance:
				best_distance = d
				best = n
		if best == current:
			return
		current = best
		_obstacles.erase(current)


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
