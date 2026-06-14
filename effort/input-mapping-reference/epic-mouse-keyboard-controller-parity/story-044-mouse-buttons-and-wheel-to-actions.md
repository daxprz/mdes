---
xid: STO-MECH-044
parent: ./epic.md
kind: story
effort: mech
size: M
status: in-progress
date: 2026-06-09
depends-on: []
bd-id: mdes-k4zm
---

# Mouse buttons & wheel mapped to controller-equivalent actions

## Summary

Mouse buttons and wheel now drive the controller-equivalent inputs, and the two
bumpers get keyboard homes that are holdable with WASD — so a M&K player has the
full pad surface within reach.

## Context

First half of EPI-MECH-MOUSE-KEYBOARD-CONTROLLER-PARITY. Before this, mouse
buttons and wheel were unbound; bumpers/triggers only had awkward keyboard keys
(L2=Tab, R2=Enter, L1=G, R1=R). Operator directed: LMB/RMB = triggers; bumpers =
something holdable with WASD (Shift/Ctrl); block must move off Shift.

## Problem

Map the discrete controller buttons onto mouse + ergonomic keyboard keys, using
research-backed placements (keys in the WASD "easy zone"; avoid `Alt`).

## Design

### Approach

Bind on the existing input-map actions where the action is already map-driven
(so `player_side.gd` picks them up unchanged); use code reads for the still-
hardcoded triggers/R1. Block moves to middle-mouse to free Shift for a bumper.

### Final mapping

| Input | → | Controller | Where |
|-------|---|-----------|-------|
| Left mouse | L2 trigger | L2/LT | `player_side.gd:_is_trigger_pressed` |
| Right mouse | R2 trigger | R2/RT | `player_side.gd:_is_trigger_pressed` |
| Middle mouse | `block` (hold) | L3 | `project.godot` |
| Wheel up/down | `interact` (cycle) | B/Circle | `project.godot` |
| Left Shift | `grapple` | L1 | `project.godot` |
| Left Ctrl | recall | R1 | `executioner_class.gd` |

### Changes

| File | Change |
|------|--------|
| `project.godot` | MMB→`block`; wheel→`interact`; Shift→`grapple`; reverted earlier LMB/RMB on attack/special |
| `scripts/characters/player_side.gd` | `_is_trigger_pressed` keyboard branch: Tab/Enter → LMB/RMB |
| `scripts/classes/executioner/executioner_class.gd` | R1 keyboard read: `KEY_R` → `KEY_CTRL` |
| `docs/design/input_mapping.md` | Mouse & Keyboard section + sources |

## Definition of Done

- [x] LMB/RMB drive L2/R2; MMB blocks; wheel cycles mode; Shift grapples; Ctrl recalls.
- [x] No double-binding (LMB no longer also fires `attack`).
- [x] Choices research-backed and cited in `docs/design/input_mapping.md`.
- [x] Headless editor pass: input map parses, 0 script errors.
- [x] **Operator verification (T-020):** operator ran the build in an interactive testing session and directed the commit (2026-06-13). Explicit per-binding feel-confirmation not separately recorded.
- [x] Committed (trunk).

## Testing

### Integration

- [x] Editor pass validates `project.godot` input map (no parse errors).
- [ ] Manual: each binding fires the right action in-game.

## Out of scope

- Trigger/R1 lived in code (not the input map) — migrating them is STO-MECH-047.
- Push-magnitude / analog aim — STO-MECH-045.

## Implementation Notes

### What Changed

As in the mapping table. Bumper keys (Shift/Ctrl) chosen from the WASD
"easy-zone" consensus; `Alt` explicitly rejected as a "difficult-zone" key.

### Gotchas

- `block` was on Shift (L3); had to vacate to middle-mouse before Shift could
  host the L1 bumper.
- Editing `project.godot`'s serialized `Object(InputEvent…)` strings by hand is
  fragile — validate with a headless `--editor --quit` pass (Godot rewrites it
  canonically and drops malformed events).

## Status log

- 2026-06-13: Implemented + committed to trunk. Operator directed the commit
  after the interactive session. Follow-up: STO-MECH-047 re-homes the
  still-hardcoded L2/R2/R1 bindings into the input map.
