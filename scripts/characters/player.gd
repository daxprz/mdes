extends CharacterBody2D

## Overworld player character (top-down Zelda-style movement).
## Assigned a player_index, device_id, and character_class at spawn.

const CLASS_SPRITES := {
	PlayerManager.CharacterClass.MELEE: "res://assets/sprites/characters/melee_topdown.png",
	PlayerManager.CharacterClass.RANGED: "res://assets/sprites/characters/ranged_topdown.png",
	PlayerManager.CharacterClass.MAGE: "res://assets/sprites/characters/mage_topdown.png",
	PlayerManager.CharacterClass.SUMMONER: "res://assets/sprites/characters/summoner_topdown.png",
	PlayerManager.CharacterClass.ROGUE: "res://assets/sprites/characters/rogue_topdown.png",
	PlayerManager.CharacterClass.DEMOLITIONIST: "res://assets/sprites/characters/demolitionist_topdown.png",
	PlayerManager.CharacterClass.HEALER: "res://assets/sprites/characters/healer_topdown.png",
	PlayerManager.CharacterClass.TANK: "res://assets/sprites/characters/tank_topdown.png",
	PlayerManager.CharacterClass.JUMPER: "res://assets/sprites/characters/jumper_topdown.png",
}

# Direction rows in the spritesheet: down=0, left=1, right=2, up=3
enum Dir { DOWN, LEFT, RIGHT, UP }

@export var player_index: int = 0
@export var device_id: int = -1  # -1 = keyboard
@export var character_class: PlayerManager.CharacterClass = PlayerManager.CharacterClass.MELEE

var _direction: Dir = Dir.DOWN
var _anim_frame: int = 0
var _anim_timer: float = 0.0
var _is_moving: bool = false
var _attack_cooldown: float = 0.0
var _special_cooldown: float = 0.0
var _interactable: Node = null  # nearest interactable in range

# Melee combo
var _melee_combo: int = 0
var _melee_combo_timer: float = 0.0
const MELEE_COMBO_WINDOW := 0.6
const MELEE_COMBO_DMG := [25, 35, 50]
const MELEE_COMBO_RANGE := [20.0, 22.0, 28.0]

const ANIM_FPS := 8.0
const ATTACK_COOLDOWN_TIME := 0.4
const SPECIAL_COOLDOWN_TIME := 1.0

# -- Melee Enrage (Circle) --
var _melee_enraged: bool = false
var _melee_enrage_timer: float = 0.0
var _melee_enrage_cooldown: float = 0.0
const MELEE_ENRAGE_DURATION := 10.0
const MELEE_ENRAGE_COOLDOWN := 45.0
const MELEE_ENRAGE_SPEED_MULT := 1.5
const MELEE_ENRAGE_DAMAGE_MULT := 1.8

# -- Ranger Ammo + Reload (Circle) --
var _ranger_arrows: int = 10
var _ranger_reloading: bool = false
var _ranger_reload_timer: float = 0.0
const RANGER_MAX_ARROWS := 10
const RANGER_RELOAD_TIME := 1.5

# -- Rogue Stealth (Circle) --
var _rogue_stealth: bool = false
var _rogue_stealth_timer: float = 0.0
var _rogue_stealth_cooldown: float = 0.0
const ROGUE_STEALTH_DURATION := 5.0
const ROGUE_STEALTH_COOLDOWN := 20.0
const ROGUE_STEALTH_DAMAGE_MULT := 3.75

# -- Summoner Delegate (Circle) --
var _summoner_delegate_target: Vector2 = Vector2.ZERO
var _summoner_delegate_active: bool = false

# -- Demolitionist Refuel (Circle) --
var _rocket_fuel: float = 4.0
const ROCKET_FUEL_MAX := 4.0

# -- Healer Wind Gust (Circle) --
var _healer_gust_cooldown: float = 0.0
const HEALER_GUST_COOLDOWN := 8.0
const HEALER_GUST_RADIUS := 100.0
const HEALER_GUST_FORCE := 400.0

const HEALTH_BAR_SCENE := preload("res://scenes/ui/health_bar.tscn")

@onready var sprite: Sprite2D = $Sprite
@onready var collision_shape: CollisionShape2D = $CollisionShape
@onready var player_label: Label = $PlayerLabel
@onready var interact_area: Area2D = $InteractArea
@onready var attack_area: Area2D = $AttackArea

var _health_bar: Node2D = null


func _ready() -> void:
	add_to_group("players")
	_apply_class_sprite()
	player_label.text = "P" + str(player_index + 1)
	interact_area.body_entered.connect(_on_interact_body_entered)
	interact_area.body_exited.connect(_on_interact_body_exited)
	_health_bar = HEALTH_BAR_SCENE.instantiate()
	_health_bar.bar_width = 28.0
	_health_bar.bar_offset = Vector2(0, -22)
	_health_bar.hide_when_full = true
	add_child(_health_bar)


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
	sprite.hframes = 4
	sprite.vframes = 4
	sprite.frame = 0


# -- Input helpers -------------------------------------------------------------

func _is_device_action_pressed(action: String) -> bool:
	if device_id == -1:
		# Keyboard player: use standard check (all keyboard events are device -1)
		return Input.is_action_pressed(action)
	# Controller: check via polling with device filter
	# Godot 4 Input.is_action_pressed does not filter by device,
	# so we track state from _input instead.
	return _controller_actions.get(action, false)


func _is_device_action_just_pressed(action: String) -> bool:
	if device_id == -1:
		return Input.is_action_just_pressed(action)
	return _controller_just_pressed.get(action, false)


# Controller-specific state tracking
var _controller_actions: Dictionary = {}
var _controller_just_pressed: Dictionary = {}


func _input(event: InputEvent) -> void:
	# Only process events from our device
	if device_id == -1:
		return  # Keyboard handled via Input singleton
	if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	if event.device != device_id:
		return

	for action in ["move_up", "move_down", "move_left", "move_right", "attack", "special", "interact", "block"]:
		if event.is_action_pressed(action):
			_controller_actions[action] = true
			_controller_just_pressed[action] = true
		elif event.is_action_released(action):
			_controller_actions[action] = false


func _physics_process(delta: float) -> void:
	_update_cooldowns(delta)
	_handle_circle_abilities(delta)
	if _melee_combo_timer > 0.0:
		_melee_combo_timer -= delta
		if _melee_combo_timer <= 0.0:
			_melee_combo = 0
	_handle_movement(delta)
	_handle_attack()
	_handle_special()
	_handle_interact()
	_update_animation(delta)
	move_and_slide()

	# Clear AFTER all checks so button presses are actually read
	_controller_just_pressed.clear()


func _update_cooldowns(delta: float) -> void:
	if _attack_cooldown > 0.0:
		_attack_cooldown -= delta
	if _special_cooldown > 0.0:
		_special_cooldown -= delta


# -- Movement ------------------------------------------------------------------

func _handle_movement(_delta: float) -> void:
	var input_vec := Vector2.ZERO
	if _is_device_action_pressed("move_up"):
		input_vec.y -= 1.0
	if _is_device_action_pressed("move_down"):
		input_vec.y += 1.0
	if _is_device_action_pressed("move_left"):
		input_vec.x -= 1.0
	if _is_device_action_pressed("move_right"):
		input_vec.x += 1.0

	input_vec = input_vec.normalized()
	_is_moving = input_vec.length() > 0.1

	var speed: float = PlayerManager.get_player(player_index).get("speed", 100)
	if _melee_enraged:
		speed *= MELEE_ENRAGE_SPEED_MULT
	velocity = input_vec * speed

	if _is_moving:
		_update_direction(input_vec)


func _update_direction(input_vec: Vector2) -> void:
	if abs(input_vec.x) > abs(input_vec.y):
		_direction = Dir.RIGHT if input_vec.x > 0 else Dir.LEFT
	else:
		_direction = Dir.DOWN if input_vec.y > 0 else Dir.UP


# -- Animation -----------------------------------------------------------------

func _update_animation(delta: float) -> void:
	if _is_moving:
		_anim_timer += delta
		if _anim_timer >= 1.0 / ANIM_FPS:
			_anim_timer -= 1.0 / ANIM_FPS
			_anim_frame = (_anim_frame + 1) % 4
	else:
		_anim_frame = 0
		_anim_timer = 0.0

	# Frame = column + row * hframes
	sprite.frame = _anim_frame + int(_direction) * 4


# -- Attack --------------------------------------------------------------------

func _handle_attack() -> void:
	if _attack_cooldown > 0.0:
		return
	if not _is_device_action_just_pressed("attack"):
		return

	_attack_cooldown = ATTACK_COOLDOWN_TIME
	_perform_attack()


func _perform_attack() -> void:
	# Melee gets combo system
	if character_class == PlayerManager.CharacterClass.MELEE:
		_perform_melee_combo()
		return

	# Demolitionist throws a bomb
	if character_class == PlayerManager.CharacterClass.DEMOLITIONIST:
		_attack_demolitionist()
		return

	# Healer swings staff + heals ally
	if character_class == PlayerManager.CharacterClass.HEALER:
		_attack_healer()
		return

	# Ranger fires crossbow (uses ammo)
	if character_class == PlayerManager.CharacterClass.RANGED:
		_attack_ranged()
		return

	# Rogue throws knives or backstab from stealth
	if character_class == PlayerManager.CharacterClass.ROGUE:
		_attack_rogue()
		return

	# Position the attack area based on facing direction
	var offset := Vector2.ZERO
	match _direction:
		Dir.UP: offset = Vector2(0, -20)
		Dir.DOWN: offset = Vector2(0, 20)
		Dir.LEFT: offset = Vector2(-20, 0)
		Dir.RIGHT: offset = Vector2(20, 0)
	attack_area.position = offset

	# Enable the attack area briefly
	attack_area.monitoring = true
	var damage := _get_attack_damage()

	# Deal damage to overlapping enemies
	for body in attack_area.get_overlapping_bodies():
		if body.has_method("take_damage"):
			body.take_damage(damage, player_index)

	# Disable after a short delay
	await get_tree().create_timer(0.15).timeout
	if is_inside_tree():
		attack_area.monitoring = false


func _perform_melee_combo() -> void:
	if _melee_combo_timer <= 0.0:
		_melee_combo = 0
	var idx: int = mini(_melee_combo, MELEE_COMBO_DMG.size() - 1)
	var damage: int = MELEE_COMBO_DMG[idx]
	if _melee_enraged:
		damage = int(damage * MELEE_ENRAGE_DAMAGE_MULT)
	var reach: float = MELEE_COMBO_RANGE[idx]

	AudioManager.play("sword_slash", 0.0 if idx < 2 else 2.0, 1.0 if idx < 2 else 0.75)

	var offset := _facing_vector() * reach
	attack_area.position = offset
	attack_area.monitoring = true

	for body in attack_area.get_overlapping_bodies():
		if body.has_method("take_damage"):
			body.take_damage(damage, player_index)
		if idx == MELEE_COMBO_DMG.size() - 1 and body.has_method("apply_knockback"):
			body.apply_knockback(_facing_vector() * 200.0)

	await get_tree().create_timer(0.15).timeout
	if is_inside_tree():
		attack_area.monitoring = false

	_melee_combo += 1
	_melee_combo_timer = MELEE_COMBO_WINDOW
	if _melee_combo >= MELEE_COMBO_DMG.size():
		_melee_combo = 0


func _get_attack_damage() -> int:
	match character_class:
		PlayerManager.CharacterClass.MELEE: return 25
		PlayerManager.CharacterClass.RANGED: return 15
		PlayerManager.CharacterClass.MAGE: return 20
		PlayerManager.CharacterClass.SUMMONER: return 10
		PlayerManager.CharacterClass.ROGUE: return 18
		PlayerManager.CharacterClass.DEMOLITIONIST: return 25
		PlayerManager.CharacterClass.HEALER: return 10
		PlayerManager.CharacterClass.TANK: return 45
		PlayerManager.CharacterClass.JUMPER: return 15
	return 10


# -- Special Ability -----------------------------------------------------------

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
			_special_melee()
		PlayerManager.CharacterClass.RANGED:
			_special_ranger_grapple()
		PlayerManager.CharacterClass.MAGE:
			_special_mage()
		PlayerManager.CharacterClass.SUMMONER:
			_special_summoner()
		PlayerManager.CharacterClass.ROGUE:
			_special_rogue()
		PlayerManager.CharacterClass.DEMOLITIONIST:
			_special_demolitionist()
		PlayerManager.CharacterClass.HEALER:
			_special_healer()
		PlayerManager.CharacterClass.TANK:
			_special_tank_slam()
		PlayerManager.CharacterClass.JUMPER:
			_special_jumper_dash_attack()


func _special_melee() -> void:
	# Shield charge: dash forward with knockback + invincibility
	var dash_dir := _facing_vector() * 250.0
	velocity = dash_dir
	modulate = Color(0.4, 0.7, 1.0)
	move_and_slide()
	var hit_bodies: Array = []
	for body in attack_area.get_overlapping_bodies():
		if body in hit_bodies:
			continue
		if body.has_method("take_damage"):
			body.take_damage(40, player_index)
			hit_bodies.append(body)
		if body.has_method("apply_knockback"):
			body.apply_knockback(_facing_vector() * 350.0)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.25)


func _special_mage() -> void:
	# Frosting freeze: slow nearby enemies
	if not PlayerManager.use_mana(player_index, 30):
		_special_cooldown = 0.0
		return
	for body in attack_area.get_overlapping_bodies():
		if body.has_method("apply_slow"):
			body.apply_slow(3.0)


func _special_summoner() -> void:
	# Summon donut buddy (placeholder - spawn scene)
	if not PlayerManager.use_mana(player_index, 25):
		_special_cooldown = 0.0
		return
	var buddy_scene := load("res://scenes/characters/donut_buddy.tscn") as PackedScene
	if buddy_scene:
		var buddy := buddy_scene.instantiate()
		buddy.owner_index = player_index
		buddy.global_position = global_position + _facing_vector() * 24.0
		get_parent().add_child(buddy)


func _special_rogue() -> void:
	# Shadow dash: teleport short distance
	var dash_offset := _facing_vector() * 80.0
	global_position += dash_offset


# -- Demolitionist (overworld) -------------------------------------------------

func _attack_demolitionist() -> void:
	AudioManager.play("explosion", -6.0, 1.3)
	var facing := _facing_vector()
	var bomb := ColorRect.new()
	bomb.color = Color(0.9, 0.6, 0.1)
	bomb.size = Vector2(8, 8)
	bomb.z_index = 5
	get_parent().add_child(bomb)
	bomb.global_position = global_position + facing * 12.0

	var bomb_vel: Vector2 = facing * 180.0
	var bomb_time := 0.0
	var bomb_max_time := 1.5

	while bomb_time < bomb_max_time and is_instance_valid(bomb) and is_inside_tree():
		var dt: float = get_process_delta_time()
		bomb_time += dt
		bomb.global_position += bomb_vel * dt
		bomb_vel *= 0.98

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

	if is_instance_valid(bomb) and is_inside_tree():
		var explode_pos: Vector2 = bomb.global_position
		bomb.queue_free()
		_demolitionist_explode_topdown(explode_pos, 25, 60.0)


func _demolitionist_explode_topdown(pos: Vector2, damage: int, radius: float) -> void:
	AudioManager.play("explosion")
	var vfx := ColorRect.new()
	vfx.color = Color(0.9, 0.6, 0.1, 0.8)
	vfx.size = Vector2(radius * 2, radius * 2)
	vfx.position = pos - Vector2(radius, radius)
	get_parent().add_child(vfx)
	var tween := vfx.create_tween()
	tween.set_parallel(true)
	tween.tween_property(vfx, "scale", Vector2(1.5, 1.5), 0.3)
	tween.tween_property(vfx, "modulate:a", 0.0, 0.3)
	tween.chain().tween_callback(vfx.queue_free)

	for body in get_tree().get_nodes_in_group("enemies"):
		if not body is Node2D:
			continue
		var dist: float = pos.distance_to(body.global_position)
		if dist < radius and body.has_method("take_damage"):
			body.take_damage(damage, player_index)
			if body.has_method("apply_knockback"):
				var kb: Vector2 = (body.global_position - pos).normalized()
				body.apply_knockback(kb * 200.0)


func _special_demolitionist() -> void:
	if not PlayerManager.use_mana(player_index, 40):
		_special_cooldown = 0.0
		return
	AudioManager.play("explosion", -3.0, 0.8)
	var facing := _facing_vector()
	var bomb := ColorRect.new()
	bomb.color = Color(1.0, 0.4, 0.0)
	bomb.size = Vector2(12, 12)
	bomb.z_index = 5
	get_parent().add_child(bomb)
	bomb.global_position = global_position + facing * 12.0

	var bomb_vel: Vector2 = facing * 160.0
	var bomb_time := 0.0
	var bomb_max_time := 1.5

	while bomb_time < bomb_max_time and is_instance_valid(bomb) and is_inside_tree():
		var dt: float = get_process_delta_time()
		bomb_time += dt
		bomb.global_position += bomb_vel * dt
		bomb_vel *= 0.97

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

	if is_instance_valid(bomb) and is_inside_tree():
		var explode_pos: Vector2 = bomb.global_position
		bomb.queue_free()
		_demolitionist_explode_topdown(explode_pos, 50, 90.0)


# -- Healer (overworld) -------------------------------------------------------

func _attack_healer() -> void:
	AudioManager.play("staff_bonk")
	var offset := _facing_vector() * 16.0
	attack_area.position = offset
	attack_area.monitoring = true
	for body in attack_area.get_overlapping_bodies():
		if body.has_method("take_damage"):
			body.take_damage(10, player_index)
	await get_tree().create_timer(0.15).timeout
	if is_inside_tree():
		attack_area.monitoring = false

	# Heal nearest injured ally within 120px
	var nearest_ally: Node2D = null
	var nearest_dist: float = 120.0
	for p in get_tree().get_nodes_in_group("players"):
		if p == self or not (p is CharacterBody2D):
			continue
		var p_idx: int = p.get("player_index")
		var p_data: Dictionary = PlayerManager.get_player(p_idx)
		if p_data.is_empty():
			continue
		if p_data["health"] >= p_data["max_health"]:
			continue
		var dist: float = global_position.distance_to(p.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_ally = p

	if nearest_ally != null:
		var ally_idx: int = nearest_ally.get("player_index")
		PlayerManager.heal_player(ally_idx, 8)
		var line_vfx := ColorRect.new()
		line_vfx.color = Color(0.3, 0.9, 0.4, 0.7)
		var dir_to_ally: Vector2 = nearest_ally.global_position - global_position
		var line_len: float = dir_to_ally.length()
		line_vfx.size = Vector2(line_len, 3)
		line_vfx.position = global_position
		line_vfx.rotation = dir_to_ally.angle()
		get_parent().add_child(line_vfx)
		var heal_tween := line_vfx.create_tween()
		heal_tween.tween_property(line_vfx, "modulate:a", 0.0, 0.4)
		heal_tween.tween_callback(line_vfx.queue_free)


func _special_healer() -> void:
	if not PlayerManager.use_mana(player_index, 50):
		_special_cooldown = 0.0
		return
	AudioManager.play("player_revive")
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

	for p in get_tree().get_nodes_in_group("players"):
		if not (p is CharacterBody2D):
			continue
		var dist: float = global_position.distance_to(p.global_position)
		if dist < 80.0:
			var p_idx: int = p.get("player_index")
			PlayerManager.heal_player(p_idx, 30)


func take_damage(amount: int, _source_index: int = -1) -> void:
	if _rogue_stealth:
		amount = int(amount * 0.5)
	if _tank_fortify:
		amount = int(amount * 0.4)
	PlayerManager.damage_player(player_index, amount)
	if _health_bar:
		var p := PlayerManager.get_player(player_index)
		_health_bar.set_health(p["health"], p["max_health"])
	modulate = Color.RED
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.2)


func _facing_vector() -> Vector2:
	match _direction:
		Dir.UP: return Vector2(0, -1)
		Dir.DOWN: return Vector2(0, 1)
		Dir.LEFT: return Vector2(-1, 0)
		Dir.RIGHT: return Vector2(1, 0)
	return Vector2(0, 1)


# -- Interaction ---------------------------------------------------------------

func _handle_interact() -> void:
	if not _is_device_action_just_pressed("interact"):
		return
	if _interactable and _interactable.has_method("interact"):
		_interactable.interact(player_index)


func _on_interact_body_entered(body: Node2D) -> void:
	if body.has_method("interact"):
		_interactable = body


func _on_interact_body_exited(body: Node2D) -> void:
	if body == _interactable:
		_interactable = null


# -- Aim Direction (top-down) --------------------------------------------------

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
		return _facing_vector()
	var result: Vector2 = aim.normalized()
	return result


# -- VFX Helpers ---------------------------------------------------------------

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
	modulate = Color(1.0, 0.3, 0.3)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.15)


func _spawn_blood_particles(hit_pos: Vector2) -> void:
	for i in range(3):
		var angle: float = randf_range(-2.2, -0.9)
		var spd: float = randf_range(120.0, 220.0)
		var vel: Vector2 = Vector2(cos(angle), sin(angle)) * spd
		vel.x += randf_range(-40.0, 40.0)
		var blood := ColorRect.new()
		blood.color = Color(0.8, 0.05, 0.05, 0.9)
		blood.size = Vector2(4, 4)
		blood.position = hit_pos
		blood.z_index = 9
		get_parent().add_child(blood)
		var bt := blood.create_tween()
		bt.tween_property(blood, "position", blood.position + vel.normalized() * 15.0, 0.25)
		bt.parallel().tween_property(blood, "modulate:a", 0.0, 0.25)
		bt.tween_callback(blood.queue_free)


# -- Circle Ability Router -----------------------------------------------------

func _handle_circle_abilities(delta: float) -> void:
	match character_class:
		PlayerManager.CharacterClass.MELEE:
			_handle_melee_enrage(delta)
		PlayerManager.CharacterClass.RANGED:
			_handle_ranger_reload(delta)
		PlayerManager.CharacterClass.ROGUE:
			_handle_rogue_stealth_toggle()
			_handle_rogue_stealth(delta)
		PlayerManager.CharacterClass.SUMMONER:
			_handle_summoner_delegate()
		PlayerManager.CharacterClass.DEMOLITIONIST:
			_handle_demo_refuel()
		PlayerManager.CharacterClass.HEALER:
			_handle_healer_wind_gust()
		PlayerManager.CharacterClass.TANK:
			_handle_tank_fortify(delta)
		PlayerManager.CharacterClass.JUMPER:
			_handle_jumper_dash()


# -- Melee Enrage (Circle) ----------------------------------------------------

func _handle_melee_enrage(delta: float) -> void:
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


# -- Ranger Attack (crossbow) -------------------------------------------------

func _attack_ranged() -> void:
	if _ranger_arrows <= 0:
		_spawn_fail_flash()
		AudioManager.play("reload_click", -4.0)
		return
	_ranger_arrows -= 1
	AudioManager.play("crossbow_shoot", 0.0, 0.8)
	_attack_cooldown = 0.6
	var scaled_dmg: int = int(60 * PlayerManager.get_skill_bonus(player_index, "attack"))
	var aim: Vector2 = _get_aim_direction()

	var bolt_scene := load("res://scenes/characters/projectile.tscn") as PackedScene
	if bolt_scene:
		var bolt := bolt_scene.instantiate()
		bolt.damage = scaled_dmg
		bolt.speed = 400.0
		bolt.direction = aim
		bolt.projectile_type = "crossbow_bolt"
		bolt.owner_index = player_index
		bolt.global_position = global_position + aim * 12.0
		get_parent().add_child(bolt)


# -- Ranger Reload (Circle held) ----------------------------------------------

func _handle_ranger_reload(delta: float) -> void:
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

		# Arrow count VFX
		var arrow_text := Label.new()
		arrow_text.text = "%d/%d" % [_ranger_arrows, RANGER_MAX_ARROWS]
		arrow_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		arrow_text.add_theme_font_size_override("font_size", 8)
		arrow_text.modulate = Color(0.3, 0.8, 0.3)
		arrow_text.position = global_position + Vector2(-12, -35)
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


# -- Ranger Grappling Hook (Triangle / special) --------------------------------

func _special_ranger_grapple() -> void:
	var aim: Vector2 = _get_aim_direction()
	var hook_range: float = 250.0
	AudioManager.play("grapple_launch")

	# Raycast to find what the hook hits
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		global_position,
		global_position + aim * hook_range,
		1 | 8  # Mask: world (1) + enemies (8)
	)
	query.exclude = [get_rid()]
	var result: Dictionary = space.intersect_ray(query)

	var hook_target: Vector2
	var hit_enemy: Node2D = null

	if result:
		hook_target = result["position"]
		var collider: Node = result["collider"]
		if collider.is_in_group("enemies"):
			hit_enemy = collider as Node2D
	else:
		hook_target = global_position + aim * hook_range

	# Visual: draw the hook line
	var hook_line := ColorRect.new()
	hook_line.color = Color(0.5, 0.4, 0.3, 0.8)
	var line_vec: Vector2 = hook_target - global_position
	var line_len: float = line_vec.length()
	hook_line.size = Vector2(line_len, 2)
	hook_line.position = global_position
	hook_line.rotation = line_vec.angle()
	hook_line.z_index = 6
	get_parent().add_child(hook_line)

	var hook_head := ColorRect.new()
	hook_head.color = Color(0.6, 0.5, 0.35)
	hook_head.size = Vector2(6, 6)
	hook_head.position = hook_target - Vector2(3, 3)
	hook_head.z_index = 7
	get_parent().add_child(hook_head)

	if not result:
		var miss_tween := hook_line.create_tween()
		miss_tween.tween_property(hook_line, "modulate:a", 0.0, 0.2)
		miss_tween.tween_callback(hook_line.queue_free)
		var miss_head := hook_head.create_tween()
		miss_head.tween_property(hook_head, "modulate:a", 0.0, 0.2)
		miss_head.tween_callback(hook_head.queue_free)
		return

	# Pull player to the hook point
	AudioManager.play("grapple_hit")
	set_physics_process(false)
	collision_layer = 0

	var pull_target: Vector2
	if hit_enemy:
		pull_target = hit_enemy.global_position + (-aim * 16.0)
	else:
		pull_target = hook_target + (-aim * 8.0)

	var pull_speed: float = 600.0
	var pull_time: float = clampf(line_len / pull_speed, 0.08, 0.4)
	var pull_tween := create_tween()
	pull_tween.tween_property(self, "global_position", pull_target, pull_time).set_ease(Tween.EASE_IN)
	await pull_tween.finished

	if is_instance_valid(hook_line):
		hook_line.queue_free()
	if is_instance_valid(hook_head):
		hook_head.queue_free()

	if is_inside_tree():
		set_physics_process(true)
		collision_layer = 2
		velocity = aim * 100.0

		if hit_enemy and is_instance_valid(hit_enemy):
			if hit_enemy.has_method("take_damage"):
				var hook_dmg: int = int(20 * PlayerManager.get_skill_bonus(player_index, "attack"))
				hit_enemy.take_damage(hook_dmg, player_index)


# -- Rogue Attack (knives / backstab) -----------------------------------------

func _attack_rogue() -> void:
	AudioManager.play("dagger_stab")
	_attack_cooldown = 0.5
	var base_dir: Vector2 = _get_aim_direction()
	var angles := [-0.2, 0.0, 0.2]
	var base_dmg: int = int(12 * PlayerManager.get_skill_bonus(player_index, "attack"))

	# STEALTH: close-range backstab instead of throwing knives
	if _rogue_stealth:
		var backstab_dmg: int = int(base_dmg * ROGUE_STEALTH_DAMAGE_MULT)
		_exit_stealth()

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
				hit_something = true
		if hit_something:
			AudioManager.play("backstab_hit")
			_stealth_backstab_vfx(global_position + base_dir * 16.0)
		await get_tree().create_timer(0.1).timeout
		if is_inside_tree():
			attack_area.monitoring = false
		return

	# Normal: throw 3 knives in a fan spread
	var scaled_dmg: int = base_dmg
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


# -- Rogue Stealth (Circle) ---------------------------------------------------

func _handle_rogue_stealth_toggle() -> void:
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
	modulate = Color.WHITE
	AudioManager.play("stealth_activate", -4.0, 1.3)


func _stealth_backstab_vfx(hit_pos: Vector2) -> void:
	var label := Label.new()
	label.text = "BACK STAB!"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.modulate = Color(1.0, 0.6, 0.1)
	label.position = hit_pos + Vector2(-30, -20)
	label.z_index = 15
	get_parent().add_child(label)
	var tt := label.create_tween()
	tt.tween_property(label, "position:y", label.position.y - 25, 0.7)
	tt.parallel().tween_property(label, "modulate:a", 0.0, 0.7)
	tt.tween_callback(label.queue_free)


# -- Summoner Delegate (Circle) -----------------------------------------------

func _handle_summoner_delegate() -> void:
	if not _is_device_action_just_pressed("interact"):
		return

	# Toggle: send all donut buddies to the position the summoner is facing
	_summoner_delegate_target = global_position + _facing_vector() * 80.0
	_summoner_delegate_active = not _summoner_delegate_active

	if _summoner_delegate_active:
		AudioManager.play("summon", -3.0, 1.5)
		# Point all donut buddies toward the target
		for buddy in get_tree().get_nodes_in_group("donut_buddies"):
			if buddy.get("owner_index") == player_index:
				if "target_position" in buddy:
					buddy.target_position = _summoner_delegate_target
				elif buddy.has_method("set_target"):
					buddy.set_target(_summoner_delegate_target)
		# VFX: target indicator
		var marker := ColorRect.new()
		marker.color = Color(0.8, 0.5, 1.0, 0.5)
		marker.size = Vector2(12, 12)
		marker.position = _summoner_delegate_target - Vector2(6, 6)
		marker.z_index = 8
		get_parent().add_child(marker)
		var mt := marker.create_tween()
		mt.tween_property(marker, "scale", Vector2(2.0, 2.0), 0.4)
		mt.parallel().tween_property(marker, "modulate:a", 0.0, 0.4)
		mt.tween_callback(marker.queue_free)
	else:
		# Recall buddies back to summoner
		for buddy in get_tree().get_nodes_in_group("donut_buddies"):
			if buddy.get("owner_index") == player_index:
				if "target_position" in buddy:
					buddy.target_position = global_position
				elif buddy.has_method("set_target"):
					buddy.set_target(global_position)


# -- Demolitionist Refuel (Circle held) ---------------------------------------

func _handle_demo_refuel() -> void:
	if not _is_device_action_pressed("interact"):
		return
	if _rocket_fuel >= ROCKET_FUEL_MAX:
		return

	# Refuel 1.5 units per second while holding Circle
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

	AudioManager.play("refuel_gurgle")


# -- Healer Wind Gust (Circle) ------------------------------------------------

func _handle_healer_wind_gust() -> void:
	if _healer_gust_cooldown > 0.0:
		_healer_gust_cooldown -= get_process_delta_time()
	if not _is_device_action_just_pressed("interact"):
		return
	if _healer_gust_cooldown > 0.0:
		_spawn_fail_flash()
		return

	_healer_gust_cooldown = HEALER_GUST_COOLDOWN
	AudioManager.play("wind_gust")

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

	# Push ALL enemies away (5 damage)
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


# -- Tank Abilities ------------------------------------------------------------

var _tank_fortify: bool = false
var _tank_fortify_timer: float = 0.0
var _tank_fortify_cooldown: float = 0.0
const TANK_FORTIFY_DURATION := 8.0
const TANK_FORTIFY_COOLDOWN := 25.0

func _special_tank_slam() -> void:
	AudioManager.play("explosion", 2.0, 0.6)
	_spawn_vfx(Color(0.6, 0.5, 0.3, 0.7), Vector2(80, 80))
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
			if body.has_method("apply_slow"):
				body.apply_slow(2.0)


func _handle_tank_fortify(delta: float) -> void:
	if _tank_fortify_cooldown > 0.0:
		_tank_fortify_cooldown -= delta
	if _is_device_action_just_pressed("interact"):
		if _tank_fortify:
			return
		if _tank_fortify_cooldown > 0.0:
			_spawn_fail_flash()
			return
		_tank_fortify = true
		_tank_fortify_timer = TANK_FORTIFY_DURATION
		AudioManager.play("shield_charge", 2.0, 0.3)
		modulate = Color(0.7, 0.65, 0.5)
		var ft := Label.new()
		ft.text = "FORTIFIED!"
		ft.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ft.add_theme_font_size_override("font_size", 12)
		ft.modulate = Color(0.8, 0.7, 0.4)
		ft.position = global_position + Vector2(-25, -40)
		ft.z_index = 15
		get_parent().add_child(ft)
		var tt := ft.create_tween()
		tt.tween_property(ft, "position:y", ft.position.y - 15, 0.6)
		tt.parallel().tween_property(ft, "modulate:a", 0.0, 0.6)
		tt.tween_callback(ft.queue_free)
	if _tank_fortify:
		_tank_fortify_timer -= delta
		modulate = Color(0.7, 0.65 + sin(_tank_fortify_timer * 4.0) * 0.05, 0.5)
		if _tank_fortify_timer <= 2.0:
			if fmod(_tank_fortify_timer, 0.25) < 0.125:
				modulate = Color.WHITE
		if _tank_fortify_timer <= 0.0:
			_tank_fortify = false
			_tank_fortify_cooldown = TANK_FORTIFY_COOLDOWN
			modulate = Color.WHITE


# -- Jumper Abilities ----------------------------------------------------------

var _jumper_dash_cooldown: float = 0.0
const JUMPER_DASH_COOLDOWN_TD := 0.8
const JUMPER_DASH_SPEED_TD := 400.0

func _special_jumper_dash_attack() -> void:
	# Quick dash in aimed direction + damage at endpoint
	var aim: Vector2 = _get_aim_direction()
	velocity = aim * JUMPER_DASH_SPEED_TD
	AudioManager.play("shadow_dash", -2.0, 1.5)
	_spawn_vfx(Color(0.3, 1.0, 1.0, 0.5), Vector2(14, 14))
	# Damage at destination
	attack_area.position = aim * 20.0
	attack_area.monitoring = true
	await get_tree().create_timer(0.15).timeout
	if is_inside_tree():
		for body in attack_area.get_overlapping_bodies():
			if body.has_method("take_damage"):
				body.take_damage(20, player_index)
		attack_area.monitoring = false

func _handle_jumper_dash() -> void:
	if _jumper_dash_cooldown > 0.0:
		_jumper_dash_cooldown -= get_process_delta_time()
	if not _is_device_action_just_pressed("interact"):
		return
	if _jumper_dash_cooldown > 0.0:
		_spawn_fail_flash()
		return
	_jumper_dash_cooldown = JUMPER_DASH_COOLDOWN_TD
	var aim: Vector2 = _get_aim_direction()
	velocity = aim * JUMPER_DASH_SPEED_TD
	AudioManager.play("shadow_dash", -2.0, 1.5)
	_spawn_vfx(Color(0.3, 1.0, 1.0, 0.4), Vector2(10, 10))
