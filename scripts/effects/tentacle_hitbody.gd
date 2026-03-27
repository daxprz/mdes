extends CharacterBody2D

## Thin collision proxy for rift_tentacle.gd.
## Lives as a child of the tentacle; forwards take_damage to it.

var _tentacle: Node2D = null


func take_damage(amount: int, attacker_index: int = -1) -> void:
	if is_instance_valid(_tentacle) and _tentacle.has_method("take_damage"):
		_tentacle.take_damage(amount, attacker_index)
