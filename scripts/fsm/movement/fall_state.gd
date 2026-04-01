extends State

## Character is falling (not on floor, moving downward).
## Transitions to: Idle/Run (landed), WallSlide (on wall)


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

	# Landed
	if ctx.body.is_on_floor():
		if absf(ctx.input.intent_direction.x) > 0.1:
			fsm.transition_to("Run")
		else:
			fsm.transition_to("Idle")
		return

	# Wall slide
	if ctx.body.is_on_wall_only() and ctx.body.velocity.y > 0.0:
		fsm.transition_to("WallSlide")
		return
