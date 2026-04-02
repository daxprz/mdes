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


# -- Shared physics constants --------------------------------------------------
# Subclasses can override via cfg() or direct assignment.

const DEFAULT_GRAVITY := 900.0
const DEFAULT_JUMP_VELOCITY := -550.0
const DEFAULT_MAX_FALL_SPEED := 600.0
const DEFAULT_WALL_SLIDE_SPEED := 60.0


# -- Shared state (accessed by components and class scripts) -------------------

var _is_dead: bool = false
var _is_wall_sliding: bool = false


# -- Virtual methods for shared systems ----------------------------------------
# These provide default behavior that subclasses and ClassComponents can use.
# player_side.gd overrides most of these with class-specific logic.

func apply_gravity(delta: float) -> void:
	## Default gravity — simple downward acceleration. Override for airwalk, float, etc.
	if not is_on_floor():
		var grav: float = cfg("gravity", DEFAULT_GRAVITY)
		velocity.y += grav * delta
		velocity.y = minf(velocity.y, DEFAULT_MAX_FALL_SPEED)


func apply_knockback(force: Vector2) -> void:
	## Apply a knockback impulse. Override for immunity, resistance, etc.
	velocity += force


func get_aim_direction() -> Vector2:
	## Default aim direction — facing direction. Override for analog stick, mouse, etc.
	return Vector2(1.0 if _facing_right else -1.0, 0.0)


# -- Entity interface (for @e[...] selectors) ---------------------------------

var entity_id: String = ""
