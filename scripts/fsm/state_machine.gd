class_name StateMachine extends Node

## Generic FSM node. States are child nodes extending State.
## Supports runtime state injection (classes add movement/action states).
## Dependencies injected via CharacterContext — never uses owner or get_parent().

signal state_changed(old_name: String, new_name: String)

@export var initial_state: State

var current_state: State
var states: Dictionary = {}          ## name -> State
var ctx: CharacterContext


func inject_context(c: CharacterContext) -> void:
	## Receive dependencies from Character. Propagates to all states.
	ctx = c
	for state: State in states.values():
		state.ctx = ctx


func _ready() -> void:
	## Discover child states and register them.
	for child in get_children():
		if child is State:
			_register_state(child)
	# Don't auto-transition here — wait for inject_context + explicit start


func start() -> void:
	## Begin the FSM. Call after inject_context().
	if initial_state and not current_state:
		transition_to(initial_state.name)


func _physics_process(delta: float) -> void:
	if current_state:
		current_state.physics_update(delta)


func transition_to(state_name: String, msg: Dictionary = {}) -> void:
	## Transition to a named state. Calls exit() on old, enter() on new.
	if not states.has(state_name):
		push_warning("StateMachine: no state '%s' in %s" % [state_name, name])
		return
	var old_name: String = current_state.name if current_state else ""
	if current_state:
		current_state.exit()
	current_state = states[state_name]
	current_state.enter(msg)
	state_changed.emit(old_name, state_name)
	DebugOverlay.log("character/%s" % name, ctx.body if ctx else null,
		"%s → %s", [old_name, state_name])


func is_in_state(state_name: String) -> bool:
	## Clean query interface — does not expose internal state object.
	return current_state != null and current_state.name == state_name


func add_state(state: State) -> void:
	## Add a state at runtime (class injection). Auto-injects context.
	add_child(state)
	_register_state(state)


func remove_state(state_name: String) -> void:
	## Remove a runtime-injected state. Cannot remove the current state.
	if current_state and current_state.name == state_name:
		push_warning("StateMachine: cannot remove active state '%s'" % state_name)
		return
	if states.has(state_name):
		var state: State = states[state_name]
		states.erase(state_name)
		state.queue_free()


func _register_state(state: State) -> void:
	states[state.name] = state
	state.fsm = self
	if ctx:
		state.ctx = ctx
