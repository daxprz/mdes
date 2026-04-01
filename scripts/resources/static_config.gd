class_name StaticConfig extends ConfigProvider

## Static key-value config. Replaces DictProvider.
## Loads from JSON class defaults and/or user overrides.
## Editable in Inspector via the data dictionary.

@export var data: Dictionary = {}


func get_value(key: String) -> Variant:
	if data.has(key):
		return data[key]
	return null


## Factory: load from class defaults JSON, merge user overrides.
static func from_class_defaults(cls_name: String) -> StaticConfig:
	var config := StaticConfig.new()
	config.provider_name = "%s_defaults" % cls_name

	# Load resource defaults
	var res_path: String = "res://data/config/class_defaults/%s.json" % cls_name
	var file := FileAccess.open(res_path, FileAccess.READ)
	if file:
		var parsed = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:
			config.data = parsed

	# Merge user overrides on top
	var override_path: String = "user://class_overrides/%s.json" % cls_name
	var ofile := FileAccess.open(override_path, FileAccess.READ)
	if ofile:
		var oparsed = JSON.parse_string(ofile.get_as_text())
		if oparsed is Dictionary:
			for key in oparsed:
				config.data[key] = oparsed[key]

	return config
