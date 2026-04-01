class_name ConfigProvider extends Resource

## Base class for all config providers. Inspector-visible, saveable as .tres.
## Replaces the old RefCounted-based providers in monster_config.gd.
## Same interface, same math — now a proper Resource.

@export var provider_name: String = ""


func get_value(_key: String) -> Variant:
	## Return the value for a key, or null if not provided.
	return null


func get_modifier(_key: String) -> Variant:
	## Return modifier info for a key, or null. Used by ModifierConfig.
	return null
