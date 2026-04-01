class_name CharacterContext extends RefCounted

## Typed dependency container — built by Character, injected into all components.
## Components store only what they need. Never crawl the tree.

var body: CharacterBody2D           ## The physics body (the Character node itself)
var input: Node                     ## Current InputController (Player or AI)
var movement: Node                  ## Movement StateMachine
var action: Node                    ## Action StateMachine
var health: Node                    ## HealthComponent
var stats: Node                     ## StatsComponent
var class_comp: Node                ## Current ClassComponent (nullable during swap)
var drawer: CanvasItem              ## CharacterDrawer
