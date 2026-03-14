extends Node2D

## Spawner that drops damaging rocks when triggered by proximity or signal.

@export var use_proximity_trigger: bool = true
@export var detection_range: float = 80.0
@export var rock_damage: int = 20
@export var rock_count_min: int = 3
@export var rock_count_max: int = 5
@export var rock_size: float = 16.0
@export var rock_lifetime: float = 3.0
@export var spread_width: float = 48.0
@export var warning_duration: float = 0.4

var _triggered: bool = false
var _warning_active: bool = false
var _warning_timer: float = 0.0
var _detection_area: Area2D
var _dust_particles: Array[Dictionary] = []

func _ready() -> void:
	if use_proximity_trigger:
		_detection_area = Area2D.new()
		_detection_area.collision_layer = 0
		_detection_area.collision_mask = 2
		add_child(_detection_area)

		var col: CollisionShape2D = CollisionShape2D.new()
		var shape: CircleShape2D = CircleShape2D.new()
		shape.radius = detection_range
		col.shape = shape
		_detection_area.add_child(col)

		_detection_area.body_entered.connect(_on_detection_body_entered)


func _process(delta: float) -> void:
	if _warning_active:
		_warning_timer -= delta
		# Update dust particles
		for p: Dictionary in _dust_particles:
			p["y"] += p["vy"] * delta
			p["x"] += p["vx"] * delta
			p["alpha"] -= delta * 1.5
		queue_redraw()
		if _warning_timer <= 0.0:
			_warning_active = false
			_spawn_rocks()


func _draw() -> void:
	if _warning_active:
		# Draw dust warning particles
		for p: Dictionary in _dust_particles:
			var alpha: float = maxf(p["alpha"], 0.0)
			if alpha > 0.0:
				draw_circle(Vector2(p["x"], p["y"]), 2.0, Color(0.6, 0.5, 0.4, alpha))

	# Draw ceiling indicator
	draw_rect(Rect2(-spread_width / 2.0, -4.0, spread_width, 4.0), Color(0.4, 0.38, 0.35, 0.5))


## Call this method to trigger the rock fall externally (e.g., from a pressure plate).
func trigger() -> void:
	if _triggered:
		return
	_triggered = true
	_start_warning()


func _on_detection_body_entered(_body: Node2D) -> void:
	trigger()


func _start_warning() -> void:
	_warning_active = true
	_warning_timer = warning_duration

	# Create dust particles
	_dust_particles.clear()
	for i: int in range(8):
		var p: Dictionary = {
			"x": randf_range(-spread_width / 2.0, spread_width / 2.0),
			"y": 0.0,
			"vx": randf_range(-10.0, 10.0),
			"vy": randf_range(10.0, 30.0),
			"alpha": 1.0,
		}
		_dust_particles.append(p)
	queue_redraw()


func _spawn_rocks() -> void:
	var count: int = randi_range(rock_count_min, rock_count_max)
	for i: int in range(count):
		var rock: RigidBody2D = RigidBody2D.new()
		rock.position = global_position + Vector2(randf_range(-spread_width / 2.0, spread_width / 2.0), 0.0)
		rock.collision_layer = 8
		rock.collision_mask = 1 | 2

		var col: CollisionShape2D = CollisionShape2D.new()
		var shape: RectangleShape2D = RectangleShape2D.new()
		shape.size = Vector2(rock_size, rock_size)
		col.shape = shape
		rock.add_child(col)

		# Damage hitbox
		var hitbox: Area2D = Area2D.new()
		hitbox.collision_layer = 0
		hitbox.collision_mask = 2
		rock.add_child(hitbox)

		var hit_col: CollisionShape2D = CollisionShape2D.new()
		var hit_shape: RectangleShape2D = RectangleShape2D.new()
		hit_shape.size = Vector2(rock_size, rock_size)
		hit_col.shape = hit_shape
		hitbox.add_child(hit_col)

		# Visual
		var rect: ColorRect = ColorRect.new()
		rect.size = Vector2(rock_size, rock_size)
		rect.position = Vector2(-rock_size / 2.0, -rock_size / 2.0)
		var brown_val: float = randf_range(0.35, 0.5)
		rect.color = Color(brown_val + 0.1, brown_val, brown_val - 0.05, 1.0)
		rock.add_child(rect)

		# Add rock script
		var script: GDScript = GDScript.new()
		script.source_code = _get_rock_script()
		script.reload()
		rock.set_script(script)
		rock.set("damage", rock_damage)
		rock.set("lifetime", rock_lifetime)

		# Small random initial velocity for spread
		rock.linear_velocity = Vector2(randf_range(-30.0, 30.0), randf_range(-20.0, 0.0))

		get_tree().current_scene.add_child(rock)

	AudioManager.play("explosion")


func _get_rock_script() -> String:
	return """extends RigidBody2D

var damage: int = 20
var lifetime: float = 3.0
var _age: float = 0.0
var _has_hit: bool = false

func _ready() -> void:
	add_to_group(\"enemies\")
	for child: Node in get_children():
		if child is Area2D:
			var area: Area2D = child as Area2D
			area.body_entered.connect(_on_hit_body)
			break

func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()

func _on_hit_body(body: Node2D) -> void:
	if _has_hit:
		return
	if body.has_method(\"take_damage\"):
		_has_hit = true
		body.take_damage(damage)
		AudioManager.play(\"player_hurt\")
		queue_free()
"""
