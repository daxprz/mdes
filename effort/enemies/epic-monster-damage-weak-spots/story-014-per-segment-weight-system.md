---
xid: STO-ENMY-014
parent: ./epic.md
kind: story
effort: enmy
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-0xn
shipped: 2026-06-07
tasks: 11
complete: 8
---

# Per-Segment Weight System

## Summary

Distribute weight across the skeleton (total ~193) so localized attach forces produce different effects, with force propagation, gravity reduction, and RCON inspection.

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

- [x] SEGMENT_WEIGHTS dict per body part
- [x] Forces divided by local segment weight in _apply_attach_forces()
- [x] Force propagation through skeleton chains with attenuation
- [x] Gravity reduced when upward force > 50% body weight (cap -120)
- [x] Head balloons tilt spine[0] upward
- [x] RCON weight command
- [x] RCON attach balloon <point> command
- [x] RCON detach <point> command


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

- **Source:** docs/epics/EPIC_monster_damage_and_weak_spots.md Story 4
- **Shipped in:** v0.9.18
- **History:** Distribute weight across the skeleton (total ~193) so localized attach forces produce different effects, with force propagation, gravity reduction, and RCON inspection.

## Status notes

- 2026-06-07: Closed with --force; 3/11 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.18
