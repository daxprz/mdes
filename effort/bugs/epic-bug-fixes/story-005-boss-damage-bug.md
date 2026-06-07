---
xid: STO-BUG-005
parent: ./epic.md
kind: story
effort: bug
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-boj
shipped: 2026-06-07
tasks: 6
complete: 3
---

# Boss Damage Bug

## Summary

Players could not damage the Giant Muffin because bosses had no collision_layer set (defaulted to world) and were invisible to attack masks. Fix put all 4 bosses on collision_layer 8 and in the enemies/bosses groups (commit 2026-03-14: bosses now on collision layer 8).

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

- [x] BUG: Players cannot damage the final boss (Giant Muffin) - attacks don't register
- [x] Investigate boss collision layers vs player attack area masks
- [x] Verify boss is in "enemies"/"bosses" group and take_damage is callable


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

- **Source:** BACKLOG Story 2.4
- **Shipped in:** n/a
- **History:** Players could not damage the Giant Muffin because bosses had no collision_layer set (defaulted to world) and were invisible to attack masks. Fix put all 4 bosses on collision_layer 8 and in the enemies/bosses groups (commit 2026-03-14: bosses now on collision layer 8).

## Status notes

- 2026-06-07: Closed with --force; 3/6 DoD boxes unchecked. Reason: historical: shipped in TUMU
