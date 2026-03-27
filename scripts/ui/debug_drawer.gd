extends CanvasLayer

## Multi-section debug panel — slide-out from left edge.
## Sections: Debug (magnifying glass), Test Runner (play/bug), Config (gear).
## Ctrl+D toggles open/close. Click icon bar to switch sections.

const SLIDE_SPEED := 1200.0
const ROW_HEIGHT := 18.0
const INDENT := 20.0
var _tree_y_start: float = 160.0  # Dynamically set each frame when drawing the debug section
const CHECKBOX_SIZE := 12.0
const GROUP_ARROW_SIZE := 8.0
var SCALE_PRESETS: Array[float] = [0.25, 0.5, 1.0, 2.0, 4.0]

# Section management
enum Section { DEBUG, TEST_RUNNER, CONFIG }
var _current_section: Section = Section.DEBUG
const ICON_BAR_WIDTH := 36.0
const ICON_SIZE := 20.0
const ICON_PAD := 8.0

# Config section state
var _config_scroll_offset: int = 0
var _config_dragging_key: String = ""  # Which config slider is being dragged
var _config_keys: Array[String] = []   # Sorted list of configurable keys
var _config_slider_provider: Variant = null  # Single DictProvider for all slider edits
var _config_slider_data: Dictionary = {}     # The data dict inside the provider
var _config_filter_text: String = ""         # Search filter for config keys
var _config_filter_focused: bool = false     # Whether the config filter field has focus

# Test runner section state — sub-section framework
var _test_scroll_offset: int = 0
var _test_hover_item: String = ""  # Hovered suite or test name

# Sub-section framework for test runner (collapsible, resizable panels)
const SUB_HEADER_H := 20.0      # Height of each sub-section header bar
const SUB_RESIZE_ZONE := 5.0    # Pixels around the bottom edge for resize grab

# Per-sub-section min heights (total including header)
const SUB_MIN := {
	"suites":   30.0,
	"tests":    36.0,
	"controls": 36.0,
	"status":   36.0,
	"editor":   SUB_HEADER_H + 10 * 18.0,  # ~10 lines
}
const SUB_SNAP_DISTANCE := 12.0  # Pixels within which height snaps to the snap point

# Sub-section definitions: id, title, collapsed, height (total including header)
var _subsections: Array[Dictionary] = []
var _subsections_initialized: bool = false
var _sub_resize_idx: int = -1      # Which sub-section is being resized (-1 = none)
var _sub_resize_start_y: float = 0.0
var _sub_resize_start_h: float = 0.0
var _sub_resize_next_h: float = 0.0  # Height of the Editor section (absorbs changes)
var _grip_last_click_idx: int = -1   # Last grip index clicked (for double-click detection)
var _grip_last_click_time: float = 0.0  # Time of last grip click

# Cached lists for the suites/tests sub-sections (rebuilt on section switch)
var _cached_suite_names: Array[String] = []
var _cached_test_names: Array[String] = []
var _cached_lists_dirty: bool = true

# Suite/test selection state
var _selected_suite_name: String = ""         # Currently selected suite
var _selected_suite_tests: Array[String] = [] # Tests in the selected suite
var _suite_results: Dictionary = {}           # suite_name → {"passed": int, "total": int}
var _test_results_cache: Dictionary = {}      # test_name → "pass" | "fail" | ""

# Docked editor scroll offsets (separate from the suite/test list scrolls)
var _editor_scroll_offset: int = 0
var _status_scroll_offset: int = 0

# Editor insertion indicator
var _editor_hover_y: float = -1.0     # Mouse Y within the editor body (-1 = not hovering)
var _editor_insert_idx: int = -1       # Line index where insertion would happen (-1 = none)
var _editor_body_y: float = 0.0       # Top of editor body (set each frame)
var _editor_pending_deletes: Dictionary = {}  # script_idx → true for lines pending deletion
var _editor_row_y_map: Array[float] = []      # Cumulative Y offsets for each row (variable heights)
var _editor_hover_row: int = -1               # Which script row the mouse is hovering over

var _active := false
var _panel_x: float = 0.0      # Current X offset (0 = fully visible)
var _panel_width: float = 396.0  # Wider to fit icon bar + content
var _content_width: float = 360.0  # Content area (panel - icon bar)
var _panel: Control = null
var _scroll_offset: int = 0

# Filter text input
var _filter_text: String = ""
var _filter_focused: bool = false
var _id_filter_focused: bool = false
var _cursor_blink: float = 0.0

# Interaction state
var _hover_row: int = -1
var _visible_rows: Array[Dictionary] = []  # [{type, path, group, ...}]

# Scale slider state
var _scale_dragging: bool = false
var _scale_area_y: float = 110.0  # Updated by _draw_panel each frame
const SCALE_SLIDER_H := 28.0     # Height of scale control area
const SCALE_MIN := 0.1
const SCALE_MAX := 8.0


var _world_overlay: Node2D = null  # World-space overlay for entity selection indicators

func _ready() -> void:
	layer = 109  # Below console (110), above game
	_panel_x = -_panel_width
	_panel = Control.new()
	_panel.name = "DebugDrawerPanel"
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.draw.connect(_draw_panel)
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_panel)
	# Deferred: add world-space overlay to the scene for selection indicators
	call_deferred("_init_world_overlay")


func _init_world_overlay() -> void:
	var scene := get_tree().current_scene
	if not scene:
		return
	_world_overlay = Node2D.new()
	_world_overlay.name = "DebugSelectionOverlay"
	_world_overlay.z_index = 40
	scene.add_child(_world_overlay)
	_world_overlay.draw.connect(_draw_selection_overlay)


func toggle() -> void:
	_active = not _active
	if _active:
		# Opening drawer enables global debug
		DebugOverlay.global_enabled = true
		PlayerHUD._debug_mode = true
		_rebuild_visible_rows()
		_cached_lists_dirty = true
	# Test editor stays docked — no floating mode anymore


func is_open() -> bool:
	return _active


func _init_subsections() -> void:
	## Initialize the test runner sub-sections with preferred (content-based) heights.
	## Layout is loaded from user://debug_panel_layout.json if available.
	_subsections = []
	for sid in ["suites", "tests", "controls", "status", "editor"]:
		_subsections.append({
			"id": sid,
			"title": sid.capitalize(),
			"collapsed": false,
			"height": _get_preferred_height(sid),
		})
	_load_subsection_layout()
	# Auto-snap all sections to their preferred (content-based) heights
	_auto_snap_all()
	_subsections_initialized = true


func _load_subsection_layout() -> void:
	## Load sub-section collapsed/height state from disk.
	var path: String = "user://debug_panel_layout.json"
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return
	var data: Dictionary = json.data
	for sub in _subsections:
		var sid: String = sub["id"]
		if data.has(sid):
			var sd: Dictionary = data[sid]
			sub["collapsed"] = sd.get("collapsed", sub["collapsed"])
			sub["height"] = sd.get("height", sub["height"])


func _save_subsection_layout() -> void:
	## Persist sub-section layout to disk.
	var data: Dictionary = {}
	for sub in _subsections:
		data[sub["id"]] = {"collapsed": sub["collapsed"], "height": sub["height"]}
	var file := FileAccess.open("user://debug_panel_layout.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "  "))


func _get_test_editor() -> Node:
	## Get the test editor node, creating it if needed.
	## Sets _docked=true so the editor suppresses its floating window.
	var rcon: Node = get_node_or_null("/root/Rcon")
	if not rcon:
		return null
	if rcon._test_editor and is_instance_valid(rcon._test_editor):
		# Guard: script properties don't exist until _ready runs
		if not "_docked" in rcon._test_editor:
			return null  # Not ready yet — caller should handle null gracefully
		rcon._test_editor._docked = true
		if not rcon._test_editor._active:
			rcon._test_editor._active = true
			rcon._test_editor.visible = true
			if rcon._test_editor._overlay:
				rcon._test_editor._overlay.visible = true
		return rcon._test_editor
	# Look for existing editor in the scene
	for node in get_tree().current_scene.get_children():
		if node.has_method("toggle") and node.has_method("_load_test") and node.has_method("_run_test"):
			rcon._test_editor = node
			node._docked = true
			if not node._active:
				node._active = true
				node.visible = true
				if node._overlay:
					node._overlay.visible = true
			return node
	# Create one — _ready() will initialize _panel and _overlay.
	# We set _docked now but defer activation until _ready has run.
	var script: GDScript = load("res://scripts/ui/test_editor.gd")
	var editor := CanvasLayer.new()
	editor.set_script(script)
	get_tree().current_scene.add_child(editor)
	# _ready() sets visible=false. We activate on next frame after _ready.
	editor._docked = true
	rcon._test_editor = editor
	editor.call_deferred("_activate_docked")
	return editor


func _auto_snap_all() -> void:
	## Snap all non-editor sections to their preferred content height.
	## Editor absorbs the total difference.
	if _subsections.is_empty():
		return
	var editor_idx: int = _subsections.size() - 1
	var editor_sub: Dictionary = _subsections[editor_idx]
	for i in range(editor_idx):
		var sub: Dictionary = _subsections[i]
		if sub["collapsed"]:
			continue
		var preferred: float = _get_preferred_height(sub["id"])
		var delta: float = preferred - sub["height"]
		sub["height"] = preferred
		editor_sub["height"] -= delta
	# Ensure editor doesn't go below min
	var editor_min: float = SUB_MIN.get("editor", 60.0)
	if editor_sub["height"] < editor_min:
		editor_sub["height"] = editor_min


func _get_preferred_height(sid: String) -> float:
	## Calculate the preferred (snap-point) height based on current content.
	var row_h: float
	match sid:
		"suites":
			row_h = 18.0
			return SUB_HEADER_H + maxf(1, _cached_suite_names.size()) * row_h + 4.0
		"tests":
			row_h = 16.0
			var display_tests: Array[String] = _get_display_test_list()
			var visible: int = mini(display_tests.size(), 10)  # Cap at 10 visible
			return SUB_HEADER_H + maxf(2, visible) * row_h + 4.0
		"controls":
			return SUB_HEADER_H + 28.0  # Button bar height
		"status":
			# 1 line for run status, 1 for summary, some for details
			var te: Node = _get_test_editor()
			var lines: int = 1
			if te and "_run_summary" in te and not te._run_summary.is_empty():
				lines = 3
			return SUB_HEADER_H + lines * 16.0 + 4.0
		"editor":
			var te: Node = _get_test_editor()
			var script_lines: int = 5
			if te and "_script" in te:
				script_lines = te._script.size() + 1  # +1 for ghost add row
			var edit_h: float = 32.0 if te and "_selected_row" in te and te._selected_row >= 0 else 0.0
			return SUB_HEADER_H + mini(script_lines, 20) * 18.0 + edit_h + 4.0
	return SUB_HEADER_H + 40.0


func _snap_height(sid: String, h: float) -> float:
	## Snap height to the preferred size if within SUB_SNAP_DISTANCE.
	var preferred: float = _get_preferred_height(sid)
	if absf(h - preferred) < SUB_SNAP_DISTANCE:
		return preferred
	return h


func _select_suite(suite_name: String) -> void:
	## Select a suite — loads its test list for display in the Tests sub-section.
	if _selected_suite_name == suite_name:
		_selected_suite_name = ""  # Toggle off
		_selected_suite_tests.clear()
		return
	_selected_suite_name = suite_name
	_selected_suite_tests.clear()
	var path: String = "res://data/tests/suites/%s.json" % suite_name
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return
	var data: Dictionary = json.data
	if data.has("tests"):
		for t in data["tests"]:
			_selected_suite_tests.append(str(t))
	_test_scroll_offset = 0


func _get_display_test_list() -> Array[String]:
	## Returns the test list to display — filtered by selected suite, or all tests.
	if not _selected_suite_name.is_empty() and not _selected_suite_tests.is_empty():
		return _selected_suite_tests
	return _cached_test_names


func _update_suite_result(suite_name: String, passed: int, total: int) -> void:
	## Record the result of a suite run.
	_suite_results[suite_name] = {"passed": passed, "total": total}


func _update_test_result(test_name: String, result: String) -> void:
	## Record the result of a test run ("pass" or "fail").
	## Also recomputes suite results for any suite containing this test.
	_test_results_cache[test_name] = result
	_recompute_suite_results()


func _recompute_suite_results() -> void:
	## Recompute all suite pass/fail from current test results cache.
	for sname in _cached_suite_names:
		var suite_path: String = "res://data/tests/suites/%s.json" % sname
		var sfile := FileAccess.open(suite_path, FileAccess.READ)
		if not sfile:
			continue
		var sjson := JSON.new()
		if sjson.parse(sfile.get_as_text()) != OK or not sjson.data is Dictionary:
			continue
		var suite_tests: Array = sjson.data.get("tests", [])
		if suite_tests.is_empty():
			continue
		var passed: int = 0
		var total: int = suite_tests.size()
		var all_known: bool = true
		for st in suite_tests:
			var st_name: String = str(st)
			if _test_results_cache.has(st_name):
				if _test_results_cache[st_name] == "pass":
					passed += 1
			else:
				all_known = false
		if all_known:
			_suite_results[sname] = {"passed": passed, "total": total}
		else:
			# Partial results — show what we know
			_suite_results[sname] = {"passed": passed, "total": total}


func _rebuild_cached_lists() -> void:
	## Rebuild cached suite and test name lists from disk.
	_cached_suite_names.clear()
	_cached_test_names.clear()
	var suite_dir := DirAccess.open("res://data/tests/suites/")
	if suite_dir:
		suite_dir.list_dir_begin()
		var fname: String = suite_dir.get_next()
		while fname != "":
			if fname.ends_with(".json"):
				_cached_suite_names.append(fname.get_basename())
			fname = suite_dir.get_next()
		suite_dir.list_dir_end()
	_cached_suite_names.sort()
	var test_dir := DirAccess.open("res://data/tests/")
	if test_dir:
		test_dir.list_dir_begin()
		var fname: String = test_dir.get_next()
		while fname != "":
			if fname.ends_with(".json"):
				_cached_test_names.append(fname.get_basename())
			fname = test_dir.get_next()
		test_dir.list_dir_end()
	_cached_test_names.sort()
	_cached_lists_dirty = false
	# Scan all tests for cached results to populate pass/fail indicators
	_scan_all_test_results()


func _scan_all_test_results() -> void:
	## Scan all tests for cached results and populate pass/fail indicators.
	## Also aggregates suite results from their constituent tests.
	var TestRunner: GDScript = load("res://scripts/systems/test_runner.gd")
	# Scan individual tests
	for tname in _cached_test_names:
		if _test_results_cache.has(tname):
			continue  # Already have a result from this session
		var results: Dictionary = TestRunner.find_latest_results(tname)
		if results.is_empty():
			continue
		# Load the test script to compute its hash
		var test_path: String = "res://data/tests/%s.json" % tname
		var file := FileAccess.open(test_path, FileAccess.READ)
		if not file:
			continue
		var json := JSON.new()
		if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
			continue
		var test_data: Dictionary = json.data
		var script_lines: Array = test_data.get("script", [])
		var current_hash: String = TestRunner._compute_script_hash(script_lines)
		var saved_hash: String = results.get("script_hash", "")
		if saved_hash.is_empty() or saved_hash != current_hash:
			continue  # Script changed — results invalid
		var passed: int = results.get("passed", 0)
		var total: int = results.get("total", 0)
		_test_results_cache[tname] = "pass" if passed == total else "fail"

	# Aggregate suite results from their tests
	for sname in _cached_suite_names:
		if _suite_results.has(sname):
			continue  # Already have a result from this session
		var suite_path: String = "res://data/tests/suites/%s.json" % sname
		var sfile := FileAccess.open(suite_path, FileAccess.READ)
		if not sfile:
			continue
		var sjson := JSON.new()
		if sjson.parse(sfile.get_as_text()) != OK or not sjson.data is Dictionary:
			continue
		var suite_tests: Array = sjson.data.get("tests", [])
		if suite_tests.is_empty():
			continue
		var suite_passed: int = 0
		var suite_total: int = suite_tests.size()
		var all_known: bool = true
		for st in suite_tests:
			var st_name: String = str(st)
			if _test_results_cache.has(st_name):
				if _test_results_cache[st_name] == "pass":
					suite_passed += 1
			else:
				all_known = false
		if all_known:
			_suite_results[sname] = {"passed": suite_passed, "total": suite_total}


func _process(delta: float) -> void:
	# Adjust game camera to fit visible area when drawer is open
	_update_game_viewport()

	var target_x: float = 0.0 if _active else -_panel_width
	if absf(_panel_x - target_x) > 1.0:
		_panel_x = lerpf(_panel_x, target_x, delta * 10.0)
		_panel.queue_redraw()
	elif _panel_x != target_x:
		_panel_x = target_x

	if _active:
		_cursor_blink += delta
		_panel.queue_redraw()
	# Redraw world overlay for selection indicators (always, even when drawer closed)
	if _world_overlay and is_instance_valid(_world_overlay):
		_world_overlay.queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		# Ctrl+D toggles drawer
		if event.keycode == KEY_D and event.ctrl_pressed and not event.shift_pressed:
			toggle()
			get_viewport().set_input_as_handled()
			return

		# Ctrl+S saves while open
		if _active and event.keycode == KEY_S and event.ctrl_pressed:
			DebugOverlay.save_profile()
			get_viewport().set_input_as_handled()
			return

		if not _active:
			return

		# Forward keyboard to docked test editor when test runner section is active
		if _current_section == Section.TEST_RUNNER:
			var te: Node = _get_test_editor()
			if te and te._edit_focused:
				te._input_edit_field(event, event.ctrl_pressed or event.meta_pressed, event.shift_pressed)
				get_viewport().set_input_as_handled()
				return
			# Ctrl+S in test runner saves test (not debug profile)
			if event.keycode == KEY_S and event.ctrl_pressed and te:
				te._save_test()
				get_viewport().set_input_as_handled()
				return
			# T opens picker
			if event.keycode == KEY_T and not (event.ctrl_pressed or event.meta_pressed) and te:
				if not te._edit_focused and not te._picker_open:
					te._open_picker()
					te._active = true
					te.visible = true
					get_viewport().set_input_as_handled()
					return

		# Text input for filter fields
		if _filter_focused:
			_handle_text_input(event, "_filter_text")
			get_viewport().set_input_as_handled()
			return
		if _id_filter_focused:
			_handle_id_input(event)
			get_viewport().set_input_as_handled()
			return
		if _config_filter_focused:
			_handle_text_input(event, "_config_filter_text")
			_config_keys.clear()  # Force rebuild when filter changes
			get_viewport().set_input_as_handled()
			return

		# Escape closes drawer or unfocuses
		if event.keycode == KEY_ESCAPE:
			if _filter_focused or _id_filter_focused or _config_filter_focused:
				_filter_focused = false
				_id_filter_focused = false
				_config_filter_focused = false
			else:
				toggle()
			get_viewport().set_input_as_handled()
			return

		# Scroll
		if event.keycode == KEY_PAGEUP:
			_scroll_offset = maxi(0, _scroll_offset - 10)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_PAGEDOWN:
			_scroll_offset += 10
			get_viewport().set_input_as_handled()

	# Mouse release — stop scale/config/subsection drag
	if _active and event is InputEventMouseButton and not event.pressed:
		if _scale_dragging:
			_scale_dragging = false
			get_viewport().set_input_as_handled()
			return
		if not _config_dragging_key.is_empty():
			_config_dragging_key = ""
			get_viewport().set_input_as_handled()
			return
		if _sub_resize_idx >= 0:
			_handle_sub_resize_release()
			_sub_resize_idx = -1
			_save_subsection_layout()
			get_viewport().set_input_as_handled()
			return

	# Mouse clicks (left button only — not scroll wheel)
	if _active and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mx: float = event.position.x
		var my: float = event.position.y
		if mx < _panel_x or mx > _panel_x + _panel_width:
			# Click outside — unfocus any text field
			_filter_focused = false
			_id_filter_focused = false
			return
		var lx: float = mx - _panel_x
		# Check if click is in the icon bar
		if lx < ICON_BAR_WIDTH:
			_handle_icon_click(my)
		elif _current_section == Section.CONFIG:
			_handle_config_click(lx - ICON_BAR_WIDTH - 4, my)
		elif _current_section == Section.TEST_RUNNER:
			_handle_test_click(lx - ICON_BAR_WIDTH - 4, my)
		else:
			_handle_click(lx - ICON_BAR_WIDTH - 4, my)
		get_viewport().set_input_as_handled()

	# Mouse scroll — route to the correct sub-section when in test runner
	if _active and event is InputEventMouseButton:
		if event.position.x >= _panel_x and event.position.x <= _panel_x + _panel_width:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
				if _current_section == Section.TEST_RUNNER:
					_handle_test_scroll(event.position.y, -3)
				elif _current_section == Section.CONFIG:
					_config_scroll_offset = maxi(0, _config_scroll_offset - 3)
				else:
					_scroll_offset = maxi(0, _scroll_offset - 3)
				get_viewport().set_input_as_handled()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
				if _current_section == Section.TEST_RUNNER:
					_handle_test_scroll(event.position.y, 3)
				elif _current_section == Section.CONFIG:
					_config_scroll_offset += 3
				else:
					_scroll_offset += 3
				get_viewport().set_input_as_handled()

	# Mouse motion for hover, scale/config/subsection drag
	if _active and event is InputEventMouseMotion:
		if _scale_dragging:
			_handle_scale_drag(event.position.x)
			get_viewport().set_input_as_handled()
		elif not _config_dragging_key.is_empty():
			_handle_config_drag(event.position.x)
			get_viewport().set_input_as_handled()
		elif _sub_resize_idx >= 0:
			_handle_sub_resize_drag(event.position.y)
			get_viewport().set_input_as_handled()
		elif event.position.x >= _panel_x and event.position.x <= _panel_x + _panel_width:
			if _current_section == Section.TEST_RUNNER:
				_handle_test_hover(event.position.y)
			_update_hover(event.position.y)


func _handle_text_input(event: InputEventKey, _field: String) -> void:
	if event.keycode == KEY_BACKSPACE:
		if _filter_text.length() > 0:
			_filter_text = _filter_text.substr(0, _filter_text.length() - 1)
			_rebuild_visible_rows()
	elif event.keycode == KEY_ENTER or event.keycode == KEY_TAB:
		_filter_focused = false
	elif event.keycode == KEY_ESCAPE:
		_filter_focused = false
	elif event.unicode > 0 and not event.ctrl_pressed:
		_filter_text += char(event.unicode)
		_rebuild_visible_rows()


func _handle_id_input(event: InputEventKey) -> void:
	if event.keycode == KEY_BACKSPACE:
		var p: String = DebugOverlay.entity_id_pattern
		if p.length() > 0:
			DebugOverlay.entity_id_pattern = p.substr(0, p.length() - 1)
	elif event.keycode == KEY_ENTER or event.keycode == KEY_TAB:
		_id_filter_focused = false
	elif event.keycode == KEY_ESCAPE:
		_id_filter_focused = false
	elif event.unicode > 0 and not event.ctrl_pressed:
		DebugOverlay.entity_id_pattern += char(event.unicode)


# -- Row Building --------------------------------------------------------------

func _rebuild_visible_rows() -> void:
	_visible_rows.clear()
	var groups: Array[String] = DebugOverlay.get_aspect_groups()
	var filter_lower: String = _filter_text.to_lower()

	for group in groups:
		var aspects: Array[String] = DebugOverlay.get_aspects_in_group(group)
		var matching_aspects: Array[String] = []

		for path in aspects:
			if filter_lower == "" or filter_lower in path.to_lower():
				matching_aspects.append(path)

		if matching_aspects.is_empty():
			continue

		# Group header row
		var collapsed: bool = DebugOverlay.collapsed_groups.get(group, false)
		_visible_rows.append({
			"type": "group",
			"group": group,
			"collapsed": collapsed,
			"aspects": matching_aspects,
		})

		if collapsed:
			continue

		# Aspect rows
		for path in matching_aspects:
			var info: DebugOverlay.AspectInfo = DebugOverlay.get_aspect(path)
			_visible_rows.append({
				"type": "aspect",
				"path": path,
				"info": info,
			})


# -- Click Handling ------------------------------------------------------------

func _handle_click(lx: float, my: float) -> void:
	# Check filter text field click
	if my >= 8 and my <= 28:
		_filter_focused = true
		_id_filter_focused = false
		return

	# Check entity type filter checkboxes (y ~ 38-55)
	if my >= 36 and my <= 56:
		_handle_type_filter_click(lx)
		_filter_focused = false
		_id_filter_focused = false
		return

	# Check entity ID field click (y ~ 58-78)
	if my >= 58 and my <= 78:
		_id_filter_focused = true
		_filter_focused = false
		return

	# Check global toggle (y ~ 88-108)
	if my >= 88 and my <= 108:
		DebugOverlay.global_enabled = not DebugOverlay.global_enabled
		# Sync legacy
		PlayerHUD._debug_mode = DebugOverlay.global_enabled
		_filter_focused = false
		_id_filter_focused = false
		return

	# Check scale control area
	if my >= _scale_area_y and my < _scale_area_y + SCALE_SLIDER_H:
		_filter_focused = false
		_id_filter_focused = false
		_handle_scale_click(lx, my)
		return

	_filter_focused = false
	_id_filter_focused = false

	# Aspect tree area — use the dynamically calculated tree start position
	var tree_y_start: float = _tree_y_start
	var row_idx: int = int((my - tree_y_start) / ROW_HEIGHT) + _scroll_offset
	if row_idx < 0 or row_idx >= _visible_rows.size():
		return

	var row: Dictionary = _visible_rows[row_idx]

	if row["type"] == "group":
		# Check if clicking V or T column headers (relative to content area)
		var v_col_x: float = _content_width - 60
		var t_col_x: float = _content_width - 30
		if lx >= v_col_x - 8 and lx < t_col_x - 8:
			# Toggle group visual
			var aspects: Array[String] = row["aspects"]
			var any_on: bool = false
			for path in aspects:
				var state: Array = DebugOverlay.get_observer_state(path, "human")
				if state[0]:
					any_on = true
					break
			DebugOverlay.set_group_visual(row["group"], not any_on)
		elif lx >= t_col_x - 8:
			# Cycle group textual
			var aspects: Array[String] = row["aspects"]
			# Find current max textual mode
			var max_txt: int = DebugOverlay.TextMode.NONE
			for path in aspects:
				var state: Array = DebugOverlay.get_observer_state(path, "human")
				if state[1] > max_txt:
					max_txt = state[1]
			var next_txt: int = _cycle_text_mode(max_txt)
			DebugOverlay.set_group_textual(row["group"], next_txt)
		else:
			# Toggle collapse
			var collapsed: bool = not row["collapsed"]
			DebugOverlay.collapsed_groups[row["group"]] = collapsed
			_rebuild_visible_rows()

	elif row["type"] == "aspect":
		var v_col_x: float = _content_width - 60
		var t_col_x: float = _content_width - 30
		var path: String = row["path"]
		var state: Array = DebugOverlay.get_observer_state(path, "human")

		if lx >= v_col_x - 8 and lx < t_col_x - 8:
			# Toggle visual
			DebugOverlay.set_observer(path, "human", not state[0], state[1])
		elif lx >= t_col_x - 8:
			# Cycle textual
			var next_txt: int = _cycle_text_mode(state[1])
			DebugOverlay.set_observer(path, "human", state[0], next_txt)


func _handle_type_filter_click(lx: float) -> void:
	# Type checkboxes laid out horizontally after "Types:" label
	var types: Array[String] = ["monster", "dummy", "attacker"]
	var start_x: float = 50.0
	var spacing: float = 80.0
	for i in range(types.size()):
		var cx: float = start_x + i * spacing
		if lx >= cx and lx < cx + spacing:
			var t: String = types[i]
			DebugOverlay.entity_type_filter[t] = not DebugOverlay.entity_type_filter.get(t, true)
			return


func _get_selected_monster() -> Node2D:
	## Returns the TAB-selected enemy if it has creature_scale, else null.
	## Used for monster-specific features (scale slider, config stack).
	var sel: Node2D = PlayerHUD.debug_selected_enemy
	if is_instance_valid(sel) and "creature_scale" in sel:
		return sel
	return null


func _get_selected_entity() -> Node2D:
	## Returns the TAB/click-selected enemy, any type. Null if none.
	var sel: Node2D = PlayerHUD.debug_selected_enemy
	if is_instance_valid(sel):
		return sel
	return null


func _handle_scale_click(lx: float, _my: float) -> void:
	var monster: Node2D = _get_selected_monster()
	if not monster:
		return
	var slider_x: float = 70.0
	var slider_w: float = _panel_width - 90.0
	# Check preset buttons (right side)
	var presets_x: float = slider_x + slider_w + 6
	# If clicking on the slider track, start drag or snap
	if lx >= slider_x and lx <= slider_x + slider_w:
		var t: float = clampf((lx - slider_x) / slider_w, 0.0, 1.0)
		# Map [0,1] → [SCALE_MIN, SCALE_MAX] logarithmic
		var new_scale: float = _slider_t_to_scale(t)
		monster.creature_scale = new_scale
		_scale_dragging = true
		_reinit_monster(monster)


func _handle_scale_drag(mx: float) -> void:
	var monster: Node2D = _get_selected_monster()
	if not monster:
		_scale_dragging = false
		return
	var lx: float = mx - _panel_x
	var slider_x: float = 70.0
	var slider_w: float = _panel_width - 90.0
	var t: float = clampf((lx - slider_x) / slider_w, 0.0, 1.0)
	var new_scale: float = _slider_t_to_scale(t)
	monster.creature_scale = new_scale
	_reinit_monster(monster)


func _slider_t_to_scale(t: float) -> float:
	## Map slider position [0,1] to scale value using log scale.
	## 0.0 → SCALE_MIN, 0.5 → 1.0, 1.0 → SCALE_MAX
	var log_min: float = log(SCALE_MIN)
	var log_max: float = log(SCALE_MAX)
	return exp(lerpf(log_min, log_max, t))


func _scale_to_slider_t(scale: float) -> float:
	## Map scale value to slider position [0,1] using log scale.
	var log_min: float = log(SCALE_MIN)
	var log_max: float = log(SCALE_MAX)
	var log_s: float = log(clampf(scale, SCALE_MIN, SCALE_MAX))
	return (log_s - log_min) / (log_max - log_min)


func _reinit_monster(monster: Node2D) -> void:
	## Re-initialize skeleton, collision, hitboxes at the new scale.
	if monster.has_method("_init_skeleton"):
		monster._init_skeleton()
	if monster.has_method("_init_collision"):
		# Remove old collision shape, re-create
		if "_body_collision" in monster and is_instance_valid(monster._body_collision):
			monster._body_collision.queue_free()
		monster._init_collision()
	# Hitboxes and attach points are positioned per-frame, no re-init needed


func _cycle_text_mode(current: int) -> int:
	match current:
		DebugOverlay.TextMode.NONE: return DebugOverlay.TextMode.LOG
		DebugOverlay.TextMode.LOG: return DebugOverlay.TextMode.CONSOLE
		DebugOverlay.TextMode.CONSOLE: return DebugOverlay.TextMode.BOTH
		DebugOverlay.TextMode.BOTH: return DebugOverlay.TextMode.NONE
	return DebugOverlay.TextMode.NONE


func _update_game_viewport() -> void:
	## When the drawer is open, use the Viewport's canvas transform to shift
	## and scale the game so it fits in the remaining visible area (right of drawer).
	## This moves ALL rendering, not just the camera.
	var vp: Viewport = get_viewport()
	if not vp:
		return

	var vp_width: float = vp.get_visible_rect().size.x
	var visible_panel: float = maxf(0.0, _panel_x + _panel_width)
	var game_width: float = vp_width - visible_panel

	if not _active and visible_panel < 2.0:
		# Drawer closed — reset to identity transform
		vp.canvas_transform = Transform2D.IDENTITY
		return

	if game_width < 100:
		return

	# Scale to fit remaining width, shift right past the drawer
	var scale_factor: float = game_width / vp_width
	var target_transform := Transform2D()
	target_transform = target_transform.scaled(Vector2(scale_factor, scale_factor))
	target_transform.origin = Vector2(visible_panel, 0)

	# Smooth lerp toward target
	var current: Transform2D = vp.canvas_transform
	vp.canvas_transform = current.interpolate_with(target_transform, 0.15)


func _handle_icon_click(my: float) -> void:
	## Click on the icon bar — switch section or collapse.
	var icon_sections: Array = [Section.DEBUG, Section.TEST_RUNNER, Section.CONFIG]
	for i in range(icon_sections.size()):
		var iy: float = 8.0 + i * (ICON_SIZE + ICON_PAD * 2 + 4)
		var ih: float = ICON_SIZE + ICON_PAD * 2
		if my >= iy and my < iy + ih:
			if _current_section == icon_sections[i]:
				# Clicking active icon could collapse, but for now just keep it
				pass
			else:
				_current_section = icon_sections[i]
				_config_keys.clear()  # Force rebuild when switching to config
				_cached_lists_dirty = true  # Force rebuild test/suite lists
			_panel.queue_redraw()
			return


func _handle_test_click(lx: float, my: float) -> void:
	## Click in the test runner section — routes to the correct sub-section.
	if not _subsections_initialized:
		_init_subsections()
	if _cached_lists_dirty:
		_rebuild_cached_lists()

	# Walk sub-sections to find which one was clicked
	var y: float = 0.0
	for i in range(_subsections.size()):
		var sub: Dictionary = _subsections[i]
		var header_y: float = y
		var header_end: float = y + SUB_HEADER_H

		# Check click on header bar
		if my >= header_y and my < header_end:
			var pw: float = _content_width
			if lx < 16:
				# Click on collapse triangle — toggle collapse
				sub["collapsed"] = not sub["collapsed"]
				_save_subsection_layout()
			elif sub["id"] == "editor":
				var te_bar: Node = _get_test_editor()
				if te_bar:
					# Approve-all-deletes button (✕) just left of grip
					if lx > pw - 40 and lx < pw - 28 and not _editor_pending_deletes.is_empty():
						var sorted_keys: Array = _editor_pending_deletes.keys()
						sorted_keys.sort()
						sorted_keys.reverse()
						for key in sorted_keys:
							te_bar._delete_row(key)
						_editor_pending_deletes.clear()
						return
					# Save button (💾) after the test name — approximate click zone
					if lx > 78 and lx < pw - 40 and "_dirty" in te_bar and te_bar._dirty:
						te_bar._save_test()
						return
				# Fall through to grip handling below if not caught
				if not (lx > pw - 28 and i > 0):
					return  # Clicked middle of editor bar, do nothing
			elif lx > pw - 28 and i > 0:
				var target_idx: int = i - 1
				var now: float = Time.get_ticks_msec() / 1000.0
				# Double-click detection — snap to preferred height
				if _grip_last_click_idx == target_idx and (now - _grip_last_click_time) < 0.4:
					var sub_above: Dictionary = _subsections[target_idx]
					var editor_sub: Dictionary = _subsections[_subsections.size() - 1]
					var preferred: float = _get_preferred_height(sub_above["id"])
					var delta: float = preferred - sub_above["height"]
					sub_above["height"] = preferred
					editor_sub["height"] -= delta
					_save_subsection_layout()
					_grip_last_click_idx = -1
					return
				_grip_last_click_idx = target_idx
				_grip_last_click_time = now
				# Start resize drag
				_sub_resize_idx = target_idx
				_sub_resize_start_y = my
				_sub_resize_start_h = _subsections[target_idx]["height"]
				_sub_resize_next_h = _subsections[_subsections.size() - 1]["height"]
			# Clicks on the title or middle of the header do nothing
			return

		if sub["collapsed"]:
			y += SUB_HEADER_H
			continue

		var body_y: float = header_end
		var body_end: float = y + sub["height"]
		# Editor fills remaining space — extend for click detection
		if sub["id"] == "editor":
			body_end = maxf(body_end, 9999.0)

		# Check if click is in the resize zone at the bottom edge of this sub-section
		# Resizes THIS section, Editor absorbs the change
		if my >= body_end - SUB_RESIZE_ZONE and my < body_end + SUB_RESIZE_ZONE and i < _subsections.size() - 1:
			_sub_resize_idx = i
			_sub_resize_start_y = my
			_sub_resize_start_h = sub["height"]
			_sub_resize_next_h = _subsections[_subsections.size() - 1]["height"]  # Editor's height
			return

		# Check if click is in the body
		if my >= body_y and my < body_end:
			var local_y: float = my - body_y
			_handle_subsection_click(sub["id"], lx, local_y, body_end - body_y)
			return

		y += sub["height"]


func _handle_subsection_click(sub_id: String, lx: float, local_y: float, body_h: float) -> void:
	## Handle a click inside a specific sub-section body.
	match sub_id:
		"suites":
			var row_h: float = 18.0
			var idx: int = int(local_y / row_h)
			if idx >= 0 and idx < _cached_suite_names.size():
				var suite_name: String = _cached_suite_names[idx]
				# Check if click is on the play button (right 40px)
				if lx > _content_width - 40:
					var rcon: Node = get_node_or_null("/root/Rcon")
					if rcon:
						rcon._execute("suite %s owait=0" % suite_name)
				else:
					# Select the suite — filter tests list to show only its tests
					_select_suite(suite_name)
		"tests":
			var row_h: float = 16.0
			var display_tests: Array[String] = _get_display_test_list()
			var idx: int = int(local_y / row_h) + _test_scroll_offset
			if idx >= 0 and idx < display_tests.size():
				var tname: String = display_tests[idx]
				if lx > _content_width - 40:
					# Play button — run this test
					var rcon: Node = get_node_or_null("/root/Rcon")
					if rcon:
						rcon._execute("run %s owait=0" % tname)
				else:
					# Select — load into the editor
					var te: Node = _get_test_editor()
					if te:
						te._test_override_vars = {"owait": "0"}
						te._load_test(tname)
		"controls":
			# Button bar click — buttons fill the entire body (title is in the header bar)
			var te: Node = _get_test_editor()
			if te:
				var pw: float = _content_width
				var btns: Array = te._get_buttons()
				if not btns.is_empty():
					var bw: float = (pw - 24.0) / float(btns.size())
					var btn_idx: int = int((lx - 8.0) / bw)
					if btn_idx >= 0 and btn_idx < btns.size():
						var action: String = btns[btn_idx][2]
						match action:
							"play":
								if te._run_running: te._pause_test()
								else: te._run_test()
							"stop":   te._stop_test()
							"restart": te._restart_test()
							"add_dis": te._try_add_disallow()
							"add_fence": te._try_add_fence()
							"add_exit_circle": te._try_add_exit_circle()
							"suite_prev": te._suite_goto(te._suite_current_idx - 1)
							"suite_next": te._suite_goto(te._suite_current_idx + 1)
							"notify_done":
								var rcon: Node = get_node_or_null("/root/Rcon")
								if rcon:
									rcon._cmd_notify_dismiss("OK")
							"save":   te._save_test()
		"editor":
			_handle_editor_subsection_click(lx, local_y, body_h)


func _handle_editor_subsection_click(lx: float, local_y: float, body_h: float) -> void:
	## Handle click inside the editor sub-section. Behavior depends on mode:
	## EDIT: select rows, insert lines, delete with confirm, focus edit field
	## EXECUTE: no interaction (read-only during run)
	## INSPECT: click rows to show their status detail
	var te: Node = _get_test_editor()
	if not te:
		return
	var is_edit_mode: bool = te._mode == 0
	var is_exec_mode: bool = te._mode == 1
	var is_inspect_mode: bool = te._mode == 2

	# EXECUTE mode — no interaction
	if is_exec_mode:
		return

	var pw: float = _content_width
	var font: Font = ThemeDB.fallback_font
	var text_w: float = pw - 56
	# Dynamic edit field height (must match the draw calculation)
	var edit_h: float = 0.0
	if te._selected_row >= 0 and is_edit_mode:
		var edit_wrap: Array[String] = _get_soft_wrap_lines(te._edit_text, text_w, font, 10)
		edit_h = maxf(32.0, 8.0 + edit_wrap.size() * 18.0)
	var list_h: float = body_h - edit_h

	# Click in edit field area — focus it (takes priority over row selection)
	if local_y >= list_h and edit_h > 0 and is_edit_mode:
		te._edit_focused = true
		return

	if local_y < list_h:
		# EDIT mode: insertion indicator (left side, near row boundary)
		if is_edit_mode and _editor_insert_idx >= 0 and not te._run_running and lx < 30:
			te._script.insert(_editor_insert_idx, "")
			te._dirty = true
			# Adjust pending deletes for indices that shifted
			var new_deletes: Dictionary = {}
			for key in _editor_pending_deletes:
				if key >= _editor_insert_idx:
					new_deletes[key + 1] = true
				else:
					new_deletes[key] = true
			_editor_pending_deletes = new_deletes
			te._select_row(_editor_insert_idx)
			te._edit_focused = true
			_editor_insert_idx = -1
			return

		# Find which script row was clicked using variable heights
		var cum_y: float = 0.0
		var clicked_idx: int = -1
		for si in range(_editor_scroll_offset, te._script.size()):
			var rh: float = _get_row_height(te, si, text_w, font)
			if local_y >= cum_y and local_y < cum_y + rh:
				clicked_idx = si
				break
			cum_y += rh

		if clicked_idx >= 0 and clicked_idx < te._script.size():
			if is_edit_mode or is_inspect_mode:
				# EDIT: check button zones (right side), then select
				if lx >= pw - 40 and not te._run_running:
					if _editor_pending_deletes.has(clicked_idx):
						# Pending delete: [↶ undo] [✕ confirm]
						if lx < pw - 22:
							_editor_pending_deletes.erase(clicked_idx)
						else:
							_editor_pending_deletes.erase(clicked_idx)
							te._delete_row(clicked_idx)
							var new_deletes: Dictionary = {}
							for key in _editor_pending_deletes:
								if key > clicked_idx:
									new_deletes[key - 1] = true
								else:
									new_deletes[key] = true
							_editor_pending_deletes = new_deletes
					elif lx < pw - 24:
						# Comment toggle (#) — left button zone
						var line: String = te._script[clicked_idx]
						if line.strip_edges().begins_with("#"):
							# Uncomment: remove leading "# " or "#"
							var stripped: String = line.strip_edges()
							if stripped.begins_with("# "):
								te._script[clicked_idx] = stripped.substr(2)
							else:
								te._script[clicked_idx] = stripped.substr(1)
						else:
							# Comment: prepend "# "
							te._script[clicked_idx] = "# " + line
						te._dirty = true
						if te._selected_row == clicked_idx:
							te._edit_text = te._script[clicked_idx]
							te._edit_cursor = te._edit_text.length()
					else:
						# Delete button (✕) — right button zone
						_editor_pending_deletes[clicked_idx] = true
				else:
					if is_inspect_mode:
						te._selected_row = clicked_idx
						_status_scroll_offset = 0
					else:
						te._select_row(clicked_idx)
	# Edit field click is handled above (before row selection)


func _handle_test_hover(my: float) -> void:
	## Track which test/suite item the mouse is hovering over for highlight.
	## Also track editor insertion indicator position.
	_test_hover_item = ""
	_editor_insert_idx = -1
	_editor_hover_y = -1.0
	_editor_hover_row = -1
	if not _subsections_initialized:
		return
	if _cached_lists_dirty:
		_rebuild_cached_lists()

	# Walk sub-sections to find which one the mouse is in
	var y: float = 0.0
	for sub in _subsections:
		if sub["collapsed"]:
			y += SUB_HEADER_H
			continue
		var body_y: float = y + SUB_HEADER_H
		var body_end: float = y + sub["height"]
		# Editor section fills remaining space — extend body_end to panel height
		if sub["id"] == "editor":
			body_end = maxf(body_end, 9999.0)  # Effectively unbounded
		if my >= body_y and my < body_end:
			var local_y: float = my - body_y
			match sub["id"]:
				"suites":
					var idx: int = int(local_y / 18.0)
					if idx >= 0 and idx < _cached_suite_names.size():
						_test_hover_item = _cached_suite_names[idx]
				"tests":
					var display_tests: Array[String] = _get_display_test_list()
					var idx: int = int(local_y / 16.0) + _test_scroll_offset
					if idx >= 0 and idx < display_tests.size():
						_test_hover_item = display_tests[idx]
				"editor":
					# Track insertion indicator using variable row heights
					var te: Node = _get_test_editor()
					var font: Font = ThemeDB.fallback_font
					var pw: float = _content_width
					if te and not te._run_running:
						var text_w_hover: float = pw - 56
						var cum_y_h: float = 0.0
						for si in range(_editor_scroll_offset, te._script.size()):
							var rh: float = _get_row_height(te, si, text_w_hover, font)
							# Track which row is hovered
							if local_y >= cum_y_h and local_y < cum_y_h + rh:
								_editor_hover_row = si
							# Check if mouse is near the TOP edge of this row (boundary)
							if local_y >= cum_y_h - 4 and local_y < cum_y_h + 4:
								_editor_insert_idx = si
								_editor_hover_y = body_y + cum_y_h
							cum_y_h += rh
						# Check bottom boundary (after last row)
						if local_y >= cum_y_h - 4 and local_y < cum_y_h + 4:
							_editor_insert_idx = te._script.size()
							_editor_hover_y = body_y + cum_y_h
			return
		y += sub["height"]


func _handle_test_scroll(my: float, delta: int) -> void:
	## Route scroll events to the correct sub-section based on mouse Y.
	if not _subsections_initialized:
		return
	var y: float = 0.0
	for sub in _subsections:
		if sub["collapsed"]:
			y += SUB_HEADER_H
			continue
		var body_y: float = y + SUB_HEADER_H
		var body_end: float = y + sub["height"]
		if sub["id"] == "editor":
			body_end = maxf(body_end, 9999.0)
		if my >= y and my < body_end:
			match sub["id"]:
				"tests":
					_test_scroll_offset = maxi(0, _test_scroll_offset + delta)
				"editor":
					_editor_scroll_offset = maxi(0, _editor_scroll_offset + delta)
				"status":
					_status_scroll_offset = maxi(0, _status_scroll_offset + delta)
			return
		y += sub["height"]


func _handle_sub_resize_drag(my: float) -> void:
	## Resize: growing/shrinking the dragged section, Editor absorbs the difference.
	## No forced snapping during drag — user can resize freely past snap points.
	if _sub_resize_idx < 0 or _sub_resize_idx >= _subsections.size():
		return
	var dy: float = my - _sub_resize_start_y
	var sub: Dictionary = _subsections[_sub_resize_idx]
	var editor_sub: Dictionary = _subsections[_subsections.size() - 1]
	var min_h: float = SUB_MIN.get(sub["id"], 30.0)
	var editor_min: float = SUB_MIN.get(editor_sub["id"], 60.0)
	var max_dy: float = _sub_resize_next_h - editor_min
	var min_dy: float = min_h - _sub_resize_start_h
	dy = clampf(dy, min_dy, max_dy)
	var new_h: float = _sub_resize_start_h + dy
	sub["height"] = new_h
	editor_sub["height"] = _sub_resize_next_h - (new_h - _sub_resize_start_h)


func _handle_sub_resize_release() -> void:
	## On release, snap to preferred height if within snap distance.
	if _sub_resize_idx < 0 or _sub_resize_idx >= _subsections.size():
		return
	var sub: Dictionary = _subsections[_sub_resize_idx]
	var editor_sub: Dictionary = _subsections[_subsections.size() - 1]
	var snapped: float = _snap_height(sub["id"], sub["height"])
	if snapped != sub["height"]:
		var delta: float = snapped - sub["height"]
		sub["height"] = snapped
		editor_sub["height"] -= delta


func _handle_config_click(lx: float, my: float) -> void:
	## Click in the config section — filter, entity list, or slider drag.
	var pw: float = _content_width
	var y: float = 8.0

	# Title
	y += 22

	# Filter field (y to y+20)
	if my >= y and my < y + 20:
		_config_filter_focused = true
		return
	y += 24

	# Entity list — same combined list as drawing
	var all_entities_click: Array = []
	all_entities_click.append_array(get_tree().get_nodes_in_group("enemies"))
	all_entities_click.append_array(get_tree().get_nodes_in_group("players"))
	all_entities_click.append_array(get_tree().get_nodes_in_group("attack_dummies"))
	var seen_click: Dictionary = {}
	var entities_click: Array = []
	for e in all_entities_click:
		if not seen_click.has(e.get_instance_id()):
			seen_click[e.get_instance_id()] = true
			entities_click.append(e)
	y += 2  # separator
	y += 16  # "Entities" header
	var entity_row_h: float = 16.0
	for ei in range(entities_click.size()):
		if my >= y and my < y + entity_row_h:
			# Click on an entity — select it directly
			PlayerHUD.debug_select_entity(entities_click[ei])
			# Auto-enable state_info
			DebugOverlay.set_observer("state_info/state_text_panel", "human", true, DebugOverlay.TextMode.NONE)
			DebugOverlay.set_observer("state_info/selection_indicator", "human", true, DebugOverlay.TextMode.NONE)
			_config_keys.clear()
			_config_filter_focused = false
			return
		y += entity_row_h
	if entities_click.is_empty():
		y += entity_row_h
	y += 8  # gap + separator

	_config_filter_focused = false

	# Entity info header (type + props line)
	y += 16

	# Slider area — only for monsters with cfg()
	var monster: Node2D = _get_selected_monster()
	if not monster or _config_keys.is_empty():
		return

	var slider_h: float = 16.0
	var slider_gap: float = 2.0
	var row: int = int((my - y) / (slider_h + slider_gap)) + _config_scroll_offset
	if row >= 0 and row < _config_keys.size():
		var key: String = _config_keys[row]
		if lx > pw * 0.47 and lx < pw * 0.82:
			_config_dragging_key = key
			_handle_config_drag_at(lx, monster)


func _handle_config_drag(mx: float) -> void:
	## Drag a config slider.
	var monster: Node2D = _get_selected_monster()
	if not monster or _config_dragging_key.is_empty():
		return
	var content_x: float = _panel_x + ICON_BAR_WIDTH + 4
	var lx: float = mx - content_x
	_handle_config_drag_at(lx, monster)


func _handle_config_drag_at(lx: float, monster: Node2D) -> void:
	## Set config value based on slider position. Uses a single persistent
	## DictProvider for all slider edits — updates in place, never pushes new ones.
	var pw: float = _content_width
	var slider_x: float = pw * 0.47
	var slider_w: float = pw * 0.35
	var t: float = clampf((lx - slider_x) / slider_w, 0.0, 1.0)

	var key: String = _config_dragging_key
	var default_val: float = _get_config_default(monster, key)
	var range_info: Vector2 = _get_config_range(key, default_val)
	var new_val: float = lerpf(range_info.x, range_info.y, t)

	# Create the slider provider once, then update its data dict in place
	if _config_slider_provider == null:
		var MCP = load("res://scripts/systems/monster_config.gd")
		_config_slider_provider = MCP.DictProvider.new(_config_slider_data, "slider_edits")
		monster.push_config(_config_slider_provider)

	_config_slider_data[key] = new_val
	_panel.queue_redraw()


func _update_hover(my: float) -> void:
	var tree_y_start: float = _tree_y_start
	var row_idx: int = int((my - tree_y_start) / ROW_HEIGHT) + _scroll_offset
	_hover_row = row_idx


# -- Drawing -------------------------------------------------------------------

func _draw_panel() -> void:
	if _panel_x <= -_panel_width + 1:
		return

	var vp: Vector2 = get_viewport().get_visible_rect().size
	var font: Font = ThemeDB.fallback_font
	var pw: float = _panel_width
	var ph: float = vp.y

	# Background (fully opaque — game viewport is scaled to the right of the panel)
	_panel.draw_rect(Rect2(_panel_x, 0, pw, ph), Color(0.06, 0.06, 0.09, 1.0))
	# Right border
	_panel.draw_line(Vector2(_panel_x + pw, 0), Vector2(_panel_x + pw, ph), Color(0.2, 0.6, 1.0, 0.5), 2.0)

	# -- Icon bar (left strip) --
	var icon_x: float = _panel_x + 4
	_panel.draw_rect(Rect2(_panel_x, 0, ICON_BAR_WIDTH, ph), Color(0.04, 0.04, 0.07, 0.98))
	_panel.draw_line(Vector2(_panel_x + ICON_BAR_WIDTH, 0), Vector2(_panel_x + ICON_BAR_WIDTH, ph), Color(0.15, 0.15, 0.2), 1.0)

	var icon_sections: Array = [
		{"section": Section.DEBUG, "label": "D"},
		{"section": Section.TEST_RUNNER, "label": "T"},
		{"section": Section.CONFIG, "label": "C"},
	]
	for i in range(icon_sections.size()):
		var iy: float = 8.0 + i * (ICON_SIZE + ICON_PAD * 2 + 4)
		var is_active: bool = _current_section == icon_sections[i]["section"]
		var bg_col: Color = Color(0.15, 0.25, 0.4, 0.8) if is_active else Color(0.08, 0.08, 0.12, 0.6)
		_panel.draw_rect(Rect2(icon_x, iy, ICON_SIZE + ICON_PAD * 2, ICON_SIZE + ICON_PAD * 2), bg_col, true)
		if is_active:
			_panel.draw_rect(Rect2(icon_x, iy, 2, ICON_SIZE + ICON_PAD * 2), Color(0.3, 0.7, 1.0), true)
		var icon_center := Vector2(icon_x + ICON_PAD + ICON_SIZE * 0.5, iy + ICON_PAD + ICON_SIZE * 0.5)
		_draw_section_icon(icon_center, icon_sections[i]["section"], is_active)

	# -- Content area --
	var content_x: float = _panel_x + ICON_BAR_WIDTH + 4
	match _current_section:
		Section.DEBUG:
			_draw_debug_section(content_x, font, ph)
		Section.TEST_RUNNER:
			_draw_test_runner_section(content_x, font, ph)
		Section.CONFIG:
			_draw_config_section(content_x, font, ph)


func _draw_section_icon(center: Vector2, section: Section, active: bool) -> void:
	var col: Color = Color(0.8, 0.9, 1.0) if active else Color(0.4, 0.45, 0.5)
	var r: float = ICON_SIZE * 0.4
	match section:
		Section.DEBUG:
			# Magnifying glass icon
			_panel.draw_arc(center + Vector2(-2, -2), r, 0, TAU, 12, col, 1.5)
			_panel.draw_line(center + Vector2(r * 0.5, r * 0.5), center + Vector2(r + 3, r + 3), col, 2.0)
		Section.TEST_RUNNER:
			# Play/bug icon (triangle)
			var pts: PackedVector2Array = [
				center + Vector2(-r * 0.7, -r),
				center + Vector2(r, 0),
				center + Vector2(-r * 0.7, r),
			]
			_panel.draw_polygon(pts, PackedColorArray([col, col, col]))
		Section.CONFIG:
			# Gear icon (circle with notches)
			_panel.draw_arc(center, r * 0.6, 0, TAU, 10, col, 1.5)
			for ni in range(6):
				var a: float = float(ni) / 6.0 * TAU
				var p1: Vector2 = center + Vector2(cos(a), sin(a)) * r * 0.5
				var p2: Vector2 = center + Vector2(cos(a), sin(a)) * r * 1.0
				_panel.draw_line(p1, p2, col, 2.0)


func _draw_debug_section(content_x: float, font: Font, ph: float) -> void:
	## Original debug drawer content — aspect tree, filters, etc.
	var x: float = content_x
	var y: float = 8.0
	var pw: float = _content_width  # Width available for content

	# -- Filter field --
	var filter_bg: Color = Color(0.12, 0.12, 0.16) if _filter_focused else Color(0.08, 0.08, 0.12)
	_panel.draw_rect(Rect2(x, y, pw - 16, 20), filter_bg)
	var filter_display: String = _filter_text
	if _filter_focused and int(_cursor_blink * 2) % 2 == 0:
		filter_display += "_"
	if filter_display == "" and not _filter_focused:
		filter_display = "Filter aspects..."
		_panel.draw_string(font, Vector2(x + 4, y + 14), filter_display, HORIZONTAL_ALIGNMENT_LEFT, pw - 24, 10, Color(0.4, 0.4, 0.4))
	else:
		_panel.draw_string(font, Vector2(x + 4, y + 14), filter_display, HORIZONTAL_ALIGNMENT_LEFT, pw - 24, 10, Color(0.8, 0.8, 0.8))
	y += 26

	# -- Entity type filter --
	_panel.draw_string(font, Vector2(x, y + 12), "Types:", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.6, 0.6))
	var types: Array[String] = ["monster", "dummy", "attacker"]
	var type_x: float = x + 50
	for t in types:
		var enabled: bool = DebugOverlay.entity_type_filter.get(t, true)
		_draw_checkbox(type_x, y + 2, enabled)
		var tcol: Color = Color(0.8, 0.8, 0.8) if enabled else Color(0.4, 0.4, 0.4)
		_panel.draw_string(font, Vector2(type_x + 16, y + 13), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, tcol)
		type_x += 80
	y += 22

	# -- Entity ID filter --
	var id_bg: Color = Color(0.12, 0.12, 0.16) if _id_filter_focused else Color(0.08, 0.08, 0.12)
	_panel.draw_string(font, Vector2(x, y + 12), "ID:", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.6, 0.6))
	_panel.draw_rect(Rect2(x + 30, y, pw - 46, 18), id_bg)
	var id_display: String = DebugOverlay.entity_id_pattern
	if _id_filter_focused and int(_cursor_blink * 2) % 2 == 0:
		id_display += "_"
	_panel.draw_string(font, Vector2(x + 34, y + 13), id_display, HORIZONTAL_ALIGNMENT_LEFT, pw - 54, 10, Color(0.8, 0.8, 0.8))
	y += 22

	# -- Global toggle --
	var global_on: bool = DebugOverlay.global_enabled
	var global_col: Color = Color(0.3, 1.0, 0.3) if global_on else Color(0.5, 0.5, 0.5)
	_panel.draw_line(Vector2(x, y + 2), Vector2(x + pw - 16, y + 2), Color(0.3, 0.3, 0.3), 1.0)
	y += 6
	_draw_checkbox(x, y, global_on)
	_panel.draw_string(font, Vector2(x + 18, y + 12), "Global Debug", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, global_col)
	var save_hint: String = "Ctrl+S save" if _active else ""
	_panel.draw_string(font, Vector2(x + pw - 90, y + 12), save_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.4, 0.4))
	y += 20

	# -- Scale control --
	_panel.draw_line(Vector2(x, y), Vector2(x + pw - 16, y), Color(0.3, 0.3, 0.3), 1.0)
	y += 4
	_scale_area_y = y  # Track for click detection
	var monster: Node2D = _get_selected_monster()
	if monster:
		var cur_scale: float = monster.creature_scale
		var label_col := Color(0.5, 0.9, 0.5)
		_panel.draw_string(font, Vector2(x, y + 12), "Scale:", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, label_col)
		# Slider track
		var slider_x: float = x + 62
		var slider_w: float = pw - 90.0
		var slider_y: float = y + 8
		_panel.draw_rect(Rect2(slider_x, slider_y - 2, slider_w, 4), Color(0.2, 0.2, 0.25))
		# Tick marks at preset values
		for preset in SCALE_PRESETS:
			var tick_t: float = _scale_to_slider_t(preset)
			var tick_x: float = slider_x + tick_t * slider_w
			_panel.draw_line(Vector2(tick_x, slider_y - 5), Vector2(tick_x, slider_y + 5), Color(0.35, 0.35, 0.4), 1.0)
		# 1.0 tick highlighted
		var one_t: float = _scale_to_slider_t(1.0)
		var one_x: float = slider_x + one_t * slider_w
		_panel.draw_line(Vector2(one_x, slider_y - 6), Vector2(one_x, slider_y + 6), Color(0.5, 0.7, 1.0, 0.6), 1.0)
		# Thumb
		var thumb_t: float = _scale_to_slider_t(cur_scale)
		var thumb_x: float = slider_x + thumb_t * slider_w
		var thumb_col := Color(0.3, 1.0, 0.5) if _scale_dragging else Color(0.5, 0.9, 0.5)
		_panel.draw_circle(Vector2(thumb_x, slider_y), 6.0, thumb_col)
		# Value text
		_panel.draw_string(font, Vector2(x + pw - 48, y + 13), "%.2f" % cur_scale, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, label_col)
	else:
		_panel.draw_string(font, Vector2(x, y + 12), "Scale: (TAB-select a monster)", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.4, 0.4, 0.4))
	y += SCALE_SLIDER_H

	# -- Column headers --
	var v_col_x: float = x + pw - 60
	var t_col_x: float = x + pw - 30
	_panel.draw_string(font, Vector2(v_col_x - 2, y + 10), "V", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.5, 0.7, 1.0))
	_panel.draw_string(font, Vector2(t_col_x - 2, y + 10), "T", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.5, 0.7, 1.0))
	_panel.draw_line(Vector2(x, y + 14), Vector2(x + pw - 16, y + 14), Color(0.25, 0.25, 0.3), 1.0)
	y += 16

	# -- Aspect tree --
	if _visible_rows.is_empty():
		_rebuild_visible_rows()

	_tree_y_start = y  # Store for click/hover detection
	var tree_y_start: float = y
	var max_visible: int = int((ph - tree_y_start - 8) / ROW_HEIGHT)
	var end_idx: int = mini(_scroll_offset + max_visible, _visible_rows.size())

	for ri in range(_scroll_offset, end_idx):
		var row: Dictionary = _visible_rows[ri]
		var ry: float = tree_y_start + (ri - _scroll_offset) * ROW_HEIGHT
		var is_hovered: bool = (ri == _hover_row)

		if is_hovered:
			_panel.draw_rect(Rect2(_panel_x, ry, pw, ROW_HEIGHT), Color(0.15, 0.15, 0.2))

		if row["type"] == "group":
			_draw_group_row(row, x, ry, v_col_x, t_col_x, font)
		elif row["type"] == "aspect":
			_draw_aspect_row(row, x, ry, v_col_x, t_col_x, font)

	# Scroll indicator
	if _visible_rows.size() > max_visible:
		var pct: float = float(_scroll_offset) / float(_visible_rows.size() - max_visible)
		var bar_h: float = maxf(20.0, ph * float(max_visible) / float(_visible_rows.size()))
		var bar_y: float = tree_y_start + pct * (ph - tree_y_start - bar_h)
		_panel.draw_rect(Rect2(x + pw - 4, bar_y, 3, bar_h), Color(0.3, 0.3, 0.4, 0.5))


func _draw_group_row(row: Dictionary, x: float, ry: float, v_col_x: float, t_col_x: float, font: Font) -> void:
	var collapsed: bool = row["collapsed"]
	var group: String = row["group"]
	var aspects: Array[String] = row["aspects"]

	# Collapse arrow
	var arrow_x: float = x + 2
	var arrow_y: float = ry + ROW_HEIGHT * 0.5
	if collapsed:
		# Right-pointing triangle ▶
		var pts := PackedVector2Array([
			Vector2(arrow_x, arrow_y - 5),
			Vector2(arrow_x + 7, arrow_y),
			Vector2(arrow_x, arrow_y + 5),
		])
		_panel.draw_polygon(pts, PackedColorArray([Color(0.5, 0.5, 0.6), Color(0.5, 0.5, 0.6), Color(0.5, 0.5, 0.6)]))
	else:
		# Down-pointing triangle ▼
		var pts := PackedVector2Array([
			Vector2(arrow_x, arrow_y - 4),
			Vector2(arrow_x + 8, arrow_y - 4),
			Vector2(arrow_x + 4, arrow_y + 4),
		])
		_panel.draw_polygon(pts, PackedColorArray([Color(0.5, 0.7, 1.0), Color(0.5, 0.7, 1.0), Color(0.5, 0.7, 1.0)]))

	# Group name
	_panel.draw_string(font, Vector2(x + 14, ry + 13), group, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.7, 1.0))

	# Group-level V/T indicators (aggregate)
	var any_vis: bool = false
	var any_txt: int = DebugOverlay.TextMode.NONE
	for path in aspects:
		var state: Array = DebugOverlay.get_observer_state(path, "human")
		if state[0]:
			any_vis = true
		if state[1] > any_txt:
			any_txt = state[1]
	_draw_checkbox(v_col_x - 4, ry + 2, any_vis)
	_draw_text_mode_indicator(t_col_x - 4, ry + 2, any_txt, font)


func _draw_aspect_row(row: Dictionary, x: float, ry: float, v_col_x: float, t_col_x: float, font: Font) -> void:
	var path: String = row["path"]
	var info: DebugOverlay.AspectInfo = row["info"]
	var state: Array = DebugOverlay.get_observer_state(path, "human")
	var visual_on: bool = state[0]
	var textual: int = state[1]

	# Actualized state (union of all observers)
	var actual_vis: bool = info._actual_visual
	var actual_txt: int = info._actual_textual

	# Sub-aspect name (indented)
	var label: String = info.sub if info.sub != "" else info.group
	var label_col: Color = Color(0.75, 0.75, 0.75) if actual_vis or actual_txt != DebugOverlay.TextMode.NONE else Color(0.4, 0.4, 0.4)

	# Show non-human observer indicator
	var has_other_observers: bool = false
	for obs_id in info.observers:
		if obs_id != "human":
			has_other_observers = true
			break

	if has_other_observers:
		label_col = Color(0.6, 0.8, 1.0) if not visual_on and textual == DebugOverlay.TextMode.NONE else label_col
		# Small dot to indicate other observers
		_panel.draw_circle(Vector2(x + INDENT + 2, ry + ROW_HEIGHT * 0.5), 2.0, Color(0.3, 0.6, 1.0, 0.7))

	_panel.draw_string(font, Vector2(x + INDENT + 6, ry + 13), label, HORIZONTAL_ALIGNMENT_LEFT, int(v_col_x - x - INDENT - 14), 9, label_col)

	# Visual checkbox
	_draw_checkbox(v_col_x - 4, ry + 2, visual_on)
	# If another observer has visual, show border highlight
	if actual_vis and not visual_on:
		_panel.draw_rect(Rect2(v_col_x - 4, ry + 2, CHECKBOX_SIZE, CHECKBOX_SIZE), Color(0.3, 0.6, 1.0, 0.5), false, 1.0)

	# Textual mode indicator
	_draw_text_mode_indicator(t_col_x - 4, ry + 2, textual, font)
	if actual_txt != DebugOverlay.TextMode.NONE and textual == DebugOverlay.TextMode.NONE:
		_panel.draw_rect(Rect2(t_col_x - 4, ry + 2, CHECKBOX_SIZE, CHECKBOX_SIZE), Color(0.3, 0.6, 1.0, 0.5), false, 1.0)


func _draw_checkbox(cx: float, cy: float, checked: bool) -> void:
	var box := Rect2(cx, cy, CHECKBOX_SIZE, CHECKBOX_SIZE)
	if checked:
		_panel.draw_rect(box, Color(0.2, 0.7, 0.3, 0.8))
		# Checkmark
		_panel.draw_line(Vector2(cx + 2, cy + 6), Vector2(cx + 5, cy + 10), Color.WHITE, 1.5)
		_panel.draw_line(Vector2(cx + 5, cy + 10), Vector2(cx + 10, cy + 2), Color.WHITE, 1.5)
	else:
		_panel.draw_rect(box, Color(0.2, 0.2, 0.25))
		_panel.draw_rect(box, Color(0.35, 0.35, 0.4), false, 1.0)


func _draw_text_mode_indicator(tx: float, ty: float, mode: int, font: Font) -> void:
	var box := Rect2(tx, ty, CHECKBOX_SIZE, CHECKBOX_SIZE)
	var label: String = ""
	var col: Color = Color(0.2, 0.2, 0.25)

	match mode:
		DebugOverlay.TextMode.NONE:
			_panel.draw_rect(box, col)
			_panel.draw_rect(box, Color(0.35, 0.35, 0.4), false, 1.0)
			return
		DebugOverlay.TextMode.LOG:
			label = "L"
			col = Color(0.2, 0.5, 0.7, 0.8)
		DebugOverlay.TextMode.CONSOLE:
			label = "C"
			col = Color(0.6, 0.4, 0.7, 0.8)
		DebugOverlay.TextMode.BOTH:
			label = "B"
			col = Color(0.7, 0.5, 0.2, 0.8)

	_panel.draw_rect(box, col)
	_panel.draw_string(font, Vector2(tx + 2, ty + 10), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)


func _draw_test_runner_section(content_x: float, font: Font, ph: float) -> void:
	## Test runner with collapsible sub-sections: Suites, Tests, Controls, Status, Editor.
	if not _subsections_initialized:
		_init_subsections()
	if _cached_lists_dirty:
		_rebuild_cached_lists()

	var x: float = content_x
	var pw: float = _content_width
	var y: float = 0.0

	# Get the test editor for status/editor sub-sections
	var te: Node = _get_test_editor()

	for si in range(_subsections.size()):
		var sub: Dictionary = _subsections[si]
		# Clip: don't draw sub-sections that are entirely below the panel
		if y > ph:
			break

		# Draw header bar
		_draw_sub_header(x, y, pw, font, sub)

		if sub["collapsed"]:
			y += SUB_HEADER_H
			continue

		# Editor (last section) fills all remaining space
		var body_y: float = y + SUB_HEADER_H
		var body_h: float
		if sub["id"] == "editor":
			body_h = maxf(SUB_MIN["editor"] - SUB_HEADER_H, ph - body_y)
		else:
			body_h = sub["height"] - SUB_HEADER_H

		if body_h > 0:
			match sub["id"]:
				"suites":  _draw_sub_suites(x, body_y, pw, body_h, font)
				"tests":   _draw_sub_tests(x, body_y, pw, body_h, font)
				"controls": _draw_sub_controls(x, body_y, pw, body_h, font, te)
				"status":  _draw_sub_status(x, body_y, pw, body_h, font, te)
				"editor":  _draw_sub_editor(x, body_y, pw, body_h, font, te)

		# Draw snap-point indicator when resizing this section
		if _sub_resize_idx == si and sub["id"] != "editor":
			var snap_h: float = _get_preferred_height(sub["id"])
			var snap_y: float = y + snap_h  # y is still at the top of this section
			var near_snap: bool = absf(sub["height"] - snap_h) < SUB_SNAP_DISTANCE
			var snap_col := Color(0.3, 0.8, 1.0, 0.6) if near_snap else Color(0.3, 0.8, 1.0, 0.25)
			# Dashed line at the snap point
			var dash_len: float = 6.0
			var gap_len: float = 4.0
			var dx: float = 0.0
			while dx < pw - 16:
				_panel.draw_line(
					Vector2(x + dx, snap_y),
					Vector2(x + minf(dx + dash_len, pw - 16), snap_y),
					snap_col, 1.0)
				dx += dash_len + gap_len
			# Small label
			if near_snap:
				_panel.draw_string(font, Vector2(x + pw - 40, snap_y - 3), "snap", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, snap_col)

		if sub["id"] == "editor":
			y += body_h + SUB_HEADER_H
		else:
			y += sub["height"]

		# Draw resize grip line at the bottom of each sub-section (not for editor)
		if sub["id"] != "editor":
			_panel.draw_line(Vector2(x, y - 1), Vector2(x + pw - 8, y - 1), Color(0.2, 0.3, 0.4, 0.4), 1.0)


func _draw_sub_header(x: float, y: float, pw: float, font: Font, sub: Dictionary) -> void:
	## Draw a sub-section header bar with collapse icon, title, context info, and grip.
	var bg_col := Color(0.08, 0.1, 0.14, 0.95)
	_panel.draw_rect(Rect2(x, y, pw - 8, SUB_HEADER_H), bg_col)
	_panel.draw_line(Vector2(x, y), Vector2(x + pw - 8, y), Color(0.25, 0.35, 0.5, 0.6), 1.0)

	# Collapse triangle
	var tri_x: float = x + 6
	var tri_y: float = y + SUB_HEADER_H * 0.5
	var tri_col := Color(0.5, 0.6, 0.7)
	if sub["collapsed"]:
		var pts: PackedVector2Array = [
			Vector2(tri_x, tri_y - 5), Vector2(tri_x + 6, tri_y), Vector2(tri_x, tri_y + 5)]
		_panel.draw_polygon(pts, PackedColorArray([tri_col, tri_col, tri_col]))
	else:
		var pts: PackedVector2Array = [
			Vector2(tri_x - 1, tri_y - 3), Vector2(tri_x + 7, tri_y - 3), Vector2(tri_x + 3, tri_y + 4)]
		_panel.draw_polygon(pts, PackedColorArray([tri_col, tri_col, tri_col]))

	# Title
	var title_col := Color(0.6, 0.8, 0.5)
	_panel.draw_string(font, Vector2(x + 18, y + 14), sub["title"], HORIZONTAL_ALIGNMENT_LEFT, 60, 10, title_col)

	# Context info in the bar (varies by sub-section)
	var te: Node = _get_test_editor()
	var ctx_text: String = ""
	var ctx_col := Color(0.5, 0.65, 0.8)
	var sid: String = sub["id"]
	match sid:
		"tests":
			# Show selected suite name in the bar
			if not _selected_suite_name.is_empty():
				ctx_text = _selected_suite_name
				ctx_col = Color(0.5, 0.75, 1.0)
		"controls":
			# Show test name + mode (EDIT/EXEC/INSPECT)
			if te and "_test_name" in te and not te._test_name.is_empty():
				ctx_text = te._test_name
			var mode_str: String = ""
			var mode_col := Color(0.5, 0.5, 0.5)
			if te and "_mode" in te:
				match te._mode:
					0:  # EDIT
						mode_str = "EDIT"
						mode_col = Color(0.3, 0.8, 0.3)
					1:  # EXECUTE
						mode_str = "EXEC"
						mode_col = Color(0.8, 0.5, 0.2)
					2:  # INSPECT
						mode_str = "INSPECT"
						mode_col = Color(0.3, 0.7, 1.0)
			if not mode_str.is_empty():
				_panel.draw_string(font, Vector2(x + pw - 68, y + 14), mode_str, HORIZONTAL_ALIGNMENT_LEFT, 38, 9, mode_col)
		"status":
			if te and "_test_name" in te and not te._test_name.is_empty():
				ctx_text = te._test_name
		"editor":
			if te and "_test_name" in te and not te._test_name.is_empty():
				ctx_text = te._test_name
				# Save button (💾) — only when dirty, right after the name
				if te._dirty:
					ctx_text += " ●"
					var save_x: float = x + 78 + font.get_string_size(ctx_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 6
					_panel.draw_string(font, Vector2(save_x, y + 14), "💾", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.8, 0.8, 0.4, 0.9))
			# Approve-all-deletes button (✕) — just left of grip, only when pending deletes exist
			if not _editor_pending_deletes.is_empty():
				_panel.draw_string(font, Vector2(x + pw - 38, y + 14), "✕", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.3, 0.3, 1.0))

	if not ctx_text.is_empty():
		var ctx_x: float = x + 78
		var ctx_max_w: float = pw - 108
		if sid == "controls":
			ctx_max_w = pw - 140  # Leave room for EDIT/RUN label
		elif sid == "editor":
			ctx_max_w = pw - 130  # Leave room for save + approve buttons
		_panel.draw_string(font, Vector2(ctx_x, y + 14), ctx_text, HORIZONTAL_ALIGNMENT_LEFT, ctx_max_w, 9, ctx_col)

	# Drag grip dots (right side)
	var grip_x: float = x + pw - 22
	for gi in range(3):
		for gj in range(2):
			_panel.draw_rect(Rect2(grip_x + gj * 5, y + 5 + gi * 5, 2, 2), Color(0.3, 0.35, 0.4))


func _draw_sub_suites(x: float, y: float, pw: float, h: float, font: Font) -> void:
	## Draw selectable suite list with pass/fail indicators and play buttons.
	var row_h: float = 18.0
	var visible_count: int = int(h / row_h)
	for i in range(mini(visible_count, _cached_suite_names.size())):
		var suite_name: String = _cached_suite_names[i]
		var ry: float = y + i * row_h
		var hover: bool = _test_hover_item == suite_name
		var is_sel: bool = _selected_suite_name == suite_name

		# Row background
		if is_sel:
			_panel.draw_rect(Rect2(x, ry, pw - 8, row_h - 2), Color(0.12, 0.22, 0.12))
		elif hover:
			_panel.draw_rect(Rect2(x, ry, pw - 8, row_h - 2), Color(0.15, 0.2, 0.3))

		# Pass/fail indicator dot
		if _suite_results.has(suite_name):
			var res: Dictionary = _suite_results[suite_name]
			var dot_col: Color = Color(0.3, 1.0, 0.3) if res["passed"] == res["total"] else Color(1.0, 0.3, 0.3)
			_panel.draw_circle(Vector2(x + 6, ry + 8), 3.5, dot_col)
			# Score text
			_panel.draw_string(font, Vector2(pw - 44, ry + 12), "%d/%d" % [res["passed"], res["total"]], HORIZONTAL_ALIGNMENT_LEFT, 30, 8, dot_col)
		else:
			_panel.draw_circle(Vector2(x + 6, ry + 8), 3.0, Color(0.3, 0.3, 0.3))

		# Suite name
		var name_col := Color(0.5, 1.0, 0.5) if is_sel else (Color(0.8, 0.8, 0.8) if hover else Color(0.6, 0.6, 0.6))
		_panel.draw_string(font, Vector2(x + 14, ry + 13), suite_name, HORIZONTAL_ALIGNMENT_LEFT, pw - 70, 9, name_col)

		# Play button (right edge) — visible when hovered/selected, subtle otherwise
		var btn_x: float = x + pw - 22
		var play_col: Color
		if hover or is_sel:
			play_col = Color(0.4, 0.8, 0.3, 0.9)
		else:
			play_col = Color(0.3, 0.4, 0.3, 0.15)
		var play_pts: PackedVector2Array = [
			Vector2(btn_x, ry + 3), Vector2(btn_x + 8, ry + 8), Vector2(btn_x, ry + 13)]
		_panel.draw_polygon(play_pts, PackedColorArray([play_col, play_col, play_col]))


func _draw_sub_tests(x: float, y: float, pw: float, h: float, font: Font) -> void:
	## Draw scrollable test list with number, pass/fail indicator, and play button.
	## Filtered by selected suite if one is active.
	var row_h: float = 16.0
	var display_tests: Array[String] = _get_display_test_list()
	var visible_count: int = int(h / row_h)
	var max_scroll: int = maxi(0, display_tests.size() - visible_count)
	_test_scroll_offset = clampi(_test_scroll_offset, 0, max_scroll)

	# Suite name is now shown in the header bar — no in-body header needed
	var te: Node = _get_test_editor()
	var rcon: Node = get_node_or_null("/root/Rcon")
	var runner: Node = rcon._test_runner if rcon and "_test_runner" in rcon else null

	for i in range(mini(visible_count, display_tests.size() - _test_scroll_offset)):
		var tname: String = display_tests[i + _test_scroll_offset]
		var test_num: int = i + _test_scroll_offset + 1
		var ry: float = y + i * row_h
		var hover: bool = _test_hover_item == tname
		var is_loaded: bool = te != null and "_test_name" in te and te._test_name == tname
		var is_running: bool = runner != null and runner._running and runner._current_test_name == tname

		# Row background
		if is_running:
			_panel.draw_rect(Rect2(x, ry, pw - 8, row_h - 2), Color(0.1, 0.2, 0.1))
		elif is_loaded:
			_panel.draw_rect(Rect2(x, ry, pw - 8, row_h - 2), Color(0.1, 0.18, 0.1))
		elif hover:
			_panel.draw_rect(Rect2(x, ry, pw - 8, row_h - 2), Color(0.15, 0.2, 0.3))

		# Test number (1-indexed)
		var num_col := Color(0.4, 0.5, 0.6)
		_panel.draw_string(font, Vector2(x + 2, ry + 11), "%d" % test_num, HORIZONTAL_ALIGNMENT_LEFT, 16, 8, num_col)

		# Pass/fail indicator
		var result: String = _test_results_cache.get(tname, "")
		if result == "pass":
			_panel.draw_circle(Vector2(x + 22, ry + 7), 3.0, Color(0.3, 1.0, 0.3))
		elif result == "fail":
			_panel.draw_circle(Vector2(x + 22, ry + 7), 3.0, Color(1.0, 0.3, 0.3))
		else:
			_panel.draw_circle(Vector2(x + 22, ry + 7), 2.5, Color(0.3, 0.3, 0.3))

		# Test name
		var col := Color(0.7, 0.7, 0.7) if hover else (Color(0.5, 0.8, 0.4) if is_loaded else Color(0.5, 0.5, 0.5))
		_panel.draw_string(font, Vector2(x + 30, ry + 11), tname, HORIZONTAL_ALIGNMENT_LEFT, pw - 52, 8, col)

		# Play/pause button (right edge) — visible when hovered/selected/running, subtle otherwise
		var btn_x: float = x + pw - 22
		if is_running:
			# Pause icon (two bars) — always visible when running
			_panel.draw_rect(Rect2(btn_x, ry + 3, 3, 10), Color(0.9, 0.7, 0.2))
			_panel.draw_rect(Rect2(btn_x + 5, ry + 3, 3, 10), Color(0.9, 0.7, 0.2))
		else:
			var play_col: Color
			if hover or is_loaded:
				play_col = Color(0.4, 0.8, 0.3, 0.9)
			else:
				play_col = Color(0.3, 0.4, 0.3, 0.15)
			var play_pts: PackedVector2Array = [
				Vector2(btn_x, ry + 3), Vector2(btn_x + 8, ry + 8), Vector2(btn_x, ry + 13)]
			_panel.draw_polygon(play_pts, PackedColorArray([play_col, play_col, play_col]))

	# Scrollbar
	if display_tests.size() > visible_count and max_scroll > 0:
		var pct: float = float(_test_scroll_offset) / float(max_scroll)
		var bar_h: float = maxf(16.0, h * float(visible_count) / float(display_tests.size()))
		var bar_y: float = y + pct * (h - bar_h)
		_panel.draw_rect(Rect2(x + pw - 12, bar_y, 3, bar_h), Color(0.3, 0.3, 0.4, 0.5))


func _draw_sub_controls(x: float, y: float, pw: float, h: float, font: Font, te: Node) -> void:
	## Draw test control buttons. Title and mode are shown in the header bar.
	if not te:
		_panel.draw_string(font, Vector2(x + 4, y + 14), "(no test loaded)", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.4, 0.4, 0.4))
		return

	# Button bar fills the entire body
	_panel.draw_rect(Rect2(x, y, pw - 8, h), Color(0.07, 0.1, 0.07, 0.8))
	var btns: Array = te._get_buttons()
	if btns.is_empty():
		return
	var bw: float = (pw - 24.0) / float(btns.size())
	for i in range(btns.size()):
		var bx: float = x + 8.0 + i * bw
		var label: String = btns[i][0]
		var col: Color = btns[i][1]
		_panel.draw_rect(Rect2(bx, y + 4, bw - 4, h - 8), col * Color(1, 1, 1, 0.15))
		_panel.draw_rect(Rect2(bx, y + 4, bw - 4, h - 8), col * Color(1, 1, 1, 0.5), false, 1.0)
		_panel.draw_string(font, Vector2(bx + 4, y + h - 8), label, HORIZONTAL_ALIGNMENT_LEFT, bw - 8, 9, col)


func _draw_sub_status(x: float, y: float, pw: float, h: float, font: Font, te: Node) -> void:
	## Draw test status/results inside its sub-section body.
	if not te:
		return

	var ry: float = y
	var rcon: Node = get_node_or_null("/root/Rcon")
	var runner: Node = rcon._test_runner if rcon else null

	# Run status indicator
	if runner and runner._running:
		_panel.draw_rect(Rect2(x, ry, pw - 8, 16), Color(0.1, 0.2, 0.1))
		var elapsed: float = (Time.get_ticks_msec() - runner._test_start_time) / 1000.0
		_panel.draw_string(font, Vector2(x + 4, ry + 12), "RUNNING: %s (%s) %.1fs" % [runner._current_test_name, runner._test_state, elapsed], HORIZONTAL_ALIGNMENT_LEFT, pw - 16, 9, Color(0.3, 1.0, 0.3))
		ry += 18

	# Result summary
	if not te._run_summary.is_empty():
		var has_fail: bool = "fail" in te._run_results.values()
		var sum_col := Color(0.3, 1.0, 0.3) if not has_fail else Color(1.0, 0.4, 0.4)
		var sum_bg := Color(0.08, 0.15, 0.08, 0.95) if not has_fail else Color(0.2, 0.08, 0.08, 0.95)
		_panel.draw_rect(Rect2(x, ry, pw - 8, 18), sum_bg)
		_panel.draw_string(font, Vector2(x + 4, ry + 13), te._run_summary, HORIZONTAL_ALIGNMENT_LEFT, pw - 16, 10, sum_col)
		ry += 20

	# Check detail log — show selected row's detail, or ALL check results if no row selected
	var all_log_lines: Array = []
	if te._selected_row >= 0 and te._run_detail.has(te._selected_row):
		# Show just the selected row's detail
		all_log_lines = te._run_detail[te._selected_row]
	elif te._selected_row < 0 or not te._run_detail.has(te._selected_row):
		# No row selected (or selected row has no detail) — show all check results
		for si in te._run_detail:
			var detail: Array = te._run_detail[si]
			for line in detail:
				all_log_lines.append(line)

	if not all_log_lines.is_empty():
		var line_h: float = 13.0
		var visible_count: int = int((y + h - ry) / line_h)
		var max_scroll: int = maxi(0, all_log_lines.size() - visible_count)
		_status_scroll_offset = clampi(_status_scroll_offset, 0, max_scroll)
		for li in range(_status_scroll_offset, mini(_status_scroll_offset + visible_count, all_log_lines.size())):
			var line_text: String = str(all_log_lines[li])
			var line_col := Color(0.6, 0.6, 0.6)
			if "FAIL" in line_text or "✗" in line_text:
				line_col = Color(1.0, 0.4, 0.4)
			elif "PASS" in line_text or "✓" in line_text:
				line_col = Color(0.4, 0.9, 0.4)
			_panel.draw_string(font, Vector2(x + 4, ry + 10), line_text, HORIZONTAL_ALIGNMENT_LEFT, pw - 16, 8, line_col)
			ry += line_h


func _draw_sub_editor(x: float, y: float, pw: float, h: float, font: Font, te: Node) -> void:
	## Draw test script editor with variable-height rows, soft-wrap, and pending deletion strikeout.
	if not te or te._script.is_empty():
		var msg: String = "(no script loaded — click a test above, or press T)" if not te or te._test_name.is_empty() else "(empty script)"
		_panel.draw_string(font, Vector2(x + 4, y + 14), msg, HORIZONTAL_ALIGNMENT_LEFT, pw - 8, 10, Color(0.4, 0.4, 0.4))
		return

	var base_row_h: float = 18.0
	var text_x: float = x + 36  # Left margin for command text (after line num + status)
	var text_w: float = pw - 56  # Width available for text (leave room for buttons on right)
	var is_edit_mode: bool = te._mode == 0  # EDIT
	var is_exec_mode: bool = te._mode == 1  # EXECUTE
	var is_inspect_mode: bool = te._mode == 2  # INSPECT
	# Edit field height: dynamic based on soft-wrapped content
	var edit_h: float = 0.0
	if te._selected_row >= 0 and is_edit_mode:
		var edit_wrap_lines: Array[String] = _get_soft_wrap_lines(te._edit_text, text_w, font, 10)
		edit_h = maxf(32.0, 8.0 + edit_wrap_lines.size() * base_row_h)
	var list_h: float = h - edit_h
	var script_size: int = te._script.size()
	_editor_body_y = y

	# Build cumulative Y positions for variable-height rows
	_editor_row_y_map.clear()
	var cum_y: float = 0.0
	for si in range(script_size + 1):  # +1 for ghost row
		_editor_row_y_map.append(cum_y)
		if si < script_size:
			cum_y += _get_row_height(te, si, text_w, font)
		else:
			cum_y += base_row_h  # Ghost row

	# Scroll management using cumulative heights
	# Find which row is at the top after scrolling
	var scroll_y: float = 0.0
	for si in range(_editor_scroll_offset):
		if si < _editor_row_y_map.size() - 1:
			scroll_y += _editor_row_y_map[si + 1] - _editor_row_y_map[si]

	# Script row list background
	_panel.draw_rect(Rect2(x, y, pw - 8, list_h), Color(0.05, 0.05, 0.08, 0.9))

	var rcon: Node = get_node_or_null("/root/Rcon")
	var ry: float = y
	for si in range(_editor_scroll_offset, script_size):
		if ry > y + list_h:
			break

		var this_row_h: float = _get_row_height(te, si, text_w, font)

		var is_sel: bool = (si == te._selected_row)
		var is_pending_delete: bool = _editor_pending_deletes.has(si)

		# Row background — color depends on mode
		if is_pending_delete:
			_panel.draw_rect(Rect2(x, ry, pw - 8, this_row_h), Color(0.25, 0.08, 0.08, 0.6))
		elif is_sel:
			if is_inspect_mode:
				_panel.draw_rect(Rect2(x, ry, pw - 8, this_row_h), Color(0.1, 0.2, 0.35, 1.0))  # Blue for inspect
			else:
				_panel.draw_rect(Rect2(x, ry, pw - 8, this_row_h), Color(0.15, 0.35, 0.15, 1.0))  # Green for edit
		elif (si - _editor_scroll_offset) % 2 == 1:
			_panel.draw_rect(Rect2(x, ry, pw - 8, this_row_h), Color(0.0, 0.0, 0.0, 0.15))

		# Line number
		var num_col := Color(0.4, 0.6, 0.4) if not is_sel else Color(0.7, 1.0, 0.7)
		if is_pending_delete:
			num_col = Color(0.5, 0.3, 0.3)
		_panel.draw_string(font, Vector2(x + 4, ry + 14), "%2d" % (si + 1), HORIZONTAL_ALIGNMENT_LEFT, 20, 9, num_col)

		# Status indicator (run state / result)
		if te._run_results.has(si):
			var res: String = te._run_results[si]
			match res:
				"pass":
					_panel.draw_string(font, Vector2(x + 24, ry + 14), "✓", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.3, 1.0, 0.3))
				"fail":
					_panel.draw_string(font, Vector2(x + 24, ry + 14), "✗", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.3, 0.3))
					_panel.draw_rect(Rect2(x, ry, pw - 8, this_row_h), Color(0.4, 0.1, 0.1, 0.3))
				"info":
					_panel.draw_string(font, Vector2(x + 24, ry + 14), "·", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.5, 0.5))
		elif te._run_running and rcon and rcon._test_runner:
			var line_state: String = ""
			if rcon._test_runner._line_states.has(si):
				line_state = rcon._test_runner._line_states[si]
			match line_state:
				"pending":
					_panel.draw_string(font, Vector2(x + 24, ry + 14), "○", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.5, 0.5))
				"running":
					_panel.draw_string(font, Vector2(x + 24, ry + 14), "●", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.3, 1.0, 0.3))
					_panel.draw_rect(Rect2(x, ry, pw - 8, this_row_h), Color(0.1, 0.25, 0.1, 0.3))
				"complete":
					_panel.draw_string(font, Vector2(x + 24, ry + 14), "✓", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.7, 0.5))

		# Command text with soft-wrap
		var cmd_text: String = te._script[si]
		var text_col := Color(0.95, 0.95, 0.85) if is_sel else _test_cmd_color(cmd_text)
		if is_pending_delete:
			text_col = text_col * Color(1, 1, 1, 0.4)
		var wrap_lines: Array[String] = _get_soft_wrap_lines(cmd_text, text_w, font, 10)
		for wi in range(wrap_lines.size()):
			var line_y: float = ry + 14 + wi * base_row_h
			if wi > 0:
				# Draw wrap indicator (↵ arrow) at the end of the previous wrap line
				_panel.draw_string(font, Vector2(text_x + text_w - 8, line_y - base_row_h), "↵", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.4, 0.5, 0.4, 0.5))
			_panel.draw_string(font, Vector2(text_x + (8 if wi > 0 else 0), line_y), wrap_lines[wi], HORIZONTAL_ALIGNMENT_LEFT, text_w - (8 if wi > 0 else 0), 10, text_col)

		# Strikethrough for pending deletions
		if is_pending_delete:
			var strike_y: float = ry + this_row_h * 0.5
			_panel.draw_line(Vector2(text_x, strike_y), Vector2(text_x + text_w, strike_y), Color(1.0, 0.3, 0.3, 0.6), 1.5)

		# Right-side buttons (only in EDIT mode)
		# Layout: [#] [✕] — comment toggle + delete, both on hover
		# When pending delete: [↶] [✕] — undo + confirm, always visible
		var is_hover_row: bool = (_editor_hover_row == si)
		var is_commented: bool = cmd_text.strip_edges().begins_with("#")
		if (is_edit_mode or is_inspect_mode) and not te._run_running:
			if is_pending_delete:
				_panel.draw_string(font, Vector2(x + pw - 32, ry + 14), "↶", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.7, 1.0, 0.9))
				_panel.draw_string(font, Vector2(x + pw - 16, ry + 14), "✕", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.2, 0.2, 1.0))
			elif is_hover_row:
				# Comment toggle (#) — shows commented state
				var hash_col: Color = Color(0.5, 0.8, 0.4, 0.9) if is_commented else Color(0.5, 0.5, 0.5, 0.7)
				_panel.draw_string(font, Vector2(x + pw - 34, ry + 14), "#", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, hash_col)
				# Delete button (✕)
				_panel.draw_string(font, Vector2(x + pw - 20, ry + 14), "✕", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.3, 0.3, 0.8))

		ry += this_row_h

	# Insertion indicator — LEFT side only, green triangle with "+" (EDIT mode only)
	if is_edit_mode and _editor_insert_idx >= 0 and _editor_hover_y >= 0 and not te._run_running:
		var ins_y: float = _editor_hover_y
		if ins_y >= y and ins_y <= y + list_h:
			# Green line
			_panel.draw_line(Vector2(x + 16, ins_y), Vector2(x + pw - 12, ins_y), Color(0.3, 0.9, 0.3, 0.5), 1.0)
			# Green triangle pointing right with "+"
			var tri_x: float = x + 4
			var tri_pts: PackedVector2Array = [
				Vector2(tri_x, ins_y - 5), Vector2(tri_x + 8, ins_y), Vector2(tri_x, ins_y + 5)]
			_panel.draw_polygon(tri_pts, PackedColorArray([Color(0.3, 0.9, 0.3, 0.7), Color(0.3, 0.9, 0.3, 0.7), Color(0.3, 0.9, 0.3, 0.7)]))
			_panel.draw_string(font, Vector2(tri_x + 10, ins_y + 4), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.3, 0.9, 0.3, 0.9))

	# Inline edit field (EDIT mode only) — soft-wrapped to fit
	if is_edit_mode and te._selected_row >= 0 and edit_h > 0:
		var ey: float = y + list_h
		var edit_bg: Color = Color(0.1, 0.12, 0.1) if te._edit_valid else Color(0.2, 0.1, 0.1)
		_panel.draw_rect(Rect2(x, ey, pw - 8, edit_h), edit_bg)
		_panel.draw_line(Vector2(x, ey), Vector2(x + pw - 8, ey), Color(0.3, 0.5, 0.3, 0.4), 1.0)
		# Build display text with cursor indicator
		var edit_display: String = te._edit_text
		if te._edit_focused and int(_cursor_blink * 2) % 2 == 0:
			edit_display = edit_display.substr(0, te._edit_cursor) + "|" + edit_display.substr(te._edit_cursor)
		# Soft-wrap the edit text
		var edit_lines: Array[String] = _get_soft_wrap_lines(edit_display, text_w, font, 10)
		for eli in range(edit_lines.size()):
			var eiy: float = ey + 16 + eli * base_row_h
			var indent: float = 8.0 if eli > 0 else 0.0
			if eli > 0:
				_panel.draw_string(font, Vector2(text_x + text_w - 8, eiy - base_row_h), "↵", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.4, 0.5, 0.4, 0.5))
			_panel.draw_string(font, Vector2(x + 6 + indent, eiy), edit_lines[eli], HORIZONTAL_ALIGNMENT_LEFT, text_w - indent, 10, Color(0.85, 0.95, 0.85))

	# Scroll indicator
	if script_size > 0:
		_panel.draw_string(font, Vector2(x + pw - 60, y + 10), "%d/%d" % [_editor_scroll_offset + 1, script_size], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.4, 0.4, 0.4))


func _get_soft_wrap_lines(text: String, max_w: float, font: Font, font_size: int) -> Array[String]:
	## Split a command into display lines at sub-command boundaries.
	## First line uses max_w, continuation lines use max_w - 8 (indented).
	## Priority order (highest first):
	##   1. Boundary commands: unless, check
	##   2. Label/extract: label:, extract:
	##   3. Comparisons: >, <, =
	##   4. Any space
	## Within each priority, pick the LATEST fitting position (maximize text per line).
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_w:
		return [text]

	# Token groups in priority order — search each group fully before falling to the next
	var token_groups: Array[Array] = [
		[" unless ", " check "],          # 1. Boundary commands
		[" label:", " extract:"],          # 2. Label/extract
		[" > ", " < ", " = "],            # 3. Comparisons
	]
	var lines: Array[String] = []
	var remaining: String = text
	var is_first_line: bool = true

	while not remaining.is_empty():
		var line_w: float = max_w if is_first_line else max_w - 8.0
		if font.get_string_size(remaining, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= line_w:
			lines.append(remaining)
			break

		var best_pos: int = -1

		# Search each priority group — stop at the first group that has a match.
		# For boundary commands (group 0): prefer the EARLIEST match (one clause per line).
		# For lower priority groups: prefer the LATEST match (maximize text per line).
		for gi in range(token_groups.size()):
			var group: Array = token_groups[gi]
			var group_best: int = -1
			for token in group:
				var search_start: int = 0
				while true:
					var pos: int = remaining.find(token, search_start)
					if pos < 0:
						break
					if pos == 0:
						search_start = pos + 1
						continue  # Don't wrap at the very start (empty first segment)
					if font.get_string_size(remaining.substr(0, pos), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= line_w:
						if gi == 0:
							# Boundary commands: take the FIRST match (one clause per line)
							if group_best < 0 or pos < group_best:
								group_best = pos
						else:
							# Lower priority: take the LATEST match (maximize text)
							if pos > group_best:
								group_best = pos
					else:
						break
					search_start = pos + 1
			if group_best > 0:
				best_pos = group_best
				break

		if best_pos > 0:
			lines.append(remaining.substr(0, best_pos))
			remaining = remaining.substr(best_pos)
		else:
			# 4. Last resort — wrap at any space (search from right to left)
			var space_pos: int = -1
			for ci in range(remaining.length() - 1, 0, -1):
				if remaining[ci] == " ":
					if font.get_string_size(remaining.substr(0, ci), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= line_w:
						space_pos = ci
						break
			if space_pos > 0:
				lines.append(remaining.substr(0, space_pos))
				remaining = remaining.substr(space_pos + 1)
			else:
				# Absolute last resort — hard character wrap
				var fit_chars: int = remaining.length()
				while fit_chars > 1:
					fit_chars -= 1
					if font.get_string_size(remaining.substr(0, fit_chars), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= line_w:
						break
				lines.append(remaining.substr(0, fit_chars))
				remaining = remaining.substr(fit_chars)
		is_first_line = false
	return lines


func _get_row_height(te: Node, script_idx: int, text_width: float, font: Font) -> float:
	## Calculate the pixel height of a script row, accounting for soft-wrap.
	var base_h: float = 18.0
	if script_idx >= te._script.size():
		return base_h
	var lines: Array[String] = _get_soft_wrap_lines(te._script[script_idx], text_width, font, 10)
	return base_h * maxf(1, lines.size())


func _test_cmd_color(cmd: String) -> Color:
	## Color-code test commands by category.
	var c := cmd.strip_edges()
	if c.begins_with("#"):                     return Color(0.45, 0.55, 0.45)
	if c.begins_with("debug "):               return Color(0.5, 0.5, 0.8)
	if c.begins_with("wait "):                return Color(0.8, 0.7, 0.3)
	if c.begins_with("check "):               return Color(0.3, 0.85, 0.85)
	if c.begins_with("bleap "):               return Color(0.7, 0.5, 0.9)
	if c.begins_with("spawn "):               return Color(0.4, 0.9, 0.5)
	if c.begins_with("etz "):                 return Color(0.3, 0.9, 0.6)
	if c.begins_with("daz "):                 return Color(0.9, 0.4, 0.4)
	if c.begins_with("standdown") or c.begins_with("clear") or c.begins_with("portal"):
		return Color(0.75, 0.55, 0.35)
	return Color(0.72, 0.72, 0.72)


func _draw_config_section(content_x: float, font: Font, ph: float) -> void:
	## Entity config: search filter, entity list, config sliders.
	var x: float = content_x
	var y: float = 8.0
	var pw: float = _content_width

	_panel.draw_string(font, Vector2(x, y + 14), "Entity Config", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.7, 0.3))
	y += 22

	# -- Search filter field --
	var cfg_filter_bg: Color = Color(0.12, 0.12, 0.16) if _config_filter_focused else Color(0.08, 0.08, 0.12)
	_panel.draw_rect(Rect2(x, y, pw - 16, 20), cfg_filter_bg)
	var cfg_filter_display: String = _config_filter_text
	if _config_filter_focused and int(_cursor_blink * 2) % 2 == 0:
		cfg_filter_display += "_"
	if cfg_filter_display == "" and not _config_filter_focused:
		_panel.draw_string(font, Vector2(x + 4, y + 14), "Filter config...", HORIZONTAL_ALIGNMENT_LEFT, pw - 24, 10, Color(0.4, 0.4, 0.4))
	else:
		_panel.draw_string(font, Vector2(x + 4, y + 14), cfg_filter_display, HORIZONTAL_ALIGNMENT_LEFT, pw - 24, 10, Color(0.8, 0.8, 0.8))
	y += 24

	# -- Entity list (enemies + players + dummies — anything selectable) --
	var all_entities: Array = []
	all_entities.append_array(get_tree().get_nodes_in_group("enemies"))
	all_entities.append_array(get_tree().get_nodes_in_group("players"))
	all_entities.append_array(get_tree().get_nodes_in_group("attack_dummies"))
	# Deduplicate (some may be in multiple groups)
	var seen: Dictionary = {}
	var entities: Array = []
	for e in all_entities:
		if not seen.has(e.get_instance_id()):
			seen[e.get_instance_id()] = true
			entities.append(e)
	_panel.draw_line(Vector2(x, y), Vector2(x + pw - 16, y), Color(0.2, 0.3, 0.4), 1.0)
	y += 2
	_panel.draw_string(font, Vector2(x, y + 12), "Entities (%d)" % entities.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.75, 1.0))
	y += 16

	var entity_row_h: float = 16.0
	var selected_entity: Node2D = _get_selected_entity()
	for ei in range(entities.size()):
		var e: Node2D = entities[ei]
		var is_sel: bool = (e == selected_entity)
		# Entity ID
		var eid: String = ""
		if "entity_id" in e and not str(e.entity_id).is_empty():
			eid = str(e.entity_id)
		else:
			eid = e.name
		# Entity type
		var etype: String = "unknown"
		if e.get_script():
			var script_path: String = e.get_script().resource_path
			var fname: String = script_path.get_file().get_basename()
			etype = fname  # e.g. "quadruped_monster", "skeleton", "gummy_bear"
		if is_sel:
			_panel.draw_rect(Rect2(x, y, pw - 16, entity_row_h - 2), Color(0.15, 0.25, 0.15))
		var id_col := Color(0.5, 1.0, 0.5) if is_sel else Color(0.7, 0.7, 0.7)
		var type_col := Color(0.4, 0.8, 0.4) if is_sel else Color(0.5, 0.5, 0.5)
		var num_col := Color(0.3, 0.9, 1.0) if is_sel else Color(0.4, 0.5, 0.6)
		# 1-indexed number for visual correlation with the in-world indicator
		_panel.draw_string(font, Vector2(x + 2, y + 12), "%d" % (ei + 1), HORIZONTAL_ALIGNMENT_LEFT, 14, 9, num_col)
		_panel.draw_string(font, Vector2(x + 18, y + 12), eid, HORIZONTAL_ALIGNMENT_LEFT, pw * 0.42, 9, id_col)
		_panel.draw_string(font, Vector2(x + pw * 0.48, y + 12), etype, HORIZONTAL_ALIGNMENT_LEFT, pw * 0.48, 8, type_col)
		y += entity_row_h

	if entities.is_empty():
		_panel.draw_string(font, Vector2(x + 6, y + 12), "(no entities in scene)", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.4, 0.4))
		y += entity_row_h

	y += 4
	_panel.draw_line(Vector2(x, y), Vector2(x + pw - 16, y), Color(0.2, 0.3, 0.4), 1.0)
	y += 4

	# -- Config sliders --
	if not selected_entity:
		_panel.draw_string(font, Vector2(x, y + 14), "Click an entity above to configure", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.5, 0.5))
		return

	# Show entity info header
	var has_cfg: bool = selected_entity.has_method("cfg")
	var entity_type_label: String = ""
	if selected_entity.get_script():
		entity_type_label = selected_entity.get_script().resource_path.get_file().get_basename()
	_panel.draw_string(font, Vector2(x, y + 12), entity_type_label, HORIZONTAL_ALIGNMENT_LEFT, pw * 0.5, 9, Color(0.9, 0.7, 0.3))

	# Show basic properties for any entity
	var props_text: String = ""
	if "health" in selected_entity:
		props_text += "HP:%d " % selected_entity.health
	if "creature_scale" in selected_entity:
		props_text += "scale:%.1f " % selected_entity.creature_scale
	if "_chained" in selected_entity and selected_entity._chained:
		props_text += "[chained] "
	if "_state" in selected_entity:
		props_text += "state:%d" % selected_entity._state
	if not props_text.is_empty():
		_panel.draw_string(font, Vector2(x + pw * 0.5, y + 12), props_text, HORIZONTAL_ALIGNMENT_LEFT, pw * 0.48, 8, Color(0.6, 0.6, 0.6))
	y += 16

	# Only show config sliders for entities that have cfg() (monsters)
	if not has_cfg:
		# For non-monster entities, show their exported/public properties
		_draw_entity_properties(x, y, pw, ph, font, selected_entity)
		return

	var monster: Node2D = selected_entity
	# Build sorted config key list (once, or when monster changes)
	if _config_keys.is_empty():
		_rebuild_config_keys(monster)

	# Filter config keys
	var filtered_keys: Array[String] = []
	if _config_filter_text.is_empty():
		filtered_keys.assign(_config_keys)
	else:
		var ft: String = _config_filter_text.to_lower()
		for key in _config_keys:
			if key.begins_with("# ") or ft in key.to_lower():
				filtered_keys.append(key)

	# Draw sliders
	var slider_h: float = 16.0
	var slider_gap: float = 2.0
	var visible_count: int = int((ph - y - 10) / (slider_h + slider_gap))
	var max_scroll: int = maxi(0, filtered_keys.size() - visible_count)
	_config_scroll_offset = clampi(_config_scroll_offset, 0, max_scroll)

	for i in range(_config_scroll_offset, mini(_config_scroll_offset + visible_count, filtered_keys.size())):
		var key: String = filtered_keys[i]

		# Group header
		if key.begins_with("# "):
			_panel.draw_line(Vector2(x, y + 8), Vector2(x + pw - 16, y + 8), Color(0.2, 0.3, 0.4), 1.0)
			_panel.draw_string(font, Vector2(x, y + 14), key.substr(2), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.5, 0.75, 1.0))
			y += slider_h + slider_gap
			continue

		var default_val: float = _get_config_default(monster, key)
		var current_val: float = monster.cfg(key, default_val)
		var is_modified: bool = monster._config_stack.size() > 1 and current_val != default_val

		# Label
		var label_col: Color = Color(1.0, 0.85, 0.3) if is_modified else Color(0.7, 0.7, 0.7)
		_panel.draw_string(font, Vector2(x + 8, y + 11), key, HORIZONTAL_ALIGNMENT_LEFT, pw * 0.42, 8, label_col)

		# Slider track
		var slider_x: float = x + pw * 0.47
		var slider_w: float = pw * 0.35
		_panel.draw_rect(Rect2(slider_x, y + 4, slider_w, 8), Color(0.1, 0.1, 0.15))

		# Slider fill
		var range_info: Vector2 = _get_config_range(key, default_val)
		var t: float = clampf((current_val - range_info.x) / maxf(range_info.y - range_info.x, 0.001), 0.0, 1.0)
		var fill_col: Color = Color(0.3, 0.6, 1.0) if not is_modified else Color(1.0, 0.7, 0.2)
		_panel.draw_rect(Rect2(slider_x, y + 4, slider_w * t, 8), fill_col)

		# Handle
		var handle_x: float = slider_x + slider_w * t
		_panel.draw_rect(Rect2(handle_x - 2, y + 2, 4, 12), Color.WHITE)

		# Value text
		_panel.draw_string(font, Vector2(x + pw * 0.84, y + 11), "%.2f" % current_val, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, label_col)

		y += slider_h + slider_gap

	# Scrollbar
	if filtered_keys.size() > visible_count:
		var pct: float = float(_config_scroll_offset) / float(max_scroll) if max_scroll > 0 else 0.0
		var bar_h: float = maxf(20.0, ph * float(visible_count) / float(filtered_keys.size()))
		var bar_y: float = y + pct * (ph - y - bar_h)
		_panel.draw_rect(Rect2(x + pw - 4, bar_y, 3, bar_h), Color(0.3, 0.3, 0.4, 0.5))


func _get_all_entities() -> Array:
	## Returns a deduplicated list of all entities (enemies + players + dummies).
	var all: Array = []
	all.append_array(get_tree().get_nodes_in_group("enemies"))
	all.append_array(get_tree().get_nodes_in_group("players"))
	all.append_array(get_tree().get_nodes_in_group("attack_dummies"))
	var seen: Dictionary = {}
	var result: Array = []
	for e in all:
		if is_instance_valid(e) and not seen.has(e.get_instance_id()):
			seen[e.get_instance_id()] = true
			result.append(e)
	return result


func _draw_selection_overlay() -> void:
	## Draw selection indicator (pulsing circle + number) on the selected entity.
	## This is world-space — drawn by a Node2D child of the scene.
	if not DebugOverlay.global_enabled:
		return
	var sel: Node2D = _get_selected_entity()
	if not sel:
		return
	if not DebugOverlay.should_draw("state_info/selection_indicator", sel):
		return

	var font: Font = ThemeDB.fallback_font
	var pulse: float = 0.5 + 0.3 * sin(Time.get_ticks_msec() / 200.0)
	var sel_col := Color(0, 0.9, 1.0, pulse)
	var pos: Vector2 = sel.global_position

	# Pulsing selection ring
	_world_overlay.draw_arc(pos, 24.0, 0, TAU, 24, sel_col, 2.0)

	# 1-indexed number
	var entities: Array = _get_all_entities()
	var idx: int = entities.find(sel)
	if idx >= 0:
		_world_overlay.draw_string(font, pos + Vector2(-5, -28), "%d" % (idx + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, sel_col)

	# State info panel — draw entity properties in world space
	if not DebugOverlay.should_draw("state_info/state_text_panel", sel):
		return

	# Position the info panel to the left or right of the entity
	var screen_x: float = pos.x
	var text_x: float = pos.x - 250 if screen_x > 960 else pos.x + 80
	var info_pos := Vector2(text_x, pos.y - 80)

	# Line from panel to entity
	_world_overlay.draw_line(info_pos + Vector2(0, 14), pos, Color(0, 0.9, 1.0, 0.2), 1.5)

	# Background
	_world_overlay.draw_rect(Rect2(info_pos.x - 4, info_pos.y - 4, 200, 100), Color(0.05, 0.05, 0.08, 0.8))

	var dy: float = 0
	var line_h: float = 12.0
	var label_col := Color(0.6, 0.6, 0.6)
	var val_col := Color(0.8, 0.9, 0.8)

	# Entity type
	var etype: String = ""
	if sel.get_script():
		etype = sel.get_script().resource_path.get_file().get_basename()
	_world_overlay.draw_string(font, info_pos + Vector2(0, dy + 10), etype, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.9, 0.7, 0.3))
	dy += line_h

	# Entity ID
	var eid: String = sel.name
	if "entity_id" in sel and not str(sel.entity_id).is_empty():
		eid = str(sel.entity_id)
	_world_overlay.draw_string(font, info_pos + Vector2(0, dy + 10), "id: " + eid, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, val_col)
	dy += line_h

	# Position
	_world_overlay.draw_string(font, info_pos + Vector2(0, dy + 10), "pos: (%.0f, %.0f)" % [pos.x, pos.y], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, val_col)
	dy += line_h

	# Common properties
	if "health" in sel:
		var max_hp: String = "/%d" % sel.max_health if "max_health" in sel else ""
		_world_overlay.draw_string(font, info_pos + Vector2(0, dy + 10), "hp: %d%s" % [sel.health, max_hp], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, val_col)
		dy += line_h
	if "_state" in sel:
		_world_overlay.draw_string(font, info_pos + Vector2(0, dy + 10), "state: %d" % sel._state, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, val_col)
		dy += line_h
	if "velocity" in sel:
		_world_overlay.draw_string(font, info_pos + Vector2(0, dy + 10), "vel: (%.0f, %.0f)" % [sel.velocity.x, sel.velocity.y], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, val_col)
		dy += line_h
	if "creature_scale" in sel:
		_world_overlay.draw_string(font, info_pos + Vector2(0, dy + 10), "scale: %.2f" % sel.creature_scale, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, val_col)
		dy += line_h
	if "_chained" in sel and sel._chained:
		_world_overlay.draw_string(font, info_pos + Vector2(0, dy + 10), "[CHAINED]", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 0.5, 0.2))
		dy += line_h


func _draw_entity_properties(x: float, y: float, pw: float, ph: float, font: Font, entity: Node2D) -> void:
	## Draw readable properties for non-monster entities (bats, skeletons, etc.)
	var prop_h: float = 14.0
	var props: Array[Array] = []  # [[key, value_str], ...]

	# Gather interesting properties from the entity
	for prop in entity.get_property_list():
		var pname: String = prop["name"]
		# Skip internal/private and boring properties
		if pname.begins_with("_") or pname in ["script", "process_mode", "process_priority", "editor_description"]:
			continue
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var val = entity.get(pname)
			if val == null:
				continue
			var val_str: String = str(val)
			if val_str.length() > 40:
				val_str = val_str.substr(0, 37) + "..."
			props.append([pname, val_str])

	if props.is_empty():
		_panel.draw_string(font, Vector2(x + 4, y + 12), "(no configurable properties)", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.4, 0.4))
		return

	var visible_count: int = int((ph - y - 10) / prop_h)
	for i in range(mini(visible_count, props.size())):
		var key: String = props[i][0]
		var val: String = props[i][1]
		_panel.draw_string(font, Vector2(x + 4, y + 10), key, HORIZONTAL_ALIGNMENT_LEFT, pw * 0.45, 8, Color(0.7, 0.7, 0.7))
		_panel.draw_string(font, Vector2(x + pw * 0.48, y + 10), val, HORIZONTAL_ALIGNMENT_LEFT, pw * 0.5, 8, Color(0.5, 0.8, 0.5))
		y += prop_h


func _rebuild_config_keys(_monster: Node2D) -> void:
	## Build grouped list of config keys. Keys are prefixed with group headers
	## (lines starting with "#") for the draw function to render as section dividers.
	_config_keys.clear()
	var groups: Array[Array] = [
		["# Mode", ["peaceful"]],
		["# Physics", ["gravity", "mass"]],
		["# Skeleton", ["spine_seg_len", "neck_len", "leg_upper_len", "leg_lower_len", "leg_foot_len", "tail_seg_len", "jaw_len", "clavicle_len", "hip_bone_len", "limb_flex", "tail_flex"]],
		["# Pose", ["stiffness", "tail_stiffness", "tail_whip_stiffness", "head_track_speed"]],
		["# Movement", ["turn_speed", "accel_rate", "decel_rate", "speed_slow", "speed_medium", "speed_fast", "sprint_speed"]],
		["# Gait", ["gait_stride_rate", "gait_knee_swing", "step_threshold", "step_duration", "step_height", "step_overshoot", "foot_push_force", "foot_grip"]],
		["# Blend", ["landing_recovery_time", "landing_compress", "fall_threshold", "shoulder_z_depth"]],
		["# Combat", ["attack_cooldown", "bite_damage", "bite_range", "bite_windup", "bite_strike", "bite_recover", "swipe_damage", "swipe_coil", "swipe_raise", "swipe_strike", "swipe_recover", "tail_damage", "tail_range", "tail_coil", "tail_whip", "tail_recover", "lunge_damage", "lunge_speed", "lunge_coil", "lunge_launch", "lunge_slide"]],
		["# Leap", ["leap_range", "leap_windup_time", "leap_launch_speed", "leap_cooldown", "leap_slash_damage", "leap_slash_raise", "leap_slash_strike", "leap_slash_pause", "leap_bite_damage", "leap_thrash_count", "leap_strike_reach", "leap_body_radius"]],
		["# Grab", ["grab_range", "grab_duration", "grab_kick_damage", "grab_bite_damage", "grab_eject_speed", "grab_kick_interval"]],
		["# Sprint Slash", ["sprint_slash_damage", "sprint_slash_range", "sprint_slash_interval"]],
		["# Hop Up", ["hop_up_max_height", "hop_up_duration", "hop_up_damage"]],
		["# Health", ["max_health", "head_health", "tail_health", "leg_health"]],
		["# Precog", ["precog_trigger_time", "precog_grid_spacing", "aggro_switch_hits"]],
	]
	for group in groups:
		_config_keys.append(group[0])  # Header
		for key in group[1]:
			_config_keys.append(key)


func _get_config_default(monster: Node2D, key: String) -> float:
	## Get the default value for a config key from the JSON defaults.
	var path: String = "res://data/config/monster_defaults.json"
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file:
			var json := JSON.new()
			if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
				if json.data.has(key):
					return float(json.data[key])
	return 0.0


func _get_config_range(key: String, default_val: float) -> Vector2:
	## Return (min, max) range for a config slider. Uses the monster's
	## CONFIG_BOUNDS if available, otherwise heuristic.
	var monster: Node2D = _get_selected_monster()
	if monster and monster.get("CONFIG_BOUNDS") and monster.CONFIG_BOUNDS.has(key):
		return monster.CONFIG_BOUNDS[key]
	# Fallback heuristic
	if default_val == 0.0:
		return Vector2(0.0, 1.0)
	return Vector2(0.0, default_val * 2.5)
