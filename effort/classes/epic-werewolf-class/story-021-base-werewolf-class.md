---
xid: STO-CLS-021
parent: ./epic.md
kind: story
effort: cls
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-9oa
shipped: 2026-06-07
tasks: 9
complete: 6
---

# Base Werewolf Class

## Summary

Adds WEREWOLF with high-HP brawler stats, sprites, triple claw combo, roar push, pounce charge, and frenzy.

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

- [x] Add WEREWOLF to CharacterClass enum + stats (200 HP, 40 mana, 120 speed, 0.5 mana regen)
- [x] Create werewolf topdown + side spritesheets
- [x] Basic attack: triple claw slash (3-hit combo, 8 blood drops per slash)
- [x] Special: roar push (30-degree arc, 250px range, weight-based push)
- [x] Charge attack: pounce (charge and leap, damage/distance scale with charge)
- [x] Circle ability: frenzy (8s duration, 35s cooldown, boosted attack/move speed)


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

- **Source:** BACKLOG.md Story 23.1
- **Shipped in:** v0.9.5
- **History:** Adds WEREWOLF with high-HP brawler stats, sprites, triple claw combo, roar push, pounce charge, and frenzy.

## Status notes

- 2026-06-07: Closed with --force; 3/9 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.5
