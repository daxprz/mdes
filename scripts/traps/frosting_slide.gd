extends StaticBody2D

## Angled frosting-covered platform that causes players to slide downhill.

@export var slide_speed: float = 80.0
@export var slide_width: float = 120.0
@export var slide_height: float = 12.0
@export var slide_angle_deg: float = -20.0

var _collision_shape: CollisionShape2D
var _slide_area: Area2D
var _players_on_slide: Array[Node2D] = []

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0

	rotation = deg_to_rad(slide_angle_deg)

	# Physical collision shape
	_collision_shape = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(slide_width, slide_height)
	_collision_shape.shape = shape
	_collision_shape.position = Vector2(slide_width / 2.0, slide_height / 2.0)
	add_child(_collision_shape)

	# Area2D to detect players standing on it
	_slide_area = Area2D.new()
	_slide_area.collision_layer = 0
	_slide_area.collision_mask = 2
	add_child(_slide_area)

	var area_col: CollisionShape2D = CollisionShape2D.new()
	var area_shape: RectangleShape2D = RectangleShape2D.new()
	area_shape.size = Vector2(slide_width, slide_height + 8.0)
	area_col.shape = area_shape
	area_col.position = Vector2(slide_width / 2.0, slide_height / 2.0 - 4.0)
	_slide_area.add_child(area_col)

	_slide_area.body_entered.connect(_on_body_entered)
	_slide_area.body_exited.connect(_on_body_exited)

	queue_redraw()


func _process(_delta: float) -> void:
	# Push players in the downhill direction
	var slide_dir: float = signf(slide_angle_deg)
	if slide_dir == 0.0:
		return

	for body: Node2D in _players_on_slide:
		if not is_instance_valid(body):
			continue
		if body is CharacterBody2D:
			var char_body: CharacterBody2D = body as CharacterBody2D
			char_body.velocity.x += slide_dir * slide_speed * 0.1


func _draw() -> void:
	var base_color: Color = Color(0.9, 0.92, 0.95, 1.0)
	var gloss_color: Color = Color(1.0, 1.0, 1.0, 0.5)
	var pastel_blue: Color = Color(0.8, 0.88, 0.95, 1.0)

	# Main platform body
	draw_rect(Rect2(0.0, 0.0, slide_width, slide_height), pastel_blue)

	# Glossy highlight stripe
	draw_rect(Rect2(0.0, 1.0, slide_width, 3.0), gloss_color)

	# Top frosting surface
	draw_rect(Rect2(0.0, 0.0, slide_width, 2.0), base_color)


func _on_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D:
		_players_on_slide.append(body)


func _on_body_exited(body: Node2D) -> void:
	_players_on_slide.erase(body)
