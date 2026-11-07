extends CanvasLayer
## The screen the game opens on. Sits above everything else and pauses the
## tree, so whatever is behind it — including a world main.gd may already have
## loaded — stays frozen until something is chosen.
 
const BUTTONS := [
	{"label": "Story", "action": "story"},
	{"label": "Skirmish", "action": "skirmish"},
	{"label": "Load game", "action": "load"},
	{"label": "Options", "action": "options"},
	{"label": "Exit", "action": "exit"},
]
 
## The world a skirmish starts in. Only loaded when there isn't one already —
## on a cold start main.gd has usually loaded it, and this fills the gap after
## a return to the menu, when the old world has been thrown away.
@export_file("*.tscn") var world_scene: String = ""
 
var _root: Control
var _status: Label
 
 
func _ready() -> void:
	layer = 70                                   # above the pause menu's 60
	process_mode = Node.PROCESS_MODE_ALWAYS      # keep running while paused
	add_to_group("main_menu")
	_build()
	open()
 
 
func is_open() -> bool:
	return _root.visible
 
 
func open() -> void:
	_status.text = ""
	_root.show()
	get_tree().paused = true
 
 
func close() -> void:
	_root.hide()
	get_tree().paused = false
 
 
# ----------------------------------------------------------------- actions
 
func _on_pressed(action: String) -> void:
	match action:
		"skirmish":
			_start_skirmish()
		"load":
			_open_load_menu()
		"exit":
			get_tree().paused = false
			get_tree().quit()
		"story":
			_status.text = "The story campaign isn't written yet."
		_:
			_status.text = "%s isn't implemented yet." % action.capitalize()
 
 
func _start_skirmish() -> void:
	# coming back to the menu frees the world, so one may need building again
	if Game.current_world == null:
		if world_scene.is_empty():
			_status.text = "No world set — fill in World Scene on the MainMenu node."
			return
		_status.text = "Loading…"
		await Game.load_world(world_scene)
	close()
 
 
## Hand over to the save menu, hiding ourselves until it comes back. Loading a
## save builds its own world, so there's nothing to start afterwards.
func _open_load_menu() -> void:
	var menu = get_tree().get_first_node_in_group("save_menu")
	if menu == null:
		_status.text = "Save menu is missing."
		return
 
	_root.hide()
	menu.open("load")
	if not menu.closed.is_connected(_on_load_menu_closed):
		menu.closed.connect(_on_load_menu_closed)
 
 
func _on_load_menu_closed(loaded: bool) -> void:
	if loaded:
		close()
	else:
		_status.text = ""
		_root.show()
 
 
# ------------------------------------------------------------------ layout
 
func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP      # swallow clicks behind
	add_child(_root)
 
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.04, 0.04, 0.06, 1.0)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(backdrop)
 
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
 
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	center.add_child(column)
 
	var title := Label.new()
	title.text = "Untitled Tactics"
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.modulate = Color(1, 0.85, 0.45)
	column.add_child(title)
 
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	column.add_child(spacer)
 
	for entry in BUTTONS:
		var button := Button.new()
		button.text = entry["label"]
		button.custom_minimum_size = Vector2(240, 42)
		button.pressed.connect(_on_pressed.bind(entry["action"]))
		column.add_child(button)
 
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 12)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.modulate = Color(1, 1, 1, 0.55)
	column.add_child(_status)
 
