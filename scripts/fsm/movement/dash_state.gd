extends State

## Character is dashing (brief invincible burst of speed).
## Transitions to: Run/Idle/Fall when dash timer expires.

var _dash_timer: float = 0.0
var _dash_direction: float = 1.0

const DASH_DURATION := 0.15
const DASH_SPEED := 600.0


func enter(msg: Dictionary = {}) -> void:
	_dash_timer = DASH_DURATION
	_dash_direction = msg.get("direction", 1.0)
	ctx.body.velocity.x = _dash_direction * DASH_SPEED
	ctx.body.velocity.y = 0.0


func physics_update(delta: float) -> void:
	_dash_timer -= delta
	ctx.body.velocity.x = _dash_direction * DASH_SPEED

	if _dash_timer <= 0.0:
		if ctx.body.is_on_floor():
			if absf(ctx.input.intent_direction.x) > 0.1:
				fsm.transition_to("Run")
			else:
				fsm.transition_to("Idle")
		else:
			fsm.transition_to("Fall")
