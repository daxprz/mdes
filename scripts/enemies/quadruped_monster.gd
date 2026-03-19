extends CharacterBody2D

## Procedurally animated quadruped monster.
## Verlet physics skeleton with 23 tracked points.
## All rendering via _draw(), no sprites.

signal died(global_pos: Vector2)

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

# Pose stiffness (how fast segments spring back to rest pose, per second)
const STIFFNESS := 12.0       # General stiffness
const TAIL_STIFFNESS := 14.0  # Tail is rigid by default
const TAIL_WHIP_STIFFNESS := 2.0  # Loose only during whip
const HEAD_TRACK_SPEED := 6.0  # How fast head turns toward target

# Foot-driven locomotion
const STEP_THRESHOLD := 60.0   # How far behind a foot gets before it steps
const STEP_DURATION := 0.12    # Seconds to complete a step (quick feet)
const STEP_HEIGHT := 28.0      # How high foot lifts during step
const STEP_OVERSHOOT := 0.25   # Overshoot fraction past target
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
const BITE_RANGE := 60.0
const TAIL_RANGE := 90.0
const ATTACK_COOLDOWN := 0.8  # Fast attack cycling
const AGGRO_SWITCH_HITS := 3

# Vertical leap
const LEAP_RANGE := 500.0      # Distance at which leap is considered
const LEAP_WINDUP_TIME := 0.6  # Seconds to coil up before launch (fast panther)
const LEAP_LAUNCH_SPEED := 900.0  # Launch velocity magnitude
const LEAP_SLASH_DAMAGE := 15  # Per slash (6 total = 90 max)
const LEAP_BITE_DAMAGE := 30   # Bite + thrash
const LEAP_THRASH_COUNT := 3   # Number of thrash shakes
const LEAP_COOLDOWN := 4.0     # Seconds between leaps

# Leap planning
const LEAP_BODY_RADIUS := 22.0    # Half-width of body for clearance checks (includes legs)
const LEAP_STRIKE_REACH := 80.0   # How far the creature can reach to strike from its center
const LEAP_ARRIVAL_SAMPLES := 12  # Number of arrival angles to test around target
const LEAP_FLIGHT_TIMES := 7      # Number of flight durations to try per arrival point
const LEAP_FLIGHT_TIME_MIN := 0.2 # Shortest flight time to test
const LEAP_FLIGHT_TIME_MAX := 1.5 # Longest flight time to test (higher arcs)
const LEAP_ARC_STEPS := 40        # Simulation steps per arc
const LEAP_PLAN_GRAVITY := 600.0  # Gravity for arc simulation
const LEAP_ARC_DT := 0.04         # Simulation timestep

# Health
const MAX_HEALTH := 200
const HEAD_HEALTH := 60
const TAIL_HEALTH := 50
const LEG_HEALTH := 40

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
			 ATTACK_LUNGE, ATTACK_SPRINT_SLASH, ATTACK_HOP_UP,
			 ATTACK_LEAP_PLAN, ATTACK_LEAP_WINDUP,
			 ATTACK_LEAP_AIRBORNE, ATTACK_LEAP_STRIKE, ATTACK_LEAP_THRASH,
			 PRECOGNITION, TRANSITION_BIPEDAL, TRANSITION_QUADRUPED, HURT, DEAD }
enum Posture { QUADRUPED, BIPEDAL }

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

# Legs: 4 legs, each with 3 points [hip, knee, foot]
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

# Part health
var _part_health: Dictionary = {}
var _leg_severed: Array[bool] = [false, false, false, false]
var _tail_severed: bool = false
var _head_severed: bool = false

# Hitbox nodes (assigned in _ready from scene tree or created dynamically)
var _hitboxes: Dictionary = {}  # part_name -> Area2D
var _body_collision: CollisionShape2D = null  # Main body collision shape
var debug_draw_enabled: bool = false  # Visual debug rendering (heavy — disable for perf)


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 8
	collision_mask = 1

	_init_skeleton()
	_init_part_health()
	_init_collision()
	_init_hitboxes()


func _init_skeleton() -> void:
	# Body height: spine elevated so feet rest at y=0 (floor contact)
	var body_y: float = -(4.0 + LEG_UPPER_LEN + LEG_LOWER_LEN)  # ~-50

	# Spine: horizontal at body_y
	_spine.resize(3)
	_spine_rest.resize(3)
	for i in range(3):
		_spine[i] = Vector2((1 - i) * SPINE_SEG_LEN * _facing, body_y)
	_spine_rest[0] = Vector2.ZERO  # spine[0] is the anchor
	_spine_rest[1] = Vector2(-SPINE_SEG_LEN * _facing, 0)  # offset from spine[0]
	_spine_rest[2] = Vector2(-SPINE_SEG_LEN * _facing, 0)  # offset from spine[1]

	# Neck: extends forward-up from spine[0]
	_neck.resize(2)
	_neck[0] = _spine[0]
	_neck_rest = Vector2(NECK_LEN * 0.8 * _facing, -NECK_LEN * 0.7)
	_neck[1] = _spine[0] + _neck_rest

	# Head: skull connects directly to neck tip (no gap), 2x size
	_skull_rest = Vector2(14 * _facing, -8)
	_skull = _neck[1] + _skull_rest
	_jaw_rest = Vector2(8 * _facing, JAW_LEN * 0.6)
	_jaw = _skull + _jaw_rest

	# Tail: extends backward from spine[2], slightly raised (rigid)
	_tail.resize(5)
	_tail_rest.resize(5)
	for i in range(5):
		# Tail goes backward and slightly up, rigid like a counterbalance
		_tail_rest[i] = Vector2(-TAIL_SEG_LEN * _facing, -2.0)
	var tail_anchor: Vector2 = _spine[2] + Vector2(-4 * _facing, -2)
	for i in range(5):
		if i == 0:
			_tail[i] = tail_anchor + _tail_rest[i]
		else:
			_tail[i] = _tail[i - 1] + _tail_rest[i]

	# Legs
	_legs.resize(4)
	_leg_rest.resize(4)
	_foot_world.resize(4)
	_foot_planted.resize(4)
	_step_timers.resize(4)
	_step_origins.resize(4)
	_step_targets.resize(4)
	_step_center.resize(4)

	for li in range(4):
		var hip_anchor: Vector2 = _spine[0] if li < 2 else _spine[2]
		var side_x: float = 3.0 if (li % 2 == 0) else -3.0

		var leg: Array[Vector2] = []
		leg.resize(3)
		leg[0] = hip_anchor + Vector2(side_x, 6)
		leg[1] = hip_anchor + Vector2(side_x, 6 + LEG_UPPER_LEN)
		leg[2] = Vector2(hip_anchor.x + side_x, 0)
		_legs[li] = leg

		var rest: Array[Vector2] = []
		rest.resize(3)
		rest[0] = Vector2(side_x, 6)
		rest[1] = Vector2(0, LEG_UPPER_LEN)
		rest[2] = Vector2(0, LEG_LOWER_LEN)
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
		"body": MAX_HEALTH,
		"head": HEAD_HEALTH,
		"tail": TAIL_HEALTH,
		"leg0": LEG_HEALTH,
		"leg1": LEG_HEALTH,
		"leg2": LEG_HEALTH,
		"leg3": LEG_HEALTH,
	}


func _init_collision() -> void:
	# Small horizontal capsule around the body core only.
	# Legs find the floor via raycasting, not the collision shape.
	var shape := CapsuleShape2D.new()
	shape.radius = 10.0
	shape.height = SPINE_SEG_LEN * 2.0 + shape.radius * 2.0
	_body_collision = CollisionShape2D.new()
	_body_collision.shape = shape
	_body_collision.rotation = PI / 2.0  # Horizontal
	_body_collision.position = Vector2(0, -10.0)  # Centered on body, slightly above floor
	add_child(_body_collision)


func _init_hitboxes() -> void:
	# Create Area2D hitboxes for each damageable part
	var parts := ["body", "head", "tail", "leg0", "leg1", "leg2", "leg3"]
	for part_name in parts:
		var area := Area2D.new()
		area.name = "Hitbox_" + part_name
		area.collision_layer = 0
		area.collision_mask = 2  # Player attacks
		area.set_meta("part_name", part_name)
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 12.0 if part_name == "body" else 8.0
		shape.shape = circle
		area.add_child(shape)
		add_child(area)
		_hitboxes[part_name] = area


# -- Physics -------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _dead:
		return

	# Out-of-bounds recovery: teleport back to spawn area
	if global_position.y > 1200 or global_position.y < -200 or global_position.x < -100 or global_position.x > 2020:
		print("MONSTER: out of bounds at (%.0f,%.0f) — teleporting back" % [global_position.x, global_position.y])
		global_position = Vector2(960, 850)
		velocity = Vector2.ZERO
		_end_leap()
		_state = State.CHASE

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

	# Leap/precog states handle their own skeleton — skip normal locomotion/pose
	var in_leap_flight: bool = (_state == State.ATTACK_LEAP_WINDUP
		or _state == State.ATTACK_LEAP_AIRBORNE or _state == State.ATTACK_LEAP_STRIKE
		or _state == State.ATTACK_LEAP_THRASH)
	var in_precog: bool = (_state == State.PRECOGNITION)

	if in_leap_flight:
		_update_leap_collision(delta)
	elif not in_precog:
		_update_foot_push(delta)

	move_and_slide()

	if in_leap_flight:
		_update_leap_pose(delta)
	elif not in_precog:
		_update_spine()
		_update_gait(delta)
		_solve_pose(delta)
	# Precognition pose is handled inside _do_precognition → _apply_curl_pose

	_update_hitbox_positions()

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
		var skull_dist: float = NECK_LEN + _skull_rest.length()
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

	# -- Legs: 2-bone IK from hip to foot, knee solved --
	for li in range(4):
		if _leg_severed[li]:
			# Severed legs fall with gravity
			for j in range(3):
				_legs[li][j].y += GRAVITY * delta * 0.3
			continue

		var hip_spine: Vector2 = _spine[0] if li < 2 else _spine[2]
		var rest: Array = _leg_rest[li]

		# Hip: pinned to spine
		_legs[li][0] = hip_spine + _get_facing_offset(rest[0])

		# When IK is off (during leap), legs are positioned manually — skip IK
		if _leap_ik_off:
			continue

		# Foot position is set by _update_gait (world→local).
		# IK solves the knee to connect hip to wherever the foot is.

		# Knee: solved via 2-bone IK (hip → knee → foot)
		# Mammal anatomy: front elbows bend BACKWARD, rear knees bend FORWARD
		var bend_dir: float = 1.0 if li < 2 else -1.0
		bend_dir *= _facing  # Flip with facing
		var knee_pos: Vector2 = _solve_leg_ik(
			_legs[li][0], _legs[li][2],
			LEG_UPPER_LEN, LEG_LOWER_LEN,
			bend_dir
		)
		_legs[li][1] = _legs[li][1].lerp(knee_pos, s_clamp)

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


func _get_facing_offset(offset: Vector2) -> Vector2:
	## Flip x component based on facing direction.
	## Rest offsets are stored for _facing=1. Flip x if facing left.
	if _facing < 0:
		return Vector2(-offset.x, offset.y)
	return offset


# -- Spine & Posture ----------------------------------------------------------

func _update_spine() -> void:
	# Spine height is relative to the real floor under the body.
	# Raycast from body center to find the floor, then position spine above it.
	var floor_y: float = _raycast_floor(Vector2(0, _spine[1].y if _spine.size() > 1 else -30))
	var leg_reach: float = LEG_UPPER_LEN + LEG_LOWER_LEN - 4.0  # How high above floor
	var body_y: float = floor_y - leg_reach
	# In bipedal, front raises higher
	var spine_y_front: float = lerpf(body_y, body_y - 30.0, _posture_blend)
	_spine[0] = Vector2(SPINE_SEG_LEN * _facing, spine_y_front)
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
		push_x += _want_direction * FOOT_PUSH_FORCE * (_move_speed / SPEED_MEDIUM)

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
	var breathe_offset: float = sin(_breathe_time * 2.0) * 1.5
	for i in range(3):
		_spine[i].y += breathe_offset * delta * 4.0

	# Convert planted feet from world space to local space for rendering/IK
	for li in range(4):
		if _leg_severed[li]:
			continue
		if _foot_planted[li]:
			# Foot stays fixed in world space — convert to local for drawing
			_legs[li][2] = _foot_world[li] - global_position
		# else: foot is mid-step, _animate_step handles it

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
	if a_dist >= b_dist and a_dist > STEP_THRESHOLD:
		_try_step(a)
	elif b_dist > STEP_THRESHOLD:
		_try_step(b)


func _ideal_foot_world(li: int) -> Vector2:
	## Where this foot SHOULD be in world space.
	## Front legs reach AHEAD, rear legs trail BEHIND.
	var hip_local: Vector2 = _legs[li][0]
	var hip_world: Vector2 = global_position + hip_local
	var stride: float = _want_direction * _move_speed * 0.35
	if li >= 2:
		# Rear legs: target behind the hip instead of ahead
		stride *= -0.5
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

	if dist > STEP_THRESHOLD:
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
		_step_center[li] = (foot_pos + _step_targets[li]) * 0.5 + Vector2(0, -STEP_HEIGHT)


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
		# Foot plants at the new world position
		_foot_planted[li] = true
		_foot_world[li] = _step_targets[li]
		_legs[li][2] = _foot_world[li] - global_position


# -- Floor raycasting ----------------------------------------------------------

func _raycast_floor(local_from: Vector2) -> float:
	## Raycast downward from a local-space point to find the world floor.
	## Returns the floor y in local space, or a fallback if no hit.
	var space := get_world_2d().direct_space_state
	if not space:
		return local_from.y + LEG_UPPER_LEN + LEG_LOWER_LEN

	var world_from: Vector2 = global_position + local_from
	var world_to: Vector2 = world_from + Vector2(0, 200)  # Cast 200px down
	var query := PhysicsRayQueryParameters2D.create(world_from, world_to, 1)  # Mask 1 = world
	query.exclude = [get_rid()]
	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return local_from.y + LEG_UPPER_LEN + LEG_LOWER_LEN  # Fallback: dangle at full leg length
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
	_move_speed = SPEED_SLOW
	_want_direction = _facing

	_pick_target()
	if _target and is_instance_valid(_target):
		_state = State.CHASE


func _do_chase(_delta: float) -> void:
	if not is_instance_valid(_target):
		_state = State.PATROL
		return

	_pick_target()  # Check aggro switch

	# If we have a precog waypoint, walk there then leap
	# Reset the no-hit timer while executing a precog plan (don't re-trigger)
	if _precog_has_waypoint or not _precog_path_edges.is_empty():
		_time_since_strike_range = 0.0

	if _precog_has_waypoint:
		var to_waypoint: Vector2 = _precog_waypoint - global_position
		var waypoint_dist: float = absf(to_waypoint.x)
		if Engine.get_frames_drawn() % 30 == 0:
			print("PRECOG WALK: wpt=(%.0f,%.0f) me=(%.0f,%.0f) dx=%.0f edge_empty=%s" % [
				_precog_waypoint.x, _precog_waypoint.y,
				global_position.x, global_position.y,
				waypoint_dist, str(_precog_waypoint_edge.is_empty())])
		_facing = signf(to_waypoint.x) if absf(to_waypoint.x) > 5.0 else _facing
		_want_direction = signf(to_waypoint.x)
		_move_speed = SPEED_FAST

		if waypoint_dist < 10.0:
			_precog_has_waypoint = false
			var has_vel: bool = _precog_waypoint_edge.has("launch_vel")
			var vel_val: String = str(_precog_waypoint_edge.get("launch_vel", "NONE"))
			var has_arcs: bool = _precog_waypoint_edge.has("arc_l") and _precog_waypoint_edge.has("arc_r")
			print("PRECOG: ARRIVED. has_vel=%s vel=%s has_arcs=%s edge_keys=%s" % [
				str(has_vel), vel_val, str(has_arcs), str(_precog_waypoint_edge.keys())])

			if not _precog_waypoint_edge.is_empty() and _precog_waypoint_edge.has("launch_vel"):
				# Use the pre-computed velocity — the arrival threshold ensures
				# we're close enough to the planned launch point.
				var edge: Dictionary = _precog_waypoint_edge
				print("PRECOG: EXECUTING leap vel=(%.0f,%.0f)" % [edge["launch_vel"].x, edge["launch_vel"].y])

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
				_state = State.ATTACK_LEAP_WINDUP
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

	# If target is on a different platform AND we can't walk to them,
	# immediately use precog pathfinding (don't wait for timeout)
	var target_above: bool = to_target.y < -40.0
	var target_far_below: bool = to_target.y > 100.0
	if (target_above or target_far_below) and _leap_cooldown <= 0.0:
		_start_precognition()
		return

	# Fallback: if we haven't hit anything for a while, also use precog
	_time_since_strike_range += _delta
	if _time_since_strike_range >= PRECOG_TRIGGER_TIME:
		_start_precognition()
		return

	# Speed based on distance
	if dist > 200.0:
		_move_speed = SPEED_FAST
	elif dist > 80.0:
		_move_speed = SPEED_MEDIUM
	else:
		_move_speed = SPEED_SLOW

	# Choose attack when in range
	if _attack_cooldown <= 0.0:
		_choose_attack(dist, to_target)


func _choose_attack(dist: float, to_target: Vector2) -> void:
	var target_behind: bool = signf(to_target.x) != _facing
	var height_diff: float = to_target.y  # Negative = target is above

	# Tail whip if target is behind and close
	if target_behind and dist < TAIL_RANGE and _posture == Posture.QUADRUPED and not _tail_severed:
		_start_attack(State.ATTACK_TAIL)
		return

	# CONNECTED HOP-UP: target is on a platform just above (short climb)
	if height_diff < -20.0 and absf(height_diff) < HOP_UP_MAX_HEIGHT and absf(to_target.x) < 150.0:
		_start_hop_up(to_target)
		return

	# SPRINT SLASH: same level, medium range — charge and slash
	if absf(height_diff) < 30.0 and dist > BITE_RANGE and dist < 200.0 and _count_front_legs() >= 1:
		_start_sprint_slash()
		return

	# VERTICAL LEAP: significant distance or height difference
	if dist > 80.0 and dist < LEAP_RANGE and _leap_cooldown <= 0.0 and _count_active_legs() >= 2:
		_start_leap()
		return

	# Lunge at medium distance
	if dist > 80.0 and dist < 200.0 and randf() < 0.3:
		_start_attack(State.ATTACK_LUNGE)
		return

	# Close range: bite or standing swipe
	if dist < BITE_RANGE:
		if randf() < 0.6 or _count_front_legs() == 0:
			_start_attack(State.ATTACK_BITE)
		else:
			_state = State.TRANSITION_BIPEDAL
			_attack_timer = 0.0
		return


func _start_attack(attack_state: State) -> void:
	_state = attack_state
	_attack_timer = 0.0
	_attack_cooldown = ATTACK_COOLDOWN


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
		_state = State.CHASE


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
		_state = State.TRANSITION_QUADRUPED
		_attack_timer = 0.0


func _do_tail_whip(delta: float) -> void:
	_attack_timer += delta
	velocity.x = 0

	if _tail_severed:
		_tail_whipping = false
		_state = State.CHASE
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
		_tail_whipping = false
		_state = State.CHASE


func _do_lunge(delta: float) -> void:
	_attack_timer += delta

	if _attack_timer < 0.15:
		# Windup: compress legs
		velocity.x = -_facing * 30.0
	elif _attack_timer < 0.4:
		# Launch
		velocity.x = _facing * LUNGE_SPEED
		_check_lunge_hit()
	elif _attack_timer < 0.7:
		# Slide to stop
		velocity.x = lerpf(velocity.x, 0, 0.1)
	else:
		velocity.x = 0
		_state = State.CHASE


# -- Sprint Slash (same-plane charge + triple swipe) ---------------------------

func _start_sprint_slash() -> void:
	_state = State.ATTACK_SPRINT_SLASH
	_attack_timer = 0.0
	_attack_cooldown = ATTACK_COOLDOWN
	_sprint_slash_count = 0


func _do_sprint_slash(delta: float) -> void:
	## Sprint toward the target, then unleash 3 rapid slashes.
	_attack_timer += delta

	if not is_instance_valid(_target):
		_state = State.CHASE
		return

	var to_target: Vector2 = _target.global_position - global_position
	var dist: float = to_target.length()
	_facing = signf(to_target.x) if absf(to_target.x) > 5.0 else _facing

	if _sprint_slash_count == 0:
		# Phase 1: Sprint toward target
		_want_direction = _facing
		_move_speed = SPRINT_SPEED

		if dist < SPRINT_SLASH_RANGE:
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

				# Damage
				var claw_world: Vector2 = global_position + _legs[slash_leg][2]
				_damage_players_in_range(claw_world, 35.0, SPRINT_SLASH_DAMAGE)

				# Visual slash lines
				_spawn_slash_effect(_legs[slash_leg][2])

			_sprint_slash_count += 1

		# Done after 3 slashes + recovery
		if _attack_timer > 3 * SPRINT_SLASH_INTERVAL + 0.2:
			_state = State.CHASE

	# Timeout safety
	if _attack_timer > 3.0:
		_state = State.CHASE


# -- Connected Hop-Up (short platform climb) -----------------------------------

func _start_hop_up(to_target: Vector2) -> void:
	_state = State.ATTACK_HOP_UP
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
		height_to_climb = HOP_UP_MAX_HEIGHT * 0.5

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
		_state = State.CHASE
		_attack_timer = 0.0


func _do_transition_bipedal(delta: float) -> void:
	_attack_timer += delta
	velocity.x = 0
	_posture_blend = clampf(_attack_timer / 0.4, 0.0, 1.0)
	if _attack_timer >= 0.4:
		_posture = Posture.BIPEDAL
		_state = State.ATTACK_SWIPE
		_attack_timer = 0.0


func _do_transition_quadruped(delta: float) -> void:
	_attack_timer += delta
	velocity.x = 0
	_posture_blend = 1.0 - clampf(_attack_timer / 0.4, 0.0, 1.0)
	if _attack_timer >= 0.4:
		_posture = Posture.QUADRUPED
		_posture_blend = 0.0
		_state = State.CHASE


# -- Vertical Leap Attack ------------------------------------------------------

func _update_leap_collision(delta: float) -> void:
	## During leap: rotate the collision shape to match the body's flight angle.
	if _state == State.ATTACK_LEAP_WINDUP:
		# During windup, rotate collision to match spine tilt
		var to_target: Vector2 = _leap_target_pos - global_position
		var target_angle: float = to_target.angle()
		_leap_body_angle = lerpf(_leap_body_angle, target_angle, 3.0 * delta)
	elif _state == State.ATTACK_LEAP_AIRBORNE:
		# During flight, align with velocity
		if velocity.length() > 10:
			_leap_body_angle = velocity.angle()
	# Apply rotation to collision shape
	if _body_collision:
		_body_collision.rotation = _leap_body_angle
		# Position collision at spine center
		_body_collision.position = (_spine[0] + _spine[2]) * 0.5


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
		var rest_spine0 := Vector2(SPINE_SEG_LEN * _facing, -(4.0 + LEG_UPPER_LEN + LEG_LOWER_LEN))
		var aimed_spine0 := spine_center + aim_dir * SPINE_SEG_LEN
		_spine[0] = _spine[0].lerp(rest_spine0.lerp(aimed_spine0, t), 6.0 * delta)
		var rest_spine2 := Vector2(-SPINE_SEG_LEN * _facing, -(4.0 + LEG_UPPER_LEN + LEG_LOWER_LEN))
		var aimed_spine2 := spine_center - aim_dir * SPINE_SEG_LEN
		_spine[2] = _spine[2].lerp(rest_spine2.lerp(aimed_spine2, t), 6.0 * delta)
		_spine[1] = (_spine[0] + _spine[2]) * 0.5
	else:
		# Airborne/strike/thrash: spine fully aimed
		_spine[0] = _spine[0].lerp(spine_center + aim_dir * SPINE_SEG_LEN, 10.0 * delta)
		_spine[2] = _spine[2].lerp(spine_center - aim_dir * SPINE_SEG_LEN, 10.0 * delta)
		_spine[1] = (_spine[0] + _spine[2]) * 0.5

	# -- Neck + Head: aim at target --
	_neck[0] = _spine[0]
	var neck_tip: Vector2 = _spine[0] + aim_dir * NECK_LEN
	_neck[1] = _neck[1].lerp(neck_tip, 8.0 * delta)
	var skull_pos: Vector2 = _neck[1] + aim_dir * 14.0
	_skull = _skull.lerp(skull_pos, 8.0 * delta)
	var jaw_down: Vector2 = -aim_perp  # Jaw opens away from "up"
	_jaw = _jaw.lerp(_skull + jaw_down * (JAW_LEN * 0.3 + _jaw_open * JAW_LEN * 0.5), 8.0 * delta)

	# -- Tail: trails behind --
	if not _tail_severed:
		var tail_dir: Vector2 = -aim_dir
		if _state == State.ATTACK_LEAP_WINDUP:
			# Tail plants on ground during windup (handled by _do_leap_windup)
			pass
		else:
			# Airborne: tail streams straight behind
			for i in range(5):
				var tail_target: Vector2 = _spine[2] + tail_dir * TAIL_SEG_LEN * (i + 1)
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
			var stretched: Vector2 = _legs[li][0] - aim_dir * (LEG_UPPER_LEN + LEG_LOWER_LEN - 2)
			_legs[li][2] = _legs[li][2].lerp(stretched, 8.0 * delta)
			_legs[li][1] = _legs[li][0] - aim_dir * LEG_UPPER_LEN

	# -- Floor constraints OFF during airborne --
	# (handled by skipping _solve_pose entirely)


func _start_leap() -> void:
	_state = State.ATTACK_LEAP_PLAN
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
		_state = State.CHASE
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
			_state = State.ATTACK_LEAP_WINDUP
			_attack_timer = 0.0
			_leap_ik_off = true
			velocity.x = 0
		else:
			# Walk toward launch position
			_facing = signf(to_launch.x) if absf(to_launch.x) > 5.0 else _facing
			_want_direction = signf(to_launch.x)
			_move_speed = SPEED_MEDIUM
	else:
		# Both phases failed — abort after brief pause
		if _attack_timer > 0.5:
			_state = State.CHASE
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

	# Step 1: find valid arrival points (open air within strike reach of target)
	var arrival_points: Array[Vector2] = []
	for ai in range(LEAP_ARRIVAL_SAMPLES):
		var angle: float = float(ai) / float(LEAP_ARRIVAL_SAMPLES) * TAU
		var arrival: Vector2 = target_pos + Vector2(cos(angle), sin(angle)) * LEAP_STRIKE_REACH

		# Must be in open air
		if _is_point_in_solid(arrival):
			continue

		# Only consider arrival points above or level with target (not attacking from below)
		if arrival.y > target_pos.y + 30:
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
			var arc_l: PackedVector2Array = _simulate_arc(monster_pos + launch_perp * LEAP_BODY_RADIUS, launch_vel)
			var arc_r: PackedVector2Array = _simulate_arc(monster_pos - launch_perp * LEAP_BODY_RADIUS, launch_vel)

			var clear: bool = _check_arc_clear(arc_c) and _check_arc_clear(arc_l) and _check_arc_clear(arc_r)

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
	var min_clearance: float = LEAP_BODY_RADIUS * 1.2  # ~26px each side — tight, precise launch

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

			if launch_pos.x < bounds_left + LEAP_BODY_RADIUS * 2:
				continue
			if launch_pos.x > bounds_right - LEAP_BODY_RADIUS * 2:
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
				var arc_l: PackedVector2Array = _simulate_arc(launch_pos + launch_perp * LEAP_BODY_RADIUS, launch_vel)
				var arc_r: PackedVector2Array = _simulate_arc(launch_pos - launch_perp * LEAP_BODY_RADIUS, launch_vel)

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
	## Pre-compute platform map and full connectivity graph at spawn time.
	## This is expensive (~50ms) but only runs once. After this, precog
	## just needs to tag entities and run Dijkstra (instant).
	_precog_platforms_cached = false  # Force fresh scan
	_precog_drop_and_detect()
	# Build full graph
	_precog_edges.clear()
	var n: int = _precog_platforms.size()
	for pi in range(n):
		for pj in range(n):
			if pi != pj:
				_precog_process_i = pi
				_precog_process_j = pj
				_precog_build_one_edge(pi, pj)
	print("PRECOG PRECACHE: %d platforms, %d edges (computed at spawn)" % [n, _precog_edges.size()])


func _start_precognition() -> void:
	_state = State.PRECOGNITION
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
			if _precog_edges.is_empty() or _precog_platforms.size() < 3:
				_precache_platforms()
			# Re-tag entity positions
			for plat in _precog_platforms:
				plat["label"] = ""
			_precog_add_entity_platform(global_position, "monster")
			if is_instance_valid(_target):
				_precog_add_entity_platform(_target.global_position, "target")
			_precog_find_path()
			print("PRECOG: path=%s (len=%d) [%d plats, %d edges]" % [
				str(_precog_path), _precog_path_edges.size(),
				_precog_platforms.size(), _precog_edges.size()])
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



func _precog_add_entity_platform(world_pos: Vector2, label: String) -> void:
	## Ensure there's a platform entry for the monster/target's current position.
	## If they're standing on an existing platform, tag it. Otherwise add one.
	## Uses generous Y tolerance since platform Y is snapped and entity Y is exact.
	# Use the floor under the entity, not its body position, for matching
	var floor_y: float = _raycast_floor(world_pos - global_position) + global_position.y
	for plat in _precog_platforms:
		if absf(floor_y - plat["pos"].y) < 30.0 and world_pos.x >= plat["min_x"] - 40 and world_pos.x <= plat["max_x"] + 40:
			plat["label"] = label
			return
	# Not on a known platform — add a point platform (reuse floor_y from above)
	_precog_platforms.append({
		"pos": Vector2(world_pos.x, floor_y),
		"min_x": world_pos.x - 10,
		"max_x": world_pos.x + 10,
		"weight": 1,
		"label": label,
	})


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
		var from_y: float = plat_from["pos"].y
		var from_min_x: float = plat_from["min_x"]
		var from_max_x: float = plat_from["max_x"]

		# Collect ball landings that are on this platform
		var launch_points: Array[Vector2] = []
		for pos in _precog_ball_lands:
			if absf(pos.y - from_y) < 15.0 and pos.x >= from_min_x - 5 and pos.x <= from_max_x + 5:
				launch_points.append(pos)

		if _precog_process_i == 0 and _precog_process_j == 1:
			print("PRECOG GRAPH: P%d->P%d launches=%d from=(%.0f,%.0f) to=(%.0f,%.0f)" % [
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

		for launch_pos in unique_launches:
			if not _has_lateral_clearance(launch_pos):
				continue

			# Reject launch points directly under the destination platform —
			# the arc would immediately hit it from below.
			var to_y: float = plat_to["pos"].y
			# Also check ALL platforms above the launch point, not just the destination
			# Target the platform surface directly (not strike-reach circle)
			var result: Dictionary = _plan_leap_to_surface(launch_pos, plat_to)
			if not result.is_empty():
				var score: float = result["arrival"].distance_to(plat_to["pos"])
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
	var n: int = _precog_platforms.size()
	var monster_plat: int = -1
	var target_plat: int = -1

	for i in range(n):
		if _precog_platforms[i]["label"] == "monster":
			monster_plat = i
		if _precog_platforms[i]["label"] == "target":
			target_plat = i

	print("PRECOG PATHFIND: monster=P%d target=P%d" % [monster_plat, target_plat])
	if monster_plat < 0 or target_plat < 0:
		print("PRECOG PATHFIND: FAILED — monster or target not on a platform")
		_precog_path.clear()
		return
	if monster_plat == target_plat:
		print("PRECOG PATHFIND: same platform — no leap needed")
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
	if _precog_path.size() < 2 or _precog_path_edges.is_empty():
		_state = State.CHASE
		_time_since_strike_range = 0.0
		return

	_precog_current_hop = 0
	_precog_start_next_hop()


func _precog_start_next_hop() -> void:
	## Set up the waypoint for the current hop in the path.
	if _precog_current_hop >= _precog_path_edges.size():
		# All hops complete — chase the target normally
		_precog_has_waypoint = false
		_state = State.CHASE
		_time_since_strike_range = 0.0
		return

	var edge: Dictionary = _precog_path_edges[_precog_current_hop]
	_precog_waypoint = edge.get("from_pos", _precog_platforms[_precog_path[_precog_current_hop]]["pos"])
	_precog_waypoint_edge = edge
	_precog_has_waypoint = true
	_state = State.CHASE
	_time_since_strike_range = 0.0

	print("PRECOG: hop %d/%d → walk to (%.0f,%.0f) then leap" % [
		_precog_current_hop + 1, _precog_path_edges.size(),
		_precog_waypoint.x, _precog_waypoint.y])


func _plan_leap_to_surface(from_pos: Vector2, plat: Dictionary) -> Dictionary:
	## Plan a leap to land ON a platform surface.
	## Samples landing points along the platform's top surface.
	var best: Dictionary = {}
	var best_score: float = INF
	var plat_y: float = plat["pos"].y
	var plat_min_x: float = plat["min_x"]
	var plat_max_x: float = plat["max_x"]

	# Sample landing points along the platform surface (slightly above it)
	var landing_y: float = plat_y - 5.0  # Just above the surface
	var sample_count: int = maxi(3, int((plat_max_x - plat_min_x) / PRECOG_GRID_SPACING) + 1)
	sample_count = mini(sample_count, 7)

	for si in range(sample_count):
		var t: float = float(si) / float(sample_count - 1) if sample_count > 1 else 0.5
		# Inset from edges so the body fits on the platform
		var inset: float = LEAP_BODY_RADIUS
		var landing_x: float = lerpf(plat_min_x + inset, plat_max_x - inset, t)
		var arrival := Vector2(landing_x, landing_y)

		if _is_point_in_solid(arrival):
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
			var arc_l: PackedVector2Array = _simulate_arc(from_pos + launch_perp * LEAP_BODY_RADIUS, launch_vel)
			var arc_r: PackedVector2Array = _simulate_arc(from_pos - launch_perp * LEAP_BODY_RADIUS, launch_vel)

			# Check clearance but ignore hits near the destination platform
			# (the arc is SUPPOSED to land there)
			var dest_rect := Rect2(plat_min_x - 10, plat_y - 30, plat_max_x - plat_min_x + 20, 40)
			if not (_check_arc_clear_ignore(arc_c, dest_rect) and _check_arc_clear_ignore(arc_l, dest_rect) and _check_arc_clear_ignore(arc_r, dest_rect)):
				continue

			# Score: prefer landing near platform center
			var center_dist: float = absf(landing_x - plat["pos"].x)
			var time_penalty: float = absf(t_flight - 0.6) * 20.0
			var score: float = center_dist + time_penalty
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


func _plan_leap_from_to(from_pos: Vector2, to_pos: Vector2) -> Dictionary:
	## Run the reverse leap planner between two arbitrary world positions.
	## Returns the best clear result, or empty dict if none found.
	var best: Dictionary = {}
	var best_score: float = INF

	# Sample arrival points: circle around target + direct landing on target surface
	var arrivals: Array[Vector2] = []
	for ai in range(LEAP_ARRIVAL_SAMPLES):
		var angle: float = float(ai) / float(LEAP_ARRIVAL_SAMPLES) * TAU
		arrivals.append(to_pos + Vector2(cos(angle), sin(angle)) * LEAP_STRIKE_REACH)
	# Also try landing directly on the target (important for platform-to-platform)
	arrivals.append(to_pos)
	arrivals.append(to_pos + Vector2(-40, 0))
	arrivals.append(to_pos + Vector2(40, 0))

	for arrival in arrivals:
		if _is_point_in_solid(arrival):
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
			var arc_l: PackedVector2Array = _simulate_arc(from_pos + launch_perp * LEAP_BODY_RADIUS, launch_vel)
			var arc_r: PackedVector2Array = _simulate_arc(from_pos - launch_perp * LEAP_BODY_RADIUS, launch_vel)

			if not (_check_arc_clear(arc_c) and _check_arc_clear(arc_l) and _check_arc_clear(arc_r)):
				continue

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
	## Like _check_arc_clear but ignores hits within ignore_rect (the destination platform).
	var space := get_world_2d().direct_space_state
	if not space:
		return true

	for i in range(arc.size() - 1):
		var from: Vector2 = arc[i]
		var to: Vector2 = arc[i + 1]
		var query := PhysicsRayQueryParameters2D.create(from, to, 1)
		query.exclude = [get_rid()]
		var result: Dictionary = space.intersect_ray(query)
		if not result.is_empty():
			# If the hit is within the destination rect, ignore it
			if ignore_rect.has_point(result["position"]):
				continue
			return false
	return true


func _check_arc_clear(arc: PackedVector2Array) -> bool:
	## Raycast along each segment of the arc. If any hit, path is blocked.
	## Skip only the very last segment (the touchdown).
	var space := get_world_2d().direct_space_state
	if not space:
		return true

	var check_count: int = maxi(1, arc.size() - 3)  # Skip last 2 segments (landing approach)
	for i in range(check_count):
		var from: Vector2 = arc[i]
		var to: Vector2 = arc[i + 1]
		var query := PhysicsRayQueryParameters2D.create(from, to, 1)  # Mask 1 = world
		query.exclude = [get_rid()]
		var result: Dictionary = space.intersect_ray(query)
		if not result.is_empty():
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
			var compressed_foot: Vector2 = hip + Vector2(0, (LEG_UPPER_LEN + LEG_LOWER_LEN) * (1.0 - compress * 0.4))
			_legs[li][2] = _legs[li][2].lerp(compressed_foot, 4.0 * delta)

	# LAUNCH at end of windup
	if _attack_timer >= LEAP_WINDUP_TIME:
		_state = State.ATTACK_LEAP_AIRBORNE
		_attack_timer = 0.0
		_leap_ik_off = true
		# Use the pre-computed launch velocity from planning, adjusted for current target
		if has_meta("_leap_chosen_vel"):
			var planned_vel: Vector2 = get_meta("_leap_chosen_vel")
			# Adjust horizontal direction toward current target position
			if is_instance_valid(_target):
				_leap_target_pos = _target.global_position
				var to_target: Vector2 = _leap_target_pos - global_position
				planned_vel.x = signf(to_target.x) * absf(planned_vel.x)
			velocity = planned_vel
		else:
			# Fallback if no plan data
			var to_target: Vector2 = _leap_target_pos - global_position
			velocity.x = signf(to_target.x) * LEAP_LAUNCH_SPEED * 0.7
			velocity.y = -LEAP_LAUNCH_SPEED * 0.5
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

	# Align spine toward target (body aims like a missile)
	var fly_dir: Vector2 = velocity.normalized() if velocity.length() > 10 else Vector2(_facing, 0)
	var body_aim: Vector2 = fly_dir
	if is_instance_valid(_target):
		var to_target: Vector2 = (_target.global_position - global_position).normalized()
		body_aim = body_aim.lerp(to_target, 0.6)  # Blend flight dir with target aim

	# Position spine along the aim direction
	var spine_center: Vector2 = (_spine[0] + _spine[2]) * 0.5
	_spine[0] = _spine[0].lerp(spine_center + body_aim * SPINE_SEG_LEN, 8.0 * delta)
	_spine[2] = _spine[2].lerp(spine_center - body_aim * SPINE_SEG_LEN, 8.0 * delta)

	# Rear legs extend to full stretch behind (pushing off)
	for li in [2, 3]:
		if _leg_severed[li]:
			continue
		var hip: Vector2 = _legs[li][0]
		var stretch_dir: Vector2 = -body_aim  # Behind the body
		var stretched: Vector2 = hip + stretch_dir * (LEG_UPPER_LEN + LEG_LOWER_LEN - 2)
		_legs[li][2] = _legs[li][2].lerp(stretched, 8.0 * delta)
		# Knee midway along the stretch
		_legs[li][1] = _legs[li][1].lerp(hip + stretch_dir * LEG_UPPER_LEN, 8.0 * delta)

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
			var tail_target: Vector2 = _spine[2] + tail_dir * TAIL_SEG_LEN * (i + 1)
			_tail[i] = _tail[i].lerp(tail_target, 6.0 * delta)

	# Check if we've reached the target
	if is_instance_valid(_target):
		var dist_to_target: float = global_position.distance_to(_target.global_position)
		if dist_to_target < LEAP_STRIKE_REACH:
			_state = State.ATTACK_LEAP_STRIKE
			_attack_timer = 0.0
			_leap_slash_count = 0
			_leap_slash_side = 1
			velocity = Vector2.ZERO
			_tail_whipping = false
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

			# Damage check
			var claw_world: Vector2 = global_position + swipe_end
			_damage_players_in_range(claw_world, 35.0, LEAP_SLASH_DAMAGE)

			# Spawn slash effect
			_spawn_slash_effect(swipe_end)

	# After all 6 slashes: transition to bite+thrash
	if _leap_slash_count >= 6 and _attack_timer > 6 * slash_interval + 0.1:
		_state = State.ATTACK_LEAP_THRASH
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
	_jaw_open = 0.0
	_posture_blend = 0.0
	_tail_whipping = false
	_leap_ik_off = false
	_leap_body_angle = 0.0
	_leap_plan_results.clear()
	_leap_chosen_arc_l.clear()
	_leap_chosen_arc_r.clear()
	_attack_timer = 0.0
	velocity = Vector2.ZERO  # Kill all momentum on landing
	if _body_collision:
		_body_collision.rotation = PI / 2.0
		_body_collision.position = Vector2(0, -10.0)

	# Reset skeleton to standing pose — spine horizontal, feet on the ground
	var body_y: float = -(4.0 + LEG_UPPER_LEN + LEG_LOWER_LEN)
	_spine[0] = Vector2(SPINE_SEG_LEN * _facing, body_y)
	_spine[1] = Vector2(0, body_y)
	_spine[2] = Vector2(-SPINE_SEG_LEN * _facing, body_y)

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
		_state = State.CHASE
		_time_since_strike_range = 0.0


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
	_damage_players_in_range(bite_pos, 30.0, BITE_DAMAGE)


func _check_swipe_hit(leg_idx: int) -> void:
	var claw_pos: Vector2 = global_position + _legs[leg_idx][2]
	_damage_players_in_range(claw_pos, 25.0, SWIPE_DAMAGE)


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
			var pi_val: Variant = node.get("player_index")
			var pi: int = pi_val if pi_val is int else 0
			PlayerManager.damage_player(pi, damage)
			_time_since_strike_range = 0.0  # Reset precog timer on successful hit
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

	# Keep current target if valid
	if is_instance_valid(_target):
		return

	# Find nearest player
	_target = _find_nearest_player()
	if _target:
		var pi_val: Variant = _target.get("player_index")
		_target_player_index = pi_val if pi_val is int else 0


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
	if not _part_health.has(part_name):
		take_damage(amount, source_index)
		return

	_part_health[part_name] -= amount
	if _part_health[part_name] <= 0 and part_name != "body":
		_sever_part(part_name)

	# Also damage main health pool
	take_damage(amount / 2, source_index)


func _sever_part(part_name: String) -> void:
	if part_name.begins_with("leg"):
		var idx: int = int(part_name.replace("leg", ""))
		_leg_severed[idx] = true
		if _hitboxes.has(part_name):
			_hitboxes[part_name].queue_free()
			_hitboxes.erase(part_name)
	elif part_name == "tail":
		_tail_severed = true
		if _hitboxes.has("tail"):
			_hitboxes["tail"].queue_free()
			_hitboxes.erase("tail")
	elif part_name == "head":
		_head_severed = true
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
	_state = State.DEAD
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
	if _hitboxes.has("tail") and not _tail_severed:
		_hitboxes["tail"].position = _tail[2]  # Mid-tail
	for li in range(4):
		var key: String = "leg%d" % li
		if _hitboxes.has(key) and not _leg_severed[li]:
			_hitboxes[key].position = _legs[li][1]  # Knee area


# -- Drawing -------------------------------------------------------------------

func _draw() -> void:
	if _dead and modulate.a < 0.05:
		return
	_draw_body()
	_draw_tail()
	_draw_legs()
	_draw_neck_head()
	if debug_draw_enabled and PlayerHUD._debug_mode and PlayerHUD.debug_selected_enemy == self:
		_draw_debug()


func _draw_body() -> void:
	var body_col := Color(0.3, 0.25, 0.2)
	var body_inner := Color(0.4, 0.33, 0.28)
	for i in range(_spine.size() - 1):
		var t: float = float(i) / float(_spine.size() - 1)
		var thickness: float = lerpf(10.0, 8.0, t)
		draw_line(_spine[i], _spine[i + 1], body_col, thickness, true)
		draw_line(_spine[i], _spine[i + 1], body_inner, thickness * 0.4, true)
	# Body mass circles at each spine point
	for i in range(_spine.size()):
		var r: float = lerpf(12.0, 10.0, float(i) / 2.0)
		draw_circle(_spine[i], r, body_col)


func _draw_tail() -> void:
	if _tail_severed:
		# Draw stump
		var stump: Vector2 = _spine[2] + Vector2(-4 * _facing, 2)
		draw_circle(stump, 4.0, Color(0.5, 0.15, 0.1))
		return

	var tail_col := Color(0.35, 0.28, 0.22)
	var prev: Vector2 = _spine[2]
	for i in range(_tail.size()):
		var t: float = float(i) / float(_tail.size() - 1)
		var thickness: float = lerpf(6.0, 2.0, t)
		draw_line(prev, _tail[i], tail_col, thickness, true)
		prev = _tail[i]
	# Tail tip
	draw_circle(_tail[_tail.size() - 1], 2.5, tail_col)


func _draw_legs() -> void:
	for li in range(4):
		if _leg_severed[li]:
			# Draw stump at hip
			var hip_anchor: Vector2 = _spine[0] if li < 2 else _spine[2]
			draw_circle(hip_anchor + Vector2(0, 6), 3.0, Color(0.5, 0.15, 0.1))
			continue

		var leg: Array = _legs[li]
		var leg_col := Color(0.32, 0.26, 0.2)
		var claw_col := Color(0.25, 0.2, 0.18)

		# Upper leg
		draw_line(leg[0], leg[1], leg_col, 5.0, true)
		# Lower leg
		draw_line(leg[1], leg[2], leg_col, 4.0, true)
		# Joint circles
		draw_circle(leg[0], 4.0, leg_col)
		draw_circle(leg[1], 3.5, leg_col)

		# Foot / claw
		var foot: Vector2 = leg[2]
		var knee: Vector2 = leg[1]
		var foot_dir: Vector2 = (foot - knee).normalized()
		var claw_tip: Vector2 = foot + foot_dir * 6.0
		var perp: Vector2 = Vector2(-foot_dir.y, foot_dir.x)
		draw_polygon(PackedVector2Array([
			foot + perp * 3.0,
			foot - perp * 3.0,
			claw_tip
		]), PackedColorArray([claw_col, claw_col, claw_col]))


func _draw_neck_head() -> void:
	if _head_severed:
		var stump: Vector2 = _spine[0] + Vector2(4 * _facing, -8)
		draw_circle(stump, 4.0, Color(0.5, 0.15, 0.1))
		return

	var neck_col := Color(0.33, 0.27, 0.22)

	# Neck: thick line from spine[0] through neck tip to skull
	draw_line(_neck[0], _neck[1], neck_col, 8.0, true)
	draw_line(_neck[1], _skull, neck_col, 7.0, true)
	draw_circle(_neck[0], 5.0, neck_col)
	draw_circle(_neck[1], 4.5, neck_col)

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
		Vector2(-12, 16),   # Back-top
		Vector2(28, 12),    # Front-top
		Vector2(32, -4),    # Front snout
		Vector2(16, -12),   # Front-bottom
		Vector2(-8, -8),    # Back-bottom
	]
	var skull_pts := PackedVector2Array()
	for pt in skull_local:
		skull_pts.append(_skull + pt.x * head_fwd + pt.y * head_up)
	draw_polygon(skull_pts, PackedColorArray([skull_col, skull_col, skull_col, skull_col, skull_col]))

	# Eye
	var eye_local := Vector2(16, 5)
	var eye_pos: Vector2 = _skull + eye_local.x * head_fwd + eye_local.y * head_up
	draw_circle(eye_pos, 4.0, Color(1.0, 0.2, 0.1))
	draw_circle(eye_pos, 2.0, Color(1.0, 0.5, 0.2))

	# Jaw (opens downward = negative head_up direction)
	var jaw_col := Color(0.3, 0.24, 0.19)
	var jaw_open_fwd: float = _jaw_open * 16.0
	var jaw_open_down: float = _jaw_open * 8.0
	var jaw_local := [
		Vector2(-4, -8),                            # Back hinge
		Vector2(28, -4 - jaw_open_fwd),             # Front tip
		Vector2(20, -14 - jaw_open_fwd),            # Jaw tip far
		Vector2(-4, -12 - jaw_open_down),           # Back bottom
	]
	var jaw_pts := PackedVector2Array()
	for pt in jaw_local:
		jaw_pts.append(_skull + pt.x * head_fwd + pt.y * head_up)
	draw_polygon(jaw_pts, PackedColorArray([jaw_col, jaw_col, jaw_col, jaw_col]))

	# Teeth (hang from upper jaw, pointing in -head_up direction)
	var teeth_col := Color(0.9, 0.85, 0.7)
	for i in range(4):
		var t: float = float(i + 1) / 5.0
		var base_local := Vector2(lerpf(4, 28, t), -4)
		var tip_local := Vector2(base_local.x, base_local.y - 6 - _jaw_open * 5)
		var base_pt: Vector2 = _skull + base_local.x * head_fwd + base_local.y * head_up
		var tip_pt: Vector2 = _skull + tip_local.x * head_fwd + tip_local.y * head_up
		draw_line(base_pt, tip_pt, teeth_col, 2.0)


func _draw_debug() -> void:
	var dbg := Color(0, 1, 0, 0.7)
	var dbg_dim := Color(0, 1, 0, 0.3)
	var red := Color(1, 0.2, 0.2, 0.7)
	var cyan := Color(0, 0.9, 1, 0.7)
	var yellow := Color(1, 1, 0, 0.6)
	var font: Font = ThemeDB.fallback_font

	# -- Origin crosshair (CharacterBody2D position in local space = 0,0) --
	draw_line(Vector2(-20, 0), Vector2(20, 0), red, 1.5)
	draw_line(Vector2(0, -20), Vector2(0, 20), red, 1.5)
	draw_string(font, Vector2(4, -4), "ORIGIN(0,0)", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, red)

	# -- Floor line (raycast from center) --
	var floor_y: float = _raycast_floor(Vector2(0, _spine[1].y))
	draw_line(Vector2(-120, floor_y), Vector2(120, floor_y), yellow, 1.0)
	draw_string(font, Vector2(-120, floor_y - 4), "FLOOR y=%.0f" % floor_y, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, yellow)

	# -- Collision shape bounds (rotates during leap) --
	var col_r: float = 10.0
	var col_half_w: float = SPINE_SEG_LEN + col_r
	var col_center: Vector2 = _body_collision.position if _body_collision else Vector2(0, -10)
	var col_angle: float = _body_collision.rotation if _body_collision else PI / 2.0
	var col_dir: Vector2 = Vector2(cos(col_angle), sin(col_angle))
	var col_perp: Vector2 = Vector2(-col_dir.y, col_dir.x)
	# Draw rotated rectangle as 4 lines
	var c1: Vector2 = col_center + col_dir * col_half_w + col_perp * col_r
	var c2: Vector2 = col_center + col_dir * col_half_w - col_perp * col_r
	var c3: Vector2 = col_center - col_dir * col_half_w - col_perp * col_r
	var c4: Vector2 = col_center - col_dir * col_half_w + col_perp * col_r
	draw_polygon(PackedVector2Array([c1, c2, c3, c4]), PackedColorArray([Color(1, 0, 1, 0.15), Color(1, 0, 1, 0.15), Color(1, 0, 1, 0.15), Color(1, 0, 1, 0.15)]))
	draw_line(c1, c2, Color(1, 0, 1, 0.5), 1.0)
	draw_line(c2, c3, Color(1, 0, 1, 0.5), 1.0)
	draw_line(c3, c4, Color(1, 0, 1, 0.5), 1.0)
	draw_line(c4, c1, Color(1, 0, 1, 0.5), 1.0)
	draw_string(font, col_center + Vector2(-20, -col_r - 4), "COLLISION", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 0, 1, 0.7))

	# -- Spine points --
	for i in range(_spine.size()):
		draw_circle(_spine[i], 3.0, dbg)
		draw_string(font, _spine[i] + Vector2(4, -4), "S%d(%.0f,%.0f)" % [i, _spine[i].x, _spine[i].y], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, dbg)

	# -- Neck + head --
	draw_circle(_neck[0], 2.5, cyan)
	draw_circle(_neck[1], 2.5, cyan)
	draw_line(_neck[0], _neck[1], cyan, 1.0)
	draw_string(font, _neck[1] + Vector2(4, -4), "NECK", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, cyan)
	draw_circle(_skull, 3.0, cyan)
	draw_string(font, _skull + Vector2(4, -10), "SKULL(%.0f,%.0f)" % [_skull.x, _skull.y], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, cyan)
	draw_circle(_jaw, 2.0, cyan)

	# -- Tail points --
	if not _tail_severed:
		for i in range(_tail.size()):
			draw_circle(_tail[i], 2.0, Color(1, 0.6, 0, 0.6))
			if i == 0 or i == _tail.size() - 1:
				draw_string(font, _tail[i] + Vector2(2, -4), "T%d(%.0f,%.0f)" % [i, _tail[i].x, _tail[i].y], HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(1, 0.6, 0))

	# -- Legs: joints, foot targets, home positions --
	var leg_colors := [Color(0, 0.8, 1), Color(0.2, 1, 0.5), Color(1, 0.8, 0.2), Color(1, 0.4, 0.6)]
	for li in range(4):
		if _leg_severed[li]:
			continue
		var col: Color = leg_colors[li]
		var leg: Array = _legs[li]
		# Joint circles
		for j in range(3):
			draw_circle(leg[j], 2.5, col)
		# Leg chain lines
		draw_line(leg[0], leg[1], col * Color(1,1,1,0.5), 1.0)
		draw_line(leg[1], leg[2], col * Color(1,1,1,0.5), 1.0)
		# Labels
		var label: String = ["FL", "FR", "RL", "RR"][li]
		draw_string(font, leg[0] + Vector2(-8, -6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, col)
		# Foot local position
		draw_string(font, leg[2] + Vector2(4, 10), "ft(%.0f,%.0f)" % [leg[2].x, leg[2].y], HORIZONTAL_ALIGNMENT_LEFT, -1, 7, col)
		# World foot position (X marker, converted to local for drawing)
		var fw_local: Vector2 = _foot_world[li] - global_position
		draw_line(fw_local + Vector2(-5, -5), fw_local + Vector2(5, 5), col, 2.0)
		draw_line(fw_local + Vector2(5, -5), fw_local + Vector2(-5, 5), col, 2.0)
		# Ideal foot position (circle)
		var ideal: Vector2 = _ideal_foot_world(li) - global_position
		draw_arc(ideal, 6.0, 0, TAU, 12, col * Color(1,1,1,0.4), 1.0)
		# Planted indicator
		var planted_text: String = "PLANT" if _foot_planted[li] else "STEP"
		draw_string(font, leg[2] + Vector2(4, 20), planted_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, col)

	# -- State info (top-left of creature) --
	var info_pos := _spine[0] + Vector2(-40, -60)
	var state_names := ["PATROL", "CHASE", "BITE", "SWIPE", "TAIL", "LUNGE", "SPRINT", "HOP-UP", "LEAP:PLAN", "LEAP:WIND", "LEAP:AIR", "LEAP:SLASH", "LEAP:THRASH", "PRECOG", "->BIPED", "->QUAD", "HURT", "DEAD"]
	var state_text: String = state_names[_state] if _state < state_names.size() else "?"
	draw_string(font, info_pos, "State: %s" % state_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, dbg)
	draw_string(font, info_pos + Vector2(0, 12), "Facing: %s  Speed: %.0f" % ["R" if _facing > 0 else "L", _move_speed], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, dbg)
	draw_string(font, info_pos + Vector2(0, 22), "HP: %d  Legs: %d" % [health, _count_active_legs()], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, dbg)
	draw_string(font, info_pos + Vector2(0, 32), "Posture: %s  Vel: (%.0f,%.0f)" % ["QUAD" if _posture == Posture.QUADRUPED else "BIPED", velocity.x, velocity.y], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, dbg)
	var waypoint_str: String = "  WPT!" if _precog_has_waypoint else ""
	draw_string(font, info_pos + Vector2(0, 42), "onFloor: %s  wantDir: %.1f  noHit: %.0fs/%.0f%s" % [str(is_on_floor()), _want_direction, _time_since_strike_range, PRECOG_TRIGGER_TIME, waypoint_str], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, dbg)

	# Draw waypoint marker if active
	if _precog_has_waypoint:
		var wpt_local: Vector2 = _precog_waypoint - global_position
		draw_circle(wpt_local, 10.0, Color(1, 0.5, 0, 0.6))
		draw_arc(wpt_local, 14.0, 0, TAU, 16, Color(1, 0.5, 0, 0.8), 2.0)
		draw_string(font, wpt_local + Vector2(16, -4), "WAYPOINT", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 0.5, 0))
		# Line from monster to waypoint
		draw_line(Vector2.ZERO, wpt_local, Color(1, 0.5, 0, 0.4), 1.5)
	draw_string(font, info_pos + Vector2(0, 52), "floorY: %.1f  global: (%.0f,%.0f)" % [floor_y, global_position.x, global_position.y], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, dbg)

	# -- Target indicator: crosshair on the hunted player --
	if is_instance_valid(_target):
		var target_local: Vector2 = _target.global_position - global_position
		var tgt_col := Color(1, 0, 0, 0.8)
		# Crosshair
		draw_line(target_local + Vector2(-16, 0), target_local + Vector2(16, 0), tgt_col, 2.0)
		draw_line(target_local + Vector2(0, -16), target_local + Vector2(0, 16), tgt_col, 2.0)
		draw_arc(target_local, 12.0, 0, TAU, 16, tgt_col, 1.5)
		draw_arc(target_local, 20.0, 0, TAU, 16, Color(1, 0, 0, 0.3), 1.0)
		var target_dist: float = target_local.length()
		draw_string(font, target_local + Vector2(14, -14), "TARGET P%d  dist:%.0f" % [_target_player_index, target_dist], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, tgt_col)
		# Line from skull to target
		draw_line(_skull, target_local, Color(1, 0.3, 0.1, 0.3), 1.0)

	# -- Leap plan visualization --
	if is_instance_valid(_target) and (_state == State.ATTACK_LEAP_PLAN or not _leap_plan_results.is_empty()):
		var tgt_local: Vector2 = _leap_target_pos - global_position

		# Strike zone circle around target
		draw_arc(tgt_local, LEAP_STRIKE_REACH, 0, TAU, 24, Color(1, 0.8, 0, 0.4), 1.5)
		draw_string(font, tgt_local + Vector2(LEAP_STRIKE_REACH + 4, -4), "STRIKE ZONE", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 0.8, 0, 0.5))

		# Arrival point markers (dots on the strike circle)
		for result in _leap_plan_results:
			if result.has("arrival"):
				var arr_local: Vector2 = result["arrival"] - global_position
				var is_clear: bool = result["clear"]
				var arr_col: Color = Color(0, 1, 0, 0.7) if is_clear else Color(1, 0.3, 0, 0.4)
				draw_circle(arr_local, 3.0, arr_col)

	if not _leap_plan_results.is_empty():
		# Summary
		var plan_info: Vector2 = _spine[0] + Vector2(-40, -80)
		var clear_count: int = 0
		for r in _leap_plan_results:
			if r["clear"]:
				clear_count += 1
		var phase_str: String = "P1" if _leap_plan_phase <= 1 else "P1+P2"
		draw_string(font, plan_info, "LEAP %s: %d/%d clear  arrivals:%d" % [phase_str, clear_count, _leap_plan_results.size(), LEAP_ARRIVAL_SAMPLES], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0, 1, 0.5))

		# Draw all arcs (dim)
		for result in _leap_plan_results:
			var is_clear: bool = result["clear"]
			var arc_col: Color = Color(0, 0.7, 0, 0.2) if is_clear else Color(0.7, 0, 0, 0.08)
			var arc_l: PackedVector2Array = result["arc_l"]
			var arc_r: PackedVector2Array = result["arc_r"]
			for i in range(arc_l.size() - 1):
				draw_line(arc_l[i] - global_position, arc_l[i + 1] - global_position, arc_col, 1.0)
			for i in range(arc_r.size() - 1):
				draw_line(arc_r[i] - global_position, arc_r[i + 1] - global_position, arc_col, 1.0)

		# Highlight the chosen path
		if _leap_found_path:
			var launch_local: Vector2 = _leap_launch_pos - global_position
			draw_circle(launch_local, 8.0, Color(0, 1, 0.5, 0.8))
			draw_string(font, launch_local + Vector2(10, -8), "LAUNCH", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0, 1, 0.5))
			var chosen_col := Color(0, 1, 0.3, 0.8)
			for i in range(_leap_chosen_arc_l.size() - 1):
				draw_line(_leap_chosen_arc_l[i] - global_position, _leap_chosen_arc_l[i + 1] - global_position, chosen_col, 2.5)
			for i in range(_leap_chosen_arc_r.size() - 1):
				draw_line(_leap_chosen_arc_r[i] - global_position, _leap_chosen_arc_r[i + 1] - global_position, chosen_col, 2.5)
			# Body width at peak
			if _leap_chosen_arc_l.size() > 5 and _leap_chosen_arc_r.size() > 5:
				var peak_l: Vector2 = _leap_chosen_arc_l[5] - global_position
				var peak_r: Vector2 = _leap_chosen_arc_r[5] - global_position
				draw_line(peak_l, peak_r, Color(0, 1, 0.5, 0.5), 1.0)

	# -- Pre-cognition visualization --
	if _state == State.PRECOGNITION or not _precog_platforms.is_empty():
		var precog_info: Vector2 = _spine[0] + Vector2(-40, -95)
		var phase_labels := ["DETECT", "GRAPH", "PATH", "EXEC"]
		var phase_lbl: String = phase_labels[_precog_phase] if _precog_phase < phase_labels.size() else "?"
		draw_string(font, precog_info, "PRECOG: %s  plats:%d  edges:%d  path:%d  hop:%d/%d" % [
			phase_lbl, _precog_platforms.size(), _precog_edges.size(),
			_precog_path.size(), _precog_current_hop + 1, _precog_path_edges.size()
		], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.8, 0.4, 1))

		# Draw ball landings (dim dots)
		for pos in _precog_ball_lands:
			draw_circle(pos - global_position, 1.5, Color(0.5, 0.3, 0.8, 0.2))

		# Draw platforms (horizontal bars)
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

		# Draw edges (leap connections between platforms)
		for edge in _precog_edges:
			var from_local: Vector2 = edge["from_pos"] - global_position
			var arc_l: PackedVector2Array = edge["arc_l"]
			var arc_r: PackedVector2Array = edge["arc_r"]
			var edge_col := Color(0.3, 0.6, 1, 0.25)
			for ei in range(arc_l.size() - 1):
				draw_line(arc_l[ei] - global_position, arc_l[ei + 1] - global_position, edge_col, 1.0)
			for ei in range(arc_r.size() - 1):
				draw_line(arc_r[ei] - global_position, arc_r[ei + 1] - global_position, edge_col, 1.0)

		# Draw the chosen path (bright, thick)
		if _precog_path.size() >= 2:
			var path_col := Color(1, 0.8, 0, 0.8)
			for pi in range(_precog_path.size() - 1):
				var a_local: Vector2 = _precog_platforms[_precog_path[pi]]["pos"] - global_position
				var b_local: Vector2 = _precog_platforms[_precog_path[pi + 1]]["pos"] - global_position
				draw_line(a_local, b_local, path_col, 2.0)
				draw_circle(a_local, 6.0, path_col)
			draw_circle(_precog_platforms[_precog_path[_precog_path.size() - 1]]["pos"] - global_position, 6.0, path_col)

			# Draw path edge arcs (bright)
			for pe in _precog_path_edges:
				var pe_col := Color(0, 1, 0.3, 0.6)
				var pe_l: PackedVector2Array = pe["arc_l"]
				var pe_r: PackedVector2Array = pe["arc_r"]
				for ei in range(pe_l.size() - 1):
					draw_line(pe_l[ei] - global_position, pe_l[ei + 1] - global_position, pe_col, 2.0)
				for ei in range(pe_r.size() - 1):
					draw_line(pe_r[ei] - global_position, pe_r[ei + 1] - global_position, pe_col, 2.0)
