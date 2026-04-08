extends RefCounted

## Tool state machine for whiteboard world-space interaction.
## Manages click/drag/release for Select, Point, Line, Rect, Circle, etc.
## Created by the debug drawer, called from its _input handler.

enum Tool {
	SELECT, ANNOTATE, POINT, LINE, POLYLINE, POLY,
	RECT, CIRCLE, ELLIPSE, ARROW, VECTOR, NORMAL
}

# -- State --
var _whiteboard: Node2D = null  # The whiteboard.gd node
var _active_tool: Tool = Tool.SELECT
var _color: String = "red"
var _line_width: float = 2.0

# Drawing state (in-progress operations)
var _drawing: bool = false          # True while a draw op is in progress
var _start_pos: Vector2 = Vector2.ZERO
var _current_pos: Vector2 = Vector2.ZERO
var _poly_points: Array = []        # For polyline/poly multi-click
var _preview: Dictionary = {}       # Ghost component for preview rendering
var _did_drag: bool = false         # True if mouse moved meaningfully during draw

# Selection state
var _drag_selected: bool = false    # True when drag-moving a selected component
var _drag_id: int = -1

# Control point drag state
var _cp_dragging: bool = false
var _cp_comp_id: int = -1
var _cp_key: String = ""

const CP_HIT_RADIUS := 8.0
const MIN_DRAG_DISTANCE := 3.0


func setup(whiteboard: Node2D) -> void:
	_whiteboard = whiteboard


func set_tool(tool_idx: int) -> void:
	cancel()
	if tool_idx >= 0 and tool_idx < Tool.size():
		_active_tool = tool_idx as Tool


func set_color(color_name: String) -> void:
	_color = color_name


# ============================================================================
# INPUT HANDLERS — called by debug_drawer when click is in world space
# ============================================================================

func handle_click(world_pos: Vector2) -> void:
	if not _whiteboard:
		return

	match _active_tool:
		Tool.SELECT:
			_handle_select_click(world_pos)
		Tool.ANNOTATE:
			_handle_annotate_click(world_pos)
		Tool.POINT:
			var new_id: int = _whiteboard.add_point(world_pos.x, world_pos.y, _color)
			_select_new(new_id)
		Tool.LINE, Tool.ARROW, Tool.RECT, Tool.CIRCLE, Tool.ELLIPSE, Tool.VECTOR:
			if not _drawing:
				_drawing = true
				_did_drag = false
				_start_pos = world_pos
				_current_pos = world_pos
			else:
				# Second click finalization (two-click mode)
				_finalize_two_step(world_pos)
		Tool.POLYLINE, Tool.POLY:
			_handle_poly_click(world_pos)
		Tool.NORMAL:
			_handle_normal_click(world_pos)


func handle_drag(world_pos: Vector2) -> void:
	if not _whiteboard:
		return
	_current_pos = world_pos

	# Control point dragging takes priority
	if _cp_dragging and _cp_comp_id >= 0:
		_apply_cp_drag(world_pos)
		return

	# Whole-component dragging (SELECT tool)
	if _active_tool == Tool.SELECT and _drag_selected and _drag_id >= 0:
		var delta: Vector2 = world_pos - _start_pos
		_whiteboard.move_component(_drag_id, delta.x, delta.y)
		_start_pos = world_pos
		return

	# Two-step tool: mark that we've actually dragged
	if _drawing:
		if world_pos.distance_to(_start_pos) > MIN_DRAG_DISTANCE:
			_did_drag = true

	_update_preview()


func handle_release(world_pos: Vector2) -> void:
	if not _whiteboard:
		return

	# Control point release
	if _cp_dragging:
		_cp_dragging = false
		_cp_comp_id = -1
		_cp_key = ""
		return

	# Select drag release
	if _active_tool == Tool.SELECT:
		_drag_selected = false
		_drag_id = -1
		return

	# Two-step tool: finalize on release if user actually dragged far enough
	if _drawing and _did_drag:
		if world_pos.distance_to(_start_pos) > MIN_DRAG_DISTANCE:
			_finalize_two_step(world_pos)
		else:
			_did_drag = false  # Reset — keep _drawing true for two-click mode


func handle_double_click(_world_pos: Vector2) -> void:
	if not _whiteboard:
		return
	# Finalize polyline/poly on double-click
	if _active_tool in [Tool.POLYLINE, Tool.POLY] and _poly_points.size() >= 2:
		_finish_poly()


func cancel() -> void:
	_drawing = false
	_did_drag = false
	_poly_points.clear()
	_preview.clear()
	_drag_selected = false
	_drag_id = -1
	_cp_dragging = false
	_cp_comp_id = -1
	_cp_key = ""
	if _whiteboard:
		_whiteboard.queue_redraw()


func is_drawing() -> bool:
	return _drawing or not _poly_points.is_empty()


func get_preview() -> Dictionary:
	return _preview


# ============================================================================
# TOOL-SPECIFIC HANDLERS
# ============================================================================

func _handle_select_click(world_pos: Vector2) -> void:
	# First check if clicking a control point of an already-selected component
	var cp_hit: Dictionary = _cp_hit_test(world_pos)
	if not cp_hit.is_empty():
		_cp_dragging = true
		_cp_comp_id = cp_hit["comp_id"]
		_cp_key = cp_hit["key"]
		return

	# Otherwise, try to select a component
	var hit_id: int = _hit_test(world_pos)
	if hit_id >= 0:
		_whiteboard.deselect_all()
		_whiteboard.select_component(hit_id)
		_drag_selected = true
		_drag_id = hit_id
		_start_pos = world_pos
	else:
		_whiteboard.deselect_all()


func _handle_annotate_click(world_pos: Vector2) -> void:
	# Select component under click for annotation
	var hit_id: int = _hit_test(world_pos)
	if hit_id >= 0:
		_whiteboard.deselect_all()
		_whiteboard.select_component(hit_id)
		# The annotation text field in the Settings pane is auto-focused by the drawer


func _handle_poly_click(world_pos: Vector2) -> void:
	_poly_points.append([world_pos.x, world_pos.y])
	_drawing = true
	_current_pos = world_pos
	_update_preview()


func _handle_normal_click(world_pos: Vector2) -> void:
	# Find the nearest component and compute t parameter
	var best_id: int = -1
	var best_t: float = 0.5
	var best_dist: float = 50.0  # Max distance for normal placement

	for c in _whiteboard.get_all_components():
		if c["type"] in ["point", "normal"]:
			continue
		var result: Array = _nearest_point_on_component(c, world_pos)
		if result[0] < best_dist:
			best_dist = result[0]
			best_id = c["id"]
			best_t = result[1]

	if best_id >= 0:
		var new_id: int = _whiteboard.add_normal(best_id, best_t, 30.0, false, _color)
		_select_new(new_id)


func _select_new(id: int) -> void:
	## Auto-select a freshly created component so its CPs show immediately
	if id >= 0 and _whiteboard:
		_whiteboard.deselect_all()
		_whiteboard.select_component(id)


func _finalize_two_step(end_pos: Vector2) -> void:
	## Dispatch finalization to the correct shape builder
	var new_id: int = -1
	match _active_tool:
		Tool.LINE:
			new_id = _whiteboard.add_line(_start_pos.x, _start_pos.y, end_pos.x, end_pos.y, _color)
		Tool.ARROW:
			new_id = _whiteboard.add_arrow(_start_pos.x, _start_pos.y, end_pos.x, end_pos.y, _color)
		Tool.RECT:
			var x: float = minf(_start_pos.x, end_pos.x)
			var y: float = minf(_start_pos.y, end_pos.y)
			var w: float = absf(end_pos.x - _start_pos.x)
			var h: float = absf(end_pos.y - _start_pos.y)
			if w > 1 and h > 1:
				new_id = _whiteboard.add_rect(x, y, w, h, _color)
		Tool.CIRCLE:
			var r: float = _start_pos.distance_to(end_pos)
			if r > 1:
				new_id = _whiteboard.add_circle(_start_pos.x, _start_pos.y, r, _color)
		Tool.ELLIPSE:
			var rx: float = absf(end_pos.x - _start_pos.x)
			var ry: float = absf(end_pos.y - _start_pos.y)
			if rx > 1 and ry > 1:
				new_id = _whiteboard.add_ellipse(_start_pos.x, _start_pos.y, rx, ry, _color)
		Tool.VECTOR:
			var dx: float = end_pos.x - _start_pos.x
			var dy: float = end_pos.y - _start_pos.y
			if Vector2(dx, dy).length() > 1:
				new_id = _whiteboard.add_vector(_start_pos.x, _start_pos.y, dx, dy, _color)
	_drawing = false
	_did_drag = false
	_preview.clear()
	_select_new(new_id)


func _finish_poly() -> void:
	if _poly_points.size() < 2:
		_poly_points.clear()
		_drawing = false
		return
	var new_id: int = -1
	if _active_tool == Tool.POLYLINE:
		new_id = _whiteboard.add_polyline(_poly_points.duplicate(), _color)
	elif _active_tool == Tool.POLY:
		if _poly_points.size() >= 3:
			new_id = _whiteboard.add_poly(_poly_points.duplicate(), _color)
	_poly_points.clear()
	_drawing = false
	_preview.clear()
	_select_new(new_id)


# ============================================================================
# CONTROL POINT HIT TESTING & DRAGGING
# ============================================================================

func _cp_hit_test(world_pos: Vector2) -> Dictionary:
	## Check if world_pos hits a control point of any selected component.
	## Returns {"comp_id": int, "key": String} or empty dict.
	if not _whiteboard:
		return {}
	for c in _whiteboard.get_all_components():
		if not c.get("selected", false) or not c.get("visible", true):
			continue
		var cps: Array = _whiteboard.get_control_points(c)
		for cp in cps:
			if world_pos.distance_to(cp["pos"]) < CP_HIT_RADIUS:
				return {"comp_id": c["id"], "key": cp["key"]}
	return {}


func _apply_cp_drag(world_pos: Vector2) -> void:
	## Move the active control point to world_pos
	var c: Dictionary = _whiteboard.get_component(_cp_comp_id)
	if c.is_empty():
		return

	match c["type"]:
		"point":
			if _cp_key == "pos":
				c["x"] = world_pos.x; c["y"] = world_pos.y
		"line", "arrow":
			if _cp_key == "p1":
				c["x1"] = world_pos.x; c["y1"] = world_pos.y
			elif _cp_key == "p2":
				c["x2"] = world_pos.x; c["y2"] = world_pos.y
		"rect":
			_apply_rect_cp(c, world_pos)
		"circle":
			if _cp_key == "center":
				c["cx"] = world_pos.x; c["cy"] = world_pos.y
			elif _cp_key == "radius":
				c["r"] = maxf(1.0, Vector2(c["cx"], c["cy"]).distance_to(world_pos))
		"ellipse":
			if _cp_key == "center":
				c["cx"] = world_pos.x; c["cy"] = world_pos.y
			elif _cp_key == "rx":
				c["rx"] = maxf(1.0, absf(world_pos.x - c["cx"]))
			elif _cp_key == "ry":
				c["ry"] = maxf(1.0, absf(world_pos.y - c["cy"]))
		"polyline", "poly":
			if _cp_key.begins_with("p"):
				var idx: int = _cp_key.substr(1).to_int()
				var pts: Array = c.get("points", [])
				if idx >= 0 and idx < pts.size():
					pts[idx] = [world_pos.x, world_pos.y]
		"vector":
			if _cp_key == "origin":
				c["ox"] = world_pos.x; c["oy"] = world_pos.y
			elif _cp_key == "tip":
				c["dx"] = world_pos.x - c["ox"]
				c["dy"] = world_pos.y - c["oy"]
		"normal":
			if _cp_key == "base":
				# Recompute t parameter along reference component
				var ref: Dictionary = _whiteboard.get_component(c.get("ref_id", -1))
				if not ref.is_empty():
					var result: Array = _nearest_point_on_component(ref, world_pos)
					c["t"] = clampf(result[1], 0.0, 1.0)
			elif _cp_key == "tip":
				# Adjust length based on distance from base
				var endpoints: Array = _whiteboard._get_normal_endpoints(c)
				if not endpoints.is_empty():
					c["length"] = maxf(5.0, world_pos.distance_to(endpoints[0]))

	_whiteboard.queue_redraw()


func _apply_rect_cp(c: Dictionary, world_pos: Vector2) -> void:
	## Drag a rect corner — opposite corner stays fixed
	var rx: float = c["x"]; var ry: float = c["y"]
	var rw: float = c["w"]; var rh: float = c["h"]
	var fixed: Vector2
	match _cp_key:
		"tl": fixed = Vector2(rx + rw, ry + rh)
		"tr": fixed = Vector2(rx, ry + rh)
		"br": fixed = Vector2(rx, ry)
		"bl": fixed = Vector2(rx + rw, ry)
		_: return
	c["x"] = minf(fixed.x, world_pos.x)
	c["y"] = minf(fixed.y, world_pos.y)
	c["w"] = maxf(1.0, absf(world_pos.x - fixed.x))
	c["h"] = maxf(1.0, absf(world_pos.y - fixed.y))


# ============================================================================
# PREVIEW — ghost rendering for in-progress operations
# ============================================================================

func _update_preview() -> void:
	if not _drawing and _poly_points.is_empty():
		_preview.clear()
		return

	match _active_tool:
		Tool.LINE:
			_preview = {"type": "line", "x1": _start_pos.x, "y1": _start_pos.y,
				"x2": _current_pos.x, "y2": _current_pos.y, "color": _color,
				"line_width": _line_width, "visible": true, "selected": false,
				"id": -1, "label": "", "annotations": [], "show_annotations": false}
		Tool.ARROW:
			_preview = {"type": "arrow", "x1": _start_pos.x, "y1": _start_pos.y,
				"x2": _current_pos.x, "y2": _current_pos.y, "color": _color,
				"line_width": _line_width, "head_size": 12.0, "visible": true,
				"selected": false, "id": -1, "label": "", "annotations": [],
				"show_annotations": false}
		Tool.RECT:
			var x: float = minf(_start_pos.x, _current_pos.x)
			var y: float = minf(_start_pos.y, _current_pos.y)
			_preview = {"type": "rect", "x": x, "y": y,
				"w": absf(_current_pos.x - _start_pos.x),
				"h": absf(_current_pos.y - _start_pos.y),
				"color": _color, "line_width": _line_width, "visible": true,
				"selected": false, "id": -1, "label": "", "annotations": [],
				"show_annotations": false}
		Tool.CIRCLE:
			var r: float = _start_pos.distance_to(_current_pos)
			_preview = {"type": "circle", "cx": _start_pos.x, "cy": _start_pos.y,
				"r": r, "color": _color, "line_width": _line_width, "visible": true,
				"selected": false, "id": -1, "label": "", "annotations": [],
				"show_annotations": false}
		Tool.ELLIPSE:
			_preview = {"type": "ellipse", "cx": _start_pos.x, "cy": _start_pos.y,
				"rx": absf(_current_pos.x - _start_pos.x),
				"ry": absf(_current_pos.y - _start_pos.y),
				"color": _color, "line_width": _line_width, "visible": true,
				"selected": false, "id": -1, "label": "", "annotations": [],
				"show_annotations": false}
		Tool.VECTOR:
			var dx: float = _current_pos.x - _start_pos.x
			var dy: float = _current_pos.y - _start_pos.y
			_preview = {"type": "vector", "ox": _start_pos.x, "oy": _start_pos.y,
				"dx": dx, "dy": dy, "color": _color, "line_width": _line_width,
				"visible": true, "selected": false, "id": -1, "label": "",
				"annotations": [], "show_annotations": false}
		Tool.POLYLINE, Tool.POLY:
			var pts: Array = _poly_points.duplicate()
			pts.append([_current_pos.x, _current_pos.y])
			var ptype: String = "polyline" if _active_tool == Tool.POLYLINE else "poly"
			_preview = {"type": ptype, "points": pts, "color": _color,
				"line_width": _line_width, "visible": true, "selected": false,
				"id": -1, "label": "", "annotations": [], "show_annotations": false}
		_:
			_preview.clear()

	if _whiteboard:
		_whiteboard.queue_redraw()


# ============================================================================
# HIT TESTING — find component near a world position
# ============================================================================

func _hit_test(pos: Vector2) -> int:
	## Find the component closest to pos within a hit radius. Returns id or -1.
	if not _whiteboard:
		return -1
	var hit_radius: float = 15.0
	var best_id: int = -1
	var best_dist: float = hit_radius

	for c in _whiteboard.get_all_components():
		if not c.get("visible", true):
			continue
		var dist: float = _distance_to_component(c, pos)
		if dist < best_dist:
			best_dist = dist
			best_id = c["id"]

	return best_id


func _distance_to_component(c: Dictionary, pos: Vector2) -> float:
	match c["type"]:
		"point":
			return pos.distance_to(Vector2(c["x"], c["y"]))
		"circle":
			var center := Vector2(c["cx"], c["cy"])
			return absf(pos.distance_to(center) - c["r"])
		"ellipse":
			var center := Vector2(c["cx"], c["cy"])
			# Approximate: distance to center scaled by ellipse shape
			var dx: float = (pos.x - center.x) / maxf(c["rx"], 1.0)
			var dy: float = (pos.y - center.y) / maxf(c["ry"], 1.0)
			var normalized_dist: float = sqrt(dx * dx + dy * dy)
			return absf(normalized_dist - 1.0) * minf(c["rx"], c["ry"])
		"rect":
			var rect := Rect2(c["x"], c["y"], c["w"], c["h"])
			# Distance to rect edges
			return _distance_to_rect_edge(rect, pos)
		"line", "arrow":
			var p1 := Vector2(c["x1"], c["y1"])
			var p2 := Vector2(c["x2"], c["y2"])
			return _distance_to_segment(p1, p2, pos)
		"polyline":
			return _distance_to_polyline(c["points"], pos, false)
		"poly":
			return _distance_to_polyline(c["points"], pos, true)
		"vector":
			var origin := Vector2(c["ox"], c["oy"])
			var tip := origin + Vector2(c["dx"], c["dy"])
			return _distance_to_segment(origin, tip, pos)
		"normal":
			# Use the normal's actual endpoints for hit testing
			if _whiteboard:
				var endpoints: Array = _whiteboard._get_normal_endpoints(c)
				if endpoints.size() >= 2:
					return _distance_to_segment(endpoints[0], endpoints[1], pos)
			var centroid: Vector2 = _whiteboard._get_centroid(c)
			return pos.distance_to(centroid)
	return 999.0


func _distance_to_segment(a: Vector2, b: Vector2, p: Vector2) -> float:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq < 0.001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	var projection: Vector2 = a + ab * t
	return p.distance_to(projection)


func _distance_to_rect_edge(rect: Rect2, p: Vector2) -> float:
	# Distance to nearest edge of rect
	var min_dist: float = 999.0
	var corners: Array[Vector2] = [
		rect.position,
		rect.position + Vector2(rect.size.x, 0),
		rect.position + rect.size,
		rect.position + Vector2(0, rect.size.y),
	]
	for i in range(4):
		var d: float = _distance_to_segment(corners[i], corners[(i + 1) % 4], p)
		min_dist = minf(min_dist, d)
	return min_dist


func _distance_to_polyline(points: Array, p: Vector2, closed: bool) -> float:
	if points.size() < 2:
		if points.size() == 1:
			return p.distance_to(Vector2(points[0][0], points[0][1]))
		return 999.0
	var min_dist: float = 999.0
	var count: int = points.size()
	var seg_count: int = count - 1 + (1 if closed else 0)
	for i in range(seg_count):
		var j: int = (i + 1) % count
		var a := Vector2(points[i][0], points[i][1])
		var b := Vector2(points[j][0], points[j][1])
		var d: float = _distance_to_segment(a, b, p)
		min_dist = minf(min_dist, d)
	return min_dist


func _nearest_point_on_component(c: Dictionary, pos: Vector2) -> Array:
	## Returns [distance: float, t: float] — nearest distance and parameter
	match c["type"]:
		"line", "arrow":
			var p1 := Vector2(c["x1"], c["y1"])
			var p2 := Vector2(c["x2"], c["y2"])
			var ab: Vector2 = p2 - p1
			var len_sq: float = ab.length_squared()
			var t: float = 0.5
			if len_sq > 0.001:
				t = clampf((pos - p1).dot(ab) / len_sq, 0.0, 1.0)
			var proj: Vector2 = p1 + ab * t
			return [pos.distance_to(proj), t]

		"circle":
			var center := Vector2(c["cx"], c["cy"])
			var dir: Vector2 = (pos - center).normalized()
			var angle: float = atan2(dir.y, dir.x)
			if angle < 0:
				angle += TAU
			var t: float = angle / TAU
			var nearest: Vector2 = center + dir * c["r"]
			return [pos.distance_to(nearest), t]

		"rect":
			var rect := Rect2(c["x"], c["y"], c["w"], c["h"])
			var corners: Array[Vector2] = [
				rect.position,
				rect.position + Vector2(rect.size.x, 0),
				rect.position + rect.size,
				rect.position + Vector2(0, rect.size.y),
			]
			var perimeter: float = 2.0 * (rect.size.x + rect.size.y)
			var best_dist: float = 999.0
			var best_t: float = 0.0
			var acc_len: float = 0.0
			for i in range(4):
				var a: Vector2 = corners[i]
				var b: Vector2 = corners[(i + 1) % 4]
				var seg_len: float = a.distance_to(b)
				var ab: Vector2 = b - a
				var len_sq: float = ab.length_squared()
				var seg_t: float = 0.5
				if len_sq > 0.001:
					seg_t = clampf((pos - a).dot(ab) / len_sq, 0.0, 1.0)
				var proj: Vector2 = a + ab * seg_t
				var d: float = pos.distance_to(proj)
				if d < best_dist:
					best_dist = d
					best_t = (acc_len + seg_t * seg_len) / maxf(perimeter, 0.001)
				acc_len += seg_len
			return [best_dist, best_t]

		"polyline", "poly":
			var points: Array = c["points"]
			if points.size() < 2:
				return [999.0, 0.0]
			var closed: bool = c["type"] == "poly"
			var count: int = points.size()
			var seg_count: int = count - 1 + (1 if closed else 0)
			var total_len: float = 0.0
			var seg_lens: Array[float] = []
			for i in range(seg_count):
				var j: int = (i + 1) % count
				var a := Vector2(points[i][0], points[i][1])
				var b := Vector2(points[j][0], points[j][1])
				var sl: float = a.distance_to(b)
				seg_lens.append(sl)
				total_len += sl
			var best_dist: float = 999.0
			var best_t: float = 0.0
			var acc_len: float = 0.0
			for i in range(seg_count):
				var j: int = (i + 1) % count
				var a := Vector2(points[i][0], points[i][1])
				var b := Vector2(points[j][0], points[j][1])
				var ab: Vector2 = b - a
				var len_sq: float = ab.length_squared()
				var seg_t: float = 0.5
				if len_sq > 0.001:
					seg_t = clampf((pos - a).dot(ab) / len_sq, 0.0, 1.0)
				var proj: Vector2 = a + ab * seg_t
				var d: float = pos.distance_to(proj)
				if d < best_dist:
					best_dist = d
					best_t = (acc_len + seg_t * seg_lens[i]) / maxf(total_len, 0.001)
				acc_len += seg_lens[i]
			return [best_dist, best_t]

		"vector":
			var origin := Vector2(c["ox"], c["oy"])
			var tip := origin + Vector2(c["dx"], c["dy"])
			var ab: Vector2 = tip - origin
			var len_sq: float = ab.length_squared()
			var t: float = 0.5
			if len_sq > 0.001:
				t = clampf((pos - origin).dot(ab) / len_sq, 0.0, 1.0)
			var proj: Vector2 = origin + ab * t
			return [pos.distance_to(proj), t]

	return [999.0, 0.5]
