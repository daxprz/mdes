class_name ClassDefinition extends Resource

## Blueprint for a character class. The Resource is the "what" — data, sprites,
## ability definitions, scene reference. The ClassComponent Node is the "how."
##
## Lives at: res://data/classes/<class_name>.tres

@export var display_name: String = ""
@export var sprite_sheet: Texture2D
@export var base_stats: StaticConfig
@export var class_scene: PackedScene      ## The ClassComponent scene to instantiate
@export var abilities: Array[AbilityDefinition] = []
@export var icon_color: Color = Color.WHITE
