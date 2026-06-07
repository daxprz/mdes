---
xid: STO-MECH-004
parent: ./epic.md
kind: story
effort: mech
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-ovj
shipped: 2026-06-07
tasks: 13
complete: 10
---

# New Obstacles - Wave 2

## Summary

A candy-themed obstacle set adding movement-altering and timed hazards across the towers.

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

- [x] Rotating saw blades on chains (circle around an anchor point)
- [x] Icing waterfall (slippery vertical stream, pushes players down if they enter)
- [x] Candy cane poles (bounce pads - launch players upward when touched)
- [x] Chocolate lava rising floor (slowly rises from bottom, forces players to climb faster)
- [x] Sugar crystal barriers (breakable walls that block paths, require X hits)
- [x] Frosting slides (angled platforms that are slippery, players slide down)
- [x] Cookie crumble floors (entire sections that collapse after a timer once stepped on)
- [x] Caramel sticky zones (slow player movement to 30%, must jump through)
- [x] Popcorn geysers (periodic upward blast that launches players + enemies high)
- [x] Sprinkle mines (hidden on platforms, explode when stepped on, 15 dmg + knockback)


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

- **Source:** BACKLOG Story 7.3
- **Shipped in:** v0.9.4
- **History:** A candy-themed obstacle set adding movement-altering and timed hazards across the towers.

## Status notes

- 2026-06-07: Closed with --force; 3/13 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.4
