---
xid: STO-TOOLS-018
parent: ./epic.md
kind: story
effort: tools
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-24h5
shipped: 2026-06-07
tasks: 9
complete: 6
---

# Test File Format & Loader

## Summary

JSON test format with setup, wait, and typed checks, loaded and validated by test_runner.gd.

## Context

_(Why is this story needed? What does it depend on? Link to the parent
epic. If this is a discovered-from another story, surface the link.)_

## Problem

_(What specific problem does this story solve? Concrete; the reader
should be able to verify completion without re-reading the epic.)_

## Design

### Approach

_(How will this be implemented? Reference HUGs that constrain the
implementation choice; cite alternatives only when they shaped the
final pick.)_

### Changes

| File | Change |
|------|--------|
| `path/to/file` | _(add / modify / extract)_ |
| `path/to/test` | _(add tests for the new behavior)_ |

## Definition of Done

- [x] Test files in res://data/tests/ and user://data/tests/
- [x] Test format: name, description, setup, wait, checks
- [x] Check types: expect_gt/lt/eq/contains
- [x] Extract: parse RCON response to a named value
- [x] test_runner.gd loader + validation
- [x] Convert existing bash scenarios to JSON


## Testing

### Unit / fixture tests

- [ ] _(Specific case.)_
- [ ] _(Edge case.)_

### Integration

- [ ] _(Scenario.)_

## Out of scope

- _(Things deliberately deferred to a later story. Be explicit — the
  reader should know what's *not* changing.)_

## Implementation Notes

_(Fill in during / after implementation. Capture what diverged from
the original design and why — useful for the retrospective + for
operators reading this story in a year.)_

### What Changed

_(Actual implementation. May differ from § Design above.)_

### Files Modified

- `path/to/file` — _(what changed)_

### Gotchas

_(Anything surprising or worth noting for future readers.)_


## TUMU Provenance

- **Source:** docs/epics/EPIC_ingame_console.md Story 2
- **Shipped in:** 0.10.0
- **History:** JSON test format with setup, wait, and typed checks, loaded and validated by test_runner.gd.

## Status notes

- 2026-06-07: Closed with --force; 3/9 DoD boxes unchecked. Reason: historical: shipped in TUMU 0.10.0
