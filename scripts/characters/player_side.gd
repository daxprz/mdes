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
var _donut_buddy_count: int = 0
var _shadow_dash_active: bool = false
var _is_dead: bool = false

# Melee combo system
var _combo_count: int = 0
var _combo_timer: float = 0.0
const COMBO_WINDOW := 0.6  # Seconds to chain next hit
const COMBO_DAMAGES := [30, 40, 55]
const COMBO_RANGES := [20.0, 22.0, 28.0]  # Final hit has wider reach

# Melee ground slam
var _ground_slam_active: bool = false
var _ground_slam_damage := 45
var _revive_progress: float = 0.0
const REVIVE_TIME := 3.0
const REVIVE_RANGE := 60.0

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

	for action in ["move_left", "move_right", "jump", "attack", "special"]:
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

	_update_cooldowns(delta)
	_update_combo_timer(delta)
	_handle_movement()
	_handle_jump()
	_handle_wall_slide(delta)
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
	var h_input := 0.0
	if _is_device_action_pressed("move_left"):
		h_input -= 1.0
	if _is_device_action_pressed("move_right"):
		h_input += 1.0

	var speed: float = PlayerManager.get_player(player_index).get("speed", 100)
	velocity.x = h_input * speed

	if h_input != 0.0:
		_facing_right = h_input > 0.0
		sprite.flip_h = not _facing_right


func _handle_jump() -> void:
	if not _is_device_action_just_pressed("jump"):
		return

	if is_on_floor():
		velocity.y = JUMP_VELOCITY
		AudioManager.play("jump", -5.0)
	elif _is_wall_sliding:
		_wall_jump()
		AudioManager.play("jump", -5.0, 1.2)


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

func _handle_attack(delta: float) -> void:
	if _attack_cooldown > 0.0:
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


func _attack_melee() -> void:
	# Ground slam if airborne
	if not is_on_floor():
		_start_ground_slam()
		return

	# Combo: advance if within window, reset if expired
	if _combo_timer <= 0.0:
		_combo_count = 0
	var combo_idx := mini(_combo_count, COMBO_DAMAGES.size() - 1)
	var damage: int = COMBO_DAMAGES[combo_idx]
	var reach: float = COMBO_RANGES[combo_idx]

	# Final combo hit plays a heavier sound
	if combo_idx == COMBO_DAMAGES.size() - 1:
		AudioManager.play("sword_slash", 2.0, 0.75)
		_spawn_vfx(Color(1.0, 0.8, 0.2, 0.6), Vector2(reach * 2, 24))
	else:
		AudioManager.play("sword_slash")

	var offset := Vector2(reach if _facing_right else -reach, 0.0)
	attack_area.position = offset
	attack_area.monitoring = true
	for body in attack_area.get_overlapping_bodies():
		if body.has_method("take_damage"):
			body.take_damage(damage, player_index)
		# Final hit knocks back
		if combo_idx == COMBO_DAMAGES.size() - 1 and body.has_method("apply_knockback"):
			var kb_dir := Vector2(1.0 if _facing_right else -1.0, -0.3).normalized()
			body.apply_knockback(kb_dir * 200.0)
	await get_tree().create_timer(0.15).timeout
	if is_inside_tree():
		attack_area.monitoring = false

	_combo_count += 1
	_combo_timer = COMBO_WINDOW
	# Reset combo after full chain
	if _combo_count >= COMBO_DAMAGES.size():
		_combo_count = 0


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
	AudioManager.play("dagger_stab")
	var offset := Vector2(18.0 if _facing_right else -18.0, 0.0)
	attack_area.position = offset
	attack_area.monitoring = true
	for body in attack_area.get_overlapping_bodies():
		if body.has_method("take_damage"):
			body.take_damage(22, player_index)
	await get_tree().create_timer(0.1).timeout
	if is_inside_tree():
		attack_area.monitoring = false


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
	# Big AoE shockwave VFX
	_spawn_vfx(Color(1.0, 0.5, 0.1, 0.7), Vector2(80, 16))

	# Damage all nearby enemies on the ground
	for body in get_tree().get_nodes_in_group("enemies"):
		if not body is Node2D:
			continue
		var dist: float = global_position.distance_to(body.global_position)
		if dist < 80.0 and body.has_method("take_damage"):
			body.take_damage(_ground_slam_damage, player_index)
			if body.has_method("apply_knockback"):
				var kb := (body.global_position - global_position).normalized()
				body.apply_knockback(kb * 250.0)


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


func _special_shield_charge() -> void:
	AudioManager.play("shield_charge", 2.0, 0.9)
	var dash_speed := 600.0
	velocity.x = dash_speed if _facing_right else -dash_speed
	velocity.y = -120.0  # Slight lift

	# Invincible during charge
	collision_layer = 0
	modulate = Color(0.4, 0.7, 1.0)  # Bright blue
	_spawn_vfx(Color(0.3, 0.6, 1.0, 0.8), Vector2(48, 24))

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
				var kb_dir := Vector2(1.0 if _facing_right else -1.0, -0.4).normalized()
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


func take_damage(amount: int, _source_index: int = -1) -> void:
	if _shadow_dash_active or _is_dead:
		return
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
	var result := space.intersect_ray(query)

	var target_pos: Vector2
	if result:
		# Stop short of the wall
		target_pos = result["position"] - direction * 12.0
	else:
		target_pos = global_position + direction * dash_distance

	AudioManager.play("shadow_dash")
	_spawn_vfx(Color(0.8, 0.2, 0.2, 0.5), Vector2(14, 28))
	global_position = target_pos
	# Arrive flash
	_spawn_vfx(Color(0.8, 0.2, 0.2, 0.5), Vector2(14, 28))
	modulate = Color(1.0, 1.0, 1.0, 0.4)
	collision_layer = 0
	_shadow_dash_active = true
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


func _spawn_fail_flash() -> void:
	# Red X flash to show ability can't be used
	modulate = Color(1.0, 0.3, 0.3)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.15)
