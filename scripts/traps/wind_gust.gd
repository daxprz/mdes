extends Area2D

## Wind zone that pushes players in a configurable direction.
## Intermittently active with on/off cycling.

@export var push_direction: Vector2 = Vector2(1.0, 0.0)
@export var force: float = 200.0
@export var zone_width: float = 64.0
@export var zone_height: float = 96.0
@export var on_duration: float = 2.0
@export var off_duration: float = 1.5

var _time: float = 0.0
var _is_active: bool = true
var _cycle_timer: float = 0.0
var _players_inside: Array[Node2D] = []
var _line_offsets: Array[float] = []

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

	# Pre-generate line offsets for visual variety
	for i: int in range(6):
		_line_offsets.append(randf() * zone_height)


func _process(delta: float) -> void:
	_time += delta
	_cycle_timer += delta

	# Handle on/off cycling
	if _is_active:
		if _cycle_timer >= on_duration:
			_is_active = false
			_cycle_timer = 0.0
	else:
		if _cycle_timer >= off_duration:
			_is_active = true
			_cycle_timer = 0.0

	# Apply force to players
	if _is_active:
		var normalized_dir: Vector2 = push_direction.normalized()
		for body: Node2D in _players_inside:
			if not is_instance_valid(body):
				continue
			if body is CharacterBody2D:
				var char_body: CharacterBody2D = body as CharacterBody2D
				char_body.velocity += normalized_dir * force * delta

	queue_redraw()


func _draw() -> void:
	# Zone background
	var bg_alpha: float = 0.08 if _is_active else 0.03
	draw_rect(Rect2(0.0, 0.0, zone_width, zone_height), Color(0.7, 0.85, 1.0, bg_alpha))

	if not _is_active:
		return

	# Animated directional lines
	var dir: Vector2 = push_direction.normalized()
	var line_color: Color = Color(0.7, 0.85, 1.0, 0.3)

	for i: int in range(_line_offsets.size()):
		var base_offset: float = _line_offsets[i]
		# Animate lines along push direction
		var anim_offset: float = fmod(_time * 60.0 + float(i) * 20.0, zone_width + 20.0) - 10.0

		var start: Vector2
		var end: Vector2

		if absf(dir.x) > absf(dir.y):
			# Horizontal wind
			start = Vector2(anim_offset, base_offset)
			end = start + dir * 15.0
		else:
			# Vertical wind
			start = Vector2(base_offset * (zone_width / zone_height), anim_offset)
			end = start + dir * 15.0

		# Clip to zone bounds
		if start.x >= 0.0 and start.x <= zone_width and start.y >= 0.0 and start.y <= zone_height:
			draw_line(start, end, line_color, 1.0)

	# Draw small arrow indicators
	var arrow_alpha: float = 0.2 + sin(_time * 3.0) * 0.1
	var arrow_color: Color = Color(0.7, 0.85, 1.0, arrow_alpha)
	var center: Vector2 = Vector2(zone_width / 2.0, zone_height / 2.0)
	var arrow_end: Vector2 = center + dir * 12.0
	draw_line(center, arrow_end, arrow_color, 2.0)
	# Arrowhead
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	draw_line(arrow_end, arrow_end - dir * 5.0 + perp * 3.0, arrow_color, 2.0)
	draw_line(arrow_end, arrow_end - dir * 5.0 - perp * 3.0, arrow_color, 2.0)


func _on_body_entered(body: Node2D) -> void:
	_players_inside.append(body)


func _on_body_exited(body: Node2D) -> void:
	_players_inside.erase(body)
