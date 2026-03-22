extends CanvasLayer

## Level editor overlay — toggled with Ctrl+E.
## Modes: spawn areas, seeds, platforms, portal.
## Mouse-driven vertex editing, saves to user://levels/.

enum Mode { SPAWN_AREAS, SPAWN_POSITIONS, SEEDS, PLATFORMS, PORTAL, MIGRATION, SPLAY, SPLAY_EDIT }

const MODE_NAMES := ["Spawn Areas", "Spawn Positions", "Seeds", "Platforms", "Portal", "Migration", "Splay", "Splay Edit"]
const MODE_COLORS := [
	Color(1.0, 0.9, 0.2, 0.3),   # Spawn areas: yellow
	Color(0.2, 0.9, 0.5, 0.3),   # Seeds: green
	Color(0.4, 0.6, 1.0, 0.3),   # Platforms: blue
	Color(0.9, 0.3, 0.9, 0.3),   # Portal: purple
]

signal config_changed(data: Dictionary)

var _active := false
var _mode: Mode = Mode.SPAWN_AREAS
var _level_name: String = ""
var _config: Dictionary = {}
var _selected_idx: int = -1
var _dragging := false
var _drag_handle: int = -1  # Which corner/handle is being dragged
var _drag_item_type: String = ""
var _nav_cooldown: float = 0.0
var _migration_pattern_idx: int = 0  # Which pattern is selected
var _migration_phase_idx: int = 0    # Which phase within that pattern

# -- Change tracking --
var _changed: Dictionary = {}        # component_name -> bool (has unsaved changes)
var _changed_items: Dictionary = {}  # component_name -> Array[int] (changed item indices)
var _level_save_dialog_active: bool = false  # True when showing O/C save dialog for level

# UI nodes
var _panel: PanelContainer
var _mode_label: Label
var _info_label: Label
var _status_label: Label
var _overlay: Node2D  # For drawing zones/handles in world space


func setup(level_name: String, config: Dictionary) -> void:
	_level_name = level_name
	_config = config.duplicate(true)  # Deep copy so edits don't affect live config until save


func toggle() -> void:
	_active = not _active
	visible = _active
	if _overlay:
		_overlay.visible = _active
	if _active:
		_update_display()


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()
	_build_overlay()


func _build_ui() -> void:
	# Semi-transparent top bar
	var top_bar := ColorRect.new()
	top_bar.color = Color(0.05, 0.05, 0.1, 0.85)
	top_bar.anchor_right = 1.0
	top_bar.offset_bottom = 40
	add_child(top_bar)

	# Mode label (left)
	_mode_label = Label.new()
	_mode_label.text = "MODE: Spawn Areas"
	_mode_label.add_theme_font_size_override("font_size", 16)
	_mode_label.modulate = Color(1.0, 0.9, 0.3)
	_mode_label.offset_left = 10
	_mode_label.offset_top = 8
	_mode_label.offset_right = 300
	_mode_label.offset_bottom = 35
	add_child(_mode_label)

	# Info label (center)
	_info_label = Label.new()
	_info_label.text = "Tab: switch mode | Click: select/drag | S: save | R: reset"
	_info_label.add_theme_font_size_override("font_size", 12)
	_info_label.modulate = Color(0.6, 0.6, 0.6)
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.anchor_left = 0.3
	_info_label.anchor_right = 0.7
	_info_label.offset_top = 10
	_info_label.offset_bottom = 35
	add_child(_info_label)

	# Status label (right)
	_status_label = Label.new()
	_status_label.text = "EDITOR"
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.modulate = Color(0.3, 0.8, 0.3)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_label.anchor_left = 0.85
	_status_label.anchor_right = 1.0
	_status_label.offset_left = -10
	_status_label.offset_top = 10
	_status_label.offset_right = -10
	_status_label.offset_bottom = 35
	add_child(_status_label)


func _build_overlay() -> void:
	# World-space overlay for drawing zones, handles, etc.
	# Added to the parent scene (not this CanvasLayer) so it's in world space
	_overlay = Node2D.new()
	_overlay.z_index = 50
	_overlay.visible = false
	# Deferred add to parent scene
	call_deferred("_add_overlay_to_scene")


func _add_overlay_to_scene() -> void:
	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(_overlay)
		_overlay.draw.connect(_draw_overlay)


func _process(delta: float) -> void:
	if not _active:
		return
	if _nav_cooldown > 0.0:
		_nav_cooldown -= delta
	if _overlay:
		_overlay.queue_redraw()


func _input(event: InputEvent) -> void:
	if not _active:
		return

	# ESC closes editor (unless in SPLAY_EDIT which handles its own ESC)
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _mode != Mode.SPLAY_EDIT:
			toggle()
			get_viewport().set_input_as_handled()
			return

	# Tab to switch modes
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_TAB:
			_mode = ((_mode + 1) % Mode.size()) as Mode
			_selected_idx = -1
			_update_display()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_S and event.ctrl_pressed and _mode != Mode.SPLAY_EDIT:
			if Version.is_source_mode():
				_level_save_dialog_active = true
			else:
				_save()  # Non-source: always save custom
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_R and event.ctrl_pressed:
			_reset()
			get_viewport().set_input_as_handled()
		elif _mode == Mode.MIGRATION:
			# Number keys 1-9 switch phase within current pattern
			var key_num: int = event.keycode - KEY_0
			if key_num >= 1 and key_num <= 9:
				var patterns: Array = _config.get("migration_patterns", [])
				if _migration_pattern_idx < patterns.size():
					var phases: Array = patterns[_migration_pattern_idx].get("phases", [])
					if key_num - 1 < phases.size():
						_migration_phase_idx = key_num - 1
						_selected_idx = -1
						_update_display()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_N:
				_migration_add_phase()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
				_migration_delete_last_phase()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_EQUAL or event.keycode == KEY_KP_ADD:  # + key
				_migration_add_zone()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_S and not event.ctrl_pressed:
				_migration_cycle_species()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_G:
				_migration_toggle_stagger()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_LEFT:
				_migration_adjust_cadence(-1.0)
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_RIGHT:
				_migration_adjust_cadence(1.0)
				get_viewport().set_input_as_handled()
		elif _mode == Mode.SPLAY:
			if event.keycode == KEY_N:
				_splay_add_instance()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
				_splay_delete_selected()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_LEFT:
				_splay_adjust_rotation(-15.0)
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_RIGHT:
				_splay_adjust_rotation(15.0)
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_UP:
				_splay_cycle_pose(1)
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_DOWN:
				_splay_cycle_pose(-1)
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_B:
				_splay_cycle_behavior()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_QUOTELEFT:  # Backtick ` — toggle physics preview
				_splay_toggle_physics_preview()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_ESCAPE and _splay_physics_preview:
				_splay_cancel_physics_preview()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_P:
				_splay_open_library()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_E:
				# Enter pose edit mode — uses existing monster or spawns one
				_splay_edit_pose_idx = _selected_idx
				_mode = Mode.SPLAY_EDIT
				_selected_idx = -1
				_enter_splay_edit()
				_update_display()
				get_viewport().set_input_as_handled()
		elif _mode == Mode.SPLAY_EDIT:
			if event.keycode == KEY_ESCAPE:
				_exit_splay_edit()
				_mode = Mode.SPLAY
				_selected_idx = _splay_edit_pose_idx
				_splay_edit_pose_idx = -1
				# Rebuild level to re-spawn all splay creatures
				config_changed.emit(_config)
				_update_display()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_SPACE and event.shift_pressed:
				# Shift+SPACE: dump skeleton to logs
				if is_instance_valid(_splay_edit_creature):
					PlayerHUD.dump_entity_skeleton(_splay_edit_creature, "splay_edit")
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_SPACE:
				_splay_edit_toggle_point()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_UP:
				_splay_edit_move_endpoint(Vector2(0, -1))
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_DOWN:
				_splay_edit_move_endpoint(Vector2(0, 1))
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_LEFT:
				_splay_edit_move_endpoint(Vector2(-1, 0))
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_RIGHT:
				_splay_edit_move_endpoint(Vector2(1, 0))
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_S and event.ctrl_pressed:
				_splay_save_dialog_active = true
				get_viewport().set_input_as_handled()
			elif _splay_save_dialog_active and event.keycode == KEY_O:
				_splay_save_dialog_active = false
				if Version.is_source_mode():
					_splay_edit_save_pose_original()
				get_viewport().set_input_as_handled()
			elif _splay_save_dialog_active and event.keycode == KEY_C:
				_splay_save_dialog_active = false
				_splay_edit_save_pose_custom()
				get_viewport().set_input_as_handled()
			elif _splay_save_dialog_active and event.keycode == KEY_ESCAPE:
				_splay_save_dialog_active = false
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_L:
				_splay_edit_preset_pose("left")
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_R:
				_splay_edit_preset_pose("right")
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_U:
				_splay_edit_preset_pose("up")
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_D and not event.ctrl_pressed:
				_splay_edit_preset_pose("down")
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_P:
				_splay_edit_toggle_pin()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_M:
				_splay_edit_mirror = not _splay_edit_mirror
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_C:
				_splay_edit_cycle_link_type()
				get_viewport().set_input_as_handled()

	# Level save dialog keyboard handling
	if _level_save_dialog_active and event is InputEventKey and event.pressed:
		if event.keycode == KEY_O and Version.is_source_mode():
			_level_save_dialog_active = false
			_save_original()
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_C:
			_level_save_dialog_active = false
			_save()
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_ESCAPE:
			_level_save_dialog_active = false
			get_viewport().set_input_as_handled()
			return

	# Level save dialog click handling
	if _level_save_dialog_active and event is InputEventMouseButton and event.pressed:
		var vp2: Vector2 = get_viewport().get_visible_rect().size
		var ldx: float = vp2.x / 2.0 - 160
		var ldy: float = vp2.y / 2.0 - 40
		var lmpos: Vector2 = event.position
		if Rect2(ldx + 20, ldy + 40, 120, 28).has_point(lmpos) and Version.is_source_mode():
			_level_save_dialog_active = false
			_save_original()
		elif Rect2(ldx + 180, ldy + 40, 120, 28).has_point(lmpos):
			_level_save_dialog_active = false
			_save()
		else:
			_level_save_dialog_active = false
		get_viewport().set_input_as_handled()
		return

	# Splay pose save dialog click handling — intercept ALL mouse clicks when dialog is active
	if _splay_save_dialog_active and event is InputEventMouseButton and event.pressed:
		var vp: Vector2 = get_viewport().get_visible_rect().size
		var dx: float = vp.x / 2.0 - 160
		var dy: float = vp.y / 2.0 - 40
		var mpos: Vector2 = event.position
		# Original button (left side)
		var orig_rect := Rect2(dx + 20, dy + 40, 120, 28)
		# Custom button (right side)
		var custom_rect := Rect2(dx + 180, dy + 40, 120, 28)
		if orig_rect.has_point(mpos) and Version.is_source_mode():
			_splay_save_dialog_active = false
			_splay_edit_save_pose_original()
		elif custom_rect.has_point(mpos):
			_splay_save_dialog_active = false
			_splay_edit_save_pose_custom()
		else:
			# Click outside dialog — cancel
			_splay_save_dialog_active = false
		get_viewport().set_input_as_handled()
		return

	# Mouse input for dragging
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_start_drag(event.position)
			else:
				_stop_drag()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and _mode == Mode.SPLAY_EDIT:
			if event.pressed:
				_splay_edit_dragging_endpoint = true
				_try_select_splay_connection(_get_world_pos(event.position))
			else:
				_splay_edit_dragging_endpoint = false
			get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion:
		if _dragging:
			_do_drag(event.position)
			get_viewport().set_input_as_handled()
		elif _splay_edit_dragging_endpoint and _mode == Mode.SPLAY_EDIT and _splay_edit_selected_point != "":
			_drag_splay_connection(_get_world_pos(event.position))
			get_viewport().set_input_as_handled()


func _update_display() -> void:
	if _mode == Mode.MIGRATION:
		var patterns: Array = _config.get("migration_patterns", [])
		if _migration_pattern_idx < patterns.size():
			var p: Dictionary = patterns[_migration_pattern_idx]
			var n_phases: int = p.get("phases", []).size()
			var species_str: String = str(p.get("species", "fireflies"))
			var cadence_val: float = p.get("cadence", 30.0)
			var stagger_str: String = " STAGGER" if p.get("stagger", false) else ""
			_mode_label.text = "Migration [%s] %ds%s  Phase %d/%d  1-9:phase N/Del S:species +:zone </>:cadence G:stagger" % [species_str, int(cadence_val), stagger_str, _migration_phase_idx + 1, n_phases]
		else:
			_mode_label.text = "MODE: Migration (no patterns)"
	else:
		_mode_label.text = "MODE: " + MODE_NAMES[_mode]


func _get_world_pos(screen_pos: Vector2) -> Vector2:
	var cam := get_viewport().get_camera_2d()
	if not cam:
		return screen_pos
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var zoom: Vector2 = cam.zoom if cam.zoom.x > 0 else Vector2.ONE
	return (screen_pos - vp_size / 2.0) / zoom + cam.global_position


func _start_drag(screen_pos: Vector2) -> void:
	var world_pos: Vector2 = _get_world_pos(screen_pos)
	_selected_idx = -1
	_dragging = false

	match _mode:
		Mode.SPAWN_AREAS:
			_try_select_zone(world_pos)
		Mode.SPAWN_POSITIONS:
			_try_select_spawn_pos(world_pos)
		Mode.SEEDS:
			_try_select_scenery(world_pos)
		Mode.PLATFORMS:
			_try_select_platform(world_pos)
		Mode.PORTAL:
			_try_select_portal(world_pos)
		Mode.MIGRATION:
			_try_select_migration(world_pos)
		Mode.SPLAY:
			_try_select_splay(world_pos)
		Mode.SPLAY_EDIT:
			_try_select_splay_connection(world_pos)


var _drag_moved: bool = false  # True if mouse actually moved during a drag

func _stop_drag() -> void:
	if _dragging and _drag_moved:
		# Live refresh on drag release — skip for SPLAY modes (handled separately)
		if _mode != Mode.SPLAY_EDIT and _mode != Mode.SPLAY:
			config_changed.emit(_config)
	_dragging = false
	_drag_moved = false
	_drag_handle = -1
	_splay_edit_dragging_endpoint = false
	_splay_edit_rotating = false


func _do_drag(screen_pos: Vector2) -> void:
	_drag_moved = true
	var world_pos: Vector2 = _get_world_pos(screen_pos)

	match _mode:
		Mode.SPAWN_AREAS:
			_drag_zone(world_pos)
		Mode.SPAWN_POSITIONS:
			_drag_spawn_pos(world_pos)
		Mode.SEEDS:
			_drag_scenery(world_pos)
		Mode.PLATFORMS:
			_drag_platform(world_pos)
		Mode.PORTAL:
			_drag_portal(world_pos)
		Mode.MIGRATION:
			_drag_migration(world_pos)
		Mode.SPLAY:
			_drag_splay(world_pos)
		Mode.SPLAY_EDIT:
			_drag_splay_connection(world_pos)


# -- Spawn Area editing --------------------------------------------------------

func _try_select_zone(world_pos: Vector2) -> void:
	# Check all zone types: fireflies, bats, and spawn positions
	var zone_types := ["fireflies", "bats"]
	for zone_type in zone_types:
		var zones: Array = _config.get("spawn_zones", {}).get(zone_type, [])
		for i in range(zones.size()):
			var r: Array = zones[i].get("rect", [0, 0, 100, 100])
			var rect := Rect2(r[0], r[1], r[2], r[3])
			var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
			for ci in range(4):
				if world_pos.distance_to(corners[ci]) < 15.0:
					_selected_idx = i
					_drag_handle = ci
					_drag_item_type = zone_type + "_zone"
					_dragging = true
					return
			if rect.has_point(world_pos):
				_selected_idx = i
				_drag_item_type = zone_type + "_zone"
				_drag_handle = -1
				_dragging = true
				return



func _try_select_spawn_pos(world_pos: Vector2) -> void:
	var spawn_pos: Array = _config.get("spawn_positions", [])
	for i in range(spawn_pos.size()):
		var p: Array = spawn_pos[i]
		if world_pos.distance_to(Vector2(p[0], p[1])) < 15.0:
			_selected_idx = i
			_drag_item_type = "spawn_position"
			_dragging = true
			return


func _drag_spawn_pos(world_pos: Vector2) -> void:
	var spawn_pos: Array = _config.get("spawn_positions", [])
	if _selected_idx >= 0 and _selected_idx < spawn_pos.size():
		spawn_pos[_selected_idx] = [world_pos.x, world_pos.y]


func _drag_zone(world_pos: Vector2) -> void:
	# Handle zone rects (fireflies_zone, bats_zone)
	var zone_key: String = _drag_item_type.replace("_zone", "")
	var zones: Array = _config.get("spawn_zones", {}).get(zone_key, [])
	if _selected_idx < 0 or _selected_idx >= zones.size():
		return
	var r: Array = zones[_selected_idx]["rect"]
	if _drag_handle >= 0:
		match _drag_handle:
			0:  # Top-left
				var dx: float = world_pos.x - r[0]
				var dy: float = world_pos.y - r[1]
				r[0] = world_pos.x
				r[1] = world_pos.y
				r[2] -= dx
				r[3] -= dy
			1:  # Top-right
				r[2] = world_pos.x - r[0]
				var dy: float = world_pos.y - r[1]
				r[1] = world_pos.y
				r[3] -= dy
			2:  # Bottom-right
				r[2] = world_pos.x - r[0]
				r[3] = world_pos.y - r[1]
			3:  # Bottom-left
				var dx: float = world_pos.x - r[0]
				r[0] = world_pos.x
				r[2] -= dx
				r[3] = world_pos.y - r[1]


# -- Scenery editing -----------------------------------------------------------

func _try_select_scenery(world_pos: Vector2) -> void:
	var trees: Array = _config.get("scenery", {}).get("trees", [])
	for i in range(trees.size()):
		var p: Array = trees[i].get("pos", [0, 0])
		if world_pos.distance_to(Vector2(p[0], p[1])) < 30.0:
			_selected_idx = i
			_drag_item_type = "tree"
			_dragging = true
			return
	var rocks: Array = _config.get("scenery", {}).get("rocks", [])
	for i in range(rocks.size()):
		var p: Array = rocks[i].get("pos", [0, 0])
		if world_pos.distance_to(Vector2(p[0], p[1])) < 30.0:
			_selected_idx = i
			_drag_item_type = "rock"
			_dragging = true
			return


func _drag_scenery(world_pos: Vector2) -> void:
	if _selected_idx < 0:
		return
	var items: Array
	if _drag_item_type == "tree":
		items = _config.get("scenery", {}).get("trees", [])
	else:
		items = _config.get("scenery", {}).get("rocks", [])
	if _selected_idx < items.size():
		items[_selected_idx]["pos"] = [world_pos.x, world_pos.y]


# -- Platform editing ----------------------------------------------------------

func _try_select_platform(world_pos: Vector2) -> void:
	var platforms: Array = _config.get("platforms", [])
	for i in range(platforms.size()):
		var p: Array = platforms[i].get("pos", [0, 0])
		var w: float = platforms[i].get("width", 200)
		var rect := Rect2(p[0] - w / 2.0, p[1] - 10, w, 20)
		if rect.has_point(world_pos):
			_selected_idx = i
			_drag_item_type = "platform"
			_dragging = true
			return


func _drag_platform(world_pos: Vector2) -> void:
	if _selected_idx < 0:
		return
	var platforms: Array = _config.get("platforms", [])
	if _selected_idx < platforms.size():
		platforms[_selected_idx]["pos"] = [world_pos.x, world_pos.y]


# -- Portal editing ------------------------------------------------------------

func _try_select_portal(world_pos: Vector2) -> void:
	var portal: Dictionary = _config.get("portal", {})
	var p: Array = portal.get("pos", [960, 880])
	if world_pos.distance_to(Vector2(p[0], p[1])) < 40.0:
		_selected_idx = 0
		_drag_item_type = "portal"
		_dragging = true


func _drag_portal(world_pos: Vector2) -> void:
	_config["portal"]["pos"] = [world_pos.x, world_pos.y]


# -- Migration editing ---------------------------------------------------------

func _get_migration_zones_for_phase() -> Array:
	var patterns: Array = _config.get("migration_patterns", [])
	if _migration_pattern_idx >= patterns.size():
		return []
	var phases: Array = patterns[_migration_pattern_idx].get("phases", [])
	if _migration_phase_idx >= phases.size():
		return []
	return phases[_migration_phase_idx].get("zones", [])


func _try_select_migration(world_pos: Vector2) -> void:
	var zones: Array = _get_migration_zones_for_phase()
	for i in range(zones.size()):
		var p: Array = zones[i].get("point", [0, 0])
		var pos := Vector2(p[0], p[1])
		var radius: float = zones[i].get("radius", 100.0)
		# Check X delete button (top-right of circle)
		var x_pos := pos + Vector2(radius * 0.7, -radius * 0.7)
		if world_pos.distance_to(x_pos) < 12.0:
			zones.remove_at(i)
			_selected_idx = -1
			_update_display()
			config_changed.emit(_config)
			return
		# Check radius handle (on the right edge of the circle)
		var radius_handle := pos + Vector2(radius, 0)
		if world_pos.distance_to(radius_handle) < 15.0:
			_selected_idx = i
			_drag_item_type = "migration_radius"
			_dragging = true
			return
		# Check center
		if world_pos.distance_to(pos) < maxf(radius, 15.0):
			_selected_idx = i
			_drag_item_type = "migration_center"
			_dragging = true
			return


func _drag_migration(world_pos: Vector2) -> void:
	var zones: Array = _get_migration_zones_for_phase()
	if _selected_idx < 0 or _selected_idx >= zones.size():
		return
	if _drag_item_type == "migration_center":
		zones[_selected_idx]["point"] = [world_pos.x, world_pos.y]
	elif _drag_item_type == "migration_radius":
		var p: Array = zones[_selected_idx]["point"]
		var center := Vector2(p[0], p[1])
		zones[_selected_idx]["radius"] = maxf(20.0, world_pos.distance_to(center))


func _migration_next_zone_id() -> int:
	## Find the highest zone_id across all phases and return +1.
	var patterns: Array = _config.get("migration_patterns", [])
	var max_id: int = 0
	for pattern in patterns:
		for phase in pattern.get("phases", []):
			for zone in phase.get("zones", []):
				max_id = maxi(max_id, int(zone.get("zone_id", 0)))
	return max_id + 1


func _migration_add_phase() -> void:
	## INSERT: add a new phase at the end with one default zone.
	var patterns: Array = _config.get("migration_patterns", [])
	if _migration_pattern_idx >= patterns.size():
		return
	var phases: Array = patterns[_migration_pattern_idx].get("phases", [])
	var new_zone_id: int = _migration_next_zone_id()
	phases.append({"zones": [{"zone_id": new_zone_id, "point": [960, 500], "radius": 120, "strength": 2.0}]})
	_migration_phase_idx = phases.size() - 1
	_selected_idx = -1
	_update_display()
	config_changed.emit(_config)


func _migration_delete_last_phase() -> void:
	## DELETE: remove the last phase.
	var patterns: Array = _config.get("migration_patterns", [])
	if _migration_pattern_idx >= patterns.size():
		return
	var phases: Array = patterns[_migration_pattern_idx].get("phases", [])
	if phases.size() <= 1:
		return  # Don't delete the only phase
	phases.pop_back()
	_migration_phase_idx = mini(_migration_phase_idx, phases.size() - 1)
	_selected_idx = -1
	_update_display()
	config_changed.emit(_config)


func _migration_cycle_species() -> void:
	## S: switch to the next migration pattern (each pattern = one species).
	var patterns: Array = _config.get("migration_patterns", [])
	if patterns.size() <= 1:
		return
	_migration_pattern_idx = (_migration_pattern_idx + 1) % patterns.size()
	_migration_phase_idx = 0
	_selected_idx = -1
	_update_display()


func _migration_toggle_stagger() -> void:
	## G: toggle stagger (random phase offset per individual).
	var patterns: Array = _config.get("migration_patterns", [])
	if _migration_pattern_idx >= patterns.size():
		return
	var pattern: Dictionary = patterns[_migration_pattern_idx]
	pattern["stagger"] = not pattern.get("stagger", false)
	_update_display()
	config_changed.emit(_config)


func _migration_adjust_cadence(delta: float) -> void:
	## Left/Right arrows: adjust cadence by delta seconds (min 5s).
	var patterns: Array = _config.get("migration_patterns", [])
	if _migration_pattern_idx >= patterns.size():
		return
	var pattern: Dictionary = patterns[_migration_pattern_idx]
	pattern["cadence"] = maxf(1.0, pattern.get("cadence", 30.0) + delta)
	_update_display()
	config_changed.emit(_config)


func _migration_add_zone() -> void:
	## +: add a new zone to the current phase.
	var zones: Array = _get_migration_zones_for_phase()
	var new_zone_id: int = _migration_next_zone_id()
	# Place near center of screen, offset slightly from existing zones
	var offset_x: float = zones.size() * 80.0
	zones.append({"zone_id": new_zone_id, "point": [960 + offset_x, 500], "radius": 100, "strength": 2.0})
	_selected_idx = zones.size() - 1
	_update_display()
	config_changed.emit(_config)


# -- Save / Reset --------------------------------------------------------------

func _save() -> void:
	## Save level to user:// (custom save)
	LevelConfig.save_level(_level_name, _config)
	config_changed.emit(_config)
	_clear_all_changes()
	_status_label.text = "CUSTOM SAVED!"
	_status_label.modulate = Color(0.3, 1.0, 0.3)
	_show_center_flash("CUSTOM SAVED", Color(0.3, 1.0, 0.3))
	var tween := create_tween()
	tween.tween_interval(1.5)
	tween.tween_callback(func() -> void:
		_status_label.text = "EDITOR"
		_status_label.modulate = Color(0.3, 0.8, 0.3)
	)


func _save_original() -> void:
	## Save level to res:// (source authority) and delete custom if it exists.
	if not Version.is_source_mode():
		return
	var path: String = "res://levels/" + _level_name + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_config, "\t"))
		file.close()
	# Delete custom override since original is now up-to-date
	var custom_path: String = "user://levels/" + _level_name + ".json"
	if FileAccess.file_exists(custom_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(custom_path))
	config_changed.emit(_config)
	_clear_all_changes()
	_status_label.text = "ORIGINAL SAVED!"
	_status_label.modulate = Color(0.3, 0.8, 1.0)
	_show_center_flash("ORIGINAL SAVED", Color(0.3, 0.8, 1.0))
	var tween := create_tween()
	tween.tween_interval(1.5)
	tween.tween_callback(func() -> void:
		_status_label.text = "EDITOR"
		_status_label.modulate = Color(0.3, 0.8, 0.3)
	)


func _reset() -> void:
	LevelConfig.reset_level(_level_name)
	_config = LevelConfig.load_level(_level_name).duplicate(true)
	config_changed.emit(_config)
	_status_label.text = "RESET!"
	_status_label.modulate = Color(1.0, 0.5, 0.3)
	_show_center_flash("RESET", Color(1.0, 0.5, 0.3))
	var tween := create_tween()
	tween.tween_interval(1.5)
	tween.tween_callback(func() -> void:
		_status_label.text = "EDITOR"
		_status_label.modulate = Color(0.3, 0.8, 0.3)
	)


func _show_center_flash(text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 64)
	lbl.modulate = color
	lbl.anchors_preset = Control.PRESET_CENTER
	lbl.anchor_left = 0.5
	lbl.anchor_right = 0.5
	lbl.anchor_top = 0.5
	lbl.anchor_bottom = 0.5
	lbl.offset_left = -200
	lbl.offset_right = 200
	lbl.offset_top = -40
	lbl.offset_bottom = 40
	add_child(lbl)

	var tween := lbl.create_tween()
	tween.tween_interval(1.0)  # Hold for 1 second
	tween.tween_property(lbl, "modulate:a", 0.0, 0.5)  # Fade out over 0.5s
	tween.tween_callback(lbl.queue_free)


# -- Overlay drawing -----------------------------------------------------------

func _draw_overlay() -> void:
	if not _active or not _overlay:
		return

	match _mode:
		Mode.SPAWN_AREAS:
			_draw_spawn_zones()
		Mode.SPAWN_POSITIONS:
			_draw_spawn_positions()
		Mode.SEEDS:
			_draw_seed_markers()
		Mode.PLATFORMS:
			_draw_platform_outlines()
		Mode.PORTAL:
			_draw_portal_overlay()
		Mode.MIGRATION:
			_draw_migration_overlay()
		Mode.SPLAY:
			_draw_splay_overlay()
		Mode.SPLAY_EDIT:
			_draw_splay_edit_overlay()

	# -- Common overlay: change summary + save dialogs --
	_draw_change_summary()
	if _level_save_dialog_active:
		_draw_level_save_dialog()


func _draw_change_summary() -> void:
	## Draw change count summary and custom/original status at top-right.
	var font: Font = ThemeDB.fallback_font
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var rx: float = vp.x - 10  # Right-aligned
	var y: float = 55.0

	# Change summary: list non-zero changes
	var change_parts: Array[String] = []
	for key in _changed:
		if _changed[key]:
			var count: int = _changed_items[key].size() if _changed_items.has(key) else 1
			change_parts.append("%d %s" % [count, key])

	if not change_parts.is_empty():
		var summary: String = ", ".join(change_parts) + " changed"
		_overlay.draw_string(font, Vector2(rx - 300, y), summary, HORIZONTAL_ALIGNMENT_RIGHT, 300, 10, Color(1.0, 0.9, 0.3, 0.8))
		y += 14

	# Custom/Original status (source mode only)
	if Version.is_source_mode():
		if _has_custom_level():
			var total: int = _get_total_change_count()
			var status_text: String
			if total > 0:
				status_text = "(CUSTOM - %d unsaved changes)" % total
			else:
				status_text = "(CUSTOM - saved)"
			_overlay.draw_string(font, Vector2(rx - 300, y), status_text, HORIZONTAL_ALIGNMENT_RIGHT, 300, 10, Color(1.0, 0.6, 0.3, 0.8))
		else:
			_overlay.draw_string(font, Vector2(rx - 300, y), "(ORIGINAL)", HORIZONTAL_ALIGNMENT_RIGHT, 300, 10, Color(0.3, 0.8, 1.0, 0.6))


func _draw_level_save_dialog() -> void:
	## Draw the O/C save dialog for level saving (same style as pose save).
	var font: Font = ThemeDB.fallback_font
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var dx: float = vp.x / 2.0 - 160
	var dy: float = vp.y / 2.0 - 40
	_overlay.draw_rect(Rect2(dx, dy, 320, 80), Color(0.1, 0.1, 0.12, 0.95))
	_overlay.draw_rect(Rect2(dx, dy, 320, 80), Color(0.5, 0.5, 0.3, 0.7), false, 2.0)
	_overlay.draw_string(font, Vector2(dx + 20, dy + 24), "Save Level: %s" % _level_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.9, 0.3))

	# Original button
	var o_col := Color(0.3, 0.8, 1.0)
	_overlay.draw_rect(Rect2(dx + 20, dy + 40, 120, 28), o_col * Color(1, 1, 1, 0.2))
	_overlay.draw_rect(Rect2(dx + 20, dy + 40, 120, 28), o_col, false, 1.5)
	_overlay.draw_string(font, Vector2(dx + 35, dy + 60), "O", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, o_col)
	_overlay.draw_line(Vector2(dx + 35, dy + 62), Vector2(dx + 45, dy + 62), o_col, 1.5)
	_overlay.draw_string(font, Vector2(dx + 46, dy + 60), "riginal", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, o_col)

	# Custom button
	var c_col := Color(0.3, 1.0, 0.3)
	_overlay.draw_rect(Rect2(dx + 180, dy + 40, 120, 28), c_col * Color(1, 1, 1, 0.2))
	_overlay.draw_rect(Rect2(dx + 180, dy + 40, 120, 28), c_col, false, 1.5)
	_overlay.draw_string(font, Vector2(dx + 200, dy + 60), "C", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, c_col)
	_overlay.draw_line(Vector2(dx + 200, dy + 62), Vector2(dx + 210, dy + 62), c_col, 1.5)
	_overlay.draw_string(font, Vector2(dx + 211, dy + 60), "ustom", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, c_col)


func _draw_spawn_zones() -> void:
	# Draw all zone types with labels and draggable corners
	var zone_configs := [
		{"key": "fireflies", "color": Color(1.0, 0.9, 0.2), "label": "FF"},
		{"key": "bats", "color": Color(0.7, 0.2, 0.9), "label": "BAT"},
	]
	for zcfg in zone_configs:
		var zones: Array = _config.get("spawn_zones", {}).get(zcfg["key"], [])
		var base_col: Color = zcfg["color"]
		for i in range(zones.size()):
			var r: Array = zones[i].get("rect", [0, 0, 100, 100])
			var rect := Rect2(r[0], r[1], r[2], r[3])
			var is_selected: bool = (_drag_item_type == zcfg["key"] + "_zone" and _selected_idx == i)
			var fill_alpha: float = 0.25 if is_selected else 0.1
			_overlay.draw_rect(rect, base_col * Color(1, 1, 1, fill_alpha))
			_overlay.draw_rect(rect, base_col * Color(1, 1, 1, 0.6), false, 1.5 if not is_selected else 2.5)
			# Corner handles
			var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
			for c in corners:
				_overlay.draw_rect(Rect2(c - Vector2(4, 4), Vector2(8, 8)), base_col * Color(1, 1, 1, 0.8))
			# Label with type and weight/count
			var label_text: String = zcfg["label"]
			if zones[i].has("weight"):
				label_text += " w:%.1f" % zones[i]["weight"]
			if zones[i].has("max_count"):
				label_text += " max:%d" % int(zones[i]["max_count"])
			_overlay.draw_string(ThemeDB.fallback_font, rect.position + Vector2(4, 14), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, base_col)



func _draw_spawn_positions() -> void:
	var spawn_pos: Array = _config.get("spawn_positions", [])
	for i in range(spawn_pos.size()):
		var p: Array = spawn_pos[i]
		var pos := Vector2(p[0], p[1])
		var is_selected: bool = (_drag_item_type == "spawn_position" and _selected_idx == i)
		var col := Color(0.2, 0.9, 1.0, 0.9) if is_selected else Color(0.2, 0.9, 1.0, 0.6)
		_overlay.draw_circle(pos, 10.0 if is_selected else 7.0, col)
		_overlay.draw_string(ThemeDB.fallback_font, pos + Vector2(-8, -14), "P%d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
		# Crosshair
		_overlay.draw_line(pos + Vector2(-12, 0), pos + Vector2(12, 0), col, 1.0)
		_overlay.draw_line(pos + Vector2(0, -12), pos + Vector2(0, 12), col, 1.0)


func _draw_seed_markers() -> void:
	var trees: Array = _config.get("scenery", {}).get("trees", [])
	for i in range(trees.size()):
		var p: Array = trees[i].get("pos", [0, 0])
		var pos := Vector2(p[0], p[1])
		var s: int = int(trees[i].get("seed", 0))
		_overlay.draw_circle(pos, 8.0, Color(0.2, 0.8, 0.3, 0.5))
		_overlay.draw_string(ThemeDB.fallback_font, pos + Vector2(-20, -15), "T:%d" % s, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.3, 1.0, 0.4))

	var rocks: Array = _config.get("scenery", {}).get("rocks", [])
	for i in range(rocks.size()):
		var p: Array = rocks[i].get("pos", [0, 0])
		var pos := Vector2(p[0], p[1])
		var s: int = int(rocks[i].get("seed", 0))
		_overlay.draw_circle(pos, 6.0, Color(0.6, 0.5, 0.3, 0.5))
		_overlay.draw_string(ThemeDB.fallback_font, pos + Vector2(-20, -12), "R:%d" % s, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.8, 0.7, 0.4))


func _draw_platform_outlines() -> void:
	var platforms: Array = _config.get("platforms", [])
	for i in range(platforms.size()):
		var p: Array = platforms[i].get("pos", [0, 0])
		var w: float = platforms[i].get("width", 200)
		var rect := Rect2(p[0] - w / 2.0, p[1] - 10, w, 20)
		var col := Color(0.4, 0.6, 1.0, 0.25) if i != _selected_idx else Color(0.4, 0.6, 1.0, 0.5)
		_overlay.draw_rect(rect, col)
		_overlay.draw_rect(rect, Color(0.4, 0.6, 1.0, 0.7), false, 2.0)
		_overlay.draw_circle(Vector2(p[0], p[1]), 5.0, Color(1.0, 1.0, 1.0, 0.6))


func _draw_portal_overlay() -> void:
	var portal: Dictionary = _config.get("portal", {})
	var p: Array = portal.get("pos", [960, 880])
	var pos := Vector2(p[0], p[1])
	var range_val: float = portal.get("activation_range", 100)
	_overlay.draw_circle(pos, range_val, Color(0.9, 0.3, 0.9, 0.1))
	_overlay.draw_arc(pos, range_val, 0, TAU, 32, Color(0.9, 0.3, 0.9, 0.5), 1.5)
	_overlay.draw_circle(pos, 6.0, Color(0.9, 0.4, 0.9, 0.7))


func _draw_migration_overlay() -> void:
	# Phase colors cycle through a palette
	var phase_colors := [
		Color(0.3, 0.5, 1.0),   # Blue
		Color(0.2, 0.9, 0.4),   # Green
		Color(1.0, 0.6, 0.2),   # Orange
		Color(0.9, 0.2, 0.6),   # Pink
		Color(0.5, 0.9, 0.9),   # Cyan
		Color(0.9, 0.9, 0.2),   # Yellow
	]

	var patterns: Array = _config.get("migration_patterns", [])
	if _migration_pattern_idx >= patterns.size():
		_overlay.draw_string(ThemeDB.fallback_font, Vector2(100, 80), "No migration patterns defined", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		return

	var pattern: Dictionary = patterns[_migration_pattern_idx]
	var species_name: String = str(pattern.get("species", "?"))
	var all_phases: Array = pattern.get("phases", [])

	# Draw ALL phases (dim for inactive, bright for active)
	for pi in range(all_phases.size()):
		var is_active: bool = (pi == _migration_phase_idx)
		var base_col: Color = phase_colors[pi % phase_colors.size()]
		var alpha_mult: float = 1.0 if is_active else 0.25
		var zones: Array = all_phases[pi].get("zones", [])

		for zi in range(zones.size()):
			var p: Array = zones[zi].get("point", [0, 0])
			var pos := Vector2(p[0], p[1])
			var radius: float = zones[zi].get("radius", 100.0)
			var zone_id: int = int(zones[zi].get("zone_id", 0))
			var is_selected: bool = is_active and _selected_idx == zi

			# Fill circle
			_overlay.draw_circle(pos, radius, base_col * Color(1, 1, 1, 0.08 * alpha_mult))
			# Outline
			var line_width: float = 2.5 if is_selected else 1.5
			if is_active:
				_overlay.draw_arc(pos, radius, 0, TAU, 32, base_col * Color(1, 1, 1, 0.7 * alpha_mult), line_width)
			else:
				# Dashed look: draw partial arcs
				for seg in range(8):
					var start_angle: float = seg * TAU / 8.0
					var end_angle: float = start_angle + TAU / 16.0
					_overlay.draw_arc(pos, radius, start_angle, end_angle, 4, base_col * Color(1, 1, 1, 0.4), 1.0)

			# Center handle
			_overlay.draw_circle(pos, 6.0 if is_selected else 4.0, base_col * Color(1, 1, 1, 0.8 * alpha_mult))

			# Radius handle (right edge)
			if is_active:
				var rh := pos + Vector2(radius, 0)
				_overlay.draw_rect(Rect2(rh - Vector2(4, 4), Vector2(8, 8)), base_col * Color(1, 1, 1, 0.8))

			# X delete button (top-right of circle)
			if is_active:
				var x_pos := pos + Vector2(radius * 0.7, -radius * 0.7)
				var x_col := Color(1.0, 0.3, 0.3, 0.9)
				_overlay.draw_circle(x_pos, 8.0, Color(0.15, 0.15, 0.15, 0.85))
				_overlay.draw_line(x_pos + Vector2(-4, -4), x_pos + Vector2(4, 4), x_col, 2.0)
				_overlay.draw_line(x_pos + Vector2(4, -4), x_pos + Vector2(-4, 4), x_col, 2.0)

			# Label
			var label_text := "%s P%d Z%d" % [species_name, pi + 1, zone_id]
			if is_active:
				label_text += " r:%.0f s:%.1f" % [radius, zones[zi].get("strength", 2.0)]
			_overlay.draw_string(ThemeDB.fallback_font, pos + Vector2(-20, -radius - 8), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, base_col * Color(1, 1, 1, alpha_mult))


# -- Splay editing -------------------------------------------------------------

var _splay_available_poses: Array[String] = []
var _splay_edit_pose_idx: int = -1  # Which splay instance we're editing the pose of
var _splay_edit_dragging_cast: bool = false  # True when right-dragging to set cast direction
var _splay_edit_pose_data: Dictionary = {}  # Loaded pose data being edited
var _pose_library: Node = null  # Pose library overlay
var _splay_physics_preview: bool = false  # True when physics is active in editor

func _mark_changed(component: String, item_idx: int = -1) -> void:
	## Mark a component as having unsaved changes.
	_changed[component] = true
	if item_idx >= 0:
		if not _changed_items.has(component):
			_changed_items[component] = []
		if item_idx not in _changed_items[component]:
			_changed_items[component].append(item_idx)


func _clear_all_changes() -> void:
	_changed.clear()
	_changed_items.clear()


func _get_total_change_count() -> int:
	var total: int = 0
	for key in _changed:
		if _changed[key]:
			total += 1
	return total


func _has_custom_level() -> bool:
	return FileAccess.file_exists("user://levels/" + _level_name + ".json")


func _get_splays() -> Array:
	if not _config.has("splays"):
		_config["splays"] = []
	return _config["splays"]


func _try_select_splay(world_pos: Vector2) -> void:
	var splays: Array = _get_splays()
	for i in range(splays.size()):
		var p: Array = splays[i].get("pos", [960, 500])
		var pos := Vector2(p[0], p[1])
		if world_pos.distance_to(pos) < 40.0:
			_selected_idx = i
			_dragging = true
			return
	_selected_idx = -1


func _drag_splay(world_pos: Vector2) -> void:
	if _selected_idx < 0:
		return
	# Dragging = repositioning = cancel physics preview
	if _splay_physics_preview:
		_splay_cancel_physics_preview()
	var splays: Array = _get_splays()
	if _selected_idx < splays.size():
		var old_pos_arr: Array = splays[_selected_idx].get("pos", [960, 500])
		var old_pos := Vector2(old_pos_arr[0], old_pos_arr[1])
		var delta_pos: Vector2 = world_pos - old_pos
		splays[_selected_idx]["pos"] = [world_pos.x, world_pos.y]
		_mark_changed("splays", _selected_idx)
		# Move the creature associated with this specific splay instance
		# Only use stored reference — never guess by proximity (prevents moving wrong creature)
		var target_enemy: Node2D = null
		if splays[_selected_idx].has("_creature_ref"):
			var ref: Node2D = splays[_selected_idx]["_creature_ref"] as Node2D
			if is_instance_valid(ref):
				target_enemy = ref
		# Move the creature and its chains
		if is_instance_valid(target_enemy):
			target_enemy.global_position = world_pos
			for tether in get_tree().get_nodes_in_group("tethers"):
				if not is_instance_valid(tether):
					continue
				var ta: Dictionary = tether.anchor_a
				var tb: Dictionary = tether.anchor_b
				if ta.get("body") != target_enemy and tb.get("body") != target_enemy:
					continue
				# Move wall anchors
				if ta.get("body") == target_enemy and tb.get("is_wall", false):
					tb["pos"] = tb["pos"] + delta_pos
				elif tb.get("body") == target_enemy and ta.get("is_wall", false):
					ta["pos"] = ta["pos"] + delta_pos
				# Shift chain Verlet points
				if "_points" in tether:
					for pi in range(tether._points.size()):
						tether._points[pi] += delta_pos
					if "_prev_points" in tether:
						for pi in range(tether._prev_points.size()):
							tether._prev_points[pi] += delta_pos


func _splay_toggle_physics_preview() -> void:
	## Toggle physics simulation for all splay creatures in the level.
	## When off (default), creatures are frozen rigid — position/rotate freely.
	## When on, creatures respond to gravity and tether physics.
	_splay_physics_preview = not _splay_physics_preview
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if "_physics_frozen" in enemy:
			enemy._physics_frozen = not _splay_physics_preview
	_update_display()


func _splay_cancel_physics_preview() -> void:
	## Stop physics preview and re-freeze all splay creatures.
	_splay_physics_preview = false
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if "_physics_frozen" in enemy:
			enemy._physics_frozen = true
			enemy.velocity = Vector2.ZERO
	_update_display()


func _splay_open_library() -> void:
	if not _pose_library:
		var lib_script: GDScript = load("res://scripts/ui/pose_library.gd")
		_pose_library = CanvasLayer.new()
		_pose_library.set_script(lib_script)
		add_child(_pose_library)
		_pose_library.pose_selected.connect(_on_library_pose_selected)
	_pose_library.open()


func _on_library_pose_selected(pose_name: String) -> void:
	if _pose_library and _pose_library._replacement_mode and _selected_idx >= 0:
		# Replacing a missing pose reference
		var splays: Array = _get_splays()
		if _selected_idx < splays.size():
			splays[_selected_idx]["pose"] = pose_name
			config_changed.emit(_config)
			_update_display()
		return

	# Place a new splay instance with the selected pose
	var splays: Array = _get_splays()
	splays.append({
		"pose": pose_name,
		"creature": "quadruped",
		"pos": [960, 500],
		"rotation": 0,
		"behavior": "asleep",
	})
	_selected_idx = splays.size() - 1
	config_changed.emit(_config)
	_update_display()


func _splay_add_instance() -> void:
	## Add a new splay instance at screen center.
	if _splay_available_poses.is_empty():
		# Load pose names
		var mgr_script: GDScript = load("res://scripts/systems/splay_manager.gd")
		if mgr_script:
			var temp := Node.new()
			temp.set_script(mgr_script)
			add_child(temp)
			_splay_available_poses = temp.get_all_pose_names()
			temp.queue_free()
	var pose_name: String = _splay_available_poses[0] if not _splay_available_poses.is_empty() else "t-pose"
	var splays: Array = _get_splays()
	splays.append({
		"pose": pose_name,
		"creature": "quadruped",
		"pos": [960, 500],
		"rotation": 0,
		"behavior": "asleep",
	})
	_selected_idx = splays.size() - 1
	config_changed.emit(_config)
	_update_display()


func _splay_delete_selected() -> void:
	if _selected_idx < 0:
		return
	var splays: Array = _get_splays()
	if _selected_idx < splays.size():
		splays.remove_at(_selected_idx)
		_selected_idx = -1
		config_changed.emit(_config)
		_update_display()


func _splay_adjust_rotation(delta_deg: float) -> void:
	if _selected_idx < 0:
		return
	var splays: Array = _get_splays()
	if _selected_idx < splays.size():
		var current: float = splays[_selected_idx].get("rotation", 0)
		splays[_selected_idx]["rotation"] = fmod(current + delta_deg, 360.0)
		_mark_changed("splays", _selected_idx)
		_update_display()


func _splay_cycle_pose(direction: int) -> void:
	if _selected_idx < 0:
		return
	if _splay_available_poses.is_empty():
		var mgr_script: GDScript = load("res://scripts/systems/splay_manager.gd")
		if mgr_script:
			var temp := Node.new()
			temp.set_script(mgr_script)
			add_child(temp)
			_splay_available_poses = temp.get_all_pose_names()
			temp.queue_free()
	if _splay_available_poses.is_empty():
		return
	var splays: Array = _get_splays()
	if _selected_idx >= splays.size():
		return
	var current_pose: String = splays[_selected_idx].get("pose", "")
	var idx: int = _splay_available_poses.find(current_pose)
	idx = (idx + direction) % _splay_available_poses.size()
	if idx < 0:
		idx += _splay_available_poses.size()
	splays[_selected_idx]["pose"] = _splay_available_poses[idx]
	_mark_changed("splays", _selected_idx)
	_update_display()


func _splay_cycle_behavior() -> void:
	if _selected_idx < 0:
		return
	var splays: Array = _get_splays()
	if _selected_idx >= splays.size():
		return
	var behaviors := ["asleep", "stand_down", "active"]
	var current: String = splays[_selected_idx].get("behavior", "asleep")
	var idx: int = behaviors.find(current)
	idx = (idx + 1) % behaviors.size()
	splays[_selected_idx]["behavior"] = behaviors[idx]
	_mark_changed("splays", _selected_idx)
	_update_display()


func _draw_splay_overlay() -> void:
	var splays: Array = _get_splays()
	var splay_col := Color(0.9, 0.4, 0.2, 0.7)
	var selected_col := Color(1.0, 0.8, 0.2, 0.9)

	# Check which poses exist
	var mgr_script: GDScript = load("res://scripts/systems/splay_manager.gd")
	var temp_mgr := Node.new()
	temp_mgr.set_script(mgr_script)
	add_child(temp_mgr)
	var available_poses: Array[String] = temp_mgr.get_all_pose_names()
	temp_mgr.queue_free()

	for i in range(splays.size()):
		var s: Dictionary = splays[i]
		var p: Array = s.get("pos", [960, 500])
		var pos := Vector2(p[0], p[1])
		var is_selected: bool = (i == _selected_idx)
		var pose_name: String = s.get("pose", "")
		var pose_missing: bool = pose_name not in available_poses
		var rot: float = s.get("rotation", 0)

		var col: Color
		if pose_missing:
			col = Color(1.0, 0.2, 0.2, 0.9)  # RED for missing
		elif is_selected:
			col = selected_col
		else:
			col = splay_col

		# Body marker
		_overlay.draw_circle(pos, 16.0 if is_selected else 12.0, col * Color(1, 1, 1, 0.4))
		_overlay.draw_arc(pos, 16.0, 0, TAU, 16, col, 1.5)
		# Change indicator: yellow asterisk if this item has unsaved changes
		if _changed_items.has("splays") and i in _changed_items["splays"]:
			_overlay.draw_string(ThemeDB.fallback_font, pos + Vector2(14, -14), "*", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.9, 0.2))

		# Rotation arrow
		var rot_rad: float = deg_to_rad(rot)
		var arrow_end: Vector2 = pos + Vector2(cos(rot_rad), sin(rot_rad)) * 30.0
		_overlay.draw_line(pos, arrow_end, col, 2.0)
		var perp: Vector2 = Vector2(-sin(rot_rad), cos(rot_rad))
		_overlay.draw_line(arrow_end, arrow_end - Vector2(cos(rot_rad), sin(rot_rad)) * 8 + perp * 5, col, 1.5)
		_overlay.draw_line(arrow_end, arrow_end - Vector2(cos(rot_rad), sin(rot_rad)) * 8 - perp * 5, col, 1.5)

		# Labels
		var display_pose_name: String = s.get("pose", "?")
		var behavior: String = s.get("behavior", "?")
		if pose_missing:
			_overlay.draw_string(ThemeDB.fallback_font, pos + Vector2(-40, -22), "MISSING: " + display_pose_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 0.2, 0.2))
		else:
			_overlay.draw_string(ThemeDB.fallback_font, pos + Vector2(-30, -22), display_pose_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
		_overlay.draw_string(ThemeDB.fallback_font, pos + Vector2(-30, -10), behavior, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, col * Color(1, 1, 1, 0.7))
		_overlay.draw_string(ThemeDB.fallback_font, pos + Vector2(-30, 26), "rot:%.0f" % rot, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, col * Color(1, 1, 1, 0.5))

	# Help text
	if _active:
		var physics_str: String = " [PHYSICS ON]" if _splay_physics_preview else ""
		var help := "SPLAY: N=add  P=library  `=physics%s  Del=delete  L/R=rotate  U/D=pose  B=behavior  E=edit  Drag=move" % physics_str
		_overlay.draw_string(ThemeDB.fallback_font, Vector2(10, 30), help, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.9, 0.7, 0.3, 0.8))


# -- Splay Pose Editing (SPLAY_EDIT mode) -------------------------------------
# Spawns a frozen creature, shows all candidate connection points.
# SPACE toggles points on/off, drag to position, right-drag for cast endpoint.

var _splay_edit_creature: Node2D = null  # The frozen creature being edited
var _splay_edit_origin_pose_name: String = ""  # The pose this edit started from
var _splay_save_dialog_active: bool = false  # True when O/C save dialog is showing
var _splay_edit_origin: Vector2 = Vector2(960, 500)
var _splay_edit_all_points: Array[String] = []  # All available attachment point names
var _splay_edit_active: Dictionary = {}  # point_name -> { enabled: bool, cast_end: Vector2, pos_override: Vector2 }
var _splay_edit_selected_point: String = ""  # Currently selected point name
var _splay_edit_dragging_endpoint: bool = false  # True when dragging a cast endpoint
var _splay_edit_rotating: bool = false           # True when dragging the rotation ring
var _splay_edit_last_rotate_angle: float = 0.0   # Last angle during rotation drag
var _splay_edit_pinned: Dictionary = {}  # point_name -> bool (pinned = doesn't respond to IK pulling)
var _splay_edit_mirror: bool = false  # When true, L/R changes are mirrored along body axis
var _splay_edit_link_type: Dictionary = {}  # point_name -> "rope" or "chain"

func _enter_splay_edit() -> void:
	## Called when entering SPLAY_EDIT mode.
	## Deletes any existing monster and spawns a fresh one at the configured origin.

	# Determine origin from selected splay instance, or default center
	_splay_edit_origin = Vector2(960, 500)
	var splays: Array = _get_splays()
	if _splay_edit_pose_idx >= 0 and _splay_edit_pose_idx < splays.size():
		var p: Array = splays[_splay_edit_pose_idx].get("pos", [960, 500])
		_splay_edit_origin = Vector2(p[0], p[1])

	# Delete ALL existing quadruped monsters (the running ones)
	for e in get_tree().get_nodes_in_group("enemies"):
		if "_attach_points" in e:
			# Also remove any tethers attached to it
			for tether in get_tree().get_nodes_in_group("tethers"):
				if is_instance_valid(tether):
					var ta: Dictionary = tether.anchor_a
					var tb: Dictionary = tether.anchor_b
					if ta.get("body") == e or tb.get("body") == e:
						tether.queue_free()
			e.queue_free()
	_splay_edit_creature = null

	# Spawn a fresh monster at the configured origin
	var script: GDScript = load("res://scripts/enemies/quadruped_monster.gd")
	var creature := CharacterBody2D.new()
	creature.set_script(script)
	creature.global_position = _splay_edit_origin
	var container: Node = get_tree().current_scene
	container.add_child(creature)
	_splay_edit_creature = creature

	# Remove any existing tethers attached to this creature
	for tether in get_tree().get_nodes_in_group("tethers"):
		if is_instance_valid(tether):
			var ta: Dictionary = tether.anchor_a
			var tb: Dictionary = tether.anchor_b
			if ta.get("body") == _splay_edit_creature or tb.get("body") == _splay_edit_creature:
				tether.queue_free()

	# Freeze it and lock the pose so editor controls the skeleton
	if "_physics_frozen" in _splay_edit_creature:
		_splay_edit_creature._physics_frozen = true
	if "_pose_locked" in _splay_edit_creature:
		_splay_edit_creature._pose_locked = true
	if "_standdown" in _splay_edit_creature:
		_splay_edit_creature._standdown = true

	_splay_edit_origin = _splay_edit_creature.global_position

	# Enumerate all attachment points from the creature
	_splay_edit_all_points.clear()
	if "_attach_points" in _splay_edit_creature:
		for point_name in _splay_edit_creature._attach_points:
			_splay_edit_all_points.append(point_name)
	_splay_edit_all_points.sort()

	# Init defaults BEFORE loading saved data (load will override)
	_splay_edit_pinned.clear()
	_splay_edit_link_type.clear()
	for point_name in _splay_edit_all_points:
		_splay_edit_pinned[point_name] = point_name in ["shoulders", "waist"]
		_splay_edit_link_type[point_name] = "rope"

	# Try to reload pose data from disk (in case it was saved previously)
	if _splay_edit_pose_data.is_empty() or true:  # Always reload fresh
		var mgr_script: GDScript = load("res://scripts/systems/splay_manager.gd")
		var temp := Node.new()
		temp.set_script(mgr_script)
		add_child(temp)
		# Try to load the pose associated with the selected splay instance
		var pose_name: String = ""
		var splays2: Array = _get_splays()
		if _splay_edit_pose_idx >= 0 and _splay_edit_pose_idx < splays2.size():
			pose_name = splays2[_splay_edit_pose_idx].get("pose", "")
		if pose_name != "":
			var loaded: Dictionary = temp.load_pose(pose_name)
			if not loaded.is_empty():
				_splay_edit_pose_data = loaded.duplicate(true)
				_splay_edit_origin_pose_name = pose_name
		temp.queue_free()

	# Initialize active state — start from creature's live skeleton positions
	_splay_edit_active.clear()
	for point_name in _splay_edit_all_points:
		var point_world: Vector2
		if is_instance_valid(_splay_edit_creature) and "_attach_points" in _splay_edit_creature:
			if _splay_edit_creature._attach_points.has(point_name):
				point_world = _splay_edit_creature.global_position + _splay_edit_creature._attach_points[point_name].position
			else:
				point_world = _splay_edit_origin
		else:
			point_world = _splay_edit_origin
		_splay_edit_active[point_name] = {
			"enabled": false,
			"cast_end": Vector2.ZERO,
			"pos_override": point_world,
		}

	# Load saved pose data: directly set skeleton positions from saved relative_pos,
	# then enforce rigidity, then set active state.
	if not _splay_edit_pose_data.is_empty() and is_instance_valid(_splay_edit_creature):
		var c: Node2D = _splay_edit_creature

		# Restore full skeleton snapshot if available (exact positions)
		var skel: Dictionary = _splay_edit_pose_data.get("skeleton", {})
		if not skel.is_empty():
			if skel.has("spine") and skel["spine"].size() >= 3:
				for i in range(3):
					c._spine[i] = Vector2(skel["spine"][i][0], skel["spine"][i][1])
			if skel.has("neck") and skel["neck"].size() >= 2:
				c._neck[0] = Vector2(skel["neck"][0][0], skel["neck"][0][1])
				c._neck[1] = Vector2(skel["neck"][1][0], skel["neck"][1][1])
			if skel.has("skull"):
				c._skull = Vector2(skel["skull"][0], skel["skull"][1])
			if skel.has("jaw"):
				c._jaw = Vector2(skel["jaw"][0], skel["jaw"][1])
			if skel.has("clavicles") and "_clavicles" in c:
				c._clavicles[0] = Vector2(skel["clavicles"][0][0], skel["clavicles"][0][1])
				c._clavicles[1] = Vector2(skel["clavicles"][1][0], skel["clavicles"][1][1])
			if skel.has("hip_bones") and "_hip_bones" in c:
				c._hip_bones[0] = Vector2(skel["hip_bones"][0][0], skel["hip_bones"][0][1])
				c._hip_bones[1] = Vector2(skel["hip_bones"][1][0], skel["hip_bones"][1][1])
			if skel.has("tail") and "_tail" in c:
				for ti in range(mini(skel["tail"].size(), c._tail.size())):
					c._tail[ti] = Vector2(skel["tail"][ti][0], skel["tail"][ti][1])
			if skel.has("legs") and "_legs" in c:
				for li in range(mini(skel["legs"].size(), c._legs.size())):
					for ji in range(3):
						c._legs[li][ji] = Vector2(skel["legs"][li][ji][0], skel["legs"][li][ji][1])

		# Update attachment point positions from restored skeleton
		if c.has_method("_update_hitbox_positions"):
			c._update_hitbox_positions()
		c.queue_redraw()

		# Set active state with correct world positions
		for conn in _splay_edit_pose_data.get("connections", []):
			var pn: String = conn.get("point", "")
			if _splay_edit_active.has(pn):
				_splay_edit_active[pn]["enabled"] = true
				_splay_edit_link_type[pn] = conn.get("link_type", "rope")
				var point_world: Vector2 = _splay_edit_origin
				if "_attach_points" in c and c._attach_points.has(pn):
					point_world = c.global_position + c._attach_points[pn].position
				_splay_edit_active[pn]["pos_override"] = point_world
				var cd: Array = conn.get("cast_dir", [0, -1])
				_splay_edit_active[pn]["cast_end"] = point_world + Vector2(cd[0], cd[1]) * 200.0

	_selected_idx = -1
	_splay_edit_selected_point = ""
	_splay_edit_mirror = false
	# NOTE: pinned/link_type are initialized BEFORE pose load (above), not here


func _exit_splay_edit() -> void:
	# If we have a saved pose with active connections, spawn as a splay with tethers
	if is_instance_valid(_splay_edit_creature) and not _splay_edit_pose_data.is_empty():
		var has_active: bool = false
		for pn in _splay_edit_active:
			if _splay_edit_active[pn].get("enabled", false):
				has_active = true
				break
		if has_active:
			# Snap creature to the configured origin
			_splay_edit_creature.global_position = _splay_edit_origin
			_splay_edit_creature.velocity = Vector2.ZERO

			# Restore skeleton from saved snapshot
			var skel: Dictionary = _splay_edit_pose_data.get("skeleton", {})
			if not skel.is_empty():
				var c: Node2D = _splay_edit_creature
				if skel.has("spine") and skel["spine"].size() >= 3:
					for i in range(3):
						c._spine[i] = Vector2(skel["spine"][i][0], skel["spine"][i][1])
				if skel.has("neck") and skel["neck"].size() >= 2:
					c._neck[0] = Vector2(skel["neck"][0][0], skel["neck"][0][1])
					c._neck[1] = Vector2(skel["neck"][1][0], skel["neck"][1][1])
				if skel.has("skull"):
					c._skull = Vector2(skel["skull"][0], skel["skull"][1])
				if skel.has("jaw"):
					c._jaw = Vector2(skel["jaw"][0], skel["jaw"][1])
				if skel.has("clavicles") and "_clavicles" in c:
					c._clavicles[0] = Vector2(skel["clavicles"][0][0], skel["clavicles"][0][1])
					c._clavicles[1] = Vector2(skel["clavicles"][1][0], skel["clavicles"][1][1])
				if skel.has("hip_bones") and "_hip_bones" in c:
					c._hip_bones[0] = Vector2(skel["hip_bones"][0][0], skel["hip_bones"][0][1])
					c._hip_bones[1] = Vector2(skel["hip_bones"][1][0], skel["hip_bones"][1][1])
				if skel.has("tail") and "_tail" in c:
					for ti in range(mini(skel["tail"].size(), c._tail.size())):
						c._tail[ti] = Vector2(skel["tail"][ti][0], skel["tail"][ti][1])
				if skel.has("legs") and "_legs" in c:
					for li in range(mini(skel["legs"].size(), c._legs.size())):
						for ji in range(3):
							c._legs[li][ji] = Vector2(skel["legs"][li][ji][0], skel["legs"][li][ji][1])
				if c.has_method("_update_hitbox_positions"):
					c._update_hitbox_positions()

			# Keep frozen + pose locked — same as splay spawn
			if "_physics_frozen" in _splay_edit_creature:
				_splay_edit_creature._physics_frozen = true
			if "_pose_locked" in _splay_edit_creature:
				_splay_edit_creature._pose_locked = true

			# Spawn tethers/chains from the saved pose
			_spawn_tethers_from_pose()
			_splay_edit_creature.queue_redraw()
			return

	# No active connections — just unfreeze
	if is_instance_valid(_splay_edit_creature):
		if "_physics_frozen" in _splay_edit_creature:
			_splay_edit_creature._physics_frozen = false
		if "_pose_locked" in _splay_edit_creature:
			_splay_edit_creature._pose_locked = false


func _spawn_tethers_from_pose() -> void:
	## Create tethers/chains from the saved pose connections to world surfaces.
	if not is_instance_valid(_splay_edit_creature) or _splay_edit_pose_data.is_empty():
		return
	var TetherScript: GDScript = load("res://scripts/systems/tether.gd")
	var ChainScript: GDScript = load("res://scripts/systems/chain.gd")
	var creature: Node2D = _splay_edit_creature
	var origin: Vector2 = creature.global_position

	for conn in _splay_edit_pose_data.get("connections", []):
		var point_name: String = conn.get("point", "")
		var rp: Array = conn.get("relative_pos", [0, 0])
		var cd: Array = conn.get("cast_dir", [0, -1])
		var lt: String = conn.get("link_type", "rope")
		var cast_dir := Vector2(cd[0], cd[1]).normalized()
		var conn_world: Vector2 = origin + Vector2(rp[0], rp[1])

		# Raycast to find surface
		var cast_end: Vector2 = conn_world + cast_dir * 800.0
		var space := creature.get_world_2d().direct_space_state
		var query := PhysicsRayQueryParameters2D.create(conn_world, cast_end, 1)
		var result: Dictionary = space.intersect_ray(query)
		if not result:
			continue

		var surface_pos: Vector2 = result["position"]
		var length: float = conn_world.distance_to(surface_pos)

		if lt == "chain":
			var anchor_a: Dictionary = ChainScript.make_anchor_body(creature, point_name)
			var anchor_b: Dictionary = ChainScript.make_anchor_wall(surface_pos)
			var link := Node2D.new()
			link.set_script(ChainScript)
			link.setup(anchor_a, anchor_b, length)
			get_tree().current_scene.add_child(link)
		else:
			var anchor_a: Dictionary = TetherScript.make_anchor_body(creature, point_name)
			var anchor_b: Dictionary = TetherScript.make_anchor_wall(surface_pos)
			var link := Node2D.new()
			link.set_script(TetherScript)
			link.setup(anchor_a, anchor_b, length)
			get_tree().current_scene.add_child(link)


func _try_select_splay_connection(world_pos: Vector2) -> void:
	if not is_instance_valid(_splay_edit_creature):
		return

	# Check if clicking the origin (center) to drag the whole creature
	if world_pos.distance_to(_splay_edit_origin) < 15.0:
		_splay_edit_selected_point = "_origin"
		_dragging = true
		return

	# Check if clicking the rotation ring (radius ~40px from origin, ±8px tolerance)
	var ring_dist: float = world_pos.distance_to(_splay_edit_origin)
	if ring_dist > 32.0 and ring_dist < 48.0:
		_splay_edit_selected_point = "_rotate"
		_splay_edit_rotating = true
		_splay_edit_last_rotate_angle = (_splay_edit_origin).angle_to_point(world_pos)
		_dragging = true
		return

	# Check cast endpoints first (small circles at end of ray)
	for point_name in _splay_edit_all_points:
		var data: Dictionary = _splay_edit_active.get(point_name, {})
		if not data.get("enabled", false):
			continue
		var cast_end: Vector2 = data.get("cast_end", Vector2.ZERO)
		if cast_end != Vector2.ZERO and world_pos.distance_to(cast_end) < 15.0:
			_splay_edit_selected_point = point_name
			_splay_edit_dragging_endpoint = true
			_dragging = true
			return

	# Check connection point circles
	for point_name in _splay_edit_all_points:
		var point_world: Vector2 = _get_splay_point_world(point_name)
		if world_pos.distance_to(point_world) < 15.0:
			_splay_edit_selected_point = point_name
			_splay_edit_dragging_endpoint = false
			_dragging = true
			return

	_splay_edit_selected_point = ""
	_dragging = false


func _drag_splay_connection(world_pos: Vector2) -> void:
	if _splay_edit_selected_point == "_rotate" and _splay_edit_rotating:
		# Rotate everything around the origin
		_splay_edit_rotate_all(world_pos)
		return

	if _splay_edit_selected_point == "_origin":
		# Move the whole creature + all overrides
		if is_instance_valid(_splay_edit_creature):
			var delta_pos: Vector2 = world_pos - _splay_edit_origin
			_splay_edit_creature.global_position = world_pos
			_splay_edit_origin = world_pos
			# Move all overrides and cast endpoints with it
			for pn in _splay_edit_active:
				var data: Dictionary = _splay_edit_active[pn]
				if data["pos_override"] != Vector2.ZERO:
					data["pos_override"] += delta_pos
				if data["cast_end"] != Vector2.ZERO:
					data["cast_end"] += delta_pos
		return

	if _splay_edit_selected_point == "" or not _splay_edit_active.has(_splay_edit_selected_point):
		return

	if _splay_edit_dragging_endpoint:
		# Dragging the cast ray endpoint
		_splay_edit_active[_splay_edit_selected_point]["cast_end"] = world_pos
		# Mirror the cast endpoint too
		if _splay_edit_mirror:
			var mirror_pt: String = _get_mirror_point(_splay_edit_selected_point)
			if mirror_pt != "" and _splay_edit_active.has(mirror_pt):
				# Mirror across spine axis
				var rel: Vector2 = world_pos - _splay_edit_origin
				var spine_dir: Vector2 = Vector2(1, 0)
				if is_instance_valid(_splay_edit_creature) and "_spine" in _splay_edit_creature:
					spine_dir = (_splay_edit_creature._spine[0] - _splay_edit_creature._spine[2]).normalized()
				var proj: float = rel.dot(spine_dir)
				var perp: Vector2 = rel - spine_dir * proj
				var mirrored_rel: Vector2 = spine_dir * proj - perp
				_splay_edit_active[mirror_pt]["cast_end"] = _splay_edit_origin + mirrored_rel
	else:
		# Dragging the connection point — check if pinned
		if _splay_edit_pinned.get(_splay_edit_selected_point, false):
			return  # Pinned — doesn't move
		if not is_instance_valid(_splay_edit_creature):
			return

		# IK solve the chain from origin to drag point
		_splay_edit_ik_drag(_splay_edit_selected_point, world_pos)

		# Mirror: apply same movement to the opposite side
		if _splay_edit_mirror:
			var mirror_pt: String = _get_mirror_point(_splay_edit_selected_point)
			if mirror_pt != "" and not _splay_edit_pinned.get(mirror_pt, false):
				# Mirror the target position across the spine axis
				var rel: Vector2 = world_pos - _splay_edit_origin
				# Determine spine axis from creature
				var spine_dir: Vector2 = (_splay_edit_creature._spine[0] - _splay_edit_creature._spine[2]).normalized()
				# Reflect rel across spine axis
				var proj: float = rel.dot(spine_dir)
				var perp: Vector2 = rel - spine_dir * proj
				var mirrored_rel: Vector2 = spine_dir * proj - perp
				var mirror_world: Vector2 = _splay_edit_origin + mirrored_rel
				_splay_edit_ik_drag(mirror_pt, mirror_world)
				# Mirror the enabled/cast_end state too
				if _splay_edit_active.has(mirror_pt) and _splay_edit_active.has(_splay_edit_selected_point):
					var src: Dictionary = _splay_edit_active[_splay_edit_selected_point]
					var dst: Dictionary = _splay_edit_active[mirror_pt]
					dst["enabled"] = src["enabled"]


func _get_splay_point_world(point_name: String) -> Vector2:
	# Use override position if available (from dragging or loaded pose)
	if _splay_edit_active.has(point_name):
		var pos_ov: Vector2 = _splay_edit_active[point_name].get("pos_override", Vector2.ZERO)
		if pos_ov != Vector2.ZERO:
			return pos_ov
	# Fallback: creature's live skeleton position
	if is_instance_valid(_splay_edit_creature) and "_attach_points" in _splay_edit_creature:
		if _splay_edit_creature._attach_points.has(point_name):
			return _splay_edit_creature.global_position + _splay_edit_creature._attach_points[point_name].position
	return _splay_edit_origin


func _splay_edit_toggle_point() -> void:
	if _splay_edit_selected_point == "" or _splay_edit_selected_point == "_origin":
		return
	if not _splay_edit_active.has(_splay_edit_selected_point):
		return
	var data: Dictionary = _splay_edit_active[_splay_edit_selected_point]
	data["enabled"] = not data["enabled"]
	if data["enabled"] and data["cast_end"] == Vector2.ZERO:
		_splay_edit_set_default_cast(data, _splay_edit_selected_point)
	# Mirror toggle
	if _splay_edit_mirror:
		var mirror_pt: String = _get_mirror_point(_splay_edit_selected_point)
		if mirror_pt != "" and _splay_edit_active.has(mirror_pt):
			var mdata: Dictionary = _splay_edit_active[mirror_pt]
			mdata["enabled"] = data["enabled"]
			if mdata["enabled"] and mdata["cast_end"] == Vector2.ZERO:
				_splay_edit_set_default_cast(mdata, mirror_pt)


func _splay_edit_cycle_link_type() -> void:
	if _splay_edit_selected_point == "" or _splay_edit_selected_point == "_origin":
		return
	if _splay_edit_link_type.has(_splay_edit_selected_point):
		if _splay_edit_link_type[_splay_edit_selected_point] == "rope":
			_splay_edit_link_type[_splay_edit_selected_point] = "chain"
		else:
			_splay_edit_link_type[_splay_edit_selected_point] = "rope"
		# Mirror
		if _splay_edit_mirror:
			var mirror_pt: String = _get_mirror_point(_splay_edit_selected_point)
			if mirror_pt != "" and _splay_edit_link_type.has(mirror_pt):
				_splay_edit_link_type[mirror_pt] = _splay_edit_link_type[_splay_edit_selected_point]


func _splay_edit_set_default_cast(data: Dictionary, point_name: String) -> void:
	var body_len: float = _splay_edit_get_body_length()
	var point_world: Vector2 = data.get("pos_override", _get_splay_point_world(point_name))
	var away: Vector2 = (point_world - _splay_edit_origin).normalized()
	if away.length() < 0.1:
		away = Vector2(0, -1)
	data["cast_end"] = _splay_edit_origin + away * body_len


func _splay_edit_rotate_all(world_pos: Vector2) -> void:
	## Rotate the entire skeleton + all connection points around the origin.
	var current_angle: float = _splay_edit_origin.angle_to_point(world_pos)
	var delta_angle: float = current_angle - _splay_edit_last_rotate_angle
	_splay_edit_last_rotate_angle = current_angle

	if absf(delta_angle) < 0.001 or not is_instance_valid(_splay_edit_creature):
		return

	var origin: Vector2 = _splay_edit_origin
	var cr: Node2D = _splay_edit_creature

	# Rotate all skeleton points around the origin (in local space, origin = creature global_pos)
	# Since skeleton points are local to the creature, and creature is at origin, rotate around (0,0)
	for i in range(cr._spine.size()):
		cr._spine[i] = cr._spine[i].rotated(delta_angle)
	for i in range(cr._neck.size()):
		cr._neck[i] = cr._neck[i].rotated(delta_angle)
	cr._skull = cr._skull.rotated(delta_angle)
	cr._jaw = cr._jaw.rotated(delta_angle)
	if "_clavicles" in cr:
		for i in range(cr._clavicles.size()):
			cr._clavicles[i] = cr._clavicles[i].rotated(delta_angle)
	if "_hip_bones" in cr:
		for i in range(cr._hip_bones.size()):
			cr._hip_bones[i] = cr._hip_bones[i].rotated(delta_angle)
	if "_tail" in cr:
		for i in range(cr._tail.size()):
			cr._tail[i] = cr._tail[i].rotated(delta_angle)
	if "_legs" in cr:
		for li in range(cr._legs.size()):
			for ji in range(cr._legs[li].size()):
				cr._legs[li][ji] = cr._legs[li][ji].rotated(delta_angle)

	# Update attachment positions
	if cr.has_method("_update_hitbox_positions"):
		cr._update_hitbox_positions()
	cr.queue_redraw()

	# Rotate all active point overrides and cast endpoints around the origin (world space)
	for pn in _splay_edit_active:
		var data: Dictionary = _splay_edit_active[pn]
		var pos_ov: Vector2 = data.get("pos_override", Vector2.ZERO)
		if pos_ov != Vector2.ZERO:
			data["pos_override"] = origin + (pos_ov - origin).rotated(delta_angle)
		var cast_end: Vector2 = data.get("cast_end", Vector2.ZERO)
		if cast_end != Vector2.ZERO:
			data["cast_end"] = origin + (cast_end - origin).rotated(delta_angle)


func _splay_edit_ik_drag(point_name: String, world_pos: Vector2) -> void:
	## IK-drag a single connection point to world_pos. Updates skeleton + pos_override.
	if not is_instance_valid(_splay_edit_creature):
		return
	var ChainIK: GDScript = load("res://scripts/systems/chain_ik.gd")
	var target_local: Vector2 = world_pos - _splay_edit_creature.global_position
	var chain_data: Dictionary = ChainIK.get_chain_for_point(point_name, _splay_edit_creature)
	if chain_data.is_empty():
		return

	# Build pinned array
	var chain: Array[Vector2] = chain_data["chain"]
	var pinned_arr: Array[bool] = []
	pinned_arr.append(true)  # Root always pinned
	var chain_point_names: Array[String] = _get_chain_point_names(point_name)
	for i in range(1, chain.size()):
		if i - 1 < chain_point_names.size():
			var cpn: String = chain_point_names[i - 1]
			pinned_arr.append(_splay_edit_pinned.get(cpn, false))
		else:
			pinned_arr.append(false)

	var solved: Array[Vector2] = ChainIK.solve(
		chain_data["chain"], chain_data["lengths"], chain_data["max_angles"],
		target_local, true, pinned_arr
	)
	var apply_fn: Callable = chain_data["apply"]
	apply_fn.call(solved)

	# Settle dangling lower legs after IK changes
	_splay_edit_settle_legs()

	# Update attachment positions from skeleton
	if _splay_edit_creature.has_method("_update_hitbox_positions"):
		_splay_edit_creature._update_hitbox_positions()
	_splay_edit_creature.queue_redraw()

	# Refresh ALL pos_overrides and cast endpoints from actual skeleton
	_splay_edit_refresh_all_points()


func _splay_edit_settle_legs() -> void:
	## Simulate gravity on lower leg segments (knee→foot) so they dangle naturally.
	if not is_instance_valid(_splay_edit_creature) or "_legs" not in _splay_edit_creature:
		return
	for _sim in range(8):
		for li in range(_splay_edit_creature._legs.size()):
			if "_leg_severed" in _splay_edit_creature and _splay_edit_creature._leg_severed[li]:
				continue
			var knee: Vector2 = _splay_edit_creature._legs[li][1]
			var foot: Vector2 = _splay_edit_creature._legs[li][2]
			var lower_dir: Vector2 = (foot - knee).normalized()
			# Pull toward gravity
			lower_dir = (lower_dir + Vector2(0, 0.4)).normalized()
			_splay_edit_creature._legs[li][2] = knee + lower_dir * 22.0  # LEG_LOWER_LEN


func _splay_edit_refresh_all_points() -> void:
	## Refresh all pos_overrides and recalculate cast endpoints for OFF points.
	if not is_instance_valid(_splay_edit_creature):
		return
	var body_len: float = _splay_edit_get_body_length()
	var origin: Vector2 = _splay_edit_origin
	for pn in _splay_edit_all_points:
		# Read actual skeleton position
		var point_world: Vector2 = origin
		if "_attach_points" in _splay_edit_creature and _splay_edit_creature._attach_points.has(pn):
			point_world = _splay_edit_creature.global_position + _splay_edit_creature._attach_points[pn].position
		_splay_edit_active[pn]["pos_override"] = point_world
		# For OFF points (not enabled): recalculate cast endpoint on body-length circle
		if not _splay_edit_active[pn].get("enabled", false):
			var away: Vector2 = (point_world - origin).normalized()
			if away.length() < 0.1:
				away = Vector2(0, -1)
			_splay_edit_active[pn]["cast_end"] = origin + away * body_len


func _get_chain_point_names(endpoint: String) -> Array[String]:
	## Map chain indices (after root) to attachment point names for pin lookup.
	## Chain is [origin(spine1), ..., endpoint]. Returns names for indices 1..N-1.
	match endpoint:
		"head":
			return ["shoulders", "", "head"]  # spine[0]=shoulders, neck[1]=(no attach), skull=head
		"tail_tip":
			return ["waist", "", "", "", "", "tail_tip"]  # spine[2]=waist, tail[0..4], tail_tip
		"shoulders":
			return ["shoulders"]
		"waist":
			return ["waist"]
		"elbow_l":
			return ["shoulders", "", "", "elbow_l"]  # spine[0], clavicle, leg hip, knee
		"elbow_r":
			return ["shoulders", "", "", "elbow_r"]
		"knee_l":
			return ["waist", "", "", "knee_l"]
		"knee_r":
			return ["waist", "", "", "knee_r"]
	return []


func _splay_edit_toggle_pin() -> void:
	if _splay_edit_selected_point == "" or _splay_edit_selected_point == "_origin":
		return
	if _splay_edit_pinned.has(_splay_edit_selected_point):
		_splay_edit_pinned[_splay_edit_selected_point] = not _splay_edit_pinned[_splay_edit_selected_point]


func _get_mirror_point(point_name: String) -> String:
	## Get the mirrored counterpart of a point (L↔R).
	match point_name:
		"elbow_l": return "elbow_r"
		"elbow_r": return "elbow_l"
		"knee_l": return "knee_r"
		"knee_r": return "knee_l"
	return ""


func _splay_edit_move_endpoint(dir: Vector2) -> void:
	if _splay_edit_selected_point == "" or not _splay_edit_active.has(_splay_edit_selected_point):
		return
	var data: Dictionary = _splay_edit_active[_splay_edit_selected_point]
	if data.get("enabled", false):
		data["cast_end"] += dir * 5.0


func _splay_edit_preset_pose(direction: String) -> void:
	## Reset body to a cardinal preset pose. Generic for spine-based creatures.
	## direction: "left" (head L, tail R), "right", "up" (head up), "down" (head down)
	if not is_instance_valid(_splay_edit_creature):
		return

	var creature: Node2D = _splay_edit_creature
	var origin: Vector2 = _splay_edit_origin
	# Calculate in local space (relative to creature global_position, which == origin)
	var local_origin: Vector2 = Vector2.ZERO  # spine[1] in local space

	# Determine the spine axis direction based on preset
	var head_dir: Vector2  # Direction from origin toward head
	var perp_dir: Vector2  # Perpendicular (for limb placement)
	match direction:
		"left":
			head_dir = Vector2(-1, 0)
			perp_dir = Vector2(0, 1)
		"right":
			head_dir = Vector2(1, 0)
			perp_dir = Vector2(0, 1)
		"up":
			head_dir = Vector2(0, -1)
			perp_dir = Vector2(1, 0)
		"down":
			head_dir = Vector2(0, 1)
			perp_dir = Vector2(-1, 0)
		_:
			head_dir = Vector2(1, 0)
			perp_dir = Vector2(0, 1)

	var tail_dir: Vector2 = -head_dir

	# Segment lengths
	var SPINE_L: float = 28.0
	var NECK_L: float = 22.0
	var SKULL_L: float = 16.0
	var TAIL_L: float = 16.0
	var CLAV_L: float = 12.0
	var HIP_L: float = 12.0
	var UPPER_L: float = 24.0
	var LOWER_L: float = 22.0

	# Place spine along axis
	creature._spine[1] = local_origin
	creature._spine[0] = local_origin + head_dir * SPINE_L
	creature._spine[2] = local_origin + tail_dir * SPINE_L

	# Neck + skull along head direction
	creature._neck[0] = creature._spine[0]
	creature._neck[1] = creature._spine[0] + head_dir * NECK_L
	creature._skull = creature._neck[1] + head_dir * SKULL_L
	creature._jaw = creature._skull + head_dir * 8 + perp_dir * 6

	# Tail along tail direction
	if "_tail" in creature:
		var tail_start: Vector2 = creature._spine[2] + tail_dir * 4
		for ti in range(creature._tail.size()):
			creature._tail[ti] = tail_start + tail_dir * TAIL_L * (ti + 1)

	# Clavicles: perpendicular from spine[0]
	if "_clavicles" in creature:
		creature._clavicles[0] = creature._spine[0] + perp_dir * CLAV_L
		creature._clavicles[1] = creature._spine[0] - perp_dir * CLAV_L

	# Hip bones: perpendicular from spine[2]
	if "_hip_bones" in creature:
		creature._hip_bones[0] = creature._spine[2] + perp_dir * HIP_L
		creature._hip_bones[1] = creature._spine[2] - perp_dir * HIP_L

	# Limbs: dangle in the perp direction (gravity-like)
	# For "up"/"down", limbs go sideways; for "left"/"right", limbs dangle down
	var dangle_dir: Vector2
	if direction in ["left", "right"]:
		dangle_dir = Vector2(0, 1)  # Dangle downward
	else:
		# For up/down poses, limbs go outward from the spine
		dangle_dir = perp_dir  # Already set correctly

	if "_legs" in creature:
		# Front legs (arms) — attach to clavicles
		for li in [0, 1]:
			var clav: Vector2 = creature._clavicles[li] if "_clavicles" in creature else creature._spine[0]
			creature._legs[li][0] = clav
			creature._legs[li][1] = clav + dangle_dir * UPPER_L
			creature._legs[li][2] = clav + dangle_dir * (UPPER_L + LOWER_L)
		# Rear legs — attach to hip bones
		for li in [2, 3]:
			var hip: Vector2 = creature._hip_bones[li - 2] if "_hip_bones" in creature else creature._spine[2]
			creature._legs[li][0] = hip
			creature._legs[li][1] = hip + dangle_dir * UPPER_L
			creature._legs[li][2] = hip + dangle_dir * (UPPER_L + LOWER_L)

	# For "down" pose: mirror the legs (right on left, left on right)
	if direction == "down" and "_legs" in creature and "_clavicles" in creature:
		# Swap leg pairs side assignment
		var temp_clav: Vector2 = creature._clavicles[0]
		creature._clavicles[0] = creature._clavicles[1]
		creature._clavicles[1] = temp_clav
		if "_hip_bones" in creature:
			var temp_hip: Vector2 = creature._hip_bones[0]
			creature._hip_bones[0] = creature._hip_bones[1]
			creature._hip_bones[1] = temp_hip
		# Re-attach legs to swapped positions
		for li in [0, 1]:
			creature._legs[li][0] = creature._clavicles[li]
			creature._legs[li][1] = creature._clavicles[li] + dangle_dir * UPPER_L
			creature._legs[li][2] = creature._clavicles[li] + dangle_dir * (UPPER_L + LOWER_L)
		for li in [2, 3]:
			creature._legs[li][0] = creature._hip_bones[li - 2]
			creature._legs[li][1] = creature._hip_bones[li - 2] + dangle_dir * UPPER_L
			creature._legs[li][2] = creature._hip_bones[li - 2] + dangle_dir * (UPPER_L + LOWER_L)

	# Update facing
	creature._facing = -1.0 if direction == "left" else 1.0

	# Unplant all feet
	if "_foot_planted" in creature:
		for li in range(creature._foot_planted.size()):
			creature._foot_planted[li] = false

	# Force creature to update hitbox/attachment point positions from new skeleton
	if creature.has_method("_update_hitbox_positions"):
		creature._update_hitbox_positions()

	# Let dangling segments (lower legs) settle briefly with gravity
	# Simulate a few frames of gravity on unplanted feet
	for _sim in range(5):
		for li in range(creature._legs.size()):
			if "_leg_severed" in creature and creature._leg_severed[li]:
				continue
			# Lower leg dangles from knee
			var knee: Vector2 = creature._legs[li][1]
			var foot: Vector2 = creature._legs[li][2]
			var lower_dir: Vector2 = (foot - knee).normalized()
			# Apply slight gravity pull
			lower_dir = (lower_dir + Vector2(0, 0.3)).normalized()
			creature._legs[li][2] = knee + lower_dir * 22.0  # LEG_LOWER_LEN

	# Update attachment positions again after leg settling
	if creature.has_method("_update_hitbox_positions"):
		creature._update_hitbox_positions()

	# Now read actual joint positions from the creature and set connection points
	var body_len: float = _splay_edit_get_body_length()
	for pn in _splay_edit_active:
		_splay_edit_active[pn]["enabled"] = false
		# Read the actual skeleton position for this attachment point
		var point_world: Vector2 = Vector2.ZERO
		if "_attach_points" in creature and creature._attach_points.has(pn):
			point_world = creature.global_position + creature._attach_points[pn].position
		else:
			point_world = origin
		_splay_edit_active[pn]["pos_override"] = point_world
		# Cast endpoint: body-length radius straight out from origin through this joint
		var away: Vector2 = (point_world - origin).normalized()
		if away.length() < 0.1:
			away = Vector2(0, -1)
		_splay_edit_active[pn]["cast_end"] = origin + away * body_len

	# Force redraw
	creature.queue_redraw()


func _splay_edit_get_body_length() -> float:
	## Total body length from skull to tail tip — used for cast endpoint default radius.
	if not is_instance_valid(_splay_edit_creature):
		return 200.0
	var skull: Vector2 = _splay_edit_creature._skull if "_skull" in _splay_edit_creature else Vector2.ZERO
	var tail_tip: Vector2 = Vector2.ZERO
	if "_tail" in _splay_edit_creature and _splay_edit_creature._tail.size() > 0:
		tail_tip = _splay_edit_creature._tail[_splay_edit_creature._tail.size() - 1]
	return skull.distance_to(tail_tip)


func _splay_edit_build_pose(pose_name: String) -> Dictionary:
	## Build pose dictionary from current editor state.
	var connections: Array = []
	for point_name in _splay_edit_all_points:
		var data: Dictionary = _splay_edit_active.get(point_name, {})
		if not data.get("enabled", false):
			continue
		var point_world: Vector2 = data.get("pos_override", _get_splay_point_world(point_name))
		var rel_pos: Vector2 = point_world - _splay_edit_origin
		var cast_end: Vector2 = data.get("cast_end", point_world + Vector2(0, -200))
		var cast_dir: Vector2 = (cast_end - point_world).normalized()
		if cast_dir.length() < 0.1:
			cast_dir = Vector2(0, -1)
		var lt: String = _splay_edit_link_type.get(point_name, "rope")
		connections.append({
			"point": point_name,
			"relative_pos": [snappedf(rel_pos.x, 0.1), snappedf(rel_pos.y, 0.1)],
			"cast_dir": [snappedf(cast_dir.x, 0.01), snappedf(cast_dir.y, 0.01)],
			"link_type": lt,
		})

	var skel: Dictionary = {}
	if is_instance_valid(_splay_edit_creature):
		var cr: Node2D = _splay_edit_creature
		skel["spine"] = [[cr._spine[0].x, cr._spine[0].y], [cr._spine[1].x, cr._spine[1].y], [cr._spine[2].x, cr._spine[2].y]]
		skel["neck"] = [[cr._neck[0].x, cr._neck[0].y], [cr._neck[1].x, cr._neck[1].y]]
		skel["skull"] = [cr._skull.x, cr._skull.y]
		skel["jaw"] = [cr._jaw.x, cr._jaw.y]
		if "_clavicles" in cr:
			skel["clavicles"] = [[cr._clavicles[0].x, cr._clavicles[0].y], [cr._clavicles[1].x, cr._clavicles[1].y]]
		if "_hip_bones" in cr:
			skel["hip_bones"] = [[cr._hip_bones[0].x, cr._hip_bones[0].y], [cr._hip_bones[1].x, cr._hip_bones[1].y]]
		if "_tail" in cr:
			skel["tail"] = []
			for t in cr._tail:
				skel["tail"].append([t.x, t.y])
		if "_legs" in cr:
			skel["legs"] = []
			for li in range(cr._legs.size()):
				skel["legs"].append([[cr._legs[li][0].x, cr._legs[li][0].y], [cr._legs[li][1].x, cr._legs[li][1].y], [cr._legs[li][2].x, cr._legs[li][2].y]])

	return {
		"name": pose_name,
		"creature": "quadruped",
		"breakaway_sound": "",
		"connections": connections,
		"skeleton": skel,
	}


func _splay_edit_save_pose_original() -> void:
	## Save to bundled source: res://data/splay_poses/ (source mode only)
	if not Version.is_source_mode():
		return
	var pose_name: String = _splay_edit_origin_pose_name if _splay_edit_origin_pose_name != "" else _splay_edit_pose_data.get("name", "custom-%d" % (randi() % 1000))
	var pose: Dictionary = _splay_edit_build_pose(pose_name)
	# Write directly to res:// (project source)
	var path: String = "res://data/splay_poses/" + pose_name + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(pose, "\t"))
		file.close()
	_splay_edit_pose_data = pose
	print("EDITOR: saved ORIGINAL pose '%s'" % pose_name)
	_show_center_flash("ORIGINAL SAVED", Color(0.3, 0.8, 1.0))
	_status_label.text = "ORIGINAL SAVED"
	_status_label.modulate = Color(0.3, 0.8, 1.0)
	var tween := create_tween()
	tween.tween_interval(1.5)
	tween.tween_callback(func() -> void:
		if is_instance_valid(_status_label):
			_status_label.text = "EDITOR"
			_status_label.modulate = Color(0.3, 0.8, 0.3)
	)


func _splay_edit_save_pose_custom() -> void:
	## Save to user directory: user://data/splay_poses/
	var pose_name: String = _splay_edit_pose_data.get("name", "custom-%d" % (randi() % 1000))
	var pose: Dictionary = _splay_edit_build_pose(pose_name)
	var mgr_script: GDScript = load("res://scripts/systems/splay_manager.gd")
	var temp := Node.new()
	temp.set_script(mgr_script)
	add_child(temp)
	temp.save_pose(pose)
	temp.queue_free()
	_splay_edit_pose_data = pose
	print("EDITOR: saved CUSTOM pose '%s'" % pose_name)
	_show_center_flash("CUSTOM SAVED", Color(0.3, 1.0, 0.3))
	_status_label.text = "CUSTOM SAVED"
	_status_label.modulate = Color(0.3, 1.0, 0.3)
	var tween := create_tween()
	tween.tween_interval(1.5)
	tween.tween_callback(func() -> void:
		if is_instance_valid(_status_label):
			_status_label.text = "EDITOR"
			_status_label.modulate = Color(0.3, 0.8, 0.3)
	)


func _draw_splay_edit_overlay() -> void:
	if not is_instance_valid(_splay_edit_creature):
		_overlay.draw_string(ThemeDB.fallback_font, Vector2(400, 300), "No creature found. Press ESC and spawn one first.", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.3, 0.3))
		return

	var origin: Vector2 = _splay_edit_origin
	var font: Font = ThemeDB.fallback_font

	# Draw rotation ring (outer circle for drag-to-rotate)
	var rotate_selected: bool = (_splay_edit_selected_point == "_rotate")
	var ring_col: Color = Color(1.0, 0.7, 0.2, 0.7) if rotate_selected else Color(0.6, 0.5, 0.3, 0.4)
	# Dashed ring at 40px radius
	for seg in range(16):
		if seg % 2 == 1:
			continue
		var a1: float = TAU * float(seg) / 16.0
		var a2: float = TAU * float(seg + 1) / 16.0
		_overlay.draw_arc(origin, 40.0, a1, a2, 4, ring_col, 1.5)
	# Small arrow on the ring to indicate rotation direction
	var arrow_pos: Vector2 = origin + Vector2(40, 0)
	_overlay.draw_line(arrow_pos, arrow_pos + Vector2(-4, -6), ring_col, 1.5)
	_overlay.draw_line(arrow_pos, arrow_pos + Vector2(4, -6), ring_col, 1.5)

	# Draw origin (draggable center)
	var origin_selected: bool = (_splay_edit_selected_point == "_origin")
	var origin_col: Color = Color(1.0, 0.9, 0.3, 0.9) if origin_selected else Color(0.9, 0.5, 0.2, 0.7)
	_overlay.draw_circle(origin, 10.0, origin_col * Color(1, 1, 1, 0.3))
	_overlay.draw_arc(origin, 10.0, 0, TAU, 16, origin_col, 2.0)
	_overlay.draw_string(font, origin + Vector2(-8, 4), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, origin_col)

	# Draw each candidate connection point
	var off_col := Color(0.4, 0.4, 0.4, 0.5)
	var on_col := Color(0.2, 0.9, 0.5, 0.8)
	var sel_col := Color(1.0, 1.0, 0.3, 1.0)
	var cast_col := Color(1.0, 0.4, 0.3, 0.6)
	var endpoint_col := Color(1.0, 0.6, 0.2, 0.8)

	for point_name in _splay_edit_all_points:
		var point_world: Vector2 = _get_splay_point_world(point_name)
		var data: Dictionary = _splay_edit_active.get(point_name, {})
		var enabled: bool = data.get("enabled", false)
		var is_selected: bool = (_splay_edit_selected_point == point_name)

		var col: Color
		if is_selected:
			col = sel_col
		elif enabled:
			col = on_col
		else:
			col = off_col

		# Connection point circle
		var r: float = 10.0 if is_selected else 7.0
		_overlay.draw_circle(point_world, r, col * Color(1, 1, 1, 0.3))
		_overlay.draw_arc(point_world, r, 0, TAU, 12, col, 1.5)

		# Pin indicator
		var is_pinned: bool = _splay_edit_pinned.get(point_name, false)
		if is_pinned:
			# Draw pin icon (small X through the circle)
			_overlay.draw_line(point_world + Vector2(-4, -4), point_world + Vector2(4, 4), Color(1, 0.3, 0.3, 0.7), 1.5)
			_overlay.draw_line(point_world + Vector2(4, -4), point_world + Vector2(-4, 4), Color(1, 0.3, 0.3, 0.7), 1.5)

		# Label
		var label_col: Color = col
		var lt: String = _splay_edit_link_type.get(point_name, "rope")
		var status: String = ""
		if enabled:
			status += " [ON]"
		if is_pinned:
			status += " PIN"
		if lt == "chain":
			status += " CHAIN"
		_overlay.draw_string(font, point_world + Vector2(-25, -r - 6), point_name + status, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, label_col)

		# Cast ray + endpoint — always shown if cast_end exists (dim if disabled, bright if enabled)
		var cast_end: Vector2 = data.get("cast_end", Vector2.ZERO)
		if cast_end != Vector2.ZERO:
			var alpha: float = 1.0 if enabled else 0.3
			var is_chain: bool = _splay_edit_link_type.get(point_name, "rope") == "chain"
			var base_ray_col: Color = Color(0.5, 0.48, 0.45, 0.7) if is_chain else cast_col
			var ray_col: Color = base_ray_col * Color(1, 1, 1, alpha)

			# Dotted line from connection point to cast endpoint
			var ray_dir: Vector2 = (cast_end - point_world).normalized()
			var ray_len: float = point_world.distance_to(cast_end)
			var dash: float = 0.0
			while dash < ray_len:
				var d_start: Vector2 = point_world + ray_dir * dash
				var d_end: Vector2 = point_world + ray_dir * minf(dash + 8.0, ray_len)
				_overlay.draw_line(d_start, d_end, ray_col, 1.5)
				dash += 14.0

			# Arrow at endpoint
			var perp: Vector2 = Vector2(-ray_dir.y, ray_dir.x)
			_overlay.draw_line(cast_end, cast_end - ray_dir * 10 + perp * 5, ray_col, 1.5)
			_overlay.draw_line(cast_end, cast_end - ray_dir * 10 - perp * 5, ray_col, 1.5)

			# Draggable endpoint circle
			var ep_selected: bool = is_selected and _splay_edit_dragging_endpoint
			var ep_alpha: float = 0.8 if enabled else 0.3
			var ep_col: Color = (sel_col if ep_selected else endpoint_col) * Color(1, 1, 1, ep_alpha)
			_overlay.draw_circle(cast_end, 6.0, ep_col * Color(1, 1, 1, 0.5))
			_overlay.draw_arc(cast_end, 6.0, 0, TAU, 8, ep_col, 1.5)

	# Pose name
	var pose_name: String = _splay_edit_pose_data.get("name", "(unsaved)")
	_overlay.draw_string(font, Vector2(10, 50), "Pose: %s" % pose_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.8, 0.3))

	# Active count
	var active_count: int = 0
	for pn in _splay_edit_active:
		if _splay_edit_active[pn].get("enabled", false):
			active_count += 1
	_overlay.draw_string(font, Vector2(10, 66), "Active points: %d / %d" % [active_count, _splay_edit_all_points.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.7, 0.7))

	# Help text
	# Save dialog overlay
	if _splay_save_dialog_active:
		var vp: Vector2 = get_viewport().get_visible_rect().size
		var dx: float = vp.x / 2.0 - 160
		var dy: float = vp.y / 2.0 - 40
		_overlay.draw_rect(Rect2(dx, dy, 320, 80), Color(0.1, 0.1, 0.12, 0.95))
		_overlay.draw_rect(Rect2(dx, dy, 320, 80), Color(0.5, 0.5, 0.3, 0.7), false, 2.0)
		_overlay.draw_string(font, Vector2(dx + 20, dy + 24), "Save Pose: %s" % _splay_edit_pose_data.get("name", "?"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.9, 0.3))

		# Original button
		var o_available: bool = Version.is_source_mode()
		var o_col: Color = Color(0.3, 0.8, 1.0) if o_available else Color(0.3, 0.3, 0.3)
		_overlay.draw_rect(Rect2(dx + 20, dy + 40, 120, 28), o_col * Color(1, 1, 1, 0.2))
		_overlay.draw_rect(Rect2(dx + 20, dy + 40, 120, 28), o_col, false, 1.5)
		# Underline the O
		_overlay.draw_string(font, Vector2(dx + 35, dy + 60), "O", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, o_col)
		_overlay.draw_line(Vector2(dx + 35, dy + 62), Vector2(dx + 45, dy + 62), o_col, 1.5)
		_overlay.draw_string(font, Vector2(dx + 46, dy + 60), "riginal", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, o_col)

		# Custom button
		var c_col := Color(0.3, 1.0, 0.3)
		_overlay.draw_rect(Rect2(dx + 180, dy + 40, 120, 28), c_col * Color(1, 1, 1, 0.2))
		_overlay.draw_rect(Rect2(dx + 180, dy + 40, 120, 28), c_col, false, 1.5)
		_overlay.draw_string(font, Vector2(dx + 200, dy + 60), "C", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, c_col)
		_overlay.draw_line(Vector2(dx + 200, dy + 62), Vector2(dx + 210, dy + 62), c_col, 1.5)
		_overlay.draw_string(font, Vector2(dx + 211, dy + 60), "ustom", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, c_col)

	var mirror_str: String = " [MIRROR]" if _splay_edit_mirror else ""
	var src_str: String = " [DEV]" if Version.is_source_mode() else ""
	var help := "SPLAY EDIT: Click=select  SPACE=toggle  C=rope/chain  P=pin  M=mirror%s  Drag=IK  L/R/U/D=pose  Ctrl+S=save  Esc=back%s" % [mirror_str, src_str]
	_overlay.draw_string(font, Vector2(10, 30), help, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.3, 0.8, 1.0, 0.8))
