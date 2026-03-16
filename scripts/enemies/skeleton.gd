extends CharacterBody2D

## Skeleton enemy - patrols, chases nearby players, and lunges to attack.

signal died(global_pos: Vector2)

const PATROL_SPEED := 35.0
const CHASE_SPEED := 55.0
const LUNGE_SPEED := 150.0
const GRAVITY := 800.0
const MAX_HEALTH := 25
const CONTACT_DAMAGE := 5
const ATTACK_DAMAGE := 8
const DETECTION_RANGE := 140.0
const ATTACK_RANGE := 35.0
const ATTACK_COOLDOWN := 2.0

enum State { PATROL, CHASE, ATTACK, HURT, DEAD }

var health := MAX_HEALTH
var mass := 30.0
var patrol_direction := 1.0
var _patrol_distance := 100.0
var _start_x := 0.0
var _state: State = State.PATROL
var _attack_timer := 0.0
var _hurt_timer := 0.0
var _attack_active := false
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
	_health_bar.bar_offset = Vector2(0, -18)
	_health_bar.fill_color = Color(0.9, 0.2, 0.1)
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

	# Find nearest player
	_target = _find_nearest_player()

	match _state:
		State.PATROL:
			_do_patrol(delta)
		State.CHASE:
			_do_chase(delta)
		State.ATTACK:
			_do_attack(delta)

	# Animate walk
	_animate(delta)
	move_and_slide()


func _do_patrol(delta: float) -> void:
	velocity.x = PATROL_SPEED * patrol_direction

	if is_on_wall():
		patrol_direction *= -1.0
	elif abs(global_position.x - _start_x) > _patrol_distance:
		patrol_direction *= -1.0

	# Switch to chase if player nearby
	if _target and global_position.distance_to(_target.global_position) < DETECTION_RANGE:
		_state = State.CHASE


func _do_chase(delta: float) -> void:
	if not _target:
		_state = State.PATROL
		return

	var dist := global_position.distance_to(_target.global_position)

	# Lost the player
	if dist > DETECTION_RANGE * 1.5:
		_state = State.PATROL
		return

	# Close enough to attack
	if dist < ATTACK_RANGE and _attack_timer <= 0.0:
		_state = State.ATTACK
		_attack_timer = ATTACK_COOLDOWN
		_attack_active = true
		return

	# Move toward player
	var dir: float = signf(_target.global_position.x - global_position.x)
	velocity.x = CHASE_SPEED * dir
	patrol_direction = dir

	# Jump if player is above and we're on the floor
	if _target.global_position.y < global_position.y - 30 and is_on_floor():
		velocity.y = -400.0


func _do_attack(delta: float) -> void:
	if _attack_active:
		# Lunge toward player
		var dir := 1.0 if not sprite.flip_h else -1.0
		if _target:
			dir = signf(_target.global_position.x - global_position.x)
		velocity.x = LUNGE_SPEED * dir
		patrol_direction = dir

		# Deal damage to players in hitbox
		if hitbox:
			for body in hitbox.get_overlapping_bodies():
				if body != self and ("player_index" in body or body.has_meta("player_index")):
					var pi: int = body.get("player_index") if "player_index" in body else body.get_meta("player_index")
					PlayerManager.damage_player(pi, ATTACK_DAMAGE)
					if body.has_method("take_damage"):
						body.take_damage(ATTACK_DAMAGE, -1)

		_attack_active = false
		# Brief pause after attack
		await get_tree().create_timer(0.3).timeout
		if is_inside_tree() and _state != State.DEAD:
			_state = State.CHASE


func _animate(delta: float) -> void:
	if not sprite:
		return

	sprite.flip_h = patrol_direction < 0

	_anim_timer += delta
	if _anim_timer >= 0.15:
		_anim_timer -= 0.15
		if _state == State.ATTACK:
			sprite.frame = 2  # Attack frame
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

	# Knockback + hurt stun
	_hurt_timer = 0.25
	var kb_dir := -patrol_direction
	velocity.x = kb_dir * 150.0
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
	# Temporarily reduce speed
	var old_chase := CHASE_SPEED
	var old_patrol := PATROL_SPEED
	await get_tree().create_timer(duration).timeout
	# Speed constants can't be changed, but we can stun instead
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
