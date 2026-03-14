extends BossBase

## Boss 3 - Sprinkle Dragon
## Attacks: sprinkle breath (cone), tail swipe (melee behind), fly & rain (phase 2+).

const BREATH_SPEED := 280.0
const BREATH_DAMAGE := 10
const TAIL_DAMAGE := 20
const TAIL_RANGE := 70.0
const RAIN_DAMAGE := 8

var _is_flying := false
var _fly_timer := 0.0
var _original_y := 0.0

const SPRINKLE_COLORS: Array[Color] = [
	Color(1.0, 0.3, 0.3),   # Red
	Color(0.3, 1.0, 0.3),   # Green
	Color(0.3, 0.3, 1.0),   # Blue
	Color(1.0, 1.0, 0.3),   # Yellow
	Color(1.0, 0.5, 0.8),   # Pink
]


func _setup_boss() -> void:
	max_health = 800
	health = max_health
	_attack_cooldown = 2.5
	_attack_timer = 2.0
	move_speed = 60.0

	var texture := load("res://assets/sprites/bosses/sprinkle_dragon.png")
	if texture:
		sprite.texture = texture
		sprite.hframes = 4
		sprite.frame = 0
		sprite.scale = Vector2(2.5, 2.5)

	var shape := RectangleShape2D.new()
	shape.size = Vector2(64, 48)
	collision_shape.shape = shape

	add_to_group("bosses")


func _boss_process(delta: float) -> void:
	if _is_flying:
		_fly_timer -= delta
		if _fly_timer <= 0.0:
			_end_fly()
		return

	# Walk toward nearest player
	var target := get_nearest_player()
	if target:
		face_target(target.global_position)
		var dir: float = signf(target.global_position.x - global_position.x)
		velocity.x = dir * move_speed

		var frame_time: int = Time.get_ticks_msec() / 250
		sprite.frame = frame_time % 4
	else:
		velocity.x = 0.0


func _choose_attack() -> void:
	if _is_flying:
		_rain_sprinkles()
		return

	var target := get_nearest_player()
	if not target:
		return

	var dist := global_position.distance_to(target.global_position)
	var target_behind := (facing_left and target.global_position.x > global_position.x) or \
		(!facing_left and target.global_position.x < global_position.x)

	# Phase 2+: chance to fly up and rain sprinkles
	if current_phase >= 2 and randf() < 0.25:
		_start_fly()
		return

	# Player behind: tail swipe
	if target_behind and dist < TAIL_RANGE + 20.0:
		_tail_swipe()
	else:
		_sprinkle_breath(target)


func _sprinkle_breath(target: Node2D) -> void:
	var base_dir: Vector2 = (target.global_position - global_position).normalized()
	var count := 3 if current_phase < 3 else 5

	for i in range(count):
		var angle := (i - count / 2.0) * 0.18
		var dir := base_dir.rotated(angle)
		var col: Color = SPRINKLE_COLORS[i % SPRINKLE_COLORS.size()]
		spawn_projectile(dir, BREATH_SPEED + randf_range(-30, 30), BREATH_DAMAGE, col)


func _tail_swipe() -> void:
	# Area damage behind the dragon
	var swipe_dir := 1.0 if facing_left else -1.0
	var swipe_center := global_position + Vector2(swipe_dir * 50, 0)

	var players := get_tree().get_nodes_in_group("players")
	for p in players:
		if not p is Node2D:
			continue
		if swipe_center.distance_to(p.global_position) <= TAIL_RANGE:
			if p.has_method("take_damage"):
				p.take_damage(TAIL_DAMAGE)
			elif p.has_meta("player_index"):
				PlayerManager.damage_player(p.get_meta("player_index"), TAIL_DAMAGE)

	# Visual indicator
	var rect := ColorRect.new()
	rect.size = Vector2(TAIL_RANGE * 2, 20)
	rect.position = swipe_center - Vector2(TAIL_RANGE, 10)
	rect.color = Color(1.0, 0.5, 0.0, 0.5)
	var scene := get_tree().current_scene
	if scene:
		scene.add_child(rect)
	var tween := rect.create_tween()
	tween.tween_property(rect, "modulate:a", 0.0, 0.3)
	tween.tween_callback(rect.queue_free)


func _start_fly() -> void:
	_is_flying = true
	_original_y = position.y
	_fly_timer = 4.0
	velocity.x = 0.0

	var tween := create_tween()
	tween.tween_property(self, "position:y", _original_y - 150, 0.5).set_ease(Tween.EASE_OUT)


func _rain_sprinkles() -> void:
	if is_dead or not is_inside_tree():
		return
	var scene := get_tree().current_scene
	if not scene:
		return
	var count := 4 if current_phase < 3 else 7
	for i in range(count):
		var x_offset := randf_range(-200, 200)
		var dir: Vector2 = Vector2(randf_range(-0.2, 0.2), 1.0).normalized()
		var col: Color = SPRINKLE_COLORS[randi() % SPRINKLE_COLORS.size()]

		var proj_scene := preload("res://scenes/bosses/boss_projectile.tscn")
		var proj: Node2D = proj_scene.instantiate()
		proj.global_position = global_position + Vector2(x_offset, 0)
		proj.direction = dir
		proj.speed = 180.0
		proj.damage = RAIN_DAMAGE
		proj.color = col
		scene.add_child(proj)


func _end_fly() -> void:
	_is_flying = false
	var tween := create_tween()
	tween.tween_property(self, "position:y", _original_y, 0.4).set_ease(Tween.EASE_IN)


func _on_phase_change(phase: int) -> void:
	if phase == 2:
		_attack_cooldown = 2.0
		move_speed = 80.0
	elif phase == 3:
		_attack_cooldown = 1.5
		move_speed = 100.0
