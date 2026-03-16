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
	PlayerManager.CharacterClass.TANK: "res://assets/sprites/characters/tank_side.png",
	PlayerManager.CharacterClass.NINJA: "res://assets/sprites/characters/ninja_side.png",
	PlayerManager.CharacterClass.BALLOONIST: "res://assets/sprites/characters/balloonist_side.png",
	PlayerManager.CharacterClass.GUITARIST: "res://assets/sprites/characters/guitarist_side.png",
	PlayerManager.CharacterClass.WEREWOLF: "res://assets/sprites/characters/werewolf_side.png",
}

enum AnimFrame { IDLE = 0, WALK1 = 1, WALK2 = 2, JUMP = 3, ATTACK1 = 4, ATTACK2 = 5 }

@export var player_index: int = 0
@export var device_id: int = -1
@export var character_class: PlayerManager.CharacterClass = PlayerManager.CharacterClass.MELEE
var mass := 70.0

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
const GRAPPLE_BASE_THROW_SPEED := 200.0
const GRAPPLE_THROW_SPEED_PER_SEC := 150.0
const GRAPPLE_MAX_THROW_SPEED := 500.0
const GRAPPLE_HOOK_GRAVITY := 400.0
const GRAPPLE_HOOK_DRAG := 0.98
const GRAPPLE_ROPE_SEGMENTS := 20
const GRAPPLE_ROPE_SEGMENT_LEN := 12.0
const GRAPPLE_LAUNCH_SPEED_RATIO := 2.5  # 250% of JUMP_VELOCITY (5x the original 50%)
const GRAPPLE_PENDULUM_GRAVITY := 600.0
const GRAPPLE_SWING_DAMPING := 0.02
const GRAPPLE_INPUT_BOOST := 1.5  # rad/s² when pushing with swing
const GRAPPLE_INPUT_BRAKE := 1.0
const GRAPPLE_ROPE_ADJUST_SPEED := 80.0
const GRAPPLE_MIN_ROPE_LEN := 30.0
const GRAPPLE_MAX_ROPE_LEN := 300.0
const GRAPPLE_TUG_FORCE := 8000.0
const GRAPPLE_TUG_DURATION := 0.15
const GRAPPLE_HOOK_DAMAGE := 10
const GRAPPLE_TUG_DAMAGE := 10
const PLAYER_MASS := 70.0

enum GrappleState { IDLE, WINDUP, THROWN, CONNECTED, SWINGING, TUG, RETRACTING }
var _grapple_state: GrappleState = GrappleState.IDLE
var _grapple_hold_time: float = 0.0
var _grapple_angle: float = 0.0  # Current windup angle
var _grapple_angular_vel: float = 0.0
var _grapple_hook_pos: Vector2 = Vector2.ZERO  # Hook world position
var _grapple_hook_vel: Vector2 = Vector2.ZERO  # Hook velocity during throw
var _grapple_anchor: Vector2 = Vector2.ZERO  # Anchor point (wall/enemy contact)
var _grapple_anchor_entity: Node2D = null  # If anchored to an enemy
var _grapple_rope_len: float = 100.0  # Current rope length
var _grapple_swing_angle: float = 0.0  # Pendulum angle from vertical
var _grapple_swing_vel: float = 0.0  # Pendulum angular velocity
var _grapple_rope_points: Array[Vector2] = []  # Verlet rope segments
var _grapple_retract_timer: float = 0.0

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
	_update_player_label()
	_setup_health_bar()
	_setup_mana_bar()
	# Load demolitionist upgrades from persistent state
	_demo_aspect = PlayerManager.demo_aspect
	_demo_power_tier = PlayerManager.demo_power_tier
	_demo_size_tier = PlayerManager.demo_size_tier
	_demo_napalm = PlayerManager.demo_napalm
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

	# Red portal + smoke poof VFX at current position
	_spawn_class_change_vfx()


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

	# Ghost effect: fade out then back in
	modulate = Color(1, 1, 1, 0.4)
	var restore_tween := create_tween()
	restore_tween.tween_property(self, "modulate:a", 1.0, 0.5)

	# Spawn rift tentacle (counts toward global limit)
	PlayerHUD.active_tentacle_count += 1
	var rift_script := load("res://scripts/effects/rift_tentacle.gd")
	var rift := Node2D.new()
	rift.set_script(rift_script)
	rift.global_position = global_position + Vector2(0, -30)
	rift.setup(player_index)
	get_parent().add_child(rift)

	# Lock class changes for this player
	PlayerHUD.class_change_locked[player_index] = true
	# Unlock after rift duration (15s) via a timer — unless tentacle attached permanently
	var unlock_timer := get_tree().create_timer(15.0)
	var pi_capture: int = player_index
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


func _input(event: InputEvent) -> void:
	if device_id == -1:
		return
	if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	if event.device != device_id:
		return

	for action in ["move_left", "move_right", "move_up", "move_down", "jump", "attack", "special", "block", "interact"]:
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
	_handle_ranger_grapple()
	# While swinging on grapple, skip normal movement/gravity
	if _grapple_state == GrappleState.SWINGING:
		_update_health_bar()
		_update_animation(delta)
		_controller_just_pressed.clear()
		queue_redraw()
		return
	_handle_demo_refuel()
	_handle_healer_wind_gust()
	_handle_tank_fortify(delta)
	_handle_balloonist_float(delta)
	_handle_jumper_dash()
	_handle_jumper_momentum(delta)
	_handle_melee_enrage(delta)
	_handle_mage_airwalk_toggle()
	_handle_mage_airwalk(delta)
	_handle_guitarist_amp_up(delta)
	_handle_werewolf_frenzy(delta)
	_handle_rogue_stealth_toggle()
	_handle_rogue_stealth(delta)
	_handle_ranger_reload(delta)
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
	_handle_charge(delta)
	_check_ground_slam_landing()
	_check_werewolf_pounce_landing()
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
	if _mage_airwalk:
		return
	if _balloonist_floating:
		return  # Balloon carries us up
	if not is_on_floor():
		# Count attached balloons - reduce gravity per balloon
		var balloon_count: int = 0
		for dart in get_tree().get_nodes_in_group("balloon_darts"):
			if dart.has_method("_get_entity_weight") and dart.get("_attached_to") == self:
				balloon_count += 1
		if balloon_count > 0:
			# Each balloon reduces gravity by 30%, fall slower
			var gravity_mult: float = maxf(0.1, 1.0 - balloon_count * 0.3)
			velocity.y += GRAVITY * delta * gravity_mult
			velocity.y = min(velocity.y, 600.0 * gravity_mult)
		else:
			velocity.y += GRAVITY * delta
			velocity.y = min(velocity.y, 600.0)


func _handle_movement() -> void:
	# Healer cannot move while channeling
	if _is_charging and character_class == PlayerManager.CharacterClass.HEALER:
		velocity.x = 0.0
		return
	# Shield charge overrides movement
	if _shield_charging:
		return

	var h_input := 0.0
	if _is_device_action_pressed("move_left"):
		h_input -= 1.0
	if _is_device_action_pressed("move_right"):
		h_input += 1.0

	var speed: float = PlayerManager.get_player(player_index).get("speed", 100)
	if _melee_enraged:
		speed *= MELEE_ENRAGE_SPEED_MULT
	if _werewolf_frenzy_active:
		speed *= 1.25
	if _is_blocking:
		speed *= 0.5
	velocity.x = h_input * speed

	if h_input != 0.0:
		_facing_right = h_input > 0.0
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
		var jump_vel: float = JUMPER_JUMP_VELOCITY if character_class == PlayerManager.CharacterClass.NINJA else JUMP_VELOCITY
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
		PlayerManager.CharacterClass.TANK:
			_attack_tank()
		PlayerManager.CharacterClass.NINJA:
			_attack_jumper()
		PlayerManager.CharacterClass.BALLOONIST:
			_attack_balloonist()
		PlayerManager.CharacterClass.GUITARIST:
			_attack_guitarist()
		PlayerManager.CharacterClass.WEREWOLF:
			_attack_werewolf()


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

	# Aim direction determines swing position
	var aim: Vector2 = _get_aim_direction()

	# Spawn large arcing slash VFX with particles
	_spawn_melee_arc(reach, combo_idx)

	# Enable attack area in aimed direction
	var offset: Vector2 = aim * reach
	attack_area.position = offset
	attack_area.monitoring = true
	# Wait one physics frame for Godot to detect overlaps
	await get_tree().physics_frame
	if not is_inside_tree():
		return

	# Now check for hits
	var attack_bonus: float = PlayerManager.get_skill_bonus(player_index, "attack")
	if _melee_enraged:
		attack_bonus *= MELEE_ENRAGE_DAMAGE_MULT
	for body in attack_area.get_overlapping_bodies():
		if body.has_method("take_damage"):
			var scaled_damage: int = int(damage * attack_bonus)
			body.take_damage(scaled_damage, player_index)
			PlayerManager.add_skill_xp(player_index, "attack", 2)
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
	# Large sweeping arc in the aimed direction
	var aim: Vector2 = _get_aim_direction()
	var arc_center: Vector2 = global_position + aim * reach * 0.5
	var arc_dir: float = 1.0 if aim.x >= 0.0 else -1.0
	var colors: Array[Color] = [
		Color(0.85, 0.85, 0.9, 0.8),   # Silver
		Color(0.6, 0.6, 0.65, 0.7),    # Grey
		Color(1.0, 0.95, 0.5, 0.7),    # Yellow
		Color(1.0, 1.0, 1.0, 0.9),     # White
	]

	# Spawn arc particles along a curved path
	var particle_count: int = 12 + combo_idx * 4
	for i in range(particle_count):
		var t: float = float(i) / float(particle_count)
		# Arc angle from -60 to +60 degrees (vertical sweep)
		var angle: float = lerpf(-1.0, 1.0, t)
		# Position particles in an arc in front of the player
		var arc_pos: Vector2 = global_position + Vector2(
			cos(angle) * reach * 0.8 * arc_dir,
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
	var arc_width: float = reach * 1.5
	var arc_height: float = reach * 0.8
	arc_visual.size = Vector2(arc_width, arc_height)
	var arc_x: float = 0.0 if _facing_right else -arc_width
	arc_visual.position = global_position + Vector2(arc_x, -arc_height / 2.0)
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
	# Square: fire crossbow
	if _ranger_arrows <= 0:
		_spawn_fail_flash()
		AudioManager.play("reload_click", -4.0)
		return
	_ranger_arrows -= 1
	AudioManager.play("crossbow_shoot", 0.0, 0.8)
	_attack_cooldown = 0.6
	var scaled_dmg: int = int(60 * PlayerManager.get_skill_bonus(player_index, "attack"))
	_spawn_projectile(scaled_dmg, 400.0, "crossbow_bolt")
	PlayerManager.add_skill_xp(player_index, "attack", 2)


func _attack_mage() -> void:
	# Mage: FIREBALL - slow, high damage, fire trail
	if not PlayerManager.use_mana(player_index, 5):
		return
	AudioManager.play("explosion", -6.0, 1.5)
	_attack_cooldown = 0.6
	var scaled_dmg: int = int(18 * PlayerManager.get_skill_bonus(player_index, "attack"))
	PlayerManager.add_skill_xp(player_index, "attack", 2)

	var aim: Vector2 = _get_aim_direction()
	_spawn_fireball(aim, scaled_dmg)


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


func _attack_summoner() -> void:
	# Homing mark spell - slow projectile that seeks nearest enemy
	# When it hits, marks the target so donut buddies deal +20-40% damage
	AudioManager.play("summon", -4.0, 1.6)
	_attack_cooldown = 0.8
	PlayerManager.add_skill_xp(player_index, "attack", 2)

	# Find nearest enemy to home toward
	var nearest_enemy: Node2D = null
	var nearest_dist: float = 200.0
	for body in get_tree().get_nodes_in_group("enemies"):
		if body is Node2D:
			var dist: float = global_position.distance_to(body.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest_enemy = body

	# Spawn homing orb
	var orb := ColorRect.new()
	orb.color = Color(1.0, 0.6, 0.2, 0.9)
	orb.size = Vector2(6, 6)
	orb.position = global_position
	orb.z_index = 6
	get_parent().add_child(orb)

	# Homing flight
	var orb_speed: float = 120.0
	var orb_age: float = 0.0
	var orb_max_age: float = 3.0
	var hit := false

	while orb_age < orb_max_age and is_instance_valid(orb) and is_inside_tree():
		var dt: float = get_process_delta_time()
		orb_age += dt

		# Re-acquire nearest enemy each frame for true homing
		var current_target: Node2D = null
		var best_dist: float = 250.0
		for body in get_tree().get_nodes_in_group("enemies"):
			if body is Node2D:
				var d: float = orb.position.distance_to(body.global_position)
				if d < best_dist:
					best_dist = d
					current_target = body

		if current_target:
			var to_target: Vector2 = (current_target.global_position - orb.position).normalized()
			orb.position += to_target * orb_speed * dt

			# Trail particle
			if randi() % 3 == 0:
				var trail := ColorRect.new()
				trail.color = Color(1.0, 0.7, 0.3, 0.5)
				trail.size = Vector2(3, 3)
				trail.position = orb.position + Vector2(randf_range(-2, 2), randf_range(-2, 2))
				trail.z_index = 5
				get_parent().add_child(trail)
				var tt := trail.create_tween()
				tt.tween_property(trail, "modulate:a", 0.0, 0.3)
				tt.tween_callback(trail.queue_free)

			# Check if hit
			if orb.position.distance_to(current_target.global_position) < 12.0:
				# HIT - deal small damage and MARK the enemy
				var scaled_dmg: int = int(5 * PlayerManager.get_skill_bonus(player_index, "attack"))
				if current_target.has_method("take_damage"):
					current_target.take_damage(scaled_dmg, player_index)
				# Mark the enemy for bonus donut buddy damage
				current_target.set_meta("summoner_marked", true)
				current_target.set_meta("summoner_mark_owner", player_index)
				# Visual mark - orange glow
				current_target.modulate = Color(1.2, 0.9, 0.6)
				# Mark expires after 6 seconds
				_expire_mark_after(current_target, 6.0)
				AudioManager.play("mark_target")
				_spawn_vfx(Color(1.0, 0.6, 0.2, 0.6), Vector2(20, 20))
				hit = true
				break
		else:
			# No target - drift in aimed direction
			var aim: Vector2 = _get_aim_direction()
			orb.position += aim * orb_speed * dt

		await get_tree().process_frame

	if is_instance_valid(orb):
		orb.queue_free()


func _expire_mark_after(enemy: Node2D, duration: float) -> void:
	await get_tree().create_timer(duration).timeout
	if is_instance_valid(enemy):
		enemy.remove_meta("summoner_marked")
		enemy.remove_meta("summoner_mark_owner")
		enemy.modulate = Color.WHITE


func _attack_rogue() -> void:
	# Throw 3 knives in a fan spread, 0.5s cooldown
	AudioManager.play("dagger_stab")
	_attack_cooldown = 0.5
	var base_dir: Vector2 = _get_aim_direction()
	var angles := [-0.2, 0.0, 0.2]
	var base_dmg: int = int(12 * PlayerManager.get_skill_bonus(player_index, "attack"))

	# STEALTH: close-range backstab instead of throwing knives
	if _rogue_stealth:
		var backstab_dmg: int = int(base_dmg * ROGUE_STEALTH_DAMAGE_MULT)
		_exit_stealth()

		# Small square melee hit in front of rogue
		attack_area.position = base_dir * 14.0
		attack_area.monitoring = true
		await get_tree().physics_frame
		if not is_inside_tree():
			return
		var hit_something := false
		for body in attack_area.get_overlapping_bodies():
			if body.has_method("take_damage"):
				body.take_damage(backstab_dmg, player_index)
				_spawn_blood_particles(body.global_position)
				PlayerManager.add_skill_xp(player_index, "attack", 5)
				hit_something = true
		# Only show BACK STAB text + sound if we actually hit an enemy
		if hit_something:
			AudioManager.play("backstab_hit")
			_stealth_backstab_vfx(global_position + base_dir * 16.0)
		await get_tree().create_timer(0.1).timeout
		if is_inside_tree():
			attack_area.monitoring = false
		return

	# Normal: throw 3 knives in a fan spread
	var scaled_dmg: int = base_dmg
	PlayerManager.add_skill_xp(player_index, "attack", 2)
	for angle in angles:
		var dir: Vector2 = base_dir.rotated(angle)
		var knife_scene := load("res://scenes/characters/projectile.tscn") as PackedScene
		if not knife_scene:
			continue
		var knife := knife_scene.instantiate()
		knife.damage = scaled_dmg
		knife.speed = 400.0
		knife.direction = dir
		knife.projectile_type = "knife"
		knife.owner_index = player_index
		knife.global_position = global_position + base_dir * 12.0
		get_parent().add_child(knife)


func _get_aim_direction_analog() -> Vector2:
	## Returns full analog aim direction from the joystick (not snapped to 8 dirs).
	## Falls back to _get_aim_direction() for keyboard or if stick is neutral.
	if device_id >= 0:
		var stick := Vector2(
			Input.get_joy_axis(device_id, JOY_AXIS_LEFT_X),
			Input.get_joy_axis(device_id, JOY_AXIS_LEFT_Y)
		)
		if stick.length() > 0.2:  # Deadzone
			return stick.normalized()
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
	var slam_bonus: float = PlayerManager.get_skill_bonus(player_index, "attack")
	for body in get_tree().get_nodes_in_group("enemies"):
		if not body is Node2D:
			continue
		var dist: float = global_position.distance_to(body.global_position)
		if dist < blast_radius and body.has_method("take_damage"):
			body.take_damage(int(slam_damage * slam_bonus), player_index)
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

	# Apply special cooldown reduction from skill level
	var cooldown_reduction: float = PlayerManager.get_skill_level_for(player_index, "special") * 0.02
	_special_cooldown = SPECIAL_COOLDOWN_TIME * (1.0 - cooldown_reduction)
	PlayerManager.add_skill_xp(player_index, "special", 7)
	_perform_special()


func _perform_special() -> void:
	match character_class:
		PlayerManager.CharacterClass.MELEE:
			_special_shield_charge()
		PlayerManager.CharacterClass.RANGED:
			_special_grappling_hook()
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
		PlayerManager.CharacterClass.TANK:
			_special_tank_slam()
		PlayerManager.CharacterClass.NINJA:
			_special_jumper_dive()
		PlayerManager.CharacterClass.BALLOONIST:
			_special_balloonist_burst()
		PlayerManager.CharacterClass.GUITARIST:
			_special_guitarist_blast_wave()
		PlayerManager.CharacterClass.WEREWOLF:
			_special_werewolf_roar_push()


var _shield_charging: bool = false

func _special_shield_charge() -> void:
	AudioManager.play("shield_charge", 2.0, 0.9)
	var dash_speed: float = 600.0
	var charge_dir: Vector2 = Vector2(1.0 if _facing_right else -1.0, 0.0)

	# Flag to block normal movement during charge
	_shield_charging = true

	# Invincible during charge
	collision_layer = 0
	modulate = Color(0.4, 0.7, 1.0)

	# Initial burst VFX - big flash
	_spawn_vfx(Color(0.3, 0.6, 1.0, 0.9), Vector2(48, 32))
	_spawn_vfx(Color(1.0, 1.0, 1.0, 0.6), Vector2(24, 24))

	# Dash wave
	_spawn_dash_wave(global_position, charge_dir, 5)

	# Charge across multiple frames
	attack_area.monitoring = true
	var hit_bodies: Array = []
	var charge_frames: int = 14
	for i in range(charge_frames):
		if not is_inside_tree():
			_shield_charging = false
			return

		velocity.x = dash_speed * charge_dir.x
		velocity.y = -30.0
		move_and_slide()

		# Check for hits
		var offset := Vector2(24.0 if _facing_right else -24.0, 0.0)
		attack_area.position = offset
		for body in attack_area.get_overlapping_bodies():
			if body in hit_bodies:
				continue
			if body.has_method("take_damage"):
				var shield_dmg: int = int(35 * PlayerManager.get_skill_bonus(player_index, "attack"))
				body.take_damage(shield_dmg, player_index)
				PlayerManager.add_skill_xp(player_index, "special", 7)
				hit_bodies.append(body)
				# Impact spark burst on hit
				for s in range(6):
					var spark := ColorRect.new()
					spark.color = [Color(1.0, 0.9, 0.3, 0.9), Color(0.5, 0.8, 1.0, 0.9), Color(1.0, 1.0, 1.0, 0.8)][s % 3]
					spark.size = Vector2(randf_range(2, 5), randf_range(2, 5))
					spark.position = body.global_position + Vector2(randf_range(-8, 8), randf_range(-8, 8))
					spark.z_index = 10
					get_parent().add_child(spark)
					var spark_vel: Vector2 = Vector2(randf_range(-80, 80), randf_range(-100, -20))
					var st := spark.create_tween()
					st.tween_property(spark, "position", spark.position + spark_vel * 0.2, 0.2)
					st.parallel().tween_property(spark, "modulate:a", 0.0, 0.2)
					st.tween_callback(spark.queue_free)
			if body.has_method("apply_knockback"):
				var kb_dir: Vector2 = Vector2(1.0 if _facing_right else -1.0, -0.4).normalized()
				body.apply_knockback(kb_dir * 400.0)

		# Rich trail particles every frame
		# Blue energy streaks
		for p in range(3):
			var trail := ColorRect.new()
			var trail_colors: Array[Color] = [
				Color(0.3, 0.5, 1.0, 0.7),
				Color(0.5, 0.7, 1.0, 0.5),
				Color(0.8, 0.9, 1.0, 0.4),
			]
			trail.color = trail_colors[p]
			trail.size = Vector2(randf_range(4, 10), randf_range(2, 5))
			trail.position = global_position + Vector2(
				-charge_dir.x * randf_range(4, 16),
				randf_range(-10, 10)
			)
			trail.z_index = 7
			get_parent().add_child(trail)
			var drift: Vector2 = Vector2(-charge_dir.x * randf_range(10, 30), randf_range(-15, 15))
			var tt := trail.create_tween()
			tt.set_parallel(true)
			tt.tween_property(trail, "position", trail.position + drift, randf_range(0.15, 0.3))
			tt.tween_property(trail, "modulate:a", 0.0, randf_range(0.2, 0.35))
			tt.tween_property(trail, "scale", Vector2(0.3, 0.3), 0.3)
			tt.chain().tween_callback(trail.queue_free)

		# Ground sparks (if on floor)
		if is_on_floor() and i % 2 == 0:
			var ground_spark := ColorRect.new()
			ground_spark.color = Color(1.0, 0.8, 0.3, 0.6)
			ground_spark.size = Vector2(3, 3)
			ground_spark.position = global_position + Vector2(randf_range(-6, 6), 12)
			ground_spark.z_index = 6
			get_parent().add_child(ground_spark)
			var gs_tween := ground_spark.create_tween()
			gs_tween.tween_property(ground_spark, "position:y", ground_spark.position.y - randf_range(8, 20), 0.2)
			gs_tween.parallel().tween_property(ground_spark, "modulate:a", 0.0, 0.2)
			gs_tween.tween_callback(ground_spark.queue_free)

		await get_tree().process_frame

	# End charge - final burst
	_shield_charging = false
	if is_inside_tree():
		attack_area.monitoring = false
		collision_layer = 2
		# Deceleration flash
		_spawn_vfx(Color(0.4, 0.6, 1.0, 0.5), Vector2(30, 30))
		var brake_tween := create_tween()
		brake_tween.tween_property(self, "modulate", Color.WHITE, 0.15)
		velocity.x = 0.0


func _special_grappling_hook() -> void:
	# Start windup when special is pressed (if not already grappling)
	if _grapple_state == GrappleState.IDLE:
		_grapple_state = GrappleState.WINDUP
		_grapple_hold_time = 0.0
		_grapple_angle = 0.0
		_grapple_angular_vel = GRAPPLE_BASE_ANGULAR_VEL
	elif _grapple_state == GrappleState.SWINGING:
		# Press grapple again while swinging = release or tug
		if _grapple_anchor_entity and is_instance_valid(_grapple_anchor_entity):
			_grapple_tug()
		else:
			_grapple_release()
	elif _grapple_state == GrappleState.CONNECTED:
		_grapple_release()


func _special_frosting_freeze() -> void:
	# Mana Potion - restore a big chunk of mana
	var p_data: Dictionary = PlayerManager.get_player(player_index)
	if p_data.is_empty():
		return
	var current_mana: float = p_data["mana"]
	var max_mana: float = p_data["max_mana"]
	if current_mana >= max_mana:
		_spawn_fail_flash()
		_special_cooldown = 0.0
		return

	# Restore 60% of max mana
	var restore_amount: float = max_mana * 0.6
	p_data["mana"] = minf(current_mana + restore_amount, max_mana)

	AudioManager.play("mana_drink")
	AudioManager.play("muffin_collect", -4.0, 0.8)

	# Drink animation - brief pause + purple glow
	modulate = Color(0.6, 0.4, 1.0)

	# Blue/purple mana particles spiral upward
	for i in range(12):
		var mana_p := ColorRect.new()
		mana_p.color = [Color(0.4, 0.3, 1.0, 0.8), Color(0.6, 0.5, 1.0, 0.7), Color(0.8, 0.7, 1.0, 0.6)][i % 3]
		mana_p.size = Vector2(4, 4)
		var angle: float = float(i) * TAU / 12.0
		mana_p.position = global_position + Vector2(cos(angle) * 12.0, sin(angle) * 12.0)
		mana_p.z_index = 8
		get_parent().add_child(mana_p)
		var pt := mana_p.create_tween()
		pt.set_parallel(true)
		pt.tween_property(mana_p, "position:y", mana_p.position.y - randf_range(20, 40), 0.5)
		pt.tween_property(mana_p, "position:x", mana_p.position.x + randf_range(-8, 8), 0.5)
		pt.tween_property(mana_p, "modulate:a", 0.0, 0.5)
		pt.tween_property(mana_p, "scale", Vector2(0.2, 0.2), 0.5)
		pt.chain().tween_callback(mana_p.queue_free)

	# "MANA+" text floats up
	var mana_text := Label.new()
	mana_text.text = "+%d MANA" % int(restore_amount)
	mana_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mana_text.add_theme_font_size_override("font_size", 10)
	mana_text.modulate = Color(0.5, 0.4, 1.0)
	mana_text.position = global_position + Vector2(-20, -30)
	mana_text.z_index = 12
	get_parent().add_child(mana_text)
	var text_tw := mana_text.create_tween()
	text_tw.tween_property(mana_text, "position:y", mana_text.position.y - 25, 0.8)
	text_tw.parallel().tween_property(mana_text, "modulate:a", 0.0, 0.8)
	text_tw.tween_callback(mana_text.queue_free)

	# Fade back
	var mod_tw := create_tween()
	mod_tw.tween_property(self, "modulate", Color.WHITE, 0.3)

	_update_health_bar()
	PlayerManager.add_skill_xp(player_index, "special", 7)


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


# -- Demolitionist Refuel (Circle) ---------------------------------------------

func _handle_demo_refuel() -> void:
	if character_class != PlayerManager.CharacterClass.DEMOLITIONIST:
		return
	if not _is_device_action_pressed("interact"):
		return
	if _rocket_active:
		return  # Can't refuel while flying!
	if _rocket_fuel >= ROCKET_FUEL_MAX:
		return

	# Refuel 1 unit per second while holding Circle
	var dt: float = get_process_delta_time()
	_rocket_fuel = minf(_rocket_fuel + dt * 1.5, ROCKET_FUEL_MAX)

	# VFX: orange fuel particles rising
	if randi() % 5 == 0:
		var fuel_p := ColorRect.new()
		fuel_p.color = Color(1.0, 0.6, 0.1, 0.6)
		fuel_p.size = Vector2(3, 3)
		fuel_p.position = global_position + Vector2(randf_range(-5, 5), randf_range(4, 10))
		fuel_p.z_index = 5
		get_parent().add_child(fuel_p)
		var ft := fuel_p.create_tween()
		ft.tween_property(fuel_p, "position:y", fuel_p.position.y - 15, 0.3)
		ft.parallel().tween_property(fuel_p, "modulate:a", 0.0, 0.3)
		ft.tween_callback(fuel_p.queue_free)

		# Show fuel level
		var fuel_pct: int = int(_rocket_fuel / ROCKET_FUEL_MAX * 100)
		var fuel_text := Label.new()
		fuel_text.text = "FUEL %d%%" % fuel_pct
		fuel_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fuel_text.add_theme_font_size_override("font_size", 7)
		fuel_text.modulate = Color(1.0, 0.6, 0.1)
		fuel_text.position = global_position + Vector2(-15, -35)
		fuel_text.z_index = 12
		get_parent().add_child(fuel_text)
		var tt := fuel_text.create_tween()
		tt.tween_property(fuel_text, "modulate:a", 0.0, 0.4)
		tt.tween_callback(fuel_text.queue_free)


# -- Balloonist Abilities ------------------------------------------------------

var _balloonist_pop_cooldown: float = 0.0
var _balloonist_floating: bool = false
var _balloonist_float_timer: float = 0.0
const BALLOONIST_FLOAT_DURATION := 6.0
const BALLOONIST_FLOAT_COOLDOWN := 12.0
var _balloonist_float_cooldown: float = 0.0


func _handle_balloonist_float(delta: float) -> void:
	if character_class != PlayerManager.CharacterClass.BALLOONIST:
		return
	if _balloonist_float_cooldown > 0.0:
		_balloonist_float_cooldown -= delta

	if _is_device_action_just_pressed("interact"):
		if _balloonist_floating:
			return
		if _balloonist_float_cooldown > 0.0:
			_spawn_fail_flash()
			return
		# Tie a balloon to self - float upward!
		_balloonist_floating = true
		_balloonist_float_timer = BALLOONIST_FLOAT_DURATION
		AudioManager.play("summon", -2.0, 1.4)

	if _balloonist_floating:
		_balloonist_float_timer -= delta
		# Float upward gently
		velocity.y = lerpf(velocity.y, -80.0, delta * 3.0)
		# Can still move left/right but slowly
		# Pink balloon visual drawn above head
		if randi() % 8 == 0:
			_spawn_vfx(Color(0.9, 0.4, 0.7, 0.3), Vector2(6, 6))
		# Warning
		if _balloonist_float_timer <= 2.0:
			if fmod(_balloonist_float_timer, 0.3) < 0.15:
				modulate = Color(0.9, 0.5, 0.7)
			else:
				modulate = Color.WHITE
		else:
			modulate = Color(0.95, 0.8, 0.9)
		if _balloonist_float_timer <= 0.0:
			_balloonist_floating = false
			_balloonist_float_cooldown = BALLOONIST_FLOAT_COOLDOWN
			modulate = Color.WHITE
			AudioManager.play("explosion", -8.0, 2.0)  # Pop

func _attack_balloonist() -> void:
	# Max 10 active balloons
	var active_count: int = 0
	for dart in get_tree().get_nodes_in_group("balloon_darts"):
		if dart.has_method("_get_entity_weight") and dart.get("owner_index") == player_index:
			active_count += 1
	if active_count >= 10:
		_spawn_fail_flash()
		return

	# 3x faster fire rate (0.8 → 0.27)
	AudioManager.play("crossbow_shoot", -3.0, 1.5)
	_attack_cooldown = 0.27
	PlayerManager.add_skill_xp(player_index, "attack", 2)

	var aim: Vector2 = _get_aim_direction()
	var dart_script := load("res://scripts/characters/balloon_dart.gd")
	var dart := Node2D.new()
	dart.set_script(dart_script)
	dart.dart_direction = aim
	dart.owner_index = player_index
	dart.global_position = global_position + aim * 12.0
	get_parent().add_child(dart)


func _special_balloonist_burst() -> void:
	# Pop all active balloons for AoE damage around each
	AudioManager.play("explosion", -2.0, 1.8)
	PlayerManager.add_skill_xp(player_index, "special", 7)

	var popped: int = 0
	for dart in get_tree().get_nodes_in_group("balloon_darts"):
		if dart is Node2D and dart.has_method("_detach_and_free"):
			# Damage enemies near the balloon
			var balloon_pos: Vector2 = dart.get("_balloon_pos") if "_balloon_pos" in dart else dart.global_position
			for body in get_tree().get_nodes_in_group("enemies"):
				if body is Node2D:
					var dist: float = balloon_pos.distance_to(body.global_position)
					if dist < 60.0 and body.has_method("take_damage"):
						body.take_damage(20, player_index)
						if body.has_method("apply_knockback"):
							var kb: Vector2 = (body.global_position - balloon_pos).normalized() * 200.0
							body.apply_knockback(kb)
			dart._spawn_pop_particles()
			dart._detach_and_free()
			popped += 1

	if popped > 0:
		_spawn_vfx(Color(0.9, 0.4, 0.7, 0.5), Vector2(30, 30))
	else:
		_spawn_fail_flash()
		_special_cooldown = 0.0


func _charged_balloonist_barrage(charge_ratio: float) -> void:
	# Shoot multiple balloon darts in a spread
	var count: int = int(lerpf(3.0, 8.0, charge_ratio))
	var spread: float = lerpf(0.3, 1.0, charge_ratio)
	var aim: Vector2 = _get_aim_direction()

	AudioManager.play("crossbow_shoot", 0.0, 1.2)
	PlayerManager.add_skill_xp(player_index, "charge", 5)

	for i in range(count):
		var t: float = float(i) / maxf(float(count - 1), 1.0)
		var angle: float = lerpf(-spread / 2.0, spread / 2.0, t)
		var dir: Vector2 = aim.rotated(angle)

		var dart_script := load("res://scripts/characters/balloon_dart.gd")
		var dart := Node2D.new()
		dart.set_script(dart_script)
		dart.dart_direction = dir
		dart.owner_index = player_index
		dart.global_position = global_position + dir * 12.0
		get_parent().add_child(dart)


# -- Jumper Abilities ----------------------------------------------------------

func _attack_jumper() -> void:
	# 3 fast sequential slices - damage scales with speed
	_attack_cooldown = 0.45
	PlayerManager.add_skill_xp(player_index, "attack", 2)
	var aim: Vector2 = _get_aim_direction()
	var speed_ratio: float = clampf(velocity.length() / 400.0, 0.0, 1.0)
	var base_dmg: int = int(lerpf(6.0, 20.0, speed_ratio) * PlayerManager.get_skill_bonus(player_index, "attack"))

	# Slash angles: horizontal, diagonal down, diagonal up
	var slash_angles: Array[float] = [0.0, 0.5, -0.5]
	var slash_colors: Array[Color] = [
		Color(0.3, 1.0, 1.0, 0.8),
		Color(0.5, 1.0, 0.9, 0.7),
		Color(0.2, 0.9, 1.0, 0.9),
	]

	for i in range(3):
		if not is_inside_tree():
			return
		if i > 0:
			await get_tree().create_timer(0.07).timeout
			if not is_inside_tree():
				return

		AudioManager.play("sword_slash", -2.0, 1.3 + i * 0.15)

		# Slash line VFX
		var slash_dir: Vector2 = aim.rotated(slash_angles[i])
		var slash := ColorRect.new()
		slash.color = slash_colors[i]
		slash.size = Vector2(35, 2)
		slash.position = global_position + slash_dir * 6.0
		slash.rotation = slash_dir.angle() + 0.785
		slash.z_index = 9
		get_parent().add_child(slash)
		var st := slash.create_tween()
		st.set_parallel(true)
		st.tween_property(slash, "position", slash.position + slash_dir * 18.0, 0.08)
		st.tween_property(slash, "modulate:a", 0.0, 0.12)
		st.chain().tween_callback(slash.queue_free)

		# Hit check
		attack_area.position = aim * 20.0
		attack_area.monitoring = true
		await get_tree().physics_frame
		if not is_inside_tree():
			return
		for body in attack_area.get_overlapping_bodies():
			if body.has_method("take_damage"):
				body.take_damage(base_dmg, player_index)
				_spawn_blood_particles(body.global_position)
			if body.has_method("apply_knockback") and i == 2:
				body.apply_knockback(aim * (100.0 + speed_ratio * 200.0))
		attack_area.monitoring = false
	await get_tree().create_timer(0.1).timeout
	if is_inside_tree():
		attack_area.monitoring = false


func _special_jumper_dive() -> void:
	# Dive kick downward - faster the higher you are
	if is_on_floor():
		# On ground: super jump upward
		velocity.y = JUMPER_JUMP_VELOCITY * 1.5
		AudioManager.play("jump", 0.0, 0.6)
		_spawn_vfx(Color(0.3, 1.0, 1.0, 0.6), Vector2(24, 24))
		PlayerManager.add_skill_xp(player_index, "special", 7)
	else:
		# In air: DIVE KICK downward at aimed angle
		_jumper_dive_active = true
		var aim: Vector2 = _get_aim_direction()
		if aim.y < 0.3:
			aim.y = 0.5  # Default to downward-ish if aiming up
		aim = aim.normalized()
		velocity = aim * 700.0
		AudioManager.play("shield_charge", 0.0, 1.6)
		modulate = Color(0.3, 1.0, 1.0)
		PlayerManager.add_skill_xp(player_index, "special", 7)


func _handle_jumper_dash() -> void:
	if character_class != PlayerManager.CharacterClass.NINJA:
		return
	if _jumper_dash_cooldown > 0.0:
		_jumper_dash_cooldown -= get_process_delta_time()
	if _jumper_pickup_cooldown > 0.0:
		_jumper_pickup_cooldown -= get_process_delta_time()

	if not _is_device_action_just_pressed("interact"):
		return

	# If holding an item, THROW IT in aimed direction
	if is_instance_valid(_jumper_held_item):
		_throw_held_item()
		return

	# Try to PICK UP a loose item nearby (bombs, muffins, rocks, enemy projectiles)
	if _jumper_pickup_cooldown <= 0.0:
		var nearest_item: Node2D = null
		var nearest_dist: float = JUMPER_PICKUP_RANGE

		# Check for loose projectiles (bombs, arrows, bolts)
		for node in get_tree().get_nodes_in_group("loose_items"):
			if node is Node2D:
				var dist: float = global_position.distance_to(node.global_position)
				if dist < nearest_dist:
					nearest_dist = dist
					nearest_item = node

		# Also check for boss projectiles we can catch!
		if not nearest_item:
			for node in get_tree().get_nodes_in_group("boss_projectiles"):
				if node is Node2D:
					var dist: float = global_position.distance_to(node.global_position)
					if dist < nearest_dist:
						nearest_dist = dist
						nearest_item = node

		# Check for enemy projectiles (arrows from cookie archers etc)
		if not nearest_item:
			for node in get_children():
				pass  # Projectiles aren't in a group by default

		if nearest_item:
			_pickup_item(nearest_item)
			_jumper_pickup_cooldown = 0.5
			return

	# Nothing to pick up: AIR DASH
	if _jumper_dash_cooldown > 0.0:
		_spawn_fail_flash()
		return
	_jumper_dash_cooldown = JUMPER_DASH_COOLDOWN
	var aim: Vector2 = _get_aim_direction()
	velocity = aim * JUMPER_DASH_SPEED
	velocity.y = minf(velocity.y, -50.0)
	AudioManager.play("shadow_dash", -2.0, 1.5)
	_spawn_vfx(Color(0.3, 1.0, 1.0, 0.5), Vector2(14, 28))
	for i in range(5):
		var trail := ColorRect.new()
		trail.color = Color(0.3, 1.0, 1.0, 0.4 - i * 0.06)
		trail.size = Vector2(8, 8)
		trail.position = global_position - aim * (i * 8)
		trail.z_index = -1
		get_parent().add_child(trail)
		var tt := trail.create_tween()
		tt.tween_property(trail, "modulate:a", 0.0, 0.3)
		tt.tween_callback(trail.queue_free)


func _pickup_item(item: Node2D) -> void:
	# Grab a loose physical item and carry it
	_jumper_held_item = item
	AudioManager.play("muffin_collect", 0.0, 0.8)

	# Stop the item's physics/movement
	if item.has_method("set_physics_process"):
		item.set_physics_process(false)
	if item.has_method("set_process"):
		item.set_process(false)
	if "velocity" in item:
		item.velocity = Vector2.ZERO

	# Reparent to player so it follows
	var old_pos: Vector2 = item.global_position
	if item.get_parent():
		item.get_parent().remove_child(item)
	add_child(item)
	item.position = Vector2(0, -20)  # Float above head

	# "PICKED UP!" text
	var pickup_text := Label.new()
	pickup_text.text = "GRABBED!"
	pickup_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pickup_text.add_theme_font_size_override("font_size", 10)
	pickup_text.modulate = Color(0.3, 1.0, 1.0)
	pickup_text.position = global_position + Vector2(-20, -40)
	pickup_text.z_index = 15
	get_parent().add_child(pickup_text)
	var tt := pickup_text.create_tween()
	tt.tween_property(pickup_text, "position:y", pickup_text.position.y - 15, 0.5)
	tt.parallel().tween_property(pickup_text, "modulate:a", 0.0, 0.5)
	tt.tween_callback(pickup_text.queue_free)


func _throw_held_item() -> void:
	if not is_instance_valid(_jumper_held_item):
		_jumper_held_item = null
		return

	var item: Node2D = _jumper_held_item
	_jumper_held_item = null

	var aim: Vector2 = _get_aim_direction()
	AudioManager.play("crossbow_shoot", 0.0, 0.9)

	# Reparent back to the scene
	var throw_pos: Vector2 = global_position + aim * 16.0
	remove_child(item)
	get_parent().add_child(item)
	item.global_position = throw_pos

	# Re-enable physics and launch it
	if item.has_method("set_physics_process"):
		item.set_physics_process(true)
	if item.has_method("set_process"):
		item.set_process(true)
	if "velocity" in item:
		item.velocity = aim * 400.0
	if "direction" in item:
		item.direction = aim
	if "speed" in item:
		item.speed = 400.0

	# Make it damage enemies on contact if it doesn't already
	if item.has_method("take_damage"):
		pass  # It's an enemy projectile, already does damage
	elif "damage" in item:
		item.damage = maxi(item.damage, 20)  # At least 20 damage

	_spawn_vfx(Color(0.3, 1.0, 1.0, 0.4), Vector2(12, 12))


func _handle_jumper_momentum(delta: float) -> void:
	if character_class != PlayerManager.CharacterClass.NINJA:
		return

	# Dive kick landing
	if _jumper_dive_active and is_on_floor():
		_jumper_dive_active = false
		modulate = Color.WHITE
		# Impact damage based on fall speed
		var impact_speed: float = clampf(velocity.length() / 500.0, 0.0, 1.0)
		var impact_dmg: int = int(lerpf(10.0, 50.0, impact_speed))
		AudioManager.play("explosion", -2.0, 1.2)
		_spawn_vfx(Color(0.3, 1.0, 1.0, 0.7), Vector2(40 + impact_speed * 40, 16))
		_screen_shake(impact_speed * 5.0, 0.15)

		for body in get_tree().get_nodes_in_group("enemies"):
			if not body is Node2D:
				continue
			var dist: float = global_position.distance_to(body.global_position)
			if dist < 50.0 + impact_speed * 30.0 and body.has_method("take_damage"):
				body.take_damage(impact_dmg, player_index)
				if body.has_method("apply_knockback"):
					var kb: Vector2 = (body.global_position - global_position).normalized()
					body.apply_knockback(kb * 300.0)

	# Speed trails while moving fast
	if velocity.length() > 200.0 and randi() % 3 == 0:
		var trail := ColorRect.new()
		trail.color = Color(0.3, 1.0, 1.0, 0.25)
		trail.size = Vector2(4, 4)
		trail.position = global_position + Vector2(randf_range(-4, 4), randf_range(-4, 4))
		trail.z_index = -1
		get_parent().add_child(trail)
		var tt := trail.create_tween()
		tt.tween_property(trail, "modulate:a", 0.0, 0.2)
		tt.tween_callback(trail.queue_free)


func _charged_jumper_meteor(charge_ratio: float) -> void:
	# METEOR DROP - launch up then slam down with massive impact
	AudioManager.play("jump", 2.0, 0.4)
	velocity.y = lerpf(-600.0, -900.0, charge_ratio)
	_jumper_dive_active = true
	modulate = Color(1.0, 0.6, 0.2)  # Orange meteor tint

	# Delay then dive - after reaching apex
	await get_tree().create_timer(lerpf(0.3, 0.6, charge_ratio)).timeout
	if not is_inside_tree():
		return
	velocity.y = lerpf(500.0, 900.0, charge_ratio)
	velocity.x = 0.0
	modulate = Color(1.0, 0.3, 0.1)  # Red-hot
	_spawn_vfx(Color(1.0, 0.5, 0.1, 0.7), Vector2(20, 20))
	PlayerManager.add_skill_xp(player_index, "charge", 5)


# -- Tank Abilities ------------------------------------------------------------

var _tank_fortify: bool = false
var _tank_fortify_timer: float = 0.0
var _tank_fortify_cooldown: float = 0.0
const TANK_FORTIFY_DURATION := 8.0
const TANK_FORTIFY_COOLDOWN := 25.0

func _attack_tank() -> void:
	# Heavy mace slam - slow, wide, powerful
	AudioManager.play("sword_slash", 2.0, 0.5)
	_attack_cooldown = 1.2  # Very slow
	var aim: Vector2 = _get_aim_direction()
	var base_dmg: int = int(45 * PlayerManager.get_skill_bonus(player_index, "attack"))
	if _tank_fortify:
		base_dmg = int(base_dmg * 0.5)  # Less damage while fortified (tradeoff)
	PlayerManager.add_skill_xp(player_index, "attack", 2)

	# Wide attack area
	attack_area.position = aim * 20.0
	attack_area.monitoring = true
	await get_tree().physics_frame
	if not is_inside_tree():
		return

	# VFX: ground slam impact
	_spawn_vfx(Color(0.7, 0.6, 0.4, 0.6), Vector2(40, 20))

	for body in attack_area.get_overlapping_bodies():
		if body.has_method("take_damage"):
			body.take_damage(base_dmg, player_index)
			_spawn_blood_particles(body.global_position)
		if body.has_method("apply_knockback"):
			var kb: Vector2 = aim * 250.0
			body.apply_knockback(kb)
	await get_tree().create_timer(0.15).timeout
	if is_inside_tree():
		attack_area.monitoring = false


func _special_tank_slam() -> void:
	# Ground pound - AoE stun around the tank
	AudioManager.play("explosion", 2.0, 0.6)
	AudioManager.play("shield_charge", 0.0, 0.4)
	_screen_shake(6.0, 0.25)
	_spawn_vfx(Color(0.6, 0.5, 0.3, 0.7), Vector2(80, 80))

	# Damage + stun all enemies in radius
	for body in get_tree().get_nodes_in_group("enemies"):
		if not body is Node2D:
			continue
		var dist: float = global_position.distance_to(body.global_position)
		if dist < 80.0:
			if body.has_method("take_damage"):
				body.take_damage(30, player_index)
			if body.has_method("apply_knockback"):
				var kb: Vector2 = (body.global_position - global_position).normalized() * 150.0
				body.apply_knockback(kb)
			# Stun via hurt timer
			if body.has_method("apply_slow"):
				body.apply_slow(2.0)
	PlayerManager.add_skill_xp(player_index, "special", 7)


func _handle_tank_fortify(delta: float) -> void:
	if character_class != PlayerManager.CharacterClass.TANK:
		return
	if _tank_fortify_cooldown > 0.0:
		_tank_fortify_cooldown -= delta

	if _is_device_action_just_pressed("interact"):
		if _tank_fortify:
			return
		if _tank_fortify_cooldown > 0.0:
			_spawn_fail_flash()
			return
		# FORTIFY!
		_tank_fortify = true
		_tank_fortify_timer = TANK_FORTIFY_DURATION
		AudioManager.play("shield_charge", 2.0, 0.3)
		modulate = Color(0.7, 0.65, 0.5)
		_spawn_vfx(Color(0.8, 0.7, 0.4, 0.6), Vector2(30, 30))
		var fort_text := Label.new()
		fort_text.text = "FORTIFIED!"
		fort_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fort_text.add_theme_font_size_override("font_size", 12)
		fort_text.modulate = Color(0.8, 0.7, 0.4)
		fort_text.position = global_position + Vector2(-25, -40)
		fort_text.z_index = 15
		get_parent().add_child(fort_text)
		var tt := fort_text.create_tween()
		tt.tween_property(fort_text, "position:y", fort_text.position.y - 15, 0.6)
		tt.parallel().tween_property(fort_text, "modulate:a", 0.0, 0.6)
		tt.tween_callback(fort_text.queue_free)

	if _tank_fortify:
		_tank_fortify_timer -= delta
		# Pulsing bronze glow
		modulate = Color(0.7, 0.65 + sin(_tank_fortify_timer * 4.0) * 0.05, 0.5)
		# Warning
		if _tank_fortify_timer <= 2.0:
			if fmod(_tank_fortify_timer, 0.25) < 0.125:
				modulate = Color.WHITE
		if _tank_fortify_timer <= 0.0:
			_tank_fortify = false
			_tank_fortify_cooldown = TANK_FORTIFY_COOLDOWN
			modulate = Color.WHITE


# -- Melee Enrage (Circle) -----------------------------------------------------

func _handle_melee_enrage(delta: float) -> void:
	if character_class != PlayerManager.CharacterClass.MELEE:
		return
	if _melee_enrage_cooldown > 0.0:
		_melee_enrage_cooldown -= delta

	# Toggle enrage on Circle press
	if _is_device_action_just_pressed("interact"):
		if _melee_enraged:
			return  # Can't cancel early
		if _melee_enrage_cooldown > 0.0:
			_spawn_fail_flash()
			return
		# ENRAGE!
		_melee_enraged = true
		_melee_enrage_timer = MELEE_ENRAGE_DURATION
		AudioManager.play("enrage_roar")
		AudioManager.play("shield_charge", 2.0, 0.5)
		modulate = Color(1.3, 0.3, 0.2)
		# Burst VFX
		_spawn_vfx(Color(1.0, 0.2, 0.1, 0.7), Vector2(40, 40))
		# "ENRAGED!" text
		var rage_text := Label.new()
		rage_text.text = "ENRAGED!"
		rage_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rage_text.add_theme_font_size_override("font_size", 14)
		rage_text.modulate = Color(1.0, 0.3, 0.1)
		rage_text.position = global_position + Vector2(-25, -40)
		rage_text.z_index = 15
		get_parent().add_child(rage_text)
		var tt := rage_text.create_tween()
		tt.tween_property(rage_text, "position:y", rage_text.position.y - 20, 0.8)
		tt.parallel().tween_property(rage_text, "modulate:a", 0.0, 0.8)
		tt.tween_callback(rage_text.queue_free)

	# While enraged
	if _melee_enraged:
		_melee_enrage_timer -= delta

		# Pulsing red glow
		var pulse: float = 0.2 + sin(_melee_enrage_timer * 6.0) * 0.1
		modulate = Color(1.3, 0.3 + pulse, 0.2 + pulse)

		# Red particles emit while enraged
		if randi() % 6 == 0:
			var rp := ColorRect.new()
			rp.color = Color(1.0, 0.2, 0.0, 0.6)
			rp.size = Vector2(3, 3)
			rp.position = global_position + Vector2(randf_range(-8, 8), randf_range(-5, 5))
			rp.z_index = 5
			get_parent().add_child(rp)
			var rt := rp.create_tween()
			rt.tween_property(rp, "position:y", rp.position.y - randf_range(10, 20), 0.3)
			rt.parallel().tween_property(rp, "modulate:a", 0.0, 0.3)
			rt.tween_callback(rp.queue_free)

		# Warning flicker when almost done
		if _melee_enrage_timer <= 2.0:
			if fmod(_melee_enrage_timer, 0.2) < 0.1:
				modulate = Color.WHITE

		# Enrage ends
		if _melee_enrage_timer <= 0.0:
			_melee_enraged = false
			_melee_enrage_cooldown = MELEE_ENRAGE_COOLDOWN
			modulate = Color.WHITE
			AudioManager.play("player_hurt", -4.0, 0.8)


# -- Healer Wind Gust (Circle) -------------------------------------------------

var _healer_gust_cooldown: float = 0.0
const HEALER_GUST_COOLDOWN := 8.0
const HEALER_GUST_RADIUS := 100.0
const HEALER_GUST_FORCE := 400.0

func _handle_healer_wind_gust() -> void:
	if character_class != PlayerManager.CharacterClass.HEALER:
		return
	if _healer_gust_cooldown > 0.0:
		_healer_gust_cooldown -= get_process_delta_time()
	if not _is_device_action_just_pressed("interact"):
		return
	if _healer_gust_cooldown > 0.0:
		_spawn_fail_flash()
		return

	_healer_gust_cooldown = HEALER_GUST_COOLDOWN
	AudioManager.play("wind_gust")
	AudioManager.play("jump", 2.0, 0.5)

	# Expanding wind ring VFX
	for ring_i in range(3):
		var ring := ColorRect.new()
		ring.color = Color(0.8, 0.9, 1.0, 0.4 - ring_i * 0.1)
		var ring_size: float = 16.0 + ring_i * 8.0
		ring.size = Vector2(ring_size, ring_size)
		ring.position = global_position - Vector2(ring_size / 2.0, ring_size / 2.0)
		ring.pivot_offset = Vector2(ring_size / 2.0, ring_size / 2.0)
		ring.z_index = 8
		get_parent().add_child(ring)
		var scale_target: float = HEALER_GUST_RADIUS * 2.0 / ring_size
		var rt := ring.create_tween()
		rt.set_parallel(true)
		rt.tween_property(ring, "scale", Vector2(scale_target, scale_target), 0.3 + ring_i * 0.1)
		rt.tween_property(ring, "modulate:a", 0.0, 0.35 + ring_i * 0.1)
		rt.chain().tween_callback(ring.queue_free)

	# Wind line particles shooting outward
	for i in range(16):
		var angle: float = float(i) * TAU / 16.0
		var dir: Vector2 = Vector2(cos(angle), sin(angle))
		var wind_p := ColorRect.new()
		wind_p.color = Color(0.85, 0.9, 1.0, 0.6)
		wind_p.size = Vector2(6, 2)
		wind_p.rotation = angle
		wind_p.position = global_position + dir * 8.0
		wind_p.z_index = 9
		get_parent().add_child(wind_p)
		var wt := wind_p.create_tween()
		wt.tween_property(wind_p, "position", wind_p.position + dir * HEALER_GUST_RADIUS, 0.25)
		wt.parallel().tween_property(wind_p, "modulate:a", 0.0, 0.3)
		wt.tween_callback(wind_p.queue_free)

	# Push ALL enemies away
	for body in get_tree().get_nodes_in_group("enemies"):
		if not body is Node2D:
			continue
		var dist: float = global_position.distance_to(body.global_position)
		if dist < HEALER_GUST_RADIUS and dist > 1.0:
			var push_dir: Vector2 = (body.global_position - global_position).normalized()
			var push_strength: float = HEALER_GUST_FORCE * (1.0 - dist / HEALER_GUST_RADIUS)
			if body.has_method("apply_knockback"):
				body.apply_knockback(push_dir * push_strength)
			elif "velocity" in body:
				body.velocity += push_dir * push_strength
			# Small damage from the gust
			if body.has_method("take_damage"):
				body.take_damage(5, player_index)

	# Push other players away too (friendly push, no damage)
	for body in get_tree().get_nodes_in_group("players"):
		if body == self or not body is Node2D:
			continue
		var dist: float = global_position.distance_to(body.global_position)
		if dist < HEALER_GUST_RADIUS and dist > 1.0:
			var push_dir: Vector2 = (body.global_position - global_position).normalized()
			var push_strength: float = HEALER_GUST_FORCE * 0.6 * (1.0 - dist / HEALER_GUST_RADIUS)
			if "velocity" in body:
				body.velocity += push_dir * push_strength

	_screen_shake(3.0, 0.15)


# -- Ranger Fire Crossbow (Triangle) -------------------------------------------

func _ranger_fire_crossbow() -> void:
	if _ranger_arrows <= 0:
		_spawn_fail_flash()
		AudioManager.play("reload_click", -4.0)
		return

	_ranger_arrows -= 1
	AudioManager.play("crossbow_shoot", 0.0, 0.8)
	var scaled_dmg: int = int(60 * PlayerManager.get_skill_bonus(player_index, "attack"))
	_spawn_projectile(scaled_dmg, 400.0, "crossbow_bolt")
	PlayerManager.add_skill_xp(player_index, "attack", 2)


# -- Ranger Grapple (Circle) ---------------------------------------------------

func _handle_ranger_grapple() -> void:
	if character_class != PlayerManager.CharacterClass.RANGED:
		return

	# Check for special press to release/tug while connected (bypasses cooldown)
	if _grapple_state in [GrappleState.SWINGING, GrappleState.CONNECTED]:
		if _is_device_action_just_pressed("special"):
			if _grapple_anchor_entity and is_instance_valid(_grapple_anchor_entity):
				_grapple_tug()
			else:
				_grapple_release()

	if _grapple_state == GrappleState.IDLE:
		return

	var delta: float = get_process_delta_time()

	match _grapple_state:
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

	queue_redraw()


func _grapple_tick_windup(delta: float) -> void:
	_grapple_hold_time += delta
	_grapple_angular_vel = minf(
		GRAPPLE_BASE_ANGULAR_VEL + _grapple_hold_time * GRAPPLE_ANGULAR_ACCEL,
		GRAPPLE_MAX_ANGULAR_VEL
	)
	_grapple_angle += _grapple_angular_vel * delta

	# Hook orbits player
	_grapple_hook_pos = global_position + Vector2(
		cos(_grapple_angle) * GRAPPLE_SWING_RADIUS,
		sin(_grapple_angle) * GRAPPLE_SWING_RADIUS
	)

	# Release check: special button released
	if not _is_device_action_pressed("special"):
		if _grapple_hold_time >= GRAPPLE_MIN_HOLD:
			_grapple_throw()
		else:
			_grapple_state = GrappleState.IDLE


func _grapple_throw() -> void:
	var aim: Vector2 = _get_aim_direction_analog()
	var throw_speed: float = clampf(
		GRAPPLE_BASE_THROW_SPEED + _grapple_hold_time * GRAPPLE_THROW_SPEED_PER_SEC,
		GRAPPLE_BASE_THROW_SPEED,
		GRAPPLE_MAX_THROW_SPEED
	)
	_grapple_hook_vel = aim * throw_speed
	_grapple_hook_pos = global_position
	_grapple_state = GrappleState.THROWN
	_grapple_anchor_entity = null
	AudioManager.play("grapple_launch")

	# Initialize rope points
	_grapple_rope_points.clear()
	for i in range(GRAPPLE_ROPE_SEGMENTS):
		_grapple_rope_points.append(global_position)


func _grapple_tick_thrown(delta: float) -> void:
	# Apply gravity and drag to hook
	_grapple_hook_vel.y += GRAPPLE_HOOK_GRAVITY * delta
	_grapple_hook_vel *= GRAPPLE_HOOK_DRAG
	var prev_pos: Vector2 = _grapple_hook_pos
	_grapple_hook_pos += _grapple_hook_vel * delta

	# Raycast along movement for collision
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		prev_pos, _grapple_hook_pos,
		1 | 8  # world + enemies
	)
	query.exclude = [get_rid()]
	var result: Dictionary = space.intersect_ray(query)

	if result:
		_grapple_hook_pos = result["position"]
		_grapple_anchor = result["position"]
		var collider: Node = result["collider"]
		if collider.is_in_group("enemies"):
			_grapple_anchor_entity = collider as Node2D
			if collider.has_method("take_damage"):
				collider.take_damage(GRAPPLE_HOOK_DAMAGE, player_index)
				PlayerManager.add_skill_xp(player_index, "special", 5)
		AudioManager.play("grapple_hit")
		_grapple_state = GrappleState.CONNECTED
		_grapple_rope_len = global_position.distance_to(_grapple_anchor)

		# Launch player toward anchor
		var launch_dir: Vector2 = (_grapple_anchor - global_position).normalized()
		velocity = launch_dir * abs(JUMP_VELOCITY) * GRAPPLE_LAUNCH_SPEED_RATIO
		return

	# Update rope points (trail behind hook)
	_grapple_update_rope_thrown()

	# Max range check - if hook is too far, retract
	if global_position.distance_to(_grapple_hook_pos) > GRAPPLE_MAX_ROPE_LEN * 1.5:
		_grapple_start_retract()


func _grapple_update_rope_thrown() -> void:
	if _grapple_rope_points.is_empty():
		return
	# First point = player, last = hook
	_grapple_rope_points[0] = global_position
	_grapple_rope_points[GRAPPLE_ROPE_SEGMENTS - 1] = _grapple_hook_pos
	# Interpolate middle points with slight sag
	for i in range(1, GRAPPLE_ROPE_SEGMENTS - 1):
		var t: float = float(i) / float(GRAPPLE_ROPE_SEGMENTS - 1)
		var lerped: Vector2 = global_position.lerp(_grapple_hook_pos, t)
		var sag: float = sin(t * PI) * 15.0  # Gravity sag
		_grapple_rope_points[i] = lerped + Vector2(0, sag)


func _grapple_tick_connected(delta: float) -> void:
	# Player is launching toward anchor — check if at apex (velocity.y flips)
	if _grapple_anchor_entity and is_instance_valid(_grapple_anchor_entity):
		_grapple_anchor = _grapple_anchor_entity.global_position

	# Normal gravity still applies during launch
	# Transition to swing when rope goes taut (player within rope length)
	var dist: float = global_position.distance_to(_grapple_anchor)
	if dist <= _grapple_rope_len or velocity.y >= 0:
		_grapple_rope_len = dist
		# Calculate initial swing angle
		var diff: Vector2 = global_position - _grapple_anchor
		_grapple_swing_angle = atan2(diff.x, diff.y)  # angle from vertical
		# Convert current velocity to angular velocity
		var tangent: Vector2 = Vector2(cos(_grapple_swing_angle), -sin(_grapple_swing_angle))
		_grapple_swing_vel = velocity.dot(tangent) / maxf(_grapple_rope_len, 1.0)
		_grapple_state = GrappleState.SWINGING


func _grapple_tick_swinging(delta: float) -> void:
	# Update anchor if attached to enemy
	if _grapple_anchor_entity and is_instance_valid(_grapple_anchor_entity):
		_grapple_anchor = _grapple_anchor_entity.global_position
	elif _grapple_anchor_entity:
		# Enemy died — release
		_grapple_release()
		return

	# Pendulum physics: α = -(g/L) * sin(θ)
	var alpha: float = -(GRAPPLE_PENDULUM_GRAVITY / maxf(_grapple_rope_len, 1.0)) * sin(_grapple_swing_angle)
	# Damping
	alpha -= _grapple_swing_vel * GRAPPLE_SWING_DAMPING

	# Player input
	var input_h: float = 0.0
	var input_v: float = 0.0
	if _is_device_action_pressed("move_left"):
		input_h -= 1.0
	if _is_device_action_pressed("move_right"):
		input_h += 1.0
	if _is_device_action_pressed("move_up"):
		input_v -= 1.0
	if _is_device_action_pressed("move_down"):
		input_v += 1.0

	# Horizontal input: boost or brake swing
	if input_h != 0.0:
		if signf(input_h) == signf(_grapple_swing_vel):
			alpha += input_h * GRAPPLE_INPUT_BOOST
		else:
			alpha += input_h * GRAPPLE_INPUT_BRAKE

	# Vertical input: adjust rope length
	if input_v != 0.0:
		_grapple_rope_len = clampf(
			_grapple_rope_len + input_v * GRAPPLE_ROPE_ADJUST_SPEED * delta,
			GRAPPLE_MIN_ROPE_LEN,
			GRAPPLE_MAX_ROPE_LEN
		)

	# Integrate pendulum
	_grapple_swing_vel += alpha * delta
	_grapple_swing_angle += _grapple_swing_vel * delta

	# Position player on the pendulum arc
	var new_pos := Vector2(
		_grapple_anchor.x + _grapple_rope_len * sin(_grapple_swing_angle),
		_grapple_anchor.y + _grapple_rope_len * cos(_grapple_swing_angle)
	)
	global_position = new_pos

	# Update velocity to match pendulum motion (for momentum on release)
	var tangent: Vector2 = Vector2(cos(_grapple_swing_angle), -sin(_grapple_swing_angle))
	velocity = tangent * _grapple_swing_vel * _grapple_rope_len

	# Override gravity while swinging
	# (handled by setting position directly)


func _grapple_tug() -> void:
	## Newtonian tug when releasing from an enemy
	if not _grapple_anchor_entity or not is_instance_valid(_grapple_anchor_entity):
		_grapple_release()
		return

	_grapple_state = GrappleState.TUG

	# Deal tug damage
	if _grapple_anchor_entity.has_method("take_damage"):
		_grapple_anchor_entity.take_damage(GRAPPLE_TUG_DAMAGE, player_index)
		PlayerManager.add_skill_xp(player_index, "special", 7)

	# Get enemy mass
	var enemy_mass: float = 70.0  # default
	if "mass" in _grapple_anchor_entity:
		enemy_mass = _grapple_anchor_entity.mass

	# F = ma → a = F/m, applied as impulse over TUG_DURATION
	var dir_to_enemy: Vector2 = (_grapple_anchor_entity.global_position - global_position).normalized()
	var player_accel: float = GRAPPLE_TUG_FORCE / PLAYER_MASS
	var enemy_accel: float = GRAPPLE_TUG_FORCE / enemy_mass

	# Apply impulses
	velocity = dir_to_enemy * player_accel * GRAPPLE_TUG_DURATION
	if _grapple_anchor_entity is CharacterBody2D:
		_grapple_anchor_entity.velocity = -dir_to_enemy * enemy_accel * GRAPPLE_TUG_DURATION

	# Apply knockback if the enemy has the method
	if _grapple_anchor_entity.has_method("apply_knockback"):
		_grapple_anchor_entity.apply_knockback(-dir_to_enemy * enemy_accel * GRAPPLE_TUG_DURATION)

	AudioManager.play("grapple_hit", 0.0, 0.8)
	_spawn_blood_particles(_grapple_anchor_entity.global_position)
	_grapple_start_retract()


func _grapple_release() -> void:
	## Release from wall — keep swing momentum
	_grapple_state = GrappleState.RETRACTING
	_grapple_retract_timer = 0.2
	_grapple_anchor_entity = null
	# velocity is already set from swing


func _grapple_start_retract() -> void:
	_grapple_state = GrappleState.RETRACTING
	_grapple_retract_timer = 0.2
	_grapple_anchor_entity = null


func _grapple_tick_retracting(delta: float) -> void:
	_grapple_retract_timer -= delta
	# Animate hook back to player
	_grapple_hook_pos = _grapple_hook_pos.lerp(global_position, delta * 10.0)
	if _grapple_retract_timer <= 0.0:
		_grapple_state = GrappleState.IDLE
		_grapple_rope_points.clear()


# -- Grapple Drawing -----------------------------------------------------------

func _draw_grapple() -> void:
	if _grapple_state == GrappleState.IDLE:
		return

	var rope_color := Color(0.5, 0.4, 0.3, 0.8)
	var hook_color := Color(0.6, 0.5, 0.35)

	match _grapple_state:
		GrappleState.WINDUP:
			# Draw hook orbiting
			var hook_local: Vector2 = _grapple_hook_pos - global_position
			draw_line(Vector2.ZERO, hook_local, rope_color, 2.0)
			draw_circle(hook_local, 4.0, hook_color)

			# Draw aim direction indicator (dotted line showing throw trajectory)
			var aim: Vector2 = _get_aim_direction_analog()
			var throw_speed: float = clampf(
				GRAPPLE_BASE_THROW_SPEED + _grapple_hold_time * GRAPPLE_THROW_SPEED_PER_SEC,
				GRAPPLE_BASE_THROW_SPEED, GRAPPLE_MAX_THROW_SPEED
			)
			var indicator_len: float = throw_speed * 0.3  # Visual preview length
			var aim_color := Color(1.0, 0.8, 0.2, 0.4)
			# Dotted line: draw segments with gaps
			var dash_len: float = 8.0
			var gap_len: float = 6.0
			var total: float = 0.0
			while total < indicator_len:
				var seg_start: Vector2 = aim * total
				var seg_end: Vector2 = aim * minf(total + dash_len, indicator_len)
				draw_line(seg_start, seg_end, aim_color, 1.5)
				total += dash_len + gap_len
			# Arrowhead at the end
			var arrow_tip: Vector2 = aim * indicator_len
			var perp: Vector2 = Vector2(-aim.y, aim.x)
			draw_line(arrow_tip, arrow_tip - aim * 8.0 + perp * 5.0, aim_color, 1.5)
			draw_line(arrow_tip, arrow_tip - aim * 8.0 - perp * 5.0, aim_color, 1.5)

		GrappleState.THROWN:
			# Draw rope trailing behind hook
			if _grapple_rope_points.size() >= 2:
				for i in range(_grapple_rope_points.size() - 1):
					var a: Vector2 = _grapple_rope_points[i] - global_position
					var b: Vector2 = _grapple_rope_points[i + 1] - global_position
					draw_line(a, b, rope_color, 2.0)
			var hook_local: Vector2 = _grapple_hook_pos - global_position
			draw_circle(hook_local, 4.0, hook_color)

		GrappleState.CONNECTED, GrappleState.SWINGING:
			# Draw rope from player to anchor with physics-based slack
			var anchor_local: Vector2 = _grapple_anchor - global_position
			var straight_dist: float = anchor_local.length()
			# Slack = how much extra rope vs straight-line distance
			var slack: float = maxf(_grapple_rope_len - straight_dist, 0.0)
			var seg_count: int = maxi(int(_grapple_rope_len / GRAPPLE_ROPE_SEGMENT_LEN), 3)
			var prev_pt: Vector2 = Vector2.ZERO
			for i in range(1, seg_count + 1):
				var t: float = float(i) / float(seg_count)
				var pt: Vector2 = Vector2.ZERO.lerp(anchor_local, t)
				# Catenary-like sag: more slack = more droop, weighted toward middle
				var sag_amount: float = slack * 0.5 + 5.0  # Always slight sag + slack contribution
				pt.y += sin(t * PI) * sag_amount
				draw_line(prev_pt, pt, rope_color, 2.0)
				prev_pt = pt
			draw_circle(anchor_local, 5.0, hook_color)

		GrappleState.RETRACTING:
			var hook_local: Vector2 = _grapple_hook_pos - global_position
			draw_line(Vector2.ZERO, hook_local, rope_color * Color(1, 1, 1, 0.5), 1.5)
			draw_circle(hook_local, 3.0, hook_color * Color(1, 1, 1, 0.5))


# -- Ranger Reload -------------------------------------------------------------

func _handle_ranger_reload(delta: float) -> void:
	if character_class != PlayerManager.CharacterClass.RANGED:
		return

	# Press Circle (interact) to start/continue reloading
	if _is_device_action_pressed("interact") and _ranger_arrows < RANGER_MAX_ARROWS:
		if not _ranger_reloading:
			_ranger_reloading = true
			_ranger_reload_timer = RANGER_RELOAD_TIME
	elif not _is_device_action_pressed("interact"):
		# Released Circle - stop reloading
		_ranger_reloading = false
		_ranger_reload_timer = RANGER_RELOAD_TIME
		return

	if not _ranger_reloading:
		return

	_ranger_reload_timer -= delta
	if _ranger_reload_timer <= 0.0:
		# Reload one arrow
		_ranger_arrows = mini(_ranger_arrows + 1, RANGER_MAX_ARROWS)
		AudioManager.play("reload_click")

		# Small arrow VFX
		var arrow_text := Label.new()
		arrow_text.text = "%d/%d" % [_ranger_arrows, RANGER_MAX_ARROWS]
		arrow_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		arrow_text.add_theme_font_size_override("font_size", 8)
		arrow_text.modulate = Color(0.3, 0.8, 0.3)
		arrow_text.position = global_position + Vector2(-10, -35)
		arrow_text.z_index = 12
		get_parent().add_child(arrow_text)
		var tt := arrow_text.create_tween()
		tt.tween_property(arrow_text, "position:y", arrow_text.position.y - 10, 0.4)
		tt.parallel().tween_property(arrow_text, "modulate:a", 0.0, 0.4)
		tt.tween_callback(arrow_text.queue_free)

		if _ranger_arrows < RANGER_MAX_ARROWS:
			_ranger_reload_timer = RANGER_RELOAD_TIME
		else:
			_ranger_reloading = false


# -- Rogue Stealth -------------------------------------------------------------

func _handle_rogue_stealth_toggle() -> void:
	if character_class != PlayerManager.CharacterClass.ROGUE:
		return
	if not _is_device_action_just_pressed("interact"):
		return
	if _rogue_stealth:
		return
	if _rogue_stealth_cooldown > 0.0:
		_spawn_fail_flash()
		return

	_rogue_stealth = true
	_rogue_stealth_timer = ROGUE_STEALTH_DURATION
	AudioManager.play("stealth_activate")
	# Go nearly invisible + enemies can't see us
	remove_from_group("players")
	modulate = Color(1.0, 1.0, 1.0, 0.15)


func _handle_rogue_stealth(delta: float) -> void:
	if _rogue_stealth_cooldown > 0.0:
		_rogue_stealth_cooldown -= delta
	if not _rogue_stealth:
		return

	_rogue_stealth_timer -= delta

	# Subtle shimmer while stealthed
	modulate.a = 0.1 + sin(_rogue_stealth_timer * 8.0) * 0.05

	# Warning: flicker more when almost out
	if _rogue_stealth_timer <= 1.5:
		modulate.a = 0.15 + sin(_rogue_stealth_timer * 20.0) * 0.1

	# Time's up
	if _rogue_stealth_timer <= 0.0:
		_exit_stealth()


func _exit_stealth() -> void:
	_rogue_stealth = false
	_rogue_stealth_cooldown = ROGUE_STEALTH_COOLDOWN
	add_to_group("players")  # Enemies can see us again
	modulate = Color.WHITE
	AudioManager.play("stealth_activate", -4.0, 1.3)


func _stealth_backstab_vfx(hit_pos: Vector2) -> void:
	# "BACK STAB!" text in orange, floats up, flickers, disappears
	var label := Label.new()
	label.text = "BACK STAB!"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.modulate = Color(1.0, 0.6, 0.1)
	label.position = hit_pos + Vector2(-30, -30)
	label.z_index = 15
	get_parent().add_child(label)

	# Float up + flicker + fade
	var tween := label.create_tween()
	tween.tween_property(label, "position:y", label.position.y - 35, 1.0)
	# Flicker by toggling alpha
	for i in range(6):
		tween.parallel().tween_property(label, "modulate:a", 0.2, 0.08).set_delay(0.1 * i)
		tween.parallel().tween_property(label, "modulate:a", 1.0, 0.08).set_delay(0.1 * i + 0.08)
	tween.tween_property(label, "modulate:a", 0.0, 0.2)
	tween.tween_callback(label.queue_free)


# -- Mage Air-Walk -------------------------------------------------------------

func _handle_mage_airwalk_toggle() -> void:
	if character_class != PlayerManager.CharacterClass.MAGE:
		return
	if not _is_device_action_just_pressed("interact"):
		return
	if _mage_airwalk:
		return
	if _mage_airwalk_cooldown > 0.0:
		_spawn_fail_flash()
		return

	_mage_airwalk = true
	_mage_airwalk_timer = MAGE_AIRWALK_DURATION
	AudioManager.play("airwalk_activate")
	modulate = Color(0.7, 0.7, 1.0, 0.9)


func _handle_mage_airwalk(delta: float) -> void:
	if _mage_airwalk_cooldown > 0.0:
		_mage_airwalk_cooldown -= delta
	if not _mage_airwalk:
		return

	_mage_airwalk_timer -= delta

	# Drain mana while air-walking (10 mana/sec)
	if not PlayerManager.use_mana(player_index, 0):
		pass  # Just checking
	var p_data: Dictionary = PlayerManager.get_player(player_index)
	if not p_data.is_empty():
		p_data["mana"] = maxf(0.0, p_data["mana"] - 10.0 * delta)
		if p_data["mana"] <= 0.0:
			_mage_airwalk = false
			_mage_airwalk_cooldown = MAGE_AIRWALK_COOLDOWN
			modulate = Color.WHITE
			AudioManager.play("player_hurt", -6.0, 1.5)
			return

	# Cancel gravity - mage walks on air
	if not is_on_floor():
		velocity.y = 0.0

	# Move at half speed while air-walking
	var air_speed: float = PlayerManager.get_player(player_index).get("speed", 90) * 0.5
	velocity.x *= 0.5  # Halve the horizontal speed set by _handle_movement

	# Can also move up/down with the stick
	if _is_device_action_pressed("move_up"):
		velocity.y = -air_speed
	elif _is_device_action_pressed("move_down"):
		velocity.y = air_speed
	elif not is_on_floor():
		velocity.y = 0.0

	# Sparkle trail under feet
	if randi() % 4 == 0:
		var sparkle := ColorRect.new()
		sparkle.color = [Color(0.6, 0.5, 1.0, 0.5), Color(0.8, 0.7, 1.0, 0.4), Color(1.0, 1.0, 1.0, 0.3)][randi() % 3]
		sparkle.size = Vector2(3, 3)
		sparkle.position = global_position + Vector2(randf_range(-6, 6), randf_range(8, 14))
		sparkle.z_index = -1
		get_parent().add_child(sparkle)
		var st := sparkle.create_tween()
		st.tween_property(sparkle, "position:y", sparkle.position.y + randf_range(5, 15), 0.4)
		st.parallel().tween_property(sparkle, "modulate:a", 0.0, 0.4)
		st.tween_callback(sparkle.queue_free)

	# Timer warning: flash when almost out
	if _mage_airwalk_timer <= 1.5:
		if fmod(_mage_airwalk_timer, 0.3) < 0.15:
			modulate = Color(1.0, 0.5, 0.5, 0.85)
		else:
			modulate = Color(0.7, 0.7, 1.0, 0.9)

	# Time's up
	if _mage_airwalk_timer <= 0.0:
		_mage_airwalk = false
		_mage_airwalk_cooldown = MAGE_AIRWALK_COOLDOWN
		modulate = Color.WHITE
		AudioManager.play("player_hurt", -6.0, 1.5)


# -- Summoner Delegate Mode ----------------------------------------------------

func _handle_delegate_toggle() -> void:
	if character_class != PlayerManager.CharacterClass.SUMMONER:
		return
	if _delegate_cooldown > 0.0:
		_delegate_cooldown -= get_process_delta_time()
	if not _is_device_action_just_pressed("interact"):
		return

	if _delegate_active:
		_exit_delegate_mode()
	elif _delegate_cooldown <= 0.0:
		_enter_delegate_mode()
	else:
		_spawn_fail_flash()


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
	_delegate_cooldown = DELEGATE_COOLDOWN

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

		# Werewolf: track press start but DON'T charge instantly
		# (quick taps need to do triple slash, hold does pounce)
		if character_class == PlayerManager.CharacterClass.WEREWOLF:
			_charge_time = 0.0

	# Transition from normal hold to charge (0.15s for werewolf, 0.3s others)
	if pressing_attack and _was_pressing_attack and not _is_charging and _attack_cooldown <= 0.0:
		_charge_time += delta
		var charge_threshold: float = 0.15 if character_class == PlayerManager.CharacterClass.WEREWOLF else 0.3
		if _charge_time >= charge_threshold:
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
		# Button held - charging (charge speed scales with charge skill)
		var charge_speed_bonus: float = PlayerManager.get_skill_bonus(player_index, "charge")
		_charge_time = minf(_charge_time + delta * charge_speed_bonus, CHARGE_MAX)
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
		elif character_class == PlayerManager.CharacterClass.WEREWOLF:
			# Werewolf crouches while charging pounce
			sprite.scale.y = 0.7
			var shake_x: float = randf_range(-1.0, 1.0)
			position.x += shake_x * 0.5
			modulate = Color(0.7, 0.5, 0.3, 1.0)
			if _charge_time > 0.3 and fmod(_charge_time, 0.4) < 0.05:
				AudioManager.play("boss_roar", -6.0, 0.4)
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
		# Reset werewolf crouch
		if character_class == PlayerManager.CharacterClass.WEREWOLF:
			sprite.scale.y = 1.0
		if _charge_time >= CHARGE_MIN:
			# Fire charged attack
			_attack_cooldown = ATTACK_COOLDOWN_TIME
			_is_attacking = true
			_attack_timer = ATTACK_DURATION
			PlayerManager.add_skill_xp(player_index, "charge", 5)
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
		PlayerManager.CharacterClass.TANK:
			_charged_tank_shockwave(charge_ratio)
		PlayerManager.CharacterClass.NINJA:
			_charged_jumper_meteor(charge_ratio)
		PlayerManager.CharacterClass.BALLOONIST:
			_charged_balloonist_barrage(charge_ratio)
		PlayerManager.CharacterClass.GUITARIST:
			_charged_guitarist_power_chord(charge_ratio)
		PlayerManager.CharacterClass.WEREWOLF:
			_charged_werewolf_pounce(charge_ratio)


func _charged_tank_shockwave(charge_ratio: float) -> void:
	# Massive ground shockwave - bigger than special, stuns longer
	var radius: float = lerpf(60.0, 160.0, charge_ratio)
	var damage: int = int(lerpf(20.0, 70.0, charge_ratio))
	var stun_time: float = lerpf(1.0, 4.0, charge_ratio)
	AudioManager.play("explosion", 4.0, 0.3)
	_screen_shake(lerpf(4.0, 12.0, charge_ratio), 0.3)
	_spawn_vfx(Color(0.6, 0.5, 0.3, 0.8), Vector2(radius * 2, radius * 2))
	for body in get_tree().get_nodes_in_group("enemies"):
		if not body is Node2D:
			continue
		var dist: float = global_position.distance_to(body.global_position)
		if dist < radius:
			if body.has_method("take_damage"):
				body.take_damage(damage, player_index)
			if body.has_method("apply_knockback"):
				var kb: Vector2 = (body.global_position - global_position).normalized() * 300.0
				body.apply_knockback(kb)
			if body.has_method("apply_slow"):
				body.apply_slow(stun_time)
	PlayerManager.add_skill_xp(player_index, "charge", 5)


func _charged_melee_slam(charge_ratio: float) -> void:
	var atk_bonus: float = PlayerManager.get_skill_bonus(player_index, "attack")
	if not is_on_floor():
		# Already hovering, slam down
		_ground_slam_active = true
		velocity.y = 600.0 + charge_ratio * 200.0
		AudioManager.play("sword_slash", 2.0, 0.5)
		modulate = Color(1.0, 0.4, 0.1)
	else:
		# On ground: AoE stomp
		var blast_radius: float = lerpf(40.0, 120.0, charge_ratio)
		var damage: int = int(lerpf(30.0, 80.0, charge_ratio) * atk_bonus)
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
	# BEAM OF LIGHT - costs lots of mana, deals massive damage
	var mana_cost: int = int(lerpf(40.0, 100.0, charge_ratio))
	if not PlayerManager.use_mana(player_index, mana_cost):
		_spawn_fail_flash()
		return

	var aim: Vector2 = _get_aim_direction()
	var beam_range: float = lerpf(200.0, 500.0, charge_ratio)
	var beam_width: float = lerpf(8.0, 24.0, charge_ratio)
	var beam_damage: int = int(lerpf(40.0, 120.0, charge_ratio))
	var beam_hits: int = int(lerpf(3.0, 8.0, charge_ratio))  # Hits per enemy

	AudioManager.play("beam_fire")
	AudioManager.play("shield_charge", 2.0, 1.5)
	PlayerManager.add_skill_xp(player_index, "charge", 5)

	# Brief charge-up flash
	modulate = Color(1.0, 1.0, 2.0)

	# --- Raycast to find beam endpoint ---
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		global_position,
		global_position + aim * beam_range,
		1  # World layer only for endpoint
	)
	query.exclude = [get_rid()]
	var result: Dictionary = space.intersect_ray(query)
	var beam_end: Vector2 = global_position + aim * beam_range
	if result:
		beam_end = result["position"]

	var beam_length: float = global_position.distance_to(beam_end)

	# --- Draw the beam (multiple layers for glow effect) ---
	var beam_start: Vector2 = global_position + aim * 8.0

	# Outer glow (wide, faint)
	var glow := ColorRect.new()
	glow.color = Color(0.6, 0.5, 1.0, 0.3)
	glow.size = Vector2(beam_length, beam_width * 3.0)
	glow.position = beam_start - Vector2(0, beam_width * 1.5).rotated(aim.angle())
	glow.rotation = aim.angle()
	glow.z_index = 8
	get_parent().add_child(glow)

	# Middle beam (bright purple/white)
	var mid_beam := ColorRect.new()
	mid_beam.color = Color(0.8, 0.6, 1.0, 0.7)
	mid_beam.size = Vector2(beam_length, beam_width * 1.5)
	mid_beam.position = beam_start - Vector2(0, beam_width * 0.75).rotated(aim.angle())
	mid_beam.rotation = aim.angle()
	mid_beam.z_index = 9
	get_parent().add_child(mid_beam)

	# Core beam (white-hot center)
	var core := ColorRect.new()
	core.color = Color(1.0, 1.0, 1.0, 0.9)
	core.size = Vector2(beam_length, beam_width * 0.5)
	core.position = beam_start - Vector2(0, beam_width * 0.25).rotated(aim.angle())
	core.rotation = aim.angle()
	core.z_index = 10
	get_parent().add_child(core)

	# --- Sparkle particles along the beam ---
	for i in range(int(beam_length / 8.0)):
		var t: float = float(i) / maxf(beam_length / 8.0, 1.0)
		var spark_pos: Vector2 = beam_start.lerp(beam_end, t) + Vector2(randf_range(-beam_width, beam_width), randf_range(-beam_width, beam_width))
		var spark := ColorRect.new()
		spark.color = [Color(1.0, 1.0, 1.0, 0.8), Color(0.7, 0.5, 1.0, 0.7), Color(0.9, 0.8, 1.0, 0.6)][i % 3]
		spark.size = Vector2(3, 3)
		spark.position = spark_pos
		spark.z_index = 11
		get_parent().add_child(spark)
		var st := spark.create_tween()
		st.tween_property(spark, "position", spark_pos + Vector2(randf_range(-15, 15), randf_range(-15, 15)), randf_range(0.2, 0.5))
		st.parallel().tween_property(spark, "modulate:a", 0.0, randf_range(0.3, 0.5))
		st.tween_callback(spark.queue_free)

	# --- Deal damage to all enemies along the beam ---
	var hit_enemies: Array = []
	for body in get_tree().get_nodes_in_group("enemies"):
		if not body is Node2D:
			continue
		# Check if enemy is within the beam rectangle
		var to_enemy: Vector2 = body.global_position - global_position
		var along_beam: float = to_enemy.dot(aim)
		if along_beam < 0 or along_beam > beam_length:
			continue
		var perp_dist: float = absf(to_enemy.cross(aim))
		if perp_dist < beam_width * 2.0:
			# HIT! Apply damage multiple times (beam burns)
			if body.has_method("take_damage"):
				for h in range(beam_hits):
					body.take_damage(int(beam_damage / beam_hits), player_index)
				hit_enemies.append(body)
				_spawn_blood_particles(body.global_position)
				# Knockback away from beam
				if body.has_method("apply_knockback"):
					var kb: Vector2 = aim * 200.0
					body.apply_knockback(kb)

	# --- Fade out the beam ---
	var fade_time: float = lerpf(0.3, 0.6, charge_ratio)
	var fade_tw := create_tween()
	fade_tw.set_parallel(true)
	fade_tw.tween_property(glow, "modulate:a", 0.0, fade_time)
	fade_tw.tween_property(mid_beam, "modulate:a", 0.0, fade_time * 0.8)
	fade_tw.tween_property(core, "modulate:a", 0.0, fade_time * 0.6)
	fade_tw.chain().tween_callback(glow.queue_free)
	fade_tw.tween_callback(mid_beam.queue_free)
	fade_tw.tween_callback(core.queue_free)

	# Screen shake
	_screen_shake(lerpf(2.0, 8.0, charge_ratio), 0.2)

	# Reset modulate
	var mod_tw := create_tween()
	mod_tw.tween_property(self, "modulate", Color.WHITE, 0.3)


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
	# Charged knife fan: more charge = more knives, wider spread, bigger hitbox, more damage
	var knife_count: int = int(lerpf(3.0, 9.0, charge_ratio))
	var spread_angle: float = lerpf(0.3, 1.2, charge_ratio)  # radians total spread
	var damage_per_knife: int = int(lerpf(10.0, 25.0, charge_ratio))
	var knife_speed: float = lerpf(350.0, 500.0, charge_ratio)
	var knife_size: float = lerpf(1.0, 2.0, charge_ratio)  # scale multiplier

	AudioManager.play("dagger_stab", 2.0, lerpf(1.0, 0.6, charge_ratio))
	PlayerManager.add_skill_xp(player_index, "charge", 5)

	var base_dir: Vector2 = Vector2(1.0 if _facing_right else -1.0, 0.0)

	# Spawn VFX sweep arc
	var arc_width: float = lerpf(30.0, 80.0, charge_ratio)
	var arc_height: float = lerpf(20.0, 50.0, charge_ratio)
	var arc_vfx := ColorRect.new()
	arc_vfx.color = Color(0.8, 0.15, 0.15, 0.5)
	arc_vfx.size = Vector2(arc_width, arc_height)
	arc_vfx.position = global_position + Vector2(
		-arc_width / 2.0 if not _facing_right else 0,
		-arc_height / 2.0
	)
	arc_vfx.z_index = 7
	get_parent().add_child(arc_vfx)
	var arc_tween := arc_vfx.create_tween()
	arc_tween.set_parallel(true)
	arc_tween.tween_property(arc_vfx, "modulate:a", 0.0, 0.25)
	arc_tween.tween_property(arc_vfx, "scale:x", 1.5, 0.25)
	arc_tween.chain().tween_callback(arc_vfx.queue_free)

	# Spawn knives in a fan
	for i in range(knife_count):
		var t: float = 0.0
		if knife_count > 1:
			t = float(i) / float(knife_count - 1)
		var angle: float = lerpf(-spread_angle / 2.0, spread_angle / 2.0, t)
		var dir: Vector2 = base_dir.rotated(angle)

		var knife_scene := load("res://scenes/characters/projectile.tscn") as PackedScene
		if not knife_scene:
			continue
		var knife := knife_scene.instantiate()
		knife.damage = damage_per_knife
		knife.speed = knife_speed
		knife.direction = dir
		knife.projectile_type = "knife"
		knife.owner_index = player_index
		knife.global_position = global_position + base_dir * 12.0
		if knife_size > 1.1:
			knife.scale = Vector2(knife_size, knife_size)
		get_parent().add_child(knife)

	# Red/crimson particle burst
	for p_i in range(int(lerpf(4.0, 12.0, charge_ratio))):
		var particle := ColorRect.new()
		particle.color = Color(0.8, 0.1, 0.1, 0.7)
		particle.size = Vector2(3 + charge_ratio * 3, 3 + charge_ratio * 3)
		particle.position = global_position + Vector2(randf_range(-10, 10), randf_range(-10, 10))
		particle.z_index = 8
		get_parent().add_child(particle)
		var p_dir: Vector2 = base_dir.rotated(randf_range(-spread_angle, spread_angle))
		var pt := particle.create_tween()
		pt.tween_property(particle, "position", particle.position + p_dir * randf_range(20, 50), 0.3)
		pt.parallel().tween_property(particle, "modulate:a", 0.0, 0.3)
		pt.tween_callback(particle.queue_free)


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
	var aim: Vector2 = _get_aim_direction()
	# Spawn a bomb projectile that arcs with gravity
	var bomb := ColorRect.new()
	bomb.color = Color(0.9, 0.6, 0.1)
	bomb.size = Vector2(8, 8)
	bomb.z_index = 5
	get_parent().add_child(bomb)
	bomb.global_position = global_position + aim * 12.0

	var bomb_vel: Vector2 = aim * 180.0 + Vector2(0, -200.0)
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
		var base_dmg: int = int(25 * (1.0 + _demo_power_tier * 0.25) * PlayerManager.get_skill_bonus(player_index, "attack"))
		var base_rad: float = 60.0 * (1.0 + _demo_size_tier * 0.20)
		PlayerManager.add_skill_xp(player_index, "attack", 2)
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
		var big_dmg: int = int(50 * (1.0 + _demo_power_tier * 0.25) * PlayerManager.get_skill_bonus(player_index, "attack"))
		var big_rad: float = 90.0 * (1.0 + _demo_size_tier * 0.20)
		_demolitionist_explode(explode_pos, big_dmg, big_rad)


# -- Healer -------------------------------------------------------------------

func _attack_healer() -> void:
	# Throw a healing potion in aimed direction
	AudioManager.play("summon", -3.0, 1.2)
	var throw_dir: Vector2 = _get_aim_direction()

	# Default target: aimed direction. Override if injured ally nearby in that direction.
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
	PlayerManager.add_skill_xp(player_index, "attack", 2)
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


# -- Guitarist -----------------------------------------------------------------

var _guitarist_amp_up_active: bool = false
var _guitarist_amp_up_timer: float = 0.0
var _guitarist_amp_up_cooldown: float = 0.0
const GUITARIST_AMP_DURATION := 15.0
const GUITARIST_AMP_COOLDOWN := 30.0
const GUITARIST_AMP_RADIUS := 80.0


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


func _handle_guitarist_amp_up(delta: float) -> void:
	if character_class != PlayerManager.CharacterClass.GUITARIST:
		return
	if _guitarist_amp_up_cooldown > 0.0:
		_guitarist_amp_up_cooldown -= delta

	# Toggle amp up on Circle press
	if _is_device_action_just_pressed("interact"):
		if _guitarist_amp_up_active:
			return  # Can't cancel early
		if _guitarist_amp_up_cooldown > 0.0:
			_spawn_fail_flash()
			return
		# AMP UP!
		_guitarist_amp_up_active = true
		_guitarist_amp_up_timer = GUITARIST_AMP_DURATION
		AudioManager.play("shield_charge", 2.0, 0.6)
		AudioManager.play("menu_confirm", 0.0, 0.8)
		modulate = Color(1.2, 1.0, 0.5)

		# "AMP UP!" text
		var amp_text := Label.new()
		amp_text.text = "AMP UP!"
		amp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		amp_text.add_theme_font_size_override("font_size", 14)
		amp_text.modulate = Color(1.0, 0.9, 0.2)
		amp_text.position = global_position + Vector2(-22, -40)
		amp_text.z_index = 15
		get_parent().add_child(amp_text)
		var tt := amp_text.create_tween()
		tt.tween_property(amp_text, "position:y", amp_text.position.y - 20, 0.8)
		tt.parallel().tween_property(amp_text, "modulate:a", 0.0, 0.8)
		tt.tween_callback(amp_text.queue_free)

	# While amp up is active
	if _guitarist_amp_up_active:
		_guitarist_amp_up_timer -= delta

		# Golden aura pulse
		var pulse: float = 0.15 + sin(_guitarist_amp_up_timer * 4.0) * 0.1
		modulate = Color(1.2, 1.0 + pulse, 0.5 + pulse)

		# Golden particles
		if randi() % 5 == 0:
			var gp := ColorRect.new()
			gp.color = Color(1.0, 0.9, 0.3, 0.5)
			gp.size = Vector2(2, 2)
			gp.position = global_position + Vector2(randf_range(-12, 12), randf_range(-12, 12))
			gp.z_index = 7
			get_parent().add_child(gp)
			var gt := gp.create_tween()
			gt.tween_property(gp, "position:y", gp.position.y - randf_range(5, 12), 0.4)
			gt.parallel().tween_property(gp, "modulate:a", 0.0, 0.4)
			gt.tween_callback(gp.queue_free)

		# Boost nearby allies
		for p in get_tree().get_nodes_in_group("players"):
			if not (p is CharacterBody2D):
				continue
			if p == self:
				continue
			var dist: float = global_position.distance_to(p.global_position)
			if dist < GUITARIST_AMP_RADIUS:
				# Speed boost (temporary per-frame)
				if "velocity" in p:
					p.velocity *= 1.0 + 0.20 * delta * 60.0 * 0.016

		if _guitarist_amp_up_timer <= 0.0:
			_guitarist_amp_up_active = false
			_guitarist_amp_up_cooldown = GUITARIST_AMP_COOLDOWN
			modulate = Color.WHITE


func _charged_guitarist_power_chord(charge_ratio: float) -> void:
	# Charged power chord: bigger blast wave
	var mana_cost: int = int(lerpf(15.0, 40.0, charge_ratio))
	if not PlayerManager.use_mana(player_index, mana_cost):
		_spawn_fail_flash()
		return

	AudioManager.play("explosion", 6.0, 0.25)
	AudioManager.play("shield_charge", 4.0, 0.35)
	PlayerManager.add_skill_xp(player_index, "charge", 5)

	var aim: Vector2 = _get_aim_direction()
	var aim_angle: float = aim.angle()
	var arc_half: float = deg_to_rad(lerpf(30.0, 45.0, charge_ratio))
	var radius: float = lerpf(150.0, 200.0, charge_ratio)
	var push: float = lerpf(300.0, 500.0, charge_ratio)
	var dmg: int = int(lerpf(5.0, 12.0, charge_ratio))

	_screen_shake(lerpf(3.0, 8.0, charge_ratio), 0.25)
	_spawn_blast_wave_arc(aim_angle, arc_half, radius, 200.0, lerpf(0.5, 0.7, charge_ratio), dmg, push)


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


func _attack_werewolf() -> void:
	# Triple Claw Slash - 3 diagonal white slash lines
	var base_cooldown: float = 0.5
	if _werewolf_frenzy_active:
		base_cooldown *= 0.5
	_attack_cooldown = base_cooldown
	PlayerManager.add_skill_xp(player_index, "attack", 2)

	var aim: Vector2 = _get_aim_direction()
	var attack_bonus: float = PlayerManager.get_skill_bonus(player_index, "attack")
	if _werewolf_frenzy_active:
		attack_bonus *= 1.3
	var slash_damage: int = int(15 * attack_bonus)

	for slash_i in range(3):
		if not is_inside_tree():
			return
		if slash_i > 0:
			await get_tree().create_timer(0.05).timeout
			if not is_inside_tree():
				return
		AudioManager.play("sword_slash", 2.0, 1.3)
		_spawn_werewolf_slash(aim, slash_i, slash_damage)


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


func _special_werewolf_roar_push() -> void:
	# Roar Push - no mana cost, narrow 30-degree arc blast
	AudioManager.play("boss_roar", 3.0, 1.2)
	AudioManager.play("wind_gust", 2.0, 0.7)
	_special_cooldown = 2.0
	PlayerManager.add_skill_xp(player_index, "special", 7)

	var aim: Vector2 = _get_aim_direction()
	var aim_angle: float = aim.angle()
	var half_arc: float = deg_to_rad(15.0)  # 30-degree arc total
	var push_range: float = 250.0
	var push_force: float = 500.0
	var roar_damage: int = 10

	# Visual: narrow expanding cone
	var cone := ColorRect.new()
	cone.color = Color(0.9, 0.9, 0.9, 0.5)
	cone.size = Vector2(push_range, 30)
	cone.position = global_position
	cone.rotation = aim_angle - 0.06
	cone.pivot_offset = Vector2(0, 15)
	cone.z_index = 7
	get_parent().add_child(cone)

	var ct := cone.create_tween()
	ct.set_parallel(true)
	ct.tween_property(cone, "scale", Vector2(1.2, 2.0), 0.2)
	ct.tween_property(cone, "modulate:a", 0.0, 0.3)
	ct.chain().tween_callback(cone.queue_free)

	# Hit enemies in arc
	for body in get_tree().get_nodes_in_group("enemies"):
		if not body is Node2D:
			continue
		var to_enemy: Vector2 = body.global_position - global_position
		var dist: float = to_enemy.length()
		if dist > push_range:
			continue
		var angle_to: float = to_enemy.angle()
		var angle_diff: float = abs(wrapf(angle_to - aim_angle, -PI, PI))
		if angle_diff > half_arc:
			continue

		if body.has_method("take_damage"):
			body.take_damage(roar_damage, player_index)
		if body.has_method("apply_knockback"):
			var kb_dir: Vector2 = to_enemy.normalized()
			var weight: float = 1.0
			if body.has_method("get_weight"):
				weight = body.get_weight()
			body.apply_knockback(kb_dir * push_force / maxf(weight, 0.5))


func _charged_werewolf_pounce(charge_ratio: float) -> void:
	# Pounce - diagonal arc attack
	AudioManager.play("jump", 2.0, 0.5)
	PlayerManager.add_skill_xp(player_index, "charge", 5)

	var aim: Vector2 = _get_aim_direction()
	var h_dir: float = signf(aim.x) if abs(aim.x) > 0.1 else (1.0 if _facing_right else -1.0)

	# Launch in parabolic arc
	var launch_vy: float = lerpf(-400.0, -700.0, charge_ratio)
	var launch_vx: float = lerpf(300.0, 600.0, charge_ratio) * h_dir
	velocity.y = launch_vy
	velocity.x = launch_vx

	# Set pounce state for landing check
	_werewolf_pouncing = true
	_werewolf_pounce_damage = int(lerpf(30.0, 60.0, charge_ratio))
	_werewolf_pounce_radius = lerpf(40.0, 80.0, charge_ratio)

	# Visual: brief flash
	modulate = Color(0.8, 0.6, 0.3)
	_spawn_vfx(Color(0.6, 0.4, 0.2, 0.5), Vector2(20, 20))


func _check_werewolf_pounce_landing() -> void:
	if not _werewolf_pouncing:
		return
	if not is_on_floor():
		return

	_werewolf_pouncing = false
	modulate = Color.WHITE
	sprite.scale.y = 1.0
	AudioManager.play("explosion", 0.0, 0.8)
	_screen_shake(lerpf(3.0, 8.0, _werewolf_pounce_radius / 80.0), 0.25)

	# AoE slam damage
	_spawn_vfx(Color(0.6, 0.4, 0.2, 0.7), Vector2(_werewolf_pounce_radius * 2.0, 16))

	var slam_bonus: float = PlayerManager.get_skill_bonus(player_index, "charge")
	if _werewolf_frenzy_active:
		slam_bonus *= 1.3
	for body in get_tree().get_nodes_in_group("enemies"):
		if not body is Node2D:
			continue
		var dist: float = global_position.distance_to(body.global_position)
		if dist < _werewolf_pounce_radius:
			if body.has_method("take_damage"):
				body.take_damage(int(_werewolf_pounce_damage * slam_bonus), player_index)
				_spawn_werewolf_blood(body.global_position)
			if body.has_method("apply_knockback"):
				var kb: Vector2 = (body.global_position - global_position).normalized() * 250.0
				body.apply_knockback(kb)


func _handle_werewolf_frenzy(delta: float) -> void:
	if character_class != PlayerManager.CharacterClass.WEREWOLF:
		return
	if _werewolf_frenzy_cooldown > 0.0:
		_werewolf_frenzy_cooldown -= delta

	# Toggle frenzy on Circle press
	if _is_device_action_just_pressed("interact"):
		if _werewolf_frenzy_active:
			return  # Can't cancel early
		if _werewolf_frenzy_cooldown > 0.0:
			_spawn_fail_flash()
			return
		# FRENZY!
		_werewolf_frenzy_active = true
		_werewolf_frenzy_timer = WEREWOLF_FRENZY_DURATION
		AudioManager.play("enrage_roar", 2.0, 1.3)
		modulate = Color(0.7, 0.3, 0.2)
		# Burst VFX
		_spawn_vfx(Color(0.8, 0.15, 0.1, 0.7), Vector2(40, 40))
		# "FRENZY!" text
		var frenzy_text := Label.new()
		frenzy_text.text = "FRENZY!"
		frenzy_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		frenzy_text.add_theme_font_size_override("font_size", 14)
		frenzy_text.modulate = Color(1.0, 0.2, 0.1)
		frenzy_text.position = global_position + Vector2(-25, -40)
		frenzy_text.z_index = 15
		get_parent().add_child(frenzy_text)
		var tt := frenzy_text.create_tween()
		tt.tween_property(frenzy_text, "position:y", frenzy_text.position.y - 20, 0.8)
		tt.parallel().tween_property(frenzy_text, "modulate:a", 0.0, 0.8)
		tt.tween_callback(frenzy_text.queue_free)

	# While frenzy active
	if _werewolf_frenzy_active:
		_werewolf_frenzy_timer -= delta

		# Reddish-brown pulsing glow (eyes glow red, fur bristles)
		var pulse: float = 0.15 + sin(_werewolf_frenzy_timer * 6.0) * 0.1
		modulate = Color(0.7 + pulse, 0.3, 0.2)

		# Red particles while frenzied
		if randi() % 4 == 0:
			var rp := ColorRect.new()
			rp.color = Color(1.0, 0.1, 0.0, 0.6)
			rp.size = Vector2(3, 3)
			rp.position = global_position + Vector2(randf_range(-10, 10), randf_range(-8, 8))
			rp.z_index = 5
			get_parent().add_child(rp)
			var rt := rp.create_tween()
			rt.tween_property(rp, "position:y", rp.position.y - randf_range(10, 20), 0.3)
			rt.parallel().tween_property(rp, "modulate:a", 0.0, 0.3)
			rt.tween_callback(rp.queue_free)

		# Warning flicker when almost done
		if _werewolf_frenzy_timer <= 2.0:
			if fmod(_werewolf_frenzy_timer, 0.2) < 0.1:
				modulate = Color.WHITE

		# Frenzy ends
		if _werewolf_frenzy_timer <= 0.0:
			_werewolf_frenzy_active = false
			_werewolf_frenzy_cooldown = WEREWOLF_FRENZY_COOLDOWN
			modulate = Color.WHITE
			AudioManager.play("player_hurt", -4.0, 0.8)
