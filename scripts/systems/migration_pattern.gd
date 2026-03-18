extends Node

## Manages a single migration pattern — a repeating multi-phase sequence of zones.
## Species associated with this pattern are compelled toward the nearest active zone.
## Once an individual arrives at a zone, it returns to normal behavior until the phase advances.

var pattern_id: String = ""
var species: Array[String] = []
var cadence: float = 30.0
var phases: Array = []  # Array of Arrays of zone dicts: [{zone_id, point, radius, strength}]
var active_phase: int = 0  # 0-based index into phases

var _timer: float = 0.0


func setup_from_config(config: Dictionary) -> void:
	pattern_id = config.get("id", "")
	cadence = config.get("cadence", 30.0)

	var sp: Array = config.get("species", [])
	species.clear()
	for s in sp:
		species.append(str(s))

	phases.clear()
	var phase_configs: Array = config.get("phases", [])
	for phase_cfg in phase_configs:
		var zones: Array = []
		for zone_cfg in phase_cfg.get("zones", []):
			var point_arr: Array = zone_cfg.get("point", [0, 0])
			zones.append({
				"zone_id": int(zone_cfg.get("zone_id", 0)),
				"point": Vector2(point_arr[0], point_arr[1]),
				"radius": float(zone_cfg.get("radius", 100.0)),
				"strength": float(zone_cfg.get("strength", 2.0)),
			})
		phases.append(zones)

	active_phase = 0
	_timer = 0.0


func _process(delta: float) -> void:
	if phases.is_empty():
		return
	_timer += delta
	if _timer >= cadence:
		_timer -= cadence
		active_phase = (active_phase + 1) % phases.size()


func get_active_zones() -> Array:
	## Returns the zones for the current active phase.
	if active_phase >= 0 and active_phase < phases.size():
		return phases[active_phase]
	return []


func get_active_zone_ids() -> Array[int]:
	## Returns just the zone_ids for the current active phase.
	var ids: Array[int] = []
	for zone in get_active_zones():
		ids.append(zone["zone_id"])
	return ids


func has_species(species_name: String) -> bool:
	return species.has(species_name)


func get_nearest_zone(pos: Vector2) -> Dictionary:
	## Returns the nearest active zone to the given position, or empty dict.
	var best: Dictionary = {}
	var best_dist: float = INF
	for zone in get_active_zones():
		var d: float = pos.distance_to(zone["point"])
		if d < best_dist:
			best_dist = d
			best = zone
	return best


func is_in_zone(pos: Vector2, zone: Dictionary) -> bool:
	return pos.distance_to(zone["point"]) < zone["radius"]
