extends CharacterBody2D

## Top-down patrol skeleton for the overworld valley and dungeon.
## Walks back and forth and deals contact damage. No gravity (top-down).

signal died(global_pos: Vector2)

const PATROL_SPEED := 30.0
const CHASE_SPEED := 50.0
const DETECTION_RANGE := 100.0
const CONTACT_DAMAGE := 5
const CONTACT_COOLDOWN := 1.0
const MAX_HEALTH := 20

enum State { PATROL, CHASE, DEAD }

var health: int = MAX_HEALTH
var mass := 30.0
var patrol_direction: float = 1.0
var _patrol_distance: float = 80.0
var _start_pos := Vector2.ZERO
var _state: State = State.PATROL
var _contact_timer: float = 0.0
var _anim_timer: float = 0.0
var _target: Node2D = null

const HEALTH_BAR_SCENE := preload("res://scenes/ui/health_bar.tscn")

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var hitbox: Area2D = $Hitbox

var _health_bar: Node2D = null


func _ready() -> void:
	add_to_group("enemies")
	_start_pos = global_position
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

	_contact_timer -= delta
	_target = _find_nearest_player()

	match _state:
		State.PATROL:
			_do_patrol(delta)
		State.CHASE:
			_do_chase(delta)

	_animate(delta)
	move_and_slide()


func _do_patrol(_delta: float) -> void:
	velocity = Vector2(PATROL_SPEED * patrol_direction, 0.0)

	# Reverse at patrol bounds
	if abs(global_position.x - _start_pos.x) > _patrol_distance:
		patrol_direction *= -1.0

	# Switch to chase if player nearby
	if _target and global_position.distance_to(_target.global_position) < DETECTION_RANGE:
		_state = State.CHASE


func _do_chase(_delta: float) -> void:
	if not _target:
		_state = State.PATROL
		return

	var dist: float = global_position.distance_to(_target.global_position)

	if dist > DETECTION_RANGE * 1.8:
		_state = State.PATROL
		return

	var dir_vec: Vector2 = (_target.global_position - global_position).normalized()
	velocity = dir_vec * CHASE_SPEED
	if dir_vec.x != 0.0:
		patrol_direction = signf(dir_vec.x)


func _animate(delta: float) -> void:
	if not sprite:
		return

	sprite.flip_h = patrol_direction < 0

	_anim_timer += delta
	if _anim_timer >= 0.15:
		_anim_timer -= 0.15
		if velocity.length() > 5.0:
			sprite.frame = (sprite.frame + 1) % 4
		else:
			sprite.frame = 0


func _find_nearest_player() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist: float = INF
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


func apply_slow(duration: float) -> void:
	# Stun the skeleton briefly
	_state = State.PATROL
	velocity = Vector2.ZERO
	await get_tree().create_timer(duration).timeout
	if is_inside_tree() and _state != State.DEAD:
		pass  # Resume normal behavior


func _on_hitbox_body_entered(body: Node2D) -> void:
	if _state == State.DEAD:
		return
	if _contact_timer > 0.0:
		return
	if "player_index" in body or body.has_meta("player_index"):
		var player_index: int = body.get("player_index") if "player_index" in body else body.get_meta("player_index")
		PlayerManager.damage_player(player_index, CONTACT_DAMAGE)
		if body.has_method("take_damage"):
			body.take_damage(CONTACT_DAMAGE, -1)
		_contact_timer = CONTACT_COOLDOWN
