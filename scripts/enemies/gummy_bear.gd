extends CharacterBody2D

## Gummy Bear Brute - heavy ground enemy that charges at players and bounces off walls.
## Gets dizzy after 2 bounces or traveling 300px.

signal died(global_pos: Vector2)

const MAX_HEALTH := 60
const GRAVITY := 800.0
const PATROL_SPEED := 20.0
const CHARGE_SPEED := 200.0
const DETECTION_RANGE := 130.0
const CHARGE_DAMAGE := 20
const CONTACT_DAMAGE := 8
const MAX_BOUNCES := 2
const MAX_CHARGE_DISTANCE := 300.0
const DIZZY_DURATION := 2.0

enum State { PATROL, CHARGE, DIZZY, HURT, DEAD }

var health := MAX_HEALTH
var patrol_direction := 1.0
var _patrol_distance := 100.0
var _start_x := 0.0
var _state: State = State.PATROL
var _hurt_timer := 0.0
var _anim_timer := 0.0
var _target: Node2D = null
var _charge_direction := 1.0
var _bounce_count := 0
var _charge_distance := 0.0
var _dizzy_timer := 0.0
var _damage_multiplier := 1.0

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
	_health_bar.bar_width = 26.0
	_health_bar.bar_height = 3.0
	_health_bar.bar_offset = Vector2(0, -22)
	_health_bar.fill_color = Color(0.3, 0.85, 0.4)
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
		State.CHARGE:
			_do_charge(delta)
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

	# Detect player and start charging
	if _target and global_position.distance_to(_target.global_position) < DETECTION_RANGE:
		_state = State.CHARGE
		_charge_direction = signf(_target.global_position.x - global_position.x)
		if _charge_direction == 0.0:
			_charge_direction = patrol_direction
		_bounce_count = 0
		_charge_distance = 0.0
		_damage_multiplier = 1.0


func _do_charge(delta: float) -> void:
	velocity.x = CHARGE_SPEED * _charge_direction
	_charge_distance += CHARGE_SPEED * delta

	# Bounce off walls
	if is_on_wall():
		_charge_direction *= -1.0
		_bounce_count += 1
		AudioManager.play("enemy_hit", -6.0)

	# Check dizzy conditions
	if _bounce_count >= MAX_BOUNCES or _charge_distance >= MAX_CHARGE_DISTANCE:
		_state = State.DIZZY
		_dizzy_timer = DIZZY_DURATION
		_damage_multiplier = 2.0
		velocity.x = 0.0


func _do_dizzy(delta: float) -> void:
	_dizzy_timer -= delta
	velocity.x = 0.0

	if _dizzy_timer <= 0.0:
		_state = State.PATROL
		_damage_multiplier = 1.0
		patrol_direction = _charge_direction


func _draw() -> void:
	if _state == State.DEAD:
		return

	var body_color := Color(0.3, 0.8, 0.4)
	if _state == State.DIZZY:
		body_color = Color(0.5, 0.9, 0.5, 0.7)
	elif _state == State.CHARGE:
		body_color = Color(0.2, 0.7, 0.3)

	# Body (large circle)
	draw_circle(Vector2(0, -2), 14, body_color)
	# Ears
	draw_circle(Vector2(-9, -14), 5, body_color)
	draw_circle(Vector2(9, -14), 5, body_color)
	# Eyes
	if _state == State.DIZZY:
		# Dizzy spiral eyes
		draw_line(Vector2(-5, -6), Vector2(-2, -3), Color.BLACK, 2.0)
		draw_line(Vector2(-2, -6), Vector2(-5, -3), Color.BLACK, 2.0)
		draw_line(Vector2(3, -6), Vector2(6, -3), Color.BLACK, 2.0)
		draw_line(Vector2(6, -6), Vector2(3, -3), Color.BLACK, 2.0)
	else:
		draw_circle(Vector2(-4, -5), 3, Color.BLACK)
		draw_circle(Vector2(4, -5), 3, Color.BLACK)
		draw_circle(Vector2(-4, -5), 1, Color.WHITE)
		draw_circle(Vector2(4, -5), 1, Color.WHITE)

	# Belly
	draw_circle(Vector2(0, 2), 7, Color(0.5, 0.95, 0.6))


func _animate(delta: float) -> void:
	if not sprite:
		return
	sprite.flip_h = patrol_direction < 0 if _state == State.PATROL else _charge_direction < 0
	_anim_timer += delta
	if _anim_timer >= 0.15:
		_anim_timer -= 0.15
		if _state == State.DIZZY:
			sprite.frame = 3
		elif _state == State.CHARGE:
			sprite.frame = 2
		else:
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
	velocity.x = kb_dir * 80.0
	velocity.y = -60.0

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
		var dmg: int = CHARGE_DAMAGE if _state == State.CHARGE else CONTACT_DAMAGE
		PlayerManager.damage_player(player_index, dmg)
		if body.has_method("take_damage"):
			body.take_damage(dmg, -1)
