extends CanvasLayer

## Pose Library — browsable overlay for splay poses.
## Shows all available poses as a list with preview thumbnails.
## Accessed from level editor SPLAY mode via P key.

signal pose_selected(pose_name: String)
signal closed

var _active := false
var _poses: Array[String] = []
var _pose_data: Dictionary = {}  # name -> parsed pose dict
var _selected_idx: int = 0
var _scroll_offset: int = 0
var _filter_text: String = ""
var _filtered_poses: Array[String] = []
var _overlay: Control = null


func _ready() -> void:
	layer = 90
	_overlay = Control.new()
	_overlay.name = "PoseLibraryOverlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	visible = false


func open() -> void:
	_active = true
	visible = true
	_load_poses()
	_apply_filter()
	_selected_idx = 0
	_scroll_offset = 0


func close() -> void:
	_active = false
	visible = false
	closed.emit()


func _load_poses() -> void:
	var mgr_script: GDScript = load("res://scripts/systems/splay_manager.gd")
	var temp := Node.new()
	temp.set_script(mgr_script)
	add_child(temp)
	_poses = temp.get_all_pose_names()
	_pose_data.clear()
	for pname in _poses:
		_pose_data[pname] = temp.load_pose(pname)
	temp.queue_free()


func _apply_filter() -> void:
	_filtered_poses.clear()
	for pname in _poses:
		if _filter_text.is_empty() or _filter_text.to_lower() in pname.to_lower():
			_filtered_poses.append(pname)
	_selected_idx = clampi(_selected_idx, 0, maxi(_filtered_poses.size() - 1, 0))


func _input(event: InputEvent) -> void:
	if not _active:
		return

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				close()
				get_viewport().set_input_as_handled()
			KEY_UP:
				_selected_idx = maxi(_selected_idx - 1, 0)
				_ensure_visible()
				get_viewport().set_input_as_handled()
			KEY_DOWN:
				_selected_idx = mini(_selected_idx + 1, _filtered_poses.size() - 1)
				_ensure_visible()
				get_viewport().set_input_as_handled()
			KEY_ENTER:
				if _selected_idx >= 0 and _selected_idx < _filtered_poses.size():
					pose_selected.emit(_filtered_poses[_selected_idx])
					close()
				get_viewport().set_input_as_handled()
			KEY_BACKSPACE:
				if _filter_text.length() > 0:
					_filter_text = _filter_text.substr(0, _filter_text.length() - 1)
					_apply_filter()
				get_viewport().set_input_as_handled()
			_:
				# Type to filter
				var ch: String = char(event.unicode) if event.unicode > 0 else ""
				if ch.length() == 1 and (ch.is_valid_identifier() or ch == "-"):
					_filter_text += ch
					_apply_filter()
					get_viewport().set_input_as_handled()

	if _overlay:
		_overlay.queue_redraw()


func _ensure_visible() -> void:
	var visible_count: int = 12
	if _selected_idx < _scroll_offset:
		_scroll_offset = _selected_idx
	elif _selected_idx >= _scroll_offset + visible_count:
		_scroll_offset = _selected_idx - visible_count + 1


func _draw_overlay() -> void:
	if not _active:
		return

	var vp: Vector2 = get_viewport().get_visible_rect().size

	# Background panel
	var panel_x: float = vp.x * 0.15
	var panel_w: float = vp.x * 0.7
	var panel_y: float = 40.0
	var panel_h: float = vp.y - 80.0
	_overlay.draw_rect(Rect2(panel_x, panel_y, panel_w, panel_h), Color(0.1, 0.1, 0.12, 0.95))
	_overlay.draw_rect(Rect2(panel_x, panel_y, panel_w, panel_h), Color(0.5, 0.4, 0.3, 0.6), false, 2.0)

	# Title
	_overlay.draw_string(ThemeDB.fallback_font, Vector2(panel_x + 20, panel_y + 28), "SPLAY POSE LIBRARY", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.8, 0.3))

	# Filter
	var filter_text: String = "Filter: " + _filter_text + "_"
	_overlay.draw_string(ThemeDB.fallback_font, Vector2(panel_x + 20, panel_y + 50), filter_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.7, 0.7))

	# Pose list (left side)
	var list_x: float = panel_x + 20
	var list_y: float = panel_y + 70
	var row_h: float = 28.0
	var visible_count: int = int((panel_h - 90) / row_h)

	for i in range(visible_count):
		var pi: int = _scroll_offset + i
		if pi >= _filtered_poses.size():
			break
		var pname: String = _filtered_poses[pi]
		var y: float = list_y + i * row_h
		var is_selected: bool = (pi == _selected_idx)

		if is_selected:
			_overlay.draw_rect(Rect2(list_x - 4, y - 14, panel_w * 0.4, row_h - 2), Color(0.3, 0.25, 0.15, 0.8))

		var col: Color = Color(1.0, 0.9, 0.5) if is_selected else Color(0.7, 0.7, 0.7)
		var pose: Dictionary = _pose_data.get(pname, {})
		var conn_count: int = pose.get("connections", []).size()
		var creature: String = pose.get("creature", "?")
		var label: String = "%s  (%s, %d pts)" % [pname, creature, conn_count]
		_overlay.draw_string(ThemeDB.fallback_font, Vector2(list_x, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)

	# Preview (right side) — draw the selected pose's connection layout
	if _selected_idx >= 0 and _selected_idx < _filtered_poses.size():
		var pname: String = _filtered_poses[_selected_idx]
		var pose: Dictionary = _pose_data.get(pname, {})
		_draw_pose_preview(pose, panel_x + panel_w * 0.5, panel_y + 100, panel_w * 0.4, panel_h - 140)

	# Help
	_overlay.draw_string(ThemeDB.fallback_font, Vector2(panel_x + 20, panel_y + panel_h - 10),
		"Up/Down=select  Enter=place  Esc=close  Type to filter",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.5, 0.5))


func _draw_pose_preview(pose: Dictionary, x: float, y: float, w: float, h: float) -> void:
	## Draw a schematic preview of the pose.
	if pose.is_empty():
		return

	# Border
	_overlay.draw_rect(Rect2(x, y, w, h), Color(0.15, 0.15, 0.18, 0.8))
	_overlay.draw_rect(Rect2(x, y, w, h), Color(0.4, 0.35, 0.3, 0.5), false, 1.0)

	var center := Vector2(x + w / 2.0, y + h / 2.0)
	var scale: float = minf(w, h) / 250.0  # Fit 250px pose into preview area

	# Origin
	_overlay.draw_circle(center, 6.0, Color(0.5, 0.4, 0.3, 0.6))

	# Connections
	var connections: Array = pose.get("connections", [])
	for conn in connections:
		var rel: Array = conn.get("relative_pos", [0, 0])
		var cast: Array = conn.get("cast_dir", [0, -1])
		var point_name: String = conn.get("point", "?")
		var conn_pos: Vector2 = center + Vector2(rel[0], rel[1]) * scale
		var cast_dir: Vector2 = Vector2(cast[0], cast[1]).normalized()

		# Line from origin
		_overlay.draw_line(center, conn_pos, Color(0.4, 0.7, 1.0, 0.3), 1.0)

		# Connection dot
		_overlay.draw_circle(conn_pos, 5.0, Color(0.4, 0.8, 1.0, 0.8))

		# Cast direction arrow
		var arrow_end: Vector2 = conn_pos + cast_dir * 25.0 * scale
		_overlay.draw_line(conn_pos, arrow_end, Color(1.0, 0.4, 0.3, 0.5), 1.5)

		# Label
		_overlay.draw_string(ThemeDB.fallback_font, conn_pos + Vector2(8, -4), point_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.6, 0.8, 1.0))

	# Pose name
	_overlay.draw_string(ThemeDB.fallback_font, Vector2(x + 8, y + 18), pose.get("name", "?"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.8, 0.3))
