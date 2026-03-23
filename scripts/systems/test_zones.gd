extends Node2D

## Test Zone Manager — renders and tracks Expected Target Zones (ETZ)
## and Disallowed Zones (DAZ) for automated testing.

const ETZ_COLOR := Color(0.2, 0.8, 0.3, 0.35)
const ETZ_ENTERED_COLOR := Color(0.1, 1.0, 0.2, 0.5)
const DAZ_COLOR := Color(0.8, 0.2, 0.2, 0.35)
const DAZ_ENTERED_COLOR := Color(1.0, 0.1, 0.1, 0.5)
const LABEL_SIZE := 14
const MARK_SIZE := 32

var _zones: Array[Dictionary] = []  # {id, type, pos, radius, entity_id, entered, entered_order}
var _next_expected_order: int = 1
var _order_violation: bool = false


func add_etz(id: int, pos: Vector2, radius: float, entity_id: String = "") -> void:
	_zones.append({
		"id": id,
		"type": "etz",
		"pos": pos,
		"radius": radius,
		"entity_id": entity_id,
		"entered": false,
		"entered_order": -1,
	})
	queue_redraw()


func add_daz(id: int, pos: Vector2, radius: float, entity_id: String = "") -> void:
	_zones.append({
		"id": id,
		"type": "daz",
		"pos": pos,
		"radius": radius,
		"entity_id": entity_id,
		"entered": false,
		"entered_order": -1,
	})
	queue_redraw()


func clear_zones() -> void:
	_zones.clear()
	_next_expected_order = 1
	_order_violation = false
	queue_redraw()


func get_status() -> String:
	var lines: Array[String] = ["zones: %d" % _zones.size()]
	for z in _zones:
		var mark: String = "?" if not z["entered"] else ("OK" if z["type"] == "etz" else "FAIL")
		lines.append("  %s-%d: %s at (%.0f,%.0f) r=%.0f entity=%s" % [
			z["type"].to_upper(), z["id"], mark,
			z["pos"].x, z["pos"].y, z["radius"],
			z["entity_id"] if z["entity_id"] != "" else "*"])
	if _order_violation:
		lines.append("  ORDER VIOLATION detected")
	return "\n".join(lines)


func get_check_result() -> Dictionary:
	## Returns a summary for test runner checks.
	var etz_total: int = 0
	var etz_entered: int = 0
	var daz_total: int = 0
	var daz_violated: int = 0

	for z in _zones:
		if z["type"] == "etz":
			etz_total += 1
			if z["entered"]:
				etz_entered += 1
		else:
			daz_total += 1
			if z["entered"]:
				daz_violated += 1

	# Per-zone detail for the test editor
	var etz_details: Array = []
	var daz_details: Array = []
	for z in _zones:
		if z["type"] == "etz":
			etz_details.append({"id": z["id"], "entered": z["entered"]})
		else:
			daz_details.append({"id": z["id"], "violated": z["entered"]})

	return {
		"etz_entered": etz_entered,
		"etz_total": etz_total,
		"daz_violated": daz_violated,
		"daz_total": daz_total,
		"order_ok": not _order_violation,
		"all_pass": etz_entered == etz_total and daz_violated == 0 and not _order_violation,
		"etz_details": etz_details,
		"daz_details": daz_details,
	}


func _physics_process(_delta: float) -> void:
	var changed: bool = false
	for z in _zones:
		if z["entered"] and z["type"] == "etz":
			continue  # ETZ already entered, no need to re-check
		var entities: Array[Node] = _get_tracked_entities(z)
		for entity in entities:
			if not is_instance_valid(entity):
				continue
			var dist: float = entity.global_position.distance_to(z["pos"])
			if dist < z["radius"]:
				if not z["entered"]:
					z["entered"] = true
					changed = true
					if z["type"] == "etz":
						z["entered_order"] = _next_expected_order
						if z["id"] != _next_expected_order:
							_order_violation = true
							print("ETZ-%d ENTERED (expected order %d, actual %d) — ORDER VIOLATION" % [
								z["id"], z["id"], _next_expected_order])
						else:
							print("ETZ-%d ENTERED (order OK)" % z["id"])
						_next_expected_order += 1
					else:
						print("DAZ-%d ENTERED — VIOLATION by %s at (%.0f,%.0f)" % [
							z["id"], _get_entity_id(entity),
							entity.global_position.x, entity.global_position.y])
				break  # One entity entering is enough

	if changed:
		queue_redraw()


func _get_tracked_entities(zone: Dictionary) -> Array[Node]:
	## Get entities that should be tracked for this zone.
	## Only tracks enemies (monsters) — not players/dummies.
	var result: Array[Node] = []
	var entity_id: String = zone["entity_id"]

	for e in get_tree().get_nodes_in_group("enemies"):
		if entity_id == "" or _get_entity_id(e) == entity_id:
			result.append(e)
	return result


func _get_entity_id(node: Node) -> String:
	if "entity_id" in node:
		return node.entity_id
	return node.name


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font

	for z in _zones:
		var local_pos: Vector2 = z["pos"] - global_position
		var is_etz: bool = z["type"] == "etz"
		var entered: bool = z["entered"]

		# Circle fill
		var fill_color: Color
		if entered:
			fill_color = ETZ_ENTERED_COLOR if is_etz else DAZ_ENTERED_COLOR
		else:
			fill_color = ETZ_COLOR if is_etz else DAZ_COLOR
		draw_circle(local_pos, z["radius"], fill_color)

		# Circle outline
		var outline_color: Color = fill_color
		outline_color.a = 0.8
		draw_arc(local_pos, z["radius"], 0, TAU, 48, outline_color, 2.0)

		# Dashed inner ring
		var inner_r: float = z["radius"] * 0.6
		var dash_count: int = 16
		for i in range(dash_count):
			if i % 2 == 0:
				var a1: float = float(i) / dash_count * TAU
				var a2: float = float(i + 1) / dash_count * TAU
				draw_arc(local_pos, inner_r, a1, a2, 4, outline_color * Color(1, 1, 1, 0.5), 1.0)

		# Label: type + id
		var label: String = "%s-%d" % [z["type"].to_upper(), z["id"]]
		var label_pos: Vector2 = local_pos + Vector2(-20, -z["radius"] - 8)
		draw_string(font, label_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, outline_color)

		# Status mark
		if entered:
			if is_etz:
				# Green checkmark
				_draw_checkmark(local_pos, MARK_SIZE, Color(0.1, 1.0, 0.2))
			else:
				# Red X
				_draw_x_mark(local_pos, MARK_SIZE, Color(1.0, 0.1, 0.1))
		else:
			# Question mark
			draw_string(font, local_pos + Vector2(-8, 10), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, MARK_SIZE,
				Color(1, 1, 1, 0.6))

		# Entity filter label
		if z["entity_id"] != "":
			var eid_pos: Vector2 = local_pos + Vector2(-20, z["radius"] + 16)
			draw_string(font, eid_pos, z["entity_id"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
				Color(0.7, 0.7, 0.7, 0.6))


func _draw_checkmark(center: Vector2, size: float, color: Color) -> void:
	var half: float = size * 0.5
	var p1: Vector2 = center + Vector2(-half * 0.6, 0)
	var p2: Vector2 = center + Vector2(-half * 0.1, half * 0.4)
	var p3: Vector2 = center + Vector2(half * 0.6, -half * 0.4)
	draw_line(p1, p2, color, 4.0)
	draw_line(p2, p3, color, 4.0)


func _draw_x_mark(center: Vector2, size: float, color: Color) -> void:
	var half: float = size * 0.4
	draw_line(center + Vector2(-half, -half), center + Vector2(half, half), color, 4.0)
	draw_line(center + Vector2(half, -half), center + Vector2(-half, half), color, 4.0)
