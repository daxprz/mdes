---
xid: STO-MECH-046
parent: ./epic.md
kind: story
effort: mech
size: M
status: draft
date: 2026-06-09
depends-on: [STO-MECH-045]
bd-id: mdes-0glm
---

# Honor aim push-magnitude across abilities + controller parity

## Summary

Decide and implement which gameplay behaviors should respond to the new aim
push-magnitude, and resolve the mouse/controller asymmetry so the cursor donut
is genuinely "equivalent to a right-stick push."

## Context

STO-MECH-045 makes the keyboard aim vector carry magnitude (0–1). But:
1. Most consumers only use the *direction* (they normalize), so push has no
   effect there yet.
2. The physical right-stick is still normalized in `_get_aim_direction_analog()`
   (always full push past the 0.2 deadzone), so pad and mouse are not yet
   equivalent.

## Problem

Define the intended semantics of "push strength" per ability, then make the code
honor it consistently across input devices.

## Design

### Open questions (need operator input)

- Which behaviors should scale with push? Candidates: directional jump/dash
  impulse, throw power, archer reticle distance, movement lean.
- Should the controller right-stick stop normalizing (preserve magnitude) so pad
  ↔ mouse are equivalent? Risk: changes existing pad feel for any consumer that
  used the vector directly.

### Known consumers (from 2026-06-09 scan)

| Consumer | Uses | Effect of magnitude |
|----------|------|---------------------|
| `ranger_class.gd:729` jump impulse (`aim * JUMP_VELOCITY * 0.25`) | vector directly | scales with push today |
| `player_side.gd:~2410` leap prediction | vector directly | scales today |
| `executioner_class.gd` ball/shackle throws | direction; power from charge timer | ignores push (likely keep) |

### Changes (provisional)

| File | Change |
|------|--------|
| `scripts/characters/player_side.gd` | optionally de-normalize right-stick; clamp helper |
| ability consumers | opt specific behaviors into magnitude scaling |

## Definition of Done

- [ ] Operator decision recorded: which behaviors honor push + stick parity yes/no.
- [ ] Implemented consistently for keyboard and (if chosen) controller.
- [ ] No regression in existing pad feel for behaviors not meant to change.
- [ ] Debug viz / test confirms push affects the chosen behaviors.

## Testing

### Integration

- [ ] Selected behaviors measurably scale between light (near inner ring) and hard (beyond outer).

## Out of scope

- The donut input math itself (STO-MECH-045).

## Implementation Notes

_(Filled during implementation.)_
