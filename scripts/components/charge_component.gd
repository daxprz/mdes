extends Node

## Charge attack system — hold attack button to charge, release to fire.
## Generic framework; class-specific VFX via hooks on the ClassComponent.
##
## The charge system reads input, manages charge state, and dispatches
## the charged attack via the class dispatch table when released.

const CHARGE_MIN := 0.5
const CHARGE_MAX := 3.0

var _player: Object = null  # The player node (ctx.body equivalent)

# State vars live on the player for backwards compatibility with class hooks.
# This component reads/writes _player._charge_time, _player._is_charging, etc.


func setup(player: Object) -> void:
	_player = player


func tick(delta: float) -> void:
	if not _player:
		return

	var pressing_attack: bool = _player._is_device_action_pressed("attack")

	# -- Button just pressed: reset charge tracking
	if pressing_attack and not _player._was_pressing_attack:
		_player._charge_time = 0.0
		_player._charge_smoke_timer = 0.0
		_player._charge_hover_time = 0.0
		_notify_class("on_charge_press")

	# -- Transition from hold to charge
	if pressing_attack and _player._was_pressing_attack and not _player._is_charging and _player._attack_cooldown <= 0.0:
		_player._charge_time += delta
		var threshold: float = _get_charge_threshold()
		if _player._charge_time >= threshold:
			_player._is_charging = true
			_player._charge_time = threshold
			_notify_class("on_charge_start")

	# -- Charging: accumulate + VFX
	if pressing_attack and _player._is_charging:
		var charge_speed_bonus: float = PlayerManager.get_skill_bonus(_player.player_index, "charge")
		_player._charge_time = minf(_player._charge_time + delta * charge_speed_bonus, CHARGE_MAX)
		var charge_ratio: float = clampf(_player._charge_time / CHARGE_MAX, 0.0, 1.0)

		# Class-specific charge tick (VFX, movement override, etc.)
		_notify_class_with("on_charge_tick", [delta, charge_ratio])

		# Default: glow toward yellow (class can override)
		if not _class_handles("on_charge_tick"):
			var glow_color := Color(1.0, 1.0, 1.0 - charge_ratio * 0.7, 1.0)
			_player.modulate = glow_color

		# Spawn small charge particles
		_player._charge_smoke_timer += delta
		if _player._charge_smoke_timer >= 0.1:
			_player._charge_smoke_timer -= 0.1
			var particle_color := Color(1.0, 0.9, 0.3, 0.4 * charge_ratio)
			_player._spawn_vfx(particle_color, Vector2(6, 6))

	# -- Button released while charging: fire
	elif not pressing_attack and _player._was_pressing_attack and _player._is_charging:
		_player._is_charging = false
		_player.modulate = Color.WHITE
		_notify_class("on_charge_release")

		if _player._charge_time >= CHARGE_MIN:
			_player._attack_cooldown = _player.cfg("attack_cooldown", _player.ATTACK_COOLDOWN_TIME)
			_player._is_attacking = true
			_player._attack_timer = _player.ATTACK_DURATION
			PlayerManager.add_skill_xp(_player.player_index, "charge", 5)
			_perform_charged_attack()
		_player._charge_time = 0.0

	_player._was_pressing_attack = pressing_attack


func _perform_charged_attack() -> void:
	var charge_ratio: float = clampf((_player._charge_time - CHARGE_MIN) / (CHARGE_MAX - CHARGE_MIN), 0.0, 1.0)
	var fn: Variant = _player._class_charged_fn.get(_player.character_class)
	if fn is Callable:
		fn.call(charge_ratio)


func _get_charge_threshold() -> float:
	## Class-specific charge threshold. Default 0.3s.
	var cls_comp = _get_class_comp()
	if cls_comp and cls_comp.has_method("get_charge_threshold"):
		return cls_comp.get_charge_threshold()
	return 0.3


func _notify_class(method: String) -> void:
	var cls_comp = _get_class_comp()
	if cls_comp and cls_comp.has_method(method):
		cls_comp.call(method)


func _notify_class_with(method: String, args: Array) -> void:
	var cls_comp = _get_class_comp()
	if cls_comp and cls_comp.has_method(method):
		cls_comp.callv(method, args)


func _class_handles(method: String) -> bool:
	var cls_comp = _get_class_comp()
	return cls_comp and cls_comp.has_method(method)


func _get_class_comp() -> Object:
	## Find the active class component on the player.
	for cls_var in ["_executioner_class", "_ranger_class", "_melee_class", "_mage_class",
					"_tank_class", "_balloonist_class", "_ninja_class", "_rogue_class",
					"_demolitionist_class", "_healer_class", "_summoner_class",
					"_guitarist_class", "_werewolf_class"]:
		if cls_var in _player:
			var comp = _player.get(cls_var)
			if comp:
				return comp
	return null


func get_charge_ratio() -> float:
	return clampf(_player._charge_time / CHARGE_MAX, 0.0, 1.0) if _player._is_charging else 0.0
