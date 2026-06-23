extends Node2D
## MDES space-themed title screen — fully procedural via _draw().
## Aesthetic nod to Risk of Rain / Risk of Rain Returns: dark starfield, a big
## moody planet with an atmospheric rim, parallax drift, falling meteor streaks,
## a chunky glowing logo and a navigable menu.

const W := 1920.0
const H := 1080.0

# Menu layout (shared by drawing + mouse hit-testing).
const MENU_Y0 := 660.0
const MENU_GAP := 70.0
const MENU_HALF_W := 340.0

# --- Palette ---
const BG_TOP := Color(0.02, 0.03, 0.07)
const BG_BOT := Color(0.05, 0.08, 0.13)
const PLANET_DARK := Color(0.14, 0.10, 0.09)
const PLANET_LIT := Color(0.72, 0.52, 0.36)
const ATMO := Color(0.40, 0.72, 0.95)
const LOGO_COL := Color(0.93, 0.96, 1.0)
const LOGO_GLOW := Color(0.35, 0.70, 0.95)
const SEL_COL := Color(1.0, 0.72, 0.38)
const DIM_COL := Color(0.55, 0.62, 0.74)

var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _stars: Array = []          # {pos, r, base, twspeed, twphase, plx}
var _nebulae: Array = []        # {pos, r, col}
var _meteors: Array = []        # {pos, vel, life, max}
var _meteor_timer := 0.0

var _menu := ["Single Player", "Multiplayer", "Settings", "Quit"]
var _sel := 0
var _last_sel := 0

var _sfx_move: AudioStreamPlayer
var _sfx_select: AudioStreamPlayer

# Light direction for planet shading (from upper-left).
var _light := Vector2(-0.55, -0.45).normalized()
var _planet_center := Vector2(1420, 720)
var _planet_r := 300.0


func _ready() -> void:
	_rng.seed = 7731  # fixed seed => stable star/nebula layout
	_generate_stars()
	_generate_nebulae()
	_setup_audio()
	_last_sel = _sel  # prevent a blip on first frame
	set_process(true)


func _setup_audio() -> void:
	# Synthesize tiny UI blips in code (no GDSiON / asset-file dependency).
	_sfx_move = AudioStreamPlayer.new()
	_sfx_move.stream = _make_blip(620.0, 0.05, 0.30)
	add_child(_sfx_move)
	_sfx_select = AudioStreamPlayer.new()
	_sfx_select.stream = _make_blip(960.0, 0.13, 0.38)
	add_child(_sfx_select)


func _generate_stars() -> void:
	_stars.clear()
	# Three parallax layers, denser/fainter in the back.
	var layers := [
		{"count": 220, "rmin": 0.6, "rmax": 1.3, "plx": 4.0,  "bmax": 0.55},
		{"count": 120, "rmin": 1.0, "rmax": 2.0, "plx": 9.0,  "bmax": 0.8},
		{"count": 55,  "rmin": 1.6, "rmax": 2.8, "plx": 16.0, "bmax": 1.0},
	]
	for L in layers:
		for _i in int(L["count"]):
			var tint := 1.0
			var roll := _rng.randf()
			var col := Color(1, 1, 1)
			if roll < 0.12:
				col = Color(0.7, 0.82, 1.0)   # blue star
			elif roll < 0.20:
				col = Color(1.0, 0.85, 0.7)   # warm star
			_stars.append({
				"pos": Vector2(_rng.randf() * W, _rng.randf() * H),
				"r": _rng.randf_range(L["rmin"], L["rmax"]),
				"base": _rng.randf_range(0.25, L["bmax"]) * tint,
				"twspeed": _rng.randf_range(1.0, 3.5),
				"twphase": _rng.randf_range(0.0, TAU),
				"plx": L["plx"],
				"col": col,
			})


func _generate_nebulae() -> void:
	_nebulae = [
		{"pos": Vector2(380, 300), "r": 520.0, "col": Color(0.28, 0.12, 0.42, 0.05)},
		{"pos": Vector2(1250, 240), "r": 460.0, "col": Color(0.10, 0.30, 0.40, 0.05)},
		{"pos": Vector2(760, 820), "r": 600.0, "col": Color(0.20, 0.10, 0.30, 0.045)},
	]


func _process(delta: float) -> void:
	_t += delta
	_update_meteors(delta)
	_handle_input()
	# Play a blip whenever the highlighted option changes, regardless of whether
	# it changed via keyboard, mouse hover, or a number hotkey.
	if _sel != _last_sel:
		_last_sel = _sel
		if _sfx_move:
			_sfx_move.pitch_scale = 0.92 + _sel * 0.06
			_sfx_move.play()
	queue_redraw()


func _update_meteors(delta: float) -> void:
	_meteor_timer -= delta
	if _meteor_timer <= 0.0:
		_meteor_timer = _rng.randf_range(0.9, 2.4)
		var sx := _rng.randf() * W
		var ang := deg_to_rad(_rng.randf_range(108.0, 122.0))  # steep, down-leftish
		var spd := _rng.randf_range(900.0, 1500.0)
		_meteors.append({
			"pos": Vector2(sx, -40.0),
			"vel": Vector2(cos(ang), sin(ang)) * spd,
			"life": 0.0,
			"max": _rng.randf_range(0.9, 1.6),
		})
	for m in _meteors:
		m["pos"] += m["vel"] * delta
		m["life"] += delta
	_meteors = _meteors.filter(func(m): return m["life"] < m["max"] and m["pos"].y < H + 60.0)


func _move(delta_sel: int) -> void:
	_sel = (_sel + delta_sel + _menu.size()) % _menu.size()


func _handle_input() -> void:
	# Action-based: arrow keys + controller d-pad/stick.
	if Input.is_action_just_pressed("ui_down"):
		_move(1)
	elif Input.is_action_just_pressed("ui_up"):
		_move(-1)
	elif Input.is_action_just_pressed("ui_accept"):
		_activate(_menu[_sel])


# Raw-key handling for keyboard niceties not bound to ui_* actions:
# WASD navigation, Space/Enter select, 1-4 quick-launch, Esc to quit.
func _unhandled_input(event: InputEvent) -> void:
	# Mouse hover highlights an option (only on actual movement, so a resting
	# mouse never overrides the keyboard selection).
	if event is InputEventMouseMotion:
		var idx := _mouse_menu_index()
		if idx >= 0:
			_sel = idx
		return
	# Left click activates the option under the cursor.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hit := _mouse_menu_index()
		if hit >= 0:
			_sel = hit
			_activate(_menu[hit])
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_W, KEY_K:
			_move(-1)
		KEY_S, KEY_J:
			_move(1)
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			_activate(_menu[_sel])
		KEY_ESCAPE:
			_activate("Quit")
		KEY_1:
			_sel = 0; _activate(_menu[0])
		KEY_2:
			_sel = 1; _activate(_menu[1])
		KEY_3:
			_sel = 2; _activate(_menu[2])
		KEY_4:
			_sel = 3; _activate(_menu[3])


# Which menu row the mouse is over, or -1. Uses the shared MENU_* layout.
func _mouse_menu_index() -> int:
	var m := get_global_mouse_position()
	if absf(m.x - W * 0.5) > MENU_HALF_W:
		return -1
	for i in _menu.size():
		var cy := MENU_Y0 + i * MENU_GAP
		if m.y > cy - 46.0 and m.y < cy + 18.0:
			return i
	return -1


func _activate(item: String) -> void:
	if _sfx_select:
		_sfx_select.play()
	match item:
		"Single Player", "Multiplayer":
			get_tree().change_scene_to_file("res://scenes/mdes/mdes_main.tscn")
		"Settings":
			pass  # placeholder — settings screen TBD
		"Quit":
			get_tree().quit()


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	_draw_background()
	_draw_nebulae()
	_draw_stars()
	_draw_planet_ring(true)   # back half
	_draw_planet()
	_draw_planet_ring(false)  # front half
	_draw_moon(Vector2(560, 250), 46.0)
	_draw_meteors()
	_draw_terrain()
	_draw_fog()
	_draw_character(715.0)
	_draw_vignette()
	_draw_logo()
	_draw_menu()
	_draw_footer()


func _draw_background() -> void:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(W, 0), Vector2(W, H), Vector2(0, H)])
	var cols := PackedColorArray([BG_TOP, BG_TOP, BG_BOT, BG_BOT])
	draw_polygon(pts, cols)


func _draw_nebulae() -> void:
	for n in _nebulae:
		var drift := Vector2(sin(_t * 0.05) * 14.0, cos(_t * 0.04) * 8.0)
		# Soft blob = a few stacked translucent circles.
		for k in 4:
			var rr: float = n["r"] * (1.0 - k * 0.18)
			var c: Color = n["col"]
			draw_circle(n["pos"] + drift, rr, Color(c.r, c.g, c.b, c.a))


func _draw_stars() -> void:
	for s in _stars:
		var x: float = fposmod(s["pos"].x + _t * s["plx"], W)
		var tw: float = 0.6 + 0.4 * sin(_t * s["twspeed"] + s["twphase"])
		var b: float = clampf(s["base"] * tw, 0.0, 1.0)
		var col: Color = s["col"]
		draw_circle(Vector2(x, s["pos"].y), s["r"], Color(col.r, col.g, col.b, b))
		# brighter foreground stars get a faint cross-glow
		if s["plx"] >= 16.0 and b > 0.7:
			var g := Color(col.r, col.g, col.b, (b - 0.7) * 0.5)
			draw_line(Vector2(x - s["r"] * 3.0, s["pos"].y), Vector2(x + s["r"] * 3.0, s["pos"].y), g, 1.0)
			draw_line(Vector2(x, s["pos"].y - s["r"] * 3.0), Vector2(x, s["pos"].y + s["r"] * 3.0), g, 1.0)


func _draw_planet() -> void:
	var c := _planet_center
	var R := _planet_r
	# Atmospheric glow halo behind the disk.
	for i in 6:
		var rr := R + 8.0 + i * 9.0
		draw_circle(c, rr, Color(ATMO.r, ATMO.g, ATMO.b, 0.05 * (1.0 - i / 6.0)))
	# Sphere shading: stacked circles shifting toward the light, dark->lit.
	var steps := 22
	for i in steps:
		var f := float(i) / float(steps - 1)
		var rr := R * (1.0 - f * 0.92)
		var off := -_light * (R * 0.55 * f)
		var col := PLANET_DARK.lerp(PLANET_LIT, pow(f, 1.3))
		draw_circle(c + off, rr, col)
	# Bright atmospheric rim on the lit edge.
	var rim_a := atan2(_light.y, _light.x)
	var rim := _arc_points(c, R - 1.0, rim_a - 1.5, rim_a + 1.5, 40)
	draw_polyline(rim, Color(ATMO.r, ATMO.g, ATMO.b, 0.85), 3.0, true)


func _draw_planet_ring(back_half: bool) -> void:
	var c := _planet_center
	var rx := _planet_r * 1.85
	var ry := _planet_r * 0.42
	# back half = top of ellipse (behind planet), front half = bottom (in front).
	var a0 := PI if back_half else 0.0
	var a1 := TAU if back_half else PI
	var pts := PackedVector2Array()
	var steps := 80
	for i in steps + 1:
		var a: float = lerp(a0, a1, float(i) / steps)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	var col := Color(0.75, 0.66, 0.55, 0.32 if back_half else 0.5)
	draw_polyline(pts, col, 6.0, true)


func _draw_moon(pos: Vector2, r: float) -> void:
	for i in 10:
		var f := float(i) / 9.0
		var rr := r * (1.0 - f * 0.9)
		var off := -_light * (r * 0.5 * f)
		draw_circle(pos + off, rr, Color(0.22, 0.24, 0.3).lerp(Color(0.78, 0.82, 0.9), f))
	# couple of craters
	draw_circle(pos + Vector2(-r * 0.3, -r * 0.1), r * 0.16, Color(0.4, 0.43, 0.5, 0.5))
	draw_circle(pos + Vector2(r * 0.15, r * 0.25), r * 0.11, Color(0.4, 0.43, 0.5, 0.5))


func _draw_meteors() -> void:
	for m in _meteors:
		var life: float = m["life"]
		var maxl: float = m["max"]
		var fade := 1.0 - life / maxl
		var dir: Vector2 = m["vel"].normalized()
		var head: Vector2 = m["pos"]
		var tail: Vector2 = head - dir * 130.0
		# tail (dim) -> head (bright)
		draw_line(tail, head, Color(0.6, 0.8, 1.0, 0.0), 1.0)
		draw_line((tail + head) * 0.5, head, Color(0.7, 0.85, 1.0, 0.45 * fade), 2.0)
		draw_line(head - dir * 22.0, head, Color(1.0, 1.0, 1.0, 0.9 * fade), 3.0)
		draw_circle(head, 2.5, Color(1, 1, 1, fade))


func _draw_logo() -> void:
	var font := ThemeDB.fallback_font
	var cx := W * 0.5
	var bob := sin(_t * 0.8) * 4.0
	var y := 250.0 + bob
	var size := 200
	var text := "M.D.E.S."
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := cx - tw * 0.5
	# Glow: stacked offset copies.
	var pulse := 0.5 + 0.5 * sin(_t * 1.6)
	for ring in range(10, 0, -1):
		var rad := ring * 1.6
		var a := (0.05 + 0.05 * pulse) * (1.0 - ring / 11.0)
		for step in 8:
			var ang := step * TAU / 8.0
			var o := Vector2(cos(ang), sin(ang)) * rad
			draw_string(font, Vector2(x, y) + o, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
				Color(LOGO_GLOW.r, LOGO_GLOW.g, LOGO_GLOW.b, a))
	# Faux-bold main text (a few tight offsets) + crisp top layer.
	for o in [Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2), Vector2(0, -2)]:
		draw_string(font, Vector2(x, y) + o, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, LOGO_COL)
	draw_string(font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, LOGO_COL)
	# Glowing underline rule beneath the logo.
	var uy := y + 18.0
	var uw := tw * 0.46
	draw_line(Vector2(cx - uw, uy), Vector2(cx + uw, uy), Color(LOGO_GLOW.r, LOGO_GLOW.g, LOGO_GLOW.b, 0.55), 2.0)
	draw_line(Vector2(cx - uw, uy), Vector2(cx + uw, uy), Color(LOGO_COL.r, LOGO_COL.g, LOGO_COL.b, 0.25 + 0.15 * pulse), 1.0)
	# Subtitle, spaced caps.
	var sub := "M A I N T A I N E D   D O O M E D   E N V I R O N M E N T  ·  S T R A N D E D"
	_text_centered(font, cx, y + 56.0, sub, 22, Color(0.62, 0.78, 0.92, 0.85))


func _draw_menu() -> void:
	var font := ThemeDB.fallback_font
	var cx := W * 0.5
	# Subtle backing panel for legibility over the busy starfield.
	var ptop := MENU_Y0 - 56.0
	var pbot := MENU_Y0 + (_menu.size() - 1) * MENU_GAP + 28.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx - MENU_HALF_W, ptop), Vector2(cx + MENU_HALF_W, ptop),
		Vector2(cx + MENU_HALF_W, pbot), Vector2(cx - MENU_HALF_W, pbot)]),
		Color(0.02, 0.03, 0.06, 0.32))
	draw_line(Vector2(cx - MENU_HALF_W, ptop), Vector2(cx + MENU_HALF_W, ptop), Color(ATMO.r, ATMO.g, ATMO.b, 0.18), 1.0)
	draw_line(Vector2(cx - MENU_HALF_W, pbot), Vector2(cx + MENU_HALF_W, pbot), Color(ATMO.r, ATMO.g, ATMO.b, 0.18), 1.0)
	for i in _menu.size():
		var y := MENU_Y0 + i * MENU_GAP
		var selected := i == _sel
		var col := SEL_COL if selected else DIM_COL
		var size := 44 if selected else 36
		var label: String = "%d.  %s" % [i + 1, _menu[i]]
		if selected:
			var pulse := 0.7 + 0.3 * sin(_t * 4.0)
			col = Color(SEL_COL.r, SEL_COL.g, SEL_COL.b, pulse)
			# chevron markers
			var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			var slide := sin(_t * 4.0) * 6.0
			_text_centered(font, cx - tw * 0.5 - 46.0 - slide, y, ">", size, col)
			_text_centered(font, cx + tw * 0.5 + 46.0 + slide, y, "<", size, col)
		_text_centered(font, cx, y, label, size, col)


func _draw_footer() -> void:
	var font := ThemeDB.fallback_font
	var ver := str(ProjectSettings.get_setting("application/config/version", ""))
	if ver != "":
		ver = "v" + ver
	_text_centered(font, W * 0.5, H - 80.0,
		"[ Mouse hover + click · W/S or Arrows · Enter/Space select · 1-4 quick · Esc quit ]", 20,
		Color(0.5, 0.58, 0.7, 0.7))
	draw_string(font, Vector2(40, H - 40), "M.D.E.S.  " + ver, HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
		Color(0.45, 0.52, 0.64, 0.6))


func _ridge_far(x: float) -> float:
	return 900.0 + sin(x * 0.0042) * 24.0 + sin(x * 0.011 + 1.3) * 12.0


func _ridge_near(x: float) -> float:
	return 984.0 + sin(x * 0.0031 + 2.0) * 30.0 + sin(x * 0.0125) * 14.0


func _draw_terrain() -> void:
	var step := 24.0
	# Far hill (slightly lighter, for depth).
	var far := PackedVector2Array()
	var x := 0.0
	while x <= W:
		far.append(Vector2(x, _ridge_far(x)))
		x += step
	far.append(Vector2(W, H))
	far.append(Vector2(0, H))
	draw_colored_polygon(far, Color(0.05, 0.06, 0.11))
	# Near hill (near-black foreground).
	var near := PackedVector2Array()
	x = 0.0
	while x <= W:
		near.append(Vector2(x, _ridge_near(x)))
		x += step
	near.append(Vector2(W, H))
	near.append(Vector2(0, H))
	draw_colored_polygon(near, Color(0.015, 0.02, 0.045))
	# Faint atmospheric rim light catching the top of the near ridge.
	var rim := PackedVector2Array()
	x = 0.0
	while x <= W:
		rim.append(Vector2(x, _ridge_near(x)))
		x += step
	draw_polyline(rim, Color(ATMO.r, ATMO.g, ATMO.b, 0.10), 2.0, true)


func _draw_fog() -> void:
	for i in 5:
		var bx := fposmod(i * 430.0 + _t * 16.0, W + 600.0) - 300.0
		var by := 962.0 + i * 7.0
		for k in 3:
			draw_circle(Vector2(bx, by), 240.0 - k * 60.0, Color(0.5, 0.6, 0.78, 0.022))


func _draw_character(fx: float) -> void:
	# Lone armed survivor silhouette on the near ridge (Risk of Rain nod).
	var bob := sin(_t * 1.6) * 1.5
	var fy := _ridge_near(fx) + 2.0 + bob
	var dark := Color(0.01, 0.015, 0.035)
	var rim := Color(ATMO.r, ATMO.g, ATMO.b, 0.55)
	# legs
	draw_line(Vector2(fx - 3, fy - 22), Vector2(fx - 8, fy), dark, 6.0)
	draw_line(Vector2(fx + 4, fy - 22), Vector2(fx + 7, fy), dark, 6.0)
	# backpack
	draw_colored_polygon(PackedVector2Array([
		Vector2(fx - 15, fy - 50), Vector2(fx - 9, fy - 50),
		Vector2(fx - 9, fy - 30), Vector2(fx - 15, fy - 30)]), dark)
	# torso (tapered)
	draw_colored_polygon(PackedVector2Array([
		Vector2(fx - 11, fy - 54), Vector2(fx + 11, fy - 54),
		Vector2(fx + 8, fy - 22), Vector2(fx - 8, fy - 22)]), dark)
	# head
	draw_circle(Vector2(fx, fy - 62), 8.0, dark)
	# arm + raised rifle held forward
	draw_line(Vector2(fx + 6, fy - 48), Vector2(fx + 26, fy - 42), dark, 5.0)
	draw_line(Vector2(fx + 18, fy - 42), Vector2(fx + 42, fy - 42), dark, 3.0)
	# rim light on the planet-lit (left) edge
	draw_line(Vector2(fx - 11, fy - 53), Vector2(fx - 8, fy - 24), rim, 1.5)
	draw_line(Vector2(fx - 6, fy - 67), Vector2(fx - 7, fy - 58), rim, 1.5)


func _draw_vignette() -> void:
	var dark := Color(0, 0, 0, 0.42)
	var clear := Color(0, 0, 0, 0)
	var b := 340.0
	# top, bottom, left, right gradient bands (corners overlap => darker).
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(W, 0), Vector2(W, b), Vector2(0, b)]),
		PackedColorArray([dark, dark, clear, clear]))
	draw_polygon(PackedVector2Array([Vector2(0, H - b), Vector2(W, H - b), Vector2(W, H), Vector2(0, H)]),
		PackedColorArray([clear, clear, dark, dark]))
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(b, 0), Vector2(b, H), Vector2(0, H)]),
		PackedColorArray([dark, clear, clear, dark]))
	draw_polygon(PackedVector2Array([Vector2(W - b, 0), Vector2(W, 0), Vector2(W, H), Vector2(W - b, H)]),
		PackedColorArray([clear, dark, dark, clear]))


# --- helpers ---

func _make_blip(freq: float, dur: float, vol: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)  # 16-bit mono
	for i in n:
		var t := float(i) / rate
		var env := pow(1.0 - float(i) / n, 2.2)            # quick percussive decay
		var s := sin(TAU * freq * t)
		s = lerpf(s, signf(s), 0.25)                       # slight square edge => chiptune feel
		var v := int(clampf(s * env * vol, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


func _text_centered(font: Font, cx: float, y: float, text: String, size: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2(cx - w * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _arc_points(center: Vector2, radius: float, a0: float, a1: float, steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps + 1:
		var a: float = lerp(a0, a1, float(i) / steps)
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	return pts
