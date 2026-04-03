class_name StrudelMini extends RefCounted

## Converts mini-notation strings into StrudelPatterns.
## Ported from Strudel v1.2.0 mini.mjs.
##
## Usage:
##   var pat = StrudelMini.mini("bd sd [hh hh] cp")
##   var haps = pat.query_arc(0, 1)

static var _parser: StrudelMiniParser = StrudelMiniParser.new()

# -- Public API ----------------------------------------------------------------

static func mini(input: String) -> StrudelPattern:
	## Parse a mini-notation string and return a Pattern.
	## Input should NOT include surrounding quotes.
	var ast: Dictionary = _parser.parse(input)
	return _patternify_ast(ast, input, 0)


static func get_leaf_locations(input: String, offset: int = 0) -> Array:
	## Return source locations of all leaf atoms in the mini-notation.
	## Each entry is [from_offset, to_offset].
	var ast: Dictionary = _parser.parse(input)
	var leaves: Array = []
	_collect_leaves(ast, input, offset, leaves)
	return leaves


# -- AST to Pattern Conversion -------------------------------------------------

static func _patternify_ast(ast: Dictionary, code: String, offset: int) -> StrudelPattern:
	## Recursively convert an AST node into a StrudelPattern.
	var type: String = ast.get("type_", "")

	match type:
		"atom":
			return _patternify_atom(ast, code, offset)
		"element":
			return _patternify_element(ast, code, offset)
		"pattern":
			return _patternify_pattern(ast, code, offset)
		_:
			push_warning("StrudelMini: unknown AST node type '%s'" % type)
			return Strudel.silence()


static func _patternify_atom(ast: Dictionary, code: String, offset: int) -> StrudelPattern:
	var source: String = ast.get("source_", "")

	# Silence
	if source == "~" or source == "-":
		return Strudel.silence()

	# Number or string value
	var value: Variant
	if source.is_valid_float():
		value = float(source) if "." in source else int(source)
	else:
		value = source

	# Attach source location for highlighting
	var loc: Dictionary = ast.get("location_", {})
	var from_offset: int = loc.get("start", {}).get("offset", 0) + offset
	var to_offset: int = loc.get("end", {}).get("offset", 0) + offset

	return Strudel.pure(value).with_loc(from_offset, to_offset)


static func _patternify_element(ast: Dictionary, code: String, offset: int) -> StrudelPattern:
	## element = source + options (operators)
	var source_ast: Dictionary = ast.get("source_", {})
	var pat: StrudelPattern = _patternify_ast(source_ast, code, offset)
	var options: Dictionary = ast.get("options_", {})
	return _apply_options(pat, options, code, offset)


static func _patternify_pattern(ast: Dictionary, code: String, offset: int) -> StrudelPattern:
	## pattern = list of children with an alignment strategy
	var sources: Array = ast.get("source_", [])
	var args: Dictionary = ast.get("arguments_", {})
	var alignment: String = args.get("alignment", "fastcat")

	# Recursively convert children
	# Note: _patternify_element already applies options, so we don't re-apply here
	var children: Array = []
	for i in range(sources.size()):
		var child_ast: Dictionary = sources[i]
		var child_pat: StrudelPattern = _patternify_ast(child_ast, code, offset)
		children.append(child_pat)

	if children.is_empty():
		return Strudel.silence()

	# Dispatch based on alignment
	match alignment:
		"stack":
			return Strudel.stack(children)
		"polymeter_slowcat":
			# <a b c> = slowcat of children, each slowed by its weight
			var slowed: Array = []
			for i in range(children.size()):
				var child: StrudelPattern = children[i]
				var weight: Variant = _get_weight(sources[i])
				if weight != null and weight > 1:
					slowed.append(child._slow(weight))
				else:
					slowed.append(child)
			return Strudel.stack(slowed)
		"polymeter":
			# {a b, c d e} = polymeter
			if children.size() == 1:
				return children[0]
			var steps_per_cycle: Variant = null
			if args.has("stepsPerCycle"):
				steps_per_cycle = _patternify_ast(args["stepsPerCycle"], code, offset)
			# For now: simple polymeter — each child plays at its own rate
			# Full polymeter aligns to the first child's length
			if steps_per_cycle == null and not children.is_empty():
				# Default: steps from first child
				return Strudel.stack(children)
			return Strudel.stack(children)
		"rand":
			# a | b | c = random pick each cycle (seeded)
			var rand_seed: int = args.get("seed", 0)
			return _choose_with_seed(children, rand_seed)
		"feet":
			# a . b . c = foot separator (fastcat)
			return Strudel.fastcat(children)
		_:
			# Default: fastcat (sequence)
			# Check for weighted children
			var has_weights: bool = false
			for i in range(sources.size()):
				if sources[i].get("options_", {}).get("weight") != null:
					has_weights = true
					break

			if has_weights:
				# Build timeCat entries: [weight, pattern]
				var entries: Array = []
				for i in range(sources.size()):
					var weight: Variant = _get_weight(sources[i])
					if weight == null:
						weight = 1
					entries.append([weight, children[i]])
				return Strudel.time_cat(entries)
			else:
				return Strudel.sequence(children)


# -- Operator Application ------------------------------------------------------

static func _apply_options(pat: StrudelPattern, options: Dictionary, code: String, offset: int) -> StrudelPattern:
	## Apply operators from the options dictionary to a pattern.
	var ops: Array = options.get("ops", [])

	for op in ops:
		var op_type: String = op.get("type_", "")
		var op_args: Dictionary = op.get("arguments_", {})

		match op_type:
			"stretch":
				var amount_ast: Variant = op_args.get("amount")
				var stretch_type: String = op_args.get("type", "fast")
				if amount_ast is Dictionary:
					var amount_pat: StrudelPattern = _patternify_ast(amount_ast, code, offset)
					var amount_val: Variant = amount_pat.first_cycle_values
					if not amount_val.is_empty():
						var factor: Variant = amount_val[0]
						if stretch_type == "fast":
							pat = pat._fast(factor)
						else:
							pat = pat._slow(factor)
				elif amount_ast != null:
					if stretch_type == "fast":
						pat = pat._fast(amount_ast)
					else:
						pat = pat._slow(amount_ast)

			"replicate":
				var amount: int = int(op_args.get("amount", 2))
				# Replicate: repeat the pattern `amount` times within the same duration
				pat = pat._fast(amount)

			"bjorklund":
				var pulse_ast: Variant = op_args.get("pulse")
				var step_ast: Variant = op_args.get("step")
				var rotation_ast: Variant = op_args.get("rotation")
				# Resolve to values
				var pulses: int = _resolve_int(pulse_ast, code, offset)
				var steps: int = _resolve_int(step_ast, code, offset)
				if rotation_ast != null:
					var rotation: int = _resolve_int(rotation_ast, code, offset)
					pat = pat._euclid_rot(pulses, steps, rotation)
				else:
					pat = pat._euclid(pulses, steps)

			"degradeBy":
				# Randomly drop events with probability `amount` (default 0.5)
				var degrade_amount: float = 0.5
				if op_args.get("amount") != null:
					degrade_amount = float(op_args["amount"])
				var degrade_seed: int = int(op_args.get("seed", 0))
				pat = pat._degrade_by(degrade_amount, degrade_seed)

			"tail":
				# Colon operator: bd:2 sets n=2 on the value
				var element_ast: Variant = op_args.get("element")
				if element_ast is Dictionary:
					var tail_pat: StrudelPattern = _patternify_ast(element_ast, code, offset)
					# Apply as a value combiner (makes array [head, tail])
					pat = pat.fmap(func(a: Variant) -> Callable:
						return func(b: Variant) -> Variant:
							if a is Array:
								return a + [b]
							return [a, b]).app_left(tail_pat)

			"range":
				# ".." range operator — TODO
				pass

	return pat


# -- Helpers -------------------------------------------------------------------

static func _get_weight(ast: Dictionary) -> Variant:
	## Extract weight from an element's options.
	if ast.get("type_") == "element":
		return ast.get("options_", {}).get("weight")
	return null


static func _resolve_int(ast: Variant, code: String, offset: int) -> int:
	## Resolve an AST node to an integer value.
	if ast == null:
		return 0
	if ast is Dictionary:
		var pat: StrudelPattern = _patternify_ast(ast, code, offset)
		var vals: Array = pat.first_cycle_values
		if not vals.is_empty():
			return int(vals[0])
	if ast is int:
		return ast
	if ast is float:
		return int(ast)
	return 0


static func _choose_with_seed(children: Array, seed: int) -> StrudelPattern:
	## Randomly choose one pattern per cycle, using a deterministic seed.
	var n: int = children.size()
	if n == 0:
		return Strudel.silence()
	if n == 1:
		return children[0]
	var q := func(state: StrudelState) -> Array:
		var cycle: int = int(state.span.begin.sam().to_float())
		var hash_val: float = fmod(absf(sin(float(cycle + seed) * 12345.6789) * 43758.5453), 1.0)
		var idx: int = int(hash_val * n) % n
		return children[idx].query.call(state)
	return StrudelPattern.new(q).split_queries()


static func _collect_leaves(ast: Dictionary, code: String, offset: int, leaves: Array) -> void:
	## Recursively collect leaf (atom) locations.
	var type: String = ast.get("type_", "")

	if type == "atom":
		var loc: Dictionary = ast.get("location_", {})
		var from_col: int = loc.get("start", {}).get("offset", 0) + offset
		var to_col: int = loc.get("end", {}).get("offset", 0) + offset
		leaves.append([from_col, to_col])
	elif type == "element":
		var source: Variant = ast.get("source_")
		if source is Dictionary:
			_collect_leaves(source, code, offset, leaves)
	elif type == "pattern":
		var sources: Array = ast.get("source_", [])
		for child in sources:
			if child is Dictionary:
				_collect_leaves(child, code, offset, leaves)
