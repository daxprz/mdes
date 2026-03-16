extends Node2D

## Red rift portal with a multi-segmented tentacle that emerges on class change.
## The rift persists for 15 seconds. The tentacle wiggles confused for 5 seconds,
## then begins hunting nearby players. If it grabs one, it smashes them around.

const RIFT_DURATION := 15.0
const HUNT_DELAY := 5.0
const SEGMENT_COUNT := 14
const SEGMENT_LENGTH := 9.0  # ~126px total, close to balloon string
const GRAB_RANGE := 200.0
const STRETCH_RANGE := 300.0  # 1.5x normal reach for grab lunges
const LUNGE_SPEED := 400.0
const WIGGLE_SPEED := 3.0
const SMASH_DAMAGE := 8
const SMASH_INTERVAL := 0.4
const SUCKER_RADIUS := 3.0
const TIP_CURL_SEGMENTS := 3

var _segments: Array[Vector2] = []  # positions in local space
var _prev_segments: Array[Vector2] = []  # previous frame (verlet)
var _timer: float = 0.0
var _phase: int = 0  # 0=wiggle, 1=hunt, 2=grabbed
var _target_node: Node2D = null
var _grabbed_player: Node2D = null
var _grabbed_player_index: int = -1
var _smash_timer: float = 0.0
var _smash_direction: int = 1
var _smash_count: int = 0
var _lunge_cooldown: float = 0.0
var _rift_scale: float = 0.0  # Grows from 0 to 1 on spawn
var _owner_player_index: int = -1


func setup(owner_index: int) -> void:
	_owner_player_index = owner_index


func _ready() -> void:
	z_index = 5
	# Initialize segments hanging downward from rift center
	_segments.resize(SEGMENT_COUNT)
	_prev_segments.resize(SEGMENT_COUNT)
	for i in range(SEGMENT_COUNT):
		var pos := Vector2(0, i * SEGMENT_LENGTH)
		_segments[i] = pos
		_prev_segments[i] = pos


func _process(delta: float) -> void:
	_timer += delta

	# Rift scale-in
	_rift_scale = minf(_timer / 0.3, 1.0)

	# Phase transitions
	if _timer >= RIFT_DURATION:
		_release_grab()
		queue_free()
		return

	if _phase == 0 and _timer >= HUNT_DELAY:
		_phase = 1

	# Lunge cooldown
	if _lunge_cooldown > 0.0:
		_lunge_cooldown -= delta

	# Physics
	match _phase:
		0:
			_wiggle(delta)
		1:
			_hunt(delta)
		2:
			_smash(delta)

	_apply_constraints()
	queue_redraw()


func _wiggle(delta: float) -> void:
	## Confused wiggling - tip wanders randomly
	for i in range(1, SEGMENT_COUNT):
		var wiggle_offset := Vector2(
			sin(_timer * WIGGLE_SPEED * 2.0 + i * 0.7) * 15.0,
			cos(_timer * WIGGLE_SPEED * 1.5 + i * 0.9) * 8.0
		)
		# Verlet integration with wiggle force
		var vel: Vector2 = _segments[i] - _prev_segments[i]
		_prev_segments[i] = _segments[i]
		_segments[i] += vel * 0.95 + wiggle_offset * delta + Vector2(0, 12.0 * delta)  # gravity


func _hunt(delta: float) -> void:
	## Seek nearest non-owner player
	var tip: Vector2 = _segments[SEGMENT_COUNT - 1]
	var tip_global: Vector2 = global_position + tip

	# Find closest player
	var best_dist: float = GRAB_RANGE
	var best_node: Node2D = null
	var best_pi: int = -1

	for node in get_tree().get_nodes_in_group("players"):
		if not node is CharacterBody2D:
			continue
		var pi: int = node.get("player_index")
		if pi == _owner_player_index:
			continue
		var dist: float = tip_global.distance_to(node.global_position)
		var max_range: float = GRAB_RANGE
		# Lunge: allow stretch to 1.5x
		if _lunge_cooldown <= 0.0:
			max_range = STRETCH_RANGE
		if dist < best_dist:
			best_dist = dist
			best_node = node
			best_pi = pi

	if best_node:
		# Move tip toward target
		var target_pos: Vector2 = best_node.global_position - global_position
		var dir: Vector2 = (target_pos - tip).normalized()
		var speed: float = LUNGE_SPEED if _lunge_cooldown <= 0.0 else 150.0

		# Verlet: push tip toward target
		_prev_segments[SEGMENT_COUNT - 1] = _segments[SEGMENT_COUNT - 1]
		_segments[SEGMENT_COUNT - 1] += dir * speed * delta

		# Check grab (tip close enough)
		if best_dist < 25.0:
			_grabbed_player = best_node
			_grabbed_player_index = best_pi
			_phase = 2
			_smash_timer = 0.0
			_smash_count = 0
			_smash_direction = 1
			_lunge_cooldown = 3.0
	else:
		# No target - wiggle while hunting
		_wiggle(delta)
		# Periodic lunge reset
		if _lunge_cooldown <= 0.0:
			_lunge_cooldown = 2.0 + randf() * 2.0


func _smash(delta: float) -> void:
	## Grabbed a player - smash them back and forth
	if not is_instance_valid(_grabbed_player):
		_release_grab()
		return

	# Keep tip at player
	var player_local: Vector2 = _grabbed_player.global_position - global_position
	_segments[SEGMENT_COUNT - 1] = player_local

	_smash_timer += delta
	if _smash_timer >= SMASH_INTERVAL:
		_smash_timer = 0.0
		_smash_count += 1

		# Damage
		PlayerManager.damage_player(_grabbed_player_index, SMASH_DAMAGE)

		# Smash velocity - fling player side to side
		_smash_direction *= -1
		_grabbed_player.velocity = Vector2(_smash_direction * 350.0, -200.0)

		# Smoke poof at player
		_spawn_smash_smoke(_grabbed_player.global_position)

		# Release after 4 smashes
		if _smash_count >= 4:
			# Final fling
			_grabbed_player.velocity = Vector2(_smash_direction * 500.0, -300.0)
			_release_grab()

	# Gravity on other segments
	for i in range(1, SEGMENT_COUNT - 1):
		var vel: Vector2 = _segments[i] - _prev_segments[i]
		_prev_segments[i] = _segments[i]
		_segments[i] += vel * 0.9 + Vector2(0, 10.0 * delta)


func _release_grab() -> void:
	_grabbed_player = null
	_grabbed_player_index = -1
	if _phase == 2:
		_phase = 1
		_lunge_cooldown = 3.0


func _apply_constraints() -> void:
	## Verlet distance constraints - anchor first segment to rift center
	_segments[0] = Vector2.ZERO

	for _iter in range(3):
		# First segment stays at origin
		_segments[0] = Vector2.ZERO
		for i in range(1, SEGMENT_COUNT):
			var diff: Vector2 = _segments[i] - _segments[i - 1]
			var dist: float = diff.length()
			if dist < 0.01:
				diff = Vector2(0, 1)
				dist = 1.0
			var max_len: float = SEGMENT_LENGTH
			# Allow stretch during lunge
			if _phase == 1 and i >= SEGMENT_COUNT - 3 and _lunge_cooldown <= 0.0:
				max_len = SEGMENT_LENGTH * 1.5
			if dist > max_len:
				var correction: Vector2 = diff.normalized() * (dist - max_len) * 0.5
				_segments[i] -= correction
				if i > 0:
					_segments[i - 1] += correction


func _draw() -> void:
	# Draw rift portal
	_draw_rift()
	# Draw tentacle
	_draw_tentacle()


func _draw_rift() -> void:
	## Pulsing red circular rift
	var pulse: float = 1.0 + 0.15 * sin(_timer * 6.0)
	var rift_size: float = 22.0 * _rift_scale * pulse

	# Outer glow
	draw_circle(Vector2.ZERO, rift_size + 6, Color(0.9, 0.1, 0.1, 0.2 * _rift_scale))
	draw_circle(Vector2.ZERO, rift_size + 3, Color(0.9, 0.1, 0.1, 0.3 * _rift_scale))
	# Main rift circle
	draw_circle(Vector2.ZERO, rift_size, Color(0.8, 0.05, 0.05, 0.7 * _rift_scale))
	# Inner bright core
	draw_circle(Vector2.ZERO, rift_size * 0.5, Color(1.0, 0.3, 0.2, 0.9 * _rift_scale))
	# Center
	draw_circle(Vector2.ZERO, rift_size * 0.2, Color(1.0, 0.6, 0.4, _rift_scale))


func _draw_tentacle() -> void:
	if SEGMENT_COUNT < 2:
		return

	var outer_color := Color(0.45, 0.1, 0.7)  # Purple outer
	var inner_color := Color(0.7, 0.4, 0.9)  # Light-purple inner
	var sucker_color := Color(0.6, 0.3, 0.8, 0.8)

	# Draw each segment
	for i in range(SEGMENT_COUNT - 1):
		var a: Vector2 = _segments[i]
		var b: Vector2 = _segments[i + 1]

		# Segment thickness tapers from base to tip
		var t: float = float(i) / float(SEGMENT_COUNT - 1)
		var thickness: float = lerpf(7.0, 3.0, t)

		# Outer (purple)
		draw_line(a, b, outer_color, thickness, true)
		# Inner (light-purple), thinner
		draw_line(a, b, inner_color, thickness * 0.5, true)

		# Suckers at segment joints
		if i > 0:
			var mid: Vector2 = (a + b) * 0.5
			var dir: Vector2 = (b - a).normalized()
			var perp: Vector2 = Vector2(-dir.y, dir.x)
			# Alternate sides
			var side: float = 1.0 if i % 2 == 0 else -1.0
			var sucker_pos: Vector2 = a + perp * side * (thickness * 0.5 + SUCKER_RADIUS * 0.5)
			draw_circle(sucker_pos, SUCKER_RADIUS * (1.0 - t * 0.3), sucker_color)

	# Menacing curl at tip
	var tip: Vector2 = _segments[SEGMENT_COUNT - 1]
	var pre_tip: Vector2 = _segments[SEGMENT_COUNT - 2]
	var tip_dir: Vector2 = (tip - pre_tip).normalized()
	var curl_perp: Vector2 = Vector2(-tip_dir.y, tip_dir.x)

	# Draw curled tip - a small hook
	var curl_steps := 8
	var prev_pt: Vector2 = tip
	for step in range(1, curl_steps + 1):
		var angle: float = step * PI * 0.25
		var curl_radius: float = 5.0 - step * 0.4
		var curl_pt: Vector2 = tip + tip_dir * cos(angle) * curl_radius + curl_perp * sin(angle) * curl_radius
		var curl_t: float = float(step) / float(curl_steps)
		draw_line(prev_pt, curl_pt, outer_color, lerpf(3.0, 1.0, curl_t), true)
		prev_pt = curl_pt

	# Grabbed player indicator - tentacle tip glows red
	if _phase == 2:
		draw_circle(tip, 6.0, Color(1.0, 0.2, 0.1, 0.5 + 0.3 * sin(_timer * 10.0)))


func _spawn_smash_smoke(pos: Vector2) -> void:
	## Burst of smoke particles at smash point
	for i in range(6):
		var smoke := ColorRect.new()
		smoke.color = Color(0.7, 0.7, 0.7, 0.6)
		smoke.size = Vector2(8, 8)
		smoke.z_index = 7
		smoke.position = pos - Vector2(4, 4)
		get_parent().add_child(smoke)

		var angle: float = randf() * TAU
		var dist: float = 20.0 + randf() * 30.0
		var target: Vector2 = pos + Vector2(cos(angle), sin(angle)) * dist - Vector2(4, 4)

		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(smoke, "position", target, 0.4)
		tween.tween_property(smoke, "modulate:a", 0.0, 0.5)
		tween.tween_property(smoke, "scale", Vector2(2.0, 2.0), 0.4)
		tween.set_parallel(false)
		tween.tween_callback(smoke.queue_free)
