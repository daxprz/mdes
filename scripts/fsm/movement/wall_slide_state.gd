extends State

## Character is sliding down a wall.
## Transitions to: Jump (wall jump), Fall (left wall), Idle (landed)


func enter(_msg: Dictionary = {}) -> void:
	# Cap fall speed to wall slide rate
	ctx.body.velocity.y = minf(ctx.body.velocity.y, 60.0)


func physics_update(delta: float) -> void:
	# Slow fall
	var grav: float = ctx.stats.cfg("gravity", 900.0)
	ctx.body.velocity.y += grav * delta
	ctx.body.velocity.y = minf(ctx.body.velocity.y, 60.0)

	# Landed
	if ctx.body.is_on_floor():
		fsm.transition_to("Idle")
		return

	# Left the wall
	if not ctx.body.is_on_wall_only():
		fsm.transition_to("Fall")
		return

	# Wall jump
	if ctx.input.is_action_just_pressed("jump"):
		var wall_normal: Vector2 = ctx.body.get_wall_normal()
		ctx.body.velocity.x = wall_normal.x * 200.0
		ctx.body.velocity.y = -400.0
		ctx.body._facing_right = wall_normal.x > 0.0
		if ctx.body.sprite:
			ctx.body.sprite.flip_h = not ctx.body._facing_right
		AudioManager.play("jump", -5.0, 1.2)
		fsm.transition_to("Jump")
		return
