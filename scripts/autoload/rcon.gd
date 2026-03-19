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
			return "OK: cleared %d players" % cleared_p

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

		_:
			return "ERR: unknown attacker subcommand '%s'. Try: target, part, weapon, rate, stop, start, stats" % subcmd
