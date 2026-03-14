extends Camera2D

## Camera that dynamically pans and zooms to keep all players on screen.

@export var min_zoom: float = 0.4
@export var max_zoom: float = 1.5
@export var zoom_margin: Vector2 = Vector2(120, 100)  # Extra padding around players
@export var smooth_speed: float = 4.0

var _target_pos := Vector2.ZERO
var _target_zoom := 1.0


func _process(delta: float) -> void:
	var players := _get_player_positions()
	if players.is_empty():
		return

	# Find bounding box of all players
	var min_pos := players[0]
	var max_pos := players[0]
	for p in players:
		min_pos.x = min(min_pos.x, p.x)
		min_pos.y = min(min_pos.y, p.y)
		max_pos.x = max(max_pos.x, p.x)
		max_pos.y = max(max_pos.y, p.y)

	# Target position = center of all players
	_target_pos = (min_pos + max_pos) / 2.0

	# Target zoom = fit all players + margin into viewport
	var viewport_size: Vector2 = get_viewport_rect().size
	var spread: Vector2 = max_pos - min_pos + zoom_margin * 2.0

	var zoom_x: float = viewport_size.x / maxf(spread.x, 1.0)
	var zoom_y: float = viewport_size.y / maxf(spread.y, 1.0)
	_target_zoom = clampf(minf(zoom_x, zoom_y), min_zoom, max_zoom)

	# Smooth lerp toward target
	global_position = global_position.lerp(_target_pos, smooth_speed * delta)
	zoom = zoom.lerp(Vector2(_target_zoom, _target_zoom), smooth_speed * delta)


func _get_player_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for node in get_tree().get_nodes_in_group("players"):
		if node is Node2D:
			positions.append(node.global_position)
	# Also include donut buddies
	for node in get_tree().get_nodes_in_group("donut_buddies"):
		if node is Node2D:
			positions.append(node.global_position)
	return positions
