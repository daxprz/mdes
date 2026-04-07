class_name StrudelLineCompiler extends RefCounted

## Strudel line compiler — parses and compiles .strudel file lines into
## StrudelPattern objects.  Extracted from MusicDrawer so that the Composition
## system, MusicManager, and any non-UI code can parse .strudel files without
## depending on the drawer.
##
## All methods are static.  No UI or scene-tree dependencies.


# -- Constants -----------------------------------------------------------------

## Audio control method names -> canonical Strudel control key.
## Parsed from method chains like .lpf(800).room(0.5).
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

## Signal names for the signal expression parser.
const SIGNAL_NAMES := ["sine", "saw", "isaw", "cosine", "tri", "square", "rand"]

## Viz type constants — kept for parse_line results, no UI dependency.
const VIZ_NONE := "none"
const VIZ_PIANOROLL := "pianoroll"
const VIZ_SCOPE := "scope"
const VIZ_WORDFALL := "wordfall"
const VIZ_SPIRAL := "spiral"
const VIZ_PITCHWHEEL := "pitchwheel"
const VIZ_FSCOPE := "fscope"


# -- File Processing -----------------------------------------------------------

static func resolve_strudel_path(path_or_name: String) -> String:
	## Resolve a strudel file path.  Tries:
	## 1. Absolute/res://user:// path as-is (with extension fallback)
	## 2. res://data/strudel/<name> with .strudel/.js/.txt extensions
	## 3. user://patterns/<name> with .txt extension
	if path_or_name.begins_with("/") or path_or_name.begins_with("res://") or path_or_name.begins_with("user://"):
		if FileAccess.file_exists(path_or_name):
			return path_or_name
		for ext in [".strudel", ".js", ".txt"]:
			if FileAccess.file_exists(path_or_name + ext):
				return path_or_name + ext
		return ""
	var name: String = path_or_name
	for dir_path in ["res://data/strudel/", "user://patterns/"]:
		for ext in ["", ".strudel", ".js", ".txt"]:
			var candidate: String = dir_path + name + ext
			if FileAccess.file_exists(candidate):
				return candidate
	return ""


static func read_strudel_file(path: String) -> Array[String]:
	## Read a strudel file and return its raw lines.
	## Returns empty array on failure.
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return []
	var raw_lines: Array[String] = []
	while not file.eof_reached():
		raw_lines.append(file.get_line())
	file.close()
	# Trim trailing blank lines
	while not raw_lines.is_empty() and raw_lines[-1].strip_edges().is_empty():
		raw_lines.pop_back()
	return raw_lines


static func merge_continuation_lines(raw_lines: Array[String]) -> Array[String]:
	## Merge multi-line expressions by tracking paren depth.
	## Lines with unclosed parens are continuation lines joined with spaces.
	## Comments and blank lines are preserved as separate entries when at depth 0.
	var result: Array[String] = []
	var current: String = ""
	var depth: int = 0
	for rl in raw_lines:
		var cl: String = rl.strip_edges()
		if cl.is_empty() or cl.begins_with("//") or cl.begins_with("#"):
			if depth == 0 and not current.is_empty():
				result.append(current)
				current = ""
			if cl.begins_with("//") or cl.begins_with("#"):
				result.append(cl)
			continue
		if current.is_empty():
			current = cl
		else:
			current += " " + cl
		# Count parens (outside of quoted strings)
		var in_str: bool = false
		var str_char: String = ""
		for ci in range(cl.length()):
			var ch: String = cl[ci]
			if in_str:
				if ch == str_char:
					in_str = false
			elif ch == '"' or ch == "'":
				in_str = true
				str_char = ch
			elif ch == '(':
				depth += 1
			elif ch == ')':
				depth = maxi(0, depth - 1)
		if depth == 0:
			result.append(current)
			current = ""
	if not current.is_empty():
		result.append(current)
	return result


static func expand_stacks(lines: Array[String]) -> Array[String]:
	## Expand stack(...) lines into individual sub-expressions.
	## "stack(a, b, c)" becomes three lines: "a", "b", "c".
	## Standalone comments are dropped (they were between stack sub-expressions
	## in the file).  The file comment at the top is kept only if first line.
	var result: Array[String] = []
	for li in range(lines.size()):
		var stripped: String = lines[li].strip_edges()
		# Drop standalone comments (except the very first line as a file header)
		if stripped.begins_with("//") or stripped.begins_with("#"):
			if li == 0:
				result.append(stripped)
			continue
		if stripped.begins_with("stack(") and stripped.ends_with(")"):
			var inner: String = stripped.substr(6, stripped.length() - 7)
			var subs: Array = split_top_level_commas(inner)
			if subs.size() > 1:
				for sub in subs:
					var sub_text: String = sub["text"] if sub is Dictionary else str(sub)
					sub_text = sub_text.strip_edges()
					if not sub_text.is_empty():
						result.append(sub_text)
				continue
		result.append(stripped)
	return result


# -- Line Dict Factory ---------------------------------------------------------

static func make_line(text: String = "", name: String = "") -> Dictionary:
	## Create a minimal line dict suitable for parse_line().
	return {
		"text": text, "name": name, "muted": false,
		"viz": VIZ_NONE, "viz_options": {}, "pattern_offset": 0, "block_id": -1,
	}


# -- Line Parsing --------------------------------------------------------------

static func parse_line(line: Dictionary) -> Dictionary:
	## Parse a line dict into a result describing its contents.
	##
	## PURE — does NOT mutate `line`.  All metadata is returned in the result dict.
	## The caller (e.g. MusicDrawer._resolve_line) is responsible for applying
	## result["name"], result["viz"], result["viz_options"] back to the line dict
	## if it wants to.
	##
	## Result keys:
	##   pattern_text: String        — mini-notation text (after stripping wrappers/chains)
	##   name: String                — track label (from "sub: note(...)" syntax)
	##   sound: String               — voice name (from .s("sine"))
	##   is_valid: bool              — true if a playable pattern was found
	##   viz: String                 — visualizer type (VIZ_NONE, VIZ_PIANOROLL, etc.)
	##   viz_options: Dictionary     — viz options ({labels:1, fold:0})
	##   pattern_offset: int         — char position where mini-notation starts in raw text
	##   audio_controls: Dictionary  — {gain: 0.12, lpf: 800, ...}
	##   signal_controls: Array      — [StrudelPattern, ...] for signal-modulated controls
	##   deferred_ops: Array         — [{method, args, args_offset}, ...] pattern transforms
	##   wrapper_type: String        — "note", "s", "n", or ""
	##   is_stack: bool              — true if stack() expression
	##   stack_exprs: Array          — [{text, pos}, ...] sub-expressions
	##   stack_offset: int           — char offset of stack inner content
	##   setcps: float               — (present only for setcps/setcpm directives)
	##   hush: bool                  — (present only for hush directives)
	##   is_let: bool                — (present only for let bindings)
	##   let_name: String            — (present only for let bindings)
	##   let_expr: String            — (present only for let bindings)
	var raw: String = line.get("text", "")
	var result := {
		"pattern_text": "", "name": line.get("name", ""), "sound": "",
		"is_valid": false, "viz": VIZ_NONE, "pattern_offset": 0,
	}

	var stripped: String = raw.strip_edges()
	if stripped.is_empty() or stripped.begins_with("#") or stripped.begins_with("//"):
		return result

	# Handle let bindings: let name = expression
	if stripped.begins_with("let "):
		var after_let: String = stripped.substr(4).strip_edges()
		var eq_idx: int = after_let.find("=")
		if eq_idx > 0:
			var var_name: String = after_let.substr(0, eq_idx).strip_edges()
			var var_expr: String = after_let.substr(eq_idx + 1).strip_edges()
			if var_name.is_valid_identifier() and not var_expr.is_empty():
				result["is_let"] = true
				result["let_name"] = var_name
				result["let_expr"] = var_expr
				result["is_valid"] = false
				return result

	# Handle JS-style top-level function calls and keywords
	if stripped.begins_with("setcps(") and stripped.ends_with(")"):
		var inner: String = stripped.substr(7, stripped.length() - 8).strip_edges()
		if inner.is_valid_float():
			result["setcps"] = float(inner)
			result["is_valid"] = false
			return result
	if stripped.begins_with("setcpm(") and stripped.ends_with(")"):
		var inner: String = stripped.substr(7, stripped.length() - 8).strip_edges()
		if inner.is_valid_float():
			result["setcps"] = float(inner) / 60.0
			result["is_valid"] = false
			return result
	if stripped == "hush" or stripped == "hush()":
		result["hush"] = true
		result["is_valid"] = false
		return result

	var text: String = raw
	var offset: int = 0  # Track chars consumed from the front

	# Check for "name: pattern" syntax (Strudel label style)
	var colon_idx: int = text.find(": ")
	if colon_idx > 0 and colon_idx < 20:
		var candidate: String = text.substr(0, colon_idx).strip_edges()
		if candidate.is_valid_identifier():
			result["name"] = candidate
			# NOTE: we do NOT write line["name"] — that's the caller's job
			offset = colon_idx + 2
			text = text.substr(offset)
			while not text.is_empty() and text[0] == " ":
				offset += 1
				text = text.substr(1)

	result["pattern_offset"] = offset

	# -- Method chain parsing (viz + audio + pattern combinators) ----------------
	# Viz method names -> viz type
	var viz_names := {
		"pianoroll": VIZ_PIANOROLL, "punchcard": VIZ_PIANOROLL, "_pianoroll": VIZ_PIANOROLL,
		"scope": VIZ_SCOPE, "tscope": VIZ_SCOPE, "_scope": VIZ_SCOPE,
		"wordfall": VIZ_WORDFALL,
		"spiral": VIZ_SPIRAL, "_spiral": VIZ_SPIRAL,
		"pitchwheel": VIZ_PITCHWHEEL, "_pitchwheel": VIZ_PITCHWHEEL,
		"fscope": VIZ_FSCOPE,
	}

	var stripped_text: String = text.strip_edges()
	var viz_options: Dictionary = {}
	var audio_controls: Dictionary = {}
	var signal_controls: Array = []
	var found_viz: bool = false

	# Pattern combinator methods
	var pattern_methods := [
		"degrade", "degradeBy", "undegrade", "undegradeBy",
		"fast", "slow", "hurry",
		"early", "late",
		"rev", "palindrome",
		"euclid", "euclidRot",
		"every",
		"chunk",
		"segment",
		"sometimes", "often", "rarely",
		"add", "sub", "mul",
		"superimpose", "layer",
		"jux",
		"off",
		"iter",
		"ply",
		"striate",
		"chop",
	]

	# Build combined lookup of all known method names
	var all_methods: Dictionary = {}
	for k in viz_names:
		all_methods[k] = "viz"
	for k in AUDIO_CONTROL_METHODS:
		all_methods[k] = "audio"
	for k in pattern_methods:
		all_methods[k] = "pattern"
	var deferred_ops: Array = []

	# Parse method chain from right to left: find the rightmost known
	# .method(args) whose closing paren is at the end of the string,
	# strip it, and repeat.
	var chain_changed: bool = true
	while chain_changed:
		chain_changed = false

		var best_pos: int = -1
		var best_method: String = ""
		var best_paren_open: int = -1
		var best_paren_close: int = -1

		for method_name in all_methods:
			var prefix: String = "." + method_name + "("
			var pos: int = stripped_text.rfind(prefix)
			if pos < 0:
				continue
			var po: int = pos + prefix.length()
			# Find BALANCED closing paren
			var depth: int = 1
			var pc: int = po
			while pc < stripped_text.length() and depth > 0:
				if stripped_text[pc] == "(":
					depth += 1
				elif stripped_text[pc] == ")":
					depth -= 1
				if depth > 0:
					pc += 1
			if depth != 0:
				continue
			# Must be at end of string
			if pc < stripped_text.length() - 1:
				var after: String = stripped_text.substr(pc + 1).strip_edges()
				if not after.is_empty():
					continue
			if pos > best_pos:
				best_pos = pos
				best_method = method_name
				best_paren_open = po
				best_paren_close = pc

		if best_pos < 0:
			break

		var args_str: String = stripped_text.substr(best_paren_open, best_paren_close - best_paren_open).strip_edges()
		var kind: String = all_methods[best_method]

		if kind == "viz":
			if not found_viz:
				result["viz"] = viz_names[best_method]
				if not args_str.is_empty():
					viz_options = parse_viz_options(args_str)
				result["viz_options"] = viz_options
				found_viz = true
		elif kind == "pattern":
			var args_offset_in_line: int = offset + best_paren_open
			deferred_ops.append({"method": best_method, "args": args_str, "args_offset": args_offset_in_line})
		else:
			var control_key: String = AUDIO_CONTROL_METHODS[best_method]
			if control_key == "s":
				var voice_val: String = args_str.replace("\"", "").replace("'", "").strip_edges()
				if not voice_val.is_empty():
					result["sound"] = voice_val
			elif control_key in ["clip", "duration"]:
				if args_str.is_valid_float():
					deferred_ops.append({"method": "_set_in", "args": control_key, "value": float(args_str)})
				else:
					var signal_pat: StrudelPattern = parse_signal_expr(args_str)
					if signal_pat != null:
						var ck: String = control_key
						signal_pat = signal_pat.fmap(func(v: Variant) -> Dictionary:
							return {ck: float(v)})
						signal_controls.append(signal_pat)
			elif args_str.is_valid_float():
				audio_controls[control_key] = float(args_str)
			else:
				var signal_pat: StrudelPattern = parse_signal_expr(args_str)
				if signal_pat != null:
					var ck: String = control_key
					signal_pat = signal_pat.fmap(func(v: Variant) -> Dictionary:
						return {ck: float(v)})
					signal_controls.append(signal_pat)

		stripped_text = stripped_text.substr(0, best_pos).strip_edges()
		chain_changed = true

	result["audio_controls"] = audio_controls
	result["signal_controls"] = signal_controls
	result["deferred_ops"] = deferred_ops

	# If no viz found from method chain but viz text was present, record VIZ_NONE
	if not found_viz:
		var had_viz_text: bool = false
		for method_name in viz_names:
			if ("." + method_name + "(") in raw:
				had_viz_text = true
				break
		if had_viz_text:
			result["viz"] = VIZ_NONE
			result["viz_options"] = {}

	# Handle stack(): split into sub-expressions evaluated independently.
	if stripped_text.begins_with("stack(") and stripped_text.ends_with(")"):
		var inner: String = stripped_text.substr(6, stripped_text.length() - 7)
		var sub_exprs: Array = split_top_level_commas(inner)
		if sub_exprs.size() > 1:
			var stack_pos: int = raw.find("stack(")
			var stack_inner_offset: int = (stack_pos + 6) if stack_pos >= 0 else offset
			for se in sub_exprs:
				var raw_sub: String = inner.substr(se["pos"])
				var comma_or_end: int = raw_sub.find(",")
				if comma_or_end < 0:
					comma_or_end = raw_sub.length()
				raw_sub = raw_sub.substr(0, comma_or_end)
				var leading: int = raw_sub.length() - raw_sub.lstrip(" \t").length()
				se["pos"] = se["pos"] + leading
			result["is_stack"] = true
			result["stack_exprs"] = sub_exprs
			result["stack_offset"] = stack_inner_offset
			result["is_valid"] = true
			result["pattern_text"] = ""
			return result

	# Strip Strudel wrappers: note("..."), s("..."), sound("..."), n("...")
	var wrapper_type: String = ""
	for wrapper in ["note(", "s(", "sound(", "n("]:
		if stripped_text.begins_with(wrapper) and stripped_text.ends_with(")"):
			wrapper_type = "s" if wrapper in ["s(", "sound("] else ("n" if wrapper == "n(" else "note")
			stripped_text = stripped_text.substr(wrapper.length(), stripped_text.length() - wrapper.length() - 1).strip_edges()
			break
	result["wrapper_type"] = wrapper_type

	# Strip surrounding quotes
	if stripped_text.length() >= 2:
		if (stripped_text[0] == '"' and stripped_text[-1] == '"') or \
		   (stripped_text[0] == "'" and stripped_text[-1] == "'") or \
		   (stripped_text[0] == '`' and stripped_text[-1] == '`'):
			var inner: String = stripped_text.substr(1, stripped_text.length() - 2)
			var quote_pos: int = text.find(stripped_text[0])
			if quote_pos >= 0:
				offset += quote_pos + 1
				result["pattern_offset"] = offset
			stripped_text = inner

	text = stripped_text

	# Extract key=value parameters (cps, sound, and audio controls)
	for param in ["cps=", "sound=", "s="]:
		var p_idx: int = text.find(param)
		if p_idx >= 0:
			var p_val: String = text.substr(p_idx + param.length()).strip_edges()
			var space_idx: int = p_val.find(" ")
			if space_idx >= 0:
				p_val = p_val.substr(0, space_idx)
			if param == "cps=":
				if p_val.is_valid_float():
					# Return inline CPS in result — caller decides what to do with it
					result["inline_cps"] = float(p_val)
			else:
				result["sound"] = p_val
			text = (text.substr(0, p_idx) + text.substr(p_idx + param.length() + p_val.length())).strip_edges()

	# Also extract audio control key=value params
	for ctrl_param in ["gain=", "velocity=", "lpf=", "hpf=", "room=", "delay=",
						"distort=", "crush=", "pan=", "roomsize=", "delaytime=",
						"delayfeedback=", "shape=", "lpq=", "hpq=", "roomlp="]:
		var p_idx: int = text.find(ctrl_param)
		if p_idx >= 0:
			var p_val: String = text.substr(p_idx + ctrl_param.length()).strip_edges()
			var space_idx: int = p_val.find(" ")
			if space_idx >= 0:
				p_val = p_val.substr(0, space_idx)
			if p_val.is_valid_float():
				var key: String = ctrl_param.substr(0, ctrl_param.length() - 1)
				audio_controls[key] = float(p_val)
			text = (text.substr(0, p_idx) + text.substr(p_idx + ctrl_param.length() + p_val.length())).strip_edges()

	if not text.is_empty():
		result["pattern_text"] = text
		result["is_valid"] = true
	return result


# -- Pattern Compilation -------------------------------------------------------

static func compile_parsed(parsed: Dictionary, resolver: Callable = Callable()) -> StrudelPattern:
	## Compile a parsed line result into a Pattern.
	## Handles stack, mini-notation, wrapper types, and deferred ops.
	##
	## `resolver` is an optional Callable(String) -> StrudelPattern that resolves
	## let-variable references in stack sub-expressions.  Returns null if the text
	## is not a known binding.  Pass Callable() (empty) to skip resolution.
	var pat: StrudelPattern
	if parsed.get("is_stack", false):
		var sub_pats: Array = []
		var stack_base: int = parsed.get("stack_offset", 0)
		for sub in parsed["stack_exprs"]:
			var sub_text: String = (sub["text"] if sub is Dictionary else str(sub)).strip_edges()
			var sub_pos: int = sub["pos"] if sub is Dictionary else 0
			# Try resolver first (let variable references)
			var resolved: StrudelPattern = null
			if resolver.is_valid():
				resolved = resolver.call(sub_text)
			if resolved != null:
				sub_pats.append(resolved)
			else:
				sub_pats.append(eval_sub_expr(sub_text, stack_base + sub_pos))
		pat = Strudel.stack(sub_pats)
	else:
		pat = StrudelMini.mini(parsed["pattern_text"])
		var wt: String = parsed.get("wrapper_type", "")
		if wt == "s":
			pat = pat.fmap(func(v: Variant) -> Dictionary:
				return {"s": str(v), "note": "c4"})
		elif wt == "n":
			pat = pat.fmap(func(v: Variant) -> Dictionary:
				return {"n": int(v) if v is float or v is int else 0})
	var ops: Array = parsed.get("deferred_ops", [])
	if not ops.is_empty():
		pat = apply_deferred_ops(pat, ops)
	return pat


static func eval_sub_expr(expr: String, base_offset: int = 0) -> StrudelPattern:
	## Evaluate a single Strudel sub-expression (e.g., note("c3 g3").s("sawtooth").lpf(800)).
	## Handles full method chains (audio controls, pattern transforms, viz),
	## note()/s()/n() wrappers, and quoted mini-notation.
	## base_offset: character position of expr within the full line (for source highlighting).
	var text: String = expr.strip_edges()
	var inner_offset: int = base_offset + (expr.length() - expr.strip_edges().length())
	var voice: String = ""
	var audio_controls: Dictionary = {}
	var deferred_ops: Array = []

	# Build method lookup
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

	# Strip method chains from right to left
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
	var sub_wrapper: String = ""
	if text.begins_with("note(") and text.ends_with(")"):
		sub_wrapper = "note"
		inner_offset += 5
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
			inner_offset += 1
			text = text.substr(1, text.length() - 2)

	var pat: StrudelPattern = StrudelMini.mini(text, inner_offset)

	# s() wrapper: each token is a voice name
	if sub_wrapper == "s":
		pat = pat.fmap(func(v: Variant) -> Dictionary:
			return {"s": str(v), "note": "c4"})
	elif sub_wrapper == "n":
		pat = pat.fmap(func(v: Variant) -> Dictionary:
			return {"n": int(v) if v is float or v is int else 0})

	# Apply deferred pattern ops
	if not deferred_ops.is_empty():
		pat = apply_deferred_ops(pat, deferred_ops)

	if not voice.is_empty():
		pat = pat.set_in(Strudel.pure({"s": voice}))
	return pat


# -- Deferred Ops Application --------------------------------------------------

static func apply_deferred_ops(pat: StrudelPattern, ops: Array) -> StrudelPattern:
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
					pat = pat._fast(float(args))
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
				var layer_parts: Array = split_top_level_commas(args)
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
				var si_key: String = args
				var si_val: float = op.get("value", 1.0)
				pat = pat.set_in(Strudel.pure({si_key: si_val}))
	return pat


# -- Transform Parsing ---------------------------------------------------------

static func _parse_transform_fn(expr: String) -> Variant:
	## Parse a pattern-transforming function from a string.
	## Returns a Callable(StrudelPattern) -> StrudelPattern, or null if unparseable.
	var s: String = expr.strip_edges()
	if s.is_empty():
		return null
	# Arrow function: x=>x.method(...) or x => x.method(...)
	var arrow_idx: int = s.find("=>")
	if arrow_idx >= 0:
		var body: String = s.substr(arrow_idx + 2).strip_edges()
		var dot_idx: int = body.find(".")
		if dot_idx < 0:
			return null
		body = body.substr(dot_idx)
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
	var transforms: Array = []
	var remaining: String = chain.strip_edges()
	while remaining.begins_with("."):
		remaining = remaining.substr(1)
		var paren_pos: int = remaining.find("(")
		var fn_name: String
		var args_str: String = ""
		if paren_pos < 0:
			fn_name = remaining.strip_edges()
			remaining = ""
		else:
			fn_name = remaining.substr(0, paren_pos).strip_edges()
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
	var fns: Array = transforms
	return func(p: StrudelPattern) -> StrudelPattern:
		var result: StrudelPattern = p
		for fn in fns:
			result = fn.call(result)
		return result


static func _parse_transform_arg(args_str: String, base_offset: int = 0) -> Variant:
	## Parse a transform argument — a number, note() wrapper, or quoted mini.
	var s: String = args_str.strip_edges()
	var inner_offset: int = base_offset + (args_str.length() - args_str.strip_edges().length())
	if s.is_empty():
		return null
	# note(N) wrapper -> wrap as {note: N} dict for per-key merging
	if s.begins_with("note(") and s.ends_with(")"):
		var inner: String = s.substr(5, s.length() - 6).strip_edges()
		inner_offset += 5
		if inner.length() >= 2 and ((inner[0] == '"' and inner[-1] == '"') or (inner[0] == "'" and inner[-1] == "'")):
			inner_offset += 1
			inner = inner.substr(1, inner.length() - 2)
		if inner.is_valid_float():
			return {"note": float(inner)}
		return StrudelMini.mini(inner)._strip_locations().fmap(func(v: Variant) -> Dictionary:
			return {"note": float(v) if v is float or v is int else 0})
	# Strip quotes
	if s.length() >= 2 and ((s[0] == '"' and s[-1] == '"') or (s[0] == "'" and s[-1] == "'")):
		inner_offset += 1
		s = s.substr(1, s.length() - 2)
	# Try as number
	if s.is_valid_float():
		return float(s)
	# Try as mini-notation pattern
	if not s.is_empty():
		return StrudelMini.mini(s)._strip_locations()
	return null


static func _build_single_transform(fn_name: String, args_str: String) -> Variant:
	## Build a single transform Callable from a function name and args string.
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


# -- Signal Expression Parsing -------------------------------------------------

static func parse_signal_expr(expr: String) -> StrudelPattern:
	## Parse a Strudel signal expression like "sine.range(200, 2000).slow(2)".
	## Returns a StrudelPattern, or null if the expression isn't a signal.
	expr = expr.strip_edges()
	if expr.is_empty():
		return null
	var dot_pos: int = expr.find(".")
	var signal_name: String = expr if dot_pos < 0 else expr.substr(0, dot_pos)
	signal_name = signal_name.strip_edges().to_lower()
	if signal_name not in SIGNAL_NAMES:
		return null
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
	if dot_pos < 0:
		return pat
	var remaining: String = expr.substr(dot_pos)
	while not remaining.is_empty():
		if not remaining.begins_with("."):
			break
		remaining = remaining.substr(1)
		var paren_pos: int = remaining.find("(")
		if paren_pos < 0:
			break
		var method: String = remaining.substr(0, paren_pos).strip_edges()
		var close_pos: int = remaining.find(")", paren_pos)
		if close_pos < 0:
			break
		var args_str: String = remaining.substr(paren_pos + 1, close_pos - paren_pos - 1).strip_edges()
		remaining = remaining.substr(close_pos + 1)
		var args: Array[float] = []
		for arg in args_str.split(","):
			arg = arg.strip_edges()
			if arg.is_valid_float():
				args.append(float(arg))
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


# -- Utility -------------------------------------------------------------------

static func parse_viz_options(opts_str: String) -> Dictionary:
	## Parse simple JS-like options: {labels:1, fold:0} or {labels: true}
	var result: Dictionary = {}
	opts_str = opts_str.strip_edges()
	if opts_str.begins_with("{"):
		opts_str = opts_str.substr(1)
	if opts_str.ends_with("}"):
		opts_str = opts_str.substr(0, opts_str.length() - 1)
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
		if val_str == "true":
			result[key] = true
		elif val_str == "false":
			result[key] = false
		elif val_str.is_valid_float():
			result[key] = float(val_str) if "." in val_str else int(val_str)
		else:
			result[key] = val_str
	return result


static func split_top_level_commas(text: String) -> Array:
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


static func _is_ident_char(c: String) -> bool:
	## Returns true if c is a valid identifier character.
	var code: int = c.unicode_at(0)
	return (code >= 65 and code <= 90) or (code >= 97 and code <= 122) \
		or (code >= 48 and code <= 57) or code == 95


# -- Convenience: Compile a whole .strudel file --------------------------------

static func compile_strudel_file(path: String) -> Dictionary:
	## Read, parse, and compile a .strudel file into track data.
	##
	## Returns: {
	##   tracks: Array[Dictionary]  — [{pattern, voice, gain, name, controls, signals, source_text}]
	##   cps: float                 — tempo (cycles per second)
	##   stacked: StrudelPattern    — all tracks combined via Strudel.stack()
	##   source: String             — newline-joined source lines
	##   error: String              — empty on success, error message on failure
	## }
	var resolved: String = resolve_strudel_path(path)
	if resolved.is_empty():
		return {"tracks": [], "cps": 0.5, "stacked": null, "source": "", "error": "file not found: %s" % path}

	var raw_lines: Array[String] = read_strudel_file(resolved)
	if raw_lines.is_empty():
		return {"tracks": [], "cps": 0.5, "stacked": null, "source": "", "error": "empty file: %s" % path}

	var merged: Array[String] = merge_continuation_lines(raw_lines)
	var expanded: Array[String] = expand_stacks(merged)

	var cps: float = -1.0
	var patterns: Array[StrudelPattern] = []
	var source_lines: Array[String] = []
	var tracks: Array = []

	for line_text in expanded:
		var stripped: String = line_text.strip_edges()
		if stripped.is_empty() or stripped.begins_with("//") or stripped.begins_with("#"):
			continue

		var line_dict: Dictionary = make_line(stripped)
		var parsed: Dictionary = parse_line(line_dict)

		# Handle setcps/setcpm directives
		if parsed.has("setcps"):
			if cps < 0:
				cps = parsed["setcps"]
			continue

		# Handle inline cps= parameter
		if parsed.has("inline_cps") and cps < 0:
			cps = parsed["inline_cps"]

		if parsed.get("hush", false):
			continue

		if not parsed["is_valid"]:
			continue

		var pat: StrudelPattern = compile_parsed(parsed)

		var sound_name: String = parsed.get("sound", "")
		if not sound_name.is_empty():
			pat = pat.set_in(Strudel.pure({"s": sound_name}))

		var controls: Dictionary = parsed.get("audio_controls", {})

		# Inject gain into hap values so _resolve_velocity() picks it up in note mode.
		# Only gain is injected — other audio controls (lpf, room, etc.) are bus-level
		# effects handled separately.  Per-note controls (clip, duration) are already
		# in the pattern via deferred_ops from compile_parsed.
		var track_gain: float = float(controls.get("gain", controls.get("velocity", 1.0)))
		if track_gain != 1.0:
			pat = pat.set_in(Strudel.pure({"gain": track_gain}))
		patterns.append(pat)
		source_lines.append(stripped)
		tracks.append({
			"pattern": pat,
			"voice": sound_name,
			"gain": float(controls.get("gain", controls.get("velocity", 1.0))),
			"name": parsed.get("name", ""),
			"controls": controls,
			"signals": parsed.get("signal_controls", []),
			"source_text": stripped,
		})

	if patterns.is_empty():
		return {"tracks": [], "cps": cps if cps > 0 else 0.5, "stacked": null, "source": "", "error": "no valid patterns in %s" % path}

	var stacked: StrudelPattern
	if patterns.size() == 1:
		stacked = patterns[0]
	else:
		stacked = Strudel.stack(patterns)

	return {
		"tracks": tracks,
		"cps": cps if cps > 0 else 0.5,
		"stacked": stacked,
		"source": "\n".join(source_lines),
		"error": "",
	}
