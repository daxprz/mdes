---
xid: STO-MECH-030
parent: ./epic.md
kind: story
effort: mech
status: in-progress
date: 2026-06-07
depends-on: []
bd-id: mdes-pb4
---

# Tether State Machine

## Summary

Extends the grapple FSM with tether windup/thrown/active states triggered by L2, a 5-slot tether inventory, and player drop on second-hook connect. Self-tether remains unimplemented.

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

- [x] Add tether states: TETHER_WINDUP, TETHER_THROWN, TETHER_ACTIVE
- [x] CONNECTED/SWINGING + L2 hold -> TETHER_WINDUP at anchor A
- [x] L2 release in TETHER_WINDUP -> TETHER_THROWN from anchor A
- [x] Second hook uses primary hook physics (gravity, drag, raycast)
- [x] Second hook connect -> TETHER_ACTIVE: player detaches, rope persists
- [x] Store tether data (anchor A, anchor B, target length)
- [x] Move existing L2 boost/shrink to a different binding
- [x] Tether inventory: max 5 active tethers per player
- [x] Severed tethers auto-reclaimed, freeing a slot
- [x] Player drops from rope on second-hook connect; rope becomes standalone
- [ ] Self-tether: anchor B = player when aimed at nothing / cancel


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

- **Source:** EPIC_dual_grapple_tether.md Story 1
- **Shipped in:** v0.9.18
- **History:** Extends the grapple FSM with tether windup/thrown/active states triggered by L2, a 5-slot tether inventory, and player drop on second-hook connect. Self-tether remains unimplemented.
