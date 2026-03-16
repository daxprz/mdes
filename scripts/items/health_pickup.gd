extends Area2D

## Green + shaped health pickup that sparkles and heals the player on contact.
## Spawned with a 25% chance when enemies die.

const HEAL_AMOUNT := 15
const LIFETIME := 30.0  # Despawn after this many seconds
const BOBBLE_SPEED := 3.0
const BOBBLE_HEIGHT := 4.0
const SPARKLE_INTERVAL := 0.3

var _collected := false
var _timer: float = 0.0
var _sparkle_timer: float = 0.0
var _start_y: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # Player layer
	body_entered.connect(_on_body_entered)

	# Collision shape
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 12.0
	shape.shape = circle
	add_child(shape)

	_start_y = position.y

	# Initial pop-up animation
	var launch_tween := create_tween()
	launch_tween.tween_property(self, "position:y", position.y - 30, 0.3).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if _collected:
		return

	_timer += delta
	_sparkle_timer += delta

	# Despawn after lifetime
	if _timer >= LIFETIME:
		_fade_out()
		return

	# Bobble up and down
	position.y = (_start_y - 30) + sin(_timer * BOBBLE_SPEED) * BOBBLE_HEIGHT

	# Spawn sparkle particles
	if _sparkle_timer >= SPARKLE_INTERVAL:
		_sparkle_timer = 0.0
		_spawn_sparkle()

	queue_redraw()


func _draw() -> void:
	if _collected:
		return

	# Green + shape
	var color := Color(0.2, 0.9, 0.3)
	var bright := Color(0.4, 1.0, 0.5)
	var pulse: float = 0.8 + 0.2 * sin(_timer * 5.0)

	# Vertical bar of the +
	draw_rect(Rect2(-3, -8, 6, 16), color * pulse)
	# Horizontal bar of the +
	draw_rect(Rect2(-8, -3, 16, 6), color * pulse)

	# Bright center
	draw_rect(Rect2(-2, -2, 4, 4), bright)

	# Outline glow
	draw_rect(Rect2(-4, -9, 8, 18), Color(0.1, 0.7, 0.2, 0.3), false, 1.0)
	draw_rect(Rect2(-9, -4, 18, 8), Color(0.1, 0.7, 0.2, 0.3), false, 1.0)


func _spawn_sparkle() -> void:
	var sparkle := ColorRect.new()
	sparkle.color = Color(0.3, 1.0, 0.4, 0.8)
	sparkle.size = Vector2(3, 3)
	sparkle.z_index = 3
	sparkle.position = global_position + Vector2(randf_range(-8, 8), randf_range(-8, 8)) - Vector2(1.5, 1.5)
	get_parent().add_child(sparkle)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(sparkle, "position:y", sparkle.position.y - 15, 0.5)
	tween.tween_property(sparkle, "modulate:a", 0.0, 0.5)
	tween.tween_property(sparkle, "scale", Vector2(0.3, 0.3), 0.5)
	tween.set_parallel(false)
	tween.tween_callback(sparkle.queue_free)


func _on_body_entered(body: Node2D) -> void:
	if _collected:
		return
	if not "player_index" in body and not body.has_meta("player_index"):
		return

	_collected = true
	var player_index: int = body.get("player_index") if "player_index" in body else body.get_meta("player_index")

	PlayerManager.heal_player(player_index, HEAL_AMOUNT)
	AudioManager.play("muffin_collect", -3.0, 1.3)

	_play_collect_effect()


func _play_collect_effect() -> void:
	# Green flash + expand
	for child in get_children():
		if child is CollisionShape2D:
			child.set_deferred("disabled", true)

	# Burst of green sparkles
	for i in range(6):
		var sparkle := ColorRect.new()
		sparkle.color = Color(0.3, 1.0, 0.4, 0.7)
		sparkle.size = Vector2(4, 4)
		sparkle.z_index = 4
		sparkle.position = global_position - Vector2(2, 2)
		get_parent().add_child(sparkle)

		var angle: float = randf() * TAU
		var dist: float = 15.0 + randf() * 20.0
		var target: Vector2 = global_position + Vector2(cos(angle), sin(angle)) * dist - Vector2(2, 2)

		var s_tween := create_tween()
		s_tween.set_parallel(true)
		s_tween.tween_property(sparkle, "position", target, 0.3)
		s_tween.tween_property(sparkle, "modulate:a", 0.0, 0.4)
		s_tween.set_parallel(false)
		s_tween.tween_callback(sparkle.queue_free)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(2.0, 2.0), 0.2)
	tween.tween_property(self, "modulate:a", 0.0, 0.2)
	tween.chain().tween_callback(queue_free)


func _fade_out() -> void:
	_collected = true
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.tween_callback(queue_free)


## Static helper: call from any enemy's _die() to maybe drop health
static func try_spawn(parent: Node, pos: Vector2) -> void:
	if randf() > 0.25:
		return  # 75% chance of no drop
	var pickup := Area2D.new()
	var script := load("res://scripts/items/health_pickup.gd")
	pickup.set_script(script)
	pickup.position = pos
	pickup.z_index = 3
	parent.add_child(pickup)
