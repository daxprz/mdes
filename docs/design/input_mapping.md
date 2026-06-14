# DAX Input Mapping Reference

All input actions defined in `project.godot`, mapped across controller vendors and keyboard.

## Button / Input Map

| RCON Action    | Typical Use           | PS5 DualSense     | Xbox Controller | Keyboard | Godot Button |
|----------------|-----------------------|--------------------|-----------------|----------|--------------|
| `jump`         | Jump                  | Cross (X)          | A               | Space    | 0 (A)        |
| `interact`     | Cycle mode / Interact | Circle (O)         | B               | F        | 1 (B)        |
| `attack`       | Primary attack        | Square             | X               | J        | 2 (X)        |
| `special`      | Special ability       | Triangle           | Y               | K        | 3 (Y)        |
| `debug_toggle` | Debug overlay toggle  | Share              | Back/View       | Backtick | 4 (Back)     |
| `ps_button`    | Join game             | PS Button/Options  | Guide/Start     | Enter    | 6 (Start)    |
| `block`        | Block / Defend        | L3 (stick click)   | LS (stick click)| Shift    | 7 (L-Stick)  |
| `grapple`      | Grapple / Throw       | L1                 | LB              | G        | 9 (L-Shoulder)|
| `pause`        | Pause menu            | Options            | Start/Menu      | Escape   | 6 (Start)    |

## Analog Inputs (not in input map — read directly)

| Input                | PS5 DualSense    | Xbox Controller  | Keyboard        | RCON             |
|----------------------|------------------|------------------|-----------------|------------------|
| Move (horizontal)    | Left Stick X     | Left Stick X     | A/D             | `move_left`/`move_right` |
| Move (vertical)      | Left Stick Y     | Left Stick Y     | W/S             | `move_up`/`move_down` |
| Aim (horizontal)     | Right Stick X    | Right Stick X    | Mouse cursor X  | `ai_cmd` aim_x   |
| Aim (vertical)       | Right Stick Y    | Right Stick Y    | Mouse cursor Y  | `ai_cmd` aim_y   |
| L2 (trigger)         | L2 Trigger       | LT               | Tab             | (hardcoded)      |
| R2 (trigger)         | R2 Trigger       | RT               | (none)          | (hardcoded)      |
| R1 (shoulder)        | R1               | RB               | R / Shift       | (hardcoded)      |

## Mouse & Keyboard (cursor aim scheme)

Mouse-and-keyboard play mirrors a game controller: the **left hand stays on
WASD**, the **right hand drives the mouse** (aim + the two triggers). The goal is
that every action is reachable *without lifting fingers off WASD* — so the
shoulder/extra actions sit on mouse buttons, the mouse wheel, and the two
"hold-while-moving" modifier keys (Shift/Ctrl).

Key placement follows the common WASD ergonomics consensus (keys in the
"easy zone" — `Q E R F`, `Shift`, `Ctrl`, `Space`, mouse buttons, wheel — host
the frequent actions; `Alt`/`6-0`/stretch keys are avoided). See Sources below.

| Input          | RCON Action / read | Controller equiv. | Notes |
|----------------|--------------------|-------------------|-------|
| Move cursor    | aim (`_poll_aim`)  | Right Stick       | `intent_aim = (cursor - player).normalized()` |
| **Left mouse** | L2 trigger         | L2 / LT           | `player_side.gd:_is_trigger_pressed` keyboard branch |
| **Right mouse**| R2 trigger         | R2 / RT           | `player_side.gd:_is_trigger_pressed` keyboard branch |
| **Middle mouse** | `block`          | L3 (stick-click)  | Hold to block; bound on the `block` input action |
| Wheel up/down  | `interact`         | Circle / B        | Cycle mode (both directions cycle for now) |
| **Left Shift** | `grapple`          | L1 (bumper)       | Holdable with WASD; bound on the `grapple` input action |
| **Left Ctrl**  | R1 (recall)        | R1 (bumper)       | Holdable with WASD; `executioner_class.gd` keyboard branch |

Triggers (L2/R2) and R1 (recall) are still **hardcoded reads**, not input-map
actions — the mouse/key bindings for them live in code (`player_side.gd`,
`executioner_class.gd`), while `block`/`grapple`/`interact` are bound in
`project.godot`. Moving L2/R2/R1 into the input map (so they're remappable +
`ai_cmd`-drivable) remains the recommended follow-up below.

Scheme chosen 2026-06-09, research-backed (see Sources). `Alt` was explicitly
rejected — it's in the "difficult zone" per the ergonomics guides.

### Sources
- walkthroughs.games — "Best Keybinds: Fix Awkward Controls Fast"
- winorm.com — "The Best Keybindings to Use in Competitive Gaming"
- Lenovo glossary — WASD hand position; Steam Community keybind discussions

## Hardcoded Reads (bypass input map)

These are read directly from `Input.is_joy_button_pressed()` or `Input.get_joy_axis()` in player_side.gd, NOT through the Godot input action system. They cannot currently be remapped or sent via `ai_cmd`.

| Code Reference                | PS5        | What It Does                     |
|-------------------------------|------------|----------------------------------|
| `JOY_BUTTON_RIGHT_SHOULDER`   | R1         | Recall chain / Toggle throw mode |
| `JOY_AXIS_TRIGGER_LEFT`       | L2         | Chain split adjust / Combat stance |
| `JOY_AXIS_TRIGGER_RIGHT`      | R2         | Chain split adjust               |
| `JOY_AXIS_RIGHT_X/Y`          | Right Stick| Aim direction (head, throw, reticle) |
| `JOY_AXIS_LEFT_X/Y`           | Left Stick | Movement (also read via input map) |

## Notes

- `ps_button` and `pause` both map to button 6 (Start/Options). Join vs pause is context-dependent (title screen vs gameplay).
- L2/R2 are analog triggers read as axes (0.0 to 1.0), not binary buttons.
- R1 recall and L2/R2 chain split are NOT in the input map — they're hardcoded in player_side.gd. This means `ai_cmd` cannot currently simulate R1, L2, or R2 presses.
- Right stick aim is passed to `ai_cmd` via the `aim_x aim_y` parameters, which set `_ai_aim`.

## Recommended Improvements

1. **Move R1, L2, R2 into the input map** so they can be remapped and sent via `ai_cmd`
2. **Rename `interact` to something more descriptive** — it's Circle/B, used for mode cycling on Executioner
3. **Add `ai_cmd` support for L2, R2, R1** so tests can simulate trigger presses and recall
