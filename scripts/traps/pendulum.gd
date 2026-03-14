extends Node2D

## Swinging pendulum trap with a damaging blade at the end.
## Pivot is at the node's position (top).

@export var swing_speed: float = 2.0
@export var swing_angle: float = 60.0
@export var arm_length: float = 80.0
@export var damage: int = 20
@export var hit_cooldown: float = 1.0
@export var blade_radius: float = 10.0

var _time: float = 0.0
var _current_angle: float = 0.0
var _blade_area: Area2D
var _hit_timers: Dictionary = {}

func _ready() -> void:
	# Create blade hitbox at the end of the pendulum
	_blade_area = Area2D.new()
	_blade_area.collision_layer = 0
	_blade_area.collision_mask = 2
	add_child(_blade_area)

	var blade_shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = blade_radius
	blade_shape.shape = circle
	_blade_area.add_child(blade_shape)

	_blade_area.body_entered.connect(_on_blade_body_entered)

	_update_blade_position()


func _process(delta: float) -> void:
	_time += delta
	var max_rad: float = deg_to_rad(swing_angle / 2.0)
	_current_angle = sin(_time * swing_speed * TAU) * max_rad

	_update_blade_position()
	queue_redraw()

	# Update cooldown timers
	var keys_to_remove: Array = []
	for player_id: int in _hit_timers:
		_hit_timers[player_id] -= delta
		if _hit_timers[player_id] <= 0.0:
			keys_to_remove.append(player_id)
	for key: int in keys_to_remove:
		_hit_timers.erase(key)

	# Continuous overlap check
	for body: Node2D in _blade_area.get_overlapping_bodies():
		_try_damage(body)


func _update_blade_position() -> void:
	var blade_x: float = sin(_current_angle) * arm_length
	var blade_y: float = cos(_current_angle) * arm_length
	_blade_area.position = Vector2(blade_x, blade_y)


func _draw() -> void:
	var blade_pos: Vector2 = _blade_area.position

	# Draw chain links
	var chain_color: Color = Color(0.3, 0.3, 0.35, 1.0)
	var link_count: int = int(arm_length / 8.0)
	for i: int in range(link_count):
		var t: float = float(i) / float(link_count)
		var link_pos: Vector2 = blade_pos * t
		draw_circle(link_pos, 2.0, chain_color)

	# Draw chain line
	draw_line(Vector2.ZERO, blade_pos, chain_color, 2.0)

	# Draw pivot
	draw_circle(Vector2.ZERO, 4.0, Color(0.4, 0.4, 0.45, 1.0))

	# Draw blade (orange/red circle)
	draw_circle(blade_pos, blade_radius, Color(0.85, 0.25, 0.1, 1.0))
	draw_circle(blade_pos, blade_radius * 0.6, Color(0.95, 0.4, 0.15, 1.0))


func _on_blade_body_entered(body: Node2D) -> void:
	_try_damage(body)


func _try_damage(body: Node2D) -> void:
	if not body.has_method("take_damage"):
		return
	var id: int = body.get_instance_id()
	if _hit_timers.has(id):
		return
	_hit_timers[id] = hit_cooldown
	body.take_damage(damage)
	AudioManager.play("player_hurt")
