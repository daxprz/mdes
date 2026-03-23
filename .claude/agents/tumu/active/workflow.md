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
