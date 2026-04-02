extends "res://scripts/classes/class_component.gd"

## Ranger class — grapple hook, tether, crossbow, aimed archer shot.
## Extracted from player_side.gd. References the player via p (ctx.body).

var p: Object = null

func inject_context(c: Variant) -> void:
	ctx = c
	p = c.body if c else null


func on_class_enter() -> void:
	pass


func tick(delta: float) -> void:
	## Per-frame ranger logic — delegates to player's existing code.
	## Functions will migrate here incrementally.
	p._handle_ranger_reload(delta)
	p._handle_archer_aim(delta)


func perform_attack(_intent: Dictionary) -> void:
	p._attack_ranged()


func perform_special(_intent: Dictionary) -> void:
	p._special_grappling_hook()
