extends Node

## Manages player joining, leaving, controller assignment, and player data.
## Supports up to 4 players with PS5 controllers or keyboard.

signal player_joined(player_index: int)
signal player_left(player_index: int)
signal all_players_dead
signal skill_leveled_up(player_index: int, skill: String, new_level: int)

enum CharacterClass { MELEE, RANGED, MAGE, SUMMONER, ROGUE, DEMOLITIONIST, HEALER, TANK, NINJA, BALLOONIST, GUITARIST, WEREWOLF }

const MAX_PLAYERS := 4
const MAX_SKILL_LEVEL := 20
const MAX_OVERALL_LEVEL := 50

const SKILL_BONUS_PER_LEVEL := {
	"attack": 0.02,
	"special": 0.02,
	"charge": 0.03,
	"block": 0.01,
}

const CLASS_STATS := {
	CharacterClass.MELEE: {
		"max_health": 175,
		"max_mana": 50,
		"speed": 110,
		"mana_regen": 1.0,
	},
	CharacterClass.RANGED: {
		"max_health": 100,
		"max_mana": 80,
		"speed": 120,
		"mana_regen": 1.5,
	},
	CharacterClass.MAGE: {
		"max_health": 80,
		"max_mana": 150,
		"speed": 90,
		"mana_regen": 3.0,
	},
	CharacterClass.SUMMONER: {
		"max_health": 90,
		"max_mana": 120,
		"speed": 95,
		"mana_regen": 2.0,
	},
	CharacterClass.ROGUE: {
		"max_health": 90,
		"max_mana": 60,
		"speed": 150,
		"mana_regen": 1.5,
	},
	CharacterClass.DEMOLITIONIST: {
		"max_health": 100,
		"max_mana": 100,
		"speed": 105,
		"mana_regen": 1.5,
	},
	CharacterClass.HEALER: {
		"max_health": 90,
		"max_mana": 130,
		"speed": 95,
		"mana_regen": 2.5,
	},
	CharacterClass.TANK: {
		"max_health": 250,
		"max_mana": 30,
		"speed": 70,
		"mana_regen": 0.5,
	},
	CharacterClass.NINJA: {
		"max_health": 75,
		"max_mana": 40,
		"speed": 170,
		"mana_regen": 1.0,
	},
	CharacterClass.BALLOONIST: {
		"max_health": 85,
		"max_mana": 80,
		"speed": 100,
		"mana_regen": 1.5,
	},
	CharacterClass.GUITARIST: {
		"max_health": 95,
		"max_mana": 70,
		"speed": 105,
		"mana_regen": 1.5,
	},
	CharacterClass.WEREWOLF: {
		"max_health": 140,
		"max_mana": 20,
		"speed": 135,
		"mana_regen": 0.5,
	},
}

## Active players keyed by player_index (0-3).
var players: Dictionary = {}

## Demolitionist bomb upgrade state (persists between scenes)
var demo_aspect: String = "none"
var demo_power_tier: int = 0
var demo_size_tier: int = 0
var demo_napalm: bool = false

## Set of device IDs that have already joined.
var _joined_devices: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _on_joy_connection_changed(device_id: int, connected: bool) -> void:
	if not connected:
		_handle_device_disconnect(device_id)


# -- Input Handling ------------------------------------------------------------

func _input(event: InputEvent) -> void:
	# Listen for the join action from any device - works in ANY scene
	if event.is_action_pressed("ps_button"):
		var device_id := _get_device_from_event(event)
		_try_join(device_id)


func _get_device_from_event(event: InputEvent) -> int:
	if event is InputEventKey:
		return -1  # Keyboard uses device -1
	return event.device


# -- Join / Leave Logic --------------------------------------------------------

func _try_join(device_id: int) -> void:
	if _joined_devices.has(device_id):
		return

	# Auto-create guest profile if no profile bound
	if not ProfileManager.has_device_profile(device_id):
		var last_profile: Dictionary = ProfileManager.get_last_profile_for_device(device_id)
		if not last_profile.is_empty():
			var pid: String = last_profile.get("id", "")
			var already_bound := false
			for did in ProfileManager.device_profiles:
				if ProfileManager.device_profiles[did].get("id", "") == pid:
					already_bound = true
					break
			if not already_bound:
				ProfileManager.bind_device_to_profile(device_id, last_profile)
		if not ProfileManager.has_device_profile(device_id):
			var guest: Dictionary = ProfileManager.create_profile("Player %d" % (players.size() + 1))
			ProfileManager.bind_device_to_profile(device_id, guest)
	if players.size() >= MAX_PLAYERS:
		return

	var player_index := _next_available_index()
	if player_index == -1:
		return

	var chosen_class := _pick_random_class()
	var stats: Dictionary = CLASS_STATS[chosen_class]

	var player_data := {
		"device_id": device_id,
		"player_index": player_index,
		"character_class": chosen_class,
		"health": stats["max_health"],
		"max_health": stats["max_health"],
		"mana": stats["max_mana"],
		"max_mana": stats["max_mana"],
		"speed": stats["speed"],
		"mana_regen": stats["mana_regen"],
		"muffin_count": 0,
		"artifacts": [],
		"is_alive": true,
		"skill_xp": {
			"attack": 0,
			"special": 0,
			"charge": 0,
			"block": 0,
		},
		"total_kills": 0,
		"session_kills": 0,
		"session_damage_dealt": 0,
	}

	players[player_index] = player_data
	_joined_devices[device_id] = player_index

	# Auto-assign the device's profile to this player
	var device_profile: Dictionary = ProfileManager.get_device_profile(device_id)
	if not device_profile.is_empty():
		ProfileManager.assign_profile_to_player(player_index, device_profile)

	_spawn_join_effect(player_index)
	player_joined.emit(player_index)


func remove_player(player_index: int) -> void:
	if not players.has(player_index):
		return
	var device_id: int = players[player_index]["device_id"]
	_joined_devices.erase(device_id)
	players.erase(player_index)
	player_left.emit(player_index)


func _handle_device_disconnect(device_id: int) -> void:
	if _joined_devices.has(device_id):
		var player_index: int = _joined_devices[device_id]
		remove_player(player_index)


func _next_available_index() -> int:
	for i in range(MAX_PLAYERS):
		if not players.has(i):
			return i
	return -1


# -- Class Assignment ----------------------------------------------------------

func _pick_random_class() -> CharacterClass:
	var all_classes: Array[CharacterClass] = [
		CharacterClass.MELEE,
		CharacterClass.RANGED,
		CharacterClass.MAGE,
		CharacterClass.SUMMONER,
		CharacterClass.ROGUE,
		CharacterClass.DEMOLITIONIST,
		CharacterClass.HEALER,
	]

	# Prefer classes not yet taken.
	var taken_classes: Array = []
	for p in players.values():
		taken_classes.append(p["character_class"])

	var available: Array[CharacterClass] = []
	for c in all_classes:
		if c not in taken_classes:
			available.append(c)

	if available.is_empty():
		available = all_classes

	return available[randi() % available.size()]


# -- Join Effect ---------------------------------------------------------------

func _spawn_join_effect(_player_index: int) -> void:
	# TODO: Instantiate a portal / particle effect at the player spawn position.
	pass


# -- Player Data Helpers -------------------------------------------------------

func get_player(player_index: int) -> Dictionary:
	if players.has(player_index):
		return players[player_index]
	return {}


func get_active_player_count() -> int:
	return players.size()


func get_alive_players() -> Array:
	var alive: Array = []
	for p in players.values():
		if p["is_alive"]:
			alive.append(p)
	return alive


func damage_player(player_index: int, amount: int) -> void:
	if not players.has(player_index):
		return
	players[player_index]["health"] = max(0, players[player_index]["health"] - amount)
	if players[player_index]["health"] <= 0:
		players[player_index]["is_alive"] = false
		# Check if ALL players are now dead
		if players.size() > 0 and get_alive_players().is_empty():
			all_players_dead.emit()


func heal_player(player_index: int, amount: int) -> void:
	if not players.has(player_index):
		return
	var p: Dictionary = players[player_index]
	p["health"] = min(p["max_health"], p["health"] + amount)


func use_mana(player_index: int, amount: int) -> bool:
	if not players.has(player_index):
		return false
	if players[player_index]["mana"] < amount:
		return false
	players[player_index]["mana"] -= amount
	return true


# -- Leveling System -----------------------------------------------------------

func xp_for_level(level: int) -> int:
	return 100 * level * (level + 1) / 2


func get_skill_level(xp: int) -> int:
	var level: int = 0
	while level < MAX_SKILL_LEVEL and xp >= xp_for_level(level + 1):
		level += 1
	return level


func add_skill_xp(player_index: int, skill: String, amount: int) -> void:
	if not players.has(player_index):
		return
	var p: Dictionary = players[player_index]
	if not p["skill_xp"].has(skill):
		return
	var old_level: int = get_skill_level(p["skill_xp"][skill])
	p["skill_xp"][skill] += amount
	var new_level: int = get_skill_level(p["skill_xp"][skill])
	if new_level > old_level:
		skill_leveled_up.emit(player_index, skill, new_level)
		apply_level_bonuses(player_index)


func get_skill_level_for(player_index: int, skill: String) -> int:
	if not players.has(player_index):
		return 0
	var p: Dictionary = players[player_index]
	if not p["skill_xp"].has(skill):
		return 0
	return get_skill_level(p["skill_xp"][skill])


func get_overall_level(player_index: int) -> int:
	if not players.has(player_index):
		return 0
	var p: Dictionary = players[player_index]
	var total: int = 0
	var count: int = 0
	for skill in p["skill_xp"]:
		total += get_skill_level(p["skill_xp"][skill])
		count += 1
	if count == 0:
		return 0
	var avg: int = total / count
	return mini(avg, MAX_OVERALL_LEVEL)


func get_skill_bonus(player_index: int, skill: String) -> float:
	var level: int = get_skill_level_for(player_index, skill)
	var bonus_per: float = SKILL_BONUS_PER_LEVEL.get(skill, 0.0)
	return 1.0 + level * bonus_per


func apply_level_bonuses(player_index: int) -> void:
	if not players.has(player_index):
		return
	var p: Dictionary = players[player_index]
	var overall: int = get_overall_level(player_index)
	var base_stats: Dictionary = CLASS_STATS[p["character_class"]]
	p["max_health"] = base_stats["max_health"] + overall * 5
	p["max_mana"] = base_stats["max_mana"] + overall * 3
	# Ensure current health/mana don't exceed new max but don't reduce them
	if p["health"] > p["max_health"]:
		p["health"] = p["max_health"]
	if p["mana"] > p["max_mana"]:
		p["mana"] = p["max_mana"]


func _process(delta: float) -> void:
	# Regenerate mana for classes that have mana_regen.
	for p in players.values():
		if p["mana_regen"] > 0.0 and p["is_alive"]:
			p["mana"] = min(p["max_mana"], p["mana"] + p["mana_regen"] * delta)


func reset_all_players() -> void:
	players.clear()
	_joined_devices.clear()
