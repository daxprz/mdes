---
xid: STO-ENMY-003
parent: ./epic.md
kind: story
effort: enmy
status: open
date: 2026-06-07
depends-on: []
bd-id: mdes-j73
---

# Improve Debug Draw Performance

## Summary

Lift min FPS with debug on from 14 to over 30 by throttling and caching debug rendering.

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

- [ ] Only redraw debug info every 3rd frame
- [ ] Cache platform bar geometry instead of recomputing per frame
- [ ] Reduce text labels into fewer draw_string calls
- [ ] Skip precog visualization when not in PRECOGNITION state


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

- **Source:** docs/EPIC_quadruped_monster.md Story 3
- **Shipped in:** n/a
- **History:** Lift min FPS with debug on from 14 to over 30 by throttling and caching debug rendering.
