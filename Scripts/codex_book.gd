class_name CodexBook
extends Resource
## The collection of codex entries. Either list them explicitly, or point
## `folder` at a directory and every .tres inside is picked up — which is
## what you want once there are fifty of them and maintaining an array by
## hand stops being reasonable.

@export var entries: Array[CodexEntry] = []
## Scanned on first use and merged with `entries`. Leave empty to skip.
@export_dir var folder: String = ""

var _all: Array = []
var _index: Dictionary = {}      # StringName -> CodexEntry
var _loaded: bool = false


func all() -> Array:
	_load()
	return _all


func entry(id: StringName) -> CodexEntry:
	_load()
	return _index.get(id)


## Force a rescan — useful from a tool script while authoring.
func reload() -> void:
	_loaded = false
	_load()


func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_all.clear()
	_index.clear()

	for e in entries:
		_register(e)

	if not folder.is_empty():
		for e in _scan(folder):
			_register(e)

	_all.sort_custom(func(a, b): return a.title.naturalnocasecmp_to(b.title) < 0)


func _register(e: CodexEntry) -> void:
	if e == null or e.id.is_empty() or _index.has(e.id):
		return
	_index[e.id] = e
	_all.append(e)


func _scan(path: String) -> Array:
	var found: Array = []
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("CodexBook: can't open %s" % path)
		return found

	for file_name in dir.get_files():
		# exported projects rename .tres to .remap
		var clean: String = file_name.trim_suffix(".remap")
		if not clean.ends_with(".tres") and not clean.ends_with(".res"):
			continue
		var res = load(path.path_join(clean))
		if res is CodexEntry:
			found.append(res)

	return found

# ------------------------------------------------------------------ queries

## Discovered entries only, optionally filtered by a search string.
func available(player, query: String = "") -> Array:
	var out: Array = []
	for e in all():
		if e.is_discovered(player) and e.matches(query):
			out.append(e)
	return out


## Discovered entries grouped by category, as { category: Array[CodexEntry] }.
func by_category(player, query: String = "") -> Dictionary:
	var groups: Dictionary = {}
	for e in available(player, query):
		if not groups.has(e.category):
			groups[e.category] = []
		groups[e.category].append(e)
	return groups


## Problems with the book, as readable lines. Empty means it's sound.
func validate(player) -> Array:
	_load()
	var problems: Array = []
	var seen: Dictionary = {}

	for e in _all:
		if e.id.is_empty():
			problems.append("An entry has no id (title: %s)." % e.title)
			continue
		if seen.has(e.id):
			problems.append("Duplicate entry id '%s'." % e.id)
		seen[e.id] = true

		for link in e.related:
			if not _index.has(link):
				problems.append("'%s' links to missing entry '%s'." % [e.id, link])

	return problems
