extends State

## Character is on the ground, moving horizontally.
## Transitions to: Idle (no input), Jump (jump pressed), Fall (walk off edge)


func physics_update(_delta: float) -> void:
	# Fall off edge
	if not ctx.body.is_on_floor():
		fsm.transition_to("Fall")
		return

	# Jump
	if ctx.input.is_action_just_pressed("jump"):
		fsm.transition_to("Jump")
		return

	# Stop moving
	var h_input: float = ctx.input.intent_direction.x
	if absf(h_input) < 0.1:
		fsm.transition_to("Idle")
		return

	# Apply movement
	var speed: float = ctx.stats.cfg("speed", 100.0)
	ctx.body.velocity.x = h_input * speed

	# Face direction
	if h_input != 0.0:
		ctx.body._facing_right = h_input > 0.0
		if ctx.body.sprite:
			ctx.body.sprite.flip_h = not ctx.body._facing_right
