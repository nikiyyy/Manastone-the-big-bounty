extends CanvasLayer
## End-of-battle summary. Holds the battle open until dismissed.

signal dismissed

var _root: Control
var _title: Label
var _highlights: VBoxContainer
var _table: VBoxContainer
var _rewards: Label


func _ready() -> void:
	layer = 55
	_build()
	_root.hide()


func show_results(won: bool, log: BattleLog, friendly: Array) -> void:
	_title.text = "Victory" if won else "Defeat"
	_title.modulate = Color(1, 0.85, 0.4) if won else Color(1, 0.45, 0.45)

	_fill_highlights(log, friendly)
	_fill_table(log, friendly)

	var parts: Array = ["%d round%s" % [log.rounds, "" if log.rounds == 1 else "s"]]
	if log.xp_awarded > 0:
		parts.append("%d xp" % log.xp_awarded)
	if log.gold_looted > 0:
		parts.append("%d gold" % log.gold_looted)
	_rewards.text = "  •  ".join(parts)

	_root.show()


func _fill_highlights(log: BattleLog, friendly: Array) -> void:
	for child in _highlights.get_children():
		child.queue_free()

	var top_damage = log.leader(log.damage_dealt, friendly)
	var top_taken = log.leader(log.damage_taken, friendly)
	var top_kills = log.leader(log.kills, friendly)

	if top_damage != null:
		_highlights.add_child(_highlight(
			"Most damage dealt", top_damage["name"], "%d" % top_damage["value"],
			Color(1.0, 0.55, 0.35)
		))
	if top_taken != null:
		_highlights.add_child(_highlight(
			"Most damage taken", top_taken["name"], "%d" % top_taken["value"],
			Color(0.55, 0.75, 1.0)
		))
	if top_kills != null:
		_highlights.add_child(_highlight(
			"Most kills", top_kills["name"], "%d" % top_kills["value"],
			Color(0.95, 0.85, 0.4)
		))


func _highlight(caption: String, who: String, value: String, tint: Color) -> Control:
	var chip := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(tint.r, tint.g, tint.b, 0.12)
	box.set_corner_radius_all(5)
	box.set_content_margin_all(9)
	chip.add_theme_stylebox_override("panel", box)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)

	var caption_label := Label.new()
	caption_label.text = caption
	caption_label.add_theme_font_size_override("font_size", 11)
	caption_label.modulate = Color(1, 1, 1, 0.6)
	caption_label.custom_minimum_size = Vector2(130, 0)
	line.add_child(caption_label)

	var who_label := Label.new()
	who_label.text = who
	who_label.add_theme_font_size_override("font_size", 13)
	who_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(who_label)

	var value_label := Label.new()
	value_label.text = value
	value_label.add_theme_font_size_override("font_size", 15)
	value_label.modulate = tint
	line.add_child(value_label)

	chip.add_child(line)
	return chip


func _fill_table(log: BattleLog, friendly: Array) -> void:
	for child in _table.get_children():
		child.queue_free()

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 4)
	_table.add_child(grid)

	for heading in ["Unit", "Dealt", "Taken", "Kills"]:
		var head := Label.new()
		head.text = heading
		head.add_theme_font_size_override("font_size", 11)
		head.modulate = Color(1, 0.85, 0.5)
		grid.add_child(head)

	for row in log.rows_for(friendly):
		var name_label := Label.new()
		name_label.text = row["name"] if row["alive"] else "%s  (down)" % row["name"]
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.modulate = Color.WHITE if row["alive"] else Color(1, 1, 1, 0.45)
		name_label.custom_minimum_size = Vector2(160, 0)
		grid.add_child(name_label)

		for key in ["dealt", "taken", "kills"]:
			var cell := Label.new()
			cell.text = str(row[key])
			cell.add_theme_font_size_override("font_size", 12)
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			cell.custom_minimum_size = Vector2(50, 0)
			grid.add_child(cell)


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
	box.set_content_margin_all(22)
	box.border_color = Color(1, 1, 1, 0.18)
	box.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", box)
	center.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	column.custom_minimum_size = Vector2(460, 0)
	panel.add_child(column)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 26)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)

	_rewards = Label.new()
	_rewards.add_theme_font_size_override("font_size", 12)
	_rewards.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rewards.modulate = Color(1, 1, 1, 0.7)
	column.add_child(_rewards)

	column.add_child(HSeparator.new())

	_highlights = VBoxContainer.new()
	_highlights.add_theme_constant_override("separation", 5)
	column.add_child(_highlights)

	column.add_child(HSeparator.new())

	_table = VBoxContainer.new()
	column.add_child(_table)

	var button := Button.new()
	button.text = "Continue"
	button.custom_minimum_size = Vector2(0, 34)
	button.pressed.connect(func():
		_root.hide()
		dismissed.emit()
	)
	column.add_child(button)
