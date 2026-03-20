extends CanvasLayer

## In-game testing menu — accessible via Ctrl+T.
## Shows test suites and reset options. Runs tests via RCON internally.

signal closed

var _active := false
var _selected_idx: int = 0
var _running: bool = false
var _output_lines: Array[String] = []
var _overlay: Control = null

const MENU_ITEMS := [
	{ "label": "Quick Sanity Check", "cmd": "quick" },
	{ "label": "Full Suite (18 scenarios)", "cmd": "all" },
	{ "label": "Baseline (10 scenarios)", "cmd": "baseline" },
	{ "label": "Edge Cases (8 scenarios)", "cmd": "edge" },
	{ "label": "Damage & Weak Spots", "cmd": "damage" },
	{ "label": "Attachments", "cmd": "attachments" },
	{ "label": "Tether", "cmd": "tether" },
	{ "label": "Attack Dummy", "cmd": "attack_dummy" },
	{ "label": "--- ACTIONS ---", "cmd": "" },
	{ "label": "Spawn Monster (standdown)", "cmd": "spawn_standdown" },
	{ "label": "Spawn Monster (active)", "cmd": "spawn_active" },
	{ "label": "Monster Fight! (2 territorial)", "cmd": "monster_fight" },
	{ "label": "Toggle Territorial Mode", "cmd": "territorial" },
	{ "label": "Clear All Enemies", "cmd": "clear" },
	{ "label": "Reset Level", "cmd": "reset" },
	{ "label": "Enable Player Joins", "cmd": "enable_joins" },
	{ "label": "Revive All Players", "cmd": "revive" },
]


func _ready() -> void:
	layer = 95
	_overlay = Control.new()
	_overlay.name = "TestMenuOverlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	visible = false


func toggle() -> void:
	if _active:
		close()
	else:
		open()


func open() -> void:
	_active = true
	visible = true
	_output_lines.clear()


func close() -> void:
	_active = false
	visible = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if not _active:
		return
	if _running:
		return

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				close()
				get_viewport().set_input_as_handled()
			KEY_UP:
				_selected_idx = maxi(_selected_idx - 1, 0)
				# Skip separator
				if MENU_ITEMS[_selected_idx]["cmd"] == "":
					_selected_idx = maxi(_selected_idx - 1, 0)
				get_viewport().set_input_as_handled()
			KEY_DOWN:
				_selected_idx = mini(_selected_idx + 1, MENU_ITEMS.size() - 1)
				if MENU_ITEMS[_selected_idx]["cmd"] == "":
					_selected_idx = mini(_selected_idx + 1, MENU_ITEMS.size() - 1)
				get_viewport().set_input_as_handled()
			KEY_ENTER:
				_execute_selected()
				get_viewport().set_input_as_handled()
			_:
				# Number keys 1-9 for quick access
				var num: int = event.keycode - KEY_0
				if num >= 1 and num <= 9 and num <= MENU_ITEMS.size():
					_selected_idx = num - 1
					_execute_selected()
					get_viewport().set_input_as_handled()

	if _overlay:
		_overlay.queue_redraw()


func _execute_selected() -> void:
	var item: Dictionary = MENU_ITEMS[_selected_idx]
	var cmd: String = item["cmd"]
	if cmd == "":
		return

	_output_lines.clear()
	_output_lines.append("Running: %s..." % item["label"])

	match cmd:
		"quick":
			_run_rcon_sequence([
				"clear", "clearplayers", "",
				"spawn dummy 800 880", "",
				"spawn monster 960 880", "",
				">> Waiting 8s for combat...",
			])
			_run_timed_test(8.0, ["hp", "fps", "ik", "enemies"])
		"spawn_standdown":
			_run_rcon_sequence(["spawn monster 670 520", "standdown on"])
		"spawn_active":
			_run_rcon_sequence(["spawn monster 960 880"])
		"monster_fight":
			_run_rcon_sequence([
				"clear", "clearplayers", "",
				"spawn monster 400 880", "",
				"spawn monster 1500 880", "",
				"territorial on", "",
			])
			_output_lines.append("Two territorial monsters spawned — FIGHT!")
		"territorial":
			_run_rcon_sequence(["territorial"])
		"clear":
			_run_rcon_sequence(["clear"])
		"reset":
			_run_rcon_sequence(["clear", "clearplayers", "enablejoins"])
			_output_lines.append("Level reset. Press controller button to rejoin.")
		"enable_joins":
			_run_rcon_sequence(["enablejoins"])
		"revive":
			_run_rcon_sequence(["revive"])
		_:
			_output_lines.append("Shell test '%s' — run from terminal:" % cmd)
			_output_lines.append("  bash scripts/test_%s.sh" % cmd)

	if _overlay:
		_overlay.queue_redraw()


func _run_rcon_sequence(commands: Array) -> void:
	for cmd_str in commands:
		if cmd_str == "":
			continue
		if cmd_str.begins_with(">>"):
			_output_lines.append(cmd_str.substr(3))
			continue
		var rcon: Node = get_node_or_null("/root/Rcon")
		if rcon and rcon.has_method("_execute"):
			var result: String = rcon._execute(cmd_str)
			_output_lines.append("  %s → %s" % [cmd_str, result])
		else:
			_output_lines.append("  %s → (no RCON)" % cmd_str)


func _run_timed_test(duration: float, check_commands: Array) -> void:
	_running = true
	await get_tree().create_timer(duration).timeout
	_output_lines.append("--- Results ---")
	_run_rcon_sequence(check_commands)
	_running = false
	if _overlay:
		_overlay.queue_redraw()


func _draw_overlay() -> void:
	if not _active:
		return

	var vp: Vector2 = get_viewport().get_visible_rect().size
	var panel_w: float = 500.0
	var panel_h: float = vp.y - 60.0
	var panel_x: float = (vp.x - panel_w) / 2.0
	var panel_y: float = 30.0

	# Background
	_overlay.draw_rect(Rect2(panel_x, panel_y, panel_w, panel_h), Color(0.08, 0.08, 0.1, 0.95))
	_overlay.draw_rect(Rect2(panel_x, panel_y, panel_w, panel_h), Color(0.4, 0.6, 0.3, 0.6), false, 2.0)

	# Title
	_overlay.draw_string(ThemeDB.fallback_font, Vector2(panel_x + 20, panel_y + 28), "TEST MENU (Ctrl+T)", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.4, 1.0, 0.4))

	# Menu items
	var y: float = panel_y + 55
	for i in range(MENU_ITEMS.size()):
		var item: Dictionary = MENU_ITEMS[i]
		var is_selected: bool = (i == _selected_idx)
		var is_separator: bool = (item["cmd"] == "")

		if is_separator:
			_overlay.draw_line(Vector2(panel_x + 20, y - 4), Vector2(panel_x + panel_w - 20, y - 4), Color(0.3, 0.3, 0.3, 0.5), 1.0)
			_overlay.draw_string(ThemeDB.fallback_font, Vector2(panel_x + 20, y + 8), item["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.5, 0.5))
			y += 22
			continue

		if is_selected:
			_overlay.draw_rect(Rect2(panel_x + 10, y - 12, panel_w - 20, 20), Color(0.2, 0.4, 0.2, 0.6))

		var col: Color = Color(1.0, 1.0, 0.8) if is_selected else Color(0.7, 0.7, 0.7)
		var num_str: String = "%d. " % (i + 1) if i < 9 else "   "
		_overlay.draw_string(ThemeDB.fallback_font, Vector2(panel_x + 20, y + 2), num_str + item["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
		y += 22

	# Output area
	y += 10
	_overlay.draw_line(Vector2(panel_x + 10, y), Vector2(panel_x + panel_w - 10, y), Color(0.3, 0.3, 0.3), 1.0)
	y += 15
	var out_col := Color(0.6, 0.9, 0.6)
	for line in _output_lines:
		_overlay.draw_string(ThemeDB.fallback_font, Vector2(panel_x + 20, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, out_col)
		y += 14
		if y > panel_y + panel_h - 20:
			break

	# Running indicator
	if _running:
		_overlay.draw_string(ThemeDB.fallback_font, Vector2(panel_x + 20, panel_y + panel_h - 15), "RUNNING...", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.8, 0.2))

	# Help
	_overlay.draw_string(ThemeDB.fallback_font, Vector2(panel_x + 20, panel_y + panel_h - 2), "Up/Down=select  Enter=run  1-9=quick  Esc=close", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.4, 0.4))
