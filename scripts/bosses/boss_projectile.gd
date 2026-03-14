extends Area2D
class_name BossProjectile

## A configurable projectile fired by bosses.

@export var speed: float = 200.0
@export var damage: int = 10
@export var color: Color = Color.WHITE
@export var projectile_size: float = 6.0
@export var leave_puddle: bool = false
@export var puddle_duration: float = 4.0
@export var puddle_slow_factor: float = 0.4
@export var lifetime: float = 6.0

var direction := Vector2.RIGHT

var _time_alive := 0.0


func _ready() -> void:
	# Build visual
	var rect := ColorRect.new()
	rect.size = Vector2(projectile_size * 2, projectile_size * 2)
	rect.position = -Vector2(projectile_size, projectile_size)
	rect.color = color
	add_child(rect)

	# Build collision
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = projectile_size
	shape.shape = circle
	add_child(shape)

	# Collision setup
	collision_layer = 4   # Boss projectile layer
	collision_mask = 2    # Player layer
	body_entered.connect(_on_body_entered)

	modulate = color


func _physics_process(delta: float) -> void:
	position += direction * speed * delta

	_time_alive += delta
	if _time_alive >= lifetime:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("take_damage"):
		body.take_damage(damage)
	elif body.has_meta("player_index"):
		var idx: int = body.get_meta("player_index")
		PlayerManager.damage_player(idx, damage)

	if leave_puddle:
		_spawn_puddle()

	queue_free()


func _spawn_puddle() -> void:
	var puddle := Area2D.new()
	puddle.global_position = global_position

	# Visual
	var rect := ColorRect.new()
	rect.size = Vector2(40, 10)
	rect.position = Vector2(-20, -5)
	rect.color = Color(0.7, 0.85, 1.0, 0.6)  # Icy blue
	puddle.add_child(rect)

	# Collision
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(40, 10)
	shape.shape = box
	puddle.add_child(shape)

	puddle.collision_layer = 8  # Hazard layer
	puddle.collision_mask = 2   # Player layer
	puddle.set_meta("slow_factor", puddle_slow_factor)

	puddle.body_entered.connect(func(body: Node2D) -> void:
		if body.has_method("apply_slow"):
			body.apply_slow(puddle_slow_factor)
	)
	puddle.body_exited.connect(func(body: Node2D) -> void:
		if body.has_method("remove_slow"):
			body.remove_slow()
	)

	var scene := get_tree().current_scene
	if scene:
		scene.add_child(puddle)

	# Auto-remove puddle
	var tween := puddle.create_tween()
	tween.tween_interval(puddle_duration)
	tween.tween_property(rect, "modulate:a", 0.0, 0.5)
	tween.tween_callback(puddle.queue_free)
