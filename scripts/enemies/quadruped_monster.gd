extends CharacterBody2D

## Procedurally animated quadruped monster.
## Verlet physics skeleton with 23 tracked points.
## All rendering via _draw(), no sprites.

signal died(global_pos: Vector2)

# -- Scale ---------------------------------------------------------------------
# Single source of truth for monster size. 1.0 = default. 4.0 = 4x larger.
# All spatial dimensions derive from this via the sc() helper.
var creature_scale: float = 1.0
var speed_override: float = -1.0  # If >= 0, overrides auto-scaled speed tiers
var pathing_radius: float = -1.0  # If >= 0, overrides sc(LEAP_BODY_RADIUS) for all clearance checks

## Scale a base value by creature_scale. Use for all spatial constants.
func sc(base: float) -> float:
	return base * creature_scale

## Get the effective body radius used for leap/pathing clearance.
## Uses pathing_radius if set, otherwise sc(LEAP_BODY_RADIUS).
func _body_clearance_radius() -> float:
	if pathing_radius >= 0:
		return pathing_radius
	return sc(LEAP_BODY_RADIUS)

## Get effective speed for a base speed tier. Scales with creature_scale
## unless speed_override is set.
func _effective_speed(base_speed: float) -> float:
	if speed_override >= 0:
		return speed_override
	return base_speed * creature_scale

## Centralized state transition — all state changes route through here.
## Calls _exit_state / _enter_state hooks, logs via debug overlay, tracks strategy counts.
func _change_state(new_state: State) -> void:
	if new_state == _state:
		return
	var old_state := _state
	_exit_state(old_state, new_state)
	_state = new_state
	_enter_state(new_state, old_state)
	_strategy_changes += 1
	_last_state = old_state
	DebugOverlay.log("monster/state", self, "STATE: %s -> %s" % [
		State.keys()[old_state], State.keys()[new_state]])


## Cleanup when leaving a state. Resets transient flags that the old state owned.
func _exit_state(old_state: State, new_state: State) -> void:
	match old_state:
		State.ATTACK_TAIL:
			_tail_whipping = false
		State.ATTACK_GRAB:
			_jaw_open = 0.0
			_tail_whipping = false
			_grab_target_node = null
			# Restore normal body collision
			if _body_collision and _body_collision.shape is CircleShape2D:
				(_body_collision.shape as CircleShape2D).radius = 14.0
				_body_collision.position = Vector2(0, -14.0)
		State.ATTACK_LEAP_WINDUP, State.ATTACK_LEAP_AIRBORNE, \
		State.ATTACK_LEAP_STRIKE, State.ATTACK_LEAP_THRASH:
			_tail_whipping = false
			# Only do full leap cleanup when leaving leap states entirely
			# (not when transitioning between leap sub-states)
			if new_state != State.ATTACK_LEAP_WINDUP \
				and new_state != State.ATTACK_LEAP_AIRBORNE \
				and new_state != State.ATTACK_LEAP_STRIKE \
				and new_state != State.ATTACK_LEAP_THRASH:
				_leap_ik_off = false
				_leap_body_angle = 0.0
				_posture_blend = 0.0
				floor_snap_length = 1.0
		State.TRANSITION_QUADRUPED:
			_posture = Posture.QUADRUPED
			_posture_blend = 0.0
		State.TRANSITION_BIPEDAL:
			_posture = Posture.BIPEDAL


## Setup when entering a state. Initializes per-state defaults.
func _enter_state(new_state: State, _old_state: State) -> void:
	match new_state:
		State.STANDDOWN:
			_want_direction = 0.0
			velocity.x = 0.0

# -- Constants -----------------------------------------------------------------

const GRAVITY := 600.0
const MASS := 200.0

# Segment lengths
const SPINE_SEG_LEN := 28.0
const NECK_LEN := 22.0
const LEG_UPPER_LEN := 24.0
const LEG_LOWER_LEN := 22.0
const LEG_FOOT_LEN := 10.0
const TAIL_SEG_LEN := 16.0
const JAW_LEN := 14.0
const CLAVICLE_LEN := 12.0   # Short rigid bone connecting shoulders to arm hips
const HIP_BONE_LEN := 12.0   # Short rigid bone connecting waist to leg hips
const LIMB_FLEX := 0.10      # ±10% flex allowed on lower limb segments
const TAIL_FLEX := 0.05      # ±5% flex allowed on tail segments
const TAIL_MAX_BEND := deg_to_rad(20.0)  # Max rotation per tail joint (radians)
const SPINE_MAX_BEND := deg_to_rad(30.0)  # Max rotation per spine joint
const NECK_MAX_BEND := deg_to_rad(45.0)   # Max rotation per neck joint

# Pose stiffness (how fast segments spring back to rest pose, per second)
const STIFFNESS := 12.0       # General stiffness
const TAIL_STIFFNESS := 14.0  # Tail is rigid by default
const TAIL_WHIP_STIFFNESS := 2.0  # Loose only during whip
const HEAD_TRACK_SPEED := 6.0  # How fast head turns toward target

# Foot-driven locomotion
const STEP_THRESHOLD := 25.0   # How far behind a foot gets before it steps
const STEP_DURATION := 0.12    # Seconds to complete a step (quick feet)
const STEP_HEIGHT := 28.0      # How high foot lifts during step
const STEP_OVERSHOOT := 0.1    # Small overshoot — feet stay close to ideal position
const FOOT_PUSH_FORCE := 200.0 # Force each planted foot exerts to push body
const FOOT_GRIP := 0.92        # How well planted feet hold ground (velocity damping)

# Speed tiers (desired speed — foot push force is modulated to achieve this)
const SPEED_SLOW := 60.0
const SPEED_MEDIUM := 140.0
const SPEED_FAST := 240.0

# Combat
const BITE_DAMAGE := 25
const SWIPE_DAMAGE := 20
const TAIL_DAMAGE := 18
const LUNGE_DAMAGE := 20
const LUNGE_SPEED := 300.0
const BITE_RANGE := 90.0  # Generous — skull can reach this far
const TAIL_RANGE := 90.0
const ATTACK_COOLDOWN := 0.8  # Fast attack cycling
const AGGRO_SWITCH_HITS := 3

# Vertical leap
const LEAP_RANGE := 500.0      # Distance at which leap is considered
const LEAP_WINDUP_TIME := 0.6  # Seconds to coil up before launch (fast panther)
const LEAP_LAUNCH_SPEED := 1000.0 # Launch velocity magnitude (powerful)
const LEAP_SLASH_DAMAGE := 15  # Per slash (6 total = 90 max)
const LEAP_BITE_DAMAGE := 30   # Bite + thrash
const LEAP_THRASH_COUNT := 3   # Number of thrash shakes
const LEAP_COOLDOWN := 2.0     # Seconds between leaps (aggressive)

# Leap planning
const LEAP_BODY_RADIUS := 55.0    # Half-size of body for clearance checks (spine + legs + head)
const LEAP_STRIKE_REACH := 80.0   # How far the creature can reach to strike from its center
const LEAP_ARRIVAL_SAMPLES := 8   # Number of arrival angles to test around target
const LEAP_FLIGHT_TIMES := 7      # Number of flight durations to try per arrival point
const LEAP_FLIGHT_TIME_MIN := 0.25 # Shortest flight time to test
const LEAP_FLIGHT_TIME_MAX := 1.6 # Longest flight time to test (higher arcs clear platform corners)
const LEAP_ARC_STEPS := 40        # Simulation steps per arc (covers ~1.2s flight at 0.03s dt)
const LEAP_PLAN_GRAVITY := 600.0  # Gravity for arc simulation
const LEAP_ARC_DT := 0.03         # Simulation timestep (small enough to catch thin platforms)

# Health
const MAX_HEALTH := 1500
const HEAD_HEALTH := 400
const TAIL_HEALTH := 300
const LEG_HEALTH := 250

# Death ball grab (close proximity)
const GRAB_RANGE := 40.0          # Must be THIS close to initiate grab
const GRAB_DURATION := 2.0        # Hold for 2 seconds
const GRAB_KICK_DAMAGE := 10      # Per kick (multiple kicks during hold)
const GRAB_BITE_DAMAGE := 20      # Bite damage during hold
const GRAB_EJECT_SPEED := 400.0   # Fling speed on release
const GRAB_KICK_INTERVAL := 0.25  # Time between kicks

# Sprint slash (same-plane attack)
const SPRINT_SPEED := 250.0       # Burst sprint speed
const SPRINT_SLASH_DAMAGE := 18   # Per slash (3 slashes = 54 total)
const SPRINT_SLASH_RANGE := 70.0  # Must be within this to start slashing
const SPRINT_SLASH_INTERVAL := 0.1  # Time between slashes

# Connected hop-up (short platform climb)
const HOP_UP_MAX_HEIGHT := 140.0  # Max height difference for a connected hop (vs full leap)
const HOP_UP_DURATION := 0.4      # Time to complete the hop (fast)
const HOP_UP_DAMAGE := 12         # Landing impact damage

# Pre-cognition (two-hop leap chaining)
const PRECOG_TRIGGER_TIME := 3.0   # Seconds without landing a hit before pre-cognition
const PRECOG_GRID_SPACING := 50.0  # Drop a ball every 50px across the entire map
const PRECOG_CLUSTER_RADIUS := 40.0 # Landed balls closer than this are merged into one cluster

# -- Enums ---------------------------------------------------------------------

enum State { PATROL, CHASE, ATTACK_BITE, ATTACK_SWIPE, ATTACK_TAIL,
			 ATTACK_LUNGE, ATTACK_SPRINT_SLASH, ATTACK_HOP_UP, ATTACK_GRAB,
			 ATTACK_LEAP_PLAN, ATTACK_LEAP_WINDUP,
			 ATTACK_LEAP_AIRBORNE, ATTACK_LEAP_STRIKE, ATTACK_LEAP_THRASH,
			 PRECOGNITION, TRANSITION_BIPEDAL, TRANSITION_QUADRUPED, HURT, DEAD,
			 STANDDOWN }
enum Posture { QUADRUPED, BIPEDAL }
enum DamageState { NONE, MEDIUM, HIGH }

# -- Skeleton arrays -----------------------------------------------------------
# Pose-driven: each point has a current position and a rest-pose offset from parent.
# Each frame, points spring toward their rest pose. No gravity on segments.

# Spine: 3 points (front to back)
var _spine: Array[Vector2] = []

# Neck: 2 points (base at spine[0], tip)
var _neck: Array[Vector2] = []

# Head
var _skull: Vector2 = Vector2.ZERO
var _jaw: Vector2 = Vector2.ZERO
var _jaw_open: float = 0.0  # 0=closed, 1=fully open

# Tail: 5 points
var _tail: Array[Vector2] = []
var _tail_whipping: bool = false  # Loosens tail stiffness during whip

# Clavicles: 2 short rigid bones from spine[0] to arm hip points
# _clavicles[0] = left clavicle endpoint, _clavicles[1] = right clavicle endpoint
var _clavicles: Array[Vector2] = []   # 2 points (endpoints where arms attach)
var _clavicle_rest: Array[Vector2] = []  # Rest offsets from spine[0]

# Hip bones: 2 short rigid bones from spine[2] to leg hip points
var _hip_bones: Array[Vector2] = []   # 2 points (endpoints where legs attach)
var _hip_bone_rest: Array[Vector2] = []  # Rest offsets from spine[2]

# Legs: 4 legs, each with 3 points [hip, knee, foot]
# Legs 0,1 (arms) attach to clavicle endpoints; legs 2,3 attach to hip bone endpoints
var _legs: Array = []       # Array of Array[Vector2]

# Rest pose offsets (relative to parent point) — computed once in _init
var _spine_rest: Array[Vector2] = []      # spine[i] offset from spine[i-1]
var _neck_rest: Vector2 = Vector2.ZERO    # neck tip offset from spine[0]
var _skull_rest: Vector2 = Vector2.ZERO   # skull offset from neck tip
var _jaw_rest: Vector2 = Vector2.ZERO     # jaw offset from skull
var _tail_rest: Array[Vector2] = []       # tail[i] offset from tail[i-1] (or spine[2])
var _leg_rest: Array = []                 # 4 arrays of 3 offsets each

# Foot targeting
var _foot_world: Array[Vector2] = []     # WORLD-space planted foot positions
var _foot_planted: Array[bool] = []      # Is the foot currently planted?
var _step_timers: Array[float] = []      # Time remaining in current step
var _step_origins: Array[Vector2] = []   # Where the step started (world)
var _step_targets: Array[Vector2] = []   # Where the step is going (world)
var _step_center: Array[Vector2] = []    # Bezier control point (world)

# -- State ---------------------------------------------------------------------

var health: int = MAX_HEALTH
var mass: float = MASS
var _dead := false
var _standdown := false  # Stand-down mode: passive, receives damage, no AI
var _asleep := false     # Asleep mode: dormant until damaged, then becomes active
var _breakaway_immune: float = 0.0  # Brief invincibility after breakaway
var _physics_frozen := false  # When true, skip all physics/gravity (used during splay setup)
var _pose_locked := false     # When true, skip _solve_pose — external system controls skeleton (splay editor)
var _chained := false         # When true, chains control position — skip gravity and move_and_slide
var _chained_stuck_timer: float = 0.0  # How long we've been stuck at chain limit
var _chained_last_pos: Vector2 = Vector2.ZERO  # Position last frame for stuck detection
var territorial := false      # When true, attacks other monsters instead of/in addition to players

# Pose overrides for splay system (attachment point name -> target local Vector2)
var _pose_overrides: Dictionary = {}
const POSE_OVERRIDE_BLEND := 0.8  # 0.0 = natural, 1.0 = fully overridden
var _state: State = State.PATROL
var _posture: Posture = Posture.QUADRUPED
var _facing: float = 1.0  # 1=right, -1=left
var _timer: float = 0.0
var _attack_cooldown: float = 0.0
var _attack_timer: float = 0.0  # Time within current attack
var _move_speed: float = SPEED_SLOW
var _posture_blend: float = 0.0  # 0=quadruped, 1=bipedal
var _breathe_time: float = 0.0  # Idle breathing phase
var _want_direction: float = 0.0  # AI intent: -1=left, 0=stop, 1=right
var _initialized: bool = false  # First-frame init flag
var _leap_cooldown: float = 0.0  # Cooldown between leaps
var _leap_ik_off: bool = false   # Disable leg IK during leap (legs positioned manually)
var _leap_body_angle: float = 0.0  # Body rotation during leap
var _leap_launch_pos: Vector2 = Vector2.ZERO  # Chosen launch position (world)
var _leap_found_path: bool = false  # Did planning find a clear path?
var _leap_plan_phase: int = 0       # 0=not started, 1=phase1 done, 2=phase2 done
var _leap_plan_results: Array = []  # Debug: [{pos, arc_l, arc_r, clear}] for each sample
var _leap_phase1_near_misses: Array = []  # Best candidates from phase 1 for phase 2 refinement
var _leap_chosen_arc_l: PackedVector2Array = PackedVector2Array()  # Debug: chosen left arc
var _leap_chosen_arc_r: PackedVector2Array = PackedVector2Array()  # Debug: chosen right arc
var _leap_phase: float = 0.0    # Sub-phase progress within leap states
var _leap_target_pos: Vector2 = Vector2.ZERO  # Where we're leaping to
var _leap_slash_count: int = 0  # Slashes delivered so far
var _leap_thrash_count: int = 0 # Thrashes delivered so far
var _leap_slash_side: int = 1   # Alternating slash direction
var _slash_effects: Array = []  # Active slash visual effects
var _sprint_slash_count: int = 0  # Slashes delivered in sprint attack
var _grab_kick_count: int = 0    # Kicks delivered during grab
var _grab_target_node: Node2D = null  # The player being grabbed
var _hop_up_target_y: float = 0.0  # Target platform Y for connected hop
var _hop_up_start_pos: Vector2 = Vector2.ZERO  # Where the hop started

# Pre-cognition state
var _time_since_strike_range: float = 0.0  # How long since last successful hit
var _precog_phase: int = 0  # 0=ball drop, 1=build graph, 2=pathfind, 3=execute
var _precog_ball_lands: Array[Vector2] = []  # World positions where balls landed (raw)
var _precog_platforms: Array = []  # [{pos, weight, min_x, max_x}] — detected platforms
var _precog_platforms_cached: bool = false  # Platforms only need to be detected once
var _precog_edges: Array = []  # [{from, to, launch_vel, arc_l, arc_r}] — leaps between platforms
var _precog_path: Array = []  # Ordered list of platform indices to traverse
var _precog_path_edges: Array = []  # The edge data for each hop in the path
var _precog_current_hop: int = 0  # Which hop we're currently executing
var _precog_has_waypoint: bool = false
var _precog_waypoint: Vector2 = Vector2.ZERO  # Where to walk before leaping
var _precog_waypoint_edge: Dictionary = {}  # The leap to execute on arrival
var _precog_process_i: int = 0  # Graph building: source platform index
var _precog_process_j: int = 0  # Graph building: dest platform index

# Target tracking
var _target: Node2D = null
var _target_player_index: int = -1
var _hit_tracker: Dictionary = {}  # player_index -> hit count

# Part health — each part: { max_hp, current_hp, damage_state }
var _part_health: Dictionary = {}
var _leg_severed: Array[bool] = [false, false, false, false]
var _tail_severed: bool = false
var _head_severed: bool = false
var _grab_disabled: bool = false       # Set when mid-tail reaches HIGH damage
var _torso_bleeding: bool = false      # Set when torso reaches HIGH damage
var _torso_bleed_timer: float = 0.0    # Timer for 1/s blood drip
var _blood_particles: Array = []       # Active blood particles [{pos, vel, life, max_life, color}]

# Hitbox nodes (assigned in _ready from scene tree or created dynamically)
var _hitboxes: Dictionary = {}  # part_name -> Area2D
var _body_collision: CollisionShape2D = null  # Main body collision shape

# Attachment points — larger zones for item attachment (balloons, grapple)
var _attach_points: Dictionary = {}  # point_name -> Area2D
var _attachments: Dictionary = {}    # point_name -> Array[Node2D] (attached items)

# Per-segment weights (proportional to visual size, total ~205)
const SEGMENT_WEIGHTS: Dictionary = {
	"head": 15.0,       # Skull + jaw (small, bony)
	"neck": 10.0,       # 2 neck segments
	"shoulders": 30.0,  # spine[0] — front of torso, clavicles attached
	"torso": 40.0,      # spine[1] — largest body section
	"waist": 30.0,      # spine[2] — rear of torso, hip bones attached
	"tail": 20.0,       # 5 tail segments (~4 each)
	"tail_tip": 20.0,   # Alias for tail
	"elbow_l": 8.0,     # Left arm elbow joint
	"elbow_r": 8.0,     # Right arm elbow joint
	"knee_l": 8.0,      # Left leg knee joint
	"knee_r": 8.0,      # Right leg knee joint
	"leg0": 12.0,       # Front-left arm (full limb)
	"leg1": 12.0,       # Front-right arm (full limb)
	"leg2": 12.0,       # Rear-left leg (full limb)
	"leg3": 12.0,       # Rear-right leg (full limb)
}
var _attach_forces: Dictionary = {}  # point_name -> Vector2 (accumulated force from attached items)
var debug_draw_enabled: bool = false  # Heavy arc/edge rendering (toggle via RCON debugdraw)
var _dbg_arc_log: bool = false        # Log arc collision details (first failure only)
var _dbg_first_body_clip: String = "" # First body clip position for diagnostics
var debug_draw_lite: bool = true     # Lightweight debug (state, platforms, waypoint, target)

# IK quality scoring (lower = better)
var _ik_score: float = 0.0         # Current frame IK quality score
var _ik_score_avg: float = 0.0     # Rolling average
var _ik_score_peak: float = 0.0    # Worst score seen
var _ik_score_samples: int = 0
var _ball_score: float = 0.0       # Current ball quality (0 = perfect, higher = worse)
var _ball_score_peak: float = 0.0  # Worst ball score seen

# Strategy thrash scoring (lower = better)
var _last_state: int = -1          # Previous frame's state
var _strategy_changes: int = 0     # State changes since dummy last moved
var _last_target_pos: Vector2 = Vector2.ZERO  # Dummy position last check
var _plan_attempts: int = 0        # How many times we've tried the current plan
const MAX_PLAN_ATTEMPTS := 3      # Commit to a plan for this many attempts before changing
var _state_lock_timer: float = 0.0 # Don't change state until this expires
var entity_id: String = ""         # Unique ID for test zone tracking
static var _next_entity_id: int = 0  # Auto-increment for default entity_id


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 8
	collision_mask = 1

	# Guarantee every monster has an entity_id
	if entity_id == "":
		entity_id = "monster_%d" % _next_entity_id
	_next_entity_id += 1

	_init_skeleton()
	_init_part_health()
	_init_collision()
	_init_hitboxes()
	_init_attach_points()


func _init_skeleton() -> void:
	# Body height: spine elevated so feet rest at y=0 (floor contact)
	var body_y: float = -(sc(4.0) + sc(LEG_UPPER_LEN) + sc(LEG_LOWER_LEN))  # ~-50 at scale 1

	# Spine: horizontal at body_y
	_spine.resize(3)
	_spine_rest.resize(3)
	for i in range(3):
		_spine[i] = Vector2((1 - i) * sc(SPINE_SEG_LEN) * _facing, body_y)
	_spine_rest[0] = Vector2.ZERO  # spine[0] is the anchor
	_spine_rest[1] = Vector2(-sc(SPINE_SEG_LEN) * _facing, 0)  # offset from spine[0]
	_spine_rest[2] = Vector2(-sc(SPINE_SEG_LEN) * _facing, 0)  # offset from spine[1]

	# Neck: extends forward-up from spine[0]
	_neck.resize(2)
	_neck[0] = _spine[0]
	_neck_rest = Vector2(sc(NECK_LEN) * 0.8 * _facing, -sc(NECK_LEN) * 0.7)
	_neck[1] = _spine[0] + _neck_rest

	# Head: skull connects directly to neck tip (no gap), 2x size
	_skull_rest = Vector2(sc(14) * _facing, -sc(8))
	_skull = _neck[1] + _skull_rest
	_jaw_rest = Vector2(sc(8) * _facing, sc(JAW_LEN) * 0.6)
	_jaw = _skull + _jaw_rest

	# Tail: extends backward from spine[2], slightly raised (rigid)
	_tail.resize(5)
	_tail_rest.resize(5)
	for i in range(5):
		# Tail goes backward and slightly up, rigid like a counterbalance
		_tail_rest[i] = Vector2(-sc(TAIL_SEG_LEN) * _facing, -sc(2.0))
	var tail_anchor: Vector2 = _spine[2] + Vector2(-sc(4) * _facing, -sc(2))
	for i in range(5):
		if i == 0:
			_tail[i] = tail_anchor + _tail_rest[i]
		else:
			_tail[i] = _tail[i - 1] + _tail_rest[i]

	# Clavicles: short rigid bones from spine[0] outward to arm attachment points
	_clavicles.resize(2)
	_clavicle_rest.resize(2)
	_clavicle_rest[0] = Vector2(-sc(CLAVICLE_LEN) * 0.5, sc(CLAVICLE_LEN) * 0.8)   # Left arm (toward front-left)
	_clavicle_rest[1] = Vector2(sc(CLAVICLE_LEN) * 0.5, sc(CLAVICLE_LEN) * 0.8)    # Right arm (toward front-right)
	_clavicles[0] = _spine[0] + _clavicle_rest[0]
	_clavicles[1] = _spine[0] + _clavicle_rest[1]

	# Hip bones: short rigid bones from spine[2] outward to leg attachment points
	_hip_bones.resize(2)
	_hip_bone_rest.resize(2)
	_hip_bone_rest[0] = Vector2(-sc(HIP_BONE_LEN) * 0.5, sc(HIP_BONE_LEN) * 0.8)   # Left leg
	_hip_bone_rest[1] = Vector2(sc(HIP_BONE_LEN) * 0.5, sc(HIP_BONE_LEN) * 0.8)    # Right leg
	_hip_bones[0] = _spine[2] + _hip_bone_rest[0]
	_hip_bones[1] = _spine[2] + _hip_bone_rest[1]

	# Legs: arms (0,1) attach to clavicle endpoints, legs (2,3) attach to hip bone endpoints
	_legs.resize(4)
	_leg_rest.resize(4)
	_foot_world.resize(4)
	_foot_planted.resize(4)
	_step_timers.resize(4)
	_step_origins.resize(4)
	_step_targets.resize(4)
	_step_center.resize(4)

	for li in range(4):
		var hip_anchor: Vector2
		if li < 2:
			hip_anchor = _clavicles[li]  # Arms attach to clavicle endpoints
		else:
			hip_anchor = _hip_bones[li - 2]  # Legs attach to hip bone endpoints
		var side_x: float = sc(3.0) if (li % 2 == 0) else -sc(3.0)

		var leg: Array[Vector2] = []
		leg.resize(3)
		leg[0] = hip_anchor
		leg[1] = hip_anchor + Vector2(0, sc(LEG_UPPER_LEN))
		leg[2] = Vector2(hip_anchor.x, 0)
		_legs[li] = leg

		var rest: Array[Vector2] = []
		rest.resize(3)
		rest[0] = Vector2(side_x, sc(6))
		rest[1] = Vector2(0, sc(LEG_UPPER_LEN))
		rest[2] = Vector2(0, sc(LEG_LOWER_LEN))
		_leg_rest[li] = rest

		# Initialize foot world positions (will be set properly on first frame)
		_foot_world[li] = Vector2.ZERO  # Set in first _physics_process
		_foot_planted[li] = true
		_step_timers[li] = 0.0
		_step_origins[li] = Vector2.ZERO
		_step_targets[li] = Vector2.ZERO
		_step_center[li] = Vector2.ZERO


func _init_part_health() -> void:
	_part_health = {
		"body": { "max_hp": MAX_HEALTH, "current_hp": MAX_HEALTH, "damage_state": DamageState.NONE },
		"head": { "max_hp": HEAD_HEALTH, "current_hp": HEAD_HEALTH, "damage_state": DamageState.NONE },
		"tail": { "max_hp": TAIL_HEALTH, "current_hp": TAIL_HEALTH, "damage_state": DamageState.NONE },
		"leg0": { "max_hp": LEG_HEALTH, "current_hp": LEG_HEALTH, "damage_state": DamageState.NONE },
		"leg1": { "max_hp": LEG_HEALTH, "current_hp": LEG_HEALTH, "damage_state": DamageState.NONE },
		"leg2": { "max_hp": LEG_HEALTH, "current_hp": LEG_HEALTH, "damage_state": DamageState.NONE },
		"leg3": { "max_hp": LEG_HEALTH, "current_hp": LEG_HEALTH, "damage_state": DamageState.NONE },
	}


func _init_collision() -> void:
	# PRIMARY collider: circle (sphere) rigidly attached to torso like a belly.
	# Circle prevents corner-catching at odd angles.
	# Position tracks spine[1] + downward offset each frame.
	var shape := CircleShape2D.new()
	shape.radius = sc(14.0)  # Belly sphere — big enough for floor contact
	_body_collision = CollisionShape2D.new()
	_body_collision.shape = shape
	_body_collision.position = Vector2(0, -sc(10.0))  # Initial; updated each frame
	add_child(_body_collision)


func _constrain_skeleton_to_world() -> void:
	## After skeleton is solved, push skull/tail/spine out of geometry.
	## This prevents body parts from clipping through floors and platforms.
	## Does NOT use CollisionShape2D — uses raycasts to detect penetration
	## and pushes the skeleton point upward.
	var space := get_world_2d().direct_space_state
	if not space or _leap_ik_off:
		return  # Don't constrain during leaps (body is flying through air)

	# Skull: must not go below the floor beneath it
	var skull_world: Vector2 = global_position + _skull
	var skull_floor_q := PhysicsRayQueryParameters2D.create(
		skull_world + Vector2(0, -sc(5)), skull_world + Vector2(0, sc(15)), 1)
	skull_floor_q.exclude = [get_rid()]
	var skull_hit: Dictionary = space.intersect_ray(skull_floor_q)
	if not skull_hit.is_empty():
		var floor_local_y: float = skull_hit["position"].y - global_position.y
		if _skull.y > floor_local_y - sc(8):
			_skull.y = floor_local_y - sc(8)
			_jaw.y = minf(_jaw.y, floor_local_y - sc(4))

	# Tail tip: must not go below floor
	if not _tail_severed and _tail.size() > 4:
		var tail_world: Vector2 = global_position + _tail[4]
		var tail_floor_q := PhysicsRayQueryParameters2D.create(
			tail_world + Vector2(0, -sc(5)), tail_world + Vector2(0, sc(15)), 1)
		tail_floor_q.exclude = [get_rid()]
		var tail_hit: Dictionary = space.intersect_ray(tail_floor_q)
		if not tail_hit.is_empty():
			var floor_local_y: float = tail_hit["position"].y - global_position.y
			if _tail[4].y > floor_local_y - sc(3):
				_tail[4].y = floor_local_y - sc(3)

	# Spine points: must not penetrate platforms from above
	for i in range(3):
		var sp_world: Vector2 = global_position + _spine[i]
		var sp_floor_q := PhysicsRayQueryParameters2D.create(
			sp_world + Vector2(0, -sc(5)), sp_world + Vector2(0, sc(15)), 1)
		sp_floor_q.exclude = [get_rid()]
		var sp_hit: Dictionary = space.intersect_ray(sp_floor_q)
		if not sp_hit.is_empty():
			var floor_local_y: float = sp_hit["position"].y - global_position.y
			if _spine[i].y > floor_local_y - sc(10):
				_spine[i].y = floor_local_y - sc(10)



func _init_hitboxes() -> void:
	# Create Area2D hitboxes for each damageable part
	var parts := ["body", "head", "tail", "leg0", "leg1", "leg2", "leg3"]
	for part_name in parts:
		var area := Area2D.new()
		area.name = "Hitbox_" + part_name
		area.collision_layer = 8  # Enemy layer — detectable by projectiles
		area.collision_mask = 0
		area.set_meta("part_name", part_name)
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = sc(12.0) if part_name == "body" else sc(8.0)
		shape.shape = circle
		area.add_child(shape)
		add_child(area)
		_hitboxes[part_name] = area

	# Eye hitbox — tiny, rewards precision aim
	var eye_area := Area2D.new()
	eye_area.name = "Hitbox_eye"
	eye_area.collision_layer = 8  # Enemy layer — detectable by projectiles
	eye_area.collision_mask = 0
	eye_area.set_meta("part_name", "eye")
	var eye_shape := CollisionShape2D.new()
	var eye_circle := CircleShape2D.new()
	eye_circle.radius = sc(4.0)  # Roughly the size of the rendered eye
	eye_shape.shape = eye_circle
	eye_area.add_child(eye_shape)
	add_child(eye_area)
	_hitboxes["eye"] = eye_area


func _init_attach_points() -> void:
	## Create larger Area2D zones for item attachment (balloons, grapple).
	## These are separate from damage hitboxes — sized to match the visual body part.
	var points := {
		"head": 16.0,       # Matches skull polygon bounding circle (~32px wide)
		"tail_tip": 30.0,   # Large generous target at tail end
		"shoulders": 14.0,  # Matches spine[0] visual size (r=12 + margin)
		"waist": 12.0,      # Matches spine[2] visual size (r=10 + margin)
		"elbow_l": 8.0,     # Left arm knee/elbow joint
		"elbow_r": 8.0,     # Right arm knee/elbow joint
		"knee_l": 8.0,      # Left leg knee joint
		"knee_r": 8.0,      # Right leg knee joint
	}
	for point_name in points:
		var area := Area2D.new()
		area.name = "Attach_" + point_name
		area.collision_layer = 0
		area.collision_mask = 2  # Player projectiles can target these
		area.set_meta("attach_point", point_name)
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = sc(points[point_name])
		shape.shape = circle
		area.add_child(shape)
		add_child(area)
		_attach_points[point_name] = area
		_attachments[point_name] = []


func attach_item(point_name: String, item: Node2D) -> void:
	## Attach an item to a named attachment point.
	if not _attachments.has(point_name):
		return
	if item not in _attachments[point_name]:
		_attachments[point_name].append(item)


func detach_item(point_name: String, item: Node2D) -> void:
	## Detach an item from a named attachment point.
	if not _attachments.has(point_name):
		return
	_attachments[point_name].erase(item)


func get_attach_world_position(point_name: String) -> Vector2:
	## Get the current world position of an attachment point.
	if _attach_points.has(point_name):
		return global_position + _attach_points[point_name].position
	return global_position


func get_chain_barrier() -> Dictionary:
	## Returns the chain barrier circle: { center: Vector2, radius: float }
	## Empty dict if not chained. Used by precog to filter unreachable positions.
	if not _chained:
		return {}
	for tether in get_tree().get_nodes_in_group("tethers"):
		if not is_instance_valid(tether) or tether._severed:
			continue
		var is_mine: bool = tether.anchor_a.get("body") == self or tether.anchor_b.get("body") == self
		if not is_mine:
			continue
		var other_anchor: Dictionary = tether.anchor_b if tether.anchor_a.get("body") == self else tether.anchor_a
		var center: Vector2
		if other_anchor.get("is_wall", false):
			center = other_anchor.get("pos", Vector2.ZERO)
		elif is_instance_valid(other_anchor.get("body")):
			center = other_anchor["body"].global_position
		else:
			continue
		return { "center": center, "radius": tether.target_length }
	return {}


func _apply_chain_constraints() -> void:
	## Clamp global_position so no attached chain/tether exceeds its target length.
	## Finds all tethers/chains attached to this creature and constrains position.
	for tether in get_tree().get_nodes_in_group("tethers"):
		if not is_instance_valid(tether) or tether._severed:
			continue
		# Check if this creature is an anchor
		var is_anchor_a: bool = tether.anchor_a.get("body") == self
		var is_anchor_b: bool = tether.anchor_b.get("body") == self
		if not is_anchor_a and not is_anchor_b:
			continue
		# Get the other anchor's world position
		var other_pos: Vector2
		var other_anchor: Dictionary = tether.anchor_b if is_anchor_a else tether.anchor_a
		# Read anchor position — works for both tether.gd and chain.gd
		if other_anchor.get("is_wall", false):
			other_pos = other_anchor.get("pos", Vector2.ZERO)
		elif is_instance_valid(other_anchor.get("body")):
			var body: Node2D = other_anchor["body"]
			var ap: String = other_anchor.get("attach_point", "")
			if ap != "" and body.has_method("get_attach_world_position"):
				other_pos = body.get_attach_world_position(ap)
			else:
				other_pos = body.global_position + other_anchor.get("body_offset", Vector2.ZERO)
		else:
			other_pos = other_anchor.get("pos", global_position)
		# Determine which attachment point on THIS creature the chain connects to
		var my_anchor: Dictionary = tether.anchor_a if is_anchor_a else tether.anchor_b
		var my_attach_point: String = my_anchor.get("attach_point", "")
		var my_attach_offset: Vector2 = Vector2.ZERO
		if my_attach_point != "" and _attach_points.has(my_attach_point):
			my_attach_offset = _attach_points[my_attach_point].position

		# Check distance from the attachment point (not body center) to the other anchor
		var my_world_pos: Vector2 = global_position + my_attach_offset
		var dist: float = my_world_pos.distance_to(other_pos)
		if dist > tether.target_length:
			var dir: Vector2 = (my_world_pos - other_pos).normalized()
			if is_on_floor():
				# On floor: only constrain horizontal movement (don't yank vertically)
				var horizontal_dist: float = absf(my_world_pos.x - other_pos.x)
				# Calculate max horizontal distance allowed at current Y
				var dy: float = my_world_pos.y - other_pos.y
				var max_dx: float = sqrt(maxf(tether.target_length * tether.target_length - dy * dy, 0.0))
				if horizontal_dist > max_dx:
					var sign_x: float = signf(my_world_pos.x - other_pos.x)
					global_position.x = other_pos.x + sign_x * max_dx - my_attach_offset.x
					# Kill horizontal velocity moving away
					if (velocity.x > 0 and sign_x > 0) or (velocity.x < 0 and sign_x < 0):
						velocity.x = 0
			else:
				# Not on floor: full 2D constraint, but don't push below floor
				var new_pos: Vector2 = other_pos + dir * tether.target_length - my_attach_offset
				# Raycast to find floor below the new position
				var space := get_world_2d().direct_space_state
				if space:
					var floor_query := PhysicsRayQueryParameters2D.create(
						new_pos + Vector2(0, -20), new_pos + Vector2(0, 20), 1)
					var floor_result: Dictionary = space.intersect_ray(floor_query)
					if floor_result and new_pos.y > floor_result["position"].y:
						new_pos.y = floor_result["position"].y
				global_position = new_pos
				var vel_along: float = velocity.dot(dir)
				if vel_along > 0:
					velocity -= dir * vel_along


func set_pose_overrides(overrides: Dictionary) -> void:
	## Set IK pose override targets. Keys = attachment point names, values = local Vector2 positions.
	_pose_overrides = overrides


func clear_pose_overrides() -> void:
	_pose_overrides.clear()


func get_segment_weight(point_name: String) -> float:
	## Get the weight of a segment by attachment point name.
	if SEGMENT_WEIGHTS.has(point_name):
		return SEGMENT_WEIGHTS[point_name]
	# Map attachment point names to segment names
	match point_name:
		"tail_tip": return SEGMENT_WEIGHTS["tail"]
	return 30.0  # Default


func get_total_weight() -> float:
	var total: float = 0.0
	for w in SEGMENT_WEIGHTS.values():
		total += w
	return total


func _accumulate_attach_forces() -> void:
	## Collect forces from all attached items. Items with a `get_attach_force()` method
	## provide their force vector; balloon darts use their float force.
	_attach_forces.clear()
	for point_name in _attachments:
		var force := Vector2.ZERO
		for item in _attachments[point_name]:
			if not is_instance_valid(item):
				continue
			if item.has_method("get_attach_force"):
				force += item.get_attach_force()
			elif "_balloon_inflating" in item and item._balloon_inflating:
				# Balloon dart: use its float force based on inflation
				var inflate_ratio: float = clampf(item._balloon_timer / item.BALLOON_INFLATE_TIME, 0.0, 1.0)
				force += Vector2(0, item.BALLOON_FLOAT_FORCE * inflate_ratio * inflate_ratio)
		if force.length_squared() > 0.01:
			_attach_forces[point_name] = force


func _apply_attach_forces(delta: float) -> void:
	## Apply accumulated attachment forces to the CharacterBody2D velocity.
	## Forces move the whole monster in world space — NOT the skeleton points.
	if _attach_forces.is_empty():
		return

	var total_force := Vector2.ZERO
	for point_name in _attach_forces:
		total_force += _attach_forces[point_name]

	# Apply force to body velocity (divided by total mass)
	var body_weight: float = get_total_weight()
	velocity += total_force * delta * (200.0 / body_weight)

	# If net force is upward and strong enough, counteract gravity
	if total_force.y < 0:
		var lift_ratio: float = clampf(absf(total_force.y) / body_weight, 0.0, 2.0)
		velocity.y -= GRAVITY * delta * lift_ratio * 0.8
		# Cap upward speed
		if velocity.y < -120.0:
			velocity.y = -120.0


# -- Physics -------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _dead:
		return
	if _physics_frozen:
		velocity = Vector2.ZERO
		if _pose_locked:
			# Still draw, but skip all physics/pose solving — editor controls skeleton
			queue_redraw()
			return
		return

	# Stand-down mode: force STANDDOWN state, override any transition
	if _standdown and _state != State.STANDDOWN:
		_change_state(State.STANDDOWN)

	# Asleep mode: same as standdown but wakes on damage
	if _asleep and _state != State.STANDDOWN:
		_change_state(State.STANDDOWN)

	# Breakaway invincibility timer
	if _breakaway_immune > 0:
		_breakaway_immune -= delta

	# Out-of-bounds recovery: teleport back to spawn area
	if global_position.y > 1200 or global_position.y < -200 or global_position.x < -100 or global_position.x > 2020:
		print("MONSTER: out of bounds at (%.0f,%.0f) — teleporting back" % [global_position.x, global_position.y])
		global_position = Vector2(960, 850)
		velocity = Vector2.ZERO
		_end_leap()
		_change_state(State.CHASE)

	# First-frame: plant feet. Precache runs after a short delay (2 frames)
	# to ensure the physics space has all StaticBody2D nodes registered.
	if not _initialized:
		_initialized = true
		for li in range(4):
			var hip_local: Vector2 = _legs[li][0]
			_foot_world[li] = global_position + Vector2(hip_local.x, _raycast_floor(hip_local))
			_step_targets[li] = _foot_world[li]
			_step_origins[li] = _foot_world[li]
		if not _precog_platforms_cached:
			get_tree().create_timer(0.1).timeout.connect(_precache_platforms)

	_timer += delta
	if _attack_cooldown > 0.0:
		_attack_cooldown -= delta
	if _leap_cooldown > 0.0:
		_leap_cooldown -= delta
	if _precog_cooldown > 0.0:
		_precog_cooldown -= delta
	if _state_lock_timer > 0.0:
		_state_lock_timer -= delta

	# Chained mode: apply chain constraints before and after movement.
	# If asleep + not on floor: go limp (skip AI, dangle limbs).
	# If awake + on floor: run normal AI but constrained by chains.
	if _chained:
		# Stuck detection: if position hasn't changed in 3 seconds, abandon current plan
		if global_position.distance_to(_chained_last_pos) < 5.0:
			_chained_stuck_timer += delta
			if _chained_stuck_timer > 3.0:
				_chained_stuck_timer = 0.0
				# Abandon precog waypoint — try direct chase instead
				if _precog_has_waypoint:
					_precog_has_waypoint = false
					_precog_path_edges.clear()
				# Try a direct leap toward the target if close enough
				if is_instance_valid(_target) and _state == State.CHASE:
					var to_target: Vector2 = _target.global_position - global_position
					if to_target.length() < sc(LEAP_RANGE) and _leap_cooldown <= 0.0:
						_facing = signf(to_target.x) if absf(to_target.x) > 5.0 else _facing
						_start_leap()
		else:
			_chained_stuck_timer = 0.0
		_chained_last_pos = global_position

		var chained_on_floor: bool = is_on_floor()
		if _asleep:
			# ASLEEP: stay frozen in place, no gravity, no AI
			# Pose-locked creatures hold their skeleton shape
			velocity = Vector2.ZERO
			_enforce_spine_rigid()
			_update_hitbox_positions()
			_update_blood_particles(delta)
			queue_redraw()
			return
		elif not chained_on_floor and _state != State.ATTACK_LEAP_AIRBORNE and _state != State.ATTACK_LEAP_WINDUP:
			# AWAKE but SUSPENDED (dangling): apply gravity, constrain by chain
			# Skip during leap flight — let the leap physics run freely
			velocity.y += GRAVITY * delta
			_apply_chain_constraints()
			move_and_slide()
			_apply_chain_constraints()
			if not _pose_locked:
				_update_spine()
				for li in range(4):
					if _leg_severed[li]:
						continue
					_legs[li][2].y += GRAVITY * delta * 0.1
			_enforce_spine_rigid()
			# Enforce limb rigidity + replant unreachable feet
			for li in range(4):
				if _leg_severed[li]:
					continue
				if li < 2:
					_legs[li][0] = _clavicles[li]
				else:
					_legs[li][0] = _hip_bones[li - 2]
				if _foot_planted[li]:
					var foot_local: Vector2 = _foot_world[li] - global_position
					var reach: float = _legs[li][0].distance_to(foot_local)
					if reach > sc(LEG_UPPER_LEN) + sc(LEG_LOWER_LEN) * (1.0 + LIMB_FLEX):
						var floor_y: float = _raycast_floor(_legs[li][0])
						_legs[li][2] = Vector2(_legs[li][0].x, floor_y)
						_foot_world[li] = global_position + _legs[li][2]
				var upper_dir: Vector2 = _legs[li][1] - _legs[li][0]
				if upper_dir.length() > 0.01:
					_legs[li][1] = _legs[li][0] + upper_dir.normalized() * sc(LEG_UPPER_LEN)
				var lower_dir: Vector2 = _legs[li][2] - _legs[li][1]
				if lower_dir.length() > 0.01:
					var clamped: float = clampf(lower_dir.length(), sc(LEG_LOWER_LEN) * (1.0 - LIMB_FLEX), sc(LEG_LOWER_LEN) * (1.0 + LIMB_FLEX))
					_legs[li][2] = _legs[li][1] + lower_dir.normalized() * clamped
			_update_hitbox_positions()
			_update_blood_particles(delta)
			queue_redraw()
			return
		# AWAKE + ON FLOOR: fall through to normal AI below,
		# chain constraints applied after move_and_slide

	# Gravity (skip during airborne leap — handled by leap physics)
	if _state != State.ATTACK_LEAP_AIRBORNE:
		velocity.y += GRAVITY * delta

	# State machine (sets _want_direction and _move_speed)
	_want_direction = 0.0
	match _state:
		State.PATROL:
			_do_patrol(delta)
		State.CHASE:
			_do_chase(delta)
		State.ATTACK_BITE:
			_do_bite(delta)
		State.ATTACK_SWIPE:
			_do_swipe(delta)
		State.ATTACK_TAIL:
			_do_tail_whip(delta)
		State.ATTACK_LUNGE:
			_do_lunge(delta)
		State.ATTACK_SPRINT_SLASH:
			_do_sprint_slash(delta)
		State.ATTACK_HOP_UP:
			_do_hop_up(delta)
		State.ATTACK_GRAB:
			_do_grab(delta)
		State.ATTACK_LEAP_PLAN:
			_do_leap_plan(delta)
		State.ATTACK_LEAP_WINDUP:
			_do_leap_windup(delta)
		State.ATTACK_LEAP_AIRBORNE:
			_do_leap_airborne(delta)
		State.ATTACK_LEAP_STRIKE:
			_do_leap_strike(delta)
		State.ATTACK_LEAP_THRASH:
			_do_leap_thrash(delta)
		State.PRECOGNITION:
			_do_precognition(delta)
		State.TRANSITION_BIPEDAL:
			_do_transition_bipedal(delta)
		State.TRANSITION_QUADRUPED:
			_do_transition_quadruped(delta)
		State.STANDDOWN:
			pass  # No AI — just idle in place, skeleton still runs

	# Leap/precog states handle their own skeleton — skip normal locomotion/pose
	var in_leap_flight: bool = (_state == State.ATTACK_LEAP_WINDUP
		or _state == State.ATTACK_LEAP_AIRBORNE or _state == State.ATTACK_LEAP_STRIKE
		or _state == State.ATTACK_LEAP_THRASH)
	var in_precog: bool = (_state == State.PRECOGNITION)

	# Async graph building (2 pairs per frame)
	if _precog_graph_building:
		_precog_build_graph_tick()

	var in_grab: bool = (_state == State.ATTACK_GRAB)

	if in_leap_flight:
		_update_leap_collision(delta)
	elif not in_precog and not in_grab:
		_update_foot_push(delta)

	if in_grab:
		# During grab: FREEZE body position. Don't let move_and_slide shift us.
		# The collision sphere traps the player, not moves us.
		velocity = Vector2.ZERO
	else:
		# Apply chain constraints BEFORE move_and_slide — but NOT during
		# airborne leaps. Chain only limits ROUTE PLANNING, not flight physics.
		if _chained and not in_leap_flight:
			_apply_chain_constraints()
		move_and_slide()

	if in_leap_flight:
		_update_leap_pose(delta)
	elif in_grab:
		pass  # Grab pose is handled inside _do_grab — skip all normal skeleton updates
	elif not in_precog:
		_update_spine()
		_update_gait(delta)
		_solve_pose(delta)
	# Precognition pose is handled inside _do_precognition → _apply_curl_pose

	# ALWAYS enforce rigid distances — even during leap/grab/precog
	_enforce_spine_rigid()
	# ALWAYS enforce tail segment rigidity (±5% flex) + max 20° bend per joint
	if not _tail_severed:
		# Reference direction: spine[1] → spine[2] (the "straight back" direction)
		var prev_dir: Vector2 = (_spine[2] - _spine[1]).normalized()
		var tail_parent: Vector2 = _spine[2] + Vector2(-4 * _facing, -2)
		for ti in range(_tail.size()):
			var tail_dir: Vector2 = _tail[ti] - tail_parent
			var tail_dist: float = tail_dir.length()
			if tail_dist > 0.01:
				var current_dir: Vector2 = tail_dir.normalized()
				# Clamp angle relative to previous segment direction
				var angle_diff: float = prev_dir.angle_to(current_dir)
				if absf(angle_diff) > TAIL_MAX_BEND:
					var clamped_angle: float = prev_dir.angle() + clampf(angle_diff, -TAIL_MAX_BEND, TAIL_MAX_BEND)
					current_dir = Vector2(cos(clamped_angle), sin(clamped_angle))
				# Clamp distance (±5% flex)
				var clamped_len: float = clampf(tail_dist, sc(TAIL_SEG_LEN) * (1.0 - TAIL_FLEX), sc(TAIL_SEG_LEN) * (1.0 + TAIL_FLEX))
				_tail[ti] = tail_parent + current_dir * clamped_len
				prev_dir = current_dir
			tail_parent = _tail[ti]
	# ALWAYS enforce limb rigidity (upper = exact, lower = ±10%)
	# For planted feet: foot stays at world position, rigidity pushes knee instead
	for li in range(4):
		if _leg_severed[li]:
			continue
		# Pin hip to clavicle/hip bone endpoint
		if li < 2:
			_legs[li][0] = _clavicles[li]
		else:
			_legs[li][0] = _hip_bones[li - 2]

		if _foot_planted[li] and not _leap_ik_off:
			# Planted: foot should be at world position
			var foot_local: Vector2 = _foot_world[li] - global_position
			var hip: Vector2 = _legs[li][0]
			var reach: float = hip.distance_to(foot_local)
			var max_reach: float = sc(LEG_UPPER_LEN) + sc(LEG_LOWER_LEN) * (1.0 + LIMB_FLEX)
			if reach <= max_reach:
				# Foot is reachable — use world position
				_legs[li][2] = foot_local
			else:
				# Foot is unreachable — force replant below hip
				var floor_y: float = _raycast_floor(hip)
				_legs[li][2] = Vector2(hip.x, floor_y)
				_foot_world[li] = global_position + _legs[li][2]
			# Enforce rigid upper limb from hip toward knee
			var upper_dir: Vector2 = _legs[li][1] - _legs[li][0]
			if upper_dir.length() > 0.01:
				_legs[li][1] = _legs[li][0] + upper_dir.normalized() * sc(LEG_UPPER_LEN)
		else:
			# Not planted or IK off: enforce from hip downward
			var upper_dir: Vector2 = _legs[li][1] - _legs[li][0]
			if upper_dir.length() > 0.01:
				_legs[li][1] = _legs[li][0] + upper_dir.normalized() * sc(LEG_UPPER_LEN)
			var lower_dir: Vector2 = _legs[li][2] - _legs[li][1]
			var lower_dist: float = lower_dir.length()
			if lower_dist > 0.01:
				var clamped: float = clampf(lower_dist, sc(LEG_LOWER_LEN) * (1.0 - LIMB_FLEX), sc(LEG_LOWER_LEN) * (1.0 + LIMB_FLEX))
				_legs[li][2] = _legs[li][1] + lower_dir.normalized() * clamped

	# Affix body collider to torso (skip during grab — grab controls collision)
	if not in_grab:
		if _body_collision:
			_body_collision.position = Vector2(_spine[1].x, -sc(14.0))
		_constrain_skeleton_to_world()

	_update_hitbox_positions()
	_accumulate_attach_forces()
	_apply_attach_forces(delta)
	_update_blood_particles(delta)
	_score_ik_quality()
	_score_strategy_thrash()

	# Auto-dump: check for anomalies every 10th frame
	if Engine.get_frames_drawn() % 10 == 5:
		PlayerHUD.check_auto_dump_triggers(self)

	queue_redraw()


func _solve_pose(delta: float) -> void:
	## Pose-driven skeleton: every segment springs toward its rest position
	## relative to its parent. Nothing is floppy. The creature holds itself up.
	var s: float = STIFFNESS * delta  # Spring factor this frame
	var s_clamp: float = minf(s, 1.0)  # Don't overshoot

	# -- Spine: spine[0] is the anchor (set by _update_spine) --
	# spine[1] and [2] follow from spine[0] via rest offsets
	for i in range(1, 3):
		var rest_target: Vector2 = _spine[i - 1] + _get_facing_offset(_spine_rest[i])
		_spine[i] = _spine[i].lerp(rest_target, s_clamp)

	# -- Neck + Skull: head pivots toward target, neck bends to follow --
	_neck[0] = _spine[0]
	var neck_rest_target: Vector2 = _spine[0] + _get_facing_offset(_neck_rest)
	var skull_rest_target: Vector2 = neck_rest_target + _get_facing_offset(_skull_rest)

	if is_instance_valid(_target) and not _head_severed:
		# Skull aims directly at target
		var to_target: Vector2 = _target.global_position - global_position
		var aim_dir: Vector2 = to_target.normalized()

		# Place skull along the aim direction, at the right distance from spine[0]
		var skull_dist: float = sc(NECK_LEN) + _skull_rest.length()
		var skull_aim: Vector2 = _spine[0] + aim_dir * skull_dist
		skull_rest_target = skull_rest_target.lerp(skull_aim, 0.7)

		# Neck tip bends toward skull — positioned between spine[0] and skull
		var neck_toward_skull: Vector2 = (skull_rest_target - _spine[0]).normalized()
		var neck_aim: Vector2 = _spine[0] + neck_toward_skull * NECK_LEN
		# Blend with rest pose so neck doesn't fully collapse
		neck_rest_target = neck_rest_target.lerp(neck_aim, 0.6)

	_neck[1] = _neck[1].lerp(neck_rest_target, minf(HEAD_TRACK_SPEED * delta, 1.0))
	_skull = _skull.lerp(skull_rest_target, minf(HEAD_TRACK_SPEED * delta, 1.0))

	# -- Jaw: springs from skull, opens for bite --
	var jaw_offset: Vector2 = _get_facing_offset(_jaw_rest)
	jaw_offset.y += _jaw_open * JAW_LEN * 0.5  # Open jaw
	_jaw = _jaw.lerp(_skull + jaw_offset, s_clamp)

	# -- Tail: rigid by default, loose only during whip --
	if not _tail_severed:
		var tail_s: float = (TAIL_WHIP_STIFFNESS if _tail_whipping else TAIL_STIFFNESS) * delta
		tail_s = minf(tail_s, 1.0)
		var parent: Vector2 = _spine[2] + Vector2(-4 * _facing, -2)
		for i in range(5):
			var rest_target: Vector2 = parent + _get_facing_offset(_tail_rest[i])
			_tail[i] = _tail[i].lerp(rest_target, tail_s)
			parent = _tail[i]

	# -- Clavicles + Hip bones --
	# During leap or grab, pin tight to spine (no perpendicular spread)
	var in_special_pose: bool = _leap_ik_off or _state == State.ATTACK_GRAB or _state == State.PRECOGNITION
	if in_special_pose:
		# Pin clavicles directly below spine[0], hip bones below spine[2]
		for ci in range(2):
			var side: float = -3.0 if ci == 0 else 3.0
			_clavicles[ci] = _spine[0] + Vector2(side, 6)
		for hi in range(2):
			var side: float = -3.0 if hi == 0 else 3.0
			_hip_bones[hi] = _spine[2] + Vector2(side, 6)
	else:
		# Normal: perpendicular to spine, rotate with body
		var spine_fwd: Vector2 = (_spine[0] - _spine[1]).normalized()
		var spine_down: Vector2 = Vector2(-spine_fwd.y, spine_fwd.x)
		if spine_down.y < 0:
			spine_down = -spine_down
		for ci in range(2):
			var side: float = -1.0 if ci == 0 else 1.0
			var rest_dir: Vector2 = (spine_down + spine_fwd * side * 0.3).normalized()
			var rest_target: Vector2 = _spine[0] + rest_dir * sc(CLAVICLE_LEN)
			_clavicles[ci] = _clavicles[ci].lerp(rest_target, s_clamp)
			var dir: Vector2 = _clavicles[ci] - _spine[0]
			if dir.length() > 0.01:
				_clavicles[ci] = _spine[0] + dir.normalized() * sc(CLAVICLE_LEN)

		var spine_back: Vector2 = (_spine[2] - _spine[1]).normalized()
		var spine_down2: Vector2 = Vector2(-spine_back.y, spine_back.x)
		if spine_down2.y < 0:
			spine_down2 = -spine_down2
		for hi in range(2):
			var side: float = -1.0 if hi == 0 else 1.0
			var rest_dir: Vector2 = (spine_down2 + spine_back * side * 0.3).normalized()
			var rest_target: Vector2 = _spine[2] + rest_dir * sc(HIP_BONE_LEN)
			_hip_bones[hi] = _hip_bones[hi].lerp(rest_target, s_clamp)
			var dir: Vector2 = _hip_bones[hi] - _spine[2]
			if dir.length() > 0.01:
				_hip_bones[hi] = _spine[2] + dir.normalized() * sc(HIP_BONE_LEN)

	# -- Legs: 2-bone IK from hip to foot, knee solved --
	var max_leg_reach: float = sc(LEG_UPPER_LEN) + sc(LEG_LOWER_LEN)
	for li in range(4):
		if _leg_severed[li]:
			for j in range(3):
				_legs[li][j].y += GRAVITY * delta * 0.3
			continue

		# Hip: pinned to clavicle endpoint (arms) or hip bone endpoint (legs)
		var hip_anchor: Vector2
		if li < 2:
			hip_anchor = _clavicles[li]
		else:
			hip_anchor = _hip_bones[li - 2]
		_legs[li][0] = hip_anchor

		if _leap_ik_off:
			continue

		# Sanity check: if foot is too far from hip, force replant below hip
		var hip: Vector2 = _legs[li][0]
		var foot: Vector2 = _legs[li][2]
		var hip_to_foot: float = hip.distance_to(foot)
		if hip_to_foot > max_leg_reach * 1.2:
			# Replant foot directly below hip at floor level
			var floor_y: float = _raycast_floor(hip)
			_legs[li][2] = Vector2(hip.x, floor_y)
			_foot_world[li] = global_position + _legs[li][2]
			_foot_planted[li] = true

		# Knee: solved via 2-bone IK — snap quickly (no slow lerp)
		var bend_dir: float = 1.0 if li < 2 else -1.0
		bend_dir *= _facing
		var knee_pos: Vector2 = _solve_leg_ik(
			_legs[li][0], _legs[li][2],
			sc(LEG_UPPER_LEN), sc(LEG_LOWER_LEN),
			bend_dir
		)
		# Snap knee to IK solution (fast lerp to prevent sticking)
		_legs[li][1] = _legs[li][1].lerp(knee_pos, minf(s * 2.0, 1.0))

		# -- Rigid upper limb: enforce exact LEG_UPPER_LEN from hip to knee --
		var upper_dir: Vector2 = _legs[li][1] - _legs[li][0]
		if upper_dir.length() > 0.01:
			_legs[li][1] = _legs[li][0] + upper_dir.normalized() * sc(LEG_UPPER_LEN)

		# -- Flex lower limb: enforce LEG_LOWER_LEN ±10% from knee to foot --
		var lower_dir: Vector2 = _legs[li][2] - _legs[li][1]
		var lower_dist: float = lower_dir.length()
		if lower_dist > 0.01:
			var min_len: float = sc(LEG_LOWER_LEN) * (1.0 - LIMB_FLEX)
			var max_len: float = sc(LEG_LOWER_LEN) * (1.0 + LIMB_FLEX)
			var clamped_len: float = clampf(lower_dist, min_len, max_len)
			_legs[li][2] = _legs[li][1] + lower_dir.normalized() * clamped_len

	# -- Pose overrides (splay system) --
	if not _pose_overrides.is_empty():
		var blend: float = POSE_OVERRIDE_BLEND
		if _pose_overrides.has("head"):
			_skull = _skull.lerp(_pose_overrides["head"], blend * minf(s, 1.0))
		if _pose_overrides.has("tail_tip") and not _tail_severed:
			_tail[4] = _tail[4].lerp(_pose_overrides["tail_tip"], blend * minf(s, 1.0))
		if _pose_overrides.has("shoulders"):
			_spine[0] = _spine[0].lerp(_pose_overrides["shoulders"], blend * minf(s, 1.0))
		if _pose_overrides.has("waist"):
			_spine[2] = _spine[2].lerp(_pose_overrides["waist"], blend * minf(s, 1.0))

	# -- Rigid distance constraints (segments can rotate but never stretch) --
	_enforce_spine_rigid()

	# -- Floor constraints (raycast-based) --
	if not _tail_severed:
		for i in range(_tail.size()):
			var tail_floor: float = _raycast_floor(_tail[i])
			if _tail[i].y > tail_floor:
				_tail[i].y = tail_floor
	var head_floor: float = _raycast_floor(_skull)
	if _skull.y > head_floor - 4.0:
		_skull.y = head_floor - 4.0
	if _jaw.y > head_floor - 2.0:
		_jaw.y = head_floor - 2.0


func _score_ik_quality() -> void:
	## Score how "good" the IK looks this frame. Lower = better.
	## Only runs every 10th frame to avoid FPS impact from raycasts.
	if _leap_ik_off or _state == State.PRECOGNITION:
		return
	if Engine.get_frames_drawn() % 10 != 0:
		return

	var max_reach: float = sc(LEG_UPPER_LEN) + sc(LEG_LOWER_LEN)
	var score: float = 0.0

	for li in range(4):
		if _leg_severed[li]:
			continue

		var hip: Vector2 = _legs[li][0]
		var foot: Vector2 = _legs[li][2]

		# Spread: horizontal distance from foot to hip
		var spread: float = absf(foot.x - hip.x)
		if spread > 30.0:
			score += (spread - 30.0) * 2.0  # 2 points per px over 30

		# Stretch: hip-to-foot total distance vs max reach
		var dist: float = hip.distance_to(foot)
		if dist > max_reach:
			score += (dist - max_reach) * 5.0  # 5 points per px over max

		# Hover: planted foot distance from floor
		if _foot_planted[li]:
			var floor_y: float = _raycast_floor(foot)
			var hover: float = floor_y - foot.y  # Positive = foot is above floor
			if hover > 5.0:
				score += hover * 3.0  # 3 points per px of hover

	_ik_score = score
	_ik_score_samples += 1
	_ik_score_avg = lerpf(_ik_score_avg, score, 0.05)  # Exponential moving average
	if score > _ik_score_peak:
		_ik_score_peak = score


func _score_ball_quality(center: Vector2, radius: float) -> void:
	## Score how well the ball contains all body parts (in LOCAL space).
	## Each px outside = penalty. 0 = perfect. Checks rendered positions.
	var score: float = 0.0
	var margin: float = radius + 12.0

	var points: Array[Vector2] = [_spine[0], _spine[1], _spine[2], _neck[0], _neck[1], _skull, _jaw]
	for pt in points:
		var d: float = pt.distance_to(center)
		if d > margin:
			score += (d - margin) * 2.0

	# Check all leg joints
	for li in range(4):
		if _leg_severed[li]:
			continue
		for j in range(3):
			var d: float = _legs[li][j].distance_to(center)
			if d > margin:
				score += (d - margin) * 1.5

	# Check tail points
	if not _tail_severed:
		for i in range(_tail.size()):
			var d: float = _tail[i].distance_to(center)
			# Tail gets extra margin (spirals outward)
			var tail_margin: float = margin + float(i) * 4.0
			if d > tail_margin:
				score += (d - tail_margin)

	_ball_score = score
	if score > _ball_score_peak:
		_ball_score_peak = score


func _score_strategy_thrash() -> void:
	## Track strategy changes. Reset when the target moves significantly.
	## Note: _strategy_changes and _last_state are updated by _change_state().
	if is_instance_valid(_target):
		var target_moved: float = _target.global_position.distance_to(_last_target_pos)
		if target_moved > 30.0:
			_strategy_changes = 0
			_last_target_pos = _target.global_position


func _get_facing_offset(offset: Vector2) -> Vector2:
	## Flip x component based on facing direction.
	## Rest offsets are stored for _facing=1. Flip x if facing left.
	if _facing < 0:
		return Vector2(-offset.x, offset.y)
	return offset


func _enforce_rigid_distance(anchor: Vector2, point: Vector2, target_dist: float) -> void:
	## Enforce that point is exactly target_dist away from anchor.
	## Preserves the angle, only corrects the distance. Modifies point in-place
	## by finding which variable holds the reference.
	## NOTE: GDScript passes Vector2 by value, so we use the actual arrays.
	pass


func _enforce_spine_rigid() -> void:
	## Enforce rigid distances + max bend angles between all connected segments.
	## When _pose_locked: only enforce distances (skip angle constraints — pose may be non-standard orientation).
	# Spine chain: spine[0] is the anchor
	if _pose_locked:
		# Distance-only enforcement — preserve the current angles
		for i in range(1, 3):
			var dir: Vector2 = (_spine[i] - _spine[i - 1])
			if dir.length() > 0.01:
				_spine[i] = _spine[i - 1] + dir.normalized() * sc(SPINE_SEG_LEN)
	else:
		# Full enforcement: distances + max 30° bend angles
		# Reference direction for spine[0]→[1]: facing direction (horizontal)
		var spine_ref_dir: Vector2 = Vector2(-_facing, 0)  # spine goes backward
		for i in range(1, 3):
			var dir: Vector2 = (_spine[i] - _spine[i - 1])
			if dir.length() > 0.01:
				var current_dir: Vector2 = dir.normalized()
				var angle_diff: float = spine_ref_dir.angle_to(current_dir)
				if absf(angle_diff) > SPINE_MAX_BEND:
					var clamped_angle: float = spine_ref_dir.angle() + clampf(angle_diff, -SPINE_MAX_BEND, SPINE_MAX_BEND)
					current_dir = Vector2(cos(clamped_angle), sin(clamped_angle))
				_spine[i] = _spine[i - 1] + current_dir * sc(SPINE_SEG_LEN)
				spine_ref_dir = current_dir

	# Neck: distance enforcement (+ angle constraints when not pose_locked)
	_neck[0] = _spine[0]
	var neck_dir: Vector2 = (_neck[1] - _spine[0])
	if neck_dir.length() > 0.01:
		var current_dir: Vector2 = neck_dir.normalized()
		if not _pose_locked:
			# Angle constraint: 45° max bend from spine forward direction
			var neck_ref_dir: Vector2 = (_spine[0] - _spine[1]).normalized()
			var angle_diff: float = neck_ref_dir.angle_to(current_dir)
			if absf(angle_diff) > NECK_MAX_BEND:
				var clamped_angle: float = neck_ref_dir.angle() + clampf(angle_diff, -NECK_MAX_BEND, NECK_MAX_BEND)
				current_dir = Vector2(cos(clamped_angle), sin(clamped_angle))
		_neck[1] = _spine[0] + current_dir * sc(NECK_LEN)

	# Skull: distance enforcement (+ angle constraints when not pose_locked)
	var skull_dist: float = _skull_rest.length()
	var skull_dir: Vector2 = (_skull - _neck[1])
	if skull_dir.length() > 0.01:
		var current_dir: Vector2 = skull_dir.normalized()
		if not _pose_locked:
			var skull_ref_dir: Vector2 = (_neck[1] - _spine[0]).normalized()
			var angle_diff: float = skull_ref_dir.angle_to(current_dir)
			if absf(angle_diff) > NECK_MAX_BEND:
				var clamped_angle: float = skull_ref_dir.angle() + clampf(angle_diff, -NECK_MAX_BEND, NECK_MAX_BEND)
				current_dir = Vector2(cos(clamped_angle), sin(clamped_angle))
		_skull = _neck[1] + current_dir * skull_dist

	# Clavicles: rigid from spine[0]
	for ci in range(2):
		var cdir: Vector2 = _clavicles[ci] - _spine[0]
		if cdir.length() > 0.01:
			_clavicles[ci] = _spine[0] + cdir.normalized() * sc(CLAVICLE_LEN)

	# Hip bones: rigid from spine[2]
	for hi in range(2):
		var hdir: Vector2 = _hip_bones[hi] - _spine[2]
		if hdir.length() > 0.01:
			_hip_bones[hi] = _spine[2] + hdir.normalized() * sc(HIP_BONE_LEN)


# -- Spine & Posture ----------------------------------------------------------

func _update_spine() -> void:
	# Spine height is relative to the real floor under the body.
	# Raycast from body center to find the floor, then position spine above it.
	var floor_y: float = _raycast_floor(Vector2(0, _spine[1].y if _spine.size() > 1 else -30))
	var leg_reach: float = sc(LEG_UPPER_LEN) + sc(LEG_LOWER_LEN) - sc(4.0)  # How high above floor
	var body_y: float = floor_y - leg_reach
	# In bipedal, front raises higher
	var spine_y_front: float = lerpf(body_y, body_y - sc(30.0), _posture_blend)
	_spine[0] = Vector2(sc(SPINE_SEG_LEN) * _facing, spine_y_front)
	# spine[1] and [2] follow via _solve_pose constraints


# -- Foot-Driven Locomotion ----------------------------------------------------
# Feet grip the ground in WORLD SPACE. Planted feet push the body forward.
# Body moves as a RESULT of foot forces, not the other way around.

func _update_foot_push(delta: float) -> void:
	## Planted feet exert a push force on the body based on AI intent (_want_direction).
	## This replaces direct velocity control — the body only moves because feet push it.
	if _state == State.DEAD:
		return

	var push_x: float = 0.0
	var planted_count: int = 0

	for li in range(4):
		if _leg_severed[li] or not _foot_planted[li]:
			continue
		planted_count += 1

		# Each planted foot pushes the body in the desired direction.
		# Force scales with desired speed.
		push_x += _want_direction * sc(FOOT_PUSH_FORCE) * (_move_speed / _effective_speed(SPEED_MEDIUM))

	# More planted feet = more traction = more force
	if planted_count > 0:
		velocity.x += push_x * delta
		# Friction/grip: dampen velocity when feet are planted (prevents sliding)
		velocity.x *= FOOT_GRIP
	else:
		# No feet planted = no traction, body slides freely
		velocity.x *= 0.98

	# Clamp to desired speed
	velocity.x = clampf(velocity.x, -_move_speed, _move_speed)


func _update_gait(delta: float) -> void:
	if _state == State.DEAD:
		return

	# Idle breathing
	_breathe_time += delta
	var breathe_offset: float = sin(_breathe_time * 2.0) * sc(1.5)
	for i in range(3):
		_spine[i].y += breathe_offset * delta * 4.0

	# Convert planted feet from world space to local space for rendering/IK
	var max_reach: float = sc(LEG_UPPER_LEN) + sc(LEG_LOWER_LEN)
	for li in range(4):
		if _leg_severed[li]:
			continue
		if _foot_planted[li]:
			var local_foot: Vector2 = _foot_world[li] - global_position
			var hip: Vector2 = _legs[li][0]
			var hip_to_foot_dist: float = hip.distance_to(local_foot)

			# Clamp: foot must not be wildly far from hip
			if hip_to_foot_dist > max_reach * 1.5:
				local_foot = hip + (local_foot - hip).normalized() * max_reach
				_foot_world[li] = global_position + local_foot
				_foot_planted[li] = false  # Force a new step to correct

			# Clamp: foot must not reach down to a lower platform
			if local_foot.y > hip.y + max_reach * 1.3:
				local_foot.y = hip.y + max_reach
				_foot_world[li] = global_position + local_foot
				_foot_planted[li] = false

			# Clamp: foot must stay roughly under the body horizontally
			var max_x_offset: float = sc(40.0)  # Max horizontal distance from hip
			if absf(local_foot.x - hip.x) > max_x_offset:
				local_foot.x = hip.x + signf(local_foot.x - hip.x) * max_x_offset
				_foot_world[li] = global_position + local_foot
				_foot_planted[li] = false

			_legs[li][2] = local_foot

	# At most one front foot and one back foot step at a time.
	# Within each pair (front 0/1, rear 2/3), only the one that's
	# furthest behind can step — and only if the other is planted.
	_try_step_pair(0, 1)  # Front legs
	_try_step_pair(2, 3)  # Rear legs

	# Animate active steps
	for li in range(4):
		if _leg_severed[li]:
			continue
		if _posture == Posture.BIPEDAL and li < 2:
			continue
		_animate_step(li, delta)


func _is_leg_stepping(li: int) -> bool:
	return not _foot_planted[li] and not _leg_severed[li]


func _try_step_pair(a: int, b: int) -> void:
	## Within a pair (e.g. front-left/front-right), only one can step at a time.
	## The one furthest from its ideal position gets priority.
	var a_stepping: bool = _is_leg_stepping(a)
	var b_stepping: bool = _is_leg_stepping(b)

	# If one is already mid-step, don't start another
	if a_stepping or b_stepping:
		return

	var a_ok: bool = not _leg_severed[a] and _foot_planted[a]
	var b_ok: bool = not _leg_severed[b] and _foot_planted[b]

	if not a_ok and not b_ok:
		return

	# Measure how far behind each foot is
	var a_dist: float = 0.0
	var b_dist: float = 0.0
	if a_ok:
		a_dist = _foot_world[a].distance_to(_ideal_foot_world(a))
	if b_ok:
		b_dist = _foot_world[b].distance_to(_ideal_foot_world(b))

	# Only step the one that's furthest behind (and past threshold)
	if a_dist >= b_dist and a_dist > sc(STEP_THRESHOLD):
		_try_step(a)
	elif b_dist > sc(STEP_THRESHOLD):
		_try_step(b)


func _ideal_foot_world(li: int) -> Vector2:
	## Where this foot SHOULD be in world space: directly below the hip
	## with a small forward offset based on movement direction.
	var hip_local: Vector2 = _legs[li][0]
	var hip_world: Vector2 = global_position + hip_local
	# Small stride offset — keeps feet mostly under the body
	var stride: float = _want_direction * minf(_move_speed * 0.1, sc(20.0))
	if li >= 2:
		# Rear legs: slightly behind
		stride *= -0.3
	var target_x: float = hip_world.x + stride
	var floor_y: float = _raycast_floor(Vector2(target_x - global_position.x, hip_local.y)) + global_position.y
	return Vector2(target_x, floor_y)


func _try_step(li: int) -> void:
	## Check if a planted foot has fallen too far behind and needs to step.
	if _leg_severed[li] or not _foot_planted[li]:
		return
	if _posture == Posture.BIPEDAL and li < 2:
		return

	var foot_pos: Vector2 = _foot_world[li]
	var ideal: Vector2 = _ideal_foot_world(li)
	var dist: float = foot_pos.distance_to(ideal)

	if dist > sc(STEP_THRESHOLD):
		# Start a step: foot lifts from current world position to new ideal
		_foot_planted[li] = false
		_step_timers[li] = STEP_DURATION
		_step_origins[li] = foot_pos

		# Overshoot past the ideal position
		var toward_ideal: Vector2 = ideal - foot_pos
		_step_targets[li] = ideal + toward_ideal.normalized() * toward_ideal.length() * STEP_OVERSHOOT
		# Raycast the target to make sure it lands on actual floor
		var target_local_x: float = _step_targets[li].x - global_position.x
		var target_floor_y: float = _raycast_floor(Vector2(target_local_x, _legs[li][0].y)) + global_position.y
		_step_targets[li].y = target_floor_y

		# Bezier midpoint: lifted arc between start and end
		_step_center[li] = (foot_pos + _step_targets[li]) * 0.5 + Vector2(0, -sc(STEP_HEIGHT))


func _animate_step(li: int, delta: float) -> void:
	## Animate a stepping foot along a bezier arc in WORLD space.
	if _foot_planted[li]:
		return

	_step_timers[li] -= delta
	var t: float = 1.0 - clampf(_step_timers[li] / STEP_DURATION, 0.0, 1.0)

	# Quadratic bezier in world space
	var p0: Vector2 = _step_origins[li]
	var p1: Vector2 = _step_center[li]
	var p2: Vector2 = _step_targets[li]
	var a: Vector2 = p0.lerp(p1, t)
	var b: Vector2 = p1.lerp(p2, t)
	var world_pos: Vector2 = a.lerp(b, t)

	# Convert to local for rendering
	_legs[li][2] = world_pos - global_position

	if _step_timers[li] <= 0.0:
		# Re-raycast floor at landing position to snap to actual surface
		var land_local: Vector2 = _step_targets[li] - global_position
		var floor_y: float = _raycast_floor(land_local) + global_position.y
		var land_pos := Vector2(_step_targets[li].x, floor_y)
		_foot_planted[li] = true
		_foot_world[li] = land_pos
		_legs[li][2] = land_pos - global_position


# -- Floor raycasting ----------------------------------------------------------

func _raycast_floor(local_from: Vector2) -> float:
	## Raycast downward from a local-space point to find the world floor.
	## Returns the floor y in local space, or a fallback if no hit.
	var space := get_world_2d().direct_space_state
	if not space:
		return local_from.y + sc(LEG_UPPER_LEN) + sc(LEG_LOWER_LEN)

	var world_from: Vector2 = global_position + local_from
	var world_to: Vector2 = world_from + Vector2(0, sc(200))  # Cast 200px down (scaled)
	var query := PhysicsRayQueryParameters2D.create(world_from, world_to, 1)  # Mask 1 = world
	query.exclude = [get_rid()]
	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return local_from.y + sc(LEG_UPPER_LEN) + sc(LEG_LOWER_LEN)  # Fallback: dangle at full leg length
	return result["position"].y - global_position.y  # Convert back to local space


# -- 2-Bone IK (legs) ---------------------------------------------------------

func _solve_leg_ik(hip: Vector2, foot: Vector2, upper_len: float, lower_len: float, bend_dir: float) -> Vector2:
	## Given hip and foot positions, solve for knee position using 2-bone IK.
	## bend_dir: 1.0 = knee bends forward (front legs), -1.0 = knee bends backward (rear legs).
	var to_foot: Vector2 = foot - hip
	var dist: float = to_foot.length()

	# Clamp distance to reachable range
	var max_reach: float = upper_len + lower_len - 0.5
	var min_reach: float = absf(upper_len - lower_len) + 0.5
	dist = clampf(dist, min_reach, max_reach)
	to_foot = to_foot.normalized() * dist

	# Law of cosines: find angle at hip
	var cos_angle: float = clampf(
		(upper_len * upper_len + dist * dist - lower_len * lower_len) / (2.0 * upper_len * dist),
		-1.0, 1.0
	)
	var angle: float = acos(cos_angle)

	# Direction from hip to foot
	var base_angle: float = to_foot.angle()

	# Knee bends perpendicular to hip-foot line
	var knee_angle: float = base_angle + angle * bend_dir
	var knee: Vector2 = hip + Vector2(cos(knee_angle), sin(knee_angle)) * upper_len

	return knee


# -- AI / State Machine -------------------------------------------------------

func _do_patrol(_delta: float) -> void:
	_move_speed = _effective_speed(SPEED_SLOW)
	_want_direction = _facing

	_pick_target()
	if _target and is_instance_valid(_target):
		_change_state(State.CHASE)


func _do_chase(_delta: float) -> void:
	if not is_instance_valid(_target):
		_change_state(State.PATROL)
		return

	_pick_target()  # Check aggro switch

	# If we have a precog waypoint, walk there then leap
	# Reset the no-hit timer while executing a precog plan (don't re-trigger)
	if _precog_has_waypoint or not _precog_path_edges.is_empty():
		_time_since_strike_range = 0.0

	# Chained: abandon precog if the FINAL TARGET is unreachable by chain.
	# Allow intermediate waypoints even if outside range — the chain constraint
	# will physically limit how far the creature goes, and it might still reach
	# the target via a shorter path.
	if _precog_has_waypoint and _chained and is_instance_valid(_target):
		for tether in get_tree().get_nodes_in_group("tethers"):
			if not is_instance_valid(tether) or tether._severed:
				continue
			if tether.anchor_a.get("body") == self or tether.anchor_b.get("body") == self:
				var other_anchor: Dictionary = tether.anchor_b if tether.anchor_a.get("body") == self else tether.anchor_a
				var anchor_pos: Vector2
				if other_anchor.get("is_wall", false):
					anchor_pos = other_anchor.get("pos", Vector2.ZERO)
				elif is_instance_valid(other_anchor.get("body")):
					anchor_pos = other_anchor["body"].global_position
				else:
					continue
				# Check if the TARGET (not waypoint) is unreachable
				var target_dist: float = _target.global_position.distance_to(anchor_pos)
				if target_dist > tether.target_length:
					DebugOverlay.log("precog/current_path", self, "PRECOG CHAIN ABORT: target dist=%.0f > chain len=%.0f", [target_dist, tether.target_length])
					_precog_has_waypoint = false
					_precog_path_edges.clear()
					break

	if _precog_has_waypoint:
		var to_waypoint: Vector2 = _precog_waypoint - global_position
		var waypoint_dist: float = absf(to_waypoint.x)
		if Engine.get_frames_drawn() % 30 == 0:
			DebugOverlay.log("pathing/walk_run_path", self, "PRECOG WALK: wpt=(%.0f,%.0f) me=(%.0f,%.0f) dx=%.0f edge_empty=%s", [
				_precog_waypoint.x, _precog_waypoint.y,
				global_position.x, global_position.y,
				waypoint_dist, str(_precog_waypoint_edge.is_empty())])
		_facing = signf(to_waypoint.x) if absf(to_waypoint.x) > 5.0 else _facing
		_want_direction = signf(to_waypoint.x)
		_move_speed = _effective_speed(SPEED_FAST)

		var arrival_tolerance: float = sc(50.0) if _chained else sc(25.0)
		if waypoint_dist < arrival_tolerance:
			_precog_has_waypoint = false
			var has_vel: bool = _precog_waypoint_edge.has("launch_vel")
			var vel_val: String = str(_precog_waypoint_edge.get("launch_vel", "NONE"))
			var has_arcs: bool = _precog_waypoint_edge.has("arc_l") and _precog_waypoint_edge.has("arc_r")
			DebugOverlay.log("pathing/waypoints", self, "PRECOG: ARRIVED. has_vel=%s vel=%s has_arcs=%s edge_keys=%s", [
				str(has_vel), vel_val, str(has_arcs), str(_precog_waypoint_edge.keys())])

			if not _precog_waypoint_edge.is_empty() and _precog_waypoint_edge.has("launch_vel"):
				# Use the pre-computed velocity — the arrival threshold ensures
				# we're close enough to the planned launch point.
				var edge: Dictionary = _precog_waypoint_edge
				DebugOverlay.log("pathing/platform_leap_path", self, "PRECOG: EXECUTING leap vel=(%.0f,%.0f)", [edge["launch_vel"].x, edge["launch_vel"].y])
				if is_instance_valid(_target):
					_leap_target_pos = _target.global_position
				else:
					_leap_target_pos = edge.get("arrival", global_position)
				set_meta("_leap_chosen_vel", edge["launch_vel"])
				_leap_launch_pos = global_position
				_leap_chosen_arc_l = edge["arc_l"]
				_leap_chosen_arc_r = edge["arc_r"]
				_leap_found_path = true
				_leap_plan_results.clear()
				_leap_plan_results.append({
					"pos": global_position,
					"arc_l": edge["arc_l"],
					"arc_r": edge["arc_r"],
					"clear": true,
					"arc_ratio": 0.5,
					"launch_vel": edge["launch_vel"],
				})
				# Force facing to match launch direction, then enter windup
				var launch_vel: Vector2 = edge.get("launch_vel", Vector2.ZERO)
				if absf(launch_vel.x) > 5.0:
					_facing = signf(launch_vel.x)
				set_meta("_precog_leap", true)  # Flag: don't adjust velocity in windup
				_change_state(State.ATTACK_LEAP_WINDUP)
				_attack_timer = 0.0
				_leap_ik_off = true
				_leap_cooldown = LEAP_COOLDOWN
				velocity.x = 0
			else:
				_leap_cooldown = 0.0
		return

	var to_target: Vector2 = _target.global_position - global_position
	_facing = signf(to_target.x) if absf(to_target.x) > 5.0 else _facing
	_want_direction = _facing
	var dist: float = absf(to_target.x)

	# Speed based on distance (thresholds scale with body size)
	if dist > sc(200.0):
		_move_speed = _effective_speed(SPEED_FAST)
	elif dist > sc(80.0):
		_move_speed = _effective_speed(SPEED_MEDIUM)
	else:
		_move_speed = _effective_speed(SPEED_SLOW)

	# Don't change strategy while locked (prevents thrashing)
	if _state_lock_timer > 0.0:
		# Just chase — don't trigger precog or change attack strategy
		return

	# If target is on a different platform, use precog pathfinding.
	# Triggers when: target is above/below OR target is across a gap (same height
	# but far horizontally with no floor between). The "across a gap" case catches
	# P1→P2 and similar same-level platform hops.
	var target_above: bool = to_target.y < -80.0
	var target_far_below: bool = to_target.y > 120.0
	var target_across_gap: bool = false
	if not target_above and not target_far_below and dist > 200.0:
		# Check if there's a gap between us and the target by probing the floor
		# ahead. If there's no floor within 100px below our current Y at the
		# midpoint between us and the target, there's a gap.
		var mid_x: float = global_position.x + to_target.x * 0.5
		var probe_from := Vector2(mid_x, global_position.y - 10)
		var probe_to := Vector2(mid_x, global_position.y + 100)
		var space := get_world_2d().direct_space_state
		if space:
			var query := PhysicsRayQueryParameters2D.create(probe_from, probe_to, 1)
			query.exclude = [get_rid()]
			var result: Dictionary = space.intersect_ray(query)
			if result.is_empty():
				target_across_gap = true
				DebugOverlay.log("pathing/waypoints", self, "GAP DETECTED: mid_x=%.0f no floor below", [mid_x])
	if (target_above or target_far_below or target_across_gap) and not _precog_has_waypoint:
		if _leap_cooldown <= 0.0:
			_start_precognition()
		return  # Don't fall through to _choose_attack when target is on different platform

	# Don't interrupt precog execution with regular attacks or re-triggers
	if _precog_has_waypoint:
		return

	# Fallback: if we haven't hit anything for a while, also use precog
	_time_since_strike_range += _delta
	if _time_since_strike_range >= PRECOG_TRIGGER_TIME:
		_start_precognition()
		return

	# Choose attack when in range (same level / close enough)
	if _attack_cooldown <= 0.0:
		_choose_attack(dist, to_target)


func _choose_attack(dist: float, to_target: Vector2) -> void:
	var target_behind: bool = signf(to_target.x) != _facing
	var height_diff: float = to_target.y  # Negative = target is above
	var dist_2d: float = to_target.length()

	# DEATH BALL GRAB: very close / overlapping — highest priority
	if dist_2d < sc(GRAB_RANGE) and not _grab_disabled:
		_start_grab()
		return

	# Tail whip if target is behind and close
	if target_behind and dist < sc(TAIL_RANGE) and _posture == Posture.QUADRUPED and not _tail_severed:
		_start_attack(State.ATTACK_TAIL)
		return

	# CONNECTED HOP-UP: target is on a platform just above (short climb)
	if height_diff < -sc(20.0) and absf(height_diff) < sc(HOP_UP_MAX_HEIGHT) and absf(to_target.x) < sc(150.0):
		_start_hop_up(to_target)
		return

	# SPRINT SLASH: same level, medium range — charge and slash
	if absf(height_diff) < sc(30.0) and dist > sc(BITE_RANGE) and dist < sc(200.0) and _count_front_legs() >= 1:
		_start_sprint_slash()
		return

	# VERTICAL LEAP: significant distance — must face target horizontally
	if dist > sc(80.0) and dist < sc(LEAP_RANGE) and _leap_cooldown <= 0.0 and _count_active_legs() >= 2:
		var facing_target: bool = (to_target.x > 0 and _facing > 0) or (to_target.x < 0 and _facing < 0) or absf(to_target.x) < sc(20.0)
		if facing_target:
			_start_leap()
			return

	# Lunge at medium distance
	if dist_2d > sc(80.0) and dist_2d < sc(200.0) and randf() < 0.3:
		_start_attack(State.ATTACK_LUNGE)
		return

	# Close range: bite or standing swipe
	if dist_2d < sc(BITE_RANGE):
		if randf() < 0.6 or _count_front_legs() == 0:
			_start_attack(State.ATTACK_BITE)
		else:
			_change_state(State.TRANSITION_BIPEDAL)
			_attack_timer = 0.0
		return


func _start_attack(attack_state: State) -> void:
	_change_state(attack_state)
	_attack_timer = 0.0
	_attack_cooldown = ATTACK_COOLDOWN
	_state_lock_timer = 1.5  # Commit to this attack


func _count_front_legs() -> int:
	var count: int = 0
	if not _leg_severed[0]: count += 1
	if not _leg_severed[1]: count += 1
	return count


func _count_active_legs() -> int:
	var count: int = 0
	for i in range(4):
		if not _leg_severed[i]:
			count += 1
	return count


# -- Attacks -------------------------------------------------------------------

func _do_bite(delta: float) -> void:
	_attack_timer += delta
	velocity.x = 0

	if _attack_timer < 0.2:
		# Telegraph: open jaw, extend neck
		_jaw_open = _attack_timer / 0.2
		_neck[1] += Vector2(_facing * 120.0 * delta, -40.0 * delta)
	elif _attack_timer < 0.35:
		# Snap: close jaw
		_jaw_open = 1.0 - (_attack_timer - 0.2) / 0.15
		_check_bite_hit()
	elif _attack_timer < 0.6:
		# Recovery
		_jaw_open = 0.0
	else:
		_jaw_open = 0.0
		_change_state(State.CHASE)


func _do_swipe(delta: float) -> void:
	_attack_timer += delta
	velocity.x = 0

	if _attack_timer < 0.3:
		# Raise front leg
		var swipe_leg: int = 0 if not _leg_severed[0] else 1
		if not _leg_severed[swipe_leg]:
			_legs[swipe_leg][2] += Vector2(_facing * 100.0 * delta, -200.0 * delta)
	elif _attack_timer < 0.5:
		# Arc downward
		var swipe_leg: int = 0 if not _leg_severed[0] else 1
		if not _leg_severed[swipe_leg]:
			_legs[swipe_leg][2] += Vector2(_facing * 200.0 * delta, 300.0 * delta)
			_check_swipe_hit(swipe_leg)
	elif _attack_timer < 0.8:
		# Recovery
		pass
	else:
		_change_state(State.TRANSITION_QUADRUPED)
		_attack_timer = 0.0


func _do_tail_whip(delta: float) -> void:
	_attack_timer += delta
	velocity.x = 0

	if _tail_severed:
		_change_state(State.CHASE)
		return

	_tail_whipping = true  # Loosen tail stiffness during whip

	if _attack_timer < 0.3:
		# Wind up: curl tail to one side
		var curl_dir: float = -_facing
		for i in range(_tail.size()):
			_tail[i] += Vector2(curl_dir * 80.0 * delta, 0)
	elif _attack_timer < 0.5:
		# Whip through
		var whip_dir: float = _facing
		for i in range(_tail.size()):
			var force: float = 400.0 * (float(i + 1) / _tail.size())
			_tail[i] += Vector2(whip_dir * force * delta, -100.0 * delta * (1.0 - float(i) / _tail.size()))
		_check_tail_hit()
	elif _attack_timer < 0.8:
		# Recovery — tail springs back to rest pose via _solve_pose
		pass
	else:
		_change_state(State.CHASE)


func _do_lunge(delta: float) -> void:
	_attack_timer += delta

	if _attack_timer < 0.15:
		# Windup: compress legs
		velocity.x = -_facing * 30.0
	elif _attack_timer < 0.4:
		# Launch
		velocity.x = _facing * sc(LUNGE_SPEED)
		_check_lunge_hit()
	elif _attack_timer < 0.7:
		# Slide to stop
		velocity.x = lerpf(velocity.x, 0, 0.1)
	else:
		velocity.x = 0
		_change_state(State.CHASE)


# -- Sprint Slash (same-plane charge + triple swipe) ---------------------------

# -- Death Ball Grab (close proximity) -----------------------------------------

func _start_grab() -> void:
	if is_instance_valid(_target):
		DebugOverlay.log("leap_attack/attack_zone", self, "GRAB START: monster at (%.0f,%.0f), target at (%.0f,%.0f)", [
			global_position.x, global_position.y,
			_target.global_position.x, _target.global_position.y])
	_change_state(State.ATTACK_GRAB)
	_attack_timer = 0.0
	_attack_cooldown = ATTACK_COOLDOWN
	_grab_kick_count = 0
	_grab_target_node = _target
	_state_lock_timer = GRAB_DURATION + 1.0
	velocity = Vector2.ZERO
	# Enlarge body collision to trap the player
	if _body_collision and _body_collision.shape is CircleShape2D:
		(_body_collision.shape as CircleShape2D).radius = 45.0


func _do_grab(delta: float) -> void:
	## Death ball: curl around player, kick rapidly, bite, then eject.
	_attack_timer += delta
	velocity.x = 0

	if not is_instance_valid(_grab_target_node):
		_change_state(State.CHASE)
		return

	var target_local: Vector2 = _grab_target_node.global_position - global_position
	var t: float = clampf(_attack_timer / GRAB_DURATION, 0.0, 1.0)

	# Phase 1 (0-0.2): curl into ball around the target
	# Phase 2 (0.2-0.8): kick rapidly + bite
	# Phase 3 (0.8-1.0): eject

	var center: Vector2 = target_local
	var ball_r: float = 40.0  # Orbit radius — big enough to see the player inside
	var spin: float = _attack_timer * 4.0  # Spin speed (rad/s)
	var curl: float = clampf(_attack_timer * 6.0, 0.0, 1.0)  # Fast curl-in (0.17s)

	# Center collision on the grabbed player — expand to cover the full ball + tail
	if _body_collision:
		_body_collision.position = target_local
		var max_tail_r: float = ball_r + 5.0 * (sc(TAIL_SEG_LEN) * 0.6)
		if _body_collision.shape is CircleShape2D:
			(_body_collision.shape as CircleShape2D).radius = max_tail_r

	# Helper: place a point on the ball. During curl-in, blend from current to target.
	# Once curled (curl=1), SET directly — no lerp, fully rigid.

	# SPINE: arc across the top of the ball
	var sp0: Vector2 = center + Vector2(cos(spin + 0.9), sin(spin + 0.9)) * ball_r
	var sp1: Vector2 = center + Vector2(cos(spin), sin(spin)) * (ball_r - 5)
	var sp2: Vector2 = center + Vector2(cos(spin - 0.9), sin(spin - 0.9)) * ball_r
	if curl >= 1.0:
		_spine[0] = sp0
		_spine[1] = sp1
		_spine[2] = sp2
	else:
		_spine[0] = _spine[0].lerp(sp0, curl * 20.0 * delta)
		_spine[1] = _spine[1].lerp(sp1, curl * 20.0 * delta)
		_spine[2] = _spine[2].lerp(sp2, curl * 20.0 * delta)

	# HEAD: skull bites into center, jaw chomps
	_neck[0] = _spine[0]
	var skull_pos: Vector2 = center + Vector2(cos(spin + 1.6), sin(spin + 1.6)) * (ball_r * 0.5)
	var neck_pos: Vector2 = (_spine[0] + skull_pos) * 0.5
	var chomp: float = absf(sin(_attack_timer * 14.0))
	_jaw_open = chomp * 0.7
	var jaw_pos: Vector2 = skull_pos + Vector2(cos(spin + 1.6), sin(spin + 1.6)) * (6 + chomp * 8)
	if curl >= 1.0:
		_neck[1] = neck_pos
		_skull = skull_pos
		_jaw = jaw_pos
	else:
		_neck[1] = _neck[1].lerp(neck_pos, curl * 20.0 * delta)
		_skull = _skull.lerp(skull_pos, curl * 20.0 * delta)
		_jaw = _jaw.lerp(jaw_pos, curl * 20.0 * delta)

	# FRONT LEGS: clasp — feet lock onto player, hips follow spine
	for li in [0, 1]:
		if _leg_severed[li]:
			continue
		_foot_planted[li] = false
		var grip_angle: float = spin + PI * 0.5 + float(li) * 0.7
		var foot_pos: Vector2 = center + Vector2(cos(grip_angle), sin(grip_angle)) * 6
		_legs[li][0] = _spine[0] + Vector2(0, 3)
		if curl >= 1.0:
			_legs[li][2] = foot_pos
		else:
			_legs[li][2] = _legs[li][2].lerp(foot_pos, curl * 20.0 * delta)
		_legs[li][1] = (_legs[li][0] + _legs[li][2]) * 0.5

	# REAR LEGS: rapid scratch-kick (oscillate violently)
	for li in [2, 3]:
		if _leg_severed[li]:
			continue
		_foot_planted[li] = false
		_legs[li][0] = _spine[2] + Vector2(0, 3)
		var kick_phase: float = sin(_attack_timer * 30.0 + float(li) * PI)
		var kick_angle: float = spin - PI * 0.5 + float(li - 2) * 0.6
		var kick_pos: Vector2 = center + Vector2(cos(kick_angle) * kick_phase * 14, sin(kick_angle) * kick_phase * 14)
		_legs[li][2] = kick_pos
		_legs[li][1] = (_legs[li][0] + _legs[li][2]) * 0.5

	# TAIL: starts from spine[2], spirals outward proportionally
	if not _tail_severed:
		_tail_whipping = true
		# First tail segment starts right next to spine[2] (same angle, slightly further)
		var spine2_angle: float = (_spine[2] - center).angle()
		for i in range(_tail.size()):
			# Continue from spine[2]'s angle, each segment steps further around
			var tail_angle: float = spine2_angle - float(i + 1) * 0.5
			# Radius grows proportionally: starts at spine[2] distance, grows by TAIL_SEG_LEN fraction
			var tail_r: float = ball_r + float(i + 1) * (sc(TAIL_SEG_LEN) * 0.6)
			var tail_pos: Vector2 = center + Vector2(cos(tail_angle) * tail_r, sin(tail_angle) * tail_r)
			if curl >= 1.0:
				_tail[i] = tail_pos
			else:
				_tail[i] = _tail[i].lerp(tail_pos, curl * 15.0 * delta)

	# Score ball quality: any point outside the ball radius = penalty
	if curl >= 1.0:
		_score_ball_quality(center, ball_r)

	# Phase 2: damage ticks
	if t > 0.2 and t < 0.8:
		var expected_kicks: int = int((_attack_timer - GRAB_DURATION * 0.2) / GRAB_KICK_INTERVAL)
		while _grab_kick_count < expected_kicks:
			_grab_kick_count += 1
			var dmg_pos: Vector2 = _grab_target_node.global_position
			# Alternate kicks and bites
			if _grab_kick_count % 3 == 0:
				_damage_players_in_range(dmg_pos, 30.0, GRAB_BITE_DAMAGE)
				_spawn_blood_spatter(center)
				_spawn_slash_effect(center)  # Slash visual in center of ball
			else:
				_damage_players_in_range(dmg_pos, 30.0, GRAB_KICK_DAMAGE)
				if _grab_kick_count % 2 == 0:
					_spawn_slash_effect(center)  # Periodic slashes

	# Phase 3: eject
	if t >= 1.0:
		# Fling the player in a random direction (before _exit_state nulls _grab_target_node)
		if is_instance_valid(_grab_target_node):
			var eject_angle: float = randf() * TAU
			_grab_target_node.velocity = Vector2(cos(eject_angle), sin(eject_angle)) * GRAB_EJECT_SPEED
			_grab_target_node.velocity.y = minf(_grab_target_node.velocity.y, -150.0)  # Some upward

		# Teleport to where the grab happened (near the player), not pre-grab position
		if is_instance_valid(_target):
			global_position.x = _target.global_position.x
		# Find safe floor at the new position
		var safe_floor: float = _raycast_floor(Vector2(0, -30))
		if safe_floor < 200:
			global_position.y = global_position.y + safe_floor - 14.0
		velocity = Vector2.ZERO

		_change_state(State.CHASE)

		# Reset skeleton to standing pose
		var body_y: float = -(sc(4.0) + sc(LEG_UPPER_LEN) + sc(LEG_LOWER_LEN))
		_spine[0] = Vector2(sc(SPINE_SEG_LEN) * _facing, body_y)
		_spine[1] = Vector2(0, body_y)
		_spine[2] = Vector2(-sc(SPINE_SEG_LEN) * _facing, body_y)

		# Re-plant feet
		for li in range(4):
			if not _leg_severed[li]:
				var hip: Vector2 = _spine[0] if li < 2 else _spine[2]
				_legs[li][2] = Vector2(hip.x, _raycast_floor(hip))
				_foot_planted[li] = true
				_foot_world[li] = global_position + _legs[li][2]


func _start_sprint_slash() -> void:
	_change_state(State.ATTACK_SPRINT_SLASH)
	_attack_timer = 0.0
	_attack_cooldown = ATTACK_COOLDOWN
	_sprint_slash_count = 0


func _do_sprint_slash(delta: float) -> void:
	## Sprint toward the target, then unleash 3 rapid slashes.
	_attack_timer += delta

	if not is_instance_valid(_target):
		_change_state(State.CHASE)
		return

	var to_target: Vector2 = _target.global_position - global_position
	var dist: float = to_target.length()
	_facing = signf(to_target.x) if absf(to_target.x) > 5.0 else _facing

	if _sprint_slash_count == 0:
		# Phase 1: Sprint toward target
		_want_direction = _facing
		_move_speed = _effective_speed(SPRINT_SPEED)

		if dist < sc(SPRINT_SLASH_RANGE):
			# Close enough — start slashing
			_sprint_slash_count = 1
			_attack_timer = 0.0
			velocity.x *= 0.3  # Decelerate on contact
	else:
		# Phase 2: Triple slash — alternate front legs
		velocity.x = _facing * 40.0  # Slight forward push during slashes
		_want_direction = 0.0

		var slash_time: float = _attack_timer
		var expected: int = mini(int(slash_time / SPRINT_SLASH_INTERVAL) + 1, 3)

		while _sprint_slash_count <= expected and _sprint_slash_count <= 3:
			var slash_leg: int = 0 if _sprint_slash_count % 2 == 1 else 1
			if _leg_severed[slash_leg]:
				slash_leg = 1 - slash_leg

			if not _leg_severed[slash_leg]:
				# Swipe arc: extend leg forward-downward
				var swipe_dir: float = _facing * (20.0 + _sprint_slash_count * 8.0)
				var swipe_y: float = -15.0 + _sprint_slash_count * 12.0
				_legs[slash_leg][2] = _skull + Vector2(swipe_dir, swipe_y)

				# Damage (reduced by arm damage)
				var claw_world: Vector2 = global_position + _legs[slash_leg][2]
				_damage_players_in_range(claw_world, 35.0, int(SPRINT_SLASH_DAMAGE * get_slash_damage_multiplier()))

				# Visual slash lines
				_spawn_slash_effect(_legs[slash_leg][2])

			_sprint_slash_count += 1

		# Done after 3 slashes + recovery
		if _attack_timer > 3 * SPRINT_SLASH_INTERVAL + 0.2:
			_change_state(State.CHASE)

	# Timeout safety
	if _attack_timer > 3.0:
		_change_state(State.CHASE)


# -- Connected Hop-Up (short platform climb) -----------------------------------

func _start_hop_up(to_target: Vector2) -> void:
	_change_state(State.ATTACK_HOP_UP)
	_attack_timer = 0.0
	_attack_cooldown = ATTACK_COOLDOWN
	_hop_up_start_pos = global_position
	# Find the platform surface above by raycasting
	var check_pos: Vector2 = Vector2(global_position.x + to_target.x * 0.5, global_position.y + to_target.y)
	_hop_up_target_y = check_pos.y


func _do_hop_up(delta: float) -> void:
	## Connected hop: rear legs push, body rises, front legs reach up and grab
	## the platform edge. Feet stay connected to surfaces throughout.
	_attack_timer += delta
	var t: float = clampf(_attack_timer / HOP_UP_DURATION, 0.0, 1.0)
	velocity.x = 0

	var height_to_climb: float = global_position.y - _hop_up_target_y
	if height_to_climb < 10:
		height_to_climb = sc(HOP_UP_MAX_HEIGHT) * 0.5

	# Phase 1 (0-0.3): rear legs compress, body tilts up, front legs reach upward
	# Phase 2 (0.3-0.7): rear legs push, body rises, front feet plant on upper surface
	# Phase 3 (0.7-1.0): pull body up, rear feet release and swing up

	if t < 0.3:
		# Tilt up: spine front rises
		_posture_blend = t / 0.3 * 0.6
		# Front legs reach up
		for li in [0, 1]:
			if _leg_severed[li]:
				continue
			var reach: Vector2 = _spine[0] + Vector2(_facing * 15, -height_to_climb * t / 0.3)
			_legs[li][2] = _legs[li][2].lerp(reach, 6.0 * delta)
			_foot_planted[li] = false

	elif t < 0.7:
		# Push up: move body upward
		var rise_t: float = (t - 0.3) / 0.4
		velocity.y = -height_to_climb * 2.0 * (1.0 - rise_t)
		_posture_blend = 0.6 * (1.0 - rise_t * 0.5)

		# Front feet try to plant on the upper surface
		for li in [0, 1]:
			if _leg_severed[li]:
				continue
			var upper_floor: float = _raycast_floor(Vector2(_legs[li][0].x, _legs[li][0].y - height_to_climb))
			_legs[li][2] = Vector2(_legs[li][0].x, upper_floor)
			_foot_planted[li] = false

		# Rear legs stay planted on original surface, stretching
		for li in [2, 3]:
			if _leg_severed[li]:
				continue
			# Keep feet at the start position (world space)
			_legs[li][2] = _hop_up_start_pos + Vector2(_legs[li][0].x, 0) - global_position
			_foot_planted[li] = false

	else:
		# Pull up: body reaches top, rear legs release and tuck
		var finish_t: float = (t - 0.7) / 0.3
		velocity.y = -height_to_climb * 0.5 * (1.0 - finish_t)
		_posture_blend = lerpf(0.3, 0.0, finish_t)

		# Rear legs swing up to the new surface
		for li in [2, 3]:
			if _leg_severed[li]:
				continue
			var upper_floor: float = _raycast_floor(Vector2(_legs[li][0].x, _spine[2].y))
			_legs[li][2] = _legs[li][2].lerp(Vector2(_legs[li][0].x, upper_floor), 6.0 * delta)

	# Landing impact when done
	if t >= 1.0:
		_posture_blend = 0.0
		velocity.y = 0
		# Re-plant all feet
		for li in range(4):
			if not _leg_severed[li]:
				var foot_floor: float = _raycast_floor(_legs[li][0])
				_legs[li][2] = Vector2(_legs[li][0].x, foot_floor)
				_foot_planted[li] = true
				_foot_world[li] = global_position + _legs[li][2]
		# Impact damage in small radius
		_damage_players_in_range(global_position, 40.0, HOP_UP_DAMAGE)
		_change_state(State.CHASE)
		_attack_timer = 0.0


func _do_transition_bipedal(delta: float) -> void:
	_attack_timer += delta
	velocity.x = 0
	_posture_blend = clampf(_attack_timer / 0.4, 0.0, 1.0)
	if _attack_timer >= 0.4:
		_change_state(State.ATTACK_SWIPE)
		_attack_timer = 0.0


func _do_transition_quadruped(delta: float) -> void:
	_attack_timer += delta
	velocity.x = 0
	_posture_blend = 1.0 - clampf(_attack_timer / 0.4, 0.0, 1.0)
	if _attack_timer >= 0.4:
		_change_state(State.CHASE)


# -- Vertical Leap Attack ------------------------------------------------------

func _update_leap_collision(delta: float) -> void:
	## During leap: track body angle for pose alignment.
	## Collision circles follow skeleton via _update_collision_positions().
	if _state == State.ATTACK_LEAP_WINDUP:
		var to_target: Vector2 = _leap_target_pos - global_position
		var target_angle: float = to_target.angle()
		_leap_body_angle = lerpf(_leap_body_angle, target_angle, 3.0 * delta)
	elif _state == State.ATTACK_LEAP_AIRBORNE:
		if velocity.length() > 10:
			_leap_body_angle = velocity.angle()


func _update_leap_pose(delta: float) -> void:
	## Position ALL skeleton parts relative to the body during leap.
	## The body (CharacterBody2D) moves via velocity — skeleton follows it.

	# Body aim direction
	var aim_dir: Vector2
	if _state == State.ATTACK_LEAP_AIRBORNE and velocity.length() > 10:
		aim_dir = velocity.normalized()
		# Blend toward target
		if is_instance_valid(_target):
			var to_target: Vector2 = (_target.global_position - global_position).normalized()
			aim_dir = aim_dir.lerp(to_target, 0.5)
	elif is_instance_valid(_target):
		aim_dir = (_target.global_position - global_position).normalized()
	else:
		aim_dir = Vector2(_facing, 0)

	var aim_perp: Vector2 = Vector2(-aim_dir.y, aim_dir.x)
	if aim_perp.y > 0:
		aim_perp = -aim_perp  # Keep "up" pointing screen-up

	# -- Spine aligns along aim direction --
	var spine_center := Vector2.ZERO  # Local center
	if _state == State.ATTACK_LEAP_WINDUP:
		# During windup, gradually tilt from horizontal to aimed
		var t: float = clampf(_attack_timer / LEAP_WINDUP_TIME, 0.0, 1.0)
		var rest_spine0 := Vector2(sc(SPINE_SEG_LEN) * _facing, -(sc(4.0) + sc(LEG_UPPER_LEN) + sc(LEG_LOWER_LEN)))
		var aimed_spine0 := spine_center + aim_dir * sc(SPINE_SEG_LEN)
		_spine[0] = _spine[0].lerp(rest_spine0.lerp(aimed_spine0, t), 6.0 * delta)
		var rest_spine2 := Vector2(-sc(SPINE_SEG_LEN) * _facing, -(sc(4.0) + sc(LEG_UPPER_LEN) + sc(LEG_LOWER_LEN)))
		var aimed_spine2 := spine_center - aim_dir * sc(SPINE_SEG_LEN)
		_spine[2] = _spine[2].lerp(rest_spine2.lerp(aimed_spine2, t), 6.0 * delta)
		_spine[1] = (_spine[0] + _spine[2]) * 0.5
	else:
		# Airborne/strike/thrash: spine fully aimed
		_spine[0] = _spine[0].lerp(spine_center + aim_dir * sc(SPINE_SEG_LEN), 10.0 * delta)
		_spine[2] = _spine[2].lerp(spine_center - aim_dir * sc(SPINE_SEG_LEN), 10.0 * delta)
		_spine[1] = (_spine[0] + _spine[2]) * 0.5

	# -- Neck + Head: aim at target --
	_neck[0] = _spine[0]
	var neck_tip: Vector2 = _spine[0] + aim_dir * sc(NECK_LEN)
	_neck[1] = _neck[1].lerp(neck_tip, 8.0 * delta)
	var skull_pos: Vector2 = _neck[1] + aim_dir * sc(14.0)
	_skull = _skull.lerp(skull_pos, 8.0 * delta)
	var jaw_down: Vector2 = -aim_perp  # Jaw opens away from "up"
	_jaw = _jaw.lerp(_skull + jaw_down * (sc(JAW_LEN) * 0.3 + _jaw_open * sc(JAW_LEN) * 0.5), 8.0 * delta)

	# -- Tail: trails behind --
	if not _tail_severed:
		var tail_dir: Vector2 = -aim_dir
		if _state == State.ATTACK_LEAP_WINDUP:
			# Tail plants on ground during windup (handled by _do_leap_windup)
			pass
		else:
			# Airborne: tail streams straight behind
			for i in range(5):
				var tail_target: Vector2 = _spine[2] + tail_dir * sc(TAIL_SEG_LEN) * (i + 1)
				_tail[i] = _tail[i].lerp(tail_target, 6.0 * delta)

	# -- Front legs: tucked against chest --
	for li in [0, 1]:
		if _leg_severed[li]:
			continue
		_foot_planted[li] = false
		_legs[li][0] = _spine[0] + aim_perp * (3.0 if li == 0 else -3.0)
		var tuck: Vector2 = _legs[li][0] + aim_perp * -8.0  # Tucked close
		_legs[li][2] = _legs[li][2].lerp(tuck, 8.0 * delta)
		_legs[li][1] = (_legs[li][0] + _legs[li][2]) * 0.5

	# -- Rear legs: during windup compress, airborne stretch behind --
	for li in [2, 3]:
		if _leg_severed[li]:
			continue
		_legs[li][0] = _spine[2] + aim_perp * (3.0 if li == 2 else -3.0)
		if _state == State.ATTACK_LEAP_WINDUP:
			# Compress: feet close to hips
			var t: float = clampf(_attack_timer / LEAP_WINDUP_TIME, 0.0, 1.0)
			if t > 0.5:
				_foot_planted[li] = false
				var compressed: Vector2 = _legs[li][0] + aim_perp * -10.0
				_legs[li][2] = _legs[li][2].lerp(compressed, 4.0 * delta)
				_legs[li][1] = (_legs[li][0] + _legs[li][2]) * 0.5
		else:
			# Airborne: stretch fully behind
			_foot_planted[li] = false
			var stretched: Vector2 = _legs[li][0] - aim_dir * (sc(LEG_UPPER_LEN) + sc(LEG_LOWER_LEN) - sc(2))
			_legs[li][2] = _legs[li][2].lerp(stretched, 8.0 * delta)
			_legs[li][1] = _legs[li][0] - aim_dir * sc(LEG_UPPER_LEN)

	# -- Floor constraints OFF during airborne --
	# (handled by skipping _solve_pose entirely)


func _start_leap() -> void:
	DebugOverlay.log("leap_attack/attack_zone", self, "LEAP START: planning from (%.0f,%.0f) toward target (%.0f,%.0f)", [
		global_position.x, global_position.y,
		_target.global_position.x if is_instance_valid(_target) else 0,
		_target.global_position.y if is_instance_valid(_target) else 0])
	_change_state(State.ATTACK_LEAP_PLAN)
	_attack_timer = 0.0
	_attack_cooldown = ATTACK_COOLDOWN
	_leap_cooldown = LEAP_COOLDOWN
	_leap_phase = 0.0
	_leap_slash_count = 0
	_leap_thrash_count = 0
	_leap_slash_side = 1
	_leap_ik_off = false  # IK stays on during planning (still walking)
	_leap_body_angle = 0.0
	_leap_found_path = false
	_leap_plan_phase = 0
	_leap_plan_results.clear()
	_leap_phase1_near_misses.clear()
	_leap_chosen_arc_l.clear()
	_leap_chosen_arc_r.clear()
	if is_instance_valid(_target):
		_leap_target_pos = _target.global_position





func _do_leap_plan(delta: float) -> void:
	## PLAN phase: two-pass search for a clear trajectory.
	## Phase 1: broad gaussian search. Phase 2: refine around near-misses.
	_attack_timer += delta

	if not is_instance_valid(_target):
		_change_state(State.CHASE)
		return

	_leap_target_pos = _target.global_position

	# Phase 1: broad search
	if _leap_plan_phase == 0:
		_simulate_leap_paths()
		_leap_plan_phase = 1

	# Phase 2: if phase 1 failed, refine around the best candidates
	if not _leap_found_path and _leap_plan_phase == 1 and not _leap_phase1_near_misses.is_empty():
		_simulate_leap_paths_phase2()
		_leap_plan_phase = 2

	if _leap_found_path:
		# Walk toward the chosen launch position
		var to_launch: Vector2 = _leap_launch_pos - global_position
		var dist_to_launch: float = absf(to_launch.x)

		if dist_to_launch < 10.0:
			# Arrived at launch position — commit to the leap
			_change_state(State.ATTACK_LEAP_WINDUP)
			_attack_timer = 0.0
			_leap_ik_off = true
			velocity.x = 0
		else:
			# Walk toward launch position
			_facing = signf(to_launch.x) if absf(to_launch.x) > 5.0 else _facing
			_want_direction = signf(to_launch.x)
			_move_speed = _effective_speed(SPEED_MEDIUM)
	else:
		# Both phases failed — abort after brief pause
		if _attack_timer > 0.5:
			_change_state(State.CHASE)
			_leap_cooldown = 2.0


func _simulate_leap_paths() -> void:
	## REVERSE approach: start at the target, find open-air attack zones,
	## then reverse-solve arcs from the monster's position to those zones.
	##
	## 1. Sample arrival points on strike-reach circle around target
	## 2. Filter to open air only (not inside geometry)
	## 3. For each valid arrival, reverse-solve launch velocity for several flight times
	## 4. Simulate full arc with body-width checks
	_leap_plan_results.clear()
	_leap_found_path = false

	var target_pos: Vector2 = _leap_target_pos
	var monster_pos: Vector2 = global_position
	var best_sample: Dictionary = {}
	var best_score: float = INF

	# Step 1: find the platform surface the target is standing on
	# Raycast down from the target to find the floor beneath them
	var target_floor_y: float = target_pos.y  # Default: target's Y
	var space := get_world_2d().direct_space_state
	if space:
		var query := PhysicsRayQueryParameters2D.create(
			target_pos + Vector2(0, -5), target_pos + Vector2(0, 30), 1)
		query.exclude = [get_rid()]
		var hit: Dictionary = space.intersect_ray(query)
		if not hit.is_empty():
			target_floor_y = hit["position"].y

	# Step 2: find valid arrival points (open air, ABOVE the target's platform)
	var arrival_points: Array[Vector2] = []
	for ai in range(LEAP_ARRIVAL_SAMPLES):
		var angle: float = float(ai) / float(LEAP_ARRIVAL_SAMPLES) * TAU
		var arrival: Vector2 = target_pos + Vector2(cos(angle), sin(angle)) * sc(LEAP_STRIKE_REACH)

		# Must be in open air
		if _is_point_in_solid(arrival):
			continue

		# REJECT: any arrival point below the platform the target is standing on
		if arrival.y > target_floor_y - 5:
			continue

		# REJECT: arrival point with no clear airspace above (under an overhang)
		if not _has_clear_airspace(arrival):
			continue

		arrival_points.append(arrival)

	if arrival_points.is_empty():
		_leap_phase1_near_misses.clear()
		return

	# Step 2: for each valid arrival point, reverse-solve launch velocities
	for arrival in arrival_points:
		for fi in range(LEAP_FLIGHT_TIMES):
			var t_flight: float = lerpf(LEAP_FLIGHT_TIME_MIN, LEAP_FLIGHT_TIME_MAX,
				float(fi) / float(LEAP_FLIGHT_TIMES - 1) if LEAP_FLIGHT_TIMES > 1 else 0.5)

			# Reverse-solve: Vx = dx/t, Vy = (dy - 0.5*g*t^2) / t
			var dx: float = arrival.x - monster_pos.x
			var dy: float = arrival.y - monster_pos.y
			var launch_vx: float = dx / t_flight
			var launch_vy: float = (dy - 0.5 * LEAP_PLAN_GRAVITY * t_flight * t_flight) / t_flight

			var launch_vel := Vector2(launch_vx, launch_vy)
			var speed: float = launch_vel.length()
			if speed < 200 or speed > LEAP_LAUNCH_SPEED * 1.5:
				continue
			if launch_vy > -50:
				continue

			# Body-width arc simulation
			var launch_dir: Vector2 = launch_vel.normalized()
			var launch_perp: Vector2 = Vector2(-launch_dir.y, launch_dir.x)
			if launch_perp.y > 0:
				launch_perp = -launch_perp

			var arc_c: PackedVector2Array = _simulate_arc(monster_pos, launch_vel)
			# Bounding arcs: horizontal offset at each point (body stays upright)
			var arc_l: PackedVector2Array = PackedVector2Array()
			var arc_r: PackedVector2Array = PackedVector2Array()
			for pt: Vector2 in arc_c:
				arc_l.append(Vector2(pt.x - _body_clearance_radius(), pt.y))
				arc_r.append(Vector2(pt.x + _body_clearance_radius(), pt.y))

			var clear: bool = _check_arc_clear(arc_c) and _check_arc_clear(arc_l) and _check_arc_clear(arc_r)

			# Arrival point filter + airspace check handle underside prevention.
			# Arc clearance prevents hitting platforms mid-flight.

			var arc_ratio: float = clampf(absf(launch_vy) / speed, 0.0, 1.0)

			var result := {
				"pos": monster_pos,
				"arrival": arrival,
				"arc_l": arc_l,
				"arc_r": arc_r,
				"clear": clear,
				"arc_ratio": arc_ratio,
				"launch_vel": launch_vel,
				"flight_time": t_flight,
			}
			_leap_plan_results.append(result)

			if clear:
				var time_penalty: float = absf(t_flight - 0.5) * 20.0
				var score: float = arrival.distance_to(target_pos) + time_penalty
				if score < best_score:
					best_score = score
					best_sample = result

	if not best_sample.is_empty():
		_leap_found_path = true
		_leap_launch_pos = best_sample["pos"]
		_leap_chosen_arc_l = best_sample["arc_l"]
		_leap_chosen_arc_r = best_sample["arc_r"]
		set_meta("_leap_chosen_vel", best_sample["launch_vel"])
	else:
		# Collect near-miss arrival points for phase 2
		_leap_phase1_near_misses.clear()
		var seen: Dictionary = {}
		for result in _leap_plan_results:
			var arr: Vector2 = result.get("arrival", target_pos)
			var key: String = "%.0f,%.0f" % [arr.x, arr.y]
			if not seen.has(key):
				seen[key] = true
				_leap_phase1_near_misses.append({
					"arrival": arr,
					"flight_time": result.get("flight_time", 0.5),
				})
		if _leap_phase1_near_misses.size() > 6:
			_leap_phase1_near_misses.resize(6)


func _has_lateral_clearance(world_pos: Vector2) -> bool:
	## Check if there's enough space on both sides AND above the launch point.
	## Checks at multiple heights to ensure the initial arc has room.
	var space := get_world_2d().direct_space_state
	if not space:
		return true
	var min_clearance: float = _body_clearance_radius()  # Full body radius clearance on each side

	# Check at 3 heights: surface, mid-body, and above (initial arc)
	for check_y in [world_pos.y - 15.0, world_pos.y - 40.0]:
		for dir in [-1.0, 1.0]:
			var from: Vector2 = Vector2(world_pos.x, check_y)
			var to: Vector2 = Vector2(world_pos.x + dir * min_clearance, check_y)
			var query := PhysicsRayQueryParameters2D.create(from, to, 1)
			query.exclude = [get_rid()]
			if not space.intersect_ray(query).is_empty():
				return false

	return true


func _has_clear_airspace(world_pos: Vector2) -> bool:
	## Check that there's clear sky above this point — not tucked under an overhang.
	## Raycasts upward from the point. If it hits something within LEAP_BODY_RADIUS,
	## the point is in a pocket with no room to approach from above.
	var space := get_world_2d().direct_space_state
	if not space:
		return true
	var query := PhysicsRayQueryParameters2D.create(
		world_pos, world_pos + Vector2(0, -_body_clearance_radius() * 2), 1)
	query.exclude = [get_rid()]
	var result: Dictionary = space.intersect_ray(query)
	if not result.is_empty():
		# Something above within 2× body radius — no clear airspace
		return false
	return true


func _is_point_in_solid(world_pos: Vector2) -> bool:
	## Check if a world-space point is inside solid geometry.
	var space := get_world_2d().direct_space_state
	if not space:
		return false
	var dirs := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
	var hit_count: int = 0
	for dir in dirs:
		var query := PhysicsRayQueryParameters2D.create(world_pos, world_pos + dir * 10, 1)
		query.exclude = [get_rid()]
		if not space.intersect_ray(query).is_empty():
			hit_count += 1
	return hit_count >= 3


func _simulate_leap_paths_phase2() -> void:
	## Phase 2: try nearby launch positions for each near-miss arrival,
	## with wider flight time spread.
	var target_pos: Vector2 = _leap_target_pos
	var monster_pos: Vector2 = global_position
	var best_sample: Dictionary = {}
	var best_score: float = INF
	var bounds_left: float = _find_wall_x(-1)
	var bounds_right: float = _find_wall_x(1)

	for candidate in _leap_phase1_near_misses:
		var arrival: Vector2 = candidate["arrival"]
		var base_time: float = candidate["flight_time"]

		# Try 5 launch positions near the monster
		for pi in range(5):
			var offset_x: float = (float(pi) / 4.0 - 0.5) * 80.0
			var launch_pos: Vector2 = monster_pos + Vector2(offset_x, 0)

			if launch_pos.x < bounds_left + _body_clearance_radius() * 2:
				continue
			if launch_pos.x > bounds_right - _body_clearance_radius() * 2:
				continue

			# 7 flight times, wider spread around candidate
			for fi in range(7):
				var t_offset: float = (float(fi) / 6.0 - 0.5) * 0.8
				var t_flight: float = clampf(base_time + t_offset, 0.2, 1.5)

				var dx: float = arrival.x - launch_pos.x
				var dy: float = arrival.y - launch_pos.y
				var launch_vx: float = dx / t_flight
				var launch_vy: float = (dy - 0.5 * LEAP_PLAN_GRAVITY * t_flight * t_flight) / t_flight

				var launch_vel := Vector2(launch_vx, launch_vy)
				var speed: float = launch_vel.length()
				if speed < 200 or speed > LEAP_LAUNCH_SPEED * 1.5:
					continue
				if launch_vy > -50:
					continue

				var launch_dir: Vector2 = launch_vel.normalized()
				var launch_perp: Vector2 = Vector2(-launch_dir.y, launch_dir.x)
				if launch_perp.y > 0:
					launch_perp = -launch_perp

				var arc_c: PackedVector2Array = _simulate_arc(launch_pos, launch_vel)
				var arc_l: PackedVector2Array = _simulate_arc(launch_pos + launch_perp * _body_clearance_radius(), launch_vel)
				var arc_r: PackedVector2Array = _simulate_arc(launch_pos - launch_perp * _body_clearance_radius(), launch_vel)

				var clear: bool = _check_arc_clear(arc_c) and _check_arc_clear(arc_l) and _check_arc_clear(arc_r)

				var arc_ratio: float = clampf(absf(launch_vy) / speed, 0.0, 1.0)

				var result := {
					"pos": launch_pos,
					"arrival": arrival,
					"arc_l": arc_l,
					"arc_r": arc_r,
					"clear": clear,
					"arc_ratio": arc_ratio,
					"launch_vel": launch_vel,
					"flight_time": t_flight,
				}
				_leap_plan_results.append(result)

				if clear:
					var time_penalty: float = absf(t_flight - 0.5) * 20.0
					var score: float = arrival.distance_to(target_pos) + time_penalty
					if score < best_score:
						best_score = score
						best_sample = result

	if not best_sample.is_empty():
		_leap_found_path = true
		_leap_launch_pos = best_sample["pos"]
		_leap_chosen_arc_l = best_sample["arc_l"]
		_leap_chosen_arc_r = best_sample["arc_r"]
		set_meta("_leap_chosen_vel", best_sample["launch_vel"])



func _find_wall_x(direction: int) -> float:
	## Raycast horizontally to find the nearest wall. Returns world x.
	var space := get_world_2d().direct_space_state
	if not space:
		return global_position.x + direction * 1000

	var from: Vector2 = global_position + Vector2(0, -30)
	var to: Vector2 = from + Vector2(direction * 1000, 0)
	var query := PhysicsRayQueryParameters2D.create(from, to, 1)
	query.exclude = [get_rid()]
	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return to.x
	return result["position"].x


# -- Pre-cognition (two-hop leap chaining) -------------------------------------

func _precache_platforms() -> void:
	## Pre-compute platform map, then build graph edges across multiple frames.
	_precog_platforms_cached = false
	_precog_drop_and_detect()
	_precog_edges.clear()
	# Start async graph building
	_precog_graph_building = true
	_precog_process_i = 0
	_precog_process_j = 1
	DebugOverlay.log("precog/platform_list", self, "PRECOG PRECACHE: %d platforms detected, building graph...", [_precog_platforms.size()])
	for pi in range(_precog_platforms.size()):
		var p: Dictionary = _precog_platforms[pi]
		DebugOverlay.log("precog/platform_list", self, "  P%d: (%.0f,%.0f) x=[%.0f..%.0f]", [pi, p["pos"].x, p["pos"].y, p["min_x"], p["max_x"]])


var _precog_graph_building: bool = false

func _precog_build_graph_tick() -> void:
	## Build 2 edges per frame to avoid stutter.
	if not _precog_graph_building:
		return
	var n: int = _precog_platforms.size()
	var pairs_this_frame: int = 0
	while pairs_this_frame < 5:
		if _precog_process_i >= n:
			_precog_graph_building = false
			DebugOverlay.log("precog/graph_edges", self, "PRECOG GRAPH READY: %d edges", [_precog_edges.size()])
			return
		if _precog_process_i != _precog_process_j:
			_precog_build_one_edge(_precog_process_i, _precog_process_j)
			pairs_this_frame += 1
		_precog_process_j += 1
		if _precog_process_j >= n:
			_precog_process_i += 1
			_precog_process_j = 0


var _precog_cooldown: float = 0.0  # Prevent precog spam

func _start_precognition() -> void:
	if _precog_cooldown > 0.0:
		_change_state(State.CHASE)
		return
	_plan_attempts += 1
	if _plan_attempts < MAX_PLAN_ATTEMPTS and _precog_has_waypoint:
		# Still committed to current plan — don't re-plan yet
		_change_state(State.CHASE)
		return
	_plan_attempts = 0
	_precog_cooldown = 2.0
	_state_lock_timer = 3.0  # Commit to precog for at least 3 seconds
	_change_state(State.PRECOGNITION)
	_attack_timer = 0.0
	_precog_phase = 0
	_precog_ball_lands.clear()
	_precog_platforms.clear()
	_precog_edges.clear()
	_precog_path.clear()
	_precog_path_edges.clear()
	_precog_current_hop = 0
	_precog_has_waypoint = false
	_precog_process_i = 0
	_precog_process_j = 1
	_time_since_strike_range = 0.0
	velocity.x = 0


func _do_precognition(delta: float) -> void:
	## Multi-phase thinking while curled up:
	## Phase 0: drop balls, detect platforms
	## Phase 1: build connectivity graph (one edge per frame)
	## Phase 2: find shortest path from monster's platform to target's platform
	## Phase 3: execute path (walk + leap for each hop)
	_attack_timer += delta
	velocity.x = 0
	_want_direction = 0.0
	_apply_curl_pose(delta)

	match _precog_phase:
		0:
			# Build graph if not cached yet
			if not _precog_platforms_cached or _precog_platforms.size() < 3:
				_precache_platforms()
			# Wait for async graph building to complete
			if _precog_graph_building:
				return  # Still building — wait
			# Re-tag entity positions
			for plat in _precog_platforms:
				plat["label"] = ""
			_precog_add_entity_platform(global_position, "monster")
			if is_instance_valid(_target):
				_precog_add_entity_platform(_target.global_position, "target")
			_precog_find_path()
			DebugOverlay.log("precog/current_path", self, "PRECOG: path=%s (len=%d) [%d plats, %d edges]", [
				str(_precog_path), _precog_path_edges.size(),
				_precog_platforms.size(), _precog_edges.size()])
			for hi in range(_precog_path_edges.size()):
				var he: Dictionary = _precog_path_edges[hi]
				DebugOverlay.log("precog/current_path", self, "  HOP %d: from=(%.0f,%.0f) vel=(%.0f,%.0f) arrival=(%.0f,%.0f)", [
					hi, he.get("from_pos", Vector2.ZERO).x, he.get("from_pos", Vector2.ZERO).y,
					he.get("launch_vel", Vector2.ZERO).x, he.get("launch_vel", Vector2.ZERO).y,
					he.get("arrival", Vector2.ZERO).x, he.get("arrival", Vector2.ZERO).y])
			_precog_phase = 3
		3:
			_precog_start_execution()


func _precog_drop_and_detect() -> void:
	## Drop balls and detect platforms — cached after first run since
	## the level geometry doesn't change.
	if not _precog_platforms_cached:
		_precog_ball_lands.clear()
		_precog_platforms.clear()

		var bounds_left: float = _find_wall_x(-1) + 10
		var bounds_right: float = _find_wall_x(1) - 10
		var space := get_world_2d().direct_space_state
		if not space:
			return

		var bounds_top: float = 10.0
		var bounds_bottom: float = 950.0
		var y: float = bounds_top
		while y <= bounds_bottom:
			var x: float = bounds_left
			while x <= bounds_right:
				var drop_pos := Vector2(x, y)
				if not _is_point_in_solid(drop_pos):
					var query := PhysicsRayQueryParameters2D.create(drop_pos, drop_pos + Vector2(0, 2000), 1)
					query.exclude = [get_rid()]
					var result: Dictionary = space.intersect_ray(query)
					if not result.is_empty():
						_precog_ball_lands.append(result["position"])
				x += PRECOG_GRID_SPACING
			y += PRECOG_GRID_SPACING

		_precog_detect_platforms()
		_precog_refine_platform_edges()
		_precog_platforms_cached = true

	# Clear entity labels (monster/target move between precog cycles)
	for plat in _precog_platforms:
		plat["label"] = ""

	# Re-tag entity positions
	_precog_add_entity_platform(global_position, "monster")
	if is_instance_valid(_target):
		_precog_add_entity_platform(_target.global_position, "target")


func _precog_detect_platforms() -> void:
	## Detect platforms from ball landings:
	## 1. Snap all Y values to a coarse grid (15px) so a flat surface = one Y level
	## 2. Deduplicate by snapped position
	## 3. Group by Y level, then by X connectivity within each level
	## Result: one platform per contiguous horizontal surface
	if _precog_ball_lands.is_empty():
		return

	var y_snap: float = 15.0
	var x_snap: float = PRECOG_GRID_SPACING

	# Snap Y, deduplicate
	var seen: Dictionary = {}
	var snapped: Array[Vector2] = []
	for pos in _precog_ball_lands:
		var sy: float = roundf(pos.y / y_snap) * y_snap
		var key: String = "%d,%d" % [int(pos.x / x_snap), int(sy / y_snap)]
		if not seen.has(key):
			seen[key] = true
			snapped.append(Vector2(pos.x, sy))

	if snapped.is_empty():
		return

	# Group by Y level
	var by_y: Dictionary = {}
	for pt in snapped:
		var y_key: int = int(pt.y)
		if not by_y.has(y_key):
			by_y[y_key] = []
		by_y[y_key].append(pt.x)

	# For each Y level, sort X and find contiguous runs (platforms)
	for y_key in by_y:
		var x_vals: Array = by_y[y_key]
		x_vals.sort()
		var y_val: float = float(y_key)

		var run_start: float = x_vals[0]
		var run_end: float = x_vals[0]

		for i in range(1, x_vals.size()):
			if x_vals[i] - run_end <= PRECOG_GRID_SPACING * 1.5:
				run_end = x_vals[i]
			else:
				# Only emit platforms wider than a single point
				if run_end - run_start >= PRECOG_GRID_SPACING:
					_precog_platforms.append({
						"pos": Vector2((run_start + run_end) * 0.5, y_val),
						"min_x": run_start,
						"max_x": run_end,
						"weight": int((run_end - run_start) / PRECOG_GRID_SPACING) + 1,
						"label": "",
					})
				run_start = x_vals[i]
				run_end = x_vals[i]

		if run_end - run_start >= PRECOG_GRID_SPACING:
			_precog_platforms.append({
				"pos": Vector2((run_start + run_end) * 0.5, y_val),
				"min_x": run_start,
				"max_x": run_end,
				"weight": int((run_end - run_start) / PRECOG_GRID_SPACING) + 1,
				"label": "",
			})



func _precog_refine_platform_edges() -> void:
	## 2nd pass: refine platform edges using ball-drop technique.
	## For each platform, drop balls just outside the detected edges.
	## If the ball lands at the same Y level, the platform extends further.
	## Binary-search to find the precise drop-off point.
	var space := get_world_2d().direct_space_state
	if not space:
		return
	for plat in _precog_platforms:
		var y: float = plat["pos"].y
		# Floor platform: only refine edges near walls (don't waste time
		# probing the middle). Still refine to find cliff corners.


		# Refine left edge
		plat["min_x"] = _find_platform_edge(space, plat["min_x"], y, -1.0)
		# Refine right edge
		plat["max_x"] = _find_platform_edge(space, plat["max_x"], y, 1.0)
		# Update center
		plat["pos"].x = (plat["min_x"] + plat["max_x"]) * 0.5


func _find_platform_edge(space: PhysicsDirectSpaceState2D, start_x: float, plat_y: float, direction: float) -> float:
	## Binary-search for the exact platform edge by dropping balls.
	## direction: -1 = search left, +1 = search right
	var edge_x: float = start_x
	var step: float = PRECOG_GRID_SPACING

	# First: extend outward while surface exists
	for _i in range(3):
		var test_x: float = edge_x + direction * step
		# Drop a ball from above
		var query := PhysicsRayQueryParameters2D.create(
			Vector2(test_x, plat_y - 100), Vector2(test_x, plat_y + 100), 1)
		var hit: Dictionary = space.intersect_ray(query)
		if not hit.is_empty() and absf(hit["position"].y - plat_y) < 15:
			edge_x = test_x  # Surface continues
		else:
			break  # Surface ended

	# Then: binary-search between last-good and first-bad
	var good_x: float = edge_x
	var bad_x: float = edge_x + direction * step
	for _i in range(4):  # 4 iterations = ~3px precision
		var mid_x: float = (good_x + bad_x) * 0.5
		var query := PhysicsRayQueryParameters2D.create(
			Vector2(mid_x, plat_y - 100), Vector2(mid_x, plat_y + 100), 1)
		var hit: Dictionary = space.intersect_ray(query)
		if not hit.is_empty() and absf(hit["position"].y - plat_y) < 15:
			good_x = mid_x
		else:
			bad_x = mid_x

	return good_x


func _precog_add_entity_platform(world_pos: Vector2, label: String) -> void:
	## Tag the platform the entity is standing on.
	## First tries exact match (on the platform), then falls back to
	## the NEAREST known platform (never creates new disconnected platforms).
	var floor_y: float = _raycast_floor(world_pos - global_position) + global_position.y

	# Try exact match first
	for plat in _precog_platforms:
		if absf(floor_y - plat["pos"].y) < 30.0 and world_pos.x >= plat["min_x"] - 40 and world_pos.x <= plat["max_x"] + 40:
			plat["label"] = label
			return

	# No exact match — find the nearest platform (by 2D distance)
	var best_plat: Dictionary = {}
	var best_dist: float = INF
	for plat in _precog_platforms:
		var d: float = Vector2(world_pos.x, floor_y).distance_to(plat["pos"])
		if d < best_dist:
			best_dist = d
			best_plat = plat

	if not best_plat.is_empty():
		best_plat["label"] = label
		DebugOverlay.log("precog/platform_list", self, "PRECOG ENTITY: %s at (%.0f,%.0f) floor=%.0f → nearest P '%s' at (%.0f,%.0f) dist=%.0f", [
			label, world_pos.x, world_pos.y, floor_y,
			best_plat.get("label", ""), best_plat["pos"].x, best_plat["pos"].y, best_dist])
	else:
		DebugOverlay.log("precog/platform_list", self, "PRECOG ENTITY: %s at (%.0f,%.0f) — NO platforms at all!", [label, world_pos.x, world_pos.y])


func _precog_build_graph_step() -> void:
	## Build the ENTIRE connectivity graph in one frame.
	## With ~5 platforms this is ~20 pairs — fast enough.
	var n: int = _precog_platforms.size()

	for pi in range(n):
		for pj in range(n):
			if pi == pj:
				continue
			_precog_process_i = pi
			_precog_process_j = pj
			_precog_build_one_edge(pi, pj)

	_precog_phase = 2
	return


func _precog_build_one_edge(pi: int, pj: int) -> void:
	## Test one pair of platforms for leap connectivity.
	var n: int = _precog_platforms.size()
	if true:
		var plat_from: Dictionary = _precog_platforms[_precog_process_i]
		var plat_to: Dictionary = _precog_platforms[_precog_process_j]

		# Chain barrier: skip edges where the destination platform center is
		# outside chain reach. Launch points on the source platform are filtered
		# individually below (they must be within chain reach too).
		var barrier: Dictionary = get_chain_barrier()
		if not barrier.is_empty():
			var to_reachable: bool = plat_to["pos"].distance_to(barrier["center"]) < barrier["radius"]
			if not to_reachable:
				return  # Destination unreachable
		var from_y: float = plat_from["pos"].y
		var from_min_x: float = plat_from["min_x"]
		var from_max_x: float = plat_from["max_x"]

		# Collect ball landings that are on this platform
		# Filter by chain barrier if chained (reuse barrier from above)
		var launch_points: Array[Vector2] = []
		for pos in _precog_ball_lands:
			if absf(pos.y - from_y) < 15.0 and pos.x >= from_min_x - 5 and pos.x <= from_max_x + 5:
				# Chain barrier: reject points outside chain reach
				if not barrier.is_empty():
					if pos.distance_to(barrier["center"]) > barrier["radius"]:
						continue
				launch_points.append(pos)

		if launch_points.size() > 0:
			DebugOverlay.log("precog/graph_edges", self, "PRECOG GRAPH: P%d->P%d launches=%d from=(%.0f,%.0f) to=(%.0f,%.0f)", [
				_precog_process_i, _precog_process_j, launch_points.size(),
				plat_from["pos"].x, plat_from["pos"].y,
				plat_to["pos"].x, plat_to["pos"].y])

		# Deduplicate by X (keep one per grid cell)
		var seen_x: Dictionary = {}
		var unique_launches: Array[Vector2] = []
		for pos in launch_points:
			var kx: int = int(pos.x / PRECOG_GRID_SPACING)
			if not seen_x.has(kx):
				seen_x[kx] = true
				unique_launches.append(pos)

		var best_edge: Dictionary = {}
		var best_score: float = INF

		# Down-jump: source is above destination — gravity helps, loosen constraints
		var is_down_jump: bool = plat_from["pos"].y < plat_to["pos"].y - 20

		for launch_pos in unique_launches:
			# Skip lateral clearance for down-jumps and for launches
			# near platform edges (tree/wall proximity is expected there)
			if not is_down_jump:
				var near_edge: bool = (launch_pos.x > plat_to["max_x"] or launch_pos.x < plat_to["min_x"])
				if not near_edge and not _has_lateral_clearance(launch_pos):
					continue

			# Target the platform surface directly
			var result: Dictionary = _plan_leap_to_surface(launch_pos, plat_to, is_down_jump)
			if not result.is_empty():
				# Score: prefer short walk + close landing. Launch distance
				# matters because the monster has to walk there first.
				var landing_dist: float = result["arrival"].distance_to(plat_to["pos"])
				var walk_dist: float = launch_pos.distance_to(plat_to["pos"]) * 0.3
				var score: float = landing_dist + walk_dist
				if score < best_score:
					best_score = score
					best_edge = result
					best_edge["from_pos"] = launch_pos

		if not best_edge.is_empty():
			best_edge["from"] = pi
			best_edge["to"] = pj
			_precog_edges.append(best_edge)


func _precog_find_path() -> void:
	## Dijkstra from monster's platform to target's platform using the edge graph.
	for ei in range(_precog_edges.size()):
		var e: Dictionary = _precog_edges[ei]
		DebugOverlay.log("precog/graph_edges", self, "  EDGE[%d]: P%d->P%d", [ei, e["from"], e["to"]])
	var n: int = _precog_platforms.size()
	var monster_plat: int = -1
	var target_plat: int = -1

	for i in range(n):
		if _precog_platforms[i]["label"] == "monster":
			monster_plat = i
		if _precog_platforms[i]["label"] == "target":
			target_plat = i

	DebugOverlay.log("precog/current_path", self, "PRECOG PATHFIND: monster=P%d target=P%d", [monster_plat, target_plat])
	if monster_plat < 0 or target_plat < 0:
		DebugOverlay.log("precog/current_path", self, "PRECOG PATHFIND: FAILED — monster or target not on a platform")
		_precog_path.clear()
		return
	if monster_plat == target_plat:
		DebugOverlay.log("precog/current_path", self, "PRECOG PATHFIND: same platform — no leap needed")
		_precog_path.clear()
		return

	# Build adjacency: for each platform, list of {to, edge_idx, cost}
	var adj: Array = []
	adj.resize(n)
	for i in range(n):
		adj[i] = []
	for ei in range(_precog_edges.size()):
		var e: Dictionary = _precog_edges[ei]
		var cost: float = _precog_platforms[e["from"]]["pos"].distance_to(_precog_platforms[e["to"]]["pos"])
		adj[e["from"]].append({"to": e["to"], "edge_idx": ei, "cost": cost})

	# Dijkstra
	var dist: Array[float] = []
	var prev_node: Array[int] = []
	var prev_edge: Array[int] = []
	var visited: Array[bool] = []
	dist.resize(n)
	prev_node.resize(n)
	prev_edge.resize(n)
	visited.resize(n)
	for i in range(n):
		dist[i] = INF
		prev_node[i] = -1
		prev_edge[i] = -1
		visited[i] = false
	dist[monster_plat] = 0.0

	for _iter in range(n):
		# Find unvisited node with smallest distance
		var u: int = -1
		var u_dist: float = INF
		for i in range(n):
			if not visited[i] and dist[i] < u_dist:
				u = i
				u_dist = dist[i]
		if u < 0:
			break
		visited[u] = true

		if u == target_plat:
			break

		for neighbor in adj[u]:
			var v: int = neighbor["to"]
			var new_dist: float = dist[u] + neighbor["cost"]
			if new_dist < dist[v]:
				dist[v] = new_dist
				prev_node[v] = u
				prev_edge[v] = neighbor["edge_idx"]

	# Reconstruct path
	_precog_path.clear()
	_precog_path_edges.clear()
	if dist[target_plat] == INF:
		return  # No path found

	var current: int = target_plat
	var path_nodes: Array[int] = []
	var path_edges: Array[int] = []
	while current != monster_plat:
		path_nodes.push_front(current)
		path_edges.push_front(prev_edge[current])
		current = prev_node[current]
	path_nodes.push_front(monster_plat)

	_precog_path = path_nodes
	for ei in path_edges:
		_precog_path_edges.append(_precog_edges[ei])


func _precog_start_execution() -> void:
	## Start executing the path: walk to first hop's launch point, then leap.
	DebugOverlay.log("precog/current_path", self, "PRECOG EXEC: path=%s edges=%d", [str(_precog_path), _precog_path_edges.size()])
	if _precog_path.size() < 2 or _precog_path_edges.is_empty():
		DebugOverlay.log("precog/current_path", self, "PRECOG EXEC: ABORT — path too short or no edges")
		_change_state(State.CHASE)
		_time_since_strike_range = 0.0
		return
	# Reset stuck timer so execution isn't immediately cancelled
	_chained_stuck_timer = 0.0
	_chained_last_pos = global_position

	_precog_current_hop = 0
	_precog_start_next_hop()


func _precog_start_next_hop() -> void:
	## Set up the waypoint for the current hop in the path.
	if _precog_current_hop >= _precog_path_edges.size():
		# All hops complete — chase the target normally
		_precog_has_waypoint = false
		_change_state(State.CHASE)
		_time_since_strike_range = 0.0
		return

	var edge: Dictionary = _precog_path_edges[_precog_current_hop]
	_precog_waypoint = edge.get("from_pos", _precog_platforms[_precog_path[_precog_current_hop]]["pos"])
	_precog_waypoint_edge = edge
	_precog_has_waypoint = true
	_change_state(State.CHASE)
	_time_since_strike_range = 0.0

	DebugOverlay.log("pathing/waypoints", self, "PRECOG: hop %d/%d → walk to (%.0f,%.0f) then leap", [
		_precog_current_hop + 1, _precog_path_edges.size(),
		_precog_waypoint.x, _precog_waypoint.y])


func _plan_leap_to_surface(from_pos: Vector2, plat: Dictionary, down_jump: bool = false) -> Dictionary:
	## Plan a leap to land ON a platform surface.
	## down_jump=true loosens body radius constraints (gravity helps).
	var best: Dictionary = {}
	var best_score: float = INF
	var plat_y: float = plat["pos"].y
	var plat_min_x: float = plat["min_x"]
	var plat_max_x: float = plat["max_x"]
	var _dbg_solid: int = 0
	var _dbg_speed: int = 0
	var _dbg_vy: int = 0
	var _dbg_arc: int = 0
	var _dbg_ok: int = 0
	var _dbg_total: int = 0

	# For down-jumps: smaller effective body radius (can curl up and drop)
	var effective_radius: float = _body_clearance_radius() * 0.4 if down_jump else _body_clearance_radius()

	var landing_y: float = plat_y - 5.0
	# Sample landing points: evenly spaced + precise edge points
	var sample_count: int = maxi(3, int((plat_max_x - plat_min_x) / PRECOG_GRID_SPACING) + 1)
	sample_count = mini(sample_count, 5)
	# Add edge landing points (just inside each edge with body clearance)
	var edge_landings: Array[float] = [
		plat_min_x + effective_radius + 5,
		plat_max_x - effective_radius - 5,
	]

	# Build all landing X positions: regular samples + edge points
	var all_landing_xs: Array[float] = []
	for si in range(sample_count):
		var t: float = float(si) / float(sample_count - 1) if sample_count > 1 else 0.5
		var inset: float = effective_radius
		all_landing_xs.append(lerpf(plat_min_x + inset, plat_max_x - inset, t))
	for ex in edge_landings:
		if ex >= plat_min_x and ex <= plat_max_x:
			all_landing_xs.append(ex)

	for landing_x in all_landing_xs:
		_dbg_first_body_clip = ""
		var arrival := Vector2(landing_x, landing_y)

		if _is_point_in_solid(arrival):
			_dbg_solid += 1
			continue

		# Reject if launch is under the platform — solid platforms block
		# upward movement. Margin scales with height difference (higher
		# platforms need more horizontal clearance to arc over).
		if not down_jump and from_pos.y > plat_y + 20:
			var height_diff: float = from_pos.y - plat_y
			var edge_margin: float = height_diff * 0.15  # 15% of height as horizontal clearance
			edge_margin = clampf(edge_margin, 20.0, 120.0)
			if from_pos.x >= plat_min_x - edge_margin and from_pos.x <= plat_max_x + edge_margin:
				continue

		for fi in range(LEAP_FLIGHT_TIMES):
			_dbg_total += 1
			var t_flight: float = lerpf(LEAP_FLIGHT_TIME_MIN, LEAP_FLIGHT_TIME_MAX,
				float(fi) / float(LEAP_FLIGHT_TIMES - 1) if LEAP_FLIGHT_TIMES > 1 else 0.5)

			var dx: float = arrival.x - from_pos.x
			var dy: float = arrival.y - from_pos.y
			var launch_vx: float = dx / t_flight
			var launch_vy: float = (dy - 0.5 * LEAP_PLAN_GRAVITY * t_flight * t_flight) / t_flight

			var launch_vel := Vector2(launch_vx, launch_vy)
			var speed: float = launch_vel.length()
			var min_speed: float = sc(50.0) if down_jump else sc(200.0)  # Down-jumps can be gentle
			if speed < min_speed or speed > sc(LEAP_LAUNCH_SPEED) * 1.5:
				_dbg_speed += 1
				continue
			if not down_jump and launch_vy > -50:
				_dbg_vy += 1
				continue  # Up-jumps must launch upward
			# Reject if arrival velocity is still ascending — the arc hasn't
			# peaked yet and would pass through the platform from below.
			var arrival_vy: float = launch_vy + LEAP_PLAN_GRAVITY * t_flight
			if not down_jump and arrival_vy < 0:
				_dbg_vy += 1
				continue  # Still going up at arrival — through-floor

			var arc_c: PackedVector2Array = _simulate_arc(from_pos, launch_vel)
			# Build bounding arcs as horizontal offsets for visualization.
			var arc_l: PackedVector2Array = PackedVector2Array()
			var arc_r: PackedVector2Array = PackedVector2Array()
			for pt: Vector2 in arc_c:
				arc_l.append(Vector2(pt.x - effective_radius, pt.y))
				arc_r.append(Vector2(pt.x + effective_radius, pt.y))

			# Landing zone: ignore body clips near the destination platform.
			# Extends well below the surface to cover the approach arc path,
			# and expanded horizontally by body radius for side approaches.
			var landing_zone := Rect2(
				plat_min_x - effective_radius - 20,
				plat_y - 80,
				plat_max_x - plat_min_x + effective_radius * 2 + 40,
				200 + effective_radius)
			# 1. Forward raycasts on all three arcs: center + body-width edges.
			#    Catches walls and platforms the body would physically hit.
			# Arc clearance: sweep a body-sized circle along arc_c and check
			# for intersection with ANY collision object. Near the destination
			# platform, the check radius reduces dynamically to allow landing
			# from above while still catching corner clips from the side.
			if not _check_arc_body_clearance(arc_c, effective_radius, plat_min_x, plat_max_x, plat_y):
				_dbg_arc += 1
				continue

			# Verify ALL arc paths (center + body-width) stay ABOVE the
			# destination platform. Any arc dipping below = through-floor.
			# Check ASCENDING portion only: reject arcs where the body passes
			# below the platform surface while still going UP. This catches
			# through-floor arcs but allows the descending/landing portion.
			var arc_goes_below: bool = false
			# Find the peak (where arc stops ascending)
			var peak_i: int = arc_c.size() - 1  # Default: entire arc is ascending
			for pi in range(1, arc_c.size()):
				if arc_c[pi].y > arc_c[pi - 1].y:
					peak_i = pi - 1
					break
			# Check ascending portion: no arc point should be below destination
			# platform surface within its X range
			# Only flag when arc is deep inside the platform (inner half).
			# Arc points near the edges are side-approach trajectories.
			var plat_half_w: float = (plat_max_x - plat_min_x) * 0.4
			var asc_inset: float = maxf(plat_half_w, effective_radius)
			for arc in [arc_c, arc_l, arc_r]:
				for pi in range(1, mini(peak_i + 1, arc.size())):
					if arc[pi].y > plat_y:
						if arc[pi].x >= plat_min_x + asc_inset and arc[pi].x <= plat_max_x - asc_inset:
							arc_goes_below = true
							break
				if arc_goes_below:
					break
			if arc_goes_below:
				_dbg_arc += 100  # +100 = ascending fail (vs +1 = clear_ignore fail)
				continue

			_dbg_ok += 1

			# Score: prefer arcs with maximum clearance from ALL platform edges.
			# Lower score = better.
			var min_clearance: float = 999.0
			var min_edge_clearance: float = 999.0
			for pi in range(3, arc_c.size() - 3):
				# How far above destination platform surface?
				if arc_c[pi].x >= plat_min_x - 40 and arc_c[pi].x <= plat_max_x + 40:
					var above_plat: float = plat_y - arc_c[pi].y  # Positive = above
					if above_plat < min_clearance:
						min_clearance = above_plat
				# How far are the bounding arcs from any OTHER platform edge?
				for other_plat in _precog_platforms:
					if absf(other_plat["pos"].y - from_pos.y) < 20:
						continue  # Skip source platform
					var opy: float = other_plat["pos"].y
					var opx_min: float = other_plat["min_x"]
					var opx_max: float = other_plat["max_x"]
					# Check horizontal distance from bounding arcs to platform edges
					var lx: float = arc_c[pi].x - effective_radius
					var rx: float = arc_c[pi].x + effective_radius
					# Only care if arc point is near platform's Y level (within 150px)
					if absf(arc_c[pi].y - opy) < 150:
						# Distance from left body edge to platform right edge
						if lx < opx_max and lx > opx_min:
							var edge_dist: float = opx_max - lx
							if edge_dist < min_edge_clearance:
								min_edge_clearance = edge_dist
						# Distance from right body edge to platform left edge
						if rx > opx_min and rx < opx_max:
							var edge_dist: float = rx - opx_min
							if edge_dist < min_edge_clearance:
								min_edge_clearance = edge_dist
			var clearance_penalty: float = maxf(0, 120.0 - min_clearance)
			var edge_penalty: float = maxf(0, 80.0 - min_edge_clearance) * 3.0  # Heavy penalty for close to edges
			var time_penalty: float = absf(t_flight - 0.8) * 5.0
			var score: float = clearance_penalty * 2.0 + edge_penalty + time_penalty
			if score < best_score:
				best_score = score
				best = {
					"arrival": arrival,
					"launch_vel": launch_vel,
					"arc_c": arc_c,
					"arc_l": arc_l,
					"arc_r": arc_r,
					"from_pos": from_pos,
				}

	if _dbg_total > 0:
		if best.is_empty():
			DebugOverlay.log("leap_attack/rays_cast", self, "  LEAP_PLAN_FAIL: solid=%d speed=%d vy=%d arc=%d ok=%d total=%d from=(%.0f,%.0f) to_plat=(%.0f,%.0f) clip=%s", [
				_dbg_solid, _dbg_speed, _dbg_vy, _dbg_arc, _dbg_ok, _dbg_total,
				from_pos.x, from_pos.y, plat["pos"].x, plat["pos"].y, _dbg_first_body_clip])
		else:
			DebugOverlay.log("leap_attack/rays_cast", self, "  LEAP_PLAN_OK: solid=%d speed=%d vy=%d arc=%d ok=%d total=%d from=(%.0f,%.0f) arrival=(%.0f,%.0f)", [
				_dbg_solid, _dbg_speed, _dbg_vy, _dbg_arc, _dbg_ok, _dbg_total,
				best["from_pos"].x, best["from_pos"].y, best["arrival"].x, best["arrival"].y])
	return best


func get_leap_graph() -> Array:
	## Returns all planned hop edges with platform and arc data for external inspection.
	## Called by the test runner to evaluate bounded leap constraints.
	var result: Array = []
	for edge in _precog_edges:
		var fi: int = edge.get("from", -1)
		var ti: int = edge.get("to", -1)
		var from_plat: Dictionary = _precog_platforms[fi] if fi >= 0 and fi < _precog_platforms.size() else {}
		var to_plat: Dictionary = _precog_platforms[ti] if ti >= 0 and ti < _precog_platforms.size() else {}
		result.append({
			"from_plat_pos": from_plat.get("pos", Vector2.ZERO),
			"from_plat_min_x": from_plat.get("min_x", 0.0),
			"from_plat_max_x": from_plat.get("max_x", 0.0),
			"to_plat_pos": to_plat.get("pos", Vector2.ZERO),
			"to_plat_min_x": to_plat.get("min_x", 0.0),
			"to_plat_max_x": to_plat.get("max_x", 0.0),
			"from_pos": edge.get("from_pos", Vector2.ZERO),
			"arrival": edge.get("arrival", Vector2.ZERO),
			"launch_vel": edge.get("launch_vel", Vector2.ZERO),
			"arc_c": edge.get("arc_c", PackedVector2Array()),
			"arc_l": edge.get("arc_l", PackedVector2Array()),
			"arc_r": edge.get("arc_r", PackedVector2Array()),
		})
	return result


func _plan_leap_from_to(from_pos: Vector2, to_pos: Vector2) -> Dictionary:
	## Run the reverse leap planner between two arbitrary world positions.
	## Returns the best clear result, or empty dict if none found.
	var best: Dictionary = {}
	var best_score: float = INF

	# Find the floor/platform surface at the target position
	var to_floor_y: float = to_pos.y
	var space := get_world_2d().direct_space_state
	if space:
		var fq := PhysicsRayQueryParameters2D.create(
			to_pos + Vector2(0, -5), to_pos + Vector2(0, 30), 1)
		fq.exclude = [get_rid()]
		var fhit: Dictionary = space.intersect_ray(fq)
		if not fhit.is_empty():
			to_floor_y = fhit["position"].y

	# Sample arrival points: circle around target + direct landing
	var arrivals: Array[Vector2] = []
	for ai in range(LEAP_ARRIVAL_SAMPLES):
		var angle: float = float(ai) / float(LEAP_ARRIVAL_SAMPLES) * TAU
		arrivals.append(to_pos + Vector2(cos(angle), sin(angle)) * sc(LEAP_STRIKE_REACH))
	arrivals.append(to_pos)
	arrivals.append(to_pos + Vector2(-40, 0))
	arrivals.append(to_pos + Vector2(40, 0))

	for arrival in arrivals:
		if _is_point_in_solid(arrival):
			continue
		# Reject circle arrivals below the target's platform
		var is_direct_landing: bool = absf(arrival.y - to_pos.y) < 5.0
		if not is_direct_landing and arrival.y > to_floor_y - 5:
			continue
		# Reject arrivals with no clear airspace (under overhang)
		if not is_direct_landing and not _has_clear_airspace(arrival):
			continue

		for fi in range(LEAP_FLIGHT_TIMES):
			var t_flight: float = lerpf(LEAP_FLIGHT_TIME_MIN, LEAP_FLIGHT_TIME_MAX,
				float(fi) / float(LEAP_FLIGHT_TIMES - 1) if LEAP_FLIGHT_TIMES > 1 else 0.5)

			var dx: float = arrival.x - from_pos.x
			var dy: float = arrival.y - from_pos.y
			var launch_vx: float = dx / t_flight
			var launch_vy: float = (dy - 0.5 * LEAP_PLAN_GRAVITY * t_flight * t_flight) / t_flight

			var launch_vel := Vector2(launch_vx, launch_vy)
			var speed: float = launch_vel.length()
			if speed < 200 or speed > LEAP_LAUNCH_SPEED * 1.5:
				continue
			if launch_vy > -50:
				continue

			var launch_dir: Vector2 = launch_vel.normalized()
			var launch_perp: Vector2 = Vector2(-launch_dir.y, launch_dir.x)
			if launch_perp.y > 0:
				launch_perp = -launch_perp

			var arc_c: PackedVector2Array = _simulate_arc(from_pos, launch_vel)
			var arc_l: PackedVector2Array = _simulate_arc(from_pos + launch_perp * _body_clearance_radius(), launch_vel)
			var arc_r: PackedVector2Array = _simulate_arc(from_pos - launch_perp * _body_clearance_radius(), launch_vel)

			if not (_check_arc_clear(arc_c) and _check_arc_clear(arc_l) and _check_arc_clear(arc_r)):
				continue

			# Arrival point filter already rejects below-platform arrivals

			var time_penalty: float = absf(t_flight - 0.5) * 20.0
			var score: float = arrival.distance_to(to_pos) + time_penalty
			if score < best_score:
				best_score = score
				best = {
					"arrival": arrival,
					"launch_vel": launch_vel,
					"arc_l": arc_l,
					"arc_r": arc_r,
					"from_pos": from_pos,
				}

	return best


func _apply_curl_pose(delta: float) -> void:
	## Curl up on the ground: compress body, tuck all limbs, lower head.
	var s: float = minf(6.0 * delta, 1.0)
	var body_y: float = _raycast_floor(Vector2(0, -30))

	_spine[0] = _spine[0].lerp(Vector2(12 * _facing, body_y - 15), s)
	_spine[1] = _spine[1].lerp(Vector2(0, body_y - 13), s)
	_spine[2] = _spine[2].lerp(Vector2(-12 * _facing, body_y - 15), s)

	_neck[0] = _spine[0]
	_neck[1] = _neck[1].lerp(_spine[0] + Vector2(8 * _facing, -5), s)
	_skull = _skull.lerp(_neck[1] + Vector2(4 * _facing, 3), s)
	_jaw = _jaw.lerp(_skull + Vector2(2 * _facing, 5), s)

	if not _tail_severed:
		var tail_start: Vector2 = _spine[2]
		for i in range(5):
			var curl_angle: float = PI * 0.8 + float(i) * 0.3 * _facing
			var curl_target: Vector2 = tail_start + Vector2(cos(curl_angle) * (i + 1) * 8, sin(curl_angle) * (i + 1) * 4 - 5)
			_tail[i] = _tail[i].lerp(curl_target, s)

	for li in range(4):
		if _leg_severed[li]:
			continue
		var hip_spine: Vector2 = _spine[0] if li < 2 else _spine[2]
		_legs[li][0] = hip_spine + Vector2(0, 4)
		_legs[li][2] = _legs[li][2].lerp(hip_spine + Vector2(0, 10), s)
		_legs[li][1] = (_legs[li][0] + _legs[li][2]) * 0.5
		_foot_planted[li] = false



func _check_arc_swept_circle(arc: PackedVector2Array, radius: float, ignore_rect: Rect2) -> bool:
	## Check arc clearance using a swept circle along the center path.
	## This catches obstacles between the body-width edge arcs that raycasts miss.
	## Skip first 2 segments (launch) and last 2 segments (landing).
	var space := get_world_2d().direct_space_state
	if not space:
		return true
	if arc.size() < 5:
		return true

	var shape := CircleShape2D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 1  # World layer
	query.exclude = [get_rid()]

	var check_end: int = arc.size() - 2
	for i in range(2, check_end):
		query.transform = Transform2D(0, arc[i])
		var results: Array = space.intersect_shape(query, 1)
		if not results.is_empty():
			# Check if hit is in the landing zone (ignore destination platform)
			var hit_pos: Vector2 = arc[i]  # Approximate — shape query doesn't give exact hit pos
			if ignore_rect.has_point(hit_pos):
				continue
			return false
	return true


func _simulate_arc(start: Vector2, launch_vel: Vector2) -> PackedVector2Array:
	## Simulate a parabolic arc from start with launch_vel, returning world-space points.
	## Stops early if the arc descends past the starting height (landed).
	var points := PackedVector2Array()
	var pos: Vector2 = start
	var vel: Vector2 = launch_vel

	points.append(pos)
	var past_peak: bool = false
	for _i in range(LEAP_ARC_STEPS):
		vel.y += LEAP_PLAN_GRAVITY * LEAP_ARC_DT
		pos += vel * LEAP_ARC_DT
		points.append(pos)
		# Track if we've gone past the peak
		if vel.y > 0:
			past_peak = true
		# Stop if we've descended back to or below launch height
		if past_peak and pos.y >= start.y + 20:
			break

	return points


func _check_arc_clear_ignore(arc: PackedVector2Array, ignore_rect: Rect2) -> bool:
	## Check arc clearance, ignoring hits within ignore_rect (destination platform).
	## Detects both solid walls (forward raycasts) AND one-way platforms crossed
	## from below (downward probes at mid-flight arc points).
	var space := get_world_2d().direct_space_state
	if not space:
		return true
	if arc.size() < 4:
		return true

	var launch_y: float = arc[0].y  # Source platform surface Y
	var check_end: int = arc.size() - 2  # Skip last 2 segments (landing)

	for i in range(2, check_end):  # Skip first 2 segments (body-width arcs may start inside floor)
		var from: Vector2 = arc[i]
		var to: Vector2 = arc[i + 1]
		# Forward raycast: catches solid walls
		var query := PhysicsRayQueryParameters2D.create(from, to, 1)
		query.exclude = [get_rid()]
		var result: Dictionary = space.intersect_ray(query)
		if not result.is_empty():
			if ignore_rect.has_point(result["position"]):
				continue
			return false

		# One-way platform detection: when moving upward mid-flight, check
		# if we just crossed through a platform by raycasting downward.
		# Only flag if a surface is within 8px below (practically inside it).
		if to.y < from.y and to.y < launch_y - 60:
			var probe := PhysicsRayQueryParameters2D.create(to, to + Vector2(0, 8), 1)
			probe.exclude = [get_rid()]
			var probe_hit: Dictionary = space.intersect_ray(probe)
			if not probe_hit.is_empty():
				if not ignore_rect.has_point(probe_hit["position"]):
					return false
	return true


func _check_arc_body_clearance(arc: PackedVector2Array, radius: float,
		dest_min_x: float, dest_max_x: float, dest_y: float) -> bool:
	## Sweep a body-sized circle along the center arc and check for intersection
	## with ANY collision object on physics layer 1.
	##
	## Dynamic radius near the destination platform:
	## - Full radius during mid-flight (no clipping anything)
	## - When DIRECTLY ABOVE the destination (x within platform, descending),
	##   reduce radius proportionally to height above surface — allows landing
	## - When BESIDE the destination (x outside platform range), keep full radius
	##   — catches corner clips from the side
	##
	## All ratios are relative to body radius for future dynamic monster sizing.
	var space := get_world_2d().direct_space_state
	if not space:
		return true
	if arc.size() < 8:
		return true

	var shape := CircleShape2D.new()
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 1  # World layer
	query.exclude = [get_rid()]

	var launch_y: float = arc[0].y
	# Height above destination where radius starts reducing (ratio of body radius)
	var fade_start_height: float = radius * 3.0  # Start fading at 3x body radius above
	# Inset from platform edges — only reduce radius when well inside the platform
	var edge_margin: float = radius * 0.8  # 80% of body radius as edge buffer

	for i in range(4, arc.size() - 4, 2):
		var pt: Vector2 = arc[i]
		# Skip if still near launch platform height
		if pt.y > launch_y - radius - 20:
			continue

		# Compute the effective check radius at this point
		var check_radius: float = radius
		var height_above_dest: float = dest_y - pt.y  # Positive = above platform

		if height_above_dest > 0 and height_above_dest < fade_start_height:
			# Near the destination — check if we're ABOVE the interior (not beside the edge)
			var inside_platform_x: bool = (pt.x > dest_min_x + edge_margin
				and pt.x < dest_max_x - edge_margin)
			if inside_platform_x:
				# Directly above the platform interior and descending toward it.
				# Reduce radius proportionally: at fade_start_height → full radius,
				# at surface (0) → zero radius (body is landing).
				var fade_t: float = height_above_dest / fade_start_height
				check_radius = radius * fade_t
		elif height_above_dest <= 0:
			# Below the destination surface. If the arc center is within the
			# platform x range (approaching from below), reduce the radius so the
			# body circle doesn't reach UP and clip the platform from underneath.
			var inside_platform_x: bool = (pt.x > dest_min_x + edge_margin
				and pt.x < dest_max_x - edge_margin)
			if inside_platform_x:
				# Reduce radius so the top of the circle can't reach the platform surface.
				# body_top = pt.y - check_radius. We need body_top > dest_y (stay below).
				# So check_radius < pt.y - dest_y = -height_above_dest.
				var max_safe_radius: float = -height_above_dest - 5.0  # 5px margin
				check_radius = maxf(0.0, minf(check_radius, max_safe_radius))

		if check_radius < 5.0:
			continue  # Radius too small to meaningfully check

		shape.radius = check_radius
		query.transform = Transform2D(0, pt)
		var results: Array = space.intersect_shape(query, 1)
		if not results.is_empty():
			if _dbg_first_body_clip.is_empty():
				_dbg_first_body_clip = "at (%.0f,%.0f) r=%.0f h_above=%.0f" % [pt.x, pt.y, check_radius, dest_y - pt.y]
			return false
	return true


func _check_arc_circle_sweep(arc: PackedVector2Array, radius: float, ignore_rect: Rect2) -> bool:
	## Sweep a circle of the given radius along the center arc to check clearance.
	## At each mid-flight point, cast the circle HORIZONTALLY (left and right) to
	## detect walls and platform edges within body-width. This avoids false positives
	## from one-way platforms below the arc (which the body passes through during ascent).
	## Vertical clearance (floors/ceilings) is handled by _check_arc_clear_ignore.
	var space := get_world_2d().direct_space_state
	if not space:
		return true
	if arc.size() < 6:
		return true

	for i in range(3, arc.size() - 3):
		var pt: Vector2 = arc[i]
		if ignore_rect.has_point(pt):
			continue
		# Raycast left and right to check horizontal clearance
		var query_l := PhysicsRayQueryParameters2D.create(pt, pt + Vector2(-radius, 0), 1)
		query_l.exclude = [get_rid()]
		var hit_l: Dictionary = space.intersect_ray(query_l)
		if not hit_l.is_empty() and not ignore_rect.has_point(hit_l["position"]):
			DebugOverlay.log("leap_attack/lateral_clearance", self,
				"LATERAL HIT LEFT at (%.0f,%.0f) wall=(%.0f,%.0f) radius=%.0f",
				[pt.x, pt.y, hit_l["position"].x, hit_l["position"].y, radius])
			return false
		var query_r := PhysicsRayQueryParameters2D.create(pt, pt + Vector2(radius, 0), 1)
		query_r.exclude = [get_rid()]
		var hit_r: Dictionary = space.intersect_ray(query_r)
		if not hit_r.is_empty() and not ignore_rect.has_point(hit_r["position"]):
			DebugOverlay.log("leap_attack/lateral_clearance", self,
				"LATERAL HIT RIGHT at (%.0f,%.0f) wall=(%.0f,%.0f) radius=%.0f",
				[pt.x, pt.y, hit_r["position"].x, hit_r["position"].y, radius])
			return false
	return true


func _check_arc_lateral_clearance(arc: PackedVector2Array, radius: float, ignore_rect: Rect2) -> bool:
	## At each mid-flight point on the center arc, raycast left and right to verify
	## there is at least `radius` pixels of free space on both sides.
	## Skips points near launch (first 3) and landing (last 3), and points inside ignore_rect.
	var space := get_world_2d().direct_space_state
	if not space:
		return true
	if arc.size() < 6:
		return true

	var do_log: bool = DebugOverlay.should_log("leap_attack/lateral_clearance", self)

	# Check every 3rd point to avoid excessive raycasts
	for i in range(3, arc.size() - 3, 3):
		var pt: Vector2 = arc[i]
		if ignore_rect.has_point(pt):
			continue
		# Raycast left
		var query_l := PhysicsRayQueryParameters2D.create(pt, pt + Vector2(-radius, 0), 1)
		query_l.exclude = [get_rid()]
		var hit_l: Dictionary = space.intersect_ray(query_l)
		if not hit_l.is_empty() and not ignore_rect.has_point(hit_l["position"]):
			if do_log:
				DebugOverlay.log("leap_attack/lateral_clearance", self,
					"LATERAL FAIL LEFT at (%.0f,%.0f) — hit at (%.0f,%.0f) dist=%.0f radius=%.0f",
					[pt.x, pt.y, hit_l["position"].x, hit_l["position"].y,
					pt.distance_to(hit_l["position"]), radius])
			return false
		# Raycast right
		var query_r := PhysicsRayQueryParameters2D.create(pt, pt + Vector2(radius, 0), 1)
		query_r.exclude = [get_rid()]
		var hit_r: Dictionary = space.intersect_ray(query_r)
		if not hit_r.is_empty() and not ignore_rect.has_point(hit_r["position"]):
			if do_log:
				DebugOverlay.log("leap_attack/lateral_clearance", self,
					"LATERAL FAIL RIGHT at (%.0f,%.0f) — hit at (%.0f,%.0f) dist=%.0f radius=%.0f",
					[pt.x, pt.y, hit_r["position"].x, hit_r["position"].y,
					pt.distance_to(hit_r["position"]), radius])
			return false
	return true


func _check_arc_platform_edge_clearance(arc_l: PackedVector2Array, arc_r: PackedVector2Array,
		source_y: float, dest_plat: Dictionary) -> bool:
	## Check that the bounding arcs (representing body width) do not clip any known
	## platform surface. Skips the source platform (by Y) and destination platform.
	## A bounding arc point "clips" a platform if it falls within the platform's
	## surface zone: [min_x, max_x] horizontally, [plat_y - 15, plat_y + 15] vertically.
	var dest_pos: Vector2 = dest_plat.get("pos", Vector2.ZERO)
	var is_dest_plat: bool = false
	var do_log: bool = DebugOverlay.should_log("leap_attack/lateral_clearance", self)

	for plat in _precog_platforms:
		var py: float = plat["pos"].y
		# Skip source platform (same Y level as launch)
		if absf(py - source_y) < 20:
			continue
		is_dest_plat = plat["pos"].distance_to(dest_pos) < 10
		var px_min: float = plat["min_x"]
		var px_max: float = plat["max_x"]
		# Platform edge zone: the body clips if a bounding arc point is within
		# the platform's horizontal extent. The zone extends from above the
		# surface (py - 30) down to well below (py + 150) to catch arcs that
		# pass alongside the platform's vertical edge (e.g., floor-to-platform
		# arcs whose body width clips the platform edge from below).
		var surface_rect := Rect2(px_min, py - 30, px_max - px_min, 180)
		for arc in [arc_l, arc_r]:
			for i in range(3, arc.size() - 3):
				# For dest platform: only check ascending portion
				if is_dest_plat and i > 0 and arc[i].y > arc[i - 1].y:
					break
				if surface_rect.has_point(arc[i]):
					if do_log:
						DebugOverlay.log("leap_attack/lateral_clearance", self,
							"PLATFORM CLIP at (%.0f,%.0f) — hits platform at y=%.0f x=[%.0f..%.0f]%s",
							[arc[i].x, arc[i].y, py, px_min, px_max,
							" (dest)" if is_dest_plat else ""])
					return false
	return true


func _check_arc_clear(arc: PackedVector2Array) -> bool:
	## Check arc clearance for solid walls and one-way platforms.
	## Skip last 2 segments (landing approach).
	var space := get_world_2d().direct_space_state
	if not space:
		return true
	if arc.size() < 4:
		return true

	var launch_y: float = arc[0].y
	var check_end: int = arc.size() - 3

	for i in range(check_end):
		var from: Vector2 = arc[i]
		var to: Vector2 = arc[i + 1]
		# Forward raycast: solid walls
		var query := PhysicsRayQueryParameters2D.create(from, to, 1)
		query.exclude = [get_rid()]
		if not space.intersect_ray(query).is_empty():
			return false

		# Note: one-way platform detection is handled by the ascending arc
		# check in _plan_leap_to_surface, not by probes here.
		if false:  # Disabled — ascending check handles one-way platforms
			var probe := PhysicsRayQueryParameters2D.create(to, to + Vector2(0, 20), 1)
			probe.exclude = [get_rid()]
			if not space.intersect_ray(probe).is_empty():
				return false

	return true


func _do_leap_windup(delta: float) -> void:
	## Coiling phase: body tilts up, front legs retract, tail plants, rear compresses.
	_attack_timer += delta
	velocity.x = 0
	var t: float = clampf(_attack_timer / LEAP_WINDUP_TIME, 0.0, 1.0)

	# Update target tracking during windup
	if is_instance_valid(_target):
		_leap_target_pos = _target.global_position

	# Phase 1 (0-0.3): front legs lift off ground, body starts tilting
	# Phase 2 (0.3-0.6): tail lowers, last 3 segments touch ground one at a time
	# Phase 3 (0.6-1.0): rear legs compress, spine goes near-vertical, front legs tuck

	# Tilt spine: front rises, back stays
	_posture_blend = t * 0.8  # Re-use posture blend for spine tilt

	# Front legs retract toward chest (pull feet up and inward)
	if not _leg_severed[0]:
		var tuck: Vector2 = _spine[0] + Vector2(0, 10)
		_legs[0][2] = _legs[0][2].lerp(tuck, t * 3.0 * delta)
		_foot_planted[0] = false
	if not _leg_severed[1]:
		var tuck: Vector2 = _spine[0] + Vector2(0, 10)
		_legs[1][2] = _legs[1][2].lerp(tuck, t * 3.0 * delta)
		_foot_planted[1] = false

	# Tail lowers: last 3 segments plant one at a time
	if not _tail_severed:
		var tail_floor: float = _raycast_floor(_tail[4])
		if t > 0.3:
			_tail[4].y = lerpf(_tail[4].y, tail_floor, minf((t - 0.3) * 5.0 * delta, 1.0))
		if t > 0.45:
			_tail[3].y = lerpf(_tail[3].y, tail_floor, minf((t - 0.45) * 5.0 * delta, 1.0))
		if t > 0.6:
			_tail[2].y = lerpf(_tail[2].y, tail_floor, minf((t - 0.6) * 5.0 * delta, 1.0))

	# Rear legs compress (feet move closer to hips)
	if t > 0.6:
		var compress: float = (t - 0.6) / 0.4
		for li in [2, 3]:
			if _leg_severed[li]:
				continue
			var hip: Vector2 = _legs[li][0]
			var compressed_foot: Vector2 = hip + Vector2(0, (sc(LEG_UPPER_LEN) + sc(LEG_LOWER_LEN)) * (1.0 - compress * 0.4))
			_legs[li][2] = _legs[li][2].lerp(compressed_foot, 4.0 * delta)

	# LAUNCH at end of windup — check facing (skip for precog hops which
	# may face away from the target to reach an intermediate platform).
	if _attack_timer >= LEAP_WINDUP_TIME:
		if is_instance_valid(_target) and not get_meta("_precog_leap", false):
			var to_target_x: float = _target.global_position.x - global_position.x
			if (to_target_x > 20.0 and _facing < 0) or (to_target_x < -20.0 and _facing > 0):
				_facing = signf(to_target_x)
				_end_leap()
				_change_state(State.CHASE)
				return

		_change_state(State.ATTACK_LEAP_AIRBORNE)
		_attack_timer = 0.0
		_leap_ik_off = true
		# Disable floor snap so the monster actually leaves the ground
		floor_snap_length = 0.0
		var leap_mult: float = get_leap_speed_multiplier()
		# Use the pre-computed launch velocity from planning.
		if has_meta("_leap_chosen_vel"):
			var planned_vel: Vector2 = get_meta("_leap_chosen_vel")
			if get_meta("_precog_leap", false):
				# Precog hop: use EXACT planned velocity (arc was validated)
				velocity = planned_vel * leap_mult
				remove_meta("_precog_leap")
			else:
				# Direct leap: adjust toward current target position
				if is_instance_valid(_target):
					_leap_target_pos = _target.global_position
					var to_target: Vector2 = _leap_target_pos - global_position
					planned_vel.x = signf(to_target.x) * absf(planned_vel.x)
				velocity = planned_vel * leap_mult
		else:
			# Fallback if no plan data
			var to_target: Vector2 = _leap_target_pos - global_position
			velocity.x = signf(to_target.x) * LEAP_LAUNCH_SPEED * 0.7 * leap_mult
			velocity.y = -LEAP_LAUNCH_SPEED * 0.5 * leap_mult
		# Force facing to match launch direction
		if absf(velocity.x) > 10.0:
			_facing = signf(velocity.x)
		# Unplant all feet
		for li in range(4):
			_foot_planted[li] = false
		# Tail whips straight (release)
		_tail_whipping = true


func _do_leap_airborne(delta: float) -> void:
	## Parabolic flight. Body aligns toward target. Gravity applies.
	_attack_timer += delta

	# Apply gravity for parabolic arc
	velocity.y += GRAVITY * delta


# Force facing to match horizontal velocity — no backwards flight
	if absf(velocity.x) > 10.0:
		_facing = signf(velocity.x)

	# Align spine toward target (body aims like a missile)
	var fly_dir: Vector2 = velocity.normalized() if velocity.length() > 10 else Vector2(_facing, 0)
	var body_aim: Vector2 = fly_dir
	if is_instance_valid(_target):
		var to_target: Vector2 = (_target.global_position - global_position).normalized()
		body_aim = body_aim.lerp(to_target, 0.6)  # Blend flight dir with target aim

	# Position spine along the aim direction
	var spine_center: Vector2 = (_spine[0] + _spine[2]) * 0.5
	_spine[0] = _spine[0].lerp(spine_center + body_aim * sc(SPINE_SEG_LEN), 8.0 * delta)
	_spine[2] = _spine[2].lerp(spine_center - body_aim * sc(SPINE_SEG_LEN), 8.0 * delta)

	# Rear legs extend to full stretch behind (pushing off)
	for li in [2, 3]:
		if _leg_severed[li]:
			continue
		var hip: Vector2 = _legs[li][0]
		var stretch_dir: Vector2 = -body_aim  # Behind the body
		var stretched: Vector2 = hip + stretch_dir * (sc(LEG_UPPER_LEN) + sc(LEG_LOWER_LEN) - sc(2))
		_legs[li][2] = _legs[li][2].lerp(stretched, 8.0 * delta)
		# Knee midway along the stretch
		_legs[li][1] = _legs[li][1].lerp(hip + stretch_dir * sc(LEG_UPPER_LEN), 8.0 * delta)

	# Front legs stay tucked against chest
	for li in [0, 1]:
		if _leg_severed[li]:
			continue
		var hip: Vector2 = _legs[li][0]
		var tuck: Vector2 = hip + Vector2(body_aim.y * 5, -body_aim.x * 5)  # Tucked perpendicular
		_legs[li][2] = _legs[li][2].lerp(tuck, 10.0 * delta)
		_legs[li][1] = _legs[li][1].lerp((hip + tuck) * 0.5, 10.0 * delta)

	# Tail straightens behind (release energy)
	if not _tail_severed:
		var tail_dir: Vector2 = -body_aim
		for i in range(5):
			var tail_target: Vector2 = _spine[2] + tail_dir * sc(TAIL_SEG_LEN) * (i + 1)
			_tail[i] = _tail[i].lerp(tail_target, 6.0 * delta)

	# Check if we've reached the target
	if is_instance_valid(_target):
		var dist_to_target: float = global_position.distance_to(_target.global_position)
		if dist_to_target < sc(LEAP_STRIKE_REACH):
			DebugOverlay.log("leap_attack/chosen_arc", self, "LEAP ARRIVED: monster at (%.0f,%.0f), target at (%.0f,%.0f), dist=%.0f", [
					global_position.x, global_position.y,
					_target.global_position.x, _target.global_position.y, dist_to_target])
			# 25% chance: transition to grab-ball instead of normal slash
			if randf() < 0.25 and not _grab_disabled:
				_start_grab()
			else:
				_change_state(State.ATTACK_LEAP_STRIKE)
				_attack_timer = 0.0
				_leap_slash_count = 0
				_leap_slash_side = 1
			velocity = Vector2.ZERO
			return

	# Timeout / hit ground fallback
	if _attack_timer > 2.5 or (is_on_floor() and _attack_timer > 0.3):
		_end_leap()


func _do_leap_strike(delta: float) -> void:
	## Double-time slash attack: 2 groups of 3 slashes (6 total).
	_attack_timer += delta
	velocity.x = 0
	velocity.y = 0

	# Slash timing: 6 slashes at ~0.08s intervals (double-time)
	var slash_interval: float = 0.08
	var expected_slashes: int = mini(int(_attack_timer / slash_interval), 6)

	while _leap_slash_count < expected_slashes:
		_leap_slash_count += 1
		_leap_slash_side *= -1

		# Swing the appropriate front leg
		var slash_leg: int = 0 if _leap_slash_side > 0 else 1
		if _leg_severed[slash_leg]:
			slash_leg = 1 - slash_leg
		if not _leg_severed[slash_leg]:
			# Claw swipe arc
			var swipe_end: Vector2 = _skull + Vector2(_facing * 30, _leap_slash_side * 25)
			_legs[slash_leg][2] = swipe_end

			# Damage check (reduced by arm damage)
			var claw_world: Vector2 = global_position + swipe_end
			_damage_players_in_range(claw_world, 35.0, int(LEAP_SLASH_DAMAGE * get_slash_damage_multiplier()))

			# Spawn slash effect
			_spawn_slash_effect(swipe_end)

	# After all 6 slashes: transition to bite+thrash
	if _leap_slash_count >= 6 and _attack_timer > 6 * slash_interval + 0.1:
		_change_state(State.ATTACK_LEAP_THRASH)
		_attack_timer = 0.0
		_leap_thrash_count = 0
		# Open jaw for bite
		_jaw_open = 1.0


func _do_leap_thrash(delta: float) -> void:
	## Bite the player and thrash back-and-forth 3 times, then fling.
	_attack_timer += delta
	velocity.x = 0

	if not is_instance_valid(_target):
		_end_leap()
		return

	# Bite damage on first frame
	if _leap_thrash_count == 0 and _attack_timer < delta * 2:
		var bite_world: Vector2 = global_position + _skull
		_damage_players_in_range(bite_world, 35.0, LEAP_BITE_DAMAGE)
		_spawn_blood_spatter(_skull)

	# Thrash: shake the skull side-to-side, dragging the player
	var thrash_interval: float = 0.2
	var expected_thrashes: int = mini(int(_attack_timer / thrash_interval), LEAP_THRASH_COUNT)

	if expected_thrashes > _leap_thrash_count:
		_leap_thrash_count = expected_thrashes
		_leap_slash_side *= -1
		# Damage each thrash
		var bite_world: Vector2 = global_position + _skull
		_damage_players_in_range(bite_world, 35.0, LEAP_BITE_DAMAGE / 2)
		_spawn_blood_spatter(_skull)
		# Knock target sideways
		if is_instance_valid(_target):
			_target.velocity.x = _leap_slash_side * 300.0

	# Skull thrashes side-to-side
	var thrash_offset: float = sin(_attack_timer * 25.0) * 20.0
	# Apply thrash to skull drawing (offset applied in _solve_pose won't work — do it here)
	_skull.y += thrash_offset * delta * 5.0

	# Close jaw during thrash
	_jaw_open = 0.1

	# After 3 thrashes: fling player and end
	if _leap_thrash_count >= LEAP_THRASH_COUNT and _attack_timer > LEAP_THRASH_COUNT * thrash_interval + 0.15:
		# Fling the target
		if is_instance_valid(_target):
			var fling_dir: Vector2 = Vector2(_facing * _leap_slash_side, -0.6).normalized()
			_target.velocity = fling_dir * 600.0

		_end_leap()


func _end_leap() -> void:
	## Clean up leap-specific data. Flag resets (_tail_whipping, _leap_ik_off,
	## _leap_body_angle, _posture_blend, floor_snap_length) are handled by
	## _exit_state when the state actually changes.
	DebugOverlay.log("pathing/platform_leap_path", self, "LEAP END: at (%.0f,%.0f) on_floor=%s timer=%.2f", [
		global_position.x, global_position.y, str(is_on_floor()), _attack_timer])
	_jaw_open = 0.0
	_leap_plan_results.clear()
	_leap_chosen_arc_l.clear()
	_leap_chosen_arc_r.clear()
	_attack_timer = 0.0
	velocity = Vector2.ZERO  # Kill all momentum on landing
	# Collision circles reset via _update_collision_positions on next frame

	# Reset skeleton to standing pose — spine horizontal, feet on the ground
	var body_y: float = -(sc(4.0) + sc(LEG_UPPER_LEN) + sc(LEG_LOWER_LEN))
	_spine[0] = Vector2(sc(SPINE_SEG_LEN) * _facing, body_y)
	_spine[1] = Vector2(0, body_y)
	_spine[2] = Vector2(-sc(SPINE_SEG_LEN) * _facing, body_y)

	# Plant feet at floor level below each hip
	for li in range(4):
		if not _leg_severed[li]:
			var hip_spine: Vector2 = _spine[0] if li < 2 else _spine[2]
			var rest: Array = _leg_rest[li]
			_legs[li][0] = hip_spine + _get_facing_offset(rest[0])
			var foot_floor_y: float = _raycast_floor(_legs[li][0])
			_legs[li][2] = Vector2(_legs[li][0].x, foot_floor_y)
			_foot_planted[li] = true
			_foot_world[li] = global_position + _legs[li][2]

	# If we have more hops in the precog path, start the next one
	if _precog_current_hop < _precog_path_edges.size() - 1:
		_precog_current_hop += 1
		_precog_start_next_hop()
	else:
		_precog_path.clear()
		_precog_path_edges.clear()
		_time_since_strike_range = 0.0

		# After all platform hops: if target is still not reachable by walking,
		# do a RAW ballistic leap directly at the player — no planning, just launch.
		if is_instance_valid(_target):
			var to_target: Vector2 = _target.global_position - global_position
			var dist: float = to_target.length()
			if dist < sc(LEAP_RANGE) and dist > sc(GRAB_RANGE):
				# Raw launch: aim directly at the player
				var flight_time: float = 0.6
				var launch_vx: float = to_target.x / flight_time
				var launch_vy: float = (to_target.y - 0.5 * GRAVITY * flight_time * flight_time) / flight_time
				velocity = Vector2(launch_vx, launch_vy)
				_leap_target_pos = _target.global_position
				set_meta("_leap_chosen_vel", velocity)
				_leap_launch_pos = global_position
				_leap_found_path = true
				_change_state(State.ATTACK_LEAP_AIRBORNE)
				_attack_timer = 0.0
				_leap_ik_off = true
				_leap_cooldown = LEAP_COOLDOWN
				DebugOverlay.log("leap_attack/attack_zone", self, "PRECOG: RAW AERIAL STRIKE at (%.0f,%.0f) vel=(%.0f,%.0f)", [
					_target.global_position.x, _target.global_position.y, velocity.x, velocity.y])
				return

		_change_state(State.CHASE)


func _spawn_slash_effect(local_pos: Vector2) -> void:
	## 3 diagonal slash lines that fade out quickly.
	var parent: Node = get_parent()
	if not parent:
		return
	var world_pos: Vector2 = global_position + local_pos
	for i in range(3):
		var slash := ColorRect.new()
		slash.color = Color(1, 0.9, 0.8, 0.9)
		slash.size = Vector2(28 + i * 6, 3)
		slash.rotation = _facing * (0.5 + i * 0.3)
		slash.z_index = 10
		slash.position = world_pos + Vector2(randf_range(-8, 8), -10 + i * 10)
		parent.add_child(slash)
		var tween := slash.create_tween()
		tween.tween_property(slash, "modulate:a", 0.0, 0.15)
		tween.tween_callback(slash.queue_free)


func _spawn_blood_spatter(local_pos: Vector2) -> void:
	## Small blood particles spraying from bite point.
	var parent: Node = get_parent()
	if not parent:
		return
	var world_pos: Vector2 = global_position + local_pos
	for i in range(8):
		var drop := ColorRect.new()
		drop.color = Color(0.7, 0.05, 0.05, 0.8)
		drop.size = Vector2(4, 4)
		drop.z_index = 10
		drop.position = world_pos
		parent.add_child(drop)
		var angle: float = randf() * TAU
		var dist: float = 20.0 + randf() * 40.0
		var target_pos: Vector2 = world_pos + Vector2(cos(angle), sin(angle)) * dist
		var tween := drop.create_tween()
		tween.set_parallel(true)
		tween.tween_property(drop, "position", target_pos, 0.3)
		tween.tween_property(drop, "modulate:a", 0.0, 0.5)
		tween.tween_property(drop, "scale", Vector2(0.3, 0.3), 0.4)
		tween.set_parallel(false)
		tween.tween_callback(drop.queue_free)


# -- Hit detection -------------------------------------------------------------

func _check_bite_hit() -> void:
	var bite_pos: Vector2 = global_position + _skull
	_damage_players_in_range(bite_pos, 50.0, BITE_DAMAGE)


func _check_swipe_hit(leg_idx: int) -> void:
	var claw_pos: Vector2 = global_position + _legs[leg_idx][2]
	_damage_players_in_range(claw_pos, 25.0, int(SWIPE_DAMAGE * get_slash_damage_multiplier()))


func _check_tail_hit() -> void:
	# Check last 2 tail segments
	for i in range(3, _tail.size()):
		var tail_pos: Vector2 = global_position + _tail[i]
		_damage_players_in_range(tail_pos, 20.0, TAIL_DAMAGE)


func _check_lunge_hit() -> void:
	_damage_players_in_range(global_position, 35.0, LUNGE_DAMAGE)


func _damage_players_in_range(world_pos: Vector2, radius: float, damage: int) -> void:
	for node in get_tree().get_nodes_in_group("players"):
		if not node is CharacterBody2D:
			continue
		if world_pos.distance_to(node.global_position) < radius:
			# Line-of-sight check: raycast to player, skip if blocked by world geometry
			var space := get_world_2d().direct_space_state
			if space:
				var los_query := PhysicsRayQueryParameters2D.create(world_pos, node.global_position, 1)  # World layer only
				var los_result: Dictionary = space.intersect_ray(los_query)
				if los_result:
					DebugOverlay.log("leap_attack/rays_cast", self, "DMG BLOCKED by LOS: attack at (%.0f,%.0f) → player at (%.0f,%.0f), hit geometry", [
							world_pos.x, world_pos.y, node.global_position.x, node.global_position.y])
					continue  # Blocked by geometry — can't attack through floors/walls
			# Damage via node method (supports dummy) or PlayerManager (real players)
			DebugOverlay.log("leap_attack/attack_zone", self, "DMG DEALT: %d from (%.0f,%.0f) → player at (%.0f,%.0f)", [
					damage, world_pos.x, world_pos.y, node.global_position.x, node.global_position.y])
			if node.has_method("take_damage"):
				node.take_damage(damage)
			else:
				var pi_val: Variant = node.get("player_index")
				var pi: int = pi_val if pi_val is int else 0
				PlayerManager.damage_player(pi, damage)
			_time_since_strike_range = 0.0
			# Knockback
			var kb_dir: Vector2 = (node.global_position - world_pos).normalized()
			node.velocity += kb_dir * 250.0


# -- Target tracking ----------------------------------------------------------

func _pick_target() -> void:
	# Check aggro switch
	for pi in _hit_tracker:
		if pi != _target_player_index and _hit_tracker.get(pi, 0) >= AGGRO_SWITCH_HITS:
			var new_target: Node2D = _find_player_by_index(pi)
			if new_target:
				_target = new_target
				_target_player_index = pi
				_hit_tracker.clear()
				return

	# Keep current target if valid and alive
	if is_instance_valid(_target):
		# If territorial target is another monster, check it's still alive
		if _target.is_in_group("enemies") and "_dead" in _target and _target._dead:
			_target = null
		else:
			return

	# Territorial: find nearest other monster first
	if territorial:
		var rival: Node2D = _find_nearest_rival()
		if rival:
			_target = rival
			_target_player_index = -1
			return

	# Find nearest player
	_target = _find_nearest_player()
	if _target:
		var pi_val: Variant = _target.get("player_index")
		_target_player_index = pi_val if pi_val is int else 0


func _find_nearest_rival() -> Node2D:
	## Find the nearest other monster (for territorial mode).
	var best: Node2D = null
	var best_dist: float = INF
	for node in get_tree().get_nodes_in_group("enemies"):
		if node == self:
			continue
		if not node is CharacterBody2D:
			continue
		if "_dead" in node and node._dead:
			continue
		if "_standdown" in node and node._standdown:
			continue
		if "_asleep" in node and node._asleep:
			continue
		var d: float = global_position.distance_to(node.global_position)
		if d < best_dist:
			best_dist = d
			best = node
	return best


func _find_nearest_player() -> Node2D:
	var best: Node2D = null
	var best_dist: float = INF
	for node in get_tree().get_nodes_in_group("players"):
		if not node is CharacterBody2D:
			continue
		var d: float = global_position.distance_to(node.global_position)
		if d < best_dist:
			best_dist = d
			best = node
	return best


func _find_player_by_index(pi: int) -> Node2D:
	for node in get_tree().get_nodes_in_group("players"):
		if node is CharacterBody2D and node.get("player_index") == pi:
			return node
	return null


# -- Damage / Severing --------------------------------------------------------

func take_damage(amount: int, source_index: int = -1) -> void:
	if _dead:
		return
	if _breakaway_immune > 0:
		return

	# Wake from sleep on any damage
	if _asleep:
		_asleep = false
		_standdown = false
		AudioManager.play("grapple_hit", 2.0, 0.6)  # Growl on wake

	# Rift tentacle absorption
	if has_meta("rift_tentacle"):
		var tentacle: Node2D = get_meta("rift_tentacle")
		if is_instance_valid(tentacle) and tentacle.has_method("take_tentacle_damage"):
			amount = tentacle.take_tentacle_damage(amount)
			if amount <= 0:
				return
		else:
			remove_meta("rift_tentacle")
			remove_meta("rift_attached")

	health -= amount
	if source_index >= 0:
		_hit_tracker[source_index] = _hit_tracker.get(source_index, 0) + 1

	if health <= 0:
		_die()


func take_part_damage(part_name: String, amount: int, source_index: int = -1) -> void:
	if _dead:
		return

	# Eye hit = critical hit on head
	if part_name == "eye":
		_on_eye_critical_hit()
		# Apply 2x damage to head
		take_part_damage("head", amount * 2, source_index)
		return

	if not _part_health.has(part_name):
		take_damage(amount, source_index)
		return

	var part: Dictionary = _part_health[part_name]
	part["current_hp"] -= amount
	if part["current_hp"] < 0:
		part["current_hp"] = 0

	# Update damage state
	var old_state: DamageState = part["damage_state"] as DamageState
	var ratio: float = float(part["current_hp"]) / float(part["max_hp"])
	if ratio > 0.66:
		part["damage_state"] = DamageState.NONE
	elif ratio > 0.33:
		part["damage_state"] = DamageState.MEDIUM
	else:
		part["damage_state"] = DamageState.HIGH

	# Spawn blood at the hit location
	var blood_pos: Vector2 = _get_part_world_position(part_name)
	var blood_count: int = 0
	match part["damage_state"]:
		DamageState.MEDIUM: blood_count = 3
		DamageState.HIGH: blood_count = 6
	if blood_count > 0:
		_spawn_blood(blood_pos, blood_count, "splash")

	# Apply gameplay penalties when transitioning to HIGH
	if part["damage_state"] == DamageState.HIGH and old_state != DamageState.HIGH:
		_on_part_high_damage(part_name)

	# Sever at 0 HP
	if part["current_hp"] <= 0 and part_name != "body":
		_sever_part(part_name)

	# Also damage main health pool
	take_damage(amount / 2, source_index)


func _on_part_high_damage(part_name: String) -> void:
	## Apply gameplay penalties when a part reaches HIGH damage state.
	if part_name == "tail":
		_grab_disabled = true
		print("MONSTER: tail HIGH damage — grab/roll attack DISABLED")
	elif part_name == "body":
		_torso_bleeding = true
		_torso_bleed_timer = 0.0
		print("MONSTER: torso HIGH damage — continuous bleeding")
	elif part_name == "leg2" or part_name == "leg3":
		print("MONSTER: rear leg %s HIGH damage — leap distance reduced" % part_name)
	elif part_name == "leg0" or part_name == "leg1":
		print("MONSTER: arm %s HIGH damage — slash damage reduced" % part_name)


func _get_part_world_position(part_name: String) -> Vector2:
	## Get the world position of a body part for blood effects.
	match part_name:
		"head": return global_position + _skull
		"body": return global_position + _spine[1]
		"tail": return global_position + _tail[2]
		"leg0": return global_position + _legs[0][1]
		"leg1": return global_position + _legs[1][1]
		"leg2": return global_position + _legs[2][1]
		"leg3": return global_position + _legs[3][1]
	return global_position


func _on_eye_critical_hit() -> void:
	## Eye hit — PING sound + 5-directional blood squirt.
	AudioManager.play("grapple_hit", 2.0, 2.0)  # High-pitched PING
	var eye_world: Vector2 = global_position + _hitboxes["eye"].position if _hitboxes.has("eye") else global_position + _skull
	_spawn_blood(eye_world, 5, "squirt")


func get_slash_damage_multiplier() -> float:
	## Returns damage multiplier based on arm (front leg) damage state.
	var high_arms: int = 0
	if _part_health.has("leg0") and _part_health["leg0"]["damage_state"] == DamageState.HIGH:
		high_arms += 1
	if _part_health.has("leg1") and _part_health["leg1"]["damage_state"] == DamageState.HIGH:
		high_arms += 1
	match high_arms:
		1: return 0.5   # 50% damage
		2: return 0.25  # 25% damage (75% reduction)
	return 1.0


func get_leap_speed_multiplier() -> float:
	## Returns leap launch speed multiplier based on rear leg damage state.
	var high_legs: int = 0
	if _part_health.has("leg2") and _part_health["leg2"]["damage_state"] == DamageState.HIGH:
		high_legs += 1
	if _part_health.has("leg3") and _part_health["leg3"]["damage_state"] == DamageState.HIGH:
		high_legs += 1
	match high_legs:
		1: return 0.75  # 25% reduction
		2: return 0.50  # 50% reduction
	return 1.0


func _sever_part(part_name: String) -> void:
	if part_name.begins_with("leg"):
		var idx: int = int(part_name.replace("leg", ""))
		_leg_severed[idx] = true
		if _hitboxes.has(part_name):
			_hitboxes[part_name].queue_free()
			_hitboxes.erase(part_name)
	elif part_name == "tail":
		_tail_severed = true
		_grab_disabled = true  # Tail gone = no grab
		if _hitboxes.has("tail"):
			_hitboxes["tail"].queue_free()
			_hitboxes.erase("tail")
	elif part_name == "head":
		_head_severed = true
		if _hitboxes.has("eye"):
			_hitboxes["eye"].queue_free()
			_hitboxes.erase("eye")
		_die()  # Losing the head is fatal

	# Adjust speed for missing legs
	var leg_count: int = _count_active_legs()
	match leg_count:
		3: _move_speed *= 0.75
		2: _move_speed *= 0.4
		1: _move_speed *= 0.15
		0: _move_speed *= 0.05


func _die() -> void:
	_dead = true
	_change_state(State.DEAD)
	velocity = Vector2.ZERO
	died.emit(global_position)

	# Death: collapse and fade
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 1.0)
	tween.tween_callback(queue_free)


func apply_knockback(force: Vector2) -> void:
	velocity += force / (mass * 0.01)  # Heavy = small knockback


# -- Hitbox position updates ---------------------------------------------------

func _update_hitbox_positions() -> void:
	if _hitboxes.has("body"):
		_hitboxes["body"].position = _spine[1]
	if _hitboxes.has("head"):
		_hitboxes["head"].position = _skull
	if _hitboxes.has("eye") and not _head_severed:
		# Eye position matches _draw_neck_head eye rendering
		var head_dir: Vector2 = (_skull - _neck[1]).normalized()
		if head_dir.length_squared() < 0.01:
			head_dir = Vector2(_facing, 0)
		var head_fwd: Vector2 = head_dir
		var head_up: Vector2 = Vector2(-head_dir.y, head_dir.x)
		if head_up.y > 0:
			head_up = -head_up
		_hitboxes["eye"].position = _skull + 16.0 * head_fwd + 5.0 * head_up
	if _hitboxes.has("tail") and not _tail_severed:
		_hitboxes["tail"].position = _tail[2]  # Mid-tail
	for li in range(4):
		var key: String = "leg%d" % li
		if _hitboxes.has(key) and not _leg_severed[li]:
			_hitboxes[key].position = _legs[li][1]  # Knee area

	# Attachment points
	if _attach_points.has("head"):
		_attach_points["head"].position = _skull
	if _attach_points.has("tail_tip") and not _tail_severed:
		_attach_points["tail_tip"].position = _tail[4]  # Last tail segment
	if _attach_points.has("shoulders"):
		_attach_points["shoulders"].position = _spine[0]
	if _attach_points.has("waist"):
		_attach_points["waist"].position = _spine[2]
	# Elbows/knees: positioned at the knee joint (legs[li][1])
	if _attach_points.has("elbow_l") and not _leg_severed[0]:
		_attach_points["elbow_l"].position = _legs[0][1]
	if _attach_points.has("elbow_r") and not _leg_severed[1]:
		_attach_points["elbow_r"].position = _legs[1][1]
	if _attach_points.has("knee_l") and not _leg_severed[2]:
		_attach_points["knee_l"].position = _legs[2][1]
	if _attach_points.has("knee_r") and not _leg_severed[3]:
		_attach_points["knee_r"].position = _legs[3][1]

	# Update attached items to follow their attachment points
	for point_name in _attachments:
		var world_pos: Vector2 = get_attach_world_position(point_name)
		var items: Array = _attachments[point_name]
		var i: int = items.size() - 1
		while i >= 0:
			if is_instance_valid(items[i]):
				items[i].global_position = world_pos
			else:
				items.remove_at(i)  # Clean up freed items
			i -= 1


# -- Blood Particles -----------------------------------------------------------

func _spawn_blood(world_pos: Vector2, count: int, spread_mode: String) -> void:
	## Spawn blood particles at a world position.
	## spread_mode: "splash" = random directions, "squirt" = 5 fixed directions (72 deg apart)
	for i in range(count):
		var dir: Vector2
		if spread_mode == "squirt":
			# 5 directions, evenly spaced
			var angle: float = (TAU / 5.0) * i
			dir = Vector2(cos(angle), sin(angle))
		else:
			var angle: float = randf() * TAU
			dir = Vector2(cos(angle), sin(angle))
		var speed: float = randf_range(60.0, 180.0)
		var life: float = randf_range(0.8, 1.5)
		_blood_particles.append({
			"pos": world_pos,
			"vel": dir * speed,
			"life": life,
			"max_life": life,
			"color": Color(0.8, 0.05, 0.05, 1.0),
		})


func _update_blood_particles(delta: float) -> void:
	## Update blood particle positions and remove expired ones.
	var i: int = _blood_particles.size() - 1
	while i >= 0:
		var p: Dictionary = _blood_particles[i]
		p["pos"] += p["vel"] * delta
		p["vel"].y += 300.0 * delta  # Gravity on blood
		p["vel"] *= 0.97  # Drag
		p["life"] -= delta
		if p["life"] <= 0:
			_blood_particles.remove_at(i)
		i -= 1

	# Continuous torso bleeding
	if _torso_bleeding:
		_torso_bleed_timer -= delta
		if _torso_bleed_timer <= 0.0:
			_torso_bleed_timer = 1.0
			var torso_world: Vector2 = global_position + _spine[1]
			_spawn_blood(torso_world, 2, "splash")


func _draw_blood_particles() -> void:
	for p in _blood_particles:
		var local_pos: Vector2 = p["pos"] - global_position
		var alpha: float = clampf(p["life"] / p["max_life"], 0.0, 1.0)
		var col: Color = p["color"]
		col.a = alpha
		var size: float = lerpf(2.5, 5.0, 1.0 - alpha)
		draw_circle(local_pos, size, col)


# -- Drawing -------------------------------------------------------------------

func _draw() -> void:
	if _dead and modulate.a < 0.05:
		return
	_draw_body()
	_draw_tail()
	_draw_legs()
	_draw_neck_head()
	_draw_blood_particles()
	# Chain barrier visualization: candy-striped red circle showing reach limit
	if _chained and DebugOverlay.should_draw("chain/tether_arc", self):
		var chain_barrier: Dictionary = get_chain_barrier()
		if not chain_barrier.is_empty():
			var center_local: Vector2 = chain_barrier["center"] - global_position
			var radius: float = chain_barrier["radius"]
			var stripe_count: int = 32
			for si in range(stripe_count):
				var a1: float = TAU * float(si) / float(stripe_count)
				var a2: float = TAU * float(si + 1) / float(stripe_count)
				var col: Color = Color(1.0, 0.2, 0.1, 0.4) if si % 2 == 0 else Color(0.5, 0.1, 0.05, 0.3)
				draw_arc(center_local, radius, a1, a2, 4, col, 3.0)

	# Selection indicator: pulsing cyan ring when TAB-selected
	if PlayerHUD.debug_selected_enemy == self and DebugOverlay.should_draw("state_info/selection_indicator", self):
		var pulse: float = 0.5 + 0.3 * sin(Time.get_ticks_msec() / 200.0)
		var sel_col := Color(0, 0.9, 1.0, pulse)
		draw_arc(_spine[1], sc(30.0), 0, TAU, 24, sel_col, 2.0)
		draw_string(ThemeDB.fallback_font, _spine[1] + Vector2(-sc(20), -sc(35)), "SELECTED", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, sel_col)
	if DebugOverlay.should_draw("state_info/sleep_standdown", self):
		if _asleep:
			var zzz_pos: Vector2 = _skull + Vector2(10, -20)
			var zzz_alpha: float = 0.5 + 0.3 * sin(Time.get_ticks_msec() / 800.0)
			draw_string(ThemeDB.fallback_font, zzz_pos, "ZZZ", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.8, 0.8, 1.0, zzz_alpha))
		if _standdown:
			var flag_pos: Vector2 = _spine[1] + Vector2(0, -40)
			draw_string(ThemeDB.fallback_font, flag_pos, "STANDDOWN", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(1, 1, 1, 0.8))
			var fp: Vector2 = flag_pos + Vector2(-20, -12)
			draw_line(fp, fp + Vector2(0, 14), Color.WHITE, 1.5)
			var flag_pts := PackedVector2Array([fp, fp + Vector2(10, 3), fp + Vector2(0, 6)])
			draw_polygon(flag_pts, PackedColorArray([Color(1, 1, 1, 0.7), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0.7)]))
	_draw_debug()


func _draw_body() -> void:
	var body_col := Color(0.3, 0.25, 0.2)
	var body_inner := Color(0.4, 0.33, 0.28)
	for i in range(_spine.size() - 1):
		var t: float = float(i) / float(_spine.size() - 1)
		var thickness: float = lerpf(sc(10.0), sc(8.0), t)
		draw_line(_spine[i], _spine[i + 1], body_col, thickness, true)
		draw_line(_spine[i], _spine[i + 1], body_inner, thickness * 0.4, true)
	# Body mass circles at each spine point
	for i in range(_spine.size()):
		var r: float = lerpf(sc(12.0), sc(10.0), float(i) / 2.0)
		draw_circle(_spine[i], r, body_col)


func _draw_tail() -> void:
	if _tail_severed:
		# Draw stump
		var stump: Vector2 = _spine[2] + Vector2(-sc(4) * _facing, sc(2))
		draw_circle(stump, sc(4.0), Color(0.5, 0.15, 0.1))
		return

	var tail_col := Color(0.35, 0.28, 0.22)
	var prev: Vector2 = _spine[2]
	for i in range(_tail.size()):
		var t: float = float(i) / float(_tail.size() - 1)
		var thickness: float = lerpf(sc(6.0), sc(2.0), t)
		draw_line(prev, _tail[i], tail_col, thickness, true)
		prev = _tail[i]
	# Tail tip
	draw_circle(_tail[_tail.size() - 1], sc(2.5), tail_col)


func _draw_legs() -> void:
	var bone_col := Color(0.35, 0.28, 0.22)

	# Draw clavicles (spine[0] to arm hips)
	for ci in range(2):
		draw_line(_spine[0], _clavicles[ci], bone_col, sc(4.0), true)
		draw_circle(_clavicles[ci], sc(3.0), bone_col)

	# Draw hip bones (spine[2] to leg hips)
	for hi in range(2):
		draw_line(_spine[2], _hip_bones[hi], bone_col, sc(4.0), true)
		draw_circle(_hip_bones[hi], sc(3.0), bone_col)

	for li in range(4):
		if _leg_severed[li]:
			# Draw stump at clavicle/hip bone endpoint
			var stump: Vector2 = _clavicles[li] if li < 2 else _hip_bones[li - 2]
			draw_circle(stump, sc(3.0), Color(0.5, 0.15, 0.1))
			continue

		var leg: Array = _legs[li]
		var leg_col := Color(0.32, 0.26, 0.2)
		var claw_col := Color(0.25, 0.2, 0.18)

		# Upper leg (rigid)
		draw_line(leg[0], leg[1], leg_col, sc(5.0), true)
		# Lower leg (±10% flex)
		draw_line(leg[1], leg[2], leg_col, sc(4.0), true)
		# Joint circles
		draw_circle(leg[0], sc(4.0), leg_col)
		draw_circle(leg[1], sc(3.5), leg_col)

		# Foot / claw
		var foot: Vector2 = leg[2]
		var knee: Vector2 = leg[1]
		var foot_dir: Vector2 = (foot - knee).normalized()
		var claw_tip: Vector2 = foot + foot_dir * sc(6.0)
		var perp: Vector2 = Vector2(-foot_dir.y, foot_dir.x)
		draw_polygon(PackedVector2Array([
			foot + perp * sc(3.0),
			foot - perp * sc(3.0),
			claw_tip
		]), PackedColorArray([claw_col, claw_col, claw_col]))


func _draw_neck_head() -> void:
	if _head_severed:
		var stump: Vector2 = _spine[0] + Vector2(sc(4) * _facing, -sc(8))
		draw_circle(stump, sc(4.0), Color(0.5, 0.15, 0.1))
		return

	var neck_col := Color(0.33, 0.27, 0.22)

	# Neck: thick line from spine[0] through neck tip to skull
	draw_line(_neck[0], _neck[1], neck_col, sc(8.0), true)
	draw_line(_neck[1], _skull, neck_col, sc(7.0), true)
	draw_circle(_neck[0], sc(5.0), neck_col)
	draw_circle(_neck[1], sc(4.5), neck_col)

	# Head facing direction: derived from neck→skull vector
	# All skull/jaw/eye points rotate to face this direction
	var head_dir: Vector2 = (_skull - _neck[1]).normalized()
	if head_dir.length_squared() < 0.01:
		head_dir = Vector2(_facing, 0)
	# Head-local coordinate system:
	#   head_fwd  = direction skull faces (neck→skull)
	#   head_up   = perpendicular, ALWAYS pointing screen-up (negative Y)
	# When facing left, we need to mirror the "up" axis so the head doesn't flip.
	var head_fwd: Vector2 = head_dir
	var head_up: Vector2 = Vector2(-head_dir.y, head_dir.x)
	# head_up should point screen-up (negative Y). If it doesn't, flip it.
	if head_up.y > 0:
		head_up = -head_up

	# Skull polygon (x=forward toward snout, y=upward toward top of skull)
	var skull_col := Color(0.35, 0.28, 0.22)
	var skull_local := [
		Vector2(-sc(12), sc(16)),   # Back-top
		Vector2(sc(28), sc(12)),    # Front-top
		Vector2(sc(32), -sc(4)),    # Front snout
		Vector2(sc(16), -sc(12)),   # Front-bottom
		Vector2(-sc(8), -sc(8)),    # Back-bottom
	]
	var skull_pts := PackedVector2Array()
	for pt in skull_local:
		skull_pts.append(_skull + pt.x * head_fwd + pt.y * head_up)
	draw_polygon(skull_pts, PackedColorArray([skull_col, skull_col, skull_col, skull_col, skull_col]))

	# Eye
	var eye_local := Vector2(sc(16), sc(5))
	var eye_pos: Vector2 = _skull + eye_local.x * head_fwd + eye_local.y * head_up
	if _asleep:
		# Closed eye: horizontal line
		draw_line(eye_pos - head_fwd * sc(3.0), eye_pos + head_fwd * sc(3.0), Color(0.4, 0.15, 0.1), sc(1.5))
	else:
		draw_circle(eye_pos, sc(4.0), Color(1.0, 0.2, 0.1))
		draw_circle(eye_pos, sc(2.0), Color(1.0, 0.5, 0.2))

	# Jaw (opens downward = negative head_up direction)
	var jaw_col := Color(0.3, 0.24, 0.19)
	var jaw_open_fwd: float = _jaw_open * sc(16.0)
	var jaw_open_down: float = _jaw_open * sc(8.0)
	var jaw_local := [
		Vector2(-sc(4), -sc(8)),                            # Back hinge
		Vector2(sc(28), -sc(4) - jaw_open_fwd),             # Front tip
		Vector2(sc(20), -sc(14) - jaw_open_fwd),            # Jaw tip far
		Vector2(-sc(4), -sc(12) - jaw_open_down),           # Back bottom
	]
	var jaw_pts := PackedVector2Array()
	for pt in jaw_local:
		jaw_pts.append(_skull + pt.x * head_fwd + pt.y * head_up)
	draw_polygon(jaw_pts, PackedColorArray([jaw_col, jaw_col, jaw_col, jaw_col]))

	# Teeth (hang from upper jaw, pointing in -head_up direction)
	var teeth_col := Color(0.9, 0.85, 0.7)
	for i in range(4):
		var t: float = float(i + 1) / 5.0
		var base_local := Vector2(lerpf(sc(4), sc(28), t), -sc(4))
		var tip_local := Vector2(base_local.x, base_local.y - sc(6) - _jaw_open * sc(5))
		var base_pt: Vector2 = _skull + base_local.x * head_fwd + base_local.y * head_up
		var tip_pt: Vector2 = _skull + tip_local.x * head_fwd + tip_local.y * head_up
		draw_line(base_pt, tip_pt, teeth_col, sc(2.0))


func _draw_debug() -> void:
	var dbg := Color(0, 1, 0, 0.7)
	var red := Color(1, 0.2, 0.2, 0.7)
	var cyan := Color(0, 0.9, 1, 0.7)
	var yellow := Color(1, 1, 0, 0.6)
	var font: Font = ThemeDB.fallback_font

	# -- Origin crosshair --
	if DebugOverlay.should_draw("body_mechanics/origin_marker", self):
		draw_line(Vector2(-20, 0), Vector2(20, 0), red, 1.5)
		draw_line(Vector2(0, -20), Vector2(0, 20), red, 1.5)
		draw_string(font, Vector2(4, -4), "ORIGIN(0,0)", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, red)

	# -- Scale info --
	if creature_scale != 1.0 and DebugOverlay.should_draw("scaling/active_scale", self):
		var scale_text := "SCALE: %.1fx" % creature_scale
		draw_string(font, _spine[1] + Vector2(-sc(20), -sc(50)), scale_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.3, 1.0, 0.5, 0.9))
	if DebugOverlay.should_draw("scaling/effective_radii", self):
		# Body clearance circle (what leap planning uses)
		draw_arc(_spine[1], _body_clearance_radius(), 0, TAU, 32, Color(0.3, 1.0, 0.5, 0.3), 1.5)

	# -- Floor line --
	var floor_y: float = 0.0
	if DebugOverlay.should_draw("body_mechanics/floor_line", self):
		floor_y = _raycast_floor(Vector2(0, _spine[1].y))
		draw_line(Vector2(-sc(120), floor_y), Vector2(sc(120), floor_y), yellow, 1.0)
		draw_string(font, Vector2(-sc(120), floor_y - 4), "FLOOR y=%.0f" % floor_y, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, yellow)

	# -- Body collision sphere (belly) --
	if DebugOverlay.should_draw("body_mechanics/collision_shapes", self):
		if _body_collision:
			var col_col := Color(1, 0, 1, 0.3)
			draw_arc(_body_collision.position, sc(14.0), 0, TAU, 16, col_col, 1.5)
			draw_string(font, _body_collision.position + Vector2(-12, -18), "BELLY", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, col_col)

	# -- Spine points --
	if DebugOverlay.should_draw("body_mechanics/spine_debug", self):
		for i in range(_spine.size()):
			draw_circle(_spine[i], 3.0, dbg)
			draw_string(font, _spine[i] + Vector2(4, -4), "S%d(%.0f,%.0f)" % [i, _spine[i].x, _spine[i].y], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, dbg)

	# -- Neck + head --
	if DebugOverlay.should_draw("body_mechanics/neck_skull", self):
		draw_circle(_neck[0], 2.5, cyan)
		draw_circle(_neck[1], 2.5, cyan)
		draw_line(_neck[0], _neck[1], cyan, 1.0)
		draw_string(font, _neck[1] + Vector2(4, -4), "NECK", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, cyan)
		draw_circle(_skull, 3.0, cyan)
		draw_string(font, _skull + Vector2(4, -10), "SKULL(%.0f,%.0f)" % [_skull.x, _skull.y], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, cyan)

	# -- Jaw --
	if DebugOverlay.should_draw("body_mechanics/jaw", self):
		draw_circle(_jaw, 2.0, cyan)

	# -- Tail points --
	if DebugOverlay.should_draw("body_mechanics/tail_segments", self):
		if not _tail_severed:
			for i in range(_tail.size()):
				draw_circle(_tail[i], 2.0, Color(1, 0.6, 0, 0.6))
				if i == 0 or i == _tail.size() - 1:
					draw_string(font, _tail[i] + Vector2(2, -4), "T%d(%.0f,%.0f)" % [i, _tail[i].x, _tail[i].y], HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(1, 0.6, 0))

	# -- Legs: joints, foot targets, home positions --
	if DebugOverlay.should_draw("body_mechanics/leg_debug", self):
		var leg_colors := [Color(0, 0.8, 1), Color(0.2, 1, 0.5), Color(1, 0.8, 0.2), Color(1, 0.4, 0.6)]
		for li in range(4):
			if _leg_severed[li]:
				continue
			var col: Color = leg_colors[li]
			var leg: Array = _legs[li]
			for j in range(3):
				draw_circle(leg[j], 2.5, col)
			draw_line(leg[0], leg[1], col * Color(1,1,1,0.5), 1.0)
			draw_line(leg[1], leg[2], col * Color(1,1,1,0.5), 1.0)
			var label: String = ["FL", "FR", "RL", "RR"][li]
			draw_string(font, leg[0] + Vector2(-8, -6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, col)
			draw_string(font, leg[2] + Vector2(4, 10), "ft(%.0f,%.0f)" % [leg[2].x, leg[2].y], HORIZONTAL_ALIGNMENT_LEFT, -1, 7, col)
			# World foot position (X marker)
			var fw_local: Vector2 = _foot_world[li] - global_position
			draw_line(fw_local + Vector2(-5, -5), fw_local + Vector2(5, 5), col, 2.0)
			draw_line(fw_local + Vector2(5, -5), fw_local + Vector2(-5, 5), col, 2.0)

	# -- IK plant marks (ideal foot positions + planted indicators) --
	if DebugOverlay.should_draw("body_mechanics/ik_plant_marks", self):
		var leg_colors2 := [Color(0, 0.8, 1), Color(0.2, 1, 0.5), Color(1, 0.8, 0.2), Color(1, 0.4, 0.6)]
		for li in range(4):
			if _leg_severed[li]:
				continue
			var col: Color = leg_colors2[li]
			var ideal: Vector2 = _ideal_foot_world(li) - global_position
			draw_arc(ideal, 6.0, 0, TAU, 12, col * Color(1,1,1,0.4), 1.0)
			var planted_text: String = "PLANT" if _foot_planted[li] else "STEP"
			draw_string(font, _legs[li][2] + Vector2(4, 20), planted_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, col)

	# -- State info text panel --
	if DebugOverlay.should_draw("state_info/state_text_panel", self):
		if floor_y == 0.0:
			floor_y = _raycast_floor(Vector2(0, _spine[1].y))
		var screen_x: float = global_position.x
		var text_x: float = -global_position.x + 200 if screen_x > 960 else -global_position.x + 1700
		var info_pos := Vector2(text_x, -global_position.y + 50)
		draw_line(info_pos + Vector2(0, 30), _spine[1], Color(0.5, 0.5, 0.5, 0.15), 1.0)
		var state_names := ["PATROL", "CHASE", "BITE", "SWIPE", "TAIL", "LUNGE", "SPRINT", "HOP-UP", "GRAB", "LEAP:PLAN", "LEAP:WIND", "LEAP:AIR", "LEAP:SLASH", "LEAP:THRASH", "PRECOG", "->BIPED", "->QUAD", "HURT", "DEAD"]
		var state_text: String = state_names[_state] if _state < state_names.size() else "?"
		var dy: int = 0
		draw_string(font, info_pos + Vector2(0, dy), "State: %s  Facing: %s  Spd: %.0f" % [state_text, "R" if _facing > 0 else "L", _move_speed], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, dbg)
		dy += 12
		draw_string(font, info_pos + Vector2(0, dy), "HP: %d  Legs: %d  Vel: (%.0f,%.0f)" % [health, _count_active_legs(), velocity.x, velocity.y], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, dbg)
		dy += 12
		var waypoint_str: String = "  WPT!" if _precog_has_waypoint else ""
		draw_string(font, info_pos + Vector2(0, dy), "Floor: %s  noHit: %.0fs%s" % [str(is_on_floor()), _time_since_strike_range, waypoint_str], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, dbg)
		dy += 12
		draw_string(font, info_pos + Vector2(0, dy), "Pos: (%.0f,%.0f)  floorY: %.1f" % [global_position.x, global_position.y, floor_y], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, dbg)
		dy += 14
		var ik_col: Color = Color(0, 1, 0) if _ik_score < 20 else (Color(1, 1, 0) if _ik_score < 100 else Color(1, 0, 0))
		draw_string(font, info_pos + Vector2(0, dy), "IK: %.0f avg:%.0f pk:%.0f" % [_ik_score, _ik_score_avg, _ik_score_peak], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, ik_col)
		dy += 12
		var thrash_col: Color = Color(0, 1, 0) if _strategy_changes < 5 else (Color(1, 1, 0) if _strategy_changes < 15 else Color(1, 0, 0))
		draw_string(font, info_pos + Vector2(0, dy), "Thrash: %d  plan: %d/%d" % [_strategy_changes, _plan_attempts, MAX_PLAN_ATTEMPTS], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, thrash_col)
		if _state == State.ATTACK_GRAB:
			dy += 12
			var ball_col: Color = Color(0, 1, 0) if _ball_score < 10 else (Color(1, 1, 0) if _ball_score < 50 else Color(1, 0, 0))
			draw_string(font, info_pos + Vector2(0, dy), "Ball: %.0f pk:%.0f" % [_ball_score, _ball_score_peak], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, ball_col)

	# -- Waypoint marker --
	if _precog_has_waypoint and DebugOverlay.should_draw("pathing/waypoints", self):
		var wpt_local: Vector2 = _precog_waypoint - global_position
		draw_circle(wpt_local, 10.0, Color(1, 0.5, 0, 0.6))
		draw_arc(wpt_local, 14.0, 0, TAU, 16, Color(1, 0.5, 0, 0.8), 2.0)
		draw_string(font, wpt_local + Vector2(16, -4), "WAYPOINT", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 0.5, 0))
		draw_line(Vector2.ZERO, wpt_local, Color(1, 0.5, 0, 0.4), 1.5)

	# -- Target indicator --
	if is_instance_valid(_target) and DebugOverlay.should_draw("state_info/target_indicator", self):
		var target_local: Vector2 = _target.global_position - global_position
		var tgt_col := Color(1, 0, 0, 0.8)
		draw_line(target_local + Vector2(-16, 0), target_local + Vector2(16, 0), tgt_col, 2.0)
		draw_line(target_local + Vector2(0, -16), target_local + Vector2(0, 16), tgt_col, 2.0)
		draw_arc(target_local, 12.0, 0, TAU, 16, tgt_col, 1.5)
		draw_arc(target_local, 20.0, 0, TAU, 16, Color(1, 0, 0, 0.3), 1.0)
		var target_dist: float = target_local.length()
		draw_string(font, target_local + Vector2(14, -14), "TARGET P%d  dist:%.0f" % [_target_player_index, target_dist], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, tgt_col)
		draw_line(_skull, target_local, Color(1, 0.3, 0.1, 0.3), 1.0)

	# -- Leap attack: strike zone + arrival dots --
	if is_instance_valid(_target) and (_state == State.ATTACK_LEAP_PLAN or not _leap_plan_results.is_empty()):
		if DebugOverlay.should_draw("leap_attack/attack_zone", self):
			var tgt_local: Vector2 = _leap_target_pos - global_position
			draw_arc(tgt_local, sc(LEAP_STRIKE_REACH), 0, TAU, 24, Color(1, 0.8, 0, 0.4), 1.5)
			draw_string(font, tgt_local + Vector2(sc(LEAP_STRIKE_REACH) + 4, -4), "STRIKE ZONE", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 0.8, 0, 0.5))

		if DebugOverlay.should_draw("leap_attack/spots_considered", self):
			for result in _leap_plan_results:
				if result.has("arrival"):
					var arr_local: Vector2 = result["arrival"] - global_position
					var is_clear: bool = result["clear"]
					var arr_col: Color = Color(0, 1, 0, 0.7) if is_clear else Color(1, 0.3, 0, 0.4)
					draw_circle(arr_local, 3.0, arr_col)

	if not _leap_plan_results.is_empty():
		if DebugOverlay.should_draw("leap_attack/attack_zone", self):
			var plan_info: Vector2 = _spine[0] + Vector2(-40, -80)
			var clear_count: int = 0
			for r in _leap_plan_results:
				if r["clear"]:
					clear_count += 1
			var phase_str: String = "P1" if _leap_plan_phase <= 1 else "P1+P2"
			draw_string(font, plan_info, "LEAP %s: %d/%d clear  arrivals:%d" % [phase_str, clear_count, _leap_plan_results.size(), LEAP_ARRIVAL_SAMPLES], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0, 1, 0.5))

		# All arcs (heavy)
		if DebugOverlay.should_draw("leap_attack/arc_trajectories", self):
			for result in _leap_plan_results:
				var is_clear: bool = result["clear"]
				var arc_col: Color = Color(0, 0.7, 0, 0.2) if is_clear else Color(0.7, 0, 0, 0.08)
				var al: PackedVector2Array = result["arc_l"]
				var ar: PackedVector2Array = result["arc_r"]
				for i in range(al.size() - 1):
					draw_line(al[i] - global_position, al[i + 1] - global_position, arc_col, 1.0)
				for i in range(ar.size() - 1):
					draw_line(ar[i] - global_position, ar[i + 1] - global_position, arc_col, 1.0)

		# Chosen arc + launch point
		if _leap_found_path:
			if DebugOverlay.should_draw("leap_attack/launch_point", self):
				var launch_local: Vector2 = _leap_launch_pos - global_position
				draw_circle(launch_local, 8.0, Color(0, 1, 0.5, 0.8))
				draw_string(font, launch_local + Vector2(10, -8), "LAUNCH", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0, 1, 0.5))
			if DebugOverlay.should_draw("leap_attack/chosen_arc", self):
				var chosen_col := Color(0, 1, 0.3, 0.8)
				for i in range(_leap_chosen_arc_l.size() - 1):
					draw_line(_leap_chosen_arc_l[i] - global_position, _leap_chosen_arc_l[i + 1] - global_position, chosen_col, 2.5)
				for i in range(_leap_chosen_arc_r.size() - 1):
					draw_line(_leap_chosen_arc_r[i] - global_position, _leap_chosen_arc_r[i + 1] - global_position, chosen_col, 2.5)
				if _leap_chosen_arc_l.size() > 5 and _leap_chosen_arc_r.size() > 5:
					var peak_l: Vector2 = _leap_chosen_arc_l[5] - global_position
					var peak_r: Vector2 = _leap_chosen_arc_r[5] - global_position
					draw_line(peak_l, peak_r, Color(0, 1, 0.5, 0.5), 1.0)

	# -- Pre-cognition: status text --
	if (_state == State.PRECOGNITION or not _precog_platforms.is_empty()):
		if DebugOverlay.should_draw("precog/status_text", self):
			var screen_x2: float = global_position.x
			var text_x2: float = -global_position.x + 200 if screen_x2 > 960 else -global_position.x + 1700
			var precog_info := Vector2(text_x2, -global_position.y + 160)
			draw_line(precog_info + Vector2(0, 10), _spine[0], Color(0.6, 0.3, 0.8, 0.15), 1.0)
			var phase_labels := ["DETECT", "GRAPH", "PATH", "EXEC"]
			var phase_lbl: String = phase_labels[_precog_phase] if _precog_phase < phase_labels.size() else "?"
			var pdy: int = 0
			var pcol := Color(0.8, 0.4, 1)
			draw_string(font, precog_info + Vector2(0, pdy), "PRECOG: %s  plats:%d  edges:%d" % [
				phase_lbl, _precog_platforms.size(), _precog_edges.size()
			], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, pcol)
			pdy += 12
			draw_string(font, precog_info + Vector2(0, pdy), "Path: %s  hop:%d/%d" % [
				str(_precog_path), _precog_current_hop + 1, _precog_path_edges.size()
			], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, pcol)
			if _precog_has_waypoint:
				pdy += 12
				draw_string(font, precog_info + Vector2(0, pdy), "WPT: (%.0f,%.0f)  edge_keys:%s" % [
					_precog_waypoint.x, _precog_waypoint.y, str(_precog_waypoint_edge.keys())
				], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 0.5, 0))

		# Ball landings
		if DebugOverlay.should_draw("precog/ball_landings", self):
			for pos in _precog_ball_lands:
				draw_circle(pos - global_position, 1.5, Color(0.5, 0.3, 0.8, 0.2))

		# Platforms
		if DebugOverlay.should_draw("precog/platform_list", self):
			for i in range(_precog_platforms.size()):
				var plat: Dictionary = _precog_platforms[i]
				var p_local: Vector2 = plat["pos"] - global_position
				var half_w: float = (plat["max_x"] - plat["min_x"]) * 0.5
				var bar_l: Vector2 = Vector2(p_local.x - half_w, p_local.y)
				var bar_r: Vector2 = Vector2(p_local.x + half_w, p_local.y)
				var plat_col: Color = Color(0.7, 0.3, 1, 0.6)
				if plat["label"] == "monster":
					plat_col = Color(0, 1, 0.5, 0.8)
				elif plat["label"] == "target":
					plat_col = Color(1, 0.2, 0.2, 0.8)
				draw_line(bar_l, bar_r, plat_col, 3.0)
				draw_circle(p_local, 4.0, plat_col)
				var lbl: String = "P%d" % i
				if plat["label"] != "":
					lbl += " [%s]" % plat["label"]
				draw_string(font, p_local + Vector2(6, -6), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, plat_col)

		# Graph edges (heavy)
		if DebugOverlay.should_draw("precog/graph_edges", self):
			for edge in _precog_edges:
				var arc_l: PackedVector2Array = edge["arc_l"]
				var arc_r: PackedVector2Array = edge["arc_r"]
				var edge_col := Color(0.3, 0.6, 1, 0.25)
				for ei in range(arc_l.size() - 1):
					draw_line(arc_l[ei] - global_position, arc_l[ei + 1] - global_position, edge_col, 1.0)
				for ei in range(arc_r.size() - 1):
					draw_line(arc_r[ei] - global_position, arc_r[ei + 1] - global_position, edge_col, 1.0)

		# Chosen path
		if DebugOverlay.should_draw("precog/current_path", self):
			if _precog_path.size() >= 2:
				var path_col := Color(1, 0.8, 0, 0.8)
				for pi in range(_precog_path.size() - 1):
					var a_local: Vector2 = _precog_platforms[_precog_path[pi]]["pos"] - global_position
					var b_local: Vector2 = _precog_platforms[_precog_path[pi + 1]]["pos"] - global_position
					draw_line(a_local, b_local, path_col, 2.0)
					draw_circle(a_local, 6.0, path_col)
				draw_circle(_precog_platforms[_precog_path[_precog_path.size() - 1]]["pos"] - global_position, 6.0, path_col)

				# Path edge arcs
				for pe in _precog_path_edges:
					var pe_col := Color(0, 1, 0.3, 0.6)
					var pe_l: PackedVector2Array = pe["arc_l"]
					var pe_r: PackedVector2Array = pe["arc_r"]
					for ei in range(pe_l.size() - 1):
						draw_line(pe_l[ei] - global_position, pe_l[ei + 1] - global_position, pe_col, 2.0)
					for ei in range(pe_r.size() - 1):
						draw_line(pe_r[ei] - global_position, pe_r[ei + 1] - global_position, pe_col, 2.0)

	# -- Planned leap edges (for test inspection) --
	if DebugOverlay.should_draw("testing/planned_leaps", self) and not _precog_edges.is_empty():
		for edge in _precog_edges:
			var launch: Vector2 = edge.get("from_pos", Vector2.ZERO) - global_position
			var landing: Vector2 = edge.get("arrival", Vector2.ZERO) - global_position
			var arc_c: PackedVector2Array = edge.get("arc_c", PackedVector2Array())
			var arc_l: PackedVector2Array = edge.get("arc_l", PackedVector2Array())
			var arc_r: PackedVector2Array = edge.get("arc_r", PackedVector2Array())
			# Center arc: bold blue
			for ei in range(arc_c.size() - 1):
				draw_line(arc_c[ei] - global_position, arc_c[ei + 1] - global_position, Color(0.2, 0.6, 1.0, 0.8), 2.5)
			# Draw arrowhead at center arc end
			if arc_c.size() >= 2:
				var tip: Vector2 = arc_c[arc_c.size() - 1] - global_position
				var dir: Vector2 = (arc_c[arc_c.size() - 1] - arc_c[arc_c.size() - 2]).normalized()
				var perp: Vector2 = Vector2(-dir.y, dir.x)
				draw_line(tip, tip - dir * 8 + perp * 5, Color(0.2, 0.6, 1.0, 0.9), 2.0)
				draw_line(tip, tip - dir * 8 - perp * 5, Color(0.2, 0.6, 1.0, 0.9), 2.0)
			# Bounding arcs: thin grey — skip first 3 and last 3 points (inside platforms)
			for ei in range(3, arc_l.size() - 4):
				draw_line(arc_l[ei] - global_position, arc_l[ei + 1] - global_position, Color(0.5, 0.5, 0.5, 0.4), 1.0)
			for ei in range(3, arc_r.size() - 4):
				draw_line(arc_r[ei] - global_position, arc_r[ei + 1] - global_position, Color(0.5, 0.5, 0.5, 0.4), 1.0)
			# Launch dot: green
			draw_circle(launch, 5.0, Color(0.2, 1.0, 0.3, 0.9))
			draw_circle(launch, 7.0, Color(0.2, 1.0, 0.3, 0.4))
			# Landing dot: orange
			draw_circle(landing, 5.0, Color(1.0, 0.6, 0.1, 0.9))
			draw_circle(landing, 7.0, Color(1.0, 0.6, 0.1, 0.4))

	# -- Attachment points --
	if DebugOverlay.should_draw("precog/attach_points", self):
		var attach_col := Color(0.4, 0.8, 1.0, 0.5)
		for point_name in _attach_points:
			var area: Area2D = _attach_points[point_name]
			var pos: Vector2 = area.position
			var r: float = 12.0
			if area.get_child_count() > 0:
				var shape_node: CollisionShape2D = area.get_child(0) as CollisionShape2D
				if shape_node and shape_node.shape is CircleShape2D:
					r = (shape_node.shape as CircleShape2D).radius
			var segments: int = 16
			for si in range(segments):
				if si % 2 == 1:
					continue
				var a1: float = TAU * float(si) / float(segments)
				var a2: float = TAU * float(si + 1) / float(segments)
				draw_line(pos + Vector2(cos(a1), sin(a1)) * r, pos + Vector2(cos(a2), sin(a2)) * r, attach_col, 1.0)
			draw_string(font, pos + Vector2(-20, -r - 4), point_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, attach_col)
			var acount: int = _attachments[point_name].size() if _attachments.has(point_name) else 0
			if acount > 0:
				draw_string(font, pos + Vector2(-8, r + 10), "x%d" % acount, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 0.8, 0.2))
