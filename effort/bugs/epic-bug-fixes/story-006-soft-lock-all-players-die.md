---
xid: STO-BUG-006
parent: ./epic.md
kind: story
effort: bug
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-ne4
shipped: 2026-06-07
tasks: 4
complete: 1
---

# Soft-Lock When All Players Die

## Summary

Fixed the soft-lock when all players died with no revive path; PlayerManager now emits all_players_dead and GameManager shows an overlay then auto-restarts the scene with players revived (commit 2026-03-14: auto restart).

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

- [x] BUG: Game soft-locks when all players die (no revive possible) — fix: all_players_dead signal + auto-restart with revive


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

- **Source:** BACKLOG Story 2.8
- **Shipped in:** n/a
- **History:** Fixed the soft-lock when all players died with no revive path; PlayerManager now emits all_players_dead and GameManager shows an overlay then auto-restarts the scene with players revived (commit 2026-03-14: auto restart).

## Status notes

- 2026-06-07: Closed with --force; 3/4 DoD boxes unchecked. Reason: historical: shipped in TUMU
