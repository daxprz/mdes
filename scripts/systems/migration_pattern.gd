extends Node

## Manages a single migration pattern — a repeating multi-phase sequence of zones.
## Species associated with this pattern are compelled toward the nearest active zone.
## Once an individual arrives at a zone, it returns to normal behavior until the phase advances.

var pattern_id: String = ""
var species: String = "fireflies"  # One species per pattern
var cadence: float = 30.0
var stagger: bool = false  # When true, each individual gets a random phase offset
var phases: Array = []  # Array of Arrays of zone dicts: [{zone_id, point, radius, strength}]
var active_phase: int = 0  # 0-based index into phases

var _timer: float = 0.0


func setup_from_config(config: Dictionary) -> void:
	pattern_id = config.get("id", "")
	cadence = config.get("cadence", 30.0)
	stagger = config.get("stagger", false)

	species = str(config.get("species", "fireflies"))

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


func effective_phase(offset: int) -> int:
	## Returns the effective phase index for an individual with the given offset.
	if phases.is_empty():
		return 0
	return (active_phase + offset) % phases.size()


func get_zones_for_phase(phase_idx: int) -> Array:
	if phase_idx >= 0 and phase_idx < phases.size():
		return phases[phase_idx]
	return []


func get_zone_ids_for_phase(phase_idx: int) -> Array[int]:
	var ids: Array[int] = []
	for zone in get_zones_for_phase(phase_idx):
		ids.append(zone["zone_id"])
	return ids


func get_active_zones() -> Array:
	return get_zones_for_phase(active_phase)


func get_active_zone_ids() -> Array[int]:
	return get_zone_ids_for_phase(active_phase)


func has_species(species_name: String) -> bool:
	return species == species_name


func get_nearest_zone_in_phase(pos: Vector2, phase_idx: int) -> Dictionary:
	## Returns the nearest zone in the given phase to the position, or empty dict.
	var best: Dictionary = {}
	var best_dist: float = INF
	for zone in get_zones_for_phase(phase_idx):
		var d: float = pos.distance_to(zone["point"])
		if d < best_dist:
			best_dist = d
			best = zone
	return best


func get_nearest_zone(pos: Vector2) -> Dictionary:
	return get_nearest_zone_in_phase(pos, active_phase)


func is_in_zone(pos: Vector2, zone: Dictionary) -> bool:
	return pos.distance_to(zone["point"]) < zone["radius"]


func generate_offset() -> int:
	## Returns a random phase offset if stagger is enabled, else 0.
	if stagger and phases.size() > 1:
		return randi() % phases.size()
	return 0
