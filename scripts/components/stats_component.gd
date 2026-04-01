class_name StatsComponent extends Node

## Config stack wrapper — resolves values through a stack of ConfigProviders.
## Same math as the existing monster_config.gd pattern, now as a proper component.

signal stat_changed(key: String, old_value: float, new_value: float)

var ctx: CharacterContext
var config_stack: Array[ConfigProvider] = []


func inject_context(c: CharacterContext) -> void:
	ctx = c


func cfg(key: String, default_val: float) -> float:
	## Resolve a config value by walking the stack (top-down for base values,
	## then applying modifiers from all providers).
	var val: float = default_val
	# Find base value (first provider that has it)
	for provider in config_stack:
		var pval: Variant = provider.get_value(key)
		if pval != null:
			val = float(pval)
			break
	# Apply modifiers from all providers
	for provider in config_stack:
		var mod: Variant = provider.get_modifier(key)
		if mod != null and mod is Array:
			val = ModifierConfig.apply(mod, val)
	return val


func push_config(provider: ConfigProvider) -> void:
	## Push a provider to the top of the stack (highest priority).
	config_stack.insert(0, provider)


func remove_config(provider: ConfigProvider) -> void:
	## Remove a provider from the stack.
	config_stack.erase(provider)


func set_base_config(provider: ConfigProvider) -> void:
	## Replace the bottom-of-stack base config (class defaults).
	if not config_stack.is_empty():
		config_stack[-1] = provider
	else:
		config_stack.append(provider)
