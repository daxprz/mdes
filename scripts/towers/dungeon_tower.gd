extends Node2D

## Tower 2 - A procedural top-down dungeon maze viewed from above.
## Uses recursive backtracker algorithm to generate a maze with rooms,
## enemies, muffins, traps, and a boss room trigger.

signal tower_cleared(tower_id: int)

const GRID_WIDTH := 15
const GRID_HEIGHT := 15
const CELL_SIZE := 64
const MAP_WIDTH: int = GRID_WIDTH * CELL_SIZE   # 960
const MAP_HEIGHT: int = GRID_HEIGHT * CELL_SIZE  # 960

const PLAYER_SCENE := preload("res://scenes/characters/player.tscn")
const MUFFIN_SCENE_PATH := "res://scenes/items/mini_muffin.tscn"
const SKELETON_SCENE_PATH := "res://scenes/enemies/skeleton.tscn"
const SPIKES_SCENE := "res://scenes/traps/spikes.tscn"
const LAVA_POOL_SCENE := "res://scenes/traps/lava_pool.tscn"

# Cell types for the grid
enum Cell { WALL, FLOOR, DOOR }

# Room types
enum RoomType { START, BOSS, TREASURE, ENEMY, TRAP }

var tower_id: int = 2
var _grid: Array = []  # 2D array [y][x] of Cell values
var _rooms: Array = []  # Array of Dictionaries: { pos: Vector2i, size: Vector2i, type: RoomType }
var _muffins_collected: int = 0
var _muffins_total: int = 0
var _enemies_killed: int = 0
var _exiting: bool = false

var _walls_container: Node2D = null
var _floors_container: Node2D = null
var _enemies_container: Node2D = null
var _muffins_container: Node2D = null
var _traps_container: Node2D = null
var _fog_container: Node2D = null
var _ui_layer: CanvasLayer = null
var _muffin_counter_label: Label = null
var _tower_label: Label = null


func _ready() -> void:
	GameManager.change_state(GameManager.GameState.TOWER)
	tower_id = GameManager.current_tower_id
	PlayerManager.player_joined.connect(_on_player_joined_midgame)

	_create_containers()
	_create_ui()
	_generate_dungeon()
	_spawn_players()
	_update_muffin_counter()


func _create_containers() -> void:
	_floors_container = Node2D.new()
	_floors_container.name = "Floors"
	_floors_container.z_index = -5
	add_child(_floors_container)

	_walls_container = Node2D.new()
	_walls_container.name = "Walls"
	add_child(_walls_container)

	_enemies_container = Node2D.new()
	_enemies_container.name = "Enemies"
	add_child(_enemies_container)

	_muffins_container = Node2D.new()
	_muffins_container.name = "Muffins"
	add_child(_muffins_container)

	_traps_container = Node2D.new()
	_traps_container.name = "Traps"
	add_child(_traps_container)

	_fog_container = Node2D.new()
	_fog_container.name = "Fog"
	_fog_container.z_index = 5
	add_child(_fog_container)


func _create_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "UI"
	_ui_layer.layer = 10
	add_child(_ui_layer)

	_muffin_counter_label = Label.new()
	_muffin_counter_label.name = "MuffinCounter"
	_muffin_counter_label.position = Vector2(10, 10)
	_muffin_counter_label.add_theme_font_size_override("font_size", 18)
	_muffin_counter_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
	_ui_layer.add_child(_muffin_counter_label)

	_tower_label = Label.new()
	_tower_label.name = "TowerLabel"
	_tower_label.text = "Tower 2 - Dungeon"
	_tower_label.position = Vector2(10, 36)
	_tower_label.add_theme_font_size_override("font_size", 14)
	_tower_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	_ui_layer.add_child(_tower_label)


# =============================================================================
# Dungeon Generation
# =============================================================================

func _generate_dungeon() -> void:
	# Create background
	var bg := ColorRect.new()
	bg.size = Vector2(MAP_WIDTH, MAP_HEIGHT)
	bg.position = Vector2.ZERO
	bg.color = Color(0.05, 0.05, 0.08)
	bg.z_index = -10
	add_child(bg)
	move_child(bg, 0)

	# Step 1: Initialize grid with all walls
	_init_grid()

	# Step 2: Generate maze using recursive backtracker
	_generate_maze()

	# Step 3: Carve rooms
	_create_rooms()

	# Step 4: Build the visual/physical dungeon from the grid
	_build_dungeon_visuals()

	# Step 5: Place content in rooms
	_populate_rooms()

	# Step 6: Scatter muffins in corridors
	_scatter_corridor_muffins()

	# Step 7: Create fog of war
	_create_fog_of_war()


func _init_grid() -> void:
	_grid.clear()
	for y in range(GRID_HEIGHT):
		var row: Array = []
		for x in range(GRID_WIDTH):
			row.append(Cell.WALL)
		_grid.append(row)


func _generate_maze() -> void:
	# Recursive backtracker (DFS with stack)
	# We work on odd-numbered cells only so walls exist between them
	var visited: Dictionary = {}
	var stack: Array[Vector2i] = []

	# Start from cell (1, 1)
	var start := Vector2i(1, 1)
	visited[start] = true
	_grid[start.y][start.x] = Cell.FLOOR
	stack.push_back(start)

	while not stack.is_empty():
		var current: Vector2i = stack.back()
		var neighbors: Array[Vector2i] = _get_unvisited_neighbors(current, visited)

		if neighbors.is_empty():
			stack.pop_back()
		else:
			var chosen: Vector2i = neighbors[randi() % neighbors.size()]
			# Remove wall between current and chosen
			var wall_pos := Vector2i(
				(current.x + chosen.x) / 2,
				(current.y + chosen.y) / 2
			)
			_grid[wall_pos.y][wall_pos.x] = Cell.FLOOR
			_grid[chosen.y][chosen.x] = Cell.FLOOR
			visited[chosen] = true
			stack.push_back(chosen)


func _get_unvisited_neighbors(cell: Vector2i, visited: Dictionary) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	var directions: Array[Vector2i] = [
		Vector2i(0, -2),  # Up
		Vector2i(0, 2),   # Down
		Vector2i(-2, 0),  # Left
		Vector2i(2, 0),   # Right
	]
	for dir in directions:
		var neighbor: Vector2i = cell + dir
		if neighbor.x >= 1 and neighbor.x < GRID_WIDTH - 1 and \
		   neighbor.y >= 1 and neighbor.y < GRID_HEIGHT - 1 and \
		   not visited.has(neighbor):
			neighbors.append(neighbor)
	return neighbors


func _create_rooms() -> void:
	_rooms.clear()

	# Start room: top-left area
	var start_room: Dictionary = {
		"pos": Vector2i(1, 1),
		"size": Vector2i(3, 3),
		"type": RoomType.START,
	}
	_rooms.append(start_room)
	_carve_room(start_room)

	# Boss room: placed far from start (bottom-right area)
	var boss_candidates: Array[Vector2i] = []
	for attempt in range(50):
		var bx: int = randi_range(GRID_WIDTH - 5, GRID_WIDTH - 2)
		var by: int = randi_range(GRID_HEIGHT - 5, GRID_HEIGHT - 2)
		# Ensure it fits and is far enough from start
		if bx + 3 < GRID_WIDTH and by + 3 < GRID_HEIGHT:
			var dist: int = absi(bx - 1) + absi(by - 1)
			if dist >= 8:
				boss_candidates.append(Vector2i(bx, by))
				break

	var boss_pos: Vector2i = Vector2i(GRID_WIDTH - 5, GRID_HEIGHT - 5)
	if not boss_candidates.is_empty():
		boss_pos = boss_candidates[0]

	var boss_room: Dictionary = {
		"pos": boss_pos,
		"size": Vector2i(4, 4),
		"type": RoomType.BOSS,
	}
	_rooms.append(boss_room)
	_carve_room(boss_room)

	# Generate 5-8 additional rooms: treasure, enemy, trap
	var extra_room_count: int = randi_range(5, 8)
	var room_types_pool: Array[int] = [
		RoomType.TREASURE, RoomType.TREASURE,
		RoomType.ENEMY, RoomType.ENEMY, RoomType.ENEMY,
		RoomType.TRAP, RoomType.TRAP, RoomType.TRAP,
	]

	for i in range(extra_room_count):
		var room_placed: bool = false
		for attempt in range(30):
			var rw: int = randi_range(3, 4)
			var rh: int = randi_range(3, 4)
			var rx: int = randi_range(1, GRID_WIDTH - rw - 1)
			var ry: int = randi_range(1, GRID_HEIGHT - rh - 1)

			if _can_place_room(Vector2i(rx, ry), Vector2i(rw, rh)):
				var rtype: int = room_types_pool[i % room_types_pool.size()]
				var room: Dictionary = {
					"pos": Vector2i(rx, ry),
					"size": Vector2i(rw, rh),
					"type": rtype,
				}
				_rooms.append(room)
				_carve_room(room)
				room_placed = true
				break

		if not room_placed:
			continue


func _can_place_room(pos: Vector2i, room_size: Vector2i) -> bool:
	# Check the room doesn't go out of bounds
	if pos.x + room_size.x >= GRID_WIDTH - 1 or pos.y + room_size.y >= GRID_HEIGHT - 1:
		return false
	if pos.x < 1 or pos.y < 1:
		return false

	# Check it doesn't overlap with existing rooms (with 1-cell padding)
	for room: Dictionary in _rooms:
		var rpos: Vector2i = room["pos"] as Vector2i
		var rsize: Vector2i = room["size"] as Vector2i
		if pos.x < rpos.x + rsize.x + 1 and pos.x + room_size.x + 1 > rpos.x and \
		   pos.y < rpos.y + rsize.y + 1 and pos.y + room_size.y + 1 > rpos.y:
			return false
	return true


func _carve_room(room: Dictionary) -> void:
	var pos: Vector2i = room["pos"] as Vector2i
	var room_size: Vector2i = room["size"] as Vector2i
	for y in range(pos.y, pos.y + room_size.y):
		for x in range(pos.x, pos.x + room_size.x):
			if x >= 0 and x < GRID_WIDTH and y >= 0 and y < GRID_HEIGHT:
				_grid[y][x] = Cell.FLOOR

	# Ensure room connects to adjacent corridors by carving doorways
	# Try each edge of the room to find and create connections
	_ensure_room_connection(room)


func _ensure_room_connection(room: Dictionary) -> void:
	var pos: Vector2i = room["pos"] as Vector2i
	var room_size: Vector2i = room["size"] as Vector2i

	# Try to connect on each side
	var connected: bool = false

	# Top edge
	for x in range(pos.x, pos.x + room_size.x):
		if pos.y - 1 >= 0 and pos.y - 2 >= 0:
			if _grid[pos.y - 2][x] == Cell.FLOOR:
				_grid[pos.y - 1][x] = Cell.DOOR
				connected = true
				break

	# Bottom edge
	for x in range(pos.x, pos.x + room_size.x):
		var bottom_y: int = pos.y + room_size.y
		if bottom_y < GRID_HEIGHT and bottom_y + 1 < GRID_HEIGHT:
			if _grid[bottom_y + 1][x] == Cell.FLOOR:
				_grid[bottom_y][x] = Cell.DOOR
				connected = true
				break

	# Left edge
	for y in range(pos.y, pos.y + room_size.y):
		if pos.x - 1 >= 0 and pos.x - 2 >= 0:
			if _grid[y][pos.x - 2] == Cell.FLOOR:
				_grid[y][pos.x - 1] = Cell.DOOR
				connected = true
				break

	# Right edge
	for y in range(pos.y, pos.y + room_size.y):
		var right_x: int = pos.x + room_size.x
		if right_x < GRID_WIDTH and right_x + 1 < GRID_WIDTH:
			if _grid[y][right_x + 1] == Cell.FLOOR:
				_grid[y][right_x] = Cell.DOOR
				connected = true
				break

	# If no natural connection found, force a corridor to the nearest floor cell
	if not connected:
		var center: Vector2i = pos + room_size / 2
		# Carve a path left until we hit a floor
		var cx: int = pos.x - 1
		while cx >= 0:
			if _grid[center.y][cx] == Cell.FLOOR:
				# Carve from cx+1 to pos.x-1
				for fill_x in range(cx + 1, pos.x):
					_grid[center.y][fill_x] = Cell.FLOOR
				break
			cx -= 1


# =============================================================================
# Visual Construction
# =============================================================================

func _build_dungeon_visuals() -> void:
	for y in range(GRID_HEIGHT):
		for x in range(GRID_WIDTH):
			var world_pos: Vector2 = Vector2(x * CELL_SIZE, y * CELL_SIZE)
			var cell_type: int = _grid[y][x] as int

			if cell_type == Cell.WALL:
				_create_wall(world_pos, x, y)
			elif cell_type == Cell.FLOOR:
				_create_floor(world_pos, false)
			elif cell_type == Cell.DOOR:
				_create_floor(world_pos, true)


func _create_wall(pos: Vector2, gx: int, gy: int) -> void:
	var wall := StaticBody2D.new()
	wall.position = pos + Vector2(CELL_SIZE / 2.0, CELL_SIZE / 2.0)
	wall.collision_layer = 1

	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(CELL_SIZE, CELL_SIZE)
	col.shape = shape
	wall.add_child(col)

	var rect := ColorRect.new()
	rect.size = Vector2(CELL_SIZE, CELL_SIZE)
	rect.position = Vector2(-CELL_SIZE / 2.0, -CELL_SIZE / 2.0)

	# Vary wall color slightly for visual interest
	var base_color := Color(0.3, 0.25, 0.2)
	var variation: float = (sin(float(gx) * 3.7 + float(gy) * 2.3) + 1.0) * 0.05
	rect.color = Color(
		base_color.r + variation,
		base_color.g + variation * 0.8,
		base_color.b + variation * 0.5
	)
	wall.add_child(rect)

	_walls_container.add_child(wall)


func _create_floor(pos: Vector2, is_door: bool) -> void:
	var rect := ColorRect.new()
	rect.size = Vector2(CELL_SIZE, CELL_SIZE)
	rect.position = pos

	if is_door:
		rect.color = Color(0.2, 0.18, 0.22)
	else:
		rect.color = Color(0.12, 0.11, 0.14)

	_floors_container.add_child(rect)


# =============================================================================
# Room Population
# =============================================================================

func _populate_rooms() -> void:
	for room: Dictionary in _rooms:
		var rtype: int = room["type"] as int
		var pos: Vector2i = room["pos"] as Vector2i
		var room_size: Vector2i = room["size"] as Vector2i
		var center: Vector2 = Vector2(
			(pos.x + room_size.x / 2.0) * CELL_SIZE,
			(pos.y + room_size.y / 2.0) * CELL_SIZE
		)

		match rtype:
			RoomType.START:
				# Mark start room floor with a slightly lighter color
				_highlight_room(room, Color(0.15, 0.18, 0.12))

			RoomType.BOSS:
				_create_boss_room(room, center)

			RoomType.TREASURE:
				_populate_treasure_room(room, center)

			RoomType.ENEMY:
				_populate_enemy_room(room, center)

			RoomType.TRAP:
				_populate_trap_room(room, center)


func _highlight_room(room: Dictionary, color: Color) -> void:
	var pos: Vector2i = room["pos"] as Vector2i
	var room_size: Vector2i = room["size"] as Vector2i
	for y in range(pos.y, pos.y + room_size.y):
		for x in range(pos.x, pos.x + room_size.x):
			var highlight := ColorRect.new()
			highlight.size = Vector2(CELL_SIZE, CELL_SIZE)
			highlight.position = Vector2(x * CELL_SIZE, y * CELL_SIZE)
			highlight.color = color
			highlight.z_index = -4
			_floors_container.add_child(highlight)


func _create_boss_room(room: Dictionary, center: Vector2) -> void:
	# Highlight boss room with dark red tint
	_highlight_room(room, Color(0.2, 0.08, 0.08))

	# Boss room door visual: gold/red label
	var pos: Vector2i = room["pos"] as Vector2i
	var room_size: Vector2i = room["size"] as Vector2i

	# Gold border markers on the floor edges of the boss room
	for x in range(pos.x, pos.x + room_size.x):
		var top_marker := ColorRect.new()
		top_marker.size = Vector2(CELL_SIZE, 4)
		top_marker.position = Vector2(x * CELL_SIZE, pos.y * CELL_SIZE)
		top_marker.color = Color(0.85, 0.65, 0.1)
		top_marker.z_index = -3
		_floors_container.add_child(top_marker)

		var bottom_marker := ColorRect.new()
		bottom_marker.size = Vector2(CELL_SIZE, 4)
		bottom_marker.position = Vector2(x * CELL_SIZE, (pos.y + room_size.y) * CELL_SIZE - 4)
		bottom_marker.color = Color(0.85, 0.65, 0.1)
		bottom_marker.z_index = -3
		_floors_container.add_child(bottom_marker)

	for y in range(pos.y, pos.y + room_size.y):
		var left_marker := ColorRect.new()
		left_marker.size = Vector2(4, CELL_SIZE)
		left_marker.position = Vector2(pos.x * CELL_SIZE, y * CELL_SIZE)
		left_marker.color = Color(0.85, 0.65, 0.1)
		left_marker.z_index = -3
		_floors_container.add_child(left_marker)

		var right_marker := ColorRect.new()
		right_marker.size = Vector2(4, CELL_SIZE)
		right_marker.position = Vector2((pos.x + room_size.x) * CELL_SIZE - 4, y * CELL_SIZE)
		right_marker.color = Color(0.85, 0.65, 0.1)
		right_marker.z_index = -3
		_floors_container.add_child(right_marker)

	# BOSS label
	var boss_label := Label.new()
	boss_label.text = "BOSS"
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_label.position = center - Vector2(30, 40)
	boss_label.add_theme_font_size_override("font_size", 16)
	boss_label.add_theme_color_override("font_color", Color(0.9, 0.2, 0.1))
	boss_label.z_index = 2
	add_child(boss_label)

	# Boss room trigger Area2D
	var trigger := Area2D.new()
	trigger.name = "BossRoomTrigger"
	trigger.position = center
	trigger.collision_layer = 0
	trigger.collision_mask = 2  # Detect players

	var trigger_shape := CollisionShape2D.new()
	var trigger_rect := RectangleShape2D.new()
	trigger_rect.size = Vector2(room_size.x * CELL_SIZE - 16, room_size.y * CELL_SIZE - 16)
	trigger_shape.shape = trigger_rect
	trigger.add_child(trigger_shape)

	trigger.body_entered.connect(_on_boss_room_entered)
	add_child(trigger)


func _populate_treasure_room(room: Dictionary, center: Vector2) -> void:
	_highlight_room(room, Color(0.18, 0.16, 0.08))
	var room_size: Vector2i = room["size"] as Vector2i

	# Place 5-8 muffins in the treasure room
	var muffin_count: int = randi_range(5, 8)
	for i in range(muffin_count):
		var offset: Vector2 = Vector2(
			randf_range(-room_size.x * CELL_SIZE * 0.3, room_size.x * CELL_SIZE * 0.3),
			randf_range(-room_size.y * CELL_SIZE * 0.3, room_size.y * CELL_SIZE * 0.3)
		)
		_spawn_muffin(center + offset)


func _populate_enemy_room(room: Dictionary, center: Vector2) -> void:
	_highlight_room(room, Color(0.18, 0.1, 0.1))
	var room_size: Vector2i = room["size"] as Vector2i

	# Place 2-4 enemies in the room
	var enemy_count: int = randi_range(2, 4)
	for i in range(enemy_count):
		var offset: Vector2 = Vector2(
			randf_range(-room_size.x * CELL_SIZE * 0.3, room_size.x * CELL_SIZE * 0.3),
			randf_range(-room_size.y * CELL_SIZE * 0.3, room_size.y * CELL_SIZE * 0.3)
		)
		_spawn_enemy(center + offset)

	# Also place a muffin reward
	_spawn_muffin(center)


func _populate_trap_room(room: Dictionary, center: Vector2) -> void:
	_highlight_room(room, Color(0.15, 0.08, 0.15))
	var room_size: Vector2i = room["size"] as Vector2i

	# Place 2-3 traps
	var trap_count: int = randi_range(2, 3)
	for i in range(trap_count):
		var offset: Vector2 = Vector2(
			randf_range(-room_size.x * CELL_SIZE * 0.25, room_size.x * CELL_SIZE * 0.25),
			randf_range(-room_size.y * CELL_SIZE * 0.25, room_size.y * CELL_SIZE * 0.25)
		)
		var trap_scene_path: String = SPIKES_SCENE if randf() < 0.6 else LAVA_POOL_SCENE
		_spawn_trap(trap_scene_path, center + offset)

	# A muffin as bait
	_spawn_muffin(center)


# =============================================================================
# Corridor Content
# =============================================================================

func _scatter_corridor_muffins() -> void:
	# Place 15-20 muffins in corridor floor tiles
	var floor_cells: Array[Vector2i] = []
	for y in range(GRID_HEIGHT):
		for x in range(GRID_WIDTH):
			if _grid[y][x] == Cell.FLOOR and not _is_in_any_room(Vector2i(x, y)):
				floor_cells.append(Vector2i(x, y))

	floor_cells.shuffle()
	var muffin_count: int = mini(randi_range(15, 20), floor_cells.size())
	var enemies_to_place: int = randi_range(8, 12)
	var enemies_placed: int = 0

	for i in range(muffin_count):
		var cell: Vector2i = floor_cells[i]
		var world_pos: Vector2 = Vector2(
			cell.x * CELL_SIZE + CELL_SIZE / 2.0,
			cell.y * CELL_SIZE + CELL_SIZE / 2.0
		)
		_spawn_muffin(world_pos)

	# Also place corridor enemies
	for i in range(muffin_count, floor_cells.size()):
		if enemies_placed >= enemies_to_place:
			break
		var cell: Vector2i = floor_cells[i]
		var world_pos: Vector2 = Vector2(
			cell.x * CELL_SIZE + CELL_SIZE / 2.0,
			cell.y * CELL_SIZE + CELL_SIZE / 2.0
		)
		_spawn_enemy(world_pos)
		enemies_placed += 1


func _is_in_any_room(cell: Vector2i) -> bool:
	for room: Dictionary in _rooms:
		var pos: Vector2i = room["pos"] as Vector2i
		var room_size: Vector2i = room["size"] as Vector2i
		if cell.x >= pos.x and cell.x < pos.x + room_size.x and \
		   cell.y >= pos.y and cell.y < pos.y + room_size.y:
			return true
	return false


# =============================================================================
# Fog of War
# =============================================================================

func _create_fog_of_war() -> void:
	# Create dark overlay rectangles for each cell; they fade when players get close
	for y in range(GRID_HEIGHT):
		for x in range(GRID_WIDTH):
			if _grid[y][x] == Cell.WALL:
				continue
			var fog := ColorRect.new()
			fog.size = Vector2(CELL_SIZE, CELL_SIZE)
			fog.position = Vector2(x * CELL_SIZE, y * CELL_SIZE)
			fog.color = Color(0.0, 0.0, 0.0, 0.85)
			fog.name = "Fog_%d_%d" % [x, y]
			fog.set_meta("grid_x", x)
			fog.set_meta("grid_y", y)
			_fog_container.add_child(fog)


func _process(_delta: float) -> void:
	_update_fog_of_war()


func _update_fog_of_war() -> void:
	if not is_instance_valid(_fog_container):
		return

	var players: Array[Node] = get_tree().get_nodes_in_group("players")
	if players.is_empty():
		return

	for fog_node in _fog_container.get_children():
		if not fog_node is ColorRect:
			continue
		var fog_rect: ColorRect = fog_node as ColorRect
		var gx: int = fog_rect.get_meta("grid_x") as int
		var gy: int = fog_rect.get_meta("grid_y") as int
		var fog_center: Vector2 = Vector2(
			gx * CELL_SIZE + CELL_SIZE / 2.0,
			gy * CELL_SIZE + CELL_SIZE / 2.0
		)

		var min_dist: float = 99999.0
		for p in players:
			if p is Node2D:
				var dist: float = p.global_position.distance_to(fog_center)
				if dist < min_dist:
					min_dist = dist

		# Reveal radius of ~3 cells (192 pixels), fade between 128-192
		var reveal_radius: float = 192.0
		var fade_start: float = 128.0
		if min_dist <= fade_start:
			fog_rect.color.a = 0.0
		elif min_dist >= reveal_radius:
			fog_rect.color.a = 0.85
		else:
			var t: float = (min_dist - fade_start) / (reveal_radius - fade_start)
			fog_rect.color.a = t * 0.85


# =============================================================================
# Entity Spawning
# =============================================================================

func _spawn_muffin(pos: Vector2) -> void:
	_muffins_total += 1
	var muffin_scene := load(MUFFIN_SCENE_PATH)
	if muffin_scene:
		var muffin: Area2D = muffin_scene.instantiate()
		muffin.position = pos
		muffin.collected.connect(_on_muffin_collected)
		_muffins_container.add_child(muffin)
	else:
		# Fallback placeholder
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
		rect.color = Color(1.0, 0.85, 0.0)
		muffin.add_child(rect)

		_muffins_container.add_child(muffin)


func _spawn_enemy(pos: Vector2) -> void:
	var enemy_scene := load(SKELETON_SCENE_PATH)
	if not enemy_scene:
		return
	var enemy: CharacterBody2D = enemy_scene.instantiate()
	enemy.position = pos
	enemy.set_patrol_distance(40.0)
	enemy.died.connect(_on_enemy_died)
	_enemies_container.add_child(enemy)


func _spawn_trap(scene_path: String, pos: Vector2) -> void:
	var scene := load(scene_path)
	if not scene:
		return
	var trap: Node2D = scene.instantiate()
	trap.position = pos
	_traps_container.add_child(trap)


# =============================================================================
# Player Spawning
# =============================================================================

func _spawn_players() -> void:
	# Spawn in the start room (first room, always at grid 1,1)
	var start_room: Dictionary = _rooms[0]
	var spos: Vector2i = start_room["pos"] as Vector2i
	var ssize: Vector2i = start_room["size"] as Vector2i
	var spawn_center: Vector2 = Vector2(
		(spos.x + ssize.x / 2.0) * CELL_SIZE,
		(spos.y + ssize.y / 2.0) * CELL_SIZE
	)
	var offset_step := Vector2(24, 0)

	for player_index in PlayerManager.players:
		var p_data: Dictionary = PlayerManager.players[player_index]
		if not p_data["is_alive"]:
			continue

		var player_node: CharacterBody2D = PLAYER_SCENE.instantiate()
		player_node.name = "DungeonPlayer_%d" % player_index
		player_node.player_index = player_index
		player_node.device_id = p_data["device_id"]
		player_node.character_class = p_data["character_class"]
		player_node.global_position = spawn_center + offset_step * player_index
		add_child(player_node)

	# Set up multi-player camera
	var multi_cam_script := load("res://scripts/ui/multi_camera.gd")
	var cam := Camera2D.new()
	cam.set_script(multi_cam_script)
	cam.min_zoom = 0.8
	cam.max_zoom = 2.0
	cam.zoom_margin = Vector2(80, 60)
	cam.limit_left = 0
	cam.limit_right = MAP_WIDTH
	cam.limit_top = 0
	cam.limit_bottom = MAP_HEIGHT
	cam.position = spawn_center
	add_child(cam)


func _on_player_joined_midgame(player_index: int) -> void:
	var p_data: Dictionary = PlayerManager.players[player_index]
	var start_room: Dictionary = _rooms[0]
	var spos: Vector2i = start_room["pos"] as Vector2i
	var ssize: Vector2i = start_room["size"] as Vector2i
	var spawn_center: Vector2 = Vector2(
		(spos.x + ssize.x / 2.0) * CELL_SIZE,
		(spos.y + ssize.y / 2.0) * CELL_SIZE
	)

	var player_node: CharacterBody2D = PLAYER_SCENE.instantiate()
	player_node.name = "DungeonPlayer_%d" % player_index
	player_node.player_index = player_index
	player_node.device_id = p_data["device_id"]
	player_node.character_class = p_data["character_class"]
	player_node.global_position = spawn_center + Vector2(24, 0) * player_index
	add_child(player_node)


# =============================================================================
# Callbacks
# =============================================================================

func _on_muffin_collected(_player_index: int) -> void:
	_muffins_collected += 1
	_update_muffin_counter()
	AudioManager.play("muffin_collect")


func _on_enemy_died(pos: Vector2, _muffin_count: int = 3) -> void:
	_enemies_killed += 1
	# Drop muffins at enemy death position
	for i in range(3):
		var offset := Vector2(randf_range(-15, 15), randf_range(-10, 10))
		_spawn_muffin(pos + offset)
	AudioManager.play("enemy_die")


func _on_boss_room_entered(body: Node2D) -> void:
	if _exiting:
		return
	if not ("player_index" in body or body.has_meta("player_index")):
		return

	_exiting = true
	tower_cleared.emit(tower_id)
	ProfileManager.auto_save()
	AudioManager.play("boss_roar")

	# Transition to boss fight (Icing Goblin)
	GameManager.go_to_boss(2)


func _update_muffin_counter() -> void:
	if _muffin_counter_label:
		_muffin_counter_label.text = "Muffins: %d / %d" % [_muffins_collected, _muffins_total]
