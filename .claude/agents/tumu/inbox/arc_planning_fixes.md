# Task: Arc Planning & Precog Pathfinding Fixes

**EPIC:** `docs/epics/EPIC_arc_planning_fixes.md`
**Priority:** High
**Status:** Ready to begin

## Context

The quadruped monster's platform leaping system is broken. The monster can't reliably pathfind across platforms because multiple arc planning and precog execution bugs interact. A previous attempt applied all fixes at once (401 lines) and the result was unstable.

## Current State

- `quadruped_monster.gd` has 401 lines of uncommitted changes (mixed: debug migration + unstable pathing fixes)
- The debug migration (Story 5) is working and should be preserved
- Test `leap_floor_to_P1` FAILS: `PRECOG PATHFIND: monster=P-1` — monster can't find its platform
- All leaping tests are expected to fail until fixes are applied

## What You Need To Do

### Phase 1: Diagnose Entity-Platform Matching
The most urgent issue is `monster=P-1`. Before any arc fixes matter, the monster must be able to locate itself on a platform.

1. Run `leap_floor_to_P1` and inspect the precog/platform_list logs
2. Check `_precog_add_entity_platform()` — why does the spawned monster not match P0?
3. Compare the raycast floor_y with platform P0's Y coordinate
4. Look for coordinate-space issues (local vs world in `_raycast_floor`)

### Phase 2: Apply Fixes Incrementally
Follow the order in the EPIC (Fix A through Fix G). After each fix:
1. Run `leap_floor_to_P1` (simplest test)
2. Check debug output for improvement
3. Only proceed to next fix if current one doesn't regress

### Phase 3: Full Regression
Once all fixes are in:
1. Run `suite leaping` — all 5 tests
2. Run `suite chained` — verify chained behavior
3. Run `suite combat` — verify floor combat still works

## Key Files to Read
- `docs/epics/EPIC_arc_planning_fixes.md` — full fix details and rationale
- `scripts/enemies/quadruped_monster.gd` — the monster (search for `_precog_add_entity_platform`, `_plan_leap_to_surface`, `_precog_find_path`)

## Debug Profile
All leaping tests have debug profiles that log pathing diagnostics automatically. Run any test and inspect stdout/log for detailed output.
