class_name StrudelFraction extends RefCounted

## Exact rational number for Strudel's time domain.
## All time values in the pattern algebra use fractions, never floats.
## Ported from Strudel v1.2.0 fraction.mjs + fraction.js behavior.

var n: int  ## Numerator (signed, carries the sign of the fraction)
var d: int  ## Denominator (always positive, >= 1)

# -- Construction --------------------------------------------------------------

func _init(numerator: int = 0, denominator: int = 1) -> void:
	assert(denominator != 0, "StrudelFraction: denominator cannot be zero")
	# Normalize sign: denominator is always positive
	if denominator < 0:
		numerator = -numerator
		denominator = -denominator
	# Reduce
	var g: int = _gcd(absi(numerator), denominator)
	n = numerator / g
	d = denominator / g


static func from_int(value: int) -> StrudelFraction:
	return StrudelFraction.new(value, 1)


static func from_float(value: float) -> StrudelFraction:
	## Convert a float to a fraction. Multiplies by increasing powers of 10
	## until the fractional part vanishes, then reduces.
	if value == floorf(value):
		return StrudelFraction.new(int(value), 1)
	# Multiply up to remove decimal places (max 10 digits of precision)
	var sign: int = 1 if value >= 0.0 else -1
	var abs_val: float = absf(value)
	var den: int = 1
	var scaled: float = abs_val
	for _i in range(10):
		if absf(scaled - roundf(scaled)) < 1e-9:
			break
		den *= 10
		scaled = abs_val * den
	var num: int = int(roundf(scaled)) * sign
	return StrudelFraction.new(num, den)


static func create(value: Variant) -> StrudelFraction:
	## Universal constructor: accepts int, float, StrudelFraction, or String "n/d".
	if value is StrudelFraction:
		return value
	if value is int:
		return from_int(value)
	if value is float:
		return from_float(value)
	if value is String:
		var parts: PackedStringArray = value.split("/")
		if parts.size() == 2:
			return StrudelFraction.new(int(parts[0]), int(parts[1]))
		return from_float(float(value))
	push_warning("StrudelFraction.create: unexpected type %s" % typeof(value))
	return StrudelFraction.new(0, 1)


# -- Arithmetic ----------------------------------------------------------------

func add(other: StrudelFraction) -> StrudelFraction:
	return StrudelFraction.new(n * other.d + other.n * d, d * other.d)

func sub(other: StrudelFraction) -> StrudelFraction:
	return StrudelFraction.new(n * other.d - other.n * d, d * other.d)

func mul(other: StrudelFraction) -> StrudelFraction:
	return StrudelFraction.new(n * other.n, d * other.d)

func div(other: StrudelFraction) -> StrudelFraction:
	assert(other.n != 0, "StrudelFraction: division by zero")
	return StrudelFraction.new(n * other.d, d * other.n)

func modulo(other: StrudelFraction) -> StrudelFraction:
	## Floored modulo matching Strudel/Haskell behavior (always non-negative for positive divisor)
	var quotient: StrudelFraction = self.div(other)
	var floored: StrudelFraction = quotient.floor_frac()
	return self.sub(other.mul(floored))

func negate() -> StrudelFraction:
	return StrudelFraction.new(-n, d)

func abs_frac() -> StrudelFraction:
	return StrudelFraction.new(absi(n), d)

func inverse() -> StrudelFraction:
	return StrudelFraction.new(d, n)

# -- Comparison ----------------------------------------------------------------

func compare(other: StrudelFraction) -> int:
	## Returns -1, 0, or 1
	var lhs: int = n * other.d
	var rhs: int = other.n * d
	if lhs < rhs:
		return -1
	if lhs > rhs:
		return 1
	return 0

func lt(other: StrudelFraction) -> bool:
	return compare(other) < 0

func gt(other: StrudelFraction) -> bool:
	return compare(other) > 0

func lte(other: StrudelFraction) -> bool:
	return compare(other) <= 0

func gte(other: StrudelFraction) -> bool:
	return compare(other) >= 0

func eq(other: StrudelFraction) -> bool:
	return n == other.n and d == other.d

func ne(other: StrudelFraction) -> bool:
	return not eq(other)

func equals(other: StrudelFraction) -> bool:
	return eq(other)

func max_frac(other: StrudelFraction) -> StrudelFraction:
	return self if gt(other) else other

func min_frac(other: StrudelFraction) -> StrudelFraction:
	return self if lt(other) else other

func maximum(others: Array) -> StrudelFraction:
	var result: StrudelFraction = self
	for other in others:
		var f: StrudelFraction = StrudelFraction.create(other)
		result = result.max_frac(f)
	return result

# -- Rounding / Cycle Ops -----------------------------------------------------

func floor_frac() -> StrudelFraction:
	## Mathematical floor: largest integer <= self.
	if d == 1:
		return StrudelFraction.new(n, 1)
	if n >= 0:
		return StrudelFraction.new(n / d, 1)
	# Negative: floor rounds toward -infinity
	return StrudelFraction.new((n / d) - 1, 1)

func ceil_frac() -> StrudelFraction:
	if d == 1:
		return StrudelFraction.new(n, 1)
	if n > 0:
		return StrudelFraction.new((n / d) + 1, 1)
	return StrudelFraction.new(n / d, 1)

func sam() -> StrudelFraction:
	## Start of the cycle containing this time. (= floor)
	return floor_frac()

func next_sam() -> StrudelFraction:
	## Start of the next cycle.
	return sam().add(StrudelFraction.new(1, 1))

func whole_cycle() -> Array:
	## Returns [begin, end] Fractions for the cycle containing this time.
	return [sam(), next_sam()]

func cycle_pos() -> StrudelFraction:
	## Position within the current cycle (0..1).
	return self.sub(sam())

# -- Conversion ----------------------------------------------------------------

func to_float() -> float:
	return float(n) / float(d)

func show() -> String:
	return "%d/%d" % [n, d]

func to_fraction_string(exclude_whole: bool = false) -> String:
	if d == 1:
		return str(n)
	if exclude_whole and absi(n) > d:
		var whole: int = n / d
		var remainder: int = absi(n) % d
		if remainder == 0:
			return str(whole)
		return "%d %d/%d" % [whole, remainder, d]
	return "%d/%d" % [n, d]

func _to_string() -> String:
	return show()

# -- GCD / LCM (static) -------------------------------------------------------

func gcd_with(other: StrudelFraction) -> StrudelFraction:
	## GCD of two fractions: gcd(a/b, c/d) = gcd(a,c) / lcm(b,d)
	var gcd_num: int = _gcd(absi(n), absi(other.n))
	var lcm_den: int = _lcm(d, other.d)
	return StrudelFraction.new(gcd_num, lcm_den)

func lcm_with(other: StrudelFraction) -> StrudelFraction:
	## LCM of two fractions: lcm(a/b, c/d) = lcm(a,c) / gcd(b,d)
	var lcm_num: int = _lcm(absi(n), absi(other.n))
	var gcd_den: int = _gcd(d, other.d)
	return StrudelFraction.new(lcm_num, gcd_den)

# -- Maybe ops (match Strudel's mulmaybe etc.) ---------------------------------

func mulmaybe(other) -> Variant:
	if other == null:
		return null
	return mul(StrudelFraction.create(other))

func divmaybe(other) -> Variant:
	if other == null:
		return null
	return div(StrudelFraction.create(other))

func addmaybe(other) -> Variant:
	if other == null:
		return null
	return add(StrudelFraction.create(other))

func submaybe(other) -> Variant:
	if other == null:
		return null
	return sub(StrudelFraction.create(other))

# -- Or (match Strudel's Fraction.or) -----------------------------------------

func or_frac(other: StrudelFraction) -> StrudelFraction:
	return other if eq(StrudelFraction.new(0, 1)) else self

# -- Internal ------------------------------------------------------------------

static func _gcd(a: int, b: int) -> int:
	a = absi(a)
	b = absi(b)
	while b != 0:
		var t: int = b
		b = a % b
		a = t
	return maxi(a, 1)

static func _lcm(a: int, b: int) -> int:
	if a == 0 or b == 0:
		return 0
	return absi(a * b) / _gcd(a, b)
