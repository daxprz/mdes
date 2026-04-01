extends State

## Character is staggered (hit stun). No input accepted.
## Transitions to: Ready (timer expires)

var _stagger_timer: float = 0.0


func enter(msg: Dictionary = {}) -> void:
	_stagger_timer = msg.get("duration", 0.5)


func physics_update(delta: float) -> void:
	_stagger_timer -= delta
	# Visual shake
	ctx.body.position.x += sin(Time.get_ticks_msec() * 0.04) * 3.0

	if _stagger_timer <= 0.0:
		fsm.transition_to("Ready")
