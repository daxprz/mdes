extends Node2D

## Title screen with a playable lobby arena.
## Players can jump around, fight, and choose their class before starting.

const PLAYER_SIDE_SCENE := preload("res://scenes/characters/player_side.tscn")

const ALL_CLASSES: Array[PlayerManager.CharacterClass] = [
	PlayerManager.CharacterClass.MELEE,
	PlayerManager.CharacterClass.RANGED,
	PlayerManager.CharacterClass.MAGE,
	PlayerManager.CharacterClass.SUMMONER,
	PlayerManager.CharacterClass.ROGUE,
	PlayerManager.CharacterClass.DEMOLITIONIST,
	PlayerManager.CharacterClass.HEALER,
]

const CLASS_NAMES := {
	PlayerManager.CharacterClass.MELEE: "Melee",
	PlayerManager.CharacterClass.RANGED: "Ranged",
	PlayerManager.CharacterClass.MAGE: "Mage",
	PlayerManager.CharacterClass.SUMMONER: "Summoner",
	PlayerManager.CharacterClass.ROGUE: "Rogue",
	PlayerManager.CharacterClass.DEMOLITIONIST: "Demolitionist",
	PlayerManager.CharacterClass.HEALER: "Healer",
}

const CLASS_COLORS := {
	PlayerManager.CharacterClass.MELEE: Color(0.9, 0.3, 0.2),
	PlayerManager.CharacterClass.RANGED: Color(0.2, 0.8, 0.3),
	PlayerManager.CharacterClass.MAGE: Color(0.3, 0.4, 0.95),
	PlayerManager.CharacterClass.SUMMONER: Color(0.8, 0.5, 0.9),
	PlayerManager.CharacterClass.ROGUE: Color(0.95, 0.85, 0.2),
	PlayerManager.CharacterClass.DEMOLITIONIST: Color(0.9, 0.6, 0.1),
	PlayerManager.CharacterClass.HEALER: Color(0.3, 0.9, 0.4),
}

const EMPTY_SLOT_COLOR := Color(0.3, 0.3, 0.3, 1.0)

@onready var player_slots: HBoxContainer = $UI/PlayerSlots
@onready var start_text: Label = $UI/StartText
@onready var join_text: Label = $UI/JoinText
@onready var players_container: Node2D = $Players
@onready var spawn_point: Marker2D = $PlaygroundSpawn

var _blink_timer: float = 0.0
var _just_joined := false
var _spawned_players: Dictionary = {}  # player_index -> node
# Track which device triggered class cycle to avoid repeat
var _cycle_cooldowns: Dictionary = {}  # device_id -> float

# Profile / name entry
var _pending_device_id: int = -99  # Device waiting for profile creation
var _name_entry: Node = null


func _ready() -> void:
	PlayerManager.player_joined.connect(_on_player_joined)
	PlayerManager.player_left.connect(_on_player_left)
	ProfileManager.device_needs_profile.connect(_on_device_needs_profile)
	PlayerManager.reset_all_players()
	ProfileManager.unassign_all()
	_refresh_all_slots()
	_update_start_visibility()
	_setup_camera()
	_setup_name_entry()


func _setup_camera() -> void:
	var multi_cam_script := load("res://scripts/ui/multi_camera.gd")
	var cam := Camera2D.new()
	cam.set_script(multi_cam_script)
	cam.min_zoom = 0.8
	cam.max_zoom = 1.3
	cam.zoom_margin = Vector2(200, 150)
	cam.position = Vector2(640, 450)
	add_child(cam)


var _profile_select: Node = null

func _setup_name_entry() -> void:
	# Name entry overlay
	var name_script := load("res://scripts/ui/name_entry_overlay.gd")
	_name_entry = CanvasLayer.new()
	_name_entry.set_script(name_script)
	add_child(_name_entry)
	_name_entry.name_confirmed.connect(_on_name_confirmed)
	_name_entry.cancelled.connect(_on_name_cancelled)

	# Profile selection overlay
	var select_script := load("res://scripts/ui/profile_select_overlay.gd")
	_profile_select = CanvasLayer.new()
	_profile_select.set_script(select_script)
	add_child(_profile_select)
	_profile_select.profile_selected.connect(_on_profile_selected)
	_profile_select.create_new_requested.connect(_on_create_new_requested)


func _on_device_needs_profile(device_id: int) -> void:
	_pending_device_id = device_id
	# If profiles exist, let the player choose or create new
	if not ProfileManager.profiles.is_empty() and _profile_select and _profile_select.has_method("setup"):
		_profile_select.setup(-1, device_id)  # -1 since player isn't joined yet
	else:
		# No profiles exist - go straight to name entry
		if _name_entry and _name_entry.has_method("setup"):
			_name_entry.setup(device_id)


func _on_profile_selected(_player_index: int, profile: Dictionary) -> void:
	ProfileManager.bind_device_to_profile(_pending_device_id, profile)
	var dev_id: int = _pending_device_id
	_pending_device_id = -99
	call_deferred("_deferred_join", dev_id)


func _on_create_new_requested(_player_index: int) -> void:
	# Player wants to create a new profile - show name entry
	if _name_entry and _name_entry.has_method("setup"):
		_name_entry.setup(_pending_device_id)


func _on_name_confirmed(player_name: String) -> void:
	var profile: Dictionary = ProfileManager.create_profile(player_name)
	ProfileManager.bind_device_to_profile(_pending_device_id, profile)
	# Defer the join to next frame so overlays fully close first
	var dev_id: int = _pending_device_id
	_pending_device_id = -99
	call_deferred("_deferred_join", dev_id)


func _deferred_join(device_id: int) -> void:
	PlayerManager._try_join(device_id)


func _on_name_cancelled() -> void:
	var guest_name: String = "Guest"
	if _pending_device_id >= 0:
		guest_name = "Player %d" % (_pending_device_id + 1)
	var profile: Dictionary = ProfileManager.create_profile(guest_name)
	ProfileManager.bind_device_to_profile(_pending_device_id, profile)
	var dev_id: int = _pending_device_id
	_pending_device_id = -99
	call_deferred("_deferred_join", dev_id)


func _process(delta: float) -> void:
	if start_text.visible:
		_blink_timer += delta
		start_text.modulate.a = 0.5 + 0.5 * sin(_blink_timer * 4.0)
	join_text.modulate.a = 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.003)

	# Cooldown timers for class cycling
	for key in _cycle_cooldowns.keys():
		_cycle_cooldowns[key] -= delta
		if _cycle_cooldowns[key] <= 0.0:
			_cycle_cooldowns.erase(key)


func _input(event: InputEvent) -> void:
	# START to join or start game
	if event.is_action_pressed("ps_button"):
		if _just_joined:
			_just_joined = false
			return
		if PlayerManager.get_active_player_count() > 0:
			_start_game()

	# Class cycling with shoulder buttons (L1/R1) or interact/special
	# L1 = button 9, R1 = button 10 on PS5
	if event is InputEventJoypadButton and event.pressed:
		var device_id: int = event.device
		var player_index := _get_player_index_for_device(device_id)
		if player_index < 0:
			return

		var cooldown_key := "%d_%d" % [device_id, event.button_index]
		if _cycle_cooldowns.has(cooldown_key):
			return

		if event.button_index == 9:  # L1 - previous class
			_cycle_class(player_index, -1)
			_cycle_cooldowns[cooldown_key] = 0.2
		elif event.button_index == 10:  # R1 - next class
			_cycle_class(player_index, 1)
			_cycle_cooldowns[cooldown_key] = 0.2

	# Keyboard class cycling with Q/E for player on keyboard
	if event is InputEventKey and event.pressed:
		var player_index := _get_player_index_for_device(-1)
		if player_index < 0:
			return
		if event.keycode == KEY_Q:  # Q - previous
			_cycle_class(player_index, -1)
		elif event.keycode == KEY_E:  # E - next
			_cycle_class(player_index, 1)


# -- Class Cycling -------------------------------------------------------------

func _cycle_class(player_index: int, direction: int) -> void:
	var p_data: Dictionary = PlayerManager.get_player(player_index)
	if p_data.is_empty():
		return

	var current_class: PlayerManager.CharacterClass = p_data["character_class"]
	var available := _get_available_classes(player_index)
	if available.is_empty():
		return

	# Find current class in the full list and step
	var current_idx := ALL_CLASSES.find(current_class)
	var new_class := current_class

	# Step through ALL_CLASSES in direction, skipping taken ones
	for i in range(1, ALL_CLASSES.size() + 1):
		var check_idx := (current_idx + direction * i) % ALL_CLASSES.size()
		if check_idx < 0:
			check_idx += ALL_CLASSES.size()
		var candidate: PlayerManager.CharacterClass = ALL_CLASSES[check_idx]
		if candidate in available:
			new_class = candidate
			break

	if new_class == current_class:
		return

	AudioManager.play("menu_select")
	# Update player data
	p_data["character_class"] = new_class
	var stats: Dictionary = PlayerManager.CLASS_STATS[new_class]
	p_data["max_health"] = stats["max_health"]
	p_data["health"] = stats["max_health"]
	p_data["max_mana"] = stats["max_mana"]
	p_data["mana"] = stats["max_mana"]
	p_data["speed"] = stats["speed"]
	p_data["mana_regen"] = stats["mana_regen"]

	# Update UI slot
	_update_slot(player_index)

	# Respawn lobby player with new class
	_remove_lobby_player(player_index)
	_spawn_lobby_player(player_index)


func _get_available_classes(for_player_index: int) -> Array[PlayerManager.CharacterClass]:
	var taken: Array[PlayerManager.CharacterClass] = []
	for pi in PlayerManager.players:
		if pi != for_player_index:
			taken.append(PlayerManager.players[pi]["character_class"])

	var available: Array[PlayerManager.CharacterClass] = []
	for c in ALL_CLASSES:
		if c not in taken:
			available.append(c)
	return available


func _get_player_index_for_device(device_id: int) -> int:
	for pi in PlayerManager.players:
		if PlayerManager.players[pi]["device_id"] == device_id:
			return pi
	return -1




# -- Signal Callbacks ----------------------------------------------------------

func _on_player_joined(player_index: int) -> void:
	_just_joined = true
	_update_slot(player_index)
	_update_start_visibility()
	_spawn_lobby_player(player_index)


func _on_player_left(player_index: int) -> void:
	_clear_slot(player_index)
	_update_start_visibility()
	_remove_lobby_player(player_index)
	ProfileManager.unassign_profile(player_index)


# -- Lobby Player Spawning -----------------------------------------------------

func _spawn_lobby_player(player_index: int) -> void:
	var p_data: Dictionary = PlayerManager.get_player(player_index)
	if p_data.is_empty():
		return

	var player_node: CharacterBody2D = PLAYER_SIDE_SCENE.instantiate()
	player_node.player_index = player_index
	player_node.device_id = p_data["device_id"]
	player_node.character_class = p_data["character_class"]

	var offset := Vector2((player_index - 1.5) * 60, 0)
	player_node.global_position = spawn_point.global_position + offset

	players_container.add_child(player_node)
	_spawned_players[player_index] = player_node


func _remove_lobby_player(player_index: int) -> void:
	if _spawned_players.has(player_index):
		_spawned_players[player_index].queue_free()
		_spawned_players.erase(player_index)


# -- Slot Management -----------------------------------------------------------

func _get_slot(index: int) -> PanelContainer:
	return player_slots.get_child(index) as PanelContainer


func _update_slot(player_index: int) -> void:
	var slot := _get_slot(player_index)
	if slot == null:
		return
	var data: Dictionary = PlayerManager.get_player(player_index)
	if data.is_empty():
		_clear_slot(player_index)
		return
	var char_class: PlayerManager.CharacterClass = data["character_class"]
	var vbox: VBoxContainer = slot.get_node("VBox")
	var class_icon: ColorRect = vbox.get_node("ClassIcon")
	var class_label: Label = vbox.get_node("ClassLabel")
	class_icon.color = CLASS_COLORS.get(char_class, EMPTY_SLOT_COLOR)

	# Show profile name + level if available
	var profile: Dictionary = ProfileManager.get_active_profile(player_index)
	var class_name_text: String = CLASS_NAMES.get(char_class, "???")
	if not profile.is_empty():
		var pname: String = profile.get("name", "")
		var class_key: String = str(int(char_class))
		var level: int = ProfileManager.get_overall_level(profile, class_key)
		if level > 0:
			class_label.text = pname + " - " + class_name_text + " Lv." + str(level)
		else:
			class_label.text = pname + " - " + class_name_text
	else:
		class_label.text = class_name_text

	# Update arrows hint
	var arrows: Label = vbox.get_node_or_null("Arrows")
	if not arrows:
		arrows = Label.new()
		arrows.name = "Arrows"
		arrows.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		arrows.add_theme_font_size_override("font_size", 10)
		arrows.modulate = Color(0.7, 0.7, 0.7)
		vbox.add_child(arrows)
	arrows.text = "< L1 / R1 >"


func _clear_slot(player_index: int) -> void:
	var slot := _get_slot(player_index)
	if slot == null:
		return
	var vbox: VBoxContainer = slot.get_node("VBox")
	var class_icon: ColorRect = vbox.get_node("ClassIcon")
	var class_label: Label = vbox.get_node("ClassLabel")
	class_icon.color = EMPTY_SLOT_COLOR
	class_label.text = "---"
	var arrows: Label = vbox.get_node_or_null("Arrows")
	if arrows:
		arrows.text = ""


func _refresh_all_slots() -> void:
	for i in range(PlayerManager.MAX_PLAYERS):
		if PlayerManager.players.has(i):
			_update_slot(i)
		else:
			_clear_slot(i)


func _update_start_visibility() -> void:
	start_text.visible = PlayerManager.get_active_player_count() > 0


# -- Transition ----------------------------------------------------------------

func _start_game() -> void:
	set_process_input(false)
	GameManager.go_to_overworld()
