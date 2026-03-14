extends CharacterBody2D

## Batter Elemental - mid-tower mini-boss for Tower 4.
## Shapeshifter that cycles through Blob, Spike, Wave, and Shield forms.

signal died(global_pos: Vector2)

const MAX_HEALTH := 200
const GRAVITY := 800.0
const FORM_DURATION := 8.0
const MORPH_DURATION := 0.5
const BLOB_SPEED := 80.0
const BLOB_CONTACT_DAMAGE := 10
const SPIKE_PROJECTILE_COUNT := 6
const SPIKE_PROJECTILE_SPEED := 150.0
const SPIKE_PROJECTILE_DAMAGE := 10
const SPIKE_INTERVAL := 1.5
const WAVE_DAMAGE := 15
const WAVE_INTERVAL := 2.0
const SHIELD_DAMAGE_REDUCTION := 0.75
const SHIELD_HEAL_RATE := 10.0  # HP/s
const SHIELD_SPEED := 20.0

enum Form { BLOB, SPIKE, WAVE, SHIELD }

var health := MAX_HEALTH
var is_dead := false
var _current_form: Form = Form.BLOB
var _form_timer := FORM_DURATION
var _is_morphing := false
var _morph_timer := 0.0
var _attack_timer := 0.0
var _flash_timer := 0.0
var _original_modulate := Color.WHITE
var _blob_direction := 1.0
var _blob_bounce_timer := 0.0
var _form_index := 0
var _draw_timer := 0.0

const FORM_ORDER: Array[int] = [0, 1, 2, 3]  # BLOB, SPIKE, WAVE, SHIELD

const HEALTH_BAR_SCENE := preload("res://scenes/ui/health_bar.tscn")
const PROJECTILE_SCENE := preload("res://scenes/bosses/boss_projectile.tscn")

var _health_bar: Node2D = null


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 8
	collision_mask = 1
	_original_modulate = modulate

	_health_bar = HEALTH_BAR_SCENE.instantiate()
	_health_bar.bar_width = 44.0
	_health_bar.bar_height = 4.0
	_health_bar.bar_offset = Vector2(0, -44)
	_health_bar.fill_color = Color(0.9, 0.1, 0.1)
	add_child(_health_bar)
	_health_bar.set_health(health, MAX_HEALTH)

	_enter_form(Form.BLOB)


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

	_draw_timer += delta

	# Morphing state
	if _is_morphing:
		_morph_timer -= delta
		velocity.x = 0.0
		if _morph_timer <= 0.0:
			_is_morphing = false
			_form_index = (_form_index + 1) % FORM_ORDER.size()
			_current_form = FORM_ORDER[_form_index] as Form
			_enter_form(_current_form)
		move_and_slide()
		queue_redraw()
		return

	# Form timer
	_form_timer -= delta
	if _form_timer <= 0.0:
		_start_morph()
		move_and_slide()
		queue_redraw()
		return

	# Form-specific behavior
	match _current_form:
		Form.BLOB:
			_do_blob(delta)
		Form.SPIKE:
			_do_spike(delta)
		Form.WAVE:
			_do_wave(delta)
		Form.SHIELD:
			_do_shield(delta)

	move_and_slide()
	queue_redraw()


func _enter_form(form: Form) -> void:
	_form_timer = FORM_DURATION
	_attack_timer = 0.0
	match form:
		Form.BLOB:
			_blob_direction = 1.0 if randf() > 0.5 else -1.0
			_blob_bounce_timer = 0.0


func _start_morph() -> void:
	_is_morphing = true
	_morph_timer = MORPH_DURATION
	velocity = Vector2.ZERO


# -- Form: Blob ---------------------------------------------------------------

func _do_blob(delta: float) -> void:
	velocity.x = BLOB_SPEED * _blob_direction

	# Bounce off walls
	if is_on_wall():
		_blob_direction *= -1.0

	# Random direction changes
	_blob_bounce_timer += delta
	if _blob_bounce_timer > 1.5:
		_blob_bounce_timer = 0.0
		if randf() < 0.4:
			_blob_direction *= -1.0
		# Random bounce
		if is_on_floor() and randf() < 0.5:
			velocity.y = -200.0

	# Contact damage
	for p in get_tree().get_nodes_in_group("players"):
		if not p is Node2D:
			continue
		var dist: float = global_position.distance_to(p.global_position)
		if dist < 30.0:
			_damage_player(p, BLOB_CONTACT_DAMAGE)


# -- Form: Spike ---------------------------------------------------------------

func _do_spike(delta: float) -> void:
	velocity.x = 0.0

	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_attack_timer = SPIKE_INTERVAL
		_fire_spikes()


func _fire_spikes() -> void:
	for i in range(SPIKE_PROJECTILE_COUNT):
		var angle: float = (TAU / float(SPIKE_PROJECTILE_COUNT)) * float(i)
		var dir := Vector2(cos(angle), sin(angle))
		var proj: Node2D = PROJECTILE_SCENE.instantiate()
		proj.global_position = global_position
		proj.direction = dir
		proj.speed = SPIKE_PROJECTILE_SPEED
		proj.damage = SPIKE_PROJECTILE_DAMAGE
		proj.color = Color(0.85, 0.75, 0.55)  # Tan/batter color
		proj.projectile_size = 4.0
		proj.lifetime = 3.0
		get_tree().current_scene.add_child(proj)
	AudioManager.play("enemy_hit", -4.0, 1.0)


# -- Form: Wave ----------------------------------------------------------------

func _do_wave(delta: float) -> void:
	velocity.x = 0.0

	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_attack_timer = WAVE_INTERVAL
		_send_ground_waves()


func _send_ground_waves() -> void:
	# Left wave
	_spawn_ground_wave(-1.0)
	# Right wave
	_spawn_ground_wave(1.0)
	AudioManager.play("enemy_hit", -2.0, 0.8)


func _spawn_ground_wave(dir: float) -> void:
	var wave := Area2D.new()
	wave.global_position = global_position + Vector2(dir * 20.0, 0)
	wave.collision_layer = 4
	wave.collision_mask = 2

	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(30, 20)
	col.shape = shape
	wave.add_child(col)

	var rect := ColorRect.new()
	rect.size = Vector2(30, 20)
	rect.position = Vector2(-15, -10)
	rect.color = Color(0.85, 0.75, 0.55, 0.7)
	wave.add_child(rect)

	wave.body_entered.connect(func(body: Node2D) -> void:
		if body.has_method("take_damage"):
			body.take_damage(WAVE_DAMAGE, -1)
		var pi: int = -1
		if "player_index" in body:
			pi = body.get("player_index")
		elif body.has_meta("player_index"):
			pi = body.get_meta("player_index")
		if pi >= 0:
			PlayerManager.damage_player(pi, WAVE_DAMAGE)
	)

	get_tree().current_scene.add_child(wave)

	# Move wave horizontally and destroy after distance
	var tween := wave.create_tween()
	tween.tween_property(wave, "position:x", wave.position.x + dir * 300.0, 1.5)
	tween.tween_callback(wave.queue_free)


# -- Form: Shield --------------------------------------------------------------

func _do_shield(delta: float) -> void:
	# Slow movement toward nearest player
	var target: Node2D = _find_nearest_player()
	if target:
		var dir_x: float = signf(target.global_position.x - global_position.x)
		velocity.x = SHIELD_SPEED * dir_x
	else:
		velocity.x = 0.0

	# Heal
	health = mini(health + int(SHIELD_HEAL_RATE * delta), MAX_HEALTH)
	if _health_bar:
		_health_bar.set_health(health, MAX_HEALTH)


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
	if _is_morphing:
		return  # Invulnerable during morph

	var final_amount: int = amount
	if _current_form == Form.SHIELD:
		final_amount = maxi(1, int(float(amount) * (1.0 - SHIELD_DAMAGE_REDUCTION)))

	health = maxi(0, health - final_amount)
	if _health_bar:
		_health_bar.set_health(health, MAX_HEALTH)
	AudioManager.play("enemy_hit", -2.0, 0.7)
	_hit_flash()
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
	var base_color := Color(0.85, 0.75, 0.55)  # Tan batter
	var dark := Color(0.7, 0.6, 0.4)

	if _is_morphing:
		# Morphing: wobbling amorphous shape
		var wobble: float = sin(_draw_timer * 12.0) * 5.0
		draw_circle(Vector2(wobble, 0), 18.0, base_color)
		draw_circle(Vector2(-wobble, -4), 14.0, dark)
		return

	match _current_form:
		Form.BLOB:
			_draw_blob()
		Form.SPIKE:
			_draw_spike()
		Form.WAVE:
			_draw_wave()
		Form.SHIELD:
			_draw_shield()


func _draw_blob() -> void:
	var base_color := Color(0.85, 0.75, 0.55)
	var highlight := Color(0.95, 0.88, 0.7)
	# Bouncy blob shape
	var squash: float = 1.0 + sin(_draw_timer * 6.0) * 0.15
	var stretch: float = 1.0 - sin(_draw_timer * 6.0) * 0.1
	draw_ellipse_approx(Vector2.ZERO, 16.0 * squash, 14.0 * stretch, base_color)
	# Eyes
	draw_circle(Vector2(-5, -4), 3.0, Color.WHITE)
	draw_circle(Vector2(5, -4), 3.0, Color.WHITE)
	draw_circle(Vector2(-5, -4), 1.5, Color(0.3, 0.2, 0.1))
	draw_circle(Vector2(5, -4), 1.5, Color(0.3, 0.2, 0.1))


func _draw_spike() -> void:
	var base_color := Color(0.85, 0.75, 0.55)
	var spike_color := Color(0.7, 0.55, 0.35)
	# Wider body
	draw_circle(Vector2.ZERO, 18.0, base_color)
	# Spikes radiating out
	for i in range(SPIKE_PROJECTILE_COUNT):
		var angle: float = (TAU / float(SPIKE_PROJECTILE_COUNT)) * float(i) + _draw_timer
		var spike_base := Vector2(cos(angle), sin(angle)) * 14.0
		var spike_tip := Vector2(cos(angle), sin(angle)) * 26.0
		draw_line(spike_base, spike_tip, spike_color, 3.0)
	# Eyes
	draw_circle(Vector2(-4, -3), 2.5, Color.WHITE)
	draw_circle(Vector2(4, -3), 2.5, Color.WHITE)
	draw_circle(Vector2(-4, -3), 1.0, Color.RED)
	draw_circle(Vector2(4, -3), 1.0, Color.RED)


func _draw_wave() -> void:
	var base_color := Color(0.85, 0.75, 0.55)
	# Flatter shape
	draw_ellipse_approx(Vector2.ZERO, 22.0, 10.0, base_color)
	# Wave lines
	for i in range(3):
		var y_off: float = -3.0 + float(i) * 3.0
		var x1 := Vector2(-20.0, y_off + sin(_draw_timer * 4.0 + float(i)) * 3.0)
		var x2 := Vector2(20.0, y_off + sin(_draw_timer * 4.0 + float(i) + 1.0) * 3.0)
		draw_line(x1, x2, Color(0.7, 0.6, 0.4, 0.6), 1.5)
	# Sleepy eyes
	draw_line(Vector2(-6, -2), Vector2(-2, -2), Color(0.3, 0.2, 0.1), 2.0)
	draw_line(Vector2(2, -2), Vector2(6, -2), Color(0.3, 0.2, 0.1), 2.0)


func _draw_shield() -> void:
	var base_color := Color(0.85, 0.75, 0.55)
	var shield_color := Color(0.6, 0.8, 1.0, 0.4)
	# Round, bigger body
	draw_circle(Vector2.ZERO, 22.0, base_color)
	# Shield aura
	draw_arc(Vector2.ZERO, 26.0, 0, TAU, 32, shield_color, 3.0)
	draw_arc(Vector2.ZERO, 30.0, 0, TAU, 32, Color(0.6, 0.8, 1.0, 0.2), 2.0)
	# Healing sparkles
	for i in range(4):
		var a: float = _draw_timer * 2.0 + float(i) * TAU / 4.0
		var sparkle_pos := Vector2(cos(a) * 20.0, sin(a) * 20.0)
		draw_circle(sparkle_pos, 2.0, Color(0.5, 1, 0.5, 0.7))
	# Content eyes
	draw_circle(Vector2(-6, -4), 3.0, Color.WHITE)
	draw_circle(Vector2(6, -4), 3.0, Color.WHITE)
	draw_circle(Vector2(-6, -4), 1.5, Color(0.2, 0.5, 0.2))
	draw_circle(Vector2(6, -4), 1.5, Color(0.2, 0.5, 0.2))


## Approximate ellipse using a colored polygon.
func draw_ellipse_approx(center: Vector2, rx: float, ry: float, color: Color) -> void:
	var points := PackedVector2Array()
	var segments := 24
	for i in range(segments):
		var angle: float = (TAU / float(segments)) * float(i)
		points.append(center + Vector2(cos(angle) * rx, sin(angle) * ry))
	draw_colored_polygon(points, color)


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
