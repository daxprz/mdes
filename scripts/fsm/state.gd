class_name State extends Node

## Base state for all FSMs. Dependencies injected via ctx — never crawl the tree.
## Subclass and override enter(), exit(), physics_update().

var fsm: Node                        ## The StateMachine that owns this state
var ctx: CharacterContext             ## Injected by FSM — typed access to all components


func enter(_msg: Dictionary = {}) -> void:
	## Called when this state becomes active.
	pass


func exit() -> void:
	## Called when this state is deactivated.
	pass


func physics_update(_delta: float) -> void:
	## Called every physics frame while this state is active.
	pass


func handle_input(_event: InputEvent) -> void:
	## Optional: called for unhandled input while this state is active.
	pass
