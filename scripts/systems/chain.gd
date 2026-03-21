extends Node2D

## Chain — rigid connection between two anchor points.
## Unlike tethers, chains have ZERO stretch (hard constraint) and much higher durability.
## Visually rendered as chain links instead of a rope.

# -- Constants -----------------------------------------------------------------

const CHAIN_PULL_FORCE := 80000.0   # Extremely strong — near-instant correction
const CHAIN_PULL_DAMPING := 0.95    # High damping to prevent oscillation
const CHAIN_MIN_LEN := 10.0
const CHAIN_MAX_LEN := 900.0
const CHAIN_MAX_HP := 2000
const CHAIN_HIT_RADIUS := 6.0      # Slightly harder to hit than rope
const LINK_COUNT := 20              # Visual chain links
const WALL_MASS := 99999.0

# Reuse tether's anchor helpers
var _TetherScript: GDScript = null

# -- State ---------------------------------------------------------------------

var anchor_a: Dictionary = {}
var anchor_b: Dictionary = {}
var target_length: float = 200.0
var current_hp: int = CHAIN_MAX_HP
var _severed: bool = false
var _owner_index: int = -1



func _ready() -> void:
	add_to_group("tethers")  # Same group as tethers for RCON/status/cut
	add_to_group("chains")
	z_index = 5
	_TetherScript = load("res://scripts/systems/tether.gd")


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


func setup(a: Dictionary, b: Dictionary, length: float, owner_idx: int = -1) -> void:
	anchor_a = a
	anchor_b = b
	target_length = clampf(length, CHAIN_MIN_LEN, CHAIN_MAX_LEN)
	_owner_index = owner_idx


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
	var dist: float = pos_a.distance_to(pos_b)

	# ZERO stretch: hard constraint — snap position every frame, no exceptions
	if dist > target_length + 0.5:
		var direction: Vector2 = (pos_b - pos_a).normalized()
		var over: float = dist - target_length

		var mass_a: float = _get_anchor_mass(anchor_a)
		var mass_b: float = _get_anchor_mass(anchor_b)
		var total_mass: float = mass_a + mass_b
		var ratio_a: float = mass_b / total_mass
		var ratio_b: float = mass_a / total_mass

		# Hard position snap — full correction, every frame
		var correction: Vector2 = direction * over
		if not anchor_a.get("is_wall", false) and is_instance_valid(anchor_a.get("body")):
			var body_a: Node2D = anchor_a["body"]
			body_a.global_position += correction * ratio_a
			# Kill velocity component along chain direction
			if "velocity" in body_a:
				var vel_along: float = body_a.velocity.dot(direction)
				if vel_along < 0:  # Moving away from B
					body_a.velocity -= direction * vel_along
		if not anchor_b.get("is_wall", false) and is_instance_valid(anchor_b.get("body")):
			var body_b: Node2D = anchor_b["body"]
			body_b.global_position -= correction * ratio_b
			if "velocity" in body_b:
				var vel_along: float = body_b.velocity.dot(-direction)
				if vel_along < 0:  # Moving away from A
					body_b.velocity += direction * vel_along

	# Check projectile hits
	_check_projectile_hits(pos_a, pos_b)

	# Update visual
	_compute_link_points(pos_a, pos_b, dist)
	queue_redraw()


func _apply_force(anchor: Dictionary, force: Vector2) -> void:
	var body: Node2D = anchor.get("body")
	if not is_instance_valid(body):
		return
	var ap: String = anchor.get("attach_point", "")
	if ap != "" and "_attach_forces" in body:
		if not body._attach_forces.has(ap):
			body._attach_forces[ap] = Vector2.ZERO
		body._attach_forces[ap] += force * 60.0
	if "velocity" in body:
		body.velocity += force * CHAIN_PULL_DAMPING
		if force.y > 0 and body.velocity.y < 0:
			body.velocity.y *= 0.3


func _check_projectile_hits(pos_a: Vector2, pos_b: Vector2) -> void:
	for proj in get_tree().get_nodes_in_group("loose_items"):
		if not proj is Node2D:
			continue
		var dist: float = _point_to_segment_distance(proj.global_position, pos_a, pos_b)
		if dist < CHAIN_HIT_RADIUS:
			var dmg: int = 3  # Chains are harder to damage
			if "damage" in proj:
				dmg = mini(proj.damage, 5)  # Cap damage per hit
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
	return point.distance_to(seg_a + ab * t)


func sever() -> void:
	if _severed:
		return
	_severed = true
	AudioManager.play("grapple_hit", 0.0, 0.5)  # Heavy metallic snap

	for anchor in [anchor_a, anchor_b]:
		var ap: String = anchor.get("attach_point", "")
		if not anchor.get("is_wall", false) and is_instance_valid(anchor.get("body")) and ap != "":
			if anchor["body"].has_method("detach_item"):
				anchor["body"].detach_item(ap, self)

	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.2)
	tween.tween_callback(queue_free)


func get_tension() -> float:
	var pos_a: Vector2 = _get_anchor_world_pos(anchor_a)
	var pos_b: Vector2 = _get_anchor_world_pos(anchor_b)
	var dist: float = pos_a.distance_to(pos_b)
	if dist <= target_length:
		return 0.0
	return (dist - target_length) / target_length


func _draw() -> void:
	var pos_a: Vector2 = _get_anchor_world_pos(anchor_a)
	var pos_b: Vector2 = _get_anchor_world_pos(anchor_b)
	var dist: float = pos_a.distance_to(pos_b)
	if dist < 0.1:
		return

	var hp_ratio: float = float(current_hp) / float(CHAIN_MAX_HP)
	var dark_grey := Color(0.3, 0.28, 0.26, 0.95)
	if hp_ratio < 0.5:
		dark_grey = dark_grey.lerp(Color(0.6, 0.2, 0.15, 0.95), 1.0 - hp_ratio * 2.0)

	var chain_dir: Vector2 = (pos_b - pos_a).normalized()
	var a_local: Vector2 = pos_a - global_position
	var b_local: Vector2 = pos_b - global_position

	# Draw chain as fixed-length segments with catenary sag.
	# Total path length = target_length ALWAYS. Sag increases when endpoints are closer.
	var slack: float = maxf(0.0, target_length - dist)
	var sag_amount: float = slack * 0.4  # Sag proportional to slack

	# Build points along the chain path with sag
	var seg_len: float = target_length / float(LINK_COUNT)
	var chain_points: PackedVector2Array = PackedVector2Array()
	for i in range(LINK_COUNT + 1):
		var t: float = float(i) / float(LINK_COUNT)
		var pt: Vector2 = a_local.lerp(b_local, t)
		# Catenary sag (downward arc)
		pt.y += sin(t * PI) * sag_amount
		chain_points.append(pt)

	# Now enforce that each segment has exactly seg_len length
	# Walk from A, placing each point at seg_len from the previous
	for i in range(1, chain_points.size()):
		var dir: Vector2 = (chain_points[i] - chain_points[i - 1])
		if dir.length() > 0.01:
			chain_points[i] = chain_points[i - 1] + dir.normalized() * seg_len

	# Draw alternating thin/thick segments
	for i in range(chain_points.size() - 1):
		var width: float = 4.0 if i % 2 == 0 else 2.0
		draw_line(chain_points[i], chain_points[i + 1], dark_grey, width)

	# Shackle at creature end — solid filled rectangle in body-local coordinates
	_draw_anchor_hardware(anchor_a, pos_a, dark_grey)
	_draw_anchor_hardware(anchor_b, pos_b, dark_grey)


func _draw_anchor_hardware(anchor: Dictionary, world_pos: Vector2, chain_col: Color) -> void:
	if anchor.get("is_wall", false):
		_draw_wall_mount(world_pos - global_position, chain_col)
	else:
		_draw_shackle(anchor, world_pos, chain_col)


func _draw_shackle(anchor: Dictionary, world_pos: Vector2, chain_col: Color) -> void:
	## Draw a solid rectangle shackle at the body part position, rendered relative to the body.
	var body: Node2D = anchor.get("body")
	if not is_instance_valid(body):
		draw_rect(Rect2((world_pos - global_position) + Vector2(-5, -4), Vector2(10, 8)), chain_col)
		return

	# Get the attachment point position in body-local space
	var ap: String = anchor.get("attach_point", "")
	var local_pos: Vector2 = Vector2.ZERO
	if ap != "" and "_attach_points" in body and body._attach_points.has(ap):
		local_pos = body._attach_points[ap].position

	# Limb width determines shackle size
	var limb_w: float = _get_limb_width(anchor)
	var hw: float = limb_w * 0.5 + 2.0  # Slightly larger than limb
	var hh: float = hw * 0.6

	# Convert to our draw space (body global + local offset - our global)
	var draw_pos: Vector2 = body.global_position + local_pos - global_position
	draw_rect(Rect2(draw_pos.x - hw, draw_pos.y - hh, hw * 2, hh * 2), chain_col)


func _get_limb_width(anchor: Dictionary) -> float:
	var ap: String = anchor.get("attach_point", "")
	match ap:
		"head": return 14.0
		"shoulders": return 12.0
		"waist": return 11.0
		"tail_tip": return 4.0
		"elbow_l", "elbow_r": return 6.0
		"knee_l", "knee_r": return 6.0
	return 8.0


func _draw_wall_mount(pos: Vector2, chain_col: Color) -> void:
	## Peg + ring at wall anchor.
	# Peg
	draw_line(pos, pos + Vector2(0, -10), chain_col, 4.0)
	# Ring
	draw_arc(pos, 5.0, 0, TAU, 12, chain_col, 2.0)
