extends Area2D

## Vertical icing waterfall that pushes players downward and reduces horizontal control.

@export var stream_height: float = 120.0
@export var stream_width: float = 24.0
@export var push_speed: float = 200.0
@export var horizontal_control: float = 0.3

var _time: float = 0.0
var _players_inside: Array[Node2D] = []
var _drip_offsets: Array[float] = []

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2

	var col: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(stream_width, stream_height)
	col.shape = shape
	col.position = Vector2(stream_width / 2.0, stream_height / 2.0)
	add_child(col)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Pre-generate drip particle offsets
	for i: int in range(6):
		_drip_offsets.append(randf() * stream_width)


func _process(delta: float) -> void:
	_time += delta

	for body: Node2D in _players_inside:
		if not is_instance_valid(body):
			continue
		if body is CharacterBody2D:
			var char_body: CharacterBody2D = body as CharacterBody2D
			# Push downward
			if char_body.velocity.y < push_speed:
				char_body.velocity.y = push_speed
			# Reduce horizontal control by dampening horizontal velocity toward zero
			char_body.velocity.x *= horizontal_control

	queue_redraw()


func _draw() -> void:
	var stream_color: Color = Color(0.6, 0.8, 1.0, 0.5)
	var drip_color: Color = Color(0.7, 0.9, 1.0, 0.7)
	var highlight_color: Color = Color(0.85, 0.95, 1.0, 0.3)

	# Main stream body
	draw_rect(Rect2(0.0, 0.0, stream_width, stream_height), stream_color)

	# Lighter center highlight
	draw_rect(Rect2(stream_width * 0.3, 0.0, stream_width * 0.4, stream_height), highlight_color)

	# Animated drip particles falling down
	for i: int in range(_drip_offsets.size()):
		var dx: float = _drip_offsets[i]
		var speed_factor: float = 40.0 + float(i) * 10.0
		var dy: float = fmod(_time * speed_factor + float(i) * 25.0, stream_height)
		var drip_size: float = 2.0 + sin(_time * 3.0 + float(i)) * 0.5
		draw_circle(Vector2(dx, dy), drip_size, drip_color)


func _on_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D:
		_players_inside.append(body)


func _on_body_exited(body: Node2D) -> void:
	_players_inside.erase(body)
