extends CharacterBody2D

## Jellybean Sniper - ranged enemy that hides in the background, fires precise shots
## with a laser warning. Can only be damaged by AoE or melee at very close range.

signal died(global_pos: Vector2)

const MAX_HEALTH := 12
const GRAVITY := 800.0
const DETECTION_RANGE := 250.0
const SHOT_DAMAGE := 12
const SHOT_SPEED := 350.0
const SHOT_INTERVAL := 3.5
const WARNING_DURATION := 0.5
const MELEE_RANGE := 30.0
const CONTACT_DAMAGE := 3

enum State { IDLE, WARNING, SHOOTING, HURT, DEAD }

var health := MAX_HEALTH
var patrol_direction := 1.0
var _patrol_distance := 100.0
var _state: State = State.IDLE
var _shot_timer := SHOT_INTERVAL
var _warning_timer := 0.0
var _hurt_timer := 0.0
var _anim_timer := 0.0
var _target: Node2D = null
var _aim_direction := Vector2.ZERO
var _glow_intensity := 0.0

const HEALTH_BAR_SCENE := preload("res://scenes/ui/health_bar.tscn")

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var hitbox: Area2D = $Hitbox

var _health_bar: Node2D = null


func _ready() -> void:
	add_to_group("enemies")
	# Slightly translucent - background enemy
	modulate = Color(1.0, 1.0, 1.0, 0.65)

	if hitbox:
		hitbox.body_entered.connect(_on_hitbox_body_entered)
	_health_bar = HEALTH_BAR_SCENE.instantiate()
	_health_bar.bar_width = 16.0
	_health_bar.bar_height = 2.0
	_health_bar.bar_offset = Vector2(0, -18)
	_health_bar.fill_color = Color(0.5, 0.25, 0.75)
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

	# Stationary - no horizontal movement
	velocity.x = 0.0

	_hurt_timer -= delta
	_shot_timer -= delta

	if _hurt_timer > 0.0:
		move_and_slide()
		queue_redraw()
		return

	_target = _find_nearest_player()

	match _state:
		State.IDLE:
			_do_idle(delta)
		State.WARNING:
			_do_warning(delta)
		State.SHOOTING:
			_do_shooting(delta)

	_animate(delta)
	move_and_slide()
	queue_redraw()


func _do_idle(_delta: float) -> void:
	_glow_intensity = maxf(_glow_intensity - 0.05, 0.0)

	if _shot_timer <= 0.0 and _target:
		var dist: float = global_position.distance_to(_target.global_position)
		if dist < DETECTION_RANGE:
			_state = State.WARNING
			_warning_timer = WARNING_DURATION
			_aim_direction = (_target.global_position - global_position).normalized()
			patrol_direction = signf(_aim_direction.x) if _aim_direction.x != 0.0 else 1.0


func _do_warning(delta: float) -> void:
	_warning_timer -= delta
	_glow_intensity = minf(_glow_intensity + delta * 4.0, 1.0)

	# Update aim
	if _target:
		_aim_direction = (_target.global_position - global_position).normalized()

	if _warning_timer <= 0.0:
		_state = State.SHOOTING
		_fire_projectile()
		_shot_timer = SHOT_INTERVAL
		_state = State.IDLE


func _do_shooting(_delta: float) -> void:
	_state = State.IDLE


func _fire_projectile() -> void:
	if not _target:
		return

	AudioManager.play("enemy_hit", -5.0)

	var projectile := Area2D.new()
	projectile.collision_layer = 8
	projectile.collision_mask = 2
	projectile.global_position = global_position

	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 4.0
	col.shape = shape
	projectile.add_child(col)

	var rect := ColorRect.new()
	rect.size = Vector2(6, 6)
	rect.position = Vector2(-3, -3)
	rect.color = Color(0.9, 0.2, 0.3)
	projectile.add_child(rect)

	var proj_velocity: Vector2 = _aim_direction * SHOT_SPEED
	projectile.set_meta("proj_velocity", proj_velocity)
	projectile.set_meta("proj_damage", SHOT_DAMAGE)
	projectile.set_script(_get_projectile_script())

	projectile.body_entered.connect(_on_projectile_hit.bind(projectile))
	get_tree().current_scene.add_child(projectile)


func _get_projectile_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = '
extends Area2D

var proj_velocity := Vector2.ZERO
var _lifetime := 0.0

func _ready() -> void:
	proj_velocity = get_meta("proj_velocity")

func _physics_process(delta: float) -> void:
	position += proj_velocity * delta
	_lifetime += delta
	if _lifetime > 3.0:
		queue_free()
'
	script.reload()
	return script


func _on_projectile_hit(body: Node2D, projectile: Area2D) -> void:
	if not is_instance_valid(projectile):
		return
	if "player_index" in body or body.has_meta("player_index"):
		var pi: int = body.get("player_index") if "player_index" in body else body.get_meta("player_index")
		PlayerManager.damage_player(pi, SHOT_DAMAGE)
		if body.has_method("take_damage"):
			body.take_damage(SHOT_DAMAGE, -1)
		projectile.queue_free()


func _draw() -> void:
	if _state == State.DEAD:
		return

	# Jellybean oval shape
	var base_color := Color(0.5, 0.25, 0.75)
	if _glow_intensity > 0.0:
		base_color = base_color.lerp(Color(0.9, 0.2, 0.2), _glow_intensity)

	# Oval body
	_draw_ellipse_shape(Rect2(-10, -12, 20, 24), base_color)

	# Highlight
	_draw_ellipse_shape(Rect2(-6, -10, 8, 8), Color(0.7, 0.5, 0.9, 0.5))

	# Eyes
	draw_circle(Vector2(-3, -3), 2, Color.BLACK)
	draw_circle(Vector2(3, -3), 2, Color.BLACK)

	# Laser warning line
	if _state == State.WARNING and _glow_intensity > 0.3:
		var line_end: Vector2 = _aim_direction * DETECTION_RANGE
		draw_line(Vector2.ZERO, line_end, Color(1.0, 0.1, 0.1, _glow_intensity * 0.6), 1.5)


# Helper since Godot doesn't have _draw_ellipse_shape built-in with Rect2
func _draw_ellipse_shape(rect: Rect2, color: Color) -> void:
	var center := Vector2(rect.position.x + rect.size.x / 2.0, rect.position.y + rect.size.y / 2.0)
	var radius_x: float = rect.size.x / 2.0
	var radius_y: float = rect.size.y / 2.0
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var segments: int = 24
	for i in range(segments):
		var angle: float = TAU * i / segments
		points.append(Vector2(center.x + cos(angle) * radius_x, center.y + sin(angle) * radius_y))
		colors.append(color)
	if points.size() >= 3:
		draw_polygon(points, colors)


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

	# Can only be damaged by AoE (source_index == -1) or close range
	if _source_index >= 0:
		# Check if player is within melee range
		var close_enough := false
		for p in get_tree().get_nodes_in_group("players"):
			if "player_index" in p and p.player_index == _source_index:
				if p is Node2D:
					var dist: float = global_position.distance_to(p.global_position)
					if dist <= MELEE_RANGE:
						close_enough = true
				break
		if not close_enough:
			return

	health -= amount
	if _health_bar:
		_health_bar.set_health(health, MAX_HEALTH)

	_hurt_timer = 0.2
	velocity.y = -60.0

	AudioManager.play("enemy_hit", -3.0)
	_flash_hit()

	if health <= 0:
		_die()


func _flash_hit() -> void:
	if sprite:
		var original_alpha: float = modulate.a
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
		PlayerManager.damage_player(player_index, CONTACT_DAMAGE)
		if body.has_method("take_damage"):
			body.take_damage(CONTACT_DAMAGE, -1)
