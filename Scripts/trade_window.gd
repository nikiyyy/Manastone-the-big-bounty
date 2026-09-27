extends CanvasLayer
## Two inventory grids side by side. Double-click an item to buy or sell.
 
const COLUMNS := 4
const CELLS := 28
 
signal closed
 
var merchant = null
var player = null
 
var _root: Control
var _panel: PanelContainer
var _merchant_title: Label
var _player_title: Label
var _merchant_cells: Array = []
var _player_cells: Array = []
 
 
func _ready() -> void:
	layer = 40
	add_to_group("trade_window")
	_build()
	_root.hide()
	_panel.hide()
 
	
func open(merchant_npc, player_node) -> void:
	merchant = merchant_npc
	player = player_node
	merchant.merchant_inventory()
	_refresh()
	_root.show()
	_panel.show()
 
 
func close() -> void:
	merchant = null
	player = null
	_panel.hide()
	_root.hide()
	closed.emit()
 
 
func _unhandled_input(event: InputEvent) -> void:
	if not _panel.visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
 
 
# ------------------------------------------------------------------ layout
 
func _build() -> void:
	_root = CenterContainer.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
 
	_panel = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.08, 0.08, 0.10, 0.97)
	box.set_corner_radius_all(8)
	box.set_content_margin_all(18)
	box.border_color = Color(1, 1, 1, 0.18)
	box.set_border_width_all(1)
	_panel.add_theme_stylebox_override("panel", box)
	_root.add_child(_panel)
 
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	_panel.add_child(outer)
 
	var grids := HBoxContainer.new()
	grids.add_theme_constant_override("separation", 28)
	outer.add_child(grids)
 
	_merchant_title = Label.new()
	_player_title = Label.new()
	grids.add_child(_build_side(_merchant_title, _merchant_cells, true))
	grids.add_child(_build_side(_player_title, _player_cells, false))
 
	var hint := Label.new()
	hint.text = "Double-click an item to trade. Esc to close."
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(1, 1, 1, 0.5)
	outer.add_child(hint)
 
 
func _build_side(title: Label, cells: Array, from_merchant: bool) -> Control:
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
		button.custom_minimum_size = Vector2(60, 60)
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
 
		button.gui_input.connect(_on_cell_input.bind(i, from_merchant))
		grid.add_child(button)
		cells.append(button)
 
	return column
 
 
# -------------------------------------------------------------------- data
 
func _refresh() -> void:
	if merchant == null or player == null:
		return
 
	var m_name: String = merchant.display_name if "display_name" in merchant else "Merchant"
	_merchant_title.text = "%s — %d gold" % [m_name, merchant.merchant_gold]
	_player_title.text = "%s — %d gold" % [player.display_name, player.gold]
 
	_fill(_merchant_cells, merchant.inventory, true)
	_fill(_player_cells, player.inventory, false)
 
 
func _fill(cells: Array, inv: Inventory, from_merchant: bool) -> void:
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
 
		var price: int = merchant.sell_price(item) if from_merchant else merchant.buy_price(item)
		button.text = "%dg" % price
		button.tooltip_text = "%s\n%s for %d gold" % [
			item.tooltip(), "Buy" if from_merchant else "Sell", price
		]
		button.modulate = item.rarity_color()
 
 
func _on_cell_input(event: InputEvent, index: int, from_merchant: bool) -> void:
	if not (event is InputEventMouseButton and event.double_click):
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if from_merchant:
		_buy(index)
	else:
		_sell(index)
 
 
func _buy(index: int) -> void:
	var stock: Inventory = merchant.inventory
	if stock == null or index >= stock.items.size():
		return
	var item: Item = stock.items[index]
	var price: int = merchant.sell_price(item)
 
	if player.gold < price:
		print("Not enough gold — %d needed." % price)
		return
	if player.inventory.is_full():
		print("Your pack is full.")
		return
 
	player.add_gold(-price)
	merchant.merchant_gold += price
	stock.items.remove_at(index)
	player.inventory.items.append(item)
	print("Bought %s for %d." % [item.display_name, price])
	_refresh()
 
 
func _sell(index: int) -> void:
	var pack: Inventory = player.inventory
	if pack == null or index >= pack.items.size():
		return
	var item: Item = pack.items[index]
	var price: int = merchant.buy_price(item)
 
	if merchant.merchant_gold < price:
		print("%s can't afford that." % merchant.display_name)
		return
 
	merchant.merchant_gold -= price
	player.add_gold(price)
	pack.items.remove_at(index)
	merchant.inventory.items.append(item)
	print("Sold %s for %d." % [item.display_name, price])
	_refresh()
 
func is_open() -> bool:
	return _root.visible
