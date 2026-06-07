---
xid: STO-MECH-021
parent: ./epic.md
kind: story
effort: mech
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-c41
shipped: 2026-06-07
tasks: 6
complete: 3
---

# Pendulum Swing Physics

## Summary

Full pendulum swing with momentum/brake input and rope-length control, catenary rope sag, and launch immunity preserving momentum through freefall.

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

- [x] Full pendulum physics with momentum/brake input and rope length adjustment
- [x] Rope rendered with catenary sag proportional to slack
- [x] Launch immunity preserves momentum through freefall until landing


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

- **Source:** BACKLOG Story 30.3; grappling_hook_physics.md Phase 4
- **Shipped in:** v0.10.79
- **History:** Full pendulum swing with momentum/brake input and rope-length control, catenary rope sag, and launch immunity preserving momentum through freefall.

## Status notes

- 2026-06-07: Closed with --force; 3/6 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.10.79
