extends StaticBody2D

## Cookie platform that crumbles when stood on and respawns after a delay.

@export var platform_width: float = 80.0
@export var platform_height: float = 12.0
@export var shake_duration: float = 0.8
@export var respawn_delay: float = 5.0

enum State { IDLE, SHAKING, BROKEN, RESPAWNING }

var _state: int = State.IDLE
var _timer: float = 0.0
var _time: float = 0.0
var _collision_shape: CollisionShape2D
var _detect_area: Area2D
var _shake_offset: Vector2 = Vector2.ZERO
var _original_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0

	_original_position = position

	# Physical collision
	_collision_shape = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(platform_width, platform_height)
	_collision_shape.shape = shape
	_collision_shape.position = Vector2(platform_width / 2.0, platform_height / 2.0)
	add_child(_collision_shape)

	# Detection area slightly above the platform
	_detect_area = Area2D.new()
	_detect_area.collision_layer = 0
	_detect_area.collision_mask = 2
	add_child(_detect_area)

	var area_col: CollisionShape2D = CollisionShape2D.new()
	var area_shape: RectangleShape2D = RectangleShape2D.new()
	area_shape.size = Vector2(platform_width, platform_height + 6.0)
	area_col.shape = area_shape
	area_col.position = Vector2(platform_width / 2.0, platform_height / 2.0 - 3.0)
	_detect_area.add_child(area_col)

	_detect_area.body_entered.connect(_on_body_entered)

	queue_redraw()


func _process(delta: float) -> void:
	_time += delta

	match _state:
		State.SHAKING:
			_timer -= delta
			_shake_offset = Vector2(randf_range(-2.0, 2.0), randf_range(-1.0, 1.0))
			position = _original_position + _shake_offset
			queue_redraw()
			if _timer <= 0.0:
				_break_apart()
		State.BROKEN:
			_timer -= delta
			if _timer <= 0.0:
				_respawn()
		State.RESPAWNING:
			pass


func _draw() -> void:
	if _state == State.BROKEN:
		return

	var brown: Color = Color(0.55, 0.35, 0.2, 1.0)
	var dark_brown: Color = Color(0.4, 0.25, 0.12, 1.0)
	var crack_color: Color = Color(0.3, 0.18, 0.08, 0.7)

	# Main platform
	draw_rect(Rect2(0.0, 0.0, platform_width, platform_height), brown)

	# Cookie texture dots
	for i: int in range(5):
		var dx: float = 8.0 + float(i) * (platform_width - 16.0) / 4.0
		var dy: float = platform_height / 2.0
		draw_circle(Vector2(dx, dy), 2.0, dark_brown)

	# Crack lines (always visible to hint at fragility)
	draw_line(Vector2(platform_width * 0.3, 0.0),
		Vector2(platform_width * 0.35, platform_height), crack_color, 1.0)
	draw_line(Vector2(platform_width * 0.7, platform_height),
		Vector2(platform_width * 0.65, 0.0), crack_color, 1.0)

	# Extra shaking cracks
	if _state == State.SHAKING:
		draw_line(Vector2(platform_width * 0.5, 0.0),
			Vector2(platform_width * 0.45, platform_height * 0.6), crack_color, 1.5)


func _on_body_entered(body: Node2D) -> void:
	if _state != State.IDLE:
		return
	if body is CharacterBody2D:
		_state = State.SHAKING
		_timer = shake_duration
		AudioManager.play("player_hurt")


func _break_apart() -> void:
	_state = State.BROKEN
	_timer = respawn_delay
	_collision_shape.set_deferred("disabled", true)
	_shake_offset = Vector2.ZERO
	position = _original_position
	visible = false


func _respawn() -> void:
	_state = State.IDLE
	_collision_shape.set_deferred("disabled", false)
	visible = true
	position = _original_position
	queue_redraw()
