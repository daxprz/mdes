extends CharacterBody2D

## Peppermint Roller - rolls along platforms, bounces off walls, speeds up with each bounce.
## Deals more damage the faster it goes.

signal died(global_pos: Vector2)

const MAX_HEALTH := 18
const GRAVITY := 800.0
const INITIAL_SPEED := 60.0
const SPEED_INCREASE_PER_BOUNCE := 10.0
const MAX_SPEED := 200.0
const BASE_CONTACT_DAMAGE := 10
const DAMAGE_PER_SPEED := 0.05  # +1 damage per 20 speed

var health := MAX_HEALTH
var patrol_direction := 1.0
var _patrol_distance := 100.0
var _start_x := 0.0
var _current_speed := INITIAL_SPEED
var _dead := false
var _hurt_timer := 0.0
var _anim_timer := 0.0
var _roll_angle := 0.0
var _bounce_cooldown := 0.0

const HEALTH_BAR_SCENE := preload("res://scenes/ui/health_bar.tscn")

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var hitbox: Area2D = $Hitbox

var _health_bar: Node2D = null


func _ready() -> void:
	add_to_group("enemies")
	_start_x = global_position.x
	if hitbox:
		hitbox.body_entered.connect(_on_hitbox_body_entered)
	_health_bar = HEALTH_BAR_SCENE.instantiate()
	_health_bar.bar_width = 18.0
	_health_bar.bar_height = 2.0
	_health_bar.bar_offset = Vector2(0, -18)
	_health_bar.fill_color = Color(0.9, 0.2, 0.2)
	add_child(_health_bar)
	_health_bar.set_health(health, MAX_HEALTH)


func _physics_process(delta: float) -> void:
	if _dead:
		return

	# Gravity
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	else:
		velocity.y = 0.0

	_hurt_timer -= delta
	_bounce_cooldown -= delta

	if _hurt_timer > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, 200.0 * delta)
		move_and_slide()
		queue_redraw()
		return

	# Roll continuously
	velocity.x = _current_speed * patrol_direction

	# Bounce off walls - speed up (with cooldown to prevent stuck toggling)
	if is_on_wall() and _bounce_cooldown <= 0.0:
		patrol_direction *= -1.0
		_current_speed = minf(_current_speed + SPEED_INCREASE_PER_BOUNCE, MAX_SPEED)
		_bounce_cooldown = 0.15  # Minimum time between bounces
		# Push away from wall to prevent getting stuck
		global_position.x += patrol_direction * 4.0
		AudioManager.play("enemy_hit", -8.0, 1.3)

	# Rotation based on speed
	_roll_angle += _current_speed * patrol_direction * delta * 0.1

	_animate(delta)
	move_and_slide()
	queue_redraw()


func _draw() -> void:
	if _dead:
		return

	# Peppermint circle with red/white stripes
	var radius := 12.0
	draw_circle(Vector2.ZERO, radius, Color.WHITE)

	# Draw red stripes (6 segments, alternating)
	for i in range(6):
		var angle_start: float = _roll_angle + i * TAU / 6.0
		var angle_end: float = angle_start + TAU / 12.0
		var p1 := Vector2.ZERO
		var p2 := Vector2(cos(angle_start), sin(angle_start)) * radius
		var p3 := Vector2(cos(angle_end), sin(angle_end)) * radius
		draw_polygon(
			PackedVector2Array([p1, p2, p3]),
			PackedColorArray([Color(0.85, 0.15, 0.15)])
		)

	# Center dot
	draw_circle(Vector2.ZERO, 3, Color(0.9, 0.2, 0.2))

	# Outline
	draw_arc(Vector2.ZERO, radius, 0, TAU, 32, Color(0.7, 0.1, 0.1), 1.5)


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
	if _dead:
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
	velocity.y = -100.0

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
	_dead = true
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
	if _dead:
		return
	if "player_index" in body or body.has_meta("player_index"):
		var player_index: int = body.get("player_index") if "player_index" in body else body.get_meta("player_index")
		var dmg: int = int(BASE_CONTACT_DAMAGE + _current_speed * DAMAGE_PER_SPEED)
		PlayerManager.damage_player(player_index, dmg)
		if body.has_method("take_damage"):
			body.take_damage(dmg, -1)
