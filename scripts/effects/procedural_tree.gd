extends Node2D

## Simple procedural 2D tree — thick trunk, few branches, huge leaf canopy.
## Designed for background decoration with minimal draw calls.
## All generation parameters are configurable — defaults produce a classic oak shape.
##
## Per-instance settings (from level JSON):
##   seed         — random seed for deterministic generation
##   trunk_weight — trunk thickness at base (px)
##   trunk_length — trunk height (px)
##
## Shape tuning:
##   max_depth        — max branching recursion depth (more = bushier)
##   min_weight       — branches thinner than this stop growing
##   bend_min/max     — number of bending segments per branch section
##   wobble           — max angular deviation per bend (radians)
##   split_min/max    — number of child branches at each split
##   spread           — angular spread of child branches (radians)
##   decay_min/max    — weight/length multiplier range per split
##
## Canopy tuning:
##   canopy_offset    — Y offset multiplier for canopy center (relative to trunk_length)
##   canopy_layers    — [{count, size_min, size_max, spread_x, spread_y_min, spread_y_max}]
##
## Colors:
##   bark_color, bark_highlight — trunk/branch colors
##   leaf_colors                — Array of 3 colors [dark, mid, bright] for canopy layers

# -- Colors (configurable) ----------------------------------------------------

@export var bark_color: Color = Color(0.22, 0.13, 0.06)
@export var bark_highlight: Color = Color(0.3, 0.18, 0.08)
@export var leaf_colors: Array[Color] = [
	Color(0.12, 0.28, 0.08),   # Layer 0: dark background
	Color(0.18, 0.4, 0.12),    # Layer 1: mid
	Color(0.28, 0.55, 0.18),   # Layer 2: bright foreground
]

# -- Trunk (configurable per-instance) ----------------------------------------

@export var trunk_weight: float = 20.0
@export var trunk_length: float = 200.0
@export var seed_value: int = -1

# -- Branching shape -----------------------------------------------------------

@export var max_depth: int = 4
@export var min_weight: float = 3.0
@export var bend_min: int = 2
@export var bend_max: int = 4
@export var wobble: float = 0.25          # Max radians per bend
@export var split_min: int = 2
@export var split_max: int = 3
@export var spread: float = 0.94          # ~PI * 0.3 radians
@export var decay_min: float = 0.5        # Weight/length shrink per split (min)
@export var decay_max: float = 0.7        # Weight/length shrink per split (max)

# -- Canopy shape --------------------------------------------------------------

@export var canopy_offset: float = 1.3    # Canopy center = -trunk_length * this
@export var canopy_layers: Array[Dictionary] = [
	{"count": 3, "size_min": 70.0, "size_max": 110.0, "spread_x": 80.0, "spread_y_min": -100.0, "spread_y_max": 20.0},
	{"count": 4, "size_min": 50.0, "size_max": 75.0,  "spread_x": 60.0, "spread_y_min": -80.0,  "spread_y_max": 30.0},
	{"count": 4, "size_min": 35.0, "size_max": 55.0,  "spread_x": 50.0, "spread_y_min": -60.0,  "spread_y_max": 40.0},
]

# -- Generated data (internal) ------------------------------------------------

var _branches: Array = []
var _leaves: Array = []  # [{pos, size, color, layer}]


func _ready() -> void:
	_generate()


func regenerate(new_seed: int = -1) -> void:
	if new_seed >= 0:
		seed_value = new_seed
	_branches.clear()
	_leaves.clear()
	_generate()
	queue_redraw()


func load_blueprint(blueprint_name: String) -> bool:
	## Load shape parameters from a named blueprint file.
	## Checks user:// first (custom), then res:// (bundled).
	var paths: Array[String] = [
		"user://tree_blueprints/%s.json" % blueprint_name,
		"res://data/tree_blueprints/%s.json" % blueprint_name,
	]
	for path in paths:
		if not FileAccess.file_exists(path):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if not file:
			continue
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
			apply_config(json.data)
			return true
	return false


static func get_blueprint_names() -> Array[String]:
	## Scan both bundled and custom directories for available tree blueprints.
	var names: Array[String] = []
	for dir_path in ["res://data/tree_blueprints/", "user://tree_blueprints/"]:
		var dir := DirAccess.open(dir_path)
		if dir:
			dir.list_dir_begin()
			var fname: String = dir.get_next()
			while fname != "":
				if fname.ends_with(".json"):
					var bname: String = fname.get_basename()
					if bname not in names:
						names.append(bname)
				fname = dir.get_next()
			dir.list_dir_end()
	names.sort()
	return names


func save_blueprint(blueprint_name: String, use_original: bool = false) -> void:
	## Save current shape parameters as a blueprint file.
	var cfg: Dictionary = to_config()
	cfg.erase("seed")  # Seed is per-instance, not part of blueprint
	var path: String
	if use_original:
		path = "res://data/tree_blueprints/%s.json" % blueprint_name
	else:
		path = "user://tree_blueprints/%s.json" % blueprint_name
		DirAccess.make_dir_recursive_absolute("user://tree_blueprints")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(cfg, "\t"))


func apply_config(cfg: Dictionary) -> void:
	## Apply a config dictionary (from level JSON or editor). Regenerates.
	## If cfg contains "blueprint", loads that blueprint first, then applies overrides.
	if cfg.has("blueprint"):
		load_blueprint(str(cfg["blueprint"]))
	trunk_weight = cfg.get("trunk_weight", trunk_weight)
	trunk_length = cfg.get("trunk_length", trunk_length)
	seed_value = int(cfg.get("seed", seed_value))
	max_depth = int(cfg.get("max_depth", max_depth))
	min_weight = cfg.get("min_weight", min_weight)
	bend_min = int(cfg.get("bend_min", bend_min))
	bend_max = int(cfg.get("bend_max", bend_max))
	wobble = cfg.get("wobble", wobble)
	split_min = int(cfg.get("split_min", split_min))
	split_max = int(cfg.get("split_max", split_max))
	spread = cfg.get("spread", spread)
	decay_min = cfg.get("decay_min", decay_min)
	decay_max = cfg.get("decay_max", decay_max)
	canopy_offset = cfg.get("canopy_offset", canopy_offset)
	if cfg.has("bark_color") and cfg["bark_color"] is Array:
		bark_color = Color(cfg["bark_color"][0], cfg["bark_color"][1], cfg["bark_color"][2])
	if cfg.has("bark_highlight") and cfg["bark_highlight"] is Array:
		bark_highlight = Color(cfg["bark_highlight"][0], cfg["bark_highlight"][1], cfg["bark_highlight"][2])
	if cfg.has("leaf_colors") and cfg["leaf_colors"] is Array:
		for i in range(mini(cfg["leaf_colors"].size(), leaf_colors.size())):
			var c: Array = cfg["leaf_colors"][i]
			leaf_colors[i] = Color(c[0], c[1], c[2])
	if cfg.has("canopy_layers") and cfg["canopy_layers"] is Array:
		canopy_layers.clear()
		for layer in cfg["canopy_layers"]:
			canopy_layers.append(layer)
	regenerate()


func to_config() -> Dictionary:
	## Export current settings as a config dictionary (for saving to JSON).
	var lc: Array = []
	for c in leaf_colors:
		lc.append([c.r, c.g, c.b])
	return {
		"seed": seed_value,
		"trunk_weight": trunk_weight,
		"trunk_length": trunk_length,
		"max_depth": max_depth,
		"min_weight": min_weight,
		"bend_min": bend_min,
		"bend_max": bend_max,
		"wobble": wobble,
		"split_min": split_min,
		"split_max": split_max,
		"spread": spread,
		"decay_min": decay_min,
		"decay_max": decay_max,
		"canopy_offset": canopy_offset,
		"bark_color": [bark_color.r, bark_color.g, bark_color.b],
		"bark_highlight": [bark_highlight.r, bark_highlight.g, bark_highlight.b],
		"leaf_colors": lc,
		"canopy_layers": canopy_layers.duplicate(true),
	}


# -- Generation ----------------------------------------------------------------

func _generate() -> void:
	if seed_value >= 0:
		seed(seed_value)
	_grow(Vector2.ZERO, -PI / 2.0, trunk_weight, trunk_length, 0)

	# Canopy centered around the top of the tree
	var canopy_y: float = -trunk_length * canopy_offset

	for layer_idx in range(canopy_layers.size()):
		var layer: Dictionary = canopy_layers[layer_idx]
		var count: int = int(layer.get("count", 3))
		var size_min: float = layer.get("size_min", 40.0)
		var size_max: float = layer.get("size_max", 80.0)
		var sx: float = layer.get("spread_x", 60.0)
		var sy_min: float = layer.get("spread_y_min", -80.0)
		var sy_max: float = layer.get("spread_y_max", 20.0)
		var col: Color = leaf_colors[layer_idx] if layer_idx < leaf_colors.size() else Color(0.2, 0.4, 0.15)
		for _i in range(count):
			_leaves.append({
				"pos": Vector2(randf_range(-sx, sx), canopy_y + randf_range(sy_min, sy_max)),
				"size": randf_range(size_min, size_max),
				"color": col,
				"layer": layer_idx,
			})

	queue_redraw()


func _grow(start: Vector2, angle: float, weight: float, length: float, depth: int) -> void:
	if depth > max_depth or weight < min_weight:
		return

	# Draw multiple bending segments before splitting
	var pos: Vector2 = start
	var cur_angle: float = angle
	var n_bends: int = randi_range(bend_min, bend_max)
	var seg_len: float = length / float(n_bends)

	for i in range(n_bends):
		var w: float = randf_range(-wobble, wobble)
		cur_angle += w
		var end: Vector2 = pos + Vector2(cos(cur_angle), sin(cur_angle)) * seg_len
		_branches.append({"start": pos, "end": end, "weight": weight})
		pos = end

	if depth >= max_depth - 1:
		# Terminal — add 1 large leaf circle
		var col: Color = leaf_colors[1] if randf() > 0.5 and leaf_colors.size() > 1 else (leaf_colors[2] if leaf_colors.size() > 2 else leaf_colors[0])
		_leaves.append({
			"pos": pos + Vector2(randf_range(-10, 10), randf_range(-15, 5)),
			"size": randf_range(30, 50),
			"color": col,
			"layer": 1 if randf() > 0.5 else 2,
		})
		return

	var n_splits: int = randi_range(split_min, split_max)
	for _b in range(n_splits):
		var branch_angle: float = cur_angle + randf_range(-spread, spread)
		var branch_weight: float = weight * randf_range(decay_min, decay_max)
		var branch_length: float = length * randf_range(decay_min, decay_max)
		_grow(pos, branch_angle, branch_weight, branch_length, depth + 1)


# -- Drawing -------------------------------------------------------------------

func _draw() -> void:
	# Layer 0: dark background canopy
	for leaf in _leaves:
		if leaf["layer"] == 0:
			draw_circle(leaf["pos"], leaf["size"], leaf["color"])

	# Branches
	for b in _branches:
		draw_line(b["start"], b["end"], bark_color, b["weight"], true)
		var dir: Vector2 = (b["end"] - b["start"]).normalized()
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		draw_line(b["start"] + perp * b["weight"] * 0.3, b["end"] + perp * b["weight"] * 0.3, bark_highlight, b["weight"] * 0.3, true)

	# Layer 1: mid canopy
	for leaf in _leaves:
		if leaf["layer"] == 1:
			draw_circle(leaf["pos"], leaf["size"], leaf["color"])

	# Layer 2: bright foreground canopy
	for leaf in _leaves:
		if leaf["layer"] == 2:
			draw_circle(leaf["pos"], leaf["size"], leaf["color"])
