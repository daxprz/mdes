extends CharacterBody2D

## Licorice Whip - stationary enemy that extends a whip to grab and pull players.

signal died(global_pos: Vector2)

const MAX_HEALTH := 35
const GRAVITY := 800.0
const DETECTION_RANGE := 150.0
const WHIP_DAMAGE := 10
const GRAB_COOLDOWN := 4.0
const PULL_SPEED := 100.0
const PULL_DURATION := 1.0
const WHIP_EXTEND_SPEED := 300.0
const CONTACT_DAMAGE := 5

enum State { IDLE, EXTENDING, GRABBING, COOLDOWN, HURT, DEAD }

var health := MAX_HEALTH
var patrol_direction := 1.0
var _patrol_distance := 100.0
var _state: State = State.IDLE
var _grab_timer := 0.0
var _hurt_timer := 0.0
var _anim_timer := 0.0
var _whip_length := 0.0
var _whip_target_pos := Vector2.ZERO
var _whip_direction := Vector2.ZERO
var _grab_target: Node2D = null
var _pull_timer := 0.0
var _cooldown_timer := 0.0

const HEALTH_BAR_SCENE := preload("res://scenes/ui/health_bar.tscn")

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var hitbox: Area2D = $Hitbox

var _health_bar: Node2D = null


func _ready() -> void:
	add_to_group("enemies")
	if hitbox:
		hitbox.body_entered.connect(_on_hitbox_body_entered)
	_health_bar = HEALTH_BAR_SCENE.instantiate()
	_health_bar.bar_width = 22.0
	_health_bar.bar_height = 2.0
	_health_bar.bar_offset = Vector2(0, -20)
	_health_bar.fill_color = Color(0.6, 0.1, 0.15)
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
	_cooldown_timer -= delta

	if _hurt_timer > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, 200.0 * delta)
		move_and_slide()
		queue_redraw()
		return

	# Stationary - no horizontal movement
	velocity.x = 0.0

	match _state:
		State.IDLE:
			_do_idle(delta)
		State.EXTENDING:
			_do_extending(delta)
		State.GRABBING:
			_do_grabbing(delta)
		State.COOLDOWN:
			_do_cooldown(delta)

	_animate(delta)
	move_and_slide()
	queue_redraw()


func _do_idle(_delta: float) -> void:
	if _cooldown_timer > 0.0:
		return
	var target: Node2D = _find_nearest_player()
	if target:
		var dist: float = global_position.distance_to(target.global_position)
		if dist < DETECTION_RANGE:
			_state = State.EXTENDING
			_whip_length = 0.0
			_whip_direction = (target.global_position - global_position).normalized()
			_whip_target_pos = target.global_position
			patrol_direction = signf(_whip_direction.x) if _whip_direction.x != 0.0 else 1.0


func _do_extending(delta: float) -> void:
	_whip_length += WHIP_EXTEND_SPEED * delta
	var tip_pos: Vector2 = global_position + _whip_direction * _whip_length

	# Check if whip reached target distance
	if _whip_length >= DETECTION_RANGE:
		_state = State.COOLDOWN
		_cooldown_timer = GRAB_COOLDOWN
		_whip_length = 0.0
		return

	# Check if whip hit a player
	for p in get_tree().get_nodes_in_group("players"):
		if p is Node2D:
			var dist: float = tip_pos.distance_to(p.global_position)
			if dist < 20.0:
				# Grab the player
				_grab_target = p
				_pull_timer = PULL_DURATION
				_state = State.GRABBING
				# Deal whip damage
				if "player_index" in p or p.has_meta("player_index"):
					var pi: int = p.get("player_index") if "player_index" in p else p.get_meta("player_index")
					PlayerManager.damage_player(pi, WHIP_DAMAGE)
				AudioManager.play("enemy_hit", -3.0)
				return


func _do_grabbing(delta: float) -> void:
	_pull_timer -= delta

	if not is_instance_valid(_grab_target):
		_state = State.COOLDOWN
		_cooldown_timer = GRAB_COOLDOWN
		_whip_length = 0.0
		return

	# Pull target toward self
	var dir: Vector2 = (global_position - _grab_target.global_position).normalized()
	if _grab_target.has_method("apply_knockback"):
		_grab_target.apply_knockback(dir * PULL_SPEED)

	# Player can break free by jumping (check if they moved away fast enough)
	var dist: float = global_position.distance_to(_grab_target.global_position)
	_whip_length = dist

	if _pull_timer <= 0.0 or dist < 20.0 or dist > DETECTION_RANGE * 1.5:
		_state = State.COOLDOWN
		_cooldown_timer = GRAB_COOLDOWN
		_whip_length = 0.0
		_grab_target = null


func _do_cooldown(_delta: float) -> void:
	_whip_length = maxf(_whip_length - 200.0 * _cooldown_timer, 0.0)
	if _cooldown_timer <= 0.0:
		_state = State.IDLE
		_whip_length = 0.0


func _draw() -> void:
	if _state == State.DEAD:
		return

	# Dark red/black twisted body
	draw_rect(Rect2(-8, -14, 16, 28), Color(0.3, 0.05, 0.08))
	draw_rect(Rect2(-6, -12, 12, 24), Color(0.5, 0.1, 0.15))
	# Eyes
	draw_circle(Vector2(-3, -6), 2, Color(0.9, 0.3, 0.1))
	draw_circle(Vector2(3, -6), 2, Color(0.9, 0.3, 0.1))

	# Whip line
	if _whip_length > 0.0 and (_state == State.EXTENDING or _state == State.GRABBING):
		var end_pos: Vector2 = _whip_direction * _whip_length
		draw_line(Vector2.ZERO, end_pos, Color(0.15, 0.0, 0.0), 3.0)
		draw_line(Vector2(0, 2), end_pos + Vector2(0, 2), Color(0.4, 0.05, 0.08), 2.0)


func _animate(delta: float) -> void:
	if not sprite:
		return
	sprite.flip_h = patrol_direction < 0
	_anim_timer += delta
	if _anim_timer >= 0.15:
		_anim_timer -= 0.15
		if _state == State.EXTENDING or _state == State.GRABBING:
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
	health -= amount
	if _health_bar:
		_health_bar.set_health(health, MAX_HEALTH)

	_hurt_timer = 0.25
	var kb_dir: float = -patrol_direction
	velocity.x = kb_dir * 100.0
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
