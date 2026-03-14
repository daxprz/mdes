extends CanvasLayer

## Profile selection overlay - shown when a player joins.
## Lists existing profiles + "Create New" option.
## D-pad to navigate, X to select.

signal profile_selected(player_index: int, profile: Dictionary)
signal create_new_requested(player_index: int)

var _owner_device: int = -1
var _player_index: int = -1
var _selected: int = 0
var _active: bool = false
var _nav_cooldown: float = 0.0
const NAV_COOLDOWN_TIME := 0.2

var _labels: Array[Label] = []
var _entries: Array[Dictionary] = []  # profile dicts, last entry is "create new"
var _vbox: VBoxContainer = null


func setup(player_index: int, device_id: int) -> void:
	_player_index = player_index
	_owner_device = device_id
	_selected = 0
	_active = true
	visible = true
	_populate_list()
	_update_selection()


func _ready() -> void:
	layer = 105
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()


func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.name = "Overlay"
	overlay.anchors_preset = Control.PRESET_FULL_RECT
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.color = Color(0, 0, 0, 0.75)
	add_child(overlay)

	var panel := PanelContainer.new()
	panel.anchors_preset = Control.PRESET_CENTER
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -180
	panel.offset_right = 180
	panel.offset_top = -160
	panel.offset_bottom = 160

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.07, 0.15, 0.95)
	style.border_color = Color(0.7, 0.5, 0.2)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	_vbox = VBoxContainer.new()
	_vbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	_vbox.add_theme_constant_override("separation", 8)
	panel.add_child(_vbox)

	var title := Label.new()
	title.text = "SELECT PROFILE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.modulate = Color(1.0, 0.85, 0.3)
	_vbox.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	_vbox.add_child(spacer)


func _populate_list() -> void:
	# Clear old labels
	for lbl: Label in _labels:
		if is_instance_valid(lbl):
			lbl.queue_free()
	_labels.clear()
	_entries.clear()

	# Add existing profiles
	for profile: Dictionary in ProfileManager.profiles:
		_entries.append(profile)
		var lbl := Label.new()
		var pname: String = profile.get("name", "???")
		var last_played: String = profile.get("last_played", "")
		lbl.text = "  " + pname + "  (" + last_played + ")"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lbl.add_theme_font_size_override("font_size", 18)
		_vbox.add_child(lbl)
		_labels.append(lbl)

	# "Create New" entry
	_entries.append({})  # Empty dict signals "create new"
	var new_lbl := Label.new()
	new_lbl.text = "  + CREATE NEW PROFILE"
	new_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	new_lbl.add_theme_font_size_override("font_size", 18)
	new_lbl.modulate = Color(0.5, 1.0, 0.5)
	_vbox.add_child(new_lbl)
	_labels.append(new_lbl)

	# Add hint at bottom
	var hint := Label.new()
	hint.text = "D-Pad: navigate | X: select"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(0.5, 0.5, 0.5)
	_vbox.add_child(hint)


func _process(delta: float) -> void:
	if _nav_cooldown > 0.0:
		_nav_cooldown -= delta


func _input(event: InputEvent) -> void:
	if not _active:
		return

	var device: int = _get_event_device(event)
	if device != _owner_device:
		return

	if _nav_cooldown > 0.0:
		return

	if event.is_action_pressed("move_up"):
		if _selected > 0:
			_selected -= 1
			_nav_cooldown = NAV_COOLDOWN_TIME
			_update_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		if _selected < _entries.size() - 1:
			_selected += 1
			_nav_cooldown = NAV_COOLDOWN_TIME
			_update_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("attack") or event.is_action_pressed("jump"):
		_confirm_selection()
		get_viewport().set_input_as_handled()


func _get_event_device(event: InputEvent) -> int:
	if event is InputEventKey:
		return -1
	return event.device


func _update_selection() -> void:
	for i in range(_labels.size()):
		if _labels[i] == null or not is_instance_valid(_labels[i]):
			continue
		if i == _selected:
			var base_text: String = _labels[i].text.strip_edges()
			_labels[i].text = "> " + base_text
			if i == _labels.size() - 1:
				_labels[i].modulate = Color(0.5, 1.0, 0.5)
			else:
				_labels[i].modulate = Color.WHITE
		else:
			var base_text: String = _labels[i].text.strip_edges()
			if base_text.begins_with(">"):
				base_text = base_text.substr(1).strip_edges()
			_labels[i].text = "  " + base_text
			if i == _labels.size() - 1:
				_labels[i].modulate = Color(0.4, 0.7, 0.4)
			else:
				_labels[i].modulate = Color(0.6, 0.6, 0.6)


func _confirm_selection() -> void:
	if _selected < 0 or _selected >= _entries.size():
		return

	_active = false
	visible = false

	var entry: Dictionary = _entries[_selected]
	if entry.is_empty():
		# Create new
		create_new_requested.emit(_player_index)
	else:
		profile_selected.emit(_player_index, entry)
