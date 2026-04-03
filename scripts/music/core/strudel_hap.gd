class_name StrudelHap extends RefCounted

## An event in the pattern algebra. Named "Hap" because "Event" is reserved.
##
## whole: The full timespan of the event (null for continuous/signal values).
## part:  The visible fragment (may be clipped at cycle boundaries).
## value: The event's payload (any type — number, string, Dictionary, etc.).
## context: Metadata dictionary. context.locations carries source locations for highlighting.
##
## Ported from Strudel v1.2.0 hap.mjs.

var whole: Variant           ## StrudelTimeSpan or null (null for continuous)
var part: StrudelTimeSpan    ## Visible fragment
var value: Variant          ## Event payload
var context: Dictionary     ## Metadata (locations, etc.)
var stateful: bool          ## If true, value is a Callable that takes/returns state


func _init(p_whole: Variant, p_part: StrudelTimeSpan, p_value: Variant,
		p_context: Dictionary = {}, p_stateful: bool = false) -> void:
	whole = p_whole  # may be null
	part = p_part
	value = p_value
	context = p_context
	stateful = p_stateful


# -- Duration ------------------------------------------------------------------

func get_duration() -> StrudelFraction:
	var dur: StrudelFraction
	if value is Dictionary and value.has("duration") and value["duration"] is float:
		dur = StrudelFraction.from_float(value["duration"])
	elif whole != null:
		var w: StrudelTimeSpan = whole as StrudelTimeSpan
		dur = w.end.sub(w.begin)
	else:
		dur = part.end.sub(part.begin)

	if value is Dictionary and value.has("clip") and value["clip"] is float:
		dur = dur.mul(StrudelFraction.from_float(value["clip"]))
	return dur


func get_end_clipped() -> StrudelFraction:
	if whole == null:
		return part.end
	var w: StrudelTimeSpan = whole as StrudelTimeSpan
	return w.begin.add(get_duration())


# -- Typed whole accessor (avoids Variant property access issues) --------------

func w() -> StrudelTimeSpan:
	## Safe typed access to whole. Only call when whole != null.
	return whole as StrudelTimeSpan


# -- Time Queries --------------------------------------------------------------

func is_active(current_time: float) -> bool:
	if whole == null:
		return false
	return w().begin.to_float() <= current_time and get_end_clipped().to_float() >= current_time


func is_in_past(current_time: float) -> bool:
	return current_time > get_end_clipped().to_float()


func is_in_near_past(margin: float, current_time: float) -> bool:
	return current_time - margin <= get_end_clipped().to_float()


func is_in_future(current_time: float) -> bool:
	if whole == null:
		return false
	return current_time < w().begin.to_float()


func is_within_time(min_t: float, max_t: float) -> bool:
	if whole == null:
		return false
	return w().begin.to_float() <= max_t and get_end_clipped().to_float() >= min_t


# -- Accessors -----------------------------------------------------------------

func whole_or_part() -> StrudelTimeSpan:
	return w() if whole != null else part


func has_onset() -> bool:
	## True if this hap contains its onset (part begins where whole begins).
	return whole != null and w().begin.equals(part.begin)


# -- Transformations -----------------------------------------------------------

func with_span(func_span: Callable) -> StrudelHap:
	## Returns a new hap with the function applied to the timespan(s).
	var new_whole: Variant = func_span.call(w()) if whole != null else null
	return StrudelHap.new(new_whole, func_span.call(part), value, context)


func with_value(func_value: Callable) -> StrudelHap:
	## Returns a new hap with the function applied to the value.
	return StrudelHap.new(whole, part, func_value.call(value), context)


func set_context(new_context: Dictionary) -> StrudelHap:
	return StrudelHap.new(whole, part, value, new_context)


func combine_context(other: StrudelHap) -> Dictionary:
	var combined: Dictionary = {}
	combined.merge(context)
	combined.merge(other.context)
	# Concatenate locations arrays
	var locs_a: Array = context.get("locations", [])
	var locs_b: Array = other.context.get("locations", [])
	if not locs_a.is_empty() or not locs_b.is_empty():
		combined["locations"] = locs_a + locs_b
	return combined


# -- State Resolution ----------------------------------------------------------

func resolve_state(state: Dictionary) -> Array:
	## For stateful haps: call value(state) -> [new_state, new_value].
	## Returns [new_state, new_hap].
	if stateful and has_onset():
		var fn: Callable = value
		var result: Array = fn.call(state)
		var new_state: Dictionary = result[0]
		var new_value: Variant = result[1]
		return [new_state, StrudelHap.new(whole, part, new_value, context, false)]
	return [state, self]


# -- Equality ------------------------------------------------------------------

func span_equals(other: StrudelHap) -> bool:
	if whole == null and other.whole == null:
		return true
	if whole == null or other.whole == null:
		return false
	return w().equals(other.w())


func equals(other: StrudelHap) -> bool:
	return span_equals(other) and part.equals(other.part) and value == other.value


# -- Display -------------------------------------------------------------------

func show(compact: bool = false) -> String:
	var val_str: String
	if value is Dictionary:
		val_str = str(value) if not compact else str(value).replace('"', '').replace('{', '').replace('}', '')
	else:
		val_str = str(value)

	var spans: String = ""
	if whole == null:
		spans = "~" + part.show()
	else:
		var wt: StrudelTimeSpan = w()
		var is_whole_span: bool = wt.begin.equals(part.begin) and wt.end.equals(part.end)
		if not wt.begin.equals(part.begin):
			spans = wt.begin.show() + " << "
		if not is_whole_span:
			spans += "("
		spans += part.show()
		if not is_whole_span:
			spans += ")"
		if not wt.end.equals(part.end):
			spans += " >> " + wt.end.show()
	return "[ " + spans + " | " + val_str + " ]"


func show_whole(compact: bool = false) -> String:
	var val_str: String
	if value is Dictionary:
		val_str = str(value) if not compact else str(value).replace('"', '').replace('{', '').replace('}', '')
	else:
		val_str = str(value)
	var whole_str: String = "~" if whole == null else w().show()
	return "%s: %s" % [whole_str, val_str]


func _to_string() -> String:
	return show()
