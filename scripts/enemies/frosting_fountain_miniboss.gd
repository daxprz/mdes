extends CharacterBody2D

## Frosting Fountain - mid-tower mini-boss for Tower 2.
## Stationary turret that sprays rotating icing streams with phase escalation.

signal died(global_pos: Vector2)

const MAX_HEALTH := 120
const GRAVITY := 800.0
const SPRAY_INTERVAL := 0.15
const PROJECTILE_SPEED := 200.0
const PROJECTILE_DAMAGE := 8
const ROTATION_PERIOD := 4.0  # Full 360 in 4 seconds
const PAUSE_INTERVAL := 4.0
const PAUSE_DURATION := 1.0
const DOUBLE_DAMAGE_MULTIPLIER := 2

var health := MAX_HEALTH
var is_dead := false
var current_phase := 1
var _nozzle_angle := 0.0
var _spray_timer := 0.0
var _cycle_timer := 0.0
var _is_spraying := true
var _pause_timer := 0.0
var _flash_timer := 0.0
var _original_modulate := Color.WHITE
var _stream_count := 1
var _rotation_speed: float = TAU / ROTATION_PERIOD

const HEALTH_BAR_SCENE := preload("res://scenes/ui/health_bar.tscn")
const PROJECTILE_SCENE := preload("res://scenes/bosses/boss_projectile.tscn")

var _health_bar: Node2D = null


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 8
	collision_mask = 1
	_original_modulate = modulate

	_health_bar = HEALTH_BAR_SCENE.instantiate()
	_health_bar.bar_width = 36.0
	_health_bar.bar_height = 4.0
	_health_bar.bar_offset = Vector2(0, -36)
	_health_bar.fill_color = Color(0.9, 0.1, 0.1)
	add_child(_health_bar)
	_health_bar.set_health(health, MAX_HEALTH)


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# Gravity - stationary but sits on platforms
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	else:
		velocity.y = 0.0
	velocity.x = 0.0

	# Flash timer
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			modulate = _original_modulate

	# Spray/pause cycle
	if _is_spraying:
		_cycle_timer += delta
		_nozzle_angle += _rotation_speed * delta
		if _nozzle_angle > TAU:
			_nozzle_angle -= TAU

		# Fire projectiles
		_spray_timer -= delta
		if _spray_timer <= 0.0:
			_spray_timer = SPRAY_INTERVAL
			_fire_streams()

		# Pause after cycle
		if _cycle_timer >= PAUSE_INTERVAL:
			_is_spraying = false
			_pause_timer = PAUSE_DURATION
			_cycle_timer = 0.0
	else:
		_pause_timer -= delta
		if _pause_timer <= 0.0:
			_is_spraying = true

	move_and_slide()
	queue_redraw()


func _fire_streams() -> void:
	for i in range(_stream_count):
		var angle_offset: float = (TAU / float(_stream_count)) * float(i)
		var angle: float = _nozzle_angle + angle_offset
		var dir := Vector2(cos(angle), sin(angle))
		_spawn_icing_projectile(dir)


func _spawn_icing_projectile(dir: Vector2) -> void:
	var proj: Node2D = PROJECTILE_SCENE.instantiate()
	proj.global_position = global_position + Vector2(0, -16)
	var normalized_dir: Vector2 = Vector2(dir.x, dir.y).normalized()
	proj.direction = normalized_dir
	proj.speed = PROJECTILE_SPEED
	proj.damage = PROJECTILE_DAMAGE
	proj.color = Color(1.0, 0.85, 0.9)  # Pink icing
	proj.leave_puddle = true
	proj.projectile_size = 4.0
	proj.lifetime = 3.0
	get_tree().current_scene.add_child(proj)


func _check_phase() -> void:
	var pct: float = float(health) / float(MAX_HEALTH)
	var new_phase := 1
	if pct <= 0.25:
		new_phase = 3
	elif pct <= 0.50:
		new_phase = 2

	if new_phase != current_phase:
		current_phase = new_phase
		match current_phase:
			2:
				_stream_count = 2
			3:
				_stream_count = 3
				_rotation_speed = TAU / (ROTATION_PERIOD * 0.7)  # Faster rotation


# -- Health --------------------------------------------------------------------

func take_damage(amount: int, _source_index: int = -1) -> void:
	if is_dead:
		return
	# Rift tentacle absorbs damage first
	if has_meta("rift_tentacle"):
		var tentacle: Node2D = get_meta("rift_tentacle")
		if is_instance_valid(tentacle) and tentacle.has_method("take_tentacle_damage"):
			amount = tentacle.take_tentacle_damage(amount)
			if amount <= 0:
				return
		else:
			remove_meta("rift_tentacle")
			remove_meta("rift_attached")

	var final_amount: int = amount
	# Double damage when NOT spraying (vulnerable window)
	if not _is_spraying:
		final_amount = amount * DOUBLE_DAMAGE_MULTIPLIER

	health = maxi(0, health - final_amount)
	if _health_bar:
		_health_bar.set_health(health, MAX_HEALTH)
	AudioManager.play("enemy_hit", -2.0, 0.7)
	_hit_flash()
	_check_phase()
	if health <= 0:
		_die()


func _hit_flash() -> void:
	modulate = Color.WHITE * 3.0
	_flash_timer = 0.12


func _die() -> void:
	is_dead = true
	var HealthPickup := load("res://scripts/items/health_pickup.gd")
	HealthPickup.try_spawn(get_parent(), global_position)
	AudioManager.play("enemy_die")
	died.emit(global_position)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(0.1, 0.1), 0.4)
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.chain().tween_callback(queue_free)


# -- Drawing -------------------------------------------------------------------

func _draw() -> void:
	# Base: white/pink fountain
	var base_color := Color(0.95, 0.9, 0.92)
	var pink := Color(1.0, 0.75, 0.82)
	# Fountain base (trapezoid approximated as rects)
	draw_rect(Rect2(-16, -4, 32, 20), base_color)
	draw_rect(Rect2(-12, -12, 24, 10), base_color)
	# Rim accent
	draw_rect(Rect2(-17, -5, 34, 3), pink)

	# Nozzle
	var nozzle_base := Vector2(0, -16)
	var nozzle_end := nozzle_base + Vector2(cos(_nozzle_angle), sin(_nozzle_angle)) * 12.0
	draw_line(nozzle_base, nozzle_end, Color(0.6, 0.6, 0.65), 3.0)
	draw_circle(nozzle_end, 3.0, pink)

	# Phase 2+: show extra nozzle directions
	for i in range(1, _stream_count):
		var a: float = _nozzle_angle + (TAU / float(_stream_count)) * float(i)
		var ne := nozzle_base + Vector2(cos(a), sin(a)) * 10.0
		draw_line(nozzle_base, ne, Color(0.6, 0.6, 0.65, 0.5), 2.0)

	# Icing droplets decoration
	if _is_spraying:
		for i in range(4):
			var a: float = _nozzle_angle + float(i) * 0.3
			var drop_pos := nozzle_base + Vector2(cos(a), sin(a)) * (14.0 + float(i) * 3.0)
			draw_circle(drop_pos, 2.0, Color(1.0, 0.85, 0.9, 0.7))

	# Vulnerability indicator when paused
	if not _is_spraying:
		draw_circle(Vector2(0, -24), 4.0, Color(1, 1, 0, 0.8))


# -- Helpers -------------------------------------------------------------------

func set_patrol_distance(_dist: float) -> void:
	pass  # Stationary mini-boss
