extends Node2D

## Collaborative debug whiteboard — data model + renderer.
## Renders a coordinate grid and user/AI-created components (points, lines,
## shapes, arrows, vectors, normals) with annotations and grouping.
## Decoupled from game systems — works as a standalone overlay on any level.

# -- Grid settings --
const GRID_MINOR := 20.0
const GRID_MAJOR := 100.0
const GRID_MINOR_COLOR := Color(0.15, 0.15, 0.2, 0.15)
const GRID_MAJOR_COLOR := Color(0.2, 0.25, 0.35, 0.3)
const GRID_AXIS_COLOR := Color(0.3, 0.4, 0.55, 0.4)
const GRID_LABEL_COLOR := Color(0.35, 0.4, 0.5, 0.5)
const GRID_LABEL_SIZE := 8

# -- Component defaults --
const DEFAULT_COLOR := "#ff4444"
const DEFAULT_LINE_WIDTH := 2.0
const DEFAULT_POINT_RADIUS := 4.0
const DEFAULT_HEAD_SIZE := 12.0
const DEFAULT_NORMAL_LENGTH := 30.0
const DEFAULT_ARC_SEGMENTS := 48
const BEZIER_SAMPLES := 32

# -- Annotation rendering --
const ANNOTATION_BG := Color(0.06, 0.06, 0.1, 0.85)
const ANNOTATION_BORDER := Color(0.2, 0.25, 0.35, 0.6)
const ANNOTATION_H_COLOR := Color(0.3, 0.85, 0.9)  # Cyan for Human
const ANNOTATION_A_COLOR := Color(1.0, 0.65, 0.2)   # Orange for AI
const ANNOTATION_TEXT_COLOR := Color(0.8, 0.8, 0.8)
const ANNOTATION_FONT_SIZE := 9
const ANNOTATION_LINE_HEIGHT := 13
const ANNOTATION_PADDING := 4
const ANNOTATION_OFFSET := Vector2(20, -30)  # Offset from component centroid
const ANNOTATION_MAX_WIDTH := 260

# -- Selection --
const SELECTION_EXTRA_WIDTH := 2.0
const SELECTION_PULSE_SPEED := 4.0

# -- Control points --
const CP_SIZE := 5.0
const CP_FILL := Color(1.0, 1.0, 1.0, 0.9)
const CP_OUTLINE := Color(0.0, 0.0, 0.0, 0.8)
const CP_CENTER_FILL := Color(0.3, 0.7, 1.0, 0.9)  # Blue for center/origin handles

# -- Selection rectangle --
const SELECTION_RECT_FILL := Color(0.3, 0.5, 1.0, 0.08)
const SELECTION_RECT_BORDER := Color(0.3, 0.5, 1.0, 0.4)

# -- State --
var _name: String = "untitled"
var _components: Array[Dictionary] = []
var _next_id: int = 1
var _grid_visible: bool = true
var _font: Font = null
var _preview_component: Dictionary = {}  # Ghost component from tools (rendered semi-transparent)
var _selection_rect: Rect2 = Rect2()     # Current multi-select rectangle (for rendering)
var _lasso_points: PackedVector2Array = PackedVector2Array()  # Lasso polygon (world coords)
var _cursor_indicator: Dictionary = {}   # {pos: Vector2, type: "add"|"remove"} for +/- cursor

# -- Layers --
var _layers: Array[Dictionary] = []
var _next_layer_id: int = 1
var _next_group_id: int = 1
var _active_layer_id: int = -1  # ID of the active layer (new components go here)


# -- Named color lookup (RCON-friendly names) --
const NAMED_COLORS := {
	# Vivid spectrum
	"red": "#ff4444", "orange": "#ff8844", "gold": "#ffcc44",
	"yellow": "#ffff44", "lime": "#88ff44", "green": "#44ff44",
	"cyan": "#44ffff", "blue": "#4488ff", "purple": "#aa44ff",
	"magenta": "#ff44ff", "pink": "#ff88aa", "white": "#ffffff",
	# Earth tones
	"maroon": "#661a1e", "brown": "#8c5429", "tan": "#d1ad75",
	"olive": "#808033", "teal": "#338080", "navy": "#212259",
	# Greys
	"charcoal": "#2e2e33", "dark_grey": "#4d4d4d", "slate": "#66667f",
	"steel": "#738ca6", "grey": "#808080", "gray": "#808080",
	"light_grey": "#bfbfbf", "black": "#000000",
}


func _ready() -> void:
	z_index = 100  # Above game content, below debug overlays (4096)
	_font = ThemeDB.fallback_font
	if _layers.is_empty():
		_ensure_default_layer()


# ============================================================================
# PUBLIC API — Component Creation
# ============================================================================

func add_point(x: float, y: float, color: String = DEFAULT_COLOR, label: String = "") -> int:
	var c := _make_base("point", color, label)
	c["x"] = x
	c["y"] = y
	c["radius"] = DEFAULT_POINT_RADIUS
	_register_component(c)
	queue_redraw()
	return c["id"]


func add_text(x: float, y: float, text: String = "", font_size: int = 14, color: String = DEFAULT_COLOR) -> int:
	var c := _make_base("text", color, "")
	c["x"] = x
	c["y"] = y
	c["text"] = text
	c["font_size"] = font_size
	_register_component(c)
	queue_redraw()
	return c["id"]


func add_line(x1: float, y1: float, x2: float, y2: float, color: String = DEFAULT_COLOR, label: String = "") -> int:
	var c := _make_base("line", color, label)
	c["x1"] = x1; c["y1"] = y1
	c["x2"] = x2; c["y2"] = y2
	_register_component(c)
	queue_redraw()
	return c["id"]


func add_rect(x: float, y: float, w: float, h: float, color: String = DEFAULT_COLOR, label: String = "") -> int:
	var c := _make_base("rect", color, label)
	c["x"] = x; c["y"] = y
	c["w"] = w; c["h"] = h
	_register_component(c)
	queue_redraw()
	return c["id"]


func add_circle(cx: float, cy: float, r: float, color: String = DEFAULT_COLOR, label: String = "") -> int:
	var c := _make_base("circle", color, label)
	c["cx"] = cx; c["cy"] = cy; c["r"] = r
	_register_component(c)
	queue_redraw()
	return c["id"]


func add_ellipse(cx: float, cy: float, rx: float, ry: float, color: String = DEFAULT_COLOR, label: String = "") -> int:
	var c := _make_base("ellipse", color, label)
	c["cx"] = cx; c["cy"] = cy
	c["rx"] = rx; c["ry"] = ry
	_register_component(c)
	queue_redraw()
	return c["id"]


func add_polyline(points: Array, color: String = DEFAULT_COLOR, label: String = "") -> int:
	var c := _make_base("polyline", color, label)
	c["points"] = points
	_register_component(c)
	queue_redraw()
	return c["id"]


func add_poly(points: Array, color: String = DEFAULT_COLOR, label: String = "") -> int:
	var c := _make_base("poly", color, label)
	c["points"] = points
	_register_component(c)
	queue_redraw()
	return c["id"]


func add_arrow(x1: float, y1: float, x2: float, y2: float, color: String = DEFAULT_COLOR, label: String = "") -> int:
	var c := _make_base("arrow", color, label)
	c["x1"] = x1; c["y1"] = y1
	c["x2"] = x2; c["y2"] = y2
	c["head_size"] = DEFAULT_HEAD_SIZE
	_register_component(c)
	queue_redraw()
	return c["id"]


func add_vector(ox: float, oy: float, dx: float, dy: float, color: String = DEFAULT_COLOR, label: String = "") -> int:
	var c := _make_base("vector", color, label)
	c["ox"] = ox; c["oy"] = oy
	c["dx"] = dx; c["dy"] = dy
	_register_component(c)
	queue_redraw()
	return c["id"]


func add_normal(ref_id: int, t: float = 0.5, length: float = DEFAULT_NORMAL_LENGTH, flipped: bool = false, color: String = DEFAULT_COLOR) -> int:
	var ref := get_component(ref_id)
	if ref.is_empty():
		return -1
	var c := _make_base("normal", color, "")
	c["ref_id"] = ref_id
	c["t"] = clampf(t, 0.0, 1.0)
	c["length"] = length
	c["flipped"] = flipped
	_register_component(c)
	queue_redraw()
	return c["id"]


func add_arc(cx: float, cy: float, r: float, start_angle: float, sweep_angle: float, color: String = DEFAULT_COLOR, label: String = "") -> int:
	var c := _make_base("arc", color, label)
	c["cx"] = cx; c["cy"] = cy; c["r"] = r
	c["start_angle"] = start_angle
	c["sweep_angle"] = sweep_angle
	_register_component(c)
	queue_redraw()
	return c["id"]


func add_bezier(points: Array, controls: Array, color: String = DEFAULT_COLOR, label: String = "") -> int:
	## Create a cubic bezier path.
	## points: [[x,y], ...] — N anchor points
	## controls: [[x,y], ...] — 2*(N-1) control points [out0, in1, out1, in2, ...]
	if points.size() < 2:
		return -1
	var expected_controls: int = 2 * (points.size() - 1)
	if controls.size() != expected_controls:
		# Auto-generate smooth controls if wrong count
		controls = _auto_bezier_controls(points)
	var c := _make_base("bezier", color, label)
	c["points"] = points
	c["controls"] = controls
	_register_component(c)
	queue_redraw()
	return c["id"]


func _auto_bezier_controls(points: Array) -> Array:
	## Generate smooth Catmull-Rom-style control handles for a bezier path.
	var n: int = points.size()
	var controls: Array = []
	for i in range(n - 1):
		var p0 := Vector2(points[i][0], points[i][1])
		var p1 := Vector2(points[i + 1][0], points[i + 1][1])
		# Tangent at start anchor
		var tan_out: Vector2
		if i > 0:
			var pp := Vector2(points[i - 1][0], points[i - 1][1])
			tan_out = (p1 - pp).normalized() * p0.distance_to(p1) * 0.3
		else:
			tan_out = (p1 - p0) * 0.3
		# Tangent at end anchor
		var tan_in: Vector2
		if i + 2 < n:
			var pn := Vector2(points[i + 2][0], points[i + 2][1])
			tan_in = (p0 - pn).normalized() * p0.distance_to(p1) * 0.3
		else:
			tan_in = (p0 - p1) * 0.3
		controls.append([p0.x + tan_out.x, p0.y + tan_out.y])
		controls.append([p1.x + tan_in.x, p1.y + tan_in.y])
	return controls


# ============================================================================
# PUBLIC API — Component Access & Modification
# ============================================================================

func get_component(id: int) -> Dictionary:
	for c in _components:
		if c["id"] == id:
			return c
	return {}


func set_component_property(id: int, key: String, value: Variant) -> bool:
	var c := get_component(id)
	if c.is_empty():
		return false
	if key == "id" or key == "type":
		return false  # Immutable
	# Allow toggling lock itself, but block other edits on locked components
	if key != "locked" and key != "selected" and key != "visible" and c.get("locked", false):
		return false
	if key == "color" and value is String:
		value = _resolve_color(value)
	c[key] = value
	queue_redraw()
	return true


func move_component(id: int, dx: float, dy: float) -> bool:
	var c := get_component(id)
	if c.is_empty():
		return false
	if c.get("locked", false):
		return false
	match c["type"]:
		"point":
			c["x"] += dx; c["y"] += dy
		"rect":
			c["x"] += dx; c["y"] += dy
		"circle":
			c["cx"] += dx; c["cy"] += dy
		"ellipse":
			c["cx"] += dx; c["cy"] += dy
		"line", "arrow":
			c["x1"] += dx; c["y1"] += dy
			c["x2"] += dx; c["y2"] += dy
		"polyline", "poly":
			var pts: Array = c["points"]
			for i in range(pts.size()):
				pts[i] = [pts[i][0] + dx, pts[i][1] + dy]
		"vector":
			c["ox"] += dx; c["oy"] += dy
		"arc":
			c["cx"] += dx; c["cy"] += dy
		"bezier":
			var pts: Array = c["points"]
			for i in range(pts.size()):
				pts[i] = [pts[i][0] + dx, pts[i][1] + dy]
			var ctrls: Array = c["controls"]
			for i in range(ctrls.size()):
				ctrls[i] = [ctrls[i][0] + dx, ctrls[i][1] + dy]
		"normal":
			pass  # Normals are relative to ref — can't move directly
	queue_redraw()
	return true


func delete_component(id: int) -> bool:
	for i in range(_components.size()):
		if _components[i]["id"] == id:
			_components.remove_at(i)
			# Remove from layers and groups
			_unregister_component_id(id)
			queue_redraw()
			return true
	return false


func delete_selected() -> int:
	## Delete all selected components. Returns count deleted.
	var sel_ids: Array[int] = get_selected_ids()
	for sid in sel_ids:
		delete_component(sid)
	return sel_ids.size()


func deselect_component(id: int) -> bool:
	var c := get_component(id)
	if c.is_empty():
		return false
	c["selected"] = false
	queue_redraw()
	return true


func select_component(id: int) -> bool:
	var c := get_component(id)
	if c.is_empty():
		return false
	c["selected"] = true
	queue_redraw()
	return true


func deselect_all() -> void:
	for c in _components:
		c["selected"] = false
	queue_redraw()


func get_selected_ids() -> Array[int]:
	var ids: Array[int] = []
	for c in _components:
		if c.get("selected", false):
			ids.append(c["id"])
	return ids


func get_all_components() -> Array[Dictionary]:
	return _components


# ============================================================================
# PUBLIC API — Annotations
# ============================================================================

func annotate(id: int, producer: String, text: String) -> bool:
	var c := get_component(id)
	if c.is_empty():
		return false
	c["annotations"].append({"producer": producer, "text": text})
	queue_redraw()
	return true


func get_annotations(id: int) -> Array:
	var c := get_component(id)
	if c.is_empty():
		return []
	return c.get("annotations", [])


func clear_annotations(id: int) -> bool:
	var c := get_component(id)
	if c.is_empty():
		return false
	c["annotations"] = []
	queue_redraw()
	return true


# ============================================================================
# PUBLIC API — Control Points
# ============================================================================

func get_control_points(c: Dictionary) -> Array:
	## Returns [{pos: Vector2, key: String}, ...] for a component's edit handles.
	## Used by whiteboard_tools for CP hit testing and by _draw for rendering.
	var pts: Array = []
	match c["type"]:
		"point":
			pts.append({"pos": Vector2(c["x"], c["y"]), "key": "pos"})
		"line", "arrow":
			pts.append({"pos": Vector2(c["x1"], c["y1"]), "key": "p1"})
			pts.append({"pos": Vector2(c["x2"], c["y2"]), "key": "p2"})
		"rect":
			var rx: float = c["x"]; var ry: float = c["y"]
			var rw: float = c["w"]; var rh: float = c["h"]
			pts.append({"pos": Vector2(rx, ry), "key": "tl"})
			pts.append({"pos": Vector2(rx + rw, ry), "key": "tr"})
			pts.append({"pos": Vector2(rx + rw, ry + rh), "key": "br"})
			pts.append({"pos": Vector2(rx, ry + rh), "key": "bl"})
		"circle":
			pts.append({"pos": Vector2(c["cx"], c["cy"]), "key": "center"})
			pts.append({"pos": Vector2(c["cx"] + c["r"], c["cy"]), "key": "radius"})
		"ellipse":
			pts.append({"pos": Vector2(c["cx"], c["cy"]), "key": "center"})
			pts.append({"pos": Vector2(c["cx"] + c["rx"], c["cy"]), "key": "rx"})
			pts.append({"pos": Vector2(c["cx"], c["cy"] + c["ry"]), "key": "ry"})
		"polyline", "poly":
			var points: Array = c.get("points", [])
			for i in range(points.size()):
				pts.append({"pos": Vector2(points[i][0], points[i][1]), "key": "p%d" % i})
		"vector":
			pts.append({"pos": Vector2(c["ox"], c["oy"]), "key": "origin"})
			pts.append({"pos": Vector2(c["ox"] + c["dx"], c["oy"] + c["dy"]), "key": "tip"})
		"text":
			pts.append({"pos": Vector2(c["x"], c["y"]), "key": "pos"})
			var fsize: int = c.get("font_size", 14)
			pts.append({"pos": Vector2(c["x"] - 14, c["y"] + fsize * 0.5), "key": "size"})
		"normal":
			var endpoints: Array = _get_normal_endpoints(c)
			if endpoints.size() >= 2:
				pts.append({"pos": endpoints[0], "key": "base"})
				pts.append({"pos": endpoints[1], "key": "tip"})
				# Flip control: offset perpendicular from midpoint
				var mid: Vector2 = (endpoints[0] + endpoints[1]) * 0.5
				var ndir: Vector2 = (endpoints[1] - endpoints[0]).normalized()
				var perp: Vector2 = Vector2(-ndir.y, ndir.x)
				pts.append({"pos": mid + perp * 12.0, "key": "flip"})
		"arc":
			var acx: float = c["cx"]; var acy: float = c["cy"]; var ar: float = c["r"]
			var sa: float = c["start_angle"]; var sw: float = c["sweep_angle"]
			pts.append({"pos": Vector2(acx, acy), "key": "center"})
			pts.append({"pos": Vector2(acx + ar * cos(sa), acy + ar * sin(sa)), "key": "start"})
			pts.append({"pos": Vector2(acx + ar * cos(sa + sw), acy + ar * sin(sa + sw)), "key": "end"})
		"bezier":
			var bpts: Array = c.get("points", [])
			for i in range(bpts.size()):
				pts.append({"pos": Vector2(bpts[i][0], bpts[i][1]), "key": "a%d" % i})
			var ctrls: Array = c.get("controls", [])
			for i in range(ctrls.size()):
				pts.append({"pos": Vector2(ctrls[i][0], ctrls[i][1]), "key": "c%d" % i})
	return pts


# ============================================================================
# PUBLIC API — Groups (legacy compatibility wrappers)
# ============================================================================

func create_group_by_name(label: String, ids: Array[int], color: String = "#888888") -> void:
	## Legacy RCON wrapper: create or update a group by name on the active layer.
	# Check if a group with this name already exists
	for layer in _layers:
		for group in layer["groups"]:
			if group["name"] == label:
				# Update: replace component IDs
				for old_cid in group["component_ids"]:
					var comp := get_component(int(old_cid))
					if not comp.is_empty():
						comp["group_id"] = -1
						layer["component_ids"].append(int(old_cid))
				group["component_ids"].clear()
				group["color"] = _resolve_color(color)
				for cid in ids:
					_remove_from_group(cid)
					layer["component_ids"].erase(cid)
					group["component_ids"].append(cid)
					var comp := get_component(cid)
					if not comp.is_empty():
						comp["group_id"] = group["id"]
				queue_redraw()
				return
	# Create new group
	create_group(label, ids, _active_layer_id, color)


func remove_group_by_name(label: String) -> bool:
	## Legacy RCON wrapper: remove a group by name.
	for layer in _layers:
		for gi in range(layer["groups"].size()):
			if layer["groups"][gi]["name"] == label:
				return remove_group(layer["groups"][gi]["id"])
	return false


func get_wb_groups() -> Array[Dictionary]:
	## Return all groups across all layers (for RCON listing).
	var result: Array[Dictionary] = []
	for layer in _layers:
		for group in layer["groups"]:
			result.append(group)
	return result


# ============================================================================
# PUBLIC API — Whiteboard Management
# ============================================================================

func clear_all() -> void:
	_components.clear()
	_layers.clear()
	_next_id = 1
	_next_layer_id = 1
	_next_group_id = 1
	_selection_rect = Rect2()
	_ensure_default_layer()
	queue_redraw()


func set_board_name(n: String) -> void:
	_name = n


func get_board_name() -> String:
	return _name


func set_grid_visible(v: bool) -> void:
	_grid_visible = v
	queue_redraw()


func is_grid_visible() -> bool:
	return _grid_visible


# ============================================================================
# PUBLIC API — Layers
# ============================================================================

func _ensure_default_layer() -> void:
	## Create Layer1 if no layers exist.
	if _layers.is_empty():
		var lid: int = _next_layer_id
		_next_layer_id += 1
		_layers.append({
			"id": lid,
			"name": "Layer1",
			"visible": true,
			"locked": false,
			"groups": [],
			"component_ids": [],
		})
		_active_layer_id = lid


func add_layer(layer_name: String = "") -> int:
	## Add a new layer at the top (index 0). Returns layer ID.
	var lid: int = _next_layer_id
	_next_layer_id += 1
	if layer_name.is_empty():
		layer_name = "Layer%d" % lid
	var layer := {
		"id": lid,
		"name": layer_name,
		"visible": true,
		"locked": false,
		"groups": [],
		"component_ids": [],
	}
	_layers.insert(0, layer)  # Top of stack
	_active_layer_id = lid
	queue_redraw()
	return lid


func remove_layer(layer_id: int) -> bool:
	## Remove a layer and all its components. Cannot remove the last layer.
	if _layers.size() <= 1:
		return false
	for i in range(_layers.size()):
		if _layers[i]["id"] == layer_id:
			var layer: Dictionary = _layers[i]
			# Delete all components on this layer
			var all_ids: Array[int] = []
			for gid in _get_layer_all_component_ids(layer):
				all_ids.append(gid)
			for cid in all_ids:
				for ci in range(_components.size()):
					if _components[ci]["id"] == cid:
						_components.remove_at(ci)
						break
			_layers.remove_at(i)
			if _active_layer_id == layer_id:
				_active_layer_id = _layers[0]["id"]
			queue_redraw()
			return true
	return false


func get_layer(layer_id: int) -> Dictionary:
	for layer in _layers:
		if layer["id"] == layer_id:
			return layer
	return {}


func get_layers() -> Array[Dictionary]:
	return _layers


func rename_layer(layer_id: int, new_name: String) -> bool:
	var layer := get_layer(layer_id)
	if layer.is_empty():
		return false
	layer["name"] = new_name
	return true


func set_layer_visible(layer_id: int, v: bool) -> bool:
	var layer := get_layer(layer_id)
	if layer.is_empty():
		return false
	layer["visible"] = v
	queue_redraw()
	return true


func set_layer_locked(layer_id: int, v: bool) -> bool:
	var layer := get_layer(layer_id)
	if layer.is_empty():
		return false
	layer["locked"] = v
	queue_redraw()
	return true


func move_layer(layer_id: int, direction: int) -> bool:
	## Move layer up (-1) or down (1) in the stack. Top=index 0.
	for i in range(_layers.size()):
		if _layers[i]["id"] == layer_id:
			var new_idx: int = i + direction
			if new_idx < 0 or new_idx >= _layers.size():
				return false
			var tmp: Dictionary = _layers[i]
			_layers[i] = _layers[new_idx]
			_layers[new_idx] = tmp
			queue_redraw()
			return true
	return false


func set_active_layer(layer_id: int) -> bool:
	var layer := get_layer(layer_id)
	if layer.is_empty():
		return false
	_active_layer_id = layer_id
	return true


func get_active_layer_id() -> int:
	return _active_layer_id


# ============================================================================
# PUBLIC API — Groups (within layers)
# ============================================================================

func create_group(group_name: String, comp_ids: Array, layer_id: int = -1, color: String = "#888888") -> int:
	## Create a group on the specified layer (or active layer). Returns group ID.
	## Components are moved from ungrouped to this group within the same layer.
	if layer_id < 0:
		layer_id = _active_layer_id
	var layer := get_layer(layer_id)
	if layer.is_empty():
		return -1
	var gid: int = _next_group_id
	_next_group_id += 1
	if group_name.is_empty():
		group_name = "Group%d" % gid
	var group := {
		"id": gid,
		"name": group_name,
		"visible": true,
		"locked": false,
		"component_ids": [],
		"color": _resolve_color(color),
	}
	for cid in comp_ids:
		var comp_id: int = int(cid)
		# Remove from any existing group
		_remove_from_group(comp_id)
		# Ensure component is on this layer
		assign_to_layer(comp_id, layer_id)
		# Remove from layer's ungrouped list
		layer["component_ids"].erase(comp_id)
		group["component_ids"].append(comp_id)
		var comp := get_component(comp_id)
		if not comp.is_empty():
			comp["group_id"] = gid
	layer["groups"].append(group)
	queue_redraw()
	return gid


func remove_group(group_id: int) -> bool:
	## Remove a group — components stay on the layer, ungrouped.
	for layer in _layers:
		for gi in range(layer["groups"].size()):
			if layer["groups"][gi]["id"] == group_id:
				var group: Dictionary = layer["groups"][gi]
				# Move components back to layer ungrouped list
				for cid in group["component_ids"]:
					layer["component_ids"].append(int(cid))
					var comp := get_component(int(cid))
					if not comp.is_empty():
						comp["group_id"] = -1
				layer["groups"].remove_at(gi)
				queue_redraw()
				return true
	return false


func get_group(group_id: int) -> Dictionary:
	for layer in _layers:
		for group in layer["groups"]:
			if group["id"] == group_id:
				return group
	return {}


func get_group_layer(group_id: int) -> Dictionary:
	## Find the layer that contains a group.
	for layer in _layers:
		for group in layer["groups"]:
			if group["id"] == group_id:
				return layer
	return {}


func set_group_visible(group_id: int, v: bool) -> bool:
	var group := get_group(group_id)
	if group.is_empty():
		return false
	group["visible"] = v
	queue_redraw()
	return true


func set_group_locked(group_id: int, v: bool) -> bool:
	var group := get_group(group_id)
	if group.is_empty():
		return false
	group["locked"] = v
	queue_redraw()
	return true


func rename_group(group_id: int, new_name: String) -> bool:
	var group := get_group(group_id)
	if group.is_empty():
		return false
	group["name"] = new_name
	return true


# ============================================================================
# PUBLIC API — Layer/Group Assignment
# ============================================================================

func assign_to_layer(comp_id: int, layer_id: int) -> bool:
	## Move a component to a different layer (ungrouped). Returns true if moved.
	var comp := get_component(comp_id)
	if comp.is_empty():
		return false
	var target_layer := get_layer(layer_id)
	if target_layer.is_empty():
		return false
	# Remove from current layer/group
	_unregister_component_id(comp_id)
	# Add to target layer ungrouped
	comp["layer_id"] = layer_id
	comp["group_id"] = -1
	target_layer["component_ids"].append(comp_id)
	return true


func assign_to_group(comp_id: int, group_id: int) -> bool:
	## Move a component into a group. Returns true if moved.
	var comp := get_component(comp_id)
	if comp.is_empty():
		return false
	var group := get_group(group_id)
	if group.is_empty():
		return false
	var layer := get_group_layer(group_id)
	if layer.is_empty():
		return false
	# Remove from current position
	_unregister_component_id(comp_id)
	# Add to group
	comp["layer_id"] = layer["id"]
	comp["group_id"] = group_id
	group["component_ids"].append(comp_id)
	return true


func ungroup_component(comp_id: int) -> bool:
	## Remove a component from its group, keeping it on the same layer.
	var comp := get_component(comp_id)
	if comp.is_empty():
		return false
	var gid: int = int(comp.get("group_id", -1))
	if gid < 0:
		return false
	var group := get_group(gid)
	if group.is_empty():
		return false
	var layer := get_group_layer(gid)
	if layer.is_empty():
		return false
	group["component_ids"].erase(comp_id)
	layer["component_ids"].append(comp_id)
	comp["group_id"] = -1
	return true


# ============================================================================
# PUBLIC API — Effective State (cascading visibility/lock)
# ============================================================================

func is_effectively_visible(c: Dictionary) -> bool:
	## Check if component is visible considering layer and group visibility.
	if not c.get("visible", true):
		return false
	var lid: int = int(c.get("layer_id", -1))
	if lid >= 0:
		var layer := get_layer(lid)
		if not layer.is_empty() and not layer.get("visible", true):
			return false
	var gid: int = int(c.get("group_id", -1))
	if gid >= 0:
		var group := get_group(gid)
		if not group.is_empty() and not group.get("visible", true):
			return false
	return true


func is_effectively_locked(c: Dictionary) -> bool:
	## Check if component is locked considering layer and group lock.
	if c.get("locked", false):
		return true
	var lid: int = int(c.get("layer_id", -1))
	if lid >= 0:
		var layer := get_layer(lid)
		if not layer.is_empty() and layer.get("locked", false):
			return true
	var gid: int = int(c.get("group_id", -1))
	if gid >= 0:
		var group := get_group(gid)
		if not group.is_empty() and group.get("locked", false):
			return true
	return false


func move_selected(dx: float, dy: float) -> int:
	## Move all selected, effectively-unlocked components. Returns count moved.
	var moved: int = 0
	for c in _components:
		if c.get("selected", false) and not is_effectively_locked(c):
			move_component(c["id"], dx, dy)
			moved += 1
	return moved


func get_bounding_rect(c: Dictionary) -> Rect2:
	## Get the axis-aligned bounding rect of a component's RENDERED shape.
	## Uses actual visual geometry, not edit control points.
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)

	match c["type"]:
		"point":
			var r: float = c.get("radius", DEFAULT_POINT_RADIUS)
			var p := Vector2(c["x"], c["y"])
			min_p = p - Vector2(r, r)
			max_p = p + Vector2(r, r)
		"line":
			min_p = Vector2(minf(c["x1"], c["x2"]), minf(c["y1"], c["y2"]))
			max_p = Vector2(maxf(c["x1"], c["x2"]), maxf(c["y1"], c["y2"]))
		"arrow":
			var hs: float = c.get("head_size", 12.0)
			min_p = Vector2(minf(c["x1"], c["x2"]) - hs, minf(c["y1"], c["y2"]) - hs)
			max_p = Vector2(maxf(c["x1"], c["x2"]) + hs, maxf(c["y1"], c["y2"]) + hs)
		"rect":
			min_p = Vector2(c["x"], c["y"])
			max_p = Vector2(c["x"] + c["w"], c["y"] + c["h"])
		"circle":
			var r: float = c["r"]
			min_p = Vector2(c["cx"] - r, c["cy"] - r)
			max_p = Vector2(c["cx"] + r, c["cy"] + r)
		"ellipse":
			min_p = Vector2(c["cx"] - c["rx"], c["cy"] - c["ry"])
			max_p = Vector2(c["cx"] + c["rx"], c["cy"] + c["ry"])
		"polyline", "poly":
			for pt in c.get("points", []):
				min_p.x = minf(min_p.x, pt[0]); min_p.y = minf(min_p.y, pt[1])
				max_p.x = maxf(max_p.x, pt[0]); max_p.y = maxf(max_p.y, pt[1])
		"vector":
			var o := Vector2(c["ox"], c["oy"])
			var t := Vector2(c["ox"] + c["dx"], c["oy"] + c["dy"])
			min_p = Vector2(minf(o.x, t.x), minf(o.y, t.y))
			max_p = Vector2(maxf(o.x, t.x), maxf(o.y, t.y))
		"normal":
			var eps: Array = _get_normal_endpoints(c)
			if eps.size() >= 2:
				min_p = Vector2(minf(eps[0].x, eps[1].x), minf(eps[0].y, eps[1].y))
				max_p = Vector2(maxf(eps[0].x, eps[1].x), maxf(eps[0].y, eps[1].y))
		"arc":
			# Sample the arc to find rendered bounds
			var cx: float = c["cx"]; var cy: float = c["cy"]; var r: float = c["r"]
			var sa: float = c["start_angle"]; var sw: float = c["sweep_angle"]
			for i in range(DEFAULT_ARC_SEGMENTS + 1):
				var t: float = float(i) / float(DEFAULT_ARC_SEGMENTS)
				var a: float = sa + sw * t
				var px: float = cx + r * cos(a)
				var py: float = cy + r * sin(a)
				min_p.x = minf(min_p.x, px); min_p.y = minf(min_p.y, py)
				max_p.x = maxf(max_p.x, px); max_p.y = maxf(max_p.y, py)
		"bezier":
			var bpts: Array = c.get("points", [])
			var ctrls: Array = c.get("controls", [])
			for seg_i in range(bpts.size() - 1):
				var co: int = seg_i * 2; var ci: int = seg_i * 2 + 1
				if co >= ctrls.size() or ci >= ctrls.size():
					break
				var p0 := Vector2(bpts[seg_i][0], bpts[seg_i][1])
				var p3 := Vector2(bpts[seg_i + 1][0], bpts[seg_i + 1][1])
				var p1 := Vector2(ctrls[co][0], ctrls[co][1])
				var p2 := Vector2(ctrls[ci][0], ctrls[ci][1])
				for s in range(BEZIER_SAMPLES + 1):
					var t: float = float(s) / float(BEZIER_SAMPLES)
					var it: float = 1.0 - t
					var pt: Vector2 = it*it*it*p0 + 3.0*it*it*t*p1 + 3.0*it*t*t*p2 + t*t*t*p3
					min_p.x = minf(min_p.x, pt.x); min_p.y = minf(min_p.y, pt.y)
					max_p.x = maxf(max_p.x, pt.x); max_p.y = maxf(max_p.y, pt.y)
		"text":
			var pos := Vector2(c["x"], c["y"])
			var fsize: int = c.get("font_size", 14)
			var text_str: String = c.get("text", "")
			var tw: float = maxf(text_str.length() * fsize * 0.6, 10.0)
			min_p = pos
			max_p = Vector2(pos.x + tw, pos.y + fsize)
		_:
			# Fallback to control points
			var cps: Array = get_control_points(c)
			for cp in cps:
				var p: Vector2 = cp["pos"]
				min_p.x = minf(min_p.x, p.x); min_p.y = minf(min_p.y, p.y)
				max_p.x = maxf(max_p.x, p.x); max_p.y = maxf(max_p.y, p.y)

	if min_p.x == INF:
		return Rect2()
	return Rect2(min_p, max_p - min_p)


# ============================================================================
# INTERNAL — Layer/Group helpers
# ============================================================================

func _register_component(c: Dictionary) -> void:
	## Append component to _components and add to active layer's ungrouped list.
	_components.append(c)
	var layer := get_layer(_active_layer_id)
	if not layer.is_empty():
		layer["component_ids"].append(c["id"])


func _unregister_component_id(comp_id: int) -> void:
	## Remove a component ID from all layer/group references.
	for layer in _layers:
		layer["component_ids"].erase(comp_id)
		for group in layer["groups"]:
			group["component_ids"].erase(comp_id)


func _remove_from_group(comp_id: int) -> void:
	## Remove a component from its current group (if any).
	for layer in _layers:
		for group in layer["groups"]:
			if group["component_ids"].has(comp_id):
				group["component_ids"].erase(comp_id)
				var comp := get_component(comp_id)
				if not comp.is_empty():
					comp["group_id"] = -1
				return


func _get_layer_all_component_ids(layer: Dictionary) -> Array[int]:
	## Get all component IDs on a layer (ungrouped + grouped).
	var ids: Array[int] = []
	for cid in layer.get("component_ids", []):
		ids.append(int(cid))
	for group in layer.get("groups", []):
		for cid in group.get("component_ids", []):
			ids.append(int(cid))
	return ids


# ============================================================================
# SERIALIZATION
# ============================================================================

func to_dict() -> Dictionary:
	return {
		"name": _name,
		"version": 2,
		"next_id": _next_id,
		"next_layer_id": _next_layer_id,
		"next_group_id": _next_group_id,
		"active_layer_id": _active_layer_id,
		"components": _components.duplicate(true),
		"layers": _layers.duplicate(true),
	}


func from_dict(data: Dictionary) -> void:
	_name = data.get("name", "untitled")
	_next_id = data.get("next_id", 1)
	_components.clear()
	for c in data.get("components", []):
		_components.append(c)

	var ver: int = int(data.get("version", 1))
	if ver >= 2 and data.has("layers"):
		# Version 2+ — load layers directly
		_layers.clear()
		for layer_data in data.get("layers", []):
			_layers.append(layer_data)
		_next_layer_id = int(data.get("next_layer_id", 1))
		_next_group_id = int(data.get("next_group_id", 1))
		_active_layer_id = int(data.get("active_layer_id", -1))
		if _layers.is_empty():
			_ensure_default_layer()
		elif _active_layer_id < 0:
			_active_layer_id = _layers[0]["id"]
	else:
		# Version 1 — migrate: create Layer1 with all components
		_layers.clear()
		_next_layer_id = 1
		_next_group_id = 1
		_ensure_default_layer()
		var layer: Dictionary = _layers[0]
		for c in _components:
			c["layer_id"] = layer["id"]
			c["group_id"] = -1
			if not layer["component_ids"].has(int(c["id"])):
				layer["component_ids"].append(int(c["id"]))
		# Migrate old groups into layer groups
		for old_g in data.get("groups", []):
			var gid: int = _next_group_id
			_next_group_id += 1
			var group := {
				"id": gid,
				"name": str(old_g.get("label", "Group%d" % gid)),
				"visible": true,
				"locked": false,
				"component_ids": [],
				"color": str(old_g.get("color", "#888888")),
			}
			for cid in old_g.get("ids", []):
				var comp_id: int = int(cid)
				group["component_ids"].append(comp_id)
				layer["component_ids"].erase(comp_id)
				# Update component's group_id
				var comp := get_component(comp_id)
				if not comp.is_empty():
					comp["group_id"] = gid
			layer["groups"].append(group)
	queue_redraw()


func save_to_file(filename: String = "") -> String:
	var fname: String = filename if not filename.is_empty() else _name
	fname = fname.to_lower().replace(" ", "_")
	if not fname.ends_with(".json"):
		fname += ".json"
	var path: String = "res://data/whiteboards/" + fname
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		# Try user:// as fallback
		path = "user://whiteboards/" + fname
		DirAccess.make_dir_recursive_absolute("user://whiteboards")
		file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return "ERR: cannot write to " + path
	file.store_string(JSON.stringify(to_dict(), "  "))
	file = null
	return "OK: saved to " + path


func load_from_file(filename: String) -> String:
	var fname: String = filename.to_lower().replace(" ", "_")
	if not fname.ends_with(".json"):
		fname += ".json"
	# Try res:// first, then user://
	var path: String = "res://data/whiteboards/" + fname
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		path = "user://whiteboards/" + fname
		file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return "ERR: file not found: " + fname
	var text: String = file.get_as_text()
	file = null
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		return "ERR: invalid JSON in " + fname
	from_dict(parsed)
	return "OK: loaded '%s' (%d components, %d layers)" % [_name, _components.size(), _layers.size()]


func list_saved_files() -> Array[String]:
	var files: Array[String] = []
	for dir_path in ["res://data/whiteboards/", "user://whiteboards/"]:
		var dir := DirAccess.open(dir_path)
		if not dir:
			continue
		dir.list_dir_begin()
		var f: String = dir.get_next()
		while not f.is_empty():
			if f.ends_with(".json"):
				var name_without_ext: String = f.get_basename()
				if name_without_ext not in files:
					files.append(name_without_ext)
			f = dir.get_next()
	return files


# ============================================================================
# DRAWING
# ============================================================================

func _draw() -> void:
	if not _font:
		_font = ThemeDB.fallback_font

	if _grid_visible:
		_draw_grid()

	# Render layers bottom-to-top (last in array = bottom, first = top)
	for layer_idx in range(_layers.size() - 1, -1, -1):
		var layer: Dictionary = _layers[layer_idx]
		if not layer.get("visible", true):
			continue

		# Draw group bounding boxes for this layer
		for group in layer.get("groups", []):
			if group.get("visible", true):
				_draw_group_box(group)

		# Draw ungrouped components on this layer
		for cid in layer.get("component_ids", []):
			var c := get_component(int(cid))
			if c.is_empty() or not is_effectively_visible(c):
				continue
			_draw_component(c)

		# Draw grouped components
		for group in layer.get("groups", []):
			if not group.get("visible", true):
				continue
			for cid in group.get("component_ids", []):
				var c := get_component(int(cid))
				if c.is_empty() or not is_effectively_visible(c):
					continue
				_draw_component(c)

	# Draw preview/ghost component from tools (semi-transparent via alpha-dimmed color)
	if not _preview_component.is_empty() and _preview_component.get("visible", true):
		var ghost := _preview_component.duplicate()
		var gc: String = ghost.get("color", DEFAULT_COLOR)
		var parsed: Color = _parse_color(gc)
		parsed.a = 0.45
		ghost["color"] = "#" + parsed.to_html(true)
		_draw_component(ghost)
		# Draw control points on the preview for visual feedback
		_draw_preview_control_points(ghost)

	# Draw annotations on top (all visible components)
	for c in _components:
		if not is_effectively_visible(c):
			continue
		if c.get("show_annotations", true) and not c.get("annotations", []).is_empty():
			_draw_annotations(c)

	# Draw selection rectangle (if multi-select in progress)
	if _selection_rect.size.x > 0 or _selection_rect.size.y > 0:
		draw_rect(_selection_rect, SELECTION_RECT_FILL, true)
		draw_rect(_selection_rect, SELECTION_RECT_BORDER, false, 1.0)

	# Draw lasso polygon (if lasso select in progress)
	if _lasso_points.size() >= 2:
		var offset: Vector2 = -global_position
		var lasso_col := Color(0.3, 0.7, 1.0, 0.6)
		var fill_col := Color(0.2, 0.4, 0.7, 0.1)
		var shifted: PackedVector2Array = PackedVector2Array()
		for p in _lasso_points:
			shifted.append(p + offset)
		if shifted.size() >= 3:
			draw_polygon(shifted, PackedColorArray([fill_col]))
		draw_polyline(shifted, lasso_col, 2.0)
		# Close the loop back to start
		if shifted.size() >= 2:
			draw_line(shifted[shifted.size() - 1], shifted[0], lasso_col * Color(1, 1, 1, 0.4), 1.0)

	# Draw cursor indicator (+/-) for selection tools
	if not _cursor_indicator.is_empty():
		var ci_pos: Vector2 = _cursor_indicator["pos"] - global_position
		var ci_type: String = _cursor_indicator["type"]
		var ci_col := Color(0.3, 1.0, 0.3) if ci_type == "add" else Color(1.0, 0.3, 0.3)
		# Draw + or - symbol offset from cursor
		var ix: float = ci_pos.x + 12
		var iy: float = ci_pos.y - 12
		if ci_type == "add":
			draw_line(Vector2(ix - 5, iy), Vector2(ix + 5, iy), ci_col, 2.0)
			draw_line(Vector2(ix, iy - 5), Vector2(ix, iy + 5), ci_col, 2.0)
		else:
			draw_line(Vector2(ix - 5, iy), Vector2(ix + 5, iy), ci_col, 2.0)

	# Draw control points for selected, effectively-unlocked components (on top of everything)
	for c in _components:
		if c.get("selected", false) and is_effectively_visible(c) and not is_effectively_locked(c):
			_draw_control_points(c)


func _draw_grid() -> void:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var cam_pos: Vector2 = Vector2(960, 540)
	var cam := get_viewport().get_camera_2d()
	if cam:
		cam_pos = cam.global_position

	var half_w: float = vp_size.x * 0.5
	var half_h: float = vp_size.y * 0.5
	var left: float = cam_pos.x - half_w
	var right: float = cam_pos.x + half_w
	var top: float = cam_pos.y - half_h
	var bottom: float = cam_pos.y + half_h

	# Snap grid start to grid intervals
	var minor_left: float = floorf(left / GRID_MINOR) * GRID_MINOR
	var minor_top: float = floorf(top / GRID_MINOR) * GRID_MINOR

	# Minor vertical lines
	var gx: float = minor_left
	while gx <= right:
		var is_major: bool = fmod(absf(gx), GRID_MAJOR) < 0.5
		if not is_major:
			var lp := Vector2(gx, top) - global_position
			var lp2 := Vector2(gx, bottom) - global_position
			draw_line(lp, lp2, GRID_MINOR_COLOR, 1.0)
		gx += GRID_MINOR

	# Minor horizontal lines
	var gy: float = minor_top
	while gy <= bottom:
		var is_major: bool = fmod(absf(gy), GRID_MAJOR) < 0.5
		if not is_major:
			var lp := Vector2(left, gy) - global_position
			var lp2 := Vector2(right, gy) - global_position
			draw_line(lp, lp2, GRID_MINOR_COLOR, 1.0)
		gy += GRID_MINOR

	# Major vertical lines + labels
	var major_left: float = floorf(left / GRID_MAJOR) * GRID_MAJOR
	gx = major_left
	while gx <= right:
		var is_axis: bool = absf(gx) < 0.5
		var col: Color = GRID_AXIS_COLOR if is_axis else GRID_MAJOR_COLOR
		var w: float = 1.5 if is_axis else 1.0
		var lp := Vector2(gx, top) - global_position
		var lp2 := Vector2(gx, bottom) - global_position
		draw_line(lp, lp2, col, w)
		# Coordinate label at top
		var label_pos := Vector2(gx + 2, top + 10) - global_position
		draw_string(_font, label_pos, str(int(gx)), HORIZONTAL_ALIGNMENT_LEFT, -1, GRID_LABEL_SIZE, GRID_LABEL_COLOR)
		gx += GRID_MAJOR

	# Major horizontal lines + labels
	var major_top: float = floorf(top / GRID_MAJOR) * GRID_MAJOR
	gy = major_top
	while gy <= bottom:
		var is_axis: bool = absf(gy) < 0.5
		var col: Color = GRID_AXIS_COLOR if is_axis else GRID_MAJOR_COLOR
		var w: float = 1.5 if is_axis else 1.0
		var lp := Vector2(left, gy) - global_position
		var lp2 := Vector2(right, gy) - global_position
		draw_line(lp, lp2, col, w)
		# Coordinate label at left
		var label_pos := Vector2(left + 2, gy - 2) - global_position
		draw_string(_font, label_pos, str(int(gy)), HORIZONTAL_ALIGNMENT_LEFT, -1, GRID_LABEL_SIZE, GRID_LABEL_COLOR)
		gy += GRID_MAJOR


func _draw_component(c: Dictionary) -> void:
	var col: Color = _parse_color(c.get("color", DEFAULT_COLOR))
	var lw: float = c.get("line_width", DEFAULT_LINE_WIDTH)
	var is_selected: bool = c.get("selected", false)

	if is_selected:
		lw += SELECTION_EXTRA_WIDTH
		var pulse: float = 0.6 + 0.4 * sin(Time.get_ticks_msec() / 1000.0 * SELECTION_PULSE_SPEED)
		col = col.lerp(Color.WHITE, 0.3 * pulse)

	var offset: Vector2 = -global_position

	match c["type"]:
		"point":
			var pos := Vector2(c["x"], c["y"]) + offset
			var r: float = c.get("radius", DEFAULT_POINT_RADIUS)
			draw_circle(pos, r + (1.0 if is_selected else 0.0), col)
			if not c.get("label", "").is_empty():
				draw_string(_font, pos + Vector2(r + 4, 4), c["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)

		"line":
			var p1 := Vector2(c["x1"], c["y1"]) + offset
			var p2 := Vector2(c["x2"], c["y2"]) + offset
			draw_line(p1, p2, col, lw)
			_draw_label_at_midpoint(c, p1, p2, col)

		"rect":
			var r := Rect2(c["x"] + offset.x, c["y"] + offset.y, c["w"], c["h"])
			draw_rect(r, col, false, lw)
			if not c.get("label", "").is_empty():
				draw_string(_font, Vector2(r.position.x, r.position.y - 4), c["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)

		"circle":
			var center := Vector2(c["cx"], c["cy"]) + offset
			draw_arc(center, c["r"], 0, TAU, 48, col, lw)
			if not c.get("label", "").is_empty():
				draw_string(_font, center + Vector2(c["r"] + 4, 4), c["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)

		"ellipse":
			_draw_ellipse(Vector2(c["cx"], c["cy"]) + offset, c["rx"], c["ry"], col, lw)
			if not c.get("label", "").is_empty():
				draw_string(_font, Vector2(c["cx"] + c["rx"] + 4, c["cy"] + 4) + offset, c["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)

		"polyline":
			var pts: PackedVector2Array = _points_to_packed(c["points"], offset)
			if pts.size() >= 2:
				draw_polyline(pts, col, lw)
			_draw_label_at_packed(c, pts, col)

		"poly":
			var pts: PackedVector2Array = _points_to_packed(c["points"], offset)
			if pts.size() >= 2:
				# Close the polygon
				var closed := PackedVector2Array(pts)
				closed.append(pts[0])
				draw_polyline(closed, col, lw)
			_draw_label_at_packed(c, pts, col)

		"arrow":
			var p1 := Vector2(c["x1"], c["y1"]) + offset
			var p2 := Vector2(c["x2"], c["y2"]) + offset
			_draw_arrow(p1, p2, col, lw, c.get("head_size", DEFAULT_HEAD_SIZE))
			_draw_label_at_midpoint(c, p1, p2, col)

		"vector":
			var origin := Vector2(c["ox"], c["oy"]) + offset
			var tip := origin + Vector2(c["dx"], c["dy"])
			_draw_arrow(origin, tip, col, lw, DEFAULT_HEAD_SIZE)
			if not c.get("label", "").is_empty():
				draw_string(_font, origin + Vector2(4, -8), c["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)

		"normal":
			_draw_normal(c, col, lw, offset)

		"arc":
			var ac := Vector2(c["cx"], c["cy"]) + offset
			var ar: float = c["r"]
			var sa: float = c["start_angle"]
			var sw: float = c["sweep_angle"]
			draw_arc(ac, ar, sa, sa + sw, DEFAULT_ARC_SEGMENTS, col, lw)
			# Draw small tick marks at start and end
			var start_p := ac + Vector2(cos(sa), sin(sa)) * ar
			var end_p := ac + Vector2(cos(sa + sw), sin(sa + sw)) * ar
			var tick: float = 6.0
			var sdir := Vector2(cos(sa), sin(sa))
			var edir := Vector2(cos(sa + sw), sin(sa + sw))
			draw_line(start_p - sdir * tick, start_p + sdir * tick, col, lw)
			draw_line(end_p - edir * tick, end_p + edir * tick, col, lw)
			if not c.get("label", "").is_empty():
				var mid_angle: float = sa + sw * 0.5
				var label_p := ac + Vector2(cos(mid_angle), sin(mid_angle)) * (ar + 12)
				draw_string(_font, label_p, c["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)

		"bezier":
			_draw_bezier(c, col, lw, offset)

		"text":
			var pos := Vector2(c["x"], c["y"]) + offset
			var text_str: String = c.get("text", "")
			var fsize: int = c.get("font_size", 14)
			if text_str.is_empty():
				# Show blinking cursor placeholder when empty
				if int(Time.get_ticks_msec() / 500) % 2 == 0:
					draw_line(pos, pos + Vector2(0, fsize), col, 1.5)
			else:
				draw_string(_font, pos + Vector2(0, fsize), text_str, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
			# Size indicator: horizontal ◄─►  left of the position point
			if is_selected:
				var sz_x: float = pos.x - 14
				var sz_y: float = pos.y + fsize * 0.5
				var sz_col := col * Color(1, 1, 1, 0.5)
				# Horizontal line with left/right arrows
				draw_line(Vector2(sz_x - 6, sz_y), Vector2(sz_x + 6, sz_y), sz_col, 1.0)
				draw_line(Vector2(sz_x - 6, sz_y), Vector2(sz_x - 4, sz_y - 2), sz_col, 1.0)
				draw_line(Vector2(sz_x - 6, sz_y), Vector2(sz_x - 4, sz_y + 2), sz_col, 1.0)
				draw_line(Vector2(sz_x + 6, sz_y), Vector2(sz_x + 4, sz_y - 2), sz_col, 1.0)
				draw_line(Vector2(sz_x + 6, sz_y), Vector2(sz_x + 4, sz_y + 2), sz_col, 1.0)


func _draw_arrow(from: Vector2, to: Vector2, col: Color, lw: float, head_size: float) -> void:
	draw_line(from, to, col, lw)
	var dir: Vector2 = (to - from).normalized()
	if dir.length_squared() < 0.001:
		return
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var head_base: Vector2 = to - dir * head_size
	var pts: PackedVector2Array = [
		to,
		head_base + perp * head_size * 0.4,
		head_base - perp * head_size * 0.4,
	]
	draw_polygon(pts, PackedColorArray([col, col, col]))


func _draw_ellipse(center: Vector2, rx: float, ry: float, col: Color, lw: float) -> void:
	var segments := 48
	var pts: PackedVector2Array = PackedVector2Array()
	for i in range(segments + 1):
		var angle: float = float(i) / float(segments) * TAU
		pts.append(center + Vector2(cos(angle) * rx, sin(angle) * ry))
	draw_polyline(pts, col, lw)


func _get_normal_endpoints(c: Dictionary) -> Array:
	## Compute [base_pos: Vector2, tip_pos: Vector2] for a normal component.
	## Used by get_control_points(), _draw_normal(), and control point dragging.
	var ref := get_component(c.get("ref_id", -1))
	if ref.is_empty():
		return []
	var t: float = c.get("t", 0.5)
	var length: float = c.get("length", DEFAULT_NORMAL_LENGTH)
	var flipped: bool = c.get("flipped", false)

	var pos: Vector2 = Vector2.ZERO
	var normal_dir: Vector2 = Vector2.UP

	match ref["type"]:
		"line", "arrow":
			var p1 := Vector2(ref["x1"], ref["y1"])
			var p2 := Vector2(ref["x2"], ref["y2"])
			pos = p1.lerp(p2, t)
			var dir: Vector2 = (p2 - p1).normalized()
			normal_dir = Vector2(-dir.y, dir.x)
		"polyline", "poly":
			var result: Array = _sample_polyline(ref["points"], t, ref["type"] == "poly")
			pos = result[0]
			normal_dir = result[1]
		"rect":
			var perimeter: float = 2.0 * (ref["w"] + ref["h"])
			var d: float = t * perimeter
			var rx: float = ref["x"]; var ry: float = ref["y"]
			var rw: float = ref["w"]; var rh: float = ref["h"]
			if d < rw:
				pos = Vector2(rx + d, ry); normal_dir = Vector2.UP
			elif d < rw + rh:
				pos = Vector2(rx + rw, ry + (d - rw)); normal_dir = Vector2.RIGHT
			elif d < 2 * rw + rh:
				pos = Vector2(rx + rw - (d - rw - rh), ry + rh); normal_dir = Vector2.DOWN
			else:
				pos = Vector2(rx, ry + rh - (d - 2 * rw - rh)); normal_dir = Vector2.LEFT
		"circle":
			var angle: float = t * TAU
			pos = Vector2(ref["cx"] + cos(angle) * ref["r"], ref["cy"] + sin(angle) * ref["r"])
			normal_dir = Vector2(cos(angle), sin(angle))
		"ellipse":
			var angle: float = t * TAU
			pos = Vector2(ref["cx"] + cos(angle) * ref["rx"], ref["cy"] + sin(angle) * ref["ry"])
			normal_dir = Vector2(cos(angle) / ref["rx"], sin(angle) / ref["ry"]).normalized()
		"vector":
			var origin := Vector2(ref["ox"], ref["oy"])
			var tip := origin + Vector2(ref["dx"], ref["dy"])
			pos = origin.lerp(tip, t)
			var dir: Vector2 = (tip - origin).normalized()
			normal_dir = Vector2(-dir.y, dir.x)
		_:
			return []

	if flipped:
		normal_dir = -normal_dir

	return [pos, pos + normal_dir * length]


func _draw_normal(c: Dictionary, col: Color, lw: float, offset: Vector2) -> void:
	var endpoints: Array = _get_normal_endpoints(c)
	if endpoints.is_empty():
		return
	var base: Vector2 = endpoints[0] + offset
	var normal_tip: Vector2 = endpoints[1] + offset

	draw_line(base, normal_tip, col, lw)
	# Tick mark at base (perpendicular)
	var normal_dir: Vector2 = (normal_tip - base).normalized()
	var tick_dir: Vector2 = Vector2(-normal_dir.y, normal_dir.x)
	draw_line(base - tick_dir * 4, base + tick_dir * 4, col, lw)
	# Arrowhead at tip pointing outward
	var arrow_size: float = 6.0
	var left: Vector2 = normal_tip - normal_dir * arrow_size + tick_dir * arrow_size * 0.5
	var right: Vector2 = normal_tip - normal_dir * arrow_size - tick_dir * arrow_size * 0.5
	draw_polygon(PackedVector2Array([normal_tip, left, right]), PackedColorArray([col, col, col]))


func _draw_bezier(c: Dictionary, col: Color, lw: float, offset: Vector2) -> void:
	var bpts: Array = c.get("points", [])
	var ctrls: Array = c.get("controls", [])
	if bpts.size() < 2:
		return
	var n: int = bpts.size()
	for seg_i in range(n - 1):
		var cp_out_idx: int = seg_i * 2
		var cp_in_idx: int = seg_i * 2 + 1
		if cp_out_idx >= ctrls.size() or cp_in_idx >= ctrls.size():
			break
		var p0 := Vector2(bpts[seg_i][0], bpts[seg_i][1]) + offset
		var p3 := Vector2(bpts[seg_i + 1][0], bpts[seg_i + 1][1]) + offset
		var p1 := Vector2(ctrls[cp_out_idx][0], ctrls[cp_out_idx][1]) + offset
		var p2 := Vector2(ctrls[cp_in_idx][0], ctrls[cp_in_idx][1]) + offset
		# Sample cubic bezier
		var prev: Vector2 = p0
		for s in range(1, BEZIER_SAMPLES + 1):
			var t: float = float(s) / float(BEZIER_SAMPLES)
			var it: float = 1.0 - t
			var pt: Vector2 = it * it * it * p0 + 3.0 * it * it * t * p1 + 3.0 * it * t * t * p2 + t * t * t * p3
			draw_line(prev, pt, col, lw)
			prev = pt
	# Draw control handle lines (thin, dimmed) when selected
	if c.get("selected", false):
		var handle_col := col * Color(1, 1, 1, 0.3)
		for seg_i in range(n - 1):
			var cp_out_idx: int = seg_i * 2
			var cp_in_idx: int = seg_i * 2 + 1
			if cp_out_idx >= ctrls.size() or cp_in_idx >= ctrls.size():
				break
			var anchor_start := Vector2(bpts[seg_i][0], bpts[seg_i][1]) + offset
			var anchor_end := Vector2(bpts[seg_i + 1][0], bpts[seg_i + 1][1]) + offset
			var ctrl_out := Vector2(ctrls[cp_out_idx][0], ctrls[cp_out_idx][1]) + offset
			var ctrl_in := Vector2(ctrls[cp_in_idx][0], ctrls[cp_in_idx][1]) + offset
			draw_line(anchor_start, ctrl_out, handle_col, 1.0)
			draw_line(anchor_end, ctrl_in, handle_col, 1.0)
	if not c.get("label", "").is_empty() and bpts.size() > 0:
		draw_string(_font, Vector2(bpts[0][0] + 4, bpts[0][1] - 8) + offset, c["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)


func _draw_control_points(c: Dictionary) -> void:
	## Draw edit handles (small squares) at each control point of a selected component.
	var offset: Vector2 = -global_position
	var cps: Array = get_control_points(c)
	for cp in cps:
		var p: Vector2 = cp["pos"] + offset
		var key: String = cp["key"]
		if key == "flip":
			# Special flip control — draw as a circle with arrows
			draw_circle(p, CP_SIZE + 1, CP_OUTLINE)
			draw_circle(p, CP_SIZE, Color(0.9, 0.6, 0.2))
			# Small up/down arrows
			draw_line(p + Vector2(0, -3), p + Vector2(0, 3), Color.BLACK, 1.0)
			draw_line(p + Vector2(0, -3), p + Vector2(-2, -1), Color.BLACK, 1.0)
			draw_line(p + Vector2(0, 3), p + Vector2(2, 1), Color.BLACK, 1.0)
			continue
		# Use blue for center/origin/anchor handles, white for edges/endpoints/controls
		var is_center: bool = key in ["center", "origin", "pos"] or key.begins_with("a")
		var fill: Color = CP_CENTER_FILL if is_center else CP_FILL
		draw_rect(Rect2(p.x - CP_SIZE, p.y - CP_SIZE, CP_SIZE * 2, CP_SIZE * 2), CP_OUTLINE, true)
		draw_rect(Rect2(p.x - CP_SIZE + 1, p.y - CP_SIZE + 1, CP_SIZE * 2 - 2, CP_SIZE * 2 - 2), fill, true)


func _draw_preview_control_points(ghost: Dictionary) -> void:
	## Draw semi-transparent control points on the preview ghost component.
	var offset: Vector2 = -global_position
	var cps: Array = get_control_points(ghost)
	for cp in cps:
		var p: Vector2 = cp["pos"] + offset
		var fill := Color(0.4, 0.7, 1.0, 0.5)
		draw_rect(Rect2(p.x - CP_SIZE, p.y - CP_SIZE, CP_SIZE * 2, CP_SIZE * 2), Color(0.0, 0.0, 0.0, 0.4), true)
		draw_rect(Rect2(p.x - CP_SIZE + 1, p.y - CP_SIZE + 1, CP_SIZE * 2 - 2, CP_SIZE * 2 - 2), fill, true)


func _draw_group_box(g: Dictionary) -> void:
	# Draw a bounding box around all components in the group using true AABB
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	var found := false
	for cid in g.get("component_ids", []):
		var c := get_component(int(cid))
		if c.is_empty() or not is_effectively_visible(c):
			continue
		var bounds: Rect2 = get_bounding_rect(c)
		if bounds.size.length_squared() < 0.001:
			# Point-like — use centroid with small margin
			var centroid := _get_centroid(c)
			min_pos.x = minf(min_pos.x, centroid.x - 4)
			min_pos.y = minf(min_pos.y, centroid.y - 4)
			max_pos.x = maxf(max_pos.x, centroid.x + 4)
			max_pos.y = maxf(max_pos.y, centroid.y + 4)
		else:
			min_pos.x = minf(min_pos.x, bounds.position.x)
			min_pos.y = minf(min_pos.y, bounds.position.y)
			max_pos.x = maxf(max_pos.x, bounds.end.x)
			max_pos.y = maxf(max_pos.y, bounds.end.y)
		found = true
	if not found:
		return
	var offset: Vector2 = -global_position
	var col: Color = _parse_color(g.get("color", "#888888"))
	col.a = 0.04
	var pad: float = 4.0
	var rect := Rect2(min_pos + offset - Vector2(pad, pad), max_pos - min_pos + Vector2(pad * 2, pad * 2))
	draw_rect(rect, col, true)
	col.a = 0.15
	draw_rect(rect, col, false, 1.0)
	# Group label
	col.a = 0.25
	draw_string(_font, rect.position + Vector2(4, -4), g.get("name", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, col)


func _draw_annotations(c: Dictionary) -> void:
	var annotations: Array = c.get("annotations", [])
	if annotations.is_empty():
		return
	var centroid := _get_centroid(c) - global_position
	var box_pos: Vector2 = centroid + ANNOTATION_OFFSET

	# Calculate box size
	var max_text_width: float = 0
	for ann in annotations:
		var prefix: String = "[%s] " % ann.get("producer", "?")
		var line_text: String = prefix + ann.get("text", "")
		var text_w: float = _font.get_string_size(line_text, HORIZONTAL_ALIGNMENT_LEFT, -1, ANNOTATION_FONT_SIZE).x
		max_text_width = maxf(max_text_width, text_w)
	max_text_width = minf(max_text_width, ANNOTATION_MAX_WIDTH)
	var box_w: float = max_text_width + ANNOTATION_PADDING * 2
	var box_h: float = annotations.size() * ANNOTATION_LINE_HEIGHT + ANNOTATION_PADDING * 2

	# Leader line from centroid to box
	draw_line(centroid, box_pos, ANNOTATION_BORDER, 1.0)

	# Background
	draw_rect(Rect2(box_pos, Vector2(box_w, box_h)), ANNOTATION_BG, true)
	draw_rect(Rect2(box_pos, Vector2(box_w, box_h)), ANNOTATION_BORDER, false, 1.0)

	# Text lines
	var ty: float = box_pos.y + ANNOTATION_PADDING + ANNOTATION_FONT_SIZE
	for ann in annotations:
		var producer: String = ann.get("producer", "?")
		var prefix_col: Color = ANNOTATION_H_COLOR if producer == "H" else ANNOTATION_A_COLOR
		var prefix: String = "[%s] " % producer
		var prefix_w: float = _font.get_string_size(prefix, HORIZONTAL_ALIGNMENT_LEFT, -1, ANNOTATION_FONT_SIZE).x
		draw_string(_font, Vector2(box_pos.x + ANNOTATION_PADDING, ty), prefix, HORIZONTAL_ALIGNMENT_LEFT, -1, ANNOTATION_FONT_SIZE, prefix_col)
		draw_string(_font, Vector2(box_pos.x + ANNOTATION_PADDING + prefix_w, ty), ann.get("text", ""), HORIZONTAL_ALIGNMENT_LEFT, max_text_width, ANNOTATION_FONT_SIZE, ANNOTATION_TEXT_COLOR)
		ty += ANNOTATION_LINE_HEIGHT


# ============================================================================
# HELPERS
# ============================================================================

func _make_base(type: String, color: String, label: String) -> Dictionary:
	var id: int = _next_id
	_next_id += 1
	return {
		"id": id,
		"type": type,
		"color": _resolve_color(color),
		"label": label,
		"visible": true,
		"selected": false,
		"locked": false,
		"line_width": DEFAULT_LINE_WIDTH,
		"annotations": [],
		"show_annotations": true,
		"layer_id": _active_layer_id,
		"group_id": -1,
	}


func _resolve_color(input: String) -> String:
	## Convert named color or hex to stored hex format
	var lower: String = input.strip_edges().to_lower()
	if NAMED_COLORS.has(lower):
		return NAMED_COLORS[lower]
	if lower.begins_with("#"):
		return lower
	# Try Godot's named color
	var test := Color.from_string(lower, Color(-1, -1, -1))
	if test.r >= 0:
		return "#" + test.to_html(false)
	return DEFAULT_COLOR


func _parse_color(hex: String) -> Color:
	## Parse a stored color string (hex or named) to Godot Color
	if not hex.begins_with("#"):
		# Might be a named color — resolve it first
		var resolved: String = _resolve_color(hex)
		if resolved.begins_with("#"):
			return Color.from_string(resolved, Color.RED)
		return Color.from_string("#" + resolved, Color.RED)
	return Color.from_string(hex, Color.RED)


func _get_centroid(c: Dictionary) -> Vector2:
	match c["type"]:
		"point":
			return Vector2(c["x"], c["y"])
		"rect":
			return Vector2(c["x"] + c["w"] * 0.5, c["y"] + c["h"] * 0.5)
		"circle":
			return Vector2(c["cx"], c["cy"])
		"ellipse":
			return Vector2(c["cx"], c["cy"])
		"line", "arrow":
			return Vector2((c["x1"] + c["x2"]) * 0.5, (c["y1"] + c["y2"]) * 0.5)
		"polyline", "poly":
			var pts: Array = c.get("points", [])
			if pts.is_empty():
				return Vector2.ZERO
			var sum := Vector2.ZERO
			for p in pts:
				sum += Vector2(p[0], p[1])
			return sum / pts.size()
		"vector":
			return Vector2(c["ox"] + c["dx"] * 0.5, c["oy"] + c["dy"] * 0.5)
		"normal":
			var ref := get_component(c.get("ref_id", -1))
			if not ref.is_empty():
				return _get_centroid(ref)
		"arc":
			var mid_a: float = c["start_angle"] + c["sweep_angle"] * 0.5
			return Vector2(c["cx"] + cos(mid_a) * c["r"], c["cy"] + sin(mid_a) * c["r"])
		"bezier":
			var bpts: Array = c.get("points", [])
			if not bpts.is_empty():
				var sum := Vector2.ZERO
				for p in bpts:
					sum += Vector2(p[0], p[1])
				return sum / bpts.size()
	return Vector2.ZERO


func snap_to_grid(pos: Vector2) -> Vector2:
	## Snap a position to the nearest minor grid intersection.
	return Vector2(roundf(pos.x / GRID_MINOR) * GRID_MINOR, roundf(pos.y / GRID_MINOR) * GRID_MINOR)


func snap_to_components(pos: Vector2, exclude_ids: Array = [], radius: float = 12.0) -> Vector2:
	## Snap to the nearest control point or notable position on existing components.
	var best_pos: Vector2 = pos
	var best_dist: float = radius
	for c in _components:
		if not c.get("visible", true) or c["id"] in exclude_ids:
			continue
		var cps: Array = get_control_points(c)
		for cp in cps:
			var d: float = pos.distance_to(cp["pos"])
			if d < best_dist:
				best_dist = d
				best_pos = cp["pos"]
	return best_pos


func _points_to_packed(points: Array, offset: Vector2) -> PackedVector2Array:
	var packed := PackedVector2Array()
	for p in points:
		packed.append(Vector2(p[0], p[1]) + offset)
	return packed


func _draw_label_at_midpoint(c: Dictionary, p1: Vector2, p2: Vector2, col: Color) -> void:
	if not c.get("label", "").is_empty():
		var mid: Vector2 = (p1 + p2) * 0.5
		draw_string(_font, mid + Vector2(4, -4), c["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)


func _draw_label_at_packed(c: Dictionary, pts: PackedVector2Array, col: Color) -> void:
	if not c.get("label", "").is_empty() and pts.size() > 0:
		draw_string(_font, pts[0] + Vector2(4, -8), c["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)


func _sample_polyline(points: Array, t: float, closed: bool) -> Array:
	## Sample position and normal along a polyline at parameter t [0..1].
	## Returns [position: Vector2, normal: Vector2]
	if points.size() < 2:
		if points.size() == 1:
			return [Vector2(points[0][0], points[0][1]), Vector2.UP]
		return [Vector2.ZERO, Vector2.UP]

	# Build segment lengths
	var segments: Array[Vector2] = []
	var lengths: Array[float] = []
	var total_len: float = 0.0
	var count: int = points.size()
	var seg_count: int = count - 1 + (1 if closed else 0)

	for i in range(seg_count):
		var j: int = (i + 1) % count
		var a := Vector2(points[i][0], points[i][1])
		var b := Vector2(points[j][0], points[j][1])
		var seg_len: float = a.distance_to(b)
		segments.append(b - a)
		lengths.append(seg_len)
		total_len += seg_len

	if total_len < 0.001:
		return [Vector2(points[0][0], points[0][1]), Vector2.UP]

	var target_len: float = t * total_len
	var accumulated: float = 0.0
	for i in range(segments.size()):
		if accumulated + lengths[i] >= target_len or i == segments.size() - 1:
			var seg_t: float = (target_len - accumulated) / maxf(lengths[i], 0.001)
			var a := Vector2(points[i][0], points[i][1])
			var pos: Vector2 = a + segments[i] * seg_t
			var dir: Vector2 = segments[i].normalized()
			var normal: Vector2 = Vector2(-dir.y, dir.x)
			return [pos, normal]
		accumulated += lengths[i]

	return [Vector2(points[0][0], points[0][1]), Vector2.UP]
