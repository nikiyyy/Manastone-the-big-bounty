extends Node

signal world_loaded(world: Node)
signal player_spawned(player: Node)
signal battle_started(battle: Node)
signal battle_ended

const PLAYER_SCENE_PATH := "res://scenes/player.tscn"

var world_root: Node = null
var current_world: Node = null
var player: Node = null

var _in_battle: bool = false
var _return_world_path: String = ""
var _return_position: Vector3 = Vector3.ZERO
var _world_states: Dictionary = {}
var _player_state: Dictionary = {}
var _pending_ally_xp: Dictionary = {}      # display_name -> xp gained
var _suppress_capture: bool = false        # set while a save is being applied


func register_world_root(node: Node) -> void:
	world_root = node

# ------------------------------------------------------------ world loading

func load_world(scene_path: String) -> void:
	if world_root == null:
		push_error("Game: world_root not registered — did main.gd run?")
		return

	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("Game: could not load world at %s" % scene_path)
		return

	_free_current_world()

	current_world = packed.instantiate()
	world_root.add_child(current_world)

	# give the new world one frame to finish its own _ready()
	await get_tree().process_frame

	_spawn_player(current_world)
	_restore_state(current_world)
	world_loaded.emit(current_world)


## Snapshots are skipped while a save is being applied — otherwise the world
## we're leaving would overwrite the state we just loaded.
func _free_current_world() -> void:
	if not _suppress_capture:
		if player != null and is_instance_valid(player) and player.has_method("save_state"):
			_player_state = player.save_state()
	player = null

	if current_world == null:
		return

	if not _suppress_capture:
		_world_states[current_world.scene_file_path] = _capture_state(current_world)

	world_root.remove_child(current_world)
	current_world.queue_free()
	current_world = null


func _spawn_player(world: Node) -> void:
	var packed: PackedScene = load(PLAYER_SCENE_PATH)
	if packed == null:
		push_error("Game: no player scene at %s" % PLAYER_SCENE_PATH)
		return

	player = packed.instantiate()
	world.add_child(player)
	player.global_position = _find_spawn(world)
	if not _player_state.is_empty() and player.has_method("load_state"):
		player.load_state(_player_state)
	if player.has_method("teleport_to"):
		player.teleport_to(player.global_position)
	player_spawned.emit(player)


func _find_spawn(world: Node) -> Vector3:
	# worlds that generate themselves compute spawns in code
	if world.has_method("get_spawn_position"):
		return world.get_spawn_position("PlayerSpawn")
	var marker := world.get_node_or_null("PlayerSpawn")
	if marker is Node3D:
		return marker.global_position
	push_warning("No PlayerSpawn in %s — using origin" % world.name)
	return Vector3.ZERO

# ------------------------------------------------------------------- battle

func in_battle() -> bool:
	return _in_battle


func start_battle(battle_scene_path: String, enemy_source: Node) -> void:
	if _in_battle or current_world == null:
		return

	# remember how to get back
	_return_world_path = current_world.scene_file_path
	_return_position = player.global_position

	var enemy_group: Dictionary = {}
	if enemy_source and enemy_source.has_method("to_battle_group"):
		enemy_group = enemy_source.to_battle_group()

	var ally_data: Array = []
	_collect_followers(current_world, ally_data)

	_in_battle = true
	await load_world(battle_scene_path)

	if current_world.has_method("setup_battle"):
		current_world.setup_battle(player, enemy_group, ally_data)
	battle_started.emit(current_world)


func end_battle() -> void:
	if not _in_battle:
		return
	_in_battle = false

	await load_world(_return_world_path)
	player.global_position = _return_position
	if player.has_method("teleport_to"):
		player.teleport_to(_return_position)

	_apply_pending_ally_xp(current_world)
	battle_ended.emit()


func _collect_followers(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child.has_method("is_following") and child.is_following():
			if child.has_method("to_ally_data"):
				out.append(child.to_ally_data())
		_collect_followers(child, out)


## Called by the battle map on victory. Ally XP is matched back by name when
## the overworld reloads, since the battle versions are throwaway copies.
func record_battle_results(_total_xp: int, survivors: Array) -> void:
	_pending_ally_xp.clear()
	for u in survivors:
		if u == player or not "display_name" in u or not "xp" in u:
			continue
		_pending_ally_xp[u.display_name] = u.xp


func _apply_pending_ally_xp(world: Node) -> void:
	if _pending_ally_xp.is_empty():
		return
	_match_ally_xp(world)
	_pending_ally_xp.clear()


func _match_ally_xp(node: Node) -> void:
	for child in node.get_children():
		if "display_name" in child and _pending_ally_xp.has(child.display_name):
			if "xp" in child and child.has_method("add_xp"):
				var gained: int = _pending_ally_xp[child.display_name] - child.xp
				if gained > 0:
					child.add_xp(gained)
		_match_ally_xp(child)

# -------------------------------------------------------- world state cache

func _capture_state(world: Node) -> Dictionary:
	var data: Dictionary = {}
	_walk_save(world, world, data)
	return data


func _walk_save(world: Node, node: Node, data: Dictionary) -> void:
	for child in node.get_children():
		if child == player:
			continue          # the player has its own dedicated snapshot
		if child.has_method("save_state"):
			data[String(world.get_path_to(child))] = child.save_state()
		_walk_save(world, child, data)


func _restore_state(world: Node) -> void:
	var data: Dictionary = _world_states.get(world.scene_file_path, {})
	for path in data.keys():
		var node := world.get_node_or_null(NodePath(path))
		if node == null or node == player:
			continue
		if node.has_method("load_state"):
			node.load_state(data[path])

# ------------------------------------------------------------ save and load

func can_save() -> bool:
	return not _in_battle and current_world != null and player != null


## Everything needed to restore this session. The current world is snapshotted
## on the spot, since _world_states only updates when a world unloads.
func capture_save() -> Dictionary:
	var worlds: Dictionary = _world_states.duplicate(true)
	if current_world != null:
		worlds[current_world.scene_file_path] = _capture_state(current_world)

	var player_data: Dictionary = {}
	if player != null and player.has_method("save_state"):
		player_data = player.save_state()

	return {
		"version": 2,
		"saved_at": Time.get_datetime_string_from_system(true),
		"summary": _save_summary(),
		"world_path": current_world.scene_file_path if current_world != null else "",
		"player_position": player.global_position if player != null else Vector3.ZERO,
		"player": player_data,
		"worlds": worlds,
		"story": Story.save_state(),
	}


func _save_summary() -> String:
	if player == null:
		return ""
	var who: String = player.display_name if "display_name" in player else "Hero"
	var level: int = player.level if "level" in player else 1
	var place: String = ""
	if current_world != null:
		place = current_world.scene_file_path.get_file().get_basename().capitalize()
	return "%s — level %d — %s" % [who, level, place]


func apply_save(data: Dictionary) -> void:
	var world_path: String = data.get("world_path", "")
	if world_path.is_empty():
		push_error("Game: save has no world path")
		return

	# the incoming state must survive the unload that load_world triggers
	_suppress_capture = true
	_in_battle = false
	_pending_ally_xp.clear()
	_world_states = data.get("worlds", {}).duplicate(true)
	_player_state = data.get("player", {}).duplicate(true)
	Story.load_state(data.get("story", {}))

	await load_world(world_path)
	_suppress_capture = false

	var where = data.get("player_position", Vector3.ZERO)
	if player != null and player.has_method("teleport_to"):
		player.teleport_to(where)
