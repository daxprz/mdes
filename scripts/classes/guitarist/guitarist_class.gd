extends "res://scripts/classes/class_component.gd"

## Guitarist class

var p: Object = null

func inject_context(c: Variant) -> void:
	ctx = c
	p = c.body if c else null

func tick(delta: float) -> void:
	p._tick_guitarist(delta)

func perform_attack(_intent: Dictionary) -> void:
	_handle_guitarist_amp_up()

func perform_charged(charge_ratio: float) -> void:
	_charged_guitarist_power_chord(charge_ratio)



func _handle_guitarist_amp_up(delta: float) -> void:
	if p.character_class != PlayerManager.CharacterClass.GUITARIST:
		return
	if _guitarist_amp_up_cooldown > 0.0:
		_guitarist_amp_up_cooldown -= delta

	# Toggle amp up on Circle press
	if p._is_device_action_just_pressed("interact"):
		if _guitarist_amp_up_active:
			return  # Can't cancel early
		if _guitarist_amp_up_cooldown > 0.0:
			p._spawn_fail_flash()
			return
		# AMP UP!
		_guitarist_amp_up_active = true
		_guitarist_amp_up_timer = GUITARIST_AMP_DURATION
		AudioManager.play("shield_charge", 2.0, 0.6)
		AudioManager.play("menu_confirm", 0.0, 0.8)
		p.modulate = Color(1.2, 1.0, 0.5)

		# "AMP UP!" text
		var amp_text := Label.new()
		amp_text.text = "AMP UP!"
		amp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		amp_text.add_theme_font_size_override("font_size", 14)
		amp_text.modulate = Color(1.0, 0.9, 0.2)
		amp_text.position = p.global_position + Vector2(-22, -40)
		amp_text.z_index = 15
		get_parent().add_child(amp_text)
		var tt := amp_text.create_tween()
		tt.tween_property(amp_text, "position:y", amp_text.position.y - 20, 0.8)
		tt.parallel().tween_property(amp_text, "modulate:a", 0.0, 0.8)
		tt.tween_callback(amp_text.queue_free)

	# While amp up is active
	if _guitarist_amp_up_active:
		_guitarist_amp_up_timer -= delta

		# Golden aura pulse
		var pulse: float = 0.15 + sin(_guitarist_amp_up_timer * 4.0) * 0.1
		p.modulate = Color(1.2, 1.0 + pulse, 0.5 + pulse)

		# Golden particles
		if randi() % 5 == 0:
			var gp := ColorRect.new()
			gp.color = Color(1.0, 0.9, 0.3, 0.5)
			gp.size = Vector2(2, 2)
			gp.position = p.global_position + Vector2(randf_range(-12, 12), randf_range(-12, 12))
			gp.z_index = 7
			get_parent().add_child(gp)
			var gt := gp.create_tween()
			gt.tween_property(gp, "position:y", gp.position.y - randf_range(5, 12), 0.4)
			gt.parallel().tween_property(gp, "modulate:a", 0.0, 0.4)
			gt.tween_callback(gp.queue_free)

		# Boost nearby allies
		for p in get_tree().get_nodes_in_group("players"):
			if not (p is CharacterBody2D):
				continue
			if p == self:
				continue
			var dist: float = p.global_position.distance_to(p.global_position)
			if dist < GUITARIST_AMP_RADIUS:
				# Speed boost (temporary per-frame)
				if "velocity" in p:
					p.velocity *= 1.0 + 0.20 * delta * 60.0 * 0.016

		if _guitarist_amp_up_timer <= 0.0:
			_guitarist_amp_up_active = false
			_guitarist_amp_up_cooldown = GUITARIST_AMP_COOLDOWN
			p.modulate = Color.WHITE




func _charged_guitarist_power_chord(charge_ratio: float) -> void:
	# Charged power chord: bigger blast wave
	var mana_cost: int = int(lerpf(15.0, 40.0, charge_ratio))
	if not PlayerManager.use_mana(p.player_index, mana_cost):
		p._spawn_fail_flash()
		return

	AudioManager.play("explosion", 6.0, 0.25)
	AudioManager.play("shield_charge", 4.0, 0.35)
	PlayerManager.add_skill_xp(p.player_index, "charge", 5)

	var aim: Vector2 = p._get_aim_direction()
	var aim_angle: float = aim.angle()
	var arc_half: float = deg_to_rad(lerpf(30.0, 45.0, charge_ratio))
	var radius: float = lerpf(150.0, 200.0, charge_ratio)
	var push: float = lerpf(300.0, 500.0, charge_ratio)
	var dmg: int = int(lerpf(5.0, 12.0, charge_ratio))

	p._screen_shake(lerpf(3.0, 8.0, charge_ratio), 0.25)
	_spawn_blast_wave_arc(aim_angle, arc_half, radius, 200.0, lerpf(0.5, 0.7, charge_ratio), dmg, push)


