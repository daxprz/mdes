class_name CompositionLoader extends RefCounted

## Loads a Composition from a JSON definition file.
##
## JSON format:
## {
##   "id": "title_screen",
##   "default_movement": "light",
##   "movements": [
##     {"id": "light", "file": "intro_light", "bars": -1},
##     {"id": "dark",  "file": "intro_dark",  "bars": -1}
##   ],
##   "bridges": [
##     {"id": "bridge_to_dark",  "file": "intro_bridge_to_dark",  "bars": 1, "from": "light", "to": "dark"},
##     {"id": "bridge_to_light", "file": "intro_bridge_to_light", "bars": 1, "from": "dark",  "to": "light"}
##   ],
##   "turnarounds": []
## }


static func load_from_json(json_path: String) -> MusicComposition:
	## Load a composition from a JSON file.  Returns null on failure.
	var resolved: String = _resolve_json_path(json_path)
	if resolved.is_empty():
		push_error("CompositionLoader: file not found: %s" % json_path)
		return null

	var file := FileAccess.open(resolved, FileAccess.READ)
	if not file:
		push_error("CompositionLoader: cannot read: %s" % resolved)
		return null

	var json := JSON.new()
	var err: Error = json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("CompositionLoader: JSON parse error in %s: %s" % [resolved, json.get_error_message()])
		return null

	return load_from_dict(json.data)


static func load_from_dict(data: Dictionary) -> MusicComposition:
	## Build a Composition from a parsed JSON dictionary.
	var comp := MusicComposition.new()
	comp.id = data.get("id", "")
	comp.default_movement_id = data.get("default_movement", "")

	# Load movements
	for m_data in data.get("movements", []):
		var movement := _load_movement(m_data)
		if movement:
			comp.movements[movement.id] = movement

	# Load bridges
	for b_data in data.get("bridges", []):
		var bridge := _load_bridge(b_data)
		if bridge:
			comp.bridges[bridge.id] = bridge

	# Load turnarounds
	for t_data in data.get("turnarounds", []):
		var ta := _load_turnaround(t_data)
		if ta:
			comp.turnarounds[ta.id] = ta

	# Validate default movement exists
	if not comp.default_movement_id.is_empty() and not comp.movements.has(comp.default_movement_id):
		push_warning("CompositionLoader: default_movement '%s' not found" % comp.default_movement_id)

	return comp


static func _load_movement(data: Dictionary) -> MusicMovement:
	var m := MusicMovement.new()
	m.id = data.get("id", "")
	m.bars = int(data.get("bars", -1))
	m.strudel_file = data.get("file", "")

	if m.strudel_file.is_empty():
		push_error("CompositionLoader: movement '%s' has no file" % m.id)
		return null

	var compiled: Dictionary = StrudelLineCompiler.compile_strudel_file(m.strudel_file)
	if not compiled["error"].is_empty():
		push_error("CompositionLoader: movement '%s': %s" % [m.id, compiled["error"]])
		return null

	m.cps = compiled["cps"]
	# CPS override from JSON
	if data.has("cps"):
		m.cps = float(data["cps"])

	# Convert compiled track dicts into MusicTrack objects
	for track_data in compiled["tracks"]:
		m.tracks.append(MusicTrack.from_compiled(track_data))

	return m


static func _load_bridge(data: Dictionary) -> MusicBridge:
	var b := MusicBridge.new()
	b.id = data.get("id", "")
	b.bars = int(data.get("bars", 1))
	b.from_movement_id = data.get("from", "")
	b.to_movement_id = data.get("to", "")
	b.strudel_file = data.get("file", "")

	if b.strudel_file.is_empty():
		push_error("CompositionLoader: bridge '%s' has no file" % b.id)
		return null

	var compiled: Dictionary = StrudelLineCompiler.compile_strudel_file(b.strudel_file)
	if not compiled["error"].is_empty():
		push_error("CompositionLoader: bridge '%s': %s" % [b.id, compiled["error"]])
		return null

	b.cps = compiled["cps"]
	if data.has("cps"):
		b.cps = float(data["cps"])

	for track_data in compiled["tracks"]:
		b.tracks.append(MusicTrack.from_compiled(track_data))

	return b


static func _load_turnaround(data: Dictionary) -> MusicTurnaround:
	var ta := MusicTurnaround.new()
	ta.id = data.get("id", "")
	ta.bars = int(data.get("bars", 1))
	ta.target_bridge_id = data.get("target_bridge", "")

	var file_path: String = data.get("file", "")
	if file_path.is_empty():
		return ta  # Turnaround with no file = uses movement tracks (future)

	var compiled: Dictionary = StrudelLineCompiler.compile_strudel_file(file_path)
	if not compiled["error"].is_empty():
		push_error("CompositionLoader: turnaround '%s': %s" % [ta.id, compiled["error"]])
		return null

	for track_data in compiled["tracks"]:
		ta.tracks.append(MusicTrack.from_compiled(track_data))

	return ta


static func _resolve_json_path(path_or_name: String) -> String:
	## Resolve a composition JSON path.
	if path_or_name.begins_with("res://") or path_or_name.begins_with("user://") or path_or_name.begins_with("/"):
		if FileAccess.file_exists(path_or_name):
			return path_or_name
		if FileAccess.file_exists(path_or_name + ".json"):
			return path_or_name + ".json"
		return ""
	# Short name — search compositions directory
	for ext in ["", ".json"]:
		var candidate: String = "res://data/compositions/" + path_or_name + ext
		if FileAccess.file_exists(candidate):
			return candidate
	return ""
