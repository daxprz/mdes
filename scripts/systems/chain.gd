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

var _link_points: PackedVector2Array = PackedVector2Array()


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

	# ZERO stretch: hard constraint — if distance exceeds target, snap back immediately
	if dist > target_length and dist > 0.1:
		var over: float = dist - target_length
		var direction: Vector2 = (pos_b - pos_a).normalized()

		# Force proportional to overshoot — much stronger than tether
		var force_magnitude: float = CHAIN_PULL_FORCE * (over / target_length)

		var mass_a: float = _get_anchor_mass(anchor_a)
		var mass_b: float = _get_anchor_mass(anchor_b)
		var total_mass: float = mass_a + mass_b
		var ratio_a: float = mass_b / total_mass
		var ratio_b: float = mass_a / total_mass

		if not anchor_a.get("is_wall", false) and is_instance_valid(anchor_a.get("body")):
			_apply_force(anchor_a, direction * force_magnitude * ratio_a * delta)
		if not anchor_b.get("is_wall", false) and is_instance_valid(anchor_b.get("body")):
			_apply_force(anchor_b, -direction * force_magnitude * ratio_b * delta)

		# Hard position correction: directly snap bodies toward target length
		if over > 1.0:
			var correction: Vector2 = direction * over
			if not anchor_a.get("is_wall", false) and is_instance_valid(anchor_a.get("body")):
				anchor_a["body"].global_position += correction * ratio_a * 0.5
			if not anchor_b.get("is_wall", false) and is_instance_valid(anchor_b.get("body")):
				anchor_b["body"].global_position -= correction * ratio_b * 0.5

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


func _compute_link_points(pos_a: Vector2, pos_b: Vector2, dist: float) -> void:
	_link_points.clear()
	for i in range(LINK_COUNT + 1):
		var t: float = float(i) / float(LINK_COUNT)
		var pt: Vector2 = pos_a.lerp(pos_b, t)
		# Minimal sag — chains are rigid, just a tiny droop
		var sag: float = maxf(0.0, target_length - dist) * 0.15
		pt.y += sin(t * PI) * sag
		_link_points.append(pt)


func _draw() -> void:
	if _link_points.size() < 2:
		return

	var tension: float = get_tension()
	var hp_ratio: float = float(current_hp) / float(CHAIN_MAX_HP)

	# Chain color: dark metallic grey, reddens when damaged
	var chain_color := Color(0.45, 0.42, 0.4, 0.9)
	if hp_ratio < 0.5:
		chain_color = chain_color.lerp(Color(0.8, 0.3, 0.2, 0.9), 1.0 - hp_ratio * 2.0)

	# Draw chain links: alternating horizontal and vertical ovals
	for i in range(_link_points.size() - 1):
		var a: Vector2 = _link_points[i] - global_position
		var b: Vector2 = _link_points[i + 1] - global_position
		var mid: Vector2 = (a + b) / 2.0
		var seg_dir: Vector2 = (b - a).normalized()
		var seg_perp: Vector2 = Vector2(-seg_dir.y, seg_dir.x)

		# Alternating link orientation
		if i % 2 == 0:
			# Horizontal link: short wide oval
			draw_line(mid - seg_dir * 3, mid + seg_dir * 3, chain_color, 3.0)
			draw_line(mid - seg_dir * 3, mid - seg_dir * 3 + seg_perp * 2, chain_color, 1.5)
			draw_line(mid + seg_dir * 3, mid + seg_dir * 3 + seg_perp * 2, chain_color, 1.5)
			draw_line(mid - seg_dir * 3 + seg_perp * 2, mid + seg_dir * 3 + seg_perp * 2, chain_color, 1.5)
		else:
			# Vertical link: tall narrow oval
			draw_line(mid - seg_perp * 2, mid + seg_perp * 2, chain_color, 2.5)

		# Connection between links
		draw_line(a, b, chain_color * Color(1, 1, 1, 0.5), 1.5)

	# Anchor hooks: metallic circles
	var hook_color := Color(0.5, 0.48, 0.45, 0.9)
	draw_circle(_link_points[0] - global_position, 4.0, hook_color)
	draw_circle(_link_points[_link_points.size() - 1] - global_position, 4.0, hook_color)
