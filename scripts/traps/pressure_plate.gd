extends Area2D

## Pressure plate that detects players standing on it and triggers connected traps.

signal activated
signal deactivated

@export var plate_width: float = 32.0
@export var plate_height: float = 6.0
@export var connected_trap_path: NodePath

var _is_pressed: bool = false
var _bodies_on_plate: int = 0

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2

	var col: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(plate_width, plate_height)
	col.shape = shape
	col.position = Vector2(plate_width / 2.0, plate_height / 2.0)
	add_child(col)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	queue_redraw()


func _draw() -> void:
	var offset_y: float = 0.0
	var color: Color = Color(0.5, 0.5, 0.52, 1.0)

	if _is_pressed:
		offset_y = 2.0
		color = Color(0.4, 0.4, 0.42, 1.0)

	# Plate base (recessed area)
	draw_rect(Rect2(0.0, 0.0, plate_width, plate_height), Color(0.3, 0.3, 0.32, 1.0))

	# Plate surface
	draw_rect(Rect2(1.0, offset_y, plate_width - 2.0, plate_height - 2.0), color)

	# Highlight line on top
	var highlight: Color = Color(0.6, 0.6, 0.62, 1.0) if not _is_pressed else Color(0.45, 0.45, 0.47, 1.0)
	draw_line(Vector2(2.0, offset_y + 1.0), Vector2(plate_width - 2.0, offset_y + 1.0), highlight, 1.0)


func _on_body_entered(_body: Node2D) -> void:
	_bodies_on_plate += 1
	if not _is_pressed:
		_is_pressed = true
		queue_redraw()
		activated.emit()
		_trigger_connected_trap()


func _on_body_exited(_body: Node2D) -> void:
	_bodies_on_plate -= 1
	if _bodies_on_plate <= 0:
		_bodies_on_plate = 0
		_is_pressed = false
		queue_redraw()
		deactivated.emit()


func _trigger_connected_trap() -> void:
	if connected_trap_path == NodePath():
		return
	var trap: Node = get_node_or_null(connected_trap_path)
	if trap == null:
		return
	if trap.has_method("trigger"):
		trap.trigger()
