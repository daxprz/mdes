extends CharacterBody2D

## Sprinkle Tornado - mid-tower mini-boss for Tower 3.
## Moves toward players, pulls them in, throws sprinkle projectile rings.

signal died(global_pos: Vector2)

const MAX_HEALTH := 180
const GRAVITY := 800.0
const MOVE_SPEED := 30.0
const PULL_RANGE := 120.0
const PULL_FORCE := 60.0
const INNER_RANGE := 25.0
const INNER_DAMAGE := 15
const INNER_DAMAGE_INTERVAL := 0.5
const RING_INTERVAL := 2.0
const RING_PROJECTILE_COUNT := 6
const RING_PROJECTILE_SPEED := 180.0
const RING_PROJECTILE_DAMAGE := 8
const MINI_TORNADO_HP := 15
const MINI_TORNADO_PULL := 40.0

var health := MAX_HEALTH
var is_dead := false
var current_phase := 1
var _ring_timer := RING_INTERVAL
var _inner_damage_timer := 0.0
var _flash_timer := 0.0
var _original_modulate := Color.WHITE
var _pull_force_current: float = PULL_FORCE
var _ring_count := RING_PROJECTILE_COUNT
var _spin_angle := 0.0
var _mini_tornado_spawned := false

const HEALTH_BAR_SCENE := preload("res://scenes/ui/health_bar.tscn")
const PROJECTILE_SCENE := preload("res://scenes/bosses/boss_projectile.tscn")

var _health_bar: Node2D = null


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 8
	collision_mask = 1
	_original_modulate = modulate

	_health_bar = HEALTH_BAR_SCENE.instantiate()
	_health_bar.bar_width = 40.0
	_health_bar.bar_height = 4.0
	_health_bar.bar_offset = Vector2(0, -48)
	_health_bar.fill_color = Color(0.9, 0.1, 0.1)
	add_child(_health_bar)
	_health_bar.set_health(health, MAX_HEALTH)


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# Gravity
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	else:
		velocity.y = 0.0

	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			modulate = _original_modulate

	# Move toward nearest player
	var target: Node2D = _find_nearest_player()
	if target:
		var dir_x: float = signf(target.global_position.x - global_position.x)
		velocity.x = MOVE_SPEED * dir_x
	else:
		velocity.x = 0.0

	# Pull effect on nearby players
	_apply_pull(delta)

	# Inner damage
	_inner_damage_timer -= delta
	if _inner_damage_timer <= 0.0:
		_inner_damage_timer = INNER_DAMAGE_INTERVAL
		_deal_inner_damage()

	# Projectile ring
	_ring_timer -= delta
	if _ring_timer <= 0.0:
		_ring_timer = RING_INTERVAL
		_fire_ring()

	# Spin visual
	_spin_angle += 5.0 * delta
	if _spin_angle > TAU:
		_spin_angle -= TAU

	move_and_slide()
	queue_redraw()


func _apply_pull(delta: float) -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if not p is Node2D:
			continue
		var dist: float = global_position.distance_to(p.global_position)
		if dist < PULL_RANGE and dist > 1.0:
			var pull_dir := Vector2(
				global_position.x - p.global_position.x,
				global_position.y - p.global_position.y
			).normalized()
			if p.has_method("apply_external_force"):
				p.apply_external_force(pull_dir * _pull_force_current * delta)
			elif "velocity" in p:
				p.velocity += pull_dir * _pull_force_current * delta


func _deal_inner_damage() -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if not p is Node2D:
			continue
		var dist: float = global_position.distance_to(p.global_position)
		if dist < INNER_RANGE:
			_damage_player(p, INNER_DAMAGE)


func _fire_ring() -> void:
	for i in range(_ring_count):
		var angle: float = (TAU / float(_ring_count)) * float(i)
		var dir := Vector2(cos(angle), sin(angle))
		var proj: Node2D = PROJECTILE_SCENE.instantiate()
		proj.global_position = global_position
		proj.direction = dir
		proj.speed = RING_PROJECTILE_SPEED
		proj.damage = RING_PROJECTILE_DAMAGE
		proj.color = _random_sprinkle_color()
		proj.projectile_size = 3.0
		proj.lifetime = 3.0
		get_tree().current_scene.add_child(proj)
	AudioManager.play("enemy_hit", -4.0, 1.2)


func _random_sprinkle_color() -> Color:
	var colors: Array[Color] = [
		Color(1, 0.2, 0.3),   # Red
		Color(0.2, 1, 0.3),   # Green
		Color(0.3, 0.5, 1),   # Blue
		Color(1, 1, 0.2),     # Yellow
		Color(1, 0.5, 0.8),   # Pink
		Color(0.8, 0.4, 1),   # Purple
	]
	return colors[randi() % colors.size()]


func _check_phase() -> void:
	var pct: float = float(health) / float(MAX_HEALTH)
	var new_phase := 1
	if pct <= 0.25:
		new_phase = 3
	elif pct <= 0.50:
		new_phase = 2

	if new_phase != current_phase:
		current_phase = new_phase
		match current_phase:
			2:
				_pull_force_current = PULL_FORCE * 2.0
				_ring_count = 8
			3:
				_pull_force_current = PULL_FORCE * 2.0
				_ring_count = 8
				if not _mini_tornado_spawned:
					_mini_tornado_spawned = true
					_spawn_mini_tornados()


func _spawn_mini_tornados() -> void:
	for i in range(2):
		var mini := CharacterBody2D.new()
		mini.global_position = global_position + Vector2(float(i) * 60.0 - 30.0, 0)
		mini.collision_layer = 8
		mini.collision_mask = 1
		mini.add_to_group("enemies")

		var col := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 10.0
		col.shape = shape
		mini.add_child(col)

		var script_text := "extends CharacterBody2D

var health := %d
var _pull_range := 60.0
var _pull_force := %0.1f
var _spin := 0.0

signal died(global_pos: Vector2)

func _ready() -> void:
	add_to_group('enemies')

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += 800.0 * delta
	else:
		velocity.y = 0.0
	_spin += 4.0 * delta
	var target: Node2D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group('players'):
		if p is Node2D:
			var d: float = global_position.distance_to(p.global_position)
			if d < best_d:
				best_d = d
				target = p
	if target:
		var dx: float = signf(target.global_position.x - global_position.x)
		velocity.x = 40.0 * dx
	for p in get_tree().get_nodes_in_group('players'):
		if p is Node2D:
			var d2: float = global_position.distance_to(p.global_position)
			if d2 < _pull_range and d2 > 1.0:
				var pull_dir: Vector2 = (global_position - p.global_position).normalized()
				if 'velocity' in p:
					p.velocity += pull_dir * _pull_force * delta
	move_and_slide()
	queue_redraw()

func _draw() -> void:
	for j in range(3):
		var a: float = _spin + float(j) * TAU / 3.0
		var r: float = 6.0 + float(j)
		draw_circle(Vector2(cos(a) * r, -4.0 + float(j) * 3.0), 3.0, Color(randf(), randf(), randf()))

func take_damage(amount: int, _source_index: int = -1) -> void:
	# Rift tentacle absorbs damage first
	if has_meta(\"rift_tentacle\"):
		var tentacle: Node2D = get_meta(\"rift_tentacle\")
		if is_instance_valid(tentacle) and tentacle.has_method(\"take_tentacle_damage\"):
			amount = tentacle.take_tentacle_damage(amount)
			if amount <= 0:
				return
		else:
			remove_meta(\"rift_tentacle\")
			remove_meta(\"rift_attached\")
	health -= amount
	if health <= 0:
		died.emit(global_position)
		queue_free()
" % [MINI_TORNADO_HP, MINI_TORNADO_PULL]

		var gd_script := GDScript.new()
		gd_script.source_code = script_text
		gd_script.reload()
		mini.set_script(gd_script)
		get_tree().current_scene.add_child(mini)


func _damage_player(player: Node2D, amount: int) -> void:
	if player.has_method("take_damage"):
		player.take_damage(amount, -1)
	var pi: int = -1
	if "player_index" in player:
		pi = player.get("player_index")
	elif player.has_meta("player_index"):
		pi = player.get_meta("player_index")
	if pi >= 0:
		PlayerManager.damage_player(pi, amount)


# -- Health --------------------------------------------------------------------

func take_damage(amount: int, _source_index: int = -1) -> void:
	if is_dead:
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
	health = maxi(0, health - amount)
	if _health_bar:
		_health_bar.set_health(health, MAX_HEALTH)
	AudioManager.play("enemy_hit", -2.0, 0.7)
	_hit_flash()
	_check_phase()
	if health <= 0:
		_die()


func _hit_flash() -> void:
	modulate = Color.WHITE * 3.0
	_flash_timer = 0.12


func _die() -> void:
	is_dead = true
	AudioManager.play("enemy_die")
	died.emit(global_position)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(0.1, 0.1), 0.4)
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.chain().tween_callback(queue_free)


# -- Drawing -------------------------------------------------------------------

func _draw() -> void:
	# Swirling cone of colorful sprinkles
	var colors: Array[Color] = [
		Color(1, 0.2, 0.3), Color(0.2, 1, 0.3), Color(0.3, 0.5, 1),
		Color(1, 1, 0.2), Color(1, 0.5, 0.8), Color(0.8, 0.4, 1),
	]

	# Draw layers of the tornado cone (bottom=wide, top=narrow)
	for layer in range(6):
		var y_pos: float = 20.0 - float(layer) * 8.0
		var radius: float = 18.0 - float(layer) * 2.5
		var layer_angle: float = _spin_angle + float(layer) * 0.8

		for s in range(3):
			var a: float = layer_angle + float(s) * TAU / 3.0
			var pos := Vector2(cos(a) * radius, y_pos)
			var col_idx: int = (layer + s) % colors.size()
			draw_circle(pos, 3.0, colors[col_idx])

	# Central funnel shape
	var funnel_color := Color(0.9, 0.85, 0.7, 0.4)
	var points: PackedVector2Array = PackedVector2Array([
		Vector2(-18, 20), Vector2(18, 20),
		Vector2(6, -28), Vector2(-6, -28),
	])
	draw_colored_polygon(points, funnel_color)

	# Pull range indicator (faint)
	if current_phase >= 2:
		draw_arc(Vector2.ZERO, PULL_RANGE, 0, TAU, 32, Color(0.8, 0.4, 1, 0.15), 1.0)


# -- Helpers -------------------------------------------------------------------

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


func set_patrol_distance(_dist: float) -> void:
	pass
