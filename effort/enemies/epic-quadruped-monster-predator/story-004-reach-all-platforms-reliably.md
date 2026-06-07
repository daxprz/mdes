---
xid: STO-ENMY-004
parent: ./epic.md
kind: story
effort: enmy
status: in-progress
date: 2026-06-07
depends-on: []
bd-id: mdes-yl1
---

# Reach All Platforms Reliably

## Summary

Raise leap hit rate to 10/10 by fixing trajectory accuracy, landing correction, and launch-position velocity adjustment. Cross-platform gap detection and bounded leaps landed in v0.10.0.

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

- [ ] Add post-leap floor detection — retry if not on target platform
- [ ] Increase flight time range for more arc options
- [ ] Adjust velocity vector when launch position differs from planned
- [ ] Add landing correction — nudge onto platform within 30px of edge
- [ ] Score arrival accuracy per scenario


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

- **Source:** docs/EPIC_quadruped_monster.md Story 4
- **Shipped in:** v0.10.0
- **History:** Raise leap hit rate to 10/10 by fixing trajectory accuracy, landing correction, and launch-position velocity adjustment. Cross-platform gap detection and bounded leaps landed in v0.10.0.
