extends Control
 
signal unit_hovered(unit)
signal unit_unhovered
signal deployment_confirmed
 
const SWATCH_SIZE := Vector2(44, 44)
const COLOR_PLAYER := Color(0.92, 0.92, 0.90)
const COLOR_ALLY := Color(0.25, 0.75, 0.35)
const COLOR_ENEMY := Color(0.80, 0.20, 0.20)
const COLOR_ACTIVE := Color(1.0, 0.85, 0.35)
 
@onready var turn_label: Label = $Panel/Margin/HBox/TurnLabel
@onready var move_label: Label = $Panel/Margin/HBox/MoveLabel
@onready var end_turn_button: Button = $Panel/Margin/HBox/EndTurnButton
@onready var flee_button: Button = $Panel/Margin/HBox/FleeButton
 
var combat: Combat = null
 
var _order_bar: PanelContainer
var _order_row: HBoxContainer
var _entries: Dictionary = {}      # unit -> { frame, health }
var _deploy_button: Button
 
 
func _ready() -> void:
	hide()
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	flee_button.pressed.connect(_on_flee_pressed)
	_build_order_bar()
 
 
func bind(new_combat: Combat) -> void:
	combat = new_combat
	combat.turn_changed.connect(_on_turn_changed)
	combat.order_changed.connect(_rebuild_order)
 
	_rebuild_order(combat.order)
	_on_turn_changed(combat.active, combat.round_number, combat.player_controlled())
	show()
 
 
# ------------------------------------------------------------- turn order bar
 
func _build_order_bar() -> void:
	_order_bar = PanelContainer.new()
	_order_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_order_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_order_bar.grow_vertical = Control.GROW_DIRECTION_END
	_order_bar.offset_top = -10
	_order_bar.offset_bottom = 20
	_order_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
 
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.06, 0.06, 0.08, 0.85)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(8)
	box.border_color = Color(1, 1, 1, 0.15)
	box.set_border_width_all(1)
	_order_bar.add_theme_stylebox_override("panel", box)
 
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
	if not _entries.has(unit) or not is_instance_valid(unit):
		return
	var current: int = unit.current_health if "current_health" in unit else 0
	var maximum: int = unit.max_health() if unit.has_method("max_health") else 0
	_entries[unit]["health"].text = "%d/%d" % [current, maximum]
 
 
func _highlight_active() -> void:
	if combat == null:
		return
	for unit in _entries.keys():
		var style: StyleBoxFlat = _entries[unit]["frame"].get_theme_stylebox("panel")
		style.bg_color = COLOR_ACTIVE if unit == combat.active else Color(0, 0, 0, 0)
 
 
# -------------------------------------------------------------------- panel
 
func _on_turn_changed(_unit, _round_number: int, player_controlled: bool) -> void:
	end_turn_button.disabled = not player_controlled
	_highlight_active()
 
 
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
 
