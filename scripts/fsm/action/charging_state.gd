extends State

## Character is charging an ability (hold to charge, release to fire).
## Transitions to: Ready (released or max charge reached)

var _charge_time: float = 0.0
var _ability: String = "special"


func enter(msg: Dictionary = {}) -> void:
	_charge_time = 0.0
	_ability = msg.get("ability", "special")


func physics_update(delta: float) -> void:
	_charge_time += delta

	# Release on button up
	var still_held: bool = false
	if _ability == "special":
		still_held = ctx.input.is_action_pressed("special")
	elif _ability == "attack":
		still_held = ctx.input.is_action_pressed("attack")

	if not still_held or _charge_time >= 3.0:
		# Fire the charged ability
		if ctx.class_comp:
			ctx.class_comp.perform_special({
				"charge_time": _charge_time,
				"aim": ctx.input.intent_aim,
				"direction": ctx.input.intent_direction,
			})
		fsm.transition_to("Ready")


func get_charge_ratio() -> float:
	var max_charge: float = ctx.stats.cfg("charge_time", 2.0) if ctx else 2.0
	return clampf(_charge_time / max_charge, 0.0, 1.0)
