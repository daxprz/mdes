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


# -- Convenience accessor for the player body ---------------------------------
# All executioner code was written referencing `self` as the player.
# This accessor lets moved code use `p.velocity`, `p.global_position`, etc.
# without rewriting every line. New code should use ctx.body directly.

var p: Node2D:
	get: return ctx.body if ctx else null


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
	p._attack_executioner()


func perform_special(_intent: Dictionary) -> void:
	p._special_executioner_cleave()


func perform_charged(charge_ratio: float) -> void:
	p._charged_executioner_overhead(charge_ratio)


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
	return p._exec_shackle_state == p.ExecEndState.ATTACHED_ENEMY and \
		p._exec_shackle_anchor_body and is_instance_valid(p._exec_shackle_anchor_body)

func exec_get_ball_world_pos() -> Vector2:
	match p._exec_ball_state:
		p.ExecEndState.HELD:
			return p.global_position + Vector2(20.0 if p._facing_right else -20.0, -5.0)
		p.ExecEndState.WINDUP:
			return p.global_position + Vector2(cos(p._exec_ball_spin_angle), sin(p._exec_ball_spin_angle)) * 25.0
		_:
			return p._exec_ball_pos

func exec_get_shackle_world_pos() -> Vector2:
	match p._exec_shackle_state:
		p.ExecEndState.HELD:
			return p.global_position + Vector2(-15.0 if p._facing_right else 15.0, 0.0)
		p.ExecEndState.WINDUP:
			return p.global_position + Vector2(cos(p._exec_shackle_spin_angle), sin(p._exec_shackle_spin_angle)) * 20.0
		_:
			return p._exec_shackle_pos
