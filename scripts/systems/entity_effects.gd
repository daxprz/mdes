extends RefCounted

## Generic timed-effect system for arbitrary entities.
##
## Any entity (player, enemy, monster, dummy) can have effects applied to it.
## Effects are named, timed, stackable, and queryable. Entities don't need to
## know about this system — callers apply effects, and any code can query them.
##
## Usage:
##   EntityEffects.apply(enemy, "stun", 3.0)           # 3-second stun
##   EntityEffects.apply(enemy, "slow", 5.0, 0.5)      # 50% speed for 5s
##   EntityEffects.apply(player, "bleed", 4.0, 3)       # 3 DPS bleed for 4s
##   EntityEffects.apply(boss, "burn", 6.0, 5)           # 5 DPS burn for 6s
##
##   if EntityEffects.has_effect(enemy, "stun"):
##       # skip AI this frame
##
##   var slow_val = EntityEffects.get_value(enemy, "slow", 1.0)  # default 1.0
##
## The system is a static class — no autoload needed. Call EntityEffects.tick(delta)
## from any central place (or each entity can tick its own effects).

## Each active effect: { entity_rid: { effect_name: { remaining: float, value: Variant } } }
## We key by instance_id since RIDs aren't available on all node types.
static var _effects: Dictionary = {}

## Signal-like: entities can poll, or we can add signals later
static var _expired_queue: Array = []  # [{entity, effect_name}] cleared each tick


static func apply(entity: Node, effect_name: String, duration: float, value: Variant = null) -> void:
	## Apply a named effect to an entity for a duration.
	## If the effect already exists, it refreshes the timer (takes the longer remaining).
	## value: optional payload (e.g., slow multiplier, DPS for DoT, knockback force).
	if not is_instance_valid(entity):
		return
	var eid: int = entity.get_instance_id()
	if not _effects.has(eid):
		_effects[eid] = {}
	var existing: Dictionary = _effects[eid]
	if existing.has(effect_name):
		# Refresh: take the longer remaining time, update value
		existing[effect_name]["remaining"] = maxf(existing[effect_name]["remaining"], duration)
		if value != null:
			existing[effect_name]["value"] = value
	else:
		existing[effect_name] = { "remaining": duration, "value": value }

	DebugOverlay.log("effects/applied", entity, "EFFECT APPLIED: %s duration=%.1f value=%s",
		[effect_name, duration, str(value)])


static func remove(entity: Node, effect_name: String) -> void:
	## Immediately remove a named effect from an entity.
	if not is_instance_valid(entity):
		return
	var eid: int = entity.get_instance_id()
	if _effects.has(eid) and _effects[eid].has(effect_name):
		_effects[eid].erase(effect_name)
		if _effects[eid].is_empty():
			_effects.erase(eid)


static func has_effect(entity: Node, effect_name: String) -> bool:
	## Check if an entity currently has a named effect active.
	if not is_instance_valid(entity):
		return false
	var eid: int = entity.get_instance_id()
	return _effects.has(eid) and _effects[eid].has(effect_name)


static func get_value(entity: Node, effect_name: String, default: Variant = null) -> Variant:
	## Get the value payload of an active effect, or default if not active.
	if not is_instance_valid(entity):
		return default
	var eid: int = entity.get_instance_id()
	if _effects.has(eid) and _effects[eid].has(effect_name):
		return _effects[eid][effect_name].get("value", default)
	return default


static func get_remaining(entity: Node, effect_name: String) -> float:
	## Get remaining duration of an effect, or 0.0 if not active.
	if not is_instance_valid(entity):
		return 0.0
	var eid: int = entity.get_instance_id()
	if _effects.has(eid) and _effects[eid].has(effect_name):
		return _effects[eid][effect_name].get("remaining", 0.0)
	return 0.0


static func get_all_effects(entity: Node) -> Dictionary:
	## Get all active effects on an entity. Returns { name: { remaining, value } }.
	if not is_instance_valid(entity):
		return {}
	var eid: int = entity.get_instance_id()
	if _effects.has(eid):
		return _effects[eid].duplicate()
	return {}


static func clear_entity(entity: Node) -> void:
	## Remove all effects from an entity.
	if not is_instance_valid(entity):
		return
	_effects.erase(entity.get_instance_id())


static func tick(delta: float) -> void:
	## Advance all effect timers. Call once per frame from a central location.
	## Returns expired effects in _expired_queue for anyone who wants to check.
	_expired_queue.clear()
	var to_remove: Array = []
	for eid in _effects:
		var effects: Dictionary = _effects[eid]
		var expired_names: Array = []
		for effect_name in effects:
			effects[effect_name]["remaining"] -= delta
			if effects[effect_name]["remaining"] <= 0.0:
				expired_names.append(effect_name)
		for name in expired_names:
			effects.erase(name)
			_expired_queue.append({ "entity_id": eid, "effect_name": name })
		if effects.is_empty():
			to_remove.append(eid)
	for eid in to_remove:
		_effects.erase(eid)


static func get_expired_this_frame() -> Array:
	## Get effects that expired this frame: [{ entity_id, effect_name }].
	return _expired_queue


# -- Well-known effect names (conventions, not enforced) -----------------------
# "stun"   — entity cannot act (value: null)
# "slow"   — entity moves at reduced speed (value: float multiplier, e.g., 0.5 = 50%)
# "bleed"  — damage over time (value: int DPS)
# "burn"   — fire damage over time (value: int DPS)
# "poison" — poison damage over time (value: int DPS)
# "freeze" — cannot move, can still take damage (value: null)
# "weaken" — takes more damage (value: float multiplier, e.g., 1.5 = 150% damage taken)
# "haste"  — moves faster (value: float multiplier, e.g., 1.5 = 150% speed)
# "shield" — absorbs damage (value: int remaining HP)
# "regen"  — heals over time (value: int HPS)
