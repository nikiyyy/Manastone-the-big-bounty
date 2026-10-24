extends CanvasLayer
## In-game wiki. J opens it, Escape closes. Entries link to each other with
## [url=entry_id]text[/url] in their body text; the reader colours those and
## turns them into clicks.
##
## Undiscovered targets render as plain grey text rather than dead links, so
## the colour of a word never tells you a page exists before you've found it.

const LINK_COLOR := "#7fb4ff"
const DEAD_COLOR := "#8f8f8f"

@export var book: CodexBook

var _root: Control
var _search: LineEdit
var _index_list: VBoxContainer
var _page: RichTextLabel
var _back_button: Button
var _breadcrumb: Label

var _current: StringName = ""
var _history: Array = []
var _link_re := RegEx.new()


func _ready() -> void:
	layer = 58
	add_to_group("codex_ui")
	_link_re.compile("\\[url=([^\\]]+)\\]([\\s\\S]*?)\\[/url\\]")
	_build()
	_root.hide()


func is_open() -> bool:
	return _root.visible


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	if event.keycode == KEY_J:
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


func open(entry_id: StringName = &"") -> void:
	_root.show()
	_history.clear()
	_rebuild_index()
	if not entry_id.is_empty():
		_show_entry(entry_id)
	elif _current.is_empty():
		_show_welcome()
	else:
		_show_entry(_current)


func close() -> void:
	_root.hide()


func _player():
	return Game.player

# ------------------------------------------------------------------- index

func _rebuild_index() -> void:
	for child in _index_list.get_children():
		child.queue_free()

	if book == null:
		var missing := Label.new()
		missing.text = "No codex assigned."
		missing.add_theme_font_size_override("font_size", 12)
		missing.modulate = Color(1, 1, 1, 0.5)
		_index_list.add_child(missing)
		return

	var query: String = _search.text.strip_edges()
	var groups: Dictionary = book.by_category(_player(), query)

	if groups.is_empty():
		var empty := Label.new()
		empty.text = "Nothing found." if not query.is_empty() else "Nothing discovered yet."
		empty.add_theme_font_size_override("font_size", 12)
		empty.modulate = Color(1, 1, 1, 0.45)
		_index_list.add_child(empty)
		return

	var categories: Array = groups.keys()
	categories.sort()

	for category in categories:
		var header := Label.new()
		header.text = category
		header.add_theme_font_size_override("font_size", 12)
		header.modulate = Color(1, 0.85, 0.5)
		_index_list.add_child(header)

		for entry in groups[category]:
			_index_list.add_child(_index_row(entry))

		_index_list.add_child(HSeparator.new())


func _index_row(entry: CodexEntry) -> Button:
	var unread: bool = not entry.has_been_read()
	var updated: bool = entry.has_unread_secret(_player())

	var button := Button.new()
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 12)
	button.custom_minimum_size = Vector2(0, 26)
	button.text = entry.title
	if unread:
		button.text = "• " + entry.title
	elif updated:
		button.text = "+ " + entry.title

	if entry.id == _current:
		button.modulate = Color(1, 0.9, 0.6)
	elif unread or updated:
		button.modulate = Color(0.75, 0.9, 1.0)
	else:
		button.modulate = Color(1, 1, 1, 0.75)

	button.tooltip_text = entry.summary
	button.pressed.connect(_on_index_pressed.bind(entry.id))
	return button


func _on_index_pressed(id: StringName) -> void:
	if not _current.is_empty() and _current != id:
		_history.append(_current)
	_show_entry(id)

# -------------------------------------------------------------------- page

func _show_welcome() -> void:
	_current = &""
	_breadcrumb.text = "Codex"
	_back_button.disabled = true
	_page.text = "[i]Pick a topic from the list.[/i]\n\nThings you learn out in the world are added here. Some entries grow once you know more."


func _show_entry(id: StringName) -> void:
	if book == null:
		return
	var entry: CodexEntry = book.entry(id)
	if entry == null or not entry.is_discovered(_player()):
		_show_welcome()
		return

	_current = id
	_breadcrumb.text = "%s  ·  %s" % [entry.category, entry.title]
	_back_button.disabled = _history.is_empty()

	var parts: Array = []
	parts.append("[font_size=20][color=#%s]%s[/color][/font_size]" % [
		entry.tint.to_html(false), entry.title
	])
	if not entry.summary.is_empty():
		parts.append("[i][color=%s]%s[/color][/i]" % [DEAD_COLOR, entry.summary])
	parts.append("")

	for section in entry.visible_sections(_player()):
		if not section.heading.is_empty():
			var marker: String = "  [color=#ffd36b](new)[/color]" if _is_new_secret(entry, section) else ""
			parts.append("[font_size=15][b]%s[/b][/font_size]%s" % [section.heading, marker])
		parts.append(_linkify(section.text))
		parts.append("")

	var links: Array = _related_links(entry)
	if not links.is_empty():
		parts.append("[color=%s]———[/color]" % DEAD_COLOR)
		parts.append("[b]See also:[/b]  " + "   ".join(links))

	_page.text = "\n".join(parts)
	_page.scroll_to_line(0)

	# marked read after rendering, so the "new" markers show this once
	Story.mark_read(id)
	entry.acknowledge_secrets(_player())
	_rebuild_index()


func _is_new_secret(entry: CodexEntry, section: CodexSection) -> bool:
	if not section.is_secret:
		return false
	return not Story.get_flag(StringName("codex_secret:%s:%s" % [entry.id, section.heading]))


func _related_links(entry: CodexEntry) -> Array:
	var out: Array = []
	for link in entry.related:
		var other: CodexEntry = book.entry(link)
		if other != null and other.is_discovered(_player()):
			out.append("[color=%s][url=%s]%s[/url][/color]" % [LINK_COLOR, link, other.title])
	return out


## Turn [url=id]text[/url] into a coloured link, or plain grey text when the
## target doesn't exist or hasn't been discovered.
func _linkify(text: String) -> String:
	var out: String = ""
	var cursor: int = 0

	for m in _link_re.search_all(text):
		out += text.substr(cursor, m.get_start() - cursor)
		var target := StringName(m.get_string(1))
		var label: String = m.get_string(2)
		var other: CodexEntry = book.entry(target) if book != null else null

		if other != null and other.is_discovered(_player()):
			out += "[color=%s][url=%s]%s[/url][/color]" % [LINK_COLOR, target, label]
		else:
			out += "[color=%s]%s[/color]" % [DEAD_COLOR, label]
		cursor = m.get_end()

	out += text.substr(cursor)
	return out


func _on_link_clicked(meta) -> void:
	_on_index_pressed(StringName(str(meta)))


func _on_back_pressed() -> void:
	if _history.is_empty():
		return
	_show_entry(_history.pop_back())

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
	box.set_content_margin_all(18)
	box.border_color = Color(1, 1, 1, 0.18)
	box.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", box)
	center.add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	outer.custom_minimum_size = Vector2(880, 540)
	panel.add_child(outer)

	outer.add_child(_build_header())

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(columns)

	columns.add_child(_build_index_column())
	columns.add_child(_build_page_column())

	var hint := Label.new()
	hint.text = "J or Esc to close"
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(1, 1, 1, 0.45)
	outer.add_child(hint)


func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var title := Label.new()
	title.text = "Codex"
	title.add_theme_font_size_override("font_size", 22)
	title.modulate = Color(1, 0.85, 0.4)
	row.add_child(title)

	_search = LineEdit.new()
	_search.placeholder_text = "Search"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t): _rebuild_index())
	row.add_child(_search)

	return row


func _build_index_column() -> Control:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(250, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	_index_list = VBoxContainer.new()
	_index_list.add_theme_constant_override("separation", 3)
	_index_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_index_list)

	return scroll


func _build_page_column() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	column.add_child(bar)

	_back_button = Button.new()
	_back_button.text = "< Back"
	_back_button.custom_minimum_size = Vector2(80, 26)
	_back_button.add_theme_font_size_override("font_size", 11)
	_back_button.disabled = true
	_back_button.pressed.connect(_on_back_pressed)
	bar.add_child(_back_button)

	_breadcrumb = Label.new()
	_breadcrumb.add_theme_font_size_override("font_size", 11)
	_breadcrumb.modulate = Color(1, 1, 1, 0.55)
	bar.add_child(_breadcrumb)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_page = RichTextLabel.new()
	_page.bbcode_enabled = true
	_page.fit_content = true
	_page.selection_enabled = true
	_page.meta_underlined = true
	_page.add_theme_font_size_override("normal_font_size", 13)
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.custom_minimum_size = Vector2(560, 0)
	_page.meta_clicked.connect(_on_link_clicked)
	scroll.add_child(_page)

	return column
