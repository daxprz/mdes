extends Node2D

## Procedural vector rock generator using faceted plane shading.
## Irregular silhouette with 3-4 flat planes, directional lighting,
## crack lines between facets, and edge highlights.

@export var rock_size: float = 60.0  # Base radius (bigger default)
@export var seed_value: int = -1
@export var hue: String = "grey"  # "grey" or "red"
@export var light_direction: Vector2 = Vector2(-0.6, -0.8)  # Configurable light angle
@export var highlight_intensity: float = 1.0  # 0.0 = no highlights, 1.0 = normal, 2.0 = strong
@export var highlight_width: float = 2.0  # Edge highlight line thickness

# Color palettes
const GREY_PALETTE := {
	"shadow": Color(0.18, 0.17, 0.16),
	"base": Color(0.35, 0.33, 0.3),
	"lit": Color(0.52, 0.5, 0.45),
	"highlight": Color(0.7, 0.68, 0.6),
}
const RED_PALETTE := {
	"shadow": Color(0.25, 0.12, 0.1),
	"base": Color(0.45, 0.25, 0.18),
	"lit": Color(0.6, 0.4, 0.28),
	"highlight": Color(0.78, 0.6, 0.42),
}

var _silhouette: PackedVector2Array = []  # Outer rock shape
var _facets: Array = []  # [{points: PackedVector2Array, shade: String}]
var _cracks: Array = []  # [{from: Vector2, to: Vector2}]
var _edge_highlights: Array = []  # [{from: Vector2, to: Vector2}]
var _palette: Dictionary = {}


func _ready() -> void:
	_generate()
	queue_redraw()


func regenerate(new_seed: int) -> void:
	seed_value = new_seed
	_silhouette = PackedVector2Array()
	_facets.clear()
	_cracks.clear()
	_edge_highlights.clear()
	_generate()
	queue_redraw()


func _generate() -> void:
	if seed_value >= 0:
		seed(seed_value)

	_palette = RED_PALETTE if hue == "red" else GREY_PALETTE

	# Step 1: Generate irregular silhouette
	_generate_silhouette()

	# Step 2: Define facet planes by splitting the silhouette
	_generate_facets()

	# Step 3: Generate crack lines between facets
	_generate_cracks()

	# Step 4: Edge highlights on light-facing edges
	_generate_edge_highlights()


func _generate_silhouette() -> void:
	# Irregular polygon — 7-10 vertices with random radii
	var n_verts: int = randi_range(7, 10)
	_silhouette = PackedVector2Array()
	for i in range(n_verts):
		var angle: float = (float(i) / float(n_verts)) * TAU
		# Vary radius for irregularity — rocks aren't round
		var r: float = rock_size * randf_range(0.6, 1.1)
		# Flatten bottom slightly (rocks sit on ground)
		if angle > PI * 0.3 and angle < PI * 0.7:
			r *= 0.85
		_silhouette.append(Vector2(cos(angle) * r, sin(angle) * r))


func _generate_facets() -> void:
	# Split the rock into 3-4 facet regions using internal division lines
	# Each facet is a polygon that covers part of the silhouette
	# Light comes from top-left: facets facing up-left are brightest

	var center := Vector2.ZERO
	for pt in _silhouette:
		center += pt
	center /= _silhouette.size()

	# Pick 2-3 internal split points to create facets
	var n_splits: int = randi_range(2, 3)
	var split_points: Array[Vector2] = []
	for _i in range(n_splits):
		split_points.append(Vector2(
			randf_range(-rock_size * 0.3, rock_size * 0.3),
			randf_range(-rock_size * 0.3, rock_size * 0.3)
		))

	# Create facets by grouping silhouette vertices by which split point they're nearest
	# Then build polygon for each group
	var groups: Dictionary = {}  # split_index -> [vertex indices]
	for vi in range(_silhouette.size()):
		var pt: Vector2 = _silhouette[vi]
		var best_si: int = 0
		var best_dist: float = INF
		for si in range(split_points.size()):
			var d: float = pt.distance_to(split_points[si])
			if d < best_dist:
				best_dist = d
				best_si = si
		if not groups.has(best_si):
			groups[best_si] = []
		groups[best_si].append(vi)

	# Build facet polygons
	for si in groups:
		var indices: Array = groups[si]
		if indices.size() < 3:
			continue

		var facet_pts := PackedVector2Array()
		# Add the silhouette vertices for this group
		for vi in indices:
			facet_pts.append(_silhouette[vi])
		# Add the split point as a central vertex
		facet_pts.append(split_points[si])

		# Sort points by angle around their centroid for proper polygon
		var facet_center := Vector2.ZERO
		for pt in facet_pts:
			facet_center += pt
		facet_center /= facet_pts.size()

		var sorted_pts: Array[Vector2] = []
		for pt in facet_pts:
			sorted_pts.append(pt)
		sorted_pts.sort_custom(func(a: Vector2, b: Vector2) -> bool:
			return (a - facet_center).angle() < (b - facet_center).angle()
		)
		facet_pts = PackedVector2Array(sorted_pts)

		# Determine shade based on facet direction relative to light
		var facet_dir: Vector2 = (facet_center - center).normalized()
		var light_norm: Vector2 = light_direction.normalized()
		var light_dot: float = facet_dir.dot(light_norm)

		var shade: String
		if light_dot > 0.3:
			shade = "highlight"
		elif light_dot > -0.1:
			shade = "lit"
		elif light_dot > -0.5:
			shade = "base"
		else:
			shade = "shadow"

		_facets.append({"points": facet_pts, "shade": shade})


func _generate_cracks() -> void:
	# Crack lines between facets — thin dark lines along internal boundaries
	for fi in range(_facets.size()):
		var pts: PackedVector2Array = _facets[fi]["points"]
		if pts.size() < 3:
			continue
		# Pick 1-2 edges that are internal (not on the silhouette boundary)
		for ei in range(mini(2, pts.size() - 1)):
			var idx: int = randi_range(0, pts.size() - 1)
			var a: Vector2 = pts[idx]
			var b: Vector2 = pts[(idx + 1) % pts.size()]
			# Only draw if both points are reasonably internal
			if a.length() < rock_size * 0.9 or b.length() < rock_size * 0.9:
				_cracks.append({"from": a, "to": b})


func _generate_edge_highlights() -> void:
	var light_norm: Vector2 = light_direction.normalized()
	for i in range(_silhouette.size()):
		var a: Vector2 = _silhouette[i]
		var b: Vector2 = _silhouette[(i + 1) % _silhouette.size()]
		var edge_dir: Vector2 = (b - a).normalized()
		var edge_normal: Vector2 = Vector2(-edge_dir.y, edge_dir.x)
		if edge_normal.dot(light_norm) > 0.2:
			_edge_highlights.append({"from": a, "to": b})


func _draw() -> void:
	if _silhouette.is_empty():
		return

	# 1. Draw full silhouette as shadow base
	var shadow_colors := PackedColorArray()
	for _i in range(_silhouette.size()):
		shadow_colors.append(_palette["shadow"])
	draw_polygon(_silhouette, shadow_colors)

	# 2. Draw each facet with its shade
	for facet in _facets:
		var pts: PackedVector2Array = facet["points"]
		if pts.size() < 3:
			continue
		var colors := PackedColorArray()
		for _i in range(pts.size()):
			colors.append(_palette[facet["shade"]])
		draw_polygon(pts, colors)

	# 3. Draw crack lines
	for crack in _cracks:
		draw_line(crack["from"], crack["to"], _palette["shadow"], 1.5)

	# 4. Draw silhouette outline
	for i in range(_silhouette.size()):
		var a: Vector2 = _silhouette[i]
		var b: Vector2 = _silhouette[(i + 1) % _silhouette.size()]
		draw_line(a, b, _palette["shadow"] * Color(0.8, 0.8, 0.8), 1.5)

	# 5. Draw edge highlights (configurable intensity and width)
	if highlight_intensity > 0.0:
		var hl_color: Color = _palette["highlight"]
		hl_color.a = clampf(highlight_intensity, 0.0, 1.0)
		for eh in _edge_highlights:
			draw_line(eh["from"], eh["to"], hl_color, highlight_width * highlight_intensity)
