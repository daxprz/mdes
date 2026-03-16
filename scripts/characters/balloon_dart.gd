extends Node2D

## Physics-based balloon dart system.
## A dart flies out, trailing a string. When it hits an enemy,
## a balloon inflates at the string end and tugs the enemy upward.
## The string is physics-simulated with segments.

const DART_SPEED := 350.0
const DART_DAMAGE := 8
const STRING_SEGMENTS := 12
const STRING_SEGMENT_LENGTH := 10.0
const BALLOON_FLOAT_FORCE := -180.0  # Negative = upward
const BALLOON_INFLATE_TIME := 1.5
const BALLOON_MAX_RADIUS := 16.0
const BALLOON_WIND_SENSITIVITY := 3.0  # How much wind affects the balloon
const BALLOON_LIFETIME := 8.0

var dart_direction: Vector2 = Vector2.RIGHT
var owner_index: int = -1

var _dart_pos: Vector2
var _dart_vel: Vector2
var _dart_active := true
var _attached_to: Node2D = null

var _string_points: Array[Vector2] = []
var _balloon_pos: Vector2
var _balloon_radius: float = 2.0
var _balloon_inflating := false
var _balloon_timer: float = 0.0
var _balloon_color: Color

var _age: float = 0.0
var _wind_dir: Vector2 = Vector2.ZERO
var _wind_force: float = 0.0

# Weight constants for different entity types
const WEIGHTS: Dictionary = {
	"player": 70.0,     # Average person
	"skeleton": 30.0,   # Light bones
	"bat": 5.0,         # Tiny
	"golem": 150.0,     # Heavy
	"boss": 300.0,      # Very heavy
	"muffin": 0.5,      # Tiny item
	"default": 50.0,
}


func _ready() -> void:
	add_to_group("balloon_darts")
	# Pick a random balloon color
	var colors: Array[Color] = [
		Color(1.0, 0.3, 0.4),  # Red
		Color(0.3, 0.7, 1.0),  # Blue
		Color(1.0, 0.9, 0.2),  # Yellow
		Color(0.4, 1.0, 0.4),  # Green
		Color(1.0, 0.5, 0.8),  # Pink
		Color(0.8, 0.4, 1.0),  # Purple
	]
	_balloon_color = colors[randi() % colors.size()]

	_dart_pos = global_position
	_dart_vel = dart_direction.normalized() * DART_SPEED

	# Initialize string points from dart to spawn
	_string_points.clear()
	for i in range(STRING_SEGMENTS):
		_string_points.append(global_position)
	_balloon_pos = global_position


func _process(delta: float) -> void:
	_age += delta
	if _age > BALLOON_LIFETIME + BALLOON_INFLATE_TIME + 2.0:
		_detach_and_free()
		return

	_detect_wind()

	if _dart_active:
		_update_dart(delta)
	elif _balloon_inflating:
		_update_balloon(delta)

	_update_string_physics(delta)
	_apply_balloon_force(delta)

	queue_redraw()


func _update_dart(delta: float) -> void:
	_dart_vel.y += 100.0 * delta  # Slight gravity on dart
	_dart_pos += _dart_vel * delta

	# Check for enemy hits
	for body in get_tree().get_nodes_in_group("enemies"):
		if not body is Node2D:
			continue
		var dist: float = _dart_pos.distance_to(body.global_position)
		if dist < 16.0:
			_dart_active = false
			_attached_to = body
			_balloon_inflating = true
			_balloon_timer = 0.0
			AudioManager.play("grapple_hit")
			if body.has_method("take_damage"):
				body.take_damage(DART_DAMAGE, owner_index)
			return

	# Check for player hits (attach balloon to teammates - no damage!)
	for body in get_tree().get_nodes_in_group("players"):
		if not body is Node2D:
			continue
		# Don't attach to the balloonist who shot it
		if "player_index" in body and body.player_index == owner_index:
			continue
		var dist: float = _dart_pos.distance_to(body.global_position)
		if dist < 16.0:
			_dart_active = false
			_attached_to = body
			_balloon_inflating = true
			_balloon_timer = 0.0
			AudioManager.play("muffin_collect", -2.0, 1.2)
			return

	# Check for wall hits
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		_dart_pos - _dart_vel * delta,
		_dart_pos,
		1  # World layer
	)
	var result: Dictionary = space.intersect_ray(query)
	if result:
		_dart_active = false
		_dart_pos = result["position"]
		# Stick to wall, start inflating balloon anyway
		_balloon_inflating = true
		_balloon_timer = 0.0
		AudioManager.play("grapple_hit", -4.0)

	# Despawn if too far
	if _dart_pos.distance_to(global_position) > 400.0:
		queue_free()


func _update_balloon(delta: float) -> void:
	_balloon_timer += delta

	# Inflate the balloon over time
	var inflate_ratio: float = clampf(_balloon_timer / BALLOON_INFLATE_TIME, 0.0, 1.0)
	_balloon_radius = lerpf(2.0, BALLOON_MAX_RADIUS, inflate_ratio * inflate_ratio)

	# Balloon lifetime
	if _balloon_timer > BALLOON_INFLATE_TIME + BALLOON_LIFETIME:
		# Pop!
		AudioManager.play("explosion", -6.0, 2.0)
		_spawn_pop_particles()
		_detach_and_free()


func _update_string_physics(delta: float) -> void:
	# String anchor point: attached enemy or dart position
	var anchor: Vector2 = _dart_pos
	if is_instance_valid(_attached_to):
		anchor = _attached_to.global_position

	# First point follows the anchor
	_string_points[0] = anchor

	# Balloon at the end of the string
	# Apply wind + float to balloon position
	var balloon_target_y: float = anchor.y + BALLOON_FLOAT_FORCE * 0.5  # Float above
	_balloon_pos.x = _balloon_pos.lerp(Vector2(anchor.x + _wind_dir.x * _wind_force * BALLOON_WIND_SENSITIVITY, 0), delta * 2.0).x
	_balloon_pos.y = lerpf(_balloon_pos.y, balloon_target_y, delta * 1.5)

	# Wind pushes balloon sideways
	_balloon_pos.x += _wind_dir.x * _wind_force * BALLOON_WIND_SENSITIVITY * delta
	_balloon_pos.y += _wind_dir.y * _wind_force * BALLOON_WIND_SENSITIVITY * delta * 0.5

	# Last string point follows balloon
	_string_points[STRING_SEGMENTS - 1] = _balloon_pos

	# Simulate middle string segments (simple verlet-like)
	for iteration in range(3):
		for i in range(1, STRING_SEGMENTS - 1):
			var prev: Vector2 = _string_points[i - 1]
			var next: Vector2 = _string_points[i + 1]
			# Move toward midpoint of neighbors
			var target: Vector2 = (prev + next) / 2.0
			_string_points[i] = _string_points[i].lerp(target, 0.4)

			# Gravity on string segments
			_string_points[i].y += 15.0 * delta

			# Constrain distance between segments
			var to_prev: Vector2 = _string_points[i] - prev
			if to_prev.length() > STRING_SEGMENT_LENGTH:
				_string_points[i] = prev + to_prev.normalized() * STRING_SEGMENT_LENGTH


func _apply_balloon_force(delta: float) -> void:
	if not is_instance_valid(_attached_to) or not _balloon_inflating:
		return

	# Calculate lift force based on balloon size
	var inflate_ratio: float = clampf(_balloon_timer / BALLOON_INFLATE_TIME, 0.0, 1.0)
	var lift_force: float = BALLOON_FLOAT_FORCE * inflate_ratio * inflate_ratio

	# Get the entity's weight
	var entity_weight: float = _get_entity_weight(_attached_to)

	# Net force: balloon lift vs entity weight
	# If balloon lift overcomes weight, entity floats up
	var net_force: float = lift_force + entity_weight
	# negative net_force = upward, positive = stays grounded

	if "velocity" in _attached_to:
		if net_force < 0.0:
			# Balloon is winning! Tug the entity upward
			_attached_to.velocity.y += net_force * delta * 3.0
			# Cap upward velocity
			if _attached_to.velocity.y < -120.0:
				_attached_to.velocity.y = -120.0
		# Even if not fully lifting, reduce gravity effect (balloon assists)
		_attached_to.velocity.y -= absf(lift_force) * delta * 1.5

		# Multiple balloons stack! Check how many are attached
		var balloon_count: int = 0
		for dart in get_tree().get_nodes_in_group("balloon_darts"):
			if dart != self and dart.has_method("_get_entity_weight") and dart._attached_to == _attached_to:
				balloon_count += 1
		if balloon_count > 0:
			# Extra lift per additional balloon
			_attached_to.velocity.y -= 40.0 * balloon_count * delta


func _get_entity_weight(entity: Node2D) -> float:
	# Check for explicit weight
	if entity.has_meta("weight"):
		return entity.get_meta("weight")

	# Estimate from groups
	if entity.is_in_group("bosses"):
		return WEIGHTS["boss"]
	if entity.is_in_group("enemies"):
		# Try to guess from name
		var ename: String = entity.name.to_lower()
		if "golem" in ename or "candy_golem" in ename:
			return WEIGHTS["golem"]
		if "bat" in ename or "fairy" in ename:
			return WEIGHTS["bat"]
		if "skeleton" in ename:
			return WEIGHTS["skeleton"]
		return WEIGHTS["default"]
	if entity.is_in_group("players"):
		return WEIGHTS["player"]
	return WEIGHTS["default"]


func _detect_wind() -> void:
	_wind_dir = Vector2.ZERO
	_wind_force = 0.0
	for node in get_tree().get_nodes_in_group("wind_gusts"):
		if not node is Node2D:
			continue
		var dist: float = _balloon_pos.distance_to(node.global_position)
		if dist < 250.0 and "push_direction" in node and "force" in node:
			_wind_dir = node.get("push_direction") as Vector2
			_wind_force = node.get("force") as float
			break


func _spawn_pop_particles() -> void:
	for i in range(8):
		var p := ColorRect.new()
		p.color = _balloon_color
		p.color.a = 0.7
		p.size = Vector2(4, 4)
		p.position = _balloon_pos + Vector2(randf_range(-5, 5), randf_range(-5, 5))
		p.z_index = 8
		get_parent().add_child(p)
		var vel: Vector2 = Vector2(randf_range(-60, 60), randf_range(-60, 30))
		var pt := p.create_tween()
		pt.tween_property(p, "position", p.position + vel * 0.3, 0.3)
		pt.parallel().tween_property(p, "modulate:a", 0.0, 0.3)
		pt.tween_callback(p.queue_free)


func _detach_and_free() -> void:
	_attached_to = null
	_balloon_inflating = false
	queue_free()


func _draw() -> void:
	# Draw dart (if still flying)
	if _dart_active:
		var local_dart: Vector2 = _dart_pos - global_position
		draw_circle(local_dart, 2.0, Color(0.8, 0.8, 0.8))
		# Dart tail
		var tail_dir: Vector2 = -_dart_vel.normalized() * 6.0
		draw_line(local_dart, local_dart + tail_dir, Color(0.6, 0.5, 0.4), 1.5)

	# Draw string
	for i in range(STRING_SEGMENTS - 1):
		var p1: Vector2 = _string_points[i] - global_position
		var p2: Vector2 = _string_points[i + 1] - global_position
		var string_color := Color(0.6, 0.6, 0.6, 0.7)
		draw_line(p1, p2, string_color, 1.0)

	# Draw balloon
	if _balloon_inflating or _balloon_radius > 2.0:
		var local_balloon: Vector2 = _balloon_pos - global_position

		# Balloon body (oval)
		var r: float = _balloon_radius
		# Outer
		draw_circle(local_balloon, r, _balloon_color)
		# Highlight
		draw_circle(local_balloon + Vector2(-r * 0.3, -r * 0.3), r * 0.3, Color(1, 1, 1, 0.4))
		# Knot at bottom
		draw_circle(local_balloon + Vector2(0, r * 0.8), 2.0, _balloon_color.darkened(0.3))

		# Tie string to balloon knot
		var knot: Vector2 = local_balloon + Vector2(0, r * 0.8)
		var last_string: Vector2 = _string_points[STRING_SEGMENTS - 1] - global_position
		draw_line(last_string, knot, Color(0.6, 0.6, 0.6, 0.7), 1.0)
