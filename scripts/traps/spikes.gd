extends StaticBody2D

## Row of triangular spikes that damage players on contact.
## Can be placed on floors, walls, or ceilings.

@export var damage: int = 15
@export var hit_cooldown: float = 0.5
@export var spike_count: int = 4
@export var spike_width: float = 12.0
@export var spike_height: float = 12.0

var _hit_timers: Dictionary = {}
var _hitbox: Area2D
var _collision_shape: CollisionShape2D

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0

	# Main collision shape for the base
	_collision_shape = CollisionShape2D.new()
	var base_shape: RectangleShape2D = RectangleShape2D.new()
	var total_width: float = spike_width * spike_count
	base_shape.size = Vector2(total_width, 4.0)
	_collision_shape.shape = base_shape
	_collision_shape.position = Vector2(total_width / 2.0, spike_height + 2.0)
	add_child(_collision_shape)

	# Hitbox Area2D for detecting players
	_hitbox = Area2D.new()
	_hitbox.collision_layer = 0
	_hitbox.collision_mask = 2
	add_child(_hitbox)

	var area_shape: CollisionShape2D = CollisionShape2D.new()
	var hitbox_rect: RectangleShape2D = RectangleShape2D.new()
	hitbox_rect.size = Vector2(total_width, spike_height)
	area_shape.shape = hitbox_rect
	area_shape.position = Vector2(total_width / 2.0, spike_height / 2.0)
	_hitbox.add_child(area_shape)

	_hitbox.body_entered.connect(_on_body_entered)
	_hitbox.body_exited.connect(_on_body_exited)

	queue_redraw()


func _draw() -> void:
	var base_color: Color = Color(0.6, 0.6, 0.65, 1.0)
	var tip_color: Color = Color(0.75, 0.75, 0.8, 1.0)
	var total_width: float = spike_width * spike_count

	# Draw base
	draw_rect(Rect2(0.0, spike_height, total_width, 4.0), base_color)

	# Draw triangular spikes
	for i: int in range(spike_count):
		var x_start: float = i * spike_width
		var points: PackedVector2Array = PackedVector2Array([
			Vector2(x_start, spike_height),
			Vector2(x_start + spike_width / 2.0, 0.0),
			Vector2(x_start + spike_width, spike_height),
		])
		var colors: PackedColorArray = PackedColorArray([tip_color, base_color, tip_color])
		draw_polygon(points, colors)


func _process(delta: float) -> void:
	# Update cooldown timers
	var keys_to_remove: Array = []
	for player_id: int in _hit_timers:
		_hit_timers[player_id] -= delta
		if _hit_timers[player_id] <= 0.0:
			keys_to_remove.append(player_id)
	for key: int in keys_to_remove:
		_hit_timers.erase(key)

	# Check for overlapping players and damage them
	for body: Node2D in _hitbox.get_overlapping_bodies():
		_try_damage(body)


func _on_body_entered(body: Node2D) -> void:
	_try_damage(body)


func _on_body_exited(_body: Node2D) -> void:
	pass


func _try_damage(body: Node2D) -> void:
	if not body.has_method("take_damage"):
		return
	var id: int = body.get_instance_id()
	if _hit_timers.has(id):
		return
	_hit_timers[id] = hit_cooldown
	body.take_damage(damage)
	AudioManager.play("player_hurt")
