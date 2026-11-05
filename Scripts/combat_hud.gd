extends Control
 
signal unit_hovered(unit)
signal unit_unhovered
signal deployment_confirmed
 
const SWATCH_SIZE := Vector2(44, 44)
const COLOR_PLAYER := Color(0.92, 0.92, 0.90)
const COLOR_ALLY := Color(0.25, 0.75, 0.35)
const COLOR_ENEMY := Color(0.80, 0.20, 0.20)
const COLOR_ACTIVE := Color(1.0, 0.85, 0.35)
 
# A warm, dark palette standing in for the painted frames in the real thing.
const BAR_BG := Color(0.07, 0.065, 0.05, 0.94)
const GOLD := Color(0.72, 0.58, 0.30)
const GOLD_DIM := Color(0.38, 0.31, 0.18)
const SLOT_BG := Color(0.145, 0.125, 0.10)
const SLOT_EMPTY_BG := Color(0.085, 0.078, 0.065)
 
const COLOR_MANA := Color(0.26, 0.40, 0.72)
const COLOR_MOVE := Color(0.26, 0.52, 0.30)
const COLOR_ACTION := Color(0.58, 0.44, 0.16)
 
const SLOT_SIZE := 46
const SLOT_COLUMNS := 6
const SLOT_ROWS := 2
const AVATAR_SIZE := 86
const DOT_SIZE := 38
const END_TURN_SIZE := 78
const FLEE_SIZE := 42
const EDGE_MARGIN := 18
const BOTTOM_MARGIN := 12
 
## Which list the hotbar is showing.
enum Bar { ABILITIES, ITEMS }
 
# The old panel is left in the scene but hidden — the bars below replace it.
@onready var turn_label: Label = get_node_or_null("Panel/Margin/HBox/TurnLabel")
@onready var move_label: Label = get_node_or_null("Panel/Margin/HBox/MoveLabel")
@onready var end_turn_button: Button = get_node_or_null("Panel/Margin/HBox/EndTurnButton")
@onready var flee_button: Button = get_node_or_null("Panel/Margin/HBox/FleeButton")
 
var combat: Combat = null
## The battle map. Duck-typed: the HUD asks it what to show and tells it what
## was clicked, rather than working any of it out itself.
var map = null
 
var _order_bar: PanelContainer
var _order_row: HBoxContainer
var _entries: Dictionary = {}      # unit -> { frame, health }
var _deploy_button: Button
 
## Holds the three bottom panels so they show and hide together.
var _action_bar: Control
 
var _avatar: Panel
var _avatar_health: Label
var _mana_dot: Label
var _move_dot: Label
var _action_dot: Label
 
var _melee_button: Button
var _ranged_button: Button
var _slots: Array = []             # the hotbar buttons, left to right
var _abilities_tab: Button
var _items_tab: Button
var _end_turn_circle: Button
var _flee_circle: Button
 
var _bar_mode: int = Bar.ABILITIES
## Only the movement signal carries the maximum, so it's kept for the poll.
var _move_max: int = 0
 
 
func _ready() -> void:
	hide()
	var old_panel := get_node_or_null("Panel")
	if old_panel != null:
		old_panel.hide()
 
	_build_order_bar()
	_build_action_bar()
	_action_bar.hide()
 
 
func bind(new_combat: Combat, battle_map = null) -> void:
	combat = new_combat
	map = battle_map
 
	combat.turn_changed.connect(_on_turn_changed)
	combat.order_changed.connect(_rebuild_order)
	if combat.has_signal("movement_changed"):
		combat.movement_changed.connect(_on_movement_changed)
	if map != null and map.has_signal("attack_mode_changed"):
		map.attack_mode_changed.connect(func(_mode): _refresh_stance())
 
	_rebuild_order(combat.order)
	_on_turn_changed(combat.active, combat.round_number, combat.player_controlled())
	_action_bar.show()
	show()
 
 
# ------------------------------------------------------------- turn order bar
 
func _build_order_bar() -> void:
	_order_bar = PanelContainer.new()
	_order_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_order_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_order_bar.grow_vertical = Control.GROW_DIRECTION_END
	_order_bar.offset_top = -10
	_order_bar.offset_bottom = -10
	_order_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_order_bar.add_theme_stylebox_override("panel", _panel_style())
 
	_order_row = HBoxContainer.new()
	_order_row.add_theme_constant_override("separation", 6)
	_order_bar.add_child(_order_row)
	add_child(_order_bar)
 
 
func _rebuild_order(order: Array) -> void:
	for child in _order_row.get_children():
		child.queue_free()
	_entries.clear()
 
	for unit in order:
		if not is_instance_valid(unit):
			continue
		if unit.has_method("is_alive") and not unit.is_alive():
			continue
		_order_row.add_child(_make_entry(unit))
	_highlight_active()
 
 
func _make_entry(unit) -> Control:
	# outer frame — its background is the active-turn highlight
	var frame := PanelContainer.new()
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0, 0, 0, 0)
	frame_style.set_corner_radius_all(4)
	frame_style.set_content_margin_all(3)
	frame.add_theme_stylebox_override("panel", frame_style)
 
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
 
	# the portrait, and the only part of the entry that answers the mouse
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = SWATCH_SIZE
	swatch.color = _color_for(unit)
	swatch.mouse_filter = Control.MOUSE_FILTER_STOP
	swatch.tooltip_text = _tooltip_for(unit)
	swatch.mouse_entered.connect(func(): unit_hovered.emit(unit))
	swatch.mouse_exited.connect(func(): unit_unhovered.emit())
 
	var health := Label.new()
	health.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	health.add_theme_font_size_override("font_size", 13)
 
	column.add_child(swatch)
	column.add_child(health)
	frame.add_child(column)
 
	_entries[unit] = {"frame": frame, "health": health}
	_update_health(unit)
 
	if unit.has_signal("health_changed"):
		unit.health_changed.connect(func(_c, _m): _update_health(unit))
 
	return frame
 
 
## Initiative no longer takes up a line in the bar, so it lives here instead —
## rolled once at the start of the battle, it's reference rather than something
## you watch change.
func _tooltip_for(unit) -> String:
	var who: String = unit.display_name if "display_name" in unit else "Unit"
	if combat == null:
		return who
	return "%s\nInitiative %d" % [who, int(combat.initiative.get(unit, 0.0))]
 
 
func _color_for(unit) -> Color:
	if unit.has_method("is_enemy") and unit.is_enemy():
		return COLOR_ENEMY
	if unit.has_method("is_ally") and unit.is_ally():
		return COLOR_ALLY
	return COLOR_PLAYER
 
 
func _update_health(unit) -> void:
	if _entries.has(unit) and is_instance_valid(unit):
		_entries[unit]["health"].text = _health_text(unit)
	if combat != null and unit == combat.active:
		_refresh_avatar()
 
 
func _health_text(unit) -> String:
	var current: int = unit.current_health if "current_health" in unit else 0
	var maximum: int = unit.max_health() if unit.has_method("max_health") else 0
	return "%d/%d" % [current, maximum]
 
 
func _highlight_active() -> void:
	if combat == null:
		return
	for unit in _entries.keys():
		var style: StyleBoxFlat = _entries[unit]["frame"].get_theme_stylebox("panel")
		style.bg_color = COLOR_ACTIVE if unit == combat.active else Color(0, 0, 0, 0)
 
 
# ---------------------------------------------------------- the three panels
 
func _build_action_bar() -> void:
	_action_bar = Control.new()
	_action_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_action_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_action_bar)
 
	_action_bar.add_child(_panel_at(Control.PRESET_BOTTOM_LEFT, _build_status()))
	_action_bar.add_child(_panel_at(Control.PRESET_CENTER_BOTTOM, _build_hotbar()))
	_action_bar.add_child(_panel_at(Control.PRESET_BOTTOM_RIGHT, _build_turn_controls()))
 
 
## One of the three bottom panels, pinned to its corner of the screen.
func _panel_at(preset: int, contents: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(preset)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_top = -BOTTOM_MARGIN
	panel.offset_bottom = -BOTTOM_MARGIN
 
	match preset:
		Control.PRESET_BOTTOM_LEFT:
			panel.grow_horizontal = Control.GROW_DIRECTION_END
			panel.offset_left = EDGE_MARGIN
			panel.offset_right = EDGE_MARGIN
		Control.PRESET_BOTTOM_RIGHT:
			panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			panel.offset_left = -EDGE_MARGIN
			panel.offset_right = -EDGE_MARGIN
		_:
			panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
 
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.add_child(contents)
	return panel
 
 
# ------------------------------------------------------------- left: status
 
func _build_status() -> Control:
	# negative separation tucks the readout circles against the portrait, the
	# way the sketch has them clustered on its edge
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", -10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
 
	_avatar = Panel.new()
	_avatar.custom_minimum_size = Vector2(AVATAR_SIZE, AVATAR_SIZE)
	_avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_avatar.add_theme_stylebox_override("panel", _circle_style(COLOR_PLAYER, AVATAR_SIZE))
 
	_avatar_health = Label.new()
	_avatar_health.set_anchors_preset(Control.PRESET_FULL_RECT)
	_avatar_health.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_avatar_health.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_avatar_health.add_theme_font_size_override("font_size", 18)
	_avatar_health.add_theme_color_override("font_color", Color(0.08, 0.07, 0.06))
	_avatar_health.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_avatar.add_child(_avatar_health)
	row.add_child(_avatar)
 
	var dots := VBoxContainer.new()
	dots.add_theme_constant_override("separation", 2)
	dots.alignment = BoxContainer.ALIGNMENT_CENTER
	dots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
 
	var mana_circle := _dot_circle(COLOR_MANA, "Mana")
	_mana_dot = mana_circle.get_child(0)
	dots.add_child(mana_circle)
 
	var move_circle := _dot_circle(COLOR_MOVE, "Movement left")
	_move_dot = move_circle.get_child(0)
	dots.add_child(move_circle)
 
	var action_circle := _dot_circle(COLOR_ACTION, "Actions left")
	_action_dot = action_circle.get_child(0)
	dots.add_child(action_circle)
 
	row.add_child(dots)
	return row
 
 
## A small circle with a number in it. The label is its only child, which is
## how the caller above fishes it back out.
func _dot_circle(fill: Color, tooltip: String) -> Panel:
	var circle := Panel.new()
	circle.custom_minimum_size = Vector2(DOT_SIZE, DOT_SIZE)
	circle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	circle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	circle.tooltip_text = tooltip
	circle.add_theme_stylebox_override("panel", _circle_style(fill, DOT_SIZE))
 
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	circle.add_child(label)
 
	return circle
 
 
# ------------------------------------------------------------- middle: hotbar
 
func _build_hotbar() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
 
	row.add_child(_build_stance_column())
 
	var grid := GridContainer.new()
	grid.columns = SLOT_COLUMNS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
 
	for i in SLOT_COLUMNS * SLOT_ROWS:
		var slot := _framed_button("", SLOT_SIZE)
		slot.pressed.connect(_on_slot_pressed.bind(i))
		grid.add_child(slot)
		_slots.append(slot)
 
	row.add_child(grid)
	row.add_child(_build_filter_column())
	return row
 
 
## Stance picker down the left edge, ranged above melee as in the sketch.
func _build_stance_column() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
 
	_ranged_button = _tall_button("R", 34)
	_ranged_button.pressed.connect(func(): _choose_stance(1))
	column.add_child(_ranged_button)
 
	_melee_button = _tall_button("M", 34)
	_melee_button.tooltip_text = "Melee attack — strike the next unit you click"
	_melee_button.pressed.connect(func(): _choose_stance(0))
	column.add_child(_melee_button)
 
	return column
 
 
func _build_filter_column() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
 
	_abilities_tab = _tall_button("Abilities", 84)
	_abilities_tab.pressed.connect(func(): _set_bar_mode(Bar.ABILITIES))
	column.add_child(_abilities_tab)
 
	_items_tab = _tall_button("Items", 84)
	_items_tab.pressed.connect(func(): _set_bar_mode(Bar.ITEMS))
	column.add_child(_items_tab)
 
	return column
 
 
# -------------------------------------------------------- right: turn controls
 
func _build_turn_controls() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
 
	_end_turn_circle = _circle_button("End\nturn", END_TURN_SIZE, Color(0.24, 0.20, 0.12))
	_end_turn_circle.tooltip_text = "End this unit's turn"
	_end_turn_circle.pressed.connect(_on_end_turn_pressed)
	row.add_child(_end_turn_circle)
 
	_flee_circle = _circle_button("Flee", FLEE_SIZE, Color(0.26, 0.11, 0.11))
	_flee_circle.tooltip_text = "Leave the battle"
	_flee_circle.pressed.connect(_on_flee_pressed)
	row.add_child(_flee_circle)
 
	return row
 
 
# ------------------------------------------------------------------- the bar
 
func _choose_stance(mode: int) -> void:
	if map != null and map.has_method("set_attack_mode"):
		map.set_attack_mode(mode)
	_refresh_stance()
 
 
## Lit button is the stance you're in. Ranged greys out with no bow equipped,
## which is also the answer to "why can't I shoot".
func _refresh_stance() -> void:
	if map == null:
		return
	var unit = map.get_controlled_unit() if map.has_method("get_controlled_unit") else null
	var has_bow: bool = map.has_ranged_weapon(unit) if map.has_method("has_ranged_weapon") else false
	var ranged_now: bool = "attack_mode" in map and map.attack_mode == 1
 
	_ranged_button.disabled = not has_bow
	_ranged_button.tooltip_text = (
		"Ranged attack — shoot the next unit you click" if has_bow
		else "No ranged weapon equipped"
	)
	_paint_selected(_melee_button, not ranged_now)
	_paint_selected(_ranged_button, ranged_now)
 
 
func _set_bar_mode(mode: int) -> void:
	_bar_mode = mode
	_refresh_hotbar()
 
 
func _refresh_hotbar() -> void:
	_paint_selected(_abilities_tab, _bar_mode == Bar.ABILITIES)
	_paint_selected(_items_tab, _bar_mode == Bar.ITEMS)
 
	var entries: Array = _bar_entries()
	for i in _slots.size():
		var slot: Button = _slots[i]
		var filled: bool = i < entries.size()
 
		slot.text = _abbreviate(_entry_name(entries[i])) if filled else ""
		slot.tooltip_text = _entry_tooltip(entries[i]) if filled else ""
		slot.disabled = not filled
		_paint_slot(slot, filled)
 
 
func _bar_entries() -> Array:
	if map == null:
		return []
	if _bar_mode == Bar.ITEMS:
		return map.controlled_consumables() if map.has_method("controlled_consumables") else []
	return map.controlled_spells() if map.has_method("controlled_spells") else []
 
 
func _entry_name(entry) -> String:
	return entry.display_name if "display_name" in entry else "?"
 
 
func _entry_tooltip(entry) -> String:
	var lines: Array = [_entry_name(entry)]
	if _bar_mode == Bar.ITEMS:
		if entry.has_method("is_thrown") and entry.is_thrown():
			lines.append("Thrown — pick a target")
		else:
			lines.append("Drink")
	else:
		if "mana_cost" in entry:
			lines.append("%d mana" % entry.mana_cost)
		if "cast_range" in entry:
			lines.append("Range %d" % entry.cast_range)
	return "\n".join(lines)
 
 
## Three letters is enough to tell slots apart until there are icons.
func _abbreviate(text: String) -> String:
	var trimmed: String = text.strip_edges()
	if trimmed.is_empty():
		return ""
	return trimmed.substr(0, 3).to_upper()
 
 
func _on_slot_pressed(index: int) -> void:
	if map == null:
		return
	var entries: Array = _bar_entries()
	if index >= entries.size():
		return
 
	if _bar_mode == Bar.ITEMS:
		var unit = map.get_controlled_unit() if map.has_method("get_controlled_unit") else null
		if unit != null and map.has_method("use_consumable"):
			map.use_consumable(unit, entries[index])
		# drinking one empties the slot, so the bar has to be redrawn
		_refresh_hotbar()
	elif map.has_method("cast_spell_slot"):
		map.cast_spell_slot(index)
 
 
func _refresh_avatar() -> void:
	if combat == null or _avatar == null:
		return
	var unit = combat.active
	if unit == null or not is_instance_valid(unit):
		return
 
	_avatar.add_theme_stylebox_override("panel", _circle_style(_color_for(unit), AVATAR_SIZE))
	_avatar_health.text = _health_text(unit)
	_refresh_readouts()
 
 
## Mana drains when a spell is cast and the action is gone the moment it's
## used, and neither announces itself — so the three circles are read every
## frame rather than waiting for a signal that doesn't exist. Writing only on
## a change keeps it to three string compares.
func _process(_delta: float) -> void:
	if combat != null and _action_bar.visible:
		_refresh_readouts()
 
 
func _refresh_readouts() -> void:
	if combat == null or _mana_dot == null:
		return
	var unit = combat.active
	if unit == null or not is_instance_valid(unit):
		return
 
	var mana: int = unit.current_mana if "current_mana" in unit else 0
	var mana_max: int = unit.max_mana() if unit.has_method("max_mana") else 0
	_set_dot(_mana_dot, "%d/%d" % [mana, mana_max])
 
	var can_act: bool = combat.can_act() if combat.has_method("can_act") else false
	if _set_dot(_action_dot, "1/1" if can_act else "0/1"):
		_action_dot.modulate = Color.WHITE if can_act else Color(1, 0.6, 0.6)
 
	if "movement_left" in combat:
		var left: int = combat.movement_left
		_set_dot(_move_dot, "%d/%d" % [left, maxi(_move_max, left)])
 
 
## Returns true when the text actually changed.
func _set_dot(label: Label, text: String) -> bool:
	if label == null or label.text == text:
		return false
	label.text = text
	return true
 
 
func _on_movement_changed(remaining: int, maximum: int) -> void:
	_move_max = maximum
	_set_dot(_move_dot, "%d/%d" % [remaining, maximum])
	if move_label != null:
		move_label.text = "Move %d/%d" % [remaining, maximum]
 
 
# -------------------------------------------------------------------- panel
 
func _on_turn_changed(_unit, _round_number: int, player_controlled: bool) -> void:
	if end_turn_button != null:
		end_turn_button.disabled = not player_controlled
	_end_turn_circle.disabled = not player_controlled
 
	_highlight_active()
	_refresh_avatar()
	_refresh_stance()
	_refresh_hotbar()
 
 
func _on_end_turn_pressed() -> void:
	if combat != null:
		combat.end_turn()
 
 
func _on_flee_pressed() -> void:
	Game.end_battle.call_deferred()
 
 
func show_deployment() -> void:
	_deploy_button = Button.new()
	_deploy_button.text = "Start battle"
	_deploy_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_deploy_button.offset_left = -70
	_deploy_button.offset_right = 70
	_deploy_button.offset_top = -70
	_deploy_button.offset_bottom = -30
	_deploy_button.pressed.connect(func():
		deployment_confirmed.emit()
		_deploy_button.queue_free()
	)
	add_child(_deploy_button)
	show()
 
 
# ------------------------------------------------------------------- styling
 
func _panel_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = BAR_BG
	box.set_corner_radius_all(8)
	box.set_content_margin_all(10)
	box.border_color = GOLD_DIM
	box.set_border_width_all(2)
	return box
 
 
## A circle is a rounded rectangle whose corner radius is half its width — but
## only if it's actually square, which is why every caller pins both axes and
## stops the containers stretching it.
func _circle_style(fill: Color, diameter: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(int(diameter / 2.0))
	box.border_color = GOLD
	box.set_border_width_all(2)
	return box
 
 
func _circle_button(text: String, diameter: int, fill: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(diameter, diameter)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 11 if diameter < 60 else 14)
	button.add_theme_color_override("font_color", Color(0.93, 0.87, 0.72))
	button.add_theme_stylebox_override("normal", _circle_style(fill, diameter))
	button.add_theme_stylebox_override("hover", _circle_style(fill.lightened(0.18), diameter))
	button.add_theme_stylebox_override("pressed", _circle_style(fill.darkened(0.25), diameter))
	button.add_theme_stylebox_override("disabled", _circle_style(fill.darkened(0.5), diameter))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return button
 
 
func _slot_style(fill: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(3)
	return box
 
 
## Square, framed, and visible whether or not there's anything in it — an
## empty slot still has to read as a slot.
func _framed_button(text: String, side: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(side, side)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", Color(0.93, 0.87, 0.72))
	button.add_theme_color_override("font_disabled_color", Color(0.5, 0.45, 0.35, 0.5))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_paint_slot(button, true)
	return button
 
 
## Half the height of the slot grid, so two of them stack flush beside it.
func _tall_button(text: String, width: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(width, SLOT_SIZE)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_paint_selected(button, false)
	return button
 
 
func _paint_slot(button: Button, filled: bool) -> void:
	var fill: Color = SLOT_BG if filled else SLOT_EMPTY_BG
	var border: Color = GOLD_DIM if filled else Color(0.22, 0.19, 0.14)
	button.add_theme_stylebox_override("normal", _slot_style(fill, border))
	button.add_theme_stylebox_override("hover", _slot_style(fill.lightened(0.12), GOLD))
	button.add_theme_stylebox_override("pressed", _slot_style(fill.darkened(0.2), GOLD))
	button.add_theme_stylebox_override("disabled", _slot_style(SLOT_EMPTY_BG, border))
 
 
## The lit-up treatment shared by the stance buttons and the hotbar tabs.
func _paint_selected(button: Button, selected: bool) -> void:
	var fill: Color = Color(0.26, 0.21, 0.10) if selected else SLOT_EMPTY_BG
	var border: Color = GOLD if selected else GOLD_DIM
	button.add_theme_stylebox_override("normal", _slot_style(fill, border))
	button.add_theme_stylebox_override("hover", _slot_style(fill.lightened(0.14), GOLD))
	button.add_theme_stylebox_override("pressed", _slot_style(fill.darkened(0.2), GOLD))
	button.add_theme_stylebox_override("disabled", _slot_style(SLOT_EMPTY_BG, Color(0.2, 0.18, 0.13)))
	button.add_theme_color_override(
		"font_color", COLOR_ACTIVE if selected else Color(0.72, 0.68, 0.60)
	)
 
