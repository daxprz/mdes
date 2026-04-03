class_name StrudelClock extends RefCounted

## Frame-based clock for the Strudel scheduler.
## Replaces Strudel's zyklus.mjs (setInterval-based) with Godot frame timing.
## Called from _process() each frame — no timers needed.

var phase: float = 0.0         ## Next callback time (seconds)
var duration: float = 0.05     ## Duration of each tick window (seconds)
var tick: int = 0              ## Tick counter
var min_latency: float = 0.01
var running: bool = false

var _callback: Callable        ## func(phase, duration, tick, current_time)
var _overlap: float = 0.1


func _init(callback: Callable, p_duration: float = 0.05, p_overlap: float = 0.1) -> void:
	_callback = callback
	duration = p_duration
	_overlap = p_overlap


func start(current_time: float) -> void:
	phase = current_time + min_latency
	tick = 0
	running = true


func stop() -> void:
	tick = 0
	phase = 0.0
	running = false


func pause() -> void:
	running = false


func process(current_time: float) -> void:
	## Call this every frame from _process(). Fires callbacks as needed.
	if not running:
		return
	var lookahead: float = current_time + duration + _overlap
	while phase < lookahead:
		phase = snappedf(phase, 0.0001)  # Round to avoid drift
		_callback.call(phase, duration, tick, current_time)
		phase += duration
		tick += 1
