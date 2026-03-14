extends Area2D

## Smoke bomb trap. When triggered, launches 10 smoke canisters in random arcs.
## Each canister leaves a trail of opaque smoke circles that dissipate over 20s.
## Wind gusts in the area blow the smoke around.

@export var zone_width: float = 320.0
@export var zone_height: float = 240.0
@export var canister_count: int = 10
@export var smoke_lifetime: float = 20.0
@export var smoke_opacity: float = 0.7

var _triggered := false
var _canisters: Array[Dictionary] = []
var _smoke_particles: Array[Dictionary] = []  # {pos, radius, alpha, max_alpha, age, max_age, vel}
var _wind_dir: Vector2 = Vector2.ZERO
var _wind_force: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2

	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(zone_width, zone_height)
	col.shape = shape
	add_child(col)

	body_entered.connect(_on_body_entered)

	# Also trigger by proximity check as backup
	set_process(true)


func _on_body_entered(_body: Node2D) -> void:
	_trigger()


func _trigger() -> void:
	if _triggered:
		return
	_triggered = true
	AudioManager.play("explosion", -4.0, 0.6)

	# Launch smoke canisters in random arcs
	for i in range(canister_count):
		var angle: float = randf_range(-PI, PI)
		var speed: float = randf_range(60.0, 180.0)
		var arc_height: float = randf_range(40.0, 120.0)
		var lifetime: float = randf_range(0.8, 2.0)

		var canister := {
			"pos": Vector2(global_position.x, global_position.y),
			"vel_x": cos(angle) * speed,
			"vel_y": sin(angle) * speed * 0.5 - arc_height,  # Initial upward + outward
			"gravity": randf_range(150.0, 300.0),
			"age": 0.0,
			"max_age": lifetime,
			"trail_timer": 0.0,
			"trail_interval": randf_range(0.03, 0.07),
			"smoke_size": randf_range(12.0, 24.0),
			"alive": true,
		}
		_canisters.append(canister)


func _process(delta: float) -> void:
	# Detect nearby wind gusts
	_detect_wind()

	# Update canisters (the "smoke canister" projectiles arcing outward)
	for c in _canisters:
		if not c["alive"]:
			continue

		c["age"] += delta
		if c["age"] >= c["max_age"]:
			c["alive"] = false
			# Final puff at landing position
			_spawn_smoke_puff(Vector2(c["pos"].x, c["pos"].y), c["smoke_size"] * 1.5)
			continue

		# Physics: gravity pulls canister down, velocity moves it
		c["vel_y"] += c["gravity"] * delta
		c["pos"].x += c["vel_x"] * delta
		c["pos"].y += c["vel_y"] * delta

		# Wind affects canisters too
		c["pos"].x += _wind_dir.x * _wind_force * delta * 0.3
		c["pos"].y += _wind_dir.y * _wind_force * delta * 0.3

		# Air resistance
		c["vel_x"] *= (1.0 - 0.5 * delta)

		# Leave smoke trail
		c["trail_timer"] += delta
		if c["trail_timer"] >= c["trail_interval"]:
			c["trail_timer"] -= c["trail_interval"]
			_spawn_smoke_puff(
				Vector2(c["pos"].x, c["pos"].y),
				c["smoke_size"] * randf_range(0.7, 1.3)
			)

	# Update smoke particles
	var i: int = _smoke_particles.size() - 1
	while i >= 0:
		var p: Dictionary = _smoke_particles[i]
		p["age"] += delta

		if p["age"] >= p["max_age"]:
			_smoke_particles.remove_at(i)
			i -= 1
			continue

		# Fade out over lifetime (slow start, faster at end)
		var life_ratio: float = p["age"] / p["max_age"]
		if life_ratio < 0.1:
			# Fade IN briefly
			p["alpha"] = lerpf(0.0, p["max_alpha"], life_ratio / 0.1)
		elif life_ratio > 0.6:
			# Fade OUT
			p["alpha"] = lerpf(p["max_alpha"], 0.0, (life_ratio - 0.6) / 0.4)

		# Smoke slowly expands
		p["radius"] += delta * 2.0

		# Wind pushes smoke
		p["pos"].x += (_wind_dir.x * _wind_force * 0.5 + p["vel"].x) * delta
		p["pos"].y += (_wind_dir.y * _wind_force * 0.5 + p["vel"].y) * delta

		# Smoke drifts upward slightly and has random turbulence
		p["vel"].y -= 3.0 * delta  # Slight rise
		p["vel"].x += randf_range(-8.0, 8.0) * delta  # Turbulence
		p["vel"].y += randf_range(-5.0, 5.0) * delta
		# Dampen velocity
		p["vel"] *= (1.0 - 0.3 * delta)

		i -= 1

	queue_redraw()


func _spawn_smoke_puff(pos: Vector2, base_radius: float) -> void:
	var puff := {
		"pos": Vector2(pos.x + randf_range(-4.0, 4.0), pos.y + randf_range(-4.0, 4.0)),
		"radius": base_radius * randf_range(0.6, 1.0),
		"alpha": 0.0,
		"max_alpha": smoke_opacity * randf_range(0.5, 1.0),
		"age": 0.0,
		"max_age": smoke_lifetime * randf_range(0.7, 1.3),
		"vel": Vector2(randf_range(-10.0, 10.0), randf_range(-15.0, -5.0)),
	}
	_smoke_particles.append(puff)


func _detect_wind() -> void:
	# Look for nearby wind gust traps and use their direction
	_wind_dir = Vector2.ZERO
	_wind_force = 0.0

	for node in get_tree().get_nodes_in_group("wind_gusts"):
		if not node is Node2D:
			continue
		var dist: float = global_position.distance_to(node.global_position)
		if dist < 300.0 and "push_direction" in node and "force" in node:
			var wind_node: Node2D = node as Node2D
			_wind_dir = wind_node.get("push_direction") as Vector2
			_wind_force = wind_node.get("force") as float
			break


func _draw() -> void:
	# Draw active canisters as small bright dots
	for c in _canisters:
		if not c["alive"]:
			continue
		var cpos: Vector2 = Vector2(c["pos"].x, c["pos"].y) - global_position
		# Canister body
		draw_circle(cpos, 3.0, Color(0.9, 0.4, 0.1, 0.9))
		# Canister spark/trail
		draw_circle(cpos + Vector2(0, -2), 2.0, Color(1.0, 0.7, 0.2, 0.6))

	# Draw smoke particles
	for p in _smoke_particles:
		var spos: Vector2 = Vector2(p["pos"].x, p["pos"].y) - global_position
		var alpha: float = p["alpha"]
		if alpha <= 0.01:
			continue
		var radius: float = p["radius"]

		# Multi-layer smoke for depth
		# Outer: lighter, more transparent
		draw_circle(spos, radius * 1.2, Color(0.3, 0.3, 0.35, alpha * 0.3))
		# Middle: main smoke body
		draw_circle(spos, radius, Color(0.2, 0.2, 0.25, alpha * 0.7))
		# Inner: slightly lighter core
		draw_circle(spos, radius * 0.5, Color(0.35, 0.35, 0.4, alpha * 0.5))
