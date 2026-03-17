extends Node2D

## Simple procedural 2D tree — thick trunk, few branches, huge leaf canopy.
## Designed for background decoration with minimal draw calls.

const BARK_COLOR := Color(0.22, 0.13, 0.06)
const BARK_LIGHT := Color(0.3, 0.18, 0.08)

const LEAF_DARK := Color(0.12, 0.28, 0.08)    # Darkest background
const LEAF_MID := Color(0.18, 0.4, 0.12)      # Middle layer
const LEAF_BRIGHT := Color(0.28, 0.55, 0.18)  # Foreground, brightest

@export var trunk_weight: float = 20.0
@export var trunk_length: float = 200.0
@export var seed_value: int = -1

var _branches: Array = []
var _leaves: Array = []  # [{pos, size, color, layer}]


func _ready() -> void:
	_generate()


func regenerate(new_seed: int) -> void:
	seed_value = new_seed
	_branches.clear()
	_leaves.clear()
	_generate()
	queue_redraw()


func _generate() -> void:
	if seed_value >= 0:
		seed(seed_value)
	_grow(Vector2.ZERO, -PI / 2.0, trunk_weight, trunk_length, 0)

	# Canopy centered around the top of the tree
	var canopy_y: float = -trunk_length * 1.3

	# Ultra-large dark background circles
	for _i in range(3):
		_leaves.append({
			"pos": Vector2(randf_range(-80, 80), canopy_y + randf_range(-100, 20)),
			"size": randf_range(70, 110),
			"color": LEAF_DARK,
			"layer": 0,
		})

	# Mid-layer circles
	for _i in range(4):
		_leaves.append({
			"pos": Vector2(randf_range(-60, 60), canopy_y + randf_range(-80, 30)),
			"size": randf_range(50, 75),
			"color": LEAF_MID,
			"layer": 1,
		})

	# Bright foreground circles
	for _i in range(4):
		_leaves.append({
			"pos": Vector2(randf_range(-50, 50), canopy_y + randf_range(-60, 40)),
			"size": randf_range(35, 55),
			"color": LEAF_BRIGHT,
			"layer": 2,
		})

	queue_redraw()


func _grow(start: Vector2, angle: float, weight: float, length: float, depth: int) -> void:
	if depth > 4 or weight < 3.0:
		return

	# Draw multiple bending segments before splitting
	var pos: Vector2 = start
	var cur_angle: float = angle
	var n_bends: int = randi_range(2, 4)
	var seg_len: float = length / float(n_bends)

	for i in range(n_bends):
		var wobble: float = randf_range(-0.25, 0.25)
		cur_angle += wobble
		var end: Vector2 = pos + Vector2(cos(cur_angle), sin(cur_angle)) * seg_len
		_branches.append({"start": pos, "end": end, "weight": weight})
		pos = end

	if depth >= 3:
		# Terminal — add 1 large leaf circle
		_leaves.append({
			"pos": pos + Vector2(randf_range(-10, 10), randf_range(-15, 5)),
			"size": randf_range(30, 50),
			"color": LEAF_MID if randf() > 0.5 else LEAF_BRIGHT,
			"layer": 1 if randf() > 0.5 else 2,
		})
		return

	var n_splits: int = randi_range(2, 3)
	for _b in range(n_splits):
		var spread: float = PI * 0.3
		var branch_angle: float = cur_angle + randf_range(-spread, spread)
		var branch_weight: float = weight * randf_range(0.5, 0.7)
		var branch_length: float = length * randf_range(0.5, 0.7)
		_grow(pos, branch_angle, branch_weight, branch_length, depth + 1)


func _draw() -> void:
	# Layer 0: dark background canopy
	for leaf in _leaves:
		if leaf["layer"] == 0:
			draw_circle(leaf["pos"], leaf["size"], leaf["color"])

	# Branches
	for b in _branches:
		draw_line(b["start"], b["end"], BARK_COLOR, b["weight"], true)
		var dir: Vector2 = (b["end"] - b["start"]).normalized()
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		draw_line(b["start"] + perp * b["weight"] * 0.3, b["end"] + perp * b["weight"] * 0.3, BARK_LIGHT, b["weight"] * 0.3, true)

	# Layer 1: mid canopy
	for leaf in _leaves:
		if leaf["layer"] == 1:
			draw_circle(leaf["pos"], leaf["size"], leaf["color"])

	# Layer 2: bright foreground canopy
	for leaf in _leaves:
		if leaf["layer"] == 2:
			draw_circle(leaf["pos"], leaf["size"], leaf["color"])
