extends Node2D

## Base tower scene for side-scrolling platformer sections.
## Each tower uses this with different tower_id to vary layout and difficulty.

signal tower_cleared(tower_id: int)

const GRAVITY := 800.0
const BASE_TOWER_WIDTH := 600.0
const BASE_TOWER_HEIGHT := 3200.0

# Per-tower size overrides
const TOWER_SIZES: Dictionary = {
	2: {"width": 900.0, "height": 4800.0},
}

var TOWER_WIDTH := BASE_TOWER_WIDTH
var TOWER_HEIGHT := BASE_TOWER_HEIGHT
const PLATFORM_COUNT_BASE := 35
const MAX_PLATFORM_SPACING := 80.0  # Dense platforming
const PLAYER_SIDE_SCENE := preload("res://scenes/characters/player_side.tscn")
const MUFFIN_SCENE_PATH := "res://scenes/items/mini_muffin.tscn"
const SKELETON_SCENE_PATH := "res://scenes/enemies/skeleton.tscn"
const FAIRY_CAKE_BAT_SCENE_PATH := "res://scenes/enemies/fairy_cake_bat.tscn"
const COOKIE_ARCHER_SCENE_PATH := "res://scenes/enemies/cookie_archer.tscn"
const CANDY_GOLEM_SCENE_PATH := "res://scenes/enemies/candy_golem.tscn"
const SPRINKLE_SWARM_SCENE_PATH := "res://scenes/enemies/sprinkle_swarm.tscn"
const CUPCAKE_BOMBER_SCENE_PATH := "res://scenes/enemies/cupcake_bomber.tscn"
const LICORICE_WHIP_SCENE_PATH := "res://scenes/enemies/licorice_whip.tscn"
const GUMMY_BEAR_SCENE_PATH := "res://scenes/enemies/gummy_bear.tscn"
const WAFER_SHIELD_SCENE_PATH := "res://scenes/enemies/wafer_shield.tscn"
const CANDY_CORN_SCENE_PATH := "res://scenes/enemies/candy_corn.tscn"
const MARSHMALLOW_BLOB_SCENE_PATH := "res://scenes/enemies/marshmallow_blob.tscn"
const PEPPERMINT_ROLLER_SCENE_PATH := "res://scenes/enemies/peppermint_roller.tscn"
const JELLYBEAN_SNIPER_SCENE_PATH := "res://scenes/enemies/jellybean_sniper.tscn"
const SPIKES_SCENE := "res://scenes/traps/spikes.tscn"
const PENDULUM_SCENE := "res://scenes/traps/pendulum.tscn"
const ARROW_TRAP_SCENE := "res://scenes/traps/arrow_trap.tscn"
const LAVA_POOL_SCENE := "res://scenes/traps/lava_pool.tscn"
const WIND_GUST_SCENE := "res://scenes/traps/wind_gust.tscn"
const FALLING_ROCKS_SCENE := "res://scenes/traps/falling_rocks.tscn"
const SAW_BLADE_SCENE := "res://scenes/traps/saw_blade.tscn"
const ICING_WATERFALL_SCENE := "res://scenes/traps/icing_waterfall.tscn"
const BOUNCE_PAD_SCENE := "res://scenes/traps/bounce_pad.tscn"
const RISING_LAVA_SCENE := "res://scenes/traps/rising_lava.tscn"
const CRYSTAL_BARRIER_SCENE := "res://scenes/traps/crystal_barrier.tscn"
const FROSTING_SLIDE_SCENE := "res://scenes/traps/frosting_slide.tscn"
const CRUMBLE_FLOOR_SCENE := "res://scenes/traps/crumble_floor.tscn"
const CARAMEL_ZONE_SCENE := "res://scenes/traps/caramel_zone.tscn"
const POPCORN_GEYSER_SCENE := "res://scenes/traps/popcorn_geyser.tscn"
const SPRINKLE_MINE_SCENE := "res://scenes/traps/sprinkle_mine.tscn"

const MINIBOSS_SCENES: Dictionary = {
	1: "res://scenes/enemies/frosting_fountain_miniboss.tscn",  # Replaced cookie cutter
	2: "res://scenes/enemies/frosting_fountain_miniboss.tscn",
	3: "res://scenes/enemies/sprinkle_tornado_miniboss.tscn",
	4: "res://scenes/enemies/batter_elemental_miniboss.tscn",
}
const MINIBOSS_MUFFIN_REWARD := 10

# Task 3: Tower theme color palettes
# Each entry: { platform_color, bg_color, wall_color }
const TOWER_THEMES: Dictionary = {
	1: {  # Gingerbread
		"platform": Color(0.55, 0.35, 0.15),
		"background": Color(0.2, 0.15, 0.1),
		"wall": Color(0.45, 0.28, 0.12),
	},
	2: {  # Icing
		"platform": Color(0.85, 0.85, 0.95),
		"background": Color(0.15, 0.15, 0.25),
		"wall": Color(0.9, 0.9, 0.95),
	},
	3: {  # Sprinkle
		"platform": Color(1.0, 0.3, 0.5),  # Base; cycled in _get_sprinkle_color
		"background": Color(0.1, 0.05, 0.15),
		"wall": Color(0.3, 0.1, 0.35),
	},
	4: {  # Muffin
		"platform": Color(0.6, 0.45, 0.2),
		"background": Color(0.15, 0.05, 0.05),
		"wall": Color(0.25, 0.1, 0.08),
	},
}

# Task 1: Fork interval and merge length
const FORK_INTERVAL := 5          # Every 5th platform section is a fork
const FORK_PATH_LENGTH := 3       # Each fork side has 3 platforms before merging

# Task 2: Secret area constants
const SECRET_AREAS_PER_TOWER := 2
const SECRET_MUFFIN_COUNT_MIN := 5
const SECRET_MUFFIN_COUNT_MAX := 8

# Task 7: Vertical section constants
const VERTICAL_SHAFT_WIDTH := 80.0
const VERTICAL_SHAFT_HEIGHT := 200.0

@export var tower_id: int = 1

var _muffins_collected := 0
var _muffins_total := 0
var _enemies_killed := 0
var _exiting := false
var _miniboss_active := false
var _miniboss_barrier: StaticBody2D = null
var _miniboss_trigger: Area2D = null
var _moving_platforms: Array[Node2D] = []
var _sprinkle_color_index: int = 0

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


func _process(delta: float) -> void:
	# Task 4: Update moving platforms
	for mp: Node2D in _moving_platforms:
		if not is_instance_valid(mp):
			continue
		var data: Dictionary = mp.get_meta("move_data") as Dictionary
		var start_pos: Vector2 = data["start"] as Vector2
		var end_pos: Vector2 = data["end"] as Vector2
		var spd: float = data["speed"] as float
		var progress: float = data["progress"] as float
		var direction_sign: float = data["dir"] as float

		progress += spd * delta * direction_sign
		if progress >= 1.0:
			progress = 1.0
			direction_sign = -1.0
		elif progress <= 0.0:
			progress = 0.0
			direction_sign = 1.0

		data["progress"] = progress
		data["dir"] = direction_sign
		mp.set_meta("move_data", data)
		mp.position = start_pos.lerp(end_pos, progress)


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
	# Apply per-tower size overrides
	if TOWER_SIZES.has(tower_id):
		TOWER_WIDTH = TOWER_SIZES[tower_id]["width"]
		TOWER_HEIGHT = TOWER_SIZES[tower_id]["height"]
	else:
		TOWER_WIDTH = BASE_TOWER_WIDTH
		TOWER_HEIGHT = BASE_TOWER_HEIGHT

	# Task 3: Apply tower background color
	_apply_tower_theme()

	var platform_count: int = PLATFORM_COUNT_BASE + tower_id * 2
	var vertical_spacing: float = TOWER_HEIGHT / (platform_count + 1)
	# If spacing exceeds max jump height, add more platforms instead
	if vertical_spacing > MAX_PLATFORM_SPACING:
		platform_count = int(TOWER_HEIGHT / MAX_PLATFORM_SPACING)
		vertical_spacing = TOWER_HEIGHT / (platform_count + 1)

	# Track which indices are fork zones or vertical shaft to skip normal gen
	var fork_indices: Array[int] = []
	var vertical_shaft_index: int = -1

	# Task 7: Determine vertical shaft placement (60-70% height)
	var shaft_fraction: float = randf_range(0.6, 0.7)
	vertical_shaft_index = int(platform_count * shaft_fraction)

	# Task 1: Determine fork indices (every FORK_INTERVAL platforms)
	var fork_start: int = FORK_INTERVAL
	while fork_start < platform_count - FORK_PATH_LENGTH - 2:
		fork_indices.append(fork_start)
		fork_start += FORK_INTERVAL + FORK_PATH_LENGTH + 1  # Skip past the fork zone

	# Track crumbling platform placement for Task 5
	var crumble_budget: int = 2 + tower_id  # 3 for T1, up to 6 for T4
	var crumble_placed: int = 0
	var crumble_interval: int = maxi(platform_count / (crumble_budget + 1), 3)

	# Task 6: Conveyor belt tracking
	var conveyor_budget: int = 0
	if tower_id >= 2:
		conveyor_budget = 1 + (tower_id - 2)  # T2: 1, T3: 2, T4: 3
	var conveyor_placed: int = 0
	var conveyor_interval: int = maxi(platform_count / (conveyor_budget + 1), 4)

	# Task 4: Moving platform tracking
	var moving_budget: int = 1 + (tower_id - 1)  # T1: 1, T4: 4
	var moving_placed: int = 0
	var moving_interval: int = maxi(platform_count / (moving_budget + 1), 4)

	# Main platform generation loop
	var i: int = 0
	while i < platform_count:
		var y_pos: float = TOWER_HEIGHT - (i + 1) * vertical_spacing
		var x_offset: float = _get_platform_x(i, tower_id)

		# --- Task 7: Vertical shaft section ---
		if i == vertical_shaft_index:
			_create_vertical_shaft(Vector2(TOWER_WIDTH / 2.0, y_pos), vertical_spacing)
			# The shaft replaces one platform; the player wall-jumps through it
			i += 1
			continue

		# --- Task 1: Fork section (dual paths) ---
		if i in fork_indices:
			_create_fork_section(i, y_pos, vertical_spacing)
			i += FORK_PATH_LENGTH + 1  # Skip past the fork zone indices
			continue

		# --- Task 5: Crumbling platform replacement ---
		if crumble_placed < crumble_budget and i > 2 and i % crumble_interval == 0:
			_create_crumble_platform(Vector2(x_offset, y_pos))
			crumble_placed += 1
			# Still place muffin/enemy on crumble platforms
			if i % 2 == 0:
				_spawn_muffin(Vector2(x_offset, y_pos - 20))
			i += 1
			continue

		# --- Task 6: Conveyor belt platform ---
		if conveyor_placed < conveyor_budget and i > 3 and (i - 2) % conveyor_interval == 0:
			var conv_dir: float = 1.0 if conveyor_placed % 2 == 0 else -1.0
			var conv_speed: float = 60.0 + tower_id * 15.0
			var conv_width: float = randf_range(100.0, 160.0)
			_create_conveyor_platform(Vector2(x_offset, y_pos), conv_width, conv_dir, conv_speed)
			conveyor_placed += 1
			if i % 2 == 0:
				_spawn_muffin(Vector2(x_offset, y_pos - 20))
			i += 1
			continue

		# --- Task 4: Moving platform ---
		if moving_placed < moving_budget and i > 2 and (i - 1) % moving_interval == 0:
			var move_start := Vector2(80.0, y_pos)
			var move_end := Vector2(TOWER_WIDTH - 80.0, y_pos)
			var move_speed: float = 0.3 + tower_id * 0.1
			_create_moving_platform(move_start, move_end, 100.0, move_speed)
			moving_placed += 1
			_spawn_muffin(Vector2(TOWER_WIDTH / 2.0, y_pos - 20))
			i += 1
			continue

		# --- Normal platform ---
		var platform_width: float = randf_range(120.0, 220.0)
		_create_platform(Vector2(x_offset, y_pos), platform_width)

		# Place muffin on some platforms.
		if i % 2 == 0:
			_spawn_muffin(Vector2(x_offset, y_pos - 20))

		# Place enemy on some platforms (spaced out).
		if i % 5 == 1 and i > 0:
			_spawn_enemy(Vector2(x_offset, y_pos - 24), platform_width * 0.4)

		i += 1

	# Floor platform at the bottom.
	_create_platform(Vector2(TOWER_WIDTH / 2.0, TOWER_HEIGHT - 10), TOWER_WIDTH)

	# Tower walls with themed color
	_apply_wall_theme()

	# Interior walls - small obstacles inside the tower
	_place_interior_walls(platform_count, vertical_spacing)

	# Place traps throughout the tower (more in harder towers)
	_place_traps(platform_count, vertical_spacing)

	# Task 2: Secret areas
	_place_secret_areas(platform_count, vertical_spacing)

	# Set up mini-boss trigger at the midpoint of the tower.
	_setup_miniboss_trigger()

	# Set up exit door at the top.
	if exit_door:
		exit_door.position = Vector2(TOWER_WIDTH / 2.0, 40)
		exit_door.body_entered.connect(_on_exit_door_entered)


# -- Task 3: Tower Theme System -----------------------------------------------

func _apply_tower_theme() -> void:
	var theme_id: int = clampi(tower_id, 1, 4)
	var theme: Dictionary = TOWER_THEMES.get(theme_id, TOWER_THEMES[1]) as Dictionary
	var bg_color: Color = theme["background"] as Color

	# Create a full-tower background ColorRect
	var bg := ColorRect.new()
	bg.size = Vector2(TOWER_WIDTH, TOWER_HEIGHT)
	bg.position = Vector2.ZERO
	bg.color = bg_color
	bg.z_index = -10
	add_child(bg)
	move_child(bg, 0)


func _get_platform_color(platform_index: int) -> Color:
	var theme_id: int = clampi(tower_id, 1, 4)
	if theme_id == 3:
		return _get_sprinkle_color(platform_index)
	var theme: Dictionary = TOWER_THEMES.get(theme_id, TOWER_THEMES[1]) as Dictionary
	return theme["platform"] as Color


func _get_sprinkle_color(index: int) -> Color:
	# Cycle through rainbow colors for Tower 3 (Sprinkle)
	var colors: Array[Color] = [
		Color(1.0, 0.3, 0.3),   # Red
		Color(1.0, 0.6, 0.2),   # Orange
		Color(1.0, 1.0, 0.3),   # Yellow
		Color(0.3, 1.0, 0.3),   # Green
		Color(0.3, 0.6, 1.0),   # Blue
		Color(0.7, 0.3, 1.0),   # Purple
		Color(1.0, 0.4, 0.8),   # Pink
	]
	var color_idx: int = index % colors.size()
	return colors[color_idx]


func _get_wall_color() -> Color:
	var theme_id: int = clampi(tower_id, 1, 4)
	var theme: Dictionary = TOWER_THEMES.get(theme_id, TOWER_THEMES[1]) as Dictionary
	return theme["wall"] as Color


func _place_interior_walls(platform_count: int, vertical_spacing: float) -> void:
	# Place small wall segments inside the tower for variety
	var wall_count: int = 25 + tower_id * 8  # 33 for T1, 57 for T4
	var wall_color: Color = _get_wall_color().darkened(0.2)

	for w in range(wall_count):
		# Pick a random height (skip bottom safe zone and top exit area)
		var min_y: float = TOWER_HEIGHT * 0.1
		var max_y: float = TOWER_HEIGHT * 0.85
		var wall_y: float = randf_range(min_y, max_y)

		# Random side: left wall stub or right wall stub
		var from_left: bool = randf() > 0.5
		var wall_width: float = randf_range(40.0, 120.0)
		var wall_height: float = randf_range(12.0, 24.0)

		# Don't extend more than 60% across the tower
		wall_width = minf(wall_width, TOWER_WIDTH * 0.6)

		var wall_x: float
		if from_left:
			wall_x = wall_width / 2.0
		else:
			wall_x = TOWER_WIDTH - wall_width / 2.0

		var wall := StaticBody2D.new()
		wall.position = Vector2(wall_x, wall_y)

		var col := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(wall_width, wall_height)
		col.shape = shape
		wall.add_child(col)

		var rect := ColorRect.new()
		rect.size = Vector2(wall_width, wall_height)
		rect.position = Vector2(-wall_width / 2.0, -wall_height / 2.0)
		rect.color = wall_color
		wall.add_child(rect)

		platforms_container.add_child(wall)


func _apply_wall_theme() -> void:
	# Recolor the walls from the .tscn to match the tower theme
	var wall_color: Color = _get_wall_color()
	var left_wall: ColorRect = get_node_or_null("WallLeft")
	var right_wall: ColorRect = get_node_or_null("WallRight")
	if left_wall:
		left_wall.color = wall_color
	if right_wall:
		right_wall.color = wall_color


func _add_rainbow_streaks(wall_node: Node2D, wall_w: float) -> void:
	var streak_count: int = 12
	for s in range(streak_count):
		var streak := ColorRect.new()
		var streak_y: float = (TOWER_HEIGHT / streak_count) * s
		streak.size = Vector2(wall_w, 8.0)
		streak.position = Vector2(-wall_w / 2.0, -TOWER_HEIGHT / 2.0 + streak_y)
		streak.color = _get_sprinkle_color(s)
		streak.modulate.a = 0.5
		wall_node.add_child(streak)


# -- Core Platform Creation (Task 3 themed) -----------------------------------

func _get_platform_x(index: int, tid: int) -> float:
	# Alternate platforms left and right with some variation per tower.
	var base_x := TOWER_WIDTH / 2.0
	var offset := 100.0 * (1 if index % 2 == 0 else -1)
	# Add tower-specific variation.
	offset += sin(index * 0.7 + tid) * 40.0
	return clampf(base_x + offset, 60.0, TOWER_WIDTH - 60.0)


func _create_platform(pos: Vector2, width: float, color_override: Color = Color(-1, -1, -1)) -> void:
	var platform := StaticBody2D.new()
	platform.position = pos

	var col_shape := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(width, 16)
	col_shape.shape = shape
	platform.add_child(col_shape)

	# Visual with themed color
	var rect := ColorRect.new()
	rect.size = Vector2(width, 16)
	rect.position = Vector2(-width / 2.0, -8)
	if color_override.r >= 0.0:
		rect.color = color_override
	else:
		rect.color = _get_platform_color(_sprinkle_color_index)
	_sprinkle_color_index += 1
	platform.add_child(rect)

	platforms_container.add_child(platform)


# -- Task 1: Multiple Paths (Fork Sections) -----------------------------------

func _create_fork_section(start_index: int, start_y: float, v_spacing: float) -> void:
	# Create a merge platform at the start of the fork
	var merge_start_x: float = TOWER_WIDTH / 2.0
	_create_platform(Vector2(merge_start_x, start_y), 140.0)

	# Left path: more enemies but more muffins
	for p in range(FORK_PATH_LENGTH):
		var fork_y: float = start_y - (p + 1) * v_spacing
		var left_x: float = clampf(70.0 + randf_range(0.0, 40.0), 60.0, TOWER_WIDTH / 2.0 - 20.0)
		var left_width: float = randf_range(70.0, 110.0)
		_create_platform(Vector2(left_x, fork_y), left_width)

		# Left path: always muffins, sometimes enemies
		_spawn_muffin(Vector2(left_x, fork_y - 20))
		if p % 2 == 0:
			_spawn_muffin(Vector2(left_x + 20.0, fork_y - 20))  # Extra muffin
		if p == 1:
			_spawn_enemy(Vector2(left_x, fork_y - 24), left_width * 0.3)

	# Right path: more traps but shorter (one fewer platform = shortcut)
	var right_steps: int = maxi(FORK_PATH_LENGTH - 1, 1)
	var right_v_spacing: float = (FORK_PATH_LENGTH * v_spacing) / right_steps
	for p in range(right_steps):
		var fork_y: float = start_y - (p + 1) * right_v_spacing
		var right_x: float = clampf(TOWER_WIDTH - 70.0 + randf_range(-40.0, 0.0), TOWER_WIDTH / 2.0 + 20.0, TOWER_WIDTH - 60.0)
		var right_width: float = randf_range(70.0, 110.0)
		_create_platform(Vector2(right_x, fork_y), right_width)

		# Right path: a muffin but also a trap
		_spawn_muffin(Vector2(right_x, fork_y - 20))
		if p == 0:
			_spawn_trap(SPIKES_SCENE, Vector2(right_x, fork_y - 16))

	# Merge platform at the top of the fork
	var merge_end_y: float = start_y - (FORK_PATH_LENGTH + 1) * v_spacing
	_create_platform(Vector2(merge_start_x, merge_end_y), 160.0)
	_spawn_muffin(Vector2(merge_start_x, merge_end_y - 20))


# -- Task 2: Secret Areas -----------------------------------------------------

func _place_secret_areas(platform_count: int, vertical_spacing: float) -> void:
	var secret_count: int = mini(SECRET_AREAS_PER_TOWER, platform_count - 4)
	if secret_count <= 0:
		return

	# Pick random platform indices for secret areas (avoid bottom 3 and top 2)
	var candidate_indices: Array[int] = []
	for idx in range(3, platform_count - 2):
		candidate_indices.append(idx)

	# Shuffle and pick
	candidate_indices.shuffle()
	var chosen_count: int = mini(secret_count, candidate_indices.size())
	for s in range(chosen_count):
		var idx: int = candidate_indices[s]
		var y_pos: float = TOWER_HEIGHT - (idx + 1) * vertical_spacing
		# Secret area on a random side
		var on_left: bool = randf() > 0.5
		var alcove_x: float = -40.0 if on_left else TOWER_WIDTH + 40.0
		var barrier_x: float = 8.0 if on_left else TOWER_WIDTH - 8.0

		_create_secret_alcove(Vector2(alcove_x, y_pos), Vector2(barrier_x, y_pos))


func _create_secret_alcove(alcove_pos: Vector2, barrier_pos: Vector2) -> void:
	# Place crystal barrier at the entrance
	_spawn_trap(CRYSTAL_BARRIER_SCENE, barrier_pos)

	# Visual hint: a crack-colored rectangle near the barrier
	var hint := ColorRect.new()
	hint.size = Vector2(6, 20)
	hint.position = Vector2(barrier_pos.x - 3, barrier_pos.y - 30)
	hint.color = Color(0.7, 0.5, 0.3, 0.4)
	hint.z_index = -1
	platforms_container.add_child(hint)

	# Create the alcove floor
	var alcove_floor := StaticBody2D.new()
	alcove_floor.position = Vector2(alcove_pos.x, alcove_pos.y + 8)
	var alcove_col := CollisionShape2D.new()
	var alcove_shape := RectangleShape2D.new()
	alcove_shape.size = Vector2(60, 16)
	alcove_col.shape = alcove_shape
	alcove_floor.add_child(alcove_col)

	var alcove_rect := ColorRect.new()
	alcove_rect.size = Vector2(60, 16)
	alcove_rect.position = Vector2(-30, -8)
	alcove_rect.color = _get_platform_color(_sprinkle_color_index).darkened(0.2)
	_sprinkle_color_index += 1
	alcove_floor.add_child(alcove_rect)
	platforms_container.add_child(alcove_floor)

	# Spawn bonus muffins in the alcove
	var muffin_count: int = randi_range(SECRET_MUFFIN_COUNT_MIN, SECRET_MUFFIN_COUNT_MAX)
	for m in range(muffin_count):
		var offset := Vector2(randf_range(-25, 25), -20 - randf_range(0, 40))
		_spawn_muffin(alcove_pos + offset)


# -- Task 4: Moving Platforms -------------------------------------------------

func _create_moving_platform(start_pos: Vector2, end_pos: Vector2, width: float, speed: float) -> void:
	var platform := AnimatableBody2D.new()
	platform.position = start_pos
	platform.sync_to_physics = true

	var col_shape := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(width, 16)
	col_shape.shape = shape
	platform.add_child(col_shape)

	# Visual - slightly different color to indicate movement
	var rect := ColorRect.new()
	rect.size = Vector2(width, 16)
	rect.position = Vector2(-width / 2.0, -8)
	var base_color: Color = _get_platform_color(_sprinkle_color_index)
	_sprinkle_color_index += 1
	rect.color = base_color.lightened(0.15)
	platform.add_child(rect)

	# Arrow indicators on the platform
	var arrow := ColorRect.new()
	arrow.size = Vector2(12, 4)
	arrow.position = Vector2(-6, -2)
	arrow.color = Color(1.0, 1.0, 1.0, 0.5)
	platform.add_child(arrow)

	# Store movement data as metadata
	var move_data: Dictionary = {
		"start": start_pos,
		"end": end_pos,
		"speed": speed,
		"progress": 0.0,
		"dir": 1.0,
	}
	platform.set_meta("move_data", move_data)
	_moving_platforms.append(platform)

	platforms_container.add_child(platform)


# -- Task 5: Crumbling Platforms -----------------------------------------------

func _create_crumble_platform(pos: Vector2) -> void:
	var scene := load(CRUMBLE_FLOOR_SCENE)
	if scene:
		var crumble: Node2D = scene.instantiate()
		crumble.position = pos
		platforms_container.add_child(crumble)
	else:
		# Fallback: just create a normal platform that looks fragile
		_create_platform(pos, 90.0, Color(0.6, 0.4, 0.3, 0.7))


# -- Task 6: Conveyor Belt Platforms -------------------------------------------

func _create_conveyor_platform(pos: Vector2, width: float, direction: float, speed: float) -> void:
	# Use StaticBody2D with constant_linear_velocity for conveyor effect
	var platform := StaticBody2D.new()
	platform.position = pos
	platform.constant_linear_velocity = Vector2(direction * speed, 0.0)

	var col_shape := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(width, 16)
	col_shape.shape = shape
	platform.add_child(col_shape)

	# Visual: yellow-ish tinted platform
	var rect := ColorRect.new()
	rect.size = Vector2(width, 16)
	rect.position = Vector2(-width / 2.0, -8)
	rect.color = Color(0.85, 0.75, 0.2)
	platform.add_child(rect)

	# Arrow indicators showing conveyor direction
	var arrow_count: int = int(width / 30.0)
	for a in range(arrow_count):
		var arrow := ColorRect.new()
		arrow.size = Vector2(8, 4)
		var arrow_x: float = -width / 2.0 + 15.0 + a * 30.0
		arrow.position = Vector2(arrow_x, -2)
		if direction > 0:
			arrow.color = Color(1.0, 0.9, 0.4, 0.8)
		else:
			arrow.color = Color(0.9, 0.8, 0.2, 0.8)
		platform.add_child(arrow)

	# Direction label arrow: > or <
	var dir_label := Label.new()
	dir_label.text = ">>>" if direction > 0 else "<<<"
	dir_label.position = Vector2(-12, -14)
	dir_label.add_theme_font_size_override("font_size", 10)
	dir_label.add_theme_color_override("font_color", Color(0.3, 0.2, 0.0))
	platform.add_child(dir_label)

	platforms_container.add_child(platform)


# -- Task 7: Vertical Shaft Section -------------------------------------------

func _create_vertical_shaft(center_pos: Vector2, v_spacing: float) -> void:
	var shaft_x: float = center_pos.x
	var shaft_top: float = center_pos.y - VERTICAL_SHAFT_HEIGHT / 2.0
	var shaft_bottom: float = center_pos.y + VERTICAL_SHAFT_HEIGHT / 2.0
	var half_shaft_w: float = VERTICAL_SHAFT_WIDTH / 2.0
	var wall_thickness: float = 12.0
	var wall_color: Color = _get_wall_color().lightened(0.1)

	# Left shaft wall
	var left_wall := StaticBody2D.new()
	left_wall.position = Vector2(shaft_x - half_shaft_w - wall_thickness / 2.0, center_pos.y)
	var left_col := CollisionShape2D.new()
	var left_shape := RectangleShape2D.new()
	left_shape.size = Vector2(wall_thickness, VERTICAL_SHAFT_HEIGHT)
	left_col.shape = left_shape
	left_wall.add_child(left_col)

	var left_rect := ColorRect.new()
	left_rect.size = Vector2(wall_thickness, VERTICAL_SHAFT_HEIGHT)
	left_rect.position = Vector2(-wall_thickness / 2.0, -VERTICAL_SHAFT_HEIGHT / 2.0)
	left_rect.color = wall_color
	left_wall.add_child(left_rect)
	platforms_container.add_child(left_wall)

	# Right shaft wall
	var right_wall := StaticBody2D.new()
	right_wall.position = Vector2(shaft_x + half_shaft_w + wall_thickness / 2.0, center_pos.y)
	var right_col := CollisionShape2D.new()
	var right_shape := RectangleShape2D.new()
	right_shape.size = Vector2(wall_thickness, VERTICAL_SHAFT_HEIGHT)
	right_col.shape = right_shape
	right_wall.add_child(right_col)

	var right_rect := ColorRect.new()
	right_rect.size = Vector2(wall_thickness, VERTICAL_SHAFT_HEIGHT)
	right_rect.position = Vector2(-wall_thickness / 2.0, -VERTICAL_SHAFT_HEIGHT / 2.0)
	right_rect.color = wall_color
	right_wall.add_child(right_rect)
	platforms_container.add_child(right_wall)

	# Entry platform at bottom of shaft
	_create_platform(Vector2(shaft_x, shaft_bottom + 10.0), VERTICAL_SHAFT_WIDTH + 40.0)

	# Exit platform at top of shaft
	_create_platform(Vector2(shaft_x, shaft_top - 10.0), VERTICAL_SHAFT_WIDTH + 40.0)

	# Muffins along the shaft to reward wall-jumping
	var muffin_steps: int = 5
	var muffin_v_spacing: float = VERTICAL_SHAFT_HEIGHT / (muffin_steps + 1)
	for m in range(muffin_steps):
		var muffin_y: float = shaft_bottom - (m + 1) * muffin_v_spacing
		# Alternate muffins left and right inside the shaft
		var muffin_x: float = shaft_x
		if m % 2 == 0:
			muffin_x = shaft_x - half_shaft_w * 0.4
		else:
			muffin_x = shaft_x + half_shaft_w * 0.4
		_spawn_muffin(Vector2(muffin_x, muffin_y))


# -- Muffin / Enemy / Trap Spawning -------------------------------------------

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

		# Build weighted trap table based on tower_id
		var trap_table: Array[Dictionary] = []

		# Original traps - all towers
		trap_table.append({"scene": SPIKES_SCENE, "weight": 12, "type": "spikes"})
		trap_table.append({"scene": ARROW_TRAP_SCENE, "weight": 10, "type": "arrow"})
		trap_table.append({"scene": PENDULUM_SCENE, "weight": 8, "type": "pendulum"})
		trap_table.append({"scene": LAVA_POOL_SCENE, "weight": 8, "type": "lava_pool"})
		trap_table.append({"scene": WIND_GUST_SCENE, "weight": 6, "type": "wind"})
		trap_table.append({"scene": FALLING_ROCKS_SCENE, "weight": 6, "type": "rocks"})

		# New traps - all towers
		trap_table.append({"scene": BOUNCE_PAD_SCENE, "weight": 10, "type": "bounce"})
		trap_table.append({"scene": CRYSTAL_BARRIER_SCENE, "weight": 6, "type": "barrier"})
		trap_table.append({"scene": CRUMBLE_FLOOR_SCENE, "weight": 8, "type": "crumble"})
		trap_table.append({"scene": POPCORN_GEYSER_SCENE, "weight": 7, "type": "geyser"})

		# Tower 2+ traps
		if tower_id >= 2:
			trap_table.append({"scene": SAW_BLADE_SCENE, "weight": 7, "type": "saw"})
			trap_table.append({"scene": ICING_WATERFALL_SCENE, "weight": 6, "type": "waterfall"})
			trap_table.append({"scene": FROSTING_SLIDE_SCENE, "weight": 6, "type": "slide"})
			trap_table.append({"scene": CARAMEL_ZONE_SCENE, "weight": 5, "type": "caramel"})

		# Tower 3+ traps
		if tower_id >= 3:
			trap_table.append({"scene": SPRINKLE_MINE_SCENE, "weight": 5, "type": "mine"})

		# Calculate total weight
		var total_weight: int = 0
		for entry: Dictionary in trap_table:
			total_weight += entry["weight"] as int

		# Roll weighted random
		var weight_roll: int = randi_range(0, total_weight - 1)
		var accumulated: int = 0
		var chosen_type: String = "spikes"
		var chosen_scene: String = SPIKES_SCENE
		for entry: Dictionary in trap_table:
			accumulated += entry["weight"] as int
			if weight_roll < accumulated:
				chosen_type = entry["type"] as String
				chosen_scene = entry["scene"] as String
				break

		# Spawn the chosen trap with appropriate positioning
		match chosen_type:
			"spikes":
				_spawn_trap(chosen_scene, Vector2(x_offset, y_pos - 16))
			"arrow":
				var wall_x: float = 15.0 if randf() > 0.5 else TOWER_WIDTH - 15.0
				var facing_right: bool = wall_x < TOWER_WIDTH / 2.0
				_spawn_arrow_trap(Vector2(wall_x, y_pos - 30), facing_right)
			"pendulum":
				_spawn_trap(chosen_scene, Vector2(x_offset, y_pos - vertical_spacing * 0.5))
			"lava_pool":
				_spawn_trap(chosen_scene, Vector2(x_offset, y_pos + 8))
			"wind":
				var wind_dir: float = 1.0 if randf() > 0.5 else -1.0
				_spawn_wind_gust(Vector2(x_offset, y_pos - 40), wind_dir)
			"rocks":
				_spawn_trap(chosen_scene, Vector2(x_offset, y_pos - vertical_spacing * 0.7))
			"bounce":
				_spawn_trap(chosen_scene, Vector2(x_offset, y_pos - 12))
			"barrier":
				_spawn_trap(chosen_scene, Vector2(x_offset + 40.0, y_pos - 48))
			"crumble":
				_spawn_trap(chosen_scene, Vector2(x_offset, y_pos))
			"geyser":
				_spawn_trap(chosen_scene, Vector2(x_offset, y_pos))
			"saw":
				_spawn_trap(chosen_scene, Vector2(x_offset, y_pos - vertical_spacing * 0.4))
			"waterfall":
				_spawn_trap(chosen_scene, Vector2(x_offset, y_pos - 60))
			"slide":
				_spawn_trap(chosen_scene, Vector2(x_offset - 30.0, y_pos))
			"caramel":
				_spawn_trap(chosen_scene, Vector2(x_offset, y_pos + 4))
			"mine":
				_spawn_trap(chosen_scene, Vector2(x_offset + randf_range(-20.0, 20.0), y_pos - 8))

	# Tower 3+ gets rising chocolate lava at the bottom
	if tower_id >= 3:
		var lava_scene := load(RISING_LAVA_SCENE)
		if lava_scene:
			var lava: Node2D = lava_scene.instantiate()
			lava.position = Vector2(TOWER_WIDTH / 2.0, TOWER_HEIGHT - 10)
			if "tower_height" in lava:
				lava.tower_height = TOWER_HEIGHT
			if "lava_width" in lava:
				lava.lava_width = TOWER_WIDTH
			traps_container.add_child(lava)

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
	_spawn_random_enemy(pos, patrol_dist)


func _spawn_random_enemy(pos: Vector2, patrol_dist: float) -> void:
	var scene_path: String = ""
	var muffin_drop_count: int = 3
	var roll: float = randf()

	match tower_id:
		1:
			# Tower 1: skeleton, bat, peppermint roller
			if roll < 0.45:
				scene_path = SKELETON_SCENE_PATH
			elif roll < 0.75:
				scene_path = FAIRY_CAKE_BAT_SCENE_PATH
				muffin_drop_count = 2
			else:
				scene_path = PEPPERMINT_ROLLER_SCENE_PATH
				muffin_drop_count = 2
		2:
			# Tower 2: + archer, cupcake bomber, marshmallow blob
			if roll < 0.20:
				scene_path = SKELETON_SCENE_PATH
			elif roll < 0.35:
				scene_path = FAIRY_CAKE_BAT_SCENE_PATH
				muffin_drop_count = 2
			elif roll < 0.50:
				scene_path = PEPPERMINT_ROLLER_SCENE_PATH
				muffin_drop_count = 2
			elif roll < 0.65:
				scene_path = COOKIE_ARCHER_SCENE_PATH
				muffin_drop_count = 2
			elif roll < 0.80:
				scene_path = CUPCAKE_BOMBER_SCENE_PATH
				muffin_drop_count = 3
			else:
				scene_path = MARSHMALLOW_BLOB_SCENE_PATH
				muffin_drop_count = 3
		3:
			# Tower 3: + golem, candy corn, wafer shield, gummy bear, licorice whip
			if roll < 0.10:
				scene_path = SKELETON_SCENE_PATH
			elif roll < 0.18:
				scene_path = FAIRY_CAKE_BAT_SCENE_PATH
				muffin_drop_count = 2
			elif roll < 0.26:
				scene_path = PEPPERMINT_ROLLER_SCENE_PATH
				muffin_drop_count = 2
			elif roll < 0.34:
				scene_path = COOKIE_ARCHER_SCENE_PATH
				muffin_drop_count = 2
			elif roll < 0.42:
				scene_path = CUPCAKE_BOMBER_SCENE_PATH
				muffin_drop_count = 3
			elif roll < 0.50:
				scene_path = MARSHMALLOW_BLOB_SCENE_PATH
				muffin_drop_count = 3
			elif roll < 0.60:
				scene_path = CANDY_GOLEM_SCENE_PATH
				muffin_drop_count = 5
			elif roll < 0.70:
				scene_path = CANDY_CORN_SCENE_PATH
				muffin_drop_count = 3
			elif roll < 0.80:
				scene_path = WAFER_SHIELD_SCENE_PATH
				muffin_drop_count = 4
			elif roll < 0.90:
				scene_path = GUMMY_BEAR_SCENE_PATH
				muffin_drop_count = 5
			else:
				scene_path = LICORICE_WHIP_SCENE_PATH
				muffin_drop_count = 4
		_:
			# Tower 4+: everything including jellybean sniper
			if roll < 0.06:
				scene_path = SKELETON_SCENE_PATH
			elif roll < 0.12:
				scene_path = FAIRY_CAKE_BAT_SCENE_PATH
				muffin_drop_count = 2
			elif roll < 0.18:
				scene_path = PEPPERMINT_ROLLER_SCENE_PATH
				muffin_drop_count = 2
			elif roll < 0.24:
				scene_path = COOKIE_ARCHER_SCENE_PATH
				muffin_drop_count = 2
			elif roll < 0.30:
				scene_path = CUPCAKE_BOMBER_SCENE_PATH
				muffin_drop_count = 3
			elif roll < 0.36:
				scene_path = MARSHMALLOW_BLOB_SCENE_PATH
				muffin_drop_count = 3
			elif roll < 0.44:
				scene_path = CANDY_GOLEM_SCENE_PATH
				muffin_drop_count = 5
			elif roll < 0.52:
				scene_path = CANDY_CORN_SCENE_PATH
				muffin_drop_count = 3
			elif roll < 0.60:
				scene_path = WAFER_SHIELD_SCENE_PATH
				muffin_drop_count = 4
			elif roll < 0.68:
				scene_path = GUMMY_BEAR_SCENE_PATH
				muffin_drop_count = 5
			elif roll < 0.76:
				scene_path = LICORICE_WHIP_SCENE_PATH
				muffin_drop_count = 4
			elif roll < 0.84:
				scene_path = SPRINKLE_SWARM_SCENE_PATH
				muffin_drop_count = 1
			else:
				scene_path = JELLYBEAN_SNIPER_SCENE_PATH
				muffin_drop_count = 2

	# Handle sprinkle swarm spawning (4-6 individuals)
	if scene_path == SPRINKLE_SWARM_SCENE_PATH:
		var swarm_count: int = randi_range(4, 6)
		for i in range(swarm_count):
			var offset := Vector2(randf_range(-20, 20), randf_range(-5, 5))
			var enemy_scene := load(scene_path)
			if enemy_scene:
				var enemy: CharacterBody2D = enemy_scene.instantiate()
				enemy.position = pos + offset
				enemy.set_patrol_distance(patrol_dist)
				enemy.died.connect(_on_enemy_died.bind(muffin_drop_count))
				enemies_container.add_child(enemy)
		return

	var enemy_scene := load(scene_path)
	if enemy_scene:
		var enemy: CharacterBody2D = enemy_scene.instantiate()
		enemy.position = pos
		enemy.set_patrol_distance(patrol_dist)
		enemy.died.connect(_on_enemy_died.bind(muffin_drop_count))
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


func _on_enemy_died(pos: Vector2, muffin_count: int = 3) -> void:
	_enemies_killed += 1
	# Drop muffins at enemy death position.
	for i in range(muffin_count):
		var offset := Vector2(randf_range(-20, 20), randf_range(-10, 10))
		_spawn_muffin(pos + offset)


func _on_exit_door_entered(body: Node2D) -> void:
	if _exiting:
		return
	if not ("player_index" in body or body.has_meta("player_index")):
		return

	_exiting = true
	tower_cleared.emit(tower_id)

	# Auto-save profiles on tower clear
	ProfileManager.auto_save()

	# Go to boss fight!
	GameManager.go_to_boss(tower_id)


func _update_muffin_counter() -> void:
	if muffin_counter_label:
		muffin_counter_label.text = "Muffins: %d / %d" % [_muffins_collected, _muffins_total]


# -- Mini-boss System ----------------------------------------------------------

func _setup_miniboss_trigger() -> void:
	var mid_y: float = TOWER_HEIGHT * 0.5
	_miniboss_trigger = Area2D.new()
	_miniboss_trigger.position = Vector2(TOWER_WIDTH / 2.0, mid_y)
	_miniboss_trigger.collision_layer = 0
	_miniboss_trigger.collision_mask = 2  # Detect players

	var trigger_shape := CollisionShape2D.new()
	var trigger_rect := RectangleShape2D.new()
	trigger_rect.size = Vector2(TOWER_WIDTH, 40)
	trigger_shape.shape = trigger_rect
	_miniboss_trigger.add_child(trigger_shape)

	_miniboss_trigger.body_entered.connect(_on_miniboss_trigger_entered)
	add_child(_miniboss_trigger)


func _on_miniboss_trigger_entered(body: Node2D) -> void:
	if _miniboss_active:
		return
	if not ("player_index" in body or body.has_meta("player_index")):
		return

	_miniboss_active = true
	# Disable trigger so it only fires once
	_miniboss_trigger.set_deferred("monitoring", false)

	_spawn_mini_boss(tower_id)


func _spawn_mini_boss(tid: int) -> void:
	var scene_id: int = clampi(tid, 1, 4)
	var scene_path: String = MINIBOSS_SCENES.get(scene_id, "") as String
	if scene_path.is_empty():
		return

	var boss_scene := load(scene_path)
	if not boss_scene:
		return

	var mid_y: float = TOWER_HEIGHT * 0.5

	# Create barrier to block the exit until mini-boss is defeated
	_miniboss_barrier = StaticBody2D.new()
	_miniboss_barrier.position = Vector2(TOWER_WIDTH / 2.0, mid_y - 80.0)
	_miniboss_barrier.collision_layer = 1  # World layer

	var barrier_col := CollisionShape2D.new()
	var barrier_shape := RectangleShape2D.new()
	barrier_shape.size = Vector2(TOWER_WIDTH, 16)
	barrier_col.shape = barrier_shape
	_miniboss_barrier.add_child(barrier_col)

	# Barrier visual
	var barrier_rect := ColorRect.new()
	barrier_rect.size = Vector2(TOWER_WIDTH, 16)
	barrier_rect.position = Vector2(-TOWER_WIDTH / 2.0, -8)
	barrier_rect.color = Color(0.8, 0.2, 0.1, 0.7)
	_miniboss_barrier.add_child(barrier_rect)

	add_child(_miniboss_barrier)

	# Spawn the mini-boss
	var boss: CharacterBody2D = boss_scene.instantiate()
	boss.position = Vector2(TOWER_WIDTH / 2.0, mid_y - 40.0)
	boss.died.connect(_on_miniboss_died)
	enemies_container.add_child(boss)

	AudioManager.play("boss_roar")


func _on_miniboss_died(death_pos: Vector2) -> void:
	_miniboss_active = false

	# Remove barrier
	if _miniboss_barrier and is_instance_valid(_miniboss_barrier):
		var barrier_tween := _miniboss_barrier.create_tween()
		barrier_tween.tween_property(_miniboss_barrier, "modulate:a", 0.0, 0.4)
		barrier_tween.tween_callback(_miniboss_barrier.queue_free)

	# Drop bonus muffins
	for i in range(MINIBOSS_MUFFIN_REWARD):
		var offset := Vector2(randf_range(-30, 30), randf_range(-20, 10))
		_spawn_muffin(death_pos + offset)

	# Fanfare
	AudioManager.play("boss_defeat")
