extends Node

## Always-visible player HUD at the bottom of the screen.
## Shows 1-4 panels based on connected controllers.
## On the title screen, players use D-pad to select profile/class inline.

const CLASS_NAMES := {
	PlayerManager.CharacterClass.MELEE: "Melee",
	PlayerManager.CharacterClass.RANGED: "Ranged",
	PlayerManager.CharacterClass.MAGE: "Mage",
	PlayerManager.CharacterClass.SUMMONER: "Summoner",
	PlayerManager.CharacterClass.ROGUE: "Rogue",
	PlayerManager.CharacterClass.DEMOLITIONIST: "Demolitionist",
	PlayerManager.CharacterClass.HEALER: "Healer",
	PlayerManager.CharacterClass.TANK: "Tank",
	PlayerManager.CharacterClass.NINJA: "Ninja",
	PlayerManager.CharacterClass.BALLOONIST: "Balloonist",
	PlayerManager.CharacterClass.GUITARIST: "Guitarist",
	PlayerManager.CharacterClass.WEREWOLF: "Werewolf",
	PlayerManager.CharacterClass.EXECUTIONER: "Executioner",
}

const CLASS_COLORS := {
	PlayerManager.CharacterClass.MELEE: Color(0.9, 0.3, 0.2),
	PlayerManager.CharacterClass.RANGED: Color(0.2, 0.8, 0.3),
	PlayerManager.CharacterClass.MAGE: Color(0.3, 0.4, 0.95),
	PlayerManager.CharacterClass.SUMMONER: Color(0.8, 0.5, 0.9),
	PlayerManager.CharacterClass.ROGUE: Color(0.95, 0.85, 0.2),
	PlayerManager.CharacterClass.DEMOLITIONIST: Color(0.9, 0.6, 0.1),
	PlayerManager.CharacterClass.HEALER: Color(0.3, 0.9, 0.4),
	PlayerManager.CharacterClass.TANK: Color(0.6, 0.5, 0.35),
	PlayerManager.CharacterClass.NINJA: Color(0.2, 0.9, 0.9),
	PlayerManager.CharacterClass.BALLOONIST: Color(0.9, 0.4, 0.7),
	PlayerManager.CharacterClass.GUITARIST: Color(0.9, 0.7, 0.2),
	PlayerManager.CharacterClass.WEREWOLF: Color(0.5, 0.3, 0.15),
	PlayerManager.CharacterClass.EXECUTIONER: Color(0.15, 0.1, 0.1),
}

const CLASS_SPRITE_PATHS := {
	PlayerManager.CharacterClass.MELEE: "res://assets/sprites/characters/melee_side.png",
	PlayerManager.CharacterClass.RANGED: "res://assets/sprites/characters/ranged_side.png",
	PlayerManager.CharacterClass.MAGE: "res://assets/sprites/characters/mage_side.png",
	PlayerManager.CharacterClass.SUMMONER: "res://assets/sprites/characters/summoner_side.png",
	PlayerManager.CharacterClass.ROGUE: "res://assets/sprites/characters/rogue_side.png",
	PlayerManager.CharacterClass.DEMOLITIONIST: "res://assets/sprites/characters/demolitionist_side.png",
	PlayerManager.CharacterClass.HEALER: "res://assets/sprites/characters/healer_side.png",
	PlayerManager.CharacterClass.TANK: "res://assets/sprites/characters/tank_side.png",
	PlayerManager.CharacterClass.NINJA: "res://assets/sprites/characters/ninja_side.png",
	PlayerManager.CharacterClass.BALLOONIST: "res://assets/sprites/characters/balloonist_side.png",
	PlayerManager.CharacterClass.GUITARIST: "res://assets/sprites/characters/guitarist_side.png",
	PlayerManager.CharacterClass.WEREWOLF: "res://assets/sprites/characters/werewolf_side.png",
	PlayerManager.CharacterClass.EXECUTIONER: "res://assets/sprites/characters/executioner_side.png",
}

const ALL_CLASSES: Array[PlayerManager.CharacterClass] = [
	PlayerManager.CharacterClass.MELEE,
	PlayerManager.CharacterClass.RANGED,
	PlayerManager.CharacterClass.MAGE,
	PlayerManager.CharacterClass.SUMMONER,
	PlayerManager.CharacterClass.ROGUE,
	PlayerManager.CharacterClass.DEMOLITIONIST,
	PlayerManager.CharacterClass.HEALER,
	PlayerManager.CharacterClass.TANK,
	PlayerManager.CharacterClass.NINJA,
	PlayerManager.CharacterClass.BALLOONIST,
	PlayerManager.CharacterClass.GUITARIST,
	PlayerManager.CharacterClass.WEREWOLF,
	PlayerManager.CharacterClass.EXECUTIONER,
	PlayerManager.CharacterClass.MONSTER,
]

const HUD_HEIGHT := 80
const HUD_BOTTOM_MARGIN := 10
const HUD_PANEL_WIDTH := 220
const HUD_PANEL_SPACING := 16

## Emitted when a player changes class on the title screen
signal class_changed(player_index: int, new_class: PlayerManager.CharacterClass)
## Emitted when a player wants to create a profile (START on title screen)
signal create_profile_requested(device_id: int)

var _canvas: CanvasLayer = null
var _hud_container: HBoxContainer = null
var _backing: ColorRect = null
var _panels: Dictionary = {}  # player_index -> Dictionary of UI nodes
var _muffin_label: Label = null
var _cycle_cooldowns: Dictionary = {}  # "device_button" -> float
var class_change_locked: Dictionary = {}  # player_index -> true (temporary rift lock)
var tentacle_lost: Dictionary = {}  # player_index -> true (permanent: tentacle attached to enemy)
const MAX_ACTIVE_TENTACLES := 4  # Max rift tentacles in-game at once
var active_tentacle_count: int = 0
var _debug_mode: bool = false
var _debug_labels: Dictionary = {}  # player_index -> Label
var debug_selected_enemy: Node2D = null  # TAB-cycled enemy for diagnostics
var _debug_enemy_index: int = -1  # Index into enemies group
var _hud_popups: Dictionary = {}  # player_index -> true (HUD popup visible for this player)
var _popup_panels: Dictionary = {}  # player_index -> Control node in canvas
var profile_select_mode: bool = false  # True when in pause-menu profile selection mode

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_hud()
	PlayerManager.player_joined.connect(_on_player_joined)
	PlayerManager.player_left.connect(_on_player_left)
	GameManager.state_changed.connect(_on_state_changed)


func _on_state_changed(_new_state: GameManager.GameState) -> void:
	# Reset tentacle status at the start of each level
	class_change_locked.clear()
	tentacle_lost.clear()
	active_tentacle_count = 0

	# Remove all bottom bar panels when leaving title screen
	if _new_state != GameManager.GameState.TITLE:
		for pi in _panels.keys():
			_panels[pi]["panel"].queue_free()
		_panels.clear()
		if _backing:
			_backing.visible = false
		if _hud_container:
			_hud_container.visible = false
		if _muffin_label:
			_muffin_label.visible = false

	# Clear popup HUDs on scene change
	for pi in _popup_panels.keys():
		_popup_panels[pi]["panel"].queue_free()
	_popup_panels.clear()
	_hud_popups.clear()


func _build_hud() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 100
	_canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_canvas)

	# Dark backing strip across bottom
	_backing = ColorRect.new()
	_backing.color = Color(0, 0, 0, 0.6)
	_backing.anchor_left = 0.0
	_backing.anchor_right = 1.0
	_backing.anchor_top = 1.0
	_backing.anchor_bottom = 1.0
	_backing.offset_top = -(HUD_HEIGHT + HUD_BOTTOM_MARGIN)
	_backing.offset_bottom = 0
	_canvas.add_child(_backing)

	# HBox container for player panels, centered at bottom
	_hud_container = HBoxContainer.new()
	_hud_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_hud_container.add_theme_constant_override("separation", HUD_PANEL_SPACING)
	_hud_container.anchor_left = 0.5
	_hud_container.anchor_right = 0.5
	_hud_container.anchor_top = 1.0
	_hud_container.anchor_bottom = 1.0
	var total_width: float = HUD_PANEL_WIDTH * 4 + HUD_PANEL_SPACING * 3
	_hud_container.offset_left = -total_width / 2.0
	_hud_container.offset_right = total_width / 2.0
	_hud_container.offset_top = -(HUD_HEIGHT + HUD_BOTTOM_MARGIN)
	_hud_container.offset_bottom = -HUD_BOTTOM_MARGIN
	_canvas.add_child(_hud_container)

	# Muffin counter - top center
	_muffin_label = Label.new()
	_muffin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_muffin_label.add_theme_font_size_override("font_size", 14)
	_muffin_label.modulate = Color(1.0, 0.85, 0.2)
	_muffin_label.anchors_preset = Control.PRESET_CENTER_TOP
	_muffin_label.anchor_left = 0.5
	_muffin_label.anchor_right = 0.5
	_muffin_label.offset_left = -100
	_muffin_label.offset_right = 100
	_muffin_label.offset_top = 5
	_muffin_label.offset_bottom = 25
	_muffin_label.text = ""
	_canvas.add_child(_muffin_label)


func _create_panel(player_index: int) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(HUD_PANEL_WIDTH, HUD_HEIGHT - 8)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.12, 0.9)
	style.border_color = Color(0.4, 0.3, 0.2)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	panel.add_child(hbox)

	# Class sprite icon (first frame of the 192x32 spritesheet, 32x32)
	var icon_container := Control.new()
	icon_container.custom_minimum_size = Vector2(48, 48)
	icon_container.clip_contents = true
	hbox.add_child(icon_container)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(48, 48)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon_container.add_child(icon)

	# Info vbox
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 1)
	hbox.add_child(vbox)

	# Name label
	var name_lbl := Label.new()
	name_lbl.text = "P%d" % (player_index + 1)
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.modulate = Color(1.0, 1.0, 1.0)
	vbox.add_child(name_lbl)

	# Class label
	var class_lbl := Label.new()
	class_lbl.text = "---"
	class_lbl.add_theme_font_size_override("font_size", 11)
	class_lbl.modulate = Color(0.7, 0.7, 0.7)
	vbox.add_child(class_lbl)

	# HP bar
	var hp_bar := ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(0, 8)
	hp_bar.max_value = 100
	hp_bar.value = 100
	hp_bar.show_percentage = false
	var hp_style_bg := StyleBoxFlat.new()
	hp_style_bg.bg_color = Color(0.2, 0.05, 0.05)
	hp_style_bg.set_corner_radius_all(2)
	hp_bar.add_theme_stylebox_override("background", hp_style_bg)
	var hp_style_fill := StyleBoxFlat.new()
	hp_style_fill.bg_color = Color(0.8, 0.2, 0.15)
	hp_style_fill.set_corner_radius_all(2)
	hp_bar.add_theme_stylebox_override("fill", hp_style_fill)
	vbox.add_child(hp_bar)

	# Mana bar
	var mana_bar := ProgressBar.new()
	mana_bar.custom_minimum_size = Vector2(0, 6)
	mana_bar.max_value = 100
	mana_bar.value = 100
	mana_bar.show_percentage = false
	var mana_style_bg := StyleBoxFlat.new()
	mana_style_bg.bg_color = Color(0.05, 0.05, 0.2)
	mana_style_bg.set_corner_radius_all(2)
	mana_bar.add_theme_stylebox_override("background", mana_style_bg)
	var mana_style_fill := StyleBoxFlat.new()
	mana_style_fill.bg_color = Color(0.2, 0.3, 0.9)
	mana_style_fill.set_corner_radius_all(2)
	mana_bar.add_theme_stylebox_override("fill", mana_style_fill)
	vbox.add_child(mana_bar)

	# Hint label (only shown on title screen)
	var hint_lbl := Label.new()
	hint_lbl.text = ""
	hint_lbl.add_theme_font_size_override("font_size", 8)
	hint_lbl.modulate = Color(0.5, 0.5, 0.5)
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint_lbl)

	_hud_container.add_child(panel)

	_panels[player_index] = {
		"panel": panel,
		"icon": icon,
		"name_label": name_lbl,
		"class_label": class_lbl,
		"hp_bar": hp_bar,
		"mana_bar": mana_bar,
		"hint_label": hint_lbl,
		"style": style,
		"current_class": -1,  # Track to avoid re-loading sprite every frame
	}


func _remove_panel(player_index: int) -> void:
	if _panels.has(player_index):
		_panels[player_index]["panel"].queue_free()
		_panels.erase(player_index)


func _on_player_joined(player_index: int) -> void:
	# Bottom bar panels only on title screen
	if GameManager.current_state == GameManager.GameState.TITLE:
		if not _panels.has(player_index):
			_create_panel(player_index)
		_update_panel(player_index)
	else:
		# During gameplay, remove any lingering bottom bar panel
		_remove_panel(player_index)


func _on_player_left(player_index: int) -> void:
	_remove_panel(player_index)
	_remove_popup_panel(player_index)
	_hud_popups.erase(player_index)


func _process(delta: float) -> void:
	_process_announcement(delta)
	# Cooldowns
	for key in _cycle_cooldowns.keys():
		_cycle_cooldowns[key] -= delta
		if _cycle_cooldowns[key] <= 0.0:
			_cycle_cooldowns.erase(key)

	var is_title: bool = GameManager.current_state == GameManager.GameState.TITLE

	# Hide bottom bar and panels during gameplay — only show on title screen
	if _backing:
		_backing.visible = is_title
	if _hud_container:
		_hud_container.visible = is_title

	# Update popup HUD positions (corner nearest to player)
	_update_popup_positions()

	# Muffin counter hidden during gameplay
	if _muffin_label:
		_muffin_label.visible = false

	# Update bottom bar panels (title screen only)
	if is_title:
		for pi in _panels.keys():
			_update_panel(pi)

	# Show hints / tentacle status (title screen only)
	for pi in _panels.keys():
		var hint: Label = _panels[pi]["hint_label"]
		if tentacle_lost.has(pi):
			hint.text = "TENTACLE LOST"
			hint.modulate = Color(0.7, 0.2, 0.3)
		elif class_change_locked.has(pi):
			hint.text = "RIFT ACTIVE..."
			hint.modulate = Color(0.9, 0.3, 0.2)
		elif is_title:
			hint.text = "D-Pad: profile/class"
			hint.modulate = Color(0.5, 0.5, 0.5)
		else:
			hint.text = "L/R: change class"
			hint.modulate = Color(0.4, 0.6, 0.4)

	# Debug: show button states above each HUD panel
	_update_debug_labels()


func _create_popup_panel(player_index: int) -> void:
	if _popup_panels.has(player_index):
		return
	# Create a small HUD panel on the canvas layer
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(HUD_PANEL_WIDTH, HUD_HEIGHT - 8)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.12, 0.85)
	style.border_color = Color(0.4, 0.3, 0.2)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	panel.add_child(hbox)

	var icon_container := Control.new()
	icon_container.custom_minimum_size = Vector2(48, 48)
	icon_container.clip_contents = true
	hbox.add_child(icon_container)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(48, 48)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon_container.add_child(icon)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 1)
	hbox.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.text = "P%d" % (player_index + 1)
	name_lbl.add_theme_font_size_override("font_size", 14)
	vbox.add_child(name_lbl)

	var class_lbl := Label.new()
	class_lbl.text = "---"
	class_lbl.add_theme_font_size_override("font_size", 11)
	class_lbl.modulate = Color(0.7, 0.7, 0.7)
	vbox.add_child(class_lbl)

	var hp_bar := ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(0, 8)
	hp_bar.show_percentage = false
	var hp_bg := StyleBoxFlat.new()
	hp_bg.bg_color = Color(0.2, 0.05, 0.05)
	hp_bg.set_corner_radius_all(2)
	hp_bar.add_theme_stylebox_override("background", hp_bg)
	var hp_fill := StyleBoxFlat.new()
	hp_fill.bg_color = Color(0.8, 0.2, 0.15)
	hp_fill.set_corner_radius_all(2)
	hp_bar.add_theme_stylebox_override("fill", hp_fill)
	vbox.add_child(hp_bar)

	var mana_bar := ProgressBar.new()
	mana_bar.custom_minimum_size = Vector2(0, 6)
	mana_bar.show_percentage = false
	var mana_bg := StyleBoxFlat.new()
	mana_bg.bg_color = Color(0.05, 0.05, 0.2)
	mana_bg.set_corner_radius_all(2)
	mana_bar.add_theme_stylebox_override("background", mana_bg)
	var mana_fill := StyleBoxFlat.new()
	mana_fill.bg_color = Color(0.2, 0.3, 0.9)
	mana_fill.set_corner_radius_all(2)
	mana_bar.add_theme_stylebox_override("fill", mana_fill)
	vbox.add_child(mana_bar)

	_canvas.add_child(panel)
	_popup_panels[player_index] = {
		"panel": panel,
		"icon": icon,
		"name_label": name_lbl,
		"class_label": class_lbl,
		"hp_bar": hp_bar,
		"mana_bar": mana_bar,
		"style": style,
		"current_class": -1,
	}


func _remove_popup_panel(player_index: int) -> void:
	if _popup_panels.has(player_index):
		_popup_panels[player_index]["panel"].queue_free()
		_popup_panels.erase(player_index)


func _update_popup_positions() -> void:
	var cam := get_viewport().get_camera_2d() if get_viewport() else null
	if not cam:
		return
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var zoom: Vector2 = cam.zoom if cam and cam.zoom.x > 0 else Vector2.ONE

	for pi in _popup_panels.keys():
		var popup: Dictionary = _popup_panels[pi]
		var panel: PanelContainer = popup["panel"]

		# Find the player's screen position
		var p_data: Dictionary = PlayerManager.get_player(pi)
		if p_data.is_empty():
			continue

		# Update the popup panel data
		_update_popup_data(pi, popup, p_data)

		# Find the player node
		var player_pos: Vector2 = cam.global_position  # fallback
		for node in get_tree().get_nodes_in_group("players"):
			if node is Node2D and "player_index" in node and node.player_index == pi:
				player_pos = node.global_position
				break

		# Convert player world pos to screen pos
		var screen_pos: Vector2 = (player_pos - cam.global_position) * zoom + vp_size / 2.0

		# Pick the nearest corner
		var margin: float = 10.0
		var pw: float = HUD_PANEL_WIDTH
		var ph: float = HUD_HEIGHT
		var corners := [
			Vector2(margin, margin),  # Top-left
			Vector2(vp_size.x - pw - margin, margin),  # Top-right
			Vector2(margin, vp_size.y - ph - margin),  # Bottom-left
			Vector2(vp_size.x - pw - margin, vp_size.y - ph - margin),  # Bottom-right
		]

		var best_corner: Vector2 = corners[0]
		var best_dist: float = INF
		for c in corners:
			var center: Vector2 = c + Vector2(pw / 2.0, ph / 2.0)
			var d: float = screen_pos.distance_to(center)
			if d < best_dist:
				best_dist = d
				best_corner = c

		panel.anchor_left = 0
		panel.anchor_top = 0
		panel.anchor_right = 0
		panel.anchor_bottom = 0
		panel.offset_left = best_corner.x
		panel.offset_top = best_corner.y
		panel.offset_right = best_corner.x + pw
		panel.offset_bottom = best_corner.y + ph


func _update_popup_data(player_index: int, popup: Dictionary, p_data: Dictionary) -> void:
	var char_class: PlayerManager.CharacterClass = p_data["character_class"]
	var name_lbl: Label = popup["name_label"]
	var profile: Dictionary = ProfileManager.get_active_profile(player_index)
	name_lbl.text = profile.get("name", "P%d" % (player_index + 1)) if not profile.is_empty() else "P%d" % (player_index + 1)

	var class_lbl: Label = popup["class_label"]
	class_lbl.text = CLASS_NAMES.get(char_class, "???")

	if popup["current_class"] != char_class:
		popup["current_class"] = char_class
		var icon: TextureRect = popup["icon"]
		var sprite_path: String = CLASS_SPRITE_PATHS.get(char_class, "")
		if not sprite_path.is_empty():
			var sheet: Texture2D = load(sprite_path)
			if sheet:
				var atlas := AtlasTexture.new()
				atlas.atlas = sheet
				atlas.region = Rect2(0, 0, 32, 32)
				icon.texture = atlas

	var style: StyleBoxFlat = popup["style"]
	style.border_color = CLASS_COLORS.get(char_class, Color(0.4, 0.3, 0.2))

	var hp_bar: ProgressBar = popup["hp_bar"]
	hp_bar.max_value = p_data.get("max_health", 100)
	hp_bar.value = p_data.get("health", 100)

	var mana_bar: ProgressBar = popup["mana_bar"]
	mana_bar.max_value = p_data.get("max_mana", 100)
	mana_bar.value = p_data.get("mana", 100)


func _update_debug_labels() -> void:
	if not DebugOverlay.should_draw("player/button_state", self):
		for pi in _debug_labels.keys():
			if is_instance_valid(_debug_labels[pi]):
				_debug_labels[pi].visible = false
		return

	for pi in _panels.keys():
		var p_data: Dictionary = PlayerManager.get_player(pi)
		if p_data.is_empty():
			continue

		var dev_id: int = p_data.get("device_id", -1)

		# Create debug label if needed
		if not _debug_labels.has(pi) or not is_instance_valid(_debug_labels[pi]):
			var lbl := Label.new()
			lbl.add_theme_font_size_override("font_size", 8)
			lbl.modulate = Color(1.0, 1.0, 0.3, 0.9)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_canvas.add_child(lbl)
			_debug_labels[pi] = lbl

		var lbl: Label = _debug_labels[pi]
		lbl.visible = true

		# Position above the HUD panel
		var panel_count: int = _panels.size()
		var total_width: float = HUD_PANEL_WIDTH * panel_count + HUD_PANEL_SPACING * (panel_count - 1)
		var panel_idx: int = _panels.keys().find(pi)
		var panel_x: float = -total_width / 2.0 + panel_idx * (HUD_PANEL_WIDTH + HUD_PANEL_SPACING) + HUD_PANEL_WIDTH / 2.0

		var vp_size: Vector2 = get_viewport().get_visible_rect().size
		lbl.anchor_left = 0.5
		lbl.anchor_right = 0.5
		lbl.anchor_top = 1.0
		lbl.offset_left = panel_x - HUD_PANEL_WIDTH / 2.0
		lbl.offset_right = panel_x + HUD_PANEL_WIDTH / 2.0
		lbl.offset_top = -(HUD_HEIGHT + HUD_BOTTOM_MARGIN + 45)
		lbl.offset_bottom = -(HUD_HEIGHT + HUD_BOTTOM_MARGIN)

		# Build button state string
		var btn_text: String = ""
		if dev_id == -1:
			# Keyboard
			btn_text = "KB: "
			for action in ["attack", "special", "jump", "block", "grapple"]:
				var pressed: bool = Input.is_action_pressed(action)
				var short: String = action.substr(0, 3).to_upper()
				btn_text += short + ("*" if pressed else ".") + " "
		else:
			# Controller buttons
			var button_names := ["A", "B", "X", "Y", "Sel", "??", "Opt", "R3", "L3", "LB", "RB",
				"DU", "DD", "DL", "DR"]
			btn_text = "P%d: " % (pi + 1)
			for bi in range(mini(button_names.size(), 15)):
				var pressed: bool = Input.is_joy_button_pressed(dev_id, bi)
				if pressed:
					btn_text += button_names[bi] + " "

			# Axes
			var lx: float = Input.get_joy_axis(dev_id, JOY_AXIS_LEFT_X)
			var ly: float = Input.get_joy_axis(dev_id, JOY_AXIS_LEFT_Y)
			if absf(lx) > 0.15 or absf(ly) > 0.15:
				btn_text += "L(%.1f,%.1f) " % [lx, ly]
			var rx: float = Input.get_joy_axis(dev_id, JOY_AXIS_RIGHT_X)
			var ry: float = Input.get_joy_axis(dev_id, JOY_AXIS_RIGHT_Y)
			if absf(rx) > 0.15 or absf(ry) > 0.15:
				btn_text += "R(%.1f,%.1f) " % [rx, ry]

		lbl.text = btn_text


func _update_panel(player_index: int) -> void:
	if not _panels.has(player_index):
		return
	var ui: Dictionary = _panels[player_index]
	var p_data: Dictionary = PlayerManager.get_player(player_index)
	if p_data.is_empty():
		return

	var char_class: PlayerManager.CharacterClass = p_data["character_class"]

	# Name
	var name_lbl: Label = ui["name_label"]
	var profile: Dictionary = ProfileManager.get_active_profile(player_index)
	if not profile.is_empty():
		name_lbl.text = profile.get("name", "P%d" % (player_index + 1))
	else:
		name_lbl.text = "P%d" % (player_index + 1)

	# Class
	var class_lbl: Label = ui["class_label"]
	class_lbl.text = CLASS_NAMES.get(char_class, "???")

	# Class sprite icon (only update when class changes)
	if ui["current_class"] != char_class:
		ui["current_class"] = char_class
		var icon: TextureRect = ui["icon"]
		var sprite_path: String = CLASS_SPRITE_PATHS.get(char_class, "")
		if not sprite_path.is_empty():
			var sheet: Texture2D = load(sprite_path)
			if sheet:
				var atlas := AtlasTexture.new()
				atlas.atlas = sheet
				atlas.region = Rect2(0, 0, 32, 32)  # First frame
				icon.texture = atlas

	# Border color matches class
	var style: StyleBoxFlat = ui["style"]
	style.border_color = CLASS_COLORS.get(char_class, Color(0.4, 0.3, 0.2))

	# HP bar
	var hp_bar: ProgressBar = ui["hp_bar"]
	hp_bar.max_value = p_data.get("max_health", 100)
	hp_bar.value = p_data.get("health", 100)

	# Mana bar
	var mana_bar: ProgressBar = ui["mana_bar"]
	mana_bar.max_value = p_data.get("max_mana", 100)
	mana_bar.value = p_data.get("mana", 100)

	# Dead state
	if not p_data.get("is_alive", true):
		name_lbl.modulate = Color(0.5, 0.3, 0.3)
	else:
		name_lbl.modulate = Color.WHITE


func _input(event: InputEvent) -> void:
	# Ctrl+D now handled by DebugDrawer — sync debug_mode from DebugOverlay
	if event is InputEventKey and event.pressed and event.keycode == KEY_D and event.ctrl_pressed:
		# DebugDrawer handles the toggle and syncs PlayerHUD._debug_mode
		return

	# TAB cycles through enemies in debug mode
	if DebugOverlay.global_enabled and event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_debug_cycle_enemy()

	# SPACEBAR dumps selected entity skeleton JSON
	if DebugOverlay.global_enabled and event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		if is_instance_valid(debug_selected_enemy):
			dump_entity_skeleton(debug_selected_enemy, "manual")

	# I toggles debug draw on ALL enemies (no prerequisites)
	if event is InputEventKey and event.pressed and event.keycode == KEY_I:
		DebugOverlay.global_enabled = true
		_debug_mode = true
		for e in get_tree().get_nodes_in_group("enemies"):
			if "debug_draw_lite" in e:
				e.debug_draw_lite = not e.debug_draw_lite
		# Auto-select first enemy if none selected
		if not is_instance_valid(debug_selected_enemy):
			_debug_cycle_enemy()

	# SEL toggles HUD popup
	if event.is_action_pressed("debug_toggle"):
		var device_id_sel := _get_device_from_event(event)
		var pi_sel := _get_player_index_for_device(device_id_sel)
		if pi_sel >= 0:
			if _hud_popups.has(pi_sel):
				_hud_popups.erase(pi_sel)
				_remove_popup_panel(pi_sel)
			else:
				_hud_popups[pi_sel] = true
				_create_popup_panel(pi_sel)

	var device_id := _get_device_from_event(event)
	var is_title: bool = GameManager.current_state == GameManager.GameState.TITLE

	# Title-screen only: START = create profile
	if is_title and event.is_action_pressed("ps_button"):
		var pi := _get_player_index_for_device(device_id)
		if pi >= 0:
			var profile: Dictionary = ProfileManager.get_active_profile(pi)
			if profile.is_empty():
				create_profile_requested.emit(device_id)
				return

	# Don't process D-pad for class/profile while pause menu is showing
	# (pause menu handles its own D-pad navigation)
	var is_paused: bool = get_tree().paused
	if is_paused and not profile_select_mode:
		return

	# Determine if profile/class cycling is allowed
	var allow_profiles: bool = is_title or profile_select_mode
	# Class cycling: title screen or gameplay (NOT during profile select mode)
	var allow_classes: bool = is_title or (not is_paused and not profile_select_mode)

	# D-pad input
	if event is InputEventJoypadButton and event.pressed:
		var pi := _get_player_index_for_device(device_id)
		if pi < 0:
			return

		var cooldown_key := "%d_%d" % [device_id, event.button_index]
		if _cycle_cooldowns.has(cooldown_key):
			return

		# Profile cycling: title screen or profile select mode only
		if allow_profiles:
			if event.button_index == 11:  # D-pad Up
				_cycle_profile(pi, device_id, -1)
				_cycle_cooldowns[cooldown_key] = 0.3
			elif event.button_index == 12:  # D-pad Down
				_cycle_profile(pi, device_id, 1)
				_cycle_cooldowns[cooldown_key] = 0.3

		# Class cycling: title/profile-select (unlimited) or gameplay (rift-limited)
		if allow_classes:
			if event.button_index == 13:  # D-pad Left
				_cycle_class(pi, -1, is_title or profile_select_mode)
				_cycle_cooldowns[cooldown_key] = 0.2
			elif event.button_index == 14:  # D-pad Right
				_cycle_class(pi, 1, is_title or profile_select_mode)
				_cycle_cooldowns[cooldown_key] = 0.2

	# Keyboard: Q/E for class, R/F for profile
	if event is InputEventKey and event.pressed:
		var pi := _get_player_index_for_device(-1)
		if pi < 0:
			return
		if allow_classes:
			if event.keycode == KEY_Q:
				_cycle_class(pi, -1, is_title or profile_select_mode)
			elif event.keycode == KEY_E and not event.ctrl_pressed:
				_cycle_class(pi, 1, is_title or profile_select_mode)
		if allow_profiles and event.keycode == KEY_R:
			_cycle_profile(pi, -1, -1)
		elif allow_profiles and event.keycode == KEY_F:
			_cycle_profile(pi, -1, 1)


func _debug_cycle_enemy() -> void:
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	if enemies.is_empty():
		debug_selected_enemy = null
		_debug_enemy_index = -1
		return
	_debug_enemy_index = (_debug_enemy_index + 1) % enemies.size()
	debug_selected_enemy = enemies[_debug_enemy_index]
	if not is_instance_valid(debug_selected_enemy):
		debug_selected_enemy = null


func debug_select_enemy_by_index(idx: int) -> void:
	## Directly select the enemy at the given index in the enemies group.
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	if idx < 0 or idx >= enemies.size():
		debug_selected_enemy = null
		_debug_enemy_index = -1
		return
	_debug_enemy_index = idx
	debug_selected_enemy = enemies[idx]


func debug_select_entity(entity: Node2D) -> void:
	## Directly select any entity (enemy, player, dummy, etc.)
	debug_selected_enemy = entity
	# Update the enemy index if this entity is in the enemies group
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	_debug_enemy_index = enemies.find(entity)


func debug_get_selected_index() -> int:
	## Returns the 0-based index of the currently selected enemy, or -1.
	if not is_instance_valid(debug_selected_enemy):
		return -1
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	return enemies.find(debug_selected_enemy)


func _get_device_from_event(event: InputEvent) -> int:
	if event is InputEventKey:
		return -1
	return event.device


func _get_player_index_for_device(device_id: int) -> int:
	for pi in PlayerManager.players:
		if PlayerManager.players[pi]["device_id"] == device_id:
			return pi
	return -1


# -- Profile Cycling -----------------------------------------------------------

func _cycle_profile(player_index: int, device_id: int, direction: int) -> void:
	if ProfileManager.profiles.is_empty():
		return

	var current_profile: Dictionary = ProfileManager.get_active_profile(player_index)
	var current_id: String = current_profile.get("id", "")

	# Build list of available profiles (unbound + current)
	var available: Array[Dictionary] = []
	for profile in ProfileManager.profiles:
		var pid: String = profile.get("id", "")
		var is_bound := false
		for did in ProfileManager.device_profiles:
			if ProfileManager.device_profiles[did].get("id", "") == pid and did != device_id:
				is_bound = true
				break
		if not is_bound:
			available.append(profile)

	if available.is_empty():
		return

	# If no profile currently selected, pick the first available
	if current_id.is_empty():
		var new_profile: Dictionary = available[0]
		ProfileManager.bind_device_to_profile(device_id, new_profile)
		ProfileManager.assign_profile_to_player(player_index, new_profile)
		_apply_profile_preferred_class(player_index, new_profile)
		AudioManager.play("menu_select")
		return

	if available.size() <= 1:
		return

	# Find current and step
	var current_idx: int = 0
	for i in range(available.size()):
		if available[i].get("id", "") == current_id:
			current_idx = i
			break

	var new_idx: int = (current_idx + direction) % available.size()
	if new_idx < 0:
		new_idx += available.size()

	var new_profile: Dictionary = available[new_idx]
	ProfileManager.bind_device_to_profile(device_id, new_profile)
	ProfileManager.assign_profile_to_player(player_index, new_profile)
	AudioManager.play("menu_select")

	# Auto-select the profile's preferred class if available
	_apply_profile_preferred_class(player_index, new_profile)


func _apply_profile_preferred_class(player_index: int, profile: Dictionary) -> void:
	## Set the player's class to the profile's preferred class if available
	var p_data: Dictionary = PlayerManager.get_player(player_index)
	if p_data.is_empty():
		return

	# Get taken classes (by other players)
	var taken: Array[int] = []
	for pi in PlayerManager.players:
		if pi != player_index:
			taken.append(int(PlayerManager.players[pi]["character_class"]))

	# Try last_class first
	if profile.has("last_class"):
		var last: int = int(profile["last_class"])
		if last not in taken and last >= 0 and last < PlayerManager.CharacterClass.values().size():
			_set_player_class(player_index, last as PlayerManager.CharacterClass)
			return

	# Try class_preferences list
	var prefs: Array = profile.get("class_preferences", [])
	for pref in prefs:
		var cls: int = int(pref)
		if cls not in taken and cls >= 0 and cls < PlayerManager.CharacterClass.values().size():
			_set_player_class(player_index, cls as PlayerManager.CharacterClass)
			return

	# No preference found or all taken — pick random available
	var all_classes: int = PlayerManager.CharacterClass.values().size()
	for cls in range(all_classes):
		if cls not in taken:
			_set_player_class(player_index, cls as PlayerManager.CharacterClass)
			return


func _set_player_class(player_index: int, new_class: PlayerManager.CharacterClass) -> void:
	var p_data: Dictionary = PlayerManager.get_player(player_index)
	if p_data.is_empty():
		return
	p_data["character_class"] = new_class
	var stats: Dictionary = PlayerManager.CLASS_STATS[new_class]
	p_data["max_health"] = stats["max_health"]
	p_data["health"] = stats["max_health"]
	p_data["max_mana"] = stats["max_mana"]
	p_data["mana"] = stats["max_mana"]
	p_data["speed"] = stats["speed"]
	p_data["mana_regen"] = stats["mana_regen"]
	class_changed.emit(player_index, new_class)


# -- Class Cycling -------------------------------------------------------------

func _cycle_class(player_index: int, direction: int, ignore_rift: bool = false) -> void:
	if not ignore_rift:
		if class_change_locked.has(player_index):
			return
		if tentacle_lost.has(player_index):
			return
		if active_tentacle_count >= MAX_ACTIVE_TENTACLES:
			return
	var p_data: Dictionary = PlayerManager.get_player(player_index)
	if p_data.is_empty():
		return

	var current_class: PlayerManager.CharacterClass = p_data["character_class"]

	# Get classes not taken by other players (unless duplicates allowed)
	var available: Array[PlayerManager.CharacterClass] = []
	if GameManager.multiple_players_same_class:
		available.assign(ALL_CLASSES)
	else:
		var taken: Array[PlayerManager.CharacterClass] = []
		for pi in PlayerManager.players:
			if pi != player_index:
				taken.append(PlayerManager.players[pi]["character_class"])
		for c in ALL_CLASSES:
			if c not in taken:
				available.append(c)

	if available.is_empty():
		return

	var current_idx := ALL_CLASSES.find(current_class)
	var new_class := current_class

	for i in range(1, ALL_CLASSES.size() + 1):
		var check_idx := (current_idx + direction * i) % ALL_CLASSES.size()
		if check_idx < 0:
			check_idx += ALL_CLASSES.size()
		var candidate: PlayerManager.CharacterClass = ALL_CLASSES[check_idx]
		if candidate in available:
			new_class = candidate
			break

	if new_class == current_class:
		return

	AudioManager.play("menu_select")
	p_data["character_class"] = new_class
	var stats: Dictionary = PlayerManager.CLASS_STATS[new_class]
	p_data["max_health"] = stats["max_health"]
	p_data["health"] = stats["max_health"]
	p_data["max_mana"] = stats["max_mana"]
	p_data["mana"] = stats["max_mana"]
	p_data["speed"] = stats["speed"]
	p_data["mana_regen"] = stats["mana_regen"]

	# Save last class choice to profile
	var profile: Dictionary = ProfileManager.get_active_profile(player_index)
	if not profile.is_empty():
		profile["last_class"] = int(new_class)
		ProfileManager.save_profiles()

	class_changed.emit(player_index, new_class)


# -- Skeleton Dump System ------------------------------------------------------

var _dump_count: int = 0
var _last_auto_dump_time: float = 0.0
const AUTO_DUMP_COOLDOWN := 2.0  # Min seconds between auto-dumps

func dump_entity_skeleton(entity: Node2D, trigger: String = "manual") -> Dictionary:
	## Dump full skeleton/pose data as a Dictionary. Also prints JSON and saves to file.
	var data: Dictionary = {
		"trigger": trigger,
		"timestamp": Time.get_ticks_msec() / 1000.0,
		"entity_name": entity.name,
		"global_position": _v2d(entity.global_position),
		"velocity": _v2d(entity.velocity) if "velocity" in entity else [0, 0],
	}

	if "_state" in entity:
		data["state"] = entity._state
	if "_standdown" in entity:
		data["standdown"] = entity._standdown
	if "_asleep" in entity:
		data["asleep"] = entity._asleep
	if "_chained" in entity:
		data["chained"] = entity._chained
	if "_pose_locked" in entity:
		data["pose_locked"] = entity._pose_locked
	if "_physics_frozen" in entity:
		data["physics_frozen"] = entity._physics_frozen
	if "_facing" in entity:
		data["facing"] = entity._facing
	if "_want_direction" in entity:
		data["want_direction"] = entity._want_direction
	if "_move_speed" in entity:
		data["move_speed"] = entity._move_speed
	if "_target" in entity:
		if is_instance_valid(entity._target):
			data["target"] = entity._target.name
			data["target_pos"] = _v2d(entity._target.global_position)
		else:
			data["target"] = "null"

	if "_spine" in entity:
		data["spine"] = []
		for pt in entity._spine:
			data["spine"].append(_v2d(pt))

	if "_neck" in entity:
		data["neck"] = [_v2d(entity._neck[0]), _v2d(entity._neck[1])]
	if "_skull" in entity:
		data["skull"] = _v2d(entity._skull)
	if "_jaw" in entity:
		data["jaw"] = _v2d(entity._jaw)

	if "_clavicles" in entity:
		data["clavicles"] = [_v2d(entity._clavicles[0]), _v2d(entity._clavicles[1])]
	if "_hip_bones" in entity:
		data["hip_bones"] = [_v2d(entity._hip_bones[0]), _v2d(entity._hip_bones[1])]

	if "_tail" in entity:
		data["tail"] = []
		for pt in entity._tail:
			data["tail"].append(_v2d(pt))

	if "_legs" in entity:
		data["legs"] = []
		for li in range(entity._legs.size()):
			var leg_data: Dictionary = {
				"hip": _v2d(entity._legs[li][0]),
				"knee": _v2d(entity._legs[li][1]),
				"foot": _v2d(entity._legs[li][2]),
				"severed": entity._leg_severed[li] if "_leg_severed" in entity else false,
			}
			if "_foot_world" in entity:
				leg_data["foot_world"] = _v2d(entity._foot_world[li])
			if "_foot_planted" in entity:
				leg_data["planted"] = entity._foot_planted[li]
			data["legs"].append(leg_data)

	# Distances for rigidity verification
	data["distances"] = {}
	if "_spine" in entity and entity._spine.size() >= 3:
		data["distances"]["spine0_1"] = snappedf(entity._spine[0].distance_to(entity._spine[1]), 0.1)
		data["distances"]["spine1_2"] = snappedf(entity._spine[1].distance_to(entity._spine[2]), 0.1)
	if "_neck" in entity and "_spine" in entity:
		data["distances"]["spine0_neck1"] = snappedf(entity._spine[0].distance_to(entity._neck[1]), 0.1)
	if "_skull" in entity and "_neck" in entity:
		data["distances"]["neck1_skull"] = snappedf(entity._neck[1].distance_to(entity._skull), 0.1)
	if "_clavicles" in entity and "_spine" in entity:
		data["distances"]["clav_l"] = snappedf(entity._spine[0].distance_to(entity._clavicles[0]), 0.1)
		data["distances"]["clav_r"] = snappedf(entity._spine[0].distance_to(entity._clavicles[1]), 0.1)
	if "_hip_bones" in entity and "_spine" in entity:
		data["distances"]["hip_l"] = snappedf(entity._spine[2].distance_to(entity._hip_bones[0]), 0.1)
		data["distances"]["hip_r"] = snappedf(entity._spine[2].distance_to(entity._hip_bones[1]), 0.1)
	if "_legs" in entity:
		for li in range(entity._legs.size()):
			var leg: Array = entity._legs[li]
			data["distances"]["leg%d_upper" % li] = snappedf(leg[0].distance_to(leg[1]), 0.1)
			data["distances"]["leg%d_lower" % li] = snappedf(leg[1].distance_to(leg[2]), 0.1)

	if "_ik_score" in entity:
		data["ik_score"] = snappedf(entity._ik_score, 0.1)
		data["ik_peak"] = snappedf(entity._ik_score_peak, 0.1)

	if "_part_health" in entity:
		data["part_health"] = {}
		for pname in entity._part_health:
			var p: Dictionary = entity._part_health[pname]
			data["part_health"][pname] = { "hp": p["current_hp"], "max": p["max_hp"], "state": p["damage_state"] }

	var json_str: String = JSON.stringify(data, "\t")
	DebugOverlay.log("body_mechanics/spine_debug", entity,
		"=== SKELETON DUMP [%s] ===\n%s", [trigger, json_str])

	_dump_count += 1
	var path: String = "user://dumps/skeleton_%03d_%s.json" % [_dump_count, trigger]
	DirAccess.make_dir_recursive_absolute("user://dumps")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(json_str)
		file.close()
		DebugOverlay.log("body_mechanics/spine_debug", entity,
			"Saved to: %s", [path])

	return data


func check_auto_dump_triggers(entity: Node2D) -> void:
	## Call periodically to check if any auto-dump rule fires.
	## Only active when body_mechanics/spine_debug logging is enabled.
	if DebugOverlay.should_log("body_mechanics/spine_debug", entity) == DebugOverlay.TextMode.NONE:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last_auto_dump_time < AUTO_DUMP_COOLDOWN:
		return

	# Rule 1: IK score spike (> 500)
	if "_ik_score" in entity and entity._ik_score > 500:
		_last_auto_dump_time = now
		dump_entity_skeleton(entity, "ik_spike_%.0f" % entity._ik_score)
		return

	# Rule 2: Spine stretched beyond 110%
	if "_spine" in entity and entity._spine.size() >= 3:
		for i in range(1, 3):
			var dist: float = entity._spine[i].distance_to(entity._spine[i - 1])
			if dist > 28.0 * 1.1:
				_last_auto_dump_time = now
				dump_entity_skeleton(entity, "spine_stretch_%.1f" % dist)
				return

	# Rule 3: Upper limb stretched beyond 105%
	if "_legs" in entity:
		for li in range(entity._legs.size()):
			if "_leg_severed" in entity and entity._leg_severed[li]:
				continue
			var upper_dist: float = entity._legs[li][0].distance_to(entity._legs[li][1])
			if upper_dist > 24.0 * 1.05:
				_last_auto_dump_time = now
				dump_entity_skeleton(entity, "limb_stretch_leg%d_%.1f" % [li, upper_dist])
				return

	# Rule 4: Clavicle/hip bone stretched beyond 110%
	if "_clavicles" in entity and "_spine" in entity:
		for ci in range(2):
			var cdist: float = entity._spine[0].distance_to(entity._clavicles[ci])
			if cdist > 12.0 * 1.1:
				_last_auto_dump_time = now
				dump_entity_skeleton(entity, "clav_stretch_%d_%.1f" % [ci, cdist])
				return


func _v2d(v: Vector2) -> Array:
	return [snappedf(v.x, 0.1), snappedf(v.y, 0.1)]


# -- Announcement overlay (large centered text that fades out) -----------------

var _announce_label: Label = null
var _announce_timer: float = 0.0

func show_announcement(text: String, duration: float = 3.0) -> void:
	## Show large centered text on screen that fades out.
	if not _canvas:
		return
	if not _announce_label or not is_instance_valid(_announce_label):
		_announce_label = Label.new()
		_announce_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_announce_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_announce_label.add_theme_font_size_override("font_size", 28)
		_announce_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
		_announce_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
		_announce_label.add_theme_constant_override("shadow_offset_x", 2)
		_announce_label.add_theme_constant_override("shadow_offset_y", 2)
		_announce_label.anchors_preset = Control.PRESET_CENTER_TOP
		_announce_label.anchor_left = 0; _announce_label.anchor_right = 1
		_announce_label.anchor_top = 0.15; _announce_label.anchor_bottom = 0.25
		_canvas.add_child(_announce_label)
	_announce_label.text = text
	_announce_label.modulate = Color(1, 1, 1, 1)
	_announce_label.visible = true
	_announce_timer = duration


func _process_announcement(delta: float) -> void:
	if _announce_timer <= 0:
		return
	_announce_timer -= delta
	if _announce_timer <= 0:
		if _announce_label and is_instance_valid(_announce_label):
			_announce_label.visible = false
	elif _announce_timer < 1.0 and _announce_label and is_instance_valid(_announce_label):
		_announce_label.modulate.a = _announce_timer
