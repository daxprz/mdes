extends CharacterBody2D

## Vector-graphics bat for the title screen.
## Swooping graceful movement, hunts fireflies, interactive with game systems.

signal died(global_pos: Vector2)

const MAX_HEALTH := 8
const MOVE_SPEED := 160.0
const MIN_SPEED := 60.0  # Must always be moving at least this fast
const NOISE_SCALE := 0.6  # Higher = more frequent direction changes
const WING_SPEED := 8.0
const FIREFLY_DETECT_RANGE := 100.0
const FIREFLY_EAT_RANGE := 10.0
const GRAVITY := 200.0

const HUNGER_COOLDOWN := 5.0
const MAX_BELLY := 5  # Stops eating after this many

var health := MAX_HEALTH
var mass := 3.0  # Very light
var _dead := false
var _timer: float = 0.0
var _hunger_timer: float = 0.0  # Counts down to next meal
var _belly: int = 0  # How many fireflies eaten
var _wing_phase: float = 0.0
var _direction: float = 1.0
var _target_vel: Vector2 = Vector2.ZERO
var _firefly_manager: Node2D = null
var _bounds: Rect2 = Rect2(100, 300, 1720, 500)
var _noise: FastNoiseLite = null
var _noise_offset: float = 0.0  # Unique offset per bat
var _migration_patterns: Array = []  # Array of MigrationPattern nodes
var _migration_zone: int = -1  # zone_id of last entered migration zone
var _migration_offset: int = 0  # Random phase offset (stagger)
var _migration_offset_set: bool = false

@onready var collision_shape: CollisionShape2D = null


func setup(firefly_mgr: Node2D, bounds: Rect2, migration_patterns: Array = []) -> void:
	_firefly_manager = firefly_mgr
	_bounds = bounds
	_migration_patterns = migration_patterns


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 8  # Enemy layer
	collision_mask = 1   # World only

	# Create collision shape
	collision_shape = CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 8.0
	collision_shape.shape = shape
	add_child(collision_shape)

	_direction = 1.0 if randf() > 0.5 else -1.0
	_wing_phase = randf() * TAU
	_timer = randf() * 5.0
	_noise_offset = randf() * 1000.0  # Unique noise sampling offset per bat
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.seed = randi()
	_noise.frequency = 0.8


func _physics_process(delta: float) -> void:
	if _dead:
		return

	_timer += delta
	_wing_phase += WING_SPEED * delta

	# Perlin noise-driven movement (organic, unpredictable)
	var noise_x: float = _noise.get_noise_2d(_timer * NOISE_SCALE + _noise_offset, 0.0)
	var noise_y: float = _noise.get_noise_2d(0.0, _timer * NOISE_SCALE + _noise_offset + 500.0)
	_target_vel = Vector2(noise_x * MOVE_SPEED * 1.5, noise_y * MOVE_SPEED)
	_direction = signf(_target_vel.x) if absf(_target_vel.x) > 5.0 else _direction

	# Hunger cooldown
	if _hunger_timer > 0.0:
		_hunger_timer -= delta

	# Hunt fireflies (only if hungry and not full)
	var is_hungry: bool = _hunger_timer <= 0.0 and _belly < MAX_BELLY
	if is_hungry and _firefly_manager and is_instance_valid(_firefly_manager):
		var nearest_fly: Vector2 = _firefly_manager.get_nearest_fly(global_position, FIREFLY_DETECT_RANGE)
		if nearest_fly != Vector2.INF:
			var to_fly: Vector2 = (nearest_fly - global_position)
			_target_vel = to_fly.normalized() * MOVE_SPEED * 1.3
			_direction = signf(to_fly.x) if absf(to_fly.x) > 1.0 else _direction

			if to_fly.length() < FIREFLY_EAT_RANGE:
				if _firefly_manager.remove_nearest(global_position):
					AudioManager.play("menu_select", -12.0, 2.0)
					_hunger_timer = HUNGER_COOLDOWN
					_belly += 1

	# Gravitate toward firefly spawn zones (when not hunting)
	if not is_hungry or not _firefly_manager or not is_instance_valid(_firefly_manager):
		pass  # Just use noise movement
	elif _firefly_manager.get_nearest_fly(global_position, FIREFLY_DETECT_RANGE) == Vector2.INF:
		# No nearby fly — drift toward a random zone
		if not _firefly_manager._zones.is_empty():
			var zone_idx: int = randi() % _firefly_manager._zones.size()
			var zone: Rect2 = _firefly_manager._zones[zone_idx]
			if not zone.has_point(global_position):
				var pull: Vector2 = (zone.get_center() - global_position).normalized() * MOVE_SPEED * 0.4
				_target_vel += pull

	# Migration force (overrides normal drift when active)
	var migrating := false
	for pattern in _migration_patterns:
		if not pattern.has_species("bats"):
			continue
		# Assign stagger offset once
		if not _migration_offset_set:
			_migration_offset = pattern.generate_offset()
			_migration_offset_set = true
		var eff_phase: int = pattern.effective_phase(_migration_offset)
		var phase_ids: Array[int] = pattern.get_zone_ids_for_phase(eff_phase)
		if phase_ids.has(_migration_zone):
			continue  # Already arrived — normal behavior
		var nearest_zone: Dictionary = pattern.get_nearest_zone_in_phase(global_position, eff_phase)
		if nearest_zone.is_empty():
			continue
		if pattern.is_in_zone(global_position, nearest_zone):
			_migration_zone = nearest_zone["zone_id"]
			continue  # Just arrived
		var strength: float = nearest_zone["strength"]
		_target_vel = (nearest_zone["point"] - global_position).normalized() * MOVE_SPEED * strength
		_direction = signf(_target_vel.x) if absf(_target_vel.x) > 5.0 else _direction
		migrating = true
		break

	# Repulsion from other bats
	var repulse := Vector2.ZERO
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self or not is_instance_valid(other) or not other is CharacterBody2D:
			continue
		var away: Vector2 = global_position - other.global_position
		var dist: float = away.length()
		if dist > 0.0 and dist < 120.0:
			# Inverse-square falloff: strong close, fades at range
			repulse += away.normalized() * (1.0 - dist / 120.0) * MOVE_SPEED * 2.0
	_target_vel += repulse

	# Faster response — more abrupt direction changes
	velocity = velocity.lerp(_target_vel, delta * 6.0)

	# Enforce minimum speed — bats must always be moving
	if velocity.length() < MIN_SPEED:
		if velocity.length() > 0.1:
			velocity = velocity.normalized() * MIN_SPEED
		else:
			velocity = Vector2(_direction * MIN_SPEED, randf_range(-20, 20))

	# Bounds steering
	if global_position.x < _bounds.position.x:
		velocity.x += 200.0 * delta
	elif global_position.x > _bounds.end.x:
		velocity.x -= 200.0 * delta
	if global_position.y < _bounds.position.y - 50:
		velocity.y += 150.0 * delta
	elif global_position.y > _bounds.end.y:
		velocity.y -= 150.0 * delta

	move_and_slide()
	queue_redraw()


func _draw() -> void:
	if _dead:
		return

	var wing_flap: float = sin(_wing_phase) * 0.7
	var body_color := Color(0.2, 0.2, 0.22)
	var wing_color := Color(0.25, 0.24, 0.26)
	var eye_color := Color(0.9, 0.15, 0.1)
	var facing: float = -1.0 if _direction < 0 else 1.0

	# Body (small oval)
	draw_circle(Vector2.ZERO, 4.0, body_color)
	draw_circle(Vector2(facing * 2.0, -1.0), 2.5, body_color)  # Head

	# Eyes (tiny red dots)
	draw_circle(Vector2(facing * 3.5, -2.0), 1.0, eye_color)
	draw_circle(Vector2(facing * 3.5, -2.0), 0.5, Color(1.0, 0.3, 0.2))

	# Wings (triangular, flapping)
	var wing_y: float = wing_flap * 6.0
	# Left wing
	draw_polygon(PackedVector2Array([
		Vector2(-2, 0),
		Vector2(-10 * facing, -3 + wing_y),
		Vector2(-7 * facing, 1 + wing_y * 0.5),
	]), PackedColorArray([wing_color, wing_color, wing_color]))
	# Right wing
	draw_polygon(PackedVector2Array([
		Vector2(-2, 0),
		Vector2(-10 * facing, -3 - wing_y),
		Vector2(-7 * facing, 1 - wing_y * 0.5),
	]), PackedColorArray([wing_color, wing_color, wing_color]))

	# Wing membrane lines
	var line_col := body_color * Color(0.7, 0.7, 0.7)
	draw_line(Vector2(-2, 0), Vector2(-9 * facing, -2 + wing_y), line_col, 0.5)
	draw_line(Vector2(-2, 0), Vector2(-9 * facing, -2 - wing_y), line_col, 0.5)


func take_damage(amount: int, _source_index: int = -1) -> void:
	if _dead:
		return
	# Rift tentacle absorption
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
	if health <= 0:
		_die()


func _die() -> void:
	_dead = true
	AudioManager.play("enemy_die", -6.0, 1.5)
	died.emit(global_position)
	# No drops for bats
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(0.1, 0.1), 0.3)
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.chain().tween_callback(queue_free)


func apply_knockback(force: Vector2) -> void:
	velocity = force * 2.0  # Light = big knockback
