extends Area2D

## Rising chocolate lava that slowly climbs from the tower bottom, forcing players upward.

@export var damage: int = 25
@export var damage_interval: float = 0.5
@export var rise_speed: float = 8.0
@export var tower_height: float = 2400.0
@export var max_rise_fraction: float = 0.6
@export var lava_width: float = 400.0

var _time: float = 0.0
var _current_height: float = 0.0
var _max_height: float = 0.0
var _hit_timers: Dictionary = {}
var _players_inside: Array[Node2D] = []
var _col_shape: CollisionShape2D
var _rect_shape: RectangleShape2D

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2

	_max_height = tower_height * max_rise_fraction
	_current_height = 12.0  # Start as a thin layer

	_col_shape = CollisionShape2D.new()
	_rect_shape = RectangleShape2D.new()
	_rect_shape.size = Vector2(lava_width, _current_height)
	_col_shape.shape = _rect_shape
	_col_shape.position = Vector2(0.0, -_current_height / 2.0)
	add_child(_col_shape)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	_time += delta

	# Wait 15 seconds before rising
	if _time < 15.0:
		return

	# Rise the lava
	if _current_height < _max_height:
		_current_height += rise_speed * delta
		if _current_height > _max_height:
			_current_height = _max_height
		_rect_shape.size = Vector2(lava_width, _current_height)
		_col_shape.position = Vector2(0.0, -_current_height / 2.0)

	# Update cooldowns
	var keys_to_remove: Array = []
	for player_id: int in _hit_timers:
		_hit_timers[player_id] -= delta
		if _hit_timers[player_id] <= 0.0:
			keys_to_remove.append(player_id)
	for key: int in keys_to_remove:
		_hit_timers.erase(key)

	# Damage players inside
	for body: Node2D in _players_inside:
		if not is_instance_valid(body):
			continue
		var id: int = body.get_instance_id()
		if _hit_timers.has(id):
			continue
		_hit_timers[id] = damage_interval
		if body.has_method("take_damage"):
			body.take_damage(damage)
			AudioManager.play("player_hurt")

	queue_redraw()


func _draw() -> void:
	var choco_dark: Color = Color(0.25, 0.12, 0.05, 1.0)
	var choco_mid: Color = Color(0.35, 0.18, 0.08, 1.0)
	var choco_light: Color = Color(0.5, 0.28, 0.12, 1.0)

	# Draw main lava body (extends downward from position)
	var half_w: float = lava_width / 2.0
	draw_rect(Rect2(-half_w, -_current_height, lava_width, _current_height), choco_dark)

	# Surface line (lighter)
	draw_rect(Rect2(-half_w, -_current_height, lava_width, 4.0), choco_light)

	# Animated wavy surface
	var wave_segments: int = 20
	var seg_width: float = lava_width / float(wave_segments)
	for i: int in range(wave_segments):
		var sx: float = -half_w + float(i) * seg_width
		var wave_y: float = -_current_height + sin(_time * 2.0 + float(i) * 0.5) * 3.0
		draw_rect(Rect2(sx, wave_y, seg_width, 3.0), choco_mid)

	# Bubbles
	for i: int in range(8):
		var bx: float = -half_w + fmod(float(i) * 53.7, lava_width)
		var bubble_phase: float = _time * 1.5 + float(i) * 1.7
		var by: float = -_current_height + 10.0 + sin(bubble_phase) * 6.0
		var bubble_r: float = 2.0 + sin(bubble_phase * 0.8) * 1.0
		var bubble_alpha: float = 0.4 + sin(bubble_phase) * 0.2
		draw_circle(Vector2(bx, by), bubble_r, Color(0.55, 0.3, 0.12, bubble_alpha))


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("take_damage"):
		_players_inside.append(body)


func _on_body_exited(body: Node2D) -> void:
	_players_inside.erase(body)
