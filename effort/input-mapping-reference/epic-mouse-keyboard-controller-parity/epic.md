---
xid: EPI-MECH-MOUSE-KEYBOARD-CONTROLLER-PARITY
parent: ../design.md
kind: epic
effort: mech
status: in-progress
date: 2026-06-09
hugs: []
tenets: []
bd-id: mdes-qf5m
---

# Mouse & Keyboard Controller Parity

## Problem Statement

The game is designed around a game controller, but mouse-and-keyboard play had
no equivalent control scheme: mouse buttons and wheel were unbound, and the
live player (`player_side.gd`) read **aim from WASD**, not the cursor. The
mouse-relative aim that did exist lived in `PlayerInputController`, which is
attached to no scene (dead scaffolding). The result was that M&K players had no
analog-aim, no trigger/bumper equivalents, and a control feel nothing like the
pad. This epic makes M&K a first-class, controller-faithful scheme.

## Goals

- Mouse + keyboard maps 1:1 to the controller surface (sticks, triggers,
  bumpers, face/utility buttons) using research-backed, easy-to-press keys.
- Cursor position relative to the player acts as the right-stick: direction +
  **push magnitude** (close = light, far = hard), via a radial donut.
- Bindings stay in the input map / a single aim path so they remain remappable
  and `ai_cmd`-testable, with debug visualization to verify feel.

## Non-Goals (Out of Scope)

- Full user-facing rebinding UI (settings menu). Bindings are config/code-level
  for now.
- Touch / gyro / other input modalities.
- Changing controller (gamepad) feel beyond what parity requires.

## Context

**Source:** Interactive session with the operator (2026-06-09) — "drastically
improve the mouse-and-keyboard mappings to make the controls similar to game
controllers," followed by iterative refinement (triggers on mouse, bumpers on
Shift/Ctrl, cursor-as-right-stick-push donut). Decisions were research-backed
at the operator's request.

**Dependencies:**

- `player_side.gd` is the live player (the `Character` subclass "during
  migration"); `PlayerInputController` is unwired scaffolding.
- Godot input map in `project.godot`; hardcoded shoulder reads in
  `player_side.gd` / `executioner_class.gd`.

## Stories

| # | XID | Story | Status | Size |
|---|-----|-------|--------|------|
| 1 | `STO-MECH-044` | Mouse buttons & wheel → controller-equivalent actions | Implemented (pending operator verify + commit) | M |
| 2 | `STO-MECH-045` | Cursor-aim donut: mouse position as right-stick push magnitude | Implemented (pending operator verify + commit) | M |
| 3 | `STO-MECH-046` | Honor aim push-magnitude across abilities + controller parity | Open | M |
| 4 | `STO-MECH-047` | Move hardcoded L2/R2/R1 reads into the input map | Open | M |

## Design

### Approach

Two layers. **(a) Discrete buttons** are bound as events on the existing input
map actions (`project.godot`) where possible so the player code and
remappability come for free; the triggers (L2/R2) and R1 are still hardcoded
reads, so their M&K bindings live in code until STO-MECH-047 moves them into
the map. **(b) Analog aim** is computed in `player_side.gd`: for a keyboard
player the cursor offset is remapped through a donut (annulus) into a
direction×magnitude vector equivalent to a right-stick push.

### Architecture

- `project.godot` `[input]` — action event bindings (LMB/RMB removed from
  attack/special; MMB→`block`; wheel→`interact`; Shift→`grapple`).
- `player_side.gd` — `_mouse_aim_vector()` (donut), `_get_aim_direction()` /
  `_get_aim_direction_analog()` keyboard branches, `_draw_aim_donut()`.
- `executioner_class.gd` — R1 keyboard read.
- `scripts/autoload/debug_aspects.gd` — `input/aim_donut` aspect.
- `docs/design/input_mapping.md` — operator-facing reference (kept in sync).

### Alternatives Considered

| Alternative | Pros | Cons | Decision |
|-------------|------|------|----------|
| LMB/RMB → attack/special (face buttons) | Conventional shooter feel | Operator wanted triggers; collides with trigger semantics | Rejected (reverted) |
| Bumpers on `Alt` / letter keys | Free keys | `Alt` is in the ergonomic "difficult zone"; letters not holdable as cleanly | Rejected (research) |
| Bumpers on Shift + Ctrl | Both "easy-zone", holdable with WASD | Forced `block` off Shift | Selected |
| `block` stays on Shift | No remap | Blocks the bumper slot | Rejected → `block` moved to MMB |

## Decisions

| XID | Decision | Status | Rationale |
|-----|----------|--------|-----------|
| — | Cursor = right-stick push via donut (inner=deadzone, outer=saturation) | Adopted | Operator spec; gives analog aim M&K lacked |
| — | Bumpers on Shift/Ctrl, block on MMB | Adopted | Research-backed ergonomics; `Alt` rejected |
| — | Build in `player_side.gd`, not `PlayerInputController` | Adopted | Latter is unwired; former is the live player |

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Donut magnitude weakens existing keyboard abilities that used full-magnitude aim | Medium | Medium | STO-MECH-046 audits consumers; tune radii; debug viz |
| Controller vs mouse asymmetry (stick still normalized) | High | Low | STO-MECH-046 decides whether to de-normalize the stick |
| MMB/LMB conflict with debug tools (level editor, console) | Low | Low | Debug tools not active during gameplay |

## Success Criteria

- [ ] M&K player can aim (cursor), fire triggers (LMB/RMB), block (MMB), and use
      both bumpers (Shift/Ctrl) without lifting fingers off WASD.
- [ ] Cursor distance visibly modulates push (donut viz green→red).
- [ ] All stories shipped.
- [ ] `docs/design/input_mapping.md` updated.

## Milestones

| Milestone | Target Date | Actual | Status |
|-----------|-------------|--------|--------|
| Stories defined | 2026-06-09 | 2026-06-09 | done |
| Button + donut implementation | | 2026-06-09 | implemented, pending verify |
| Operator verification + commit | | | open |
| Magnitude consumption + map migration | | | open |

## Retrospective

_(Fill in after epic completion.)_

### What Went Well

-

### What Could Be Improved

-

### Lessons Learned

- The "aim already works" assumption was wrong — the live aim path was WASD,
  not the cursor. Tracing the *active* code path before building avoided
  shipping into dead scaffolding (T-001/T-004).
