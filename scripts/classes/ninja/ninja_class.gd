extends "res://scripts/classes/class_component.gd"

## Ninja class

var p: Object = null

func inject_context(c: Variant) -> void:
	ctx = c
	p = c.body if c else null

func tick(delta: float) -> void:
	p._tick_ninja(delta)

func perform_attack(_intent: Dictionary) -> void:
	_attack_jumper()

func perform_special(_intent: Dictionary) -> void:
	_special_jumper_dive()

func perform_charged(charge_ratio: float) -> void:
	_charged_jumper_meteor(charge_ratio)



# -- Jumper Abilities ----------------------------------------------------------

func _attack_jumper() -> void:
	# 3 fast sequential slices - damage scales with speed
	p._attack_cooldown = 0.45
	PlayerManager.add_skill_xp(p.player_index, "attack", 2)
	var aim: Vector2 = p._get_aim_direction()
	var speed_ratio: float = clampf(p.velocity.length() / 400.0, 0.0, 1.0)
	var base_dmg: int = int(lerpf(6.0, 20.0, speed_ratio) * PlayerManager.get_skill_bonus(p.player_index, "attack"))

	# Slash angles: horizontal, diagonal down, diagonal up
	var slash_angles: Array[float] = [0.0, 0.5, -0.5]
	var slash_colors: Array[Color] = [
		Color(0.3, 1.0, 1.0, 0.8),
		Color(0.5, 1.0, 0.9, 0.7),
		Color(0.2, 0.9, 1.0, 0.9),
	]

	for i in range(3):
		if not is_inside_tree():
			return
		if i > 0:
			await get_tree().create_timer(0.07).timeout
			if not is_inside_tree():
				return

		AudioManager.play("sword_slash", -2.0, 1.3 + i * 0.15)

		# Slash line VFX
		var slash_dir: Vector2 = aim.rotated(slash_angles[i])
		var slash := ColorRect.new()
		slash.color = slash_colors[i]
		slash.size = Vector2(35, 2)
		slash.position = p.global_position + slash_dir * 6.0
		slash.rotation = slash_dir.angle() + 0.785
		slash.z_index = 9
		get_parent().add_child(slash)
		var st := slash.create_tween()
		st.set_parallel(true)
		st.tween_property(slash, "position", slash.position + slash_dir * 18.0, 0.08)
		st.tween_property(slash, "modulate:a", 0.0, 0.12)
		st.chain().tween_callback(slash.queue_free)

		# Hit check
		p.attack_area.position = aim * 20.0
		p.attack_area.monitoring = true
		await get_tree().physics_frame
		if not is_inside_tree():
			return
		for body in p.attack_area.get_overlapping_bodies():
			if body.has_method("take_damage"):
				body.take_damage(base_dmg, p.player_index)
				p._spawn_blood_particles(body.global_position)
			if body.has_method("apply_knockback") and i == 2:
				body.apply_knockback(aim * (100.0 + speed_ratio * 200.0))
		p.attack_area.monitoring = false
	await get_tree().create_timer(0.1).timeout
	if is_inside_tree():
		p.attack_area.monitoring = false




func _special_jumper_dive() -> void:
	# Dive kick downward - faster the higher you are
	if p.is_on_floor():
		# On ground: super jump upward
		p.velocity.y = JUMPER_JUMP_VELOCITY * 1.5
		AudioManager.play("jump", 0.0, 0.6)
		p._spawn_vfx(Color(0.3, 1.0, 1.0, 0.6), Vector2(24, 24))
		PlayerManager.add_skill_xp(p.player_index, "special", 7)
	else:
		# In air: DIVE KICK downward at aimed angle
		p._jumper_dive_active = true
		var aim: Vector2 = p._get_aim_direction()
		if aim.y < 0.3:
			aim.y = 0.5  # Default to downward-ish if aiming up
		aim = aim.normalized()
		p.velocity = aim * 700.0
		AudioManager.play("shield_charge", 0.0, 1.6)
		p.modulate = Color(0.3, 1.0, 1.0)
		PlayerManager.add_skill_xp(p.player_index, "special", 7)




func _handle_jumper_dash() -> void:
	if p.character_class != PlayerManager.CharacterClass.NINJA:
		return
	if p._jumper_dash_cooldown > 0.0:
		p._jumper_dash_cooldown -= get_process_delta_time()
	if _jumper_pickup_cooldown > 0.0:
		_jumper_pickup_cooldown -= get_process_delta_time()

	if not p._is_device_action_just_pressed("interact"):
		return

	# If holding an item, THROW IT in aimed direction
	if is_instance_valid(p._jumper_held_item):
		_throw_held_item()
		return

	# Try to PICK UP a loose item nearby (bombs, muffins, rocks, enemy projectiles)
	if _jumper_pickup_cooldown <= 0.0:
		var nearest_item: Node2D = null
		var nearest_dist: float = JUMPER_PICKUP_RANGE

		# Check for loose projectiles (bombs, arrows, bolts)
		for node in get_tree().get_nodes_in_group("loose_items"):
			if node is Node2D:
				var dist: float = p.global_position.distance_to(node.global_position)
				if dist < nearest_dist:
					nearest_dist = dist
					nearest_item = node

		# Also check for boss projectiles we can catch!
		if not nearest_item:
			for node in get_tree().get_nodes_in_group("boss_projectiles"):
				if node is Node2D:
					var dist: float = p.global_position.distance_to(node.global_position)
					if dist < nearest_dist:
						nearest_dist = dist
						nearest_item = node

		# Check for enemy projectiles (arrows from cookie archers etc)
		if not nearest_item:
			for node in get_children():
				pass  # Projectiles aren't in a group by default

		if nearest_item:
			_pickup_item(nearest_item)
			_jumper_pickup_cooldown = 0.5
			return

	# Nothing to pick up: AIR DASH
	if p._jumper_dash_cooldown > 0.0:
		p._spawn_fail_flash()
		return
	p._jumper_dash_cooldown = JUMPER_DASH_COOLDOWN
	var aim: Vector2 = p._get_aim_direction()
	p.velocity = aim * JUMPER_DASH_SPEED
	p.velocity.y = minf(p.velocity.y, -50.0)
	AudioManager.play("shadow_dash", -2.0, 1.5)
	p._spawn_vfx(Color(0.3, 1.0, 1.0, 0.5), Vector2(14, 28))
	for i in range(5):
		var trail := ColorRect.new()
		trail.color = Color(0.3, 1.0, 1.0, 0.4 - i * 0.06)
		trail.size = Vector2(8, 8)
		trail.position = p.global_position - aim * (i * 8)
		trail.z_index = -1
		get_parent().add_child(trail)
		var tt := trail.create_tween()
		tt.tween_property(trail, "modulate:a", 0.0, 0.3)
		tt.tween_callback(trail.queue_free)




func _pickup_item(item: Node2D) -> void:
	# Grab a loose physical item and carry it
	p._jumper_held_item = item
	AudioManager.play("muffin_collect", 0.0, 0.8)

	# Stop the item's physics/movement
	if item.has_method("set_physics_process"):
		item.set_physics_process(false)
	if item.has_method("set_process"):
		item.set_process(false)
	if "velocity" in item:
		item.velocity = Vector2.ZERO

	# Reparent to player so it follows
	var old_pos: Vector2 = item.global_position
	if item.get_parent():
		item.get_parent().remove_child(item)
	add_child(item)
	item.position = Vector2(0, -20)  # Float above head

	# "PICKED UP!" text
	var pickup_text := Label.new()
	pickup_text.text = "GRABBED!"
	pickup_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pickup_text.add_theme_font_size_override("font_size", 10)
	pickup_text.modulate = Color(0.3, 1.0, 1.0)
	pickup_text.position = p.global_position + Vector2(-20, -40)
	pickup_text.z_index = 15
	get_parent().add_child(pickup_text)
	var tt := pickup_text.create_tween()
	tt.tween_property(pickup_text, "position:y", pickup_text.position.y - 15, 0.5)
	tt.parallel().tween_property(pickup_text, "modulate:a", 0.0, 0.5)
	tt.tween_callback(pickup_text.queue_free)




func _throw_held_item() -> void:
	if not is_instance_valid(p._jumper_held_item):
		p._jumper_held_item = null
		return

	var item: Node2D = p._jumper_held_item
	p._jumper_held_item = null

	var aim: Vector2 = p._get_aim_direction()
	AudioManager.play("crossbow_shoot", 0.0, 0.9)

	# Reparent back to the scene
	var throw_pos: Vector2 = p.global_position + aim * 16.0
	remove_child(item)
	get_parent().add_child(item)
	item.global_position = throw_pos

	# Re-enable physics and launch it
	if item.has_method("set_physics_process"):
		item.set_physics_process(true)
	if item.has_method("set_process"):
		item.set_process(true)
	if "velocity" in item:
		item.velocity = aim * 400.0
	if "direction" in item:
		item.direction = aim
	if "speed" in item:
		item.speed = 400.0

	# Make it damage enemies on contact if it doesn't already
	if item.has_method("take_damage"):
		pass  # It's an enemy projectile, already does damage
	elif "damage" in item:
		item.damage = maxi(item.damage, 20)  # At least 20 damage

	p._spawn_vfx(Color(0.3, 1.0, 1.0, 0.4), Vector2(12, 12))




func _handle_jumper_momentum(delta: float) -> void:
	if p.character_class != PlayerManager.CharacterClass.NINJA:
		return

	# Dive kick landing
	if p._jumper_dive_active and p.is_on_floor():
		p._jumper_dive_active = false
		p.modulate = Color.WHITE
		# Impact damage based on fall speed
		var impact_speed: float = clampf(p.velocity.length() / 500.0, 0.0, 1.0)
		var impact_dmg: int = int(lerpf(10.0, 50.0, impact_speed))
		AudioManager.play("explosion", -2.0, 1.2)
		p._spawn_vfx(Color(0.3, 1.0, 1.0, 0.7), Vector2(40 + impact_speed * 40, 16))
		p._screen_shake(impact_speed * 5.0, 0.15)

		for body in get_tree().get_nodes_in_group("enemies"):
			if not body is Node2D:
				continue
			var dist: float = p.global_position.distance_to(body.global_position)
			if dist < 50.0 + impact_speed * 30.0 and body.has_method("take_damage"):
				body.take_damage(impact_dmg, p.player_index)
				if body.has_method("apply_knockback"):
					var kb: Vector2 = (body.global_position - p.global_position).normalized()
					body.apply_knockback(kb * 300.0)

	# Speed trails while moving fast
	if p.velocity.length() > 200.0 and randi() % 3 == 0:
		var trail := ColorRect.new()
		trail.color = Color(0.3, 1.0, 1.0, 0.25)
		trail.size = Vector2(4, 4)
		trail.position = p.global_position + Vector2(randf_range(-4, 4), randf_range(-4, 4))
		trail.z_index = -1
		get_parent().add_child(trail)
		var tt := trail.create_tween()
		tt.tween_property(trail, "modulate:a", 0.0, 0.2)
		tt.tween_callback(trail.queue_free)




func _charged_jumper_meteor(charge_ratio: float) -> void:
	# METEOR DROP - launch up then slam down with massive impact
	AudioManager.play("jump", 2.0, 0.4)
	p.velocity.y = lerpf(-600.0, -900.0, charge_ratio)
	p._jumper_dive_active = true
	p.modulate = Color(1.0, 0.6, 0.2)  # Orange meteor tint

	# Delay then dive - after reaching apex
	await get_tree().create_timer(lerpf(0.3, 0.6, charge_ratio)).timeout
	if not is_inside_tree():
		return
	p.velocity.y = lerpf(500.0, 900.0, charge_ratio)
	p.velocity.x = 0.0
	p.modulate = Color(1.0, 0.3, 0.1)  # Red-hot
	p._spawn_vfx(Color(1.0, 0.5, 0.1, 0.7), Vector2(20, 20))
	PlayerManager.add_skill_xp(p.player_index, "charge", 5)


# -- Tank Abilities ------------------------------------------------------------

const TANK_FORTIFY_DURATION := 8.0
const TANK_FORTIFY_COOLDOWN := 25.0

