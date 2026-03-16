extends CharacterBody2D

## Marshmallow Blob - bouncy ground enemy that splits into smaller blobs on death.
## Large -> 2 Medium -> 2 Small each.

signal died(global_pos: Vector2)

const GRAVITY := 800.0
const BASE_SPEED := 35.0
const SPEED_PER_TIER := 15.0
const BASE_CONTACT_DAMAGE := 8
const DAMAGE_REDUCTION_PER_TIER := 2
const BOUNCE_AMPLITUDE := 6.0
const BOUNCE_FREQUENCY := 4.0
const SPLIT_OFFSET := 15.0

const TIER_HEALTH := [20, 10, 5]
const TIER_SCALE := [1.0, 0.6, 0.35]

@export var size_tier: int = 0  # 0=large, 1=medium, 2=small

var health := 20
var max_health := 20
var patrol_direction := 1.0
var _patrol_distance := 100.0
var _start_x := 0.0
var _time := 0.0
var _hurt_timer := 0.0
var _anim_timer := 0.0
var _dead := false

const HEALTH_BAR_SCENE := preload("res://scenes/ui/health_bar.tscn")
const SELF_SCENE_PATH := "res://scenes/enemies/marshmallow_blob.tscn"

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var hitbox: Area2D = $Hitbox

var _health_bar: Node2D = null


func _ready() -> void:
	add_to_group("enemies")
	_start_x = global_position.x

	# Apply tier stats
	max_health = TIER_HEALTH[size_tier]
	health = max_health
	scale = Vector2(TIER_SCALE[size_tier], TIER_SCALE[size_tier])

	if hitbox:
		hitbox.body_entered.connect(_on_hitbox_body_entered)
	_health_bar = HEALTH_BAR_SCENE.instantiate()
	_health_bar.bar_width = 18.0
	_health_bar.bar_height = 2.0
	_health_bar.bar_offset = Vector2(0, -16)
	_health_bar.fill_color = Color(1.0, 0.85, 0.9)
	add_child(_health_bar)
	_health_bar.set_health(health, max_health)


func _physics_process(delta: float) -> void:
	if _dead:
		return

	# Gravity
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	else:
		velocity.y = 0.0

	_hurt_timer -= delta
	_time += delta

	if _hurt_timer > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, 200.0 * delta)
		move_and_slide()
		queue_redraw()
		return

	# Movement
	var speed: float = BASE_SPEED + size_tier * SPEED_PER_TIER
	velocity.x = speed * patrol_direction

	if is_on_wall():
		patrol_direction *= -1.0
	elif abs(global_position.x - _start_x) > _patrol_distance:
		patrol_direction *= -1.0

	# Bounce effect on y (visual only, applied to position offset via draw)
	_animate(delta)
	move_and_slide()
	queue_redraw()


func _draw() -> void:
	if _dead:
		return

	# Bounce offset
	var bounce_y: float = absf(sin(_time * BOUNCE_FREQUENCY)) * BOUNCE_AMPLITUDE

	# White/pink rounded body
	var body_color := Color(1.0, 0.9, 0.95)
	var highlight := Color(1.0, 0.75, 0.85)

	# Main body (rounded rectangle approximation with circles)
	draw_circle(Vector2(0, -4 - bounce_y), 12, body_color)
	draw_circle(Vector2(-5, 2 - bounce_y), 8, body_color)
	draw_circle(Vector2(5, 2 - bounce_y), 8, body_color)
	draw_rect(Rect2(-10, -8 - bounce_y, 20, 14), body_color)

	# Highlight
	draw_circle(Vector2(-3, -8 - bounce_y), 4, highlight)

	# Eyes
	draw_circle(Vector2(-4, -4 - bounce_y), 2, Color.BLACK)
	draw_circle(Vector2(4, -4 - bounce_y), 2, Color.BLACK)
	# Mouth
	draw_line(Vector2(-3, 0 - bounce_y), Vector2(3, 0 - bounce_y), Color(0.7, 0.4, 0.5), 1.5)


func _animate(delta: float) -> void:
	if not sprite:
		return
	sprite.flip_h = patrol_direction < 0
	_anim_timer += delta
	if _anim_timer >= 0.15:
		_anim_timer -= 0.15
		sprite.frame = (sprite.frame + 1) % 4


func _find_nearest_player() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := INF
	for p in get_tree().get_nodes_in_group("players"):
		if p is Node2D:
			var dist: float = global_position.distance_to(p.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = p
	return nearest


func set_patrol_distance(dist: float) -> void:
	_patrol_distance = dist


func take_damage(amount: int, _source_index: int = -1) -> void:
	if _dead:
		return
	# Rift tentacle absorbs damage first
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
	if _health_bar:
		_health_bar.set_health(health, max_health)

	_hurt_timer = 0.2
	var kb_dir: float = -patrol_direction
	velocity.x = kb_dir * 100.0
	velocity.y = -80.0

	AudioManager.play("enemy_hit", -3.0)
	_flash_hit()

	if health <= 0:
		_die()


func _flash_hit() -> void:
	if sprite:
		sprite.modulate = Color.RED
		var tween := create_tween()
		tween.tween_property(sprite, "modulate", Color.WHITE, 0.15)


func _die() -> void:
	_dead = true
	var HealthPickup := load("res://scripts/items/health_pickup.gd")
	HealthPickup.try_spawn(get_parent(), global_position)
	AudioManager.play("enemy_die")
	died.emit(global_position)

	# Spawn smaller blobs if not smallest tier
	if size_tier < 2:
		_spawn_split_blobs()

	collision_shape.set_deferred("disabled", true)
	if hitbox:
		hitbox.set_deferred("monitoring", false)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(0.05, 0.05), 0.25)
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	tween.chain().tween_callback(queue_free)


func _spawn_split_blobs() -> void:
	var blob_scene := load(SELF_SCENE_PATH)
	if not blob_scene:
		return

	for i in range(2):
		var blob: CharacterBody2D = blob_scene.instantiate()
		var x_offset: float = SPLIT_OFFSET if i == 0 else -SPLIT_OFFSET
		blob.global_position = global_position + Vector2(x_offset, -5)
		blob.size_tier = size_tier + 1
		blob.patrol_direction = 1.0 if i == 0 else -1.0

		# Connect died signal to parent's enemies container for muffin drops
		var enemies_node: Node = get_parent()
		if enemies_node:
			blob.died.connect(func(pos: Vector2) -> void:
				pass  # Split blobs don't drop extra muffins
			)
			enemies_node.add_child(blob)


func apply_knockback(force: Vector2) -> void:
	velocity = force
	_hurt_timer = 0.2


func apply_slow(duration: float) -> void:
	if is_inside_tree():
		_hurt_timer = duration


func _on_hitbox_body_entered(body: Node2D) -> void:
	if _dead:
		return
	if "player_index" in body or body.has_meta("player_index"):
		var player_index: int = body.get("player_index") if "player_index" in body else body.get_meta("player_index")
		var dmg: int = BASE_CONTACT_DAMAGE - size_tier * DAMAGE_REDUCTION_PER_TIER
		PlayerManager.damage_player(player_index, dmg)
		if body.has_method("take_damage"):
			body.take_damage(dmg, -1)
