extends BossBase

## Boss 2 - Icing Goblin
## Attacks: icing spit (slowing puddle), belly flop, icing shield (phase 2+).

const ICING_SPEED := 200.0
const ICING_DAMAGE := 12
const FLOP_DAMAGE := 30
const FLOP_RADIUS := 90.0

var _shield_active := false
var _shield_timer := 0.0
const SHIELD_DURATION := 4.0
const SHIELD_REDUCTION := 0.5  # Takes half damage


func _setup_boss() -> void:
	max_health = 600
	health = max_health
	_attack_cooldown = 2.0
	_attack_timer = 1.5

	var texture := load("res://assets/sprites/bosses/icing_goblin.png")
	if texture:
		sprite.texture = texture
		sprite.hframes = 4
		sprite.frame = 0
		sprite.scale = Vector2(2.0, 2.0)

	var shape := RectangleShape2D.new()
	shape.size = Vector2(52, 52)
	collision_shape.shape = shape

	add_to_group("bosses")


func _boss_process(delta: float) -> void:
	# Shield timer
	if _shield_active:
		_shield_timer -= delta
		if _shield_timer <= 0.0:
			_shield_active = false
			modulate = Color.WHITE

	# Walk toward nearest player
	var target := get_nearest_player()
	if target:
		face_target(target.global_position)
		var dir: float = signf(target.global_position.x - global_position.x)
		velocity.x = dir * move_speed

		var frame_time: int = Time.get_ticks_msec() / 200
		sprite.frame = frame_time % 4
	else:
		velocity.x = 0.0


func take_damage(amount: int, source_index: int = -1) -> void:
	if _shield_active:
		amount = int(amount * SHIELD_REDUCTION)
	super.take_damage(amount, source_index)


func _choose_attack() -> void:
	var target := get_nearest_player()
	if not target:
		return

	var dist := global_position.distance_to(target.global_position)

	# Phase 2+: chance to use icing shield
	if current_phase >= 2 and not _shield_active and randf() < 0.25:
		_icing_shield()
		return

	# Close range: belly flop
	if dist < FLOP_RADIUS + 20.0:
		_belly_flop()
	else:
		_icing_spit(target)


func _icing_spit(target: Node2D) -> void:
	var dir: Vector2 = (target.global_position - global_position).normalized()
	# Icing spit leaves a slowing puddle
	spawn_projectile(dir, ICING_SPEED, ICING_DAMAGE, Color(0.7, 0.85, 1.0), true)

	# Phase 3: double spit
	if current_phase >= 3:
		await get_tree().create_timer(0.3).timeout
		if is_dead:
			return
		spawn_projectile(dir.rotated(0.15), ICING_SPEED, ICING_DAMAGE, Color(0.7, 0.85, 1.0), true)


func _belly_flop() -> void:
	# Jump up then slam down
	var start_y := position.y
	var tween := create_tween()
	tween.tween_property(self, "position:y", start_y - 60, 0.3).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position:y", start_y, 0.2).set_ease(Tween.EASE_IN)
	tween.tween_callback(_apply_flop_damage)


func _apply_flop_damage() -> void:
	# Screen shake effect placeholder
	var players := get_tree().get_nodes_in_group("players")
	for p in players:
		if not p is Node2D:
			continue
		if global_position.distance_to(p.global_position) <= FLOP_RADIUS:
			if p.has_method("take_damage"):
				p.take_damage(FLOP_DAMAGE)
			elif p.has_meta("player_index"):
				PlayerManager.damage_player(p.get_meta("player_index"), FLOP_DAMAGE)


func _icing_shield() -> void:
	_shield_active = true
	_shield_timer = SHIELD_DURATION
	# Tint blue-white to show shield
	modulate = Color(0.6, 0.8, 1.0, 1.0)


func _on_phase_change(phase: int) -> void:
	if phase == 2:
		# Get faster
		_attack_cooldown = 1.6
		move_speed = 100.0
	elif phase == 3:
		_attack_cooldown = 1.3
		move_speed = 120.0
