---
xid: STO-ENMY-023
parent: ./epic.md
kind: story
effort: enmy
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-zm0
shipped: 2026-06-07
tasks: 7
complete: 4
---

# Leap Planning & Precog

## Summary

Scale all leap trajectory, body clearance, and precog pathfinding dimensions; keep precog grid world-space.

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

- [x] Scale LEAP_BODY_RADIUS at point of use
- [x] Scale LEAP_STRIKE_REACH, LEAP_RANGE, LEAP_LAUNCH_SPEED, HOP_UP_MAX_HEIGHT
- [x] Scale precog entity-platform matching tolerances
- [x] Keep PRECOG_GRID_SPACING world-space


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

- **Source:** docs/epics/EPIC_monster_scaling.md Story 4
- **Shipped in:** v0.10.1
- **History:** Scale all leap trajectory, body clearance, and precog pathfinding dimensions; keep precog grid world-space.

## Status notes

- 2026-06-07: Closed with --force; 3/7 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.10.1
