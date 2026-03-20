extends RefCounted

## FABRIK-based chain IK solver with joint angle constraints.
## Solves a chain of rigid segments to reach a target position,
## respecting max bend angles at each joint.
## Used by the splay editor for interactive pose dragging.

const MAX_ITERATIONS := 10
const TOLERANCE := 0.5  # px — close enough to target


static func solve(chain: Array[Vector2], lengths: Array[float], max_angles: Array[float], target: Vector2, pin_root: bool = true, pinned: Array[bool] = []) -> Array[Vector2]:
	## Solve IK for a chain of points.
	## chain: array of Vector2 positions [root, joint1, joint2, ..., endpoint]
	## lengths: array of segment lengths (chain.size() - 1 entries)
	## max_angles: array of max bend angles in radians (chain.size() - 1 entries)
	## target: desired position for the last point in the chain
	## pin_root: if true, root stays fixed
	## pinned: array of bools per joint — pinned joints don't move
	## Returns: new chain positions

	if chain.size() < 2:
		return chain

	var result: Array[Vector2] = []
	var saved: Array[Vector2] = []  # Original positions for pinned joints
	for pt in chain:
		result.append(pt)
		saved.append(pt)

	var n: int = result.size()
	var root: Vector2 = result[0]

	for _iter in range(MAX_ITERATIONS):
		# Check if close enough
		if result[n - 1].distance_to(target) < TOLERANCE:
			break

		# --- FORWARD pass: move endpoint to target, work backward ---
		result[n - 1] = target
		for i in range(n - 2, -1, -1):
			if i < pinned.size() and pinned[i]:
				result[i] = saved[i]  # Pinned — don't move
				continue
			var dir: Vector2 = (result[i] - result[i + 1])
			if dir.length() < 0.001:
				dir = Vector2(0, -1)
			result[i] = result[i + 1] + dir.normalized() * lengths[i]

		# --- BACKWARD pass: pin root, work forward ---
		if pin_root:
			result[0] = root
		for i in range(1, n):
			if i < pinned.size() and pinned[i]:
				result[i] = saved[i]  # Pinned — don't move
				continue
			var dir: Vector2 = (result[i] - result[i - 1])
			if dir.length() < 0.001:
				dir = Vector2(0, 1)
			result[i] = result[i - 1] + dir.normalized() * lengths[i - 1]

		# --- Restore pinned positions ---
		for i in range(n):
			if i < pinned.size() and pinned[i]:
				result[i] = saved[i]

		# --- Angle constraint pass ---
		_apply_angle_constraints(result, lengths, max_angles)

	return result


static func _apply_angle_constraints(chain: Array[Vector2], lengths: Array[float], max_angles: Array[float]) -> void:
	## Enforce max bend angle at each joint.
	## The angle at joint i is measured between segment (i-1→i) and segment (i→i+1).
	for i in range(1, chain.size() - 1):
		if i - 1 >= max_angles.size() or i >= max_angles.size():
			continue
		var max_angle: float = max_angles[i]
		if max_angle >= PI:
			continue  # No constraint

		var prev_dir: Vector2 = (chain[i] - chain[i - 1]).normalized()
		var next_dir: Vector2 = (chain[i + 1] - chain[i]).normalized()

		if prev_dir.length() < 0.001 or next_dir.length() < 0.001:
			continue

		var angle_diff: float = prev_dir.angle_to(next_dir)
		if absf(angle_diff) > max_angle:
			var clamped_angle: float = prev_dir.angle() + clampf(angle_diff, -max_angle, max_angle)
			var new_dir: Vector2 = Vector2(cos(clamped_angle), sin(clamped_angle))
			var seg_len: float = lengths[i] if i < lengths.size() else chain[i].distance_to(chain[i + 1])
			chain[i + 1] = chain[i] + new_dir * seg_len


static func get_chain_for_point(point_name: String, creature: Node2D) -> Dictionary:
	## Returns { "chain": Array[Vector2], "lengths": Array[float], "max_angles": Array[float], "apply": Callable }
	## for a given attachment point name. The chain goes from origin (spine[1]) to the endpoint.
	## The "apply" callable writes solved positions back to the creature skeleton.

	if not is_instance_valid(creature):
		return {}

	var spine: Array = creature._spine if "_spine" in creature else []
	if spine.size() < 3:
		return {}

	var origin: Vector2 = spine[1]  # Torso = pin point

	match point_name:
		"head":
			var chain: Array[Vector2] = [
				spine[1], spine[0],
				creature._neck[1] if "_neck" in creature else spine[0],
				creature._skull if "_skull" in creature else spine[0],
			]
			var lengths: Array[float] = [28.0, 22.0, 16.1]
			var max_angles: Array[float] = [deg_to_rad(30), deg_to_rad(45), deg_to_rad(45)]
			var apply_fn := func(solved: Array[Vector2]):
				creature._spine[0] = solved[1]
				creature._neck[1] = solved[2]
				creature._skull = solved[3]
			return { "chain": chain, "lengths": lengths, "max_angles": max_angles, "apply": apply_fn }

		"tail_tip":
			var chain: Array[Vector2] = [spine[1], spine[2]]
			var lengths: Array[float] = [28.0]
			var max_angles: Array[float] = [deg_to_rad(30)]
			if "_tail" in creature:
				for t in creature._tail:
					chain.append(t)
					lengths.append(16.0)
					max_angles.append(deg_to_rad(20))
			var apply_fn := func(solved: Array[Vector2]):
				creature._spine[2] = solved[1]
				if "_tail" in creature:
					for ti in range(creature._tail.size()):
						creature._tail[ti] = solved[2 + ti]
			return { "chain": chain, "lengths": lengths, "max_angles": max_angles, "apply": apply_fn }

		"shoulders":
			var chain: Array[Vector2] = [spine[1], spine[0]]
			var lengths: Array[float] = [28.0]
			var max_angles: Array[float] = [deg_to_rad(30)]
			var apply_fn := func(solved: Array[Vector2]):
				creature._spine[0] = solved[1]
			return { "chain": chain, "lengths": lengths, "max_angles": max_angles, "apply": apply_fn }

		"waist":
			var chain: Array[Vector2] = [spine[1], spine[2]]
			var lengths: Array[float] = [28.0]
			var max_angles: Array[float] = [deg_to_rad(30)]
			var apply_fn := func(solved: Array[Vector2]):
				creature._spine[2] = solved[1]
			return { "chain": chain, "lengths": lengths, "max_angles": max_angles, "apply": apply_fn }

		"elbow_l", "elbow_r":
			var li: int = 0 if point_name == "elbow_l" else 1
			var clav_idx: int = li
			if "_clavicles" in creature and "_legs" in creature:
				var chain: Array[Vector2] = [
					spine[1], spine[0],
					creature._clavicles[clav_idx],
					creature._legs[li][0],
					creature._legs[li][1],
				]
				var lengths: Array[float] = [28.0, 12.0, 0.1, 24.0]
				var max_angles: Array[float] = [deg_to_rad(30), deg_to_rad(45), deg_to_rad(90), deg_to_rad(90)]
				var apply_fn := func(solved: Array[Vector2]):
					creature._spine[0] = solved[1]
					creature._clavicles[clav_idx] = solved[2]
					creature._legs[li][0] = solved[3]
					creature._legs[li][1] = solved[4]
				return { "chain": chain, "lengths": lengths, "max_angles": max_angles, "apply": apply_fn }

		"knee_l", "knee_r":
			var li: int = 2 if point_name == "knee_l" else 3
			var hip_idx: int = li - 2
			if "_hip_bones" in creature and "_legs" in creature:
				var chain: Array[Vector2] = [
					spine[1], spine[2],
					creature._hip_bones[hip_idx],
					creature._legs[li][0],
					creature._legs[li][1],
				]
				var lengths: Array[float] = [28.0, 12.0, 0.1, 24.0]
				var max_angles: Array[float] = [deg_to_rad(30), deg_to_rad(45), deg_to_rad(90), deg_to_rad(90)]
				var apply_fn := func(solved: Array[Vector2]):
					creature._spine[2] = solved[1]
					creature._hip_bones[hip_idx] = solved[2]
					creature._legs[li][0] = solved[3]
					creature._legs[li][1] = solved[4]
				return { "chain": chain, "lengths": lengths, "max_angles": max_angles, "apply": apply_fn }

	return {}
