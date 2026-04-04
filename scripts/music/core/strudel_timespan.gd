class_name StrudelTimeSpan extends RefCounted

## A time interval [begin, end) in the pattern algebra.
## Both begin and end are exact Fractions.
## Ported from Strudel v1.2.0 timespan.mjs.

var begin: StrudelFraction
var end: StrudelFraction


func _init(b: StrudelFraction, e: StrudelFraction) -> void:
	begin = b
	end = e


# -- Cycle Splitting -----------------------------------------------------------

var spanCycles: Array:
	get:
		## Split this span at cycle boundaries. Returns Array[StrudelTimeSpan].
		## E.g., TimeSpan(0.5, 2.5) -> [TimeSpan(0.5,1), TimeSpan(1,2), TimeSpan(2,2.5)]
		var spans: Array = []
		var b: StrudelFraction = begin
		var e: StrudelFraction = end
		var e_sam: StrudelFraction = e.sam()

		# Support zero-width timespans
		if b.equals(e):
			return [StrudelTimeSpan.new(b, e)]

		while e.gt(b):
			# If begin and end are in the same cycle, we're done
			if b.sam().equals(e_sam):
				spans.append(StrudelTimeSpan.new(b, end))
				break
			# Add a timespan up to the next sam
			var next_b: StrudelFraction = b.next_sam()
			spans.append(StrudelTimeSpan.new(b, next_b))
			# Continue with the next cycle
			b = next_b
		return spans


# -- Properties ----------------------------------------------------------------

var duration: StrudelFraction:
	get:
		return end.sub(begin)


func midpoint() -> StrudelFraction:
	return begin.add(duration.div(StrudelFraction.new(2, 1)))


# -- Transformations -----------------------------------------------------------

func cycle_arc() -> StrudelTimeSpan:
	## Shift this timespan so it starts within cycle zero.
	var b: StrudelFraction = begin.cycle_pos()
	var e: StrudelFraction = b.add(duration)
	return StrudelTimeSpan.new(b, e)


func with_time(func_time: Callable) -> StrudelTimeSpan:
	## Apply a function to both begin and end.
	return StrudelTimeSpan.new(func_time.call(begin), func_time.call(end))


func with_end(func_time: Callable) -> StrudelTimeSpan:
	## Apply a function to the end time only.
	return StrudelTimeSpan.new(begin, func_time.call(end))


func with_cycle(func_time: Callable) -> StrudelTimeSpan:
	## Like with_time, but time is relative to the cycle.
	var s: StrudelFraction = begin.sam()
	var b: StrudelFraction = s.add(func_time.call(begin.sub(s)))
	var e: StrudelFraction = s.add(func_time.call(end.sub(s)))
	return StrudelTimeSpan.new(b, e)


# -- Intersection --------------------------------------------------------------

func intersection(other: StrudelTimeSpan) -> Variant:
	## Returns the intersection of two timespans, or null if they don't intersect.
	var intersect_begin: StrudelFraction = begin.max_frac(other.begin)
	var intersect_end: StrudelFraction = end.min_frac(other.end)

	if intersect_begin.gt(intersect_end):
		return null

	if intersect_begin.equals(intersect_end):
		# Zero-width intersection: doesn't count if it's at the end of a non-zero-width span
		if intersect_begin.equals(end) and begin.lt(end):
			return null
		if intersect_begin.equals(other.end) and other.begin.lt(other.end):
			return null

	return StrudelTimeSpan.new(intersect_begin, intersect_end)


func intersection_e(other: StrudelTimeSpan) -> StrudelTimeSpan:
	## Like intersection(), but asserts they do intersect.
	var result: Variant = intersection(other)
	assert(result != null, "StrudelTimeSpan: timespans do not intersect")
	return result


func shift_by(offset: float) -> StrudelTimeSpan:
	## Return a new timespan shifted by offset cycles.
	var off := StrudelFraction.from_float(offset)
	return StrudelTimeSpan.new(begin.add(off), end.add(off))


# -- Equality / Display --------------------------------------------------------

func equals(other: StrudelTimeSpan) -> bool:
	return begin.equals(other.begin) and end.equals(other.end)


func show() -> String:
	return begin.show() + " -> " + end.show()


func _to_string() -> String:
	return show()
