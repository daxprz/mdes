extends CharacterBody2D

## Fairy Cake Bat - a flying cupcake with bat wings that moves in a sine wave
## and dive-bombs players when close.

signal died(global_pos: Vector2)

const MAX_HEALTH := 15
const HORIZONTAL_SPEED := 70.0
const SINE_AMPLITUDE := 40.0
const SINE_FREQUENCY := 2.0
const DIVE_DAMAGE := 8
const DIVE_SPEED := 180.0
const DIVE_COOLDOWN := 3.0
const DETECTION_RANGE := 100.0
const CONTACT_DAMAGE := 5

enum State { FLOAT, DIVE, RETURN, HURT, DEAD }

var health := MAX_HEALTH
var patrol_direction := 1.0
var _patrol_distance := 100.0
var _start_x := 0.0
var _start_y := 0.0
var _state: State = State.FLOAT
var _time := 0.0
var _dive_timer := 0.0
var _hurt_timer := 0.0
var _target: Node2D = null
var _anim_timer := 0.0
var _dive_origin_y := 0.0
var _wing_phase := 0.0

const HEALTH_BAR_SCENE := preload("res://scenes/ui/health_bar.tscn")

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var hitbox: Area2D = $Hitbox

var _health_bar: Node2D = null


func _ready() -> void:
	add_to_group("enemies")
	_start_x = global_position.x
	_start_y = global_position.y
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

	# No gravity for flying enemy
	_dive_timer -= delta
	_hurt_timer -= delta
	_time += delta
	_wing_phase += delta * 10.0

	if _hurt_timer > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, 200.0 * delta)
		velocity.y = move_toward(velocity.y, 0.0, 200.0 * delta)
		move_and_slide()
		queue_redraw()
		return

	_target = _find_nearest_player()

	match _state:
		State.FLOAT:
			_do_float(delta)
		State.DIVE:
			_do_dive(delta)
		State.RETURN:
			_do_return(delta)

	_animate(delta)
	move_and_slide()
	queue_redraw()


func _do_float(delta: float) -> void:
	# Horizontal patrol
	velocity.x = HORIZONTAL_SPEED * patrol_direction

	if abs(global_position.x - _start_x) > _patrol_distance:
		patrol_direction *= -1.0

	# Sine wave vertical movement
	var target_y: float = _start_y + sin(_time * SINE_FREQUENCY) * SINE_AMPLITUDE
	velocity.y = (target_y - global_position.y) * 5.0

	# Check for dive-bomb opportunity
	if _target and _dive_timer <= 0.0:
		var dist: float = global_position.distance_to(_target.global_position)
		if dist < DETECTION_RANGE:
			_state = State.DIVE
			_dive_origin_y = global_position.y
			_dive_timer = DIVE_COOLDOWN


func _do_dive(delta: float) -> void:
	if not _target:
		_state = State.RETURN
		return

	var dir: Vector2 = (_target.global_position - global_position)
	if dir.length() > 5.0:
		var norm: Vector2 = dir.normalized()
		velocity = norm * DIVE_SPEED
	else:
		# Reached target area, start returning
		_state = State.RETURN

	# Also transition to return if we've gone too far below origin
	if global_position.y > _dive_origin_y + 120.0:
		_state = State.RETURN


func _do_return(delta: float) -> void:
	# Fly back up to sine wave altitude
	var target_y: float = _start_y + sin(_time * SINE_FREQUENCY) * SINE_AMPLITUDE
	var diff_y: float = target_y - global_position.y

	velocity.y = diff_y * 3.0
	velocity.x = HORIZONTAL_SPEED * patrol_direction

	if absf(diff_y) < 10.0:
		_state = State.FLOAT


func _draw() -> void:
	if _state == State.DEAD:
		return

	# Cupcake body - pink/brown
	# Brown base (cupcake wrapper)
	draw_rect(Rect2(-8, -2, 16, 10), Color(0.55, 0.35, 0.2))
	# Pink frosting top (circle)
	draw_circle(Vector2(0, -4), 10, Color(1.0, 0.6, 0.75))
	# Cherry on top
	draw_circle(Vector2(0, -12), 3, Color(0.9, 0.15, 0.2))

	# Bat wings (flapping triangles)
	var wing_y: float = sin(_wing_phase) * 4.0
	# Left wing
	var left_wing := PackedVector2Array([
		Vector2(-10, -4),
		Vector2(-26, -10 + wing_y),
		Vector2(-14, 2 + wing_y),
	])
	draw_polygon(left_wing, PackedColorArray([Color(0.35, 0.2, 0.35)]))
	# Right wing
	var right_wing := PackedVector2Array([
		Vector2(10, -4),
		Vector2(26, -10 + wing_y),
		Vector2(14, 2 + wing_y),
	])
	draw_polygon(right_wing, PackedColorArray([Color(0.35, 0.2, 0.35)]))


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
		var dmg: int = DIVE_DAMAGE if _state == State.DIVE else CONTACT_DAMAGE
		PlayerManager.damage_player(player_index, dmg)
		if body.has_method("take_damage"):
			body.take_damage(dmg, -1)
