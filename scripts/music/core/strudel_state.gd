class_name StrudelState extends RefCounted

## Query input for Pattern.query(). Carries a time span and control parameters.
## Ported from Strudel v1.2.0 state.mjs.

var span: StrudelTimeSpan
var controls: Dictionary


func _init(p_span: StrudelTimeSpan, p_controls: Dictionary = {}) -> void:
	span = p_span
	controls = p_controls


func set_span(new_span: StrudelTimeSpan) -> StrudelState:
	return StrudelState.new(new_span, controls)


func with_span(func_span: Callable) -> StrudelState:
	return set_span(func_span.call(span))


func set_controls(new_controls: Dictionary) -> StrudelState:
	return StrudelState.new(span, new_controls)
