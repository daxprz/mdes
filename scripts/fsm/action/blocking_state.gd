extends State

## Character is blocking. Reduced movement speed, damage reduction.
## Transitions to: Ready (release block)


func enter(_msg: Dictionary = {}) -> void:
	pass


func physics_update(_delta: float) -> void:
	if not ctx.input.is_action_pressed("block"):
		fsm.transition_to("Ready")
