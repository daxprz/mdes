extends "res://scripts/classes/class_component.gd"

## Werewolf class

var p: Object = null

func inject_context(c: Variant) -> void:
	ctx = c
	p = c.body if c else null

func tick(delta: float) -> void:
	_handle_werewolf_frenzy(delta)


func perform_attack(_intent: Dictionary) -> void:
	_attack_werewolf()

func perform_special(_intent: Dictionary) -> void:
	_special_werewolf_roar_push()

func perform_charged(charge_ratio: float) -> void:
	_charged_werewolf_pounce(charge_ratio)



func _attack_werewolf() -> void:
	# Triple Claw Slash - 3 diagonal white slash lines
	var base_cooldown: float = 0.5
	if p._werewolf_frenzy_active:
		base_cooldown *= 0.5
	p._attack_cooldown = base_cooldown
	PlayerManager.add_skill_xp(p.player_index, "attack", 2)

	var aim: Vector2 = p._get_aim_direction()
	var attack_bonus: float = PlayerManager.get_skill_bonus(p.player_index, "attack")
	if p._werewolf_frenzy_active:
		attack_bonus *= 1.3
	var slash_damage: int = int(15 * attack_bonus)

	for slash_i in range(3):
		if not is_inside_tree():
			return
		if slash_i > 0:
			await get_tree().create_timer(0.05).timeout
			if not is_inside_tree():
				return
		AudioManager.play("sword_slash", 2.0, 1.3)
		_spawn_werewolf_slash(aim, slash_i, slash_damage)




func _handle_werewolf_frenzy(delta: float) -> void:
	if p.character_class != PlayerManager.CharacterClass.WEREWOLF:
		return
	if p._werewolf_frenzy_cooldown > 0.0:
		p._werewolf_frenzy_cooldown -= delta

	# Toggle frenzy on Circle press
	if p._is_device_action_just_pressed("interact"):
		if p._werewolf_frenzy_active:
			return  # Can't cancel early
		if p._werewolf_frenzy_cooldown > 0.0:
			p._spawn_fail_flash()
			return
		# FRENZY!
		p._werewolf_frenzy_active = true
		p._werewolf_frenzy_timer = WEREWOLF_FRENZY_DURATION
		AudioManager.play("enrage_roar", 2.0, 1.3)
		p.modulate = Color(0.7, 0.3, 0.2)
		# Burst VFX
		p._spawn_vfx(Color(0.8, 0.15, 0.1, 0.7), Vector2(40, 40))
		# "FRENZY!" text
		var frenzy_text := Label.new()
		frenzy_text.text = "FRENZY!"
		frenzy_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		frenzy_text.add_theme_font_size_override("font_size", 14)
		frenzy_text.modulate = Color(1.0, 0.2, 0.1)
		frenzy_text.position = p.global_position + Vector2(-25, -40)
		frenzy_text.z_index = 15
		get_parent().add_child(frenzy_text)
		var tt := frenzy_text.create_tween()
		tt.tween_property(frenzy_text, "position:y", frenzy_text.position.y - 20, 0.8)
		tt.parallel().tween_property(frenzy_text, "modulate:a", 0.0, 0.8)
		tt.tween_callback(frenzy_text.queue_free)

	# While frenzy active
	if p._werewolf_frenzy_active:
		p._werewolf_frenzy_timer -= delta

		# Reddish-brown pulsing glow (eyes glow red, fur bristles)
		var pulse: float = 0.15 + sin(p._werewolf_frenzy_timer * 6.0) * 0.1
		p.modulate = Color(0.7 + pulse, 0.3, 0.2)

		# Red particles while frenzied
		if randi() % 4 == 0:
			var rp := ColorRect.new()
			rp.color = Color(1.0, 0.1, 0.0, 0.6)
			rp.size = Vector2(3, 3)
			rp.position = p.global_position + Vector2(randf_range(-10, 10), randf_range(-8, 8))
			rp.z_index = 5
			get_parent().add_child(rp)
			var rt := rp.create_tween()
			rt.tween_property(rp, "position:y", rp.position.y - randf_range(10, 20), 0.3)
			rt.parallel().tween_property(rp, "modulate:a", 0.0, 0.3)
			rt.tween_callback(rp.queue_free)

		# Warning flicker when almost done
		if p._werewolf_frenzy_timer <= 2.0:
			if fmod(p._werewolf_frenzy_timer, 0.2) < 0.1:
				p.modulate = Color.WHITE

		# Frenzy ends
		if p._werewolf_frenzy_timer <= 0.0:
			p._werewolf_frenzy_active = false
			p._werewolf_frenzy_cooldown = WEREWOLF_FRENZY_COOLDOWN
			p.modulate = Color.WHITE
			AudioManager.play("player_hurt", -4.0, 0.8)


# ==============================================================================
# EXECUTIONER — Ball-and-chain + Shackle + Axe
# ==============================================================================


# Executioner constants moved to executioner_class.gd

# -- State Variables -----------------------------------------------------------

enum ExecThrowMode { BALL_FIRST, SHACKLE_FIRST }
enum ExecEndState { HELD, WINDUP, THROWN, STUCK_WALL, STUCK_PLATFORM, STUCK_CEILING, ATTACHED_ENEMY, RETRACTING }

# Chain mode: what happens with the chain on each throw
# Circle button cycles through these
enum ExecChainMode {
	RELEASE_RELEASE,  # 1st: throw & release, 2nd: N/A (already free)
	HOLD_RELEASE,     # 1st: throw & hold, 2nd: throw & release (entity YEET)
	HOLD_HOLD,        # 1st: throw & hold, 2nd: throw & hold (3-body)
}

const EXEC_CHAIN_MODE_NAMES := ["Release", "Hold+Release", "Hold+Hold"]
const EXEC_CHAIN_MODE_COLORS: Array[Color] = [
	Color(0.9, 0.4, 0.2),   # Release: orange-red
	Color(0.8, 0.7, 0.2),   # Hold+Release: gold
	Color(0.3, 0.7, 0.9),   # Hold+Hold: blue
]

var _exec_throw_mode: ExecThrowMode = ExecThrowMode.BALL_FIRST
var _exec_chain_mode: ExecChainMode = ExecChainMode.HOLD_RELEASE  # Default
var _exec_chain_mode_changed_timer: float = 0.0  # Flash timer when mode changes
var _exec_throw_step: int = 0

var _exec_ball_state: ExecEndState = ExecEndState.HELD
var _exec_ball_pos: Vector2 = Vector2.ZERO
var _exec_ball_marker: Node2D = null  # SpikeBallEntity — persistent, owns ball config stack
var _exec_ball_vel: Vector2 = Vector2.ZERO
var _exec_ball_anchor_body: Node2D = null
var _exec_ball_anchor_offset: Vector2 = Vector2.ZERO
var _exec_ball_spin_angle: float = 0.0
var _exec_ball_angular_vel: float = 0.0
var _exec_ball_hold_time: float = 0.0
var _exec_ball_rotation: float = 0.0

# Shackle entity — proper scene node with own config stack and physics.
# Created on executioner init, persists while player exists.
var _shackle: Node2D = null  # ShackleEntity instance
# Legacy accessors for gradual migration (read/write through to _shackle)
var _exec_shackle_state: int:
	get: return _shackle.state if _shackle else 0
	set(v): if _shackle: _shackle.state = v
var _exec_shackle_pos: Vector2:
	get: return _shackle.global_position if _shackle else Vector2.ZERO
	set(v): if _shackle: _shackle.global_position = v
var _exec_shackle_vel: Vector2:
	get: return _shackle.vel if _shackle else Vector2.ZERO
	set(v): if _shackle: _shackle.vel = v
var _exec_shackle_anchor_body: Node2D:
	get: return _shackle.anchor_body if _shackle else null
	set(v): if _shackle: _shackle.anchor_body = v
var _exec_shackle_anchor_offset: Vector2:
	get: return _shackle.anchor_offset if _shackle else Vector2.ZERO
	set(v): if _shackle: _shackle.anchor_offset = v
var _exec_shackle_spin_angle: float:
	get: return _shackle.spin_angle if _shackle else 0.0
	set(v): if _shackle: _shackle.spin_angle = v
var _exec_shackle_angular_vel: float:
	get: return _shackle.angular_vel if _shackle else 0.0
	set(v): if _shackle: _shackle.angular_vel = v
var _exec_shackle_hold_time: float:
	get: return _shackle.hold_time if _shackle else 0.0
	set(v): if _shackle: _shackle.hold_time = v

# Chain nodes (chain.gd instances — splay-chain physics, breakable)
var _exec_chain_node: Node2D = null       # Ball side chain
var _exec_shackle_chain_node: Node2D:
	get: return _shackle.chain_node if _shackle else null
	set(v): if _shackle: _shackle.chain_node = v

# Chain split: how much of total goes to ball (rest goes to shackle)
var _exec_chain_split: float = 0.5

# Trajectory preview — two arcs forming a probability cone
var _exec_preview_arc: PackedVector2Array = PackedVector2Array()       # Optimistic (no damping)
var _exec_preview_arc_inner: PackedVector2Array = PackedVector2Array()  # Pessimistic (damped)
var _exec_shackle_preview_arc: PackedVector2Array:
	get: return _shackle.preview_arc if _shackle else PackedVector2Array()
	set(v): if _shackle: _shackle.preview_arc = v

var _exec_swing_active: bool = false
var _exec_swing_time: float = 0.0
var _exec_swing_angle: float = 0.0
var _exec_swing_angular_vel: float = 0.0

var _exec_cleave_charging: bool = false
var _exec_cleave_charge_time: float = 0.0
var _exec_cleave_flash_timer: float = 0.0

var _exec_r1_was_pressed: bool = false
var _exec_chain_clank_timer: float = 0.0  # Timer for chain clanking during throw
var _exec_chain_taut: bool = false        # True once ball chain goes slack→taut (YEET fires once)
var _exec_shackle_chain_taut: bool:
	get: return _shackle.chain_taut if _shackle else false
	set(v): if _shackle: _shackle.chain_taut = v
var _exec_yeet_immunity: float = 0.0     # Seconds to skip OOB check after YEET

# Legacy accessors — config stack now lives on the ShackleEntity
var _exec_shackle_config_stack: Array:
	get: return _shackle._config_stack if _shackle else []
	set(v): if _shackle: _shackle._config_stack = v
var _exec_shackle_base_config: Variant:
	get: return _shackle._base_config if _shackle else null
	set(v): if _shackle: _shackle._base_config = v
var _exec_chain_len_changing: bool = false  # True while actively adjusting split
var _exec_l2_tap_timer: float = 0.0      # Double-tap detection for L2
var _exec_r2_tap_timer: float = 0.0      # Double-tap detection for R2
var _exec_l2_was_pressed: bool = false    # Edge detection for L2
var _exec_r2_was_pressed: bool = false    # Edge detection for R2
var _exec_chain_radius_fade: float = 0.0 # Fade timer for radius indicator
var _exec_chain_reel_timer: float = 0.0  # Timer for reel in/out clink sound

# Tuning popup — live sliders for ball/chain feel
var _exec_tuning_visible: bool = false
var _exec_tuning_provider: Variant = null  # DictProvider pushed onto config stack
var _exec_tuning_data: Dictionary = {}     # The data dict inside the provider
var _exec_tuning_dragging: String = ""     # Which slider is being dragged

const EXEC_TUNING_KEYS: Array[Array] = [
	# [key, label, default, min, max]
	["exec_ball_mass", "Ball Mass", 140.0, 10.0, 1000.0],
	["exec_chain_elasticity", "Elasticity", 0.25, 0.0, 1.0],
	["exec_ball_throw_speed", "Throw Min", 1200.0, 100.0, 3000.0],
	["exec_ball_max_throw_speed", "Throw Max", 6000.0, 400.0, 10000.0],
	["exec_ball_gravity", "Ball Gravity", 900.0, 100.0, 2000.0],
	["exec_chain_total_len", "Chain Total", 600.0, 200.0, 1500.0],
	["exec_chain_adjust_speed", "Split Speed", 0.5, 0.1, 2.0],
	["exec_ball_stun_duration", "Stun Secs", 3.0, 0.5, 10.0],
	["exec_ball_damage", "Ball Damage", 35.0, 5.0, 200.0],
]


# -- Chain Constraint on Player (same as monster chain pull) -------------------



func _special_werewolf_roar_push() -> void:
	# Roar Push - no mana cost, narrow 30-degree arc blast
	AudioManager.play("boss_roar", 3.0, 1.2)
	AudioManager.play("wind_gust", 2.0, 0.7)
	p._special_cooldown = 2.0
	PlayerManager.add_skill_xp(p.player_index, "special", 7)

	var aim: Vector2 = p._get_aim_direction()
	var aim_angle: float = aim.angle()
	var half_arc: float = deg_to_rad(15.0)  # 30-degree arc total
	var push_range: float = 250.0
	var push_force: float = 500.0
	var roar_damage: int = 10

	# Visual: narrow expanding cone
	var cone := ColorRect.new()
	cone.color = Color(0.9, 0.9, 0.9, 0.5)
	cone.size = Vector2(push_range, 30)
	cone.position = p.global_position
	cone.rotation = aim_angle - 0.06
	cone.pivot_offset = Vector2(0, 15)
	cone.z_index = 7
	get_parent().add_child(cone)

	var ct := cone.create_tween()
	ct.set_parallel(true)
	ct.tween_property(cone, "scale", Vector2(1.2, 2.0), 0.2)
	ct.tween_property(cone, "modulate:a", 0.0, 0.3)
	ct.chain().tween_callback(cone.queue_free)

	# Hit enemies in arc
	for body in get_tree().get_nodes_in_group("enemies"):
		if not body is Node2D:
			continue
		var to_enemy: Vector2 = body.global_position - p.global_position
		var dist: float = to_enemy.length()
		if dist > push_range:
			continue
		var angle_to: float = to_enemy.angle()
		var angle_diff: float = abs(wrapf(angle_to - aim_angle, -PI, PI))
		if angle_diff > half_arc:
			continue

		if body.has_method("take_damage"):
			body.take_damage(roar_damage, p.player_index)
		if body.has_method("apply_knockback"):
			var kb_dir: Vector2 = to_enemy.normalized()
			var weight: float = 1.0
			if body.has_method("get_weight"):
				weight = body.get_weight()
			body.apply_knockback(kb_dir * push_force / maxf(weight, 0.5))




func _charged_werewolf_pounce(charge_ratio: float) -> void:
	# Pounce - diagonal arc attack
	AudioManager.play("jump", 2.0, 0.5)
	PlayerManager.add_skill_xp(p.player_index, "charge", 5)

	var aim: Vector2 = p._get_aim_direction()
	var h_dir: float = signf(aim.x) if abs(aim.x) > 0.1 else (1.0 if p._facing_right else -1.0)

	# Launch in parabolic arc
	var launch_vy: float = lerpf(-400.0, -700.0, charge_ratio)
	var launch_vx: float = lerpf(300.0, 600.0, charge_ratio) * h_dir
	p.velocity.y = launch_vy
	p.velocity.x = launch_vx

	# Set pounce state for landing check
	_werewolf_pouncing = true
	_werewolf_pounce_damage = int(lerpf(30.0, 60.0, charge_ratio))
	_werewolf_pounce_radius = lerpf(40.0, 80.0, charge_ratio)

	# Visual: brief flash
	p.modulate = Color(0.8, 0.6, 0.3)
	p._spawn_vfx(Color(0.6, 0.4, 0.2, 0.5), Vector2(20, 20))




func _check_werewolf_pounce_landing() -> void:
	if not _werewolf_pouncing:
		return
	if not p.is_on_floor():
		return

	_werewolf_pouncing = false
	p.modulate = Color.WHITE
	p.sprite.scale.y = 1.0
	AudioManager.play("explosion", 0.0, 0.8)
	p._screen_shake(lerpf(3.0, 8.0, _werewolf_pounce_radius / 80.0), 0.25)

	# AoE slam damage
	p._spawn_vfx(Color(0.6, 0.4, 0.2, 0.7), Vector2(_werewolf_pounce_radius * 2.0, 16))

	var slam_bonus: float = PlayerManager.get_skill_bonus(p.player_index, "charge")
	if p._werewolf_frenzy_active:
		slam_bonus *= 1.3
	for body in get_tree().get_nodes_in_group("enemies"):
		if not body is Node2D:
			continue
		var dist: float = p.global_position.distance_to(body.global_position)
		if dist < _werewolf_pounce_radius:
			if body.has_method("take_damage"):
				body.take_damage(int(_werewolf_pounce_damage * slam_bonus), p.player_index)
				_spawn_werewolf_blood(body.global_position)
			if body.has_method("apply_knockback"):
				var kb: Vector2 = (body.global_position - p.global_position).normalized() * 250.0
				body.apply_knockback(kb)




# -- Charge Hooks (called by ChargeComponent) ----------------------------------

func on_charge_tick(_delta: float, _charge_ratio: float) -> void:
	p.sprite.scale.y = 0.7
	var shake_x: float = randf_range(-1.0, 1.0)
	p.position.x += shake_x * 0.5
	p.modulate = Color(0.7, 0.5, 0.3, 1.0)
	if p._charge_time > 0.3 and fmod(p._charge_time, 0.4) < 0.05:
		AudioManager.play("boss_roar", -6.0, 0.4)

func on_charge_release() -> void:
	p.sprite.scale.y = 1.0

func get_charge_threshold() -> float:
	return 0.15
