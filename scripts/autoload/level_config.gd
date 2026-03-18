extends Node

## Loads and saves JSON level configurations.
## Bundled defaults in res://levels/, user overrides in user://levels/.
## Falls back to bundled if override is corrupt or missing.

const BUNDLED_DIR := "res://levels/"
const OVERRIDE_DIR := "user://levels/"
const CURRENT_VERSION := 1

var _cache: Dictionary = {}  # level_name -> Dictionary


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func load_level(level_name: String) -> Dictionary:
	## Load level config. Tries override first, falls back to bundled.
	if _cache.has(level_name):
		return _cache[level_name]

	# Try user override first
	var override_path: String = OVERRIDE_DIR + level_name + ".json"
	var data: Dictionary = _load_json(override_path)
	if not data.is_empty() and _validate(data):
		_cache[level_name] = data
		return data

	if not data.is_empty():
		push_warning("LevelConfig: Override '%s' is invalid, using bundled default." % override_path)

	# Fall back to bundled
	var bundled_path: String = BUNDLED_DIR + level_name + ".json"
	data = _load_json(bundled_path)
	if not data.is_empty() and _validate(data):
		_cache[level_name] = data
		return data

	push_error("LevelConfig: Failed to load level '%s' from both override and bundled." % level_name)
	return {}


func save_level(level_name: String, data: Dictionary) -> void:
	## Save level config to user override directory.
	# Ensure directory exists
	DirAccess.make_dir_recursive_absolute(OVERRIDE_DIR.replace("user://", OS.get_user_data_dir() + "/"))

	var path: String = OVERRIDE_DIR + level_name + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("LevelConfig: Failed to open '%s' for writing." % path)
		return
	data["version"] = CURRENT_VERSION
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	_cache[level_name] = data


func reset_level(level_name: String) -> void:
	## Delete user override, reload from bundled.
	var override_path: String = OVERRIDE_DIR + level_name + ".json"
	if FileAccess.file_exists(override_path):
		DirAccess.remove_absolute(override_path)
	_cache.erase(level_name)


func get_level(level_name: String) -> Dictionary:
	## Return cached config or load if not cached.
	if _cache.has(level_name):
		return _cache[level_name]
	return load_level(level_name)


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var content: String = file.get_as_text()
	file.close()
	if content.is_empty():
		return {}
	var json := JSON.new()
	var err: Error = json.parse(content)
	if err != OK:
		push_warning("LevelConfig: JSON parse error in '%s': %s" % [path, json.get_error_message()])
		return {}
	var data: Variant = json.data
	if data is Dictionary:
		return data as Dictionary
	return {}


func _validate(data: Dictionary) -> bool:
	## Basic validation of level config structure.
	if not data.has("version"):
		return false
	if not data.has("level_name"):
		return false
	# Version check
	var ver: int = int(data.get("version", 0))
	if ver < 1 or ver > CURRENT_VERSION:
		return false
	return true
