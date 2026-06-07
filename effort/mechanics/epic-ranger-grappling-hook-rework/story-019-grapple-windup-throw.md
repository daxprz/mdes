---
xid: STO-MECH-019
parent: ./epic.md
kind: story
effort: mech
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-eiq
shipped: 2026-06-07
tasks: 7
complete: 4
---

# Grapple Windup & Throw

## Summary

L1 spins the hook in a circle with thumbstick aim, releasing into a gravity-arced throw, with full movement preserved during windup.

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

- [x] L1/LB initiates grapple. Hook swings in a circle (14-35 rad/s)
- [x] Either thumbstick aims (right priority). Dotted arrow shows direction.
- [x] Release L1 throws at 4000-10000 px/s with gravity arc. Max range 900px.
- [x] Full movement during windup (walk, jump, gravity all work)


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

- **Source:** BACKLOG Story 30.1; grappling_hook_physics.md Phases 1-2
- **Shipped in:** v0.9.4
- **History:** L1 spins the hook in a circle with thumbstick aim, releasing into a gravity-arced throw, with full movement preserved during windup.

## Status notes

- 2026-06-07: Closed with --force; 3/7 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.4
