# EPIC: In-Game Console & Test Runner

## Overview

Quake-style pop-down console that accepts RCON commands directly. File-based test system where tests are JSON/script files stored on disk. Test suites aggregate multiple tests with a results task. Task queue executes tests sequentially.

## Concepts

### Console
- Slides down from top of screen on backtick (`)
- Accepts all RCON commands (same as TCP port 9999)
- Shows command history, scrollable output
- Tab completion for commands

### Test File
A JSON file defining a single test scenario:
```json
{
  "name": "same_floor_near",
  "description": "Monster attacks dummy on same floor, close range",
  "setup": [
    "clear",
    "clearplayers",
    "spawn dummy 800 885",
    "spawn monster 960 885"
  ],
  "wait": 15.0,
  "checks": [
    { "command": "hp", "extract": "damage_taken", "expect_gt": 0, "label": "damage" },
    { "command": "fps", "extract": "fps", "expect_gt": 30, "label": "fps" },
    { "command": "ik", "extract": "ik_peak", "expect_lt": 500, "label": "ik" }
  ]
}
```

### Test Suite
A JSON file defining a collection of tests + aggregation:
```json
{
  "name": "full_suite",
  "description": "Full 18-scenario combat test",
  "tests": [
    "res://data/tests/same_floor_near.json",
    "res://data/tests/same_floor_far.json"
  ],
  "aggregation": {
    "show_grid": true,
    "pass_threshold": 0.9
  }
}
```

### Task Queue
Sequential execution: setup → wait → check → next test → ... → aggregate.

## Stories

### STORY 1: Pop-Down Console

- [ ] **1.1** New script: `scripts/ui/game_console.gd` — CanvasLayer that slides down from top
- [ ] **1.2** Toggle with backtick (`) — slides in/out with animation
- [ ] **1.3** Text input field at bottom, output log above (scrollable)
- [ ] **1.4** Commands routed to `Rcon._execute()` — same as TCP commands
- [ ] **1.5** Command history (up/down arrows to cycle)
- [ ] **1.6** Output shows command + result, colored (green=OK, red=ERR)
- [ ] **1.7** Special console commands: `run <test>`, `suite <suite>`, `tests` (list available)
- [ ] **1.8** Hook into title_screen.gd input handler

### STORY 2: Test File Format & Loader

- [ ] **2.1** Test files stored in `res://data/tests/` (bundled) and `user://data/tests/` (custom)
- [ ] **2.2** Test file format: JSON with name, description, setup commands, wait time, checks
- [ ] **2.3** Check types: `expect_gt`, `expect_lt`, `expect_eq`, `expect_contains`
- [ ] **2.4** Extract: parse RCON response to pull a named value (e.g., "damage_taken=123" → 123)
- [ ] **2.5** Loader: `scripts/systems/test_runner.gd` — loads test files, validates format
- [ ] **2.6** Convert existing bash test scenarios to JSON test files

### STORY 3: Test Runner & Task Queue

- [ ] **3.1** Task queue: Array of tasks, executed sequentially
- [ ] **3.2** Each test becomes tasks: [setup_task, wait_task, check_task]
- [ ] **3.3** Setup task: execute RCON commands in sequence
- [ ] **3.4** Wait task: pause for N seconds (show countdown in console)
- [ ] **3.5** Check task: run check commands, compare results, record pass/fail
- [ ] **3.6** Results stored per-test: { name, passed, checks: [{label, value, expected, result}] }
- [ ] **3.7** Console command: `run <test_name>` — queue and execute a single test
- [ ] **3.8** Progress shown in console: "Running test 3/18: hunt_P1..."

### STORY 4: Test Suite & Aggregation

- [ ] **4.1** Suite file format: JSON with name, list of test file paths, aggregation config
- [ ] **4.2** Console command: `suite <suite_name>` — queue all tests + aggregation task
- [ ] **4.3** Aggregation task: runs after all tests complete, shows summary grid
- [ ] **4.4** Summary: total pass/fail, per-test results, worst metrics
- [ ] **4.5** Grid display: rendered on screen (reuse existing `title`/`score`/`grid` RCON commands)
- [ ] **4.6** `tests` command: list all available test files and suites

### STORY 5: Migrate Existing Tests

- [ ] **5.1** Convert `test_quick.sh` → `data/tests/quick.json`
- [ ] **5.2** Convert `test_all.sh` scenarios → individual test files + `data/tests/suites/full.json`
- [ ] **5.3** Convert `test_baseline.sh` → `data/tests/suites/baseline.json`
- [ ] **5.4** Convert `test_damage.sh` → `data/tests/suites/damage.json`
- [ ] **5.5** Convert `test_tether.sh` → `data/tests/suites/tether.json`

## Implementation Priority

1. **Story 1** — Console (foundation for everything)
2. **Story 2** — Test file format
3. **Story 3** — Test runner
4. **Story 4** — Suites + aggregation
5. **Story 5** — Migrate existing tests
