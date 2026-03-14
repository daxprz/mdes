extends Area2D

## Sticky caramel zone that slows player movement and reduces jump height.

@export var zone_width: float = 48.0
@export var zone_height: float = 12.0
@export var speed_multiplier: float = 0.3
@export var jump_multiplier: float = 0.6

var _time: float = 0.0
var _players_inside: Array[Node2D] = []
var _player_positions: Dictionary = {}

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2

	var col: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(zone_width, zone_height)
	col.shape = shape
	col.position = Vector2(zone_width / 2.0, zone_height / 2.0)
	add_child(col)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	_time += delta

	for body: Node2D in _players_inside:
		if not is_instance_valid(body):
			continue
		if body is CharacterBody2D:
			var char_body: CharacterBody2D = body as CharacterBody2D
			# Slow horizontal movement
			char_body.velocity.x *= speed_multiplier
			# Reduce upward velocity (jump reduction)
			if char_body.velocity.y < 0.0:
				char_body.velocity.y *= jump_multiplier
			# Track position for stretchy string visuals
			_player_positions[body.get_instance_id()] = body.global_position

	queue_redraw()


func _draw() -> void:
	var amber: Color = Color(0.85, 0.65, 0.15, 0.7)
	var amber_dark: Color = Color(0.7, 0.5, 0.1, 0.8)
	var amber_highlight: Color = Color(0.95, 0.8, 0.3, 0.5)

	# Main sticky pool
	draw_rect(Rect2(0.0, 0.0, zone_width, zone_height), amber)

	# Darker edges
	draw_rect(Rect2(0.0, 0.0, 2.0, zone_height), amber_dark)
	draw_rect(Rect2(zone_width - 2.0, 0.0, 2.0, zone_height), amber_dark)

	# Glossy highlight
	draw_rect(Rect2(zone_width * 0.2, 2.0, zone_width * 0.3, 3.0), amber_highlight)

	# Stretchy strings to players inside
	for body: Node2D in _players_inside:
		if not is_instance_valid(body):
			continue
		var local_pos: Vector2 = to_local(body.global_position)
		var base_x: float = clampf(local_pos.x, 0.0, zone_width)
		var string_base: Vector2 = Vector2(base_x, zone_height / 2.0)
		draw_line(string_base, local_pos, Color(0.8, 0.6, 0.1, 0.4), 1.0)


func _on_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D:
		_players_inside.append(body)


func _on_body_exited(body: Node2D) -> void:
	if body is CharacterBody2D:
		_player_positions.erase(body.get_instance_id())
	_players_inside.erase(body)
