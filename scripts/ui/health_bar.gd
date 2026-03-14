extends Node2D

## A small health bar that floats above an entity.
## Draws itself using _draw() for pixel-perfect look.

@export var bar_width: float = 24.0
@export var bar_height: float = 3.0
@export var bar_offset: Vector2 = Vector2(0, -20)
@export var fill_color: Color = Color(0.1, 0.9, 0.1)
@export var damage_color: Color = Color(0.9, 0.1, 0.1)
@export var bg_color: Color = Color(0.15, 0.15, 0.15)
@export var border_color: Color = Color(0.0, 0.0, 0.0)
@export var hide_when_full: bool = false

var max_value: float = 100.0
var current_value: float = 100.0
var _display_value: float = 100.0  # Smoothly animated


func _ready() -> void:
	position = bar_offset
	z_index = 5


func _process(delta: float) -> void:
	# Smooth the bar drain
	_display_value = move_toward(_display_value, current_value, max_value * delta * 3.0)

	if hide_when_full and current_value >= max_value:
		visible = false
	else:
		visible = true

	queue_redraw()


func set_health(current: float, maximum: float) -> void:
	max_value = maximum
	current_value = clampf(current, 0.0, maximum)


func _draw() -> void:
	if max_value <= 0.0:
		return

	var half_w := bar_width / 2.0
	var rect := Rect2(-half_w, 0, bar_width, bar_height)

	# Border
	draw_rect(Rect2(rect.position - Vector2(1, 1), rect.size + Vector2(2, 2)), border_color)

	# Background
	draw_rect(rect, bg_color)

	# Damage trail (shows where health was)
	var display_ratio := clampf(_display_value / max_value, 0.0, 1.0)
	var display_rect := Rect2(-half_w, 0, bar_width * display_ratio, bar_height)
	draw_rect(display_rect, damage_color)

	# Current health
	var fill_ratio := clampf(current_value / max_value, 0.0, 1.0)
	var fill_rect := Rect2(-half_w, 0, bar_width * fill_ratio, bar_height)

	# Color shifts from green to yellow to red
	var color := fill_color
	if fill_ratio < 0.5:
		color = damage_color.lerp(Color.YELLOW, fill_ratio * 2.0)
	elif fill_ratio < 0.8:
		color = Color.YELLOW.lerp(fill_color, (fill_ratio - 0.5) / 0.3)

	draw_rect(fill_rect, color)
