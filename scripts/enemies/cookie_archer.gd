extends CharacterBody2D

## Cookie Archer - stands on platforms and shoots cookie arrow projectiles at players.

signal died(global_pos: Vector2)

const MAX_HEALTH := 20
const GRAVITY := 800.0
const BACKUP_SPEED := 40.0
const DETECTION_RANGE := 200.0
const BACKUP_RANGE := 50.0
const ATTACK_COOLDOWN := 2.5
const ARROW_DAMAGE := 8
const ARROW_SPEED := 250.0
const ARROW_LIFETIME := 3.0
const CONTACT_DAMAGE := 4

enum State { IDLE, SHOOT, BACKUP, HURT, DEAD }

var health := MAX_HEALTH
var patrol_direction := 1.0
var _patrol_distance := 80.0
var _start_x := 0.0
var _state: State = State.IDLE
var _attack_timer := 0.0
var _hurt_timer := 0.0
var _target: Node2D = null
var _anim_timer := 0.0

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
	_health_bar.fill_color = Color(0.8, 0.6, 0.3)
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

	_attack_timer -= delta
	_hurt_timer -= delta

	if _hurt_timer > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, 200.0 * delta)
		move_and_slide()
		return

	_target = _find_nearest_player()

	match _state:
		State.IDLE:
			_do_idle(delta)
		State.BACKUP:
			_do_backup(delta)
		State.SHOOT:
			_do_shoot(delta)

	_animate(delta)
	move_and_slide()


func _do_idle(delta: float) -> void:
	velocity.x = 0.0

	if not _target:
		return

	var dist: float = global_position.distance_to(_target.global_position)

	# Back away if too close
	if dist < BACKUP_RANGE:
		_state = State.BACKUP
		return

	# Shoot if in range and cooldown ready
	if dist < DETECTION_RANGE and _attack_timer <= 0.0:
		_state = State.SHOOT
		return

	# Face the target
	if _target:
		patrol_direction = signf(_target.global_position.x - global_position.x)


func _do_backup(delta: float) -> void:
	if not _target:
		_state = State.IDLE
		return

	var dist: float = global_position.distance_to(_target.global_position)

	# Move away from player
	var dir: float = signf(global_position.x - _target.global_position.x)
	velocity.x = BACKUP_SPEED * dir
	patrol_direction = -dir  # Face the player while backing up

	if dist > BACKUP_RANGE * 1.5:
		_state = State.IDLE


func _do_shoot(delta: float) -> void:
	if not _target:
		_state = State.IDLE
		return

	velocity.x = 0.0
	patrol_direction = signf(_target.global_position.x - global_position.x)

	_fire_arrow()
	_attack_timer = ATTACK_COOLDOWN
	_state = State.IDLE


func _fire_arrow() -> void:
	if not _target:
		return

	AudioManager.play("crossbow_shoot", -5.0)

	var arrow := Area2D.new()
	arrow.collision_layer = 8
	arrow.collision_mask = 2
	arrow.position = global_position + Vector2(patrol_direction * 12.0, -4.0)

	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(10, 3)
	col.shape = shape
	arrow.add_child(col)

	# Arrow visual
	var visual := ArrowVisual.new()
	visual.facing = patrol_direction
	arrow.add_child(visual)

	# Direction toward player
	var dir: Vector2 = (_target.global_position - global_position).normalized()
	var arrow_velocity: Vector2 = dir * ARROW_SPEED

	arrow.body_entered.connect(_on_arrow_hit.bind(arrow))

	get_tree().current_scene.add_child(arrow)

	# Move arrow in a separate script-like approach using a tween + timer
	var lifetime := 0.0
	_move_arrow(arrow, arrow_velocity)


func _move_arrow(arrow: Area2D, vel: Vector2) -> void:
	if not is_instance_valid(arrow):
		return

	# Use a timer to auto-destroy
	var timer := Timer.new()
	timer.wait_time = ARROW_LIFETIME
	timer.one_shot = true
	timer.timeout.connect(func() -> void:
		if is_instance_valid(arrow):
			arrow.queue_free()
	)
	arrow.add_child(timer)
	timer.start()

	# Move arrow with a process callback
	arrow.set_meta("velocity", vel)
	arrow.set_meta("arrow_damage", ARROW_DAMAGE)
	var callable := func(delta: float) -> void:
		if is_instance_valid(arrow):
			arrow.position += vel * delta
	arrow.set_process(true)
	arrow.set_meta("_process_func", callable)
	# Connect to tree process via a helper node
	var helper := ArrowMover.new()
	helper.arrow = arrow
	helper.arrow_velocity = vel
	arrow.add_child(helper)


func _on_arrow_hit(body: Node2D, arrow: Area2D) -> void:
	if "player_index" in body or body.has_meta("player_index"):
		var player_index: int = body.get("player_index") if "player_index" in body else body.get_meta("player_index")
		PlayerManager.damage_player(player_index, ARROW_DAMAGE)
		if body.has_method("take_damage"):
			body.take_damage(ARROW_DAMAGE, -1)
	if is_instance_valid(arrow):
		arrow.queue_free()


func _animate(delta: float) -> void:
	if not sprite:
		return
	sprite.flip_h = patrol_direction < 0
	_anim_timer += delta
	if _anim_timer >= 0.15:
		_anim_timer -= 0.15
		if _state == State.SHOOT:
			sprite.frame = 2
		elif abs(velocity.x) > 5.0:
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

	_hurt_timer = 0.25
	var kb_dir: float = -patrol_direction
	velocity.x = kb_dir * 130.0
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


## Helper node that moves the arrow each frame.
class ArrowMover extends Node2D:
	var arrow: Area2D
	var arrow_velocity: Vector2

	func _physics_process(delta: float) -> void:
		if is_instance_valid(arrow):
			arrow.position += arrow_velocity * delta
		else:
			queue_free()


## Simple visual for the arrow projectile.
class ArrowVisual extends Node2D:
	var facing := 1.0

	func _draw() -> void:
		# Arrow shaft
		draw_line(Vector2(-6 * facing, 0), Vector2(6 * facing, 0), Color(0.6, 0.4, 0.2), 2.0)
		# Arrowhead
		draw_line(Vector2(6 * facing, 0), Vector2(3 * facing, -3), Color(0.5, 0.5, 0.5), 1.5)
		draw_line(Vector2(6 * facing, 0), Vector2(3 * facing, 3), Color(0.5, 0.5, 0.5), 1.5)
