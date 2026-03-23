# TUMU Workflow — Patch Discipline

## Before Starting Patch Work
1. **Commit current state** — never start changes on a dirty tree
2. **Run baseline** — `suite leaping`, `suite combat`, `suite chained` — capture scores
3. **Document what you're changing and why** in the active task file
4. **Run the specific test** you're modifying to confirm the failure BEFORE patching

## Before Releasing Patch Work
1. **Run the specific test** — confirm the fix works
2. **Run all related suites** — confirm no regressions
3. **Compare to baseline** — score should be equal or better
4. **Commit with clear message** describing what changed and the before/after scores

## Testing Rules
- NEVER use sleep/wait — tests succeed or fail fast (breach fences, exit circles)
- NEVER change tests to fix code bugs — fix the code
- ALWAYS run tests via the game UI so the human can SEE what's happening
- When running a single test, use the test editor (Ctrl+T → Tests... → pick → play)
- When running a suite, use the console (`suite <name>`)
- When polling for results, NEVER sleep longer than 1 second. Check frequently.
- Prefer `sleep 1` loops over `sleep 30/60/90` blocks that block the user.

## Directory Structure
```
.claude/agents/tumu/
  active/
    arc_planning_fixes.md    — current task status + next steps
    workflow.md              — this file
    baseline_results.md      — latest test baseline scores
  pending/                   — blocked tasks
  archive/                   — completed tasks
  inbox/                     — new tasks
```

## Test Output Files

Every test run writes comprehensive output to:
```
user://test-output/<major>.<minor>.<patch>/<testname>/<timestamp>/
  test.json      — copy of the test script that was run
  results.json   — comprehensive output:
                   * test duration in seconds
                   * all checks: label, passed, value, expected
                   * check logs (per-plan detail for bounded leaps)
                   * violations: from/arrival positions, breach points with reasons
                   * matched edges: from/arrival positions
                   * bleap monitor counts (matched, violations)
                   * breach fence result (entity, position)
```

Suite runs write to:
```
user://test-output/<major>.<minor>.<patch>/<suitename>/<timestamp>.json
  — list of tests run with per-test pass/fail and summary
  — aggregate suite outcome (passed/total/all_passed)
```

These files persist across runs and can be compared across versions to track regressions.
Reference them when investigating failures — they contain the exact check values, violation
positions, and breach details that the on-screen display might not fully capture.
