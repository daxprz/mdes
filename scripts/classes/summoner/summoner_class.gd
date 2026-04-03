extends "res://scripts/classes/class_component.gd"

## Summoner class

var p: Object = null

func inject_context(c: Variant) -> void:
	ctx = c
	p = c.body if c else null

func tick(_delta: float) -> void:
	pass  # Delegate handled in _physics_process


func perform_attack(_intent: Dictionary) -> void:
	_attack_summoner()

func perform_special(_intent: Dictionary) -> void:
	_special_summon_donut()

func perform_charged(charge_ratio: float) -> void:
	_charged_summoner_donut(charge_ratio)



func _attack_summoner() -> void:
	# Homing mark spell - slow projectile that seeks nearest enemy
	# When it hits, marks the target so donut buddies deal +20-40% damage
	AudioManager.play("summon", -4.0, 1.6)
	p._attack_cooldown = 0.8
	PlayerManager.add_skill_xp(p.player_index, "attack", 2)

	# Find nearest enemy to home toward
	var nearest_enemy: Node2D = null
	var nearest_dist: float = 200.0
	for body in get_tree().get_nodes_in_group("enemies"):
		if body is Node2D:
			var dist: float = p.global_position.distance_to(body.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest_enemy = body

	# Spawn homing orb
	var orb := ColorRect.new()
	orb.color = Color(1.0, 0.6, 0.2, 0.9)
	orb.size = Vector2(6, 6)
	orb.position = p.global_position
	orb.z_index = 6
	get_parent().add_child(orb)

	# Homing flight
	var orb_speed: float = 120.0
	var orb_age: float = 0.0
	var orb_max_age: float = 3.0
	var hit := false

	while orb_age < orb_max_age and is_instance_valid(orb) and is_inside_tree():
		var dt: float = get_process_delta_time()
		orb_age += dt

		# Re-acquire nearest enemy each frame for true homing
		var current_target: Node2D = null
		var best_dist: float = 250.0
		for body in get_tree().get_nodes_in_group("enemies"):
			if body is Node2D:
				var d: float = orb.position.distance_to(body.global_position)
				if d < best_dist:
					best_dist = d
					current_target = body

		if current_target:
			var to_target: Vector2 = (current_target.global_position - orb.position).normalized()
			orb.position += to_target * orb_speed * dt

			# Trail particle
			if randi() % 3 == 0:
				var trail := ColorRect.new()
				trail.color = Color(1.0, 0.7, 0.3, 0.5)
				trail.size = Vector2(3, 3)
				trail.position = orb.position + Vector2(randf_range(-2, 2), randf_range(-2, 2))
				trail.z_index = 5
				get_parent().add_child(trail)
				var tt := trail.create_tween()
				tt.tween_property(trail, "modulate:a", 0.0, 0.3)
				tt.tween_callback(trail.queue_free)

			# Check if hit
			if orb.position.distance_to(current_target.global_position) < 12.0:
				# HIT - deal small damage and MARK the enemy
				var scaled_dmg: int = int(5 * PlayerManager.get_skill_bonus(p.player_index, "attack"))
				if current_target.has_method("take_damage"):
					current_target.take_damage(scaled_dmg, p.player_index)
				# Mark the enemy for bonus donut buddy damage
				current_target.set_meta("summoner_marked", true)
				current_target.set_meta("summoner_mark_owner", p.player_index)
				# Visual mark - orange glow
				current_target.modulate = Color(1.2, 0.9, 0.6)
				# Mark expires after 6 seconds
				_expire_mark_after(current_target, 6.0)
				AudioManager.play("mark_target")
				p._spawn_vfx(Color(1.0, 0.6, 0.2, 0.6), Vector2(20, 20))
				hit = true
				break
		else:
			# No target - drift in aimed direction
			var aim: Vector2 = p._get_aim_direction()
			orb.position += aim * orb_speed * dt

		await get_tree().process_frame

	if is_instance_valid(orb):
		orb.queue_free()




func _expire_mark_after(enemy: Node2D, duration: float) -> void:
	await get_tree().create_timer(duration).timeout
	if is_instance_valid(enemy):
		enemy.remove_meta("summoner_marked")
		enemy.remove_meta("summoner_mark_owner")
		enemy.modulate = Color.WHITE


func _special_summon_donut() -> void:
	# Summon donut buddy (up to 3)
	if p._donut_buddy_count >= 3:
		p._special_cooldown = 0.0
		p._spawn_fail_flash()
		return
	if not PlayerManager.use_mana(p.player_index, 30):
		p._special_cooldown = 0.0
		p._spawn_fail_flash()
		return

	AudioManager.play("summon")
	p._spawn_vfx(Color(1.0, 0.6, 0.2, 0.7), Vector2(30, 30))
	var buddy_scene := load("res://scenes/characters/donut_buddy.tscn") as PackedScene
	if not buddy_scene:
		return
	var buddy := buddy_scene.instantiate()
	buddy.owner_index = p.player_index
	buddy.global_position = p.global_position + Vector2(24.0 if p._facing_right else -24.0, 0.0)
	buddy.tree_exited.connect(func(): p._donut_buddy_count -= 1)
	get_parent().add_child(buddy)
	p._donut_buddy_count += 1


# -- Demolitionist Refuel (Circle) ---------------------------------------------

func _charged_summoner_donut(charge_ratio: float) -> void:
	if p._donut_buddy_count >= 3:
		p._spawn_fail_flash()
		return
	if not PlayerManager.use_mana(p.player_index, 40):
		p._spawn_fail_flash()
		return

	var buddy_scale: float = lerpf(1.5, 2.5, charge_ratio)
	var buddy_hp: int = int(lerpf(30.0, 80.0, charge_ratio))
	var buddy_dmg: int = int(lerpf(8.0, 20.0, charge_ratio))

	AudioManager.play("summon", 2.0, 0.8)
	p._spawn_vfx(Color(1.0, 0.8, 0.2, 0.8), Vector2(40, 40))
	var buddy_scene := load("res://scenes/characters/donut_buddy.tscn") as PackedScene
	if not buddy_scene:
		return
	var buddy := buddy_scene.instantiate()
	buddy.owner_index = p.player_index
	if buddy.has_method("set_empowered"):
		buddy.set_empowered(buddy_hp, buddy_dmg)
	buddy.scale = Vector2(buddy_scale, buddy_scale)
	buddy.global_position = p.global_position + Vector2(24.0 if p._facing_right else -24.0, 0.0)
	buddy.tree_exited.connect(func(): p._donut_buddy_count -= 1)
	get_parent().add_child(buddy)
	p._donut_buddy_count += 1


func _handle_delegate_toggle() -> void:
	if p.character_class != PlayerManager.CharacterClass.SUMMONER:
		return
	if _delegate_cooldown > 0.0:
		_delegate_cooldown -= get_process_delta_time()
	if not p._is_device_action_just_pressed("interact"):
		return

	if p._delegate_active:
		_exit_delegate_mode()
	elif _delegate_cooldown <= 0.0:
		_enter_delegate_mode()
	else:
		p._spawn_fail_flash()




func _enter_delegate_mode() -> void:
	p._delegate_active = true
	p._delegate_timer = DELEGATE_DURATION
	AudioManager.play("summon", -3.0, 1.5)
	# Summoner goes into trance
	p.modulate = Color(0.6, 0.5, 0.8, 0.5)

	# Countdown label on the summoner
	p._delegate_countdown_label = Label.new()
	p._delegate_countdown_label.name = "DelegateCountdown"
	p._delegate_countdown_label.text = "10"
	p._delegate_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p._delegate_countdown_label.add_theme_font_size_override("font_size", 14)
	p._delegate_countdown_label.position = Vector2(-8, -40)
	p._delegate_countdown_label.modulate = Color(0.8, 0.5, 1.0)
	add_child(p._delegate_countdown_label)

	# Spawn ghost delegate
	p._delegate_node = CharacterBody2D.new()
	p._delegate_node.collision_layer = 0
	p._delegate_node.collision_mask = 1
	p._delegate_node.global_position = p.global_position

	var ghost_sprite := ColorRect.new()
	ghost_sprite.name = "GhostSprite"
	ghost_sprite.color = Color(0.8, 0.5, 1.0, 0.4)
	ghost_sprite.size = Vector2(12, 20)
	ghost_sprite.position = Vector2(-6, -14)
	p._delegate_node.add_child(ghost_sprite)

	var glow := ColorRect.new()
	glow.name = "Glow"
	glow.color = Color(0.7, 0.4, 1.0, 0.15)
	glow.size = Vector2(20, 24)
	glow.position = Vector2(-10, -16)
	p._delegate_node.add_child(glow)

	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(10, 18)
	col.shape = shape
	p._delegate_node.add_child(col)

	get_parent().add_child(p._delegate_node)
	_update_buddy_target()




func _exit_delegate_mode() -> void:
	if not p._delegate_active:
		return
	p._delegate_active = false
	_delegate_cooldown = DELEGATE_COOLDOWN

	var teleport_target: Vector2 = p.global_position
	if is_instance_valid(p._delegate_node):
		teleport_target = p._delegate_node.global_position

	# --- Aether Dig-In at old p.position ---
	AudioManager.play("explosion", -2.0, 0.5)
	_spawn_aether_rift(p.global_position)

	# Screen rumble
	p._screen_shake(4.0, 0.2)

	# Summoner "digs into the aether" - shrink + purple flash
	p.modulate = Color(0.6, 0.2, 1.0)
	var dig_in := create_tween()
	dig_in.tween_property(self, "scale", Vector2(0.1, 0.1), 0.3).set_ease(Tween.EASE_IN)
	await dig_in.finished

	# --- Teleport ---
	p.global_position = teleport_target
	if is_instance_valid(p._delegate_node):
		p._delegate_node.queue_free()
		p._delegate_node = null

	# --- Aether Dig-Out at new p.position ---
	AudioManager.play("summon", 0.0, 0.7)
	_spawn_aether_rift(p.global_position)
	p._screen_shake(4.0, 0.2)

	# Summoner "digs out" - grow back + flash
	var dig_out := create_tween()
	dig_out.tween_property(self, "scale", Vector2(1.0, 1.0), 0.3).set_ease(Tween.EASE_OUT)
	await dig_out.finished

	p.modulate = Color.WHITE

	# Clean up countdown label
	if is_instance_valid(p._delegate_countdown_label):
		p._delegate_countdown_label.queue_free()
		p._delegate_countdown_label = null

	_update_buddy_target()




func _spawn_aether_rift(pos: Vector2) -> void:
	# Purple tear in space that emits particles
	var rift := Node2D.new()
	rift.global_position = pos
	rift.z_index = 10
	get_parent().add_child(rift)

	# The rift visual - a jagged purple tear
	var tear := ColorRect.new()
	tear.color = Color(0.5, 0.1, 0.9, 0.8)
	tear.size = Vector2(6, 40)
	tear.position = Vector2(-3, -20)
	rift.add_child(tear)

	# Inner glow
	var inner := ColorRect.new()
	inner.color = Color(0.8, 0.3, 1.0, 0.5)
	inner.size = Vector2(2, 36)
	inner.position = Vector2(-1, -18)
	rift.add_child(inner)

	# Emit purple particles for 4 seconds
	var particle_count := 40
	for i in range(particle_count):
		# Stagger particle spawns
		_spawn_aether_particle_delayed(rift, pos, float(i) * 0.1)

	# Rift fades out after 4 seconds
	var rift_tween := rift.create_tween()
	rift_tween.tween_interval(4.0)
	rift_tween.tween_property(tear, "modulate:a", 0.0, 1.0)
	rift_tween.parallel().tween_property(inner, "modulate:a", 0.0, 1.0)
	rift_tween.tween_callback(rift.queue_free)




func _spawn_aether_particle_delayed(rift: Node2D, pos: Vector2, delay: float) -> void:
	if not is_inside_tree():
		return
	await get_tree().create_timer(delay).timeout
	if not is_instance_valid(rift) or not is_inside_tree():
		return

	var particle := Area2D.new()
	particle.collision_layer = 0
	particle.collision_mask = 8  # Detect enemies
	particle.global_position = pos + Vector2(randf_range(-4, 4), randf_range(-15, 15))

	var pcol := CollisionShape2D.new()
	var pshape := CircleShape2D.new()
	pshape.radius = 5.0
	pcol.shape = pshape
	particle.add_child(pcol)

	# Purple glowing dot
	var dot := ColorRect.new()
	dot.color = Color(0.7, 0.2, 1.0, 0.8)
	dot.size = Vector2(6, 6)
	dot.position = Vector2(-3, -3)
	particle.add_child(dot)

	get_parent().add_child(particle)

	# Float outward in random direction
	var vel: Vector2 = Vector2(randf_range(-40, 40), randf_range(-60, 10))
	var lifetime := 2.0
	var age := 0.0

	# Check for enemy contact
	particle.body_entered.connect(func(body: Node2D) -> void:
		if body.is_in_group("enemies") and body.has_method("_apply_aether_growth"):
			body._apply_aether_growth()
		elif body.is_in_group("enemies"):
			_apply_aether_growth_to(body)
	)

	while age < lifetime and is_instance_valid(particle):
		var dt: float = get_process_delta_time()
		age += dt
		particle.global_position += vel * dt
		vel.y += 20.0 * dt  # Slight gravity
		vel *= (1.0 - 0.5 * dt)  # Drag
		# Fade
		dot.modulate.a = lerpf(0.8, 0.0, age / lifetime)
		if not is_inside_tree():
			break
		await get_tree().process_frame

	if is_instance_valid(particle):
		particle.queue_free()




func _apply_aether_growth_to(enemy: Node2D) -> void:
	# Enemy grows 300% in size and power!
	if enemy.has_meta("aether_grown"):
		return  # Don't stack
	enemy.set_meta("aether_grown", true)

	AudioManager.play("boss_roar", -4.0, 1.5)

	# Visual: purple flash then grow
	enemy.modulate = Color(0.7, 0.3, 1.0)
	var grow_tween := enemy.create_tween()
	grow_tween.tween_property(enemy, "scale", enemy.scale * 3.0, 0.5).set_ease(Tween.EASE_OUT)
	grow_tween.parallel().tween_property(enemy, "modulate", Color(0.9, 0.6, 1.0), 0.5)

	# Buff stats if possible
	if "health" in enemy:
		enemy.health *= 3
	if "MAX_HEALTH" in enemy:
		pass  # Can't change const, but health is tripled
	# Update health bar if it has one
	if "_health_bar" in enemy and enemy._health_bar != null:
		enemy._health_bar.set_health(enemy.health, enemy.health)

	# Purple particle aura on the grown enemy
	_spawn_aether_aura(enemy)




func _spawn_aether_aura(enemy: Node2D) -> void:
	# Continuous purple particles around the empowered enemy
	for i in range(20):
		if not is_instance_valid(enemy):
			break
		var p := ColorRect.new()
		p.color = Color(0.6, 0.2, 1.0, 0.5)
		p.size = Vector2(4, 4)
		p.position = enemy.global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
		p.z_index = 5
		get_parent().add_child(p)
		var pt := p.create_tween()
		pt.tween_property(p, "position:y", p.position.y - randf_range(15, 40), 0.8)
		pt.parallel().tween_property(p, "modulate:a", 0.0, 0.8)
		pt.tween_callback(p.queue_free)
		await get_tree().create_timer(0.3).timeout




func _update_delegate(delta: float) -> void:
	if not is_instance_valid(p._delegate_node):
		_exit_delegate_mode()
		return

	# Countdown timer
	p._delegate_timer -= delta
	if p._delegate_timer <= 0.0:
		_exit_delegate_mode()
		return

	# Update countdown display
	if is_instance_valid(p._delegate_countdown_label):
		var secs: int = int(ceil(p._delegate_timer))
		p._delegate_countdown_label.text = str(secs)
		# Flash red when low
		if p._delegate_timer <= 3.0:
			p._delegate_countdown_label.modulate = Color(1.0, 0.3, 0.3) if fmod(p._delegate_timer, 0.5) < 0.25 else Color(0.8, 0.5, 1.0)

	var speed: float = PlayerManager.get_player(p.player_index).get("speed", 95) * DELEGATE_SPEED_MULT

	# Gravity
	if not p._delegate_node.is_on_floor():
		p._delegate_node.velocity.y += GRAVITY * delta
		p._delegate_node.velocity.y = minf(p._delegate_node.velocity.y, 600.0)
	else:
		p._delegate_node.velocity.y = 0.0

	# Movement
	var h_input := 0.0
	if p._is_device_action_pressed("move_left"):
		h_input -= 1.0
	if p._is_device_action_pressed("move_right"):
		h_input += 1.0
	p._delegate_node.velocity.x = h_input * speed

	# Jump (1.5x height)
	if p._is_device_action_just_pressed("jump") and p._delegate_node.is_on_floor():
		p._delegate_node.velocity.y = JUMP_VELOCITY * DELEGATE_JUMP_MULT
		AudioManager.play("jump", -8.0, 1.5)

	# Dash (special button)
	if p._is_device_action_just_pressed("special"):
		var dash_dir := 1.0 if h_input >= 0 else -1.0
		p._delegate_node.global_position.x += dash_dir * 80.0
		AudioManager.play("shadow_dash", -6.0, 1.3)

	p._delegate_node.move_and_slide()

	# Pulsing glow
	var glow := p._delegate_node.get_node_or_null("Glow")
	if glow:
		glow.modulate.a = 0.1 + sin(Time.get_ticks_msec() * 0.005) * 0.08

	_update_buddy_target()




func _update_buddy_target() -> void:
	# Point all donut buddies toward the delegate (or back to summoner)
	var target_node: Node2D = p._delegate_node if p._delegate_active and is_instance_valid(p._delegate_node) else self
	for buddy in get_tree().get_nodes_in_group("donut_buddies"):
		if buddy.get("owner_index") == p.player_index:
			# Override the buddy's follow target
			if buddy.has_method("set_follow_target"):
				buddy.set_follow_target(target_node)
			elif "follow_target" in buddy:
				buddy.follow_target = target_node


