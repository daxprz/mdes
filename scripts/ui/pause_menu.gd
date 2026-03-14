extends CanvasLayer

## Pause menu - the player who pressed START controls it.
## Only that player's device can navigate/confirm. Others are locked out.

var _selected := 0  # 0 = Resume, 1 = Quit to Menu, 2 = Quit Game
var _active := false
var _owner_device: int = -99  # Device that opened the menu (-1 = keyboard)
var _nav_cooldown: float = 0.0
const NAV_COOLDOWN_TIME := 0.25  # Prevent too-fast scrolling

var _panel: PanelContainer
var _resume_label: Label
var _quit_menu_label: Label
var _quit_game_label: Label

# Profile stats labels
var _profile_name_label: Label = null
var _skill_attack_label: Label = null
var _skill_special_label: Label = null
var _skill_charge_label: Label = null
var _skill_block_label: Label = null
var _session_stats_label: Label = null


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false


func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.name = "Overlay"
	overlay.anchors_preset = Control.PRESET_FULL_RECT
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.color = Color(0, 0, 0, 0.6)
	add_child(overlay)

	_panel = PanelContainer.new()
	_panel.anchors_preset = Control.PRESET_CENTER
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -180
	_panel.offset_right = 180
	_panel.offset_top = -200
	_panel.offset_bottom = 200

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.08, 0.18, 0.95)
	style.border_color = Color(0.8, 0.6, 0.2)
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(20)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title)

	# Profile stats section
	_profile_name_label = Label.new()
	_profile_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_profile_name_label.add_theme_font_size_override("font_size", 16)
	_profile_name_label.modulate = Color(1.0, 0.85, 0.3)
	vbox.add_child(_profile_name_label)

	var skills_title := Label.new()
	skills_title.text = "====== SKILLS ======"
	skills_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skills_title.add_theme_font_size_override("font_size", 11)
	skills_title.modulate = Color(0.5, 0.5, 0.5)
	vbox.add_child(skills_title)

	_skill_attack_label = Label.new()
	_skill_attack_label.add_theme_font_size_override("font_size", 13)
	_skill_attack_label.modulate = Color(0.9, 0.5, 0.4)
	vbox.add_child(_skill_attack_label)

	_skill_special_label = Label.new()
	_skill_special_label.add_theme_font_size_override("font_size", 13)
	_skill_special_label.modulate = Color(0.4, 0.7, 0.95)
	vbox.add_child(_skill_special_label)

	_skill_charge_label = Label.new()
	_skill_charge_label.add_theme_font_size_override("font_size", 13)
	_skill_charge_label.modulate = Color(1.0, 0.8, 0.3)
	vbox.add_child(_skill_charge_label)

	_skill_block_label = Label.new()
	_skill_block_label.add_theme_font_size_override("font_size", 13)
	_skill_block_label.modulate = Color(0.5, 0.8, 0.5)
	vbox.add_child(_skill_block_label)

	_session_stats_label = Label.new()
	_session_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_session_stats_label.add_theme_font_size_override("font_size", 12)
	_session_stats_label.modulate = Color(0.7, 0.7, 0.7)
	vbox.add_child(_session_stats_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	vbox.add_child(spacer)

	_resume_label = Label.new()
	_resume_label.text = "> RESUME"
	_resume_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_resume_label.add_theme_font_size_override("font_size", 24)
	vbox.add_child(_resume_label)

	_quit_menu_label = Label.new()
	_quit_menu_label.text = "  QUIT TO MENU"
	_quit_menu_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quit_menu_label.add_theme_font_size_override("font_size", 24)
	vbox.add_child(_quit_menu_label)

	_quit_game_label = Label.new()
	_quit_game_label.text = "  QUIT GAME"
	_quit_game_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quit_game_label.add_theme_font_size_override("font_size", 24)
	vbox.add_child(_quit_game_label)


func _process(delta: float) -> void:
	if _nav_cooldown > 0.0:
		_nav_cooldown -= delta


func _get_event_device(event: InputEvent) -> int:
	if event is InputEventKey:
		return -1
	return event.device


func _input(event: InputEvent) -> void:
	var device: int = _get_event_device(event)

	# START/Options button or Escape to toggle pause
	if event.is_action_pressed("pause") or event.is_action_pressed("ps_button"):
		if _active:
			# Only the player who paused can unpause
			if device == _owner_device:
				_unpause()
				get_viewport().set_input_as_handled()
		elif GameManager.current_state != GameManager.GameState.TITLE:
			_owner_device = device
			_pause()
			get_viewport().set_input_as_handled()
		return

	if not _active:
		return

	# Only the player who paused can navigate the menu
	if device != _owner_device:
		return

	# Navigation with cooldown to prevent too-fast scrolling
	if _nav_cooldown > 0.0:
		return

	if event.is_action_pressed("move_up") or event.is_action_pressed("move_left"):
		if _selected > 0:
			_selected -= 1
			_nav_cooldown = NAV_COOLDOWN_TIME
			AudioManager.play("menu_select")
			_update_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down") or event.is_action_pressed("move_right"):
		if _selected < 2:
			_selected += 1
			_nav_cooldown = NAV_COOLDOWN_TIME
			AudioManager.play("menu_select")
			_update_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("attack") or event.is_action_pressed("jump"):
		AudioManager.play("menu_confirm")
		_confirm()
		get_viewport().set_input_as_handled()


func _pause() -> void:
	if GameManager.current_state == GameManager.GameState.TITLE:
		return
	AudioManager.play("pause")
	_active = true
	_selected = 0
	_nav_cooldown = 0.3  # Brief cooldown so the pause press doesn't immediately navigate
	_update_selection()
	_update_profile_stats()
	visible = true
	get_tree().paused = true


func _update_profile_stats() -> void:
	# Find which player paused (by device)
	var pauser_index: int = -1
	for pi: int in PlayerManager.players:
		var p: Dictionary = PlayerManager.players[pi]
		if p.get("device_id", -99) == _owner_device:
			pauser_index = pi
			break
	if pauser_index < 0 and not PlayerManager.players.is_empty():
		# Fallback to first player
		pauser_index = PlayerManager.players.keys()[0]

	if pauser_index < 0:
		_hide_stats()
		return

	var profile: Dictionary = ProfileManager.get_active_profile(pauser_index)
	var p_data: Dictionary = PlayerManager.get_player(pauser_index)

	if profile.is_empty() or p_data.is_empty():
		_hide_stats()
		return

	var char_class: int = int(p_data.get("character_class", 0))
	var class_key: String = str(char_class)
	var class_names: Dictionary = {
		0: "Melee", 1: "Ranged", 2: "Mage", 3: "Summoner",
		4: "Rogue", 5: "Demolitionist", 6: "Healer",
	}
	var class_name_str: String = class_names.get(char_class, "???")
	var overall_lv: int = ProfileManager.get_overall_level(profile, class_key)
	var pname: String = profile.get("name", "Player")

	_profile_name_label.text = pname + " - " + class_name_str + " Lv." + str(overall_lv)
	_profile_name_label.visible = true

	# Get skill XP data
	var class_data: Dictionary = profile.get("per_class", {}).get(class_key, {})
	var skill_xp: Dictionary = class_data.get("skill_xp", {"attack": 0, "special": 0, "charge": 0, "block": 0})

	_skill_attack_label.text = _format_skill_bar("Attack ", skill_xp.get("attack", 0))
	_skill_attack_label.visible = true
	_skill_special_label.text = _format_skill_bar("Special", skill_xp.get("special", 0))
	_skill_special_label.visible = true
	_skill_charge_label.text = _format_skill_bar("Charge ", skill_xp.get("charge", 0))
	_skill_charge_label.visible = true
	_skill_block_label.text = _format_skill_bar("Block  ", skill_xp.get("block", 0))
	_skill_block_label.visible = true

	# Session stats
	var muffins: int = p_data.get("muffin_count", 0) + GameManager.get_mini_muffin_count(pauser_index)
	var kills: int = class_data.get("total_kills", 0)
	_session_stats_label.text = "Muffins: " + str(muffins) + "  |  Kills: " + str(kills)
	_session_stats_label.visible = true


func _format_skill_bar(skill_name: String, xp: int) -> String:
	var level: int = ProfileManager.get_skill_level(xp)
	var max_level: int = ProfileManager.MAX_SKILL_LEVEL

	# Build a 10-segment bar
	var bar_segments: int = 10
	var filled: int = mini(int(level * bar_segments / max_level), bar_segments)
	if level > 0 and filled == 0:
		filled = 1
	var bar_str: String = ""
	for i in range(bar_segments):
		if i < filled:
			bar_str += "\u2588"  # Full block
		else:
			bar_str += "\u2591"  # Light shade
	var lv_str: String = "Lv.%2d" % level
	return "%s  %s  %s" % [skill_name, lv_str, bar_str]


func _hide_stats() -> void:
	if _profile_name_label:
		_profile_name_label.visible = false
	if _skill_attack_label:
		_skill_attack_label.visible = false
	if _skill_special_label:
		_skill_special_label.visible = false
	if _skill_charge_label:
		_skill_charge_label.visible = false
	if _skill_block_label:
		_skill_block_label.visible = false
	if _session_stats_label:
		_session_stats_label.visible = false


func _unpause() -> void:
	_active = false
	_owner_device = -99
	visible = false
	get_tree().paused = false


func _confirm() -> void:
	if _selected == 0:
		_unpause()
	elif _selected == 1:
		# Auto-save profiles before quitting to menu
		ProfileManager.auto_save()
		_unpause()
		GameManager.reset_game()
		PlayerManager.reset_all_players()
		get_tree().change_scene_to_file("res://scenes/ui/title_screen.tscn")
	elif _selected == 2:
		# Auto-save profiles before quitting game
		ProfileManager.auto_save()
		get_tree().quit()


func _update_selection() -> void:
	var labels := [_resume_label, _quit_menu_label, _quit_game_label]
	var texts := [" RESUME", " QUIT TO MENU", " QUIT GAME"]
	for i in range(labels.size()):
		if labels[i] == null:
			continue
		if i == _selected:
			labels[i].text = "> " + texts[i].strip_edges()
			labels[i].modulate = Color.WHITE
		else:
			labels[i].text = "  " + texts[i].strip_edges()
			labels[i].modulate = Color(0.5, 0.5, 0.5)
