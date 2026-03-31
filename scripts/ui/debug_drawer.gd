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
enum Section { DEBUG, TEST_RUNNER, CONFIG, LEVEL_EDITOR, BLUEPRINTS }
var _current_section: Section = Section.DEBUG
const ICON_BAR_WIDTH := 36.0
const ICON_SIZE := 20.0
const ICON_PAD := 8.0

# Level editor section state — sub-section framework (same pattern as test runner)
var _le_subsections: Array[Dictionary] = []
var _le_subsections_initialized: bool = false
var _le_sub_resize_idx: int = -1
var _le_sub_resize_start_y: float = 0.0
var _le_sub_resize_start_h: float = 0.0
var _le_sub_resize_next_h: float = 0.0
var _le_grip_last_click_idx: int = -1
var _le_grip_last_click_time: float = 0.0

# Level editor sub-section min heights
const LE_SUB_MIN := {
	"le_level":      30.0,
	"le_modes":      30.0,
	"le_items":      36.0,
	"le_properties": 60.0,
	"le_actions":    36.0,
	"le_save":       SUB_HEADER_H + 3 * 16.0,
}

# Constructs section state
var _ct_subsections: Array[Dictionary] = []
var _ct_subsections_initialized: bool = false
var _ct_sub_resize_idx: int = -1
var _ct_sub_resize_start_y: float = 0.0
var _ct_sub_resize_start_h: float = 0.0
var _ct_sub_resize_next_h: float = 0.0
var _ct_grip_last_click_idx: int = -1
var _ct_grip_last_click_time: float = 0.0
var _ct_hover_type_idx: int = -1
var _ct_hover_instance_idx: int = -1
var _ct_instances_scroll_offset: int = 0
var _ct_selected_type: String = "splays"  # "splays" or "trees"

const CT_SUB_MIN := {
	"ct_types":     30.0,
	"ct_instances": 36.0,
	"ct_editor":    60.0,
}

# Cached level names
var _le_cached_level_names: Array[String] = []
var _le_level_names_dirty: bool = true
var _le_level_scroll_offset: int = 0
var _le_hover_level_idx: int = -1

# Level editor scroll/hover state
var _le_items_scroll_offset: int = 0
var _le_properties_scroll_offset: int = 0
var _le_hover_mode_idx: int = -1
var _le_hover_item_idx: int = -1
var _le_scene_hover_idx: int = -1

# Level editor property edit state
var _le_prop_edit_key: String = ""
var _le_prop_edit_text: String = ""
var _le_prop_edit_cursor: int = 0
var _le_prop_edit_focused: bool = false
var _le_prop_dragging_key: String = ""

# Level editor scene action flash
var _le_scene_flash: String = ""
var _le_scene_flash_timer: float = 0.0

# Level editor mode names & colors
# Index -1 = Gameplay (no editing). Indices 0-5 match level_editor.gd Mode enum.
const LE_MODE_GAMEPLAY := -1
const LE_MODE_DISPLAY_NAMES := ["Gameplay", "Spawn Areas", "Spawn Pos", "Seeds", "Platforms", "Portal", "Migration", "Splays"]
const LE_MODE_DISPLAY_COLORS: Array[Color] = [
	Color(0.5, 0.8, 0.5),   # Gameplay: soft green
	Color(1.0, 0.9, 0.2),   Color(0.2, 0.9, 0.5),   Color(0.3, 0.8, 0.4),
	Color(0.4, 0.6, 1.0),   Color(0.9, 0.3, 0.9),   Color(0.3, 0.5, 1.0),
	Color(0.9, 0.4, 0.2),   # Splays: orange
]
# Map display index → level_editor.gd Mode value (-1 = gameplay/none)
# 0=SPAWN_AREAS, 1=SPAWN_POS, 2=SEEDS, 3=PLATFORMS, 4=PORTAL, 5=MIGRATION, 6=SPLAY
const LE_MODE_MAP := [-1, 0, 1, 2, 3, 4, 5, 6]

# Active display mode index (0=Gameplay, 1+=editor modes)
var _le_active_display_mode: int = 0  # Start in Gameplay

# Always-available actions (shown in every mode)
const LE_ACTIONS_ALWAYS: Array[Dictionary] = [
	{"label": "LEVEL", "cmd": ""},
	{"label": "Clear Entities", "cmd": "clear", "color": Color(1.0, 0.5, 0.3)},
	{"label": "Restart Level", "cmd": "restart_level", "color": Color(1.0, 0.6, 0.2)},
]

# Gameplay-only actions
const LE_ACTIONS_GAMEPLAY: Array[Dictionary] = [
	{"label": "SPAWN", "cmd": ""},
	{"label": "Monster (standdown)", "cmd": "spawn_standdown", "color": Color(0.4, 0.9, 0.5)},
	{"label": "Monster (active)", "cmd": "spawn_active", "color": Color(0.4, 0.9, 0.5)},
	{"label": "Dummy (soccer ball)", "cmd": "spawn_dummy", "color": Color(0.3, 0.8, 1.0)},
	{"label": "Monster Fight!", "cmd": "monster_fight", "color": Color(1.0, 0.6, 0.3)},
	{"label": "GAMEPLAY", "cmd": ""},
	{"label": "Kill All Enemies", "cmd": "kill", "color": Color(1.0, 0.4, 0.4)},
	{"label": "Toggle Territorial", "cmd": "territorial", "color": Color(0.8, 0.6, 0.3)},
	{"label": "Revive All Players", "cmd": "revive", "color": Color(0.3, 0.9, 0.6)},
	{"label": "Enable Player Joins", "cmd": "enable_joins", "color": Color(0.3, 0.8, 0.8)},
]

# Config section state
var _config_scroll_offset: int = 0
var _config_dragging_key: String = ""  # Which config slider is being dragged
var _config_keys: Array[String] = []   # Sorted list of configurable keys
var _config_slider_provider: Variant = null  # Single DictProvider for all slider edits
var _config_slider_data: Dictionary = {}     # The data dict inside the provider
var _config_filter_text: String = ""         # Search filter for config keys
var _config_filter_focused: bool = false     # Whether the config filter field has focus
var _game_config_rects: Dictionary = {}      # Key -> Rect2 for clickable game settings

# Config sub-section framework (same pattern as LE/CT)
var _cfg_subsections: Array[Dictionary] = []
var _cfg_subsections_initialized: bool = false
var _cfg_sub_resize_idx: int = -1
var _cfg_sub_resize_start_y: float = 0.0
var _cfg_sub_resize_start_h: float = 0.0
var _cfg_sub_resize_next_h: float = 0.0
var _cfg_grip_last_click_idx: int = -1
var _cfg_grip_last_click_time: float = 0.0

# Config sub-section scroll/hover state
var _cfg_entities_scroll_offset: int = 0
var _cfg_blueprints_scroll_offset: int = 0
var _cfg_instances_scroll_offset: int = 0
var _cfg_hover_entity_idx: int = -1
var _cfg_hover_blueprint_idx: int = -1
var _cfg_hover_instance_idx: int = -1

# Blueprint filter
var _cfg_bp_filter_text: String = ""
var _cfg_bp_filter_focused: bool = false

# Modifier instance filter
var _cfg_mod_filter_text: String = ""
var _cfg_mod_filter_focused: bool = false

# Selected blueprint for editing
var _cfg_selected_blueprint: String = ""
var _cfg_bp_edit_key: String = ""       # Key being edited in blueprint editor
var _cfg_bp_edit_text: String = ""      # Text being typed
var _cfg_bp_edit_focused: bool = false
var _cfg_bp_dragging_key: String = ""   # Which blueprint slider is being dragged
var _cfg_bp_cached_data: Dictionary = {}  # Cached loaded blueprint data (for live editing)
var _cfg_bp_editor_scroll: int = 0       # Scroll offset in the blueprint editor area

# Cached blueprint names
var _cfg_cached_bp_names: Array[String] = []
var _cfg_bp_names_dirty: bool = true

# Class selection
var _cfg_selected_class: int = -1          # CharacterClass enum value (-1 = none)
var _cfg_class_scroll_offset: int = 0
var _cfg_class_dragging_key: String = ""   # Which class slider is being dragged
var _cfg_class_data: Dictionary = {}       # Cached class default data (for live editing)
var _cfg_class_data_name: String = ""      # Which class the cached data is for

# Stat selection for calculations
var _cfg_selected_stat: String = ""        # Config key selected in Entity Stats
var _cfg_stat_cache: Array = []            # Cached calculation steps for selected stat
var _cfg_stat_cache_dirty: bool = true

const CFG_SUB_MIN := {
	"cfg_settings":    30.0,
	"cfg_classes":     30.0,
	"cfg_class":       36.0,
	"cfg_entities":    36.0,
	"cfg_entity_mods": 30.0,
	"cfg_entity_stats":36.0,
	"cfg_calculations":30.0,
	"cfg_modifiers":   36.0,
	"cfg_modifier":    36.0,
	"cfg_modified_ents":30.0,
}

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
	_load_drawer_state()
	_panel_x = -_panel_width
	_panel = Control.new()
	_panel.name = "DebugDrawerPanel"
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.draw.connect(_draw_panel)
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_panel)
	# Deferred: add world-space overlay to the scene for selection indicators
	call_deferred("_init_world_overlay")


func _load_drawer_state() -> void:
	## Load drawer-level state: active section, panel width.
	var path: String = "user://drawer_state.json"
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return
	var data: Dictionary = json.data
	if data.has("section"):
		_current_section = clampi(int(data["section"]), 0, Section.values().size() - 1) as Section
	if data.has("panel_width"):
		_panel_width = clampf(float(data["panel_width"]), 300.0, 800.0)
		_content_width = _panel_width - ICON_BAR_WIDTH


func _save_drawer_state() -> void:
	## Save drawer-level state.
	var data: Dictionary = {
		"section": int(_current_section),
		"panel_width": _panel_width,
	}
	var file := FileAccess.open("user://drawer_state.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "  "))


func _init_world_overlay() -> void:
	var scene := get_tree().current_scene
	if not scene:
		return
	_world_overlay = Node2D.new()
	_world_overlay.name = "DebugSelectionOverlay"
	_world_overlay.z_index = 4096  # Front-most — debug labels must be on top of everything
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
	var had_saved_layout: bool = FileAccess.file_exists("user://debug_panel_layout.json")
	_load_subsection_layout()
	# Only auto-snap if no saved layout — trust user's saved heights otherwise
	if not had_saved_layout:
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
		if _le_scene_flash_timer > 0:
			_le_scene_flash_timer -= delta
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

		# Forward keyboard to level editor property edit field
		if _current_section == Section.LEVEL_EDITOR and _le_prop_edit_focused:
			_handle_le_prop_edit_key(event)
			get_viewport().set_input_as_handled()
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
		if _cfg_bp_filter_focused or _cfg_mod_filter_focused:
			_handle_cfg_text_input(event)
			get_viewport().set_input_as_handled()
			return

		# Escape closes drawer or unfocuses
		if event.keycode == KEY_ESCAPE:
			if _filter_focused or _id_filter_focused or _config_filter_focused or _cfg_bp_filter_focused or _cfg_mod_filter_focused:
				_filter_focused = false
				_id_filter_focused = false
				_config_filter_focused = false
				_cfg_bp_filter_focused = false
				_cfg_mod_filter_focused = false
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
		if not _cfg_bp_dragging_key.is_empty():
			_cfg_bp_dragging_key = ""
			get_viewport().set_input_as_handled()
			return
		if not _cfg_class_dragging_key.is_empty():
			_cfg_class_dragging_key = ""
			get_viewport().set_input_as_handled()
			return
		if _sub_resize_idx >= 0:
			_handle_sub_resize_release()
			_sub_resize_idx = -1
			_save_subsection_layout()
			get_viewport().set_input_as_handled()
			return
		if _le_sub_resize_idx >= 0:
			_handle_le_sub_resize_release()
			_le_sub_resize_idx = -1
			_save_le_layout()
			get_viewport().set_input_as_handled()
			return
		if _ct_sub_resize_idx >= 0:
			_handle_ct_sub_resize_release()
			_ct_sub_resize_idx = -1
			_save_ct_layout()
			get_viewport().set_input_as_handled()
			return
		if _cfg_sub_resize_idx >= 0:
			_handle_cfg_sub_resize_release()
			get_viewport().set_input_as_handled()
			return
		if not _le_prop_dragging_key.is_empty():
			_le_prop_dragging_key = ""
			get_viewport().set_input_as_handled()
			return
		if not _ct_tree_prop_dragging.is_empty():
			_ct_tree_prop_dragging = ""
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
		elif _current_section == Section.LEVEL_EDITOR:
			_handle_le_click(lx - ICON_BAR_WIDTH - 4, my)
		elif _current_section == Section.BLUEPRINTS:
			_handle_ct_click(lx - ICON_BAR_WIDTH - 4, my)
		else:
			_handle_click(lx - ICON_BAR_WIDTH - 4, my)
		get_viewport().set_input_as_handled()

	# Mouse scroll — route to the correct sub-section when in test runner
	if _active and event is InputEventMouseButton:
		if event.position.x >= _panel_x and event.position.x <= _panel_x + _panel_width:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
				if _current_section == Section.TEST_RUNNER:
					_handle_test_scroll(event.position.y, -3)
				elif _current_section == Section.LEVEL_EDITOR:
					_handle_le_scroll(event.position.y, -3)
				elif _current_section == Section.BLUEPRINTS:
					_handle_ct_scroll(event.position.y, -3)
				elif _current_section == Section.CONFIG:
					_handle_cfg_scroll(event.position.y, -3)
				else:
					_scroll_offset = maxi(0, _scroll_offset - 3)
				get_viewport().set_input_as_handled()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
				if _current_section == Section.TEST_RUNNER:
					_handle_test_scroll(event.position.y, 3)
				elif _current_section == Section.LEVEL_EDITOR:
					_handle_le_scroll(event.position.y, 3)
				elif _current_section == Section.BLUEPRINTS:
					_handle_ct_scroll(event.position.y, 3)
				elif _current_section == Section.CONFIG:
					_handle_cfg_scroll(event.position.y, 3)
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
		elif not _cfg_class_dragging_key.is_empty():
			var cls_lx: float = event.position.x - _panel_x - ICON_BAR_WIDTH - 4
			_cfg_class_drag_at(cls_lx)
			get_viewport().set_input_as_handled()
		elif not _cfg_bp_dragging_key.is_empty():
			var bp_lx: float = event.position.x - _panel_x - ICON_BAR_WIDTH - 4
			_cfg_bp_drag_at(bp_lx)
			get_viewport().set_input_as_handled()
		elif _sub_resize_idx >= 0:
			_handle_sub_resize_drag(event.position.y)
			get_viewport().set_input_as_handled()
		elif _le_sub_resize_idx >= 0:
			_handle_le_sub_resize_drag(event.position.y)
			get_viewport().set_input_as_handled()
		elif _ct_sub_resize_idx >= 0:
			_handle_ct_sub_resize_drag(event.position.y)
			get_viewport().set_input_as_handled()
		elif _cfg_sub_resize_idx >= 0:
			_handle_cfg_sub_resize_drag(event.position.y)
			get_viewport().set_input_as_handled()
		elif not _le_prop_dragging_key.is_empty():
			_handle_le_prop_drag(event.position.x)
			get_viewport().set_input_as_handled()
		elif not _ct_tree_prop_dragging.is_empty():
			_handle_ct_tree_prop_drag(event.position.x)
			get_viewport().set_input_as_handled()
		elif event.position.x >= _panel_x and event.position.x <= _panel_x + _panel_width:
			if _current_section == Section.TEST_RUNNER:
				_handle_test_hover(event.position.y)
			elif _current_section == Section.LEVEL_EDITOR:
				_handle_le_hover(event.position.y)
			elif _current_section == Section.BLUEPRINTS:
				_handle_ct_hover(event.position.y)
			elif _current_section == Section.CONFIG:
				_handle_cfg_hover(event.position.y)
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
	## Fit the game into the remaining visible area: right of drawer, above console.
	## Both the drawer and console contribute to the available rectangle.
	var vp: Viewport = get_viewport()
	if not vp:
		return

	var vp_size: Vector2 = vp.get_visible_rect().size
	var visible_panel: float = maxf(0.0, _panel_x + _panel_width)

	# Check if the console is eating space from the bottom
	var console: Node = get_node_or_null("/root/GameConsole")
	var console_h: float = 0.0
	if console and console.is_open() and "_panel_y" in console:
		console_h = maxf(0.0, vp_size.y - console._panel_y)

	var game_width: float = vp_size.x - visible_panel
	var game_height: float = vp_size.y - console_h

	if not _active and visible_panel < 2.0 and console_h < 2.0:
		# Nothing open — reset to identity transform
		vp.canvas_transform = Transform2D.IDENTITY
		return

	if game_width < 100 or game_height < 100:
		return

	var scale_x: float = game_width / vp_size.x
	var scale_y: float = game_height / vp_size.y
	var target_transform := Transform2D()
	target_transform = target_transform.scaled(Vector2(scale_x, scale_y))
	target_transform.origin = Vector2(visible_panel, 0)

	var current: Transform2D = vp.canvas_transform
	vp.canvas_transform = current.interpolate_with(target_transform, 0.15)


func _handle_icon_click(my: float) -> void:
	## Click on the icon bar — switch section or collapse.
	var icon_sections: Array = [Section.DEBUG, Section.TEST_RUNNER, Section.CONFIG, Section.LEVEL_EDITOR, Section.BLUEPRINTS]
	var icon_btn_size: float = ICON_BAR_WIDTH - 4
	for i in range(icon_sections.size()):
		var iy: float = 8.0 + i * (icon_btn_size + 4)
		var ih: float = icon_btn_size
		if my >= iy and my < iy + ih:
			if _current_section == icon_sections[i]:
				# Clicking active icon could collapse, but for now just keep it
				pass
			else:
				_current_section = icon_sections[i]
				_config_keys.clear()  # Force rebuild when switching to config
				_cached_lists_dirty = true  # Force rebuild test/suite lists
				_save_drawer_state()
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
	## Route click to the new config sub-section framework.
	_handle_cfg_click(lx, my)


func _handle_config_drag(mx: float) -> void:
	## Drag a config slider.
	var entity: Node2D = _get_selected_entity()
	if not entity or _config_dragging_key.is_empty():
		return
	# Entity must have push_config to accept slider changes
	if not entity.has_method("push_config"):
		return
	var content_x: float = _panel_x + ICON_BAR_WIDTH + 4
	var lx: float = mx - content_x
	_handle_config_drag_at(lx, entity)


func _handle_config_drag_at(lx: float, monster: Node2D) -> void:
	## Set config value based on slider position. Uses a single persistent
	## DictProvider for all slider edits — updates in place, never pushes new ones.
	## Shackle keys (shackle:*) route to the shackle config stack instead.
	var pw: float = _content_width
	var slider_x: float = pw * 0.47
	var slider_w: float = pw * 0.35
	var t: float = clampf((lx - slider_x) / slider_w, 0.0, 1.0)

	var key: String = _config_dragging_key

	# Shackle keys route to shackle config stack
	if key.begins_with("shackle:"):
		var skey: String = key.substr(8)
		var default_val: float = _get_shackle_config_default(skey)
		var range_info: Vector2 = _get_config_range(key, default_val)
		var new_val: float = lerpf(range_info.x, range_info.y, t)
		# Update the shackle base config directly
		if monster.has_method("shackle_cfg") and "_exec_shackle_config_stack" in monster:
			if monster._exec_shackle_base_config and "_data" in monster._exec_shackle_base_config:
				monster._exec_shackle_base_config._data[skey] = new_val
		_panel.queue_redraw()
		return

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
	_panel.draw_rect(Rect2(_panel_x, 0, ICON_BAR_WIDTH, ph), Color(0.04, 0.04, 0.07, 0.98))
	_panel.draw_line(Vector2(_panel_x + ICON_BAR_WIDTH, 0), Vector2(_panel_x + ICON_BAR_WIDTH, ph), Color(0.15, 0.15, 0.2), 1.0)

	var icon_sections: Array = [
		{"section": Section.DEBUG, "label": "D"},
		{"section": Section.TEST_RUNNER, "label": "T"},
		{"section": Section.CONFIG, "label": "C"},
		{"section": Section.LEVEL_EDITOR, "label": "E"},
		{"section": Section.BLUEPRINTS, "label": "B"},
	]
	var icon_btn_size: float = ICON_BAR_WIDTH - 4  # Fit within bar with 2px margin each side
	var icon_x: float = _panel_x + 2
	for i in range(icon_sections.size()):
		var iy: float = 8.0 + i * (icon_btn_size + 4)
		var is_active: bool = _current_section == icon_sections[i]["section"]
		var bg_col: Color = Color(0.15, 0.25, 0.4, 0.8) if is_active else Color(0.08, 0.08, 0.12, 0.6)
		_panel.draw_rect(Rect2(icon_x, iy, icon_btn_size, icon_btn_size), bg_col, true)
		if is_active:
			_panel.draw_rect(Rect2(icon_x, iy, 2, icon_btn_size), Color(0.3, 0.7, 1.0), true)
		var icon_center := Vector2(icon_x + icon_btn_size * 0.5, iy + icon_btn_size * 0.5)
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
		Section.LEVEL_EDITOR:
			_draw_level_editor_section(content_x, font, ph)
		Section.BLUEPRINTS:
			_draw_blueprints_section(content_x, font, ph)


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
		Section.LEVEL_EDITOR:
			# Pencil icon — diagonal line with nib
			var tip: Vector2 = center + Vector2(-r, r)
			var end: Vector2 = center + Vector2(r, -r)
			_panel.draw_line(tip, end, col, 2.0)
			_panel.draw_line(tip, tip + Vector2(3, 0), col, 1.5)
			_panel.draw_line(tip, tip + Vector2(0, -3), col, 1.5)
		Section.BLUEPRINTS:
			# Blueprint icon — page with corner fold
			var bx: float = center.x - r * 0.6
			var by: float = center.y - r * 0.8
			var bw: float = r * 1.2
			var bh: float = r * 1.6
			_panel.draw_rect(Rect2(bx, by, bw, bh), col, false, 1.5)
			# Corner fold
			_panel.draw_line(Vector2(bx + bw - r * 0.4, by), Vector2(bx + bw - r * 0.4, by + r * 0.4), col, 1.0)
			_panel.draw_line(Vector2(bx + bw - r * 0.4, by + r * 0.4), Vector2(bx + bw, by + r * 0.4), col, 1.0)
			# Horizontal lines (content)
			for li in range(3):
				var ly: float = by + r * 0.6 + li * r * 0.35
				_panel.draw_line(Vector2(bx + 2, ly), Vector2(bx + bw - 3, ly), col * Color(1, 1, 1, 0.5), 1.0)


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

	_scale_area_y = -1  # Disabled — scale slider removed

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
			_panel.draw_rect(Rect2(x, ry, pw - 8, ROW_HEIGHT), Color(0.15, 0.15, 0.2))

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

	# Group-level aggregate TPS — visual and textual separate
	var group_v_tps: int = 0
	var group_t_tps: int = 0
	for path in aspects:
		var ainfo: DebugOverlay.AspectInfo = DebugOverlay.get_aspect(path)
		if ainfo:
			group_v_tps += ainfo._visual_tps
			group_t_tps += ainfo._textual_tps
	if group_v_tps > 0:
		_panel.draw_string(font, Vector2(v_col_x - 36, ry + 13), "%d" % group_v_tps, HORIZONTAL_ALIGNMENT_RIGHT, 30, 7, _tps_color(group_v_tps))
	if group_t_tps > 0:
		_panel.draw_string(font, Vector2(t_col_x - 36, ry + 13), "%d" % group_t_tps, HORIZONTAL_ALIGNMENT_RIGHT, 30, 7, _tps_color(group_t_tps))

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

	_panel.draw_string(font, Vector2(x + INDENT + 6, ry + 13), label, HORIZONTAL_ALIGNMENT_LEFT, int(v_col_x - x - INDENT - 70), 9, label_col)

	# TPS metrics — visual and textual shown separately, aligned with V/T columns
	var v_tps: int = info._visual_tps
	var t_tps: int = info._textual_tps
	if v_tps > 0:
		var v_tps_col: Color = _tps_color(v_tps)
		_panel.draw_string(font, Vector2(v_col_x - 36, ry + 13), "%d" % v_tps, HORIZONTAL_ALIGNMENT_RIGHT, 30, 7, v_tps_col)
	if t_tps > 0:
		var t_tps_col: Color = _tps_color(t_tps)
		_panel.draw_string(font, Vector2(t_col_x - 36, ry + 13), "%d" % t_tps, HORIZONTAL_ALIGNMENT_RIGHT, 30, 7, t_tps_col)

	# Visual checkbox
	_draw_checkbox(v_col_x - 4, ry + 2, visual_on)
	# If another observer has visual, show border highlight
	if actual_vis and not visual_on:
		_panel.draw_rect(Rect2(v_col_x - 4, ry + 2, CHECKBOX_SIZE, CHECKBOX_SIZE), Color(0.3, 0.6, 1.0, 0.5), false, 1.0)

	# Textual mode indicator
	_draw_text_mode_indicator(t_col_x - 4, ry + 2, textual, font)
	if actual_txt != DebugOverlay.TextMode.NONE and textual == DebugOverlay.TextMode.NONE:
		_panel.draw_rect(Rect2(t_col_x - 4, ry + 2, CHECKBOX_SIZE, CHECKBOX_SIZE), Color(0.3, 0.6, 1.0, 0.5), false, 1.0)


func _tps_color(tps: int) -> Color:
	## Color for TPS counter: green→orange→red based on tick rate.
	if tps > 120:
		return Color(1.0, 0.3, 0.2, 0.9)   # Hot
	elif tps > 30:
		return Color(1.0, 0.7, 0.2, 0.8)   # Warm
	else:
		return Color(0.4, 0.7, 0.4, 0.6)   # Cool


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
		_draw_test_sub_header(x, y, pw, font, sub)

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


func _draw_test_sub_header(x: float, y: float, pw: float, font: Font, sub: Dictionary) -> void:
	## Draw test runner sub-section header — has extra context (mode, save, deletes).
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
				var is_modified: bool = te.has_method("is_modified_from_disk") and te.is_modified_from_disk()
				if is_modified:
					# Show modified indicator + save button
					ctx_text += " ●"
					ctx_col = Color(1.0, 0.8, 0.3)  # Yellow-orange to indicate unsaved changes
					var save_x: float = x + 78 + font.get_string_size(ctx_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 6
					_panel.draw_string(font, Vector2(save_x, y + 14), "💾", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 0.9, 0.3, 1.0))
				elif te._dirty:
					# Dirty but not different from disk (e.g., editing in progress)
					ctx_text += " ·"
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
		elif rcon and rcon._test_runner:
			var line_state: String = ""
			if rcon._test_runner._line_states.has(si):
				line_state = rcon._test_runner._line_states[si]
			match line_state:
				"pending":
					_panel.draw_string(font, Vector2(x + 24, ry + 14), "○", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.5, 0.5))
				"running":
					_panel.draw_string(font, Vector2(x + 24, ry + 14), "●", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.3, 1.0, 0.3))
					_panel.draw_rect(Rect2(x, ry, pw - 8, this_row_h), Color(0.1, 0.25, 0.1, 0.3))
				"looping":
					_panel.draw_string(font, Vector2(x + 24, ry + 14), "↻", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.7, 0.2))
					_panel.draw_rect(Rect2(x, ry, pw - 8, this_row_h), Color(0.25, 0.18, 0.05, 0.3))
					# Show loop variable value on the right
					var while_cmd: String = str(te._script[si]).strip_edges()
					if while_cmd.begins_with("while "):
						var wvar: String = while_cmd.substr(6).strip_edges()
						if wvar.begins_with("{") and wvar.ends_with("}"):
							wvar = wvar.substr(1, wvar.length() - 2)
						var wval: String = rcon._test_runner._test_vars.get(wvar, "?")
						_panel.draw_string(font, Vector2(x + pw - 80, ry + 14), "%s=%s" % [wvar, wval], HORIZONTAL_ALIGNMENT_RIGHT, 68, 9, Color(1.0, 0.7, 0.2))
				"verifying":
					var pulse: float = 0.5 + 0.3 * sin(Time.get_ticks_msec() / 300.0)
					_panel.draw_string(font, Vector2(x + 24, ry + 14), "◈", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.3, 0.8, 1.0, pulse))
					_panel.draw_rect(Rect2(x, ry, pw - 8, this_row_h), Color(0.05, 0.15, 0.25, 0.3))
				"failed":
					_panel.draw_string(font, Vector2(x + 24, ry + 14), "✗", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.2, 0.2))
					_panel.draw_rect(Rect2(x, ry, pw - 8, this_row_h), Color(0.3, 0.05, 0.05, 0.3))
				"complete":
					_panel.draw_string(font, Vector2(x + 24, ry + 14), "✓", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.7, 0.5))
					# Show final loop variable value for completed while lines
					var done_cmd: String = str(te._script[si]).strip_edges()
					if done_cmd.begins_with("while "):
						var dvar: String = done_cmd.substr(6).strip_edges()
						if dvar.begins_with("{") and dvar.ends_with("}"):
							dvar = dvar.substr(1, dvar.length() - 2)
						var dval: String = rcon._test_runner._test_vars.get(dvar, "0")
						_panel.draw_string(font, Vector2(x + pw - 80, ry + 14), "%s=%s" % [dvar, dval], HORIZONTAL_ALIGNMENT_RIGHT, 68, 9, Color(0.5, 0.7, 0.5))

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
	## Config section with sub-sections: Game Settings, Entities, Blueprints, Instances.
	if not _cfg_subsections_initialized:
		_init_cfg_subsections()

	var x: float = content_x
	var pw: float = _content_width
	var y: float = 0.0

	for si in range(_cfg_subsections.size()):
		var sub: Dictionary = _cfg_subsections[si]
		if y > ph:
			break

		_draw_cfg_sub_header(x, y, pw, font, sub)

		if sub["collapsed"]:
			y += SUB_HEADER_H
			continue

		var body_y: float = y + SUB_HEADER_H
		var body_h: float
		if sub["id"] == "cfg_modified_ents":
			# Last section fills remaining space
			body_h = maxf(CFG_SUB_MIN["cfg_modified_ents"] - SUB_HEADER_H, ph - body_y)
		else:
			body_h = sub["height"] - SUB_HEADER_H

		if body_h > 0:
			match sub["id"]:
				"cfg_settings":    _draw_cfg_sub_settings(x, body_y, pw, body_h, font)
				"cfg_classes":     _draw_cfg_sub_classes(x, body_y, pw, body_h, font)
				"cfg_class":       _draw_cfg_sub_class(x, body_y, pw, body_h, font)
				"cfg_entities":    _draw_cfg_sub_entities(x, body_y, pw, body_h, font)
				"cfg_entity_mods": _draw_cfg_sub_entity_mods(x, body_y, pw, body_h, font)
				"cfg_entity_stats":_draw_cfg_sub_entity_stats(x, body_y, pw, body_h, font)
				"cfg_calculations":_draw_cfg_sub_calculations(x, body_y, pw, body_h, font)
				"cfg_modifiers":   _draw_cfg_sub_blueprints(x, body_y, pw, body_h, font)
				"cfg_modifier":    _draw_cfg_sub_modifier(x, body_y, pw, body_h, font)
				"cfg_modified_ents":_draw_cfg_sub_modified_ents(x, body_y, pw, body_h, font)

		# Snap indicator during resize
		if _cfg_sub_resize_idx == si and sub["id"] != "cfg_modified_ents":
			var snap_h: float = _get_cfg_preferred_height(sub["id"])
			var snap_y: float = y + snap_h
			var near_snap: bool = absf(sub["height"] - snap_h) < SUB_SNAP_DISTANCE
			var snap_col := Color(0.4, 0.7, 1.0, 0.6) if near_snap else Color(0.4, 0.7, 1.0, 0.25)
			var dx: float = 0.0
			while dx < pw - 16:
				_panel.draw_line(Vector2(x + dx, snap_y), Vector2(x + minf(dx + 6.0, pw - 16), snap_y), snap_col, 1.0)
				dx += 10.0
			if near_snap:
				_panel.draw_string(font, Vector2(x + pw - 40, snap_y - 3), "snap", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, snap_col)

		if sub["id"] == "cfg_modified_ents":
			y += body_h + SUB_HEADER_H
		else:
			y += sub["height"]

		if sub["id"] != "cfg_modified_ents":
			_panel.draw_line(Vector2(x, y - 1), Vector2(x + pw - 8, y - 1), Color(0.15, 0.2, 0.3, 0.4), 1.0)


func _get_all_entities() -> Array:
	## Returns a deduplicated list of all entities (enemies + players + dummies + entities).
	var all: Array = []
	all.append_array(get_tree().get_nodes_in_group("enemies"))
	all.append_array(get_tree().get_nodes_in_group("players"))
	all.append_array(get_tree().get_nodes_in_group("attack_dummies"))
	all.append_array(get_tree().get_nodes_in_group("entities"))
	var seen: Dictionary = {}
	var result: Array = []
	for e in all:
		if is_instance_valid(e) and not seen.has(e.get_instance_id()):
			seen[e.get_instance_id()] = true
			result.append(e)
	return result


func _draw_debug_label(pos: Vector2, text: String, font_size: int, color: Color, font: Font = ThemeDB.fallback_font) -> void:
	## Draw a debug label with 75% grey background. All debug world-space text uses this.
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pad := Vector2(3, 2)
	var bg_rect := Rect2(pos.x - pad.x, pos.y - text_size.y, text_size.x + pad.x * 2, text_size.y + pad.y * 2)
	_world_overlay.draw_rect(bg_rect, Color(0.15, 0.15, 0.15, 0.75))
	_world_overlay.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_selection_overlay() -> void:
	## Draw selection indicator, verify monitors, etc.
	## This is world-space — drawn by a Node2D child of the scene.
	if not DebugOverlay.global_enabled:
		return
	_draw_verify_monitors()

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
		_draw_debug_label(pos + Vector2(-5, -28), "%d" % (idx + 1), 12, sel_col, font)

	# State info panel — draw entity properties in world space
	if not DebugOverlay.should_draw("state_info/state_text_panel", sel):
		return

	# Position the info panel to the left or right of the entity
	var screen_x: float = pos.x
	var text_x: float = pos.x - 250 if screen_x > 960 else pos.x + 80
	var info_pos := Vector2(text_x, pos.y - 80)

	# Line from panel to entity
	_world_overlay.draw_line(info_pos + Vector2(0, 14), pos, Color(0, 0.9, 1.0, 0.2), 1.5)

	var dy: float = 0
	var line_h: float = 12.0
	var val_col := Color(0.8, 0.9, 0.8)

	# Entity type
	var etype: String = ""
	if sel.get_script():
		etype = sel.get_script().resource_path.get_file().get_basename()
	_draw_debug_label(info_pos + Vector2(0, dy + 10), etype, 10, Color(0.9, 0.7, 0.3), font)
	dy += line_h

	# Entity ID
	var eid: String = sel.name
	if "entity_id" in sel and not str(sel.entity_id).is_empty():
		eid = str(sel.entity_id)
	_draw_debug_label(info_pos + Vector2(0, dy + 10), "id: " + eid, 9, val_col, font)
	dy += line_h

	# Position
	_draw_debug_label(info_pos + Vector2(0, dy + 10), "pos: (%.0f, %.0f)" % [pos.x, pos.y], 9, val_col, font)
	dy += line_h

	# Common properties
	if "health" in sel:
		var max_hp: String = "/%d" % sel.max_health if "max_health" in sel else ""
		_draw_debug_label(info_pos + Vector2(0, dy + 10), "hp: %d%s" % [sel.health, max_hp], 9, val_col, font)
		dy += line_h
	if "_state" in sel:
		_draw_debug_label(info_pos + Vector2(0, dy + 10), "state: %d" % sel._state, 9, val_col, font)
		dy += line_h
	if "velocity" in sel:
		_draw_debug_label(info_pos + Vector2(0, dy + 10), "vel: (%.0f, %.0f)" % [sel.velocity.x, sel.velocity.y], 9, val_col, font)
		dy += line_h
	if "creature_scale" in sel:
		_draw_debug_label(info_pos + Vector2(0, dy + 10), "scale: %.2f" % sel.creature_scale, 9, val_col, font)
		dy += line_h
	if "_chained" in sel and sel._chained:
		_draw_debug_label(info_pos + Vector2(0, dy + 10), "[CHAINED]", 9, Color(1.0, 0.5, 0.2), font)
		dy += line_h


func _draw_verify_monitors() -> void:
	## Draw verify monitor boundaries in world space — always visible when active.
	## 4-zone ring system:
	##   Zone 1 (inner): transparent→green diagonal stripes, fading in from 80% to boundary
	##   Zone 2: solid green ring at the boundary
	##   Zone 3: solid red ring just outside the boundary
	##   Zone 4 (outer): red horizontal stripes fading out
	if not _world_overlay:
		return
	var rcon: Node = get_node_or_null("/root/Rcon")
	if not rcon or not rcon._test_runner:
		return
	var monitors: Array = rcon._test_runner.get_all_verify_monitors()
	var font: Font = ThemeDB.fallback_font
	for monitor in monitors:
		var state: String = monitor.get("state", "")
		if state != "active" and state != "failed":
			continue
		var boundary: Dictionary = monitor.get("boundary", {})

		match boundary.get("type", ""):
			"circle":
				var center: Vector2 = rcon._test_runner._resolve_boundary_center(boundary)
				var radius: float = boundary.get("radius", 100.0)
				_draw_verify_circle(center, radius, state == "active")
				# Label
				var label_col: Color = Color(0.3, 1.0, 0.4, 0.9) if state == "active" else Color(1.0, 0.3, 0.2, 0.9)
				_draw_debug_label(center + Vector2(radius + 10, -4),
					"verify[%d] r=%.0f" % [monitor["id"], radius], 9, label_col, font)
				# Line from center to monitored entity + distance label
				var entities: Array = rcon._test_runner._resolve_entity_selector(monitor.get("selector", {}))
				for entity in entities:
					if is_instance_valid(entity):
						var dist: float = entity.global_position.distance_to(center)
						var line_col: Color = Color(0.2, 0.9, 0.3, 0.3) if dist <= radius else Color(1.0, 0.2, 0.1, 0.6)
						_world_overlay.draw_line(center, entity.global_position, line_col, 1.5)
						_draw_debug_label(entity.global_position + Vector2(10, -14),
							"%.0f/%.0f" % [dist, radius], 9, label_col, font)

			"rect":
				var bmin: Vector2 = boundary.get("min", Vector2.ZERO)
				var bmax: Vector2 = boundary.get("max", Vector2(1920, 1080))
				var rect_col: Color = Color(0.2, 0.9, 0.3, 0.3) if state == "active" else Color(1.0, 0.2, 0.1, 0.5)
				_world_overlay.draw_rect(Rect2(bmin, bmax - bmin), rect_col, false, 2.0)
				var rect_label_col: Color = Color(0.3, 1.0, 0.4, 0.9) if state == "active" else Color(1.0, 0.3, 0.2, 0.9)
				_draw_debug_label(bmin + Vector2(4, -4),
					"verify[%d]" % monitor["id"], 9, rect_label_col, font)


func _draw_verify_circle(center: Vector2, radius: float, is_ok: bool) -> void:
	## Draw the 4-zone verify circle boundary with candy-stripe fill.
	## Zone 1: inner green 45° candy stripes, fading in from 80% to 100% radius
	## Zone 2: solid green ring at boundary
	## Zone 3: solid red ring just outside boundary
	## Zone 4: outer red 45° candy stripes (same direction), fading out to 130% radius
	##
	## Stripes are true 45° lines in world-space, clipped to annular regions.
	var segments: int = 64
	var stripe_spacing: float = 16.0  # Distance between stripe centers (perpendicular)

	# Determine saturation phase:
	#   Running:  both zones desaturated
	#   Passed:   green hyper-saturated, red fully grey
	#   Failed:   red hyper-saturated + pulsing, green fully grey
	var test_runner: Node = null
	var rcon_ref: Node = get_node_or_null("/root/Rcon")
	if rcon_ref and rcon_ref._test_runner:
		test_runner = rcon_ref._test_runner
	var test_done: bool = test_runner and test_runner._test_state in ["COMPLETE", "FINALIZED"]

	var green_sat: float = 0.3   # 0 = full grey, 1 = hyper-saturated
	var red_sat: float = 0.3
	if test_done:
		if is_ok:
			green_sat = 1.0  # Winner: vivid green
			red_sat = 0.0    # Loser: full grey
		else:
			green_sat = 0.0  # Loser: full grey
			red_sat = 1.0    # Winner: vivid red

	# Green base: grey at sat=0, desaturated at 0.3, vivid at 1.0
	var grey := 0.18
	var green_base := Color(
		lerpf(grey, 0.05, green_sat),
		lerpf(grey, 0.6, green_sat),
		lerpf(grey, 0.05, green_sat))
	# Red base
	var red_base := Color(
		lerpf(grey, 0.7, red_sat),
		lerpf(grey, 0.04, red_sat),
		lerpf(grey, 0.02, red_sat))
	# Ring colors
	var green_ring := Color(
		lerpf(grey, 0.1, green_sat),
		lerpf(grey, 0.9, green_sat),
		lerpf(grey, 0.15, green_sat),
		lerpf(0.25, 0.7, green_sat))
	var red_ring := Color(
		lerpf(grey, 1.0, red_sat),
		lerpf(grey, 0.1, red_sat),
		lerpf(grey, 0.05, red_sat),
		lerpf(0.25, 0.7, red_sat))

	# If test failed, pulse the red zone
	if test_done and not is_ok:
		var pulse: float = 0.7 + 0.3 * sin(Time.get_ticks_msec() / 150.0)
		red_ring.a = pulse
		red_base = Color(0.9, 0.05, 0.02)

	# Zone 1: Inner green stripes (80% → 100% radius)
	_draw_candy_stripe_annulus(center, radius * 0.8, radius,
		green_base, stripe_spacing, true)

	# Zone 2: Solid green ring at the boundary
	_draw_circle_ring(center, radius, green_ring, 3.0, segments)

	# Zone 3: Solid red ring just outside the boundary
	var red_r: float = radius + 4.0
	_draw_circle_ring(center, red_r, red_ring, 3.0, segments)

	# Zone 4: Outer red stripes (100%+6 → 130% radius)
	_draw_candy_stripe_annulus(center, radius + 6.0, radius * 1.3,
		red_base, stripe_spacing, false)


func _draw_circle_ring(center: Vector2, radius: float, color: Color, width: float, segments: int) -> void:
	## Draw a solid circle ring.
	for i in range(segments):
		var a1: float = float(i) / float(segments) * TAU
		var a2: float = float(i + 1) / float(segments) * TAU
		_world_overlay.draw_line(
			center + Vector2(cos(a1), sin(a1)) * radius,
			center + Vector2(cos(a2), sin(a2)) * radius,
			color, width)


func _draw_candy_stripe_annulus(center: Vector2, r_min: float, r_max: float,
		base_color: Color, spacing: float, fade_inward: bool) -> void:
	## Draw 45° candy stripes clipped to an annular region (between r_min and r_max).
	## Each stripe is a true diagonal line, clipped to the two circles.
	## fade_inward=true: alpha 0 at r_min, 0.5 at r_max (inner zone)
	## fade_inward=false: alpha 0.4 at r_min, 0 at r_max (outer zone)
	##
	## Math: a 45° line has the form x + y = k (constant).
	## For each stripe, k is spaced by `spacing`. We clip each line to the annulus
	## by finding intersections with circles r_min and r_max.

	# Stripe lines: x + y = k. Range of k that intersects the outer circle:
	# |k| <= r_max * sqrt(2)  (the 45° line tangent to the circle)
	var k_extent: float = r_max * 1.415  # sqrt(2) ≈ 1.414
	# Quantize k to stripe spacing grid (world-aligned)
	var k_base: float = center.x + center.y
	var k_start: float = k_base - k_extent
	var k_end: float = k_base + k_extent
	# Snap to grid
	k_start = floor(k_start / spacing) * spacing
	var stripe_width: float = spacing * 0.4  # Stripe is 40% of spacing, gap is 60%

	var sub_len: float = 8.0  # Length of each sub-segment for radial alpha gradient
	var k: float = k_start
	while k <= k_end:
		var k_local: float = k - k_base
		# Clip 45° line (lx + ly = k_local) to outer circle r_max
		var disc_outer: float = 2.0 * r_max * r_max - k_local * k_local
		if disc_outer < 0:
			k += spacing
			continue
		var sqrt_outer: float = sqrt(disc_outer)
		var lx1_outer: float = (k_local - sqrt_outer) / 2.0
		var lx2_outer: float = (k_local + sqrt_outer) / 2.0

		# Clip to inner circle r_min
		var disc_inner: float = 2.0 * r_min * r_min - k_local * k_local
		# Collect drawable spans: segments of the line that are inside the annulus
		var spans: Array = []  # [[lx_start, lx_end], ...]
		if disc_inner <= 0:
			spans.append([lx1_outer, lx2_outer])
		else:
			var sqrt_inner: float = sqrt(disc_inner)
			var lx1_inner: float = (k_local - sqrt_inner) / 2.0
			var lx2_inner: float = (k_local + sqrt_inner) / 2.0
			if lx1_outer < lx1_inner - 1.0:
				spans.append([lx1_outer, lx1_inner])
			if lx2_inner < lx2_outer - 1.0:
				spans.append([lx2_inner, lx2_outer])

		# Draw each span as sub-segments with per-point radial alpha
		for span in spans:
			var sx: float = span[0]
			var sx_end: float = span[1]
			while sx < sx_end:
				var sx_next: float = minf(sx + sub_len, sx_end)
				var mid_lx: float = (sx + sx_next) * 0.5
				var mid_ly: float = k_local - mid_lx
				var dist: float = sqrt(mid_lx * mid_lx + mid_ly * mid_ly)
				var alpha: float = _annulus_alpha(dist, r_min, r_max, fade_inward)
				if alpha > 0.005:
					var p1 := center + Vector2(sx, k_local - sx)
					var p2 := center + Vector2(sx_next, k_local - sx_next)
					_world_overlay.draw_line(p1, p2,
						Color(base_color.r, base_color.g, base_color.b, alpha), stripe_width)
				sx = sx_next
		k += spacing


func _annulus_alpha(dist: float, r_min: float, r_max: float, fade_inward: bool) -> float:
	## Compute alpha for a point at `dist` from center within an annulus.
	## fade_inward=true: 0 at r_min → 0.5 at r_max (inner green zone)
	## fade_inward=false: 0.4 at r_min → 0 at r_max (outer red zone)
	var t: float = clampf((dist - r_min) / maxf(r_max - r_min, 1.0), 0.0, 1.0)
	if fade_inward:
		return t * 0.5
	else:
		return 0.4 * (1.0 - t)


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


func _rebuild_config_keys(entity: Node2D) -> void:
	## Build grouped list of config keys. Keys are prefixed with group headers
	## (lines starting with "#") for the draw function to render as section dividers.
	## Detects whether entity is a monster or player and builds appropriate keys.
	_config_keys.clear()

	# Detect entity type by script path
	var is_player: bool = false
	if entity.get_script():
		var script_path: String = entity.get_script().resource_path
		is_player = script_path.ends_with("player_side.gd")

	var groups: Array[Array] = []
	if is_player:
		groups = _build_player_config_groups(entity)
	else:
		groups = [
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


func _build_player_config_groups(entity: Node2D) -> Array[Array]:
	## Build config key groups for a player character.
	## Shows shared keys plus class-specific keys.
	var groups: Array[Array] = [
		["# Physics", ["gravity", "jump_velocity", "speed"]],
		["# Combat", ["attack_cooldown", "special_cooldown", "attack_damage_mult", "special_damage_mult", "charge_damage_mult", "knockback_mult"]],
		["# Health", ["max_health", "max_mana", "mana_regen"]],
	]

	# Class-specific config groups
	var char_class = entity.get("character_class")
	if char_class == PlayerManager.CharacterClass.MELEE:
		groups.append(["# Melee", ["melee_combo_window", "melee_enrage_duration", "melee_enrage_cooldown"]])
	elif char_class == PlayerManager.CharacterClass.ROGUE:
		groups.append(["# Rogue", ["rogue_stealth_duration", "rogue_stealth_cooldown", "rogue_stealth_damage_mult"]])
	elif char_class == PlayerManager.CharacterClass.RANGED:
		groups.append(["# Ranger", ["ranger_max_arrows", "ranger_reload_time"]])
	elif char_class == PlayerManager.CharacterClass.EXECUTIONER:
		groups.append(["# Executioner Ball", ["exec_ball_damage", "exec_ball_stun_duration", "exec_ball_gravity", "exec_ball_throw_speed", "exec_ball_max_throw_speed", "exec_ball_mass", "exec_ball_spin_speed", "exec_ball_spin_accel", "exec_ball_max_spin", "exec_ball_wall_drag", "exec_ball_ceiling_drag", "exec_chain_elasticity", "exec_chain_total_len", "exec_chain_adjust_speed", "exec_chain_damping", "exec_chain_gravity"]])
		groups.append(["# Executioner Shackle", ["shackle:mass", "shackle:chain_elasticity", "shackle:gravity", "shackle:drag"]])
		groups.append(["# Executioner Swing", ["exec_swing_max_damage", "exec_swing_slam_radius"]])
		groups.append(["# Executioner Cleave", ["exec_cleave_max_damage", "exec_cleave_charge_time", "exec_cleave_knockback"]])

	return groups


func _get_config_default(entity: Node2D, key: String) -> float:
	## Get the default value for a config key.
	## For monsters: reads from monster_defaults.json
	## For players: reads from hardcoded defaults matching player_side.gd constants
	var is_player: bool = false
	if entity.get_script():
		is_player = entity.get_script().resource_path.ends_with("player_side.gd")

	if is_player:
		return _get_player_config_default(entity, key)

	var path: String = "res://data/config/monster_defaults.json"
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file:
			var json := JSON.new()
			if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
				if json.data.has(key):
					return float(json.data[key])
	return 0.0


func _get_player_config_default(_entity: Node2D, key: String) -> float:
	## Default values for player config keys, matching player_side.gd constants.
	var defaults := {
		"gravity": 900.0,
		"jump_velocity": -550.0,
		"speed": 110.0,
		"attack_cooldown": 0.4,
		"special_cooldown": 1.5,
		"attack_damage_mult": 1.0,
		"special_damage_mult": 1.0,
		"charge_damage_mult": 1.0,
		"knockback_mult": 1.0,
		"max_health": 100.0,
		"max_mana": 50.0,
		"mana_regen": 1.0,
		"melee_combo_window": 0.6,
		"melee_enrage_duration": 10.0,
		"melee_enrage_cooldown": 45.0,
		"rogue_stealth_duration": 5.0,
		"rogue_stealth_cooldown": 20.0,
		"rogue_stealth_damage_mult": 3.75,
		"ranger_max_arrows": 10.0,
		"ranger_reload_time": 1.5,
		"exec_ball_damage": 35.0,
		"exec_ball_stun_duration": 3.0,
		"exec_ball_gravity": 900.0,
		"exec_ball_throw_speed": 1200.0,
		"exec_ball_max_throw_speed": 6000.0,
		"exec_ball_mass": 140.0,
	"exec_ball_spin_speed": 4.0,
	"exec_ball_spin_accel": 3.0,
	"exec_ball_max_spin": 15.0,
	"exec_ball_wall_drag": 12.0,
	"exec_ball_ceiling_drag": 20.0,
		"exec_chain_elasticity": 0.25,
		"exec_chain_total_len": 600.0,
		"exec_chain_adjust_speed": 0.5,
	"exec_chain_damping": 0.85,
	"exec_chain_gravity": 600.0,
		"exec_swing_max_damage": 80.0,
		"exec_swing_slam_radius": 60.0,
		"exec_cleave_max_damage": 150.0,
		"exec_cleave_charge_time": 2.0,
		"exec_cleave_knockback": 500.0,
	}
	return defaults.get(key, 0.0)


func _get_shackle_config_default(key: String) -> float:
	## Default values for shackle config keys, matching SHACKLE_DEFAULT_CONFIG.
	var defaults := {
		"mass": 5.0,
		"chain_elasticity": 0.25,
		"gravity": 600.0,
		"drag": 0.97,
	}
	return defaults.get(key, 0.0)


func _get_config_range(key: String, default_val: float) -> Vector2:
	## Return (min, max) range for a config slider. Uses the entity's
	## CONFIG_BOUNDS if available, otherwise heuristic.
	# Shackle keys have known ranges
	if key.begins_with("shackle:"):
		var skey: String = key.substr(8)
		match skey:
			"mass": return Vector2(0.1, 200.0)
			"chain_elasticity": return Vector2(0.0, 1.0)
			"gravity": return Vector2(0.0, 2000.0)
			"drag": return Vector2(0.8, 1.0)
		return Vector2(0.0, maxf(1.0, default_val * 3.0))
	# Chain physics ranges
	if key == "exec_chain_damping":
		return Vector2(0.8, 1.0)
	if key == "exec_chain_gravity":
		return Vector2(0.0, 1500.0)
	var entity: Node2D = _get_selected_entity()
	if entity and entity.get("CONFIG_BOUNDS") and entity.CONFIG_BOUNDS.has(key):
		return entity.CONFIG_BOUNDS[key]
	# Also check selected monster as fallback
	var monster: Node2D = _get_selected_monster()
	if monster and monster.get("CONFIG_BOUNDS") and monster.CONFIG_BOUNDS.has(key):
		return monster.CONFIG_BOUNDS[key]
	# Fallback heuristic
	if default_val == 0.0:
		return Vector2(0.0, 1.0)
	return Vector2(0.0, default_val * 2.5)


# ==============================================================================
# CONFIG SECTION — sub-section framework (Game Settings, Entities, Blueprints, Instances)
# ==============================================================================

func _init_cfg_subsections() -> void:
	_cfg_subsections = []
	var sids: Array[String] = [
		"cfg_settings",      # 1. Game Settings
		"cfg_classes",       # 2. Classes list
		"cfg_class",         # 3. Class editor
		"cfg_entities",      # 4. Entities list
		"cfg_entity_mods",   # 5. Entity Mods
		"cfg_entity_stats",  # 6. Entity Stats table
		"cfg_calculations",  # 7. Calculations breakdown
		"cfg_modifiers",     # 8. Modifier blueprints list
		"cfg_modifier",      # 9. Modifier editor
		"cfg_modified_ents", # 10. Modified Entities
	]
	for sid in sids:
		_cfg_subsections.append({
			"id": sid,
			"title": _cfg_sub_title(sid),
			"collapsed": sid in ["cfg_class", "cfg_calculations", "cfg_modified_ents"],  # Start collapsed
			"height": _get_cfg_preferred_height(sid),
		})
	var had_cfg_layout: bool = FileAccess.file_exists("user://config_panel_layout.json")
	_load_cfg_layout()
	if not had_cfg_layout:
		_auto_snap_cfg()
	_cfg_subsections_initialized = true
	_cfg_rebuild_bp_names()


func _cfg_sub_title(sid: String) -> String:
	match sid:
		"cfg_settings": return "Game Settings"
		"cfg_classes": return "Classes"
		"cfg_class":
			if _cfg_selected_class >= 0:
				var cls_name: String = PlayerHUD.CLASS_NAMES.get(_cfg_selected_class, "")
				return "Class (%s)" % cls_name if not cls_name.is_empty() else "Class"
			return "Class"
		"cfg_entities": return "Entities"
		"cfg_entity_mods":
			var sel: Node2D = _get_selected_entity()
			if sel:
				return "Entity Mods (%s)" % _cfg_get_entity_display_name(sel)
			return "Entity Mods"
		"cfg_entity_stats":
			var sel: Node2D = _get_selected_entity()
			if sel:
				return "Entity Stats (%s)" % _cfg_get_entity_display_name(sel)
			return "Entity Stats"
		"cfg_calculations":
			if not _cfg_selected_stat.is_empty():
				var sel: Node2D = _get_selected_entity()
				var ename: String = _cfg_get_entity_display_name(sel) if sel else ""
				return "Calc (%s:%s)" % [ename, _cfg_selected_stat]
			return "Calculations"
		"cfg_modifiers": return "Modifiers"
		"cfg_modifier":
			if not _cfg_selected_blueprint.is_empty():
				return "Modifier (%s)" % _cfg_selected_blueprint
			return "Modifier"
		"cfg_modified_ents":
			if not _cfg_selected_blueprint.is_empty():
				return "Modified (%s)" % _cfg_selected_blueprint
			return "Modified Entities"
	return sid


func _load_cfg_layout() -> void:
	var path: String = "user://config_panel_layout.json"
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return
	for sub in _cfg_subsections:
		if json.data.has(sub["id"]):
			sub["collapsed"] = json.data[sub["id"]].get("collapsed", sub["collapsed"])
			sub["height"] = json.data[sub["id"]].get("height", sub["height"])


func _save_cfg_layout() -> void:
	var data: Dictionary = {}
	for sub in _cfg_subsections:
		data[sub["id"]] = {"collapsed": sub["collapsed"], "height": sub["height"]}
	var file := FileAccess.open("user://config_panel_layout.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "  "))


func _auto_snap_cfg() -> void:
	if _cfg_subsections.is_empty():
		return
	var last: Dictionary = _cfg_subsections[_cfg_subsections.size() - 1]
	for i in range(_cfg_subsections.size() - 1):
		var sub: Dictionary = _cfg_subsections[i]
		if sub["collapsed"]:
			continue
		var preferred: float = _get_cfg_preferred_height(sub["id"])
		var delta: float = preferred - sub["height"]
		sub["height"] = preferred
		last["height"] -= delta
	if last["height"] < CFG_SUB_MIN.get("cfg_modified_ents", 36.0):
		last["height"] = CFG_SUB_MIN.get("cfg_modified_ents", 36.0)


func _get_cfg_preferred_height(sid: String) -> float:
	match sid:
		"cfg_settings":
			return SUB_HEADER_H + 1 * 18.0 + 8.0
		"cfg_classes":
			return SUB_HEADER_H + clampi(PlayerHUD.ALL_CLASSES.size() + 2, 4, 10) * 16.0 + 4.0
		"cfg_class":
			return SUB_HEADER_H + 8 * 16.0 + 4.0  # ~8 sliders
		"cfg_entities":
			var entity_count: int = _get_all_entities().size()
			return SUB_HEADER_H + clampi(entity_count + 1, 3, 10) * 16.0 + 4.0
		"cfg_entity_mods":
			return SUB_HEADER_H + 4 * 16.0 + 4.0
		"cfg_entity_stats":
			return SUB_HEADER_H + 8 * 14.0 + 4.0  # ~8 stat rows
		"cfg_calculations":
			return SUB_HEADER_H + 4 * 14.0 + 4.0
		"cfg_modifiers":
			var count: int = maxi(2, _cfg_cached_bp_names.size())
			return SUB_HEADER_H + clampi(count, 2, 6) * 16.0 + 4.0
		"cfg_modifier":
			return SUB_HEADER_H + 6 * 16.0 + 20.0  # Sliders + buttons
		"cfg_modified_ents":
			return SUB_HEADER_H + 3 * 16.0 + 4.0
	return SUB_HEADER_H + 40.0


func _snap_cfg_height(sid: String, h: float) -> float:
	var preferred: float = _get_cfg_preferred_height(sid)
	if absf(h - preferred) < SUB_SNAP_DISTANCE:
		return preferred
	return h


# -- Config sub-section helpers ------------------------------------------------

func _cfg_rebuild_bp_names() -> void:
	## Scan data/modifier_blueprints/ for available blueprint JSON files.
	_cfg_cached_bp_names.clear()
	var dir := DirAccess.open("res://data/modifier_blueprints/")
	if dir:
		dir.list_dir_begin()
		var fname: String = dir.get_next()
		while fname != "":
			if fname.ends_with(".json"):
				_cfg_cached_bp_names.append(fname.get_basename())
			fname = dir.get_next()
		dir.list_dir_end()
	# Also check user:// for custom blueprints
	var udir := DirAccess.open("user://modifier_blueprints/")
	if udir:
		udir.list_dir_begin()
		var fname2: String = udir.get_next()
		while fname2 != "":
			if fname2.ends_with(".json"):
				var bname: String = fname2.get_basename()
				if bname not in _cfg_cached_bp_names:
					_cfg_cached_bp_names.append(bname)
			fname2 = udir.get_next()
		udir.list_dir_end()
	_cfg_cached_bp_names.sort()
	_cfg_bp_names_dirty = false


func _cfg_load_blueprint(bp_name: String) -> Dictionary:
	## Load a modifier blueprint JSON by name. Checks user:// first, then res://.
	for base in ["user://modifier_blueprints/", "res://data/modifier_blueprints/"]:
		var path: String = base + bp_name + ".json"
		if FileAccess.file_exists(path):
			var file := FileAccess.open(path, FileAccess.READ)
			if file:
				var json := JSON.new()
				if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
					return json.data
	return {}


func _cfg_save_blueprint(bp_name: String, data: Dictionary) -> void:
	## Save a modifier blueprint to user://modifier_blueprints/.
	DirAccess.make_dir_recursive_absolute("user://modifier_blueprints")
	var path: String = "user://modifier_blueprints/" + bp_name + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "  "))
	_cfg_bp_names_dirty = true


func _cfg_bp_slider_range(op: String, current_val: float) -> Vector2:
	## Return (min, max) range for a blueprint modifier slider based on operation type.
	match op:
		"multiply":
			return Vector2(0.0, maxf(5.0, current_val * 2.0))
		"add":
			if current_val >= 0:
				return Vector2(-absf(current_val) * 2.0, absf(current_val) * 3.0)
			else:
				return Vector2(current_val * 3.0, absf(current_val) * 2.0)
		"set":
			if current_val == 0.0:
				return Vector2(0.0, 100.0)
			elif current_val > 0:
				return Vector2(0.0, current_val * 3.0)
			else:
				return Vector2(current_val * 3.0, 0.0)
		"min", "max":
			if current_val == 0.0:
				return Vector2(0.0, 100.0)
			return Vector2(0.0, current_val * 3.0)
	return Vector2(0.0, maxf(1.0, absf(current_val) * 2.5))


func _cfg_bp_update_live_instances(bp_name: String, key: String, op: String, value: float) -> void:
	## Update all live ModifierProvider instances that came from this blueprint.
	## This makes slider changes take effect immediately in-game.
	for entity in _get_all_entities():
		# Check entity config stack
		if "_config_stack" in entity:
			for provider in entity._config_stack:
				if provider.has_method("is_modifier") and provider.is_modifier():
					if "_name" in provider and provider._name == bp_name:
						provider._modifiers[key] = [op, value]
		# Check shackle config stack
		if "_exec_shackle_config_stack" in entity:
			for provider in entity._exec_shackle_config_stack:
				if provider.has_method("is_modifier") and provider.is_modifier():
					if "_name" in provider and provider._name == bp_name:
						provider._modifiers[key] = [op, value]


func _cfg_bp_cycle_operation(key: String) -> void:
	## Cycle the operation for a modifier key in the selected blueprint.
	if _cfg_bp_cached_data.is_empty() or not _cfg_bp_cached_data.has(key):
		return
	var val = _cfg_bp_cached_data[key]
	if not val is Array or val.size() != 2:
		return
	var ops: Array[String] = ["multiply", "add", "set", "min", "max"]
	var current_op: String = str(val[0])
	var idx: int = ops.find(current_op)
	var next_op: String = ops[(idx + 1) % ops.size()]
	_cfg_bp_cached_data[key] = [next_op, val[1]]
	# Update live instances
	_cfg_bp_update_live_instances(_cfg_selected_blueprint, key, next_op, float(val[1]))


func _cfg_bp_drag_at(lx: float) -> void:
	## Set blueprint modifier value based on slider position.
	if _cfg_bp_dragging_key.is_empty() or _cfg_bp_cached_data.is_empty():
		return
	var key: String = _cfg_bp_dragging_key
	if not _cfg_bp_cached_data.has(key):
		return
	var val = _cfg_bp_cached_data[key]
	if not val is Array or val.size() != 2:
		return
	var pw: float = _content_width
	var slider_x: float = pw * 0.42
	var slider_w: float = pw * 0.35
	var t: float = clampf((lx - slider_x) / slider_w, 0.0, 1.0)
	var op_str: String = str(val[0])
	var current_val: float = float(val[1])
	var range_info: Vector2 = _cfg_bp_slider_range(op_str, current_val)
	var new_val: float = lerpf(range_info.x, range_info.y, t)
	# Snap to nice values
	if absf(new_val) < 0.01:
		new_val = 0.0
	elif absf(new_val) > 10.0:
		new_val = roundf(new_val)
	elif absf(new_val) > 1.0:
		new_val = roundf(new_val * 10.0) / 10.0
	else:
		new_val = roundf(new_val * 100.0) / 100.0
	_cfg_bp_cached_data[key] = [op_str, new_val]
	# Update live instances in real-time
	_cfg_bp_update_live_instances(_cfg_selected_blueprint, key, op_str, new_val)
	_panel.queue_redraw()


func _cfg_count_active_modifiers() -> int:
	## Count total active ModifierProviders across all entities and shackle stacks.
	var count: int = 0
	for entity in _get_all_entities():
		if entity.has_method("cfg") and "_config_stack" in entity:
			for provider in entity._config_stack:
				if provider.has_method("is_modifier") and provider.is_modifier():
					count += 1
		# Also count shackle config stack modifiers (Executioner)
		if "_exec_shackle_config_stack" in entity:
			for provider in entity._exec_shackle_config_stack:
				if provider.has_method("is_modifier") and provider.is_modifier():
					count += 1
	return count


func _cfg_get_active_modifiers() -> Array:
	## Returns [{entity, provider, name, entity_id, stack}] for all active ModifierProviders.
	## Includes both entity config stacks and shackle config stacks.
	var result: Array = []
	for entity in _get_all_entities():
		var eid: String = _cfg_entity_id_str(entity)
		if entity.has_method("cfg") and "_config_stack" in entity:
			for provider in entity._config_stack:
				if provider.has_method("is_modifier") and provider.is_modifier():
					var pname: String = provider._name if "_name" in provider else str(provider)
					result.append({"entity": entity, "provider": provider, "name": pname, "entity_id": eid, "stack": "entity"})
		# Shackle config stack (Executioner)
		if "_exec_shackle_config_stack" in entity:
			for provider in entity._exec_shackle_config_stack:
				if provider.has_method("is_modifier") and provider.is_modifier():
					var pname: String = provider._name if "_name" in provider else str(provider)
					result.append({"entity": entity, "provider": provider, "name": pname, "entity_id": eid + " [shackle]", "stack": "shackle"})
	return result


func _cfg_entity_id_str(entity: Node2D) -> String:
	## Short entity ID for display in modifier lists.
	if "entity_id" in entity and not str(entity.entity_id).is_empty():
		return str(entity.entity_id)
	elif "player_index" in entity:
		return "P%d" % (entity.player_index + 1)
	return entity.name


func _cfg_instantiate_blueprint(bp_name: String, entity: Node2D) -> void:
	## Create a ModifierProvider from a blueprint and push it onto entity's config stack.
	var data: Dictionary = _cfg_load_blueprint(bp_name)
	if data.is_empty():
		return
	if not entity.has_method("push_config"):
		return
	# Build modifiers dict from blueprint data
	# Blueprint format: { "key": ["operation", value], ... }
	# Optional metadata: "_name", "_description" are skipped
	var modifiers: Dictionary = {}
	for key in data:
		if key.begins_with("_"):
			continue  # Skip metadata keys
		var val = data[key]
		if val is Array and val.size() == 2:
			modifiers[key] = val
	if modifiers.is_empty():
		return
	var MCP = load("res://scripts/systems/monster_config.gd")
	var provider = MCP.ModifierProvider.new(modifiers, bp_name)
	entity.push_config(provider)


# -- Config sub-section drawing ------------------------------------------------

func _draw_sub_header(x: float, y: float, pw: float, font: Font, sub: Dictionary,
		accent_col: Color, ctx_text: String = "", ctx_col: Color = Color(0.5, 0.5, 0.5)) -> void:
	## Unified sub-section header — used by Config, Level Editor, and Constructs.
	## accent_col tints the title, top line, and triangle.
	var bg_col := Color(0.07, 0.07, 0.07, 0.95)
	_panel.draw_rect(Rect2(x, y, pw - 8, SUB_HEADER_H), bg_col)
	_panel.draw_line(Vector2(x, y), Vector2(x + pw - 8, y), accent_col * Color(1, 1, 1, 0.4), 1.0)

	# Collapse triangle
	var tri_x: float = x + 6
	var tri_y: float = y + SUB_HEADER_H * 0.5
	var tri_col := accent_col * Color(1, 1, 1, 0.6)
	if sub["collapsed"]:
		var pts: PackedVector2Array = [
			Vector2(tri_x, tri_y - 5), Vector2(tri_x + 6, tri_y), Vector2(tri_x, tri_y + 5)]
		_panel.draw_polygon(pts, PackedColorArray([tri_col, tri_col, tri_col]))
	else:
		var pts: PackedVector2Array = [
			Vector2(tri_x - 1, tri_y - 3), Vector2(tri_x + 7, tri_y - 3), Vector2(tri_x + 3, tri_y + 4)]
		_panel.draw_polygon(pts, PackedColorArray([tri_col, tri_col, tri_col]))

	# Title
	_panel.draw_string(font, Vector2(x + 18, y + 14), sub["title"], HORIZONTAL_ALIGNMENT_LEFT, 120, 10, accent_col)

	# Context info
	if not ctx_text.is_empty():
		_panel.draw_string(font, Vector2(x + 140, y + 14), ctx_text, HORIZONTAL_ALIGNMENT_LEFT, pw - 170, 9, ctx_col)

	# Resize grip dots (2x3 grid) — always visible since grip controls section ABOVE
	var grip_x: float = x + pw - 22
	var grip_col := accent_col * Color(1, 1, 1, 0.3)
	for gi in range(3):
		for gj in range(2):
			_panel.draw_rect(Rect2(grip_x + gj * 5, y + 5 + gi * 5, 2, 2), grip_col)


func _draw_cfg_sub_header(x: float, y: float, pw: float, font: Font, sub: Dictionary) -> void:
	var ctx_text: String = ""
	var ctx_col := Color(0.4, 0.6, 0.8)
	match sub["id"]:
		"cfg_classes":
			ctx_text = "%d" % (PlayerHUD.ALL_CLASSES.size() + 5)  # +5 physics entity classes
		"cfg_entities":
			ctx_text = "%d" % _get_all_entities().size()
		"cfg_entity_mods":
			var sel: Node2D = _get_selected_entity()
			if sel and "_config_stack" in sel:
				ctx_text = "%d providers" % sel._config_stack.size()
		"cfg_entity_stats":
			if not _config_keys.is_empty():
				ctx_text = "%d keys" % _config_keys.size()
		"cfg_modifiers":
			ctx_text = "%d" % _cfg_cached_bp_names.size()
		"cfg_modified_ents":
			var count: int = _cfg_count_active_modifiers()
			if count > 0:
				ctx_text = "%d active" % count
				ctx_col = Color(0.9, 0.7, 0.3)
	_draw_sub_header(x, y, pw, font, sub, Color(0.5, 0.8, 1.0), ctx_text, ctx_col)


func _draw_cfg_sub_settings(x: float, y: float, pw: float, _h: float, font: Font) -> void:
	## Game Settings sub-section: toggle rows for global game config.
	# game/multiple_players_same_class toggle
	var mpc_val: bool = GameManager.multiple_players_same_class
	var mpc_label: String = "multiple_players_same_class"
	var mpc_col: Color = Color(0.3, 1.0, 0.3) if mpc_val else Color(0.6, 0.4, 0.4)
	var mpc_text: String = "ON" if mpc_val else "OFF"
	_panel.draw_string(font, Vector2(x + 4, y + 11), mpc_label, HORIZONTAL_ALIGNMENT_LEFT, pw * 0.7, 9, Color(0.7, 0.7, 0.7))
	_panel.draw_string(font, Vector2(x + pw - 44, y + 11), mpc_text, HORIZONTAL_ALIGNMENT_LEFT, 40, 9, mpc_col)
	# Store clickable rect for hit testing
	_game_config_rects["multiple_players_same_class"] = Rect2(x, y, pw - 16, 16)


func _draw_cfg_sub_entities(x: float, y: float, pw: float, h: float, font: Font) -> void:
	## Entities sub-section: filter, entity list, config sliders for selected entity.
	var local_y: float = 0.0

	# -- Search filter field --
	var cfg_filter_bg: Color = Color(0.12, 0.12, 0.16) if _config_filter_focused else Color(0.08, 0.08, 0.12)
	_panel.draw_rect(Rect2(x, y + local_y, pw - 16, 20), cfg_filter_bg)
	var cfg_filter_display: String = _config_filter_text
	if _config_filter_focused and int(_cursor_blink * 2) % 2 == 0:
		cfg_filter_display += "_"
	if cfg_filter_display == "" and not _config_filter_focused:
		_panel.draw_string(font, Vector2(x + 4, y + local_y + 14), "Filter config...", HORIZONTAL_ALIGNMENT_LEFT, pw - 24, 10, Color(0.4, 0.4, 0.4))
	else:
		_panel.draw_string(font, Vector2(x + 4, y + local_y + 14), cfg_filter_display, HORIZONTAL_ALIGNMENT_LEFT, pw - 24, 10, Color(0.8, 0.8, 0.8))
	local_y += 24

	# -- Entity list --
	var entities: Array = _get_all_entities()
	_panel.draw_line(Vector2(x, y + local_y), Vector2(x + pw - 16, y + local_y), Color(0.2, 0.3, 0.4), 1.0)
	local_y += 2
	_panel.draw_string(font, Vector2(x, y + local_y + 12), "Entities (%d)" % entities.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.75, 1.0))
	local_y += 16

	var entity_row_h: float = 16.0
	var selected_entity: Node2D = _get_selected_entity()
	var max_entity_rows: int = int((h - local_y - 4) * 0.4 / entity_row_h)  # Use ~40% of remaining space for entity list
	max_entity_rows = maxi(max_entity_rows, 2)
	var visible_entities: int = mini(entities.size(), max_entity_rows)
	var entity_offset: int = clampi(_cfg_entities_scroll_offset, 0, maxi(0, entities.size() - visible_entities))
	_cfg_entities_scroll_offset = entity_offset

	for ei in range(entity_offset, mini(entity_offset + visible_entities, entities.size())):
		var e: Node2D = entities[ei]
		var is_sel: bool = (e == selected_entity)
		# Entity ID — show player name for players, entity_id or node name otherwise
		var eid: String = _cfg_get_entity_display_name(e)
		# Entity type
		var etype: String = _cfg_get_entity_type(e)
		if is_sel:
			_panel.draw_rect(Rect2(x, y + local_y, pw - 16, entity_row_h - 2), Color(0.15, 0.25, 0.15))
		var id_col := Color(0.5, 1.0, 0.5) if is_sel else Color(0.7, 0.7, 0.7)
		var type_col := Color(0.4, 0.8, 0.4) if is_sel else Color(0.5, 0.5, 0.5)
		var num_col := Color(0.3, 0.9, 1.0) if is_sel else Color(0.4, 0.5, 0.6)
		_panel.draw_string(font, Vector2(x + 2, y + local_y + 12), "%d" % (ei + 1), HORIZONTAL_ALIGNMENT_LEFT, 14, 9, num_col)
		_panel.draw_string(font, Vector2(x + 18, y + local_y + 12), eid, HORIZONTAL_ALIGNMENT_LEFT, pw * 0.35, 9, id_col)
		_panel.draw_string(font, Vector2(x + pw * 0.40, y + local_y + 12), etype, HORIZONTAL_ALIGNMENT_LEFT, pw * 0.25, 8, type_col)
		# "Tune" button for entities that support tuning popup
		if e.has_method("exec_tuning_toggle"):
			var btn_x: float = x + pw - 52
			var btn_w: float = 34.0
			var has_tuning: bool = e.get("_exec_tuning_visible") == true
			var btn_col: Color = Color(0.3, 0.5, 0.2) if has_tuning else Color(0.2, 0.2, 0.25)
			var btn_text_col: Color = Color(0.8, 1.0, 0.5) if has_tuning else Color(0.5, 0.5, 0.5)
			_panel.draw_rect(Rect2(btn_x, y + local_y + 1, btn_w, entity_row_h - 3), btn_col)
			_panel.draw_string(font, Vector2(btn_x + 3, y + local_y + 11), "Tune", HORIZONTAL_ALIGNMENT_LEFT, btn_w, 8, btn_text_col)
		# "Mod+" button for applying modifier blueprints
		if e.has_method("push_config") and not _cfg_cached_bp_names.is_empty():
			var mod_btn_x: float = x + pw - 90
			var mod_btn_w: float = 32.0
			var mod_btn_col := Color(0.2, 0.25, 0.35)
			_panel.draw_rect(Rect2(mod_btn_x, y + local_y + 1, mod_btn_w, entity_row_h - 3), mod_btn_col)
			_panel.draw_string(font, Vector2(mod_btn_x + 3, y + local_y + 11), "Mod+", HORIZONTAL_ALIGNMENT_LEFT, mod_btn_w, 7, Color(0.5, 0.7, 1.0))
		local_y += entity_row_h

	if entities.is_empty():
		_panel.draw_string(font, Vector2(x + 6, y + local_y + 12), "(no entities in scene)", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.4, 0.4))
		local_y += entity_row_h

	# Entities list is now a pure list — sliders moved to Class editor and Entity Stats


func _draw_cfg_sub_blueprints(x: float, y: float, pw: float, h: float, font: Font) -> void:
	## Modifier Blueprints sub-section: list of blueprint templates with editor.
	var local_y: float = 0.0

	# Filter field
	var bp_filter_bg: Color = Color(0.12, 0.12, 0.16) if _cfg_bp_filter_focused else Color(0.08, 0.08, 0.12)
	_panel.draw_rect(Rect2(x, y + local_y, pw - 16, 18), bp_filter_bg)
	var bp_filter_display: String = _cfg_bp_filter_text
	if _cfg_bp_filter_focused and int(_cursor_blink * 2) % 2 == 0:
		bp_filter_display += "_"
	if bp_filter_display == "" and not _cfg_bp_filter_focused:
		_panel.draw_string(font, Vector2(x + 4, y + local_y + 12), "Filter blueprints...", HORIZONTAL_ALIGNMENT_LEFT, pw - 24, 9, Color(0.4, 0.4, 0.4))
	else:
		_panel.draw_string(font, Vector2(x + 4, y + local_y + 12), bp_filter_display, HORIZONTAL_ALIGNMENT_LEFT, pw - 24, 9, Color(0.8, 0.8, 0.8))
	local_y += 20

	# Blueprint list
	if _cfg_bp_names_dirty:
		_cfg_rebuild_bp_names()

	var filtered_bps: Array[String] = []
	if _cfg_bp_filter_text.is_empty():
		filtered_bps.assign(_cfg_cached_bp_names)
	else:
		var ft: String = _cfg_bp_filter_text.to_lower()
		for bp in _cfg_cached_bp_names:
			if ft in bp.to_lower():
				filtered_bps.append(bp)

	var row_h: float = 16.0
	var list_h: float = minf(h * 0.45, filtered_bps.size() * row_h + 4.0)
	var visible: int = int(list_h / row_h)
	var bp_offset: int = clampi(_cfg_blueprints_scroll_offset, 0, maxi(0, filtered_bps.size() - visible))
	_cfg_blueprints_scroll_offset = bp_offset

	for bi in range(bp_offset, mini(bp_offset + visible, filtered_bps.size())):
		var bp_name: String = filtered_bps[bi]
		var is_sel: bool = (bp_name == _cfg_selected_blueprint)
		if is_sel:
			_panel.draw_rect(Rect2(x, y + local_y, pw - 16, row_h - 2), Color(0.15, 0.15, 0.25))
		var col: Color = Color(0.6, 0.8, 1.0) if is_sel else Color(0.5, 0.5, 0.6)
		_panel.draw_string(font, Vector2(x + 4, y + local_y + 11), bp_name, HORIZONTAL_ALIGNMENT_LEFT, pw * 0.65, 9, col)
		# Show modifier count
		var bp_data: Dictionary = _cfg_load_blueprint(bp_name)
		var mod_count: int = 0
		for key in bp_data:
			if not key.begins_with("_"):
				mod_count += 1
		_panel.draw_string(font, Vector2(x + pw * 0.7, y + local_y + 11), "%d mods" % mod_count, HORIZONTAL_ALIGNMENT_LEFT, 60, 8, Color(0.4, 0.5, 0.6))
		local_y += row_h

	if filtered_bps.is_empty():
		_panel.draw_string(font, Vector2(x + 4, y + local_y + 11), "(no blueprints)", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.4, 0.4))
		local_y += row_h

	local_y += 4
	_panel.draw_line(Vector2(x, y + local_y), Vector2(x + pw - 16, y + local_y), Color(0.2, 0.3, 0.4), 1.0)
	local_y += 4

	# Blueprint editor — interactive sliders for live tuning
	if _cfg_selected_blueprint.is_empty():
		_panel.draw_string(font, Vector2(x + 4, y + local_y + 11), "Click a blueprint to edit", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.4, 0.4))
		return

	# Cache blueprint data for editing (reload only on selection change)
	if _cfg_bp_cached_data.get("_bp_name", "") != _cfg_selected_blueprint:
		_cfg_bp_cached_data = _cfg_load_blueprint(_cfg_selected_blueprint)
		_cfg_bp_cached_data["_bp_name"] = _cfg_selected_blueprint

	# Header: blueprint name + buttons
	_panel.draw_string(font, Vector2(x, y + local_y + 11), _cfg_selected_blueprint, HORIZONTAL_ALIGNMENT_LEFT, pw * 0.38, 9, Color(0.9, 0.7, 0.3))

	# [Apply] button — applies to selected entity's config stack
	var sel_entity: Node2D = _get_selected_entity()
	if sel_entity and sel_entity.has_method("push_config"):
		var apply_x: float = x + pw * 0.40
		_panel.draw_rect(Rect2(apply_x, y + local_y, 38, 14), Color(0.2, 0.35, 0.2))
		_panel.draw_string(font, Vector2(apply_x + 3, y + local_y + 10), "Apply", HORIZONTAL_ALIGNMENT_LEFT, 34, 7, Color(0.5, 1.0, 0.5))

	# [Shackle] button — applies to shackle config stack
	if sel_entity and sel_entity.has_method("push_shackle_config"):
		var shk_x: float = x + pw * 0.53
		_panel.draw_rect(Rect2(shk_x, y + local_y, 44, 14), Color(0.2, 0.25, 0.35))
		_panel.draw_string(font, Vector2(shk_x + 3, y + local_y + 10), "Shackle", HORIZONTAL_ALIGNMENT_LEFT, 40, 7, Color(0.5, 0.7, 1.0))

	# [Save] button
	var save_x: float = x + pw - 44
	_panel.draw_rect(Rect2(save_x, y + local_y, 30, 14), Color(0.25, 0.2, 0.15))
	_panel.draw_string(font, Vector2(save_x + 3, y + local_y + 10), "Save", HORIZONTAL_ALIGNMENT_LEFT, 28, 7, Color(0.9, 0.8, 0.4))
	local_y += 18

	# Editable modifier rows: [key] [op] [===slider===] [value]
	var slider_h: float = 16.0
	var slider_gap: float = 2.0
	var mod_keys: Array[String] = []
	for key in _cfg_bp_cached_data:
		if not key.begins_with("_"):
			mod_keys.append(key)

	for key in mod_keys:
		if y + local_y > y + h - 4:
			break
		var val = _cfg_bp_cached_data[key]
		var op_str: String = "?"
		var num_val: float = 0.0
		if val is Array and val.size() == 2:
			op_str = str(val[0])
			num_val = float(val[1])

		# Operation label (clickable to cycle)
		var op_col := Color(0.6, 0.8, 0.4)
		match op_str:
			"multiply": op_col = Color(0.8, 0.6, 1.0)
			"add": op_col = Color(0.4, 0.8, 0.6)
			"set": op_col = Color(1.0, 0.7, 0.3)
			"min": op_col = Color(0.4, 0.7, 1.0)
			"max": op_col = Color(1.0, 0.5, 0.4)

		# Key name
		_panel.draw_string(font, Vector2(x + 4, y + local_y + 11), key, HORIZONTAL_ALIGNMENT_LEFT, pw * 0.28, 8, Color(0.7, 0.7, 0.7))

		# Operation badge
		var op_badge_x: float = x + pw * 0.29
		_panel.draw_rect(Rect2(op_badge_x, y + local_y + 2, pw * 0.11, 12), op_col * 0.3)
		_panel.draw_string(font, Vector2(op_badge_x + 2, y + local_y + 11), op_str.substr(0, 3), HORIZONTAL_ALIGNMENT_LEFT, pw * 0.11, 7, op_col)

		# Slider track
		var slider_x: float = x + pw * 0.42
		var slider_w: float = pw * 0.35
		_panel.draw_rect(Rect2(slider_x, y + local_y + 4, slider_w, 8), Color(0.1, 0.1, 0.15))

		# Slider range depends on operation
		var range_info: Vector2 = _cfg_bp_slider_range(op_str, num_val)
		var t: float = clampf((num_val - range_info.x) / maxf(range_info.y - range_info.x, 0.001), 0.0, 1.0)

		# Slider fill
		var is_dragging: bool = (_cfg_bp_dragging_key == key)
		var fill_col: Color = Color(0.8, 0.6, 1.0) if is_dragging else op_col * 0.7
		_panel.draw_rect(Rect2(slider_x, y + local_y + 4, slider_w * t, 8), fill_col)

		# Handle
		var handle_x: float = slider_x + slider_w * t
		_panel.draw_rect(Rect2(handle_x - 2, y + local_y + 2, 4, 12), Color.WHITE if is_dragging else Color(0.8, 0.8, 0.8))

		# Value text
		_panel.draw_string(font, Vector2(x + pw * 0.80, y + local_y + 11), "%.2f" % num_val, HORIZONTAL_ALIGNMENT_LEFT, pw * 0.18, 8, Color(0.9, 0.9, 0.9))

		local_y += slider_h + slider_gap


func _draw_cfg_sub_instances(x: float, y: float, pw: float, h: float, font: Font) -> void:
	## Modifier Instances sub-section: all active modifiers across entities.
	var local_y: float = 0.0

	# Filter field
	var mod_filter_bg: Color = Color(0.12, 0.12, 0.16) if _cfg_mod_filter_focused else Color(0.08, 0.08, 0.12)
	_panel.draw_rect(Rect2(x, y + local_y, pw - 16, 18), mod_filter_bg)
	var mod_filter_display: String = _cfg_mod_filter_text
	if _cfg_mod_filter_focused and int(_cursor_blink * 2) % 2 == 0:
		mod_filter_display += "_"
	if mod_filter_display == "" and not _cfg_mod_filter_focused:
		_panel.draw_string(font, Vector2(x + 4, y + local_y + 12), "Filter modifiers...", HORIZONTAL_ALIGNMENT_LEFT, pw - 24, 9, Color(0.4, 0.4, 0.4))
	else:
		_panel.draw_string(font, Vector2(x + 4, y + local_y + 12), mod_filter_display, HORIZONTAL_ALIGNMENT_LEFT, pw - 24, 9, Color(0.8, 0.8, 0.8))
	local_y += 20

	var active_mods: Array = _cfg_get_active_modifiers()

	# Filter
	var filtered_mods: Array = []
	if _cfg_mod_filter_text.is_empty():
		filtered_mods = active_mods
	else:
		var ft: String = _cfg_mod_filter_text.to_lower()
		for mod in active_mods:
			if ft in mod["name"].to_lower() or ft in mod["entity_id"].to_lower():
				filtered_mods.append(mod)

	var row_h: float = 16.0
	var visible: int = int((h - local_y - 4) / row_h)
	var mod_offset: int = clampi(_cfg_instances_scroll_offset, 0, maxi(0, filtered_mods.size() - visible))
	_cfg_instances_scroll_offset = mod_offset

	for mi in range(mod_offset, mini(mod_offset + visible, filtered_mods.size())):
		var mod: Dictionary = filtered_mods[mi]
		var is_hover: bool = (mi == _cfg_hover_instance_idx)
		if is_hover:
			_panel.draw_rect(Rect2(x, y + local_y, pw - 16, row_h - 2), Color(0.15, 0.15, 0.2))
		# Modifier name
		_panel.draw_string(font, Vector2(x + 4, y + local_y + 11), mod["name"], HORIZONTAL_ALIGNMENT_LEFT, pw * 0.45, 9, Color(0.7, 0.85, 1.0))
		# Entity it's attached to
		_panel.draw_string(font, Vector2(x + pw * 0.48, y + local_y + 11), mod["entity_id"], HORIZONTAL_ALIGNMENT_LEFT, pw * 0.25, 8, Color(0.5, 0.7, 0.5))
		# Remove button [X]
		var rm_x: float = x + pw - 28
		_panel.draw_rect(Rect2(rm_x, y + local_y + 2, 16, row_h - 4), Color(0.35, 0.15, 0.15))
		_panel.draw_string(font, Vector2(rm_x + 3, y + local_y + 11), "X", HORIZONTAL_ALIGNMENT_LEFT, 14, 8, Color(1.0, 0.4, 0.4))
		local_y += row_h

	if filtered_mods.is_empty():
		_panel.draw_string(font, Vector2(x + 4, y + local_y + 11), "(no active modifiers)", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.4, 0.4))


func _draw_cfg_sub_classes(x: float, y: float, pw: float, h: float, font: Font) -> void:
	## Classes list — click to select a class for editing.
	var row_h: float = 16.0
	var all_classes: Array = PlayerHUD.ALL_CLASSES
	# Also add physics entity "classes"
	var extra_classes: Array[String] = ["spikeball", "shackle", "chain", "soccer_dummy", "monster"]
	var local_y: float = 0.0

	for i in range(all_classes.size()):
		if y + local_y > y + h:
			break
		var cls: int = all_classes[i]
		var cls_name: String = PlayerHUD.CLASS_NAMES.get(cls, "?")
		var is_sel: bool = (_cfg_selected_class == cls)
		if is_sel:
			_panel.draw_rect(Rect2(x, y + local_y, pw - 16, row_h - 2), Color(0.15, 0.2, 0.15))
		var col: Color = Color(0.5, 1.0, 0.5) if is_sel else Color(0.6, 0.6, 0.6)
		var cls_col: Color = PlayerHUD.CLASS_COLORS.get(cls, Color(0.5, 0.5, 0.5))
		_panel.draw_rect(Rect2(x + 2, y + local_y + 3, 8, row_h - 6), cls_col)
		_panel.draw_string(font, Vector2(x + 14, y + local_y + 11), cls_name, HORIZONTAL_ALIGNMENT_LEFT, pw * 0.6, 9, col)
		local_y += row_h

	# Physics entity classes
	_panel.draw_line(Vector2(x, y + local_y), Vector2(x + pw - 16, y + local_y), Color(0.2, 0.3, 0.4), 1.0)
	local_y += 2
	for ec in extra_classes:
		if y + local_y > y + h:
			break
		var is_sel: bool = (_cfg_selected_class == -100 - extra_classes.find(ec))  # Negative IDs for physics entities
		if is_sel:
			_panel.draw_rect(Rect2(x, y + local_y, pw - 16, row_h - 2), Color(0.15, 0.15, 0.2))
		var col: Color = Color(0.5, 0.8, 1.0) if is_sel else Color(0.5, 0.5, 0.5)
		_panel.draw_string(font, Vector2(x + 14, y + local_y + 11), ec, HORIZONTAL_ALIGNMENT_LEFT, pw * 0.6, 9, col)
		local_y += row_h


func _draw_cfg_sub_class(x: float, y: float, pw: float, h: float, font: Font) -> void:
	## Class editor — sliders for base stats loaded from class default JSON.
	if _cfg_selected_class < 0 and _cfg_selected_class > -100:
		_panel.draw_string(font, Vector2(x + 4, y + 11), "Select a class above", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.4, 0.4))
		return

	var cls_name: String = _cfg_resolve_class_name()
	if cls_name.is_empty():
		_panel.draw_string(font, Vector2(x + 4, y + 11), "Unknown class", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.5, 0.3, 0.3))
		return

	_cfg_ensure_class_data(cls_name)
	if _cfg_class_data.is_empty():
		_panel.draw_string(font, Vector2(x + 4, y + 11), "No defaults for '%s'" % cls_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.5, 0.3, 0.3))
		return

	var data: Dictionary = _cfg_class_data
	var local_y: float = 0.0
	var slider_h: float = 16.0
	var slider_gap: float = 2.0

	for key in data:
		if y + local_y > y + h:
			break
		var val: float = float(data[key])
		var range_info: Vector2 = _get_config_range(key, val)
		var t: float = clampf((val - range_info.x) / maxf(range_info.y - range_info.x, 0.001), 0.0, 1.0)

		# Key label
		_panel.draw_string(font, Vector2(x + 4, y + local_y + 11), key, HORIZONTAL_ALIGNMENT_LEFT, pw * 0.42, 8, Color(0.7, 0.7, 0.7))

		# Slider track
		var slider_x: float = x + pw * 0.45
		var slider_w: float = pw * 0.35
		_panel.draw_rect(Rect2(slider_x, y + local_y + 4, slider_w, 8), Color(0.1, 0.1, 0.15))
		_panel.draw_rect(Rect2(slider_x, y + local_y + 4, slider_w * t, 8), Color(0.3, 0.6, 1.0))

		# Handle
		var handle_x: float = slider_x + slider_w * t
		_panel.draw_rect(Rect2(handle_x - 2, y + local_y + 2, 4, 12), Color(0.8, 0.8, 0.8))

		# Value
		_panel.draw_string(font, Vector2(x + pw * 0.83, y + local_y + 11), "%.2f" % val, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.7, 0.7, 0.7))

		local_y += slider_h + slider_gap


func _draw_cfg_sub_entity_mods(x: float, y: float, pw: float, h: float, font: Font) -> void:
	## Entity Mods — modifiers applied to selected entity.
	var sel: Node2D = _get_selected_entity()
	if not sel:
		_panel.draw_string(font, Vector2(x + 4, y + 11), "Select an entity", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.4, 0.4))
		return
	if not sel.has_method("cfg") or not "_config_stack" in sel:
		_panel.draw_string(font, Vector2(x + 4, y + 11), "(no config stack)", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.4, 0.4))
		return
	var row_h: float = 14.0
	var local_y: float = 0.0
	for provider in sel._config_stack:
		if y + local_y > y + h:
			break
		var pname: String = provider._name if "_name" in provider else str(provider)
		var is_mod: bool = provider.has_method("is_modifier") and provider.is_modifier()
		var col: Color = Color(0.7, 0.85, 1.0) if is_mod else Color(0.5, 0.5, 0.5)
		var type_str: String = "MOD" if is_mod else "BASE"
		_panel.draw_string(font, Vector2(x + 4, y + local_y + 10), type_str, HORIZONTAL_ALIGNMENT_LEFT, 30, 7, col * 0.7)
		_panel.draw_string(font, Vector2(x + 36, y + local_y + 10), pname, HORIZONTAL_ALIGNMENT_LEFT, pw * 0.6, 8, col)
		local_y += row_h
	if sel._config_stack.is_empty():
		_panel.draw_string(font, Vector2(x + 4, y + 11), "(no providers)", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.4, 0.4))


func _draw_cfg_sub_entity_stats(x: float, y: float, pw: float, h: float, font: Font) -> void:
	## Entity Stats — Stat / Base / Mods / Curr table.
	var sel: Node2D = _get_selected_entity()
	if not sel or not sel.has_method("cfg"):
		_panel.draw_string(font, Vector2(x + 4, y + 11), "Select an entity with cfg()", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.4, 0.4))
		return
	# Header row
	var local_y: float = 0.0
	var col_stat_x: float = x + 4
	var col_base_x: float = x + pw * 0.45
	var col_mods_x: float = x + pw * 0.65
	var col_curr_x: float = x + pw * 0.78
	_panel.draw_string(font, Vector2(col_stat_x, y + 10), "Stat", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.5, 0.5, 0.6))
	_panel.draw_string(font, Vector2(col_base_x, y + 10), "Base", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.5, 0.5, 0.6))
	_panel.draw_string(font, Vector2(col_mods_x, y + 10), "Mods", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.5, 0.5, 0.6))
	_panel.draw_string(font, Vector2(col_curr_x, y + 10), "Curr", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.5, 0.5, 0.6))
	local_y += 14.0
	_panel.draw_line(Vector2(x, y + local_y), Vector2(x + pw - 16, y + local_y), Color(0.2, 0.3, 0.4), 1.0)
	local_y += 2

	# Build stat rows from config keys
	if _config_keys.is_empty():
		_rebuild_config_keys(sel)
	var row_h: float = 13.0
	for key in _config_keys:
		if y + local_y > y + h:
			break
		if key.begins_with("# "):
			# Group header
			_panel.draw_string(font, Vector2(col_stat_x, y + local_y + 9), key.substr(2), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.4, 0.6, 0.8))
			local_y += row_h
			continue
		# Resolve values
		var default_val: float = _get_config_default(sel, key)
		var base_val: float = default_val
		var curr_val: float = sel.cfg(key, default_val)
		# Count modifiers touching this key
		var mod_count: int = 0
		if "_config_stack" in sel:
			for provider in sel._config_stack:
				if provider.has_method("is_modifier") and provider.is_modifier() and provider.has_method("has_modifier"):
					if provider.has_modifier(key):
						mod_count += 1
		var is_modified: bool = curr_val != base_val
		var is_sel_stat: bool = (_cfg_selected_stat == key)
		if is_sel_stat:
			_panel.draw_rect(Rect2(x, y + local_y, pw - 16, row_h - 1), Color(0.15, 0.2, 0.25))
		var stat_col: Color = Color(1.0, 0.85, 0.3) if is_modified else Color(0.6, 0.6, 0.6)
		_panel.draw_string(font, Vector2(col_stat_x, y + local_y + 9), key, HORIZONTAL_ALIGNMENT_LEFT, pw * 0.40, 7, stat_col)
		_panel.draw_string(font, Vector2(col_base_x, y + local_y + 9), "%.1f" % base_val, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.5, 0.5, 0.5))
		if mod_count > 0:
			_panel.draw_string(font, Vector2(col_mods_x, y + local_y + 9), "%d" % mod_count, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.8, 0.6, 1.0))
		_panel.draw_string(font, Vector2(col_curr_x, y + local_y + 9), "%.1f" % curr_val, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, stat_col)
		local_y += row_h


func _draw_cfg_sub_calculations(x: float, y: float, pw: float, h: float, font: Font) -> void:
	## Calculations — breakdown of how a selected stat is computed.
	if _cfg_selected_stat.is_empty():
		_panel.draw_string(font, Vector2(x + 4, y + 11), "Click a stat above", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.4, 0.4))
		return
	var sel: Node2D = _get_selected_entity()
	if not sel or not sel.has_method("cfg") or not "_config_stack" in sel:
		return
	# Walk config stack and show each provider's contribution
	var local_y: float = 0.0
	var row_h: float = 13.0
	var key: String = _cfg_selected_stat
	var default_val: float = _get_config_default(sel, key)
	var val: float = default_val
	# Header
	_panel.draw_string(font, Vector2(x + 4, y + local_y + 9), "Step", HORIZONTAL_ALIGNMENT_LEFT, 30, 7, Color(0.5, 0.5, 0.6))
	_panel.draw_string(font, Vector2(x + 36, y + local_y + 9), "Source", HORIZONTAL_ALIGNMENT_LEFT, pw * 0.3, 7, Color(0.5, 0.5, 0.6))
	_panel.draw_string(font, Vector2(x + pw * 0.48, y + local_y + 9), "Op", HORIZONTAL_ALIGNMENT_LEFT, 40, 7, Color(0.5, 0.5, 0.6))
	_panel.draw_string(font, Vector2(x + pw * 0.62, y + local_y + 9), "Value", HORIZONTAL_ALIGNMENT_LEFT, 40, 7, Color(0.5, 0.5, 0.6))
	_panel.draw_string(font, Vector2(x + pw * 0.80, y + local_y + 9), "Result", HORIZONTAL_ALIGNMENT_LEFT, 40, 7, Color(0.5, 0.5, 0.6))
	local_y += row_h + 2
	# Base value
	_panel.draw_string(font, Vector2(x + 4, y + local_y + 9), "base", HORIZONTAL_ALIGNMENT_LEFT, 30, 7, Color(0.5, 0.7, 0.5))
	_panel.draw_string(font, Vector2(x + 36, y + local_y + 9), "default", HORIZONTAL_ALIGNMENT_LEFT, pw * 0.3, 7, Color(0.5, 0.5, 0.5))
	_panel.draw_string(font, Vector2(x + pw * 0.80, y + local_y + 9), "%.2f" % val, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.7, 0.7, 0.7))
	local_y += row_h
	# Walk base providers (first non-null wins)
	for provider in sel._config_stack:
		if provider.has_method("is_modifier") and provider.is_modifier():
			continue
		var pval = provider.get_value(key)
		if pval != null:
			val = float(pval)
			var pname: String = provider._name if "_name" in provider else "?"
			_panel.draw_string(font, Vector2(x + 4, y + local_y + 9), "set", HORIZONTAL_ALIGNMENT_LEFT, 30, 7, Color(1.0, 0.7, 0.3))
			_panel.draw_string(font, Vector2(x + 36, y + local_y + 9), pname, HORIZONTAL_ALIGNMENT_LEFT, pw * 0.3, 7, Color(0.7, 0.7, 0.7))
			_panel.draw_string(font, Vector2(x + pw * 0.80, y + local_y + 9), "%.2f" % val, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.9, 0.9, 0.9))
			local_y += row_h
			break
	# Walk modifier providers (applied in reverse order in apply_modifiers)
	var step: int = 1
	for i in range(sel._config_stack.size() - 1, -1, -1):
		if y + local_y > y + h:
			break
		var provider = sel._config_stack[i]
		if not provider.has_method("is_modifier") or not provider.is_modifier():
			continue
		if not provider.has_method("get_modifier"):
			continue
		var mod = provider.get_modifier(key)
		if mod == null:
			continue
		var op: String = str(mod[0])
		var operand: float = float(mod[1])
		var prev_val: float = val
		match op:
			"multiply": val *= operand
			"add": val += operand
			"set": val = operand
			"min": val = maxf(val, operand)
			"max": val = minf(val, operand)
		var pname: String = provider._name if "_name" in provider else "?"
		var op_col: Color = Color(0.8, 0.6, 1.0)
		_panel.draw_string(font, Vector2(x + 4, y + local_y + 9), "%d" % step, HORIZONTAL_ALIGNMENT_LEFT, 30, 7, Color(0.5, 0.5, 0.5))
		_panel.draw_string(font, Vector2(x + 36, y + local_y + 9), pname, HORIZONTAL_ALIGNMENT_LEFT, pw * 0.3, 7, Color(0.7, 0.7, 0.7))
		_panel.draw_string(font, Vector2(x + pw * 0.48, y + local_y + 9), op, HORIZONTAL_ALIGNMENT_LEFT, 40, 7, op_col)
		_panel.draw_string(font, Vector2(x + pw * 0.62, y + local_y + 9), "%.2f" % operand, HORIZONTAL_ALIGNMENT_LEFT, 40, 7, Color(0.7, 0.7, 0.7))
		_panel.draw_string(font, Vector2(x + pw * 0.80, y + local_y + 9), "%.2f" % val, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.9, 0.9, 0.9))
		local_y += row_h
		step += 1
	# Final
	_panel.draw_line(Vector2(x, y + local_y), Vector2(x + pw - 16, y + local_y), Color(0.3, 0.4, 0.3), 1.0)
	local_y += 2
	_panel.draw_string(font, Vector2(x + 4, y + local_y + 9), "final", HORIZONTAL_ALIGNMENT_LEFT, 30, 7, Color(0.3, 1.0, 0.3))
	_panel.draw_string(font, Vector2(x + pw * 0.80, y + local_y + 9), "%.2f" % val, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.3, 1.0, 0.3))


func _draw_cfg_sub_modifier(x: float, y: float, pw: float, h: float, font: Font) -> void:
	## Modifier editor — same as old _draw_cfg_sub_blueprints editor area.
	## Reuses the blueprint editor drawing from the existing code.
	if _cfg_selected_blueprint.is_empty():
		_panel.draw_string(font, Vector2(x + 4, y + 11), "Select a modifier above", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.4, 0.4))
		return
	# Delegate to the existing blueprint editor drawing (it handles cached data, sliders, buttons)
	# The _draw_cfg_sub_blueprints function handles list + editor. Here we just draw the editor part.
	_panel.draw_string(font, Vector2(x + 4, y + 11), "Modifier editor — use Modifiers list above", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.5, 0.5, 0.5))


func _draw_cfg_sub_modified_ents(x: float, y: float, pw: float, h: float, font: Font) -> void:
	## Modified Entities — entities with the selected modifier applied.
	if _cfg_selected_blueprint.is_empty():
		_panel.draw_string(font, Vector2(x + 4, y + 11), "Select a modifier", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.4, 0.4))
		return
	var row_h: float = 14.0
	var local_y: float = 0.0
	var bp_name: String = _cfg_selected_blueprint
	for entity in _get_all_entities():
		if not "_config_stack" in entity:
			continue
		for provider in entity._config_stack:
			if provider.has_method("is_modifier") and provider.is_modifier():
				if "_name" in provider and provider._name == bp_name:
					if y + local_y > y + h:
						break
					var eid: String = _cfg_entity_id_str(entity)
					var etype: String = _cfg_get_entity_type(entity)
					_panel.draw_string(font, Vector2(x + 4, y + local_y + 10), eid, HORIZONTAL_ALIGNMENT_LEFT, pw * 0.5, 8, Color(0.7, 0.85, 1.0))
					_panel.draw_string(font, Vector2(x + pw * 0.52, y + local_y + 10), etype, HORIZONTAL_ALIGNMENT_LEFT, pw * 0.4, 7, Color(0.5, 0.5, 0.5))
					local_y += row_h
					break  # One entry per entity
	if local_y == 0:
		_panel.draw_string(font, Vector2(x + 4, y + 11), "(no entities)", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.4, 0.4))


func _cfg_get_entity_display_name(e: Node2D) -> String:
	## Returns display name for an entity in the entity list.
	var is_player_entity: bool = "player_index" in e and "character_class" in e
	if is_player_entity:
		var pi: int = e.player_index
		var profile: Dictionary = ProfileManager.get_active_profile(pi)
		var result: String = ""
		if not profile.is_empty() and profile.has("name"):
			result = profile["name"]
		else:
			result = "P%d" % (pi + 1)
		var cls_name: String = PlayerHUD.CLASS_NAMES.get(e.character_class, "")
		if not cls_name.is_empty():
			result += " (%s)" % cls_name
		return result
	elif "entity_id" in e and not str(e.entity_id).is_empty():
		return str(e.entity_id)
	else:
		return e.name


func _cfg_get_entity_type(e: Node2D) -> String:
	## Returns type name for an entity.
	var is_player_entity: bool = "player_index" in e and "character_class" in e
	if is_player_entity:
		return "player"
	elif e.get_script():
		return e.get_script().resource_path.get_file().get_basename()
	return "unknown"


# -- Config sub-section input handling -----------------------------------------

func _handle_cfg_click(lx: float, my: float) -> void:
	## Route click to the appropriate config sub-section.
	if not _cfg_subsections_initialized:
		_init_cfg_subsections()
	var y: float = 0.0
	for i in range(_cfg_subsections.size()):
		var sub: Dictionary = _cfg_subsections[i]
		var header_end: float = y + SUB_HEADER_H

		# Click on header — collapse toggle or resize grip
		if my >= y and my < header_end:
			var pw: float = _content_width
			if lx < 16:
				sub["collapsed"] = not sub["collapsed"]
				_save_cfg_layout()
			elif lx > pw - 28 and i > 0:
				# Resize grip — double-click snaps, single click starts resize
				var target_idx: int = i - 1
				var now: float = Time.get_ticks_msec() / 1000.0
				if _cfg_grip_last_click_idx == target_idx and (now - _cfg_grip_last_click_time) < 0.4:
					var sub_above: Dictionary = _cfg_subsections[target_idx]
					var last_sub: Dictionary = _cfg_subsections[_cfg_subsections.size() - 1]
					var preferred: float = _get_cfg_preferred_height(sub_above["id"])
					var delta: float = preferred - sub_above["height"]
					sub_above["height"] = preferred
					last_sub["height"] -= delta
					_save_cfg_layout()
					_cfg_grip_last_click_idx = -1
					return
				_cfg_grip_last_click_idx = target_idx
				_cfg_grip_last_click_time = now
				_cfg_sub_resize_idx = target_idx
				_cfg_sub_resize_start_y = my
				_cfg_sub_resize_start_h = _cfg_subsections[target_idx]["height"]
				_cfg_sub_resize_next_h = _cfg_subsections[_cfg_subsections.size() - 1]["height"]
			return

		if sub["collapsed"]:
			y += SUB_HEADER_H
			continue

		var body_y: float = header_end
		var body_end: float = y + sub["height"]
		if sub["id"] == "cfg_modified_ents":
			body_end = maxf(body_end, 9999.0)  # Last section fills remaining space

		if my >= body_y and my < body_end:
			var local_y: float = my - body_y
			_handle_cfg_subsection_click(sub["id"], lx, local_y, body_end - body_y)
			return
		y += sub["height"]


func _handle_cfg_subsection_click(sub_id: String, lx: float, local_y: float, body_h: float) -> void:
	## Handle click within a specific config sub-section.
	match sub_id:
		"cfg_settings":
			_handle_cfg_settings_click(lx, local_y)
		"cfg_classes":
			_handle_cfg_classes_click(lx, local_y, body_h)
		"cfg_class":
			_handle_cfg_class_click(lx, local_y, body_h)
		"cfg_entities":
			_handle_cfg_entities_click(lx, local_y, body_h)
		"cfg_entity_stats":
			_handle_cfg_entity_stats_click(lx, local_y, body_h)
		"cfg_modifiers":
			_handle_cfg_blueprints_click(lx, local_y, body_h)
		"cfg_modified_ents":
			_handle_cfg_modified_ents_click(lx, local_y, body_h)


func _handle_cfg_classes_click(_lx: float, local_y: float, _body_h: float) -> void:
	## Click in classes list — select a class.
	var row_h: float = 16.0
	var all_classes: Array = PlayerHUD.ALL_CLASSES
	var extra_classes: Array[String] = ["spikeball", "shackle", "chain", "soccer_dummy", "monster"]
	# Player classes
	for i in range(all_classes.size()):
		if local_y >= i * row_h and local_y < (i + 1) * row_h:
			_cfg_selected_class = all_classes[i]
			_cfg_class_data.clear()  # Force reload on class change
			_cfg_class_data_name = ""
			return
	# Separator + physics entity classes
	var offset: float = all_classes.size() * row_h + 2
	for i in range(extra_classes.size()):
		if local_y >= offset + i * row_h and local_y < offset + (i + 1) * row_h:
			_cfg_selected_class = -100 - i  # Negative IDs for physics entities
			_cfg_class_data.clear()
			_cfg_class_data_name = ""
			return


func _handle_cfg_class_click(lx: float, local_y: float, _body_h: float) -> void:
	## Click in class editor — start slider drag.
	if _cfg_selected_class < 0 and _cfg_selected_class > -100:
		return
	var pw: float = _content_width
	var slider_h: float = 16.0
	var slider_gap: float = 2.0
	var row_idx: int = int(local_y / (slider_h + slider_gap))
	# Map row to key
	var cls_name: String = _cfg_resolve_class_name()
	if cls_name.is_empty():
		return
	_cfg_ensure_class_data(cls_name)
	var keys: Array = []
	for key in _cfg_class_data:
		keys.append(key)
	if row_idx < 0 or row_idx >= keys.size():
		return
	var key: String = keys[row_idx]
	# Check if click is on slider area
	if lx >= pw * 0.45 and lx < pw * 0.82:
		_cfg_class_dragging_key = key
		_cfg_class_drag_at(lx)


func _cfg_resolve_class_name() -> String:
	## Get the class name string for the currently selected class.
	var extra_classes: Array[String] = ["spikeball", "shackle", "chain", "soccer_dummy", "monster"]
	if _cfg_selected_class >= 0:
		return PlayerHUD.CLASS_NAMES.get(_cfg_selected_class, "").to_lower()
	elif _cfg_selected_class <= -100:
		var idx: int = -100 - _cfg_selected_class
		if idx >= 0 and idx < extra_classes.size():
			return extra_classes[idx]
	return ""


func _cfg_ensure_class_data(cls_name: String) -> void:
	## Load class data into cache if not already loaded.
	if _cfg_class_data_name == cls_name and not _cfg_class_data.is_empty():
		return
	_cfg_class_data.clear()
	_cfg_class_data_name = cls_name
	var MCP = load("res://scripts/systems/monster_config.gd")
	var provider = MCP.load_class_defaults(cls_name)
	if provider and "_data" in provider:
		_cfg_class_data = provider._data.duplicate()


func _cfg_class_drag_at(lx: float) -> void:
	## Set class default value based on slider position.
	if _cfg_class_dragging_key.is_empty() or _cfg_class_data.is_empty():
		return
	var pw: float = _content_width
	var slider_x: float = pw * 0.45
	var slider_w: float = pw * 0.35
	var t: float = clampf((lx - slider_x) / slider_w, 0.0, 1.0)
	var key: String = _cfg_class_dragging_key
	if not _cfg_class_data.has(key):
		return
	var current_val: float = float(_cfg_class_data[key])
	var range_info: Vector2 = _get_config_range(key, current_val)
	var new_val: float = lerpf(range_info.x, range_info.y, t)
	# Snap to nice values
	if absf(new_val) > 10.0:
		new_val = roundf(new_val)
	elif absf(new_val) > 1.0:
		new_val = roundf(new_val * 10.0) / 10.0
	else:
		new_val = roundf(new_val * 100.0) / 100.0
	_cfg_class_data[key] = new_val
	# Save to user overrides
	_cfg_save_class_override()
	# Update all entities of this class — reload their base config
	_cfg_apply_class_data_to_entities()
	_panel.queue_redraw()


func _cfg_save_class_override() -> void:
	## Save current class data edits to user://class_overrides/<class>.json.
	var cls_name: String = _cfg_class_data_name
	if cls_name.is_empty():
		return
	DirAccess.make_dir_recursive_absolute("user://class_overrides")
	var path: String = "user://class_overrides/%s.json" % cls_name
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_cfg_class_data, "  "))


func _cfg_apply_class_data_to_entities() -> void:
	## Push updated class data onto all entities that use this class.
	## Replaces the existing base config provider with the new data.
	var cls_name: String = _cfg_class_data_name
	if cls_name.is_empty():
		return
	var MCP = load("res://scripts/systems/monster_config.gd")
	var new_provider = MCP.DictProvider.new(_cfg_class_data.duplicate(), "%s_defaults" % cls_name)
	for entity in _get_all_entities():
		if not "_config_stack" in entity:
			continue
		# Find and replace the existing defaults provider
		for i in range(entity._config_stack.size()):
			var p = entity._config_stack[i]
			if "_name" in p and p._name == "%s_defaults" % cls_name:
				entity._config_stack[i] = new_provider
				break


func _handle_cfg_entity_stats_click(_lx: float, local_y: float, _body_h: float) -> void:
	## Click in entity stats table — select a stat for calculations.
	var header_h: float = 16.0  # Header + separator
	if local_y < header_h:
		return
	var row_h: float = 13.0
	var row_idx: int = int((local_y - header_h) / row_h)
	# Map row index to config key (skipping group headers)
	var key_idx: int = 0
	for key in _config_keys:
		if key.begins_with("# "):
			if key_idx == row_idx:
				return  # Clicked a group header, ignore
			key_idx += 1
			continue
		if key_idx == row_idx:
			_cfg_selected_stat = key
			_cfg_stat_cache_dirty = true
			return
		key_idx += 1


func _handle_cfg_modified_ents_click(_lx: float, local_y: float, _body_h: float) -> void:
	## Click in modified entities list — cross-select entity.
	if _cfg_selected_blueprint.is_empty():
		return
	var row_h: float = 14.0
	var idx: int = int(local_y / row_h)
	var bp_name: String = _cfg_selected_blueprint
	var match_idx: int = 0
	for entity in _get_all_entities():
		if not "_config_stack" in entity:
			continue
		for provider in entity._config_stack:
			if provider.has_method("is_modifier") and provider.is_modifier():
				if "_name" in provider and provider._name == bp_name:
					if match_idx == idx:
						# Cross-select: select this entity
						PlayerHUD.debug_select_entity(entity)
						DebugOverlay.set_observer("state_info/state_text_panel", "human", true, DebugOverlay.TextMode.NONE)
						DebugOverlay.set_observer("state_info/selection_indicator", "human", true, DebugOverlay.TextMode.NONE)
						_config_keys.clear()
						_cfg_selected_stat = ""
						return
					match_idx += 1
					break


func _handle_cfg_settings_click(_lx: float, local_y: float) -> void:
	## Click in game settings sub-section.
	if local_y >= 0 and local_y < 16:
		GameManager.multiple_players_same_class = not GameManager.multiple_players_same_class


func _handle_cfg_entities_click(lx: float, local_y: float, _body_h: float) -> void:
	## Click in entities sub-section — filter, entity list, or slider drag.
	var pw: float = _content_width
	var y: float = 0.0

	# Filter field (first 20px)
	if local_y >= y and local_y < y + 20:
		_config_filter_focused = true
		_cfg_bp_filter_focused = false
		_cfg_mod_filter_focused = false
		return
	y += 24

	# Entity list
	y += 2  # separator
	y += 16  # "Entities" header
	var entity_row_h: float = 16.0
	var entities: Array = _get_all_entities()

	for ei in range(entities.size()):
		if local_y >= y and local_y < y + entity_row_h:
			var e: Node2D = entities[ei]
			# Check "Mod+" button click
			if e.has_method("push_config") and not _cfg_cached_bp_names.is_empty():
				var mod_btn_x: float = pw - 90
				if lx >= mod_btn_x and lx <= mod_btn_x + 32:
					# Apply the selected blueprint to this entity
					if not _cfg_selected_blueprint.is_empty():
						_cfg_instantiate_blueprint(_cfg_selected_blueprint, e)
					return
			# Check "Tune" button click
			var btn_x: float = pw - 52
			if lx >= btn_x and lx <= btn_x + 34 and e.has_method("exec_tuning_toggle"):
				e.exec_tuning_toggle()
				return
			# Click on entity name — select it + clear stat selection
			PlayerHUD.debug_select_entity(e)
			DebugOverlay.set_observer("state_info/state_text_panel", "human", true, DebugOverlay.TextMode.NONE)
			DebugOverlay.set_observer("state_info/selection_indicator", "human", true, DebugOverlay.TextMode.NONE)
			_config_keys.clear()
			_cfg_selected_stat = ""
			_config_filter_focused = false
			return
		y += entity_row_h
	if entities.is_empty():
		y += entity_row_h
	y += 8

	_config_filter_focused = false

	# Entity info header
	y += 16

	# Slider area — for any entity with cfg()
	var cfg_entity: Node2D = _get_selected_entity()
	if not cfg_entity or not cfg_entity.has_method("cfg") or _config_keys.is_empty():
		return

	var slider_h: float = 16.0
	var slider_gap: float = 2.0
	var row: int = int((local_y - y) / (slider_h + slider_gap)) + _config_scroll_offset
	if row >= 0 and row < _config_keys.size():
		var key: String = _config_keys[row]
		if lx > pw * 0.47 and lx < pw * 0.82:
			_config_dragging_key = key
			_handle_config_drag_at(lx, cfg_entity)


func _handle_cfg_blueprints_click(lx: float, local_y: float, _body_h: float) -> void:
	## Click in blueprints sub-section — filter, list, buttons, or slider drag.
	var pw: float = _content_width
	var y: float = 0.0

	# Filter field (first 18px)
	if local_y >= y and local_y < y + 18:
		_cfg_bp_filter_focused = true
		_config_filter_focused = false
		_cfg_mod_filter_focused = false
		return
	y += 20

	# Blueprint list
	var filtered_bps: Array[String] = []
	if _cfg_bp_filter_text.is_empty():
		filtered_bps.assign(_cfg_cached_bp_names)
	else:
		var ft: String = _cfg_bp_filter_text.to_lower()
		for bp in _cfg_cached_bp_names:
			if ft in bp.to_lower():
				filtered_bps.append(bp)

	var row_h: float = 16.0
	var list_h: float = minf(_body_h * 0.45, filtered_bps.size() * row_h + 4.0)
	var visible: int = int(list_h / row_h)
	for bi in range(mini(visible, filtered_bps.size())):
		if local_y >= y and local_y < y + row_h:
			_cfg_selected_blueprint = filtered_bps[bi + _cfg_blueprints_scroll_offset]
			_cfg_bp_cached_data.clear()  # Force reload
			_cfg_bp_filter_focused = false
			return
		y += row_h
	if filtered_bps.is_empty():
		y += row_h

	y += 8  # gap + separator

	# Blueprint editor area
	if _cfg_selected_blueprint.is_empty():
		_cfg_bp_filter_focused = false
		return

	# Header row: blueprint name + [Apply] + [Shackle] + [Save]
	var sel_entity: Node2D = _get_selected_entity()

	# [Apply] button
	if sel_entity and sel_entity.has_method("push_config"):
		var apply_x: float = pw * 0.40
		if local_y >= y and local_y < y + 14 and lx >= apply_x and lx <= apply_x + 38:
			_cfg_instantiate_blueprint(_cfg_selected_blueprint, sel_entity)
			return

	# [Shackle] button
	if sel_entity and sel_entity.has_method("push_shackle_config"):
		var shk_x: float = pw * 0.53
		if local_y >= y and local_y < y + 14 and lx >= shk_x and lx <= shk_x + 44:
			# Instantiate blueprint as shackle modifier
			var data: Dictionary = _cfg_bp_cached_data.duplicate()
			var modifiers: Dictionary = {}
			for key in data:
				if key.begins_with("_"):
					continue
				var val = data[key]
				if val is Array and val.size() == 2:
					modifiers[key] = val
			if not modifiers.is_empty():
				var MCP = load("res://scripts/systems/monster_config.gd")
				var provider = MCP.ModifierProvider.new(modifiers, _cfg_selected_blueprint)
				sel_entity.push_shackle_config(provider)
			return

	# [Save] button
	var save_x: float = pw - 44
	if local_y >= y and local_y < y + 14 and lx >= save_x and lx <= save_x + 30:
		# Save cached data back to disk
		var save_data: Dictionary = _cfg_bp_cached_data.duplicate()
		save_data.erase("_bp_name")
		_cfg_save_blueprint(_cfg_selected_blueprint, save_data)
		return

	y += 18

	# Modifier rows — check for operation click or slider drag
	var slider_h: float = 16.0
	var slider_gap: float = 2.0
	var mod_keys: Array[String] = []
	for key in _cfg_bp_cached_data:
		if not key.begins_with("_"):
			mod_keys.append(key)

	for key in mod_keys:
		if local_y >= y and local_y < y + slider_h:
			# Click on operation badge? (pw*0.29 to pw*0.40)
			if lx >= pw * 0.29 and lx < pw * 0.40:
				_cfg_bp_cycle_operation(key)
				return
			# Click on slider? (pw*0.42 to pw*0.77)
			if lx >= pw * 0.42 and lx < pw * 0.77:
				_cfg_bp_dragging_key = key
				_cfg_bp_drag_at(lx)
				return
		y += slider_h + slider_gap

	_cfg_bp_filter_focused = false


func _handle_cfg_instances_click(lx: float, local_y: float, _body_h: float) -> void:
	## Click in instances sub-section — filter, list, or remove button.
	var pw: float = _content_width
	var y: float = 0.0

	# Filter field (first 18px)
	if local_y >= y and local_y < y + 18:
		_cfg_mod_filter_focused = true
		_config_filter_focused = false
		_cfg_bp_filter_focused = false
		return
	y += 20

	# Instance list
	var active_mods: Array = _cfg_get_active_modifiers()
	var filtered_mods: Array = []
	if _cfg_mod_filter_text.is_empty():
		filtered_mods = active_mods
	else:
		var ft: String = _cfg_mod_filter_text.to_lower()
		for mod in active_mods:
			if ft in mod["name"].to_lower() or ft in mod["entity_id"].to_lower():
				filtered_mods.append(mod)

	var row_h: float = 16.0
	for mi in range(filtered_mods.size()):
		if local_y >= y and local_y < y + row_h:
			# Check remove button [X]
			var rm_x: float = pw - 28
			if lx >= rm_x and lx <= rm_x + 16:
				# Remove modifier from the appropriate config stack
				var mod: Dictionary = filtered_mods[mi]
				var entity: Node2D = mod["entity"]
				if is_instance_valid(entity):
					if mod.get("stack", "entity") == "shackle" and entity.has_method("remove_shackle_config"):
						entity.remove_shackle_config(mod["provider"])
					elif entity.has_method("remove_config"):
						entity.remove_config(mod["provider"])
				return
			# Click on modifier — could select for inspection later
			return
		y += row_h
	_cfg_mod_filter_focused = false


func _handle_cfg_scroll(my: float, delta: int) -> void:
	## Route scroll to the appropriate config sub-section.
	if not _cfg_subsections_initialized:
		return
	var y: float = 0.0
	for i in range(_cfg_subsections.size()):
		var sub: Dictionary = _cfg_subsections[i]
		if sub["collapsed"]:
			y += SUB_HEADER_H
			continue
		var sub_end: float = y + sub["height"]
		if sub["id"] == "cfg_modified_ents":
			sub_end = 9999.0
		if my >= y and my < sub_end:
			match sub["id"]:
				"cfg_entities":
					_config_scroll_offset = maxi(0, _config_scroll_offset + delta)
				"cfg_blueprints":
					_cfg_blueprints_scroll_offset = maxi(0, _cfg_blueprints_scroll_offset + delta)
				"cfg_modified_ents":
					_cfg_instances_scroll_offset = maxi(0, _cfg_instances_scroll_offset + delta)
			return
		y += sub["height"]


func _handle_cfg_hover(my: float) -> void:
	## Update hover state for config sub-sections.
	_cfg_hover_entity_idx = -1
	_cfg_hover_blueprint_idx = -1
	_cfg_hover_instance_idx = -1
	if not _cfg_subsections_initialized:
		return
	var y: float = 0.0
	for i in range(_cfg_subsections.size()):
		var sub: Dictionary = _cfg_subsections[i]
		if sub["collapsed"]:
			y += SUB_HEADER_H
			continue
		var body_y: float = y + SUB_HEADER_H
		var sub_end: float = y + sub["height"]
		if sub["id"] == "cfg_modified_ents":
			sub_end = 9999.0
		if my >= body_y and my < sub_end:
			var local_y: float = my - body_y
			match sub["id"]:
				"cfg_entities":
					# Hover over entity list (after filter+header = 42px)
					var entity_local: float = local_y - 42
					if entity_local >= 0:
						_cfg_hover_entity_idx = int(entity_local / 16.0) + _cfg_entities_scroll_offset
				"cfg_blueprints":
					var bp_local: float = local_y - 20  # After filter
					if bp_local >= 0:
						_cfg_hover_blueprint_idx = int(bp_local / 16.0) + _cfg_blueprints_scroll_offset
				"cfg_modified_ents":
					var mod_local: float = local_y - 20  # After filter
					if mod_local >= 0:
						_cfg_hover_instance_idx = int(mod_local / 16.0) + _cfg_instances_scroll_offset
			return
		y += sub["height"]


func _handle_cfg_sub_resize_drag(my: float) -> void:
	## Handle drag to resize config sub-sections.
	if _cfg_sub_resize_idx < 0 or _cfg_sub_resize_idx >= _cfg_subsections.size():
		return
	var sub: Dictionary = _cfg_subsections[_cfg_sub_resize_idx]
	var last_sub: Dictionary = _cfg_subsections[_cfg_subsections.size() - 1]
	var delta: float = my - _cfg_sub_resize_start_y
	var new_h: float = _cfg_sub_resize_start_h + delta
	var new_next_h: float = _cfg_sub_resize_next_h - delta
	var min_h: float = CFG_SUB_MIN.get(sub["id"], 30.0)
	var min_next: float = CFG_SUB_MIN.get(last_sub["id"], 30.0)
	new_h = maxf(new_h, min_h)
	new_next_h = maxf(new_next_h, min_next)
	# Snap to preferred
	new_h = _snap_cfg_height(sub["id"], new_h)
	sub["height"] = new_h
	last_sub["height"] = new_next_h


func _handle_cfg_sub_resize_release() -> void:
	## Finalize config sub-section resize.
	_cfg_sub_resize_idx = -1
	_save_cfg_layout()


func _handle_cfg_text_input(event: InputEventKey) -> void:
	## Handle text input for config sub-section filter fields.
	if _cfg_bp_filter_focused:
		if event.keycode == KEY_BACKSPACE:
			if _cfg_bp_filter_text.length() > 0:
				_cfg_bp_filter_text = _cfg_bp_filter_text.substr(0, _cfg_bp_filter_text.length() - 1)
		elif event.keycode == KEY_ENTER or event.keycode == KEY_TAB or event.keycode == KEY_ESCAPE:
			_cfg_bp_filter_focused = false
		elif event.unicode > 0 and not event.ctrl_pressed:
			_cfg_bp_filter_text += char(event.unicode)
		return
	if _cfg_mod_filter_focused:
		if event.keycode == KEY_BACKSPACE:
			if _cfg_mod_filter_text.length() > 0:
				_cfg_mod_filter_text = _cfg_mod_filter_text.substr(0, _cfg_mod_filter_text.length() - 1)
		elif event.keycode == KEY_ENTER or event.keycode == KEY_TAB or event.keycode == KEY_ESCAPE:
			_cfg_mod_filter_focused = false
		elif event.unicode > 0 and not event.ctrl_pressed:
			_cfg_mod_filter_text += char(event.unicode)
		return


# ==============================================================================
# LEVEL EDITOR SECTION — sub-section framework (same pattern as test runner)
# ==============================================================================

func _get_level_editor() -> Node:
	## Get the level editor node from the scene tree.
	var scene := get_tree().current_scene
	if not scene:
		return null
	for node in scene.get_children():
		if node.get_script() and node.get_script().resource_path.ends_with("level_editor.gd"):
			return node
	return null


func _init_le_subsections() -> void:
	_le_subsections = []
	for sid in ["le_level", "le_modes", "le_items", "le_properties", "le_actions", "le_save"]:
		_le_subsections.append({
			"id": sid,
			"title": sid.substr(3).capitalize(),  # Strip "le_" prefix
			"collapsed": false,
			"height": _get_le_preferred_height(sid),
		})
	var had_le_layout: bool = FileAccess.file_exists("user://level_editor_layout.json")
	_load_le_layout()
	if not had_le_layout:
		_auto_snap_le()
	_le_subsections_initialized = true
	_le_rebuild_level_names()


func _load_le_layout() -> void:
	var path: String = "user://level_editor_layout.json"
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return
	var data: Dictionary = json.data
	for sub in _le_subsections:
		if data.has(sub["id"]):
			var sd: Dictionary = data[sub["id"]]
			sub["collapsed"] = sd.get("collapsed", sub["collapsed"])
			sub["height"] = sd.get("height", sub["height"])


func _save_le_layout() -> void:
	var data: Dictionary = {}
	for sub in _le_subsections:
		data[sub["id"]] = {"collapsed": sub["collapsed"], "height": sub["height"]}
	var file := FileAccess.open("user://level_editor_layout.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "  "))


func _auto_snap_le() -> void:
	if _le_subsections.is_empty():
		return
	var last_idx: int = _le_subsections.size() - 1
	var last_sub: Dictionary = _le_subsections[last_idx]
	for i in range(last_idx):
		var sub: Dictionary = _le_subsections[i]
		if sub["collapsed"]:
			continue
		var preferred: float = _get_le_preferred_height(sub["id"])
		var delta: float = preferred - sub["height"]
		sub["height"] = preferred
		last_sub["height"] -= delta
	var last_min: float = LE_SUB_MIN.get("le_save", 30.0)
	if last_sub["height"] < last_min:
		last_sub["height"] = last_min


func _get_le_preferred_height(sid: String) -> float:
	match sid:
		"le_level":
			var count: int = maxi(2, _le_cached_level_names.size())
			return SUB_HEADER_H + count * ROW_HEIGHT + 4.0
		"le_modes":
			return SUB_HEADER_H + LE_MODE_DISPLAY_NAMES.size() * ROW_HEIGHT + 4.0
		"le_items":
			var count: int = _le_get_item_count()
			return SUB_HEADER_H + clampi(count, 2, 10) * 16.0 + 4.0
		"le_properties":
			return SUB_HEADER_H + 6 * 18.0 + 4.0
		"le_actions":
			return SUB_HEADER_H + 6 * 18.0 + 4.0
		"le_save":
			return SUB_HEADER_H + 4 * 16.0 + 4.0
	return SUB_HEADER_H + 40.0


func _snap_le_height(sid: String, h: float) -> float:
	var preferred: float = _get_le_preferred_height(sid)
	if absf(h - preferred) < SUB_SNAP_DISTANCE:
		return preferred
	return h


# -- LE helpers ----------------------------------------------------------------

func _le_rebuild_level_names() -> void:
	## Scan res://levels/ for available level JSON files.
	_le_cached_level_names.clear()
	var dir := DirAccess.open("res://levels/")
	if dir:
		dir.list_dir_begin()
		var fname: String = dir.get_next()
		while fname != "":
			if fname.ends_with(".json"):
				_le_cached_level_names.append(fname.get_basename())
			fname = dir.get_next()
		dir.list_dir_end()
	_le_cached_level_names.sort()
	_le_level_names_dirty = false


func _le_get_current_level_name() -> String:
	var le: Node = _get_level_editor()
	if le and "_level_name" in le:
		return le._level_name
	return "title_screen"


func _le_load_level(level_name: String) -> void:
	## Load a level via RCON — rebuilds the world.
	var rcon: Node = get_node_or_null("/root/Rcon")
	if rcon:
		rcon._execute("level %s" % level_name)
	# If the level editor exists, update its config reference
	_le_ensure_editor_for_level(level_name)


func _le_ensure_editor_for_level(level_name: String) -> void:
	## Ensure the level editor exists and is configured for the given level.
	var scene: Node = get_tree().current_scene
	if not scene:
		return
	var le: Node = _get_level_editor()
	if le:
		# Update existing editor with new level
		var config: Dictionary = LevelConfig.load_level(level_name)
		if not config.is_empty():
			le.setup(level_name, config)
		return
	# Create the level editor (same pattern as title_screen._toggle_editor)
	var editor_script: GDScript = load("res://scripts/ui/level_editor.gd")
	le = CanvasLayer.new()
	le.set_script(editor_script)
	var config: Dictionary = LevelConfig.load_level(level_name)
	le.setup(level_name, config)
	if scene.has_method("_rebuild_from_config"):
		le.config_changed.connect(scene._rebuild_from_config)
	scene.add_child(le)


func _le_get_mode() -> int:
	## Get the display mode index (0=Gameplay, 1+=editor modes).
	return _le_active_display_mode


func _le_set_mode(display_idx: int) -> void:
	## Set the active display mode. 0=Gameplay (no editing), 1+=editor modes.
	_le_active_display_mode = display_idx
	_le_items_scroll_offset = 0

	if display_idx <= 0 or display_idx >= LE_MODE_MAP.size():
		# Gameplay — deactivate level editor overlay
		var le: Node = _get_level_editor()
		if le and "_active" in le and le._active:
			le._active = false
			le.visible = false
			if le._overlay:
				le._overlay.visible = false
		return

	# Editor mode — map display index to level_editor.gd Mode value
	var editor_mode: int = LE_MODE_MAP[display_idx]
	var le: Node = _get_level_editor()
	if not le:
		# Auto-create the level editor
		_le_ensure_editor_for_level(_le_get_current_level_name())
		le = _get_level_editor()
	if le:
		if not le._active:
			le._active = true
			le.visible = true
			if le._overlay:
				le._overlay.visible = true
		le._mode = editor_mode
		le._selected_idx = -1
		if le.has_method("_update_display"):
			le._update_display()


func _le_get_selected_idx() -> int:
	var le: Node = _get_level_editor()
	if le and "_selected_idx" in le:
		return le._selected_idx
	return -1


func _le_get_config() -> Dictionary:
	var le: Node = _get_level_editor()
	if le and "_config" in le:
		return le._config
	return {}


func _le_get_editor_mode_value() -> int:
	## Map display mode to level_editor.gd Mode enum value. -1 = gameplay.
	if _le_active_display_mode <= 0 or _le_active_display_mode >= LE_MODE_MAP.size():
		return -1
	return LE_MODE_MAP[_le_active_display_mode]


func _le_get_item_count() -> int:
	var config: Dictionary = _le_get_config()
	if config.is_empty():
		return 0
	match _le_get_editor_mode_value():
		0:  # SPAWN_AREAS
			var total: int = 0
			for key in config.get("spawn_zones", {}):
				total += (config["spawn_zones"][key] as Array).size()
			return total
		1: return config.get("spawn_positions", []).size()
		2: return config.get("scenery", {}).get("trees", []).size() + config.get("scenery", {}).get("rocks", []).size()
		3: return config.get("platforms", []).size()
		4: return 1 if config.has("portal") else 0
		5:
			var total: int = 0
			for p in config.get("migration_patterns", []):
				for phase in p.get("phases", []):
					total += phase.get("zones", []).size()
			return total
		6: return config.get("splays", []).size()
	return 0


func _le_get_item_count_for_mode(mode: int) -> int:
	var config: Dictionary = _le_get_config()
	if config.is_empty():
		return 0
	match mode:
		0:
			var total: int = 0
			for key in config.get("spawn_zones", {}):
				total += (config["spawn_zones"][key] as Array).size()
			return total
		1: return config.get("spawn_positions", []).size()
		2: return config.get("scenery", {}).get("trees", []).size() + config.get("scenery", {}).get("rocks", []).size()
		3: return config.get("platforms", []).size()
		4: return 1 if config.has("portal") else 0
		5:
			var total: int = 0
			for p in config.get("migration_patterns", []):
				total += p.get("phases", []).size()
			return total
		6: return config.get("splays", []).size()
	return 0


func _le_build_item_list() -> Array:
	## Build a flat list of {label, color, idx, zone_type?} for the current mode.
	var config: Dictionary = _le_get_config()
	var mode: int = _le_get_editor_mode_value()
	var items: Array = []
	if config.is_empty():
		return items
	match mode:
		0:
			for key in ["fireflies", "bats"]:
				var zone_list: Array = config.get("spawn_zones", {}).get(key, [])
				var zcol: Color = Color(1.0, 0.9, 0.2) if key == "fireflies" else Color(0.7, 0.2, 0.9)
				for i in range(zone_list.size()):
					var r: Array = zone_list[i].get("rect", [0, 0, 100, 100])
					items.append({"label": "%s #%d  (%d,%d)" % [key.substr(0, 2).to_upper(), i+1, int(r[0]), int(r[1])], "color": zcol, "idx": i, "zone_type": key})
		1:
			for i in range(config.get("spawn_positions", []).size()):
				var p: Array = config["spawn_positions"][i]
				items.append({"label": "P%d  (%d, %d)" % [i+1, int(p[0]), int(p[1])], "color": Color(0.2, 0.9, 1.0), "idx": i})
		2:
			var trees: Array = config.get("scenery", {}).get("trees", [])
			for i in range(trees.size()):
				var p: Array = trees[i].get("pos", [0, 0])
				items.append({"label": "Tree #%d  seed:%d" % [i+1, int(trees[i].get("seed", 0))], "color": Color(0.3, 0.8, 0.4), "idx": i})
			var rocks: Array = config.get("scenery", {}).get("rocks", [])
			for i in range(rocks.size()):
				items.append({"label": "Rock #%d  seed:%d" % [i+1, int(rocks[i].get("seed", 0))], "color": Color(0.8, 0.7, 0.4), "idx": i})
		3:
			for i in range(config.get("platforms", []).size()):
				var p: Array = config["platforms"][i].get("pos", [0, 0])
				var w: float = config["platforms"][i].get("width", 200)
				items.append({"label": "Plat %d  (%d,%d) w:%d" % [i+1, int(p[0]), int(p[1]), int(w)], "color": Color(0.4, 0.6, 1.0), "idx": i})
		4:
			var portal: Dictionary = config.get("portal", {})
			var p: Array = portal.get("pos", [960, 880])
			items.append({"label": "Portal  (%d,%d)" % [int(p[0]), int(p[1])], "color": Color(0.9, 0.3, 0.9), "idx": 0})
		5:
			for pi in range(config.get("migration_patterns", []).size()):
				var pattern: Dictionary = config["migration_patterns"][pi]
				var species: String = str(pattern.get("species", "?"))
				for phi in range(pattern.get("phases", []).size()):
					var zones: Array = pattern["phases"][phi].get("zones", [])
					for zi in range(zones.size()):
						items.append({"label": "%s P%d Z%d" % [species, phi+1, int(zones[zi].get("zone_id", 0))], "color": Color(0.3, 0.5, 1.0), "idx": zi})
		6:
			for i in range(config.get("splays", []).size()):
				var s: Dictionary = config["splays"][i]
				items.append({"label": "%s  %s  x%.1f" % [s.get("pose", "?"), s.get("behavior", "?"), s.get("scale", 1.0)], "color": Color(0.9, 0.4, 0.2), "idx": i})
	return items


func _le_get_properties() -> Array:
	## Returns Array of {key, label, value, type, editable, min?, max?}.
	var config: Dictionary = _le_get_config()
	var le: Node = _get_level_editor()
	var sel: int = _le_get_selected_idx()
	var props: Array = []
	if sel < 0 or config.is_empty():
		return props
	match _le_get_editor_mode_value():
		1:
			var positions: Array = config.get("spawn_positions", [])
			if sel < positions.size():
				props.append({"key": "x", "label": "X", "value": positions[sel][0], "type": "number", "editable": true})
				props.append({"key": "y", "label": "Y", "value": positions[sel][1], "type": "number", "editable": true})
		3:
			var platforms: Array = config.get("platforms", [])
			if sel < platforms.size():
				props.append({"key": "x", "label": "X", "value": platforms[sel]["pos"][0], "type": "number", "editable": true})
				props.append({"key": "y", "label": "Y", "value": platforms[sel]["pos"][1], "type": "number", "editable": true})
				props.append({"key": "width", "label": "Width", "value": platforms[sel].get("width", 200), "type": "slider", "editable": true, "min": 50.0, "max": 800.0})
		4:
			var portal: Dictionary = config.get("portal", {})
			props.append({"key": "x", "label": "X", "value": portal.get("pos", [960, 880])[0], "type": "number", "editable": true})
			props.append({"key": "y", "label": "Y", "value": portal.get("pos", [960, 880])[1], "type": "number", "editable": true})
			props.append({"key": "range", "label": "Range", "value": portal.get("activation_range", 100), "type": "slider", "editable": true, "min": 20.0, "max": 400.0})
		6:
			var splays: Array = config.get("splays", [])
			if sel < splays.size():
				var s: Dictionary = splays[sel]
				props.append({"key": "x", "label": "X", "value": s.get("pos", [960, 500])[0], "type": "number", "editable": true})
				props.append({"key": "y", "label": "Y", "value": s.get("pos", [960, 500])[1], "type": "number", "editable": true})
				props.append({"key": "rotation", "label": "Rotation", "value": s.get("rotation", 0), "type": "slider", "editable": true, "min": -180.0, "max": 180.0})
				props.append({"key": "scale", "label": "Scale", "value": s.get("scale", 1.0), "type": "slider", "editable": true, "min": 0.25, "max": 8.0})
				props.append({"key": "pose", "label": "Pose", "value": s.get("pose", ""), "type": "text", "editable": false})
				props.append({"key": "behavior", "label": "Behavior", "value": s.get("behavior", ""), "type": "text", "editable": false})
	return props


func _le_get_current_actions() -> Array:
	## Return the action list for the current mode.
	var actions: Array = []
	if _le_active_display_mode == 0:
		# Gameplay mode — show gameplay actions + always actions
		actions.append_array(LE_ACTIONS_GAMEPLAY)
	actions.append_array(LE_ACTIONS_ALWAYS)
	return actions


func _le_get_action_buttons() -> Array:
	## Returns Array of [label, color, action_id] for the current mode.
	match _le_get_editor_mode_value():
		2: return [  # Seeds (trees)
			["+Tree", Color(0.3, 0.8, 0.3), "tree_add"],
			["Del", Color(0.8, 0.3, 0.3), "tree_delete"],
			["Type", Color(0.3, 0.6, 1.0), "tree_cycle_blueprint"],
			["Seed", Color(0.8, 0.6, 0.3), "tree_randomize_seed"],
		]
		5: return [  # Migration
			["+Phase", Color(0.3, 0.8, 0.3), "mig_add_phase"],
			["-Phase", Color(0.8, 0.3, 0.3), "mig_del_phase"],
			["+Zone", Color(0.3, 0.6, 1.0), "mig_add_zone"],
			["Species", Color(0.8, 0.6, 0.3), "mig_cycle_species"],
		]
		6: return [  # Splay
			["Add", Color(0.3, 0.8, 0.3), "splay_add"],
			["Del", Color(0.8, 0.3, 0.3), "splay_delete"],
			["Pose", Color(0.3, 0.6, 1.0), "splay_cycle_pose"],
			["Bhvr", Color(0.8, 0.6, 0.3), "splay_cycle_behavior"],
			["Lib", Color(0.6, 0.4, 0.8), "splay_library"],
		]
	return []


func _le_execute_action(action: String) -> void:
	var le: Node = _get_level_editor()
	if not le:
		return
	match action:
		"tree_add":
			_le_tree_add()
		"tree_delete":
			_le_tree_delete()
		"tree_cycle_blueprint":
			_le_tree_cycle_blueprint()
		"tree_randomize_seed":
			_le_tree_randomize_seed()
		"mig_add_phase": if le.has_method("_migration_add_phase"): le._migration_add_phase()
		"mig_del_phase": if le.has_method("_migration_delete_last_phase"): le._migration_delete_last_phase()
		"mig_add_zone": if le.has_method("_migration_add_zone"): le._migration_add_zone()
		"mig_cycle_species": if le.has_method("_migration_cycle_species"): le._migration_cycle_species()
		"splay_add": if le.has_method("_splay_add_instance"): le._splay_add_instance()
		"splay_delete": if le.has_method("_splay_delete_selected"): le._splay_delete_selected()
		"splay_cycle_pose": if le.has_method("_splay_cycle_pose"): le._splay_cycle_pose(1)
		"splay_cycle_behavior": if le.has_method("_splay_cycle_behavior"): le._splay_cycle_behavior()
		"splay_library": if le.has_method("_splay_open_library"): le._splay_open_library()


func _le_tree_add() -> void:
	## Add a new tree to the level config with default blueprint.
	var config: Dictionary = _le_get_config()
	if not config.has("scenery"):
		config["scenery"] = {}
	if not config["scenery"].has("trees"):
		config["scenery"]["trees"] = []
	var trees: Array = config["scenery"]["trees"]
	var blueprints: Array[String] = _ct_get_tree_blueprint_names()
	var bp_name: String = blueprints[0] if not blueprints.is_empty() else "oak"
	trees.append({
		"pos": [960, 900],
		"seed": randi(),
		"blueprint": bp_name,
		"trunk_weight": 20.0,
		"trunk_length": 200.0,
	})
	var le: Node = _get_level_editor()
	if le:
		le._selected_idx = trees.size() - 1
		le._drag_item_type = "tree"
		le.config_changed.emit(config)
		le._update_display()


func _le_tree_delete() -> void:
	## Delete the selected tree from the level config.
	var le: Node = _get_level_editor()
	if not le:
		return
	var sel: int = le._selected_idx
	var config: Dictionary = _le_get_config()
	var trees: Array = config.get("scenery", {}).get("trees", [])
	if sel >= 0 and sel < trees.size():
		trees.remove_at(sel)
		le._selected_idx = -1
		le.config_changed.emit(config)
		le._update_display()


func _le_tree_cycle_blueprint() -> void:
	## Cycle the selected tree through available blueprints.
	var le: Node = _get_level_editor()
	if not le:
		return
	var sel: int = le._selected_idx
	var config: Dictionary = _le_get_config()
	var trees: Array = config.get("scenery", {}).get("trees", [])
	if sel < 0 or sel >= trees.size():
		return
	var blueprints: Array[String] = _ct_get_tree_blueprint_names()
	if blueprints.is_empty():
		return
	var current_bp: String = trees[sel].get("blueprint", "")
	var idx: int = blueprints.find(current_bp)
	var next_idx: int = (idx + 1) % blueprints.size()
	trees[sel]["blueprint"] = blueprints[next_idx]
	le.config_changed.emit(config)


func _le_tree_randomize_seed() -> void:
	## Assign a new random seed to the selected tree.
	var le: Node = _get_level_editor()
	if not le:
		return
	var sel: int = le._selected_idx
	var config: Dictionary = _le_get_config()
	var trees: Array = config.get("scenery", {}).get("trees", [])
	if sel >= 0 and sel < trees.size():
		trees[sel]["seed"] = randi()
		le.config_changed.emit(config)


func _ct_get_tree_blueprint_names() -> Array[String]:
	## Scan tree_blueprints directories for available blueprint JSON files.
	var TreeScript: GDScript = load("res://scripts/effects/procedural_tree.gd")
	return TreeScript.get_blueprint_names()


func _le_execute_scene_action(cmd: String) -> void:
	var rcon: Node = get_node_or_null("/root/Rcon")
	if not rcon:
		return
	match cmd:
		"spawn_standdown":
			rcon._execute("spawn monster 670 520")
			rcon._execute("standdown on")
			_le_scene_flash = "Spawned monster (standdown)"
		"spawn_active":
			rcon._execute("spawn monster 960 880")
			_le_scene_flash = "Spawned monster"
		"spawn_dummy":
			rcon._execute("spawn dummy 960 880")
			_le_scene_flash = "Spawned dummy"
		"monster_fight":
			rcon._execute("clear")
			rcon._execute("clearplayers")
			rcon._execute("spawn monster 400 880")
			rcon._execute("spawn monster 1500 880")
			rcon._execute("territorial on")
			_le_scene_flash = "Monster fight!"
		"kill":
			rcon._execute("kill")
			_le_scene_flash = "Killed all"
		"clear":
			rcon._execute("clear")
			_le_scene_flash = "Cleared"
		"territorial":
			rcon._execute("territorial")
			_le_scene_flash = "Toggled territorial"
		"revive":
			rcon._execute("revive")
			_le_scene_flash = "Revived"
		"enable_joins":
			rcon._execute("enablejoins")
			_le_scene_flash = "Joins enabled"
		"clear_level":
			rcon._execute("clear")
			rcon._execute("clearplayers")
			rcon._execute("enablejoins")
			_le_scene_flash = "Level cleared"
		"restart_level":
			get_tree().reload_current_scene()
			return
	_le_scene_flash_timer = 2.0


func _le_select_item(idx: int) -> void:
	## Translate flat list index into correct selection in the level editor.
	var le: Node = _get_level_editor()
	if not le:
		return
	var config: Dictionary = _le_get_config()
	var mode: int = _le_get_editor_mode_value()
	le._selected_idx = -1  # Reset first
	match mode:
		0:
			var flat: int = 0
			for key in ["fireflies", "bats"]:
				var zone_list: Array = config.get("spawn_zones", {}).get(key, [])
				for i in range(zone_list.size()):
					if flat == idx:
						le._selected_idx = i
						le._drag_item_type = key + "_zone"
						return
					flat += 1
		1:
			if idx >= 0 and idx < config.get("spawn_positions", []).size():
				le._selected_idx = idx
				le._drag_item_type = "spawn_position"
		2:
			var trees: Array = config.get("scenery", {}).get("trees", [])
			var rocks: Array = config.get("scenery", {}).get("rocks", [])
			if idx < trees.size():
				le._selected_idx = idx
				le._drag_item_type = "tree"
			elif idx - trees.size() < rocks.size():
				le._selected_idx = idx - trees.size()
				le._drag_item_type = "rock"
		3:
			if idx >= 0 and idx < config.get("platforms", []).size():
				le._selected_idx = idx
				le._drag_item_type = "platform"
		4:
			le._selected_idx = 0
			le._drag_item_type = "portal"
		6:
			if idx >= 0 and idx < config.get("splays", []).size():
				le._selected_idx = idx
				le._drag_item_type = "splay_move"


# -- LE click handlers ---------------------------------------------------------

func _handle_le_click(lx: float, my: float) -> void:
	if not _le_subsections_initialized:
		_init_le_subsections()
	var y: float = 0.0
	for i in range(_le_subsections.size()):
		var sub: Dictionary = _le_subsections[i]
		var header_end: float = y + SUB_HEADER_H

		if my >= y and my < header_end:
			var pw: float = _content_width
			if lx < 16:
				sub["collapsed"] = not sub["collapsed"]
				_save_le_layout()
			elif lx > pw - 28 and i > 0:
				var target_idx: int = i - 1
				var now: float = Time.get_ticks_msec() / 1000.0
				if _le_grip_last_click_idx == target_idx and (now - _le_grip_last_click_time) < 0.4:
					var sub_above: Dictionary = _le_subsections[target_idx]
					var last_sub: Dictionary = _le_subsections[_le_subsections.size() - 1]
					var preferred: float = _get_le_preferred_height(sub_above["id"])
					var delta: float = preferred - sub_above["height"]
					sub_above["height"] = preferred
					last_sub["height"] -= delta
					_save_le_layout()
					_le_grip_last_click_idx = -1
					return
				_le_grip_last_click_idx = target_idx
				_le_grip_last_click_time = now
				_le_sub_resize_idx = target_idx
				_le_sub_resize_start_y = my
				_le_sub_resize_start_h = _le_subsections[target_idx]["height"]
				_le_sub_resize_next_h = _le_subsections[_le_subsections.size() - 1]["height"]
			return

		if sub["collapsed"]:
			y += SUB_HEADER_H
			continue

		var body_y: float = header_end
		var body_end: float = y + sub["height"]
		if sub["id"] == "le_save":
			body_end = maxf(body_end, 9999.0)

		if my >= body_y and my < body_end:
			var local_y: float = my - body_y
			_handle_le_subsection_click(sub["id"], lx, local_y, body_end - body_y)
			return
		y += sub["height"]


func _handle_le_subsection_click(sub_id: String, lx: float, local_y: float, _body_h: float) -> void:
	match sub_id:
		"le_level":
			var idx: int = int(local_y / ROW_HEIGHT) + _le_level_scroll_offset
			if idx >= 0 and idx < _le_cached_level_names.size():
				_le_load_level(_le_cached_level_names[idx])
		"le_modes":
			var idx: int = int(local_y / ROW_HEIGHT)
			if idx >= 0 and idx < LE_MODE_DISPLAY_NAMES.size():
				_le_set_mode(idx)
		"le_items":
			var idx: int = int(local_y / 16.0) + _le_items_scroll_offset
			_le_select_item(idx)
		"le_properties":
			_handle_le_properties_click(lx, local_y)
		"le_actions":
			_handle_le_actions_click(lx, local_y)
		"le_save":
			_handle_le_save_click(lx, local_y)


func _handle_le_properties_click(lx: float, local_y: float) -> void:
	var props: Array = _le_get_properties()
	var row_h: float = 18.0
	var idx: int = int(local_y / row_h) + _le_properties_scroll_offset
	if idx < 0 or idx >= props.size():
		_le_prop_edit_focused = false
		return
	var prop: Dictionary = props[idx]
	var pw: float = _content_width
	if lx > pw * 0.45 and prop.get("editable", false):
		if prop.get("type", "") == "slider":
			_le_prop_dragging_key = prop["key"]
			_handle_le_prop_drag_at(lx)
		else:
			_le_prop_edit_key = prop["key"]
			_le_prop_edit_text = str(prop.get("value", ""))
			_le_prop_edit_cursor = _le_prop_edit_text.length()
			_le_prop_edit_focused = true


func _handle_le_actions_click(lx: float, local_y: float) -> void:
	## Click on an action row. Actions depend on mode.
	var actions: Array = _le_get_current_actions()
	var row_h: float = 18.0
	var y: float = 0.0

	# Mode-specific button bar (if any)
	var action_btns: Array = _le_get_action_buttons()
	if not action_btns.is_empty():
		var btn_h: float = 24.0
		if local_y < btn_h:
			var pw: float = _content_width
			var bw: float = (pw - 24.0) / float(action_btns.size())
			var btn_idx: int = int((lx - 8.0) / bw)
			if btn_idx >= 0 and btn_idx < action_btns.size():
				_le_execute_action(action_btns[btn_idx][2])
			return
		y += btn_h + 4

	# Action list
	for i in range(actions.size()):
		var action: Dictionary = actions[i]
		if action["cmd"] == "":
			y += 16  # separator
			continue
		if local_y >= y and local_y < y + row_h:
			_le_execute_scene_action(action["cmd"])
			return
		y += row_h


func _handle_le_save_click(lx: float, local_y: float) -> void:
	var le: Node = _get_level_editor()
	if not le:
		return
	var pw: float = _content_width
	var btn_y: float = 18.0  # After summary line
	var btn_h: float = 22.0
	if local_y >= btn_y and local_y < btn_y + btn_h:
		if lx < pw * 0.48 and Version.is_source_mode():
			if le.has_method("_save_original"):
				le._save_original()
		elif lx >= pw * 0.5:
			if le.has_method("_save"):
				le._save()


# -- LE scroll/resize ----------------------------------------------------------

func _handle_le_scroll(my: float, delta: int) -> void:
	if not _le_subsections_initialized:
		return
	var y: float = 0.0
	for sub in _le_subsections:
		if sub["collapsed"]:
			y += SUB_HEADER_H
			continue
		var body_y: float = y + SUB_HEADER_H
		var body_end: float = y + sub["height"]
		if sub["id"] == "le_save":
			body_end = maxf(body_end, 9999.0)
		if my >= y and my < body_end:
			match sub["id"]:
				"le_level": _le_level_scroll_offset = maxi(0, _le_level_scroll_offset + delta)
				"le_items": _le_items_scroll_offset = maxi(0, _le_items_scroll_offset + delta)
				"le_properties": _le_properties_scroll_offset = maxi(0, _le_properties_scroll_offset + delta)
				"le_actions": pass
			return
		y += sub["height"]


func _handle_le_sub_resize_drag(my: float) -> void:
	if _le_sub_resize_idx < 0 or _le_sub_resize_idx >= _le_subsections.size():
		return
	var dy: float = my - _le_sub_resize_start_y
	var sub: Dictionary = _le_subsections[_le_sub_resize_idx]
	var last_sub: Dictionary = _le_subsections[_le_subsections.size() - 1]
	var min_h: float = LE_SUB_MIN.get(sub["id"], 30.0)
	var last_min: float = LE_SUB_MIN.get(last_sub["id"], 30.0)
	dy = clampf(dy, min_h - _le_sub_resize_start_h, _le_sub_resize_next_h - last_min)
	sub["height"] = _le_sub_resize_start_h + dy
	last_sub["height"] = _le_sub_resize_next_h - (sub["height"] - _le_sub_resize_start_h)


func _handle_le_sub_resize_release() -> void:
	if _le_sub_resize_idx < 0 or _le_sub_resize_idx >= _le_subsections.size():
		return
	var sub: Dictionary = _le_subsections[_le_sub_resize_idx]
	var last_sub: Dictionary = _le_subsections[_le_subsections.size() - 1]
	var snapped: float = _snap_le_height(sub["id"], sub["height"])
	if snapped != sub["height"]:
		var delta: float = snapped - sub["height"]
		sub["height"] = snapped
		last_sub["height"] -= delta


func _handle_le_hover(my: float) -> void:
	_le_hover_mode_idx = -1
	_le_hover_item_idx = -1
	_le_scene_hover_idx = -1
	_le_hover_level_idx = -1
	if not _le_subsections_initialized:
		return
	var y: float = 0.0
	for sub in _le_subsections:
		if sub["collapsed"]:
			y += SUB_HEADER_H
			continue
		var body_y: float = y + SUB_HEADER_H
		var body_end: float = y + sub["height"]
		if sub["id"] == "le_save":
			body_end = maxf(body_end, 9999.0)
		if my >= body_y and my < body_end:
			var local_y: float = my - body_y
			match sub["id"]:
				"le_level": _le_hover_level_idx = int(local_y / ROW_HEIGHT) + _le_level_scroll_offset
				"le_modes": _le_hover_mode_idx = int(local_y / ROW_HEIGHT)
				"le_items": _le_hover_item_idx = int(local_y / 16.0) + _le_items_scroll_offset
				"le_actions":
					var sy: float = 0.0
					var action_btns: Array = _le_get_action_buttons()
					if not action_btns.is_empty():
						sy += 28.0
					var actions: Array = _le_get_current_actions()
					var aidx: int = 0
					for ai in range(actions.size()):
						if actions[ai]["cmd"] == "":
							sy += 18
							continue
						if local_y >= sy and local_y < sy + 18:
							_le_scene_hover_idx = aidx
						sy += 18
						aidx += 1
			return
		y += sub["height"]


# -- LE property editing -------------------------------------------------------

func _handle_le_prop_edit_key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_ENTER:
			_apply_le_prop_edit()
		KEY_ESCAPE:
			_le_prop_edit_focused = false
			_le_prop_edit_key = ""
		KEY_BACKSPACE:
			if _le_prop_edit_cursor > 0:
				_le_prop_edit_text = _le_prop_edit_text.substr(0, _le_prop_edit_cursor - 1) + _le_prop_edit_text.substr(_le_prop_edit_cursor)
				_le_prop_edit_cursor -= 1
		KEY_LEFT:
			_le_prop_edit_cursor = maxi(0, _le_prop_edit_cursor - 1)
		KEY_RIGHT:
			_le_prop_edit_cursor = mini(_le_prop_edit_text.length(), _le_prop_edit_cursor + 1)
		_:
			if event.unicode > 0 and not event.ctrl_pressed:
				var ch := char(event.unicode)
				_le_prop_edit_text = _le_prop_edit_text.substr(0, _le_prop_edit_cursor) + ch + _le_prop_edit_text.substr(_le_prop_edit_cursor)
				_le_prop_edit_cursor += 1


func _apply_le_prop_edit() -> void:
	if _le_prop_edit_key.is_empty():
		_le_prop_edit_focused = false
		return
	_le_set_property(_le_prop_edit_key, _le_prop_edit_text.to_float())
	_le_prop_edit_focused = false
	_le_prop_edit_key = ""


func _handle_le_prop_drag(mx: float) -> void:
	var lx: float = mx - _panel_x - ICON_BAR_WIDTH - 4
	_handle_le_prop_drag_at(lx)


func _handle_le_prop_drag_at(lx: float) -> void:
	var pw: float = _content_width
	var slider_x: float = pw * 0.47
	var slider_w: float = pw * 0.35
	var t: float = clampf((lx - slider_x) / slider_w, 0.0, 1.0)
	for prop in _le_get_properties():
		if prop["key"] == _le_prop_dragging_key:
			var new_val: float = lerpf(prop.get("min", 0.0), prop.get("max", 1000.0), t)
			_le_set_property(_le_prop_dragging_key, new_val)
			return


func _le_set_property(key: String, value: float) -> void:
	var config: Dictionary = _le_get_config()
	var le: Node = _get_level_editor()
	var sel: int = _le_get_selected_idx()
	if sel < 0 or not le:
		return
	match _le_get_editor_mode_value():
		1:
			var positions: Array = config.get("spawn_positions", [])
			if sel < positions.size():
				match key:
					"x": positions[sel][0] = value
					"y": positions[sel][1] = value
		3:
			var platforms: Array = config.get("platforms", [])
			if sel < platforms.size():
				match key:
					"x": platforms[sel]["pos"][0] = value
					"y": platforms[sel]["pos"][1] = value
					"width": platforms[sel]["width"] = value
		4:
			var portal: Dictionary = config.get("portal", {})
			match key:
				"x": portal["pos"][0] = value
				"y": portal["pos"][1] = value
				"range": portal["activation_range"] = value
		6:
			var splays: Array = config.get("splays", [])
			if sel < splays.size():
				match key:
					"x": splays[sel]["pos"][0] = value
					"y": splays[sel]["pos"][1] = value
					"rotation": splays[sel]["rotation"] = value
					"scale": splays[sel]["scale"] = clampf(value, 0.25, 8.0)
	le.config_changed.emit(config)


# -- LE drawing ----------------------------------------------------------------

func _draw_level_editor_section(content_x: float, font: Font, ph: float) -> void:
	if not _le_subsections_initialized:
		_init_le_subsections()

	var x: float = content_x
	var pw: float = _content_width
	var y: float = 0.0

	for si in range(_le_subsections.size()):
		var sub: Dictionary = _le_subsections[si]
		if y > ph:
			break

		_draw_le_sub_header(x, y, pw, font, sub)

		if sub["collapsed"]:
			y += SUB_HEADER_H
			continue

		var body_y: float = y + SUB_HEADER_H
		var body_h: float
		if sub["id"] == "le_save":
			body_h = maxf(LE_SUB_MIN["le_save"] - SUB_HEADER_H, ph - body_y)
		else:
			body_h = sub["height"] - SUB_HEADER_H

		if body_h > 0:
			match sub["id"]:
				"le_level":      _draw_le_sub_level(x, body_y, pw, body_h, font)
				"le_modes":      _draw_le_sub_modes(x, body_y, pw, body_h, font)
				"le_items":      _draw_le_sub_items(x, body_y, pw, body_h, font)
				"le_properties": _draw_le_sub_properties(x, body_y, pw, body_h, font)
				"le_actions":    _draw_le_sub_actions(x, body_y, pw, body_h, font)
				"le_save":       _draw_le_sub_save(x, body_y, pw, body_h, font)

		# Snap indicator during resize
		if _le_sub_resize_idx == si and sub["id"] != "le_save":
			var snap_h: float = _get_le_preferred_height(sub["id"])
			var snap_y: float = y + snap_h
			var near_snap: bool = absf(sub["height"] - snap_h) < SUB_SNAP_DISTANCE
			var snap_col := Color(0.9, 0.6, 0.2, 0.6) if near_snap else Color(0.9, 0.6, 0.2, 0.25)
			var dx: float = 0.0
			while dx < pw - 16:
				_panel.draw_line(Vector2(x + dx, snap_y), Vector2(x + minf(dx + 6.0, pw - 16), snap_y), snap_col, 1.0)
				dx += 10.0
			if near_snap:
				_panel.draw_string(font, Vector2(x + pw - 40, snap_y - 3), "snap", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, snap_col)

		if sub["id"] == "le_save":
			y += body_h + SUB_HEADER_H
		else:
			y += sub["height"]

		if sub["id"] != "le_save":
			_panel.draw_line(Vector2(x, y - 1), Vector2(x + pw - 8, y - 1), Color(0.2, 0.25, 0.2, 0.4), 1.0)


func _draw_le_sub_header(x: float, y: float, pw: float, font: Font, sub: Dictionary) -> void:
	var ctx_text: String = ""
	var ctx_col := Color(0.6, 0.55, 0.4)
	match sub["id"]:
		"le_level":
			ctx_text = _le_get_current_level_name()
		"le_modes":
			var mi: int = _le_active_display_mode
			if mi >= 0 and mi < LE_MODE_DISPLAY_NAMES.size():
				ctx_text = LE_MODE_DISPLAY_NAMES[mi]
				ctx_col = LE_MODE_DISPLAY_COLORS[mi]
		"le_items":
			ctx_text = "%d items" % _le_get_item_count()
		"le_properties":
			var sel: int = _le_get_selected_idx()
			if sel >= 0:
				ctx_text = "#%d" % (sel + 1)
		"le_scene":
			var enemy_count: int = get_tree().get_nodes_in_group("enemies").size()
			var player_count: int = get_tree().get_nodes_in_group("players").size()
			ctx_text = "%dE %dP" % [enemy_count, player_count]
		"le_save":
			var le: Node = _get_level_editor()
			if le and "_changed" in le:
				var total: int = 0
				for k in le._changed:
					if le._changed[k]:
						total += 1
				if total > 0:
					ctx_text = "%d changed" % total
					ctx_col = Color(1.0, 0.8, 0.3)
	_draw_sub_header(x, y, pw, font, sub, Color(0.9, 0.7, 0.3), ctx_text, ctx_col)


func _draw_le_sub_level(x: float, y: float, pw: float, h: float, font: Font) -> void:
	## Draw scrollable level selector list.
	if _le_level_names_dirty:
		_le_rebuild_level_names()
	var row_h: float = ROW_HEIGHT
	var visible_count: int = int(h / row_h)
	var max_scroll: int = maxi(0, _le_cached_level_names.size() - visible_count)
	_le_level_scroll_offset = clampi(_le_level_scroll_offset, 0, max_scroll)
	var current_level: String = _le_get_current_level_name()

	for i in range(mini(visible_count, _le_cached_level_names.size() - _le_level_scroll_offset)):
		var lname: String = _le_cached_level_names[i + _le_level_scroll_offset]
		var ry: float = y + i * row_h
		var is_current: bool = (lname == current_level)
		var is_hover: bool = (_le_hover_level_idx == i + _le_level_scroll_offset)

		if is_current:
			_panel.draw_rect(Rect2(x, ry, pw - 8, row_h - 2), Color(0.15, 0.25, 0.1))
			_panel.draw_rect(Rect2(x, ry, 2, row_h - 2), Color(0.3, 0.8, 0.3))
		elif is_hover:
			_panel.draw_rect(Rect2(x, ry, pw - 8, row_h - 2), Color(0.12, 0.12, 0.08))

		var col: Color = Color(0.5, 1.0, 0.5) if is_current else (Color(0.75, 0.75, 0.7) if is_hover else Color(0.5, 0.5, 0.45))
		_panel.draw_string(font, Vector2(x + 8, ry + 13), lname, HORIZONTAL_ALIGNMENT_LEFT, pw - 16, 9, col)

	if _le_cached_level_names.size() > visible_count and max_scroll > 0:
		var pct: float = float(_le_level_scroll_offset) / float(max_scroll)
		var bar_h: float = maxf(16.0, h * float(visible_count) / float(_le_cached_level_names.size()))
		_panel.draw_rect(Rect2(x + pw - 12, y + pct * (h - bar_h), 3, bar_h), Color(0.3, 0.3, 0.25, 0.5))


func _draw_le_sub_modes(x: float, y: float, pw: float, h: float, font: Font) -> void:
	var row_h: float = ROW_HEIGHT
	var current_mode: int = _le_active_display_mode
	var visible_count: int = int(h / row_h)

	for i in range(mini(visible_count, LE_MODE_DISPLAY_NAMES.size())):
		var ry: float = y + i * row_h
		var is_active_mode: bool = (i == current_mode)
		var is_hover: bool = (_le_hover_mode_idx == i)
		var col: Color = LE_MODE_DISPLAY_COLORS[i]

		if is_active_mode:
			_panel.draw_rect(Rect2(x, ry, pw - 8, row_h - 2), col * Color(1, 1, 1, 0.15))
			_panel.draw_rect(Rect2(x, ry, 2, row_h - 2), col)
		elif is_hover:
			_panel.draw_rect(Rect2(x, ry, pw - 8, row_h - 2), Color(0.12, 0.12, 0.08))

		# Mode dot
		_panel.draw_circle(Vector2(x + 8, ry + 8), 3.0 if is_active_mode else 2.0, col if is_active_mode else col * Color(1, 1, 1, 0.4))

		# Name
		var name_col: Color = col if is_active_mode else (Color(0.7, 0.7, 0.65) if is_hover else Color(0.5, 0.5, 0.45))
		_panel.draw_string(font, Vector2(x + 16, ry + 13), LE_MODE_DISPLAY_NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, pw * 0.6, 9, name_col)

		# Count (skip for Gameplay)
		if i > 0 and i < LE_MODE_MAP.size():
			var editor_mode: int = LE_MODE_MAP[i]
			_panel.draw_string(font, Vector2(x + pw - 48, ry + 13), "(%d)" % _le_get_item_count_for_mode(editor_mode), HORIZONTAL_ALIGNMENT_LEFT, 40, 8, Color(0.4, 0.4, 0.35))


func _draw_le_sub_items(x: float, y: float, pw: float, h: float, font: Font) -> void:
	var row_h: float = 16.0
	var items: Array = _le_build_item_list()
	var visible_count: int = int(h / row_h)
	var max_scroll: int = maxi(0, items.size() - visible_count)
	_le_items_scroll_offset = clampi(_le_items_scroll_offset, 0, max_scroll)

	var sel: int = _le_get_selected_idx()
	var le: Node = _get_level_editor()

	for i in range(mini(visible_count, items.size() - _le_items_scroll_offset)):
		var item: Dictionary = items[i + _le_items_scroll_offset]
		var ry: float = y + i * row_h
		# Selection check: for spawn areas, match both idx and zone type
		var is_selected: bool = false
		if sel >= 0:
			if item.has("zone_type") and le and "_drag_item_type" in le:
				is_selected = (sel == item["idx"] and le._drag_item_type == item["zone_type"] + "_zone")
			else:
				is_selected = (sel == item.get("idx", -1))
		var is_hover: bool = (_le_hover_item_idx == i + _le_items_scroll_offset)

		if is_selected:
			_panel.draw_rect(Rect2(x, ry, pw - 8, row_h - 2), Color(0.15, 0.22, 0.1))
		elif is_hover:
			_panel.draw_rect(Rect2(x, ry, pw - 8, row_h - 2), Color(0.12, 0.12, 0.08))

		_panel.draw_string(font, Vector2(x + 2, ry + 11), "%d" % (i + _le_items_scroll_offset + 1), HORIZONTAL_ALIGNMENT_LEFT, 16, 8, Color(0.4, 0.4, 0.35))

		var col: Color = item.get("color", Color(0.6, 0.6, 0.6))
		if is_selected: col = col.lightened(0.3)
		elif is_hover: col = col.lightened(0.15)
		_panel.draw_string(font, Vector2(x + 20, ry + 11), item.get("label", "?"), HORIZONTAL_ALIGNMENT_LEFT, pw - 36, 8, col)

	if items.size() > visible_count and max_scroll > 0:
		var pct: float = float(_le_items_scroll_offset) / float(max_scroll)
		var bar_h: float = maxf(16.0, h * float(visible_count) / float(items.size()))
		_panel.draw_rect(Rect2(x + pw - 12, y + pct * (h - bar_h), 3, bar_h), Color(0.3, 0.3, 0.25, 0.5))


func _draw_le_sub_properties(x: float, y: float, pw: float, h: float, font: Font) -> void:
	var props: Array = _le_get_properties()
	if props.is_empty():
		_panel.draw_string(font, Vector2(x + 4, y + 14), "(select an item)", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.4, 0.4, 0.35))
		return

	var row_h: float = 18.0
	var visible_count: int = int(h / row_h)
	for i in range(mini(visible_count, props.size())):
		var prop: Dictionary = props[i]
		var ry: float = y + i * row_h
		var is_editing: bool = _le_prop_edit_focused and _le_prop_edit_key == prop["key"]

		_panel.draw_string(font, Vector2(x + 4, ry + 13), prop["label"], HORIZONTAL_ALIGNMENT_LEFT, pw * 0.4, 9, Color(0.6, 0.6, 0.55))

		var val_x: float = x + pw * 0.47
		var val_w: float = pw * 0.48
		if prop.get("type", "") == "slider" and prop.get("editable", false):
			var slider_w: float = pw * 0.35
			var slider_y: float = ry + 8
			_panel.draw_rect(Rect2(val_x, slider_y - 2, slider_w, 4), Color(0.2, 0.2, 0.18))
			var min_v: float = prop.get("min", 0.0)
			var max_v: float = prop.get("max", 1000.0)
			var cur_v: float = float(prop.get("value", 0))
			var t: float = clampf((cur_v - min_v) / (max_v - min_v), 0.0, 1.0) if max_v != min_v else 0.0
			var thumb_col := Color(0.9, 0.6, 0.2) if _le_prop_dragging_key == prop["key"] else Color(0.8, 0.6, 0.3)
			_panel.draw_circle(Vector2(val_x + t * slider_w, slider_y), 5.0, thumb_col)
			_panel.draw_string(font, Vector2(val_x + slider_w + 4, ry + 13), "%.1f" % cur_v, HORIZONTAL_ALIGNMENT_LEFT, 50, 8, Color(0.7, 0.7, 0.6))
		elif is_editing:
			_panel.draw_rect(Rect2(val_x, ry + 1, val_w, row_h - 4), Color(0.12, 0.12, 0.1))
			var display: String = _le_prop_edit_text
			if int(_cursor_blink * 2) % 2 == 0:
				display = display.substr(0, _le_prop_edit_cursor) + "|" + display.substr(_le_prop_edit_cursor)
			_panel.draw_string(font, Vector2(val_x + 4, ry + 13), display, HORIZONTAL_ALIGNMENT_LEFT, val_w - 8, 9, Color(0.9, 0.9, 0.8))
		else:
			var val_text: String = "%.1f" % prop["value"] if prop.get("value") is float else str(prop.get("value", ""))
			var val_col: Color = Color(0.8, 0.8, 0.7) if prop.get("editable", false) else Color(0.5, 0.5, 0.45)
			_panel.draw_string(font, Vector2(val_x + 4, ry + 13), val_text, HORIZONTAL_ALIGNMENT_LEFT, val_w, 9, val_col)


func _draw_le_sub_actions(x: float, y: float, pw: float, h: float, font: Font) -> void:
	## Draw mode-dependent actions. Gameplay shows spawn/kill/etc. Editor modes show
	## mode-specific button bar. Always-available actions appear at the bottom.
	var ry: float = y

	# Mode-specific action button bar (migration/splay etc.)
	var action_btns: Array = _le_get_action_buttons()
	if not action_btns.is_empty():
		var btn_h: float = 22.0
		_panel.draw_rect(Rect2(x, ry, pw - 8, btn_h), Color(0.06, 0.06, 0.04, 0.8))
		var bw: float = (pw - 24.0) / float(action_btns.size())
		for i in range(action_btns.size()):
			var bx: float = x + 8.0 + i * bw
			var col: Color = action_btns[i][1]
			_panel.draw_rect(Rect2(bx, ry + 2, bw - 4, btn_h - 4), col * Color(1, 1, 1, 0.12))
			_panel.draw_rect(Rect2(bx, ry + 2, bw - 4, btn_h - 4), col * Color(1, 1, 1, 0.45), false, 1.0)
			_panel.draw_string(font, Vector2(bx + 4, ry + btn_h - 6), action_btns[i][0], HORIZONTAL_ALIGNMENT_LEFT, bw - 8, 8, col)
		ry += btn_h + 4

	# Mode-dependent action list
	var actions: Array = _le_get_current_actions()
	var row_h: float = 18.0
	var action_idx: int = 0
	for i in range(actions.size()):
		if ry > y + h:
			break
		var action: Dictionary = actions[i]
		if action["cmd"] == "":
			ry += 2
			_panel.draw_line(Vector2(x, ry), Vector2(x + pw - 16, ry), Color(0.25, 0.25, 0.2, 0.4), 1.0)
			ry += 2
			_panel.draw_string(font, Vector2(x + 4, ry + 10), action["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.5, 0.5, 0.45))
			ry += 14
			continue

		var is_hover: bool = (_le_scene_hover_idx == action_idx)
		if is_hover:
			_panel.draw_rect(Rect2(x, ry, pw - 8, row_h - 2), Color(0.15, 0.15, 0.1))
		var col: Color = action.get("color", Color(0.6, 0.6, 0.6))
		if not is_hover:
			col = col * Color(1, 1, 1, 0.7)
		_panel.draw_string(font, Vector2(x + 8, ry + 13), action["label"], HORIZONTAL_ALIGNMENT_LEFT, pw - 16, 9, col)
		ry += row_h
		action_idx += 1

	# Flash feedback
	if _le_scene_flash_timer > 0:
		var alpha: float = clampf(_le_scene_flash_timer / 0.5, 0.0, 1.0)
		ry += 4
		_panel.draw_string(font, Vector2(x + 8, ry + 12), _le_scene_flash, HORIZONTAL_ALIGNMENT_LEFT, pw - 16, 9, Color(0.3, 1.0, 0.5, alpha))


func _draw_le_sub_save(x: float, y: float, pw: float, _h: float, font: Font) -> void:
	var ry: float = y
	var le: Node = _get_level_editor()

	# Change summary
	if le and "_changed" in le:
		var parts: Array[String] = []
		for key in le._changed:
			if le._changed[key]:
				var count: int = le._changed_items[key].size() if le._changed_items.has(key) else 1
				parts.append("%d %s" % [count, key])
		if not parts.is_empty():
			_panel.draw_string(font, Vector2(x + 4, ry + 12), ", ".join(parts), HORIZONTAL_ALIGNMENT_LEFT, pw - 16, 9, Color(1.0, 0.8, 0.3))
		else:
			_panel.draw_string(font, Vector2(x + 4, ry + 12), "No unsaved changes", HORIZONTAL_ALIGNMENT_LEFT, pw - 16, 9, Color(0.4, 0.5, 0.4))
	ry += 18

	# Save buttons
	var btn_h: float = 22.0
	if Version.is_source_mode():
		var o_col := Color(0.3, 0.8, 1.0)
		_panel.draw_rect(Rect2(x + 4, ry, pw * 0.44, btn_h), o_col * Color(1, 1, 1, 0.1))
		_panel.draw_rect(Rect2(x + 4, ry, pw * 0.44, btn_h), o_col * Color(1, 1, 1, 0.5), false, 1.0)
		_panel.draw_string(font, Vector2(x + 12, ry + 15), "Save Original", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, o_col)

	var c_col := Color(0.3, 1.0, 0.3)
	var cx: float = x + pw * 0.5
	_panel.draw_rect(Rect2(cx, ry, pw * 0.44, btn_h), c_col * Color(1, 1, 1, 0.1))
	_panel.draw_rect(Rect2(cx, ry, pw * 0.44, btn_h), c_col * Color(1, 1, 1, 0.5), false, 1.0)
	_panel.draw_string(font, Vector2(cx + 8, ry + 15), "Save Custom", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, c_col)
	ry += btn_h + 6

	# Status
	if le and le.has_method("_has_custom_level"):
		if le._has_custom_level():
			_panel.draw_string(font, Vector2(x + 4, ry + 12), "CUSTOM", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 0.6, 0.3))
		else:
			_panel.draw_string(font, Vector2(x + 4, ry + 12), "ORIGINAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.3, 0.8, 1.0, 0.6))


# ==============================================================================
# BLUEPRINTS SECTION — Edit construct definitions (splay poses, tree shapes).
# Opens a blank sandbox level for editing. All spawned entities are temporary.
# ==============================================================================

const CT_TYPE_NAMES := ["Splay Poses", "Trees"]
const CT_TYPE_COLORS: Array[Color] = [Color(0.9, 0.4, 0.2), Color(0.3, 0.8, 0.4)]

# Tracks whether we're in the blueprint sandbox
var _ct_sandbox_active: bool = false
var _ct_sandbox_return_level: String = ""  # Level to return to when exiting sandbox

# Tree blueprint editing state
var _ct_tree_preview: Node2D = null       # Live preview tree in the sandbox
var _ct_tree_blueprint_name: String = ""  # Currently editing blueprint name
var _ct_tree_prop_dragging: String = ""   # Which tree property slider is being dragged


func _init_ct_subsections() -> void:
	_ct_subsections = []
	for sid in ["ct_types", "ct_instances", "ct_editor"]:
		_ct_subsections.append({
			"id": sid,
			"title": sid.substr(3).capitalize(),
			"collapsed": false,
			"height": _get_ct_preferred_height(sid),
		})
	var had_ct_layout: bool = FileAccess.file_exists("user://constructs_layout.json")
	_load_ct_layout()
	if not had_ct_layout:
		_auto_snap_ct()
	_ct_subsections_initialized = true


func _load_ct_layout() -> void:
	var path: String = "user://constructs_layout.json"
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return
	for sub in _ct_subsections:
		if json.data.has(sub["id"]):
			sub["collapsed"] = json.data[sub["id"]].get("collapsed", sub["collapsed"])
			sub["height"] = json.data[sub["id"]].get("height", sub["height"])


func _save_ct_layout() -> void:
	var data: Dictionary = {}
	for sub in _ct_subsections:
		data[sub["id"]] = {"collapsed": sub["collapsed"], "height": sub["height"]}
	var file := FileAccess.open("user://constructs_layout.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "  "))


func _auto_snap_ct() -> void:
	if _ct_subsections.is_empty():
		return
	var last: Dictionary = _ct_subsections[_ct_subsections.size() - 1]
	for i in range(_ct_subsections.size() - 1):
		var sub: Dictionary = _ct_subsections[i]
		if sub["collapsed"]:
			continue
		var preferred: float = _get_ct_preferred_height(sub["id"])
		var delta: float = preferred - sub["height"]
		sub["height"] = preferred
		last["height"] -= delta
	if last["height"] < CT_SUB_MIN.get("ct_editor", 60.0):
		last["height"] = CT_SUB_MIN.get("ct_editor", 60.0)


func _get_ct_preferred_height(sid: String) -> float:
	match sid:
		"ct_types":
			return SUB_HEADER_H + CT_TYPE_NAMES.size() * ROW_HEIGHT + 4.0
		"ct_instances":
			var count: int = _ct_get_instance_count()
			return SUB_HEADER_H + clampi(count, 3, 10) * 16.0 + 4.0
		"ct_editor":
			if _ct_selected_type == "trees" and is_instance_valid(_ct_tree_preview):
				return SUB_HEADER_H + _ct_get_tree_properties().size() * 18.0 + 30.0
			return SUB_HEADER_H + 40.0
	return SUB_HEADER_H + 40.0


func _ct_get_splay_pose_names() -> Array[String]:
	## Scan splay_poses directories for available pose JSON files.
	var names: Array[String] = []
	# Bundled poses
	var dir := DirAccess.open("res://data/splay_poses/")
	if dir:
		dir.list_dir_begin()
		var fname: String = dir.get_next()
		while fname != "":
			if fname.ends_with(".json"):
				names.append(fname.get_basename())
			fname = dir.get_next()
		dir.list_dir_end()
	# Custom poses (user://)
	var udir := DirAccess.open("user://splay_poses/")
	if udir:
		udir.list_dir_begin()
		var fname2: String = udir.get_next()
		while fname2 != "":
			if fname2.ends_with(".json"):
				var bname: String = fname2.get_basename()
				if bname not in names:
					names.append(bname)
			fname2 = udir.get_next()
		udir.list_dir_end()
	names.sort()
	return names


func _ct_get_instance_count() -> int:
	match _ct_selected_type:
		"splays": return _ct_get_splay_pose_names().size()
		"trees": return _ct_get_tree_blueprint_names().size()
	return 0


func _ct_build_instance_list() -> Array:
	## Build the list of blueprint definitions (not level instances).
	## Splays: lists available pose files. Trees: lists tree blueprint files.
	var items: Array = []
	match _ct_selected_type:
		"splays":
			var poses: Array[String] = _ct_get_splay_pose_names()
			for i in range(poses.size()):
				items.append({"label": poses[i], "color": Color(0.9, 0.4, 0.2), "idx": i})
		"trees":
			var blueprints: Array[String] = _ct_get_tree_blueprint_names()
			for i in range(blueprints.size()):
				items.append({"label": blueprints[i], "color": Color(0.3, 0.8, 0.4), "idx": i})
	return items


# -- CT click/scroll/hover/resize ---------------------------------------------

func _handle_ct_click(lx: float, my: float) -> void:
	if not _ct_subsections_initialized:
		_init_ct_subsections()
	var y: float = 0.0
	for i in range(_ct_subsections.size()):
		var sub: Dictionary = _ct_subsections[i]
		var header_end: float = y + SUB_HEADER_H

		if my >= y and my < header_end:
			var pw: float = _content_width
			if lx < 16:
				sub["collapsed"] = not sub["collapsed"]
				_save_ct_layout()
			elif lx > pw - 28 and i > 0:
				var target_idx: int = i - 1
				var now: float = Time.get_ticks_msec() / 1000.0
				if _ct_grip_last_click_idx == target_idx and (now - _ct_grip_last_click_time) < 0.4:
					var sub_above: Dictionary = _ct_subsections[target_idx]
					var last_sub: Dictionary = _ct_subsections[_ct_subsections.size() - 1]
					var preferred: float = _get_ct_preferred_height(sub_above["id"])
					var delta: float = preferred - sub_above["height"]
					sub_above["height"] = preferred
					last_sub["height"] -= delta
					_save_ct_layout()
					_ct_grip_last_click_idx = -1
					return
				_ct_grip_last_click_idx = target_idx
				_ct_grip_last_click_time = now
				_ct_sub_resize_idx = target_idx
				_ct_sub_resize_start_y = my
				_ct_sub_resize_start_h = _ct_subsections[target_idx]["height"]
				_ct_sub_resize_next_h = _ct_subsections[_ct_subsections.size() - 1]["height"]
			return

		if sub["collapsed"]:
			y += SUB_HEADER_H
			continue

		var body_y: float = header_end
		var body_end: float = y + sub["height"]
		if sub["id"] == "ct_editor":
			body_end = maxf(body_end, 9999.0)

		if my >= body_y and my < body_end:
			var local_y: float = my - body_y
			match sub["id"]:
				"ct_types":
					var idx: int = int(local_y / ROW_HEIGHT)
					if idx == 0: _ct_selected_type = "splays"
					elif idx == 1: _ct_selected_type = "trees"
					_ct_instances_scroll_offset = 0
				"ct_instances":
					var idx: int = int(local_y / 16.0) + _ct_instances_scroll_offset
					_ct_select_instance(idx)
				"ct_editor":
					_handle_ct_editor_click(lx, local_y)
			return
		y += sub["height"]


func _ct_enter_sandbox() -> void:
	## Enter the blueprint sandbox — load a blank level for construct editing.
	## Remembers the current level to return to later.
	if _ct_sandbox_active:
		return
	_ct_sandbox_return_level = _le_get_current_level_name()
	_ct_sandbox_active = true
	# Load flat_floor as the sandbox (minimal level)
	var rcon: Node = get_node_or_null("/root/Rcon")
	if rcon:
		rcon._execute("clear")
		rcon._execute("level flat_floor")


func _ct_exit_sandbox() -> void:
	## Exit the blueprint sandbox — return to the previous level.
	if not _ct_sandbox_active:
		return
	_ct_sandbox_active = false
	# Deactivate level editor overlay
	var le: Node = _get_level_editor()
	if le and le._active:
		if le._mode == 7:  # SPLAY_EDIT — exit cleanly
			le._exit_splay_edit()
			le._mode = 6
		le._active = false
		le.visible = false
		if le._overlay:
			le._overlay.visible = false
	# Return to previous level
	if not _ct_sandbox_return_level.is_empty():
		var rcon: Node = get_node_or_null("/root/Rcon")
		if rcon:
			rcon._execute("level %s" % _ct_sandbox_return_level)
	_ct_sandbox_return_level = ""


func _ct_select_instance(idx: int) -> void:
	## Select a blueprint instance to edit. Enters sandbox if not already there.
	## For splay poses: enters SPLAY_EDIT mode with that pose loaded.
	## For trees: selects the tree for seed/position editing.
	if not _ct_sandbox_active:
		_ct_enter_sandbox()
		# Wait a frame for the level to load before entering edit mode
		# For now, just set up — the user can click again after sandbox loads
		return

	var le: Node = _get_level_editor()
	if not le:
		_le_ensure_editor_for_level("flat_floor")
		le = _get_level_editor()
	if not le:
		return

	match _ct_selected_type:
		"splays":
			var poses: Array[String] = _ct_get_splay_pose_names()
			if idx >= 0 and idx < poses.size():
				var pose_name: String = poses[idx]
				le._active = true
				le.visible = true
				if le._overlay:
					le._overlay.visible = true
				le._mode = 6  # SPLAY first
				if not le._config.has("splays"):
					le._config["splays"] = []
				var splays: Array = le._config["splays"]
				var found_idx: int = -1
				for si in range(splays.size()):
					if splays[si].get("pose", "") == pose_name:
						found_idx = si
						break
				if found_idx < 0:
					splays.append({"pose": pose_name, "creature": "quadruped", "pos": [960, 500], "rotation": 0, "behavior": "asleep"})
					found_idx = splays.size() - 1
				le._selected_idx = found_idx
				le._splay_edit_pose_idx = found_idx
				le._mode = 7  # SPLAY_EDIT
				le._enter_splay_edit()
				le._update_display()
		"trees":
			var blueprints: Array[String] = _ct_get_tree_blueprint_names()
			if idx >= 0 and idx < blueprints.size():
				var bp_name: String = blueprints[idx]
				_ct_edit_tree_blueprint(bp_name)


func _ct_edit_tree_blueprint(bp_name: String) -> void:
	## Spawn a preview tree in the sandbox and enter tree editing mode.
	_ct_tree_blueprint_name = bp_name

	# Remove any existing preview tree
	if is_instance_valid(_ct_tree_preview):
		_ct_tree_preview.queue_free()
		_ct_tree_preview = null

	# Spawn a preview tree
	var tree_script: GDScript = load("res://scripts/effects/procedural_tree.gd")
	var tree := Node2D.new()
	tree.set_script(tree_script)
	tree.load_blueprint(bp_name)
	tree.seed_value = 42  # Fixed seed for consistent preview
	tree.z_index = 5
	tree.regenerate()

	var scene: Node = get_tree().current_scene
	if scene:
		scene.add_child(tree)
		tree.global_position = Vector2(960, 880)
	_ct_tree_preview = tree


func _ct_get_tree_properties() -> Array:
	## Returns configurable properties for the currently-editing tree blueprint.
	if not is_instance_valid(_ct_tree_preview):
		return []
	var t: Node2D = _ct_tree_preview
	return [
		{"key": "trunk_weight", "label": "Trunk Width", "value": t.trunk_weight, "type": "slider", "min": 5.0, "max": 50.0},
		{"key": "trunk_length", "label": "Trunk Height", "value": t.trunk_length, "type": "slider", "min": 50.0, "max": 500.0},
		{"key": "max_depth", "label": "Max Depth", "value": float(t.max_depth), "type": "slider", "min": 1.0, "max": 8.0},
		{"key": "min_weight", "label": "Min Weight", "value": t.min_weight, "type": "slider", "min": 1.0, "max": 10.0},
		{"key": "wobble", "label": "Wobble", "value": t.wobble, "type": "slider", "min": 0.0, "max": 1.0},
		{"key": "spread", "label": "Spread", "value": t.spread, "type": "slider", "min": 0.2, "max": 2.0},
		{"key": "decay_min", "label": "Decay Min", "value": t.decay_min, "type": "slider", "min": 0.2, "max": 0.9},
		{"key": "decay_max", "label": "Decay Max", "value": t.decay_max, "type": "slider", "min": 0.3, "max": 1.0},
		{"key": "split_min", "label": "Split Min", "value": float(t.split_min), "type": "slider", "min": 1.0, "max": 5.0},
		{"key": "split_max", "label": "Split Max", "value": float(t.split_max), "type": "slider", "min": 1.0, "max": 6.0},
		{"key": "bend_min", "label": "Bend Min", "value": float(t.bend_min), "type": "slider", "min": 1.0, "max": 6.0},
		{"key": "bend_max", "label": "Bend Max", "value": float(t.bend_max), "type": "slider", "min": 1.0, "max": 8.0},
		{"key": "canopy_offset", "label": "Canopy Offset", "value": t.canopy_offset, "type": "slider", "min": 0.5, "max": 2.5},
		{"key": "seed_value", "label": "Preview Seed", "value": float(t.seed_value), "type": "slider", "min": 0.0, "max": 9999.0},
	]


func _ct_set_tree_property(key: String, value: float) -> void:
	## Set a tree property on the preview and regenerate.
	if not is_instance_valid(_ct_tree_preview):
		return
	var t: Node2D = _ct_tree_preview
	match key:
		"trunk_weight": t.trunk_weight = value
		"trunk_length": t.trunk_length = value
		"max_depth": t.max_depth = int(value)
		"min_weight": t.min_weight = value
		"wobble": t.wobble = value
		"spread": t.spread = value
		"decay_min": t.decay_min = value
		"decay_max": t.decay_max = value
		"split_min": t.split_min = int(value)
		"split_max": t.split_max = int(value)
		"bend_min": t.bend_min = int(value)
		"bend_max": t.bend_max = int(value)
		"canopy_offset": t.canopy_offset = value
		"seed_value": t.seed_value = int(value)
	t.regenerate()


func _ct_save_tree_blueprint() -> void:
	## Save the current preview tree's settings as the active blueprint.
	if not is_instance_valid(_ct_tree_preview) or _ct_tree_blueprint_name.is_empty():
		return
	if Version.is_source_mode():
		_ct_tree_preview.save_blueprint(_ct_tree_blueprint_name, true)
	else:
		_ct_tree_preview.save_blueprint(_ct_tree_blueprint_name, false)
	_le_scene_flash = "Saved: %s" % _ct_tree_blueprint_name
	_le_scene_flash_timer = 2.0


func _handle_ct_scroll(my: float, delta: int) -> void:
	if not _ct_subsections_initialized:
		return
	var y: float = 0.0
	for sub in _ct_subsections:
		if sub["collapsed"]:
			y += SUB_HEADER_H
			continue
		var body_end: float = y + sub["height"]
		if sub["id"] == "ct_instances":
			body_end = maxf(body_end, 9999.0)
		if my >= y and my < body_end:
			if sub["id"] == "ct_instances":
				_ct_instances_scroll_offset = maxi(0, _ct_instances_scroll_offset + delta)
			return
		y += sub["height"]


func _handle_ct_hover(my: float) -> void:
	_ct_hover_type_idx = -1
	_ct_hover_instance_idx = -1
	if not _ct_subsections_initialized:
		return
	var y: float = 0.0
	for sub in _ct_subsections:
		if sub["collapsed"]:
			y += SUB_HEADER_H
			continue
		var body_y: float = y + SUB_HEADER_H
		var body_end: float = y + sub["height"]
		if sub["id"] == "ct_instances":
			body_end = maxf(body_end, 9999.0)
		if my >= body_y and my < body_end:
			var local_y: float = my - body_y
			match sub["id"]:
				"ct_types": _ct_hover_type_idx = int(local_y / ROW_HEIGHT)
				"ct_instances": _ct_hover_instance_idx = int(local_y / 16.0) + _ct_instances_scroll_offset
			return
		y += sub["height"]


func _handle_ct_editor_click(lx: float, local_y: float) -> void:
	## Click in the editor sub-section — tree property sliders or save button.
	if _ct_selected_type == "trees" and is_instance_valid(_ct_tree_preview):
		var props: Array = _ct_get_tree_properties()
		var row_h: float = 18.0
		var idx: int = int(local_y / row_h)
		if idx >= 0 and idx < props.size():
			var prop: Dictionary = props[idx]
			var pw: float = _content_width
			if lx > pw * 0.45:
				_ct_tree_prop_dragging = prop["key"]
				# Set value from click position
				var slider_x: float = pw * 0.47
				var slider_w: float = pw * 0.35
				var t: float = clampf((lx - slider_x) / slider_w, 0.0, 1.0)
				var new_val: float = lerpf(prop.get("min", 0.0), prop.get("max", 100.0), t)
				_ct_set_tree_property(prop["key"], new_val)
			return
		# Save button (below properties)
		var save_y: float = props.size() * row_h + 4
		if local_y >= save_y and local_y < save_y + 22:
			_ct_save_tree_blueprint()


func _handle_ct_tree_prop_drag(mx: float) -> void:
	## Drag a tree property slider.
	if _ct_tree_prop_dragging.is_empty() or not is_instance_valid(_ct_tree_preview):
		_ct_tree_prop_dragging = ""
		return
	var lx: float = mx - _panel_x - ICON_BAR_WIDTH - 4
	var pw: float = _content_width
	var slider_x: float = pw * 0.47
	var slider_w: float = pw * 0.35
	var t: float = clampf((lx - slider_x) / slider_w, 0.0, 1.0)
	for prop in _ct_get_tree_properties():
		if prop["key"] == _ct_tree_prop_dragging:
			var new_val: float = lerpf(prop.get("min", 0.0), prop.get("max", 100.0), t)
			_ct_set_tree_property(prop["key"], new_val)
			return


func _handle_ct_sub_resize_drag(my: float) -> void:
	if _ct_sub_resize_idx < 0 or _ct_sub_resize_idx >= _ct_subsections.size():
		return
	var dy: float = my - _ct_sub_resize_start_y
	var sub: Dictionary = _ct_subsections[_ct_sub_resize_idx]
	var last: Dictionary = _ct_subsections[_ct_subsections.size() - 1]
	var min_h: float = CT_SUB_MIN.get(sub["id"], 30.0)
	var last_min: float = CT_SUB_MIN.get(last["id"], 60.0)
	dy = clampf(dy, min_h - _ct_sub_resize_start_h, _ct_sub_resize_next_h - last_min)
	sub["height"] = _ct_sub_resize_start_h + dy
	last["height"] = _ct_sub_resize_next_h - (sub["height"] - _ct_sub_resize_start_h)


func _handle_ct_sub_resize_release() -> void:
	if _ct_sub_resize_idx < 0 or _ct_sub_resize_idx >= _ct_subsections.size():
		return
	var sub: Dictionary = _ct_subsections[_ct_sub_resize_idx]
	var last: Dictionary = _ct_subsections[_ct_subsections.size() - 1]
	var preferred: float = _get_ct_preferred_height(sub["id"])
	if absf(sub["height"] - preferred) < SUB_SNAP_DISTANCE:
		var delta: float = preferred - sub["height"]
		sub["height"] = preferred
		last["height"] -= delta


# -- CT drawing ----------------------------------------------------------------

func _draw_blueprints_section(content_x: float, font: Font, ph: float) -> void:
	if not _ct_subsections_initialized:
		_init_ct_subsections()

	var x: float = content_x
	var pw: float = _content_width
	var y: float = 0.0

	for si in range(_ct_subsections.size()):
		var sub: Dictionary = _ct_subsections[si]
		if y > ph:
			break

		# Header
		_draw_ct_sub_header(x, y, pw, font, sub)

		if sub["collapsed"]:
			y += SUB_HEADER_H
			continue

		var body_y: float = y + SUB_HEADER_H
		var body_h: float
		if sub["id"] == "ct_editor":
			body_h = maxf(CT_SUB_MIN["ct_editor"] - SUB_HEADER_H, ph - body_y)
		else:
			body_h = sub["height"] - SUB_HEADER_H

		if body_h > 0:
			match sub["id"]:
				"ct_types":     _draw_ct_sub_types(x, body_y, pw, body_h, font)
				"ct_instances": _draw_ct_sub_instances(x, body_y, pw, body_h, font)
				"ct_editor":    _draw_ct_sub_editor(x, body_y, pw, body_h, font)

		# Snap indicator
		if _ct_sub_resize_idx == si and sub["id"] != "ct_editor":
			var snap_h: float = _get_ct_preferred_height(sub["id"])
			var snap_y: float = y + snap_h
			var near: bool = absf(sub["height"] - snap_h) < SUB_SNAP_DISTANCE
			var scol := Color(0.9, 0.5, 0.2, 0.6) if near else Color(0.9, 0.5, 0.2, 0.25)
			var dx: float = 0.0
			while dx < pw - 16:
				_panel.draw_line(Vector2(x + dx, snap_y), Vector2(x + minf(dx + 6, pw - 16), snap_y), scol, 1.0)
				dx += 10.0

		if sub["id"] == "ct_editor":
			y += body_h + SUB_HEADER_H
		else:
			y += sub["height"]

		if sub["id"] != "ct_editor":
			_panel.draw_line(Vector2(x, y - 1), Vector2(x + pw - 8, y - 1), Color(0.2, 0.2, 0.15, 0.4), 1.0)


func _draw_ct_sub_header(x: float, y: float, pw: float, font: Font, sub: Dictionary) -> void:
	var ctx: String = ""
	var ctx_col := Color(0.6, 0.5, 0.4)
	match sub["id"]:
		"ct_types":
			ctx = _ct_selected_type.capitalize()
			if _ct_sandbox_active:
				ctx += "  [SANDBOX]"
				ctx_col = Color(1.0, 0.7, 0.3)
		"ct_instances":
			ctx = "%d blueprints" % _ct_get_instance_count()
		"ct_editor":
			if _ct_selected_type == "trees" and not _ct_tree_blueprint_name.is_empty():
				ctx = _ct_tree_blueprint_name
				ctx_col = Color(0.3, 0.8, 0.4)
	_draw_sub_header(x, y, pw, font, sub, Color(0.9, 0.55, 0.2), ctx, ctx_col)


func _draw_ct_sub_types(x: float, y: float, pw: float, h: float, font: Font) -> void:
	var row_h: float = ROW_HEIGHT
	for i in range(mini(int(h / row_h), CT_TYPE_NAMES.size())):
		var ry: float = y + i * row_h
		var type_key: String = "splays" if i == 0 else "trees"
		var is_selected: bool = (_ct_selected_type == type_key)
		var is_hover: bool = (_ct_hover_type_idx == i)
		var col: Color = CT_TYPE_COLORS[i]

		if is_selected:
			_panel.draw_rect(Rect2(x, ry, pw - 8, row_h - 2), col * Color(1, 1, 1, 0.15))
			_panel.draw_rect(Rect2(x, ry, 2, row_h - 2), col)
		elif is_hover:
			_panel.draw_rect(Rect2(x, ry, pw - 8, row_h - 2), Color(0.12, 0.1, 0.06))

		_panel.draw_circle(Vector2(x + 8, ry + 8), 3.0 if is_selected else 2.0, col if is_selected else col * Color(1, 1, 1, 0.4))
		var ncol: Color = col if is_selected else (Color(0.7, 0.7, 0.65) if is_hover else Color(0.5, 0.5, 0.45))
		_panel.draw_string(font, Vector2(x + 16, ry + 13), CT_TYPE_NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, pw * 0.6, 9, ncol)

		# Count
		var config: Dictionary = _le_get_config()
		var count: int = 0
		match type_key:
			"splays": count = config.get("splays", []).size()
			"trees": count = config.get("scenery", {}).get("trees", []).size()
		_panel.draw_string(font, Vector2(x + pw - 48, ry + 13), "(%d)" % count, HORIZONTAL_ALIGNMENT_LEFT, 40, 8, Color(0.4, 0.4, 0.35))


func _draw_ct_sub_instances(x: float, y: float, pw: float, h: float, font: Font) -> void:
	var row_h: float = 16.0
	var items: Array = _ct_build_instance_list()
	var visible_count: int = int(h / row_h)
	var max_scroll: int = maxi(0, items.size() - visible_count)
	_ct_instances_scroll_offset = clampi(_ct_instances_scroll_offset, 0, max_scroll)

	if items.is_empty():
		_panel.draw_string(font, Vector2(x + 4, y + 14), "(no %s)" % _ct_selected_type, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.4, 0.4, 0.35))
		return

	# For splay poses, track which pose is being edited (by name in splay edit mode)
	var le: Node = _get_level_editor()
	var editing_pose: String = ""
	if le and "_mode" in le and le._mode == 7 and "_splay_edit_origin_pose_name" in le:
		editing_pose = le._splay_edit_origin_pose_name

	for i in range(mini(visible_count, items.size() - _ct_instances_scroll_offset)):
		var item: Dictionary = items[i + _ct_instances_scroll_offset]
		var ry: float = y + i * row_h
		var is_selected: bool = false
		if _ct_selected_type == "splays":
			is_selected = (not editing_pose.is_empty() and item.get("label", "") == editing_pose)
		else:
			var le_sel: int = le._selected_idx if le and "_selected_idx" in le else -1
			is_selected = (le_sel == item.get("idx", -1))
		var is_hover: bool = (_ct_hover_instance_idx == i + _ct_instances_scroll_offset)

		if is_selected:
			_panel.draw_rect(Rect2(x, ry, pw - 8, row_h - 2), Color(0.15, 0.22, 0.1))
		elif is_hover:
			_panel.draw_rect(Rect2(x, ry, pw - 8, row_h - 2), Color(0.12, 0.1, 0.06))

		_panel.draw_string(font, Vector2(x + 2, ry + 11), "%d" % (i + _ct_instances_scroll_offset + 1), HORIZONTAL_ALIGNMENT_LEFT, 16, 8, Color(0.4, 0.4, 0.35))
		var col: Color = item.get("color", Color(0.6, 0.6, 0.6))
		if is_selected: col = col.lightened(0.3)
		elif is_hover: col = col.lightened(0.15)
		_panel.draw_string(font, Vector2(x + 20, ry + 11), item.get("label", "?"), HORIZONTAL_ALIGNMENT_LEFT, pw - 36, 8, col)

	if items.size() > visible_count and max_scroll > 0:
		var pct: float = float(_ct_instances_scroll_offset) / float(max_scroll)
		var bar_h: float = maxf(16.0, h * float(visible_count) / float(items.size()))
		_panel.draw_rect(Rect2(x + pw - 12, y + pct * (h - bar_h), 3, bar_h), Color(0.3, 0.25, 0.2, 0.5))


func _draw_ct_sub_editor(x: float, y: float, pw: float, h: float, font: Font) -> void:
	## Draw the blueprint editor — tree property sliders + save button,
	## or splay edit status when editing a splay pose.
	if _ct_selected_type == "trees" and is_instance_valid(_ct_tree_preview):
		_draw_ct_tree_editor(x, y, pw, h, font)
	elif _ct_selected_type == "splays":
		var le: Node = _get_level_editor()
		if le and "_mode" in le and le._mode == 7:
			_panel.draw_string(font, Vector2(x + 4, y + 14), "Editing: %s" % _ct_tree_blueprint_name if not _ct_tree_blueprint_name.is_empty() else "Splay Edit active", HORIZONTAL_ALIGNMENT_LEFT, pw - 16, 10, Color(0.9, 0.4, 0.2))
			_panel.draw_string(font, Vector2(x + 4, y + 30), "Use world handles to adjust pose", HORIZONTAL_ALIGNMENT_LEFT, pw - 16, 9, Color(0.5, 0.5, 0.45))
		else:
			_panel.draw_string(font, Vector2(x + 4, y + 14), "(click a blueprint above to edit)", HORIZONTAL_ALIGNMENT_LEFT, pw - 16, 10, Color(0.4, 0.4, 0.35))
	else:
		_panel.draw_string(font, Vector2(x + 4, y + 14), "(click a blueprint above to edit)", HORIZONTAL_ALIGNMENT_LEFT, pw - 16, 10, Color(0.4, 0.4, 0.35))


func _draw_ct_tree_editor(x: float, y: float, pw: float, h: float, font: Font) -> void:
	## Draw tree blueprint property sliders with live preview.
	var props: Array = _ct_get_tree_properties()
	var row_h: float = 18.0
	var ry: float = y

	for i in range(props.size()):
		if ry > y + h - 30:
			break
		var prop: Dictionary = props[i]
		# Label
		_panel.draw_string(font, Vector2(x + 4, ry + 13), prop["label"], HORIZONTAL_ALIGNMENT_LEFT, pw * 0.42, 9, Color(0.6, 0.6, 0.55))
		# Slider
		var slider_x: float = x + pw * 0.47
		var slider_w: float = pw * 0.35
		var slider_y: float = ry + 8
		_panel.draw_rect(Rect2(slider_x, slider_y - 2, slider_w, 4), Color(0.2, 0.2, 0.18))
		var min_v: float = prop.get("min", 0.0)
		var max_v: float = prop.get("max", 100.0)
		var cur_v: float = float(prop.get("value", 0))
		var t: float = clampf((cur_v - min_v) / (max_v - min_v), 0.0, 1.0) if max_v != min_v else 0.0
		var thumb_col := Color(0.3, 0.8, 0.4) if _ct_tree_prop_dragging == prop["key"] else Color(0.3, 0.7, 0.35)
		_panel.draw_circle(Vector2(slider_x + t * slider_w, slider_y), 5.0, thumb_col)
		# Value text
		var val_str: String = "%d" % int(cur_v) if prop["key"] in ["max_depth", "split_min", "split_max", "bend_min", "bend_max", "seed_value"] else "%.2f" % cur_v
		_panel.draw_string(font, Vector2(slider_x + slider_w + 4, ry + 13), val_str, HORIZONTAL_ALIGNMENT_LEFT, 50, 8, Color(0.7, 0.7, 0.6))
		ry += row_h

	# Save button
	ry += 4
	if ry < y + h:
		var btn_w: float = pw * 0.5
		var btn_col := Color(0.3, 0.8, 0.3)
		_panel.draw_rect(Rect2(x + 4, ry, btn_w, 20), btn_col * Color(1, 1, 1, 0.1))
		_panel.draw_rect(Rect2(x + 4, ry, btn_w, 20), btn_col * Color(1, 1, 1, 0.5), false, 1.0)
		var save_label: String = "Save: %s" % _ct_tree_blueprint_name if not _ct_tree_blueprint_name.is_empty() else "Save"
		_panel.draw_string(font, Vector2(x + 12, ry + 14), save_label, HORIZONTAL_ALIGNMENT_LEFT, btn_w - 16, 9, btn_col)

	# Flash feedback
	if _le_scene_flash_timer > 0:
		var alpha: float = clampf(_le_scene_flash_timer / 0.5, 0.0, 1.0)
		_panel.draw_string(font, Vector2(x + pw * 0.55, ry + 14), _le_scene_flash, HORIZONTAL_ALIGNMENT_LEFT, pw * 0.4, 9, Color(0.3, 1.0, 0.5, alpha))
