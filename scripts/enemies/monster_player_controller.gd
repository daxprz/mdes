extends "res://scripts/enemies/monster_controller.gd"

## Player controller for the quadruped monster.
## Maps gamepad/keyboard input to monster intent variables and attack requests.
## The monster's state machine validates transitions — this just expresses intent.

var device_id: int = -1  # -1 = keyboard, 0+ = controller
var player_index: int = 0

# Input state tracking (for controllers — keyboard uses Input directly)
var _controller_actions: Dictionary = {}
var _controller_just_pressed: Dictionary = {}

# Attack input buffering — allows pressing attack slightly before cooldown ends
var _attack_buffer: String = ""  # "bite", "swipe", "tail", "lunge"
var _attack_buffer_timer: float = 0.0
const ATTACK_BUFFER_WINDOW := 0.15

# Jump intent
var _jump_requested: bool = false

# Leap aiming (hold L1 to charge, stick to aim, release to leap)
var _leap_charging: bool = false
var _leap_charge_time: float = 0.0
var _leap_aim_dir: Vector2 = Vector2.RIGHT  # Aimed direction
const LEAP_MIN_CHARGE := 0.15  # Minimum hold time before leap fires
const LEAP_MAX_CHARGE := 1.5   # Max charge time (caps power)
const LEAP_BASE_SPEED := 400.0
const LEAP_MAX_SPEED := 900.0

# Air slash cooldown (R1 mid-flight)
var _air_slash_cooldown: float = 0.0
const AIR_SLASH_INTERVAL := 0.25  # Min time between air slashes


func on_attach(monster: CharacterBody2D) -> void:
	# Start in a neutral state (not patrol/chase)
	monster._standdown = false
	monster._asleep = false
	monster._change_state(monster.State.PATROL)
	# Disable AI target acquisition
	monster._target = null
	# Set faction to "players" — AI monsters will target us, we target them
	monster.set_meta("faction", "players")
	monster.set_meta("player_controlled", true)
	monster.add_to_group("players")  # So other systems (camera, HUD) can find us


func update(monster: CharacterBody2D, delta: float) -> void:
	_attack_buffer_timer -= delta

	# -- Movement --
	var move_x: float = _get_axis("move_left", "move_right")
	var move_y: float = _get_axis("move_up", "move_down")

	monster._want_direction = move_x
	if absf(move_x) > 0.1:
		monster._facing_target = signf(move_x)

	# Speed tiers based on stick magnitude
	var stick_mag: float = absf(move_x)
	if stick_mag < 0.1:
		monster._target_move_speed = 0.0
	elif stick_mag < 0.5:
		monster._target_move_speed = monster._effective_speed(monster.cfg("speed_slow", monster.SPEED_SLOW))
	elif stick_mag < 0.85:
		monster._target_move_speed = monster._effective_speed(monster.cfg("speed_medium", monster.SPEED_MEDIUM))
	else:
		monster._target_move_speed = monster._effective_speed(monster.cfg("speed_fast", monster.SPEED_FAST))

	# -- Right thumbstick → head aim --
	var right_stick := Vector2.ZERO
	if device_id >= 0:
		right_stick = Vector2(
			Input.get_joy_axis(device_id, JOY_AXIS_RIGHT_X),
			Input.get_joy_axis(device_id, JOY_AXIS_RIGHT_Y)
		)
	if right_stick.length() > 0.2:
		# Aim head in the stick direction, projected out from the monster
		var aim_range: float = monster.sc(200.0)
		monster._head_look_pos = monster.global_position + right_stick.normalized() * aim_range
	else:
		monster._head_look_pos = Vector2.ZERO  # Disable override — head returns to neutral

	# -- Jump (not in ball mode — Cross in ball triggers ball-leap below) --
	if monster._state != monster.State.BALL:
		if _is_just_pressed("jump"):
			if monster.is_on_floor():
				_jump_requested = true

		if _jump_requested and monster.is_on_floor():
			monster.velocity.y = -monster.sc(350.0)
			_jump_requested = false

	# -- Leap (hold L1 to charge/aim, release to fire) --
	# Press L1: begin charging. Aim with left stick (or right stick).
	# Release L1: fire the leap along the aimed arc.
	if _is_just_pressed("grapple"):
		if not _leap_charging and monster._leap_cooldown <= 0.0:
			var can_leap: bool = monster._state in [
				monster.State.PATROL, monster.State.CHASE, monster.State.STANDDOWN
			]
			if can_leap:
				_leap_charging = true
				_leap_charge_time = 0.0
				_leap_aim_dir = Vector2(monster._facing, -0.5).normalized()

	if _leap_charging:
		_leap_charge_time += delta
		# Update aim direction: right stick priority, then left stick
		var aim_input := Vector2(move_x, move_y)
		if right_stick.length() > 0.2:
			aim_input = right_stick
		if aim_input.length() > 0.2:
			_leap_aim_dir = aim_input.normalized()

		# Slow movement while charging (creature braces to leap)
		monster._target_move_speed = 0.0
		monster._want_direction = 0.0

		# Compute and display the arc preview
		var charge_t: float = clampf(_leap_charge_time / LEAP_MAX_CHARGE, 0.0, 1.0)
		var speed: float = lerpf(LEAP_BASE_SPEED, LEAP_MAX_SPEED, charge_t) * monster.creature_scale
		_update_leap_preview(monster, _leap_aim_dir * speed)

		# Release check
		if not _is_pressed("grapple"):
			_leap_charging = false
			monster._leap_preview_arc.clear()
			if _leap_charge_time >= LEAP_MIN_CHARGE:
				# Fire the leap!
				monster.velocity = _leap_aim_dir * speed
				monster._leap_target_pos = monster.global_position + _leap_aim_dir * 300.0
				monster._leap_launch_pos = monster.global_position
				monster._leap_phase = 0.0
				monster._leap_ik_off = true
				monster._leap_body_angle = 0.0
				monster._leap_slash_count = 0
				monster._leap_thrash_count = 0
				monster._leap_cooldown = monster.cfg("leap_cooldown", monster.LEAP_COOLDOWN) * 0.5
				monster._change_state(monster.State.ATTACK_LEAP_AIRBORNE)
				DebugOverlay.log("monster/player_input", monster, "LEAP FIRE: charge=%.2f speed=%.0f dir=(%.2f,%.2f)", [_leap_charge_time, speed, _leap_aim_dir.x, _leap_aim_dir.y])
			else:
				DebugOverlay.log("monster/player_input", monster, "LEAP CANCEL: charge=%.2f < min=%.2f", [_leap_charge_time, LEAP_MIN_CHARGE])
	else:
		# Clear preview when not charging
		if not monster._leap_preview_arc.is_empty():
			monster._leap_preview_arc.clear()

	# -- Ball mode (Circle/O) --
	if _is_just_pressed("interact"):
		if monster._state == monster.State.BALL:
			# Circle while in ball: unfurl back to walking
			monster._change_state(monster.State.PATROL)
			DebugOverlay.log("monster/player_input", monster, "BALL MODE: OFF (unfurl)")
		else:
			var can_ball: bool = monster._state in [
				monster.State.PATROL, monster.State.CHASE, monster.State.STANDDOWN
			]
			if can_ball:
				monster._change_state(monster.State.BALL)
				DebugOverlay.log("monster/player_input", monster, "BALL MODE: ON")

	# -- Cross/A while in ball: quick uncurl → mid-power leap --
	if _is_just_pressed("jump") and monster._state == monster.State.BALL:
		# Uncurl and immediately launch a mid-power leap in the facing direction
		var leap_dir := Vector2(monster._facing, -0.6).normalized()
		if right_stick.length() > 0.2:
			leap_dir = right_stick.normalized()
		elif absf(move_x) > 0.2:
			leap_dir = Vector2(move_x, -0.5).normalized()
		var leap_speed: float = lerpf(LEAP_BASE_SPEED, LEAP_MAX_SPEED, 0.5) * monster.creature_scale
		monster._change_state(monster.State.PATROL)  # Triggers _exit_ball
		monster.velocity = leap_dir * leap_speed
		monster._leap_target_pos = monster.global_position + leap_dir * 300.0
		monster._leap_launch_pos = monster.global_position
		monster._leap_phase = 0.0
		monster._leap_ik_off = true
		monster._leap_body_angle = 0.0
		monster._leap_slash_count = 0
		monster._leap_thrash_count = 0
		monster._leap_cooldown = monster.cfg("leap_cooldown", monster.LEAP_COOLDOWN) * 0.3
		monster._change_state(monster.State.ATTACK_LEAP_AIRBORNE)
		DebugOverlay.log("monster/player_input", monster, "BALL LEAP: speed=%.0f dir=(%.2f,%.2f)", [leap_speed, leap_dir.x, leap_dir.y])

	# -- R1 mid-flight: arm slash --
	_air_slash_cooldown -= delta
	if monster._state == monster.State.ATTACK_LEAP_AIRBORNE:
		var r1_pressed: bool = false
		if device_id >= 0:
			r1_pressed = Input.is_joy_button_pressed(device_id, JOY_BUTTON_RIGHT_SHOULDER)
		else:
			r1_pressed = Input.is_key_pressed(KEY_SHIFT)
		if r1_pressed and monster._leap_slash_count < 3 and _air_slash_cooldown <= 0.0:
			var slash_leg: int = 0 if not monster._leg_severed[0] else 1
			monster._check_swipe_hit(slash_leg)
			monster._spawn_slash_effect(monster._skull)
			monster._leap_slash_count += 1
			_air_slash_cooldown = AIR_SLASH_INTERVAL
			DebugOverlay.log("monster/player_input", monster, "AIR SLASH #%d", [monster._leap_slash_count])

	# -- Attacks (not in ball mode) --
	# Square/X = bite, Triangle/Y = swipe, L3 = tail whip
	# L1 = leap (hold-aim-release)
	if monster._state != monster.State.BALL:
		if _is_just_pressed("attack"):
			_attack_buffer = "bite"
			_attack_buffer_timer = ATTACK_BUFFER_WINDOW
		elif _is_just_pressed("special"):
			_attack_buffer = "swipe"
			_attack_buffer_timer = ATTACK_BUFFER_WINDOW
		elif _is_just_pressed("block"):
			_attack_buffer = "tail"
			_attack_buffer_timer = ATTACK_BUFFER_WINDOW

	# Process attack buffer — attempt the attack if the monster can accept it
	if _attack_buffer_timer > 0 and _attack_buffer != "":
		var accepted: bool = _try_attack(monster, _attack_buffer)
		if accepted:
			DebugOverlay.log("monster/player_input", monster, "ATTACK: %s accepted (state→%s)", [_attack_buffer, monster.State.keys()[monster._state]])
			_attack_buffer = ""
			_attack_buffer_timer = 0.0

	# -- Handle active attack states (the monster's _do_* functions still run) --
	# For attack states, delegate to the monster's existing animation/hit logic
	_update_active_state(monster, delta)

	# Clear just-pressed state at end of frame
	_controller_just_pressed.clear()


func _update_active_state(monster: CharacterBody2D, delta: float) -> void:
	## Run the monster's built-in state logic for attack/transition states.
	## Movement states (PATROL/CHASE) are handled by our input above.
	match monster._state:
		monster.State.PATROL, monster.State.CHASE, monster.State.STANDDOWN:
			pass  # Handled by movement input above
		monster.State.BALL:
			pass  # Ball physics handled by _do_ball in _physics_process
		monster.State.ATTACK_BITE:
			monster._do_bite(delta)
		monster.State.ATTACK_SWIPE:
			monster._do_swipe(delta)
		monster.State.ATTACK_TAIL:
			monster._do_tail_whip(delta)
		monster.State.ATTACK_LUNGE:
			monster._do_lunge(delta)
		monster.State.ATTACK_SPRINT_SLASH:
			monster._do_sprint_slash(delta)
		monster.State.ATTACK_HOP_UP:
			monster._do_hop_up(delta)
		monster.State.ATTACK_GRAB:
			monster._do_grab(delta)
		monster.State.ATTACK_LEAP_PLAN:
			monster._do_leap_plan(delta)
		monster.State.ATTACK_LEAP_WINDUP:
			monster._do_leap_windup(delta)
		monster.State.ATTACK_LEAP_AIRBORNE:
			monster._do_leap_airborne(delta)
		monster.State.ATTACK_LEAP_STRIKE:
			monster._do_leap_strike(delta)
		monster.State.ATTACK_LEAP_THRASH:
			monster._do_leap_thrash(delta)
		monster.State.TRANSITION_BIPEDAL:
			monster._do_transition_bipedal(delta)
		monster.State.TRANSITION_QUADRUPED:
			monster._do_transition_quadruped(delta)
		monster.State.CHAIN_DAZE:
			monster._do_chain_daze(delta)
		monster.State.HURT:
			pass  # Hurt state runs its own timer
		monster.State.DEAD:
			pass


func _try_attack(monster: CharacterBody2D, attack_name: String) -> bool:
	## Request an attack transition. Returns true if accepted.
	# Can't attack during other attacks, leaps, transitions, or hurt
	if _leap_charging:
		return false
	var can_attack: bool = monster._state in [
		monster.State.PATROL, monster.State.CHASE, monster.State.STANDDOWN
	]
	if not can_attack:
		return false
	if monster._attack_cooldown > 0.0:
		return false

	match attack_name:
		"bite":
			monster._attack_timer = 0.0
			monster._change_state(monster.State.ATTACK_BITE)
			monster._attack_cooldown = monster.cfg("attack_cooldown", monster.ATTACK_COOLDOWN)
			return true
		"swipe":
			monster._attack_timer = 0.0
			monster._change_state(monster.State.ATTACK_SWIPE)
			monster._attack_cooldown = monster.cfg("attack_cooldown", monster.ATTACK_COOLDOWN)
			return true
		"tail":
			if monster._tail_severed:
				return false
			monster._attack_timer = 0.0
			monster._change_state(monster.State.ATTACK_TAIL)
			monster._attack_cooldown = monster.cfg("attack_cooldown", monster.ATTACK_COOLDOWN)
			return true
		"lunge":
			monster._attack_timer = 0.0
			monster._change_state(monster.State.ATTACK_LUNGE)
			monster._attack_cooldown = monster.cfg("attack_cooldown", monster.ATTACK_COOLDOWN)
			return true
	return false


func _update_leap_preview(monster: CharacterBody2D, launch_vel: Vector2) -> void:
	## Simulate a parabolic arc and store points in monster._leap_preview_arc (local space).
	var gravity: float = monster.cfg("gravity", monster.GRAVITY)
	var dt: float = 0.02  # Simulation time step
	var max_steps: int = 80  # ~1.6 seconds of flight
	var pos := Vector2.ZERO  # Start at monster origin (local space)
	var vel := launch_vel

	var arc := PackedVector2Array()
	arc.append(pos)

	for _i in range(max_steps):
		vel.y += gravity * dt
		pos += vel * dt
		arc.append(pos)
		# Stop if we've gone below the launch point by a lot (hit the ground conceptually)
		if pos.y > 200.0 * monster.creature_scale:
			break

	monster._leap_preview_arc = arc
	monster.queue_redraw()


func is_player() -> bool:
	return true


# -- Input helpers (mirrors player_side.gd pattern) --

func _get_axis(negative_action: String, positive_action: String) -> float:
	if device_id == -1:
		# Keyboard: digital on/off
		var val: float = 0.0
		if Input.is_action_pressed(negative_action):
			val -= 1.0
		if Input.is_action_pressed(positive_action):
			val += 1.0
		return val
	# Controller: read analog stick directly for smooth speed control
	if negative_action == "move_left" and positive_action == "move_right":
		var raw: float = Input.get_joy_axis(device_id, JOY_AXIS_LEFT_X)
		if absf(raw) > 0.1:
			return raw
		# Fall back to D-pad digital input
		var neg: float = 1.0 if _controller_actions.get(negative_action, false) else 0.0
		var pos: float = 1.0 if _controller_actions.get(positive_action, false) else 0.0
		return pos - neg
	elif negative_action == "move_up" and positive_action == "move_down":
		var raw: float = Input.get_joy_axis(device_id, JOY_AXIS_LEFT_Y)
		if absf(raw) > 0.1:
			return raw
		var neg: float = 1.0 if _controller_actions.get(negative_action, false) else 0.0
		var pos: float = 1.0 if _controller_actions.get(positive_action, false) else 0.0
		return pos - neg
	# Generic fallback
	var neg: float = 1.0 if _controller_actions.get(negative_action, false) else 0.0
	var pos: float = 1.0 if _controller_actions.get(positive_action, false) else 0.0
	return pos - neg


func _is_pressed(action: String) -> bool:
	if device_id == -1:
		return Input.is_action_pressed(action)
	return _controller_actions.get(action, false)


func _is_just_pressed(action: String) -> bool:
	if device_id == -1:
		return Input.is_action_just_pressed(action)
	return _controller_just_pressed.get(action, false)


func handle_input(event: InputEvent) -> void:
	## Call from the monster's _input() to track controller button state.
	if device_id == -1:
		return
	if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	if event.device != device_id:
		return

	for action in ["move_left", "move_right", "move_up", "move_down",
					"jump", "attack", "special", "block", "interact", "grapple"]:
		if event.is_action_pressed(action):
			_controller_actions[action] = true
			_controller_just_pressed[action] = true
		elif event.is_action_released(action):
			_controller_actions[action] = false
