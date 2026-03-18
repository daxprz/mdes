extends CharacterBody2D

## Vector-graphics bat for the title screen.
## Swooping graceful movement, hunts fireflies, interactive with game systems.

signal died(global_pos: Vector2)

const MAX_HEALTH := 8
const MOVE_SPEED := 80.0
const SWOOP_AMPLITUDE := 30.0
const SWOOP_FREQ := 2.5
const WING_SPEED := 8.0
const FIREFLY_DETECT_RANGE := 100.0
const FIREFLY_EAT_RANGE := 10.0
const GRAVITY := 200.0

var health := MAX_HEALTH
var mass := 3.0  # Very light
var _dead := false
var _timer: float = 0.0
var _wing_phase: float = 0.0
var _direction: float = 1.0  # 1 = right, -1 = left
var _swoop_phase: float = 0.0
var _target_vel: Vector2 = Vector2.ZERO
var _firefly_manager: Node2D = null  # Reference to the fireflies node
var _bounds: Rect2 = Rect2(100, 300, 1720, 500)

@onready var collision_shape: CollisionShape2D = null


func setup(firefly_mgr: Node2D, bounds: Rect2) -> void:
	_firefly_manager = firefly_mgr
	_bounds = bounds


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 8  # Enemy layer
	collision_mask = 1   # World only

	# Create collision shape
	collision_shape = CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 8.0
	collision_shape.shape = shape
	add_child(collision_shape)

	_direction = 1.0 if randf() > 0.5 else -1.0
	_swoop_phase = randf() * TAU
	_wing_phase = randf() * TAU
	_timer = randf() * 5.0


func _physics_process(delta: float) -> void:
	if _dead:
		return

	_timer += delta
	_wing_phase += WING_SPEED * delta
	_swoop_phase += SWOOP_FREQ * delta

	# Base swooping movement
	var swoop_y: float = sin(_swoop_phase) * SWOOP_AMPLITUDE
	_target_vel = Vector2(_direction * MOVE_SPEED, swoop_y)

	# Hunt fireflies
	if _firefly_manager and is_instance_valid(_firefly_manager):
		var nearest_fly: Vector2 = _firefly_manager.get_nearest_fly(global_position, FIREFLY_DETECT_RANGE)
		if nearest_fly != Vector2.INF:
			# Veer toward firefly
			var to_fly: Vector2 = (nearest_fly - global_position)
			_target_vel = to_fly.normalized() * MOVE_SPEED * 1.3
			_direction = signf(to_fly.x) if absf(to_fly.x) > 1.0 else _direction

			# Eat firefly if close enough
			if to_fly.length() < FIREFLY_EAT_RANGE:
				if _firefly_manager.remove_nearest(global_position):
					AudioManager.play("menu_select", -12.0, 2.0)  # Quiet peep

	# Smooth velocity
	velocity = velocity.lerp(_target_vel, delta * 3.0)

	# Bounds steering
	if global_position.x < _bounds.position.x:
		_direction = 1.0
	elif global_position.x > _bounds.end.x:
		_direction = -1.0
	if global_position.y < _bounds.position.y - 50:
		velocity.y += 100.0 * delta
	elif global_position.y > _bounds.end.y:
		velocity.y -= 100.0 * delta

	# Random direction changes
	if randf() < 0.005:
		_direction *= -1.0

	move_and_slide()
	queue_redraw()


func _draw() -> void:
	if _dead:
		return

	var wing_flap: float = sin(_wing_phase) * 0.7
	var body_color := Color(0.2, 0.2, 0.22)
	var wing_color := Color(0.25, 0.24, 0.26)
	var eye_color := Color(0.9, 0.15, 0.1)
	var facing: float = -1.0 if _direction < 0 else 1.0

	# Body (small oval)
	draw_circle(Vector2.ZERO, 4.0, body_color)
	draw_circle(Vector2(facing * 2.0, -1.0), 2.5, body_color)  # Head

	# Eyes (tiny red dots)
	draw_circle(Vector2(facing * 3.5, -2.0), 1.0, eye_color)
	draw_circle(Vector2(facing * 3.5, -2.0), 0.5, Color(1.0, 0.3, 0.2))

	# Wings (triangular, flapping)
	var wing_y: float = wing_flap * 6.0
	# Left wing
	draw_polygon(PackedVector2Array([
		Vector2(-2, 0),
		Vector2(-10 * facing, -3 + wing_y),
		Vector2(-7 * facing, 1 + wing_y * 0.5),
	]), PackedColorArray([wing_color, wing_color, wing_color]))
	# Right wing
	draw_polygon(PackedVector2Array([
		Vector2(-2, 0),
		Vector2(-10 * facing, -3 - wing_y),
		Vector2(-7 * facing, 1 - wing_y * 0.5),
	]), PackedColorArray([wing_color, wing_color, wing_color]))

	# Wing membrane lines
	var line_col := body_color * Color(0.7, 0.7, 0.7)
	draw_line(Vector2(-2, 0), Vector2(-9 * facing, -2 + wing_y), line_col, 0.5)
	draw_line(Vector2(-2, 0), Vector2(-9 * facing, -2 - wing_y), line_col, 0.5)


func take_damage(amount: int, _source_index: int = -1) -> void:
	if _dead:
		return
	# Rift tentacle absorption
	if has_meta("rift_tentacle"):
		var tentacle: Node2D = get_meta("rift_tentacle")
		if is_instance_valid(tentacle) and tentacle.has_method("take_tentacle_damage"):
			amount = tentacle.take_tentacle_damage(amount)
			if amount <= 0:
				return
		else:
			remove_meta("rift_tentacle")
			remove_meta("rift_attached")
	health -= amount
	if health <= 0:
		_die()


func _die() -> void:
	_dead = true
	AudioManager.play("enemy_die", -6.0, 1.5)
	died.emit(global_position)
	# No drops for bats
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(0.1, 0.1), 0.3)
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.chain().tween_callback(queue_free)


func apply_knockback(force: Vector2) -> void:
	velocity = force * 2.0  # Light = big knockback
