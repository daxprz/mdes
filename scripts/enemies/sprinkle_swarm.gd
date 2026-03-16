extends CharacterBody2D

## Sprinkle Swarm Individual - a tiny fast sprinkle creature that rushes players.
## Spawned in groups of 4-6 by the scene.

signal died(global_pos: Vector2)

const MAX_HEALTH := 8
const GRAVITY := 800.0
const MOVE_SPEED := 90.0
const DETECTION_RANGE := 150.0
const CONTACT_DAMAGE := 3

enum State { IDLE, RUSH, HURT, DEAD }

var health := MAX_HEALTH
var mass := 5.0
var patrol_direction := 1.0
var _patrol_distance := 60.0
var _start_x := 0.0
var _state: State = State.IDLE
var _hurt_timer := 0.0
var _target: Node2D = null
var _anim_timer := 0.0
var _offset: Vector2 = Vector2.ZERO  # Random cluster offset
var _sprinkle_color: Color = Color.WHITE

const HEALTH_BAR_SCENE := preload("res://scenes/ui/health_bar.tscn")

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var hitbox: Area2D = $Hitbox

var _health_bar: Node2D = null


func _ready() -> void:
	add_to_group("enemies")
	_start_x = global_position.x

	# Random offset for cluster behavior
	_offset = Vector2(randf_range(-15, 15), randf_range(-8, 8))

	# Random bright color
	var colors: Array[Color] = [
		Color(1.0, 0.2, 0.3),  # Red
		Color(0.2, 1.0, 0.3),  # Green
		Color(0.3, 0.4, 1.0),  # Blue
		Color(1.0, 1.0, 0.2),  # Yellow
		Color(1.0, 0.4, 1.0),  # Pink
		Color(0.2, 1.0, 1.0),  # Cyan
		Color(1.0, 0.6, 0.1),  # Orange
	]
	_sprinkle_color = colors[randi() % colors.size()]

	if hitbox:
		hitbox.body_entered.connect(_on_hitbox_body_entered)
	_health_bar = HEALTH_BAR_SCENE.instantiate()
	_health_bar.bar_width = 10.0
	_health_bar.bar_height = 1.0
	_health_bar.bar_offset = Vector2(0, -10)
	_health_bar.fill_color = _sprinkle_color
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
		velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)
		move_and_slide()
		return

	_target = _find_nearest_player()

	match _state:
		State.IDLE:
			_do_idle(delta)
		State.RUSH:
			_do_rush(delta)

	_animate(delta)
	move_and_slide()


func _do_idle(delta: float) -> void:
	# Small patrol movement
	velocity.x = MOVE_SPEED * 0.3 * patrol_direction

	if is_on_wall():
		patrol_direction *= -1.0
	elif abs(global_position.x - _start_x) > _patrol_distance:
		patrol_direction *= -1.0

	if _target and global_position.distance_to(_target.global_position) < DETECTION_RANGE:
		_state = State.RUSH


func _do_rush(delta: float) -> void:
	if not _target:
		_state = State.IDLE
		return

	var dist: float = global_position.distance_to(_target.global_position)

	if dist > DETECTION_RANGE * 1.5:
		_state = State.IDLE
		return

	# Rush toward player with cluster offset
	var target_pos: Vector2 = _target.global_position + _offset
	var dir: float = signf(target_pos.x - global_position.x)
	velocity.x = MOVE_SPEED * dir
	patrol_direction = dir

	# Jump toward player if they're above
	if _target.global_position.y < global_position.y - 20 and is_on_floor():
		velocity.y = -350.0


func _animate(delta: float) -> void:
	if not sprite:
		return
	sprite.flip_h = patrol_direction < 0
	_anim_timer += delta
	if _anim_timer >= 0.1:
		_anim_timer -= 0.1
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
	# Very fragile - any hit kills
	health = 0
	if _health_bar:
		_health_bar.set_health(0, MAX_HEALTH)

	AudioManager.play("enemy_hit", -6.0)
	_die()


func _flash_hit() -> void:
	if sprite:
		sprite.modulate = Color.RED
		var tween := create_tween()
		tween.tween_property(sprite, "modulate", Color.WHITE, 0.1)


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
	tween.tween_property(self, "scale", Vector2(0.05, 0.05), 0.2)
	tween.tween_property(self, "modulate:a", 0.0, 0.2)
	tween.chain().tween_callback(queue_free)


func apply_knockback(force: Vector2) -> void:
	velocity = force * 1.5  # Light, so more knockback
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
