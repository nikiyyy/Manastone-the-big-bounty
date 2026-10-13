extends CanvasLayer
## Right-click and hold on a unit to see its full stat block.
 
const OFFSET := Vector2(18, 18)
 
var _panel: PanelContainer
var _title: Label
var _grid: GridContainer
var _gear_list: VBoxContainer
var _effect_list: VBoxContainer
var _unit = null
 
 
func _ready() -> void:
	layer = 50
	add_to_group("unit_inspector")
	Game.battle_ended.connect(hide_card)
	Game.world_loaded.connect(func(_w): hide_card())
	_build()
	_panel.hide()
 
 
func show_for(unit) -> void:
	if unit == null or not is_instance_valid(unit):
		hide_card()
		return
	_unit = unit
	_populate()
	_panel.show()
	_panel.reset_size()
	await get_tree().process_frame
	_panel.reset_size()
	_follow_mouse()
 
 
func hide_card() -> void:
	_unit = null
	_panel.hide()
 
 
func _process(_delta: float) -> void:
	if _panel.visible:
		_follow_mouse()
 
 
## Flip the card to the other side of the cursor when it would run off-screen.
func _follow_mouse() -> void:
	var mouse: Vector2 = _panel.get_viewport().get_mouse_position()
	var screen: Vector2 = _panel.get_viewport_rect().size
	var size: Vector2 = _panel.size
 
	var pos: Vector2 = mouse + OFFSET
	if pos.x + size.x > screen.x:
		pos.x = mouse.x - size.x - OFFSET.x
	if pos.y + size.y > screen.y:
		pos.y = mouse.y - size.y - OFFSET.y
	_panel.position = pos
 
 
# ------------------------------------------------------------------- layout
 
func _build() -> void:
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_panel.custom_minimum_size = Vector2.ZERO
 
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.07, 0.07, 0.09, 0.95)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(12)
	box.border_color = Color(1, 1, 1, 0.2)
	box.set_border_width_all(1)
	_panel.add_theme_stylebox_override("panel", box)
	add_child(_panel)
 
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_panel.add_child(column)
 
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 15)
	column.add_child(_title)
	column.add_child(HSeparator.new())
 
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 3)
	column.add_child(_grid)
 
	_gear_list = VBoxContainer.new()
	_gear_list.add_theme_constant_override("separation", 2)
	column.add_child(_gear_list)
 
	_effect_list = VBoxContainer.new()
	_effect_list.add_theme_constant_override("separation", 4)
	column.add_child(_effect_list)
 
# --------------------------------------------------------------------- data
 
func _populate() -> void:
	for child in _grid.get_children():
		child.queue_free()
 
	var name: String = _unit.display_name if "display_name" in _unit else "Unit"
	var level: int = _unit.level if "level" in _unit else 1
	var hp: int = _unit.current_health if "current_health" in _unit else 0
	var hp_max: int = _unit.max_health() if _unit.has_method("max_health") else 0
	var armor: int = _unit.armor() if _unit.has_method("armor") else 0
	var mana: int = _unit.current_mana if "current_mana" in _unit else 0
	var mana_max: int = _unit.max_mana() if _unit.has_method("max_mana") else 0
	var klass: String = _unit.class_name_of() if _unit.has_method("class_name_of") else ""
 
	_title.text = "%s   %s   lvl %d" % [name, klass, level]
	_add_pair("Mana", "%d / %d" % [mana, mana_max])
	_add_pair("Health", "%d / %d" % [hp, hp_max])
 
	var cut: int = int(round((1.0 - Damage.multiplier(armor)) * 100.0))
	_add_pair("Armor", "%d  (-%d%%)" % [armor, cut])
 
	var weapon: Item = null
	if "inventory" in _unit and _unit.inventory != null:
		weapon = _unit.inventory.get_equipped(Item.Slot.MAIN_HAND)
	_add_pair("Weapon", weapon.display_name if weapon != null else "Unarmed")
 
	var damage: String = "—"
	if weapon != null and weapon.is_weapon():
		damage = "%d–%d %s" % [
			weapon.damage_min, weapon.damage_max,
			DamageType.label(weapon.damage_type).to_lower()
		]
	_add_pair("Damage", damage)
 
	var reach: String = "1 (melee)"
	if weapon != null and weapon.is_weapon():
		reach = "%d (%s)" % [weapon.reach, "ranged" if weapon.is_ranged() else "melee"]
	_add_pair("Reach", reach)
 
	_add_pair("Crit", "%d%%" % Damage.crit_chance(_unit, weapon))
 
	if _unit.has_method("resistances"):
		var res: Resistances = _unit.resistances()
		for element in DamageType.ELEMENTS:
			var value: int = res.get_for(element)
			var reduction: int = int(round((1.0 - Damage.multiplier(value)) * 100.0))
			_add_pair("%s resist" % DamageType.label(element), "%d  (-%d%%)" % [value, reduction])
 
	var stats: Stats = _unit.stats if "stats" in _unit else null
	if stats != null:
		for stat_name in Stats.NAMES:
			if stat_name == "health":
				continue
			var base: int = stats.get(stat_name)
			var now: int = _unit.modified_stat(stat_name) if _unit.has_method("modified_stat") else base
			_add_pair(Stats.LABELS[stat_name], str(now) if now == base else "%d (%d)" % [now, base])
 
	_build_gear_rows()
	_build_effect_rows()
 
 
func _add_pair(label: String, value: String) -> void:
	var name_label := Label.new()
	name_label.text = label
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.modulate = Color(1, 1, 1, 0.6)
	name_label.custom_minimum_size = Vector2(90, 0)
	_grid.add_child(name_label)
 
	var value_label := Label.new()
	value_label.text = value
	value_label.add_theme_font_size_override("font_size", 12)
	value_label.custom_minimum_size = Vector2(55, 0)
	_grid.add_child(value_label)
 
 
## Everything this unit is wearing, slot by slot. Empty slots are skipped.
func _build_gear_rows() -> void:
	for child in _gear_list.get_children():
		child.queue_free()
 
	if not "inventory" in _unit or _unit.inventory == null:
		return
	var inv: Inventory = _unit.inventory
 
	var worn: Array = []
	for slot in Inventory.SLOT_ORDER:
		var item: Item = inv.get_equipped(slot)
		if item != null:
			worn.append({"slot": slot, "item": item})
 
	if worn.is_empty():
		return
 
	_gear_list.add_child(HSeparator.new())
 
	var heading := Label.new()
	heading.text = "Equipped"
	heading.add_theme_font_size_override("font_size", 12)
	heading.modulate = Color(1, 0.85, 0.5)
	_gear_list.add_child(heading)
 
	for entry in worn:
		var item: Item = entry["item"]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
 
		var slot_label := Label.new()
		slot_label.text = Inventory.SLOT_LABELS[entry["slot"]]
		slot_label.add_theme_font_size_override("font_size", 11)
		slot_label.modulate = Color(1, 1, 1, 0.55)
		slot_label.custom_minimum_size = Vector2(90, 0)
		line.add_child(slot_label)
 
		var name_label := Label.new()
		name_label.text = item.display_name
		name_label.add_theme_font_size_override("font_size", 11)
		name_label.modulate = item.rarity_color()
		line.add_child(name_label)
 
		_gear_list.add_child(line)
 
 
## One row per active effect: colour swatch, description, turns remaining.
func _build_effect_rows() -> void:
	for child in _effect_list.get_children():
		child.queue_free()
 
	if not "effects" in _unit or _unit.effects == null:
		return
	var entries: Array = _unit.effects.entries()
	if entries.is_empty():
		return
 
	_effect_list.add_child(HSeparator.new())
 
	for entry in entries:
		var effect: Effect = entry["effect"]
 
		var row := PanelContainer.new()
		var box := StyleBoxFlat.new()
		box.bg_color = Color(1, 1, 1, 0.05)
		box.set_corner_radius_all(4)
		box.set_content_margin_all(6)
		row.add_theme_stylebox_override("panel", box)
 
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
 
		var icon := ColorRect.new()
		icon.custom_minimum_size = Vector2(22, 22)
		icon.color = effect.color
		line.add_child(icon)
 
		var text := Label.new()
		text.text = effect.display_name if effect.description.is_empty() else "%s — %s" % [
			effect.display_name, effect.description
		]
		text.add_theme_font_size_override("font_size", 12)
		text.custom_minimum_size = Vector2(200, 0)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
 
		var turns := Label.new()
		turns.text = str(entry["turns_left"])
		turns.add_theme_font_size_override("font_size", 13)
		turns.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		turns.custom_minimum_size = Vector2(28, 0)
		turns.modulate = Color(1, 0.9, 0.6)
		line.add_child(turns)
 
		row.add_child(line)
		_effect_list.add_child(row)
 
