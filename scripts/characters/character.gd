class_name Character extends CharacterBody2D

## Universal character base — shared by ALL combatants (players AND enemies).
## Owns the composition infrastructure: context, FSMs, components.
## Subclasses (player_side.gd during migration) add class-specific behavior.
##
## The RCON interface (ai_queue_cmd, reset_state, cfg, etc.) is preserved
## through compatibility methods that delegate to the new components.

# -- Composition nodes (set by subclass or scene tree) -------------------------
# Typed as Variant to avoid class_name resolution order issues during loading.
# Runtime type is enforced in _build_context().

var _ctx: Variant                       ## CharacterContext
var _input_controller: Variant          ## InputController
var _movement_fsm: Variant              ## StateMachine
var _action_fsm: Variant                ## StateMachine
var _health_comp: Variant               ## HealthComponent
var _stats_comp: Variant                ## StatsComponent
var _class_comp: Variant                ## ClassComponent

# -- Shared state (accessed by states and components via ctx.body) -------------

var _facing_right: bool = true
var mass: float = 70.0


func _build_context() -> void:
	## Build the CharacterContext and inject into all components.
	## Called by subclass after all component nodes are in place.
	var CharCtx := preload("res://scripts/components/character_context.gd")
	_ctx = CharCtx.new()
	_ctx.body = self
	_ctx.input = _input_controller
	_ctx.movement = _movement_fsm
	_ctx.action = _action_fsm
	_ctx.health = _health_comp
	_ctx.stats = _stats_comp
	_ctx.class_comp = _class_comp

	# Inject context into all components that accept it
	for child in get_children():
		if child.has_method("inject_context"):
			child.inject_context(_ctx)

	# Also inject into deeply nested children (FSM states)
	if _movement_fsm:
		_movement_fsm.inject_context(_ctx)
	if _action_fsm:
		_action_fsm.inject_context(_ctx)
	if _class_comp and _class_comp.has_method("inject_context"):
		_class_comp.inject_context(_ctx)


func _start_fsms() -> void:
	## Start FSMs after context injection. Call after _build_context().
	if _movement_fsm:
		_movement_fsm.start()
	if _action_fsm:
		_action_fsm.start()


# -- Config compatibility (delegates to StatsComponent) ------------------------

func cfg(key: String, default_val: float) -> float:
	## Config resolution — delegates to StatsComponent if available.
	## Subclass can override for legacy behavior during migration.
	if _stats_comp:
		return _stats_comp.cfg(key, default_val)
	return default_val


func push_config(provider: Variant) -> void:
	if _stats_comp:
		_stats_comp.push_config(provider)


func remove_config(provider: Variant) -> void:
	if _stats_comp:
		_stats_comp.remove_config(provider)


# -- Health compatibility (delegates to HealthComponent) -----------------------

func take_damage(amount: int, source_index: int = -1) -> void:
	if _health_comp:
		_health_comp.take_damage(amount, source_index)


# -- Entity interface (for @e[...] selectors) ---------------------------------

var entity_id: String = ""
