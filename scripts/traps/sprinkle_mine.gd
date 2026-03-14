extends Area2D

## Hidden sprinkle mine that arms when a player approaches and explodes after a short delay.

@export var damage: int = 15
@export var knockback_force: float = 300.0
@export var arm_radius: float = 20.0
@export var explosion_radius: float = 40.0
@export var arm_delay: float = 0.3

enum State { HIDDEN, ARMED, EXPLODING, SPENT }

var _state: int = State.HIDDEN
var _timer: float = 0.0
var _time: float = 0.0
var _detect_area: Area2D
var _explosion_area: Area2D
var _sprinkle_colors: Array[Color] = []

func _ready() -> void:
	collision_layer = 0
	collision_mask = 0

	# Detection area for arming
	_detect_area = Area2D.new()
	_detect_area.collision_layer = 0
	_detect_area.collision_mask = 2
	add_child(_detect_area)

	var detect_col: CollisionShape2D = CollisionShape2D.new()
	var detect_shape: CircleShape2D = CircleShape2D.new()
	detect_shape.radius = arm_radius
	detect_col.shape = detect_shape
	_detect_area.add_child(detect_col)

	_detect_area.body_entered.connect(_on_detect_body_entered)

	# Explosion area (starts disabled)
	_explosion_area = Area2D.new()
	_explosion_area.collision_layer = 0
	_explosion_area.collision_mask = 2
	_explosion_area.monitoring = false
	add_child(_explosion_area)

	var exp_col: CollisionShape2D = CollisionShape2D.new()
	var exp_shape: CircleShape2D = CircleShape2D.new()
	exp_shape.radius = explosion_radius
	exp_col.shape = exp_shape
	_explosion_area.add_child(exp_col)

	# Generate random sprinkle colors
	_sprinkle_colors.append(Color(1.0, 0.3, 0.4, 1.0))  # Pink
	_sprinkle_colors.append(Color(0.3, 0.8, 1.0, 1.0))  # Blue
	_sprinkle_colors.append(Color(1.0, 0.9, 0.2, 1.0))  # Yellow
	_sprinkle_colors.append(Color(0.4, 1.0, 0.4, 1.0))  # Green
	_sprinkle_colors.append(Color(0.8, 0.4, 1.0, 1.0))  # Purple

	queue_redraw()


func _process(delta: float) -> void:
	_time += delta

	match _state:
		State.ARMED:
			_timer -= delta
			queue_redraw()
			if _timer <= 0.0:
				_explode()
		State.EXPLODING:
			_timer -= delta
			if _timer <= 0.0:
				_state = State.SPENT
				visible = false
				set_process(false)


func _draw() -> void:
	match _state:
		State.HIDDEN:
			# Tiny cluster of colored dots (slightly visible)
			for i: int in range(5):
				var angle: float = float(i) * TAU / 5.0
				var pos: Vector2 = Vector2(cos(angle), sin(angle)) * 3.0
				var col_idx: int = i % _sprinkle_colors.size()
				draw_circle(pos, 1.5, _sprinkle_colors[col_idx])
		State.ARMED:
			# Flashing red warning
			var flash_alpha: float = 0.5 + sin(_time * 20.0) * 0.5
			for i: int in range(5):
				var angle: float = float(i) * TAU / 5.0
				var pos: Vector2 = Vector2(cos(angle), sin(angle)) * 3.0
				draw_circle(pos, 2.0, Color(1.0, 0.1, 0.1, flash_alpha))
		State.EXPLODING:
			# Explosion burst
			var alpha: float = _timer / 0.2
			draw_circle(Vector2.ZERO, explosion_radius * (1.0 - alpha * 0.5),
				Color(1.0, 0.6, 0.2, alpha * 0.6))
			draw_circle(Vector2.ZERO, explosion_radius * 0.5 * (1.0 - alpha * 0.3),
				Color(1.0, 0.9, 0.3, alpha * 0.8))


func _on_detect_body_entered(body: Node2D) -> void:
	if _state != State.HIDDEN:
		return
	if not (body is CharacterBody2D):
		return
	_state = State.ARMED
	_timer = arm_delay
	AudioManager.play("jump")  # Brief beep sound
	queue_redraw()


func _explode() -> void:
	_state = State.EXPLODING
	_timer = 0.2  # Brief explosion visual duration
	AudioManager.play("explosion")

	# Enable explosion area briefly to detect bodies
	_explosion_area.monitoring = true

	# Damage and knockback all bodies in range
	# Use call_deferred to let physics update
	call_deferred("_apply_explosion")


func _apply_explosion() -> void:
	for body: Node2D in _explosion_area.get_overlapping_bodies():
		if body.has_method("take_damage"):
			body.take_damage(damage)
		if body is CharacterBody2D:
			var char_body: CharacterBody2D = body as CharacterBody2D
			var dir: Vector2 = (body.global_position - global_position).normalized()
			if dir.length_squared() < 0.01:
				dir = Vector2.UP
			char_body.velocity += dir * knockback_force

	_explosion_area.monitoring = false
	_detect_area.monitoring = false
	queue_redraw()
