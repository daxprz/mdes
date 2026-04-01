# Character Refactor — Unified Composition Architecture

## Overview

Refactor `player_side.gd` (9,598 lines, 274 functions, 13 character classes) AND the enemy system into a unified composition-based architecture using Godot best practices: node-based FSMs, component nodes, Resource-based data, and the Strategy pattern.

**Core tenet: All enemies are playable characters.** Every combatant — player classes, the quadruped monster, fairy cake bats, candy golems — shares the same `Character` base. The ONLY difference between "player" and "enemy" is which InputController is attached. Swap it, and a player IS the monster.

**Constraint**: No functionality changes. All 35 existing tests must pass. No RCON interface changes.

## Knowledge Base References

| Pattern | Sources | Application |
|---------|---------|-------------|
| Node-based FSMs | [V3], [V7], [V12], [V13] | Movement FSM, Action FSM, class-specific FSMs |
| Hierarchical/Concurrent FSMs | [V3] | Movement + Action run simultaneously; class FSM nested inside |
| Component-based design | [V2], [V9] | Health, Stats, Input, Drawing as independent child nodes |
| Strategy Pattern via Resources | [V11] | ClassDefinition Resource as blueprint; ClassComponent as instance |
| Resource-based stats + buffs | [V4] | ConfigProvider hierarchy extends Resource for Inspector integration |
| Dependency injection | [V3] | States receive references to character body, not crawling tree |
| Signal-based decoupling | [V2], [V9] | Components communicate via signals, not direct method calls |
| Duck typing contracts | [V9] | `has_method("take_damage")` pattern preserved for entity interactions |
| Anti-pattern: negative scaling | [V1] | Already avoided (using `_facing_right` flag) |
| Anti-pattern: God Object | [V1], [V9] | The entire reason for this refactor |

## Architecture

### Design Principles

1. **Hybrid Node+Resource**: Each class is a **Node** (code encapsulation, owns child nodes) backed by a **Resource** (data encapsulation, Inspector-editable, defines the interface). The Resource is the blueprint; the Node is the instance.

2. **Concurrent FSMs**: Two generic FSMs (Movement, Action) shared by ALL characters. Class-specific FSMs nest inside the class component. The outer FSMs handle universal physics; inner FSMs handle class-unique mechanics.

3. **Every combatant is a Character**: Players, monsters, and enemies all extend the same `Character` base. A quadruped monster IS-A Character with a `MonsterClass` component, just like an executioner IS-A Character with an `ExecutionerClass` component. A fairy cake bat IS-A Character with a `BatClass` component.

4. **InputController is the only player/enemy distinction**: `PlayerInputController` reads gamepads. `AIInputController` reads AI commands. Attach either to any Character. "Play as the monster" = swap its controller.

5. **Inspector-Native Config**: The existing config stack (DictProvider, ModifierProvider) becomes proper Resource subclasses visible in the Inspector.

### Node Hierarchy

```
Character (CharacterBody2D)             ← universal base for ALL combatants
│
├── InputController (Node)              ← reads gamepad/keyboard OR AI commands
│   Swappable: PlayerInputController / AIInputController
│   Exposes: intent_direction, intent_actions[], intent_aim
│   PlayerInputController owns: player_index, device_id
│
├── MovementFSM (Node)                  ← generic, shared by all characters
│   ├── IdleState (Node)
│   ├── RunState (Node)
│   ├── JumpState (Node)
│   ├── FallState (Node)
│   ├── WallSlideState (Node)
│   └── DashState (Node)
│   Classes can INJECT additional states:
│   ├── AirwalkState (Mage)
│   ├── BalloonFloatState (Balloonist)
│   ├── RocketState (Demolitionist)
│   └── DelegateState (Summoner)
│
├── ActionFSM (Node)                    ← generic, shared by all characters
│   ├── ReadyState (Node)               ← can attack/special/block
│   ├── AttackingState (Node)           ← delegates to ClassComponent.perform_attack()
│   ├── ChargingState (Node)            ← charge-release pattern
│   ├── BlockingState (Node)
│   ├── StaggeredState (Node)
│   └── DeadState (Node)
│
├── HealthComponent (Node)              ← HP, damage, death, revive
│   signal health_changed(current, max)
│   signal died()
│   signal revived()
│
├── StatsComponent (Node)               ← config stack, stat resolution
│   var config_stack: Array[ConfigProvider]
│   func cfg(key, default) -> float
│   func push_config(provider)
│   func remove_config(provider)
│
├── ClassComponent (Node)               ← SWAPPABLE, class-specific behavior
│   @export var class_definition: ClassDefinition  ← the Resource
│   Has-a: class-specific FSM (if needed)
│   Has-a: class-specific child nodes (chains, projectiles, etc.)
│   Has-a: class-specific drawing (CanvasItem children)
│   Has-a: class-injected movement states (Fly, Crawl, Leap...)
│
└── CharacterDrawer (CanvasItem)        ← base sprite + shared VFX
    Delegates class-specific drawing to ClassComponent children

Examples of the SAME hierarchy used for different entity types:

  Player Executioner:                  Quadruped Monster:
  Character                            Character
  ├── PlayerInputController            ├── AIInputController (MonsterAI)
  ├── MovementFSM                      ├── MovementFSM
  │   └── Idle,Run,Jump,Fall...        │   └── Idle,Crawl,Leap,Climb...
  ├── ActionFSM                        ├── ActionFSM
  │   └── Ready,Attacking...           │   └── Ready,Biting,Swiping...
  ├── HealthComponent                  ├── HealthComponent
  ├── StatsComponent                   ├── StatsComponent
  └── ExecutionerClass                 └── MonsterClass
      ├── ExecutionerFSM                   ├── PrecogPathfinder
      ├── ShackleEntity                    ├── SkeletonRenderer
      └── SpikeBallEntity                  └── LeapPlanner
```
```

### ClassComponent Variants

Each class extends `ClassComponent`. Simple classes are thin; complex ones own sub-systems:

```
ClassComponent (Node)                   ← base class
├── var ctx: CharacterContext           ← injected, never crawled
├── func inject_context(ctx)            ← receives all dependencies
├── func perform_attack(intent) -> void
├── func perform_special(intent) -> void
├── func on_class_enter() -> void       ← called when class is equipped
├── func on_class_exit() -> void        ← called when class is unequipped
├── func inject_movement_states(fsm)    ← add class-specific movement states
├── func inject_action_states(fsm)      ← add class-specific action states
├── func get_draw_nodes() -> Array      ← CanvasItem children for rendering
├── signal attack_performed(data)
├── signal special_performed(data)

MeleeClass extends ClassComponent
├── Combo tracker
├── Enrage timer
└── ~150 lines

RangerClass extends ClassComponent
├── GrappleFSM (Node)                   ← class-specific FSM
│   ├── IdleState
│   ├── WindupState
│   ├── ThrownState
│   ├── ConnectedState
│   ├── SwingingState
│   ├── TetherState
│   └── RetractingState
├── AimComponent (Node)                 ← archer aim + arc solve
├── ReloadComponent (Node)
├── GrappleDrawer (CanvasItem)          ← rope rendering
└── ~900 lines (from ~1,400 in player_side.gd)

ExecutionerClass extends ClassComponent
├── ExecutionerFSM (Node)               ← class-specific FSM
│   ├── IdleState
│   ├── WindupState
│   ├── BallThrownState
│   ├── ShackleThrownState
│   ├── BothHeldState
│   └── RecallingState
├── ShackleEntity (Node2D)              ← already exists
├── SpikeBallEntity (Node2D)            ← already exists
├── ChainNode (Node2D)                  ← already exists
├── YeetPhysics (RefCounted)            ← extracted elastic collision math
├── ExecutionerDrawer (CanvasItem)      ← chain/ball/shackle rendering
└── ~1,200 lines (from ~2,200 in player_side.gd)

SummonerClass extends ClassComponent
├── DelegateFSM (Node)
├── BuddyController (Node)
├── MarkSystem (Node)
└── ~400 lines

WerewolfClass extends ClassComponent
├── TransformFSM (Node)
│   ├── HumanState
│   └── WolfState
└── ~270 lines

MonsterClass extends ClassComponent     ← the quadruped monster as a "class"
├── PrecogPathfinder (Node)             ← path planning, arc evaluation
├── SkeletonRenderer (CanvasItem)       ← procedural bone animation + _draw()
├── LeapPlanner (Node)                  ← surface detection, leap execution
├── MonsterActionFSM (Node)             ← Idle, Stalking, Leaping, Biting, Swiping
│   Injects movement states: CrawlState, LeapState, ClimbState, CeilingState
└── ~5,000 lines (the existing monster, split across sub-nodes)

### Enemy Classes (same pattern, just different ClassComponents)

BatClass extends ClassComponent         ← fairy_cake_bat.gd
├── Injects: FlyState, SwoopState into MovementFSM
├── BatActionFSM: Circling, Diving, Fleeing
└── ~200 lines

CandyGolemClass extends ClassComponent  ← candy_golem.gd
├── Injects: StompState into MovementFSM
├── GolemActionFSM: Patrolling, Smashing, Stunned
└── ~300 lines

GummyBearClass extends ClassComponent   ← gummy_bear.gd
├── BouncePhysics (Node)
└── ~150 lines

... (each enemy script becomes a ClassComponent)
```

### Resource Hierarchy

```
ConfigProvider (Resource)               ← base, Inspector-visible
├── _name: String
├── func get_value(key) -> Variant
├── func get_modifier(key) -> Variant
│
├── StaticConfig (Resource)             ← was DictProvider
│   @export var data: Dictionary
│
├── ModifierConfig (Resource)           ← was ModifierProvider
│   @export var modifiers: Dictionary   ← {key: [op, value]}
│   Operations: multiply, add, set, min, max
│
├── TimedConfig (Resource)              ← was TimedProvider
│   @export var duration: float
│   @export var base: ConfigProvider
│
└── ClassConfig (Resource)              ← loaded from JSON, merged with user overrides
    @export var class_name: String
    Loads from res://data/config/class_defaults/<class>.json
    Merges user://class_overrides/<class>.json


ClassDefinition (Resource)              ← the "blueprint" for a character class
├── @export var display_name: String
├── @export var sprite_sheet: Texture2D
├── @export var base_stats: StaticConfig
├── @export var class_scene: PackedScene ← the ClassComponent scene to instantiate
├── @export var abilities: Array[AbilityDefinition]
│
│   AbilityDefinition (Resource)
│   ├── @export var name: String
│   ├── @export var cooldown: float
│   ├── @export var mana_cost: float
│   ├── @export var damage_mult: float
│   └── @export var description: String
│
└── Lives at: res://data/classes/<class_name>.tres
```

### Dependency Injection ([V3])

Components and states NEVER crawl the tree. All dependencies are injected explicitly by the Character during `_ready()`. This makes every component reusable on any entity.

**The Context pattern**: Character builds a `CharacterContext` dictionary of typed references during `_ready()` and passes it to every component. Components store only what they need.

```gdscript
## character_context.gd — Typed dependency container
class_name CharacterContext extends RefCounted

var body: CharacterBody2D           # the physics body
var input: InputController          # current input source
var movement: StateMachine          # movement FSM
var action: StateMachine            # action FSM
var health: HealthComponent
var stats: StatsComponent
var class_comp: ClassComponent      # current class (nullable during swap)
var drawer: CharacterDrawer
```

**Character injects context into all children at startup:**
```gdscript
## character.gd
func _ready() -> void:
    var ctx := CharacterContext.new()
    ctx.body = self
    ctx.input = $InputController
    ctx.movement = $MovementFSM
    ctx.action = $ActionFSM
    ctx.health = $HealthComponent
    ctx.stats = $StatsComponent
    ctx.class_comp = $ClassComponent
    ctx.drawer = $CharacterDrawer

    # Inject into every component
    for child in get_children():
        if child.has_method("inject_context"):
            child.inject_context(ctx)
```

**Components declare what they need:**
```gdscript
## health_component.gd
var ctx: CharacterContext

func inject_context(c: CharacterContext) -> void:
    ctx = c

func take_damage(amount: int, source: int = -1) -> void:
    var defense: float = ctx.stats.cfg("defense", 0.0)
    # ... never calls get_parent() or get_node()
```

**States receive context from their FSM, not from the tree:**
```gdscript
## state.gd — Base state
class_name State extends Node

var ctx: CharacterContext    # injected by FSM, not crawled

func enter(_msg: Dictionary = {}) -> void:
    pass

func exit() -> void:
    pass

func physics_update(_delta: float) -> void:
    pass
```

**Cross-FSM communication uses signals, not direct reach:**
```gdscript
## WRONG (tree coupling):
if character.movement_fsm.current_state.name == "WallSlide":
    fsm.transition_to("Ready")

## RIGHT (signal-driven):
# In Character._ready():
ctx.movement.state_changed.connect(_on_movement_state_changed)

# Or: states query context, not siblings:
if ctx.movement.is_in_state("WallSlide"):
    fsm.transition_to("Ready")
```

The `is_in_state()` method on StateMachine is a clean query interface — it doesn't expose the internal state object, just answers a yes/no question. States never hold references to other states.

### FSM Implementation

Following [V3] and [V7], each FSM is a Node with State children:

```gdscript
## state_machine.gd — Generic FSM node
class_name StateMachine extends Node

signal state_changed(old_name: String, new_name: String)

@export var initial_state: State
var current_state: State
var states: Dictionary = {}  # name -> State
var ctx: CharacterContext

func inject_context(c: CharacterContext) -> void:
    ctx = c
    for state in states.values():
        state.ctx = ctx

func _ready() -> void:
    for child in get_children():
        if child is State:
            states[child.name] = child
            child.fsm = self
    if initial_state:
        transition_to(initial_state.name)

func _physics_process(delta: float) -> void:
    if current_state:
        current_state.physics_update(delta)

func transition_to(state_name: String, msg: Dictionary = {}) -> void:
    var old_name: String = current_state.name if current_state else ""
    if current_state:
        current_state.exit()
    current_state = states.get(state_name)
    if current_state:
        current_state.enter(msg)
    state_changed.emit(old_name, state_name)

func is_in_state(state_name: String) -> bool:
    return current_state and current_state.name == state_name

## Add a state at runtime (class injection)
func add_state(state: State) -> void:
    add_child(state)
    states[state.name] = state
    state.fsm = self
    state.ctx = ctx
```

### Concurrent FSM Coordination

Movement and Action FSMs run independently but can influence each other via the context:

```gdscript
## In Character._physics_process():
func _physics_process(delta: float) -> void:
    _input_controller.poll()               # gather intent
    _movement_fsm._physics_process(delta)  # resolve movement
    _action_fsm._physics_process(delta)    # resolve actions
    _class_component.tick(delta)           # class-specific logic
    move_and_slide()                       # apply physics
```

Cross-FSM queries go through the context's clean interface — never reach into sibling internals:
```gdscript
## AttackingState queries movement via context:
func physics_update(delta: float) -> void:
    # Can't attack while wall-sliding — query, don't reach
    if ctx.movement.is_in_state("WallSlide"):
        fsm.transition_to("Ready")
        return
    # ... attack logic using ctx.stats.cfg(), ctx.health, etc.
```

### Drawing Architecture

Each component that needs to draw creates a CanvasItem child:

```gdscript
## ExecutionerDrawer extends Node2D (child of ExecutionerClass)
## Draws chains, ball, shackle, prediction arc
## Uses shared helpers from DrawUtils autoload

func _draw() -> void:
    _draw_chain()
    _draw_ball()
    _draw_shackle()
    _draw_prediction_arc()

func _draw_chain() -> void:
    # Uses DrawUtils.draw_chain_segment() for DRY rendering
    DrawUtils.draw_chain_links(self, chain_points, link_width, color)
```

Shared drawing helpers live in a `DrawUtils` autoload or static class:
```gdscript
## draw_utils.gd — Shared drawing helpers (autoload or static)
class_name DrawUtils

static func draw_chain_links(canvas: CanvasItem, points: PackedVector2Array,
        width: float, color: Color) -> void:
    # Shared chain rendering logic

static func draw_health_bar(canvas: CanvasItem, pos: Vector2,
        current: float, max_val: float, width: float) -> void:
    # Shared health bar rendering

static func draw_aim_arc(canvas: CanvasItem, points: PackedVector2Array,
        color: Color, width: float) -> void:
    # Shared arc rendering
```

### Object Pooling ([V1] enemy spawning efficiency)

VFX particles and projectiles are allocated/freed at high frequency (~50 `ColorRect.new()` call sites, 5-20 particles per attack). An autoload `ObjectPool` recycles short-lived nodes instead of allocating/freeing each frame.

**What gets pooled:**
- VFX particles (blood, sparks, dust, smoke, fire) — highest frequency
- Projectiles (arrows, fireballs, darts, orbs) — medium frequency
- Floating labels (damage numbers, status text) — medium frequency

**What also gets pooled (medium frequency, non-trivial allocation):**
- Chains — created/destroyed on every throw/retract cycle. Each chain allocates a Node2D + script + two PackedVector2Arrays (50-100 Vector2 entries each) + config stack + group membership. In a 4-player game with executioners throwing constantly, this adds up. Pool the entire chain node; on `reset_pooled()`, clear the point arrays (but keep allocated capacity), reset anchors/tension/severed state, strip modifier configs back to base. **Links stay as flat array entries, not individual objects** — PackedVector2Array gives cache-coherent memory for the FABRIK solver, and array capacity naturally stabilizes at the high-water mark across pool cycles. Chain lengths vary (split ratio, config changes), so a recycled chain's arrays may need to grow on reuse, but PackedVector2Array doubles capacity on growth so this cost amortizes to zero after a few cycles.

**What does NOT get pooled:**
- Shackles, spikeballs — persistent entities, created once per class init
- Characters — persistent, never recycled
- FSM states — permanent children of their FSM

**Implementation:**

```gdscript
## object_pool.gd — Autoload singleton
class_name ObjectPool extends Node

## Pool storage: { type_key: [inactive_nodes] }
var _pools: Dictionary = {}

## Acquire a node from the pool, or create a new one.
## The node is RESET before returning — no stale state.
func acquire(type_key: String, factory: Callable) -> Node:
    if _pools.has(type_key) and not _pools[type_key].is_empty():
        var node: Node = _pools[type_key].pop_back()
        node.visible = true
        node.set_physics_process(true)
        return node
    # Pool empty — create new
    return factory.call()

## Return a node to the pool instead of queue_free().
## Caller MUST reset all state before returning.
func release(type_key: String, node: Node) -> void:
    node.visible = false
    node.set_physics_process(false)
    # Detach from parent but keep in tree under the pool
    if node.get_parent() != self:
        node.reparent(self)
    if not _pools.has(type_key):
        _pools[type_key] = []
    _pools[type_key].append(node)

## Hard limit — prevent unbounded growth
const MAX_PER_TYPE := 64

func _trim_pools() -> void:
    for key in _pools:
        while _pools[key].size() > MAX_PER_TYPE:
            _pools[key].pop_back().queue_free()
```

**Lifecycle contract — the Poolable interface:**

Every pooled object must implement `reset_pooled()` to guarantee no stale state:

```gdscript
## poolable.gd — interface contract
## Any node that goes through ObjectPool MUST implement this.

## Called by the pool BEFORE handing the node to a new owner.
## Must reset ALL mutable state to factory defaults.
func reset_pooled() -> void:
    pass  # override in subclass
```

**Example — pooled VFX particle:**

```gdscript
## vfx_particle.gd
extends ColorRect

var vel: Vector2 = Vector2.ZERO
var lifetime: float = 0.0
var _elapsed: float = 0.0

func reset_pooled() -> void:
    vel = Vector2.ZERO
    lifetime = 0.0
    _elapsed = 0.0
    modulate = Color.WHITE
    size = Vector2(4, 4)
    rotation = 0.0
    scale = Vector2.ONE
    visible = true

func _physics_process(delta: float) -> void:
    _elapsed += delta
    position += vel * delta
    vel.y += 600.0 * delta  # gravity
    modulate.a = 1.0 - (_elapsed / lifetime)
    if _elapsed >= lifetime:
        ObjectPool.release("vfx_particle", self)

## Usage in ClassComponent:
func _spawn_blood(pos: Vector2) -> void:
    var p: ColorRect = ObjectPool.acquire("vfx_particle", func():
        var node := ColorRect.new()
        node.set_script(preload("res://scripts/effects/vfx_particle.gd"))
        return node
    )
    p.reset_pooled()
    p.position = pos
    p.vel = Vector2(randf_range(-100, 100), randf_range(-200, -50))
    p.lifetime = 0.5
    p.color = Color(0.8, 0.1, 0.05)
    add_child(p)
```

**Example — pooled chain:**

```gdscript
## In chain.gd — add reset_pooled() to existing script
func reset_pooled() -> void:
    # Clear physics state but KEEP array capacity (avoid reallocation)
    _points.clear()
    _prev_points.clear()
    _point_count = 0
    _link_len = 8.0
    anchor_a = {}
    anchor_b = {}
    target_length = 0.0
    _severed = false
    is_taut = false
    tension_pos_a = Vector2.ZERO
    tension_pos_b = Vector2.ZERO
    _owner_index = -1
    # Strip modifiers back to base config — keep the base provider
    _config_stack = [_base_config] if _base_config else []
    # Selection state
    _selected = false
    visible = true

## In ExecutionerClass — acquire chain from pool instead of new():
func _spawn_chain(a: Dictionary, b: Dictionary, length: float) -> Node2D:
    var chain: Node2D = ObjectPool.acquire("chain", func():
        var node := Node2D.new()
        node.set_script(preload("res://scripts/systems/chain.gd"))
        return node
    )
    chain.reset_pooled()
    chain.setup(a, b, length, ctx.body.player_index)
    ctx.body.get_parent().add_child(chain)
    return chain

## On retract — release instead of queue_free():
func _release_chain(chain: Node2D) -> void:
    if chain and is_instance_valid(chain):
        ObjectPool.release("chain", chain)
```

**Stale state prevention guarantees:**
1. `reset_pooled()` is called on every `acquire()` — caller never gets dirty state
2. `release()` hides and disables physics — no phantom updates while pooled
3. `MAX_PER_TYPE` cap prevents unbounded memory growth
4. Pool nodes live under the ObjectPool autoload — clear parent hierarchy
5. Debug aspect `performance/object_pool` logs pool sizes and acquire/release rates

### Signal Flow

```
InputController
  └─→ intent_changed(direction, actions, aim)

HealthComponent
  ├─→ health_changed(current, max)
  ├─→ damage_taken(amount, source)
  ├─→ died()
  └─→ revived()

StatsComponent
  └─→ stat_changed(key, old_value, new_value)

ClassComponent
  ├─→ attack_performed(attack_data)
  ├─→ special_performed(special_data)
  └─→ class_state_changed(state_name)

MovementFSM
  └─→ state_changed(old_state, new_state)

ActionFSM
  └─→ state_changed(old_state, new_state)
```

### IS-A vs HAS-A

```
IS-A relationships (inheritance):
  Character IS-A CharacterBody2D           ← ONE base for all combatants
  State IS-A Node
  StateMachine IS-A Node
  ConfigProvider IS-A Resource
  StaticConfig IS-A ConfigProvider
  ModifierConfig IS-A ConfigProvider
  ClassDefinition IS-A Resource
  MeleeClass IS-A ClassComponent           ← player classes
  ExecutionerClass IS-A ClassComponent
  RangerClass IS-A ClassComponent
  MonsterClass IS-A ClassComponent         ← "enemy" classes (same hierarchy)
  BatClass IS-A ClassComponent
  CandyGolemClass IS-A ClassComponent
  PlayerInputController IS-A InputController
  AIInputController IS-A InputController

HAS-A relationships (composition):
  Character HAS-A InputController          ← the ONLY player/enemy distinction
  Character HAS-A MovementFSM
  Character HAS-A ActionFSM
  Character HAS-A HealthComponent
  Character HAS-A StatsComponent
  Character HAS-A ClassComponent (swappable)
  ClassComponent HAS-A ClassDefinition (Resource)
  ExecutionerClass HAS-A ExecutionerFSM
  ExecutionerClass HAS-A ShackleEntity
  ExecutionerClass HAS-A SpikeBallEntity
  MonsterClass HAS-A PrecogPathfinder
  MonsterClass HAS-A SkeletonRenderer
  MonsterClass HAS-A LeapPlanner
  RangerClass HAS-A GrappleFSM
  RangerClass HAS-A AimComponent
  StatsComponent HAS-A Array[ConfigProvider]
```

### File Layout

```
scripts/
  characters/
    character.gd                    ← universal base (~500 lines), was player_side.gd
    character_drawer.gd             ← base sprite rendering
    draw_utils.gd                   ← static shared draw helpers

  components/
    input_controller.gd             ← base input interface
    player_input_controller.gd      ← gamepad/keyboard
    ai_input_controller.gd          ← AI command queue
    health_component.gd             ← HP, damage, death, revive
    stats_component.gd              ← config stack wrapper

  fsm/
    state_machine.gd                ← generic FSM node
    state.gd                        ← base state
    movement/
      idle_state.gd
      run_state.gd
      jump_state.gd
      fall_state.gd
      wall_slide_state.gd
      dash_state.gd
    action/
      ready_state.gd
      attacking_state.gd
      charging_state.gd
      blocking_state.gd
      staggered_state.gd
      dead_state.gd

  classes/
    class_component.gd              ← base class component
    melee_class.gd                  ← ~150 lines
    ranged_class.gd                 ← ~200 lines (crossbow only)
    mage_class.gd                   ← ~200 lines
    summoner_class.gd               ← ~400 lines
    rogue_class.gd                  ← ~200 lines
    demolitionist_class.gd          ← ~400 lines
    healer_class.gd                 ← ~200 lines
    tank_class.gd                   ← ~200 lines
    ninja_class.gd                  ← ~100 lines
    balloonist_class.gd             ← ~300 lines
    guitarist_class.gd              ← ~360 lines
    werewolf_class.gd               ← ~270 lines
    executioner/
      executioner_class.gd          ← ~400 lines (orchestration)
      executioner_fsm.gd            ← chain mode states
      yeet_physics.gd               ← elastic collision math
      executioner_drawer.gd         ← chain/ball/shackle rendering
      prediction_arc.gd             ← throw prediction
    ranger/
      grapple_fsm.gd               ← grapple state machine
      aim_component.gd             ← archer aim + arc solve
      reload_component.gd
      grapple_drawer.gd            ← rope rendering
    monster/
      monster_class.gd              ← was quadruped_monster.gd orchestration
      precog_pathfinder.gd          ← path planning + arc evaluation
      skeleton_renderer.gd          ← procedural bone _draw()
      leap_planner.gd               ← surface detection + leap execution
      monster_action_fsm.gd         ← Idle, Stalking, Leaping, Biting, Swiping
    enemies/
      bat_class.gd                  ← was fairy_cake_bat.gd
      candy_golem_class.gd          ← was candy_golem.gd
      gummy_bear_class.gd           ← was gummy_bear.gd
      ... (one file per enemy type)

  resources/
    config_provider.gd              ← Resource base
    static_config.gd                ← was DictProvider
    modifier_config.gd              ← was ModifierProvider
    timed_config.gd                 ← was TimedProvider
    class_definition.gd             ← class blueprint Resource
    ability_definition.gd           ← ability data Resource

data/
  classes/
    melee.tres                      ← ClassDefinition resources (player classes)
    executioner.tres
    ranger.tres
    ...
    monster.tres                    ← ClassDefinition for quadruped monster
    bat.tres                        ← ClassDefinition for fairy cake bat
    candy_golem.tres                ← enemies are just more class definitions
    ...
  config/
    class_defaults/                 ← existing JSON (loaded by StaticConfig)
```

## Implementation Plan

### Phase 0: Tag and Prepare
1. `git tag -a refactor-start -m "Pre-refactor snapshot"`
2. Run full test suite — confirm 35/35 pass
3. Create `scripts/fsm/`, `scripts/components/`, `scripts/classes/`, `scripts/resources/`

### Phase 1: Foundation (~2 sessions)
1. Create `StateMachine` and `State` base classes
2. Create `ConfigProvider` Resource hierarchy (wrap existing DictProvider/ModifierProvider)
3. Create `ClassDefinition` Resource + `ClassComponent` base class
4. Create `HealthComponent`, `StatsComponent`
5. Create `InputController` base + `PlayerInputController` + `AIInputController`
6. **Test**: All existing tests still pass (components exist but aren't wired yet)

### Phase 2: Movement FSM (~1 session)
1. Extract movement logic into states: Idle, Run, Jump, Fall, WallSlide, Dash
2. Wire `MovementFSM` into `CharacterBase`
3. Remove movement code from player_side.gd, delegate to FSM
4. **Test**: All movement-related tests pass

### Phase 3: Action FSM (~1 session)
1. Extract action logic: Ready, Attacking, Charging, Blocking, Staggered, Dead
2. Wire `ActionFSM` into `CharacterBase`
3. **Test**: All combat tests pass

### Phase 4: Extract Simple Classes (~2 sessions)
1. Extract MeleeClass, TankClass, RogueClass, NinjaClass (simplest first)
2. Wire class swapping through `ClassDefinition` resources
3. **Test**: Class-change tests pass

### Phase 5: Extract Complex Classes (~3 sessions)
1. Extract RangerClass + GrappleFSM + AimComponent
2. Extract ExecutionerClass + ExecutionerFSM (leveraging existing ShackleEntity, SpikeBallEntity, Chain)
3. Extract SummonerClass + DelegateFSM
4. Extract remaining classes (Demolitionist, Healer, Guitarist, Werewolf, Balloonist)
5. **Test**: Full executioner suite (7/7), full combat suite (14/14)

### Phase 6: Enemy Migration (~2 sessions)
1. Wrap `quadruped_monster.gd` as `MonsterClass` extending ClassComponent
2. Move monster's existing controller pattern into the unified InputController system
3. Migrate simple enemies: bat, gummy bear, candy corn → ClassComponent pattern
4. Migrate complex enemies: candy golem, minibosses
5. Create ClassDefinition `.tres` for each enemy type
6. **Test**: All chained/combat/leaping/scaling suites pass (monster behavior unchanged)

### Phase 7: Drawing Extraction (~1 session)
1. Create `DrawUtils` with shared helpers
2. Move class-specific drawing into ClassComponent CanvasItem children
3. Move base sprite rendering to `CharacterDrawer`
4. **Test**: Visual verification + all tests pass

### Phase 8: Cleanup (~1 session)
1. Delete `player_side.gd` (the original 9,598-line file)
2. Delete individual enemy scripts (now ClassComponents)
3. Update CLAUDE.md, design docs
4. Create `.tres` files for all ClassDefinitions
5. Final full test gate run
6. **Test**: 35/35 green
7. "Play as monster" smoke test — swap controller, verify it works

## Debug Aspects

Existing debug aspects preserved. New ones added:

| Aspect | Description |
|--------|-------------|
| `character/movement_fsm` | Current movement state + transitions |
| `character/action_fsm` | Current action state + transitions |
| `character/class_switch` | Class component swap events |
| `character/stats_resolve` | Config stack resolution trace |
| `character/input_intent` | Raw input → intent mapping |

## Test Scenarios

**No new tests needed for refactoring** — the existing 35 tests ARE the verification. The RCON interface is the contract:
- `ai_spawn`, `ai_cmd`, `spawn`, `kick`, `query` — all unchanged
- Entity selectors (`@e[name=...]`) — unchanged
- Verify monitors — unchanged
- Debug logging aspects — preserved

After refactoring, run `/test-gate` to confirm all 5 gate suites pass.

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Regression in class-specific behavior | Each class extracted one at a time, full suite run after each |
| Performance regression from node overhead | Profile before/after; FSM node overhead is negligible per [V12] |
| RCON interface breakage | RCON routes to the same methods; only internal structure changes |
| Drawing order changes | CanvasItem z_index preserves layer ordering |
| Config stack behavior change | ConfigProvider Resources wrap existing logic 1:1, same math |
