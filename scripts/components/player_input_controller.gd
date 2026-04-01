class_name PlayerInputController extends InputController

## Reads gamepad/keyboard input and sets intent.
## player_index and device_id live HERE, not on the Character.

@export var player_index: int = 0
@export var device_id: int = -1


func is_player() -> bool:
	return true


func poll() -> void:
	## Read device input and populate intent_direction, intent_aim, intent_actions.
	intent_direction = Vector2.ZERO
	intent_actions.clear()

	if _is_pressed("move_left"):
		intent_direction.x -= 1.0
	if _is_pressed("move_right"):
		intent_direction.x += 1.0
	if _is_pressed("move_up"):
		intent_direction.y -= 1.0
	if _is_pressed("move_down"):
		intent_direction.y += 1.0

	intent_actions["jump"] = _is_pressed("jump")
	intent_actions["just_jump"] = _is_just_pressed("jump")
	intent_actions["attack"] = _is_pressed("attack")
	intent_actions["just_attack"] = _is_just_pressed("attack")
	intent_actions["special"] = _is_pressed("special")
	intent_actions["just_special"] = _is_just_pressed("special")
	intent_actions["block"] = _is_pressed("block")
	intent_actions["just_block"] = _is_just_pressed("block")
	intent_actions["interact"] = _is_pressed("interact")
	intent_actions["just_interact"] = _is_just_pressed("interact")
	intent_actions["grapple"] = _is_pressed("grapple")
	intent_actions["just_grapple"] = _is_just_pressed("grapple")

	# Aim from right stick or mouse
	_poll_aim()


func _is_pressed(action: String) -> bool:
	if device_id >= 0:
		return Input.is_action_pressed(action, true) and _is_device_match()
	return Input.is_action_pressed(action)


func _is_just_pressed(action: String) -> bool:
	if device_id >= 0:
		return Input.is_action_just_pressed(action, true) and _is_device_match()
	return Input.is_action_just_pressed(action)


func _is_device_match() -> bool:
	## Check if the last input event came from our assigned device.
	## This is a simplified check — the full version routes through PlayerManager.
	return true  # TODO: proper per-device filtering via PlayerManager


func _poll_aim() -> void:
	## Read aim direction from right stick or mouse position.
	if device_id >= 0:
		var aim_x: float = Input.get_joy_axis(device_id, JOY_AXIS_RIGHT_X)
		var aim_y: float = Input.get_joy_axis(device_id, JOY_AXIS_RIGHT_Y)
		if Vector2(aim_x, aim_y).length() > 0.2:
			intent_aim = Vector2(aim_x, aim_y).normalized()
		else:
			intent_aim = Vector2.ZERO
	else:
		# Keyboard: aim toward mouse
		if ctx and ctx.body:
			var mouse_pos: Vector2 = ctx.body.get_global_mouse_position()
			intent_aim = (mouse_pos - ctx.body.global_position).normalized()
