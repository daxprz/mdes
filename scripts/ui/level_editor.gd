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

	# Tab to switch modes
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_TAB:
			_mode = ((_mode + 1) % Mode.size()) as Mode
			_selected_idx = -1
			_update_display()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_S and event.ctrl_pressed:
			_save()
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
				# Enter pose edit mode for selected splay
				if _selected_idx >= 0:
					_splay_edit_pose_idx = _selected_idx
					_mode = Mode.SPLAY_EDIT
					_selected_idx = -1
					_update_display()
				get_viewport().set_input_as_handled()
		elif _mode == Mode.SPLAY_EDIT:
			if event.keycode == KEY_ESCAPE:
				# Exit pose edit, back to SPLAY mode
				_mode = Mode.SPLAY
				_selected_idx = _splay_edit_pose_idx
				_splay_edit_pose_idx = -1
				_update_display()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_N:
				_splay_edit_add_connection()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
				_splay_edit_delete_connection()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_S and event.ctrl_pressed:
				_splay_edit_save_pose()
				get_viewport().set_input_as_handled()

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
				_splay_edit_dragging_cast = true
				_try_select_splay_connection(_get_world_pos(event.position))
			else:
				_splay_edit_dragging_cast = false
			get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion:
		if _dragging:
			_do_drag(event.position)
			get_viewport().set_input_as_handled()
		elif _splay_edit_dragging_cast and _mode == Mode.SPLAY_EDIT and _selected_idx >= 0:
			_splay_edit_update_cast_dir(_get_world_pos(event.position))
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


func _stop_drag() -> void:
	if _dragging:
		# Live refresh on drag release
		config_changed.emit(_config)
	_dragging = false
	_drag_handle = -1


func _do_drag(screen_pos: Vector2) -> void:
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
	LevelConfig.save_level(_level_name, _config)
	config_changed.emit(_config)
	_status_label.text = "SAVED!"
	_status_label.modulate = Color(0.3, 1.0, 0.3)
	_show_center_flash("SAVED", Color(0.3, 1.0, 0.3))
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
		splays[_selected_idx]["pos"] = [world_pos.x, world_pos.y]


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
		config_changed.emit(_config)
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
	config_changed.emit(_config)
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
	config_changed.emit(_config)
	_update_display()


func _draw_splay_overlay() -> void:
	var splays: Array = _get_splays()
	var splay_col := Color(0.9, 0.4, 0.2, 0.7)
	var selected_col := Color(1.0, 0.8, 0.2, 0.9)

	for i in range(splays.size()):
		var s: Dictionary = splays[i]
		var p: Array = s.get("pos", [960, 500])
		var pos := Vector2(p[0], p[1])
		var is_selected: bool = (i == _selected_idx)
		var col: Color = selected_col if is_selected else splay_col
		var rot: float = s.get("rotation", 0)

		# Body marker
		_overlay.draw_circle(pos, 16.0 if is_selected else 12.0, col * Color(1, 1, 1, 0.4))
		_overlay.draw_arc(pos, 16.0, 0, TAU, 16, col, 1.5)

		# Rotation arrow
		var rot_rad: float = deg_to_rad(rot)
		var arrow_end: Vector2 = pos + Vector2(cos(rot_rad), sin(rot_rad)) * 30.0
		_overlay.draw_line(pos, arrow_end, col, 2.0)
		var perp: Vector2 = Vector2(-sin(rot_rad), cos(rot_rad))
		_overlay.draw_line(arrow_end, arrow_end - Vector2(cos(rot_rad), sin(rot_rad)) * 8 + perp * 5, col, 1.5)
		_overlay.draw_line(arrow_end, arrow_end - Vector2(cos(rot_rad), sin(rot_rad)) * 8 - perp * 5, col, 1.5)

		# Labels
		var pose_name: String = s.get("pose", "?")
		var behavior: String = s.get("behavior", "?")
		_overlay.draw_string(ThemeDB.fallback_font, pos + Vector2(-30, -22), pose_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
		_overlay.draw_string(ThemeDB.fallback_font, pos + Vector2(-30, -10), behavior, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, col * Color(1, 1, 1, 0.7))
		_overlay.draw_string(ThemeDB.fallback_font, pos + Vector2(-30, 26), "rot:%.0f" % rot, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, col * Color(1, 1, 1, 0.5))

	# Help text
	if _active:
		var physics_str: String = " [PHYSICS ON]" if _splay_physics_preview else ""
		var help := "SPLAY: N=add  P=library  `=physics%s  Del=delete  L/R=rotate  U/D=pose  B=behavior  E=edit  Drag=move" % physics_str
		_overlay.draw_string(ThemeDB.fallback_font, Vector2(10, 30), help, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.9, 0.7, 0.3, 0.8))


# -- Splay Pose Editing (SPLAY_EDIT mode) -------------------------------------

func _get_editing_pose() -> Dictionary:
	## Get the pose data for the splay instance being edited.
	if _splay_edit_pose_idx < 0:
		return {}
	var splays: Array = _get_splays()
	if _splay_edit_pose_idx >= splays.size():
		return {}
	var splay_inst: Dictionary = splays[_splay_edit_pose_idx]
	var pose_name: String = splay_inst.get("pose", "")
	if _splay_edit_pose_data.is_empty() or _splay_edit_pose_data.get("name", "") != pose_name:
		# Load the pose
		var mgr_script: GDScript = load("res://scripts/systems/splay_manager.gd")
		var temp := Node.new()
		temp.set_script(mgr_script)
		add_child(temp)
		_splay_edit_pose_data = temp.load_pose(pose_name).duplicate(true)
		temp.queue_free()
	return _splay_edit_pose_data


func _get_editing_origin() -> Vector2:
	var splays: Array = _get_splays()
	if _splay_edit_pose_idx >= 0 and _splay_edit_pose_idx < splays.size():
		var p: Array = splays[_splay_edit_pose_idx].get("pos", [960, 500])
		return Vector2(p[0], p[1])
	return Vector2(960, 500)


func _try_select_splay_connection(world_pos: Vector2) -> void:
	var pose: Dictionary = _get_editing_pose()
	if pose.is_empty():
		return
	var origin: Vector2 = _get_editing_origin()
	var connections: Array = pose.get("connections", [])
	for i in range(connections.size()):
		var rel: Array = connections[i].get("relative_pos", [0, 0])
		var conn_world: Vector2 = origin + Vector2(rel[0], rel[1])
		if world_pos.distance_to(conn_world) < 20.0:
			_selected_idx = i
			_dragging = true
			return
	_selected_idx = -1


func _drag_splay_connection(world_pos: Vector2) -> void:
	if _selected_idx < 0:
		return
	var pose: Dictionary = _get_editing_pose()
	if pose.is_empty():
		return
	var origin: Vector2 = _get_editing_origin()
	var connections: Array = pose.get("connections", [])
	if _selected_idx < connections.size():
		var rel: Vector2 = world_pos - origin
		connections[_selected_idx]["relative_pos"] = [rel.x, rel.y]


func _splay_edit_add_connection() -> void:
	var pose: Dictionary = _get_editing_pose()
	if pose.is_empty():
		return
	var connections: Array = pose.get("connections", [])
	# Find an attachment point not yet used
	var all_points := ["head", "tail_tip", "shoulders", "waist"]
	var used: Array[String] = []
	for c in connections:
		used.append(c.get("point", ""))
	var new_point: String = ""
	for p in all_points:
		if p not in used:
			new_point = p
			break
	if new_point.is_empty():
		return  # All points already used
	connections.append({
		"point": new_point,
		"relative_pos": [0, 0],
		"cast_dir": [0, -1],
	})
	_selected_idx = connections.size() - 1
	_update_display()


func _splay_edit_delete_connection() -> void:
	if _selected_idx < 0:
		return
	var pose: Dictionary = _get_editing_pose()
	if pose.is_empty():
		return
	var connections: Array = pose.get("connections", [])
	if _selected_idx < connections.size():
		connections.remove_at(_selected_idx)
		_selected_idx = -1
		_update_display()


func _splay_edit_update_cast_dir(world_pos: Vector2) -> void:
	## Right-drag: set cast direction on selected connection point.
	var pose: Dictionary = _get_editing_pose()
	if pose.is_empty() or _selected_idx < 0:
		return
	var origin: Vector2 = _get_editing_origin()
	var connections: Array = pose.get("connections", [])
	if _selected_idx >= connections.size():
		return
	var rel: Array = connections[_selected_idx].get("relative_pos", [0, 0])
	var conn_pos: Vector2 = origin + Vector2(rel[0], rel[1])
	var dir: Vector2 = (world_pos - conn_pos).normalized()
	if dir.length() < 0.1:
		dir = Vector2(0, -1)
	connections[_selected_idx]["cast_dir"] = [dir.x, dir.y]
	_update_display()


func _splay_edit_save_pose() -> void:
	var pose: Dictionary = _get_editing_pose()
	if pose.is_empty():
		return
	var mgr_script: GDScript = load("res://scripts/systems/splay_manager.gd")
	var temp := Node.new()
	temp.set_script(mgr_script)
	add_child(temp)
	temp.save_pose(pose)
	temp.queue_free()
	print("EDITOR: saved splay pose '%s'" % pose.get("name", "?"))


func _draw_splay_edit_overlay() -> void:
	var pose: Dictionary = _get_editing_pose()
	if pose.is_empty():
		return
	var origin: Vector2 = _get_editing_origin()
	var connections: Array = pose.get("connections", [])

	# Draw origin marker
	_overlay.draw_circle(origin, 8.0, Color(0.9, 0.5, 0.2, 0.5))
	_overlay.draw_arc(origin, 8.0, 0, TAU, 16, Color(0.9, 0.5, 0.2, 0.8), 1.5)
	_overlay.draw_string(ThemeDB.fallback_font, origin + Vector2(-20, -14), pose.get("name", "?"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.8, 0.3))

	var conn_col := Color(0.3, 0.8, 1.0, 0.8)
	var sel_col := Color(1.0, 1.0, 0.3, 1.0)
	var cast_col := Color(1.0, 0.4, 0.3, 0.5)

	for i in range(connections.size()):
		var c: Dictionary = connections[i]
		var rel: Array = c.get("relative_pos", [0, 0])
		var cast: Array = c.get("cast_dir", [0, -1])
		var point_name: String = c.get("point", "?")
		var conn_pos: Vector2 = origin + Vector2(rel[0], rel[1])
		var cast_dir: Vector2 = Vector2(cast[0], cast[1]).normalized()
		var is_selected: bool = (i == _selected_idx)
		var col: Color = sel_col if is_selected else conn_col

		# Connection point handle
		_overlay.draw_circle(conn_pos, 8.0 if is_selected else 6.0, col * Color(1, 1, 1, 0.5))
		_overlay.draw_arc(conn_pos, 8.0, 0, TAU, 12, col, 1.5)

		# Line from origin to connection
		_overlay.draw_line(origin, conn_pos, col * Color(1, 1, 1, 0.3), 1.0)

		# Cast direction arrow
		var cast_end: Vector2 = conn_pos + cast_dir * 60.0
		_overlay.draw_line(conn_pos, cast_end, cast_col, 2.0)
		var perp: Vector2 = Vector2(-cast_dir.y, cast_dir.x)
		_overlay.draw_line(cast_end, cast_end - cast_dir * 8 + perp * 4, cast_col, 1.5)
		_overlay.draw_line(cast_end, cast_end - cast_dir * 8 - perp * 4, cast_col, 1.5)

		# Cast direction dotted preview (where raycast would hit)
		var dash_pos: float = 60.0
		while dash_pos < 400.0:
			var d_start: Vector2 = conn_pos + cast_dir * dash_pos
			var d_end: Vector2 = conn_pos + cast_dir * minf(dash_pos + 6.0, 400.0)
			_overlay.draw_line(d_start, d_end, cast_col * Color(1, 1, 1, 0.3), 1.0)
			dash_pos += 12.0

		# Label
		_overlay.draw_string(ThemeDB.fallback_font, conn_pos + Vector2(-20, -14), point_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, col)

	# Help text
	if _active:
		var help := "SPLAY EDIT: Drag=move point  N=add  Del=delete  Ctrl+S=save pose  Esc=back"
		_overlay.draw_string(ThemeDB.fallback_font, Vector2(10, 30), help, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.3, 0.8, 1.0, 0.8))
