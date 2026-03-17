extends Node2D

## Simple procedural 2D tree — thick trunk, few branches, huge leaf canopy.
## Designed for background decoration with minimal draw calls.

const BARK_COLOR := Color(0.22, 0.13, 0.06)
const BARK_LIGHT := Color(0.3, 0.18, 0.08)

const LEAF_DARK := Color(0.12, 0.28, 0.08)    # Darkest background
const LEAF_MID := Color(0.18, 0.4, 0.12)      # Middle layer
const LEAF_BRIGHT := Color(0.28, 0.55, 0.18)  # Foreground, brightest

@export var trunk_weight: float = 20.0
@export var trunk_length: float = 130.0
@export var seed_value: int = -1

var _branches: Array = []
var _leaves: Array = []  # [{pos, size, color, layer}]


func _ready() -> void:
	if seed_value >= 0:
		seed(seed_value)
	_grow(Vector2.ZERO, -PI / 2.0, trunk_weight, trunk_length, 0)

	# Add a few ultra-large dark background canopy circles
	for _i in range(3):
		_leaves.append({
			"pos": Vector2(randf_range(-60, 60), -trunk_length + randf_range(-80, -20)),
			"size": randf_range(60, 90),
			"color": LEAF_DARK,
			"layer": 0,
		})

	# Add mid-layer circles
	for _i in range(4):
		_leaves.append({
			"pos": Vector2(randf_range(-50, 50), -trunk_length + randf_range(-70, 0)),
			"size": randf_range(40, 65),
			"color": LEAF_MID,
			"layer": 1,
		})

	# Add bright foreground circles
	for _i in range(4):
		_leaves.append({
			"pos": Vector2(randf_range(-40, 40), -trunk_length + randf_range(-60, 10)),
			"size": randf_range(30, 50),
			"color": LEAF_BRIGHT,
			"layer": 2,
		})

	queue_redraw()


func _grow(start: Vector2, angle: float, weight: float, length: float, depth: int) -> void:
	if depth > 3 or weight < 3.0:
		return

	var wobble: float = randf_range(-0.2, 0.2)
	var end: Vector2 = start + Vector2(cos(angle + wobble), sin(angle + wobble)) * length
	_branches.append({"start": start, "end": end, "weight": weight})

	if depth >= 2:
		# Terminal — add 1 large leaf circle at the end
		_leaves.append({
			"pos": end + Vector2(randf_range(-10, 10), randf_range(-15, 5)),
			"size": randf_range(30, 50),
			"color": LEAF_MID if randf() > 0.5 else LEAF_BRIGHT,
			"layer": 1 if randf() > 0.5 else 2,
		})
		return

	var n_splits: int = randi_range(2, 3)
	for _b in range(n_splits):
		var spread: float = PI * 0.3
		var branch_angle: float = angle + randf_range(-spread, spread)
		var branch_weight: float = weight * randf_range(0.5, 0.7)
		var branch_length: float = length * randf_range(0.55, 0.75)
		_grow(end, branch_angle, branch_weight, branch_length, depth + 1)


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
