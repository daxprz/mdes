extends "res://scripts/classes/class_component.gd"

## Healer class

var p: Object = null

func inject_context(c: Variant) -> void:
	ctx = c
	p = c.body if c else null

func tick(delta: float) -> void:
	_handle_healer_wind_gust()


func perform_attack(_intent: Dictionary) -> void:
	_attack_healer()

func perform_special(_intent: Dictionary) -> void:
	_special_healing_burst()

func perform_charged(charge_ratio: float) -> void:
	_charged_healer_wave(charge_ratio)



# -- Healer -------------------------------------------------------------------

func _attack_healer() -> void:
	# Throw a healing potion in aimed direction
	AudioManager.play("summon", -3.0, 1.2)
	var throw_dir: Vector2 = p._get_aim_direction()

	# Default target: aimed direction. Override if injured ally nearby in that direction.
	var target_pos: Vector2 = p.global_position + throw_dir * 80.0
	for p in get_tree().get_nodes_in_group("players"):
		if p == self or not (p is CharacterBody2D):
			continue
		if p.get("_is_dead"):
			continue
		var p_idx: int = p.get("player_index")
		var p_data: Dictionary = PlayerManager.get_player(p_idx)
		if p_data.is_empty():
			continue
		if p_data["health"] < p_data["max_health"]:
			var dist: float = p.global_position.distance_to(p.global_position)
			if dist < 150.0:
				target_pos = p.global_position
				break

	# Spawn the potion projectile
	PlayerManager.add_skill_xp(p.player_index, "attack", 2)
	_spawn_healing_potion(target_pos)


func _handle_healer_wind_gust() -> void:
	if p.character_class != PlayerManager.CharacterClass.HEALER:
		return
	if p._healer_gust_cooldown > 0.0:
		p._healer_gust_cooldown -= get_process_delta_time()
	if not p._is_device_action_just_pressed("interact"):
		return
	if p._healer_gust_cooldown > 0.0:
		p._spawn_fail_flash()
		return

	p._healer_gust_cooldown = HEALER_GUST_COOLDOWN
	AudioManager.play("wind_gust")
	AudioManager.play("jump", 2.0, 0.5)

	# Expanding wind ring VFX
	for ring_i in range(3):
		var ring := ColorRect.new()
		ring.color = Color(0.8, 0.9, 1.0, 0.4 - ring_i * 0.1)
		var ring_size: float = 16.0 + ring_i * 8.0
		ring.size = Vector2(ring_size, ring_size)
		ring.position = p.global_position - Vector2(ring_size / 2.0, ring_size / 2.0)
		ring.pivot_offset = Vector2(ring_size / 2.0, ring_size / 2.0)
		ring.z_index = 8
		get_parent().add_child(ring)
		var scale_target: float = HEALER_GUST_RADIUS * 2.0 / ring_size
		var rt := ring.create_tween()
		rt.set_parallel(true)
		rt.tween_property(ring, "scale", Vector2(scale_target, scale_target), 0.3 + ring_i * 0.1)
		rt.tween_property(ring, "modulate:a", 0.0, 0.35 + ring_i * 0.1)
		rt.chain().tween_callback(ring.queue_free)

	# Wind line particles shooting outward
	for i in range(16):
		var angle: float = float(i) * TAU / 16.0
		var dir: Vector2 = Vector2(cos(angle), sin(angle))
		var wind_p := ColorRect.new()
		wind_p.color = Color(0.85, 0.9, 1.0, 0.6)
		wind_p.size = Vector2(6, 2)
		wind_p.rotation = angle
		wind_p.position = p.global_position + dir * 8.0
		wind_p.z_index = 9
		get_parent().add_child(wind_p)
		var wt := wind_p.create_tween()
		wt.tween_property(wind_p, "position", wind_p.position + dir * HEALER_GUST_RADIUS, 0.25)
		wt.parallel().tween_property(wind_p, "modulate:a", 0.0, 0.3)
		wt.tween_callback(wind_p.queue_free)

	# Push ALL enemies away
	for body in get_tree().get_nodes_in_group("enemies"):
		if not body is Node2D:
			continue
		var dist: float = p.global_position.distance_to(body.global_position)
		if dist < HEALER_GUST_RADIUS and dist > 1.0:
			var push_dir: Vector2 = (body.global_position - p.global_position).normalized()
			var push_strength: float = HEALER_GUST_FORCE * (1.0 - dist / HEALER_GUST_RADIUS)
			if body.has_method("apply_knockback"):
				body.apply_knockback(push_dir * push_strength)
			elif "velocity" in body:
				body.velocity += push_dir * push_strength
			# Small damage from the gust
			if body.has_method("take_damage"):
				body.take_damage(5, p.player_index)

	# Push other players away too (friendly push, no damage)
	for body in get_tree().get_nodes_in_group("players"):
		if body == self or not body is Node2D:
			continue
		var dist: float = p.global_position.distance_to(body.global_position)
		if dist < HEALER_GUST_RADIUS and dist > 1.0:
			var push_dir: Vector2 = (body.global_position - p.global_position).normalized()
			var push_strength: float = HEALER_GUST_FORCE * 0.6 * (1.0 - dist / HEALER_GUST_RADIUS)
			if "velocity" in body:
				body.velocity += push_dir * push_strength

	p._screen_shake(3.0, 0.15)


func _special_healing_burst() -> void:
	if not PlayerManager.use_mana(p.player_index, 50):
		p._special_cooldown = 0.0
		p._spawn_fail_flash()
		return

	AudioManager.play("player_revive")
	# Green pulse VFX expanding outward
	var pulse := ColorRect.new()
	pulse.color = Color(0.3, 0.9, 0.4, 0.5)
	pulse.size = Vector2(20, 20)
	pulse.position = p.global_position - Vector2(10, 10)
	pulse.pivot_offset = Vector2(10, 10)
	get_parent().add_child(pulse)
	var pulse_tween := pulse.create_tween()
	pulse_tween.set_parallel(true)
	pulse_tween.tween_property(pulse, "scale", Vector2(8.0, 8.0), 0.4)
	pulse_tween.tween_property(pulse, "modulate:a", 0.0, 0.4)
	pulse_tween.chain().tween_callback(pulse.queue_free)

	# Heal all allies within 80px for 30 HP
	for p in get_tree().get_nodes_in_group("players"):
		if not (p is CharacterBody2D):
			continue
		if p.get("_is_dead"):
			continue
		var dist: float = p.global_position.distance_to(p.global_position)
		if dist < 80.0:
			var p_idx: int = p.get("player_index")
			PlayerManager.heal_player(p_idx, 30)


# -- Guitarist -----------------------------------------------------------------

var _guitarist_amp_up_active: bool = false
var _guitarist_amp_up_timer: float = 0.0
var _guitarist_amp_up_cooldown: float = 0.0
const GUITARIST_AMP_DURATION := 15.0
const GUITARIST_AMP_COOLDOWN := 30.0
const GUITARIST_AMP_RADIUS := 80.0




func _charged_healer_wave(charge_ratio: float) -> void:
	# Final burst heal on release - proportional to charge time
	_healer_channel_burst()




# -- Charge Hooks (called by ChargeComponent) ----------------------------------

func on_charge_start() -> void:
	p.velocity.x = 0.0
	p._healer_channel_start_vfx()

func on_charge_tick(delta: float, charge_ratio: float) -> void:
	p.velocity.x = 0.0
	var glow_intensity: float = 0.5 + sin(p._charge_time * 4.0) * 0.2
	p.modulate = Color(0.6, 1.0, 0.6, 1.0).lerp(Color(0.3, 1.0, 0.3, 1.0), glow_intensity)
	p._healer_channel_heal_timer += delta
	if p._healer_channel_heal_timer >= 0.2:
		p._healer_channel_heal_timer -= 0.2
		p._healer_channel_heal_tick()
	p._healer_channel_pulse_timer += delta
	if p._healer_channel_pulse_timer >= 0.8:
		p._healer_channel_pulse_timer -= 0.8
		p._spawn_expanding_ring(p.global_position, p.HEALER_CHANNEL_RADIUS, Color(0.3, 1.0, 0.4, 0.35), 0.7)
	p._healer_channel_update_vfx(charge_ratio)

func on_charge_release() -> void:
	p._healer_channel_stop_vfx()
