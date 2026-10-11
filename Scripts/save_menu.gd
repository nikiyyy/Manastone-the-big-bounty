extends CanvasLayer
## Serves both the Save and Load screens — same list, different buttons.
## Opened by the pause menu; emits `closed(loaded)` so it knows whether the
## world changed underneath it.

signal closed(loaded: bool)

const ROW_HEIGHT := 56

var mode: String = "load"      # "save" or "load"

var _root: Control
var _title: Label
var _list: VBoxContainer
var _scroll: ScrollContainer
var _name_field: LineEdit
var _save_row: HBoxContainer
var _status: Label
var _pending_delete: String = ""


func _ready() -> void:
	layer = 65
	process_mode = Node.PROCESS_MODE_ALWAYS      # usable while the tree is paused
	add_to_group("save_menu")
	_build()
	_root.hide()


func is_open() -> bool:
	return _root.visible


func open(which: String) -> void:
	mode = which
	_pending_delete = ""
	_status.text = ""
	_title.text = "Save game" if mode == "save" else "Load game"
	_save_row.visible = (mode == "save")
	if mode == "save":
		_name_field.text = _suggested_name()
	_refresh()
	_root.show()


func close(loaded: bool = false) -> void:
	_root.hide()
	closed.emit(loaded)


func _unhandled_input(event: InputEvent) -> void:
	if not _root.visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close(false)
		get_viewport().set_input_as_handled()


func _suggested_name() -> String:
	var stamp: String = Time.get_datetime_string_from_system(false).replace("T", " ")
	return stamp.substr(0, 16)


# ------------------------------------------------------------------- actions

func _on_save_pressed() -> void:
	var slot: String = _name_field.text.strip_edges()
	if slot.is_empty():
		_status.text = "Give the save a name."
		return
	_write(slot)


func _write(slot: String) -> void:
	if not Game.can_save():
		_status.text = "Can't save right now."
		return
	if SaveGame.write(slot, Game.capture_save()):
		_status.text = "Saved as \"%s\"." % slot
		_refresh()
	else:
		_status.text = "Save failed — check the console."


func _on_row_pressed(entry: Dictionary) -> void:
	if mode == "save":
		_name_field.text = entry["name"]
		_write(entry["name"])
	else:
		_load(entry)


func _load(entry: Dictionary) -> void:
	var data: Dictionary = SaveGame.read(entry["path"])
	if data.is_empty():
		_status.text = "That save couldn't be read."
		return
	# unpause first: loading awaits a frame, which never arrives while paused
	get_tree().paused = false
	close(true)
	Game.apply_save(data)


func _on_delete_pressed(entry: Dictionary) -> void:
	if _pending_delete != entry["path"]:
		_pending_delete = entry["path"]
		_status.text = "Delete \"%s\"? Click again to confirm." % entry["name"]
		_refresh()
		return

	_pending_delete = ""
	if SaveGame.erase(entry["path"]):
		_status.text = "Deleted \"%s\"." % entry["name"]
	else:
		_status.text = "Couldn't delete that file."
	_refresh()


# -------------------------------------------------------------------- layout

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

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.custom_minimum_size = Vector2(520, 0)
	panel.add_child(column)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	column.add_child(_title)
	column.add_child(HSeparator.new())

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 280)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 5)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)

	_save_row = HBoxContainer.new()
	_save_row.add_theme_constant_override("separation", 8)
	column.add_child(_save_row)

	_name_field = LineEdit.new()
	_name_field.placeholder_text = "Save name"
	_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_field.text_submitted.connect(func(_t): _on_save_pressed())
	_save_row.add_child(_name_field)

	var save_button := Button.new()
	save_button.text = "Save"
	save_button.custom_minimum_size = Vector2(110, 32)
	save_button.pressed.connect(_on_save_pressed)
	_save_row.add_child(save_button)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 11)
	_status.modulate = Color(1, 1, 1, 0.65)
	column.add_child(_status)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0, 32)
	back.pressed.connect(func(): close(false))
	column.add_child(back)


func _refresh() -> void:
	for child in _list.get_children():
		child.queue_free()

	var saves: Array = SaveGame.list_saves()
	if saves.is_empty():
		var empty := Label.new()
		empty.text = "No saves yet."
		empty.add_theme_font_size_override("font_size", 12)
		empty.modulate = Color(1, 1, 1, 0.45)
		_list.add_child(empty)
		return

	for entry in saves:
		_list.add_child(_make_row(entry))


func _make_row(entry: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)

	var pick := Button.new()
	pick.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
	pick.text = "%s\n%s    %s" % [
		entry["name"], entry["summary"], entry["saved_at"].replace("T", "  ")
	]
	pick.add_theme_font_size_override("font_size", 12)
	pick.pressed.connect(_on_row_pressed.bind(entry))
	row.add_child(pick)

	var remove := Button.new()
	remove.text = "Delete" if _pending_delete != entry["path"] else "Sure?"
	remove.custom_minimum_size = Vector2(80, ROW_HEIGHT)
	remove.add_theme_font_size_override("font_size", 11)
	if _pending_delete == entry["path"]:
		remove.modulate = Color(1.0, 0.55, 0.5)
	remove.pressed.connect(_on_delete_pressed.bind(entry))
	row.add_child(remove)

	return row
