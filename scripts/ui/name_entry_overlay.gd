extends CanvasLayer

## Name entry with A-Z grid selector for controller + direct keyboard typing.
## Pauses the game and blocks input to the entering player's character.

signal name_confirmed(player_name: String)
signal cancelled

const MIN_LENGTH := 3
const MAX_LENGTH := 16

# Grid layout: 7 columns, rows of characters
const GRID_CHARS: Array[String] = [
	"A", "B", "C", "D", "E", "F", "G",
	"H", "I", "J", "K", "L", "M", "N",
	"O", "P", "Q", "R", "S", "T", "U",
	"V", "W", "X", "Y", "Z", " ", "-",
	"0", "1", "2", "3", "4", "5", "6",
	"7", "8", "9", ".", "_", "!", "OK",
]
const GRID_COLS := 7
const GRID_ROWS := 6
const CELL_SIZE := 36
const CELL_MARGIN := 4
const BACKSPACE_LABEL := "<-"

var _owner_device: int = -1
var _current_name: String = ""
var _grid_x: int = 0
var _grid_y: int = 0
var _active: bool = false
var _nav_cooldown: float = 0.0
const NAV_COOLDOWN_TIME := 0.12

# UI references
var _name_label: Label = null
var _hint_label: Label = null
var _grid_container: Control = null
var _grid_cells: Array[Label] = []
var _backspace_label: Label = null


func setup(device_id: int) -> void:
	_owner_device = device_id
	_current_name = ""
	_grid_x = 0
	_grid_y = 0
	_active = true
	visible = true
	# Only pause if we're NOT on the title screen (title screen is already safe)
	if GameManager.current_state != GameManager.GameState.TITLE:
		get_tree().paused = true
	_update_display()
	_update_grid_highlight()


func _ready() -> void:
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()


func _build_ui() -> void:
	# Dark overlay
	var overlay := ColorRect.new()
	overlay.anchors_preset = Control.PRESET_FULL_RECT
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.color = Color(0, 0, 0, 0.85)
	add_child(overlay)

	# Main container
	var vbox := VBoxContainer.new()
	vbox.anchors_preset = Control.PRESET_CENTER
	vbox.anchor_left = 0.5
	vbox.anchor_right = 0.5
	vbox.anchor_top = 0.5
	vbox.anchor_bottom = 0.5
	vbox.offset_left = -180
	vbox.offset_right = 180
	vbox.offset_top = -200
	vbox.offset_bottom = 200
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)
	add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "ENTER YOUR NAME"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.modulate = Color(1.0, 0.85, 0.3)
	vbox.add_child(title)

	# Current name display
	_name_label = Label.new()
	_name_label.text = "_"
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 30)
	vbox.add_child(_name_label)

	# Character count
	var count_label := Label.new()
	count_label.name = "CountLabel"
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.add_theme_font_size_override("font_size", 12)
	count_label.modulate = Color(0.5, 0.5, 0.5)
	vbox.add_child(count_label)

	# Grid container
	_grid_container = Control.new()
	var grid_w: float = GRID_COLS * (CELL_SIZE + CELL_MARGIN)
	var grid_h: float = GRID_ROWS * (CELL_SIZE + CELL_MARGIN)
	_grid_container.custom_minimum_size = Vector2(grid_w, grid_h)
	_grid_container.size = Vector2(grid_w, grid_h)
	vbox.add_child(_grid_container)

	# Build grid cells
	_grid_cells.clear()
	for i in range(GRID_CHARS.size()):
		var row: int = i / GRID_COLS
		var col: int = i % GRID_COLS
		var cell := Label.new()
		cell.text = GRID_CHARS[i]
		cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cell.add_theme_font_size_override("font_size", 16)
		cell.position = Vector2(
			col * (CELL_SIZE + CELL_MARGIN),
			row * (CELL_SIZE + CELL_MARGIN)
		)
		cell.size = Vector2(CELL_SIZE, CELL_SIZE)

		# Background panel
		var bg := ColorRect.new()
		bg.name = "BG"
		bg.color = Color(0.2, 0.2, 0.25, 0.8)
		bg.size = Vector2(CELL_SIZE, CELL_SIZE)
		bg.position = Vector2.ZERO
		bg.z_index = -1
		cell.add_child(bg)

		# Mouse support
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		var ci: int = i  # Capture for lambda
		cell.mouse_entered.connect(func() -> void: _on_grid_mouse_hover(ci))
		cell.gui_input.connect(func(event: InputEvent) -> void: _on_grid_mouse_click(event, ci))

		_grid_container.add_child(cell)
		_grid_cells.append(cell)

	# Add backspace button below grid
	_backspace_label = Label.new()
	_backspace_label.text = "[BACKSPACE / Triangle]"
	_backspace_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_backspace_label.add_theme_font_size_override("font_size", 14)
	_backspace_label.modulate = Color(0.7, 0.5, 0.5)
	vbox.add_child(_backspace_label)

	# Hint
	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 11)
	_hint_label.modulate = Color(0.5, 0.5, 0.5)
	vbox.add_child(_hint_label)


func _process(delta: float) -> void:
	if _nav_cooldown > 0.0:
		_nav_cooldown -= delta


func _input(event: InputEvent) -> void:
	if not _active:
		return

	var device: int = _get_event_device(event)

	# --- Keyboard direct typing (any keyboard player) ---
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event: InputEventKey = event as InputEventKey

		# Enter to confirm
		if key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER:
			_finish()
			get_viewport().set_input_as_handled()
			return

		# Backspace to delete
		if key_event.keycode == KEY_BACKSPACE:
			_delete_last()
			get_viewport().set_input_as_handled()
			return

		# Escape to cancel
		if key_event.keycode == KEY_ESCAPE:
			_cancel()
			get_viewport().set_input_as_handled()
			return

		# Type any printable character directly
		var unicode_char: String = char(key_event.unicode)
		if unicode_char.length() > 0 and key_event.unicode >= 32 and key_event.unicode < 127:
			_add_character(unicode_char)
			get_viewport().set_input_as_handled()
		return

	# --- Controller grid navigation (only owner device) ---
	if device != _owner_device:
		return

	if _nav_cooldown > 0.0:
		return

	# D-pad / stick navigation
	if event.is_action_pressed("move_up"):
		_grid_y = (_grid_y - 1) % GRID_ROWS
		if _grid_y < 0:
			_grid_y += GRID_ROWS
		_clamp_grid()
		_nav_cooldown = NAV_COOLDOWN_TIME
		AudioManager.play("menu_select", -8.0)
		_update_grid_highlight()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_grid_y = (_grid_y + 1) % GRID_ROWS
		_clamp_grid()
		_nav_cooldown = NAV_COOLDOWN_TIME
		AudioManager.play("menu_select", -8.0)
		_update_grid_highlight()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_left"):
		_grid_x = (_grid_x - 1) % GRID_COLS
		if _grid_x < 0:
			_grid_x += GRID_COLS
		_nav_cooldown = NAV_COOLDOWN_TIME
		AudioManager.play("menu_select", -8.0)
		_update_grid_highlight()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_right"):
		_grid_x = (_grid_x + 1) % GRID_COLS
		_nav_cooldown = NAV_COOLDOWN_TIME
		AudioManager.play("menu_select", -8.0)
		_update_grid_highlight()
		get_viewport().set_input_as_handled()

	# X / Cross - select character from grid
	elif event.is_action_pressed("attack") or event.is_action_pressed("jump"):
		var idx: int = _grid_y * GRID_COLS + _grid_x
		if idx < GRID_CHARS.size():
			var selected: String = GRID_CHARS[idx]
			if selected == "OK":
				_finish()
			else:
				_add_character(selected)
				AudioManager.play("menu_confirm", -6.0)
		get_viewport().set_input_as_handled()

	# Triangle - delete last character
	elif event.is_action_pressed("special"):
		_delete_last()
		get_viewport().set_input_as_handled()

	# START - confirm name
	elif event.is_action_pressed("ps_button"):
		_finish()
		get_viewport().set_input_as_handled()


func _on_grid_mouse_hover(cell_index: int) -> void:
	if not _active:
		return
	_grid_x = cell_index % GRID_COLS
	_grid_y = cell_index / GRID_COLS
	_update_grid_highlight()


func _on_grid_mouse_click(event: InputEvent, cell_index: int) -> void:
	if not _active:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_grid_x = cell_index % GRID_COLS
		_grid_y = cell_index / GRID_COLS
		_update_grid_highlight()
		_select_current_cell()


func _select_current_cell() -> void:
	var idx: int = _grid_y * GRID_COLS + _grid_x
	if idx < 0 or idx >= GRID_CHARS.size():
		return
	var ch: String = GRID_CHARS[idx]
	if ch == "OK":
		_finish()
	else:
		_add_character(ch)
		AudioManager.play("menu_confirm", -6.0)


func _get_event_device(event: InputEvent) -> int:
	if event is InputEventKey:
		return -1
	return event.device


func _clamp_grid() -> void:
	var idx: int = _grid_y * GRID_COLS + _grid_x
	if idx >= GRID_CHARS.size():
		_grid_x = GRID_CHARS.size() % GRID_COLS - 1
		if _grid_x < 0:
			_grid_x = 0


func _add_character(ch: String) -> void:
	if _current_name.length() < MAX_LENGTH:
		_current_name += ch
		_update_display()


func _delete_last() -> void:
	if _current_name.length() > 0:
		_current_name = _current_name.substr(0, _current_name.length() - 1)
		AudioManager.play("menu_select", -4.0, 0.7)
		_update_display()


func _update_display() -> void:
	if _name_label:
		if _current_name.is_empty():
			_name_label.text = "_"
		else:
			_name_label.text = _current_name + "_"

	# Update count label
	var count_node := get_node_or_null("VBoxContainer/CountLabel")
	if count_node == null:
		# Try to find it via the vbox
		for child in get_children():
			if child is VBoxContainer:
				count_node = child.get_node_or_null("CountLabel")
				break
	if count_node and count_node is Label:
		(count_node as Label).text = "%d / %d characters" % [_current_name.length(), MAX_LENGTH]
		if _current_name.length() < MIN_LENGTH:
			(count_node as Label).modulate = Color(0.8, 0.4, 0.4)
		else:
			(count_node as Label).modulate = Color(0.4, 0.8, 0.4)

	if _hint_label:
		if _owner_device == -1:
			_hint_label.text = "Type name | ENTER: confirm | BACKSPACE: delete | ESC: cancel"
		else:
			_hint_label.text = "D-Pad: move | X: select | Triangle: delete | START: confirm"


func _update_grid_highlight() -> void:
	for i in range(_grid_cells.size()):
		var cell: Label = _grid_cells[i]
		var bg: ColorRect = cell.get_node_or_null("BG") as ColorRect
		if not bg:
			continue

		var row: int = i / GRID_COLS
		var col: int = i % GRID_COLS

		if row == _grid_y and col == _grid_x:
			# Highlighted cell
			bg.color = Color(0.3, 0.5, 0.9, 0.9)
			cell.modulate = Color.WHITE
			cell.add_theme_font_size_override("font_size", 18)
		else:
			bg.color = Color(0.2, 0.2, 0.25, 0.8)
			cell.modulate = Color(0.8, 0.8, 0.8)
			cell.add_theme_font_size_override("font_size", 16)

		# Special color for OK button
		if GRID_CHARS[i] == "OK":
			if row == _grid_y and col == _grid_x:
				bg.color = Color(0.2, 0.7, 0.3, 0.9)
			else:
				bg.color = Color(0.15, 0.4, 0.2, 0.8)


func _finish() -> void:
	var trimmed: String = _current_name.strip_edges()
	if trimmed.length() < MIN_LENGTH:
		if _name_label:
			_name_label.modulate = Color.RED
			var tween := create_tween()
			tween.tween_property(_name_label, "modulate", Color.WHITE, 0.3)
		return

	_active = false
	visible = false
	if get_tree().paused:
		get_tree().paused = false
	name_confirmed.emit(trimmed)


func _cancel() -> void:
	_active = false
	visible = false
	if get_tree().paused:
		get_tree().paused = false
	cancelled.emit()
