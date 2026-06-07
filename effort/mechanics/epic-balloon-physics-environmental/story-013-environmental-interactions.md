---
xid: STO-MECH-013
parent: ./epic.md
kind: story
effort: mech
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-57j
shipped: 2026-06-07
tasks: 8
complete: 5
---

# Environmental Interactions

## Summary

Cross-system reactions among lava, gas, fire, and balloons, plus AI-targeting group cleanup for dead and stealthed players.

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

- [x] Rising chocolate lava kills enemies instantly
- [x] Rising chocolate lava ignites H2 gas on contact
- [x] Mage fireballs are fire type - explode balloons on contact
- [x] Dead players removed from "players" group (enemies stop targeting)
- [x] Stealthed rogue removed from "players" group (invisible to enemy AI)


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

- **Source:** BACKLOG Story 25.1
- **Shipped in:** v0.9.4
- **History:** Cross-system reactions among lava, gas, fire, and balloons, plus AI-targeting group cleanup for dead and stealthed players.

## Status notes

- 2026-06-07: Closed with --force; 3/8 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.4
