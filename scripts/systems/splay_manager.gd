extends Node

## Splay Manager — loads pose definitions, spawns splayed creatures with auto-tethers.
## Poses stored as JSON in res://data/splay_poses/ (bundled) and user://data/splay_poses/ (overrides).

const BUNDLED_PATH := "res://data/splay_poses/"
const USER_PATH := "user://data/splay_poses/"
const TETHER_CAST_MAX_DIST := 800.0  # Max raycast distance for finding surfaces

var _poses: Dictionary = {}  # name -> parsed Dictionary
var _splay_instances: Array = []  # Array of { creatures: Array[Node2D], tethers: Array[Node2D], pose_name: String }


func _ready() -> void:
	_load_all_poses()


func _load_all_poses() -> void:
	_poses.clear()
	# Load bundled first, then user overrides
	_load_poses_from_dir(BUNDLED_PATH)
	_load_poses_from_dir(USER_PATH)


func _load_poses_from_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if not dir:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var full_path: String = dir_path + file_name
			var file := FileAccess.open(full_path, FileAccess.READ)
			if file:
				var text: String = file.get_as_text()
				file.close()
				var json := JSON.new()
				if json.parse(text) == OK:
					var data: Dictionary = json.data
					if data.has("name"):
						_poses[data["name"]] = data
		file_name = dir.get_next()


func load_pose(pose_name: String) -> Dictionary:
	if _poses.has(pose_name):
		return _poses[pose_name]
	return {}


func get_all_pose_names() -> Array[String]:
	var names: Array[String] = []
	for k in _poses:
		names.append(k)
	names.sort()
	return names


func save_pose(pose: Dictionary) -> void:
	var name: String = pose.get("name", "")
	if name.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(USER_PATH)
	var path: String = USER_PATH + name + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(pose, "\t"))
		file.close()
	_poses[name] = pose


func spawn_splay(pose_name: String, pos: Vector2, rotation_deg: float = 0.0, behavior: String = "asleep") -> Dictionary:
	## Spawn a splay instance: creature(s) + tethers. Returns instance data dict.
	## Supports single-creature (legacy "creature" + "connections" keys) and
	## multi-creature ("creatures" array) pose formats.
	var pose: Dictionary = load_pose(pose_name)
	if pose.is_empty():
		push_warning("SplayManager: pose '%s' not found" % pose_name)
		return {}

	var scene_root: Node = get_tree().current_scene
	if not scene_root:
		return {}

	var rotation_rad: float = deg_to_rad(rotation_deg)

	# Determine creature list — support both single and multi formats
	var creature_defs: Array = []
	if pose.has("creatures"):
		creature_defs = pose["creatures"]
	else:
		# Legacy single-creature format
		creature_defs = [{
			"creature_type": pose.get("creature", "quadruped"),
			"offset": [0, 0],
			"connections": pose.get("connections", []),
			"behavior": behavior,
		}]

	# Spawn all creatures
	var creatures: Array = []
	for cdef in creature_defs:
		var c_type: String = cdef.get("creature_type", "quadruped")
		var c_offset_arr: Array = cdef.get("offset", [0, 0])
		var c_offset := Vector2(c_offset_arr[0], c_offset_arr[1])
		if rotation_rad != 0.0:
			c_offset = c_offset.rotated(rotation_rad)
		var c_behavior: String = cdef.get("behavior", behavior)
		var creature: Node2D = _spawn_creature(c_type, pos + c_offset)
		if creature:
			# Freeze physics until tethers are connected
			if "_physics_frozen" in creature:
				creature._physics_frozen = true
			creatures.append({"node": creature, "def": cdef, "behavior": c_behavior})

	if creatures.is_empty():
		return {}

	# Wait a frame for physics to initialize
	await get_tree().physics_frame

	var TetherScript: GDScript = load("res://scripts/systems/tether.gd")
	var tethers: Array = []
	var all_creatures_nodes: Array = []
	for c in creatures:
		all_creatures_nodes.append(c["node"])

	# Create tethers for each creature's connections
	for ci in range(creatures.size()):
		var c: Dictionary = creatures[ci]
		var creature: Node2D = c["node"]
		var connections: Array = c["def"].get("connections", [])

		for conn in connections:
			var point_name: String = conn.get("point", "")
			var target: String = conn.get("target", "world")  # "world" or "creature:<idx>:<point>"

			if target.begins_with("creature:"):
				# Inter-creature tether: creature:<index>:<attachment_point>
				var parts: PackedStringArray = target.split(":")
				if parts.size() >= 3:
					var target_ci: int = int(parts[1])
					var target_point: String = parts[2]
					if target_ci < creatures.size():
						var target_creature: Node2D = creatures[target_ci]["node"]
						var anchor_a: Dictionary = TetherScript.make_anchor_body(creature, point_name)
						var anchor_b: Dictionary = TetherScript.make_anchor_body(target_creature, target_point)
						var dist: float = TetherScript.get_anchor_world_pos(anchor_a).distance_to(TetherScript.get_anchor_world_pos(anchor_b))
						var tether := Node2D.new()
						tether.set_script(TetherScript)
						tether.setup(anchor_a, anchor_b, dist)
						scene_root.add_child(tether)
						tethers.append(tether)
			else:
				# World tether: raycast in cast direction
				var rel_pos_arr: Array = conn.get("relative_pos", [0, 0])
				var cast_dir_arr: Array = conn.get("cast_dir", [0, -1])
				var rel_pos := Vector2(rel_pos_arr[0], rel_pos_arr[1])
				var cast_dir := Vector2(cast_dir_arr[0], cast_dir_arr[1]).normalized()

				if rotation_rad != 0.0:
					rel_pos = rel_pos.rotated(rotation_rad)
					cast_dir = cast_dir.rotated(rotation_rad)

				var cast_origin: Vector2 = pos + rel_pos
				var cast_end: Vector2 = cast_origin + cast_dir * TETHER_CAST_MAX_DIST

				var space := creature.get_world_2d().direct_space_state
				var query := PhysicsRayQueryParameters2D.create(cast_origin, cast_end, 1)
				var result: Dictionary = space.intersect_ray(query)

				if not result:
					push_warning("SplayManager: raycast miss for point '%s' in pose '%s'" % [point_name, pose_name])
					continue

				var surface_pos: Vector2 = result["position"]
				var anchor_a: Dictionary = TetherScript.make_anchor_body(creature, point_name)
				var anchor_b: Dictionary = TetherScript.make_anchor_wall(surface_pos)
				var length: float = cast_origin.distance_to(surface_pos)

				var tether := Node2D.new()
				tether.set_script(TetherScript)
				tether.setup(anchor_a, anchor_b, length)
				scene_root.add_child(tether)
				tethers.append(tether)

		# Set behavior per creature
		_apply_behavior(creature, c["behavior"])

		# Set pose overrides for IK
		_apply_pose_overrides(creature, c["def"], rotation_rad)

		# Unfreeze physics now that tethers and pose are set
		if "_physics_frozen" in creature:
			creature._physics_frozen = false

	# Track instance
	var instance: Dictionary = {
		"creatures": all_creatures_nodes,
		"tethers": tethers,
		"pose_name": pose_name,
		"pos": pos,
		"rotation": rotation_deg,
		"behavior": behavior,
		"breakaway_sound": pose.get("breakaway_sound", ""),
	}
	_splay_instances.append(instance)

	# Start monitoring for breakaway
	_monitor_breakaway(instance)

	return instance


func _spawn_creature(creature_type: String, pos: Vector2) -> Node2D:
	match creature_type:
		"quadruped":
			var script: GDScript = load("res://scripts/enemies/quadruped_monster.gd")
			var creature := CharacterBody2D.new()
			creature.set_script(script)
			creature.global_position = pos
			var container: Node = get_tree().current_scene.get_node_or_null("Players")
			if not container:
				container = get_tree().current_scene
			container.add_child(creature)
			return creature
	push_warning("SplayManager: unknown creature type '%s'" % creature_type)
	return null


func _apply_behavior(creature: Node2D, behavior: String) -> void:
	match behavior:
		"active":
			if "_standdown" in creature:
				creature._standdown = false
			if "_asleep" in creature:
				creature._asleep = false
		"stand_down":
			if "_standdown" in creature:
				creature._standdown = true
			if "_asleep" in creature:
				creature._asleep = false
		"asleep":
			if "_asleep" in creature:
				creature._asleep = true
			if "_standdown" in creature:
				creature._standdown = false  # Asleep mode handles its own AI skip


func _apply_pose_overrides(creature: Node2D, pose: Dictionary, rotation_rad: float) -> void:
	if not creature.has_method("set_pose_overrides"):
		return
	var overrides: Dictionary = {}
	for conn in pose.get("connections", []):
		var point_name: String = conn.get("point", "")
		var rel_pos_arr: Array = conn.get("relative_pos", [0, 0])
		var rel_pos := Vector2(rel_pos_arr[0], rel_pos_arr[1])
		if rotation_rad != 0.0:
			rel_pos = rel_pos.rotated(rotation_rad)
		overrides[point_name] = rel_pos
	creature.set_pose_overrides(overrides)


func _monitor_breakaway(instance: Dictionary) -> void:
	## Polls tether damage each frame. Triggers breakaway at 50% aggregate damage.
	# Use a deferred call loop instead of _process to keep it simple
	_check_breakaway_loop(instance)


func _check_breakaway_loop(instance: Dictionary) -> void:
	if not is_inside_tree():
		return
	# Check if instance is still valid
	var valid_tethers: Array = []
	var total_max_hp: float = 0.0
	var total_damage: float = 0.0
	for t in instance["tethers"]:
		if is_instance_valid(t) and not t._severed:
			total_max_hp += t.TETHER_MAX_HP
			total_damage += (t.TETHER_MAX_HP - t.current_hp)
			valid_tethers.append(t)

	if valid_tethers.is_empty():
		# All tethers gone — trigger breakaway if not already
		_trigger_breakaway(instance)
		return

	if total_max_hp > 0 and total_damage > total_max_hp * 0.5:
		_trigger_breakaway(instance)
		return

	# Check again next frame
	await get_tree().process_frame
	_check_breakaway_loop(instance)


func _trigger_breakaway(instance: Dictionary) -> void:
	# Sever all remaining tethers
	for t in instance["tethers"]:
		if is_instance_valid(t) and not t._severed:
			t.sever()

	# Breakaway effects on each creature
	for creature in instance["creatures"]:
		if not is_instance_valid(creature):
			continue

		# Clear pose overrides
		if creature.has_method("clear_pose_overrides"):
			creature.clear_pose_overrides()

		# Wake up
		if "_standdown" in creature:
			creature._standdown = false
		if "_asleep" in creature:
			creature._asleep = false

		# Brief invincibility
		if "_breakaway_immune" in creature:
			creature._breakaway_immune = 0.5

		# Flash
		creature.modulate = Color(1.5, 1.2, 1.0)
		var tween: Tween = creature.create_tween()
		tween.tween_property(creature, "modulate", Color.WHITE, 0.3)

	# Sound
	var sound: String = instance.get("breakaway_sound", "")
	if sound != "" and ResourceLoader.exists(sound):
		AudioManager.play_resource(sound)
	else:
		AudioManager.play("grapple_hit", 4.0, 0.5)  # Default: loud snap

	# Screen shake
	var cam := get_viewport().get_camera_2d()
	if cam:
		var orig: Vector2 = cam.offset
		for i in range(6):
			cam.offset = orig + Vector2(randf_range(-6, 6), randf_range(-6, 6))
			await get_tree().create_timer(0.04).timeout
		if is_instance_valid(cam):
			cam.offset = orig

	# Remove from tracked instances
	_splay_instances.erase(instance)


func clear_all_splays() -> int:
	var count: int = _splay_instances.size()
	for instance in _splay_instances.duplicate():
		for t in instance["tethers"]:
			if is_instance_valid(t):
				t.queue_free()
		for c in instance["creatures"]:
			if is_instance_valid(c):
				c.queue_free()
	_splay_instances.clear()
	return count


func get_splay_status() -> Array[String]:
	var lines: Array[String] = ["splays: %d" % _splay_instances.size()]
	for i in range(_splay_instances.size()):
		var inst: Dictionary = _splay_instances[i]
		var alive_tethers: int = 0
		var total_dmg: float = 0.0
		var total_hp: float = 0.0
		for t in inst["tethers"]:
			if is_instance_valid(t) and not t._severed:
				alive_tethers += 1
				total_hp += t.TETHER_MAX_HP
				total_dmg += (t.TETHER_MAX_HP - t.current_hp)
		var creature_count: int = 0
		for c in inst["creatures"]:
			if is_instance_valid(c):
				creature_count += 1
		var dmg_pct: String = "%.0f%%" % (total_dmg / total_hp * 100.0) if total_hp > 0 else "N/A"
		lines.append("  [%d] pose=%s pos=(%.0f,%.0f) rot=%.0f behavior=%s creatures=%d tethers=%d dmg=%s" % [
			i, inst["pose_name"], inst["pos"].x, inst["pos"].y, inst["rotation"],
			inst["behavior"], creature_count, alive_tethers, dmg_pct])
	return lines
