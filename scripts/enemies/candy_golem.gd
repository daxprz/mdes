extends CharacterBody2D

## Candy Golem - slow, heavily armored candy creature with a ground pound attack.

signal died(global_pos: Vector2)

const MAX_HEALTH := 80
const GRAVITY := 800.0
const PATROL_SPEED := 25.0
const CHASE_SPEED := 35.0
const DETECTION_RANGE := 120.0
const ATTACK_RANGE := 50.0
const ATTACK_DAMAGE := 25
const ATTACK_COOLDOWN := 3.0
const CONTACT_DAMAGE := 10
const PROJECTILE_ARMOR := 0.5  # 50% reduced projectile damage

enum State { PATROL, CHASE, ATTACK_JUMP, ATTACK_SLAM, HURT, DEAD }

var health := MAX_HEALTH
var patrol_direction := 1.0
var _patrol_distance := 100.0
var _start_x := 0.0
var _state: State = State.PATROL
var _attack_timer := 0.0
var _hurt_timer := 0.0
var _target: Node2D = null
var _anim_timer := 0.0
var _slam_dealt := false

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
	_health_bar.bar_width = 28.0
	_health_bar.bar_height = 3.0
	_health_bar.bar_offset = Vector2(0, -26)
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
		velocity.x = move_toward(velocity.x, 0.0, 150.0 * delta)
		move_and_slide()
		return

	_target = _find_nearest_player()

	match _state:
		State.PATROL:
			_do_patrol(delta)
		State.CHASE:
			_do_chase(delta)
		State.ATTACK_JUMP:
			_do_attack_jump(delta)
		State.ATTACK_SLAM:
			_do_attack_slam(delta)

	_animate(delta)
	move_and_slide()


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

	if dist < ATTACK_RANGE and _attack_timer <= 0.0 and is_on_floor():
		_state = State.ATTACK_JUMP
		_attack_timer = ATTACK_COOLDOWN
		_slam_dealt = false
		velocity.y = -250.0  # Jump up for ground pound
		return

	var dir: float = signf(_target.global_position.x - global_position.x)
	velocity.x = CHASE_SPEED * dir
	patrol_direction = dir


func _do_attack_jump(delta: float) -> void:
	# Rising phase of ground pound
	if velocity.y >= 0.0:
		_state = State.ATTACK_SLAM


func _do_attack_slam(delta: float) -> void:
	# Falling phase - slam down
	velocity.x = 0.0

	if is_on_floor() and not _slam_dealt:
		_slam_dealt = true
		# Deal AoE damage
		_do_slam_damage()
		# Brief pause after slam
		_hurt_timer = 0.4  # Reuse hurt timer for recovery
		_state = State.CHASE


func _do_slam_damage() -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if p is Node2D:
			var dist: float = global_position.distance_to(p.global_position)
			if dist < ATTACK_RANGE:
				var pi: int = -1
				if "player_index" in p:
					pi = p.get("player_index")
				elif p.has_meta("player_index"):
					pi = p.get_meta("player_index")
				if pi >= 0:
					PlayerManager.damage_player(pi, ATTACK_DAMAGE)
				if p.has_method("take_damage"):
					p.take_damage(ATTACK_DAMAGE, -1)
				# Knock players away from slam
				if p.has_method("apply_knockback"):
					var kb_dir: float = signf(p.global_position.x - global_position.x)
					p.apply_knockback(Vector2(kb_dir * 200.0, -150.0))

	AudioManager.play("enemy_hit", 0.0)


func _animate(delta: float) -> void:
	if not sprite:
		return
	sprite.flip_h = patrol_direction < 0
	_anim_timer += delta
	if _anim_timer >= 0.2:
		_anim_timer -= 0.2
		if _state == State.ATTACK_JUMP or _state == State.ATTACK_SLAM:
			sprite.frame = 3
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

	# Check if this is projectile damage (source_index >= 0 means player projectile)
	# Apply armor reduction to projectile damage
	var final_amount: int = amount
	if _source_index >= 0:
		final_amount = int(float(amount) * PROJECTILE_ARMOR)
		if final_amount < 1:
			final_amount = 1

	health -= final_amount
	if _health_bar:
		_health_bar.set_health(health, MAX_HEALTH)

	_hurt_timer = 0.15  # Short stun - golem is tough
	var kb_dir: float = -patrol_direction
	velocity.x = kb_dir * 60.0  # Less knockback due to mass
	velocity.y = -40.0

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
	tween.tween_property(self, "scale", Vector2(0.1, 0.1), 0.4)
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.chain().tween_callback(queue_free)


func apply_knockback(force: Vector2) -> void:
	# Reduced knockback due to mass
	velocity = force * 0.4
	_hurt_timer = 0.15


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
