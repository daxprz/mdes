class_name ModifierConfig extends ConfigProvider

## Modifier that transforms values from lower providers in the stack.
## Replaces ModifierProvider from monster_config.gd.
## Operations: multiply, add, set, min, max
##
## Format: modifiers = { "key": ["operation", value], ... }
## Example: { "mass": ["multiply", 2.0], "speed": ["add", 50.0] }

@export var modifiers: Dictionary = {}
@export var description: String = ""


func get_value(_key: String) -> Variant:
	## Modifiers don't provide base values — they transform them.
	return null


func get_modifier(key: String) -> Variant:
	if modifiers.has(key):
		return modifiers[key]
	return null


## Apply this modifier's operation to a base value.
static func apply(mod_entry: Array, base_value: float) -> float:
	if mod_entry.size() < 2:
		return base_value
	var op: String = str(mod_entry[0])
	var val: float = float(mod_entry[1])
	match op:
		"multiply":
			return base_value * val
		"add":
			return base_value + val
		"set":
			return val
		"min":
			return minf(base_value, val)
		"max":
			return maxf(base_value, val)
	return base_value


## Load a modifier from a blueprint JSON file.
static func from_blueprint(path: String) -> ModifierConfig:
	var config := ModifierConfig.new()
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return config
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return config
	config.provider_name = parsed.get("_name", path.get_file().get_basename())
	config.description = parsed.get("_description", "")
	for key in parsed:
		if not key.begins_with("_"):
			config.modifiers[key] = parsed[key]
	return config
