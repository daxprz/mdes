extends State

## Character can perform actions (attack, special, block).
## Transitions to: Attacking, Charging, Blocking


func physics_update(_delta: float) -> void:
	# Block
	if ctx.input.is_action_pressed("block"):
		fsm.transition_to("Blocking")
		return

	# Attack
	if ctx.input.is_action_just_pressed("attack"):
		fsm.transition_to("Attacking")
		return

	# Special
	if ctx.input.is_action_just_pressed("special"):
		fsm.transition_to("Charging", {"ability": "special"})
		return
