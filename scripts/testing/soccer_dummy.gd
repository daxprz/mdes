extends CharacterBody2D

## Soccer ball dummy — a test entity that monsters can target.
## Rendered as a classic soccer ball (white with black pentagons).
## Rolls realistically: rotation = distance_traveled / radius.
## Has its own config stack — every physics body is configurable.

const DEFAULT_GRAVITY := 600.0
const DEFAULT_RADIUS := 14.0
const DEFAULT_FRICTION := 0.97
const DEFAULT_AIR_FRICTION := 0.998
const DEFAULT_BOUNCE := 0.5
const DEFAULT_MASS := 20.0

const DEFAULT_CONFIG := {
	"mass": 20.0,
	"gravity": 600.0,
	"friction": 0.97,
	"air_friction": 0.998,
	"bounce": 0.5,
	"radius": 14.0,
	"max_health": 1000,
}

var player_index: int = 0
var entity_id: String = ""
var mass: float = 20.0
var health: int = 1000
var max_health: int = 1000
var damage_taken: int = 0

# Config stack — standard entity interface
var _config_stack: Array = []
var _base_config: Variant = null

var _rotation_angle: float = 0.0  # Current visual rotation in radians
var _was_on_floor: bool = false
var _sprite: Sprite2D = null


func cfg(key: String, default_val: float) -> float:
	var val: float = default_val
	for provider in _config_stack:
		var pval: Variant = provider.get_value(key)
		if pval != null:
			val = float(pval)
			break
	var MCP = preload("res://scripts/systems/monster_config.gd")
	val = MCP.apply_modifiers(_config_stack, key, val)
	return val


func push_config(provider: Variant) -> void:
	_config_stack.insert(0, provider)


func remove_config(provider: Variant) -> void:
	_config_stack.erase(provider)


func _init_config() -> void:
	if _base_config != null:
		return
	var MCP = preload("res://scripts/systems/monster_config.gd")
	_base_config = MCP.load_class_defaults("soccer_dummy")
	if not _base_config:
		_base_config = MCP.DictProvider.new(DEFAULT_CONFIG, "soccer_defaults")
	_config_stack = [_base_config]


func _ready() -> void:
	_init_config()
	# Apply config to instance vars
	mass = cfg("mass", DEFAULT_MASS)
	max_health = int(cfg("max_health", 1000))
	health = max_health
	# Replace the capsule collision with a circle for the ball
	var ball_radius: float = cfg("radius", DEFAULT_RADIUS)
	for child in get_children():
		if child is CollisionShape2D:
			child.queue_free()
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = ball_radius
	col.shape = shape
	add_child(col)
	# Load the soccer ball PNG at runtime (bypasses Godot import system)
	var img := Image.new()
	var err := img.load("res://assets/sprites/soccer_ball.png")
	if err == OK:
		var tex := ImageTexture.create_from_image(img)
		_sprite = Sprite2D.new()
		_sprite.texture = tex
		# Scale to match ball radius (image is 64x64, we want diameter = radius*2)
		var tex_size: float = maxf(img.get_width(), img.get_height())
		var scale_f: float = (ball_radius * 2.0) / tex_size
		_sprite.scale = Vector2(scale_f, scale_f)
		add_child(_sprite)
	else:
		push_warning("Soccer ball PNG failed to load (err=%d)" % err)


func _physics_process(delta: float) -> void:
	# Gravity
	velocity.y += cfg("gravity", DEFAULT_GRAVITY) * delta

	# Friction
	if is_on_floor():
		velocity.x *= cfg("friction", DEFAULT_FRICTION)
		if absf(velocity.x) < 5.0:
			velocity.x = 0.0
	else:
		velocity.x *= cfg("air_friction", DEFAULT_AIR_FRICTION)

	var was_vel_y: float = velocity.y
	move_and_slide()

	# Simple bounce: if we hit the floor and were falling, bounce
	if is_on_floor() and was_vel_y > 50.0 and not _was_on_floor:
		velocity.y = -was_vel_y * cfg("bounce", DEFAULT_BOUNCE)
	_was_on_floor = is_on_floor()

	# Rolling rotation: angular velocity = linear velocity / radius
	# Rotate the body itself so child nodes (stuck arrows, etc.) follow
	_rotation_angle += (velocity.x * delta) / cfg("radius", DEFAULT_RADIUS)
	rotation = _rotation_angle

	queue_redraw()


func take_damage(amount: int, _source: int = -1) -> void:
	damage_taken += amount
	health -= amount
	if health < 0:
		health = 0
	queue_redraw()


func apply_knockback(force: Vector2) -> void:
	velocity += force


func _draw() -> void:
	# HP overlay (ball visual is handled by the Sprite2D child)
	if damage_taken > 0:
		var hp_text: String = "HP:%d DMG:%d" % [health, damage_taken]
		draw_string(ThemeDB.fallback_font, Vector2(-28, -cfg("radius", DEFAULT_RADIUS) - 6), hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.GREEN)
