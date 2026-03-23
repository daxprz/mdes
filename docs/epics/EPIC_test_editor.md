# EPIC: In-Game Test Editor

## Overview

Tests are currently JSON files with nested structures that must be hand-edited outside the game. This EPIC builds an in-game system where every aspect of a test — setup commands, wait duration, debug profile, and check constraints — is expressed as a flat sequence of RCON statements that can be viewed and edited directly from the in-game console and a dedicated editor panel.

## Design: Tests as RCON Scripts

The core idea: **a test is a numbered list of RCON commands.** The test runner executes them in order. Some commands are "meta-commands" that only exist in test context (like `wait` and `check`). Bounded leap constraints are configured with a `bleap` builder. Everything you can see in the JSON, you can also type at the console.

### Script Format (JSON `"script"` field)

```json
{
    "name": "verify_leap_graph_P0_P1",
    "script": [
        "debug on precog/platform_list",
        "debug on testing/planned_leaps",
        "debug on testing/bounded_leap_checks",
        "debug log precog/current_path",
        "clear",
        "portal off",
        "clearplayers",
        "clearzones",
        "spawn monster 700 885",
        "spawn dummy 540 730",
        "standdown off",
        "wait 8",
        "bleap reset",
        "bleap a 540 885 600",
        "bleap b 540 750 130",
        "bleap plan req start 30 855 1850 50 end 540 750 130",
        "bleap plan opt start 600 855 300 50 end 540 750 130 disallow 60 669 525 811 525",
        "bleap min 1",
        "check bounded_leaps P0-to-P1 leap graph edge",
        "check fps > 20"
    ]
}
```

The legacy `setup`/`wait`/`checks` format continues to work. The `script` field is the new format. Both can coexist.

### `bleap` Command Reference

Stateful builder for bounded leap checks. Each `bleap reset` starts a fresh definition.

```
bleap reset                            — start new leap def (clears state)
bleap a <x> <y> <r>                    — set platform A (source) circle
bleap b <x> <y> <r>                    — set platform B (dest) circle
bleap plan req|opt                     — start a plan (required or optional)
bleap start <x> <y> <w> <h>           — set START rect for current plan
bleap end <x> <y> <r>                  — set END circle for current plan
bleap disallow <r> <x1> <y1> <x2> <y2>— add DISALLOW capsule to current plan
bleap min <n>                          — set min_matched count
bleap show                             — display current state in console
```

**All-in-one plan shorthand** (used in script format):
```
bleap plan req start <x> <y> <w> <h> end <x> <y> <r> [disallow <r> <x1> <y1> <x2> <y2>]
bleap plan opt start <x> <y> <w> <h> end <x> <y> <r> [disallow ...]
```

### `check` Command Reference

```
check bounded_leaps <label>           — run check with current bleap state
check fps > <n>                       — check FPS threshold
check hp > <n>                        — check damage taken threshold
check zones                           — validate ETZ/DAZ zones
```

### Test Management Commands

```
testload <name>        — load a test into the editor buffer
testshow               — display current script as numbered list
testedit <n> <cmd>     — replace line N with a new command
testinsert <n> <cmd>   — insert a command before line N
testdelete <n>         — delete line N
testrun                — run the currently loaded script
testsave               — save current script back to its JSON file
testsave <name>        — save as a new test name
testnew <name>         — start a blank test with that name
```

## Stories

### Story 1: Script Format + `bleap` + `testload/show/edit/run/save` ✦ MVP
**Status:** Complete ✓

Add the `bleap` command family to RCON. Add script-format support to the test runner. Add `testload`, `testshow`, `testedit`, `testinsert`, `testdelete`, `testrun`, `testsave` to RCON. Convert `verify_leap_graph_P0_P1.json` to script format. This gives full editing capability via the console.

**Acceptance:** `testload verify_leap_graph_P0_P1` → `testshow` displays numbered list → `testedit 14 "bleap a 500 885 400"` updates line 14 → `testrun` executes and passes.

### Story 2: Test Editor Panel
**Status:** Planned

A slide-in panel (from right, layer=108) that shows the loaded test script as a scrollable numbered list. The selected line is highlighted. Keyboard/gamepad navigation: arrow keys scroll, Enter edits the selected line using the console input. The panel shows execution state (which line ran last, pass/fail indicator per check).

### Story 3: Click-to-Place Constraint Shapes
**Status:** Planned

When editing a `bleap` constraint, clicking on the game world places/resizes the shapes:
- Click + drag for platform A/B circles: adjusts center and radius
- Click + drag for START rectangles: resizes corners
- Click + drag for END circles: adjusts center and radius
- Click two points for DISALLOW paths: sets x1,y1 → x2,y2

The `testing/bounded_leap_checks` aspect must be ON for this to work (provides visual handles).

### Story 4: Test Library Browser
**Status:** Planned

A left panel showing all available tests (`tests` command output). Click a test to load it. Shows PASS/FAIL state from the last run. Filter by name. Drag to reorder within a suite.

## Implementation Notes

- `bleap` state lives in RCON (or a dedicated `TestScriptState` node) — reset on `testload`
- `testload` reads the JSON and converts both legacy and script formats to a canonical script list
- `testsave` converts the script back to JSON (using `script` field)
- The test editor panel is a CanvasLayer at layer=108 (below console=110, below debug_drawer=109)
- Constraint shape handles (Story 3) use `_unhandled_input` with a mouse capture mode

## Debug Aspects Added

- `testing/planned_leaps` — arc visualization (already added)
- `testing/bounded_leap_checks` — constraint shape overlays (already added)
- `testing/test_editor_panel` — test script panel UI (Story 2)
