extends Node2D

## The overworld valley map. Top-down Zelda-style layout with tower entrances,
## paths, chasms, and ziplines.

const PLAYER_SCENE := preload("res://scenes/characters/player.tscn")
const PATROL_SKELETON_SCENE := preload("res://scenes/enemies/overworld_patrol_skeleton.tscn")

const TOWER_NAMES := {
	1: "tower_1",
	2: "tower_2",
	3: "tower_3",
	4: "tower_final",
}

## Spawn position for players entering the overworld.
const SPAWN_POSITION := Vector2(640, 400)

## How many towers must be completed to unlock the final chasm crossing.
const TOWERS_REQUIRED_FOR_FINAL := 3

## Zipline endpoints: start position -> end position for each tower's zipline.
const ZIPLINE_DATA := {
	1: { "start": Vector2(530, 575), "end": Vector2(530, 595) },
	2: { "start": Vector2(620, 575), "end": Vector2(620, 595) },
	3: { "start": Vector2(710, 575), "end": Vector2(710, 595) },
}

## Signpost info: position offset from tower entrance, text to display.
const SIGNPOST_DATA := {
	1: { "offset": Vector2(50, 20), "text": "Gingerbread Tower - Watch out for cookie bones!" },
	2: { "offset": Vector2(50, -30), "text": "Icing Tower - The floors are slippery..." },
	3: { "offset": Vector2(-50, -30), "text": "Sprinkle Tower - Colors everywhere, danger too!" },
	4: { "offset": Vector2(50, -20), "text": "The Muffin's Lair - Are you ready?" },
}

## Patrol skeleton spawn positions and patrol distances.
const SKELETON_SPAWNS := [
	{ "pos": Vector2(450, 375), "dist": 60.0 },
	{ "pos": Vector2(850, 375), "dist": 70.0 },
	{ "pos": Vector2(640, 300), "dist": 50.0 },
]

var _ziplines_unlocked: Array[int] = []
var _zipline_areas: Dictionary = {}  # tower_id -> Area2D
var _signpost_labels: Dictionary = {}  # tower_id -> Label
var _wave_timer: float = 0.0

@onready var tower_entrance_1: Area2D = $TowerEntrance1
@onready var tower_entrance_2: Area2D = $TowerEntrance2
@onready var tower_entrance_3: Area2D = $TowerEntrance3
@onready var tower_entrance_final: Area2D = $TowerEntranceFinal
@onready var chasm_blocker: StaticBody2D = $ChasmBlocker
@onready var zipline_visual_1: ColorRect = $ZiplineVisual1
@onready var zipline_visual_2: ColorRect = $ZiplineVisual2
@onready var zipline_visual_3: ColorRect = $ZiplineVisual3
@onready var player_spawn_point: Marker2D = $PlayerSpawnPoint


func _ready() -> void:
	GameManager.change_state(GameManager.GameState.OVERWORLD)

	# Allow new players to join mid-game
	PlayerManager.player_joined.connect(_on_player_joined_midgame)

	# Connect tower entrance signals.
	_connect_entrance(tower_entrance_1)
	_connect_entrance(tower_entrance_2)
	_connect_entrance(tower_entrance_3)
	_connect_entrance(tower_entrance_final)

	# Task 2: Add visual boundaries around map edges.
	_create_visual_boundaries()

	# Task 1: Create interactive zipline Area2Ds.
	_create_zipline_areas()

	# Update ziplines/chasms based on completed towers.
	_update_ziplines()

	# Task 4: Create signposts near tower entrances.
	_create_signposts()

	# Task 5: Spawn ambient patrol skeletons.
	_spawn_patrol_skeletons()

	# Spawn players.
	_spawn_players()

	# Replace static camera with multi-player camera
	var old_cam := $Camera2D
	if old_cam:
		old_cam.queue_free()
	var multi_cam_script := load("res://scripts/ui/multi_camera.gd")
	var cam := Camera2D.new()
	cam.set_script(multi_cam_script)
	cam.min_zoom = 0.6
	cam.max_zoom = 1.2
	cam.zoom_margin = Vector2(200, 150)
	cam.position = Vector2(640, 360)
	# Task 3: Camera limits so it stays within map bounds.
	cam.limit_left = 0
	cam.limit_right = 1280
	cam.limit_top = 0
	cam.limit_bottom = 720
	add_child(cam)


func _on_player_joined_midgame(player_index: int) -> void:
	var p_data: Dictionary = PlayerManager.players[player_index]
	var spawn_pos: Vector2 = player_spawn_point.global_position if player_spawn_point else SPAWN_POSITION
	var player_node: CharacterBody2D = PLAYER_SCENE.instantiate()
	player_node.player_index = player_index
	player_node.device_id = p_data["device_id"]
	player_node.character_class = p_data["character_class"]
	player_node.global_position = spawn_pos + Vector2(40, 0) * player_index
	add_child(player_node)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or not event.shift_pressed:
		return
	var key_event: InputEventKey = event as InputEventKey
	# SHIFT+1: complete tower 1
	if key_event.keycode == KEY_1:
		GameManager.mark_tower_completed(TOWER_NAMES[1])
		_update_ziplines()
		_show_cheat_message("Tower 1 completed (cheat)")
	# SHIFT+2: complete tower 2
	elif key_event.keycode == KEY_2:
		GameManager.mark_tower_completed(TOWER_NAMES[2])
		_update_ziplines()
		_show_cheat_message("Tower 2 completed (cheat)")
	# SHIFT+3: complete tower 3
	elif key_event.keycode == KEY_3:
		GameManager.mark_tower_completed(TOWER_NAMES[3])
		_update_ziplines()
		_show_cheat_message("Tower 3 completed (cheat)")
	# SHIFT+4: cycle demolitionist bomb aspect
	elif key_event.keycode == KEY_4:
		var aspects: Array[String] = ["none", "electric", "fire", "impact", "ice"]
		var idx: int = aspects.find(PlayerManager.demo_aspect)
		idx = (idx + 1) % aspects.size()
		PlayerManager.demo_aspect = aspects[idx]
		_show_cheat_message("Demo aspect: " + aspects[idx])


func _show_cheat_message(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(440, 10)
	label.add_theme_font_size_override("font_size", 18)
	label.modulate = Color(1.0, 0.5, 1.0)
	add_child(label)
	AudioManager.play("menu_confirm")
	var tween := create_tween()
	tween.tween_property(label, "modulate:a", 0.0, 2.0)
	tween.tween_callback(label.queue_free)


func _connect_entrance(entrance: Area2D) -> void:
	if entrance and entrance.has_signal("all_players_at_tower"):
		entrance.all_players_at_tower.connect(_on_all_players_at_tower)


func _spawn_players() -> void:
	var spawn_pos: Vector2 = player_spawn_point.global_position if player_spawn_point else SPAWN_POSITION
	var offset_step := Vector2(40, 0)

	for player_index in PlayerManager.players:
		var p_data: Dictionary = PlayerManager.players[player_index]
		if not p_data["is_alive"]:
			continue

		var player_node: CharacterBody2D = PLAYER_SCENE.instantiate()
		player_node.player_index = player_index
		player_node.device_id = p_data["device_id"]
		player_node.character_class = p_data["character_class"]
		player_node.global_position = spawn_pos + offset_step * player_index
		add_child(player_node)


func _on_all_players_at_tower(tower_id: int) -> void:
	# Check if the final tower is accessible.
	if tower_id == 4 and not _is_final_tower_accessible():
		_show_locked_message()
		return

	# Enforce sequential tower progression: Tower 2 requires Tower 1, Tower 3 requires Tower 2.
	if tower_id == 2 and not GameManager.is_tower_completed(TOWER_NAMES[1]):
		_show_prerequisite_message(1)
		return
	if tower_id == 3 and not GameManager.is_tower_completed(TOWER_NAMES[2]):
		_show_prerequisite_message(2)
		return

	# Check if tower is already completed.
	var tower_name: String = TOWER_NAMES.get(tower_id, "")
	if GameManager.is_tower_completed(tower_name):
		_show_completed_message(tower_name)
		return

	# Transition to tower scene.
	GameManager.go_to_tower(tower_id)


func _is_final_tower_accessible() -> bool:
	var count := 0
	for i in [1, 2, 3]:
		if GameManager.is_tower_completed(TOWER_NAMES[i]):
			count += 1
	return count >= TOWERS_REQUIRED_FOR_FINAL


func _update_ziplines() -> void:
	# Show/hide ziplines based on completed towers.
	var zipline_visuals := [zipline_visual_1, zipline_visual_2, zipline_visual_3]
	for i in range(3):
		var tower_id: int = i + 1
		var tower_name: String = TOWER_NAMES[tower_id]
		var completed := GameManager.is_tower_completed(tower_name)
		if zipline_visuals[i]:
			zipline_visuals[i].visible = completed

		# Task 1: Also show/hide the interactive zipline area and its visuals.
		if _zipline_areas.has(tower_id):
			var area: Area2D = _zipline_areas[tower_id]
			area.visible = completed
			area.set_deferred("monitoring", completed)
			# Show/hide cable and post visuals.
			var cable: ColorRect = area.get_meta("cable_node") as ColorRect
			var post_start: ColorRect = area.get_meta("post_start_node") as ColorRect
			var post_end: ColorRect = area.get_meta("post_end_node") as ColorRect
			if cable:
				cable.visible = completed
			if post_start:
				post_start.visible = completed
			if post_end:
				post_end.visible = completed

	# Remove chasm blocker if all 3 towers are done.
	if _is_final_tower_accessible():
		if chasm_blocker:
			chasm_blocker.queue_free()


func _show_locked_message() -> void:
	var label := Label.new()
	label.text = "Complete all 3 towers to cross the chasm!"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(440, 10)
	label.add_theme_font_size_override("font_size", 18)
	label.modulate = Color.YELLOW
	add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "modulate:a", 0.0, 2.0)
	tween.tween_callback(label.queue_free)


func _show_prerequisite_message(required_tower_id: int) -> void:
	var label := Label.new()
	label.text = "Complete Tower %d first!" % required_tower_id
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(460, 10)
	label.add_theme_font_size_override("font_size", 18)
	label.modulate = Color.ORANGE
	add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "modulate:a", 0.0, 2.0)
	tween.tween_callback(label.queue_free)


func _show_completed_message(tower_name: String) -> void:
	var label := Label.new()
	label.text = "%s already completed!" % tower_name.capitalize()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(480, 10)
	label.add_theme_font_size_override("font_size", 18)
	label.modulate = Color.GREEN
	add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "modulate:a", 0.0, 2.0)
	tween.tween_callback(label.queue_free)


func _process(delta: float) -> void:
	# Task 4: Update signpost label visibility based on player proximity.
	_update_signpost_proximity()
	# Task 2: Animate the ocean wave at the bottom edge.
	_animate_ocean_wave(delta)


# =============================================================================
# Task 1: Functional Animated Ziplines
# =============================================================================

func _create_zipline_areas() -> void:
	for tower_id in ZIPLINE_DATA:
		var data: Dictionary = ZIPLINE_DATA[tower_id]
		var start_pos: Vector2 = data["start"]
		var end_pos: Vector2 = data["end"]

		# Create the cable visual (a thin ColorRect line between posts).
		var cable := ColorRect.new()
		cable.name = "ZiplineCable%d" % tower_id
		cable.color = Color(0.45, 0.35, 0.2)
		var cable_length: float = start_pos.distance_to(end_pos)
		cable.size = Vector2(cable_length, 3)
		cable.position = start_pos
		cable.rotation = (end_pos - start_pos).angle()
		cable.visible = false
		add_child(cable)

		# Post visuals at each end of the zipline.
		var post_start := ColorRect.new()
		post_start.name = "ZiplinePostStart%d" % tower_id
		post_start.color = Color(0.35, 0.25, 0.15)
		post_start.size = Vector2(6, 14)
		post_start.position = start_pos - Vector2(3, 7)
		post_start.visible = false
		add_child(post_start)

		var post_end := ColorRect.new()
		post_end.name = "ZiplinePostEnd%d" % tower_id
		post_end.color = Color(0.35, 0.25, 0.15)
		post_end.size = Vector2(6, 14)
		post_end.position = end_pos - Vector2(3, 7)
		post_end.visible = false
		add_child(post_end)

		# Create the Area2D for interaction.
		var area := Area2D.new()
		area.name = "ZiplineArea%d" % tower_id
		area.position = (start_pos + end_pos) / 2.0
		area.collision_layer = 4
		area.collision_mask = 2
		area.monitoring = true
		area.monitorable = false

		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		var half_size: Vector2 = (end_pos - start_pos).abs() / 2.0 + Vector2(16, 16)
		rect.size = half_size * 2.0
		shape.shape = rect
		area.add_child(shape)

		area.set_meta("zipline_start", start_pos)
		area.set_meta("zipline_end", end_pos)
		area.set_meta("zipline_tower_id", tower_id)
		area.set_meta("cable_node", cable)
		area.set_meta("post_start_node", post_start)
		area.set_meta("post_end_node", post_end)

		area.body_entered.connect(_on_zipline_body_entered.bind(area))
		area.visible = false
		add_child(area)
		_zipline_areas[tower_id] = area


func _on_zipline_body_entered(body: Node2D, area: Area2D) -> void:
	if not ("player_index" in body or body.has_meta("player_index")):
		return
	if not area.visible:
		return
	# Tween the player along the zipline path.
	var start_pos: Vector2 = area.get_meta("zipline_start")
	var end_pos: Vector2 = area.get_meta("zipline_end")

	# Determine ride direction based on which end the player is closer to.
	var dist_to_start: float = body.global_position.distance_to(start_pos)
	var dist_to_end: float = body.global_position.distance_to(end_pos)
	var ride_from: Vector2 = start_pos if dist_to_start < dist_to_end else end_pos
	var ride_to: Vector2 = end_pos if dist_to_start < dist_to_end else start_pos

	# Disable player physics during zipline ride.
	body.set_physics_process(false)
	body.velocity = Vector2.ZERO

	var ride_tween := create_tween()
	ride_tween.tween_property(body, "global_position", ride_from, 0.1)
	ride_tween.tween_property(body, "global_position", ride_to, 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	ride_tween.tween_callback(func() -> void:
		if is_instance_valid(body):
			body.set_physics_process(true)
	)


# =============================================================================
# Task 2: Visual Boundaries
# =============================================================================

var _ocean_rect: ColorRect = null

func _create_visual_boundaries() -> void:
	# Top edge: dark green forest/tree row.
	var forest := ColorRect.new()
	forest.name = "BoundaryForest"
	forest.color = Color(0.1, 0.35, 0.08)
	forest.position = Vector2(0, -30)
	forest.size = Vector2(1280, 40)
	forest.z_index = -1
	add_child(forest)

	# Extra tree blocks on top edge for texture.
	for i in range(16):
		var tree_block := ColorRect.new()
		tree_block.color = Color(0.08, 0.28, 0.06) if i % 2 == 0 else Color(0.12, 0.38, 0.1)
		tree_block.position = Vector2(float(i) * 80.0, -20)
		tree_block.size = Vector2(80, 30)
		tree_block.z_index = -1
		forest.add_child(tree_block)

	# Left edge: cliff face.
	var cliff_left := ColorRect.new()
	cliff_left.name = "BoundaryCliffLeft"
	cliff_left.color = Color(0.4, 0.35, 0.3)
	cliff_left.position = Vector2(-30, 0)
	cliff_left.size = Vector2(35, 720)
	cliff_left.z_index = -1
	add_child(cliff_left)

	# Darker edge strip on cliffs.
	var cliff_left_edge := ColorRect.new()
	cliff_left_edge.color = Color(0.25, 0.2, 0.18)
	cliff_left_edge.position = Vector2(0, 0)
	cliff_left_edge.size = Vector2(5, 720)
	cliff_left.add_child(cliff_left_edge)

	# Right edge: cliff face.
	var cliff_right := ColorRect.new()
	cliff_right.name = "BoundaryCliffRight"
	cliff_right.color = Color(0.4, 0.35, 0.3)
	cliff_right.position = Vector2(1275, 0)
	cliff_right.size = Vector2(35, 720)
	cliff_right.z_index = -1
	add_child(cliff_right)

	var cliff_right_edge := ColorRect.new()
	cliff_right_edge.color = Color(0.25, 0.2, 0.18)
	cliff_right_edge.position = Vector2(30, 0)
	cliff_right_edge.size = Vector2(5, 720)
	cliff_right.add_child(cliff_right_edge)

	# Bottom edge: ocean water.
	_ocean_rect = ColorRect.new()
	_ocean_rect.name = "BoundaryOcean"
	_ocean_rect.color = Color(0.15, 0.35, 0.65)
	_ocean_rect.position = Vector2(0, 710)
	_ocean_rect.size = Vector2(1280, 40)
	_ocean_rect.z_index = -1
	add_child(_ocean_rect)

	# Lighter wave strip on top of ocean.
	var wave_strip := ColorRect.new()
	wave_strip.name = "WaveStrip"
	wave_strip.color = Color(0.3, 0.55, 0.8, 0.6)
	wave_strip.position = Vector2(0, 0)
	wave_strip.size = Vector2(1280, 6)
	_ocean_rect.add_child(wave_strip)


func _animate_ocean_wave(delta: float) -> void:
	if not _ocean_rect:
		return
	_wave_timer += delta
	# Subtle vertical bob for the ocean.
	_ocean_rect.position.y = 710.0 + sin(_wave_timer * 2.0) * 2.0


# =============================================================================
# Task 4: NPCs/Signposts
# =============================================================================

func _create_signposts() -> void:
	var entrances := {
		1: tower_entrance_1,
		2: tower_entrance_2,
		3: tower_entrance_3,
		4: tower_entrance_final,
	}

	for tower_id in SIGNPOST_DATA:
		var data: Dictionary = SIGNPOST_DATA[tower_id]
		var entrance: Area2D = entrances.get(tower_id)
		if not entrance:
			continue

		var sign_pos: Vector2 = entrance.global_position + data["offset"]

		# Signpost pole (brown rectangle).
		var pole := ColorRect.new()
		pole.name = "SignpostPole%d" % tower_id
		pole.color = Color(0.45, 0.3, 0.15)
		pole.size = Vector2(4, 18)
		pole.position = sign_pos - Vector2(2, 9)
		pole.z_index = 1
		add_child(pole)

		# Signpost board on top.
		var board := ColorRect.new()
		board.name = "SignpostBoard%d" % tower_id
		board.color = Color(0.6, 0.45, 0.2)
		board.size = Vector2(20, 10)
		board.position = sign_pos - Vector2(10, 18)
		board.z_index = 1
		add_child(board)

		# Floating text label (hidden by default).
		var info_label := Label.new()
		info_label.name = "SignpostLabel%d" % tower_id
		info_label.text = data["text"]
		info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info_label.add_theme_font_size_override("font_size", 11)
		info_label.modulate = Color(1.0, 1.0, 0.8, 0.0)
		# Position the label above the signpost.
		var text_width: float = float(data["text"].length()) * 5.5
		info_label.position = sign_pos - Vector2(text_width / 2.0, 32)
		info_label.z_index = 10
		add_child(info_label)

		info_label.set_meta("signpost_pos", sign_pos)
		_signpost_labels[tower_id] = info_label


func _update_signpost_proximity() -> void:
	var players: Array[Node] = get_tree().get_nodes_in_group("players")
	for tower_id in _signpost_labels:
		var label: Label = _signpost_labels[tower_id]
		var sign_pos: Vector2 = label.get_meta("signpost_pos")
		var any_near := false
		for p in players:
			if p is Node2D:
				var dist: float = p.global_position.distance_to(sign_pos)
				if dist < 40.0:
					any_near = true
					break

		var target_alpha: float = 1.0 if any_near else 0.0
		var current_alpha: float = label.modulate.a
		# Smooth fade in/out.
		var new_alpha: float = move_toward(current_alpha, target_alpha, get_process_delta_time() * 4.0)
		label.modulate.a = new_alpha


# =============================================================================
# Task 5: Ambient Overworld Enemies
# =============================================================================

func _spawn_patrol_skeletons() -> void:
	for spawn_data in SKELETON_SPAWNS:
		var skeleton: CharacterBody2D = PATROL_SKELETON_SCENE.instantiate()
		skeleton.global_position = spawn_data["pos"]
		skeleton.set_patrol_distance(spawn_data["dist"])
		add_child(skeleton)
