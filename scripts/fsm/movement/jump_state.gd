extends State

## Character is rising after a jump.
## Transitions to: Fall (velocity.y >= 0 or peak reached)


func enter(_msg: Dictionary = {}) -> void:
	var jump_vel: float = ctx.stats.cfg("jump_velocity", -550.0)
	ctx.body.velocity.y = jump_vel
	AudioManager.play("jump", -5.0)


func physics_update(delta: float) -> void:
	# Apply gravity
	var grav: float = ctx.stats.cfg("gravity", 900.0)
	ctx.body.velocity.y += grav * delta
	ctx.body.velocity.y = minf(ctx.body.velocity.y, 600.0)

	# Horizontal movement while airborne
	var h_input: float = ctx.input.intent_direction.x
	var speed: float = ctx.stats.cfg("speed", 100.0)
	ctx.body.velocity.x = h_input * speed

	if h_input != 0.0:
		ctx.body._facing_right = h_input > 0.0
		if ctx.body.sprite:
			ctx.body.sprite.flip_h = not ctx.body._facing_right

	# Transition to fall when moving downward
	if ctx.body.velocity.y >= 0.0:
		fsm.transition_to("Fall")
		return

	# Landed (hit ceiling and bounced?)
	if ctx.body.is_on_floor():
		fsm.transition_to("Idle")
		return
