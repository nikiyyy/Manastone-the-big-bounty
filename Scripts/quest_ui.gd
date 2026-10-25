extends CanvasLayer
## Quest log. Q opens it, Escape closes. Left is the list grouped by category,
## right is the selected quest's objectives, story text and rewards.

const COLOR_DONE := "#7ec97e"
const COLOR_PENDING := "#e8e4d8"
const COLOR_MUTED := "#8f8f8f"
const COLOR_TITLE := "#ffd36b"

var _root: Control
var _count_label: Label
var _list: VBoxContainer
var _page: RichTextLabel

var _selected: StringName = ""


func _ready() -> void:
	layer = 57
	add_to_group("quest_ui")
	_build()
	_root.hide()

	Quests.quest_started.connect(func(_q): _refresh_if_open())
	Quests.quest_advanced.connect(func(_q, _s): _refresh_if_open())
	Quests.objective_progressed.connect(func(_q, _o, _n, _r): _refresh_if_open())
	Quests.quest_completed.connect(func(_q): _refresh_if_open())


func is_open() -> bool:
	return _root.visible


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	if event.keycode == KEY_Q:
		toggle()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and is_open():
		close()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


func open() -> void:
	Quests.refresh()
	_root.show()
	_rebuild()


func close() -> void:
	_root.hide()


func _refresh_if_open() -> void:
	if is_open():
		_rebuild()

# ------------------------------------------------------------------ contents

func _rebuild() -> void:
	var quests: Array = Quests.active_quests()
	_count_label.text = "Quests: %d" % quests.size()

	if not quests.is_empty() and _selected.is_empty():
		_selected = quests[0].id
	if Quests.quest(_selected) == null or not Quests.is_active(_selected):
		_selected = quests[0].id if not quests.is_empty() else &""

	_rebuild_list(quests)
	_rebuild_page()


func _rebuild_list(quests: Array) -> void:
	for child in _list.get_children():
		child.queue_free()

	if quests.is_empty():
		var empty := Label.new()
		empty.text = "No active quests."
		empty.add_theme_font_size_override("font_size", 12)
		empty.modulate = Color(1, 1, 1, 0.45)
		_list.add_child(empty)
		return

	var current_category: String = ""
	for q in quests:
		if q.category != current_category:
			current_category = q.category
			var header := Label.new()
			header.text = current_category
			header.add_theme_font_size_override("font_size", 12)
			header.modulate = Color(1, 0.85, 0.5)
			_list.add_child(header)

		_list.add_child(_list_row(q))


func _list_row(q: Quest) -> Button:
	# not named `ready`: that shadows Node's own signal
	var done: bool = Quests.is_ready_to_turn_in(q.id)

	var button := Button.new()
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 12)
	button.custom_minimum_size = Vector2(0, 26)
	button.text = "[%d] %s" % [q.level, q.title]
	if done:
		button.text += "   (Complete)"

	if q.id == _selected:
		button.modulate = Color(1, 0.9, 0.6)
	elif done:
		button.modulate = Color(0.55, 0.9, 0.55)
	else:
		button.modulate = Color(1, 1, 1, 0.8)

	button.pressed.connect(func():
		_selected = q.id
		_rebuild()
	)
	return button


func _rebuild_page() -> void:
	var q: Quest = Quests.quest(_selected)
	if q == null:
		_page.text = "[i]Pick a quest from the list.[/i]"
		return

	var parts: Array = []
	parts.append("[font_size=19][color=%s]%s[/color][/font_size]" % [COLOR_TITLE, q.title])
	parts.append("")

	var stage: QuestStage = Quests.current_stage(q.id)
	if stage != null and not stage.text.is_empty():
		parts.append("[color=%s]%s[/color]" % [COLOR_PENDING, stage.text])
		parts.append("")

	parts.append_array(_objective_lines(q, stage))

	if Quests.is_ready_to_turn_in(q.id):
		parts.append("")
		var hint: String = q.turn_in_hint if not q.turn_in_hint.is_empty() else "Report back."
		parts.append("[color=%s]%s[/color]" % [COLOR_DONE, hint])

	if not q.description.is_empty():
		parts.append("")
		parts.append("[font_size=15][b]Description[/b][/font_size]")
		parts.append("[color=%s]%s[/color]" % [COLOR_MUTED, q.description])

	var rewards: Array = q.reward_lines()
	if not rewards.is_empty():
		parts.append("")
		parts.append("[font_size=15][b]Rewards[/b][/font_size]")
		for line in rewards:
			parts.append("[color=%s]  %s[/color]" % [COLOR_PENDING, line])

	_page.text = "\n".join(parts)
	_page.scroll_to_line(0)


func _objective_lines(q: Quest, stage: QuestStage) -> Array:
	if stage == null:
		return []

	var lines: Array = []
	for objective in stage.objectives:
		if objective == null:
			continue
		var progress: int = Quests.objective_progress(q.id, objective)
		var done: bool = objective.is_done(progress)
		if objective.hidden_until_done and not done:
			continue

		var text: String = objective.label(progress)
		if objective.optional:
			text += "  (optional)"
		lines.append("[color=%s]%s%s[/color]" % [
			COLOR_DONE if done else COLOR_PENDING,
			"✓ " if done else "",
			text,
		])
	return lines


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
	box.set_content_margin_all(18)
	box.border_color = Color(1, 1, 1, 0.18)
	box.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", box)
	center.add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	outer.custom_minimum_size = Vector2(860, 520)
	panel.add_child(outer)

	outer.add_child(_build_header())

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(columns)

	columns.add_child(_build_list_column())
	columns.add_child(_build_page_column())

	outer.add_child(_build_footer())


func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var title := Label.new()
	title.text = "Quest log"
	title.add_theme_font_size_override("font_size", 22)
	title.modulate = Color(1, 0.85, 0.4)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)

	_count_label = Label.new()
	_count_label.add_theme_font_size_override("font_size", 12)
	_count_label.modulate = Color(1, 1, 1, 0.6)
	row.add_child(_count_label)

	return row


func _build_list_column() -> Control:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(270, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 3)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	return scroll


func _build_page_column() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	_page = RichTextLabel.new()
	_page.bbcode_enabled = true
	_page.fit_content = true
	_page.selection_enabled = true
	_page.add_theme_font_size_override("normal_font_size", 13)
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.custom_minimum_size = Vector2(530, 0)
	scroll.add_child(_page)

	return scroll


func _build_footer() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var hint := Label.new()
	hint.text = "Q or Esc to close"
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(1, 1, 1, 0.45)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(hint)

	return row
