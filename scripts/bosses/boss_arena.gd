extends Node2D

## Boss fight arena. Spawns the correct boss based on tower_id,
## spawns players, displays boss health bar, handles victory.

const ARENA_WIDTH := 800.0
const ARENA_HEIGHT := 450.0
const FLOOR_Y := 400.0
const CEILING_Y := 0.0
const WALL_THICKNESS := 20.0
const KILL_ZONE_Y := FLOOR_Y + WALL_THICKNESS + 80.0
const KILL_ZONE_DAMAGE := 10
const SPAWN_POSITION := Vector2(100.0, FLOOR_Y - 30.0)

const BOSS_SCENES := {
	1: "res://scenes/bosses/gingerbread_skeleton.tscn",
	2: "res://scenes/bosses/icing_goblin.tscn",
	3: "res://scenes/bosses/sprinkle_dragon.tscn",
	4: "res://scenes/bosses/giant_muffin.tscn",
}

const TOWER_NAMES := {
	1: "Gingerbread Tower",
	2: "Icing Tower",
	3: "Sprinkle Tower",
	4: "Muffin Tower",
}

const ARTIFACTS := {
	1: ["Skeleton Bone Charm", "Gingerbread Shield"],
	2: ["Icing Wand", "Goblin Boots"],
	3: ["Sprinkle Crown", "Dragon Scale"],
	4: ["Muffin Heart", "Golden Crumb"],
}

## Set this before adding to tree, or via the inspector.
@export var tower_id: int = 1

var _boss: Node2D = null
var _boss_health_bar: ProgressBar = null
var _boss_name_label: Label = null
var _victory_shown := false
var _kill_zone: Area2D = null


func _ready() -> void:
	tower_id = GameManager.current_tower_id
	PlayerManager.player_joined.connect(_on_player_joined_midgame)
	_build_arena()
	_build_boss_ui()
	_spawn_boss()
	_spawn_players()
	_setup_camera()
	GameManager.change_state(GameManager.GameState.BOSS)


func _on_player_joined_midgame(player_index: int) -> void:
	var pos := Vector2(80.0 + player_index * 50.0, FLOOR_Y - 30)
	_spawn_player_placeholder(player_index, pos)


func _setup_camera() -> void:
	var multi_cam_script := load("res://scripts/ui/multi_camera.gd")
	var cam := Camera2D.new()
	cam.set_script(multi_cam_script)
	cam.min_zoom = 0.6
	cam.max_zoom = 1.2
	cam.zoom_margin = Vector2(150, 100)
	cam.position = Vector2(ARENA_WIDTH / 2.0, ARENA_HEIGHT / 2.0)
	add_child(cam)


# -- Arena Construction --------------------------------------------------------

func _build_arena() -> void:
	var wall_height: float = FLOOR_Y + WALL_THICKNESS - CEILING_Y

	# Floor
	var floor_body := StaticBody2D.new()
	floor_body.position = Vector2(ARENA_WIDTH / 2.0, FLOOR_Y + WALL_THICKNESS / 2.0)
	var floor_shape := CollisionShape2D.new()
	var floor_rect := RectangleShape2D.new()
	floor_rect.size = Vector2(ARENA_WIDTH, WALL_THICKNESS)
	floor_shape.shape = floor_rect
	floor_body.add_child(floor_shape)
	add_child(floor_body)

	# Floor visual
	var floor_vis := ColorRect.new()
	floor_vis.size = Vector2(ARENA_WIDTH, WALL_THICKNESS)
	floor_vis.position = Vector2(0, FLOOR_Y)
	floor_vis.color = Color(0.45, 0.35, 0.25)  # Brown ground
	add_child(floor_vis)

	# Ceiling
	var ceiling_body := StaticBody2D.new()
	ceiling_body.position = Vector2(ARENA_WIDTH / 2.0, CEILING_Y - WALL_THICKNESS / 2.0)
	var ceiling_shape := CollisionShape2D.new()
	var ceiling_rect := RectangleShape2D.new()
	ceiling_rect.size = Vector2(ARENA_WIDTH + WALL_THICKNESS * 2.0, WALL_THICKNESS)
	ceiling_shape.shape = ceiling_rect
	ceiling_body.add_child(ceiling_shape)
	add_child(ceiling_body)

	# Ceiling visual
	var ceiling_vis := ColorRect.new()
	ceiling_vis.size = Vector2(ARENA_WIDTH + WALL_THICKNESS * 2.0, WALL_THICKNESS)
	ceiling_vis.position = Vector2(-WALL_THICKNESS, CEILING_Y - WALL_THICKNESS)
	ceiling_vis.color = Color(0.3, 0.25, 0.2)
	add_child(ceiling_vis)

	# Left wall (full height from ceiling to floor)
	_add_wall(Vector2(-WALL_THICKNESS / 2.0, CEILING_Y + wall_height / 2.0),
			Vector2(WALL_THICKNESS, wall_height))

	# Right wall (full height from ceiling to floor)
	_add_wall(Vector2(ARENA_WIDTH + WALL_THICKNESS / 2.0, CEILING_Y + wall_height / 2.0),
			Vector2(WALL_THICKNESS, wall_height))

	# Kill zone below the floor - catches players that clip through
	_kill_zone = Area2D.new()
	_kill_zone.position = Vector2(ARENA_WIDTH / 2.0, KILL_ZONE_Y)
	var kz_shape := CollisionShape2D.new()
	var kz_rect := RectangleShape2D.new()
	kz_rect.size = Vector2(ARENA_WIDTH + 200.0, 40.0)
	kz_shape.shape = kz_rect
	_kill_zone.add_child(kz_shape)
	_kill_zone.body_entered.connect(_on_kill_zone_body_entered)
	add_child(_kill_zone)

	# Background
	var bg := ColorRect.new()
	bg.size = Vector2(ARENA_WIDTH, ARENA_HEIGHT)
	bg.position = Vector2.ZERO
	bg.color = Color(0.15, 0.1, 0.2)  # Dark purple
	bg.z_index = -10
	add_child(bg)


func _add_wall(pos: Vector2, size: Vector2) -> void:
	var wall := StaticBody2D.new()
	wall.position = pos
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	wall.add_child(shape)
	add_child(wall)

	var vis := ColorRect.new()
	vis.size = size
	vis.position = pos - size / 2.0
	vis.color = Color(0.3, 0.25, 0.2)
	add_child(vis)


func _on_kill_zone_body_entered(body: Node2D) -> void:
	if not body.is_in_group("players"):
		return
	# Teleport player back to spawn
	body.global_position = SPAWN_POSITION
	body.velocity = Vector2.ZERO
	# Deal damage if possible
	if body.has_method("take_damage"):
		body.take_damage(KILL_ZONE_DAMAGE, -1)


# -- Boss UI -------------------------------------------------------------------

func _build_boss_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	# Container at top-center
	var container := VBoxContainer.new()
	container.anchors_preset = Control.PRESET_CENTER_TOP
	container.anchor_top = 0.0
	container.anchor_bottom = 0.0
	container.anchor_left = 0.5
	container.anchor_right = 0.5
	container.offset_left = -150
	container.offset_right = 150
	container.offset_top = 16
	container.offset_bottom = 70
	canvas.add_child(container)

	# Boss name
	_boss_name_label = Label.new()
	_boss_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name_label.add_theme_font_size_override("font_size", 18)
	_boss_name_label.text = ""
	container.add_child(_boss_name_label)

	# Health bar
	_boss_health_bar = ProgressBar.new()
	_boss_health_bar.custom_minimum_size = Vector2(300, 20)
	_boss_health_bar.max_value = 100
	_boss_health_bar.value = 100
	_boss_health_bar.show_percentage = false

	# Style the health bar red
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.8, 0.1, 0.1)
	_boss_health_bar.add_theme_stylebox_override("fill", style)

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.2, 0.2, 0.2)
	_boss_health_bar.add_theme_stylebox_override("background", bg_style)

	container.add_child(_boss_health_bar)


# -- Spawning ------------------------------------------------------------------

func _spawn_boss() -> void:
	var scene_path: String = BOSS_SCENES.get(tower_id, BOSS_SCENES[1])
	if not ResourceLoader.exists(scene_path):
		push_error("Boss scene not found: " + scene_path)
		return

	var scene: PackedScene = load(scene_path)
	_boss = scene.instantiate()
	_boss.global_position = Vector2(ARENA_WIDTH - 100, FLOOR_Y - 40)
	add_child(_boss)

	# Connect signals
	if _boss.has_signal("defeated"):
		_boss.defeated.connect(_on_boss_defeated)
	if _boss.has_signal("health_changed"):
		_boss.health_changed.connect(_on_boss_health_changed)

	# Set UI
	var boss_display_name := ""
	match tower_id:
		1: boss_display_name = "Gingerbread Skeleton"
		2: boss_display_name = "Icing Goblin"
		3: boss_display_name = "Sprinkle Dragon"
		4: boss_display_name = "Giant Muffin"
		_: boss_display_name = "Boss"
	_boss_name_label.text = boss_display_name

	if _boss is BossBase:
		_boss_health_bar.max_value = _boss.max_health
		_boss_health_bar.value = _boss.max_health


func _spawn_players() -> void:
	# Spawn a character for each active player on the left side of the arena
	var player_count := PlayerManager.get_active_player_count()
	if player_count == 0:
		# If no players joined yet, spawn at least one placeholder
		_spawn_player_placeholder(0, Vector2(100, FLOOR_Y - 30))
		return

	var spacing := 50.0
	var start_x := 80.0
	var idx := 0
	for player_index in PlayerManager.players.keys():
		var pos := Vector2(start_x + idx * spacing, FLOOR_Y - 30)
		_spawn_player_placeholder(player_index, pos)
		idx += 1


func _spawn_player_placeholder(player_index: int, pos: Vector2) -> void:
	var p_data: Dictionary = PlayerManager.get_player(player_index)
	# Use side-scrolling player for boss arena
	if ResourceLoader.exists("res://scenes/characters/player_side.tscn"):
		var player_scene: PackedScene = load("res://scenes/characters/player_side.tscn")
		var player: Node2D = player_scene.instantiate()
		player.global_position = pos
		player.player_index = player_index
		player.device_id = p_data.get("device_id", -1)
		player.character_class = p_data.get("character_class", PlayerManager.CharacterClass.MELEE)
		player.add_to_group("players")
		add_child(player)
		return

	# Fallback: simple colored rectangle
	var player := CharacterBody2D.new()
	player.global_position = pos
	player.set_meta("player_index", player_index)
	player.add_to_group("players")
	var rect := ColorRect.new()
	rect.color = [Color.GREEN, Color.CYAN, Color.YELLOW, Color.MAGENTA][player_index % 4]
	rect.size = Vector2(20, 28)
	rect.position = Vector2(-10, -14)
	player.add_child(rect)
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(20, 28)
	shape.shape = box
	player.add_child(shape)
	add_child(player)


# -- Signal Handlers -----------------------------------------------------------

func _on_boss_health_changed(current: int, maximum: int) -> void:
	if _boss_health_bar:
		_boss_health_bar.max_value = maximum
		_boss_health_bar.value = current


func _on_boss_defeated() -> void:
	if _victory_shown:
		return
	_victory_shown = true

	_award_artifacts()
	_show_victory()


# -- Victory -------------------------------------------------------------------

func _award_artifacts() -> void:
	var artifact_list: Array = ARTIFACTS.get(tower_id, ["Unknown Artifact"])
	# Give each active player an artifact matching their class or a random one
	for player_index in PlayerManager.players.keys():
		var artifact: String = artifact_list[player_index % artifact_list.size()]
		GameManager.add_artifact(player_index, artifact)


func _show_victory() -> void:
	# Mark tower as completed using the same naming convention as valley.gd
	var tower_key := "tower_%d" % tower_id if tower_id != 4 else "tower_final"
	GameManager.mark_tower_completed(tower_key)

	# Track boss kills and tower completions in profiles, then auto-save
	for pi: int in PlayerManager.players:
		ProfileManager.add_boss_kill(pi)
		ProfileManager.add_tower_complete(pi)
	ProfileManager.auto_save()

	# Victory overlay
	var canvas := CanvasLayer.new()
	canvas.layer = 20
	add_child(canvas)

	var overlay := ColorRect.new()
	overlay.anchors_preset = Control.PRESET_FULL_RECT
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.color = Color(0, 0, 0, 0)
	canvas.add_child(overlay)

	var label := Label.new()
	label.text = "BOSS DEFEATED!"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.anchors_preset = Control.PRESET_CENTER
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.anchor_top = 0.5
	label.anchor_bottom = 0.5
	label.offset_left = -200
	label.offset_right = 200
	label.offset_top = -40
	label.offset_bottom = 40
	label.add_theme_font_size_override("font_size", 36)
	label.modulate.a = 0.0
	canvas.add_child(label)

	var sublabel := Label.new()
	sublabel.text = "Zipline unlocked! Returning to overworld..."
	sublabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sublabel.anchors_preset = Control.PRESET_CENTER
	sublabel.anchor_left = 0.5
	sublabel.anchor_right = 0.5
	sublabel.anchor_top = 0.5
	sublabel.anchor_bottom = 0.5
	sublabel.offset_left = -200
	sublabel.offset_right = 200
	sublabel.offset_top = 30
	sublabel.offset_bottom = 60
	sublabel.add_theme_font_size_override("font_size", 16)
	sublabel.modulate.a = 0.0
	canvas.add_child(sublabel)

	# Animate victory screen
	var tween := create_tween()
	tween.tween_property(overlay, "color:a", 0.6, 0.5)
	tween.tween_property(label, "modulate:a", 1.0, 0.4)
	tween.tween_property(sublabel, "modulate:a", 1.0, 0.3)
	tween.tween_interval(3.0)
	tween.tween_callback(_return_to_overworld)


func _return_to_overworld() -> void:
	if is_inside_tree():
		GameManager.go_to_overworld()
