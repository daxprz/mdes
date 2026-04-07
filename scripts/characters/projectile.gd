extends Area2D

## A projectile that travels in a direction, interacts with surfaces, chains,
## and living targets. Crossbow bolts stick in flesh and ricochet off walls.
##
## Impact rules:
##   Living target  → stick, thunk, blood (proportional to damage)
##   Inanimate obj  → stick, thunk, no blood
##   Chain          → deflect ±5°, lose 30% speed, continue
##   Surface/wall   → angle-dependent: stick (30-90°), bounce (0-30°)

@export var speed: float = 300.0
@export var damage: int = 10
@export var direction: Vector2 = Vector2.RIGHT
@export var lifetime: float = 3.0
@export var owner_index: int = -1

## "crossbow_bolt", "magic_bolt", "muffin_grenade"
var projectile_type: String = "crossbow_bolt"

var _age: float = 0.0
var _launch_speed: float = 0.0  # Recorded at first physics frame; damage scales relative to this

# Arc flight (parabolic trajectory)
var _arc_vel := Vector2.ZERO
var _arc_gravity: float = 0.0
var _is_arc: bool = false

# Impact state
var _stuck: bool = false
var _stuck_parent: Node2D = null
var _stuck_lifetime: float = 10.0  # Fades last 2s, gone at 0

var _blood_emitter: Node2D = null
var _hit := false
var _bounce_count: int = 0
const MAX_BOUNCES := 3  # Prevent infinite ricochets

@onready var sprite: Sprite2D = $Sprite
@onready var collision_shape: CollisionShape2D = $CollisionShape


func _ready() -> void:
	add_to_group("loose_items")
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	sprite.visible = false
	# Set initial rotation to match flight direction
	rotation = direction.angle()


# =============================================================================
# Drawing
# =============================================================================

func _draw() -> void:
	if DebugOverlay.should_draw("player/projectiles", self):
		draw_circle(Vector2.ZERO, 8.0, Color(1.0, 0.0, 0.0, 0.7))
		draw_string(ThemeDB.fallback_font, Vector2(10, 4),
			"(%.0f,%.0f)" % [global_position.x, global_position.y],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)

	var fade: float = 1.0
	if _stuck:
		fade = clampf(_stuck_lifetime / 2.0, 0.0, 1.0)

	match projectile_type:
		"crossbow_bolt":
			# Arrow always drawn along local X axis; rotation handles direction
			var shaft_len: float = 12.0
			var tip := Vector2(shaft_len * 0.5, 0.0)
			var tail := Vector2(-shaft_len * 0.5, 0.0)
			var shaft_color := Color(0.85, 0.75, 0.5, fade)
			draw_line(tail, tip, shaft_color, 1.5)
			# Arrowhead
			var head_color := Color(0.7, 0.7, 0.7, fade)
			draw_polygon(
				PackedVector2Array([tip, tip + Vector2(-4.0, 3.0), tip + Vector2(-4.0, -3.0)]),
				PackedColorArray([head_color, head_color, head_color]))
			# Fletching
			var fletch := tail + Vector2(2.0, 0.0)
			draw_line(fletch + Vector2(0, -2.5), fletch + Vector2(0, 2.5),
				Color(0.6, 0.2, 0.2, fade), 1.0)
		"magic_bolt":
			draw_circle(Vector2.ZERO, 4.0, Color(0.4, 0.6, 1.0, 0.9 * fade))
			draw_circle(Vector2.ZERO, 2.0, Color(0.8, 0.9, 1.0, fade))
		"muffin_grenade":
			draw_circle(Vector2.ZERO, 5.0, Color(0.8, 0.6, 0.3, fade))
			draw_circle(Vector2.ZERO, 3.0, Color(1.0, 0.85, 0.6, fade))
		_:
			draw_circle(Vector2.ZERO, 3.0, Color(1.0, 1.0, 1.0, fade))


# =============================================================================
# Physics
# =============================================================================

func _physics_process(delta: float) -> void:
	_age += delta

	# Record launch speed on first frame
	if _launch_speed == 0.0:
		_launch_speed = _get_speed()

	# -- Stuck state: just tick lifetime and fade --
	if _stuck:
		if _stuck_parent and not is_instance_valid(_stuck_parent):
			queue_free()
			return
		_stuck_lifetime -= delta
		if _stuck_lifetime <= 0.0:
			queue_free()
			return
		modulate.a = clampf(_stuck_lifetime / 2.0, 0.0, 1.0)
		# Update blood emitter source to follow arrowhead
		if _blood_emitter and is_instance_valid(_blood_emitter):
			_blood_emitter.source_pos = global_position
		queue_redraw()
		return

	if _age >= lifetime:
		queue_free()
		return

	# -- Move --
	var old_pos: Vector2 = global_position
	if _is_arc:
		_arc_vel.y += _arc_gravity * delta
		position += _arc_vel * delta
	else:
		position += direction * speed * delta

	# -- Rotate to match flight direction --
	var vel: Vector2 = _get_velocity()
	if vel.length_squared() > 1.0:
		rotation = vel.angle()

	# -- Chain deflection check (manual, chains have no collision bodies) --
	if not _hit:
		_check_chain_deflection(old_pos, global_position)

	# -- Fast-mover raycast for tunneling prevention --
	if not _hit and not _stuck:
		var new_pos: Vector2 = global_position
		var travel: float = old_pos.distance_to(new_pos)
		if travel > 4.0:
			var space_state := get_world_2d().direct_space_state
			var query := PhysicsRayQueryParameters2D.create(old_pos, new_pos, collision_mask)
			query.collide_with_bodies = true
			query.collide_with_areas = true
			query.exclude = [get_rid()]
			var result := space_state.intersect_ray(query)
			if result:
				global_position = result.position
				var collider: Object = result.collider
				if collider is Node2D:
					var normal: Vector2 = result.normal
					_handle_impact(collider as Node2D, normal)

	queue_redraw()

	DebugOverlay.log("player/projectiles", self,
		"%s pos=(%.0f,%.0f) spd=%.0f age=%.2f bounces=%d",
		[projectile_type, global_position.x, global_position.y,
		_get_speed(), _age, _bounce_count])


# =============================================================================
# Velocity helpers
# =============================================================================

func _get_velocity() -> Vector2:
	if _is_arc:
		return _arc_vel
	return direction * speed


func _get_speed() -> float:
	if _is_arc:
		return _arc_vel.length()
	return speed


func _effective_damage() -> int:
	## Damage scaled by current speed relative to launch speed.
	## Full speed = full damage. Half speed = half damage. Stopped = 0.
	if _launch_speed < 1.0:
		return 0
	var ratio: float = clampf(_get_speed() / _launch_speed, 0.0, 1.0)
	return maxi(1, roundi(float(damage) * ratio)) if ratio > 0.05 else 0


func _set_velocity(vel: Vector2) -> void:
	## Update both direction+speed (linear) and _arc_vel (arc) to match.
	if _is_arc:
		_arc_vel = vel
	else:
		var spd: float = vel.length()
		if spd > 0.01:
			direction = vel / spd
			speed = spd
		else:
			speed = 0.0


# =============================================================================
# Impact classification
# =============================================================================

func _body_is_living(body: Node2D) -> bool:
	## Returns true if the body is a living creature that bleeds.
	if body.is_in_group("enemies"):
		return true
	if body.is_in_group("players"):
		return true
	if body.has_meta("bleeds") and body.get_meta("bleeds"):
		return true
	return false


func _body_is_surface(body: Node2D) -> bool:
	## Returns true if this is static world geometry (walls, floors, platforms).
	# Layer 1 = world. If body is on layer 1 and not a character, it's a surface.
	if body.get("collision_layer") != null:
		return (body.collision_layer & 1) != 0
	return false


# =============================================================================
# Impact handling
# =============================================================================

func _handle_impact(body: Node2D, normal: Vector2) -> void:
	## Central impact handler. Classifies the target and reacts accordingly.
	if _hit and _stuck:
		return

	# -- Living creature: damage + stick + blood --
	if _body_is_living(body):
		_impact_living(body)
		return

	# -- Surface/wall: angle-dependent stick or bounce --
	if _body_is_surface(body) and normal.length() > 0.1:
		_impact_surface(body, normal)
		return

	# -- Inanimate object (dummy, prop): damage + stick, no blood --
	_impact_inanimate(body)


func _impact_living(body: Node2D) -> void:
	## Hit a living creature: deal damage, stick, bleed.
	if _hit:
		return
	_hit = true

	# Damage proportional to current speed vs launch speed
	var eff_dmg: int = _effective_damage()
	if body.has_method("take_part_damage") and "_hitboxes" in body:
		var best_part: String = "body"
		var best_dist: float = 999.0
		for part_name in body._hitboxes:
			var hitbox: Area2D = body._hitboxes[part_name]
			var hitbox_world: Vector2 = body.global_position + hitbox.position
			var d: float = global_position.distance_to(hitbox_world)
			if d < best_dist:
				best_dist = d
				best_part = part_name
		body.take_part_damage(best_part, eff_dmg, owner_index)
	elif body.has_method("take_damage"):
		body.take_damage(eff_dmg, owner_index)

	_apply_impact_force(body)
	_spawn_damage_number(eff_dmg)
	if projectile_type == "muffin_grenade":
		_explode()
	else:
		_stick_to(body)
		if eff_dmg > 0:
			_spawn_blood_emitter(eff_dmg)

	DebugOverlay.log("player/projectiles", self,
		"HIT LIVING: eff_dmg=%d (base=%d spd=%.0f launch=%.0f ratio=%.0f%%)",
		[eff_dmg, damage, _get_speed(), _launch_speed,
		_get_speed() / maxf(_launch_speed, 1.0) * 100.0])


func _impact_inanimate(body: Node2D) -> void:
	## Hit an inanimate object: damage if possible, stick, NO blood.
	if _hit:
		return
	_hit = true

	var eff_dmg: int = _effective_damage()
	if body.has_method("take_damage"):
		body.take_damage(eff_dmg, owner_index)

	_apply_impact_force(body)
	_spawn_damage_number(eff_dmg)
	if projectile_type == "muffin_grenade":
		_explode()
	else:
		_stick_to(body)
		# No blood for inanimate targets


func _impact_surface(_body: Node2D, normal: Vector2) -> void:
	## Hit a wall/floor. Behavior depends on impact angle:
	##   90-30° from surface (steep)    → stick
	##   30-0°  from surface (glancing) → bounce with proportional speed loss
	var vel: Vector2 = _get_velocity()
	var spd: float = vel.length()
	if spd < 1.0:
		_freeze_in_place()
		return

	# Angle between velocity and surface normal (0° = head-on, 90° = parallel)
	# We want the angle FROM the surface, so:
	#   impact_angle = angle between -velocity and normal
	#   0° = head-on into surface, 90° = perfectly parallel/glancing
	var incoming: Vector2 = -vel.normalized()
	var cos_angle: float = absf(incoming.dot(normal))
	var impact_angle_deg: float = rad_to_deg(acos(clampf(cos_angle, 0.0, 1.0)))
	# impact_angle_deg: 0 = head-on, 90 = glancing

	# Convert to "angle from surface" (complement):
	# surface_angle = 90 - impact_angle
	# surface_angle: 0 = head-on (perpendicular to surface), 90 = glancing (parallel)
	# But the user spec uses angle FROM surface normal:
	#   90-30° = steep → stick
	#   30-0°  = glancing → bounce
	# So impact_angle_deg 0-30 = steep (stick), 30-90 = glancing (bounce)
	# Wait, re-reading the spec:
	#   "90-30 degrees" → stick
	#   "30-0 degrees" → bounce
	# The "degrees" here refers to angle of incidence from surface tangent.
	# At 90° from surface (perpendicular hit) = stick
	# At 0° from surface (parallel/glancing) = bounce
	# My impact_angle_deg: 0 = perpendicular, 90 = parallel
	# So: if impact_angle_deg < 30 → stick (steep, near-perpendicular)
	#     if impact_angle_deg >= 30 → bounce (glancing)
	# Speed loss at 30° = 50%, at 90° = 0%, linear between

	if impact_angle_deg < 30.0:
		# Steep impact — arrow sticks
		_freeze_in_place()
		return

	# Glancing bounce — reflect velocity off surface normal
	if _bounce_count >= MAX_BOUNCES:
		_freeze_in_place()
		return
	_bounce_count += 1

	var reflected: Vector2 = vel - 2.0 * vel.dot(normal) * normal

	# Speed loss: 50% at exactly 30°, 0% at 90° (perfectly parallel), linear between
	var t: float = clampf((impact_angle_deg - 30.0) / 60.0, 0.0, 1.0)  # 0 at 30°, 1 at 90°
	var speed_retention: float = lerpf(0.5, 1.0, t)  # 50% at 30°, 100% at 90°

	_set_velocity(reflected.normalized() * spd * speed_retention)
	_play_ricochet()

	DebugOverlay.log("player/projectiles", self,
		"BOUNCE angle=%.1f° retain=%.0f%% spd=%.0f→%.0f",
		[impact_angle_deg, speed_retention * 100.0, spd, spd * speed_retention])


func _freeze_in_place() -> void:
	## Stick the arrow at its current position (no parent body to follow).
	_hit = true
	_stuck = true
	_stuck_parent = null
	var vel: Vector2 = _get_velocity()
	if vel.length() > 0.1:
		rotation = vel.angle()
	collision_shape.set_deferred("disabled", true)
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	_play_thunk()


# =============================================================================
# Chain deflection
# =============================================================================

const CHAIN_HIT_RADIUS := 6.0  # How close the arrow must pass to a chain segment

func _check_chain_deflection(from: Vector2, to: Vector2) -> void:
	## Check if the arrow's path intersects any chain. If so, deflect.
	var chains := get_tree().get_nodes_in_group("chains")
	for chain in chains:
		if not "_points" in chain:
			continue
		var points: PackedVector2Array = chain._points
		if points.size() < 2:
			continue
		for i in range(points.size() - 1):
			var a: Vector2 = points[i]
			var b: Vector2 = points[i + 1]
			# Find closest distance between line segments (from→to) and (a→b)
			var closest: float = _segment_distance(from, to, a, b)
			if closest < CHAIN_HIT_RADIUS:
				_deflect_off_chain()
				return


func _segment_distance(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2) -> float:
	## Minimum distance between two line segments (p1-p2) and (p3-p4).
	# Project each endpoint onto the other segment and take the minimum
	var d1: float = _point_to_segment_dist(p1, p3, p4)
	var d2: float = _point_to_segment_dist(p2, p3, p4)
	var d3: float = _point_to_segment_dist(p3, p1, p2)
	var d4: float = _point_to_segment_dist(p4, p1, p2)
	return minf(minf(d1, d2), minf(d3, d4))


func _point_to_segment_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	## Distance from point p to line segment a-b.
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq < 0.001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	var proj: Vector2 = a + ab * t
	return p.distance_to(proj)


func _deflect_off_chain() -> void:
	## Arrow glances off a chain: random ±5° deflection, lose 30% speed.
	var vel: Vector2 = _get_velocity()
	var deflect_angle: float = deg_to_rad(randf_range(-5.0, 5.0))
	var new_vel: Vector2 = vel.rotated(deflect_angle) * 0.7
	_set_velocity(new_vel)
	_play_clink()

	DebugOverlay.log("player/projectiles", self,
		"CHAIN DEFLECT angle=%.1f° spd=%.0f→%.0f",
		[rad_to_deg(deflect_angle), vel.length(), new_vel.length()])


func _play_clink() -> void:
	## Short metallic clink for chain deflection.
	var player := AudioStreamPlayer.new()
	add_child(player)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.05
	player.stream = gen
	player.volume_db = -12.0
	player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	player.play()
	var playback: AudioStreamGeneratorPlayback = player.get_stream_playback()
	var samples := int(22050.0 * 0.04)
	for i in samples:
		var t: float = float(i) / 22050.0
		var env: float = exp(-t * 120.0)
		# High metallic ping
		var ping: float = sin(t * TAU * 2200.0) * 0.4 + sin(t * TAU * 3300.0) * 0.3
		var noise: float = randf_range(-1.0, 1.0) * 0.15
		playback.push_frame(Vector2.ONE * (ping + noise) * env)
	player.finished.connect(player.queue_free)


func _play_ricochet() -> void:
	## Sharp ricochet sound for surface bounces.
	var player := AudioStreamPlayer.new()
	add_child(player)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.06
	player.stream = gen
	player.volume_db = -10.0
	player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	player.play()
	var playback: AudioStreamGeneratorPlayback = player.get_stream_playback()
	var samples := int(22050.0 * 0.05)
	for i in samples:
		var t: float = float(i) / 22050.0
		var env: float = exp(-t * 60.0)
		# Rising pitch ping
		var freq: float = 800.0 + t * 8000.0
		var ping: float = sin(t * TAU * freq) * 0.5
		var noise: float = randf_range(-1.0, 1.0) * 0.2
		playback.push_frame(Vector2.ONE * (ping + noise) * env)
	player.finished.connect(player.queue_free)


# =============================================================================
# Stick + embed
# =============================================================================

func _stick_to(body: Node2D) -> void:
	## Embed the projectile in the hit body. Reparent so it follows
	## the body's position and rotation.
	_hit = true
	_stuck = true
	_stuck_parent = body
	# Disable collision (deferred to avoid physics callback errors)
	collision_shape.set_deferred("disabled", true)
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	_play_thunk()
	# Defer reparent to avoid removing CollisionObject during physics callback
	call_deferred("_deferred_reparent", body, global_position)


func _deferred_reparent(body: Node2D, impact_global: Vector2) -> void:
	if not is_instance_valid(body):
		return
	var parent_node: Node = get_parent()
	if parent_node:
		parent_node.remove_child(self)
	body.add_child(self)
	var body_rot: float = body.global_rotation
	var local_offset: Vector2 = (impact_global - body.global_position).rotated(-body_rot)
	position = local_offset
	# Arrow rotation relative to body: flight angle minus body's current rotation
	var vel: Vector2 = _get_velocity()
	if vel.length() > 0.1:
		rotation = vel.angle() - body_rot
	else:
		rotation = rotation - body_rot


func _apply_impact_force(body: Node2D) -> void:
	if body.has_method("apply_knockback"):
		var impact_vel: Vector2 = _get_velocity()
		# Force scales with effective damage (speed-proportional)
		var eff_dmg: int = _effective_damage()
		var force: Vector2 = impact_vel.normalized() * eff_dmg * 8.0
		body.apply_knockback(force)


func _play_thunk() -> void:
	var player := AudioStreamPlayer.new()
	add_child(player)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.08
	player.stream = gen
	player.volume_db = -8.0
	player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	player.play()
	var playback: AudioStreamGeneratorPlayback = player.get_stream_playback()
	var samples := int(22050.0 * 0.06)
	for i in samples:
		var t: float = float(i) / 22050.0
		var env: float = exp(-t * 80.0)
		var noise: float = randf_range(-1.0, 1.0) * 0.3
		var thud: float = sin(t * TAU * 120.0) * 0.7
		playback.push_frame(Vector2.ONE * (noise + thud) * env)
	player.finished.connect(player.queue_free)


# =============================================================================
# Blood emitter (world-space, only for living targets)
# =============================================================================

func _spawn_damage_number(eff_dmg: int) -> void:
	## Floating damage number at the impact point. World-space, above everything.
	if eff_dmg <= 0:
		return
	var num := DamageNumber.new()
	num.value = eff_dmg
	num.global_position = global_position
	get_tree().current_scene.add_child(num)


func _spawn_blood_emitter(eff_dmg: int = -1) -> void:
	## Only called for living targets. Particle count scales with effective damage.
	if eff_dmg < 0:
		eff_dmg = _effective_damage()
	if eff_dmg == 0:
		return  # No damage = no blood
	var impact_dir: Vector2 = _get_velocity().normalized()
	var drip_count: int = maxi(2, eff_dmg / 5)
	var drip_interval: float = clampf(0.5 - eff_dmg * 0.01, 0.1, 0.5)

	var emitter := BloodEmitter.new()
	emitter.source_pos = global_position
	emitter.splatter_dir = -impact_dir
	emitter.drip_count = drip_count
	emitter.drip_interval = drip_interval
	emitter.damage_scale = clampf(float(eff_dmg) / 30.0, 0.3, 3.0)
	get_tree().current_scene.add_child(emitter)
	_blood_emitter = emitter


# =============================================================================
# Collision callbacks (overlap-based, backup for raycast)
# =============================================================================

func _on_body_entered(body: Node2D) -> void:
	if _hit:
		return
	# Use a zero-length normal — let _handle_impact classify without surface info
	# For body overlaps the raycast path handles surfaces; this catches slower hits
	if _body_is_living(body):
		_impact_living(body)
	elif _body_is_surface(body):
		# No normal from overlap — treat as steep (stick)
		_freeze_in_place()
	else:
		_impact_inanimate(body)


func _on_area_entered(area: Area2D) -> void:
	if _hit:
		return
	if area.has_meta("part_name"):
		_hit = true
		var eff_dmg: int = _effective_damage()
		var part_name: String = area.get_meta("part_name")
		var enemy: Node2D = area.get_parent()
		if enemy and enemy.has_method("take_part_damage"):
			enemy.take_part_damage(part_name, eff_dmg, owner_index)
		elif enemy and enemy.has_method("take_damage"):
			enemy.take_damage(eff_dmg, owner_index)
		_spawn_damage_number(eff_dmg)
		if projectile_type == "muffin_grenade":
			_explode()
		elif enemy:
			_stick_to(enemy)
			if _body_is_living(enemy) and eff_dmg > 0:
				_spawn_blood_emitter(eff_dmg)
		else:
			queue_free()
		return

	# Wall/obstacle area
	if projectile_type == "muffin_grenade":
		_explode()
	else:
		_freeze_in_place()


func _explode() -> void:
	var eff_dmg: int = _effective_damage()
	var explosion_radius := 48.0
	var bodies := get_tree().get_nodes_in_group("enemies")
	for body in bodies:
		if body is Node2D:
			var dist: float = global_position.distance_to(body.global_position)
			if dist <= explosion_radius and body.has_method("take_damage"):
				body.take_damage(eff_dmg, owner_index)
	queue_free()


# =============================================================================
# BloodEmitter — world-space blood particle system
# =============================================================================

class BloodEmitter extends Node2D:
	var source_pos: Vector2
	var splatter_dir: Vector2
	var drip_count: int = 5
	var drip_interval: float = 0.3
	var damage_scale: float = 1.0

	var _timer: float = 0.0
	var _emitted: int = 0
	var _drops: Array = []

	const GRAVITY := 400.0
	const AIR_RESISTANCE := 2.5
	const MAX_DROP_LIFE := 2.5

	func _physics_process(delta: float) -> void:
		if _emitted < drip_count:
			_timer -= delta
			if _timer <= 0.0:
				_timer = drip_interval
				_emit_drop()
				_emitted += 1

		var i := _drops.size() - 1
		while i >= 0:
			var d: Dictionary = _drops[i]
			d.age += delta
			d.vel.y += GRAVITY * delta
			d.vel *= exp(-AIR_RESISTANCE * delta)
			d.pos += d.vel * delta
			if d.age > MAX_DROP_LIFE:
				_drops.remove_at(i)
			i -= 1

		if _emitted >= drip_count and _drops.is_empty():
			queue_free()
			return
		queue_redraw()

	func _emit_drop() -> void:
		var spread: float = randf_range(-0.6, 0.6)
		var splash_speed: float = randf_range(20.0, 80.0) * damage_scale
		var splash_dir: Vector2 = splatter_dir.rotated(spread)
		var init_vel: Vector2 = splash_dir * splash_speed + Vector2(0, randf_range(-30.0, -10.0))
		var drop_size: float = randf_range(1.0, 2.5) * clampf(damage_scale, 0.5, 2.0)
		_drops.append({"pos": source_pos, "vel": init_vel, "age": 0.0, "size": drop_size})

	func _draw() -> void:
		for d in _drops:
			var life_frac: float = d.age / MAX_DROP_LIFE
			var alpha: float = clampf(1.0 - life_frac * life_frac, 0.0, 1.0)
			var r: float = d.size * lerpf(1.0, 0.3, life_frac)
			draw_circle(d.pos, r, Color(0.55, 0.0, 0.0, alpha))


# =============================================================================
# DamageNumber — floating damage text
# =============================================================================
# White number with black outline, arcs upward in a random direction, fades out.
# z_index set above everything so it's always visible.

class DamageNumber extends Node2D:
	var value: int = 0
	var _vel: Vector2
	var _age: float = 0.0

	const LIFETIME := 1.2
	const GRAVITY := 120.0
	const FONT_SIZE := 14

	func _ready() -> void:
		z_index = 100
		# Random upward arc: mostly up, slight horizontal variation
		_vel = Vector2(randf_range(-30.0, 30.0), randf_range(-80.0, -50.0))

	func _process(delta: float) -> void:
		_age += delta
		if _age >= LIFETIME:
			queue_free()
			return
		_vel.y += GRAVITY * delta
		position += _vel * delta
		queue_redraw()

	func _draw() -> void:
		var alpha: float = clampf(1.0 - (_age / LIFETIME), 0.0, 1.0)
		var text: String = str(value)
		var font: Font = ThemeDB.fallback_font
		var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
		var offset := Vector2(-text_size.x * 0.5, text_size.y * 0.25)
		# Black outline (draw at 8 offsets around the text)
		var outline_color := Color(0.0, 0.0, 0.0, alpha)
		for dx in [-1.0, 0.0, 1.0]:
			for dy in [-1.0, 0.0, 1.0]:
				if dx == 0.0 and dy == 0.0:
					continue
				draw_string(font, offset + Vector2(dx, dy), text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, outline_color)
		# White fill
		draw_string(font, offset, text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(1.0, 1.0, 1.0, alpha))
