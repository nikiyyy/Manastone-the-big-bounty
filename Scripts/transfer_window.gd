extends CanvasLayer
## Two inventories side by side, items moving freely between them. Serves both
## battle spoils and overworld containers — the caller supplies the labels.
##
## Replaces loot_window.gd; delete that script and its scene.
 
signal closed
 
const COLUMNS := 4
const CELLS := 24
 
var left: Inventory = null
var right: Inventory = null
 
var _root: Control
var _heading: Label
var _left_title: Label
var _right_title: Label
var _left_cells: Array = []
var _right_cells: Array = []
var _take_all_button: Button
var _close_button: Button
var _hint: Label
 
var _left_name: String = "There"
var _right_name: String = "You"
var _player: Node = null
var _source: Node = null          # the container we were opened from, if any
 
 
func _ready() -> void:
	layer = 50
	add_to_group("transfer_window")
	_build()
	_root.hide()
 
	Game.player_spawned.connect(_on_player_spawned)
	if Game.player != null:
		_on_player_spawned(Game.player)
 
 
func is_open() -> bool:
	return _root.visible
 
 
func _on_player_spawned(new_player: Node) -> void:
	_player = new_player
	if _player.has_signal("container_opened"):
		if not _player.container_opened.is_connected(_on_container_opened):
			_player.container_opened.connect(_on_container_opened)
	if is_open():
		close()
 
 
# ---------------------------------------------------------------- opening
 
## Generic entry point. `config` keys: title, left_title, right_title,
## close_label, hint, show_take_all.
func open(left_inv: Inventory, right_inv: Inventory, config: Dictionary = {}) -> void:
	left = left_inv
	right = right_inv
	_left_name = config.get("left_title", "There")
	_right_name = config.get("right_title", "You")
 
	_heading.text = config.get("title", "Transfer")
	_close_button.text = config.get("close_label", "Close")
	_hint.text = config.get("hint", "Double-click an item to move it.")
	_take_all_button.visible = config.get("show_take_all", true)
 
	_refresh()
	_root.show()
 
 
## Opened by walking up to a chest in the overworld.
func _on_container_opened(container) -> void:
	if container == null or not is_instance_valid(container):
		return
	_source = container
	var name: String = container.display_name if "display_name" in container else "Container"
 
	open(container.open_inventory(), _player.inventory, {
		"title": name,
		"left_title": name,
		"right_title": _player.display_name,
		"close_label": "Close",
		"hint": "Double-click an item to move it. Anything left here stays.",
	})
 
 
func close() -> void:
	_root.hide()
	_source = null
	# whichever window set this, the player is free to act again
	if _player != null and is_instance_valid(_player):
		_player.dialogue_open = false
	closed.emit()
 
 
func _unhandled_input(event: InputEvent) -> void:
	if not _root.visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
 
 
func _take_all() -> void:
	if left == null or right == null:
		return
	while not left.items.is_empty() and not right.is_full():
		right.items.append(left.items.pop_front())
	_refresh()
 
 
# ------------------------------------------------------------------ layout
 
func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
 
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
 
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
 
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.08, 0.08, 0.10, 0.97)
	box.set_corner_radius_all(8)
	box.set_content_margin_all(20)
	box.border_color = Color(1, 1, 1, 0.18)
	box.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", box)
	center.add_child(panel)
 
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	panel.add_child(outer)
 
	_heading = Label.new()
	_heading.add_theme_font_size_override("font_size", 22)
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading.modulate = Color(1, 0.85, 0.4)
	outer.add_child(_heading)
 
	var grids := HBoxContainer.new()
	grids.add_theme_constant_override("separation", 28)
	outer.add_child(grids)
 
	_left_title = Label.new()
	_right_title = Label.new()
	grids.add_child(_build_side(_left_title, _left_cells, true))
	grids.add_child(_build_side(_right_title, _right_cells, false))
 
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(buttons)
 
	_take_all_button = Button.new()
	_take_all_button.text = "Take all"
	_take_all_button.custom_minimum_size = Vector2(150, 34)
	_take_all_button.pressed.connect(_take_all)
	buttons.add_child(_take_all_button)
 
	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.custom_minimum_size = Vector2(150, 34)
	_close_button.pressed.connect(close)
	buttons.add_child(_close_button)
 
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 11)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.modulate = Color(1, 1, 1, 0.5)
	outer.add_child(_hint)
 
 
func _build_side(title: Label, cells: Array, from_left: bool) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
 
	title.add_theme_font_size_override("font_size", 15)
	column.add_child(title)
 
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	column.add_child(grid)
 
	for i in CELLS:
		var button := Button.new()
		button.custom_minimum_size = Vector2(56, 56)
		button.clip_text = true
		button.add_theme_font_size_override("font_size", 10)
 
		var icon := ColorRect.new()
		icon.name = "Icon"
		icon.color = Color(0.55, 0.35, 0.85)
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 6
		icon.offset_top = 6
		icon.offset_right = -6
		icon.offset_bottom = -6
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.visible = false
		button.add_child(icon)
 
		button.gui_input.connect(_on_cell_input.bind(i, from_left))
		grid.add_child(button)
		cells.append(button)
 
	return column
 
 
# -------------------------------------------------------------------- data
 
func _refresh() -> void:
	if left == null or right == null:
		return
 
	_left_title.text = "%s — %d / %d" % [_left_name, left.items.size(), left.capacity]
	_right_title.text = "%s — %d / %d" % [_right_name, right.items.size(), right.capacity]
 
	_fill(_left_cells, left)
	_fill(_right_cells, right)
 
 
func _fill(cells: Array, inv: Inventory) -> void:
	for i in cells.size():
		var item: Item = null
		if inv != null and i < inv.items.size():
			item = inv.items[i]
 
		var button: Button = cells[i]
		var icon: ColorRect = button.get_node("Icon")
		icon.visible = item != null
 
		if item == null:
			button.tooltip_text = ""
			button.modulate = Color.WHITE
			continue
 
		button.tooltip_text = item.tooltip()
		button.modulate = item.rarity_color()
		icon.color = item.rarity_color()
 
 
func _on_cell_input(event: InputEvent, index: int, from_left: bool) -> void:
	if not (event is InputEventMouseButton and event.double_click):
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if from_left:
		_move(left, right, index)
	else:
		_move(right, left, index)
 
 
## No gold, no prices — items just change hands.
func _move(from: Inventory, to: Inventory, index: int) -> void:
	if from == null or to == null or index >= from.items.size():
		return
	if to.is_full():
		print("No room.")
		return
	to.items.append(from.items[index])
	from.items.remove_at(index)
	_refresh()
 
