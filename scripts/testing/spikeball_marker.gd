extends Node2D

## Spike ball marker — tracks the Executioner's ball position in the scene tree.
## Proxies cfg()/push_config()/remove_config() to the owning player so it
## appears as a configurable entity in the debug drawer with ball properties.

var _owner_player: Node2D = null
var entity_id: String = "spikeball"
var _config_stack: Array = []  # Proxy — delegates to owner


func cfg(key: String, default_val: float) -> float:
	if _owner_player and is_instance_valid(_owner_player) and _owner_player.has_method("cfg"):
		return _owner_player.cfg(key, default_val)
	return default_val


func push_config(provider: Variant) -> void:
	if _owner_player and is_instance_valid(_owner_player) and _owner_player.has_method("push_config"):
		_owner_player.push_config(provider)


func remove_config(provider: Variant) -> void:
	if _owner_player and is_instance_valid(_owner_player) and _owner_player.has_method("remove_config"):
		_owner_player.remove_config(provider)
