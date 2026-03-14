extends StaticBody2D

## Wall-mounted arrow trap that fires projectiles at regular intervals.

@export var fire_interval: float = 2.5
@export var arrow_speed: float = 300.0
@export var arrow_damage: int = 10
@export var arrow_lifetime: float = 3.0
@export var direction: int = -1  ## -1 = left, 1 = right
@export var warning_duration: float = 0.3

var _timer: float = 0.0
var _warning: bool = false
var _warning_timer: float = 0.0
var _block_size: Vector2 = Vector2(16.0, 16.0)

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0

	# Collision shape for the stone block
	var col: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = _block_size
	col.shape = shape
	add_child(col)

	queue_redraw()


func _process(delta: float) -> void:
	_timer += delta

	var time_until_fire: float = fire_interval - _timer
	if time_until_fire <= warning_duration and not _warning:
		_warning = true
		queue_redraw()

	if _timer >= fire_interval:
		_timer = 0.0
		_warning = false
		_fire_arrow()
		queue_redraw()


func _draw() -> void:
	# Stone block
	var block_color: Color = Color(0.45, 0.42, 0.4, 1.0)
	draw_rect(Rect2(-_block_size / 2.0, _block_size), block_color)

	# Dark hole
	var hole_offset_x: float = float(direction) * 2.0
	draw_rect(Rect2(Vector2(hole_offset_x - 3.0, -3.0), Vector2(6.0, 6.0)), Color(0.15, 0.12, 0.1, 1.0))

	# Warning glow
	if _warning:
		var glow_color: Color = Color(1.0, 0.2, 0.1, 0.6)
		draw_circle(Vector2(hole_offset_x, 0.0), 5.0, glow_color)


func _fire_arrow() -> void:
	var arrow: Area2D = Area2D.new()
	arrow.collision_layer = 0
	arrow.collision_mask = 2
	arrow.position = global_position + Vector2(float(direction) * (_block_size.x / 2.0 + 4.0), 0.0)

	var col: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(10.0, 3.0)
	col.shape = shape
	arrow.add_child(col)

	var script: GDScript = GDScript.new()
	script.source_code = _get_arrow_script()
	script.reload()
	arrow.set_script(script)
	arrow.set("speed", arrow_speed * float(direction))
	arrow.set("damage", arrow_damage)
	arrow.set("lifetime", arrow_lifetime)

	get_tree().current_scene.add_child(arrow)


func _get_arrow_script() -> String:
	return """extends Area2D

var speed: float = 0.0
var damage: int = 10
var lifetime: float = 3.0
var _age: float = 0.0
var _arrow_color: Color = Color(0.55, 0.35, 0.15, 1.0)

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	position.x += speed * delta
	_age += delta
	if _age >= lifetime:
		queue_free()
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(-5.0, -1.5, 10.0, 3.0), _arrow_color)
	var tip_dir: float = signf(speed)
	var tip: PackedVector2Array = PackedVector2Array([
		Vector2(5.0 * tip_dir, -3.0),
		Vector2(8.0 * tip_dir, 0.0),
		Vector2(5.0 * tip_dir, 3.0),
	])
	draw_polygon(tip, PackedColorArray([Color(0.4, 0.4, 0.42), Color(0.4, 0.4, 0.42), Color(0.4, 0.4, 0.42)]))

func _on_body_entered(body: Node2D) -> void:
	if body.has_method(\"take_damage\"):
		body.take_damage(damage)
		AudioManager.play(\"player_hurt\")
	queue_free()
"""
