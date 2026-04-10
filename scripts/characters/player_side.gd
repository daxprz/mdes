extends "res://scripts/characters/character.gd"

## Tower player character (side-scrolling platformer).
## Uses {class}_side.png spritesheets: 192x32, 6 frames at 32x32.
## Frame layout: 0=idle, 1=walk1, 2=walk2, 3=jump, 4=attack1, 5=attack2

const CLASS_SPRITES := {
	PlayerManager.CharacterClass.MELEE: "res://assets/sprites/characters/melee_side.png",
	PlayerManager.CharacterClass.RANGED: "res://assets/sprites/characters/ranged_side.png",
	PlayerManager.CharacterClass.MAGE: "res://assets/sprites/characters/mage_side.png",
	PlayerManager.CharacterClass.SUMMONER: "res://assets/sprites/characters/summoner_side.png",
	PlayerManager.CharacterClass.ROGUE: "res://assets/sprites/characters/rogue_side.png",
	PlayerManager.CharacterClass.DEMOLITIONIST: "res://assets/sprites/characters/demolitionist_side.png",
	PlayerManager.CharacterClass.HEALER: "res://assets/sprites/characters/healer_side.png",
	PlayerManager.CharacterClass.TANK: "res://assets/sprites/characters/tank_side.png",
	PlayerManager.CharacterClass.NINJA: "res://assets/sprites/characters/ninja_side.png",
	PlayerManager.CharacterClass.BALLOONIST: "res://assets/sprites/characters/balloonist_side.png",
	PlayerManager.CharacterClass.GUITARIST: "res://assets/sprites/characters/guitarist_side.png",
	PlayerManager.CharacterClass.WEREWOLF: "res://assets/sprites/characters/werewolf_side.png",
	PlayerManager.CharacterClass.EXECUTIONER: "res://assets/sprites/characters/executioner_side.png",
}

enum AnimFrame { IDLE = 0, WALK1 = 1, WALK2 = 2, JUMP = 3, ATTACK1 = 4, ATTACK2 = 5 }

@export var player_index: int = 0
@export var device_id: int = -1
@export var character_class: PlayerManager.CharacterClass = PlayerManager.CharacterClass.MELEE
## mass: inherited from character.gd (default 70.0)

# -- Config provider stack (same pattern as quadruped_monster) -----------------
var _config_stack: Array = []  # Array[MonsterConfigProvider-compatible]

const CONFIG_BOUNDS := {
	"gravity": Vector2(100, 2000),
	"jump_velocity": Vector2(-1000, -100),
	"speed": Vector2(10, 400),
	"attack_cooldown": Vector2(0.05, 3.0),
	"special_cooldown": Vector2(0.1, 10.0),
	"attack_damage_mult": Vector2(0.1, 5.0),
	"special_damage_mult": Vector2(0.1, 5.0),
	"charge_damage_mult": Vector2(0.1, 5.0),
	"max_health": Vector2(1, 1000),
	"max_mana": Vector2(0, 500),
	"mana_regen": Vector2(0, 20),
	"knockback_mult": Vector2(0, 5.0),
	"melee_combo_window": Vector2(0.1, 2.0),
	"melee_enrage_duration": Vector2(1, 30),
	"melee_enrage_cooldown": Vector2(5, 120),
	"rogue_stealth_duration": Vector2(1, 20),
	"rogue_stealth_cooldown": Vector2(5, 60),
	"rogue_stealth_damage_mult": Vector2(1, 10),
	"ranger_max_arrows": Vector2(1, 50),
	"ranger_reload_time": Vector2(0.1, 5.0),
	"exec_ball_damage": Vector2(1, 200),
	"exec_ball_stun_duration": Vector2(0.5, 10),
	"exec_ball_gravity": Vector2(100, 2000),
	"exec_ball_throw_speed": Vector2(200, 2000),
	"exec_ball_max_throw_speed": Vector2(400, 10000),
	"exec_ball_mass": Vector2(10, 1000),
	"exec_chain_elasticity": Vector2(0, 1.0),
	"exec_chain_total_len": Vector2(200, 1500),
	"exec_chain_split_default": Vector2(0.1, 0.9),
	"exec_chain_adjust_speed": Vector2(0.1, 2.0),
	"exec_swing_max_damage": Vector2(10, 300),
	"exec_swing_slam_radius": Vector2(20, 200),
	"exec_cleave_max_damage": Vector2(10, 500),
	"exec_cleave_charge_time": Vector2(0.5, 5.0),
	"exec_cleave_knockback": Vector2(50, 1000),
}

func cfg(key: String, default_val: float) -> float:
	## Resolve a config value: base override (first non-null) → modifiers → bounds clamp.
	var val: float = default_val
	for provider in _config_stack:
		var pval: Variant = provider.get_value(key)
		if pval != null:
			val = float(pval)
			break
	# Apply modifier providers (multiply, add, min, max, etc.)
	var MCP = preload("res://scripts/systems/monster_config.gd")
	val = MCP.apply_modifiers(_config_stack, key, val)
	if CONFIG_BOUNDS.has(key):
		var bounds: Vector2 = CONFIG_BOUNDS[key]
		val = clampf(val, bounds.x, bounds.y)
	return val

func push_config(provider: Variant) -> void:
	_config_stack.insert(0, provider)

func remove_config(provider: Variant) -> void:
	_config_stack.erase(provider)


# -- Shackle Config Stack -----------------------------------------------------
# The shackle is the "other end" in B-S mode. It has its own config stack so
# modifiers can change its flight characteristics independently.
# Default: nearly massless (mass=5) so the ball barely notices it.
# Push modifiers to make the shackle heavier, bouncier, etc.

func _init_class_config() -> void:
	## Load class defaults from JSON file and push as base config provider.
	var MCP = preload("res://scripts/systems/monster_config.gd")
	var cls_name: String = PlayerHUD.CLASS_NAMES.get(character_class, "").to_lower()
	if cls_name.is_empty():
		return
	var provider = MCP.load_class_defaults(cls_name)
	if provider:
		# Remove any existing class defaults provider (in case of class change)
		for p in _config_stack:
			if "_name" in p and p._name.ends_with("_defaults"):
				_config_stack.erase(p)
				break
		# Push at bottom of stack (lowest priority — base defaults)
		_config_stack.append(provider)


func _init_spikeball_entity() -> void:
	## Create the SpikeBallEntity node — persistent, owns ball config stack.
	if _exec_ball_marker and is_instance_valid(_exec_ball_marker):
		return
	var SpikeScript: GDScript = preload("res://scripts/systems/spikeball_entity.gd")
	_exec_ball_marker = Node2D.new()
	_exec_ball_marker.set_script(SpikeScript)
	_exec_ball_marker.owner_player = self
	_exec_ball_marker.entity_id = "spikeball"
	_exec_ball_marker.name = "spikeball"
	add_child(_exec_ball_marker)
	_exec_ball_marker.top_level = true
	_exec_ball_marker.global_position = global_position


func ball_cfg(key: String, default_val: float) -> float:
	## Query the spike ball's config stack. Keys have no prefix (mass, gravity, etc.)
	if _exec_ball_marker and is_instance_valid(_exec_ball_marker) and _exec_ball_marker.has_method("cfg"):
		return _exec_ball_marker.cfg(key, default_val)
	return default_val


func _init_shackle_entity() -> void:
	## Create the ShackleEntity node if it doesn't exist.
	if _shackle and is_instance_valid(_shackle):
		return
	var ShackleScript: GDScript = preload("res://scripts/systems/shackle_entity.gd")
	_shackle = Node2D.new()
	_shackle.set_script(ShackleScript)
	_shackle.owner_player = self
	_shackle.entity_id = "shackle"
	_shackle.name = "shackle"
	add_child(_shackle)
	_shackle.top_level = true
	_shackle.global_position = global_position

func shackle_cfg(key: String, default_val: float) -> float:
	## Delegate to shackle entity's cfg().
	if _shackle and is_instance_valid(_shackle):
		return _shackle.cfg(key, default_val)
	return default_val

func push_shackle_config(provider: Variant) -> void:
	if _shackle and is_instance_valid(_shackle):
		_shackle.push_config(provider)

func remove_shackle_config(provider: Variant) -> void:
	if _shackle and is_instance_valid(_shackle):
		_shackle.remove_config(provider)


# Jump height = v^2 / (2*g). With v=550, g=900: max height ~168px
const GRAVITY := 900.0
const JUMP_VELOCITY := -550.0
const WALL_JUMP_VELOCITY := Vector2(250.0, -480.0)
const WALK_ANIM_FPS := 8.0
const ATTACK_DURATION := 0.3
const ATTACK_COOLDOWN_TIME := 0.4
const SPECIAL_COOLDOWN_TIME := 1.5

## _facing_right: inherited from character.gd (default true)
var _walk_timer: float = 0.0
var _walk_frame_toggle: bool = false
var _is_attacking: bool = false
var _attack_timer: float = 0.0
var _attack_cooldown: float = 0.0
var _special_cooldown: float = 0.0
## _is_wall_sliding: inherited from character.gd
var _wall_jump_stamina: int = 3
const WALL_JUMP_STAMINA_MAX: int = 3
var _donut_buddy_count: int = 0
var _shadow_dash_active: bool = false
var _hud_aura_fade: float = 0.0  # Grapple aura HUD fade
var _tank_fortify: bool = false
var _balloonist_floating: bool = false   # Tank fortify state (shared with healer)
var _healer_gust_cooldown: float = 0.0
const HEALER_GUST_COOLDOWN := 8.0
const HEALER_GUST_RADIUS := 120.0
const HEALER_GUST_FORCE := 400.0
## _is_dead: inherited from character.gd

# Melee combo system
var _combo_count: int = 0
var _combo_timer: float = 0.0
const COMBO_WINDOW := 0.6  # Seconds to chain next hit
const COMBO_DAMAGES := [30, 40, 55]
const COMBO_RANGES := [28.0, 31.0, 39.0]  # Buffed ~40% from [20, 22, 28]
const COMBO_SWING_COLORS: Array[Color] = [
	Color(1.0, 1.0, 1.0, 0.6),  # hit1 = white
	Color(1.0, 1.0, 0.3, 0.6),  # hit2 = yellow
	Color(1.0, 0.6, 0.1, 0.6),  # hit3 = orange
]
const COMBO_PITCHES: Array[float] = [1.0, 0.9, 0.7]

# Jumper
var _jumper_air_jumps: int = 0
const JUMPER_MAX_AIR_JUMPS := 3  # Triple jump!
const JUMPER_JUMP_VELOCITY := -620.0  # Higher than normal (-550)
var _jumper_dive_active: bool = false
var _jumper_dash_cooldown: float = 0.0
const JUMPER_DASH_COOLDOWN := 0.8
const JUMPER_DASH_SPEED := 500.0
var _jumper_held_item: Node2D = null  # Physical item being carried
var _jumper_pickup_cooldown: float = 0.0
const JUMPER_PICKUP_RANGE := 50.0

# Melee enrage
var _melee_enraged: bool = false
var _melee_enrage_timer: float = 0.0
var _melee_enrage_cooldown: float = 0.0
const MELEE_ENRAGE_DURATION := 10.0
const MELEE_ENRAGE_COOLDOWN := 45.0
const MELEE_ENRAGE_SPEED_MULT := 1.5
const MELEE_ENRAGE_DAMAGE_MULT := 1.8

# Melee ground slam
var _ground_slam_active: bool = false
var _ground_slam_damage := 45
var _revive_progress: float = 0.0
const REVIVE_TIME := 3.0
const REVIVE_RANGE := 60.0

# Charge attack system
var _charge_time: float = 0.0
var _is_charging: bool = false
var _was_pressing_attack: bool = false
var _charge_smoke_timer: float = 0.0
var _charge_hover_time: float = 0.0
var _healer_channel_heal_timer: float = 0.0
var _healer_channel_pulse_timer: float = 0.0
var _healer_channel_ring: ColorRect = null
var _healer_channel_glow: ColorRect = null
const CHARGE_MIN := 0.5
const CHARGE_MAX := 3.0
const HEALER_CHANNEL_HPS := 5.0  # HP per second to nearby allies
const HEALER_CHANNEL_RADIUS := 80.0
const HEALER_CHANNEL_DMG_MULT := 1.25  # 25% more damage taken while channeling
const HEALER_BURST_MIN_HEAL := 10
const HEALER_BURST_MAX_HEAL := 40
const HEALER_BURST_MIN_RADIUS := 60.0
const HEALER_BURST_MAX_RADIUS := 150.0

# Stagger mechanic
# Summoner delegate mode
var _delegate_active: bool = false
var _delegate_node: CharacterBody2D = null
var _delegate_timer: float = 0.0
var _delegate_countdown_label: Label = null
var _delegate_cooldown: float = 0.0
const DELEGATE_SPEED_MULT := 1.5
const DELEGATE_COOLDOWN := 30.0
const DELEGATE_JUMP_MULT := 1.5
const DELEGATE_DMG_MULT := 1.5
const DELEGATE_DURATION := 10.0

var _is_staggered: bool = false
var _stagger_timer: float = 0.0
const STAGGER_DURATION := 1.0
const STAGGER_DAMAGE_MULT := 1.25

# Block / Parry system
var _is_blocking: bool = false
var _block_start_time: float = 0.0
var _block_shield_vfx: ColorRect = null
const PARRY_WINDOW := 0.2  # seconds after block starts where parry is active

# Demolitionist bomb upgrades
var _demo_power_tier: int = 0  # 0-3, +25% damage per tier
var _demo_size_tier: int = 0   # 0-3, +20% radius per tier
var _demo_napalm: bool = false  # Leaves burning ground
var _demo_aspect: String = "none"  # "none", "electric", "fire", "impact", "ice"

# Demolitionist rocket jetpack
# Rogue stealth
var _rogue_stealth: bool = false
var _rogue_stealth_timer: float = 0.0
var _rogue_stealth_cooldown: float = 0.0
const ROGUE_STEALTH_DURATION := 5.0
const ROGUE_STEALTH_COOLDOWN := 20.0
const ROGUE_STEALTH_DAMAGE_MULT := 3.75  # 3.75x damage from stealth (was 2.5)

# Ranger ammo
var _ranger_arrows: int = 10
const RANGER_MAX_ARROWS := 10
const RANGER_RELOAD_TIME := 1.5
var _ranger_reload_timer: float = 0.0
var _ranger_reloading: bool = false

# Physics grappling hook
const GRAPPLE_SWING_RADIUS := 40.0
const GRAPPLE_BASE_ANGULAR_VEL := 14.0  # rad/s
const GRAPPLE_ANGULAR_ACCEL := 12.0  # rad/s²
const GRAPPLE_MAX_ANGULAR_VEL := 35.0  # rad/s
const GRAPPLE_MIN_HOLD := 0.3  # seconds before throw is valid
const GRAPPLE_BASE_THROW_SPEED := 4000.0
const GRAPPLE_THROW_SPEED_PER_SEC := 3000.0
const GRAPPLE_MAX_THROW_SPEED := 10000.0
const GRAPPLE_HOOK_GRAVITY := 400.0
const GRAPPLE_HOOK_DRAG := 0.98
const GRAPPLE_ROPE_SEGMENTS := 20
const GRAPPLE_ROPE_SEGMENT_LEN := 12.0
const GRAPPLE_LAUNCH_SPEED_RATIO := 0.75  # 75% of JUMP_VELOCITY (reduced 70% from 2.5)
const GRAPPLE_PENDULUM_GRAVITY := 600.0
const GRAPPLE_SWING_DAMPING := 0.02
const GRAPPLE_INPUT_BOOST := 1.5  # rad/s² when pushing with swing
const GRAPPLE_INPUT_BRAKE := 1.0
const GRAPPLE_ROPE_ADJUST_SPEED := 80.0
const GRAPPLE_MIN_ROPE_LEN := 30.0
const GRAPPLE_MAX_ROPE_LEN := 900.0
const GRAPPLE_TUG_FORCE := 8000.0
const GRAPPLE_TUG_DURATION := 0.15
const GRAPPLE_HOOK_DAMAGE := 0  # No damage on connection
const GRAPPLE_TUG_DAMAGE := 0
const PLAYER_MASS := 70.0

enum GrappleState { IDLE, WINDUP, THROWN, CONNECTED, SWINGING, TUG, RETRACTING,
					 TETHER_WINDUP, TETHER_THROWN, SLIDE, SLIDE_FREE }
var _grapple_state: GrappleState = GrappleState.IDLE
var _grapple_hold_time: float = 0.0
var _grapple_angle: float = 0.0  # Current windup angle
var _grapple_angular_vel: float = 0.0
var _grapple_hook_pos: Vector2 = Vector2.ZERO  # Hook world position
var _grapple_hook_vel: Vector2 = Vector2.ZERO  # Hook velocity during throw
var _grapple_anchor: Vector2 = Vector2.ZERO  # Anchor point (wall/enemy contact)
var _grapple_anchor_entity: Node2D = null  # If anchored to an enemy
var _grapple_anchor_body: Node2D = null  # The body the hook connected to (for moving platforms)
var _grapple_anchor_offset: Vector2 = Vector2.ZERO  # Local offset from anchor body
var _grapple_rope_len: float = 100.0  # Current rope length
var _grapple_swing_angle: float = 0.0  # Pendulum angle from vertical
var _grapple_swing_vel: float = 0.0  # Pendulum angular velocity
var _grapple_rope_points: Array[Vector2] = []  # Verlet rope segments
var _grapple_retract_timer: float = 0.0
var _grapple_locked_aim: Vector2 = Vector2.RIGHT  # Persists last aim direction
var _grapple_rope_slack: bool = false  # True when player is closer than rope length (rope loose)
var _grapple_pulling: bool = false  # True after first L1 press (pulling toward anchor, still connected)
var _grapple_launch_immunity: float = 0.0  # Seconds where _handle_movement won't override velocity
var _grapple_swing_drove_velocity: bool = false  # True when pendulum set velocity this frame (skip _handle_movement)

# Swing-slide state (Ranger: swing into terrain → slide → jump)
var _slide_velocity: Vector2 = Vector2.ZERO      # Current slide direction + speed
var _slide_surface_normal: Vector2 = Vector2.UP   # Normal of the surface being slid on
var _slide_surface_tangent: Vector2 = Vector2.RIGHT # Tangent direction of slide

# Tether system (dual-grapple)
const TETHER_MAX_COUNT := 5
var _active_tethers: Array = []        # Array of tether Node2D refs (max 5)
var _tether_target_length: float = 0.0 # Length set by D-pad before L2 throw
var _tether_anchor_a: Dictionary = {}  # First anchor (saved when L2 pressed)
var _tether_hook_pos: Vector2 = Vector2.ZERO  # Second hook position during TETHER_THROWN
var _tether_hook_vel: Vector2 = Vector2.ZERO  # Second hook velocity
var _tether_hold_time: float = 0.0     # L2 hold duration for windup
var _tether_angle: float = 0.0         # Second hook spin angle
var _tether_angular_vel: float = 0.0   # Second hook spin speed

var _debug_mode: bool = false  # Toggle with SELECT button
var _debug_tracers: Array = []  # [{pos, vel, predicted, time}]

# Archer aimed shot
const ARCHER_AIM_RETICLE_SPEED := 400.0  # Pixels/s reticle movement
const ARCHER_ARROW_MIN_SPEED := 300.0  # Arrow speed at min pull
const ARCHER_ARROW_MAX_SPEED := 1800.0  # Arrow speed at max pull
const ARCHER_ARROW_SPEED_RATE := 1200.0  # Speed increase per second of hold
const ARCHER_ARROW_GRAVITY := 500.0  # Arrow gravity during flight
const ARCHER_AIM_LOCK_COOLDOWN := 0.25  # Seconds between target-lock recalculations
const ARCHER_AIM_MAX_RANGE := 600.0  # Max reticle distance from player
var _archer_aiming: bool = false
var _archer_aim_hold_time: float = 0.0  # How long L2 has been held (determines pull strength)
var _archer_arrow_speed: float = ARCHER_ARROW_MIN_SPEED  # Current arrow speed based on pull
var _archer_reticle_pos: Vector2 = Vector2.ZERO  # World position of reticle
var _archer_has_solution: bool = false
var _archer_launch_angle: float = 0.0  # Solved launch angle
var _archer_arc_points: Array[Vector2] = []  # Points along the solved arc
var _archer_lock_timer: float = 0.0  # Cooldown between lock recalculations
var _archer_gleam_timer: float = 0.0  # For sparkle animation
var _archer_inactive_timer: float = 0.0  # Time since reticle was last active
var _archer_auto_target: Node2D = null  # Auto-targeted enemy
var _archer_auto_target_cooldown: float = 0.0
var _archer_last_auto_target: Node2D = null  # Track changes for starburst
var _archer_starburst_timer: float = 0.0  # Starburst animation timer
var _archer_fired_this_pull: bool = false  # Re-strings after 0.5s cooldown
var _archer_r2_was_pressed: bool = false  # Track R2 for fresh-press detection
var _archer_power_locked: bool = false  # True when RB released after power-down
var _archer_power_reversing: bool = false  # True while RB held (power decreasing)
var _archer_locked_speed: float = 0.0  # The speed level that was locked
var _archer_debug_trails: Array = []  # [{points, time, color}] for debug arc/arrow trails
var _archer_solved_vx: float = 0.0  # Cached solved velocity for firing
var _archer_solved_vy: float = 0.0

# Mage air-walk
var _mage_airwalk: bool = false
var _mage_airwalk_timer: float = 0.0
var _mage_airwalk_cooldown: float = 0.0
const MAGE_AIRWALK_DURATION := 5.0
const MAGE_AIRWALK_COOLDOWN := 10.0

var _rocket_active: bool = false
var _rocket_fuel: float = 4.0  # seconds of burn time
const ROCKET_FUEL_MAX := 4.0
const ROCKET_THRUST := 800.0  # acceleration per second
const ROCKET_MAX_SPEED := 550.0
var _rocket_can_activate: bool = false  # true after first jump, false on ground
var _rocket_smoke_timer: float = 0.0
var _rocket_flame_timer: float = 0.0
var _rocket_hold_time: float = 0.0
var _rocket_spin_direction: float = 0.0  # +1 or -1, chosen randomly on activation
var _rocket_drift_angle: float = 0.0  # Accumulated rotational drift
var _rocket_out_of_control: bool = false  # Past the point of no return

# Controller state tracking
var _controller_actions: Dictionary = {}
var _controller_just_pressed: Dictionary = {}

# -- AI Input System -----------------------------------------------------------
# An AI controller that drives this player via scripted commands.
# When active, overrides all real input. Commands are queued and processed
# in sequence. Each command runs for a duration, injecting inputs each frame.
#
# Usage via RCON:
#   ai_spawn                        — spawn an AI-controlled player
#   ai_cmd <action> <duration>      — queue a command
#   ai_aim <x> <y>                  — set aim direction
#   ai_seq <cmd1;cmd2;cmd3>         — queue a sequence
#
# Command format: { "actions": ["grapple"], "duration": 1.5, "aim": Vector2 }

var _ai_active: bool = false
var _ai_aim: Vector2 = Vector2(1, 0)         # Current AI aim direction
var _ai_queue: Array = []                     # Array of command dicts
var _ai_current_cmd: Dictionary = {}          # Currently executing command
var _ai_cmd_timer: float = 0.0               # Time remaining on current command
var _ai_cmd_first_frame: bool = false        # True on first frame of a command
var _ai_triggers: Dictionary = {}            # AI-injected trigger state: {"l2": bool, "r2": bool}
var _ai_holds: Dictionary = {}               # Persistent holds: {"l2": true, "r2": true, "jump": true, ...}


func reset_state() -> void:
	## Reset player to default start state. Works for any class.
	## Recalls all projectiles, clears cooldowns, resets velocity.
	velocity = Vector2.ZERO
	_is_attacking = false
	_attack_timer = 0.0
	_attack_cooldown = 0.0
	_special_cooldown = 0.0
	_is_staggered = false
	_is_blocking = false
	_is_charging = false
	_charge_time = 0.0

	# Executioner-specific reset
	if character_class == PlayerManager.CharacterClass.EXECUTIONER:
		_init_shackle_entity()
		_exec_ball_state = ExecEndState.HELD
		if _shackle:
			_shackle.reset()
		_exec_throw_step = 0
		_exec_ball_vel = Vector2.ZERO
		_exec_shackle_vel = Vector2.ZERO
		_exec_ball_pos = global_position
		_exec_shackle_pos = global_position
		# Marker creation deferred to first tick of _handle_executioner
		_exec_swing_active = false
		_exec_cleave_charging = false
		_exec_chain_taut = false
		_exec_shackle_chain_taut = false
		_exec_yeet_immunity = 0.0
		_exec_preview_arc.clear()
		_exec_preview_arc_inner.clear()
		_exec_shackle_preview_arc.clear()
		# Destroy all chain nodes (they're scene children, not player children)
		if _exec_chain_node and is_instance_valid(_exec_chain_node):
			_exec_chain_node.queue_free()
			_exec_chain_node = null
		if _exec_shackle_chain_node and is_instance_valid(_exec_shackle_chain_node):
			_exec_shackle_chain_node.queue_free()
			_exec_shackle_chain_node = null

	# Grapple reset (Ranger)
	_grapple_state = GrappleState.IDLE

	DebugOverlay.log("player/velocity_arrows", self, "RESET STATE")


func ai_set_active(active: bool) -> void:
	_ai_active = active


func ai_set_aim(aim: Vector2) -> void:
	_ai_aim = aim.normalized() if aim.length() > 0.1 else Vector2(1, 0)


func ai_queue_cmd(actions: Array, duration: float, aim: Vector2 = Vector2.ZERO) -> void:
	## Queue a command: hold these actions for this many seconds.
	## If aim is non-zero, override aim direction for this command.
	var cmd: Dictionary = { "actions": actions, "duration": duration }
	if aim != Vector2.ZERO:
		cmd["aim"] = aim
	_ai_queue.append(cmd)


var _ai_holds_new: Dictionary = {}  # Holds that are new THIS frame (for just_pressed)

func ai_set_hold(action: String, held: bool) -> void:
	## Set a persistent button hold. Independent of the command queue.
	## Stays active until explicitly released via ai_set_hold(action, false).
	if held:
		if not _ai_holds.has(action):
			_ai_holds_new[action] = true  # Mark as new for just_pressed trigger
		_ai_holds[action] = true
	else:
		_ai_holds.erase(action)
		# Clear the action from controller state so pressed() returns false
		if action in ["l2", "r2"]:
			_ai_triggers[action] = false
		else:
			_controller_actions[action] = false


func ai_clear() -> void:
	_ai_queue.clear()
	_ai_current_cmd = {}
	_ai_cmd_timer = 0.0
	_ai_holds.clear()
	_ai_holds_new.clear()


func _ai_tick() -> void:
	## Called at the START of _physics_process, before any input is read.
	## Injects actions into _controller_actions / _controller_just_pressed.
	## Two layers: persistent holds (_ai_holds) and queued commands (_ai_queue).
	## Holds are always applied, even when the queue is empty.
	if not _ai_active:
		return

	# Layer 1: Apply persistent holds every frame
	for hold_action in _ai_holds:
		if hold_action == "l2":
			_ai_triggers["l2"] = true
		elif hold_action == "r2":
			_ai_triggers["r2"] = true
		else:
			_controller_actions[hold_action] = true
			# Trigger just_pressed on the first frame a hold is set
			if _ai_holds_new.has(hold_action):
				_controller_just_pressed[hold_action] = true
	_ai_holds_new.clear()

	# Layer 2: Advance queued command (if any)
	if _ai_current_cmd.is_empty():
		if _ai_queue.is_empty():
			return  # No queued work — holds still active above
		_ai_current_cmd = _ai_queue.pop_front()
		_ai_cmd_timer = _ai_current_cmd.get("duration", 0.0)
		_ai_cmd_first_frame = true
		if _ai_current_cmd.has("aim"):
			_ai_aim = _ai_current_cmd["aim"]
	else:
		_ai_cmd_first_frame = false

	# Inject queued command actions
	var actions: Array = _ai_current_cmd.get("actions", [])
	for action in actions:
		if action == "l2":
			_ai_triggers["l2"] = true
		elif action == "r2":
			_ai_triggers["r2"] = true
		else:
			_controller_actions[action] = true
			if _ai_cmd_first_frame:
				_controller_just_pressed[action] = true

	# Tick timer
	_ai_cmd_timer -= get_physics_process_delta_time()
	if _ai_cmd_timer <= 0.0:
		# Command finished — release actions NOT held by persistent holds
		for action in actions:
			if _ai_holds.has(action):
				continue  # Persistent hold keeps this active
			if action == "l2":
				_ai_triggers["l2"] = false
			elif action == "r2":
				_ai_triggers["r2"] = false
			else:
				_controller_actions[action] = false
		_ai_current_cmd = {}

const HEALTH_BAR_SCENE := preload("res://scenes/ui/health_bar.tscn")

@onready var sprite: Sprite2D = $Sprite
@onready var collision_shape: CollisionShape2D = $CollisionShape
@onready var player_label: Label = $PlayerLabel
@onready var attack_area: Area2D = $AttackArea

var _health_bar: Node2D = null
var _mana_bar: Node2D = null


func _ready() -> void:
	add_to_group("players")
	_init_class_dispatch()
	_init_class_config()
	_apply_class_sprite()
	_update_player_label()
	_update_controller_led()
	_setup_health_bar()
	_setup_mana_bar()
	# Load demolitionist upgrades from persistent state
	_demo_aspect = PlayerManager.demo_aspect
	_demo_power_tier = PlayerManager.demo_power_tier
	_demo_size_tier = PlayerManager.demo_size_tier
	_demo_napalm = PlayerManager.demo_napalm
	# Initialize class components
	match character_class:
		PlayerManager.CharacterClass.EXECUTIONER:
			_init_executioner_class()
		PlayerManager.CharacterClass.RANGED:
			_init_ranger_class()
			call_deferred("_init_reticle_pos")
		PlayerManager.CharacterClass.MELEE:
			_init_class_component("melee")
		PlayerManager.CharacterClass.MAGE:
			_init_class_component("mage")
		PlayerManager.CharacterClass.TANK:
			_init_class_component("tank")
		PlayerManager.CharacterClass.BALLOONIST:
			_init_class_component("balloonist")
		PlayerManager.CharacterClass.NINJA:
			_init_class_component("ninja")
		PlayerManager.CharacterClass.ROGUE:
			_init_class_component("rogue")
		PlayerManager.CharacterClass.DEMOLITIONIST:
			_init_class_component("demolitionist")
		PlayerManager.CharacterClass.HEALER:
			_init_class_component("healer")
		PlayerManager.CharacterClass.SUMMONER:
			_init_class_component("summoner")
		PlayerManager.CharacterClass.GUITARIST:
			_init_class_component("guitarist")
		PlayerManager.CharacterClass.WEREWOLF:
			_init_class_component("werewolf")
	# Initialize charge system component
	_charge_comp = preload("res://scripts/components/charge_component.gd").new()
	add_child(_charge_comp)
	_charge_comp.setup(self)
	# Connect level-up signal for VFX and apply existing level bonuses
	PlayerManager.skill_leveled_up.connect(_on_skill_leveled_up)
	ProfileManager.profile_loaded.connect(_on_profile_changed)
	PlayerHUD.class_changed.connect(_on_class_changed_inline)
	PlayerManager.apply_level_bonuses(player_index)


func setup(p_index: int, p_device_id: int, p_class: PlayerManager.CharacterClass) -> void:
	player_index = p_index
	device_id = p_device_id
	character_class = p_class
	if is_inside_tree():
		_apply_class_sprite()
		_update_player_label()


func _draw() -> void:
	_draw_grapple()
	_draw_archer_aim()
	_draw_executioner()
	_draw_hud_popup_indicator()
	_draw_debug()
	# Hitbox: show attack area when active
	if attack_area.monitoring and DebugOverlay.should_draw("hitboxes/player_attack", self):
		var area_pos: Vector2 = attack_area.position
		var atk_shape: CollisionShape2D = attack_area.get_node_or_null("AttackShape")
		if atk_shape and atk_shape.shape is RectangleShape2D:
			var half: Vector2 = (atk_shape.shape as RectangleShape2D).size * 0.5
			var rect := Rect2(area_pos - half, half * 2.0)
			draw_rect(rect, Color(1.0, 0.3, 0.1, 0.35))
			draw_rect(rect, Color(1.0, 0.5, 0.2, 0.7), false, 1.5)


func _apply_class_sprite() -> void:
	if CLASS_SPRITES.has(character_class):
		sprite.texture = load(CLASS_SPRITES[character_class])
	sprite.hframes = 6
	sprite.vframes = 1
	sprite.frame = AnimFrame.IDLE


func _update_player_label() -> void:
	var overall_lv: int = PlayerManager.get_overall_level(player_index)
	var profile: Dictionary = ProfileManager.get_active_profile(player_index)
	if not profile.is_empty():
		var pname: String = profile.get("name", "")
		var class_key: String = str(int(character_class))
		var profile_lv: int = ProfileManager.get_overall_level(profile, class_key)
		# Use the higher of PlayerManager level and profile level
		var display_lv: int = maxi(overall_lv, profile_lv)
		if display_lv > 0:
			player_label.text = pname + " Lv." + str(display_lv)
		else:
			player_label.text = pname
	else:
		if overall_lv > 0:
			player_label.text = "P" + str(player_index + 1) + " Lv." + str(overall_lv)
		else:
			player_label.text = "P" + str(player_index + 1)


func _on_profile_changed(_profile_id: String) -> void:
	_update_player_label()


func _on_class_changed_inline(p_index: int, new_class: PlayerManager.CharacterClass) -> void:
	if p_index != player_index:
		return
	# On title screen, title_screen.gd handles the full respawn + rift
	if GameManager.current_state == GameManager.GameState.TITLE:
		return
	# Update class and sprite in-place (no respawn needed)
	character_class = new_class
	_apply_class_sprite()
	_update_player_label()
	_update_controller_led()

	# Red portal + smoke poof VFX at current position
	_spawn_class_change_vfx()


var _class_change_ghost: bool = false  # True while waiting for player to materialize


func _spawn_class_change_vfx() -> void:
	# Red portal
	var portal := ColorRect.new()
	portal.color = Color(0.9, 0.1, 0.1, 0.8)
	portal.size = Vector2(40, 60)
	portal.position = global_position - Vector2(20, 50)
	portal.z_index = 5
	get_parent().add_child(portal)

	var tween := create_tween()
	tween.tween_property(portal, "scale", Vector2(1.5, 1.5), 0.15)
	tween.parallel().tween_property(portal, "modulate:a", 0.0, 0.5)
	tween.tween_callback(portal.queue_free)

	# Smoke poof
	var poof := ColorRect.new()
	poof.color = Color(0.8, 0.8, 0.8, 0.7)
	poof.size = Vector2(30, 30)
	poof.position = global_position - Vector2(15, 30)
	poof.z_index = 6
	get_parent().add_child(poof)

	var poof_tween := create_tween()
	poof_tween.tween_property(poof, "scale", Vector2(2.5, 2.5), 0.3)
	poof_tween.parallel().tween_property(poof, "modulate:a", 0.0, 0.4)
	poof_tween.tween_callback(poof.queue_free)

	# Ghost state: semi-transparent until player presses a non-movement button
	modulate = Color(1, 1, 1, 0.4)
	_class_change_ghost = true
	PlayerHUD.class_change_locked[player_index] = true


func _check_class_change_ghost() -> void:
	if not _class_change_ghost:
		return

	var pressed := false
	if device_id == -1:
		pressed = _is_device_action_just_pressed("attack") or \
				  _is_device_action_just_pressed("special") or \
				  _is_device_action_just_pressed("jump") or \
				  _is_device_action_just_pressed("block") or \
				  _is_device_action_just_pressed("interact")
	else:
		pressed = _is_device_action_just_pressed("attack") or \
				  _is_device_action_just_pressed("special") or \
				  _is_device_action_just_pressed("jump") or \
				  _is_device_action_just_pressed("block") or \
				  _is_device_action_just_pressed("interact") or \
				  _is_device_action_just_pressed("grapple")

	if not pressed:
		return

	# Materialize: restore opacity
	_class_change_ghost = false
	var restore_tween := create_tween()
	restore_tween.tween_property(self, "modulate:a", 1.0, 0.2)

	# NOW spawn the rift tentacle
	PlayerHUD.active_tentacle_count += 1
	var rift_script := load("res://scripts/effects/rift_tentacle.gd")
	var rift := Node2D.new()
	rift.set_script(rift_script)
	rift.global_position = global_position + Vector2(0, -30)
	rift.setup(player_index)
	get_parent().add_child(rift)

	# Unlock after rift duration (15s)
	var pi_capture: int = player_index
	var unlock_timer := get_tree().create_timer(15.0)
	unlock_timer.timeout.connect(func() -> void:
		if not PlayerHUD.tentacle_lost.has(pi_capture):
			PlayerHUD.class_change_locked.erase(pi_capture)
			PlayerHUD.active_tentacle_count = maxi(0, PlayerHUD.active_tentacle_count - 1)
	)


func _on_skill_leveled_up(p_index: int, skill: String, new_level: int) -> void:
	if p_index != player_index:
		return
	_update_player_label()
	# Gold flash
	modulate = Color(1.0, 0.85, 0.0)
	var flash_tween := create_tween()
	flash_tween.tween_property(self, "modulate", Color.WHITE, 0.5)
	# Floating "LEVEL UP!" text
	var level_label := Label.new()
	level_label.text = skill.to_upper() + " Lv." + str(new_level) + "!"
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.add_theme_font_size_override("font_size", 12)
	level_label.modulate = Color(1.0, 0.85, 0.0)
	level_label.position = Vector2(-30, -45)
	level_label.z_index = 15
	add_child(level_label)
	var label_tween := level_label.create_tween()
	label_tween.set_parallel(true)
	label_tween.tween_property(level_label, "position:y", level_label.position.y - 30.0, 1.2)
	label_tween.tween_property(level_label, "modulate:a", 0.0, 1.2)
	label_tween.chain().tween_callback(level_label.queue_free)
	# Fanfare sound
	AudioManager.play("menu_confirm", 2.0, 0.8)


# -- Input helpers -------------------------------------------------------------

func _is_device_action_pressed(action: String) -> bool:
	if device_id == -1:
		return Input.is_action_pressed(action)
	return _controller_actions.get(action, false)


func _is_device_action_just_pressed(action: String) -> bool:
	if device_id == -1:
		return Input.is_action_just_pressed(action)
	return _controller_just_pressed.get(action, false)


func _init_reticle_pos() -> void:
	_archer_reticle_pos = global_position + Vector2(100.0 if _facing_right else -100.0, -50.0)


func _needs_redraw() -> bool:
	## Returns true if this player needs to redraw custom visuals this frame.
	if DebugOverlay.global_enabled:
		return true
	if _hud_aura_fade > 0.0:
		return true
	if PlayerHUD and PlayerHUD._hud_popups.has(player_index):
		return true
	if character_class == PlayerManager.CharacterClass.RANGED:
		return true
	if _grapple_state != GrappleState.IDLE:
		return true
	return false


var _trigger_left_was_pressed: bool = false  # Previous frame L2 state

func _is_trigger_pressed(axis: JoyAxis) -> bool:
	## Check if an analog trigger is pressed with hysteresis.
	## Higher threshold to START pressing, lower threshold to STOP.
	# AI override: check injected trigger state
	if _ai_active and not _ai_triggers.is_empty():
		if axis == JOY_AXIS_TRIGGER_LEFT:
			return _ai_triggers.get("l2", false)
		elif axis == JOY_AXIS_TRIGGER_RIGHT:
			return _ai_triggers.get("r2", false)
	if device_id == -1:
		if axis == JOY_AXIS_TRIGGER_LEFT:
			return Input.is_key_pressed(KEY_TAB)
		elif axis == JOY_AXIS_TRIGGER_RIGHT:
			return Input.is_key_pressed(KEY_ENTER)
		return false
	var value: float = Input.get_joy_axis(device_id, axis)
	# Hysteresis: if already aiming, use lower threshold to keep it active
	var threshold: float = 0.05 if _archer_aiming else 0.1
	return value > threshold


func _is_trigger_just_pressed(axis: JoyAxis) -> bool:
	## Returns true on the frame the trigger transitions from released to pressed.
	var pressed: bool = _is_trigger_pressed(axis)
	if axis == JOY_AXIS_TRIGGER_LEFT:
		var just: bool = pressed and not _trigger_left_was_pressed
		_trigger_left_was_pressed = pressed
		return just
	return false


func _input(event: InputEvent) -> void:
	# Tuning popup mouse handling (works for keyboard player)
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		_exec_tuning_handle_input(event)
	if device_id == -1:
		return
	if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	if event.device != device_id:
		return

	for action in ["move_left", "move_right", "move_up", "move_down", "jump", "attack", "special", "block", "interact", "grapple", "debug_toggle"]:
		if event.is_action_pressed(action):
			_controller_actions[action] = true
			_controller_just_pressed[action] = true
		elif event.is_action_released(action):
			_controller_actions[action] = false


func _physics_process(delta: float) -> void:
	# AI input injection — must run BEFORE anything reads input
	_ai_tick()
	# Sync debug mode from DebugOverlay global state
	_debug_mode = DebugOverlay.global_enabled
	if _needs_redraw():
		queue_redraw()
	_apply_gravity(delta)
	_check_out_of_bounds()
	_check_class_change_ghost()

	if _is_dead:
		_check_revive(delta)
		move_and_slide()
		_controller_just_pressed.clear()
		return

	# Stagger update - skip all input while staggered
	if _is_staggered:
		_stagger_timer -= delta
		# Rapid shake while staggered
		var shake_offset: float = sin(Time.get_ticks_msec() * 0.04) * 3.0
		position.x += shake_offset
		if _stagger_timer <= 0.0:
			_is_staggered = false
			# Remove stagger stars VFX
			var stars := get_node_or_null("StaggerStars")
			if stars:
				stars.queue_free()
		_update_health_bar()
		_update_animation(delta)
		move_and_slide()
		_controller_just_pressed.clear()
		return

	_update_cooldowns(delta)
	_update_combo_timer(delta)
	_handle_delegate_toggle()
	_grapple_swing_drove_velocity = false
	_handle_ranger_grapple()
	# While swinging taut on grapple, pendulum drives velocity — skip normal
	# movement handlers but still run move_and_slide() for collision resolution.
	if _grapple_swing_drove_velocity:
		_handle_archer_aim(delta)  # Can aim and shoot while swinging
		_update_health_bar()
		_update_animation(delta)
		move_and_slide()
		_grapple_post_slide_correct()
		_controller_just_pressed.clear()
		queue_redraw()
		return
	_class_tick(delta)
	_handle_block()
	if _delegate_active:
		# Summoner is frozen in delegate mode - skip normal input
		velocity.x = 0.0
		_update_delegate(delta)
		_update_health_bar()
		_update_animation(delta)
		move_and_slide()
		_controller_just_pressed.clear()
		return
	_handle_movement()
	_handle_jump()
	_handle_rocket(delta)
	_handle_wall_slide(delta)
	if _charge_comp:
		_charge_comp.tick(delta)
	_check_ground_slam_landing()
	_check_werewolf_pounce_landing()
	_update_health_bar()
	_handle_attack(delta)
	_handle_special()
	_update_animation(delta)
	move_and_slide()
	_exec_apply_chain_constraint()

	# Clear AFTER all checks so button presses are actually read
	_controller_just_pressed.clear()


func _update_cooldowns(delta: float) -> void:
	if _attack_cooldown > 0.0:
		_attack_cooldown -= delta
	if _special_cooldown > 0.0:
		_special_cooldown -= delta
	if _grapple_launch_immunity > 0.0:
		_grapple_launch_immunity -= delta


func _grapple_post_slide_correct() -> void:
	## After move_and_slide(), the player may have been pushed by a wall or floor.
	## Re-sync the pendulum angle and rope length to match the actual position
	## so the next frame's swing math starts from reality, not from the pre-collision
	## target. Without this, the pendulum would fight the wall every frame.
	if _grapple_state != GrappleState.SWINGING or _grapple_rope_slack:
		return
	var diff: Vector2 = global_position - _grapple_anchor
	var actual_dist: float = diff.length()
	if actual_dist < 1.0:
		return
	# Update pendulum angle to match where move_and_slide placed us
	_grapple_swing_angle = atan2(diff.x, diff.y)
	# If we hit a wall, the actual distance is shorter than rope length — go slack
	# briefly so the player doesn't stick to the wall
	if actual_dist < _grapple_rope_len * 0.9:
		_grapple_rope_slack = true
	# Kill angular velocity component that pushes INTO the wall
	if get_slide_collision_count() > 0:
		var tangent: Vector2 = Vector2(cos(_grapple_swing_angle), -sin(_grapple_swing_angle))
		_grapple_swing_vel = velocity.dot(tangent) / maxf(actual_dist, 1.0)


# -- Physics -------------------------------------------------------------------

func _apply_gravity(delta: float) -> void:
	if _mage_airwalk:
		return
	if _balloonist_floating:
		return  # Balloon carries us up
	if not is_on_floor():
		var grav: float = cfg("gravity", GRAVITY)
		# Count attached balloons - reduce gravity per balloon
		var balloon_count: int = 0
		for dart in get_tree().get_nodes_in_group("balloon_darts"):
			if dart.has_method("_get_entity_weight") and dart.get("_attached_to") == self:
				balloon_count += 1
		if balloon_count > 0:
			# Each balloon reduces gravity by 30%, fall slower
			var gravity_mult: float = maxf(0.1, 1.0 - balloon_count * 0.3)
			velocity.y += grav * delta * gravity_mult
			velocity.y = min(velocity.y, 600.0 * gravity_mult)
		else:
			velocity.y += grav * delta
			velocity.y = min(velocity.y, 600.0)


func _handle_movement() -> void:
	# Grapple launch immunity — don't override velocity after grapple release
	# Stays active until timer expires AND player is on the floor
	if _grapple_launch_immunity > 0.0:
		if not is_on_floor():
			_grapple_launch_immunity = maxf(_grapple_launch_immunity, 0.05)  # Keep alive while airborne
		return
	# YEET launch immunity — don't override velocity after chain YEET
	if _exec_yeet_immunity > 0.0:
		if not is_on_floor():
			_exec_yeet_immunity = maxf(_exec_yeet_immunity, 0.05)  # Keep alive while airborne
		return
	# Healer cannot move while channeling
	if _is_charging and character_class == PlayerManager.CharacterClass.HEALER:
		velocity.x = 0.0
		return
	# Shield charge overrides movement
	if _shield_charging:
		return

	# Analog stick via Godot's action system (applies project deadzone, works for all input types)
	var h_input: float = Input.get_axis("move_left", "move_right")

	# Ranger uses smoothed input to filter sign-flip jitter from noisy controllers
	var move_h: float = h_input
	if _ranger_class and character_class == PlayerManager.CharacterClass.RANGED:
		move_h = _ranger_class._smoothed_h

	var speed: float = PlayerManager.get_player(player_index).get("speed", 100)
	if _melee_enraged:
		speed *= MELEE_ENRAGE_SPEED_MULT
	if _werewolf_frenzy_active:
		speed *= 1.25
	if _is_blocking:
		speed *= 0.5
	# Ranger dash: locked direction at 4x speed (overrides input)
	if _ranger_class and _ranger_class._is_dashing:
		velocity.x = _ranger_class._dash_direction * speed * _ranger_class.DASH_SPEED_MULT
		return
	# Ranger variable walk/run: 0-90% stick = walk (proportional), 91%+ = run (2x)
	if _ranger_class and character_class == PlayerManager.CharacterClass.RANGED:
		var deflection := absf(move_h)
		if _ranger_class._is_running or _ranger_class._run_airborne:
			# Run mode (or airborne from run): 2x speed in input direction
			velocity.x = signf(move_h) * speed * _ranger_class.RUN_SPEED_MULT if deflection > 0.0 else 0.0
		else:
			# Walk mode: scale within 0-90% range (90% stick = full walk speed)
			var walk_factor := clampf(deflection / 0.9, 0.0, 1.0)
			velocity.x = signf(move_h) * speed * walk_factor
	else:
		velocity.x = h_input * speed

	# Update facing — use smoothed input for Ranger, raw for others
	var face_h: float = move_h if _ranger_class else h_input
	if absf(face_h) > 0.2:
		_facing_right = face_h > 0.0
		sprite.flip_h = not _facing_right


func _handle_jump() -> void:
	# Reset wall jump stamina and rocket when on the floor
	if is_on_floor():
		_wall_jump_stamina = WALL_JUMP_STAMINA_MAX
		_jumper_air_jumps = 0
		_jumper_dive_active = false
		if character_class == PlayerManager.CharacterClass.DEMOLITIONIST:
			_rocket_can_activate = false
			_rocket_active = false
			_rocket_out_of_control = false
			_rocket_hold_time = 0.0
			_rocket_drift_angle = 0.0
			# NO auto-refuel on landing - must hold Circle to refuel

	if not _is_device_action_just_pressed("jump"):
		return

	if is_on_floor():
		var jump_vel: float = JUMPER_JUMP_VELOCITY if character_class == PlayerManager.CharacterClass.NINJA else cfg("jump_velocity", JUMP_VELOCITY)
		velocity.y = jump_vel
		AudioManager.play("jump", -5.0)
		if character_class == PlayerManager.CharacterClass.DEMOLITIONIST:
			_rocket_can_activate = true
	elif character_class == PlayerManager.CharacterClass.NINJA and _jumper_air_jumps < JUMPER_MAX_AIR_JUMPS:
		# TRIPLE JUMP - each jump slightly weaker
		_jumper_air_jumps += 1
		var jump_power: float = JUMPER_JUMP_VELOCITY * (1.0 - _jumper_air_jumps * 0.15)
		velocity.y = jump_power
		AudioManager.play("jump", -3.0, 1.0 + _jumper_air_jumps * 0.2)
		# Wind puff VFX at feet
		_spawn_vfx(Color(0.5, 1.0, 1.0, 0.4), Vector2(12, 12))
	elif character_class == PlayerManager.CharacterClass.DEMOLITIONIST and _rocket_can_activate and not _rocket_active and _rocket_fuel > 0.0:
		_rocket_active = true
		_rocket_hold_time = 0.0
		_rocket_drift_angle = 0.0
		_rocket_out_of_control = false
		# Random spin direction: clockwise or counter-clockwise
		_rocket_spin_direction = 1.0 if randf() > 0.5 else -1.0
		AudioManager.play("rocket_ignite")
	elif _is_wall_sliding:
		if _wall_jump_stamina <= 0:
			_flash_wall_jump_exhausted()
			return
		_wall_jump_stamina -= 1
		_wall_jump()
		AudioManager.play("jump", -5.0, 1.2)
		if _wall_jump_stamina <= 0:
			_flash_wall_jump_exhausted()


func _handle_rocket(delta: float) -> void:
	if character_class != PlayerManager.CharacterClass.DEMOLITIONIST:
		return
	if not _rocket_active:
		return

	# Landing safely deactivates rocket
	if is_on_floor():
		_rocket_active = false
		return

	# Out of fuel mid-air = EXPLOSION!
	if _rocket_fuel <= 0.0:
		sprite.rotation = 0.0
		_rocket_crash_explode()
		return

	# Once out of control, player CANNOT stop - careens until crash
	var pressing_thrust: bool = _is_device_action_pressed("jump") or _rocket_out_of_control

	if pressing_thrust:
		_rocket_fuel -= delta
		_rocket_hold_time += delta

		# --- Chaos ramps FAST: 0→1 over 1.5 seconds ---
		var chaos: float = clampf(_rocket_hold_time / 1.5, 0.0, 1.0)
		var chaos_sq: float = chaos * chaos
		var chaos_cube: float = chaos_sq * chaos

		# Point of no return at 80% chaos (~1.2 seconds)
		if chaos > 0.8 and not _rocket_out_of_control:
			_rocket_out_of_control = true
			AudioManager.play("boss_roar", -2.0, 2.0)

		# --- Consistent rotational drift ---
		# Drift angle accumulates in one direction (CW or CCW)
		# Starts slow, accelerates with chaos
		var drift_rate: float = chaos_sq * 3.0  # radians per second at max chaos
		_rocket_drift_angle += _rocket_spin_direction * drift_rate * delta

		# Player's aim input
		var aim_dir := Vector2.ZERO
		if _is_device_action_pressed("move_left"):
			aim_dir.x -= 1.0
		if _is_device_action_pressed("move_right"):
			aim_dir.x += 1.0
		if _is_device_action_pressed("move_up"):
			aim_dir.y -= 1.0
		if _is_device_action_pressed("move_down"):
			aim_dir.y += 1.0

		var base_dir: Vector2
		if aim_dir == Vector2.ZERO:
			base_dir = Vector2(0, -1)
		else:
			base_dir = aim_dir.normalized()

		# Apply accumulated drift rotation to the aimed direction
		# At low chaos: player has full control
		# At high chaos: drift overpowers the aim completely
		var player_influence: float = 1.0 - chaos_cube  # 1.0 → 0.0
		var thrust_dir: Vector2 = base_dir.rotated(_rocket_drift_angle * (1.0 - player_influence * 0.7))

		# When out of control, thrust locks to whatever direction it's drifting
		if _rocket_out_of_control:
			thrust_dir = Vector2.UP.rotated(_rocket_drift_angle)

		var exhaust_dir: Vector2 = -thrust_dir

		# Non-linear thrust ramp
		var current_thrust: float = ROCKET_THRUST * (1.0 + chaos_cube * 2.0)
		velocity += thrust_dir * current_thrust * delta

		# Speed cap ramps with chaos
		var current_max_speed: float = ROCKET_MAX_SPEED * (1.0 + chaos_sq * 0.8)
		if velocity.length() > current_max_speed:
			velocity = velocity.normalized() * current_max_speed

		# Cancel gravity
		velocity.y -= GRAVITY * delta * 0.85

		# Rotate the sprite to match flight direction
		sprite.rotation = velocity.angle() + PI / 2.0 if _rocket_out_of_control else 0.0

		# --- Flames: denser and wilder with chaos ---
		_rocket_flame_timer += delta
		var flame_interval: float = maxf(0.006, 0.015 - chaos * 0.009)
		if _rocket_flame_timer >= flame_interval:
			_rocket_flame_timer -= flame_interval
			_spawn_rocket_flame(exhaust_dir)
			_spawn_rocket_flame(exhaust_dir)
			if chaos > 0.3:
				_spawn_rocket_flame(exhaust_dir)
			if randi() % 2 == 0:
				_spawn_rocket_flame_big(exhaust_dir)
			# Wild sparks spray sideways at high chaos
			if chaos > 0.5:
				var spark_dir: Vector2 = exhaust_dir.rotated(_rocket_spin_direction * randf_range(0.5, 1.5))
				_spawn_rocket_flame(spark_dir)

		# --- Smoke ---
		_rocket_smoke_timer += delta
		var smoke_interval: float = maxf(0.015, 0.035 - chaos * 0.02)
		if _rocket_smoke_timer >= smoke_interval:
			_rocket_smoke_timer -= smoke_interval
			_spawn_rocket_smoke()
			if chaos > 0.5:
				_spawn_rocket_smoke()

		# Screen shake escalates
		var shake_amount: float = clampf(chaos_sq * 5.0, 0.0, 5.0)
		position.x += randf_range(-shake_amount, shake_amount)
		position.y += randf_range(-shake_amount, shake_amount)

		# Tint: white → orange → red
		var chaos_color: Color = Color.WHITE.lerp(Color(1.0, 0.4, 0.1), chaos_sq)
		if _rocket_out_of_control:
			# Flash red/white when out of control
			chaos_color = Color(1.0, 0.2, 0.1) if fmod(_rocket_hold_time, 0.15) < 0.075 else Color(1.0, 0.6, 0.2)
		modulate = chaos_color

		# --- CRASH CHECK ---
		if velocity.length() > 250.0:
			if is_on_wall() or is_on_floor() or is_on_ceiling():
				sprite.rotation = 0.0
				_rocket_crash_explode()
				return
			for body in get_tree().get_nodes_in_group("enemies"):
				if body is Node2D:
					var dist: float = global_position.distance_to(body.global_position)
					if dist < 20.0:
						sprite.rotation = 0.0
						_rocket_crash_explode()
						return
	else:
		# Jump released (only possible if not out of control)
		_rocket_hold_time = maxf(0.0, _rocket_hold_time - delta * 3.0)
		_rocket_drift_angle *= (1.0 - delta * 4.0)  # Drift recovers when not thrusting
		sprite.rotation = 0.0


func _rocket_crash_explode() -> void:
	_rocket_active = false
	var chaos: float = clampf(_rocket_hold_time / 3.0, 0.0, 1.0)
	var chaos_sq: float = chaos * chaos
	_rocket_hold_time = 0.0
	modulate = Color.WHITE

	# Blast radius and damage scale with how long they held the rocket
	var blast_radius: float = lerpf(40.0, 150.0, chaos_sq)
	var blast_damage: int = int(lerpf(10.0, 50.0, chaos_sq))
	# Self damage = 40% of max health
	var p_data: Dictionary = PlayerManager.get_player(player_index)
	var max_hp: int = p_data.get("max_health", 100) if not p_data.is_empty() else 100
	var self_damage: int = int(max_hp * 0.4)

	AudioManager.play("explosion", 4.0, lerpf(0.8, 0.4, chaos))
	if chaos > 0.5:
		AudioManager.play("boss_roar", -2.0, 1.5)  # Extra boom

	# Self damage
	PlayerManager.damage_player(player_index, self_damage)
	_update_health_bar()

	# Screen shake proportional to blast
	_screen_shake(lerpf(3.0, 12.0, chaos_sq), lerpf(0.15, 0.4, chaos))

	# Knockback self
	velocity = Vector2(0, -200.0 - chaos * 200.0)

	# --- EXPLOSION VFX ---
	var explode_pos: Vector2 = global_position

	# White-hot flash at center
	var flash := ColorRect.new()
	flash.color = Color(1.0, 1.0, 0.9, 0.9)
	var flash_size: float = blast_radius * 0.6
	flash.size = Vector2(flash_size, flash_size)
	flash.position = explode_pos - Vector2(flash_size / 2.0, flash_size / 2.0)
	flash.z_index = 12
	get_parent().add_child(flash)
	var flash_tw := flash.create_tween()
	flash_tw.tween_property(flash, "modulate:a", 0.0, 0.15)
	flash_tw.tween_callback(flash.queue_free)

	# Expanding fire ring
	var ring := ColorRect.new()
	ring.color = Color(1.0, 0.4, 0.0, 0.7)
	ring.size = Vector2(20, 20)
	ring.position = explode_pos - Vector2(10, 10)
	ring.pivot_offset = Vector2(10, 10)
	ring.z_index = 11
	get_parent().add_child(ring)
	var ring_scale: float = blast_radius / 10.0
	var ring_tw := ring.create_tween()
	ring_tw.set_parallel(true)
	ring_tw.tween_property(ring, "scale", Vector2(ring_scale, ring_scale), 0.25)
	ring_tw.tween_property(ring, "modulate:a", 0.0, 0.35)
	ring_tw.chain().tween_callback(ring.queue_free)

	# Fire + smoke debris particles with physics
	var particle_count: int = int(lerpf(12.0, 40.0, chaos_sq))
	for i in range(particle_count):
		var is_fire: bool = randf() < 0.6
		var p := ColorRect.new()
		if is_fire:
			var fire_colors: Array[Color] = [
				Color(1.0, 0.9, 0.3, 0.9),
				Color(1.0, 0.5, 0.0, 0.85),
				Color(1.0, 0.2, 0.0, 0.8),
			]
			p.color = fire_colors[i % fire_colors.size()]
		else:
			p.color = Color(0.4, 0.4, 0.4, 0.6)

		var psize: float = randf_range(3.0, 8.0 + chaos * 5.0)
		p.size = Vector2(psize, psize)
		p.position = explode_pos + Vector2(randf_range(-5, 5), randf_range(-5, 5))
		p.z_index = 10
		get_parent().add_child(p)

		# Physics: launch outward with gravity
		var launch_angle: float = randf_range(0, TAU)
		var launch_speed: float = randf_range(80.0, 250.0 + chaos * 200.0)
		var p_vel: Vector2 = Vector2(cos(launch_angle), sin(launch_angle)) * launch_speed
		_animate_crash_particle(p, p_vel, is_fire, blast_damage)

	# Damage enemies in blast radius
	for body in get_tree().get_nodes_in_group("enemies"):
		if not body is Node2D:
			continue
		var dist: float = explode_pos.distance_to(body.global_position)
		if dist < blast_radius and body.has_method("take_damage"):
			body.take_damage(blast_damage, player_index)
			if body.has_method("apply_knockback"):
				var kb: Vector2 = (body.global_position - explode_pos).normalized()
				body.apply_knockback(kb * (300.0 + chaos * 300.0))


func _animate_crash_particle(p: ColorRect, vel: Vector2, is_fire: bool, contact_damage: int) -> void:
	var gravity: float = 300.0
	var age: float = 0.0
	var max_age: float = randf_range(0.8, 2.0)

	while age < max_age and is_instance_valid(p) and is_inside_tree():
		var dt: float = get_process_delta_time()
		age += dt
		vel.y += gravity * dt
		vel *= (1.0 - 0.8 * dt)  # Air drag
		p.position += vel * dt

		# Fade out
		if age > max_age * 0.5:
			p.modulate.a = lerpf(1.0, 0.0, (age - max_age * 0.5) / (max_age * 0.5))

		# Fire particles can damage enemies they touch
		if is_fire and age < max_age * 0.6:
			for body in get_tree().get_nodes_in_group("enemies"):
				if body is Node2D:
					var dist: float = p.position.distance_to(body.global_position)
					if dist < 12.0 and body.has_method("take_damage"):
						body.take_damage(int(contact_damage * 0.3), -1)
						# Only damage each enemy once per particle
						is_fire = false
						break

		# Smoke particles expand
		if not is_fire:
			p.scale += Vector2(dt * 1.5, dt * 1.5)

		await get_tree().process_frame

	if is_instance_valid(p):
		p.queue_free()


func _spawn_rocket_flame(flame_dir: Vector2) -> void:
	var flame := ColorRect.new()
	var flame_colors: Array[Color] = [
		Color(1.0, 0.9, 0.5, 0.95),  # White-hot core
		Color(1.0, 0.7, 0.1, 0.9),   # Bright yellow
		Color(1.0, 0.45, 0.0, 0.85), # Orange
		Color(1.0, 0.2, 0.0, 0.8),   # Red tip
	]
	flame.color = flame_colors[randi() % flame_colors.size()]
	var size: float = randf_range(2.0, 5.0)
	flame.size = Vector2(size, size)
	flame.z_index = -1
	# Tight spawn: very close to player, minimal perpendicular spread
	var perp: Vector2 = Vector2(-flame_dir.y, flame_dir.x)
	flame.position = global_position + flame_dir * 6.0 + perp * randf_range(-2, 2)
	get_parent().add_child(flame)

	# Tight cone: flames travel mostly along exhaust_dir with very little spread
	var spread: Vector2 = perp * randf_range(-4, 4)
	var target_pos: Vector2 = flame.position + flame_dir * randf_range(20, 45) + spread

	var tween := flame.create_tween()
	tween.set_parallel(true)
	tween.tween_property(flame, "position", target_pos, randf_range(0.08, 0.18))
	tween.tween_property(flame, "modulate:a", 0.0, randf_range(0.1, 0.2))
	tween.tween_property(flame, "scale", Vector2(0.15, 0.15), 0.18)
	tween.chain().tween_callback(flame.queue_free)


func _spawn_rocket_flame_big(exhaust_dir: Vector2) -> void:
	var flame := ColorRect.new()
	flame.color = Color(1.0, 0.95, 0.7, 0.95)  # White-hot
	var size: float = randf_range(5.0, 10.0)
	flame.size = Vector2(size, size)
	flame.z_index = -1
	flame.position = global_position + exhaust_dir * 4.0
	get_parent().add_child(flame)

	var perp: Vector2 = Vector2(-exhaust_dir.y, exhaust_dir.x)
	var target_pos: Vector2 = flame.position + exhaust_dir * randf_range(30, 55) + perp * randf_range(-5, 5)
	var tween := flame.create_tween()
	tween.set_parallel(true)
	tween.tween_property(flame, "position", target_pos, randf_range(0.12, 0.25))
	tween.tween_property(flame, "modulate:a", 0.0, randf_range(0.15, 0.3))
	tween.tween_property(flame, "scale", Vector2(0.05, 0.05), 0.25)
	tween.tween_property(flame, "color", Color(0.9, 0.15, 0.0, 0.0), 0.25)
	tween.chain().tween_callback(flame.queue_free)


func _spawn_rocket_smoke() -> void:
	var smoke := ColorRect.new()
	var smoke_colors: Array[Color] = [
		Color(0.45, 0.45, 0.45, 0.35),
		Color(0.55, 0.50, 0.45, 0.3),
		Color(0.35, 0.35, 0.35, 0.4),
	]
	smoke.color = smoke_colors[randi() % smoke_colors.size()]
	var size: float = randf_range(3.0, 7.0)
	smoke.size = Vector2(size, size)
	smoke.z_index = -2
	smoke.position = global_position + Vector2(randf_range(-3, 3), randf_range(-2, 3))
	get_parent().add_child(smoke)

	var tween := smoke.create_tween()
	tween.set_parallel(true)
	tween.tween_property(smoke, "position:y", smoke.position.y - randf_range(8, 25), 0.7)
	tween.tween_property(smoke, "position:x", smoke.position.x + randf_range(-12, 12), 0.7)
	tween.tween_property(smoke, "modulate:a", 0.0, 0.9)
	tween.tween_property(smoke, "scale", Vector2(2.5, 2.5), 0.9)
	tween.chain().tween_callback(smoke.queue_free)


func _handle_wall_slide(_delta: float) -> void:
	_is_wall_sliding = false
	if is_on_wall_only() and not is_on_floor() and velocity.y > 0.0:
		_is_wall_sliding = true
		velocity.y = min(velocity.y, 60.0)  # Slow fall on wall


func _wall_jump() -> void:
	var wall_normal := get_wall_normal()
	velocity.x = wall_normal.x * WALL_JUMP_VELOCITY.x
	velocity.y = WALL_JUMP_VELOCITY.y
	_facing_right = wall_normal.x > 0.0
	sprite.flip_h = not _facing_right


func _flash_wall_jump_exhausted() -> void:
	# Brief red flash to indicate wall jump stamina is depleted
	modulate = Color(1.0, 0.2, 0.2)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.2)


# -- Animation -----------------------------------------------------------------

func _update_animation(delta: float) -> void:
	if _is_attacking:
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			_is_attacking = false
		else:
			# Alternate between attack frames
			sprite.frame = AnimFrame.ATTACK1 if _attack_timer > ATTACK_DURATION * 0.5 else AnimFrame.ATTACK2
			return

	if not is_on_floor():
		sprite.frame = AnimFrame.JUMP
		return

	if abs(velocity.x) > 10.0:
		_walk_timer += delta
		if _walk_timer >= 1.0 / WALK_ANIM_FPS:
			_walk_timer -= 1.0 / WALK_ANIM_FPS
			_walk_frame_toggle = not _walk_frame_toggle
		sprite.frame = AnimFrame.WALK1 if _walk_frame_toggle else AnimFrame.WALK2
	else:
		sprite.frame = AnimFrame.IDLE
		_walk_timer = 0.0


# -- Attack --------------------------------------------------------------------

func _handle_attack(_delta: float) -> void:
	if _attack_cooldown > 0.0 or _is_charging:
		return
	if not _is_device_action_just_pressed("attack"):
		return

	_attack_cooldown = cfg("attack_cooldown", ATTACK_COOLDOWN_TIME)
	_is_attacking = true
	_attack_timer = ATTACK_DURATION
	_perform_attack()


## Class dispatch tables — map class enum to callables.
## When a class is extracted to a ClassComponent, its entry gets removed from here.
var _class_attack_fn: Dictionary = {}
var _class_special_fn: Dictionary = {}
var _class_charged_fn: Dictionary = {}
var _class_tick_fn: Dictionary = {}

func _init_class_dispatch() -> void:
	## Build dispatch tables. Called from _ready().
	_class_attack_fn = {
	}
	_class_special_fn = {
	}
	_class_charged_fn = {
	}
	# Per-frame class handlers — each class gets ONE tick function
	# that consolidates all its per-frame logic (was scattered _handle_* calls)
	_class_tick_fn = {
	}


func _class_tick(delta: float) -> void:
	## Per-frame class-specific logic — replaces scattered _handle_* calls.
	var fn: Variant = _class_tick_fn.get(character_class)
	if fn is Callable:
		fn.call(delta)

func _tick_ranged(delta: float) -> void:
	_handle_ranger_reload(delta)
	_handle_archer_aim(delta)

var _charge_comp: Variant = null         # ChargeComponent instance
var _executioner_class: Variant = null  # ExecutionerClass instance (when active)
var _ranger_class: Variant = null       # RangerClass instance (when active)

func _init_ranger_class() -> void:
	## Create the RangerClass component and wire dispatch through it.
	var RangerScript := preload("res://scripts/classes/ranger/ranger_class.gd")
	_ranger_class = Node.new()
	_ranger_class.set_script(RangerScript)
	add_child(_ranger_class)
	var CharCtx := preload("res://scripts/components/character_context.gd")
	var ranger_ctx = CharCtx.new()
	ranger_ctx.body = self
	_ranger_class.inject_context(ranger_ctx)
	_ranger_class.on_class_enter()
	# Redirect dispatch entries to the class component
	_class_attack_fn[PlayerManager.CharacterClass.RANGED] = _ranger_class.perform_attack
	_class_special_fn[PlayerManager.CharacterClass.RANGED] = _ranger_class.perform_special
	_class_tick_fn[PlayerManager.CharacterClass.RANGED] = func(delta: float): _ranger_class.tick(delta)

func _init_executioner_class() -> void:
	## Create the ExecutionerClass component and wire dispatch through it.
	var ExecScript := preload("res://scripts/classes/executioner/executioner_class.gd")
	_executioner_class = Node.new()
	_executioner_class.set_script(ExecScript)
	add_child(_executioner_class)
	# Build minimal context for the class component
	var CharCtx := preload("res://scripts/components/character_context.gd")
	var exec_ctx = CharCtx.new()
	exec_ctx.body = self
	_executioner_class.inject_context(exec_ctx)
	# Let the class component handle init
	_executioner_class.on_class_enter()
	# Redirect dispatch entries to the class component
	_class_attack_fn[PlayerManager.CharacterClass.EXECUTIONER] = _executioner_class.perform_attack
	_class_special_fn[PlayerManager.CharacterClass.EXECUTIONER] = _executioner_class.perform_special
	_class_charged_fn[PlayerManager.CharacterClass.EXECUTIONER] = _executioner_class.perform_charged
	_class_tick_fn[PlayerManager.CharacterClass.EXECUTIONER] = func(delta: float): _executioner_class.tick(delta)

func _tick_executioner(delta: float) -> void:
	_handle_executioner(delta)


func _perform_attack() -> void:
	var fn: Variant = _class_attack_fn.get(character_class)
	if fn is Callable:
		fn.call({})

# -- Small class forwarders ---------------------------------------------------

var _melee_class: Variant = null
var _mage_class: Variant = null
var _tank_class: Variant = null
var _balloonist_class: Variant = null
var _ninja_class: Variant = null

func _init_class_component(cls_name: String) -> void:
	var script_path: String = "res://scripts/classes/%s/%s_class.gd" % [cls_name, cls_name]
	var cls_script := load(script_path)
	if not cls_script: return
	var comp := Node.new()
	comp.set_script(cls_script)
	add_child(comp)
	var CharCtx := preload("res://scripts/components/character_context.gd")
	var ctx = CharCtx.new()
	ctx.body = self
	comp.inject_context(ctx)
	match cls_name:
		"melee": _melee_class = comp
		"mage": _mage_class = comp
		"tank": _tank_class = comp
		"balloonist": _balloonist_class = comp
		"ninja": _ninja_class = comp
		"rogue": _rogue_class = comp
		"demolitionist": _demolitionist_class = comp
		"healer": _healer_class = comp
		"summoner": _summoner_class = comp
		"guitarist": _guitarist_class = comp
		"werewolf": _werewolf_class = comp
	var cls_map := {"melee": 0, "mage": 2, "tank": 7, "balloonist": 9, "ninja": 8,
		"rogue": 4, "demolitionist": 5, "healer": 6, "summoner": 3,
		"guitarist": 10, "werewolf": 11}
	var e: int = cls_map.get(cls_name, -1)
	if e >= 0:
		_class_attack_fn[e] = comp.perform_attack
		if comp.has_method("perform_special"): _class_special_fn[e] = comp.perform_special
		if comp.has_method("perform_charged"): _class_charged_fn[e] = comp.perform_charged
		_class_tick_fn[e] = func(delta: float): comp.tick(delta)

func _update_combo_timer(delta: float) -> void:
	if _melee_class:
		_melee_class._update_combo_timer(delta)

func _check_ground_slam_landing() -> void:
	if _melee_class:
		_melee_class._check_ground_slam_landing()

func _spawn_blood_particles(hit_pos: Vector2) -> void:
	# 3 blood squirts in random upward directions
	for i in range(3):
		var angle: float = randf_range(-2.2, -0.9)  # Upward arc range
		var speed: float = randf_range(120.0, 220.0)
		var vel: Vector2 = Vector2(cos(angle), sin(angle)) * speed
		# Add some horizontal randomness
		vel.x += randf_range(-40.0, 40.0)

		var blood := ColorRect.new()
		blood.color = Color(0.8, 0.05, 0.05, 0.9)
		blood.size = Vector2(4, 4)
		blood.position = hit_pos
		blood.z_index = 9
		get_parent().add_child(blood)

		# Animate the blood arc with physics
		_animate_blood_drop(blood, vel)


func _animate_blood_drop(blood: ColorRect, vel: Vector2) -> void:
	var gravity: float = 400.0
	var age: float = 0.0
	var max_age: float = 3.0
	var landed := false
	var drip_speed: float = 15.0

	while age < max_age and is_instance_valid(blood):
		var dt: float = get_process_delta_time()
		age += dt

		if not landed:
			# Flying through air
			vel.y += gravity * dt
			blood.position += vel * dt

			# Check if hit a surface (simple: check if any StaticBody2D nearby)
			# Use a rough check: if velocity was going down and now we'd go below a platform
			var space := get_world_2d().direct_space_state
			var query := PhysicsRayQueryParameters2D.create(
				blood.position,
				blood.position + vel.normalized() * 8.0,
				1  # World layer
			)
			var result: Dictionary = space.intersect_ray(query)
			if not result.is_empty():
				# Hit a surface! Stick and drip
				landed = true
				blood.position = result["position"]
				# Determine drip direction (blood drips down along surface)
				var normal: Vector2 = result["normal"]
				if absf(normal.x) > absf(normal.y):
					# Hit a wall - drip downward
					drip_speed = randf_range(10.0, 25.0)
				else:
					# Hit floor/ceiling - slow spread
					drip_speed = randf_range(2.0, 8.0)

				# Splat effect - spawn extra tiny drops
				for s in range(2):
					var splat := ColorRect.new()
					splat.color = Color(0.7, 0.02, 0.02, 0.7)
					splat.size = Vector2(2, 2)
					splat.position = blood.position + Vector2(randf_range(-4, 4), randf_range(-4, 4))
					splat.z_index = 9
					get_parent().add_child(splat)
					var st := splat.create_tween()
					st.tween_property(splat, "modulate:a", 0.0, randf_range(3.0, 8.0))
					st.tween_callback(splat.queue_free)
		else:
			# Dripping down the surface
			blood.position.y += drip_speed * dt
			# Slowly fade
			blood.modulate.a = lerpf(0.9, 0.0, (age - 1.0) / (max_age - 1.0)) if age > 1.0 else 0.9
			# Blood stretches as it drips
			blood.size.y = minf(blood.size.y + dt * 3.0, 12.0)
			blood.size.x = maxf(blood.size.x - dt * 0.5, 2.0)

		await get_tree().process_frame

	if is_instance_valid(blood):
		blood.queue_free()

# -- Ranger functions delegated to RangerClass --------------------------------

func _handle_ranger_grapple() -> void:
	if _ranger_class:
		_ranger_class._handle_ranger_grapple()
	elif _grapple_state != GrappleState.IDLE:
		DebugOverlay.log("player/slide", self, "WARN: grapple state=%d but no _ranger_class!" % _grapple_state)

func _draw_grapple() -> void:
	if _ranger_class:
		_ranger_class._draw_grapple()

func _handle_ranger_reload(delta: float) -> void:
	if _ranger_class:
		_ranger_class._handle_ranger_reload(delta)

func _handle_archer_aim(delta: float) -> void:
	if _ranger_class:
		_ranger_class._handle_archer_aim(delta)

func _draw_archer_aim() -> void:
	if _ranger_class:
		_ranger_class._draw_archer_aim()

func _spawn_fireball(aim: Vector2, damage: int) -> void:
	var fireball := Node2D.new()
	fireball.name = "Fireball"
	fireball.global_position = global_position + aim * 16.0
	fireball.z_index = 8
	fireball.add_to_group("loose_items")
	fireball.set_meta("projectile_type", "fire")

	# Attach a script-like behavior via inline approach: store data on meta
	fireball.set_meta("direction", aim)
	fireball.set_meta("speed", 200.0)
	fireball.set_meta("damage", damage)
	fireball.set_meta("owner_index", player_index)
	fireball.set_meta("lifetime", 3.0)

	# Add a public property for balloon detection
	var fb_script := GDScript.new()
	fb_script.source_code = """extends Node2D

var projectile_type: String = "fire"
var direction: Vector2 = Vector2.ZERO
var speed: float = 200.0
var damage: int = 18
var owner_index: int = 0
var lifetime: float = 3.0
var _age: float = 0.0
var _fire_timer: float = 0.0
var _smoke_timer: float = 0.0

func _ready() -> void:
	add_to_group("loose_items")

func _draw() -> void:
	# Outer glow
	draw_circle(Vector2.ZERO, 10.0, Color(1.0, 0.5, 0.0, 0.3))
	# Main fireball body
	draw_circle(Vector2.ZERO, 8.0, Color(1.0, 0.6, 0.1, 0.9))
	# Bright center
	draw_circle(Vector2.ZERO, 4.0, Color(1.0, 0.95, 0.5, 1.0))
	# Hot core
	draw_circle(Vector2.ZERO, 2.0, Color(1.0, 1.0, 0.9, 1.0))

func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		_fizzle_out()
		return

	# Move
	global_position += direction * speed * delta
	queue_redraw()

	# Fire trail particles
	_fire_timer += delta
	if _fire_timer >= 0.03:
		_fire_timer -= 0.03
		_spawn_fire_particle()

	# Smoke trail particles
	_smoke_timer += delta
	if _smoke_timer >= 0.06:
		_smoke_timer -= 0.06
		_spawn_smoke_particle()

	# Check enemy collision
	for body in get_tree().get_nodes_in_group("enemies"):
		if body is Node2D:
			var dist: float = global_position.distance_to(body.global_position)
			if dist < 12.0:
				_hit_enemy(body)
				return

	# Raycast for wall collision
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
		global_position,
		global_position + direction * speed * delta * 2.0,
		1
	)
	var result: Dictionary = space.intersect_ray(query)
	if result:
		_explode_fire_burst()
		return


func _hit_enemy(body: Node2D) -> void:
	if body.has_method("take_damage"):
		body.take_damage(damage, owner_index)
	if body.has_method("apply_knockback"):
		var kb: Vector2 = direction.normalized() * 150.0
		body.apply_knockback(kb)
	_explode_fire_burst()


func _explode_fire_burst() -> void:
	AudioManager.play("explosion", -4.0, 1.2)
	# Spawn explosion particles
	if is_inside_tree():
		for i in range(12):
			var p := ColorRect.new()
			var colors: Array[Color] = [
				Color(1.0, 0.9, 0.3, 0.9),
				Color(1.0, 0.5, 0.0, 0.8),
				Color(1.0, 0.2, 0.0, 0.7),
			]
			p.color = colors[i % colors.size()]
			p.size = Vector2(randf_range(3, 6), randf_range(3, 6))
			p.position = global_position + Vector2(randf_range(-4, 4), randf_range(-4, 4))
			p.z_index = 10
			get_parent().add_child(p)
			var angle: float = randf_range(0, TAU)
			var dist: float = randf_range(20, 50)
			var target: Vector2 = p.position + Vector2(cos(angle), sin(angle)) * dist
			var tw := p.create_tween()
			tw.set_parallel(true)
			tw.tween_property(p, "position", target, 0.3)
			tw.tween_property(p, "modulate:a", 0.0, 0.3)
			tw.chain().tween_callback(p.queue_free)
	queue_free()


func _fizzle_out() -> void:
	if is_inside_tree():
		for i in range(5):
			var p := ColorRect.new()
			p.color = Color(0.5, 0.5, 0.5, 0.4)
			p.size = Vector2(3, 3)
			p.position = global_position + Vector2(randf_range(-3, 3), randf_range(-3, 3))
			p.z_index = 8
			get_parent().add_child(p)
			var tw := p.create_tween()
			tw.tween_property(p, "modulate:a", 0.0, 0.4)
			tw.tween_callback(p.queue_free)
	queue_free()


func _spawn_fire_particle() -> void:
	if not is_inside_tree():
		return
	var p := ColorRect.new()
	var fire_colors: Array[Color] = [
		Color(1.0, 0.7, 0.1, 0.8),
		Color(1.0, 0.4, 0.0, 0.7),
		Color(1.0, 0.2, 0.0, 0.6),
	]
	p.color = fire_colors[randi() % fire_colors.size()]
	p.size = Vector2(randf_range(2, 5), randf_range(2, 5))
	p.position = global_position + Vector2(randf_range(-3, 3), randf_range(-3, 3))
	p.z_index = 7
	get_parent().add_child(p)
	var tw := p.create_tween()
	tw.set_parallel(true)
	tw.tween_property(p, "modulate:a", 0.0, 0.25)
	tw.tween_property(p, "scale", Vector2(0.3, 0.3), 0.25)
	tw.chain().tween_callback(p.queue_free)


func _spawn_smoke_particle() -> void:
	if not is_inside_tree():
		return
	var p := ColorRect.new()
	p.color = Color(0.4, 0.4, 0.4, 0.4)
	p.size = Vector2(3, 3)
	p.position = global_position + Vector2(randf_range(-2, 2), randf_range(-2, 2))
	p.z_index = 6
	get_parent().add_child(p)
	var tw := p.create_tween()
	tw.set_parallel(true)
	tw.tween_property(p, "position:y", p.position.y - randf_range(8, 15), 0.4)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_property(p, "scale", Vector2(2.0, 2.0), 0.4)
	tw.chain().tween_callback(p.queue_free)
"""
	fb_script.reload()
	fireball.set_script(fb_script)
	fireball.direction = aim
	fireball.speed = 200.0
	fireball.damage = damage
	fireball.owner_index = player_index
	fireball.lifetime = 3.0

	get_parent().add_child(fireball)

# -- Remaining class forwarders -----------------------------------------------

var _rogue_class: Variant = null
var _demolitionist_class: Variant = null
var _healer_class: Variant = null
var _summoner_class: Variant = null
var _guitarist_class: Variant = null
var _werewolf_class: Variant = null

func _handle_delegate_toggle() -> void:
	if _summoner_class:
		_summoner_class._handle_delegate_toggle()

func _exit_delegate_mode() -> void:
	if _summoner_class:
		_summoner_class._exit_delegate_mode()

func _spawn_aether_rift(pos: Vector2) -> void:
	if _summoner_class:
		_summoner_class._spawn_aether_rift(pos)

func _update_delegate(delta: float) -> void:
	if _summoner_class:
		_summoner_class._update_delegate(delta)

func _check_werewolf_pounce_landing() -> void:
	if _werewolf_class:
		_werewolf_class._check_werewolf_pounce_landing()

func _get_aim_direction_analog() -> Vector2:
	## Returns full analog aim direction. Right stick takes priority over left.
	## Falls back to _get_aim_direction() for keyboard or if both sticks are neutral.
	# AI aim override — persists as long as AI is active
	if _ai_active:
		return _ai_aim
	if device_id >= 0:
		# Right stick priority
		var right_stick := Vector2(
			Input.get_joy_axis(device_id, JOY_AXIS_RIGHT_X),
			Input.get_joy_axis(device_id, JOY_AXIS_RIGHT_Y)
		)
		if right_stick.length() > 0.2:
			return right_stick.normalized()
		# Fall back to left stick
		var left_stick := Vector2(
			Input.get_joy_axis(device_id, JOY_AXIS_LEFT_X),
			Input.get_joy_axis(device_id, JOY_AXIS_LEFT_Y)
		)
		if left_stick.length() > 0.2:
			return left_stick.normalized()
	return _get_aim_direction()


func _get_aim_direction() -> Vector2:
	## Returns the direction the player is aiming with D-pad/stick.
	## Falls back to facing direction if no directional input.
	var aim := Vector2.ZERO
	if _is_device_action_pressed("move_left"):
		aim.x -= 1.0
	if _is_device_action_pressed("move_right"):
		aim.x += 1.0
	if _is_device_action_pressed("move_up"):
		aim.y -= 1.0
	if _is_device_action_pressed("move_down"):
		aim.y += 1.0
	if aim == Vector2.ZERO:
		aim = Vector2(1.0 if _facing_right else -1.0, 0.0)
	else:
		aim = aim.normalized()
		# Update facing based on aim
		if aim.x != 0.0:
			_facing_right = aim.x > 0.0
			sprite.flip_h = not _facing_right
	return aim


func _spawn_projectile(damage: int, speed: float, type: String) -> void:
	var projectile_scene := load("res://scenes/characters/projectile.tscn") as PackedScene
	if not projectile_scene:
		return
	var aim: Vector2 = _get_aim_direction()
	var proj := projectile_scene.instantiate()
	proj.damage = damage
	proj.speed = speed
	proj.direction = aim
	proj.projectile_type = type
	proj.owner_index = player_index
	proj.global_position = global_position + aim * 16.0
	get_parent().add_child(proj)


func _handle_special() -> void:
	if _special_cooldown > 0.0:
		return
	if not _is_device_action_just_pressed("special"):
		return
	# Special (Triangle) is fine during all states — no conflict with slide (Circle/interact)

	# Apply special cooldown reduction from skill level
	var cooldown_reduction: float = PlayerManager.get_skill_level_for(player_index, "special") * 0.02
	_special_cooldown = cfg("special_cooldown", SPECIAL_COOLDOWN_TIME) * (1.0 - cooldown_reduction)
	PlayerManager.add_skill_xp(player_index, "special", 7)
	_perform_special()


func _perform_special() -> void:
	var fn: Variant = _class_special_fn.get(character_class)
	if fn is Callable:
		fn.call({})


var _shield_charging: bool = false
func _special_grappling_hook() -> void:
	# Grapple moved to left bumper — this is now a no-op for the special button
	pass
func _rumble(weak: float, strong: float, duration: float) -> void:
	## Trigger controller vibration. No-op for keyboard (device -1).
	if device_id >= 0:
		Input.start_joy_vibration(device_id, weak, strong, duration)


func _stop_rumble() -> void:
	if device_id >= 0:
		Input.stop_joy_vibration(device_id)


func _update_controller_led() -> void:
	## Set controller LED to match the player's class color
	if device_id < 0:
		return
	var colors := {
		PlayerManager.CharacterClass.MELEE: Color(0.9, 0.3, 0.2),
		PlayerManager.CharacterClass.RANGED: Color(0.2, 0.8, 0.3),
		PlayerManager.CharacterClass.MAGE: Color(0.3, 0.4, 0.95),
		PlayerManager.CharacterClass.SUMMONER: Color(0.8, 0.5, 0.9),
		PlayerManager.CharacterClass.ROGUE: Color(0.95, 0.85, 0.2),
		PlayerManager.CharacterClass.DEMOLITIONIST: Color(0.9, 0.6, 0.1),
		PlayerManager.CharacterClass.HEALER: Color(0.3, 0.9, 0.4),
		PlayerManager.CharacterClass.TANK: Color(0.6, 0.5, 0.35),
		PlayerManager.CharacterClass.NINJA: Color(0.2, 0.9, 0.9),
		PlayerManager.CharacterClass.BALLOONIST: Color(0.9, 0.4, 0.7),
		PlayerManager.CharacterClass.GUITARIST: Color(0.9, 0.7, 0.2),
		PlayerManager.CharacterClass.WEREWOLF: Color(0.5, 0.3, 0.15),
		PlayerManager.CharacterClass.EXECUTIONER: Color(0.15, 0.1, 0.1),
	}
	var led_color: Color = colors.get(character_class, Color.WHITE)
	# Use call() to avoid parse error if set_joy_light doesn't exist in this build
	if Input.has_method("set_joy_light"):
		Input.call("set_joy_light", device_id, led_color)
func _draw_debug_arrow(from: Vector2, to: Vector2, col: Color, width: float) -> void:
	## Draw a line with an arrowhead at the end.
	draw_line(from, to, col, width)
	var dir: Vector2 = (to - from).normalized()
	if dir.length_squared() < 0.001:
		return
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var head_size: float = 6.0
	draw_line(to, to - dir * head_size + perp * head_size * 0.5, col, width * 0.8)
	draw_line(to, to - dir * head_size - perp * head_size * 0.5, col, width * 0.8)


func _draw_hud_popup_indicator() -> void:
	## Draw color-matched starburst aura around player when HUD popup is active
	if not PlayerHUD:
		return

	var popup_active: bool = PlayerHUD._hud_popups.has(player_index)
	if popup_active:
		_hud_aura_fade = 1.0
	elif _hud_aura_fade > 0.0:
		_hud_aura_fade -= get_process_delta_time()
		if _hud_aura_fade <= 0.0:
			_hud_aura_fade = 0.0
			return
	else:
		return

	var aura_alpha: float = clampf(_hud_aura_fade, 0.0, 1.0)
	var class_color: Color = PlayerHUD.CLASS_COLORS.get(character_class, Color.WHITE)
	var t: float = Time.get_ticks_msec() * 0.001

	# Outer layer (dimmer, larger)
	var outer_rays: int = 12
	for i in range(outer_rays):
		var angle: float = float(i) / float(outer_rays) * TAU + t * 0.5
		var sparkle: float = 0.5 + 0.5 * sin(t * 4.0 + i * 1.3)
		var inner_r: float = 20.0
		var outer_r: float = 32.0 + sparkle * 8.0
		var col := class_color * Color(1, 1, 1, (0.2 + sparkle * 0.15) * aura_alpha)
		draw_line(Vector2(cos(angle) * inner_r, sin(angle) * inner_r),
				  Vector2(cos(angle) * outer_r, sin(angle) * outer_r), col, 2.0)

	# Inner layer (brighter, smaller)
	var inner_rays: int = 8
	for i in range(inner_rays):
		var angle: float = float(i) / float(inner_rays) * TAU - t * 0.8
		var sparkle: float = 0.5 + 0.5 * sin(t * 6.0 + i * 2.1)
		var inner_r: float = 14.0
		var outer_r: float = 22.0 + sparkle * 5.0
		var col := class_color * Color(1.2, 1.2, 1.2, (0.3 + sparkle * 0.2) * aura_alpha)
		draw_line(Vector2(cos(angle) * inner_r, sin(angle) * inner_r),
				  Vector2(cos(angle) * outer_r, sin(angle) * outer_r), col, 1.5)

	# Glow circle
	draw_circle(Vector2.ZERO, 16.0, class_color * Color(1, 1, 1, (0.08 + 0.04 * sin(t * 3.0)) * aura_alpha))


func _draw_debug() -> void:
	# Always tick down tracers regardless of debug state
	var dt: float = get_process_delta_time()
	var i: int = _debug_tracers.size() - 1
	while i >= 0:
		_debug_tracers[i]["time"] -= dt
		if _debug_tracers[i]["time"] <= 0.0:
			_debug_tracers.remove_at(i)
		i -= 1

	# Jump tracers — lingering snapshots from jump releases
	if DebugOverlay.should_draw("player/jump_tracers", self):
		for ti in range(_debug_tracers.size()):
			var tracer: Dictionary = _debug_tracers[ti]
			var tpos: Vector2 = tracer["pos"] - global_position
			var fade: float = clampf(tracer["time"] / 3.0, 0.1, 1.0)
			var scale_f: float = 0.12

			# Pre-velocity (green)
			var pre: Vector2 = tracer["pre_vel"]
			if pre.length() > 5.0:
				var pend: Vector2 = tpos + pre.normalized() * clampf(pre.length() * scale_f, 5.0, 80.0)
				draw_line(tpos, pend, Color(0.2, 0.8, 0.2, 0.5 * fade), 1.5)

			# Jump impulse (yellow)
			var imp: Vector2 = tracer["impulse"]
			if imp.length() > 5.0:
				var iend: Vector2 = tpos + imp.normalized() * clampf(imp.length() * scale_f, 5.0, 80.0)
				draw_line(tpos, iend, Color(1.0, 1.0, 0.2, 0.7 * fade), 2.0)

			# Post-velocity / actual result (cyan, thick)
			var post: Vector2 = tracer["post_vel"]
			if post.length() > 5.0:
				var oend: Vector2 = tpos + post.normalized() * clampf(post.length() * scale_f, 5.0, 100.0)
				draw_line(tpos, oend, Color(0.2, 0.9, 1.0, 0.8 * fade), 3.0)
				var odir: Vector2 = post.normalized()
				var operp: Vector2 = Vector2(-odir.y, odir.x)
				draw_line(oend, oend - odir * 8.0 + operp * 5.0, Color(0.2, 0.9, 1.0, 0.8 * fade), 2.5)
				draw_line(oend, oend - odir * 8.0 - operp * 5.0, Color(0.2, 0.9, 1.0, 0.8 * fade), 2.5)

			# Speed label
			draw_string(ThemeDB.fallback_font, tpos + Vector2(5, -10),
				"v:%d +j:%d = %d" % [int(pre.length()), int(imp.length()), int(post.length())],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1.0, 1.0, 1.0, 0.7 * fade))

	# Slide debug visuals — impact radius during swing, decomposition during slide
	if DebugOverlay.should_draw("player/slide", self):
		var scale_f: float = 0.15
		if _grapple_state in [GrappleState.SWINGING, GrappleState.CONNECTED,
							  GrappleState.TETHER_WINDUP, GrappleState.TETHER_THROWN]:
			# Show impact detection radius as a dashed circle
			var r: float = 48.0  # SLIDE_IMPACT_RADIUS
			var segments: int = 16
			for si in range(segments):
				if si % 2 == 0:
					var a1: float = float(si) / float(segments) * TAU
					var a2: float = float(si + 1) / float(segments) * TAU
					draw_line(Vector2(cos(a1) * r, sin(a1) * r),
							  Vector2(cos(a2) * r, sin(a2) * r),
							  Color(1.0, 0.8, 0.2, 0.3), 1.0)
			if velocity.length() > 10:
				var probe_dir: Vector2 = velocity.normalized() * r
				draw_line(Vector2.ZERO, probe_dir, Color(1.0, 0.8, 0.2, 0.2), 1.0)

		if _grapple_state in [GrappleState.SLIDE, GrappleState.SLIDE_FREE]:
			# -- Charge ring (gameplay visual) --
			var charge_pct: float = 0.0
			var ranger_cls = get_node_or_null("ClassComponent")
			if ranger_cls and "_slide_charge_mod" in ranger_cls and ranger_cls._slide_charge_mod:
				charge_pct = ranger_cls._slide_charge_mod.get_progress()
			var ring_r: float = 20.0
			var ring_sweep: float = charge_pct * TAU
			var ring_col: Color = Color(1.0, 1.0, 0.2).lerp(Color(1.0, 0.5, 0.1), charge_pct)
			if charge_pct >= 0.95:
				ring_col = Color(1.0, 1.0, 1.0)  # White-hot at max
			var ring_width: float = lerpf(2.0, 4.0, charge_pct)
			if ring_sweep > 0.05:
				draw_arc(Vector2.ZERO, ring_r, -PI * 0.5, -PI * 0.5 + ring_sweep, 24, ring_col, ring_width)

			# -- Surface contact indicator --
			var on_surf: bool = true
			if ranger_cls and "_slide_on_surface" in ranger_cls:
				on_surf = ranger_cls._slide_on_surface
			if not on_surf:
				# Off surface: red X
				draw_line(Vector2(-6, -6), Vector2(6, 6), Color(1.0, 0.2, 0.2, 0.6), 2.0)
				draw_line(Vector2(6, -6), Vector2(-6, 6), Color(1.0, 0.2, 0.2, 0.6), 2.0)

			# -- Debug vectors --
			# YELLOW: full slide velocity
			var vel_end: Vector2 = _slide_velocity * scale_f
			if vel_end.length() > 3:
				_draw_debug_arrow(Vector2.ZERO, vel_end, Color(1.0, 1.0, 0.2, 0.8), 2.5)
			# GREEN: surface normal (constant size)
			var norm_end: Vector2 = _slide_surface_normal * 40.0
			_draw_debug_arrow(Vector2.ZERO, norm_end, Color(0.2, 1.0, 0.2, 0.7), 2.0)
			# BLUE: surface-parallel velocity
			var par_end: Vector2 = _slide_surface_tangent * _slide_velocity.length() * scale_f
			if par_end.length() > 3:
				_draw_debug_arrow(Vector2.ZERO, par_end, Color(0.3, 0.5, 1.0, 0.7), 2.0)
			# RED: predicted launch with current charge multiplier
			var charge_mult: float = cfg("ranger_slide_charge_mult", 1.0)
			var predicted_launch: Vector2 = _slide_velocity * charge_mult
			var pred_end: Vector2 = predicted_launch * scale_f
			if pred_end.length() > 3:
				_draw_debug_arrow(Vector2.ZERO, pred_end, Color(1.0, 0.3, 0.2, 0.6), 2.0)
			# Surface line (white, thin)
			var surf_line: Vector2 = _slide_surface_tangent * 60.0
			draw_line(-surf_line, surf_line, Color(1.0, 1.0, 1.0, 0.15), 1.0)
			# Speed + charge label
			var state_str: String = "FREE" if _grapple_state == GrappleState.SLIDE_FREE else "ROPE"
			var surf_str: String = "SURFACE" if on_surf else "AIRBORNE"
			draw_string(ThemeDB.fallback_font, Vector2(5, -28),
				"slide: %.0f px/s  ×%.2f  %s %s" % [_slide_velocity.length(), charge_mult, state_str, surf_str],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1.0, 1.0, 0.5, 0.8))
			draw_string(ThemeDB.fallback_font, Vector2(5, -18),
				"charge: %.0f%%  gravity_component: %.1f" % [charge_pct * 100.0, _slide_surface_tangent.dot(Vector2.DOWN)],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.7, 0.7, 0.5, 0.7))

	# Current velocity arrow (green) + predicted jump arrow (red)
	if DebugOverlay.should_draw("player/velocity_arrows", self):
		if velocity.length() > 5.0:
			var vel_dir: Vector2 = velocity.normalized()
			var vel_len: float = clampf(velocity.length() * 0.15, 10.0, 120.0)
			var vel_end: Vector2 = vel_dir * vel_len
			draw_line(Vector2.ZERO, vel_end, Color(0.2, 1.0, 0.2, 0.7), 2.0)

		# Predicted jump-release velocity arrow (red) — only while grapple connected
		if _grapple_state in [GrappleState.SWINGING, GrappleState.CONNECTED]:
			var aim: Vector2 = _get_aim_direction_analog()
			var predicted: Vector2 = velocity + aim * abs(JUMP_VELOCITY)
			if predicted.length() > 5.0:
				var pred_dir: Vector2 = predicted.normalized()
				var pred_len: float = clampf(predicted.length() * 0.15, 10.0, 150.0)
				var pred_end: Vector2 = pred_dir * pred_len
				draw_line(Vector2.ZERO, pred_end, Color(1.0, 0.15, 0.1, 0.8), 2.5)
				var perp: Vector2 = Vector2(-pred_dir.y, pred_dir.x)
				draw_line(pred_end, pred_end - pred_dir * 10.0 + perp * 6.0, Color(1.0, 0.15, 0.1, 0.8), 2.5)
				draw_line(pred_end, pred_end - pred_dir * 10.0 - perp * 6.0, Color(1.0, 0.15, 0.1, 0.8), 2.5)
				var speed_text: String = "%d" % int(predicted.length())
				draw_string(ThemeDB.fallback_font, pred_end + Vector2(5, -5), speed_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.3, 0.2, 0.9))
func _check_out_of_bounds() -> void:
	## Teleport player back in-bounds if they escape the playable area
	# Skip during YEET launch — player is flying on the chain
	if _exec_yeet_immunity > 0.0:
		return
	# Skip while executioner ball is active AND player is chained (not entity-yeet mode)
	if character_class == PlayerManager.CharacterClass.EXECUTIONER:
		if not _exec_is_entity_yeet_mode():
			if _exec_ball_state in [ExecEndState.THROWN, ExecEndState.STUCK_WALL, ExecEndState.STUCK_PLATFORM, ExecEndState.STUCK_CEILING]:
				return
	var cam = get_viewport().get_camera_2d()
	if not cam:
		return

	var vp_size: Vector2 = get_viewport_rect().size
	var zoom: Vector2 = cam.zoom if cam.zoom.x > 0 else Vector2.ONE
	var half_view: Vector2 = vp_size / (2.0 * zoom)
	var cam_pos: Vector2 = cam.global_position

	# OOB margin: 2x the visible area in any direction
	var margin: float = 2.0
	var min_bound: Vector2 = cam_pos - half_view * margin
	var max_bound: Vector2 = cam_pos + half_view * margin

	if global_position.x >= min_bound.x and global_position.x <= max_bound.x \
		and global_position.y >= min_bound.y and global_position.y <= max_bound.y:
		return  # In bounds

	# Out of bounds — find teleport target
	var target_pos: Vector2 = cam_pos  # Default: center of screen

	# Try to find nearest other player
	var best_dist: float = INF
	for node in get_tree().get_nodes_in_group("players"):
		if node == self or not node is Node2D:
			continue
		if not is_instance_valid(node):
			continue
		var dist: float = cam_pos.distance_to(node.global_position)
		if dist < best_dist:
			best_dist = dist
			target_pos = node.global_position

	# Spawn purple rift at origin (where we were)
	_spawn_aether_rift(global_position)

	# Teleport
	global_position = target_pos + Vector2(randf_range(-20, 20), -10)
	velocity = Vector2.ZERO

	# Spawn purple rift at destination
	_spawn_aether_rift(global_position)

	AudioManager.play("summon", -2.0, 1.2)
func take_damage(amount: int, source_index: int = -1) -> void:
	if _shadow_dash_active or _is_dead:
		return

	# Delegate mode: summoner takes extra damage
	if _delegate_active:
		amount = int(amount * DELEGATE_DMG_MULT)
		# Getting hit hard while delegating cancels it
		if amount >= 15:
			_exit_delegate_mode()

	# Rogue stealth: ignore 50% of damage
	if _rogue_stealth:
		amount = int(amount * 0.5)

	# Tank fortify: ignore 60% of damage
	if _tank_fortify:
		amount = int(amount * 0.4)

	# Stagger: extra damage while staggered
	if _is_staggered:
		amount = int(amount * STAGGER_DAMAGE_MULT)

	# Block/Parry check
	if _is_blocking:
		var time_since_block: float = Time.get_ticks_msec() / 1000.0 - _block_start_time
		if time_since_block < PARRY_WINDOW:
			# PERFECT PARRY - no damage, stun attacker, bright flash
			AudioManager.play("sword_slash", 4.0, 1.5)
			_spawn_vfx(Color(1.0, 1.0, 1.0, 0.9), Vector2(48, 48))
			modulate = Color(1.0, 1.0, 0.8)
			var parry_tween := create_tween()
			parry_tween.tween_property(self, "modulate", Color.WHITE, 0.15)
			PlayerManager.add_skill_xp(player_index, "block", 15)
			# Stun the attacker if we can find them
			if source_index >= 0:
				_stun_source(source_index)
			return
		else:
			# Regular block - damage reduction scales with block level
			var block_reduction: float = 0.5 + PlayerManager.get_skill_level_for(player_index, "block") * 0.01
			amount = int(amount * (1.0 - block_reduction))
			PlayerManager.add_skill_xp(player_index, "block", 3)

	# Healer takes 25% more damage while channeling
	if _is_charging and character_class == PlayerManager.CharacterClass.HEALER:
		amount = int(amount * HEALER_CHANNEL_DMG_MULT)

	# Interrupt charge → apply stagger
	if _is_charging:
		# Healer channel interrupted: fire burst heal proportional to charge time
		if character_class == PlayerManager.CharacterClass.HEALER and _charge_time >= CHARGE_MIN:
			_healer_channel_burst()
		_healer_channel_stop_vfx()
		_apply_stagger()

	PlayerManager.damage_player(player_index, amount)
	_update_health_bar()

	var p_data := PlayerManager.get_player(player_index)
	if not p_data.is_empty() and p_data["health"] <= 0:
		_die()
		return

	AudioManager.play("player_hurt", -3.0)
	modulate = Color.RED
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.2)


func _die() -> void:
	_is_dead = true
	_revive_progress = 0.0
	AudioManager.play("player_die")
	# Remove from players group so enemies stop targeting us
	remove_from_group("players")
	# Ghost appearance
	modulate = Color(0.5, 0.5, 0.8, 0.4)
	collision_layer = 0  # Can't be hit
	# Disable attacks
	if attack_area:
		attack_area.monitoring = false

	# Add revive prompt above head
	var revive_label := Label.new()
	revive_label.name = "ReviveLabel"
	revive_label.text = "PRESS JUMP TO REVIVE"
	revive_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	revive_label.add_theme_font_size_override("font_size", 8)
	revive_label.position = Vector2(-50, -36)
	revive_label.modulate = Color.YELLOW
	add_child(revive_label)

	# Add revive progress bar
	var revive_bar := HEALTH_BAR_SCENE.instantiate()
	revive_bar.name = "ReviveBar"
	revive_bar.bar_width = 28.0
	revive_bar.bar_height = 3.0
	revive_bar.bar_offset = Vector2(0, -30)
	revive_bar.fill_color = Color(1.0, 0.9, 0.2)
	revive_bar.damage_color = Color(0.3, 0.3, 0.1)
	add_child(revive_bar)
	revive_bar.set_health(0, REVIVE_TIME)


func _check_revive(delta: float) -> void:
	if not _is_dead:
		return

	# Solo self-revive: if no other alive players exist, press jump to revive
	var alive_teammates: int = 0
	for p in get_tree().get_nodes_in_group("players"):
		if p == self or not (p is CharacterBody2D):
			continue
		if not p.get("_is_dead"):
			alive_teammates += 1

	if alive_teammates == 0:
		if _is_device_action_just_pressed("jump"):
			_revive()
			return

	# Auto-revive when any alive player stands nearby
	var teammate_nearby := false
	for p in get_tree().get_nodes_in_group("players"):
		if p == self or not (p is CharacterBody2D):
			continue
		if p.get("_is_dead"):
			continue
		var dist: float = global_position.distance_to(p.global_position)
		if dist < REVIVE_RANGE:
			teammate_nearby = true
			break

	var revive_bar := get_node_or_null("ReviveBar")
	if teammate_nearby:
		_revive_progress += delta
		if revive_bar:
			revive_bar.set_health(_revive_progress, REVIVE_TIME)
		if _revive_progress >= REVIVE_TIME:
			_revive()
	else:
		_revive_progress = maxf(0.0, _revive_progress - delta * 0.5)
		if revive_bar:
			revive_bar.set_health(_revive_progress, REVIVE_TIME)


func _revive() -> void:
	_is_dead = false
	_revive_progress = 0.0
	AudioManager.play("player_revive")
	add_to_group("players")  # Re-visible to enemies
	collision_layer = 2
	modulate = Color.WHITE

	# Restore health to 50%
	var p_data := PlayerManager.get_player(player_index)
	if not p_data.is_empty():
		p_data["health"] = int(p_data["max_health"] * 0.5)
		p_data["is_alive"] = true
	_update_health_bar()

	# Remove revive UI
	var revive_label := get_node_or_null("ReviveLabel")
	if revive_label:
		revive_label.queue_free()
	var revive_bar := get_node_or_null("ReviveBar")
	if revive_bar:
		revive_bar.queue_free()

	# Flash gold on revive
	modulate = Color(1.0, 0.9, 0.3)
	_spawn_vfx(Color(1.0, 0.9, 0.3, 0.6), Vector2(40, 40))
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.5)


func _setup_health_bar() -> void:
	_health_bar = HEALTH_BAR_SCENE.instantiate()
	_health_bar.bar_width = 28.0
	_health_bar.bar_height = 3.0
	_health_bar.bar_offset = Vector2(0, -22)
	_health_bar.hide_when_full = false
	add_child(_health_bar)
	_update_health_bar()


func _setup_mana_bar() -> void:
	var p_data := PlayerManager.get_player(player_index)
	if p_data.is_empty() or p_data["max_mana"] <= 0:
		return
	_mana_bar = HEALTH_BAR_SCENE.instantiate()
	_mana_bar.bar_width = 28.0
	_mana_bar.bar_height = 2.0
	_mana_bar.bar_offset = Vector2(0, -18)
	_mana_bar.fill_color = Color(0.2, 0.4, 1.0)
	_mana_bar.damage_color = Color(0.1, 0.15, 0.4)
	add_child(_mana_bar)
	_mana_bar.set_health(p_data["mana"], p_data["max_mana"])


func _update_health_bar() -> void:
	var p_data := PlayerManager.get_player(player_index)
	if p_data.is_empty():
		return
	if _health_bar:
		_health_bar.set_health(p_data["health"], p_data["max_health"])
	if _mana_bar:
		_mana_bar.set_health(p_data["mana"], p_data["max_mana"])
func _spawn_vfx(color: Color, size: Vector2) -> void:
	var vfx := ColorRect.new()
	vfx.color = color
	vfx.size = size
	vfx.position = global_position - size / 2.0
	get_parent().add_child(vfx)
	var tween := vfx.create_tween()
	tween.set_parallel(true)
	tween.tween_property(vfx, "scale", Vector2(2.0, 2.0), 0.3)
	tween.tween_property(vfx, "modulate:a", 0.0, 0.3)
	tween.chain().tween_callback(vfx.queue_free)


func _spawn_swing_arc(reach: float, color: Color) -> void:
	# Wide thin arc VFX at attack position
	var arc := ColorRect.new()
	arc.color = color
	arc.size = Vector2(reach * 2.5, 6)
	var arc_offset_x: float = reach * 0.8 if _facing_right else -reach * 0.8 - reach * 2.5
	arc.position = global_position + Vector2(arc_offset_x, -3.0)
	arc.pivot_offset = Vector2(0.0 if _facing_right else reach * 2.5, 3.0)
	get_parent().add_child(arc)
	var tween := arc.create_tween()
	tween.set_parallel(true)
	tween.tween_property(arc, "scale:y", 2.5, 0.15)
	tween.tween_property(arc, "modulate:a", 0.0, 0.15)
	tween.chain().tween_callback(arc.queue_free)


func _spawn_expanding_ring(center: Vector2, max_radius: float, color: Color, duration: float) -> void:
	var ring := ColorRect.new()
	ring.color = color
	ring.size = Vector2(max_radius * 2.0, max_radius * 2.0)
	ring.position = center - Vector2(max_radius, max_radius)
	ring.scale = Vector2(0.1, 0.1)
	ring.pivot_offset = Vector2(max_radius, max_radius)
	get_parent().add_child(ring)
	var tween := ring.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector2(1.0, 1.0), duration)
	tween.tween_property(ring, "modulate:a", 0.0, duration)
	tween.chain().tween_callback(ring.queue_free)


func _screen_shake(intensity: float, duration: float) -> void:
	var camera = get_viewport().get_camera_2d()
	if not camera:
		return
	var original_offset: Vector2 = camera.offset
	var shake_tween := create_tween()
	var steps: int = int(duration / 0.03)
	for i in range(steps):
		var shake_x: float = randf_range(-intensity, intensity)
		var shake_y: float = randf_range(-intensity, intensity)
		shake_tween.tween_property(camera, "offset", original_offset + Vector2(shake_x, shake_y), 0.03)
	shake_tween.tween_property(camera, "offset", original_offset, 0.03)


# -- Block / Parry -------------------------------------------------------------

func _handle_block() -> void:
	# Ranger uses block button for RUN — skip block/parry
	if character_class == PlayerManager.CharacterClass.RANGED:
		return
	var pressing_block: bool = _is_device_action_pressed("block")
	if pressing_block and not _is_blocking:
		# Start blocking
		_is_blocking = true
		_block_start_time = Time.get_ticks_msec() / 1000.0
		# Spawn shield VFX in front of character
		if _block_shield_vfx == null or not is_instance_valid(_block_shield_vfx):
			_block_shield_vfx = ColorRect.new()
			_block_shield_vfx.color = Color(0.4, 0.7, 1.0, 0.4)
			_block_shield_vfx.size = Vector2(8, 28)
			add_child(_block_shield_vfx)
		_block_shield_vfx.visible = true
		_block_shield_vfx.position = Vector2(14.0 if _facing_right else -22.0, -14.0)
	elif pressing_block and _is_blocking:
		# Update shield position while blocking
		if _block_shield_vfx and is_instance_valid(_block_shield_vfx):
			_block_shield_vfx.position = Vector2(14.0 if _facing_right else -22.0, -14.0)
	elif not pressing_block and _is_blocking:
		# Stop blocking
		_is_blocking = false
		if _block_shield_vfx and is_instance_valid(_block_shield_vfx):
			_block_shield_vfx.visible = false


func _stun_source(source_idx: int) -> void:
	# Find the attacker (player or enemy) by source_index and stagger/stun them
	for body in get_tree().get_nodes_in_group("enemies"):
		if body.has_method("apply_stun"):
			if body is Node2D:
				var dist: float = global_position.distance_to(body.global_position)
				if dist < 60.0:
					body.apply_stun(1.0)
	for p in get_tree().get_nodes_in_group("players"):
		if p == self:
			continue
		if p.has_method("_apply_stagger") and p.get("player_index") == source_idx:
			p._apply_stagger()


# -- Stagger -------------------------------------------------------------------

func _apply_stagger() -> void:
	_is_staggered = true
	_stagger_timer = STAGGER_DURATION
	_is_charging = false
	_charge_time = 0.0
	_healer_channel_stop_vfx()
	AudioManager.play("player_hurt", 0.0, 0.5)
	modulate = Color(1.0, 1.0, 0.5)
	# Spawn star VFX above head
	var stars := Label.new()
	stars.name = "StaggerStars"
	stars.text = "***"
	stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stars.add_theme_font_size_override("font_size", 10)
	stars.position = Vector2(-12, -34)
	stars.modulate = Color.YELLOW
	add_child(stars)


# -- Charge system moved to ChargeComponent ---

func _charged_ranged_shot(charge_ratio: float) -> void:
	var damage: int = int(lerpf(20.0, 50.0, charge_ratio))
	AudioManager.play("crossbow_shoot", 2.0, 0.7)
	_spawn_vfx(Color(0.8, 0.8, 0.2, 0.6), Vector2(20, 12))
	var projectile_scene := load("res://scenes/characters/projectile.tscn") as PackedScene
	if not projectile_scene:
		return
	var proj := projectile_scene.instantiate()
	proj.damage = damage
	proj.speed = 450.0
	proj.direction = Vector2(1.0 if _facing_right else -1.0, 0.0)
	proj.projectile_type = "crossbow_bolt"
	proj.owner_index = player_index
	if proj.has_method("set_piercing"):
		proj.set_piercing(true)
	proj.global_position = global_position + Vector2(16.0 if _facing_right else -16.0, 0.0)
	proj.scale = Vector2(1.5 + charge_ratio, 1.5 + charge_ratio)
	get_parent().add_child(proj)
func _spawn_fragment_bomb(pos: Vector2, damage: int) -> void:
	var frag_vfx := ColorRect.new()
	frag_vfx.color = Color(1.0, 0.6, 0.1, 0.7)
	frag_vfx.size = Vector2(8, 8)
	frag_vfx.position = pos - Vector2(4, 4)
	get_parent().add_child(frag_vfx)

	await get_tree().create_timer(0.3).timeout
	if not is_inside_tree():
		return
	AudioManager.play("explosion", -6.0, 1.6)
	frag_vfx.color = Color(1.0, 0.3, 0.0, 0.9)
	frag_vfx.size = Vector2(24, 24)
	frag_vfx.position = pos - Vector2(12, 12)
	for body in get_tree().get_nodes_in_group("enemies"):
		if not body is Node2D:
			continue
		var dist: float = pos.distance_to(body.global_position)
		if dist < 30.0 and body.has_method("take_damage"):
			body.take_damage(damage, player_index)
	var tween := frag_vfx.create_tween()
	tween.tween_property(frag_vfx, "modulate:a", 0.0, 0.2)
	tween.tween_callback(frag_vfx.queue_free)
func _healer_channel_burst() -> void:
	var charge_ratio: float = clampf((_charge_time - CHARGE_MIN) / (CHARGE_MAX - CHARGE_MIN), 0.0, 1.0)
	var burst_radius: float = lerpf(HEALER_BURST_MIN_RADIUS, HEALER_BURST_MAX_RADIUS, charge_ratio)
	var burst_heal: int = int(lerpf(float(HEALER_BURST_MIN_HEAL), float(HEALER_BURST_MAX_HEAL), charge_ratio))

	AudioManager.play("player_revive", 0.0, 1.2)
	_spawn_expanding_ring(global_position, burst_radius, Color(0.2, 1.0, 0.3, 0.7), 0.4)
	_spawn_vfx(Color(0.3, 1.0, 0.4, 0.6), Vector2(burst_radius, burst_radius))

	# Heal all allies within burst radius
	for p in get_tree().get_nodes_in_group("players"):
		if not p is Node2D:
			continue
		var dist: float = global_position.distance_to(p.global_position)
		if dist < burst_radius and p.has_method("receive_heal"):
			p.receive_heal(burst_heal)
	# Self heal
	receive_heal(burst_heal)


func _healer_channel_heal_tick() -> void:
	# Heal nearby allies for ~5 HP/sec (this fires every 0.2s = 1 HP per tick)
	# Scale with proximity: closer = more healing
	var heal_per_tick: float = HEALER_CHANNEL_HPS * 0.2
	for p in get_tree().get_nodes_in_group("players"):
		if not p is Node2D:
			continue
		if p.get("_is_dead"):
			continue
		var dist: float = global_position.distance_to(p.global_position)
		if dist < HEALER_CHANNEL_RADIUS:
			# Proximity scaling: 100% at point blank, 50% at edge
			var proximity_scale: float = lerpf(1.0, 0.5, dist / HEALER_CHANNEL_RADIUS)
			var heal_amount: int = int(heal_per_tick * proximity_scale)
			if heal_amount < 1:
				heal_amount = 1
			var p_idx: int = p.get("player_index")
			PlayerManager.heal_player(p_idx, heal_amount)
			# Small green line VFX to each healed ally (skip self)
			if p != self:
				_spawn_heal_beam(p)


func _spawn_heal_beam(target: Node2D) -> void:
	var beam := ColorRect.new()
	beam.color = Color(0.3, 1.0, 0.4, 0.4)
	var dir_to_target: Vector2 = target.global_position - global_position
	var beam_len: float = dir_to_target.length()
	beam.size = Vector2(beam_len, 2)
	beam.position = global_position
	beam.rotation = dir_to_target.angle()
	get_parent().add_child(beam)
	var beam_tween := beam.create_tween()
	beam_tween.tween_property(beam, "modulate:a", 0.0, 0.15)
	beam_tween.tween_callback(beam.queue_free)


func _healer_channel_start_vfx() -> void:
	# Soft green glow around healer
	if _healer_channel_glow == null or not is_instance_valid(_healer_channel_glow):
		_healer_channel_glow = ColorRect.new()
		_healer_channel_glow.color = Color(0.2, 0.8, 0.3, 0.2)
		_healer_channel_glow.size = Vector2(48, 48)
		_healer_channel_glow.position = Vector2(-24, -24)
		_healer_channel_glow.z_index = -1
		add_child(_healer_channel_glow)


func _healer_channel_update_vfx(charge_ratio: float) -> void:
	if _healer_channel_glow and is_instance_valid(_healer_channel_glow):
		# Pulse the glow size
		var pulse_scale: float = 1.0 + sin(_charge_time * 3.0) * 0.15
		var base_size: float = lerpf(48.0, 72.0, charge_ratio)
		_healer_channel_glow.size = Vector2(base_size, base_size) * pulse_scale
		_healer_channel_glow.position = -_healer_channel_glow.size / 2.0
		_healer_channel_glow.color = Color(0.2, 0.8, 0.3, 0.15 + charge_ratio * 0.15)


func _healer_channel_stop_vfx() -> void:
	if _healer_channel_glow and is_instance_valid(_healer_channel_glow):
		_healer_channel_glow.queue_free()
		_healer_channel_glow = null


func receive_heal(amount: int) -> void:
	var p_data := PlayerManager.get_player(player_index)
	if p_data.is_empty():
		return
	p_data["health"] = mini(p_data["health"] + amount, p_data["max_health"])
	_update_health_bar()
	modulate = Color(0.4, 1.0, 0.4)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.2)


# -- Dash Wave -----------------------------------------------------------------

func _spawn_dash_wave(start_pos: Vector2, dash_dir: Vector2, damage: int) -> void:
	var perp_dir := Vector2(-dash_dir.y, dash_dir.x)

	var wave := ColorRect.new()
	wave.color = Color(0.6, 0.8, 1.0, 0.5)
	wave.size = Vector2(4, 40)
	var mid_pos: Vector2 = (start_pos + global_position) * 0.5
	wave.position = mid_pos - Vector2(2, 20)
	wave.rotation = atan2(perp_dir.y, perp_dir.x)
	get_parent().add_child(wave)

	var wave_tween := wave.create_tween()
	wave_tween.set_parallel(true)
	wave_tween.tween_property(wave, "scale", Vector2(3.0, 2.5), 0.3)
	wave_tween.tween_property(wave, "modulate:a", 0.0, 0.3)
	wave_tween.chain().tween_callback(wave.queue_free)

	for body in get_tree().get_nodes_in_group("enemies"):
		if not body is Node2D:
			continue
		var dist: float = mid_pos.distance_to(body.global_position)
		if dist < 50.0 and body.has_method("take_damage"):
			body.take_damage(damage, player_index)
			if body.has_method("apply_knockback"):
				var push_dir: Vector2 = (body.global_position - mid_pos).normalized()
				body.apply_knockback(push_dir * 120.0)
func _demolitionist_explode(pos: Vector2, damage: int, radius: float) -> void:
	AudioManager.play("explosion")

	# Impact aspect: knockback doubled, damage -30%
	var actual_damage: int = damage
	var knockback_mult: float = 1.0
	if _demo_aspect == "impact":
		actual_damage = int(damage * 0.7)
		knockback_mult = 2.0

	# VFX burst - aspect-tinted
	var burst_color: Color = Color(0.9, 0.6, 0.1, 0.8)
	if _demo_aspect == "electric":
		burst_color = Color(0.3, 0.5, 1.0, 0.8)
	elif _demo_aspect == "fire":
		burst_color = Color(1.0, 0.4, 0.0, 0.8)
	elif _demo_aspect == "impact":
		burst_color = Color(1.0, 1.0, 1.0, 0.9)
	elif _demo_aspect == "ice":
		burst_color = Color(0.5, 0.8, 1.0, 0.8)

	var vfx := ColorRect.new()
	vfx.color = burst_color
	vfx.size = Vector2(radius * 2, radius * 2)
	vfx.position = pos - Vector2(radius, radius)
	get_parent().add_child(vfx)
	var tween := vfx.create_tween()
	tween.set_parallel(true)
	tween.tween_property(vfx, "scale", Vector2(1.5, 1.5), 0.3)
	tween.tween_property(vfx, "modulate:a", 0.0, 0.3)
	tween.chain().tween_callback(vfx.queue_free)

	# Impact aspect: big white shockwave VFX
	if _demo_aspect == "impact":
		var shockwave := ColorRect.new()
		shockwave.color = Color(1.0, 1.0, 1.0, 0.5)
		shockwave.size = Vector2(radius * 3, radius * 3)
		shockwave.position = pos - Vector2(radius * 1.5, radius * 1.5)
		get_parent().add_child(shockwave)
		var sw_tween := shockwave.create_tween()
		sw_tween.set_parallel(true)
		sw_tween.tween_property(shockwave, "scale", Vector2(2.0, 2.0), 0.4)
		sw_tween.tween_property(shockwave, "modulate:a", 0.0, 0.4)
		sw_tween.chain().tween_callback(shockwave.queue_free)

	# Collect enemies hit for aspect effects
	var enemies_hit: Array[Node2D] = []

	# Damage enemies in radius
	for body in get_tree().get_nodes_in_group("enemies"):
		if not body is Node2D:
			continue
		var dist: float = pos.distance_to(body.global_position)
		if dist < radius and body.has_method("take_damage"):
			body.take_damage(actual_damage, player_index)
			enemies_hit.append(body)
			if body.has_method("apply_knockback"):
				var kb: Vector2 = (body.global_position - pos).normalized()
				body.apply_knockback(kb * 200.0 * knockback_mult)

	# Fire aspect: enemies catch fire - 5 damage/sec for 3s
	if _demo_aspect == "fire":
		for enemy in enemies_hit:
			_demo_apply_fire(enemy)

	# Ice aspect: enemies slowed to 30% speed for 3s
	if _demo_aspect == "ice":
		for enemy in enemies_hit:
			_demo_apply_ice(enemy)

	# Electric aspect: chain lightning to nearby enemies
	if _demo_aspect == "electric":
		_demo_chain_lightning(pos, enemies_hit)

	# Napalm: leave burning ground zone
	if _demo_napalm:
		_demo_spawn_napalm(pos)


func _demo_apply_fire(enemy: Node2D) -> void:
	if not is_instance_valid(enemy):
		return
	# Orange particle VFX on burning enemy
	var fire_vfx := ColorRect.new()
	fire_vfx.color = Color(1.0, 0.5, 0.0, 0.7)
	fire_vfx.size = Vector2(6, 8)
	fire_vfx.z_index = 10
	enemy.add_child(fire_vfx)
	fire_vfx.position = Vector2(-3, -20)

	var ticks: int = 6  # 3s at 0.5s intervals = 6 ticks of 5 damage (= 5 dps * 3s overall via ticks)
	var tick_interval: float = 0.5
	var dmg_per_tick: int = 3  # ~5 damage per second (3 per 0.5s ≈ 6/s, close enough; or use 2.5 rounded)
	# Actually 5 damage/sec for 3s = 15 total. 6 ticks * 2.5 = 15. Use 3,2,3,2,3,2 = 15.
	# Simpler: deal 5 damage every 1s for 3 ticks.
	var fire_ticks: int = 3
	var fire_interval: float = 1.0
	while fire_ticks > 0 and is_instance_valid(enemy) and is_inside_tree():
		await get_tree().create_timer(fire_interval).timeout
		if not is_instance_valid(enemy):
			break
		if enemy.has_method("take_damage"):
			enemy.take_damage(5, player_index)
		fire_ticks -= 1
		# Flicker fire VFX
		if is_instance_valid(fire_vfx):
			fire_vfx.modulate.a = 0.5 if fire_ticks % 2 == 0 else 0.9

	if is_instance_valid(fire_vfx):
		fire_vfx.queue_free()


func _demo_apply_ice(enemy: Node2D) -> void:
	if not is_instance_valid(enemy):
		return
	# Blue/white frost VFX
	var ice_vfx := ColorRect.new()
	ice_vfx.color = Color(0.5, 0.8, 1.0, 0.6)
	ice_vfx.size = Vector2(10, 10)
	ice_vfx.z_index = 10
	enemy.add_child(ice_vfx)
	ice_vfx.position = Vector2(-5, -16)

	# Slow enemy to 30% speed for 3s
	if enemy.has_method("apply_slow"):
		enemy.apply_slow(0.3, 3.0)
	else:
		# Fallback: tint blue for 3s to indicate slow
		var original_mod: Color = enemy.modulate
		enemy.modulate = Color(0.5, 0.7, 1.0)
		if is_inside_tree():
			await get_tree().create_timer(3.0).timeout
		if is_instance_valid(enemy):
			enemy.modulate = original_mod

	if is_instance_valid(ice_vfx):
		ice_vfx.queue_free()


func _demo_chain_lightning(pos: Vector2, already_hit: Array[Node2D]) -> void:
	# Chain lightning to up to 2 nearby enemies within 60px of any hit enemy
	var chain_targets: Array[Node2D] = []
	for body in get_tree().get_nodes_in_group("enemies"):
		if not body is Node2D or body in already_hit or body in chain_targets:
			continue
		for hit_enemy in already_hit:
			if not is_instance_valid(hit_enemy):
				continue
			var dist: float = hit_enemy.global_position.distance_to(body.global_position)
			if dist < 60.0:
				chain_targets.append(body)
				break
		if chain_targets.size() >= 2:
			break

	for target in chain_targets:
		if not is_instance_valid(target):
			continue
		if target.has_method("take_damage"):
			target.take_damage(5, player_index)
		if target.has_method("apply_stun"):
			target.apply_stun(0.5)

		# Blue VFX line between nearest hit enemy and chain target
		var nearest_hit: Node2D = null
		var nearest_dist: float = 9999.0
		for hit_enemy in already_hit:
			if not is_instance_valid(hit_enemy):
				continue
			var d: float = hit_enemy.global_position.distance_to(target.global_position)
			if d < nearest_dist:
				nearest_dist = d
				nearest_hit = hit_enemy

		if nearest_hit != null:
			_demo_draw_lightning_line(nearest_hit.global_position, target.global_position)


func _demo_draw_lightning_line(from_pos: Vector2, to_pos: Vector2) -> void:
	var line := Line2D.new()
	line.width = 2.0
	line.default_color = Color(0.3, 0.5, 1.0, 0.9)
	line.z_index = 15
	line.add_point(from_pos)
	# Add a jagged midpoint for lightning effect
	var mid: Vector2 = (from_pos + to_pos) / 2.0 + Vector2(randf_range(-8, 8), randf_range(-8, 8))
	line.add_point(mid)
	line.add_point(to_pos)
	get_parent().add_child(line)
	var tween := line.create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.3)
	tween.tween_callback(line.queue_free)


func _demo_spawn_napalm(pos: Vector2) -> void:
	# Burning ground zone: Area2D, 30px radius, lasts 3s, deals 8 damage per 0.5s
	var napalm_area := Area2D.new()
	napalm_area.name = "NapalmZone"
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 30.0
	shape.shape = circle
	napalm_area.add_child(shape)
	napalm_area.global_position = pos
	napalm_area.collision_layer = 0
	napalm_area.collision_mask = 2  # enemy layer
	get_parent().add_child(napalm_area)

	# Orange/red VFX with flame particles rising
	var ground_vfx := ColorRect.new()
	ground_vfx.color = Color(1.0, 0.3, 0.0, 0.6)
	ground_vfx.size = Vector2(60, 16)
	ground_vfx.position = Vector2(-30, -8)
	ground_vfx.z_index = 4
	napalm_area.add_child(ground_vfx)

	var napalm_time: float = 0.0
	var napalm_duration: float = 3.0
	var tick_timer: float = 0.0
	var particle_timer: float = 0.0
	var p_idx: int = player_index

	while napalm_time < napalm_duration and is_instance_valid(napalm_area) and is_inside_tree():
		var dt: float = get_process_delta_time()
		napalm_time += dt
		tick_timer += dt
		particle_timer += dt

		# Damage enemies in zone every 0.5s
		if tick_timer >= 0.5:
			tick_timer -= 0.5
			for body in get_tree().get_nodes_in_group("enemies"):
				if not body is Node2D:
					continue
				var dist: float = napalm_area.global_position.distance_to(body.global_position)
				if dist < 30.0 and body.has_method("take_damage"):
					body.take_damage(8, p_idx)

		# Spawn rising flame particles every 0.2s
		if particle_timer >= 0.2 and is_instance_valid(napalm_area):
			particle_timer -= 0.2
			var flame := ColorRect.new()
			flame.color = Color(1.0, randf_range(0.2, 0.6), 0.0, 0.8)
			flame.size = Vector2(4, 4)
			flame.z_index = 5
			flame.position = Vector2(randf_range(-25, 25), -8)
			napalm_area.add_child(flame)
			var flame_tween := flame.create_tween()
			flame_tween.set_parallel(true)
			flame_tween.tween_property(flame, "position:y", flame.position.y - 20.0, 0.4)
			flame_tween.tween_property(flame, "modulate:a", 0.0, 0.4)
			flame_tween.chain().tween_callback(flame.queue_free)

		# Fade out ground VFX near end
		if napalm_time > napalm_duration - 0.5 and is_instance_valid(ground_vfx):
			ground_vfx.modulate.a = lerpf(0.6, 0.0, (napalm_time - (napalm_duration - 0.5)) / 0.5)

		await get_tree().process_frame

	if is_instance_valid(napalm_area):
		napalm_area.queue_free()
func _spawn_healing_potion(target_pos: Vector2) -> void:
	var potion := ColorRect.new()
	potion.color = Color(0.2, 0.9, 0.3, 0.9)
	potion.size = Vector2(8, 10)
	potion.z_index = 5
	get_parent().add_child(potion)
	potion.global_position = global_position + Vector2(0, -8)

	# Arc the potion toward target
	var travel_time := 0.4
	var start_pos: Vector2 = potion.global_position
	var elapsed := 0.0
	while elapsed < travel_time and is_instance_valid(potion):
		var dt: float = get_process_delta_time()
		elapsed += dt
		var t: float = clampf(elapsed / travel_time, 0.0, 1.0)
		var mid: Vector2 = (start_pos + target_pos) / 2.0 + Vector2(0, -40)  # Arc height
		# Quadratic bezier
		var a: Vector2 = start_pos.lerp(mid, t)
		var b: Vector2 = mid.lerp(target_pos, t)
		potion.global_position = a.lerp(b, t)
		await get_tree().process_frame

	if not is_instance_valid(potion):
		return
	var land_pos: Vector2 = potion.global_position
	potion.queue_free()

	# Create lingering healing zone
	_spawn_healing_zone(land_pos)


func _spawn_healing_zone(pos: Vector2) -> void:
	AudioManager.play("player_revive", -6.0, 1.4)
	var zone := Area2D.new()
	zone.global_position = pos
	zone.collision_layer = 0
	zone.collision_mask = 2  # Detect players

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 40.0
	shape.shape = circle
	zone.add_child(shape)

	# Visual: green glowing circle
	var visual := ColorRect.new()
	visual.color = Color(0.2, 0.85, 0.3, 0.25)
	visual.size = Vector2(80, 80)
	visual.position = Vector2(-40, -40)
	zone.add_child(visual)

	get_parent().add_child(zone)

	# Heal players in zone every 0.5s for 4 seconds, with bubble particles
	var heal_ticks := 8
	for tick in range(heal_ticks):
		if not is_instance_valid(zone):
			break
		# Bubble particle VFX
		for b in range(3):
			var bubble := ColorRect.new()
			bubble.color = Color(0.3, 1.0, 0.4, 0.6)
			bubble.size = Vector2(4, 4)
			bubble.position = pos + Vector2(randf_range(-30, 30), randf_range(-10, 10))
			bubble.z_index = 6
			get_parent().add_child(bubble)
			var btween := bubble.create_tween()
			btween.tween_property(bubble, "position:y", bubble.position.y - randf_range(20, 50), 0.6)
			btween.parallel().tween_property(bubble, "modulate:a", 0.0, 0.6)
			btween.tween_callback(bubble.queue_free)

		# Heal overlapping players
		for body in zone.get_overlapping_bodies():
			if "player_index" in body:
				var p_idx: int = body.get("player_index")
				PlayerManager.heal_player(p_idx, 5)
				if body.has_method("_update_health_bar"):
					body._update_health_bar()

		# Pulse the visual
		if is_instance_valid(visual):
			visual.modulate.a = 0.35
			var ptween := visual.create_tween()
			ptween.tween_property(visual, "modulate:a", 0.15, 0.4)

		await get_tree().create_timer(0.5).timeout

	# Fade out and remove
	if is_instance_valid(zone):
		var fade := zone.create_tween()
		fade.tween_property(visual, "modulate:a", 0.0, 0.5)
		fade.tween_callback(zone.queue_free)
func _attack_guitarist() -> void:
	# Musical Notes - 3 sine-wave notes in quick succession
	AudioManager.play("menu_confirm", -2.0, 1.0)
	_attack_cooldown = 0.7
	PlayerManager.add_skill_xp(player_index, "attack", 2)

	var aim: Vector2 = _get_aim_direction()
	var pitches: Array[float] = [1.0, 1.25, 1.5]

	for note_i in range(3):
		if not is_inside_tree():
			return
		if note_i > 0:
			await get_tree().create_timer(0.1).timeout
			if not is_inside_tree():
				return
		AudioManager.play("menu_confirm", -4.0, pitches[note_i])
		_spawn_musical_note(aim, note_i)


func _spawn_musical_note(aim: Vector2, note_index: int) -> void:
	var note := Node2D.new()
	note.name = "MusicalNote"
	note.global_position = global_position + aim * 12.0
	note.z_index = 8
	note.add_to_group("loose_items")

	var note_script := GDScript.new()
	note_script.source_code = """extends Node2D

var direction: Vector2 = Vector2.ZERO
var speed: float = 250.0
var damage: int = 8
var owner_index: int = 0
var note_color: Color = Color(1.0, 0.8, 0.2)
var _age: float = 0.0
var _distance_traveled: float = 0.0
var _sine_amplitude: float = 20.0
var _perp: Vector2 = Vector2.ZERO
var _base_pos: Vector2 = Vector2.ZERO
var _hit: bool = false

func _ready() -> void:
	add_to_group("loose_items")
	_perp = Vector2(-direction.y, direction.x)
	_base_pos = global_position

func _draw() -> void:
	# Musical note: small filled circle + stem
	draw_circle(Vector2(0, 2), 3.0, note_color)
	draw_line(Vector2(3, 2), Vector2(3, -6), note_color, 1.5)
	draw_line(Vector2(3, -6), Vector2(6, -4), note_color, 1.5)

func _process(delta: float) -> void:
	if _hit:
		return
	_age += delta
	if _age >= 2.0:
		queue_free()
		return

	# Move along direction
	_distance_traveled += speed * delta
	var base_offset: Vector2 = direction * _distance_traveled
	# Sine wave perpendicular to travel direction
	var sine_offset: float = sin(_distance_traveled * 0.08) * _sine_amplitude
	global_position = _base_pos + base_offset + _perp * sine_offset
	queue_redraw()

	# Check enemy collision
	for body in get_tree().get_nodes_in_group("enemies"):
		if body is Node2D:
			var dist: float = global_position.distance_to(body.global_position)
			if dist < 12.0:
				_hit = true
				if body.has_method("take_damage"):
					body.take_damage(damage, owner_index)
				# Hit VFX
				if is_inside_tree():
					var p := ColorRect.new()
					p.color = note_color
					p.size = Vector2(6, 6)
					p.position = global_position
					p.z_index = 9
					get_parent().add_child(p)
					var tw := p.create_tween()
					tw.set_parallel(true)
					tw.tween_property(p, "scale", Vector2(3.0, 3.0), 0.2)
					tw.tween_property(p, "modulate:a", 0.0, 0.2)
					tw.chain().tween_callback(p.queue_free)
				queue_free()
				return
"""
	note_script.reload()
	note.set_script(note_script)

	var bright_colors: Array[Color] = [
		Color(1.0, 0.3, 0.5),
		Color(0.3, 1.0, 0.5),
		Color(0.3, 0.5, 1.0),
		Color(1.0, 0.9, 0.2),
		Color(0.9, 0.4, 1.0),
		Color(0.2, 1.0, 1.0),
	]
	note.direction = aim
	note.speed = 250.0
	note.damage = int(8 * PlayerManager.get_skill_bonus(player_index, "attack"))
	note.owner_index = player_index
	note.note_color = bright_colors[randi() % bright_colors.size()]

	get_parent().add_child(note)


func _special_guitarist_blast_wave() -> void:
	# Blast Wave - 60 degree arc that expands outward
	if not PlayerManager.use_mana(player_index, 25):
		_spawn_fail_flash()
		_special_cooldown = 0.0
		return

	AudioManager.play("explosion", 4.0, 0.3)
	AudioManager.play("shield_charge", 2.0, 0.4)
	PlayerManager.add_skill_xp(player_index, "special", 7)

	var aim: Vector2 = _get_aim_direction()
	var aim_angle: float = aim.angle()
	_spawn_blast_wave_arc(aim_angle, deg_to_rad(30.0), 150.0, 200.0, 0.5, 5, 300.0)


func _spawn_blast_wave_arc(center_angle: float, half_arc: float, max_radius: float, wave_speed: float, duration: float, tick_damage: int, push_force_base: float) -> void:
	var wave := Node2D.new()
	wave.name = "BlastWave"
	wave.global_position = global_position
	wave.z_index = 7

	var wave_script := GDScript.new()
	wave_script.source_code = """extends Node2D

var center_angle: float = 0.0
var half_arc: float = 0.524
var max_radius: float = 150.0
var wave_speed: float = 200.0
var duration: float = 0.5
var tick_damage: int = 5
var push_force_base: float = 300.0
var owner_index: int = 0
var origin_pos: Vector2 = Vector2.ZERO
var _age: float = 0.0
var _current_radius: float = 10.0
var _tick_timer: float = 0.0
var _hit_this_tick: Dictionary = {}

func _draw() -> void:
	# Draw expanding arc
	var alpha: float = clampf(1.0 - _age / duration, 0.1, 0.6)
	var color: Color = Color(0.95, 0.85, 0.3, alpha)
	var points: int = 16
	var inner_radius: float = maxf(0.0, _current_radius - 15.0)

	# Draw arc wedge
	var arc_points: PackedVector2Array = PackedVector2Array()
	# Inner arc (from left to right)
	for i in range(points + 1):
		var angle: float = center_angle - half_arc + (half_arc * 2.0) * (float(i) / float(points))
		arc_points.append(Vector2(cos(angle), sin(angle)) * inner_radius)
	# Outer arc (from right to left)
	for i in range(points, -1, -1):
		var angle: float = center_angle - half_arc + (half_arc * 2.0) * (float(i) / float(points))
		arc_points.append(Vector2(cos(angle), sin(angle)) * _current_radius)

	if arc_points.size() >= 3:
		var colors: PackedColorArray = PackedColorArray()
		for i in range(arc_points.size()):
			colors.append(color)
		draw_polygon(arc_points, colors)

	# Bright edge
	var edge_color: Color = Color(1.0, 1.0, 0.8, alpha * 1.5)
	for i in range(points):
		var a1: float = center_angle - half_arc + (half_arc * 2.0) * (float(i) / float(points))
		var a2: float = center_angle - half_arc + (half_arc * 2.0) * (float(i + 1) / float(points))
		var p1: Vector2 = Vector2(cos(a1), sin(a1)) * _current_radius
		var p2: Vector2 = Vector2(cos(a2), sin(a2)) * _current_radius
		draw_line(p1, p2, edge_color, 2.0)


func _process(delta: float) -> void:
	_age += delta
	if _age >= duration:
		queue_free()
		return

	_current_radius = minf(_current_radius + wave_speed * delta, max_radius)
	queue_redraw()

	# Damage tick
	_tick_timer += delta
	if _tick_timer >= 0.1:
		_tick_timer -= 0.1
		_hit_this_tick.clear()
		_apply_damage_and_push()


func _apply_damage_and_push() -> void:
	for body in get_tree().get_nodes_in_group("enemies"):
		if not body is Node2D:
			continue
		var to_body: Vector2 = body.global_position - origin_pos
		var dist: float = to_body.length()
		if dist > _current_radius or dist < 1.0:
			continue
		# Check angle
		var body_angle: float = to_body.angle()
		var angle_diff: float = wrapf(body_angle - center_angle, -PI, PI)
		if absf(angle_diff) > half_arc:
			continue

		# Deal damage
		if body.has_method("take_damage"):
			body.take_damage(tick_damage, owner_index)

		# Push effect
		var push_dir: Vector2 = to_body.normalized()
		var weight: float = 50.0
		if body.has_meta("weight"):
			weight = body.get_meta("weight")
		elif body.has_method("get_weight"):
			weight = body.get_weight()
		var force: float = push_force_base / (weight / 50.0)
		if body.has_method("apply_knockback"):
			body.apply_knockback(push_dir * force)
		elif "velocity" in body:
			body.velocity += push_dir * force
"""
	wave_script.reload()
	wave.set_script(wave_script)
	wave.center_angle = center_angle
	wave.half_arc = half_arc
	wave.max_radius = max_radius
	wave.wave_speed = wave_speed
	wave.duration = duration
	wave.tick_damage = tick_damage
	wave.push_force_base = push_force_base
	wave.owner_index = player_index
	wave.origin_pos = global_position

	get_parent().add_child(wave)
func _spawn_fail_flash() -> void:
	# Red X flash to show ability can't be used
	modulate = Color(1.0, 0.3, 0.3)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.15)


# -- Werewolf ------------------------------------------------------------------

var _werewolf_frenzy_active: bool = false
var _werewolf_frenzy_timer: float = 0.0
var _werewolf_frenzy_cooldown: float = 0.0
var _werewolf_pouncing: bool = false
var _werewolf_pounce_damage: int = 0
var _werewolf_pounce_radius: float = 0.0
const WEREWOLF_FRENZY_DURATION := 8.0
const WEREWOLF_FRENZY_COOLDOWN := 35.0
func _spawn_werewolf_slash(aim: Vector2, slash_index: int, damage: int) -> void:
	# Spawn a diagonal white slash line VFX
	var slash := ColorRect.new()
	slash.color = Color(1.0, 1.0, 1.0, 0.8)
	# Each slash offset slightly
	var offset_angle: float = -0.3 + slash_index * 0.3
	var slash_dir: Vector2 = aim.rotated(offset_angle)
	var slash_start: Vector2 = global_position + slash_dir * 8.0
	slash.size = Vector2(30, 3)
	slash.position = slash_start
	slash.rotation = slash_dir.angle() + 0.785  # ~45 degrees
	slash.z_index = 8
	slash.pivot_offset = Vector2(0, 1.5)
	get_parent().add_child(slash)

	var st := slash.create_tween()
	st.set_parallel(true)
	st.tween_property(slash, "position", slash_start + slash_dir * 20.0, 0.1)
	st.tween_property(slash, "modulate:a", 0.0, 0.15)
	st.chain().tween_callback(slash.queue_free)

	# Hit detection in the slash area
	for body in get_tree().get_nodes_in_group("enemies"):
		if not body is Node2D:
			continue
		var dist: float = global_position.distance_to(body.global_position)
		var to_enemy: Vector2 = (body.global_position - global_position)
		var dot_val: float = to_enemy.normalized().dot(aim)
		if dist < 45.0 and dot_val > 0.3:
			if body.has_method("take_damage"):
				body.take_damage(damage, player_index)
				PlayerManager.add_skill_xp(player_index, "attack", 1)
				_spawn_werewolf_blood(body.global_position)


func _spawn_werewolf_blood(hit_pos: Vector2) -> void:
	# 8 blood drops in random upward arcs
	for i in range(8):
		var angle: float = randf_range(-2.5, -0.6)
		var spd: float = randf_range(100.0, 250.0)
		var vel: Vector2 = Vector2(cos(angle), sin(angle)) * spd
		vel.x += randf_range(-60.0, 60.0)

		var blood := ColorRect.new()
		blood.color = Color(0.8, 0.05, 0.05, 0.9)
		blood.size = Vector2(4, 4)
		blood.position = hit_pos
		blood.z_index = 9
		get_parent().add_child(blood)

		_animate_blood_drop(blood, vel)
func _exec_apply_chain_constraint() -> void:
	if _executioner_class:
		_executioner_class.exec_apply_chain_constraint()


# -- Chain Length Helpers -------------------------------------------------------

# -- Chain Length Helpers — delegated to ExecutionerClass ----------------------








# -- YEET Physics (shared by thrown + stuck states) ----------------------------

static func entity_cfg(entity: Node, key: String, default_val: float) -> float:
	## Query a config value from any entity. If the entity has cfg(), use it.
	## Otherwise return the default. This lets any entity provide overrides
	## via its own config stack (artifacts, equipment, entity-type defaults).
	if entity and is_instance_valid(entity) and entity.has_method("cfg"):
		return entity.cfg(key, default_val)
	# Check for a simple property match (e.g., entity.mass)
	if entity and is_instance_valid(entity) and key == "mass" and "mass" in entity:
		return entity.mass
	return default_val


func _exec_is_entity_yeet_mode() -> bool:
	return _executioner_class.exec_is_entity_yeet_mode() if _executioner_class else false




# -- Main Tick -----------------------------------------------------------------

func _handle_executioner(delta: float) -> void:
	if _executioner_class:
		_executioner_class.exec_main_tick(delta)







































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




# -- Executioner Drawing + Tuning — delegated to ExecutionerClass --------------

func _draw_executioner() -> void:
	if _executioner_class:
		_executioner_class.draw_executioner()


func exec_tuning_set(key: String, value: float) -> void:
	if _executioner_class:
		_executioner_class.exec_tuning_set(key, value)


func _exec_tuning_handle_input(event: InputEvent) -> void:
	if _executioner_class:
		_executioner_class.exec_tuning_handle_input(event)
