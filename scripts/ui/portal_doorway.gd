extends Node2D

## Magical stone doorway with wooden double doors on the title screen.
## Players walk in front to open doors; all players present for 5s triggers transition.

signal all_players_entered

const DOORWAY_WIDTH := 130.0
const DOORWAY_HEIGHT := 180.0
const STONE_COLOR := Color(0.4, 0.35, 0.3)
const STONE_DARK := Color(0.3, 0.25, 0.2)
const STONE_LIGHT := Color(0.5, 0.45, 0.38)
const KEYSTONE_COLOR := Color(0.55, 0.5, 0.4)
const VOID_COLOR := Color(0.02, 0.01, 0.05)
const DOOR_COLOR := Color(0.45, 0.3, 0.15)
const DOOR_DARK := Color(0.35, 0.22, 0.1)
const DOOR_PLANK := Color(0.5, 0.35, 0.18)
const HANDLE_COLOR := Color(0.6, 0.55, 0.45)
const ACTIVATION_RANGE := 100.0
const ALL_PRESENT_TIME := 5.0  # Seconds all players must be present before pull-in
const SPIRAL_SPEED := 3.0

var _timer: float = 0.0
var _players_near: int = 0
var _total_players: int = 0
var _activated: bool = false  # At least one player near
var _all_present: bool = false  # All players near
var _all_present_timer: float = 0.0  # How long all players have been present
var _transition_started: bool = false
var _transition_timer: float = 0.0
var _doors_open: bool = false  # Once opened, stays open
var _door_open_amount: float = 0.0  # 0 = closed, 1 = fully open
var _spiral_particles: Array = []
var _fog_particles: Array = []
var _particle_timer: float = 0.0
var _fog_timer: float = 0.0
var _hum_timer: float = 0.0


func _process(delta: float) -> void:
	_timer += delta
	_particle_timer += delta
	_fog_timer += delta

	# Count players near the doorway
	_total_players = PlayerManager.get_active_player_count()
	_players_near = 0
	for node in get_tree().get_nodes_in_group("players"):
		if node is Node2D:
			var dist: float = global_position.distance_to(node.global_position)
			if dist < ACTIVATION_RANGE:
				_players_near += 1

	_activated = _players_near > 0
	_all_present = _players_near >= _total_players and _total_players > 0

	# Doors open when a player stands in front, stay open once opened
	if _activated and not _doors_open:
		_doors_open = true
		AudioManager.play("enemy_hit", -6.0, 0.4)  # Creak sound
		AudioManager.play("boss_roar", -8.0, 0.25)  # Deep ominous drone

	# Repeating ominous hum while doors open
	if _doors_open:
		_hum_timer -= delta
		if _hum_timer <= 0.0:
			_hum_timer = 4.0  # Repeat every 4 seconds
			AudioManager.play("boss_roar", -12.0, 0.2)  # Very deep, quiet drone

	# Animate door opening
	if _doors_open and _door_open_amount < 1.0:
		_door_open_amount = minf(_door_open_amount + delta * 0.8, 1.0)

	# Fog when doors open
	if _doors_open and _fog_timer >= 0.08:
		_fog_timer = 0.0
		_spawn_fog_particle()

	# Vortex particles when doors are open
	if _doors_open and _particle_timer >= 0.04:
		_particle_timer = 0.0
		_spawn_spiral_particle()
		if _all_present:
			_spawn_spiral_particle()  # Double particles when all present
			_spawn_spiral_particle()

	# Track all-present timer
	if _all_present and not _transition_started:
		_all_present_timer += delta

		# Spawn rays that get brighter over time
		if _particle_timer <= 0.01:
			_spawn_ray_particle()

		# After 5 seconds, start pull-in
		if _all_present_timer >= ALL_PRESENT_TIME:
			_transition_started = true
			_transition_timer = 0.0
			for i in range(30):
				_spawn_spiral_particle()
	elif not _all_present and not _transition_started:
		# Player stepped out — rays dissipate, timer resets
		_all_present_timer = maxf(_all_present_timer - delta * 2.0, 0.0)

	# Transition sequence
	if _transition_started:
		_transition_timer += delta
		# More rays during transition
		if _fog_timer >= 0.02:
			_fog_timer = 0.0
			_spawn_ray_particle()
			_spawn_spiral_particle()

		if _transition_timer >= 0.5 and _transition_timer < 2.5:
			_pull_players_in(delta)

		if _transition_timer >= 2.5:
			all_players_entered.emit()

	# Tick particles
	_tick_particles(delta)
	queue_redraw()


func _tick_particles(delta: float) -> void:
	var i: int = _spiral_particles.size() - 1
	while i >= 0:
		_spiral_particles[i]["time"] -= delta
		if _spiral_particles[i]["time"] <= 0.0:
			_spiral_particles.remove_at(i)
		i -= 1

	i = _fog_particles.size() - 1
	while i >= 0:
		_fog_particles[i]["time"] -= delta
		_fog_particles[i]["x"] += _fog_particles[i]["vx"] * delta
		_fog_particles[i]["y"] += _fog_particles[i]["vy"] * delta
		if _fog_particles[i]["time"] <= 0.0:
			_fog_particles.remove_at(i)
		i -= 1


func _pull_players_in(delta: float) -> void:
	var pull_strength: float = (_transition_timer - 0.5) * 2.5
	var center := Vector2(0, -DOORWAY_HEIGHT / 2.0)
	for node in get_tree().get_nodes_in_group("players"):
		if node is CharacterBody2D:
			var to_door: Vector2 = (global_position + center) - node.global_position
			var dist: float = to_door.length()
			if dist > 3.0:
				node.velocity = to_door.normalized() * pull_strength * 250.0
			var shrink: float = clampf(1.0 - (_transition_timer - 0.5) / 2.0, 0.03, 1.0)
			node.scale = Vector2(shrink, shrink)
			node.rotation += pull_strength * 6.0 * delta


func _spawn_spiral_particle() -> void:
	_spiral_particles.append({
		"angle": randf() * TAU,
		"dist": randf_range(8.0, 55.0),
		"speed": randf_range(40.0, 100.0),
		"size": randf_range(2.0, 6.0),
		"brightness": 0.6 + randf() * 0.4,
		"time": randf_range(1.0, 3.0),
		"type": "spiral",
	})


func _spawn_ray_particle() -> void:
	_spiral_particles.append({
		"angle": randf() * TAU,
		"dist": 0.0,
		"speed": randf_range(120.0, 400.0),
		"size": randf_range(1.5, 4.0),
		"brightness": 0.8 + randf() * 0.2,
		"time": randf_range(0.4, 1.0),
		"type": "ray",
	})


func _spawn_fog_particle() -> void:
	var side: float = 1.0 if randf() > 0.5 else -1.0
	_fog_particles.append({
		"x": randf_range(-30.0, 30.0),
		"y": 0.0,
		"vx": side * randf_range(15.0, 40.0),
		"vy": randf_range(-3.0, 1.0),
		"size": randf_range(8.0, 20.0),
		"time": randf_range(2.0, 5.0),
	})


var _fog_overlay: Node2D = null

func _draw() -> void:
	# Everything here renders at z_index -1 (behind players)
	_draw_platform_and_stairs()
	_draw_back_layer()
	_draw_wooden_transom()
	_draw_vortex()
	_draw_doors()
	_draw_front_layer()
	_draw_rays()

	# Fog renders on a separate overlay node in front of everything
	if _fog_overlay:
		_fog_overlay.queue_redraw()


func _ready() -> void:
	z_index = -1  # Behind players
	# Create fog overlay that renders in front of everything
	_fog_overlay = Node2D.new()
	_fog_overlay.z_index = 10  # In front of players
	_fog_overlay.set_script(null)
	add_child(_fog_overlay)
	_fog_overlay.draw.connect(_draw_fog_on_overlay)


func _draw_back_layer() -> void:
	var half_w: float = DOORWAY_WIDTH / 2.0
	draw_rect(Rect2(-half_w, -DOORWAY_HEIGHT, DOORWAY_WIDTH, DOORWAY_HEIGHT), VOID_COLOR)


func _draw_doors() -> void:
	if not _doors_open and _door_open_amount <= 0.0:
		# Closed double doors
		var half_w: float = DOORWAY_WIDTH / 2.0
		var door_h: float = DOORWAY_HEIGHT - 10.0

		# Left door
		_draw_single_door(-half_w, -door_h, half_w, door_h, false)
		# Right door
		_draw_single_door(0, -door_h, half_w, door_h, true)
		return

	if _door_open_amount > 0.0:
		# Doors swinging open (perspective effect: width shrinks as they open)
		var half_w: float = DOORWAY_WIDTH / 2.0
		var door_h: float = DOORWAY_HEIGHT - 10.0
		var open_ratio: float = _door_open_amount
		var visible_width: float = half_w * (1.0 - open_ratio * 0.85)

		if visible_width > 2.0:
			# Left door (swings left)
			var left_x: float = -half_w
			_draw_single_door(left_x, -door_h, visible_width, door_h, false)
			# Right door (swings right)
			var right_x: float = half_w - visible_width
			_draw_single_door(right_x, -door_h, visible_width, door_h, true)


func _draw_single_door(x: float, y: float, w: float, h: float, is_right: bool) -> void:
	# Main door panel
	draw_rect(Rect2(x, y, w, h), DOOR_COLOR)

	# Planks (vertical lines)
	var plank_count := maxi(int(w / 12.0), 1)
	for i in range(plank_count + 1):
		var px: float = x + (w / float(plank_count)) * i
		draw_line(Vector2(px, y), Vector2(px, y + h), DOOR_DARK, 1.0)

	# Horizontal crossbars
	draw_rect(Rect2(x, y + h * 0.25, w, 4), DOOR_DARK)
	draw_rect(Rect2(x, y + h * 0.65, w, 4), DOOR_DARK)

	# Ring handle
	var handle_x: float = x + w * (0.75 if not is_right else 0.25)
	var handle_y: float = y + h * 0.45
	draw_arc(Vector2(handle_x, handle_y), 5.0, 0, TAU, 12, HANDLE_COLOR, 2.0)
	draw_circle(Vector2(handle_x, handle_y - 5.0), 2.0, HANDLE_COLOR)  # Mount point


func _draw_fog_on_overlay() -> void:
	for f in _fog_particles:
		var alpha: float = clampf(f["time"] / 2.0, 0.0, 0.3)
		var size: float = f["size"] + (5.0 - f["time"]) * 3.0
		_fog_overlay.draw_circle(Vector2(f["x"], f["y"]), size, Color(0.6, 0.65, 0.7, alpha))


func _draw_vortex() -> void:
	if not _doors_open:
		return

	var center := Vector2(0, -DOORWAY_HEIGHT / 2.0)
	var vortex_scale: float = 1.25  # 25% larger

	# Base glow (always present when doors open)
	var base_glow: float = 0.08 + 0.04 * sin(_timer * 3.0)
	draw_circle(center, 62.0 * vortex_scale, Color(0.2, 0.3, 0.8, base_glow))
	draw_circle(center, 38.0 * vortex_scale, Color(0.3, 0.5, 1.0, base_glow * 1.5))
	draw_circle(center, 18.0 * vortex_scale, Color(0.5, 0.7, 1.0, base_glow * 2.0))

	# Spiral particles — outer edge slow, inner fast
	for p in _spiral_particles:
		if p["type"] != "spiral":
			continue
		var age_ratio: float = 1.0 - clampf(p["time"] / 2.5, 0.0, 1.0)
		var current_dist: float = p["dist"] * (1.0 - age_ratio * 0.7) * vortex_scale
		# Speed inversely proportional to distance: closer = faster spin
		var dist_ratio: float = clampf(current_dist / (55.0 * vortex_scale), 0.0, 1.0)
		var spin_speed: float = lerpf(SPIRAL_SPEED * 3.0, SPIRAL_SPEED * 0.5, dist_ratio)
		var current_angle: float = p["angle"] + _timer * spin_speed + age_ratio * 3.0
		var pos: Vector2 = center + Vector2(cos(current_angle) * current_dist, sin(current_angle) * current_dist)
		var alpha: float = p["brightness"] * (1.0 - age_ratio)
		var size: float = p["size"] * (1.0 - age_ratio * 0.5)

		# Outer glow
		draw_circle(pos, size * 2.0, Color(0.2, 0.4, 1.0, alpha * 0.2))
		# Core sparkle
		draw_circle(pos, size, Color(0.3, 0.5, 1.0, alpha))
		draw_circle(pos, size * 0.4, Color(0.7, 0.85, 1.0, alpha))

	# Brighter glow when all present (scales with timer)
	if _all_present_timer > 0.0:
		var intensity: float = clampf(_all_present_timer / ALL_PRESENT_TIME, 0.0, 1.0)
		var pulse: float = 1.0 + 0.15 * sin(_timer * 5.0)
		var glow_size: float = lerpf(40.0, 80.0, intensity) * pulse
		draw_circle(center, glow_size, Color(0.4, 0.6, 1.0, intensity * 0.3))
		draw_circle(center, glow_size * 0.6, Color(0.5, 0.7, 1.0, intensity * 0.4))
		draw_circle(center, glow_size * 0.3, Color(0.7, 0.9, 1.0, intensity * 0.6))


func _draw_rays() -> void:
	if _all_present_timer <= 0.0 and not _transition_started:
		return

	var center := Vector2(0, -DOORWAY_HEIGHT / 2.0)
	var intensity: float = clampf(_all_present_timer / ALL_PRESENT_TIME, 0.0, 1.0)
	if _transition_started:
		intensity = 1.0

	for p in _spiral_particles:
		if p["type"] != "ray":
			continue
		var age_ratio: float = 1.0 - clampf(p["time"] / 0.8, 0.0, 1.0)
		var current_dist: float = p["speed"] * age_ratio * 2.0
		var pos: Vector2 = center + Vector2(cos(p["angle"]) * current_dist, sin(p["angle"]) * current_dist)
		var alpha: float = p["brightness"] * (1.0 - age_ratio) * intensity * 0.7
		var size: float = p["size"] * (1.0 + intensity)

		# Ray with trailing glow
		var trail_pos: Vector2 = center + Vector2(cos(p["angle"]) * current_dist * 0.7, sin(p["angle"]) * current_dist * 0.7)
		draw_line(trail_pos, pos, Color(0.6, 0.8, 1.0, alpha * 0.5), size * 0.8)
		draw_circle(pos, size, Color(0.7, 0.85, 1.0, alpha))


func _draw_front_layer() -> void:
	var half_w: float = DOORWAY_WIDTH / 2.0
	var stone_w: float = 20.0

	# Pillars — matching pattern both sides
	for i in range(9):
		var y: float = -DOORWAY_HEIGHT + i * 20.0
		var col: Color = STONE_COLOR if i % 2 == 0 else STONE_DARK
		# Left pillar
		draw_rect(Rect2(-half_w - stone_w, y, stone_w, 20.0), col)
		draw_line(Vector2(-half_w - stone_w, y), Vector2(-half_w, y), STONE_LIGHT * Color(1, 1, 1, 0.3), 1.0)
		# Right pillar — same pattern
		draw_rect(Rect2(half_w, y, stone_w, 20.0), col)
		draw_line(Vector2(half_w, y), Vector2(half_w + stone_w, y), STONE_LIGHT * Color(1, 1, 1, 0.3), 1.0)

	# Archway — leave gap at top center for keystone
	var arch_segments := 16
	var prev_outer := Vector2.ZERO
	var prev_inner := Vector2.ZERO
	var keystone_start := arch_segments / 2 - 1
	var keystone_end := arch_segments / 2 + 1
	for i in range(arch_segments + 1):
		var t: float = float(i) / float(arch_segments)
		var angle: float = PI + t * PI
		var inner_pt := Vector2(cos(angle) * half_w, sin(angle) * half_w + (-DOORWAY_HEIGHT))
		var outer_pt := Vector2(cos(angle) * (half_w + stone_w), sin(angle) * (half_w + stone_w) + (-DOORWAY_HEIGHT))
		if i > 0 and not (i > keystone_start and i <= keystone_end):
			var col: Color = STONE_COLOR if i % 2 == 0 else STONE_DARK
			draw_polygon(
				PackedVector2Array([prev_inner, prev_outer, outer_pt, inner_pt]),
				PackedColorArray([col, col, col, col])
			)
		prev_outer = outer_pt
		prev_inner = inner_pt

	# Large trapezoidal keystone centered at arch peak
	var ks_top_w: float = 14.0  # Half-width at top (narrower)
	var ks_bot_w: float = 22.0  # Half-width at bottom (wider)
	var ks_h: float = stone_w + 8.0  # Tall enough to span the arch thickness
	var ks_cy: float = -DOORWAY_HEIGHT - half_w  # Center of the arch peak
	var ks_top: float = ks_cy - ks_h / 2.0
	var ks_bot: float = ks_cy + ks_h / 2.0
	draw_polygon(
		PackedVector2Array([
			Vector2(-ks_top_w, ks_top),
			Vector2(ks_top_w, ks_top),
			Vector2(ks_bot_w, ks_bot),
			Vector2(-ks_bot_w, ks_bot),
		]),
		PackedColorArray([KEYSTONE_COLOR, KEYSTONE_COLOR, KEYSTONE_COLOR, KEYSTONE_COLOR])
	)
	# Keystone border lines
	draw_line(Vector2(-ks_top_w, ks_top), Vector2(ks_top_w, ks_top), STONE_LIGHT, 1.5)
	draw_line(Vector2(-ks_top_w, ks_top), Vector2(-ks_bot_w, ks_bot), STONE_LIGHT * Color(1, 1, 1, 0.5), 1.0)
	draw_line(Vector2(ks_top_w, ks_top), Vector2(ks_bot_w, ks_bot), STONE_LIGHT * Color(1, 1, 1, 0.5), 1.0)
	# Keystone symbol
	draw_circle(Vector2(0, ks_cy), 4.0, STONE_LIGHT * Color(1, 1, 1, 0.5))

	# Base stones
	draw_rect(Rect2(-half_w - stone_w - 8, -6, stone_w + 8, 10), STONE_DARK)
	draw_rect(Rect2(half_w, -6, stone_w + 8, 10), STONE_DARK)


func _draw_wooden_transom() -> void:
	## Wooden slats and beam fill the entire archway, drawn BEHIND the stone arch
	var half_w: float = DOORWAY_WIDTH / 2.0
	var door_top: float = -DOORWAY_HEIGHT + 10.0  # Top of the door panels
	var arch_peak: float = -DOORWAY_HEIGHT - half_w - 10.0  # Above arch curve peak

	# Slats fill from arch peak down to just above doors
	var slat_region_top: float = arch_peak
	var slat_region_bottom: float = door_top

	# Wooden background panel — extends into the arch curve (arch stone covers edges)
	draw_rect(Rect2(-half_w - 5, slat_region_top, DOORWAY_WIDTH + 10, slat_region_bottom - slat_region_top), DOOR_COLOR * Color(0.85, 0.85, 0.85))

	# Vertical slats
	var slat_count := 12
	for i in range(slat_count + 1):
		var sx: float = -half_w + (DOORWAY_WIDTH / float(slat_count)) * i
		draw_line(Vector2(sx, slat_region_top), Vector2(sx, slat_region_bottom), DOOR_DARK, 1.0)

	# Horizontal beam just above the doors
	var beam_h: float = 7.0
	draw_rect(Rect2(-half_w, door_top - beam_h, DOORWAY_WIDTH, beam_h), DOOR_DARK)
	draw_line(Vector2(-half_w, door_top - beam_h), Vector2(half_w, door_top - beam_h), DOOR_PLANK, 1.0)
	draw_line(Vector2(-half_w, door_top), Vector2(half_w, door_top), DOOR_DARK * Color(0.7, 0.7, 0.7), 1.0)

	# Mysterious muffin symbol centered in the slat area
	var sym_cx: float = 0.0
	var sym_cy: float = (slat_region_top + slat_region_bottom) / 2.0 - 5.0
	var sym_color := Color(0.7, 0.6, 0.35, 0.85)
	var sym_glow := Color(0.8, 0.7, 0.4, 0.3)

	# Subtle glow behind
	draw_circle(Vector2(sym_cx, sym_cy), 16.0, Color(0.6, 0.5, 0.3, 0.12))

	# Muffin top (puffy dome — 3 overlapping circles)
	draw_circle(Vector2(sym_cx, sym_cy - 4), 9.0, sym_color)
	draw_circle(Vector2(sym_cx - 6, sym_cy - 1), 6.0, sym_color)
	draw_circle(Vector2(sym_cx + 6, sym_cy - 1), 6.0, sym_color)
	draw_circle(Vector2(sym_cx, sym_cy - 6), 4.0, sym_glow)  # Highlight

	# Muffin wrapper body (trapezoid)
	draw_polygon(
		PackedVector2Array([
			Vector2(sym_cx - 11, sym_cy),
			Vector2(sym_cx + 11, sym_cy),
			Vector2(sym_cx + 8, sym_cy + 8),
			Vector2(sym_cx - 8, sym_cy + 8),
		]),
		PackedColorArray([sym_color, sym_color, sym_color, sym_color])
	)
	# Wrapper lines
	draw_line(Vector2(sym_cx - 8, sym_cy + 3), Vector2(sym_cx + 8, sym_cy + 3), DOOR_DARK, 1.0)
	draw_line(Vector2(sym_cx - 8, sym_cy + 6), Vector2(sym_cx + 8, sym_cy + 6), DOOR_DARK, 1.0)


func _draw_platform_and_stairs() -> void:
	## Platform the doorway sits on (50% wider) and 3 descending stairs
	var half_w: float = DOORWAY_WIDTH / 2.0
	var plat_w: float = DOORWAY_WIDTH * 1.5
	var plat_half: float = plat_w / 2.0
	var plat_h: float = 12.0
	var stair_h: float = 10.0
	var stair_grow: float = 16.0  # Each stair gets wider

	# Main platform
	draw_rect(Rect2(-plat_half, 0, plat_w, plat_h), STONE_COLOR)
	draw_line(Vector2(-plat_half, 0), Vector2(plat_half, 0), STONE_LIGHT, 1.5)

	# 3 descending stairs
	for i in range(3):
		var sw: float = plat_w + stair_grow * (i + 1)
		var sh: float = plat_h + stair_h * (i + 1)
		var sx: float = -sw / 2.0
		var col: Color = STONE_DARK if i % 2 == 0 else STONE_COLOR
		draw_rect(Rect2(sx, sh - stair_h, sw, stair_h), col)
		draw_line(Vector2(sx, sh - stair_h), Vector2(sx + sw, sh - stair_h), STONE_LIGHT * Color(1, 1, 1, 0.4), 1.0)
