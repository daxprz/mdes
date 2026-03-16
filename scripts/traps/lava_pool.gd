extends Area2D

## Lava pool that deals heavy continuous damage and applies upward knockback.

@export var damage: int = 30
@export var damage_interval: float = 0.3
@export var pool_width: float = 64.0
@export var pool_height: float = 12.0
@export var knockback_force: float = -250.0

var _time: float = 0.0
var _hit_timers: Dictionary = {}
var _players_inside: Array[Node2D] = []
var _sound_played: bool = false

func _ready() -> void:
	add_to_group("lava_traps")
	collision_layer = 0
	collision_mask = 2

	var col: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(pool_width, pool_height)
	col.shape = shape
	col.position = Vector2(pool_width / 2.0, pool_height / 2.0)
	add_child(col)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	_time += delta

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
		# Apply upward knockback
		if body is CharacterBody2D:
			var char_body: CharacterBody2D = body as CharacterBody2D
			char_body.velocity.y = knockback_force

	queue_redraw()


func _draw() -> void:
	# Base lava color
	var lava_dark: Color = Color(0.8, 0.2, 0.0, 1.0)
	var lava_bright: Color = Color(1.0, 0.5, 0.0, 1.0)

	# Draw base rectangle
	draw_rect(Rect2(0.0, 0.0, pool_width, pool_height), lava_dark)

	# Animated bright streaks
	for i: int in range(3):
		var offset_x: float = fmod(_time * 8.0 + float(i) * pool_width / 3.0, pool_width)
		var streak_width: float = 8.0 + sin(_time * 3.0 + float(i)) * 3.0
		draw_rect(Rect2(offset_x, 2.0, streak_width, pool_height - 4.0), lava_bright)

	# Animated bubbles using sin
	for i: int in range(5):
		var bx: float = fmod(float(i) * 13.7, pool_width)
		var bubble_phase: float = _time * 2.0 + float(i) * 1.3
		var by: float = pool_height / 2.0 + sin(bubble_phase) * (pool_height / 3.0)
		var bubble_r: float = 1.5 + sin(bubble_phase * 0.7) * 0.8
		var bubble_alpha: float = 0.5 + sin(bubble_phase) * 0.3
		draw_circle(Vector2(bx, by), bubble_r, Color(1.0, 0.7, 0.1, bubble_alpha))


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("take_damage"):
		_players_inside.append(body)
		if not _sound_played:
			AudioManager.play("explosion")
			_sound_played = true


func _on_body_exited(body: Node2D) -> void:
	_players_inside.erase(body)
	if _players_inside.is_empty():
		_sound_played = false
