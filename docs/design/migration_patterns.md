# Migration Patterns

## Overview

Migration patterns create natural-looking seasonal/cyclical movement of wildlife (fireflies, bats, future species) across the level. A migration pattern defines a repeating sequence of phases, each containing one or more destination zones. Species associated with a pattern are compelled to move toward the nearest active zone, then return to normal behavior once they arrive.

## Core Concepts

### Migration Pattern

A named, repeating multi-phase sequence that governs where a species congregates over time.

| Property   | Type       | Description                                          |
|------------|------------|------------------------------------------------------|
| `id`       | String     | Unique identifier (e.g. `"firefly_drift"`)           |
| `species`  | String[]   | Which species this pattern applies to (e.g. `["fireflies"]`) |
| `cadence`  | float      | Seconds between phase transitions                    |
| `phases`   | Phase[]    | Ordered list of phases (1 through N)                 |

### Phase

A single step in the migration sequence. Contains one or more zones that species are drawn toward during this phase.

| Property | Type   | Description                              |
|----------|--------|------------------------------------------|
| `index`  | int    | Phase number (1-based)                   |
| `zones`  | Zone[] | One or more migration zones for this phase |

### Migration Zone (Node)

A circular area that acts as a destination during its parent phase.

| Property   | Type    | Description                                      |
|------------|---------|--------------------------------------------------|
| `zone_id`  | int     | Unique ID across all zones in the pattern        |
| `point`    | Vector2 | Center position (world space)                    |
| `radius`   | float   | Arrival radius — individual is "arrived" when inside |
| `strength` | float   | Pull force multiplier (configurable per-zone)    |

## Behavior Rules

### Phase Cycling

1. Only **one phase is active** at a time (the active phase `X`).
2. A timer fires every `cadence` seconds and advances `X → X+1`.
3. When `X > N`, it wraps back to `1` (endless loop).
4. Phase advances by time alone — it does **not** wait for individuals to arrive.

### Individual Movement

1. Each individual tracks a single int: `current_zone` — the `zone_id` of the last migration zone it entered.
2. When a phase becomes active, individuals compare their `current_zone` against the active phase's zone IDs.
3. If `current_zone` does **not** match any zone in the active phase → the individual is **compelled** toward the **nearest** active zone.
4. "Compelled" means a strong directional force (stronger than spawn-gravity, configurable via `strength`) is applied toward the zone's `point`.
5. Once the individual enters a zone (distance to `point` < `radius`), its `current_zone` is set to that `zone_id`. It **stops** being compelled and returns to normal behavior (random wander, home-point drift, etc.).
6. If the active phase has multiple zones, each individual independently calculates and targets the nearest one. It only needs to enter **one** zone to be satisfied.

### Phase Transition

When the phase advances from X to X+1:
- Every individual whose `current_zone` doesn't match any zone in the **new** phase will begin migrating.
- Individuals already inside a new-phase zone (by coincidence) are immediately satisfied.
- No state is "reset" — the `current_zone` int naturally mismatches the new phase's zone IDs, which triggers migration.

## JSON Schema

Added to the level config under a top-level `"migration_patterns"` key:

```json
{
  "migration_patterns": [
    {
      "id": "firefly_drift",
      "species": ["fireflies"],
      "cadence": 30.0,
      "phases": [
        {
          "zones": [
            {"zone_id": 1, "point": [300, 600], "radius": 120, "strength": 2.0},
            {"zone_id": 2, "point": [1600, 600], "radius": 120, "strength": 2.0}
          ]
        },
        {
          "zones": [
            {"zone_id": 3, "point": [960, 400], "radius": 150, "strength": 2.5}
          ]
        },
        {
          "zones": [
            {"zone_id": 4, "point": [500, 800], "radius": 100, "strength": 2.0},
            {"zone_id": 5, "point": [1400, 800], "radius": 100, "strength": 2.0}
          ]
        }
      ]
    }
  ]
}
```

## Level Editor Integration

A new editor mode: **MIGRATION**.

### Display
- Each migration zone rendered as a circle (center handle + radius handle)
- Zones colored by phase (phase 1 = blue, phase 2 = green, phase 3 = orange, etc., cycling)
- Active phase zones drawn solid, inactive phases drawn dim/dashed
- Phase number label at each zone center

### Editing
- Drag zone center to reposition `point`
- Drag radius handle to resize `radius`
- Right-click to add/remove zones within a phase
- Tab/number keys to switch which phase is being edited
- Properties panel shows `strength`, `cadence`, `species`

## Per-Individual State

Each entity (firefly, bat, etc.) gains one new field:

```gdscript
var _migration_zone: int = -1  # zone_id of last entered migration zone (-1 = none)
```

The movement system checks:
```
if active_phase has no zone matching _migration_zone:
    apply migration force toward nearest zone in active phase
else:
    normal behavior (wander, home-point, spawn-gravity)
```

## Scope

- **Current focus:** Title screen level (fireflies, bats)
- **Future:** All gameplay levels, additional species

## Example: Title Screen Firefly Migration

A 3-phase pattern with 30-second cadence:

| Phase | Zones | Description |
|-------|-------|-------------|
| 1     | Left grove + Right grove | Fireflies gather near the two trees |
| 2     | Center sky | Fireflies drift upward to center screen |
| 3     | Portal area (2 zones flanking portal) | Fireflies descend around the portal |

After phase 3, wraps back to phase 1. Bats follow their own pattern or share the same one. The result is a living, breathing title screen where wildlife visibly migrates across the landscape in waves.
