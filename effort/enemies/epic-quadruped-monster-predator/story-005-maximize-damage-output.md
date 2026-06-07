---
xid: STO-ENMY-005
parent: ./epic.md
kind: story
effort: enmy
status: in-progress
date: 2026-06-07
depends-on: []
bd-id: mdes-cj8
---

# Maximize Damage Output

## Summary

Push damage output above 1000 via aggressive chase/bite after reaching target and a pounce mechanic. Aerial ballistic strike on the final precog hop landed in the v0.10.x line.

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

- [x] After reaching target's platform, enter chase+bite mode (no more precog)
- [ ] Increase bite damage check frequency
- [x] Add pounce mechanic — instant damage when landing within 60px of target
- [ ] Trigger sprint slash more aggressively on same-level scenarios
- [ ] Track damage-per-second as a baseline metric


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

- **Source:** docs/EPIC_quadruped_monster.md Story 5
- **Shipped in:** v0.10.15
- **History:** Push damage output above 1000 via aggressive chase/bite after reaching target and a pounce mechanic. Aerial ballistic strike on the final precog hop landed in the v0.10.x line.
