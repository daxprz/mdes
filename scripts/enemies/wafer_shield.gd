extends CharacterBody2D

## Wafer Shield Bearer - ground enemy with a front-facing shield that blocks damage.
## Must be hit from behind or with charge attacks to break the shield.

signal died(global_pos: Vector2)

const MAX_HEALTH := 40
const GRAVITY := 800.0
const NORMAL_SPEED := 30.0
const PANICKED_SPEED := 50.0
const DETECTION_RANGE := 120.0
const SHIELD_BASH_DAMAGE := 15
const BASH_RANGE := 30.0
const BASH_COOLDOWN := 2.0
const SHIELD_BREAK_DURATION := 3.0
const CONTACT_DAMAGE := 5

enum State { PATROL, CHASE, BASH, HURT, DEAD }

var health := MAX_HEALTH
var patrol_direction := 1.0
var _patrol_distance := 100.0
var _start_x := 0.0
var _state: State = State.PATROL
var _hurt_timer := 0.0
var _anim_timer := 0.0
var _target: Node2D = null
var _bash_timer := 0.0
var _shield_active := true
var _shield_break_timer := 0.0
var _damage_multiplier := 1.0
var _facing := 1.0

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
	_health_bar.bar_width = 22.0
	_health_bar.bar_height = 2.0
	_health_bar.bar_offset = Vector2(0, -20)
	_health_bar.fill_color = Color(0.85, 0.75, 0.5)
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
	_bash_timer -= delta

	# Shield break timer
	if not _shield_active:
		_shield_break_timer -= delta
		if _shield_break_timer <= 0.0:
			_shield_active = true
			_damage_multiplier = 1.0

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
		State.BASH:
			_do_bash(delta)

	_animate(delta)
	move_and_slide()
	queue_redraw()


func _do_patrol(delta: float) -> void:
	var spd: float = PANICKED_SPEED if not _shield_active else NORMAL_SPEED
	velocity.x = spd * patrol_direction
	_facing = patrol_direction

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
	_facing = dir
	patrol_direction = dir

	# When shield is broken, try to turn around (face away from player)
	if not _shield_active:
		_facing = -dir
		velocity.x = PANICKED_SPEED * dir
	else:
		velocity.x = NORMAL_SPEED * dir

	# Shield bash when close
	if dist < BASH_RANGE and _bash_timer <= 0.0 and _shield_active:
		_state = State.BASH
		_bash_timer = BASH_COOLDOWN


func _do_bash(delta: float) -> void:
	# Lunge forward with shield
	velocity.x = _facing * 120.0

	# Deal damage
	if hitbox:
		for body in hitbox.get_overlapping_bodies():
			if body != self and ("player_index" in body or body.has_meta("player_index")):
				var pi: int = body.get("player_index") if "player_index" in body else body.get_meta("player_index")
				PlayerManager.damage_player(pi, SHIELD_BASH_DAMAGE)
				if body.has_method("apply_knockback"):
					body.apply_knockback(Vector2(_facing * 200.0, -100.0))

	_state = State.CHASE


func _draw() -> void:
	if _state == State.DEAD:
		return

	# Rectangular wafer body
	draw_rect(Rect2(-8, -14, 16, 28), Color(0.85, 0.73, 0.5))
	# Wafer lines
	draw_line(Vector2(-6, -8), Vector2(6, -8), Color(0.7, 0.6, 0.4), 1.0)
	draw_line(Vector2(-6, -2), Vector2(6, -2), Color(0.7, 0.6, 0.4), 1.0)
	draw_line(Vector2(-6, 4), Vector2(6, 4), Color(0.7, 0.6, 0.4), 1.0)
	# Eyes
	draw_circle(Vector2(-3, -5), 2, Color.BLACK)
	draw_circle(Vector2(3, -5), 2, Color.BLACK)

	# Shield on front side
	var shield_x: float = 10.0 * _facing
	if _shield_active:
		draw_rect(Rect2(shield_x - 3, -16, 6, 32), Color(0.6, 0.5, 0.3))
		draw_rect(Rect2(shield_x - 2, -14, 4, 28), Color(0.75, 0.65, 0.45))
	else:
		# Broken shield - just fragments
		draw_line(Vector2(shield_x, -10), Vector2(shield_x + 2, -4), Color(0.6, 0.5, 0.3, 0.5), 2.0)
		draw_line(Vector2(shield_x, 4), Vector2(shield_x - 1, 8), Color(0.6, 0.5, 0.3, 0.5), 2.0)


func _animate(delta: float) -> void:
	if not sprite:
		return
	sprite.flip_h = _facing < 0
	_anim_timer += delta
	if _anim_timer >= 0.15:
		_anim_timer -= 0.15
		if _state == State.BASH:
			sprite.frame = 2
		elif abs(velocity.x) > 10.0:
			sprite.frame = (sprite.frame + 1) % 4
		else:
			sprite.frame = 0


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


func break_shield() -> void:
	_shield_active = false
	_shield_break_timer = SHIELD_BREAK_DURATION
	_damage_multiplier = 2.0
	AudioManager.play("enemy_hit", -2.0)


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

	# Check if hit from the front (shielded side)
	if _shield_active and _source_index >= 0:
		var source_node: Node2D = null
		for p in get_tree().get_nodes_in_group("players"):
			if "player_index" in p and p.player_index == _source_index:
				source_node = p
				break
		if source_node:
			var hit_dir: float = signf(source_node.global_position.x - global_position.x)
			# If hit from the front (same direction as facing), shield blocks
			if hit_dir == _facing:
				AudioManager.play("enemy_hit", -8.0)
				return

	var actual_amount: int = int(amount * _damage_multiplier)
	health -= actual_amount
	if _health_bar:
		_health_bar.set_health(health, MAX_HEALTH)

	_hurt_timer = 0.25
	var kb_dir: float = -_facing
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
	# Charge attacks break the shield
	if force.length() > 180.0 and _shield_active:
		break_shield()


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
