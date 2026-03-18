extends CanvasLayer

## Pause menu — any player can control it.
## Simple: RESUME, QUIT TO MAIN MENU, QUIT GAME
## Supports: thumbstick, D-pad, and mouse selection.
## SEL while paused toggles debug mode.

var _selected := 0
var _active := false
var _nav_cooldown: float = 0.0
const NAV_COOLDOWN_TIME := 0.25

var _panel: PanelContainer
var _menu_labels: Array[Label] = []
var _menu_texts := ["RESUME", "QUIT TO MAIN MENU", "QUIT GAME"]


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
	_panel.offset_left = -140
	_panel.offset_right = 140
	_panel.offset_top = -100
	_panel.offset_bottom = 100

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
	vbox.add_theme_constant_override("separation", 16)
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer)

	# Create menu items with mouse support
	for i in range(_menu_texts.size()):
		var lbl := Label.new()
		lbl.text = "  " + _menu_texts[i]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 24)
		lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		var idx: int = i  # Capture for lambda
		lbl.mouse_entered.connect(func() -> void: _on_mouse_hover(idx))
		lbl.gui_input.connect(func(event: InputEvent) -> void: _on_label_input(event, idx))
		vbox.add_child(lbl)
		_menu_labels.append(lbl)


func _process(delta: float) -> void:
	if _nav_cooldown > 0.0:
		_nav_cooldown -= delta


func _input(event: InputEvent) -> void:
	# START/Options or Escape to toggle pause — any player
	if event.is_action_pressed("pause") or event.is_action_pressed("ps_button"):
		if _active:
			_unpause()
			get_viewport().set_input_as_handled()
		elif GameManager.current_state != GameManager.GameState.TITLE:
			_pause()
			get_viewport().set_input_as_handled()
		return

	if not _active:
		return

	# SEL while paused = toggle debug mode
	if event.is_action_pressed("debug_toggle"):
		PlayerHUD._debug_mode = not PlayerHUD._debug_mode
		get_viewport().set_input_as_handled()
		return

	# Thumbstick + D-pad navigation (both map to move_up/move_down)
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
		if _selected < _menu_labels.size() - 1:
			_selected += 1
			_nav_cooldown = NAV_COOLDOWN_TIME
			AudioManager.play("menu_select")
			_update_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("attack") or event.is_action_pressed("jump"):
		AudioManager.play("menu_confirm")
		_confirm()
		get_viewport().set_input_as_handled()


func _on_mouse_hover(index: int) -> void:
	if not _active:
		return
	if _selected != index:
		_selected = index
		AudioManager.play("menu_select")
		_update_selection()


func _on_label_input(event: InputEvent, index: int) -> void:
	if not _active:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_selected = index
		_update_selection()
		AudioManager.play("menu_confirm")
		_confirm()


func _pause() -> void:
	if GameManager.current_state == GameManager.GameState.TITLE:
		return
	AudioManager.play("pause")
	_active = true
	_selected = 0
	_nav_cooldown = 0.3
	_update_selection()
	visible = true
	get_tree().paused = true


func _unpause() -> void:
	_active = false
	visible = false
	get_tree().paused = false


func _update_selection() -> void:
	for i in range(_menu_labels.size()):
		if i == _selected:
			_menu_labels[i].text = "> " + _menu_texts[i]
			_menu_labels[i].modulate = Color.WHITE
		else:
			_menu_labels[i].text = "  " + _menu_texts[i]
			_menu_labels[i].modulate = Color(0.6, 0.6, 0.6)


func _confirm() -> void:
	if _selected == 0:
		_unpause()
	elif _selected == 1:
		ProfileManager.auto_save()
		var saved_choices: Dictionary = {}
		for pi in PlayerManager.players.keys():
			var p: Dictionary = PlayerManager.players[pi]
			saved_choices[pi] = {
				"device_id": p.get("device_id", -1),
				"character_class": p.get("character_class", 0),
			}
		PlayerManager.set_meta("saved_choices", saved_choices)
		_unpause()
		GameManager.reset_game()
		PlayerManager.reset_all_players()
		get_tree().change_scene_to_file("res://scenes/ui/title_screen.tscn")
	elif _selected == 2:
		ProfileManager.auto_save()
		get_tree().quit()
