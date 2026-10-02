extends Control
## Press Tab to open. Builds its own layout so adding a stat to Stats.NAMES
## is the only change needed to show it here.
 
const PORTRAIT_SIZE := 44
const COLOR_PLAYER := Color(0.92, 0.92, 0.90)
const COLOR_ALLY := Color(0.25, 0.75, 0.35)
const COLOR_SELECTED := Color(1.0, 0.85, 0.35)
const INVENTORY_CELLS := 16
const CELL_SIZE := Vector2(48, 48)
 
const TAB_STATS := 0
const TAB_TALENTS := 1
const TALENT_CELL := 54
const TALENT_GAP := 22
 
var _tab: int = TAB_STATS
var _tab_buttons: Array = []
var _pages: Array = []
var _talent_root: VBoxContainer
 
var _selected = null
var _party_row: HBoxContainer
var _portraits: Dictionary = {}      # unit -> Button
var player: Node = null
var _slot_buttons: Dictionary = {}
var _item_buttons: Array = []
var _panel: PanelContainer
var _header: Label
var _points_label: Label
var _rows: Dictionary = {}           # stat name -> { value: Label, button: Button }
var _xp_bar: ProgressBar
var _xp_label: Label
var _defence_row: HBoxContainer
 
 
func _ready() -> void:
	add_to_group("character_sheet")
	Game.battle_started.connect(func(_b): hide())
	_build()
	hide()
	Game.player_spawned.connect(_on_player_spawned)
	if Game.player != null:
		_on_player_spawned(Game.player)
 
 
func is_open() -> bool:
	return visible
 
 
func _on_player_spawned(new_player: Node) -> void:
	player = new_player
	_selected = new_player
	if player.has_signal("gold_changed"):
		player.gold_changed.connect(func(_g): _refresh())
	if player.has_signal("xp_changed"):
		player.xp_changed.connect(func(_x): _refresh())
	if visible:
		_refresh()
 
 
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
 
	if event.keycode == KEY_TAB:
		if Game.in_battle() and not visible:
			return
		_toggle()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and visible:
		hide()
		get_viewport().set_input_as_handled()
 
 
func _toggle() -> void:
	if visible:
		hide()
	else:
		_refresh()
		show()
 
 
# ------------------------------------------------------------------ layout
 
func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
 
	_panel = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.08, 0.08, 0.10, 0.96)
	box.set_corner_radius_all(8)
	box.set_content_margin_all(16)
	box.border_color = Color(1, 1, 1, 0.18)
	box.set_border_width_all(1)
	_panel.add_theme_stylebox_override("panel", box)
	center.add_child(_panel)
 
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	_panel.add_child(outer)
 
	_header = Label.new()
	_header.add_theme_font_size_override("font_size", 17)
	outer.add_child(_header)
 
	_xp_bar = ProgressBar.new()
	_xp_bar.custom_minimum_size = Vector2(0, 14)
	_xp_bar.show_percentage = false
	outer.add_child(_xp_bar)
 
	_xp_label = Label.new()
	_xp_label.add_theme_font_size_override("font_size", 11)
	_xp_label.modulate = Color(1, 1, 1, 0.65)
	outer.add_child(_xp_label)
 
	_defence_row = HBoxContainer.new()
	_defence_row.add_theme_constant_override("separation", 12)
	outer.add_child(_defence_row)
 
	_party_row = HBoxContainer.new()
	_party_row.add_theme_constant_override("separation", 8)
	outer.add_child(_party_row)
 
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	outer.add_child(tabs)
 
	for entry in [{"label": "Character", "id": TAB_STATS}, {"label": "Talents", "id": TAB_TALENTS}]:
		var tab_button := Button.new()
		tab_button.text = entry["label"]
		tab_button.custom_minimum_size = Vector2(110, 26)
		tab_button.add_theme_font_size_override("font_size", 12)
		tab_button.pressed.connect(_on_tab_pressed.bind(entry["id"]))
		tabs.add_child(tab_button)
		_tab_buttons.append(tab_button)
 
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	columns.add_child(_build_stats_panel())
	columns.add_child(_build_equipment_panel())
	columns.add_child(_build_inventory_panel())
	outer.add_child(columns)
 
	_talent_root = VBoxContainer.new()
	_talent_root.add_theme_constant_override("separation", 8)
	_talent_root.custom_minimum_size = Vector2(620, 330)
	outer.add_child(_talent_root)
 
	_pages = [columns, _talent_root]
	_show_tab(TAB_STATS)
 
	var hint := Label.new()
	hint.text = "Tab or Esc to close"
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(1, 1, 1, 0.5)
	outer.add_child(hint)
 
 
func _on_tab_pressed(id: int) -> void:
	_show_tab(id)
	_refresh()
 
 
func _show_tab(id: int) -> void:
	_tab = id
	for i in _pages.size():
		_pages[i].visible = (i == id)
	for i in _tab_buttons.size():
		_tab_buttons[i].modulate = Color.WHITE if i == id else Color(1, 1, 1, 0.5)
 
 
func _build_stats_panel() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.custom_minimum_size = Vector2(220, 0)
 
	column.add_child(_section_title("Stats"))
 
	_points_label = Label.new()
	_points_label.add_theme_font_size_override("font_size", 12)
	column.add_child(_points_label)
 
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 2)
	column.add_child(grid)
 
	for stat_name in Stats.NAMES:
		var name_label := Label.new()
		name_label.text = Stats.LABELS[stat_name]
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.custom_minimum_size = Vector2(110, 0)
		grid.add_child(name_label)
 
		var value_label := Label.new()
		value_label.add_theme_font_size_override("font_size", 12)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.custom_minimum_size = Vector2(32, 0)
		grid.add_child(value_label)
 
		var button := Button.new()
		button.text = "+"
		button.custom_minimum_size = Vector2(26, 22)
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(_on_raise.bind(stat_name))
		grid.add_child(button)
 
		_rows[stat_name] = {"value": value_label, "button": button}
 
	return column
 
 
func _build_equipment_panel() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.custom_minimum_size = Vector2(180, 0)
 
	column.add_child(_section_title("Equipment"))
 
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
 
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
 
	for slot in Inventory.SLOT_ORDER:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 3)
 
		var button := _make_slot_button(CELL_SIZE, "equipment", slot)
		cell.add_child(button)
 
		var caption := Label.new()
		caption.text = Inventory.SLOT_LABELS[slot]
		caption.add_theme_font_size_override("font_size", 10)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.modulate = Color(1, 1, 1, 0.6)
		cell.add_child(caption)
 
		row.add_child(cell)
		_slot_buttons[slot] = button
 
	return column
 
 
func _build_inventory_panel() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
 
	column.add_child(_section_title("Inventory"))
 
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	column.add_child(grid)
 
	for i in INVENTORY_CELLS:
		var button := _make_slot_button(CELL_SIZE, "inventory", i)
		grid.add_child(button)
		_item_buttons.append(button)
 
	return column
 
 
func _section_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.modulate = Color(1, 0.85, 0.5)
	return label
 
 
func _make_slot_button(size: Vector2, kind: String, key) -> Button:
	var button := Button.new()
	button.custom_minimum_size = size
	button.clip_text = true
	button.add_theme_font_size_override("font_size", 10)
 
	var icon := ColorRect.new()
	icon.name = "Icon"
	icon.color = Color(0.55, 0.35, 0.85)
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 5
	icon.offset_top = 5
	icon.offset_right = -5
	icon.offset_bottom = -5
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.visible = false
	button.add_child(icon)
 
	button.set_drag_forwarding(
		_drag_from.bind(kind, key),
		_can_drop_here.bind(kind, key),
		_drop_here.bind(kind, key)
	)
	return button
 
 
# ------------------------------------------------------------------- data
 
func _refresh() -> void:
	if player == null or not is_instance_valid(player):
		return
	if _selected == null or not is_instance_valid(_selected):
		_selected = player
 
	_rebuild_party()
 
	var unit = _selected
	var stats: Stats = unit.stats
	if stats == null:
		return
 
	var klass: String = unit.class_name_of() if unit.has_method("class_name_of") else "—"
	var mana: int = unit.current_mana if "current_mana" in unit else 0
	var mana_max: int = unit.max_mana() if unit.has_method("max_mana") else 0
	var who: String = unit.display_name if "display_name" in unit else "Unit"
	var gold: int = player.gold if "gold" in player else 0
	var xp: int = unit.xp if "xp" in unit else 0
 
	var progress: Dictionary = Progression.progress(xp)
 
	_header.text = "%s   %s   lvl %d   mana %d/%d   %d gold" % [
		who, klass, progress["level"], mana, mana_max, gold
	]
 
	_rebuild_defences(unit)
 
	_xp_bar.max_value = 100.0
	_xp_bar.value = progress["ratio"] * 100.0
 
	if progress["maxed"]:
		_xp_label.text = "Max level (%d xp)" % xp
	else:
		_xp_label.text = "%d / %d xp toward level %d" % [
			progress["into"], progress["needed"], progress["level"] + 1
		]
 
	_points_label.text = "Points to spend: %d" % stats.available_points
 
	for stat_name in Stats.NAMES:
		var base: int = stats.get(stat_name)
		var now: int = unit.modified_stat(stat_name) if unit.has_method("modified_stat") else base
		var cell: Label = _rows[stat_name]["value"]
		cell.text = str(now) if now == base else "%d (%d)" % [now, base]
		cell.modulate = Color.WHITE if now == base else Color(0.6, 0.9, 1.0)
		_rows[stat_name]["button"].disabled = not stats.can_raise()
 
	var gear: Inventory = unit.inventory if "inventory" in unit else null
	for slot in Inventory.SLOT_ORDER:
		_paint_cell(_slot_buttons[slot], gear.get_equipped(slot) if gear != null else null)
 
	var pack: Inventory = _backpack()
	for i in _item_buttons.size():
		var carried: Item = null
		if pack != null and i < pack.items.size():
			carried = pack.items[i]
		_paint_cell(_item_buttons[i], carried)
 
	if _tab == TAB_TALENTS:
		_rebuild_talents(unit)
 
 
func _on_raise(stat_name: String) -> void:
	if _selected == null or _selected.stats == null:
		return
	if _selected.stats.raise(stat_name):
		_refresh()
 
 
func _paint_cell(button: Button, item: Item) -> void:
	var icon: ColorRect = button.get_node("Icon")
	icon.visible = item != null
	if item != null:
		icon.color = Color(0.55, 0.35, 0.85)
		button.tooltip_text = item.tooltip()
		button.modulate = item.rarity_color()
	else:
		button.tooltip_text = ""
		button.modulate = Color.WHITE
 
 
# ----------------------------------------------------------------- talents
 
func _rebuild_talents(unit) -> void:
	for child in _talent_root.get_children():
		child.queue_free()
 
	var klass: CharacterClass = unit.character_class if "character_class" in unit else null
	var tree: TalentTree = klass.talent_tree if klass != null else null
 
	if tree == null:
		var none := Label.new()
		none.text = "No talent tree for this class."
		none.add_theme_font_size_override("font_size", 12)
		none.modulate = Color(1, 1, 1, 0.5)
		_talent_root.add_child(none)
		return
 
	var header := Label.new()
	var points: int = unit.stats.talent_points if unit.stats != null else 0
	header.text = "%s     %d point%s to spend" % [
		tree.display_name, points, "" if points == 1 else "s"
	]
	header.add_theme_font_size_override("font_size", 14)
	header.modulate = Color(1, 0.85, 0.5)
	_talent_root.add_child(header)
 
	# fixed grid so nodes keep their authored positions
	var grid := GridContainer.new()
	grid.columns = maxi(1, tree.columns_used())
	grid.add_theme_constant_override("h_separation", TALENT_GAP)
	grid.add_theme_constant_override("v_separation", TALENT_GAP)
	_talent_root.add_child(grid)
 
	var placed: Dictionary = {}
	for t in tree.talents:
		if t != null:
			placed[Vector2i(t.column, t.row)] = t
 
	for row in tree.rows_used():
		for col in grid.columns:
			var talent: Talent = placed.get(Vector2i(col, row))
			grid.add_child(_talent_cell(unit, talent))
 
 
func _talent_cell(unit, talent: Talent) -> Control:
	if talent == null:
		var blank := Control.new()
		blank.custom_minimum_size = Vector2(TALENT_CELL, TALENT_CELL)
		return blank
 
	var rank: int = unit.talent_rank(talent)
	var learnable: bool = unit.can_learn(talent)
	var maxed: bool = rank >= talent.max_ranks
 
	var button := Button.new()
	button.custom_minimum_size = Vector2(TALENT_CELL, TALENT_CELL)
	button.text = "%d/%d" % [rank, talent.max_ranks]
	button.add_theme_font_size_override("font_size", 11)
	button.disabled = not learnable
	button.tooltip_text = _talent_tooltip(talent, rank)
	button.pressed.connect(_on_talent_pressed.bind(talent))
 
	# learned nodes glow, available ones are lit, locked ones are dim
	var tint: Color = talent.icon_color
	var alpha: float = 0.9 if rank > 0 else (0.5 if learnable else 0.18)
 
	var box := StyleBoxFlat.new()
	box.bg_color = Color(tint.r, tint.g, tint.b, alpha * 0.4)
	box.set_corner_radius_all(6)
	box.border_color = Color(tint.r, tint.g, tint.b, alpha)
	box.set_border_width_all(3 if maxed else 1)
	button.add_theme_stylebox_override("normal", box)
	button.add_theme_stylebox_override("hover", box)
	button.add_theme_stylebox_override("pressed", box)
	button.add_theme_stylebox_override("disabled", box)
 
	return button
 
 
func _talent_tooltip(talent: Talent, rank: int) -> String:
	var lines: Array = ["%s  (%d/%d)" % [talent.display_name, rank, talent.max_ranks]]
	if not talent.description.is_empty():
		lines.append(talent.description)
	if talent.requires != null:
		lines.append("Requires: %s" % talent.requires.display_name)
	if talent.required_points > 0:
		lines.append("Requires %d points in this tree" % talent.required_points)
	return "\n".join(lines)
 
 
func _on_talent_pressed(talent: Talent) -> void:
	if _selected != null and _selected.has_method("learn_talent"):
		if _selected.learn_talent(talent):
			_refresh()
 
 
# ------------------------------------------------------------ drag and drop
## Bound args arrive after the engine's own, hence (at, [data,] kind, key).
 
## The backpack is always the player's; equipment belongs to the selected unit.
func _backpack() -> Inventory:
	if player == null or not is_instance_valid(player) or not "inventory" in player:
		return null
	return player.inventory
 
 
func _gear() -> Inventory:
	if _selected == null or not is_instance_valid(_selected) or not "inventory" in _selected:
		return null
	return _selected.inventory
 
 
func _item_at(kind: String, key) -> Item:
	if kind == "equipment":
		var gear := _gear()
		return gear.get_equipped(key) if gear != null else null
	var pack := _backpack()
	if pack == null or key >= pack.items.size():
		return null
	return pack.items[key]
 
 
func _drag_from(_at: Vector2, kind: String, key) -> Variant:
	var item: Item = _item_at(kind, key)
	if item == null:
		return null
 
	var preview := ColorRect.new()
	preview.color = Color(0.55, 0.35, 0.85, 0.8)
	preview.custom_minimum_size = Vector2(44, 44)
	preview.size = Vector2(44, 44)
	set_drag_preview(preview)
 
	return {"kind": kind, "key": key, "item": item}
 
 
func _can_drop_here(_at: Vector2, data: Variant, kind: String, key) -> bool:
	if typeof(data) != TYPE_DICTIONARY or not data.has("item"):
		return false
	if kind == "equipment":
		var gear := _gear()
		return gear != null and gear.can_equip(data["item"], key)
	return true
 
 
func _drop_here(_at: Vector2, data: Variant, kind: String, key) -> void:
	var pack := _backpack()
	var gear := _gear()
	if pack == null or gear == null:
		return
	var item: Item = data["item"]
 
	if kind == "equipment":
		if data["kind"] == "inventory":
			gear.equip_from(pack, item, key)
	else:
		if data["kind"] == "equipment":
			gear.unequip_to(pack, data["key"])
		else:
			pack.swap_items(data["key"], key)
 
	_refresh()
 
 
# ---------------------------------------------------------------- party bar
 
func _party() -> Array:
	var out: Array = [player]
	if Game.current_world != null:
		_collect_allies(Game.current_world, out)
	return out
 
 
func _collect_allies(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child.has_method("is_following") and child.is_following():
			out.append(child)
		_collect_allies(child, out)
 
 
func _rebuild_party() -> void:
	for child in _party_row.get_children():
		child.queue_free()
	_portraits.clear()
 
	var members: Array = _party()
	if not members.has(_selected):
		_selected = player
 
	for unit in members:
		if unit == null or not is_instance_valid(unit):
			continue
		var button := Button.new()
		button.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
		button.tooltip_text = unit.display_name if "display_name" in unit else "Unit"
		button.pressed.connect(_on_portrait_pressed.bind(unit))
		_party_row.add_child(button)
		_portraits[unit] = button
 
	_paint_portraits()
 
 
## Round buttons: a StyleBoxFlat whose corner radius is half its height.
func _paint_portraits() -> void:
	for unit in _portraits.keys():
		var fill: Color = COLOR_PLAYER if unit == player else COLOR_ALLY
 
		var normal := StyleBoxFlat.new()
		normal.bg_color = fill
		normal.set_corner_radius_all(int(PORTRAIT_SIZE / 2.0))
		if unit == _selected:
			normal.border_color = COLOR_SELECTED
			normal.set_border_width_all(3)
 
		_portraits[unit].add_theme_stylebox_override("normal", normal)
		_portraits[unit].add_theme_stylebox_override("hover", normal)
		_portraits[unit].add_theme_stylebox_override("pressed", normal)
 
 
func _on_portrait_pressed(unit) -> void:
	_selected = unit
	_refresh()
 
 
# --------------------------------------------------------------- defences
 
## Armor and the four elemental resistances, each with its mitigation percent.
func _rebuild_defences(unit) -> void:
	for child in _defence_row.get_children():
		child.queue_free()
 
	var armor: int = unit.armor() if unit.has_method("armor") else 0
	_defence_row.add_child(_defence_chip("Armor", armor, Color(0.80, 0.80, 0.84)))
 
	if not unit.has_method("resistances"):
		return
	var res: Resistances = unit.resistances()
	for element in DamageType.ELEMENTS:
		_defence_row.add_child(_defence_chip(
			DamageType.label(element), res.get_for(element), DamageType.color(element)
		))
 
 
func _defence_chip(label_text: String, value: int, tint: Color) -> Control:
	var cut: int = int(round((1.0 - Damage.multiplier(value)) * 100.0))
 
	var chip := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(tint.r, tint.g, tint.b, 0.14)
	box.set_corner_radius_all(4)
	box.set_content_margin_all(5)
	chip.add_theme_stylebox_override("panel", box)
	chip.tooltip_text = "%s %d — reduces %s damage by %d%%" % [
		label_text, value, label_text.to_lower(), cut
	]
 
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 5)
 
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(9, 9)
	swatch.color = tint
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(swatch)
 
	var text := Label.new()
	text.text = "%s %d  (-%d%%)" % [label_text, value, cut]
	text.add_theme_font_size_override("font_size", 11)
	line.add_child(text)
 
	chip.add_child(line)
	return chip
 
