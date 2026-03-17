extends Node2D

## Procedural 2D tree generator — thick, stout, gnarled trees.
## Adapted from julienduranleau-sandbox/procedural-2d-tree.
## Generates the tree structure once, then renders it with _draw().

const BARK_COLOR := Color(0.22, 0.13, 0.06)
const BARK_LIGHT := Color(0.3, 0.18, 0.08)

# Leaf colors — multi-layered, brighter in front
const LEAF_BACK := Color(0.15, 0.35, 0.1, 0.7)
const LEAF_MID := Color(0.2, 0.5, 0.15, 0.8)
const LEAF_FRONT := Color(0.3, 0.65, 0.2, 0.85)
const LEAF_BRIGHT := Color(0.4, 0.75, 0.25, 0.9)

@export var trunk_weight: float = 18.0
@export var trunk_length: float = 120.0
@export var max_recurse: int = 5
@export var seed_value: int = -1  # -1 = random

var _segments: Array = []  # [{start, end, weight, recurse, is_leaf}]
var _leaves: Array = []  # [{pos, size, color, layer}]
var _generated: bool = false


func _ready() -> void:
	if seed_value >= 0:
		seed(seed_value)
	_generate_tree(Vector2.ZERO, -PI / 2.0, trunk_weight, trunk_length, 0)
	_generated = true
	queue_redraw()


func _generate_tree(start: Vector2, angle: float, weight: float, length: float, recurse: int) -> void:
	if recurse > max_recurse:
		return

	# Draw trunk/branch as multiple short segments with random wobble
	var pos: Vector2 = start
	var seg_count: int = 8
	var seg_len: float = length / float(seg_count)

	for i in range(seg_count):
		var wobble: float = randf_range(-0.15, 0.15) * (0.3 + 0.1 * recurse)
		var seg_angle: float = angle + wobble
		var end_pos: Vector2 = pos + Vector2(cos(seg_angle), sin(seg_angle)) * seg_len

		_segments.append({
			"start": pos,
			"end": end_pos,
			"weight": weight,
			"recurse": recurse,
		})

		pos = end_pos

		# Random mid-branch splits (gnarled effect)
		if i > 2 and randf() > 0.6 and recurse < max_recurse - 1:
			var side_angle: float = angle + randf_range(-1.2, 1.2)
			var side_weight: float = weight * randf_range(0.4, 0.6)
			var side_length: float = length * randf_range(0.3, 0.5)
			_generate_tree(pos, side_angle, side_weight, side_length, recurse + 1)

	# End-of-branch splits
	var n_branches: int
	if recurse < 2:
		n_branches = randi_range(2, 4)  # Thick main splits
	elif recurse < 3:
		n_branches = randi_range(2, 5)
	else:
		n_branches = randi_range(1, 6)

	for _b in range(n_branches):
		if recurse >= max_recurse - 1:
			# Terminal — spawn leaves
			_spawn_leaf_cluster(pos, recurse)
			continue

		var angle_spread: float = PI * 0.25 + PI * 0.08 * recurse
		var branch_angle: float = angle + randf_range(-angle_spread, angle_spread)
		var branch_weight: float = weight * randf_range(0.55, 0.75)  # Slow decay = thicker
		var branch_length: float = length * randf_range(0.5, 0.75)
		_generate_tree(pos, branch_angle, branch_weight, branch_length, recurse + 1)


func _spawn_leaf_cluster(pos: Vector2, recurse: int) -> void:
	var cluster_size: int = randi_range(5, 12)
	for _i in range(cluster_size):
		var offset := Vector2(randf_range(-25, 25), randf_range(-25, 15))
		var size: float = randf_range(4, 12)
		# Layer: 0=back(dark), 1=mid, 2=front(bright)
		var layer: int = randi_range(0, 2)
		var col: Color
		match layer:
			0: col = LEAF_BACK
			1: col = LEAF_MID
			2:
				col = LEAF_FRONT if randf() > 0.3 else LEAF_BRIGHT
		_leaves.append({
			"pos": pos + offset,
			"size": size,
			"color": col,
			"layer": layer,
		})


func _draw() -> void:
	if not _generated:
		return

	# Draw back leaves first (darker, behind branches)
	for leaf in _leaves:
		if leaf["layer"] == 0:
			draw_circle(leaf["pos"], leaf["size"], leaf["color"])

	# Draw branches
	for seg in _segments:
		var col: Color = BARK_COLOR if seg["recurse"] % 2 == 0 else BARK_LIGHT
		draw_line(seg["start"], seg["end"], col, seg["weight"], true)

	# Draw mid leaves
	for leaf in _leaves:
		if leaf["layer"] == 1:
			draw_circle(leaf["pos"], leaf["size"], leaf["color"])

	# Draw front leaves (brightest, in front of branches)
	for leaf in _leaves:
		if leaf["layer"] == 2:
			draw_circle(leaf["pos"], leaf["size"], leaf["color"])
