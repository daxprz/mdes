# Test Reference

## Gate Suite Protocol

### Tag Convention
- `ts/<suite>/pass` — suite passed at this commit
- `ts/<suite>/fail` — suite failed at this commit
- Tags force-moved to HEAD after each run
- LOCAL only (push with `git push origin --tags` if desired)

### Gate vs Non-Gate
- Gate suites: `"gate": true` in JSON. Must partition ALL tests, no overlaps.
- Current gate suites: `chained`, `combat`, `leaping`, `scaling`
- Non-gate: `all` (everything), `todo` (known failures)

### Staleness Check
1. No tag → NEVER_TESTED → must run
2. `pass` tag at HEAD → CLEAN → skip
3. `pass` tag behind HEAD + `.gd` changes → STALE → must run
4. `fail` tag → KNOWN_BROKEN → should run

### Code Annotations
Source files can declare suite affinity:
```gdscript
func _plan_leap_to_surface(...):  # TEST ts:leaping ts:combat
```
Without annotations, any `.gd` change = all gate suites stale.

## Platform Layout (Standard Test Level)

```
P3 (669,525)          P4 (1251,525)      ← upper platforms
   x=[527..811]          x=[1108..1393]

P1 (540,750)          P2 (1380,750)      ← lower platforms
   x=[330..749]          x=[1171..1590]

P0 (960,885)                              ← floor
   x=[30..1880]
```

## Test Output Paths
- Per-test: `user://test-output/<version>/<testname>/<timestamp>/`
  - `test.json` — copy of script
  - `results.json` — checks, violations, durations
- Per-suite: `user://test-output/<version>/<suitename>/<timestamp>.json`

## Test State Machine
`INITIALIZING → RUNNING → COMPLETE → FINALIZED`
