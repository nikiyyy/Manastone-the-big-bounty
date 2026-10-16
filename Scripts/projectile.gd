extends Node3D
## A flying visual. Launched between two world points, frees itself on arrival.
## The mesh and its material live in the scene, so they're editor-tunable.

signal arrived

@export var speed: float = 30.0          ## metres per second
@export var arc_height: float = 0.9      ## shallow lob; 0 for a flat shot
@export var align_to_flight: bool = true ## point the mesh along its path
@export var spin_speed: float = 0.0      ## degrees/sec around its own axis

var _from: Vector3
var _to: Vector3
var _elapsed: float = 0.0
var _duration: float = 0.0
var _on_arrive: Callable = Callable()
var _flying: bool = false


func launch(from: Vector3, to: Vector3, on_arrive: Callable = Callable()) -> void:
	_from = from
	_to = to
	_on_arrive = on_arrive
	_duration = maxf(0.05, from.distance_to(to) / maxf(1.0, speed))
	_elapsed = 0.0
	_flying = true
	global_position = from


func _process(delta: float) -> void:
	if not _flying:
		return

	_elapsed += delta
	var t: float = clampf(_elapsed / _duration, 0.0, 1.0)

	var previous: Vector3 = global_position
	var next: Vector3 = _from.lerp(_to, t)
	next.y += arc_height * sin(t * PI)      # peaks at the midpoint
	global_position = next

	if align_to_flight and next.distance_to(previous) > 0.001:
		look_at(next + (next - previous), Vector3.UP)
	if spin_speed != 0.0:
		rotate_object_local(Vector3.FORWARD, deg_to_rad(spin_speed) * delta)

	if t >= 1.0:
		_flying = false
		arrived.emit()
		if _on_arrive.is_valid():
			_on_arrive.call()
		queue_free()
