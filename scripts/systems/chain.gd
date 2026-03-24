extends Node2D

## Chain — rigid fixed-length connection between two anchor points.
## Position-based constraint solving (Jakobsen method) — no RigidBody2D.
## Zero stretch: hard position correction every frame.
## Visually rendered as alternating thin/thick dark grey segments.
## Shackles at creature end, peg+ring at wall end.

# -- Configurable Constants ----------------------------------------------------

const CHAIN_LINK_LENGTH := 8.0     # Visual/physics segment length (configurable)
const CHAIN_MAX_HP := 200
const CHAIN_HIT_RADIUS := 10.0    # Proximity for projectile damage
const CHAIN_MIN_LEN := 10.0
const CHAIN_MAX_LEN := 900.0
const WALL_MASS := 99999.0

# -- Anchor data (same format as tether) ---------------------------------------

var anchor_a: Dictionary = {}
var anchor_b: Dictionary = {}
var target_length: float = 200.0
var current_hp: int = CHAIN_MAX_HP
var _severed: bool = false
var _owner_index: int = -1

# -- Chain segment positions (Jakobsen constraint) -----------------------------

var _points: PackedVector2Array = PackedVector2Array()  # Current world positions
var _prev_points: PackedVector2Array = PackedVector2Array()  # Previous frame positions (for Verlet)
var _point_count: int = 0
var _link_len: float = 8.0        # Actual length per segment

# -- Shake feedback ------------------------------------------------------------

var _shake_timer: float = 0.0
var _shake_intensity: float = 0.0


static func make_anchor_wall(world_pos: Vector2) -> Dictionary:
	return { "pos": world_pos, "body": null, "body_offset": Vector2.ZERO, "attach_point": "", "is_wall": true }


static func make_anchor_body(body: Node2D, attach_point: String = "", offset: Vector2 = Vector2.ZERO) -> Dictionary:
	return { "pos": Vector2.ZERO, "body": body, "body_offset": offset, "attach_point": attach_point, "is_wall": false }


func _get_anchor_world_pos(anchor: Dictionary) -> Vector2:
	if anchor.get("is_wall", false):
		return anchor.get("pos", Vector2.ZERO)
	var body: Node2D = anchor.get("body")
	if is_instance_valid(body):
		var ap: String = anchor.get("attach_point", "")
		if ap != "" and body.has_method("get_attach_world_position"):
			return body.get_attach_world_position(ap)
		return body.global_position + anchor.get("body_offset", Vector2.ZERO)
	return anchor.get("pos", Vector2.ZERO)


func _get_anchor_mass(anchor: Dictionary) -> float:
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
	add_to_group("tethers")  # Compatible with tether status/cut commands
	add_to_group("chains")
	z_index = 5


func setup(a: Dictionary, b: Dictionary, length: float, owner_idx: int = -1) -> void:
	anchor_a = a
	anchor_b = b
	target_length = clampf(length, CHAIN_MIN_LEN, CHAIN_MAX_LEN)
	_owner_index = owner_idx
	_build_chain()


func _build_chain() -> void:
	## Initialize chain points along the line between anchors.
	var pos_a: Vector2 = _get_anchor_world_pos(anchor_a)
	var pos_b: Vector2 = _get_anchor_world_pos(anchor_b)

	# Calculate number of segments
	_point_count = clampi(int(ceil(target_length / CHAIN_LINK_LENGTH)) + 1, 3, 100)
	_link_len = target_length / float(_point_count - 1)

	# Initialize points along the straight line from A to B
	_points.clear()
	_prev_points.clear()
	for i in range(_point_count):
		var t: float = float(i) / float(_point_count - 1)
		var pt: Vector2 = pos_a.lerp(pos_b, t)
		_points.append(pt)
		_prev_points.append(pt)  # No initial velocity


func _physics_process(delta: float) -> void:
	if _severed:
		return

	# Check anchor validity
	if not anchor_a.get("is_wall", false) and not is_instance_valid(anchor_a.get("body")):
		sever()
		return
	if not anchor_b.get("is_wall", false) and not is_instance_valid(anchor_b.get("body")):
		sever()
		return

	var pos_a: Vector2 = _get_anchor_world_pos(anchor_a)
	var pos_b: Vector2 = _get_anchor_world_pos(anchor_b)

	# Pin endpoints to anchors
	_points[0] = pos_a
	_points[_point_count - 1] = pos_b
	_prev_points[0] = pos_a
	_prev_points[_point_count - 1] = pos_b

	# Verlet integration: position-based physics with implicit velocity
	var gravity := Vector2(0, 600.0)  # Match game gravity
	var damping: float = 0.99  # Slight damping to reduce oscillation
	for i in range(1, _point_count - 1):
		var current: Vector2 = _points[i]
		var prev: Vector2 = _prev_points[i]
		var velocity: Vector2 = (current - prev) * damping
		_prev_points[i] = current
		_points[i] = current + velocity + gravity * delta * delta

	# Surface collision: push points out of world geometry
	_collide_with_surfaces()

	# Jakobsen constraint solving: enforce fixed distances
	# Iterations scale with chain length for convergence
	var iterations: int = clampi(_point_count * 2, 20, 100)
	for _pass in range(iterations):
		# Pin endpoints every pass
		_points[0] = pos_a
		_points[_point_count - 1] = pos_b
		# Correct all consecutive pairs
		for i in range(_point_count - 1):
			var p1: Vector2 = _points[i]
			var p2: Vector2 = _points[i + 1]
			var dir: Vector2 = p2 - p1
			var dist: float = dir.length()
			if dist < 0.001:
				dir = Vector2(0, 1)
				dist = 0.001
			var diff: float = (dist - _link_len) / dist
			var offset: Vector2 = dir * diff * 0.5
			# Don't move pinned endpoints
			if i > 0:
				_points[i] += offset
			if i + 1 < _point_count - 1:
				_points[i + 1] -= offset

	# Re-apply surface collision after constraints (may have pushed points inside)
	_collide_with_surfaces()

	# Check for projectile hits
	_check_projectile_hits()

	# Shake decay
	if _shake_timer > 0:
		_shake_timer -= delta

	queue_redraw()


func _collide_with_surfaces() -> void:
	## For each intermediate chain point, check if it's inside world geometry.
	## If so, push it to the nearest surface. Uses short raycasts in 4 directions.
	var space := get_world_2d().direct_space_state
	if not space:
		return

	for i in range(1, _point_count - 1):
		var pt: Vector2 = _points[i]

		# Raycast downward — most common collision (chain resting on platform)
		var query_down := PhysicsRayQueryParameters2D.create(
			pt + Vector2(0, -2), pt + Vector2(0, 4), 1  # World layer only
		)
		var result: Dictionary = space.intersect_ray(query_down)
		if result:
			# Point is at or below a surface — push it up
			_points[i].y = result["position"].y - 1.0
			# Kill downward velocity (friction)
			if i < _prev_points.size():
				_prev_points[i].y = _points[i].y
				# Add friction to horizontal movement on surfaces
				_prev_points[i].x = lerpf(_prev_points[i].x, _points[i].x, 0.1)
			continue

		# Raycast upward — ceiling collision
		var query_up := PhysicsRayQueryParameters2D.create(
			pt + Vector2(0, 2), pt + Vector2(0, -4), 1
		)
		result = space.intersect_ray(query_up)
		if result:
			_points[i].y = result["position"].y + 1.0
			if i < _prev_points.size():
				_prev_points[i].y = _points[i].y
			continue

		# Raycast left — wall collision
		var query_left := PhysicsRayQueryParameters2D.create(
			pt + Vector2(2, 0), pt + Vector2(-4, 0), 1
		)
		result = space.intersect_ray(query_left)
		if result:
			_points[i].x = result["position"].x + 1.0
			if i < _prev_points.size():
				_prev_points[i].x = _points[i].x
			continue

		# Raycast right — wall collision
		var query_right := PhysicsRayQueryParameters2D.create(
			pt + Vector2(-2, 0), pt + Vector2(4, 0), 1
		)
		result = space.intersect_ray(query_right)
		if result:
			_points[i].x = result["position"].x - 1.0
			if i < _prev_points.size():
				_prev_points[i].x = _points[i].x


func _check_projectile_hits() -> void:
	## Check projectile proximity to chain segments and deal damage.
	for proj in get_tree().get_nodes_in_group("loose_items"):
		if not proj is Node2D:
			continue
		var proj_pos: Vector2 = proj.global_position
		for i in range(_point_count - 1):
			var dist: float = _point_to_segment_distance(proj_pos, _points[i], _points[i + 1])
			if dist < CHAIN_HIT_RADIUS:
				var dmg: int = 3
				if "damage" in proj:
					dmg = mini(proj.damage, 5)
				current_hp -= dmg
				_shake_timer = 0.4
				_shake_intensity = clampf(float(dmg) / 3.0, 1.0, 3.0)
				AudioManager.play("grapple_hit", -8.0, 1.5)
				if current_hp <= 0:
					sever()
					return
				break


func _point_to_segment_distance(point: Vector2, seg_a: Vector2, seg_b: Vector2) -> float:
	var ab: Vector2 = seg_b - seg_a
	var ap: Vector2 = point - seg_a
	var ab_len_sq: float = ab.length_squared()
	if ab_len_sq < 0.01:
		return ap.length()
	var t: float = clampf(ap.dot(ab) / ab_len_sq, 0.0, 1.0)
	return point.distance_to(seg_a + ab * t)


func sever() -> void:
	if _severed:
		return
	_severed = true
	AudioManager.play("grapple_hit", 0.0, 0.5)
	for anchor in [anchor_a, anchor_b]:
		var ap: String = anchor.get("attach_point", "")
		if not anchor.get("is_wall", false) and is_instance_valid(anchor.get("body")) and ap != "":
			if anchor["body"].has_method("detach_item"):
				anchor["body"].detach_item(ap, self)
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)


func get_tension() -> float:
	var pos_a: Vector2 = _get_anchor_world_pos(anchor_a)
	var pos_b: Vector2 = _get_anchor_world_pos(anchor_b)
	var dist: float = pos_a.distance_to(pos_b)
	if dist <= target_length:
		return 0.0
	return (dist - target_length) / target_length


func _draw() -> void:
	if _points.size() < 2:
		return

	var hp_ratio: float = float(current_hp) / float(CHAIN_MAX_HP)
	var dark_grey := Color(0.3, 0.28, 0.26, 0.95)
	if hp_ratio < 0.5:
		dark_grey = dark_grey.lerp(Color(0.6, 0.2, 0.15, 0.95), 1.0 - hp_ratio * 2.0)

	var shaking: bool = _shake_timer > 0

	# Chain link thickness scales with creature size
	var cs: float = maxf(_get_creature_scale(anchor_a), _get_creature_scale(anchor_b))

	# Draw alternating thin/thick segments
	for i in range(_points.size() - 1):
		var p1: Vector2 = _points[i] - global_position
		var p2: Vector2 = _points[i + 1] - global_position
		if shaking:
			var t: float = float(i) / float(_points.size() - 1)
			var shake_amt: float = sin(t * PI) * _shake_intensity * _shake_timer * 15.0
			var seg_dir: Vector2 = (p2 - p1).normalized()
			var perp: Vector2 = Vector2(-seg_dir.y, seg_dir.x)
			var offset: Vector2 = perp * sin(Time.get_ticks_msec() * 0.05 + i * 2.0) * shake_amt
			p1 += offset
			p2 += offset
		var draw_col: Color = dark_grey
		if shaking and _shake_timer > 0.3:
			draw_col = dark_grey.lerp(Color(0.9, 0.9, 0.8, 1.0), (_shake_timer - 0.3) * 10.0)
		var width: float = (4.0 if i % 2 == 0 else 2.0) * cs
		draw_line(p1, p2, draw_col, width)

	# Anchor hardware
	_draw_anchor_hardware(anchor_a, _points[0])
	_draw_anchor_hardware(anchor_b, _points[_points.size() - 1])


func _get_creature_scale(anchor: Dictionary) -> float:
	## Get creature_scale from the anchor's body, defaulting to 1.0.
	var body: Node2D = anchor.get("body")
	if is_instance_valid(body) and "creature_scale" in body:
		return body.creature_scale
	return 1.0


func _draw_anchor_hardware(anchor: Dictionary, world_pos: Vector2) -> void:
	var chain_col := Color(0.3, 0.28, 0.26, 0.95)
	var local_pos: Vector2 = world_pos - global_position
	var cs: float = _get_creature_scale(anchor)
	if anchor.get("is_wall", false):
		# Peg + ring — scale with the OTHER anchor's creature
		var other: Dictionary = anchor_b if anchor == anchor_a else anchor_a
		cs = _get_creature_scale(other)
		draw_line(local_pos, local_pos + Vector2(0, -10 * cs), chain_col, 4.0 * cs)
		draw_arc(local_pos, 5.0 * cs, 0, TAU, 12, chain_col, 2.0 * cs)
	else:
		# Shackle — solid rectangle at attachment point, scaled to creature
		var body: Node2D = anchor.get("body")
		var draw_pos: Vector2 = local_pos
		if is_instance_valid(body):
			var ap: String = anchor.get("attach_point", "")
			if ap != "" and "_attach_points" in body and body._attach_points.has(ap):
				draw_pos = body.global_position + body._attach_points[ap].position - global_position
		var limb_w: float = _get_limb_width(anchor) * cs
		var hw: float = limb_w * 0.5 + 2.0 * cs
		var hh: float = hw * 0.6
		draw_rect(Rect2(draw_pos.x - hw, draw_pos.y - hh, hw * 2, hh * 2), chain_col)


func _get_limb_width(anchor: Dictionary) -> float:
	## Base limb width at scale 1.0 — caller multiplies by creature_scale.
	var ap: String = anchor.get("attach_point", "")
	match ap:
		"head": return 14.0
		"shoulders": return 12.0
		"waist": return 11.0
		"tail_tip": return 4.0
		"elbow_l", "elbow_r": return 6.0
		"knee_l", "knee_r": return 6.0
	return 8.0
