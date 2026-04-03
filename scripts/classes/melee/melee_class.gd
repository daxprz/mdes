extends "res://scripts/classes/class_component.gd"

## Melee class

var p: Object = null

func inject_context(c: Variant) -> void:
	ctx = c
	p = c.body if c else null

func tick(delta: float) -> void:
	_handle_melee_enrage(delta)


func perform_attack(_intent: Dictionary) -> void:
	_attack_melee()

func perform_special(_intent: Dictionary) -> void:
	_special_shield_charge()

func perform_charged(charge_ratio: float) -> void:
	_charged_melee_slam(charge_ratio)



func _attack_melee() -> void:
	# Ground slam if airborne
	if not p.is_on_floor():
		_start_ground_slam()
		return

	# Combo: advance if within window, reset if expired
	if p._combo_timer <= 0.0:
		p._combo_count = 0
	var combo_idx: int = mini(p._combo_count, COMBO_DAMAGES.size() - 1)
	var damage: int = COMBO_DAMAGES[combo_idx]
	var reach: float = COMBO_RANGES[combo_idx]

	# Per-combo sound with distinct pitch
	var pitch: float = COMBO_PITCHES[combo_idx]
	var volume: float = 0.0 if combo_idx < COMBO_DAMAGES.size() - 1 else 2.0
	AudioManager.play("sword_slash", volume, pitch)

	# Aim direction determines swing p.position
	var aim: Vector2 = p._get_aim_direction()

	# Spawn large arcing slash VFX with particles
	_spawn_melee_arc(reach, combo_idx)

	# Enable attack area in aimed direction
	var offset: Vector2 = aim * reach
	p.attack_area.position = offset
	p.attack_area.monitoring = true
	# Wait one physics frame for Godot to detect overlaps
	await get_tree().physics_frame
	if not is_inside_tree():
		return

	# Now check for hits
	var attack_bonus: float = PlayerManager.get_skill_bonus(p.player_index, "attack")
	if p._melee_enraged:
		attack_bonus *= MELEE_ENRAGE_DAMAGE_MULT
	for body in p.attack_area.get_overlapping_bodies():
		if body.has_method("take_damage"):
			var scaled_damage: int = int(damage * attack_bonus)
			body.take_damage(scaled_damage, p.player_index)
			PlayerManager.add_skill_xp(p.player_index, "attack", 2)
			# Blood particles on hit!
			p._spawn_blood_particles(body.global_position)
		if combo_idx == COMBO_DAMAGES.size() - 1 and body.has_method("apply_knockback"):
			var kb_dir: Vector2 = Vector2(1.0 if p._facing_right else -1.0, -0.3).normalized()
			body.apply_knockback(kb_dir * 200.0)

	await get_tree().create_timer(0.1).timeout
	if is_inside_tree():
		p.attack_area.monitoring = false

	p._combo_count += 1
	p._combo_timer = COMBO_WINDOW
	if p._combo_count >= COMBO_DAMAGES.size():
		p._combo_count = 0




func _spawn_melee_arc(reach: float, combo_idx: int) -> void:
	# Large sweeping arc in the aimed direction
	var aim: Vector2 = p._get_aim_direction()
	var arc_center: Vector2 = p.global_position + aim * reach * 0.5
	var arc_dir: float = 1.0 if aim.x >= 0.0 else -1.0
	var colors: Array[Color] = [
		Color(0.85, 0.85, 0.9, 0.8),   # Silver
		Color(0.6, 0.6, 0.65, 0.7),    # Grey
		Color(1.0, 0.95, 0.5, 0.7),    # Yellow
		Color(1.0, 1.0, 1.0, 0.9),     # White
	]

	# Spawn arc particles along a curved path
	var particle_count: int = 12 + combo_idx * 4
	for i in range(particle_count):
		var t: float = float(i) / float(particle_count)
		# Arc angle from -60 to +60 degrees (vertical sweep)
		var angle: float = lerpf(-1.0, 1.0, t)
		# Position particles in an arc in front of the player
		var arc_pos: Vector2 = p.global_position + Vector2(
			cos(angle) * reach * 0.8 * arc_dir,
			sin(angle) * reach * 0.6
		)

		var p := ColorRect.new()
		var color_idx: int = i % colors.size()
		p.color = colors[color_idx]
		var psize: float = randf_range(3.0, 6.0 + combo_idx * 2.0)
		p.size = Vector2(psize, psize)
		p.position = arc_pos - Vector2(psize / 2.0, psize / 2.0)
		p.z_index = 8
		get_parent().add_child(p)

		# Particles fly outward slightly then fade
		var fly_dir: Vector2 = (arc_pos - p.global_position).normalized()
		var tween := p.create_tween()
		tween.set_parallel(true)
		tween.tween_property(p, "position", p.position + fly_dir * randf_range(8.0, 20.0), 0.25)
		tween.tween_property(p, "modulate:a", 0.0, 0.3)
		tween.tween_property(p, "scale", Vector2(0.3, 0.3), 0.3)
		tween.chain().tween_callback(p.queue_free)

	# Big central arc sweep visual
	var arc_visual := ColorRect.new()
	arc_visual.color = Color(0.9, 0.9, 1.0, 0.5)
	var arc_width: float = reach * 1.5
	var arc_height: float = reach * 0.8
	arc_visual.size = Vector2(arc_width, arc_height)
	var arc_x: float = 0.0 if p._facing_right else -arc_width
	arc_visual.position = p.global_position + Vector2(arc_x, -arc_height / 2.0)
	arc_visual.z_index = 7
	get_parent().add_child(arc_visual)

	var arc_tween := arc_visual.create_tween()
	arc_tween.set_parallel(true)
	arc_tween.tween_property(arc_visual, "modulate:a", 0.0, 0.2)
	arc_tween.tween_property(arc_visual, "scale:x", 1.3, 0.2)
	arc_tween.chain().tween_callback(arc_visual.queue_free)




# -- Melee Combo & Ground Slam ------------------------------------------------

func _update_combo_timer(delta: float) -> void:
	if p._combo_timer > 0.0:
		p._combo_timer -= delta
		if p._combo_timer <= 0.0:
			p._combo_count = 0




func _start_ground_slam() -> void:
	p._ground_slam_active = true
	p.velocity.y = 600.0  # Slam downward fast
	AudioManager.play("sword_slash", 0.0, 0.6)
	p.modulate = Color(1.0, 0.6, 0.2)  # Orange glow while falling




func _check_ground_slam_landing() -> void:
	if not p._ground_slam_active:
		return
	# Pop any balloons we pass through while falling — doesn't stop the slam
	_ground_slam_pop_balloons()
	if not p.is_on_floor():
		return

	p._ground_slam_active = false
	p.modulate = Color.WHITE
	AudioManager.play("explosion", -4.0, 1.4)

	# Charge ratio determines blast radius and damage (0.0 if no charge)
	var charge_ratio: float = clampf((_charge_time - CHARGE_MIN) / (CHARGE_MAX - CHARGE_MIN), 0.0, 1.0) if _charge_time >= CHARGE_MIN else 0.0
	var blast_radius: float = lerpf(40.0, 120.0, charge_ratio) if charge_ratio > 0.0 else 80.0
	var slam_damage: int = int(lerpf(30.0, 80.0, charge_ratio)) if charge_ratio > 0.0 else _ground_slam_damage

	# Big AoE shockwave VFX - size scales with charge
	p._spawn_vfx(Color(1.0, 0.5, 0.1, 0.7), Vector2(blast_radius * 2.0, 16))

	# Screen shake - briefly offset camera
	p._screen_shake(charge_ratio * 8.0 + 2.0, 0.2)

	# Damage all nearby enemies on the ground
	var slam_bonus: float = PlayerManager.get_skill_bonus(p.player_index, "attack")
	for body in get_tree().get_nodes_in_group("enemies"):
		if not body is Node2D:
			continue
		var dist: float = p.global_position.distance_to(body.global_position)
		if dist < blast_radius and body.has_method("take_damage"):
			body.take_damage(int(slam_damage * slam_bonus), p.player_index)
			if body.has_method("apply_knockback"):
				var kb: Vector2 = (body.global_position - p.global_position).normalized()
				body.apply_knockback(kb * 250.0)

	_charge_time = 0.0




func _ground_slam_pop_balloons() -> void:
	## While ground-slamming downward, pop any balloons the player overlaps.
	## The player keeps falling — balloons don't stop the slam.
	var hit_radius: float = 20.0  # Player body radius for collision
	for balloon in get_tree().get_nodes_in_group("balloon_darts"):
		if not is_instance_valid(balloon) or not balloon is Node2D:
			continue
		if balloon._dart_active or balloon._popping:
			continue
		var dist: float = p.global_position.distance_to(balloon._balloon_pos)
		if dist < hit_radius + balloon._balloon_radius:
			balloon._chain_pop_receive()


# -- Special Abilities ---------------------------------------------------------


func _special_shield_charge() -> void:
	AudioManager.play("shield_charge", 2.0, 0.9)
	var dash_speed: float = 600.0
	var charge_dir: Vector2 = Vector2(1.0 if p._facing_right else -1.0, 0.0)

	# Flag to block normal movement during charge
	p._shield_charging = true

	# Invincible during charge
	collision_layer = 0
	p.modulate = Color(0.4, 0.7, 1.0)

	# Initial burst VFX - big flash
	p._spawn_vfx(Color(0.3, 0.6, 1.0, 0.9), Vector2(48, 32))
	p._spawn_vfx(Color(1.0, 1.0, 1.0, 0.6), Vector2(24, 24))

	# Dash wave
	_spawn_dash_wave(p.global_position, charge_dir, 5)

	# Charge across multiple frames
	p.attack_area.monitoring = true
	var hit_bodies: Array = []
	var charge_frames: int = 14
	for i in range(charge_frames):
		if not is_inside_tree():
			p._shield_charging = false
			return

		p.velocity.x = dash_speed * charge_dir.x
		p.velocity.y = -30.0
		move_and_slide()

		# Check for hits
		var offset := Vector2(24.0 if p._facing_right else -24.0, 0.0)
		p.attack_area.position = offset
		for body in p.attack_area.get_overlapping_bodies():
			if body in hit_bodies:
				continue
			if body.has_method("take_damage"):
				var shield_dmg: int = int(35 * PlayerManager.get_skill_bonus(p.player_index, "attack"))
				body.take_damage(shield_dmg, p.player_index)
				PlayerManager.add_skill_xp(p.player_index, "special", 7)
				hit_bodies.append(body)
				# Impact spark burst on hit
				for s in range(6):
					var spark := ColorRect.new()
					spark.color = [Color(1.0, 0.9, 0.3, 0.9), Color(0.5, 0.8, 1.0, 0.9), Color(1.0, 1.0, 1.0, 0.8)][s % 3]
					spark.size = Vector2(randf_range(2, 5), randf_range(2, 5))
					spark.position = body.global_position + Vector2(randf_range(-8, 8), randf_range(-8, 8))
					spark.z_index = 10
					get_parent().add_child(spark)
					var spark_vel: Vector2 = Vector2(randf_range(-80, 80), randf_range(-100, -20))
					var st := spark.create_tween()
					st.tween_property(spark, "position", spark.position + spark_vel * 0.2, 0.2)
					st.parallel().tween_property(spark, "modulate:a", 0.0, 0.2)
					st.tween_callback(spark.queue_free)
			if body.has_method("apply_knockback"):
				var kb_dir: Vector2 = Vector2(1.0 if p._facing_right else -1.0, -0.4).normalized()
				body.apply_knockback(kb_dir * 400.0)

		# Rich trail particles every frame
		# Blue energy streaks
		for p in range(3):
			var trail := ColorRect.new()
			var trail_colors: Array[Color] = [
				Color(0.3, 0.5, 1.0, 0.7),
				Color(0.5, 0.7, 1.0, 0.5),
				Color(0.8, 0.9, 1.0, 0.4),
			]
			trail.color = trail_colors[p]
			trail.size = Vector2(randf_range(4, 10), randf_range(2, 5))
			trail.position = p.global_position + Vector2(
				-charge_dir.x * randf_range(4, 16),
				randf_range(-10, 10)
			)
			trail.z_index = 7
			get_parent().add_child(trail)
			var drift: Vector2 = Vector2(-charge_dir.x * randf_range(10, 30), randf_range(-15, 15))
			var tt := trail.create_tween()
			tt.set_parallel(true)
			tt.tween_property(trail, "position", trail.position + drift, randf_range(0.15, 0.3))
			tt.tween_property(trail, "modulate:a", 0.0, randf_range(0.2, 0.35))
			tt.tween_property(trail, "scale", Vector2(0.3, 0.3), 0.3)
			tt.chain().tween_callback(trail.queue_free)

		# Ground sparks (if on floor)
		if p.is_on_floor() and i % 2 == 0:
			var ground_spark := ColorRect.new()
			ground_spark.color = Color(1.0, 0.8, 0.3, 0.6)
			ground_spark.size = Vector2(3, 3)
			ground_spark.position = p.global_position + Vector2(randf_range(-6, 6), 12)
			ground_spark.z_index = 6
			get_parent().add_child(ground_spark)
			var gs_tween := ground_spark.create_tween()
			gs_tween.tween_property(ground_spark, "position:y", ground_spark.position.y - randf_range(8, 20), 0.2)
			gs_tween.parallel().tween_property(ground_spark, "modulate:a", 0.0, 0.2)
			gs_tween.tween_callback(ground_spark.queue_free)

		await get_tree().process_frame

	# End charge - final burst
	p._shield_charging = false
	if is_inside_tree():
		p.attack_area.monitoring = false
		collision_layer = 2
		# Deceleration flash
		p._spawn_vfx(Color(0.4, 0.6, 1.0, 0.5), Vector2(30, 30))
		var brake_tween := create_tween()
		brake_tween.tween_property(self, "modulate", Color.WHITE, 0.15)
		p.velocity.x = 0.0




# -- Melee Enrage (Circle) -----------------------------------------------------

func _handle_melee_enrage(delta: float) -> void:
	if p.character_class != PlayerManager.CharacterClass.MELEE:
		return
	if p._melee_enrage_cooldown > 0.0:
		p._melee_enrage_cooldown -= delta

	# Toggle enrage on Circle press
	if p._is_device_action_just_pressed("interact"):
		if p._melee_enraged:
			return  # Can't cancel early
		if p._melee_enrage_cooldown > 0.0:
			p._spawn_fail_flash()
			return
		# ENRAGE!
		p._melee_enraged = true
		p._melee_enrage_timer = MELEE_ENRAGE_DURATION
		AudioManager.play("enrage_roar")
		AudioManager.play("shield_charge", 2.0, 0.5)
		p.modulate = Color(1.3, 0.3, 0.2)
		# Burst VFX
		p._spawn_vfx(Color(1.0, 0.2, 0.1, 0.7), Vector2(40, 40))
		# "ENRAGED!" text
		var rage_text := Label.new()
		rage_text.text = "ENRAGED!"
		rage_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rage_text.add_theme_font_size_override("font_size", 14)
		rage_text.modulate = Color(1.0, 0.3, 0.1)
		rage_text.position = p.global_position + Vector2(-25, -40)
		rage_text.z_index = 15
		get_parent().add_child(rage_text)
		var tt := rage_text.create_tween()
		tt.tween_property(rage_text, "position:y", rage_text.position.y - 20, 0.8)
		tt.parallel().tween_property(rage_text, "modulate:a", 0.0, 0.8)
		tt.tween_callback(rage_text.queue_free)

	# While enraged
	if p._melee_enraged:
		p._melee_enrage_timer -= delta

		# Pulsing red glow
		var pulse: float = 0.2 + sin(p._melee_enrage_timer * 6.0) * 0.1
		p.modulate = Color(1.3, 0.3 + pulse, 0.2 + pulse)

		# Red particles emit while enraged
		if randi() % 6 == 0:
			var rp := ColorRect.new()
			rp.color = Color(1.0, 0.2, 0.0, 0.6)
			rp.size = Vector2(3, 3)
			rp.position = p.global_position + Vector2(randf_range(-8, 8), randf_range(-5, 5))
			rp.z_index = 5
			get_parent().add_child(rp)
			var rt := rp.create_tween()
			rt.tween_property(rp, "position:y", rp.position.y - randf_range(10, 20), 0.3)
			rt.parallel().tween_property(rp, "modulate:a", 0.0, 0.3)
			rt.tween_callback(rp.queue_free)

		# Warning flicker when almost done
		if p._melee_enrage_timer <= 2.0:
			if fmod(p._melee_enrage_timer, 0.2) < 0.1:
				p.modulate = Color.WHITE

		# Enrage ends
		if p._melee_enrage_timer <= 0.0:
			p._melee_enraged = false
			p._melee_enrage_cooldown = MELEE_ENRAGE_COOLDOWN
			p.modulate = Color.WHITE
			AudioManager.play("player_hurt", -4.0, 0.8)


# -- Healer Wind Gust (Circle) -------------------------------------------------

const p.HEALER_GUST_COOLDOWN := 8.0
const p.HEALER_GUST_RADIUS := 100.0
const p.HEALER_GUST_FORCE := 400.0



func _charged_melee_slam(charge_ratio: float) -> void:
	var atk_bonus: float = PlayerManager.get_skill_bonus(p.player_index, "attack")
	if not p.is_on_floor():
		# Already hovering, slam down
		p._ground_slam_active = true
		p.velocity.y = 600.0 + charge_ratio * 200.0
		AudioManager.play("sword_slash", 2.0, 0.5)
		p.modulate = Color(1.0, 0.4, 0.1)
	else:
		# On ground: AoE stomp
		var blast_radius: float = lerpf(40.0, 120.0, charge_ratio)
		var damage: int = int(lerpf(30.0, 80.0, charge_ratio) * atk_bonus)
		AudioManager.play("explosion", -2.0, 1.2)
		p._spawn_vfx(Color(1.0, 0.5, 0.1, 0.7), Vector2(blast_radius * 2.0, 16))
		p._screen_shake(charge_ratio * 8.0 + 2.0, 0.2)
		for body in get_tree().get_nodes_in_group("enemies"):
			if not body is Node2D:
				continue
			var dist: float = p.global_position.distance_to(body.global_position)
			if dist < blast_radius and body.has_method("take_damage"):
				body.take_damage(damage, p.player_index)
				if body.has_method("apply_knockback"):
					var kb: Vector2 = (body.global_position - p.global_position).normalized()
					body.apply_knockback(kb * (200.0 + charge_ratio * 150.0))




# -- Charge Hooks (called by ChargeComponent) ----------------------------------

func on_charge_press() -> void:
	# Melee airborne: instant charge (ground pound hover)
	if not p.is_on_floor() and p._attack_cooldown <= 0.0:
		p._is_charging = true
		p.velocity.y = 0.0

func on_charge_start() -> void:
	if not p.is_on_floor():
		p.velocity.y = 0.0

func on_charge_tick(delta: float, charge_ratio: float) -> void:
	# Glow yellow
	var glow_color := Color(1.0, 1.0, 1.0 - charge_ratio * 0.7, 1.0)
	p.modulate = glow_color
	# Airborne hover
	if not p.is_on_floor():
		p.velocity.y = 0.0
		p._charge_hover_time += delta
		p.position.x += sin(p._charge_hover_time * 20.0) * 2.0 * delta * 20.0

func get_charge_threshold() -> float:
	return 0.3
