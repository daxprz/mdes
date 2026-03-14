extends Node2D

## Base tower scene for side-scrolling platformer sections.
## Each tower uses this with different tower_id to vary layout and difficulty.

signal tower_cleared(tower_id: int)

const GRAVITY := 800.0
const TOWER_WIDTH := 400.0
const TOWER_HEIGHT := 2400.0
const PLATFORM_COUNT_BASE := 12
const MAX_PLATFORM_SPACING := 140.0  # Must be below max jump height (v²/2g = 168px)
const PLAYER_SIDE_SCENE := preload("res://scenes/characters/player_side.tscn")
const MUFFIN_SCENE_PATH := "res://scenes/items/mini_muffin.tscn"
const SKELETON_SCENE_PATH := "res://scenes/enemies/skeleton.tscn"
const SPIKES_SCENE := "res://scenes/traps/spikes.tscn"
const PENDULUM_SCENE := "res://scenes/traps/pendulum.tscn"
const ARROW_TRAP_SCENE := "res://scenes/traps/arrow_trap.tscn"
const LAVA_POOL_SCENE := "res://scenes/traps/lava_pool.tscn"
const WIND_GUST_SCENE := "res://scenes/traps/wind_gust.tscn"
const FALLING_ROCKS_SCENE := "res://scenes/traps/falling_rocks.tscn"

@export var tower_id: int = 1

var _muffins_collected := 0
var _muffins_total := 0
var _enemies_killed := 0
var _exiting := false

@onready var camera: Camera2D = $Camera2D
@onready var platforms_container: Node2D = $Platforms
@onready var enemies_container: Node2D = $Enemies
@onready var muffins_container: Node2D = $Muffins
@onready var exit_door: Area2D = $ExitDoor
@onready var muffin_counter_label: Label = $UI/MuffinCounter
@onready var traps_container: Node2D = $Traps


func _ready() -> void:
	GameManager.change_state(GameManager.GameState.TOWER)
	tower_id = GameManager.current_tower_id
	PlayerManager.player_joined.connect(_on_player_joined_midgame)
	_build_tower()
	_spawn_players()
	_update_muffin_counter()


func _on_player_joined_midgame(player_index: int) -> void:
	var p_data: Dictionary = PlayerManager.players[player_index]
	var spawn_pos := Vector2(TOWER_WIDTH / 2.0, TOWER_HEIGHT - 40)
	var player_node: CharacterBody2D = PLAYER_SIDE_SCENE.instantiate()
	player_node.name = "TowerPlayer_%d" % player_index
	player_node.player_index = player_index
	player_node.device_id = p_data["device_id"]
	player_node.character_class = p_data["character_class"]
	player_node.global_position = spawn_pos + Vector2(30, 0) * player_index
	add_child(player_node)


func _build_tower() -> void:
	var platform_count: int = PLATFORM_COUNT_BASE + tower_id * 2
	var vertical_spacing: float = TOWER_HEIGHT / (platform_count + 1)
	# If spacing exceeds max jump height, add more platforms instead
	if vertical_spacing > MAX_PLATFORM_SPACING:
		platform_count = int(TOWER_HEIGHT / MAX_PLATFORM_SPACING)
		vertical_spacing = TOWER_HEIGHT / (platform_count + 1)

	# Generate platforms ascending the tower.
	for i in range(platform_count):
		var y_pos := TOWER_HEIGHT - (i + 1) * vertical_spacing
		var x_offset := _get_platform_x(i, tower_id)
		var platform_width: float = randf_range(80.0, 160.0)
		_create_platform(Vector2(x_offset, y_pos), platform_width)

		# Place muffin on some platforms.
		if i % 2 == 0:
			_spawn_muffin(Vector2(x_offset, y_pos - 20))

		# Place enemy on some platforms.
		if i % 3 == 1 and i > 0:
			_spawn_enemy(Vector2(x_offset, y_pos - 24), platform_width * 0.4)

	# Floor platform at the bottom.
	_create_platform(Vector2(TOWER_WIDTH / 2.0, TOWER_HEIGHT - 10), TOWER_WIDTH)

	# Place traps throughout the tower (more in harder towers)
	_place_traps(platform_count, vertical_spacing)

	# Set up exit door at the top.
	if exit_door:
		exit_door.position = Vector2(TOWER_WIDTH / 2.0, 40)
		exit_door.body_entered.connect(_on_exit_door_entered)


func _get_platform_x(index: int, tid: int) -> float:
	# Alternate platforms left and right with some variation per tower.
	var base_x := TOWER_WIDTH / 2.0
	var offset := 100.0 * (1 if index % 2 == 0 else -1)
	# Add tower-specific variation.
	offset += sin(index * 0.7 + tid) * 40.0
	return clampf(base_x + offset, 60.0, TOWER_WIDTH - 60.0)


func _create_platform(pos: Vector2, width: float) -> void:
	var platform := StaticBody2D.new()
	platform.position = pos

	var col_shape := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(width, 16)
	col_shape.shape = shape
	platform.add_child(col_shape)

	# Visual.
	var rect := ColorRect.new()
	rect.size = Vector2(width, 16)
	rect.position = Vector2(-width / 2.0, -8)
	rect.color = Color(0.45, 0.35, 0.25)  # Brown platform.
	platform.add_child(rect)

	platforms_container.add_child(platform)


func _spawn_muffin(pos: Vector2) -> void:
	_muffins_total += 1
	var muffin_scene := load(MUFFIN_SCENE_PATH)
	if muffin_scene:
		var muffin: Area2D = muffin_scene.instantiate()
		muffin.position = pos
		muffin.collected.connect(_on_muffin_collected)
		muffins_container.add_child(muffin)
	else:
		# Fallback: create a simple muffin placeholder.
		var muffin := Area2D.new()
		muffin.position = pos

		var col := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 8
		col.shape = shape
		muffin.add_child(col)

		var rect := ColorRect.new()
		rect.size = Vector2(12, 12)
		rect.position = Vector2(-6, -6)
		rect.color = Color(1.0, 0.85, 0.0)  # Gold.
		muffin.add_child(rect)

		muffins_container.add_child(muffin)


func _place_traps(platform_count: int, vertical_spacing: float) -> void:
	# Trap density scales with tower difficulty
	var trap_chance: float = 0.15 + tower_id * 0.1  # Tower 1: 25%, Tower 4: 55%

	for i in range(platform_count):
		var y_pos: float = TOWER_HEIGHT - (i + 1) * vertical_spacing
		var x_offset: float = _get_platform_x(i, tower_id)

		# Skip first 2 platforms (safe zone at start)
		if i < 2:
			continue

		var roll: float = randf()
		if roll > trap_chance:
			continue

		# Pick a trap type based on position and tower
		var trap_roll: float = randf()

		if trap_roll < 0.25:
			# Spikes on platform surface
			_spawn_trap(SPIKES_SCENE, Vector2(x_offset, y_pos - 16))
		elif trap_roll < 0.45:
			# Arrow trap on a wall
			var wall_x: float = 15.0 if randf() > 0.5 else TOWER_WIDTH - 15.0
			var facing_right: bool = wall_x < TOWER_WIDTH / 2.0
			_spawn_arrow_trap(Vector2(wall_x, y_pos - 30), facing_right)
		elif trap_roll < 0.6:
			# Pendulum between platforms
			_spawn_trap(PENDULUM_SCENE, Vector2(x_offset, y_pos - vertical_spacing * 0.5))
		elif trap_roll < 0.75:
			# Lava pool on floor of a section
			_spawn_trap(LAVA_POOL_SCENE, Vector2(x_offset, y_pos + 8))
		elif trap_roll < 0.85:
			# Wind gust pushing sideways
			var wind_dir: float = 1.0 if randf() > 0.5 else -1.0
			_spawn_wind_gust(Vector2(x_offset, y_pos - 40), wind_dir)
		else:
			# Falling rocks triggered by proximity
			_spawn_trap(FALLING_ROCKS_SCENE, Vector2(x_offset, y_pos - vertical_spacing * 0.7))

	# Tower 3+ gets a dark zone in the middle section
	if tower_id >= 3:
		var dark_scene := load("res://scenes/traps/dark_zone.tscn")
		if dark_scene:
			var dark: Node = dark_scene.instantiate()
			dark.position = Vector2(TOWER_WIDTH / 2.0, TOWER_HEIGHT * 0.5)
			if dark.has_method("set") and "zone_height" in dark:
				dark.zone_height = 400.0
			traps_container.add_child(dark)


func _spawn_trap(scene_path: String, pos: Vector2) -> void:
	var scene := load(scene_path)
	if not scene:
		return
	var trap: Node2D = scene.instantiate()
	trap.position = pos
	traps_container.add_child(trap)


func _spawn_arrow_trap(pos: Vector2, facing_right: bool) -> void:
	var scene := load(ARROW_TRAP_SCENE)
	if not scene:
		return
	var trap: Node2D = scene.instantiate()
	trap.position = pos
	if "fire_direction" in trap:
		trap.fire_direction = Vector2.RIGHT if facing_right else Vector2.LEFT
	traps_container.add_child(trap)


func _spawn_wind_gust(pos: Vector2, dir: float) -> void:
	var scene := load(WIND_GUST_SCENE)
	if not scene:
		return
	var trap: Node2D = scene.instantiate()
	trap.position = pos
	if "push_direction" in trap:
		trap.push_direction = Vector2(dir, 0)
	traps_container.add_child(trap)


func _spawn_enemy(pos: Vector2, patrol_dist: float) -> void:
	var enemy_scene := load(SKELETON_SCENE_PATH)
	if enemy_scene:
		var enemy: CharacterBody2D = enemy_scene.instantiate()
		enemy.position = pos
		enemy.set_patrol_distance(patrol_dist)
		enemy.died.connect(_on_enemy_died)
		enemies_container.add_child(enemy)


func _spawn_players() -> void:
	var spawn_pos := Vector2(TOWER_WIDTH / 2.0, TOWER_HEIGHT - 40)
	var offset_step := Vector2(30, 0)

	for player_index in PlayerManager.players:
		var p_data: Dictionary = PlayerManager.players[player_index]
		if not p_data["is_alive"]:
			continue

		var player_node: CharacterBody2D = PLAYER_SIDE_SCENE.instantiate()
		player_node.name = "TowerPlayer_%d" % player_index
		player_node.player_index = player_index
		player_node.device_id = p_data["device_id"]
		player_node.character_class = p_data["character_class"]
		player_node.global_position = spawn_pos + offset_step * player_index
		add_child(player_node)

	# Replace the default camera with a multi-player camera
	if camera:
		camera.queue_free()
	var multi_cam_script := load("res://scripts/ui/multi_camera.gd")
	var new_cam := Camera2D.new()
	new_cam.set_script(multi_cam_script)
	new_cam.min_zoom = 0.5
	new_cam.max_zoom = 1.8
	new_cam.zoom_margin = Vector2(100, 80)
	new_cam.limit_left = 0
	new_cam.limit_right = int(TOWER_WIDTH)
	new_cam.limit_top = 0
	new_cam.limit_bottom = int(TOWER_HEIGHT)
	new_cam.position = spawn_pos
	add_child(new_cam)


func _on_muffin_collected(_player_index: int) -> void:
	_muffins_collected += 1
	_update_muffin_counter()


func _on_enemy_died(pos: Vector2) -> void:
	_enemies_killed += 1
	# Drop muffins at enemy death position.
	for i in range(3):
		var offset := Vector2(randf_range(-20, 20), randf_range(-10, 10))
		_spawn_muffin(pos + offset)


func _on_exit_door_entered(body: Node2D) -> void:
	if _exiting:
		return
	if not ("player_index" in body or body.has_meta("player_index")):
		return

	_exiting = true
	tower_cleared.emit(tower_id)

	# Go to boss fight!
	GameManager.go_to_boss(tower_id)


func _update_muffin_counter() -> void:
	if muffin_counter_label:
		muffin_counter_label.text = "Muffins: %d / %d" % [_muffins_collected, _muffins_total]
