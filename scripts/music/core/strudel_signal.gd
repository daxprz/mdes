class_name StrudelSignal extends RefCounted

## Continuous signal patterns — time-varying values without discrete events.
## Ported from Strudel v1.2.0 signal.mjs.
##
## Signals are continuous: their haps have whole=null, meaning they represent
## a sampled value at a point in time rather than a discrete event.
## Use .segment(n) to discretize them into n events per cycle.

# -- Core signal factory -------------------------------------------------------

static func sig(func_time: Callable) -> StrudelPattern:
	## Create a continuous pattern from a function of time.
	## func_time takes a Fraction and returns a float.
	var q := func(state: StrudelState) -> Array:
		return [StrudelHap.new(null, state.span, func_time.call(state.span.begin))]
	return StrudelPattern.new(q)


static func steady(value: Variant) -> StrudelPattern:
	## A continuous constant value.
	return StrudelPattern.new(func(state: StrudelState) -> Array:
		return [StrudelHap.new(null, state.span, value)])


# -- Waveform signals ----------------------------------------------------------

## Sawtooth wave: 0 to 1 over one cycle, then resets.
static func saw() -> StrudelPattern:
	return sig(func(t: StrudelFraction) -> float:
		return fmod(t.to_float(), 1.0))

## Inverse sawtooth: 1 to 0 over one cycle.
static func isaw() -> StrudelPattern:
	return sig(func(t: StrudelFraction) -> float:
		return 1.0 - fmod(t.to_float(), 1.0))

## Sine wave: 0 to 1 to 0 (unipolar).
static func sine() -> StrudelPattern:
	return sig(func(t: StrudelFraction) -> float:
		return (sin(TAU * t.to_float()) + 1.0) / 2.0)

## Bipolar sine: -1 to 1.
static func sine2() -> StrudelPattern:
	return sig(func(t: StrudelFraction) -> float:
		return sin(TAU * t.to_float()))

## Cosine wave: unipolar (0 to 1).
static func cosine() -> StrudelPattern:
	return sig(func(t: StrudelFraction) -> float:
		return (cos(TAU * t.to_float()) + 1.0) / 2.0)

## Triangle wave: 0 to 1 to 0 (unipolar).
static func tri() -> StrudelPattern:
	return sig(func(t: StrudelFraction) -> float:
		var pos: float = fmod(t.to_float(), 1.0)
		return 1.0 - absf(pos * 2.0 - 1.0))

## Bipolar triangle: -1 to 1 to -1.
static func tri2() -> StrudelPattern:
	return sig(func(t: StrudelFraction) -> float:
		var pos: float = fmod(t.to_float(), 1.0)
		return (1.0 - absf(pos * 2.0 - 1.0)) * 2.0 - 1.0)

## Square wave: 0 for first half, 1 for second half (unipolar).
static func square() -> StrudelPattern:
	return sig(func(t: StrudelFraction) -> float:
		return 0.0 if fmod(t.to_float(), 1.0) < 0.5 else 1.0)

## Bipolar square: -1 for first half, 1 for second half.
static func square2() -> StrudelPattern:
	return sig(func(t: StrudelFraction) -> float:
		return -1.0 if fmod(t.to_float(), 1.0) < 0.5 else 1.0)

## Random value — deterministic PRNG matching Strudel v1.2.0's xorwise algorithm.
## Ported from signal.mjs: xorwise → timeToIntSeed → intSeedToRand → timeToRand.
static func rand() -> StrudelPattern:
	return sig(func(t: StrudelFraction) -> float:
		return _time_to_rand(t.to_float()))


static func _to_int32(x: int) -> int:
	## Simulate JavaScript's ToInt32 (32-bit signed integer semantics).
	x = x & 0xFFFFFFFF
	if x >= 0x80000000:
		x -= 0x100000000
	return x


static func _xorwise(x: int) -> int:
	## Strudel's xorwise PRNG (from Tidal Cycles / Haskell Music Theory).
	## Must use 32-bit signed integer semantics to match JavaScript.
	x = _to_int32(x)
	var a: int = _to_int32(_to_int32(x << 13) ^ x)
	var b: int = _to_int32((a >> 17) ^ a)
	return _to_int32(_to_int32(b << 5) ^ b)


static func _time_to_rand(x: float) -> float:
	## Strudel's timeToRand: maps a time value to a deterministic [0,1) random.
	## Stretches 300 cycles over [0, 2^29), applies xorwise.
	var frac: float = x / 300.0
	frac = frac - floorf(frac)  # fractional part
	var int_seed: int = _xorwise(int(frac * 536870912.0))
	return absf(float(int_seed % 536870912) / 536870912.0)

## Linear time signal: value equals the cycle position (0, 1, 2, ...).
static func time_signal() -> StrudelPattern:
	return sig(func(t: StrudelFraction) -> float: return t.to_float())

# -- Numeric patterns ----------------------------------------------------------

## Run: count from 0 to n-1 in one cycle.
static func run(n: int) -> StrudelPattern:
	var pats: Array = []
	for i in range(n):
		pats.append(Strudel.pure(i))
	return Strudel.sequence(pats)

## Scan: like run but builds up (1, then 1 2, then 1 2 3, ...).
static func scan(n: int) -> StrudelPattern:
	var pats: Array = []
	for i in range(1, n + 1):
		pats.append(run(i))
	return Strudel.slowcat(pats)

## Integer random: random integer 0..n-1, one per cycle.
static func irand(n: int) -> StrudelPattern:
	return rand()._segment(1).fmap(func(v: float) -> int: return int(v * n) % n)

## Choose: randomly pick from given values each cycle.
static func choose(values: Array) -> StrudelPattern:
	if values.is_empty():
		return Strudel.silence()
	return rand()._segment(1).fmap(func(v: float) -> Variant:
		return values[int(v * values.size()) % values.size()])
