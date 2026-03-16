extends BossBase

## Boss 4 - Giant Muffin (Final Boss)
## Attacks: muffin slam (shockwave), crumb burst (360), summon mini-muffins.
## At 25%: berserk mode with faster attacks and spawns previous boss minions.

const SLAM_DAMAGE := 35
const SLAM_RADIUS := 100.0
const CRUMB_SPEED := 220.0
const CRUMB_DAMAGE := 12
const CRUMB_COUNT := 12

var _berserk := false
var _pants_dropped := false
var _pants_cutscene_active := false
var _cherry_timer: float = 0.0
const CHERRY_INTERVAL := 3.0


func _setup_boss() -> void:
	max_health = 1200
	health = max_health
	_attack_cooldown = 2.5
	_attack_timer = 2.0
	move_speed = 50.0

	var texture := load("res://assets/sprites/bosses/giant_muffin.png")
	if texture:
		sprite.texture = texture
		sprite.hframes = 4
		sprite.frame = 0
		sprite.scale = Vector2(3.0, 3.0)

	var shape := RectangleShape2D.new()
	shape.size = Vector2(120, 120)
	collision_shape.shape = shape

	add_to_group("bosses")


func _boss_process(delta: float) -> void:
	if _pants_cutscene_active:
		velocity.x = 0.0
		return

	var target := get_nearest_player()
	if target:
		face_target(target.global_position)
		var dir: float = signf(target.global_position.x - global_position.x)
		velocity.x = dir * move_speed

		var frame_time: int = Time.get_ticks_msec() / 300
		sprite.frame = frame_time % 4
	else:
		velocity.x = 0.0

	# After pants drop: cherries rain from above
	if _pants_dropped:
		_cherry_timer += delta
		if _cherry_timer >= CHERRY_INTERVAL:
			_cherry_timer -= CHERRY_INTERVAL
			_spawn_falling_cherry()


func _choose_attack() -> void:
	var target := get_nearest_player()
	if not target:
		return

	var dist := global_position.distance_to(target.global_position)
	var roll := randf()

	if _berserk:
		# Berserk: cycle through attacks rapidly
		if roll < 0.3:
			_muffin_slam()
		elif roll < 0.6:
			_crumb_burst()
		elif roll < 0.8:
			_summon_mini_muffins()
		else:
			_summon_previous_boss_minions()
		return

	# Normal patterns
	if dist < SLAM_RADIUS + 20.0 and roll < 0.5:
		_muffin_slam()
	elif roll < 0.7:
		_crumb_burst()
	else:
		_summon_mini_muffins()


func _muffin_slam() -> void:
	# Jump high, slam down, create shockwave
	var start_y := position.y
	var tween := create_tween()
	tween.tween_property(self, "position:y", start_y - 80, 0.35).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position:y", start_y, 0.2).set_ease(Tween.EASE_IN)
	tween.tween_callback(_apply_slam_shockwave)


func _apply_slam_shockwave() -> void:
	if is_dead or not is_inside_tree():
		return
	var players := get_tree().get_nodes_in_group("players")
	for p in players:
		if not p is Node2D:
			continue
		if global_position.distance_to(p.global_position) <= SLAM_RADIUS:
			if p.has_method("take_damage"):
				p.take_damage(SLAM_DAMAGE)
			elif p.has_meta("player_index"):
				PlayerManager.damage_player(p.get_meta("player_index"), SLAM_DAMAGE)

	# Shockwave visual: expanding ring
	_create_shockwave_visual()

	# Shockwave projectiles traveling outward along ground
	spawn_projectile(Vector2.LEFT, 150, 15, Color(0.8, 0.6, 0.3))
	spawn_projectile(Vector2.RIGHT, 150, 15, Color(0.8, 0.6, 0.3))


func _create_shockwave_visual() -> void:
	var ring := ColorRect.new()
	ring.size = Vector2(20, 20)
	ring.position = global_position - Vector2(10, 10)
	ring.color = Color(0.9, 0.7, 0.4, 0.7)
	var _scene := get_tree().current_scene
	if _scene:
		_scene.add_child(ring)

	var tween := ring.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "size", Vector2(SLAM_RADIUS * 2, 20), 0.3)
	tween.tween_property(ring, "position:x", global_position.x - SLAM_RADIUS, 0.3)
	tween.tween_property(ring, "modulate:a", 0.0, 0.4)
	tween.chain().tween_callback(ring.queue_free)


func _crumb_burst() -> void:
	# 360 degree burst of crumb projectiles
	var count := CRUMB_COUNT if not _berserk else CRUMB_COUNT * 2
	for i in range(count):
		var angle := (TAU / count) * i
		var dir := Vector2.from_angle(angle)
		spawn_projectile(dir, CRUMB_SPEED, CRUMB_DAMAGE, Color(0.75, 0.55, 0.3))


func _summon_mini_muffins() -> void:
	if is_dead or not is_inside_tree():
		return
	var count := 2 if current_phase < 3 else 4
	for i in range(count):
		var muffin := _create_mini_muffin_enemy()
		var offset_x := (i - count / 2.0) * 50.0
		muffin.global_position = global_position + Vector2(offset_x, -30)
		var sc := get_tree().current_scene
		if sc:
			sc.add_child(muffin)


func _summon_previous_boss_minions() -> void:
	if is_dead or not is_inside_tree():
		return
	var scenes_to_try: Array[String] = [
		"res://scenes/enemies/skeleton_basic.tscn",
	]

	for scene_path in scenes_to_try:
		if ResourceLoader.exists(scene_path):
			var scene: PackedScene = load(scene_path)
			var enemy: Node2D = scene.instantiate()
			enemy.global_position = global_position + Vector2(randf_range(-80, 80), -20)
			var esc := get_tree().current_scene
			if esc:
				esc.add_child(enemy)

	# Also spawn a couple placeholder minions
	for i in range(2):
		var minion := _create_mini_muffin_enemy()
		minion.global_position = global_position + Vector2(randf_range(-100, 100), -20)
		var msc := get_tree().current_scene
		if msc:
			msc.add_child(minion)


func _create_mini_muffin_enemy() -> CharacterBody2D:
	var enemy := CharacterBody2D.new()
	enemy.collision_layer = 8  # Enemy layer - won't collide with boss (also layer 8)
	enemy.collision_mask = 1   # Only collide with world/floor
	enemy.add_to_group("enemies")

	var rect := ColorRect.new()
	rect.size = Vector2(18, 18)
	rect.position = Vector2(-9, -9)
	rect.color = Color(0.8, 0.6, 0.35)
	enemy.add_child(rect)

	# Muffin top
	var top := ColorRect.new()
	top.size = Vector2(22, 10)
	top.position = Vector2(-11, -19)
	top.color = Color(0.9, 0.7, 0.4)
	enemy.add_child(top)

	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(18, 18)
	shape.shape = box
	enemy.add_child(shape)

	return enemy


func _on_phase_change(phase: int) -> void:
	if phase == 2:
		_attack_cooldown = 2.0
		move_speed = 65.0
		if not _pants_dropped:
			_pants_dropped = true
			_pants_cutscene()
	elif phase == 3:
		_berserk = true
		_attack_cooldown = 1.2
		move_speed = 90.0
		_original_modulate = Color(1.2, 0.7, 0.7)
		modulate = _original_modulate


# =============================================================================
# PANTS DROP CUTSCENE
# =============================================================================

func _pants_cutscene() -> void:
	_pants_cutscene_active = true
	velocity = Vector2.ZERO

	# --- PANTS FALL OFF ---
	AudioManager.play("enemy_die", 0.0, 0.5)

	# Create the "pants" (muffin wrapper bottom) falling down
	var pants := ColorRect.new()
	pants.color = Color(0.7, 0.55, 0.3)
	pants.size = Vector2(60, 25)
	pants.position = global_position + Vector2(-30, 10)
	pants.z_index = 3
	get_parent().add_child(pants)

	# Pants wrapper lines
	for line_i in range(4):
		var line := ColorRect.new()
		line.color = Color(0.6, 0.45, 0.25)
		line.size = Vector2(60, 2)
		line.position = Vector2(0, 5 + line_i * 5)
		pants.add_child(line)

	# Pants drop animation
	var pants_tween := pants.create_tween()
	pants_tween.tween_property(pants, "position:y", pants.position.y + 80, 0.6).set_ease(Tween.EASE_IN)
	pants_tween.parallel().tween_property(pants, "rotation", 0.3, 0.6)
	pants_tween.tween_property(pants, "modulate:a", 0.3, 1.0)

	# --- SHOCK FACE ---
	# Muffin goes wide-eyed - flash white then red
	modulate = Color(1.0, 1.0, 1.0, 1.0)
	await get_tree().create_timer(0.2).timeout
	modulate = Color(1.5, 0.8, 0.8)

	# Spawn shock expression (big eyes + open mouth above boss)
	var shock_eyes := Label.new()
	shock_eyes.text = "O  O"
	shock_eyes.add_theme_font_size_override("font_size", 20)
	shock_eyes.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shock_eyes.position = Vector2(-20, -50)
	shock_eyes.z_index = 15
	add_child(shock_eyes)

	var shock_mouth := Label.new()
	shock_mouth.text = "O"
	shock_mouth.add_theme_font_size_override("font_size", 16)
	shock_mouth.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shock_mouth.position = Vector2(-5, -30)
	shock_mouth.z_index = 15
	add_child(shock_mouth)

	await get_tree().create_timer(0.8).timeout

	# --- JUMP UP ---
	AudioManager.play("jump", 2.0, 0.5)
	var start_y: float = global_position.y
	var jump_tween := create_tween()
	jump_tween.tween_property(self, "global_position:y", start_y - 150, 0.4).set_ease(Tween.EASE_OUT)
	await jump_tween.finished

	# --- APEX: PULL PANTS UP ---
	# Brief pause at apex
	velocity.y = 0.0
	await get_tree().create_timer(0.3).timeout

	# Pants fly back up to muffin
	if is_instance_valid(pants):
		var pants_return := pants.create_tween()
		pants_return.tween_property(pants, "position", global_position + Vector2(-30, 10), 0.2)
		pants_return.tween_property(pants, "modulate:a", 0.0, 0.1)
		pants_return.tween_callback(pants.queue_free)

	# Flash with determination
	modulate = Color(1.3, 0.9, 0.6)
	AudioManager.play("shield_charge", 0.0, 0.6)
	await get_tree().create_timer(0.2).timeout

	# Remove shock face
	if is_instance_valid(shock_eyes):
		shock_eyes.queue_free()
	if is_instance_valid(shock_mouth):
		shock_mouth.queue_free()

	# --- GROUND POUND ---
	var slam_tween := create_tween()
	slam_tween.tween_property(self, "global_position:y", start_y, 0.15).set_ease(Tween.EASE_IN)
	await slam_tween.finished

	# MASSIVE IMPACT
	AudioManager.play("explosion", 4.0, 0.4)
	AudioManager.play("boss_roar", 2.0, 0.6)

	# Screen shake - intense
	_shake_screen_intense()

	# Cloud of chips and sprinkles
	_spawn_chip_sprinkle_cloud()

	# Damage all players in arena
	for p in get_tree().get_nodes_in_group("players"):
		if p is Node2D:
			var dist: float = global_position.distance_to(p.global_position)
			if dist < 250.0 and p.has_method("take_damage"):
				p.take_damage(40)

	modulate = _original_modulate
	await get_tree().create_timer(0.5).timeout
	_pants_cutscene_active = false


func _shake_screen_intense() -> void:
	var cam := get_viewport().get_camera_2d()
	if not cam:
		return
	var original_offset: Vector2 = cam.offset
	for i in range(12):
		cam.offset = original_offset + Vector2(randf_range(-8, 8), randf_range(-8, 8))
		await get_tree().create_timer(0.04).timeout
	cam.offset = original_offset


func _spawn_chip_sprinkle_cloud() -> void:
	var chip_colors: Array[Color] = [
		Color(0.55, 0.35, 0.15),  # Chocolate chip
		Color(0.8, 0.65, 0.3),   # Butterscotch
		Color(0.3, 0.2, 0.1),    # Dark chocolate
	]
	var sprinkle_colors: Array[Color] = [
		Color(1.0, 0.3, 0.3),  Color(0.3, 1.0, 0.3),
		Color(0.3, 0.3, 1.0),  Color(1.0, 1.0, 0.3),
		Color(1.0, 0.5, 0.8),  Color(0.5, 1.0, 1.0),
	]

	# Spawn 30 chips and sprinkles
	for i in range(30):
		var is_chip: bool = randf() < 0.4
		var p := ColorRect.new()
		if is_chip:
			p.color = chip_colors[i % chip_colors.size()]
			p.size = Vector2(randf_range(4, 8), randf_range(4, 8))
		else:
			p.color = sprinkle_colors[i % sprinkle_colors.size()]
			p.size = Vector2(randf_range(2, 4), randf_range(5, 8))
			p.rotation = randf_range(-0.5, 0.5)

		p.position = global_position + Vector2(randf_range(-20, 20), randf_range(-20, 5))
		p.z_index = 12
		get_parent().add_child(p)

		var vel: Vector2 = Vector2(randf_range(-150, 150), randf_range(-200, -50))
		_animate_chip(p, vel)


func _animate_chip(chip: ColorRect, vel: Vector2) -> void:
	var gravity: float = 300.0
	var age: float = 0.0
	while age < 3.0 and is_instance_valid(chip):
		var dt: float = get_process_delta_time()
		age += dt
		vel.y += gravity * dt
		chip.position += vel * dt
		chip.rotation += vel.x * 0.001 * dt
		if age > 2.0:
			chip.modulate.a = lerpf(1.0, 0.0, (age - 2.0))
		await get_tree().process_frame
	if is_instance_valid(chip):
		chip.queue_free()


# =============================================================================
# CHERRY RAIN SYSTEM
# =============================================================================

func _spawn_falling_cherry() -> void:
	var cherry := Area2D.new()
	cherry.collision_layer = 0
	cherry.collision_mask = 8  # Detect boss (on layer 8)
	var cherry_x: float = randf_range(50.0, 750.0)  # Across arena width
	cherry.global_position = Vector2(cherry_x, -20.0)

	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 10.0
	col.shape = shape
	cherry.add_child(col)

	# Cherry visual - red circle with green stem
	var body_vis := ColorRect.new()
	body_vis.name = "CherryBody"
	body_vis.color = Color(0.9, 0.1, 0.1)
	body_vis.size = Vector2(14, 14)
	body_vis.position = Vector2(-7, -7)
	cherry.add_child(body_vis)

	var stem := ColorRect.new()
	stem.color = Color(0.2, 0.6, 0.1)
	stem.size = Vector2(2, 8)
	stem.position = Vector2(-1, -14)
	cherry.add_child(stem)

	# Highlight
	var highlight := ColorRect.new()
	highlight.color = Color(1.0, 0.5, 0.5, 0.6)
	highlight.size = Vector2(4, 4)
	highlight.position = Vector2(-5, -5)
	cherry.add_child(highlight)

	get_parent().add_child(cherry)

	# Detect if cherry hits the muffin boss
	cherry.body_entered.connect(func(hit_body: Node2D) -> void:
		if hit_body == self and is_instance_valid(cherry):
			cherry.queue_free()
			_muffin_catches_cherry()
	)

	# Fall with slight wobble
	_animate_falling_cherry(cherry)


func _animate_falling_cherry(cherry: Area2D) -> void:
	var fall_speed: float = 80.0
	var wobble_time: float = 0.0
	while is_instance_valid(cherry):
		var dt: float = get_process_delta_time()
		wobble_time += dt
		cherry.global_position.y += fall_speed * dt
		cherry.global_position.x += sin(wobble_time * 3.0) * 30.0 * dt
		# If it falls below the arena, remove it
		if cherry.global_position.y > 500.0:
			cherry.queue_free()
			return

		await get_tree().process_frame


func _muffin_catches_cherry() -> void:
	AudioManager.play("muffin_collect", 2.0, 0.7)

	# Find nearest player to throw at
	var target := get_nearest_player()
	if not target:
		return

	var throw_dir: Vector2 = (target.global_position - global_position).normalized()

	# Brief wind-up
	await get_tree().create_timer(0.2).timeout
	if is_dead:
		return

	AudioManager.play("crossbow_shoot", 2.0, 0.6)

	# Throw the cherry at the player
	var thrown := ColorRect.new()
	thrown.color = Color(0.9, 0.1, 0.1)
	thrown.size = Vector2(12, 12)
	thrown.position = global_position
	thrown.z_index = 10
	get_parent().add_child(thrown)

	# Fly toward target
	var travel_time := 0.4
	var start_pos: Vector2 = thrown.position
	var target_pos: Vector2 = target.global_position
	var elapsed := 0.0
	while elapsed < travel_time and is_instance_valid(thrown):
		var dt: float = get_process_delta_time()
		elapsed += dt
		var t: float = clampf(elapsed / travel_time, 0.0, 1.0)
		thrown.position = start_pos.lerp(target_pos, t)
		await get_tree().process_frame

	if not is_instance_valid(thrown):
		return
	var explode_pos: Vector2 = thrown.position
	thrown.queue_free()

	# Deal damage at impact
	for p in get_tree().get_nodes_in_group("players"):
		if p is Node2D:
			var dist: float = explode_pos.distance_to(p.global_position)
			if dist < 40.0 and p.has_method("take_damage"):
				p.take_damage(20)

	# EXPLODE into 4 cherry pieces
	AudioManager.play("explosion", -2.0, 1.2)
	_spawn_cherry_fragments(explode_pos)


func _spawn_cherry_fragments(pos: Vector2) -> void:
	var angles: Array[float] = [-2.5, -1.8, -1.2, -0.5]
	for i in range(4):
		var frag := CharacterBody2D.new()
		frag.collision_layer = 0
		frag.collision_mask = 1  # Collide with world (walls/floor)
		frag.global_position = pos

		var vis := ColorRect.new()
		vis.name = "FragVis"
		vis.color = Color(0.85, 0.1, 0.1, 0.9)
		vis.size = Vector2(8, 8)
		vis.position = Vector2(-4, -4)
		frag.add_child(vis)

		var col := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(8, 8)
		col.shape = shape
		frag.add_child(col)

		get_parent().add_child(frag)

		var vel: Vector2 = Vector2(cos(angles[i]), sin(angles[i])) * randf_range(150.0, 250.0)
		_animate_cherry_fragment(frag, vel)


func _animate_cherry_fragment(frag: CharacterBody2D, vel: Vector2) -> void:
	var gravity: float = 400.0
	var landed := false
	var wiggle_time: float = 0.0
	var grow_legs := false
	var running := false
	var run_target: Node2D = null
	var run_speed: float = 0.0

	# Phase 1: Arc through air with physics
	while not landed and is_instance_valid(frag):
		var dt: float = get_process_delta_time()
		vel.y += gravity * dt
		frag.velocity = vel
		frag.move_and_slide()

		if frag.is_on_floor() or frag.is_on_wall():
			landed = true
			break
		await get_tree().process_frame

	if not is_instance_valid(frag):
		return

	# Phase 2: Wiggle and shake on the ground (1.5 seconds)
	AudioManager.play("enemy_hit", -4.0, 1.8)
	var wiggle_duration := 1.5
	while wiggle_time < wiggle_duration and is_instance_valid(frag):
		var dt: float = get_process_delta_time()
		wiggle_time += dt
		# Rapid shake
		var shake_intensity: float = 2.0 + wiggle_time * 2.0
		frag.position.x += sin(wiggle_time * 40.0) * shake_intensity * dt * 20.0
		# Rotate slightly
		var frag_vis := frag.get_node_or_null("FragVis")
		if frag_vis:
			frag_vis.rotation = sin(wiggle_time * 30.0) * 0.3
		await get_tree().process_frame

	if not is_instance_valid(frag):
		return

	# Phase 3: Grow legs!
	AudioManager.play("summon", -4.0, 2.0)
	grow_legs = true

	# Add leg visuals
	var left_leg := ColorRect.new()
	left_leg.name = "LeftLeg"
	left_leg.color = Color(0.7, 0.08, 0.08)
	left_leg.size = Vector2(2, 6)
	left_leg.position = Vector2(-3, 4)
	frag.add_child(left_leg)

	var right_leg := ColorRect.new()
	right_leg.name = "RightLeg"
	right_leg.color = Color(0.7, 0.08, 0.08)
	right_leg.size = Vector2(2, 6)
	right_leg.position = Vector2(1, 4)
	frag.add_child(right_leg)

	# Brief pause to show legs
	await get_tree().create_timer(0.3).timeout
	if not is_instance_valid(frag):
		return

	# Phase 4: RUN at nearest player at 3x speed in a straight line
	running = true
	run_target = get_nearest_player()
	run_speed = 270.0  # ~3x normal enemy speed

	if run_target and is_instance_valid(run_target):
		var run_dir: Vector2 = (run_target.global_position - frag.global_position).normalized()
		var run_time: float = 0.0
		var max_run_time: float = 4.0
		var leg_anim_time: float = 0.0

		while run_time < max_run_time and is_instance_valid(frag):
			var dt: float = get_process_delta_time()
			run_time += dt
			leg_anim_time += dt

			# Straight line movement
			frag.velocity = Vector2(run_dir.x * run_speed, 0)
			# Apply gravity
			if not frag.is_on_floor():
				frag.velocity.y += 400.0
			else:
				frag.velocity.y = 0.0

			frag.move_and_slide()

			# Animate legs running
			var ll := frag.get_node_or_null("LeftLeg")
			var rl := frag.get_node_or_null("RightLeg")
			if ll and rl:
				ll.position.y = 4.0 + sin(leg_anim_time * 25.0) * 3.0
				rl.position.y = 4.0 + sin(leg_anim_time * 25.0 + PI) * 3.0

			# Hit a wall → EXPLODE
			if frag.is_on_wall():
				break

			# Hit a player → damage + EXPLODE
			for p in get_tree().get_nodes_in_group("players"):
				if p is Node2D:
					var dist: float = frag.global_position.distance_to(p.global_position)
					if dist < 16.0 and p.has_method("take_damage"):
						p.take_damage(12)
						run_time = max_run_time  # Trigger explode
						break

			await get_tree().process_frame

	if not is_instance_valid(frag):
		return

	# Phase 5: EXPLODE on wall hit or timeout
	AudioManager.play("explosion", -3.0, 1.5)
	var explode_pos: Vector2 = frag.global_position
	frag.queue_free()

	# Explosion VFX
	for j in range(8):
		var spark := ColorRect.new()
		spark.color = Color(0.9, 0.2, 0.1, 0.8)
		spark.size = Vector2(4, 4)
		spark.position = explode_pos + Vector2(randf_range(-5, 5), randf_range(-5, 5))
		spark.z_index = 10
		get_parent().add_child(spark)
		var st := spark.create_tween()
		var spark_vel: Vector2 = Vector2(randf_range(-80, 80), randf_range(-80, 20))
		st.tween_property(spark, "position", spark.position + spark_vel * 0.3, 0.3)
		st.parallel().tween_property(spark, "modulate:a", 0.0, 0.3)
		st.tween_callback(spark.queue_free)
