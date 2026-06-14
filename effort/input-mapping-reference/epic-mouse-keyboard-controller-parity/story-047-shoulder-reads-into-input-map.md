---
xid: STO-MECH-047
parent: ./epic.md
kind: story
effort: mech
size: M
status: draft
date: 2026-06-09
depends-on: [STO-MECH-044]
bd-id: mdes-ee30
---

# Move hardcoded L2/R2/R1 reads into the input map (remappable + ai_cmd)

## Summary

The triggers (L2/R2) and right bumper (R1/recall) are read directly via
`Input.is_key_pressed` / `Input.get_joy_axis` rather than through input-map
actions, so they can't be remapped or simulated via `ai_cmd`. Promote them to
proper input actions.

## Context

Long-standing recommendation in `docs/design/input_mapping.md` ("Recommended
Improvements"). STO-MECH-044 bound LMB/RMB→L2/R2 and Ctrl→R1 *in code* as a
pragmatic step; this story makes them first-class input actions so the whole
controller surface is uniform, rebindable, and test-drivable.

## Problem

L2/R2/R1 bypass the Godot input action system, creating two classes of input
(map-driven vs hardcoded) and blocking `ai_cmd` simulation + future rebinding.

## Design

### Approach

Create input-map actions (e.g. `trigger_left`, `trigger_right`, `recall`) with
both the joypad axis/button and the M&K bindings (LMB/RMB/Ctrl) attached. Triggers
are analog on a pad but binary on M&K — keep the threshold→bool collapse in
`_is_trigger_pressed`, but source the binary state from the action. Add `ai_cmd`
support so tests can drive L2/R2/R1.

### Changes (provisional)

| File | Change |
|------|--------|
| `project.godot` | add `trigger_left` / `trigger_right` / `recall` actions |
| `scripts/characters/player_side.gd` | read triggers via actions; keep analog hysteresis for pad |
| `scripts/classes/executioner/executioner_class.gd` | read R1 via action |
| `scripts/autoload/rcon.gd` | `ai_cmd` support for L2/R2/R1 |
| `docs/design/input_mapping.md` | move L2/R2/R1 out of "Hardcoded Reads" |

## Definition of Done

- [ ] L2/R2/R1 are input-map actions; no remaining hardcoded `is_key_pressed`/axis reads for them.
- [ ] Analog trigger hysteresis preserved for controllers.
- [ ] `ai_cmd` can simulate L2/R2/R1 presses.
- [ ] `docs/design/input_mapping.md` "Hardcoded Reads" table emptied of these.

## Testing

### Integration

- [ ] A test drives L2/R2/R1 via `ai_cmd` and observes the expected behavior.
- [ ] Controller analog feel unchanged (threshold/hysteresis intact).

## Out of scope

- The M&K bindings themselves (delivered in STO-MECH-044); this re-homes them.

## Implementation Notes

_(Filled during implementation.)_
