extends StaticBody2D

## Breakable sugar crystal barrier that blocks paths and drops muffins when destroyed.

@export var hp: int = 50
@export var max_hp: int = 50
@export var barrier_width: float = 32.0
@export var barrier_height: float = 48.0
@export var muffin_drop_count: int = 2

var _collision_shape: CollisionShape2D

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	max_hp = hp

	_collision_shape = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(barrier_width, barrier_height)
	_collision_shape.shape = shape
	_collision_shape.position = Vector2(barrier_width / 2.0, barrier_height / 2.0)
	add_child(_collision_shape)

	queue_redraw()


func take_damage(amount: int) -> void:
	hp -= amount
	AudioManager.play("player_hurt")
	queue_redraw()
	if hp <= 0:
		_shatter()


func _shatter() -> void:
	AudioManager.play("explosion")

	# Drop muffins
	var muffin_scene_path: String = "res://scenes/items/mini_muffin.tscn"
	var muffin_scene: Resource = load(muffin_scene_path)
	if muffin_scene:
		for i: int in range(muffin_drop_count):
			var muffin: Node2D = muffin_scene.instantiate()
			muffin.global_position = global_position + Vector2(
				randf_range(-15.0, 15.0),
				randf_range(-10.0, 10.0)
			)
			get_tree().current_scene.add_child(muffin)

	queue_free()


func _draw() -> void:
	var hp_ratio: float = float(hp) / float(max_hp)
	var base_color: Color = Color(0.4, 0.9, 0.95, 0.85)
	var highlight_color: Color = Color(0.85, 0.95, 1.0, 0.9)

	# Darken as damaged
	base_color = base_color.darkened(1.0 - hp_ratio)

	# Main crystal body
	draw_rect(Rect2(0.0, 0.0, barrier_width, barrier_height), base_color)

	# Vertical highlight facet
	draw_rect(Rect2(barrier_width * 0.3, 0.0, barrier_width * 0.15, barrier_height), highlight_color)

	# Crack lines at 50% HP
	if hp_ratio <= 0.5:
		var crack_color: Color = Color(0.2, 0.2, 0.25, 0.8)
		var cx: float = barrier_width * 0.5
		var cy: float = barrier_height * 0.5
		draw_line(Vector2(cx, cy - 10.0), Vector2(cx + 8.0, cy + 5.0), crack_color, 1.5)
		draw_line(Vector2(cx + 8.0, cy + 5.0), Vector2(cx - 3.0, cy + 15.0), crack_color, 1.5)

	# More cracks at 25% HP
	if hp_ratio <= 0.25:
		var crack_color2: Color = Color(0.15, 0.15, 0.2, 0.9)
		draw_line(Vector2(5.0, 10.0), Vector2(15.0, 25.0), crack_color2, 1.5)
		draw_line(Vector2(barrier_width - 5.0, barrier_height - 10.0),
			Vector2(barrier_width - 12.0, barrier_height - 25.0), crack_color2, 1.5)
