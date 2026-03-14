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

	for action in ["move_up", "move_down", "move_left", "move_right", "attack", "special", "interact"]:
		if event.is_action_pressed(action):
			_controller_actions[action] = true
			_controller_just_pressed[action] = true
		elif event.is_action_released(action):
			_controller_actions[action] = false


func _physics_process(delta: float) -> void:
	_update_cooldowns(delta)
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
			_special_ranged()
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


func _special_ranged() -> void:
	# Explosive muffin: area damage around self
	for body in attack_area.get_overlapping_bodies():
		if body.has_method("take_damage"):
			body.take_damage(20, player_index)


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
	# Spawn bomb that travels in facing direction
	var bomb := ColorRect.new()
	bomb.color = Color(0.9, 0.6, 0.1)
	bomb.size = Vector2(8, 8)
	bomb.z_index = 5
	get_parent().add_child(bomb)
	bomb.global_position = global_position + facing * 12.0

	var bomb_vel: Vector2 = facing * 180.0
	var bomb_time := 0.0
	var bomb_max_time := 1.5

	while bomb_time < bomb_max_time and is_instance_valid(bomb):
		var dt: float = get_process_delta_time()
		bomb_time += dt
		bomb.global_position += bomb_vel * dt
		bomb_vel *= 0.98  # Slow down over time

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

	if is_instance_valid(bomb):
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

	while bomb_time < bomb_max_time and is_instance_valid(bomb):
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

	if is_instance_valid(bomb):
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
