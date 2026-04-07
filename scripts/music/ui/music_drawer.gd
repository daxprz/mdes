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
##     Ctrl+.              — cycle visualizer (none → pianoroll → bar → none)
##   Music:
##     Escape              — close drawer
##
## Line format:
##   Each line is an independent pattern. Non-muted lines are stacked on eval.
##   Multi-line blocks: lines with unclosed parens continue onto the next line.
##   The block is visually grouped with a bracket gutter and treated as one
##   expression on eval. Muting any line in a block mutes the whole block.
##     stack(                         — block start (unclosed paren)
##       s("bd sd hh cp"),            — continuation
##       note("c2 e2").s("saw")       — continuation
##     )                              — block end (parens balanced)
##   Lines support the Strudel label syntax:
##     drums: c4(3,8)                — named "drums"
##     bass: c2 ~ c2 ~ e2 ~ s=bass  — named "bass", voice override
##     c4 e4 g4 c5                   — auto-named "d1", "d2", etc.
##     # this is a comment           — skipped on eval
##   Muted lines (Ctrl+/) are dimmed and excluded from playback.
##
##   Inline visualizers (Strudel v1.2.0 syntax):
##     "c4 e4 g4 c5".pianoroll()    — quoted mini + pianoroll
##     note("c4 e4 g4").scope()     — note() wrapper + scope
##     "c4 e4 g4 c5".wordfall()     — vertical pianoroll with labels
##     "c4(3,8)".spiral()           — archimedean spiral
##     "[c4,e4,g4]".pitchwheel()    — pitch circle (12-EDO)
##     "c3 e3 g3".fscope()          — frequency spectrum
##     c4 e4 g4 c5                  — bare mini (no viz, no quotes needed)
##   Or toggle with Ctrl+. to cycle through all types

const SLIDE_SPEED := 1200.0
const PANEL_WIDTH := 420.0
const TOOLBAR_HEIGHT := 36.0
const SCRUB_HEIGHT := 10.0
const LINE_HEIGHT := 24.0     # Height of each editor line
const MIN_VISIBLE_LINES := 8  # Minimum visible lines (fallback)
const PIANOROLL_CYCLES := 4.0
const PIANOROLL_PLAYHEAD := 0.5  # Fraction of width where "now" is
const RECORD_STRIP_HEIGHT := 14.0  # Height of the record timeline strip
const ACTION_AREA_HEIGHT := 28.0   # Height of the composition action area

## Color palette for movements — indexed by order of first appearance.
const MOVEMENT_COLORS: Array[Color] = [
	Color(0.35, 0.55, 0.85),   # warm blue (e.g. "light")
	Color(0.45, 0.25, 0.65),   # deep purple (e.g. "dark")
	Color(0.25, 0.7, 0.5),     # teal
	Color(0.7, 0.35, 0.35),    # muted red
	Color(0.6, 0.55, 0.3),     # olive
]
const BRIDGE_COLOR := Color(0.85, 0.6, 0.2)       # orange/amber
const TURNAROUND_COLOR := Color(0.85, 0.75, 0.2)  # yellow/gold

var _active: bool = false
var _panel_x: float = 0.0      # Current X position of panel left edge
var _target_x: float = 0.0     # Target X for slide animation
var _panel: Control = null

# Multi-line editor state — each line is a named, independently mutable pattern
# Line format: "name: pattern_text" or just "pattern_text" (auto-named d1, d2, ...)
var _lines: Array[Dictionary] = []  # [{text, name, muted, block_id}]
var _block_map: Dictionary = {}  # block_id (first line idx) → Array of line indices
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


## Visualizer types — matches Strudel v1.2.0 visualizer methods.
## Only types that exist in Strudel are supported.
const VIZ_NONE := "none"            ## No visualizer (default)
const VIZ_PIANOROLL := "pianoroll"   ## .pianoroll() / .punchcard() / ._pianoroll()
const VIZ_SCOPE := "scope"          ## .scope() / .tscope() / ._scope() — oscilloscope
const VIZ_WORDFALL := "wordfall"    ## .wordfall() — vertical pianoroll with labels
const VIZ_SPIRAL := "spiral"        ## .spiral() / ._spiral() — archimedean spiral
const VIZ_PITCHWHEEL := "pitchwheel" ## .pitchwheel() / ._pitchwheel() — pitch circle
const VIZ_FSCOPE := "fscope"        ## .fscope() — frequency spectrum
const VIZ_TYPES := [VIZ_NONE, VIZ_PIANOROLL, VIZ_SCOPE, VIZ_WORDFALL, VIZ_SPIRAL, VIZ_PITCHWHEEL, VIZ_FSCOPE]
const VIZ_STRIP_HEIGHT := 32.0    ## Height of visualizer strip when active

## Audio control method names → canonical Strudel control key.
## These are parsed from method chains like .lpf(800).room(0.5) and applied
## as bus-level post-processing effects via MusicManager.set_music_effects().
const AUDIO_CONTROL_METHODS := {
	"lpf": "lpf", "lowpass": "lpf",
	"hpf": "hpf", "highpass": "hpf",
	"lpq": "lpq", "hpq": "hpq",
	"room": "room", "roomsize": "roomsize", "roomlp": "roomlp",
	"delay": "delay", "delaytime": "delaytime", "delayfeedback": "delayfeedback",
	"distort": "distort", "crush": "crush", "shape": "shape",
	"pan": "pan",
	"gain": "gain",
	"s": "s", "sound": "s",
	# Per-note ADSR (applied to SiON voice envelope, not bus effects)
	"attack": "attack", "att": "attack",
	"decay": "decay", "dec": "decay",
	"sustain": "sustain", "sus": "sustain",
	"release": "release", "rel": "release",
	# Per-note duration control (modifies hap duration, not bus effects)
	"clip": "clip", "legato": "clip",
	"dur": "duration", "duration": "duration",
}

## Signal names → factory callables for the signal expression parser.
const SIGNAL_NAMES := ["sine", "saw", "isaw", "cosine", "tri", "square", "rand"]

static func _parse_signal_expr(expr: String) -> StrudelPattern:
	## Parse a Strudel signal expression like "sine.range(200, 2000).slow(2)".
	## Returns a StrudelPattern, or null if the expression isn't a signal.
	##
	## Supported syntax:
	##   sine                          → unipolar sine [0,1]
	##   sine.range(200, 2000)         → mapped to [200, 2000]
	##   saw.range(0, 0.8).slow(2)     → sawtooth, range-mapped, half speed
	##   cosine.segment(8)             → discretized to 8 steps per cycle
	expr = expr.strip_edges()
	if expr.is_empty():
		return null

	# Extract the signal name (first token before '.' or end)
	var dot_pos: int = expr.find(".")
	var signal_name: String = expr if dot_pos < 0 else expr.substr(0, dot_pos)
	signal_name = signal_name.strip_edges().to_lower()

	if signal_name not in SIGNAL_NAMES:
		return null

	# Create the base signal pattern
	var pat: StrudelPattern = null
	match signal_name:
		"sine": pat = StrudelSignal.sine()
		"saw": pat = StrudelSignal.saw()
		"isaw": pat = StrudelSignal.isaw()
		"cosine": pat = StrudelSignal.cosine()
		"tri": pat = StrudelSignal.tri()
		"square": pat = StrudelSignal.square()
		"rand": pat = StrudelSignal.rand()

	if pat == null:
		return null

	# Parse chained methods: .range(200, 2000).slow(2).segment(8)
	if dot_pos < 0:
		return pat  # Just the signal name, no methods

	var remaining: String = expr.substr(dot_pos)  # ".range(200, 2000).slow(2)"

	while not remaining.is_empty():
		if not remaining.begins_with("."):
			break
		remaining = remaining.substr(1)  # skip dot

		# Extract method name
		var paren_pos: int = remaining.find("(")
		if paren_pos < 0:
			break
		var method: String = remaining.substr(0, paren_pos).strip_edges()
		var close_pos: int = remaining.find(")", paren_pos)
		if close_pos < 0:
			break
		var args_str: String = remaining.substr(paren_pos + 1, close_pos - paren_pos - 1).strip_edges()
		remaining = remaining.substr(close_pos + 1)

		# Parse args (comma-separated floats)
		var args: Array[float] = []
		for arg in args_str.split(","):
			arg = arg.strip_edges()
			if arg.is_valid_float():
				args.append(float(arg))

		# Apply method
		match method:
			"range":
				if args.size() >= 2:
					pat = pat._range(args[0], args[1])
			"slow":
				if args.size() >= 1:
					pat = pat._slow(args[0])
			"fast":
				if args.size() >= 1:
					pat = pat._fast(args[0])
			"segment":
				if args.size() >= 1:
					pat = pat._segment(int(args[0]))

	return pat

func _make_line(text: String = "", name: String = "", muted: bool = false, viz: String = VIZ_NONE) -> Dictionary:
	return {"text": text, "name": name, "muted": muted, "viz": viz, "viz_options": {}, "pattern_offset": 0, "block_id": -1}


const WRAP_INDENT := 12.0  ## Extra indent for soft-wrapped continuation rows


## Strudel structural keywords that act as block-level splits.
const WRAP_STRUCTURAL_FUNCS: PackedStringArray = ["stack(", "cat(", "slowcat(", "sequence(", "polymeter("]


func _find_best_wrap_break(text: String, max_pos: int) -> int:
	## Find the best break position within text[0..max_pos] using Strudel-aware
	## semantic priorities. Returns the character index to break AT.
	##
	## Priority tiers (first match wins):
	##   1. Before a structural function call: stack(, cat(, slowcat(, etc.
	##   2. Before '.' after ')' — method chain boundary: ).lpf(800) → break before '.'
	##   3. After a comma (possibly followed by space) — argument list split
	##   4. At any of the above, only if (1)-(3) are found within the search window
	var search_from: int = maxi(max_pos - 40, 1)  # Search back up to 40 chars

	# Tier 1: Before a structural function call (stack, cat, etc.)
	for j in range(max_pos, search_from, -1):
		for kw in WRAP_STRUCTURAL_FUNCS:
			if j + kw.length() <= text.length() and text.substr(j, kw.length()) == kw:
				if j > 0:  # Don't break at position 0
					return j

	# Tier 2: Before '.' that follows ')' — method chain boundary
	# Breaks ".lpf(800)" onto a new line after the previous chain link closes.
	for j in range(max_pos, search_from, -1):
		if j < text.length() and text[j] == "." and j > 0 and text[j - 1] == ")":
			return j

	# Tier 3: After comma — argument list boundary
	# Prefer "after comma+space" but also accept "after comma"
	for j in range(max_pos, search_from, -1):
		if j > 1 and text[j - 2] == "," and text[j - 1] == " ":
			return j
		if j > 0 and text[j - 1] == "," and (j >= text.length() or text[j] != " "):
			return j

	# Tier 4 (fallback): at any space, paren, or operator
	for j in range(max_pos, search_from, -1):
		if j > 0 and text[j - 1] in " )|+-*/":
			return j

	return max_pos


func _compute_wrap_rows(text: String, font: Font, font_size: int, max_w: float) -> Array:
	## Split a line's text into visual rows for soft-wrapping.
	## Returns Array of {text: String, char_offset: int} where char_offset
	## is the character index in the original text where this row starts.
	## Prefers breaking at Strudel-semantic boundaries (method chains, commas, parens).
	if text.is_empty():
		return [{"text": "", "char_offset": 0}]
	var full_w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if full_w <= max_w:
		return [{"text": text, "char_offset": 0}]
	var rows: Array = []
	var pos: int = 0
	var is_first: bool = true
	while pos < text.length():
		var remaining: String = text.substr(pos)
		var avail_w: float = max_w if is_first else max_w - WRAP_INDENT
		var row_w: float = font.get_string_size(remaining, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if row_w <= avail_w:
			rows.append({"text": remaining, "char_offset": pos})
			break
		# Binary search for the max chars that fit within avail_w
		var lo: int = 1
		var hi: int = remaining.length()
		while lo < hi:
			var mid: int = (lo + hi + 1) / 2
			var w: float = font.get_string_size(remaining.substr(0, mid), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			if w <= avail_w:
				lo = mid
			else:
				hi = mid - 1
		# lo = max chars that fit. Find the best semantic break point.
		var break_at: int = _find_best_wrap_break(remaining, lo)
		if break_at <= 0:
			break_at = maxi(1, lo)
		rows.append({"text": remaining.substr(0, break_at), "char_offset": pos})
		pos += break_at
		is_first = false
	if rows.is_empty():
		rows.append({"text": text, "char_offset": 0})
	return rows


func _char_to_wrap_row(char_idx: int, wrap_rows: Array) -> Dictionary:
	## Map a character index in the full line text to a wrap row index and local offset.
	## Returns {row: int, local_offset: int}.
	for i in range(wrap_rows.size() - 1, -1, -1):
		if char_idx >= wrap_rows[i]["char_offset"]:
			return {"row": i, "local_offset": char_idx - wrap_rows[i]["char_offset"]}
	return {"row": 0, "local_offset": char_idx}


func _compute_blocks() -> void:
	## Scan lines for multi-line blocks by tracking paren/bracket depth.
	## Lines with unclosed parens are continuation lines of the block that opened them.
	## Sets block_id on each line: first line index of the block, or -1 if standalone.
	## Also builds _block_map: {block_start_idx: [line indices in the block]}.
	_block_map.clear()
	var depth: int = 0
	var block_start: int = -1
	for i in range(_lines.size()):
		var text: String = _lines[i].get("text", "")
		if depth > 0:
			# We're inside a block — this line continues it
			_lines[i]["block_id"] = block_start
			_block_map[block_start].append(i)
		else:
			# Not inside a block yet — check if this line opens one
			block_start = -1
			_lines[i]["block_id"] = -1
		# Count parens/brackets outside of quoted strings
		var in_str: bool = false
		var str_char: String = ""
		for ci in range(text.length()):
			var ch: String = text[ci]
			if in_str:
				if ch == str_char:
					in_str = false
			elif ch == '"' or ch == "'":
				in_str = true
				str_char = ch
			elif ch == '(' or ch == '[':
				if depth == 0 and block_start < 0:
					# This line opens a new block
					block_start = i
					_lines[i]["block_id"] = i
					_block_map[i] = [i]
				depth += 1
			elif ch == ')' or ch == ']':
				depth = maxi(0, depth - 1)
		# If parens balanced on the same line that opened the block, it's not
		# actually multi-line — remove the block entry.
		if depth == 0:
			if block_start == i and _block_map.has(i) and _block_map[i].size() == 1:
				_block_map.erase(i)
				_lines[i]["block_id"] = -1
			block_start = -1


func _get_block_text(block_start: int) -> String:
	## Merge all lines in a block into a single expression string.
	if not _block_map.has(block_start):
		return _lines[block_start].get("text", "")
	var parts: Array[String] = []
	for idx in _block_map[block_start]:
		var t: String = _lines[idx].get("text", "").strip_edges()
		if not t.is_empty():
			parts.append(t)
	return " ".join(parts)


func _get_block_offset_table(block_start: int) -> Array:
	## Build an offset table mapping merged-string positions to (line_idx, local_offset).
	## Returns [{line_idx, merged_start, local_start, length}] for each non-empty line.
	## local_start is the offset of the stripped text within the original line text.
	var table: Array = []
	var merged_pos: int = 0
	for idx in _block_map.get(block_start, []):
		var raw: String = _lines[idx].get("text", "")
		var stripped: String = raw.strip_edges()
		if stripped.is_empty():
			continue
		# Find where stripped text starts in the raw line (leading whitespace)
		var local_start: int = raw.find(stripped)
		table.append({
			"line_idx": idx,
			"merged_start": merged_pos,
			"local_start": local_start,
			"length": stripped.length(),
		})
		merged_pos += stripped.length() + 1  # +1 for the space separator
	return table


func _remap_block_locations(pat: StrudelPattern, block_start: int, pat_offset: int) -> StrudelPattern:
	## Remap a pattern's source locations from merged-string coordinates to
	## per-line coordinates. Each location gets a correct line index and
	## start/end offsets relative to that line's text.
	var table: Array = _get_block_offset_table(block_start)
	if table.is_empty():
		return pat
	return pat.with_hap(func(hap: StrudelHap) -> StrudelHap:
		if not hap.context.has("locations"):
			return hap
		var new_locs: Array = []
		for loc in hap.context["locations"]:
			var s: int = int(loc.get("start", 0)) + pat_offset
			var e: int = int(loc.get("end", 0)) + pat_offset
			# Find which table entry contains offset s
			var found: bool = false
			for ti in range(table.size()):
				var entry: Dictionary = table[ti]
				var seg_end: int = entry["merged_start"] + entry["length"]
				if s >= entry["merged_start"] and s < seg_end:
					var tagged: Dictionary = loc.duplicate()
					tagged["line"] = entry["line_idx"]
					# Remap to local line coordinates (subtract merged offset, add local whitespace)
					tagged["start"] = s - entry["merged_start"] + entry["local_start"] - pat_offset
					tagged["end"] = mini(e, seg_end) - entry["merged_start"] + entry["local_start"] - pat_offset
					new_locs.append(tagged)
					found = true
					break
			if not found:
				new_locs.append(loc)
		var new_ctx: Dictionary = hap.context.duplicate()
		new_ctx["locations"] = new_locs
		return hap.set_context(new_ctx))


func _is_block_muted(block_start: int) -> bool:
	## A block is muted if its first line is muted.
	return _line_muted(block_start)


static func _parse_viz_options(opts_str: String) -> Dictionary:
	## Parse simple JS-like options: {labels:1, fold:0} or {labels: true}
	## Returns a Dictionary of key→value (values are int/float/bool/string).
	var result: Dictionary = {}
	# Strip surrounding braces if present
	opts_str = opts_str.strip_edges()
	if opts_str.begins_with("{"):
		opts_str = opts_str.substr(1)
	if opts_str.ends_with("}"):
		opts_str = opts_str.substr(0, opts_str.length() - 1)
	# Split by comma
	for pair in opts_str.split(","):
		pair = pair.strip_edges()
		if pair.is_empty():
			continue
		var sep: int = pair.find(":")
		if sep < 0:
			sep = pair.find("=")
		if sep < 0:
			continue
		var key: String = pair.substr(0, sep).strip_edges().replace("'", "").replace('"', '')
		var val_str: String = pair.substr(sep + 1).strip_edges().replace("'", "").replace('"', '')
		# Parse value
		if val_str == "true":
			result[key] = true
		elif val_str == "false":
			result[key] = false
		elif val_str.is_valid_float():
			result[key] = float(val_str) if "." in val_str else int(val_str)
		else:
			result[key] = val_str
	return result


func _line_viz(idx: int) -> String:
	if idx >= _lines.size():
		return VIZ_NONE
	# Check stored viz (set by Ctrl+. or by eval parsing)
	var stored: String = _lines[idx].get("viz", VIZ_NONE)
	if stored != VIZ_NONE:
		return stored
	# Also detect inline viz methods in the text (live, before eval)
	var text: String = _lines[idx].get("text", "")
	for method_name in ["pianoroll", "punchcard", "_pianoroll",
						"scope", "tscope", "_scope",
						"wordfall", "spiral", "_spiral",
						"pitchwheel", "_pitchwheel", "fscope"]:
		if ("." + method_name + "(") in text:
			match method_name:
				"pianoroll", "punchcard", "_pianoroll": return VIZ_PIANOROLL
				"scope", "tscope", "_scope": return VIZ_SCOPE
				"wordfall": return VIZ_WORDFALL
				"spiral", "_spiral": return VIZ_SPIRAL
				"pitchwheel", "_pitchwheel": return VIZ_PITCHWHEEL
				"fscope": return VIZ_FSCOPE
	return VIZ_NONE


func _cycle_line_viz(idx: int) -> void:
	## Cycle the visualizer type for a line.
	if idx >= _lines.size():
		return
	var current: String = _line_viz(idx)
	var next_idx: int = (VIZ_TYPES.find(current) + 1) % VIZ_TYPES.size()
	_lines[idx]["viz"] = VIZ_TYPES[next_idx]


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

# Transport button hit areas (computed during draw, tested during input)
var _btn_play: Rect2 = Rect2()
var _btn_prev: Rect2 = Rect2()
var _btn_next: Rect2 = Rect2()
var _scrub_rect: Rect2 = Rect2()
var _scrub_dragging: bool = false
var _btn_reset: Rect2 = Rect2()
var _btn_transition: Rect2 = Rect2()

# Per-line pattern state (set on eval, used for per-line pianoroll)
var _line_patterns: Array = []   # Array[StrudelPattern or null] — one per line
var _line_haps: Array = []       # Array[Array[StrudelHap]] — per-line rolling hap buffers
var _line_query_ends: Array = [] # Array[float] — per-line last query end

# Global pianoroll state
var _visible_haps: Array = []   # Combined haps (all lines) for the shared pianoroll
var _current_time: float = 0.0  # Current cycle position for rendering
var _last_query_end: float = 0.0

# Highlight state — per-line source locations
var _active_locations: Dictionary = {}  # "line:start:end" -> StrudelHap
var _debug_frame: int = 0               # Frame counter for throttled logging

# Highlight tracking for testing — time-bucketed sets.
# Each beat maps to the set of substrings highlighted at that time.
# Format: {"0/4": ["L1:c4", "L1:c5"], "1/4": ["L1:e4"], ...}
# Reset via strudel highlights clear, read via strudel highlights.
var _highlight_beats: Dictionary = {}      # fraction_str -> Array[String]
var _highlight_seen: Dictionary = {}       # "line:start:end" -> true (dedup)
var _highlight_tracking: bool = false      # Only track when enabled (test mode)


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


func open() -> void:
	if not _active:
		toggle()

func close() -> void:
	if _active:
		toggle()

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
		# Still handle scrub drag release even when unfocused
		if event is InputEventMouseButton and not event.pressed and _scrub_dragging:
			_scrub_dragging = false
		return

	# -- Mouse input for transport controls --
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _btn_play.has_point(event.position):
				_toggle_play_pause()
				get_viewport().set_input_as_handled()
				return
			elif _btn_prev.has_point(event.position):
				MusicManager.strudel_prev_cycle()
				get_viewport().set_input_as_handled()
				return
			elif _btn_next.has_point(event.position):
				MusicManager.strudel_next_cycle()
				get_viewport().set_input_as_handled()
				return
			elif _btn_reset.size != Vector2.ZERO and _btn_reset.has_point(event.position):
				_on_reset_button_pressed()
				get_viewport().set_input_as_handled()
				return
			elif _btn_transition.size != Vector2.ZERO and _btn_transition.has_point(event.position):
				_on_transition_button_pressed()
				get_viewport().set_input_as_handled()
				return
			elif _scrub_rect.has_point(event.position):
				_scrub_dragging = true
				_scrub_seek_to_mouse(event.position.x)
				get_viewport().set_input_as_handled()
				return
		else:
			if _scrub_dragging:
				_scrub_dragging = false
				get_viewport().set_input_as_handled()
				return

	if event is InputEventMouseMotion and _scrub_dragging:
		_scrub_seek_to_mouse(event.position.x)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed:
		var shift: bool = event.shift_pressed
		var ctrl: bool = event.ctrl_pressed or event.meta_pressed

		# Transport shortcuts (before editor keys)
		if event.keycode == KEY_SPACE and ctrl:
			# Ctrl+Space: toggle play/pause
			_toggle_play_pause()
			get_viewport().set_input_as_handled()
			return
		if event.alt_pressed and event.keycode == KEY_LEFT:
			MusicManager.strudel_prev_cycle()
			get_viewport().set_input_as_handled()
			return
		if event.alt_pressed and event.keycode == KEY_RIGHT:
			MusicManager.strudel_next_cycle()
			get_viewport().set_input_as_handled()
			return

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
							# Ctrl+/: toggle mute on current line (or entire block)
							if _current_line < _lines.size():
								var mbid: int = _lines[_current_line].get("block_id", -1)
								if mbid >= 0 and _block_map.has(mbid):
									# Toggle all lines in the block together
									var new_muted: bool = not _line_muted(mbid)
									for bidx in _block_map[mbid]:
										_lines[bidx]["muted"] = new_muted
								else:
									_lines[_current_line]["muted"] = not _line_muted(_current_line)
							get_viewport().set_input_as_handled()
							return
						KEY_PERIOD:
							# Ctrl+.: cycle visualizer for current line (none → pianoroll → bar → none)
							_cycle_line_viz(_current_line)
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
	elif _current_line >= _editor_scroll + MIN_VISIBLE_LINES:
		_editor_scroll = _current_line - MIN_VISIBLE_LINES + 1

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
	## Parse a line dict — delegates to StrudelLineCompiler.parse_line() and
	## applies side-effects (line["name"], line["viz"], etc.) that the drawer needs.
	var result: Dictionary = StrudelLineCompiler.parse_line(line)

	# Apply side-effects that the drawer expects on the line dict.
	# StrudelLineCompiler.parse_line() is pure — it doesn't mutate the line.
	if not result.get("name", "").is_empty():
		line["name"] = result["name"]
	if result.has("viz"):
		line["viz"] = result["viz"]
	if result.has("viz_options"):
		line["viz_options"] = result["viz_options"]
	# Inline cps= parameter — apply to drawer state
	if result.has("inline_cps"):
		_cps = result["inline_cps"]
	return result


static func _is_ident_char(c: String) -> bool:
	## Returns true if c is a valid identifier character (alphanumeric or underscore).
	var code: int = c.unicode_at(0)
	return (code >= 65 and code <= 90) or (code >= 97 and code <= 122) \
		or (code >= 48 and code <= 57) or code == 95  # A-Z, a-z, 0-9, _


static func _split_top_level_commas(text: String) -> Array:
	## Split a string by commas at the top level (depth 0).
	## Returns Array of {text: String, pos: int} with character positions.
	## Respects nested parens, brackets, and quotes.
	var parts: Array = []
	var depth: int = 0
	var in_quote: String = ""
	var start: int = 0
	for i in range(text.length()):
		var c: String = text[i]
		if not in_quote.is_empty():
			if c == in_quote:
				in_quote = ""
			continue
		if c == '"' or c == "'":
			in_quote = c
		elif c == "(" or c == "[" or c == "{":
			depth += 1
		elif c == ")" or c == "]" or c == "}":
			depth -= 1
		elif c == "," and depth == 0:
			parts.append({"text": text.substr(start, i - start).strip_edges(), "pos": start})
			start = i + 1
	if start < text.length():
		parts.append({"text": text.substr(start).strip_edges(), "pos": start})
	return parts


static func _eval_sub_expr(expr: String, base_offset: int = 0) -> StrudelPattern:
	## Evaluate a single Strudel sub-expression (e.g., note("c3 g3").s("sawtooth").lpf(800)).
	## Handles full method chains (audio controls, pattern transforms, viz),
	## note()/s()/n() wrappers, and quoted mini-notation.
	## base_offset: character position of expr within the full line (for source highlighting).
	var text: String = expr.strip_edges()
	var inner_offset: int = base_offset + (expr.length() - expr.strip_edges().length())
	var voice: String = ""
	var audio_controls: Dictionary = {}
	var deferred_ops: Array = []

	# Build method lookup (same as _parse_line_text)
	var all_methods: Dictionary = {}
	for k in AUDIO_CONTROL_METHODS:
		all_methods[k] = "audio"
	for pm in ["degrade", "degradeBy", "undegrade", "undegradeBy",
				"fast", "slow", "hurry", "early", "late",
				"rev", "palindrome", "euclid", "euclidRot", "every",
				"chunk", "segment", "sometimes", "often", "rarely",
				"add", "sub", "mul", "superimpose", "layer", "jux", "off",
				"iter", "ply", "striate", "chop"]:
		all_methods[pm] = "pattern"
	for vz in ["pianoroll", "punchcard", "_pianoroll", "scope", "tscope", "_scope",
				"wordfall", "spiral", "_spiral", "pitchwheel", "_pitchwheel", "fscope"]:
		all_methods[vz] = "viz"

	# Strip method chains from right to left (same algorithm as _parse_line_text).
	var chain_changed: bool = true
	while chain_changed:
		chain_changed = false
		var best_pos: int = -1
		var best_method: String = ""
		var best_paren_open: int = -1
		var best_paren_close: int = -1
		for method_name in all_methods:
			var prefix: String = "." + method_name + "("
			var pos: int = text.rfind(prefix)
			if pos < 0:
				continue
			var po: int = pos + prefix.length()
			var depth: int = 1
			var pc: int = po
			while pc < text.length() and depth > 0:
				if text[pc] == "(":
					depth += 1
				elif text[pc] == ")":
					depth -= 1
				if depth > 0:
					pc += 1
			if depth != 0:
				continue
			if pc < text.length() - 1:
				var after: String = text.substr(pc + 1).strip_edges()
				if not after.is_empty():
					continue
			if pos > best_pos:
				best_pos = pos
				best_method = method_name
				best_paren_open = po
				best_paren_close = pc
		if best_pos < 0:
			break
		var args_str: String = text.substr(best_paren_open, best_paren_close - best_paren_open).strip_edges()
		var kind: String = all_methods[best_method]
		if kind == "audio":
			var control_key: String = AUDIO_CONTROL_METHODS[best_method]
			if control_key == "s":
				voice = args_str.replace("\"", "").replace("'", "").strip_edges()
			elif args_str.is_valid_float():
				audio_controls[control_key] = float(args_str)
		elif kind == "pattern":
			var args_offset_in_line: int = inner_offset + best_paren_open
			deferred_ops.append({"method": best_method, "args": args_str, "args_offset": args_offset_in_line})
		# Strip the method from text (viz methods just get dropped)
		text = text.substr(0, best_pos).strip_edges()
		chain_changed = true

	# Strip wrapper — track offset shift and wrapper type
	var sub_wrapper: String = ""  # "note", "s", or "n"
	if text.begins_with("note(") and text.ends_with(")"):
		sub_wrapper = "note"
		inner_offset += 5  # skip "note("
		text = text.substr(5, text.length() - 6).strip_edges()
	elif text.begins_with("sound(") and text.ends_with(")"):
		sub_wrapper = "s"
		inner_offset += 6
		text = text.substr(6, text.length() - 7).strip_edges()
	elif text.begins_with("s(") and text.ends_with(")"):
		sub_wrapper = "s"
		inner_offset += 2
		text = text.substr(2, text.length() - 3).strip_edges()
	elif text.begins_with("n(") and text.ends_with(")"):
		sub_wrapper = "n"
		inner_offset += 2
		text = text.substr(2, text.length() - 3).strip_edges()

	# Strip quotes — track offset shift
	if text.length() >= 2:
		if (text[0] == '"' and text[-1] == '"') or \
		   (text[0] == "'" and text[-1] == "'"):
			inner_offset += 1  # skip opening quote
			text = text.substr(1, text.length() - 2)

	var pat: StrudelPattern = StrudelMini.mini(text, inner_offset)

	# s() wrapper: each token is a voice name → wrap as {s: name, note: "c4"}
	if sub_wrapper == "s":
		pat = pat.fmap(func(v: Variant) -> Dictionary:
			return {"s": str(v), "note": "c4"})
	elif sub_wrapper == "n":
		pat = pat.fmap(func(v: Variant) -> Dictionary:
			return {"n": int(v) if v is float or v is int else 0})

	# Apply deferred pattern ops (fast, rev, add, etc.)
	if not deferred_ops.is_empty():
		pat = _apply_deferred_ops(pat, deferred_ops)

	if not voice.is_empty():
		pat = pat.set_in(Strudel.pure({"s": voice}))
	return pat


static func _parse_transform_fn(expr: String) -> Variant:
	## Parse a pattern-transforming function from a string.
	## Returns a Callable(StrudelPattern) -> StrudelPattern, or null if unparseable.
	##
	## Supported forms:
	##   rev                         → pat._rev()
	##   fast(2)                     → pat._fast(2)
	##   slow(2)                     → pat._slow(2)
	##   early(0.125)                → pat._early(0.125)
	##   hurry(2)                    → pat._fast(2)
	##   x=>x.fast(2)               → pat._fast(2)
	##   x=>x.fast(2).rev()         → pat._fast(2)._rev()
	##   x => x.fast(2).degradeBy(0.5)  → chained transforms
	var s: String = expr.strip_edges()
	if s.is_empty():
		return null

	# Arrow function: x=>x.method(...) or x => x.method(...)
	var arrow_idx: int = s.find("=>")
	if arrow_idx >= 0:
		var body: String = s.substr(arrow_idx + 2).strip_edges()
		# Strip the parameter reference (x., p., pat.)
		var dot_idx: int = body.find(".")
		if dot_idx < 0:
			return null
		body = body.substr(dot_idx)  # now starts with ".method(..."
		return _parse_method_chain_transform(body)

	# Named transform with parens: fast(2), slow(0.5), early(1/8)
	var paren_idx: int = s.find("(")
	if paren_idx >= 0:
		var fn_name: String = s.substr(0, paren_idx).strip_edges()
		var args_str: String = s.substr(paren_idx + 1, s.length() - paren_idx - 2).strip_edges()
		return _build_single_transform(fn_name, args_str)

	# Bare name: rev, palindrome
	return _build_single_transform(s, "")


static func _parse_method_chain_transform(chain: String) -> Variant:
	## Parse ".method1(args).method2(args)..." into a chained Callable.
	## Returns Callable(StrudelPattern) -> StrudelPattern, or null.
	var transforms: Array = []  # Array of Callable

	var remaining: String = chain.strip_edges()
	while remaining.begins_with("."):
		remaining = remaining.substr(1)  # skip the dot
		# Find method name (up to "(" or end)
		var paren_pos: int = remaining.find("(")
		var fn_name: String
		var args_str: String = ""

		if paren_pos < 0:
			# Bare name like "rev" at end of chain
			fn_name = remaining.strip_edges()
			remaining = ""
		else:
			fn_name = remaining.substr(0, paren_pos).strip_edges()
			# Find balanced closing paren
			var depth: int = 1
			var pc: int = paren_pos + 1
			while pc < remaining.length() and depth > 0:
				if remaining[pc] == "(":
					depth += 1
				elif remaining[pc] == ")":
					depth -= 1
				if depth > 0:
					pc += 1
			args_str = remaining.substr(paren_pos + 1, pc - paren_pos - 1).strip_edges()
			remaining = remaining.substr(pc + 1).strip_edges()

		var t: Variant = _build_single_transform(fn_name, args_str)
		if t != null:
			transforms.append(t)

	if transforms.is_empty():
		return null
	if transforms.size() == 1:
		return transforms[0]
	# Chain multiple transforms
	var fns: Array = transforms
	return func(p: StrudelPattern) -> StrudelPattern:
		var result: StrudelPattern = p
		for fn in fns:
			result = fn.call(result)
		return result


static func _parse_transform_arg(args_str: String, base_offset: int = 0) -> Variant:
	## Parse a transform argument — a number, note() wrapper, or quoted mini.
	## Returns a value suitable for add_in/sub_in/mul_in.
	## base_offset: character position of args_str within the line (for source highlighting).
	##
	## In Strudel, add() uses _opIn which merges dict values per-key.
	## So note("c4").add(7) does NOT transpose — the 7 has no "note" key.
	## To transpose notes: note("c4").add(note(7)) — both have "note" key.
	##
	## We handle common forms:
	##   add(7)          → add_in(7) — works on plain numbers
	##   add(note(7))    → add_in({note: 7}) — works on note patterns
	##   add(note("7"))  → same
	##   add("<0 5 7>")  → add_in(mini pattern)
	var s: String = args_str.strip_edges()
	var inner_offset: int = base_offset + (args_str.length() - args_str.strip_edges().length())
	if s.is_empty():
		return null
	# note(N) wrapper → wrap as {note: N} dict for per-key merging
	if s.begins_with("note(") and s.ends_with(")"):
		var inner: String = s.substr(5, s.length() - 6).strip_edges()
		inner_offset += 5  # skip "note("
		# Strip quotes inside note()
		if inner.length() >= 2 and ((inner[0] == '"' and inner[-1] == '"') or (inner[0] == "'" and inner[-1] == "'")):
			inner_offset += 1  # skip opening quote
			inner = inner.substr(1, inner.length() - 2)
		if inner.is_valid_float():
			return {"note": float(inner)}
		# Mini-notation inside note() → pattern.
		# Strip locations so they don't pollute the base pattern's coordinate space
		# when combined via add_in/sub_in/mul_in → app_left → combine_context.
		return StrudelMini.mini(inner)._strip_locations().fmap(func(v: Variant) -> Dictionary:
			return {"note": float(v) if v is float or v is int else 0})
	# Strip quotes
	if s.length() >= 2 and ((s[0] == '"' and s[-1] == '"') or (s[0] == "'" and s[-1] == "'")):
		inner_offset += 1  # skip opening quote
		s = s.substr(1, s.length() - 2)
	# Try as number
	if s.is_valid_float():
		return float(s)
	# Try as mini-notation pattern (e.g., "0,2" or "<0 5 7 0>")
	# Strip locations — same reasoning as note() case above.
	if not s.is_empty():
		return StrudelMini.mini(s)._strip_locations()
	return null


static func _build_single_transform(fn_name: String, args_str: String) -> Variant:
	## Build a single transform Callable from a function name and args string.
	## Returns Callable(StrudelPattern) -> StrudelPattern, or null.
	match fn_name:
		"fast":
			if args_str.is_valid_float():
				var v: float = float(args_str)
				return func(p: StrudelPattern) -> StrudelPattern: return p._fast(v)
		"slow":
			if args_str.is_valid_float():
				var v: float = float(args_str)
				return func(p: StrudelPattern) -> StrudelPattern: return p._slow(v)
		"hurry":
			if args_str.is_valid_float():
				var v: float = float(args_str)
				return func(p: StrudelPattern) -> StrudelPattern: return p._fast(v)
		"early":
			if args_str.is_valid_float():
				var v: float = float(args_str)
				return func(p: StrudelPattern) -> StrudelPattern: return p._early(StrudelFraction.from_float(v))
		"late":
			if args_str.is_valid_float():
				var v: float = float(args_str)
				return func(p: StrudelPattern) -> StrudelPattern: return p._late(StrudelFraction.from_float(v))
		"add":
			# add(N) transposes by N semitones. Accepts number or quoted mini.
			var add_val: Variant = _parse_transform_arg(args_str)
			if add_val != null:
				return func(p: StrudelPattern) -> StrudelPattern: return p.add_in(add_val)
		"sub":
			var sub_val: Variant = _parse_transform_arg(args_str)
			if sub_val != null:
				return func(p: StrudelPattern) -> StrudelPattern: return p.sub_in(sub_val)
		"mul":
			var mul_val: Variant = _parse_transform_arg(args_str)
			if mul_val != null:
				return func(p: StrudelPattern) -> StrudelPattern: return p.mul_in(mul_val)
		"rev":
			return func(p: StrudelPattern) -> StrudelPattern: return p._rev()
		"palindrome":
			return func(p: StrudelPattern) -> StrudelPattern: return p._palindrome()
		"degrade":
			return func(p: StrudelPattern) -> StrudelPattern: return p._degrade_by(0.5)
		"degradeBy":
			if args_str.is_valid_float():
				var v: float = float(args_str)
				return func(p: StrudelPattern) -> StrudelPattern: return p._degrade_by(v)
		"ply":
			if args_str.is_valid_float():
				var v: int = int(float(args_str))
				return func(p: StrudelPattern) -> StrudelPattern: return p._ply(v)
		"segment":
			if args_str.is_valid_float():
				var v: int = int(float(args_str))
				return func(p: StrudelPattern) -> StrudelPattern: return p._segment(v)
		"iter":
			if args_str.is_valid_float():
				var v: int = int(float(args_str))
				return func(p: StrudelPattern) -> StrudelPattern: return p._iter(v)
	return null


static func _apply_deferred_ops(pat: StrudelPattern, ops: Array) -> StrudelPattern:
	## Apply deferred pattern combinator methods parsed from the method chain.
	## ops is [{method: String, args: String}], applied in reverse order
	## (since they were parsed right-to-left but should apply left-to-right).
	for i in range(ops.size() - 1, -1, -1):
		var op: Dictionary = ops[i]
		var method: String = op["method"]
		var args: String = op["args"]
		match method:
			"degrade":
				pat = pat._degrade_by(0.5)
			"degradeBy":
				var amount: float = float(args) if args.is_valid_float() else 0.5
				pat = pat._degrade_by(amount)
			"undegradeBy":
				# undegradeBy keeps events that degrade would drop
				var amount: float = float(args) if args.is_valid_float() else 0.5
				pat = pat._degrade_by(amount)  # TODO: proper undegradeBy
			"undegrade":
				pat = pat._degrade_by(0.5)  # TODO: proper undegrade
			"fast":
				if args.is_valid_float():
					pat = pat._fast(float(args))
			"slow":
				if args.is_valid_float():
					pat = pat._slow(float(args))
			"hurry":
				if args.is_valid_float():
					pat = pat._fast(float(args))  # hurry also speeds up sample
			"early":
				if args.is_valid_float():
					pat = pat._early(StrudelFraction.from_float(float(args)))
			"late":
				if args.is_valid_float():
					pat = pat._late(StrudelFraction.from_float(float(args)))
			"rev":
				pat = pat._rev()
			"palindrome":
				pat = pat._palindrome()
			"euclid", "euclidRot":
				# Parse euclid(pulses, steps) or euclidRot(pulses, steps, rotation)
				var euclid_args: PackedStringArray = args.split(",")
				if euclid_args.size() >= 2:
					var pulses: int = int(euclid_args[0].strip_edges())
					var steps: int = int(euclid_args[1].strip_edges())
					if euclid_args.size() >= 3:
						var rotation: int = int(euclid_args[2].strip_edges())
						pat = pat._euclid_rot(pulses, steps, rotation)
					else:
						pat = pat._euclid(pulses, steps)
			"segment":
				if args.is_valid_float():
					pat = pat._segment(int(float(args)))
			"sometimes":
				var st_fn: Variant = _parse_transform_fn(args)
				if st_fn != null:
					pat = pat._sometimes(st_fn)
			"often":
				var of_fn: Variant = _parse_transform_fn(args)
				if of_fn != null:
					pat = pat._often(of_fn)
			"rarely":
				var ra_fn: Variant = _parse_transform_fn(args)
				if ra_fn != null:
					pat = pat._rarely(ra_fn)
			"superimpose":
				var si_fn: Variant = _parse_transform_fn(args)
				if si_fn != null:
					pat = pat.superimpose([si_fn])
			"layer":
				# layer(fn1, fn2, ...) — apply multiple transforms and stack
				var layer_parts: Array = _split_top_level_commas(args)
				var layer_fns: Array = []
				for lp in layer_parts:
					var lp_text: String = lp["text"] if lp is Dictionary else str(lp)
					var lf: Variant = _parse_transform_fn(lp_text)
					if lf != null:
						layer_fns.append(lf)
				if not layer_fns.is_empty():
					pat = pat.layer(layer_fns)
			"jux":
				var jx_fn: Variant = _parse_transform_fn(args)
				if jx_fn != null:
					pat = pat._jux(jx_fn)
			"iter":
				if args.is_valid_float():
					pat = pat._iter(int(float(args)))
			"every":
				# every(n, transform) — first arg is count, rest is the transform
				var comma_pos: int = args.find(",")
				if comma_pos > 0:
					var n_str: String = args.substr(0, comma_pos).strip_edges()
					var fn_str: String = args.substr(comma_pos + 1).strip_edges()
					if n_str.is_valid_float():
						var ev_fn: Variant = _parse_transform_fn(fn_str)
						if ev_fn != null:
							pat = pat._every(int(float(n_str)), ev_fn)
			"chunk":
				var ch_comma: int = args.find(",")
				if ch_comma > 0:
					var n_str: String = args.substr(0, ch_comma).strip_edges()
					var fn_str: String = args.substr(ch_comma + 1).strip_edges()
					if n_str.is_valid_float():
						var ch_fn: Variant = _parse_transform_fn(fn_str)
						if ch_fn != null:
							pat = pat._chunk(int(float(n_str)), ch_fn)
			"off":
				# off(time, transform) — first arg is time offset, rest is transform
				var off_comma: int = args.find(",")
				if off_comma > 0:
					var t_str: String = args.substr(0, off_comma).strip_edges()
					var fn_str: String = args.substr(off_comma + 1).strip_edges()
					if t_str.is_valid_float():
						var off_fn: Variant = _parse_transform_fn(fn_str)
						if off_fn != null:
							pat = pat._off(StrudelFraction.from_float(float(t_str)), off_fn)
			"ply":
				if args.is_valid_float():
					pat = pat._ply(int(float(args)))
			"add":
				var add_v: Variant = _parse_transform_arg(args, op.get("args_offset", 0))
				if add_v != null:
					pat = pat.add_in(add_v)
			"sub":
				var sub_v: Variant = _parse_transform_arg(args, op.get("args_offset", 0))
				if sub_v != null:
					pat = pat.sub_in(sub_v)
			"mul":
				var mul_v: Variant = _parse_transform_arg(args, op.get("args_offset", 0))
				if mul_v != null:
					pat = pat.mul_in(mul_v)
			"_set_in":
				# Inject a key=value into each hap via set_in.
				# Used for per-note controls like clip and duration.
				var si_key: String = args
				var si_val: float = op.get("value", 1.0)
				pat = pat.set_in(Strudel.pure({si_key: si_val}))
	return pat


# -- Line Resolution (let bindings, pattern compilation) ----------------------


func _compile_parsed(parsed: Dictionary, bindings: Dictionary = {}) -> StrudelPattern:
	## Compile a parsed line result into a Pattern.
	## Delegates to StrudelLineCompiler.compile_parsed() with a resolver that
	## handles let-variable bindings from the drawer's scope.
	var resolver: Callable = Callable()
	if not bindings.is_empty():
		resolver = func(text: String) -> StrudelPattern:
			return _resolve_expr(text, bindings)
	return StrudelLineCompiler.compile_parsed(parsed, resolver)


func _resolve_expr(text: String, bindings: Dictionary) -> StrudelPattern:
	## Try to resolve `text` as a let variable reference.
	## Returns the bound pattern (with suffix transforms applied), or null if not a reference.
	## Handles: bare name ("melody"), method chain ("melody.fast(2)").
	if bindings.is_empty():
		return null
	var name: String = ""
	var suffix: String = ""
	var dot_pos: int = text.find(".")
	if dot_pos > 0:
		var candidate: String = text.substr(0, dot_pos).strip_edges()
		if candidate.is_valid_identifier() and bindings.has(candidate):
			name = candidate
			suffix = text.substr(dot_pos)
	elif text.is_valid_identifier() and bindings.has(text):
		name = text
	if name.is_empty():
		return null
	var pat: StrudelPattern = bindings[name]["pattern"]
	if not suffix.is_empty():
		# Parse suffix as method chains on a dummy pattern
		var sfx_parsed: Dictionary = StrudelLineCompiler.parse_line(StrudelLineCompiler.make_line("x" + suffix))
		var sfx_ops: Array = sfx_parsed.get("deferred_ops", [])
		if not sfx_ops.is_empty():
			pat = StrudelLineCompiler.apply_deferred_ops(pat, sfx_ops)
	return pat


func _resolve_line(i: int, bindings: Dictionary) -> Dictionary:
	## Resolve a single drawer line into a result dict.
	## Returns: {type, pattern, sound, controls, signals, name, display}
	##   type: "skip" | "setcps" | "hush" | "let" | "pattern"
	##   For "let": adds let_name, let_binding
	##   For "pattern": pattern is ready to play
	var text: String = _lines[i].get("text", "").strip_edges()

	# Muted or empty
	if _line_muted(i) or text.is_empty() or text.begins_with("//") or text.begins_with("#"):
		return {"type": "skip"}

	# Let variable reference — check BEFORE parsing (bare identifiers are valid mini)
	var ref_pat: StrudelPattern = _resolve_expr(text, bindings)
	if ref_pat != null:
		# Find which binding this references (for def_line)
		var ref_name: String = text.split(".")[0].strip_edges() if "." in text else text
		_lines[i]["_let_ref"] = ref_name
		_lines[i]["_let_def_line"] = bindings[ref_name]["def_line"]
		return {
			"type": "pattern", "pattern": ref_pat,
			"sound": bindings[ref_name].get("sound", ""),
			"controls": bindings[ref_name].get("controls", {}),
			"signals": [], "name": "", "display": text,
		}

	# Normal parse
	var parsed: Dictionary = _parse_line_text(_lines[i])

	if parsed.has("setcps"):
		return {"type": "setcps", "value": parsed["setcps"]}
	if parsed.get("hush", false):
		return {"type": "hush"}

	# Let definition — compile RHS, tag locations with this line
	if parsed.get("is_let", false):
		var let_name: String = parsed["let_name"]
		var let_expr: String = parsed["let_expr"]
		var line_text: String = _lines[i].get("text", "")
		var eq_pos: int = line_text.find("=")
		var expr_offset: int = eq_pos + 1 if eq_pos >= 0 else 0
		while expr_offset < line_text.length() and line_text[expr_offset] == " ":
			expr_offset += 1
		var rhs_parsed: Dictionary = StrudelLineCompiler.parse_line(StrudelLineCompiler.make_line(let_expr))
		if rhs_parsed["is_valid"]:
			var let_pat: StrudelPattern = _compile_parsed(rhs_parsed, bindings)
			# Set pattern_offset on the definition line so draw-time alignment works.
			# Locations are 0-based (from _compile_parsed), and pattern_offset shifts
			# them to point past "let name = note(" in the definition line.
			_lines[i]["pattern_offset"] = rhs_parsed["pattern_offset"] + expr_offset
			# Tag locations with this line index so they render on the definition line
			let_pat = let_pat._tag_locations_line(i)
			return {
				"type": "let", "let_name": let_name,
				"let_binding": {
					"pattern": let_pat,
					"sound": rhs_parsed["sound"],
					"def_line": i,
					"controls": rhs_parsed.get("audio_controls", {}),
				},
			}
		return {"type": "skip"}

	if not parsed["is_valid"]:
		return {"type": "skip"}

	# Normal pattern line
	var pat: StrudelPattern = _compile_parsed(parsed, bindings)
	_lines[i]["pattern_offset"] = parsed["pattern_offset"]
	var sound_name: String = parsed["sound"]
	var is_batch: bool = MusicManager._sion_trigger != null and MusicManager._sion_trigger.batch_mode
	var display_pat: StrudelPattern = pat
	if not sound_name.is_empty() and not is_batch:
		display_pat = pat.set_in(Strudel.pure({"s": sound_name}))
	return {
		"type": "pattern", "pattern": display_pat, "clean_pattern": pat,
		"sound": sound_name, "name": parsed.get("name", ""),
		"controls": parsed.get("audio_controls", {}),
		"signals": parsed.get("signal_controls", []),
		"display": _lines[i].get("text", "").strip_edges(),
	}


func _play_current() -> void:
	## Resolve all lines, collect patterns, and play.
	## Multi-line blocks (unclosed parens) are merged into a single expression
	## and resolved on the block's first line.
	_compute_blocks()

	var active_patterns: Array = []
	var display_parts: Array[String] = []
	var merged_controls: Dictionary = {}
	var line_tracks: Array = []
	var let_bindings: Dictionary = {}

	_line_patterns.resize(_lines.size())
	_line_haps.resize(_lines.size())
	_line_query_ends.resize(_lines.size())

	for i in range(_lines.size()):
		_line_patterns[i] = null
		_line_haps[i] = []
		_line_query_ends[i] = 0.0

		var bid: int = _lines[i].get("block_id", -1)
		# Skip continuation lines — they're merged into their block's first line
		if bid >= 0 and bid != i:
			continue
		# Skip muted blocks entirely
		if bid >= 0 and _is_block_muted(bid):
			continue

		# Resolve: block start lines use merged text, standalone lines resolve normally
		var resolved: Dictionary
		if bid == i and _block_map.has(i):
			var merged_text: String = _get_block_text(i)
			var saved_text: String = _lines[i].get("text", "")
			_lines[i]["text"] = merged_text
			resolved = _resolve_line(i, let_bindings)
			_lines[i]["text"] = saved_text
			# Remap source locations from merged-string coords to per-line coords
			if resolved["type"] == "pattern":
				var pat_off: int = _lines[i].get("pattern_offset", 0)
				var remapped: StrudelPattern = _remap_block_locations(
					resolved["pattern"], i, pat_off)
				resolved["pattern"] = remapped
				if resolved.has("clean_pattern"):
					resolved["clean_pattern"] = _remap_block_locations(
						resolved["clean_pattern"], i, pat_off)
				# Set pattern_offset on each block line so highlight drawing aligns
				var offset_table: Array = _get_block_offset_table(i)
				for entry in offset_table:
					_lines[entry["line_idx"]]["pattern_offset"] = 0
				for block_idx in _block_map[i]:
					_line_patterns[block_idx] = remapped
		else:
			resolved = _resolve_line(i, let_bindings)

		match resolved["type"]:
			"skip":
				continue
			"setcps":
				_cps = resolved["value"]
			"hush":
				MusicManager.strudel_stop()
				_is_playing = false
				return
			"let":
				let_bindings[resolved["let_name"]] = resolved["let_binding"]
			"pattern":
				var pat: StrudelPattern = resolved["pattern"]
				_line_patterns[i] = pat
				active_patterns.append(pat)

				var controls: Dictionary = resolved.get("controls", {})
				for key in controls:
					merged_controls[key] = controls[key]

				var line_name: String = resolved["name"] if not resolved.get("name", "").is_empty() else "line%d" % i
				line_tracks.append({
					"pattern": resolved.get("clean_pattern", pat),
					"voice": resolved.get("sound", ""),
					"gain": float(controls.get("gain", controls.get("velocity", 1.0))),
					"name": line_name,
					"controls": controls,
					"signals": resolved.get("signals", []),
				})
				display_parts.append(resolved.get("display", ""))

	if active_patterns.is_empty():
		return

	var combined: StrudelPattern
	if active_patterns.size() == 1:
		combined = active_patterns[0]
	else:
		combined = Strudel.stack(active_patterns)

	var is_batch: bool = MusicManager._sion_trigger != null and MusicManager._sion_trigger.batch_mode

	if is_batch:
		_self_triggered = true
		MusicManager.strudel_play_batch(line_tracks, _cps)
		MusicManager._strudel_source_text = " | ".join(PackedStringArray(display_parts))
		MusicManager._strudel_pattern = combined
		MusicManager._strudel_playing = true
	else:
		_self_triggered = true
		MusicManager.strudel_play(combined, _cps, " | ".join(PackedStringArray(display_parts)))

	if MusicManager._sion_trigger:
		MusicManager._sion_trigger._signal_controls.clear()
		for t in line_tracks:
			MusicManager._sion_trigger._signal_controls.append_array(t.get("signals", []))

	if merged_controls.is_empty():
		MusicManager.reset_music_effects()
	else:
		MusicManager.set_music_effects(merged_controls)

	_is_playing = true
	# Reset rolling buffer on pattern change
	_visible_haps.clear()
	_last_query_end = 0.0
	_active_locations.clear()

	# Apply audio effects from method chains (lpf, room, delay, etc.)
	if merged_controls.is_empty():
		MusicManager.reset_music_effects()
	else:
		MusicManager.set_music_effects(merged_controls)


func _stop() -> void:
	MusicManager.strudel_stop()
	_is_playing = false
	_visible_haps.clear()
	_last_query_end = 0.0
	_active_locations.clear()


func _toggle_play_pause() -> void:
	if MusicManager._strudel_paused:
		MusicManager.strudel_resume()
		_is_playing = true
	elif _is_playing:
		MusicManager.strudel_pause()
		_is_playing = false
	else:
		# Stopped — evaluate and start
		_play_current()


func _on_reset_button_pressed() -> void:
	## Reset the composition to its beginning (default movement, bar 0).
	if MusicManager.get_composition():
		MusicManager.play_composition()


func _on_transition_button_pressed() -> void:
	## Handle click on the composition transition button.
	## Triggers a transition to the first available target movement.
	## If already queued, clicking again does nothing.
	if MusicManager.composition_is_transition_queued():
		return
	var transitions: Array = MusicManager.composition_get_available_transitions()
	if transitions.is_empty():
		return
	var target_id: String = transitions[0]["target_id"]
	MusicManager.composition_transition_to(target_id)


func _scrub_seek_to_mouse(mouse_x: float) -> void:
	if _scrub_rect.size.x <= 0:
		return
	var frac: float = clampf((mouse_x - _scrub_rect.position.x) / _scrub_rect.size.x, 0.0, 1.0)
	var scrub_max: float = maxf(floorf(_current_time) + 8.0, 8.0)
	var target_cycle: float = frac * scrub_max
	MusicManager.strudel_seek(target_cycle)


func _update_leaf_locations() -> void:
	# Source locations are embedded in the pattern's hap contexts
	# They'll be extracted per-frame in _update_pianoroll
	pass


# -- Pianoroll Update ----------------------------------------------------------

var _last_known_pattern: StrudelPattern = null  ## Track pattern changes from outside
var _self_triggered: bool = false  ## True when we initiated the pattern change (skip sync)

func _update_pianoroll() -> void:
	if not MusicManager._cyclist or (not MusicManager._strudel_playing and not MusicManager._strudel_paused):
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

		if _self_triggered:
			# We caused this change — don't overwrite our lines or patterns
			_self_triggered = false
		elif not MusicManager._strudel_source_text.is_empty():
			var src: String = MusicManager._strudel_source_text
			if " | " in src:
				_lines.clear()
				for part in src.split(" | "):
					_lines.append(_make_line(part.strip_edges()))
			else:
				if _lines.is_empty():
					_lines.append(_make_line(src))
				else:
					_lines[0]["text"] = src
					# Truncate to single line — old continuation/block lines are stale
					if _lines.size() > 1:
						_lines.resize(1)
			_current_line = 0
			_editor_cursor = _editor_text.length()
			_select_start = -1
			# Populate per-line patterns for external sync
			_line_patterns.clear()
			_line_haps.clear()
			_line_query_ends.clear()
			for i in range(_lines.size()):
				var parsed: Dictionary = _parse_line_text(_lines[i])
				if parsed["is_valid"]:
					var pat: StrudelPattern = StrudelMini.mini(parsed["pattern_text"])
					var snd: String = parsed["sound"]
					if not snd.is_empty():
						pat = pat.set_in(Strudel.pure({"s": snd}))
					_line_patterns.append(pat)
					_lines[i]["pattern_offset"] = parsed["pattern_offset"]
				else:
					_line_patterns.append(null)
				_line_haps.append([])
				_line_query_ends.append(0.0)
		_is_playing = MusicManager._strudel_playing
		DebugOverlay.log("strudel/pattern", null, "DRAWER: synced to '%s' (%d line patterns)" % [
			_editor_text, _line_patterns.filter(func(p): return p != null).size()])

	_current_time = MusicManager._cyclist.now()
	var lookbehind: float = PIANOROLL_CYCLES * PIANOROLL_PLAYHEAD
	var lookahead: float = PIANOROLL_CYCLES * (1.0 - PIANOROLL_PLAYHEAD)
	var visible_start: float = _current_time - lookbehind
	var visible_end: float = _current_time + lookahead

	# Detect seek (time jumped backward) — reset per-line rolling buffers so
	# haps are re-queried for the new time range instead of stale high-water marks.
	for i in range(_line_query_ends.size()):
		if _line_query_ends[i] > visible_end + 0.01:
			_line_query_ends[i] = 0.0
			if i < _line_haps.size():
				_line_haps[i] = []

	# Per-line rolling buffer: query each line's pattern independently
	_visible_haps.clear()
	_active_locations.clear()

	# Ensure arrays are sized
	while _line_haps.size() < _lines.size():
		_line_haps.append([])
		_line_query_ends.append(0.0)
		_line_patterns.append(null)

	for i in range(_lines.size()):
		var pat: Variant = _line_patterns[i] if i < _line_patterns.size() else null

		# If a line has a viz but no pattern, try parsing on the fly
		# (user typed .pianoroll() but hasn't pressed Ctrl+Enter yet)
		if pat == null and _line_viz(i) != VIZ_NONE and MusicManager._strudel_playing:
			var parsed: Dictionary = _parse_line_text(_lines[i])
			if parsed["is_valid"]:
				pat = StrudelMini.mini(parsed["pattern_text"])
				var snd: String = parsed["sound"]
				if not snd.is_empty():
					pat = pat.set_in(Strudel.pure({"s": snd}))
				# Store it so we don't re-parse every frame
				while _line_patterns.size() <= i:
					_line_patterns.append(null)
				_line_patterns[i] = pat
				_lines[i]["pattern_offset"] = parsed["pattern_offset"]

		if pat == null or _line_muted(i):
			if i < _line_haps.size():
				_line_haps[i] = []
			continue

		# Continuation lines in a block share the block start's hap buffer.
		# Don't query independently — copy the reference to avoid duplicate haps.
		var line_bid: int = _lines[i].get("block_id", -1) if i < _lines.size() else -1
		if line_bid >= 0 and line_bid != i:
			if line_bid < _line_haps.size():
				_line_haps[i] = _line_haps[line_bid]
			continue

		# Prune old haps for this line
		_line_haps[i] = _line_haps[i].filter(func(hap: StrudelHap) -> bool:
			if hap.whole == null: return false
			return hap.get_end_clipped().to_float() >= visible_start)

		# Query new haps for this line.
		# In batch mode, the oscillator WAV contains N pre-rendered cycles and loops.
		# To match, we wrap queries modulo N so the pianoroll shows the same
		# degrade/random variation that the audio plays.
		var line_qe: float = _line_query_ends[i] if i < _line_query_ends.size() else 0.0
		var query_start: float = maxf(line_qe, visible_start)
		if visible_end > query_start:
			var is_batch_mode: bool = MusicManager._sion_trigger != null and MusicManager._sion_trigger.batch_mode
			var bc: int = MusicManager._sion_trigger.batch_cycle_count if is_batch_mode else 0
			if is_batch_mode and bc > 1:
				# Wrap query range to match the looping WAV's cycle range [0, bc)
				var wrap_start: float = fmod(query_start, float(bc))
				var wrap_end: float = fmod(visible_end, float(bc))
				if wrap_start < 0: wrap_start += float(bc)
				if wrap_end < 0: wrap_end += float(bc)
				# Query in wrapped space, then shift haps back to real time
				var cycle_offset: float = query_start - wrap_start
				if wrap_end > wrap_start:
					var new_haps: Array = pat.query_arc(wrap_start, wrap_end)
					for hap in new_haps:
						if hap.has_onset():
							var shifted := StrudelHap.new(
								hap.whole.shift_by(cycle_offset) if hap.whole != null else null,
								hap.part.shift_by(cycle_offset),
								hap.value, hap.context)
							_line_haps[i].append(shifted)
				else:
					# Wraps around: query [wrap_start, bc) then [0, wrap_end)
					var new_haps1: Array = pat.query_arc(wrap_start, float(bc))
					for hap in new_haps1:
						if hap.has_onset():
							var shifted := StrudelHap.new(
								hap.whole.shift_by(cycle_offset) if hap.whole != null else null,
								hap.part.shift_by(cycle_offset),
								hap.value, hap.context)
							_line_haps[i].append(shifted)
					var new_haps2: Array = pat.query_arc(0.0, wrap_end)
					var offset2: float = cycle_offset + float(bc)
					for hap in new_haps2:
						if hap.has_onset():
							var shifted := StrudelHap.new(
								hap.whole.shift_by(offset2) if hap.whole != null else null,
								hap.part.shift_by(offset2),
								hap.value, hap.context)
							_line_haps[i].append(shifted)
			else:
				var new_haps: Array = pat.query_arc(query_start, visible_end)
				for hap in new_haps:
					if hap.has_onset():
						_line_haps[i].append(hap)
			_line_query_ends[i] = visible_end

		# Accumulate into global list + per-line highlighting.
		# Locations can carry an explicit "line" field (set by let bindings)
		# that overrides the default line index. This allows highlights from
		# stack(drums, melody) to render on each variable's definition line.
		var default_line: int = _lines[i].get("_let_def_line", i) if i < _lines.size() else i
		for hap in _line_haps[i]:
			_visible_haps.append(hap)
			if hap.whole == null or not hap.is_active(_current_time):
				continue
			var locations: Array = hap.context.get("locations", [])
			for loc in locations:
				var loc_line: int = loc.get("line", default_line)
				var line_text: String = _lines[loc_line].get("text", "") if loc_line < _lines.size() else ""
				var pat_off: int = _lines[loc_line].get("pattern_offset", 0) if loc_line < _lines.size() else 0
				var key: String = "%d:%d:%d" % [loc_line, loc.get("start", 0), loc.get("end", 0)]
				if not _active_locations.has(key) or hap.w().begin.to_float() > _active_locations[key].w().begin.to_float():
					_active_locations[key] = hap
				# Track first-seen highlights bucketed by beat fraction
				if _highlight_tracking and hap.whole != null:
					var beat_frac: String = hap.w().begin.modulo(StrudelFraction.new(1, 1)).show()
					# Dedup key includes beat so same source at different beats is tracked
					var beat_key: String = "%s@%s" % [key, beat_frac]
					if not _highlight_seen.has(beat_key):
						_highlight_seen[beat_key] = true
						var hl_start: int = clampi(int(loc.get("start", 0)) + pat_off, 0, line_text.length())
						var hl_end: int = clampi(int(loc.get("end", 0)) + pat_off, 0, line_text.length())
						var hl_sub: String = line_text.substr(hl_start, hl_end - hl_start).strip_edges()
						if not hl_sub.is_empty():
							var entry: String = "L%d:%s" % [loc_line + 1, hl_sub]
							if not _highlight_beats.has(beat_frac):
								_highlight_beats[beat_frac] = []
							if entry not in _highlight_beats[beat_frac]:
								_highlight_beats[beat_frac].append(entry)


# -- Drawing -------------------------------------------------------------------

func _draw_panel() -> void:
	# Recompute blocks every frame so visual grouping stays in sync with edits
	_compute_blocks()

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

	var has_composition: bool = MusicManager.get_record() != null and MusicManager.get_composition() != null

	# -- Toolbar --
	_panel.draw_rect(Rect2(px, 0, pw, TOOLBAR_HEIGHT), Color(0.12, 0.12, 0.18))

	# Transport buttons
	var btn_x: float = px + 8.0
	var btn_y: float = 8.0
	var btn_sz: float = 18.0
	var paused: bool = MusicManager._strudel_paused

	# Play/Pause button
	_btn_play = Rect2(btn_x, btn_y, btn_sz, btn_sz)
	if _is_playing:
		# Pause icon (two vertical bars) — green
		var bar_w: float = 5.0
		var gap: float = 3.0
		var bx: float = btn_x + (btn_sz - bar_w * 2 - gap) / 2.0
		_panel.draw_rect(Rect2(bx, btn_y + 2, bar_w, btn_sz - 4), Color(0.3, 0.9, 0.3))
		_panel.draw_rect(Rect2(bx + bar_w + gap, btn_y + 2, bar_w, btn_sz - 4), Color(0.3, 0.9, 0.3))
	else:
		# Play icon (triangle) — white if paused, gray if stopped
		var play_color: Color = Color(1.0, 1.0, 1.0) if paused else Color(0.5, 0.5, 0.5)
		_panel.draw_polygon(PackedVector2Array([
			Vector2(btn_x + 3, btn_y + 1),
			Vector2(btn_x + btn_sz - 2, btn_y + btn_sz / 2.0),
			Vector2(btn_x + 3, btn_y + btn_sz - 1),
		]), PackedColorArray([play_color, play_color, play_color]))

	# Prev cycle button (left-pointing triangle)
	var prev_x: float = btn_x + btn_sz + 6
	var nav_sz: float = 14.0
	var nav_y: float = btn_y + (btn_sz - nav_sz) / 2.0
	_btn_prev = Rect2(prev_x, nav_y, nav_sz, nav_sz)
	var nav_color: Color = Color(0.7, 0.8, 0.9)
	_panel.draw_polygon(PackedVector2Array([
		Vector2(prev_x + nav_sz - 2, nav_y + 1),
		Vector2(prev_x + 2, nav_y + nav_sz / 2.0),
		Vector2(prev_x + nav_sz - 2, nav_y + nav_sz - 1),
	]), PackedColorArray([nav_color, nav_color, nav_color]))

	# Next cycle button (right-pointing triangle)
	var next_x: float = prev_x + nav_sz + 4
	_btn_next = Rect2(next_x, nav_y, nav_sz, nav_sz)
	_panel.draw_polygon(PackedVector2Array([
		Vector2(next_x + 2, nav_y + 1),
		Vector2(next_x + nav_sz - 2, nav_y + nav_sz / 2.0),
		Vector2(next_x + 2, nav_y + nav_sz - 1),
	]), PackedColorArray([nav_color, nav_color, nav_color]))

	# Reset button |< (vertical bar + left-pointing triangle)
	var reset_x: float = next_x + nav_sz + 6
	var reset_color: Color = Color(0.7, 0.8, 0.9) if has_composition else Color(0.3, 0.3, 0.4)
	_btn_reset = Rect2(reset_x, nav_y, nav_sz, nav_sz)
	# Vertical bar on the left
	_panel.draw_rect(Rect2(reset_x + 1, nav_y + 1, 2.0, nav_sz - 2), reset_color)
	# Left-pointing triangle
	_panel.draw_polygon(PackedVector2Array([
		Vector2(reset_x + nav_sz - 1, nav_y + 1),
		Vector2(reset_x + 4, nav_y + nav_sz / 2.0),
		Vector2(reset_x + nav_sz - 1, nav_y + nav_sz - 1),
	]), PackedColorArray([reset_color, reset_color, reset_color]))

	# Cycle counter
	var info_x: float = reset_x + nav_sz + 8
	var cycle_num: int = int(floorf(_current_time)) if (_is_playing or paused) else 0
	_panel.draw_string(font, Vector2(info_x, btn_y + 13),
		"Cy %d" % cycle_num, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.9, 0.9, 0.6))

	# CPS display
	_panel.draw_string(font, Vector2(info_x + 44, btn_y + 13), "cps=%.2f" % _cps,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.8, 1.0))

	# Title
	_panel.draw_string(font, Vector2(px + pw - 80, btn_y + 13), "Strudel",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 0.7, 1.0))

	# -- Scrub Bar --
	var scrub_y: float = TOOLBAR_HEIGHT
	var scrub_pad: float = 6.0
	_scrub_rect = Rect2(px + scrub_pad, scrub_y, pw - scrub_pad * 2, SCRUB_HEIGHT)
	_panel.draw_rect(_scrub_rect, Color(0.06, 0.06, 0.1))
	# Determine scrub range (auto-extend as playback progresses)
	var scrub_max: float = maxf(floorf(_current_time) + 8.0, 8.0)
	# Cycle tick marks
	var tick_c: int = 0
	while tick_c < int(scrub_max):
		var tick_frac: float = float(tick_c) / scrub_max
		var tick_px: float = _scrub_rect.position.x + tick_frac * _scrub_rect.size.x
		var tick_alpha: float = 0.15 if tick_c % 4 == 0 else 0.06
		_panel.draw_line(Vector2(tick_px, scrub_y + 1), Vector2(tick_px, scrub_y + SCRUB_HEIGHT - 1),
			Color(1.0, 1.0, 1.0, tick_alpha), 1.0)
		tick_c += 1
	# Playhead indicator
	if _is_playing or paused:
		var head_frac: float = clampf(_current_time / scrub_max, 0.0, 1.0)
		var head_px: float = _scrub_rect.position.x + head_frac * _scrub_rect.size.x
		_panel.draw_rect(Rect2(head_px - 1.5, scrub_y + 1, 3.0, SCRUB_HEIGHT - 2), Color(0.3, 0.9, 0.3, 0.9))

	# -- Record Timeline Strip (composition mode) --
	var record_strip_bottom: float = scrub_y + SCRUB_HEIGHT
	if has_composition:
		_draw_record_strip(px, record_strip_bottom, pw, RECORD_STRIP_HEIGHT, font)
		record_strip_bottom += RECORD_STRIP_HEIGHT

	# -- Editor Lines (multi-line with per-line visualizers) --
	var ey: float = record_strip_bottom + 4.0
	var draw_y: float = ey
	# Calculate how many lines fit in the available panel height
	# With soft-wrapping, we can't pre-compute a fixed line count — draw until full.

	for i in range(_editor_scroll, _lines.size()):
		var is_current: bool = (i == _current_line)
		var viz: String = _line_viz(i)

		# Draw the code line (returns actual height — may be > LINE_HEIGHT for wrapped lines)
		var line_h: float = _draw_editor_line_at(px + 8, draw_y, pw - 16, LINE_HEIGHT, font, i, is_current)
		draw_y += line_h

		# Draw the per-line visualizer strip (if enabled).
		# For multi-line blocks, only show the viz on the block's first line
		# (continuation lines skip the viz to keep the block visually compact).
		var line_bid: int = _lines[i].get("block_id", -1) if i < _lines.size() else -1
		var show_viz: bool = viz != VIZ_NONE
		if show_viz and line_bid >= 0 and line_bid != i:
			show_viz = false  # Continuation line — skip viz
		if show_viz:
			# For block start lines, use the block's first line index for hap data
			var viz_line: int = line_bid if line_bid >= 0 else i
			if viz_line < _line_haps.size():
				_draw_line_viz(px + 8, draw_y, pw - 16, VIZ_STRIP_HEIGHT, font, viz_line, viz)
			else:
				# Hap buffer not ready yet — draw empty viz background
				_panel.draw_rect(Rect2(px + 8, draw_y, pw - 16, VIZ_STRIP_HEIGHT), Color(0.03, 0.03, 0.05))
			draw_y += VIZ_STRIP_HEIGHT

		# Stop if we run out of panel space
		if draw_y > ph - 20:
			break

	# Line count indicator
	if _lines.size() > 1:
		_panel.draw_string(font, Vector2(px + pw - 40, draw_y + 4),
			"%d/%d" % [_current_line + 1, _lines.size()],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.4, 0.5))

	# -- Action Area (composition mode) --
	if has_composition:
		_draw_action_area(px, draw_y + 12, pw, ACTION_AREA_HEIGHT, font)


func _draw_record_strip(x: float, y: float, w: float, h: float, font: Font) -> void:
	## Draw the color-coded Record timeline: played bars, current bar, cued bars.
	## Each bar is colored by section type: Movement (per-id color), Bridge (amber),
	## Turnaround (gold).  Current bar has a white outline and playhead.
	var record: MusicRecord = MusicManager.get_record()
	var comp: MusicComposition = MusicManager.get_composition()
	if not record or not comp:
		return

	# Background
	_panel.draw_rect(Rect2(x, y, w, h), Color(0.05, 0.05, 0.08))

	# Build movement → color map (palette indexed by iteration order)
	var movement_color_map: Dictionary = {}
	var mi: int = 0
	for m_id in comp.movements:
		movement_color_map[m_id] = MOVEMENT_COLORS[mi % MOVEMENT_COLORS.size()]
		mi += 1

	# Collect all bars: played + [current] + cued
	var all_bars: Array = []
	all_bars.append_array(record.played_bars)
	var current_idx: int = all_bars.size()
	if record.current_bar:
		all_bars.append(record.current_bar)
	all_bars.append_array(record.cued_bars)
	if all_bars.is_empty():
		return

	# Bar sizing
	var pad: float = 4.0
	var bar_gap: float = 1.0
	var usable_w: float = w - pad * 2
	var bar_w: float = minf(16.0, (usable_w - bar_gap * maxf(all_bars.size() - 1, 0)) / maxf(all_bars.size(), 1))
	bar_w = maxf(bar_w, 4.0)

	# Scroll offset to keep current bar centered
	var center_target: float = current_idx * (bar_w + bar_gap) + bar_w * 0.5
	var scroll_offset: float = center_target - usable_w * 0.5

	for i in range(all_bars.size()):
		var bar: MusicBar = all_bars[i]
		var bx: float = x + pad + i * (bar_w + bar_gap) - scroll_offset

		# Cull bars outside visible range
		if bx + bar_w < x or bx > x + w:
			continue

		# Color by section type
		var color: Color
		if bar.bridge:
			color = BRIDGE_COLOR
		elif bar.turnaround:
			color = TURNAROUND_COLOR
		elif bar.movement:
			color = movement_color_map.get(bar.movement.id, Color(0.4, 0.4, 0.4))
		else:
			color = Color(0.3, 0.3, 0.3)

		# Dimming: played bars fade, cued bars are semi-transparent
		if i < current_idx:
			var age: float = float(current_idx - i)
			color.a = clampf(1.0 - age * 0.08, 0.2, 0.7)
		elif i == current_idx:
			color.a = 1.0
		else:
			color.a = 0.5

		_panel.draw_rect(Rect2(bx, y + 1, bar_w, h - 2), color)

		# Current bar: white outline + playhead
		if i == current_idx:
			_panel.draw_rect(Rect2(bx, y, bar_w, h), Color(1, 1, 1, 0.4), false, 1.0)
			var progress: float = record.play_head.cycle_position
			var head_x: float = bx + progress * bar_w
			_panel.draw_line(Vector2(head_x, y), Vector2(head_x, y + h), Color(1, 1, 1, 0.8), 1.0)

		# Movement initial inside the bar (if wide enough)
		if bar_w >= 12.0 and bar.movement and not bar.bridge:
			var label: String = bar.movement.id.substr(0, 1).to_upper()
			_panel.draw_string(font, Vector2(bx + 2, y + h - 3), label,
				HORIZONTAL_ALIGNMENT_LEFT, bar_w - 4, 7, Color(1, 1, 1, 0.5 * color.a))


func _draw_action_area(x: float, y: float, w: float, h: float, font: Font) -> void:
	## Draw composition action buttons below the editor lines.
	## Shows a Transition button with state: active, disabled, or queued.
	var comp: MusicComposition = MusicManager.get_composition()
	var record: MusicRecord = MusicManager.get_record()
	if not comp or not record or not record.current_bar:
		_btn_transition = Rect2()
		return

	# Separator line
	_panel.draw_line(Vector2(x + 8, y), Vector2(x + w - 8, y), Color(0.2, 0.2, 0.25), 1.0)

	var transitions: Array = MusicManager.composition_get_available_transitions()
	var in_transition: bool = MusicManager.composition_is_in_transition()
	var is_queued: bool = MusicManager.composition_is_transition_queued()

	if transitions.is_empty() and not in_transition and not is_queued:
		_btn_transition = Rect2()
		return

	# Transition button
	var btn_w: float = 100.0
	var btn_h: float = 20.0
	var btn_x: float = x + 8.0
	var btn_y: float = y + (h - btn_h) / 2.0

	var btn_color: Color
	var btn_text: String
	var btn_text_color: Color

	if is_queued:
		btn_color = Color(0.15, 0.13, 0.08)
		btn_text = "Queued"
		btn_text_color = Color(0.85, 0.7, 0.3)
	elif in_transition:
		btn_color = Color(0.08, 0.08, 0.1)
		btn_text = "Transition"
		btn_text_color = Color(0.35, 0.35, 0.4)
	else:
		var target_name: String = ""
		if not transitions.is_empty():
			target_name = transitions[0]["target_id"]
		btn_text = "-> %s" % target_name if not target_name.is_empty() else "Transition"
		btn_color = Color(0.15, 0.18, 0.25)
		btn_text_color = Color(0.7, 0.85, 1.0)

	_btn_transition = Rect2(btn_x, btn_y, btn_w, btn_h)
	_panel.draw_rect(_btn_transition, btn_color)
	_panel.draw_rect(_btn_transition, Color(btn_text_color.r, btn_text_color.g, btn_text_color.b, 0.3), false, 1.0)
	_panel.draw_string(font, Vector2(btn_x + 8, btn_y + 14), btn_text,
		HORIZONTAL_ALIGNMENT_LEFT, btn_w - 16, 11, btn_text_color)

	# Current section label on the right
	var section_label: String = ""
	if record.current_bar.bridge:
		section_label = "bridge"
	elif record.current_bar.turnaround:
		section_label = "turnaround"
	elif record.current_bar.movement:
		section_label = record.current_bar.movement.id
	_panel.draw_string(font, Vector2(x + w - 80, btn_y + 14), section_label,
		HORIZONTAL_ALIGNMENT_LEFT, 72, 10, Color(0.5, 0.5, 0.6))


func _draw_editor_line_at(x: float, y: float, w: float, h: float, font: Font, line_idx: int, is_current: bool) -> float:
	## Draw one editor line with source highlighting, name, mute state, and soft-wrapping.
	## Lines that belong to a multi-line block get a bracket gutter and tinted background.
	## Long lines soft-wrap into multiple visual rows with a wrap indicator.
	## Returns the total height consumed (may be > h for wrapped lines).
	var line_text: String = _lines[line_idx].get("text", "") if line_idx < _lines.size() else ""
	var is_muted: bool = _line_muted(line_idx)
	var line_name: String = _line_name(line_idx)
	var font_size: int = 12
	var label_w: float = 32.0

	# Block membership
	var bid: int = _lines[line_idx].get("block_id", -1) if line_idx < _lines.size() else -1
	var in_block: bool = bid >= 0
	var is_block_start: bool = in_block and bid == line_idx
	var is_block_end: bool = false
	if in_block and _block_map.has(bid):
		var members: Array = _block_map[bid]
		is_block_end = line_idx == members[members.size() - 1]

	# Compute soft-wrap rows
	var text_w: float = w - label_w - 4
	var wrap_rows: Array = _compute_wrap_rows(line_text, font, font_size, text_w)
	var num_rows: int = wrap_rows.size()
	var total_h: float = h * num_rows
	var is_wrapped: bool = num_rows > 1

	# Background — spans all visual rows
	var bg_color: Color
	if is_muted:
		bg_color = Color(0.06, 0.03, 0.03)
	elif is_current:
		bg_color = Color(0.07, 0.07, 0.11)
	elif in_block:
		bg_color = Color(0.05, 0.05, 0.09)
	else:
		bg_color = Color(0.04, 0.04, 0.07)
	_panel.draw_rect(Rect2(x, y, w, total_h), bg_color)

	# Block bracket gutter — vertical bar with caps spanning all visual rows
	if in_block:
		var bracket_x: float = x + 1.0
		var bracket_color: Color = Color(0.35, 0.55, 0.85, 0.5) if not is_muted else Color(0.5, 0.2, 0.2, 0.4)
		_panel.draw_rect(Rect2(bracket_x, y, 2, total_h), bracket_color)
		if is_block_start:
			_panel.draw_rect(Rect2(bracket_x, y, 6, 1), bracket_color)
		if is_block_end:
			_panel.draw_rect(Rect2(bracket_x, y + total_h - 1, 6, 1), bracket_color)
	elif is_current:
		_panel.draw_rect(Rect2(x, y, 2, total_h), Color(0.4, 0.7, 1.0, 0.6))
	elif is_muted:
		_panel.draw_rect(Rect2(x, y, 2, total_h), Color(0.6, 0.2, 0.2, 0.4))

	# Soft-wrap gutter — thin dotted line on wrapped continuation rows
	if is_wrapped:
		var wrap_color: Color = Color(0.5, 0.4, 0.2, 0.35) if is_current else Color(0.4, 0.3, 0.2, 0.25)
		for ri in range(1, num_rows):
			var ry: float = y + h * ri
			# Small wrap arrow in the label area
			_panel.draw_string(font, Vector2(x + label_w - 8, ry + h * 0.72),
				String.chr(0x21A9), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, wrap_color)

	# Line label (first visual row only)
	var viz: String = _line_viz(line_idx)
	var label: String
	if in_block and not is_block_start:
		label = "..."
	else:
		label = line_name
	var label_color: Color
	if is_muted:
		label_color = Color(0.5, 0.2, 0.2)
		if is_block_start or not in_block:
			label = "x" + label
	elif is_current:
		label_color = Color(0.5, 0.6, 0.8)
	elif in_block:
		label_color = Color(0.35, 0.45, 0.65)
	else:
		label_color = Color(0.3, 0.3, 0.4)
	var viz_char: String = ""
	match viz:
		VIZ_PIANOROLL: viz_char = "P"
		VIZ_SCOPE: viz_char = "~"
		VIZ_WORDFALL: viz_char = "W"
		VIZ_SPIRAL: viz_char = "@"
		VIZ_PITCHWHEEL: viz_char = "O"
		VIZ_FSCOPE: viz_char = "F"
	if not viz_char.is_empty():
		label += viz_char
	_panel.draw_string(font, Vector2(x + 3, y + h * 0.72), label,
		HORIZONTAL_ALIGNMENT_LEFT, label_w, 8, label_color)

	# Text color
	var text_color: Color
	if is_muted:
		text_color = Color(0.4, 0.3, 0.3)
	elif line_text.begins_with("#"):
		text_color = Color(0.4, 0.5, 0.4)
	else:
		text_color = Color(0.9, 0.9, 0.95)

	# Draw source highlights, selection, text, and cursor for each wrap row
	var pat_offset: int = _lines[line_idx].get("pattern_offset", 0) if line_idx < _lines.size() else 0

	for ri in range(num_rows):
		var row: Dictionary = wrap_rows[ri]
		var row_text: String = row["text"]
		var row_char_off: int = row["char_offset"]
		var row_y: float = y + h * ri
		var row_text_x: float = x + label_w + 2 + (WRAP_INDENT if ri > 0 else 0.0)
		var row_text_y: float = row_y + h * 0.72
		var row_text_w: float = text_w - (WRAP_INDENT if ri > 0 else 0.0)

		# Source highlights — map global char offsets to this row
		for key in _active_locations:
			var loc_parts: PackedStringArray = key.split(":")
			if loc_parts.size() != 3:
				continue
			if int(loc_parts[0]) != line_idx:
				continue
			var loc_start: int = int(loc_parts[1]) + pat_offset
			var loc_end: int = int(loc_parts[2]) + pat_offset
			if loc_start >= line_text.length() or loc_end <= 0:
				continue
			loc_start = clampi(loc_start, 0, line_text.length())
			loc_end = clampi(loc_end, 0, line_text.length())
			# Intersect with this row's character range
			var row_end_off: int = row_char_off + row_text.length()
			if loc_end <= row_char_off or loc_start >= row_end_off:
				continue
			var hl_start: int = maxi(loc_start, row_char_off) - row_char_off
			var hl_end: int = mini(loc_end, row_end_off) - row_char_off
			var pre_w: float = font.get_string_size(row_text.substr(0, hl_start), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var hl_w: float = font.get_string_size(row_text.substr(hl_start, hl_end - hl_start), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var hap: StrudelHap = _active_locations[key]
			var progress: float = 0.0
			if hap.whole != null:
				var dur: float = hap.get_duration().to_float()
				if dur > 0:
					progress = clampf((_current_time - hap.w().begin.to_float()) / dur, 0.0, 1.0)
			var alpha: float = lerpf(0.5, 0.1, progress)
			_panel.draw_rect(Rect2(row_text_x + pre_w, row_y + 2, hl_w, h - 4),
				Color(0.3, 0.6, 1.0, alpha))

		# Selection highlight — map to this row
		if is_current and _has_selection():
			var sel_from: int = mini(_select_start, _editor_cursor)
			var sel_to: int = maxi(_select_start, _editor_cursor)
			var row_end_off: int = row_char_off + row_text.length()
			if sel_to > row_char_off and sel_from < row_end_off:
				var vis_from: int = maxi(sel_from, row_char_off) - row_char_off
				var vis_to: int = mini(sel_to, row_end_off) - row_char_off
				var sx_from: float = row_text_x + font.get_string_size(
					row_text.substr(0, vis_from), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
				var sx_to: float = row_text_x + font.get_string_size(
					row_text.substr(0, vis_to), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
				_panel.draw_rect(Rect2(sx_from, row_y + 2, sx_to - sx_from, h - 4),
					Color(0.3, 0.5, 0.8, 0.4))

		# Draw row text
		_panel.draw_string(font, Vector2(row_text_x, row_text_y), row_text,
			HORIZONTAL_ALIGNMENT_LEFT, row_text_w, font_size, text_color)

		# Cursor (only on the row containing the cursor position)
		if is_current and _editor_focused and int(_cursor_blink * 2.0) % 2 == 0:
			var row_end_off: int = row_char_off + row_text.length()
			# Cursor is on this row if its char offset falls within [row_char_off, row_end_off]
			# (use <= for end-of-row to allow cursor at the end of the last row)
			var cursor_on_row: bool
			if ri == num_rows - 1:
				cursor_on_row = _editor_cursor >= row_char_off and _editor_cursor <= row_end_off
			else:
				cursor_on_row = _editor_cursor >= row_char_off and _editor_cursor < row_end_off
			if cursor_on_row:
				var local_cursor: int = _editor_cursor - row_char_off
				var cursor_x: float = row_text_x + font.get_string_size(
					row_text.substr(0, local_cursor), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
				_panel.draw_line(Vector2(cursor_x, row_y + 3), Vector2(cursor_x, row_y + h - 3),
					Color(1.0, 0.8, 0.2), 1.5)

	return total_h


func _draw_line_viz(x: float, y: float, w: float, h: float, font: Font, line_idx: int, viz_type: String) -> void:
	## Draw the per-line visualizer strip below a code line.
	match viz_type:
		VIZ_PIANOROLL:
			_draw_line_pianoroll(x, y, w, h, font, line_idx)
		VIZ_SCOPE:
			_draw_line_scope(x, y, w, h, font, line_idx)
		VIZ_WORDFALL:
			_draw_line_wordfall(x, y, w, h, font, line_idx)
		VIZ_SPIRAL:
			_draw_line_spiral(x, y, w, h, font, line_idx)
		VIZ_PITCHWHEEL:
			_draw_line_pitchwheel(x, y, w, h, font, line_idx)
		VIZ_FSCOPE:
			_draw_line_fscope(x, y, w, h, font, line_idx)


func _draw_line_pianoroll(x: float, y: float, w: float, h: float, font: Font, line_idx: int) -> void:
	## Draw a mini pianoroll strip — supports Strudel pianoroll options.
	## Options: labels, fold, vertical, autorange, cycles, playhead, active, inactive,
	##          fill, fillActive, strokeActive, hideInactive, minMidi, maxMidi
	var opts: Dictionary = _lines[line_idx].get("viz_options", {}) if line_idx < _lines.size() else {}
	var show_labels: bool = opts.get("labels", false)
	var fold: bool = opts.get("fold", true)
	var vertical: bool = opts.get("vertical", false)
	var autorange: bool = opts.get("autorange", false)
	var viz_cycles: float = float(opts.get("cycles", PIANOROLL_CYCLES))
	var viz_playhead: float = float(opts.get("playhead", PIANOROLL_PLAYHEAD))
	var fill_notes: bool = opts.get("fill", true)
	var fill_active: bool = opts.get("fillActive", false)
	var stroke_active: bool = opts.get("strokeActive", true)
	var hide_inactive: bool = opts.get("hideInactive", false)
	var active_color := Color(1.0, 0.8, 0.2, 0.9)
	var inactive_color := Color(0.3, 0.5, 0.8, 0.5)
	var min_midi: int = int(opts.get("minMidi", 10))
	var max_midi: int = int(opts.get("maxMidi", 90))

	_panel.draw_rect(Rect2(x, y, w, h), Color(0.03, 0.03, 0.05))

	var haps: Array = _line_haps[line_idx] if line_idx < _line_haps.size() else []
	if haps.is_empty():
		return

	# Collect values for fold mode / autorange
	var values: Array = []
	for hap in haps:
		var v: float = _hap_to_pitch(hap)
		if v >= 0 and v not in values:
			values.append(v)
	if values.is_empty():
		return
	values.sort()

	if autorange:
		min_midi = int(values[0])
		max_midi = int(values[-1])

	var val_count: int
	var val_extent: float
	if fold:
		val_count = maxi(values.size(), 1)
		val_extent = val_count
	else:
		val_extent = maxf(float(max_midi - min_midi + 1), 1.0)
		val_count = int(val_extent)

	# Axis dimensions — swap for vertical mode
	var time_axis: float = w if not vertical else h
	var value_axis: float = h if not vertical else w
	var bar_size: float = value_axis / maxf(val_count, 1)
	bar_size = clampf(bar_size, 1.0, value_axis)  # Safety: at least 1px, at most full axis

	var from_time: float = _current_time - viz_cycles * viz_playhead
	var to_time: float = _current_time + viz_cycles * (1.0 - viz_playhead)
	var time_range: float = to_time - from_time

	for hap in haps:
		if hap.whole == null:
			continue
		var pitch: float = _hap_to_pitch(hap)
		if pitch < 0:
			continue
		var is_active: bool = hap.is_active(_current_time)
		if hide_inactive and not is_active:
			continue

		var hap_begin: float = hap.w().begin.to_float()
		var hap_end: float = hap.get_end_clipped().to_float()
		var time_progress: float = (hap_begin - from_time) / time_range
		var time_px: float = time_progress * time_axis
		var duration_px: float = ((hap_end - hap_begin) / time_range) * time_axis

		var val_progress: float
		if fold:
			val_progress = float(values.find(pitch)) / val_count
		else:
			val_progress = (pitch - min_midi) / val_extent

		var val_px: float = value_axis - (val_progress + 1.0 / val_count) * value_axis

		# Build rect coords based on orientation
		var rect: Rect2
		if vertical:
			rect = Rect2(x + val_px + 1, y + h - time_px - duration_px + 1, bar_size - 2, maxf(duration_px - 2, 1))
		else:
			rect = Rect2(x + time_px + 1, y + val_px + 1, maxf(duration_px - 2, 1), bar_size - 2)

		# Safety: skip degenerate rects
		if rect.size.x <= 0 or rect.size.y <= 0 or is_nan(rect.position.x) or is_nan(rect.position.y):
			continue
		# Clip to bounds
		if rect.position.x + rect.size.x < x or rect.position.x > x + w:
			continue
		if rect.position.y + rect.size.y < y or rect.position.y > y + h:
			continue
		# Clamp rect within panel
		rect = rect.intersection(Rect2(x, y, w, h))
		if rect.size.x <= 0 or rect.size.y <= 0:
			continue

		var color: Color = active_color if is_active else inactive_color
		var should_fill: bool = (is_active and fill_active) or (not is_active and fill_notes)
		var should_stroke: bool = is_active and stroke_active

		if should_fill:
			_panel.draw_rect(rect, color)
		if should_stroke:
			_panel.draw_rect(rect, color, false, 1.0)

		# Labels
		if show_labels and is_active and bar_size > 8 and duration_px > 15:
			var lbl: String = str(hap.value) if not (hap.value is Dictionary) else str(hap.value.get("note", hap.value.get("value", "")))
			_panel.draw_string(font, Vector2(rect.position.x + 2, rect.position.y + bar_size - 3),
				lbl, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 4, 7, Color(0, 0, 0, 0.8))

	# Playhead
	var ph_pos: float = viz_playhead * time_axis
	if vertical:
		_panel.draw_line(Vector2(x, y + h - ph_pos), Vector2(x + w, y + h - ph_pos), Color(1.0, 1.0, 1.0, 0.4), 1.0)
	else:
		_panel.draw_line(Vector2(x + ph_pos, y), Vector2(x + ph_pos, y + h), Color(1.0, 1.0, 1.0, 0.4), 1.0)



func _draw_line_scope(x: float, y: float, w: float, h: float, _font: Font, line_idx: int) -> void:
	## Oscilloscope-style waveform — draws the synthesized wave shape of
	## currently active notes, matching Strudel's .scope() visualizer.
	## Shows a sine wave at the pitch frequency, amplitude modulated by
	## the note's progress. When no note is active, draws a flat line.
	_panel.draw_rect(Rect2(x, y, w, h), Color(0.02, 0.02, 0.04))

	var haps: Array = _line_haps[line_idx] if line_idx < _line_haps.size() else []
	var cy: float = y + h * 0.5
	var amplitude: float = h * 0.35

	# Find active notes
	var active_pitches: Array = []
	for hap in haps:
		if hap.whole == null:
			continue
		if not hap.is_active(_current_time):
			continue
		var pitch: float = _hap_to_pitch(hap)
		if pitch >= 0:
			# Calculate progress through this note for amplitude envelope
			var dur: float = hap.get_duration().to_float()
			var progress: float = 0.0
			if dur > 0:
				progress = clampf((_current_time - hap.w().begin.to_float()) / dur, 0.0, 1.0)
			active_pitches.append({"pitch": pitch, "progress": progress})

	if active_pitches.is_empty():
		# Flat line when silent
		_panel.draw_line(Vector2(x, cy), Vector2(x + w, cy), Color(0.15, 0.2, 0.15), 1.0)
		return

	# Draw the composite waveform across the strip width
	var step_count: int = int(w)
	var prev_point := Vector2(x, cy)
	var phase_offset: float = _current_time * 20.0  # Scroll the wave with time

	for i in range(step_count):
		var t: float = float(i) / float(step_count)
		var sample: float = 0.0

		for note in active_pitches:
			# Convert MIDI pitch to a visual frequency
			# Higher pitches = more cycles across the strip
			var freq: float = (note["pitch"] - 48.0) * 0.5 + 2.0  # ~2-20 cycles across strip
			freq = maxf(freq, 1.0)
			# Amplitude envelope: attack then decay
			var env: float = 1.0 - note["progress"] * 0.7  # Fade out as note progresses
			sample += sin(TAU * (t * freq + phase_offset)) * env

		# Clamp and normalize for multiple notes
		sample = clampf(sample / maxf(active_pitches.size(), 1), -1.0, 1.0)
		var py: float = cy - sample * amplitude
		var point := Vector2(x + i, py)

		if i > 0:
			_panel.draw_line(prev_point, point, Color(0.3, 0.9, 0.4, 0.8), 1.5)
		prev_point = point



func _draw_line_wordfall(x: float, y: float, w: float, h: float, font: Font, line_idx: int) -> void:
	## Wordfall = pianoroll with preset options matching Strudel:
	## punchcard({vertical:1, labels:1, stroke:0, fillActive:1, active:'white', ...options})
	## We inject these defaults then delegate to pianoroll.
	var saved_opts: Dictionary = _lines[line_idx].get("viz_options", {}).duplicate() if line_idx < _lines.size() else {}
	# Wordfall defaults (user options override)
	var wordfall_defaults := {"vertical": true, "labels": true, "fillActive": true, "fill": false}
	wordfall_defaults.merge(saved_opts)  # User opts override defaults
	_lines[line_idx]["viz_options"] = wordfall_defaults
	_draw_line_pianoroll(x, y, w, h, font, line_idx)
	# Restore original options
	_lines[line_idx]["viz_options"] = saved_opts


func _draw_line_spiral(x: float, y: float, w: float, h: float, _font: Font, line_idx: int) -> void:
	## Archimedean spiral — Strudel's .spiral().
	## Haps are drawn as arc segments on a spiral. Active segments are bright.
	## The playhead is at a fixed inset position; the spiral rotates with time.
	_panel.draw_rect(Rect2(x, y, w, h), Color(0.02, 0.02, 0.04))

	var haps: Array = _line_haps[line_idx] if line_idx < _line_haps.size() else []
	var size: float = minf(w, h)
	var cx: float = x + w * 0.5
	var cy: float = y + h * 0.5
	var margin: float = size * 0.12  # Spiral expansion per rotation
	var inset: float = 3.0           # Playhead position (rotations from center)
	var rotate: float = _current_time  # Spiral rotates with time

	# Draw hap segments as spiral arcs
	for hap in haps:
		if hap.whole == null:
			continue
		var is_active: bool = hap.is_active(_current_time)
		var from_angle: float = hap.w().begin.to_float() - _current_time + inset
		var to_angle: float = hap.get_end_clipped().to_float() - _current_time + inset
		var color: Color = Color(0.3, 0.7, 1.0, 0.8) if is_active else Color(0.2, 0.3, 0.5, 0.3)
		# Draw arc segments along the spiral
		var steps: int = maxi(int((to_angle - from_angle) * 30), 2)
		var prev := Vector2.ZERO
		for i in range(steps + 1):
			var t: float = from_angle + (to_angle - from_angle) * float(i) / float(steps)
			var angle_rad: float = (t + rotate) * TAU
			var radius: float = margin * t
			var px: float = cx + cos(angle_rad) * radius
			var py: float = cy + sin(angle_rad) * radius
			var pt := Vector2(px, py)
			if i > 0 and pt.x > x and pt.x < x + w and pt.y > y and pt.y < y + h:
				_panel.draw_line(prev, pt, color, 2.5 if is_active else 1.5)
			prev = pt

	# Playhead dot at the inset position
	var ph_angle: float = (inset + rotate) * TAU
	var ph_r: float = margin * inset
	var ph_pos := Vector2(cx + cos(ph_angle) * ph_r, cy + sin(ph_angle) * ph_r)
	if ph_pos.x > x and ph_pos.x < x + w and ph_pos.y > y and ph_pos.y < y + h:
		_panel.draw_circle(ph_pos, 3.0, Color(1.0, 1.0, 1.0, 0.8))


func _draw_line_pitchwheel(x: float, y: float, w: float, h: float, _font: Font, line_idx: int) -> void:
	## Pitch circle — Strudel's .pitchwheel().
	## Notes placed on a circle at their chromatic position (12-EDO).
	## Active notes shown as bright circles; lines from center (flake mode).
	_panel.draw_rect(Rect2(x, y, w, h), Color(0.02, 0.02, 0.04))

	var haps: Array = _line_haps[line_idx] if line_idx < _line_haps.size() else []
	var size: float = minf(w, h)
	var cx: float = x + w * 0.5
	var cy: float = y + h * 0.5
	var radius: float = size * 0.38
	var dot_r: float = 3.0

	# Draw 12-EDO reference dots (faint)
	for i in range(12):
		var angle: float = float(i) / 12.0 * TAU - TAU / 4.0  # Start from top
		var dx: float = cx + cos(angle) * radius
		var dy: float = cy + sin(angle) * radius
		_panel.draw_circle(Vector2(dx, dy), 2.0, Color(0.2, 0.2, 0.3, 0.4))

	# Draw active notes
	for hap in haps:
		if hap.whole == null or not hap.is_active(_current_time):
			continue
		var pitch: float = _hap_to_pitch(hap)
		if pitch < 0:
			continue
		# Map MIDI pitch to position on the circle (chromatic, mod 12)
		var chroma: float = fmod(pitch, 12.0) / 12.0
		var angle: float = chroma * TAU - TAU / 4.0  # Start from top
		var dx: float = cx + cos(angle) * radius
		var dy: float = cy + sin(angle) * radius
		var color: Color = Color(0.3, 0.8, 1.0, 0.9)
		# Flake mode: line from center to note
		_panel.draw_line(Vector2(cx, cy), Vector2(dx, dy), Color(color.r, color.g, color.b, 0.3), 1.0)
		# Note dot
		_panel.draw_circle(Vector2(dx, dy), dot_r + 1.5, color)


func _draw_line_fscope(x: float, y: float, w: float, h: float, _font: Font, line_idx: int) -> void:
	## Frequency spectrum — Strudel's .fscope().
	## Since we don't have a real audio analyser, we simulate the spectrum
	## by showing vertical bars at each active note's frequency position.
	_panel.draw_rect(Rect2(x, y, w, h), Color(0.02, 0.02, 0.04))

	var haps: Array = _line_haps[line_idx] if line_idx < _line_haps.size() else []
	if haps.is_empty():
		return

	# Frequency range: map MIDI 24-96 to the strip width (log scale)
	var min_midi: float = 24.0
	var max_midi: float = 96.0
	var midi_range: float = max_midi - min_midi

	for hap in haps:
		if hap.whole == null or not hap.is_active(_current_time):
			continue
		var pitch: float = _hap_to_pitch(hap)
		if pitch < 0:
			continue
		# Map pitch to x position (linear in MIDI = log in frequency)
		var norm: float = clampf((pitch - min_midi) / midi_range, 0.0, 1.0)
		var bx: float = x + norm * (w - 4)
		# Bar height based on velocity/gain or fixed
		var bar_h: float = h * 0.7
		# Amplitude decay based on note progress
		var dur: float = hap.get_duration().to_float()
		var progress: float = 0.0
		if dur > 0:
			progress = clampf((_current_time - hap.w().begin.to_float()) / dur, 0.0, 1.0)
		bar_h *= (1.0 - progress * 0.5)
		var bar_w: float = maxf(w / 72.0, 2.0)  # ~1 bar per MIDI note
		var by: float = y + h - bar_h
		var color: Color = Color(0.3, 0.7, 1.0, 0.7 - progress * 0.3)
		_panel.draw_rect(Rect2(bx, by, bar_w, bar_h), color)


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
