extends RefCounted

## Base class for monster controllers (AI or Player).
## The controller sets intent variables on the monster each frame.
## The monster's state machine validates and executes the intents.

## Called every physics frame. Set monster._want_direction, _target_move_speed,
## _facing_target, and call request_* methods for attacks/abilities.
func update(_monster: CharacterBody2D, _delta: float) -> void:
	pass

## Called when this controller is attached to a monster.
func on_attach(_monster: CharacterBody2D) -> void:
	pass

## Called when this controller is detached from a monster.
func on_detach(_monster: CharacterBody2D) -> void:
	pass

## Whether this controller is player-driven (affects camera, HUD, targeting).
func is_player() -> bool:
	return false
