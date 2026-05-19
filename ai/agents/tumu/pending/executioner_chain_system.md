# Executioner Chain System — In Progress

## Status: PENDING (multi-session)
## Last updated: 2026-03-31

## What's Done (v0.10.31+)

### Core Mechanics
- Ball-and-chain with FABRIK rigid chain physics (chain.gd)
- Shackle attaches to any damageable entity (enemies, dummies, players)
- YEET physics: partially elastic collision on slack→taut transitions
- Absolute mass system: ball=140, player=70, shackle=5, entities have own mass
- Chain split: L2/R2 adjusts how much chain goes to ball vs shackle
- String constraint (max distance only, no compression)
- Every-4th-link collision for chain performance
- Chain cannot pass through walls (segment raycast + point probe)
- Default chain total length = 400 (configurable via `exec_chain_total_len`)

### ShackleEntity (Proper Entity)
- `scripts/systems/shackle_entity.gd` — own config stack, physics tick, chain spawning
- States: HELD, WINDUP, THROWN, STUCK_WALL, STUCK_PLATFORM, STUCK_CEILING, ATTACHED_ENEMY, RETRACTING
- Enemy snap detection with hitbox awareness
- Bounce physics with settlement (settles after 10+ bounces or velocity < 30)
- Chain constraint: rigid leash to player or B-S chain
- YEET elastic collision when attached to enemy and chain goes taut
- Config: mass=5, gravity=600, drag=0.97, chain_elasticity=0.25

### SpikeBallEntity (Proper Entity)
- `scripts/systems/spikeball_entity.gd` — own config stack
- Config: mass=140, gravity=900, damage=35, stun_duration=3, throw_speed=1200

### Chain Config
- `scripts/systems/chain.gd` — own config stack with cfg()/push_config()/remove_config()
- Configurable damping=0.85, gravity=600
- FABRIK always runs (no straight-line shortcut for taut chains)
- Selection glow: pulsing blue polyline behind chain
- Auto-naming: chain_01, chain_02 via static counter

### 3 Chain Modes (Circle toggles)
- **RELEASE (R)**: Both B+S fly as connected pair, player is free
- **HOLD+RELEASE (H&R)**: First throw holds, second releases (entity YEET)
- **HOLD+HOLD (H&H)**: Both throws hold (3-body, player in middle)

### Release Mode Fix
- B-S chain no longer YEETs the player (was falling through to B-P YEET path)
- Fix: `if not is_bs_chain: _exec_try_yeet(chain_dir)`

### AI Player System
- `ai_spawn [x y] class=executioner name=AI mode=release facing=right`
- Generic `_apply_entity_state()` handles semantic keys (mode, facing, throw_mode, standdown)
- `ai_cmd <action> <duration> [aim_x aim_y]` — queues input commands
- Entity selector: `@e[name=...]`, `@e[type=...]`, `@e[group=...]`, `@e[class=...]`

### Config System
- Every physics body has its own config stack (player, ball, shackle, chain, soccer dummy)
- Class defaults loaded from `data/config/class_defaults/*.json`
- User overrides in `user://class_overrides/*.json`
- Modifier blueprints in `data/modifier_blueprints/*.json`
- Class editor with live sliders, revert (↩) and promote (↑) buttons
- RCON: mod/mods/unmod, smod/smods/unsmod

### Verify Monitors
- `verify @e[...] within circle|rect ... until done|timer|{var}` in test scripts
- Candy-stripe visual boundaries
- Breach immediately fails the test

## What's Next

### Immediate TODO
1. **Shackle Config Tuning** — find right default mass/elasticity/gravity for good B-S feel
2. **H&H 3-Body Physics** — player stays between ball and shackle, L2/R2 slides position
3. **Shackle→Entity→Ball YEET Flow** — shackle attaches, ball thrown, chain pulls entity

### Known Issues
- Executioner sprite not importing (needs .import file fix — ctex path)
- Prediction arc doesn't perfectly match reality (damping approximation)
- H&H mode not yet distinct from H&R in behavior
- Chain mode indicator shows correctly but some modes aren't fully wired
- `clearplayers` may leave orphaned chain nodes (mitigated by cleaning chains group)
- Title screen freed instance error: `_on_class_changed` in title_screen.gd:759

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

### Key Files
- `scripts/characters/player_side.gd` — all executioner code
- `scripts/systems/chain.gd` — FABRIK chain physics
- `scripts/systems/shackle_entity.gd` — shackle entity
- `scripts/systems/spikeball_entity.gd` — spikeball entity
- `scripts/systems/monster_config.gd` — ModifierProvider, DictProvider, load_class_defaults
- `scripts/autoload/rcon.gd` — AI player commands, exec_test, tuning
- `scripts/ui/debug_drawer.gd` — config section, class editor
- `data/config/class_defaults/` — 18 class default JSON files
- `data/modifier_blueprints/` — 8 modifier blueprint files
- `data/tests/exec_release_ball_up.json` — automated test
- `data/tests/suites/executioner.json` — test suite
