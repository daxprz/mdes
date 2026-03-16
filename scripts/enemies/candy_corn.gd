extends CharacterBody2D

## Candy Corn Spinner - ground enemy that winds up and spins rapidly to attack.
## Gets dizzy after spinning, taking extra damage.

signal died(global_pos: Vector2)

const MAX_HEALTH := 25
const GRAVITY := 800.0
const PATROL_SPEED := 40.0
const SPIN_SPEED := 60.0
const DETECTION_RANGE := 100.0
const SPIN_DAMAGE := 5
const SPIN_HIT_INTERVAL := 0.3
const WINDUP_DURATION := 0.5
const SPIN_DURATION := 2.0
const DIZZY_DURATION := 1.5
const SPIN_RADIUS := 35.0
const CONTACT_DAMAGE := 5

enum State { PATROL, CHASE, WINDUP, SPINNING, DIZZY, HURT, DEAD }

var health := MAX_HEALTH
var mass := 25.0
var patrol_direction := 1.0
var _patrol_distance := 100.0
var _start_x := 0.0
var _state: State = State.PATROL
var _hurt_timer := 0.0
var _anim_timer := 0.0
var _target: Node2D = null
var _windup_timer := 0.0
var _spin_timer := 0.0
var _spin_hit_timer := 0.0
var _dizzy_timer := 0.0
var _damage_multiplier := 1.0
var _rotation_angle := 0.0

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
	_health_bar.bar_width = 20.0
	_health_bar.bar_height = 2.0
	_health_bar.bar_offset = Vector2(0, -20)
	_health_bar.fill_color = Color(1.0, 0.7, 0.2)
	add_child(_health_bar)
	_health_bar.set_health(health, MAX_HEALTH)


func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return

	# Gravity
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	else:
		velocity.y = 0.0

	_hurt_timer -= delta

	if _hurt_timer > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, 200.0 * delta)
		move_and_slide()
		queue_redraw()
		return

	_target = _find_nearest_player()

	match _state:
		State.PATROL:
			_do_patrol(delta)
		State.CHASE:
			_do_chase(delta)
		State.WINDUP:
			_do_windup(delta)
		State.SPINNING:
			_do_spinning(delta)
		State.DIZZY:
			_do_dizzy(delta)

	_animate(delta)
	move_and_slide()
	queue_redraw()


func _do_patrol(delta: float) -> void:
	velocity.x = PATROL_SPEED * patrol_direction

	if is_on_wall():
		patrol_direction *= -1.0
	elif abs(global_position.x - _start_x) > _patrol_distance:
		patrol_direction *= -1.0

	if _target and global_position.distance_to(_target.global_position) < DETECTION_RANGE:
		_state = State.CHASE


func _do_chase(delta: float) -> void:
	if not _target:
		_state = State.PATROL
		return

	var dist: float = global_position.distance_to(_target.global_position)
	if dist > DETECTION_RANGE * 1.5:
		_state = State.PATROL
		return

	var dir: float = signf(_target.global_position.x - global_position.x)
	velocity.x = PATROL_SPEED * dir
	patrol_direction = dir

	# Start windup when close enough
	if dist < SPIN_RADIUS * 2.0:
		_state = State.WINDUP
		_windup_timer = WINDUP_DURATION
		velocity.x = 0.0


func _do_windup(delta: float) -> void:
	_windup_timer -= delta
	velocity.x = 0.0
	_rotation_angle += delta * 5.0  # Slow rotation during windup

	if _windup_timer <= 0.0:
		_state = State.SPINNING
		_spin_timer = SPIN_DURATION
		_spin_hit_timer = 0.0
		_damage_multiplier = 1.0


func _do_spinning(delta: float) -> void:
	_spin_timer -= delta
	_spin_hit_timer -= delta
	_rotation_angle += delta * 25.0  # Fast rotation

	# Move toward player while spinning
	if _target:
		var dir: float = signf(_target.global_position.x - global_position.x)
		velocity.x = SPIN_SPEED * dir
	else:
		velocity.x = SPIN_SPEED * patrol_direction

	# Deal damage periodically to nearby players
	if _spin_hit_timer <= 0.0:
		_spin_hit_timer = SPIN_HIT_INTERVAL
		for p in get_tree().get_nodes_in_group("players"):
			if p is Node2D:
				var dist: float = global_position.distance_to(p.global_position)
				if dist < SPIN_RADIUS:
					if "player_index" in p or p.has_meta("player_index"):
						var pi: int = p.get("player_index") if "player_index" in p else p.get_meta("player_index")
						PlayerManager.damage_player(pi, SPIN_DAMAGE)

	if _spin_timer <= 0.0:
		_state = State.DIZZY
		_dizzy_timer = DIZZY_DURATION
		_damage_multiplier = 1.5
		velocity.x = 0.0


func _do_dizzy(delta: float) -> void:
	_dizzy_timer -= delta
	velocity.x = 0.0

	if _dizzy_timer <= 0.0:
		_state = State.PATROL
		_damage_multiplier = 1.0


func _draw() -> void:
	if _state == State.DEAD:
		return

	# Candy corn triangle shape (rotates when spinning)
	var rot: float = _rotation_angle if _state == State.SPINNING or _state == State.WINDUP else 0.0

	# Triangle points (candy corn shape)
	var p1 := Vector2(0, -14).rotated(rot)
	var p2 := Vector2(-8, 10).rotated(rot)
	var p3 := Vector2(8, 10).rotated(rot)

	# White top section
	var white_pts := PackedVector2Array([p1, (p1 + p2) * 0.5, (p1 + p3) * 0.5])
	draw_polygon(white_pts, PackedColorArray([Color(0.95, 0.95, 0.9)]))

	# Orange middle section
	var mid_top_l: Vector2 = (p1 + p2) * 0.5
	var mid_top_r: Vector2 = (p1 + p3) * 0.5
	var mid_bot_l: Vector2 = (p1 * 0.2 + p2 * 0.8)
	var mid_bot_r: Vector2 = (p1 * 0.2 + p3 * 0.8)
	var orange_pts := PackedVector2Array([mid_top_l, mid_top_r, mid_bot_r, mid_bot_l])
	draw_polygon(orange_pts, PackedColorArray([Color(1.0, 0.6, 0.1), Color(1.0, 0.6, 0.1), Color(1.0, 0.6, 0.1), Color(1.0, 0.6, 0.1)]))

	# Yellow bottom section
	var yellow_pts := PackedVector2Array([mid_bot_l, mid_bot_r, p3, p2])
	draw_polygon(yellow_pts, PackedColorArray([Color(1.0, 0.85, 0.2), Color(1.0, 0.85, 0.2), Color(1.0, 0.85, 0.2), Color(1.0, 0.85, 0.2)]))

	# Eyes (only when not spinning fast)
	if _state != State.SPINNING:
		draw_circle(Vector2(-3, -2), 2, Color.BLACK)
		draw_circle(Vector2(3, -2), 2, Color.BLACK)
	else:
		# Dizzy/spinning eyes
		draw_circle(Vector2(-3, -2).rotated(rot), 2, Color(0.5, 0.5, 0.5))
		draw_circle(Vector2(3, -2).rotated(rot), 2, Color(0.5, 0.5, 0.5))

	# Dizzy stars
	if _state == State.DIZZY:
		var star_phase: float = _dizzy_timer * 3.0
		draw_circle(Vector2(sin(star_phase) * 10, -18), 2, Color(1.0, 1.0, 0.3))
		draw_circle(Vector2(sin(star_phase + 2.0) * 10, -20), 2, Color(1.0, 1.0, 0.3))


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
	var actual_amount: int = int(amount * _damage_multiplier)
	health -= actual_amount
	if _health_bar:
		_health_bar.set_health(health, MAX_HEALTH)

	_hurt_timer = 0.25
	var kb_dir: float = -patrol_direction
	velocity.x = kb_dir * 130.0
	velocity.y = -90.0

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
	var HealthPickup := load("res://scripts/items/health_pickup.gd")
	HealthPickup.try_spawn(get_parent(), global_position)
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
