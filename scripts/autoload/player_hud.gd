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
	if not _panels.has(player_index):
		_create_panel(player_index)
	_update_panel(player_index)


func _on_player_left(player_index: int) -> void:
	_remove_panel(player_index)


func _process(delta: float) -> void:
	# Cooldowns
	for key in _cycle_cooldowns.keys():
		_cycle_cooldowns[key] -= delta
		if _cycle_cooldowns[key] <= 0.0:
			_cycle_cooldowns.erase(key)

	var is_title: bool = GameManager.current_state == GameManager.GameState.TITLE

	# Update muffin counter (hidden on title)
	if _muffin_label:
		if is_title:
			_muffin_label.text = ""
		else:
			var total: int = 0
			for pi in GameManager.mini_muffin_counts:
				total += GameManager.mini_muffin_counts[pi]
			_muffin_label.text = "Muffins: %d" % total

	# Update all panels
	for pi in _panels.keys():
		_update_panel(pi)

	# Show hints / tentacle status
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


func _update_debug_labels() -> void:
	if not _debug_mode:
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
	# Debug toggle
	if event.is_action_pressed("debug_toggle"):
		_debug_mode = not _debug_mode

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

	# D-pad input
	if event is InputEventJoypadButton and event.pressed:
		var pi := _get_player_index_for_device(device_id)
		if pi < 0:
			return

		var cooldown_key := "%d_%d" % [device_id, event.button_index]
		if _cycle_cooldowns.has(cooldown_key):
			return

		# Profile cycling: title screen only
		if is_title:
			if event.button_index == 11:  # D-pad Up
				_cycle_profile(pi, device_id, -1)
				_cycle_cooldowns[cooldown_key] = 0.3
			elif event.button_index == 12:  # D-pad Down
				_cycle_profile(pi, device_id, 1)
				_cycle_cooldowns[cooldown_key] = 0.3

		# Class cycling: ANY time
		if event.button_index == 13:  # D-pad Left
			_cycle_class(pi, -1)
			_cycle_cooldowns[cooldown_key] = 0.2
		elif event.button_index == 14:  # D-pad Right
			_cycle_class(pi, 1)
			_cycle_cooldowns[cooldown_key] = 0.2

	# Keyboard: Q/E for class (always), R/F for profile (title only)
	if event is InputEventKey and event.pressed:
		var pi := _get_player_index_for_device(-1)
		if pi < 0:
			return
		if event.keycode == KEY_Q:
			_cycle_class(pi, -1)
		elif event.keycode == KEY_E:
			_cycle_class(pi, 1)
		elif is_title and event.keycode == KEY_R:
			_cycle_profile(pi, -1, -1)
		elif is_title and event.keycode == KEY_F:
			_cycle_profile(pi, -1, 1)


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


# -- Class Cycling -------------------------------------------------------------

func _cycle_class(player_index: int, direction: int) -> void:
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

	# Get classes not taken by other players
	var taken: Array[PlayerManager.CharacterClass] = []
	for pi in PlayerManager.players:
		if pi != player_index:
			taken.append(PlayerManager.players[pi]["character_class"])

	var available: Array[PlayerManager.CharacterClass] = []
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
