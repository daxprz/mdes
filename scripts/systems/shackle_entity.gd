extends Node2D

## ShackleEntity — the Executioner's shackle as a proper scene entity.
## Owns its position, velocity, state, config stack, chain node, and physics.
## Appears in the Entities list with configurable properties.
## The player creates this on executioner init; it persists while the player exists.

# -- Constants (defaults — overridable via cfg()) --------------------------------

const THROW_SPEED := 400.0
const MAX_THROW_SPEED := 700.0
const SPIN_SPEED := 8.0
const SPIN_ACCEL := 6.0
const MAX_SPIN := 20.0
const GRAVITY := 600.0
const DRAG := 0.97
const DAMAGE := 15
const SNAP_RANGE := 40.0

const DEFAULT_CONFIG := {
	"mass": 5.0,
	"chain_elasticity": 0.25,
	"gravity": 600.0,
	"drag": 0.97,
}

# -- Entity interface -------------------------------------------------------------

var entity_id: String = "shackle"
var _config_stack: Array = []
var _base_config: Variant = null

# -- State ------------------------------------------------------------------------

enum State { HELD, WINDUP, THROWN, STUCK_WALL, STUCK_PLATFORM, STUCK_CEILING, ATTACHED_ENEMY, RETRACTING }

var state: State = State.HELD
var vel: Vector2 = Vector2.ZERO
var anchor_body: Node2D = null          # Entity we're attached to
var anchor_offset: Vector2 = Vector2.ZERO
var spin_angle: float = 0.0
var angular_vel: float = 0.0
var hold_time: float = 0.0
var chain_node: Node2D = null           # Shackle-side chain (to player)
var chain_taut: bool = false
var preview_arc: PackedVector2Array = PackedVector2Array()

# -- Owner reference --------------------------------------------------------------

var owner_player: Node2D = null         # The Executioner player that owns this shackle


func _ready() -> void:
	add_to_group("entities")  # For @e[...] selectors — NOT "players" to avoid intercepting AI commands
	_init_config()


# -- Config stack (standard entity interface) ------------------------------------

func _init_config() -> void:
	if _base_config != null:
		return
	var MCP = preload("res://scripts/systems/monster_config.gd")
	_base_config = MCP.load_class_defaults("shackle")
	if not _base_config:
		_base_config = MCP.DictProvider.new(DEFAULT_CONFIG, "shackle_defaults")
	_config_stack = [_base_config]


func cfg(key: String, default_val: float) -> float:
	## Resolve a config value from the shackle's config stack.
	var val: float = default_val
	for provider in _config_stack:
		var pval: Variant = provider.get_value(key)
		if pval != null:
			val = float(pval)
			break
	var MCP = preload("res://scripts/systems/monster_config.gd")
	val = MCP.apply_modifiers(_config_stack, key, val)
	return val


func push_config(provider: Variant) -> void:
	_config_stack.insert(0, provider)


func remove_config(provider: Variant) -> void:
	_config_stack.erase(provider)


# -- Chain helpers ---------------------------------------------------------------

func chain_len() -> float:
	## How much chain the shackle side gets (based on owner's split).
	if not owner_player or not is_instance_valid(owner_player):
		return 300.0
	var total: float = owner_player.cfg("exec_chain_total_len", 600.0)
	return total * (1.0 - owner_player._exec_chain_split)


# -- Physics tick ----------------------------------------------------------------

func tick(delta: float) -> void:
	## Main physics tick — called by the owner player's _handle_executioner.
	if not owner_player or not is_instance_valid(owner_player):
		return

	match state:
		State.HELD, State.WINDUP:
			global_position = owner_player.global_position
		State.THROWN:
			_tick_thrown(delta)
		State.ATTACHED_ENEMY:
			_tick_attached(delta)
		State.RETRACTING:
			_tick_retracting(delta)


func _tick_thrown(delta: float) -> void:
	## Shackle in flight — gravity, collision, chain constraint, snap detection.
	vel.y += cfg("gravity", GRAVITY) * delta
	var prev_pos: Vector2 = global_position
	global_position += vel * delta

	# World collision — raycast
	var s_space := get_world_2d().direct_space_state
	if s_space:
		var s_query := PhysicsRayQueryParameters2D.create(prev_pos, global_position, 1)
		s_query.exclude = [owner_player.get_rid()]
		var s_result: Dictionary = s_space.intersect_ray(s_query)
		if s_result:
			var normal: Vector2 = s_result["normal"]
			global_position = s_result["position"] + normal * 2.0
			vel = vel.bounce(normal) * 0.4
			AudioManager.play("grapple_hit", -8.0, 1.5)

	# RIGID chain constraint — if shackle has a chain to player
	var has_chain: bool = chain_node and is_instance_valid(chain_node)
	if has_chain:
		var shackle_len: float = chain_len()
		var chain_vec: Vector2 = global_position - owner_player.global_position
		var chain_dist: float = chain_vec.length()
		if chain_dist > shackle_len:
			var chain_dir: Vector2 = chain_vec.normalized()
			global_position = owner_player.global_position + chain_dir * shackle_len
			var outward_v: float = vel.dot(chain_dir)
			if outward_v > 0.0:
				vel -= chain_dir * outward_v
	else:
		# B-S chain constraint: shackle dragged by ball (RELEASE mode)
		var ball_chain: Node2D = owner_player._exec_chain_node
		var has_bs_chain: bool = ball_chain and is_instance_valid(ball_chain) and \
			ball_chain.anchor_a.get("is_wall", false)
		if has_bs_chain:
			var total_len: float = owner_player.cfg("exec_chain_total_len", 600.0)
			var bs_vec: Vector2 = global_position - owner_player._exec_ball_pos
			var bs_dist: float = bs_vec.length()
			if bs_dist > total_len:
				var bs_dir: Vector2 = bs_vec / bs_dist
				global_position = owner_player._exec_ball_pos + bs_dir * total_len
				var outward_v: float = vel.dot(bs_dir)
				if outward_v > 0.0:
					vel -= bs_dir * outward_v
		else:
			chain_taut = false

	# Snap to enemies
	try_snap_to_enemy()

	# Update chain anchor
	update_chain_anchor()


func _tick_attached(delta: float) -> void:
	## Shackle attached to enemy — track position, enforce chain constraint.
	if anchor_body and is_instance_valid(anchor_body):
		global_position = anchor_body.global_position + anchor_offset

		# Chain constraint on attached entity (leash)
		var has_chain: bool = chain_node and is_instance_valid(chain_node)
		if has_chain:
			var shackle_len: float = chain_len()
			var chain_vec: Vector2 = global_position - owner_player.global_position
			var chain_dist: float = chain_vec.length()
			if chain_dist > shackle_len:
				var chain_dir: Vector2 = chain_vec / chain_dist
				var overshoot: float = chain_dist - shackle_len
				# YEET: elastic collision once per taut
				if not chain_taut:
					chain_taut = true
					var m_player: float = owner_player.mass
					var PlayerSide = preload("res://scripts/characters/player_side.gd")
					var m_entity: float = PlayerSide.entity_cfg(anchor_body, "mass", 20.0)
					var e_col: float = owner_player.cfg("exec_chain_elasticity", 0.25)
					var entity_vel: Vector2 = anchor_body.velocity if "velocity" in anchor_body else Vector2.ZERO
					var v_e: float = entity_vel.dot(chain_dir)
					var v_p: float = owner_player.velocity.dot(chain_dir)
					var relative_v: float = v_e - v_p
					if absf(relative_v) > 10.0:
						var impulse_to_player: float = (1.0 + e_col) * m_entity / (m_player + m_entity) * relative_v
						var impulse_to_entity: float = (1.0 + e_col) * m_player / (m_player + m_entity) * relative_v
						owner_player.velocity += chain_dir * impulse_to_player
						if anchor_body.has_method("apply_knockback"):
							anchor_body.apply_knockback(-chain_dir * impulse_to_entity)
						elif "velocity" in anchor_body:
							anchor_body.velocity -= chain_dir * impulse_to_entity
						DebugOverlay.log("executioner/chain_radius", self,
							"SHACKLE YEET: entity_imp=%.0f player_imp=%.0f dist=%.0f len=%.0f",
							[impulse_to_entity, impulse_to_player, chain_dist, shackle_len])
				# Leash: clamp entity to chain boundary (full 2D, not just X)
				var clamped_pos: Vector2 = owner_player.global_position + chain_dir * shackle_len
				anchor_body.global_position = clamped_pos - anchor_offset
				global_position = clamped_pos
				if "velocity" in anchor_body:
					var outward_v: float = anchor_body.velocity.dot(chain_dir)
					if outward_v > 0.0:
						anchor_body.velocity -= chain_dir * outward_v
			else:
				chain_taut = false
	else:
		state = State.RETRACTING
	update_chain_anchor()


func _tick_retracting(delta: float) -> void:
	## Shackle returning to player.
	var to_player: Vector2 = owner_player.global_position - global_position
	if to_player.length() < 20.0:
		state = State.HELD
		if owner_player._exec_ball_state == owner_player.ExecEndState.HELD:
			owner_player._exec_throw_step = 0
		if chain_node and is_instance_valid(chain_node):
			chain_node.queue_free()
			chain_node = null
	else:
		global_position += to_player.normalized() * 700.0 * delta
	update_chain_anchor()


# -- Chain anchor sync -----------------------------------------------------------

func update_chain_anchor() -> void:
	## Keep the chain's anchor in sync with our position.
	if chain_node and is_instance_valid(chain_node) and not chain_node._severed:
		chain_node.anchor_b["pos"] = global_position


# -- Enemy snap detection --------------------------------------------------------

func try_snap_to_enemy() -> bool:
	## Check if the shackle is near any damageable entity. Snaps to hitbox or center.
	var targets: Array = []
	targets.append_array(get_tree().get_nodes_in_group("enemies"))
	targets.append_array(get_tree().get_nodes_in_group("attack_dummies"))
	for p in get_tree().get_nodes_in_group("players"):
		if p != owner_player and p != self and p not in targets:
			targets.append(p)
	for enemy in targets:
		if not enemy is Node2D:
			continue
		# Check hitbox parts if available
		if "_hitboxes" in enemy:
			for part_name in enemy._hitboxes:
				var hitbox: Area2D = enemy._hitboxes[part_name]
				var hitbox_world: Vector2 = enemy.global_position + hitbox.position
				var dist: float = global_position.distance_to(hitbox_world)
				if dist < SNAP_RANGE:
					state = State.ATTACHED_ENEMY
					anchor_body = enemy
					anchor_offset = hitbox.position
					global_position = hitbox_world
					if enemy.has_method("take_damage"):
						enemy.take_damage(DAMAGE, owner_player.player_index if owner_player else -1)
					AudioManager.play("grapple_hit", 2.0, 0.6)
					if owner_player:
						owner_player._rumble(0.6, 0.8, 0.2)
					DebugOverlay.log("executioner/throw", self,
						"SHACKLE ATTACHED: %s/%s", [enemy.name, part_name])
					return true
		else:
			var dist: float = global_position.distance_to(enemy.global_position)
			if dist < SNAP_RANGE:
				state = State.ATTACHED_ENEMY
				anchor_body = enemy
				anchor_offset = Vector2.ZERO
				global_position = enemy.global_position
				if enemy.has_method("take_damage"):
					enemy.take_damage(DAMAGE, owner_player.player_index if owner_player else -1)
				AudioManager.play("grapple_hit", 2.0, 0.6)
				if owner_player:
					owner_player._rumble(0.6, 0.8, 0.2)
				DebugOverlay.log("executioner/throw", self,
					"SHACKLE ATTACHED: %s", [enemy.name])
				return true
	return false


# -- Chain spawning --------------------------------------------------------------

func spawn_chain_to_player() -> void:
	## Create a chain from player to shackle (HOLD mode).
	if chain_node and is_instance_valid(chain_node):
		chain_node.queue_free()
	var ChainScript: GDScript = load("res://scripts/systems/chain.gd")
	chain_node = Node2D.new()
	chain_node.set_script(ChainScript)
	var anchor_a: Dictionary = {"body": owner_player, "body_offset": Vector2.ZERO, "is_wall": false}
	var anchor_b: Dictionary = ChainScript.make_anchor_wall(global_position)
	chain_node.setup(anchor_a, anchor_b, chain_len(), owner_player.player_index if owner_player else -1)
	owner_player.get_parent().add_child(chain_node)
	DebugOverlay.log("executioner/throw", self, "SHACKLE CHAIN: len=%.0f (split=%.0f%%)",
		[chain_len(), (1.0 - owner_player._exec_chain_split) * 100])


# -- Reset -----------------------------------------------------------------------

func reset() -> void:
	## Reset shackle to held state. Destroys chain.
	state = State.HELD
	vel = Vector2.ZERO
	anchor_body = null
	anchor_offset = Vector2.ZERO
	spin_angle = 0.0
	angular_vel = 0.0
	hold_time = 0.0
	chain_taut = false
	preview_arc.clear()
	if owner_player:
		global_position = owner_player.global_position
	if chain_node and is_instance_valid(chain_node):
		chain_node.queue_free()
		chain_node = null
