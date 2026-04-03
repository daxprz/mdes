extends CanvasLayer

## Music Drawer — slide-out panel from the right edge for live-coding music.
## Contains a Strudel mini-notation editor, transport controls, scrolling
## pianoroll, and source highlighting (active notes glow in the text).
##
## Toggle: Ctrl+M or RCON `musicdrawer` / `md`
##
## Keybindings:
##   Navigation:
##     Left / Right        — move cursor one character
##     Ctrl+Left / Right   — move cursor one word
##     Home / End          — beginning / end of line
##     Ctrl+A              — beginning of line (at start: select all)
##     Ctrl+E              — end of line
##   Selection:
##     Shift + any movement — extend selection
##   Editing:
##     Type                — insert at cursor (replaces selection)
##     Backspace           — delete char before cursor
##     Shift+Backspace     — delete word backward
##     Ctrl+Backspace      — delete word backward
##     Delete              — delete char after cursor
##     Ctrl+Delete         — delete word forward
##   Clipboard (OS):
##     Ctrl+C              — copy selection (or whole line)
##     Ctrl+X              — cut selection (or whole line)
##     Ctrl+V              — paste from clipboard
##   Kill ring (emacs):
##     Ctrl+K              — kill from cursor to end of line
##     Ctrl+U              — kill from cursor to beginning of line
##     Ctrl+W              — kill word backward
##     Ctrl+Y              — yank (paste from kill buffer)
##   Multi-line:
##     Enter               — new line below current
##     Ctrl+Enter          — evaluate all non-muted lines (play/hot-swap)
##     Up / Down           — move cursor between lines
##     Backspace at col 0  — join with previous line
##     Ctrl+Shift+K        — delete current line
##     Ctrl+/              — toggle mute on current line
##   Music:
##     Escape              — close drawer
##
## Line format:
##   Each line is an independent pattern. Non-muted lines are stacked on eval.
##   Lines support the Strudel label syntax:
##     drums: c4(3,8)                — named "drums"
##     bass: c2 ~ c2 ~ e2 ~ s=bass  — named "bass", voice override
##     c4 e4 g4 c5                   — auto-named "d1", "d2", etc.
##     # this is a comment           — skipped on eval
##   Muted lines (Ctrl+/) are dimmed and excluded from playback.

const SLIDE_SPEED := 1200.0
const PANEL_WIDTH := 420.0
const TOOLBAR_HEIGHT := 36.0
const LINE_HEIGHT := 24.0     # Height of each editor line
const MAX_VISIBLE_LINES := 8  # Max lines before scrolling
const PIANOROLL_CYCLES := 4.0
const PIANOROLL_PLAYHEAD := 0.5  # Fraction of width where "now" is

var _active: bool = false
var _panel_x: float = 0.0      # Current X position of panel left edge
var _target_x: float = 0.0     # Target X for slide animation
var _panel: Control = null

# Multi-line editor state — each line is a named, independently mutable pattern
# Line format: "name: pattern_text" or just "pattern_text" (auto-named d1, d2, ...)
var _lines: Array[Dictionary] = []  # [{text, name, muted}]
var _current_line: int = 0     # Which line the cursor is on
var _editor_cursor: int = 0    # Cursor position within the current line
var _editor_focused: bool = true
var _cursor_blink: float = 0.0
var _select_start: int = -1    # Selection anchor (-1 = no selection, within current line)
var _kill_buffer: String = ""  # Ctrl+K / Ctrl+Y kill ring
var _editor_scroll: int = 0    # First visible line index (for scrolling)

## Current line text (convenience accessor)
var _editor_text: String:
	get:
		if _current_line < _lines.size():
			return _lines[_current_line].get("text", "")
		return ""
	set(value):
		if _current_line < _lines.size():
			_lines[_current_line]["text"] = value


func _make_line(text: String = "", name: String = "", muted: bool = false) -> Dictionary:
	return {"text": text, "name": name, "muted": muted}


func _line_name(idx: int) -> String:
	## Get display name for a line. User-set name or default "d1", "d2", etc.
	if idx >= _lines.size():
		return "d%d" % (idx + 1)
	var n: String = _lines[idx].get("name", "")
	return n if not n.is_empty() else "d%d" % (idx + 1)


func _line_muted(idx: int) -> bool:
	if idx >= _lines.size():
		return false
	return _lines[idx].get("muted", false)

# Playback state
var _is_playing: bool = false
var _cps: float = 0.5

# Pianoroll state — rolling buffer (haps accumulate, old ones pruned)
var _visible_haps: Array = []   # Haps currently visible in the pianoroll
var _current_time: float = 0.0  # Current cycle position for rendering
var _last_query_end: float = 0.0  # Right edge of last query (only query new haps beyond this)

# Highlight state — which source locations are active right now
var _active_locations: Dictionary = {}  # "start:end" -> StrudelHap
var _debug_frame: int = 0               # Frame counter for throttled logging


func _ready() -> void:
	_lines = [_make_line("c4 e4 g4 c5")]
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
	# Sync drawer state with MusicManager — if strudel is already playing
	# (e.g. from RCON or title pattern), just observe, don't restart.
	if _active and MusicManager._strudel_playing:
		_is_playing = true
		# Reset rolling buffer so pianoroll fills from current position
		_visible_haps.clear()
		_last_query_end = 0.0
		DebugOverlay.log("strudel/pattern", null, "DRAWER: opened, syncing to cyclist at cycle %.2f" % (
			MusicManager._cyclist.now() if MusicManager._cyclist else 0.0))


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
		_debug_frame += 1
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
		var shift: bool = event.shift_pressed
		var ctrl: bool = event.ctrl_pressed or event.meta_pressed

		match event.keycode:
			KEY_ESCAPE:
				toggle()
				get_viewport().set_input_as_handled()

			KEY_ENTER:
				if ctrl:
					# Ctrl+Enter: evaluate all lines
					_play_current()
				else:
					# Enter: new line below current
					var tail: String = _editor_text.substr(_editor_cursor)
					_editor_text = _editor_text.substr(0, _editor_cursor)
					_current_line += 1
					_lines.insert(_current_line, _make_line(tail))
					_editor_cursor = 0
					_select_start = -1
					_ensure_cursor_visible()
				get_viewport().set_input_as_handled()

			KEY_BACKSPACE:
				if _has_selection():
					_delete_selection()
				elif ctrl or shift:
					var p: int = _word_boundary_left()
					_editor_text = _editor_text.substr(0, p) + _editor_text.substr(_editor_cursor)
					_editor_cursor = p
				elif _editor_cursor > 0:
					_editor_text = _editor_text.substr(0, _editor_cursor - 1) + _editor_text.substr(_editor_cursor)
					_editor_cursor -= 1
				elif _current_line > 0:
					# At column 0: join with previous line
					var prev_text: String = _lines[_current_line - 1].get("text", "")
					var prev_len: int = prev_text.length()
					_lines[_current_line - 1]["text"] = prev_text + _editor_text
					_lines.remove_at(_current_line)
					_current_line -= 1
					_editor_cursor = prev_len
					_ensure_cursor_visible()
				get_viewport().set_input_as_handled()

			KEY_DELETE:
				if _has_selection():
					_delete_selection()
				elif ctrl:
					# Ctrl+Delete: delete word forward
					var p: int = _word_boundary_right()
					_editor_text = _editor_text.substr(0, _editor_cursor) + _editor_text.substr(p)
				elif _editor_cursor < _editor_text.length():
					_editor_text = _editor_text.substr(0, _editor_cursor) + _editor_text.substr(_editor_cursor + 1)
				get_viewport().set_input_as_handled()

			KEY_LEFT:
				if ctrl:
					_move_cursor(_word_boundary_left(), shift)
				else:
					_move_cursor(maxi(0, _editor_cursor - 1), shift)
				get_viewport().set_input_as_handled()

			KEY_RIGHT:
				if ctrl:
					_move_cursor(_word_boundary_right(), shift)
				else:
					_move_cursor(mini(_editor_text.length(), _editor_cursor + 1), shift)
				get_viewport().set_input_as_handled()

			KEY_HOME:
				_move_cursor(0, shift)
				get_viewport().set_input_as_handled()

			KEY_END:
				_move_cursor(_editor_text.length(), shift)
				get_viewport().set_input_as_handled()

			KEY_UP:
				if _current_line > 0:
					_current_line -= 1
					_editor_cursor = mini(_editor_cursor, _editor_text.length())
					_select_start = -1
					_ensure_cursor_visible()
				get_viewport().set_input_as_handled()

			KEY_DOWN:
				if _current_line < _lines.size() - 1:
					_current_line += 1
					_editor_cursor = mini(_editor_cursor, _editor_text.length())
					_select_start = -1
					_ensure_cursor_visible()
				get_viewport().set_input_as_handled()

			_:
				if ctrl:
					match event.keycode:
						KEY_A:
							# Ctrl+A: beginning of line — or select all if already at start
							if _editor_cursor == 0:
								_select_start = 0
								_editor_cursor = _editor_text.length()
							else:
								_move_cursor(0, shift)
							get_viewport().set_input_as_handled()
							return
						KEY_E:
							# Ctrl+E: end of line
							_move_cursor(_editor_text.length(), shift)
							get_viewport().set_input_as_handled()
							return
						KEY_SLASH:
							# Ctrl+/: toggle mute on current line
							if _current_line < _lines.size():
								_lines[_current_line]["muted"] = not _line_muted(_current_line)
							get_viewport().set_input_as_handled()
							return
						KEY_K:
							if shift:
								# Ctrl+Shift+K: delete entire current line
								if _lines.size() > 1:
									_kill_buffer = _editor_text
									_lines.remove_at(_current_line)
									if _current_line >= _lines.size():
										_current_line = _lines.size() - 1
									_editor_cursor = mini(_editor_cursor, _editor_text.length())
									_ensure_cursor_visible()
								else:
									_kill_buffer = _editor_text
									_editor_text = ""
									_editor_cursor = 0
							else:
								# Ctrl+K: kill from cursor to end of line
								_kill_buffer = _editor_text.substr(_editor_cursor)
								_editor_text = _editor_text.substr(0, _editor_cursor)
							get_viewport().set_input_as_handled()
							return
						KEY_U:
							# Ctrl+U: kill from cursor to beginning of line
							_kill_buffer = _editor_text.substr(0, _editor_cursor)
							_editor_text = _editor_text.substr(_editor_cursor)
							_editor_cursor = 0
							get_viewport().set_input_as_handled()
							return
						KEY_Y:
							# Ctrl+Y: yank (paste kill buffer)
							if not _kill_buffer.is_empty():
								if _has_selection():
									_delete_selection()
								_editor_text = _editor_text.substr(0, _editor_cursor) + _kill_buffer + _editor_text.substr(_editor_cursor)
								_editor_cursor += _kill_buffer.length()
							get_viewport().set_input_as_handled()
							return
						KEY_W:
							# Ctrl+W: kill word backward
							if _has_selection():
								_kill_buffer = _get_selected_text()
								_delete_selection()
							else:
								var p: int = _word_boundary_left()
								_kill_buffer = _editor_text.substr(p, _editor_cursor - p)
								_editor_text = _editor_text.substr(0, p) + _editor_text.substr(_editor_cursor)
								_editor_cursor = p
							get_viewport().set_input_as_handled()
							return
						KEY_C:
							# Ctrl+C: copy selection (or whole line)
							var text: String = _get_selected_text() if _has_selection() else _editor_text
							if not text.is_empty():
								DisplayServer.clipboard_set(text)
							get_viewport().set_input_as_handled()
							return
						KEY_X:
							# Ctrl+X: cut selection (or whole line)
							if _has_selection():
								DisplayServer.clipboard_set(_get_selected_text())
								_delete_selection()
							else:
								DisplayServer.clipboard_set(_editor_text)
								_editor_text = ""
								_editor_cursor = 0
							get_viewport().set_input_as_handled()
							return
						KEY_V:
							# Ctrl+V: paste from clipboard
							var clip: String = DisplayServer.clipboard_get()
							if not clip.is_empty():
								clip = clip.replace("\r\n", " ").replace("\n", " ").replace("\r", " ").strip_edges()
								if _has_selection():
									_delete_selection()
								_editor_text = _editor_text.substr(0, _editor_cursor) + clip + _editor_text.substr(_editor_cursor)
								_editor_cursor += clip.length()
							get_viewport().set_input_as_handled()
							return

				# Type character at cursor (skip if ctrl held, except for Ctrl+M which was handled above)
				if event.unicode > 0 and not ctrl:
					if _has_selection():
						_delete_selection()
					var ch: String = char(event.unicode)
					_editor_text = _editor_text.substr(0, _editor_cursor) + ch + _editor_text.substr(_editor_cursor)
					_editor_cursor += 1
					_cursor_blink = 0.0
					get_viewport().set_input_as_handled()


# -- Selection helpers ---------------------------------------------------------

func _has_selection() -> bool:
	return _select_start >= 0 and _select_start != _editor_cursor

func _get_selected_text() -> String:
	if not _has_selection():
		return ""
	var from: int = mini(_select_start, _editor_cursor)
	var to: int = maxi(_select_start, _editor_cursor)
	return _editor_text.substr(from, to - from)

func _delete_selection() -> void:
	if not _has_selection():
		return
	var from: int = mini(_select_start, _editor_cursor)
	var to: int = maxi(_select_start, _editor_cursor)
	_editor_text = _editor_text.substr(0, from) + _editor_text.substr(to)
	_editor_cursor = from
	_select_start = -1

func _move_cursor(new_pos: int, extend_selection: bool) -> void:
	if extend_selection:
		if _select_start < 0:
			_select_start = _editor_cursor
	else:
		_select_start = -1
	_editor_cursor = new_pos
	_cursor_blink = 0.0

func _ensure_cursor_visible() -> void:
	## Scroll the editor so the current line is visible.
	if _current_line < _editor_scroll:
		_editor_scroll = _current_line
	elif _current_line >= _editor_scroll + MAX_VISIBLE_LINES:
		_editor_scroll = _current_line - MAX_VISIBLE_LINES + 1

func _word_boundary_left() -> int:
	var p: int = _editor_cursor - 1
	while p > 0 and _editor_text[p - 1] == " ":
		p -= 1
	while p > 0 and _editor_text[p - 1] != " ":
		p -= 1
	return maxi(0, p)

func _word_boundary_right() -> int:
	var p: int = _editor_cursor
	var slen: int = _editor_text.length()
	while p < slen and _editor_text[p] != " ":
		p += 1
	while p < slen and _editor_text[p] == " ":
		p += 1
	return p


# -- Playback ------------------------------------------------------------------

func _parse_line_text(line: Dictionary) -> Dictionary:
	## Parse a line dict into {pattern_text, name, sound, is_valid}.
	## Supports "name: pattern s=voice" syntax.
	var raw: String = line.get("text", "").strip_edges()
	var result := {"pattern_text": "", "name": line.get("name", ""), "sound": "", "is_valid": false}

	if raw.is_empty() or raw.begins_with("#"):
		return result

	var text: String = raw

	# Check for "name: pattern" syntax (Strudel label style)
	var colon_idx: int = text.find(": ")
	if colon_idx > 0 and colon_idx < 20:
		# Everything before ": " is the name, rest is pattern
		var candidate: String = text.substr(0, colon_idx).strip_edges()
		# Only treat as name if it's a simple identifier (no spaces, brackets, etc.)
		if candidate.is_valid_identifier():
			result["name"] = candidate
			line["name"] = candidate  # Persist the name
			text = text.substr(colon_idx + 2).strip_edges()

	# Extract key=value parameters
	for param in ["cps=", "sound=", "s="]:
		var p_idx: int = text.find(param)
		if p_idx >= 0:
			var p_val: String = text.substr(p_idx + param.length()).strip_edges()
			var space_idx: int = p_val.find(" ")
			if space_idx >= 0:
				p_val = p_val.substr(0, space_idx)
			if param == "cps=":
				if p_val.is_valid_float():
					_cps = float(p_val)
			else:
				result["sound"] = p_val
			text = (text.substr(0, p_idx) + text.substr(p_idx + param.length() + p_val.length())).strip_edges()

	if not text.is_empty():
		result["pattern_text"] = text
		result["is_valid"] = true
	return result


func _play_current() -> void:
	## Parse all non-muted, non-empty lines into patterns and stack them.
	var patterns: Array = []
	var display_parts: Array[String] = []

	for i in range(_lines.size()):
		if _line_muted(i):
			continue

		var parsed: Dictionary = _parse_line_text(_lines[i])
		if not parsed["is_valid"]:
			continue

		var text: String = parsed["pattern_text"]
		var sound_name: String = parsed["sound"]

		var pat: StrudelPattern = StrudelMini.mini(text)
		if not sound_name.is_empty():
			pat = pat.set_in(Strudel.pure({"s": sound_name}))
		patterns.append(pat)

		var name: String = parsed["name"]
		var label: String = (name + ": " if not name.is_empty() else "") + text
		if not sound_name.is_empty():
			label += " s=%s" % sound_name
		display_parts.append(label)

	if patterns.is_empty():
		return

	var combined: StrudelPattern
	if patterns.size() == 1:
		combined = patterns[0]
	else:
		combined = Strudel.stack(patterns)

	var display: String = " | ".join(PackedStringArray(display_parts))
	MusicManager.strudel_play(combined, _cps, display)
	_is_playing = true
	# Reset rolling buffer on pattern change
	_visible_haps.clear()
	_last_query_end = 0.0
	_active_locations.clear()


func _stop() -> void:
	MusicManager.strudel_stop()
	_is_playing = false
	_visible_haps.clear()
	_last_query_end = 0.0
	_active_locations.clear()


func _update_leaf_locations() -> void:
	# Source locations are embedded in the pattern's hap contexts
	# They'll be extracted per-frame in _update_pianoroll
	pass


# -- Pianoroll Update ----------------------------------------------------------

var _last_known_pattern: StrudelPattern = null  ## Track pattern changes from outside

func _update_pianoroll() -> void:
	if not MusicManager._cyclist or not MusicManager._strudel_playing:
		_visible_haps.clear()
		_current_time = 0.0
		_last_query_end = 0.0
		_last_known_pattern = null
		return

	# Detect external pattern change (e.g. RCON strudel command, test runner)
	if MusicManager._strudel_pattern != _last_known_pattern:
		_last_known_pattern = MusicManager._strudel_pattern
		_visible_haps.clear()
		_last_query_end = 0.0
		_active_locations.clear()
		# Sync editor text from the source that created this pattern
		if not MusicManager._strudel_source_text.is_empty():
			var src: String = MusicManager._strudel_source_text
			# If source contains " | ", it was multiple patterns stacked — split into lines
			if " | " in src:
				_lines.clear()
				for part in src.split(" | "):
					_lines.append(_make_line(part.strip_edges()))
			else:
				# Single pattern — put in first line, keep others
				if _lines.is_empty():
					_lines.append(_make_line(src))
				else:
					_lines[0]["text"] = src
			_current_line = 0
			_editor_cursor = _editor_text.length()
			_select_start = -1
		_is_playing = MusicManager._strudel_playing
		DebugOverlay.log("strudel/pattern", null, "DRAWER: synced to '%s'" % _editor_text)

	_current_time = MusicManager._cyclist.now()
	var lookbehind: float = PIANOROLL_CYCLES * PIANOROLL_PLAYHEAD
	var lookahead: float = PIANOROLL_CYCLES * (1.0 - PIANOROLL_PLAYHEAD)
	var visible_start: float = _current_time - lookbehind
	var visible_end: float = _current_time + lookahead

	# Rolling buffer: prune haps that scrolled off the left edge
	_visible_haps = _visible_haps.filter(func(hap: StrudelHap) -> bool:
		if hap.whole == null:
			return false
		return hap.get_end_clipped().to_float() >= visible_start)

	# Query only NEW haps beyond where we last queried
	if MusicManager._strudel_pattern:
		var query_start: float = maxf(_last_query_end, visible_start)
		if visible_end > query_start:
			var new_haps: Array = MusicManager._strudel_pattern.query_arc(query_start, visible_end)
			var added: int = 0
			for hap in new_haps:
				if hap.has_onset():
					_visible_haps.append(hap)
					added += 1
			_last_query_end = visible_end
			# Throttled debug logging (every 60 frames)
			if _debug_frame % 60 == 0:
				DebugOverlay.log("strudel/pattern", null,
					"DRAWER: t=%.2f haps=%d added=%d active_locs=%d query=[%.2f,%.2f]" % [
					_current_time, _visible_haps.size(), added, _active_locations.size(),
					query_start, visible_end])

	# Update source highlighting — only from currently active haps
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

	# -- Editor Lines (multi-line) --
	var ey: float = TOOLBAR_HEIGHT + 4.0
	var visible_lines: int = mini(_lines.size(), MAX_VISIBLE_LINES)
	var editor_total_h: float = visible_lines * LINE_HEIGHT

	for i in range(_editor_scroll, mini(_editor_scroll + MAX_VISIBLE_LINES, _lines.size())):
		var line_y: float = ey + (i - _editor_scroll) * LINE_HEIGHT
		var is_current: bool = (i == _current_line)
		_draw_editor_line_at(px + 8, line_y, pw - 16, LINE_HEIGHT, font, i, is_current)

	# Line count indicator
	if _lines.size() > 1:
		_panel.draw_string(font, Vector2(px + pw - 40, ey + editor_total_h + 10),
			"%d/%d" % [_current_line + 1, _lines.size()],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.4, 0.5))

	# -- Pianoroll --
	var pr_y: float = ey + editor_total_h + 8.0
	var pr_h: float = ph - pr_y - 8.0
	if pr_h > 20:
		_draw_pianoroll(px + 4, pr_y, pw - 8, pr_h, font)


func _draw_editor_line_at(x: float, y: float, w: float, h: float, font: Font, line_idx: int, is_current: bool) -> void:
	## Draw one editor line with source highlighting, name, and mute state.
	var line_text: String = _lines[line_idx].get("text", "") if line_idx < _lines.size() else ""
	var is_muted: bool = _line_muted(line_idx)
	var line_name: String = _line_name(line_idx)
	var font_size: int = 12

	# Background — brighter for current, dimmed for muted
	var bg_color: Color
	if is_muted:
		bg_color = Color(0.06, 0.03, 0.03)
	elif is_current:
		bg_color = Color(0.07, 0.07, 0.11)
	else:
		bg_color = Color(0.04, 0.04, 0.07)
	_panel.draw_rect(Rect2(x, y, w, h), bg_color)

	# Left border accent — blue for current, red for muted
	if is_current:
		_panel.draw_rect(Rect2(x, y, 2, h), Color(0.4, 0.7, 1.0, 0.6))
	elif is_muted:
		_panel.draw_rect(Rect2(x, y, 2, h), Color(0.6, 0.2, 0.2, 0.4))

	# Line label: name or number + mute indicator
	var label: String = line_name
	var label_w: float = 28.0
	var label_color: Color
	if is_muted:
		label_color = Color(0.5, 0.2, 0.2)
		label = "x" + label  # 'x' prefix = muted
	elif is_current:
		label_color = Color(0.5, 0.6, 0.8)
	else:
		label_color = Color(0.3, 0.3, 0.4)
	_panel.draw_string(font, Vector2(x + 3, y + h * 0.72), label,
		HORIZONTAL_ALIGNMENT_LEFT, label_w, 8, label_color)

	var text_x: float = x + label_w + 2
	var text_y: float = y + h * 0.72
	var text_w: float = w - label_w - 4

	# Draw source highlights behind text (active notes glow)
	# Source locations are offsets within this line's text
	for key in _active_locations:
		var loc_parts: PackedStringArray = key.split(":")
		if loc_parts.size() != 2:
			continue
		var loc_start: int = int(loc_parts[0])
		var loc_end: int = int(loc_parts[1])
		# Only highlight if this location falls within this line's text
		if loc_start >= line_text.length() or loc_end <= 0:
			continue
		loc_start = clampi(loc_start, 0, line_text.length())
		loc_end = clampi(loc_end, 0, line_text.length())
		var pre_text: String = line_text.substr(0, loc_start)
		var highlight_text: String = line_text.substr(loc_start, loc_end - loc_start)
		var pre_w: float = font.get_string_size(pre_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var hl_w: float = font.get_string_size(highlight_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var hap: StrudelHap = _active_locations[key]
		var progress: float = 0.0
		if hap.whole != null:
			var dur: float = hap.get_duration().to_float()
			if dur > 0:
				progress = clampf((_current_time - hap.w().begin.to_float()) / dur, 0.0, 1.0)
		var alpha: float = lerpf(0.5, 0.1, progress)
		_panel.draw_rect(Rect2(text_x + pre_w, y + 2, hl_w, h - 4),
			Color(0.3, 0.6, 1.0, alpha))

	# Draw selection highlight (only on current line)
	if is_current and _has_selection():
		var sel_from: int = mini(_select_start, _editor_cursor)
		var sel_to: int = maxi(_select_start, _editor_cursor)
		var sel_x_from: float = text_x + font.get_string_size(
			line_text.substr(0, sel_from), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var sel_x_to: float = text_x + font.get_string_size(
			line_text.substr(0, sel_to), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		_panel.draw_rect(Rect2(sel_x_from, y + 2, sel_x_to - sel_x_from, h - 4),
			Color(0.3, 0.5, 0.8, 0.4))

	# Draw the text
	var text_color: Color
	if is_muted:
		text_color = Color(0.4, 0.3, 0.3)
	elif line_text.begins_with("#"):
		text_color = Color(0.4, 0.5, 0.4)
	else:
		text_color = Color(0.9, 0.9, 0.95)
	_panel.draw_string(font, Vector2(text_x, text_y), line_text,
		HORIZONTAL_ALIGNMENT_LEFT, text_w, font_size, text_color)

	# Draw cursor (only on current line, blinking)
	if is_current and _editor_focused and int(_cursor_blink * 2.0) % 2 == 0:
		var cursor_text: String = line_text.substr(0, _editor_cursor)
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
	## Handles: plain int/float, plain string ("c4"), dict with "note"/"value"/"n" keys.
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
		# Check all possible keys where a note value might be
		for key in ["note", "value", "n"]:
			if val.has(key):
				var n_val: Variant = val[key]
				if n_val is int or n_val is float:
					return float(n_val)
				if n_val is String:
					var midi: int = _note_helper._note_name_to_midi(n_val)
					if midi >= 0:
						return float(midi)
	return -1.0
