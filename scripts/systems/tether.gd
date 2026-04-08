extends Node2D

## Tether — a physics rope connecting two anchor points.
## Persists independently after the player places it.
## Pulls anchors toward each other when distance exceeds target length.
## Can be severed by projectile damage.

# -- Constants -----------------------------------------------------------------

const TETHER_PULL_FORCE := 25000.0   # Very strong pull when over-length
const TETHER_PULL_DAMPING := 0.9     # Damping on pull velocity
const TETHER_MIN_LEN := 30.0
const TETHER_MAX_LEN := 900.0
const TETHER_MAX_HP := 1000
const TETHER_HIT_RADIUS := 8.0      # Proximity for projectile hit detection
const ROPE_SEGMENTS := 16            # Visual rope segments
const WALL_MASS := 99999.0           # Effectively infinite

# -- Anchor data ---------------------------------------------------------------
# Each anchor is a Dictionary with keys:
#   pos: Vector2          - world position (for walls)
#   body: Node2D          - entity (enemy, player) or null for wall
#   body_offset: Vector2  - local offset from body origin
#   attach_point: String  - attachment point name on body (or "")
#   is_wall: bool         - true if anchored to static geometry

# -- State ---------------------------------------------------------------------

var anchor_a: Dictionary = {}
var anchor_b: Dictionary = {}
var target_length: float = 200.0
var current_hp: int = TETHER_MAX_HP
var _severed: bool = false
var _owner_index: int = -1  # Player who created this tether

# Rope visual points (computed each frame)
var _rope_points: PackedVector2Array = PackedVector2Array()


static func make_anchor_wall(world_pos: Vector2) -> Dictionary:
	return { "pos": world_pos, "body": null, "body_offset": Vector2.ZERO, "attach_point": "", "is_wall": true }


static func make_anchor_body(body: Node2D, attach_point: String = "", offset: Vector2 = Vector2.ZERO) -> Dictionary:
	return { "pos": Vector2.ZERO, "body": body, "body_offset": offset, "attach_point": attach_point, "is_wall": false }


static func get_anchor_world_pos(anchor: Dictionary) -> Vector2:
	if anchor.get("is_wall", false):
		return anchor.get("pos", Vector2.ZERO)
	var body: Node2D = anchor.get("body")
	if is_instance_valid(body):
		var ap: String = anchor.get("attach_point", "")
		if ap != "" and body.has_method("get_attach_world_position"):
			return body.get_attach_world_position(ap)
		return body.global_position + anchor.get("body_offset", Vector2.ZERO)
	return anchor.get("pos", Vector2.ZERO)


static func get_anchor_mass(anchor: Dictionary) -> float:
	if anchor.get("is_wall", false):
		return WALL_MASS
	var body: Node2D = anchor.get("body")
	if is_instance_valid(body):
		var ap: String = anchor.get("attach_point", "")
		if ap != "" and body.has_method("get_segment_weight"):
			return body.get_segment_weight(ap)
		if "mass" in body:
			return body.mass
	return 50.0


func _ready() -> void:
	add_to_group("tethers")
	z_index = 5


func setup(a: Dictionary, b: Dictionary, length: float, owner_idx: int = -1) -> void:
	anchor_a = a
	anchor_b = b
	target_length = clampf(length, TETHER_MIN_LEN, TETHER_MAX_LEN)
	_owner_index = owner_idx


func _physics_process(delta: float) -> void:
	if _severed:
		return

	# Check if anchors are still valid
	if not anchor_a.get("is_wall", false) and not is_instance_valid(anchor_a.get("body")):
		sever()
		return
	if not anchor_b.get("is_wall", false) and not is_instance_valid(anchor_b.get("body")):
		sever()
		return

	var pos_a: Vector2 = get_anchor_world_pos(anchor_a)
	var pos_b: Vector2 = get_anchor_world_pos(anchor_b)
	var dist: float = pos_a.distance_to(pos_b)

	# Apply pull force when distance exceeds target length
	if dist > target_length and dist > 0.1:
		var over: float = dist - target_length
		var direction: Vector2 = (pos_b - pos_a).normalized()
		var force_magnitude: float = TETHER_PULL_FORCE * (over / target_length)

		var mass_a: float = get_anchor_mass(anchor_a)
		var mass_b: float = get_anchor_mass(anchor_b)
		var total_mass: float = mass_a + mass_b

		# Distribute force inversely proportional to mass
		var ratio_a: float = mass_b / total_mass  # Lighter = moves more
		var ratio_b: float = mass_a / total_mass

		# Apply to anchor A (pull toward B)
		if not anchor_a.get("is_wall", false) and is_instance_valid(anchor_a.get("body")):
			_apply_force_to_anchor(anchor_a, direction * force_magnitude * ratio_a * delta)

		# Apply to anchor B (pull toward A)
		if not anchor_b.get("is_wall", false) and is_instance_valid(anchor_b.get("body")):
			_apply_force_to_anchor(anchor_b, -direction * force_magnitude * ratio_b * delta)

	# Check for projectile hits (severing)
	_check_projectile_hits(pos_a, pos_b)

	# Update visual
	_compute_rope_points(pos_a, pos_b, dist)
	queue_redraw()


func _apply_force_to_anchor(anchor: Dictionary, force: Vector2) -> void:
	var body: Node2D = anchor.get("body")
	if not is_instance_valid(body):
		return

	# Apply force at attachment point if available
	var ap: String = anchor.get("attach_point", "")
	if ap != "" and "_attach_forces" in body:
		if not body._attach_forces.has(ap):
			body._attach_forces[ap] = Vector2.ZERO
		body._attach_forces[ap] += force * 60.0  # Scale for per-frame accumulation

	# Apply to body velocity directly — strong enough to counteract balloons/gravity
	if "velocity" in body:
		body.velocity += force * TETHER_PULL_DAMPING
		# Hard clamp: if force is pulling down (tether to floor) and body is moving up, kill upward velocity
		if force.y > 0 and body.velocity.y < 0:
			body.velocity.y *= 0.5  # Dampen upward movement when tether pulls down


func _check_projectile_hits(pos_a: Vector2, pos_b: Vector2) -> void:
	for proj in get_tree().get_nodes_in_group("loose_items"):
		if not proj is Node2D:
			continue
		var proj_pos: Vector2 = proj.global_position
		var dist: float = _point_to_segment_distance(proj_pos, pos_a, pos_b)
		if dist < TETHER_HIT_RADIUS:
			var dmg: int = 5
			if "damage" in proj:
				dmg = proj.damage
			current_hp -= dmg
			if current_hp <= 0:
				sever()
				return


func _point_to_segment_distance(point: Vector2, seg_a: Vector2, seg_b: Vector2) -> float:
	var ab: Vector2 = seg_b - seg_a
	var ap: Vector2 = point - seg_a
	var ab_len_sq: float = ab.length_squared()
	if ab_len_sq < 0.01:
		return ap.length()
	var t: float = clampf(ap.dot(ab) / ab_len_sq, 0.0, 1.0)
	var closest: Vector2 = seg_a + ab * t
	return point.distance_to(closest)


func sever() -> void:
	if _severed:
		return
	_severed = true
	AudioManager.play("grapple_hit", -4.0, 2.0)

	# Detach from attachment systems
	for anchor in [anchor_a, anchor_b]:
		var ap: String = anchor.get("attach_point", "")
		if not anchor.get("is_wall", false) and is_instance_valid(anchor.get("body")) and ap != "":
			if anchor["body"].has_method("detach_item"):
				anchor["body"].detach_item(ap, self)

	# Hide and stop processing immediately, then defer free.
	# Hiding removes us from the renderer's canvas batch list.
	hide()
	set_physics_process(false)
	set_process(false)
	queue_free()


func get_tension() -> float:
	var pos_a: Vector2 = get_anchor_world_pos(anchor_a)
	var pos_b: Vector2 = get_anchor_world_pos(anchor_b)
	var dist: float = pos_a.distance_to(pos_b)
	if dist <= target_length:
		return 0.0
	return (dist - target_length) / target_length


func _compute_rope_points(pos_a: Vector2, pos_b: Vector2, dist: float) -> void:
	_rope_points.clear()
	var slack: float = maxf(0.0, target_length - dist)
	var sag_amount: float = slack * 0.3

	for i in range(ROPE_SEGMENTS + 1):
		var t: float = float(i) / float(ROPE_SEGMENTS)
		var pt: Vector2 = pos_a.lerp(pos_b, t)
		pt.y += sin(t * PI) * sag_amount
		_rope_points.append(pt)


func _get_creature_scale(anchor: Dictionary) -> float:
	## Get creature_scale from the anchor's body, defaulting to 1.0.
	var body: Node2D = anchor.get("body")
	if is_instance_valid(body) and "creature_scale" in body:
		return body.creature_scale
	return 1.0


func _draw() -> void:
	if _severed or _rope_points.size() < 2:
		return

	# Rope thickness scales with creature size
	var cs: float = maxf(_get_creature_scale(anchor_a), _get_creature_scale(anchor_b))

	var tension: float = get_tension()
	var hp_ratio: float = float(current_hp) / float(TETHER_MAX_HP)
	var rope_color: Color
	if tension < 0.01:
		rope_color = Color(0.4, 0.35, 0.3, 0.6)
	elif tension < 0.5:
		rope_color = Color(0.5, 0.4, 0.3, 0.8)
	else:
		rope_color = Color(0.8, 0.3, 0.2, 0.9)

	if hp_ratio < 0.5:
		rope_color = rope_color.lerp(Color(1.0, 0.2, 0.1, 0.9), 1.0 - hp_ratio * 2.0)

	var width: float = (2.0 if tension < 0.3 else 2.5) * cs

	for i in range(_rope_points.size() - 1):
		var a: Vector2 = _rope_points[i] - global_position
		var b: Vector2 = _rope_points[i + 1] - global_position
		if hp_ratio < 0.5:
			var fray: float = (1.0 - hp_ratio * 2.0) * 3.0 * cs
			a += Vector2(randf_range(-fray, fray), randf_range(-fray, fray))
			b += Vector2(randf_range(-fray, fray), randf_range(-fray, fray))
		draw_line(a, b, rope_color, width)

	var hook_color := Color(0.6, 0.5, 0.35, 0.8)
	draw_circle(_rope_points[0] - global_position, 3.0 * cs, hook_color)
	draw_circle(_rope_points[_rope_points.size() - 1] - global_position, 3.0 * cs, hook_color)
