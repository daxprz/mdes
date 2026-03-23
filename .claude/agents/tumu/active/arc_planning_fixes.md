# Task: Arc Planning & Precog Pathfinding Fixes

**EPIC:** `docs/epics/EPIC_arc_planning_fixes.md`
**Priority:** High
**Status:** In Progress — Test Editor Story 1 + UI shell complete

---

## Completed This Session

### In-Game Test Editor — Story 1 (COMPLETE)
Full RCON-based test editing workflow implemented and verified passing.

**New files:**
- `scripts/systems/test_bounded_leaps.gd` — visualization node for bounded leap checks
- `scripts/ui/test_editor.gd` — full in-game test editor UI (floating window, control points)
- `data/tests/verify_leap_graph_P0_P1.json` — has `"script"` field, passes end-to-end
- `docs/epics/EPIC_test_editor.md` — Story 1 marked Complete ✓

**Modified files:**
- `scripts/systems/test_runner.gd` — added `run_test_script()`, `_parse_script_check()`, `from_rcon_bleap` support in `_execute_check_task`
- `scripts/autoload/rcon.gd` — added `bleap`, `testload`, `testshow`, `testedit`, `testinsert`, `testdelete`, `testrun`, `testsave`, `testnew`, `leaps`, `clearleaps` commands; `_cmd_bleap`, `get_bleap_check_data`, `_cmd_testload`, `_cmd_testsave`
- `scripts/ui/game_console.gd` — full rewrite: cursor/selection/cut/paste support; test name autocomplete for `testload`, `run`, `testsave`, `suite`
- `scripts/ui/test_menu.gd` — added "Tests..." item → opens test_editor via `call_deferred`
- `scripts/autoload/debug_aspects.gd` — added `testing/planned_leaps`, `testing/bounded_leap_checks`

**Verified:**
- `testload verify_leap_graph_P0_P1` → 21 lines (script format) ✓
- `testshow` → numbered list ✓
- `testedit` / `testinsert` / `testdelete` → all work ✓
- `testrun` → both plans matched, fps=111 > 20, `=== 2/2 PASSED ===` ✓

### Game Console Improvements (COMPLETE)
- Cursor position (`_cursor_pos`) — blinking vertical bar, not just end-of-line
- Text selection (`_select_start`) — Shift+arrow/Home/End
- Ctrl+A (select all), Ctrl+C (copy), Ctrl+X (cut), Ctrl+V (paste)
- Ctrl+Left/Right — word jump
- Delete key — delete char at cursor / delete selection
- Test name autocomplete: `testload <Tab>`, `run <Tab>`, `testsave <Tab>` → filesystem names
- Suite autocomplete: `suite <Tab>`

### In-Game Test Editor UI — Story 2 skeleton (IN PROGRESS)
`scripts/ui/test_editor.gd` (~550 lines) implements:
- Ctrl+T → "Tests..." → opens editor (via `call_deferred` to avoid input leakage)
- Floating draggable window (title bar drag)
- Numbered command list, color-coded by type
- `T` key → test picker (filterable, ↑↓ navigate, Enter load)
- Inline edit field for selected row (cursor/selection/Ctrl+C/V/X/A)
- Button bar: ▶/⏸, ⏹, ↺, +row, ✕row, 💾
- TAB → EDIT/RUN mode toggle
- World-space control handles (Node2D overlay, same pattern as level_editor):
  - `spawn monster/dummy X Y` → draggable dot
  - `bleap a/b X Y R` → circle center + radius diamond grip
  - `bleap plan ...` → START rect corners + center, END circle center + radius, DISALLOW endpoint dots
- Real-time command text update as handles drag
- `_parse_command` / `_format_command` / `_build_handles` / `_apply_handle_drag` for all command types
- Ctrl+S / 💾 button → save via RCON `testsave`

**Current state:** Window opens (Ctrl+T → Tests...) but untested beyond that. User is actively testing.

**Known issue fixed this session:** Opening editor caused immediate close because Enter key event leaked into test_editor (layer=108 > test_menu layer=95, so test_editor received input first). Fixed with `call_deferred("_open_test_editor")`.

---

## Open / Next Steps

### Test Editor UI bugs to investigate
1. Test picker — verify T key opens it, filter works, Enter loads test and clears scene
2. Handle dragging — verify world-space coordinate conversion works in the test level (camera zoom)
3. `_load_test` in test_editor syncs `rcon._test_script` — verify this roundtrip is correct
4. Play button — calls `rcon._test_runner.run_test_script(...)` — verify test runner output shows in console (not in editor window currently)
5. Window drag off-screen prevention (clamp `_window_pos` to viewport)

### Story 2 remaining (EPIC_test_editor.md)
- Execution state overlay: highlight the currently-running line during `testrun`
- Per-check pass/fail indicator in the row list after run completes
- Scroll-to-selected-row behavior during run

### Physical Leap Execution Bug (from original task — STILL OPEN)
- Precog graph IS correct (P0→P1 edge: `from=(778,890) arrival=(463,745) vel=(-262,-481)`)
- Monster launches but lands back at floor (y=890) at t=0.78s instead of P1 (y=750)
- `floor_snap_length=0` IS set during leap
- `verify_leap_graph_P0_P1` is the regression baseline — run it to confirm graph is still healthy
- Next step: add logging to the physical leap execution path to trace why trajectory fails
- Relevant code: `quadruped_monster.gd` around leap state machine, `_do_leap_physics()`

---

## Key File Locations

| File | Purpose |
|------|---------|
| `scripts/ui/test_editor.gd` | Full test editor UI |
| `scripts/ui/test_menu.gd` | Ctrl+T menu — wired to open editor |
| `scripts/ui/game_console.gd` | Backtick console — cursor/select/paste + test autocomplete |
| `scripts/autoload/rcon.gd` | All bleap/test* commands |
| `scripts/systems/test_runner.gd` | `run_test_script()`, `_parse_script_check()` |
| `scripts/systems/test_bounded_leaps.gd` | Visual overlay for bounded leap checks |
| `data/tests/verify_leap_graph_P0_P1.json` | Primary regression test — has `"script"` field |
| `docs/epics/EPIC_test_editor.md` | Story 1 complete, Stories 2-4 planned |
| `docs/epics/EPIC_arc_planning_fixes.md` | Original task — physical leap fixes |

---

## Platform Layout (reference)
```
P3 (669,525)  x=[527..811]     P4 (1251,525)  x=[1108..1393]   ← upper
P1 (540,750)  x=[330..749]     P2 (1380,750)  x=[1171..1590]   ← lower
P0 (960,885)  x=[30..1880]                                      ← floor
```
