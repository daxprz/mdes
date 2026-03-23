extends CanvasLayer

## Quake-style pop-down console. Slides from top of screen on backtick (`).
## Accepts RCON commands directly. Supports test runner via `run` and `suite` commands.
## Input line supports cursor movement, text selection, and clipboard (cut/copy/paste).

const SLIDE_SPEED := 800.0  # Pixels per second for slide animation
const MAX_HISTORY := 50     # Command history size
const MAX_OUTPUT := 200     # Max output lines
const INPUT_FONT_SIZE := 12
const OUTPUT_FONT_SIZE := 11

var _active := false
var _panel_y: float = -400.0  # Current Y position (negative = hidden)
var _target_y: float = -400.0 # Target Y position
var _panel_height: float = 400.0

var _output_lines: Array[Dictionary] = []  # [{text, color}]
var _command_history: Array[String] = []
var _history_idx: int = -1
var _current_input: String = ""
var _cursor_pos: int = 0        # Caret position within _current_input
var _select_start: int = -1     # Selection anchor (-1 = no selection)
var _scroll_offset: int = 0
var _cursor_blink: float = 0.0

# Autocomplete
var _tab_completions: Array[String] = []
var _tab_index: int = 0

# All known commands for autocomplete
const COMMANDS := [
	"help", "debug", "spawn monster", "spawn dummy", "spawn attacker",
	"clear", "clearplayers", "enablejoins", "portal off", "portal on",
	"tp", "tab", "key", "enemies", "players", "status", "quit",
	"standdown on", "standdown off", "standdown",
	"territorial on", "territorial off", "territorial",
	"revive", "resethp", "fps", "hp", "ik", "ikreset", "thrash", "ball",
	"debugdraw", "title", "score", "grid",
	"partstatus", "partdmg", "weight",
	"attach balloon", "detach",
	"tether status", "tether cut", "tether length",
	"chain status", "chain cut", "chaindump",
	"splay list", "splay spawn", "splay clear", "splay status",
	"dump",
	"attacker target", "attacker part", "attacker weapon",
	"attacker rate", "attacker stop", "attacker start", "attacker stats",
	"attacker tether_length", "attacker tether_b",
	"run", "suite", "tests", "cls",
	"leaps", "clearleaps",
	"bleap reset", "bleap a", "bleap b", "bleap plan req", "bleap plan opt",
	"bleap start", "bleap end", "bleap disallow", "bleap min", "bleap show",
	"testload", "testshow", "testedit", "testinsert", "testdelete",
	"testrun", "testsave", "testnew",
	"etz", "daz", "zones", "clearzones",
	"debug", "debug list", "debug on", "debug off",
	"debug log", "debug console", "debug both", "debug nolog",
	"debug save", "debug load", "debug filter type", "debug filter id",
	"debug reset", "debug profile", "debug clear_transient",
]

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
		var shift: bool = event.shift_pressed
		var ctrl: bool = event.ctrl_pressed or event.meta_pressed

		match event.keycode:
			KEY_ESCAPE:
				toggle()
				get_viewport().set_input_as_handled()

			KEY_ENTER:
				_execute_input()
				get_viewport().set_input_as_handled()

			KEY_TAB:
				_autocomplete()
				get_viewport().set_input_as_handled()

			KEY_BACKSPACE:
				if _has_selection():
					_delete_selection()
				elif _cursor_pos > 0:
					_current_input = _current_input.substr(0, _cursor_pos - 1) + _current_input.substr(_cursor_pos)
					_cursor_pos -= 1
				_tab_completions.clear()
				get_viewport().set_input_as_handled()

			KEY_DELETE:
				if _has_selection():
					_delete_selection()
				elif _cursor_pos < _current_input.length():
					_current_input = _current_input.substr(0, _cursor_pos) + _current_input.substr(_cursor_pos + 1)
				_tab_completions.clear()
				get_viewport().set_input_as_handled()

			KEY_LEFT:
				if ctrl:
					# Jump to previous word boundary
					var p: int = _cursor_pos - 1
					while p > 0 and _current_input[p - 1] == " ":
						p -= 1
					while p > 0 and _current_input[p - 1] != " ":
						p -= 1
					_move_cursor(p, shift)
				else:
					_move_cursor(maxi(0, _cursor_pos - 1), shift)
				get_viewport().set_input_as_handled()

			KEY_RIGHT:
				if ctrl:
					# Jump to next word boundary
					var p: int = _cursor_pos
					var len: int = _current_input.length()
					while p < len and _current_input[p] != " ":
						p += 1
					while p < len and _current_input[p] == " ":
						p += 1
					_move_cursor(p, shift)
				else:
					_move_cursor(mini(_current_input.length(), _cursor_pos + 1), shift)
				get_viewport().set_input_as_handled()

			KEY_HOME:
				_move_cursor(0, shift)
				get_viewport().set_input_as_handled()

			KEY_END:
				_move_cursor(_current_input.length(), shift)
				get_viewport().set_input_as_handled()

			KEY_UP:
				if not ctrl:
					_history_up()
					get_viewport().set_input_as_handled()

			KEY_DOWN:
				if not ctrl:
					_history_down()
					get_viewport().set_input_as_handled()

			KEY_PAGEUP:
				_scroll_offset = mini(_scroll_offset + 5, maxi(0, _output_lines.size() - 10))
				get_viewport().set_input_as_handled()

			KEY_PAGEDOWN:
				_scroll_offset = maxi(_scroll_offset - 5, 0)
				get_viewport().set_input_as_handled()

			_:
				# Ctrl+A/C/X/V — must be here (not in separate match cases) so
				# plain a/c/x/v without ctrl still fall through to character typing
				if ctrl:
					match event.keycode:
						KEY_A:
							_select_start = 0
							_cursor_pos = _current_input.length()
							get_viewport().set_input_as_handled()
							return
						KEY_C:
							var text: String = _get_selected_text() if _has_selection() else _current_input
							if not text.is_empty():
								DisplayServer.clipboard_set(text)
							get_viewport().set_input_as_handled()
							return
						KEY_X:
							if _has_selection():
								DisplayServer.clipboard_set(_get_selected_text())
								_delete_selection()
							get_viewport().set_input_as_handled()
							return
						KEY_V:
							var clip: String = DisplayServer.clipboard_get()
							if not clip.is_empty():
								clip = clip.replace("\r\n", " ").replace("\n", " ").replace("\r", " ").strip_edges()
								if _has_selection():
									_delete_selection()
								_current_input = _current_input.substr(0, _cursor_pos) + clip + _current_input.substr(_cursor_pos)
								_cursor_pos += clip.length()
								_tab_completions.clear()
							get_viewport().set_input_as_handled()
							return
				# Type character
				if event.unicode > 0 and event.keycode != KEY_QUOTELEFT and not ctrl:
					if _has_selection():
						_delete_selection()
					var ch: String = char(event.unicode)
					_current_input = _current_input.substr(0, _cursor_pos) + ch + _current_input.substr(_cursor_pos)
					_cursor_pos += 1
					_tab_completions.clear()
					get_viewport().set_input_as_handled()


# -- Selection helpers ---------------------------------------------------------


func _has_selection() -> bool:
	return _select_start >= 0 and _select_start != _cursor_pos


func _get_selected_text() -> String:
	if not _has_selection():
		return ""
	var from: int = mini(_select_start, _cursor_pos)
	var to: int   = maxi(_select_start, _cursor_pos)
	return _current_input.substr(from, to - from)


func _delete_selection() -> void:
	if not _has_selection():
		return
	var from: int = mini(_select_start, _cursor_pos)
	var to: int   = maxi(_select_start, _cursor_pos)
	_current_input = _current_input.substr(0, from) + _current_input.substr(to)
	_cursor_pos = from
	_select_start = -1


func _move_cursor(new_pos: int, extend_selection: bool) -> void:
	## Move cursor to new_pos. If extend_selection, anchor stays put; else clear selection.
	if extend_selection:
		if _select_start < 0:
			_select_start = _cursor_pos  # Anchor at old position
	else:
		_select_start = -1  # Clear selection
	_cursor_pos = new_pos
	_cursor_blink = 0.0  # Reset blink so cursor is visible after move


# -- Input execution -----------------------------------------------------------


func _execute_input() -> void:
	var cmd: String = _current_input.strip_edges()
	_current_input = ""
	_cursor_pos = 0
	_select_start = -1
	_tab_completions.clear()
	if cmd.is_empty():
		return

	# Add to history
	_command_history.append(cmd)
	if _command_history.size() > MAX_HISTORY:
		_command_history.remove_at(0)
	_history_idx = -1
	_scroll_offset = 0

	_log("> " + cmd, Color(1.0, 1.0, 0.8))

	# Parse special console commands
	var parts: PackedStringArray = cmd.split(" ", false)
	if parts.is_empty():
		return

	match parts[0].to_lower():
		"cls":
			_output_lines.clear()
		"run", "suite":
			# Route through RCON so key=value args are parsed
			var rcon2: Node = get_node_or_null("/root/Rcon")
			if rcon2:
				# Close console so editor is visible
				_active = false
				_target_y = -_panel_height
				var result2: String = rcon2._execute(cmd)
				_log_result(result2)
		_:
			# Route everything to RCON
			var rcon: Node = get_node_or_null("/root/Rcon")
			if rcon:
				var result: String = rcon._execute(cmd)
				_log_result(result)
			else:
				_log("ERR: RCON not available", Color(1.0, 0.3, 0.3))


func _run_test_in_editor(test_name: String) -> void:
	## Open the test editor, load the test, and hit play — so the human can SEE it.
	# Find or create the test editor via the test menu
	var scene_root := get_tree().current_scene
	var editor: Node = null
	# Look for existing test editor in the scene tree
	for node in scene_root.get_children():
		if node.has_method("toggle") and node.has_method("_load_test") and node.has_method("_run_test"):
			editor = node
			break
	if editor == null:
		# Create one
		var script := load("res://scripts/ui/test_editor.gd")
		editor = CanvasLayer.new()
		editor.set_script(script)
		scene_root.add_child(editor)
	# Ensure it's open
	if not editor._active:
		editor.toggle()
	# Close the console so it doesn't cover the editor
	_active = false
	_target_y = -_panel_height
	# Load and run (deferred so the editor is ready)
	editor._load_test(test_name)
	editor.call_deferred("_run_test")
	_log("Opening test '%s' in editor..." % test_name, Color(0.5, 0.9, 0.5))


func _run_suite_in_editor(suite_name: String) -> void:
	## Open the test editor and run the suite through it — each test loads visually.
	var scene_root := get_tree().current_scene
	var editor: Node = null
	for node in scene_root.get_children():
		if node.has_method("toggle") and node.has_method("run_suite"):
			editor = node
			break
	if editor == null:
		var script := load("res://scripts/ui/test_editor.gd")
		editor = CanvasLayer.new()
		editor.set_script(script)
		scene_root.add_child(editor)
	if not editor._active:
		editor.toggle()
	_active = false
	_target_y = -_panel_height
	editor.run_suite(suite_name)
	_log("Running suite '%s' in editor..." % suite_name, Color(0.5, 0.9, 0.5))


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


# -- Autocomplete --------------------------------------------------------------


func _autocomplete() -> void:
	## Tab autocomplete — cycles through matching commands and known test/suite names.
	if _current_input.is_empty():
		return

	# Build completions list on first tab press (or after input cleared them)
	if _tab_completions.is_empty():
		var prefix: String = _current_input.to_lower()

		# Commands that take a test name as first argument
		for test_cmd in ["run ", "testload ", "testsave "]:
			if prefix.begins_with(test_cmd):
				var name_prefix: String = prefix.substr(test_cmd.length())
				for test_name in _get_test_names():
					if test_name.to_lower().begins_with(name_prefix):
						_tab_completions.append(test_cmd.strip_edges() + " " + test_name)
				_tab_index = 0
				break

		# suite / testnew take a suite name
		if _tab_completions.is_empty() and prefix.begins_with("suite "):
			var name_prefix: String = prefix.substr(6)
			for suite_name in _get_suite_names():
				if suite_name.to_lower().begins_with(name_prefix):
					_tab_completions.append("suite " + suite_name)
			_tab_index = 0

		# Fall back to command keyword completion
		if _tab_completions.is_empty():
			for cmd in COMMANDS:
				if cmd.to_lower().begins_with(prefix):
					_tab_completions.append(cmd)
			_tab_index = 0

	if _tab_completions.is_empty():
		return

	# Cycle through completions and place cursor at end
	_current_input = _tab_completions[_tab_index]
	_cursor_pos = _current_input.length()
	_select_start = -1
	_tab_index = (_tab_index + 1) % _tab_completions.size()


func _get_test_names() -> Array[String]:
	var names: Array[String] = []
	for dir_path in ["res://data/tests/", "user://data/tests/"]:
		var dir := DirAccess.open(dir_path)
		if not dir:
			continue
		dir.list_dir_begin()
		var fname: String = dir.get_next()
		while fname != "":
			if fname.ends_with(".json") and not dir.current_is_dir():
				names.append(fname.replace(".json", ""))
			fname = dir.get_next()
	return names


func _get_suite_names() -> Array[String]:
	var names: Array[String] = []
	for dir_path in ["res://data/tests/suites/", "user://data/tests/suites/"]:
		var dir := DirAccess.open(dir_path)
		if not dir:
			continue
		dir.list_dir_begin()
		var fname: String = dir.get_next()
		while fname != "":
			if fname.ends_with(".json") and not dir.current_is_dir():
				names.append(fname.replace(".json", ""))
			fname = dir.get_next()
	return names


# -- History -------------------------------------------------------------------


func _history_up() -> void:
	if _command_history.is_empty():
		return
	if _history_idx < 0:
		_history_idx = _command_history.size() - 1
	elif _history_idx > 0:
		_history_idx -= 1
	_current_input = _command_history[_history_idx]
	_cursor_pos = _current_input.length()
	_select_start = -1


func _history_down() -> void:
	if _history_idx < 0:
		return
	_history_idx += 1
	if _history_idx >= _command_history.size():
		_history_idx = -1
		_current_input = ""
		_cursor_pos = 0
	else:
		_current_input = _command_history[_history_idx]
		_cursor_pos = _current_input.length()
	_select_start = -1


# -- Test Runner Integration ---------------------------------------------------



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
		_panel.draw_string(font, Vector2(10, y + 10), entry["text"],
			HORIZONTAL_ALIGNMENT_LEFT, pw - 20, OUTPUT_FONT_SIZE, entry["color"])
		y += line_h

	# Autocomplete hint (above input line)
	if not _tab_completions.is_empty():
		var hint_y: float = _panel_y + ph - 36
		var hint_parts: Array[String] = []
		var selected_ci: int = (_tab_index - 1 + _tab_completions.size()) % _tab_completions.size()
		for ci in range(mini(_tab_completions.size(), 8)):
			if ci == selected_ci:
				hint_parts.append("[%s]" % _tab_completions[ci])
			else:
				hint_parts.append(_tab_completions[ci])
		var hint_text: String = "  ".join(hint_parts)
		if _tab_completions.size() > 8:
			hint_text += "  (+%d more)" % (_tab_completions.size() - 8)
		_panel.draw_string(font, Vector2(10, hint_y + 10), hint_text,
			HORIZONTAL_ALIGNMENT_LEFT, pw - 20, 10, Color(0.5, 0.7, 0.5, 0.7))

	# Input line background
	var input_y: float = _panel_y + ph - 20
	_panel.draw_rect(Rect2(0, input_y - 2, pw, 20), Color(0.08, 0.08, 0.1, 0.9))

	# Measure prompt prefix to find pixel position of characters
	var prompt_prefix: String = "> "
	var prefix_w: float = font.get_string_size(prompt_prefix, HORIZONTAL_ALIGNMENT_LEFT, -1, INPUT_FONT_SIZE).x

	# Selection highlight
	if _has_selection():
		var sel_from: int = mini(_select_start, _cursor_pos)
		var sel_to: int   = maxi(_select_start, _cursor_pos)
		var x_from: float = 10 + prefix_w + font.get_string_size(
			_current_input.substr(0, sel_from), HORIZONTAL_ALIGNMENT_LEFT, -1, INPUT_FONT_SIZE).x
		var x_to: float = 10 + prefix_w + font.get_string_size(
			_current_input.substr(0, sel_to), HORIZONTAL_ALIGNMENT_LEFT, -1, INPUT_FONT_SIZE).x
		_panel.draw_rect(Rect2(x_from, input_y - 1, x_to - x_from, 16), Color(0.3, 0.6, 0.3, 0.4))

	# Input text
	_panel.draw_string(font, Vector2(10, input_y + 12),
		prompt_prefix + _current_input, HORIZONTAL_ALIGNMENT_LEFT, pw - 20, INPUT_FONT_SIZE, Color(0.3, 1.0, 0.3))

	# Cursor (blinking vertical bar at _cursor_pos)
	if int(_cursor_blink * 2) % 2 == 0:
		var cursor_x: float = 10 + prefix_w + font.get_string_size(
			_current_input.substr(0, _cursor_pos), HORIZONTAL_ALIGNMENT_LEFT, -1, INPUT_FONT_SIZE).x
		_panel.draw_line(
			Vector2(cursor_x, input_y - 1),
			Vector2(cursor_x, input_y + 14),
			Color(0.3, 1.0, 0.3, 0.9), 1.5)

	# Scroll indicator
	if _scroll_offset > 0:
		_panel.draw_string(font, Vector2(pw - 80, _panel_y + 10), "PgUp/PgDn",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.4, 0.4))
