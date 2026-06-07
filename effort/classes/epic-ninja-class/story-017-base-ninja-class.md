---
xid: STO-CLS-017
parent: ./epic.md
kind: story
effort: cls
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-o11
shipped: 2026-06-07
tasks: 10
complete: 7
---

# Base Ninja Class

## Summary

Adds NINJA with high-speed stats, sprites, and its full aerial kit including triple jump.

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

- [x] Add NINJA to CharacterClass enum + stats (85 HP, 70 mana, 140 speed, 1.5 mana regen)
- [x] Create ninja topdown + side spritesheets
- [x] Basic attack: 3 fast sequential slices
- [x] Special: dive kick (fast downward kick, bounces on hit)
- [x] Charge attack: meteor strike (charge in air, slam down with scaling damage/radius)
- [x] Circle ability: air dash / item pickup (dash through air + pull nearby items)
- [x] Passive: triple jump (3 jumps before needing ground)


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

- **Source:** BACKLOG.md Story 20.1
- **Shipped in:** v0.9.5
- **History:** Adds NINJA with high-speed stats, sprites, and its full aerial kit including triple jump.

## Status notes

- 2026-06-07: Closed with --force; 3/10 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.5
