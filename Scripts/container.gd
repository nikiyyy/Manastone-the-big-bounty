@tool
class_name LootContainer
extends StaticBody3D
## A chest, barrel or crate in the overworld. Walk up to it and click to open
## a transfer window; whatever you leave inside stays there.
##
## Named LootContainer because Godot already has a Control called Container.
 
@export var display_name: String = "Chest"
@export var inventory: Inventory
## Placed inside on first open. Simpler to fill in than the inventory itself.
@export var contents: Array[Item] = []
@export var capacity: int = 16
@export var tint: Color = Color(0.45, 0.32, 0.18):
	set(value):
		tint = value
		_apply_tint()
 
## Filled lazily so an untouched chest costs nothing until opened.
var _filled: bool = false
 
 
func _ready() -> void:
	if not Engine.is_editor_hint():
		inventory = inventory.duplicate(true) if inventory != null else Inventory.new()
		inventory.capacity = capacity
	_apply_tint()
 
 
func _apply_tint() -> void:
	if not is_node_ready():
		return
	var mesh := get_node_or_null("MeshInstance3D")
	if mesh == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mesh.material_override = mat
 
 
## Duck-typed marker. The player's click handler looks for this.
func is_container() -> bool:
	return true
 
 
## Fill from `contents` the first time, then persist whatever's left inside.
func open_inventory() -> Inventory:
	if inventory == null:
		inventory = Inventory.new()
		inventory.capacity = capacity
	if not _filled:
		_filled = true
		for item in contents:
			if item != null:
				inventory.items.append(item.duplicate())
	return inventory
 
 
func is_empty() -> bool:
	return open_inventory().items.is_empty()
 
# -------------------------------------------------------------------- saving
 
func save_state() -> Dictionary:
	return {
		"inventory": inventory,
		"filled": _filled,
	}
 
 
func load_state(data: Dictionary) -> void:
	if data.get("inventory") != null:
		inventory = data["inventory"]
	_filled = data.get("filled", false)
 
