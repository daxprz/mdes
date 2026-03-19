extends Node2D

## Title screen with a playable lobby arena.
## Players auto-join when a controller is connected.
## Profile/class selection is handled inline via the PlayerHUD autoload.
## Class changes trigger a red portal + ghost + poof sequence.

const PLAYER_SIDE_SCENE := preload("res://scenes/characters/player_side.tscn")

@onready var title_label: Label = $UI/Title
@onready var join_text: Label = $UI/JoinText
@onready var players_container: Node2D = $Players
@onready var spawn_point: Marker2D = $PlaygroundSpawn

const RIFT_TENTACLE_SCENE := preload("res://scripts/effects/rift_tentacle.gd")

var _blink_timer: float = 0.0
var _spawned_players: Dictionary = {}  # player_index -> node
var _ghost_players: Dictionary = {}  # player_index -> true (waiting for non-movement input)
var _rift_locks: Dictionary = {}  # player_index -> float (seconds remaining on rift lock)
var _name_entry: Node = null
var _pending_device_id: int = -99
var _returning_from_game: bool = false
var _scenery_items: Array = []  # Procedurally generated background items
var _current_config: Dictionary = {}
var _config_spawn_positions: Array[Vector2] = []
var _editor: Node = null
var _dynamic_nodes: Array = []  # All nodes created from config (for teardown)
var _portal_node: Node2D = null
var _firefly_manager: Node2D = null
var _bat_spawn_timer: float = 0.0
var _bat_max: int = 5
var _bat_bounds: Rect2 = Rect2(100, 350, 1720, 500)
var _migration_patterns: Array = []  # MigrationPattern nodes


func _ready() -> void:
	PlayerManager.player_joined.connect(_on_player_joined)
	PlayerManager.player_left.connect(_on_player_left)
	PlayerHUD.class_changed.connect(_on_class_changed)
	PlayerHUD.create_profile_requested.connect(_on_create_profile_requested)

	# Check if returning from quit-to-menu with saved choices
	var saved_choices: Dictionary = {}
	if PlayerManager.has_meta("saved_choices"):
		saved_choices = PlayerManager.get_meta("saved_choices")
		PlayerManager.remove_meta("saved_choices")
	PlayerManager.reset_all_players()
	ProfileManager.unassign_all()
	ProfileManager.device_profiles.clear()

	# Load level config from JSON (with fallback to bundled default)
	var config: Dictionary = LevelConfig.load_level("title_screen")
	_current_config = config

	_setup_camera_from_config(config.get("camera", {}))
	_setup_name_entry()
	_setup_version_label()
	_setup_migration_patterns_from_config(config.get("migration_patterns", []))
	_setup_background_trees_from_config(config.get("scenery", {}).get("trees", []))
	_setup_rocks_from_config(config.get("scenery", {}).get("rocks", []))
	_setup_fireflies_from_config(config.get("spawn_zones", {}).get("fireflies", []))
	_setup_bats_from_config(config.get("spawn_zones", {}).get("bats", []))
	_setup_portal_from_config(config.get("portal", {}))
	_setup_spawn_positions_from_config(config.get("spawn_positions", []))
	_setup_cave_walls_from_config(config.get("cave_walls", {}))

	# Restore saved player choices or auto-join connected controllers
	_returning_from_game = not saved_choices.is_empty()
	if _returning_from_game:
		_restore_saved_choices(saved_choices)
	else:
		_auto_join_connected_controllers()


func _restore_saved_choices(saved_choices: Dictionary) -> void:
	for pi in saved_choices.keys():
		var choice: Dictionary = saved_choices[pi]
		var dev_id: int = choice.get("device_id", -1)
		var char_class: int = choice.get("character_class", 0)
		var last_profile: Dictionary = ProfileManager.get_last_profile_for_device(dev_id)
		if not last_profile.is_empty():
			ProfileManager.bind_device_to_profile(dev_id, last_profile)
		else:
			var guest: Dictionary = ProfileManager.create_profile("Player %d" % (pi + 1))
			ProfileManager.bind_device_to_profile(dev_id, guest)
		PlayerManager._try_join(dev_id)
	call_deferred("_apply_saved_classes", saved_choices)


func _apply_saved_classes(saved_choices: Dictionary) -> void:
	for pi in saved_choices.keys():
		var choice: Dictionary = saved_choices[pi]
		var dev_id: int = choice.get("device_id", -1)
		var char_class: int = choice.get("character_class", 0)
		for p_idx in PlayerManager.players.keys():
			var p_data: Dictionary = PlayerManager.players[p_idx]
			if p_data.get("device_id", -99) == dev_id:
				p_data["character_class"] = char_class
				var stats: Dictionary = PlayerManager.CLASS_STATS.get(char_class, {})
				if not stats.is_empty():
					p_data["max_health"] = stats["max_health"]
					p_data["health"] = stats["max_health"]
					p_data["max_mana"] = stats["max_mana"]
					p_data["mana"] = stats["max_mana"]
					p_data["speed"] = stats["speed"]
					p_data["mana_regen"] = stats["mana_regen"]
				_remove_lobby_player(p_idx)
				_spawn_lobby_player(p_idx)
				break


func _auto_join_connected_controllers() -> void:
	## Auto-join only connected joypads (not keyboard)
	for dev_id in Input.get_connected_joypads():
		_auto_join_device(dev_id)
	# Listen for controllers connecting/disconnecting
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _auto_join_device(device_id: int) -> void:
	## Auto-assign a profile (or create guest) and join
	if not ProfileManager.has_device_profile(device_id):
		var last_profile: Dictionary = ProfileManager.get_last_profile_for_device(device_id)
		if not last_profile.is_empty():
			# Check it's not already bound to another device
			var pid: String = last_profile.get("id", "")
			var already_bound := false
			for did in ProfileManager.device_profiles:
				if ProfileManager.device_profiles[did].get("id", "") == pid:
					already_bound = true
					break
			if not already_bound:
				ProfileManager.bind_device_to_profile(device_id, last_profile)
		# If still no profile, create a guest
		if not ProfileManager.has_device_profile(device_id):
			var guest_name := "Player %d" % (PlayerManager.players.size() + 1)
			var guest: Dictionary = ProfileManager.create_profile(guest_name)
			ProfileManager.bind_device_to_profile(device_id, guest)
	PlayerManager._try_join(device_id)


func _setup_camera_from_config(cam_config: Dictionary) -> void:
	var cam := Camera2D.new()
	var pos_arr: Array = cam_config.get("position", [960, 495])
	cam.position = Vector2(pos_arr[0], pos_arr[1])
	add_child(cam)


func _setup_name_entry() -> void:
	var name_script := load("res://scripts/ui/name_entry_overlay.gd")
	_name_entry = CanvasLayer.new()
	_name_entry.set_script(name_script)
	add_child(_name_entry)
	_name_entry.name_confirmed.connect(_on_name_confirmed)
	_name_entry.cancelled.connect(_on_name_cancelled)


func _setup_version_label() -> void:
	var ver_label := Label.new()
	ver_label.text = "v" + Version.get_string()
	ver_label.add_theme_font_size_override("font_size", 12)
	ver_label.modulate = Color(0.5, 0.5, 0.5, 0.6)
	ver_label.anchor_left = 1.0
	ver_label.anchor_right = 1.0
	ver_label.anchor_top = 0.0
	ver_label.offset_left = -80
	ver_label.offset_right = -10
	ver_label.offset_top = 10
	ver_label.offset_bottom = 30
	ver_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	$UI.add_child(ver_label)


func _setup_migration_patterns_from_config(pattern_configs: Array) -> void:
	var pattern_script := load("res://scripts/systems/migration_pattern.gd")
	for cfg in pattern_configs:
		var pattern := Node.new()
		pattern.set_script(pattern_script)
		pattern.setup_from_config(cfg)
		add_child(pattern)
		_migration_patterns.append(pattern)
		_dynamic_nodes.append(pattern)


func _setup_background_trees_from_config(tree_configs: Array) -> void:
	var tree_script := load("res://scripts/effects/procedural_tree.gd")
	for cfg in tree_configs:
		var tree := Node2D.new()
		tree.set_script(tree_script)
		tree.trunk_weight = cfg.get("trunk_weight", 20.0)
		tree.trunk_length = cfg.get("trunk_length", 200.0)
		tree.seed_value = int(cfg.get("seed", randi()))
		tree.z_index = -5
		add_child(tree)
		var pos_arr: Array = cfg.get("pos", [960, 900])
		tree.global_position = Vector2(pos_arr[0], pos_arr[1])
		_scenery_items.append(tree)
		_dynamic_nodes.append(tree)


func _setup_rocks_from_config(rock_configs: Array) -> void:
	var rock_script := load("res://scripts/effects/procedural_rock.gd")
	for cfg in rock_configs:
		var rock := Node2D.new()
		rock.set_script(rock_script)
		rock.rock_size = cfg.get("size", 40.0)
		rock.seed_value = int(cfg.get("seed", randi()))
		rock.hue = cfg.get("hue", "grey")
		rock.z_index = -3
		add_child(rock)
		var pos_arr: Array = cfg.get("pos", [960, 900])
		rock.global_position = Vector2(pos_arr[0], pos_arr[1])
		_scenery_items.append(rock)
		_dynamic_nodes.append(rock)


func _setup_fireflies_from_config(ff_zone_configs: Array) -> void:
	var ff_script := load("res://scripts/effects/fireflies.gd")
	_firefly_manager = Node2D.new()
	_firefly_manager.set_script(ff_script)

	var zones: Array[Rect2] = []
	var weights: Array[float] = []
	for cfg in ff_zone_configs:
		var r: Array = cfg.get("rect", [0, 0, 100, 100])
		zones.append(Rect2(r[0], r[1], r[2], r[3]))
		weights.append(cfg.get("weight", 1.0))

	_firefly_manager.setup_zones(zones, weights)
	for pattern in _migration_patterns:
		if pattern.has_species("fireflies"):
			_firefly_manager.add_migration_pattern(pattern)
	add_child(_firefly_manager)
	_dynamic_nodes.append(_firefly_manager)


func _setup_bats_from_config(bat_zone_configs: Array) -> void:
	if bat_zone_configs.is_empty():
		return
	var cfg: Dictionary = bat_zone_configs[0]
	var r: Array = cfg.get("rect", [100, 350, 1720, 500])
	_bat_bounds = Rect2(r[0], r[1], r[2], r[3])
	_bat_max = int(cfg.get("max_count", 5))
	for _i in range(_bat_max):
		_spawn_bat()


func _spawn_bat() -> void:
	var bat_count: int = get_tree().get_nodes_in_group("enemies").size()
	if bat_count >= _bat_max:
		return
	var bat_script := load("res://scripts/enemies/title_bat.gd")
	var bat := CharacterBody2D.new()
	bat.set_script(bat_script)
	bat.global_position = Vector2(960 + randf_range(-30, 30), 780 + randf_range(-20, 0))
	var bat_patterns: Array = []
	for pattern in _migration_patterns:
		if pattern.has_species("bats"):
			bat_patterns.append(pattern)
	bat.setup(_firefly_manager, _bat_bounds, bat_patterns)
	players_container.add_child(bat)


func _setup_portal_from_config(portal_config: Dictionary) -> void:
	var doorway_script := load("res://scripts/ui/portal_doorway.gd")
	var doorway := Node2D.new()
	doorway.set_script(doorway_script)
	var pos_arr: Array = portal_config.get("pos", [960, 880])
	doorway.global_position = Vector2(pos_arr[0], pos_arr[1])
	doorway.z_index = -1
	add_child(doorway)
	doorway.all_players_entered.connect(_start_game)
	_portal_node = doorway
	_dynamic_nodes.append(doorway)


func _setup_spawn_positions_from_config(positions: Array) -> void:
	if not positions.is_empty():
		var new_spawns: Array[Vector2] = []
		for p in positions:
			new_spawns.append(Vector2(p[0], p[1]))
		_config_spawn_positions = new_spawns


func _setup_cave_walls_from_config(cave_config: Dictionary) -> void:
	if cave_config.is_empty():
		return
	var cave_script := load("res://scripts/effects/cave_wall.gd")
	var floor_y: float = cave_config.get("floor_y", 900.0)
	var ceil_y: float = cave_config.get("ceiling_y", 0.0)
	var curve_w: float = cave_config.get("curve_width", 180.0)
	var ledge_ratio: float = cave_config.get("ledge_height_ratio", 0.33)
	var ledge_depth: float = cave_config.get("ledge_depth", 40.0)

	for side in ["left", "right"]:
		var wall := StaticBody2D.new()
		wall.set_script(cave_script)
		wall.side = side
		wall.room_height = floor_y
		wall.room_top = ceil_y
		wall.curve_width = curve_w
		wall.ledge_height_ratio = ledge_ratio
		wall.ledge_depth = ledge_depth
		wall.global_position = Vector2(0 if side == "left" else 1920, 0)
		wall.z_index = -2
		add_child(wall)
		_dynamic_nodes.append(wall)


# -- Process -------------------------------------------------------------------

func _process(delta: float) -> void:
	_blink_timer += delta

	# Blink join text
	join_text.modulate.a = 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.003)

	# Respawn bats from the doorway cracks
	_bat_spawn_timer += delta
	if _bat_spawn_timer >= 5.0:
		_bat_spawn_timer = 0.0
		if randf() > 0.5:
			_spawn_bat()

	# Count down rift locks
	for pi in _rift_locks.keys():
		_rift_locks[pi] -= delta
		if _rift_locks[pi] <= 0.0:
			_rift_locks.erase(pi)
			if not PlayerHUD.tentacle_lost.has(pi):
				PlayerHUD.class_change_locked.erase(pi)
				PlayerHUD.active_tentacle_count = maxi(0, PlayerHUD.active_tentacle_count - 1)

	# Check ghost players for non-movement button press to materialize
	for pi in _ghost_players.keys():
		var p_data: Dictionary = PlayerManager.get_player(pi)
		if p_data.is_empty():
			_ghost_players.erase(pi)
			continue
		if _check_non_movement_press(p_data["device_id"]):
			_materialize_player(pi)


func _check_non_movement_press(device_id: int) -> bool:
	## Check if any non-movement button is pressed for this device
	if device_id == -1:
		# Keyboard
		return Input.is_action_just_pressed("attack") or \
			   Input.is_action_just_pressed("special") or \
			   Input.is_action_just_pressed("jump") or \
			   Input.is_action_just_pressed("block") or \
			   Input.is_action_just_pressed("interact")
	else:
		# Joypad - check standard action buttons (not D-pad, not START)
		return Input.is_joy_button_pressed(device_id, JOY_BUTTON_A) or \
			   Input.is_joy_button_pressed(device_id, JOY_BUTTON_B) or \
			   Input.is_joy_button_pressed(device_id, JOY_BUTTON_X) or \
			   Input.is_joy_button_pressed(device_id, JOY_BUTTON_Y) or \
			   Input.is_joy_button_pressed(device_id, JOY_BUTTON_RIGHT_SHOULDER) or \
			   Input.is_joy_button_pressed(device_id, JOY_BUTTON_LEFT_SHOULDER)


# -- Input ---------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	# Ctrl+E toggles level editor
	if event is InputEventKey and event.pressed and event.keycode == KEY_E and event.ctrl_pressed:
		_toggle_editor()
		get_viewport().set_input_as_handled()
		return

	# Debug: G key regenerates nearest scenery item to P1
	if event is InputEventKey and event.pressed and event.keycode == KEY_G:
		if PlayerHUD._debug_mode:
			_debug_regenerate_nearest_scenery()

	# Debug: M key spawns a quadruped monster
	if event is InputEventKey and event.pressed and event.keycode == KEY_M:
		if PlayerHUD._debug_mode:
			_debug_spawn_monster()


func _toggle_editor() -> void:
	if _editor == null:
		var editor_script := load("res://scripts/ui/level_editor.gd")
		_editor = CanvasLayer.new()
		_editor.set_script(editor_script)
		_editor.setup("title_screen", _current_config)
		_editor.config_changed.connect(_rebuild_from_config)
		add_child(_editor)
	else:
		_editor.toggle()


func _rebuild_from_config(new_config: Dictionary) -> void:
	## Tear down all dynamic objects and rebuild from new config
	_current_config = new_config

	# Remove all dynamic nodes
	for node in _dynamic_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_dynamic_nodes.clear()
	_scenery_items.clear()
	_firefly_manager = null
	_portal_node = null
	_migration_patterns.clear()

	# Kill any bats
	for node in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(node):
			node.queue_free()

	# Defer rebuild to next frame so queue_free completes
	call_deferred("_deferred_rebuild")


func _deferred_rebuild() -> void:
	var config: Dictionary = _current_config
	_setup_migration_patterns_from_config(config.get("migration_patterns", []))
	_setup_background_trees_from_config(config.get("scenery", {}).get("trees", []))
	_setup_rocks_from_config(config.get("scenery", {}).get("rocks", []))
	_setup_fireflies_from_config(config.get("spawn_zones", {}).get("fireflies", []))
	_setup_bats_from_config(config.get("spawn_zones", {}).get("bats", []))
	_setup_portal_from_config(config.get("portal", {}))
	_setup_spawn_positions_from_config(config.get("spawn_positions", []))
	_setup_cave_walls_from_config(config.get("cave_walls", {}))


func _debug_regenerate_nearest_scenery() -> void:
	# Find P1's position
	var p1_pos := Vector2(960, 500)  # Default if no player
	for node in get_tree().get_nodes_in_group("players"):
		if node is CharacterBody2D and node.get("player_index") == 0:
			p1_pos = node.global_position
			break

	# Find closest scenery item
	var best_item: Node2D = null
	var best_dist: float = INF
	for item in _scenery_items:
		if not is_instance_valid(item):
			continue
		var dist: float = p1_pos.distance_to(item.global_position)
		if dist < best_dist:
			best_dist = dist
			best_item = item

	if best_item and best_item.has_method("regenerate"):
		var new_seed: int = randi()
		best_item.regenerate(new_seed)
		print("Regenerated scenery with seed: ", new_seed)


func _debug_spawn_monster() -> void:
	var monster_script := load("res://scripts/enemies/quadruped_monster.gd")
	var monster := CharacterBody2D.new()
	monster.set_script(monster_script)
	monster.global_position = Vector2(960, 750)
	players_container.add_child(monster)
	print("Spawned quadruped monster at (960, 750)")


# -- Profile Creation ----------------------------------------------------------

func _on_create_profile_requested(device_id: int) -> void:
	_pending_device_id = device_id
	if _name_entry and _name_entry.has_method("setup"):
		_name_entry.setup(device_id)


func _on_name_confirmed(player_name: String) -> void:
	var profile: Dictionary = ProfileManager.create_profile(player_name)
	ProfileManager.bind_device_to_profile(_pending_device_id, profile)
	var pi := _get_player_index_for_device(_pending_device_id)
	if pi >= 0:
		ProfileManager.assign_profile_to_player(pi, profile)
	_pending_device_id = -99


func _on_name_cancelled() -> void:
	_pending_device_id = -99


# -- Controller Connect/Disconnect --------------------------------------------

func _on_joy_connection_changed(device_id: int, connected: bool) -> void:
	if connected:
		_auto_join_device(device_id)
	else:
		# Remove the player associated with this device
		var pi := _get_player_index_for_device(device_id)
		if pi >= 0:
			_remove_lobby_player(pi)
			_ghost_players.erase(pi)
			PlayerManager.remove_player(pi)
			ProfileManager.unbind_device(device_id)


# -- Class Change with Portal/Ghost/Poof Sequence -----------------------------

func _on_class_changed(player_index: int, new_class: PlayerManager.CharacterClass) -> void:
	# Block class changes while rift is active for this player
	if _rift_locks.has(player_index):
		return
	if not _spawned_players.has(player_index):
		_spawn_lobby_player(player_index)
		return

	var old_node: CharacterBody2D = _spawned_players[player_index]
	var pos: Vector2 = old_node.global_position

	# Spawn red portal at player position
	_spawn_red_portal(pos)

	# Make player ghost (semi-transparent)
	old_node.queue_free()
	_spawned_players.erase(player_index)

	# Spawn smoke poof
	_spawn_poof(pos)

	# Spawn new character at same position
	var p_data: Dictionary = PlayerManager.get_player(player_index)
	if p_data.is_empty():
		return

	var player_node: CharacterBody2D = PLAYER_SIDE_SCENE.instantiate()
	player_node.player_index = player_index
	player_node.device_id = p_data["device_id"]
	player_node.character_class = new_class
	player_node.global_position = pos
	player_node.modulate = Color(1, 1, 1, 0.4)  # Ghost
	players_container.add_child(player_node)
	_spawned_players[player_index] = player_node

	# Mark as ghost
	_ghost_players[player_index] = true


func _materialize_player(player_index: int) -> void:
	_ghost_players.erase(player_index)
	if not _spawned_players.has(player_index):
		return

	var node: CharacterBody2D = _spawned_players[player_index]
	var pos: Vector2 = node.global_position

	# Restore opacity
	var tween := create_tween()
	tween.tween_property(node, "modulate:a", 1.0, 0.2)

	# Spawn persistent rift with tentacle
	PlayerHUD.active_tentacle_count += 1
	var rift := Node2D.new()
	rift.set_script(RIFT_TENTACLE_SCENE)
	rift.global_position = pos + Vector2(0, -30)
	rift.setup(player_index)
	players_container.add_child(rift)

	# Lock class changes for this player for the rift duration
	_rift_locks[player_index] = 15.0
	PlayerHUD.class_change_locked[player_index] = true


func _spawn_red_portal(pos: Vector2) -> void:
	## Red swirling portal effect (ColorRect + tween for now)
	var portal := ColorRect.new()
	portal.color = Color(0.9, 0.1, 0.1, 0.8)
	portal.size = Vector2(40, 60)
	portal.position = pos - Vector2(20, 50)
	portal.z_index = 5
	players_container.add_child(portal)

	var tween := create_tween()
	tween.tween_property(portal, "scale", Vector2(1.5, 1.5), 0.15)
	tween.parallel().tween_property(portal, "modulate:a", 0.0, 0.5)
	tween.tween_callback(portal.queue_free)


func _spawn_poof(pos: Vector2) -> void:
	## Smoke poof (expanding circle that fades)
	var poof := ColorRect.new()
	poof.color = Color(0.8, 0.8, 0.8, 0.7)
	poof.size = Vector2(30, 30)
	poof.position = pos - Vector2(15, 30)
	poof.z_index = 6
	players_container.add_child(poof)

	var tween := create_tween()
	tween.tween_property(poof, "scale", Vector2(2.5, 2.5), 0.3)
	tween.parallel().tween_property(poof, "modulate:a", 0.0, 0.4)
	tween.tween_callback(poof.queue_free)


# -- Player Join/Leave Callbacks -----------------------------------------------

func _on_player_joined(player_index: int) -> void:
	_spawn_lobby_player(player_index)


func _on_player_left(player_index: int) -> void:
	_remove_lobby_player(player_index)
	_ghost_players.erase(player_index)


# -- Lobby Player Spawning -----------------------------------------------------

const SPAWN_POSITIONS := [
	Vector2(670, 520),   # P1: upper-left platform
	Vector2(1250, 520),  # P2: upper-right platform
	Vector2(540, 740),   # P3: lower-left platform
	Vector2(1380, 740),  # P4: lower-right platform
]

func _spawn_lobby_player(player_index: int) -> void:
	var p_data: Dictionary = PlayerManager.get_player(player_index)
	if p_data.is_empty():
		return

	var player_node: CharacterBody2D = PLAYER_SIDE_SCENE.instantiate()
	player_node.player_index = player_index
	player_node.device_id = p_data["device_id"]
	player_node.character_class = p_data["character_class"]

	# Spawn on assigned platform (config overrides default)
	var spawns: Array = _config_spawn_positions if not _config_spawn_positions.is_empty() else SPAWN_POSITIONS
	if player_index < spawns.size():
		player_node.global_position = spawns[player_index]
	else:
		player_node.global_position = spawn_point.global_position

	players_container.add_child(player_node)
	_spawned_players[player_index] = player_node


func _remove_lobby_player(player_index: int) -> void:
	if _spawned_players.has(player_index):
		_spawned_players[player_index].queue_free()
		_spawned_players.erase(player_index)


func _get_player_index_for_device(device_id: int) -> int:
	for pi in PlayerManager.players:
		if PlayerManager.players[pi]["device_id"] == device_id:
			return pi
	return -1


# -- Transition ----------------------------------------------------------------

func _start_game() -> void:
	set_process_input(false)
	GameManager.go_to_overworld()
