# EPIC: Debug Overlay System

## Overview

Replace the current ad-hoc debug rendering (Ctrl+D toggle, `debug_draw_lite`, `debug_draw_enabled`, scattered print statements) with a unified, configurable debug overlay system. All debug visuals and logging route through a central registry of **aspects** organized in a 2-level tree. A slide-out drawer (left edge) provides in-game configuration. Multiple **observers** (human, tests, scripts) can independently request debug output, each specifying whether they want VISUAL, TEXTUAL, or both.

## Key Concepts

### Aspect Tree

A 2-level hierarchy of debug concerns. Each leaf node is a toggleable debug output.

```
platform_detection/
  ├── platform_indicators
  ├── ball_drop_buckets
  ├── ball_drop_final_spots
  └── edge_adjustment_indicators
leap_attack/
  ├── spots_considered
  ├── rays_cast
  └── attack_zone_dots
pathing/
  ├── waypoints
  ├── way_platform
  ├── walk_run_path
  ├── platform_leap_path
  └── leap_attack_choice
testing/
  └── etz_daz_zones
body_mechanics/
  ├── collision_shapes
  ├── ik_plant_marks
  ├── spine_debug
  ├── neck_skull
  ├── jaw
  ├── tail_segments
  ├── leg_debug
  ├── origin_marker
  ├── floor_line
  └── body_collider
splay_poses/
  ├── pre_physics_pose
  ├── post_physics_pose
  ├── chain_points
  └── anchor_points
state_info/
  ├── state_text_panel
  ├── selection_indicator
  └── ik_metrics
precog/
  ├── platform_list
  ├── graph_edges
  ├── current_path
  └── attach_points
chain/
  ├── tether_arc
  └── chain_barrier
```

This list is extensible — new aspects are registered in code and automatically appear in the drawer.

### Observer Model

Each aspect tracks **who** wants it on and **what** they want:

```
aspect "pathing/waypoints":
  observers:
    human → VISUAL
    test:leap_floor_to_P1 → TEXTUAL(log)
  actualized → VISUAL + TEXTUAL(log)
```

**Observer types:**
- `human` — persisted to `user://debug_profile.json`, configured via drawer UI, saved with Ctrl+S
- `test:<name>` — transient, loaded from test JSON `"debug"` block, cleared when test ends
- `script:<id>` — transient, set programmatically via RCON or GDScript

**Resolution:** For each aspect, the actualized state is the **union** of all observer requests. If ANY observer wants VISUAL → render it. If ANY observer wants TEXTUAL(log|console|both) → log it accordingly.

### Textual Output Modes

Each textual request specifies a destination:
- `log` — Godot print() output (captured by shell scripts, RCON polling)
- `console` — in-game console only
- `both` — both log and console

### Entity Filtering

Global filters that apply across all aspects:
- **By type:** toggle per entity type (monster, dummy, attacker). Checked types are included.
- **By entity ID:** wildcard string match (e.g., `monster_*`, `splay_2`, `*`). Empty = all.

When an entity filter is active, debug output only fires for entities matching the filter. Filter state is part of the human observer's persisted profile.

## UI: Debug Drawer

### Activation
- `Ctrl+D` — toggles the drawer (replaces current debug mode toggle)
- Slides in from the **left edge** of the screen
- Width calculated from content (enough for tree + checkboxes + labels)
- `Ctrl+S` while drawer is open — saves human observer state to disk
- `Ctrl+D` again — slides drawer out, debug settings remain active

### Layout (top to bottom)

```
┌─────────────────────────────┐
│ [Filter: ________________] │  ← aspect search, hides non-matches
│                             │
│ Entity Filter:              │
│  Types: [x]monster [x]dummy │
│  ID:    [monster_*________] │
│                             │
│ ─── Global ──────────── [x] │  ← master on/off (does NOT toggle
│                             │     individual aspects, just gates
│                             │     all actualized output)
│                             │
│ ▼ platform_detection    V T │  ← V=visual, T=textual columns
│    platform_indicators  ☑ ☐ │
│    ball_drop_buckets    ☑ ☐ │
│    ball_drop_final      ☐ ☐ │
│    edge_adjustment      ☑ ☐ │
│ ▼ pathing               V T │
│    waypoints            ☑ L │  ← L=log, C=console, B=both, ☐=none
│    walk_run_path        ☑ ☐ │
│    ...                      │
│ ▶ leap_attack           V T │  ← collapsed group
│ ▶ body_mechanics        V T │
│    ...                      │
└─────────────────────────────┘
```

- Groups are collapsible (▼/▶)
- Group header checkboxes toggle all children in that group
- Aspect filter (top) hides non-matching rows
- Visual column: checkbox (on/off)
- Textual column: cycles through none → log → console → both on click

### Global On/Off

The global toggle gates ALL debug output. When OFF, nothing renders or logs regardless of individual aspect states. When turned back ON, all previously-configured aspects resume. It does NOT mass-enable/disable individual aspects.

## RCON Commands

```
debug                          — toggle global on/off
debug list                     — list all registered aspects with current state
debug on <aspect>[/<sub>]      — human observer: enable VISUAL
debug off <aspect>[/<sub>]     — human observer: disable VISUAL
debug log <aspect>[/<sub>]     — human observer: enable TEXTUAL(log)
debug console <aspect>[/<sub>] — human observer: enable TEXTUAL(console)
debug both <aspect>[/<sub>]    — human observer: enable TEXTUAL(both)
debug nolog <aspect>[/<sub>]   — human observer: disable TEXTUAL
debug save                     — persist human observer state
debug load                     — reload human observer state from disk
debug filter type <type> on|off — entity type filter
debug filter id <pattern>      — entity ID filter (wildcard)
debug reset                    — clear all human observer state
debug profile <json>           — load a debug profile inline (for test automation)
debug clear_transient          — clear all non-human observers
```

## Test Integration

### Debug Profile in Test JSON

```json
{
  "name": "leap_floor_to_P1",
  "debug": {
    "pathing/waypoints": "log",
    "pathing/platform_leap_path": "log",
    "leap_attack/spots_considered": "both",
    "precog/current_path": "log"
  },
  "setup": [...],
  "checks": [...]
}
```

When the test runner loads a test, it registers a `test:<name>` observer for each listed aspect with the specified output mode. When the test completes, the observer is removed.

## Rendering API

All debug visuals and logs route through a common interface:

```gdscript
# In any script that renders debug output:
DebugOverlay.draw_line(
    aspect = "pathing/walk_run_path",
    entity = self,             # the entity being debugged
    from = pos_a,
    to = pos_b,
    color = Color.ORANGE,
    width = 2.0,
    log_msg = "walk path: %s → %s",   # optional log format string
    log_args = [pos_a, pos_b]          # optional log args
)

DebugOverlay.draw_circle(
    aspect = "body_mechanics/ik_plant_marks",
    entity = self,
    center = foot_pos,
    radius = 4.0,
    color = Color.GREEN
)

DebugOverlay.log(
    aspect = "precog/current_path",
    entity = self,
    msg = "PRECOG PATHFIND: P%d → P%d",
    args = [src, dst]
)
```

The DebugOverlay singleton:
1. Checks global on/off
2. Checks entity against filters
3. Checks if any observer wants VISUAL for this aspect → if yes, draw
4. Checks if any observer wants TEXTUAL for this aspect → if yes, log to appropriate destination(s)
5. If neither → early return (zero cost beyond the function call + checks)

### Draw Primitives

The API wraps all Godot draw methods:
- `draw_line`, `draw_circle`, `draw_arc`, `draw_rect`, `draw_string`
- `draw_polyline`, `draw_polygon`
- `log` (text-only, no visual)

Each accepts `aspect`, `entity`, visual params, and optional `log_msg`/`log_args`.

### Registration

Aspects are registered at startup:

```gdscript
# In quadruped_monster.gd _ready() or a central registration file:
DebugOverlay.register("platform_detection/platform_indicators", "Platform location bars and labels")
DebugOverlay.register("platform_detection/ball_drop_buckets", "Ball-drop simulation buckets")
DebugOverlay.register("pathing/waypoints", "Waypoint targets and current waypoint")
# ... etc
```

Unregistered aspects used in draw calls are auto-registered (but won't have descriptions in the UI).

## Persistence

### Human Observer State: `user://debug_profile.json`

```json
{
  "global_enabled": true,
  "entity_filter": {
    "types": {"monster": true, "dummy": true, "attacker": false},
    "id_pattern": "*"
  },
  "aspects": {
    "pathing/waypoints": {"visual": true, "textual": "none"},
    "pathing/walk_run_path": {"visual": true, "textual": "log"},
    "body_mechanics/ik_plant_marks": {"visual": false, "textual": "none"}
  },
  "collapsed_groups": ["leap_attack", "splay_poses"]
}
```

Saved on `Ctrl+S`. Loaded on game start.

## Stories

### Story 1: Core Infrastructure
- DebugOverlay autoload singleton with aspect registry
- Observer model (add/remove observers, resolve actualized state)
- Entity filtering (type + ID wildcard)
- Global on/off gate
- Draw primitive wrappers (draw_line, draw_circle, draw_arc, draw_rect, draw_string, draw_polyline, draw_polygon, log)
- Registration API

### Story 2: Debug Drawer UI
- Slide-out panel from left edge (Ctrl+D toggle)
- Aspect filter search box (hides non-matches)
- Entity filter section (type checkboxes, ID wildcard field)
- Global on/off checkbox
- 2-level collapsible tree with V/T columns
- Visual checkbox, textual mode cycling
- Group header toggles
- Ctrl+S save, auto-load on startup

### Story 3: RCON Integration
- All `debug` subcommands listed above
- Wired to DebugOverlay singleton
- Tab completion in console for aspect names

### Story 4: Test Runner Integration
- Parse `"debug"` block from test JSON
- Register/unregister test observers on test start/end
- `debug clear_transient` command

### Story 5: Migrate Existing Debug Rendering — COMPLETE (v0.10.18)
- Player debug rendering migrated to DebugOverlay aspects (`player/velocity_arrows`, `player/jump_tracers`, `player/archer_arcs`, `player/reticle_info`, `player/button_state`)
- `PlayerHUD._debug_mode` replaced by `DebugOverlay.global_enabled` as source of truth
- Hitbox debug aspects added (`hitboxes/monster_parts`, `hitboxes/player_attack`)
- Old `_debug_mode` flag in player_side.gd syncs from DebugOverlay
- Debug auto-disabled when entering gameplay from title screen

### Story 6: Docked Test Runner — IN PROGRESS (v0.10.18)
- Sub-section framework: 5 collapsible, resizable panels (Suites, Tests, Controls, Status, Editor)
- Layout persisted to `user://debug_panel_layout.json`
- Test editor docked into debug panel; floating window suppressed when docked
- World-space overlay (handles, zones) still renders independently
- RCON `run`/`suite` commands auto-dock when debug drawer is open

### Story 7: Generic Entity Selection & Config Panel — COMPLETE (v0.10.19)
- Config panel reorganized: search filter, entity list, config sliders
- Entity list shows ALL entities (enemies, players, dummies) with 1-indexed numbers, ID, and type
- Click any entity to select it — works for monsters, bats, players, dummies
- Generic world-space selection overlay: pulsing circle + number + state info panel with line pointing to entity
- Selection indicator removed from quadruped_monster.gd — now handled generically by debug drawer
- Config adapts to entity type: monsters show cfg() sliders, other entities show script properties
- Debug aspect tree click offset bug fixed (was using hardcoded header height)

## Implementation Order

1. **Story 1** — Core infrastructure (can test via RCON immediately)
2. **Story 3** — RCON integration (enables testing without UI)
3. **Story 4** — Test runner integration
4. **Story 2** — Drawer UI
5. **Story 5** — Migrate existing rendering (big bang rewrite of `_draw_debug()`)

## Migration Notes

- During Story 1-4, old debug rendering continues to work alongside the new system
- Story 5 is the big bang — all old debug code gets rewritten in one pass
- After Story 5, `debug_draw_lite` and `debug_draw_enabled` are removed
- `PlayerHUD._debug_mode` is replaced by `DebugOverlay.global_enabled`
- `PlayerHUD.debug_selected_enemy` may remain as a separate concept (entity selection for inspection) or be absorbed into entity filtering
