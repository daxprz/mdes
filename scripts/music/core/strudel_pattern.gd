class_name StrudelPattern extends RefCounted

## The core pattern type. A Pattern is a function from State -> Array[Hap].
## All musical structures are Patterns. All transformations return new Patterns.
##
## Ported from Strudel v1.2.0 pattern.mjs.
## This file covers Stories 1.4 (foundation), 1.5 (applicative/monadic),
## and 1.6 (combinators).

var query: Callable  ## func(state: StrudelState) -> Array[StrudelHap]
var _steps: Variant  ## StrudelFraction or null — steps per cycle


func _init(p_query: Callable, p_steps: Variant = null) -> void:
	query = p_query
	if p_steps != null and not (p_steps is StrudelFraction):
		_steps = StrudelFraction.create(p_steps)
	else:
		_steps = p_steps


func set_steps(steps: Variant) -> StrudelPattern:
	if steps != null and not (steps is StrudelFraction):
		_steps = StrudelFraction.create(steps)
	else:
		_steps = steps
	return self


# ==============================================================================
# Query
# ==============================================================================

func query_arc(begin_val: Variant, end_val: Variant, controls: Dictionary = {}) -> Array:
	## Query haps in the given time range. Returns Array[StrudelHap].
	var b: StrudelFraction = StrudelFraction.create(begin_val)
	var e: StrudelFraction = StrudelFraction.create(end_val)
	var state := StrudelState.new(StrudelTimeSpan.new(b, e), controls)
	return query.call(state)


func first_cycle(with_context: bool = false) -> Array:
	## Query the first cycle [0, 1). Returns Array[StrudelHap].
	var pat: StrudelPattern = self if with_context else strip_context()
	return pat.query.call(StrudelState.new(
		StrudelTimeSpan.new(StrudelFraction.new(0, 1), StrudelFraction.new(1, 1))))


var first_cycle_values: Array:
	get:
		return first_cycle().map(func(hap: StrudelHap): return hap.value)


# ==============================================================================
# Functor: withValue / fmap
# ==============================================================================

func with_value(func_val: Callable) -> StrudelPattern:
	var pat: StrudelPattern = self
	var result := StrudelPattern.new(
		func(state: StrudelState) -> Array:
			return pat.query.call(state).map(func(hap: StrudelHap): return hap.with_value(func_val)))
	result._steps = _steps
	return result

func fmap(func_val: Callable) -> StrudelPattern:
	return with_value(func_val)


# ==============================================================================
# Query manipulation
# ==============================================================================

func split_queries() -> StrudelPattern:
	## Split queries at cycle boundaries.
	var pat: StrudelPattern = self
	var q := func(state: StrudelState) -> Array:
		var result: Array = []
		for subspan in state.span.spanCycles:
			result.append_array(pat.query.call(state.set_span(subspan)))
		return result
	return StrudelPattern.new(q)


func with_query_span(func_span: Callable) -> StrudelPattern:
	var pat: StrudelPattern = self
	return StrudelPattern.new(
		func(state: StrudelState) -> Array:
			return pat.query.call(state.with_span(func_span)))


func with_query_time(func_time: Callable) -> StrudelPattern:
	var pat: StrudelPattern = self
	return StrudelPattern.new(
		func(state: StrudelState) -> Array:
			return pat.query.call(state.with_span(
				func(span: StrudelTimeSpan) -> StrudelTimeSpan:
					return span.with_time(func_time))))


func with_hap_span(func_span: Callable) -> StrudelPattern:
	var pat: StrudelPattern = self
	return StrudelPattern.new(
		func(state: StrudelState) -> Array:
			return pat.query.call(state).map(
				func(hap: StrudelHap) -> StrudelHap:
					return hap.with_span(func_span)))


func with_hap_time(func_time: Callable) -> StrudelPattern:
	return with_hap_span(func(span: StrudelTimeSpan) -> StrudelTimeSpan:
		return span.with_time(func_time))


func with_haps(func_haps: Callable) -> StrudelPattern:
	var pat: StrudelPattern = self
	var result := StrudelPattern.new(
		func(state: StrudelState) -> Array:
			return func_haps.call(pat.query.call(state), state))
	result._steps = _steps
	return result


func with_hap(func_hap: Callable) -> StrudelPattern:
	return with_haps(func(haps: Array, _state: StrudelState) -> Array:
		return haps.map(func_hap))


# ==============================================================================
# Context
# ==============================================================================

func set_context(ctx: Dictionary) -> StrudelPattern:
	return with_hap(func(hap: StrudelHap) -> StrudelHap: return hap.set_context(ctx))


func strip_context() -> StrudelPattern:
	return with_hap(func(hap: StrudelHap) -> StrudelHap: return hap.set_context({}))


func with_loc(start: int, end: int) -> StrudelPattern:
	var location: Dictionary = {"start": start, "end": end}
	return with_hap(func(hap: StrudelHap) -> StrudelHap:
		var locs: Array = hap.context.get("locations", []) + [location]
		var new_ctx: Dictionary = hap.context.duplicate()
		new_ctx["locations"] = locs
		return hap.set_context(new_ctx))


# ==============================================================================
# Filters
# ==============================================================================

func filter_haps(test: Callable) -> StrudelPattern:
	var pat: StrudelPattern = self
	return StrudelPattern.new(
		func(state: StrudelState) -> Array:
			return pat.query.call(state).filter(test))


func filter_values(test: Callable) -> StrudelPattern:
	return StrudelPattern.new(
		func(state: StrudelState) -> Array:
			return query.call(state).filter(
				func(hap: StrudelHap) -> bool: return test.call(hap.value))).set_steps(_steps)


func remove_undefineds() -> StrudelPattern:
	return filter_values(func(val: Variant) -> bool: return val != null)


func onsets_only() -> StrudelPattern:
	return filter_haps(func(hap: StrudelHap) -> bool: return hap.has_onset())


func discrete_only() -> StrudelPattern:
	return filter_haps(func(hap: StrudelHap) -> bool: return hap.whole != null)


func sort_haps_by_part() -> StrudelPattern:
	return with_haps(func(haps: Array, _state: StrudelState) -> Array:
		var sorted: Array = haps.duplicate()
		sorted.sort_custom(func(a: StrudelHap, b: StrudelHap) -> bool:
			var cmp: int = a.part.begin.compare(b.part.begin)
			if cmp != 0: return cmp < 0
			cmp = a.part.end.compare(b.part.end)
			if cmp != 0: return cmp < 0
			if a.whole != null and b.whole != null:
				cmp = a.whole.begin.compare(b.whole.begin)
				if cmp != 0: return cmp < 0
				return a.whole.end.compare(b.whole.end) < 0
			return false)
		return sorted)


# ==============================================================================
# Applicative: appWhole, appBoth, appLeft, appRight
# ==============================================================================

func app_whole(whole_func: Callable, pat_val: StrudelPattern) -> StrudelPattern:
	var pat_func: StrudelPattern = self
	var q := func(state: StrudelState) -> Array:
		var hap_funcs: Array = pat_func.query.call(state)
		var hap_vals: Array = pat_val.query.call(state)
		var result: Array = []
		for hap_func in hap_funcs:
			for hap_val in hap_vals:
				var s: Variant = hap_func.part.intersection(hap_val.part)
				if s == null:
					continue
				var w: Variant = whole_func.call(hap_func.whole, hap_val.whole)
				var v: Variant = hap_func.value.call(hap_val.value)
				var c: Dictionary = hap_val.combine_context(hap_func)
				result.append(StrudelHap.new(w, s, v, c))
		return result
	return StrudelPattern.new(q)


func app_both(pat_val: StrudelPattern) -> StrudelPattern:
	## Tidal's <*>: wholes are intersection of func and val wholes.
	var wf := func(span_a: Variant, span_b: Variant) -> Variant:
		if span_a == null or span_b == null:
			return null
		return span_a.intersection_e(span_b)
	return app_whole(wf, pat_val)


func app_left(pat_val: StrudelPattern) -> StrudelPattern:
	## Structure from the left/inner pattern (self).
	var pat_func: StrudelPattern = self
	var q := func(state: StrudelState) -> Array:
		var haps: Array = []
		for hap_func in pat_func.query.call(state):
			var hap_vals: Array = pat_val.query.call(state.set_span(hap_func.whole_or_part()))
			for hap_val in hap_vals:
				var new_part: Variant = hap_func.part.intersection(hap_val.part)
				if new_part != null:
					var v: Variant = hap_func.value.call(hap_val.value)
					var c: Dictionary = hap_val.combine_context(hap_func)
					haps.append(StrudelHap.new(hap_func.whole, new_part, v, c))
		return haps
	var result := StrudelPattern.new(q)
	result._steps = _steps
	return result


func app_right(pat_val: StrudelPattern) -> StrudelPattern:
	## Structure from the right/outer pattern (pat_val).
	var pat_func: StrudelPattern = self
	var q := func(state: StrudelState) -> Array:
		var haps: Array = []
		for hap_val in pat_val.query.call(state):
			var hap_funcs: Array = pat_func.query.call(state.set_span(hap_val.whole_or_part()))
			for hap_func in hap_funcs:
				var new_part: Variant = hap_func.part.intersection(hap_val.part)
				if new_part != null:
					var v: Variant = hap_func.value.call(hap_val.value)
					var c: Dictionary = hap_val.combine_context(hap_func)
					haps.append(StrudelHap.new(hap_val.whole, new_part, v, c))
		return haps
	var result := StrudelPattern.new(q)
	result._steps = pat_val._steps
	return result


# ==============================================================================
# Monadic: bind, join, outerBind, outerJoin, innerBind, innerJoin, squeezeJoin
# ==============================================================================

func bind_whole(choose_whole: Callable, func_bind: Callable) -> StrudelPattern:
	var pat_val: StrudelPattern = self
	var q := func(state: StrudelState) -> Array:
		var result: Array = []
		for a in pat_val.query.call(state):
			var inner_pat: StrudelPattern = func_bind.call(a.value)
			for b in inner_pat.query.call(state.set_span(a.part)):
				var w: Variant = choose_whole.call(a.whole, b.whole)
				var c: Dictionary = a.combine_context(b)
				var locs_a: Array = a.context.get("locations", [])
				var locs_b: Array = b.context.get("locations", [])
				c["locations"] = locs_a + locs_b
				result.append(StrudelHap.new(w, b.part, b.value, c))
		return result
	return StrudelPattern.new(q)


func bind(func_bind: Callable) -> StrudelPattern:
	var wf := func(a: Variant, b: Variant) -> Variant:
		if a == null or b == null: return null
		return a.intersection_e(b)
	return bind_whole(wf, func_bind)


func join() -> StrudelPattern:
	## Flatten Pattern<Pattern<T>> -> Pattern<T>. Wholes = intersection.
	return bind(func(val: Variant) -> StrudelPattern: return val)


func outer_bind(func_bind: Callable) -> StrudelPattern:
	return bind_whole(func(a: Variant, _b: Variant) -> Variant: return a, func_bind).set_steps(_steps)

func outer_join() -> StrudelPattern:
	return outer_bind(func(val: Variant) -> StrudelPattern: return val)

func inner_bind(func_bind: Callable) -> StrudelPattern:
	return bind_whole(func(_a: Variant, b: Variant) -> Variant: return b, func_bind)

func inner_join() -> StrudelPattern:
	return inner_bind(func(val: Variant) -> StrudelPattern: return val)


func squeeze_join() -> StrudelPattern:
	var pat_of_pats: StrudelPattern = self
	var q := func(state: StrudelState) -> Array:
		var haps: Array = pat_of_pats.discrete_only().query.call(state)
		var result: Array = []
		for outer_hap in haps:
			var inner_pat: StrudelPattern = outer_hap.value._focus_span(outer_hap.whole_or_part())
			var inner_haps: Array = inner_pat.query.call(state.set_span(outer_hap.part))
			for inner_hap in inner_haps:
				var w: Variant = null
				if inner_hap.whole != null and outer_hap.whole != null:
					w = inner_hap.whole.intersection(outer_hap.whole)
					if w == null:
						continue
				var p: Variant = inner_hap.part.intersection(outer_hap.part)
				if p == null:
					continue
				var c: Dictionary = inner_hap.combine_context(outer_hap)
				result.append(StrudelHap.new(w, p, inner_hap.value, c))
		return result
	return StrudelPattern.new(q)


func squeeze_bind(func_bind: Callable) -> StrudelPattern:
	return fmap(func_bind).squeeze_join()


# ==============================================================================
# Combinators: fast, slow, early, late, every, rev, stack, sequence, cat
# ==============================================================================

func _fast(factor_val: Variant) -> StrudelPattern:
	## Speed up by a plain (non-pattern) factor.
	var factor: StrudelFraction = StrudelFraction.create(factor_val)
	if factor.eq(StrudelFraction.new(0, 1)):
		return Strudel.silence()
	var fast_query: StrudelPattern = with_query_time(
		func(t: StrudelFraction) -> StrudelFraction: return t.mul(factor))
	return fast_query.with_hap_time(
		func(t: StrudelFraction) -> StrudelFraction: return t.div(factor)).set_steps(_steps)


func _slow(factor_val: Variant) -> StrudelPattern:
	var factor: StrudelFraction = StrudelFraction.create(factor_val)
	if factor.eq(StrudelFraction.new(0, 1)):
		return Strudel.silence()
	return _fast(StrudelFraction.new(1, 1).div(factor))


func _early(offset_val: Variant) -> StrudelPattern:
	## Shift earlier in time by a plain offset.
	var offset: StrudelFraction = StrudelFraction.create(offset_val)
	return with_query_time(
		func(t: StrudelFraction) -> StrudelFraction: return t.add(offset)
	).with_hap_time(
		func(t: StrudelFraction) -> StrudelFraction: return t.sub(offset)
	).set_steps(_steps)


func _late(offset_val: Variant) -> StrudelPattern:
	var offset: StrudelFraction = StrudelFraction.create(offset_val)
	return _early(StrudelFraction.new(0, 1).sub(offset))


func _compress(b_val: Variant, e_val: Variant) -> StrudelPattern:
	var b: StrudelFraction = StrudelFraction.create(b_val)
	var e: StrudelFraction = StrudelFraction.create(e_val)
	if b.gt(e) or b.gt(StrudelFraction.new(1, 1)) or e.gt(StrudelFraction.new(1, 1)) \
			or b.lt(StrudelFraction.new(0, 1)) or e.lt(StrudelFraction.new(0, 1)):
		return Strudel.silence()
	return _fast_gap(StrudelFraction.new(1, 1).div(e.sub(b)))._late(b)


func _fast_gap(factor_val: Variant) -> StrudelPattern:
	var factor: StrudelFraction = StrudelFraction.create(factor_val)
	var pat: StrudelPattern = self
	var one := StrudelFraction.new(1, 1)

	var qf := func(span: StrudelTimeSpan) -> Variant:
		var cycle: StrudelFraction = span.begin.sam()
		var bpos: StrudelFraction = span.begin.sub(cycle).mul(factor).min_frac(one)
		var epos: StrudelFraction = span.end.sub(cycle).mul(factor).min_frac(one)
		if bpos.gte(one):
			return null
		return StrudelTimeSpan.new(cycle.add(bpos), cycle.add(epos))

	var ef := func(hap: StrudelHap) -> StrudelHap:
		var b: StrudelFraction = hap.part.begin
		var e: StrudelFraction = hap.part.end
		var cycle: StrudelFraction = b.sam()
		var begin_pos: StrudelFraction = b.sub(cycle).div(factor).min_frac(one)
		var end_pos: StrudelFraction = e.sub(cycle).div(factor).min_frac(one)
		var new_part := StrudelTimeSpan.new(cycle.add(begin_pos), cycle.add(end_pos))
		var new_whole: Variant = null
		if hap.whole != null:
			new_whole = StrudelTimeSpan.new(
				new_part.begin.sub(b.sub(hap.whole.begin).div(factor)),
				new_part.end.add(hap.whole.end.sub(e).div(factor)))
		return StrudelHap.new(new_whole, new_part, hap.value, hap.context)

	# with_query_span_maybe — skip if qf returns null
	var result := StrudelPattern.new(func(state: StrudelState) -> Array:
		var new_span: Variant = qf.call(state.span)
		if new_span == null:
			return []
		return pat.query.call(state.set_span(new_span)))
	return result.with_hap(ef).split_queries()


func _focus(b_val: Variant, e_val: Variant) -> StrudelPattern:
	var b: StrudelFraction = StrudelFraction.create(b_val)
	var e: StrudelFraction = StrudelFraction.create(e_val)
	return _early(b.sam())._fast(StrudelFraction.new(1, 1).div(e.sub(b)))._late(b)


func _focus_span(span: StrudelTimeSpan) -> StrudelPattern:
	return _focus(span.begin, span.end)


func _rev() -> StrudelPattern:
	## Reverse a cycle.
	var pat: StrudelPattern = self
	var q := func(state: StrudelState) -> Array:
		var cycle: StrudelFraction = state.span.begin.sam()
		var next: StrudelFraction = state.span.begin.next_sam()
		var reflect := func(t: StrudelFraction) -> StrudelFraction:
			return cycle.add(next.sub(t))
		var reflected_span := StrudelTimeSpan.new(
			reflect.call(state.span.end), reflect.call(state.span.begin))
		var haps: Array = pat.query.call(state.set_span(reflected_span))
		return haps.map(func(hap: StrudelHap) -> StrudelHap:
			return hap.with_span(func(s: StrudelTimeSpan) -> StrudelTimeSpan:
				return StrudelTimeSpan.new(reflect.call(s.end), reflect.call(s.begin))))
	return StrudelPattern.new(q).split_queries()


# ==============================================================================
# Multi-pattern: layer, superimpose
# ==============================================================================

func layer(funcs: Array) -> StrudelPattern:
	var pats: Array = funcs.map(func(f: Callable) -> StrudelPattern: return f.call(self))
	return Strudel.stack(pats)


func superimpose(funcs: Array) -> StrudelPattern:
	var pats: Array = funcs.map(func(f: Callable) -> StrudelPattern: return f.call(self))
	return Strudel.stack([self] + pats)


# ==============================================================================
# Euclidean rhythms
# ==============================================================================

func _euclid(pulses: int, steps: int) -> StrudelPattern:
	## Apply a Euclidean rhythm structure.
	var bin_pat: Array = _bjork(pulses, steps)
	var bool_pats: Array = []
	for b in bin_pat:
		bool_pats.append(Strudel.pure(b == 1))
	var struct_pat: StrudelPattern = Strudel.sequence(bool_pats)
	# keepif.out: keep self's values where struct is true
	return _struct(struct_pat)


func _euclid_rot(pulses: int, steps: int, rotation: int) -> StrudelPattern:
	var bin_pat: Array = _bjork(pulses, steps)
	# Rotate
	if rotation != 0:
		var r: int = ((-rotation) % bin_pat.size() + bin_pat.size()) % bin_pat.size()
		bin_pat = bin_pat.slice(r) + bin_pat.slice(0, r)
	var bool_pats: Array = []
	for b in bin_pat:
		bool_pats.append(Strudel.pure(b == 1))
	return _struct(Strudel.sequence(bool_pats))


func _struct(struct_pat: StrudelPattern) -> StrudelPattern:
	## Keep self's values only where struct_pat is truthy. (keepif.out)
	var pat: StrudelPattern = self
	var q := func(state: StrudelState) -> Array:
		var result: Array = []
		for hap_struct in struct_pat.query.call(state):
			if not hap_struct.value:
				continue
			var hap_vals: Array = pat.query.call(state.set_span(hap_struct.whole_or_part()))
			for hap_val in hap_vals:
				var new_part: Variant = hap_struct.part.intersection(hap_val.part)
				if new_part != null:
					result.append(StrudelHap.new(hap_struct.whole, new_part, hap_val.value, hap_val.combine_context(hap_struct)))
		return result
	return StrudelPattern.new(q)


static func _bjork(pulses: int, steps: int) -> Array:
	## Bjorklund algorithm: distribute `pulses` onsets across `steps` slots.
	if pulses <= 0:
		return Array().duplicate()
	if pulses >= steps:
		var r: Array = []
		r.resize(steps)
		r.fill(1)
		return r
	var ons: Array = []
	for _i in range(pulses):
		ons.append([1])
	var offs: Array = []
	for _i in range(steps - pulses):
		offs.append([0])
	return _bjork_rec(ons, offs)


static func _bjork_rec(ons: Array, offs: Array) -> Array:
	## Ported from Strudel v1.2.0 euclid.mjs _bjork/left/right.
	if ons.is_empty() or offs.is_empty() or mini(ons.size(), offs.size()) <= 1:
		var result: Array = []
		for a in ons:
			result.append_array(a)
		for a in offs:
			result.append_array(a)
		return result
	if ons.size() > offs.size():
		# Left: pair first offs.size() ons with offs, remainder stays as ons
		var new_ons: Array = []
		for i in range(offs.size()):
			new_ons.append(ons[i] + offs[i])
		var remaining: Array = ons.slice(offs.size())
		return _bjork_rec(new_ons, remaining)
	else:
		# Right: pair first ons.size() offs with ons, remainder stays as offs
		var new_ons: Array = []
		for i in range(ons.size()):
			new_ons.append(ons[i] + offs[i])
		var remaining: Array = offs.slice(ons.size())
		return _bjork_rec(new_ons, remaining)


# ==============================================================================
# Composers: add, sub, mul, div, set, keep, keepif
# Each has a default "in" behavior (structure from left/self).
# ==============================================================================

## Helper: merge two values using a function. Handles Dictionary union.
static func _numeral(v: Variant) -> Variant:
	## Convert a value to a number for arithmetic, like Strudel's parseNumeral.
	## Note names (c4, eb3) → MIDI number. Numbers pass through.
	if v is float or v is int:
		return v
	if v is String:
		if v.is_valid_float():
			return float(v)
		# Try note name → MIDI
		var midi: int = StrudelOscillator._note_to_midi(v)
		if midi >= 0:
			return midi
	return v  # Can't convert — return as-is


static func _compose_op(a: Variant, b: Variant, op: Callable) -> Variant:
	if a is Dictionary or b is Dictionary:
		if not (a is Dictionary):
			a = {"value": a}
		if not (b is Dictionary):
			b = {"value": b}
		var result: Dictionary = a.duplicate()
		result.merge(b)
		for key in b:
			if a.has(key):
				# Convert note names to MIDI numbers before arithmetic
				result[key] = op.call(_numeral(a[key]), _numeral(b[key]))
		return result
	return op.call(_numeral(a), _numeral(b))

# -- add: numerical addition --
func add_in(other: Variant) -> StrudelPattern:
	var other_pat: StrudelPattern = Strudel.reify(other)
	return fmap(func(a: Variant) -> Callable:
		return func(b: Variant) -> Variant:
			return _compose_op(a, b, func(x, y): return x + y)).app_left(other_pat)

func add_out(other: Variant) -> StrudelPattern:
	var other_pat: StrudelPattern = Strudel.reify(other)
	return fmap(func(a: Variant) -> Callable:
		return func(b: Variant) -> Variant:
			return _compose_op(a, b, func(x, y): return x + y)).app_right(other_pat)

func add_both(other: Variant) -> StrudelPattern:
	var other_pat: StrudelPattern = Strudel.reify(other)
	return fmap(func(a: Variant) -> Callable:
		return func(b: Variant) -> Variant:
			return _compose_op(a, b, func(x, y): return x + y)).app_both(other_pat)

func add_squeeze(other: Variant) -> StrudelPattern:
	var pat: StrudelPattern = self
	var other_pat: StrudelPattern = Strudel.reify(other)
	return fmap(func(a: Variant) -> StrudelPattern:
		return other_pat.fmap(func(b: Variant) -> Variant:
			return _compose_op(a, b, func(x, y): return x + y))).squeeze_join()

# -- sub: numerical subtraction --
func sub_in(other: Variant) -> StrudelPattern:
	var other_pat: StrudelPattern = Strudel.reify(other)
	return fmap(func(a: Variant) -> Callable:
		return func(b: Variant) -> Variant:
			return _compose_op(a, b, func(x, y): return x - y)).app_left(other_pat)

# -- mul: numerical multiplication --
func mul_in(other: Variant) -> StrudelPattern:
	var other_pat: StrudelPattern = Strudel.reify(other)
	return fmap(func(a: Variant) -> Callable:
		return func(b: Variant) -> Variant:
			return _compose_op(a, b, func(x, y): return x * y)).app_left(other_pat)

# -- div: numerical division --
func div_in(other: Variant) -> StrudelPattern:
	var other_pat: StrudelPattern = Strudel.reify(other)
	return fmap(func(a: Variant) -> Callable:
		return func(b: Variant) -> Variant:
			return _compose_op(a, b, func(x, y): return float(x) / float(y) if y != 0 else x)).app_left(other_pat)

# -- set: replace values (merge dicts) --
func set_in(other: Variant) -> StrudelPattern:
	var other_pat: StrudelPattern = Strudel.reify(other)
	return fmap(func(a: Variant) -> Callable:
		return func(b: Variant) -> Variant:
			return _compose_op(a, b, func(_x, y): return y)).app_left(other_pat)

func set_out(other: Variant) -> StrudelPattern:
	var other_pat: StrudelPattern = Strudel.reify(other)
	return fmap(func(a: Variant) -> Callable:
		return func(b: Variant) -> Variant:
			return _compose_op(a, b, func(_x, y): return y)).app_right(other_pat)

# -- keep: keep self's values with other's structure --
func keep_in(other: Variant) -> StrudelPattern:
	var other_pat: StrudelPattern = Strudel.reify(other)
	return fmap(func(a: Variant) -> Callable:
		return func(_b: Variant) -> Variant: return a).app_left(other_pat)

func keep_out(other: Variant) -> StrudelPattern:
	var other_pat: StrudelPattern = Strudel.reify(other)
	return fmap(func(a: Variant) -> Callable:
		return func(_b: Variant) -> Variant: return a).app_right(other_pat)

# -- keepif: keep self's values where other is truthy --
func keepif_in(other: Variant) -> StrudelPattern:
	var other_pat: StrudelPattern = Strudel.reify(other)
	return fmap(func(a: Variant) -> Callable:
		return func(b: Variant) -> Variant:
			return a if b else null).app_left(other_pat).remove_undefineds()

func keepif_out(other: Variant) -> StrudelPattern:
	var other_pat: StrudelPattern = Strudel.reify(other)
	return fmap(func(a: Variant) -> Callable:
		return func(b: Variant) -> Variant:
			return a if b else null).app_right(other_pat).remove_undefineds()

# -- Convenience: default to "in" behavior --
func pat_add(other: Variant) -> StrudelPattern:
	return add_in(other)

func pat_sub(other: Variant) -> StrudelPattern:
	return sub_in(other)

func pat_mul(other: Variant) -> StrudelPattern:
	return mul_in(other)

func pat_div(other: Variant) -> StrudelPattern:
	return div_in(other)

func pat_set(other: Variant) -> StrudelPattern:
	return set_in(other)

# -- Binary composers built on keep/keepif --
func mask(other: Variant) -> StrudelPattern:
	## Silence where mask is falsy. Structure from self.
	return keepif_in(other)

func struct_out(other: Variant) -> StrudelPattern:
	## Impose outer pattern's structure on self's values.
	return keepif_out(other)

# ==============================================================================
# Combinators: every, firstOf, lastOf, ply, palindrome, jux, off, inside, outside
# ==============================================================================

func _every(n: int, func_transform: Callable) -> StrudelPattern:
	## Apply func every n cycles, starting from the first.
	var pats: Array = []
	pats.append(func_transform.call(self))
	for _i in range(n - 1):
		pats.append(self)
	return Strudel.slowcat_prime(pats)

func _first_of(n: int, func_transform: Callable) -> StrudelPattern:
	return _every(n, func_transform)

func _last_of(n: int, func_transform: Callable) -> StrudelPattern:
	var pats: Array = []
	for _i in range(n - 1):
		pats.append(self)
	pats.append(func_transform.call(self))
	return Strudel.slowcat_prime(pats)

func _ply(factor: int) -> StrudelPattern:
	## Repeat each event within its timespan.
	return fmap(func(x: Variant) -> StrudelPattern:
		return Strudel.pure(x)._fast(factor)).squeeze_join()

func _palindrome() -> StrudelPattern:
	## Play forward then backward.
	return Strudel.slowcat([self, _rev()])

func _jux(func_transform: Callable) -> StrudelPattern:
	## Apply func to a copy, pan original left and copy right.
	## Since we don't have panning yet, just superimpose.
	return superimpose([func_transform])

func _off(time_offset: Variant, func_transform: Callable) -> StrudelPattern:
	## Superimpose a transformed, time-shifted copy.
	## Strudel applies late BEFORE the transform: stack(pat, func(pat.late(t)))
	return superimpose([func(p: StrudelPattern) -> StrudelPattern:
		return func_transform.call(p._late(time_offset))])

func _inside(factor: Variant, func_transform: Callable) -> StrudelPattern:
	## Apply func inside a cycle: slow, transform, fast.
	return func_transform.call(_slow(factor))._fast(factor)

func _outside(factor: Variant, func_transform: Callable) -> StrudelPattern:
	## Apply func outside a cycle: fast, transform, slow.
	return func_transform.call(_fast(factor))._slow(factor)

func _zoom(s: Variant, e: Variant) -> StrudelPattern:
	## Play only a portion of the cycle.
	return _focus(s, e)._fast(StrudelFraction.new(1, 1).div(
		StrudelFraction.create(e).sub(StrudelFraction.create(s))))

func _hurry(r: Variant) -> StrudelPattern:
	## Speed up both pattern and playback speed.
	return _fast(r)

func _degrade_by(amount: float = 0.5, _seed: int = 0) -> StrudelPattern:
	## Randomly drop events. Uses Strudel's rand signal for deterministic
	## randomness matching Strudel v1.2.0's degradeBy implementation:
	## pat._degradeByWith(rand, amount)
	## = pat.fmap(a => _ => a).appLeft(rand.filterValues(v => v > amount))
	var pat: StrudelPattern = self
	var rand_pat: StrudelPattern = StrudelSignal.rand()
	return pat.fmap(func(a: Variant) -> Callable:
		return func(_b: Variant) -> Variant: return a
	).app_left(rand_pat.filter_values(func(v: Variant) -> bool:
		return float(v) > amount))

func _sometimes(func_transform: Callable) -> StrudelPattern:
	## Apply func ~50% of the time (per event).
	return _every(2, func_transform)

func _often(func_transform: Callable) -> StrudelPattern:
	return _every(4, func(p: StrudelPattern) -> StrudelPattern:
		return p._every(3, func_transform))

func _rarely(func_transform: Callable) -> StrudelPattern:
	return _every(4, func_transform)

func _chunk(n: int, func_transform: Callable) -> StrudelPattern:
	## Apply func to successive nth chunks of the cycle.
	var pat: StrudelPattern = self
	var pats: Array = []
	for i in range(n):
		var s: StrudelFraction = StrudelFraction.new(i, n)
		var e: StrudelFraction = StrudelFraction.new(i + 1, n)
		pats.append(pat._zoom(s, e).layer([func_transform])._slow(n)._late(s))
	return Strudel.slowcat(pats)

# ==============================================================================
# Value transformations
# ==============================================================================

func _round() -> StrudelPattern:
	return fmap(func(v: Variant) -> Variant: return roundi(v) if v is float or v is int else v)

func _floor() -> StrudelPattern:
	return fmap(func(v: Variant) -> Variant: return int(floorf(v)) if v is float or v is int else v)

func _ceil() -> StrudelPattern:
	return fmap(func(v: Variant) -> Variant: return int(ceilf(v)) if v is float or v is int else v)

func _range(min_val: Variant, max_val: Variant) -> StrudelPattern:
	## Map unipolar [0,1] values to [min, max].
	var mn: float = float(min_val)
	var mx: float = float(max_val)
	return fmap(func(v: Variant) -> float: return float(v) * (mx - mn) + mn)

func _segment(n: Variant) -> StrudelPattern:
	## Sample a continuous pattern n times per cycle.
	var num: int = int(n)
	var pat: StrudelPattern = self
	return Strudel.pure(true)._fast(num).fmap(
		func(_v: Variant) -> StrudelPattern: return pat).squeeze_join()

# ==============================================================================
# Note/sound controls (creates {note: x} objects)
# ==============================================================================

func note() -> StrudelPattern:
	## Wrap values as {note: value} dictionaries.
	return fmap(func(v: Variant) -> Dictionary: return {"note": v})

func s() -> StrudelPattern:
	## Wrap values as {s: value} dictionaries (sound/sample name).
	return fmap(func(v: Variant) -> Dictionary: return {"s": v})

func gain(amount: Variant = null) -> StrudelPattern:
	if amount == null:
		return fmap(func(v: Variant) -> Dictionary:
			if v is Dictionary:
				return v
			return {"gain": v})
	return set_in(Strudel.pure({"gain": amount}))

func velocity(amount: Variant = null) -> StrudelPattern:
	if amount == null:
		return fmap(func(v: Variant) -> Dictionary:
			if v is Dictionary:
				return v
			return {"velocity": v})
	return set_in(Strudel.pure({"velocity": amount}))


# ==============================================================================
# onTrigger (for scheduling output)
# ==============================================================================

func on_trigger(trigger_fn: Callable, dominant: bool = true) -> StrudelPattern:
	return with_hap(func(hap: StrudelHap) -> StrudelHap:
		var new_ctx: Dictionary = hap.context.duplicate()
		new_ctx["onTrigger"] = trigger_fn
		new_ctx["dominantTrigger"] = hap.context.get("dominantTrigger", false) or dominant
		return hap.set_context(new_ctx))


# ==============================================================================
# Display
# ==============================================================================

func _to_string() -> String:
	var haps: Array = first_cycle()
	var lines: Array = []
	for hap in haps:
		lines.append(hap.show(true))
	return "Pattern[%d haps: %s]" % [haps.size(), ", ".join(PackedStringArray(lines))]
