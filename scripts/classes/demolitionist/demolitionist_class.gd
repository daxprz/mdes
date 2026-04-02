extends "res://scripts/classes/class_component.gd"

## Demolitionist class

var p: Object = null

func inject_context(c: Variant) -> void:
	ctx = c
	p = c.body if c else null

func tick(delta: float) -> void:
	p._tick_demolitionist(delta)

func perform_attack(_intent: Dictionary) -> void:
	_attack_demolitionist()

func perform_special(_intent: Dictionary) -> void:
	_special_big_bomb()

func perform_charged(charge_ratio: float) -> void:
	_charged_demo_mega_bomb(charge_ratio)



# -- Demolitionist -------------------------------------------------------------

func _attack_demolitionist() -> void:
	AudioManager.play("explosion", -6.0, 1.3)
	var aim: Vector2 = p._get_aim_direction()
	# Spawn a bomb projectile that arcs with gravity
	var bomb := ColorRect.new()
	bomb.color = Color(0.9, 0.6, 0.1)
	bomb.size = Vector2(8, 8)
	bomb.z_index = 5
	get_parent().add_child(bomb)
	bomb.global_position = p.global_position + aim * 12.0

	var bomb_vel: Vector2 = aim * 180.0 + Vector2(0, -200.0)
	var bomb_gravity := 500.0
	var bomb_time := 0.0
	var bomb_max_time := 1.5
	var bomb_bounced := false

	while bomb_time < bomb_max_time and is_instance_valid(bomb) and is_inside_tree():
		var dt: float = get_process_delta_time()
		bomb_time += dt
		bomb_vel.y += bomb_gravity * dt
		bomb.global_position += bomb_vel * dt

		# Bounce once off floor
		if bomb.global_position.y > p.global_position.y + 8.0 and not bomb_bounced:
			bomb_bounced = true
			bomb_vel.y = -120.0
			bomb_vel.x *= 0.5

		# Check enemy hit
		var hit_enemy := false
		for body in get_tree().get_nodes_in_group("enemies"):
			if not body is Node2D:
				continue
			var dist: float = bomb.global_position.distance_to(body.global_position)
			if dist < 20.0:
				hit_enemy = true
				break
		if hit_enemy:
			break
		await get_tree().process_frame

	# Explode
	if is_instance_valid(bomb):
		var explode_pos: Vector2 = bomb.global_position
		bomb.queue_free()
		var base_dmg: int = int(25 * (1.0 + p._demo_power_tier * 0.25) * PlayerManager.get_skill_bonus(p.player_index, "attack"))
		var base_rad: float = 60.0 * (1.0 + p._demo_size_tier * 0.20)
		PlayerManager.add_skill_xp(p.player_index, "attack", 2)
		_demolitionist_explode(explode_pos, base_dmg, base_rad)




# -- Demolitionist Refuel (Circle) ---------------------------------------------

func _handle_demo_refuel() -> void:
	if p.character_class != PlayerManager.CharacterClass.DEMOLITIONIST:
		return
	if not p._is_device_action_pressed("interact"):
		return
	if _rocket_active:
		return  # Can't refuel while flying!
	if _rocket_fuel >= ROCKET_FUEL_MAX:
		return

	# Refuel 1 unit per second while holding Circle
	var dt: float = get_process_delta_time()
	_rocket_fuel = minf(_rocket_fuel + dt * 1.5, ROCKET_FUEL_MAX)

	# VFX: orange fuel particles rising
	if randi() % 5 == 0:
		var fuel_p := ColorRect.new()
		fuel_p.color = Color(1.0, 0.6, 0.1, 0.6)
		fuel_p.size = Vector2(3, 3)
		fuel_p.position = p.global_position + Vector2(randf_range(-5, 5), randf_range(4, 10))
		fuel_p.z_index = 5
		get_parent().add_child(fuel_p)
		var ft := fuel_p.create_tween()
		ft.tween_property(fuel_p, "position:y", fuel_p.position.y - 15, 0.3)
		ft.parallel().tween_property(fuel_p, "modulate:a", 0.0, 0.3)
		ft.tween_callback(fuel_p.queue_free)

		# Show fuel level
		var fuel_pct: int = int(_rocket_fuel / ROCKET_FUEL_MAX * 100)
		var fuel_text := Label.new()
		fuel_text.text = "FUEL %d%%" % fuel_pct
		fuel_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fuel_text.add_theme_font_size_override("font_size", 7)
		fuel_text.modulate = Color(1.0, 0.6, 0.1)
		fuel_text.position = p.global_position + Vector2(-15, -35)
		fuel_text.z_index = 12
		get_parent().add_child(fuel_text)
		var tt := fuel_text.create_tween()
		tt.tween_property(fuel_text, "modulate:a", 0.0, 0.4)
		tt.tween_callback(fuel_text.queue_free)


# -- Balloonist Abilities ------------------------------------------------------

var _balloonist_pop_cooldown: float = 0.0
var _balloonist_floating: bool = false
var _balloonist_float_timer: float = 0.0
const BALLOONIST_FLOAT_DURATION := 6.0
const BALLOONIST_FLOAT_COOLDOWN := 12.0
var _balloonist_float_cooldown: float = 0.0


func _special_big_bomb() -> void:
	if not PlayerManager.use_mana(p.player_index, 40):
		p._special_cooldown = 0.0
		p._spawn_fail_flash()
		return

	AudioManager.play("explosion", -3.0, 0.8)
	# Spawn a bigger bomb projectile
	var bomb := ColorRect.new()
	bomb.color = Color(1.0, 0.4, 0.0)
	bomb.size = Vector2(12, 12)
	bomb.z_index = 5
	get_parent().add_child(bomb)
	bomb.global_position = p.global_position + Vector2(12.0 if p._facing_right else -12.0, -4.0)

	var bomb_vel := Vector2(160.0 if p._facing_right else -160.0, -220.0)
	var bomb_gravity := 450.0
	var bomb_time := 0.0
	var bomb_max_time := 1.5
	var bomb_bounced := false

	while bomb_time < bomb_max_time and is_instance_valid(bomb) and is_inside_tree():
		var dt: float = get_process_delta_time()
		bomb_time += dt
		bomb_vel.y += bomb_gravity * dt
		bomb.global_position += bomb_vel * dt

		if bomb.global_position.y > p.global_position.y + 8.0 and not bomb_bounced:
			bomb_bounced = true
			bomb_vel.y = -100.0
			bomb_vel.x *= 0.4

		var hit_enemy := false
		for body in get_tree().get_nodes_in_group("enemies"):
			if not body is Node2D:
				continue
			var dist: float = bomb.global_position.distance_to(body.global_position)
			if dist < 24.0:
				hit_enemy = true
				break
		if hit_enemy:
			break
		await get_tree().process_frame

	if is_instance_valid(bomb):
		var explode_pos: Vector2 = bomb.global_position
		bomb.queue_free()
		var big_dmg: int = int(50 * (1.0 + p._demo_power_tier * 0.25) * PlayerManager.get_skill_bonus(p.player_index, "attack"))
		var big_rad: float = 90.0 * (1.0 + p._demo_size_tier * 0.20)
		_demolitionist_explode(explode_pos, big_dmg, big_rad)


# -- Healer -------------------------------------------------------------------



func _charged_demo_mega_bomb(charge_ratio: float) -> void:
	var blast_radius: float = lerpf(60.0, 140.0, charge_ratio)
	var damage: int = int(lerpf(30.0, 70.0, charge_ratio))
	var fragment_count: int = int(lerpf(0.0, 5.0, charge_ratio))

	AudioManager.play("explosion", 2.0, 0.7)
	p._spawn_vfx(Color(1.0, 0.4, 0.1, 0.8), Vector2(blast_radius * 2.0, blast_radius * 2.0))
	p._screen_shake(charge_ratio * 6.0 + 2.0, 0.25)

	for body in get_tree().get_nodes_in_group("enemies"):
		if not body is Node2D:
			continue
		var dist: float = p.global_position.distance_to(body.global_position)
		if dist < blast_radius and body.has_method("take_damage"):
			body.take_damage(damage, p.player_index)
			if body.has_method("apply_knockback"):
				var kb: Vector2 = (body.global_position - p.global_position).normalized()
				body.apply_knockback(kb * 300.0)

	# Spawn fragment mini-bombs
	for i in range(fragment_count):
		var angle: float = randf() * TAU
		var frag_offset := Vector2(cos(angle), sin(angle)) * (blast_radius * 0.5)
		var frag_pos: Vector2 = p.global_position + frag_offset
		_spawn_fragment_bomb(frag_pos, int(damage * 0.3))


