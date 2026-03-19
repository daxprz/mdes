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
const STEP_DURATION := 0.2     # Seconds to complete a step
const STEP_HEIGHT := 28.0      # How high foot lifts during step
const STEP_OVERSHOOT := 0.25   # Overshoot fraction past target
const FOOT_PUSH_FORCE := 120.0 # Force each planted foot exerts to push body
const FOOT_GRIP := 0.92        # How well planted feet hold ground (velocity damping)

# Speed tiers (desired speed — foot push force is modulated to achieve this)
const SPEED_SLOW := 30.0
const SPEED_MEDIUM := 80.0
const SPEED_FAST := 160.0

# Combat
const BITE_DAMAGE := 25
const SWIPE_DAMAGE := 20
const TAIL_DAMAGE := 18
const LUNGE_DAMAGE := 20
const LUNGE_SPEED := 300.0
const BITE_RANGE := 60.0
const TAIL_RANGE := 90.0
const ATTACK_COOLDOWN := 1.5
const AGGRO_SWITCH_HITS := 3

# Vertical leap
const LEAP_RANGE := 500.0      # Distance at which leap is considered
const LEAP_WINDUP_TIME := 1.2  # Seconds to coil up before launch
const LEAP_LAUNCH_SPEED := 900.0  # Launch velocity magnitude
const LEAP_SLASH_DAMAGE := 15  # Per slash (6 total = 90 max)
const LEAP_BITE_DAMAGE := 30   # Bite + thrash
const LEAP_THRASH_COUNT := 3   # Number of thrash shakes
const LEAP_COOLDOWN := 8.0     # Seconds between leaps

# Health
const MAX_HEALTH := 200
const HEAD_HEALTH := 60
const TAIL_HEALTH := 50
const LEG_HEALTH := 40

# -- Enums ---------------------------------------------------------------------

enum State { PATROL, CHASE, ATTACK_BITE, ATTACK_SWIPE, ATTACK_TAIL,
			 ATTACK_LUNGE, ATTACK_LEAP_WINDUP, ATTACK_LEAP_AIRBORNE,
			 ATTACK_LEAP_STRIKE, ATTACK_LEAP_THRASH,
			 TRANSITION_BIPEDAL, TRANSITION_QUADRUPED, HURT, DEAD }
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
var _leap_phase: float = 0.0    # Sub-phase progress within leap states
var _leap_target_pos: Vector2 = Vector2.ZERO  # Where we're leaping to
var _leap_slash_count: int = 0  # Slashes delivered so far
var _leap_thrash_count: int = 0 # Thrashes delivered so far
var _leap_slash_side: int = 1   # Alternating slash direction
var _slash_effects: Array = []  # Active slash visual effects

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
	var col := CollisionShape2D.new()
	col.shape = shape
	col.rotation = PI / 2.0  # Horizontal
	col.position = Vector2(0, -10.0)  # Centered on body, slightly above floor
	add_child(col)


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

	# First-frame: plant feet at current world position
	if not _initialized:
		_initialized = true
		for li in range(4):
			var hip_local: Vector2 = _legs[li][0]
			_foot_world[li] = global_position + Vector2(hip_local.x, _raycast_floor(hip_local))
			_step_targets[li] = _foot_world[li]
			_step_origins[li] = _foot_world[li]

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
		State.ATTACK_LEAP_WINDUP:
			_do_leap_windup(delta)
		State.ATTACK_LEAP_AIRBORNE:
			_do_leap_airborne(delta)
		State.ATTACK_LEAP_STRIKE:
			_do_leap_strike(delta)
		State.ATTACK_LEAP_THRASH:
			_do_leap_thrash(delta)
		State.TRANSITION_BIPEDAL:
			_do_transition_bipedal(delta)
		State.TRANSITION_QUADRUPED:
			_do_transition_quadruped(delta)

	# FOOT-DRIVEN LOCOMOTION (skip during leap)
	var in_leap: bool = (_state == State.ATTACK_LEAP_WINDUP or _state == State.ATTACK_LEAP_AIRBORNE
		or _state == State.ATTACK_LEAP_STRIKE or _state == State.ATTACK_LEAP_THRASH)
	if not in_leap:
		_update_foot_push(delta)

	move_and_slide()

	# Update skeleton after body has moved
	_update_spine()
	_update_gait(delta)
	_solve_pose(delta)
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

	var to_target: Vector2 = _target.global_position - global_position
	_facing = signf(to_target.x) if absf(to_target.x) > 5.0 else _facing
	_want_direction = _facing
	var dist: float = absf(to_target.x)

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

	# Tail whip if target is behind
	if target_behind and dist < TAIL_RANGE and _posture == Posture.QUADRUPED and not _tail_severed:
		_start_attack(State.ATTACK_TAIL)
		return

	# VERTICAL LEAP at leap range (priority over lunge)
	if dist > 80.0 and dist < LEAP_RANGE and _leap_cooldown <= 0.0 and _count_active_legs() >= 2:
		_start_leap()
		return

	# Lunge at medium distance
	if dist > 80.0 and dist < 200.0 and randf() < 0.3:
		_start_attack(State.ATTACK_LUNGE)
		return

	# Close range
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

func _start_leap() -> void:
	_state = State.ATTACK_LEAP_WINDUP
	_attack_timer = 0.0
	_attack_cooldown = ATTACK_COOLDOWN
	_leap_cooldown = LEAP_COOLDOWN
	_leap_phase = 0.0
	_leap_slash_count = 0
	_leap_thrash_count = 0
	_leap_slash_side = 1
	_leap_ik_off = false  # IK still on during early windup for rear legs
	velocity.x = 0
	if is_instance_valid(_target):
		_leap_target_pos = _target.global_position


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
		_leap_ik_off = true  # All legs positioned manually from here
		# Update target one last time
		if is_instance_valid(_target):
			_leap_target_pos = _target.global_position
		# Launch: strong parabolic arc aimed at target
		var to_target: Vector2 = _leap_target_pos - global_position
		var dist: float = to_target.length()
		# Calculate launch angle for a nice arc — more horizontal for close, more vertical for far
		var arc_ratio: float = clampf(dist / 400.0, 0.3, 0.8)
		velocity.x = signf(to_target.x) * LEAP_LAUNCH_SPEED * (1.0 - arc_ratio * 0.5)
		velocity.y = -LEAP_LAUNCH_SPEED * arc_ratio
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
		if dist_to_target < 60.0:
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
	_leap_ik_off = false  # Re-enable IK
	_state = State.CHASE
	_attack_timer = 0.0
	# Re-plant feet at current positions
	for li in range(4):
		if not _leg_severed[li]:
			_foot_planted[li] = true
			_foot_world[li] = global_position + _legs[li][2]


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
			var pi: int = node.get("player_index")
			PlayerManager.damage_player(pi, damage)
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
		_target_player_index = _target.get("player_index")


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
	if PlayerHUD._debug_mode and PlayerHUD.debug_selected_enemy == self:
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

	# -- Collision shape bounds (horizontal capsule) --
	var col_r: float = 10.0
	var col_w: float = SPINE_SEG_LEN * 2.0 + col_r * 2.0
	var col_center := Vector2(0, -10.0)
	draw_rect(Rect2(col_center.x - col_w / 2.0, col_center.y - col_r, col_w, col_r * 2.0), Color(1, 0, 1, 0.15))
	draw_rect(Rect2(col_center.x - col_w / 2.0, col_center.y - col_r, col_w, col_r * 2.0), Color(1, 0, 1, 0.5), false, 1.0)
	draw_string(font, col_center + Vector2(-col_w / 2.0, -col_r - 4), "COLLISION", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 0, 1, 0.7))

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
	var state_names := ["PATROL", "CHASE", "BITE", "SWIPE", "TAIL", "LUNGE", "LEAP:WIND", "LEAP:AIR", "LEAP:SLASH", "LEAP:THRASH", "->BIPED", "->QUAD", "HURT", "DEAD"]
	var state_text: String = state_names[_state] if _state < state_names.size() else "?"
	draw_string(font, info_pos, "State: %s" % state_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, dbg)
	draw_string(font, info_pos + Vector2(0, 12), "Facing: %s  Speed: %.0f" % ["R" if _facing > 0 else "L", _move_speed], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, dbg)
	draw_string(font, info_pos + Vector2(0, 22), "HP: %d  Legs: %d" % [health, _count_active_legs()], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, dbg)
	draw_string(font, info_pos + Vector2(0, 32), "Posture: %s  Vel: (%.0f,%.0f)" % ["QUAD" if _posture == Posture.QUADRUPED else "BIPED", velocity.x, velocity.y], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, dbg)
	draw_string(font, info_pos + Vector2(0, 42), "onFloor: %s  wantDir: %.1f" % [str(is_on_floor()), _want_direction], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, dbg)
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
