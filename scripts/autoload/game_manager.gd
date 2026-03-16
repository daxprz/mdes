extends Node

## Global game state manager.
## Tracks game state, tower completion, artifacts, mini-muffin counts,
## and handles scene transitions.

enum GameState { TITLE, OVERWORLD, TOWER, BOSS }

signal state_changed(new_state: GameState)
signal tower_completed(tower_name: String)
signal final_tower_unlocked

const TOTAL_TOWERS := 3  # Complete towers 1-3 to unlock the final tower

var current_state: GameState = GameState.TITLE
var completed_towers: Dictionary = {}  # tower_name -> bool
var collected_artifacts: Dictionary = {}  # player_index -> Array of artifact names
var mini_muffin_counts: Dictionary = {}  # player_index -> int

var current_tower_id: int = 0
var _transitioning := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	PlayerManager.all_players_dead.connect(_on_all_players_dead)


func _on_all_players_dead() -> void:
	# Don't restart from title screen
	if current_state == GameState.TITLE:
		return

	# Show "ALL PLAYERS DOWN" message, then restart the current scene
	_show_wipe_screen()


# -- State Management ----------------------------------------------------------

func change_state(new_state: GameState) -> void:
	if current_state == new_state:
		return
	current_state = new_state
	state_changed.emit(new_state)


# -- Tower Tracking ------------------------------------------------------------

func mark_tower_completed(tower_name: String) -> void:
	if completed_towers.has(tower_name):
		return
	completed_towers[tower_name] = true
	tower_completed.emit(tower_name)
	_check_final_tower_unlock()


func is_tower_completed(tower_name: String) -> bool:
	return completed_towers.has(tower_name)


func get_completed_tower_count() -> int:
	return completed_towers.size()


func _check_final_tower_unlock() -> void:
	if completed_towers.size() >= TOTAL_TOWERS:
		final_tower_unlocked.emit()


# -- Artifacts -----------------------------------------------------------------

func add_artifact(player_index: int, artifact_name: String) -> void:
	if not collected_artifacts.has(player_index):
		collected_artifacts[player_index] = []
	if artifact_name not in collected_artifacts[player_index]:
		collected_artifacts[player_index].append(artifact_name)


func get_artifacts(player_index: int) -> Array:
	if collected_artifacts.has(player_index):
		return collected_artifacts[player_index]
	return []


# -- Mini-Muffins --------------------------------------------------------------

func add_mini_muffins(player_index: int, amount: int = 1) -> void:
	if not mini_muffin_counts.has(player_index):
		mini_muffin_counts[player_index] = 0
	mini_muffin_counts[player_index] += amount


func get_mini_muffin_count(player_index: int) -> int:
	if mini_muffin_counts.has(player_index):
		return mini_muffin_counts[player_index]
	return 0


# -- Scene Transitions ---------------------------------------------------------

func transition_to_scene(scene_path: String) -> void:
	if _transitioning:
		return
	_transitioning = true
	get_tree().call_deferred("change_scene_to_file", scene_path)
	await get_tree().process_frame
	await get_tree().process_frame
	_transitioning = false


func go_to_title() -> void:
	change_state(GameState.TITLE)
	transition_to_scene("res://scenes/ui/title_screen.tscn")


func go_to_overworld() -> void:
	change_state(GameState.OVERWORLD)
	transition_to_scene("res://scenes/overworld/valley.tscn")


func go_to_tower(tower_id: int) -> void:
	current_tower_id = tower_id
	change_state(GameState.TOWER)
	if tower_id == 2:
		transition_to_scene("res://scenes/towers/dungeon_tower.tscn")
	else:
		transition_to_scene("res://scenes/towers/tower_base.tscn")


func go_to_boss(tower_id: int = -1) -> void:
	if tower_id >= 0:
		current_tower_id = tower_id
	change_state(GameState.BOSS)
	transition_to_scene("res://scenes/bosses/boss_arena.tscn")


# -- Reset / New Game ----------------------------------------------------------

func reset_game() -> void:
	current_state = GameState.TITLE
	completed_towers.clear()
	collected_artifacts.clear()
	mini_muffin_counts.clear()


func _show_wipe_screen() -> void:
	# Dark overlay + "ALL PLAYERS DOWN" text, then restart
	var canvas := CanvasLayer.new()
	canvas.layer = 50
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas)

	var overlay := ColorRect.new()
	overlay.anchors_preset = Control.PRESET_FULL_RECT
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.color = Color(0, 0, 0, 0)
	canvas.add_child(overlay)

	var label := Label.new()
	label.text = "ALL PLAYERS DOWN!"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.anchors_preset = Control.PRESET_CENTER
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.anchor_top = 0.5
	label.anchor_bottom = 0.5
	label.offset_left = -200
	label.offset_right = 200
	label.offset_top = -30
	label.offset_bottom = 30
	label.add_theme_font_size_override("font_size", 36)
	label.modulate = Color(1.0, 0.3, 0.3)
	label.modulate.a = 0.0
	canvas.add_child(label)

	var sub_label := Label.new()
	sub_label.text = "Restarting..."
	sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_label.anchors_preset = Control.PRESET_CENTER
	sub_label.anchor_left = 0.5
	sub_label.anchor_right = 0.5
	sub_label.anchor_top = 0.5
	sub_label.anchor_bottom = 0.5
	sub_label.offset_left = -100
	sub_label.offset_right = 100
	sub_label.offset_top = 20
	sub_label.offset_bottom = 50
	sub_label.add_theme_font_size_override("font_size", 18)
	sub_label.modulate.a = 0.0
	canvas.add_child(sub_label)

	AudioManager.play("player_die", 2.0, 0.6)

	var tween := create_tween()
	tween.tween_property(overlay, "color:a", 0.8, 0.5)
	tween.tween_property(label, "modulate:a", 1.0, 0.3)
	tween.tween_property(sub_label, "modulate:a", 1.0, 0.3)
	tween.tween_interval(2.0)
	tween.tween_callback(func() -> void:
		canvas.queue_free()
		_restart_current_scene()
	)


func _restart_current_scene() -> void:
	# Revive all players with full health
	for pi in PlayerManager.players:
		var p: Dictionary = PlayerManager.players[pi]
		p["health"] = p["max_health"]
		p["mana"] = p["max_mana"]
		p["is_alive"] = true

	# Reload the current scene
	_transitioning = false  # Force allow transition
	match current_state:
		GameState.TOWER:
			if current_tower_id == 2:
				transition_to_scene("res://scenes/towers/dungeon_tower.tscn")
			else:
				transition_to_scene("res://scenes/towers/tower_base.tscn")
		GameState.BOSS:
			transition_to_scene("res://scenes/bosses/boss_arena.tscn")
		GameState.OVERWORLD:
			transition_to_scene("res://scenes/overworld/valley.tscn")
		_:
			transition_to_scene("res://scenes/overworld/valley.tscn")
