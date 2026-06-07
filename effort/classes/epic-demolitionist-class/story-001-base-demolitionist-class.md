---
xid: STO-CLS-001
parent: ./epic.md
kind: story
effort: cls
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-h10
shipped: 2026-06-07
tasks: 8
complete: 5
---

# Base Demolitionist Class

## Summary

Adds DEMOLITIONIST with stats, sprites, an arcing bomb basic attack, and the Big Bomb special.

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

- [x] Add DEMOLITIONIST to CharacterClass enum + stats (100 HP, 100 mana, 105 speed, 1.5 mana regen)
- [x] Create demolitionist topdown + side spritesheets
- [x] Basic attack: throw bomb (arcs with gravity, bounces once, explodes after 1.5s or on enemy contact)
- [x] Bomb explosion: 25 damage, 60px radius, knockback, VFX + screen shake
- [x] Special: Big Bomb (costs 40 mana, 50 damage, 90px radius, bigger VFX)


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

- **Source:** BACKLOG.md Story 9.1; docs/design/new_classes.md
- **Shipped in:** v0.9.5
- **History:** Adds DEMOLITIONIST with stats, sprites, an arcing bomb basic attack, and the Big Bomb special.

## Status notes

- 2026-06-07: Closed with --force; 3/8 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.5
