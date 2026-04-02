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
const EXEC_CHAIN_MODE_COLORS: Array[Color] = [
	Color(0.9, 0.4, 0.2),
	Color(0.8, 0.7, 0.2),
	Color(0.3, 0.7, 0.9),
]

const EXEC_TUNING_KEYS: Array[Array] = [
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
	exec_main_tick(delta)


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

	var m_ball: float = p.ball_cfg("p.mass", EXEC_BALL_MASS)
	var e: float = p.cfg("exec_chain_elasticity", EXEC_CHAIN_ELASTICITY)

	if exec_is_entity_yeet_mode():
		var entity: Node2D = p._exec_shackle_anchor_body
		var m_entity: float = p.entity_cfg(entity, "p.mass", 50.0)
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
			"ENTITY YEET: %s p.mass=%.1f ball_mass=%.1f impulse=%.1f dir=(%.2f,%.2f)",
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
	## toward the ball (p.mass-weighted). Ball barely moves.
	var m_ball_bs: float = p.ball_cfg("p.mass", EXEC_BALL_MASS)
	var m_shackle_bs: float = p._shackle.cfg("p.mass", 5.0) if p._shackle else 5.0
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

# -- Main Tick + Throw + Preview + Ball Tick (migrated) -----------------------

func exec_main_tick(delta: float) -> void:
	if p.character_class != PlayerManager.CharacterClass.EXECUTIONER:
		return
	p._exec_test_tick(delta)
	exec_handle_mode_toggle()
	exec_handle_chain_length(delta)
	exec_handle_throw(delta)
	exec_tick_swing(delta)
	exec_handle_chain_mode()
	exec_tick_cleave(delta)
	exec_tick_ball(delta)
	exec_tick_shackle(delta)
	# Update spikeball entity position — persistent, tracks ball position
	if p._exec_ball_marker and is_instance_valid(p._exec_ball_marker):
		if p._exec_ball_state == ExecEndState.HELD:
			p._exec_ball_marker.global_position = p.global_position
		else:
			p._exec_ball_marker.global_position = p._exec_ball_pos
	exec_check_chain_severed()
	if p._exec_cleave_flash_timer > 0.0:
		p._exec_cleave_flash_timer -= delta
	if p._exec_chain_mode_changed_timer > 0.0:
		p._exec_chain_mode_changed_timer -= delta
	if p._exec_yeet_immunity > 0.0:
		p._exec_yeet_immunity -= delta
	if p._exec_chain_radius_fade > 0.0:
		p._exec_chain_radius_fade -= delta
	p._exec_ball_rotation += delta * 1.5
	p.queue_redraw()


func exec_handle_mode_toggle() -> void:
	## R1 always works:
	##   - Nothing out: toggle ball/shackle order
	##   - Ball out: recall ball, ready for next throw
	##   - Shackle out: recall shackle, ready for next throw
	##   - Both out: recall both
	## No stuck states possible.
	var r1_pressed: bool = false
	if p.device_id >= 0:
		r1_pressed = Input.is_joy_button_pressed(p.device_id, JOY_BUTTON_RIGHT_SHOULDER)
	else:
		r1_pressed = Input.is_key_pressed(KEY_R)
	if r1_pressed and not p._exec_r1_was_pressed:
		var anything_out: bool = p._exec_ball_state not in [ExecEndState.HELD, ExecEndState.WINDUP, ExecEndState.RETRACTING] or \
			p._exec_shackle_state not in [ExecEndState.HELD, ExecEndState.WINDUP, ExecEndState.RETRACTING]

		if anything_out:
			# Recall everything that's out
			if p._exec_ball_state not in [ExecEndState.HELD, ExecEndState.RETRACTING]:
				p._exec_ball_state = ExecEndState.RETRACTING
				DebugOverlay.log("executioner/throw", p, "R1 RECALL: ball")
			if p._exec_shackle_state not in [ExecEndState.HELD, ExecEndState.RETRACTING]:
				p._exec_shackle_state = ExecEndState.RETRACTING
				DebugOverlay.log("executioner/throw", p, "R1 RECALL: shackle")
			p._exec_throw_step = 0
			# Destroy chain nodes
			if p._exec_chain_node and is_instance_valid(p._exec_chain_node):
				p._exec_chain_node.queue_free()
				p._exec_chain_node = null
			if p._exec_shackle_chain_node and is_instance_valid(p._exec_shackle_chain_node):
				p._exec_shackle_chain_node.queue_free()
				p._exec_shackle_chain_node = null
		else:
			# Nothing out — toggle throw order
			if p._exec_throw_mode == ExecThrowMode.BALL_FIRST:
				p._exec_throw_mode = ExecThrowMode.SHACKLE_FIRST
			else:
				p._exec_throw_mode = ExecThrowMode.BALL_FIRST
			DebugOverlay.log("executioner/throw", p, "MODE TOGGLE: %s",
				["BALL_FIRST" if p._exec_throw_mode == ExecThrowMode.BALL_FIRST else "SHACKLE_FIRST"])
	p._exec_r1_was_pressed = r1_pressed


# -- Chain Length Adjustment (L2 shortens, R2 lengthens) -----------------------

func exec_handle_chain_length(delta: float) -> void:
	## L2 = more chain to ball (less to shackle), R2 = more to shackle (less to ball).
	## The TOTAL chain length is fixed. L2/R2 adjusts the split ratio.
	## Double-tap L2 = max ball. Double-tap R2 = max shackle.

	# Tick double-tap timers
	if p._exec_l2_tap_timer > 0.0:
		p._exec_l2_tap_timer -= delta
	if p._exec_r2_tap_timer > 0.0:
		p._exec_r2_tap_timer -= delta

	# Read trigger values
	var l2_val: float = 0.0
	var r2_val: float = 0.0
	if p.device_id >= 0:
		l2_val = clampf(Input.get_joy_axis(p.device_id, JOY_AXIS_TRIGGER_LEFT), 0.0, 1.0)
		r2_val = clampf(Input.get_joy_axis(p.device_id, JOY_AXIS_TRIGGER_RIGHT), 0.0, 1.0)
	else:
		if Input.is_key_pressed(KEY_TAB):
			l2_val = 1.0
		if Input.is_key_pressed(KEY_ENTER):
			r2_val = 1.0

	var l2_pressed: bool = l2_val > 0.3
	var r2_pressed: bool = r2_val > 0.3
	var old_split: float = p._exec_chain_split

	# Double-tap detection: L2 = max ball
	if l2_pressed and not p._exec_l2_was_pressed:
		if p._exec_l2_tap_timer > 0.0:
			p._exec_chain_split = EXEC_CHAIN_SPLIT_MAX
			AudioManager.play("grapple_hit", 0.0, 1.5)
			DebugOverlay.log("executioner/ball", p, "SPLIT SNAP MAX BALL: %.0f%%", [p._exec_chain_split * 100])
			p._exec_l2_tap_timer = 0.0
		else:
			p._exec_l2_tap_timer = EXEC_CHAIN_DOUBLETAP_WINDOW

	# Double-tap detection: R2 = max shackle
	if r2_pressed and not p._exec_r2_was_pressed:
		if p._exec_r2_tap_timer > 0.0:
			p._exec_chain_split = EXEC_CHAIN_SPLIT_MIN
			AudioManager.play("grapple_hit", 0.0, 0.6)
			DebugOverlay.log("executioner/ball", p, "SPLIT SNAP MAX SHACKLE: %.0f%%", [p._exec_chain_split * 100])
			p._exec_r2_tap_timer = 0.0
		else:
			p._exec_r2_tap_timer = EXEC_CHAIN_DOUBLETAP_WINDOW

	p._exec_l2_was_pressed = l2_pressed
	p._exec_r2_was_pressed = r2_pressed

	# Continuous: L2 = more to ball, R2 = more to shackle
	var adjust_speed: float = p.cfg("exec_chain_adjust_speed", EXEC_CHAIN_ADJUST_SPEED)
	if l2_val > 0.1:
		p._exec_chain_split += adjust_speed * l2_val * delta
	if r2_val > 0.1:
		p._exec_chain_split -= adjust_speed * r2_val * delta

	p._exec_chain_split = clampf(p._exec_chain_split, EXEC_CHAIN_SPLIT_MIN, EXEC_CHAIN_SPLIT_MAX)

	# Update chain.gd target_lengths — but NOT for B-S chains (they use full length)
	if p._exec_chain_node and is_instance_valid(p._exec_chain_node) and not p._exec_chain_node._severed:
		if not p._exec_chain_node.anchor_a.get("is_wall", false):
			# B-P chain: ball side gets split portion
			p._exec_chain_node.target_length = exec_ball_chain_len()
		# else: B-S chain keeps its full target_length (set at creation)
	if p._exec_shackle_chain_node and is_instance_valid(p._exec_shackle_chain_node) and not p._exec_shackle_chain_node._severed:
		p._exec_shackle_chain_node.target_length = exec_shackle_chain_len()

	# Sync chain physics settings from player config
	var chain_damp: float = p.cfg("exec_chain_damping", 0.85)
	var chain_grav: float = p.cfg("exec_chain_gravity", 600.0)
	if p._exec_chain_node and is_instance_valid(p._exec_chain_node) and not p._exec_chain_node._severed:
		p._exec_chain_node.chain_damping = chain_damp
		p._exec_chain_node.chain_gravity = chain_grav
	if p._exec_shackle_chain_node and is_instance_valid(p._exec_shackle_chain_node) and not p._exec_shackle_chain_node._severed:
		p._exec_shackle_chain_node.chain_damping = chain_damp
		p._exec_shackle_chain_node.chain_gravity = chain_grav

	# Track whether split is actively changing (for radius display)
	var split_delta: float = p._exec_chain_split - old_split
	p._exec_chain_len_changing = absf(split_delta) > 0.001

	# Chain clink sound while reeling
	var chain_is_out: bool = p._exec_ball_state not in [ExecEndState.HELD, ExecEndState.WINDUP]
	var shackle_is_out: bool = p._exec_shackle_state not in [ExecEndState.HELD, ExecEndState.WINDUP]
	if p._exec_chain_len_changing and (chain_is_out or shackle_is_out):
		p._exec_chain_reel_timer -= delta
		if p._exec_chain_reel_timer <= 0.0:
			var pitch: float = 1.4 if split_delta > 0 else 0.9
			AudioManager.play("grapple_hit", -8.0, pitch + randf_range(-0.1, 0.1))
			p._exec_chain_reel_timer = 0.06
	else:
		p._exec_chain_reel_timer = 0.0


func exec_handle_throw(delta: float) -> void:
	if p._exec_swing_active:
		return
	var is_throwing_ball: bool = (
		(p._exec_throw_step == 0 and p._exec_throw_mode == ExecThrowMode.BALL_FIRST) or
		(p._exec_throw_step == 1 and p._exec_throw_mode == ExecThrowMode.SHACKLE_FIRST))
	if p._exec_throw_step >= 2:
		if p._is_device_action_just_pressed("grapple"):
			exec_retract_all()
		return
	if p._is_device_action_just_pressed("grapple"):
		DebugOverlay.log("executioner/throw", p,
			"GRAPPLE PRESSED: step=%d is_ball=%s ball_state=%d shackle_state=%d",
			[p._exec_throw_step, str(is_throwing_ball), p._exec_ball_state, p._exec_shackle_state])
		if is_throwing_ball and p._exec_ball_state == ExecEndState.HELD:
			p._exec_ball_state = ExecEndState.WINDUP
			p._exec_ball_hold_time = 0.0
			p._exec_ball_angular_vel = p.ball_cfg("spin_speed", EXEC_BALL_SPIN_SPEED)
			p._exec_ball_spin_angle = 0.0
		elif not is_throwing_ball and p._exec_shackle_state == ExecEndState.HELD:
			p._exec_shackle_state = ExecEndState.WINDUP
			p._exec_shackle_hold_time = 0.0
			p._exec_shackle_angular_vel = EXEC_SHACKLE_SPIN_SPEED
			p._exec_shackle_spin_angle = 0.0
	if p._exec_ball_state == ExecEndState.WINDUP:
		p._exec_ball_hold_time += delta
		p._exec_ball_angular_vel = minf(p._exec_ball_angular_vel + p.ball_cfg("spin_accel", EXEC_BALL_SPIN_ACCEL) * delta, p.ball_cfg("max_spin", EXEC_BALL_MAX_SPIN))
		var dir_sign: float = 1.0 if p._facing_right else -1.0
		p._exec_ball_spin_angle += p._exec_ball_angular_vel * delta * dir_sign
		p.velocity.x *= 0.6
		# Show trajectory preview (like monster leap) — right stick priority for aiming
		var aim: Vector2 = p._get_aim_direction_analog()
		var charge_t: float = clampf(p._exec_ball_hold_time / 1.5, 0.0, 1.0)
		var speed: float = lerpf(p.ball_cfg("throw_speed", EXEC_BALL_THROW_SPEED), p.ball_cfg("max_throw_speed", EXEC_BALL_MAX_THROW_SPEED), charge_t)
		exec_update_preview(aim * speed)
		if not p._is_device_action_pressed("grapple"):
			p._exec_preview_arc.clear()
			p._exec_preview_arc_inner.clear()
			exec_throw_ball()
	else:
		if not p._exec_preview_arc.is_empty():
			p._exec_preview_arc.clear()
			p._exec_preview_arc_inner.clear()
	if p._exec_shackle_state == ExecEndState.WINDUP:
		p._exec_shackle_hold_time += delta
		p._exec_shackle_angular_vel = minf(p._exec_shackle_angular_vel + EXEC_SHACKLE_SPIN_ACCEL * delta, EXEC_SHACKLE_MAX_SPIN)
		var dir_sign: float = 1.0 if p._facing_right else -1.0
		p._exec_shackle_spin_angle += p._exec_shackle_angular_vel * delta * dir_sign
		# Shackle trajectory preview — narrow line like monster leap
		var s_aim: Vector2 = p._get_aim_direction_analog()
		var s_charge_t: float = clampf(p._exec_shackle_hold_time / 1.0, 0.0, 1.0)
		var s_speed: float = lerpf(EXEC_SHACKLE_THROW_SPEED, EXEC_SHACKLE_MAX_THROW_SPEED, s_charge_t)
		exec_update_shackle_preview(s_aim * s_speed)
		if not p._is_device_action_pressed("grapple"):
			p._exec_shackle_preview_arc.clear()
			exec_throw_shackle()
	else:
		if not p._exec_shackle_preview_arc.is_empty():
			p._exec_shackle_preview_arc.clear()


func exec_update_preview(launch_vel: Vector2) -> void:
	## Run TWO coupled simulations to form a probability cone:
	##   Outer arc: optimistic (no floor damping on player)
	##   Inner arc: pessimistic (player stops on floor, heavy ball friction)
	## Reality should always fall between the two.
	var R: float = exec_ball_chain_len()
	var g: float = p.ball_cfg("gravity", EXEC_BALL_GRAVITY)
	var mb: float = p.ball_cfg("p.mass", EXEC_BALL_MASS)
	var e: float = p.cfg("exec_chain_elasticity", EXEC_CHAIN_ELASTICITY)
	var space = p.get_world_2d().direct_space_state

	# Floor
	var floor_y: float = 5000.0
	if space:
		var fq := PhysicsRayQueryParameters2D.create(p.global_position, p.global_position + Vector2(0, 300), 1)
		fq.exclude = [p.get_rid()]
		var fr: Dictionary = space.intersect_ray(fq)
		if fr:
			floor_y = fr["position"].y - p.global_position.y

	# Viewport bounds
	var cam = p.get_viewport().get_camera_2d()
	var vp: Vector2 = p.get_viewport_rect().size
	var zm: Vector2 = cam.zoom if cam and cam.zoom.x > 0 else Vector2.ONE
	var hv: Vector2 = vp / (2.0 * zm)
	var cp: Vector2 = (cam.global_position if cam else p.global_position) - p.global_position
	var v_min: Vector2 = cp - hv
	var v_max: Vector2 = cp + hv

	# Outer arc: optimistic — no damping, pure physics
	p._exec_preview_arc = exec_sim_arc(launch_vel, R, g, mb, e, floor_y, 1.0, space, v_min, v_max, true)

	# Inner arc: pessimistic — models chain friction, movement override, air drag
	# 0.95 per step at 60fps ≈ retains 0.95^60 = 4.6% per second (very aggressive)
	p._exec_preview_arc_inner = exec_sim_arc(launch_vel, R, g, mb, e, floor_y, 0.95, space, v_min, v_max, false)


func exec_sim_arc(launch_vel: Vector2, R: float, g: float, mb: float, e: float,
		floor_y: float, vel_retain: float,
		space: PhysicsDirectSpaceState2D, v_min: Vector2, v_max: Vector2,
		log_yeets: bool) -> PackedVector2Array:
	## Core two-body string simulation. Returns ball arc points.
	## vel_retain: p.velocity multiplier per frame (1.0 = no damping, 0.99 = light damping)
	var dt: float = 0.016
	var max_steps: int = 600
	var mp: float = p.mass  # Player's absolute p.mass
	var bp := Vector2.ZERO
	var bv := launch_vel
	var pp := Vector2.ZERO
	var pv: Vector2 = p.velocity
	var taut: bool = false
	var arc := PackedVector2Array()
	arc.append(bp)

	for _i in range(max_steps):
		bv.y += g * dt
		pv.y += g * dt
		var prev_bp: Vector2 = bp
		bp += bv * dt
		pp += pv * dt

		# Velocity damping — models chain friction, movement system, etc.
		bv *= vel_retain
		pv *= vel_retain

		# Floor collisions
		if pp.y >= floor_y:
			pp.y = floor_y
			if pv.y > 0:
				pv.y = 0

		if bp.y >= floor_y:
			bp.y = floor_y
			if bv.y > 0:
				bv.y = 0

		# String constraint
		var cv: Vector2 = bp - pp
		var cd: float = cv.length()
		if cd > R:
			var cn: Vector2 = cv / cd
			if not taut:
				taut = true
				var vb_c: float = bv.dot(cn)
				var vp_c: float = pv.dot(cn)
				var rv: float = vb_c - vp_c
				if absf(rv) > 1.0:
					var coeff: float = (1.0 + e) / (mb + mp)
					var imp_p: float = coeff * mb * rv
					pv += cn * imp_p
					bv -= cn * (coeff * mp * rv)
					if log_yeets:
						DebugOverlay.log("executioner/ball", p,
							"SIM YEET #%d: dir=(%.2f,%.2f) imp=%.0f rv=%.0f",
							[arc.size(), cn.x, cn.y, imp_p, rv])
			else:
				var excess: float = cd - R
				bp -= cn * (excess * mp / (mb + mp))
				pp += cn * (excess * mb / (mb + mp))
				var ro: float = (bv - pv).dot(cn)
				if ro > 0.0:
					bv -= cn * (ro * mp / (mb + mp))
					pv += cn * (ro * mb / (mb + mp))
		else:
			taut = false

		arc.append(bp)

		# Stop: ball hits physics body (only when slack)
		if not taut and space and _i % 3 == 0:
			var wp: Vector2 = p.global_position + prev_bp
			var wn: Vector2 = p.global_position + bp
			if wp.distance_squared_to(wn) > 1.0:
				var q := PhysicsRayQueryParameters2D.create(wp, wn, 1)
				q.exclude = [p.get_rid()]
				if not space.intersect_ray(q).is_empty():
					break

		if bp.x < v_min.x or bp.x > v_max.x or bp.y < v_min.y or bp.y > v_max.y:
			break

		if _i > 60 and bv.length_squared() < 100.0:
			break

	if log_yeets:
		DebugOverlay.log("executioner/ball", p,
			"SIM DONE: %d pts, ball=(%.0f,%.0f) player=(%.0f,%.0f)",
			[arc.size(), bp.x, bp.y, pp.x, pp.y])
	return arc


func exec_update_shackle_preview(launch_vel: Vector2) -> void:
	## Shackle trajectory: narrow precise line (like monster leap arc).
	var dt: float = 0.02
	var max_steps: int = 60
	var pos := Vector2.ZERO
	var vel := launch_vel
	p._exec_shackle_preview_arc.clear()
	p._exec_shackle_preview_arc.append(pos)
	for _i in range(max_steps):
		vel.y += EXEC_SHACKLE_GRAVITY * dt
		pos += vel * dt
		p._exec_shackle_preview_arc.append(pos)
		if pos.length() > exec_shackle_chain_len():
			break
		if pos.y > 400.0:
			break


func exec_should_hold_on_throw() -> bool:
	## Based on chain mode and throw step, should the player hold the chain?
	## p._exec_throw_step is BEFORE increment (0 = first throw, 1 = second throw)
	var is_first: bool = (p._exec_throw_step == 0)
	match p._exec_chain_mode:
		ExecChainMode.RELEASE_RELEASE:
			return false  # Never hold
		ExecChainMode.HOLD_RELEASE:
			return is_first  # Hold on first, release on second
		ExecChainMode.HOLD_HOLD:
			return true  # Always hold
	return true


func exec_throw_ball() -> void:
	var aim: Vector2 = p._get_aim_direction_analog()
	var charge_t: float = clampf(p._exec_ball_hold_time / 1.5, 0.0, 1.0)
	var speed: float = lerpf(p.ball_cfg("throw_speed", EXEC_BALL_THROW_SPEED), p.ball_cfg("max_throw_speed", EXEC_BALL_MAX_THROW_SPEED), charge_t)
	p._exec_ball_vel = aim * speed
	p._exec_ball_pos = p.global_position + aim * 20.0
	DebugOverlay.log("executioner/throw", p,
		"ACTUAL THROW: aim=(%.2f,%.2f) speed=%.0f vel=(%.0f,%.0f) hold=%.2f charge_t=%.2f step=%d mode=%s",
		[aim.x, aim.y, speed, p._exec_ball_vel.x, p._exec_ball_vel.y, p._exec_ball_hold_time, charge_t,
		 p._exec_throw_step, EXEC_CHAIN_MODE_NAMES[p._exec_chain_mode]])
	p._exec_ball_state = ExecEndState.THROWN
	p._exec_ball_anchor_body = null
	p._exec_chain_clank_timer = 0.0
	p._exec_chain_taut = false

	# Decide whether to hold (spawn chain) or release (no chain, ball flies free)
	var should_hold: bool = exec_should_hold_on_throw()
	if should_hold:
		exec_spawn_chain()
	else:
		# RELEASE mode: B-S flies as a connected pair. Shackle gets dragged behind.
		p._exec_shackle_pos = p.global_position + aim * 10.0
		p._exec_shackle_vel = aim * speed * 0.05  # Shackle is light — barely launches, gets dragged
		p._exec_shackle_state = ExecEndState.THROWN
		exec_spawn_ball_to_shackle_chain()
		p._exec_throw_step = 2  # Both ends deployed — no more throws
		DebugOverlay.log("executioner/throw", p, "B-S RELEASED: ball + shackle flying free")

	if p._exec_throw_step < 2:
		p._exec_throw_step += 1
	AudioManager.play("grapple_throw", 2.0, 0.5)
	p._rumble(0.4, 0.7, 0.15)
	DebugOverlay.log("executioner/throw", p, "BALL THROWN: speed=%.0f step=%d hold=%s",
		[speed, p._exec_throw_step, str(should_hold)])


func exec_throw_shackle() -> void:
	var aim: Vector2 = p._get_aim_direction_analog()
	var charge_t: float = clampf(p._exec_shackle_hold_time / 1.0, 0.0, 1.0)
	var speed: float = lerpf(EXEC_SHACKLE_THROW_SPEED, EXEC_SHACKLE_MAX_THROW_SPEED, charge_t)
	p._exec_shackle_vel = aim * speed
	p._exec_shackle_pos = p.global_position + aim * 15.0
	p._exec_shackle_state = ExecEndState.THROWN
	p._exec_shackle_anchor_body = null
	p._exec_shackle_chain_taut = false

	var should_hold: bool = exec_should_hold_on_throw()
	if should_hold:
		exec_spawn_shackle_chain()
	else:
		# RELEASE mode: S-B flies as a connected pair. Ball gets dragged behind.
		p._exec_ball_pos = p.global_position + aim * 10.0
		p._exec_ball_vel = aim * speed * 0.3  # Ball trails behind shackle
		p._exec_ball_state = ExecEndState.THROWN
		exec_spawn_ball_to_shackle_chain()
		p._exec_throw_step = 2  # Both ends deployed
		DebugOverlay.log("executioner/throw", p, "S-B RELEASED: shackle + ball flying free")

	if p._exec_throw_step < 2:
		p._exec_throw_step += 1
	AudioManager.play("grapple_throw", 0.0, 0.8)
	p._rumble(0.3, 0.5, 0.1)
	DebugOverlay.log("executioner/throw", p, "SHACKLE THROWN: speed=%.0f step=%d hold=%s",
		[speed, p._exec_throw_step, str(should_hold)])


func exec_retract_all() -> void:
	p._exec_ball_state = ExecEndState.RETRACTING
	p._exec_shackle_state = ExecEndState.RETRACTING
	p._exec_throw_step = 0
	# Destroy both chain nodes
	if p._exec_chain_node and is_instance_valid(p._exec_chain_node):
		p._exec_chain_node.queue_free()
		p._exec_chain_node = null
	if p._exec_shackle_chain_node and is_instance_valid(p._exec_shackle_chain_node):
		p._exec_shackle_chain_node.queue_free()
		p._exec_shackle_chain_node = null
	DebugOverlay.log("executioner/throw", p, "RETRACT ALL")


func exec_tick_ball(delta: float) -> void:
	match p._exec_ball_state:
		ExecEndState.HELD, ExecEndState.WINDUP:
			pass
		ExecEndState.THROWN:
			# Pure gravity — no air drag. Ball freefalls like a heavy object.
			p._exec_ball_vel.y += p.ball_cfg("gravity", EXEC_BALL_GRAVITY) * delta
			var prev_pos: Vector2 = p._exec_ball_pos
			p._exec_ball_pos += p._exec_ball_vel * delta

			# RIGID chain constraint + YEET physics.
			# The chain is a rigid rod. When the ball reaches max length, momentum
			# transfers along the chain as tension (partially elastic collision).
			#
			# Physics model (1D elastic collision along chain axis):
			#   chain_dir = unit vector from player → ball (direction of tension)
			#   v_b = ball p.velocity component along chain_dir
			#   v_p = player p.velocity component along chain_dir
			#   m_b = EXEC_BALL_MASS (absolute p.mass of spike ball)
			#   m_p = 1.0
			#   e = EXEC_CHAIN_ELASTICITY (0.75 = 75% elastic)
			#
			#   v_p' = v_p + (1+e) * m_b/(m_b+m_p) * (v_b - v_p)
			#   v_b' = v_b - (1+e) * m_p/(m_b+m_p) * (v_b - v_p)
			#
			# The player gets YEETED in the chain direction. With m_b=8, e=0.75:
			#   coefficient = 1.75 * 8/9 = 1.556 — player gets 155% of the
			#   relative p.velocity slammed into them along the chain vector.
			# Chain constraint — only if ball has a chain attached
			var has_ball_chain: bool = p._exec_chain_node and is_instance_valid(p._exec_chain_node)
			# Detect B-S chain (RELEASE mode): both anchors are wall anchors, no player
			var is_bs_chain: bool = has_ball_chain and p._exec_chain_node.anchor_a.get("is_wall", false)
			# Unified chain constraint for ALL modes: B-P, B-E, and B-S.
			# is_bs_chain is used only for anchor updates, not physics branching.
			# In B-S mode with attached entity, exec_is_entity_yeet_mode() returns
			# true, so _exec_try_yeet uses entity p.mass. Same code path as B-E.
			if has_ball_chain:
				# Player↔Ball, Entity↔Ball, or B-S Ball↔Shackle — apply constraint + YEET
				var chain_anchor_pos: Vector2
				var chain_max: float
				if is_bs_chain:
					# B-S: anchor is the shackle (or the entity it's attached to)
					chain_anchor_pos = p._exec_shackle_pos
					chain_max = p.cfg("exec_chain_total_len", EXEC_CHAIN_TOTAL_LEN)
				elif exec_is_entity_yeet_mode():
					# B-E: anchor is the shackled entity
					chain_anchor_pos = p._exec_shackle_anchor_body.global_position + p._exec_shackle_anchor_offset
					chain_max = p.cfg("exec_chain_total_len", EXEC_CHAIN_TOTAL_LEN)
				else:
					# B-P: anchor is the player
					chain_anchor_pos = p.global_position
					chain_max = exec_ball_chain_len()
				var chain_vec: Vector2 = p._exec_ball_pos - chain_anchor_pos
				var chain_dist: float = chain_vec.length()
				if chain_dist > chain_max:
					var chain_dir: Vector2 = chain_vec.normalized()
					var overshoot: float = chain_dist - chain_max
					if is_bs_chain:
						# B-S: p.mass-weighted constraint — heavy ball barely slows, light shackle gets yanked
						var m_ball_bs: float = p.ball_cfg("p.mass", EXEC_BALL_MASS)
						var m_shackle_bs: float = p._shackle.cfg("p.mass", 5.0) if p._shackle else 5.0
						var total_mass_bs: float = m_ball_bs + m_shackle_bs
						var ball_frac: float = m_shackle_bs / total_mass_bs   # How much ball moves (small: 5/145 ≈ 3%)
						var shackle_frac: float = m_ball_bs / total_mass_bs   # How much shackle moves (large: 140/145 ≈ 97%)
						# Position correction: distribute overshoot by inverse p.mass
						p._exec_ball_pos -= chain_dir * overshoot * ball_frac
						p._exec_shackle_pos += chain_dir * overshoot * shackle_frac
						# Elastic collision (YEET) — once per slack→taut transition
						if not p._exec_chain_taut:
							p._exec_chain_taut = true
							var e_bs: float = p._shackle.cfg("chain_elasticity", 0.25) if p._shackle else 0.25
							var v_b: float = p._exec_ball_vel.dot(chain_dir)
							var v_s: float = p._exec_shackle_vel.dot(chain_dir)
							var relative_v: float = v_b - v_s
							if absf(relative_v) > 10.0:
								var imp_to_shackle: float = (1.0 + e_bs) * m_ball_bs / total_mass_bs * relative_v
								var imp_to_ball: float = (1.0 + e_bs) * m_shackle_bs / total_mass_bs * relative_v
								p._exec_shackle_vel += chain_dir * imp_to_shackle
								p._exec_ball_vel -= chain_dir * imp_to_ball
								p._shackle._settled = false  # Wake shackle from settlement
								p._shackle._bounce_count = 0
								DebugOverlay.log("executioner/ball", p,
									"B-S YEET: ball_imp=%.0f shackle_imp=%.0f rel_v=%.0f m_b=%.0f m_s=%.0f",
									[imp_to_ball, imp_to_shackle, relative_v, m_ball_bs, m_shackle_bs])
						else:
							# Already taut: project out outward p.velocity components (p.mass-weighted)
							var v_b_out: float = p._exec_ball_vel.dot(chain_dir)
							if v_b_out > 0.0:
								p._exec_ball_vel -= chain_dir * v_b_out * ball_frac
							var v_s_out: float = p._exec_shackle_vel.dot(-chain_dir)
							if v_s_out > 0.0:
								p._exec_shackle_vel -= (-chain_dir) * v_s_out * shackle_frac
					else:
						# B-P / B-E: ball clamped to anchor, player/entity gets YEETed
						p._exec_ball_pos = chain_anchor_pos + chain_dir * chain_max
						exec_try_yeet(chain_dir)
						var outward_v: float = p._exec_ball_vel.dot(chain_dir)
						if outward_v > 0.0:
							p._exec_ball_vel -= chain_dir * outward_v
				else:
					p._exec_chain_taut = false

				# Chain clanking sound as links flow out during throw
				if chain_dist < chain_max * 0.95:
					p._exec_chain_clank_timer -= delta
					if p._exec_chain_clank_timer <= 0.0:
						p._exec_chain_clank_timer = EXEC_CHAIN_CLANK_INTERVAL
						AudioManager.play("grapple_hit", -12.0, randf_range(1.2, 1.8))

			# Raycast for collision with world and enemies
			var space = p.get_world_2d().direct_space_state
			var query := PhysicsRayQueryParameters2D.create(prev_pos, p._exec_ball_pos, 1 | 8)
			query.exclude = [p.get_rid()]
			var result: Dictionary = space.intersect_ray(query)
			if result:
				p._exec_ball_pos = result["position"]
				var collider: Node = result["collider"]
				var normal: Vector2 = result["normal"]
				# Damage + stun on enemy hit (same stagger as chain-yank on monster)
				if collider.has_method("take_damage"):
					collider.take_damage(int(p.ball_cfg("damage", EXEC_BALL_DAMAGE)), p.player_index)
					p._spawn_blood_particles(result["position"])
				var EntityEffects := preload("res://scripts/systems/entity_effects.gd")
				EntityEffects.apply(collider, "stun", p.ball_cfg("stun_duration", EXEC_BALL_STUN_DURATION))
				if collider.has_method("apply_stun"):
					collider.apply_stun(p.ball_cfg("stun_duration", EXEC_BALL_STUN_DURATION))
				elif collider.has_method("apply_slow"):
					collider.apply_slow(p.ball_cfg("stun_duration", EXEC_BALL_STUN_DURATION))
				DebugOverlay.log("executioner/ball", p, "BALL HIT: target=%s stunned=%.1fs",
					[collider.name, p.ball_cfg("stun_duration", EXEC_BALL_STUN_DURATION)])

				# Determine surface type by normal direction
				if collider is Node2D:
					p._exec_ball_anchor_body = collider
					p._exec_ball_anchor_offset = result["position"] - collider.global_position

				if normal.y > 0.7:
					# Ceiling hit — ball cannot stick, drags out and falls
					p._exec_ball_state = ExecEndState.STUCK_CEILING
					DebugOverlay.log("executioner/ball", p,
						"BALL HIT CEILING — will drag out and fall")
				elif absf(normal.x) > 0.7:
					# Wall hit — sticks, drags slowly downward
					p._exec_ball_state = ExecEndState.STUCK_WALL
				else:
					# Floor/platform hit — sticks, drags slowly if pulled
					p._exec_ball_state = ExecEndState.STUCK_PLATFORM

				AudioManager.play("grapple_hit", 2.0, 0.4)
				p._rumble(0.8, 1.0, 0.25)
				p._exec_ball_vel = Vector2.ZERO

			# Update chain anchor while in flight
			exec_update_chain_ball_anchor()

		ExecEndState.STUCK_WALL:
			# Ball drags slowly down the wall under its own weight
			var prev_wall_y: float = p._exec_ball_pos.y
			p._exec_ball_pos.y += p.ball_cfg("wall_drag", EXEC_BALL_WALL_DRAG) * delta
			if p._exec_ball_anchor_body and is_instance_valid(p._exec_ball_anchor_body):
				p._exec_ball_anchor_offset.y += p.ball_cfg("wall_drag", EXEC_BALL_WALL_DRAG) * delta
				p._exec_ball_pos = p._exec_ball_anchor_body.global_position + p._exec_ball_anchor_offset
			# Floor check — if ball slides down past a floor, transition to STUCK_PLATFORM
			var wall_space = p.get_world_2d().direct_space_state
			if wall_space:
				var wall_query := PhysicsRayQueryParameters2D.create(
					Vector2(p._exec_ball_pos.x, prev_wall_y),
					Vector2(p._exec_ball_pos.x, p._exec_ball_pos.y + 4.0), 1)
				wall_query.exclude = [p.get_rid()]
				var wall_result: Dictionary = wall_space.intersect_ray(wall_query)
				if wall_result and wall_result["normal"].y < -0.5:
					p._exec_ball_pos.y = wall_result["position"].y
					p._exec_ball_anchor_body = wall_result["collider"] if wall_result["collider"] is Node2D else null
					if p._exec_ball_anchor_body:
						p._exec_ball_anchor_offset = p._exec_ball_pos - p._exec_ball_anchor_body.global_position
					p._exec_ball_state = ExecEndState.STUCK_PLATFORM
					DebugOverlay.log("executioner/ball", p,
						"BALL SLID OFF WALL → STUCK_PLATFORM at y=%.0f", [p._exec_ball_pos.y])
			# Chain tension — resolve anchor: shackle in B-S, player otherwise
			var bw_anchor: Vector2 = exec_stuck_chain_anchor()
			var bw_len: float = exec_stuck_chain_max()
			var bw_vec: Vector2 = p._exec_ball_pos - bw_anchor
			var bw_dist: float = bw_vec.length()
			if bw_dist > bw_len:
				var bw_dir: Vector2 = bw_vec / bw_dist
				var bw_over: float = bw_dist - bw_len
				if exec_is_bs_release():
					# B-S: p.mass-weighted — yank shackle, barely move ball
					exec_bs_stuck_pull(bw_dir, bw_over, delta)
				else:
					# B-P: drag ball toward player, tug player toward ball
					var ball_pull: float = bw_over * 8.0
					p._exec_ball_pos -= bw_dir * ball_pull * delta
					if p._exec_ball_anchor_body and is_instance_valid(p._exec_ball_anchor_body):
						p._exec_ball_anchor_offset -= bw_dir * ball_pull * delta
					p.velocity += bw_dir * minf(bw_over * 3.0, 300.0) * delta
				# If dragged far enough, pop off wall → freefall
				if bw_over > 30.0 and not exec_is_bs_release():
					p._exec_ball_state = ExecEndState.THROWN
					p._exec_ball_vel = -bw_dir * 100.0
					p._exec_ball_anchor_body = null
					DebugOverlay.log("executioner/ball", p, "BALL PULLED OFF WALL by chain")
			exec_update_chain_ball_anchor()

		ExecEndState.STUCK_PLATFORM:
			var bp_anchor: Vector2 = exec_stuck_chain_anchor()
			var bp_len: float = exec_stuck_chain_max()
			var bp_vec: Vector2 = p._exec_ball_pos - bp_anchor
			var bp_dist: float = bp_vec.length()
			if exec_is_bs_release():
				# B-S: ball stays stuck, shackle gets yanked if too far
				if bp_dist > bp_len:
					var bp_dir: Vector2 = bp_vec / bp_dist
					var bp_over: float = bp_dist - bp_len
					exec_bs_stuck_pull(bp_dir, bp_over, delta)
			else:
				# B-P: drag ball along platform, tug player
				if bp_dist > bp_len * 0.8:
					var bp_dir: Vector2 = bp_vec / bp_dist
					var bp_over: float = bp_dist - bp_len * 0.8
					var plat_pull: float = bp_over * 6.0
					p._exec_ball_pos -= bp_dir * plat_pull * delta
					if p._exec_ball_anchor_body and is_instance_valid(p._exec_ball_anchor_body):
						p._exec_ball_anchor_offset -= bp_dir * plat_pull * delta
				if bp_dist > bp_len:
					var bp_dir2: Vector2 = bp_vec / bp_dist
					var bp_over2: float = bp_dist - bp_len
					p.velocity += bp_dir2 * minf(bp_over2 * 3.0, 300.0) * delta
					if bp_over2 > 30.0:
						p._exec_ball_state = ExecEndState.THROWN
						p._exec_ball_vel = -bp_dir2 * 100.0
						p._exec_ball_anchor_body = null
						DebugOverlay.log("executioner/ball", p, "BALL PULLED OFF PLATFORM by chain")
			exec_update_chain_ball_anchor()

		ExecEndState.STUCK_CEILING:
			# Ball is in ceiling — drags out quickly and then freefalls
			p._exec_ball_pos.y += p.ball_cfg("ceiling_drag", EXEC_BALL_CEILING_DRAG) * delta
			if p._exec_ball_anchor_body and is_instance_valid(p._exec_ball_anchor_body):
				p._exec_ball_anchor_offset.y += p.ball_cfg("ceiling_drag", EXEC_BALL_CEILING_DRAG) * delta
				p._exec_ball_pos = p._exec_ball_anchor_body.global_position + p._exec_ball_anchor_offset
			# After dragging ~10px out, the ball pops free and freefalls
			# Check if we've moved far enough from impact to consider it "popped out"
			p._exec_ball_vel.y += p.ball_cfg("gravity", EXEC_BALL_GRAVITY) * delta * 0.3  # Partial gravity while dragging
			if p._exec_ball_vel.y > 50.0:
				# Ball has popped free — back to THROWN state (freefall with chain constraint)
				p._exec_ball_state = ExecEndState.THROWN
				p._exec_ball_vel = Vector2(0, 100.0)  # Falls downward
				p._exec_ball_anchor_body = null
				DebugOverlay.log("executioner/ball", p, "BALL FELL FROM CEILING")
			exec_update_chain_ball_anchor()

		ExecEndState.RETRACTING:
			var to_player: Vector2 = p.global_position - p._exec_ball_pos
			if to_player.length() < 20.0:
				p._exec_ball_state = ExecEndState.HELD
			else:
				p._exec_ball_pos += to_player.normalized() * 600.0 * delta



# -- Drawing (migrated from player_side.gd) ------------------------------------

func draw_executioner() -> void:
	if p.character_class != PlayerManager.CharacterClass.EXECUTIONER:
		return
	# Chain is drawn by chain.gd itself (real splay-chain physics)
	draw_exec_ball()
	draw_exec_shackle()
	draw_exec_trajectory_preview()
	if p._exec_swing_active:
		draw_exec_swing()
	draw_exec_chain_mode_indicator()
	if p._exec_cleave_charging:
		draw_exec_cleave_charge()
	if p._exec_cleave_flash_timer > 0.0:
		p.draw_circle(Vector2.ZERO, EXEC_CLEAVE_RANGE * 1.5, Color(1, 1, 1, p._exec_cleave_flash_timer / 0.15 * 0.4))
	draw_exec_mode_indicator()
	draw_exec_chain_radius()
	draw_exec_tuning()


func draw_exec_chain_radius() -> void:
	## Dynamic chain radius visualization based on actual runtime state.
	## Shows constraint circles where they actually exist:
	##   - Ball chain held → golden circle around PLAYER (ball can't go beyond)
	##   - Shackle chain held → blue circle around PLAYER (shackle/entity can't go beyond)
	##   - Ball stuck + shackle trailing (B-S) → circle around BALL p.position
	## Also shows static split preview during windup/adjustment.

	var is_winding: bool = p._exec_ball_state == ExecEndState.WINDUP or p._exec_shackle_state == ExecEndState.WINDUP
	var is_adjusting: bool = p._exec_chain_len_changing
	var debug_on: bool = DebugOverlay.should_draw("executioner/chain_radius", p)

	var show_static: bool = is_winding or is_adjusting or p._exec_chain_radius_fade > 0.0
	var static_alpha: float = 0.0
	if is_adjusting:
		static_alpha = 0.5
		p._exec_chain_radius_fade = 0.6
	elif p._exec_chain_radius_fade > 0.0:
		static_alpha = 0.5 * (p._exec_chain_radius_fade / 0.6)
	elif is_winding:
		static_alpha = 0.12

	# -- Static split preview (centered on player, shows potential range) --
	if show_static and static_alpha > 0.01:
		var segments: int = 48
		var ball_len: float = exec_ball_chain_len()
		var shackle_len: float = exec_shackle_chain_len()
		_draw_dashed_circle(Vector2.ZERO, ball_len, Color(0.9, 0.65, 0.2, static_alpha), segments)
		_draw_dashed_circle(Vector2.ZERO, shackle_len, Color(0.4, 0.5, 0.7, static_alpha * 0.8), segments)
		if static_alpha > 0.15:
			var ball_pct: int = int(p._exec_chain_split * 100.0)
			p.draw_string(ThemeDB.fallback_font, Vector2(0, -ball_len - 12),
				"Ball %d%%" % ball_pct, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0.9, 0.65, 0.2, static_alpha))
			p.draw_string(ThemeDB.fallback_font, Vector2(0, -shackle_len - 12),
				"Shackle %d%%" % (100 - ball_pct), HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0.4, 0.5, 0.7, static_alpha))

	if not debug_on:
		return

	# -- Dynamic runtime constraint circles (only when debug aspect is on) --
	var font: Font = ThemeDB.fallback_font
	var segments_d: int = 48

	# Ball chain: if ball is out and has a chain connected to player
	var has_ball_chain: bool = p._exec_chain_node and is_instance_valid(p._exec_chain_node)
	var ball_is_held: bool = has_ball_chain and not p._exec_chain_node.anchor_a.get("is_wall", false)
	if ball_is_held and p._exec_ball_state in [ExecEndState.THROWN, ExecEndState.STUCK_WALL, ExecEndState.STUCK_PLATFORM, ExecEndState.STUCK_CEILING]:
		var ball_len: float = exec_ball_chain_len()
		_draw_dashed_circle(Vector2.ZERO, ball_len, Color(0.9, 0.65, 0.2, 0.4), segments_d, 2.0)
		p.draw_string(font, Vector2(ball_len + 4, 4), "Ball %.0f" % ball_len, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.9, 0.65, 0.2, 0.6))
		# Log distance
		var ball_dist: float = (p._exec_ball_pos - p.global_position).length()
		DebugOverlay.log("executioner/chain_radius", p,
			"BALL CHAIN: len=%.0f dist=%.0f %s",
			[ball_len, ball_dist, "OK" if ball_dist <= ball_len + 5 else "BREACH!"])

	# Shackle chain: if shackle is out and has a chain connected to player
	var has_shackle_chain: bool = p._exec_shackle_chain_node and is_instance_valid(p._exec_shackle_chain_node)
	if has_shackle_chain and p._exec_shackle_state in [ExecEndState.THROWN, ExecEndState.ATTACHED_ENEMY]:
		var shackle_len: float = exec_shackle_chain_len()
		_draw_dashed_circle(Vector2.ZERO, shackle_len, Color(0.3, 0.6, 1.0, 0.5), segments_d, 2.0)
		p.draw_string(font, Vector2(shackle_len + 4, 16), "Shackle %.0f" % shackle_len, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.3, 0.6, 1.0, 0.6))
		var shackle_dist: float = (p._exec_shackle_pos - p.global_position).length()
		DebugOverlay.log("executioner/chain_radius", p,
			"SHACKLE CHAIN: len=%.0f dist=%.0f entity=%s %s",
			[shackle_len, shackle_dist,
			 p._exec_shackle_anchor_body.name if p._exec_shackle_anchor_body and is_instance_valid(p._exec_shackle_anchor_body) else "none",
			 "OK" if shackle_dist <= shackle_len + 5 else "BREACH!"])

	# B-S mode: ball stuck somewhere, shackle trailing — show total chain radius around ball
	if has_ball_chain and p._exec_chain_node.anchor_a.get("is_wall", false):
		var total_len: float = p.cfg("exec_chain_total_len", EXEC_CHAIN_TOTAL_LEN)
		var ball_local: Vector2 = p._exec_ball_pos - p.global_position
		_draw_dashed_circle(ball_local, total_len, Color(1.0, 0.4, 0.2, 0.35), segments_d, 1.5)
		p.draw_string(font, ball_local + Vector2(total_len + 4, 4), "B-S %.0f" % total_len, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 0.4, 0.2, 0.5))

	# Shackle attached to entity but NO shackle chain (released) — show as unconnected
	if p._exec_shackle_state == ExecEndState.ATTACHED_ENEMY and not has_shackle_chain:
		var entity_local: Vector2 = p._exec_shackle_pos - p.global_position
		p.draw_string(font, entity_local + Vector2(8, -8), "RELEASED (no chain)", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 0.4, 0.4, 0.7))


func _draw_dashed_circle(center: Vector2, radius: float, color: Color, segments: int = 48, width: float = 1.5) -> void:
	## Draw a dashed circle (every 3rd segment skipped).
	for i in range(segments):
		if i % 3 == 0:
			continue
		var a1: float = float(i) / float(segments) * TAU
		var a2: float = float(i + 1) / float(segments) * TAU
		p.draw_line(center + Vector2(cos(a1), sin(a1)) * radius,
			center + Vector2(cos(a2), sin(a2)) * radius, color, width)


func draw_exec_ball() -> void:
	var ball_local: Vector2 = exec_get_ball_world_pos() - p.global_position
	p.draw_circle(ball_local, EXEC_BALL_RADIUS, Color(0.08, 0.06, 0.06))
	p.draw_circle(ball_local + Vector2(-2, -3), EXEC_BALL_RADIUS * 0.4, Color(0.2, 0.18, 0.18, 0.5))
	for i in range(EXEC_BALL_SPIKE_COUNT):
		var spike_angle: float = p._exec_ball_rotation + float(i) / float(EXEC_BALL_SPIKE_COUNT) * TAU
		var base: Vector2 = ball_local + Vector2(cos(spike_angle), sin(spike_angle)) * EXEC_BALL_RADIUS * 0.8
		var tip: Vector2 = ball_local + Vector2(cos(spike_angle), sin(spike_angle)) * (EXEC_BALL_RADIUS + EXEC_BALL_SPIKE_LEN)
		var perp := Vector2(-sin(spike_angle), cos(spike_angle)) * 2.5
		p.draw_colored_polygon(PackedVector2Array([base - perp, base + perp, tip]), Color(0.12, 0.1, 0.1))
	if p._exec_ball_state == ExecEndState.WINDUP:
		for j in range(5):
			var a: float = p._exec_ball_spin_angle - float(j) * 0.3
			p.draw_circle(Vector2(cos(a), sin(a)) * 25.0, 2.0, Color(0.3, 0.3, 0.3, 0.5 - float(j) * 0.1))


func draw_exec_shackle() -> void:
	var shackle_local: Vector2 = exec_get_shackle_world_pos() - p.global_position
	var chain_col := Color(0.3, 0.28, 0.26, 0.95)
	# Splay-style shackle: solid rectangle cuff (like monster splay chain hardware)
	var hw: float = 5.0
	var hh: float = 3.5
	p.draw_rect(Rect2(shackle_local.x - hw, shackle_local.y - hh, hw * 2, hh * 2), chain_col)
	# Inner dark
	p.draw_rect(Rect2(shackle_local.x - hw + 1, shackle_local.y - hh + 1, hw * 2 - 2, hh * 2 - 2), Color(0.15, 0.12, 0.12))
	# Rivet dots
	p.draw_circle(shackle_local + Vector2(-3, -2), 1.0, chain_col)
	p.draw_circle(shackle_local + Vector2(3, -2), 1.0, chain_col)
	p.draw_circle(shackle_local + Vector2(-3, 2), 1.0, chain_col)
	p.draw_circle(shackle_local + Vector2(3, 2), 1.0, chain_col)
	# Windup trail
	if p._exec_shackle_state == ExecEndState.WINDUP:
		for j in range(5):
			var a: float = p._exec_shackle_spin_angle - float(j) * 0.3
			p.draw_circle(Vector2(cos(a), sin(a)) * 20.0, 1.5, Color(0.4, 0.35, 0.3, 0.4 - float(j) * 0.08))


func draw_exec_trajectory_preview() -> void:
	## Ball arc: probability CONE between optimistic (outer) and pessimistic (inner).
	## Reality always falls within this cone.
	var outer: PackedVector2Array = p._exec_preview_arc
	var inner: PackedVector2Array = p._exec_preview_arc_inner
	if outer.size() >= 2:
		var max_len: int = maxi(outer.size(), inner.size())

		# Draw filled cone between outer and inner arcs
		for i in range(max_len - 1):
			if i % 4 == 3:
				continue  # Tight dashes
			var t: float = float(i) / float(max_len - 1)
			var alpha: float = 0.25 * (1.0 - t * 0.5)
			var oi: int = mini(i, outer.size() - 1)
			var oi2: int = mini(i + 1, outer.size() - 1)
			var ii: int = mini(i, inner.size() - 1)
			var ii2: int = mini(i + 1, inner.size() - 1)
			var o1: Vector2 = outer[oi]
			var o2: Vector2 = outer[oi2]
			var i1: Vector2 = inner[ii]
			var i2: Vector2 = inner[ii2]

			# Fill between the two arcs (cone interior)
			if o1.distance_to(i1) > 2.0:
				p.draw_line(o1, i1, Color(0.8, 0.4, 0.15, alpha * 0.3), 1.0)

			# Outer edge (optimistic) — bright
			p.draw_line(o1, o2, Color(0.8, 0.3, 0.2, alpha), 1.5)

			# Inner edge (pessimistic) — dimmer
			if inner.size() > 1:
				p.draw_line(i1, i2, Color(0.9, 0.6, 0.2, alpha * 0.6), 1.0)

		# Chain taut marker on outer arc
		var ball_len: float = exec_ball_chain_len()
		for i in range(outer.size()):
			if outer[i].length() >= ball_len * 0.95:
				p.draw_circle(outer[i], 5.0, Color(1.0, 0.7, 0.2, 0.4))
				p.draw_circle(outer[i], 2.5, Color(1.0, 0.85, 0.3, 0.8))
				break

		# End points
		var outer_end: Vector2 = outer[outer.size() - 1]
		p.draw_circle(outer_end, 4.0, Color(0.9, 0.4, 0.2, 0.3))
		p.draw_circle(outer_end, 2.0, Color(1.0, 0.6, 0.3, 0.6))
		if inner.size() > 1:
			var inner_end: Vector2 = inner[inner.size() - 1]
			p.draw_circle(inner_end, 3.0, Color(0.9, 0.6, 0.2, 0.2))
			p.draw_circle(inner_end, 1.5, Color(1.0, 0.7, 0.3, 0.4))

	## Shackle arc: NARROW precise line (like monster leap).
	if p._exec_shackle_preview_arc.size() >= 2:
		var s_count: int = p._exec_shackle_preview_arc.size()
		# Solid narrow line
		for i in range(s_count - 1):
			var alpha: float = 0.7 * (1.0 - float(i) / float(s_count) * 0.3)
			p.draw_line(p._exec_shackle_preview_arc[i], p._exec_shackle_preview_arc[i + 1],
				Color(0.4, 0.5, 0.7, alpha), 2.0)
		# Precise landing dot
		var end_pt: Vector2 = p._exec_shackle_preview_arc[s_count - 1]
		p.draw_circle(end_pt, 3.0, Color(0.5, 0.6, 0.8, 0.8))
		p.draw_circle(end_pt, 1.5, Color(0.7, 0.8, 1.0, 1.0))


func draw_exec_swing() -> void:
	var swing_radius := 30.0
	var ball_offset := Vector2(cos(p._exec_swing_angle), sin(p._exec_swing_angle)) * swing_radius
	for i in range(6):
		var trail_angle: float = p._exec_swing_angle - float(i) * 0.25 * (1.0 if p._facing_right else -1.0)
		p.draw_circle(Vector2(cos(trail_angle), sin(trail_angle)) * swing_radius, EXEC_BALL_RADIUS * 0.7,
			Color(0.1, 0.08, 0.08, (1.0 - float(i) / 6.0) * 0.3))
	p.draw_circle(ball_offset, EXEC_BALL_RADIUS, Color(0.08, 0.06, 0.06))
	for j in range(EXEC_BALL_SPIKE_COUNT):
		var spike_a: float = p._exec_ball_rotation + float(j) / float(EXEC_BALL_SPIKE_COUNT) * TAU
		var tip: Vector2 = ball_offset + Vector2(cos(spike_a), sin(spike_a)) * (EXEC_BALL_RADIUS + EXEC_BALL_SPIKE_LEN * 0.7)
		p.draw_line(ball_offset, tip, Color(0.15, 0.12, 0.12), 1.5)
	if p._exec_swing_angular_vel > EXEC_SWING_MAX_SPIN * 0.5:
		var intensity: float = (p._exec_swing_angular_vel - EXEC_SWING_MAX_SPIN * 0.5) / (EXEC_SWING_MAX_SPIN * 0.5)
		for k in range(3):
			var la: float = p._exec_swing_angle + float(k) * TAU / 3.0
			p.draw_line(Vector2(cos(la), sin(la)) * swing_radius * 0.3,
				Vector2(cos(la), sin(la)) * swing_radius * 0.8,
				Color(0.5, 0.5, 0.5, intensity * 0.3), 1.0)


func draw_exec_chain_mode_indicator() -> void:
	## Draw chain mode indicator near the player.
	## STEADY: small icon showing current mode always visible.
	## CHANGE: flash animation when mode just changed.
	var mode_col: Color = EXEC_CHAIN_MODE_COLORS[p._exec_chain_mode]
	var mode_name: String = EXEC_CHAIN_MODE_NAMES[p._exec_chain_mode]

	# Flash alpha when recently changed
	var flash: float = 0.0
	if p._exec_chain_mode_changed_timer > 0.0:
		flash = clampf(p._exec_chain_mode_changed_timer / 1.5, 0.0, 1.0)

	# STEADY indicator: small colored bar under player
	var bar_y: float = 18.0
	var bar_w: float = 24.0
	var steady_alpha: float = 0.4 + flash * 0.4
	p.draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w, 3.0), mode_col * Color(1, 1, 1, steady_alpha))

	# Mode dots: 1, 2, or 3 dots showing which mode
	for i in range(3):
		var dot_x: float = -8.0 + i * 8.0
		var dot_y: float = bar_y + 7.0
		var is_active: bool = (i == p._exec_chain_mode)
		var dot_alpha: float = 0.7 if is_active else 0.15
		if flash > 0.0 and is_active:
			dot_alpha = 1.0
		p.draw_circle(Vector2(dot_x, dot_y), 2.0 if is_active else 1.5,
			mode_col * Color(1, 1, 1, dot_alpha))

	# CHANGE: text label when recently changed
	if flash > 0.2:
		var label_alpha: float = (flash - 0.2) / 0.8
		p.draw_string(ThemeDB.fallback_font, Vector2(-30, bar_y + 20),
			mode_name, HORIZONTAL_ALIGNMENT_CENTER, 60, 9,
			mode_col * Color(1, 1, 1, label_alpha))

		# Ghost animation: show what the throw pattern looks like
		# Release: broken chain icon. Hold: solid chain. Hold+Hold: double chain.
		var ghost_alpha: float = label_alpha * 0.3
		if p._exec_chain_mode == ExecChainMode.RELEASE_RELEASE:
			# Broken chain segments
			p.draw_line(Vector2(-10, bar_y + 28), Vector2(-3, bar_y + 28),
				mode_col * Color(1, 1, 1, ghost_alpha), 2.0)
			p.draw_line(Vector2(3, bar_y + 28), Vector2(10, bar_y + 28),
				mode_col * Color(1, 1, 1, ghost_alpha), 2.0)
		elif p._exec_chain_mode == ExecChainMode.HOLD_RELEASE:
			# Solid chain then broken
			p.draw_line(Vector2(-12, bar_y + 28), Vector2(0, bar_y + 28),
				mode_col * Color(1, 1, 1, ghost_alpha), 2.0)
			p.draw_line(Vector2(4, bar_y + 28), Vector2(8, bar_y + 28),
				mode_col * Color(1, 1, 1, ghost_alpha * 0.5), 1.5)
			p.draw_line(Vector2(10, bar_y + 28), Vector2(14, bar_y + 28),
				mode_col * Color(1, 1, 1, ghost_alpha * 0.3), 1.0)
		elif p._exec_chain_mode == ExecChainMode.HOLD_HOLD:
			# Double solid chain
			p.draw_line(Vector2(-14, bar_y + 28), Vector2(14, bar_y + 28),
				mode_col * Color(1, 1, 1, ghost_alpha), 2.0)
			p.draw_circle(Vector2(0, bar_y + 28), 2.0, mode_col * Color(1, 1, 1, ghost_alpha))


func draw_exec_cleave_charge() -> void:
	var charge_t: float = clampf(p._exec_cleave_charge_time / EXEC_CLEAVE_CHARGE_TIME, 0.0, 1.0)
	var aim: Vector2 = p._get_aim_direction_analog()
	var pulse: float = sin(Time.get_ticks_msec() * 0.01) * 0.2
	var aura_radius: float = lerpf(10.0, 40.0, charge_t)
	p.draw_circle(Vector2.ZERO, aura_radius, Color(0.15, 0.05, 0.05, (0.2 + pulse) * charge_t))
	p.draw_circle(Vector2.ZERO, aura_radius * 0.6, Color(0.3, 0.05, 0.0, (0.3 + pulse) * charge_t))
	var blade_end: Vector2 = aim * lerpf(35.0, 50.0, charge_t)
	p.draw_line(aim * 20.0, blade_end, Color(1.0, 0.8, 0.6, charge_t * 0.8), lerpf(2.0, 4.0, charge_t))
	if charge_t > 0.5:
		for i in range(int(charge_t * 4)):
			p.draw_circle(Vector2(randf_range(-15, 15), randf_range(-15, 15)) * charge_t, 1.5,
				Color(1.0, 0.9, 0.5, randf_range(0.3, 0.7)))


func draw_exec_mode_indicator() -> void:
	# Only show when idle (not thrown)
	if p._exec_ball_state != ExecEndState.HELD and p._exec_shackle_state != ExecEndState.HELD:
		return

	var dir_x: float = 1.0 if p._facing_right else -1.0
	var chain_col := Color(0.3, 0.28, 0.26, 0.7)

	if p._exec_throw_mode == ExecThrowMode.BALL_FIRST:
		# Ball is next throw — show ball dangling in front
		# (already drawn by _draw_exec_ball in HELD state)
		# Small "BALL" label
		pass
	else:
		# Shackle is next throw — show shackle dangling in front with chain links
		var shackle_base := Vector2(dir_x * 18.0, -5.0)
		# A few chain links dangling from hand to shackle
		var link_count: int = 4
		for i in range(link_count):
			var t: float = float(i) / float(link_count)
			var p1 := Vector2(dir_x * (12.0 + i * 5.0), -4.0 + i * 3.0 + sin(Time.get_ticks_msec() * 0.003 + i) * 1.5)
			var p2 := Vector2(dir_x * (12.0 + (i + 1) * 5.0), -4.0 + (i + 1) * 3.0 + sin(Time.get_ticks_msec() * 0.003 + i + 1) * 1.5)
			var width: float = 2.5 if i % 2 == 0 else 1.5
			p.draw_line(p1, p2, chain_col, width)
		# Shackle cuff at the end
		var cuff_pos := Vector2(dir_x * (12.0 + link_count * 5.0), -4.0 + link_count * 3.0 + sin(Time.get_ticks_msec() * 0.003 + link_count) * 1.5)
		p.draw_rect(Rect2(cuff_pos.x - 5, cuff_pos.y - 3.5, 10, 7), chain_col)
		p.draw_rect(Rect2(cuff_pos.x - 4, cuff_pos.y - 2.5, 8, 5), Color(0.15, 0.12, 0.12))
		# Rivet dots
		p.draw_circle(cuff_pos + Vector2(-3, -1.5), 0.8, chain_col)
		p.draw_circle(cuff_pos + Vector2(3, -1.5), 0.8, chain_col)


# -- Tuning Popup (live sliders for ball/chain feel) ---------------------------

# -- Test Throw (virtual input simulation) -------------------------------------

var _exec_test_active: bool = false
var _exec_test_phase: int = 0       # 0=windup, 1=thrown, 2=recording
var _exec_test_timer: float = 0.0
var _exec_test_hold_time: float = 1.5
var _exec_test_aim: Vector2 = Vector2.RIGHT
var _exec_test_predicted: PackedVector2Array = PackedVector2Array()
var _exec_test_actual_ball: PackedVector2Array = PackedVector2Array()
var _exec_test_actual_player: PackedVector2Array = PackedVector2Array()
var _exec_test_record_timer: float = 0.0
var _exec_test_start_pos: Vector2 = Vector2.ZERO  # Player world pos at throw time


func exec_test_throw(angle_deg: float, hold_time: float) -> void:
	## Simulate a throw: virtually hold L1 for hold_time, aim at angle, release.
	## Records predicted vs actual trajectories.
	# Aim: angle_deg upward from horizontal, in the direction the player faces
	var dir_x: float = 1.0 if p._facing_right else -1.0
	_exec_test_aim = Vector2(dir_x * cos(deg_to_rad(angle_deg)), -sin(deg_to_rad(angle_deg)))
	_exec_test_hold_time = hold_time
	_exec_test_predicted.clear()
	_exec_test_actual_ball.clear()
	_exec_test_actual_player.clear()
	_exec_test_record_timer = 0.0

	# Retract and force everything to HELD immediately
	if p._exec_ball_state != ExecEndState.HELD:
		exec_retract_all()
	p._exec_ball_state = ExecEndState.HELD
	p._exec_shackle_state = ExecEndState.HELD
	p._exec_throw_step = 0
	p._exec_ball_vel = Vector2.ZERO

	# Place player at a clean p.position: center of floor
	p.global_position = Vector2(960, 876)
	p.velocity = Vector2.ZERO
	p._exec_ball_pos = p.global_position
	_exec_test_start_pos = p.global_position
	p._facing_right = true  # Always face right for consistent tests

	# Start after a short delay to let state settle
	_exec_test_phase = 0
	_exec_test_timer = -0.2  # Small delay before windup starts
	_exec_test_active = true

	DebugOverlay.log("executioner/throw", p,
		"EXEC TEST: angle=%.0f hold=%.1fs aim=(%.2f,%.2f)",
		[angle_deg, hold_time, _exec_test_aim.x, _exec_test_aim.y])


func exec_test_tick(delta: float) -> void:
	if not _exec_test_active:
		return

	_exec_test_timer += delta

	if _exec_test_phase == 0:
		# Phase 0: Windup — inject L1 pressed + aim direction
		if _exec_test_timer < 0.0:
			return  # Settling delay
		p._controller_actions["grapple"] = true
		if _exec_test_timer <= delta * 2 + 0.2:  # First real frame after delay
			p._controller_just_pressed["grapple"] = true

		# Override aim direction
		if p.device_id >= 0:
			# Can't override stick directly, but the throw code uses p._get_aim_direction_analog
			# which reads the stick. Instead, we'll override p._facing_right and use the
			# aim from the throw function. Actually, let's just set it after windup.
			pass

		if _exec_test_timer >= _exec_test_hold_time:
			# Release — run prediction BEFORE releasing
			var charge_t: float = clampf(_exec_test_hold_time / 1.5, 0.0, 1.0)
			var speed: float = lerpf(
				p.ball_cfg("throw_speed", EXEC_BALL_THROW_SPEED),
				p.ball_cfg("max_throw_speed", EXEC_BALL_MAX_THROW_SPEED), charge_t)
			var launch_vel: Vector2 = _exec_test_aim * speed
			DebugOverlay.log("executioner/throw", p,
				"LAUNCH: vel=(%.1f, %.1f) speed=%.1f", [launch_vel.x, launch_vel.y, speed])

			# Run prediction and save it
			exec_update_preview(launch_vel)
			_exec_test_predicted = p._exec_preview_arc.duplicate()
			DebugOverlay.log("executioner/throw", p,
				"PREDICTED: %d arc points", [_exec_test_predicted.size()])

			# Now release L1 — this triggers the actual throw
			p._controller_actions["grapple"] = false
			_exec_test_phase = 1
			_exec_test_timer = 0.0

	elif _exec_test_phase == 1:
		# Phase 1: Ball is thrown — wait one frame for state to settle
		if _exec_test_timer > 0.05:
			_exec_test_phase = 2
			_exec_test_timer = 0.0
			var start_pos: Vector2 = p.global_position
			DebugOverlay.log("executioner/throw", p,
				"RECORDING: ball_state=%d player_pos=(%.1f, %.1f)", [p._exec_ball_state, start_pos.x, start_pos.y])

	elif _exec_test_phase == 2:
		# Phase 2: Record actual positions every frame
		_exec_test_record_timer += delta
		var ball_local: Vector2 = p._exec_ball_pos - p.global_position
		_exec_test_actual_ball.append(p._exec_ball_pos - p.global_position)
		_exec_test_actual_player.append(Vector2.ZERO)  # Player is always origin in local

		# Compare to prediction at corresponding time
		# Prediction was sampled at dt=0.016, actual at variable delta
		var pred_idx: int = mini(int(_exec_test_record_timer / 0.016), _exec_test_predicted.size() - 1)
		if pred_idx >= 0 and pred_idx < _exec_test_predicted.size():
			var pred_pos: Vector2 = _exec_test_predicted[pred_idx]
			var error: float = ball_local.distance_to(pred_pos)
			if _exec_test_actual_ball.size() % 10 == 0:  # Log every 10 frames
				DebugOverlay.log("executioner/throw", p,
					"t=%.2f actual=(%.0f,%.0f) pred=(%.0f,%.0f) err=%.0f",
					[_exec_test_record_timer, ball_local.x, ball_local.y,
					 pred_pos.x, pred_pos.y, error])

		# Stop after 5 seconds or ball settled
		if _exec_test_timer > 5.0 or p._exec_ball_state == ExecEndState.HELD:
			_exec_test_active = false
			DebugOverlay.log("executioner/throw", p,
				"TEST COMPLETE: %d actual frames, %d predicted points",
				[_exec_test_actual_ball.size(), _exec_test_predicted.size()])
			# Print summary error
			var total_err: float = 0.0
			var count: int = 0
			for i in range(_exec_test_actual_ball.size()):
				var pi: int = mini(int(float(i) * delta / 0.016), _exec_test_predicted.size() - 1)
				if pi >= 0 and pi < _exec_test_predicted.size():
					total_err += _exec_test_actual_ball[i].distance_to(_exec_test_predicted[pi])
					count += 1
			if count > 0:
				DebugOverlay.log("executioner/throw", p,
					"AVG ERROR: %.1f px over %d samples", [total_err / count, count])


func exec_tuning_toggle() -> void:
	## Toggle the tuning popup. Called via RCON: exec_tuning
	p._exec_tuning_visible = not p._exec_tuning_visible
	if p._exec_tuning_visible and p._exec_tuning_provider == null:
		var MCP = load("res://scripts/systems/monster_config.gd")
		p._exec_tuning_provider = MCP.DictProvider.new(p._exec_tuning_data, "exec_tuning")
		p.push_config(p._exec_tuning_provider)
	p.queue_redraw()


func exec_tuning_set(key: String, value: float) -> void:
	## Set a tuning value directly. Called via RCON: exec_set <key> <value>
	if p._exec_tuning_provider == null:
		var MCP = load("res://scripts/systems/monster_config.gd")
		p._exec_tuning_provider = MCP.DictProvider.new(p._exec_tuning_data, "exec_tuning")
		p.push_config(p._exec_tuning_provider)
	p._exec_tuning_data[key] = value
	p.queue_redraw()


func draw_exec_tuning() -> void:
	if not p._exec_tuning_visible:
		return

	# Draw in screen space — fixed p.position top-right of viewport
	var vp_size: Vector2 = p.get_viewport_rect().size
	var cam = get_viewport().get_camera_2d()
	var cam_pos: Vector2 = cam.global_position if cam else vp_size * 0.5
	var zoom: Vector2 = cam.zoom if cam and cam.zoom.x > 0 else Vector2.ONE

	# Panel dimensions
	var panel_w: float = 220.0 / zoom.x
	var row_h: float = 16.0 / zoom.y
	var font_size: int = maxi(int(9.0 / zoom.y), 6)
	var slider_h: float = 8.0 / zoom.y
	var panel_h: float = (EXEC_TUNING_KEYS.size() + 1) * row_h + 8.0 / zoom.y

	# Position: top-right of screen, offset into world coords
	var screen_top_right: Vector2 = cam_pos + Vector2(vp_size.x * 0.5 / zoom.x - panel_w - 10.0 / zoom.x, -vp_size.y * 0.5 / zoom.y + 10.0 / zoom.y)
	var panel_pos: Vector2 = screen_top_right - p.global_position  # Convert to local

	# Background
	p.draw_rect(Rect2(panel_pos, Vector2(panel_w, panel_h)), Color(0.05, 0.04, 0.06, 0.85))
	p.draw_rect(Rect2(panel_pos, Vector2(panel_w, panel_h)), Color(0.3, 0.25, 0.2, 0.5), false, 1.0 / zoom.x)

	# Title
	var x: float = panel_pos.x + 4.0 / zoom.x
	var y: float = panel_pos.y + 4.0 / zoom.y
	p.draw_string(ThemeDB.fallback_font, Vector2(x, y + row_h * 0.8), "Ball & Chain Tuning",
		HORIZONTAL_ALIGNMENT_LEFT, panel_w, font_size + 2, Color(0.9, 0.7, 0.3))
	y += row_h + 2.0 / zoom.y

	# Sliders
	var slider_x: float = panel_pos.x + panel_w * 0.45
	var slider_w: float = panel_w * 0.45
	for entry in EXEC_TUNING_KEYS:
		var key: String = entry[0]
		var label: String = entry[1]
		var default_val: float = entry[2]
		var min_val: float = entry[3]
		var max_val: float = entry[4]

		var current_val: float = p.cfg(key, default_val)
		var t: float = clampf((current_val - min_val) / (max_val - min_val), 0.0, 1.0)

		# Label
		p.draw_string(ThemeDB.fallback_font, Vector2(x, y + row_h * 0.7), label,
			HORIZONTAL_ALIGNMENT_LEFT, panel_w * 0.42, font_size, Color(0.7, 0.7, 0.7))

		# Slider track
		var track_y: float = y + row_h * 0.4
		p.draw_line(Vector2(slider_x, track_y), Vector2(slider_x + slider_w, track_y),
			Color(0.25, 0.22, 0.2), 2.0 / zoom.x)

		# Slider fill
		p.draw_line(Vector2(slider_x, track_y), Vector2(slider_x + slider_w * t, track_y),
			Color(0.8, 0.6, 0.2), 2.0 / zoom.x)

		# Slider handle
		var handle_x: float = slider_x + slider_w * t
		p.draw_circle(Vector2(handle_x, track_y), 3.0 / zoom.x, Color(0.9, 0.7, 0.3))

		# Value text
		var val_text: String = "%.2f" % current_val if max_val <= 2.0 else "%.1f" % current_val
		p.draw_string(ThemeDB.fallback_font, Vector2(slider_x + slider_w + 4.0 / zoom.x, y + row_h * 0.7),
			val_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.5, 0.8, 0.5))

		y += row_h


func exec_tuning_handle_input(event: InputEvent) -> void:
	## Handle mouse clicks/drags on the tuning popup sliders.
	if not p._exec_tuning_visible:
		return
	if not event is InputEventMouseButton and not event is InputEventMouseMotion:
		return

	var vp_size: Vector2 = p.get_viewport_rect().size
	var cam = get_viewport().get_camera_2d()
	var cam_pos: Vector2 = cam.global_position if cam else vp_size * 0.5
	var zoom: Vector2 = cam.zoom if cam and cam.zoom.x > 0 else Vector2.ONE

	var panel_w: float = 220.0 / zoom.x
	var row_h: float = 16.0 / zoom.y
	var screen_top_right: Vector2 = cam_pos + Vector2(vp_size.x * 0.5 / zoom.x - panel_w - 10.0 / zoom.x, -vp_size.y * 0.5 / zoom.y + 10.0 / zoom.y)

	# Mouse in world coords
	var mouse_world: Vector2 = p.get_global_mouse_position()
	var slider_x: float = screen_top_right.x + panel_w * 0.45
	var slider_w: float = panel_w * 0.45
	var y_start: float = screen_top_right.y + row_h + 6.0 / zoom.y

	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			# Check which row was clicked
			for i in range(EXEC_TUNING_KEYS.size()):
				var ry: float = y_start + i * row_h
				if mouse_world.y >= ry and mouse_world.y < ry + row_h:
					if mouse_world.x >= slider_x and mouse_world.x <= slider_x + slider_w:
						p._exec_tuning_dragging = EXEC_TUNING_KEYS[i][0]
						exec_tuning_apply_drag(mouse_world.x, slider_x, slider_w, EXEC_TUNING_KEYS[i])
						break
		elif not event.pressed:
			p._exec_tuning_dragging = ""

	elif event is InputEventMouseMotion and not p._exec_tuning_dragging.is_empty():
		for entry in EXEC_TUNING_KEYS:
			if entry[0] == p._exec_tuning_dragging:
				exec_tuning_apply_drag(mouse_world.x, slider_x, slider_w, entry)
				break


func exec_tuning_apply_drag(mouse_x: float, slider_x: float, slider_w: float, entry: Array) -> void:
	var t: float = clampf((mouse_x - slider_x) / slider_w, 0.0, 1.0)
	var new_val: float = lerpf(entry[3], entry[4], t)
	exec_tuning_set(entry[0], new_val)
	DebugOverlay.log("executioner/ball", p, "TUNING: %s = %.2f", [entry[0], new_val])
