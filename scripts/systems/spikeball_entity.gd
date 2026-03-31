extends Node2D

## SpikeBallEntity — the Executioner's spike ball as a proper physics entity.
## Owns its config stack. Created persistently in _ready(), tracks ball position.
## Every physics body gets its own config. Keys drop the exec_ball_ prefix.

const DEFAULT_CONFIG := {
	"mass": 140.0,
	"gravity": 900.0,
	"damage": 35.0,
	"stun_duration": 3.0,
	"throw_speed": 1200.0,
	"max_throw_speed": 6000.0,
	"spin_speed": 4.0,
	"spin_accel": 3.0,
	"max_spin": 10.0,
	"wall_drag": 12.0,
	"ceiling_drag": 20.0,
}

var entity_id: String = "spikeball"
var _config_stack: Array = []
var _base_config: Variant = null
var owner_player: Node2D = null


func _ready() -> void:
	add_to_group("entities")
	_init_config()


func _init_config() -> void:
	if _base_config != null:
		return
	var MCP = preload("res://scripts/systems/monster_config.gd")
	_base_config = MCP.load_class_defaults("spikeball")
	if not _base_config:
		_base_config = MCP.DictProvider.new(DEFAULT_CONFIG, "spikeball_defaults")
	_config_stack = [_base_config]


func cfg(key: String, default_val: float) -> float:
	var val: float = default_val
	for provider in _config_stack:
		var pval: Variant = provider.get_value(key)
		if pval != null:
			val = float(pval)
			break
	var MCP = preload("res://scripts/systems/monster_config.gd")
	val = MCP.apply_modifiers(_config_stack, key, val)
	return val


func push_config(provider: Variant) -> void:
	_config_stack.insert(0, provider)


func remove_config(provider: Variant) -> void:
	_config_stack.erase(provider)
