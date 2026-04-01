class_name InputController extends Node

## Base input controller. Subclass for Player (gamepad/keyboard) or AI.
## Exposes intent — the Character reads intent, never raw input.

var ctx: CharacterContext

## Intent state — set each frame by the active controller
var intent_direction: Vector2 = Vector2.ZERO    ## Movement direction (-1..1, -1..1)
var intent_aim: Vector2 = Vector2.ZERO          ## Aim direction (normalized or zero)
var intent_actions: Dictionary = {}             ## { "attack": bool, "jump": bool, ... }


func inject_context(c: CharacterContext) -> void:
	ctx = c


func poll() -> void:
	## Called each physics frame before FSMs process.
	## Subclass overrides this to read gamepad/keyboard/AI and set intent_*.
	pass


func is_action_pressed(action: String) -> bool:
	return intent_actions.get(action, false)


func is_action_just_pressed(action: String) -> bool:
	return intent_actions.get("just_%s" % action, false)


## Whether this controller represents a human player (affects camera, HUD, etc.)
func is_player() -> bool:
	return false
