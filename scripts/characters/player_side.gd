extends CharacterBody2D

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
}

enum AnimFrame { IDLE = 0, WALK1 = 1, WALK2 = 2, JUMP = 3, ATTACK1 = 4, ATTACK2 = 5 }

@export var player_index: int = 0
@export var device_id: int = -1
@export var character_class: PlayerManager.CharacterClass = PlayerManager.CharacterClass.MELEE

# Jump height = v^2 / (2*g). With v=550, g=900: max height ~168px
const GRAVITY := 900.0
const JUMP_VELOCITY := -550.0
const WALL_JUMP_VELOCITY := Vector2(250.0, -480.0)
const WALK_ANIM_FPS := 8.0
const ATTACK_DURATION := 0.3
const ATTACK_COOLDOWN_TIME := 0.4
const SPECIAL_COOLDOWN_TIME := 1.5

var _facing_right: bool = true
var _walk_timer: float = 0.0
var _walk_frame_toggle: bool = false
var _is_attacking: bool = false
var _attack_timer: float = 0.0
var _attack_cooldown: float = 0.0
var _special_cooldown: float = 0.0
var _is_wall_sliding: bool = false
var _wall_jump_stamina: int = 3
const WALL_JUMP_STAMINA_MAX: int = 3
var _donut_buddy_count: int = 0
var _shadow_dash_active: bool = false
var _is_dead: bool = false

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
const DELEGATE_SPEED_MULT := 1.5
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

# Controller state tracking
var _controller_actions: Dictionary = {}
var _controller_just_pressed: Dictionary = {}

const HEALTH_BAR_SCENE := preload("res://scenes/ui/health_bar.tscn")

@onready var sprite: Sprite2D = $Sprite
@onready var collision_shape: CollisionShape2D = $CollisionShape
@onready var player_label: Label = $PlayerLabel
@onready var attack_area: Area2D = $AttackArea

var _health_bar: Node2D = null
var _mana_bar: Node2D = null


func _ready() -> void:
	add_to_group("players")
	_apply_class_sprite()
	player_label.text = "P" + str(player_index + 1)
	_setup_health_bar()
	_setup_mana_bar()
	# Load demolitionist upgrades from persistent state
	_demo_aspect = PlayerManager.demo_aspect
	_demo_power_tier = PlayerManager.demo_power_tier
	_demo_size_tier = PlayerManager.demo_size_tier
	_demo_napalm = PlayerManager.demo_napalm


func setup(p_index: int, p_device_id: int, p_class: PlayerManager.CharacterClass) -> void:
	player_index = p_index
	device_id = p_device_id
	character_class = p_class
	if is_inside_tree():
		_apply_class_sprite()
		player_label.text = "P" + str(player_index + 1)


func _apply_class_sprite() -> void:
	if CLASS_SPRITES.has(character_class):
		sprite.texture = load(CLASS_SPRITES[character_class])
	sprite.hframes = 6
	sprite.vframes = 1
	sprite.frame = AnimFrame.IDLE


# -- Input helpers -------------------------------------------------------------

func _is_device_action_pressed(action: String) -> bool:
	if device_id == -1:
		return Input.is_action_pressed(action)
	return _controller_actions.get(action, false)


func _is_device_action_just_pressed(action: String) -> bool:
	if device_id == -1:
		return Input.is_action_just_pressed(action)
	return _controller_just_pressed.get(action, false)


func _input(event: InputEvent) -> void:
	if device_id == -1:
		return
	if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	if event.device != device_id:
		return

	for action in ["move_left", "move_right", "jump", "attack", "special", "block", "interact"]:
		if event.is_action_pressed(action):
			_controller_actions[action] = true
			_controller_just_pressed[action] = true
		elif event.is_action_released(action):
			_controller_actions[action] = false


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)

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
	_handle_wall_slide(delta)
	_handle_charge(delta)
	_check_ground_slam_landing()
	_update_health_bar()
	_handle_attack(delta)
	_handle_special()
	_update_animation(delta)
	move_and_slide()

	# Clear AFTER all checks so button presses are actually read
	_controller_just_pressed.clear()


func _update_cooldowns(delta: float) -> void:
	if _attack_cooldown > 0.0:
		_attack_cooldown -= delta
	if _special_cooldown > 0.0:
		_special_cooldown -= delta


# -- Physics -------------------------------------------------------------------

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * delta
		velocity.y = min(velocity.y, 600.0)  # Terminal velocity


func _handle_movement() -> void:
	# Healer cannot move while channeling
	if _is_charging and character_class == PlayerManager.CharacterClass.HEALER:
		velocity.x = 0.0
		return

	var h_input := 0.0
	if _is_device_action_pressed("move_left"):
		h_input -= 1.0
	if _is_device_action_pressed("move_right"):
		h_input += 1.0

	var speed: float = PlayerManager.get_player(player_index).get("speed", 100)
	if _is_blocking:
		speed *= 0.5
	velocity.x = h_input * speed

	if h_input != 0.0:
		_facing_right = h_input > 0.0
		sprite.flip_h = not _facing_right


func _handle_jump() -> void:
	# Reset wall jump stamina when on the floor
	if is_on_floor():
		_wall_jump_stamina = WALL_JUMP_STAMINA_MAX

	if not _is_device_action_just_pressed("jump"):
		return

	if is_on_floor():
		velocity.y = JUMP_VELOCITY
		AudioManager.play("jump", -5.0)
	elif _is_wall_sliding:
		if _wall_jump_stamina <= 0:
			# Out of wall jump stamina - flash red to indicate
			_flash_wall_jump_exhausted()
			return
		_wall_jump_stamina -= 1
		_wall_jump()
		AudioManager.play("jump", -5.0, 1.2)
		if _wall_jump_stamina <= 0:
			_flash_wall_jump_exhausted()


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

	_attack_cooldown = ATTACK_COOLDOWN_TIME
	_is_attacking = true
	_attack_timer = ATTACK_DURATION
	_perform_attack()


func _perform_attack() -> void:
	match character_class:
		PlayerManager.CharacterClass.MELEE:
			_attack_melee()
		PlayerManager.CharacterClass.RANGED:
			_attack_ranged()
		PlayerManager.CharacterClass.MAGE:
			_attack_mage()
		PlayerManager.CharacterClass.SUMMONER:
			_attack_summoner()
		PlayerManager.CharacterClass.ROGUE:
			_attack_rogue()
		PlayerManager.CharacterClass.DEMOLITIONIST:
			_attack_demolitionist()
		PlayerManager.CharacterClass.HEALER:
			_attack_healer()


func _attack_melee() -> void:
	# Ground slam if airborne
	if not is_on_floor():
		_start_ground_slam()
		return

	# Combo: advance if within window, reset if expired
	if _combo_timer <= 0.0:
		_combo_count = 0
	var combo_idx: int = mini(_combo_count, COMBO_DAMAGES.size() - 1)
	var damage: int = COMBO_DAMAGES[combo_idx]
	var reach: float = COMBO_RANGES[combo_idx]

	# Per-combo sound with distinct pitch
	var pitch: float = COMBO_PITCHES[combo_idx]
	var volume: float = 0.0 if combo_idx < COMBO_DAMAGES.size() - 1 else 2.0
	AudioManager.play("sword_slash", volume, pitch)

	# Spawn large arcing slash VFX with particles
	_spawn_melee_arc(reach, combo_idx)

	# Enable attack area and wait a physics frame so overlaps register
	var offset := Vector2(reach if _facing_right else -reach, 0.0)
	attack_area.position = offset
	attack_area.monitoring = true
	# Wait one physics frame for Godot to detect overlaps
	await get_tree().physics_frame
	if not is_inside_tree():
		return

	# Now check for hits
	for body in attack_area.get_overlapping_bodies():
		if body.has_method("take_damage"):
			body.take_damage(damage, player_index)
			# Blood particles on hit!
			_spawn_blood_particles(body.global_position)
		if combo_idx == COMBO_DAMAGES.size() - 1 and body.has_method("apply_knockback"):
			var kb_dir: Vector2 = Vector2(1.0 if _facing_right else -1.0, -0.3).normalized()
			body.apply_knockback(kb_dir * 200.0)

	await get_tree().create_timer(0.1).timeout
	if is_inside_tree():
		attack_area.monitoring = false

	_combo_count += 1
	_combo_timer = COMBO_WINDOW
	if _combo_count >= COMBO_DAMAGES.size():
		_combo_count = 0


func _spawn_melee_arc(reach: float, combo_idx: int) -> void:
	# Large sweeping arc made of particles
	var arc_center: Vector2 = global_position + Vector2(reach * 0.5 if _facing_right else -reach * 0.5, 0)
	var arc_dir: float = 1.0 if _facing_right else -1.0
	var colors: Array[Color] = [
		Color(0.85, 0.85, 0.9, 0.8),   # Silver
		Color(0.6, 0.6, 0.65, 0.7),    # Grey
		Color(1.0, 0.95, 0.5, 0.7),    # Yellow
		Color(1.0, 1.0, 1.0, 0.9),     # White
	]

	# Spawn arc particles along a curved path
	var particle_count: int = 12 + combo_idx * 4  # More particles for later combos
	for i in range(particle_count):
		var t: float = float(i) / float(particle_count)
		# Arc angle from -60 to +60 degrees
		var angle: float = lerpf(-1.0, 1.0, t) * arc_dir
		var arc_pos: Vector2 = global_position + Vector2(
			cos(angle) * reach * arc_dir,
			sin(angle) * reach * 0.6
		)

		var p := ColorRect.new()
		var color_idx: int = i % colors.size()
		p.color = colors[color_idx]
		var psize: float = randf_range(3.0, 6.0 + combo_idx * 2.0)
		p.size = Vector2(psize, psize)
		p.position = arc_pos - Vector2(psize / 2.0, psize / 2.0)
		p.z_index = 8
		get_parent().add_child(p)

		# Particles fly outward slightly then fade
		var fly_dir: Vector2 = (arc_pos - global_position).normalized()
		var tween := p.create_tween()
		tween.set_parallel(true)
		tween.tween_property(p, "position", p.position + fly_dir * randf_range(8.0, 20.0), 0.25)
		tween.tween_property(p, "modulate:a", 0.0, 0.3)
		tween.tween_property(p, "scale", Vector2(0.3, 0.3), 0.3)
		tween.chain().tween_callback(p.queue_free)

	# Big central arc sweep visual
	var arc_visual := ColorRect.new()
	arc_visual.color = Color(0.9, 0.9, 1.0, 0.5)
	var arc_width: float = reach * 2.0
	var arc_height: float = reach * 0.8
	arc_visual.size = Vector2(arc_width, arc_height)
	arc_visual.position = global_position + Vector2(
		-reach if not _facing_right else 0,
		-arc_height / 2.0
	)
	arc_visual.z_index = 7
	get_parent().add_child(arc_visual)

	var arc_tween := arc_visual.create_tween()
	arc_tween.set_parallel(true)
	arc_tween.tween_property(arc_visual, "modulate:a", 0.0, 0.2)
	arc_tween.tween_property(arc_visual, "scale:x", 1.3, 0.2)
	arc_tween.chain().tween_callback(arc_visual.queue_free)


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


func _attack_ranged() -> void:
	AudioManager.play("crossbow_shoot")
	_spawn_projectile(15, 350.0, "crossbow_bolt")


func _attack_mage() -> void:
	if not PlayerManager.use_mana(player_index, 10):
		return
	AudioManager.play("magic_bolt")
	_spawn_projectile(20, 300.0, "magic_bolt")


func _attack_summoner() -> void:
	AudioManager.play("staff_bonk")
	var offset := Vector2(16.0 if _facing_right else -16.0, 0.0)
	attack_area.position = offset
	attack_area.monitoring = true
	for body in attack_area.get_overlapping_bodies():
		if body.has_method("take_damage"):
			body.take_damage(8, player_index)
	await get_tree().create_timer(0.15).timeout
	if is_inside_tree():
		attack_area.monitoring = false


func _attack_rogue() -> void:
	# Throw 3 knives in a fan spread, 2s cooldown
	AudioManager.play("dagger_stab")
	_attack_cooldown = 2.0  # Override the default cooldown
	var base_dir: Vector2 = Vector2(1.0 if _facing_right else -1.0, 0.0)
	var angles := [-0.2, 0.0, 0.2]  # Fan spread in radians
	for angle in angles:
		var dir: Vector2 = base_dir.rotated(angle)
		var knife_scene := load("res://scenes/characters/projectile.tscn") as PackedScene
		if not knife_scene:
			continue
		var knife := knife_scene.instantiate()
		knife.damage = 12
		knife.speed = 400.0
		knife.direction = dir
		knife.projectile_type = "knife"
		knife.owner_index = player_index
		knife.global_position = global_position + base_dir * 12.0
		get_parent().add_child(knife)


func _spawn_projectile(damage: int, speed: float, type: String) -> void:
	var projectile_scene := load("res://scenes/characters/projectile.tscn") as PackedScene
	if not projectile_scene:
		return
	var proj := projectile_scene.instantiate()
	proj.damage = damage
	proj.speed = speed
	proj.direction = Vector2(1.0 if _facing_right else -1.0, 0.0)
	proj.projectile_type = type
	proj.owner_index = player_index
	proj.global_position = global_position + Vector2(16.0 if _facing_right else -16.0, 0.0)
	get_parent().add_child(proj)


# -- Melee Combo & Ground Slam ------------------------------------------------

func _update_combo_timer(delta: float) -> void:
	if _combo_timer > 0.0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			_combo_count = 0


func _start_ground_slam() -> void:
	_ground_slam_active = true
	velocity.y = 600.0  # Slam downward fast
	AudioManager.play("sword_slash", 0.0, 0.6)
	modulate = Color(1.0, 0.6, 0.2)  # Orange glow while falling


func _check_ground_slam_landing() -> void:
	if not _ground_slam_active:
		return
	if not is_on_floor():
		return

	_ground_slam_active = false
	modulate = Color.WHITE
	AudioManager.play("explosion", -4.0, 1.4)

	# Charge ratio determines blast radius and damage (0.0 if no charge)
	var charge_ratio: float = clampf((_charge_time - CHARGE_MIN) / (CHARGE_MAX - CHARGE_MIN), 0.0, 1.0) if _charge_time >= CHARGE_MIN else 0.0
	var blast_radius: float = lerpf(40.0, 120.0, charge_ratio) if charge_ratio > 0.0 else 80.0
	var slam_damage: int = int(lerpf(30.0, 80.0, charge_ratio)) if charge_ratio > 0.0 else _ground_slam_damage

	# Big AoE shockwave VFX - size scales with charge
	_spawn_vfx(Color(1.0, 0.5, 0.1, 0.7), Vector2(blast_radius * 2.0, 16))

	# Screen shake - briefly offset camera
	_screen_shake(charge_ratio * 8.0 + 2.0, 0.2)

	# Damage all nearby enemies on the ground
	for body in get_tree().get_nodes_in_group("enemies"):
		if not body is Node2D:
			continue
		var dist: float = global_position.distance_to(body.global_position)
		if dist < blast_radius and body.has_method("take_damage"):
			body.take_damage(slam_damage, player_index)
			if body.has_method("apply_knockback"):
				var kb: Vector2 = (body.global_position - global_position).normalized()
				body.apply_knockback(kb * 250.0)

	_charge_time = 0.0


# -- Special Abilities ---------------------------------------------------------

func _handle_special() -> void:
	if _special_cooldown > 0.0:
		return
	if not _is_device_action_just_pressed("special"):
		return

	_special_cooldown = SPECIAL_COOLDOWN_TIME
	_perform_special()


func _perform_special() -> void:
	match character_class:
		PlayerManager.CharacterClass.MELEE:
			_special_shield_charge()
		PlayerManager.CharacterClass.RANGED:
			_special_explosive_muffin()
		PlayerManager.CharacterClass.MAGE:
			_special_frosting_freeze()
		PlayerManager.CharacterClass.SUMMONER:
			_special_summon_donut()
		PlayerManager.CharacterClass.ROGUE:
			_special_shadow_dash()
		PlayerManager.CharacterClass.DEMOLITIONIST:
			_special_big_bomb()
		PlayerManager.CharacterClass.HEALER:
			_special_healing_burst()


func _special_shield_charge() -> void:
	AudioManager.play("shield_charge", 2.0, 0.9)
	var dash_speed := 600.0
	var charge_dir := Vector2(1.0 if _facing_right else -1.0, 0.0)
	velocity.x = dash_speed if _facing_right else -dash_speed
	velocity.y = -120.0  # Slight lift

	# Invincible during charge
	collision_layer = 0
	modulate = Color(0.4, 0.7, 1.0)  # Bright blue
	_spawn_vfx(Color(0.3, 0.6, 1.0, 0.8), Vector2(48, 24))

	# Dash wave - perpendicular to charge direction
	_spawn_dash_wave(global_position, charge_dir, 5)

	# Hit everything in path across multiple frames
	attack_area.monitoring = true
	var hit_bodies: Array = []
	for i in range(4):
		await get_tree().create_timer(0.05).timeout
		if not is_inside_tree():
			return
		var offset := Vector2(24.0 if _facing_right else -24.0, 0.0)
		attack_area.position = offset
		for body in attack_area.get_overlapping_bodies():
			if body in hit_bodies:
				continue
			if body.has_method("take_damage"):
				body.take_damage(35, player_index)
				hit_bodies.append(body)
			if body.has_method("apply_knockback"):
				var kb_dir: Vector2 = Vector2(1.0 if _facing_right else -1.0, -0.4).normalized()
				body.apply_knockback(kb_dir * 400.0)
		_spawn_vfx(Color(0.3, 0.6, 1.0, 0.4), Vector2(20, 28))

	if is_inside_tree():
		attack_area.monitoring = false
		collision_layer = 2
		modulate = Color.WHITE


func _special_explosive_muffin() -> void:
	AudioManager.play("explosion")
	_spawn_projectile(35, 250.0, "muffin_grenade")
	_spawn_vfx(Color(0.2, 0.9, 0.2, 0.7), Vector2(20, 20))


func _special_frosting_freeze() -> void:
	# Area slow effect - big icy burst
	if not PlayerManager.use_mana(player_index, 40):
		_special_cooldown = 0.0
		_spawn_fail_flash()
		return
	AudioManager.play("freeze")
	_spawn_vfx(Color(0.5, 0.8, 1.0, 0.5), Vector2(120, 120))
	modulate = Color(0.6, 0.9, 1.0)
	attack_area.monitoring = true
	for body in attack_area.get_overlapping_bodies():
		if body.has_method("apply_slow"):
			body.apply_slow(3.0)
	await get_tree().create_timer(0.3).timeout
	if is_inside_tree():
		attack_area.monitoring = false
		modulate = Color.WHITE


func _special_summon_donut() -> void:
	# Summon donut buddy (up to 3)
	if _donut_buddy_count >= 3:
		_special_cooldown = 0.0
		_spawn_fail_flash()
		return
	if not PlayerManager.use_mana(player_index, 30):
		_special_cooldown = 0.0
		_spawn_fail_flash()
		return

	AudioManager.play("summon")
	_spawn_vfx(Color(1.0, 0.6, 0.2, 0.7), Vector2(30, 30))
	var buddy_scene := load("res://scenes/characters/donut_buddy.tscn") as PackedScene
	if not buddy_scene:
		return
	var buddy := buddy_scene.instantiate()
	buddy.owner_index = player_index
	buddy.global_position = global_position + Vector2(24.0 if _facing_right else -24.0, 0.0)
	buddy.tree_exited.connect(func(): _donut_buddy_count -= 1)
	get_parent().add_child(buddy)
	_donut_buddy_count += 1


# -- Summoner Delegate Mode ----------------------------------------------------

func _handle_delegate_toggle() -> void:
	if character_class != PlayerManager.CharacterClass.SUMMONER:
		return
	if not _is_device_action_just_pressed("interact"):
		return

	if _delegate_active:
		_exit_delegate_mode()
	else:
		_enter_delegate_mode()


func _enter_delegate_mode() -> void:
	_delegate_active = true
	_delegate_timer = DELEGATE_DURATION
	AudioManager.play("summon", -3.0, 1.5)
	# Summoner goes into trance
	modulate = Color(0.6, 0.5, 0.8, 0.5)

	# Countdown label on the summoner
	_delegate_countdown_label = Label.new()
	_delegate_countdown_label.name = "DelegateCountdown"
	_delegate_countdown_label.text = "10"
	_delegate_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_delegate_countdown_label.add_theme_font_size_override("font_size", 14)
	_delegate_countdown_label.position = Vector2(-8, -40)
	_delegate_countdown_label.modulate = Color(0.8, 0.5, 1.0)
	add_child(_delegate_countdown_label)

	# Spawn ghost delegate
	_delegate_node = CharacterBody2D.new()
	_delegate_node.collision_layer = 0
	_delegate_node.collision_mask = 1
	_delegate_node.global_position = global_position

	var ghost_sprite := ColorRect.new()
	ghost_sprite.name = "GhostSprite"
	ghost_sprite.color = Color(0.8, 0.5, 1.0, 0.4)
	ghost_sprite.size = Vector2(12, 20)
	ghost_sprite.position = Vector2(-6, -14)
	_delegate_node.add_child(ghost_sprite)

	var glow := ColorRect.new()
	glow.name = "Glow"
	glow.color = Color(0.7, 0.4, 1.0, 0.15)
	glow.size = Vector2(20, 24)
	glow.position = Vector2(-10, -16)
	_delegate_node.add_child(glow)

	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(10, 18)
	col.shape = shape
	_delegate_node.add_child(col)

	get_parent().add_child(_delegate_node)
	_update_buddy_target()


func _exit_delegate_mode() -> void:
	if not _delegate_active:
		return
	_delegate_active = false

	var teleport_target: Vector2 = global_position
	if is_instance_valid(_delegate_node):
		teleport_target = _delegate_node.global_position

	# --- Aether Dig-In at old position ---
	AudioManager.play("explosion", -2.0, 0.5)
	_spawn_aether_rift(global_position)

	# Screen rumble
	_screen_shake(4.0, 0.2)

	# Summoner "digs into the aether" - shrink + purple flash
	modulate = Color(0.6, 0.2, 1.0)
	var dig_in := create_tween()
	dig_in.tween_property(self, "scale", Vector2(0.1, 0.1), 0.3).set_ease(Tween.EASE_IN)
	await dig_in.finished

	# --- Teleport ---
	global_position = teleport_target
	if is_instance_valid(_delegate_node):
		_delegate_node.queue_free()
		_delegate_node = null

	# --- Aether Dig-Out at new position ---
	AudioManager.play("summon", 0.0, 0.7)
	_spawn_aether_rift(global_position)
	_screen_shake(4.0, 0.2)

	# Summoner "digs out" - grow back + flash
	var dig_out := create_tween()
	dig_out.tween_property(self, "scale", Vector2(1.0, 1.0), 0.3).set_ease(Tween.EASE_OUT)
	await dig_out.finished

	modulate = Color.WHITE

	# Clean up countdown label
	if is_instance_valid(_delegate_countdown_label):
		_delegate_countdown_label.queue_free()
		_delegate_countdown_label = null

	_update_buddy_target()


func _spawn_aether_rift(pos: Vector2) -> void:
	# Purple tear in space that emits particles
	var rift := Node2D.new()
	rift.global_position = pos
	rift.z_index = 10
	get_parent().add_child(rift)

	# The rift visual - a jagged purple tear
	var tear := ColorRect.new()
	tear.color = Color(0.5, 0.1, 0.9, 0.8)
	tear.size = Vector2(6, 40)
	tear.position = Vector2(-3, -20)
	rift.add_child(tear)

	# Inner glow
	var inner := ColorRect.new()
	inner.color = Color(0.8, 0.3, 1.0, 0.5)
	inner.size = Vector2(2, 36)
	inner.position = Vector2(-1, -18)
	rift.add_child(inner)

	# Emit purple particles for 4 seconds
	var particle_count := 40
	for i in range(particle_count):
		# Stagger particle spawns
		_spawn_aether_particle_delayed(rift, pos, float(i) * 0.1)

	# Rift fades out after 4 seconds
	var rift_tween := rift.create_tween()
	rift_tween.tween_interval(4.0)
	rift_tween.tween_property(tear, "modulate:a", 0.0, 1.0)
	rift_tween.parallel().tween_property(inner, "modulate:a", 0.0, 1.0)
	rift_tween.tween_callback(rift.queue_free)


func _spawn_aether_particle_delayed(rift: Node2D, pos: Vector2, delay: float) -> void:
	if not is_inside_tree():
		return
	await get_tree().create_timer(delay).timeout
	if not is_instance_valid(rift) or not is_inside_tree():
		return

	var particle := Area2D.new()
	particle.collision_layer = 0
	particle.collision_mask = 8  # Detect enemies
	particle.global_position = pos + Vector2(randf_range(-4, 4), randf_range(-15, 15))

	var pcol := CollisionShape2D.new()
	var pshape := CircleShape2D.new()
	pshape.radius = 5.0
	pcol.shape = pshape
	particle.add_child(pcol)

	# Purple glowing dot
	var dot := ColorRect.new()
	dot.color = Color(0.7, 0.2, 1.0, 0.8)
	dot.size = Vector2(6, 6)
	dot.position = Vector2(-3, -3)
	particle.add_child(dot)

	get_parent().add_child(particle)

	# Float outward in random direction
	var vel: Vector2 = Vector2(randf_range(-40, 40), randf_range(-60, 10))
	var lifetime := 2.0
	var age := 0.0

	# Check for enemy contact
	particle.body_entered.connect(func(body: Node2D) -> void:
		if body.is_in_group("enemies") and body.has_method("_apply_aether_growth"):
			body._apply_aether_growth()
		elif body.is_in_group("enemies"):
			_apply_aether_growth_to(body)
	)

	while age < lifetime and is_instance_valid(particle):
		var dt: float = get_process_delta_time()
		age += dt
		particle.global_position += vel * dt
		vel.y += 20.0 * dt  # Slight gravity
		vel *= (1.0 - 0.5 * dt)  # Drag
		# Fade
		dot.modulate.a = lerpf(0.8, 0.0, age / lifetime)
		if not is_inside_tree():
			break
		await get_tree().process_frame

	if is_instance_valid(particle):
		particle.queue_free()


func _apply_aether_growth_to(enemy: Node2D) -> void:
	# Enemy grows 300% in size and power!
	if enemy.has_meta("aether_grown"):
		return  # Don't stack
	enemy.set_meta("aether_grown", true)

	AudioManager.play("boss_roar", -4.0, 1.5)

	# Visual: purple flash then grow
	enemy.modulate = Color(0.7, 0.3, 1.0)
	var grow_tween := enemy.create_tween()
	grow_tween.tween_property(enemy, "scale", enemy.scale * 3.0, 0.5).set_ease(Tween.EASE_OUT)
	grow_tween.parallel().tween_property(enemy, "modulate", Color(0.9, 0.6, 1.0), 0.5)

	# Buff stats if possible
	if "health" in enemy:
		enemy.health *= 3
	if "MAX_HEALTH" in enemy:
		pass  # Can't change const, but health is tripled
	# Update health bar if it has one
	if "_health_bar" in enemy and enemy._health_bar != null:
		enemy._health_bar.set_health(enemy.health, enemy.health)

	# Purple particle aura on the grown enemy
	_spawn_aether_aura(enemy)


func _spawn_aether_aura(enemy: Node2D) -> void:
	# Continuous purple particles around the empowered enemy
	for i in range(20):
		if not is_instance_valid(enemy):
			break
		var p := ColorRect.new()
		p.color = Color(0.6, 0.2, 1.0, 0.5)
		p.size = Vector2(4, 4)
		p.position = enemy.global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
		p.z_index = 5
		get_parent().add_child(p)
		var pt := p.create_tween()
		pt.tween_property(p, "position:y", p.position.y - randf_range(15, 40), 0.8)
		pt.parallel().tween_property(p, "modulate:a", 0.0, 0.8)
		pt.tween_callback(p.queue_free)
		await get_tree().create_timer(0.3).timeout


func _update_delegate(delta: float) -> void:
	if not is_instance_valid(_delegate_node):
		_exit_delegate_mode()
		return

	# Countdown timer
	_delegate_timer -= delta
	if _delegate_timer <= 0.0:
		_exit_delegate_mode()
		return

	# Update countdown display
	if is_instance_valid(_delegate_countdown_label):
		var secs: int = int(ceil(_delegate_timer))
		_delegate_countdown_label.text = str(secs)
		# Flash red when low
		if _delegate_timer <= 3.0:
			_delegate_countdown_label.modulate = Color(1.0, 0.3, 0.3) if fmod(_delegate_timer, 0.5) < 0.25 else Color(0.8, 0.5, 1.0)

	var speed: float = PlayerManager.get_player(player_index).get("speed", 95) * DELEGATE_SPEED_MULT

	# Gravity
	if not _delegate_node.is_on_floor():
		_delegate_node.velocity.y += GRAVITY * delta
		_delegate_node.velocity.y = minf(_delegate_node.velocity.y, 600.0)
	else:
		_delegate_node.velocity.y = 0.0

	# Movement
	var h_input := 0.0
	if _is_device_action_pressed("move_left"):
		h_input -= 1.0
	if _is_device_action_pressed("move_right"):
		h_input += 1.0
	_delegate_node.velocity.x = h_input * speed

	# Jump (1.5x height)
	if _is_device_action_just_pressed("jump") and _delegate_node.is_on_floor():
		_delegate_node.velocity.y = JUMP_VELOCITY * DELEGATE_JUMP_MULT
		AudioManager.play("jump", -8.0, 1.5)

	# Dash (special button)
	if _is_device_action_just_pressed("special"):
		var dash_dir := 1.0 if h_input >= 0 else -1.0
		_delegate_node.global_position.x += dash_dir * 80.0
		AudioManager.play("shadow_dash", -6.0, 1.3)

	_delegate_node.move_and_slide()

	# Pulsing glow
	var glow := _delegate_node.get_node_or_null("Glow")
	if glow:
		glow.modulate.a = 0.1 + sin(Time.get_ticks_msec() * 0.005) * 0.08

	_update_buddy_target()


func _update_buddy_target() -> void:
	# Point all donut buddies toward the delegate (or back to summoner)
	var target_node: Node2D = _delegate_node if _delegate_active and is_instance_valid(_delegate_node) else self
	for buddy in get_tree().get_nodes_in_group("donut_buddies"):
		if buddy.get("owner_index") == player_index:
			# Override the buddy's follow target
			if buddy.has_method("set_follow_target"):
				buddy.set_follow_target(target_node)
			elif "follow_target" in buddy:
				buddy.follow_target = target_node


func take_damage(amount: int, source_index: int = -1) -> void:
	if _shadow_dash_active or _is_dead:
		return

	# Delegate mode: summoner takes extra damage
	if _delegate_active:
		amount = int(amount * DELEGATE_DMG_MULT)
		# Getting hit hard while delegating cancels it
		if amount >= 15:
			_exit_delegate_mode()

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
			# Stun the attacker if we can find them
			if source_index >= 0:
				_stun_source(source_index)
			return
		else:
			# Regular block - 50% damage reduction
			amount = int(amount * 0.5)

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
	# Ghost appearance
	modulate = Color(0.5, 0.5, 0.8, 0.4)
	collision_layer = 0  # Can't be hit
	# Disable attacks
	if attack_area:
		attack_area.monitoring = false

	# Add revive prompt above head
	var revive_label := Label.new()
	revive_label.name = "ReviveLabel"
	revive_label.text = "STAND NEAR TO REVIVE"
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


func _special_shadow_dash() -> void:
	# Teleport short distance with ghost trail + invincibility
	# Use physics raycast to stop at walls
	var dash_distance := 120.0
	var direction := Vector2(1.0 if _facing_right else -1.0, 0.0)

	# Raycast to find wall
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		global_position,
		global_position + direction * dash_distance,
		1  # mask layer 1 = world/walls
	)
	query.exclude = [get_rid()]
	var result: Dictionary = space.intersect_ray(query)

	var target_pos: Vector2
	if result:
		# Stop short of the wall
		target_pos = result["position"] - direction * 12.0
	else:
		target_pos = global_position + direction * dash_distance

	AudioManager.play("shadow_dash")
	_spawn_vfx(Color(0.8, 0.2, 0.2, 0.5), Vector2(14, 28))
	var dash_start: Vector2 = global_position
	global_position = target_pos
	# Arrive flash
	_spawn_vfx(Color(0.8, 0.2, 0.2, 0.5), Vector2(14, 28))
	modulate = Color(1.0, 1.0, 1.0, 0.4)
	collision_layer = 0
	_shadow_dash_active = true

	# Dash wave - perpendicular to dash direction, rogue deals 10 damage
	_spawn_dash_wave(dash_start, direction, 10)

	await get_tree().create_timer(0.3).timeout
	if is_inside_tree():
		collision_layer = 2
		_shadow_dash_active = false
		modulate = Color.WHITE


# -- Visual Effects ------------------------------------------------------------

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
	var camera := get_viewport().get_camera_2d()
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


# -- Charge Attack System ------------------------------------------------------

func _handle_charge(delta: float) -> void:
	var pressing_attack: bool = _is_device_action_pressed("attack")

	if pressing_attack and not _was_pressing_attack:
		# Button just pressed - reset charge tracking
		_charge_time = 0.0
		_charge_smoke_timer = 0.0
		_charge_hover_time = 0.0
		_healer_channel_heal_timer = 0.0
		_healer_channel_pulse_timer = 0.0

		# EXCEPTION: Melee airborne → instant charge (ground pound hover)
		if not is_on_floor() and character_class == PlayerManager.CharacterClass.MELEE and _attack_cooldown <= 0.0:
			_is_charging = true
			velocity.y = 0.0  # Freeze in air immediately

	# Transition from normal hold to charge after holding for 0.3s
	if pressing_attack and _was_pressing_attack and not _is_charging and _attack_cooldown <= 0.0:
		_charge_time += delta
		if _charge_time >= 0.3:
			# Now start charging
			_is_charging = true
			_charge_time = 0.3
			# Melee airborne: freeze in air
			if not is_on_floor() and character_class == PlayerManager.CharacterClass.MELEE:
				velocity.y = 0.0
			# Healer: stop movement and start channeling
			if character_class == PlayerManager.CharacterClass.HEALER:
				velocity.x = 0.0
				_healer_channel_start_vfx()

	if pressing_attack and _is_charging:
		# Button held - charging
		_charge_time = minf(_charge_time + delta, CHARGE_MAX)
		var charge_ratio: float = clampf(_charge_time / CHARGE_MAX, 0.0, 1.0)

		# Healer: constant healing aura while channeling
		if character_class == PlayerManager.CharacterClass.HEALER:
			# Freeze in place - cannot move while channeling
			velocity.x = 0.0
			# Green glow instead of yellow
			var glow_intensity: float = 0.5 + sin(_charge_time * 4.0) * 0.2
			modulate = Color(0.6, 1.0, 0.6, 1.0).lerp(Color(0.3, 1.0, 0.3, 1.0), glow_intensity)
			# Heal nearby allies continuously (~5 HP/sec, scaled by proximity)
			_healer_channel_heal_timer += delta
			if _healer_channel_heal_timer >= 0.2:
				_healer_channel_heal_timer -= 0.2
				_healer_channel_heal_tick()
			# Pulsing ring VFX
			_healer_channel_pulse_timer += delta
			if _healer_channel_pulse_timer >= 0.8:
				_healer_channel_pulse_timer -= 0.8
				_spawn_expanding_ring(global_position, HEALER_CHANNEL_RADIUS, Color(0.3, 1.0, 0.4, 0.35), 0.7)
			# Update glow VFX size based on charge
			_healer_channel_update_vfx(charge_ratio)
		else:
			# Non-healer: glow toward yellow while charging
			var glow_color := Color(1.0, 1.0, 1.0 - charge_ratio * 0.7, 1.0)
			modulate = glow_color

		# Spawn small charge particles periodically
		_charge_smoke_timer += delta
		if _charge_smoke_timer >= 0.1:
			_charge_smoke_timer -= 0.1
			if character_class == PlayerManager.CharacterClass.HEALER:
				var particle_color := Color(0.3, 1.0, 0.4, 0.3 + charge_ratio * 0.3)
				_spawn_vfx(particle_color, Vector2(6, 6))
			else:
				var particle_color := Color(1.0, 0.9, 0.3, 0.4 * charge_ratio)
				_spawn_vfx(particle_color, Vector2(6, 6))

		# If airborne + melee, hover and oscillate every frame
		if not is_on_floor() and character_class == PlayerManager.CharacterClass.MELEE:
			velocity.y = 0.0
			_charge_hover_time += delta
			position.x += sin(_charge_hover_time * 20.0) * 2.0 * delta * 20.0

	elif not pressing_attack and _was_pressing_attack and _is_charging:
		# Button released while charging
		_is_charging = false
		modulate = Color.WHITE
		# Clean up healer channel VFX
		if character_class == PlayerManager.CharacterClass.HEALER:
			_healer_channel_stop_vfx()
		if _charge_time >= CHARGE_MIN:
			# Fire charged attack
			_attack_cooldown = ATTACK_COOLDOWN_TIME
			_is_attacking = true
			_attack_timer = ATTACK_DURATION
			_perform_charged_attack()
		_charge_time = 0.0

	_was_pressing_attack = pressing_attack


func _perform_charged_attack() -> void:
	var charge_ratio: float = clampf((_charge_time - CHARGE_MIN) / (CHARGE_MAX - CHARGE_MIN), 0.0, 1.0)

	match character_class:
		PlayerManager.CharacterClass.MELEE:
			_charged_melee_slam(charge_ratio)
		PlayerManager.CharacterClass.RANGED:
			_charged_ranged_shot(charge_ratio)
		PlayerManager.CharacterClass.MAGE:
			_charged_mage_bolt(charge_ratio)
		PlayerManager.CharacterClass.SUMMONER:
			_charged_summoner_donut(charge_ratio)
		PlayerManager.CharacterClass.ROGUE:
			_charged_rogue_backstab(charge_ratio)
		PlayerManager.CharacterClass.DEMOLITIONIST:
			_charged_demo_mega_bomb(charge_ratio)
		PlayerManager.CharacterClass.HEALER:
			_charged_healer_wave(charge_ratio)


func _charged_melee_slam(charge_ratio: float) -> void:
	if not is_on_floor():
		# Already hovering, slam down
		_ground_slam_active = true
		velocity.y = 600.0 + charge_ratio * 200.0
		AudioManager.play("sword_slash", 2.0, 0.5)
		modulate = Color(1.0, 0.4, 0.1)
	else:
		# On ground: AoE stomp
		var blast_radius: float = lerpf(40.0, 120.0, charge_ratio)
		var damage: int = int(lerpf(30.0, 80.0, charge_ratio))
		AudioManager.play("explosion", -2.0, 1.2)
		_spawn_vfx(Color(1.0, 0.5, 0.1, 0.7), Vector2(blast_radius * 2.0, 16))
		_screen_shake(charge_ratio * 8.0 + 2.0, 0.2)
		for body in get_tree().get_nodes_in_group("enemies"):
			if not body is Node2D:
				continue
			var dist: float = global_position.distance_to(body.global_position)
			if dist < blast_radius and body.has_method("take_damage"):
				body.take_damage(damage, player_index)
				if body.has_method("apply_knockback"):
					var kb: Vector2 = (body.global_position - global_position).normalized()
					body.apply_knockback(kb * (200.0 + charge_ratio * 150.0))


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


func _charged_mage_bolt(charge_ratio: float) -> void:
	var damage: int = int(lerpf(25.0, 60.0, charge_ratio))
	var aoe_radius: float = lerpf(30.0, 80.0, charge_ratio)
	if not PlayerManager.use_mana(player_index, 25):
		_spawn_fail_flash()
		return
	AudioManager.play("magic_bolt", 2.0, 0.6)
	_spawn_vfx(Color(0.6, 0.3, 1.0, 0.7), Vector2(16, 16))
	var projectile_scene := load("res://scenes/characters/projectile.tscn") as PackedScene
	if not projectile_scene:
		return
	var proj := projectile_scene.instantiate()
	proj.damage = damage
	proj.speed = 280.0
	proj.direction = Vector2(1.0 if _facing_right else -1.0, 0.0)
	proj.projectile_type = "magic_bolt"
	proj.owner_index = player_index
	if proj.has_method("set_explosion_radius"):
		proj.set_explosion_radius(aoe_radius)
	proj.global_position = global_position + Vector2(16.0 if _facing_right else -16.0, 0.0)
	proj.scale = Vector2(1.0 + charge_ratio * 0.8, 1.0 + charge_ratio * 0.8)
	get_parent().add_child(proj)


func _charged_summoner_donut(charge_ratio: float) -> void:
	if _donut_buddy_count >= 3:
		_spawn_fail_flash()
		return
	if not PlayerManager.use_mana(player_index, 40):
		_spawn_fail_flash()
		return

	var buddy_scale: float = lerpf(1.5, 2.5, charge_ratio)
	var buddy_hp: int = int(lerpf(30.0, 80.0, charge_ratio))
	var buddy_dmg: int = int(lerpf(8.0, 20.0, charge_ratio))

	AudioManager.play("summon", 2.0, 0.8)
	_spawn_vfx(Color(1.0, 0.8, 0.2, 0.8), Vector2(40, 40))
	var buddy_scene := load("res://scenes/characters/donut_buddy.tscn") as PackedScene
	if not buddy_scene:
		return
	var buddy := buddy_scene.instantiate()
	buddy.owner_index = player_index
	if buddy.has_method("set_empowered"):
		buddy.set_empowered(buddy_hp, buddy_dmg)
	buddy.scale = Vector2(buddy_scale, buddy_scale)
	buddy.global_position = global_position + Vector2(24.0 if _facing_right else -24.0, 0.0)
	buddy.tree_exited.connect(func(): _donut_buddy_count -= 1)
	get_parent().add_child(buddy)
	_donut_buddy_count += 1


func _charged_rogue_backstab(charge_ratio: float) -> void:
	var damage: int = int(lerpf(30.0, 70.0, charge_ratio))
	var nearest_enemy: Node2D = null
	var nearest_dist: float = 150.0

	for body in get_tree().get_nodes_in_group("enemies"):
		if not body is Node2D:
			continue
		var dist: float = global_position.distance_to(body.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_enemy = body as Node2D

	if nearest_enemy:
		var behind_offset: float = -20.0 if nearest_enemy.global_position.x > global_position.x else 20.0
		var teleport_pos := Vector2(nearest_enemy.global_position.x + behind_offset, nearest_enemy.global_position.y)
		_spawn_vfx(Color(0.5, 0.0, 0.5, 0.6), Vector2(14, 28))
		global_position = teleport_pos
		_facing_right = nearest_enemy.global_position.x > global_position.x
		sprite.flip_h = not _facing_right
		_spawn_vfx(Color(0.5, 0.0, 0.5, 0.6), Vector2(14, 28))
		AudioManager.play("dagger_stab", 3.0, 0.7)
		if nearest_enemy.has_method("take_damage"):
			nearest_enemy.take_damage(damage, player_index)
	else:
		AudioManager.play("dagger_stab", 1.0, 0.8)
		var offset := Vector2(18.0 if _facing_right else -18.0, 0.0)
		attack_area.position = offset
		attack_area.monitoring = true
		for body in attack_area.get_overlapping_bodies():
			if body.has_method("take_damage"):
				body.take_damage(damage, player_index)
		await get_tree().create_timer(0.1).timeout
		if is_inside_tree():
			attack_area.monitoring = false


func _charged_demo_mega_bomb(charge_ratio: float) -> void:
	var blast_radius: float = lerpf(60.0, 140.0, charge_ratio)
	var damage: int = int(lerpf(30.0, 70.0, charge_ratio))
	var fragment_count: int = int(lerpf(0.0, 5.0, charge_ratio))

	AudioManager.play("explosion", 2.0, 0.7)
	_spawn_vfx(Color(1.0, 0.4, 0.1, 0.8), Vector2(blast_radius * 2.0, blast_radius * 2.0))
	_screen_shake(charge_ratio * 6.0 + 2.0, 0.25)

	for body in get_tree().get_nodes_in_group("enemies"):
		if not body is Node2D:
			continue
		var dist: float = global_position.distance_to(body.global_position)
		if dist < blast_radius and body.has_method("take_damage"):
			body.take_damage(damage, player_index)
			if body.has_method("apply_knockback"):
				var kb: Vector2 = (body.global_position - global_position).normalized()
				body.apply_knockback(kb * 300.0)

	# Spawn fragment mini-bombs
	for i in range(fragment_count):
		var angle: float = randf() * TAU
		var frag_offset := Vector2(cos(angle), sin(angle)) * (blast_radius * 0.5)
		var frag_pos: Vector2 = global_position + frag_offset
		_spawn_fragment_bomb(frag_pos, int(damage * 0.3))


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


func _charged_healer_wave(charge_ratio: float) -> void:
	# Final burst heal on release - proportional to charge time
	_healer_channel_burst()


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


# -- Demolitionist -------------------------------------------------------------

func _attack_demolitionist() -> void:
	AudioManager.play("explosion", -6.0, 1.3)
	# Spawn a bomb projectile that arcs with gravity
	var bomb := ColorRect.new()
	bomb.color = Color(0.9, 0.6, 0.1)
	bomb.size = Vector2(8, 8)
	bomb.z_index = 5
	get_parent().add_child(bomb)
	bomb.global_position = global_position + Vector2(12.0 if _facing_right else -12.0, -4.0)

	var bomb_vel := Vector2(180.0 if _facing_right else -180.0, -200.0)
	var bomb_gravity := 500.0
	var bomb_time := 0.0
	var bomb_max_time := 1.5
	var bomb_bounced := false

	while bomb_time < bomb_max_time and is_instance_valid(bomb) and is_inside_tree():
		var dt: float = get_process_delta_time()
		bomb_time += dt
		bomb_vel.y += bomb_gravity * dt
		bomb.global_position += bomb_vel * dt

		# Bounce once off floor
		if bomb.global_position.y > global_position.y + 8.0 and not bomb_bounced:
			bomb_bounced = true
			bomb_vel.y = -120.0
			bomb_vel.x *= 0.5

		# Check enemy hit
		var hit_enemy := false
		for body in get_tree().get_nodes_in_group("enemies"):
			if not body is Node2D:
				continue
			var dist: float = bomb.global_position.distance_to(body.global_position)
			if dist < 20.0:
				hit_enemy = true
				break
		if hit_enemy:
			break
		await get_tree().process_frame

	# Explode
	if is_instance_valid(bomb):
		var explode_pos: Vector2 = bomb.global_position
		bomb.queue_free()
		var base_dmg: int = int(25 * (1.0 + _demo_power_tier * 0.25))
		var base_rad: float = 60.0 * (1.0 + _demo_size_tier * 0.20)
		_demolitionist_explode(explode_pos, base_dmg, base_rad)


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


func _special_big_bomb() -> void:
	if not PlayerManager.use_mana(player_index, 40):
		_special_cooldown = 0.0
		_spawn_fail_flash()
		return

	AudioManager.play("explosion", -3.0, 0.8)
	# Spawn a bigger bomb projectile
	var bomb := ColorRect.new()
	bomb.color = Color(1.0, 0.4, 0.0)
	bomb.size = Vector2(12, 12)
	bomb.z_index = 5
	get_parent().add_child(bomb)
	bomb.global_position = global_position + Vector2(12.0 if _facing_right else -12.0, -4.0)

	var bomb_vel := Vector2(160.0 if _facing_right else -160.0, -220.0)
	var bomb_gravity := 450.0
	var bomb_time := 0.0
	var bomb_max_time := 1.5
	var bomb_bounced := false

	while bomb_time < bomb_max_time and is_instance_valid(bomb) and is_inside_tree():
		var dt: float = get_process_delta_time()
		bomb_time += dt
		bomb_vel.y += bomb_gravity * dt
		bomb.global_position += bomb_vel * dt

		if bomb.global_position.y > global_position.y + 8.0 and not bomb_bounced:
			bomb_bounced = true
			bomb_vel.y = -100.0
			bomb_vel.x *= 0.4

		var hit_enemy := false
		for body in get_tree().get_nodes_in_group("enemies"):
			if not body is Node2D:
				continue
			var dist: float = bomb.global_position.distance_to(body.global_position)
			if dist < 24.0:
				hit_enemy = true
				break
		if hit_enemy:
			break
		await get_tree().process_frame

	if is_instance_valid(bomb):
		var explode_pos: Vector2 = bomb.global_position
		bomb.queue_free()
		var big_dmg: int = int(50 * (1.0 + _demo_power_tier * 0.25))
		var big_rad: float = 90.0 * (1.0 + _demo_size_tier * 0.20)
		_demolitionist_explode(explode_pos, big_dmg, big_rad)


# -- Healer -------------------------------------------------------------------

func _attack_healer() -> void:
	# Throw a healing potion that creates a lingering heal zone
	AudioManager.play("summon", -3.0, 1.2)
	var throw_dir: Vector2 = Vector2(1.0 if _facing_right else -1.0, 0.0)

	# Find nearest injured ally to aim toward
	var target_pos: Vector2 = global_position + throw_dir * 80.0
	for p in get_tree().get_nodes_in_group("players"):
		if p == self or not (p is CharacterBody2D):
			continue
		if p.get("_is_dead"):
			continue
		var p_idx: int = p.get("player_index")
		var p_data: Dictionary = PlayerManager.get_player(p_idx)
		if p_data.is_empty():
			continue
		if p_data["health"] < p_data["max_health"]:
			var dist: float = global_position.distance_to(p.global_position)
			if dist < 150.0:
				target_pos = p.global_position
				break

	# Spawn the potion projectile
	_spawn_healing_potion(target_pos)


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


func _special_healing_burst() -> void:
	if not PlayerManager.use_mana(player_index, 50):
		_special_cooldown = 0.0
		_spawn_fail_flash()
		return

	AudioManager.play("player_revive")
	# Green pulse VFX expanding outward
	var pulse := ColorRect.new()
	pulse.color = Color(0.3, 0.9, 0.4, 0.5)
	pulse.size = Vector2(20, 20)
	pulse.position = global_position - Vector2(10, 10)
	pulse.pivot_offset = Vector2(10, 10)
	get_parent().add_child(pulse)
	var pulse_tween := pulse.create_tween()
	pulse_tween.set_parallel(true)
	pulse_tween.tween_property(pulse, "scale", Vector2(8.0, 8.0), 0.4)
	pulse_tween.tween_property(pulse, "modulate:a", 0.0, 0.4)
	pulse_tween.chain().tween_callback(pulse.queue_free)

	# Heal all allies within 80px for 30 HP
	for p in get_tree().get_nodes_in_group("players"):
		if not (p is CharacterBody2D):
			continue
		if p.get("_is_dead"):
			continue
		var dist: float = global_position.distance_to(p.global_position)
		if dist < 80.0:
			var p_idx: int = p.get("player_index")
			PlayerManager.heal_player(p_idx, 30)


func _spawn_fail_flash() -> void:
	# Red X flash to show ability can't be used
	modulate = Color(1.0, 0.3, 0.3)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.15)
