extends RefCounted

## Base class for monster configuration providers. Subclass and override
## get_value() to provide config from different sources: JSON files, spawn
## overrides, power-ups, debuffs, state-based modifiers, etc.
##
## The monster holds a stack of providers checked in order (index 0 = highest
## priority). First non-null result wins. This enables composable effects:
##
##   stack[0] = RageBuff (overrides bite_damage=50)
##   stack[1] = SpawnOverrides (config={turn_speed=2.0})
##   stack[2] = BaseDefaults (JSON file with all defaults)
##
## Push/pop providers at runtime for temporary effects.
##
## Usage: var MCP = preload("res://scripts/systems/monster_config.gd")
##        var provider = MCP.DictProvider.new(data, "name")


func get_value(key: String) -> Variant:
	## Return the value for key, or null if this provider doesn't have it.
	## Override in subclasses.
	return null


# -- Concrete Providers --------------------------------------------------------

## DictProvider: wraps a Dictionary. Used for JSON files and spawn overrides.
class DictProvider:
	var _data: Dictionary = {}
	var _name: String = ""

	func _init(data: Dictionary = {}, provider_name: String = "dict") -> void:
		_data = data
		_name = provider_name

	func get_value(key: String) -> Variant:
		if _data.has(key):
			return _data[key]
		return null

	func is_expired() -> bool:
		return false

	func _to_string() -> String:
		return "DictProvider(%s, %d keys)" % [_name, _data.size()]


## CallableProvider: calls a function for each lookup. Used for dynamic/
## state-based values (e.g., "when hurt, speed *= 0.5").
class CallableProvider:
	var _fn: Callable
	var _name: String = ""

	func _init(fn: Callable, provider_name: String = "callable") -> void:
		_fn = fn
		_name = provider_name

	func get_value(key: String) -> Variant:
		if _fn.is_valid():
			return _fn.call(key)
		return null

	func is_expired() -> bool:
		return false

	func _to_string() -> String:
		return "CallableProvider(%s)" % _name


## TimedProvider: wraps another provider with an expiry time. After duration
## seconds, get_value() returns null (effectively removing the effect).
## The monster should periodically prune expired providers from its stack.
class TimedProvider:
	var _inner: Variant  # A provider (DictProvider, CallableProvider, etc.)
	var _name: String = ""
	var _expire_time: float = 0.0  # Engine time when this expires
	var _duration: float = 0.0

	func _init(inner: Variant, duration: float, provider_name: String = "timed") -> void:
		_inner = inner
		_duration = duration
		_expire_time = Time.get_ticks_msec() / 1000.0 + duration
		_name = provider_name

	func get_value(key: String) -> Variant:
		if Time.get_ticks_msec() / 1000.0 >= _expire_time:
			return null  # Expired
		return _inner.get_value(key)

	func is_expired() -> bool:
		return Time.get_ticks_msec() / 1000.0 >= _expire_time

	func _to_string() -> String:
		var remaining: float = _expire_time - Time.get_ticks_msec() / 1000.0
		return "TimedProvider(%s, %.1fs left)" % [_name, maxf(remaining, 0.0)]


## ModifierProvider: applies operations (multiply, add, min, max) to config values
## instead of overriding them. Multiple modifiers stack — all are applied in order.
##
## Usage:
##   var mods = { "exec_ball_mass_ratio": ["multiply", 1.5],   # 1.5x mass
##                "exec_ball_damage": ["add", 20],              # +20 damage
##                "exec_chain_elasticity": ["set", 1.0],        # force to 1.0
##                "speed": ["min", 50],                         # at least 50
##                "gravity": ["max", 500] }                     # at most 500
##   var provider = MCP.ModifierProvider.new(mods, "heavy_ball_artifact")
##
## Operations:
##   ["multiply", x]  — val *= x
##   ["add", x]       — val += x
##   ["set", x]       — val = x  (same as DictProvider, but explicit)
##   ["min", x]       — val = max(val, x)  (floor)
##   ["max", x]       — val = min(val, x)  (ceiling)
class ModifierProvider:
	var _modifiers: Dictionary = {}  # key -> [operation, value]
	var _name: String = ""

	func _init(modifiers: Dictionary = {}, provider_name: String = "modifier") -> void:
		_modifiers = modifiers
		_name = provider_name

	func get_value(_key: String) -> Variant:
		## ModifierProviders don't participate in the "first non-null wins" lookup.
		## They are applied separately via apply_modifiers(). Return null here.
		return null

	func get_modifier(key: String) -> Variant:
		## Returns [operation, value] for a key, or null if no modifier for this key.
		if _modifiers.has(key):
			return _modifiers[key]
		return null

	func has_modifier(key: String) -> bool:
		return _modifiers.has(key)

	func is_expired() -> bool:
		return false

	func is_modifier() -> bool:
		return true

	func _to_string() -> String:
		return "ModifierProvider(%s, %d mods)" % [_name, _modifiers.size()]


## Apply all modifier providers in a config stack to a base value.
## Call this after resolving the base value from DictProviders.
static func apply_modifiers(config_stack: Array, key: String, base_val: float) -> float:
	var val: float = base_val
	# Apply modifiers in reverse order (bottom of stack first = lowest priority)
	for i in range(config_stack.size() - 1, -1, -1):
		var provider = config_stack[i]
		if not provider.has_method("is_modifier") or not provider.is_modifier():
			continue
		var mod: Variant = provider.get_modifier(key)
		if mod == null:
			continue
		var op: String = mod[0]
		var operand: float = float(mod[1])
		match op:
			"multiply":
				val *= operand
			"add":
				val += operand
			"set":
				val = operand
			"min":
				val = maxf(val, operand)
			"max":
				val = minf(val, operand)
	return val
