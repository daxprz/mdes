class_name Strudel extends RefCounted

## Static factory functions for creating patterns.
## These are the top-level Strudel API — pure(), silence(), stack(), sequence(), etc.
##
## Usage:
##   var pat = Strudel.pure("hello")
##   var drums = Strudel.sequence([Strudel.pure("bd"), Strudel.pure("sd")])
##   var layers = Strudel.stack([bass, drums, melody])
##
## Shorthand:
##   var S = Strudel  # alias for brevity
##   var pat = S.pure("c4").fast(2)

# -- Helpers -------------------------------------------------------------------

static func frac(numerator: int, denominator: int = 1) -> StrudelFraction:
	return StrudelFraction.new(numerator, denominator)

static func frac_f(value: float) -> StrudelFraction:
	return StrudelFraction.from_float(value)

static func ts(begin: Variant, end: Variant) -> StrudelTimeSpan:
	return StrudelTimeSpan.new(StrudelFraction.create(begin), StrudelFraction.create(end))

# -- Elemental Patterns --------------------------------------------------------

static func gap(steps: int = 1) -> StrudelPattern:
	## Does nothing, but with a given number of steps.
	return StrudelPattern.new(func(_state: StrudelState) -> Array: return [], steps)


static func silence() -> StrudelPattern:
	## Does absolutely nothing.
	return gap(1)


static func pure(value: Variant) -> StrudelPattern:
	## A discrete value that repeats once per cycle.
	var q := func(state: StrudelState) -> Array:
		var result: Array = []
		for subspan in state.span.spanCycles:
			var whole: StrudelTimeSpan = StrudelTimeSpan.new(
				subspan.begin.sam(), subspan.begin.next_sam())
			result.append(StrudelHap.new(whole, subspan, value))
		return result
	return StrudelPattern.new(q, 1)


static func reify(thing: Variant) -> StrudelPattern:
	## Convert anything to a Pattern. Already-patterns pass through.
	if thing is StrudelPattern:
		return thing
	# TODO: when mini parser exists, parse strings as mini notation here
	return pure(thing)


# -- Multi-Pattern Constructors ------------------------------------------------

static func stack(pats: Array) -> StrudelPattern:
	## Layer all patterns simultaneously.
	var reified: Array = pats.map(func(p: Variant) -> StrudelPattern:
		if p is Array: return sequence(p)
		return reify(p))
	var q := func(state: StrudelState) -> Array:
		var result: Array = []
		for pat in reified:
			result.append_array(pat.query.call(state))
		return result
	var result := StrudelPattern.new(q)
	# Steps = LCM of all constituent steps
	var steps_list: Array = reified.filter(
		func(p: StrudelPattern) -> bool: return p._steps != null
	).map(func(p: StrudelPattern) -> StrudelFraction: return p._steps)
	if not steps_list.is_empty():
		result._steps = _lcm_array(steps_list)
	return result


static func slowcat(pats: Array) -> StrudelPattern:
	## Concatenate patterns, one per cycle.
	var reified: Array = pats.map(func(p: Variant) -> StrudelPattern:
		if p is Array: return fastcat(p)
		return reify(p))
	if reified.size() == 1:
		return reified[0]
	var n_pats: int = reified.size()

	var q := func(state: StrudelState) -> Array:
		var span: StrudelTimeSpan = state.span
		var pat_n: int = _mod_int(span.begin.sam().n, n_pats, span.begin.sam().d)
		if pat_n < 0 or pat_n >= n_pats:
			return []
		var pat: StrudelPattern = reified[pat_n]
		# Offset to prevent skipping cycles
		var offset: StrudelFraction = span.begin.floor_frac().sub(
			span.begin.div(StrudelFraction.from_int(n_pats)).floor_frac())
		return pat.with_hap_time(
			func(t: StrudelFraction) -> StrudelFraction: return t.add(offset)
		).query.call(state.set_span(span.with_time(
			func(t: StrudelFraction) -> StrudelFraction: return t.sub(offset))))
	var result := StrudelPattern.new(q).split_queries()
	var steps_list: Array = reified.filter(
		func(p: StrudelPattern) -> bool: return p._steps != null
	).map(func(p: StrudelPattern) -> StrudelFraction: return p._steps)
	if not steps_list.is_empty():
		result._steps = _lcm_array(steps_list)
	return result


static func cat(pats: Array) -> StrudelPattern:
	## Alias for slowcat.
	return slowcat(pats)


static func fastcat(pats: Array) -> StrudelPattern:
	## Concatenate patterns, all within one cycle.
	var result: StrudelPattern = slowcat(pats)
	if pats.size() > 1:
		result = result._fast(pats.size())
		result._steps = StrudelFraction.from_int(pats.size())
	return result


static func sequence(pats: Array) -> StrudelPattern:
	## Alias for fastcat.
	return fastcat(pats)


static func seq(pats: Array) -> StrudelPattern:
	## Alias for fastcat.
	return fastcat(pats)


static func slowcat_prime(pats: Array) -> StrudelPattern:
	## Like slowcat, but skips cycles (doesn't offset).
	var reified: Array = pats.map(func(p: Variant) -> StrudelPattern: return reify(p))
	var n_pats: int = reified.size()
	var q := func(state: StrudelState) -> Array:
		var pat_n: int = int(floorf(state.span.begin.to_float())) % n_pats
		if pat_n < 0:
			pat_n = ((pat_n % n_pats) + n_pats) % n_pats
		if pat_n >= n_pats:
			return []
		var pat: StrudelPattern = reified[pat_n]
		return pat.query.call(state)
	return StrudelPattern.new(q).split_queries()


static func time_cat(entries: Array) -> StrudelPattern:
	## Concatenate with explicit durations: [[dur, pat], [dur, pat], ...]
	var total := StrudelFraction.new(0, 1)
	for entry in entries:
		total = total.add(StrudelFraction.create(entry[0]))
	var pats: Array = []
	for entry in entries:
		var dur: StrudelFraction = StrudelFraction.create(entry[0])
		var pat: StrudelPattern = reify(entry[1])
		pats.append(pure(pat)._compress(
			total.sub(dur).sub(total).negate().div(total),  # this simplifies to running_start/total
			total.sub(dur).sub(total).negate().add(dur).div(total)))
	# Actually, let me do this the simpler way matching Strudel's impl
	# timeCat = compress each pat into its proportional slice
	var running := StrudelFraction.new(0, 1)
	var result_pats: Array = []
	for entry in entries:
		var dur: StrudelFraction = StrudelFraction.create(entry[0])
		var pat: StrudelPattern = reify(entry[1])
		var start: StrudelFraction = running.div(total)
		var stop: StrudelFraction = running.add(dur).div(total)
		result_pats.append(pure(pat)._compress(start, stop))
		running = running.add(dur)
	return stack(result_pats).inner_join()


# -- Internal Helpers ----------------------------------------------------------

static func _lcm_array(fracs: Array) -> StrudelFraction:
	if fracs.is_empty():
		return null
	var result: StrudelFraction = fracs[0]
	for i in range(1, fracs.size()):
		if fracs[i] != null:
			result = result.lcm_with(fracs[i])
	return result


static func _mod_int(numerator: int, modulus: int, denominator: int = 1) -> int:
	## Modular arithmetic for cycle selection, matching Strudel's _mod behavior.
	## For fraction n/d, compute floor(n/d) % modulus
	var floor_val: int
	if denominator == 1:
		floor_val = numerator
	elif numerator >= 0:
		floor_val = numerator / denominator
	else:
		floor_val = (numerator / denominator) - 1
	if modulus == 0:
		return 0
	return ((floor_val % modulus) + modulus) % modulus
