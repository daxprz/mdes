extends CanvasLayer

## Music Drawer — slide-out panel from the right edge.
## Contains a mini-notation editor line at top, transport controls,
## and a pianoroll visualization below.
## Ctrl+M toggles open/close.

const SLIDE_SPEED := 1200.0
const PANEL_WIDTH := 420.0
const TOOLBAR_HEIGHT := 36.0
const EDITOR_HEIGHT := 32.0
const PIANOROLL_CYCLES := 4.0
const PIANOROLL_PLAYHEAD := 0.5  # Fraction of width where "now" is

var _active: bool = false
var _panel_x: float = 0.0      # Current X position of panel left edge
var _target_x: float = 0.0     # Target X for slide animation
var _panel: Control = null

# Editor state
var _editor_text: String = "c4 e4 g4 c5"
var _editor_cursor: int = 0
var _editor_focused: bool = true
var _cursor_blink: float = 0.0

# Playback state
var _is_playing: bool = false
var _cps: float = 0.5

# Pianoroll state
var _visible_haps: Array = []   # Haps currently visible in the pianoroll
var _current_time: float = 0.0  # Current cycle position for rendering

# Highlight state — which source locations are active right now
var _active_locations: Dictionary = {}  # "start:end" -> StrudelHap


func _ready() -> void:
	layer = 105  # Below console (110), above game
	_panel = Control.new()
	_panel.name = "MusicDrawerPanel"
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.draw.connect(_draw_panel)
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_panel)
	# Start hidden off the right edge
	var vp_w: float = get_viewport().get_visible_rect().size.x
	_panel_x = vp_w + 10
	_target_x = _panel_x


func toggle() -> void:
	_active = not _active
	_update_target_x()
	if _active and not _is_playing:
		_play_current()


func is_open() -> bool:
	return _active


func _update_target_x() -> void:
	var vp_w: float = get_viewport().get_visible_rect().size.x
	_target_x = vp_w - PANEL_WIDTH if _active else vp_w + 10


func _process(delta: float) -> void:
	_update_target_x()
	# Slide animation
	if absf(_panel_x - _target_x) > 1.0:
		_panel_x = lerpf(_panel_x, _target_x, delta * 8.0)
		_panel.queue_redraw()
	elif _panel_x != _target_x:
		_panel_x = _target_x

	if _active:
		_cursor_blink += delta
		# Update pianoroll from cyclist
		_update_pianoroll()
		_panel.queue_redraw()


func _input(event: InputEvent) -> void:
	# Ctrl+M toggles the music drawer
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_M and event.ctrl_pressed:
			toggle()
			get_viewport().set_input_as_handled()
			return

	if not _active or not _editor_focused:
		return

	if event is InputEventKey and event.pressed:
		var handled: bool = true
		match event.keycode:
			KEY_ENTER:
				_play_current()
			KEY_ESCAPE:
				toggle()
			KEY_BACKSPACE:
				if _editor_cursor > 0:
					_editor_text = _editor_text.substr(0, _editor_cursor - 1) + _editor_text.substr(_editor_cursor)
					_editor_cursor -= 1
			KEY_DELETE:
				if _editor_cursor < _editor_text.length():
					_editor_text = _editor_text.substr(0, _editor_cursor) + _editor_text.substr(_editor_cursor + 1)
			KEY_LEFT:
				_editor_cursor = maxi(0, _editor_cursor - 1)
			KEY_RIGHT:
				_editor_cursor = mini(_editor_text.length(), _editor_cursor + 1)
			KEY_HOME:
				_editor_cursor = 0
			KEY_END:
				_editor_cursor = _editor_text.length()
			KEY_A:
				if event.ctrl_pressed:
					_editor_cursor = 0
				else:
					handled = false
			KEY_E:
				if event.ctrl_pressed:
					_editor_cursor = _editor_text.length()
				else:
					handled = false
			KEY_SPACE:
				# Space is a valid mini-notation character
				_insert_char(" ")
			_:
				handled = false

		if handled:
			get_viewport().set_input_as_handled()
			return

		# Regular character input
		if event is InputEventKey and event.pressed and event.unicode > 0:
			var ch: String = char(event.unicode)
			if ch.length() == 1 and event.unicode >= 32:
				_insert_char(ch)
				get_viewport().set_input_as_handled()


func _insert_char(ch: String) -> void:
	_editor_text = _editor_text.substr(0, _editor_cursor) + ch + _editor_text.substr(_editor_cursor)
	_editor_cursor += ch.length()


# -- Playback ------------------------------------------------------------------

func _play_current() -> void:
	if _editor_text.strip_edges().is_empty():
		return
	var pat: StrudelPattern = StrudelMini.mini(_editor_text.strip_edges())
	MusicManager.strudel_play(pat, _cps)
	_is_playing = true
	# Collect leaf locations for highlighting
	_update_leaf_locations()


func _stop() -> void:
	MusicManager.strudel_stop()
	_is_playing = false
	_visible_haps.clear()
	_active_locations.clear()


func _update_leaf_locations() -> void:
	# Source locations are embedded in the pattern's hap contexts
	# They'll be extracted per-frame in _update_pianoroll
	pass


# -- Pianoroll Update ----------------------------------------------------------

func _update_pianoroll() -> void:
	if not MusicManager._cyclist or not MusicManager._strudel_playing:
		_visible_haps.clear()
		_current_time = 0.0
		return

	_current_time = MusicManager._cyclist.now()
	var lookbehind: float = PIANOROLL_CYCLES * PIANOROLL_PLAYHEAD
	var lookahead: float = PIANOROLL_CYCLES * (1.0 - PIANOROLL_PLAYHEAD)

	# Query pattern for visible haps
	var begin: float = maxf(_current_time - lookbehind, 0.0)
	var end: float = _current_time + lookahead
	if MusicManager._strudel_pattern:
		_visible_haps = MusicManager._strudel_pattern.query_arc(begin, end)
	else:
		_visible_haps.clear()

	# Update source highlighting
	_active_locations.clear()
	for hap in _visible_haps:
		if hap.whole == null:
			continue
		if not hap.is_active(_current_time):
			continue
		var locations: Array = hap.context.get("locations", [])
		for loc in locations:
			var key: String = "%d:%d" % [loc.get("start", 0), loc.get("end", 0)]
			if not _active_locations.has(key) or hap.w().begin.to_float() > _active_locations[key].w().begin.to_float():
				_active_locations[key] = hap


# -- Drawing -------------------------------------------------------------------

func _draw_panel() -> void:
	var font: Font = ThemeDB.fallback_font
	var vp_h: float = get_viewport().get_visible_rect().size.y
	var vp_w: float = get_viewport().get_visible_rect().size.x
	var px: float = _panel_x
	var pw: float = PANEL_WIDTH
	var ph: float = vp_h

	if px >= vp_w:
		return  # Off screen

	# Background
	_panel.draw_rect(Rect2(px, 0, pw, ph), Color(0.08, 0.08, 0.12, 0.95))

	# -- Toolbar --
	_panel.draw_rect(Rect2(px, 0, pw, TOOLBAR_HEIGHT), Color(0.12, 0.12, 0.18))

	# Play/Stop button
	var btn_x: float = px + 8.0
	var btn_y: float = 8.0
	var btn_color: Color = Color(0.3, 0.9, 0.3) if _is_playing else Color(0.7, 0.7, 0.7)
	if _is_playing:
		# Stop icon (square)
		_panel.draw_rect(Rect2(btn_x, btn_y, 16, 16), btn_color)
	else:
		# Play icon (triangle)
		_panel.draw_polygon(PackedVector2Array([
			Vector2(btn_x, btn_y),
			Vector2(btn_x + 16, btn_y + 8),
			Vector2(btn_x, btn_y + 16),
		]), PackedColorArray([btn_color, btn_color, btn_color]))

	# CPS display
	_panel.draw_string(font, Vector2(btn_x + 24, btn_y + 12), "cps=%.2f" % _cps,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.8, 1.0))

	# Title
	_panel.draw_string(font, Vector2(px + pw - 80, btn_y + 12), "Strudel",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 0.7, 1.0))

	# -- Editor Line --
	var ey: float = TOOLBAR_HEIGHT + 4.0
	_draw_editor_line(px + 8, ey, pw - 16, EDITOR_HEIGHT, font)

	# -- Pianoroll --
	var pr_y: float = ey + EDITOR_HEIGHT + 8.0
	var pr_h: float = ph - pr_y - 8.0
	if pr_h > 20:
		_draw_pianoroll(px + 4, pr_y, pw - 8, pr_h, font)


func _draw_editor_line(x: float, y: float, w: float, h: float, font: Font) -> void:
	## Draw the mini-notation text input with source highlighting.
	# Background
	_panel.draw_rect(Rect2(x, y, w, h), Color(0.05, 0.05, 0.08))
	# Border
	_panel.draw_rect(Rect2(x, y, w, h), Color(0.3, 0.3, 0.5), false, 1.0)

	var text_x: float = x + 4.0
	var text_y: float = y + h * 0.7
	var font_size: int = 14

	# Draw source highlights behind text
	for key in _active_locations:
		var parts: PackedStringArray = key.split(":")
		if parts.size() != 2:
			continue
		var loc_start: int = int(parts[0])
		var loc_end: int = int(parts[1])
		# Calculate pixel positions for the highlighted range
		var pre_text: String = _editor_text.substr(0, loc_start)
		var highlight_text: String = _editor_text.substr(loc_start, loc_end - loc_start)
		var pre_w: float = font.get_string_size(pre_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var hl_w: float = font.get_string_size(highlight_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var hap: StrudelHap = _active_locations[key]
		# Fade based on progress through the event
		var progress: float = 0.0
		if hap.whole != null:
			var dur: float = hap.get_duration().to_float()
			if dur > 0:
				progress = clampf((_current_time - hap.w().begin.to_float()) / dur, 0.0, 1.0)
		var alpha: float = lerpf(0.5, 0.1, progress)
		_panel.draw_rect(Rect2(text_x + pre_w, y + 2, hl_w, h - 4),
			Color(0.3, 0.6, 1.0, alpha))

	# Draw the text
	_panel.draw_string(font, Vector2(text_x, text_y), _editor_text,
		HORIZONTAL_ALIGNMENT_LEFT, w - 8, font_size, Color(0.9, 0.9, 0.95))

	# Draw cursor
	if _editor_focused and int(_cursor_blink * 2.0) % 2 == 0:
		var cursor_text: String = _editor_text.substr(0, _editor_cursor)
		var cursor_x: float = text_x + font.get_string_size(cursor_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		_panel.draw_line(Vector2(cursor_x, y + 3), Vector2(cursor_x, y + h - 3), Color(1.0, 0.8, 0.2), 1.5)


func _draw_pianoroll(x: float, y: float, w: float, h: float, font: Font) -> void:
	## Draw a scrolling pianoroll of visible haps.
	# Background
	_panel.draw_rect(Rect2(x, y, w, h), Color(0.04, 0.04, 0.06))

	if _visible_haps.is_empty():
		_panel.draw_string(font, Vector2(x + w * 0.3, y + h * 0.5), "No pattern",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.3, 0.3, 0.4))
		return

	# Determine value range (for Y axis mapping)
	var min_val: float = INF
	var max_val: float = -INF
	var values: Array = []
	for hap in _visible_haps:
		var v: float = _hap_to_pitch(hap)
		if v != -1:
			min_val = minf(min_val, v)
			max_val = maxf(max_val, v)
			if v not in values:
				values.append(v)
	if min_val == INF:
		return
	values.sort()

	# Fold mode: map unique values to Y slots
	var val_count: int = maxi(values.size(), 1)
	var bar_h: float = h / val_count

	# Time range
	var from_time: float = _current_time - PIANOROLL_CYCLES * PIANOROLL_PLAYHEAD
	var to_time: float = _current_time + PIANOROLL_CYCLES * (1.0 - PIANOROLL_PLAYHEAD)
	var time_range: float = to_time - from_time

	# Draw hap bars
	for hap in _visible_haps:
		if hap.whole == null:
			continue
		var pitch: float = _hap_to_pitch(hap)
		if pitch == -1:
			continue

		var is_active: bool = hap.is_active(_current_time)
		var hap_begin: float = hap.w().begin.to_float()
		var hap_end: float = hap.get_end_clipped().to_float()

		# Map to pixel coordinates
		var px_x: float = x + ((hap_begin - from_time) / time_range) * w
		var px_w: float = ((hap_end - hap_begin) / time_range) * w
		var val_idx: int = values.find(pitch)
		var px_y: float = y + h - (val_idx + 1) * bar_h

		# Clamp to panel bounds
		if px_x + px_w < x or px_x > x + w:
			continue
		px_x = maxf(px_x, x)
		px_w = minf(px_w, x + w - px_x)

		var color: Color = Color(0.3, 0.6, 1.0, 0.6) if not is_active else Color(1.0, 0.8, 0.2, 0.9)
		_panel.draw_rect(Rect2(px_x + 1, px_y + 1, maxf(px_w - 2, 1), bar_h - 2), color)

		# Label (note name) on active haps
		if is_active and bar_h > 8 and px_w > 20:
			var label: String = str(hap.value) if not (hap.value is Dictionary) else str(hap.value.get("note", hap.value.get("s", "")))
			_panel.draw_string(font, Vector2(px_x + 3, px_y + bar_h - 3), label,
				HORIZONTAL_ALIGNMENT_LEFT, px_w - 4, 9, Color(0, 0, 0, 0.8))

	# Playhead line
	var playhead_x: float = x + PIANOROLL_PLAYHEAD * w
	_panel.draw_line(Vector2(playhead_x, y), Vector2(playhead_x, y + h), Color(1.0, 1.0, 1.0, 0.6), 1.0)

	# Cycle markers (vertical grid)
	var cycle_start: int = int(ceilf(from_time))
	while cycle_start < to_time:
		var cx: float = x + ((cycle_start - from_time) / time_range) * w
		_panel.draw_line(Vector2(cx, y), Vector2(cx, y + h), Color(1.0, 1.0, 1.0, 0.1), 1.0)
		cycle_start += 1


static var _note_helper: StrudelSionTrigger = null

func _hap_to_pitch(hap: StrudelHap) -> float:
	## Convert a hap's value to a numeric pitch for Y-axis placement.
	if _note_helper == null:
		_note_helper = StrudelSionTrigger.new(null, null)
	var val: Variant = hap.value
	if val is int or val is float:
		return float(val)
	if val is String:
		var midi: int = _note_helper._note_name_to_midi(val)
		if midi >= 0:
			return float(midi)
	if val is Dictionary:
		if val.has("note"):
			var n_val: Variant = val["note"]
			if n_val is int or n_val is float:
				return float(n_val)
			if n_val is String:
				var midi: int = _note_helper._note_name_to_midi(n_val)
				if midi >= 0:
					return float(midi)
	return -1.0
