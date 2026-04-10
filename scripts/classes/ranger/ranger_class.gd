extends "res://scripts/classes/class_component.gd"

## Ranger class — grapple hook, tether, crossbow, aimed archer shot.
## Extracted from player_side.gd. References the player via p (ctx.body).

var p: Object = null

func inject_context(c: Variant) -> void:
	ctx = c
	p = c.body if c else null

# Enums
enum GrappleState { IDLE, WINDUP, THROWN, CONNECTED, SWINGING, TUG, RETRACTING,
	TETHER_WINDUP, TETHER_THROWN, SLIDE, SLIDE_FREE }

# Constants
const GRAPPLE_SWING_RADIUS := 40.0
const GRAPPLE_BASE_ANGULAR_VEL := 14.0
const GRAPPLE_ANGULAR_ACCEL := 12.0
const GRAPPLE_MAX_ANGULAR_VEL := 35.0
const GRAPPLE_MIN_HOLD := 0.3
const GRAPPLE_BASE_THROW_SPEED := 4000.0
const GRAPPLE_THROW_SPEED_PER_SEC := 3000.0
const GRAPPLE_MAX_THROW_SPEED := 10000.0
const GRAPPLE_HOOK_GRAVITY := 400.0
const GRAPPLE_HOOK_DRAG := 0.98
const GRAPPLE_ROPE_SEGMENTS := 20
const GRAPPLE_ROPE_SEGMENT_LEN := 12.0
const GRAPPLE_LAUNCH_SPEED_RATIO := 0.75
const GRAPPLE_PENDULUM_GRAVITY := 600.0
const GRAPPLE_SWING_DAMPING := 0.02
const GRAPPLE_INPUT_BOOST := 1.5
const GRAPPLE_INPUT_BRAKE := 1.0
const GRAPPLE_ROPE_ADJUST_SPEED := 80.0
const GRAPPLE_MIN_ROPE_LEN := 30.0
const GRAPPLE_MAX_ROPE_LEN := 900.0
const GRAPPLE_TUG_FORCE := 8000.0
const GRAPPLE_TUG_DURATION := 0.15
const GRAPPLE_HOOK_DAMAGE := 0
const GRAPPLE_TUG_DAMAGE := 0
const RANGER_MAX_ARROWS := 10
const RANGER_RELOAD_TIME := 1.5
const ARCHER_AIM_RETICLE_SPEED := 400.0
const ARCHER_ARROW_MIN_SPEED := 300.0
const ARCHER_ARROW_MAX_SPEED := 1800.0
const ARCHER_ARROW_SPEED_RATE := 1200.0
const ARCHER_ARROW_GRAVITY := 500.0
const ARCHER_AIM_LOCK_COOLDOWN := 0.25
const ARCHER_AIM_MAX_RANGE := 600.0

# Swing-Slide-Jump constants
const SLIDE_IMPACT_RADIUS := 48.0        # Detection window (~1 player height)
const SLIDE_BOOST := 50.0                # Added to surface-parallel speed on slide start
const SLIDE_FRICTION := 0.985            # Per-frame friction (very low = fast slides)
const SLIDE_MIN_SPEED := 20.0            # Below this, slide ends
const SLIDE_GRAVITY := 600.0             # Gravity component along slopes
const SLIDE_PARTICLE_RATE := 30.0        # Dust puffs per second
const SLIDE_CHARGE_TIME := 2.0           # Seconds to reach full charge

# Run/Dash constants
const RUN_SPEED_MULT := 2.0
const RUN_FOOTSTEP_RATE := 8.0           # Puffs per second while running
const DASH_SPEED_MULT := 4.0
const DASH_DURATION := 1.0
const DASH_COOLDOWN := 5.0
const DASH_TRAIL_MAX_AGE := 0.4          # Trail points live this long (seconds)

# Slide state
var _slide_charge_mod: Variant = null     # RampModifierProvider for charge (pushed on slide start)
var _slide_on_surface: bool = true        # True while collision box contacts terrain
var _slide_max_extent: Vector2 = Vector2.ZERO  # Furthest point reached (debug)

# Run state
var _is_running: bool = false
var _run_airborne: bool = false           # True = jumped while running, maintain speed in air
var _run_footstep_accum: float = 0.0
var _smoothed_deflection: float = 0.0    # Low-pass filtered stick deflection (prevents jitter)
var _smoothed_h: float = 0.0             # Smoothed signed horizontal input (filters sign-flip jitter)

# Stick visualizer state
var _stick_trail: Array = []             # [{x, y, age}] raw stick positions for heat trail
const STICK_TRAIL_MAX_AGE := 1.5         # Trail points live this long
const STICK_VIZ_SIZE := 40.0             # Half-size of the visualizer square (pixels)

# Dash state
var _is_dashing: bool = false
var _dash_timer: float = 0.0
var _dash_cooldown_timer: float = 0.0
var _dash_direction: float = 0.0         # -1 or 1 (locked at start)
var _dash_jumped: bool = false            # True if player jumped during dash
var _r1_was_pressed: bool = false         # For just-pressed edge detection
var _dash_trail: Array = []              # [{pos: Vector2, age: float}]
var _dash_sparkles: Array = []           # [{pos, vel, age, max_age, yellow: bool}]
var _run_particles: Array = []           # [{pos, vel, age, max_age, radius}]


func on_class_enter() -> void:
	pass


func tick(delta: float) -> void:
	_handle_ranger_reload(delta)
	_handle_archer_aim(delta)
	_handle_ranger_run(delta)
	_handle_ranger_dash(delta)


func perform_attack(_intent: Dictionary) -> void:
	_attack_ranged()


func perform_special(_intent: Dictionary) -> void:
	p._special_grappling_hook()


func _attack_ranged() -> void:
	# Square: fire crossbow
	if p._ranger_arrows <= 0:
		p._spawn_fail_flash()
		AudioManager.play("reload_click", -4.0)
		return
	p._ranger_arrows -= 1
	AudioManager.play("crossbow_shoot", 0.0, 0.8)
	p._attack_cooldown = 0.6
	var scaled_dmg: int = int(60 * PlayerManager.get_skill_bonus(p.player_index, "attack"))
	p._spawn_projectile(scaled_dmg, 400.0, "crossbow_bolt")
	PlayerManager.add_skill_xp(p.player_index, "attack", 2)




# -- Ranger Fire Crossbow (Triangle) -------------------------------------------

func _ranger_fire_crossbow() -> void:
	if p._ranger_arrows <= 0:
		p._spawn_fail_flash()
		AudioManager.play("reload_click", -4.0)
		return

	p._ranger_arrows -= 1
	AudioManager.play("crossbow_shoot", 0.0, 0.8)
	var scaled_dmg: int = int(60 * PlayerManager.get_skill_bonus(p.player_index, "attack"))
	p._spawn_projectile(scaled_dmg, 400.0, "crossbow_bolt")
	PlayerManager.add_skill_xp(p.player_index, "attack", 2)


# -- Controller Rumble ---------------------------------------------------------



# -- Ranger Grapple (Circle) ---------------------------------------------------

func _handle_ranger_grapple() -> void:
	if p.character_class != PlayerManager.CharacterClass.RANGED:
		return

	# L1 (left bumper): grapple windup/throw AND tether second hook
	if p._is_device_action_just_pressed("grapple"):
		if p._grapple_state == GrappleState.IDLE:
			# First L1: start grapple windup
			p._grapple_state = GrappleState.WINDUP
			p._grapple_hold_time = 0.0
			p._grapple_angle = 0.0
			p._grapple_angular_vel = GRAPPLE_BASE_ANGULAR_VEL
			p._grapple_locked_aim = Vector2(1.0 if p._facing_right else -1.0, 0.0)
			p._grapple_pulling = false
		elif p._grapple_state in [GrappleState.SWINGING, GrappleState.CONNECTED]:
			if p._grapple_anchor_entity and is_instance_valid(p._grapple_anchor_entity):
				# Connected to enemy: tug
				_grapple_tug()
			elif p._active_tethers.size() < 3:
				# Second L1 while connected to wall: start tether second hook
				_tether_begin_second_hook()
			else:
				# All 5 tether slots full: disconnect instead
				_grapple_release()

	# R1 (right bumper): pull to anchor / disconnect
	var r1_pressed: bool = false
	if p.device_id >= 0:
		r1_pressed = Input.is_joy_button_pressed(p.device_id, JOY_BUTTON_RIGHT_SHOULDER)
	else:
		r1_pressed = Input.is_key_pressed(KEY_SHIFT)
	if r1_pressed and p._grapple_state in [GrappleState.SWINGING, GrappleState.CONNECTED]:
		if not p._grapple_pulling:
			_grapple_pull_to_anchor()

	# L1 release during tether windup: throw second hook
	if p._grapple_state == GrappleState.TETHER_WINDUP:
		if not p._is_device_action_pressed("grapple"):
			if p._tether_hold_time >= GRAPPLE_MIN_HOLD:
				_tether_throw_second_hook()
			else:
				# Cancelled — go back to swinging
				p._grapple_state = GrappleState.SWINGING

	# Clean up freed tethers
	var ti: int = p._active_tethers.size() - 1
	while ti >= 0:
		if not is_instance_valid(p._active_tethers[ti]):
			p._active_tethers.remove_at(ti)
		ti -= 1

	if p._grapple_state == GrappleState.IDLE:
		return

	var delta: float = get_process_delta_time()

	# Trace grapple state each frame (verbose — uncomment when debugging slide)
	#DebugOverlay.log("player/slide", p, "GRAPPLE TICK: state=%d pos=(%.0f,%.0f) vel=(%.0f,%.0f) on_floor=%s" % [
	#	p._grapple_state, p.global_position.x, p.global_position.y, p.velocity.x, p.velocity.y, str(p.is_on_floor())])

	match p._grapple_state:
		GrappleState.WINDUP:
			_grapple_tick_windup(delta)
		GrappleState.THROWN:
			_grapple_tick_thrown(delta)
		GrappleState.CONNECTED:
			_grapple_tick_connected(delta)
		GrappleState.SWINGING:
			_grapple_tick_swinging(delta)
		GrappleState.RETRACTING:
			_grapple_tick_retracting(delta)
		GrappleState.TETHER_WINDUP:
			_grapple_tick_swinging(delta)  # Player keeps swinging
			_tether_tick_windup(delta)
		GrappleState.TETHER_THROWN:
			_grapple_tick_swinging(delta)  # Player keeps swinging
			_tether_tick_thrown(delta)
		GrappleState.SLIDE, GrappleState.SLIDE_FREE:
			# Check Circle (interact) release BEFORE tick — so release fires before _slide_end
			if not p._is_device_action_pressed("interact"):
				_slide_release()
			else:
				_slide_tick(delta)

	# Jump: RELEASE rope. If taut → add jump boost. If slack → just detach.
	if p._grapple_state in [GrappleState.SWINGING, GrappleState.CONNECTED,
						   GrappleState.TETHER_WINDUP, GrappleState.TETHER_THROWN]:
		if p._is_device_action_just_pressed("jump"):
			var dist: float = p.global_position.distance_to(p._grapple_anchor)
			var is_taut: bool = dist >= p._grapple_rope_len * 0.95
			if is_taut:
				# Taut: release with jump boost added to current velocity
				var jump_boost: float = p.cfg("jump_velocity", p.JUMP_VELOCITY)  # Negative = upward
				p.velocity.y += jump_boost
				DebugOverlay.log("player/slide", p, "JUMP RELEASE: TAUT — boost_y=%.0f vel=(%.0f,%.0f)" % [
					jump_boost, p.velocity.x, p.velocity.y])
			else:
				# Slack: release without boost, keep current velocity
				DebugOverlay.log("player/slide", p, "JUMP RELEASE: SLACK — no boost, vel=(%.0f,%.0f)" % [
					p.velocity.x, p.velocity.y])
			p._grapple_launch_immunity = 0.5
			AudioManager.play("jump")
			p._rumble(0.3, 0.5, 0.1)
			_grapple_release()

	# Circle (interact) HELD while swinging near terrain → initiate slide
	if p._grapple_state in [GrappleState.SWINGING, GrappleState.CONNECTED,
						   GrappleState.TETHER_WINDUP, GrappleState.TETHER_THROWN]:
		if p._is_device_action_pressed("interact"):
			if _check_slide_impact():
				_slide_initiate()

	p.queue_redraw()




func _grapple_tick_windup(delta: float) -> void:
	p._grapple_hold_time += delta
	p._grapple_angular_vel = minf(
		GRAPPLE_BASE_ANGULAR_VEL + p._grapple_hold_time * GRAPPLE_ANGULAR_ACCEL,
		GRAPPLE_MAX_ANGULAR_VEL
	)
	p._grapple_angle += p._grapple_angular_vel * delta

	# Light rumble that builds with spin speed
	var spin_ratio: float = p._grapple_angular_vel / GRAPPLE_MAX_ANGULAR_VEL
	p._rumble(spin_ratio * 0.3, 0.0, 0.05)

	# Hook orbits player
	p._grapple_hook_pos = p.global_position + Vector2(
		cos(p._grapple_angle) * GRAPPLE_SWING_RADIUS,
		sin(p._grapple_angle) * GRAPPLE_SWING_RADIUS
	)

	# Update locked aim: right stick priority, then left stick, then keep last
	if p.device_id >= 0:
		var right_stick := Vector2(
			Input.get_joy_axis(p.device_id, JOY_AXIS_RIGHT_X),
			Input.get_joy_axis(p.device_id, JOY_AXIS_RIGHT_Y)
		)
		if right_stick.length() > 0.2:
			p._grapple_locked_aim = right_stick.normalized()
		else:
			var left_stick := Vector2(
				Input.get_joy_axis(p.device_id, JOY_AXIS_LEFT_X),
				Input.get_joy_axis(p.device_id, JOY_AXIS_LEFT_Y)
			)
			if left_stick.length() > 0.2:
				p._grapple_locked_aim = left_stick.normalized()
	else:
		# Keyboard: only update if actively pressing a direction
		var kb_aim := Vector2.ZERO
		if p._is_device_action_pressed("move_left"):
			kb_aim.x -= 1.0
		if p._is_device_action_pressed("move_right"):
			kb_aim.x += 1.0
		if p._is_device_action_pressed("move_up"):
			kb_aim.y -= 1.0
		if p._is_device_action_pressed("move_down"):
			kb_aim.y += 1.0
		if kb_aim != Vector2.ZERO:
			p._grapple_locked_aim = kb_aim.normalized()

	# Release check: grapple button released
	if not p._is_device_action_pressed("grapple"):
		if p._grapple_hold_time >= GRAPPLE_MIN_HOLD:
			_grapple_throw()
		else:
			p._grapple_state = GrappleState.IDLE




func _grapple_throw() -> void:
	var aim: Vector2 = p._grapple_locked_aim
	var throw_speed: float = clampf(
		GRAPPLE_BASE_THROW_SPEED + p._grapple_hold_time * GRAPPLE_THROW_SPEED_PER_SEC,
		GRAPPLE_BASE_THROW_SPEED,
		GRAPPLE_MAX_THROW_SPEED
	)
	p._grapple_hook_vel = aim * throw_speed
	p._grapple_hook_pos = p.global_position
	p._grapple_state = GrappleState.THROWN
	p._grapple_anchor_entity = null
	AudioManager.play("grapple_launch")
	p._rumble(0.4, 0.6, 0.15)  # Medium punch on throw

	# Initialize rope points
	p._grapple_rope_points.clear()
	for i in range(GRAPPLE_ROPE_SEGMENTS):
		p._grapple_rope_points.append(p.global_position)




func _grapple_tick_thrown(delta: float) -> void:
	# Apply gravity and drag to hook
	p._grapple_hook_vel.y += GRAPPLE_HOOK_GRAVITY * delta
	p._grapple_hook_vel *= GRAPPLE_HOOK_DRAG
	var prev_pos: Vector2 = p._grapple_hook_pos
	p._grapple_hook_pos += p._grapple_hook_vel * delta

	# Raycast along movement for collision
	var space = p.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		prev_pos, p._grapple_hook_pos,
		1 | 8  # world + enemies
	)
	query.exclude = [p.get_rid()]
	var result: Dictionary = space.intersect_ray(query)

	if result:
		p._grapple_hook_pos = result["position"]
		p._grapple_anchor = result["position"]
		var collider: Node = result["collider"]
		if collider.is_in_group("enemies"):
			p._grapple_anchor_entity = collider as Node2D
			p._grapple_anchor_body = null
			if collider.has_method("take_damage"):
				collider.take_damage(GRAPPLE_HOOK_DAMAGE, p.player_index)
				PlayerManager.add_skill_xp(p.player_index, "special", 5)
		elif collider is Node2D:
			# Wall/platform — track for moving platform support
			p._grapple_anchor_body = collider as Node2D
			p._grapple_anchor_offset = result["position"] - collider.global_position
			p._grapple_anchor_entity = null
		AudioManager.play("grapple_hit")
		p._rumble(0.6, 0.9, 0.2)
		p._grapple_state = GrappleState.CONNECTED
		p._grapple_rope_len = p.global_position.distance_to(p._grapple_anchor)

		# Launch: blend between direction-to-anchor and current travel tangent
		var to_anchor: Vector2 = (p._grapple_anchor - p.global_position).normalized()
		var travel_dir: Vector2 = p.velocity.normalized() if p.velocity.length() > 1.0 else to_anchor
		var blended_dir: Vector2 = (to_anchor + travel_dir).normalized()
		p.velocity = blended_dir * abs(p.JUMP_VELOCITY) * GRAPPLE_LAUNCH_SPEED_RATIO
		return

	# Update rope points (trail behind hook)
	_grapple_update_rope_thrown()

	# Max range check - if hook is too far, retract
	if p.global_position.distance_to(p._grapple_hook_pos) > GRAPPLE_MAX_ROPE_LEN * 1.5:
		_grapple_start_retract()




func _grapple_update_rope_thrown() -> void:
	if p._grapple_rope_points.is_empty():
		return
	# First point = player, last = hook
	p._grapple_rope_points[0] = p.global_position
	p._grapple_rope_points[GRAPPLE_ROPE_SEGMENTS - 1] = p._grapple_hook_pos
	# Interpolate middle points with slight sag
	for i in range(1, GRAPPLE_ROPE_SEGMENTS - 1):
		var t: float = float(i) / float(GRAPPLE_ROPE_SEGMENTS - 1)
		var lerped: Vector2 = p.global_position.lerp(p._grapple_hook_pos, t)
		var sag: float = sin(t * PI) * 15.0  # Gravity sag
		p._grapple_rope_points[i] = lerped + Vector2(0, sag)




func _update_grapple_anchor() -> void:
	## Update anchor p.position for moving platforms/enemies
	if p._grapple_anchor_entity and is_instance_valid(p._grapple_anchor_entity):
		p._grapple_anchor = p._grapple_anchor_entity.global_position
	elif p._grapple_anchor_body and is_instance_valid(p._grapple_anchor_body):
		p._grapple_anchor = p._grapple_anchor_body.global_position + p._grapple_anchor_offset




func _grapple_tick_connected(_delta: float) -> void:
	_update_grapple_anchor()

	# If pulling, actively reel player toward anchor
	if p._grapple_pulling:
		var to_anchor: Vector2 = (p._grapple_anchor - p.global_position).normalized()
		var pull_speed: float = abs(p.JUMP_VELOCITY) * GRAPPLE_LAUNCH_SPEED_RATIO
		p.velocity = to_anchor * pull_speed  # move_and_slide() will handle collision
		p._grapple_swing_drove_velocity = true
		# Update rope length to match current distance
		var dist: float = p.global_position.distance_to(p._grapple_anchor)
		p._grapple_rope_len = dist
		# If very close to anchor, stop pulling and enter swing
		if dist < 20.0:
			p._grapple_pulling = false
			_enter_swing_from_velocity()
		return

	var dist: float = p.global_position.distance_to(p._grapple_anchor)

	# If player exceeds rope length, transition to swing
	if dist >= p._grapple_rope_len:
		p._grapple_rope_len = dist
		p._grapple_rope_slack = false
		_enter_swing_from_velocity()
	# Otherwise rope is slack — normal movement via _physics_process


	# Otherwise rope is slack — normal movement via _physics_process


func _enter_swing_from_velocity() -> void:
	## Convert current p.velocity into pendulum angular p.velocity
	var diff: Vector2 = p.global_position - p._grapple_anchor
	p._grapple_swing_angle = atan2(diff.x, diff.y)
	var tangent: Vector2 = Vector2(cos(p._grapple_swing_angle), -sin(p._grapple_swing_angle))
	p._grapple_swing_vel = p.velocity.dot(tangent) / maxf(p._grapple_rope_len, 1.0)
	p._grapple_state = GrappleState.SWINGING
	p._grapple_rope_slack = false




func _grapple_tick_swinging(delta: float) -> void:
	_update_grapple_anchor()
	if p._grapple_anchor_entity and not is_instance_valid(p._grapple_anchor_entity):
		_grapple_release()
		return

	var dist: float = p.global_position.distance_to(p._grapple_anchor)

	# Check for slack: player is closer to anchor than rope length
	if dist < p._grapple_rope_len * 0.95:
		p._grapple_rope_slack = true

	if p._grapple_rope_slack:
		# Rope is slack — player moves freely with normal gravity
		# Velocity is preserved from last frame, gravity applied by _apply_gravity
		# Check if player has fallen back to rope length (bounce)
		if dist >= p._grapple_rope_len:
			p._grapple_rope_slack = false
			# Bounce: reflect p.velocity component along the rope direction
			var rope_dir: Vector2 = (p.global_position - p._grapple_anchor).normalized()
			var vel_along_rope: float = p.velocity.dot(rope_dir)
			if vel_along_rope > 0:
				# Moving away from anchor — reflect with damping
				p.velocity -= rope_dir * vel_along_rope * 1.5  # 1.5 = slight bounce
			# Constrain to rope length — set velocity toward the taut position
			# so move_and_slide() handles collision instead of teleporting through walls
			var taut_pos: Vector2 = p._grapple_anchor + rope_dir * p._grapple_rope_len
			var snap_delta: Vector2 = taut_pos - p.global_position
			p.velocity += snap_delta / maxf(p.get_physics_process_delta_time(), 0.001)
			# Re-enter pendulum from current p.velocity
			_enter_swing_from_velocity()
			p._rumble(0.4, 0.6, 0.1)  # Thump when rope snaps taut
		return

	# --- Taut rope: pendulum physics ---

	# Pendulum: α = -(g/L) * sin(θ)
	var alpha: float = -(GRAPPLE_PENDULUM_GRAVITY / maxf(p._grapple_rope_len, 1.0)) * sin(p._grapple_swing_angle)
	alpha -= p._grapple_swing_vel * GRAPPLE_SWING_DAMPING

	# Player input
	var input_h: float = 0.0
	var input_v: float = 0.0
	if p._is_device_action_pressed("move_left"):
		input_h -= 1.0
	if p._is_device_action_pressed("move_right"):
		input_h += 1.0
	if p._is_device_action_pressed("move_up"):
		input_v -= 1.0
	if p._is_device_action_pressed("move_down"):
		input_v += 1.0

	# Horizontal input: boost or brake swing
	if input_h != 0.0:
		if signf(input_h) == signf(p._grapple_swing_vel):
			alpha += input_h * GRAPPLE_INPUT_BOOST
		else:
			alpha += input_h * GRAPPLE_INPUT_BRAKE

	# Vertical input: adjust rope length
	if input_v != 0.0:
		p._grapple_rope_len = clampf(
			p._grapple_rope_len + input_v * GRAPPLE_ROPE_ADJUST_SPEED * delta,
			GRAPPLE_MIN_ROPE_LEN,
			GRAPPLE_MAX_ROPE_LEN
		)

	# Integrate pendulum
	p._grapple_swing_vel += alpha * delta
	p._grapple_swing_angle += p._grapple_swing_vel * delta

	# Check if player would go above anchor (rope would go slack)
	var new_pos := Vector2(
		p._grapple_anchor.x + p._grapple_rope_len * sin(p._grapple_swing_angle),
		p._grapple_anchor.y + p._grapple_rope_len * cos(p._grapple_swing_angle)
	)
	if new_pos.y < p._grapple_anchor.y:
		# Player swung above anchor — go slack, preserve velocity
		var tangent: Vector2 = Vector2(cos(p._grapple_swing_angle), -sin(p._grapple_swing_angle))
		p.velocity = tangent * p._grapple_swing_vel * p._grapple_rope_len
		p._grapple_rope_slack = true
		return

	# Set velocity so move_and_slide() moves us toward the pendulum target.
	# This replaces direct `global_position = new_pos` so the player collides
	# with walls and platforms instead of clipping through them.
	var delta_pos: Vector2 = new_pos - p.global_position
	p.velocity = delta_pos / maxf(p.get_physics_process_delta_time(), 0.001)

	# Flag for player_side to know the swing set velocity this frame
	# (prevents _handle_movement from overriding it)
	p._grapple_swing_drove_velocity = true

	# Rumble scales with speed: 5% at rest, 20% at full speed
	var swing_speed: float = absf(p._grapple_swing_vel * p._grapple_rope_len)
	var rumble_intensity: float = lerpf(0.05, 0.20, clampf(swing_speed / 600.0, 0.0, 1.0))
	p._rumble(rumble_intensity, 0.0, 0.05)




func _grapple_tug() -> void:
	## Newtonian tug when releasing from an enemy
	if not p._grapple_anchor_entity or not is_instance_valid(p._grapple_anchor_entity):
		_grapple_release()
		return

	p._grapple_state = GrappleState.TUG

	# Deal tug damage
	if p._grapple_anchor_entity.has_method("take_damage"):
		p._grapple_anchor_entity.take_damage(GRAPPLE_TUG_DAMAGE, p.player_index)
		PlayerManager.add_skill_xp(p.player_index, "special", 7)

	# Get enemy p.mass
	var enemy_mass: float = 70.0  # default
	if "mass" in p._grapple_anchor_entity:
		enemy_mass = p._grapple_anchor_entity.mass

	# F = ma → a = F/m, applied as impulse over TUG_DURATION
	var dir_to_enemy: Vector2 = (p._grapple_anchor_entity.global_position - p.global_position).normalized()
	var player_accel: float = GRAPPLE_TUG_FORCE / p.mass
	var enemy_accel: float = GRAPPLE_TUG_FORCE / enemy_mass

	# Apply impulses
	p.velocity = dir_to_enemy * player_accel * GRAPPLE_TUG_DURATION
	if p._grapple_anchor_entity is CharacterBody2D:
		p._grapple_anchor_entity.velocity = -dir_to_enemy * enemy_accel * GRAPPLE_TUG_DURATION

	# Apply knockback if the enemy has the method
	if p._grapple_anchor_entity.has_method("apply_knockback"):
		p._grapple_anchor_entity.apply_knockback(-dir_to_enemy * enemy_accel * GRAPPLE_TUG_DURATION)

	AudioManager.play("grapple_hit", 0.0, 0.8)
	p._rumble(0.7, 1.0, 0.25)  # Heavy thud on tug
	p._spawn_blood_particles(p._grapple_anchor_entity.global_position)
	_grapple_start_retract()




func _grapple_pull_to_anchor() -> void:
	## First L1: pull player straight toward anchor, stay connected
	# Switch to CONNECTED state so pendulum doesn't override p.position
	p._grapple_state = GrappleState.CONNECTED
	p._grapple_rope_slack = true  # Allow free movement toward anchor
	var to_anchor: Vector2 = (p._grapple_anchor - p.global_position).normalized()
	p.velocity = to_anchor * abs(p.JUMP_VELOCITY) * GRAPPLE_LAUNCH_SPEED_RATIO
	# Shorten rope to current distance so it goes taut at the new p.position
	p._grapple_rope_len = p.global_position.distance_to(p._grapple_anchor)
	p._grapple_pulling = true
	AudioManager.play("grapple_hit", 0.0, 1.2)
	p._rumble(0.5, 0.7, 0.15)  # Pull toward anchor




func _grapple_jump_on_rope() -> void:
	## Jump while staying attached to the grapple line.
	## Adds an upward impulse — the rope naturally goes slack as the player
	## rises toward the anchor, then snaps taut again on the way down.
	## This lets the player vault over obstacles, change swing direction,
	## or gain height without losing the connection.
	var jump_vel: float = p.cfg("jump_velocity", p.JUMP_VELOCITY) * 0.8  # Slightly weaker than ground jump
	p.velocity.y = jump_vel
	p._grapple_rope_slack = true  # Let normal gravity + movement run until rope catches
	AudioManager.play("jump", -3.0)
	p._rumble(0.2, 0.3, 0.08)


func _grapple_jump_release() -> void:
	## Explicit detach: release grapple and add momentum-based impulse
	var pre_vel: Vector2 = p.velocity  # Velocity from pendulum
	var aim: Vector2 = p._get_aim_direction_analog()
	var jump_impulse: Vector2 = aim * abs(p.JUMP_VELOCITY) * 0.25
	p.velocity += jump_impulse
	var post_vel: Vector2 = p.velocity

	# Prevent p._handle_movement from overriding p.velocity for 0.5s
	p._grapple_launch_immunity = 0.5

	# Debug tracers: snapshot all vectors at this moment
	if DebugOverlay.should_draw("player/jump_tracers", p):
		p._debug_tracers.append({
			"pos": p.global_position,
			"pre_vel": pre_vel,
			"impulse": jump_impulse,
			"post_vel": post_vel,
			"time": 10.0,
		})

	AudioManager.play("jump")
	p._rumble(0.3, 0.5, 0.1)  # Short pop on jump release
	p._grapple_state = GrappleState.RETRACTING
	p._grapple_retract_timer = 0.2
	p._grapple_anchor_entity = null




# =============================================================================
# SWING-SLIDE-JUMP (Phase 5.5)
# =============================================================================

func _check_slide_impact() -> bool:
	## Check if the player is within SLIDE_IMPACT_RADIUS of a non-ceiling surface.
	## Ceilings (normal pointing down, y > 0.5) are rejected — can't slide on ceilings.
	if p.is_on_floor():
		return true
	if p.is_on_wall():
		return true
	# Not touching — probe ahead
	var test_vel: Vector2 = p.velocity.normalized() * SLIDE_IMPACT_RADIUS
	if test_vel.length() < 1.0:
		test_vel = Vector2(0, SLIDE_IMPACT_RADIUS)
	var collision: KinematicCollision2D = p.move_and_collide(test_vel * p.get_physics_process_delta_time(), true)
	if collision:
		var normal: Vector2 = collision.get_normal()
		# Reject ceilings: normal.y > 0.5 means surface faces downward
		if normal.y > 0.5:
			return false
		return true
	return false


func _slide_initiate() -> void:
	## Transition from SWINGING to SLIDE — decompose velocity onto surface.
	## Pushes a RampModifierProvider for charge buildup.
	var MCP = preload("res://scripts/systems/monster_config.gd")

	# Get the surface normal from collision — reject ceilings
	var surface_normal := Vector2.UP
	if p.is_on_floor():
		surface_normal = p.get_floor_normal()
	elif p.is_on_wall():
		surface_normal = p.get_wall_normal()
	else:
		var collision: KinematicCollision2D = p.move_and_collide(
			p.velocity.normalized() * SLIDE_IMPACT_RADIUS * p.get_physics_process_delta_time(), true)
		if collision:
			surface_normal = collision.get_normal()
	# Reject ceilings
	if surface_normal.y > 0.5:
		return

	# Compute TRUE swing velocity from pendulum angular state (not p.velocity,
	# which gets mangled by move_and_slide floor collisions during the swing).
	var swing_vel := Vector2.ZERO
	if p._grapple_swing_vel != 0.0:
		var tangent := Vector2(cos(p._grapple_swing_angle), -sin(p._grapple_swing_angle))
		swing_vel = tangent * p._grapple_swing_vel * p._grapple_rope_len
	else:
		swing_vel = p.velocity  # Fallback if not in pendulum mode

	# Surface tangent = perpendicular to normal, in the direction of swing
	var raw_tangent := Vector2(-surface_normal.y, surface_normal.x)
	if raw_tangent.dot(swing_vel) < 0:
		raw_tangent = -raw_tangent

	# Decompose swing velocity onto surface: parallel component = slide speed
	var parallel_speed: float = swing_vel.dot(raw_tangent)
	parallel_speed = absf(parallel_speed) + SLIDE_BOOST

	var swing_dir: String = "RIGHT" if swing_vel.x > 0 else "LEFT"
	DebugOverlay.log("player/slide", p, "SLIDE INIT: swing_vel=(%.0f,%.0f) speed=%.0f dir=%s angle=%.2f omega=%.2f p.vel=(%.0f,%.0f)" % [
		swing_vel.x, swing_vel.y, swing_vel.length(), swing_dir,
		p._grapple_swing_angle, p._grapple_swing_vel, p.velocity.x, p.velocity.y])

	# Store slide state
	p._slide_velocity = raw_tangent * parallel_speed
	p._slide_surface_normal = surface_normal
	p._slide_surface_tangent = raw_tangent
	p._grapple_state = GrappleState.SLIDE
	_slide_on_surface = true
	_slide_max_extent = p.global_position

	# Push charge ramp modifier: 1.0x → 1.5x over 2 seconds
	if _slide_charge_mod:
		p.remove_config(_slide_charge_mod)
	_slide_charge_mod = MCP.RampModifierProvider.new({
		"ranger_slide_charge_mult": ["multiply", 1.0, 1.5]
	}, SLIDE_CHARGE_TIME, "slide_charge")
	p.push_config(_slide_charge_mod)

	# Snap player to surface — enable floor snapping to maintain contact
	p.velocity = p._slide_velocity
	p.floor_snap_length = 8.0  # Snap to floor within 8px

	AudioManager.play("jump", -6.0, 0.7)
	p._rumble(0.2, 0.1, 0.08)

	DebugOverlay.log("player/slide", p, "SLIDE START: speed=%.0f normal=(%.2f,%.2f) charge_mod pushed" % [
		parallel_speed, surface_normal.x, surface_normal.y])

	# Lingering debug vectors at impact point
	if DebugOverlay.should_draw("player/slide", p):
		p._debug_tracers.append({
			"pos": p.global_position,
			"pre_vel": p.velocity,
			"impulse": surface_normal * 200.0,
			"post_vel": raw_tangent * parallel_speed,
			"time": 8.0,
		})


func _slide_tick(delta: float) -> void:
	## Per-frame slide update: friction, gravity on slopes, terrain following, charge tracking.
	var speed: float = p._slide_velocity.length()

	# Apply friction
	speed *= SLIDE_FRICTION

	# Gravity along slope: zero on flat, partial on slopes, full on vertical
	var slope_sin: float = p._slide_surface_tangent.dot(Vector2.DOWN)
	speed += SLIDE_GRAVITY * slope_sin * delta

	# End slide if too slow — but only if Circle is released.
	# While Circle is held, keep the slide alive (player chose to hold).
	if speed < SLIDE_MIN_SPEED:
		if not p._is_device_action_pressed("interact"):
			_slide_end()
			return
		speed = 0.0  # Stopped but still in slide state — waiting for release

	p._slide_velocity = p._slide_surface_tangent * speed
	# Apply slide velocity + surface-hugging force to maintain contact
	# CharacterBody2D needs a downward component to register is_on_floor()
	p.velocity = p._slide_velocity - p._slide_surface_normal * 200.0

	# Move and check for terrain changes
	p.move_and_slide()
	# Force floor snap after move to maintain contact
	p.apply_floor_snap()

	# Track surface contact
	var was_on_surface: bool = _slide_on_surface
	_slide_on_surface = p.is_on_floor() or p.is_on_wall()

	# Update surface normal from collision (terrain following)
	if p.is_on_floor():
		var new_normal: Vector2 = p.get_floor_normal()
		if new_normal.dot(p._slide_surface_normal) < 0.0:
			_slide_on_surface = false
			_slide_leave_surface()
			return
		_slide_update_surface(new_normal)
	elif p.is_on_wall():
		var new_normal: Vector2 = p.get_wall_normal()
		_slide_update_surface(new_normal)

	# Detect leaving surface → freeze charge (no boost on release)
	# Player stays in SLIDE state — Circle release still works (but no boost).
	if was_on_surface and not _slide_on_surface:
		_slide_leave_surface()

	# Check taut point: rope reaches max length → constrain to rope circle.
	# Rope stays connected — player gets pulled off surface by the rope.
	if p._grapple_state == GrappleState.SLIDE:
		var rope_vec: Vector2 = p.global_position - p._grapple_anchor
		var dist: float = rope_vec.length()
		if dist >= p._grapple_rope_len:
			# Snap back to rope length
			p.global_position = p._grapple_anchor + rope_vec.normalized() * p._grapple_rope_len
			# Remove the velocity component that points away from anchor
			var rope_dir: Vector2 = rope_vec.normalized()
			var vel_away: float = p._slide_velocity.dot(rope_dir)
			if vel_away > 0:
				p._slide_velocity -= rope_dir * vel_away
			p._rumble(0.4, 0.6, 0.1)  # Sproing feel
			DebugOverlay.log("player/slide", p, "SLIDE: rope TAUT at dist=%.0f — constraining" % dist)

	# Track max extent for debug
	if p.global_position.distance_to(_slide_max_extent) > (_slide_max_extent - p.global_position).length():
		_slide_max_extent = p.global_position

	# Emit dust particles
	_slide_emit_particles(delta)


func _slide_update_surface(new_normal: Vector2) -> void:
	## Re-project slide velocity onto new surface tangent (terrain following).
	var new_tangent := Vector2(-new_normal.y, new_normal.x)
	if new_tangent.dot(p._slide_velocity) < 0:
		new_tangent = -new_tangent
	var speed: float = p._slide_velocity.length()
	p._slide_surface_normal = new_normal
	p._slide_surface_tangent = new_tangent
	p._slide_velocity = new_tangent * speed


func _slide_leave_surface() -> void:
	## Player left the surface (fell off edge or rope pulled them off).
	## Freeze charge, transition back to SWINGING with current momentum.
	if _slide_charge_mod and _slide_charge_mod.has_method("freeze"):
		_slide_charge_mod.freeze()
	_slide_on_surface = false

	# Preserve momentum from the slide — use the slide velocity (not p.velocity
	# which was mangled by move_and_slide floor absorption).
	# Remove the surface-hugging force component so the player launches cleanly.
	var exit_vel: Vector2 = p._slide_surface_tangent * p._slide_velocity.length()
	p.velocity = exit_vel
	p.floor_snap_length = 0.0
	p._grapple_rope_slack = true  # Rope goes slack, player freefalls until taut
	p._grapple_state = GrappleState.SWINGING
	p._grapple_launch_immunity = 0.3

	# Pop charge modifier — slide is over
	if _slide_charge_mod:
		p.remove_config(_slide_charge_mod)
		_slide_charge_mod = null

	DebugOverlay.log("player/slide", p, "SLIDE: left surface → SWINGING with vel=(%.0f,%.0f)" % [
		p.velocity.x, p.velocity.y])


func _slide_release() -> void:
	## Circle released. If on surface → boosted launch. If off surface → no boost.
	var charge_mult: float = 1.0
	var charge_pct: float = 0.0
	if _slide_charge_mod:
		charge_pct = _slide_charge_mod.get_progress()

	if _slide_on_surface:
		# ON SURFACE: RED = GREEN (normal × jump) + BLUE (slide × charge)
		# GREEN: surface normal × jump boost (the jump component)
		var jump_boost: float = abs(p.cfg("jump_velocity", p.JUMP_VELOCITY))
		var green: Vector2 = p._slide_surface_normal * jump_boost
		# BLUE: slide velocity × charge multiplier
		charge_mult = p.cfg("ranger_slide_charge_mult", 1.0)
		var blue: Vector2 = p._slide_velocity * charge_mult
		# RED: combined launch
		var launch: Vector2 = green + blue
		p.velocity = launch
		p._grapple_launch_immunity = 0.5

		# Debug tracers (lingering)
		if DebugOverlay.should_draw("player/slide", p):
			p._debug_tracers.append({
				"pos": p.global_position,
				"pre_vel": blue,           # BLUE: slide component
				"impulse": green,          # GREEN: normal jump component
				"post_vel": launch,
				"time": 8.0,
			})

		AudioManager.play("jump")
		p._rumble(0.3, 0.5, 0.1)
		DebugOverlay.log("player/slide", p, "SLIDE RELEASE: on_surface=true charge=%.0f%% mult=%.2f green=(%.0f,%.0f) blue=(%.0f,%.0f) launch=(%.0f,%.0f) speed=%.0f" % [
			charge_pct * 100.0, charge_mult, green.x, green.y, blue.x, blue.y, launch.x, launch.y, launch.length()])
	else:
		# OFF SURFACE: no boost — keep current velocity, charge wasted
		p._grapple_launch_immunity = 0.3
		DebugOverlay.log("player/slide", p, "SLIDE RELEASE: on_surface=false — charge WASTED (%.0f%%)" % [
			charge_pct * 100.0])

	# Pop the charge modifier
	if _slide_charge_mod:
		p.remove_config(_slide_charge_mod)
		_slide_charge_mod = null

	# Restore floor snap
	p.floor_snap_length = 0.0

	# Rope stays attached — go back to swinging with launch velocity
	p._grapple_rope_slack = true
	p._grapple_state = GrappleState.SWINGING


func _slide_end() -> void:
	## Slide ended naturally (too slow). Rope stays attached.
	if _slide_charge_mod:
		p.remove_config(_slide_charge_mod)
		_slide_charge_mod = null
	p.floor_snap_length = 0.0
	p._grapple_rope_slack = true
	p._grapple_state = GrappleState.SWINGING
	DebugOverlay.log("player/slide", p, "SLIDE END → SWINGING (rope attached)")


var _slide_particle_accum: float = 0.0

func _slide_emit_particles(_delta: float) -> void:
	## Emit dust puffs while sliding. Rate proportional to speed.
	var speed: float = p._slide_velocity.length()
	var rate: float = SLIDE_PARTICLE_RATE * (speed / 300.0)  # Scale by speed
	_slide_particle_accum += rate * _delta
	while _slide_particle_accum >= 1.0:
		_slide_particle_accum -= 1.0
		# Spawn a dust puff behind the player
		var puff_pos: Vector2 = p.global_position - p._slide_surface_tangent * 8.0
		puff_pos += Vector2(randf_range(-4, 4), randf_range(-4, 4))
		var puff_vel: Vector2 = -p._slide_surface_tangent * randf_range(10, 30) + p._slide_surface_normal * randf_range(5, 20)
		_spawn_dust_puff(puff_pos, puff_vel)


func _spawn_dust_puff(pos: Vector2, vel: Vector2) -> void:
	## Create a small dust/smoke particle. Uses the object pool if available.
	var pool: Node = get_node_or_null("/root/ObjectPool")
	if pool and pool.has_method("spawn_particle"):
		pool.spawn_particle(pos, vel, Color(0.6, 0.55, 0.45, 0.5), randf_range(2.0, 4.0), randf_range(0.3, 0.5))


# -- Ranger Run (block button → 2x speed) --------------------------------------

func _handle_ranger_run(delta: float) -> void:
	if p.character_class != PlayerManager.CharacterClass.RANGED:
		return
	if _is_dashing:
		_is_running = false
		_run_airborne = false
		return
	var deflection: float = _get_h_deflection()
	var h_raw: float = _get_h_raw()
	var was_running := _is_running

	# Asymmetric smoothing: fast rise (0.3), slow fall (0.08)
	# Controller jitter causes single-frame drops to ~25% even at full deflection.
	# Slow fall means garbage frames barely move the smoothed value.
	if deflection >= _smoothed_deflection:
		_smoothed_deflection = lerpf(_smoothed_deflection, deflection, 0.3)
	else:
		_smoothed_deflection = lerpf(_smoothed_deflection, deflection, 0.08)

	# Smooth signed input — prevents sign-flip jitter from briefly walking backwards.
	# Same asymmetric approach: fast toward larger magnitude, slow toward smaller/opposite.
	if absf(h_raw) >= absf(_smoothed_h) or signf(h_raw) == signf(_smoothed_h):
		_smoothed_h = lerpf(_smoothed_h, h_raw, 0.3)
	else:
		_smoothed_h = lerpf(_smoothed_h, h_raw, 0.08)

	# Update stick visualizer trail
	_stick_viz_update(h_raw, get_process_delta_time())

	if p.is_on_floor():
		# Hysteresis on smoothed value: enter run at >90%, exit only when <80%
		if _is_running:
			_is_running = _smoothed_deflection > 0.8
		else:
			_is_running = _smoothed_deflection > 0.9
		if _run_airborne:
			_run_airborne = false
			DebugOverlay.log("player/run", p, "RUN AIRBORNE: landed")
	else:
		# In air: if was running (or airborne from run), maintain momentum
		if was_running or _run_airborne:
			_run_airborne = true
			_is_running = false  # Not ground-running, but momentum preserved
		else:
			_is_running = false
			_run_airborne = false

	DebugOverlay.log("player/stick", p, "STICK: raw=%.3f defl=%.0f%% smooth=%.0f%% facing=%s run=%s airborne=%s dash=%s vel=(%.0f,%.0f)" % [
		h_raw, deflection * 100.0, _smoothed_deflection * 100.0,
		"R" if p._facing_right else "L",
		str(_is_running), str(_run_airborne), str(_is_dashing),
		p.velocity.x, p.velocity.y])

	if _is_running and not was_running:
		_spawn_run_start_puff()
		DebugOverlay.log("player/run", p, "RUN START: deflection=%.0f%%" % [deflection * 100])

	if _is_running:
		_run_emit_footstep(delta)
	else:
		_run_footstep_accum = 0.0
		if was_running and not _run_airborne:
			DebugOverlay.log("player/run", p, "RUN END")

	# Age and cull run particles
	_age_run_particles(delta)


func _get_h_raw() -> float:
	## Returns signed horizontal input (-1.0 to 1.0). Analog for gamepad, binary for keyboard.
	if p.device_id >= 0:
		var raw: float = Input.get_joy_axis(p.device_id, JOY_AXIS_LEFT_X)
		return raw if absf(raw) >= 0.1 else 0.0
	var h := 0.0
	if p._is_device_action_pressed("move_left"): h -= 1.0
	if p._is_device_action_pressed("move_right"): h += 1.0
	return h


func _get_h_deflection() -> float:
	## Returns 0.0–1.0 horizontal stick deflection (absolute value of raw).
	return absf(_get_h_raw())


func _spawn_run_start_puff() -> void:
	## Burst of 8 smoke circles at feet, expanding outward.
	var foot_pos: Vector2 = p.global_position + Vector2(0, 8)
	for i in range(8):
		var angle: float = TAU * i / 8.0 + randf_range(-0.2, 0.2)
		var speed: float = randf_range(30.0, 70.0)
		_run_particles.append({
			"pos": foot_pos + Vector2(randf_range(-4, 4), randf_range(-2, 2)),
			"vel": Vector2(cos(angle), sin(angle)) * speed,
			"age": 0.0,
			"max_age": randf_range(0.3, 0.5),
			"radius": randf_range(3.0, 6.0),
		})
	p.queue_redraw()


func _run_emit_footstep(delta: float) -> void:
	## Small puff at feet while running, alternating left/right.
	_run_footstep_accum += RUN_FOOTSTEP_RATE * delta
	while _run_footstep_accum >= 1.0:
		_run_footstep_accum -= 1.0
		var foot_offset: float = -6.0 if int(_run_footstep_accum * 10) % 2 == 0 else 6.0
		var foot_pos: Vector2 = p.global_position + Vector2(foot_offset, 8)
		_run_particles.append({
			"pos": foot_pos,
			"vel": Vector2(randf_range(-15, 15), randf_range(-25, -10)),
			"age": 0.0,
			"max_age": randf_range(0.2, 0.35),
			"radius": randf_range(1.5, 3.0),
		})
	p.queue_redraw()


func _age_run_particles(delta: float) -> void:
	var i: int = _run_particles.size() - 1
	while i >= 0:
		_run_particles[i]["age"] += delta
		_run_particles[i]["pos"] += _run_particles[i]["vel"] * delta
		_run_particles[i]["vel"] *= 0.92  # Drag
		if _run_particles[i]["age"] >= _run_particles[i]["max_age"]:
			_run_particles.remove_at(i)
		i -= 1


# -- Ranger Dash (R1 when grounded + not grappling → 4x speed, 0.5s) -----------

func _handle_ranger_dash(delta: float) -> void:
	if p.character_class != PlayerManager.CharacterClass.RANGED:
		return

	# Tick cooldown
	if _dash_cooldown_timer > 0.0:
		_dash_cooldown_timer = maxf(_dash_cooldown_timer - delta, 0.0)

	# Tick active dash
	if _is_dashing:
		_dash_timer -= delta
		_dash_update_trail(delta)

		# Track if player jumped during dash
		if not p.is_on_floor():
			_dash_jumped = true

		# End: timer expired AND (touching any surface OR never jumped)
		if _dash_timer <= 0.0:
			var on_surface: bool = p.is_on_floor() or p.is_on_wall() or p.is_on_ceiling()
			if on_surface or not _dash_jumped:
				_dash_end()
		_r1_was_pressed = _is_r1_pressed()
		return

	# Fade trail/sparkles when not dashing
	_dash_fade_trail(delta)

	# Check R1 for dash initiation
	var r1_now: bool = _is_r1_pressed()
	var r1_just: bool = r1_now and not _r1_was_pressed
	_r1_was_pressed = r1_now

	if not r1_just:
		return
	if p._grapple_state != GrappleState.IDLE:
		return  # R1 is pull-to-anchor while grappling
	if not p.is_on_floor():
		return
	if _dash_cooldown_timer > 0.0:
		# Cooldown flash / feedback
		DebugOverlay.log("player/dash", p, "DASH: on cooldown (%.1fs remaining)" % _dash_cooldown_timer)
		return

	_dash_start()


func _is_r1_pressed() -> bool:
	if p.device_id >= 0:
		return Input.is_joy_button_pressed(p.device_id, JOY_BUTTON_RIGHT_SHOULDER)
	return Input.is_key_pressed(KEY_SHIFT)


func _dash_start() -> void:
	_is_dashing = true
	_dash_timer = DASH_DURATION
	_dash_jumped = false
	_dash_direction = 1.0 if p._facing_right else -1.0
	_is_running = false  # Dash overrides run
	_dash_trail.clear()
	_dash_sparkles.clear()

	AudioManager.play("grapple_launch", -3.0, 1.5)
	p._rumble(0.2, 0.4, 0.1)
	p.queue_redraw()

	DebugOverlay.log("player/dash", p, "DASH START: dir=%.0f cooldown=%.1f" % [
		_dash_direction, DASH_COOLDOWN])


func _dash_end() -> void:
	_is_dashing = false
	_dash_cooldown_timer = DASH_COOLDOWN
	_dash_jumped = false
	p.queue_redraw()
	DebugOverlay.log("player/dash", p, "DASH END: cooldown=%.1fs" % DASH_COOLDOWN)


func _dash_update_trail(delta: float) -> void:
	# Add current position to trail
	_dash_trail.append({"pos": p.global_position, "age": 0.0})

	# Spawn sparkles (~30/sec, mix of green outer + yellow streak)
	var sparkle_count: int = int(30.0 * delta) + (1 if randf() < fmod(30.0 * delta, 1.0) else 0)
	for _si in range(sparkle_count):
		var offset := Vector2(randf_range(-12, 12), randf_range(-18, 6))
		var sparkle_vel := Vector2(-_dash_direction * randf_range(20, 80), randf_range(-40, 15))
		_dash_sparkles.append({
			"pos": p.global_position + offset,
			"vel": sparkle_vel,
			"age": 0.0,
			"max_age": randf_range(0.15, 0.35),
			"yellow": randf() < 0.35,
		})

	# Age trail points
	var i: int = _dash_trail.size() - 1
	while i >= 0:
		_dash_trail[i]["age"] += delta
		if _dash_trail[i]["age"] >= DASH_TRAIL_MAX_AGE:
			_dash_trail.remove_at(i)
		i -= 1

	# Age sparkles
	i = _dash_sparkles.size() - 1
	while i >= 0:
		_dash_sparkles[i]["age"] += delta
		_dash_sparkles[i]["pos"] += _dash_sparkles[i]["vel"] * delta
		if _dash_sparkles[i]["age"] >= _dash_sparkles[i]["max_age"]:
			_dash_sparkles.remove_at(i)
		i -= 1


func _dash_fade_trail(delta: float) -> void:
	## Continue fading trail and sparkles after dash ends.
	var i: int = _dash_trail.size() - 1
	while i >= 0:
		_dash_trail[i]["age"] += delta * 2.5  # Fade faster post-dash
		if _dash_trail[i]["age"] >= DASH_TRAIL_MAX_AGE:
			_dash_trail.remove_at(i)
		i -= 1

	i = _dash_sparkles.size() - 1
	while i >= 0:
		_dash_sparkles[i]["age"] += delta
		_dash_sparkles[i]["pos"] += _dash_sparkles[i]["vel"] * delta
		if _dash_sparkles[i]["age"] >= _dash_sparkles[i]["max_age"]:
			_dash_sparkles.remove_at(i)
		i -= 1

	if _dash_trail.is_empty() and _dash_sparkles.is_empty() and not _run_particles.is_empty():
		pass  # run particles handled separately


func get_speed_multiplier() -> float:
	## Returns the speed multiplier from run/dash state.
	## Includes airborne momentum — run/dash speed carries through jumps.
	if _is_dashing:
		return DASH_SPEED_MULT
	if _is_running or _run_airborne:
		return RUN_SPEED_MULT
	return 1.0


func _grapple_release() -> void:
	## Release from wall — keep swing momentum
	p._grapple_state = GrappleState.RETRACTING
	p._grapple_retract_timer = 0.2
	p._grapple_anchor_entity = null
	p._grapple_anchor_body = null
	p._grapple_pulling = false
	p._grapple_launch_immunity = 0.5
	p._stop_rumble()
	# p.velocity is already set from swing


	# p.velocity is already set from swing


func _grapple_start_retract() -> void:
	p._grapple_state = GrappleState.RETRACTING
	p._grapple_retract_timer = 0.2
	p._grapple_anchor_entity = null
	p._grapple_anchor_body = null
	p._grapple_launch_immunity = 0.5




func _grapple_tick_retracting(delta: float) -> void:
	p._grapple_retract_timer -= delta
	# Animate hook back to player
	p._grapple_hook_pos = p._grapple_hook_pos.lerp(p.global_position, delta * 10.0)
	if p._grapple_retract_timer <= 0.0:
		p._grapple_state = GrappleState.IDLE
		p._grapple_rope_points.clear()


# -- Tether (Dual-Grapple) ----------------------------------------------------



# -- Tether (Dual-Grapple) ----------------------------------------------------

func _tether_begin_second_hook() -> void:
	## L2 pressed while connected/swinging: save anchor A, start second hook windup at anchor p.position.
	p._tether_target_length = p._grapple_rope_len  # Current rope length is the tether target
	# Save first anchor data
	var TetherScript: GDScript = load("res://scripts/systems/tether.gd")
	if is_instance_valid(p._grapple_anchor_entity):
		# Anchored to enemy — check for nearest attachment point
		var ap: String = ""
		if "_attach_points" in p._grapple_anchor_entity:
			var best_dist: float = 999.0
			for point_name in p._grapple_anchor_entity._attach_points:
				var area: Area2D = p._grapple_anchor_entity._attach_points[point_name]
				var point_world: Vector2 = p._grapple_anchor_entity.global_position + area.position
				var d: float = p._grapple_anchor.distance_to(point_world)
				if d < best_dist:
					best_dist = d
					ap = point_name
		p._tether_anchor_a = TetherScript.make_anchor_body(p._grapple_anchor_entity, ap)
	elif is_instance_valid(p._grapple_anchor_body):
		p._tether_anchor_a = TetherScript.make_anchor_wall(p._grapple_anchor)
	else:
		p._tether_anchor_a = TetherScript.make_anchor_wall(p._grapple_anchor)

	# Start second hook spinning at the PLAYER p.position (player spins the rope)
	p._grapple_state = GrappleState.TETHER_WINDUP
	p._tether_hold_time = 0.0
	p._tether_angle = 0.0
	p._tether_angular_vel = GRAPPLE_BASE_ANGULAR_VEL
	p._tether_hook_pos = p.global_position
	AudioManager.play("grapple_launch", -6.0, 1.5)




func _tether_tick_windup(delta: float) -> void:
	## Second hook spins at the PLAYER p.position (player spins the rope end).
	p._tether_hold_time += delta
	p._tether_angular_vel = minf(
		GRAPPLE_BASE_ANGULAR_VEL + p._tether_hold_time * GRAPPLE_ANGULAR_ACCEL,
		GRAPPLE_MAX_ANGULAR_VEL
	)
	p._tether_angle += p._tether_angular_vel * delta

	# Hook orbits the player
	p._tether_hook_pos = p.global_position + Vector2(
		cos(p._tether_angle) * GRAPPLE_SWING_RADIUS,
		sin(p._tether_angle) * GRAPPLE_SWING_RADIUS
	)

	# Update aim direction (same as normal windup — sticks control aim arrow)
	if p.device_id >= 0:
		var right_stick := Vector2(
			Input.get_joy_axis(p.device_id, JOY_AXIS_RIGHT_X),
			Input.get_joy_axis(p.device_id, JOY_AXIS_RIGHT_Y)
		)
		if right_stick.length() > 0.2:
			p._grapple_locked_aim = right_stick.normalized()
		else:
			var left_stick := Vector2(
				Input.get_joy_axis(p.device_id, JOY_AXIS_LEFT_X),
				Input.get_joy_axis(p.device_id, JOY_AXIS_LEFT_Y)
			)
			if left_stick.length() > 0.2:
				p._grapple_locked_aim = left_stick.normalized()

	var spin_ratio: float = p._tether_angular_vel / GRAPPLE_MAX_ANGULAR_VEL
	p._rumble(spin_ratio * 0.2, 0.0, 0.05)




func _tether_throw_second_hook() -> void:
	## Release L2: launch second hook from anchor A toward player's aim.
	var aim: Vector2 = p._grapple_locked_aim
	var throw_speed: float = clampf(
		GRAPPLE_BASE_THROW_SPEED + p._tether_hold_time * GRAPPLE_THROW_SPEED_PER_SEC,
		GRAPPLE_BASE_THROW_SPEED,
		GRAPPLE_MAX_THROW_SPEED
	)
	p._tether_hook_vel = aim * throw_speed
	p._tether_hook_pos = p.global_position  # Launch from the player
	p._grapple_state = GrappleState.TETHER_THROWN
	AudioManager.play("grapple_launch")
	p._rumble(0.4, 0.6, 0.15)




func _tether_tick_thrown(delta: float) -> void:
	## Second hook in flight from anchor A.
	p._tether_hook_vel.y += GRAPPLE_HOOK_GRAVITY * delta
	p._tether_hook_vel *= GRAPPLE_HOOK_DRAG
	var prev_pos: Vector2 = p._tether_hook_pos
	p._tether_hook_pos += p._tether_hook_vel * delta

	# Raycast for collision
	var space = p.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		prev_pos, p._tether_hook_pos,
		1 | 8  # world + enemies
	)
	query.exclude = [p.get_rid()]
	var result: Dictionary = space.intersect_ray(query)

	if result:
		p._tether_hook_pos = result["position"]
		var collider: Node = result["collider"]

		# Build anchor B
		var TetherScript: GDScript = load("res://scripts/systems/tether.gd")
		var anchor_b: Dictionary
		if collider.is_in_group("enemies"):
			var ap: String = ""
			if "_attach_points" in collider:
				var best_dist: float = 999.0
				for point_name in collider._attach_points:
					var area: Area2D = collider._attach_points[point_name]
					var point_world: Vector2 = collider.global_position + area.position
					var d: float = p._tether_hook_pos.distance_to(point_world)
					if d < best_dist:
						best_dist = d
						ap = point_name
			anchor_b = TetherScript.make_anchor_body(collider as Node2D, ap)
			if collider.has_method("take_damage"):
				collider.take_damage(GRAPPLE_HOOK_DAMAGE, p.player_index)
		else:
			anchor_b = TetherScript.make_anchor_wall(result["position"])

		# Create the tether entity
		var tether := Node2D.new()
		tether.set_script(TetherScript)
		tether.setup(p._tether_anchor_a, anchor_b, p._tether_target_length, p.player_index)
		get_tree().current_scene.add_child(tether)
		p._active_tethers.append(tether)

		AudioManager.play("grapple_hit")
		p._rumble(0.6, 0.9, 0.2)

		# Player drops from the rope — tether is now standalone
		p._grapple_launch_immunity = 0.5
		p._grapple_state = GrappleState.RETRACTING
		p._grapple_retract_timer = 0.2
		p._grapple_anchor_entity = null
		p._grapple_anchor_body = null
		return

	# Max range: retract if second hook goes too far from anchor A
	var anchor_a_pos: Vector2 = p._grapple_anchor
	if p._tether_hook_pos.distance_to(anchor_a_pos) > GRAPPLE_MAX_ROPE_LEN:
		# Failed — cancel tether, go back to swinging
		p._grapple_state = GrappleState.SWINGING


# -- Grapple Drawing -----------------------------------------------------------

var _hud_aura_fade: float = 0.0  # 1.0 = fully visible, fades to 0 over 1s



func _draw_grapple() -> void:
	# Always draw run/dash visuals (even when grapple is idle)
	_draw_dash_trail()
	_draw_run_particles()
	_draw_stick_viz()

	if p._grapple_state == GrappleState.IDLE:
		return

	var rope_color := Color(0.5, 0.4, 0.3, 0.8)
	var hook_color := Color(0.6, 0.5, 0.35)

	match p._grapple_state:
		GrappleState.WINDUP:
			# Draw hook orbiting
			var hook_local: Vector2 = p._grapple_hook_pos - p.global_position
			p.draw_line(Vector2.ZERO, hook_local, rope_color, 2.0)
			p.draw_circle(hook_local, 4.0, hook_color)

			# Draw aim direction indicator (dotted line showing throw trajectory)
			var aim: Vector2 = p._grapple_locked_aim
			var throw_speed: float = clampf(
				GRAPPLE_BASE_THROW_SPEED + p._grapple_hold_time * GRAPPLE_THROW_SPEED_PER_SEC,
				GRAPPLE_BASE_THROW_SPEED, GRAPPLE_MAX_THROW_SPEED
			)
			var vp_size: Vector2 = p.get_viewport_rect().size
			var max_indicator: float = minf(vp_size.x, vp_size.y) * 0.3
			var indicator_len: float = minf(throw_speed * 0.06, max_indicator)
			var aim_color := Color(1.0, 0.8, 0.2, 0.4)
			# Dotted line: draw segments with gaps
			var dash_len: float = 8.0
			var gap_len: float = 6.0
			var total: float = 0.0
			while total < indicator_len:
				var seg_start: Vector2 = aim * total
				var seg_end: Vector2 = aim * minf(total + dash_len, indicator_len)
				p.draw_line(seg_start, seg_end, aim_color, 1.5)
				total += dash_len + gap_len
			# Arrowhead at the end
			var arrow_tip: Vector2 = aim * indicator_len
			var perp: Vector2 = Vector2(-aim.y, aim.x)
			p.draw_line(arrow_tip, arrow_tip - aim * 8.0 + perp * 5.0, aim_color, 1.5)
			p.draw_line(arrow_tip, arrow_tip - aim * 8.0 - perp * 5.0, aim_color, 1.5)

		GrappleState.THROWN:
			# Draw rope trailing behind hook
			if p._grapple_rope_points.size() >= 2:
				for i in range(p._grapple_rope_points.size() - 1):
					var a: Vector2 = p._grapple_rope_points[i] - p.global_position
					var b: Vector2 = p._grapple_rope_points[i + 1] - p.global_position
					p.draw_line(a, b, rope_color, 2.0)
			var hook_local: Vector2 = p._grapple_hook_pos - p.global_position
			p.draw_circle(hook_local, 4.0, hook_color)

		GrappleState.CONNECTED, GrappleState.SWINGING:
			# Draw rope from player to anchor with physics-based slack
			var anchor_local: Vector2 = p._grapple_anchor - p.global_position
			var straight_dist: float = anchor_local.length()
			# Slack = how much extra rope vs straight-line distance
			var slack: float = maxf(p._grapple_rope_len - straight_dist, 0.0)
			var seg_count: int = maxi(int(p._grapple_rope_len / GRAPPLE_ROPE_SEGMENT_LEN), 3)
			var prev_pt: Vector2 = Vector2.ZERO
			for i in range(1, seg_count + 1):
				var t: float = float(i) / float(seg_count)
				var pt: Vector2 = Vector2.ZERO.lerp(anchor_local, t)
				# Catenary-like sag: more slack = more droop, weighted toward middle
				var sag_amount: float = slack * 0.5 + 5.0  # Always slight sag + slack contribution
				pt.y += sin(t * PI) * sag_amount
				p.draw_line(prev_pt, pt, rope_color, 2.0)
				prev_pt = pt
			p.draw_circle(anchor_local, 5.0, hook_color)

		GrappleState.SLIDE:
			# Draw slack rope from player to anchor — droops with catenary sag
			var slide_anchor: Vector2 = p._grapple_anchor - p.global_position
			var slide_dist: float = slide_anchor.length()
			var slide_slack: float = maxf(p._grapple_rope_len - slide_dist, 0.0)
			var slide_segs: int = maxi(int(p._grapple_rope_len / GRAPPLE_ROPE_SEGMENT_LEN), 3)
			var slide_prev: Vector2 = Vector2.ZERO
			for i in range(1, slide_segs + 1):
				var t: float = float(i) / float(slide_segs)
				var pt: Vector2 = Vector2.ZERO.lerp(slide_anchor, t)
				var sag: float = slide_slack * 0.5 + 5.0
				pt.y += sin(t * PI) * sag
				p.draw_line(slide_prev, pt, rope_color, 2.0)
				slide_prev = pt
			p.draw_circle(slide_anchor, 5.0, hook_color)

		GrappleState.SLIDE_FREE:
			# Rope detached at taut — draw fading, dangling rope from anchor
			var free_anchor: Vector2 = p._grapple_anchor - p.global_position
			var fade_col := rope_color * Color(1, 1, 1, 0.4)
			p.draw_line(Vector2.ZERO, free_anchor, fade_col, 1.5)
			p.draw_circle(free_anchor, 4.0, hook_color * Color(1, 1, 1, 0.4))

		GrappleState.RETRACTING:
			var hook_local: Vector2 = p._grapple_hook_pos - p.global_position
			p.draw_line(Vector2.ZERO, hook_local, rope_color * Color(1, 1, 1, 0.5), 1.5)
			p.draw_circle(hook_local, 3.0, hook_color * Color(1, 1, 1, 0.5))

		GrappleState.TETHER_WINDUP:
			# Draw primary rope (player to anchor A) — same as SWINGING
			var anchor_local: Vector2 = p._grapple_anchor - p.global_position
			var straight_dist: float = anchor_local.length()
			var slack: float = maxf(p._grapple_rope_len - straight_dist, 0.0)
			var seg_count: int = maxi(int(p._grapple_rope_len / GRAPPLE_ROPE_SEGMENT_LEN), 3)
			var prev_pt: Vector2 = Vector2.ZERO
			for i in range(1, seg_count + 1):
				var t: float = float(i) / float(seg_count)
				var pt: Vector2 = Vector2.ZERO.lerp(anchor_local, t)
				pt.y += sin(t * PI) * (slack * 0.5 + 5.0)
				p.draw_line(prev_pt, pt, rope_color, 2.0)
				prev_pt = pt
			p.draw_circle(anchor_local, 5.0, hook_color)
			# Draw second hook spinning at PLAYER (orbiting player)
			var tether_hook_local: Vector2 = p._tether_hook_pos - p.global_position
			p.draw_line(Vector2.ZERO, tether_hook_local, Color(0.6, 0.4, 0.8, 0.8), 1.5)
			p.draw_circle(tether_hook_local, 4.0, Color(0.7, 0.5, 0.9))
			# Draw aim arrow (same as normal windup)
			var aim: Vector2 = p._grapple_locked_aim
			var throw_speed: float = clampf(
				GRAPPLE_BASE_THROW_SPEED + p._tether_hold_time * GRAPPLE_THROW_SPEED_PER_SEC,
				GRAPPLE_BASE_THROW_SPEED, GRAPPLE_MAX_THROW_SPEED
			)
			var vp_size: Vector2 = p.get_viewport_rect().size
			var max_indicator: float = minf(vp_size.x, vp_size.y) * 0.3
			var indicator_len: float = minf(throw_speed * 0.06, max_indicator)
			var aim_color := Color(1.0, 0.6, 0.2, 0.4)
			var dash_len: float = 8.0
			var gap_len: float = 6.0
			var total: float = 0.0
			while total < indicator_len:
				var seg_start: Vector2 = aim * total
				var seg_end: Vector2 = aim * minf(total + dash_len, indicator_len)
				p.draw_line(seg_start, seg_end, aim_color, 1.5)
				total += dash_len + gap_len
			var arrow_tip: Vector2 = aim * indicator_len
			var perp: Vector2 = Vector2(-aim.y, aim.x)
			p.draw_line(arrow_tip, arrow_tip - aim * 8.0 + perp * 5.0, aim_color, 1.5)
			p.draw_line(arrow_tip, arrow_tip - aim * 8.0 - perp * 5.0, aim_color, 1.5)

		GrappleState.TETHER_THROWN:
			# Draw primary rope (player to anchor A)
			var anchor_local: Vector2 = p._grapple_anchor - p.global_position
			var straight_dist: float = anchor_local.length()
			var slack: float = maxf(p._grapple_rope_len - straight_dist, 0.0)
			var seg_count: int = maxi(int(p._grapple_rope_len / GRAPPLE_ROPE_SEGMENT_LEN), 3)
			var prev_pt: Vector2 = Vector2.ZERO
			for i in range(1, seg_count + 1):
				var t: float = float(i) / float(seg_count)
				var pt: Vector2 = Vector2.ZERO.lerp(anchor_local, t)
				pt.y += sin(t * PI) * (slack * 0.5 + 5.0)
				p.draw_line(prev_pt, pt, rope_color, 2.0)
				prev_pt = pt
			p.draw_circle(anchor_local, 5.0, hook_color)
			# Draw second hook flying from PLAYER
			var tether_hook_local: Vector2 = p._tether_hook_pos - p.global_position
			p.draw_line(Vector2.ZERO, tether_hook_local, Color(0.6, 0.4, 0.8, 0.8), 2.0)
			p.draw_circle(tether_hook_local, 4.0, Color(0.7, 0.5, 0.9))

	# Draw tether inventory dots (5 brown dots)
	if p.character_class == PlayerManager.CharacterClass.RANGED:
		var dot_start: Vector2 = Vector2(-12, -30)
		for di in range(3):
			var dot_pos: Vector2 = dot_start + Vector2(di * 6, 0)
			if di < 3 - p._active_tethers.size():
				p.draw_circle(dot_pos, 2.0, Color(0.5, 0.4, 0.3, 0.9))  # Solid = available
			else:
				p.draw_circle(dot_pos, 2.0, Color(0.5, 0.4, 0.3, 0.3))  # Dim = in use
				p.draw_arc(dot_pos, 2.0, 0, TAU, 8, Color(0.5, 0.4, 0.3, 0.6), 0.5)


# -- Run/Dash Drawing ----------------------------------------------------------

func _draw_dash_trail() -> void:
	## Draw the DASH visual: green streak, yellow center highlight, sparkles.
	if _dash_trail.is_empty() and _dash_sparkles.is_empty():
		return

	# Draw streak (thick green line connecting trail points)
	if _dash_trail.size() >= 2:
		# Sort by age descending so we draw oldest first (painter's order)
		var sorted_trail: Array = _dash_trail.duplicate()
		sorted_trail.sort_custom(func(a, b): return a["age"] > b["age"])

		for i in range(sorted_trail.size() - 1):
			var a_data: Dictionary = sorted_trail[i]
			var b_data: Dictionary = sorted_trail[i + 1]
			var a_local: Vector2 = a_data["pos"] - p.global_position
			var b_local: Vector2 = b_data["pos"] - p.global_position
			var alpha_a: float = 1.0 - (a_data["age"] / DASH_TRAIL_MAX_AGE)
			var alpha_b: float = 1.0 - (b_data["age"] / DASH_TRAIL_MAX_AGE)
			var alpha: float = minf(alpha_a, alpha_b)
			if alpha <= 0.0:
				continue

			# Outer green streak (thick)
			var green := Color(0.2, 0.9, 0.3, alpha * 0.6)
			p.draw_line(a_local, b_local, green, 8.0)

			# Yellow center highlight (thin, bright)
			var yellow := Color(1.0, 0.95, 0.3, alpha * 0.9)
			p.draw_line(a_local, b_local, yellow, 3.0)

	# Draw sparkles
	for spark in _dash_sparkles:
		var alpha: float = 1.0 - (spark["age"] / spark["max_age"])
		if alpha <= 0.0:
			continue
		var spark_local: Vector2 = spark["pos"] - p.global_position
		var radius: float = lerpf(2.5, 0.5, spark["age"] / spark["max_age"])
		if spark["yellow"]:
			# Yellow streak sparkle
			p.draw_circle(spark_local, radius, Color(1.0, 0.95, 0.3, alpha * 0.8))
		else:
			# Green outer sparkle
			p.draw_circle(spark_local, radius, Color(0.3, 1.0, 0.4, alpha * 0.7))


func _draw_run_particles() -> void:
	## Draw smoke puffs from running.
	for particle in _run_particles:
		var t: float = particle["age"] / particle["max_age"]
		if t >= 1.0:
			continue
		var alpha: float = 1.0 - t
		var radius: float = particle["radius"] * (1.0 + t * 0.8)  # Expand slightly
		var local_pos: Vector2 = particle["pos"] - p.global_position
		# Smoke: light gray, fading
		p.draw_circle(local_pos, radius, Color(0.75, 0.72, 0.68, alpha * 0.5))


# -- Stick Visualizer ----------------------------------------------------------

func _stick_viz_update(h_raw: float, delta: float) -> void:
	## Record raw stick position for the heat trail each frame.
	var v_raw: float = 0.0
	if p.device_id >= 0:
		v_raw = Input.get_joy_axis(p.device_id, JOY_AXIS_LEFT_Y)
	else:
		if p._is_device_action_pressed("move_up"): v_raw -= 1.0
		if p._is_device_action_pressed("move_down"): v_raw += 1.0

	# Only record when stick is off-center
	if absf(h_raw) > 0.05 or absf(v_raw) > 0.05:
		_stick_trail.append({"x": h_raw, "y": v_raw, "age": 0.0})

	# Age and cull trail
	var i: int = _stick_trail.size() - 1
	while i >= 0:
		_stick_trail[i]["age"] += delta
		if _stick_trail[i]["age"] >= STICK_TRAIL_MAX_AGE:
			_stick_trail.remove_at(i)
		i -= 1


func _draw_stick_viz() -> void:
	## Thumbstick visualizer: square frame, crosshair, raw dot, smoothed ring, heat trail.
	if not DebugOverlay.should_draw("player/stick_viz", p):
		return

	var S: float = STICK_VIZ_SIZE  # Half-size
	# Center on the player (local coords = 0,0)
	var cx := 0.0
	var cy := 0.0

	# -- Background: translucent dark square --
	var bg := Rect2(cx - S, cy - S, S * 2.0, S * 2.0)
	p.draw_rect(bg, Color(0.0, 0.0, 0.0, 0.25))

	# -- Border --
	p.draw_rect(bg, Color(1.0, 1.0, 1.0, 0.3), false, 1.0)

	# -- Crosshair lines (translucent) --
	var xhair_col := Color(1.0, 1.0, 1.0, 0.15)
	p.draw_line(Vector2(cx - S, cy), Vector2(cx + S, cy), xhair_col, 1.0)  # Horizontal
	p.draw_line(Vector2(cx, cy - S), Vector2(cx, cy + S), xhair_col, 1.0)  # Vertical

	# -- Min/max vertical extent lines (90% threshold) --
	var thresh_y: float = 0.9 * S
	var thresh_col := Color(0.3, 0.8, 1.0, 0.2)
	# Horizontal threshold lines at ±90%
	p.draw_line(Vector2(cx - S, cy - thresh_y), Vector2(cx + S, cy - thresh_y), thresh_col, 1.0)
	p.draw_line(Vector2(cx - S, cy + thresh_y), Vector2(cx + S, cy + thresh_y), thresh_col, 1.0)
	# Vertical threshold lines at ±90% (run threshold)
	p.draw_line(Vector2(cx - thresh_y, cy - S), Vector2(cx - thresh_y, cy + S), thresh_col, 1.0)
	p.draw_line(Vector2(cx + thresh_y, cy - S), Vector2(cx + thresh_y, cy + S), thresh_col, 1.0)

	# -- Heat trail: older = cooler color, newer = hotter --
	for pt in _stick_trail:
		var t: float = pt["age"] / STICK_TRAIL_MAX_AGE
		if t >= 1.0:
			continue
		var px: float = cx + pt["x"] * S
		var py: float = cy + pt["y"] * S
		# Heat color: white-hot → yellow → red → dim red
		var heat_col: Color
		if t < 0.25:
			heat_col = Color(1.0, 1.0, 1.0 - t * 4.0, 0.6 * (1.0 - t))  # White → yellow
		elif t < 0.6:
			var t2: float = (t - 0.25) / 0.35
			heat_col = Color(1.0, 1.0 - t2 * 0.7, 0.0, 0.5 * (1.0 - t))  # Yellow → red
		else:
			var t3: float = (t - 0.6) / 0.4
			heat_col = Color(0.8 - t3 * 0.5, 0.3 - t3 * 0.3, 0.0, 0.3 * (1.0 - t))  # Red → dim
		var radius: float = lerpf(2.0, 0.5, t)
		p.draw_circle(Vector2(px, py), radius, heat_col)

	# -- Smoothed deflection ring (shows the filtered value used for run threshold) --
	var smooth_radius: float = _smoothed_deflection * S
	p.draw_arc(Vector2(cx, cy), smooth_radius, 0, TAU, 24, Color(0.3, 0.8, 1.0, 0.35), 1.5)

	# -- Raw stick dot (current position, bright) --
	var raw_h: float = _get_h_raw()
	var raw_v: float = 0.0
	if p.device_id >= 0:
		raw_v = Input.get_joy_axis(p.device_id, JOY_AXIS_LEFT_Y)
	var dot_x: float = cx + raw_h * S
	var dot_y: float = cy + raw_v * S
	var dot_col := Color.WHITE
	if _is_running or _run_airborne:
		dot_col = Color(0.3, 1.0, 0.4)  # Green when running
	elif _is_dashing:
		dot_col = Color(1.0, 0.95, 0.3)  # Yellow when dashing
	p.draw_circle(Vector2(dot_x, dot_y), 3.0, dot_col)

	# -- Mode label --
	var mode_text: String = "WALK"
	var mode_col := Color(0.7, 0.7, 0.7, 0.6)
	if _is_dashing:
		mode_text = "DASH"
		mode_col = Color(1.0, 0.95, 0.3, 0.8)
	elif _is_running or _run_airborne:
		mode_text = "RUN"
		mode_col = Color(0.3, 1.0, 0.4, 0.8)
	p.draw_string(ThemeDB.fallback_font, Vector2(cx - S, cy - S - 4), mode_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, mode_col)

	# -- Deflection % label --
	var defl_text: String = "%.0f%% (s:%.0f%%)" % [_get_h_deflection() * 100, _smoothed_deflection * 100]
	p.draw_string(ThemeDB.fallback_font, Vector2(cx - S, cy + S + 10), defl_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.7, 0.7, 0.7, 0.5))


# -- Ranger Reload -------------------------------------------------------------

func _handle_ranger_reload(delta: float) -> void:
	if p.character_class != PlayerManager.CharacterClass.RANGED:
		return

	# Press Circle (interact) to start/continue reloading
	if p._is_device_action_pressed("interact") and p._ranger_arrows < RANGER_MAX_ARROWS:
		if not p._ranger_reloading:
			p._ranger_reloading = true
			p._ranger_reload_timer = RANGER_RELOAD_TIME
	elif not p._is_device_action_pressed("interact"):
		# Released Circle - stop reloading
		p._ranger_reloading = false
		p._ranger_reload_timer = RANGER_RELOAD_TIME
		return

	if not p._ranger_reloading:
		return

	p._ranger_reload_timer -= delta
	if p._ranger_reload_timer <= 0.0:
		# Reload one arrow
		p._ranger_arrows = mini(p._ranger_arrows + 1, RANGER_MAX_ARROWS)
		AudioManager.play("reload_click")

		# Small arrow VFX
		var arrow_text := Label.new()
		arrow_text.text = "%d/%d" % [p._ranger_arrows, RANGER_MAX_ARROWS]
		arrow_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		arrow_text.add_theme_font_size_override("font_size", 8)
		arrow_text.modulate = Color(0.3, 0.8, 0.3)
		arrow_text.position = p.global_position + Vector2(-10, -35)
		arrow_text.z_index = 12
		get_parent().add_child(arrow_text)
		var tt := arrow_text.create_tween()
		tt.tween_property(arrow_text, "position:y", arrow_text.position.y - 10, 0.4)
		tt.parallel().tween_property(arrow_text, "modulate:a", 0.0, 0.4)
		tt.tween_callback(arrow_text.queue_free)

		if p._ranger_arrows < RANGER_MAX_ARROWS:
			p._ranger_reload_timer = RANGER_RELOAD_TIME
		else:
			p._ranger_reloading = false


# -- Archer Aimed Shot ---------------------------------------------------------



# -- Archer Aimed Shot ---------------------------------------------------------

func _handle_archer_aim(delta: float) -> void:
	if p.character_class != PlayerManager.CharacterClass.RANGED:
		p._archer_aiming = false
		return

	# L2 analog trigger
	var l2_pressed: bool = false
	var r2_pressed: bool = false
	l2_pressed = p._is_trigger_pressed(JOY_AXIS_TRIGGER_LEFT)
	r2_pressed = p._is_trigger_pressed(JOY_AXIS_TRIGGER_RIGHT)

	# DEBUG: log trigger state when triggers are active
	if l2_pressed or r2_pressed:
		var l2_val: float = Input.get_joy_axis(p.device_id, JOY_AXIS_TRIGGER_LEFT) if p.device_id >= 0 else (1.0 if l2_pressed else 0.0)
		var r2_val: float = Input.get_joy_axis(p.device_id, JOY_AXIS_TRIGGER_RIGHT) if p.device_id >= 0 else (1.0 if r2_pressed else 0.0)
		DebugOverlay.log("player/archer_triggers", p,
			"L2=%.3f R2=%.3f pressed=%s,%s aiming=%s ret=(%.0f,%.0f)",
			[l2_val, r2_val, l2_pressed, r2_pressed, p._archer_aiming, p._archer_reticle_pos.x, p._archer_reticle_pos.y])

	# Tick debug trails
	var trail_i: int = p._archer_debug_trails.size() - 1
	while trail_i >= 0:
		p._archer_debug_trails[trail_i]["time"] -= delta
		if p._archer_debug_trails[trail_i]["time"] <= 0.0:
			p._archer_debug_trails.remove_at(trail_i)
		trail_i -= 1

	if l2_pressed:
		if not p._archer_aiming:
			# L2 pressed — enter aim mode
			p._archer_aiming = true
			p._archer_aim_hold_time = 0.0
			p._archer_has_solution = false
			p._archer_arc_points.clear()
			p._archer_lock_timer = 0.0
			p._archer_fired_this_pull = false

			# Clamp reticle onto visible screen if it was off-screen
			var cam = p.get_viewport().get_camera_2d()
			if cam:
				var vp_size: Vector2 = p.get_viewport_rect().size
				var zoom: Vector2 = cam.zoom if cam.zoom.x > 0 else Vector2.ONE
				var half_view: Vector2 = vp_size / (2.0 * zoom)
				var cam_pos: Vector2 = cam.global_position
				p._archer_reticle_pos.x = clampf(p._archer_reticle_pos.x, cam_pos.x - half_view.x, cam_pos.x + half_view.x)
				p._archer_reticle_pos.y = clampf(p._archer_reticle_pos.y, cam_pos.y - half_view.y, cam_pos.y + half_view.y)
			# If reticle was never set (first time), place in front of player
			if p._archer_reticle_pos == Vector2.ZERO:
				p._archer_reticle_pos = p.global_position + Vector2(100.0 if p._facing_right else -100.0, -50.0)

		# Move reticle with right stick (no range clamp — can go anywhere on screen)
		var reticle_input := Vector2.ZERO
		if p.device_id >= 0:
			reticle_input = Vector2(
				Input.get_joy_axis(p.device_id, JOY_AXIS_RIGHT_X),
				Input.get_joy_axis(p.device_id, JOY_AXIS_RIGHT_Y)
			)
			if reticle_input.length() < 0.15:
				reticle_input = Vector2.ZERO
		else:
			if Input.is_key_pressed(KEY_LEFT):
				reticle_input.x -= 1.0
			if Input.is_key_pressed(KEY_RIGHT):
				reticle_input.x += 1.0
			if Input.is_key_pressed(KEY_UP):
				reticle_input.y -= 1.0
			if Input.is_key_pressed(KEY_DOWN):
				reticle_input.y += 1.0
		p._archer_reticle_pos += reticle_input * ARCHER_AIM_RETICLE_SPEED * delta

		# Partial trigger pull = max power cap
		var l2_amount: float = 1.0
		if p._ai_active and p._ai_triggers.get("l2", false):
			l2_amount = 1.0  # AI triggers are full-pull
		elif p.device_id >= 0:
			l2_amount = clampf(Input.get_joy_axis(p.device_id, JOY_AXIS_TRIGGER_LEFT), 0.0, 1.0)
		var trigger_max: float = lerpf(ARCHER_ARROW_MIN_SPEED, ARCHER_ARROW_MAX_SPEED, l2_amount)

		# RB: power-down while held, lock on release
		var rb_pressed: bool = false
		if p.device_id >= 0:
			rb_pressed = Input.is_joy_button_pressed(p.device_id, JOY_BUTTON_RIGHT_SHOULDER)
		else:
			rb_pressed = Input.is_key_pressed(KEY_SHIFT)

		if p._archer_power_locked:
			# Locked: charge up to locked level, then hold there
			if p._archer_arrow_speed < p._archer_locked_speed:
				p._archer_aim_hold_time += delta
				p._archer_arrow_speed = clampf(
					ARCHER_ARROW_MIN_SPEED + p._archer_aim_hold_time * ARCHER_ARROW_SPEED_RATE,
					ARCHER_ARROW_MIN_SPEED,
					minf(p._archer_locked_speed, trigger_max)
				)
			# RB while locked: unlock and start decreasing
			if rb_pressed:
				p._archer_power_locked = false
				p._archer_power_reversing = true
		else:
			if rb_pressed:
				# Power decreasing while RB held
				p._archer_power_reversing = true
				p._archer_aim_hold_time -= delta
				p._archer_aim_hold_time = maxf(p._archer_aim_hold_time, 0.0)
			elif p._archer_power_reversing:
				# RB just released — lock power at current level
				p._archer_power_locked = true
				p._archer_locked_speed = p._archer_arrow_speed
				p._archer_power_reversing = false
			else:
				# Normal power-up
				p._archer_aim_hold_time += delta

			p._archer_arrow_speed = clampf(
				ARCHER_ARROW_MIN_SPEED + p._archer_aim_hold_time * ARCHER_ARROW_SPEED_RATE,
				ARCHER_ARROW_MIN_SPEED,
				minf(ARCHER_ARROW_MAX_SPEED, trigger_max)
			)

		# Solve arc with cooldown
		p._archer_lock_timer -= delta
		if p._archer_lock_timer <= 0.0:
			p._archer_lock_timer = ARCHER_AIM_LOCK_COOLDOWN
			_archer_solve_arc()

		p._archer_gleam_timer += delta
		p.queue_redraw()

		# Auto re-string after 0.5s while L2 still held
		if p._archer_fired_this_pull and p._attack_cooldown <= 0.0:
			p._archer_fired_this_pull = false
			p._archer_power_reversing = false
			# Always reset hold time — power charges back up from zero
			# If locked, it will charge up TO the locked level then stop
			p._archer_aim_hold_time = 0.0
			p._archer_arrow_speed = ARCHER_ARROW_MIN_SPEED

		# R2 fires — requires fresh press (not held from last shot)
		if not p._archer_fired_this_pull and p._attack_cooldown <= 0.0:
			if r2_pressed and not p._archer_r2_was_pressed:
				_archer_fire_aimed()
				p._archer_fired_this_pull = true

		p._archer_r2_was_pressed = r2_pressed

	else:
		# L2 released — hide reticle
		if p._archer_aiming:
			p._archer_aiming = false
			p._archer_arc_points.clear()
			p._archer_fired_this_pull = false
			p._archer_r2_was_pressed = false
			p._archer_power_locked = false
			p._archer_power_reversing = false
			p.queue_redraw()

	# Auto-target: after 5s of reticle inactivity, target nearest enemy
	if not p._archer_aiming:
		p._archer_inactive_timer += delta
		p._archer_auto_target_cooldown -= delta
		if p._archer_inactive_timer >= 5.0 and p._archer_auto_target_cooldown <= 0.0:
			p._archer_auto_target_cooldown = 0.25
			_archer_find_nearest_enemy()
	else:
		p._archer_inactive_timer = 0.0
		p._archer_auto_target = null

	if p._archer_starburst_timer > 0.0:
		p._archer_starburst_timer -= delta
	if p._archer_auto_target or p._archer_starburst_timer > 0.0:
		p.queue_redraw()




func _archer_find_nearest_enemy() -> void:
	var best_dist: float = 600.0  # Max auto-target range
	var best_enemy: Node2D = null
	for node in get_tree().get_nodes_in_group("enemies"):
		if not node is Node2D:
			continue
		var dist: float = p.global_position.distance_to(node.global_position)
		if dist < best_dist:
			best_dist = dist
			best_enemy = node

	var target_changed: bool = best_enemy != p._archer_auto_target
	p._archer_auto_target = best_enemy
	if best_enemy:
		p._archer_reticle_pos = best_enemy.global_position
		# Only trigger starburst when target changes or first acquired
		if target_changed:
			p._archer_starburst_timer = 0.5




func _archer_solve_arc() -> void:
	## Solve for launch angle to hit reticle with a parabolic arc.
	## All math in Godot coordinates (y-down, gravity positive).
	##
	## Solve for launch angle θ given speed v, gravity g, target (dx, dy).
	## Godot coords: y-down, g positive = pulls down.
	##
	## x(t) = v·cos(θ)·t
	## y(t) = v·sin(θ)·t + ½g·t²
	## At target (dx, dy): T = dx / (v·cos(θ))
	## dy = v·sin(θ)·T + ½g·T²
	## dy = dx·tan(θ) + g·dx² / (2·v²·cos²(θ))
	## Using cos²(θ) = 1/(1+tan²(θ)), let u = tan(θ):
	## dy = dx·u + g·dx²·(1+u²) / (2v²)
	## Rearranging: (g·dx²)·u² + (2v²·dx)·u + (g·dx² - 2v²·dy) = 0
	##              ─── a ───    ─── b ───    ────── c ──────
	var target: Vector2 = p._archer_reticle_pos - p.global_position
	var dx: float = target.x
	var dy: float = target.y  # Positive = below player (y-down)
	var v: float = p._archer_arrow_speed
	var g: float = ARCHER_ARROW_GRAVITY

	p._archer_has_solution = false
	p._archer_arc_points.clear()
	var reticle_radius: float = 16.0

	# Fallback: aim directly at target
	var aim_dir: Vector2 = target.normalized() if target.length() > 1.0 else Vector2(1.0 if dx >= 0 else -1.0, 0.0)
	p._archer_solved_vx = aim_dir.x * v
	p._archer_solved_vy = aim_dir.y * v
	_build_arc_points_from_vel(p._archer_solved_vx, p._archer_solved_vy)

	if absf(dx) < 1.0:
		p._archer_solved_vx = 0.0
		p._archer_solved_vy = -v
		_build_arc_points_from_vel(0.0, -v)
		if _verify_arc_hits_target(reticle_radius):
			p._archer_has_solution = true
		return

	# Quadratic in u = tan(θ): a·u² + b·u + c = 0
	var a: float = g * dx * dx
	var b: float = 2.0 * v * v * dx
	var c: float = g * dx * dx - 2.0 * v * v * dy

	var discriminant: float = b * b - 4.0 * a * c
	if discriminant < 0:
		# No solution at this power — keep fallback
		return

	var sqrt_disc: float = sqrt(discriminant)
	var u1: float = (-b + sqrt_disc) / (2.0 * a)
	var u2: float = (-b - sqrt_disc) / (2.0 * a)

	# u = tan(θ) where θ is measured from horizontal in Godot y-down.
	# vx = v·cos(θ) = v / √(1+u²), vy = v·sin(θ) = v·u / √(1+u²)
	# vx must have same sign as dx.

	var best_vx: float = p._archer_solved_vx
	var best_vy: float = p._archer_solved_vy
	var best_dist: float = _arc_closest_distance_to_target()
	var best_hits: bool = false

	for u_val in [u1, u2]:
		var denom: float = sqrt(1.0 + u_val * u_val)
		var cvx: float = v / denom
		var cvy: float = v * u_val / denom
		# Ensure horizontal direction matches target
		if signf(cvx) != signf(dx):
			cvx = -cvx
			cvy = -cvy

		# Verify positive flight time
		var flight_time: float = dx / cvx if absf(cvx) > 0.01 else -1.0
		if flight_time < 0:
			continue

		_build_arc_points_from_vel(cvx, cvy)
		var hits: bool = _verify_arc_hits_target(reticle_radius)
		var closest: float = _arc_closest_distance_to_target()

		if (hits and not best_hits) or (hits and closest < best_dist) or (not best_hits and closest < best_dist):
			best_vx = cvx
			best_vy = cvy
			best_dist = closest
			best_hits = hits

	p._archer_solved_vx = best_vx
	p._archer_solved_vy = best_vy
	p._archer_launch_angle = atan2(best_vy, best_vx)
	p._archer_has_solution = best_hits
	_build_arc_points_from_vel(best_vx, best_vy)




func _arc_closest_distance_to_target() -> float:
	var target_local: Vector2 = p._archer_reticle_pos - p.global_position
	var closest: float = INF
	for pt in p._archer_arc_points:
		var d: float = pt.distance_to(target_local)
		if d < closest:
			closest = d
	return closest




func _verify_arc_hits_target(radius: float) -> bool:
	## Check if any point in the arc passes within radius of the reticle
	var target_local: Vector2 = p._archer_reticle_pos - p.global_position
	for pt in p._archer_arc_points:
		if pt.distance_to(target_local) <= radius:
			return true
	return false




func _build_arc_points_vertical(dy: float) -> void:
	p._archer_arc_points.clear()
	var vy: float = -p._archer_arrow_speed  # Shoot straight up
	var dt: float = 0.02
	var pos := Vector2.ZERO
	for i in range(150):
		p._archer_arc_points.append(pos)
		pos.y += vy * dt
		vy += ARCHER_ARROW_GRAVITY * dt
		if pos.y > 0 and i > 5:
			break
	p._archer_arc_points.append(pos)




func _build_arc_points_from_vel(vx: float, vy: float) -> void:
	p._archer_arc_points.clear()
	var dt: float = 0.02
	var pos := Vector2.ZERO
	var sim_vy: float = vy

	for i in range(200):
		p._archer_arc_points.append(pos)
		pos.x += vx * dt
		pos.y += sim_vy * dt
		sim_vy += ARCHER_ARROW_GRAVITY * dt

		# Stop if we've passed the target
		var to_target: Vector2 = (p._archer_reticle_pos - p.global_position)
		if pos.length() > to_target.length() * 1.3:
			break

	p._archer_arc_points.append(pos)




func _archer_fire_aimed() -> void:
	## Fire an arrow along the solved parabolic arc (does not consume ammo)
	DebugOverlay.log("player/archer_fire", p,
		"FIRE vx=%.1f vy=%.1f ret=(%.0f,%.0f) pos=(%.0f,%.0f)",
		[p._archer_solved_vx, p._archer_solved_vy,
		p._archer_reticle_pos.x, p._archer_reticle_pos.y,
		p.global_position.x, p.global_position.y])
	p._attack_cooldown = 0.5
	AudioManager.play("crossbow_shoot", 0.0, 0.8)
	p._rumble(0.4, 0.6, 0.15)
	PlayerManager.add_skill_xp(p.player_index, "attack", 3)

	var scaled_dmg: int = int(60 * PlayerManager.get_skill_bonus(p.player_index, "attack"))
	var vx: float = p._archer_solved_vx
	var vy: float = p._archer_solved_vy

	# Debug: save the solver arc trail
	if DebugOverlay.should_draw("player/archer_arcs", p) and p._archer_arc_points.size() > 1:
		var solver_trail: Array[Vector2] = []
		for pt in p._archer_arc_points:
			solver_trail.append(pt + p.global_position)  # Convert to world pos
		p._archer_debug_trails.append({
			"points": solver_trail,
			"time": 10.0,
			"color": Color(1.0, 0.6, 0.2, 0.5),  # Orange = solver arc
		})

	var projectile_scene := load("res://scenes/characters/projectile.tscn") as PackedScene
	if not projectile_scene:
		return
	var proj := projectile_scene.instantiate()
	proj.damage = scaled_dmg
	proj.speed = 0.0
	proj.direction = Vector2.ZERO
	proj.projectile_type = "crossbow_bolt"
	proj.owner_index = p.player_index
	proj._is_arc = true
	proj._arc_vel = Vector2(vx, vy)
	proj._arc_gravity = ARCHER_ARROW_GRAVITY
	# Add to scene root so projectile position is in world space
	p.get_tree().current_scene.add_child(proj)
	proj.global_position = p.global_position

	# Debug: track the actual arrow trail over time
	if DebugOverlay.should_draw("player/archer_arcs", p):
		_track_arrow_trail(proj)




func _track_arrow_trail(proj: Node2D) -> void:
	## Record the actual arrow path for debug rendering
	var trail: Array[Vector2] = []
	var trail_data := {"points": trail, "time": 10.0, "color": Color(0.2, 0.8, 1.0, 0.5)}
	p._archer_debug_trails.append(trail_data)
	# Coroutine: sample p.position each frame until arrow is gone
	while is_instance_valid(proj) and proj.is_inside_tree():
		trail_data["points"].append(proj.global_position)
		await get_tree().process_frame
	trail_data["time"] = 10.0  # Reset timer once arrow is done




func _draw_archer_aim() -> void:
	# Auto-target sense effect (portal-style: glow, subtle rays, particles)
	if p._archer_starburst_timer > 0.0 and p.character_class == PlayerManager.CharacterClass.RANGED:
		var phase: float = 1.0 - clampf(p._archer_starburst_timer / 0.5, 0.0, 1.0)
		var sense_fade: float = 1.0 - phase * phase
		var expand: float = 1.0 + phase * 0.6

		_draw_sense_effect(Vector2.ZERO, 18.0 * expand, sense_fade, phase)

		if p._archer_auto_target and is_instance_valid(p._archer_auto_target):
			var enemy_local: Vector2 = p._archer_auto_target.global_position - p.global_position
			_draw_sense_effect(enemy_local, 15.0 * expand, sense_fade * 0.8, phase)

	# Auto-target reticle (subtle crosshair on targeted enemy when not aiming)
	if not p._archer_aiming and p._archer_auto_target and is_instance_valid(p._archer_auto_target):
		if p.character_class == PlayerManager.CharacterClass.RANGED:
			var target_local: Vector2 = p._archer_auto_target.global_position - p.global_position
			var ret_alpha: float = 0.35
			var ret_color := Color(1.0, 0.85, 0.2, ret_alpha)
			p.draw_line(target_local + Vector2(-8, 0), target_local + Vector2(8, 0), ret_color, 1.5)
			p.draw_line(target_local + Vector2(0, -8), target_local + Vector2(0, 8), ret_color, 1.5)
			p.draw_circle(target_local, 6.0, Color(1.0, 0.85, 0.2, ret_alpha * 0.3))

	# -- Manual reticle (independent of auto-aim) --

	# Draw debug trails (arc solver + arrow paths) when aspect enabled
	if DebugOverlay.should_draw("player/archer_arcs", p):
		for trail in p._archer_debug_trails:
			var pts: Array = trail["points"]
			var fade: float = clampf(trail["time"] / 3.0, 0.05, 1.0)
			var col: Color = trail["color"]
			col.a *= fade
			for j in range(pts.size() - 1):
				if j % 2 == 0:  # Dotted
					var a_pt: Vector2 = pts[j] - p.global_position
					var b_pt: Vector2 = pts[j + 1] - p.global_position
					p.draw_line(a_pt, b_pt, col, 1.5)

	if not p._archer_aiming:
		# Show dim reticle at last p.position even when not aiming (ranged only)
		if p.character_class == PlayerManager.CharacterClass.RANGED and p._archer_reticle_pos != Vector2.ZERO:
			var dim_local: Vector2 = p._archer_reticle_pos - p.global_position
			var dim_col := Color(1.0, 0.3, 0.2, 0.15)
			p.draw_line(dim_local + Vector2(-12, 0), dim_local + Vector2(12, 0), dim_col, 1.5)
			p.draw_line(dim_local + Vector2(0, -12), dim_local + Vector2(0, 12), dim_col, 1.5)
			p.draw_arc(dim_local, 10.0, 0, TAU, 16, dim_col, 1.0)
		return

	var reticle_local: Vector2 = p._archer_reticle_pos - p.global_position
	var reticle_alpha: float = 1.0 if p._archer_has_solution else 0.5

	# Pull strength indicator (small bar near player)
	var pull_ratio: float = (p._archer_arrow_speed - ARCHER_ARROW_MIN_SPEED) / (ARCHER_ARROW_MAX_SPEED - ARCHER_ARROW_MIN_SPEED)
	var bar_width: float = 24.0
	var bar_height: float = 3.0
	var bar_pos := Vector2(-bar_width / 2.0, 18.0)
	p.draw_rect(Rect2(bar_pos, Vector2(bar_width, bar_height)), Color(0.3, 0.3, 0.3, 0.6))
	var fill_color := Color(0.3, 0.8, 0.3).lerp(Color(1.0, 0.3, 0.1), pull_ratio)
	p.draw_rect(Rect2(bar_pos, Vector2(bar_width * pull_ratio, bar_height)), fill_color)

	# Lock indicator: small white tick mark on the bar showing locked level
	if p._archer_power_locked:
		var lock_ratio: float = (p._archer_locked_speed - ARCHER_ARROW_MIN_SPEED) / (ARCHER_ARROW_MAX_SPEED - ARCHER_ARROW_MIN_SPEED)
		var lock_x: float = bar_pos.x + bar_width * lock_ratio
		p.draw_line(Vector2(lock_x, bar_pos.y - 2.0), Vector2(lock_x, bar_pos.y + bar_height + 2.0), Color(1.0, 1.0, 1.0, 0.9), 2.0)
		# Small lock icon (diamond shape)
		var diamond_y: float = bar_pos.y - 4.0
		p.draw_line(Vector2(lock_x, diamond_y - 3.0), Vector2(lock_x + 2.0, diamond_y), Color(1.0, 0.9, 0.3), 1.5)
		p.draw_line(Vector2(lock_x + 2.0, diamond_y), Vector2(lock_x, diamond_y + 3.0), Color(1.0, 0.9, 0.3), 1.5)
		p.draw_line(Vector2(lock_x, diamond_y + 3.0), Vector2(lock_x - 2.0, diamond_y), Color(1.0, 0.9, 0.3), 1.5)
		p.draw_line(Vector2(lock_x - 2.0, diamond_y), Vector2(lock_x, diamond_y - 3.0), Color(1.0, 0.9, 0.3), 1.5)

	# Draw reticle crosshair (large, unmissable)
	var ret_color := Color(1.0, 0.1, 0.1, reticle_alpha)
	# Large filled circle
	p.draw_circle(reticle_local, 20.0, Color(1.0, 0.0, 0.0, reticle_alpha * 0.3))
	# Bright crosshair
	p.draw_line(reticle_local + Vector2(-24, 0), reticle_local + Vector2(24, 0), ret_color, 3.0)
	p.draw_line(reticle_local + Vector2(0, -24), reticle_local + Vector2(0, 24), ret_color, 3.0)
	# Circle outline
	p.draw_arc(reticle_local, 16.0, 0, TAU, 24, ret_color, 2.5)
	# Debug: print reticle p.position
	if DebugOverlay.should_draw("player/reticle_info", p):
		p.draw_string(ThemeDB.fallback_font, reticle_local + Vector2(-30, -25),
			"RET(%.0f,%.0f)" % [p._archer_reticle_pos.x, p._archer_reticle_pos.y],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.RED)

	# Gleam/sparkle when solution found
	if p._archer_has_solution:
		var sparkle_count := 4
		for i in range(sparkle_count):
			var angle: float = p._archer_gleam_timer * 3.0 + i * TAU / sparkle_count
			var sparkle_pos: Vector2 = reticle_local + Vector2(cos(angle), sin(angle)) * 12.0
			var sparkle_alpha: float = 0.5 + 0.5 * sin(p._archer_gleam_timer * 8.0 + i * 1.5)
			p.draw_circle(sparkle_pos, 2.0, Color(1.0, 0.9, 0.3, sparkle_alpha))

	# Draw arc when debug enabled — always, even without a solution (shows best attempt)
	if DebugOverlay.should_draw("player/archer_arcs", p) and p._archer_arc_points.size() >= 2:
		var arc_color := Color(0.2, 1.0, 0.3, 0.5) if p._archer_has_solution else Color(1.0, 0.3, 0.2, 0.35)
		for i in range(p._archer_arc_points.size() - 1):
			if i % 3 == 0:
				continue
			var a: Vector2 = p._archer_arc_points[i]
			var b: Vector2 = p._archer_arc_points[i + 1]
			p.draw_line(a, b, arc_color, 1.5)




func _draw_sense_effect(center: Vector2, radius: float, alpha_mult: float, anim_phase: float) -> void:
	## Portal-style sense effect: circular gradients, subtle rays, particles
	var gold := Color(1.0, 0.85, 0.2)
	var t: float = Time.get_ticks_msec() * 0.001

	# Outer glow circle (large, very dim)
	p.draw_circle(center, radius * 1.8, gold * Color(1, 1, 1, alpha_mult * 0.06))
	# Mid glow
	p.draw_circle(center, radius * 1.2, gold * Color(1, 1, 1, alpha_mult * 0.12))
	# Inner glow (brighter)
	p.draw_circle(center, radius * 0.7, gold * Color(1, 1, 1, alpha_mult * 0.2))
	# Core
	p.draw_circle(center, radius * 0.3, gold * Color(1, 1, 1, alpha_mult * 0.3))

	# Subtle radiating rays (thin, varying length)
	var n_rays: int = 6
	for i in range(n_rays):
		var angle: float = float(i) / float(n_rays) * TAU + t * 0.4 + anim_phase * 2.0
		var ray_len: float = radius * (0.8 + 0.4 * sin(t * 3.0 + i * 1.7))
		var ray_alpha: float = alpha_mult * (0.15 + 0.1 * sin(t * 5.0 + i * 2.3))
		p.draw_line(center + Vector2(cos(angle), sin(angle)) * radius * 0.5,
				  center + Vector2(cos(angle), sin(angle)) * (radius * 0.5 + ray_len),
				  gold * Color(1, 1, 1, ray_alpha), 1.0)

	# Randomized particles (small dots scattered around, using deterministic noise)
	for i in range(5):
		var seed_f: float = float(i) * 127.1 + anim_phase * 50.0
		var px: float = fmod(sin(seed_f) * 43758.5, 1.0) * 2.0 - 1.0
		var py: float = fmod(sin(seed_f * 1.3 + 311.7) * 43758.5, 1.0) * 2.0 - 1.0
		var particle_pos: Vector2 = center + Vector2(px, py) * radius * 1.5
		var particle_alpha: float = alpha_mult * (0.3 + 0.2 * sin(t * 7.0 + i * 3.1))
		var particle_size: float = 1.5 + sin(t * 4.0 + i) * 0.5
		p.draw_circle(particle_pos, particle_size, gold * Color(1, 1, 1, particle_alpha))


# -- Rogue Stealth -------------------------------------------------------------

