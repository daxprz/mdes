class_name StrudelCyclist extends RefCounted

## Cycle-based pattern scheduler. Queries a StrudelPattern for haps and
## dispatches them to a trigger callback at the correct time.
##
## Ported from Strudel v1.2.0 cyclist.mjs.
##
## Usage:
##   var cyclist = StrudelCyclist.new(on_trigger, get_time)
##   cyclist.set_pattern(my_pattern)
##   cyclist.start()
##   # In _process():
##   cyclist.process()

var started: bool = false
var cps: float = 0.5           ## Cycles per second (0.5 = 120 BPM)
var pattern: StrudelPattern = null
var latency: float = 0.1       ## Fixed trigger time offset (seconds)

var _clock: StrudelClock
var _on_trigger: Callable      ## func(hap, deadline, duration, cps, target_time)
var _on_toggle: Callable       ## func(started: bool) — optional
var _get_time: Callable        ## func() -> float — absolute time source

var _num_ticks_since_cps_change: int = 0
var _last_tick: float = 0.0
var _last_begin: float = 0.0
var _last_end: float = 0.0
var _num_cycles_at_cps_change: float = 0.0
var _seconds_at_cps_change: float = 0.0


func _init(on_trigger: Callable, get_time: Callable,
		on_toggle: Callable = Callable(),
		p_latency: float = 0.1, interval: float = 0.05) -> void:
	_on_trigger = on_trigger
	_get_time = get_time
	_on_toggle = on_toggle
	latency = p_latency

	_clock = StrudelClock.new(_on_clock_tick, interval, 0.1)


func _on_clock_tick(phase: float, duration: float, tick: int, t: float) -> void:
	if _num_ticks_since_cps_change == 0:
		_num_cycles_at_cps_change = _last_end
		_seconds_at_cps_change = phase

	_num_ticks_since_cps_change += 1
	var seconds_since_cps_change: float = _num_ticks_since_cps_change * duration
	var num_cycles_since_cps_change: float = seconds_since_cps_change * cps

	var begin: float = _last_end
	_last_begin = begin
	var end: float = _num_cycles_at_cps_change + num_cycles_since_cps_change
	_last_end = end
	_last_tick = phase

	if phase < t:
		# Skip queries for ticks in the past
		return

	if pattern == null:
		return

	# Query the pattern for haps in this time window
	var haps: Array = pattern.query_arc(begin, end)

	for hap in haps:
		if not hap.has_onset():
			continue

		var hap_begin: float = hap.w().begin.to_float() if hap.whole != null else 0.0
		var target_time: float = (hap_begin - _num_cycles_at_cps_change) / cps + _seconds_at_cps_change + latency
		var hap_duration: float = hap.get_duration().to_float() / cps
		var deadline: float = target_time - phase

		if _on_trigger.is_valid():
			_on_trigger.call(hap, deadline, hap_duration, cps, target_time)

		# Pattern-driven CPS changes
		if hap.value is Dictionary and hap.value.has("cps"):
			var new_cps: float = float(hap.value["cps"])
			if cps != new_cps:
				cps = new_cps
				_num_ticks_since_cps_change = 0


func now() -> float:
	## Current cycle position (for visualization).
	if not started:
		return 0.0
	var seconds_since_last_tick: float = _get_time.call() - _last_tick - _clock.duration
	return _last_begin + seconds_since_last_tick * cps


func start() -> void:
	_num_ticks_since_cps_change = 0
	_num_cycles_at_cps_change = 0
	_last_end = 0.0
	_clock.start(_get_time.call())
	started = true
	if _on_toggle.is_valid():
		_on_toggle.call(true)


func pause() -> void:
	_clock.pause()
	started = false
	if _on_toggle.is_valid():
		_on_toggle.call(false)


func stop() -> void:
	_clock.stop()
	_last_end = 0.0
	started = false
	if _on_toggle.is_valid():
		_on_toggle.call(false)


func set_pattern(pat: StrudelPattern, autostart: bool = false) -> void:
	pattern = pat
	if autostart and not started:
		start()


func set_cps(new_cps: float) -> void:
	if cps == new_cps:
		return
	cps = new_cps
	_num_ticks_since_cps_change = 0


func set_bpm(bpm: float) -> void:
	## Convenience: set tempo in BPM (beats per minute = cycles per minute / 1).
	set_cps(bpm / 60.0 / 2.0)  # 120 BPM = 1 cps = 0.5 cps at "half-time"


func process() -> void:
	## Call this every frame from _process().
	if started:
		_clock.process(_get_time.call())
