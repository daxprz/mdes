extends Node2D

## Test Bounded Leaps — stores and renders leap-graph constraints for automated tests.
## Each "check" specifies a source platform (A), destination platform (B), and one or
## more Plans. A Plan passes if: the launch is in START, landing is in END, and no
## DISALLOW path is penetrated by any arc. The check is matched if any plan passes.
##
## Rendered as color-coded overlays:
##   GREY  = pending (not yet evaluated)
##   GREEN = matched
##   RED   = failed
##
## Managed by RCON via _ensure_leap_checker(). Used by test_runner for bounded_leaps checks.

const PENDING_FILL    := Color(0.55, 0.55, 0.55, 0.20)
const MATCHED_FILL    := Color(0.20, 0.85, 0.30, 0.25)
const FAILED_FILL     := Color(0.85, 0.20, 0.20, 0.25)
const PENDING_OUTLINE := Color(0.65, 0.65, 0.65, 0.75)
const MATCHED_OUTLINE := Color(0.25, 1.00, 0.35, 0.90)
const FAILED_OUTLINE  := Color(1.00, 0.25, 0.25, 0.90)
const LABEL_SIZE      := 10

## Each entry: {id, platform_a, platform_b, plans, state, matched_plans, failed_plans}
var _checks: Array[Dictionary] = []
var _evaluated: bool = false


func set_checks(checks_array: Array) -> void:
	## Load constraints from the test JSON leap_defs array. Resets evaluation state.
	_checks.clear()
	var id: int = 1
	for c in checks_array:
		_checks.append({
			"id": id,
			"platform_a": c.get("platform_a", {}),
			"platform_b": c.get("platform_b", {}),
			"plans": c.get("plans", []),
			"state": "pending",
			"matched_plans": [],   # Array[int] of plan indices that matched
			"failed_plans": [],    # Array[int] of plan indices that failed
		})
		id += 1
	_evaluated = false
	queue_redraw()


func update_check_state(check_idx: int, state: String,
		matched_plans: Array, failed_plans: Array) -> void:
	## Called by test_runner after evaluation to update visual state.
	if check_idx >= 0 and check_idx < _checks.size():
		_checks[check_idx]["state"] = state
		_checks[check_idx]["matched_plans"] = matched_plans
		_checks[check_idx]["failed_plans"] = failed_plans
	_evaluated = true
	queue_redraw()


func clear_checks() -> void:
	_checks.clear()
	_evaluated = false
	queue_redraw()


func _draw() -> void:
	if not DebugOverlay.should_draw("testing/bounded_leap_checks", self):
		return

	var font: Font = ThemeDB.fallback_font

	for check in _checks:
		var state: String = check["state"]
		var fill_col: Color = PENDING_FILL
		var out_col:  Color = PENDING_OUTLINE
		match state:
			"matched": fill_col = MATCHED_FILL;  out_col = MATCHED_OUTLINE
			"failed":  fill_col = FAILED_FILL;   out_col = FAILED_OUTLINE

		var cid: int = check["id"]

		# -- Platform A circle --
		var pa: Dictionary = check["platform_a"]
		if not pa.is_empty():
			var pa_pos := Vector2(float(pa.get("x", 0)), float(pa.get("y", 0))) - global_position
			var pa_r: float = float(pa.get("radius", 60))
			draw_circle(pa_pos, pa_r, Color(fill_col.r, fill_col.g, fill_col.b, fill_col.a * 0.6))
			draw_arc(pa_pos, pa_r, 0.0, TAU, 36, out_col, 2.0)
			draw_string(font, pa_pos + Vector2(-10, -pa_r - 5),
				"A%d" % cid, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, out_col)

		# -- Platform B circle --
		var pb: Dictionary = check["platform_b"]
		if not pb.is_empty():
			var pb_pos := Vector2(float(pb.get("x", 0)), float(pb.get("y", 0))) - global_position
			var pb_r: float = float(pb.get("radius", 60))
			draw_circle(pb_pos, pb_r, Color(fill_col.r, fill_col.g, fill_col.b, fill_col.a * 0.6))
			draw_arc(pb_pos, pb_r, 0.0, TAU, 36, out_col, 2.0)
			draw_string(font, pb_pos + Vector2(-10, -pb_r - 5),
				"B%d" % cid, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, out_col)

		# -- Per-plan constraints --
		for pi in range(check["plans"].size()):
			var plan: Dictionary = check["plans"][pi]
			var required: bool = plan.get("required", false)

			# Plan result state
			var p_state: String = "pending"
			if check["matched_plans"].has(pi):
				p_state = "matched"
			elif check["failed_plans"].has(pi):
				p_state = "failed"

			var p_fill: Color = PENDING_FILL
			var p_out:  Color = PENDING_OUTLINE
			match p_state:
				"matched": p_fill = MATCHED_FILL;  p_out = MATCHED_OUTLINE
				"failed":  p_fill = FAILED_FILL;   p_out = FAILED_OUTLINE

			var plan_label: String = "P%d.%d" % [cid, pi + 1]
			if required:
				plan_label += "!"

			# START rectangle
			var start: Dictionary = plan.get("start", {})
			if not start.is_empty():
				var sx: float = float(start.get("x", 0))
				var sy: float = float(start.get("y", 0))
				var sw: float = float(start.get("w", 50))
				var sh: float = float(start.get("h", 20))
				var local_rect := Rect2(Vector2(sx, sy) - global_position, Vector2(sw, sh))
				draw_rect(local_rect, Color(p_fill.r, p_fill.g, p_fill.b, 0.18))
				draw_rect(local_rect, p_out, false, 2.0)
				draw_string(font, local_rect.position + Vector2(4, sh + 13),
					"START " + plan_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, p_out)

			# END circle
			var end_d: Dictionary = plan.get("end", {})
			if not end_d.is_empty():
				var ex: float = float(end_d.get("x", 0))
				var ey: float = float(end_d.get("y", 0))
				var er: float = float(end_d.get("radius", 40))
				var e_pos := Vector2(ex, ey) - global_position
				draw_circle(e_pos, er, Color(p_fill.r, p_fill.g, p_fill.b, 0.18))
				draw_arc(e_pos, er, 0.0, TAU, 32, p_out, 2.0)
				draw_string(font, e_pos + Vector2(-12, -er - 5),
					"END " + plan_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, p_out)

			# DISALLOW capsules (path + radius)
			var disallows: Array = plan.get("disallow", [])
			for di in range(disallows.size()):
				var dis: Dictionary = disallows[di]
				var dr: float = float(dis.get("radius", 20))
				var p1 := Vector2(float(dis.get("x1", 0)), float(dis.get("y1", 0))) - global_position
				var p2 := Vector2(float(dis.get("x2", 0)), float(dis.get("y2", 0))) - global_position
				# Use red for disallow regardless of plan state (it's a forbidden zone)
				var dis_col: Color = PENDING_OUTLINE if p_state == "pending" else p_out
				var dis_fill := Color(0.85, 0.25, 0.25, 0.15)
				# Thick line = capsule body
				draw_line(p1, p2, Color(dis_fill.r, dis_fill.g, dis_fill.b, 0.25), dr * 2.0)
				draw_line(p1, p2, dis_col, 2.0)
				draw_circle(p1, dr, Color(dis_fill.r, dis_fill.g, dis_fill.b, 0.20))
				draw_circle(p2, dr, Color(dis_fill.r, dis_fill.g, dis_fill.b, 0.20))
				draw_string(font, p1 + Vector2(0, -dr - 5),
					"NO P%d.%d.%d" % [cid, pi + 1, di + 1], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, dis_col)

			# REQUIRED indicator (only shown after evaluation)
			if required and _evaluated:
				# Place indicator near the END circle if present, else near platform B
				var ind_pos: Vector2
				if not end_d.is_empty():
					ind_pos = Vector2(float(end_d.get("x", 0)), float(end_d.get("y", 0))) \
						- global_position + Vector2(0, -float(end_d.get("radius", 40)) - 20)
				elif not pb.is_empty():
					ind_pos = Vector2(float(pb.get("x", 0)), float(pb.get("y", 0))) \
						- global_position + Vector2(0, -float(pb.get("radius", 60)) - 20)
				else:
					ind_pos = Vector2.ZERO

				match p_state:
					"matched": _draw_checkmark(ind_pos, 24, MATCHED_OUTLINE)
					"failed":  _draw_x_mark(ind_pos, 24, FAILED_OUTLINE)


func _draw_checkmark(center: Vector2, size: float, color: Color) -> void:
	var h: float = size * 0.5
	draw_line(center + Vector2(-h * 0.6,  0.0),   center + Vector2(-h * 0.1, h * 0.4), color, 3.0)
	draw_line(center + Vector2(-h * 0.1,  h * 0.4), center + Vector2(h * 0.6, -h * 0.4), color, 3.0)


func _draw_x_mark(center: Vector2, size: float, color: Color) -> void:
	var h: float = size * 0.4
	draw_line(center + Vector2(-h, -h), center + Vector2( h,  h), color, 3.0)
	draw_line(center + Vector2( h, -h), center + Vector2(-h,  h), color, 3.0)
