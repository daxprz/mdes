extends CanvasLayer

## Simple name entry overlay for profile creation.
## Controller: L1/R1 to change letter, Up/Down to cycle A-Z, X to confirm letter, START to finish.
## Keyboard: type directly, ENTER to finish.

signal name_confirmed(player_name: String)
signal cancelled

const MIN_LENGTH := 3
const MAX_LENGTH := 16
const ALPHABET := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

var _owner_device: int = -1
var _current_name: String = ""
var _current_letter_index: int = 0  # index into ALPHABET
var _name_label: Label = null
var _cursor_label: Label = null
var _hint_label: Label = null
var _active: bool = false
var _nav_cooldown: float = 0.0
const NAV_COOLDOWN_TIME := 0.15


func setup(device_id: int) -> void:
	_owner_device = device_id
	_current_name = ""
	_current_letter_index = 0
	_active = true
	visible = true
	_update_display()


func _ready() -> void:
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()


func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.name = "Overlay"
	overlay.anchors_preset = Control.PRESET_FULL_RECT
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.color = Color(0, 0, 0, 0.8)
	add_child(overlay)

	var vbox := VBoxContainer.new()
	vbox.anchors_preset = Control.PRESET_CENTER
	vbox.anchor_left = 0.5
	vbox.anchor_right = 0.5
	vbox.anchor_top = 0.5
	vbox.anchor_bottom = 0.5
	vbox.offset_left = -200
	vbox.offset_right = 200
	vbox.offset_top = -100
	vbox.offset_bottom = 100
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	add_child(vbox)

	var title := Label.new()
	title.text = "ENTER YOUR NAME"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.modulate = Color(1.0, 0.85, 0.3)
	vbox.add_child(title)

	_name_label = Label.new()
	_name_label.text = "_"
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 36)
	vbox.add_child(_name_label)

	_cursor_label = Label.new()
	_cursor_label.text = "[A]"
	_cursor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cursor_label.add_theme_font_size_override("font_size", 24)
	_cursor_label.modulate = Color(0.6, 0.8, 1.0)
	vbox.add_child(_cursor_label)

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 14)
	_hint_label.modulate = Color(0.6, 0.6, 0.6)
	_hint_label.text = "Up/Down: letter | X: add | START: confirm"
	vbox.add_child(_hint_label)


func _process(delta: float) -> void:
	if _nav_cooldown > 0.0:
		_nav_cooldown -= delta


func _input(event: InputEvent) -> void:
	if not _active:
		return

	var device: int = _get_event_device(event)

	# Keyboard typing
	if device == -1 and _owner_device == -1:
		if event is InputEventKey and event.pressed and not event.echo:
			var key_event: InputEventKey = event as InputEventKey
			# Enter/Return to finish
			if key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER:
				_finish()
				get_viewport().set_input_as_handled()
				return
			# Backspace to delete
			if key_event.keycode == KEY_BACKSPACE:
				if _current_name.length() > 0:
					_current_name = _current_name.substr(0, _current_name.length() - 1)
					_update_display()
				get_viewport().set_input_as_handled()
				return
			# Escape to cancel
			if key_event.keycode == KEY_ESCAPE:
				_cancel()
				get_viewport().set_input_as_handled()
				return
			# Type letter
			var unicode_char: String = char(key_event.unicode)
			if unicode_char.length() > 0 and key_event.unicode >= 32 and key_event.unicode < 127:
				if _current_name.length() < MAX_LENGTH:
					_current_name += unicode_char
					_update_display()
				get_viewport().set_input_as_handled()
			return

	# Controller input - only owner device
	if device != _owner_device:
		return

	if _nav_cooldown > 0.0:
		return

	# Up/Down to cycle letter
	if event.is_action_pressed("move_up"):
		_current_letter_index = (_current_letter_index - 1) % ALPHABET.length()
		if _current_letter_index < 0:
			_current_letter_index += ALPHABET.length()
		_nav_cooldown = NAV_COOLDOWN_TIME
		_update_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_current_letter_index = (_current_letter_index + 1) % ALPHABET.length()
		_nav_cooldown = NAV_COOLDOWN_TIME
		_update_display()
		get_viewport().set_input_as_handled()
	# L1/R1 also cycle letters (button 9 = L1, 10 = R1)
	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index == 9:
			_current_letter_index = (_current_letter_index - 1) % ALPHABET.length()
			if _current_letter_index < 0:
				_current_letter_index += ALPHABET.length()
			_nav_cooldown = NAV_COOLDOWN_TIME
			_update_display()
			get_viewport().set_input_as_handled()
		elif event.button_index == 10:
			_current_letter_index = (_current_letter_index + 1) % ALPHABET.length()
			_nav_cooldown = NAV_COOLDOWN_TIME
			_update_display()
			get_viewport().set_input_as_handled()
	# X (attack) to add letter
	elif event.is_action_pressed("attack") or event.is_action_pressed("jump"):
		if _current_name.length() < MAX_LENGTH:
			_current_name += ALPHABET[_current_letter_index]
			_update_display()
		get_viewport().set_input_as_handled()
	# Triangle (special) to delete last letter
	elif event.is_action_pressed("special"):
		if _current_name.length() > 0:
			_current_name = _current_name.substr(0, _current_name.length() - 1)
			_update_display()
		get_viewport().set_input_as_handled()
	# START to confirm
	elif event.is_action_pressed("ps_button"):
		_finish()
		get_viewport().set_input_as_handled()


func _get_event_device(event: InputEvent) -> int:
	if event is InputEventKey:
		return -1
	return event.device


func _update_display() -> void:
	if _name_label:
		if _current_name.is_empty():
			_name_label.text = "_"
		else:
			_name_label.text = _current_name
	if _cursor_label:
		_cursor_label.text = "[ " + ALPHABET[_current_letter_index] + " ]"
	if _hint_label:
		var count_text: String = "(%d/%d)" % [_current_name.length(), MAX_LENGTH]
		if _owner_device == -1:
			_hint_label.text = "Type name | ENTER: confirm | BACKSPACE: delete  " + count_text
		else:
			_hint_label.text = "Up/Down: letter | X: add | Triangle: delete | START: confirm  " + count_text


func _finish() -> void:
	if _current_name.strip_edges().length() < MIN_LENGTH:
		# Flash the label red briefly to indicate too short
		if _name_label:
			_name_label.modulate = Color.RED
			var tween := create_tween()
			tween.tween_property(_name_label, "modulate", Color.WHITE, 0.3)
		return

	_active = false
	visible = false
	name_confirmed.emit(_current_name.strip_edges())


func _cancel() -> void:
	_active = false
	visible = false
	cancelled.emit()
