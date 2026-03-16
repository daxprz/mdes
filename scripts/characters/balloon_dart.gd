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
var _shadow_node: ColorRect = null
var _is_topdown: bool = false  # Detected from GameManager state

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

	# Detect if we're in top-down mode
	_is_topdown = GameManager.current_state == GameManager.GameState.OVERWORLD or GameManager.current_tower_id == 2

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
	_repulse_other_balloons(delta)

	queue_redraw()


func _update_dart(delta: float) -> void:
	if not _is_topdown:
		_dart_vel.y += 100.0 * delta  # Slight gravity on dart (side-view only)
	_dart_pos += _dart_vel * delta

	# Check for enemy hits
	for body in get_tree().get_nodes_in_group("enemies"):
		if not body is Node2D:
			continue
		var dist: float = _dart_pos.distance_to(body.global_position)
		var hit_radius: float = 50.0 if body.is_in_group("bosses") else 16.0
		if dist < hit_radius:
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

	# Balloons last forever until popped by a projectile
	# Check if any projectile is near the balloon
	for proj in get_tree().get_nodes_in_group("loose_items"):
		if not proj is Node2D:
			continue
		var dist: float = _balloon_pos.distance_to(proj.global_position)
		if dist < _balloon_radius + 8.0:
			# Check if it's a fire/flame projectile
			var is_flame: bool = false
			# Check property
			if "projectile_type" in proj:
				var ptype: String = str(proj.projectile_type).to_lower()
				if "fire" in ptype or "flame" in ptype or "napalm" in ptype or "muffin_grenade" in ptype:
					is_flame = true
			# Check meta (fireball uses this)
			if proj.has_meta("projectile_type"):
				var mtype: String = str(proj.get_meta("projectile_type")).to_lower()
				if "fire" in mtype or "flame" in mtype:
					is_flame = true
			# Check demo fire aspect
			if proj.has_meta("aspect") and str(proj.get_meta("aspect")) == "fire":
				is_flame = true
			# Check name
			if "Fireball" in proj.name or "fireball" in proj.name:
				is_flame = true

			if is_flame:
				# HYDROGEN EXPLOSION!
				AudioManager.play("explosion", 2.0, 0.6)
				AudioManager.play("rocket_crash", -2.0, 1.5)
				_spawn_hydrogen_explosion()
			else:
				# Normal pop - release H2 gas cloud
				AudioManager.play("explosion", -6.0, 2.0)
				_spawn_pop_particles()
				_spawn_h2_gas_cloud()

			proj.queue_free()
			_detach_and_free()
			return


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
			if _attached_to.velocity.y < -120.0:
				_attached_to.velocity.y = -120.0
		# Even if not fully lifting, reduce gravity effect
		_attached_to.velocity.y -= absf(lift_force) * delta * 1.5

		# Multiple balloons stack
		var balloon_count: int = 0
		for dart in get_tree().get_nodes_in_group("balloon_darts"):
			if dart != self and dart.has_method("_get_entity_weight") and dart._attached_to == _attached_to:
				balloon_count += 1
		if balloon_count > 0:
			_attached_to.velocity.y -= 40.0 * balloon_count * delta

		# Shadow under floating entity (top-down or side-view)
		if net_force < -20.0:
			_update_shadow()


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


func _spawn_hydrogen_explosion() -> void:
	var pos: Vector2 = _balloon_pos
	var blast_radius: float = 80.0

	# Screen shake
	var cam := get_viewport().get_camera_2d()
	if cam:
		var orig: Vector2 = cam.offset
		for i in range(8):
			cam.offset = orig + Vector2(randf_range(-6, 6), randf_range(-6, 6))
			await get_tree().create_timer(0.03).timeout
		if is_instance_valid(cam):
			cam.offset = orig

	# Big fire burst - white flash + orange/red expanding rings
	for ring_i in range(3):
		var ring := ColorRect.new()
		var ring_colors: Array[Color] = [
			Color(1.0, 1.0, 0.8, 0.8),
			Color(1.0, 0.5, 0.1, 0.6),
			Color(1.0, 0.2, 0.0, 0.4),
		]
		ring.color = ring_colors[ring_i]
		var rs: float = 16.0 + ring_i * 10.0
		ring.size = Vector2(rs, rs)
		ring.position = pos - Vector2(rs / 2.0, rs / 2.0)
		ring.pivot_offset = Vector2(rs / 2.0, rs / 2.0)
		ring.z_index = 12
		get_parent().add_child(ring)
		var scale_target: float = blast_radius * 2.0 / rs
		var rt := ring.create_tween()
		rt.set_parallel(true)
		rt.tween_property(ring, "scale", Vector2(scale_target, scale_target), 0.2 + ring_i * 0.05)
		rt.tween_property(ring, "modulate:a", 0.0, 0.25 + ring_i * 0.05)
		rt.chain().tween_callback(ring.queue_free)

	# Fire particles flying outward
	for i in range(20):
		var p := ColorRect.new()
		var fire_colors: Array[Color] = [
			Color(1.0, 0.9, 0.3, 0.9),
			Color(1.0, 0.5, 0.0, 0.8),
			Color(1.0, 0.2, 0.0, 0.7),
		]
		p.color = fire_colors[i % fire_colors.size()]
		p.size = Vector2(randf_range(3, 7), randf_range(3, 7))
		p.position = pos + Vector2(randf_range(-5, 5), randf_range(-5, 5))
		p.z_index = 11
		get_parent().add_child(p)
		var vel: Vector2 = Vector2(randf_range(-120, 120), randf_range(-150, 50))
		var pt := p.create_tween()
		pt.tween_property(p, "position", p.position + vel * 0.3, 0.3)
		pt.parallel().tween_property(p, "modulate:a", 0.0, 0.35)
		pt.tween_callback(p.queue_free)

	# Damage everything in blast radius
	for body in get_tree().get_nodes_in_group("enemies"):
		if body is Node2D:
			var dist: float = pos.distance_to(body.global_position)
			if dist < blast_radius and body.has_method("take_damage"):
				body.take_damage(40, owner_index)
				if body.has_method("apply_knockback"):
					var kb: Vector2 = (body.global_position - pos).normalized() * 350.0
					body.apply_knockback(kb)
	for body in get_tree().get_nodes_in_group("players"):
		if body is Node2D:
			var dist: float = pos.distance_to(body.global_position)
			if dist < blast_radius and body.has_method("take_damage"):
				body.take_damage(15, -1)  # Friendly fire from explosion


func _spawn_pop_particles() -> void:
	var pos: Vector2 = _balloon_pos

	# Big white flash at center
	var flash := ColorRect.new()
	flash.color = Color(1.0, 1.0, 1.0, 0.8)
	flash.size = Vector2(40, 40)
	flash.position = pos - Vector2(20, 20)
	flash.z_index = 12
	get_parent().add_child(flash)
	var ft := flash.create_tween()
	ft.tween_property(flash, "modulate:a", 0.0, 0.15)
	ft.tween_callback(flash.queue_free)

	# Expanding balloon-colored ring
	var ring := ColorRect.new()
	ring.color = _balloon_color
	ring.color.a = 0.6
	ring.size = Vector2(16, 16)
	ring.position = pos - Vector2(8, 8)
	ring.pivot_offset = Vector2(8, 8)
	ring.z_index = 11
	get_parent().add_child(ring)
	var rt := ring.create_tween()
	rt.set_parallel(true)
	rt.tween_property(ring, "scale", Vector2(5.0, 5.0), 0.25)
	rt.tween_property(ring, "modulate:a", 0.0, 0.3)
	rt.chain().tween_callback(ring.queue_free)

	# Rubber shred particles flying everywhere
	for i in range(20):
		var p := ColorRect.new()
		if i % 3 == 0:
			p.color = _balloon_color
		elif i % 3 == 1:
			p.color = _balloon_color.darkened(0.3)
		else:
			p.color = Color(1.0, 1.0, 1.0, 0.6)
		var psize: float = randf_range(3, 8)
		p.size = Vector2(psize, psize * randf_range(0.3, 1.0))
		p.rotation = randf_range(0, TAU)
		p.position = pos + Vector2(randf_range(-5, 5), randf_range(-5, 5))
		p.z_index = 10
		get_parent().add_child(p)
		var vel: Vector2 = Vector2(randf_range(-150, 150), randf_range(-180, 60))
		var pt := p.create_tween()
		pt.set_parallel(true)
		pt.tween_property(p, "position", p.position + vel * 0.4, 0.4)
		pt.tween_property(p, "modulate:a", 0.0, 0.45)
		pt.tween_property(p, "rotation", p.rotation + randf_range(-3, 3), 0.4)
		pt.chain().tween_callback(p.queue_free)

	# Small smoke puffs
	for i in range(6):
		var smoke := ColorRect.new()
		smoke.color = Color(0.7, 0.7, 0.7, 0.3)
		smoke.size = Vector2(8, 8)
		smoke.position = pos + Vector2(randf_range(-10, 10), randf_range(-10, 5))
		smoke.z_index = 9
		get_parent().add_child(smoke)
		var st := smoke.create_tween()
		st.set_parallel(true)
		st.tween_property(smoke, "position:y", smoke.position.y - randf_range(15, 35), 0.6)
		st.tween_property(smoke, "modulate:a", 0.0, 0.7)
		st.tween_property(smoke, "scale", Vector2(2.5, 2.5), 0.7)
		st.chain().tween_callback(smoke.queue_free)

	# Screen shake on pop
	var cam := get_viewport().get_camera_2d()
	if cam:
		var orig: Vector2 = cam.offset
		for s in range(4):
			cam.offset = orig + Vector2(randf_range(-3, 3), randf_range(-3, 3))
			await get_tree().create_timer(0.03).timeout
		if is_instance_valid(cam):
			cam.offset = orig


func _spawn_h2_gas_cloud() -> void:
	# Spawn a cloud of H2 gas particles that float upward
	# If they touch anything hot (fire projectiles, lava) → EXPLODE
	var gas_pos: Vector2 = _balloon_pos
	var gas_owner: int = owner_index
	var parent_node: Node2D = get_parent()
	if not parent_node:
		return

	# Create a gas cloud controller node
	var cloud := Node2D.new()
	cloud.name = "H2Cloud"
	cloud.global_position = gas_pos
	cloud.z_index = 7
	cloud.add_to_group("h2_clouds")
	parent_node.add_child(cloud)

	# Attach behavior via inline script
	var cloud_script := GDScript.new()
	cloud_script.source_code = """extends Node2D

var particles: Array = []
var _age: float = 0.0
const LIFETIME := 25.0  # Lingers for a long time
const GAS_SPEED := -15.0  # Slow gentle float upward
const SPREAD := 30.0
const EXPLOSION_RADIUS := 100.0
const EXPLOSION_DAMAGE := 35
var owner_index: int = -1
var _exploded := false

func _ready() -> void:
	# Spawn 12 gas particles
	for i in range(12):
		var p := ColorRect.new()
		p.color = Color(0.6, 0.8, 0.5, 0.35)
		var s: float = randf_range(6, 14)
		p.size = Vector2(s, s)
		p.position = Vector2(randf_range(-10, 10), randf_range(-10, 10))
		p.z_index = 7
		add_child(p)
		particles.append({
			\"node\": p,
			\"vel\": Vector2(randf_range(-15, 15), GAS_SPEED + randf_range(-10, 5)),
			\"wobble_phase\": randf_range(0, 6.28),
		})

func _process(delta: float) -> void:
	if _exploded:
		return
	_age += delta

	# Move particles upward with wobble
	for pd in particles:
		if not is_instance_valid(pd[\"node\"]):
			continue
		var p: ColorRect = pd[\"node\"]
		pd[\"vel\"].x += sin(_age * 2.0 + pd[\"wobble_phase\"]) * 20.0 * delta
		p.position += pd[\"vel\"] * delta
		# Expand slowly
		p.scale += Vector2(delta * 0.3, delta * 0.3)
		# Fade over time
		# Stay opaque most of the time, only fade in the last 30%
		if _age > LIFETIME * 0.7:
			p.modulate.a = lerpf(0.35, 0.0, (_age - LIFETIME * 0.7) / (LIFETIME * 0.3))
		else:
			p.modulate.a = 0.35

	# Check for fire/heat sources
	# 1. Fire projectiles (loose_items with fire type)
	for proj in get_tree().get_nodes_in_group(\"loose_items\"):
		if not proj is Node2D:
			continue
		var dist: float = global_position.distance_to(proj.global_position)
		if dist > 80.0:
			continue
		var is_fire := false
		if \"projectile_type\" in proj and \"fire\" in str(proj.projectile_type).to_lower():
			is_fire = true
		if proj.has_meta(\"projectile_type\") and \"fire\" in str(proj.get_meta(\"projectile_type\")).to_lower():
			is_fire = true
		if \"Fireball\" in proj.name:
			is_fire = true
		if is_fire:
			_h2_explode()
			return

	# 2. Lava pools
	for lava in get_tree().get_nodes_in_group(\"lava_traps\"):
		if lava is Node2D:
			var dist: float = global_position.distance_to(lava.global_position)
			if dist < 60.0:
				_h2_explode()
				return

	# 3. Other H2 explosions (chain reaction!)
	# (handled by the explosion damaging this cloud)

	if _age >= LIFETIME:
		queue_free()

func _h2_explode() -> void:
	if _exploded:
		return
	_exploded = true
	AudioManager.play(\"explosion\", 3.0, 0.5)
	AudioManager.play(\"rocket_crash\", 0.0, 1.2)

	var pos: Vector2 = global_position

	# Big fire explosion
	# Flash
	var flash := ColorRect.new()
	flash.color = Color(1.0, 1.0, 0.8, 0.9)
	flash.size = Vector2(60, 60)
	flash.position = pos - Vector2(30, 30)
	flash.z_index = 12
	get_parent().add_child(flash)
	var ft := flash.create_tween()
	ft.tween_property(flash, \"modulate:a\", 0.0, 0.15)
	ft.tween_callback(flash.queue_free)

	# Fire rings
	for ri in range(3):
		var ring := ColorRect.new()
		var rc: Array = [Color(1.0, 0.9, 0.3, 0.7), Color(1.0, 0.5, 0.1, 0.5), Color(1.0, 0.2, 0.0, 0.4)]
		ring.color = rc[ri]
		var rs: float = 20.0 + ri * 10.0
		ring.size = Vector2(rs, rs)
		ring.position = pos - Vector2(rs/2, rs/2)
		ring.pivot_offset = Vector2(rs/2, rs/2)
		ring.z_index = 11
		get_parent().add_child(ring)
		var scale_t: float = EXPLOSION_RADIUS * 2.0 / rs
		var rt := ring.create_tween()
		rt.set_parallel(true)
		rt.tween_property(ring, \"scale\", Vector2(scale_t, scale_t), 0.25 + ri * 0.05)
		rt.tween_property(ring, \"modulate:a\", 0.0, 0.3 + ri * 0.05)
		rt.chain().tween_callback(ring.queue_free)

	# Fire particles
	for i in range(15):
		var fp := ColorRect.new()
		var fc: Array = [Color(1.0, 0.9, 0.3, 0.9), Color(1.0, 0.5, 0.0, 0.8), Color(1.0, 0.2, 0.0, 0.7)]
		fp.color = fc[i % 3]
		fp.size = Vector2(randf_range(3, 6), randf_range(3, 6))
		fp.position = pos
		fp.z_index = 10
		get_parent().add_child(fp)
		var vel := Vector2(randf_range(-100, 100), randf_range(-120, 40))
		var fpt := fp.create_tween()
		fpt.tween_property(fp, \"position\", fp.position + vel * 0.3, 0.3)
		fpt.parallel().tween_property(fp, \"modulate:a\", 0.0, 0.35)
		fpt.tween_callback(fp.queue_free)

	# Damage enemies
	for body in get_tree().get_nodes_in_group(\"enemies\"):
		if body is Node2D:
			var dist: float = pos.distance_to(body.global_position)
			if dist < EXPLOSION_RADIUS and body.has_method(\"take_damage\"):
				body.take_damage(EXPLOSION_DAMAGE, owner_index)
				if body.has_method(\"apply_knockback\"):
					var kb: Vector2 = (body.global_position - pos).normalized() * 300.0
					body.apply_knockback(kb)

	# Damage players (friendly fire)
	for body in get_tree().get_nodes_in_group(\"players\"):
		if body is Node2D:
			var dist: float = pos.distance_to(body.global_position)
			if dist < EXPLOSION_RADIUS and body.has_method(\"take_damage\"):
				body.take_damage(10, -1)

	# Chain: trigger other nearby H2 clouds
	for other_cloud in get_tree().get_nodes_in_group(\"h2_clouds\"):
		if other_cloud != self and other_cloud is Node2D:
			var dist: float = pos.distance_to(other_cloud.global_position)
			if dist < EXPLOSION_RADIUS and other_cloud.has_method(\"_h2_explode\"):
				other_cloud.call_deferred(\"_h2_explode\")

	# Screen shake
	var cam := get_viewport().get_camera_2d()
	if cam:
		var orig: Vector2 = cam.offset
		for sh in range(6):
			cam.offset = orig + Vector2(randf_range(-5, 5), randf_range(-5, 5))
			await get_tree().create_timer(0.03).timeout
		if is_instance_valid(cam):
			cam.offset = orig

	# Clean up
	await get_tree().create_timer(0.5).timeout
	if is_inside_tree():
		queue_free()
"""
	cloud_script.reload()
	cloud.set_script(cloud_script)
	cloud.set("owner_index", gas_owner)


func _repulse_other_balloons(delta: float) -> void:
	if _balloon_radius < 4.0:
		return  # Not inflated enough yet
	for other in get_tree().get_nodes_in_group("balloon_darts"):
		if other == self or not other is Node2D:
			continue
		if not ("_balloon_pos" in other and "_balloon_radius" in other):
			continue
		var other_pos: Vector2 = other._balloon_pos
		var other_r: float = other._balloon_radius
		if other_r < 4.0:
			continue
		var diff: Vector2 = _balloon_pos - other_pos
		var dist: float = diff.length()
		var min_dist: float = _balloon_radius + other_r + 4.0  # Gap between balloons
		if dist < min_dist and dist > 0.1:
			# Push apart
			var push: Vector2 = diff.normalized() * (min_dist - dist) * 2.0 * delta
			_balloon_pos += push


func _update_shadow() -> void:
	if not is_instance_valid(_attached_to):
		return
	if not is_instance_valid(_shadow_node):
		_shadow_node = ColorRect.new()
		_shadow_node.color = Color(0, 0, 0, 0.25)
		_shadow_node.size = Vector2(16, 6)
		_shadow_node.z_index = -5
		get_parent().add_child(_shadow_node)
	# Shadow stays at the entity's original ground position
	# (offset slightly below where entity started)
	if _attached_to.has_meta("shadow_ground_y"):
		_shadow_node.position = Vector2(_attached_to.global_position.x - 8, _attached_to.get_meta("shadow_ground_y"))
	else:
		# First time: record ground position
		_attached_to.set_meta("shadow_ground_y", _attached_to.global_position.y + 14)
		_shadow_node.position = Vector2(_attached_to.global_position.x - 8, _attached_to.global_position.y + 14)
	# Shadow shrinks as entity floats higher
	var height_diff: float = absf(_attached_to.get_meta("shadow_ground_y") - _attached_to.global_position.y)
	var shadow_scale: float = clampf(1.0 - height_diff / 200.0, 0.2, 1.0)
	_shadow_node.scale = Vector2(shadow_scale, shadow_scale)


func _detach_and_free() -> void:
	_attached_to = null
	_balloon_inflating = false
	if is_instance_valid(_shadow_node):
		_shadow_node.queue_free()
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

	# Draw balloon (teardrop shape)
	if _balloon_inflating or _balloon_radius > 2.0:
		var local_balloon: Vector2 = _balloon_pos - global_position
		var r: float = _balloon_radius

		# Teardrop shape using polygon: wide top, narrow bottom point
		var segments: int = 16
		var points := PackedVector2Array()
		var colors := PackedColorArray()
		for i in range(segments):
			var angle: float = TAU * float(i) / float(segments)
			# Teardrop: wider at top (negative y), narrower at bottom
			var rx: float = r * cos(angle)
			var ry: float
			if sin(angle) > 0:
				# Bottom half: pinch to a point
				ry = r * sin(angle) * 1.4  # Elongated downward
				rx *= (1.0 - sin(angle) * 0.6)  # Narrow toward bottom
			else:
				# Top half: round and full
				ry = r * sin(angle) * 0.9
			points.append(local_balloon + Vector2(rx, ry))
			colors.append(_balloon_color)
		if points.size() >= 3:
			draw_polygon(points, colors)

		# Highlight (shiny spot on upper-left)
		draw_circle(local_balloon + Vector2(-r * 0.25, -r * 0.35), r * 0.25, Color(1, 1, 1, 0.35))

		# Knot at bottom tip
		var knot_pos: Vector2 = local_balloon + Vector2(0, r * 1.3)
		draw_circle(knot_pos, 2.0, _balloon_color.darkened(0.3))

		# Small triangle tie at knot
		var tie_points := PackedVector2Array([
			knot_pos + Vector2(-3, -2),
			knot_pos + Vector2(3, -2),
			knot_pos + Vector2(0, 3),
		])
		draw_polygon(tie_points, PackedColorArray([_balloon_color.darkened(0.2), _balloon_color.darkened(0.2), _balloon_color.darkened(0.2)]))

		# Tie string to balloon knot
		var last_string: Vector2 = _string_points[STRING_SEGMENTS - 1] - global_position
		draw_line(last_string, knot_pos, Color(0.6, 0.6, 0.6, 0.7), 1.0)
