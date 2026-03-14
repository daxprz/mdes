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
	1: "res://scenes/enemies/cookie_cutter_miniboss.tscn",
	2: "res://scenes/enemies/frosting_fountain_miniboss.tscn",
	3: "res://scenes/enemies/sprinkle_tornado_miniboss.tscn",
	4: "res://scenes/enemies/batter_elemental_miniboss.tscn",
}
const MINIBOSS_MUFFIN_REWARD := 10

@export var tower_id: int = 1

var _muffins_collected := 0
var _muffins_total := 0
var _enemies_killed := 0
var _exiting := false
var _miniboss_active := false
var _miniboss_barrier: StaticBody2D = null
var _miniboss_trigger: Area2D = null

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

	# Set up mini-boss trigger at the midpoint of the tower.
	_setup_miniboss_trigger()

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
