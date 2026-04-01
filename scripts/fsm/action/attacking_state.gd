extends State

## Character is performing an attack. Delegates to ClassComponent.
## Transitions to: Ready (attack complete)

var _attack_timer: float = 0.0


func enter(_msg: Dictionary = {}) -> void:
	_attack_timer = 0.0
	if ctx.class_comp:
		ctx.class_comp.perform_attack({
			"aim": ctx.input.intent_aim,
			"direction": ctx.input.intent_direction,
		})


func physics_update(delta: float) -> void:
	_attack_timer += delta
	# Return to ready after cooldown
	var cooldown: float = ctx.stats.cfg("attack_cooldown", 0.4)
	if _attack_timer >= cooldown:
		fsm.transition_to("Ready")
