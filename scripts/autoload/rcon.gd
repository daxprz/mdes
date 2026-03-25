extends Node

## Remote Console — TCP server for external tools to control the game.
## Listens on port 9999. Send text commands, one per line.
## Responds with results.

const PORT := 9999

var _server: TCPServer = null
var _clients: Array = []  # Array of StreamPeerTCP
var _title_layer: CanvasLayer = null
var _test_runner: Node = null
var _zone_manager: Node2D = null
var _leap_checker: Node2D = null
var _test_editor: Node = null

# Notify/prompt state (modal or editor-banner)
var _notify_layer: CanvasLayer = null
var _notify_name: String = ""
var _notify_buttons: Array = []
var _notify_timeout: float = 0.0
var _notify_timer: float = 0.0
var _notify_active: bool = false
var _notify_mode: String = ""  # "blocking" or "editor"
var _notify_dismissed_button: String = ""  # Set when dismissed, read by test runner

# Bounded-leap builder state (populated by `bleap` commands)
var _bleap_defs: Array = []              # Accumulated leap defs from previous `bleap next` calls
var _bleap_plat_a: Dictionary = {}       # {x, y, radius} — current def being built
var _bleap_plat_b: Dictionary = {}       # {x, y, radius}
var _bleap_plans: Array = []             # Array of plan dicts
var _bleap_current_plan: Dictionary = {} # Plan in progress (for multi-step plan building)
var _bleap_min_matched: int = 1

# Test script editor state
var _test_script: Array[String] = []     # Script as flat command list
var _test_script_name: String = ""       # Name of loaded test


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_server = TCPServer.new()
	var err := _server.listen(PORT)
	if err == OK:
		print("RCON: listening on port %d" % PORT)
	else:
		push_warning("RCON: failed to listen on port %d (err=%d)" % [PORT, err])


func _process(_delta: float) -> void:
	# Notify countdown timer
	if _notify_active:
		_notify_timer -= _delta
		if _notify_timer <= 0:
			_cmd_notify_dismiss(_notify_buttons[0] if not _notify_buttons.is_empty() else "OK")
		elif _notify_mode == "blocking" and _notify_layer and _notify_layer.get_child_count() > 0:
			_notify_layer.get_child(0).queue_redraw()

	# Re-apply portal state periodically (catches portals created after rebuild)
	if Engine.get_frames_drawn() % 60 == 0:
		_apply_portal_state()

	# Accept new connections
	if _server.is_connection_available():
		var peer: StreamPeerTCP = _server.take_connection()
		_clients.append(peer)
		print("RCON: client connected")

	# Process each client
	var to_remove: Array[int] = []
	for i in range(_clients.size()):
		var peer: StreamPeerTCP = _clients[i]
		peer.poll()

		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			to_remove.append(i)
			continue

		var available: int = peer.get_available_bytes()
		if available > 0:
			var data: PackedByteArray = peer.get_data(available)[1]
			var text: String = data.get_string_from_utf8().strip_edges()
			for line in text.split("\n"):
				line = line.strip_edges()
				if line.is_empty():
					continue
				var response: String = _execute(line)
				peer.put_data((response + "\n").to_utf8_buffer())

	# Remove disconnected clients (reverse order)
	for i in range(to_remove.size() - 1, -1, -1):
		_clients.remove_at(to_remove[i])


func _execute(command: String) -> String:
	## Execute a command and return the response string.
	var parts: PackedStringArray = command.split(" ", false)
	if parts.is_empty():
		return "ERR: empty command"

	var cmd: String = parts[0].to_lower()

	match cmd:
		"help":
			return "Commands: help, debug [list|on|off|log|...], spawn <monster|dummy|attacker> [x y], tp <x> <y>, tab [n], key <k>, enemies, players, precog, standdown [on|off], run <test>, suite <suite>, tests, etz, daz, zones, clearzones, leaps, clearleaps, status, quit"

		"debug":
			return _cmd_debug(parts)

		"spawn":
			var what: String = parts[1] if parts.size() > 1 else "monster"
			var x: float = float(parts[2]) if parts.size() > 2 else 960.0
			var y: float = float(parts[3]) if parts.size() > 3 else 750.0
			var state: String = ""
			var spawn_scale: float = 1.0
			var spawn_pathing_radius: float = -1.0
			# Parse remaining args: positional state OR key=value pairs
			for pi in range(4, parts.size()):
				var arg: String = parts[pi]
				if arg.contains("="):
					var kv: PackedStringArray = arg.split("=", true, 1)
					if kv[0] == "scale":
						spawn_scale = float(kv[1])
					elif kv[0] == "pathing_radius":
						spawn_pathing_radius = float(kv[1])
				elif state.is_empty():
					state = arg.to_lower()
			return _cmd_spawn(what, x, y, state, spawn_scale, spawn_pathing_radius)

		"tab":
			var count: int = int(parts[1]) if parts.size() > 1 else 1
			for _i in range(count):
				PlayerHUD._debug_cycle_enemy()
			var sel_name: String = "none"
			if is_instance_valid(PlayerHUD.debug_selected_enemy):
				sel_name = PlayerHUD.debug_selected_enemy.name
			return "OK: tab x%d → selected=%s" % [count, sel_name]

		"key":
			if parts.size() < 2:
				return "ERR: usage: key <keyname> (e.g. key m, key ctrl+d)"
			return _cmd_key(parts[1])

		"eval":
			var expr_text: String = command.substr(5).strip_edges()
			return _cmd_eval(expr_text)

		"status":
			return _cmd_status()

		"enemies":
			var enemies: Array = get_tree().get_nodes_in_group("enemies")
			var lines: Array[String] = ["enemies: %d" % enemies.size()]
			for e in enemies:
				lines.append("  %s at (%.0f,%.0f)" % [e.name, e.global_position.x, e.global_position.y])
			return "\n".join(lines)

		"players":
			var players: Array = get_tree().get_nodes_in_group("players")
			var lines: Array[String] = ["players: %d" % players.size()]
			for p in players:
				lines.append("  %s at (%.0f,%.0f)" % [p.name, p.global_position.x, p.global_position.y])
			return "\n".join(lines)

		"tp":
			# Teleport player: tp <x> <y> or tp <player_index> <x> <y>
			if parts.size() < 3:
				return "ERR: usage: tp <x> <y> or tp <player_index> <x> <y>"
			return _cmd_teleport(parts)

		"clearplayers":
			var cleared_p: int = 0
			for p in get_tree().get_nodes_in_group("players"):
				p.queue_free()
				cleared_p += 1
			# Block controller re-joins and clear device tracking
			PlayerManager.join_disabled = true
			PlayerManager._joined_devices.clear()
			return "OK: cleared %d players, joins disabled" % cleared_p

		"enablejoins":
			PlayerManager.join_disabled = false
			PlayerManager._joined_devices.clear()
			return "OK: joins enabled"

		"clear":
			var cleared: int = 0
			for e in get_tree().get_nodes_in_group("enemies"):
				e.queue_free()
				cleared += 1
			# Disable bat/firefly spawning by removing their managers
			var scene: Node = get_tree().current_scene
			if scene:
				# Stop bat respawn timer
				if "_bat_spawn_timer" in scene:
					scene._bat_max = 0
				# Remove firefly manager
				if "_firefly_manager" in scene and is_instance_valid(scene._firefly_manager):
					scene._firefly_manager.queue_free()
					scene._firefly_manager = null
			return "OK: cleared %d enemies, disabled respawning" % cleared

		"precog":
			for e in get_tree().get_nodes_in_group("enemies"):
				if e.has_method("_start_precognition"):
					e._start_precognition()
			return "OK: forced precognition"

		"hp":
			var players: Array = get_tree().get_nodes_in_group("players")
			for p in players:
				var hp: Variant = p.get("health")
				var dmg: Variant = p.get("damage_taken")
				if hp != null:
					return "hp=%s damage_taken=%s" % [str(hp), str(dmg)]
			return "ERR: no player with health"

		"resethp":
			var players: Array = get_tree().get_nodes_in_group("players")
			for p in players:
				if "health" in p:
					p.health = p.max_health
					p.damage_taken = 0
			return "OK: reset HP"

		"revive":
			var revived: int = 0
			# Revive real players (player_side.gd)
			for node in get_tree().get_nodes_in_group("players"):
				if "_is_dead" in node and node._is_dead and node.has_method("_revive"):
					node._revive()
					revived += 1
			# Also check dead players not in "players" group (they remove themselves on death)
			for node in get_tree().current_scene.get_children():
				if "_is_dead" in node and node._is_dead and node.has_method("_revive"):
					node._revive()
					revived += 1
			# Reset HP on all living players too
			for node in get_tree().get_nodes_in_group("players"):
				var p_data: Dictionary = {}
				if "player_index" in node:
					p_data = PlayerManager.get_player(node.player_index)
				if not p_data.is_empty():
					p_data["health"] = p_data.get("max_health", 100)
			return "OK: revived %d, reset all HP" % revived

		"fps":
			return "fps=%.0f" % Engine.get_frames_per_second()

		"ik":
			for e in get_tree().get_nodes_in_group("enemies"):
				if "_ik_score" in e:
					return "ik_now=%.0f ik_avg=%.0f ik_peak=%.0f" % [e._ik_score, e._ik_score_avg, e._ik_score_peak]
			return "ERR: no enemy with IK score"

		"ball":
			for e in get_tree().get_nodes_in_group("enemies"):
				if "_ball_score" in e:
					return "ball_now=%.0f ball_peak=%.0f" % [e._ball_score, e._ball_score_peak]
			return "ERR: no enemy with ball score"

		"thrash":
			for e in get_tree().get_nodes_in_group("enemies"):
				if "_strategy_changes" in e:
					return "thrash=%d plan_attempts=%d/%d" % [e._strategy_changes, e._plan_attempts, e.MAX_PLAN_ATTEMPTS]
			return "ERR: no enemy with thrash score"

		"ikreset":
			for e in get_tree().get_nodes_in_group("enemies"):
				if "_ik_score_peak" in e:
					e._ik_score_peak = 0.0
					e._ik_score_avg = 0.0
					e._ik_score_samples = 0
			return "OK: reset IK scores"

		"title":
			if parts.size() < 2:
				return "ERR: usage: title <text>"
			var title_text: String = command.substr(6).strip_edges()
			_show_title(title_text)
			return "OK: showing '%s'" % title_text

		"score":
			# Show score card: score <title>|<dmg>|<time>|<fps>|<ik>|<thrash>
			if parts.size() < 2:
				return "ERR: usage: score <title>|<dmg>|<time>|<fps>|<ik>|<thrash>"
			var score_text: String = command.substr(6).strip_edges()
			_show_score_card(score_text)
			return "OK: showing score"

		"grid":
			# Show final results grid: grid <line1>|<line2>|...
			if parts.size() < 2:
				return "ERR: usage: grid <line1>|<line2>|..."
			var grid_text: String = command.substr(5).strip_edges()
			_show_results_grid(grid_text)
			return "OK: showing grid"

		"debugdraw":
			for e in get_tree().get_nodes_in_group("enemies"):
				if "debug_draw_enabled" in e:
					e.debug_draw_enabled = not e.debug_draw_enabled
			return "OK: toggled debug draw"

		"test":
			# Automated test: teleport player to various spots, force precog each time
			if parts.size() < 2:
				return "ERR: usage: test precog"
			return _cmd_test(parts[1])

		"partstatus":
			return _cmd_partstatus()

		"partdmg":
			return _cmd_partdmg(parts)

		"weight":
			return _cmd_weight()

		"attach":
			return _cmd_attach(parts)

		"detach":
			return _cmd_detach(parts)

		"dump":
			# Dump skeleton JSON for selected or indexed enemy
			var idx: int = int(parts[1]) if parts.size() > 1 else 0
			var enemies: Array = get_tree().get_nodes_in_group("enemies")
			if idx >= enemies.size():
				return "ERR: enemy %d not found (have %d)" % [idx, enemies.size()]
			var trigger_name: String = parts[2] if parts.size() > 2 else "rcon"
			var data: Dictionary = PlayerHUD.dump_entity_skeleton(enemies[idx], trigger_name)
			if data.is_empty():
				return "ERR: dump failed"
			return JSON.stringify(data, "\t")

		"splay":
			return _cmd_splay(parts)

		"chaindump":
			return _cmd_chaindump()

		"chain":
			return _cmd_chain(parts)

		"tether":
			return _cmd_tether(parts)

		"territorial":
			var enemies: Array = get_tree().get_nodes_in_group("enemies")
			var count: int = 0
			var new_state: Variant = null
			if parts.size() > 1:
				match parts[1].to_lower():
					"on": new_state = true
					"off": new_state = false
			for e in enemies:
				if "territorial" in e:
					if new_state != null:
						e.territorial = new_state as bool
					else:
						e.territorial = not e.territorial
					count += 1
			if count == 0:
				return "ERR: no monsters with territorial support"
			var state_str: String = str(enemies[0].territorial) if "territorial" in enemies[0] else "?"
			return "OK: territorial=%s on %d monsters" % [state_str, count]

		"portal":
			# portal on|off — enable/disable portal transition (persists across rebuilds)
			var enable: bool = true
			if parts.size() > 1 and parts[1].to_lower() == "off":
				enable = false
			# Store as meta on the scene so it persists across rebuilds
			get_tree().current_scene.set_meta("portal_disabled", not enable)
			_apply_portal_state()
			return "OK: portal %s" % ("enabled" if enable else "disabled")

		"standdown":
			return _cmd_standdown(parts)

		"attacker":
			return _cmd_attacker(parts)

		"run":
			if parts.size() < 2:
				return "ERR: usage: run <test_name> [key=value ...]"
			var editor: Node = _ensure_test_editor()
			if editor:
				var override_vars: Dictionary = {"owait": "0"}
				for pi in range(2, parts.size()):
					var eq := parts[pi].find("=")
					if eq > 0:
						override_vars[parts[pi].substr(0, eq)] = parts[pi].substr(eq + 1)
				editor._test_override_vars = override_vars
				editor._load_test(parts[1])
				editor.call_deferred("_run_test")
				return "OK: running test '%s' in editor (%s)" % [parts[1], str(override_vars)]
			return "ERR: failed to open test editor"

		"suite":
			if parts.size() < 2:
				return "ERR: usage: suite <suite_name> [key=value ...] [skip test1 test2 ...]"
			var editor: Node = _ensure_test_editor()
			if editor:
				# Parse optional key=value args and skip list
				var override_vars: Dictionary = {"owait": "0"}  # Default for RCON
				var skip_tests: Array[String] = []
				var parsing_skip: bool = false
				for pi in range(2, parts.size()):
					if parts[pi] == "skip":
						parsing_skip = true
						continue
					if parsing_skip:
						skip_tests.append(parts[pi])
					else:
						var eq := parts[pi].find("=")
						if eq > 0:
							override_vars[parts[pi].substr(0, eq)] = parts[pi].substr(eq + 1)
				editor._test_override_vars = override_vars
				editor.run_suite(parts[1], skip_tests)
				var skip_str: String = " skip=%s" % str(skip_tests) if not skip_tests.is_empty() else ""
				return "OK: running suite '%s' in editor (%s)%s" % [parts[1], str(override_vars), skip_str]
			return "ERR: failed to open test editor"

		"tests":
			return _cmd_list_tests()

		"etz":
			# etz <id> <x> <y> <radius> [entity_id]
			if parts.size() < 5:
				return "ERR: usage: etz <id> <x> <y> <radius> [entity_id]"
			var eid: String = parts[5] if parts.size() > 5 else ""
			_ensure_zone_manager()
			_zone_manager.add_etz(int(parts[1]), Vector2(float(parts[2]), float(parts[3])), float(parts[4]), eid)
			return "OK: added ETZ-%s at (%.0f,%.0f) r=%.0f" % [parts[1], float(parts[2]), float(parts[3]), float(parts[4])]

		"daz":
			# daz <id> <x> <y> <radius> [entity_id]
			if parts.size() < 5:
				return "ERR: usage: daz <id> <x> <y> <radius> [entity_id]"
			var eid: String = parts[5] if parts.size() > 5 else ""
			_ensure_zone_manager()
			_zone_manager.add_daz(int(parts[1]), Vector2(float(parts[2]), float(parts[3])), float(parts[4]), eid)
			return "OK: added DAZ-%s at (%.0f,%.0f) r=%.0f" % [parts[1], float(parts[2]), float(parts[3]), float(parts[4])]

		"zones":
			if _zone_manager and is_instance_valid(_zone_manager):
				return _zone_manager.get_status()
			return "zones: 0"

		"clearzones":
			if _zone_manager and is_instance_valid(_zone_manager):
				_zone_manager.clear_zones()
			else:
				_zone_manager = null  # Reset stale reference
			return "OK: zones cleared"

		"leaps":
			# Return a summary of all planned hop edges from every monster
			var _leap_lines: Array[String] = []
			for _le in get_tree().get_nodes_in_group("enemies"):
				if _le.has_method("get_leap_graph"):
					var _graph: Array = _le.get_leap_graph()
					_leap_lines.append("  %s: %d edges" % [_le.name, _graph.size()])
					for _edge in _graph:
						_leap_lines.append("    from=(%.0f,%.0f) arrival=(%.0f,%.0f) vel=(%.0f,%.0f)" % [
							_edge["from_pos"].x, _edge["from_pos"].y,
							_edge["arrival"].x, _edge["arrival"].y,
							_edge["launch_vel"].x, _edge["launch_vel"].y])
			if _leap_lines.is_empty():
				return "leaps: 0 (no monsters with leap graph)"
			return "leaps: " + str(get_tree().get_nodes_in_group("enemies").size()) + "\n" + "\n".join(_leap_lines)

		"clearleaps":
			if _leap_checker and is_instance_valid(_leap_checker):
				_leap_checker.clear_checks()
			else:
				_leap_checker = null
			return "OK: leap checks cleared"

		"bleap":
			return _cmd_bleap(parts, command)

		"testload":
			if parts.size() < 2:
				return "ERR: usage: testload <test_name>"
			return _cmd_testload(parts[1])

		"testshow":
			if _test_script.is_empty():
				return "ERR: no test loaded — use testload <name>"
			var ls: Array[String] = ["Test: %s (%d lines)" % [_test_script_name, _test_script.size()]]
			for i in range(_test_script.size()):
				ls.append("  %2d: %s" % [i + 1, _test_script[i]])
			return "\n".join(ls)

		"testedit":
			# testedit <n> <new command...>
			if parts.size() < 3:
				return "ERR: usage: testedit <line_number> <new command>"
			var ln: int = int(parts[1]) - 1
			if ln < 0 or ln >= _test_script.size():
				return "ERR: line %d out of range (1..%d)" % [ln + 1, _test_script.size()]
			# Rebuild rest of command after the line number
			var new_cmd: String = command.substr(command.find(parts[1]) + parts[1].length()).strip_edges()
			_test_script[ln] = new_cmd
			return "OK: line %d = \"%s\"" % [ln + 1, new_cmd]

		"testinsert":
			# testinsert <n> <command> — insert before line n
			if parts.size() < 3:
				return "ERR: usage: testinsert <line_number> <command>"
			var ln: int = int(parts[1]) - 1
			ln = clamp(ln, 0, _test_script.size())
			var new_cmd: String = command.substr(command.find(parts[1]) + parts[1].length()).strip_edges()
			_test_script.insert(ln, new_cmd)
			return "OK: inserted at line %d: \"%s\"" % [ln + 1, new_cmd]

		"testdelete":
			if parts.size() < 2:
				return "ERR: usage: testdelete <line_number>"
			var ln: int = int(parts[1]) - 1
			if ln < 0 or ln >= _test_script.size():
				return "ERR: line %d out of range" % [ln + 1]
			var removed: String = _test_script[ln]
			_test_script.remove_at(ln)
			return "OK: deleted line %d: \"%s\"" % [ln + 1, removed]

		"testrun":
			if _test_script.is_empty():
				return "ERR: no test loaded — use testload <name>"
			_ensure_test_runner()
			if _test_runner:
				_test_runner.run_test_script(_test_script, _test_script_name, null)
				return "OK: running script '%s' (%d lines)" % [_test_script_name, _test_script.size()]
			return "ERR: failed to create test runner"

		"testsave":
			var save_name: String = parts[1] if parts.size() > 1 else _test_script_name
			if save_name.is_empty():
				return "ERR: no name — use testsave <name>"
			return _cmd_testsave(save_name)

		"testnew":
			if parts.size() < 2:
				return "ERR: usage: testnew <name>"
			_test_script_name = parts[1]
			_test_script = ["# New test: " + parts[1], "clear", "portal off", "clearplayers", "clearzones"]
			return "OK: new test '%s' — use testshow, testedit, testrun, testsave" % parts[1]

		"notify":
			# notify <name> <message> <buttons_json> <timeout> [blocking|editor]
			# e.g.: notify observations DONE ["OK"] 600 editor
			if parts.size() < 5:
				return "ERR: usage: notify <name> <message> <buttons_json> <timeout> [blocking|editor]"
			var notify_name: String = parts[1]
			var notify_msg: String = parts[2].replace("\"", "")
			var btn_start: int = command.find("[")
			var btn_end: int = command.find("]", btn_start)
			var buttons_str: String = command.substr(btn_start, btn_end - btn_start + 1) if btn_start >= 0 else '["OK"]'
			var last_token: String = parts[parts.size() - 1].to_lower()
			var mode: String = "editor"  # Default: non-blocking editor banner
			var timeout_val: float = 0.0
			if last_token == "blocking" or last_token == "editor":
				mode = last_token
				timeout_val = float(parts[parts.size() - 2]) if parts.size() >= 6 else 600.0
			else:
				timeout_val = float(last_token)
			return _cmd_notify(notify_name, notify_msg, buttons_str, timeout_val, mode)

		"notify_dismiss":
			if parts.size() < 2:
				return "ERR: usage: notify_dismiss <button_label>"
			return _cmd_notify_dismiss(parts[1].replace("\"", ""))

		"emit":
			# emit <event_name> <value>
			if parts.size() < 3:
				return "ERR: usage: emit <event_name> <value>"
			return _cmd_emit(parts[1], parts[2])

		"quit":
			get_tree().quit()
			return "OK: quitting"

		_:
			return "ERR: unknown command '%s'. Try 'help'" % cmd


func _cmd_teleport(parts: PackedStringArray) -> String:
	var players: Array = get_tree().get_nodes_in_group("players")
	var pi: int = 0
	var x: float
	var y: float

	if parts.size() >= 4:
		pi = int(parts[1])
		x = float(parts[2])
		y = float(parts[3])
	else:
		x = float(parts[1])
		y = float(parts[2])

	# Find by index or just grab the nth player in the group
	if pi < players.size():
		var p: Node = players[pi]
		if p is CharacterBody2D:
			p.global_position = Vector2(x, y)
			p.velocity = Vector2.ZERO
			return "OK: teleported %s to (%.0f, %.0f)" % [p.name, x, y]

	return "ERR: player %d not found (have %d)" % [pi, players.size()]


func _cmd_test(what: String) -> String:
	match what:
		"precog":
			# Automated precog test: cycles through positions
			# Results are printed to Godot log
			var positions := [
				Vector2(960, 520),   # Upper center (on P3/P4 level)
				Vector2(400, 740),   # On P1
				Vector2(1400, 740),  # On P2
				Vector2(200, 880),   # Floor left
				Vector2(1600, 880),  # Floor right
				Vector2(670, 520),   # On P3
				Vector2(1250, 520),  # On P4
			]
			# Teleport to first position, force precog
			# Subsequent positions handled by the game loop
			var players: Array = get_tree().get_nodes_in_group("players")
			if players.is_empty():
				return "ERR: no players"
			var p: Node = players[0]
			p.global_position = positions[0]
			p.velocity = Vector2.ZERO
			for e in get_tree().get_nodes_in_group("enemies"):
				if e.has_method("_start_precognition"):
					e._start_precognition()
			return "OK: test precog started — P0 at (%.0f, %.0f)" % [positions[0].x, positions[0].y]
		_:
			return "ERR: unknown test '%s'" % what


func _cmd_spawn(what: String, x: float = 960.0, y: float = 750.0, state: String = "", spawn_scale: float = 1.0, spawn_pathing_radius: float = -1.0) -> String:
	var scene_root := get_tree().current_scene
	if not scene_root:
		return "ERR: no current scene"

	var container: Node = scene_root.get_node_or_null("Players")
	if not container:
		container = scene_root

	match what:
		"monster":
			var script := load("res://scripts/enemies/quadruped_monster.gd")
			var monster := CharacterBody2D.new()
			monster.set_script(script)
			# Set scale and pathing radius BEFORE _ready() so _init_skeleton() uses them
			monster.creature_scale = spawn_scale
			monster.pathing_radius = spawn_pathing_radius
			monster.global_position = Vector2(x, y)
			var monster_count: int = get_tree().get_nodes_in_group("enemies").size()
			monster.entity_id = "monster_%d" % monster_count
			container.add_child(monster)
			# Apply optional initial state
			if state == "standdown":
				monster._standdown = true
			var scale_str: String = " scale=%.1f" % spawn_scale if spawn_scale != 1.0 else ""
			var state_str: String = " (%s)" % state if not state.is_empty() else ""
			return "OK: spawned monster '%s' at (%.0f, %.0f)%s%s" % [monster.entity_id, x, y, state_str, scale_str]

		"dummy":
			# Fake player — a simple CharacterBody2D in the "players" group
			# that the monster can target. No controller needed.
			var dummy := CharacterBody2D.new()
			var dummy_count: int = get_tree().get_nodes_in_group("players").size()
			dummy.name = "DummyPlayer_%d" % dummy_count
			dummy.add_to_group("players")
			dummy.global_position = Vector2(x, y)
			dummy.set("player_index", 0)
			dummy.collision_layer = 2  # Player layer
			dummy.collision_mask = 1   # World
			# Collision shape so it stands on platforms
			var col := CollisionShape2D.new()
			var shape := CapsuleShape2D.new()
			shape.radius = 8.0
			shape.height = 30.0
			col.shape = shape
			dummy.add_child(col)
			# Gravity
			var gravity_script := GDScript.new()
			gravity_script.source_code = """extends CharacterBody2D

var player_index: int = 0
var entity_id: String = ""
var health: int = 1000
var max_health: int = 1000
var damage_taken: int = 0

func _physics_process(delta: float) -> void:
	velocity.y += 600.0 * delta
	move_and_slide()

func _draw() -> void:
	draw_circle(Vector2.ZERO, 10.0, Color(0.2, 0.8, 0.2, 0.8))
	draw_circle(Vector2(0, -14), 7.0, Color(0.2, 0.8, 0.2, 0.8))
	var hp_text: String = "HP:%d DMG:%d" % [health, damage_taken]
	draw_string(ThemeDB.fallback_font, Vector2(-20, -26), hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.GREEN)

func take_damage(amount: int, _source: int = -1) -> void:
	damage_taken += amount
	health -= amount
	if health < 0:
		health = 0
	queue_redraw()
"""
			gravity_script.reload()
			dummy.set_script(gravity_script)
			dummy.entity_id = "dummy_%d" % dummy_count
			container.add_child(dummy)
			dummy.queue_redraw()
			return "OK: spawned dummy '%s' at (%.0f, %.0f)" % [dummy.entity_id, x, y]

		"attacker":
			var script := load("res://scripts/testing/attack_dummy.gd")
			var attacker := CharacterBody2D.new()
			attacker.set_script(script)
			attacker.name = "AttackDummy"
			attacker.global_position = Vector2(x, y)
			container.add_child(attacker)
			return "OK: spawned attacker at (%.0f, %.0f)" % [x, y]

		_:
			return "ERR: unknown spawn type '%s'. Try: monster, dummy, attacker" % what


func _cmd_key(key_str: String) -> String:
	## Simulate a key press via InputEventKey.
	var event := InputEventKey.new()
	event.pressed = true

	if key_str.contains("+"):
		var mods: PackedStringArray = key_str.split("+")
		for i in range(mods.size() - 1):
			match mods[i].to_lower():
				"ctrl": event.ctrl_pressed = true
				"shift": event.shift_pressed = true
				"alt": event.alt_pressed = true
		key_str = mods[mods.size() - 1]

	var keycode: int = _key_name_to_code(key_str.to_lower())
	if keycode == 0:
		return "ERR: unknown key '%s'" % key_str

	event.keycode = keycode
	Input.parse_input_event(event)

	# Also send key up
	var up := InputEventKey.new()
	up.pressed = false
	up.keycode = keycode
	up.ctrl_pressed = event.ctrl_pressed
	up.shift_pressed = event.shift_pressed
	up.alt_pressed = event.alt_pressed
	Input.parse_input_event(up)

	return "OK: key %s" % key_str


func _key_name_to_code(name: String) -> int:
	match name:
		"a": return KEY_A
		"b": return KEY_B
		"c": return KEY_C
		"d": return KEY_D
		"e": return KEY_E
		"f": return KEY_F
		"g": return KEY_G
		"m": return KEY_M
		"n": return KEY_N
		"s": return KEY_S
		"r": return KEY_R
		"tab": return KEY_TAB
		"space": return KEY_SPACE
		"enter": return KEY_ENTER
		"escape": return KEY_ESCAPE
		"up": return KEY_UP
		"down": return KEY_DOWN
		"left": return KEY_LEFT
		"right": return KEY_RIGHT
		"delete": return KEY_DELETE
		"backspace": return KEY_BACKSPACE
		_: return 0


func _cmd_eval(expr_text: String) -> String:
	var expression := Expression.new()
	var err := expression.parse(expr_text)
	if err != OK:
		return "ERR: parse: %s" % expression.get_error_text()
	var result: Variant = expression.execute()
	if expression.has_execute_failed():
		return "ERR: exec: %s" % expression.get_error_text()
	return "OK: %s" % str(result)


func _cmd_status() -> String:
	var enemies: int = get_tree().get_nodes_in_group("enemies").size()
	var players: int = get_tree().get_nodes_in_group("players").size()
	var debug: bool = PlayerHUD._debug_mode
	var sel: String = "none"
	if is_instance_valid(PlayerHUD.debug_selected_enemy):
		sel = PlayerHUD.debug_selected_enemy.name
	return "status: debug=%s enemies=%d players=%d selected=%s" % [str(debug), enemies, players, sel]


func _color_for_value(value: int, good: int, warn: int) -> Color:
	## Green if <= good, yellow if <= warn, red otherwise
	if value <= good:
		return Color(0.2, 1.0, 0.3)
	elif value <= warn:
		return Color(1.0, 0.9, 0.2)
	else:
		return Color(1.0, 0.3, 0.2)


func _show_score_card(data: String) -> void:
	## Show score card below the title. Format: title|dmg|time|fps|ik|thrash
	var fields: PackedStringArray = data.split("|")
	if fields.size() < 6:
		return

	if not _title_layer:
		_title_layer = CanvasLayer.new()
		_title_layer.layer = 100
		add_child(_title_layer)

	var title: String = fields[0]
	var dmg: int = int(fields[1])
	var time_str: String = fields[2]
	var fps: int = int(fields[3])
	var ik: int = int(fields[4])
	var thrash: int = int(fields[5])

	# Title
	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 36)
	title_lbl.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
	title_lbl.anchor_left = 0.5; title_lbl.anchor_right = 0.5
	title_lbl.anchor_top = 0.2; title_lbl.anchor_bottom = 0.2
	title_lbl.offset_left = -300; title_lbl.offset_right = 300
	_title_layer.add_child(title_lbl)

	# Score rows
	var rows := [
		["Damage", str(dmg), _color_for_value(1000 - dmg, 0, 500)],
		["Time to Hit", time_str, Color(0.2, 1.0, 0.3) if time_str != "NONE" else Color(1.0, 0.3, 0.2)],
		["Min FPS", str(fps), _color_for_value(60 - fps, 0, 20)],
		["IK Quality", str(ik), _color_for_value(ik, 100, 500)],
		["Thrash", str(thrash), _color_for_value(thrash, 5, 15)],
	]

	var container := VBoxContainer.new()
	container.anchor_left = 0.5; container.anchor_right = 0.5
	container.anchor_top = 0.32; container.anchor_bottom = 0.32
	container.offset_left = -200; container.offset_right = 200
	_title_layer.add_child(container)

	for row in rows:
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 20)
		var name_lbl := Label.new()
		name_lbl.text = row[0]
		name_lbl.add_theme_font_size_override("font_size", 20)
		name_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		name_lbl.custom_minimum_size.x = 140
		hbox.add_child(name_lbl)
		var val_lbl := Label.new()
		val_lbl.text = row[1]
		val_lbl.add_theme_font_size_override("font_size", 20)
		val_lbl.add_theme_color_override("font_color", row[2])
		hbox.add_child(val_lbl)
		container.add_child(hbox)

	# Fade out after 3 seconds
	var tween := title_lbl.create_tween()
	tween.tween_interval(2.0)
	tween.tween_property(title_lbl, "modulate:a", 0.0, 1.0)
	tween.parallel().tween_property(container, "modulate:a", 0.0, 1.0)
	tween.tween_callback(title_lbl.queue_free)
	tween.tween_callback(container.queue_free)


func _show_results_grid(data: String) -> void:
	## Show final results grid. Format: line1|line2|line3|...
	if not _title_layer:
		_title_layer = CanvasLayer.new()
		_title_layer.layer = 100
		add_child(_title_layer)

	var lines: PackedStringArray = data.split("|")

	var container := VBoxContainer.new()
	container.anchor_left = 0.5; container.anchor_right = 0.5
	container.anchor_top = 0.1; container.anchor_bottom = 0.1
	container.offset_left = -350; container.offset_right = 350
	_title_layer.add_child(container)

	for line in lines:
		var lbl := Label.new()
		lbl.text = line
		lbl.add_theme_font_size_override("font_size", 16)
		if line.begins_with("===") or line.begins_with("TOTAL"):
			lbl.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
			lbl.add_theme_font_size_override("font_size", 20)
		else:
			lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		container.add_child(lbl)

	# Stay visible until clicked or 30 seconds
	var tween := container.create_tween()
	tween.tween_interval(30.0)
	tween.tween_property(container, "modulate:a", 0.0, 2.0)
	tween.tween_callback(container.queue_free)
	# Click anywhere to dismiss early
	container.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			container.queue_free()
	)
	container.mouse_filter = Control.MOUSE_FILTER_STOP


func _show_title(text: String) -> void:
	## Show a big title on screen: hold 1s, fade out 1s.
	if not _title_layer:
		_title_layer = CanvasLayer.new()
		_title_layer.layer = 100
		add_child(_title_layer)

	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 48)
	lbl.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	lbl.add_theme_constant_override("shadow_offset_x", 2)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.anchors_preset = Control.PRESET_CENTER
	lbl.anchor_left = 0.5
	lbl.anchor_right = 0.5
	lbl.anchor_top = 0.3
	lbl.anchor_bottom = 0.3
	lbl.offset_left = -400
	lbl.offset_right = 400
	lbl.offset_top = -30
	lbl.offset_bottom = 30
	_title_layer.add_child(lbl)

	var tween := lbl.create_tween()
	tween.tween_interval(1.0)
	tween.tween_property(lbl, "modulate:a", 0.0, 1.0)
	tween.tween_callback(lbl.queue_free)


func _cmd_partstatus() -> String:
	## Print all part health/damage states for the first quadruped monster.
	for e in get_tree().get_nodes_in_group("enemies"):
		if "_part_health" in e:
			var lines: Array[String] = ["partstatus:"]
			var ph: Dictionary = e._part_health
			for part_name in ph:
				var p: Dictionary = ph[part_name]
				var state_name: String = "NONE"
				match p.get("damage_state", 0):
					1: state_name = "MEDIUM"
					2: state_name = "HIGH"
				lines.append("  %s: %d/%d (%s)" % [part_name, p["current_hp"], p["max_hp"], state_name])
			if "_grab_disabled" in e:
				lines.append("  grab_disabled=%s" % str(e._grab_disabled))
			if "_torso_bleeding" in e:
				lines.append("  torso_bleeding=%s" % str(e._torso_bleeding))
			lines.append("  slash_mult=%.2f leap_mult=%.2f" % [e.get_slash_damage_multiplier(), e.get_leap_speed_multiplier()])
			return "\n".join(lines)
	return "ERR: no enemy with part health"


func _cmd_partdmg(parts: PackedStringArray) -> String:
	## Deal damage to a specific part: partdmg <part> <amount>
	if parts.size() < 3:
		return "ERR: usage: partdmg <part_name> <amount>"
	var part_name: String = parts[1]
	var amount: int = int(parts[2])
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.has_method("take_part_damage"):
			e.take_part_damage(part_name, amount)
			return "OK: dealt %d damage to %s" % [amount, part_name]
	return "ERR: no enemy with take_part_damage"


func _cmd_weight() -> String:
	## Print segment weights and attached forces.
	for e in get_tree().get_nodes_in_group("enemies"):
		if "SEGMENT_WEIGHTS" in e:
			var lines: Array[String] = ["weights (total=%.0f):" % e.get_total_weight()]
			for seg_name in e.SEGMENT_WEIGHTS:
				lines.append("  %s: %.0f" % [seg_name, e.SEGMENT_WEIGHTS[seg_name]])
			if "_attach_forces" in e and not e._attach_forces.is_empty():
				lines.append("forces:")
				for point_name in e._attach_forces:
					var f: Vector2 = e._attach_forces[point_name]
					lines.append("  %s: (%.1f, %.1f)" % [point_name, f.x, f.y])
			else:
				lines.append("forces: none")
			if "_attachments" in e:
				var total_items: int = 0
				for point_name in e._attachments:
					total_items += e._attachments[point_name].size()
				lines.append("attached_items: %d" % total_items)
			return "\n".join(lines)
	return "ERR: no enemy with weight data"


func _cmd_attach(parts: PackedStringArray) -> String:
	## Attach a test item: attach balloon <point>
	if parts.size() < 3:
		return "ERR: usage: attach balloon <point_name>"
	var item_type: String = parts[1].to_lower()
	var point_name: String = parts[2]

	if item_type != "balloon":
		return "ERR: only 'balloon' supported. Usage: attach balloon <point>"

	for e in get_tree().get_nodes_in_group("enemies"):
		if e.has_method("attach_item") and "_attachments" in e:
			if not e._attachments.has(point_name):
				return "ERR: unknown attachment point '%s'. Try: head, tail_tip, shoulders, waist" % point_name
			# Spawn a balloon dart and attach it
			var dart_script := load("res://scripts/characters/balloon_dart.gd")
			var dart := Node2D.new()
			dart.set_script(dart_script)
			var attach_pos: Vector2 = e.get_attach_world_position(point_name)
			dart.global_position = attach_pos
			dart.dart_direction = Vector2.UP
			dart.owner_index = -1
			var container: Node = get_tree().current_scene
			container.add_child(dart)
			# Force-attach: skip dart flight, go straight to inflating
			dart._dart_active = false
			dart._attached_to = e
			dart._balloon_inflating = true
			dart._balloon_timer = 0.0
			dart._dart_pos = attach_pos
			# Register with attachment system
			e.attach_item(point_name, dart)
			return "OK: attached balloon to %s" % point_name
	return "ERR: no enemy with attachment points"


func _cmd_detach(parts: PackedStringArray) -> String:
	## Detach all items from a point: detach <point>
	if parts.size() < 2:
		return "ERR: usage: detach <point_name>"
	var point_name: String = parts[1]

	for e in get_tree().get_nodes_in_group("enemies"):
		if "_attachments" in e and e._attachments.has(point_name):
			var items: Array = e._attachments[point_name]
			var count: int = items.size()
			for item in items:
				if is_instance_valid(item):
					item.queue_free()
			items.clear()
			return "OK: detached %d items from %s" % [count, point_name]
	return "ERR: no enemy with attachment point '%s'" % point_name


func _cmd_splay(parts: PackedStringArray) -> String:
	if parts.size() < 2:
		return "ERR: usage: splay <list|spawn|clear|status>"

	var subcmd: String = parts[1].to_lower()
	# Find the SplayManager autoload or instance
	var mgr: Node = get_node_or_null("/root/SplayManager")
	if not mgr:
		# Try to find it as a child of current scene
		for child in get_tree().current_scene.get_children():
			if child.name == "SplayManager":
				mgr = child
				break
		if not mgr:
			# Create one on the fly
			var script: GDScript = load("res://scripts/systems/splay_manager.gd")
			mgr = Node.new()
			mgr.name = "SplayManager"
			mgr.set_script(script)
			get_tree().current_scene.add_child(mgr)

	match subcmd:
		"list":
			var names: Array[String] = mgr.get_all_pose_names()
			if names.is_empty():
				return "splay poses: (none)"
			return "splay poses: %s" % ", ".join(names)

		"spawn":
			# splay spawn <pose> [x y] [rotation] [behavior] [scale=N]
			if parts.size() < 3:
				return "ERR: usage: splay spawn <pose> [x y] [rotation] [behavior] [scale=N]"
			var pose_name: String = parts[2]
			var x: float = float(parts[3]) if parts.size() > 3 else 960.0
			var y: float = float(parts[4]) if parts.size() > 4 else 500.0
			var rot: float = float(parts[5]) if parts.size() > 5 else 0.0
			var behavior: String = parts[6] if parts.size() > 6 else "asleep"
			# Parse key=value args from remaining parts
			var splay_scale: float = -1.0
			for pi in range(3, parts.size()):
				if parts[pi].contains("="):
					var kv: PackedStringArray = parts[pi].split("=", true, 1)
					if kv[0] == "scale":
						splay_scale = float(kv[1])
			mgr.spawn_splay(pose_name, Vector2(x, y), rot, behavior, splay_scale)
			var scale_str: String = " scale=%.1f" % splay_scale if splay_scale > 0 else ""
			return "OK: spawning splay '%s' at (%.0f,%.0f) rot=%.0f behavior=%s%s" % [pose_name, x, y, rot, behavior, scale_str]

		"clear":
			var count: int = mgr.clear_all_splays()
			return "OK: cleared %d splay instances" % count

		"status":
			var lines: Array[String] = mgr.get_splay_status()
			return "\n".join(lines)

		_:
			return "ERR: unknown splay subcommand '%s'. Try: list, spawn, clear, status" % subcmd


func _cmd_chaindump() -> String:
	## Dump detailed state of all chains: every point position and distances.
	var chains: Array = get_tree().get_nodes_in_group("chains")
	if chains.is_empty():
		return "chains: 0"
	var lines: Array[String] = ["chains: %d" % chains.size()]
	for ci in range(chains.size()):
		var c: Node2D = chains[ci]
		lines.append("=== Chain %d: %d pts, target_len=%.1f, link_len=%.1f, hp=%d/%d ===" % [
			ci, c._point_count, c.target_length, c._link_len, c.current_hp, c.CHAIN_MAX_HP])
		# Dump points with distances
		for i in range(c._points.size()):
			var pt: Vector2 = c._points[i]
			var dist_str: String = ""
			if i > 0:
				var dist: float = c._points[i - 1].distance_to(pt)
				var pct: float = (dist / c._link_len - 1.0) * 100
				if absf(pct) > 5:
					dist_str = " dist=%.1f (%.0f%%)" % [dist, pct]
				else:
					dist_str = " dist=%.1f" % dist
			var label: String = ""
			if i == 0:
				label = " [ANCHOR_A]"
			elif i == c._point_count - 1:
				label = " [ANCHOR_B]"
			lines.append("  pt[%d]: (%.1f,%.1f)%s%s" % [i, pt.x, pt.y, dist_str, label])
	return "\n".join(lines)


func _cmd_chain(parts: PackedStringArray) -> String:
	## Chain commands — same syntax as tether but creates chains instead.
	if parts.size() < 2:
		return "ERR: usage: chain <enemy idx point floor [len]|status|cut>"
	var subcmd: String = parts[1].to_lower()
	match subcmd:
		"status":
			var chains: Array = get_tree().get_nodes_in_group("chains")
			if chains.is_empty():
				return "chains: 0"
			var lines: Array[String] = ["chains: %d" % chains.size()]
			var ChainScript: GDScript = load("res://scripts/systems/chain.gd")
			for i in range(chains.size()):
				var c: Node2D = chains[i]
				var pa: Vector2 = c._get_anchor_world_pos(c.anchor_a)
				var pb: Vector2 = c._get_anchor_world_pos(c.anchor_b)
				lines.append("  [%d] len=%.0f/%.0f tension=%.2f hp=%d/%d" % [
					i, pa.distance_to(pb), c.target_length, c.get_tension(), c.current_hp, c.CHAIN_MAX_HP])
			return "\n".join(lines)
		"cut":
			var chains: Array = get_tree().get_nodes_in_group("chains")
			var count: int = chains.size()
			for c in chains:
				c.sever()
			return "OK: severed %d chains" % count
		_:
			# chain <idx> <point> floor [len]
			if parts.size() >= 4 and parts[3].to_lower() == "floor":
				var idx: int = int(parts[1])
				var point: String = parts[2]
				var length: float = 100.0
				if parts.size() > 4:
					length = float(parts[4])
				return _create_chain_enemy_floor(idx, point, length)
			# chain <idx> <point> wall <x> <y> [len]
			elif parts.size() >= 6 and parts[3].to_lower() == "wall":
				var idx: int = int(parts[1])
				var point: String = parts[2]
				var wall_x: float = float(parts[4])
				var wall_y: float = float(parts[5])
				var length: float = -1.0
				if parts.size() > 6:
					length = float(parts[6])
				return _create_chain_enemy_wall(idx, point, Vector2(wall_x, wall_y), length)
			elif parts.size() >= 5:
				var idx1: int = int(parts[1])
				var point1: String = parts[2]
				var idx2: int = int(parts[3])
				var point2: String = parts[4]
				var length: float = -1.0
				if parts.size() > 5:
					length = float(parts[5])
				return _create_chain_enemy_enemy(idx1, point1, idx2, point2, length)
	return "ERR: usage: chain <idx> <point> floor [len] | chain status | chain cut"


func _create_chain_enemy_floor(enemy_idx: int, point: String, length: float) -> String:
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	if enemy_idx >= enemies.size():
		return "ERR: enemy %d not found" % enemy_idx
	var enemy: Node2D = enemies[enemy_idx]
	var ChainScript: GDScript = load("res://scripts/systems/chain.gd")
	var chain := Node2D.new()
	chain.set_script(ChainScript)
	var ap: String = ""
	if "_attach_points" in enemy and enemy._attach_points.has(point):
		ap = point
	var a: Dictionary = ChainScript.make_anchor_body(enemy, ap)
	var attach_pos: Vector2 = chain._get_anchor_world_pos(a) if chain.has_method("_get_anchor_world_pos") else enemy.global_position
	# For static methods we need the instance
	# Raycast to floor
	var floor_pos: Vector2 = Vector2(attach_pos.x, attach_pos.y + length + 200)
	var space := enemy.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(attach_pos, floor_pos, 1)
	var result: Dictionary = space.intersect_ray(query)
	if result:
		floor_pos = result["position"]
	var b: Dictionary = ChainScript.make_anchor_wall(floor_pos)
	var actual_length: float = length if length > 0 else attach_pos.distance_to(floor_pos)
	chain.setup(a, b, actual_length)
	get_tree().current_scene.add_child(chain)
	# Set _chained flag on the enemy so it respects chain constraints
	if "_chained" in enemy:
		enemy._chained = true
	return "OK: chained enemy %d (%s) to floor len=%.0f" % [enemy_idx, point, actual_length]


func _create_chain_enemy_wall(enemy_idx: int, point: String, wall_pos: Vector2, length: float) -> String:
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	if enemy_idx >= enemies.size():
		return "ERR: enemy %d not found" % enemy_idx
	var enemy: Node2D = enemies[enemy_idx]
	var ChainScript: GDScript = load("res://scripts/systems/chain.gd")
	var chain := Node2D.new()
	chain.set_script(ChainScript)
	var ap: String = ""
	if "_attach_points" in enemy and enemy._attach_points.has(point):
		ap = point
	var a: Dictionary = ChainScript.make_anchor_body(enemy, ap)
	var b: Dictionary = ChainScript.make_anchor_wall(wall_pos)
	if length <= 0:
		var attach_pos: Vector2 = enemy.global_position
		if ap != "" and enemy.has_method("get_attach_world_position"):
			attach_pos = enemy.get_attach_world_position(ap)
		length = attach_pos.distance_to(wall_pos)
	chain.setup(a, b, length)
	get_tree().current_scene.add_child(chain)
	if "_chained" in enemy:
		enemy._chained = true
	return "OK: chained enemy %d (%s) to wall (%.0f,%.0f) len=%.0f" % [enemy_idx, point, wall_pos.x, wall_pos.y, length]


func _create_chain_enemy_enemy(idx1: int, point1: String, idx2: int, point2: String, length: float) -> String:
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	if idx1 >= enemies.size():
		return "ERR: enemy %d not found" % idx1
	if idx2 >= enemies.size():
		return "ERR: enemy %d not found" % idx2
	var ChainScript: GDScript = load("res://scripts/systems/chain.gd")
	var chain := Node2D.new()
	chain.set_script(ChainScript)
	var ap1: String = ""
	if "_attach_points" in enemies[idx1] and enemies[idx1]._attach_points.has(point1):
		ap1 = point1
	var a: Dictionary = ChainScript.make_anchor_body(enemies[idx1], ap1)
	var ap2: String = ""
	if "_attach_points" in enemies[idx2] and enemies[idx2]._attach_points.has(point2):
		ap2 = point2
	var b: Dictionary = ChainScript.make_anchor_body(enemies[idx2], ap2)
	if length <= 0:
		length = enemies[idx1].global_position.distance_to(enemies[idx2].global_position)
	chain.setup(a, b, length)
	get_tree().current_scene.add_child(chain)
	if "_chained" in enemies[idx1]:
		enemies[idx1]._chained = true
	if "_chained" in enemies[idx2]:
		enemies[idx2]._chained = true
	return "OK: chained enemy %d (%s) to enemy %d (%s) len=%.0f" % [idx1, point1, idx2, point2, length]


func _cmd_tether(parts: PackedStringArray) -> String:
	## Tether commands: tether <subcommand> [args]
	if parts.size() < 2:
		return "ERR: usage: tether <enemy idx point floor|enemy idx1 point1 idx2 point2|wall x1 y1 x2 y2|length px|cut|status>"

	var subcmd: String = parts[1].to_lower()

	match subcmd:
		"status":
			var tethers: Array = get_tree().get_nodes_in_group("tethers")
			if tethers.is_empty():
				return "tethers: 0"
			var lines: Array[String] = ["tethers: %d" % tethers.size()]
			var TetherScript: GDScript = load("res://scripts/systems/tether.gd")
			for i in range(tethers.size()):
				var t: Node2D = tethers[i]
				var pa: Vector2 = TetherScript.get_anchor_world_pos(t.anchor_a)
				var pb: Vector2 = TetherScript.get_anchor_world_pos(t.anchor_b)
				var a_name: String = t.anchor_a.get("attach_point", "")
				if a_name == "":
					a_name = "wall" if t.anchor_a.get("is_wall", false) else "body"
				var b_name: String = t.anchor_b.get("attach_point", "")
				if b_name == "":
					b_name = "wall" if t.anchor_b.get("is_wall", false) else "body"
				var max_hp: int = t.CHAIN_MAX_HP if t.is_in_group("chains") else t.TETHER_MAX_HP
				lines.append("  [%d] A=%s(%.0f,%.0f) B=%s(%.0f,%.0f) len=%.0f/%.0f tension=%.2f hp=%d/%d" % [
					i, a_name, pa.x, pa.y, b_name, pb.x, pb.y,
					pa.distance_to(pb), t.target_length, t.get_tension(), t.current_hp, max_hp])
			return "\n".join(lines)

		"cut":
			var tethers: Array = get_tree().get_nodes_in_group("tethers")
			var count: int = tethers.size()
			for t in tethers:
				t.sever()
			return "OK: severed %d tethers" % count

		"length":
			if parts.size() < 3:
				return "ERR: usage: tether length <px>"
			var length: float = float(parts[2])
			var tethers: Array = get_tree().get_nodes_in_group("tethers")
			if tethers.is_empty():
				return "ERR: no active tethers"
			tethers[tethers.size() - 1].target_length = clampf(length, 30.0, 900.0)
			return "OK: set last tether length to %.0f" % length

		"wall":
			# tether wall <x1> <y1> <x2> <y2> [length]
			if parts.size() < 6:
				return "ERR: usage: tether wall <x1> <y1> <x2> <y2> [length]"
			var x1: float = float(parts[2])
			var y1: float = float(parts[3])
			var x2: float = float(parts[4])
			var y2: float = float(parts[5])
			var length: float = Vector2(x1, y1).distance_to(Vector2(x2, y2))
			if parts.size() > 6:
				length = float(parts[6])
			return _create_tether_wall_wall(Vector2(x1, y1), Vector2(x2, y2), length)

		_:
			# Try: tether <enemy_idx> <point> floor [length]
			# Or:  tether <enemy_idx1> <point1> <enemy_idx2> <point2> [length]
			if parts.size() >= 4 and parts[3].to_lower() == "floor":
				var idx: int = int(parts[1])
				var point: String = parts[2]
				var length: float = 100.0
				if parts.size() > 4:
					length = float(parts[4])
				return _create_tether_enemy_floor(idx, point, length)
			elif parts.size() >= 5:
				var idx1: int = int(parts[1])
				var point1: String = parts[2]
				var idx2: int = int(parts[3])
				var point2: String = parts[4]
				var length: float = -1.0  # Auto
				if parts.size() > 5:
					length = float(parts[5])
				return _create_tether_enemy_enemy(idx1, point1, idx2, point2, length)
			return "ERR: unrecognized tether command. Try: tether status, tether cut, tether <idx> <point> floor, tether <idx1> <point1> <idx2> <point2>"


func _create_tether_enemy_floor(enemy_idx: int, point: String, length: float) -> String:
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	if enemy_idx >= enemies.size():
		return "ERR: enemy index %d not found" % enemy_idx
	var enemy: Node2D = enemies[enemy_idx]

	var TetherScript: GDScript = load("res://scripts/systems/tether.gd")
	var tether := Node2D.new()
	tether.set_script(TetherScript)

	var ap: String = ""
	if "_attach_points" in enemy and enemy._attach_points.has(point):
		ap = point
	var a: Dictionary = TetherScript.make_anchor_body(enemy, ap)

	# Floor position: directly below the attachment point
	var attach_pos: Vector2 = TetherScript.get_anchor_world_pos(a)
	var floor_pos: Vector2 = Vector2(attach_pos.x, attach_pos.y + length)
	# Raycast to find actual floor
	var space := enemy.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(attach_pos, attach_pos + Vector2(0, length + 200), 1)
	var result: Dictionary = space.intersect_ray(query)
	if result:
		floor_pos = result["position"]

	var b: Dictionary = TetherScript.make_anchor_wall(floor_pos)

	var actual_length: float = length
	if actual_length <= 0:
		actual_length = attach_pos.distance_to(floor_pos)

	tether.setup(a, b, actual_length)
	get_tree().current_scene.add_child(tether)
	return "OK: tethered enemy %d (%s) to floor at (%.0f,%.0f) len=%.0f" % [enemy_idx, point, floor_pos.x, floor_pos.y, actual_length]


func _create_tether_enemy_enemy(idx1: int, point1: String, idx2: int, point2: String, length: float) -> String:
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	if idx1 >= enemies.size():
		return "ERR: enemy index %d not found" % idx1
	if idx2 >= enemies.size():
		return "ERR: enemy index %d not found" % idx2

	var TetherScript: GDScript = load("res://scripts/systems/tether.gd")
	var tether := Node2D.new()
	tether.set_script(TetherScript)

	var ap1: String = ""
	if "_attach_points" in enemies[idx1] and enemies[idx1]._attach_points.has(point1):
		ap1 = point1
	var a: Dictionary = TetherScript.make_anchor_body(enemies[idx1], ap1)

	var ap2: String = ""
	if "_attach_points" in enemies[idx2] and enemies[idx2]._attach_points.has(point2):
		ap2 = point2
	var b: Dictionary = TetherScript.make_anchor_body(enemies[idx2], ap2)

	if length <= 0:
		length = TetherScript.get_anchor_world_pos(a).distance_to(TetherScript.get_anchor_world_pos(b))

	tether.setup(a, b, length)
	get_tree().current_scene.add_child(tether)
	return "OK: tethered enemy %d (%s) to enemy %d (%s) len=%.0f" % [idx1, point1, idx2, point2, length]


func _create_tether_wall_wall(pos_a: Vector2, pos_b: Vector2, length: float) -> String:
	var TetherScript: GDScript = load("res://scripts/systems/tether.gd")
	var tether := Node2D.new()
	tether.set_script(TetherScript)

	var a: Dictionary = TetherScript.make_anchor_wall(pos_a)
	var b: Dictionary = TetherScript.make_anchor_wall(pos_b)

	tether.setup(a, b, length)
	get_tree().current_scene.add_child(tether)
	return "OK: tethered wall (%.0f,%.0f) to (%.0f,%.0f) len=%.0f" % [pos_a.x, pos_a.y, pos_b.x, pos_b.y, length]


func _apply_portal_state() -> void:
	## Apply the stored portal disabled state to all portal nodes.
	var scene := get_tree().current_scene
	if not scene:
		return
	var disabled: bool = scene.get_meta("portal_disabled", false)
	for node in scene.get_children():
		if "disabled" in node and ("_doors_open" in node or node.name.contains("ortal") or node.name.contains("oorway")):
			node.disabled = disabled


func _cmd_standdown(parts: PackedStringArray) -> String:
	## Toggle or set stand-down mode on all quadruped monsters.
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	var count: int = 0
	var new_state: Variant = null  # null = toggle

	if parts.size() > 1:
		match parts[1].to_lower():
			"on": new_state = true
			"off": new_state = false

	for e in enemies:
		if "_standdown" in e:
			if new_state != null:
				e._standdown = new_state as bool
			else:
				e._standdown = not e._standdown
			# When waking up (standdown off), kick into CHASE state
			if not e._standdown and "_state" in e and e._state == 19:  # 19 = STANDDOWN
				e._state = 1  # CHASE
				if e.has_method("_pick_target"):
					e._pick_target()
			count += 1

	if count == 0:
		return "ERR: no monsters with standdown support"
	var state_str: String = ""
	if count > 0:
		state_str = str(enemies[0]._standdown) if "_standdown" in enemies[0] else "?"
	return "OK: standdown=%s on %d monsters" % [state_str, count]


func _cmd_attacker(parts: PackedStringArray) -> String:
	## Control attack dummies: attacker <subcommand> [args]
	var attackers: Array = get_tree().get_nodes_in_group("attack_dummies")
	if attackers.is_empty():
		return "ERR: no attack dummies spawned. Use: spawn attacker [x y]"

	if parts.size() < 2:
		return "ERR: usage: attacker <target|part|weapon|rate|stop|start|stats>"

	var subcmd: String = parts[1].to_lower()
	match subcmd:
		"target":
			# attacker target <enemy_index>
			var idx: int = int(parts[2]) if parts.size() > 2 else 0
			var enemies: Array = get_tree().get_nodes_in_group("enemies")
			if idx >= enemies.size():
				return "ERR: enemy index %d not found (have %d)" % [idx, enemies.size()]
			for a in attackers:
				a.set_target(enemies[idx])
			return "OK: targeting %s" % enemies[idx].name

		"part":
			# attacker part <part_name>
			var part_name: String = parts[2] if parts.size() > 2 else ""
			for a in attackers:
				a.set_target_part(part_name)
			return "OK: targeting part '%s'" % part_name

		"weapon":
			# attacker weapon <bow|balloon>
			if parts.size() < 3:
				return "ERR: usage: attacker weapon <bow|balloon>"
			var weapon: String = parts[2].to_lower()
			for a in attackers:
				a.set_weapon(weapon)
			return "OK: weapon=%s" % weapon

		"rate":
			# attacker rate <seconds>
			if parts.size() < 3:
				return "ERR: usage: attacker rate <seconds>"
			var rate: float = float(parts[2])
			for a in attackers:
				a.set_rate(rate)
			return "OK: attack rate=%.1fs" % rate

		"stop":
			for a in attackers:
				a._attacking = false
			return "OK: attackers stopped"

		"start":
			for a in attackers:
				a._attacking = true
			return "OK: attackers started"

		"stats":
			var lines: Array[String] = ["attack_dummies: %d" % attackers.size()]
			for a in attackers:
				var target_name: String = a._target.name if is_instance_valid(a._target) else "none"
				lines.append("  %s at (%.0f,%.0f) weapon=%s part=%s attacking=%s shots=%d hits=%d" % [
					a.name, a.global_position.x, a.global_position.y,
					a._weapon, a._target_part, str(a._attacking),
					a._shots_fired, a._hits_landed])
			return "\n".join(lines)

		"tether_length":
			if parts.size() < 3:
				return "ERR: usage: attacker tether_length <px>"
			var tlen: float = float(parts[2])
			for a in attackers:
				a.set_tether_length(tlen)
			return "OK: tether_length=%.0f" % tlen

		"tether_b":
			# attacker tether_b floor  OR  attacker tether_b enemy <idx> <part>
			if parts.size() < 3:
				return "ERR: usage: attacker tether_b floor | attacker tether_b enemy <idx> <part>"
			var btype: String = parts[2].to_lower()
			if btype == "floor":
				for a in attackers:
					a.set_tether_target_b("floor")
				return "OK: tether_b=floor"
			elif btype == "enemy" and parts.size() >= 5:
				var eidx: int = int(parts[3])
				var epart: String = parts[4]
				var enemies: Array = get_tree().get_nodes_in_group("enemies")
				if eidx >= enemies.size():
					return "ERR: enemy %d not found" % eidx
				for a in attackers:
					a.set_tether_target_b("enemy", enemies[eidx], epart)
				return "OK: tether_b=enemy %d %s" % [eidx, epart]
			return "ERR: usage: attacker tether_b floor | attacker tether_b enemy <idx> <part>"

		_:
			return "ERR: unknown attacker subcommand '%s'. Try: target, part, weapon, rate, stop, start, stats, tether_length, tether_b" % subcmd


func _cmd_debug(parts: PackedStringArray) -> String:
	if parts.size() < 2:
		# No subcommand: toggle global on/off
		DebugOverlay.global_enabled = not DebugOverlay.global_enabled
		# Sync legacy PlayerHUD._debug_mode for backward compat during migration
		PlayerHUD._debug_mode = DebugOverlay.global_enabled
		return "OK: debug=%s" % ("on" if DebugOverlay.global_enabled else "off")

	var subcmd: String = parts[1].to_lower()

	match subcmd:
		"list":
			return DebugOverlay.get_status_text()

		"on":
			if parts.size() < 3:
				return "ERR: usage: debug on <aspect>[/<sub>]"
			var path: String = parts[2]
			_debug_set_human_visual(path, true)
			return "OK: %s visual=on" % path

		"off":
			if parts.size() < 3:
				return "ERR: usage: debug off <aspect>[/<sub>]"
			var path: String = parts[2]
			_debug_set_human_visual(path, false)
			return "OK: %s visual=off" % path

		"log":
			if parts.size() < 3:
				return "ERR: usage: debug log <aspect>[/<sub>]"
			_debug_set_human_textual(parts[2], DebugOverlay.TextMode.LOG)
			return "OK: %s textual=log" % parts[2]

		"console":
			if parts.size() < 3:
				return "ERR: usage: debug console <aspect>[/<sub>]"
			_debug_set_human_textual(parts[2], DebugOverlay.TextMode.CONSOLE)
			return "OK: %s textual=console" % parts[2]

		"both":
			if parts.size() < 3:
				return "ERR: usage: debug both <aspect>[/<sub>]"
			_debug_set_human_textual(parts[2], DebugOverlay.TextMode.BOTH)
			return "OK: %s textual=both" % parts[2]

		"nolog":
			if parts.size() < 3:
				return "ERR: usage: debug nolog <aspect>[/<sub>]"
			_debug_set_human_textual(parts[2], DebugOverlay.TextMode.NONE)
			return "OK: %s textual=none" % parts[2]

		"save":
			DebugOverlay.save_profile()
			return "OK: debug profile saved"

		"load":
			DebugOverlay.load_profile()
			return "OK: debug profile loaded"

		"filter":
			return _cmd_debug_filter(parts)

		"reset":
			DebugOverlay.remove_observer("human")
			return "OK: human observer state cleared"

		"profile":
			# Inline JSON profile: debug profile {"pathing/waypoints":"log"}
			if parts.size() < 3:
				return "ERR: usage: debug profile <json>"
			var json_str: String = " ".join(parts.slice(2))
			var json := JSON.new()
			if json.parse(json_str) != OK:
				return "ERR: invalid JSON: %s" % json.get_error_message()
			DebugOverlay.apply_profile("script:rcon", json.data)
			return "OK: applied debug profile (%d aspects)" % json.data.size()

		"clear_transient":
			DebugOverlay.clear_transient_observers()
			return "OK: transient observers cleared"

		_:
			return "ERR: unknown debug subcommand '%s'. Try: list, on, off, log, console, both, nolog, save, load, filter, reset, profile, clear_transient" % subcmd


## Set human visual for an aspect or all aspects in a group.
func _debug_set_human_visual(path: String, visual: bool) -> void:
	# Check if it's a group name (no "/" in path)
	if "/" not in path:
		# Try as group
		var aspects: Array[String] = DebugOverlay.get_aspects_in_group(path)
		if aspects.size() > 0:
			DebugOverlay.set_group_visual(path, visual)
			return
	# Single aspect
	var state: Array = DebugOverlay.get_observer_state(path, "human")
	DebugOverlay.set_observer(path, "human", visual, state[1])


## Set human textual for an aspect or all aspects in a group.
func _debug_set_human_textual(path: String, textual: int) -> void:
	if "/" not in path:
		var aspects: Array[String] = DebugOverlay.get_aspects_in_group(path)
		if aspects.size() > 0:
			DebugOverlay.set_group_textual(path, textual)
			return
	var state: Array = DebugOverlay.get_observer_state(path, "human")
	DebugOverlay.set_observer(path, "human", state[0], textual)


func _cmd_debug_filter(parts: PackedStringArray) -> String:
	# debug filter type <type> on|off
	# debug filter id <pattern>
	if parts.size() < 4:
		return "ERR: usage: debug filter type <type> on|off  |  debug filter id <pattern>"

	var filter_type: String = parts[2].to_lower()
	match filter_type:
		"type":
			var type_name: String = parts[3].to_lower()
			if parts.size() < 5:
				# Show current state
				var enabled: bool = DebugOverlay.entity_type_filter.get(type_name, true)
				return "filter type %s=%s" % [type_name, "on" if enabled else "off"]
			var on_off: String = parts[4].to_lower()
			DebugOverlay.entity_type_filter[type_name] = (on_off == "on")
			return "OK: filter type %s=%s" % [type_name, on_off]

		"id":
			var pattern: String = parts[3]
			DebugOverlay.entity_id_pattern = pattern
			return "OK: filter id=%s" % pattern

		_:
			return "ERR: unknown filter type '%s'. Try: type, id" % filter_type


func _ensure_test_editor() -> Node:
	## Find or create the test editor. Returns the editor node.
	if _test_editor and is_instance_valid(_test_editor):
		if not _test_editor._active:
			_test_editor.toggle()
		return _test_editor
	# Look for existing editor in the scene
	for node in get_tree().current_scene.get_children():
		if node.has_method("toggle") and node.has_method("_load_test") and node.has_method("_run_test"):
			_test_editor = node
			if not _test_editor._active:
				_test_editor.toggle()
			return _test_editor
	# Create one
	var script: GDScript = load("res://scripts/ui/test_editor.gd")
	_test_editor = CanvasLayer.new()
	_test_editor.set_script(script)
	get_tree().current_scene.add_child(_test_editor)
	_test_editor.toggle()
	return _test_editor


func _ensure_test_runner() -> void:
	if _test_runner and is_instance_valid(_test_runner):
		return
	var script: GDScript = load("res://scripts/systems/test_runner.gd")
	_test_runner = Node.new()
	_test_runner.name = "TestRunner"
	_test_runner.set_script(script)
	add_child(_test_runner)


func _ensure_zone_manager() -> void:
	if _zone_manager and is_instance_valid(_zone_manager):
		return
	var script: GDScript = load("res://scripts/systems/test_zones.gd")
	_zone_manager = Node2D.new()
	_zone_manager.name = "TestZones"
	_zone_manager.set_script(script)
	get_tree().current_scene.add_child(_zone_manager)


func _ensure_leap_checker() -> void:
	if _leap_checker and is_instance_valid(_leap_checker):
		return
	var script: GDScript = load("res://scripts/systems/test_bounded_leaps.gd")
	_leap_checker = Node2D.new()
	_leap_checker.name = "TestBoundedLeaps"
	_leap_checker.set_script(script)
	get_tree().current_scene.add_child(_leap_checker)


func _cmd_bleap(parts: PackedStringArray, full_cmd: String) -> String:
	## Bounded-leap builder. Configures leap check constraints step by step.
	## Sub-commands: reset, a, b, plan, start, end, disallow, min, show
	if parts.size() < 2:
		return "ERR: usage: bleap <reset|a|b|plan|start|end|disallow|min|show>"

	var sub: String = parts[1].to_lower()
	match sub:
		"reset":
			_bleap_defs = []
			_bleap_plat_a = {}
			_bleap_plat_b = {}
			_bleap_plans = []
			_bleap_current_plan = {}
			_bleap_min_matched = 1
			return "OK: bleap state reset"

		"a":
			if parts.size() < 5:
				return "ERR: usage: bleap a <x> <y> <radius>"
			_bleap_plat_a = {"x": float(parts[2]), "y": float(parts[3]), "radius": float(parts[4])}
			return "OK: platform_a = (%.0f,%.0f) r=%.0f" % [_bleap_plat_a["x"], _bleap_plat_a["y"], _bleap_plat_a["radius"]]

		"b":
			if parts.size() < 5:
				return "ERR: usage: bleap b <x> <y> <radius>"
			_bleap_plat_b = {"x": float(parts[2]), "y": float(parts[3]), "radius": float(parts[4])}
			return "OK: platform_b = (%.0f,%.0f) r=%.0f" % [_bleap_plat_b["x"], _bleap_plat_b["y"], _bleap_plat_b["radius"]]

		"plan":
			# bleap plan req|opt [start x y w h] [end x y r] [disallow r x1 y1 x2 y2] ...
			if parts.size() < 3:
				return "ERR: usage: bleap plan req|opt [start x y w h] [end x y r] [disallow r x1 y1 x2 y2]"
			var required: bool = parts[2].to_lower() == "req"
			var plan: Dictionary = {"required": required, "start": {}, "end": {}, "disallow": []}
			# Parse keyword args from remaining tokens
			var i: int = 3
			while i < parts.size():
				match parts[i].to_lower():
					"start":
						if i + 4 < parts.size():
							plan["start"] = {"x": float(parts[i+1]), "y": float(parts[i+2]),
								"w": float(parts[i+3]), "h": float(parts[i+4])}
							i += 5
						else: i += 1
					"end":
						if i + 3 < parts.size():
							plan["end"] = {"x": float(parts[i+1]), "y": float(parts[i+2]), "radius": float(parts[i+3])}
							i += 4
						else: i += 1
					"disallow":
						if i + 5 < parts.size():
							plan["disallow"].append({"radius": float(parts[i+1]),
								"x1": float(parts[i+2]), "y1": float(parts[i+3]),
								"x2": float(parts[i+4]), "y2": float(parts[i+5])})
							i += 6
						else: i += 1
					_: i += 1
			_bleap_plans.append(plan)
			var req_str: String = "REQUIRED" if required else "optional"
			return "OK: plan %d (%s) — start=%s end=%s disallow=%d" % [
				_bleap_plans.size(), req_str,
				str(plan["start"]), str(plan["end"]), plan["disallow"].size()]

		"start":
			# bleap start x y w h — set start for current plan being built
			if parts.size() < 6:
				return "ERR: usage: bleap start <x> <y> <w> <h>"
			_bleap_current_plan["start"] = {"x": float(parts[2]), "y": float(parts[3]),
				"w": float(parts[4]), "h": float(parts[5])}
			return "OK: current plan start = (%.0f,%.0f) %0.fx%.0f" % [float(parts[2]), float(parts[3]), float(parts[4]), float(parts[5])]

		"end":
			if parts.size() < 5:
				return "ERR: usage: bleap end <x> <y> <radius>"
			_bleap_current_plan["end"] = {"x": float(parts[2]), "y": float(parts[3]), "radius": float(parts[4])}
			return "OK: current plan end = (%.0f,%.0f) r=%.0f" % [float(parts[2]), float(parts[3]), float(parts[4])]

		"disallow":
			if parts.size() < 7:
				return "ERR: usage: bleap disallow <r> <x1> <y1> <x2> <y2>"
			if not _bleap_current_plan.has("disallow"):
				_bleap_current_plan["disallow"] = []
			_bleap_current_plan["disallow"].append({"radius": float(parts[2]),
				"x1": float(parts[3]), "y1": float(parts[4]),
				"x2": float(parts[5]), "y2": float(parts[6])})
			return "OK: disallow added (r=%.0f path=(%.0f,%.0f)→(%.0f,%.0f))" % [float(parts[2]), float(parts[3]), float(parts[4]), float(parts[5]), float(parts[6])]

		"commit":
			# Finalize current_plan and push to plans list
			if _bleap_current_plan.is_empty():
				return "ERR: no plan in progress (use bleap plan req|opt first)"
			_bleap_plans.append(_bleap_current_plan.duplicate(true))
			_bleap_current_plan = {}
			return "OK: plan %d committed" % _bleap_plans.size()

		"next":
			# Commit current def and start a new one (without clearing accumulated defs)
			if not _bleap_plat_a.is_empty() or not _bleap_plans.is_empty():
				_bleap_defs.append({"platform_a": _bleap_plat_a, "platform_b": _bleap_plat_b, "plans": _bleap_plans})
			_bleap_plat_a = {}
			_bleap_plat_b = {}
			_bleap_plans = []
			_bleap_current_plan = {}
			return "OK: def committed (%d total), ready for next" % _bleap_defs.size()

		"min":
			if parts.size() < 3:
				return "ERR: usage: bleap min <n>"
			_bleap_min_matched = int(parts[2])
			return "OK: min_matched = %d" % _bleap_min_matched

		"show":
			var ls: Array[String] = ["bleap state:"]
			ls.append("  platform_a: %s" % str(_bleap_plat_a))
			ls.append("  platform_b: %s" % str(_bleap_plat_b))
			ls.append("  min_matched: %d" % _bleap_min_matched)
			ls.append("  plans: %d" % _bleap_plans.size())
			for pi in range(_bleap_plans.size()):
				var p: Dictionary = _bleap_plans[pi]
				ls.append("    [%d] %s start=%s end=%s disallow=%d" % [
					pi + 1, "REQUIRED" if p.get("required", false) else "optional",
					str(p.get("start", {})), str(p.get("end", {})), p.get("disallow", []).size()])
			if not _bleap_current_plan.is_empty():
				ls.append("  (in-progress plan: %s)" % str(_bleap_current_plan))
			return "\n".join(ls)

		_:
			return "ERR: unknown bleap sub-command '%s'" % sub


func get_bleap_check_data() -> Dictionary:
	## Returns all accumulated bleap defs (from `bleap next`) plus the current one being built.
	var all_defs: Array = _bleap_defs.duplicate()
	# Include the current def if it has content
	if not _bleap_plat_a.is_empty() or not _bleap_plans.is_empty():
		all_defs.append({"platform_a": _bleap_plat_a, "platform_b": _bleap_plat_b, "plans": _bleap_plans})
	if all_defs.is_empty():
		return {}
	return {
		"leaps": all_defs,
		"min_matched": _bleap_min_matched,
	}


func _cmd_testload(test_name: String) -> String:
	## Load a test JSON and convert it to a flat script list for editing.
	var loaded_data: Dictionary = {}
	for dir_path in ["res://data/tests/", "user://data/tests/"]:
		var path: String = dir_path + test_name + ".json"
		if FileAccess.file_exists(path):
			var file := FileAccess.open(path, FileAccess.READ)
			if file:
				var json := JSON.new()
				if json.parse(file.get_as_text()) == OK:
					loaded_data = json.data
				file.close()
			break
	if loaded_data.is_empty():
		return "ERR: test '%s' not found" % test_name

	_test_script_name = test_name
	_test_script = []

	# Use existing "script" field if present
	if loaded_data.has("script"):
		for line in loaded_data["script"]:
			_test_script.append(str(line))
		return "OK: loaded '%s' — %d lines (script format)" % [test_name, _test_script.size()]

	# Convert legacy {setup, wait, checks, debug} format to flat script
	var debug_profile: Dictionary = loaded_data.get("debug", {})
	for aspect in debug_profile:
		var mode: String = debug_profile[aspect]
		match mode:
			"on":        _test_script.append("debug on " + aspect)
			"log":       _test_script.append("debug log " + aspect)
			"both":      _test_script.append("debug both " + aspect)
			"on+log", _: _test_script.append("debug on " + aspect)

	for cmd in loaded_data.get("setup", []):
		_test_script.append(str(cmd))

	var wait_secs: float = loaded_data.get("wait", 10.0)
	_test_script.append("wait %.0f" % wait_secs)

	# Convert checks
	for ch in loaded_data.get("checks", []):
		var ch_cmd: String = ch.get("command", "")
		var ch_label: String = ch.get("label", ch_cmd)
		match ch_cmd:
			"zones":
				_test_script.append("check zones")
			"bounded_leaps":
				# Re-encode bounded_leaps as bleap commands
				var leap_defs: Array = ch.get("leaps", [])
				var ch_min: int = ch.get("min_matched", 1)
				_test_script.append("bleap reset")
				for ld in leap_defs:
					var pa: Dictionary = ld.get("platform_a", {})
					var pb: Dictionary = ld.get("platform_b", {})
					if not pa.is_empty():
						_test_script.append("bleap a %.0f %.0f %.0f" % [pa.get("x",0), pa.get("y",0), pa.get("radius",100)])
					if not pb.is_empty():
						_test_script.append("bleap b %.0f %.0f %.0f" % [pb.get("x",0), pb.get("y",0), pb.get("radius",100)])
					for plan in ld.get("plans", []):
						var req_str: String = "req" if plan.get("required", false) else "opt"
						var plan_line: String = "bleap plan " + req_str
						var ps: Dictionary = plan.get("start", {})
						if not ps.is_empty():
							plan_line += " start %.0f %.0f %.0f %.0f" % [ps.get("x",0), ps.get("y",0), ps.get("w",0), ps.get("h",0)]
						var pe: Dictionary = plan.get("end", {})
						if not pe.is_empty():
							plan_line += " end %.0f %.0f %.0f" % [pe.get("x",0), pe.get("y",0), pe.get("radius",0)]
						for dis in plan.get("disallow", []):
							plan_line += " disallow %.0f %.0f %.0f %.0f %.0f" % [
								dis.get("radius",20), dis.get("x1",0), dis.get("y1",0),
								dis.get("x2",0), dis.get("y2",0)]
						_test_script.append(plan_line)
				_test_script.append("bleap min %d" % ch_min)
				_test_script.append("check bounded_leaps " + ch_label)
			"fps", "hp", _:
				# Generic check: rebuild as "check <cmd> > <n>" etc.
				var threshold_str: String = ""
				if ch.has("expect_gt"):  threshold_str = "> %s" % str(ch["expect_gt"])
				elif ch.has("expect_lt"): threshold_str = "< %s" % str(ch["expect_lt"])
				elif ch.has("expect_eq"): threshold_str = "= %s" % str(ch["expect_eq"])
				var extract: String = ch.get("extract", "")
				var full_check: String = "check %s" % ch_cmd
				if extract:  full_check += " extract:" + extract
				if threshold_str: full_check += " " + threshold_str
				if ch_label != ch_cmd: full_check += " label:" + ch_label
				_test_script.append(full_check)

	return "OK: loaded '%s' — %d lines (converted from legacy JSON)" % [test_name, _test_script.size()]


func _cmd_testsave(save_name: String) -> String:
	## Save the current script back to JSON (using the script field).
	if _test_script.is_empty():
		return "ERR: no script to save"
	var data: Dictionary = {
		"name": save_name,
		"script": _test_script,
	}
	var path: String = "res://data/tests/" + save_name + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		# Try user:// fallback
		path = "user://data/tests/" + save_name + ".json"
		DirAccess.make_dir_recursive_absolute("user://data/tests/")
		file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return "ERR: could not write to '%s'" % path
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	_test_script_name = save_name
	return "OK: saved '%s' (%d lines) → %s" % [save_name, _test_script.size(), path]


func _cmd_notify(notify_name: String, message: String, buttons_str: String, timeout: float, mode: String) -> String:
	## Show a notification. Modes:
	## - "blocking": modal dialog that captures all input
	## - "editor": non-blocking banner in the test editor (UI remains interactive)
	var json := JSON.new()
	var buttons: Array = ["OK"]
	if json.parse(buttons_str) == OK and json.data is Array:
		buttons = json.data

	_notify_name = notify_name
	_notify_buttons = buttons
	_notify_timeout = timeout
	_notify_timer = timeout
	_notify_active = true
	_notify_mode = mode
	_notify_dismissed_button = ""

	# Always clean up any previous blocking layer
	if _notify_layer and is_instance_valid(_notify_layer):
		_notify_layer.queue_free()
		_notify_layer = null

	if mode == "blocking":
		_notify_layer = CanvasLayer.new()
		_notify_layer.layer = 115
		var panel := Control.new()
		panel.name = "NotifyPanel"
		panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		panel.draw.connect(_draw_blocking_notify)
		panel.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_notify_handle_click(event.position)
		)
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		_notify_layer.add_child(panel)
		add_child(_notify_layer)
	elif mode == "editor":
		# Push notify state to the test editor — it renders the banner
		if _test_editor and is_instance_valid(_test_editor):
			_test_editor.set_meta("notify_name", notify_name)
			_test_editor.set_meta("notify_message", message)
			_test_editor.set_meta("notify_buttons", buttons)
			_test_editor.set_meta("notify_timeout", timeout)
			_test_editor.set_meta("notify_active", true)

	print("NOTIFY SHOW name=%s mode=%s buttons=%s timeout=%.0f" % [notify_name, mode, str(buttons), timeout])
	return "OK: notify '%s' shown (%s, %.0fs)" % [notify_name, mode, timeout]


func _cmd_notify_dismiss(button_label: String) -> String:
	## Dismiss the active notification.
	if not _notify_active:
		return "ERR: no notify active"
	_notify_dismissed_button = button_label
	_notify_active = false
	if _notify_mode == "blocking" and _notify_layer and is_instance_valid(_notify_layer):
		_notify_layer.queue_free()
		_notify_layer = null
	elif _notify_mode == "editor" and _test_editor and is_instance_valid(_test_editor):
		_test_editor.set_meta("notify_active", false)
	print("NOTIFY DISMISS button=%s" % button_label)
	return "OK: notify dismissed (button=%s)" % button_label


func _cmd_emit(event_name: String, value: String) -> String:
	## Emit a named event. Used by test scripts for state transitions.
	print("EMIT %s=%s" % [event_name, value])
	# Store the latest value for polling
	set_meta("emit_" + event_name, value)
	return "OK: emit %s=%s" % [event_name, value]


func _draw_blocking_notify() -> void:
	if not _notify_active or not _notify_layer:
		return
	var panel: Control = _notify_layer.get_child(0) if _notify_layer.get_child_count() > 0 else null
	if not panel:
		return
	var font: Font = ThemeDB.fallback_font
	var vp := get_viewport().get_visible_rect().size
	var pw: float = 300.0
	var ph: float = 120.0
	var px: float = (vp.x - pw) / 2.0
	var py: float = (vp.y - ph) / 2.0

	# Dim background
	panel.draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0, 0, 0, 0.4))
	# Dialog box
	panel.draw_rect(Rect2(px, py, pw, ph), Color(0.1, 0.12, 0.1, 0.97))
	panel.draw_rect(Rect2(px, py, pw, ph), Color(0.4, 0.7, 0.4, 0.7), false, 2.0)
	# Name label (small, top)
	panel.draw_string(font, Vector2(px + 10, py + 16), _notify_name,
		HORIZONTAL_ALIGNMENT_LEFT, pw - 20, 9, Color(0.5, 0.5, 0.5))
	# Message
	panel.draw_string(font, Vector2(px + pw/2 - 30, py + 45), _notify_name.to_upper() if _notify_name == "observations" else "DONE",
		HORIZONTAL_ALIGNMENT_LEFT, pw - 20, 20, Color(0.9, 0.9, 0.9))
	# Countdown
	var countdown: int = ceili(_notify_timer)
	panel.draw_string(font, Vector2(px + pw/2 - 10, py + 70), str(countdown),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.8, 0.8, 0.3))
	# Buttons
	var bw: float = (pw - 20) / float(_notify_buttons.size())
	for i in range(_notify_buttons.size()):
		var bx: float = px + 10 + i * bw
		var by: float = py + ph - 35
		var col := Color(0.3, 0.8, 0.3)
		panel.draw_rect(Rect2(bx, by, bw - 6, 25), col * Color(1, 1, 1, 0.2))
		panel.draw_rect(Rect2(bx, by, bw - 6, 25), col * Color(1, 1, 1, 0.6), false, 1.0)
		panel.draw_string(font, Vector2(bx + bw/2 - 12, by + 18), str(_notify_buttons[i]),
			HORIZONTAL_ALIGNMENT_LEFT, bw - 10, 12, col)


func _notify_handle_click(pos: Vector2) -> void:
	var vp := get_viewport().get_visible_rect().size
	var pw: float = 300.0
	var ph: float = 120.0
	var px: float = (vp.x - pw) / 2.0
	var py: float = (vp.y - ph) / 2.0
	var bw: float = (pw - 20) / float(_notify_buttons.size())
	for i in range(_notify_buttons.size()):
		var bx: float = px + 10 + i * bw
		var by: float = py + ph - 35
		if Rect2(bx, by, bw - 6, 25).has_point(pos):
			_cmd_notify_dismiss(str(_notify_buttons[i]))
			return


func _cmd_list_tests() -> String:
	var lines: Array[String] = ["tests:"]
	for dir_path in ["res://data/tests/"]:
		var dir := DirAccess.open(dir_path)
		if dir:
			dir.list_dir_begin()
			var fname: String = dir.get_next()
			while fname != "":
				if fname.ends_with(".json") and not dir.current_is_dir():
					lines.append("  %s" % fname.get_basename())
				fname = dir.get_next()
	lines.append("suites:")
	for dir_path in ["res://data/tests/suites/"]:
		var dir := DirAccess.open(dir_path)
		if dir:
			dir.list_dir_begin()
			var fname: String = dir.get_next()
			while fname != "":
				if fname.ends_with(".json") and not dir.current_is_dir():
					lines.append("  %s" % fname.get_basename())
				fname = dir.get_next()
	return "\n".join(lines)
