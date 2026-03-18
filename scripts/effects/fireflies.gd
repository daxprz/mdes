extends Node2D

## Manages a swarm of fireflies rendered with _draw().
## Non-interactive, golden glow, attracted to darkness.

const MAX_FIREFLIES := 50
const SPAWN_INTERVAL := 5.0
const GLOW_BASE_SPEED := 1.5
const MOVE_SPEED := 15.0
const RISE_SPEED := 40.0
const SINK_SPEED := 5.0

var _flies: Array = []  # [{pos, vel, glow_phase, glow_speed, glow_active}]
var _spawn_timer: float = 0.0
var _bounds: Rect2 = Rect2(100, 300, 1720, 600)  # Spawn area


func setup(bounds: Rect2) -> void:
	_bounds = bounds


func _ready() -> void:
	z_index = 3  # In front of most things
	for _i in range(MAX_FIREFLIES):
		_spawn_fly()


func _spawn_fly() -> void:
	if _flies.size() >= MAX_FIREFLIES:
		return
	_flies.append({
		"pos": Vector2(randf_range(_bounds.position.x, _bounds.end.x),
					   randf_range(_bounds.position.y, _bounds.end.y)),
		"vel": Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized() * MOVE_SPEED * randf_range(0.5, 1.5),
		"glow_phase": randf() * TAU,  # Random starting phase
		"glow_speed": GLOW_BASE_SPEED * randf_range(0.7, 1.4),  # Slightly different cadence
		"glow_active": false,
	})


func remove_nearest(world_pos: Vector2) -> bool:
	## Remove the fly nearest to world_pos (called by bats). Returns true if eaten.
	var best_idx: int = -1
	var best_dist: float = INF
	for i in range(_flies.size()):
		var d: float = _flies[i]["pos"].distance_to(world_pos)
		if d < best_dist:
			best_dist = d
			best_idx = i
	if best_idx >= 0 and best_dist < 15.0:
		_flies.remove_at(best_idx)
		return true
	return false


func get_nearest_fly(world_pos: Vector2, max_range: float) -> Vector2:
	## Returns position of nearest fly within range, or Vector2.INF if none
	var best_pos := Vector2.INF
	var best_dist: float = max_range
	for fly in _flies:
		var d: float = fly["pos"].distance_to(world_pos)
		if d < best_dist:
			best_dist = d
			best_pos = fly["pos"]
	return best_pos


func _process(delta: float) -> void:
	# Respawn timer — rate scales with deficit
	if _flies.size() < MAX_FIREFLIES:
		var deficit: int = MAX_FIREFLIES - _flies.size()
		var rate_mult: float = clampf(float(deficit) / 10.0, 1.0, 5.0)  # 1x-5x speed
		_spawn_timer += delta * rate_mult
		if _spawn_timer >= SPAWN_INTERVAL:
			_spawn_timer = 0.0
			_spawn_fly()

	# Update each fly
	var bounds_center: Vector2 = _bounds.get_center()
	for fly in _flies:
		fly["glow_phase"] += fly["glow_speed"] * delta
		# Strongly illuminated only 20% of the time:
		# sin wave is positive ~50% of the time, so use a higher threshold
		var raw_glow: float = sin(fly["glow_phase"])
		var glow: float = clampf((raw_glow - 0.6) / 0.4, 0.0, 1.0)  # Only top 20% of wave
		fly["glow_active"] = glow > 0.0

		# Movement
		if fly["glow_active"]:
			fly["vel"].y = lerpf(fly["vel"].y, -RISE_SPEED, delta * 3.0)
		else:
			fly["vel"].y = lerpf(fly["vel"].y, SINK_SPEED, delta * 1.5)

		# Random drift
		fly["vel"].x += randf_range(-20, 20) * delta

		# Edge avoidance
		var pos: Vector2 = fly["pos"]
		var outside: bool = not _bounds.has_point(pos)
		if outside:
			# Outside bounds: steer straight to center, override everything
			var to_center: Vector2 = (bounds_center - pos).normalized()
			fly["vel"] = to_center * MOVE_SPEED * 2.0
		else:
			# Within 200px of edge: strong steering away
			var edge_margin: float = 200.0
			var steer := Vector2.ZERO
			var dist_left: float = pos.x - _bounds.position.x
			var dist_right: float = _bounds.end.x - pos.x
			var dist_top: float = pos.y - _bounds.position.y
			var dist_bottom: float = _bounds.end.y - pos.y

			if dist_left < edge_margin:
				steer.x += (1.0 - dist_left / edge_margin) * 80.0
			if dist_right < edge_margin:
				steer.x -= (1.0 - dist_right / edge_margin) * 80.0
			if dist_top < edge_margin:
				steer.y += (1.0 - dist_top / edge_margin) * 80.0
			if dist_bottom < edge_margin:
				steer.y -= (1.0 - dist_bottom / edge_margin) * 80.0

			fly["vel"] += steer * delta

		fly["vel"] = fly["vel"].limit_length(MOVE_SPEED * 2.0)
		fly["pos"] += fly["vel"] * delta

	queue_redraw()


func _draw() -> void:
	for fly in _flies:
		var raw_glow: float = sin(fly["glow_phase"])
		var glow: float = clampf((raw_glow - 0.6) / 0.4, 0.0, 1.0)
		var pos: Vector2 = fly["pos"]

		# Outer glow (only when strongly illuminated)
		if glow > 0.0:
			draw_circle(pos, 5.0 + glow * 3.0, Color(1.0, 0.85, 0.2, glow * 0.15))
			draw_circle(pos, 3.0 + glow * 2.0, Color(1.0, 0.9, 0.3, glow * 0.3))

		# Core (always visible, tiny — dim when not glowing)
		var core_alpha: float = 0.15 + glow * 0.85
		draw_circle(pos, 1.5, Color(1.0, 0.9, 0.4, core_alpha))
