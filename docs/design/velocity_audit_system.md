# Velocity Audit System

## Problem

When diagnosing physics bugs (e.g. "why did the player suddenly change
direction?"), there's no way to know which line of code modified `velocity`
or why. Velocity is written directly from ~50+ locations in player_side.gd
(gravity, movement input, grapple, jump, knockback, wall slide, etc.) and
also mutated internally by `move_and_slide()`.

## Concept

Wrap all velocity writes behind a function that records the reason for each
change. In debug mode, unexplained or unexpected changes render as on-screen
tracer arrows so the developer can see exactly what's happening.

## API

```gdscript
# Constants
const SILENT_REASONS: Array[String] = [
    "gravity",
    "movement_input",
    "collision",          # move_and_slide internal
    "floor_snap",         # move_and_slide floor
    "friction",
    "mana_regen",         # not velocity, but pattern example
]

# State
var _vel_audit_log: Array = []  # [{reason, delta_v, pos, time}]
var _vel_audit_prev: Vector2 = Vector2.ZERO

# Core function — replaces all direct velocity writes
func _set_vel(new_vel: Vector2, reason: String = "") -> void:
    var delta_v: Vector2 = new_vel - velocity
    if _debug_mode and delta_v.length() > 2.0:
        if reason.is_empty() or reason not in SILENT_REASONS:
            _vel_audit_log.append({
                "reason": reason if not reason.is_empty() else "UNKNOWN",
                "delta_v": delta_v,
                "old_vel": velocity,
                "new_vel": new_vel,
                "pos": global_position,
                "time": 5.0,  # Linger for 5 seconds
            })
    velocity = new_vel


func _add_vel(impulse: Vector2, reason: String = "") -> void:
    _set_vel(velocity + impulse, reason)


# For move_and_slide: snapshot before/after
func _audited_move_and_slide() -> void:
    var pre: Vector2 = velocity
    move_and_slide()
    var delta_v: Vector2 = velocity - pre
    if _debug_mode and delta_v.length() > 2.0:
        _vel_audit_log.append({
            "reason": "collision",
            "delta_v": delta_v,
            "old_vel": pre,
            "new_vel": velocity,
            "pos": global_position,
            "time": 5.0,
        })
```

## Migration

Every direct write to `velocity` in player_side.gd would be replaced:

| Before | After |
|--------|-------|
| `velocity.x = speed * input` | `_set_vel(Vector2(speed * input, velocity.y), "movement_input")` |
| `velocity.y += GRAVITY * delta` | `_add_vel(Vector2(0, GRAVITY * delta), "gravity")` |
| `velocity = dir * launch_speed` | `_set_vel(dir * launch_speed, "grapple_launch")` |
| `velocity += aim * impulse` | `_add_vel(aim * impulse, "grapple_jump")` |
| `velocity = Vector2.ZERO` | `_set_vel(Vector2.ZERO, "death")` |
| `move_and_slide()` | `_audited_move_and_slide()` |

## Reason Categories

### Silent (no debug rendering)
These are expected every-frame changes that would flood the screen:

| Reason | Source |
|--------|--------|
| `gravity` | `_apply_gravity()` |
| `movement_input` | `_handle_movement()` |
| `collision` | `move_and_slide()` internal response |
| `floor_snap` | `move_and_slide()` floor sticking |
| `friction` | Horizontal deceleration |
| `swing_pendulum` | `_grapple_tick_swinging()` pendulum update |
| `mage_airwalk` | Air-walk hover |

### Audible (rendered as debug arrows when debug is on)
These are discrete events worth tracking:

| Reason | Source |
|--------|--------|
| `grapple_launch` | Initial launch toward hook point |
| `grapple_throw` | Windup release |
| `grapple_pull` | L1 pull toward anchor |
| `grapple_tug` | Newtonian tug on enemy |
| `grapple_jump` | Jump-release impulse |
| `grapple_bounce` | Rope going taut after slack |
| `jump` | Normal jump |
| `wall_jump` | Wall jump |
| `knockback` | Enemy hit / damage knockback |
| `dash` | Ninja dash, rogue shadow dash |
| `rocket_thrust` | Demolitionist jetpack |
| `rocket_crash` | Jetpack crash landing |
| `enrage_burst` | Melee enrage activation |
| `wind_gust` | Healer gust knockback |
| `oob_teleport` | Out-of-bounds teleport |
| `UNKNOWN` | No reason provided (always rendered — indicates a bug) |

## Debug Rendering

Each audit log entry renders at its world position as:

```
                    ← old velocity (dim green, thin)
    [pos] ●
                    → new velocity (bright cyan, thick, arrowhead)
         ↗ delta_v (yellow, dashed)

    "grapple_jump +275px/s"   (text label)
```

- Arrows scale with magnitude (capped at 120px visual length)
- Fade out over the last 2 seconds of their lifetime
- Color-coded by category:
  - Green: expected physics (gravity, movement)
  - Cyan: grapple system
  - Red: damage/knockback
  - Yellow: unknown/untagged

## Implementation Effort

**Scope:** ~50-70 edits across player_side.gd

**Files affected:**
- `scripts/characters/player_side.gd` — all velocity writes + move_and_slide calls
- Potentially enemy scripts if extended to enemy velocity tracking

**Risk:** Low — purely additive. The `_set_vel` / `_add_vel` functions are
no-ops in release mode (just `velocity = new_vel`). Debug rendering only
activates with SELECT button.

**Recommendation:** Implement when actively debugging physics issues.
The system pays for itself on the first complex bug where you'd otherwise
spend 30+ minutes adding print statements. Can be gated behind a compile
flag or `OS.is_debug_build()` to zero-cost in release builds.

## Relationship to Existing Debug Tools

This complements the existing debug system:
- **SELECT toggle** — already controls debug mode
- **Green arrow** — current velocity (already implemented)
- **Red arrow** — predicted jump velocity (already implemented)
- **Tracer arrows** — snapshot on jump release (already implemented)
- **HUD button state** — controller input display (already implemented)
- **Velocity audit** — would explain WHY velocity changed (proposed)
