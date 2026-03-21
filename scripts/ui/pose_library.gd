extends CanvasLayer

## Pose Library — browsable overlay for splay poses.
## Shows all available poses as a list with usage tracking and CRUD.
## Accessed from level editor SPLAY mode via P key.

signal pose_selected(pose_name: String)
signal pose_edit_requested(pose_name: String)
signal closed

var _active := false
var _replacement_mode := false  # True when choosing a replacement for a missing pose
var _poses: Array[String] = []
var _pose_data: Dictionary = {}  # name -> parsed pose dict
var _pose_usage: Dictionary = {}  # name -> [{ "level": String, "count": int }]
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


func open(replacement: bool = false) -> void:
	_active = true
	_replacement_mode = replacement
	visible = true
	_load_poses()
	_scan_usage()
	_apply_filter()
	_selected_idx = 0
	_scroll_offset = 0


func close() -> void:
	_active = false
	_replacement_mode = false
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


func _scan_usage() -> void:
	## Scan all level configs for splay pose references.
	_pose_usage.clear()
	for pname in _poses:
		_pose_usage[pname] = []

	# Scan bundled levels
	_scan_levels_in_dir("res://levels/")
	# Scan user levels
	_scan_levels_in_dir("user://levels/")


func _scan_levels_in_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if not dir:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var level_name: String = file_name.replace(".json", "")
			var file := FileAccess.open(dir_path + file_name, FileAccess.READ)
			if file:
				var json := JSON.new()
				if json.parse(file.get_as_text()) == OK:
					var data: Dictionary = json.data
					for splay in data.get("splays", []):
						var pose_name: String = splay.get("pose", "")
						if pose_name != "":
							if not _pose_usage.has(pose_name):
								_pose_usage[pose_name] = []
							# Check if already counted for this level
							var found: bool = false
							for entry in _pose_usage[pose_name]:
								if entry["level"] == level_name:
									entry["count"] += 1
									found = true
									break
							if not found:
								_pose_usage[pose_name].append({"level": level_name, "count": 1})
				file.close()
		file_name = dir.get_next()


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
			KEY_E:
				if _selected_idx >= 0 and _selected_idx < _filtered_poses.size():
					pose_edit_requested.emit(_filtered_poses[_selected_idx])
					close()
				get_viewport().set_input_as_handled()
			KEY_N:
				_create_new_pose()
				get_viewport().set_input_as_handled()
			KEY_DELETE, KEY_BACKSPACE:
				_delete_selected_pose()
				get_viewport().set_input_as_handled()
			KEY_BACKSPACE:
				if _filter_text.length() > 0:
					_filter_text = _filter_text.substr(0, _filter_text.length() - 1)
					_apply_filter()
				get_viewport().set_input_as_handled()
			_:
				var ch: String = char(event.unicode) if event.unicode > 0 else ""
				if ch.length() == 1 and (ch.is_valid_identifier() or ch == "-"):
					_filter_text += ch
					_apply_filter()
					get_viewport().set_input_as_handled()

	if _overlay:
		_overlay.queue_redraw()


func _create_new_pose() -> void:
	var new_name: String = "custom-%d" % (randi() % 10000)
	var pose: Dictionary = {
		"name": new_name,
		"creature": "quadruped",
		"breakaway_sound": "",
		"connections": [],
	}
	var mgr_script: GDScript = load("res://scripts/systems/splay_manager.gd")
	var temp := Node.new()
	temp.set_script(mgr_script)
	add_child(temp)
	temp.save_pose(pose)
	temp.queue_free()
	pose_edit_requested.emit(new_name)
	close()


func _delete_selected_pose() -> void:
	if _selected_idx < 0 or _selected_idx >= _filtered_poses.size():
		return
	var pname: String = _filtered_poses[_selected_idx]
	var is_source: bool = Version.is_source_mode()

	# Check if it's a bundled pose
	var is_bundled: bool = FileAccess.file_exists("res://data/splay_poses/" + pname + ".json")
	if is_bundled and not is_source:
		return  # Can't delete bundled poses outside source mode

	# Check usage
	var usage: Array = _pose_usage.get(pname, [])
	if not usage.is_empty():
		# TODO: double-confirm for in-use poses
		print("WARNING: pose '%s' is in use in %d levels" % [pname, usage.size()])

	# Delete
	if is_bundled and is_source:
		# Delete from res://
		DirAccess.remove_absolute(ProjectSettings.globalize_path("res://data/splay_poses/" + pname + ".json"))
	# Always try to delete user override
	var user_path: String = "user://data/splay_poses/" + pname + ".json"
	if FileAccess.file_exists(user_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(user_path))

	_load_poses()
	_scan_usage()
	_apply_filter()


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
	var font: Font = ThemeDB.fallback_font

	var panel_x: float = vp.x * 0.15
	var panel_w: float = vp.x * 0.7
	var panel_y: float = 40.0
	var panel_h: float = vp.y - 80.0
	_overlay.draw_rect(Rect2(panel_x, panel_y, panel_w, panel_h), Color(0.1, 0.1, 0.12, 0.95))
	_overlay.draw_rect(Rect2(panel_x, panel_y, panel_w, panel_h), Color(0.5, 0.4, 0.3, 0.6), false, 2.0)

	# Title
	var title: String = "SPLAY POSE LIBRARY"
	if _replacement_mode:
		title += " — Choose Replacement"
	_overlay.draw_string(font, Vector2(panel_x + 20, panel_y + 28), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.8, 0.3))

	# Source mode indicator
	if Version.is_source_mode():
		_overlay.draw_string(font, Vector2(panel_x + panel_w - 50, panel_y + 28), "[DEV]", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.3, 0.8, 1.0))

	# Filter
	var filter_text: String = "Filter: " + _filter_text + "_"
	_overlay.draw_string(font, Vector2(panel_x + 20, panel_y + 50), filter_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.7, 0.7))

	# Pose list
	var list_x: float = panel_x + 20
	var list_y: float = panel_y + 70
	var row_h: float = 32.0
	var visible_count: int = int((panel_h - 110) / row_h)

	for i in range(visible_count):
		var pi: int = _scroll_offset + i
		if pi >= _filtered_poses.size():
			break
		var pname: String = _filtered_poses[pi]
		var y: float = list_y + i * row_h
		var is_selected: bool = (pi == _selected_idx)

		if is_selected:
			_overlay.draw_rect(Rect2(list_x - 4, y - 14, panel_w * 0.45, row_h - 2), Color(0.3, 0.25, 0.15, 0.8))

		var pose: Dictionary = _pose_data.get(pname, {})
		var conn_count: int = pose.get("connections", []).size()
		var creature: String = pose.get("creature", "?")
		var usage: Array = _pose_usage.get(pname, [])

		# Usage text
		var usage_str: String = ""
		if usage.is_empty():
			usage_str = "Unused"
		else:
			var parts: Array[String] = []
			for u in usage:
				parts.append("%s(%d)" % [u["level"], u["count"]])
			usage_str = ", ".join(parts)

		var col: Color
		if is_selected:
			col = Color(1.0, 0.9, 0.5)
		elif usage.is_empty():
			col = Color(0.5, 0.5, 0.5)  # Dimmed if unused
		else:
			col = Color(0.7, 0.7, 0.7)

		var label: String = "%s  (%s, %d pts)" % [pname, creature, conn_count]
		_overlay.draw_string(font, Vector2(list_x, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
		# Usage on second line
		var usage_col: Color = Color(0.5, 0.7, 0.5) if not usage.is_empty() else Color(0.4, 0.4, 0.4)
		_overlay.draw_string(font, Vector2(list_x + 10, y + 14), usage_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, usage_col)

	# Preview
	if _selected_idx >= 0 and _selected_idx < _filtered_poses.size():
		var pname: String = _filtered_poses[_selected_idx]
		var pose: Dictionary = _pose_data.get(pname, {})
		_draw_pose_preview(pose, panel_x + panel_w * 0.5, panel_y + 100, panel_w * 0.4, panel_h - 160)

	# Help
	var help: String = "Up/Down=select  Enter=place  E=edit  N=new  Del=delete  Esc=close  Type to filter"
	_overlay.draw_string(font, Vector2(panel_x + 20, panel_y + panel_h - 10), help, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.5, 0.5))


func _draw_pose_preview(pose: Dictionary, x: float, y: float, w: float, h: float) -> void:
	if pose.is_empty():
		return
	_overlay.draw_rect(Rect2(x, y, w, h), Color(0.15, 0.15, 0.18, 0.8))
	_overlay.draw_rect(Rect2(x, y, w, h), Color(0.4, 0.35, 0.3, 0.5), false, 1.0)

	var center := Vector2(x + w / 2.0, y + h / 2.0)
	var scale: float = minf(w, h) / 250.0

	_overlay.draw_circle(center, 6.0, Color(0.5, 0.4, 0.3, 0.6))

	var connections: Array = pose.get("connections", [])
	for conn in connections:
		var rel: Array = conn.get("relative_pos", [0, 0])
		var cast: Array = conn.get("cast_dir", [0, -1])
		var point_name: String = conn.get("point", "?")
		var link_type: String = conn.get("link_type", "rope")
		var conn_pos: Vector2 = center + Vector2(rel[0], rel[1]) * scale
		var cast_dir: Vector2 = Vector2(cast[0], cast[1]).normalized()

		_overlay.draw_line(center, conn_pos, Color(0.4, 0.7, 1.0, 0.3), 1.0)

		var pt_col: Color = Color(0.5, 0.48, 0.45, 0.8) if link_type == "chain" else Color(0.4, 0.8, 1.0, 0.8)
		_overlay.draw_circle(conn_pos, 5.0, pt_col)

		var arrow_end: Vector2 = conn_pos + cast_dir * 25.0 * scale
		_overlay.draw_line(conn_pos, arrow_end, Color(1.0, 0.4, 0.3, 0.5), 1.5)

		_overlay.draw_string(ThemeDB.fallback_font, conn_pos + Vector2(8, -4), point_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.6, 0.8, 1.0))

	_overlay.draw_string(ThemeDB.fallback_font, Vector2(x + 8, y + 18), pose.get("name", "?"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.8, 0.3))
