---
xid: STO-MECH-045
parent: ./epic.md
kind: story
effort: mech
size: M
status: in-progress
date: 2026-06-09
depends-on: []
bd-id: mdes-80wa
---

# Cursor-aim donut: mouse position as right-stick push magnitude

## Summary

The cursor's offset from the player is now the right-stick: it aims toward the
cursor and produces a push *magnitude* scaled by a radial donut (inside the
inner radius = no push, ramping to full push at the outer radius), wired into
the live player's aim path with a debug overlay to verify feel.

## Context

Second half of EPI-MECH-MOUSE-KEYBOARD-CONTROLLER-PARITY. Operator spec:
"mouse position relative to the player = right-thumb-stick directional push;
close is a light push, far is a hard push; extents based on a radial donut."

Discovered while implementing: the *live* player (`player_side.gd`) read aim
from WASD, and the mouse-relative aim in `PlayerInputController` is attached to
no scene (dead code). So this story also wires mouse-aim into the live player
for the first time, completing the WASD=move / mouse=aim split.

## Problem

For a keyboard player, produce an analog aim vector (direction + magnitude in
[0,1]) from cursor position, equivalent to a physical right-stick push.

## Design

### Approach

`_mouse_aim_vector()`: `dir = (cursor - player).normalized()`;
`mag = clamp((dist - INNER) / (OUTER - INNER), 0, 1)`; return `dir * mag`.
Inside `INNER` = 0 (deadzone hole); at/beyond `OUTER` = 1.0 (saturated). Defaults
`INNER = 48px`, `OUTER = 340px` (tunable consts).

Keyboard branches: `_get_aim_direction()` (pure direction) points at the cursor;
`_get_aim_direction_analog()` (magnitude-bearing) returns the donut vector.

### Changes

| File | Change |
|------|--------|
| `scripts/characters/player_side.gd` | `MOUSE_AIM_INNER/OUTER_RADIUS` consts; `_mouse_aim_vector()`; keyboard branches of both aim fns; `_draw_aim_donut()` |
| `scripts/autoload/debug_aspects.gd` | registered `input/aim_donut` aspect |
| `docs/design/input_mapping.md` | aim rows updated to "Mouse cursor" |

## Definition of Done

- [x] Cursor distance maps to push magnitude via the donut; direction follows cursor.
- [x] Wired into the live player (`player_side.gd`), not the dead `PlayerInputController`.
- [x] `input/aim_donut` debug aspect draws inner/outer rings + push vector (green→red) + readout.
- [x] Headless editor pass: 0 script errors.
- [x] **Operator verification (T-020):** operator ran the build with the `input/aim_donut` overlay and directed the commit (2026-06-13). Radii left at defaults (48/340); no retune requested yet.
- [x] Committed (trunk).

## Testing

### Integration

- [x] Editor pass compiles `player_side.gd` / `debug_aspects.gd`.
- [ ] Manual: `debug on input/aim_donut`, confirm magnitude 0 inside inner ring, 1.0 beyond outer.

## Out of scope

- *Consuming* the magnitude in abilities and de-normalizing the controller
  stick for true parity — STO-MECH-046.

## Implementation Notes

### What Changed

As in § Design. The donut math is duplicated in `_draw_aim_donut()` for the
visualization (uses `get_local_mouse_position()` in `_draw` local space).

### Gotchas

- The big one: the aim path I initially claimed "already works" was unwired
  scaffolding. Always confirm the *active* code path (`player_side.gd` is the
  live `Character` subclass; `PlayerInputController` is attached to no scene).
- Magnitude only has gameplay effect where a consumer uses the aim vector
  *directly* (e.g. ranger jump-impulse) — not where it normalizes. See
  STO-MECH-046.

## Status log

- 2026-06-13: Implemented + committed to trunk. Operator directed the commit.
  Open follow-up: STO-MECH-046 decides which behaviors honor push-magnitude and
  whether to de-normalize the controller right-stick for true parity.
