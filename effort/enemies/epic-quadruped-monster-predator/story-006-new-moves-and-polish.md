---
xid: STO-ENMY-006
parent: ./epic.md
kind: story
effort: enmy
status: in-progress
date: 2026-06-07
depends-on: []
bd-id: mdes-eoj
---

# New Moves & Polish

## Summary

Future moves and polish: wall-cling, pounce impact, death animation, audio, and health bar. Chain daze and connected hop-up landed in the v0.10.x line.

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

- [x] Standing hop-up for short climbs (< 140px)
- [ ] Wall-cling: grab cave walls during multi-hop routes
- [ ] Pounce landing impact: area damage + screen shake
- [ ] Death animation: part-by-part collapse with physics
- [ ] Audio: growl, footsteps, leap whoosh, bite crunch
- [ ] Health bar rendering


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

- **Source:** docs/EPIC_quadruped_monster.md Story 6
- **Shipped in:** v0.10.18
- **History:** Future moves and polish: wall-cling, pounce impact, death animation, audio, and health bar. Chain daze and connected hop-up landed in the v0.10.x line.
