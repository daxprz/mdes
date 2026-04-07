class_name BarScheduler extends RefCounted

## Drives playback of a MusicRecord — detects cycle boundaries, advances bars,
## and dispatches per-Track phrases to the playback engine.
##
## The scheduler NEVER stacks patterns.  Each Track's phrase is played
## independently through its own cyclist query window or note dispatch.

var record: MusicRecord = null

## Reference to the cyclist for timing
var _cyclist: RefCounted = null  # StrudelCyclist

## Last integer cycle boundary we processed
var _last_cycle_int: int = -1

## The movement we're currently looping in (for generating cued bars)
var _current_movement_id: String = ""

## Absolute cycle counter
var _cycle_counter: int = 0


func setup(p_record: MusicRecord, p_cyclist: RefCounted) -> void:
	record = p_record
	_cyclist = p_cyclist


func start() -> void:
	## Begin playback — advance to the first bar.
	if not record or record.cued_bars.is_empty():
		return
	_last_cycle_int = -1
	_cycle_counter = 0
	record.is_playing = true
	record.advance_bar()
	if record.current_bar:
		_current_movement_id = record.current_bar.movement.id if record.current_bar.movement else ""


func process() -> void:
	## Called every frame.  Updates PlayHead, detects cycle boundaries,
	## advances bars when a cycle completes.
	if not record or not record.is_playing or not _cyclist:
		return

	var now: float = _cyclist.now()
	record.play_head.update_from_cyclist(now)

	var current_cycle_int: int = int(floorf(now))

	# Detect cycle boundary crossing
	if _last_cycle_int >= 0 and current_cycle_int > _last_cycle_int:
		_on_cycle_boundary(current_cycle_int)

	_last_cycle_int = current_cycle_int


func _on_cycle_boundary(_cycle_int: int) -> void:
	## A new cycle has started.  Check if we need to advance the bar.
	_cycle_counter += 1

	# Check if current bar's section has a finite bar count
	var bar: MusicBar = record.current_bar
	if not bar:
		return

	# Always advance at cycle boundary — each bar is one cycle
	record.advance_bar()

	if record.current_bar:
		_current_movement_id = record.current_bar.movement.id if record.current_bar.movement else ""

	# Refill cue if running low
	_refill_cue()


func transition_to(target_movement_id: String, bridge: MusicBridge = null) -> void:
	## Replace the cue queue to transition to a new movement.
	## If bridge is provided, plays bridge bars first, then target movement.
	## Current bar plays to completion — transition starts at next cycle boundary.
	if not record or not record.composition:
		return

	var target: MusicMovement = record.composition.movements.get(target_movement_id)
	if not target:
		push_error("BarScheduler: unknown movement '%s'" % target_movement_id)
		return

	var new_cue: Array = []
	var cycle: int = _cycle_counter + 1

	# Bridge bars first
	if bridge:
		for bi in range(bridge.bars):
			new_cue.append(MusicBar.from_bridge(bridge, target, bi, cycle))
			cycle += 1

	# Target movement bars (fill a reasonable lookahead)
	for mi in range(8):
		new_cue.append(MusicBar.from_movement(target, mi, cycle))
		cycle += 1

	_current_movement_id = target_movement_id
	record.replace_cued(new_cue)


func _refill_cue() -> void:
	## Keep the cue queue populated.  For infinite movements, generate more bars.
	if not record or not record.composition:
		return

	# Target: keep at least 4 bars in the cue
	while record.cued_bars.size() < 4:
		var movement: MusicMovement = record.composition.movements.get(_current_movement_id)
		if not movement:
			break
		# For infinite movements, keep generating bars
		if movement.bars < 0:
			var last_cycle: int = _cycle_counter
			if not record.cued_bars.is_empty():
				last_cycle = record.cued_bars[-1].cycle_number
			var bar_idx: int = 0
			if not record.cued_bars.is_empty():
				bar_idx = record.cued_bars[-1].index + 1
			record.cued_bars.append(MusicBar.from_movement(movement, bar_idx, last_cycle + 1))
		else:
			# Finite movement — don't generate past the end
			break
