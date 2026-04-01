extends State

## Character is on the ground, not moving.
## Transitions to: Run (input), Jump (jump pressed), Fall (walk off edge)


func enter(_msg: Dictionary = {}) -> void:
	ctx.body.velocity.x = 0.0


func physics_update(_delta: float) -> void:
	# Fall off edge
	if not ctx.body.is_on_floor():
		fsm.transition_to("Fall")
		return

	# Jump
	if ctx.input.is_action_just_pressed("jump"):
		fsm.transition_to("Jump")
		return

	# Start moving
	if absf(ctx.input.intent_direction.x) > 0.1:
		fsm.transition_to("Run")
		return
