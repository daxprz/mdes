extends State

## Character is dead. Waits for revive.
## Transitions to: Ready (revived via HealthComponent signal)


func enter(_msg: Dictionary = {}) -> void:
	ctx.body.velocity = Vector2.ZERO
	# Connect to health component revive signal
	if ctx.health and not ctx.health.revived.is_connected(_on_revived):
		ctx.health.revived.connect(_on_revived)


func exit() -> void:
	if ctx.health and ctx.health.revived.is_connected(_on_revived):
		ctx.health.revived.disconnect(_on_revived)


func _on_revived() -> void:
	fsm.transition_to("Ready")
