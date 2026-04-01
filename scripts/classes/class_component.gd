class_name ClassComponent extends Node

## Base class for all character classes (player AND enemy).
## Each class extends this. The Character swaps ClassComponents to change class.
##
## IS-A: Node (code encapsulation, owns child nodes)
## HAS-A: ClassDefinition Resource (data encapsulation, Inspector-editable)

signal attack_performed(data: Dictionary)
signal special_performed(data: Dictionary)
signal class_state_changed(state_name: String)

@export var class_definition: ClassDefinition

var ctx: CharacterContext


func inject_context(c: CharacterContext) -> void:
	## Receive dependencies. Called by Character during setup.
	ctx = c


func on_class_enter() -> void:
	## Called when this class becomes active (equipped / spawned).
	## Override to initialize class-specific state, spawn entities, etc.
	pass


func on_class_exit() -> void:
	## Called when this class is deactivated (class swap / despawn).
	## Override to clean up class-specific state, free entities, etc.
	pass


func inject_movement_states(_movement_fsm: StateMachine) -> void:
	## Override to add class-specific movement states (Airwalk, Fly, Crawl, etc.)
	pass


func inject_action_states(_action_fsm: StateMachine) -> void:
	## Override to add class-specific action states.
	pass


func perform_attack(_intent: Dictionary) -> void:
	## Override to implement class-specific attack logic.
	pass


func perform_special(_intent: Dictionary) -> void:
	## Override to implement class-specific special ability.
	pass


func tick(_delta: float) -> void:
	## Called every physics frame by Character. Class-specific per-frame logic.
	pass


func draw_class(_canvas: CanvasItem) -> void:
	## Override to draw class-specific visuals.
	## Called by CharacterDrawer, which handles base sprite.
	pass
