# Config Panel Redesign

## Status: DESIGN
## Created: 2026-03-30

## Overview

Restructure the Config tab (gear icon) from 4 sub-sections into 10 interconnected sub-sections with cross-selection, stat breakdowns, and modifier management.

## Current State (v0.10.35)

4 sub-sections:
1. **Game Settings** — toggles (multiple_players_same_class)
2. **Entities** — filter, entity list, config sliders for selected entity
3. **Mod Blueprints** — blueprint list, editor with sliders
4. **Mod Instances** — active modifiers across all entities

Problems:
- No class-level defaults editing
- No stat breakdown (can't see how a value was calculated)
- No visibility into which modifiers affect which stats
- Entity sliders mix base config with modifier effects
- Blueprints and entity modifiers are disconnected

## New Layout (10 Sub-sections)

```
┌─────────────────────────────┐
│ Game Settings               │  Toggles (unchanged)
├─────────────────────────────┤
│ Classes                     │  List of character classes
├─────────────────────────────┤
│ Class (<class_name>)        │  Base stat editor for selected class
├─────────────────────────────┤
│ Entities                    │  Live entities in scene — click to select
├─────────────────────────────┤
│ Entity Mods (<entity>)      │  Modifiers applied to selected entity
├─────────────────────────────┤
│ Entity Stats (<entity>)     │  Stat table: Name / Base / Mods / Curr
├─────────────────────────────┤
│ Calculations (<entity:stat>)│  How a selected stat is computed
├─────────────────────────────┤
│ Modifiers                   │  Modifier blueprint list
├─────────────────────────────┤
│ Modifier (<mod_name>)       │  Blueprint editor (sliders, operations)
├─────────────────────────────┤
│ Modified Entities (<mod>)   │  Entities with this modifier applied
└─────────────────────────────┘
```

## Sub-section Details

### 1. Game Settings
- Unchanged from current
- Toggles like `multiple_players_same_class`

### 2. Classes
- List of all character classes: Melee, Ranged, Mage, Summoner, Rogue, Demolitionist, Healer, Tank, Ninja, Balloonist, Guitarist, Werewolf, Executioner
- Click to select → populates **Class** editor below
- Shows class color accent and player count per class

### 3. Class (<class_name>)
- Base stat editor for the selected class
- Loads from:
  - **Default file**: `data/config/class_defaults/<class_name>.json` (checked into repo)
  - **User overrides**: `user://class_overrides/<class_name>.json` (local tuning)
- Any setting different from the default file shows highlighted
- **[Promote]** button per modified row — copies the user override value into the default file
- Sliders for all class stats (physics, combat, health, class-specific)
- Changes apply immediately to all entities of that class

### 4. Entities
- Live entities in scene — click to select
- Shows: `#  name  type  [Tune] [Mod+]`
- Title bar shows entity count (no redundant "Entities (7)" inside the list)
- Filter field for search
- Selected entity highlights green

### 5. Entity Mods (<entity_name>)
- Lists all modifiers (ModifierProviders) on the selected entity's config stack
- Each row: modifier name, source (blueprint name or "slider_edits"), operation count
- Click to select a modifier → highlights in **Modifier** editor
- [X] remove button per modifier
- Also shows shackle stack modifiers tagged `[shackle]` for Executioner

### 6. Entity Stats (<entity_name>)
Table columns:

| Stat | Base | Mods | Curr |
|------|------|------|------|
| exec_ball_mass | 140.0 | 2 | 280.0 |
| exec_ball_damage | 35 | 1 | 55 |
| speed | 110.0 | 0 | 110.0 |

- **Stat**: config key name
- **Base**: value from the bottom of the config stack (class defaults / JSON)
- **Mods**: count of ModifierProviders that have an entry for this key
- **Curr**: final resolved value from `cfg(key, default)`
- Click a row → populates **Calculations** below
- Rows where Curr != Base are highlighted (modified)

### 7. Calculations (<entity_name>:<stat>)
Shows the full computation chain for the selected stat:

| Step | Source | Operation | Value | Result |
|------|--------|-----------|-------|--------|
| base | class_defaults | — | — | 140.0 |
| 1 | heavy_ball | multiply | 2.0 | 280.0 |
| 2 | slider_edits | — | — | 280.0 |
| final | — | — | — | **280.0** |

- Walks the config stack bottom-to-top
- Shows which provider set the base value
- Shows each ModifierProvider's operation and its effect
- Highlights the final result

### 8. Modifiers
- List of modifier blueprints from `data/modifier_blueprints/` and `user://modifier_blueprints/`
- Filter field
- Click to select → populates **Modifier** editor and **Modified Entities**
- Shows modifier count per blueprint

### 9. Modifier (<mod_name>)
- Interactive editor for the selected blueprint
- Each modifier key: name, operation badge (clickable to cycle), draggable value slider
- **[Apply]** button — push onto selected entity's config stack
- **[Shackle]** button — push onto shackle config stack (Executioner only)
- **[Save]** button — persist to user://modifier_blueprints/
- Changes update live instances in real-time

### 10. Modified Entities (<mod_name>)
- Lists all entities that have the selected modifier applied
- Each row: entity name, entity type
- Click an entity → triggers cross-selection:
  1. Entity becomes selected in **Entities** (sub 4)
  2. **Entity Mods** (sub 5) populates and selects the clicked modifier
  3. **Entity Stats** (sub 6) populates
  4. **Calculations** (sub 7) clears (no stat selected yet)

## Cross-selection Flow

```
User clicks entity in Entities list
  → Entity Mods populates with entity's modifiers
  → Entity Stats populates with entity's stat table
  → Calculations clears

User clicks stat in Entity Stats
  → Calculations shows computation chain for that stat

User clicks modifier in Entity Mods
  → Modifier editor loads that blueprint (if from a blueprint)
  → Modified Entities shows all entities with that modifier

User clicks entity in Modified Entities
  → Selects entity in Entities list
  → Entity Mods populates and selects the modifier
  → Entity Stats populates

User clicks blueprint in Modifiers
  → Modifier editor loads the blueprint
  → Modified Entities shows all entities with instances of that blueprint
```

## Class Defaults Architecture

### File locations
- **Default**: `data/config/class_defaults/<class_name>.json` — checked into repo, shared
- **User override**: `user://class_overrides/<class_name>.json` — local tuning, not committed

### Load order
1. Load default file → base values
2. Load user override file → merge on top (overrides matching keys)
3. Result is the class base config, pushed as the bottom DictProvider on every entity of that class

### Promote flow
- User tunes a value via slider → saved to user override file
- Click **[Promote]** → copies that value from user override into the default file
- Default file is in `res://` (project directory) — editable in dev, read-only in export
- After promote, the override is removed (value is now the default)

### Initial migration
- Current hardcoded `CLASS_STATS` in PlayerManager and `_get_player_config_default` in debug_drawer → export to JSON files
- Current `monster_defaults.json` → becomes the monster class default
- Run once to generate initial files, then delete the hardcoded values

## State Variables

New state needed in debug_drawer.gd:
```gdscript
# Class selection
var _cfg_selected_class: int = -1          # CharacterClass enum value
var _cfg_class_scroll_offset: int = 0

# Entity selection (existing, renamed for clarity)
# _get_selected_entity() already exists

# Entity mods selection
var _cfg_selected_entity_mod_idx: int = -1  # Index into entity's config stack

# Stat selection
var _cfg_selected_stat: String = ""         # Config key selected in Entity Stats

# Modifier selection (existing: _cfg_selected_blueprint)
# Modified entities uses the same selected blueprint
```

## Implementation Plan

### Phase 1: Class defaults JSON files
1. Create `data/config/class_defaults/` directory
2. Export current CLASS_STATS + _get_player_config_default to JSON files
3. Load class defaults from JSON at startup
4. Verify existing behavior unchanged

### Phase 2: New sub-sections (structure only)
1. Replace 4 sub-sections with 10
2. Stub drawing functions for each
3. Wire click/scroll/resize handlers
4. Layout persistence

### Phase 3: Class editor
1. Classes list with selection
2. Class editor with sliders
3. User override save/load
4. Promote button

### Phase 4: Entity Stats table
1. Build stat table from entity's config stack
2. Base/Mods/Curr columns
3. Click to select stat

### Phase 5: Calculations breakdown
1. Walk config stack for selected stat
2. Show each provider's contribution
3. Table rendering

### Phase 6: Cross-selection wiring
1. Modified Entities → Entity selection
2. Entity Mods → Modifier editor
3. Stat selection → Calculations

### Phase 7: Spikeball config stack
1. Give spikeball_marker.gd its own config stack (like shackle_entity.gd)
2. Move `exec_ball_*` keys from player stack to ball stack, drop prefix
3. Update all `cfg("exec_ball_*")` calls to query ball entity instead
4. Ball modifiers go on the ball, not the player

### Phase 8: Chain config entity
1. Create chain config as a queryable entity (or sub-config on player)
2. Move `exec_chain_*` keys to their own namespace
3. Chain damping/gravity read from chain config, not player cfg()

### Phase 9: Migration cleanup
1. Remove hardcoded CLASS_STATS defaults
2. Remove _get_player_config_default hardcoded values
3. All values load from JSON files
4. `exec_ball_*` prefix removed from ball keys
5. `exec_chain_*` prefix removed from chain keys

## Resolved Questions

1. **Monster config** — yes, gets the same class defaults treatment. `monster_defaults.json` becomes the monster class default file, with a user override layer on top.

2. **Shackle and spikeball** — separate classes in the Classes list. Each has its own config stack and default file:

| Class | Config Stack | Default File | Keys |
|-------|-------------|--------------|------|
| Melee | player._config_stack | `class_defaults/melee.json` | speed, gravity, health, melee_* |
| Executioner | player._config_stack | `class_defaults/executioner.json` | speed, gravity, health, exec_chain_* |
| Spike Ball | spikeball._config_stack (NEW) | `class_defaults/spikeball.json` | mass, gravity, damage, spin, stun, throw_speed |
| Shackle | shackle._config_stack | `class_defaults/shackle.json` | mass, gravity, drag, elasticity |
| Chain | (set from player cfg) | `class_defaults/chain.json` | damping, gravity, total_len |
| Monster | monster._config_stack | `class_defaults/monster.json` (was monster_defaults.json) | all monster keys |

   The spikeball needs its own config stack (like the shackle already has) instead of proxying to the player. Ball keys (`exec_ball_*`) move from the player stack to the ball stack, dropping the `exec_ball_` prefix.

3. **Calculations caching** — cache is rebuilt on every config change (modifier push/remove, slider drag, class default edit). NOT every frame. Display from cache.
