extends Node

## Strudel test suite — run via RCON: `strudel test` or `strudel test <suite>`
##
## Suites:
##   all        — run everything
##   algebra    — fraction, timespan, hap, state, pattern
##   composers  — add, sub, mul, div, set, keep, keepif, struct, mask
##   combinators — every, ply, palindrome, euclid, off, note()
##   signals    — saw, sine, segment, range, run
##   mini       — parser: sequences, sub-cycles, operators, stacks, rests
##   integration — end-to-end: mini -> pattern -> trigger (requires running game)
##   voices     — voice resolution from dict values
##
## Results are printed to stdout and returned via RCON.

var _pass_count: int = 0
var _fail_count: int = 0
var _fail_messages: Array[String] = []


func run(suite: String = "all") -> String:
	_pass_count = 0
	_fail_count = 0
	_fail_messages.clear()

	print("=== STRUDEL TEST SUITE: %s ===" % suite)

	match suite:
		"all":
			_test_fraction()
			_test_timespan()
			_test_pattern()
			_test_composers()
			_test_combinators()
			_test_signals()
			_test_mini()
			_test_integration()
			_test_voices()
			_test_effects_parsing()
			_test_effects_bus()
			_test_mml_compiler()
		"algebra":
			_test_fraction()
			_test_timespan()
			_test_pattern()
		"composers":
			_test_composers()
		"combinators":
			_test_combinators()
		"signals":
			_test_signals()
		"mini":
			_test_mini()
		"integration":
			_test_integration()
		"voices":
			_test_voices()
		"effects":
			_test_effects_parsing()
			_test_effects_bus()
		"mml_compiler", "mml":
			_test_mml_compiler()
		_:
			return "ERR: unknown suite '%s'. Try: all, algebra, composers, combinators, signals, mini, integration, voices, effects, mml" % suite

	var total: int = _pass_count + _fail_count
	var result: String = "=== %d/%d PASS ===" % [_pass_count, total]
	if _fail_count > 0:
		result = "=== %d FAIL, %d/%d pass ===" % [_fail_count, _pass_count, total]
		for msg in _fail_messages:
			result += "\n  FAIL: %s" % msg
	print(result)
	return result


# ==============================================================================
# Algebra: Fraction, TimeSpan, Pattern foundation
# ==============================================================================

func _test_fraction() -> void:
	# Arithmetic
	_eq("1/3 + 1/6 = 1/2", StrudelFraction.new(1, 3).add(StrudelFraction.new(1, 6)).show(), "1/2")
	_eq("1/3 * 1/6 = 1/18", StrudelFraction.new(1, 3).mul(StrudelFraction.new(1, 6)).show(), "1/18")
	_eq("3/4 - 1/4 = 1/2", StrudelFraction.new(3, 4).sub(StrudelFraction.new(1, 4)).show(), "1/2")
	_eq("2/3 / 2 = 1/3", StrudelFraction.new(2, 3).div(StrudelFraction.new(2, 1)).show(), "1/3")

	# Comparison
	_ok("1/3 > 1/6", StrudelFraction.new(1, 3).gt(StrudelFraction.new(1, 6)))
	_ok("1/6 < 1/3", StrudelFraction.new(1, 6).lt(StrudelFraction.new(1, 3)))
	_ok("2/6 == 1/3", StrudelFraction.new(2, 6).eq(StrudelFraction.new(1, 3)))
	_ok("-1/3 < 0", StrudelFraction.new(-1, 3).lt(StrudelFraction.new(0, 1)))

	# Cycle ops
	_eq("sam(5/3) = 1", StrudelFraction.new(5, 3).sam().show(), "1/1")
	_eq("nextSam(5/3) = 2", StrudelFraction.new(5, 3).next_sam().show(), "2/1")
	_eq("cyclePos(5/3) = 2/3", StrudelFraction.new(5, 3).cycle_pos().show(), "2/3")

	# Floor
	_eq("floor(5/3) = 1", StrudelFraction.new(5, 3).floor_frac().show(), "1/1")
	_eq("floor(-1/3) = -1", StrudelFraction.new(-1, 3).floor_frac().show(), "-1/1")
	_eq("floor(3/1) = 3", StrudelFraction.new(3, 1).floor_frac().show(), "3/1")

	# from_float
	_ok("from_float(0.5) = 1/2", StrudelFraction.from_float(0.5).eq(StrudelFraction.new(1, 2)))
	_ok("from_float(0.25) = 1/4", StrudelFraction.from_float(0.25).eq(StrudelFraction.new(1, 4)))
	_ok("from_float(2.0) = 2/1", StrudelFraction.from_float(2.0).eq(StrudelFraction.new(2, 1)))

	# GCD/LCM
	_eq("gcd(1/6, 1/4) = 1/12", StrudelFraction.new(1, 6).gcd_with(StrudelFraction.new(1, 4)).show(), "1/12")

	print("  Fraction: %d tests" % (_pass_count + _fail_count))


func _test_timespan() -> void:
	var start: int = _pass_count + _fail_count

	# spanCycles
	var span := StrudelTimeSpan.new(StrudelFraction.new(0, 1), StrudelFraction.new(2, 1))
	_eq("span(0,2) splits into 2", str(span.spanCycles.size()), "2")

	var span3 := StrudelTimeSpan.new(StrudelFraction.new(0, 1), StrudelFraction.new(3, 1))
	_eq("span(0,3) splits into 3", str(span3.spanCycles.size()), "3")

	# Intersection
	var a := StrudelTimeSpan.new(StrudelFraction.new(0, 1), StrudelFraction.new(2, 1))
	var b := StrudelTimeSpan.new(StrudelFraction.new(1, 1), StrudelFraction.new(3, 1))
	var c: Variant = a.intersection(b)
	_ok("intersection exists", c != null)
	_ok("intersection = [1, 2]", c != null and c.begin.eq(StrudelFraction.new(1, 1)) and c.end.eq(StrudelFraction.new(2, 1)))

	# No intersection
	var d := StrudelTimeSpan.new(StrudelFraction.new(0, 1), StrudelFraction.new(1, 1))
	var e := StrudelTimeSpan.new(StrudelFraction.new(2, 1), StrudelFraction.new(3, 1))
	_ok("no intersection", d.intersection(e) == null)

	# Duration
	_ok("duration of [0,2] = 2", span.duration.eq(StrudelFraction.new(2, 1)))

	# Zero-width
	var zw := StrudelTimeSpan.new(StrudelFraction.new(1, 1), StrudelFraction.new(1, 1))
	_eq("zero-width spanCycles = 1", str(zw.spanCycles.size()), "1")

	print("  TimeSpan: %d tests" % (_pass_count + _fail_count - start))


func _test_pattern() -> void:
	var start: int = _pass_count + _fail_count

	# pure
	_eq("pure query(0.5,2.5) = 3 haps", str(Strudel.pure("hello").query_arc(0.5, 2.5).size()), "3")
	_eq("pure query(0,0) = 1 hap", str(Strudel.pure("hello").query_arc(0, 0).size()), "1")

	# fmap
	_eq("fmap(+4) on pure(3) = 7", str(Strudel.pure(3).fmap(func(x): return x + 4).first_cycle()[0].value), "7")

	# silence
	_eq("silence = 0 haps", str(Strudel.silence().first_cycle().size()), "0")

	# fast
	_eq("fast(2) = 2 haps", str(Strudel.pure("a")._fast(2).query_arc(0, 1).size()), "2")
	_eq("fast(3) = 3 haps", str(Strudel.pure("a")._fast(3).query_arc(0, 1).size()), "3")

	# slow
	_ok("slow(2): hap spans 2 cycles", Strudel.pure("a")._slow(2).query_arc(0, 1).size() >= 1)

	# sequence
	var seq := Strudel.sequence([Strudel.pure("a"), Strudel.pure("b")])
	var seq_h := seq.first_cycle()
	_eq("sequence(a,b) = 2 haps", str(seq_h.size()), "2")
	_eq("sequence first = a", str(seq_h[0].value), "a")
	_eq("sequence second = b", str(seq_h[1].value), "b")
	_ok("a occupies [0, 1/2)", seq_h[0].w().begin.eq(StrudelFraction.new(0, 1)) and seq_h[0].w().end.eq(StrudelFraction.new(1, 2)))

	# stack
	_eq("stack(a,b) = 2 simultaneous", str(Strudel.stack([Strudel.pure("a"), Strudel.pure("b")]).first_cycle().size()), "2")

	# slowcat
	var cat := Strudel.slowcat([Strudel.pure("a"), Strudel.pure("b")])
	_eq("slowcat c0 = a", str(cat.query_arc(0, 1)[0].value), "a")
	_eq("slowcat c1 = b", str(cat.query_arc(1, 2)[0].value), "b")

	# rev
	var rev := Strudel.sequence([Strudel.pure("a"), Strudel.pure("b")])._rev().sort_haps_by_part().first_cycle()
	_eq("rev: first = b", str(rev[0].value), "b")
	_eq("rev: second = a", str(rev[1].value), "a")

	# early/late
	var early := Strudel.pure("a")._early(StrudelFraction.new(1, 4))
	_ok("early shifts onset", early.first_cycle().size() >= 1)

	print("  Pattern: %d tests" % (_pass_count + _fail_count - start))


# ==============================================================================
# Composers
# ==============================================================================

func _test_composers() -> void:
	var start: int = _pass_count + _fail_count

	_eq("add(3,4) = 7", str(Strudel.pure(3).pat_add(Strudel.pure(4)).first_cycle()[0].value), "7")
	_eq("sub(3,4) = -1", str(Strudel.pure(3).pat_sub(Strudel.pure(4)).first_cycle()[0].value), "-1")
	_eq("mul(3,2) = 6", str(Strudel.pure(3).pat_mul(Strudel.pure(2)).first_cycle()[0].value), "6")
	_eq("div(3,2) = 1.5", str(Strudel.pure(3).pat_div(Strudel.pure(2)).first_cycle()[0].value), "1.5")

	# set merges dicts
	var set_v = Strudel.pure({"a": 4, "b": 6}).set_in(Strudel.pure({"c": 7})).first_cycle()[0].value
	_ok("set merges dicts", set_v is Dictionary and set_v.get("c") == 7 and set_v.get("a") == 4)

	# struct
	var struct_h := Strudel.pure("x").struct_out(Strudel.sequence([Strudel.pure(true), Strudel.pure(false)])).first_cycle()
	_eq("struct filters truthy", str(struct_h.size()), "1")

	# mask
	var mask_h := Strudel.sequence([Strudel.pure("a"), Strudel.pure("b")]).mask(
		Strudel.sequence([Strudel.pure(true), Strudel.pure(false)])).first_cycle()
	_eq("mask: 1 hap", str(mask_h.size()), "1")
	_eq("mask: value = a", str(mask_h[0].value), "a")

	print("  Composers: %d tests" % (_pass_count + _fail_count - start))


# ==============================================================================
# Combinators
# ==============================================================================

func _test_combinators() -> void:
	var start: int = _pass_count + _fail_count

	# every
	var ev := Strudel.pure("a")._every(3, func(p: StrudelPattern) -> StrudelPattern: return p.fmap(func(_v): return "b"))
	_eq("every(3): c0 = b", str(ev.query_arc(0, 1)[0].value), "b")
	_eq("every(3): c1 = a", str(ev.query_arc(1, 2)[0].value), "a")
	_eq("every(3): c2 = a", str(ev.query_arc(2, 3)[0].value), "a")

	# ply
	_eq("ply(2) doubles", str(Strudel.sequence([Strudel.pure("a"), Strudel.pure("b")])._ply(2).first_cycle().size()), "4")

	# palindrome
	var pal := Strudel.sequence([Strudel.pure("a"), Strudel.pure("b")])._palindrome()
	_eq("palindrome c0 = a first", str(pal.query_arc(0, 1)[0].value), "a")
	var pal1 := pal.sort_haps_by_part().query_arc(1, 2)
	_eq("palindrome c1 = b first", str(pal1[0].value), "b")

	# euclid
	_eq("euclid(3,8) = 3", str(Strudel.pure("x")._euclid(3, 8).first_cycle().size()), "3")
	_eq("euclid(5,8) = 5", str(Strudel.pure("x")._euclid(5, 8).first_cycle().size()), "5")
	_eq("euclid(7,8) = 7", str(Strudel.pure("x")._euclid(7, 8).first_cycle().size()), "7")

	# degrade
	var deg := Strudel.pure("x")._fast(100)._degrade_by(0.5, 42)
	var deg_h := deg.first_cycle()
	_ok("degrade drops some events", deg_h.size() < 100 and deg_h.size() > 20)

	# off
	var off := Strudel.pure("a")._off(0.5, func(p: StrudelPattern) -> StrudelPattern: return p.fmap(func(_v): return "b"))
	_ok("off: >= 2 haps", off.first_cycle().size() >= 2)

	# note() control
	var note_h := Strudel.pure("c4").note().first_cycle()
	_ok("note() makes dict", note_h[0].value is Dictionary and note_h[0].value.get("note") == "c4")

	# s() control
	var s_h := Strudel.pure("bd").s().first_cycle()
	_ok("s() makes dict", s_h[0].value is Dictionary and s_h[0].value.get("s") == "bd")

	print("  Combinators: %d tests" % (_pass_count + _fail_count - start))


# ==============================================================================
# Signals
# ==============================================================================

func _test_signals() -> void:
	var start: int = _pass_count + _fail_count

	# saw
	_ok("saw(0) ~= 0", absf(float(StrudelSignal.saw().query_arc(0, 0)[0].value)) < 0.01)
	_ok("saw(0.5) ~= 0.5", absf(float(StrudelSignal.saw().query_arc(0.5, 0.5)[0].value) - 0.5) < 0.01)

	# sine
	_ok("sine(0) ~= 0.5", absf(float(StrudelSignal.sine().query_arc(0, 0)[0].value) - 0.5) < 0.01)

	# tri
	_ok("tri(0) ~= 0", absf(float(StrudelSignal.tri().query_arc(0, 0)[0].value)) < 0.01)
	_ok("tri(0.5) ~= 1", absf(float(StrudelSignal.tri().query_arc(0.5, 0.5)[0].value) - 1.0) < 0.01)

	# square
	_ok("square(0) = 0", float(StrudelSignal.square().query_arc(0, 0)[0].value) < 0.5)
	_ok("square(0.75) = 1", float(StrudelSignal.square().query_arc(0.75, 0.75)[0].value) > 0.5)

	# segment
	_eq("saw.segment(4) = 4", str(StrudelSignal.saw()._segment(4).first_cycle().size()), "4")
	_eq("sine.segment(8) = 8", str(StrudelSignal.sine()._segment(8).first_cycle().size()), "8")

	# range
	_ok("saw.range(100,200) at 0 ~= 100", absf(float(StrudelSignal.saw()._range(100, 200).query_arc(0, 0)[0].value) - 100.0) < 1.0)

	# run
	var run_h := StrudelSignal.run(4).first_cycle()
	_eq("run(4) = 4 haps", str(run_h.size()), "4")
	_eq("run(4)[0] = 0", str(run_h[0].value), "0")
	_eq("run(4)[3] = 3", str(run_h[3].value), "3")

	# irand
	var ir := StrudelSignal.irand(10).first_cycle()
	_eq("irand(10) = 1 hap", str(ir.size()), "1")
	_ok("irand(10) in [0,9]", int(ir[0].value) >= 0 and int(ir[0].value) < 10)

	print("  Signals: %d tests" % (_pass_count + _fail_count - start))


# ==============================================================================
# Mini-notation parser
# ==============================================================================

func _test_mini() -> void:
	var start: int = _pass_count + _fail_count

	# Basic sequences
	_eq("'a b c' = 3", str(StrudelMini.mini("a b c").first_cycle().size()), "3")
	_eq("'a b c d' = 4", str(StrudelMini.mini("a b c d").first_cycle().size()), "4")

	# Sub-cycles
	_eq("'a [b c] d' = 4", str(StrudelMini.mini("a [b c] d").first_cycle().size()), "4")
	_eq("'[a b] [c d]' = 4", str(StrudelMini.mini("[a b] [c d]").first_cycle().size()), "4")
	_eq("'a [b [c d]]' = 4", str(StrudelMini.mini("a [b [c d]]").first_cycle().size()), "4")

	# Fast operator
	_eq("'a*3' = 3", str(StrudelMini.mini("a*3").first_cycle().size()), "3")
	_eq("'a*2 b' = 3", str(StrudelMini.mini("a*2 b").first_cycle().size()), "3")
	_eq("'[a b]*2' = 4", str(StrudelMini.mini("[a b]*2").first_cycle().size()), "4")

	# Slow operator
	var slow_h := StrudelMini.mini("a/2").query_arc(0, 1)
	_ok("'a/2' produces haps", slow_h.size() >= 1)

	# Rest
	_eq("'a ~ b' = 2", str(StrudelMini.mini("a ~ b").first_cycle().size()), "2")
	_eq("'~ ~ ~' = 0", str(StrudelMini.mini("~ ~ ~").first_cycle().size()), "0")
	_eq("'a ~ ~ b' = 2", str(StrudelMini.mini("a ~ ~ b").first_cycle().size()), "2")

	# Stack (comma)
	_eq("'[a, b]' = 2", str(StrudelMini.mini("[a, b]").first_cycle().size()), "2")
	_eq("'[a b, c]' = 3", str(StrudelMini.mini("[a b, c]").first_cycle().size()), "3")
	_eq("'[a, b, c]' = 3", str(StrudelMini.mini("[a, b, c]").first_cycle().size()), "3")

	# Angle brackets (slowcat)
	var angle := StrudelMini.mini("<a b c>")
	_ok("'<a b c>' produces haps", angle.query_arc(0, 1).size() >= 1)

	# Euclidean
	_eq("'a(3,8)' = 3", str(StrudelMini.mini("a(3,8)").first_cycle().size()), "3")

	# Degrade
	var deg_h := StrudelMini.mini("a?").first_cycle()
	_ok("'a?' produces 0 or 1 haps", deg_h.size() <= 1)

	# Replicate
	_eq("'a!3' = 3", str(StrudelMini.mini("a!3").first_cycle().size()), "3")

	# Random choose (pipe)
	_eq("'[a|b|c]' = 1", str(StrudelMini.mini("[a|b|c]").first_cycle().size()), "1")

	# Numbers as values
	var num_h := StrudelMini.mini("60 64 67").first_cycle()
	_eq("numbers: 3 haps", str(num_h.size()), "3")
	_ok("first is 60", num_h[0].value == 60)

	# Note names
	var note_h := StrudelMini.mini("c4 e4 g4").first_cycle()
	_eq("notes: 3 haps", str(note_h.size()), "3")
	_eq("first is c4", str(note_h[0].value), "c4")

	# Leaf locations
	var locs := StrudelMini.get_leaf_locations("bd sd hh")
	_eq("leaf locs: 3", str(locs.size()), "3")
	_ok("first starts at 0", locs[0][0] == 0)

	# Bad input doesn't crash
	var bad := StrudelMini.mini("a=b+c")
	_ok("bad input doesn't crash", bad != null)

	# Empty string
	var empty := StrudelMini.mini("")
	_ok("empty string ok", empty != null)

	print("  Mini: %d tests" % (_pass_count + _fail_count - start))


# ==============================================================================
# Integration: mini -> pattern -> trigger resolution
# ==============================================================================

func _test_integration() -> void:
	var start: int = _pass_count + _fail_count

	if not MusicManager._sion_trigger:
		print("  Integration: SKIP (no trigger)")
		return

	var trigger: StrudelSionTrigger = MusicManager._sion_trigger

	# Note resolution from strings
	_eq("c4 -> 60", str(trigger._resolve_note("c4")), "60")
	_eq("a4 -> 69", str(trigger._resolve_note("a4")), "69")
	_eq("c3 -> 48", str(trigger._resolve_note("c3")), "48")
	_eq("eb4 -> 63", str(trigger._resolve_note("eb4")), "63")
	_eq("f#5 -> 78", str(trigger._resolve_note("f#5")), "78")
	_eq("60 -> 60", str(trigger._resolve_note(60)), "60")

	# Note resolution from dicts
	_eq("{note:c4} -> 60", str(trigger._resolve_note({"note": "c4"})), "60")
	_eq("{value:c4} -> 60", str(trigger._resolve_note({"value": "c4"})), "60")
	_eq("{value:c4,s:flute} -> 60", str(trigger._resolve_note({"value": "c4", "s": "flute"})), "60")
	_eq("{n:60} -> 60", str(trigger._resolve_note({"n": 60})), "60")

	# Voice resolution
	var v_piano: Variant = trigger._resolve_voice({"s": "piano"})
	_ok("piano voice exists", v_piano != null)
	var v_flute: Variant = trigger._resolve_voice({"s": "flute"})
	_ok("flute voice exists", v_flute != null)
	var v_default: Variant = trigger._resolve_voice("unknown")
	_ok("default voice exists", v_default != null)
	var v_bass: Variant = trigger._resolve_voice({"sound": "bass"})
	_ok("bass via sound= exists", v_bass != null)

	# Full mini -> trigger path
	var pat := StrudelMini.mini("c4 e4 g4")
	var haps := pat.first_cycle()
	_eq("mini->pattern: 3 haps", str(haps.size()), "3")
	_eq("first resolves to 60", str(trigger._resolve_note(haps[0].value)), "60")
	_eq("second resolves to 64", str(trigger._resolve_note(haps[1].value)), "64")
	_eq("third resolves to 67", str(trigger._resolve_note(haps[2].value)), "67")

	# Mini with sound param applied
	var pat2 := StrudelMini.mini("c4 e4").set_in(Strudel.pure({"s": "strings"}))
	var haps2 := pat2.first_cycle()
	_ok("sound set on haps", haps2[0].value is Dictionary)
	_eq("note resolves through value key", str(trigger._resolve_note(haps2[0].value)), "60")
	var v2: Variant = trigger._resolve_voice(haps2[0].value)
	_ok("voice resolves from dict", v2 != null)

	print("  Integration: %d tests" % (_pass_count + _fail_count - start))


# ==============================================================================
# Voice mapping
# ==============================================================================

func _test_voices() -> void:
	var start: int = _pass_count + _fail_count

	if not MusicManager._sion_trigger:
		print("  Voices: SKIP (no trigger)")
		return

	var trigger: StrudelSionTrigger = MusicManager._sion_trigger
	var voice_count: int = trigger._voices.size()
	_ok("voices loaded", voice_count > 50)

	# Spot-check key voices exist
	for name in ["piano", "bass", "strings", "flute", "organ", "trumpet",
				  "saw", "pad", "marimba", "harp", "choir", "sax",
				  "violin", "cello", "guitar", "default"]:
		_ok("voice: %s" % name, trigger._voices.has(name))

	# Aliases resolve
	_ok("alias: pno", trigger._voices.has("pno"))
	_ok("alias: fl", trigger._voices.has("fl"))
	_ok("alias: str", trigger._voices.has("str"))
	_ok("alias: syn", trigger._voices.has("syn"))

	print("  Voices: %d tests" % (_pass_count + _fail_count - start))


# ==============================================================================
# Effects: method chain parsing and AudioBus setup
# ==============================================================================

func _test_effects_parsing() -> void:
	var start: int = _pass_count + _fail_count

	# Helper: parse a line through the drawer and return parsed dict
	# MusicDrawer is an autoload so we can call its method directly
	var line: Dictionary

	# --- Single audio control method ---
	line = MusicDrawer._make_line('"c4 e4".lpf(800)')
	var r: Dictionary = MusicDrawer._parse_line_text(line)
	_ok("lpf parsed: is_valid", r["is_valid"])
	_eq("lpf parsed: pattern_text", r["pattern_text"], "c4 e4")
	_ok("lpf parsed: has audio_controls", r.has("audio_controls"))
	_ok("lpf parsed: controls has lpf", r["audio_controls"].has("lpf"))
	_eq("lpf parsed: value", str(r["audio_controls"]["lpf"]), "800.0")

	# --- Single hpf ---
	line = MusicDrawer._make_line('"c4 e4".hpf(300)')
	r = MusicDrawer._parse_line_text(line)
	_ok("hpf parsed", r["audio_controls"].has("hpf"))
	_eq("hpf value", str(r["audio_controls"]["hpf"]), "300.0")

	# --- Multiple audio controls chained ---
	line = MusicDrawer._make_line('"c4 e4".lpf(600).room(0.5)')
	r = MusicDrawer._parse_line_text(line)
	_ok("multi: is_valid", r["is_valid"])
	_eq("multi: pattern_text", r["pattern_text"], "c4 e4")
	_ok("multi: has lpf", r["audio_controls"].has("lpf"))
	_ok("multi: has room", r["audio_controls"].has("room"))
	_eq("multi: lpf value", str(r["audio_controls"]["lpf"]), "600.0")
	_eq("multi: room value", str(r["audio_controls"]["room"]), "0.5")

	# --- Audio controls + viz method ---
	line = MusicDrawer._make_line('"c4 e4".lpf(800).room(0.5).pianoroll()')
	r = MusicDrawer._parse_line_text(line)
	_ok("with viz: is_valid", r["is_valid"])
	_eq("with viz: pattern_text", r["pattern_text"], "c4 e4")
	_ok("with viz: has lpf", r["audio_controls"].has("lpf"))
	_ok("with viz: has room", r["audio_controls"].has("room"))
	_eq("with viz: viz is pianoroll", r["viz"], MusicDrawer.VIZ_PIANOROLL)

	# --- Audio controls + viz with options ---
	line = MusicDrawer._make_line('"c4 e4".delay(0.3).pianoroll({labels:1})')
	r = MusicDrawer._parse_line_text(line)
	_ok("viz+opts: is_valid", r["is_valid"])
	_ok("viz+opts: has delay", r["audio_controls"].has("delay"))
	_eq("viz+opts: delay value", str(r["audio_controls"]["delay"]), "0.3")
	_eq("viz+opts: viz", r["viz"], MusicDrawer.VIZ_PIANOROLL)
	_ok("viz+opts: labels option", r.get("viz_options", {}).get("labels", 0) == 1)

	# --- All supported audio controls ---
	line = MusicDrawer._make_line('"c4".lpf(800).hpf(200).room(0.7).delay(0.4).distort(0.3).crush(8).pan(0.5)')
	r = MusicDrawer._parse_line_text(line)
	_ok("all controls: is_valid", r["is_valid"])
	var ctrl: Dictionary = r["audio_controls"]
	_ok("all: lpf", ctrl.has("lpf"))
	_ok("all: hpf", ctrl.has("hpf"))
	_ok("all: room", ctrl.has("room"))
	_ok("all: delay", ctrl.has("delay"))
	_ok("all: distort", ctrl.has("distort"))
	_ok("all: crush", ctrl.has("crush"))
	_ok("all: pan", ctrl.has("pan"))
	_eq("all: 7 controls", str(ctrl.size()), "7")

	# --- Named line with audio controls ---
	line = MusicDrawer._make_line('drums: "c4(3,8)".lpf(400).scope()')
	r = MusicDrawer._parse_line_text(line)
	_ok("named: is_valid", r["is_valid"])
	_eq("named: name", r["name"], "drums")
	_ok("named: has lpf", r["audio_controls"].has("lpf"))
	_eq("named: viz is scope", r["viz"], MusicDrawer.VIZ_SCOPE)

	# --- No audio controls = empty dict ---
	line = MusicDrawer._make_line('"c4 e4".pianoroll()')
	r = MusicDrawer._parse_line_text(line)
	_ok("no fx: is_valid", r["is_valid"])
	_eq("no fx: empty controls", str(r["audio_controls"].size()), "0")
	_eq("no fx: viz", r["viz"], MusicDrawer.VIZ_PIANOROLL)

	# --- Bare mini (no quotes, no methods) = no controls ---
	line = MusicDrawer._make_line("c4 e4 g4 c5")
	r = MusicDrawer._parse_line_text(line)
	_ok("bare: is_valid", r["is_valid"])
	_eq("bare: pattern_text", r["pattern_text"], "c4 e4 g4 c5")
	_eq("bare: no controls", str(r["audio_controls"].size()), "0")

	# --- note() wrapper with controls ---
	line = MusicDrawer._make_line('note("c4 e4").lpf(500).pianoroll()')
	r = MusicDrawer._parse_line_text(line)
	_ok("note(): is_valid", r["is_valid"])
	_eq("note(): pattern_text", r["pattern_text"], "c4 e4")
	_ok("note(): has lpf", r["audio_controls"].has("lpf"))
	_eq("note(): viz", r["viz"], MusicDrawer.VIZ_PIANOROLL)

	# --- Aliases resolve ---
	line = MusicDrawer._make_line('"c4".lowpass(800)')
	r = MusicDrawer._parse_line_text(line)
	_ok("alias lowpass: has lpf", r["audio_controls"].has("lpf"))

	line = MusicDrawer._make_line('"c4".highpass(300)')
	r = MusicDrawer._parse_line_text(line)
	_ok("alias highpass: has hpf", r["audio_controls"].has("hpf"))

	# --- Roomsize and delaytime ---
	line = MusicDrawer._make_line('"c4".room(0.6).roomsize(0.9).delay(0.5).delaytime(0.25)')
	r = MusicDrawer._parse_line_text(line)
	_ok("extended: has roomsize", r["audio_controls"].has("roomsize"))
	_ok("extended: has delaytime", r["audio_controls"].has("delaytime"))
	_eq("extended: roomsize value", str(r["audio_controls"]["roomsize"]), "0.9")
	_eq("extended: delaytime value", str(r["audio_controls"]["delaytime"]), "0.25")

	print("  Effects parsing: %d tests" % (_pass_count + _fail_count - start))


func _test_effects_bus() -> void:
	var start: int = _pass_count + _fail_count

	# Verify bus exists
	var bus_idx: int = MusicManager._music_bus_idx
	_ok("music bus initialized", bus_idx >= 0)

	if bus_idx < 0:
		print("  Effects bus: SKIP (bus not set up)")
		return

	var bus_name: String = AudioServer.get_bus_name(bus_idx)
	_ok("bus has a name", not bus_name.is_empty())

	# Verify correct number of effect slots
	var fx_count: int = AudioServer.get_bus_effect_count(bus_idx)
	_eq("bus has 6 effect slots", str(fx_count), str(MusicManager.FX_SLOT_COUNT))

	# All effects should start disabled
	for i in range(mini(fx_count, MusicManager.FX_SLOT_COUNT)):
		_ok("slot %d disabled" % i, not AudioServer.is_bus_effect_enabled(bus_idx, i))

	# Effect instances exist
	_ok("lpf instance", MusicManager._fx_lpf != null)
	_ok("hpf instance", MusicManager._fx_hpf != null)
	_ok("distort instance", MusicManager._fx_distort != null)
	_ok("reverb instance", MusicManager._fx_reverb != null)
	_ok("delay instance", MusicManager._fx_delay != null)
	_ok("pan instance", MusicManager._fx_pan != null)

	# --- Apply lpf control ---
	MusicManager.set_music_effects({"lpf": 800.0})
	_ok("lpf enabled", AudioServer.is_bus_effect_enabled(bus_idx, MusicManager.FX_IDX_LPF))
	_ok("hpf still disabled", not AudioServer.is_bus_effect_enabled(bus_idx, MusicManager.FX_IDX_HPF))
	_ok("reverb still disabled", not AudioServer.is_bus_effect_enabled(bus_idx, MusicManager.FX_IDX_REVERB))
	_eq("lpf cutoff", str(MusicManager._fx_lpf.cutoff_hz), "800.0")

	# --- Apply room control ---
	MusicManager.set_music_effects({"room": 0.6})
	_ok("reverb enabled", AudioServer.is_bus_effect_enabled(bus_idx, MusicManager.FX_IDX_REVERB))
	_ok("lpf now disabled (controls replaced)", not AudioServer.is_bus_effect_enabled(bus_idx, MusicManager.FX_IDX_LPF))
	_eq("reverb wet", str(snapped(MusicManager._fx_reverb.wet, 0.01)), "0.6")

	# --- Apply multiple controls ---
	MusicManager.set_music_effects({"lpf": 400.0, "room": 0.3, "delay": 0.5, "pan": -0.5})
	_ok("multi: lpf enabled", AudioServer.is_bus_effect_enabled(bus_idx, MusicManager.FX_IDX_LPF))
	_ok("multi: reverb enabled", AudioServer.is_bus_effect_enabled(bus_idx, MusicManager.FX_IDX_REVERB))
	_ok("multi: delay enabled", AudioServer.is_bus_effect_enabled(bus_idx, MusicManager.FX_IDX_DELAY))
	_ok("multi: pan enabled", AudioServer.is_bus_effect_enabled(bus_idx, MusicManager.FX_IDX_PAN))
	_ok("multi: distort disabled", not AudioServer.is_bus_effect_enabled(bus_idx, MusicManager.FX_IDX_DISTORT))
	_eq("multi: lpf cutoff", str(MusicManager._fx_lpf.cutoff_hz), "400.0")
	_eq("multi: pan value", str(MusicManager._fx_pan.pan), "-0.5")

	# --- Distortion modes ---
	MusicManager.set_music_effects({"distort": 0.5})
	_ok("distort: enabled", AudioServer.is_bus_effect_enabled(bus_idx, MusicManager.FX_IDX_DISTORT))
	_eq("distort: clip mode", str(MusicManager._fx_distort.mode), str(AudioEffectDistortion.MODE_CLIP))

	MusicManager.set_music_effects({"crush": 4.0})
	_ok("crush: enabled", AudioServer.is_bus_effect_enabled(bus_idx, MusicManager.FX_IDX_DISTORT))
	_eq("crush: lofi mode", str(MusicManager._fx_distort.mode), str(AudioEffectDistortion.MODE_LOFI))

	MusicManager.set_music_effects({"shape": 0.3})
	_ok("shape: enabled", AudioServer.is_bus_effect_enabled(bus_idx, MusicManager.FX_IDX_DISTORT))
	_eq("shape: waveshape mode", str(MusicManager._fx_distort.mode), str(AudioEffectDistortion.MODE_WAVESHAPE))

	# --- Reset ---
	MusicManager.reset_music_effects()
	for i in range(mini(fx_count, MusicManager.FX_SLOT_COUNT)):
		_ok("reset: slot %d disabled" % i, not AudioServer.is_bus_effect_enabled(bus_idx, i))
	_ok("reset: active_controls empty", MusicManager._active_controls.is_empty())

	# --- Clamping ---
	MusicManager.set_music_effects({"lpf": 99999.0})
	_eq("clamp: lpf max", str(MusicManager._fx_lpf.cutoff_hz), "20500.0")
	MusicManager.set_music_effects({"lpf": -100.0})
	_eq("clamp: lpf min", str(MusicManager._fx_lpf.cutoff_hz), "20.0")
	MusicManager.set_music_effects({"pan": 5.0})
	_eq("clamp: pan max", str(MusicManager._fx_pan.pan), "1.0")
	MusicManager.set_music_effects({"pan": -5.0})
	_eq("clamp: pan min", str(MusicManager._fx_pan.pan), "-1.0")

	# --- Per-hap trigger feedback loop ---
	# Controls injected into pattern haps should flow through the trigger
	# and update the bus on each note onset.
	MusicManager.reset_music_effects()
	if MusicManager._sion_trigger:
		var trigger: StrudelSionTrigger = MusicManager._sion_trigger
		trigger._last_fx.clear()

		# Simulate a hap with controls — trigger should update bus
		trigger._apply_hap_effects({"note": "c4", "lpf": 800.0, "room": 0.5})
		_ok("hap fx: lpf enabled", AudioServer.is_bus_effect_enabled(bus_idx, MusicManager.FX_IDX_LPF))
		_ok("hap fx: reverb enabled", AudioServer.is_bus_effect_enabled(bus_idx, MusicManager.FX_IDX_REVERB))
		_eq("hap fx: lpf cutoff", str(MusicManager._fx_lpf.cutoff_hz), "800.0")

		# Same controls again — should NOT re-call set_music_effects (change detection)
		var prev_controls: Dictionary = MusicManager._active_controls.duplicate()
		trigger._apply_hap_effects({"note": "e4", "lpf": 800.0, "room": 0.5})
		_ok("hap fx: no change, same controls", MusicManager._active_controls == prev_controls)

		# Different controls — should update
		trigger._apply_hap_effects({"note": "g4", "lpf": 400.0, "room": 0.5})
		_eq("hap fx: lpf changed", str(MusicManager._fx_lpf.cutoff_hz), "400.0")

		# Hap without controls — should reset
		trigger._apply_hap_effects("c4")
		_ok("hap fx: string value resets", not AudioServer.is_bus_effect_enabled(bus_idx, MusicManager.FX_IDX_LPF))
		_ok("hap fx: reverb also reset", not AudioServer.is_bus_effect_enabled(bus_idx, MusicManager.FX_IDX_REVERB))

		# Dict hap without effect keys — also resets
		trigger._last_fx = {"lpf": 800.0}
		MusicManager.set_music_effects({"lpf": 800.0})
		trigger._apply_hap_effects({"note": "c4", "s": "piano"})
		_ok("hap fx: dict without fx resets", not AudioServer.is_bus_effect_enabled(bus_idx, MusicManager.FX_IDX_LPF))

	# Clean up
	MusicManager.reset_music_effects()

	print("  Effects bus: %d tests" % (_pass_count + _fail_count - start))


# ==============================================================================
# MML Batch Compiler
# ==============================================================================

func _test_mml_compiler() -> void:
	var start: int = _pass_count + _fail_count
	var compiler := MmlBatchCompiler.new()

	# --- Duration decomposition: fraction of whole note → MML length ---

	# Simple powers of 2
	_eq("dur 1/1 = whole", compiler._duration_to_mml(StrudelFraction.new(1, 1)), "1")
	_eq("dur 1/2 = half", compiler._duration_to_mml(StrudelFraction.new(1, 2)), "2")
	_eq("dur 1/4 = quarter", compiler._duration_to_mml(StrudelFraction.new(1, 4)), "4")
	_eq("dur 1/8 = eighth", compiler._duration_to_mml(StrudelFraction.new(1, 8)), "8")
	_eq("dur 1/16 = 16th", compiler._duration_to_mml(StrudelFraction.new(1, 16)), "16")
	_eq("dur 1/32 = 32nd", compiler._duration_to_mml(StrudelFraction.new(1, 32)), "32")
	_eq("dur 1/64 = 64th", compiler._duration_to_mml(StrudelFraction.new(1, 64)), "64")

	# Dotted notes (value * 3/2)
	_eq("dur 3/8 = dotted quarter", compiler._duration_to_mml(StrudelFraction.new(3, 8)), "4.")
	_eq("dur 3/4 = dotted half", compiler._duration_to_mml(StrudelFraction.new(3, 4)), "2.")
	_eq("dur 3/16 = dotted eighth", compiler._duration_to_mml(StrudelFraction.new(3, 16)), "8.")
	_eq("dur 3/32 = dotted 16th", compiler._duration_to_mml(StrudelFraction.new(3, 32)), "16.")

	# Tied notes (sum of two lengths)
	# 5/16 = 1/4 + 1/16
	var dur_5_16: String = compiler._duration_to_mml(StrudelFraction.new(5, 16))
	_ok("dur 5/16 contains tie", "^" in dur_5_16)

	# Triplets (SiON supports arbitrary denominators)
	_eq("dur 1/3 = triplet", compiler._duration_to_mml(StrudelFraction.new(1, 3)), "3")
	_eq("dur 1/6 = triplet eighth", compiler._duration_to_mml(StrudelFraction.new(1, 6)), "6")
	_eq("dur 1/12 = triplet 16th", compiler._duration_to_mml(StrudelFraction.new(1, 12)), "12")

	# Edge: very small
	_eq("dur tiny = 64", compiler._duration_to_mml(StrudelFraction.new(1, 128)), "64")

	# Edge: zero
	_eq("dur zero = 64", compiler._duration_to_mml(StrudelFraction.new(0, 1)), "64")

	# 2/4 = 1/2 (should reduce)
	_eq("dur 2/4 = half", compiler._duration_to_mml(StrudelFraction.new(2, 4)), "2")

	# --- Note name resolution (standalone, no trigger) ---
	_eq("midi c4 = 60", str(MmlBatchCompiler._note_name_to_midi("c4")), "60")
	_eq("midi a4 = 69", str(MmlBatchCompiler._note_name_to_midi("a4")), "69")
	_eq("midi eb4 = 63", str(MmlBatchCompiler._note_name_to_midi("eb4")), "63")
	_eq("midi 60 = 60", str(MmlBatchCompiler._note_name_to_midi("60")), "60")

	# --- Single-voice MML generation ---
	# Create haps from mini-notation and compile to MML
	var pat: StrudelPattern = StrudelMini.mini("c4 e4 g4 c5")
	var haps: Array = pat.first_cycle()
	_eq("4-note pattern: 4 haps", str(haps.size()), "4")

	var mml: String = compiler._haps_to_mml(haps, 120)
	_ok("mml not empty", not mml.is_empty())
	_ok("mml has tempo", "t120" in mml)
	# Notes use MML letter names: o4 c, o4 e, o4 g, o5 c
	_ok("mml has o4 (octave 4)", "o4" in mml)
	_ok("mml has c (C note)", " c" in mml)
	_ok("mml has e (E note)", " e" in mml)
	_ok("mml has g (G note)", " g" in mml)

	# Each note should be a quarter (l4) since 4 equal notes per cycle
	_ok("mml has quarter notes", " c4 " in mml or "c4 " in mml)

	# --- Euclidean rhythm MML ---
	var euc_pat: StrudelPattern = StrudelMini.mini("c4(3,8)")
	var euc_haps: Array = euc_pat.first_cycle()
	_eq("euclidean (3,8): 3 haps", str(euc_haps.size()), "3")

	var euc_mml: String = compiler._haps_to_mml(euc_haps, 240)
	_ok("euclidean mml not empty", not euc_mml.is_empty())
	_ok("euclidean mml has tempo", "t240" in euc_mml)
	_ok("euclidean mml has c note", " c" in euc_mml)

	# --- Voice grouping ---
	var stacked: StrudelPattern = Strudel.stack([
		StrudelMini.mini("c4 e4").set_in(Strudel.pure({"s": "flute"})),
		StrudelMini.mini("c2 g2").set_in(Strudel.pure({"s": "bass"})),
	])
	var stacked_haps: Array = stacked.first_cycle()
	_eq("stacked: 4 haps", str(stacked_haps.size()), "4")

	var groups: Dictionary = compiler._group_by_voice(stacked_haps)
	_ok("groups has flute", groups.has("flute"))
	_ok("groups has bass", groups.has("bass"))
	_eq("flute group: 2 haps", str(groups["flute"]["haps"].size()), "2")
	_eq("bass group: 2 haps", str(groups["bass"]["haps"].size()), "2")

	# --- Full compile_cycle ---
	var result: Dictionary = compiler.compile_cycle(stacked_haps, 0.5)
	_ok("compile_cycle: has flute track", result.has("flute"))
	_ok("compile_cycle: has bass track", result.has("bass"))
	_ok("compile_cycle: flute has mml", result["flute"].has("mml"))
	_ok("compile_cycle: bass has mml", result["bass"].has("mml"))
	_ok("compile_cycle: flute mml not empty", not result["flute"]["mml"].is_empty())

	# Verify the MML can be compiled by SiON (requires driver)
	if MusicManager.driver:
		for track_key in result:
			var compiled: Variant = MusicManager.driver.call("compile", result[track_key]["mml"])
			_ok("SiON compile '%s': success" % track_key, compiled != null)
	else:
		print("  MML compiler: SKIP SiON compile test (no driver)")

	# --- Lane splitting (polyphony within same voice) ---
	var chord: StrudelPattern = StrudelMini.mini("[c4,e4,g4]")
	var chord_haps: Array = chord.first_cycle()
	_eq("chord: 3 haps", str(chord_haps.size()), "3")

	# All same onset → should split into 3 lanes
	var lanes: Array = compiler._split_into_lanes(chord_haps)
	_ok("chord lanes >= 2", lanes.size() >= 2)

	print("  MML compiler: %d tests" % (_pass_count + _fail_count - start))


# ==============================================================================
# Assert helpers
# ==============================================================================

func _ok(msg: String, condition: bool) -> void:
	if condition:
		_pass_count += 1
	else:
		_fail_count += 1
		_fail_messages.append(msg)
		print("    FAIL: %s" % msg)

func _eq(msg: String, actual: String, expected: String) -> void:
	if actual == expected:
		_pass_count += 1
	else:
		_fail_count += 1
		_fail_messages.append("%s (got '%s', expected '%s')" % [msg, actual, expected])
		print("    FAIL: %s (got '%s', expected '%s')" % [msg, actual, expected])
