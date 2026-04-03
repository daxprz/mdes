extends Node

func _ready() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("=== STRUDEL CORE TESTS ===")
	_test_fraction()
	_test_timespan()
	_test_pattern()
	_test_composers()
	_test_combinators()
	_test_signals()
	_test_mini()
	print("=== ALL TESTS DONE ===")
	
func _test_fraction() -> void:
	# Basic arithmetic
	var a := StrudelFraction.new(1, 3)
	var b := StrudelFraction.new(1, 6)
	var sum := a.add(b)
	_assert("1/3 + 1/6 = 1/2", sum.n == 1 and sum.d == 2)
	
	var prod := a.mul(b)
	_assert("1/3 * 1/6 = 1/18", prod.n == 1 and prod.d == 18)
	
	# Comparison
	_assert("1/3 > 1/6", a.gt(b))
	_assert("1/6 < 1/3", b.lt(a))
	_assert("1/3 == 1/3", a.eq(StrudelFraction.new(1, 3)))
	_assert("2/6 == 1/3", StrudelFraction.new(2, 6).eq(a))  # auto-reduce
	
	# Cycle ops
	var f := StrudelFraction.new(5, 3)  # 1.666...
	_assert("sam(5/3) = 1", f.sam().eq(StrudelFraction.new(1, 1)))
	_assert("nextSam(5/3) = 2", f.next_sam().eq(StrudelFraction.new(2, 1)))
	_assert("cyclePos(5/3) = 2/3", f.cycle_pos().eq(StrudelFraction.new(2, 3)))
	
	# Floor
	_assert("floor(5/3) = 1", f.floor_frac().eq(StrudelFraction.new(1, 1)))
	_assert("floor(-1/3) = -1", StrudelFraction.new(-1, 3).floor_frac().eq(StrudelFraction.new(-1, 1)))
	
	# from_float
	var half := StrudelFraction.from_float(0.5)
	_assert("from_float(0.5) = 1/2", half.n == 1 and half.d == 2)
	
	# GCD/LCM
	var gcd_result := StrudelFraction.new(1, 6).gcd_with(StrudelFraction.new(1, 4))
	_assert("gcd(1/6, 1/4) = 1/12", gcd_result.eq(StrudelFraction.new(1, 12)))
	
	print("  Fraction: PASS")


func _test_timespan() -> void:
	# spanCycles
	var span := StrudelTimeSpan.new(StrudelFraction.new(0, 1), StrudelFraction.new(2, 1))
	var cycles: Array = span.spanCycles
	_assert("span(0,2) splits into 2 cycles", cycles.size() == 2)
	
	# Intersection
	var a := StrudelTimeSpan.new(StrudelFraction.new(0, 1), StrudelFraction.new(2, 1))
	var b := StrudelTimeSpan.new(StrudelFraction.new(1, 1), StrudelFraction.new(3, 1))
	var c: Variant = a.intersection(b)
	_assert("intersection exists", c != null)
	_assert("intersection = [1, 2]",
		c.begin.eq(StrudelFraction.new(1, 1)) and c.end.eq(StrudelFraction.new(2, 1)))
	
	# Duration
	_assert("duration of [0,2] = 2", span.duration.eq(StrudelFraction.new(2, 1)))
	
	# Zero-width
	var zw := StrudelTimeSpan.new(StrudelFraction.new(1, 1), StrudelFraction.new(1, 1))
	_assert("zero-width spanCycles = 1", zw.spanCycles.size() == 1)
	
	print("  TimeSpan: PASS")


func _test_pattern() -> void:
	# pure
	var pat := Strudel.pure("hello")
	var haps: Array = pat.query_arc(0.5, 2.5)
	_assert("pure('hello') query(0.5, 2.5) = 3 haps", haps.size() == 3)
	
	# Zero-width query
	var haps_zw: Array = pat.query_arc(0, 0)
	_assert("pure('hello') query(0, 0) = 1 hap", haps_zw.size() == 1)
	
	# fmap
	var pat2 := Strudel.pure(3).fmap(func(x): return x + 4)
	var val: Variant = pat2.first_cycle()[0].value
	_assert("pure(3).fmap(+4) = 7", val == 7)
	
	# silence
	var sil := Strudel.silence()
	_assert("silence has 0 haps", sil.first_cycle().size() == 0)
	
	# fast
	var fast_pat := Strudel.pure("a")._fast(2)
	var fast_haps: Array = fast_pat.query_arc(0, 1)
	_assert("pure('a').fast(2) = 2 haps in [0,1]", fast_haps.size() == 2)
	
	# sequence
	var seq_pat := Strudel.sequence([Strudel.pure("a"), Strudel.pure("b")])
	var seq_haps: Array = seq_pat.first_cycle()
	_assert("sequence('a','b') = 2 haps", seq_haps.size() == 2)
	_assert("first = 'a'", seq_haps[0].value == "a")
	_assert("second = 'b'", seq_haps[1].value == "b")
	# Check timing: a occupies [0, 1/2), b occupies [1/2, 1)
	_assert("a whole = [0, 1/2]",
		seq_haps[0].whole.begin.eq(StrudelFraction.new(0, 1)) and
		seq_haps[0].whole.end.eq(StrudelFraction.new(1, 2)))
	
	# stack
	var stack_pat := Strudel.stack([Strudel.pure("a"), Strudel.pure("b")])
	var stack_haps: Array = stack_pat.first_cycle()
	_assert("stack('a','b') = 2 haps (simultaneous)", stack_haps.size() == 2)
	
	# slowcat
	var cat_pat := Strudel.slowcat([Strudel.pure("a"), Strudel.pure("b")])
	var cat_c0: Array = cat_pat.query_arc(0, 1)
	var cat_c1: Array = cat_pat.query_arc(1, 2)
	_assert("slowcat cycle 0 = 'a'", cat_c0.size() == 1 and cat_c0[0].value == "a")
	_assert("slowcat cycle 1 = 'b'", cat_c1.size() == 1 and cat_c1[0].value == "b")
	
	# rev
	var rev_pat := Strudel.sequence([Strudel.pure("a"), Strudel.pure("b")])._rev()
	var rev_haps: Array = rev_pat.sort_haps_by_part().first_cycle()
	_assert("rev sequence = 2 haps", rev_haps.size() == 2)
	# After rev, 'b' should come first (occupies first half of the cycle)
	_assert("rev: first value = b", rev_haps[0].value == "b")
	_assert("rev: second value = a", rev_haps[1].value == "a")
	
	print("  Pattern: PASS")


func _test_composers() -> void:
	# add
	var add_result := Strudel.pure(3).pat_add(Strudel.pure(4)).first_cycle()
	_assert("pure(3).add(pure(4)) = 7", add_result[0].value == 7)

	# sub
	var sub_result := Strudel.pure(3).pat_sub(Strudel.pure(4)).first_cycle()
	_assert("pure(3).sub(pure(4)) = -1", sub_result[0].value == -1)

	# mul
	var mul_result := Strudel.pure(3).pat_mul(Strudel.pure(2)).first_cycle()
	_assert("pure(3).mul(pure(2)) = 6", mul_result[0].value == 6)

	# div
	var div_result := Strudel.pure(3).pat_div(Strudel.pure(2)).first_cycle()
	_assert("pure(3).div(pure(2)) = 1.5", div_result[0].value == 1.5)

	# set with objects
	var set_result := Strudel.pure({"a": 4, "b": 6}).set_in(Strudel.pure({"c": 7})).first_cycle()
	_assert("set merges dicts", set_result[0].value is Dictionary and set_result[0].value.get("c") == 7 and set_result[0].value.get("a") == 4)

	# struct: impose structure
	var struct_result := Strudel.pure("x").struct_out(Strudel.sequence([Strudel.pure(true), Strudel.pure(false)]))
	var struct_haps: Array = struct_result.first_cycle()
	_assert("struct filters to truthy positions", struct_haps.size() == 1)

	# mask: silence where mask is falsy
	var mask_result := Strudel.sequence([Strudel.pure("a"), Strudel.pure("b")]).mask(
		Strudel.sequence([Strudel.pure(true), Strudel.pure(false)]))
	var mask_haps: Array = mask_result.first_cycle()
	_assert("mask: keep where true", mask_haps.size() == 1 and mask_haps[0].value == "a")

	print("  Composers: PASS")


func _test_combinators() -> void:
	# every
	var every_pat := Strudel.pure("a")._every(3, func(p: StrudelPattern) -> StrudelPattern: return p.fmap(func(_v): return "b"))
	var c0: Array = every_pat.query_arc(0, 1)
	var c1: Array = every_pat.query_arc(1, 2)
	var c2: Array = every_pat.query_arc(2, 3)
	_assert("every(3,f): cycle 0 = transformed", c0[0].value == "b")
	_assert("every(3,f): cycle 1 = original", c1[0].value == "a")
	_assert("every(3,f): cycle 2 = original", c2[0].value == "a")

	# ply
	var ply_pat := Strudel.sequence([Strudel.pure("a"), Strudel.pure("b")])._ply(2)
	var ply_haps: Array = ply_pat.first_cycle()
	_assert("ply(2): doubles events", ply_haps.size() == 4)

	# palindrome
	var pal_pat := Strudel.sequence([Strudel.pure("a"), Strudel.pure("b")])._palindrome()
	var pal_c0: Array = pal_pat.query_arc(0, 1)
	var pal_c1: Array = pal_pat.sort_haps_by_part().query_arc(1, 2)
	_assert("palindrome: cycle 0 is forward", pal_c0.size() == 2 and pal_c0[0].value == "a")
	_assert("palindrome: cycle 1 is reversed", pal_c1.size() == 2 and pal_c1[0].value == "b")

	# euclid
	var euclid_pat := Strudel.pure("x")._euclid(3, 8)
	var euclid_haps: Array = euclid_pat.first_cycle()
	_assert("euclid(3,8) = 3 onsets", euclid_haps.size() == 3)

	# off
	var off_pat := Strudel.pure("a")._off(0.5, func(p: StrudelPattern) -> StrudelPattern: return p.fmap(func(_v): return "b"))
	var off_haps: Array = off_pat.first_cycle()
	_assert("off(0.5,f): 2 values (original + shifted)", off_haps.size() >= 2)

	# note() control
	var note_pat := Strudel.pure("c4").note()
	var note_haps: Array = note_pat.first_cycle()
	_assert("note() wraps as dict", note_haps[0].value is Dictionary and note_haps[0].value.get("note") == "c4")

	print("  Combinators: PASS")


func _test_signals() -> void:
	# saw: value at t=0 should be 0, at t=0.5 should be ~0.5
	var saw_pat := StrudelSignal.saw()
	var saw_0: Array = saw_pat.query_arc(0, 0)
	_assert("saw(0) = 0", saw_0.size() == 1 and absf(float(saw_0[0].value)) < 0.01)

	var saw_half: Array = saw_pat.query_arc(0.5, 0.5)
	_assert("saw(0.5) ~= 0.5", saw_half.size() == 1 and absf(float(saw_half[0].value) - 0.5) < 0.01)

	# sine
	var sine_pat := StrudelSignal.sine()
	var sine_0: Array = sine_pat.query_arc(0, 0)
	_assert("sine(0) = 0.5 (unipolar)", absf(float(sine_0[0].value) - 0.5) < 0.01)

	# segment: discretize
	var seg_pat := StrudelSignal.saw()._segment(4)
	var seg_haps: Array = seg_pat.first_cycle()
	_assert("saw.segment(4) = 4 haps", seg_haps.size() == 4)

	# range
	var range_pat := StrudelSignal.saw()._range(100, 200)
	var range_0: Array = range_pat.query_arc(0, 0)
	_assert("saw.range(100,200) at 0 = 100", absf(float(range_0[0].value) - 100.0) < 1.0)

	# run
	var run_pat := StrudelSignal.run(4)
	var run_haps: Array = run_pat.first_cycle()
	_assert("run(4) = [0,1,2,3]", run_haps.size() == 4 and run_haps[0].value == 0 and run_haps[3].value == 3)

	print("  Signals: PASS")


func _test_mini() -> void:
	# Basic sequence
	var pat := StrudelMini.mini("a b c")
	var haps: Array = pat.first_cycle()
	_assert("mini 'a b c' = 3 haps", haps.size() == 3)

	# Sub-cycle
	var pat2 := StrudelMini.mini("a [b c] d")
	var haps2: Array = pat2.first_cycle()
	_assert("mini 'a [b c] d' = 4 haps", haps2.size() == 4)

	# Fast operator
	var pat3 := StrudelMini.mini("a*3")
	var haps3: Array = pat3.first_cycle()
	_assert("mini 'a*3' = 3 haps", haps3.size() == 3)

	# Rest
	var pat4 := StrudelMini.mini("a ~ b")
	var haps4: Array = pat4.first_cycle()
	_assert("mini 'a ~ b' = 2 haps (~ is silence)", haps4.size() == 2)

	# Stack
	var pat5 := StrudelMini.mini("[a, b]")
	var haps5: Array = pat5.first_cycle()
	_assert("mini '[a, b]' = 2 haps (stacked)", haps5.size() == 2)

	# Slow
	var pat6 := StrudelMini.mini("a/2")
	var haps6a: Array = pat6.query_arc(0, 1)
	_assert("mini 'a/2' spans 2 cycles", haps6a.size() >= 1)

	# Leaf locations
	var locs: Array = StrudelMini.get_leaf_locations("bd sd hh")
	_assert("leaf locations: 3 leaves", locs.size() == 3)
	_assert("first leaf starts at 0", locs[0][0] == 0)

	print("  Mini: PASS")


func _assert(msg: String, condition: bool) -> void:
	if not condition:
		print("    FAIL: %s" % msg)
		push_error("STRUDEL TEST FAIL: %s" % msg)
	# Uncomment to see all passing tests:
	# else:
	#   print("    ok: %s" % msg)
