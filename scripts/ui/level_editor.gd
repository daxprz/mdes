extends CanvasLayer

## Level editor overlay — toggled with Ctrl+E.
## Modes: spawn areas, seeds, platforms, portal.
## Mouse-driven vertex editing, saves to user://levels/.

enum Mode { SPAWN_AREAS, SEEDS, PLATFORMS, PORTAL }

const MODE_NAMES := ["Spawn Areas", "Seeds", "Platforms", "Portal"]
const MODE_COLORS := [
	Color(1.0, 0.9, 0.2, 0.3),   # Spawn areas: yellow
	Color(0.2, 0.9, 0.5, 0.3),   # Seeds: green
	Color(0.4, 0.6, 1.0, 0.3),   # Platforms: blue
	Color(0.9, 0.3, 0.9, 0.3),   # Portal: purple
]

var _active := false
var _mode: Mode = Mode.SPAWN_AREAS
var _level_name: String = ""
var _config: Dictionary = {}
var _selected_idx: int = -1
var _dragging := false
var _drag_handle: int = -1  # Which corner/handle is being dragged
var _drag_item_type: String = ""
var _nav_cooldown: float = 0.0

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

	# Mouse input for dragging
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_start_drag(event.position)
			else:
				_stop_drag()
			get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion and _dragging:
		_do_drag(event.position)
		get_viewport().set_input_as_handled()


func _update_display() -> void:
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
		Mode.SEEDS:
			_try_select_scenery(world_pos)
		Mode.PLATFORMS:
			_try_select_platform(world_pos)
		Mode.PORTAL:
			_try_select_portal(world_pos)


func _stop_drag() -> void:
	_dragging = false
	_drag_handle = -1


func _do_drag(screen_pos: Vector2) -> void:
	var world_pos: Vector2 = _get_world_pos(screen_pos)

	match _mode:
		Mode.SPAWN_AREAS:
			_drag_zone(world_pos)
		Mode.SEEDS:
			_drag_scenery(world_pos)
		Mode.PLATFORMS:
			_drag_platform(world_pos)
		Mode.PORTAL:
			_drag_portal(world_pos)


# -- Spawn Area editing --------------------------------------------------------

func _try_select_zone(world_pos: Vector2) -> void:
	var ff_zones: Array = _config.get("spawn_zones", {}).get("fireflies", [])
	for i in range(ff_zones.size()):
		var r: Array = ff_zones[i].get("rect", [0, 0, 100, 100])
		var rect := Rect2(r[0], r[1], r[2], r[3])
		# Check corners (8px handles)
		var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
		for ci in range(4):
			if world_pos.distance_to(corners[ci]) < 15.0:
				_selected_idx = i
				_drag_handle = ci
				_drag_item_type = "firefly_zone"
				_dragging = true
				return
		# Check if clicking inside rect (select without drag handle)
		if rect.has_point(world_pos):
			_selected_idx = i
			_drag_item_type = "firefly_zone"
			_drag_handle = -1  # Move entire zone
			_dragging = true
			return


func _drag_zone(world_pos: Vector2) -> void:
	if _selected_idx < 0 or _drag_item_type != "firefly_zone":
		return
	var ff_zones: Array = _config.get("spawn_zones", {}).get("fireflies", [])
	if _selected_idx >= ff_zones.size():
		return
	var r: Array = ff_zones[_selected_idx]["rect"]
	if _drag_handle >= 0:
		# Drag specific corner
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


# -- Save / Reset --------------------------------------------------------------

func _save() -> void:
	LevelConfig.save_level(_level_name, _config)
	_status_label.text = "SAVED!"
	_status_label.modulate = Color(0.3, 1.0, 0.3)
	var tween := create_tween()
	tween.tween_interval(1.5)
	tween.tween_callback(func() -> void:
		_status_label.text = "EDITOR"
		_status_label.modulate = Color(0.3, 0.8, 0.3)
	)


func _reset() -> void:
	LevelConfig.reset_level(_level_name)
	_config = LevelConfig.load_level(_level_name).duplicate(true)
	_status_label.text = "RESET!"
	_status_label.modulate = Color(1.0, 0.5, 0.3)
	var tween := create_tween()
	tween.tween_interval(1.5)
	tween.tween_callback(func() -> void:
		_status_label.text = "EDITOR"
		_status_label.modulate = Color(0.3, 0.8, 0.3)
	)


# -- Overlay drawing -----------------------------------------------------------

func _draw_overlay() -> void:
	if not _active or not _overlay:
		return

	match _mode:
		Mode.SPAWN_AREAS:
			_draw_spawn_zones()
		Mode.SEEDS:
			_draw_seed_markers()
		Mode.PLATFORMS:
			_draw_platform_outlines()
		Mode.PORTAL:
			_draw_portal_overlay()


func _draw_spawn_zones() -> void:
	var ff_zones: Array = _config.get("spawn_zones", {}).get("fireflies", [])
	for i in range(ff_zones.size()):
		var r: Array = ff_zones[i].get("rect", [0, 0, 100, 100])
		var rect := Rect2(r[0], r[1], r[2], r[3])
		var col := Color(1.0, 0.9, 0.2, 0.15) if i != _selected_idx else Color(1.0, 0.9, 0.2, 0.35)
		_overlay.draw_rect(rect, col)
		_overlay.draw_rect(rect, Color(1.0, 0.9, 0.2, 0.6), false, 1.5)
		# Corner handles
		var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
		for c in corners:
			_overlay.draw_rect(Rect2(c - Vector2(4, 4), Vector2(8, 8)), Color(1.0, 0.8, 0.2, 0.8))
		# Weight label
		var weight: float = ff_zones[i].get("weight", 1.0)
		_overlay.draw_string(ThemeDB.fallback_font, rect.position + Vector2(4, 14), "w:%.1f" % weight, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.9, 0.3))

	var bat_zones: Array = _config.get("spawn_zones", {}).get("bats", [])
	for bz in bat_zones:
		var r: Array = bz.get("rect", [0, 0, 100, 100])
		var rect := Rect2(r[0], r[1], r[2], r[3])
		_overlay.draw_rect(rect, Color(0.7, 0.2, 0.9, 0.1))
		_overlay.draw_rect(rect, Color(0.7, 0.2, 0.9, 0.4), false, 1.5)


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
