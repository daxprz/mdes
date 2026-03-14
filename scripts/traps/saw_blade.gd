extends Node2D

## Rotating saw blade that orbits an anchor point, dealing damage on contact.

@export var damage: int = 20
@export var hit_cooldown: float = 0.5
@export var chain_length: float = 60.0
@export var rotation_speed: float = 2.0

var _angle: float = 0.0
var _hit_timers: Dictionary = {}
var _blade_area: Area2D
var _blade_radius: float = 10.0

func _ready() -> void:
	_blade_area = Area2D.new()
	_blade_area.collision_layer = 0
	_blade_area.collision_mask = 2
	add_child(_blade_area)

	var col: CollisionShape2D = CollisionShape2D.new()
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = _blade_radius
	col.shape = shape
	_blade_area.add_child(col)

	_blade_area.body_entered.connect(_on_body_entered)

	queue_redraw()


func _process(delta: float) -> void:
	_angle += rotation_speed * delta

	# Position the blade area at the end of the chain
	var blade_pos: Vector2 = Vector2(
		cos(_angle) * chain_length,
		sin(_angle) * chain_length
	)
	_blade_area.position = blade_pos

	# Update cooldowns
	var keys_to_remove: Array = []
	for player_id: int in _hit_timers:
		_hit_timers[player_id] -= delta
		if _hit_timers[player_id] <= 0.0:
			keys_to_remove.append(player_id)
	for key: int in keys_to_remove:
		_hit_timers.erase(key)

	# Check for overlapping players
	for body: Node2D in _blade_area.get_overlapping_bodies():
		_try_damage(body)

	queue_redraw()


func _draw() -> void:
	var anchor_color: Color = Color(0.4, 0.4, 0.45, 1.0)
	var chain_color: Color = Color(0.5, 0.5, 0.55, 1.0)
	var blade_color: Color = Color(0.7, 0.7, 0.75, 1.0)
	var blade_edge_color: Color = Color(0.85, 0.85, 0.9, 1.0)

	var blade_pos: Vector2 = Vector2(
		cos(_angle) * chain_length,
		sin(_angle) * chain_length
	)

	# Draw anchor
	draw_circle(Vector2.ZERO, 5.0, anchor_color)

	# Draw chain
	draw_line(Vector2.ZERO, blade_pos, chain_color, 2.0)

	# Draw blade body
	draw_circle(blade_pos, _blade_radius, blade_color)

	# Draw jagged teeth around the blade
	var tooth_count: int = 8
	for i: int in range(tooth_count):
		var tooth_angle: float = _angle * 4.0 + float(i) * TAU / float(tooth_count)
		var inner: Vector2 = blade_pos + Vector2(cos(tooth_angle), sin(tooth_angle)) * _blade_radius
		var outer: Vector2 = blade_pos + Vector2(cos(tooth_angle), sin(tooth_angle)) * (_blade_radius + 4.0)
		var side_angle: float = tooth_angle + 0.3
		var side: Vector2 = blade_pos + Vector2(cos(side_angle), sin(side_angle)) * _blade_radius
		var points: PackedVector2Array = PackedVector2Array([inner, outer, side])
		draw_polygon(points, PackedColorArray([blade_edge_color, blade_edge_color, blade_edge_color]))


func _on_body_entered(body: Node2D) -> void:
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
