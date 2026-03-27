extends CharacterBody2D

## Soccer ball dummy — a test entity that monsters can target.
## Rendered as a classic soccer ball (white with black pentagons).
## Rolls realistically: rotation = distance_traveled / radius.

const GRAVITY := 600.0
const BALL_RADIUS := 14.0
const FRICTION := 0.97        # Ground friction (velocity retention per frame)
const AIR_FRICTION := 0.998   # Air friction
const BOUNCE_FACTOR := 0.5    # How much velocity is retained on bounce

var player_index: int = 0
var entity_id: String = ""
var health: int = 1000
var max_health: int = 1000
var damage_taken: int = 0

var _rotation_angle: float = 0.0  # Current visual rotation in radians
var _was_on_floor: bool = false
var _sprite: Sprite2D = null


func _ready() -> void:
	# Replace the capsule collision with a circle for the ball
	for child in get_children():
		if child is CollisionShape2D:
			child.queue_free()
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = BALL_RADIUS
	col.shape = shape
	add_child(col)
	# Load the soccer ball PNG at runtime (bypasses Godot import system)
	var img := Image.new()
	var err := img.load("res://assets/sprites/soccer_ball.png")
	if err == OK:
		var tex := ImageTexture.create_from_image(img)
		_sprite = Sprite2D.new()
		_sprite.texture = tex
		# Scale to match BALL_RADIUS (image is 64x64, we want diameter = BALL_RADIUS*2)
		var tex_size: float = maxf(img.get_width(), img.get_height())
		var scale_f: float = (BALL_RADIUS * 2.0) / tex_size
		_sprite.scale = Vector2(scale_f, scale_f)
		add_child(_sprite)
	else:
		push_warning("Soccer ball PNG failed to load (err=%d)" % err)


func _physics_process(delta: float) -> void:
	# Gravity
	velocity.y += GRAVITY * delta

	# Friction
	if is_on_floor():
		velocity.x *= FRICTION
		# Stop jittering at low speeds
		if absf(velocity.x) < 5.0:
			velocity.x = 0.0
	else:
		velocity.x *= AIR_FRICTION

	var was_vel_y: float = velocity.y
	move_and_slide()

	# Simple bounce: if we hit the floor and were falling, bounce
	if is_on_floor() and was_vel_y > 50.0 and not _was_on_floor:
		velocity.y = -was_vel_y * BOUNCE_FACTOR
	_was_on_floor = is_on_floor()

	# Rolling rotation: angular velocity = linear velocity / radius
	# Positive X velocity = clockwise rotation (positive angle in Godot's Y-down system)
	_rotation_angle += (velocity.x * delta) / BALL_RADIUS
	if _sprite:
		_sprite.rotation = _rotation_angle

	queue_redraw()


func take_damage(amount: int, _source: int = -1) -> void:
	damage_taken += amount
	health -= amount
	if health < 0:
		health = 0
	# Knockback from damage
	var kb_dir: float = 1.0 if randf() > 0.5 else -1.0
	velocity += Vector2(kb_dir * 120.0, -180.0)
	queue_redraw()


func apply_knockback(force: Vector2) -> void:
	velocity += force


func _draw() -> void:
	# HP overlay (ball visual is handled by the Sprite2D child)
	if damage_taken > 0:
		var hp_text: String = "HP:%d DMG:%d" % [health, damage_taken]
		draw_string(ThemeDB.fallback_font, Vector2(-28, -BALL_RADIUS - 6), hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.GREEN)
