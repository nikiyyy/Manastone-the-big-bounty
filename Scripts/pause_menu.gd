extends CanvasLayer
## Escape opens this outside combat. Pauses the tree while open.

const BUTTONS := [
	{"label": "Continue", "action": "continue"},
	{"label": "Save", "action": "save"},
	{"label": "Load", "action": "load"},
	{"label": "Options", "action": "options"},
	{"label": "Exit", "action": "exit"},
]

var _root: Control
var _status: Label


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS      # keep running while paused
	add_to_group("pause_menu")
	_build()
	_root.hide()


func is_open() -> bool:
	return _root.visible


func open() -> void:
	_status.text = ""
	_root.show()
	get_tree().paused = true


func close() -> void:
	_root.hide()
	get_tree().paused = false


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode != KEY_ESCAPE:
		return
	if Game.in_battle():
		return
	if not is_open() and _another_window_open():
		return          # let that window close itself first
	toggle()
	get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ layout

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP      # swallow clicks behind
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
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
	box.set_content_margin_all(24)
	box.border_color = Color(1, 1, 1, 0.18)
	box.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", box)
	center.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	var title := Label.new()
	title.text = "Paused"
	title.add_theme_font_size_override("font_size", 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	column.add_child(HSeparator.new())

	for entry in BUTTONS:
		var button := Button.new()
		button.text = entry["label"]
		button.custom_minimum_size = Vector2(200, 38)
		button.pressed.connect(_on_pressed.bind(entry["action"]))
		column.add_child(button)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 12)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.modulate = Color(1, 1, 1, 0.55)
	column.add_child(_status)


func _on_pressed(action: String) -> void:
	match action:
		"continue":
			close()
		"exit":
			get_tree().paused = false
			get_tree().quit()
		_:
			_status.text = "%s isn't implemented yet." % action.capitalize()

func _another_window_open() -> bool:
	for group in ["character_sheet", "trade_window"]:
		for node in get_tree().get_nodes_in_group(group):
			if node.has_method("is_open") and node.is_open():
				return true
	return false
