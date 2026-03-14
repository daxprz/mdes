extends CharacterBody2D

## Giant Cookie Cutter - mid-tower mini-boss for Tower 1.
## Floats above the arena, slams down to cut platforms, with a periodic horizontal sweep.

signal died(global_pos: Vector2)

const MAX_HEALTH := 150
const DRIFT_SPEED := 40.0
const SLAM_DAMAGE := 20
const SWEEP_DAMAGE := 15
const SLAM_WIDTH := 60.0
const TELEGRAPH_TIME := 0.8
const STUCK_TIME := 1.5
const ATTACK_COOLDOWN := 2.5
const HOVER_Y_OFFSET := -80.0  # How far above arena center the boss hovers

enum State { HOVER, TELEGRAPH, SLAM, STUCK, RISE, SWEEP }

var health := MAX_HEALTH
var is_dead := false
var _state: State = State.HOVER
var _attack_timer := ATTACK_COOLDOWN
var _state_timer := 0.0
var _slam_count := 0
var _hover_y := 0.0
var _slam_target_x := 0.0
var _slam_start_y := 0.0
var _sweep_direction := 1.0
var _flash_timer := 0.0
var _original_modulate := Color.WHITE
var _drift_direction := 1.0
var _telegraph_line_visible := false
var _arena_bottom := 0.0

const HEALTH_BAR_SCENE := preload("res://scenes/ui/health_bar.tscn")
const PROJECTILE_SCENE := preload("res://scenes/bosses/boss_projectile.tscn")

var _health_bar: Node2D = null


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 8
	collision_mask = 1
	_original_modulate = modulate
	_hover_y = global_position.y + HOVER_Y_OFFSET
	_arena_bottom = global_position.y + 60.0
	global_position.y = _hover_y

	_health_bar = HEALTH_BAR_SCENE.instantiate()
	_health_bar.bar_width = 40.0
	_health_bar.bar_height = 4.0
	_health_bar.bar_offset = Vector2(0, -40)
	_health_bar.fill_color = Color(0.9, 0.1, 0.1)
	add_child(_health_bar)
	_health_bar.set_health(health, MAX_HEALTH)


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# No gravity -- this boss floats
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			modulate = _original_modulate

	match _state:
		State.HOVER:
			_do_hover(delta)
		State.TELEGRAPH:
			_do_telegraph(delta)
		State.SLAM:
			_do_slam(delta)
		State.STUCK:
			_do_stuck(delta)
		State.RISE:
			_do_rise(delta)
		State.SWEEP:
			_do_sweep(delta)

	move_and_slide()
	queue_redraw()


func _do_hover(delta: float) -> void:
	# Drift horizontally
	velocity.x = DRIFT_SPEED * _drift_direction
	velocity.y = 0.0

	# Stay at hover height
	global_position.y = lerpf(global_position.y, _hover_y, 3.0 * delta)

	# Bounce off tower walls
	if global_position.x < 60.0:
		_drift_direction = 1.0
	elif global_position.x > 340.0:
		_drift_direction = -1.0

	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_slam_count += 1
		if _slam_count % 3 == 0:
			_start_sweep()
		else:
			_start_telegraph()


func _start_telegraph() -> void:
	_state = State.TELEGRAPH
	_state_timer = TELEGRAPH_TIME
	_telegraph_line_visible = true
	# Target nearest player x, or random if none
	var player: Node2D = _find_nearest_player()
	if player:
		_slam_target_x = player.global_position.x
	else:
		_slam_target_x = randf_range(60.0, 340.0)
	global_position.x = _slam_target_x
	velocity = Vector2.ZERO
	AudioManager.play("enemy_hit", -6.0, 1.5)


func _do_telegraph(delta: float) -> void:
	velocity = Vector2.ZERO
	_state_timer -= delta
	if _state_timer <= 0.0:
		_telegraph_line_visible = false
		_state = State.SLAM
		_slam_start_y = global_position.y
		velocity.y = 600.0  # Fast slam downward


func _do_slam(delta: float) -> void:
	velocity.x = 0.0
	velocity.y = 600.0

	# Check if reached ground level
	if global_position.y >= _arena_bottom or is_on_floor():
		velocity = Vector2.ZERO
		_state = State.STUCK
		_state_timer = STUCK_TIME
		_deal_slam_damage()
		AudioManager.play("enemy_hit", 2.0, 0.6)


func _deal_slam_damage() -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if not p is Node2D:
			continue
		var dx: float = absf(p.global_position.x - global_position.x)
		var dy: float = absf(p.global_position.y - global_position.y)
		if dx < SLAM_WIDTH / 2.0 and dy < 40.0:
			_damage_player(p, SLAM_DAMAGE)


func _do_stuck(delta: float) -> void:
	velocity = Vector2.ZERO
	_state_timer -= delta
	if _state_timer <= 0.0:
		_state = State.RISE


func _do_rise(delta: float) -> void:
	velocity.x = 0.0
	velocity.y = -120.0
	if global_position.y <= _hover_y:
		global_position.y = _hover_y
		velocity = Vector2.ZERO
		_state = State.HOVER
		_attack_timer = ATTACK_COOLDOWN


func _start_sweep() -> void:
	_state = State.SWEEP
	_state_timer = 0.0
	# Rise to a low height and sweep across
	_sweep_direction = 1.0 if global_position.x < 200.0 else -1.0
	global_position.x = 0.0 if _sweep_direction > 0 else 400.0
	global_position.y = _arena_bottom - 30.0  # Low sweep, must jump over
	AudioManager.play("enemy_hit", 0.0, 0.5)


func _do_sweep(delta: float) -> void:
	velocity.x = 200.0 * _sweep_direction
	velocity.y = 0.0
	_state_timer += delta

	# Damage players in path
	for p in get_tree().get_nodes_in_group("players"):
		if not p is Node2D:
			continue
		var dx: float = absf(p.global_position.x - global_position.x)
		var dy: float = absf(p.global_position.y - global_position.y)
		if dx < 30.0 and dy < 30.0:
			_damage_player(p, SWEEP_DAMAGE)

	# End sweep when past arena
	if global_position.x < -40.0 or global_position.x > 440.0:
		global_position.y = _hover_y
		global_position.x = clampf(global_position.x, 60.0, 340.0)
		_state = State.HOVER
		_attack_timer = ATTACK_COOLDOWN


func _damage_player(player: Node2D, amount: int) -> void:
	if player.has_method("take_damage"):
		player.take_damage(amount, -1)
	var pi: int = -1
	if "player_index" in player:
		pi = player.get("player_index")
	elif player.has_meta("player_index"):
		pi = player.get_meta("player_index")
	if pi >= 0:
		PlayerManager.damage_player(pi, amount)


# -- Health --------------------------------------------------------------------

func take_damage(amount: int, _source_index: int = -1) -> void:
	if is_dead:
		return
	health = maxi(0, health - amount)
	if _health_bar:
		_health_bar.set_health(health, MAX_HEALTH)
	AudioManager.play("enemy_hit", -2.0, 0.7)
	_hit_flash()
	if health <= 0:
		_die()


func _hit_flash() -> void:
	modulate = Color.WHITE * 3.0
	_flash_timer = 0.12


func _die() -> void:
	is_dead = true
	AudioManager.play("enemy_die")
	died.emit(global_position)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(0.1, 0.1), 0.4)
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.chain().tween_callback(queue_free)


# -- Drawing -------------------------------------------------------------------

func _draw() -> void:
	# Main body: metallic rectangle
	var body_color := Color(0.7, 0.72, 0.75)  # Metallic silver
	var edge_color := Color(0.5, 0.52, 0.55)
	draw_rect(Rect2(-20, -30, 40, 60), body_color)
	# Sharp bottom edge
	draw_rect(Rect2(-20, 26, 40, 4), edge_color)
	# Gingerbread man cutout shape (simplified star)
	var cutout_color := Color(0.3, 0.3, 0.32)
	# Head
	draw_circle(Vector2(0, -12), 6.0, cutout_color)
	# Body
	draw_rect(Rect2(-4, -8, 8, 14), cutout_color)
	# Arms
	draw_rect(Rect2(-12, -6, 8, 4), cutout_color)
	draw_rect(Rect2(4, -6, 8, 4), cutout_color)
	# Legs
	draw_rect(Rect2(-8, 4, 5, 8), cutout_color)
	draw_rect(Rect2(3, 4, 5, 8), cutout_color)

	# Telegraph line
	if _telegraph_line_visible:
		draw_line(Vector2(0, 30), Vector2(0, 300), Color(1, 0, 0, 0.6), 3.0)

	# Indicator when stuck (vulnerable)
	if _state == State.STUCK:
		draw_circle(Vector2(0, -35), 4.0, Color(1, 1, 0, 0.8))


# -- Helpers -------------------------------------------------------------------

func _find_nearest_player() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := INF
	for p in get_tree().get_nodes_in_group("players"):
		if p is Node2D:
			var dist: float = global_position.distance_to(p.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = p
	return nearest


func set_patrol_distance(_dist: float) -> void:
	pass  # Mini-boss doesn't patrol
