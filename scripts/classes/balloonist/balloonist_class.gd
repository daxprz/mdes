extends "res://scripts/classes/class_component.gd"

## Balloonist class

var p: Object = null

func inject_context(c: Variant) -> void:
	ctx = c
	p = c.body if c else null

func tick(delta: float) -> void:
	_handle_balloonist_float(delta)


func perform_attack(_intent: Dictionary) -> void:
	_handle_balloonist_float()

func perform_special(_intent: Dictionary) -> void:
	_special_balloonist_burst()

func perform_charged(charge_ratio: float) -> void:
	_charged_balloonist_barrage(charge_ratio)



func _handle_balloonist_float(delta: float) -> void:
	if p.character_class != PlayerManager.CharacterClass.BALLOONIST:
		return
	if _balloonist_float_cooldown > 0.0:
		_balloonist_float_cooldown -= delta

	if p._is_device_action_just_pressed("interact"):
		if p._balloonist_floating:
			return
		if _balloonist_float_cooldown > 0.0:
			p._spawn_fail_flash()
			return
		# Tie a balloon to self - float upward!
		p._balloonist_floating = true
		p._balloonist_float_timer = BALLOONIST_FLOAT_DURATION
		AudioManager.play("summon", -2.0, 1.4)

	if p._balloonist_floating:
		p._balloonist_float_timer -= delta
		# Float upward gently
		p.velocity.y = lerpf(p.velocity.y, -80.0, delta * 3.0)
		# Can still move left/right but slowly
		# Pink balloon visual drawn above head
		if randi() % 8 == 0:
			p._spawn_vfx(Color(0.9, 0.4, 0.7, 0.3), Vector2(6, 6))
		# Warning
		if p._balloonist_float_timer <= 2.0:
			if fmod(p._balloonist_float_timer, 0.3) < 0.15:
				p.modulate = Color(0.9, 0.5, 0.7)
			else:
				p.modulate = Color.WHITE
		else:
			p.modulate = Color(0.95, 0.8, 0.9)
		if p._balloonist_float_timer <= 0.0:
			p._balloonist_floating = false
			_balloonist_float_cooldown = BALLOONIST_FLOAT_COOLDOWN
			p.modulate = Color.WHITE
			AudioManager.play("explosion", -8.0, 2.0)  # Pop


func _attack_balloonist() -> void:
	# Max 10 active balloons
	var active_count: int = 0
	for dart in get_tree().get_nodes_in_group("balloon_darts"):
		if dart.has_method("_get_entity_weight") and dart.get("owner_index") == p.player_index:
			active_count += 1
	if active_count >= 10:
		p._spawn_fail_flash()
		return

	# 3x faster fire rate (0.8 → 0.27)
	AudioManager.play("crossbow_shoot", -3.0, 1.5)
	p._attack_cooldown = 0.27
	PlayerManager.add_skill_xp(p.player_index, "attack", 2)

	var aim: Vector2 = p._get_aim_direction()
	var dart_script := load("res://scripts/characters/balloon_dart.gd")
	var dart := Node2D.new()
	dart.set_script(dart_script)
	dart.dart_direction = aim
	dart.owner_index = p.player_index
	dart.global_position = p.global_position + aim * 12.0
	get_parent().add_child(dart)

	# Limit balloons on screen to 20 — pop the oldest when exceeding
	const MAX_BALLOONS := 20
	var all_darts: Array = get_tree().get_nodes_in_group("balloon_darts")
	while all_darts.size() > MAX_BALLOONS:
		var oldest: Node2D = all_darts[0]
		if oldest.has_method("_spawn_pop_particles"):
			oldest._spawn_pop_particles()
		if oldest.has_method("_detach_and_free"):
			oldest._detach_and_free()
		else:
			oldest.queue_free()
		all_darts.remove_at(0)




func _special_balloonist_burst() -> void:
	# Pop all active balloons for AoE damage around each
	AudioManager.play("explosion", -2.0, 1.8)
	PlayerManager.add_skill_xp(p.player_index, "special", 7)

	var popped: int = 0
	for dart in get_tree().get_nodes_in_group("balloon_darts"):
		if dart is Node2D and dart.has_method("_detach_and_free"):
			# Damage enemies near the balloon
			var balloon_pos: Vector2 = dart.get("_balloon_pos") if "_balloon_pos" in dart else dart.global_position
			for body in get_tree().get_nodes_in_group("enemies"):
				if body is Node2D:
					var dist: float = balloon_pos.distance_to(body.global_position)
					if dist < 60.0 and body.has_method("take_damage"):
						body.take_damage(20, p.player_index)
						if body.has_method("apply_knockback"):
							var kb: Vector2 = (body.global_position - balloon_pos).normalized() * 200.0
							body.apply_knockback(kb)
			dart._spawn_pop_particles()
			dart._detach_and_free()
			popped += 1

	if popped > 0:
		p._spawn_vfx(Color(0.9, 0.4, 0.7, 0.5), Vector2(30, 30))
	else:
		p._spawn_fail_flash()
		_special_cooldown = 0.0




func _charged_balloonist_barrage(charge_ratio: float) -> void:
	# Shoot multiple balloon darts in a spread
	var count: int = int(lerpf(3.0, 8.0, charge_ratio))
	var spread: float = lerpf(0.3, 1.0, charge_ratio)
	var aim: Vector2 = p._get_aim_direction()

	AudioManager.play("crossbow_shoot", 0.0, 1.2)
	PlayerManager.add_skill_xp(p.player_index, "charge", 5)

	for i in range(count):
		var t: float = float(i) / maxf(float(count - 1), 1.0)
		var angle: float = lerpf(-spread / 2.0, spread / 2.0, t)
		var dir: Vector2 = aim.rotated(angle)

		var dart_script := load("res://scripts/characters/balloon_dart.gd")
		var dart := Node2D.new()
		dart.set_script(dart_script)
		dart.dart_direction = dir
		dart.owner_index = p.player_index
		dart.global_position = p.global_position + dir * 12.0
		get_parent().add_child(dart)


# -- Jumper Abilities ----------------------------------------------------------

