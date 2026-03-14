extends Area2D

## Candy cane bounce pad that launches players upward when they land on it.

@export var launch_velocity: float = -700.0
@export var pad_width: float = 32.0
@export var pad_height: float = 8.0

var _time: float = 0.0
var _squish_timer: float = 0.0
var _squish_duration: float = 0.2

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2

	var col: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(pad_width, pad_height)
	col.shape = shape
	col.position = Vector2(pad_width / 2.0, pad_height / 2.0)
	add_child(col)

	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_time += delta
	if _squish_timer > 0.0:
		_squish_timer -= delta
		queue_redraw()


func _draw() -> void:
	var red: Color = Color(0.9, 0.15, 0.15, 1.0)
	var white: Color = Color(1.0, 0.95, 0.95, 1.0)

	var squish_factor: float = 1.0
	if _squish_timer > 0.0:
		var t: float = _squish_timer / _squish_duration
		squish_factor = 1.0 - t * 0.4  # Squish vertically

	var draw_height: float = pad_height * squish_factor
	var y_offset: float = pad_height - draw_height

	# Draw curved pad shape (flat bottom, curved top)
	# Base
	draw_rect(Rect2(0.0, y_offset, pad_width, draw_height), red)

	# Red and white stripes (candy cane pattern)
	var stripe_width: float = 6.0
	var stripe_count: int = int(pad_width / stripe_width) + 1
	for i: int in range(stripe_count):
		if i % 2 == 0:
			continue
		var sx: float = float(i) * stripe_width
		var sw: float = minf(stripe_width, pad_width - sx)
		if sw > 0.0:
			draw_rect(Rect2(sx, y_offset, sw, draw_height), white)

	# Curved top highlight
	var center_x: float = pad_width / 2.0
	draw_circle(Vector2(center_x, y_offset), pad_width * 0.15, white)


func _on_body_entered(body: Node2D) -> void:
	if not (body is CharacterBody2D):
		return
	# Only bounce if player is falling downward (landing on pad)
	var char_body: CharacterBody2D = body as CharacterBody2D
	if char_body.velocity.y < 0.0:
		return
	char_body.velocity.y = launch_velocity
	_squish_timer = _squish_duration
	AudioManager.play("jump")
	queue_redraw()
