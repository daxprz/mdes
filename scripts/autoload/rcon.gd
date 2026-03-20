extends Node

## Remote Console — TCP server for external tools to control the game.
## Listens on port 9999. Send text commands, one per line.
## Responds with results.

const PORT := 9999

var _server: TCPServer = null
var _clients: Array = []  # Array of StreamPeerTCP
var _title_layer: CanvasLayer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_server = TCPServer.new()
	var err := _server.listen(PORT)
	if err == OK:
		print("RCON: listening on port %d" % PORT)
	else:
		push_warning("RCON: failed to listen on port %d (err=%d)" % [PORT, err])


func _process(_delta: float) -> void:
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
			return "Commands: help, debug, spawn <monster|dummy|attacker> [x y], tp <x> <y>, tab [n], key <k>, enemies, players, precog, standdown [on|off], attacker <target|part|weapon|rate|stop|start|stats>, status, quit"

		"debug":
			PlayerHUD._debug_mode = not PlayerHUD._debug_mode
			return "OK: debug=%s" % str(PlayerHUD._debug_mode)

		"spawn":
			var what: String = parts[1] if parts.size() > 1 else "monster"
			var x: float = float(parts[2]) if parts.size() > 2 else 960.0
			var y: float = float(parts[3]) if parts.size() > 3 else 750.0
			return _cmd_spawn(what, x, y)

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

		"tether":
			return _cmd_tether(parts)

		"standdown":
			return _cmd_standdown(parts)

		"attacker":
			return _cmd_attacker(parts)

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


func _cmd_spawn(what: String, x: float = 960.0, y: float = 750.0) -> String:
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
			monster.global_position = Vector2(x, y)
			container.add_child(monster)
			return "OK: spawned monster at (%.0f, %.0f)" % [x, y]

		"dummy":
			# Fake player — a simple CharacterBody2D in the "players" group
			# that the monster can target. No controller needed.
			var dummy := CharacterBody2D.new()
			dummy.name = "DummyPlayer"
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
			container.add_child(dummy)
			dummy.queue_redraw()
			return "OK: spawned dummy player at (%.0f, %.0f)" % [x, y]

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

	# Hold for 8 seconds then fade
	var tween := container.create_tween()
	tween.tween_interval(8.0)
	tween.tween_property(container, "modulate:a", 0.0, 2.0)
	tween.tween_callback(container.queue_free)


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
				lines.append("  [%d] A=%s(%.0f,%.0f) B=%s(%.0f,%.0f) len=%.0f/%.0f tension=%.2f hp=%d/%d" % [
					i, a_name, pa.x, pa.y, b_name, pb.x, pb.y,
					pa.distance_to(pb), t.target_length, t.get_tension(), t.current_hp, t.TETHER_MAX_HP])
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
