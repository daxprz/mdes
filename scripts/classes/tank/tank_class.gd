extends "res://scripts/classes/class_component.gd"

## Tank class

var p: Object = null

func inject_context(c: Variant) -> void:
	ctx = c
	p = c.body if c else null

func tick(delta: float) -> void:
	p._tick_tank(delta)

func perform_attack(_intent: Dictionary) -> void:
	_attack_tank()

func perform_special(_intent: Dictionary) -> void:
	_special_tank_slam()

func perform_charged(charge_ratio: float) -> void:
	_charged_tank_shockwave(charge_ratio)


func _attack_tank() -> void:
	# Heavy mace slam - slow, wide, powerful
	AudioManager.play("sword_slash", 2.0, 0.5)
	p._attack_cooldown = 1.2  # Very slow
	var aim: Vector2 = p._get_aim_direction()
	var base_dmg: int = int(45 * PlayerManager.get_skill_bonus(p.player_index, "attack"))
	if p._tank_fortify:
		base_dmg = int(base_dmg * 0.5)  # Less damage while fortified (tradeoff)
	PlayerManager.add_skill_xp(p.player_index, "attack", 2)

	# Wide attack area
	p.attack_area.position = aim * 20.0
	p.attack_area.monitoring = true
	await get_tree().physics_frame
	if not is_inside_tree():
		return

	# VFX: ground slam impact
	p._spawn_vfx(Color(0.7, 0.6, 0.4, 0.6), Vector2(40, 20))

	for body in p.attack_area.get_overlapping_bodies():
		if body.has_method("take_damage"):
			body.take_damage(base_dmg, p.player_index)
			p._spawn_blood_particles(body.global_position)
		if body.has_method("apply_knockback"):
			var kb: Vector2 = aim * 250.0
			body.apply_knockback(kb)
	await get_tree().create_timer(0.15).timeout
	if is_inside_tree():
		p.attack_area.monitoring = false




func _special_tank_slam() -> void:
	# Ground pound - AoE stun around the tank
	AudioManager.play("explosion", 2.0, 0.6)
	AudioManager.play("shield_charge", 0.0, 0.4)
	p._screen_shake(6.0, 0.25)
	p._spawn_vfx(Color(0.6, 0.5, 0.3, 0.7), Vector2(80, 80))

	# Damage + stun all enemies in radius
	for body in get_tree().get_nodes_in_group("enemies"):
		if not body is Node2D:
			continue
		var dist: float = p.global_position.distance_to(body.global_position)
		if dist < 80.0:
			if body.has_method("take_damage"):
				body.take_damage(30, p.player_index)
			if body.has_method("apply_knockback"):
				var kb: Vector2 = (body.global_position - p.global_position).normalized() * 150.0
				body.apply_knockback(kb)
			# Stun via hurt timer
			if body.has_method("apply_slow"):
				body.apply_slow(2.0)
	PlayerManager.add_skill_xp(p.player_index, "special", 7)




func _handle_tank_fortify(delta: float) -> void:
	if p.character_class != PlayerManager.CharacterClass.TANK:
		return
	if _tank_fortify_cooldown > 0.0:
		_tank_fortify_cooldown -= delta

	if p._is_device_action_just_pressed("interact"):
		if p._tank_fortify:
			return
		if _tank_fortify_cooldown > 0.0:
			p._spawn_fail_flash()
			return
		# FORTIFY!
		p._tank_fortify = true
		p._tank_fortify_timer = TANK_FORTIFY_DURATION
		AudioManager.play("shield_charge", 2.0, 0.3)
		p.modulate = Color(0.7, 0.65, 0.5)
		p._spawn_vfx(Color(0.8, 0.7, 0.4, 0.6), Vector2(30, 30))
		var fort_text := Label.new()
		fort_text.text = "FORTIFIED!"
		fort_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fort_text.add_theme_font_size_override("font_size", 12)
		fort_text.modulate = Color(0.8, 0.7, 0.4)
		fort_text.position = p.global_position + Vector2(-25, -40)
		fort_text.z_index = 15
		get_parent().add_child(fort_text)
		var tt := fort_text.create_tween()
		tt.tween_property(fort_text, "position:y", fort_text.position.y - 15, 0.6)
		tt.parallel().tween_property(fort_text, "modulate:a", 0.0, 0.6)
		tt.tween_callback(fort_text.queue_free)

	if p._tank_fortify:
		p._tank_fortify_timer -= delta
		# Pulsing bronze glow
		p.modulate = Color(0.7, 0.65 + sin(p._tank_fortify_timer * 4.0) * 0.05, 0.5)
		# Warning
		if p._tank_fortify_timer <= 2.0:
			if fmod(p._tank_fortify_timer, 0.25) < 0.125:
				p.modulate = Color.WHITE
		if p._tank_fortify_timer <= 0.0:
			p._tank_fortify = false
			_tank_fortify_cooldown = TANK_FORTIFY_COOLDOWN
			p.modulate = Color.WHITE


# -- Melee Enrage (Circle) -----------------------------------------------------



func _charged_tank_shockwave(charge_ratio: float) -> void:
	# Massive ground shockwave - bigger than special, stuns longer
	var radius: float = lerpf(60.0, 160.0, charge_ratio)
	var damage: int = int(lerpf(20.0, 70.0, charge_ratio))
	var stun_time: float = lerpf(1.0, 4.0, charge_ratio)
	AudioManager.play("explosion", 4.0, 0.3)
	p._screen_shake(lerpf(4.0, 12.0, charge_ratio), 0.3)
	p._spawn_vfx(Color(0.6, 0.5, 0.3, 0.8), Vector2(radius * 2, radius * 2))
	for body in get_tree().get_nodes_in_group("enemies"):
		if not body is Node2D:
			continue
		var dist: float = p.global_position.distance_to(body.global_position)
		if dist < radius:
			if body.has_method("take_damage"):
				body.take_damage(damage, p.player_index)
			if body.has_method("apply_knockback"):
				var kb: Vector2 = (body.global_position - p.global_position).normalized() * 300.0
				body.apply_knockback(kb)
			if body.has_method("apply_slow"):
				body.apply_slow(stun_time)
	PlayerManager.add_skill_xp(p.player_index, "charge", 5)


