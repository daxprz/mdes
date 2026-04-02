extends "res://scripts/classes/class_component.gd"
## NOTE: Using path-based extends because Godot 4.6 class_name resolution
## requires editor scan. class_component.gd has class_name ClassComponent
## but it may not be registered yet when loading from source.

## Executioner class — ball-and-chain weapon system.
## Extracted from player_side.gd. References the player via ctx.body.
##
## Owns: spike ball, shackle, chain physics, YEET mechanics,
## prediction arc, swing/slam, cleave, tuning popup.

# -- Configurable Constants ---------------------------------------------------

const EXEC_BALL_RADIUS := 14.0
const EXEC_BALL_THROW_SPEED := 1200.0
const EXEC_BALL_MAX_THROW_SPEED := 6000.0
const EXEC_BALL_SPIN_SPEED := 4.0
const EXEC_BALL_SPIN_ACCEL := 3.0
const EXEC_BALL_MAX_SPIN := 10.0
const EXEC_BALL_GRAVITY := 900.0
const EXEC_BALL_WALL_DRAG := 12.0
const EXEC_BALL_PLAT_DRAG := 15.0
const EXEC_BALL_CEILING_DRAG := 20.0
const EXEC_BALL_SPIKE_COUNT := 12
const EXEC_BALL_SPIKE_LEN := 8.0
const EXEC_BALL_DAMAGE := 35
const EXEC_BALL_STUN_DURATION := 3.0
const EXEC_BALL_MASS := 140.0
const EXEC_CHAIN_ELASTICITY := 0.25

const EXEC_SHACKLE_THROW_SPEED := 400.0
const EXEC_SHACKLE_MAX_THROW_SPEED := 700.0
const EXEC_SHACKLE_SPIN_SPEED := 8.0
const EXEC_SHACKLE_SPIN_ACCEL := 6.0
const EXEC_SHACKLE_MAX_SPIN := 20.0
const EXEC_SHACKLE_GRAVITY := 600.0
const EXEC_SHACKLE_DRAG := 0.97
const EXEC_SHACKLE_DAMAGE := 15
const EXEC_SHACKLE_SNAP_RANGE := 40.0
const EXEC_SHACKLE_MASS := 5.0

const EXEC_CHAIN_TOTAL_LEN := 400.0
const EXEC_CHAIN_SPLIT_DEFAULT := 0.5
const EXEC_CHAIN_SPLIT_MIN := 0.1
const EXEC_CHAIN_SPLIT_MAX := 0.9
const EXEC_CHAIN_ADJUST_SPEED := 0.5
const EXEC_CHAIN_CLANK_INTERVAL := 0.08
const EXEC_CHAIN_DOUBLETAP_WINDOW := 0.3

const EXEC_SWING_SPIN_SPEED := 3.0
const EXEC_SWING_SPIN_ACCEL := 4.0
const EXEC_SWING_MAX_SPIN := 18.0
const EXEC_SWING_MIN_HOLD := 0.3
const EXEC_SWING_BASE_DAMAGE := 20
const EXEC_SWING_MAX_DAMAGE := 80
const EXEC_SWING_SLAM_RADIUS := 60.0
const EXEC_SWING_DUST_COUNT := 16
const EXEC_SWING_DUST_SPEED := 200.0
const EXEC_SWING_KNOCKBACK := 300.0

const EXEC_CLEAVE_CHARGE_TIME := 2.0
const EXEC_CLEAVE_MIN_CHARGE := 0.5
const EXEC_CLEAVE_BASE_DAMAGE := 40
const EXEC_CLEAVE_MAX_DAMAGE := 150
const EXEC_CLEAVE_RANGE := 50.0
const EXEC_CLEAVE_ARC := PI
const EXEC_CLEAVE_KNOCKBACK := 500.0
const EXEC_CLEAVE_ENEMY_KB := 400.0

# -- Enums (mirrored from player_side.gd for local use) -----------------------

enum ExecThrowMode { BALL_FIRST, SHACKLE_FIRST }
enum ExecEndState { HELD, WINDUP, THROWN, STUCK_WALL, STUCK_PLATFORM, STUCK_CEILING, ATTACHED_ENEMY, RETRACTING }
enum ExecChainMode { RELEASE_RELEASE, HOLD_RELEASE, HOLD_HOLD }

const EXEC_CHAIN_MODE_NAMES := ["Release", "Hold+Release", "Hold+Hold"]


# -- Convenience accessor for the player body ---------------------------------
# All executioner code references player state via p.property / p.method().
# Set once during inject_context, not a computed property (avoids Godot 4.6 type issues).

var p: Object = null


func inject_context(c) -> void:
	ctx = c
	p = c.body if c else null


func on_class_enter() -> void:
	## Called when executioner class is activated.
	p._init_shackle_entity()
	p._init_spikeball_entity()


func on_class_exit() -> void:
	## Called when executioner class is deactivated (class swap).
	## TODO: Clean up chains, shackle, spikeball
	pass


func tick(delta: float) -> void:
	## Per-frame executioner logic — delegates to player's existing code.
	## Functions will migrate here incrementally.
	p._handle_executioner(delta)


func perform_attack(_intent: Dictionary) -> void:
	exec_attack()


func perform_special(_intent: Dictionary) -> void:
	exec_special_cleave()


func perform_charged(charge_ratio: float) -> void:
	exec_charged_overhead(charge_ratio)


# -- Chain Length Helpers (migrated from player_side.gd) -----------------------

func exec_ball_chain_len() -> float:
	## How much chain the ball side gets.
	var total: float = p.cfg("exec_chain_total_len", EXEC_CHAIN_TOTAL_LEN)
	return total * p._exec_chain_split

func exec_shackle_chain_len() -> float:
	## Delegate to shackle entity.
	if p._shackle and is_instance_valid(p._shackle):
		return p._shackle.chain_len()
	var total: float = p.cfg("exec_chain_total_len", EXEC_CHAIN_TOTAL_LEN)
	return total * (1.0 - p._exec_chain_split)

func exec_is_bs_release() -> bool:
	## True when in Release mode — ball is chained to shackle, not player.
	var chain: Node2D = p._exec_chain_node
	return chain and is_instance_valid(chain) and chain.anchor_a.get("is_wall", false)

func exec_stuck_chain_anchor() -> Vector2:
	## Get the chain anchor for stuck states: shackle in B-S, player in B-P.
	if exec_is_bs_release():
		return p._exec_shackle_pos
	return p.global_position

func exec_stuck_chain_max() -> float:
	## Get the chain max length for stuck states: total in B-S, split in B-P.
	if exec_is_bs_release():
		return p.cfg("exec_chain_total_len", EXEC_CHAIN_TOTAL_LEN)
	return exec_ball_chain_len()

func exec_is_entity_yeet_mode() -> bool:
	## True when shackle is attached to an entity — ball YEETs the entity, not the player.
	return p._exec_shackle_state == ExecEndState.ATTACHED_ENEMY and \
		p._exec_shackle_anchor_body and is_instance_valid(p._exec_shackle_anchor_body)

func exec_get_ball_world_pos() -> Vector2:
	match p._exec_ball_state:
		ExecEndState.HELD:
			return p.global_position + Vector2(20.0 if p._facing_right else -20.0, -5.0)
		ExecEndState.WINDUP:
			return p.global_position + Vector2(cos(p._exec_ball_spin_angle), sin(p._exec_ball_spin_angle)) * 25.0
		_:
			return p._exec_ball_pos

func exec_get_shackle_world_pos() -> Vector2:
	match p._exec_shackle_state:
		ExecEndState.HELD:
			return p.global_position + Vector2(-15.0 if p._facing_right else 15.0, 0.0)
		ExecEndState.WINDUP:
			return p.global_position + Vector2(cos(p._exec_shackle_spin_angle), sin(p._exec_shackle_spin_angle)) * 20.0
		_:
			return p._exec_shackle_pos


# -- Chain Constraint (migrated from player_side.gd) --------------------------

func exec_apply_chain_constraint() -> void:
	## When the ball is stuck and chain is active, player can't move beyond chain length.
	if p.character_class != PlayerManager.CharacterClass.EXECUTIONER:
		return
	if p._exec_ball_state not in [ExecEndState.STUCK_WALL, ExecEndState.STUCK_PLATFORM, ExecEndState.STUCK_CEILING]:
		return
	if exec_is_entity_yeet_mode():
		return
	if not (p._exec_chain_node and is_instance_valid(p._exec_chain_node)):
		return
	if p._exec_chain_node.anchor_a.get("is_wall", false):
		return

	var ball_pos: Vector2 = exec_get_ball_world_pos()
	var to_ball: Vector2 = ball_pos - p.global_position
	var dist: float = to_ball.length()

	var ball_len: float = exec_ball_chain_len()
	if dist <= ball_len:
		p._exec_chain_taut = false
		return

	var chain_dir: Vector2 = to_ball.normalized()
	exec_try_yeet(chain_dir)

	var dir_from_ball: Vector2 = -chain_dir
	if p.is_on_floor():
		var dy: float = p.global_position.y - ball_pos.y
		var max_dx_sq: float = ball_len * ball_len - dy * dy
		if max_dx_sq < 0.0:
			p.global_position = ball_pos + dir_from_ball * ball_len
			p.velocity = Vector2.ZERO
		else:
			var max_dx: float = sqrt(max_dx_sq)
			var horizontal_dist: float = absf(p.global_position.x - ball_pos.x)
			if horizontal_dist > max_dx:
				var sign_x: float = signf(p.global_position.x - ball_pos.x)
				p.global_position.x = ball_pos.x + sign_x * max_dx
				if (p.velocity.x > 0 and sign_x > 0) or (p.velocity.x < 0 and sign_x < 0):
					p.velocity.x = 0
	else:
		p.global_position = ball_pos + dir_from_ball * ball_len
		var outward_vel: float = p.velocity.dot(dir_from_ball)
		if outward_vel > 0.0:
			p.velocity -= dir_from_ball * outward_vel


# -- YEET Physics (migrated from player_side.gd) ------------------------------

func exec_try_yeet(chain_dir: Vector2) -> void:
	## Partially elastic collision along the chain axis using ABSOLUTE masses.
	## Fires ONCE per slack→taut transition.
	if p._exec_chain_taut:
		return
	p._exec_chain_taut = true

	var m_ball: float = p.ball_cfg("mass", EXEC_BALL_MASS)
	var e: float = p.cfg("exec_chain_elasticity", EXEC_CHAIN_ELASTICITY)

	if exec_is_entity_yeet_mode():
		var entity: Node2D = p._exec_shackle_anchor_body
		var m_entity: float = p.entity_cfg(entity, "mass", 50.0)
		var e_entity: float = p.entity_cfg(entity, "chain_elasticity", e)
		var entity_vel: Vector2 = entity.velocity if "velocity" in entity else Vector2.ZERO

		var v_b: float = p._exec_ball_vel.dot(chain_dir)
		var v_e: float = entity_vel.dot(chain_dir)
		var relative_v: float = v_b - v_e

		if absf(relative_v) < 10.0:
			return

		var impulse_to_entity: float = (1.0 + e_entity) * m_ball / (m_ball + m_entity) * relative_v
		var impulse_to_ball: float = (1.0 + e_entity) * m_entity / (m_ball + m_entity) * relative_v

		var yeet_vec: Vector2 = chain_dir * impulse_to_entity
		if entity.has_method("apply_knockback"):
			entity.apply_knockback(yeet_vec)
		elif "velocity" in entity:
			entity.velocity += yeet_vec
		p._exec_ball_vel -= chain_dir * impulse_to_ball

		p._exec_yeet_immunity = 1.5
		AudioManager.play("grapple_hit", 2.0, 0.6)
		p._rumble(0.7, 1.0, 0.2)

		DebugOverlay.log("executioner/ball", p,
			"ENTITY YEET: %s mass=%.1f ball_mass=%.1f impulse=%.1f dir=(%.2f,%.2f)",
			[entity.name, m_entity, m_ball, impulse_to_entity, chain_dir.x, chain_dir.y])
		DebugOverlay.log("executioner/ball", p,
			"ENTITY YEET! %s impulse=%.0f dir=(%.2f,%.2f)",
			[entity.name, impulse_to_entity, chain_dir.x, chain_dir.y])
		return

	# NORMAL YEET: ball vs player
	var m_player: float = p.mass
	var v_b: float = p._exec_ball_vel.dot(chain_dir)
	var v_p: float = p.velocity.dot(chain_dir)
	var relative_v: float = v_b - v_p

	if absf(relative_v) < 10.0:
		return

	var pre_vel: Vector2 = p.velocity
	var impulse_to_player: float = (1.0 + e) * m_ball / (m_ball + m_player) * relative_v
	var impulse_to_ball: float = (1.0 + e) * m_player / (m_ball + m_player) * relative_v

	p.velocity += chain_dir * impulse_to_player
	p._exec_ball_vel -= chain_dir * impulse_to_ball

	p._exec_yeet_immunity = 1.5
	AudioManager.play("grapple_hit", 2.0, 0.6)
	p._rumble(0.7, 1.0, 0.2)

	DebugOverlay.log("executioner/ball", p,
		"YEET: dir=(%.1f,%.1f) vel=(%.1f,%.1f)->(%.1f,%.1f) impulse=%.1f m_b=%.1f m_p=%.1f e=%.2f",
		[chain_dir.x, chain_dir.y, pre_vel.x, pre_vel.y, p.velocity.x, p.velocity.y, impulse_to_player, m_ball, m_player, e])
	DebugOverlay.log("executioner/ball", p,
		"YEET! vel=(%.0f,%.0f)->(%.0f,%.0f) impulse=%.0f dir=(%.2f,%.2f)",
		[pre_vel.x, pre_vel.y, p.velocity.x, p.velocity.y, impulse_to_player,
		 chain_dir.x, chain_dir.y])


# -- B-S Stuck Pull (migrated from player_side.gd) ----------------------------

func exec_bs_stuck_pull(dir: Vector2, overshoot: float, _delta: float) -> void:
	## In B-S mode, when ball is stuck and chain is too long, yank the shackle
	## toward the ball (mass-weighted). Ball barely moves.
	var m_ball_bs: float = p.ball_cfg("mass", EXEC_BALL_MASS)
	var m_shackle_bs: float = p._shackle.cfg("mass", 5.0) if p._shackle else 5.0
	var total_mass: float = m_ball_bs + m_shackle_bs
	var shackle_frac: float = m_ball_bs / total_mass
	p._exec_shackle_pos -= dir * overshoot * shackle_frac
	if p._shackle:
		p._shackle._settled = false
		p._shackle._bounce_count = 0


# -- Chain Spawning (migrated from player_side.gd) ----------------------------

func exec_spawn_chain() -> void:
	## Spawn chain.gd for the ball side.
	if p._exec_chain_node and is_instance_valid(p._exec_chain_node):
		p._exec_chain_node.queue_free()
	var ChainScript: GDScript = load("res://scripts/systems/chain.gd")
	p._exec_chain_node = Node2D.new()
	p._exec_chain_node.set_script(ChainScript)
	var anchor_a: Dictionary
	var chain_len: float
	if exec_is_entity_yeet_mode():
		anchor_a = ChainScript.make_anchor_body(p._exec_shackle_anchor_body)
		chain_len = p.cfg("exec_chain_total_len", EXEC_CHAIN_TOTAL_LEN)
	else:
		anchor_a = ChainScript.make_anchor_body(p)
		chain_len = exec_ball_chain_len()
	var anchor_b: Dictionary = ChainScript.make_anchor_wall(p._exec_ball_pos)
	p._exec_chain_node.setup(anchor_a, anchor_b, chain_len, p.player_index)
	p.get_parent().add_child(p._exec_chain_node)
	DebugOverlay.log("executioner/ball", p, "BALL CHAIN: len=%.0f entity_mode=%s",
		[chain_len, str(exec_is_entity_yeet_mode())])


func exec_spawn_shackle_chain() -> void:
	## Delegate to shackle entity.
	if p._shackle and is_instance_valid(p._shackle):
		p._shackle.spawn_chain_to_player()
		return
	# Legacy fallback
	if p._exec_shackle_chain_node and is_instance_valid(p._exec_shackle_chain_node):
		p._exec_shackle_chain_node.queue_free()
	var ChainScript: GDScript = load("res://scripts/systems/chain.gd")
	p._exec_shackle_chain_node = Node2D.new()
	p._exec_shackle_chain_node.set_script(ChainScript)
	var anchor_a: Dictionary = ChainScript.make_anchor_body(p)
	var anchor_b: Dictionary = ChainScript.make_anchor_wall(p._exec_shackle_pos)
	p._exec_shackle_chain_node.setup(anchor_a, anchor_b, exec_shackle_chain_len(), p.player_index)
	p.get_parent().add_child(p._exec_shackle_chain_node)
	DebugOverlay.log("executioner/throw", p, "SHACKLE CHAIN: len=%.0f (split=%.0f%%)",
		[exec_shackle_chain_len(), (1.0 - p._exec_chain_split) * 100])


func exec_spawn_ball_to_shackle_chain() -> void:
	## Spawn a chain.gd between ball and shackle — NO player connection (RELEASE mode).
	if p._exec_chain_node and is_instance_valid(p._exec_chain_node):
		p._exec_chain_node.queue_free()
	var ChainScript: GDScript = load("res://scripts/systems/chain.gd")
	p._exec_chain_node = Node2D.new()
	p._exec_chain_node.set_script(ChainScript)
	var anchor_a: Dictionary = ChainScript.make_anchor_wall(p._exec_ball_pos)
	var anchor_b: Dictionary = ChainScript.make_anchor_wall(p._exec_shackle_pos)
	var total_len: float = p.cfg("exec_chain_total_len", EXEC_CHAIN_TOTAL_LEN)
	p._exec_chain_node.setup(anchor_a, anchor_b, total_len, p.player_index)
	p.get_parent().add_child(p._exec_chain_node)
	DebugOverlay.log("executioner/throw", p, "B-S CHAIN: len=%.0f (no player)", [total_len])


func exec_update_chain_ball_anchor() -> void:
	## Keep chain anchors in sync with ball (and shackle if B-S mode).
	if p._exec_chain_node and is_instance_valid(p._exec_chain_node) and not p._exec_chain_node._severed:
		if p._exec_chain_node.anchor_a.get("is_wall", false):
			p._exec_chain_node.anchor_a["pos"] = p._exec_ball_pos
			p._exec_chain_node.anchor_b["pos"] = p._exec_shackle_pos
		else:
			p._exec_chain_node.anchor_b["pos"] = p._exec_ball_pos


func exec_update_chain_shackle_anchor() -> void:
	## Delegate to shackle entity.
	if p._shackle and is_instance_valid(p._shackle):
		p._shackle.update_chain_anchor()


func exec_check_chain_severed() -> void:
	## If either chain was severed (broken by damage), retract that side.
	if p._exec_chain_node and is_instance_valid(p._exec_chain_node):
		if p._exec_chain_node._severed:
			p._exec_chain_node = null
			p._exec_ball_state = ExecEndState.RETRACTING
			DebugOverlay.log("executioner/ball", p, "BALL CHAIN BROKEN — retracting ball")
	if p._exec_shackle_chain_node and is_instance_valid(p._exec_shackle_chain_node):
		if p._exec_shackle_chain_node._severed:
			p._exec_shackle_chain_node = null
			p._exec_shackle_state = ExecEndState.RETRACTING
			DebugOverlay.log("executioner/throw", p, "SHACKLE CHAIN BROKEN — retracting shackle")


# -- Shackle/Swing Tick (migrated from player_side.gd) ------------------------

func exec_tick_shackle(delta: float) -> void:
	## Delegate to ShackleEntity for all physics.
	if p._shackle and is_instance_valid(p._shackle):
		p._shackle.tick(delta)

func exec_try_snap_shackle_to_enemy() -> bool:
	## Delegate to shackle entity.
	if p._shackle and is_instance_valid(p._shackle):
		return p._shackle.try_snap_to_enemy()
	return false

func exec_tick_swing(delta: float) -> void:
	if not p._exec_swing_active:
		return
	p._exec_swing_time += delta
	p._exec_swing_angular_vel = minf(p._exec_swing_angular_vel + EXEC_SWING_SPIN_ACCEL * delta, EXEC_SWING_MAX_SPIN)
	var dir_sign: float = 1.0 if p._facing_right else -1.0
	p._exec_swing_angle += p._exec_swing_angular_vel * delta * dir_sign
	p.velocity.x *= 0.85
	if not p._is_device_action_pressed("attack"):
		exec_perform_slam()
		p._exec_swing_active = false


# -- Combat (migrated from player_side.gd) ------------------------------------

func exec_attack() -> void:
	if p._exec_swing_active:
		return
	p._exec_swing_active = true
	p._exec_swing_time = 0.0
	p._exec_swing_angle = -PI * 0.5
	p._exec_swing_angular_vel = EXEC_SWING_SPIN_SPEED
	AudioManager.play("sword_slash", -2.0, 0.5)


func exec_perform_slam() -> void:
	var hold_t: float = clampf(p._exec_swing_time / 2.0, 0.0, 1.0)
	if p._exec_swing_time < EXEC_SWING_MIN_HOLD:
		DebugOverlay.log("executioner/swing", p, "SWING CANCEL: too short %.2fs", [p._exec_swing_time])
		return
	var damage: int = int(lerpf(EXEC_SWING_BASE_DAMAGE, EXEC_SWING_MAX_DAMAGE, hold_t))
	var slam_pos: Vector2 = p.global_position + Vector2(30.0 if p._facing_right else -30.0, 10.0)
	AudioManager.play("explosion", 2.0, 0.35)
	p._rumble(0.8, 1.0, 0.3)
	p._screen_shake(lerpf(3.0, 10.0, hold_t), 0.25)
	for i in range(EXEC_SWING_DUST_COUNT):
		var angle: float = float(i) / float(EXEC_SWING_DUST_COUNT) * TAU
		var dust := ColorRect.new()
		dust.color = Color(0.6, 0.55, 0.4, 0.7)
		dust.size = Vector2(randf_range(3, 6), randf_range(3, 6))
		dust.position = slam_pos
		dust.z_index = 4
		p.get_parent().add_child(dust)
		var target_pos: Vector2 = slam_pos + Vector2(cos(angle), sin(angle)) * EXEC_SWING_DUST_SPEED * randf_range(0.5, 1.0) * 0.3
		var dt := dust.create_tween()
		dt.tween_property(dust, "position", target_pos, 0.3).set_ease(Tween.EASE_OUT)
		dt.parallel().tween_property(dust, "modulate:a", 0.0, 0.25)
		dt.tween_callback(dust.queue_free)
	var attack_bonus: float = PlayerManager.get_skill_bonus(p.player_index, "attack")
	for body in get_tree().get_nodes_in_group("enemies"):
		if not body is Node2D:
			continue
		if slam_pos.distance_to(body.global_position) < EXEC_SWING_SLAM_RADIUS:
			if body.has_method("take_damage"):
				body.take_damage(int(damage * attack_bonus), p.player_index)
				p._spawn_blood_particles(body.global_position)
			if body.has_method("apply_knockback"):
				body.apply_knockback((body.global_position - slam_pos).normalized() * EXEC_SWING_KNOCKBACK * hold_t)
	DebugOverlay.log("executioner/swing", p, "SLAM: hold=%.2fs dmg=%d", [p._exec_swing_time, damage])
	PlayerManager.add_skill_xp(p.player_index, "attack", 4)


func exec_handle_chain_mode() -> void:
	## Circle toggles chain mode: Release / Hold+Release / Hold+Hold
	if not p._is_device_action_just_pressed("interact"):
		return
	p._exec_chain_mode = ((p._exec_chain_mode + 1) % 3) as ExecChainMode
	p._exec_chain_mode_changed_timer = 1.5
	AudioManager.play("grapple_hit", -4.0, 1.0 + p._exec_chain_mode * 0.3)
	DebugOverlay.log("executioner/throw", p, "CHAIN MODE: %s",
		[EXEC_CHAIN_MODE_NAMES[p._exec_chain_mode]])


func exec_special_cleave() -> void:
	p._exec_cleave_charging = true
	p._exec_cleave_charge_time = 0.0
	AudioManager.play("shield_charge", -2.0, 0.4)


func exec_tick_cleave(delta: float) -> void:
	if not p._exec_cleave_charging:
		return
	p._exec_cleave_charge_time += delta
	p.velocity.x *= 0.5
	if p._exec_cleave_charge_time > 0.5:
		p.position.x += sin(Time.get_ticks_msec() * 0.05) * (p._exec_cleave_charge_time * 0.5)
	if p._exec_cleave_charge_time >= EXEC_CLEAVE_CHARGE_TIME or not p._is_device_action_pressed("special"):
		exec_fire_cleave()
		p._exec_cleave_charging = false


func exec_fire_cleave() -> void:
	if p._exec_cleave_charge_time < EXEC_CLEAVE_MIN_CHARGE:
		DebugOverlay.log("executioner/cleave", p, "CLEAVE CANCEL: charge=%.2f", [p._exec_cleave_charge_time])
		return
	var charge_t: float = clampf(
		(p._exec_cleave_charge_time - EXEC_CLEAVE_MIN_CHARGE) /
		(EXEC_CLEAVE_CHARGE_TIME - EXEC_CLEAVE_MIN_CHARGE), 0.0, 1.0)
	var damage: int = int(lerpf(EXEC_CLEAVE_BASE_DAMAGE, EXEC_CLEAVE_MAX_DAMAGE, charge_t))
	var aim: Vector2 = p._get_aim_direction_analog()
	AudioManager.play("explosion", 4.0, 0.25)
	p._rumble(1.0, 1.0, 0.4)
	p._screen_shake(lerpf(5.0, 15.0, charge_t), 0.3)
	p._exec_cleave_flash_timer = 0.15
	var attack_bonus: float = PlayerManager.get_skill_bonus(p.player_index, "attack")
	for body in get_tree().get_nodes_in_group("enemies"):
		if not body is Node2D:
			continue
		var to_enemy: Vector2 = body.global_position - p.global_position
		if to_enemy.length() > EXEC_CLEAVE_RANGE:
			continue
		if absf(aim.angle_to(to_enemy.normalized())) > EXEC_CLEAVE_ARC * 0.5:
			continue
		if body.has_method("take_damage"):
			body.take_damage(int(damage * attack_bonus), p.player_index)
			p._spawn_blood_particles(body.global_position)
		if body.has_method("apply_knockback"):
			body.apply_knockback(to_enemy.normalized() * EXEC_CLEAVE_ENEMY_KB * charge_t)
	p.velocity += -aim * EXEC_CLEAVE_KNOCKBACK * charge_t
	p.velocity.y = minf(p.velocity.y, -150.0 * charge_t)
	for i in range(8):
		var arc_start: float = aim.angle() - EXEC_CLEAVE_ARC * 0.5
		var a: float = arc_start + (float(i) / 7.0) * EXEC_CLEAVE_ARC
		var spark := ColorRect.new()
		spark.color = Color(1.0, 0.95, 0.85, 0.9)
		spark.size = Vector2(lerpf(4, 8, charge_t), lerpf(4, 8, charge_t))
		spark.position = p.global_position + Vector2(cos(a), sin(a)) * EXEC_CLEAVE_RANGE
		spark.z_index = 10
		p.get_parent().add_child(spark)
		var st := spark.create_tween()
		st.tween_property(spark, "position", spark.position + Vector2(cos(a), sin(a)) * 30.0, 0.12)
		st.parallel().tween_property(spark, "modulate:a", 0.0, 0.15)
		st.tween_callback(spark.queue_free)
	PlayerManager.add_skill_xp(p.player_index, "special", 8)
	DebugOverlay.log("executioner/cleave", p, "CLEAVE: charge=%.2f dmg=%d kb=%.0f",
		[p._exec_cleave_charge_time, damage, EXEC_CLEAVE_KNOCKBACK * charge_t])


func exec_charged_overhead(charge_ratio: float) -> void:
	var damage: int = int(lerpf(EXEC_SWING_BASE_DAMAGE * 1.5, EXEC_SWING_MAX_DAMAGE * 1.5, charge_ratio))
	var slam_pos: Vector2 = p.global_position + Vector2(35.0 if p._facing_right else -35.0, 10.0)
	AudioManager.play("explosion", 4.0, 0.3)
	p._rumble(1.0, 1.0, 0.4)
	p._screen_shake(lerpf(5.0, 14.0, charge_ratio), 0.3)
	var dust_count: int = int(EXEC_SWING_DUST_COUNT * 1.5)
	for i in range(dust_count):
		var angle: float = float(i) / float(dust_count) * TAU
		var dust := ColorRect.new()
		dust.color = Color(0.5, 0.45, 0.3, 0.8)
		dust.size = Vector2(randf_range(4, 8), randf_range(4, 8))
		dust.position = slam_pos
		dust.z_index = 4
		p.get_parent().add_child(dust)
		var dt := dust.create_tween()
		dt.tween_property(dust, "position", slam_pos + Vector2(cos(angle), sin(angle)) * EXEC_SWING_DUST_SPEED * 0.5, 0.4).set_ease(Tween.EASE_OUT)
		dt.parallel().tween_property(dust, "modulate:a", 0.0, 0.35)
		dt.tween_callback(dust.queue_free)
	var attack_bonus: float = PlayerManager.get_skill_bonus(p.player_index, "charge")
	for body in get_tree().get_nodes_in_group("enemies"):
		if not body is Node2D:
			continue
		if slam_pos.distance_to(body.global_position) < EXEC_SWING_SLAM_RADIUS * 1.3:
			if body.has_method("take_damage"):
				body.take_damage(int(damage * attack_bonus), p.player_index)
				p._spawn_blood_particles(body.global_position)
			if body.has_method("apply_knockback"):
				body.apply_knockback((body.global_position - slam_pos).normalized() * EXEC_SWING_KNOCKBACK * 1.5)
	PlayerManager.add_skill_xp(p.player_index, "charge", 6)
	DebugOverlay.log("executioner/swing", p, "CHARGED OVERHEAD: ratio=%.2f dmg=%d", [charge_ratio, damage])
