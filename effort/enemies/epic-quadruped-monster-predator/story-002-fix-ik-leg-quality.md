---
xid: STO-ENMY-002
parent: ./epic.md
kind: story
effort: enmy
status: open
date: 2026-06-07
depends-on: []
bd-id: mdes-cqo
---

# Fix IK Leg Quality

## Summary

Stop legs from stretching, hovering, or splaying by re-planting feet after transitions and validating planted feet against solid surfaces.

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

- [ ] After every state transition, force feet to re-plant at floor level below hips
- [ ] Validate each planted foot is on a solid surface every N frames; replant if not
- [ ] Reduce max horizontal foot-to-hip distance to 30px
- [ ] Replant all feet immediately when body Y changes rapidly
- [ ] Benchmark: IK score avg < 20, peak < 100


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

- **Source:** docs/EPIC_quadruped_monster.md Story 2
- **Shipped in:** n/a
- **History:** Stop legs from stretching, hovering, or splaying by re-planting feet after transitions and validating planted feet against solid surfaces.
