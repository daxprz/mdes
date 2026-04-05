extends CanvasLayer

## FPS Overlay — shows current FPS number and a rolling graph.
## Enabled via debug aspect "perf/fps" (RCON: debug on perf/fps).
## Draws in the top-left corner, above all game content.

const GRAPH_WIDTH := 200
const GRAPH_HEIGHT := 60
const GRAPH_X := 8.0
const GRAPH_Y := 8.0
const MAX_SAMPLES := 200       # One sample per frame, 200 frames of history
const TARGET_FPS := 60.0
const GRAPH_MAX_FPS := 120.0   # Top of graph scale

var _samples: PackedFloat32Array = PackedFloat32Array()
var _panel: Control


func _ready() -> void:
	layer = 120  # Above everything
	_panel = Control.new()
	_panel.name = "FPSPanel"
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.draw.connect(_draw_fps)
	add_child(_panel)


func _process(_delta: float) -> void:
	if not DebugOverlay.should_draw("perf/fps"):
		_panel.visible = false
		return
	_panel.visible = true

	var fps: float = Performance.get_monitor(Performance.TIME_FPS)
	_samples.append(fps)
	if _samples.size() > MAX_SAMPLES:
		_samples = _samples.slice(_samples.size() - MAX_SAMPLES)

	_panel.queue_redraw()


func _draw_fps() -> void:
	if _samples.is_empty():
		return

	var font: Font = ThemeDB.fallback_font
	var current_fps: float = _samples[-1]

	# Background
	_panel.draw_rect(Rect2(GRAPH_X - 2, GRAPH_Y - 2, GRAPH_WIDTH + 4, GRAPH_HEIGHT + 22),
		Color(0.0, 0.0, 0.0, 0.7))

	# FPS text
	var fps_color: Color
	if current_fps >= 55:
		fps_color = Color(0.3, 1.0, 0.3)
	elif current_fps >= 30:
		fps_color = Color(1.0, 0.9, 0.2)
	else:
		fps_color = Color(1.0, 0.3, 0.2)
	_panel.draw_string(font, Vector2(GRAPH_X + 2, GRAPH_Y + 12),
		"%d FPS" % int(current_fps), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, fps_color)

	# Min/avg from visible history
	var min_fps: float = 9999.0
	var sum_fps: float = 0.0
	for s in _samples:
		min_fps = minf(min_fps, s)
		sum_fps += s
	var avg_fps: float = sum_fps / _samples.size()
	_panel.draw_string(font, Vector2(GRAPH_X + 70, GRAPH_Y + 12),
		"avg:%d min:%d" % [int(avg_fps), int(min_fps)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.6, 0.6, 0.7))

	# Graph area
	var gx: float = GRAPH_X
	var gy: float = GRAPH_Y + 16.0
	var gw: float = GRAPH_WIDTH
	var gh: float = GRAPH_HEIGHT

	# Graph background
	_panel.draw_rect(Rect2(gx, gy, gw, gh), Color(0.05, 0.05, 0.08))

	# 60 FPS target line
	var target_y: float = gy + gh * (1.0 - TARGET_FPS / GRAPH_MAX_FPS)
	_panel.draw_line(Vector2(gx, target_y), Vector2(gx + gw, target_y),
		Color(0.3, 0.5, 0.3, 0.5), 1.0)

	# 30 FPS warning line
	var warn_y: float = gy + gh * (1.0 - 30.0 / GRAPH_MAX_FPS)
	_panel.draw_line(Vector2(gx, warn_y), Vector2(gx + gw, warn_y),
		Color(0.5, 0.3, 0.2, 0.4), 1.0)

	# Plot samples as a filled polygon
	var n: int = _samples.size()
	var step: float = gw / float(MAX_SAMPLES)
	var offset: int = MAX_SAMPLES - n  # Right-align samples

	var points: PackedVector2Array = PackedVector2Array()
	var colors: PackedColorArray = PackedColorArray()

	for i in range(n):
		var x: float = gx + (offset + i) * step
		var ratio: float = clampf(_samples[i] / GRAPH_MAX_FPS, 0.0, 1.0)
		var y: float = gy + gh * (1.0 - ratio)
		points.append(Vector2(x, y))

		# Color by FPS value
		var c: Color
		if _samples[i] >= 55:
			c = Color(0.2, 0.8, 0.3, 0.8)
		elif _samples[i] >= 30:
			c = Color(0.8, 0.7, 0.1, 0.8)
		else:
			c = Color(0.9, 0.2, 0.1, 0.8)
		colors.append(c)

	# Draw as connected line segments
	if points.size() >= 2:
		for i in range(points.size() - 1):
			_panel.draw_line(points[i], points[i + 1], colors[i + 1], 1.5)

	# Border
	_panel.draw_rect(Rect2(gx, gy, gw, gh), Color(0.3, 0.3, 0.4, 0.5), false, 1.0)
