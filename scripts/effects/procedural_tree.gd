extends Node2D

## Simple procedural 2D tree — thick trunk, few branches, big leaf circles.
## Designed for background decoration with minimal draw calls.

const BARK_COLOR := Color(0.22, 0.13, 0.06)
const BARK_LIGHT := Color(0.3, 0.18, 0.08)

@export var trunk_weight: float = 20.0
@export var trunk_length: float = 130.0
@export var seed_value: int = -1

var _branches: Array = []  # [{start, end, weight}]
var _leaves: Array = []  # [{pos, size, color}]


func _ready() -> void:
	if seed_value >= 0:
		seed(seed_value)
	_grow(Vector2.ZERO, -PI / 2.0, trunk_weight, trunk_length, 0)
	queue_redraw()


func _grow(start: Vector2, angle: float, weight: float, length: float, depth: int) -> void:
	if depth > 3 or weight < 3.0:
		return

	# Single line per branch section (with slight curve via wobble)
	var wobble: float = randf_range(-0.2, 0.2)
	var end: Vector2 = start + Vector2(cos(angle + wobble), sin(angle + wobble)) * length
	_branches.append({"start": start, "end": end, "weight": weight})

	if depth >= 2:
		# Terminal — add 1-2 big leaf circles
		var n_leaves: int = randi_range(1, 2)
		for _i in range(n_leaves):
			var leaf_offset := Vector2(randf_range(-15, 15), randf_range(-20, 5))
			var leaf_size: float = randf_range(18, 35)
			var green: float = randf_range(0.3, 0.7)
			var alpha: float = randf_range(0.5, 0.8)
			_leaves.append({
				"pos": end + leaf_offset,
				"size": leaf_size,
				"color": Color(0.15 + green * 0.3, 0.3 + green * 0.4, 0.1, alpha),
			})
		return

	# Split into 2-3 sub-branches
	var n_splits: int = randi_range(2, 3)
	for _b in range(n_splits):
		var spread: float = PI * 0.3
		var branch_angle: float = angle + randf_range(-spread, spread)
		var branch_weight: float = weight * randf_range(0.5, 0.7)
		var branch_length: float = length * randf_range(0.55, 0.75)
		_grow(end, branch_angle, branch_weight, branch_length, depth + 1)


func _draw() -> void:
	# Back leaves (behind branches)
	for leaf in _leaves:
		var back_col: Color = leaf["color"] * Color(0.7, 0.7, 0.7, 0.6)
		draw_circle(leaf["pos"] + Vector2(3, 3), leaf["size"] * 0.9, back_col)

	# Branches
	for b in _branches:
		draw_line(b["start"], b["end"], BARK_COLOR, b["weight"], true)
		# Slight highlight on one side
		var dir: Vector2 = (b["end"] - b["start"]).normalized()
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		draw_line(b["start"] + perp * b["weight"] * 0.3, b["end"] + perp * b["weight"] * 0.3, BARK_LIGHT, b["weight"] * 0.3, true)

	# Front leaves
	for leaf in _leaves:
		draw_circle(leaf["pos"], leaf["size"], leaf["color"])
