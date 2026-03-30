# Executioner Chain System — In Progress

## Status: PENDING (multi-session)
## Last updated: 2026-03-29

## What's Done (v0.10.31)

### Core Mechanics
- Ball-and-chain with FABRIK rigid chain physics (chain.gd)
- Shackle attaches to any damageable entity (enemies, dummies, players)
- YEET physics: partially elastic collision on slack→taut transitions
- Absolute mass system: ball=140, player=70, shackle=5, entities have own mass
- Chain split: L2/R2 adjusts how much chain goes to ball vs shackle
- String constraint (max distance only, no compression)
- Every-4th-link collision for chain performance
- Chain cannot pass through walls (segment raycast + point probe)

### 3 Chain Modes (Circle toggles)
- **RELEASE (R)**: Both B+S fly as connected pair, player is free
- **HOLD+RELEASE (H&R)**: First throw holds, second releases (entity YEET)
- **HOLD+HOLD (H&H)**: Both throws hold (3-body, player in middle)

### Current State of Each Mode
- **R:B** — Ball+shackle release works. Ball sticks to surfaces, shackle trails and bounces. No player YEET. No duplicate B-S on re-throw.
- **R:S** — Shackle+ball release. Structurally implemented but not tested.
- **H&R** — Hold first, release second. Partially implemented. Entity YEET works when shackle attached to enemy and ball thrown.
- **H&H** — Always hold. Current default behavior. Works but 3-body YEET (player between ball and shackle) not yet implemented.

### AI Player System
- `ai_spawn [x y]` — spawns joystick-free Executioner
- `ai_cmd <action> <duration> [aim_x aim_y]` — queues input commands
- `exec_test <angle> <hold> [x y]` — full automated throw test
- `reset` — resets any player to default state
- Test: `data/tests/exec_release_ball_up.json`
- Suite: `data/tests/suites/executioner.json`

### Tuning Popup
- `et` toggles live slider panel (top-right)
- 9 configurable settings: ball mass, elasticity, throw speed, gravity, chain length, etc.
- Uses DictProvider on player's config stack
- [Tune] button in debug drawer entity list

### Prediction Arc
- Two-body coupled simulation (ball + player)
- Probability cone: optimistic (no damping) + pessimistic (0.95 damping)
- Simulates floor collision, chain constraint, elastic collisions
- Ball cone widens, then narrows after chain taut
- Shackle has separate narrow arc preview

### Entity Config System
- `entity_cfg(entity, key, default)` — queries any entity for config values
- Routes through entity's `cfg()` if it has config stack, falls back to properties
- ModifierProvider supports multiply, add, set, min, max operations
- Foundation for artifact system

### Shackle Config Stack (NEW)
- Shackle has own config stack: `_exec_shackle_config_stack` with `shackle_cfg(key, default)`
- Default: mass=5, chain_elasticity=0.25, gravity=600, drag=0.97
- `push_shackle_config()` / `remove_shackle_config()` for modifiers
- B-S YEET uses same elastic collision as B-P/B-E, querying shackle config for mass/elasticity
- RCON: `smod/smods/unsmod` for shackle modifiers
- Debug drawer: Mod Instances panel shows shackle modifiers with `[shackle]` suffix

### Modifier Blueprint System (NEW)
- JSON files in `data/modifier_blueprints/` (8 blueprints: heavy_ball, bouncy_chain, glass_cannon, tank, long_chain, monster_rage, heavy_shackle, ghost_shackle)
- Debug drawer: interactive blueprint editor with draggable sliders, operation cycling, Apply/Shackle/Save buttons
- Live editing: slider changes update active modifier instances in real-time
- RCON: `mod/mods/unmod` for entity modifiers

## What's Next

### Immediate TODO
1. ~~**Debug Drawer Config Section Refactor**~~ ✅ DONE — 4 sub-sections, blueprint editor with sliders
2. ~~**Modifier Blueprint System**~~ ✅ DONE — JSON files, live editing, Apply/Shackle/Save
3. ~~**B-S YEET Physics**~~ ✅ DONE — Shackle has own config stack, elastic collision same as B-P/B-E
4. **Shackle Config Tuning** — find right default mass/elasticity/gravity for good B-S feel

5. **H&H 3-Body Physics**
   - Player stays connected between ball and shackle
   - L2/R2 slides player position along chain
   - YEET calculations for 3 bodies (one YEET per tick max)
   - If two chain segments go taut same frame, defer second to next tick

4. **Shackle→Entity→Ball YEET Flow**
   - Shackle attaches to entity
   - Ball thrown (RELEASE mode): chain = entity↔ball
   - Ball momentum YEETs entity
   - First recall: ball returns to player
   - Second recall: shackle detaches from entity

### Conventions
```
B = Ball, S = Shackle, P = Player, E = Entity
- = chained to
R = Release, H&R = Hold & Release, H&H = Hold & Hold
R:B = Release while using Ball
B-S = Ball released, connected by chain to Shackle
B-P-S = Ball → Player → Shackle (player in middle)
S-E-B = Shackle on Entity, chain to Ball
```

### Known Issues
- Executioner sprite not importing (needs .import file fix — ctex path)
- Prediction arc doesn't perfectly match reality (damping approximation)
- H&H mode not yet distinct from H&R in behavior
- Chain mode indicator shows correctly but some modes aren't fully wired
- `clearplayers` may leave orphaned chain nodes (mitigated by cleaning chains group)

### Key Files
- `scripts/characters/player_side.gd` — all executioner code (lines ~7235-8700)
- `scripts/systems/chain.gd` — FABRIK chain physics
- `scripts/systems/monster_config.gd` — ModifierProvider, DictProvider
- `scripts/systems/entity_effects.gd` — timed effects (stun, slow, etc.)
- `scripts/autoload/rcon.gd` — AI player commands, exec_test, tuning
- `scripts/ui/debug_drawer.gd` — config section, tuning popup
- `data/tests/exec_release_ball_up.json` — automated test
- `data/tests/suites/executioner.json` — test suite

### Config Keys (all go through cfg())
| Key | Default | What |
|-----|---------|------|
| exec_ball_mass | 140 | Ball absolute mass |
| exec_shackle_mass | 5 | Shackle mass — nearly weightless in B-S mode |
| exec_chain_elasticity | 0.25 | Elastic collision bounciness |
| exec_ball_throw_speed | 1200 | Min throw speed |
| exec_ball_max_throw_speed | 6000 | Max throw speed |
| exec_ball_gravity | 900 | Ball gravity |
| exec_chain_total_len | 600 | Total chain length (ball+shackle) |
| exec_chain_adjust_speed | 0.5 | L2/R2 split adjustment speed |

#### Shackle Config Keys (via shackle_cfg())
| Key | Default | What |
|-----|---------|------|
| mass | 5 | Shackle mass — nearly weightless in B-S mode |
| chain_elasticity | 0.25 | Elastic collision bounciness for B-S YEET |
| gravity | 600 | Shackle gravity when thrown |
| drag | 0.97 | Shackle air drag |
| exec_ball_stun_duration | 3.0 | Enemy stun on ball hit |
| exec_ball_damage | 35 | Ball impact damage |
