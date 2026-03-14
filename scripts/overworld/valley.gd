extends Node2D

## The overworld valley map. Top-down Zelda-style layout with tower entrances,
## paths, chasms, and ziplines.

const PLAYER_SCENE := preload("res://scenes/characters/player.tscn")

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

var _ziplines_unlocked: Array[int] = []

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

	# Update ziplines/chasms based on completed towers.
	_update_ziplines()

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
		var tower_name: String = TOWER_NAMES[i + 1]
		var completed := GameManager.is_tower_completed(tower_name)
		if zipline_visuals[i]:
			zipline_visuals[i].visible = completed

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
