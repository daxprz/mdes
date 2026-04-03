extends CanvasLayer

## Console slides up from the bottom of the screen on backtick (`).
## Respects the debug drawer — limits width to the area right of the drawer.
## Game viewport resizes to fit above the console and right of the drawer.
## Accepts RCON commands directly. Supports test runner via `run` and `suite` commands.
##
## Keybindings:
##   Navigation:
##     Ctrl+A          — beginning of line (at start: select all)
##     Ctrl+E          — end of line
##     Left / Right    — move caret one character
##     Ctrl+Left/Right — move caret one word
##     Home / End      — beginning / end of line
##     Up / Down       — command history previous / next
##   Selection:
##     Shift + any movement key — extend selection
##   Editing:
##     Type            — insert at caret (replaces selection if active)
##     Backspace       — delete character before caret
##     Shift+Backspace — delete word backward
##     Ctrl+Backspace  — delete word backward
##     Delete          — delete character after caret
##     Ctrl+Delete     — delete word forward
##   Clipboard (OS):
##     Ctrl+C          — copy selection (or whole line if no selection)
##     Ctrl+X          — cut selection (or whole line if no selection)
##     Ctrl+V          — paste from system clipboard at caret
##   Kill ring (emacs):
##     Ctrl+K          — kill from caret to end of line
##     Ctrl+U          — kill from caret to beginning of line
##     Ctrl+W          — kill word backward
##     Ctrl+Y          — yank (paste from kill buffer)
##   Scrolling:
##     Mouse wheel     — scroll output history
##     PgUp / PgDn     — scroll output history (5 lines)
##   Other:
##     Tab             — autocomplete (cycles through matches)
##     Enter           — execute command
##     Escape          — close console
##     Backtick (`)    — toggle console open/close

const SLIDE_SPEED := 800.0  # Pixels per second for slide animation
const MAX_HISTORY := 50     # Command history size
const MAX_OUTPUT := 200     # Max output lines
const INPUT_FONT_SIZE := 12
const OUTPUT_FONT_SIZE := 11

var _active := false
var _panel_y: float = 0.0     # Current Y position of the TOP of the panel (screen coords)
var _target_y: float = 0.0    # Target Y position
var _panel_height: float = 300.0
var _panel_x: float = 0.0     # Left edge (shifted right when debug drawer is open)

var _output_lines: Array[Dictionary] = []  # [{text, color}]
var _command_history: Array[String] = []
var _history_idx: int = -1
var _current_input: String = ""
var _cursor_pos: int = 0        # Caret position within _current_input
var _select_start: int = -1     # Selection anchor (-1 = no selection)
var _scroll_offset: int = 0
var _cursor_blink: float = 0.0
var _kill_buffer: String = ""  # Ctrl+K kill ring / Ctrl+Y yank

# Autocomplete
var _tab_completions: Array[String] = []
var _tab_index: int = 0

# All known commands for autocomplete — static keywords.
# Dynamic completions (score names, debug aspects, test names, levels,
# modifier blueprints) are resolved at tab-time in _autocomplete().
const COMMANDS := [
	# -- Core --
	"help", "status", "enemies", "players", "quit", "cls",
	"eval", "emit",
	# -- Spawning --
	"spawn monster", "spawn dummy", "spawn attacker",
	"ai_spawn", "ai_cmd", "ai_off",
	# -- Entity control --
	"tp", "tab", "key", "kick",
	"clear", "clearplayers", "enablejoins",
	"kill", "revive", "resethp",
	"reset", "player_reset",
	# -- Monster --
	"standdown on", "standdown off", "standdown",
	"territorial on", "territorial off", "territorial",
	"precog", "ball", "thrash",
	# -- Info / display --
	"fps", "hp", "ik", "ikreset",
	"debugdraw", "title", "score", "grid",
	"partstatus", "partdmg", "weight",
	"dump", "dump ik", "dump skeleton",
	# -- Attachments / chain / tether --
	"attach balloon", "detach",
	"shackle_attach",
	"tether status", "tether cut", "tether length",
	"chain status", "chain cut", "chaindump",
	# -- Splay poses --
	"splay list", "splay spawn", "splay clear", "splay status",
	# -- Attacker dummy --
	"attacker target", "attacker part", "attacker weapon",
	"attacker rate", "attacker stop", "attacker start", "attacker stats",
	"attacker tether_length", "attacker tether_b",
	# -- Tests --
	"run", "suite", "tests",
	"testload", "testshow", "testedit", "testinsert", "testdelete",
	"testrun", "testsave", "testnew",
	# -- Zones / leaps --
	"etz", "daz", "zones", "clearzones",
	"leaps", "clearleaps",
	"bleap reset", "bleap a", "bleap b", "bleap plan req", "bleap plan opt",
	"bleap start", "bleap end", "bleap disallow", "bleap min", "bleap show",
	# -- Debug overlay --
	"debug", "debug list",
	"debug on", "debug off", "debug log", "debug nolog",
	"debug console", "debug both",
	"debug save", "debug load",
	"debug filter type", "debug filter id",
	"debug reset", "debug profile", "debug clear_transient",
	# -- Config / modifiers --
	"buff",
	"mod", "mods", "unmod",
	"smod", "smods", "unsmod",
	"gameconfig", "gc",
	# -- Portal --
	"portal on", "portal off",
	# -- Level --
	"level",
	# -- Executioner --
	"exec_tuning", "et", "exec_set", "exec_test",
	"exec_mode", "exec_get",
	# -- Notifications --
	"notify", "notify_dismiss",
	# -- Music --
	"music", "m",
	"music help",
	"music play", "music stop", "music off", "music test",
	"music score", "music scores",
	"music mml",
	"music intensity", "music i",
	"music tempo", "music bpm",
	"music layer", "music layer pad", "music layer bass",
	"music layer drums", "music layer melody",
	"music mute", "music unmute",
	"music push", "music combat", "music calm",
	# -- Mocap / skeleton --
	"mocap", "skeleton",
	# -- Announce / comment --
	"announce", "comment",
	# -- Strudel --
	"strudel", "strudel stop", "strudel hush",
	"strudel cps", "strudel status", "strudel drawer", "strudel voices",
	"strudel listen",
	"strudel test", "strudel test all", "strudel test algebra",
	"strudel test composers", "strudel test combinators", "strudel test signals",
	"strudel test mini", "strudel test integration", "strudel test voices",
	"musicdrawer", "md",
]

var _panel: Control = null


func _ready() -> void:
	layer = 110  # Above everything
	_panel = Control.new()
	_panel.name = "ConsolePanel"
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.draw.connect(_draw_console)
	add_child(_panel)
	# Start hidden below screen
	_panel_y = 1200.0  # Will be corrected on first _process
	_target_y = 1200.0
	_log("Game Console v%s — type 'help' for commands" % Version.get_string(), Color(0.5, 0.8, 0.5))
	_log("  run <test>  — run a test file", Color(0.4, 0.6, 0.4))
	_log("  suite <name> — run a test suite", Color(0.4, 0.6, 0.4))
	_log("  tests — list available tests/suites", Color(0.4, 0.6, 0.4))


func toggle() -> void:
	_active = not _active
	_update_target_y()


func is_open() -> bool:
	return _active


func _update_target_y() -> void:
	var vp_h: float = get_viewport().get_visible_rect().size.y
	_target_y = vp_h - _panel_height if _active else vp_h + 10


func _get_drawer_right_edge() -> float:
	## Returns the right edge of the debug drawer panel (0 if closed).
	var drawer: Node = get_node_or_null("/root/DebugDrawer")
	if drawer and drawer.is_open():
		return maxf(0.0, drawer._panel_x + drawer._panel_width)
	return 0.0


func _process(delta: float) -> void:
	# Smoothly lerp _panel_x toward the drawer's right edge
	var target_x: float = _get_drawer_right_edge()
	if absf(_panel_x - target_x) > 1.0:
		_panel_x = lerpf(_panel_x, target_x, delta * 8.0)
	else:
		_panel_x = target_x
	_update_target_y()

	# Slide animation
	if absf(_panel_y - _target_y) > 1.0:
		_panel_y = lerpf(_panel_y, _target_y, delta * 8.0)
		_panel.queue_redraw()
	elif _panel_y != _target_y:
		_panel_y = _target_y

	if _active:
		_cursor_blink += delta
		_panel.queue_redraw()
		# Only manage viewport when the debug drawer is NOT open
		# (when drawer is open, it handles both horizontal + vertical scaling)
		var drawer: Node = get_node_or_null("/root/DebugDrawer")
		if not drawer or not drawer.is_open():
			_update_game_viewport()
	elif _panel_y >= get_viewport().get_visible_rect().size.y:
		_restore_game_viewport()


func _update_game_viewport() -> void:
	## When the console is open, shrink the game viewport to fit above the console
	## and to the right of the debug drawer. The debug drawer's own viewport logic
	## handles the horizontal shift — we only adjust the vertical scale.
	## NOTE: The debug drawer already manages canvas_transform. We avoid fighting
	## it by only adjusting when the drawer is NOT open. When both are open, the
	## drawer handles horizontal and we add vertical compression.
	var vp: Viewport = get_viewport()
	if not vp:
		return
	var vp_size: Vector2 = vp.get_visible_rect().size
	var console_visible_h: float = maxf(0.0, vp_size.y - _panel_y)
	if console_visible_h < 5.0:
		return

	var game_h: float = vp_size.y - console_visible_h
	if game_h < 100:
		return

	var scale_y: float = game_h / vp_size.y
	var drawer_right: float = _panel_x
	var game_w: float = vp_size.x - drawer_right
	var scale_x: float = game_w / vp_size.x if game_w > 100 else 1.0

	var target_transform := Transform2D()
	target_transform = target_transform.scaled(Vector2(scale_x, scale_y))
	target_transform.origin = Vector2(drawer_right, 0)

	var current: Transform2D = vp.canvas_transform
	vp.canvas_transform = current.interpolate_with(target_transform, 0.15)


func _restore_game_viewport() -> void:
	## Reset viewport when console closes (only if debug drawer isn't also managing it).
	var drawer: Node = get_node_or_null("/root/DebugDrawer")
	if drawer and drawer.is_open():
		return  # Drawer will handle its own transform
	var vp: Viewport = get_viewport()
	if vp:
		vp.canvas_transform = vp.canvas_transform.interpolate_with(Transform2D.IDENTITY, 0.15)


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
				elif ctrl or shift:
					# Ctrl+Backspace / Shift+Backspace: delete word backward
					var p: int = _cursor_pos - 1
					while p > 0 and _current_input[p - 1] == " ":
						p -= 1
					while p > 0 and _current_input[p - 1] != " ":
						p -= 1
					_current_input = _current_input.substr(0, p) + _current_input.substr(_cursor_pos)
					_cursor_pos = p
				elif _cursor_pos > 0:
					_current_input = _current_input.substr(0, _cursor_pos - 1) + _current_input.substr(_cursor_pos)
					_cursor_pos -= 1
				_tab_completions.clear()
				get_viewport().set_input_as_handled()

			KEY_DELETE:
				if _has_selection():
					_delete_selection()
				elif ctrl:
					# Ctrl+Delete: delete word forward
					var p: int = _cursor_pos
					var slen: int = _current_input.length()
					while p < slen and _current_input[p] == " ":
						p += 1
					while p < slen and _current_input[p] != " ":
						p += 1
					_current_input = _current_input.substr(0, _cursor_pos) + _current_input.substr(p)
				elif _cursor_pos < _current_input.length():
					_current_input = _current_input.substr(0, _cursor_pos) + _current_input.substr(_cursor_pos + 1)
				_tab_completions.clear()
				get_viewport().set_input_as_handled()

			KEY_LEFT:
				if ctrl:
					_move_cursor(_word_boundary_left(), shift)
				else:
					_move_cursor(maxi(0, _cursor_pos - 1), shift)
				get_viewport().set_input_as_handled()

			KEY_RIGHT:
				if ctrl:
					_move_cursor(_word_boundary_right(), shift)
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
				if ctrl:
					match event.keycode:
						KEY_A:
							# Ctrl+A: beginning of line (emacs) — or select all if already at start
							if _cursor_pos == 0:
								_select_start = 0
								_cursor_pos = _current_input.length()
							else:
								_move_cursor(0, shift)
							get_viewport().set_input_as_handled()
							return
						KEY_E:
							# Ctrl+E: end of line (emacs)
							_move_cursor(_current_input.length(), shift)
							get_viewport().set_input_as_handled()
							return
						KEY_K:
							# Ctrl+K: kill from cursor to end of line
							_kill_buffer = _current_input.substr(_cursor_pos)
							_current_input = _current_input.substr(0, _cursor_pos)
							_tab_completions.clear()
							get_viewport().set_input_as_handled()
							return
						KEY_U:
							# Ctrl+U: kill from cursor to beginning of line
							_kill_buffer = _current_input.substr(0, _cursor_pos)
							_current_input = _current_input.substr(_cursor_pos)
							_cursor_pos = 0
							_tab_completions.clear()
							get_viewport().set_input_as_handled()
							return
						KEY_Y:
							# Ctrl+Y: yank (paste kill buffer)
							if not _kill_buffer.is_empty():
								if _has_selection():
									_delete_selection()
								_current_input = _current_input.substr(0, _cursor_pos) + _kill_buffer + _current_input.substr(_cursor_pos)
								_cursor_pos += _kill_buffer.length()
								_tab_completions.clear()
							get_viewport().set_input_as_handled()
							return
						KEY_W:
							# Ctrl+W: delete word backward (alt emacs binding)
							if _has_selection():
								_kill_buffer = _get_selected_text()
								_delete_selection()
							else:
								var p: int = _word_boundary_left()
								_kill_buffer = _current_input.substr(p, _cursor_pos - p)
								_current_input = _current_input.substr(0, p) + _current_input.substr(_cursor_pos)
								_cursor_pos = p
							_tab_completions.clear()
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
							else:
								# No selection: cut entire line
								DisplayServer.clipboard_set(_current_input)
								_current_input = ""
								_cursor_pos = 0
							_tab_completions.clear()
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
				# Type character at cursor
				if event.unicode > 0 and event.keycode != KEY_QUOTELEFT and not ctrl:
					if _has_selection():
						_delete_selection()
					var ch: String = char(event.unicode)
					_current_input = _current_input.substr(0, _cursor_pos) + ch + _current_input.substr(_cursor_pos)
					_cursor_pos += 1
					_tab_completions.clear()
					get_viewport().set_input_as_handled()

	# Mouse wheel scrolling (output history)
	if _active and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_scroll_offset = mini(_scroll_offset + 3, maxi(0, _output_lines.size() - 5))
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_scroll_offset = maxi(_scroll_offset - 3, 0)
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


func _word_boundary_left() -> int:
	## Find the position of the start of the previous word.
	var p: int = _cursor_pos - 1
	while p > 0 and _current_input[p - 1] == " ":
		p -= 1
	while p > 0 and _current_input[p - 1] != " ":
		p -= 1
	return maxi(0, p)


func _word_boundary_right() -> int:
	## Find the position past the end of the next word.
	var p: int = _cursor_pos
	var slen: int = _current_input.length()
	while p < slen and _current_input[p] != " ":
		p += 1
	while p < slen and _current_input[p] == " ":
		p += 1
	return p


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
				_update_target_y()
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
	_update_target_y()
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
	_update_target_y()
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
	## Tab autocomplete — cycles through matching commands and known names.
	## Dynamic completions are resolved for specific command prefixes:
	##   run/testload/testsave → test names
	##   suite → suite names
	##   music score → score names
	##   debug on/off/log/nolog/console/both → debug aspect paths
	##   mod/smod → modifier blueprint names
	##   level → level names
	##   unmod/unsmod → active modifier names
	if _current_input.is_empty():
		return

	# Build completions list on first tab press (or after input cleared them)
	if _tab_completions.is_empty():
		var prefix: String = _current_input.to_lower()
		_tab_index = 0

		# -- Dynamic completions for commands with known argument sets --

		# Test names: run/testload/testsave <test_name>
		for test_cmd in ["run ", "testload ", "testsave "]:
			if prefix.begins_with(test_cmd):
				var name_prefix: String = prefix.substr(test_cmd.length())
				for test_name in _get_test_names():
					if test_name.to_lower().begins_with(name_prefix):
						_tab_completions.append(test_cmd.strip_edges() + " " + test_name)
				break

		# Suite names: suite <suite_name>
		if _tab_completions.is_empty() and prefix.begins_with("suite "):
			var name_prefix: String = prefix.substr(6)
			for suite_name in _get_suite_names():
				if suite_name.to_lower().begins_with(name_prefix):
					_tab_completions.append("suite " + suite_name)

		# Music score names: music score <name> / m score <name>
		if _tab_completions.is_empty():
			for score_cmd in ["music score ", "m score "]:
				if prefix.begins_with(score_cmd):
					var name_prefix: String = prefix.substr(score_cmd.length())
					for score_name in _get_score_names():
						if score_name.to_lower().begins_with(name_prefix):
							_tab_completions.append(score_cmd.strip_edges() + " " + score_name)
					break

		# Debug aspect paths: debug on/off/log/nolog/console/both <aspect>
		if _tab_completions.is_empty():
			for dbg_cmd in ["debug on ", "debug off ", "debug log ", "debug nolog ",
							"debug console ", "debug both "]:
				if prefix.begins_with(dbg_cmd):
					var aspect_prefix: String = prefix.substr(dbg_cmd.length())
					for aspect_path in _get_debug_aspect_paths():
						if aspect_path.to_lower().begins_with(aspect_prefix):
							_tab_completions.append(dbg_cmd.strip_edges() + " " + aspect_path)
					break

		# Modifier blueprints: mod <name> / smod <name>
		if _tab_completions.is_empty():
			for mod_cmd in ["mod ", "smod "]:
				if prefix.begins_with(mod_cmd) and not prefix.begins_with("mods"):
					var name_prefix: String = prefix.substr(mod_cmd.length())
					for bp_name in _get_modifier_blueprints():
						if bp_name.to_lower().begins_with(name_prefix):
							_tab_completions.append(mod_cmd.strip_edges() + " " + bp_name)
					break

		# Level names: level <name>
		if _tab_completions.is_empty() and prefix.begins_with("level "):
			var name_prefix: String = prefix.substr(6)
			for level_name in _get_level_names():
				if level_name.to_lower().begins_with(name_prefix):
					_tab_completions.append("level " + level_name)

		# Music layer names with on/off: music layer <name> [on|off]
		if _tab_completions.is_empty():
			for layer_cmd in ["music layer ", "m layer "]:
				if prefix.begins_with(layer_cmd):
					var rest: String = prefix.substr(layer_cmd.length())
					# If they've typed a layer name already, offer on/off
					var layer_names := ["pad", "bass", "drums", "melody"]
					var matched_layer: String = ""
					for ln in layer_names:
						if rest.begins_with(ln + " "):
							matched_layer = ln
							break
					if matched_layer != "":
						var suffix_prefix: String = rest.substr(matched_layer.length() + 1)
						for toggle in ["on", "off"]:
							if toggle.begins_with(suffix_prefix):
								_tab_completions.append(layer_cmd.strip_edges() + " " + matched_layer + " " + toggle)
					else:
						# Complete layer name
						for ln in layer_names:
							if ln.begins_with(rest):
								_tab_completions.append(layer_cmd.strip_edges() + " " + ln)
					break

		# -- Fall back to static command keyword completion --
		if _tab_completions.is_empty():
			for cmd in COMMANDS:
				if cmd.to_lower().begins_with(prefix):
					_tab_completions.append(cmd)

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


func _get_score_names() -> Array[String]:
	## Return all available music score names from MusicManager.
	var names: Array[String] = []
	if MusicManager and MusicManager._all_scores:
		for key in MusicManager._all_scores:
			names.append(key)
	names.sort()
	return names


func _get_debug_aspect_paths() -> Array[String]:
	## Return all registered debug aspect paths.
	return DebugOverlay.get_aspect_paths()


func _get_modifier_blueprints() -> Array[String]:
	## Return modifier blueprint names from data/modifier_blueprints/.
	var names: Array[String] = []
	var dir := DirAccess.open("res://data/modifier_blueprints/")
	if dir:
		dir.list_dir_begin()
		var fname: String = dir.get_next()
		while fname != "":
			if fname.ends_with(".json") and not dir.current_is_dir():
				names.append(fname.replace(".json", ""))
			fname = dir.get_next()
	return names


func _get_level_names() -> Array[String]:
	## Return level names from LevelConfig's known levels.
	var names: Array[String] = []
	# Check bundled levels
	var dir := DirAccess.open("res://data/levels/")
	if dir:
		dir.list_dir_begin()
		var fname: String = dir.get_next()
		while fname != "":
			if fname.ends_with(".json") and not dir.current_is_dir():
				names.append(fname.replace(".json", ""))
			fname = dir.get_next()
	# Check user override levels
	dir = DirAccess.open("user://data/levels/")
	if dir:
		dir.list_dir_begin()
		var fname2: String = dir.get_next()
		while fname2 != "":
			if fname2.ends_with(".json") and not dir.current_is_dir():
				var n: String = fname2.replace(".json", "")
				if n not in names:
					names.append(n)
			fname2 = dir.get_next()
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
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if _panel_y >= vp.y:
		return  # Fully hidden below screen

	var font: Font = ThemeDB.fallback_font
	var px: float = _panel_x  # Left edge (right of debug drawer)
	var pw: float = vp.x - px # Available width
	var ph: float = _panel_height

	# Background
	_panel.draw_rect(Rect2(px, _panel_y, pw, ph), Color(0.05, 0.05, 0.08, 0.95))
	# Top border (console slides up, so top edge is the accent)
	_panel.draw_line(Vector2(px, _panel_y), Vector2(px + pw, _panel_y), Color(0.3, 0.8, 0.3, 0.6), 2.0)

	# Output lines (scrollable)
	var line_h: float = 14.0
	var visible_lines: int = int((ph - 30) / line_h)
	var start_idx: int = maxi(0, _output_lines.size() - visible_lines - _scroll_offset)
	var end_idx: int = mini(start_idx + visible_lines, _output_lines.size())

	var y: float = _panel_y + 10
	for i in range(start_idx, end_idx):
		var entry: Dictionary = _output_lines[i]
		_panel.draw_string(font, Vector2(px + 10, y + 10), entry["text"],
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
		_panel.draw_string(font, Vector2(px + 10, hint_y + 10), hint_text,
			HORIZONTAL_ALIGNMENT_LEFT, pw - 20, 10, Color(0.5, 0.7, 0.5, 0.7))

	# Input line background
	var input_y: float = _panel_y + ph - 20
	_panel.draw_rect(Rect2(px, input_y - 2, pw, 20), Color(0.08, 0.08, 0.1, 0.9))

	# Measure prompt prefix to find pixel position of characters
	var prompt_prefix: String = "> "
	var prefix_w: float = font.get_string_size(prompt_prefix, HORIZONTAL_ALIGNMENT_LEFT, -1, INPUT_FONT_SIZE).x

	# Selection highlight
	if _has_selection():
		var sel_from: int = mini(_select_start, _cursor_pos)
		var sel_to: int   = maxi(_select_start, _cursor_pos)
		var x_from: float = px + 10 + prefix_w + font.get_string_size(
			_current_input.substr(0, sel_from), HORIZONTAL_ALIGNMENT_LEFT, -1, INPUT_FONT_SIZE).x
		var x_to: float = px + 10 + prefix_w + font.get_string_size(
			_current_input.substr(0, sel_to), HORIZONTAL_ALIGNMENT_LEFT, -1, INPUT_FONT_SIZE).x
		_panel.draw_rect(Rect2(x_from, input_y - 1, x_to - x_from, 16), Color(0.3, 0.6, 0.3, 0.4))

	# Input text
	_panel.draw_string(font, Vector2(px + 10, input_y + 12),
		prompt_prefix + _current_input, HORIZONTAL_ALIGNMENT_LEFT, pw - 20, INPUT_FONT_SIZE, Color(0.3, 1.0, 0.3))

	# Cursor (blinking vertical bar at _cursor_pos)
	if int(_cursor_blink * 2) % 2 == 0:
		var cursor_x: float = px + 10 + prefix_w + font.get_string_size(
			_current_input.substr(0, _cursor_pos), HORIZONTAL_ALIGNMENT_LEFT, -1, INPUT_FONT_SIZE).x
		_panel.draw_line(
			Vector2(cursor_x, input_y - 1),
			Vector2(cursor_x, input_y + 14),
			Color(0.3, 1.0, 0.3, 0.9), 1.5)

	# Scroll indicator
	if _scroll_offset > 0:
		_panel.draw_string(font, Vector2(px + pw - 80, _panel_y + 10), "PgUp/PgDn",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.4, 0.4))
