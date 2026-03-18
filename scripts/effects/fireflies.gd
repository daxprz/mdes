extends Node2D

## Manages a swarm of fireflies rendered with _draw().
## Non-interactive, golden glow. Each firefly assigned to a spawn zone
## with spawn-gravity pulling it back toward the zone.

const MAX_FIREFLIES := 50
const SPAWN_INTERVAL := 5.0
const GLOW_BASE_SPEED := 1.5
const MOVE_SPEED := 15.0
const RISE_SPEED := 40.0
const SINK_SPEED := 5.0
const ZONE_GRAVITY := 0.8  # How strongly flies are pulled toward their zone center

var _flies: Array = []
var _spawn_timer: float = 0.0
var _zones: Array[Rect2] = []  # Spawn zones with weights
var _zone_weights: Array[float] = []  # Relative weight for spawning probability
var _total_weight: float = 0.0


func setup_zones(zones: Array[Rect2], weights: Array[float] = []) -> void:
	_zones = zones
	if weights.is_empty():
		# Default: weight by area
		for z in zones:
			_zone_weights.append(z.get_area())
	else:
		_zone_weights = weights
	_total_weight = 0.0
	for w in _zone_weights:
		_total_weight += w


func _pick_zone_index() -> int:
	## Weighted random zone selection
	if _zones.is_empty():
		return -1
	var roll: float = randf() * _total_weight
	var accum: float = 0.0
	for i in range(_zones.size()):
		accum += _zone_weights[i]
		if roll <= accum:
			return i
	return _zones.size() - 1


func _dist_to_rect(point: Vector2, rect: Rect2) -> float:
	## Distance from point to nearest edge of rect (0 if inside)
	if rect.has_point(point):
		return 0.0
	var cx: float = clampf(point.x, rect.position.x, rect.end.x)
	var cy: float = clampf(point.y, rect.position.y, rect.end.y)
	return point.distance_to(Vector2(cx, cy))


func _ready() -> void:
	z_index = 3
	# Defer spawning so zones can be set up first
	call_deferred("_initial_spawn")


func _initial_spawn() -> void:
	for _i in range(MAX_FIREFLIES):
		_spawn_fly()


func _spawn_fly() -> void:
	if _flies.size() >= MAX_FIREFLIES:
		return
	if _zones.is_empty():
		return

	var zi: int = _pick_zone_index()
	var zone: Rect2 = _zones[zi]

	# Random position within the zone
	var pos := Vector2(
		randf_range(zone.position.x, zone.end.x),
		randf_range(zone.position.y, zone.end.y)
	)

	_flies.append({
		"pos": pos,
		"vel": Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized() * MOVE_SPEED * randf_range(0.5, 1.5),
		"glow_phase": randf() * TAU,
		"glow_speed": GLOW_BASE_SPEED * randf_range(0.7, 1.4),
		"glow_active": false,
		"zone_idx": zi,
	})


func remove_nearest(world_pos: Vector2) -> bool:
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
		var rate_mult: float = clampf(float(deficit) / 10.0, 1.0, 5.0)
		_spawn_timer += delta * rate_mult
		if _spawn_timer >= SPAWN_INTERVAL:
			_spawn_timer = 0.0
			_spawn_fly()

	# Update each fly
	for fly in _flies:
		fly["glow_phase"] += fly["glow_speed"] * delta
		var raw_glow: float = sin(fly["glow_phase"])
		var glow: float = clampf((raw_glow - 0.6) / 0.4, 0.0, 1.0)
		fly["glow_active"] = glow > 0.0

		# Get this fly's zone
		var zi: int = fly["zone_idx"]
		var zone: Rect2 = _zones[zi] if zi >= 0 and zi < _zones.size() else Rect2()
		var zone_center: Vector2 = zone.get_center()

		# Movement: glow = rise briefly
		if fly["glow_active"]:
			fly["vel"].y = lerpf(fly["vel"].y, -RISE_SPEED, delta * 3.0)

		# Random wander (always active)
		fly["vel"].x += randf_range(-25, 25) * delta
		fly["vel"].y += randf_range(-8, 8) * delta

		# Spawn gravity: find nearest zone, only pull when OUTSIDE it
		var pos: Vector2 = fly["pos"]
		var in_zone: bool = zone.has_point(pos)

		if not in_zone:
			# Find the nearest zone (may have drifted to a different one)
			var nearest_zone: Rect2 = zone
			var nearest_dist: float = _dist_to_rect(pos, zone)
			for zi2 in range(_zones.size()):
				var d: float = _dist_to_rect(pos, _zones[zi2])
				if d < nearest_dist:
					nearest_dist = d
					nearest_zone = _zones[zi2]
					fly["zone_idx"] = zi2
			# Strong pull toward nearest zone center
			var pull_target: Vector2 = nearest_zone.get_center()
			var pull: Vector2 = (pull_target - pos).normalized() * MOVE_SPEED * 1.5
			fly["vel"] = fly["vel"].lerp(pull, delta * 3.0)

		# Hard edge avoidance (screen bounds)
		var screen_bounds := Rect2(30, 30, 1860, 930)
		if not screen_bounds.has_point(pos):
			var screen_center := Vector2(960, 500)
			fly["vel"] = (screen_center - pos).normalized() * MOVE_SPEED * 2.0

		fly["vel"] = fly["vel"].limit_length(MOVE_SPEED * 2.5)
		fly["pos"] += fly["vel"] * delta

	queue_redraw()


func _draw() -> void:
	for fly in _flies:
		var raw_glow: float = sin(fly["glow_phase"])
		var glow: float = clampf((raw_glow - 0.6) / 0.4, 0.0, 1.0)
		var pos: Vector2 = fly["pos"]

		if glow > 0.0:
			draw_circle(pos, 5.0 + glow * 3.0, Color(1.0, 0.85, 0.2, glow * 0.15))
			draw_circle(pos, 3.0 + glow * 2.0, Color(1.0, 0.9, 0.3, glow * 0.3))

		var core_alpha: float = 0.15 + glow * 0.85
		draw_circle(pos, 1.5, Color(1.0, 0.9, 0.4, core_alpha))
