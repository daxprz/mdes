extends CanvasLayer

## Quake-style pop-down console. Slides from top of screen on backtick (`).
## Accepts RCON commands directly. Supports test runner via `run` and `suite` commands.

const SLIDE_SPEED := 800.0  # Pixels per second for slide animation
const MAX_HISTORY := 50     # Command history size
const MAX_OUTPUT := 200     # Max output lines

var _active := false
var _panel_y: float = -400.0  # Current Y position (negative = hidden)
var _target_y: float = -400.0 # Target Y position
var _panel_height: float = 400.0

var _output_lines: Array[Dictionary] = []  # [{text, color}]
var _command_history: Array[String] = []
var _history_idx: int = -1
var _current_input: String = ""
var _scroll_offset: int = 0
var _cursor_blink: float = 0.0

# Test runner
var _test_runner: Node = null

var _panel: Control = null


func _ready() -> void:
	layer = 110  # Above everything
	_panel = Control.new()
	_panel.name = "ConsolePanel"
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.draw.connect(_draw_console)
	add_child(_panel)
	_log("Game Console v%s — type 'help' for commands" % Version.get_string(), Color(0.5, 0.8, 0.5))
	_log("  run <test>  — run a test file", Color(0.4, 0.6, 0.4))
	_log("  suite <name> — run a test suite", Color(0.4, 0.6, 0.4))
	_log("  tests — list available tests/suites", Color(0.4, 0.6, 0.4))


func toggle() -> void:
	_active = not _active
	_target_y = 0.0 if _active else -_panel_height


func is_open() -> bool:
	return _active


func _process(delta: float) -> void:
	# Slide animation
	if absf(_panel_y - _target_y) > 1.0:
		_panel_y = lerpf(_panel_y, _target_y, delta * 8.0)
		_panel.queue_redraw()
	elif _panel_y != _target_y:
		_panel_y = _target_y

	if _active:
		_cursor_blink += delta
		_panel.queue_redraw()


func _input(event: InputEvent) -> void:
	# Backtick toggles console (skip if in splay edit physics preview)
	if event is InputEventKey and event.pressed and event.keycode == KEY_QUOTELEFT:
		# Check if level editor splay edit is using backtick
		var editor: Node = null
		for child in get_tree().current_scene.get_children():
			if child.name == "LevelEditor" or (child is CanvasLayer and child.has_method("toggle")):
				if "_mode" in child and child._mode == 7:  # SPLAY_EDIT
					return  # Let splay edit handle backtick
		toggle()
		get_viewport().set_input_as_handled()
		return

	if not _active:
		return

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				toggle()
				get_viewport().set_input_as_handled()
			KEY_ENTER:
				_execute_input()
				get_viewport().set_input_as_handled()
			KEY_BACKSPACE:
				if _current_input.length() > 0:
					_current_input = _current_input.substr(0, _current_input.length() - 1)
				get_viewport().set_input_as_handled()
			KEY_UP:
				_history_up()
				get_viewport().set_input_as_handled()
			KEY_DOWN:
				_history_down()
				get_viewport().set_input_as_handled()
			KEY_PAGEUP:
				_scroll_offset = mini(_scroll_offset + 5, maxi(0, _output_lines.size() - 10))
				get_viewport().set_input_as_handled()
			KEY_PAGEDOWN:
				_scroll_offset = maxi(_scroll_offset - 5, 0)
				get_viewport().set_input_as_handled()
			_:
				# Type character
				if event.unicode > 0 and event.keycode != KEY_QUOTELEFT:
					_current_input += char(event.unicode)
					get_viewport().set_input_as_handled()


func _execute_input() -> void:
	var cmd: String = _current_input.strip_edges()
	if cmd.is_empty():
		return

	# Add to history
	_command_history.append(cmd)
	if _command_history.size() > MAX_HISTORY:
		_command_history.remove_at(0)
	_history_idx = -1
	_current_input = ""
	_scroll_offset = 0

	_log("> " + cmd, Color(1.0, 1.0, 0.8))

	# Parse special console commands
	var parts: PackedStringArray = cmd.split(" ", false)
	if parts.is_empty():
		return

	match parts[0].to_lower():
		"run":
			if parts.size() < 2:
				_log("Usage: run <test_name>", Color(1.0, 0.5, 0.3))
			else:
				_run_test(parts[1])
		"suite":
			if parts.size() < 2:
				_log("Usage: suite <suite_name>", Color(1.0, 0.5, 0.3))
			else:
				_run_suite(parts[1])
		"tests":
			_list_tests()
		"clear":
			if parts.size() == 1 and cmd == "clear":
				# Ambiguous: could be "clear console" or "clear enemies"
				# Use "cls" for console clear
				var rcon: Node = get_node_or_null("/root/Rcon")
				if rcon:
					var result: String = rcon._execute(cmd)
					_log_result(result)
			else:
				var rcon: Node = get_node_or_null("/root/Rcon")
				if rcon:
					var result: String = rcon._execute(cmd)
					_log_result(result)
		"cls":
			_output_lines.clear()
		_:
			# Route to RCON
			var rcon: Node = get_node_or_null("/root/Rcon")
			if rcon:
				var result: String = rcon._execute(cmd)
				_log_result(result)
			else:
				_log("ERR: RCON not available", Color(1.0, 0.3, 0.3))


func _log(text: String, color: Color = Color(0.7, 0.7, 0.7)) -> void:
	for line in text.split("\n"):
		_output_lines.append({"text": line, "color": color})
	if _output_lines.size() > MAX_OUTPUT:
		_output_lines = _output_lines.slice(_output_lines.size() - MAX_OUTPUT)


func _log_result(result: String) -> void:
	if result.begins_with("OK"):
		_log(result, Color(0.3, 0.9, 0.3))
	elif result.begins_with("ERR"):
		_log(result, Color(1.0, 0.3, 0.3))
	else:
		_log(result, Color(0.8, 0.8, 0.8))


func _history_up() -> void:
	if _command_history.is_empty():
		return
	if _history_idx < 0:
		_history_idx = _command_history.size() - 1
	elif _history_idx > 0:
		_history_idx -= 1
	_current_input = _command_history[_history_idx]


func _history_down() -> void:
	if _history_idx < 0:
		return
	_history_idx += 1
	if _history_idx >= _command_history.size():
		_history_idx = -1
		_current_input = ""
	else:
		_current_input = _command_history[_history_idx]


# -- Test Runner Integration ---------------------------------------------------

func _list_tests() -> void:
	_log("=== Available Tests ===", Color(1.0, 0.9, 0.3))
	_list_files_in_dir("res://data/tests/", "test")
	_list_files_in_dir("user://data/tests/", "test (custom)")
	_log("=== Available Suites ===", Color(1.0, 0.9, 0.3))
	_list_files_in_dir("res://data/tests/suites/", "suite")
	_list_files_in_dir("user://data/tests/suites/", "suite (custom)")


func _list_files_in_dir(dir_path: String, label: String) -> void:
	var dir := DirAccess.open(dir_path)
	if not dir:
		return
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.ends_with(".json"):
			_log("  %s: %s" % [label, fname.replace(".json", "")], Color(0.6, 0.8, 0.6))
		fname = dir.get_next()


func _run_test(test_name: String) -> void:
	_ensure_test_runner()
	if _test_runner:
		_test_runner.run_test(test_name, self)


func _run_suite(suite_name: String) -> void:
	_ensure_test_runner()
	if _test_runner:
		_test_runner.run_suite(suite_name, self)


func _ensure_test_runner() -> void:
	if _test_runner and is_instance_valid(_test_runner):
		return
	var script: GDScript = load("res://scripts/systems/test_runner.gd")
	_test_runner = Node.new()
	_test_runner.name = "TestRunner"
	_test_runner.set_script(script)
	add_child(_test_runner)


# -- Drawing -------------------------------------------------------------------

func _draw_console() -> void:
	if _panel_y <= -_panel_height + 1:
		return  # Fully hidden

	var vp: Vector2 = get_viewport().get_visible_rect().size
	var font: Font = ThemeDB.fallback_font
	var pw: float = vp.x
	var ph: float = _panel_height

	# Background
	_panel.draw_rect(Rect2(0, _panel_y, pw, ph), Color(0.05, 0.05, 0.08, 0.95))
	# Bottom border
	_panel.draw_line(Vector2(0, _panel_y + ph), Vector2(pw, _panel_y + ph), Color(0.3, 0.8, 0.3, 0.6), 2.0)

	# Output lines (scrollable)
	var line_h: float = 14.0
	var visible_lines: int = int((ph - 30) / line_h)
	var start_idx: int = maxi(0, _output_lines.size() - visible_lines - _scroll_offset)
	var end_idx: int = mini(start_idx + visible_lines, _output_lines.size())

	var y: float = _panel_y + 10
	for i in range(start_idx, end_idx):
		var entry: Dictionary = _output_lines[i]
		_panel.draw_string(font, Vector2(10, y + 10), entry["text"], HORIZONTAL_ALIGNMENT_LEFT, pw - 20, 11, entry["color"])
		y += line_h

	# Input line
	var input_y: float = _panel_y + ph - 20
	_panel.draw_rect(Rect2(0, input_y - 2, pw, 20), Color(0.08, 0.08, 0.1, 0.9))
	var prompt: String = "> " + _current_input
	# Cursor blink
	if int(_cursor_blink * 2) % 2 == 0:
		prompt += "_"
	_panel.draw_string(font, Vector2(10, input_y + 12), prompt, HORIZONTAL_ALIGNMENT_LEFT, pw - 20, 12, Color(0.3, 1.0, 0.3))

	# Scroll indicator
	if _scroll_offset > 0:
		_panel.draw_string(font, Vector2(pw - 80, _panel_y + 10), "PgUp/PgDn", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.4, 0.4))
