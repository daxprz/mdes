extends CharacterBody2D

## Adventure Time style animated donut companion.
## Follows the summoner, attacks nearby enemies.
## Uses donut_buddy.png: 144x24, 6 frames at 24x24.

const MAX_HEALTH := 30
const MOVE_SPEED := 80.0
const ATTACK_RANGE := 28.0
const ATTACK_DAMAGE := 8
const ATTACK_COOLDOWN := 1.0
const DETECTION_RANGE := 120.0
const FOLLOW_DISTANCE := 40.0

@export var owner_index: int = 0

var health: int = MAX_HEALTH
var _attack_timer: float = 0.0
var _anim_timer: float = 0.0
var _anim_frame: int = 0
var _target: Node2D = null

const HEALTH_BAR_SCENE := preload("res://scenes/ui/health_bar.tscn")

@onready var sprite: Sprite2D = $Sprite
@onready var collision_shape: CollisionShape2D = $CollisionShape

var _health_bar: Node2D = null


func _ready() -> void:
	add_to_group("donut_buddies")
	sprite.hframes = 6
	sprite.vframes = 1
	sprite.frame = 0
	_health_bar = HEALTH_BAR_SCENE.instantiate()
	_health_bar.bar_width = 16.0
	_health_bar.bar_height = 2.0
	_health_bar.bar_offset = Vector2(0, -16)
	_health_bar.fill_color = Color(1.0, 0.6, 0.2)
	add_child(_health_bar)
	_health_bar.set_health(health, MAX_HEALTH)


func _physics_process(delta: float) -> void:
	_attack_timer -= delta
	_find_target()

	if _target and global_position.distance_to(_target.global_position) <= ATTACK_RANGE:
		_attack()
	elif _target:
		_move_toward(_target.global_position, delta)
	else:
		_follow_owner(delta)

	_update_animation(delta)
	move_and_slide()


func _find_target() -> void:
	_target = null
	var closest_dist := DETECTION_RANGE
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is Node2D:
			var dist: float = global_position.distance_to(enemy.global_position)
			if dist < closest_dist:
				closest_dist = dist
				_target = enemy


func _move_toward(target_pos: Vector2, _delta: float) -> void:
	var dir := (target_pos - global_position).normalized()
	velocity = dir * MOVE_SPEED
	if dir.x != 0:
		sprite.flip_h = dir.x < 0


func _follow_owner(_delta: float) -> void:
	var owner_node := _find_owner()
	if not owner_node:
		# Wander if owner not found
		velocity = velocity.lerp(Vector2.ZERO, 0.1)
		return

	var dist := global_position.distance_to(owner_node.global_position)
	if dist > FOLLOW_DISTANCE:
		var dir := (owner_node.global_position - global_position).normalized()
		velocity = dir * MOVE_SPEED * 0.8
		if dir.x != 0:
			sprite.flip_h = dir.x < 0
	else:
		velocity = velocity.lerp(Vector2.ZERO, 0.15)


func _find_owner() -> Node2D:
	# Look for the player with matching player_index in the scene
	for node in get_tree().get_nodes_in_group("players"):
		if node.has_method("setup") and node.get("player_index") == owner_index:
			return node
	# Fallback: search parent for player nodes
	if get_parent():
		for child in get_parent().get_children():
			if child.get("player_index") == owner_index and child is CharacterBody2D:
				return child
	return null


func _attack() -> void:
	if _attack_timer > 0.0:
		return
	_attack_timer = ATTACK_COOLDOWN

	if _target and _target.has_method("take_damage"):
		_target.take_damage(ATTACK_DAMAGE, owner_index)

	# Play attack animation frames
	sprite.frame = 4  # attack frame


func _update_animation(delta: float) -> void:
	if _attack_timer > ATTACK_COOLDOWN - 0.2:
		# Hold attack frame briefly
		sprite.frame = 4 if _attack_timer > ATTACK_COOLDOWN - 0.1 else 5
		return

	_anim_timer += delta
	if _anim_timer >= 0.15:
		_anim_timer -= 0.15
		if velocity.length() > 10.0:
			# Walk cycle: frames 1-2
			_anim_frame = 1 if _anim_frame != 1 else 2
		else:
			_anim_frame = 0  # idle
		sprite.frame = _anim_frame


func take_damage(amount: int, _from_index: int = -1) -> void:
	health -= amount
	if _health_bar:
		_health_bar.set_health(health, MAX_HEALTH)
	sprite.modulate = Color.RED
	await get_tree().create_timer(0.1).timeout
	if is_inside_tree():
		sprite.modulate = Color.WHITE
	if health <= 0:
		queue_free()
