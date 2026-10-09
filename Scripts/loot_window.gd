extends CanvasLayer
## Spoils on the left, your pack on the right. Double-click to move an item
## either way. No gold changes hands.

const COLUMNS := 4
const CELLS := 24

signal closed

var spoils: Inventory = null
var player = null

var _root: Control
var _spoils_title: Label
var _player_title: Label
var _spoils_cells: Array = []
var _player_cells: Array = []


func _ready() -> void:
	layer = 50
	add_to_group("loot_window")
	_build()
	_root.hide()


func is_open() -> bool:
	return _root.visible


func open(pool: Inventory, player_node) -> void:
	spoils = pool
	player = player_node
	_refresh()
	_root.show()


func close() -> void:
	_root.hide()
	closed.emit()


func _take_all() -> void:
	if spoils == null or player == null:
		return
	var pack: Inventory = player.inventory
	while not spoils.items.is_empty() and not pack.is_full():
		pack.items.append(spoils.items.pop_front())
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

	var heading := Label.new()
	heading.text = "Spoils of war"
	heading.add_theme_font_size_override("font_size", 22)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.modulate = Color(1, 0.85, 0.4)
	outer.add_child(heading)

	var grids := HBoxContainer.new()
	grids.add_theme_constant_override("separation", 28)
	outer.add_child(grids)

	_spoils_title = Label.new()
	_player_title = Label.new()
	grids.add_child(_build_side(_spoils_title, _spoils_cells, true))
	grids.add_child(_build_side(_player_title, _player_cells, false))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(buttons)

	var take_all := Button.new()
	take_all.text = "Take all"
	take_all.custom_minimum_size = Vector2(150, 34)
	take_all.pressed.connect(_take_all)
	buttons.add_child(take_all)

	var leave := Button.new()
	leave.text = "Leave"
	leave.custom_minimum_size = Vector2(150, 34)
	leave.pressed.connect(close)
	buttons.add_child(leave)

	var hint := Label.new()
	hint.text = "Double-click an item to move it. Anything left behind is lost."
	hint.add_theme_font_size_override("font_size", 11)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1, 1, 1, 0.5)
	outer.add_child(hint)


func _build_side(title: Label, cells: Array, from_spoils: bool) -> Control:
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

		button.gui_input.connect(_on_cell_input.bind(i, from_spoils))
		grid.add_child(button)
		cells.append(button)

	return column


# -------------------------------------------------------------------- data

func _refresh() -> void:
	if spoils == null or player == null:
		return

	_spoils_title.text = "Spoils — %d item%s" % [
		spoils.items.size(), "" if spoils.items.size() == 1 else "s"
	]
	_player_title.text = "%s — %d / %d carried" % [
		player.display_name, player.inventory.items.size(), player.inventory.capacity
	]

	_fill(_spoils_cells, spoils)
	_fill(_player_cells, player.inventory)


func _fill(cells: Array, inv: Inventory) -> void:
	for i in cells.size():
		var item: Item = null
		if inv != null and i < inv.items.size():
			item = inv.items[i]

		var button: Button = cells[i]
		var icon: ColorRect = button.get_node("Icon")
		icon.visible = item != null

		if item == null:
			button.text = ""
			button.tooltip_text = ""
			button.modulate = Color.WHITE
			continue

		button.text = ""
		button.tooltip_text = item.tooltip()
		button.modulate = item.rarity_color()
		icon.color = item.rarity_color()


func _on_cell_input(event: InputEvent, index: int, from_spoils: bool) -> void:
	if not (event is InputEventMouseButton and event.double_click):
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if from_spoils:
		_move(spoils, player.inventory, index)
	else:
		_move(player.inventory, spoils, index)


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
