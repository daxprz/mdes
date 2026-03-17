extends Node2D

## Magical stone doorway on the title screen.
## Players walk in front to activate; all players present triggers the transition.

signal all_players_entered

const DOORWAY_WIDTH := 120.0
const DOORWAY_HEIGHT := 160.0
const STONE_COLOR := Color(0.4, 0.35, 0.3)
const STONE_DARK := Color(0.3, 0.25, 0.2)
const STONE_LIGHT := Color(0.5, 0.45, 0.38)
const KEYSTONE_COLOR := Color(0.55, 0.5, 0.4)
const VOID_COLOR := Color(0.02, 0.01, 0.05)
const ACTIVATION_RANGE := 80.0  # How close a player must be to count as "in front"
const SPIRAL_SPEED := 2.5
const RAY_SPEED := 1.5

var _timer: float = 0.0
var _players_near: int = 0
var _total_players: int = 0
var _activated: bool = false  # At least one player near
var _all_present: bool = false  # All players near
var _transition_started: bool = false
var _transition_timer: float = 0.0
var _spiral_particles: Array = []  # Visual particles
var _particle_timer: float = 0.0


func _process(delta: float) -> void:
	_timer += delta
	_particle_timer += delta

	# Count players near the doorway
	_total_players = PlayerManager.get_active_player_count()
	_players_near = 0
	for node in get_tree().get_nodes_in_group("players"):
		if node is Node2D:
			var dist: float = global_position.distance_to(node.global_position)
			if dist < ACTIVATION_RANGE:
				_players_near += 1

	_activated = _players_near > 0
	_all_present = _players_near >= _total_players and _total_players > 0

	# Spawn spiral particles when activated
	if _activated and _particle_timer >= 0.05:
		_particle_timer = 0.0
		_spawn_spiral_particle()

	# All players present — start transition after a moment
	if _all_present and not _transition_started:
		_transition_started = true
		_transition_timer = 0.0
		# Extra burst of particles
		for i in range(20):
			_spawn_spiral_particle()

	if _transition_started:
		_transition_timer += delta
		# Spawn rays
		if _particle_timer >= 0.03:
			_particle_timer = 0.0
			_spawn_ray_particle()

		# Pull players in after 1.5 seconds
		if _transition_timer >= 1.5 and _transition_timer < 3.5:
			_pull_players_in(delta)

		# Transition to overworld after animation
		if _transition_timer >= 3.5:
			all_players_entered.emit()

	# Tick down particle lifetimes
	var i: int = _spiral_particles.size() - 1
	while i >= 0:
		_spiral_particles[i]["time"] -= delta
		if _spiral_particles[i]["time"] <= 0.0:
			_spiral_particles.remove_at(i)
		i -= 1

	queue_redraw()


func _pull_players_in(delta: float) -> void:
	var pull_strength: float = (_transition_timer - 1.5) * 3.0  # Ramps up
	for node in get_tree().get_nodes_in_group("players"):
		if node is CharacterBody2D:
			var to_door: Vector2 = (global_position - node.global_position)
			var dist: float = to_door.length()
			if dist > 5.0:
				node.velocity = to_door.normalized() * pull_strength * 200.0
			# Shrink and spin
			var shrink: float = clampf(1.0 - (_transition_timer - 1.5) / 2.0, 0.05, 1.0)
			node.scale = Vector2(shrink, shrink)
			node.rotation += pull_strength * 5.0 * delta


func _spawn_spiral_particle() -> void:
	var angle: float = randf() * TAU
	var dist: float = randf_range(10.0, 50.0)
	var speed: float = randf_range(30.0, 80.0)
	var size: float = randf_range(2.0, 5.0)
	var brightness: float = 0.7 + randf() * 0.3
	_spiral_particles.append({
		"angle": angle,
		"dist": dist,
		"speed": speed,
		"size": size,
		"brightness": brightness,
		"time": randf_range(1.0, 2.5),
		"type": "spiral",
	})


func _spawn_ray_particle() -> void:
	var angle: float = randf() * TAU
	_spiral_particles.append({
		"angle": angle,
		"dist": 0.0,
		"speed": randf_range(150.0, 350.0),
		"size": randf_range(1.5, 3.0),
		"brightness": 0.9,
		"time": randf_range(0.5, 1.2),
		"type": "ray",
	})


func _draw() -> void:
	_draw_back_layer()
	_draw_front_layer()
	_draw_particles()


func _draw_back_layer() -> void:
	# Black void inside the doorway
	var half_w: float = DOORWAY_WIDTH / 2.0
	draw_rect(Rect2(-half_w, -DOORWAY_HEIGHT, DOORWAY_WIDTH, DOORWAY_HEIGHT), VOID_COLOR)


func _draw_front_layer() -> void:
	var half_w: float = DOORWAY_WIDTH / 2.0
	var stone_w: float = 18.0

	# Left pillar — stacked stones
	for i in range(8):
		var y: float = -DOORWAY_HEIGHT + i * 20.0
		var col: Color = STONE_COLOR if i % 2 == 0 else STONE_DARK
		draw_rect(Rect2(-half_w - stone_w, y, stone_w, 20.0), col)
		# Stone line detail
		draw_line(Vector2(-half_w - stone_w, y), Vector2(-half_w, y), STONE_LIGHT * Color(1, 1, 1, 0.3), 1.0)

	# Right pillar — stacked stones
	for i in range(8):
		var y: float = -DOORWAY_HEIGHT + i * 20.0
		var col: Color = STONE_DARK if i % 2 == 0 else STONE_COLOR
		draw_rect(Rect2(half_w, y, stone_w, 20.0), col)
		draw_line(Vector2(half_w, y), Vector2(half_w + stone_w, y), STONE_LIGHT * Color(1, 1, 1, 0.3), 1.0)

	# Archway at top — curved stones
	var arch_segments := 12
	var arch_radius: float = half_w + stone_w / 2.0
	var prev_outer: Vector2 = Vector2.ZERO
	var prev_inner: Vector2 = Vector2.ZERO
	for i in range(arch_segments + 1):
		var t: float = float(i) / float(arch_segments)
		var angle: float = PI + t * PI  # PI to 2*PI (top half circle)
		var inner_pt: Vector2 = Vector2(cos(angle) * half_w, sin(angle) * half_w + (-DOORWAY_HEIGHT))
		var outer_pt: Vector2 = Vector2(cos(angle) * (half_w + stone_w), sin(angle) * (half_w + stone_w) + (-DOORWAY_HEIGHT))
		if i > 0:
			var col: Color = STONE_COLOR if i % 2 == 0 else STONE_DARK
			# Draw arch stone as quad (two triangles)
			draw_polygon(
				PackedVector2Array([prev_inner, prev_outer, outer_pt, inner_pt]),
				PackedColorArray([col, col, col, col])
			)
		prev_outer = outer_pt
		prev_inner = inner_pt

	# Keystone at the top center of the arch
	var ks_w: float = 16.0
	var ks_h: float = 22.0
	var ks_y: float = -DOORWAY_HEIGHT - half_w - stone_w * 0.3
	draw_rect(Rect2(-ks_w / 2.0, ks_y, ks_w, ks_h), KEYSTONE_COLOR)
	# Keystone detail — small triangle notch
	draw_line(Vector2(-ks_w / 2.0, ks_y), Vector2(0, ks_y - 6), STONE_LIGHT, 1.5)
	draw_line(Vector2(ks_w / 2.0, ks_y), Vector2(0, ks_y - 6), STONE_LIGHT, 1.5)

	# Base stones (wider at bottom)
	draw_rect(Rect2(-half_w - stone_w - 6, -4, stone_w + 6, 8), STONE_DARK)
	draw_rect(Rect2(half_w, -4, stone_w + 6, 8), STONE_DARK)


func _draw_particles() -> void:
	if not _activated and _spiral_particles.is_empty():
		return

	for p in _spiral_particles:
		var age_ratio: float = 1.0 - clampf(p["time"] / 2.0, 0.0, 1.0)

		if p["type"] == "spiral":
			# Spiral inward while rotating
			var current_angle: float = p["angle"] + _timer * SPIRAL_SPEED
			var current_dist: float = p["dist"] * (1.0 - age_ratio * 0.5)
			var pos := Vector2(cos(current_angle) * current_dist, sin(current_angle) * current_dist)
			pos.y -= DOORWAY_HEIGHT / 2.0  # Center in doorway
			var alpha: float = p["brightness"] * (1.0 - age_ratio)
			var size: float = p["size"] * (1.0 - age_ratio * 0.5)
			# Blue sparkle
			draw_circle(pos, size, Color(0.3, 0.5, 1.0, alpha))
			draw_circle(pos, size * 0.5, Color(0.6, 0.8, 1.0, alpha))

		elif p["type"] == "ray":
			# Shoot outward from center
			var current_dist: float = p["speed"] * age_ratio * 2.0
			var pos := Vector2(cos(p["angle"]) * current_dist, sin(p["angle"]) * current_dist)
			pos.y -= DOORWAY_HEIGHT / 2.0
			var alpha: float = p["brightness"] * (1.0 - age_ratio) * 0.6
			var size: float = p["size"]
			# White-blue translucent ray dot
			draw_circle(pos, size, Color(0.7, 0.85, 1.0, alpha))

	# Glow when all present
	if _all_present or _transition_started:
		var glow_alpha: float = 0.15 + 0.1 * sin(_timer * 4.0)
		if _transition_started:
			glow_alpha = clampf(_transition_timer * 0.2, 0.1, 0.5)
		draw_circle(Vector2(0, -DOORWAY_HEIGHT / 2.0), 60.0, Color(0.4, 0.6, 1.0, glow_alpha))
		draw_circle(Vector2(0, -DOORWAY_HEIGHT / 2.0), 30.0, Color(0.6, 0.8, 1.0, glow_alpha * 1.5))
