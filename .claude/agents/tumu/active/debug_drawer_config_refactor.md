# Debug Drawer Config Section Refactor

## Status: ACTIVE — Implemented + Shackle Config Stack + Blueprint Editor
## Created: 2026-03-29
## Updated: 2026-03-29

## What Was Built (This Session)

### 1. Config Section Sub-section Framework (`_cfg_*` prefix)
- 4 collapsible, resizable sub-sections: Game Settings, Entities, Mod Blueprints, Mod Instances
- Same pattern as LE/CT: init, load, save, snap, resize drag/release
- Layout persisted to `user://config_panel_layout.json`
- Blue accent color scheme

### 2. Modifier Blueprint System
- JSON files in `data/modifier_blueprints/` define modifier templates
- Format: `{ "key": ["operation", value], ... }` with `_name`, `_description` metadata
- Operations: multiply, add, set, min, max
- Scanned from both `res://data/modifier_blueprints/` and `user://modifier_blueprints/`

### 3. Interactive Blueprint Editor (in debug drawer)
- Select a blueprint → shows editable modifier rows
- **Draggable sliders** for each modifier value — changes update live instances in real-time
- **Clickable operation badges** — click to cycle multiply→add→set→min→max
- **[Apply]** button — pushes modifier onto selected entity's config stack
- **[Shackle]** button — pushes modifier onto selected entity's shackle config stack
- **[Save]** button — persists edits back to JSON on disk
- Color-coded operations: multiply=purple, add=green, set=orange, min=blue, max=red

### 4. Modifier Instances Panel
- Lists ALL active ModifierProviders across all entities AND shackle config stacks
- Shows modifier name + which entity (+ `[shackle]` suffix for shackle stack)
- [X] remove button routes to correct stack (entity or shackle)
- Filter field for searching

### 5. Shackle Config Stack (Executioner)
- Shackle has its own config stack: `_exec_shackle_config_stack`
- `shackle_cfg(key, default)` — resolves values through the shackle stack
- `push_shackle_config()` / `remove_shackle_config()` — push/pop modifiers
- Default config: `mass=5, chain_elasticity=0.25, gravity=600, drag=0.97`
- Initialized via `_init_shackle_config()` on executioner reset
- `SHACKLE_DEFAULT_CONFIG` dict provides base values

### 6. B-S YEET Physics (Ball ↔ Shackle Elastic Collision)
- **Before**: B-S mode hard-clamped both positions and stripped velocity → unrealistic drag
- **After**: B-S uses same elastic collision (YEET) as B-P and B-E
- The "other end" always provides its own config (mass, elasticity) via its config stack
- With default `m_shackle=5` vs `m_ball=140`: ball loses ~3.4% of relative velocity (barely notices shackle)
- Shackle gets yanked with ~120% of relative velocity
- Configurable via shackle modifiers (e.g., heavy_shackle sets mass=50 → ball loses more)

### 7. RCON Commands Added

#### Entity modifiers
- `mod <blueprint> [entity]` — apply modifier blueprint to entity config stack
- `mods` — list active entity modifiers
- `unmod <name> [entity]` — remove entity modifier by name

#### Shackle modifiers
- `smod <blueprint>` — apply modifier blueprint to shackle config stack
- `smods` — list active shackle modifiers
- `unsmod <name>` — remove shackle modifier by name

### 8. Blueprint JSON Files (`data/modifier_blueprints/`)
| File | Description |
|------|-------------|
| `heavy_ball.json` | 2x mass, +20 dmg, 0.75x throw speed |
| `bouncy_chain.json` | 0.9 elasticity, 0.7x gravity |
| `glass_cannon.json` | 2.5x damage, 0.4x health |
| `tank.json` | 2x health, 0.5x knockback, 0.7x speed |
| `long_chain.json` | 1.8x chain length, 1.2x mass |
| `monster_rage.json` | 1.8x bite/swipe dmg, 0.5x cooldown, 1.3x speed, 0.6x health |
| `heavy_shackle.json` | mass=50, elasticity=0.4 (shackle drags ball more in B-S) |
| `ghost_shackle.json` | mass=0.5, gravity×0.3, elasticity=0.1 (ball unaffected) |

### 9. Test Files
- `data/tests/exec_bs_yeet.json` — B-S RELEASE mode test: spawns AI executioner, cycles to Release, throws ball at 45°, logs B-S YEET impulse values

## Architecture: Unified Flight Physics

The YEET elastic collision is now uniform across all modes:

```
Ball ↔ OtherEnd    OtherEnd provides config via its own stack
─────────────────────────────────────────────────────────
B-P  Player        player.cfg("mass", 70)
B-S  Shackle       player.shackle_cfg("mass", 5)
B-E  Entity        entity_cfg(entity, "mass", 50)
```

Modifiers on OtherEnd change the flight physics. Same math, different config source.

## Files Changed
| File | Changes |
|------|---------|
| `scripts/ui/debug_drawer.gd` | Config sub-section framework, blueprint editor with sliders, modifier instances panel, shackle stack awareness |
| `scripts/characters/player_side.gd` | Shackle config stack, `shackle_cfg()`, `push/remove_shackle_config()`, B-S YEET elastic collision, `EXEC_SHACKLE_MASS` constant |
| `scripts/autoload/rcon.gd` | `mod/mods/unmod`, `smod/smods/unsmod` commands, `_get_all_entities()` helper |
| `data/modifier_blueprints/*.json` | 8 blueprint files |
| `data/tests/exec_bs_yeet.json` | B-S RELEASE mode test |

## What's Next
- Visual verification of blueprint editor sliders in the drawer
- Test blueprint Apply/Shackle/Save buttons
- Add more blueprint files for different artifact scenarios
- Wire entity_cfg for B-E mode to accept shackle attachment modifiers
- Tuning: find the right default shackle mass/elasticity for good game feel
