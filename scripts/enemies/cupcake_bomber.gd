extends CharacterBody2D

## Cupcake Bomber - flying enemy that hovers above platforms and drops
## frosting bombs that create slow puddles on the ground.

signal died(global_pos: Vector2)

const MAX_HEALTH := 20
const PATROL_SPEED := 50.0
const Y_OFFSET := -80.0
const BOMB_INTERVAL := 3.0
const BOMB_GRAVITY := 300.0
const BOMB_DAMAGE := 8
const PUDDLE_RADIUS := 40.0
const PUDDLE_DURATION := 4.0
const PUDDLE_SLOW_FACTOR := 0.4
const CONTACT_DAMAGE := 5

enum State { PATROL, HURT, DEAD }

var health := MAX_HEALTH
var patrol_direction := 1.0
var _patrol_distance := 100.0
var _start_x := 0.0
var _start_y := 0.0
var _state: State = State.PATROL
var _bomb_timer := BOMB_INTERVAL
var _hurt_timer := 0.0
var _anim_timer := 0.0
var _wing_phase := 0.0

const HEALTH_BAR_SCENE := preload("res://scenes/ui/health_bar.tscn")

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var hitbox: Area2D = $Hitbox

var _health_bar: Node2D = null


func _ready() -> void:
	add_to_group("enemies")
	_start_x = global_position.x
	_start_y = global_position.y + Y_OFFSET
	global_position.y += Y_OFFSET
	if hitbox:
		hitbox.body_entered.connect(_on_hitbox_body_entered)
	_health_bar = HEALTH_BAR_SCENE.instantiate()
	_health_bar.bar_width = 18.0
	_health_bar.bar_height = 2.0
	_health_bar.bar_offset = Vector2(0, -20)
	_health_bar.fill_color = Color(1.0, 0.5, 0.7)
	add_child(_health_bar)
	_health_bar.set_health(health, MAX_HEALTH)


func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return

	# No gravity - flying enemy
	_hurt_timer -= delta
	_bomb_timer -= delta
	_wing_phase += delta * 10.0

	if _hurt_timer > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, 200.0 * delta)
		velocity.y = move_toward(velocity.y, 0.0, 200.0 * delta)
		move_and_slide()
		queue_redraw()
		return

	# Hover at target y
	var target_y: float = _start_y + sin(_wing_phase * 0.3) * 8.0
	velocity.y = (target_y - global_position.y) * 5.0

	# Horizontal patrol
	velocity.x = PATROL_SPEED * patrol_direction
	if abs(global_position.x - _start_x) > _patrol_distance:
		patrol_direction *= -1.0

	# Drop bombs
	if _bomb_timer <= 0.0:
		_bomb_timer = BOMB_INTERVAL
		_drop_bomb()

	_animate(delta)
	move_and_slide()
	queue_redraw()


func _drop_bomb() -> void:
	var bomb := Area2D.new()
	bomb.collision_layer = 8
	bomb.collision_mask = 2
	bomb.global_position = global_position + Vector2(0, 10)

	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 5.0
	col.shape = shape
	bomb.add_child(col)

	var rect := ColorRect.new()
	rect.size = Vector2(8, 8)
	rect.position = Vector2(-4, -4)
	rect.color = Color(1.0, 0.4, 0.6)
	bomb.add_child(rect)

	bomb.set_meta("bomb_velocity_y", 0.0)
	bomb.set_meta("bomb_damage", BOMB_DAMAGE)

	bomb.body_entered.connect(_on_bomb_hit_body.bind(bomb))
	bomb.set_script(_get_bomb_script())

	get_tree().current_scene.add_child(bomb)


func _get_bomb_script() -> GDScript:
	# Inline script for bomb behavior
	var script := GDScript.new()
	script.source_code = '
extends Area2D

var bomb_velocity_y := 0.0
const BOMB_GRAVITY := 300.0
var _alive := true

func _physics_process(delta: float) -> void:
	if not _alive:
		return
	bomb_velocity_y += BOMB_GRAVITY * delta
	position.y += bomb_velocity_y * delta
	# Kill if offscreen
	if position.y > 3000.0:
		queue_free()
'
	script.reload()
	return script


func _on_bomb_hit_body(body: Node2D, bomb: Area2D) -> void:
	if not is_instance_valid(bomb):
		return

	# Check if hit a player
	if "player_index" in body or body.has_meta("player_index"):
		var pi: int = body.get("player_index") if "player_index" in body else body.get_meta("player_index")
		PlayerManager.damage_player(pi, BOMB_DAMAGE)
		if body.has_method("take_damage"):
			body.take_damage(BOMB_DAMAGE, -1)
		bomb.queue_free()
		return

	# Hit ground - create slow puddle
	_create_slow_puddle(bomb.global_position)
	bomb.queue_free()


func _create_slow_puddle(pos: Vector2) -> void:
	var puddle := Area2D.new()
	puddle.collision_layer = 0
	puddle.collision_mask = 2
	puddle.global_position = pos

	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = PUDDLE_RADIUS
	col.shape = shape
	puddle.add_child(col)

	var rect := ColorRect.new()
	rect.size = Vector2(PUDDLE_RADIUS * 2, 6)
	rect.position = Vector2(-PUDDLE_RADIUS, -3)
	rect.color = Color(1.0, 0.5, 0.8, 0.5)
	puddle.add_child(rect)

	puddle.body_entered.connect(_on_puddle_body_entered)
	get_tree().current_scene.add_child(puddle)

	# Remove puddle after duration
	get_tree().create_timer(PUDDLE_DURATION).timeout.connect(puddle.queue_free)


func _on_puddle_body_entered(body: Node2D) -> void:
	if body.has_method("apply_slow"):
		body.apply_slow(PUDDLE_DURATION * PUDDLE_SLOW_FACTOR)


func _draw() -> void:
	if _state == State.DEAD:
		return

	# Pink cupcake body
	draw_rect(Rect2(-9, -2, 18, 10), Color(0.55, 0.35, 0.2))
	draw_circle(Vector2(0, -5), 11, Color(1.0, 0.55, 0.75))
	draw_circle(Vector2(0, -14), 3, Color(0.9, 0.15, 0.2))

	# Wings
	var wing_y: float = sin(_wing_phase) * 5.0
	var left_wing := PackedVector2Array([
		Vector2(-11, -5),
		Vector2(-28, -12 + wing_y),
		Vector2(-15, 3 + wing_y),
	])
	draw_polygon(left_wing, PackedColorArray([Color(0.9, 0.7, 0.8)]))
	var right_wing := PackedVector2Array([
		Vector2(11, -5),
		Vector2(28, -12 + wing_y),
		Vector2(15, 3 + wing_y),
	])
	draw_polygon(right_wing, PackedColorArray([Color(0.9, 0.7, 0.8)]))


func _animate(delta: float) -> void:
	if not sprite:
		return
	sprite.flip_h = patrol_direction < 0
	_anim_timer += delta
	if _anim_timer >= 0.15:
		_anim_timer -= 0.15
		sprite.frame = (sprite.frame + 1) % 4


func _find_nearest_player() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := INF
	for p in get_tree().get_nodes_in_group("players"):
		if p is Node2D:
			var dist: float = global_position.distance_to(p.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = p
	return nearest


func set_patrol_distance(dist: float) -> void:
	_patrol_distance = dist


func take_damage(amount: int, _source_index: int = -1) -> void:
	if _state == State.DEAD:
		return
	# Rift tentacle absorbs damage first
	if has_meta("rift_tentacle"):
		var tentacle: Node2D = get_meta("rift_tentacle")
		if is_instance_valid(tentacle) and tentacle.has_method("take_tentacle_damage"):
			amount = tentacle.take_tentacle_damage(amount)
			if amount <= 0:
				return
		else:
			remove_meta("rift_tentacle")
			remove_meta("rift_attached")
	health -= amount
	if _health_bar:
		_health_bar.set_health(health, MAX_HEALTH)

	_hurt_timer = 0.2
	var kb_dir: float = -patrol_direction
	velocity.x = kb_dir * 120.0
	velocity.y = -80.0

	AudioManager.play("enemy_hit", -3.0)
	_flash_hit()

	if health <= 0:
		_die()


func _flash_hit() -> void:
	if sprite:
		sprite.modulate = Color.RED
		var tween := create_tween()
		tween.tween_property(sprite, "modulate", Color.WHITE, 0.15)


func _die() -> void:
	_state = State.DEAD
	AudioManager.play("enemy_die")
	died.emit(global_position)

	collision_shape.set_deferred("disabled", true)
	if hitbox:
		hitbox.set_deferred("monitoring", false)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(0.1, 0.1), 0.3)
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.chain().tween_callback(queue_free)


func apply_knockback(force: Vector2) -> void:
	velocity = force
	_hurt_timer = 0.2


func apply_slow(duration: float) -> void:
	if is_inside_tree():
		_hurt_timer = duration


func _on_hitbox_body_entered(body: Node2D) -> void:
	if _state == State.DEAD:
		return
	if "player_index" in body or body.has_meta("player_index"):
		var player_index: int = body.get("player_index") if "player_index" in body else body.get_meta("player_index")
		PlayerManager.damage_player(player_index, CONTACT_DAMAGE)
		if body.has_method("take_damage"):
			body.take_damage(CONTACT_DAMAGE, -1)
