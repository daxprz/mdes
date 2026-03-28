extends "res://scripts/enemies/monster_controller.gd"

## AI controller for the quadruped monster.
## Delegates to the monster's built-in _do_* state functions.
## This is a thin adapter — the AI logic remains in quadruped_monster.gd.
## Future refactors can move the AI logic here incrementally.


func update(monster: CharacterBody2D, delta: float) -> void:
	# The AI sets _want_direction and _target_move_speed via the state match block.
	# Target acquisition happens inside _do_patrol / _do_chase.
	monster._want_direction = 0.0
	match monster._state:
		monster.State.PATROL:
			monster._do_patrol(delta)
		monster.State.CHASE:
			monster._do_chase(delta)
		monster.State.ATTACK_BITE:
			monster._do_bite(delta)
		monster.State.ATTACK_SWIPE:
			monster._do_swipe(delta)
		monster.State.ATTACK_TAIL:
			monster._do_tail_whip(delta)
		monster.State.ATTACK_LUNGE:
			monster._do_lunge(delta)
		monster.State.ATTACK_SPRINT_SLASH:
			monster._do_sprint_slash(delta)
		monster.State.ATTACK_HOP_UP:
			monster._do_hop_up(delta)
		monster.State.ATTACK_GRAB:
			monster._do_grab(delta)
		monster.State.ATTACK_LEAP_PLAN:
			monster._do_leap_plan(delta)
		monster.State.ATTACK_LEAP_WINDUP:
			monster._do_leap_windup(delta)
		monster.State.ATTACK_LEAP_AIRBORNE:
			monster._do_leap_airborne(delta)
		monster.State.ATTACK_LEAP_STRIKE:
			monster._do_leap_strike(delta)
		monster.State.ATTACK_LEAP_THRASH:
			monster._do_leap_thrash(delta)
		monster.State.PRECOGNITION:
			monster._do_precognition(delta)
		monster.State.TRANSITION_BIPEDAL:
			monster._do_transition_bipedal(delta)
		monster.State.TRANSITION_QUADRUPED:
			monster._do_transition_quadruped(delta)
		monster.State.STANDDOWN:
			pass  # No AI — just idle
		monster.State.CHAIN_DAZE:
			monster._do_chain_daze(delta)


func is_player() -> bool:
	return false
