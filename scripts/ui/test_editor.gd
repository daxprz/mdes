extends CanvasLayer

## In-game test script editor.
## Opened via test_menu.gd "Tests..." item (Ctrl+T → Tests...).
## TAB: switch EDIT/RUN mode.  T: pick test.  Ctrl+S: save.  Esc: close.
##
## Floating window shows the script as an editable numbered list.
## Clicking a row selects it; an inline text field appears for manual typing.
## World-space control handles appear for command types that have geometry:
##   spawn monster/dummy X Y   → draggable dot
##   bleap a/b X Y R           → circle center + radius grip
##   bleap plan req|opt ...    → START rect corners, END circle, DISALLOW capsule endpoints

enum Mode { EDIT, RUN }

# -- Layout constants ----------------------------------------------------------
const WINDOW_W     := 420.0
const TITLE_H      := 26.0
const ROW_H        := 20.0
const EDIT_H       := 32.0
const BUTTON_H     := 40.0
const MIN_VIS_ROWS := 6
const MAX_VIS_ROWS := 40
const HANDLE_HIT   := 14.0   # Screen-pixel hit radius
const HANDLE_DRAW  := 7.0    # Drawn handle radius

# -- State ---------------------------------------------------------------------
var _active := false
var _mode: Mode = Mode.EDIT

var _test_name: String = ""
var _script: Array[String] = []
var _dirty: bool = false

# Window position and drag
var _window_pos := Vector2(20.0, 60.0)
var _win_drag := false
var _win_drag_off := Vector2.ZERO

# Row list scroll & selection
var _row_scroll: int = 0
var _selected_row: int = -1

# Inline edit field
var _edit_text: String = ""
var _edit_cursor: int = 0
var _edit_sel_start: int = -1
var _edit_valid: bool = true
var _edit_focused: bool = false
var _edit_tab_completions: Array[String] = []
var _edit_tab_index: int = 0

# Common script commands for autocomplete
const SCRIPT_COMMANDS: Array[String] = [
	"spawn monster", "spawn monster 960 880 standdown", "spawn dummy",
	"clear", "clearplayers", "clearzones", "portal off", "portal on",
	"standdown on", "standdown off", "precog",
	"debug on ", "debug log ", "debug off ",
	"debug on precog/platform_list", "debug on precog/graph_edges",
	"debug on testing/planned_leaps", "debug on testing/bounded_leap_checks",
	"debug log precog/current_path",
	"wait ",
	"wait 8 unless breach 0 800 1920 800 monster* dummy*",
	"wait 10 unless exit_circle 960 750 150 dummy*",
	"bleap reset", "bleap a ", "bleap b ", "bleap min ",
	"bleap plan req start ", "bleap plan opt start ",
	"check bounded_leaps ", "check fps > 20", "check zones",
	"etz ", "daz ", "clearzones",
]

# World-space handles
var _handles: Array = []        # [ {id, world_pos, color, style, ...} ]
var _handle_drag: int = -1
var _handle_hover: int = -1
var _drag_parsed: Dictionary = {}

# Row drag-drop reordering
var _row_drag: int = -1         # Source row being dragged (-1 = none)
var _row_drag_target: int = -1  # Drop target position (insert before)
var _row_drag_start_y: float = 0.0

# Double-click to execute single line
var _last_click_row: int = -1
var _last_click_time: float = 0.0

# Test picker
var _picker_open: bool = false
var _picker_filter: String = ""
var _picker_filter_cursor: int = 0
var _picker_items: Array[String] = []
var _picker_sel: int = 0

# Runner state & results
var _run_running: bool = false
var _results_collected: bool = false  # True after _collect_results, even if runner still waiting on notify
var _run_blink: float = 0.0
var _run_results: Dictionary = {}   # {row_idx: "pass"|"fail"|"info", ...}
var _run_detail: Dictionary = {}    # {row_idx: Array[String]} — per-check detail log lines
var _run_summary: String = ""       # "2/2 PASSED" etc.
var _run_leap_edges: Array = []     # Captured leap graph edges after run, with match info
var _breach_marker: Dictionary = {} # {pos: Vector2, entity: String, line: int, idx: int} — rendered on overlay
var _test_override_vars: Dictionary = {} # Variables passed to test runner (e.g., owait)

# Suite queue — runs tests sequentially through the editor
var _suite_queue: Array[String] = []
var _suite_all_tests: Array[String] = []  # Full list of tests in the suite (for prev/next)
var _suite_current_idx: int = 0           # Current position in _suite_all_tests
var _suite_name: String = ""
var _suite_results: Array = []      # [{name, passed}]

# Status flash
var _status_msg: String = ""
var _status_timer: float = 0.0

# Nodes
var _overlay: Node2D = null   # World-space handle drawing
var _panel: Control = null    # Screen-space window drawing


# -- Lifecycle -----------------------------------------------------------------

func _ready() -> void:
	layer = 108
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	_panel = Control.new()
	_panel.name = "TestEditorPanel"
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.draw.connect(_draw_panel)
	add_child(_panel)

	_overlay = Node2D.new()
	_overlay.name = "TestEditorOverlay"
	_overlay.z_index = 50
	_overlay.visible = false
	call_deferred("_add_overlay_to_scene")


func _add_overlay_to_scene() -> void:
	var scene := get_tree().current_scene
	if scene:
		scene.add_child(_overlay)
		_overlay.draw.connect(_draw_overlay)


func toggle() -> void:
	_active = not _active
	visible = _active
	if _overlay:
		_overlay.visible = _active


func _process(delta: float) -> void:
	if not _active:
		return
	_run_blink += delta
	if _status_timer > 0:
		_status_timer -= delta
	# Poll test runner for results when a run finishes
	var rcon_poll: Node = get_node_or_null("/root/Rcon") if _run_running or _results_collected else null
	if rcon_poll and rcon_poll._test_runner:
		var runner: Node = rcon_poll._test_runner
		# Collect results ONCE when COMPLETE fires — editor becomes interactive
		if _run_running and runner._test_state == "COMPLETE" and not _results_collected:
			_collect_results(runner)
			_run_running = false  # Editor interactive immediately
		# Track runner still running (for _run_running cleanup)
		elif _run_running and not runner._running:
			_run_running = false
			if not _results_collected:
				_collect_results(runner)
		# Suite advance: results collected AND runner fully stopped (notify dismissed)
		if _results_collected and not runner._running and not _run_running:
			if (not _suite_queue.is_empty() or not _suite_name.is_empty()):
				_results_collected = false  # Prevent re-triggering
				_suite_advance()
	if _panel:
		_panel.queue_redraw()
	if _overlay:
		_overlay.queue_redraw()


# -- Input ---------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not _active:
		return

	# Picker intercepts all input when open
	if _picker_open:
		_input_picker(event)
		return

	if event is InputEventKey and event.pressed:
		var ctrl: bool = event.ctrl_pressed or event.meta_pressed
		var shift: bool = event.shift_pressed

		match event.keycode:
			KEY_ESCAPE:
				_deselect_row()
				toggle()
				get_viewport().set_input_as_handled()
				return

			KEY_TAB:
				if _edit_focused:
					_edit_autocomplete()
				else:
					_mode = Mode.EDIT if _mode == Mode.RUN else Mode.RUN
				get_viewport().set_input_as_handled()
				return

			KEY_T:
				if not _edit_focused:
					_open_picker()
					get_viewport().set_input_as_handled()
					return

			KEY_S:
				if ctrl:
					_save_test()
					get_viewport().set_input_as_handled()
					return

			KEY_R:
				if ctrl and not _test_name.is_empty():
					_load_test(_test_name)
					_status_msg = "Reloaded from disk"
					_status_timer = 2.0
					get_viewport().set_input_as_handled()
					return

		# Route to edit field if focused
		if _edit_focused:
			_input_edit_field(event, ctrl, shift)
			get_viewport().set_input_as_handled()
			return

		# Row navigation when nothing focused
		match event.keycode:
			KEY_UP:
				if _selected_row > 0:
					_select_row(_selected_row - 1)
				get_viewport().set_input_as_handled()
			KEY_DOWN:
				if _selected_row < _script.size() - 1:
					_select_row(_selected_row + 1)
				elif _selected_row < 0 and not _script.is_empty():
					_select_row(0)
				get_viewport().set_input_as_handled()
			KEY_PAGEUP:
				_row_scroll = maxi(0, _row_scroll - _max_rows_for_viewport())
				if _selected_row >= 0:
					_select_row(maxi(0, _selected_row - _max_rows_for_viewport()))
				get_viewport().set_input_as_handled()
			KEY_PAGEDOWN:
				var max_scroll: int = maxi(0, _script.size() + 1 - _max_rows_for_viewport())
				_row_scroll = mini(max_scroll, _row_scroll + _max_rows_for_viewport())
				if _selected_row >= 0:
					_select_row(mini(_script.size() - 1, _selected_row + _visible_row_count()))
				get_viewport().set_input_as_handled()
			KEY_DELETE:
				# Delete hovered disallow handle, or delete row
				if _handle_hover >= 0 and _try_delete_hovered_handle():
					pass  # Disallow deleted
				elif _selected_row >= 0:
					_delete_row(_selected_row)
				get_viewport().set_input_as_handled()

	# Mouse wheel scroll
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if _get_window_rect().has_point(event.position):
				_row_scroll = maxi(0, _row_scroll - 3)
				get_viewport().set_input_as_handled()
				return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _get_window_rect().has_point(event.position):
				_row_scroll = mini(maxi(0, _script.size() + 1 - _max_rows_for_viewport()), _row_scroll + 3)
				get_viewport().set_input_as_handled()
				return

	# Right-click: delete hovered disallow handle
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if _handle_hover >= 0 and _try_delete_hovered_handle():
			get_viewport().set_input_as_handled()
			return

	# Mouse button — only consume if click is on our window or on a handle
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var full_rect := _get_window_rect()
			full_rect.size.y += 60
			if full_rect.has_point(event.position) or _is_over_handle(event.position):
				_on_mouse_press(event.position)
				get_viewport().set_input_as_handled()
		else:
			# Always handle release if we were dragging something
			if _win_drag or _handle_drag >= 0 or _row_drag >= 0:
				_on_mouse_release()
				get_viewport().set_input_as_handled()

	# Mouse motion
	if event is InputEventMouseMotion:
		if _win_drag:
			_window_pos = event.position - _win_drag_off
			get_viewport().set_input_as_handled()
		elif _row_drag >= 0:
			# Row drag reordering — compute drop target from mouse Y
			if absf(event.position.y - _row_drag_start_y) > 6.0:
				var wy_top: float = _window_pos.y + TITLE_H
				var rel_y: float = event.position.y - wy_top
				_row_drag_target = clampi(_row_scroll + int(rel_y / ROW_H), 0, _script.size())
			get_viewport().set_input_as_handled()
		elif _handle_drag >= 0:
			_do_handle_drag(_get_world_pos(event.position))
			get_viewport().set_input_as_handled()
		else:
			_update_hover(event.position)


# -- Edit field keyboard -------------------------------------------------------

func _input_edit_field(event: InputEventKey, ctrl: bool, shift: bool) -> void:
	match event.keycode:
		KEY_ENTER:
			_apply_edit()
		KEY_ESCAPE:
			_cancel_edit()
		KEY_BACKSPACE:
			if _edit_has_sel():
				_edit_del_sel()
			elif _edit_cursor > 0:
				_edit_text = _edit_text.substr(0, _edit_cursor - 1) + _edit_text.substr(_edit_cursor)
				_edit_cursor -= 1
			_edit_tab_completions.clear()
			_validate_edit()
		KEY_DELETE:
			if _edit_has_sel():
				_edit_del_sel()
			elif _edit_cursor < _edit_text.length():
				_edit_text = _edit_text.substr(0, _edit_cursor) + _edit_text.substr(_edit_cursor + 1)
			_edit_tab_completions.clear()
			_validate_edit()
		KEY_LEFT:
			var np := maxi(0, _edit_cursor - 1)
			if shift: _edit_extend_sel(np)
			else:    _edit_cursor = np; _edit_sel_start = -1
		KEY_RIGHT:
			var np := mini(_edit_text.length(), _edit_cursor + 1)
			if shift: _edit_extend_sel(np)
			else:    _edit_cursor = np; _edit_sel_start = -1
		KEY_HOME:
			if shift: _edit_extend_sel(0)
			else:    _edit_cursor = 0; _edit_sel_start = -1
		KEY_END:
			if shift: _edit_extend_sel(_edit_text.length())
			else:    _edit_cursor = _edit_text.length(); _edit_sel_start = -1
		_:
			if ctrl:
				match event.keycode:
					KEY_A:
						_edit_sel_start = 0
						_edit_cursor = _edit_text.length()
						return
					KEY_C:
						if _edit_has_sel():
							DisplayServer.clipboard_set(_edit_get_sel())
						return
					KEY_X:
						if _edit_has_sel():
							DisplayServer.clipboard_set(_edit_get_sel())
							_edit_del_sel()
							_validate_edit()
						return
					KEY_V:
						var clip := DisplayServer.clipboard_get().replace("\n", " ").strip_edges()
						if not clip.is_empty():
							if _edit_has_sel():
								_edit_del_sel()
							_edit_text = _edit_text.substr(0, _edit_cursor) + clip + _edit_text.substr(_edit_cursor)
							_edit_cursor += clip.length()
							_validate_edit()
						return
			if event.unicode > 0 and not ctrl:
				if _edit_has_sel():
					_edit_del_sel()
				var ch := char(event.unicode)
				_edit_text = _edit_text.substr(0, _edit_cursor) + ch + _edit_text.substr(_edit_cursor)
				_edit_cursor += 1
				_edit_tab_completions.clear()
				_validate_edit()


func _edit_has_sel() -> bool:
	return _edit_sel_start >= 0 and _edit_sel_start != _edit_cursor

func _edit_get_sel() -> String:
	if not _edit_has_sel():
		return ""
	return _edit_text.substr(mini(_edit_sel_start, _edit_cursor),
		absi(_edit_cursor - _edit_sel_start))

func _edit_del_sel() -> void:
	var f := mini(_edit_sel_start, _edit_cursor)
	var t := maxi(_edit_sel_start, _edit_cursor)
	_edit_text = _edit_text.substr(0, f) + _edit_text.substr(t)
	_edit_cursor = f
	_edit_sel_start = -1

func _edit_extend_sel(new_pos: int) -> void:
	if _edit_sel_start < 0:
		_edit_sel_start = _edit_cursor
	_edit_cursor = new_pos

func _edit_autocomplete() -> void:
	## Tab autocomplete — cycles through matching script commands.
	## Context-sensitive: completes spawn states, debug aspects, etc.
	if _edit_text.strip_edges().is_empty():
		return

	# Build completions on first Tab press
	if _edit_tab_completions.is_empty():
		var prefix: String = _edit_text.strip_edges().to_lower()
		var text: String = _edit_text.strip_edges()

		# Command prefix matching
		for cmd in SCRIPT_COMMANDS:
			if cmd.to_lower().begins_with(prefix):
				_edit_tab_completions.append(cmd)

		# Context: "spawn monster/dummy X Y " → complete state
		if prefix.begins_with("spawn monster ") or prefix.begins_with("spawn dummy "):
			var parts := text.split(" ", false)
			if parts.size() >= 4:
				# Complete the state parameter
				var base: String = "%s %s %s" % [parts[0], parts[1], " ".join(PackedStringArray(parts.slice(2, 4)))]
				for state in ["standdown"]:
					var candidate: String = base + " " + state
					if candidate.to_lower().begins_with(prefix) or parts.size() == 4:
						_edit_tab_completions.append(candidate)

		# Context: "debug on/log/off " → complete aspect names
		if prefix.begins_with("debug on ") or prefix.begins_with("debug log ") or prefix.begins_with("debug off "):
			var space2: int = prefix.find(" ", 6)
			if space2 >= 0:
				var aspect_prefix: String = prefix.substr(space2 + 1)
				var mode_prefix: String = text.substr(0, space2 + 1)
				for aspect in DebugOverlay.get_aspect_paths():
					if aspect.to_lower().begins_with(aspect_prefix):
						_edit_tab_completions.append(mode_prefix + aspect)

		# Context: "bleap plan " → complete req/opt templates
		if prefix.begins_with("bleap plan "):
			if not prefix.begins_with("bleap plan req") and not prefix.begins_with("bleap plan opt"):
				_edit_tab_completions.append("bleap plan req start ")
				_edit_tab_completions.append("bleap plan opt start ")

		# Context: "wait " with number → complete breach template
		if prefix.begins_with("wait "):
			var parts := text.split(" ", false)
			if parts.size() >= 2 and parts[1].is_valid_float():
				if parts.size() == 2 or (parts.size() > 2 and not prefix.contains("unless")):
					_edit_tab_completions.append("wait %s unless breach 0 800 1920 800 monster* dummy*" % parts[1])

		_edit_tab_index = 0

	if _edit_tab_completions.is_empty():
		return

	_edit_text = _edit_tab_completions[_edit_tab_index]
	_edit_cursor = _edit_text.length()
	_edit_sel_start = -1
	_edit_tab_index = (_edit_tab_index + 1) % _edit_tab_completions.size()
	_validate_edit()


func _validate_edit() -> void:
	var p := _parse_command(_edit_text.strip_edges())
	_edit_valid = true  # Accept all — invalid lines are just stored as-is
	# Rebuild handles live if parse produces geometry
	if _selected_row >= 0 and not p.get("type", "none") == "none":
		_drag_parsed = p
		_handles = _build_handles(p)


func _apply_edit() -> void:
	if _selected_row >= 0 and _selected_row < _script.size():
		_script[_selected_row] = _edit_text.strip_edges()
		_dirty = true
		_handles = _build_handles(_parse_command(_script[_selected_row]))
	_edit_focused = false


func _cancel_edit() -> void:
	if _selected_row >= 0 and _selected_row < _script.size():
		_edit_text = _script[_selected_row]
		_edit_cursor = _edit_text.length()
	_edit_focused = false


# -- Mouse handling ------------------------------------------------------------

func _on_mouse_press(screen_pos: Vector2) -> void:
	var win_rect := _get_window_rect()
	# Title bar → start window drag
	if Rect2(win_rect.position, Vector2(win_rect.size.x, TITLE_H)).has_point(screen_pos):
		_win_drag = true
		_win_drag_off = screen_pos - _window_pos
		return

	# Inside window → check rows, buttons
	if win_rect.has_point(screen_pos):
		_handle_window_click(screen_pos, win_rect)
		return

	# Outside window → try handle hit
	if _mode == Mode.EDIT:
		var world_pos := _get_world_pos(screen_pos)
		_try_start_handle_drag(world_pos)


func _on_mouse_release() -> void:
	_win_drag = false
	if _handle_drag >= 0:
		# Commit drag: apply formatted command back to script
		if _selected_row >= 0 and _selected_row < _script.size():
			_script[_selected_row] = _format_command(_drag_parsed)
			_dirty = true
			_edit_text = _script[_selected_row]
			_edit_cursor = _edit_text.length()
		_handle_drag = -1
	if _row_drag >= 0 and _row_drag_target >= 0 and _row_drag_target != _row_drag:
		# Perform row move
		var line: String = _script[_row_drag]
		_script.remove_at(_row_drag)
		var insert_at: int = _row_drag_target if _row_drag_target < _row_drag else _row_drag_target - 1
		insert_at = clampi(insert_at, 0, _script.size())
		_script.insert(insert_at, line)
		_dirty = true
		_select_row(insert_at)
	_row_drag = -1
	_row_drag_target = -1


func _handle_window_click(screen_pos: Vector2, win_rect: Rect2) -> void:
	var local_y := screen_pos.y - win_rect.position.y

	# Below title bar
	var y_offset: float = TITLE_H
	var row_zone_h: float = _visible_row_count() * ROW_H
	if local_y >= y_offset and local_y < y_offset + row_zone_h:
		var row_idx: int = _row_scroll + int((local_y - y_offset) / ROW_H)
		var local_x: float = screen_pos.x - win_rect.position.x

		if _run_running or _results_collected:
			# Run/review mode: click selects row (to view details) but no editing/drag
			if row_idx < _script.size():
				var old_sel := _selected_row
				_selected_row = row_idx
				_edit_focused = false
				print("ROW_SELECT: old=%d new=%d script_size=%d" % [old_sel, row_idx, _script.size()])
			return

		# Ghost "add" row at bottom
		if row_idx >= _script.size():
			_script.append("")
			_dirty = true
			_select_row(_script.size() - 1)
			_row_drag = _script.size() - 1
			_row_drag_target = -1
			_row_drag_start_y = screen_pos.y
			return

		# Red X delete button on right edge
		if local_x >= WINDOW_W - 22.0:
			_delete_row(row_idx)
			return

		# Double-click → execute single line
		var now: float = Time.get_ticks_msec() / 1000.0
		if row_idx == _last_click_row and (now - _last_click_time) < 0.35:
			_execute_single_line(row_idx)
			_last_click_row = -1
			return
		_last_click_row = row_idx
		_last_click_time = now

		# Normal row click — select + start drag
		_select_row(row_idx)
		_row_drag = row_idx
		_row_drag_target = -1
		_row_drag_start_y = screen_pos.y
		return

	y_offset += row_zone_h

	if _selected_row >= 0:
		if not _run_running and local_y >= y_offset and local_y < y_offset + _edit_field_height():
			# Click in edit field → focus it (only in edit mode)
			_edit_focused = true
			return
		y_offset += _edit_field_height()
		y_offset += _detail_panel_height()
		# Notify help panel height
		if _selected_row < _script.size() and _script[_selected_row].strip_edges().begins_with("notify ") and get_meta("notify_active", false):
			y_offset += 56.0

	# Button bar
	if local_y >= y_offset and local_y < y_offset + BUTTON_H:
		var lx := screen_pos.x - win_rect.position.x
		_handle_button_click(lx)
		return



func _handle_button_click(local_x: float) -> void:
	## Button bar: [▶/⏸] [⏹] [↺] [+] [✕] [+dis?] [💾]
	var btns := _get_buttons()
	var bw: float = (WINDOW_W - 16.0) / float(btns.size())
	var btn: int = int((local_x - 8.0) / bw)
	if btn < 0 or btn >= btns.size():
		return
	var action: String = btns[btn][2]
	match action:
		"play":
			if _run_running: _pause_test()
			else: _run_test()
		"stop":   _stop_test()
		"restart": _restart_test()
		"add_dis": _try_add_disallow()
		"add_fence": _try_add_fence()
		"add_exit_circle": _try_add_exit_circle()
		"suite_prev": _suite_goto(_suite_current_idx - 1)
		"suite_next": _suite_goto(_suite_current_idx + 1)
		"notify_done":
			var rcon: Node = get_node_or_null("/root/Rcon")
			if rcon:
				rcon._cmd_notify_dismiss("OK")
		"save":   _save_test()


func _get_buttons() -> Array:
	## Returns button definitions. Context-sensitive: includes +dis when bleap plan is selected.
	var btns: Array = [
		["▶" if not _run_running else "⏸", Color(0.3, 0.9, 0.3) if not _run_running else Color(0.9, 0.7, 0.2), "play"],
		["⏹", Color(0.9, 0.4, 0.4), "stop"],
		["↺", Color(0.4, 0.7, 1.0), "restart"],
	]
	# Show +dis button when selected row is a bleap plan
	if _selected_row >= 0 and _selected_row < _script.size():
		var sel_p := _parse_command(_script[_selected_row])
		var sel_type: String = sel_p.get("type", "none")
		if sel_type == "bleap_plan":
			btns.append(["+dis", Color(0.9, 0.5, 0.5), "add_dis"])
		elif sel_type == "wait_plain" or sel_type == "wait_breach":
			btns.append(["+fence", Color(1.0, 0.6, 0.1), "add_fence"])
			btns.append(["+exit", Color(0.9, 0.7, 0.2), "add_exit_circle"])
	# Suite navigation
	if not _suite_all_tests.is_empty():
		if _suite_current_idx > 0:
			btns.append(["◀", Color(0.6, 0.7, 1.0), "suite_prev"])
		if get_meta("notify_active", false):
			btns.append(["Done ▶", Color(0.3, 1.0, 0.6), "notify_done"])
		if _suite_current_idx < _suite_all_tests.size() - 1 and not get_meta("notify_active", false):
			btns.append(["▶", Color(0.6, 0.7, 1.0), "suite_next"])
	elif get_meta("notify_active", false):
		btns.append(["Done ✓", Color(0.3, 1.0, 0.6), "notify_done"])
	btns.append(["💾", Color(0.8, 0.8, 0.4), "save"])
	return btns


func _is_over_handle(screen_pos: Vector2) -> bool:
	## True if screen_pos is close enough to any handle to count as a click on it.
	for h: Dictionary in _handles:
		var hsp := _world_to_screen(h["world_pos"])
		if screen_pos.distance_to(hsp) <= HANDLE_HIT:
			return true
	return false


func _update_hover(screen_pos: Vector2) -> void:
	var world_pos := _get_world_pos(screen_pos)
	var prev := _handle_hover
	_handle_hover = -1
	for i in range(_handles.size()):
		var h: Dictionary = _handles[i]
		var hsp := _world_to_screen(h["world_pos"])
		if screen_pos.distance_to(hsp) <= HANDLE_HIT:
			_handle_hover = i
			break
	if _handle_hover != prev:
		if _panel: _panel.queue_redraw()


func _try_start_handle_drag(world_pos: Vector2) -> void:
	if _selected_row < 0 or _script.is_empty():
		return
	for i in range(_handles.size()):
		var h: Dictionary = _handles[i]
		if world_pos.distance_to(h["world_pos"]) <= HANDLE_HIT * _world_hit_scale():
			_handle_drag = i
			_drag_parsed = _parse_command(_script[_selected_row])
			return


func _do_handle_drag(world_pos: Vector2) -> void:
	if _handle_drag < 0 or _drag_parsed.is_empty():
		return
	var h: Dictionary = _handles[_handle_drag]
	_apply_handle_drag(_drag_parsed, h["id"], world_pos)
	# Rebuild handles from updated params
	_handles = _build_handles(_drag_parsed)
	# Live-update edit text
	_edit_text = _format_command(_drag_parsed)
	_edit_cursor = _edit_text.length()
	_edit_sel_start = -1


# -- Row management ------------------------------------------------------------

func _select_row(idx: int) -> void:
	_selected_row = idx
	_edit_focused = true
	if idx >= 0 and idx < _script.size():
		_edit_text = _script[idx]
		_edit_cursor = _edit_text.length()
		_edit_sel_start = -1
		_handles = _build_handles(_parse_command(_script[idx]))
		# Scroll to keep selected row visible
		if idx < _row_scroll:
			_row_scroll = idx
		elif idx >= _row_scroll + _max_rows_for_viewport():
			_row_scroll = idx - _max_rows_for_viewport() + 1
	else:
		_handles = []


func _deselect_row() -> void:
	_selected_row = -1
	_edit_focused = false
	_handles = []


func _delete_row(idx: int) -> void:
	if idx < 0 or idx >= _script.size():
		return
	var deleted_line: String = _script[idx].strip_edges()
	_script.remove_at(idx)
	_dirty = true
	if _selected_row >= _script.size():
		_selected_row = _script.size() - 1
	if _selected_row >= 0:
		_select_row(_selected_row)
	else:
		_deselect_row()
	# If an ETZ/DAZ line was deleted, rebuild zones from remaining lines
	if deleted_line.begins_with("etz ") or deleted_line.begins_with("daz ") or deleted_line == "clearzones":
		_rebuild_zones()


func _rebuild_zones() -> void:
	## Clear all zones and re-execute ETZ/DAZ lines from the current script.
	var rcon: Node = get_node_or_null("/root/Rcon")
	if not rcon:
		return
	rcon._execute("clearzones")
	for line in _script:
		var l := line.strip_edges()
		if l.begins_with("etz ") or l.begins_with("daz "):
			rcon._execute(l)


func _insert_row_after_selected() -> void:
	var insert_at: int = (_selected_row + 1) if _selected_row >= 0 else _script.size()
	_script.insert(insert_at, "")
	_dirty = true
	_select_row(insert_at)


# -- Single line execution -----------------------------------------------------

func _execute_single_line(row_idx: int) -> void:
	## Execute one script line immediately via RCON.
	if row_idx < 0 or row_idx >= _script.size():
		return
	var line: String = _script[row_idx].strip_edges()
	if line.is_empty() or line.begins_with("#"):
		return
	# Meta-commands can't be executed standalone
	if line.begins_with("check "):
		_status_msg = "Cannot run 'check' standalone"
		_status_timer = 2.0
		return
	if line.begins_with("wait "):
		_status_msg = "Cannot run 'wait' standalone"
		_status_timer = 2.0
		return
	var rcon: Node = get_node_or_null("/root/Rcon")
	if not rcon:
		return
	var result: String = rcon._execute(line)
	_status_msg = "%d: %s" % [row_idx + 1, result.substr(0, 80)]
	_status_timer = 3.0


# -- Disallow add/delete -------------------------------------------------------

func _try_add_disallow() -> void:
	## Add a disallow zone to the selected row if it's a bleap plan command.
	if _selected_row < 0 or _selected_row >= _script.size():
		return
	var p := _parse_command(_script[_selected_row])
	if p.get("type", "none") != "bleap_plan":
		_status_msg = "D: select a bleap plan row first"
		_status_timer = 2.0
		return
	# Default disallow near center of screen
	var vp := get_viewport().get_visible_rect().size
	var center := _get_world_pos(vp / 2.0)
	if not p.has("disallows"):
		p["disallows"] = []
	p["disallows"].append({"r": 60.0, "x1": center.x - 50, "y1": center.y, "x2": center.x + 50, "y2": center.y})
	_script[_selected_row] = _format_command(p)
	_dirty = true
	_edit_text = _script[_selected_row]
	_edit_cursor = _edit_text.length()
	_handles = _build_handles(p)
	_status_msg = "Added disallow zone"
	_status_timer = 1.5


func _try_add_fence() -> void:
	## Add a breach fence to the selected wait row.
	## Works on both plain "wait N" and existing "wait N unless breach ..." (adds another fence).
	if _selected_row < 0 or _selected_row >= _script.size():
		return
	var p := _parse_command(_script[_selected_row])
	var ptype: String = p.get("type", "none")
	if ptype == "wait_plain":
		# Upgrade to wait_breach with one fence
		p = {"type": "wait_breach", "duration": p["duration"],
			"fences": [{"x1": 0, "y1": 800, "x2": 1920, "y2": 800, "patterns": ["monster*", "dummy*"]}]}
	elif ptype == "wait_breach":
		# Add another fence — offset from the last one
		var last: Dictionary = p["fences"].back() if not p["fences"].is_empty() else {}
		var y_off: float = last.get("y1", 800) - 100 if not last.is_empty() else 800
		p["fences"].append({"x1": 0, "y1": y_off, "x2": 1920, "y2": y_off, "patterns": ["monster*", "dummy*"]})
	else:
		_status_msg = "Select a 'wait' row first"
		_status_timer = 2.0
		return
	_script[_selected_row] = _format_command(p)
	_dirty = true
	_edit_text = _script[_selected_row]
	_edit_cursor = _edit_text.length()
	_handles = _build_handles(_parse_command(_script[_selected_row]))
	var n: int = p.get("fences", []).size()
	_status_msg = "Fence added (%d total) — drag endpoints" % n
	_status_timer = 2.5


func _try_add_exit_circle() -> void:
	## Add an exit_circle condition to the selected wait row.
	if _selected_row < 0 or _selected_row >= _script.size():
		return
	var p := _parse_command(_script[_selected_row])
	var ptype: String = p.get("type", "none")
	if ptype == "wait_plain":
		p = {"type": "wait_breach", "duration": p["duration"],
			"fences": [], "circles": [{"x": 960, "y": 750, "r": 150, "patterns": ["dummy*"]}]}
	elif ptype == "wait_breach":
		if not p.has("circles"):
			p["circles"] = []
		p["circles"].append({"x": 960, "y": 750, "r": 150, "patterns": ["dummy*"]})
	else:
		_status_msg = "Select a 'wait' row first"
		_status_timer = 2.0
		return
	_script[_selected_row] = _format_command(p)
	_dirty = true
	_edit_text = _script[_selected_row]
	_edit_cursor = _edit_text.length()
	_handles = _build_handles(_parse_command(_script[_selected_row]))
	var n: int = p.get("circles", []).size()
	_status_msg = "Exit circle added (%d total) — drag center/radius" % n
	_status_timer = 2.5


func _try_delete_hovered_handle() -> bool:
	## Delete the hovered handle's parent element (disallow zone or fence). Returns true if deleted.
	if _handle_hover < 0 or _handle_hover >= _handles.size():
		return false
	if _selected_row < 0 or _selected_row >= _script.size():
		return false
	var hid: String = _handles[_handle_hover].get("id", "")
	var p := _parse_command(_script[_selected_row])

	# Delete disallow zone from bleap plan
	if hid.begins_with("dis_") and p.get("type", "none") == "bleap_plan":
		var segs := hid.split("_")  # ["dis","0","p1"]
		if segs.size() < 3:
			return false
		var di: int = int(segs[1])
		var disallows: Array = p.get("disallows", [])
		if di >= disallows.size():
			return false
		disallows.remove_at(di)
		_commit_parsed(p, "Deleted disallow zone")
		return true

	# Delete exit_circle from wait_breach
	if hid.begins_with("circ_") and p.get("type", "none") == "wait_breach":
		var segs := hid.split("_")  # ["circ","0","center"]
		if segs.size() >= 3:
			var ci: int = int(segs[1])
			var circles: Array = p.get("circles", [])
			if ci < circles.size():
				circles.remove_at(ci)
				if p.get("fences", []).is_empty() and circles.is_empty():
					p = {"type": "wait_plain", "duration": p["duration"], "raw": "wait %.0f" % p["duration"]}
				_commit_parsed(p, "Deleted exit_circle (%d remaining)" % circles.size())
				return true

	# Delete fence from wait_breach
	if hid.begins_with("fence_") and p.get("type", "none") == "wait_breach":
		var segs := hid.split("_")  # ["fence","0","p1"]
		if segs.size() < 3:
			return false
		var fi: int = int(segs[1])
		var fences: Array = p.get("fences", [])
		if fi >= fences.size():
			return false
		fences.remove_at(fi)
		if fences.is_empty() and p.get("circles", []).is_empty():
			p = {"type": "wait_plain", "duration": p["duration"], "raw": "wait %.0f" % p["duration"]}
		_commit_parsed(p, "Deleted fence (%d remaining)" % fences.size())
		return true

	return false


func _commit_parsed(p: Dictionary, msg: String) -> void:
	## Write a parsed command back to the script and refresh UI state.
	_script[_selected_row] = _format_command(p)
	_dirty = true
	_edit_text = _script[_selected_row]
	_edit_cursor = _edit_text.length()
	_handles = _build_handles(_parse_command(_script[_selected_row]))
	_handle_hover = -1
	_status_msg = msg
	_status_timer = 1.5


# -- Test picker ---------------------------------------------------------------

func _open_picker() -> void:
	_picker_open = true
	_picker_filter = ""
	_picker_filter_cursor = 0
	_picker_sel = 0
	_refresh_picker_items("")


func _refresh_picker_items(filter: String) -> void:
	_picker_items.clear()
	var lower_filter := filter.to_lower()
	for dir_path in ["res://data/tests/", "user://data/tests/"]:
		var dir := DirAccess.open(dir_path)
		if not dir:
			continue
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if fname.ends_with(".json") and not dir.current_is_dir():
				var name := fname.replace(".json", "")
				if filter.is_empty() or name.to_lower().contains(lower_filter):
					_picker_items.append(name)
			fname = dir.get_next()
	_picker_items.sort()
	_picker_sel = 0


func _input_picker(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	match event.keycode:
		KEY_ESCAPE:
			_picker_open = false
			get_viewport().set_input_as_handled()
		KEY_ENTER:
			if _picker_sel < _picker_items.size():
				_load_test(_picker_items[_picker_sel])
				_picker_open = false
			get_viewport().set_input_as_handled()
		KEY_UP:
			_picker_sel = maxi(0, _picker_sel - 1)
			get_viewport().set_input_as_handled()
		KEY_DOWN:
			_picker_sel = mini(_picker_items.size() - 1, _picker_sel + 1)
			get_viewport().set_input_as_handled()
		KEY_BACKSPACE:
			if _picker_filter.length() > 0:
				_picker_filter = _picker_filter.substr(0, _picker_filter.length() - 1)
				_refresh_picker_items(_picker_filter)
			get_viewport().set_input_as_handled()
		_:
			if event.unicode > 0:
				_picker_filter += char(event.unicode)
				_picker_filter_cursor = _picker_filter.length()
				_refresh_picker_items(_picker_filter)
			get_viewport().set_input_as_handled()


# -- Test load/save/run --------------------------------------------------------

func _load_test(test_name: String) -> void:
	## Load a test via RCON testload, then sync script state here.
	var rcon: Node = get_node_or_null("/root/Rcon")
	if not rcon:
		return
	var result: String = rcon._execute("testload " + test_name)
	if result.begins_with("ERR"):
		return
	_test_name = test_name
	_script = rcon._test_script.duplicate()
	_dirty = false
	_selected_row = -1
	_handles = []
	_edit_focused = false
	_mode = Mode.EDIT
	_run_results.clear()
	_run_detail.clear()
	_run_summary = ""
	_run_leap_edges.clear()
	_breach_marker = {}
	_results_collected = false
	# Clear the scene for a clean test environment
	rcon._execute("clear")
	rcon._execute("clearplayers")
	rcon._execute("clearzones")
	rcon._execute("portal off")


func _save_test() -> void:
	var rcon: Node = get_node_or_null("/root/Rcon")
	if not rcon:
		return
	# Sync any pending edit
	if _selected_row >= 0 and _edit_focused:
		_apply_edit()
	# Push script to RCON then save
	rcon._test_script = _script.duplicate()
	rcon._test_script_name = _test_name
	var save_result: String = rcon._execute("testsave")
	_dirty = false
	_status_msg = save_result
	_status_timer = 3.0


func _run_test() -> void:
	var rcon: Node = get_node_or_null("/root/Rcon")
	if not rcon:
		return
	if _selected_row >= 0 and _edit_focused:
		_apply_edit()
	# Force-stop any previous run
	if rcon._notify_active:
		rcon._cmd_notify_dismiss("OK")
	rcon._ensure_test_runner()
	if rcon._test_runner:
		rcon._test_runner._running = false
		rcon._test_runner._task_queue.clear()
	_run_results.clear()
	_run_detail.clear()
	_run_summary = ""
	_run_leap_edges.clear()
	_breach_marker = {}
	_results_collected = false
	_run_running = true
	rcon._test_script = _script.duplicate()
	rcon._test_script_name = _test_name
	rcon._ensure_test_runner()
	if rcon._test_runner:
		# Pass override variables (e.g., owait=600 for interactive mode)
		rcon._test_runner._override_vars = _test_override_vars.duplicate()
		rcon._test_runner.run_test_script(_script, _test_name, null)
		_run_running = true
		_mode = Mode.RUN


func _collect_results(runner: Node) -> void:
	## Map the test runner's results back to script row indices and build the summary.
	_results_collected = true
	_run_results.clear()
	var total: int = 0
	var passed: int = 0

	for r: Dictionary in runner._results:
		var r_passed: bool = r.get("passed", false)
		var r_log: Array = r.get("log", [])
		total += 1
		if r_passed:
			passed += 1
		# Map checks back to the script row that triggered them
		for c: Dictionary in r.get("checks", []):
			var check_label: String = c.get("label", "")
			var check_passed: bool = c.get("passed", false)
			# Find the "check" row in the script that produced this result
			for si in range(_script.size()):
				var line: String = _script[si].strip_edges()
				if line.begins_with("check ") and check_label in line:
					_run_results[si] = "pass" if check_passed else "fail"
					_run_detail[si] = r_log
					_propagate_check_result_to_bleap_rows(si, check_passed)
					# Propagate zone results to ETZ/DAZ rows
					if check_label == "zones" or "etz" in check_label or "daz" in check_label:
						_propagate_zone_results(si, r_log)
					break

	# Mark wait rows for visual context
	for si in range(_script.size()):
		if not _run_results.has(si):
			var line: String = _script[si].strip_edges()
			if line.begins_with("wait "):
				_run_results[si] = "info"

	_run_summary = "%d/%d PASSED" % [passed, total]

	# Auto-select the first failed check row so the human can see what went wrong
	for si in range(_script.size()):
		if _run_results.get(si, "") == "fail":
			_select_row(si)
			break
	_mode = Mode.EDIT

	# Use the test runner's captured leap evaluation (evaluated at check time, not after)
	_run_leap_edges = runner._last_leap_eval.duplicate(true)
	print("EDITOR: collected %d leap edges for overlay" % _run_leap_edges.size())

	# Capture breach marker for rendering
	_breach_marker = {}
	if not runner._breach_result.is_empty():
		var bc: Dictionary = runner._breach_result.get("condition", {})
		_breach_marker = {
			"pos": runner._breach_result.get("pos", Vector2.ZERO),
			"entity": runner._breach_result.get("entity", ""),
			"idx": bc.get("idx", -1),
			"type": bc.get("cond_type", ""),
			"line": runner._breach_result.get("line", runner._current_task_line + 1),
		}


func _capture_leap_edges() -> void:
	## Grab the monster's leap graph and evaluate each edge against the bleap plan constraints.
	_run_leap_edges.clear()
	_breach_marker = {}
	var rcon: Node = get_node_or_null("/root/Rcon")
	if not rcon:
		return
	# Collect all edges from all monsters
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy.has_method("get_leap_graph"):
			continue
		var graph: Array = enemy.get_leap_graph()
		for edge in graph:
			var arc_c: PackedVector2Array = edge.get("arc_c", PackedVector2Array())
			var from_pos: Vector2 = edge.get("from_pos", Vector2.ZERO)
			var arrival: Vector2 = edge.get("arrival", Vector2.ZERO)
			# Evaluate this edge against each bleap plan in the script
			var edge_result: String = "none"  # "none", "matched", "failed", "no_candidate"
			var breach_points: Array = []  # [{pos, reason}]
			# Collect all bleap plan defs from the script
			var plans: Array = _collect_bleap_plans()
			if plans.is_empty():
				edge_result = "none"
				print("LEAP EVAL: no bleap plans found in script")
			else:
				var any_candidate := false
				for plan_info: Dictionary in plans:
					var plat_a: Dictionary = plan_info.get("plat_a", {})
					var plat_b: Dictionary = plan_info.get("plat_b", {})
					# Check if edge goes from platform A to platform B
					var from_ok := _circle_contains(plat_a, edge.get("from_plat_pos", Vector2.ZERO),
						edge.get("from_plat_min_x", 0.0), edge.get("from_plat_max_x", 0.0))
					var to_ok := _circle_contains(plat_b, edge.get("to_plat_pos", Vector2.ZERO),
						edge.get("to_plat_min_x", 0.0), edge.get("to_plat_max_x", 0.0))
					if not from_ok or not to_ok:
						continue
					any_candidate = true
					# Check each plan's constraints
					for plan: Dictionary in plan_info.get("plans", []):
						var plan_ok := true
						# START rect
						var st: Dictionary = plan.get("start", {})
						if not st.is_empty():
							var rect := Rect2(float(st.get("x", 0)), float(st.get("y", 0)),
								float(st.get("w", 9999)), float(st.get("h", 9999)))
							if not rect.has_point(from_pos):
								plan_ok = false
								breach_points.append({"pos": from_pos, "reason": "outside START"})
						# END circle
						var ed: Dictionary = plan.get("end", {})
						if not ed.is_empty():
							var ec := Vector2(float(ed.get("x", 0)), float(ed.get("y", 0)))
							if arrival.distance_to(ec) > float(ed.get("r", 9999)):
								plan_ok = false
								breach_points.append({"pos": arrival, "reason": "outside END"})
						# DISALLOW capsules
						var dis_breaches: int = 0
						for dis: Dictionary in plan.get("disallows", []):
							var dr: float = float(dis.get("r", 20))
							var p1 := Vector2(float(dis.get("x1", 0)), float(dis.get("y1", 0)))
							var p2 := Vector2(float(dis.get("x2", 0)), float(dis.get("y2", 0)))
							for pt: Vector2 in arc_c:
								if _dist_pt_seg(pt, p1, p2) < dr:
									plan_ok = false
									dis_breaches += 1
									breach_points.append({"pos": pt, "reason": "disallow"})
						print("  PLAN EVAL: start_ok=%s end_ok=%s dis_breaches=%d plan_ok=%s" % [
							str(not plan.has("start") or plan.get("start", {}).is_empty() or Rect2(float(plan.get("start",{}).get("x",0)), float(plan.get("start",{}).get("y",0)), float(plan.get("start",{}).get("w",9999)), float(plan.get("start",{}).get("h",9999))).has_point(from_pos)),
							str(not plan.has("end") or plan.get("end", {}).is_empty() or arrival.distance_to(Vector2(float(plan.get("end",{}).get("x",0)), float(plan.get("end",{}).get("y",0)))) <= float(plan.get("end",{}).get("r",9999))),
							dis_breaches, str(plan_ok)])
						if plan_ok:
							edge_result = "matched"
							breach_points.clear()
							break  # This plan matched — edge is good
					if edge_result == "matched":
						break
				if edge_result != "matched":
					edge_result = "failed" if any_candidate else "no_candidate"

			_run_leap_edges.append({
				"arc_c": arc_c,
				"from_pos": from_pos,
				"arrival": arrival,
				"result": edge_result,
				"breach_points": breach_points,
			})
			if edge_result == "failed":
				print("LEAP EDGE FAILED: from=(%.0f,%.0f) arrival=(%.0f,%.0f) breaches=%d" % [
					from_pos.x, from_pos.y, arrival.x, arrival.y, breach_points.size()])
				for bp: Dictionary in breach_points:
					print("  breach: %s at (%.0f,%.0f)" % [bp.get("reason","?"), bp["pos"].x, bp["pos"].y])


func _collect_bleap_plans() -> Array:
	## Parse the script to reconstruct the bleap state: platform A/B and plans.
	## Returns array of {plat_a, plat_b, plans} dicts (one per bleap reset block).
	var result: Array = []
	var plat_a: Dictionary = {}
	var plat_b: Dictionary = {}
	var plans: Array = []
	for line in _script:
		var l := line.strip_edges()
		if l == "bleap reset":
			if not plat_a.is_empty() or not plans.is_empty():
				result.append({"plat_a": plat_a, "plat_b": plat_b, "plans": plans})
			plat_a = {}; plat_b = {}; plans = []
		elif l == "bleap next":
			if not plat_a.is_empty() or not plans.is_empty():
				result.append({"plat_a": plat_a, "plat_b": plat_b, "plans": plans})
			plat_a = {}; plat_b = {}; plans = []
		elif l.begins_with("bleap a "):
			var parts := l.split(" ", false)
			if parts.size() >= 5:
				plat_a = {"x": float(parts[2]), "y": float(parts[3]), "radius": float(parts[4])}
		elif l.begins_with("bleap b "):
			var parts := l.split(" ", false)
			if parts.size() >= 5:
				plat_b = {"x": float(parts[2]), "y": float(parts[3]), "radius": float(parts[4])}
		elif l.begins_with("bleap plan "):
			var p := _parse_command(l)
			if p.get("type", "") == "bleap_plan":
				var plan_dict: Dictionary = {}
				if not p.get("start", {}).is_empty():
					plan_dict["start"] = p["start"]
				if not p.get("end", {}).is_empty():
					plan_dict["end"] = p["end"]
				if not p.get("disallows", []).is_empty():
					# Convert disallows format to match test_runner's expected format
					var dis_arr: Array = []
					for d: Dictionary in p["disallows"]:
						dis_arr.append({"r": d["r"], "x1": d["x1"], "y1": d["y1"], "x2": d["x2"], "y2": d["y2"]})
					plan_dict["disallows"] = dis_arr
				plan_dict["required"] = p.get("required", false)
				plans.append(plan_dict)
	# Flush last block
	if not plat_a.is_empty() or not plans.is_empty():
		result.append({"plat_a": plat_a, "plat_b": plat_b, "plans": plans})
	return result


func _circle_contains(circle: Dictionary, plat_pos: Vector2, plat_min_x: float, plat_max_x: float) -> bool:
	if circle.is_empty():
		return true
	var cx: float = float(circle.get("x", 0))
	var cy: float = float(circle.get("y", 0))
	var cr: float = float(circle.get("radius", 0))
	var closest_x: float = clampf(cx, plat_min_x, plat_max_x)
	return Vector2(cx, cy).distance_to(Vector2(closest_x, plat_pos.y)) <= cr


func _dist_pt_seg(pt: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.001:
		return pt.distance_to(a)
	var t := clampf((pt - a).dot(ab) / len_sq, 0.0, 1.0)
	return pt.distance_to(a + t * ab)


func _propagate_check_result_to_bleap_rows(check_row: int, check_passed: bool) -> void:
	## Walk backwards from a "check bounded_leaps" row and mark all preceding bleap rows
	## with the check result, so their world visuals show pass/fail coloring.
	var result_str: String = "pass" if check_passed else "fail"
	for si in range(check_row - 1, -1, -1):
		var line: String = _script[si].strip_edges()
		if line.begins_with("bleap "):
			_run_results[si] = result_str
		elif line.begins_with("check "):
			break  # Hit a previous check — stop


func _propagate_zone_results(check_row: int, log_lines: Array) -> void:
	## Read zone check log lines and mark ETZ/DAZ rows with per-zone pass/fail.
	## Log lines look like: "[PASS] etz (2/2)", "[FAIL] etz (1/2)", "[FAIL] daz (violations: 1)"
	var etz_passed: bool = true
	var daz_passed: bool = true
	var etz_entered: int = 0
	var etz_total: int = 0
	for log_line: String in log_lines:
		if "etz" in log_line:
			if "[FAIL]" in log_line:
				etz_passed = false
			# Parse "etz (1/2)" to get counts
			var paren := log_line.find("(")
			if paren >= 0:
				var inner := log_line.substr(paren + 1, log_line.find(")") - paren - 1)
				var slash := inner.find("/")
				if slash >= 0:
					etz_entered = int(inner.substr(0, slash))
					etz_total = int(inner.substr(slash + 1))
		if "daz" in log_line and "[FAIL]" in log_line:
			daz_passed = false

	# Now query the zone manager for per-zone detail
	var rcon: Node = get_node_or_null("/root/Rcon")
	var zone_detail: Dictionary = {}
	if rcon and rcon._zone_manager and is_instance_valid(rcon._zone_manager):
		zone_detail = rcon._zone_manager.get_check_result()

	# Mark each ETZ/DAZ row
	for si in range(check_row - 1, -1, -1):
		var line: String = _script[si].strip_edges()
		if line.begins_with("etz "):
			var p := _parse_command(line)
			var zone_id: int = p.get("id", 0)
			# Check if this ETZ was entered
			var entered: bool = false
			if zone_detail.has("etz_details"):
				for zd: Dictionary in zone_detail["etz_details"]:
					if zd.get("id", -1) == zone_id:
						entered = zd.get("entered", false)
						break
			# If we don't have detail, fall back to overall ETZ pass
			if not zone_detail.has("etz_details"):
				entered = etz_passed
			_run_results[si] = "pass" if entered else "fail"
		elif line.begins_with("daz "):
			var p := _parse_command(line)
			var zone_id: int = p.get("id", 0)
			var violated: bool = false
			if zone_detail.has("daz_details"):
				for zd: Dictionary in zone_detail["daz_details"]:
					if zd.get("id", -1) == zone_id:
						violated = zd.get("violated", false)
						break
			if not zone_detail.has("daz_details"):
				violated = not daz_passed
			_run_results[si] = "pass" if not violated else "fail"
		elif line.begins_with("check "):
			break


func _pause_test() -> void:
	## Pause is not yet implemented in the runner; toggle the flag for UI.
	_run_running = false


func _stop_test() -> void:
	## Stop everything — dismiss notify, kill runner, return to full edit mode.
	## Does NOT advance the suite. The user can edit and re-run.
	var rcon: Node = get_node_or_null("/root/Rcon")
	if rcon:
		if rcon._notify_active:
			rcon._cmd_notify_dismiss("OK")
		if rcon._test_runner:
			rcon._test_runner._running = false
			rcon._test_runner._task_queue.clear()
	_run_running = false
	_results_collected = false
	_mode = Mode.EDIT


func _restart_test() -> void:
	_stop_test()
	_run_test()


func run_suite(suite_name: String, skip_tests: Array[String] = []) -> void:
	## Load a suite and run each test sequentially through the editor.
	## skip_tests: test names to exclude from this run.
	var rcon: Node = get_node_or_null("/root/Rcon")
	if not rcon:
		return
	rcon._ensure_test_runner()
	var suite: Dictionary = rcon._test_runner._load_suite(suite_name)
	if suite.is_empty():
		_status_msg = "ERR: suite '%s' not found" % suite_name
		_status_timer = 3.0
		return
	_suite_name = suite.get("name", suite_name)
	_suite_all_tests = []
	_suite_queue = []
	_suite_results = []
	_suite_current_idx = 0
	var skipped: int = 0
	for t in suite.get("tests", []):
		var tname: String = str(t)
		_suite_all_tests.append(tname)
		if tname in skip_tests:
			skipped += 1
			continue
		_suite_queue.append(tname)
	var skip_str: String = " (skipping %d)" % skipped if skipped > 0 else ""
	_status_msg = "Suite '%s' — %d tests%s" % [_suite_name, _suite_queue.size(), skip_str]
	_status_timer = 2.0
	_suite_run_next()


func _suite_goto(idx: int) -> void:
	## Jump to a specific test in the suite by index. Stops current run.
	if idx < 0 or idx >= _suite_all_tests.size():
		return
	_stop_test()
	_suite_current_idx = idx
	_load_test(_suite_all_tests[idx])
	_run_test()


func _suite_run_next() -> void:
	## Load and run the next test in the suite queue.
	if _suite_queue.is_empty():
		_suite_show_results()
		return
	var next_test: String = _suite_queue.pop_front()
	_suite_current_idx = _suite_all_tests.size() - _suite_queue.size() - 1
	_load_test(next_test)
	_run_test()


func _suite_advance() -> void:
	## Called when a test completes during a suite run. Record result, run next.
	var has_fail: bool = "fail" in _run_results.values()
	_suite_results.append({"name": _test_name, "passed": not has_fail, "summary": _run_summary})
	# Advance immediately — the modal (if present) already gave pause time
	_suite_run_next()


func _suite_show_results() -> void:
	## Display suite results in the status bar, RCON grid, and write to file.
	var total: int = _suite_results.size()
	var passed: int = 0
	for r: Dictionary in _suite_results:
		if r["passed"]:
			passed += 1
	_status_msg = "Suite '%s': %d/%d PASSED" % [_suite_name, passed, total]
	_status_timer = 10.0
	# Print to stdout so log polling can detect suite completion
	print("SUITE_COMPLETE %s %d/%d" % [_suite_name, passed, total])
	# Write suite output to file
	_write_suite_output(passed, total)
	_suite_name = ""


func _write_suite_output(passed: int, total: int) -> void:
	## Write suite results to user://test-output/<version>/<suitename>/<timestamp>.json
	var version_str: String = Version.get_string()
	var timestamp: String = Time.get_datetime_string_from_system().replace(":", "-")
	var dir_path: String = "user://test-output/%s/%s" % [version_str, _suite_name]
	DirAccess.make_dir_recursive_absolute(dir_path)

	var tests_output: Array = []
	for r: Dictionary in _suite_results:
		tests_output.append({
			"name": r.get("name", ""),
			"passed": r.get("passed", false),
			"summary": r.get("summary", ""),
		})

	var suite_data: Dictionary = {
		"suite_name": _suite_name,
		"version": version_str,
		"timestamp": timestamp,
		"passed": passed,
		"total": total,
		"all_passed": passed == total,
		"tests": tests_output,
	}

	var file_path: String = dir_path + "/" + timestamp + ".json"
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(suite_data, "\t"))
		file.close()



# -- Command parsing -----------------------------------------------------------

func _parse_command(line: String) -> Dictionary:
	## Parse a script line into a typed parameter dict for handle building.
	var raw := line.strip_edges()
	var parts := raw.split(" ", false)
	if parts.is_empty():
		return {"type": "none", "raw": raw}
	var c0 := parts[0].to_lower()
	var c1 := parts[1].to_lower() if parts.size() > 1 else ""

	# spawn monster/dummy X Y [state]
	if c0 == "spawn" and (c1 == "monster" or c1 == "dummy") and parts.size() >= 4:
		var state: String = parts[4].to_lower() if parts.size() > 4 else ""
		return {"type": "spawn", "what": c1,
			"x": float(parts[2]), "y": float(parts[3]), "state": state, "raw": raw}

	# bleap a/b X Y R
	if c0 == "bleap" and (c1 == "a" or c1 == "b") and parts.size() >= 5:
		return {"type": "bleap_circle", "which": c1,
			"x": float(parts[2]), "y": float(parts[3]), "r": float(parts[4]), "raw": raw}

	# bleap plan req|opt [start X Y W H] [end X Y R] [disallow R X1 Y1 X2 Y2 ...]
	if c0 == "bleap" and c1 == "plan":
		var req := (parts[2].to_lower() == "req") if parts.size() > 2 else true
		var p: Dictionary = {"type": "bleap_plan", "required": req,
			"start": {}, "end": {}, "disallows": [], "raw": raw}
		var i := 3
		while i < parts.size():
			match parts[i].to_lower():
				"start":
					if i + 4 < parts.size():
						p["start"] = {"x": float(parts[i+1]), "y": float(parts[i+2]),
							"w": float(parts[i+3]), "h": float(parts[i+4])}
						i += 5
					else: i += 1
				"end":
					if i + 3 < parts.size():
						p["end"] = {"x": float(parts[i+1]), "y": float(parts[i+2]),
							"r": float(parts[i+3])}
						i += 4
					else: i += 1
				"disallow":
					if i + 5 < parts.size():
						p["disallows"].append({"r": float(parts[i+1]),
							"x1": float(parts[i+2]), "y1": float(parts[i+3]),
							"x2": float(parts[i+4]), "y2": float(parts[i+5])})
						i += 6
					else: i += 1
				_: i += 1
		return p

	# wait N [unless breach X1 Y1 X2 Y2 pat...] [unless exit_circle X Y R pat...]
	if c0 == "wait" and parts.size() >= 2:
		var duration: float = float(parts[1])
		var fences: Array = []
		var circles: Array = []
		var i := 2
		while i < parts.size():
			if parts[i].to_lower() == "unless" and i + 1 < parts.size():
				var ctype := parts[i + 1].to_lower()
				if ctype == "breach" and i + 6 < parts.size():
					var fence: Dictionary = {
						"x1": float(parts[i + 2]), "y1": float(parts[i + 3]),
						"x2": float(parts[i + 4]), "y2": float(parts[i + 5]),
						"patterns": [],
					}
					var j := i + 6
					while j < parts.size() and parts[j].to_lower() != "unless":
						fence["patterns"].append(parts[j])
						j += 1
					fences.append(fence)
					i = j
				elif ctype == "exit_circle" and i + 5 < parts.size():
					var circ: Dictionary = {
						"x": float(parts[i + 2]), "y": float(parts[i + 3]),
						"r": float(parts[i + 4]),
						"patterns": [],
					}
					var j := i + 5
					while j < parts.size() and parts[j].to_lower() != "unless":
						circ["patterns"].append(parts[j])
						j += 1
					circles.append(circ)
					i = j
				else:
					i += 1
			else:
				i += 1
		if not fences.is_empty() or not circles.is_empty():
			return {"type": "wait_breach", "duration": duration, "fences": fences, "circles": circles, "raw": raw}
		return {"type": "wait_plain", "duration": duration, "raw": raw}

	# etz/daz <id> <x> <y> <radius> [entity_id]
	if (c0 == "etz" or c0 == "daz") and parts.size() >= 5:
		var eid: String = parts[5] if parts.size() > 5 else ""
		return {"type": c0, "id": int(parts[1]),
			"x": float(parts[2]), "y": float(parts[3]), "r": float(parts[4]),
			"entity_id": eid, "raw": raw}

	return {"type": "none", "raw": raw}


func _format_command(p: Dictionary) -> String:
	## Rebuild a command string from a parsed parameter dict.
	match p.get("type", "none"):
		"spawn":
			var s := "spawn %s %.0f %.0f" % [p["what"], p["x"], p["y"]]
			if not p.get("state", "").is_empty():
				s += " " + p["state"]
			return s
		"bleap_circle":
			return "bleap %s %.0f %.0f %.0f" % [p["which"], p["x"], p["y"], p["r"]]
		"bleap_plan":
			var s := "bleap plan " + ("req" if p.get("required", true) else "opt")
			var st: Dictionary = p.get("start", {})
			if not st.is_empty():
				s += " start %.0f %.0f %.0f %.0f" % [st["x"], st["y"], st["w"], st["h"]]
			var e: Dictionary = p.get("end", {})
			if not e.is_empty():
				s += " end %.0f %.0f %.0f" % [e["x"], e["y"], e["r"]]
			for dis: Dictionary in p.get("disallows", []):
				s += " disallow %.0f %.0f %.0f %.0f %.0f" % [dis["r"], dis["x1"], dis["y1"], dis["x2"], dis["y2"]]
			return s
		"etz", "daz":
			var s := "%s %d %.0f %.0f %.0f" % [p["type"], p["id"], p["x"], p["y"], p["r"]]
			if not p.get("entity_id", "").is_empty():
				s += " " + p["entity_id"]
			return s
		"wait_plain":
			return "wait %.0f" % p["duration"]
		"wait_breach":
			var s := "wait %.0f" % p["duration"]
			for fence: Dictionary in p.get("fences", []):
				var pats := " ".join(fence.get("patterns", []))
				s += " unless breach %.0f %.0f %.0f %.0f %s" % [
					fence["x1"], fence["y1"], fence["x2"], fence["y2"], pats]
			for circ: Dictionary in p.get("circles", []):
				var pats := " ".join(circ.get("patterns", []))
				s += " unless exit_circle %.0f %.0f %.0f %s" % [
					circ["x"], circ["y"], circ["r"], pats]
			return s
		_:
			return p.get("raw", "")


# -- Handle building -----------------------------------------------------------

func _build_handles(p: Dictionary) -> Array:
	## Build the list of draggable world-space handles for a parsed command.
	var h: Array = []
	match p.get("type", "none"):
		"spawn":
			var col := Color(0.3, 1.0, 0.3) if p["what"] == "monster" else Color(1.0, 0.7, 0.2)
			h.append({"id": "pos", "world_pos": Vector2(p["x"], p["y"]),
				"color": col, "style": "dot"})

		"bleap_circle":
			var col := Color(0.3, 0.7, 1.0) if p["which"] == "a" else Color(1.0, 0.55, 0.1)
			h.append({"id": "center", "world_pos": Vector2(p["x"], p["y"]),
				"color": col, "style": "dot"})
			h.append({"id": "radius", "world_pos": Vector2(p["x"] + p["r"], p["y"]),
				"color": col * Color(1, 1, 1, 0.75), "style": "diamond",
				"circle_center": Vector2(p["x"], p["y"])})

		"bleap_plan":
			var st: Dictionary = p.get("start", {})
			if not st.is_empty():
				var col := Color(0.35, 0.9, 0.35, 0.95)
				var x: float = st["x"]; var y: float = st["y"]
				var w: float = st["w"]; var hh: float = st["h"]
				h.append({"id": "start_tl", "world_pos": Vector2(x, y),         "color": col, "style": "square"})
				h.append({"id": "start_tr", "world_pos": Vector2(x+w, y),       "color": col, "style": "square"})
				h.append({"id": "start_br", "world_pos": Vector2(x+w, y+hh),    "color": col, "style": "square"})
				h.append({"id": "start_bl", "world_pos": Vector2(x, y+hh),      "color": col, "style": "square"})
				h.append({"id": "start_c",  "world_pos": Vector2(x+w/2, y+hh/2),"color": col * Color(1,1,1,0.55), "style": "dot"})
			var e: Dictionary = p.get("end", {})
			if not e.is_empty():
				var col := Color(1.0, 0.85, 0.2, 0.95)
				h.append({"id": "end_c", "world_pos": Vector2(e["x"], e["y"]),
					"color": col, "style": "dot"})
				h.append({"id": "end_r", "world_pos": Vector2(e["x"] + e["r"], e["y"]),
					"color": col * Color(1,1,1,0.7), "style": "diamond",
					"circle_center": Vector2(e["x"], e["y"])})
			for di: int in range(p.get("disallows", []).size()):
				var dis: Dictionary = p["disallows"][di]
				var col := Color(1.0, 0.3, 0.3, 0.9)
				var dp1 := Vector2(dis["x1"], dis["y1"])
				var dp2 := Vector2(dis["x2"], dis["y2"])
				h.append({"id": "dis_%d_p1" % di, "world_pos": dp1, "color": col, "style": "dot"})
				h.append({"id": "dis_%d_p2" % di, "world_pos": dp2, "color": col, "style": "dot"})
				# Radius grip — perpendicular to midpoint
				var mid := (dp1 + dp2) * 0.5
				var seg_dir := (dp2 - dp1).normalized()
				var perp := Vector2(-seg_dir.y, seg_dir.x)
				var r_pos: Vector2 = mid + perp * float(dis["r"])
				h.append({"id": "dis_%d_r" % di, "world_pos": r_pos, "color": col * Color(1,1,1,0.7), "style": "diamond"})
		"etz":
			var col := Color(0.2, 0.9, 0.5, 0.95)
			h.append({"id": "zone_center", "world_pos": Vector2(p["x"], p["y"]),
				"color": col, "style": "dot"})
			h.append({"id": "zone_radius", "world_pos": Vector2(p["x"] + p["r"], p["y"]),
				"color": col * Color(1,1,1,0.7), "style": "diamond"})
		"daz":
			var col := Color(0.9, 0.2, 0.2, 0.95)
			h.append({"id": "zone_center", "world_pos": Vector2(p["x"], p["y"]),
				"color": col, "style": "dot"})
			h.append({"id": "zone_radius", "world_pos": Vector2(p["x"] + p["r"], p["y"]),
				"color": col * Color(1,1,1,0.7), "style": "diamond"})
		"wait_breach":
			for fi: int in range(p.get("fences", []).size()):
				var fence: Dictionary = p["fences"][fi]
				var col := Color(1.0, 0.6, 0.1, 0.95)
				h.append({"id": "fence_%d_p1" % fi, "world_pos": Vector2(fence["x1"], fence["y1"]),
					"color": col, "style": "dot"})
				h.append({"id": "fence_%d_p2" % fi, "world_pos": Vector2(fence["x2"], fence["y2"]),
					"color": col, "style": "dot"})
			for ci: int in range(p.get("circles", []).size()):
				var circ: Dictionary = p["circles"][ci]
				var col := Color(0.9, 0.7, 0.2, 0.95)
				h.append({"id": "circ_%d_center" % ci, "world_pos": Vector2(circ["x"], circ["y"]),
					"color": col, "style": "dot"})
				h.append({"id": "circ_%d_radius" % ci, "world_pos": Vector2(circ["x"] + circ["r"], circ["y"]),
					"color": col * Color(1,1,1,0.7), "style": "diamond"})
	return h


func _apply_handle_drag(p: Dictionary, hid: String, wp: Vector2) -> void:
	## Modify parsed params in-place based on the dragged handle and new world position.
	match p.get("type", "none"):
		"spawn":
			p["x"] = wp.x;  p["y"] = wp.y
		"bleap_circle":
			if hid == "center":
				p["x"] = wp.x;  p["y"] = wp.y
			elif hid == "radius":
				p["r"] = maxf(10.0, wp.distance_to(Vector2(p["x"], p["y"])))
		"bleap_plan":
			var st: Dictionary = p.get("start", {})
			if hid.begins_with("start_") and not st.is_empty():
				match hid:
					"start_tl":
						var dx: float = wp.x - float(st["x"]); var dy: float = wp.y - float(st["y"])
						st["x"] = wp.x; st["y"] = wp.y
						st["w"] = maxf(10.0, float(st["w"]) - dx)
						st["h"] = maxf(10.0, float(st["h"]) - dy)
					"start_tr":
						var dy: float = wp.y - float(st["y"])
						st["y"] = wp.y
						st["w"] = maxf(10.0, wp.x - float(st["x"]))
						st["h"] = maxf(10.0, float(st["h"]) - dy)
					"start_br":
						st["w"] = maxf(10.0, wp.x - float(st["x"]))
						st["h"] = maxf(10.0, wp.y - float(st["y"]))
					"start_bl":
						var dx: float = wp.x - float(st["x"])
						st["x"] = wp.x
						st["w"] = maxf(10.0, float(st["w"]) - dx)
						st["h"] = maxf(10.0, wp.y - float(st["y"]))
					"start_c":
						st["x"] += wp.x - (st["x"] + st["w"] * 0.5)
						st["y"] += wp.y - (st["y"] + st["h"] * 0.5)
			elif hid.begins_with("end_"):
				var e: Dictionary = p.get("end", {})
				if not e.is_empty():
					if hid == "end_c":
						e["x"] = wp.x;  e["y"] = wp.y
					elif hid == "end_r":
						e["r"] = maxf(10.0, wp.distance_to(Vector2(e["x"], e["y"])))
			elif hid.begins_with("dis_"):
				var segs := hid.split("_")  # ["dis","0","p1"]
				if segs.size() >= 3:
					var di := int(segs[1])
					var disallows: Array = p.get("disallows", [])
					if di < disallows.size():
						if segs[2] == "p1":
							disallows[di]["x1"] = wp.x;  disallows[di]["y1"] = wp.y
						elif segs[2] == "p2":
							disallows[di]["x2"] = wp.x;  disallows[di]["y2"] = wp.y
						elif segs[2] == "r":
							# Radius grip — distance from drag point to the segment midpoint
							var dp1 := Vector2(disallows[di]["x1"], disallows[di]["y1"])
							var dp2 := Vector2(disallows[di]["x2"], disallows[di]["y2"])
							var mid := (dp1 + dp2) * 0.5
							disallows[di]["r"] = maxf(5.0, wp.distance_to(mid))
		"etz", "daz":
			if hid == "zone_center":
				p["x"] = wp.x;  p["y"] = wp.y
			elif hid == "zone_radius":
				p["r"] = maxf(10.0, wp.distance_to(Vector2(p["x"], p["y"])))
		"wait_breach":
			if hid.begins_with("fence_"):
				var segs := hid.split("_")  # ["fence","0","p1"]
				if segs.size() >= 3:
					var fi := int(segs[1])
					var fences: Array = p.get("fences", [])
					if fi < fences.size():
						if segs[2] == "p1":
							fences[fi]["x1"] = wp.x;  fences[fi]["y1"] = wp.y
						elif segs[2] == "p2":
							fences[fi]["x2"] = wp.x;  fences[fi]["y2"] = wp.y
			elif hid.begins_with("circ_"):
				var segs := hid.split("_")  # ["circ","0","center"]
				if segs.size() >= 3:
					var ci := int(segs[1])
					var circles: Array = p.get("circles", [])
					if ci < circles.size():
						if segs[2] == "center":
							circles[ci]["x"] = wp.x;  circles[ci]["y"] = wp.y
						elif segs[2] == "radius":
							circles[ci]["r"] = maxf(10.0, wp.distance_to(Vector2(circles[ci]["x"], circles[ci]["y"])))


# -- Coordinate helpers --------------------------------------------------------

func _get_world_pos(screen_pos: Vector2) -> Vector2:
	var cam := get_viewport().get_camera_2d()
	if not cam:
		return screen_pos
	var vp := get_viewport().get_visible_rect().size
	var zoom := cam.zoom if cam.zoom.x > 0 else Vector2.ONE
	return (screen_pos - vp / 2.0) / zoom + cam.global_position


func _world_to_screen(world_pos: Vector2) -> Vector2:
	var cam := get_viewport().get_camera_2d()
	if not cam:
		return world_pos
	var vp := get_viewport().get_visible_rect().size
	var zoom := cam.zoom if cam.zoom.x > 0 else Vector2.ONE
	return (world_pos - cam.global_position) * zoom + vp / 2.0


func _world_hit_scale() -> float:
	## Convert screen hit radius to world units for handle proximity testing.
	var cam := get_viewport().get_camera_2d()
	if not cam or cam.zoom.x <= 0:
		return 1.0
	return 1.0 / cam.zoom.x


# -- Layout helpers ------------------------------------------------------------

func _max_rows_for_viewport() -> int:
	## How many rows fit given the current viewport height and window position.
	var vp_h: float = get_viewport().get_visible_rect().size.y
	var avail: float = vp_h - _window_pos.y - TITLE_H - BUTTON_H - EDIT_H - 20.0
	var rows: int = int(avail / ROW_H)
	return clampi(rows, MIN_VIS_ROWS, MAX_VIS_ROWS)


func _visible_row_count() -> int:
	# +1 for the ghost "add" row at the bottom
	return mini(_script.size() + 1 - _row_scroll, _max_rows_for_viewport())


func _edit_field_height() -> float:
	## Dynamic height for the edit field based on text length (word wrap).
	## Hidden during review mode (results collected, no editing).
	if _selected_row < 0 or _results_collected:
		return 0.0
	var font: Font = ThemeDB.fallback_font
	var text_w: float = font.get_string_size("  " + _edit_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	var avail_w: float = WINDOW_W - 24.0
	var lines: int = maxi(1, ceili(text_w / avail_w))
	return 10.0 + lines * 16.0  # padding + lines


func _detail_panel_height() -> float:
	## Height of the check detail log panel (when a check row with results is selected).
	if _selected_row < 0 or not _run_detail.has(_selected_row):
		return 0.0
	var lines: int = mini(_run_detail[_selected_row].size(), 12)  # Cap at 12 visible lines
	if lines == 0:
		return 0.0
	return 8.0 + lines * 14.0


func _window_height() -> float:
	var h := TITLE_H + _visible_row_count() * ROW_H
	if _selected_row >= 0:
		h += _edit_field_height()
		h += _detail_panel_height()
		# Notify help panel (when notify row is selected and active)
		if _selected_row < _script.size() and _script[_selected_row].strip_edges().begins_with("notify ") and get_meta("notify_active", false):
			h += 56.0
	h += BUTTON_H
	# Result summary bar
	if not _run_summary.is_empty():
		h += 22.0
	return h


func _get_window_rect() -> Rect2:
	return Rect2(_window_pos, Vector2(WINDOW_W, _window_height()))


# -- World overlay drawing -----------------------------------------------------

func _draw_overlay() -> void:
	if not _active or _mode != Mode.EDIT:
		return

	var font: Font = ThemeDB.fallback_font

	# Pass 1: draw ALL renderable lines — defocused (grey) for non-selected, bright for selected
	for row_idx in range(_script.size()):
		var p := _parse_command(_script[row_idx])
		if p.get("type", "none") == "none":
			continue
		var is_selected := (row_idx == _selected_row)
		var dim: float = 1.0 if is_selected else 0.3
		var line_num: String = "%d" % (row_idx + 1)
		var result: String = _run_results.get(row_idx, "")
		_draw_command_visual(p, dim, line_num, font, result)

	# Pass 2: draw handles for selected row only
	for i in range(_handles.size()):
		var h: Dictionary = _handles[i]
		var wp: Vector2 = h["world_pos"]
		var col: Color = h["color"]
		var is_hover := (i == _handle_hover)
		var is_drag  := (i == _handle_drag)
		var r: float = HANDLE_DRAW * _world_hit_scale()
		var draw_r: float = r * (1.4 if is_hover or is_drag else 1.0)
		match h.get("style", "dot"):
			"dot":
				_overlay.draw_circle(wp, draw_r, col)
				_overlay.draw_arc(wp, draw_r, 0, TAU, 12, Color.WHITE * Color(1,1,1,0.5), 1.0)
			"square":
				var sq := draw_r * 0.85
				_overlay.draw_rect(Rect2(wp - Vector2(sq, sq), Vector2(sq*2, sq*2)), col)
				_overlay.draw_rect(Rect2(wp - Vector2(sq, sq), Vector2(sq*2, sq*2)), Color.WHITE * Color(1,1,1,0.4), false, 1.0)
			"diamond":
				var dpts := PackedVector2Array([
					wp + Vector2(0, -draw_r * 1.3),
					wp + Vector2(draw_r, 0),
					wp + Vector2(0, draw_r * 1.3),
					wp + Vector2(-draw_r, 0),
				])
				_overlay.draw_colored_polygon(dpts, col)
				_overlay.draw_polyline(PackedVector2Array([dpts[0], dpts[1], dpts[2], dpts[3], dpts[0]]), Color.WHITE * Color(1,1,1,0.4), 1.0)

	# Pass 3: draw captured leap edges (after run) — the actual planned arcs
	if not _run_leap_edges.is_empty():
		for edge: Dictionary in _run_leap_edges:
			var arc_c: PackedVector2Array = edge.get("arc_c", PackedVector2Array())
			var from_pos: Vector2 = edge.get("from_pos", Vector2.ZERO)
			var arrival: Vector2 = edge.get("arrival", Vector2.ZERO)
			var eres: String = edge.get("result", "none")
			var breach_pts: Array = edge.get("breach_points", [])

			# Arc color based on result
			var arc_col: Color
			var launch_col: Color
			var land_col: Color
			match eres:
				"matched":
					arc_col = Color(0.2, 0.9, 0.2, 0.7)
					launch_col = Color(0.3, 1.0, 0.3)
					land_col = Color(0.3, 1.0, 0.3)
				"failed":
					arc_col = Color(1.0, 0.3, 0.3, 0.7)
					launch_col = Color(1.0, 0.4, 0.4)
					land_col = Color(1.0, 0.4, 0.4)
				"no_candidate":
					arc_col = Color(0.4, 0.4, 0.4, 0.25)
					launch_col = Color(0.5, 0.5, 0.5, 0.3)
					land_col = Color(0.5, 0.5, 0.5, 0.3)
				_:
					arc_col = Color(0.5, 0.7, 1.0, 0.4)
					launch_col = Color(0.5, 0.7, 1.0, 0.5)
					land_col = Color(0.5, 0.7, 1.0, 0.5)

			# Draw arc polyline
			if arc_c.size() >= 2:
				_overlay.draw_polyline(arc_c, arc_col, 2.0 if eres == "matched" or eres == "failed" else 1.0)

			# Launch dot
			_overlay.draw_circle(from_pos, 5.0, launch_col)
			# Landing arrowhead
			_overlay.draw_circle(arrival, 5.0, land_col)
			if arc_c.size() >= 2:
				var tip: Vector2 = arc_c[arc_c.size() - 1]
				var prev: Vector2 = arc_c[arc_c.size() - 2]
				var dir: Vector2 = (tip - prev).normalized()
				var perp: Vector2 = Vector2(-dir.y, dir.x)
				var arrow_size: float = 10.0
				var p_a: Vector2 = tip
				var p_b: Vector2 = tip - dir * arrow_size + perp * arrow_size * 0.5
				var p_c: Vector2 = tip - dir * arrow_size - perp * arrow_size * 0.5
				_overlay.draw_colored_polygon(PackedVector2Array([p_a, p_b, p_c]), land_col)

			# Breach points — show the body circle (r=55) at each breach position
			# so the user can see WHERE the body clips the platform/disallow zone.
			# Thin to every 4th disallow point to reduce clutter.
			var body_r: float = 55.0
			var drawn_disallow: int = 0
			for bp: Dictionary in breach_pts:
				var bpos: Vector2 = bp.get("pos", Vector2.ZERO)
				var reason: String = bp.get("reason", "")
				if reason.begins_with("disallow"):
					drawn_disallow += 1
					if drawn_disallow % 4 != 1:
						_overlay.draw_circle(bpos, 2.0, Color(1.0, 0.2, 0.2, 0.3))
						continue
				# Draw the body circle at this arc point — shows the actual footprint
				var pulse_alpha: float = 0.3 + 0.15 * sin(_run_blink * 3.0)
				_overlay.draw_circle(bpos, body_r, Color(1.0, 0.1, 0.1, pulse_alpha * 0.3))
				_overlay.draw_arc(bpos, body_r, 0, TAU, 24, Color(1.0, 0.2, 0.2, pulse_alpha), 1.5)
				# Small dot at center
				_overlay.draw_circle(bpos, 3.0, Color(1.0, 0.3, 0.3, 0.8))
				# Label
				_overlay.draw_string(font, bpos + Vector2(-30, -body_r - 6), reason,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 0.2, 0.2, 0.8))

	# Pass 4: breach marker — big pulsing circle where the entity crossed a fence
	if not _breach_marker.is_empty():
		var bpos: Vector2 = _breach_marker.get("pos", Vector2.ZERO)
		var bentity: String = _breach_marker.get("entity", "?")
		var bidx: int = _breach_marker.get("idx", -1)
		var bline: int = _breach_marker.get("line", 0)
		var btype: String = _breach_marker.get("type", "")
		var pulse: float = 12.0 + 4.0 * sin(_run_blink * 3.0)
		# Orange circle marker — breaches are informational (early abort), not errors
		_overlay.draw_arc(bpos, pulse + 4, 0, TAU, 16, Color(1.0, 0.7, 0.2, 0.6), 2.0)
		_overlay.draw_circle(bpos, 4.0, Color(1.0, 0.7, 0.2, 0.8))
		# Label
		var blabel: String = "BREACH L%d[%d] %s" % [bline, bidx, bentity]
		_overlay.draw_string(font, bpos + Vector2(-60, -pulse - 10), blabel,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.7, 0.2))
		_overlay.draw_string(font, bpos + Vector2(-40, pulse + 16), "(%.0f, %.0f)" % [bpos.x, bpos.y],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 0.7, 0.2, 0.6))


func _draw_command_visual(p: Dictionary, dim: float, line_num: String, font: Font, result: String = "") -> void:
	## Draw the world-space visual for a parsed command. dim=1.0 for selected, 0.3 for defocused.
	## result: "" (no result), "pass", "fail", "info"
	var line_col := Color(1.0, 1.0, 1.0, 0.7 * dim)
	# Override colors with pass/fail tint when result is present
	var result_tint := Color.WHITE
	if result == "pass":
		result_tint = Color(0.5, 1.0, 0.5)
	elif result == "fail":
		result_tint = Color(1.0, 0.4, 0.4)

	match p.get("type", "none"):
		"spawn":
			var pos := Vector2(p["x"], p["y"])
			var col := Color(0.3, 1.0, 0.3) if p["what"] == "monster" else Color(1.0, 0.7, 0.2)
			col.a = 0.7 * dim
			_overlay.draw_circle(pos, 12.0 if dim > 0.5 else 8.0, col)
			var label: String = "%s  [%s]" % [line_num, p["what"]]
			_overlay.draw_string(font, pos + Vector2(-20, -18), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, line_col)

		"bleap_circle":
			var col := Color(0.3, 0.7, 1.0) if p["which"] == "a" else Color(1.0, 0.55, 0.1)
			if result != "":
				col = result_tint
			var fill_col := col * Color(1, 1, 1, 0.12 * dim)
			var outline_col := col * Color(1, 1, 1, 0.7 * dim)
			var center := Vector2(p["x"], p["y"])
			_overlay.draw_circle(center, p["r"], fill_col)
			_overlay.draw_arc(center, p["r"], 0, TAU, 48, outline_col, 1.5 if dim > 0.5 else 1.0)
			var label: String = "%s  %s" % [line_num, "Plat A" if p["which"] == "a" else "Plat B"]
			if result == "pass":
				label += "  PASS"
			elif result == "fail":
				label += "  FAIL"
			_overlay.draw_string(font, center + Vector2(-50, -p["r"] - 8), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, outline_col)

		"bleap_plan":
			# Determine outline color from result
			var plan_col := Color(0.3, 0.85, 0.3) if result != "fail" else Color(1.0, 0.35, 0.35)
			var end_col  := Color(1.0, 0.85, 0.2) if result != "fail" else Color(1.0, 0.35, 0.35)
			var dis_col  := Color(1.0, 0.3, 0.3)
			if result == "pass":
				plan_col = Color(0.3, 1.0, 0.3)
				end_col  = Color(0.3, 1.0, 0.3)

			var st: Dictionary = p.get("start", {})
			if not st.is_empty():
				var rect := Rect2(st["x"], st["y"], st["w"], st["h"])
				_overlay.draw_rect(rect, plan_col * Color(1, 1, 1, 0.1 * dim))
				_overlay.draw_rect(rect, plan_col * Color(1, 1, 1, 0.7 * dim), false, 1.5 if dim > 0.5 else 1.0)
				var slabel: String = "%s  START" % line_num
				if result == "pass":
					slabel += " ✓"
				elif result == "fail":
					slabel += " ✗"
				if dim > 0.5:
					slabel += " (%.0f,%.0f) %.0fx%.0f" % [st["x"], st["y"], st["w"], st["h"]]
				_overlay.draw_string(font, rect.position + Vector2(4, 14), slabel,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 9, plan_col * Color(1, 1, 1, 0.9 * dim))
			var e: Dictionary = p.get("end", {})
			if not e.is_empty():
				var ec := Vector2(e["x"], e["y"])
				_overlay.draw_circle(ec, e["r"], end_col * Color(1, 1, 1, 0.1 * dim))
				_overlay.draw_arc(ec, e["r"], 0, TAU, 32, end_col * Color(1, 1, 1, 0.7 * dim), 1.5 if dim > 0.5 else 1.0)
				var elabel: String = "%s  END r=%.0f" % [line_num, e["r"]]
				if result == "pass":
					elabel += " ✓"
				elif result == "fail":
					elabel += " ✗"
				_overlay.draw_string(font, ec + Vector2(-40, -e["r"] - 8), elabel,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 9, end_col * Color(1, 1, 1, 0.8 * dim))
			for di: int in range(p.get("disallows", []).size()):
				var dis: Dictionary = p["disallows"][di]
				var dp1 := Vector2(dis["x1"], dis["y1"])
				var dp2 := Vector2(dis["x2"], dis["y2"])
				_overlay.draw_line(dp1, dp2, dis_col * Color(1, 1, 1, 0.35 * dim), dis["r"] * 2.0)
				_overlay.draw_line(dp1, dp2, dis_col * Color(1, 1, 1, 0.8 * dim), 1.5 if dim > 0.5 else 1.0)
				if dim > 0.5:
					_overlay.draw_circle(dp1, dis["r"], dis_col * Color(1, 1, 1, 0.1))
					_overlay.draw_circle(dp2, dis["r"], dis_col * Color(1, 1, 1, 0.1))
					var dlabel: String = "%s  DISALLOW[%d]" % [line_num, di]
					var mid := (dp1 + dp2) * 0.5
					_overlay.draw_string(font, mid + Vector2(-40, -dis["r"] - 6), dlabel,
						HORIZONTAL_ALIGNMENT_LEFT, -1, 9, dis_col * Color(1, 1, 1, 0.8))

		"etz":
			var center := Vector2(p["x"], p["y"])
			var r: float = p["r"]
			var col := Color(0.2, 0.9, 0.5)
			if result == "pass":
				col = Color(0.3, 1.0, 0.3)
			elif result == "fail":
				col = Color(1.0, 0.4, 0.1)
			_overlay.draw_circle(center, r, col * Color(1,1,1, 0.08 * dim))
			_overlay.draw_arc(center, r, 0, TAU, 48, col * Color(1,1,1, 0.7 * dim), 1.5 if dim > 0.5 else 1.0)
			var elabel := "%s  ETZ-%d" % [line_num, p["id"]]
			if result == "pass":
				elabel += " ENTERED"
			elif result == "fail":
				elabel += " NOT ENTERED"
			_overlay.draw_string(font, center + Vector2(-40, -r - 8), elabel,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, col * Color(1,1,1, 0.8 * dim))
			# Draw checkmark or X inside the circle
			if result == "pass":
				_overlay.draw_string(font, center + Vector2(-8, 6), "OK",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.3, 1.0, 0.3, 0.8 * dim))
			elif result == "fail":
				_overlay.draw_string(font, center + Vector2(-6, 8), "X",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.3, 0.1, 0.9 * dim))

		"daz":
			var center := Vector2(p["x"], p["y"])
			var r: float = p["r"]
			var col := Color(0.9, 0.2, 0.2)
			if result == "pass":
				col = Color(0.3, 0.8, 0.3)  # Green = no violation, good
			elif result == "fail":
				col = Color(1.0, 0.15, 0.15)  # Bright red = violated
			_overlay.draw_circle(center, r, col * Color(1,1,1, 0.08 * dim))
			_overlay.draw_arc(center, r, 0, TAU, 48, col * Color(1,1,1, 0.7 * dim), 1.5 if dim > 0.5 else 1.0)
			if dim > 0.3:
				_overlay.draw_line(center + Vector2(-r*0.7, -r*0.7), center + Vector2(r*0.7, r*0.7), col * Color(1,1,1, 0.4 * dim), 1.0)
				_overlay.draw_line(center + Vector2(r*0.7, -r*0.7), center + Vector2(-r*0.7, r*0.7), col * Color(1,1,1, 0.4 * dim), 1.0)
			var dlabel := "%s  DAZ-%d" % [line_num, p["id"]]
			if result == "pass":
				dlabel += " CLEAR"
			elif result == "fail":
				dlabel += " VIOLATED"
			_overlay.draw_string(font, center + Vector2(-40, -r - 8), dlabel,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, col * Color(1,1,1, 0.8 * dim))
			if result == "pass":
				_overlay.draw_string(font, center + Vector2(-8, 6), "OK",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.3, 1.0, 0.3, 0.8 * dim))
			elif result == "fail":
				_overlay.draw_string(font, center + Vector2(-6, 8), "X",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.15, 0.15, 0.9 * dim))

		"wait_breach":
			for fi: int in range(p.get("fences", []).size()):
				var fence: Dictionary = p["fences"][fi]
				var bp1 := Vector2(fence["x1"], fence["y1"])
				var bp2 := Vector2(fence["x2"], fence["y2"])
				var col := Color(1.0, 0.6, 0.1) * Color(1, 1, 1, 0.8 * dim)
				# Dashed fence line
				var seg_count: int = maxi(1, int(bp1.distance_to(bp2) / 20.0))
				for si in range(seg_count):
					if si % 2 == 0:
						var t0: float = float(si) / float(seg_count)
						var t1: float = float(si + 1) / float(seg_count)
						_overlay.draw_line(bp1.lerp(bp2, t0), bp1.lerp(bp2, t1), col, 2.0 if dim > 0.5 else 1.0)
				# Endpoint markers
				_overlay.draw_circle(bp1, 6.0 if dim > 0.5 else 4.0, col)
				_overlay.draw_circle(bp2, 6.0 if dim > 0.5 else 4.0, col)
				# Label
				var mid_f := (bp1 + bp2) * 0.5
				var pats := " ".join(fence.get("patterns", []))
				var blabel := "%s  FENCE[%d] %.0fs [%s]" % [line_num, fi, p["duration"], pats]
				_overlay.draw_string(font, mid_f + Vector2(-60, -12), blabel,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 9, col)
			# Exit circles
			for ci: int in range(p.get("circles", []).size()):
				var circ: Dictionary = p["circles"][ci]
				var center := Vector2(circ["x"], circ["y"])
				var r: float = circ["r"]
				var col := Color(0.9, 0.7, 0.2) * Color(1, 1, 1, 0.8 * dim)
				# Dashed circle
				var arc_segs: int = 48
				for si in range(arc_segs):
					if si % 2 == 0:
						var a0: float = TAU * float(si) / float(arc_segs)
						var a1: float = TAU * float(si + 1) / float(arc_segs)
						_overlay.draw_line(center + Vector2(cos(a0), sin(a0)) * r,
							center + Vector2(cos(a1), sin(a1)) * r, col, 1.5 if dim > 0.5 else 1.0)
				var pats := " ".join(circ.get("patterns", []))
				var clabel := "%s  EXIT[%d] r=%.0f [%s]" % [line_num, ci, r, pats]
				_overlay.draw_string(font, center + Vector2(-50, -r - 8), clabel,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 9, col)


# -- Screen panel drawing ------------------------------------------------------

func _draw_panel() -> void:
	if not _active:
		return
	if _picker_open:
		_draw_picker()
		return

	var font: Font = ThemeDB.fallback_font
	var vp  := get_viewport().get_visible_rect().size
	var wx  := _window_pos.x
	var wy  := _window_pos.y
	var ww  := WINDOW_W
	var wh  := _window_height()

	# Window shadow
	_panel.draw_rect(Rect2(wx + 4, wy + 4, ww, wh), Color(0, 0, 0, 0.4))

	# Window background
	_panel.draw_rect(Rect2(wx, wy, ww, wh), Color(0.08, 0.08, 0.12, 0.97))
	_panel.draw_rect(Rect2(wx, wy, ww, wh), Color(0.35, 0.55, 0.35, 0.7), false, 1.5)

	# Title bar
	var mode_col := Color(0.3, 0.8, 0.3) if _mode == Mode.EDIT else Color(0.8, 0.5, 0.2)
	_panel.draw_rect(Rect2(wx, wy, ww, TITLE_H), Color(0.1, 0.15, 0.1, 1.0))
	var title_str: String
	if _test_name.is_empty():
		title_str = "Test Editor  —  (no test)  press T"
	else:
		var dirty_mark := " ●" if _dirty else ""
		var suite_pos := ""
		if not _suite_all_tests.is_empty():
			suite_pos = " [%d/%d]" % [_suite_current_idx + 1, _suite_all_tests.size()]
		title_str = "%s%s%s" % [_test_name, suite_pos, dirty_mark]
	_panel.draw_string(font, Vector2(wx + 10, wy + 17), title_str,
		HORIZONTAL_ALIGNMENT_LEFT, ww - 80, 12, Color(0.85, 0.85, 0.85))
	var mode_str := "EDIT" if _mode == Mode.EDIT else "▶ RUN"
	_panel.draw_string(font, Vector2(wx + ww - 54, wy + 17), mode_str,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, mode_col)

	# Row list
	var ry := wy + TITLE_H
	var list_h := _visible_row_count() * ROW_H
	_panel.draw_rect(Rect2(wx, ry, ww, list_h), Color(0.06, 0.06, 0.09, 1.0))

	for i in range(_visible_row_count()):
		var script_idx: int = _row_scroll + i
		var row_y := ry + i * ROW_H
		var is_ghost := (script_idx >= _script.size())

		if is_ghost:
			# Ghost "add" row
			_panel.draw_string(font, Vector2(wx + 30, row_y + 15),
				"(click to add line)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
				Color(0.4, 0.6, 0.4, 0.5))
			continue

		var is_sel := (script_idx == _selected_row)

		# Row background
		if is_sel:
			_panel.draw_rect(Rect2(wx, row_y, ww, ROW_H), Color(0.15, 0.35, 0.15, 1.0))
		elif i % 2 == 1:
			_panel.draw_rect(Rect2(wx, row_y, ww, ROW_H), Color(0.0, 0.0, 0.0, 0.15))

		# Line number
		var num_col := Color(0.4, 0.6, 0.4) if not is_sel else Color(0.7, 1.0, 0.7)
		_panel.draw_string(font, Vector2(wx + 6, row_y + 15),
			"%2d" % (script_idx + 1), HORIZONTAL_ALIGNMENT_LEFT, 20, 10, num_col)

		# Status indicator — shows run state during execution, result after completion
		var rcon_ls: Node = get_node_or_null("/root/Rcon")
		var line_state: String = ""
		if rcon_ls and rcon_ls._test_runner and rcon_ls._test_runner._line_states.has(script_idx):
			line_state = rcon_ls._test_runner._line_states[script_idx]
		if _run_results.has(script_idx):
			# Post-run result
			var res: String = _run_results[script_idx]
			match res:
				"pass":
					_panel.draw_string(font, Vector2(wx + 26, row_y + 15), "✓",
						HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.3, 1.0, 0.3))
				"fail":
					_panel.draw_string(font, Vector2(wx + 26, row_y + 15), "✗",
						HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.3, 0.3))
					_panel.draw_rect(Rect2(wx, row_y, ww, ROW_H), Color(0.4, 0.1, 0.1, 0.3))
				"info":
					_panel.draw_string(font, Vector2(wx + 26, row_y + 15), "·",
						HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.5, 0.5))
		elif _run_running and not _results_collected and not line_state.is_empty():
			# During run — show execution state
			match line_state:
				"pending":
					_panel.draw_string(font, Vector2(wx + 26, row_y + 15), "○",
						HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.5, 0.5))
				"running":
					var is_notify_line: bool = _script[script_idx].strip_edges().begins_with("notify ")
					if is_notify_line:
						_panel.draw_string(font, Vector2(wx + 26, row_y + 15), "⏸",
							HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.8, 0.3))
						_panel.draw_rect(Rect2(wx, row_y, ww, ROW_H), Color(0.2, 0.2, 0.05, 0.3))
						# Countdown on the right
						var rcon_cd: Node = get_node_or_null("/root/Rcon")
						if rcon_cd and rcon_cd._notify_active:
							var secs: int = ceili(rcon_cd._notify_timer)
							var mm: int = secs / 60
							var ss: int = secs % 60
							var cd_text: String = "%02d:%02d" % [mm, ss]
							_panel.draw_string(font, Vector2(wx + ww - 48, row_y + 15), cd_text,
								HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.8, 0.8, 0.3, 0.7))
					else:
						_panel.draw_string(font, Vector2(wx + 26, row_y + 15), "●",
							HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.3, 1.0, 0.3))
						_panel.draw_rect(Rect2(wx, row_y, ww, ROW_H), Color(0.1, 0.25, 0.1, 0.3))
				"complete":
					_panel.draw_string(font, Vector2(wx + 26, row_y + 15), "✓",
						HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.7, 0.5))
		# Notify line: show ⏸ + countdown when notify is active (after results collected)
		if _results_collected and _script[script_idx].strip_edges().begins_with("notify "):
			var rcon_cd: Node = get_node_or_null("/root/Rcon")
			if rcon_cd and rcon_cd._notify_active:
				_panel.draw_string(font, Vector2(wx + 26, row_y + 15), "⏸",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.8, 0.3))
				_panel.draw_rect(Rect2(wx, row_y, ww, ROW_H), Color(0.2, 0.2, 0.05, 0.3))
				var secs: int = ceili(rcon_cd._notify_timer)
				var cd_text: String = "%02d:%02d" % [secs / 60, secs % 60]
				_panel.draw_string(font, Vector2(wx + ww - 48, row_y + 15), cd_text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.8, 0.8, 0.3, 0.7))

		# Command text — truncated (leave room for result icon + X button)
		var cmd_text: String = _script[script_idx]
		var text_col := Color(0.95, 0.95, 0.85) if is_sel else _cmd_color(cmd_text)
		_panel.draw_string(font, Vector2(wx + 38, row_y + 15), cmd_text,
			HORIZONTAL_ALIGNMENT_LEFT, ww - 62, 11, text_col)

		# Show actual override value on the right for var lines
		if cmd_text.strip_edges().begins_with("var "):
			var var_parts := cmd_text.strip_edges().split(" ", false)
			if var_parts.size() >= 2:
				var var_name: String = var_parts[1]
				if _test_override_vars.has(var_name):
					var actual := str(_test_override_vars[var_name])
					_panel.draw_string(font, Vector2(wx + ww - 65, row_y + 15),
						"= " + actual, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
						Color(0.4, 0.9, 1.0, 0.8))

		# Red X delete button on right edge — hidden during run mode
		if not _run_running:
			var xc := Vector2(wx + ww - 12, row_y + ROW_H * 0.5)
			_panel.draw_string(font, xc + Vector2(-4, 5), "✕",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.3, 0.3, 0.5 if not is_sel else 0.8))

	# Separator
	_panel.draw_line(Vector2(wx, ry + list_h), Vector2(wx + ww, ry + list_h),
		Color(0.3, 0.5, 0.3, 0.5), 1.0)

	# Row-drag drop indicator
	if _row_drag >= 0 and _row_drag_target >= 0:
		var drop_vis: int = _row_drag_target - _row_scroll
		var drop_y: float = ry + drop_vis * ROW_H
		_panel.draw_line(Vector2(wx + 4, drop_y), Vector2(wx + ww - 4, drop_y),
			Color(0.3, 1.0, 0.3, 0.9), 2.0)
		_panel.draw_circle(Vector2(wx + 4, drop_y), 3.0, Color(0.3, 1.0, 0.3))

	# Inline edit field (when row selected)
	var by := ry + list_h
	if _selected_row >= 0:
		_draw_edit_field(wx, by, ww)
		by += _edit_field_height()
		# Check detail log (when a check row with results is selected)
		if _run_detail.has(_selected_row):
			_draw_detail_panel(wx, by, ww)
			by += _detail_panel_height()
		# Notify help (when notify row is selected and active)
		elif _selected_row >= 0 and _selected_row < _script.size() and _script[_selected_row].strip_edges().begins_with("notify ") and get_meta("notify_active", false):
			var nh: float = 56.0
			_panel.draw_rect(Rect2(wx, by, ww, nh), Color(0.1, 0.1, 0.05, 1.0))
			_panel.draw_rect(Rect2(wx, by, ww, nh), Color(0.6, 0.6, 0.3, 0.4), false, 1.0)
			_panel.draw_string(font, Vector2(wx + 10, by + 16),
				"Review the test results above. Click check rows to see details.",
				HORIZONTAL_ALIGNMENT_LEFT, ww - 16, 10, Color(0.8, 0.8, 0.5))
			_panel.draw_string(font, Vector2(wx + 10, by + 32),
				"Inspect violations in the game world. Drag handles to adjust.",
				HORIZONTAL_ALIGNMENT_LEFT, ww - 16, 10, Color(0.8, 0.8, 0.5))
			_panel.draw_string(font, Vector2(wx + 10, by + 48),
				"Click [Done ✓] when finished reviewing.",
				HORIZONTAL_ALIGNMENT_LEFT, ww - 16, 10, Color(0.6, 0.9, 0.5))
			by += nh

	# Button bar
	_draw_buttons(wx, by, ww)

	# Result summary bar
	if not _run_summary.is_empty():
		by += BUTTON_H
		var all_pass: bool = _run_summary.begins_with("%d/%d" % [_run_results.values().count("pass") + _run_results.values().count("info"), _run_results.values().count("pass") + _run_results.values().count("info")])
		# Simpler: check if "fail" in any result
		var has_fail: bool = "fail" in _run_results.values()
		var sum_col := Color(0.3, 1.0, 0.3) if not has_fail else Color(1.0, 0.4, 0.4)
		var sum_bg := Color(0.08, 0.15, 0.08, 0.95) if not has_fail else Color(0.2, 0.08, 0.08, 0.95)
		_panel.draw_rect(Rect2(wx, by, ww, 22), sum_bg)
		_panel.draw_string(font, Vector2(wx + 10, by + 16), _run_summary,
			HORIZONTAL_ALIGNMENT_LEFT, ww - 16, 12, sum_col)


	# Status flash message (save feedback etc.)
	if _status_timer > 0 and not _status_msg.is_empty():
		var alpha: float = minf(1.0, _status_timer * 2.0)  # Fade out in last 0.5s
		var scol := Color(0.3, 1.0, 0.3, alpha) if _status_msg.begins_with("OK") else Color(1.0, 0.9, 0.3, alpha)
		_panel.draw_rect(Rect2(wx, wy + wh + 4, ww, 20), Color(0.08, 0.12, 0.08, 0.9 * alpha))
		_panel.draw_string(font, Vector2(wx + 10, wy + wh + 18), _status_msg,
			HORIZONTAL_ALIGNMENT_LEFT, ww - 16, 11, scol)

	# Top bar hint
	var hint := "T:pick  Tab:mode  Ctrl+S:save  Ctrl+R:reload  Esc:close"
	if _selected_row >= 0:
		var sel_p := _parse_command(_script[_selected_row] if _selected_row < _script.size() else "")
		if sel_p.get("type", "none") == "bleap_plan":
			hint += "  RClick/Del:remove disallow"
	_panel.draw_string(font, Vector2(wx, wy - 14), hint,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.45, 0.45, 0.45))

	# Scroll indicator
	if _script.size() > _visible_row_count():
		var shown_start := _row_scroll + 1
		var shown_end   := mini(_row_scroll + _visible_row_count(), _script.size())
		_panel.draw_string(font, Vector2(wx + ww - 60, wy + TITLE_H + 10),
			"%d–%d/%d" % [shown_start, shown_end, _script.size()],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.4, 0.4, 0.4))


func _draw_edit_field(wx: float, wy: float, ww: float) -> void:
	var font: Font = ThemeDB.fallback_font
	var eh: float = _edit_field_height()
	var border_col := Color(0.4, 0.8, 0.4, 0.8) if _edit_focused else Color(0.3, 0.5, 0.3, 0.5)
	_panel.draw_rect(Rect2(wx, wy, ww, eh), Color(0.05, 0.1, 0.05, 1.0))
	_panel.draw_rect(Rect2(wx, wy, ww, eh), border_col, false, 1.0)

	# Wrap text into visual lines
	var avail_w: float = ww - 24.0
	var display := "  " + _edit_text
	var wrap_lines: PackedStringArray = _wrap_text(display, font, avail_w, 11)

	# Draw each wrapped line
	var ly: float = wy + 16.0
	for wl in wrap_lines:
		_panel.draw_string(font, Vector2(wx + 12, ly), wl,
			HORIZONTAL_ALIGNMENT_LEFT, avail_w, 11, Color(0.9, 1.0, 0.85))
		ly += 16.0

	# Selection highlight (approximate — first visual line only for simplicity)
	if _edit_has_sel():
		var sf := mini(_edit_sel_start, _edit_cursor)
		var st := maxi(_edit_sel_start, _edit_cursor)
		var xf := 12.0 + font.get_string_size("  " + _edit_text.substr(0, sf),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var xt := 12.0 + font.get_string_size("  " + _edit_text.substr(0, st),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		# Clamp to first line for now
		xf = fmod(xf, avail_w)
		xt = fmod(xt, avail_w)
		if xt > xf:
			_panel.draw_rect(Rect2(wx + xf, wy + 4, xt - xf, 14), Color(0.3, 0.6, 0.3, 0.4))

	# Cursor
	if _edit_focused and int(_run_blink * 2) % 2 == 0:
		var full_cx: float = font.get_string_size("  " + _edit_text.substr(0, _edit_cursor),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var line_idx: int = int(full_cx / avail_w)
		var cx: float = wx + 12.0 + fmod(full_cx, avail_w)
		var cy: float = wy + 5.0 + line_idx * 16.0
		_panel.draw_line(Vector2(cx, cy), Vector2(cx, cy + 12),
			Color(0.4, 1.0, 0.4, 0.9), 1.5)


func _wrap_text(text: String, font: Font, max_w: float, size: int) -> PackedStringArray:
	## Split text into wrapped lines that fit within max_w pixels.
	var lines: PackedStringArray = []
	var current := ""
	for ch in text:
		var test := current + ch
		if font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_w and not current.is_empty():
			lines.append(current)
			current = ch
		else:
			current = test
	if not current.is_empty():
		lines.append(current)
	if lines.is_empty():
		lines.append("")
	return lines


func _draw_detail_panel(wx: float, wy: float, ww: float) -> void:
	## Draw the check detail log panel — shows per-plan pass/fail breakdown.
	var detail_lines: Array = _run_detail.get(_selected_row, [])
	if detail_lines.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	var dh: float = _detail_panel_height()
	# Background
	_panel.draw_rect(Rect2(wx, wy, ww, dh), Color(0.04, 0.04, 0.07, 1.0))
	_panel.draw_rect(Rect2(wx, wy, ww, dh), Color(0.4, 0.4, 0.6, 0.4), false, 1.0)
	# Lines
	var ly: float = wy + 12.0
	var max_lines: int = mini(detail_lines.size(), 12)
	for i in range(max_lines):
		var dl: String = detail_lines[i]
		var col := Color(0.7, 0.7, 0.7)
		if "PASS" in dl or "MATCHED" in dl:
			col = Color(0.3, 0.9, 0.3)
		elif "FAIL" in dl or "not matched" in dl:
			col = Color(1.0, 0.4, 0.4)
		elif "LEAPS" in dl or "candidates" in dl or "leap_def" in dl:
			col = Color(0.5, 0.7, 1.0)
		_panel.draw_string(font, Vector2(wx + 8, ly), dl,
			HORIZONTAL_ALIGNMENT_LEFT, ww - 16, 10, col)
		ly += 14.0
	if detail_lines.size() > 12:
		_panel.draw_string(font, Vector2(wx + 8, ly), "... +%d more lines" % (detail_lines.size() - 12),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.5, 0.5, 0.5))


func _draw_buttons(wx: float, wy: float, ww: float) -> void:
	var font: Font = ThemeDB.fallback_font
	_panel.draw_rect(Rect2(wx, wy, ww, BUTTON_H), Color(0.07, 0.1, 0.07, 1.0))
	_panel.draw_line(Vector2(wx, wy), Vector2(wx + ww, wy), Color(0.3, 0.5, 0.3, 0.4), 1.0)

	var btns := _get_buttons()
	var bw := (ww - 16.0) / float(btns.size())
	for i in range(btns.size()):
		var bx := wx + 8.0 + i * bw
		var label: String = btns[i][0]
		var col: Color = btns[i][1]
		_panel.draw_rect(Rect2(bx, wy + 6, bw - 4, BUTTON_H - 12),
			col * Color(1, 1, 1, 0.15))
		_panel.draw_rect(Rect2(bx, wy + 6, bw - 4, BUTTON_H - 12),
			col * Color(1, 1, 1, 0.5), false, 1.0)
		_panel.draw_string(font, Vector2(bx + 4, wy + BUTTON_H - 10), label,
			HORIZONTAL_ALIGNMENT_LEFT, bw - 8, 10, col)


func _draw_picker() -> void:
	var font: Font = ThemeDB.fallback_font
	var vp  := get_viewport().get_visible_rect().size
	var pw  := 440.0
	var ph  := minf(vp.y - 80.0, 60.0 + _picker_items.size() * 20.0 + 40.0)
	var px  := (vp.x - pw) / 2.0
	var py  := (vp.y - ph) / 2.0

	_panel.draw_rect(Rect2(px, py, pw, ph), Color(0.07, 0.07, 0.1, 0.97))
	_panel.draw_rect(Rect2(px, py, pw, ph), Color(0.4, 0.65, 0.4, 0.7), false, 2.0)
	_panel.draw_string(font, Vector2(px + 16, py + 22),
		"Choose Test  (type to filter, ↑↓ navigate, Enter load, Esc cancel)",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.9, 0.7))

	# Filter field
	_panel.draw_rect(Rect2(px + 12, py + 32, pw - 24, 22), Color(0.05, 0.1, 0.05, 1.0))
	_panel.draw_rect(Rect2(px + 12, py + 32, pw - 24, 22), Color(0.4, 0.7, 0.4, 0.6), false, 1.0)
	var filter_display := "Filter: " + _picker_filter + ("|" if int(_run_blink * 2) % 2 == 0 else " ")
	_panel.draw_string(font, Vector2(px + 18, py + 48), filter_display,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 1.0, 0.8))

	# Test list
	var ly := py + 64.0
	var visible_start := maxi(0, _picker_sel - 10)
	for i in range(visible_start, _picker_items.size()):
		if ly > py + ph - 36.0:
			break
		var is_sel := (i == _picker_sel)
		if is_sel:
			_panel.draw_rect(Rect2(px + 12, ly - 2, pw - 24, 20), Color(0.2, 0.4, 0.2, 0.7))
		var item_col := Color(1.0, 1.0, 0.85) if is_sel else Color(0.65, 0.65, 0.65)
		var prefix := "▶ " if is_sel else "  "
		_panel.draw_string(font, Vector2(px + 18, ly + 13), prefix + _picker_items[i],
			HORIZONTAL_ALIGNMENT_LEFT, pw - 30, 12, item_col)
		ly += 20.0

	if _picker_items.is_empty():
		_panel.draw_string(font, Vector2(px + 20, ly + 13), "(no tests found)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.5, 0.5))


# -- Utility -------------------------------------------------------------------

func _cmd_color(cmd: String) -> Color:
	## Color-code commands by category for the row list.
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
