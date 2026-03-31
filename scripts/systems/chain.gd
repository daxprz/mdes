extends Node2D

## Chain — rigid fixed-length connection between two anchor points.
## FABRIK constraint solving — each link is an exact fixed-length rigid rod.
## Flexible (links rotate freely) but NEVER stretches or compresses.
## Verlet integration for gravity/momentum, FABRIK for rigid link enforcement.
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
var chain_damping: float = 0.85   # Velocity retention per frame (0.85=dampened, 0.99=free-swinging)
var chain_gravity: float = 600.0  # Sag strength (px/s²)
var current_hp: int = CHAIN_MAX_HP
var _severed: bool = false
var _owner_index: int = -1

# Config stack — standard entity interface for chain physics tuning
var entity_id: String = "chain"
var _config_stack: Array = []
var _base_config: Variant = null

const DEFAULT_CONFIG := {
	"damping": 0.85,
	"gravity": 600.0,
	"link_length": 8.0,
	"max_hp": 200.0,
}

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
	_base_config = MCP.load_class_defaults("chain")
	if not _base_config:
		_base_config = MCP.DictProvider.new(DEFAULT_CONFIG, "chain_defaults")
	_config_stack = [_base_config]

# -- Chain segment positions (Jakobsen constraint) -----------------------------

var _points: PackedVector2Array = PackedVector2Array()  # Current world positions
var _prev_points: PackedVector2Array = PackedVector2Array()  # Previous frame positions (for Verlet)
var _point_count: int = 0
var _link_len: float = 8.0        # Actual length per segment

# -- Tension feedback ----------------------------------------------------------
# After FABRIK solving, these report where the chain WANTS each endpoint to be.
# If an endpoint is free-moving (ball/shackle), it should read these to get
# the chain-constrained position instead of computing its own constraint.

var tension_pos_a: Vector2 = Vector2.ZERO  # Where chain wants anchor A to be
var tension_pos_b: Vector2 = Vector2.ZERO  # Where chain wants anchor B to be
var is_taut: bool = false                   # True when chain is at full extension

# -- Debug logging (throttled) -------------------------------------------------

var _debug_log_timer: float = 0.0
const DEBUG_LOG_INTERVAL := 0.5  # Log every 0.5 seconds, not every frame

var _glow_node: Node2D = null  # Child node for selection glow, renders behind chain

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
	_init_config()
	add_to_group("entities")
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


func _update_chain_length() -> void:
	## Recalculate link length and add/remove points when target_length changes.
	## Points are added/removed at the anchor_a end (player end — chain reels in/out from player).
	var desired_count: int = clampi(int(ceil(target_length / CHAIN_LINK_LENGTH)) + 1, 3, 100)
	var pos_a: Vector2 = _get_anchor_world_pos(anchor_a)

	if desired_count > _point_count:
		# Chain got longer — add points at anchor_a end (index 0)
		var to_add: int = desired_count - _point_count
		for _i in range(to_add):
			_points.insert(0, pos_a)
			_prev_points.insert(0, pos_a)
		_point_count = desired_count
	elif desired_count < _point_count:
		# Chain got shorter — remove points from anchor_a end (index 0)
		var to_remove: int = _point_count - desired_count
		for _i in range(to_remove):
			if _points.size() > 3:
				_points.remove_at(0)
				_prev_points.remove_at(0)
		_point_count = _points.size()

	# Recalculate link length for the new target
	_link_len = target_length / float(maxi(_point_count - 1, 1))


func _physics_process(delta: float) -> void:
	if _severed:
		return

	# Update chain geometry if target_length was changed externally
	var expected_count: int = clampi(int(ceil(target_length / CHAIN_LINK_LENGTH)) + 1, 3, 100)
	if expected_count != _point_count:
		_update_chain_length()
	else:
		# Even if point count unchanged, recalc link_len for smooth adjustment
		_link_len = target_length / float(maxi(_point_count - 1, 1))

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
	var gravity := Vector2(0, cfg("gravity", chain_gravity))
	var damping: float = cfg("damping", chain_damping)
	for i in range(1, _point_count - 1):
		var current: Vector2 = _points[i]
		var prev: Vector2 = _prev_points[i]
		var vel: Vector2 = (current - prev) * damping
		_prev_points[i] = current
		_points[i] = current + vel + gravity * delta * delta

	# Surface collision: push points out of world geometry
	_collide_with_surfaces()

	# FABRIK constraint solving — enforces EXACT rigid link lengths.
	# The chain is flexible (links can rotate freely) but each link is a fixed
	# length rod. No stretching, no compression. Two alternating passes pin each
	# endpoint and propagate exact distances through the chain.
	var total_chain_len: float = _link_len * float(_point_count - 1)
	var anchor_dist: float = pos_a.distance_to(pos_b)

	# Always use FABRIK + gravity + collision. Even when taut, the chain should
	# sag under gravity and drape around geometry. A straight line is only correct
	# if the tension vastly exceeds gravity (which we don't model — real chains sag).
	if true:
		# Chain has slack — FABRIK drapes it naturally with rigid links.
		# Surface collision is applied between iterations so the chain wraps
		# around platforms and walls instead of passing through them.
		var fabrik_iterations: int = clampi(_point_count / 2, 3, 8)
		for _pass in range(fabrik_iterations):
			# Forward pass: pin A, place each successive point at exactly
			# _link_len from the previous, in the direction of its current position
			_points[0] = pos_a
			for i in range(1, _point_count):
				var dir: Vector2 = _points[i] - _points[i - 1]
				var dist: float = dir.length()
				if dist < 0.001:
					dir = Vector2(0, 1)
					dist = 0.001
				_points[i] = _points[i - 1] + (dir / dist) * _link_len

			# Backward pass: pin B, place each point backward at exactly _link_len
			_points[_point_count - 1] = pos_b
			for i in range(_point_count - 2, -1, -1):
				var dir: Vector2 = _points[i] - _points[i + 1]
				var dist: float = dir.length()
				if dist < 0.001:
					dir = Vector2(0, -1)
					dist = 0.001
				_points[i] = _points[i + 1] + (dir / dist) * _link_len

			# Collide every other iteration to save raycasts
			if _pass % 2 == 0:
				_collide_with_surfaces()

	# Final pin: endpoints are exactly at anchors
	_points[0] = pos_a
	_points[_point_count - 1] = pos_b

	# Re-apply surface collision after constraints (may have pushed points inside)
	_collide_with_surfaces()

	# Tension feedback: after FABRIK solving, report where the chain pulls each endpoint.
	# The first interior point from each end gives the tension direction.
	# If an anchor is free-moving, it should follow this position.
	is_taut = anchor_dist >= total_chain_len * 0.98
	if _point_count >= 3:
		# tension_pos_a = where anchor A would be if it followed the chain
		# (i.e., one link_len from point[1] toward point[0])
		tension_pos_a = _points[1] + (_points[0] - _points[1]).normalized() * _link_len
		tension_pos_b = _points[_point_count - 2] + (_points[_point_count - 1] - _points[_point_count - 2]).normalized() * _link_len
	else:
		tension_pos_a = pos_a
		tension_pos_b = pos_b

	# Check for projectile hits and melee attacks
	_check_projectile_hits()
	_check_melee_hits()

	# Throttled debug logging
	_debug_log_timer -= delta
	if _debug_log_timer <= 0 and DebugOverlay.should_log("chain/link_state", self) != DebugOverlay.TextMode.NONE:
		_debug_log_timer = DEBUG_LOG_INTERVAL
		_log_chain_state(pos_a, pos_b, anchor_dist, total_chain_len)

	# Shake decay
	if _shake_timer > 0:
		_shake_timer -= delta

	queue_redraw()


func _collide_with_surfaces() -> void:
	## Chain collision with world geometry. Only checks every 4th link for
	## performance — FABRIK propagates corrections to neighbors each iteration.
	## Endpoints and the midpoint are always checked.
	var space := get_world_2d().direct_space_state
	if not space:
		return
	var mid: int = _point_count / 2

	# Pass 1: Segment collision — raycast along every 4th link to catch pass-through
	for i in range(0, _point_count - 1, 4):
		var p1: Vector2 = _points[i]
		var p2: Vector2 = _points[mini(i + 4, _point_count - 1)]
		if p1.distance_squared_to(p2) < 1.0:
			continue
		var query := PhysicsRayQueryParameters2D.create(p1, p2, 1)
		var result: Dictionary = space.intersect_ray(query)
		if result:
			var hit_pos: Vector2 = result["position"]
			var normal: Vector2 = result["normal"]
			# Push the nearest interior point to the surface
			var push_i: int = clampi(i + 2, 1, _point_count - 2)
			_points[push_i] = hit_pos + normal * 2.0
			if push_i < _prev_points.size():
				_prev_points[push_i] = _points[push_i]

	# Pass 2: Point probe — only every 4th point + endpoints + midpoint
	for i in range(1, _point_count - 1):
		if i != mid and i % 4 != 0:
			continue
		_collide_point(i, space)


func _collide_point(i: int, space: PhysicsDirectSpaceState2D) -> void:
	## Push a single chain point out of world geometry (4-direction probe).
	var pt: Vector2 = _points[i]

	# Down (floor)
	var query := PhysicsRayQueryParameters2D.create(pt + Vector2(0, -3), pt + Vector2(0, 5), 1)
	var result: Dictionary = space.intersect_ray(query)
	if result:
		_points[i].y = result["position"].y - 1.0
		if i < _prev_points.size():
			_prev_points[i].y = _points[i].y
			_prev_points[i].x = lerpf(_prev_points[i].x, _points[i].x, 0.1)
		return

	# Up (ceiling)
	query = PhysicsRayQueryParameters2D.create(pt + Vector2(0, 3), pt + Vector2(0, -5), 1)
	result = space.intersect_ray(query)
	if result:
		_points[i].y = result["position"].y + 1.0
		if i < _prev_points.size():
			_prev_points[i].y = _points[i].y
		return

	# Left (wall)
	query = PhysicsRayQueryParameters2D.create(pt + Vector2(3, 0), pt + Vector2(-5, 0), 1)
	result = space.intersect_ray(query)
	if result:
		_points[i].x = result["position"].x + 1.0
		if i < _prev_points.size():
			_prev_points[i].x = _points[i].x
		return

	# Right (wall)
	query = PhysicsRayQueryParameters2D.create(pt + Vector2(-3, 0), pt + Vector2(5, 0), 1)
	result = space.intersect_ray(query)
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


func _check_melee_hits() -> void:
	## Check if any player's active attack area overlaps the chain segments.
	## Players deal damage to chains with all weapon types.
	for player in get_tree().get_nodes_in_group("players"):
		if not player is CharacterBody2D:
			continue
		# Check if the player's attack area is actively monitoring (mid-attack)
		if not "attack_area" in player:
			continue
		var area: Area2D = player.attack_area
		if not area.monitoring:
			continue
		# Get attack area world position
		var area_pos: Vector2 = player.global_position + area.position
		# Check proximity to each chain segment
		for i in range(_point_count - 1):
			var dist: float = _point_to_segment_distance(area_pos, _points[i], _points[i + 1])
			if dist < CHAIN_HIT_RADIUS + 12.0:  # 12 = roughly half the attack shape width
				var dmg: int = 8  # Melee hits are stronger than projectile grazes
				current_hp -= dmg
				_shake_timer = 0.3
				_shake_intensity = 2.0
				AudioManager.play("grapple_hit", -6.0, 1.2)
				if current_hp <= 0:
					sever()
					return
				return  # One hit per frame per player


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
	# Manage selection glow node — renders behind chain (z_index = -1)
	var is_selected: bool = DebugOverlay.global_enabled and \
		is_instance_valid(PlayerHUD.debug_selected_enemy) and \
		PlayerHUD.debug_selected_enemy == self
	if is_selected:
		if not _glow_node or not is_instance_valid(_glow_node):
			_glow_node = Node2D.new()
			_glow_node.z_index = -1  # Behind the chain
			_glow_node.draw.connect(_draw_selection_glow)
			add_child(_glow_node)
		_glow_node.visible = true
		_glow_node.queue_redraw()
	elif _glow_node and is_instance_valid(_glow_node):
		_glow_node.visible = false

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


func _draw_selection_glow() -> void:
	## Draw pulsing blue aura behind the chain — single continuous polyline.
	if _points.size() < 2:
		return
	var cs: float = maxf(_get_creature_scale(anchor_a), _get_creature_scale(anchor_b))
	var pulse: float = 0.25 + 0.2 * sin(Time.get_ticks_msec() / 200.0)
	var glow_col := Color(0.3, 0.7, 1.0, pulse)
	# Build local-space polyline
	var local_points: PackedVector2Array = PackedVector2Array()
	local_points.resize(_points.size())
	for i in range(_points.size()):
		local_points[i] = _points[i] - global_position
	_glow_node.draw_polyline(local_points, glow_col, 12.0 * cs)


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


func _log_chain_state(pos_a: Vector2, pos_b: Vector2, anchor_dist: float, total_len: float) -> void:
	## Throttled chain state log — prints link positions, taut/slack, tension direction.
	var state_str: String = "TAUT" if is_taut else "SLACK"
	var slack_pct: float = 100.0 * (1.0 - anchor_dist / maxf(total_len, 1.0)) if not is_taut else 0.0

	# Sample a few points along the chain to show shape (not all — too verbose)
	var sample_count: int = mini(5, _point_count)
	var samples: String = ""
	for i in range(sample_count):
		var idx: int = int(float(i) / float(sample_count - 1) * float(_point_count - 1)) if sample_count > 1 else 0
		var p: Vector2 = _points[idx]
		samples += "(%.0f,%.0f) " % [p.x, p.y]

	# Compute chain curvature — how far the midpoint deviates from the straight line
	var mid_idx: int = _point_count / 2
	var mid_point: Vector2 = _points[mid_idx]
	var straight_mid: Vector2 = pos_a.lerp(pos_b, 0.5)
	var sag: float = mid_point.distance_to(straight_mid)

	# Tension direction at each end
	var tension_dir_a: Vector2 = (_points[1] - _points[0]).normalized() if _point_count >= 2 else Vector2.ZERO
	var tension_dir_b: Vector2 = (_points[_point_count - 2] - _points[_point_count - 1]).normalized() if _point_count >= 2 else Vector2.ZERO

	DebugOverlay.log("chain/link_state", self,
		"CHAIN %s: links=%d len=%.0f dist=%.0f slack=%.0f%% sag=%.1f tense_a=(%.2f,%.2f) tense_b=(%.2f,%.2f) pts=[%s]",
		[state_str, _point_count, total_len, anchor_dist, slack_pct, sag,
		 tension_dir_a.x, tension_dir_a.y, tension_dir_b.x, tension_dir_b.y, samples.strip_edges()])
