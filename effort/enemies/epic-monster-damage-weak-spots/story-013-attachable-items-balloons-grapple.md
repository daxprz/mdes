---
xid: STO-ENMY-013
parent: ./epic.md
kind: story
effort: enmy
status: in-progress
date: 2026-06-07
depends-on: []
bd-id: mdes-att
---

# Attachable Items — Balloons & Grapple

## Summary

Balloon darts attach to specific body points and exert weight-aware forces; grapple hook attachment deferred until a grapple projectile exists.

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

- [x] Balloon dart checks attachment points before body center; anchors string
- [x] get_attach_force() returns inflation-based upward force at attach point
- [ ] Grapple hook attachment with pull force (deferred — no grapple projectile)
- [x] Multiple items per point with stacked forces and cleanup


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

- **Source:** docs/epics/EPIC_monster_damage_and_weak_spots.md Story 3
- **Shipped in:** v0.9.18
- **History:** Balloon darts attach to specific body points and exert weight-aware forces; grapple hook attachment deferred until a grapple projectile exists.
