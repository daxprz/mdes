class_name StrudelMiniParser extends RefCounted

## Recursive-descent parser for Strudel mini-notation.
## Replaces the PEG-generated krill-parser.js (~2600 lines) with a
## hand-written GDScript parser (~400 lines).
##
## Grammar (from krill.pegjs v1.2.0):
##   statement    = mini_definition
##   mini         = quote stack_or_choose quote
##   stack_or_choose = sequence (stack_tail | choose_tail | dot_tail)?
##   sequence     = slice_with_ops+
##   slice_with_ops = slice ops*
##   slice        = step | sub_cycle | polymeter | slow_sequence
##   step         = [a-zA-Z0-9~\-#.^_]+
##   sub_cycle    = "[" stack_or_choose "]"
##   polymeter    = "{" polymeter_stack "}" ("%"slice)?
##   slow_sequence = "<" polymeter_stack ">"
##   ops          = "*"slice | "/"slice | "("p,s,r?")" | "?"n? | "!"n? | "@"n? | ":"slice | ".."slice

# -- AST Node Types ------------------------------------------------------------

## All nodes are plain Dictionaries with a "type_" key.
## This matches Strudel's AST shape exactly for compatibility with patternifyAST.

static func atom_node(source: String, start: int, end: int) -> Dictionary:
	return {
		"type_": "atom",
		"source_": source,
		"location_": {"start": {"offset": start}, "end": {"offset": end}},
	}

static func pattern_node(sources: Array, alignment: String, seed: int = -1, steps: bool = false) -> Dictionary:
	var node := {
		"type_": "pattern",
		"source_": sources,
		"arguments_": {"alignment": alignment, "_steps": steps},
	}
	if seed >= 0:
		node["arguments_"]["seed"] = seed
	return node

static func element_node(source: Dictionary, ops: Array = [], weight: Variant = null, reps: int = 1) -> Dictionary:
	return {
		"type_": "element",
		"source_": source,
		"options_": {"ops": ops, "weight": weight, "reps": reps},
	}

# -- Parser State --------------------------------------------------------------

var _code: String       ## The full mini-notation string (without surrounding quotes)
var _pos: int           ## Current parse position
var _seed: int = 0      ## Auto-incrementing seed for random/degrade operations
var _errors: Array = [] ## Collected parse errors


# -- Public API ----------------------------------------------------------------

func parse(code: String) -> Dictionary:
	## Parse a mini-notation string (without quotes) into an AST.
	_code = code
	_pos = 0
	_seed = 0
	_errors = []

	_skip_ws()
	if _pos >= _code.length():
		# Empty string = silence
		return atom_node("~", 0, 0)

	var result: Dictionary = _parse_stack_or_choose()

	if not _errors.is_empty():
		push_warning("StrudelMiniParser: %d parse error(s) in '%s'" % [_errors.size(), code])

	return result


func get_errors() -> Array:
	return _errors


# -- Recursive Descent ---------------------------------------------------------

func _parse_stack_or_choose() -> Dictionary:
	## stack_or_choose = sequence (stack_tail | choose_tail | dot_tail)?
	var head: Dictionary = _parse_sequence()
	_skip_ws()

	if _pos < _code.length() and _peek() == ",":
		# Stack: comma-separated sequences
		var items: Array = [head]
		while _pos < _code.length() and _peek() == ",":
			_advance()  # skip comma
			_skip_ws()
			items.append(_parse_sequence())
			_skip_ws()
		return pattern_node(items, "stack")

	if _pos < _code.length() and _peek() == "|":
		# Choose: pipe-separated sequences (random pick each cycle)
		var items: Array = [head]
		var s: int = _seed
		_seed += 1
		while _pos < _code.length() and _peek() == "|":
			_advance()  # skip pipe
			_skip_ws()
			items.append(_parse_sequence())
			_skip_ws()
		return pattern_node(items, "rand", s)

	if _pos < _code.length() and _peek() == ".":
		# Check it's a dot separator, not part of a number/atom
		var next_pos: int = _pos + 1
		if next_pos < _code.length() and _code[next_pos] == ".":
			# ".." is range operator, not dot separator — fall through
			return head
		if next_pos >= _code.length() or not _code[next_pos].is_valid_int():
			# Foot separator
			var items: Array = [head]
			var s: int = _seed
			_seed += 1
			while _pos < _code.length() and _peek() == ".":
				var after_dot: int = _pos + 1
				if after_dot < _code.length() and _code[after_dot] == ".":
					break  # ".." range, not dot
				if after_dot < _code.length() and _code[after_dot].is_valid_int():
					break  # decimal number
				_advance()  # skip dot
				_skip_ws()
				items.append(_parse_sequence())
				_skip_ws()
			return pattern_node(items, "feet", s)

	return head


func _parse_sequence() -> Dictionary:
	## sequence = slice_with_ops+
	var items: Array = []
	_skip_ws()

	# Check for ^ prefix (explicit steps)
	var explicit_steps: bool = false
	if _pos < _code.length() and _peek() == "^":
		explicit_steps = true
		_advance()
		_skip_ws()

	while _pos < _code.length():
		var c: String = _peek()
		# Stop at delimiters that belong to parent rules
		if c in ["]", "}", ">", ",", "|"]:
			break
		# Also stop at "." if it's a dot separator (not decimal)
		if c == ".":
			var next_pos: int = _pos + 1
			if next_pos >= _code.length() or (not _code[next_pos].is_valid_int() and _code[next_pos] != "."):
				break

		var elem: Dictionary = _parse_slice_with_ops()
		items.append(elem)
		_skip_ws()

	if items.is_empty():
		return pattern_node([element_node(atom_node("~", _pos, _pos))], "fastcat")

	return pattern_node(items, "fastcat", -1, explicit_steps)


func _parse_slice_with_ops() -> Dictionary:
	## slice_with_ops = slice ops*
	var node: Dictionary = _parse_slice()
	var elem: Dictionary = element_node(node)

	# Parse operators: * / ( ? ! @ : ..
	while _pos < _code.length():
		var c: String = _peek()
		if c == "*":
			_advance()
			var amount: Dictionary = _parse_slice()
			elem["options_"]["ops"].append({"type_": "stretch", "arguments_": {"amount": amount, "type": "fast"}})
		elif c == "/":
			_advance()
			var amount: Dictionary = _parse_slice()
			elem["options_"]["ops"].append({"type_": "stretch", "arguments_": {"amount": amount, "type": "slow"}})
		elif c == "(":
			_advance()
			_skip_ws()
			var pulse: Dictionary = _parse_slice_with_ops()
			_skip_ws()
			_expect(",")
			_skip_ws()
			var step: Dictionary = _parse_slice_with_ops()
			_skip_ws()
			var rotation: Variant = null
			if _pos < _code.length() and _peek() == ",":
				_advance()
				_skip_ws()
				rotation = _parse_slice_with_ops()
				_skip_ws()
			_expect(")")
			elem["options_"]["ops"].append({"type_": "bjorklund", "arguments_": {"pulse": pulse, "step": step, "rotation": rotation}})
		elif c == "?":
			_advance()
			var amount: Variant = _try_parse_number()
			elem["options_"]["ops"].append({"type_": "degradeBy", "arguments_": {"amount": amount, "seed": _seed}})
			_seed += 1
		elif c == "!":
			_advance()
			var amount: Variant = _try_parse_number()
			if amount == null:
				amount = 2
			var reps: int = int(amount)
			elem["options_"]["reps"] = reps
			# Remove existing replicate ops and add fresh one
			elem["options_"]["ops"] = elem["options_"]["ops"].filter(func(op: Dictionary) -> bool: return op["type_"] != "replicate")
			elem["options_"]["ops"].append({"type_": "replicate", "arguments_": {"amount": reps}})
			elem["options_"]["weight"] = reps
		elif c == "@":
			_advance()
			var w: Variant = _try_parse_number()
			if w == null:
				w = 2
			elem["options_"]["weight"] = (elem["options_"].get("weight") if elem["options_"].get("weight") != null else 1) + int(w) - 1
		elif c == ":":
			_advance()
			var tail_elem: Dictionary = _parse_slice()
			elem["options_"]["ops"].append({"type_": "tail", "arguments_": {"element": tail_elem}})
		elif c == "." and _pos + 1 < _code.length() and _code[_pos + 1] == ".":
			_advance()  # skip first .
			_advance()  # skip second .
			var range_elem: Dictionary = _parse_slice()
			elem["options_"]["ops"].append({"type_": "range", "arguments_": {"element": range_elem}})
		else:
			break

	return elem


func _parse_slice() -> Dictionary:
	## slice = step | sub_cycle | polymeter | slow_sequence
	_skip_ws()
	if _pos >= _code.length():
		return atom_node("~", _pos, _pos)

	var c: String = _peek()

	if c == "[":
		return _parse_sub_cycle()
	if c == "{":
		return _parse_polymeter()
	if c == "<":
		return _parse_slow_sequence()

	return _parse_step()


func _parse_step() -> Dictionary:
	## step = [a-zA-Z0-9~\-#.^_]+
	var start: int = _pos
	var chars: String = ""

	while _pos < _code.length():
		var ch: String = _code[_pos]
		# Step characters: letters, digits, ~, -, #, ., ^, _
		if _is_step_char(ch):
			chars += ch
			_pos += 1
		else:
			break

	if chars.is_empty():
		_error("expected a step (note name, number, or ~) but got '%s'" % (_code[_pos] if _pos < _code.length() else "EOF"))
		# CRITICAL: advance past the bad character to prevent infinite loops
		if _pos < _code.length():
			_pos += 1
		return atom_node("~", start, _pos)

	# Don't allow "." or "_" as standalone atoms (they're separators)
	if chars == "." or chars == "_":
		_pos = start  # rewind
		return atom_node("~", start, start)

	return atom_node(chars, start, _pos)


func _parse_sub_cycle() -> Dictionary:
	## sub_cycle = "[" stack_or_choose "]"
	_expect("[")
	_skip_ws()
	var inner: Dictionary = _parse_stack_or_choose()
	_skip_ws()
	_expect("]")
	return inner


func _parse_polymeter() -> Dictionary:
	## polymeter = "{" polymeter_stack "}" ("%"slice)?
	_expect("{")
	_skip_ws()
	var inner: Dictionary = _parse_polymeter_stack()
	_skip_ws()
	_expect("}")

	# Optional steps-per-cycle: %n
	if _pos < _code.length() and _peek() == "%":
		_advance()
		var steps_node: Dictionary = _parse_slice()
		inner["arguments_"]["stepsPerCycle"] = steps_node

	return inner


func _parse_polymeter_stack() -> Dictionary:
	## polymeter_stack = sequence ("," sequence)*
	var items: Array = [_parse_sequence()]
	_skip_ws()
	while _pos < _code.length() and _peek() == ",":
		_advance()
		_skip_ws()
		items.append(_parse_sequence())
		_skip_ws()
	return pattern_node(items, "polymeter")


func _parse_slow_sequence() -> Dictionary:
	## slow_sequence = "<" polymeter_stack ">"
	_expect("<")
	_skip_ws()
	var inner: Dictionary = _parse_polymeter_stack()
	_skip_ws()
	_expect(">")
	inner["arguments_"]["alignment"] = "polymeter_slowcat"
	return inner


# -- Helpers -------------------------------------------------------------------

func _is_step_char(ch: String) -> bool:
	## Characters allowed in a step atom.
	if ch.length() != 1:
		return false
	var o: int = ch.unicode_at(0)
	# a-z, A-Z
	if (o >= 65 and o <= 90) or (o >= 97 and o <= 122):
		return true
	# 0-9
	if o >= 48 and o <= 57:
		return true
	# Special: ~ - # . ^ _
	if ch in ["~", "-", "#", ".", "^", "_"]:
		return true
	return false


func _try_parse_number() -> Variant:
	## Try to parse a number at current position. Returns null if not a number.
	var start: int = _pos
	var has_digits: bool = false
	var has_dot: bool = false
	var has_minus: bool = false

	if _pos < _code.length() and _code[_pos] == "-":
		has_minus = true
		_pos += 1

	while _pos < _code.length() and _code[_pos].is_valid_int():
		has_digits = true
		_pos += 1

	if _pos < _code.length() and _code[_pos] == ".":
		# Check it's a decimal point, not a separator
		if _pos + 1 < _code.length() and _code[_pos + 1].is_valid_int():
			has_dot = true
			_pos += 1
			while _pos < _code.length() and _code[_pos].is_valid_int():
				_pos += 1

	if not has_digits:
		_pos = start  # rewind
		return null

	var num_str: String = _code.substr(start, _pos - start)
	if has_dot:
		return float(num_str)
	return int(num_str)


func _peek() -> String:
	if _pos >= _code.length():
		return ""
	return _code[_pos]


func _advance() -> void:
	_pos += 1


func _expect(ch: String) -> void:
	if _pos < _code.length() and _code[_pos] == ch:
		_pos += 1
	else:
		_error("expected '%s'" % ch)


func _skip_ws() -> void:
	while _pos < _code.length() and _code[_pos] in [" ", "\t", "\n", "\r"]:
		_pos += 1


func _error(msg: String) -> void:
	_errors.append("at position %d: %s" % [_pos, msg])
