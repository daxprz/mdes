# Debug Drawer Config Section Refactor

## Status: ACTIVE — Revert/Promote Wired
## Created: 2026-03-29
## Updated: 2026-03-31

## What Was Built

### 1. Config Section Sub-section Framework (`_cfg_*` prefix)
- 9 collapsible, resizable sub-sections: Classes, Class Editor, Entities, Entity Mods, Entity Stats, Calculations, Modifiers, Modifier Editor, Modified Entities
- Same pattern as LE/CT: init, load, save, snap, resize drag/release
- Layout persisted to `user://config_panel_layout.json`
- Blue accent color scheme

### 2. Class Defaults System
- JSON files in `data/config/class_defaults/` (18 classes: melee, ranged, mage, executioner, spikeball, shackle, chain, soccer_dummy, monster, etc.)
- User overrides in `user://class_overrides/` merged on top
- `MCP.load_class_defaults(class_name)` loads + merges configs

### 3. Class Editor with Live Sliders
- Draggable sliders for each config key
- Orange highlight for modified values (accent bar + fill color change)
- Original value shown in parentheses above current
- Scroll support for classes with many keys

### 4. Revert (↩) and Promote (↑) Buttons — WIRED
- **Revert**: Resets key to original default, saves override, updates live entities
- **Promote**: Writes current value to `res://data/config/class_defaults/<class>.json`, removes from user override, updates original cache
- Hover detection: highlights button + shows tooltip under mouse
- Click handling: routes through `_cfg_revert_key()` / `_cfg_promote_key()`
- Buttons only appear on rows where value differs from default

### 5. Entity Stats Table
- Shows Stat/Base/Mods/Curr columns for selected entity
- Click to select stat for Calculations breakdown

### 6. Modifier Blueprint System
- JSON files in `data/modifier_blueprints/` define modifier templates
- Format: `{ "key": ["operation", value], ... }` with `_name`, `_description` metadata
- Operations: multiply, add, set, min, max
- Interactive blueprint editor with draggable sliders, operation cycling
- Apply/Shackle/Save buttons
- Live editing: slider changes update active modifier instances in real-time

### 7. Modified Entities Panel
- Lists ALL active ModifierProviders across all entities AND shackle config stacks
- Shows modifier name + which entity (+ `[shackle]` suffix for shackle stack)
- [X] remove button routes to correct stack
- Filter field for searching

### 8. TPS Metrics in Aspect Tree
- Visual and textual ticks-per-second displayed per debug aspect
- `vis()` lambda API for conditional debug draw with tick counting

### 9. Verify Monitors with Candy-Stripe Boundaries
- `verify @e[...] within circle|rect ... until done|timer|{var}` test statements
- Candy-stripe annular rendering (45° world-space lines)
- Background boundary checks during test execution

## Files Changed
| File | Changes |
|------|---------|
| `scripts/ui/debug_drawer.gd` | 9 config sub-sections, class editor with sliders + revert/promote, blueprint editor, modifier instances, entity stats, tooltip system |
| `scripts/characters/player_side.gd` | ShackleEntity, SpikeBallEntity, class config loading, entity state system |
| `scripts/systems/shackle_entity.gd` | Shackle as proper entity with config stack |
| `scripts/systems/spikeball_entity.gd` | Spikeball as proper entity with config stack |
| `scripts/systems/chain.gd` | Config stack, configurable damping/gravity |
| `scripts/systems/monster_config.gd` | `load_class_defaults()` utility |
| `scripts/autoload/rcon.gd` | mod/smod/unmod/unsmod commands, ai_spawn with class/state |
| `scripts/autoload/debug_overlay.gd` | TPS counters, vis() API |
| `data/config/class_defaults/*.json` | 18 class default JSON files |
| `data/modifier_blueprints/*.json` | 8 modifier blueprint files |

## What's Next
- Visual verification: test revert/promote buttons in running game
- Phase 8: Migration cleanup — remove hardcoded defaults from code, all go through cfg()
- Calculations breakdown sub-section (shows full config resolution chain)
