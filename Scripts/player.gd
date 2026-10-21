extends Unit
## The player character. Everything shared with NPCs lives in Unit — this is
## movement, clicking, dialogue and gold.
 
signal interacted(npc)
signal container_opened(container)
signal gold_changed(amount: int)
 
@export var speed: float = 5.0
@export var interaction_range: float = 2.0
@export var gold: int = 0
 
var target_position: Vector3
var interaction_target = null
var dialogue_open: bool = false
 
var _waypoints: Array = []
var _deploy_selection = null
 
 
func _ready() -> void:
	super()
	target_position = global_position
 
# ------------------------------------------------------------------ movement
 
func teleport_to(where: Vector3) -> void:
	super(where)
	target_position = where
	interaction_target = null
	_waypoints.clear()
 
 
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
 
	# a chest or crate: walk over and open it
	if collider != null and collider.has_method("is_container"):
		if actor == self:
			_approach(collider)
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
	if _deploy_selection != null and is_instance_valid(_deploy_selection):
		return _deploy_selection
	return self
 
 
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
 
# ------------------------------------------------------- dialogue and chests
 
## Walk to a spot just outside something and remember to interact on arrival.
## Works for NPCs and containers alike.
func _approach(thing) -> void:
	var away: Vector3 = global_position - thing.global_position
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3.FORWARD
	var stand_at: Vector3 = thing.global_position + away.normalized() * (interaction_range * 0.85)
 
	if _begin_path(_request_path(self, stand_at)):
		interaction_target = thing
 
 
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
 
	var thing = interaction_target
	interaction_target = null
	target_position = global_position
	_face(b)
 
	# both windows clear dialogue_open when they close
	dialogue_open = true
	if thing.has_method("is_container"):
		container_opened.emit(thing)
	else:
		interacted.emit(thing)
 
 
func _face(point: Vector3) -> void:
	var flat := Vector3(point.x, global_position.y, point.z)
	if flat.distance_to(global_position) > 0.01:
		look_at(flat, Vector3.UP)
 
# ---------------------------------------------------------------------- gold
 
func add_gold(amount: int) -> void:
	gold = maxi(0, gold + amount)
	gold_changed.emit(gold)
 
# -------------------------------------------------------------------- saving
 
func save_state() -> Dictionary:
	var data: Dictionary = super()
	data["gold"] = gold
	return data
 
 
func load_state(data: Dictionary) -> void:
	super(data)
	gold = data.get("gold", 0)
	gold_changed.emit(gold)
 
