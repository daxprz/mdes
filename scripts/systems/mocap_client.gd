extends Node

## Mocap Bridge Client with calibration HUD and configurable mapping.

# -- Connection --
var _stream: StreamPeerTCP = null
var _connected: bool = false
var _buffer: String = ""
var _target_monster: Node2D = null
var _port: int = 7777
var _last_frame: Dictionary = {}
var _active: bool = false
var _reconnect_timer: float = 0.0

# -- Smoothing --
var _smooth_points: Dictionary = {}
const SMOOTH_WEIGHT := 0.15

# -- Last known --
var _last_known: Dictionary = {}

# -- Pinned world positions (captured on first apply, never change) --
var _pinned: bool = false
var _pin_spine2: Vector2 = Vector2.ZERO  # World-space spine[2] — the fixed rear anchor
var _pin_spine1: Vector2 = Vector2.ZERO  # World-space spine[1] — the pin point
var _pin_facing: float = 1.0            # Locked facing direction
var _pin_scale: float = 0.0             # Locked scale factor (computed once)

# -- T-pose auto-detection --
var _tpose_detect_timer: float = 0.0
var _tpose_countdown: float = -1.0  # -1 = not counting, 3..0 = counting down
const TPOSE_ARM_HORIZONTAL_THRESHOLD := 0.08  # Max Y difference between shoulder and wrist
const TPOSE_ARM_EXTENDED_THRESHOLD := 0.15    # Min X distance from shoulder to wrist
const TPOSE_HOLD_TIME := 1.5                   # Seconds of T-pose before countdown starts

# -- Configuration (adjustable via debug drawer sliders) --
var cfg_stance_angle: float = 0.0  # 0=horizontal (quadruped), 90=vertical (standing). Default 0
var cfg_smooth_weight: float = 0.15  # Temporal smoothing blend
var cfg_x_scale: float = 1.0  # Horizontal extent multiplier
var cfg_y_scale: float = 1.0  # Vertical extent multiplier
var cfg_depth_blend: float = 0.25  # How much mocap X bleeds into game X (vs pure depth)
var cfg_arm_scale: float = 1.0  # Arm length multiplier

const FABRIK_ITERS := 4

# -- Calibration --
enum CalibState { IDLE, WAITING_SETTLE, COUNTDOWN, CAPTURE, FLASH, DONE }
var _cal_state: CalibState = CalibState.IDLE
var _cal_pose_idx: int = 0
var _cal_timer: float = 0.0
var _cal_settle_frames: Array = []
var _cal_captures: Dictionary = {}
var _calibrated: bool = false
var _cal_flash_timer: float = 0.0
var _cal_too_much_movement: bool = false
var _cal_movement_reset_timer: float = 0.0
var _cal_all_points_timer: float = 0.0  # How long ALL required landmarks have been present

const CAL_MOVEMENT_THRESHOLD := 0.06  # Max total movement across key points to detect "too much"
const CAL_MOVEMENT_RESET_TIME := 2.0  # Show warning for this long then reset
const CAL_ALL_POINTS_REQUIRED := 5.0  # Must see ALL landmarks for this many seconds before settling

# Required landmarks for calibration — must ALL be present
const CAL_REQUIRED_LANDMARKS: Array = [
	"nose", "left_shoulder", "right_shoulder", "left_elbow", "right_elbow",
	"left_wrist", "right_wrist", "left_hip", "right_hip",
]

# Calibration results
var _cal_torso_len: float = 0.15
var _cal_arm_span: float = 0.0
var _cal_upper_arm: float = 0.0
var _cal_lower_arm: float = 0.0
var _cal_shoulder_width: float = 0.0
var _cal_hip_width: float = 0.0
var _cal_depth_sign: float = -1.0

const CAL_POSES: Array = [
	{"name": "STAND ON MARKS", "instruction": "Stand with your FEET on the 2 markers, angled 45 degrees to the camera",
	 "detail": "Relax with hands at your sides. Look at the lamp."},
	{"name": "T-POSE", "instruction": "Make your body in the shape of a 'T' — arms straight out",
	 "detail": "Keep your feet on the marks. Arms level with shoulders, palms down."},
	{"name": "ARMS FORWARD", "instruction": "Point both arms straight ahead (toward the lamp)",
	 "detail": "Arms parallel, pointing in your forward direction (not at camera)."},
	{"name": "REACH UP", "instruction": "Reach both arms straight up above your head",
	 "detail": "Stretch tall. This calibrates vertical range."},
]
const CAL_SETTLE_FRAMES := 20
const CAL_SETTLE_THRESHOLD := 0.008
const CAL_COUNTDOWN := 3.0
const CAL_CAPTURE_FRAMES := 15
const CAL_FLASH_DURATION := 0.15

# -- HUD overlays --
var _hud_layer: CanvasLayer = null
var _hud_control: Control = null
var _cfg_layer: CanvasLayer = null
var _cfg_control: Control = null
var _cfg_visible: bool = false
var _cfg_dragging: String = ""
var _cfg_panel_x: float = 0.0
var _cfg_panel_y: float = 0.0
var _cfg_panel_w: float = 320.0
var _cfg_panel_h: float = 300.0


func _ready() -> void:
	set_process(false)
	set_process_input(true)  # Ensure _input is called for mouse diagnostics


func connect_to_bridge(port: int = 7777) -> String:
	_port = port
	if _stream:
		_stream.disconnect_from_host()
	_stream = StreamPeerTCP.new()
	var err := _stream.connect_to_host("127.0.0.1", port)
	if err != OK:
		return "ERR: failed to connect (err=%d)" % err
	_active = true
	_connected = false
	_buffer = ""
	_smooth_points.clear()
	_last_known.clear()
	set_process(true)
	set_process_input(true)
	return "OK: connecting to mocap bridge on 127.0.0.1:%d..." % port


func start_calibration() -> String:
	if not _connected:
		return "ERR: not connected to bridge"
	_cal_state = CalibState.WAITING_SETTLE
	_cal_pose_idx = 0
	_cal_timer = 0.0
	_cal_settle_frames.clear()
	_cal_captures.clear()
	_calibrated = false
	_cal_too_much_movement = false
	_cal_all_points_timer = 0.0
	_create_hud()
	return "OK: calibration started"


func disconnect_bridge() -> String:
	_active = false
	_connected = false
	if _stream:
		_stream.disconnect_from_host()
		_stream = null
	_target_monster = null
	_destroy_hud()
	set_process(false)
	return "OK: disconnected"


func get_status() -> String:
	if not _active:
		return "mocap: inactive"
	var state: String = "connected" if _connected else "connecting"
	var cal_str: String = " calibrated" if _calibrated else ""
	if _cal_state != CalibState.IDLE:
		cal_str = " calibrating[%s]" % CAL_POSES[_cal_pose_idx]["name"]
	var mn: String = "none"
	if is_instance_valid(_target_monster):
		mn = _target_monster.entity_id if "entity_id" in _target_monster else _target_monster.name
	return "mocap: %s port=%d target=%s angle=%.0f%s" % [state, _port, mn, cfg_stance_angle, cal_str]


var _cfg_mouse_was_pressed: bool = false

func _poll_cfg_mouse() -> void:
	## Poll mouse state every frame for the config panel.
	## This works regardless of gui_input routing issues.
	var mouse_pos: Vector2 = _cfg_control.get_global_mouse_position()
	var lx: float = mouse_pos.x - _cfg_control.global_position.x
	var ly: float = mouse_pos.y - _cfg_control.global_position.y
	var in_bounds: bool = lx >= 0 and lx <= _cfg_control.size.x and ly >= 0 and ly <= _cfg_control.size.y
	var pressed: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var just_pressed: bool = pressed and not _cfg_mouse_was_pressed
	var just_released: bool = not pressed and _cfg_mouse_was_pressed
	_cfg_mouse_was_pressed = pressed

	var track_x: float = 110.0
	var track_w: float = 140.0
	var btn_h: float = 40.0

	if just_pressed and in_bounds:
		# RESET button
		if ly < btn_h:
			_reset_scene()
			return
		# Sliders
		var row_y: float = _cfg_panel_y + 40.0
		for s in CFG_SLIDERS:
			if ly >= row_y and ly < row_y + 30:
				_cfg_dragging = s["key"]
				_cfg_apply_drag(s, lx, track_x, track_w)
				return
			row_y += 36.0

	if just_released and not _cfg_dragging.is_empty():
		_cfg_dragging = ""

	if pressed and not _cfg_dragging.is_empty():
		_cfg_apply_drag_by_key(_cfg_dragging, lx, track_x, track_w)


func _cfg_apply_drag_by_key(key: String, local_x: float, track_x: float, track_w: float) -> void:
	for s in CFG_SLIDERS:
		if s["key"] == key:
			_cfg_apply_drag(s, local_x, track_x, track_w)
			return


func _on_cfg_input(event: InputEvent) -> void:
	## gui_input callback on the sized Control. Coords are LOCAL to the control.
	if not _cfg_visible:
		return

	var track_x: float = 110.0
	var track_w: float = 140.0
	var btn_h: float = 40.0

	if event is InputEventMouseButton:
		var lx: float = event.position.x
		var ly: float = event.position.y

		DebugOverlay.log("input/mouse_clicks", null,
			"MOCAP_CFG: btn=%d pressed=%s local=(%.0f,%.0f) drag='%s'",
			[event.button_index, str(event.pressed), lx, ly, _cfg_dragging])

		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			# RESET button at top (y 0..btn_h)
			if ly < btn_h:
				DebugOverlay.log("input/mouse_clicks", null, "  → RESET")
				_reset_scene()
				_cfg_control.accept_event()
				_cfg_control.queue_redraw()
				return

			# Slider rows
			var row_y: float = _cfg_panel_y + 40.0
			_cfg_dragging = ""
			for s in CFG_SLIDERS:
				if ly >= row_y and ly < row_y + 30:
					_cfg_dragging = s["key"]
					DebugOverlay.log("input/mouse_clicks", null, "  → SLIDER '%s'", [s["key"]])
					_cfg_apply_drag(s, lx, track_x, track_w)
					_cfg_control.accept_event()
					_cfg_control.queue_redraw()
					return
				row_y += 36.0

		elif not event.pressed:
			if not _cfg_dragging.is_empty():
				_cfg_dragging = ""
				_cfg_control.accept_event()
				_cfg_control.queue_redraw()
				return

	elif event is InputEventMouseMotion and not _cfg_dragging.is_empty():
		for s in CFG_SLIDERS:
			if s["key"] == _cfg_dragging:
				_cfg_apply_drag(s, event.position.x, track_x, track_w)
				break
		_cfg_control.accept_event()
		_cfg_control.queue_redraw()


func _process(delta: float) -> void:
	if not _active or not _stream:
		return
	_stream.poll()
	var tcp_status := _stream.get_status()
	if tcp_status == StreamPeerTCP.STATUS_CONNECTED:
		if not _connected:
			_connected = true
			print("MOCAP: connected on port %d" % _port)
		_read_data()
	elif tcp_status == StreamPeerTCP.STATUS_CONNECTING:
		pass
	else:
		if _connected:
			print("MOCAP: connection lost")
			_connected = false
		_reconnect_timer += delta
		if _reconnect_timer > 2.0:
			_reconnect_timer = 0.0
			_stream.disconnect_from_host()
			_stream.connect_to_host("127.0.0.1", _port)

	if not _connected:
		return

	# Always try to find target monster, even before first frame arrives
	if not is_instance_valid(_target_monster):
		_target_monster = _find_target_monster()

	if _last_frame.is_empty():
		return

	if _cal_state != CalibState.IDLE:
		_process_calibration(delta)
		if _hud_control:
			_hud_control.queue_redraw()
		return

	_apply_to_monster()

	# Config panel: poll mouse state directly (gui_input doesn't work on CanvasLayer Controls)
	if _cfg_control and _cfg_visible:
		_poll_cfg_mouse()
		_cfg_control.queue_redraw()


func _read_data() -> void:
	var available := _stream.get_available_bytes()
	if available <= 0:
		return
	var data := _stream.get_utf8_string(available)
	_buffer += data
	while _buffer.contains("\n"):
		var nl := _buffer.find("\n")
		var line := _buffer.substr(0, nl)
		_buffer = _buffer.substr(nl + 1)
		if line.strip_edges().is_empty():
			continue
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary:
			_last_frame = parsed
			_last_frame["recv_time"] = Time.get_ticks_msec() / 1000.0


# -- Calibration HUD -----------------------------------------------------------

func _create_hud() -> void:
	_destroy_hud()
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 90
	add_child(_hud_layer)
	_hud_control = Control.new()
	_hud_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_control.draw.connect(_draw_cal_hud)
	_hud_layer.add_child(_hud_control)


func _destroy_hud() -> void:
	if _hud_layer:
		_hud_layer.queue_free()
		_hud_layer = null
		_hud_control = null


func _draw_cal_hud() -> void:
	if not _hud_control or _cal_state == CalibState.IDLE:
		return
	var vp: Vector2 = _hud_control.get_viewport_rect().size
	var font: Font = ThemeDB.fallback_font
	var w: float = vp.x
	var h: float = vp.y
	var c: Control = _hud_control  # Shorthand

	# Dim background
	c.draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.5))

	# Flash
	if _cal_state == CalibState.FLASH:
		var flash_alpha: float = _cal_flash_timer / CAL_FLASH_DURATION
		c.draw_rect(Rect2(0, 0, w, h), Color(1, 1, 1, flash_alpha * 0.8))
		return

	# Too-much-movement warning
	if _cal_too_much_movement:
		c.draw_rect(Rect2(0, 0, w, h), Color(0.3, 0.0, 0.0, 0.3))
		c.draw_string(font, Vector2(0, h * 0.4), "TOO MUCH MOVEMENT",
			HORIZONTAL_ALIGNMENT_CENTER, int(w), 48, Color(1, 0.2, 0.1))
		c.draw_string(font, Vector2(0, h * 0.4 + 50), "Hold still and try again...",
			HORIZONTAL_ALIGNMENT_CENTER, int(w), 24, Color(1, 0.6, 0.5))
		return

	var pose: Dictionary = CAL_POSES[_cal_pose_idx]

	# -- TOP: Giant pose name (centered) --
	c.draw_string(font, Vector2(0, 70), pose["name"],
		HORIZONTAL_ALIGNMENT_CENTER, int(w), 48, Color(1.0, 0.9, 0.2))

	# -- Below: Instructions at 75% size (centered) --
	c.draw_string(font, Vector2(0, 130), pose["instruction"],
		HORIZONTAL_ALIGNMENT_CENTER, int(w), 32, Color(1, 1, 1, 0.9))
	var detail_text: String = pose.get("detail", "")
	if not detail_text.is_empty():
		c.draw_string(font, Vector2(0, 170), detail_text,
			HORIZONTAL_ALIGNMENT_CENTER, int(w), 20, Color(0.7, 0.7, 0.7))

	# -- Left side: status data --
	var sx: float = 40
	var sy: float = 240
	var ss: int = 14
	var sc: Color = Color(0.5, 0.9, 0.5)
	c.draw_string(font, Vector2(sx, sy), "Pose %d / %d" % [_cal_pose_idx + 1, CAL_POSES.size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, ss, sc)
	sy += 22

	match _cal_state:
		CalibState.WAITING_SETTLE:
			if _cal_all_points_timer < CAL_ALL_POINTS_REQUIRED:
				# Still waiting for all landmarks to be visible
				var pts_progress: float = _cal_all_points_timer / CAL_ALL_POINTS_REQUIRED
				c.draw_string(font, Vector2(sx, sy), "Detecting body: %.0f%%" % (pts_progress * 100),
					HORIZONTAL_ALIGNMENT_LEFT, -1, ss, Color(0.8, 0.7, 0.3))
				sy += 20
				c.draw_rect(Rect2(sx, sy, 200, 12), Color(0.2, 0.2, 0.2))
				c.draw_rect(Rect2(sx, sy, 200 * pts_progress, 12), Color(0.8, 0.7, 0.2))
				sy += 20
				c.draw_string(font, Vector2(sx, sy), "Make sure your full body is visible",
					HORIZONTAL_ALIGNMENT_LEFT, -1, ss, Color(0.6, 0.6, 0.4))
			else:
				var progress: float = float(_cal_settle_frames.size()) / float(CAL_SETTLE_FRAMES)
				c.draw_string(font, Vector2(sx, sy), "Stability: %.0f%%" % (progress * 100),
					HORIZONTAL_ALIGNMENT_LEFT, -1, ss, sc)
				sy += 20
				c.draw_rect(Rect2(sx, sy, 200, 12), Color(0.2, 0.2, 0.2))
				c.draw_rect(Rect2(sx, sy, 200 * progress, 12), Color(0.3, 0.9, 0.3))
				sy += 20
				c.draw_string(font, Vector2(sx, sy), "Hold still...",
					HORIZONTAL_ALIGNMENT_LEFT, -1, ss, Color(0.8, 0.8, 0.3))

		CalibState.COUNTDOWN:
			c.draw_string(font, Vector2(sx, sy), "LOCKED — capturing in...",
				HORIZONTAL_ALIGNMENT_LEFT, -1, ss, Color(0.3, 1.0, 0.5))

		CalibState.CAPTURE:
			var cap_progress: float = float(_cal_settle_frames.size()) / float(CAL_CAPTURE_FRAMES)
			c.draw_string(font, Vector2(sx, sy), "Capturing: %.0f%%" % (cap_progress * 100),
				HORIZONTAL_ALIGNMENT_LEFT, -1, ss, sc)
			sy += 20
			c.draw_rect(Rect2(sx, sy, 200, 12), Color(0.2, 0.2, 0.2))
			c.draw_rect(Rect2(sx, sy, 200 * cap_progress, 12), Color(0.2, 0.6, 1.0))

	# -- Right side: captured poses --
	var rx: float = w - 250
	var ry: float = 240
	if not _cal_captures.is_empty():
		c.draw_string(font, Vector2(rx, ry), "Captured:",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.5, 0.8, 1.0))
		ry += 20
		for cap_name in _cal_captures:
			c.draw_string(font, Vector2(rx + 10, ry), cap_name,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.4, 0.9, 0.4))
			ry += 18

	# -- Bottom-right: GIANT countdown --
	if _cal_state == CalibState.COUNTDOWN:
		var count_num: int = int(ceilf(_cal_timer))
		var count_col: Color
		match count_num:
			3: count_col = Color(1, 1, 1)
			2: count_col = Color(1, 0.9, 0.3)
			1: count_col = Color(1, 0.3, 0.1)
			_: count_col = Color(1, 0.1, 0.05)
		c.draw_string(font, Vector2(w - 220, h - 60), str(count_num),
			HORIZONTAL_ALIGNMENT_CENTER, 200, 140, count_col)

	# -- Bottom center: progress dots --
	var dot_y: float = h - 30
	for i in range(CAL_POSES.size()):
		var dot_x: float = w * 0.5 + (i - CAL_POSES.size() * 0.5 + 0.5) * 40
		var dot_col: Color
		if i < _cal_pose_idx:
			dot_col = Color(0.3, 0.9, 0.3)
		elif i == _cal_pose_idx:
			dot_col = Color(1.0, 0.9, 0.2)
		else:
			dot_col = Color(0.3, 0.3, 0.3)
		c.draw_circle(Vector2(dot_x, dot_y), 8, dot_col)


# -- Config Panel (pop-out sliders) --------------------------------------------

const CFG_SLIDERS: Array = [
	{"key": "angle", "label": "Spine Angle", "min": 0.0, "max": 90.0, "field": "cfg_stance_angle"},
	{"key": "smooth", "label": "Smoothing", "min": 0.01, "max": 0.5, "field": "cfg_smooth_weight"},
	{"key": "xscale", "label": "X Scale", "min": 0.1, "max": 3.0, "field": "cfg_x_scale"},
	{"key": "yscale", "label": "Y Scale", "min": 0.1, "max": 3.0, "field": "cfg_y_scale"},
	{"key": "depth", "label": "Depth Blend", "min": -1.0, "max": 1.0, "field": "cfg_depth_blend"},
	{"key": "armscale", "label": "Arm Scale", "min": 0.5, "max": 3.0, "field": "cfg_arm_scale"},
]

func toggle_config_panel() -> String:
	_cfg_visible = not _cfg_visible
	if _cfg_visible:
		_create_cfg_panel()
		set_process_input(true)
		return "OK: mocap config panel shown"
	else:
		_destroy_cfg_panel()
		return "OK: mocap config panel hidden"


func _create_cfg_panel() -> void:
	_destroy_cfg_panel()
	_cfg_layer = CanvasLayer.new()
	_cfg_layer.layer = 95
	add_child(_cfg_layer)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_cfg_panel_w = 320.0
	_cfg_panel_h = 50.0 + CFG_SLIDERS.size() * 36.0
	_cfg_panel_x = vp.x - _cfg_panel_w - 20
	_cfg_panel_y = vp.y - _cfg_panel_h - 100
	# Sized control covering exactly the button + panel area (not full screen)
	var btn_h: float = 48.0  # Button height + gap
	var total_h: float = btn_h + _cfg_panel_h
	_cfg_control = Control.new()
	_cfg_control.position = Vector2(_cfg_panel_x, _cfg_panel_y - btn_h)
	_cfg_control.size = Vector2(_cfg_panel_w, total_h)
	_cfg_control.mouse_filter = Control.MOUSE_FILTER_STOP
	_cfg_control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_cfg_control.focus_mode = Control.FOCUS_CLICK
	_cfg_control.draw.connect(_draw_cfg_panel)
	_cfg_control.gui_input.connect(_on_cfg_input)
	_cfg_layer.add_child(_cfg_control)
	# Update panel coords to be LOCAL to the control (0,0 = top-left of control)
	_cfg_panel_x = 0.0
	_cfg_panel_y = btn_h  # Panel starts below the button


func _destroy_cfg_panel() -> void:
	if _cfg_layer:
		_cfg_layer.queue_free()
		_cfg_layer = null
		_cfg_control = null


func _draw_cfg_panel() -> void:
	if not _cfg_control:
		return
	var font: Font = ThemeDB.fallback_font
	var c: Control = _cfg_control
	# All coords are LOCAL to the control (0,0 = top-left)
	var pw: float = _cfg_panel_w
	var btn_h: float = 40.0

	# -- RESET button at top of control --
	c.draw_rect(Rect2(0, 0, pw, btn_h), Color(0.5, 0.1, 0.1, 0.9))
	c.draw_rect(Rect2(0, 0, pw, btn_h), Color(1.0, 0.3, 0.2, 0.8), false, 2.0)
	c.draw_string(font, Vector2(0, 26), "RESET SCENE",
		HORIZONTAL_ALIGNMENT_CENTER, int(pw), 18, Color(1, 1, 1))

	# T-pose indicator above button
	if _tpose_countdown > 0:
		c.draw_string(font, Vector2(0, -6), "T-POSE RESET: %.0f" % ceilf(_tpose_countdown),
			HORIZONTAL_ALIGNMENT_CENTER, int(pw), 14, Color(1, 0.9, 0.2))
	elif _tpose_detect_timer > 0.3:
		var pct: float = _tpose_detect_timer / TPOSE_HOLD_TIME
		c.draw_rect(Rect2(0, -4, pw * pct, 3), Color(1.0, 0.9, 0.2))

	# -- Panel below button --
	var py: float = _cfg_panel_y  # = btn_h + gap
	var ph: float = _cfg_panel_h
	c.draw_rect(Rect2(0, py, pw, ph), Color(0.06, 0.06, 0.1, 0.92))
	c.draw_rect(Rect2(0, py, pw, ph), Color(0.2, 0.5, 1.0, 0.5), false, 1.5)

	# Title + status
	var status_text: String = "CALIBRATED" if _calibrated else "UNCALIBRATED"
	var status_col: Color = Color(0.3, 0.9, 0.3) if _calibrated else Color(0.9, 0.5, 0.2)
	c.draw_string(font, Vector2(10, py + 22), "MOCAP CONFIG",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.4, 0.8, 1.0))
	c.draw_string(font, Vector2(pw - 100, py + 22), status_text,
		HORIZONTAL_ALIGNMENT_RIGHT, 90, 10, status_col)

	# Sliders
	var y: float = py + 40.0
	for s in CFG_SLIDERS:
		var val: float = get(s["field"])
		var t: float = (val - s["min"]) / maxf(s["max"] - s["min"], 0.001)
		t = clampf(t, 0.0, 1.0)

		c.draw_string(font, Vector2(10, y + 12), s["label"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.7, 0.7))

		var track_x: float = 110.0
		var track_w: float = 140.0
		c.draw_rect(Rect2(track_x, y + 6, track_w, 4), Color(0.2, 0.2, 0.25))
		var thumb_x: float = track_x + t * track_w
		var dragging: bool = _cfg_dragging == s["key"]
		c.draw_circle(Vector2(thumb_x, y + 8), 6.0, Color(0.3, 1.0, 0.5) if dragging else Color(0.5, 0.9, 0.5))
		c.draw_string(font, Vector2(track_x + track_w + 8, y + 12), "%.2f" % val,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.8, 0.8, 0.8))
		y += 36.0



func _cfg_apply_drag(s: Dictionary, local_x: float, track_x: float, track_w: float) -> void:
	var t: float = clampf((local_x - track_x) / track_w, 0.0, 1.0)
	var val: float = lerpf(s["min"], s["max"], t)
	set(s["field"], val)


# -- Calibration State Machine -------------------------------------------------

func _process_calibration(delta: float) -> void:
	var lm: Dictionary = _last_frame.get("landmarks", {})
	if lm.is_empty():
		return

	# -- Movement reset: if flagged, show warning then reset --
	if _cal_too_much_movement:
		_cal_movement_reset_timer -= delta
		if _cal_movement_reset_timer <= 0:
			_cal_too_much_movement = false
			_cal_settle_frames.clear()
			_cal_all_points_timer = 0.0
			_cal_state = CalibState.WAITING_SETTLE
		return

	# -- Check ALL required landmarks are present --
	var all_present: bool = true
	for key in CAL_REQUIRED_LANDMARKS:
		if not lm.has(key):
			all_present = false
			break
		var vis: float = lm[key][3] if lm[key].size() > 3 else 0.0
		if vis < 0.3:
			all_present = false
			break

	if all_present:
		_cal_all_points_timer += delta
	else:
		_cal_all_points_timer = 0.0  # Reset — need continuous presence
		if _cal_state == CalibState.WAITING_SETTLE:
			_cal_settle_frames.clear()  # Can't settle without all points
		return

	# -- Detect excessive movement during countdown or capture --
	if _cal_state in [CalibState.COUNTDOWN, CalibState.CAPTURE]:
		if _check_excessive_movement(lm):
			print("MOCAP CAL: TOO MUCH MOVEMENT — resetting pose %s" % CAL_POSES[_cal_pose_idx]["name"])
			_cal_too_much_movement = true
			_cal_movement_reset_timer = CAL_MOVEMENT_RESET_TIME
			_cal_settle_frames.clear()
			_cal_all_points_timer = 0.0
			return

	match _cal_state:
		CalibState.WAITING_SETTLE:
			# Don't start settling until all points present for 5 seconds
			if _cal_all_points_timer < CAL_ALL_POINTS_REQUIRED:
				return
			_cal_settle_frames.append(lm.duplicate())
			if _cal_settle_frames.size() > CAL_SETTLE_FRAMES:
				_cal_settle_frames.pop_front()
			if _cal_settle_frames.size() >= CAL_SETTLE_FRAMES and _check_settled():
				_cal_state = CalibState.COUNTDOWN
				_cal_timer = CAL_COUNTDOWN
				print("MOCAP CAL: %s — settled!" % CAL_POSES[_cal_pose_idx]["name"])

		CalibState.COUNTDOWN:
			_cal_timer -= delta
			if _cal_timer <= 0:
				_cal_state = CalibState.CAPTURE
				_cal_settle_frames.clear()

		CalibState.CAPTURE:
			_cal_settle_frames.append(lm.duplicate())
			if _cal_settle_frames.size() >= CAL_CAPTURE_FRAMES:
				var averaged: Dictionary = _average_frames(_cal_settle_frames)
				_cal_captures[CAL_POSES[_cal_pose_idx]["name"]] = averaged
				print("MOCAP CAL: captured %s" % CAL_POSES[_cal_pose_idx]["name"])
				_cal_settle_frames.clear()
				_cal_state = CalibState.FLASH
				_cal_flash_timer = CAL_FLASH_DURATION

		CalibState.FLASH:
			_cal_flash_timer -= delta
			if _cal_flash_timer <= 0:
				_cal_pose_idx += 1
				_cal_all_points_timer = 0.0
				if _cal_pose_idx >= CAL_POSES.size():
					_finish_calibration()
					_destroy_hud()
				else:
					_cal_state = CalibState.WAITING_SETTLE
					_cal_settle_frames.clear()


func _check_excessive_movement(current_lm: Dictionary) -> bool:
	## Check if the person moved too much since the last settle frame.
	if _cal_settle_frames.is_empty():
		return false
	var prev: Dictionary = _cal_settle_frames[_cal_settle_frames.size() - 1]
	var total_movement: float = 0.0
	for key in CAL_REQUIRED_LANDMARKS:
		if not prev.has(key) or not current_lm.has(key):
			continue
		var p: Array = prev[key]
		var c: Array = current_lm[key]
		total_movement += sqrt(pow(c[0] - p[0], 2) + pow(c[1] - p[1], 2))
	return total_movement > CAL_MOVEMENT_THRESHOLD


func _check_settled() -> bool:
	if _cal_settle_frames.size() < CAL_SETTLE_FRAMES:
		return false
	var keys: Array = ["left_shoulder", "right_shoulder", "left_wrist", "right_wrist"]
	for i in range(1, _cal_settle_frames.size()):
		var prev: Dictionary = _cal_settle_frames[i - 1]
		var curr: Dictionary = _cal_settle_frames[i]
		for key in keys:
			if not prev.has(key) or not curr.has(key):
				return false
			var p: Array = prev[key]
			var c: Array = curr[key]
			if sqrt(pow(c[0] - p[0], 2) + pow(c[1] - p[1], 2)) > CAL_SETTLE_THRESHOLD:
				return false
	return true


func _average_frames(frames: Array) -> Dictionary:
	var result: Dictionary = {}
	var counts: Dictionary = {}
	for fr in frames:
		for key in fr:
			if not fr[key] is Array or fr[key].size() < 3:
				continue
			if not result.has(key):
				result[key] = [0.0, 0.0, 0.0, 0.0]
				counts[key] = 0
			var v: Array = fr[key]
			result[key][0] += v[0]
			result[key][1] += v[1]
			result[key][2] += v[2]
			result[key][3] += v[3] if v.size() > 3 else 1.0
			counts[key] += 1
	for key in result:
		var n: float = float(counts[key])
		result[key] = [result[key][0] / n, result[key][1] / n, result[key][2] / n, result[key][3] / n]
	return result


func _finish_calibration() -> void:
	_cal_state = CalibState.IDLE
	var stand: Dictionary = _cal_captures.get("STAND ON MARKS", {})
	var tpose: Dictionary = _cal_captures.get("T-POSE", {})
	var arms_fwd: Dictionary = _cal_captures.get("ARMS FORWARD", {})
	# Use stand pose as the baseline (arms at sides)
	var arms_down: Dictionary = stand if not stand.is_empty() else tpose
	if tpose.is_empty() or arms_down.is_empty():
		print("MOCAP CAL: FAILED — missing poses")
		return

	var l_hip: Vector3 = _v3(tpose.get("left_hip", [0.5, 0.6, 0, 1]))
	var r_hip: Vector3 = _v3(tpose.get("right_hip", [0.5, 0.6, 0, 1]))
	var l_sh: Vector3 = _v3(tpose.get("left_shoulder", [0.4, 0.4, 0, 1]))
	var r_sh: Vector3 = _v3(tpose.get("right_shoulder", [0.6, 0.4, 0, 1]))
	var l_el: Vector3 = _v3(tpose.get("left_elbow", [0.3, 0.4, 0, 1]))
	var r_el: Vector3 = _v3(tpose.get("right_elbow", [0.7, 0.4, 0, 1]))
	var l_wr: Vector3 = _v3(tpose.get("left_wrist", [0.2, 0.4, 0, 1]))
	var r_wr: Vector3 = _v3(tpose.get("right_wrist", [0.8, 0.4, 0, 1]))
	var nose: Vector3 = _v3(tpose.get("nose", [0.5, 0.3, 0, 1]))
	var hip_center: Vector3 = (l_hip + r_hip) * 0.5

	_cal_torso_len = ((l_sh + r_sh) * 0.5 - hip_center).length()
	_cal_shoulder_width = (l_sh - r_sh).length()
	_cal_hip_width = (l_hip - r_hip).length()
	_cal_upper_arm = ((l_sh - l_el).length() + (r_sh - r_el).length()) * 0.5
	_cal_lower_arm = ((l_el - l_wr).length() + (r_el - r_wr).length()) * 0.5
	_cal_arm_span = (l_wr - r_wr).length()
	_cal_depth_sign = -1.0 if nose.z < hip_center.z else 1.0

	_calibrated = true
	print("MOCAP CAL: DONE — torso=%.3f shoulders=%.3f hips=%.3f upper=%.3f lower=%.3f span=%.3f" % [
		_cal_torso_len, _cal_shoulder_width, _cal_hip_width, _cal_upper_arm, _cal_lower_arm, _cal_arm_span])


# -- Mapping Pipeline ----------------------------------------------------------

func _apply_to_monster() -> void:
	## Simplified mocap mapping:
	## - RL/RR and FL/FR stay FABRIK-constrained (angle changes only within extents)
	## - FL/FR forward-apex = arms fully up in mocap, backward-apex = arms fully down
	## - Arms (front leg claws) track mocap arms translated to game coords
	## - Spine, hips, rear legs: PINNED, never move
	if not is_instance_valid(_target_monster):
		_target_monster = _find_target_monster()
		if not _target_monster:
			return

	var m: Node2D = _target_monster
	var lm: Dictionary = _last_frame.get("landmarks", {})
	if lm.is_empty():
		return

	for key in lm:
		_last_known[key] = lm[key]
	lm = _last_known

	var need: Array = ["left_hip", "right_hip", "left_shoulder", "right_shoulder"]
	for n in need:
		if not lm.has(n):
			return

	# -- PIN on first frame --
	if not _pinned:
		_pin_spine2 = m._spine[2]
		_pin_spine1 = m._spine[1]
		_pin_facing = 1.0
		if is_instance_valid(m._target):
			var dx: float = m._target.global_position.x - m.global_position.x
			_pin_facing = 1.0 if dx > 0 else -1.0
		elif m._facing_target != 0:
			_pin_facing = m._facing_target
		if not is_instance_valid(m._target):
			for node in m.get_tree().get_nodes_in_group("players"):
				if node is CharacterBody2D and node != m:
					m._target = node
					break
		# Lock scale: compute from current mocap frame's torso, never recompute
		var l_hip_pin: Vector3 = _v3(lm["left_hip"])
		var r_hip_pin: Vector3 = _v3(lm["right_hip"])
		var hip_c_pin: Vector3 = (l_hip_pin + r_hip_pin) * 0.5
		var l_sh_pin: Vector3 = _v3(lm["left_shoulder"])
		var r_sh_pin: Vector3 = _v3(lm["right_shoulder"])
		var sh_c_pin: Vector3 = (l_sh_pin + r_sh_pin) * 0.5 - hip_c_pin
		_pin_scale = m.sc(56.0) / maxf(sh_c_pin.length(), 0.01)
		_pinned = true
		print("MOCAP: pinned S2=(%.0f,%.0f) S1=(%.0f,%.0f) facing=%.0f scale=%.1f" % [
			_pin_spine2.x, _pin_spine2.y, _pin_spine1.x, _pin_spine1.y, _pin_facing, _pin_scale])

	# -- Force facing and rear body PINNED --
	m._facing_target = _pin_facing
	m._facing = _pin_facing
	m._spine[2] = _pin_spine2
	m._hip_bones[0] = m._hip_bones[0]  # Don't modify
	m._hip_bones[1] = m._hip_bones[1]

	# -- Extract mocap points --
	var l_hip: Vector3 = _v3(lm["left_hip"])
	var r_hip: Vector3 = _v3(lm["right_hip"])
	var hip_center: Vector3 = (l_hip + r_hip) * 0.5

	var l_sh: Vector3 = _v3(lm.get("left_shoulder", [0,0,0,0])) - hip_center
	var r_sh: Vector3 = _v3(lm.get("right_shoulder", [0,0,0,0])) - hip_center
	var sh_center: Vector3 = (l_sh + r_sh) * 0.5

	_detect_tpose(lm, get_process_delta_time())

	# -- Compute arm Y position (normalized: -1=fully up, +1=fully down) --
	# Use wrist Y relative to shoulder Y. In mocap space, Y increases downward.
	var l_arm_y: float = 0.0  # -1=up, +1=down
	var r_arm_y: float = 0.0
	if lm.has("left_wrist") and lm.has("left_shoulder"):
		var lw_y: float = lm["left_wrist"][1]
		var ls_y: float = lm["left_shoulder"][1]
		l_arm_y = clampf((lw_y - ls_y) / 0.25, -1.0, 1.0)  # 0.25 = rough arm length in norm
	if lm.has("right_wrist") and lm.has("right_shoulder"):
		var rw_y: float = lm["right_wrist"][1]
		var rs_y: float = lm["right_shoulder"][1]
		r_arm_y = clampf((rw_y - rs_y) / 0.25, -1.0, 1.0)

	# Smooth
	l_arm_y = lerpf(_smooth_points.get("l_arm_y_f", l_arm_y) as float, l_arm_y, cfg_smooth_weight)
	_smooth_points["l_arm_y_f"] = l_arm_y
	r_arm_y = lerpf(_smooth_points.get("r_arm_y_f", r_arm_y) as float, r_arm_y, cfg_smooth_weight)
	_smooth_points["r_arm_y_f"] = r_arm_y

	# -- FL/FR leg angle from arm position --
	# Forward apex (arm up, arm_y=-1) → leg swings FORWARD (toward target)
	# Backward apex (arm down, arm_y=+1) → leg swings BACKWARD
	# The leg pivots from the clavicle, constrained by FABRIK bone lengths
	var upper_len: float = m.sc(m.cfg("leg_upper_len", 20.0)) * cfg_arm_scale
	var lower_len: float = m.sc(m.cfg("leg_lower_len", 22.0)) * cfg_arm_scale
	var total_reach: float = upper_len + lower_len

	# Spine direction for "forward"
	var spine_dir: Vector2 = (m._spine[0] - _pin_spine2).normalized()
	if spine_dir.length() < 0.01:
		spine_dir = Vector2(_pin_facing, 0)
	var spine_perp: Vector2 = Vector2(-spine_dir.y, spine_dir.x)  # "up" relative to spine

	# Right arm → leg 0 (attached at clavicle[1])
	var r_swing: float = -r_arm_y  # Negate: arm up = forward swing
	var r_foot_dir: Vector2 = (spine_dir * r_swing + spine_perp * 0.3).normalized()
	var r_foot_target: Vector2 = m._clavicles[1] + r_foot_dir * total_reach * 0.8
	m._legs[0][0] = m._clavicles[1]
	m._legs[0][2] = _smooth("r_foot", r_foot_target)
	m._legs[0][1] = (m._legs[0][0] + m._legs[0][2]) * 0.5 + spine_perp * upper_len * 0.3
	_fabrik_chain(m._legs[0], upper_len, lower_len)

	# Left arm → leg 1 (attached at clavicle[0])
	var l_swing: float = -l_arm_y
	var l_foot_dir: Vector2 = (spine_dir * l_swing + spine_perp * 0.3).normalized()
	var l_foot_target: Vector2 = m._clavicles[0] + l_foot_dir * total_reach * 0.8
	m._legs[1][0] = m._clavicles[0]
	m._legs[1][2] = _smooth("l_foot", l_foot_target)
	m._legs[1][1] = (m._legs[1][0] + m._legs[1][2]) * 0.5 + spine_perp * upper_len * 0.3
	_fabrik_chain(m._legs[1], upper_len, lower_len)

	m._foot_planted[0] = false
	m._foot_planted[1] = false
	m._posture = m.Posture.BIPEDAL
	m._posture_blend = 1.0

	# -- Rear legs: STAY at their current positions, FABRIK-constrained --
	m._legs[2][0] = m._hip_bones[0]
	m._legs[3][0] = m._hip_bones[1]
	# Keep rear feet planted
	for li in [2, 3]:
		m._foot_planted[li] = true

	# -- Head: simple forward gaze --
	var neck_len: float = m.sc(m.cfg("neck_len", 18.0))
	var head_fwd: Vector2 = spine_dir
	m._neck[0] = m._spine[0]
	m._neck[1] = _smooth("neck1", m._spine[0] + head_fwd * neck_len * 0.6)
	m._skull = _smooth("skull", m._spine[0] + head_fwd * neck_len)
	m._jaw = _smooth("jaw", m._skull + head_fwd.rotated(0.2) * m.sc(8.0))

	# -- Spine[0] stays at rest relative to spine[1] pin --
	# Don't let mocap drive spine[0] anymore — keep it FABRIK-constrained
	var seg_len: float = m.sc(m.cfg("spine_seg_len", 28.0))
	var spine0_target: Vector2 = _pin_spine1 + spine_dir * seg_len
	m._spine[0] = _smooth("spine0", spine0_target)
	m._spine[1] = _fabrik_mid(m._spine[0], _pin_spine2, seg_len)

	m.queue_redraw()


func _detect_tpose(lm: Dictionary, delta: float) -> void:
	## Auto-detect T-pose: both arms extended horizontally.
	## When held for TPOSE_HOLD_TIME, start a 3-2-1 countdown then reset calibration.
	if not lm.has("left_shoulder") or not lm.has("right_shoulder") \
		or not lm.has("left_wrist") or not lm.has("right_wrist"):
		_tpose_detect_timer = 0.0
		_tpose_countdown = -1.0
		return

	var ls: Array = lm["left_shoulder"]
	var rs: Array = lm["right_shoulder"]
	var lw: Array = lm["left_wrist"]
	var rw: Array = lm["right_wrist"]

	# Check: wrists roughly at shoulder height (Y similar)
	var l_dy: float = absf(lw[1] - ls[1])
	var r_dy: float = absf(rw[1] - rs[1])
	# Check: wrists extended outward (X far from shoulders)
	var l_dx: float = absf(lw[0] - ls[0])
	var r_dx: float = absf(rw[0] - rs[0])

	var is_tpose: bool = (l_dy < TPOSE_ARM_HORIZONTAL_THRESHOLD and r_dy < TPOSE_ARM_HORIZONTAL_THRESHOLD \
		and l_dx > TPOSE_ARM_EXTENDED_THRESHOLD and r_dx > TPOSE_ARM_EXTENDED_THRESHOLD)

	if is_tpose:
		_tpose_detect_timer += delta
		if _tpose_detect_timer >= TPOSE_HOLD_TIME and _tpose_countdown < 0:
			_tpose_countdown = 3.0
			print("MOCAP: T-POSE detected — resetting in 3...")
	else:
		_tpose_detect_timer = 0.0
		_tpose_countdown = -1.0

	# Countdown
	if _tpose_countdown > 0:
		_tpose_countdown -= delta
		if _tpose_countdown <= 0:
			_reset_scene()
			_tpose_countdown = -1.0
			_tpose_detect_timer = 0.0


func _reset_scene() -> void:
	## Full reset: unpin, clear smoothing, re-calibrate from current pose.
	print("MOCAP: RESET — re-pinning and recalibrating")
	_pinned = false
	_smooth_points.clear()
	_last_known.clear()
	_calibrated = false
	# Capture current frame as calibration baseline
	var lm: Dictionary = _last_frame.get("landmarks", {})
	if not lm.is_empty():
		_cal_captures["T-POSE"] = lm.duplicate()
		_cal_captures["STAND ON MARKS"] = lm.duplicate()
		_finish_calibration()


# -- Helpers -------------------------------------------------------------------

func _v3(arr: Array) -> Vector3:
	return Vector3(arr[0], arr[1], arr[2] if arr.size() > 2 else 0.0)


func _project_and_tilt(pt: Vector3, facing: float, scale: float) -> Vector2:
	## Project mocap 3D point to game 2D.
	## Mocap coords (relative to hip center):
	##   x = left-right in camera view
	##   y = up-down (negative = above hips)
	##   z = depth (negative = toward camera)
	##
	## The monster's spine runs at cfg_stance_angle degrees from horizontal.
	## Mocap "up" (the spine axis, -y) maps along this angled spine direction.
	## Mocap "horizontal" (x/z) maps perpendicular to the spine.
	##
	## Spine direction in game: angle from horizontal.
	##   0° = horizontal (quadruped), 90° = vertical (standing), 45° = reared up.
	var angle_rad: float = deg_to_rad(cfg_stance_angle)
	# Spine direction vector in game space (from rear toward head)
	# At 45°: pointing right and up = (cos45, -sin45) * facing
	var spine_dir := Vector2(cos(angle_rad) * facing, -sin(angle_rad))
	# Perpendicular to spine (points "outward" from the body — used for lateral mocap)
	var spine_perp := Vector2(spine_dir.y, -spine_dir.x)  # 90° CCW

	# Map mocap Y (vertical, spine axis) along spine_dir
	# pt.y is negative when above hips → should move along +spine_dir (toward head)
	var along_spine: float = -pt.y * scale * cfg_y_scale  # Negate: up in mocap = forward along spine

	# Map mocap Z (depth) along spine_perp for lateral displacement
	# Also blend in mocap X for sideways movement visibility
	var lateral: float = (pt.z * facing + pt.x * cfg_depth_blend) * scale * cfg_x_scale

	return spine_dir * along_spine + spine_perp * lateral


func _smooth(key: String, target: Vector2) -> Vector2:
	if _smooth_points.has(key):
		var s: Vector2 = _smooth_points[key].lerp(target, cfg_smooth_weight)
		_smooth_points[key] = s
		return s
	_smooth_points[key] = target
	return target


func _fabrik_mid(a: Vector2, b: Vector2, seg_len: float) -> Vector2:
	var mid: Vector2 = (a + b) * 0.5
	var half: float = a.distance_to(b) * 0.5
	if half >= seg_len:
		return mid
	var dir: Vector2 = (b - a).normalized()
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	return mid + perp * sqrt(maxf(0.0, seg_len * seg_len - half * half)) * 0.3


func _fabrik_chain(joints: Array, upper_len: float, lower_len: float) -> void:
	var shoulder: Vector2 = joints[0]
	for _i in range(FABRIK_ITERS):
		var d1: Vector2 = joints[1] - joints[2]
		if d1.length() > 0.01:
			joints[1] = joints[2] + d1.normalized() * lower_len
		var d0: Vector2 = joints[0] - joints[1]
		if d0.length() > 0.01:
			joints[0] = joints[1] + d0.normalized() * upper_len
		joints[0] = shoulder
		d0 = joints[1] - joints[0]
		if d0.length() > 0.01:
			joints[1] = joints[0] + d0.normalized() * upper_len
		d1 = joints[2] - joints[1]
		if d1.length() > 0.01:
			joints[2] = joints[1] + d1.normalized() * lower_len


func _is_quadruped(node: Node) -> bool:
	return node.get("creature_scale") != null


func _find_target_monster() -> Node2D:
	var hud: Node = get_node_or_null("/root/PlayerHUD")
	if hud and is_instance_valid(hud.get("debug_selected_enemy")):
		var sel: Node2D = hud.debug_selected_enemy
		if _is_quadruped(sel):
			return sel
	for node in get_tree().get_nodes_in_group("enemies"):
		if _is_quadruped(node) and node.has_meta("player_controlled"):
			return node
	for node in get_tree().get_nodes_in_group("enemies"):
		if _is_quadruped(node):
			return node
	return null
