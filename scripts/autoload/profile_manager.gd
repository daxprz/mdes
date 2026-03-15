extends Node

## Persistent profile system - saves player progress between sessions.
## Profiles track per-class skill XP, lifetime stats, and class preferences.

const SAVE_PATH := "user://profiles.json"
const BINDINGS_PATH := "user://controller_bindings.json"
const MAX_PROFILES := 8

signal profile_loaded(profile_id: String)
signal profile_saved
signal device_needs_profile(device_id: int)  # Emitted when a new controller needs a profile

var profiles: Array[Dictionary] = []
var active_profiles: Dictionary = {}  # player_index -> profile dict
var device_profiles: Dictionary = {}  # device_id -> profile dict (current session)
var _controller_bindings: Dictionary = {}  # controller_name -> profile_id (persists to disk)


# -- XP / Leveling Constants --------------------------------------------------

## Formula: xp_for_level = 100 * level * (level + 1) / 2
const MAX_SKILL_LEVEL := 20


func xp_for_level(level: int) -> int:
	if level <= 0:
		return 0
	return 100 * level * (level + 1) / 2


func get_skill_level(xp: int) -> int:
	var level: int = 0
	for lv in range(1, MAX_SKILL_LEVEL + 1):
		if xp >= xp_for_level(lv):
			level = lv
		else:
			break
	return level


func get_overall_level(profile: Dictionary, class_key: String) -> int:
	var class_data: Dictionary = profile.get("per_class", {}).get(class_key, {})
	var skill_xp: Dictionary = class_data.get("skill_xp", {})
	var attack_lv: int = get_skill_level(skill_xp.get("attack", 0))
	var special_lv: int = get_skill_level(skill_xp.get("special", 0))
	var charge_lv: int = get_skill_level(skill_xp.get("charge", 0))
	var block_lv: int = get_skill_level(skill_xp.get("block", 0))
	var avg: float = (attack_lv + special_lv + charge_lv + block_lv) / 4.0
	return int(avg)


# -- Lifecycle -----------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_profiles()
	_load_bindings()


# -- Save / Load ---------------------------------------------------------------

func save_profiles() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("ProfileManager: Failed to open save file for writing: " + SAVE_PATH)
		return
	var data: Dictionary = {"profiles": profiles}
	var json_string: String = JSON.stringify(data, "\t")
	file.store_string(json_string)
	file.close()
	profile_saved.emit()


func load_profiles() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		profiles = []
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("ProfileManager: Could not open save file, starting fresh.")
		profiles = []
		return

	var content: String = file.get_as_text()
	file.close()

	if content.is_empty():
		profiles = []
		return

	var json := JSON.new()
	var err: Error = json.parse(content)
	if err != OK:
		push_warning("ProfileManager: Corrupt save file, starting fresh. Error: " + json.get_error_message())
		profiles = []
		return

	var data: Variant = json.data
	if data is Dictionary and data.has("profiles") and data["profiles"] is Array:
		profiles = []
		for entry: Variant in data["profiles"]:
			if entry is Dictionary:
				profiles.append(entry as Dictionary)
	else:
		push_warning("ProfileManager: Unexpected save format, starting fresh.")
		profiles = []


# -- Profile CRUD --------------------------------------------------------------

func _generate_id() -> String:
	return str(randi()) + str(Time.get_ticks_msec())


func _get_date_string() -> String:
	var dt: Dictionary = Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [dt["year"], dt["month"], dt["day"]]


func _make_empty_class_data() -> Dictionary:
	return {
		"skill_xp": {"attack": 0, "special": 0, "charge": 0, "block": 0},
		"total_kills": 0,
		"total_muffins": 0,
		"boss_kills": 0,
		"playtime": 0,
	}


func create_profile(profile_name: String, class_prefs: Array = [], sub_names: Dictionary = {}) -> Dictionary:
	if profiles.size() >= MAX_PROFILES:
		push_warning("ProfileManager: Max profiles reached.")
		return {}

	# Build default class preferences if none provided
	if class_prefs.is_empty():
		class_prefs = [0, 1, 2, 3, 4, 5, 6]

	# Build per-class data for all 7 classes
	var per_class: Dictionary = {}
	for i in range(7):
		per_class[str(i)] = _make_empty_class_data()

	var profile: Dictionary = {
		"id": _generate_id(),
		"name": profile_name,
		"created": _get_date_string(),
		"last_played": _get_date_string(),
		"class_preferences": class_prefs,
		"sub_names": sub_names,
		"per_class": per_class,
		"lifetime": {
			"total_playtime": 0,
			"total_muffins": 0,
			"total_kills": 0,
			"bosses_defeated": 0,
			"towers_completed": 0,
		},
	}

	profiles.append(profile)
	save_profiles()
	return profile


func delete_profile(profile_id: String) -> void:
	for i in range(profiles.size()):
		if profiles[i].get("id", "") == profile_id:
			profiles.remove_at(i)
			# Remove from active assignments
			var keys_to_erase: Array = []
			for pi: Variant in active_profiles:
				if active_profiles[pi].get("id", "") == profile_id:
					keys_to_erase.append(pi)
			for key: Variant in keys_to_erase:
				active_profiles.erase(key)
			save_profiles()
			return


func get_profile(profile_id: String) -> Dictionary:
	for p: Dictionary in profiles:
		if p.get("id", "") == profile_id:
			return p
	return {}


# -- Active Profile Assignment -------------------------------------------------

func assign_profile_to_player(player_index: int, profile: Dictionary) -> void:
	if profile.is_empty():
		return
	active_profiles[player_index] = profile
	profile["last_played"] = _get_date_string()
	profile_loaded.emit(profile.get("id", ""))


func get_active_profile(player_index: int) -> Dictionary:
	if active_profiles.has(player_index):
		return active_profiles[player_index]
	return {}


func unassign_profile(player_index: int) -> void:
	active_profiles.erase(player_index)


func unassign_all() -> void:
	active_profiles.clear()


# -- Device-Profile Binding ----------------------------------------------------

func bind_device_to_profile(device_id: int, profile: Dictionary) -> void:
	device_profiles[device_id] = profile
	# Persist: save controller name → profile ID
	var controller_name: String = _get_controller_name(device_id)
	var pid: String = profile.get("id", "")
	if not controller_name.is_empty() and not pid.is_empty():
		_controller_bindings[controller_name] = pid
		_save_bindings()


func get_device_profile(device_id: int) -> Dictionary:
	if device_profiles.has(device_id):
		return device_profiles[device_id]
	return {}


func has_device_profile(device_id: int) -> bool:
	return device_profiles.has(device_id)


func get_last_profile_for_device(device_id: int) -> Dictionary:
	## Returns the profile this controller used last session (from disk).
	## Used to highlight/suggest in the selection list, NOT to auto-bind.
	var controller_name: String = _get_controller_name(device_id)
	if _controller_bindings.has(controller_name):
		var pid: String = _controller_bindings[controller_name]
		return get_profile(pid)
	return {}


func unbind_device(device_id: int) -> void:
	device_profiles.erase(device_id)


func request_profile_for_device(device_id: int) -> void:
	device_needs_profile.emit(device_id)


func _get_controller_name(device_id: int) -> String:
	if device_id == -1:
		return "keyboard"
	var joy_name: String = Input.get_joy_name(device_id)
	if joy_name.is_empty():
		return "controller_%d" % device_id
	# Include device index to differentiate multiple identical controllers
	return joy_name + "_%d" % device_id


# -- Persistent Bindings (controller → profile) --------------------------------

func _save_bindings() -> void:
	var file := FileAccess.open(BINDINGS_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_controller_bindings, "\t"))
	file.close()


func _load_bindings() -> void:
	if not FileAccess.file_exists(BINDINGS_PATH):
		_controller_bindings = {}
		return
	var file := FileAccess.open(BINDINGS_PATH, FileAccess.READ)
	if file == null:
		_controller_bindings = {}
		return
	var content: String = file.get_as_text()
	file.close()
	if content.is_empty():
		_controller_bindings = {}
		return
	var json := JSON.new()
	var err: Error = json.parse(content)
	if err != OK:
		_controller_bindings = {}
		return
	var data: Variant = json.data
	if data is Dictionary:
		_controller_bindings = data as Dictionary
	else:
		_controller_bindings = {}


# -- Session Sync --------------------------------------------------------------

func sync_session_to_profile(player_index: int) -> void:
	var profile: Dictionary = get_active_profile(player_index)
	if profile.is_empty():
		return

	var p_data: Dictionary = PlayerManager.get_player(player_index)
	if p_data.is_empty():
		return

	var class_enum: int = p_data.get("character_class", 0) as int
	var class_key: String = str(class_enum)

	# Ensure per_class entry exists
	if not profile.has("per_class"):
		profile["per_class"] = {}
	if not profile["per_class"].has(class_key):
		profile["per_class"][class_key] = _make_empty_class_data()

	var class_data: Dictionary = profile["per_class"][class_key]

	# Sync muffin count from player data
	var session_muffins: int = p_data.get("muffin_count", 0)
	class_data["total_muffins"] = class_data.get("total_muffins", 0) + session_muffins

	# Sync from GameManager mini-muffin counts
	var gm_muffins: int = GameManager.get_mini_muffin_count(player_index)
	if gm_muffins > 0:
		class_data["total_muffins"] = class_data.get("total_muffins", 0) + gm_muffins

	# Sync lifetime stats
	if not profile.has("lifetime"):
		profile["lifetime"] = {"total_playtime": 0, "total_muffins": 0, "total_kills": 0, "bosses_defeated": 0, "towers_completed": 0}
	profile["lifetime"]["total_muffins"] = profile["lifetime"].get("total_muffins", 0) + session_muffins + gm_muffins

	profile["last_played"] = _get_date_string()


func auto_save() -> void:
	for pi: Variant in active_profiles:
		if pi is int:
			sync_session_to_profile(pi as int)
	save_profiles()


# -- Skill XP Helpers ----------------------------------------------------------

func add_skill_xp(player_index: int, skill_name: String, amount: int) -> void:
	var profile: Dictionary = get_active_profile(player_index)
	if profile.is_empty():
		return

	var p_data: Dictionary = PlayerManager.get_player(player_index)
	if p_data.is_empty():
		return

	var class_key: String = str(int(p_data.get("character_class", 0)))
	if not profile.has("per_class"):
		profile["per_class"] = {}
	if not profile["per_class"].has(class_key):
		profile["per_class"][class_key] = _make_empty_class_data()

	var class_data: Dictionary = profile["per_class"][class_key]
	if not class_data.has("skill_xp"):
		class_data["skill_xp"] = {"attack": 0, "special": 0, "charge": 0, "block": 0}

	var current: int = class_data["skill_xp"].get(skill_name, 0)
	class_data["skill_xp"][skill_name] = current + amount


func add_kill(player_index: int) -> void:
	var profile: Dictionary = get_active_profile(player_index)
	if profile.is_empty():
		return

	var p_data: Dictionary = PlayerManager.get_player(player_index)
	if p_data.is_empty():
		return

	var class_key: String = str(int(p_data.get("character_class", 0)))
	if profile.has("per_class") and profile["per_class"].has(class_key):
		profile["per_class"][class_key]["total_kills"] = profile["per_class"][class_key].get("total_kills", 0) + 1
	if profile.has("lifetime"):
		profile["lifetime"]["total_kills"] = profile["lifetime"].get("total_kills", 0) + 1


func add_boss_kill(player_index: int) -> void:
	var profile: Dictionary = get_active_profile(player_index)
	if profile.is_empty():
		return

	var p_data: Dictionary = PlayerManager.get_player(player_index)
	if p_data.is_empty():
		return

	var class_key: String = str(int(p_data.get("character_class", 0)))
	if profile.has("per_class") and profile["per_class"].has(class_key):
		profile["per_class"][class_key]["boss_kills"] = profile["per_class"][class_key].get("boss_kills", 0) + 1
	if profile.has("lifetime"):
		profile["lifetime"]["bosses_defeated"] = profile["lifetime"].get("bosses_defeated", 0) + 1


func add_tower_complete(player_index: int) -> void:
	var profile: Dictionary = get_active_profile(player_index)
	if profile.is_empty():
		return
	if profile.has("lifetime"):
		profile["lifetime"]["towers_completed"] = profile["lifetime"].get("towers_completed", 0) + 1
