extends "res://scripts/classes/class_component.gd"

## Mage class

var p: Object = null

func inject_context(c: Variant) -> void:
	ctx = c
	p = c.body if c else null

func tick(delta: float) -> void:
	p._tick_mage(delta)

func perform_attack(_intent: Dictionary) -> void:
	_attack_mage()

func perform_special(_intent: Dictionary) -> void:
	_special_frosting_freeze()

func perform_charged(charge_ratio: float) -> void:
	_charged_mage_bolt(charge_ratio)


func _attack_mage() -> void:
	# Mage: FIREBALL - slow, high damage, fire trail
	if not PlayerManager.use_mana(p.player_index, 5):
		return
	AudioManager.play("explosion", -6.0, 1.5)
	p._attack_cooldown = 0.6
	var scaled_dmg: int = int(18 * PlayerManager.get_skill_bonus(p.player_index, "attack"))
	PlayerManager.add_skill_xp(p.player_index, "attack", 2)

	var aim: Vector2 = p._get_aim_direction()
	p._spawn_fireball(aim, scaled_dmg)




func _special_frosting_freeze() -> void:
	# Mana Potion - restore a big chunk of mana
	var p_data: Dictionary = PlayerManager.get_player(p.player_index)
	if p_data.is_empty():
		return
	var current_mana: float = p_data["mana"]
	var max_mana: float = p_data["max_mana"]
	if current_mana >= max_mana:
		p._spawn_fail_flash()
		_special_cooldown = 0.0
		return

	# Restore 60% of max mana
	var restore_amount: float = max_mana * 0.6
	p_data["mana"] = minf(current_mana + restore_amount, max_mana)

	AudioManager.play("mana_drink")
	AudioManager.play("muffin_collect", -4.0, 0.8)

	# Drink animation - brief pause + purple glow
	p.modulate = Color(0.6, 0.4, 1.0)

	# Blue/purple mana particles spiral upward
	for i in range(12):
		var mana_p := ColorRect.new()
		mana_p.color = [Color(0.4, 0.3, 1.0, 0.8), Color(0.6, 0.5, 1.0, 0.7), Color(0.8, 0.7, 1.0, 0.6)][i % 3]
		mana_p.size = Vector2(4, 4)
		var angle: float = float(i) * TAU / 12.0
		mana_p.position = p.global_position + Vector2(cos(angle) * 12.0, sin(angle) * 12.0)
		mana_p.z_index = 8
		get_parent().add_child(mana_p)
		var pt := mana_p.create_tween()
		pt.set_parallel(true)
		pt.tween_property(mana_p, "position:y", mana_p.position.y - randf_range(20, 40), 0.5)
		pt.tween_property(mana_p, "position:x", mana_p.position.x + randf_range(-8, 8), 0.5)
		pt.tween_property(mana_p, "modulate:a", 0.0, 0.5)
		pt.tween_property(mana_p, "scale", Vector2(0.2, 0.2), 0.5)
		pt.chain().tween_callback(mana_p.queue_free)

	# "MANA+" text floats up
	var mana_text := Label.new()
	mana_text.text = "+%d MANA" % int(restore_amount)
	mana_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mana_text.add_theme_font_size_override("font_size", 10)
	mana_text.modulate = Color(0.5, 0.4, 1.0)
	mana_text.position = p.global_position + Vector2(-20, -30)
	mana_text.z_index = 12
	get_parent().add_child(mana_text)
	var text_tw := mana_text.create_tween()
	text_tw.tween_property(mana_text, "position:y", mana_text.position.y - 25, 0.8)
	text_tw.parallel().tween_property(mana_text, "modulate:a", 0.0, 0.8)
	text_tw.tween_callback(mana_text.queue_free)

	# Fade back
	var mod_tw := create_tween()
	mod_tw.tween_property(self, "modulate", Color.WHITE, 0.3)

	_update_health_bar()
	PlayerManager.add_skill_xp(p.player_index, "special", 7)




# -- Mage Air-Walk -------------------------------------------------------------

func _handle_mage_airwalk_toggle() -> void:
	if p.character_class != PlayerManager.CharacterClass.MAGE:
		return
	if not p._is_device_action_just_pressed("interact"):
		return
	if p._mage_airwalk:
		return
	if _mage_airwalk_cooldown > 0.0:
		p._spawn_fail_flash()
		return

	p._mage_airwalk = true
	p._mage_airwalk_timer = MAGE_AIRWALK_DURATION
	AudioManager.play("airwalk_activate")
	p.modulate = Color(0.7, 0.7, 1.0, 0.9)




func _handle_mage_airwalk(delta: float) -> void:
	if _mage_airwalk_cooldown > 0.0:
		_mage_airwalk_cooldown -= delta
	if not p._mage_airwalk:
		return

	p._mage_airwalk_timer -= delta

	# Drain mana while air-walking (10 mana/sec)
	if not PlayerManager.use_mana(p.player_index, 0):
		pass  # Just checking
	var p_data: Dictionary = PlayerManager.get_player(p.player_index)
	if not p_data.is_empty():
		p_data["mana"] = maxf(0.0, p_data["mana"] - 10.0 * delta)
		if p_data["mana"] <= 0.0:
			p._mage_airwalk = false
			_mage_airwalk_cooldown = MAGE_AIRWALK_COOLDOWN
			p.modulate = Color.WHITE
			AudioManager.play("player_hurt", -6.0, 1.5)
			return

	# Cancel gravity - mage walks on air
	if not p.is_on_floor():
		p.velocity.y = 0.0

	# Move at half speed while air-walking
	var air_speed: float = PlayerManager.get_player(p.player_index).get("speed", 90) * 0.5
	p.velocity.x *= 0.5  # Halve the horizontal speed set by _handle_movement

	# Can also move up/down with the stick
	if p._is_device_action_pressed("move_up"):
		p.velocity.y = -air_speed
	elif p._is_device_action_pressed("move_down"):
		p.velocity.y = air_speed
	elif not p.is_on_floor():
		p.velocity.y = 0.0

	# Sparkle trail under feet
	if randi() % 4 == 0:
		var sparkle := ColorRect.new()
		sparkle.color = [Color(0.6, 0.5, 1.0, 0.5), Color(0.8, 0.7, 1.0, 0.4), Color(1.0, 1.0, 1.0, 0.3)][randi() % 3]
		sparkle.size = Vector2(3, 3)
		sparkle.position = p.global_position + Vector2(randf_range(-6, 6), randf_range(8, 14))
		sparkle.z_index = -1
		get_parent().add_child(sparkle)
		var st := sparkle.create_tween()
		st.tween_property(sparkle, "position:y", sparkle.position.y + randf_range(5, 15), 0.4)
		st.parallel().tween_property(sparkle, "modulate:a", 0.0, 0.4)
		st.tween_callback(sparkle.queue_free)

	# Timer warning: flash when almost out
	if p._mage_airwalk_timer <= 1.5:
		if fmod(p._mage_airwalk_timer, 0.3) < 0.15:
			p.modulate = Color(1.0, 0.5, 0.5, 0.85)
		else:
			p.modulate = Color(0.7, 0.7, 1.0, 0.9)

	# Time's up
	if p._mage_airwalk_timer <= 0.0:
		p._mage_airwalk = false
		_mage_airwalk_cooldown = MAGE_AIRWALK_COOLDOWN
		p.modulate = Color.WHITE
		AudioManager.play("player_hurt", -6.0, 1.5)


# -- Summoner Delegate Mode ----------------------------------------------------



func _charged_mage_bolt(charge_ratio: float) -> void:
	# BEAM OF LIGHT - costs lots of mana, deals massive damage
	var mana_cost: int = int(lerpf(40.0, 100.0, charge_ratio))
	if not PlayerManager.use_mana(p.player_index, mana_cost):
		p._spawn_fail_flash()
		return

	var aim: Vector2 = p._get_aim_direction()
	var beam_range: float = lerpf(200.0, 500.0, charge_ratio)
	var beam_width: float = lerpf(8.0, 24.0, charge_ratio)
	var beam_damage: int = int(lerpf(40.0, 120.0, charge_ratio))
	var beam_hits: int = int(lerpf(3.0, 8.0, charge_ratio))  # Hits per enemy

	AudioManager.play("beam_fire")
	AudioManager.play("shield_charge", 2.0, 1.5)
	PlayerManager.add_skill_xp(p.player_index, "charge", 5)

	# Brief charge-up flash
	p.modulate = Color(1.0, 1.0, 2.0)

	# --- Raycast to find beam endpoint ---
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		p.global_position,
		p.global_position + aim * beam_range,
		1  # World layer only for endpoint
	)
	query.exclude = [get_rid()]
	var result: Dictionary = space.intersect_ray(query)
	var beam_end: Vector2 = p.global_position + aim * beam_range
	if result:
		beam_end = result["position"]

	var beam_length: float = p.global_position.distance_to(beam_end)

	# --- Draw the beam (multiple layers for glow effect) ---
	var beam_start: Vector2 = p.global_position + aim * 8.0

	# Outer glow (wide, faint)
	var glow := ColorRect.new()
	glow.color = Color(0.6, 0.5, 1.0, 0.3)
	glow.size = Vector2(beam_length, beam_width * 3.0)
	glow.position = beam_start - Vector2(0, beam_width * 1.5).rotated(aim.angle())
	glow.rotation = aim.angle()
	glow.z_index = 8
	get_parent().add_child(glow)

	# Middle beam (bright purple/white)
	var mid_beam := ColorRect.new()
	mid_beam.color = Color(0.8, 0.6, 1.0, 0.7)
	mid_beam.size = Vector2(beam_length, beam_width * 1.5)
	mid_beam.position = beam_start - Vector2(0, beam_width * 0.75).rotated(aim.angle())
	mid_beam.rotation = aim.angle()
	mid_beam.z_index = 9
	get_parent().add_child(mid_beam)

	# Core beam (white-hot center)
	var core := ColorRect.new()
	core.color = Color(1.0, 1.0, 1.0, 0.9)
	core.size = Vector2(beam_length, beam_width * 0.5)
	core.position = beam_start - Vector2(0, beam_width * 0.25).rotated(aim.angle())
	core.rotation = aim.angle()
	core.z_index = 10
	get_parent().add_child(core)

	# --- Sparkle particles along the beam ---
	for i in range(int(beam_length / 8.0)):
		var t: float = float(i) / maxf(beam_length / 8.0, 1.0)
		var spark_pos: Vector2 = beam_start.lerp(beam_end, t) + Vector2(randf_range(-beam_width, beam_width), randf_range(-beam_width, beam_width))
		var spark := ColorRect.new()
		spark.color = [Color(1.0, 1.0, 1.0, 0.8), Color(0.7, 0.5, 1.0, 0.7), Color(0.9, 0.8, 1.0, 0.6)][i % 3]
		spark.size = Vector2(3, 3)
		spark.position = spark_pos
		spark.z_index = 11
		get_parent().add_child(spark)
		var st := spark.create_tween()
		st.tween_property(spark, "position", spark_pos + Vector2(randf_range(-15, 15), randf_range(-15, 15)), randf_range(0.2, 0.5))
		st.parallel().tween_property(spark, "modulate:a", 0.0, randf_range(0.3, 0.5))
		st.tween_callback(spark.queue_free)

	# --- Deal damage to all enemies along the beam ---
	var hit_enemies: Array = []
	for body in get_tree().get_nodes_in_group("enemies"):
		if not body is Node2D:
			continue
		# Check if enemy is within the beam rectangle
		var to_enemy: Vector2 = body.global_position - p.global_position
		var along_beam: float = to_enemy.dot(aim)
		if along_beam < 0 or along_beam > beam_length:
			continue
		var perp_dist: float = absf(to_enemy.cross(aim))
		if perp_dist < beam_width * 2.0:
			# HIT! Apply damage multiple times (beam burns)
			if body.has_method("take_damage"):
				for h in range(beam_hits):
					body.take_damage(int(beam_damage / beam_hits), p.player_index)
				hit_enemies.append(body)
				p._spawn_blood_particles(body.global_position)
				# Knockback away from beam
				if body.has_method("apply_knockback"):
					var kb: Vector2 = aim * 200.0
					body.apply_knockback(kb)

	# --- Fade out the beam ---
	var fade_time: float = lerpf(0.3, 0.6, charge_ratio)
	var fade_tw := create_tween()
	fade_tw.set_parallel(true)
	fade_tw.tween_property(glow, "modulate:a", 0.0, fade_time)
	fade_tw.tween_property(mid_beam, "modulate:a", 0.0, fade_time * 0.8)
	fade_tw.tween_property(core, "modulate:a", 0.0, fade_time * 0.6)
	fade_tw.chain().tween_callback(glow.queue_free)
	fade_tw.tween_callback(mid_beam.queue_free)
	fade_tw.tween_callback(core.queue_free)

	# Screen shake
	p._screen_shake(lerpf(2.0, 8.0, charge_ratio), 0.2)

	# Reset p.modulate
	var mod_tw := create_tween()
	mod_tw.tween_property(self, "modulate", Color.WHITE, 0.3)


