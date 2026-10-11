class_name SaveGame
extends RefCounted
## Reads and writes save files. Nothing here knows what's inside a save —
## Game builds the dictionary, this just gets it onto disk and back.
##
## Files live in user://saves/, Godot's writable per-user folder. On Windows
## that's %APPDATA%\Godot\app_userdata\<project>\saves\. The project folder
## itself is read-only once the game is exported, so it can't be used.

const SAVE_DIR := "user://saves/"
const EXTENSION := ".save"
const MAX_NAME := 40


static func ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)


## Turn whatever the player typed into something safe for a filename.
static func sanitize(raw: String) -> String:
	var clean: String = raw.strip_edges().substr(0, MAX_NAME)
	clean = clean.validate_filename()
	return clean if not clean.is_empty() else "save"


static func path_for(slot_name: String) -> String:
	return SAVE_DIR + sanitize(slot_name) + EXTENSION


static func exists(slot_name: String) -> bool:
	return FileAccess.file_exists(path_for(slot_name))


## full_objects is on because saves contain Resources (Stats, Inventory, Item).
## That makes a save file capable of naming a script, so only ever load files
## the player made themselves.
static func write(slot_name: String, data: Dictionary) -> bool:
	ensure_dir()
	var path: String = path_for(slot_name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SaveGame: could not write %s (error %d)" % [path, FileAccess.get_open_error()])
		return false

	var payload: Dictionary = data.duplicate()
	payload["slot_name"] = slot_name
	file.store_var(payload, true)
	file.close()
	return true


static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("SaveGame: could not read %s" % path)
		return {}
	var data = file.get_var(true)
	file.close()
	return data if typeof(data) == TYPE_DICTIONARY else {}


static func erase(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(path) == OK


## Every save on disk, newest first. Each entry is
## { path, name, saved_at, summary }.
static func list_saves() -> Array:
	ensure_dir()
	var out: Array = []

	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return out

	for file_name in dir.get_files():
		if not file_name.ends_with(EXTENSION):
			continue
		var path: String = SAVE_DIR + file_name
		var data: Dictionary = read(path)
		if data.is_empty():
			continue
		out.append({
			"path": path,
			"name": data.get("slot_name", file_name.get_basename()),
			"saved_at": data.get("saved_at", ""),
			"summary": data.get("summary", ""),
		})

	out.sort_custom(func(a, b): return a["saved_at"] > b["saved_at"])
	return out
