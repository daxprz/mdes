extends CanvasLayer

## Debug Drawer — slide-out panel from left edge for configuring debug aspects.
## Ctrl+D toggles open/close. Ctrl+S saves profile while open.
## Shows filterable 2-level aspect tree with Visual/Textual toggles.

const SLIDE_SPEED := 1200.0
const ROW_HEIGHT := 18.0
const INDENT := 20.0
const HEADER_HEIGHT := 160.0  # Entity filter + global toggle + scale control area
const CHECKBOX_SIZE := 12.0
const GROUP_ARROW_SIZE := 8.0
var SCALE_PRESETS: Array[float] = [0.25, 0.5, 1.0, 2.0, 4.0]

var _active := false
var _panel_x: float = 0.0      # Current X offset (0 = fully visible)
var _panel_width: float = 360.0
var _panel: Control = null
var _scroll_offset: int = 0

# Filter text input
var _filter_text: String = ""
var _filter_focused: bool = false
var _id_filter_focused: bool = false
var _cursor_blink: float = 0.0

# Interaction state
var _hover_row: int = -1
var _visible_rows: Array[Dictionary] = []  # [{type, path, group, ...}]

# Scale slider state
var _scale_dragging: bool = false
var _scale_area_y: float = 110.0  # Updated by _draw_panel each frame
const SCALE_SLIDER_H := 28.0     # Height of scale control area
const SCALE_MIN := 0.1
const SCALE_MAX := 8.0


func _ready() -> void:
	layer = 109  # Below console (110), above game
	_panel_x = -_panel_width
	_panel = Control.new()
	_panel.name = "DebugDrawerPanel"
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.draw.connect(_draw_panel)
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_panel)


func toggle() -> void:
	_active = not _active
	if _active:
		# Opening drawer enables global debug
		DebugOverlay.global_enabled = true
		PlayerHUD._debug_mode = true
		_rebuild_visible_rows()


func is_open() -> bool:
	return _active


func _process(delta: float) -> void:
	var target_x: float = 0.0 if _active else -_panel_width
	if absf(_panel_x - target_x) > 1.0:
		_panel_x = lerpf(_panel_x, target_x, delta * 10.0)
		_panel.queue_redraw()
	elif _panel_x != target_x:
		_panel_x = target_x

	if _active:
		_cursor_blink += delta
		_panel.queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		# Ctrl+D toggles drawer
		if event.keycode == KEY_D and event.ctrl_pressed and not event.shift_pressed:
			toggle()
			get_viewport().set_input_as_handled()
			return

		# Ctrl+S saves while open
		if _active and event.keycode == KEY_S and event.ctrl_pressed:
			DebugOverlay.save_profile()
			get_viewport().set_input_as_handled()
			return

		if not _active:
			return

		# Text input for filter fields
		if _filter_focused:
			_handle_text_input(event, "_filter_text")
			get_viewport().set_input_as_handled()
			return
		if _id_filter_focused:
			_handle_id_input(event)
			get_viewport().set_input_as_handled()
			return

		# Escape closes drawer or unfocuses
		if event.keycode == KEY_ESCAPE:
			if _filter_focused or _id_filter_focused:
				_filter_focused = false
				_id_filter_focused = false
			else:
				toggle()
			get_viewport().set_input_as_handled()
			return

		# Scroll
		if event.keycode == KEY_PAGEUP:
			_scroll_offset = maxi(0, _scroll_offset - 10)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_PAGEDOWN:
			_scroll_offset += 10
			get_viewport().set_input_as_handled()

	# Mouse release — stop scale drag
	if _active and event is InputEventMouseButton and not event.pressed:
		if _scale_dragging:
			_scale_dragging = false
			get_viewport().set_input_as_handled()
			return

	# Mouse clicks
	if _active and event is InputEventMouseButton and event.pressed:
		var mx: float = event.position.x
		var my: float = event.position.y
		if mx < _panel_x or mx > _panel_x + _panel_width:
			# Click outside — unfocus any text field
			_filter_focused = false
			_id_filter_focused = false
			return
		_handle_click(mx - _panel_x, my)
		get_viewport().set_input_as_handled()

	# Mouse scroll
	if _active and event is InputEventMouseButton:
		if event.position.x >= _panel_x and event.position.x <= _panel_x + _panel_width:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
				_scroll_offset = maxi(0, _scroll_offset - 3)
				get_viewport().set_input_as_handled()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
				_scroll_offset += 3
				get_viewport().set_input_as_handled()

	# Mouse motion for hover and scale drag
	if _active and event is InputEventMouseMotion:
		if _scale_dragging:
			_handle_scale_drag(event.position.x)
			get_viewport().set_input_as_handled()
		elif event.position.x >= _panel_x and event.position.x <= _panel_x + _panel_width:
			_update_hover(event.position.y)


func _handle_text_input(event: InputEventKey, _field: String) -> void:
	if event.keycode == KEY_BACKSPACE:
		if _filter_text.length() > 0:
			_filter_text = _filter_text.substr(0, _filter_text.length() - 1)
			_rebuild_visible_rows()
	elif event.keycode == KEY_ENTER or event.keycode == KEY_TAB:
		_filter_focused = false
	elif event.keycode == KEY_ESCAPE:
		_filter_focused = false
	elif event.unicode > 0 and not event.ctrl_pressed:
		_filter_text += char(event.unicode)
		_rebuild_visible_rows()


func _handle_id_input(event: InputEventKey) -> void:
	if event.keycode == KEY_BACKSPACE:
		var p: String = DebugOverlay.entity_id_pattern
		if p.length() > 0:
			DebugOverlay.entity_id_pattern = p.substr(0, p.length() - 1)
	elif event.keycode == KEY_ENTER or event.keycode == KEY_TAB:
		_id_filter_focused = false
	elif event.keycode == KEY_ESCAPE:
		_id_filter_focused = false
	elif event.unicode > 0 and not event.ctrl_pressed:
		DebugOverlay.entity_id_pattern += char(event.unicode)


# -- Row Building --------------------------------------------------------------

func _rebuild_visible_rows() -> void:
	_visible_rows.clear()
	var groups: Array[String] = DebugOverlay.get_aspect_groups()
	var filter_lower: String = _filter_text.to_lower()

	for group in groups:
		var aspects: Array[String] = DebugOverlay.get_aspects_in_group(group)
		var matching_aspects: Array[String] = []

		for path in aspects:
			if filter_lower == "" or filter_lower in path.to_lower():
				matching_aspects.append(path)

		if matching_aspects.is_empty():
			continue

		# Group header row
		var collapsed: bool = DebugOverlay.collapsed_groups.get(group, false)
		_visible_rows.append({
			"type": "group",
			"group": group,
			"collapsed": collapsed,
			"aspects": matching_aspects,
		})

		if collapsed:
			continue

		# Aspect rows
		for path in matching_aspects:
			var info: DebugOverlay.AspectInfo = DebugOverlay.get_aspect(path)
			_visible_rows.append({
				"type": "aspect",
				"path": path,
				"info": info,
			})


# -- Click Handling ------------------------------------------------------------

func _handle_click(lx: float, my: float) -> void:
	# Check filter text field click
	if my >= 8 and my <= 28:
		_filter_focused = true
		_id_filter_focused = false
		return

	# Check entity type filter checkboxes (y ~ 38-55)
	if my >= 36 and my <= 56:
		_handle_type_filter_click(lx)
		_filter_focused = false
		_id_filter_focused = false
		return

	# Check entity ID field click (y ~ 58-78)
	if my >= 58 and my <= 78:
		_id_filter_focused = true
		_filter_focused = false
		return

	# Check global toggle (y ~ 88-108)
	if my >= 88 and my <= 108:
		DebugOverlay.global_enabled = not DebugOverlay.global_enabled
		# Sync legacy
		PlayerHUD._debug_mode = DebugOverlay.global_enabled
		_filter_focused = false
		_id_filter_focused = false
		return

	# Check scale control area
	if my >= _scale_area_y and my < _scale_area_y + SCALE_SLIDER_H:
		_filter_focused = false
		_id_filter_focused = false
		_handle_scale_click(lx, my)
		return

	_filter_focused = false
	_id_filter_focused = false

	# Aspect tree area
	var tree_y_start: float = HEADER_HEIGHT
	var row_idx: int = int((my - tree_y_start) / ROW_HEIGHT) + _scroll_offset
	if row_idx < 0 or row_idx >= _visible_rows.size():
		return

	var row: Dictionary = _visible_rows[row_idx]

	if row["type"] == "group":
		# Check if clicking V or T column headers
		var v_col_x: float = _panel_width - 60
		var t_col_x: float = _panel_width - 30
		if lx >= v_col_x - 8 and lx < t_col_x - 8:
			# Toggle group visual
			var aspects: Array[String] = row["aspects"]
			var any_on: bool = false
			for path in aspects:
				var state: Array = DebugOverlay.get_observer_state(path, "human")
				if state[0]:
					any_on = true
					break
			DebugOverlay.set_group_visual(row["group"], not any_on)
		elif lx >= t_col_x - 8:
			# Cycle group textual
			var aspects: Array[String] = row["aspects"]
			# Find current max textual mode
			var max_txt: int = DebugOverlay.TextMode.NONE
			for path in aspects:
				var state: Array = DebugOverlay.get_observer_state(path, "human")
				if state[1] > max_txt:
					max_txt = state[1]
			var next_txt: int = _cycle_text_mode(max_txt)
			DebugOverlay.set_group_textual(row["group"], next_txt)
		else:
			# Toggle collapse
			var collapsed: bool = not row["collapsed"]
			DebugOverlay.collapsed_groups[row["group"]] = collapsed
			_rebuild_visible_rows()

	elif row["type"] == "aspect":
		var v_col_x: float = _panel_width - 60
		var t_col_x: float = _panel_width - 30
		var path: String = row["path"]
		var state: Array = DebugOverlay.get_observer_state(path, "human")

		if lx >= v_col_x - 8 and lx < t_col_x - 8:
			# Toggle visual
			DebugOverlay.set_observer(path, "human", not state[0], state[1])
		elif lx >= t_col_x - 8:
			# Cycle textual
			var next_txt: int = _cycle_text_mode(state[1])
			DebugOverlay.set_observer(path, "human", state[0], next_txt)


func _handle_type_filter_click(lx: float) -> void:
	# Type checkboxes laid out horizontally after "Types:" label
	var types: Array[String] = ["monster", "dummy", "attacker"]
	var start_x: float = 50.0
	var spacing: float = 80.0
	for i in range(types.size()):
		var cx: float = start_x + i * spacing
		if lx >= cx and lx < cx + spacing:
			var t: String = types[i]
			DebugOverlay.entity_type_filter[t] = not DebugOverlay.entity_type_filter.get(t, true)
			return


func _get_selected_monster() -> Node2D:
	## Returns the TAB-selected enemy if it has creature_scale, else null.
	var sel: Node2D = PlayerHUD.debug_selected_enemy
	if is_instance_valid(sel) and "creature_scale" in sel:
		return sel
	return null


func _handle_scale_click(lx: float, _my: float) -> void:
	var monster: Node2D = _get_selected_monster()
	if not monster:
		return
	var slider_x: float = 70.0
	var slider_w: float = _panel_width - 90.0
	# Check preset buttons (right side)
	var presets_x: float = slider_x + slider_w + 6
	# If clicking on the slider track, start drag or snap
	if lx >= slider_x and lx <= slider_x + slider_w:
		var t: float = clampf((lx - slider_x) / slider_w, 0.0, 1.0)
		# Map [0,1] → [SCALE_MIN, SCALE_MAX] logarithmic
		var new_scale: float = _slider_t_to_scale(t)
		monster.creature_scale = new_scale
		_scale_dragging = true
		_reinit_monster(monster)


func _handle_scale_drag(mx: float) -> void:
	var monster: Node2D = _get_selected_monster()
	if not monster:
		_scale_dragging = false
		return
	var lx: float = mx - _panel_x
	var slider_x: float = 70.0
	var slider_w: float = _panel_width - 90.0
	var t: float = clampf((lx - slider_x) / slider_w, 0.0, 1.0)
	var new_scale: float = _slider_t_to_scale(t)
	monster.creature_scale = new_scale
	_reinit_monster(monster)


func _slider_t_to_scale(t: float) -> float:
	## Map slider position [0,1] to scale value using log scale.
	## 0.0 → SCALE_MIN, 0.5 → 1.0, 1.0 → SCALE_MAX
	var log_min: float = log(SCALE_MIN)
	var log_max: float = log(SCALE_MAX)
	return exp(lerpf(log_min, log_max, t))


func _scale_to_slider_t(scale: float) -> float:
	## Map scale value to slider position [0,1] using log scale.
	var log_min: float = log(SCALE_MIN)
	var log_max: float = log(SCALE_MAX)
	var log_s: float = log(clampf(scale, SCALE_MIN, SCALE_MAX))
	return (log_s - log_min) / (log_max - log_min)


func _reinit_monster(monster: Node2D) -> void:
	## Re-initialize skeleton, collision, hitboxes at the new scale.
	if monster.has_method("_init_skeleton"):
		monster._init_skeleton()
	if monster.has_method("_init_collision"):
		# Remove old collision shape, re-create
		if "_body_collision" in monster and is_instance_valid(monster._body_collision):
			monster._body_collision.queue_free()
		monster._init_collision()
	# Hitboxes and attach points are positioned per-frame, no re-init needed


func _cycle_text_mode(current: int) -> int:
	match current:
		DebugOverlay.TextMode.NONE: return DebugOverlay.TextMode.LOG
		DebugOverlay.TextMode.LOG: return DebugOverlay.TextMode.CONSOLE
		DebugOverlay.TextMode.CONSOLE: return DebugOverlay.TextMode.BOTH
		DebugOverlay.TextMode.BOTH: return DebugOverlay.TextMode.NONE
	return DebugOverlay.TextMode.NONE


func _update_hover(my: float) -> void:
	var tree_y_start: float = HEADER_HEIGHT
	var row_idx: int = int((my - tree_y_start) / ROW_HEIGHT) + _scroll_offset
	_hover_row = row_idx


# -- Drawing -------------------------------------------------------------------

func _draw_panel() -> void:
	if _panel_x <= -_panel_width + 1:
		return

	var vp: Vector2 = get_viewport().get_visible_rect().size
	var font: Font = ThemeDB.fallback_font
	var pw: float = _panel_width
	var ph: float = vp.y

	# Background
	_panel.draw_rect(Rect2(_panel_x, 0, pw, ph), Color(0.06, 0.06, 0.09, 0.95))
	# Right border
	_panel.draw_line(Vector2(_panel_x + pw, 0), Vector2(_panel_x + pw, ph), Color(0.2, 0.6, 1.0, 0.5), 2.0)

	var x: float = _panel_x + 8
	var y: float = 8.0

	# -- Filter field --
	var filter_bg: Color = Color(0.12, 0.12, 0.16) if _filter_focused else Color(0.08, 0.08, 0.12)
	_panel.draw_rect(Rect2(x, y, pw - 16, 20), filter_bg)
	var filter_display: String = _filter_text
	if _filter_focused and int(_cursor_blink * 2) % 2 == 0:
		filter_display += "_"
	if filter_display == "" and not _filter_focused:
		filter_display = "Filter aspects..."
		_panel.draw_string(font, Vector2(x + 4, y + 14), filter_display, HORIZONTAL_ALIGNMENT_LEFT, pw - 24, 10, Color(0.4, 0.4, 0.4))
	else:
		_panel.draw_string(font, Vector2(x + 4, y + 14), filter_display, HORIZONTAL_ALIGNMENT_LEFT, pw - 24, 10, Color(0.8, 0.8, 0.8))
	y += 26

	# -- Entity type filter --
	_panel.draw_string(font, Vector2(x, y + 12), "Types:", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.6, 0.6))
	var types: Array[String] = ["monster", "dummy", "attacker"]
	var type_x: float = x + 50
	for t in types:
		var enabled: bool = DebugOverlay.entity_type_filter.get(t, true)
		_draw_checkbox(type_x, y + 2, enabled)
		var tcol: Color = Color(0.8, 0.8, 0.8) if enabled else Color(0.4, 0.4, 0.4)
		_panel.draw_string(font, Vector2(type_x + 16, y + 13), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, tcol)
		type_x += 80
	y += 22

	# -- Entity ID filter --
	var id_bg: Color = Color(0.12, 0.12, 0.16) if _id_filter_focused else Color(0.08, 0.08, 0.12)
	_panel.draw_string(font, Vector2(x, y + 12), "ID:", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.6, 0.6))
	_panel.draw_rect(Rect2(x + 30, y, pw - 46, 18), id_bg)
	var id_display: String = DebugOverlay.entity_id_pattern
	if _id_filter_focused and int(_cursor_blink * 2) % 2 == 0:
		id_display += "_"
	_panel.draw_string(font, Vector2(x + 34, y + 13), id_display, HORIZONTAL_ALIGNMENT_LEFT, pw - 54, 10, Color(0.8, 0.8, 0.8))
	y += 22

	# -- Global toggle --
	var global_on: bool = DebugOverlay.global_enabled
	var global_col: Color = Color(0.3, 1.0, 0.3) if global_on else Color(0.5, 0.5, 0.5)
	_panel.draw_line(Vector2(x, y + 2), Vector2(x + pw - 16, y + 2), Color(0.3, 0.3, 0.3), 1.0)
	y += 6
	_draw_checkbox(x, y, global_on)
	_panel.draw_string(font, Vector2(x + 18, y + 12), "Global Debug", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, global_col)
	var save_hint: String = "Ctrl+S save" if _active else ""
	_panel.draw_string(font, Vector2(_panel_x + pw - 90, y + 12), save_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.4, 0.4))
	y += 20

	# -- Scale control --
	_panel.draw_line(Vector2(x, y), Vector2(x + pw - 16, y), Color(0.3, 0.3, 0.3), 1.0)
	y += 4
	_scale_area_y = y  # Track for click detection
	var monster: Node2D = _get_selected_monster()
	if monster:
		var cur_scale: float = monster.creature_scale
		var label_col := Color(0.5, 0.9, 0.5)
		_panel.draw_string(font, Vector2(x, y + 12), "Scale:", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, label_col)
		# Slider track
		var slider_x: float = x + 62
		var slider_w: float = pw - 90.0
		var slider_y: float = y + 8
		_panel.draw_rect(Rect2(slider_x, slider_y - 2, slider_w, 4), Color(0.2, 0.2, 0.25))
		# Tick marks at preset values
		for preset in SCALE_PRESETS:
			var tick_t: float = _scale_to_slider_t(preset)
			var tick_x: float = slider_x + tick_t * slider_w
			_panel.draw_line(Vector2(tick_x, slider_y - 5), Vector2(tick_x, slider_y + 5), Color(0.35, 0.35, 0.4), 1.0)
		# 1.0 tick highlighted
		var one_t: float = _scale_to_slider_t(1.0)
		var one_x: float = slider_x + one_t * slider_w
		_panel.draw_line(Vector2(one_x, slider_y - 6), Vector2(one_x, slider_y + 6), Color(0.5, 0.7, 1.0, 0.6), 1.0)
		# Thumb
		var thumb_t: float = _scale_to_slider_t(cur_scale)
		var thumb_x: float = slider_x + thumb_t * slider_w
		var thumb_col := Color(0.3, 1.0, 0.5) if _scale_dragging else Color(0.5, 0.9, 0.5)
		_panel.draw_circle(Vector2(thumb_x, slider_y), 6.0, thumb_col)
		# Value text
		_panel.draw_string(font, Vector2(_panel_x + pw - 48, y + 13), "%.2f" % cur_scale, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, label_col)
	else:
		_panel.draw_string(font, Vector2(x, y + 12), "Scale: (TAB-select a monster)", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.4, 0.4, 0.4))
	y += SCALE_SLIDER_H

	# -- Column headers --
	var v_col_x: float = _panel_x + pw - 60
	var t_col_x: float = _panel_x + pw - 30
	_panel.draw_string(font, Vector2(v_col_x - 2, y + 10), "V", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.5, 0.7, 1.0))
	_panel.draw_string(font, Vector2(t_col_x - 2, y + 10), "T", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.5, 0.7, 1.0))
	_panel.draw_line(Vector2(x, y + 14), Vector2(x + pw - 16, y + 14), Color(0.25, 0.25, 0.3), 1.0)
	y += 16

	# -- Aspect tree --
	if _visible_rows.is_empty():
		_rebuild_visible_rows()

	var tree_y_start: float = y
	var max_visible: int = int((ph - tree_y_start - 8) / ROW_HEIGHT)
	var end_idx: int = mini(_scroll_offset + max_visible, _visible_rows.size())

	for ri in range(_scroll_offset, end_idx):
		var row: Dictionary = _visible_rows[ri]
		var ry: float = tree_y_start + (ri - _scroll_offset) * ROW_HEIGHT
		var is_hovered: bool = (ri == _hover_row)

		if is_hovered:
			_panel.draw_rect(Rect2(_panel_x, ry, pw, ROW_HEIGHT), Color(0.15, 0.15, 0.2))

		if row["type"] == "group":
			_draw_group_row(row, x, ry, v_col_x, t_col_x, font)
		elif row["type"] == "aspect":
			_draw_aspect_row(row, x, ry, v_col_x, t_col_x, font)

	# Scroll indicator
	if _visible_rows.size() > max_visible:
		var pct: float = float(_scroll_offset) / float(_visible_rows.size() - max_visible)
		var bar_h: float = maxf(20.0, ph * float(max_visible) / float(_visible_rows.size()))
		var bar_y: float = tree_y_start + pct * (ph - tree_y_start - bar_h)
		_panel.draw_rect(Rect2(_panel_x + pw - 4, bar_y, 3, bar_h), Color(0.3, 0.3, 0.4, 0.5))


func _draw_group_row(row: Dictionary, x: float, ry: float, v_col_x: float, t_col_x: float, font: Font) -> void:
	var collapsed: bool = row["collapsed"]
	var group: String = row["group"]
	var aspects: Array[String] = row["aspects"]

	# Collapse arrow
	var arrow_x: float = x + 2
	var arrow_y: float = ry + ROW_HEIGHT * 0.5
	if collapsed:
		# Right-pointing triangle ▶
		var pts := PackedVector2Array([
			Vector2(arrow_x, arrow_y - 5),
			Vector2(arrow_x + 7, arrow_y),
			Vector2(arrow_x, arrow_y + 5),
		])
		_panel.draw_polygon(pts, PackedColorArray([Color(0.5, 0.5, 0.6), Color(0.5, 0.5, 0.6), Color(0.5, 0.5, 0.6)]))
	else:
		# Down-pointing triangle ▼
		var pts := PackedVector2Array([
			Vector2(arrow_x, arrow_y - 4),
			Vector2(arrow_x + 8, arrow_y - 4),
			Vector2(arrow_x + 4, arrow_y + 4),
		])
		_panel.draw_polygon(pts, PackedColorArray([Color(0.5, 0.7, 1.0), Color(0.5, 0.7, 1.0), Color(0.5, 0.7, 1.0)]))

	# Group name
	_panel.draw_string(font, Vector2(x + 14, ry + 13), group, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.7, 1.0))

	# Group-level V/T indicators (aggregate)
	var any_vis: bool = false
	var any_txt: int = DebugOverlay.TextMode.NONE
	for path in aspects:
		var state: Array = DebugOverlay.get_observer_state(path, "human")
		if state[0]:
			any_vis = true
		if state[1] > any_txt:
			any_txt = state[1]
	_draw_checkbox(v_col_x - 4, ry + 2, any_vis)
	_draw_text_mode_indicator(t_col_x - 4, ry + 2, any_txt, font)


func _draw_aspect_row(row: Dictionary, x: float, ry: float, v_col_x: float, t_col_x: float, font: Font) -> void:
	var path: String = row["path"]
	var info: DebugOverlay.AspectInfo = row["info"]
	var state: Array = DebugOverlay.get_observer_state(path, "human")
	var visual_on: bool = state[0]
	var textual: int = state[1]

	# Actualized state (union of all observers)
	var actual_vis: bool = info._actual_visual
	var actual_txt: int = info._actual_textual

	# Sub-aspect name (indented)
	var label: String = info.sub if info.sub != "" else info.group
	var label_col: Color = Color(0.75, 0.75, 0.75) if actual_vis or actual_txt != DebugOverlay.TextMode.NONE else Color(0.4, 0.4, 0.4)

	# Show non-human observer indicator
	var has_other_observers: bool = false
	for obs_id in info.observers:
		if obs_id != "human":
			has_other_observers = true
			break

	if has_other_observers:
		label_col = Color(0.6, 0.8, 1.0) if not visual_on and textual == DebugOverlay.TextMode.NONE else label_col
		# Small dot to indicate other observers
		_panel.draw_circle(Vector2(x + INDENT + 2, ry + ROW_HEIGHT * 0.5), 2.0, Color(0.3, 0.6, 1.0, 0.7))

	_panel.draw_string(font, Vector2(x + INDENT + 6, ry + 13), label, HORIZONTAL_ALIGNMENT_LEFT, int(v_col_x - x - INDENT - 14), 9, label_col)

	# Visual checkbox
	_draw_checkbox(v_col_x - 4, ry + 2, visual_on)
	# If another observer has visual, show border highlight
	if actual_vis and not visual_on:
		_panel.draw_rect(Rect2(v_col_x - 4, ry + 2, CHECKBOX_SIZE, CHECKBOX_SIZE), Color(0.3, 0.6, 1.0, 0.5), false, 1.0)

	# Textual mode indicator
	_draw_text_mode_indicator(t_col_x - 4, ry + 2, textual, font)
	if actual_txt != DebugOverlay.TextMode.NONE and textual == DebugOverlay.TextMode.NONE:
		_panel.draw_rect(Rect2(t_col_x - 4, ry + 2, CHECKBOX_SIZE, CHECKBOX_SIZE), Color(0.3, 0.6, 1.0, 0.5), false, 1.0)


func _draw_checkbox(cx: float, cy: float, checked: bool) -> void:
	var box := Rect2(cx, cy, CHECKBOX_SIZE, CHECKBOX_SIZE)
	if checked:
		_panel.draw_rect(box, Color(0.2, 0.7, 0.3, 0.8))
		# Checkmark
		_panel.draw_line(Vector2(cx + 2, cy + 6), Vector2(cx + 5, cy + 10), Color.WHITE, 1.5)
		_panel.draw_line(Vector2(cx + 5, cy + 10), Vector2(cx + 10, cy + 2), Color.WHITE, 1.5)
	else:
		_panel.draw_rect(box, Color(0.2, 0.2, 0.25))
		_panel.draw_rect(box, Color(0.35, 0.35, 0.4), false, 1.0)


func _draw_text_mode_indicator(tx: float, ty: float, mode: int, font: Font) -> void:
	var box := Rect2(tx, ty, CHECKBOX_SIZE, CHECKBOX_SIZE)
	var label: String = ""
	var col: Color = Color(0.2, 0.2, 0.25)

	match mode:
		DebugOverlay.TextMode.NONE:
			_panel.draw_rect(box, col)
			_panel.draw_rect(box, Color(0.35, 0.35, 0.4), false, 1.0)
			return
		DebugOverlay.TextMode.LOG:
			label = "L"
			col = Color(0.2, 0.5, 0.7, 0.8)
		DebugOverlay.TextMode.CONSOLE:
			label = "C"
			col = Color(0.6, 0.4, 0.7, 0.8)
		DebugOverlay.TextMode.BOTH:
			label = "B"
			col = Color(0.7, 0.5, 0.2, 0.8)

	_panel.draw_rect(box, col)
	_panel.draw_string(font, Vector2(tx + 2, ty + 10), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
