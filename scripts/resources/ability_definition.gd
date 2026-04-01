class_name AbilityDefinition extends Resource

## Data definition for a single ability (attack, special, passive).
## Pure data — no behavior. The ClassComponent reads these to configure its logic.

@export var ability_name: String = ""
@export var cooldown: float = 0.5
@export var mana_cost: float = 0.0
@export var damage_mult: float = 1.0
@export var knockback_mult: float = 1.0
@export var description: String = ""
@export var icon: Texture2D
