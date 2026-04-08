extends CanvasLayer

## Performance Monitor — FPS graph + Godot Performance metrics + entity snapshot.
##
## Modes (cycled by clicking the panel or via RCON "perf"):
##   COMPACT  — FPS number + mini graph (bottom-right)
##   EXPANDED — FPS graph + all tracked metrics in a scrollable column
##
## Spacebar (when panel visible) dumps a full snapshot to stdout, including
## every Performance monitor, entity census with per-entity state, pool stats,
## and music system status.
##
## Enabled via debug aspect "perf/fps" (RCON: debug on perf/fps).

# -- Constants -----------------------------------------------------------------

const GRAPH_WIDTH := 200
const GRAPH_HEIGHT := 60
const MARGIN := 8.0
const MAX_SAMPLES := 200       # One sample per frame, 200 frames of history
const TARGET_FPS := 60.0
const GRAPH_MAX_FPS := 120.0   # Top of graph scale

const METRIC_ROW_H := 14.0     # Height per metric line in expanded view
const METRIC_FONT_SIZE := 10
const LABEL_FONT_SIZE := 9
const HEADER_FONT_SIZE := 11

## FPS threshold for auto-snapshot on lag spikes
const LAG_SPIKE_THRESHOLD := 40.0
## Minimum seconds between auto-snapshots (don't spam on sustained low FPS)
const LAG_SPIKE_COOLDOWN := 5.0

enum Mode { COMPACT, EXPANDED }


# -- Metric Definition ---------------------------------------------------------

## Each tracked metric: what to sample, how to display, what's "bad"
class MetricDef:
	var id: String              # Internal key
	var label: String           # Display name
	var group: String           # Group header
	var source: Callable        # Returns float
	var format: String          # printf format ("%.1f", "%d", etc.)
	var warn_above: float       # Yellow if above this (-1 = no warning)
	var alert_above: float      # Red if above this (-1 = no alert)
	var warn_below: float       # Yellow if below this (-1 = no warning)
	var alert_below: float      # Red if below this (-1 = no alert)
	var unit: String            # "ms", "MB", "", etc.

	func _init(p_id: String, p_label: String, p_group: String, p_source: Callable,
			p_format: String = "%d", p_unit: String = "",
			p_warn_above: float = -1.0, p_alert_above: float = -1.0,
			p_warn_below: float = -1.0, p_alert_below: float = -1.0) -> void:
		id = p_id; label = p_label; group = p_group; source = p_source
		format = p_format; unit = p_unit
		warn_above = p_warn_above; alert_above = p_alert_above
		warn_below = p_warn_below; alert_below = p_alert_below


# -- State ---------------------------------------------------------------------

var _mode: int = Mode.COMPACT
var _fps_samples: PackedFloat32Array = PackedFloat32Array()
var _panel: Control

## Metric registry and per-metric rolling samples
var _metrics: Array = []                        # Array[MetricDef]
var _metric_values: Dictionary = {}             # id -> float (current)
var _metric_history: Dictionary = {}            # id -> PackedFloat32Array (last MAX_SAMPLES)

## Lag spike detection
var _last_spike_time: float = -999.0            # Engine.get_process_frames() time
var _spike_count: int = 0

## For click detection (expand/compact toggle)
var _panel_rect: Rect2 = Rect2()


# -- Lifecycle -----------------------------------------------------------------

func _ready() -> void:
	layer = 120  # Above everything
	_panel = Control.new()
	_panel.name = "PerfPanel"
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_panel.draw.connect(_on_draw)
	_panel.gui_input.connect(_on_gui_input)
	add_child(_panel)
	_register_metrics()


func _register_metrics() -> void:
	var m := _metrics
	var P := Performance

	# -- Timing --
	m.append(MetricDef.new("time_process", "Process", "Timing",
		func() -> float: return P.get_monitor(P.TIME_PROCESS) * 1000.0,
		"%.1f", "ms", 12.0, 16.0))
	m.append(MetricDef.new("time_physics", "Physics", "Timing",
		func() -> float: return P.get_monitor(P.TIME_PHYSICS_PROCESS) * 1000.0,
		"%.1f", "ms", 12.0, 16.0))
	m.append(MetricDef.new("time_navigation", "Navigation", "Timing",
		func() -> float: return P.get_monitor(P.TIME_NAVIGATION_PROCESS) * 1000.0,
		"%.2f", "ms", 2.0, 5.0))

	# -- Objects --
	m.append(MetricDef.new("obj_count", "Objects", "Objects",
		func() -> float: return P.get_monitor(P.OBJECT_COUNT),
		"%d", "", 5000.0, 10000.0))
	m.append(MetricDef.new("node_count", "Nodes", "Objects",
		func() -> float: return P.get_monitor(P.OBJECT_NODE_COUNT),
		"%d", "", 2000.0, 5000.0))
	m.append(MetricDef.new("orphan_nodes", "Orphan Nodes", "Objects",
		func() -> float: return P.get_monitor(P.OBJECT_ORPHAN_NODE_COUNT),
		"%d", "", 10.0, 50.0))
	m.append(MetricDef.new("resource_count", "Resources", "Objects",
		func() -> float: return P.get_monitor(P.OBJECT_RESOURCE_COUNT),
		"%d", ""))

	# -- Rendering --
	m.append(MetricDef.new("draw_calls", "Draw Calls", "Rendering",
		func() -> float: return P.get_monitor(P.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"%d", "", 200.0, 500.0))
	m.append(MetricDef.new("render_objects", "Render Objects", "Rendering",
		func() -> float: return P.get_monitor(P.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"%d", "", 500.0, 1000.0))
	m.append(MetricDef.new("render_prims", "Primitives", "Rendering",
		func() -> float: return P.get_monitor(P.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"%d", "", 50000.0, 100000.0))

	# -- Memory --
	m.append(MetricDef.new("mem_static", "Static Mem", "Memory",
		func() -> float: return P.get_monitor(P.MEMORY_STATIC) / 1048576.0,
		"%.1f", "MB", 256.0, 512.0))
	m.append(MetricDef.new("mem_static_max", "Peak Mem", "Memory",
		func() -> float: return P.get_monitor(P.MEMORY_STATIC_MAX) / 1048576.0,
		"%.1f", "MB"))
	m.append(MetricDef.new("mem_msg_buf", "Msg Buffer", "Memory",
		func() -> float: return P.get_monitor(P.MEMORY_MESSAGE_BUFFER_MAX) / 1024.0,
		"%.0f", "KB", 64.0, 128.0))

	# -- Scene entities (sampled from the tree) --
	m.append(MetricDef.new("enemies", "Enemies", "Entities",
		func() -> float: return _count_group("enemies"),
		"%d", ""))
	m.append(MetricDef.new("players", "Players", "Entities",
		func() -> float: return _count_group("players"),
		"%d", ""))
	m.append(MetricDef.new("loose_items", "Loose Items", "Entities",
		func() -> float: return _count_group("loose_items"),
		"%d", "", 20.0, 50.0))
	m.append(MetricDef.new("dummies", "Dummies", "Entities",
		func() -> float: return _count_group("attack_dummies"),
		"%d", ""))
	m.append(MetricDef.new("chains", "Chains", "Entities",
		func() -> float: return _count_group("chains"),
		"%d", ""))
	m.append(MetricDef.new("tethers", "Tethers", "Entities",
		func() -> float: return _count_group("tethers"),
		"%d", ""))

	# -- Object Pool --
	m.append(MetricDef.new("pool_active", "Pool Acquires", "Pool",
		func() -> float: return _pool_total("acquires"),
		"%d", ""))
	m.append(MetricDef.new("pool_misses", "Pool Misses", "Pool",
		func() -> float: return _pool_total("misses"),
		"%d", "", 50.0, 200.0))
	m.append(MetricDef.new("pool_size", "Pooled (idle)", "Pool",
		func() -> float: return _pool_total("pool_size"),
		"%d", ""))

	# Initialize history buffers
	for metric in _metrics:
		_metric_values[metric.id] = 0.0
		_metric_history[metric.id] = PackedFloat32Array()


# -- Per-Frame Sampling --------------------------------------------------------

func _process(_delta: float) -> void:
	if not DebugOverlay.should_draw("perf/fps"):
		_panel.visible = false
		return
	_panel.visible = true

	# Sample FPS
	var fps: float = Performance.get_monitor(Performance.TIME_FPS)
	_fps_samples.append(fps)
	if _fps_samples.size() > MAX_SAMPLES:
		_fps_samples = _fps_samples.slice(_fps_samples.size() - MAX_SAMPLES)

	# Sample all metrics
	for metric in _metrics:
		var val: float = metric.source.call()
		_metric_values[metric.id] = val
		var hist: PackedFloat32Array = _metric_history[metric.id]
		hist.append(val)
		if hist.size() > MAX_SAMPLES:
			_metric_history[metric.id] = hist.slice(hist.size() - MAX_SAMPLES)

	# Lag spike auto-detection
	if fps < LAG_SPIKE_THRESHOLD:
		var now: float = Time.get_ticks_msec() / 1000.0
		if now - _last_spike_time > LAG_SPIKE_COOLDOWN:
			_last_spike_time = now
			_spike_count += 1
			_dump_snapshot("AUTO-SPIKE #%d (%.0f FPS)" % [_spike_count, fps])

	_panel.queue_redraw()


# -- Input (spacebar snapshot + click to toggle mode) --------------------------

func _input(event: InputEvent) -> void:
	if not _panel.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_dump_snapshot("MANUAL (spacebar)")
			get_viewport().set_input_as_handled()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _panel_rect.has_point(event.position):
			_mode = Mode.EXPANDED if _mode == Mode.COMPACT else Mode.COMPACT
			_panel.queue_redraw()
			get_viewport().set_input_as_handled()


# -- Drawing -------------------------------------------------------------------

func _on_draw() -> void:
	if _fps_samples.is_empty():
		return
	if _mode == Mode.COMPACT:
		_draw_compact()
	else:
		_draw_expanded()


func _draw_compact() -> void:
	var font: Font = ThemeDB.fallback_font
	var current_fps: float = _fps_samples[-1]
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var total_h: float = GRAPH_HEIGHT + 20.0
	var bx: float = vp.x - GRAPH_WIDTH - MARGIN
	var by: float = vp.y - total_h - MARGIN

	_panel_rect = Rect2(bx - 2, by - 2, GRAPH_WIDTH + 4, total_h + 4)

	# Background
	_panel.draw_rect(_panel_rect, Color(0.0, 0.0, 0.0, 0.75))

	# FPS text
	var fps_color: Color = _fps_color(current_fps)
	_panel.draw_string(font, Vector2(bx + 2, by + 12),
		"%d FPS" % int(current_fps), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, fps_color)

	# Min/avg
	var min_fps: float = 9999.0
	var sum_fps: float = 0.0
	for s in _fps_samples:
		min_fps = minf(min_fps, s)
		sum_fps += s
	var avg_fps: float = sum_fps / _fps_samples.size()
	_panel.draw_string(font, Vector2(bx + 70, by + 12),
		"avg:%d min:%d" % [int(avg_fps), int(min_fps)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.6, 0.6, 0.7))

	# Spike count indicator
	if _spike_count > 0:
		_panel.draw_string(font, Vector2(bx + 160, by + 12),
			"%d!" % _spike_count,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 0.3, 0.2))

	# Click hint
	_panel.draw_string(font, Vector2(bx + GRAPH_WIDTH - 30, by + 12),
		"[+]", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.4, 0.5))

	_draw_fps_graph(bx, by + 16.0, GRAPH_WIDTH, GRAPH_HEIGHT)

	# Border
	_panel.draw_rect(_panel_rect, Color(0.3, 0.3, 0.4, 0.5), false, 1.0)


func _draw_expanded() -> void:
	var font: Font = ThemeDB.fallback_font
	var current_fps: float = _fps_samples[-1]
	var vp: Vector2 = get_viewport().get_visible_rect().size

	# Calculate panel height based on metric count + groups
	var group_count: int = 0
	var last_group: String = ""
	for metric in _metrics:
		if metric.group != last_group:
			group_count += 1
			last_group = metric.group

	var metrics_h: float = _metrics.size() * METRIC_ROW_H + group_count * (METRIC_ROW_H + 4.0)
	var total_h: float = GRAPH_HEIGHT + 24.0 + metrics_h + 20.0
	var panel_w: float = 280.0
	var bx: float = vp.x - panel_w - MARGIN
	var by: float = vp.y - total_h - MARGIN

	_panel_rect = Rect2(bx - 2, by - 2, panel_w + 4, total_h + 4)

	# Background
	_panel.draw_rect(_panel_rect, Color(0.0, 0.0, 0.0, 0.85))

	# FPS header
	var fps_color: Color = _fps_color(current_fps)
	_panel.draw_string(font, Vector2(bx + 4, by + 13),
		"%d FPS" % int(current_fps), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, fps_color)

	# Min / avg / 1% low
	var min_fps: float = 9999.0
	var sum_fps: float = 0.0
	var sorted_fps: Array = Array(_fps_samples)
	sorted_fps.sort()
	for s in _fps_samples:
		min_fps = minf(min_fps, s)
		sum_fps += s
	var avg_fps: float = sum_fps / _fps_samples.size()
	var one_pct_low: float = sorted_fps[0] if sorted_fps.size() > 0 else 0.0
	if sorted_fps.size() >= 10:
		var low_count: int = maxi(1, int(sorted_fps.size() / 100.0))
		var low_sum: float = 0.0
		for i in range(low_count):
			low_sum += sorted_fps[i]
		one_pct_low = low_sum / low_count

	_panel.draw_string(font, Vector2(bx + 80, by + 13),
		"avg:%d  min:%d  1%%:%d  spikes:%d" % [int(avg_fps), int(min_fps), int(one_pct_low), _spike_count],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.5, 0.5, 0.6))

	# Collapse hint
	_panel.draw_string(font, Vector2(bx + panel_w - 30, by + 13),
		"[-]", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.4, 0.5))

	# FPS graph
	_draw_fps_graph(bx, by + 18.0, panel_w, GRAPH_HEIGHT)

	# Spacebar hint
	var hint_y: float = by + 18.0 + GRAPH_HEIGHT + 3.0
	_panel.draw_string(font, Vector2(bx + 4, hint_y + 10),
		"[SPACE] snapshot to log", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.35, 0.35, 0.45))

	# Metrics list
	var cy: float = hint_y + 16.0
	last_group = ""
	for metric in _metrics:
		# Group header
		if metric.group != last_group:
			last_group = metric.group
			cy += 4.0
			_panel.draw_string(font, Vector2(bx + 4, cy + METRIC_ROW_H - 3),
				metric.group, HORIZONTAL_ALIGNMENT_LEFT, -1, HEADER_FONT_SIZE,
				Color(0.55, 0.65, 0.8))
			# Underline
			_panel.draw_line(
				Vector2(bx + 4, cy + METRIC_ROW_H),
				Vector2(bx + panel_w - 4, cy + METRIC_ROW_H),
				Color(0.3, 0.35, 0.45, 0.5), 1.0)
			cy += METRIC_ROW_H

		var val: float = _metric_values[metric.id]
		var val_str: String = (metric.format % val) + metric.unit
		var val_color: Color = _metric_color(metric, val)

		# Label
		_panel.draw_string(font, Vector2(bx + 8, cy + METRIC_ROW_H - 3),
			metric.label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE,
			Color(0.55, 0.55, 0.6))

		# Value (right-aligned)
		_panel.draw_string(font, Vector2(bx + 140, cy + METRIC_ROW_H - 3),
			val_str, HORIZONTAL_ALIGNMENT_LEFT, -1, METRIC_FONT_SIZE, val_color)

		# Mini sparkline (last 60 samples)
		_draw_sparkline(bx + 200, cy + 2, panel_w - 208, METRIC_ROW_H - 4, metric)

		cy += METRIC_ROW_H

	# Border
	_panel.draw_rect(_panel_rect, Color(0.3, 0.3, 0.4, 0.5), false, 1.0)


func _draw_fps_graph(gx: float, gy: float, gw: float, gh: float) -> void:
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

	var n: int = _fps_samples.size()
	if n < 2:
		return

	var step: float = gw / float(MAX_SAMPLES)
	var graph_offset: int = MAX_SAMPLES - n

	var prev_pt: Vector2 = Vector2.ZERO
	for i in range(n):
		var x: float = gx + (graph_offset + i) * step
		var ratio: float = clampf(_fps_samples[i] / GRAPH_MAX_FPS, 0.0, 1.0)
		var y: float = gy + gh * (1.0 - ratio)
		var pt: Vector2 = Vector2(x, y)
		if i > 0:
			_panel.draw_line(prev_pt, pt, _fps_color(_fps_samples[i]).lerp(Color.WHITE, 0.1), 1.5)
		prev_pt = pt

	# Border
	_panel.draw_rect(Rect2(gx, gy, gw, gh), Color(0.3, 0.3, 0.4, 0.5), false, 1.0)


func _draw_sparkline(sx: float, sy: float, sw: float, sh: float, metric: MetricDef) -> void:
	var hist: PackedFloat32Array = _metric_history.get(metric.id, PackedFloat32Array())
	var count: int = mini(60, hist.size())
	if count < 2:
		return

	# Find range in visible window
	var lo: float = INF
	var hi: float = -INF
	var start_idx: int = hist.size() - count
	for i in range(count):
		var v: float = hist[start_idx + i]
		lo = minf(lo, v)
		hi = maxf(hi, v)
	if hi - lo < 0.001:
		hi = lo + 1.0  # Avoid div by zero

	var step: float = sw / float(count - 1)
	var prev: Vector2 = Vector2.ZERO
	for i in range(count):
		var v: float = hist[start_idx + i]
		var ratio: float = clampf((v - lo) / (hi - lo), 0.0, 1.0)
		var pt: Vector2 = Vector2(sx + i * step, sy + sh * (1.0 - ratio))
		if i > 0:
			var c: Color = _metric_color(metric, v).lerp(Color(0.3, 0.3, 0.4), 0.3)
			_panel.draw_line(prev, pt, c, 1.0)
		prev = pt


# -- Snapshot Dump -------------------------------------------------------------

func _dump_snapshot(trigger: String) -> void:
	var lines: PackedStringArray = PackedStringArray()
	var sep: String = "=" .repeat(72)

	lines.append(sep)
	lines.append("PERF SNAPSHOT — %s — %s" % [trigger, Time.get_datetime_string_from_system()])
	lines.append(sep)

	# FPS summary
	var fps: float = Performance.get_monitor(Performance.TIME_FPS)
	var min_fps: float = INF
	var sum_fps: float = 0.0
	for s in _fps_samples:
		min_fps = minf(min_fps, s)
		sum_fps += s
	var avg_fps: float = sum_fps / _fps_samples.size() if _fps_samples.size() > 0 else 0.0
	lines.append("FPS: current=%d  avg=%d  min=%d  samples=%d  spikes=%d" % [
		int(fps), int(avg_fps), int(min_fps), _fps_samples.size(), _spike_count])
	lines.append("")

	# All metrics by group
	var last_group: String = ""
	for metric in _metrics:
		if metric.group != last_group:
			last_group = metric.group
			lines.append("--- %s ---" % metric.group)
		var val: float = _metric_values[metric.id]
		var val_str: String = (metric.format % val) + metric.unit

		# Include recent delta for history context
		var hist: PackedFloat32Array = _metric_history.get(metric.id, PackedFloat32Array())
		var delta_str: String = ""
		if hist.size() >= 60:
			var old_val: float = hist[hist.size() - 60]
			var delta: float = val - old_val
			if absf(delta) > 0.01:
				delta_str = "  (delta60: %s%.1f)" % ["+" if delta > 0 else "", delta]

		# Flag warnings
		var flag: String = ""
		if metric.alert_above > 0 and val > metric.alert_above:
			flag = " [ALERT]"
		elif metric.warn_above > 0 and val > metric.warn_above:
			flag = " [WARN]"
		elif metric.alert_below > 0 and val < metric.alert_below:
			flag = " [ALERT]"
		elif metric.warn_below > 0 and val < metric.warn_below:
			flag = " [WARN]"

		lines.append("  %-20s %s%s%s" % [metric.label + ":", val_str, delta_str, flag])
	lines.append("")

	# Object Pool detail
	lines.append("--- Object Pool ---")
	var pool: Node = _get_object_pool()
	if pool:
		var stats: Dictionary = pool.get_pool_stats()
		if stats.is_empty():
			lines.append("  (no pool activity)")
		else:
			for key in stats:
				var s: Dictionary = stats[key]
				var hit_rate: String = "N/A"
				if s.acquires > 0:
					hit_rate = "%d%%" % int(100.0 * (1.0 - float(s.misses) / float(s.acquires)))
				lines.append("  %-20s pooled=%d  acquires=%d  misses=%d  hit=%s" % [
					key + ":", s.pool_size, s.acquires, s.misses, hit_rate])
	else:
		lines.append("  (ObjectPool not registered as autoload)")
	lines.append("")

	# Entity census
	lines.append("--- Entity Census ---")
	_dump_entity_census(lines)
	lines.append("")

	# Music system status
	lines.append("--- Music ---")
	_dump_music_status(lines)
	lines.append("")

	lines.append(sep)
	lines.append("END SNAPSHOT")
	lines.append(sep)

	# Print to stdout
	for line in lines:
		print(line)


func _dump_entity_census(lines: PackedStringArray) -> void:
	var tree: SceneTree = get_tree()
	if not tree:
		lines.append("  (no scene tree)")
		return

	# Enemies
	var enemies: Array[Node] = tree.get_nodes_in_group("enemies")
	lines.append("  Enemies: %d" % enemies.size())
	for enemy in enemies:
		var info: String = "    %s" % _entity_label(enemy)
		# Try to get state
		if enemy.has_method("get") and enemy.get("_state") != null:
			var state_val: int = enemy.get("_state")
			# Try State enum
			if "State" in enemy:
				var keys: PackedStringArray = PackedStringArray(enemy.State.keys())
				if state_val >= 0 and state_val < keys.size():
					info += " state=%s" % keys[state_val]
				else:
					info += " state=%d" % state_val
			else:
				info += " state=%d" % state_val
		# Position
		if enemy.has_method("get") and enemy.get("global_position") != null:
			var pos: Vector2 = enemy.global_position
			info += " pos=(%.0f,%.0f)" % [pos.x, pos.y]
		# HP
		if enemy.has_method("get") and enemy.get("_hp") != null:
			info += " hp=%s" % str(enemy.get("_hp"))
		elif enemy.has_method("get") and enemy.get("health") != null:
			info += " hp=%s" % str(enemy.get("health"))
		# Process mode — only flag when actually stopped (both idle = truly frozen)
		var has_process: bool = enemy.is_processing()
		var has_physics: bool = enemy.is_physics_processing()
		if not has_process and not has_physics:
			info += " [FROZEN]"
		elif not has_physics:
			info += " [NO_PHYSICS]"
		if not enemy.visible:
			info += " [HIDDEN]"
		lines.append(info)
		# Section profiler data (quadruped_monster has _perf_sections)
		if enemy.get("_perf_sections") != null and not enemy._perf_sections.is_empty():
			var total_us: float = enemy._perf_total_usec
			lines.append("      physics_frame: %.0fus (%.1fms) | peak: %.0fus (%.1fms)" % [
				total_us, total_us / 1000.0, enemy._perf_peak_total, enemy._perf_peak_total / 1000.0])
			# Sort sections by peak time descending
			var section_list: Array = []
			for sec_name in enemy._perf_peak_sections:
				section_list.append([sec_name, enemy._perf_sections.get(sec_name, 0.0), enemy._perf_peak_sections[sec_name]])
			section_list.sort_custom(func(a: Array, b: Array) -> bool: return a[2] > b[2])
			for sec in section_list:
				var flag: String = " <<<" if sec[2] > 2000.0 else ""  # Flag >2ms peaks
				lines.append("        %-16s last:%6.0fus  peak:%6.0fus%s" % [sec[0], sec[1], sec[2], flag])
			# Reset peaks after reading so next snapshot shows fresh data
			enemy._perf_peak_sections.clear()
			enemy._perf_peak_total = 0.0

	# Players
	var players: Array[Node] = tree.get_nodes_in_group("players")
	lines.append("  Players: %d" % players.size())
	for player in players:
		var info: String = "    %s" % _entity_label(player)
		if player.get("global_position") != null:
			var pos: Vector2 = player.global_position
			info += " pos=(%.0f,%.0f)" % [pos.x, pos.y]
		if player.get("_hp") != null:
			info += " hp=%s" % str(player.get("_hp"))
		if not player.visible:
			info += " [HIDDEN]"
		lines.append(info)

	# Loose items (projectiles, fireballs, etc.)
	var loose: Array[Node] = tree.get_nodes_in_group("loose_items")
	if loose.size() > 0:
		lines.append("  Loose Items: %d" % loose.size())
		# Categorize by script/type
		var by_type: Dictionary = {}  # class_name -> count
		for item in loose:
			var type_name: String = item.get_script().get_global_name() if item.get_script() else item.get_class()
			if type_name.is_empty():
				type_name = item.get_script().resource_path.get_file().get_basename() if item.get_script() else "Unknown"
			by_type[type_name] = by_type.get(type_name, 0) + 1
		for type_name in by_type:
			lines.append("    %s: %d" % [type_name, by_type[type_name]])

	# Attack dummies
	var dummies: Array[Node] = tree.get_nodes_in_group("attack_dummies")
	if dummies.size() > 0:
		lines.append("  Dummies: %d" % dummies.size())

	# Chains
	var chains: Array[Node] = tree.get_nodes_in_group("chains")
	if chains.size() > 0:
		lines.append("  Chains: %d" % chains.size())
		for chain in chains:
			var info: String = "    %s" % chain.name
			if chain.get("_links") != null:
				info += " links=%d" % chain.get("_links").size()
			lines.append(info)

	# Tethers
	var tethers: Array[Node] = tree.get_nodes_in_group("tethers")
	if tethers.size() > 0:
		lines.append("  Tethers: %d" % tethers.size())

	# Bosses
	var bosses: Array[Node] = tree.get_nodes_in_group("bosses")
	if bosses.size() > 0:
		lines.append("  Bosses: %d" % bosses.size())
		for boss in bosses:
			var info: String = "    %s" % boss.name
			if boss.get("global_position") != null:
				info += " pos=(%.0f,%.0f)" % [boss.global_position.x, boss.global_position.y]
			lines.append(info)

	# Bugs (fireflies, etc.)
	var bugs: Array[Node] = tree.get_nodes_in_group("bugs")
	if bugs.size() > 0:
		lines.append("  Bugs/Ambient: %d" % bugs.size())


func _dump_music_status(lines: PackedStringArray) -> void:
	if not is_instance_valid(MusicManager):
		lines.append("  (MusicManager not available)")
		return

	# Composition
	var comp: Variant = MusicManager.get_composition() if MusicManager.has_method("get_composition") else null
	if comp:
		lines.append("  Composition: %s" % comp.id)
		var rec: Variant = MusicManager.get_record() if MusicManager.has_method("get_record") else null
		if rec and rec.current_bar:
			var bar = rec.current_bar
			var section: String = bar.get_section_id() if bar.has_method("get_section_id") else "?"
			lines.append("  Section: %s  played_bars=%d  cued=%d" % [
				section, rec.played_bars.size(), rec.cued_bars.size()])
		var in_trans: bool = MusicManager.composition_is_in_transition() if MusicManager.has_method("composition_is_in_transition") else false
		lines.append("  In transition: %s" % str(in_trans))

	# CPS
	if MusicManager.get("_strudel_cps") != null:
		lines.append("  CPS: %.3f" % MusicManager._strudel_cps)
	if MusicManager.get("_cps_ramp_active") != null and MusicManager._cps_ramp_active:
		lines.append("  CPS Ramp: %.2f → %.2f (%.1fs elapsed of %.1fs)" % [
			MusicManager._cps_ramp_from, MusicManager._cps_ramp_to,
			MusicManager._cps_ramp_elapsed, MusicManager._cps_ramp_duration])

	# Active SiON voices
	if MusicManager.get("_sion_trigger") != null and MusicManager._sion_trigger:
		var trigger: Variant = MusicManager._sion_trigger
		if trigger.get("_active_notes") != null:
			var total_active: int = 0
			for voice_name in trigger._active_notes:
				total_active += trigger._active_notes[voice_name].size()
			lines.append("  Active SiON notes: %d" % total_active)
			if total_active > 0:
				for voice_name in trigger._active_notes:
					var notes: Array = trigger._active_notes[voice_name]
					if notes.size() > 0:
						lines.append("    %s: %d notes" % [voice_name, notes.size()])


# -- Helpers -------------------------------------------------------------------

func _count_group(group_name: String) -> float:
	var tree: SceneTree = get_tree()
	if not tree:
		return 0.0
	return float(tree.get_nodes_in_group(group_name).size())


func _pool_total(field: String) -> float:
	var pool: Node = _get_object_pool()
	if not pool:
		return 0.0
	var stats: Dictionary = pool.get_pool_stats()
	var total: float = 0.0
	for key in stats:
		total += float(stats[key].get(field, 0))
	return total


var _object_pool_cache: Node = null
var _object_pool_checked: bool = false

func _get_object_pool() -> Node:
	## Safely find the ObjectPool autoload (may not be registered).
	if _object_pool_checked:
		return _object_pool_cache
	_object_pool_checked = true
	_object_pool_cache = get_node_or_null("/root/ObjectPool")
	return _object_pool_cache


func _entity_label(node: Node) -> String:
	## Best-effort human-readable name for an entity: script class > node name.
	var script: Script = node.get_script()
	if script:
		var class_nm: String = script.get_global_name()
		if not class_nm.is_empty():
			return "%s (%s)" % [class_nm, node.name]
		# Fall back to filename
		var path: String = script.resource_path
		if not path.is_empty():
			return "%s (%s)" % [path.get_file().get_basename(), node.name]
	return node.name


func _fps_color(fps: float) -> Color:
	if fps >= 55.0:
		return Color(0.3, 1.0, 0.3)
	elif fps >= 30.0:
		return Color(1.0, 0.9, 0.2)
	else:
		return Color(1.0, 0.3, 0.2)


func _metric_color(metric: MetricDef, val: float) -> Color:
	# Check alert thresholds (red)
	if metric.alert_above > 0 and val > metric.alert_above:
		return Color(1.0, 0.3, 0.2)
	if metric.alert_below > 0 and val < metric.alert_below:
		return Color(1.0, 0.3, 0.2)
	# Check warn thresholds (yellow)
	if metric.warn_above > 0 and val > metric.warn_above:
		return Color(1.0, 0.85, 0.2)
	if metric.warn_below > 0 and val < metric.warn_below:
		return Color(1.0, 0.85, 0.2)
	# Normal (green-ish white)
	return Color(0.7, 0.8, 0.7)


# -- RCON Integration ----------------------------------------------------------

func get_status_text() -> String:
	## For RCON "perf" command — returns current metrics as text.
	var lines: PackedStringArray = PackedStringArray()
	var fps: float = Performance.get_monitor(Performance.TIME_FPS)
	lines.append("FPS: %d  mode: %s  spikes: %d" % [
		int(fps), "expanded" if _mode == Mode.EXPANDED else "compact", _spike_count])
	var last_group: String = ""
	for metric in _metrics:
		if metric.group != last_group:
			last_group = metric.group
			lines.append("  [%s]" % metric.group)
		var val: float = _metric_values[metric.id]
		lines.append("    %-18s %s%s" % [metric.label, metric.format % val, metric.unit])
	return "\n".join(lines)


func set_mode(mode_name: String) -> String:
	match mode_name:
		"compact":
			_mode = Mode.COMPACT
			return "OK: perf mode = compact"
		"expanded":
			_mode = Mode.EXPANDED
			return "OK: perf mode = expanded"
		_:
			return "ERR: unknown mode '%s' (use compact/expanded)" % mode_name


func trigger_snapshot() -> String:
	_dump_snapshot("RCON")
	return "OK: snapshot dumped to log"


func reset_spikes() -> String:
	_spike_count = 0
	_last_spike_time = -999.0
	return "OK: spike counter reset"
