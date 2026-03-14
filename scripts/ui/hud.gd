extends CanvasLayer

## In-game HUD that displays health, mana, muffin count, and artifacts
## for up to 4 players, each in a corner of the screen.

const CLASS_NAMES := {
	PlayerManager.CharacterClass.MELEE: "Melee",
	PlayerManager.CharacterClass.RANGED: "Ranged",
	PlayerManager.CharacterClass.MAGE: "Mage",
	PlayerManager.CharacterClass.SUMMONER: "Summoner",
	PlayerManager.CharacterClass.ROGUE: "Rogue",
}

const CLASS_COLORS := {
	PlayerManager.CharacterClass.MELEE: Color(0.9, 0.3, 0.2),
	PlayerManager.CharacterClass.RANGED: Color(0.2, 0.8, 0.3),
	PlayerManager.CharacterClass.MAGE: Color(0.3, 0.4, 0.95),
	PlayerManager.CharacterClass.SUMMONER: Color(0.8, 0.5, 0.9),
	PlayerManager.CharacterClass.ROGUE: Color(0.95, 0.85, 0.2),
}

const HEALTH_COLOR := Color(0.85, 0.15, 0.15)
const MANA_COLOR := Color(0.2, 0.4, 0.9)

## Maps player_index (0-3) to the corner node name.
const CORNER_MAP := {
	0: "TopLeft",
	1: "TopRight",
	2: "BottomLeft",
	3: "BottomRight",
}

@onready var corners: Control = $Margin/Corners


func _ready() -> void:
	PlayerManager.player_joined.connect(_on_player_joined)
	PlayerManager.player_left.connect(_on_player_left)

	# Style the progress bars and hide all corners initially.
	for i in range(PlayerManager.MAX_PLAYERS):
		var panel := _get_corner(i)
		if panel:
			_style_bars(panel)
			panel.visible = false

	# Show corners for already-joined players.
	for i in range(PlayerManager.MAX_PLAYERS):
		if PlayerManager.players.has(i):
			_on_player_joined(i)


func _process(_delta: float) -> void:
	for player_index in PlayerManager.players:
		_update_panel(player_index)


# -- Signal Callbacks ----------------------------------------------------------

func _on_player_joined(player_index: int) -> void:
	var panel := _get_corner(player_index)
	if panel == null:
		return
	panel.visible = true
	_update_header(player_index)
	_update_panel(player_index)


func _on_player_left(player_index: int) -> void:
	var panel := _get_corner(player_index)
	if panel:
		panel.visible = false


# -- Panel Helpers -------------------------------------------------------------

func _get_corner(player_index: int) -> VBoxContainer:
	var name_key: String = CORNER_MAP.get(player_index, "")
	if name_key.is_empty():
		return null
	return corners.get_node_or_null(name_key) as VBoxContainer


func _style_bars(panel: VBoxContainer) -> void:
	var health_bar: ProgressBar = panel.get_node("HealthBar")
	var mana_bar: ProgressBar = panel.get_node("ManaBar")

	# Use stylebox overrides for bar fill colors.
	var health_fill := StyleBoxFlat.new()
	health_fill.bg_color = HEALTH_COLOR
	health_bar.add_theme_stylebox_override("fill", health_fill)

	var health_bg := StyleBoxFlat.new()
	health_bg.bg_color = Color(0.2, 0.1, 0.1)
	health_bar.add_theme_stylebox_override("background", health_bg)

	var mana_fill := StyleBoxFlat.new()
	mana_fill.bg_color = MANA_COLOR
	mana_bar.add_theme_stylebox_override("fill", mana_fill)

	var mana_bg := StyleBoxFlat.new()
	mana_bg.bg_color = Color(0.1, 0.1, 0.2)
	mana_bar.add_theme_stylebox_override("background", mana_bg)


func _update_header(player_index: int) -> void:
	var panel := _get_corner(player_index)
	if panel == null:
		return

	var data: Dictionary = PlayerManager.get_player(player_index)
	if data.is_empty():
		return

	var char_class: PlayerManager.CharacterClass = data["character_class"]
	var header: HBoxContainer = panel.get_node("Header")
	var class_icon: ColorRect = header.get_node("ClassIcon")
	var player_label: Label = header.get_node("PlayerLabel")

	class_icon.color = CLASS_COLORS.get(char_class, Color.GRAY)
	player_label.text = "P%d - %s" % [player_index + 1, CLASS_NAMES.get(char_class, "???")]


func _update_panel(player_index: int) -> void:
	var panel := _get_corner(player_index)
	if panel == null:
		return

	var data: Dictionary = PlayerManager.get_player(player_index)
	if data.is_empty():
		return

	# Health bar.
	var health_bar: ProgressBar = panel.get_node("HealthBar")
	health_bar.max_value = data["max_health"]
	health_bar.value = data["health"]

	# Mana bar -- hide if the class has no mana.
	var mana_bar: ProgressBar = panel.get_node("ManaBar")
	if data["max_mana"] > 0:
		mana_bar.visible = true
		mana_bar.max_value = data["max_mana"]
		mana_bar.value = data["mana"]
	else:
		mana_bar.visible = false

	# Muffin count.
	var stats_row: HBoxContainer = panel.get_node("StatsRow")
	var muffin_label: Label = stats_row.get_node("MuffinLabel")
	muffin_label.text = "Muffins: %d" % GameManager.get_mini_muffin_count(player_index)

	# Artifact count.
	var artifact_label: Label = stats_row.get_node("ArtifactLabel")
	var artifacts: Array = GameManager.get_artifacts(player_index)
	artifact_label.text = "  Artifacts: %d" % artifacts.size()
