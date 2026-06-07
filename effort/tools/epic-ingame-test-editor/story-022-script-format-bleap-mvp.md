---
xid: STO-TOOLS-022
parent: ./epic.md
kind: story
effort: tools
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-96aq
shipped: 2026-06-07
tasks: 7
complete: 4
---

# Script Format + bleap + Test Commands (MVP)

## Summary

Tests as RCON scripts with a bleap bounded-leap builder and testload/show/edit/run/save commands.

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

- [x] Add bleap command family to RCON
- [x] Add script-format support to test runner
- [x] Add testload/testshow/testedit/testinsert/testdelete/testrun/testsave
- [x] Convert verify_leap_graph_P0_P1.json to script format


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

- **Source:** docs/epics/EPIC_test_editor.md Story 1
- **Shipped in:** 0.10.0
- **History:** Tests as RCON scripts with a bleap bounded-leap builder and testload/show/edit/run/save commands.

## Status notes

- 2026-06-07: Closed with --force; 3/7 DoD boxes unchecked. Reason: historical: shipped in TUMU 0.10.0
