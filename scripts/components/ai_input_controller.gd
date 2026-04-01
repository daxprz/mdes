class_name AIInputController extends InputController

## AI input controller — reads from a command queue.
## Same interface as PlayerInputController but driven by RCON ai_cmd.

var _ai_active: bool = true
var _cmd_queue: Array = []  ## [{actions, duration, aim, elapsed}]
var _current_cmd: Dictionary = {}


func is_player() -> bool:
	return false


func poll() -> void:
	intent_direction = Vector2.ZERO
	intent_actions.clear()
	intent_aim = Vector2.ZERO

	if not _ai_active or _cmd_queue.is_empty():
		return

	_current_cmd = _cmd_queue[0]
	var actions: Array = _current_cmd.get("actions", [])
	var aim: Vector2 = _current_cmd.get("aim", Vector2.ZERO)

	# Set direction from actions
	if "move_left" in actions:
		intent_direction.x = -1.0
	if "move_right" in actions:
		intent_direction.x = 1.0

	# Set action intents
	for action in actions:
		intent_actions[action] = true
		intent_actions["just_%s" % action] = (_current_cmd.get("elapsed", 0.0) == 0.0)

	intent_aim = aim


func tick(delta: float) -> void:
	## Advance command timers. Called by Character after poll().
	if _cmd_queue.is_empty():
		return
	_cmd_queue[0]["elapsed"] = _cmd_queue[0].get("elapsed", 0.0) + delta
	if _cmd_queue[0]["elapsed"] >= _cmd_queue[0].get("duration", 0.0):
		_cmd_queue.pop_front()


func queue_cmd(actions: Array, duration: float, aim: Vector2 = Vector2.ZERO) -> void:
	_cmd_queue.append({"actions": actions, "duration": duration, "aim": aim, "elapsed": 0.0})


func clear() -> void:
	_cmd_queue.clear()
	_current_cmd = {}
