---
xid: STO-MECH-007
parent: ./epic.md
kind: story
effort: mech
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-k0n
shipped: 2026-06-07
tasks: 9
complete: 6
---

# Melee Ground Pound Improvements

## Summary

Air-charge hover with wiggle and smoke buildup, then a charge-scaled slam with blast radius, damage scaling, and screen shake.

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

- [x] While charging in air: character hovers in place
- [x] Hover wiggle animation (oscillate position +/-2px)
- [x] Smoke/particle VFX builds during hover
- [x] On release: slam down with blast radius proportional to charge (40px min -> 120px max)
- [x] Damage scales: 30 min -> 80 max based on charge
- [x] Screen shake on impact (intensity scales with charge)


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

- **Source:** BACKLOG Story 11.3
- **Shipped in:** v0.9.4
- **History:** Air-charge hover with wiggle and smoke buildup, then a charge-scaled slam with blast radius, damage scaling, and screen shake.

## Status notes

- 2026-06-07: Closed with --force; 3/9 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.4
