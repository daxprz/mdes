extends "res://scripts/classes/class_component.gd"

## Rogue class

var p: Object = null

func inject_context(c: Variant) -> void:
	ctx = c
	p = c.body if c else null

func tick(delta: float) -> void:
	p._tick_rogue(delta)

func perform_attack(_intent: Dictionary) -> void:
	_attack_rogue()

func perform_special(_intent: Dictionary) -> void:
	_special_shadow_dash()

func perform_charged(charge_ratio: float) -> void:
	_charged_rogue_backstab(charge_ratio)



func _attack_rogue() -> void:
	# Throw 3 knives in a fan spread, 0.5s cooldown
	AudioManager.play("dagger_stab")
	p._attack_cooldown = 0.5
	var base_dir: Vector2 = p._get_aim_direction()
	var angles := [-0.2, 0.0, 0.2]
	var base_dmg: int = int(12 * PlayerManager.get_skill_bonus(p.player_index, "attack"))

	# STEALTH: close-range backstab instead of throwing knives
	if _rogue_stealth:
		var backstab_dmg: int = int(base_dmg * ROGUE_STEALTH_DAMAGE_MULT)
		_exit_stealth()

		# Small square melee hit in front of rogue
		p.attack_area.position = base_dir * 14.0
		p.attack_area.monitoring = true
		await get_tree().physics_frame
		if not is_inside_tree():
			return
		var hit_something := false
		for body in p.attack_area.get_overlapping_bodies():
			if body.has_method("take_damage"):
				body.take_damage(backstab_dmg, p.player_index)
				p._spawn_blood_particles(body.global_position)
				PlayerManager.add_skill_xp(p.player_index, "attack", 5)
				hit_something = true
		# Only show BACK STAB text + sound if we actually hit an enemy
		if hit_something:
			AudioManager.play("backstab_hit")
			_stealth_backstab_vfx(p.global_position + base_dir * 16.0)
		await get_tree().create_timer(0.1).timeout
		if is_inside_tree():
			p.attack_area.monitoring = false
		return

	# Normal: throw 3 knives in a fan spread
	var scaled_dmg: int = base_dmg
	PlayerManager.add_skill_xp(p.player_index, "attack", 2)
	for angle in angles:
		var dir: Vector2 = base_dir.rotated(angle)
		var knife_scene := load("res://scenes/characters/projectile.tscn") as PackedScene
		if not knife_scene:
			continue
		var knife := knife_scene.instantiate()
		knife.damage = scaled_dmg
		knife.speed = 400.0
		knife.direction = dir
		knife.projectile_type = "knife"
		knife.owner_index = p.player_index
		knife.global_position = p.global_position + base_dir * 12.0
		get_parent().add_child(knife)


func _handle_rogue_stealth_toggle() -> void:
	if p.character_class != PlayerManager.CharacterClass.ROGUE:
		return
	if not p._is_device_action_just_pressed("interact"):
		return
	if _rogue_stealth:
		return
	if p._rogue_stealth_cooldown > 0.0:
		p._spawn_fail_flash()
		return

	_rogue_stealth = true
	p._rogue_stealth_timer = ROGUE_STEALTH_DURATION
	AudioManager.play("stealth_activate")
	# Go nearly invisible + enemies can't see us
	remove_from_group("players")
	p.modulate = Color(1.0, 1.0, 1.0, 0.15)




func _handle_rogue_stealth(delta: float) -> void:
	if p._rogue_stealth_cooldown > 0.0:
		p._rogue_stealth_cooldown -= delta
	if not _rogue_stealth:
		return

	p._rogue_stealth_timer -= delta

	# Subtle shimmer while stealthed
	p.modulate.a = 0.1 + sin(p._rogue_stealth_timer * 8.0) * 0.05

	# Warning: flicker more when almost out
	if p._rogue_stealth_timer <= 1.5:
		p.modulate.a = 0.15 + sin(p._rogue_stealth_timer * 20.0) * 0.1

	# Time's up
	if p._rogue_stealth_timer <= 0.0:
		_exit_stealth()




func _exit_stealth() -> void:
	_rogue_stealth = false
	p._rogue_stealth_cooldown = ROGUE_STEALTH_COOLDOWN
	add_to_group("players")  # Enemies can see us again
	p.modulate = Color.WHITE
	AudioManager.play("stealth_activate", -4.0, 1.3)




func _stealth_backstab_vfx(hit_pos: Vector2) -> void:
	# "BACK STAB!" text in orange, floats up, flickers, disappears
	var label := Label.new()
	label.text = "BACK STAB!"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.modulate = Color(1.0, 0.6, 0.1)
	label.position = hit_pos + Vector2(-30, -30)
	label.z_index = 15
	get_parent().add_child(label)

	# Float up + flicker + fade
	var tween := label.create_tween()
	tween.tween_property(label, "position:y", label.position.y - 35, 1.0)
	# Flicker by toggling alpha
	for i in range(6):
		tween.parallel().tween_property(label, "modulate:a", 0.2, 0.08).set_delay(0.1 * i)
		tween.parallel().tween_property(label, "modulate:a", 1.0, 0.08).set_delay(0.1 * i + 0.08)
	tween.tween_property(label, "modulate:a", 0.0, 0.2)
	tween.tween_callback(label.queue_free)


func _special_shadow_dash() -> void:
	# Teleport short distance with ghost trail + invincibility
	# Use physics raycast to stop at walls
	var dash_distance := 120.0
	var direction := Vector2(1.0 if p._facing_right else -1.0, 0.0)

	# Raycast to find wall
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		p.global_position,
		p.global_position + direction * dash_distance,
		1  # mask layer 1 = world/walls
	)
	query.exclude = [get_rid()]
	var result: Dictionary = space.intersect_ray(query)

	var target_pos: Vector2
	if result:
		# Stop short of the wall
		target_pos = result["position"] - direction * 12.0
	else:
		target_pos = p.global_position + direction * dash_distance

	AudioManager.play("shadow_dash")
	p._spawn_vfx(Color(0.8, 0.2, 0.2, 0.5), Vector2(14, 28))
	var dash_start: Vector2 = p.global_position
	p.global_position = target_pos
	# Arrive flash
	p._spawn_vfx(Color(0.8, 0.2, 0.2, 0.5), Vector2(14, 28))
	p.modulate = Color(1.0, 1.0, 1.0, 0.4)
	collision_layer = 0
	_shadow_dash_active = true

	# Dash wave - perpendicular to dash direction, rogue deals 10 damage
	_spawn_dash_wave(dash_start, direction, 10)

	await get_tree().create_timer(0.3).timeout
	if is_inside_tree():
		collision_layer = 2
		_shadow_dash_active = false
		p.modulate = Color.WHITE


# -- Visual Effects ------------------------------------------------------------



func _charged_rogue_backstab(charge_ratio: float) -> void:
	# Charged knife fan: more charge = more knives, wider spread, bigger hitbox, more damage
	var knife_count: int = int(lerpf(3.0, 9.0, charge_ratio))
	var spread_angle: float = lerpf(0.3, 1.2, charge_ratio)  # radians total spread
	var damage_per_knife: int = int(lerpf(10.0, 25.0, charge_ratio))
	var knife_speed: float = lerpf(350.0, 500.0, charge_ratio)
	var knife_size: float = lerpf(1.0, 2.0, charge_ratio)  # scale multiplier

	AudioManager.play("dagger_stab", 2.0, lerpf(1.0, 0.6, charge_ratio))
	PlayerManager.add_skill_xp(p.player_index, "charge", 5)

	var base_dir: Vector2 = Vector2(1.0 if p._facing_right else -1.0, 0.0)

	# Spawn VFX sweep arc
	var arc_width: float = lerpf(30.0, 80.0, charge_ratio)
	var arc_height: float = lerpf(20.0, 50.0, charge_ratio)
	var arc_vfx := ColorRect.new()
	arc_vfx.color = Color(0.8, 0.15, 0.15, 0.5)
	arc_vfx.size = Vector2(arc_width, arc_height)
	arc_vfx.position = p.global_position + Vector2(
		-arc_width / 2.0 if not p._facing_right else 0,
		-arc_height / 2.0
	)
	arc_vfx.z_index = 7
	get_parent().add_child(arc_vfx)
	var arc_tween := arc_vfx.create_tween()
	arc_tween.set_parallel(true)
	arc_tween.tween_property(arc_vfx, "modulate:a", 0.0, 0.25)
	arc_tween.tween_property(arc_vfx, "scale:x", 1.5, 0.25)
	arc_tween.chain().tween_callback(arc_vfx.queue_free)

	# Spawn knives in a fan
	for i in range(knife_count):
		var t: float = 0.0
		if knife_count > 1:
			t = float(i) / float(knife_count - 1)
		var angle: float = lerpf(-spread_angle / 2.0, spread_angle / 2.0, t)
		var dir: Vector2 = base_dir.rotated(angle)

		var knife_scene := load("res://scenes/characters/projectile.tscn") as PackedScene
		if not knife_scene:
			continue
		var knife := knife_scene.instantiate()
		knife.damage = damage_per_knife
		knife.speed = knife_speed
		knife.direction = dir
		knife.projectile_type = "knife"
		knife.owner_index = p.player_index
		knife.global_position = p.global_position + base_dir * 12.0
		if knife_size > 1.1:
			knife.scale = Vector2(knife_size, knife_size)
		get_parent().add_child(knife)

	# Red/crimson particle burst
	for p_i in range(int(lerpf(4.0, 12.0, charge_ratio))):
		var particle := ColorRect.new()
		particle.color = Color(0.8, 0.1, 0.1, 0.7)
		particle.size = Vector2(3 + charge_ratio * 3, 3 + charge_ratio * 3)
		particle.position = p.global_position + Vector2(randf_range(-10, 10), randf_range(-10, 10))
		particle.z_index = 8
		get_parent().add_child(particle)
		var p_dir: Vector2 = base_dir.rotated(randf_range(-spread_angle, spread_angle))
		var pt := particle.create_tween()
		pt.tween_property(particle, "position", particle.position + p_dir * randf_range(20, 50), 0.3)
		pt.parallel().tween_property(particle, "modulate:a", 0.0, 0.3)
		pt.tween_callback(particle.queue_free)


