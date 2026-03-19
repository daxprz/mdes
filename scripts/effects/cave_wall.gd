extends StaticBody2D

## Procedural cave wall with curved floor-to-wall transition and a small ledge.
## Generates both visual (_draw) and collision (CollisionPolygon2D).
## The polygon fills from the screen edge inward to the curved surface.

@export var side: String = "left"  # "left" or "right"
@export var room_height: float = 900.0  # Floor y position (world space)
@export var room_top: float = 0.0  # Ceiling y position (world space)
@export var curve_width: float = 180.0  # How far the curve extends into the room
@export var ledge_height_ratio: float = 0.33  # Ledge at 1/3 up the wall
@export var ledge_depth: float = 55.0  # How far the ledge sticks out
@export var ledge_thickness: float = 30.0  # Vertical thickness of ledge
@export var undulation_amplitude: float = 8.0  # Waviness of the cave surface
@export var undulation_frequency: float = 3.0  # Number of wave cycles
@export var wall_color: Color = Color(0.28, 0.2, 0.15)
@export var wall_highlight: Color = Color(0.35, 0.27, 0.2)
@export var wall_dark: Color = Color(0.2, 0.14, 0.1)
@export var ledge_color: Color = Color(0.38, 0.28, 0.2)

var _surface_points: PackedVector2Array = PackedVector2Array()  # The inner curve edge
var _polygon: PackedVector2Array = PackedVector2Array()  # Full filled polygon for collision + draw
var _collision: CollisionPolygon2D = null


func _ready() -> void:
	collision_layer = 1  # World layer — same as floor, walls, platforms
	collision_mask = 0   # Static body doesn't detect
	_generate_wall()
	queue_redraw()


func _generate_wall() -> void:
	var is_left: bool = (side == "left")
	var segments: int = 40
	var floor_y: float = room_height - global_position.y
	var ceil_y: float = room_top - global_position.y
	var wall_height: float = floor_y - ceil_y
	var ledge_y: float = floor_y - wall_height * ledge_height_ratio

	# The wall edge (off-screen side). This is how deep the solid wall extends.
	# Left wall: solid fills from x=0 (this node) to the left (negative x).
	# Right wall: solid fills from x=0 (this node) to the right (positive x).
	var solid_depth: float = 60.0  # How thick the wall slab is behind the curve

	# Build the inner surface curve (the side players see and collide with)
	_surface_points.clear()
	for i in range(segments + 1):
		var t: float = float(i) / float(segments)  # 0=floor, 1=ceiling
		var y: float = lerpf(floor_y, ceil_y, t)

		# Curve: wide at floor, narrows to flat wall at top. Quadratic ease.
		var curve_factor: float = (1.0 - t) * (1.0 - t)
		var x_inward: float = curve_width * curve_factor

		# Undulation
		var undulation: float = sin(t * undulation_frequency * TAU) * undulation_amplitude
		undulation *= (1.0 - curve_factor * 0.5)  # Less waviness at floor
		x_inward += undulation

		# Ledge: flat shelf with steep sides
		var ledge_dist: float = y - ledge_y  # Positive = below ledge center
		if absf(ledge_dist) < ledge_thickness:
			var edge_zone: float = 6.0  # Steep transition at top/bottom edges
			var from_edge: float = ledge_thickness - absf(ledge_dist)
			if from_edge < edge_zone:
				# Steep ramp at edges
				x_inward += ledge_depth * (from_edge / edge_zone)
			else:
				# Flat plateau
				x_inward += ledge_depth

		# Direction: left wall curves right (+x), right wall curves left (-x)
		var px: float = x_inward if is_left else -x_inward
		_surface_points.append(Vector2(px, y))

	# Build the full solid polygon:
	# Surface curve (floor→ceiling) + flat back wall (ceiling→floor)
	_polygon.clear()

	# Surface edge: floor to ceiling
	for pt in _surface_points:
		_polygon.append(pt)

	# Back wall edge: ceiling down to floor (behind the surface)
	var back_x: float = -solid_depth if is_left else solid_depth
	_polygon.append(Vector2(back_x, ceil_y))
	_polygon.append(Vector2(back_x, floor_y))

	# Polygon auto-closes (last point → first point)

	# Create or update collision
	if _collision:
		_collision.polygon = _polygon
	else:
		_collision = CollisionPolygon2D.new()
		_collision.polygon = _polygon
		add_child(_collision)


func _draw() -> void:
	if _polygon.size() < 3:
		return

	# Fill the solid wall polygon
	var fill_colors := PackedColorArray()
	for i in range(_polygon.size()):
		fill_colors.append(wall_color)
	draw_polygon(_polygon, fill_colors)

	# Draw surface edge with highlight (the curved inner face)
	for i in range(_surface_points.size() - 1):
		draw_line(_surface_points[i], _surface_points[i + 1], wall_highlight, 2.5, true)

	# Darker shading near the back (depth effect)
	var is_left: bool = (side == "left")
	for i in range(_surface_points.size() - 1):
		var a: Vector2 = _surface_points[i]
		var b: Vector2 = _surface_points[i + 1]
		var back_dir: float = -8.0 if is_left else 8.0
		var a2: Vector2 = a + Vector2(back_dir, 0)
		var b2: Vector2 = b + Vector2(back_dir, 0)
		draw_line(a2, b2, wall_dark, 1.5, true)

	# Ledge accent: thicker highlight at ledge height
	var floor_y: float = room_height - global_position.y
	var ceil_y: float = room_top - global_position.y
	var wall_height: float = floor_y - ceil_y
	var ledge_y: float = floor_y - wall_height * ledge_height_ratio
	for i in range(_surface_points.size() - 1):
		var a: Vector2 = _surface_points[i]
		var b: Vector2 = _surface_points[i + 1]
		if absf(a.y - ledge_y) < ledge_thickness:
			draw_line(a, b, ledge_color, 4.0, true)
			# Top surface of ledge (flat-ish)
			if absf(a.y - (ledge_y - ledge_thickness * 0.5)) < 4.0:
				draw_line(a, b, wall_highlight * Color(1.2, 1.2, 1.2), 2.0, true)

	# Rock texture marks
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(global_position)
	for i in range(30):
		var idx: int = rng.randi_range(0, _surface_points.size() - 1)
		var pt: Vector2 = _surface_points[idx]
		var inward: float = -1.0 if is_left else 1.0
		var offset := Vector2(rng.randf_range(2, 12) * inward, rng.randf_range(-3, 3))
		var len_x: float = rng.randf_range(4, 10) * inward
		draw_line(pt + offset, pt + offset + Vector2(len_x, rng.randf_range(-2, 2)),
			wall_dark * Color(1, 1, 1, 0.5), 1.0)
